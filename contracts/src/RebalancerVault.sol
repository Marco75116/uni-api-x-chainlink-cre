// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/INonfungiblePositionManager.sol";

contract RebalancerVault {
    using SafeERC20 for IERC20;

    // Polygon mainnet addresses
    INonfungiblePositionManager public constant positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant universalRouter = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;

    address public owner;
    address public operator;

    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    uint256 public tokenId; // The NFT position owned by this vault

    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event Rebalanced(
        uint256 oldTokenId,
        uint256 newTokenId,
        int24 newTickLower,
        int24 newTickUpper,
        uint128 newLiquidity
    );

    error NotOwner();
    error NotOperator();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidToken();
    error SwapFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address _owner, address _pool) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();

        owner = _owner;
        operator = msg.sender;
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(IUniswapV3Pool(_pool).token0());
        token1 = IERC20(IUniswapV3Pool(_pool).token1());

        // Approve Universal Router to spend both pool tokens (for swaps via Trading API)
        IERC20(IUniswapV3Pool(_pool).token0()).approve(universalRouter, type(uint256).max);
        IERC20(IUniswapV3Pool(_pool).token1()).approve(universalRouter, type(uint256).max);

        // Approve NonfungiblePositionManager to spend both tokens (for minting positions)
        IERC20(IUniswapV3Pool(_pool).token0()).approve(address(positionManager), type(uint256).max);
        IERC20(IUniswapV3Pool(_pool).token1()).approve(address(positionManager), type(uint256).max);
    }

    // ########## Admin Functions ##########

    /// @notice Update the operator address
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
    }

    /// @notice Deposit token0 or token1 into the vault
    /// @param token Address of the token to deposit (must be pool's token0 or token1)
    /// @param amount Amount of tokens to deposit
    function deposit(address token, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (token != address(token0) && token != address(token1)) revert InvalidToken();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(token, amount);
    }

    /// @notice Withdraw token0 or token1 from the vault
    /// @param token Address of the token to withdraw (must be pool's token0 or token1)
    /// @param amount Amount of tokens to withdraw
    function withdraw(address token, uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (token != address(token0) && token != address(token1)) revert InvalidToken();

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(token, msg.sender, amount);
    }

    /// @notice ERC721 receiver so the vault can receive NFT positions
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Remove all liquidity from the current position and collect all fees
    /// @return amount0 Total token0 received (liquidity + fees)
    /// @return amount1 Total token1 received (liquidity + fees)
    function removeLiquidityAndCollectFees() external onlyOwner returns (uint256 amount0, uint256 amount1) {
        uint256 currentTokenId = tokenId;

        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(currentTokenId);

        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: currentTokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        }

        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: currentTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    // ########## Rebalance ##########

    /// @notice Rebalance the LP position: withdraw old, swap, mint centered on current tick
    /// @param swapData Calldata from Uniswap Trading API to execute via Universal Router
    function rebalance(bytes calldata swapData) external onlyOperator {
        uint256 oldTokenId = tokenId;

        // Get old position's tick range to compute width
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) =
            positionManager.positions(oldTokenId);

        // Step 1: Withdraw all liquidity + collect fees
        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: oldTokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );
        }

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: oldTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Step 2: Execute swap via Universal Router using Trading API calldata
        if (swapData.length > 0) {
            (bool success, ) = universalRouter.call(swapData);
            if (!success) revert SwapFailed();
        }

        // Step 3: Compute centered tick range and mint new position
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();
        int24 halfWidth = (tickUpper - tickLower) / 2;

        int24 newTickLower = ((currentTick - halfWidth) / tickSpacing) * tickSpacing;
        int24 newTickUpper = ((currentTick + halfWidth) / tickSpacing) * tickSpacing;

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        (uint256 newTokenId, uint128 newLiquidity, , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: pool.fee(),
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: balance0,
                amount1Desired: balance1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        tokenId = newTokenId;

        emit Rebalanced(
            oldTokenId,
            newTokenId,
            newTickLower,
            newTickUpper,
            newLiquidity
        );
    }

    // ########## View Functions ##########

    /// @notice Returns the current tick of the pool
    function getCurrentTick() external view returns (int24 tick) {
        (, tick,,,,,) = pool.slot0();
    }

    /// @notice Returns the current sqrtPriceX96 and tick of the pool
    function getPoolState()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        (sqrtPriceX96, tick,,,,,) = pool.slot0();
    }

    /// @notice Returns the position details for the vault's NFT
    function getPosition()
        external
        view
        returns (
            address _token0,
            address _token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (
            ,
            ,
            _token0,
            _token1,
            fee,
            tickLower,
            tickUpper,
            liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);
    }

    /// @notice Check if the current position is out of range
    function isOutOfRange() external view returns (bool) {
        (, int24 tick,,,,,) = pool.slot0();
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);
        return tick < tickLower || tick >= tickUpper;
    }
}
