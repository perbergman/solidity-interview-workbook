// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/*
 * INTERVIEW NOTES
 * - OZ v5 funnels mint/burn/transfer through ONE hook: _update (v4 had
 *   _beforeTokenTransfer/_afterTokenTransfer). Overriding it with
 *   whenNotPaused pauses all three paths at once — including mint; if
 *   emergency-minting while paused must work, gate transfer only.
 * - AccessControl vs Ownable: granular grant/revoke per capability, admin
 *   can rotate a compromised minter without redeploying. Roles are just
 *   bytes32 keys (keccak of a label) into a nested mapping.
 * - Token "balances" are ordinary contract storage; nothing native moves.
 *   No payable anywhere — raw ETH sent here bounces (no receive/fallback).
 * - decimals() defaults to 18 in OZ; override if mimicking USDC (6).
 * - Not included, worth naming: cap (ERC20Capped), burn (ERC20Burnable),
 *   permit (ERC20Permit / EIP-2612 gasless approvals — modern default).
 * - DEFAULT_ADMIN_ROLE is root: production wants it behind a multisig +
 *   timelock, or AccessControlDefaultAdminRules for two-step transfer.
 */
contract InterviewToken is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(address admin) ERC20("Interview Token", "INT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // Every balance change funnels through one hook in OZ v5:
    //   mint(to, amt)          -> _mint(to, amt)   -> _update(0x0, to, amt)
    //   transfer(to, amt)      -> _transfer(...)   -> _update(from, to, amt)
    //   burn (if added)        -> _burn(from, amt) -> _update(from, 0x0, amt)
    // so the whenNotPaused override below gates all three paths at once.
    // (OZ v4 had a _beforeTokenTransfer/_afterTokenTransfer pair instead.)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
