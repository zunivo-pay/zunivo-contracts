// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title ZunivoNames
/// @notice On-chain payment-handle registry for the Zunivo network on Arc.
///         Each name is an ERC-721 token (tokenId = keccak256(name)) that
///         resolves to a payment address. Resolution follows the NFT: on any
///         transfer the record resets to the new holder, so a bought name can
///         never keep paying its previous owner by accident.
/// @dev    Mint fees (native USDC) are forwarded to the treasury within the
///         mint transaction — the contract never holds a balance.
contract ZunivoNames is ERC721 {
    address public owner;
    address public treasury;

    /// @notice Mint price in native-USDC wei (18 decimals). Adjustable, capped.
    uint256 public mintPrice;
    uint256 public constant MAX_MINT_PRICE = 100 ether;

    mapping(uint256 => string) public nameOf;
    mapping(uint256 => address) public recordOf;

    event NameRegistered(string name, uint256 indexed tokenId, address indexed holder, uint256 pricePaid);
    event AddressSet(uint256 indexed tokenId, address indexed newAddress);
    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotTokenOwner();
    error ZeroAddress();
    error WrongPayment();
    error PriceTooHigh();
    error InvalidName();
    error ReservedName();
    error AlreadyRegistered();
    error TreasuryTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _treasury, uint256 _mintPrice) ERC721("Zunivo Names", "ZNAME") {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_mintPrice > MAX_MINT_PRICE) revert PriceTooHigh();
        owner = msg.sender;
        treasury = _treasury;
        mintPrice = _mintPrice;
    }

    // ---------------------------------------------------------------
    // Registration & resolution
    // ---------------------------------------------------------------

    function tokenIdFor(string calldata label) external pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }

    function mint(string calldata label) external payable returns (uint256 tokenId) {
        if (msg.value != mintPrice) revert WrongPayment();
        if (!_validName(bytes(label))) revert InvalidName();
        if (_isReserved(label)) revert ReservedName();

        tokenId = uint256(keccak256(bytes(label)));
        if (_ownerOf(tokenId) != address(0)) revert AlreadyRegistered();

        nameOf[tokenId] = label;
        // _mint (not _safeMint): a registry has no receiver-callback needs, and
        // dropping the onERC721Received hook removes the reentrancy surface.
        _mint(msg.sender, tokenId); // _update() binds recordOf to the minter
        emit NameRegistered(label, tokenId, msg.sender, msg.value);

        if (msg.value > 0) {
            (bool ok, ) = treasury.call{value: msg.value}("");
            if (!ok) revert TreasuryTransferFailed();
        }
    }

    function resolve(string calldata label) external view returns (address) {
        return recordOf[uint256(keccak256(bytes(label)))];
    }

    /// @notice Point a name you hold at a different payment address.
    function setAddress(string calldata label, address newAddress) external {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (newAddress == address(0)) revert ZeroAddress();
        recordOf[tokenId] = newAddress;
        emit AddressSet(tokenId, newAddress);
    }

    /// @dev Resolution follows the token: mint and every transfer rebind the
    ///      record to the new holder.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (to != address(0)) {
            recordOf[tokenId] = to;
            emit AddressSet(tokenId, to);
        }
        return from;
    }

    // ---------------------------------------------------------------
    // Name rules
    // ---------------------------------------------------------------

    function _validName(bytes memory b) internal pure returns (bool) {
        if (b.length < 3 || b.length > 20) return false;
        if (b[0] == "-" || b[b.length - 1] == "-") return false;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool ok = (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0x2d;
            if (!ok) return false;
        }
        return true;
    }

    function _isReserved(string calldata label) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(label));
        return
            h == keccak256("zunivo") || h == keccak256("admin") || h == keccak256("root") ||
            h == keccak256("support") || h == keccak256("help") || h == keccak256("pay") ||
            h == keccak256("app") || h == keccak256("api") || h == keccak256("circle") ||
            h == keccak256("usdc") || h == keccak256("arc") || h == keccak256("official") ||
            h == keccak256("team") || h == keccak256("www") || h == keccak256("wallet") ||
            h == keccak256("dashboard") || h == keccak256("mail");
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------

    function setMintPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > MAX_MINT_PRICE) revert PriceTooHigh();
        emit MintPriceUpdated(mintPrice, newPrice);
        mintPrice = newPrice;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ---------------------------------------------------------------
    // Fully on-chain metadata (no server, no IPFS)
    // ---------------------------------------------------------------

    /// @notice Metadata + card image are generated on-chain. Labels are
    ///         restricted to [a-z0-9-], so string interpolation into SVG/JSON
    ///         is injection-safe by construction.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory label = nameOf[tokenId];
        string memory json = string.concat(
            '{"name":"', label, '.zunivo",',
            '"description":"Zunivo payment handle on Arc. Whoever holds this token receives payments sent to ', label, '.zunivo in the Zunivo network.",',
            '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(_cardSvg(label))), '",',
            '"attributes":[{"trait_type":"Length","value":"', Strings.toString(bytes(label).length), '"},',
            '{"trait_type":"Network","value":"Arc"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _cardSvg(string memory label) internal pure returns (string memory) {
        uint256 len = bytes(label).length;
        string memory fs = len <= 8 ? "58" : (len <= 13 ? "42" : "30");
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="500" height="500" viewBox="0 0 500 500">',
            '<rect width="500" height="500" rx="28" fill="#101828"/>',
            '<rect x="60" y="72" width="100" height="19" rx="9.5" fill="#3D5AFE"/>',
            '<line x1="146" y1="101" x2="74" y2="157" stroke="#10C48B" stroke-width="19" stroke-linecap="round"/>',
            '<circle cx="74" cy="157" r="7" fill="#0B8F63"/>',
            '<rect x="60" y="166" width="100" height="19" rx="9.5" fill="#3D5AFE"/>',
            '<text x="60" y="308" font-family="Helvetica,Arial,sans-serif" font-weight="700" font-size="', fs, '" fill="#FFFFFF">', label, '</text>',
            '<text x="60" y="352" font-family="Helvetica,Arial,sans-serif" font-weight="600" font-size="27" fill="#10C48B">.zunivo</text>',
            '<rect x="60" y="398" width="120" height="5" rx="2.5" fill="#3D5AFE"/>',
            '<text x="60" y="438" font-family="Courier,monospace" font-size="15" letter-spacing="3" fill="#98A2B3">ZUNIVO NAMES</text>',
            '<text x="60" y="462" font-family="Courier,monospace" font-size="13" letter-spacing="3" fill="#5B6474">ON ARC</text>',
            '</svg>'
        );
    }

    /// @dev Names are minted through mint() only; stray transfers are rejected.
    receive() external payable {
        revert WrongPayment();
    }
}
