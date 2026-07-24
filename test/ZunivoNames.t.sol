// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZunivoNames} from "../src/ZunivoNames.sol";

contract ZunivoNamesTest is Test {
    ZunivoNames internal names;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant PRICE = 1 ether; // 1 USDC (native, 18d)

    event NameRegistered(string name, uint256 indexed tokenId, address indexed holder, uint256 pricePaid);
    event AddressSet(uint256 indexed tokenId, address indexed newAddress);

    function setUp() public {
        vm.prank(owner);
        names = new ZunivoNames(treasury, PRICE);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function idOf(string memory n) internal pure returns (uint256) {
        return uint256(keccak256(bytes(n)));
    }

    // ------------------------------------------------------------ constructor

    function test_constructor_guards() public {
        vm.expectRevert(ZunivoNames.ZeroAddress.selector);
        new ZunivoNames(address(0), PRICE);
        vm.expectRevert(ZunivoNames.PriceTooHigh.selector);
        new ZunivoNames(treasury, 101 ether);
    }

    // ------------------------------------------------------------ mint

    function test_mint_happyPath() public {
        vm.expectEmit(true, true, false, true);
        emit NameRegistered("alice", idOf("alice"), alice, PRICE);

        vm.prank(alice);
        uint256 tokenId = names.mint{value: PRICE}("alice");

        assertEq(tokenId, idOf("alice"));
        assertEq(names.ownerOf(tokenId), alice);
        assertEq(names.nameOf(tokenId), "alice");
        assertEq(names.resolve("alice"), alice);
        assertEq(treasury.balance, PRICE);          // fee forwarded
        assertEq(address(names).balance, 0);        // zero-custody invariant
    }

    function test_mint_wrongPayment_reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(ZunivoNames.WrongPayment.selector);
        names.mint{value: PRICE - 1}("alice");
        vm.expectRevert(ZunivoNames.WrongPayment.selector);
        names.mint{value: PRICE + 1}("alice");
        vm.stopPrank();
    }

    function test_mint_freeWhenPriceZero() public {
        vm.prank(owner);
        names.setMintPrice(0);

        vm.prank(alice);
        names.mint("free-name");
        assertEq(names.resolve("free-name"), alice);
        assertEq(treasury.balance, 0);

        // paying while price is zero must revert (strict accounting)
        vm.prank(bob);
        vm.expectRevert(ZunivoNames.WrongPayment.selector);
        names.mint{value: 1}("anything"); // payment check fires before name rules
    }

    function test_mint_duplicate_reverts() public {
        vm.prank(alice);
        names.mint{value: PRICE}("alice");
        vm.prank(bob);
        vm.expectRevert(ZunivoNames.AlreadyRegistered.selector);
        names.mint{value: PRICE}("alice");
    }

    function test_mint_invalidNames_revert() public {
        string[7] memory bad = ["ab", "abcdefghijklmnopqrstu", "Alice", "al ice", "-abc", "abc-", "ab_c"];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.prank(alice);
            vm.expectRevert(ZunivoNames.InvalidName.selector);
            names.mint{value: PRICE}(bad[i]);
        }
    }

    function test_mint_reservedNames_revert() public {
        string[4] memory reserved = ["zunivo", "arc", "circle", "usdc"];
        for (uint256 i = 0; i < reserved.length; i++) {
            vm.prank(alice);
            vm.expectRevert(ZunivoNames.ReservedName.selector);
            names.mint{value: PRICE}(reserved[i]);
        }
    }

    // ------------------------------------------------------------ resolution

    function test_resolve_unknown_returnsZero() public view {
        assertEq(names.resolve("nobody"), address(0));
    }

    function test_setAddress_byHolder() public {
        vm.prank(alice);
        names.mint{value: PRICE}("alice");

        address shop = makeAddr("shopWallet");
        vm.prank(alice);
        names.setAddress("alice", shop);
        assertEq(names.resolve("alice"), shop);
    }

    function test_setAddress_stranger_reverts() public {
        vm.prank(alice);
        names.mint{value: PRICE}("alice");
        vm.prank(bob);
        vm.expectRevert(ZunivoNames.NotTokenOwner.selector);
        names.setAddress("alice", bob);
    }

    function test_setAddress_zero_reverts() public {
        vm.prank(alice);
        names.mint{value: PRICE}("alice");
        vm.prank(alice);
        vm.expectRevert(ZunivoNames.ZeroAddress.selector);
        names.setAddress("alice", address(0));
    }

    function test_transfer_rebindsResolution() public {
        vm.prank(alice);
        uint256 tokenId = names.mint{value: PRICE}("alice");

        // holder points the name somewhere custom first
        vm.prank(alice);
        names.setAddress("alice", makeAddr("oldShop"));

        vm.prank(alice);
        names.transferFrom(alice, bob, tokenId);

        // resolution must follow the new holder, not the stale record
        assertEq(names.ownerOf(tokenId), bob);
        assertEq(names.resolve("alice"), bob);
    }

    // ------------------------------------------------------------ admin

    function test_admin_guards() public {
        vm.prank(alice);
        vm.expectRevert(ZunivoNames.NotOwner.selector);
        names.setMintPrice(2 ether);

        vm.prank(owner);
        vm.expectRevert(ZunivoNames.PriceTooHigh.selector);
        names.setMintPrice(101 ether);

        vm.prank(owner);
        names.setMintPrice(2 ether);
        assertEq(names.mintPrice(), 2 ether);

        vm.prank(owner);
        vm.expectRevert(ZunivoNames.ZeroAddress.selector);
        names.setTreasury(address(0));

        address t2 = makeAddr("treasury2");
        vm.prank(owner);
        names.setTreasury(t2);
        assertEq(names.treasury(), t2);
    }

    function test_transferOwnership_flow() public {
        address next = makeAddr("nextOwner");
        vm.prank(owner);
        names.transferOwnership(next);
        vm.prank(owner);
        vm.expectRevert(ZunivoNames.NotOwner.selector);
        names.setMintPrice(1);
    }

    function test_receive_reverts() public {
        vm.prank(alice);
        (bool ok, ) = address(names).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(names).balance, 0);
    }

    // ------------------------------------------------------------ metadata

    function test_tokenURI_onchainMetadata() public {
        vm.prank(alice);
        uint256 tokenId = names.mint{value: PRICE}("alice");
        string memory uri = names.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 200);
        // must be a self-contained data URI, no external dependencies
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(bytes(uri)[i], prefix[i]);
        }
    }

    function test_tokenURI_unknownToken_reverts() public {
        vm.expectRevert();
        names.tokenURI(uint256(keccak256("ghost")));
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_mint_forwardsExactFee(uint96 price) public {
        price = uint96(bound(price, 0, 100 ether));
        vm.prank(owner);
        names.setMintPrice(price);

        vm.deal(bob, uint256(price) + 1 ether);
        vm.prank(bob);
        names.mint{value: price}("bobs-shop");

        assertEq(treasury.balance, price);
        assertEq(address(names).balance, 0);
        assertEq(names.resolve("bobs-shop"), bob);
    }
}
