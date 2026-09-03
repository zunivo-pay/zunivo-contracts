// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Test.sol";
import {ZunivoScheduledSends} from "../src/ZunivoScheduledSends.sol";
import {ZunivoSplit} from "../src/ZunivoSplit.sol";

/// A contract that rejects native transfers (no payable receive/fallback).
contract Rejector {}

/// A smart-wallet-style recipient that rejects an unsolicited push but accepts
/// funds through its own intended pull flow (models an AA / passkey account
/// that only credits itself via a known entrypoint).
contract PullWallet {
    ZunivoScheduledSends internal s;
    bool internal pulling;
    constructor(ZunivoScheduledSends _s) { s = _s; }
    function pull() external { pulling = true; s.withdraw(); pulling = false; }
    receive() external payable { require(pulling, "no unsolicited push"); }
}

contract AuditPoC is Test {
    ZunivoScheduledSends sched;
    ZunivoSplit split;
    address treasury = address(0xA11CE);
    address sender = address(0x5E4DEE);

    function setUp() public {
        sched = new ZunivoScheduledSends(treasury, 0);
        split = new ZunivoSplit(treasury, 0);
        vm.deal(sender, 100 ether);
    }

    // H-1 FIXED: a grace=0 committed lock to a non-receiving recipient no longer
    // freezes. release() succeeds (never reverts), funds are credited, and a
    // smart-wallet recipient pulls them out.
    function test_H1_fixed_grace0_nonReceiving_recipient_recoverable() public {
        PullWallet wallet = new PullWallet(sched);
        vm.prank(sender);
        uint256 id = sched.createSend{value: 5 ether}(address(wallet), uint64(block.timestamp + 1 days), 0, bytes32("wage"));

        vm.warp(block.timestamp + 2 days);

        // release no longer reverts — it settles and credits the recipient
        sched.release(id);
        assertEq(sched.withdrawable(address(wallet)), 5 ether, "credited to recipient");

        // the smart wallet pulls its funds — no freeze
        wallet.pull();
        assertEq(address(wallet).balance, 5 ether, "recipient recovered funds");
        assertEq(address(sched).balance, 0, "nothing stranded");
    }

    // H-1 control: a normal EOA still gets a direct push, no withdraw needed.
    function test_H1_control_grace0_EOA_directPush() public {
        address eoa = address(0xE0A);
        vm.prank(sender);
        uint256 id = sched.createSend{value: 5 ether}(eoa, uint64(block.timestamp + 1 days), 0, bytes32("wage"));
        vm.warp(block.timestamp + 2 days);
        sched.release(id);
        assertEq(eoa.balance, 5 ether, "EOA paid directly");
        assertEq(sched.withdrawable(eoa), 0, "no pull balance needed");
    }

    // M-1 FIXED: one reverting payee no longer bricks the split. pay() succeeds,
    // the good payee pulls, only the bad payee's own pull fails.
    function test_M1_fixed_one_bad_payee_does_not_brick_split() public {
        Rejector bad = new Rejector();
        address good = address(0x6001);
        address[] memory payees = new address[](2);
        payees[0] = good; payees[1] = address(bad);
        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; shares[1] = 5000;
        uint256 sid = split.createSplit(payees, shares);

        vm.prank(sender);
        split.pay{value: 1 ether}(sid, bytes32("x")); // no longer reverts

        split.withdraw(good);
        assertEq(good.balance, 0.5 ether, "good payee paid despite bad co-payee");
        assertEq(split.owed(address(bad)), 0.5 ether, "bad payee share safely held");
    }
}
