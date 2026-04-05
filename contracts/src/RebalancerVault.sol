// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";
import "./interfaces/INonfungiblePositionManager.sol";

contract RebalancerVault {
    // Polygon mainnet addresses
    INonfungiblePositionManager public constant positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public constant universalRouter = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223;

    address public owner;
    address public operator;

    IUniswapV3Pool public pool;
    uint256 public tokenId; // The NFT position owned by this vault

    error NotOwner();
    error NotOperator();
    error ZeroAddress();

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

        // Approve Universal Router to spend both pool tokens (for swaps via Trading API)
        address token0 = IUniswapV3Pool(_pool).token0();
        address token1 = IUniswapV3Pool(_pool).token1();
        IERC20Minimal(token0).approve(universalRouter, type(uint256).max);
        IERC20Minimal(token1).approve(universalRouter, type(uint256).max);

        // Approve NonfungiblePositionManager to spend both tokens (for minting positions)
        IERC20Minimal(token0).approve(address(positionManager), type(uint256).max);
        IERC20Minimal(token1).approve(address(positionManager), type(uint256).max);
    }

    // ########## Admin Functions ##########

    /// @notice Update the operator address
    function setOperator(address _operator) external onlyOwner {
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
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
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (
            ,
            ,
            token0,
            token1,
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
