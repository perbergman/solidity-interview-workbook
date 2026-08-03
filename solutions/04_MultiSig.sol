// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * INTERVIEW NOTES
 * - The wallet is an IDENTITY: execute() makes the target see msg.sender ==
 *   this contract. The m-of-n logic replaces a private key. (tx.origin still
 *   points at the signing EOA — why tx.origin auth breaks smart accounts.)
 * - txn.executed = true BEFORE the call (CEI): the target — arbitrary code —
 *   could otherwise reenter execute(id) and run the payload twice.
 * - Approvals are ON-CHAIN: n owners = n transactions. Gnosis Safe instead
 *   verifies m EIP-712 off-chain signatures in one execTransaction — the
 *   standard "how would you improve this" answer.
 * - Only plain CALL here. Safe also offers operation=DelegateCall (run
 *   foreign code in the wallet's own storage/identity) — powerful and how
 *   the Bybit hack drained $1.5B via a malicious signed delegatecall.
 * - Empty receive() is load-bearing: without it the wallet cannot be funded
 *   by plain transfer. Production emits a Deposit event there.
 * - Gaps vs production: NO events at all (Submit/Approve/Revoke/Execute
 *   should emit — indexers are blind here); owner set and threshold are
 *   fixed forever (Safe lets the wallet reconfigure itself via execute).
 * - approvedBy double-mapping + counter: O(1) checks, no owner iteration.
 */
contract MultiSig {
    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvals;
    }

    error NotOwner();
    error InvalidTransaction();
    error AlreadyApproved();
    error NotApproved();
    error ThresholdNotMet();
    error ExecutionFailed();

    mapping(address => bool) public isOwner;
    address[] public owners;
    uint256 public immutable threshold;
    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public approvedBy;

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    constructor(address[] memory owners_, uint256 threshold_) {
        require(owners_.length > 0);
        require(threshold_ > 0 && threshold_ <= owners_.length);
        for (uint256 i; i < owners_.length; i++) {
            address owner = owners_[i];
            require(owner != address(0) && !isOwner[owner]);
            isOwner[owner] = true;
            owners.push(owner);
        }
        threshold = threshold_;
    }

    function submit(address target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 id)
    {
        id = transactions.length;
        transactions.push(Transaction(target, value, data, false, 0));
    }

    function approve(uint256 id) external onlyOwner {
        Transaction storage txn = transactions[id];
        if (txn.executed) revert InvalidTransaction();
        if (approvedBy[id][msg.sender]) revert AlreadyApproved();
        approvedBy[id][msg.sender] = true;
        txn.approvals++;
    }

    function revoke(uint256 id) external onlyOwner {
        Transaction storage txn = transactions[id];
        if (txn.executed) revert InvalidTransaction();
        if (!approvedBy[id][msg.sender]) revert NotApproved();
        approvedBy[id][msg.sender] = false;
        txn.approvals--;
    }

    function execute(uint256 id) external onlyOwner {
        Transaction storage txn = transactions[id];
        if (txn.executed) revert InvalidTransaction();
        if (txn.approvals < threshold) revert ThresholdNotMet();
        txn.executed = true;
        (bool ok,) = txn.target.call{value: txn.value}(txn.data);
        if (!ok) revert ExecutionFailed();
    }

    receive() external payable {}
}
