// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZunivoAgentRecords} from "../src/ZunivoAgentRecords.sol";

/// @notice Deploys ZunivoAgentRecords bound to the live ZunivoNames registry.
///
/// Usage:
///   export DEPLOYER_PK=0x...
///   export NAMES_ADDRESS=0x244e0c8bE1Ed59636901F98920413d414B158cc5
///   forge script script/DeployRecords.s.sol:DeployRecords --rpc-url arc_testnet --broadcast
contract DeployRecords is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address namesAddr = vm.envAddress("NAMES_ADDRESS");

        vm.startBroadcast(pk);
        ZunivoAgentRecords records = new ZunivoAgentRecords(namesAddr);
        vm.stopBroadcast();

        console2.log("ZunivoAgentRecords deployed at:", address(records));
        console2.log("Bound to ZunivoNames:", address(records.names()));
        console2.log("Explorer: https://testnet.arcscan.app/address/%s", address(records));
    }
}
