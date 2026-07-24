// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZunivoSplit} from "../src/ZunivoSplit.sol";

/// export DEPLOYER_PK=0x… ; export SPLIT_TREASURY=0x… ; export SPLIT_FEE_BPS=0
contract DeploySplit is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address treasury = vm.envAddress("SPLIT_TREASURY");
        uint16 fee = uint16(vm.envUint("SPLIT_FEE_BPS"));

        vm.startBroadcast(pk);
        ZunivoSplit split = new ZunivoSplit(treasury, fee);
        vm.stopBroadcast();

        console2.log("ZunivoSplit deployed at:", address(split));
        console2.log("Treasury:", split.treasury());
        console2.log("Fee (bps):", split.feeBps());
        console2.log("Explorer: https://testnet.arcscan.app/address/%s", address(split));
    }
}
