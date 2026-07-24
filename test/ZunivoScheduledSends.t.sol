// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZunivoScheduledSends} from "../src/ZunivoScheduledSends.sol";

contract ReentrantRecipient {
    ZunivoScheduledSends internal s;
    uint256 internal id;
    bool internal armed;

    constructor(ZunivoScheduledSends _s) { s = _s; }
    function arm(uint256 _id) external { id = _id; armed = true; }

    receive() external payable {
        if (armed) {
            armed = false;
            // try to double-release during payout — must revert (NotPending)
            try s.release(id) { revert("reentry succeeded"); } catch {}
        }
    }
}

contract ZunivoScheduledSendsTest is Test {
    ZunivoScheduledSends internal s;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal boss = makeAddr("boss");        // sender / employer
    address internal worker = makeAddr("worker");    // recipient / employee
    address internal stranger = makeAddr("stranger");

    uint64 internal unlock;

    function setUp() public {
        vm.warp(1_800_000_000);
        unlock = uint64(block.timestamp + 15 days);
        vm.prank(owner);
        s = new ZunivoScheduledSends(treasury, 0);
        vm.deal(boss, 1_000 ether);
        vm.deal(stranger, 10 ether);
    }

    function _wage(uint256 amount) internal returns (uint256 id) {
        vm.prank(boss);
        id = s.createSend{value: amount}(worker, unlock, 0, keccak256("SALARY-07"));
    }

    // ------------------------------------------------------------ create

    function test_create_wageLock() public {
        uint256 id = _wage(100 ether);
        (address sender, address recipient, uint256 amount,, uint64 reclaimAt,, ZunivoScheduledSends.Status st,) = s.locks(id);
        assertEq(sender, boss);
        assertEq(recipient, worker);
        assertEq(amount, 100 ether);
        assertEq(reclaimAt, 0); // committed: never reclaimable
        assertEq(uint8(st), 0);
        assertEq(address(s).balance, 100 ether); // funds held by keyless code
    }

    function test_create_guards() public {
        vm.startPrank(boss);
        vm.expectRevert(ZunivoScheduledSends.ZeroAddress.selector);
        s.createSend{value: 1 ether}(address(0), unlock, 0, 0);
        vm.expectRevert(ZunivoScheduledSends.ZeroAmount.selector);
        s.createSend(worker, unlock, 0, 0);
        vm.expectRevert(ZunivoScheduledSends.UnlockNotInFuture.selector);
        s.createSend{value: 1 ether}(worker, uint64(block.timestamp), 0, 0);
        vm.expectRevert(ZunivoScheduledSends.LockTooLong.selector);
        s.createSend{value: 1 ether}(worker, uint64(block.timestamp + 367 days), 0, 0);
        vm.expectRevert(ZunivoScheduledSends.GraceTooShort.selector);
        s.createSend{value: 1 ether}(worker, unlock, 29 days, 0); // below 30d floor
        vm.stopPrank();
    }

    function test_createBatch_payroll() public {
        address w2 = makeAddr("worker2");
        address[] memory rs = new address[](2);
        uint256[] memory as_ = new uint256[](2);
        bytes32[] memory os = new bytes32[](2);
        rs[0] = worker; rs[1] = w2;
        as_[0] = 100 ether; as_[1] = 60 ether;
        os[0] = keccak256("W1"); os[1] = keccak256("W2");

        vm.prank(boss);
        uint256 first = s.createBatch{value: 160 ether}(rs, as_, unlock, 0, os);
        assertEq(address(s).balance, 160 ether);

        vm.warp(unlock);
        s.release(first);
        s.release(first + 1);
        assertEq(worker.balance, 100 ether);
        assertEq(w2.balance, 60 ether);
        assertEq(address(s).balance, 0);
    }

    function test_createBatch_guards() public {
        address[] memory rs = new address[](1);
        uint256[] memory as_ = new uint256[](1);
        bytes32[] memory os = new bytes32[](1);
        rs[0] = worker; as_[0] = 2 ether; os[0] = 0;

        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.ValueMismatch.selector);
        s.createBatch{value: 1 ether}(rs, as_, unlock, 0, os);

        address[] memory none = new address[](0);
        uint256[] memory noneA = new uint256[](0);
        bytes32[] memory noneO = new bytes32[](0);
        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.BatchInvalid.selector);
        s.createBatch(none, noneA, unlock, 0, noneO);
    }

    // ------------------------------------------------------------ the trust layer

    function test_release_beforeUnlock_revertsForEveryone() public {
        uint256 id = _wage(100 ether);
        address[4] memory actors = [boss, worker, owner, stranger];
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            vm.expectRevert(ZunivoScheduledSends.StillLocked.selector);
            s.release(id);
        }
    }

    function test_ownerHasZeroPowerOverLockedFunds() public {
        uint256 id = _wage(100 ether);
        // owner tries everything it has — none of it can move the lock
        vm.startPrank(owner);
        vm.expectRevert(ZunivoScheduledSends.StillLocked.selector);
        s.release(id);
        vm.expectRevert(ZunivoScheduledSends.OnlySender.selector);
        s.reclaim(id);
        s.setFeeBps(100); // future fees only — proven harmless by fee-snapshot test
        vm.stopPrank();
        assertEq(address(s).balance, 100 ether); // untouched
    }

    function test_wageLock_neverReclaimable() public {
        uint256 id = _wage(100 ether);
        vm.warp(unlock + 365 days); // even a year later
        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.NotReclaimable.selector);
        s.reclaim(id);
    }

    function test_release_afterUnlock_byAnyone_paysWorker() public {
        uint256 id = _wage(100 ether);
        vm.warp(unlock);
        vm.prank(stranger); // permissionless trigger
        s.release(id);
        assertEq(worker.balance, 100 ether);
        assertEq(address(s).balance, 0);
    }

    function test_release_twice_reverts() public {
        uint256 id = _wage(100 ether);
        vm.warp(unlock);
        s.release(id);
        vm.expectRevert(ZunivoScheduledSends.NotPending.selector);
        s.release(id);
    }

    function test_release_unknownId_reverts() public {
        vm.expectRevert(ZunivoScheduledSends.LockNotFound.selector);
        s.release(999);
    }

    // ------------------------------------------------------------ fee snapshot

    function test_feeSnapshot_laterChangesNeverTouchOldLocks() public {
        vm.prank(owner);
        s.setFeeBps(50); // 0.5% at creation time
        uint256 id = _wage(100 ether);

        vm.prank(owner);
        s.setFeeBps(100); // owner raises fees afterwards — must not matter

        vm.warp(unlock);
        s.release(id);
        assertEq(worker.balance, 99.5 ether);   // 0.5%, not 1%
        assertEq(treasury.balance, 0.5 ether);
    }

    // ------------------------------------------------------------ reclaim path

    function test_reclaim_flow() public {
        vm.prank(boss);
        uint256 id = s.createSend{value: 50 ether}(worker, unlock, 30 days, keccak256("REFUNDABLE"));

        // before unlock: nothing
        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.ReclaimNotOpen.selector);
        s.reclaim(id);

        // inside the worker's exclusive window: still nothing
        vm.warp(unlock + 29 days);
        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.ReclaimNotOpen.selector);
        s.reclaim(id);

        // only the sender may reclaim, even after the window
        vm.warp(unlock + 30 days);
        vm.prank(stranger);
        vm.expectRevert(ZunivoScheduledSends.OnlySender.selector);
        s.reclaim(id);

        uint256 before = boss.balance;
        vm.prank(boss);
        s.reclaim(id);
        assertEq(boss.balance, before + 50 ether); // full refund, no fee
        assertEq(address(s).balance, 0);

        vm.warp(unlock + 31 days);
        vm.expectRevert(ZunivoScheduledSends.NotPending.selector);
        s.release(id); // reclaimed locks can never also be released
    }

    function test_release_beatsReclaim_insideWindow() public {
        vm.prank(boss);
        uint256 id = s.createSend{value: 50 ether}(worker, unlock, 30 days, 0);
        vm.warp(unlock + 30 days); // window open, but worker (anyone) releases first
        s.release(id);
        assertEq(worker.balance, 50 ether);
        vm.prank(boss);
        vm.expectRevert(ZunivoScheduledSends.NotPending.selector);
        s.reclaim(id);
    }

    // ------------------------------------------------------------ reentrancy & misc

    function test_reentrantRecipient_cannotDoubleClaim() public {
        ReentrantRecipient attacker = new ReentrantRecipient(s);
        vm.prank(boss);
        uint256 id = s.createSend{value: 10 ether}(address(attacker), unlock, 0, 0);
        attacker.arm(id);
        vm.warp(unlock);
        s.release(id);
        assertEq(address(attacker).balance, 10 ether); // exactly once
        assertEq(address(s).balance, 0);
    }

    function test_receive_reverts() public {
        vm.prank(boss);
        (bool ok, ) = address(s).call{value: 1 ether}("");
        assertFalse(ok);
    }

    function test_accounting_acrossLocks() public {
        uint256 a = _wage(30 ether);
        vm.prank(boss);
        s.createSend{value: 70 ether}(worker, unlock, 0, keccak256("B"));
        vm.warp(unlock);
        s.release(a);
        assertEq(address(s).balance, 70 ether); // untouched lock stays fully backed
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_conservation(uint96 amount, uint16 fee, uint64 grace) public {
        amount = uint96(bound(amount, 1, 500 ether));
        fee = uint16(bound(fee, 0, 100));
        grace = uint64(bound(grace, 30 days, 300 days));

        vm.prank(owner);
        s.setFeeBps(fee);

        vm.prank(boss);
        uint256 id = s.createSend{value: amount}(worker, unlock, grace, 0);

        vm.warp(unlock);
        s.release(id);

        uint256 expectedFee = (uint256(amount) * fee) / 10_000;
        assertEq(treasury.balance, expectedFee);
        assertEq(worker.balance, uint256(amount) - expectedFee);
        assertEq(address(s).balance, 0);
    }
}
