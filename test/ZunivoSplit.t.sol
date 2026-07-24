// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZunivoSplit} from "../src/ZunivoSplit.sol";

contract ReentrantPayee {
    ZunivoSplit internal s;
    uint256 internal splitId;
    bool internal armed;

    constructor(ZunivoSplit _s) { s = _s; }
    function arm(uint256 _id) external { splitId = _id; armed = true; }

    receive() external payable {
        if (armed) {
            armed = false;
            // attempt to re-enter with zero value — must revert, and must not
            // corrupt the outer distribution
            try s.pay{value: 0}(splitId, bytes32(0)) { revert("reentry ok?!"); } catch {}
        }
    }
}

contract ZunivoSplitTest is Test {
    ZunivoSplit internal s;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal platform = makeAddr("platform");
    address internal creator = makeAddr("creator");
    address internal referrer = makeAddr("referrer");
    address internal payer = makeAddr("payer");

    function setUp() public {
        vm.prank(owner);
        s = new ZunivoSplit(treasury, 0);
        vm.deal(payer, 1_000 ether);
    }

    function _threeWay() internal returns (uint256 id) {
        address[] memory p = new address[](3);
        uint16[] memory b = new uint16[](3);
        p[0] = platform; p[1] = creator; p[2] = referrer;
        b[0] = 7000; b[1] = 2500; b[2] = 500;
        id = s.createSplit(p, b);
    }

    // ------------------------------------------------------------ creation

    function test_create_ok() public {
        uint256 id = _threeWay();
        (address cr, address[] memory p, uint16[] memory b) = s.splitOf(id);
        assertEq(cr, address(this));
        assertEq(p.length, 3);
        assertEq(b[0] + b[1] + b[2], 10_000);
    }

    function test_create_guards() public {
        address[] memory one = new address[](1);
        uint16[] memory oneB = new uint16[](1);
        one[0] = platform; oneB[0] = 10_000;
        vm.expectRevert(ZunivoSplit.BadPayees.selector);
        s.createSplit(one, oneB);

        address[] memory p = new address[](2);
        uint16[] memory b = new uint16[](2);
        p[0] = platform; p[1] = address(0); b[0] = 5000; b[1] = 5000;
        vm.expectRevert(ZunivoSplit.ZeroAddress.selector);
        s.createSplit(p, b);

        p[1] = creator; b[1] = 4000; // sums to 9000
        vm.expectRevert(ZunivoSplit.BadShares.selector);
        s.createSplit(p, b);

        b[1] = 0; b[0] = 10_000; // zero share slot
        vm.expectRevert(ZunivoSplit.BadShares.selector);
        s.createSplit(p, b);
    }

    // ------------------------------------------------------------ payment

    function test_pay_threeWay_exact() public {
        uint256 id = _threeWay();
        vm.prank(payer);
        s.pay{value: 100 ether}(id, keccak256("ORDER-1"));

        assertEq(platform.balance, 70 ether);
        assertEq(creator.balance, 25 ether);
        assertEq(referrer.balance, 5 ether);
        assertEq(address(s).balance, 0); // zero custody
    }

    function test_pay_roundingDust_toLastPayee() public {
        uint256 id = _threeWay();
        vm.prank(payer);
        s.pay{value: 1}(id, 0); // 1 wei: 0/0/dust
        assertEq(platform.balance, 0);
        assertEq(creator.balance, 0);
        assertEq(referrer.balance, 1); // last payee absorbs everything
        assertEq(address(s).balance, 0);
    }

    function test_pay_withFee() public {
        vm.prank(owner);
        s.setFeeBps(100); // 1%
        uint256 id = _threeWay();
        vm.prank(payer);
        s.pay{value: 100 ether}(id, 0);
        assertEq(treasury.balance, 1 ether);
        assertEq(platform.balance, 69.3 ether);   // 70% of 99
        assertEq(creator.balance, 24.75 ether);   // 25% of 99
        assertEq(referrer.balance, 4.95 ether);   // dust-free here
        assertEq(address(s).balance, 0);
    }

    function test_pay_guards() public {
        vm.expectRevert(ZunivoSplit.SplitNotFound.selector);
        s.pay{value: 1 ether}(999, 0);

        uint256 id = _threeWay();
        vm.prank(payer);
        vm.expectRevert(ZunivoSplit.ZeroValue.selector);
        s.pay(id, 0);
    }

    function test_pay_isPermissionless() public {
        uint256 id = _threeWay();
        address anyone = makeAddr("anyone");
        vm.deal(anyone, 10 ether);
        vm.prank(anyone);
        s.pay{value: 10 ether}(id, 0);
        assertEq(platform.balance, 7 ether);
    }

    function test_reentrantPayee_cannotCorruptDistribution() public {
        ReentrantPayee attacker = new ReentrantPayee(s);
        address[] memory p = new address[](2);
        uint16[] memory b = new uint16[](2);
        p[0] = address(attacker); p[1] = creator;
        b[0] = 5000; b[1] = 5000;
        uint256 id = s.createSplit(p, b);
        attacker.arm(id);

        vm.prank(payer);
        s.pay{value: 10 ether}(id, 0);
        assertEq(address(attacker).balance, 5 ether);
        assertEq(creator.balance, 5 ether);
        assertEq(address(s).balance, 0);
    }

    function test_receive_reverts() public {
        vm.prank(payer);
        (bool ok, ) = address(s).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // ------------------------------------------------------------ admin

    function test_admin_guards() public {
        vm.prank(payer);
        vm.expectRevert(ZunivoSplit.NotOwner.selector);
        s.setFeeBps(1);

        vm.prank(owner);
        vm.expectRevert(ZunivoSplit.FeeTooHigh.selector);
        s.setFeeBps(101);
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_conservation(uint96 amount, uint16 fee, uint16 aBps) public {
        amount = uint96(bound(amount, 1, 900 ether));
        fee = uint16(bound(fee, 0, 100));
        aBps = uint16(bound(aBps, 1, 9_999));

        vm.prank(owner);
        s.setFeeBps(fee);

        address[] memory p = new address[](2);
        uint16[] memory b = new uint16[](2);
        p[0] = platform; p[1] = creator;
        b[0] = aBps; b[1] = uint16(10_000 - aBps);
        uint256 id = s.createSplit(p, b);

        vm.prank(payer);
        s.pay{value: amount}(id, 0);

        // every wei accounted for, nothing stranded
        assertEq(platform.balance + creator.balance + treasury.balance, amount);
        assertEq(address(s).balance, 0);
    }
}
