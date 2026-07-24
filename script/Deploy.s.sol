// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ArcPayRouter} from "../src/ArcPayRouter.sol";

/// @notice Deploys ArcPayRouter to Arc Testnet (Chain ID 5042002).
///
/// Usage (secrets stay in 1Password — inject at runtime, never commit):
///   export DEPLOYER_PK=$(op read "op://<vault>/arc-deployer/private key")
///   export FEE_COLLECTOR=0xYourFeeWallet
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url arc_testnet \
///     --broadcast
///
/// Gas on Arc is paid in native USDC — fund the deployer from
/// https://faucet.circle.com (select Arc Testnet) before broadcasting.
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address feeCollector = vm.envAddress("FEE_COLLECTOR");

        vm.startBroadcast(pk);
        ArcPayRouter router = new ArcPayRouter(feeCollector);
        vm.stopBroadcast();

        console2.log("ArcPayRouter deployed at:", address(router));
        console2.log("Owner:", router.owner());
        console2.log("Fee collector:", router.feeCollector());
        console2.log("Fee (bps):", router.feeBps());
        console2.log("Explorer: https://testnet.arcscan.app/address/%s", address(router));
    }
}
