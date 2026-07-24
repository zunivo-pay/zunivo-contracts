// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ZunivoSplit
/// @notice Atomic revenue splitting for the machine economy on Arc. A split is
///         an immutable table of payees and basis-point shares; any payment to
///         it is distributed to every payee within the same transaction. The
///         contract never holds a balance and a share table can never be
///         edited after creation — the terms your collaborators saw are the
///         terms that execute, forever.
/// @dev    Rounding dust from integer division goes to the last payee so that
///         every wei of a payment is accounted for. Protocol fee (hard-capped
///         1%, currently 0) is taken before the split; treasury is immutable.
contract ZunivoSplit {
    struct SplitConfig {
        address creator;
        address[] payees;
        uint16[] sharesBps; // sums to 10_000
    }

    address public owner;
    address public immutable treasury;
    uint16 public feeBps;

    uint16 public constant MAX_FEE_BPS = 100; // 1%
    uint256 public constant MAX_PAYEES = 20;
    uint16 public constant TOTAL_BPS = 10_000;

    uint256 public nextSplitId;
    mapping(uint256 => SplitConfig) internal _splits;

    event SplitCreated(uint256 indexed splitId, address indexed creator, address[] payees, uint16[] sharesBps);
    event SplitPaid(uint256 indexed splitId, bytes32 indexed orderId, address indexed payer, uint256 grossAmount, uint256 feeAmount);
    event ShareSent(uint256 indexed splitId, bytes32 indexed orderId, address indexed payee, uint256 amount);
    event FeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error ZeroValue();
    error BadPayees();
    error BadShares();
    error SplitNotFound();
    error FeeTooHigh();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _treasury, uint16 _feeBps) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        owner = msg.sender;
        treasury = _treasury;
        feeBps = _feeBps;
    }

    // ---------------------------------------------------------------
    // Split creation — immutable once created
    // ---------------------------------------------------------------

    function createSplit(address[] calldata payees, uint16[] calldata sharesBps)
        external
        returns (uint256 splitId)
    {
        uint256 n = payees.length;
        if (n < 2 || n > MAX_PAYEES || sharesBps.length != n) revert BadPayees();

        uint256 total;
        for (uint256 i = 0; i < n; i++) {
            if (payees[i] == address(0)) revert ZeroAddress();
            if (sharesBps[i] == 0) revert BadShares();
            total += sharesBps[i];
        }
        if (total != TOTAL_BPS) revert BadShares();

        splitId = nextSplitId++;
        SplitConfig storage c = _splits[splitId];
        c.creator = msg.sender;
        c.payees = payees;
        c.sharesBps = sharesBps;

        emit SplitCreated(splitId, msg.sender, payees, sharesBps);
    }

    function splitOf(uint256 splitId)
        external
        view
        returns (address creator, address[] memory payees, uint16[] memory sharesBps)
    {
        SplitConfig storage c = _splits[splitId];
        if (c.creator == address(0)) revert SplitNotFound();
        return (c.creator, c.payees, c.sharesBps);
    }

    // ---------------------------------------------------------------
    // Payment — atomic distribution, zero custody
    // ---------------------------------------------------------------

    function pay(uint256 splitId, bytes32 orderId) external payable {
        SplitConfig storage c = _splits[splitId];
        if (c.creator == address(0)) revert SplitNotFound();
        if (msg.value == 0) revert ZeroValue();

        uint256 fee = (msg.value * feeBps) / uint256(TOTAL_BPS);
        uint256 distributable = msg.value - fee;

        emit SplitPaid(splitId, orderId, msg.sender, msg.value, fee);

        uint256 n = c.payees.length;
        uint256 sent;
        for (uint256 i = 0; i < n; i++) {
            uint256 share = i == n - 1
                ? distributable - sent // last payee absorbs rounding dust
                : (distributable * c.sharesBps[i]) / uint256(TOTAL_BPS);
            sent += share;
            emit ShareSent(splitId, orderId, c.payees[i], share);
            (bool ok, ) = c.payees[i].call{value: share}("");
            if (!ok) revert TransferFailed();
        }

        if (fee > 0) {
            (bool okFee, ) = treasury.call{value: fee}("");
            if (!okFee) revert TransferFailed();
        }
    }

    // ---------------------------------------------------------------
    // Admin — future fee only; share tables are untouchable by design
    // ---------------------------------------------------------------

    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit FeeBpsUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {
        revert ZeroValue();
    }
}
