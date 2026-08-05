// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ZunivoNames.sol";
import "../src/ZunivoAgentRecords.sol";

contract ZunivoAgentRecordsTest is Test {
    ZunivoNames names;
    ZunivoAgentRecords records;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 constant PRICE = 1 ether;

    function setUp() public {
        names = new ZunivoNames(address(0xBEEF), PRICE);
        records = new ZunivoAgentRecords(address(names));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.prank(alice);
        names.mint{value: PRICE}("data");
    }

    function idOf(string memory label) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }

    // ------------------------------------------------------------ happy path

    function test_setText_byHolder_andRead() public {
        vm.prank(alice);
        records.setText("data", "url", "https://api.data.example/v1");
        assertEq(records.text("data", "url"), "https://api.data.example/v1");
        assertEq(records.textById(idOf("data"), "url"), "https://api.data.example/v1");
    }

    function test_setTexts_batch() public {
        string[] memory keys = new string[](3);
        string[] memory vals = new string[](3);
        keys[0] = "url";       vals[0] = "https://api.data.example";
        keys[1] = "x402";      vals[1] = "https://api.data.example/.well-known/x402";
        keys[2] = "description"; vals[2] = "Premium crypto index, 0.05 USDC/call";
        vm.prank(alice);
        records.setTexts("data", keys, vals);

        string[] memory got = records.texts("data", keys);
        assertEq(got[0], vals[0]);
        assertEq(got[1], vals[1]);
        assertEq(got[2], vals[2]);
    }

    function test_overwrite_updatesValue() public {
        vm.startPrank(alice);
        records.setText("data", "url", "https://old.example");
        records.setText("data", "url", "https://new.example");
        vm.stopPrank();
        assertEq(records.text("data", "url"), "https://new.example");
    }

    function test_unsetKey_returnsEmpty() public {
        assertEq(records.text("data", "nope"), "");
    }

    // ------------------------------------------------------------ auth

    function test_setText_stranger_reverts() public {
        vm.prank(bob);
        vm.expectRevert(ZunivoAgentRecords.NotNameHolder.selector);
        records.setText("data", "url", "https://evil.example");
    }

    function test_setText_unknownName_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.UnknownName.selector);
        records.setText("ghost", "url", "https://x.example");
    }

    function test_transfer_newHolderWrites_oldHolderLockedOut() public {
        vm.prank(alice);
        records.setText("data", "url", "https://alice.example");

        vm.prank(alice);
        names.transferFrom(alice, bob, idOf("data"));

        // record survives transfer until overwritten
        assertEq(records.text("data", "url"), "https://alice.example");

        // old holder locked out
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.NotNameHolder.selector);
        records.setText("data", "url", "https://alice2.example");

        // new holder can overwrite
        vm.prank(bob);
        records.setText("data", "url", "https://bob.example");
        assertEq(records.text("data", "url"), "https://bob.example");
    }

    // ------------------------------------------------------------ clear

    function test_clearRecords_wipesAll_andVersionBumps() public {
        string[] memory keys = new string[](2);
        string[] memory vals = new string[](2);
        keys[0] = "url";  vals[0] = "https://a.example";
        keys[1] = "x402"; vals[1] = "https://a.example/m";
        vm.prank(alice);
        records.setTexts("data", keys, vals);

        uint64 v0 = records.recordVersion(idOf("data"));
        vm.prank(alice);
        records.clearRecords("data");
        assertEq(records.recordVersion(idOf("data")), v0 + 1);
        assertEq(records.text("data", "url"), "");
        assertEq(records.text("data", "x402"), "");

        // can write fresh records after clear
        vm.prank(alice);
        records.setText("data", "url", "https://fresh.example");
        assertEq(records.text("data", "url"), "https://fresh.example");
    }

    function test_clearRecords_stranger_reverts() public {
        vm.prank(bob);
        vm.expectRevert(ZunivoAgentRecords.NotNameHolder.selector);
        records.clearRecords("data");
    }

    // ------------------------------------------------------------ guards

    function test_emptyKey_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.KeyTooLong.selector);
        records.setText("data", "", "v");
    }

    function test_longKey_reverts() public {
        bytes memory k = new bytes(65);
        for (uint256 i = 0; i < 65; i++) k[i] = "a";
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.KeyTooLong.selector);
        records.setText("data", string(k), "v");
    }

    function test_longValue_reverts() public {
        bytes memory v = new bytes(2049);
        for (uint256 i = 0; i < 2049; i++) v[i] = "x";
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.ValueTooLong.selector);
        records.setText("data", "url", string(v));
    }

    function test_batch_lengthMismatch_reverts() public {
        string[] memory keys = new string[](2);
        string[] memory vals = new string[](1);
        vm.prank(alice);
        vm.expectRevert(ZunivoAgentRecords.LengthMismatch.selector);
        records.setTexts("data", keys, vals);
    }

    // ------------------------------------------------------------ events

    function test_events() public {
        vm.expectEmit(true, false, false, true);
        emit ZunivoAgentRecords.TextChanged(idOf("data"), "url", "url", "https://e.example");
        vm.prank(alice);
        records.setText("data", "url", "https://e.example");
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_roundTrip(string memory value) public {
        vm.assume(bytes(value).length <= 2048);
        vm.prank(alice);
        records.setText("data", "url", value);
        assertEq(records.text("data", "url"), value);
    }
}
