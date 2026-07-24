// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ZunivoNames} from "../src/ZunivoNames.sol";

/// Usage:
///   export DEPLOYER_PK=0x...
///   export NAMES_TREASURY=0x<fee wallet>
///   export NAMES_MINT_PRICE=1000000000000000000   # 1 USDC (18d native)
///   forge script script/DeployNames.s.sol:DeployNames --rpc-url arc_testnet --broadcast
contract DeployNames is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address treasury = vm.envAddress("NAMES_TREASURY");
        uint256 price = vm.envUint("NAMES_MINT_PRICE");

        vm.startBroadcast(pk);
        ZunivoNames names = new ZunivoNames(treasury, price);
        vm.stopBroadcast();

        console2.log("ZunivoNames deployed at:", address(names));
        console2.log("Treasury:", names.treasury());
        console2.log("Mint price (wei):", names.mintPrice());
        console2.log("Explorer: https://testnet.arcscan.app/address/%s", address(names));
    }
}
