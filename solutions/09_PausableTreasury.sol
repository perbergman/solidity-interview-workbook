// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
 * INTERVIEW NOTES
 * - Three orthogonal OZ mixins: AccessControl (who), Pausable (when),
 *   ReentrancyGuard (how) — same lock the hand-rolled Escrow builds, as a
 *   battle-tested transient-storage-based guard in current OZ.
 * - receive() is whenNotPaused: pausing blocks DEPOSITS too — a real design
 *   decision (refusing money vs refusing withdrawals are different risks).
 *   Forced ETH (selfdestruct push) still lands regardless — pause is not a
 *   balance freeze.
 * - Deposits emit an event precisely because plain transfers otherwise leave
 *   no log for indexers — the fix for the workbook MultiSig's silent gap.
 * - withdraw is PUSH payment to an arbitrary address, acceptable because
 *   it's role-gated (trusted caller). A permissionless variant would want
 *   pull-payments: credit balances, let payees withdraw().
 * - amount > address(this).balance check uses raw balance — fine here since
 *   there is no per-user accounting to desync; the moment you track
 *   individual deposits, switch to internal accounting (forced ETH again).
 * - Event after the external call is safe (events are effects-only, and
 *   nonReentrant holds), but strict CEI style would emit before the call.
 * - PAUSER/WITHDRAWER split: pause is incident response (low-privilege,
 *   grant widely); withdraw moves money (high-privilege, grant tightly).
 */
contract PausableTreasury is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    error InvalidAmount();
    error TransferFailed();

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(WITHDRAWER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    receive() external payable whenNotPaused {
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(address payable to, uint256 amount)
        external
        onlyRole(WITHDRAWER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (to == address(0) || amount == 0 || amount > address(this).balance) {
            revert InvalidAmount();
        }
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
