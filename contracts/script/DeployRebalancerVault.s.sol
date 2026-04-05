// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/RebalancerVault.sol";

contract DeployRebalancerVault is Script {
    // Polygon NonfungiblePositionManager
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function run() external {
        address pool = vm.envAddress("POOL_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast();

        RebalancerVault vault = new RebalancerVault(owner, pool, POSITION_MANAGER);

        vm.stopBroadcast();

        console.log("RebalancerVault deployed at:", address(vault));
        console.log("Pool:", pool);
        console.log("Owner:", owner);
        console.log("Operator (deployer):", msg.sender);
    }
}
