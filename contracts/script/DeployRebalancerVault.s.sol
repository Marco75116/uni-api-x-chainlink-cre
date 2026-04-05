// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/RebalancerVault.sol";

contract DeployRebalancerVault is Script {
    function run() external {
        address pool = vm.envAddress("POOL_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast();

        RebalancerVault vault = new RebalancerVault(owner, pool);

        vm.stopBroadcast();

        console.log("RebalancerVault deployed at:", address(vault));
        console.log("Pool:", pool);
        console.log("Owner:", owner);
        console.log("Operator (deployer):", msg.sender);
    }
}
