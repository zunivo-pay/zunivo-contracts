// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ArcPayRouter} from "../src/ArcPayRouter.sol";
import {ZunivoNames} from "../src/ZunivoNames.sol";
import {ZunivoScheduledSends} from "../src/ZunivoScheduledSends.sol";
import {ZunivoSplit} from "../src/ZunivoSplit.sol";
import {ZunivoAgentRecords} from "../src/ZunivoAgentRecords.sol";

/// @title DeployAllV13 — one-shot deploy of the audited v1.3 contract set.
/// @notice Deploys all five in the correct order (Names before AgentRecords,
///         since Records depends on Names.nameEpoch) and prints every address.
///         Same script is reused verbatim at mainnet — only the env vars change.
///
/// Usage (Arc TESTNET dress rehearsal):
///   read -s "PK?deployer key: " && export DEPLOYER_PK="0x${PK#0x}"
///   export TREASURY=0x<your fee/treasury wallet>       # can be your main wallet on testnet
///   export MINT_PRICE=1000000000000000000              # 1 USDC (18d native). 0 = free mint
///   export FEE_BPS=0                                    # keep 0 until pull-payment fee path is exercised
///   forge script script/DeployAllV13.s.sol:DeployAllV13 --rpc-url arc_testnet --broadcast -vv
contract DeployAllV13 is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address treasury = vm.envAddress("TREASURY");
        uint256 mintPrice = vm.envUint("MINT_PRICE");
        uint16 feeBps = uint16(vm.envUint("FEE_BPS"));

        require(treasury != address(0), "TREASURY unset");
        require(feeBps <= 100, "FEE_BPS must be <= 100 (1%)");

        vm.startBroadcast(pk);

        ArcPayRouter router = new ArcPayRouter(treasury);
        ZunivoNames names = new ZunivoNames(treasury, mintPrice);
        ZunivoScheduledSends sched = new ZunivoScheduledSends(treasury, feeBps);
        ZunivoSplit split = new ZunivoSplit(treasury, feeBps);
        ZunivoAgentRecords records = new ZunivoAgentRecords(address(names)); // depends on names

        vm.stopBroadcast();

        // Sanity: Records must point at the Names we just deployed.
        require(address(records.names()) == address(names), "records/names mismatch");

        console2.log("=====================================================");
        console2.log("Zunivo v1.3 deployed (Arc, chainId 5042002)");
        console2.log("  treasury      :", treasury);
        console2.log("  mintPrice(wei):", mintPrice);
        console2.log("  feeBps        :", feeBps);
        console2.log("-----------------------------------------------------");
        console2.log("ArcPayRouter          :", address(router));
        console2.log("ZunivoNames           :", address(names));
        console2.log("ZunivoScheduledSends  :", address(sched));
        console2.log("ZunivoSplit           :", address(split));
        console2.log("ZunivoAgentRecords    :", address(records));
        console2.log("=====================================================");
        console2.log("Front-end / server env to update:");
        console2.log("  VITE_ROUTER_ADDRESS =", address(router));
        console2.log("  VITE_NAMES_ADDRESS  =", address(names));
        console2.log("  VITE_RECORDS_ADDRESS=", address(records));
        console2.log("  (add scheduled/split addresses where your app references them)");
    }
}
