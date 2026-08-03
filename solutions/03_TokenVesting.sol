// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
 * INTERVIEW NOTES
 * - Vesting math: nothing before cliff; AT the cliff the full linear accrual
 *   since start unlocks at once (catch-up), then linear to start+duration.
 *   vestedAmount is monotone non-decreasing — the invariant tests should pin.
 * - released-accumulator pattern: releasable = vested(now) - released. Claim
 *   in any increments, no per-claim schedule bookkeeping, idempotent.
 * - released += amount BEFORE safeTransfer: CEI — an ERC20 with hooks (or a
 *   malicious token) could otherwise reenter release() and double-claim.
 * - SafeERC20: absorbs non-standard tokens (USDT returns nothing; some return
 *   false instead of reverting). Raw token.transfer() is an audit finding.
 * - Silent assumptions to name: contract must be pre-funded with
 *   totalAllocation (nothing checks it); fee-on-transfer or rebasing tokens
 *   break the accounting (balance != totalAllocation - released).
 * - uint64 timestamps: fine until year ~584B, and lets start/cliff/duration
 *   pack with the address into fewer storage slots (moot here — immutable).
 * - Integer division rounds down: dust vests only at the final timestamp.
 * - Design choices to discuss: only beneficiary may release (could be
 *   permissionless — funds still go to beneficiary); no revoke() — real
 *   grants usually want employer clawback of the unvested remainder.
 */
contract TokenVesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable cliff;
    uint64 public immutable duration;
    uint256 public immutable totalAllocation;
    uint256 public released;

    error NothingToRelease();
    error Unauthorized();

    constructor(
        IERC20 token_,
        address beneficiary_,
        uint64 start_,
        uint64 cliffDuration_,
        uint64 duration_,
        uint256 totalAllocation_
    ) {
        require(address(token_) != address(0) && beneficiary_ != address(0));
        require(duration_ > 0 && cliffDuration_ <= duration_);
        token = token_;
        beneficiary = beneficiary_;
        start = start_;
        cliff = start_ + cliffDuration_;
        duration = duration_;
        totalAllocation = totalAllocation_;
    }

    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        if (timestamp < cliff) return 0;
        if (timestamp >= start + duration) return totalAllocation;
        return (totalAllocation * (timestamp - start)) / duration;
    }

    function releasableAmount() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    function release() external {
        if (msg.sender != beneficiary) revert Unauthorized();
        uint256 amount = releasableAmount();
        if (amount == 0) revert NothingToRelease();
        released += amount;
        token.safeTransfer(beneficiary, amount);
    }
}
