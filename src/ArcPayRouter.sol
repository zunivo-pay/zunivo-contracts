// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ArcPayRouter
/// @notice Minimal non-custodial payment router for Arc (Chain ID 5042002),
///         where USDC is the native gas token (18 decimals at the native layer).
///         Funds are atomically forwarded to the merchant within the same tx —
///         the contract NEVER holds balances between transactions.
contract ArcPayRouter {
    address public owner;
    address public feeCollector;

    /// @notice Protocol fee in basis points (1 bps = 0.01%). Default 0.
    uint16 public feeBps;

    /// @notice Hard cap: fee can never exceed 1%, even by owner action.
    uint16 public constant MAX_FEE_BPS = 100;

    event PaymentReceived(
        bytes32 indexed orderId,
        address indexed payer,
        address indexed merchant,
        uint256 grossAmount,
        uint256 feeAmount
    );
    event FeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error FeeTooHigh();
    error NativeTransferFailed();

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
    function pay(bytes32 orderId, address merchant) external payable {
        if (merchant == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();

        uint256 fee = (msg.value * feeBps) / 10_000;
        uint256 net = msg.value - fee;

        (bool okMerchant, ) = merchant.call{value: net}("");
        if (!okMerchant) revert NativeTransferFailed();

        if (fee > 0) {
            (bool okFee, ) = feeCollector.call{value: fee}("");
            if (!okFee) revert NativeTransferFailed();
        }

        emit PaymentReceived(orderId, msg.sender, merchant, msg.value, fee);
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

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @dev Reject stray direct transfers: every payment must carry an orderId
    ///      through `pay`, otherwise reconciliation breaks by design.
    receive() external payable {
        revert ZeroAmount();
    }
}
