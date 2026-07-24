// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZunivoScheduledSends} from "../src/ZunivoScheduledSends.sol";

/// export DEPLOYER_PK=0x… ; export SCHED_TREASURY=0x… ; SCHED_FEE_BPS=0
contract DeployScheduled is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address treasury = vm.envAddress("SCHED_TREASURY");
        uint16 fee = uint16(vm.envUint("SCHED_FEE_BPS"));

        vm.startBroadcast(pk);
        ZunivoScheduledSends sched = new ZunivoScheduledSends(treasury, fee);
        vm.stopBroadcast();

        console2.log("ZunivoScheduledSends deployed at:", address(sched));
        console2.log("Treasury:", sched.treasury());
        console2.log("Fee (bps):", sched.feeBps());
        console2.log("Explorer: https://testnet.arcscan.app/address/%s", address(sched));
    }
}
