// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ArcPayRouter
/// @notice Minimal non-custodial payment router for Arc (Chain ID 5042002),
///         where USDC is the native gas token (18 decimals at the native layer).
///         Funds are atomically forwarded to the merchant within the same tx —
///         the contract NEVER holds balances between transactions.
contract ArcPayRouter {
    address public owner;
    /// @notice Two-step ownership handoff (L-3): a fat-fingered/compromised
    ///         transfer cannot take effect until the intended address accepts.
    address public pendingOwner;
    address public feeCollector;

    /// @notice Protocol fee in basis points (1 bps = 0.01%). Default 0.
    uint16 public feeBps;

    /// @notice Hard cap: fee can never exceed 1%, even by owner action.
    uint16 public constant MAX_FEE_BPS = 100;

    /// @notice Fees that could not be pushed to `feeCollector` at pay time are
    ///         credited here and pulled later (L-1). A reverting fee sink can
    ///         therefore never block a merchant payment. This is the ONLY balance
    ///         the router ever holds between transactions, and it is fee-only —
    ///         never user principal (the merchant leg settles atomically).
    mapping(address => uint256) public owedFees;

    event PaymentReceived(
        bytes32 indexed orderId,
        address indexed payer,
        address indexed merchant,
        uint256 grossAmount,
        uint256 feeAmount
    );
    event FeeAccrued(address indexed collector, uint256 amount);
    event FeeWithdrawn(address indexed collector, uint256 amount);
    event FeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error ZeroAmount();
    error FeeTooHigh();
    error NativeTransferFailed();
    error NothingOwed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _feeCollector) {
        if (_feeCollector == address(0)) revert ZeroAddress();
        owner = msg.sender;
        feeCollector = _feeCollector;
    }

    /// @notice Pay a merchant in native USDC. The full amount minus the
    ///         protocol fee is forwarded to `merchant` in the same transaction.
    ///         The merchant leg is atomic (reverts if the merchant can't receive
    ///         — the payer simply keeps their funds and re-routes; nothing is
    ///         held). The fee leg NEVER reverts a payment: a fee that can't be
    ///         pushed is accrued for later pull (L-1).
    function pay(bytes32 orderId, address merchant) external payable {
        if (merchant == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();

        uint256 fee = (msg.value * feeBps) / 10_000;
        uint256 net = msg.value - fee;

        (bool okMerchant, ) = merchant.call{value: net}("");
        if (!okMerchant) revert NativeTransferFailed();

        if (fee > 0) {
            (bool okFee, ) = feeCollector.call{value: fee}("");
            if (!okFee) {
                owedFees[feeCollector] += fee; // accrue instead of reverting the payment
                emit FeeAccrued(feeCollector, fee);
            }
        }

        emit PaymentReceived(orderId, msg.sender, merchant, msg.value, fee);
    }

    /// @notice Pull accrued fees. Callable by anyone; funds only ever go to the
    ///         credited collector address, so this is permissionless and safe.
    function withdrawFees(address collector) external {
        uint256 amt = owedFees[collector];
        if (amt == 0) revert NothingOwed();
        owedFees[collector] = 0; // effects before interaction
        emit FeeWithdrawn(collector, amt);
        (bool ok, ) = collector.call{value: amt}("");
        if (!ok) revert NativeTransferFailed();
    }

    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit FeeBpsUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    function setFeeCollector(address newCollector) external onlyOwner {
        if (newCollector == address(0)) revert ZeroAddress();
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeCollector = newCollector;
    }

    // ---------------------------------------------------------------
    // Ownership — two-step (L-3)
    // ---------------------------------------------------------------

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /// @dev Reject stray direct transfers: every payment must carry an orderId
    ///      through `pay`, otherwise reconciliation breaks by design.
    receive() external payable {
        revert ZeroAmount();
    }
}
