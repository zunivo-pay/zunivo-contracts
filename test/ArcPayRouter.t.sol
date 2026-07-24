// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArcPayRouter} from "../src/ArcPayRouter.sol";

/// @dev Merchant that rejects native transfers — simulates a broken payout target.
contract RejectingMerchant {
    receive() external payable {
        revert("no thanks");
    }
}

/// @dev Merchant that re-enters pay() on receive — reentrancy probe.
contract ReentrantMerchant {
    ArcPayRouter public router;
    address public secondMerchant;
    bool internal entered;

    constructor(ArcPayRouter _router, address _secondMerchant) {
        router = _router;
        secondMerchant = _secondMerchant;
    }

    receive() external payable {
        if (!entered) {
            entered = true;
            // Attempt a nested payment during the first payment's transfer.
            router.pay{value: msg.value / 2}(bytes32("REENTER"), secondMerchant);
        }
    }
}

contract ArcPayRouterTest is Test {
    ArcPayRouter internal router;

    address internal owner = makeAddr("owner");
    address internal feeCollector = makeAddr("feeCollector");
    address internal merchant = makeAddr("merchant");
    address internal payer = makeAddr("payer");

    event PaymentReceived(
        bytes32 indexed orderId,
        address indexed payer,
        address indexed merchant,
        uint256 grossAmount,
        uint256 feeAmount
    );

    function setUp() public {
        vm.prank(owner);
        router = new ArcPayRouter(feeCollector);
        vm.deal(payer, 1_000 ether);
    }

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    function test_constructor_setsOwnerAndCollector() public view {
        assertEq(router.owner(), owner);
        assertEq(router.feeCollector(), feeCollector);
        assertEq(router.feeBps(), 0);
    }

    function test_constructor_revertsOnZeroCollector() public {
        vm.expectRevert(ArcPayRouter.ZeroAddress.selector);
        new ArcPayRouter(address(0));
    }

    // ---------------------------------------------------------------
    // pay() — happy paths
    // ---------------------------------------------------------------

    function test_pay_zeroFee_forwardsFullAmount() public {
        bytes32 orderId = keccak256("ORDER-001");

        vm.expectEmit(true, true, true, true);
        emit PaymentReceived(orderId, payer, merchant, 10 ether, 0);

        vm.prank(payer);
        router.pay{value: 10 ether}(orderId, merchant);

        assertEq(merchant.balance, 10 ether);
        assertEq(feeCollector.balance, 0);
        assertEq(address(router).balance, 0); // zero custody invariant
    }

    function test_pay_withFee_splitsCorrectly() public {
        vm.prank(owner);
        router.setFeeBps(50); // 0.5%

        bytes32 orderId = keccak256("ORDER-002");
        vm.prank(payer);
        router.pay{value: 100 ether}(orderId, merchant);

        assertEq(merchant.balance, 99.5 ether);
        assertEq(feeCollector.balance, 0.5 ether);
        assertEq(address(router).balance, 0);
    }

    function test_pay_maxFee_splitsCorrectly() public {
        vm.prank(owner);
        router.setFeeBps(100); // 1% hard cap

        vm.prank(payer);
        router.pay{value: 100 ether}(bytes32("ORDER-003"), merchant);

        assertEq(merchant.balance, 99 ether);
        assertEq(feeCollector.balance, 1 ether);
    }

    function test_pay_tinyAmount_feeRoundsDownToZero() public {
        vm.prank(owner);
        router.setFeeBps(50);

        // 100 wei * 50 / 10_000 = 0 → merchant gets everything
        vm.prank(payer);
        router.pay{value: 100}(bytes32("ORDER-004"), merchant);

        assertEq(merchant.balance, 100);
        assertEq(feeCollector.balance, 0);
    }

    // ---------------------------------------------------------------
    // pay() — reverts
    // ---------------------------------------------------------------

    function test_pay_revertsOnZeroMerchant() public {
        vm.prank(payer);
        vm.expectRevert(ArcPayRouter.ZeroAddress.selector);
        router.pay{value: 1 ether}(bytes32("X"), address(0));
    }

    function test_pay_revertsOnZeroValue() public {
        vm.prank(payer);
        vm.expectRevert(ArcPayRouter.ZeroAmount.selector);
        router.pay(bytes32("X"), merchant);
    }

    function test_pay_revertsWhenMerchantRejects() public {
        RejectingMerchant bad = new RejectingMerchant();
        vm.prank(payer);
        vm.expectRevert(ArcPayRouter.NativeTransferFailed.selector);
        router.pay{value: 1 ether}(bytes32("X"), address(bad));
    }

    function test_receive_revertsOnStrayTransfer() public {
        vm.prank(payer);
        (bool ok, ) = address(router).call{value: 1 ether}("");
        assertFalse(ok); // direct transfers must be rejected
        assertEq(address(router).balance, 0);
    }

    // ---------------------------------------------------------------
    // Reentrancy probe
    // ---------------------------------------------------------------

    function test_pay_reentrantMerchant_cannotExtractExtraFunds() public {
        address second = makeAddr("secondMerchant");
        ReentrantMerchant attacker = new ReentrantMerchant(router, second);

        vm.prank(payer);
        router.pay{value: 10 ether}(bytes32("ORDER-R"), address(attacker));

        // The nested call is just another independent payment funded by the
        // attacker's own received balance. Conservation must hold exactly.
        assertEq(address(attacker).balance + second.balance, 10 ether);
        assertEq(address(router).balance, 0);
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------

    function test_setFeeBps_ownerOnly() public {
        vm.prank(payer);
        vm.expectRevert(ArcPayRouter.NotOwner.selector);
        router.setFeeBps(10);
    }

    function test_setFeeBps_revertsAboveCap() public {
        vm.prank(owner);
        vm.expectRevert(ArcPayRouter.FeeTooHigh.selector);
        router.setFeeBps(101);
    }

    function test_setFeeCollector_updates() public {
        address newCollector = makeAddr("newCollector");
        vm.prank(owner);
        router.setFeeCollector(newCollector);
        assertEq(router.feeCollector(), newCollector);
    }

    function test_setFeeCollector_revertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert(ArcPayRouter.ZeroAddress.selector);
        router.setFeeCollector(address(0));
    }

    function test_transferOwnership_flow() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        router.transferOwnership(newOwner);
        assertEq(router.owner(), newOwner);

        // Old owner loses rights
        vm.prank(owner);
        vm.expectRevert(ArcPayRouter.NotOwner.selector);
        router.setFeeBps(10);
    }

    // ---------------------------------------------------------------
    // Fuzz: conservation of value for arbitrary amounts and fees
    // ---------------------------------------------------------------

    function testFuzz_pay_conservesValue(uint96 amount, uint16 fee) public {
        amount = uint96(bound(amount, 1, type(uint96).max));
        fee = uint16(bound(fee, 0, router.MAX_FEE_BPS()));

        vm.prank(owner);
        router.setFeeBps(fee);

        vm.deal(payer, amount);
        vm.prank(payer);
        router.pay{value: amount}(bytes32("FUZZ"), merchant);

        uint256 expectedFee = (uint256(amount) * fee) / 10_000;
        assertEq(feeCollector.balance, expectedFee);
        assertEq(merchant.balance, uint256(amount) - expectedFee);
        assertEq(address(router).balance, 0);
    }
}
