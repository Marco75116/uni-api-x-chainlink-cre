// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RebalancerVault.sol";
import "../src/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";

contract RebalancerVaultTest is Test {
    // Polygon mainnet addresses
    address constant POOL = 0x254aa3A898071D6A2dA0DB11dA73b02B4646078F; // DAI/USDT0 0.01%
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNIVERSAL_ROUTER = 0x1095692A6237d83C6a72F3F5eFEdb9A670C49223; // Uniswap Universal Router on Polygon
    address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant USDT0 = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;

    RebalancerVault vault;
    address owner;
    address operator;

    function setUp() public {
        // Fork Polygon mainnet — set POLYGON_RPC_URL or use --fork-url
        string memory rpcUrl = vm.envOr("POLYGON_RPC_URL", string("https://polygon-bor-rpc.publicnode.com"));
        vm.createSelectFork(rpcUrl);

        owner = makeAddr("owner");
        operator = address(this); // test contract is the deployer, so becomes operator

        vault = new RebalancerVault(owner, POOL);
    }

    // ───────── Constructor Tests ─────────

    function test_constructor_setsState() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.operator(), address(this));
        assertEq(address(vault.pool()), POOL);
        assertEq(address(vault.positionManager()), POSITION_MANAGER);
        assertEq(vault.universalRouter(), UNIVERSAL_ROUTER);
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        new RebalancerVault(address(0), POOL);
    }

    function test_constructor_revertsOnZeroPool() public {
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        new RebalancerVault(owner, address(0));
    }

    function test_constructor_setsApprovals() public view {
        // Check Universal Router approvals
        assertEq(IERC20Minimal(DAI).allowance(address(vault), UNIVERSAL_ROUTER), type(uint256).max);
        assertEq(IERC20Minimal(USDT0).allowance(address(vault), UNIVERSAL_ROUTER), type(uint256).max);
        // Check Position Manager approvals
        assertEq(IERC20Minimal(DAI).allowance(address(vault), POSITION_MANAGER), type(uint256).max);
        assertEq(IERC20Minimal(USDT0).allowance(address(vault), POSITION_MANAGER), type(uint256).max);
    }

    // ───────── Access Control Tests ─────────

    function test_setOperator_byOwner() public {
        address newOperator = makeAddr("newOperator");
        vm.prank(owner);
        vault.setOperator(newOperator);
        assertEq(vault.operator(), newOperator);
    }

    function test_setOperator_revertsIfNotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.setOperator(makeAddr("newOp"));
    }

    function test_setOperator_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.setOperator(address(0));
    }

    // ───────── View Functions (live pool) ─────────

    function test_getCurrentTick_returnsValidTick() public view {
        int24 tick = vault.getCurrentTick();
        // DAI/USDT0 stablecoin pair — tick should be near -276324 (price ≈ 1:1 adjusted for decimals)
        assertGt(tick, -300000);
        assertLt(tick, -250000);
    }

    function test_getPoolState_returnsNonZeroPrice() public view {
        (uint160 sqrtPriceX96, int24 tick) = vault.getPoolState();
        assertGt(sqrtPriceX96, 0);
        assertGt(tick, -300000);
        assertLt(tick, -250000);
    }

    // ───────── Position Lifecycle ─────────

    function test_mintPositionAndQuery() public {
        // Mint a position directly via the position manager,
        // then transfer the NFT to the vault
        uint256 daiAmount = 100e18;
        uint256 usdtAmount = 100e6;

        // Mint tokens via deal
        deal(DAI, address(this), daiAmount);
        deal(USDT0, address(this), usdtAmount);

        // Approve position manager
        IERC20Minimal(DAI).approve(POSITION_MANAGER, daiAmount);
        IERC20Minimal(USDT0).approve(POSITION_MANAGER, usdtAmount);

        // Get current tick to set a range around it
        int24 currentTick = vault.getCurrentTick();
        // Tick spacing is 1 for 0.01% fee tier
        int24 tickLower = currentTick - 100;
        int24 tickUpper = currentTick + 100;

        // Mint position
        (uint256 tokenId,,,) = INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: DAI,
                token1: USDT0,
                fee: 100,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: daiAmount,
                amount1Desired: usdtAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        // Transfer NFT to vault
        INonfungiblePositionManager(POSITION_MANAGER).safeTransferFrom(
            address(this), address(vault), tokenId
        );

        // Set tokenId on vault (needs a setter or we set storage directly)
        // Since there's no public setter, use vm.store
        // tokenId is at storage slot 2 (owner=0, operator=1, tokenId=2; immutables/constants don't use storage)
        vm.store(address(vault), bytes32(uint256(2)), bytes32(tokenId));

        // Query position
        (
            address token0,
            address token1,
            uint24 fee,
            int24 posTickLower,
            int24 posTickUpper,
            uint128 liquidity
        ) = vault.getPosition();

        assertEq(token0, DAI);
        assertEq(token1, USDT0);
        assertEq(fee, 100);
        assertEq(posTickLower, tickLower);
        assertEq(posTickUpper, tickUpper);
        assertGt(liquidity, 0);
    }

    function test_isOutOfRange_falseWhenInRange() public {
        // Mint a wide-range position so the tick is in range
        _mintAndTransferPosition(-280000, -270000);

        bool outOfRange = vault.isOutOfRange();
        assertFalse(outOfRange);
    }

    function test_isOutOfRange_trueWhenOutOfRange() public {
        // Mint a position far from current tick
        _mintAndTransferPosition(-290000, -289000);

        bool outOfRange = vault.isOutOfRange();
        assertTrue(outOfRange);
    }

    // ───────── ERC721 Receiver ─────────

    function test_onERC721Received_returnsSelector() public view {
        bytes4 result = vault.onERC721Received(address(0), address(0), 0, "");
        assertEq(result, vault.onERC721Received.selector);
    }

    // ───────── Helpers ─────────

    function _mintAndTransferPosition(int24 tickLower, int24 tickUpper) internal {
        uint256 daiAmount = 100e18;
        uint256 usdtAmount = 100e6;

        deal(DAI, address(this), daiAmount);
        deal(USDT0, address(this), usdtAmount);

        IERC20Minimal(DAI).approve(POSITION_MANAGER, daiAmount);
        IERC20Minimal(USDT0).approve(POSITION_MANAGER, usdtAmount);

        (uint256 tokenId,,,) = INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: DAI,
                token1: USDT0,
                fee: 100,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: daiAmount,
                amount1Desired: usdtAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        INonfungiblePositionManager(POSITION_MANAGER).safeTransferFrom(
            address(this), address(vault), tokenId
        );

        vm.store(address(vault), bytes32(uint256(2)), bytes32(tokenId));
    }

    /// @notice Required for ERC721 safeTransferFrom to work when this contract is the sender
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
