// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IZunivoNames {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title ZunivoAgentRecords
/// @notice Text records for .agent names — the service-discovery layer of the
///         Zunivo network. ENS-resolver-style key/value store keyed by the
///         name's tokenId (keccak256(label)), writable only by the current
///         holder of the corresponding ZunivoNames NFT.
///
///         Standard keys (convention, not enforced):
///           "url"          service endpoint an agent can call
///           "x402"         URL of the x402 payment manifest (prices, schemes)
///           "description"  human/agent-readable one-liner
///           "avatar"       image URL
///
///         Records survive name transfers (the new holder can overwrite or
///         clearRecords()). Versioned storage makes clearing O(1).
/// @dev    Fully permissionless and non-custodial: no owner, no fees, no
///         admin functions. The only authority is ZunivoNames.ownerOf.
contract ZunivoAgentRecords {
    IZunivoNames public immutable names;

    /// tokenId => current record version (bumped by clearRecords)
    mapping(uint256 => uint64) public recordVersion;
    /// tokenId => version => key => value
    mapping(uint256 => mapping(uint64 => mapping(string => string))) private _texts;

    event TextChanged(uint256 indexed tokenId, string indexed indexedKey, string key, string value);
    event RecordsCleared(uint256 indexed tokenId, uint64 newVersion);

    error NotNameHolder();
    error UnknownName();
    error KeyTooLong();
    error ValueTooLong();
    error LengthMismatch();

    uint256 public constant MAX_KEY_LENGTH = 64;
    uint256 public constant MAX_VALUE_LENGTH = 2048;

    constructor(address _names) {
        names = IZunivoNames(_names);
    }

    // ---------------------------------------------------------------
    // Writes — gated by current NFT ownership
    // ---------------------------------------------------------------

    function setText(string calldata label, string calldata key, string calldata value) external {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _setText(tokenId, key, value);
    }

    /// @notice Batch write — one transaction to publish a full agent card.
    function setTexts(string calldata label, string[] calldata keys, string[] calldata values) external {
        if (keys.length != values.length) revert LengthMismatch();
        uint256 tokenId = uint256(keccak256(bytes(label)));
        for (uint256 i = 0; i < keys.length; i++) {
            _setText(tokenId, keys[i], values[i]);
        }
    }

    /// @notice Wipe every record for a name in O(1) by bumping the version.
    function clearRecords(string calldata label) external {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _requireHolder(tokenId);
        uint64 v = ++recordVersion[tokenId];
        emit RecordsCleared(tokenId, v);
    }

    function _setText(uint256 tokenId, string calldata key, string calldata value) internal {
        _requireHolder(tokenId);
        if (bytes(key).length == 0 || bytes(key).length > MAX_KEY_LENGTH) revert KeyTooLong();
        if (bytes(value).length > MAX_VALUE_LENGTH) revert ValueTooLong();
        _texts[tokenId][recordVersion[tokenId]][key] = value;
        emit TextChanged(tokenId, key, key, value);
    }

    function _requireHolder(uint256 tokenId) internal view {
        address holder;
        try names.ownerOf(tokenId) returns (address h) {
            holder = h;
        } catch {
            revert UnknownName();
        }
        if (holder != msg.sender) revert NotNameHolder();
    }

    // ---------------------------------------------------------------
    // Reads — free for anyone (agents, indexers, apps)
    // ---------------------------------------------------------------

    function text(string calldata label, string calldata key) external view returns (string memory) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        return _texts[tokenId][recordVersion[tokenId]][key];
    }

    function textById(uint256 tokenId, string calldata key) external view returns (string memory) {
        return _texts[tokenId][recordVersion[tokenId]][key];
    }

    /// @notice Batch read — one call to fetch a full agent card.
    function texts(string calldata label, string[] calldata keys) external view returns (string[] memory values) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        uint64 v = recordVersion[tokenId];
        values = new string[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            values[i] = _texts[tokenId][v][keys[i]];
        }
    }
}
