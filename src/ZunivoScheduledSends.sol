// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ZunivoScheduledSends
/// @notice Committed scheduled payments ("trust layer") on Arc. A sender locks
///         native USDC now; before `unlockAt` NOBODY can move it — not the
///         sender, not the recipient, not Zunivo (there is no function for it).
///         After unlock, `release()` is permissionless but funds can only flow
///         to the recipient fixed at creation. An optional reclaim window
///         (chosen irrevocably at creation, floored at 30 days after unlock)
///         lets the sender recover funds that were never claimable in practice
///         (e.g. a mistyped recipient). Wage-style sends set grace = 0: never
///         reclaimable.
/// @dev    Deliberately absent: pause, upgrade, blacklist, owner withdrawal.
///         The owner's power over locked funds is zero, and the test suite
///         proves it. Fee bps are snapshotted at creation so later fee changes
///         can never touch already-locked money.
contract ZunivoScheduledSends {
    enum Status { Pending, Released, Reclaimed }

    struct Lock {
        address sender;
        address recipient;
        uint256 amount;
        uint64 unlockAt;
        uint64 reclaimAt; // 0 = never reclaimable
        uint16 feeBpsAtCreation;
        Status status;
        bytes32 orderId;
    }

    address public owner;
    /// @notice Fixed at deployment — not even the owner can redirect fees.
    address public immutable treasury;
    uint16 public feeBps; // applies to locks created AFTER a change, never before

    uint16 public constant MAX_FEE_BPS = 100;        // 1% hard cap
    uint256 public constant MAX_LOCK_DURATION = 366 days;
    uint256 public constant MIN_RECLAIM_GRACE = 30 days;
    uint256 public constant MAX_BATCH = 100;

    uint256 public nextId;
    mapping(uint256 => Lock) public locks;

    event SendScheduled(
        uint256 indexed id,
        bytes32 indexed orderId,
        address indexed recipient,
        address sender,
        uint256 amount,
        uint64 unlockAt,
        uint64 reclaimAt
    );
    event Released(uint256 indexed id, bytes32 indexed orderId, address indexed recipient, uint256 netAmount, uint256 feeAmount);
    event Reclaimed(uint256 indexed id, address indexed sender, uint256 amount);
    event FeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error UnlockNotInFuture();
    error LockTooLong();
    error GraceTooShort();
    error BatchInvalid();
    error ValueMismatch();
    error LockNotFound();
    error NotPending();
    error StillLocked();
    error NotReclaimable();
    error ReclaimNotOpen();
    error OnlySender();
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
    // Creation
    // ---------------------------------------------------------------

    /// @param reclaimGrace 0 = never reclaimable (committed / wage mode);
    ///        otherwise seconds after unlock before sender may reclaim,
    ///        floored at MIN_RECLAIM_GRACE — the recipient's exclusive window.
    function createSend(
        address recipient,
        uint64 unlockAt,
        uint64 reclaimGrace,
        bytes32 orderId
    ) external payable returns (uint256 id) {
        id = _create(recipient, msg.value, unlockAt, reclaimGrace, orderId);
    }

    /// @notice Payroll batch: one transaction, many locks, one unlock moment.
    function createBatch(
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint64 unlockAt,
        uint64 reclaimGrace,
        bytes32[] calldata orderIds
    ) external payable returns (uint256 firstId) {
        uint256 n = recipients.length;
        if (n == 0 || n > MAX_BATCH || amounts.length != n || orderIds.length != n) revert BatchInvalid();
        uint256 total = 0;
        for (uint256 i = 0; i < n; i++) total += amounts[i];
        if (total != msg.value) revert ValueMismatch();

        firstId = nextId;
        for (uint256 i = 0; i < n; i++) {
            _create(recipients[i], amounts[i], unlockAt, reclaimGrace, orderIds[i]);
        }
    }

    function _create(
        address recipient,
        uint256 amount,
        uint64 unlockAt,
        uint64 reclaimGrace,
        bytes32 orderId
    ) internal returns (uint256 id) {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (unlockAt <= block.timestamp) revert UnlockNotInFuture();
        if (unlockAt > block.timestamp + MAX_LOCK_DURATION) revert LockTooLong();
        if (reclaimGrace != 0 && reclaimGrace < MIN_RECLAIM_GRACE) revert GraceTooShort();

        uint64 reclaimAt = reclaimGrace == 0 ? 0 : unlockAt + reclaimGrace;

        id = nextId++;
        locks[id] = Lock({
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            unlockAt: unlockAt,
            reclaimAt: reclaimAt,
            feeBpsAtCreation: feeBps,
            status: Status.Pending,
            orderId: orderId
        });

        emit SendScheduled(id, orderId, recipient, msg.sender, amount, unlockAt, reclaimAt);
    }

    // ---------------------------------------------------------------
    // Settlement
    // ---------------------------------------------------------------

    /// @notice Permissionless after unlock — but funds can only go to the
    ///         recipient fixed at creation, at the fee snapshotted at creation.
    function release(uint256 id) external {
        Lock storage l = locks[id];
        if (l.sender == address(0)) revert LockNotFound();
        if (l.status != Status.Pending) revert NotPending();
        if (block.timestamp < l.unlockAt) revert StillLocked();

        l.status = Status.Released; // effects before interactions

        uint256 fee = (l.amount * l.feeBpsAtCreation) / 10_000;
        uint256 net = l.amount - fee;
        emit Released(id, l.orderId, l.recipient, net, fee);

        (bool ok, ) = l.recipient.call{value: net}("");
        if (!ok) revert TransferFailed();
        if (fee > 0) {
            (bool okFee, ) = treasury.call{value: fee}("");
            if (!okFee) revert TransferFailed();
        }
    }

    /// @notice Only for locks created WITH a reclaim window, only by the
    ///         original sender, only after the recipient's exclusive window
    ///         has fully passed, only while still unclaimed. Full refund, no fee.
    function reclaim(uint256 id) external {
        Lock storage l = locks[id];
        if (l.sender == address(0)) revert LockNotFound();
        if (msg.sender != l.sender) revert OnlySender();
        if (l.status != Status.Pending) revert NotPending();
        if (l.reclaimAt == 0) revert NotReclaimable();
        if (block.timestamp < l.reclaimAt) revert ReclaimNotOpen();

        l.status = Status.Reclaimed; // effects before interactions
        emit Reclaimed(id, l.sender, l.amount);

        (bool ok, ) = l.sender.call{value: l.amount}("");
        if (!ok) revert TransferFailed();
    }

    // ---------------------------------------------------------------
    // Admin — future fees only; zero power over locked funds
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

    /// @dev Funds enter only through createSend/createBatch, each bound to a lock.
    receive() external payable {
        revert ZeroAmount();
    }
}
