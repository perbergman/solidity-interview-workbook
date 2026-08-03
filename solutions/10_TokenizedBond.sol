// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * INTERVIEW NOTES
 * - The exercise's core constraint — "avoid looping over all holders" — is
 *   answered with the PULL pattern: issuer credits per-investor coupon
 *   entitlements (O(1) writes, no holder enumeration anywhere), investors
 *   claim individually. Unbounded loops over holders are a DoS: one growth
 *   spurt and the payout transaction exceeds block gas.
 * - claimCoupon zeroes the credit BEFORE the send; redeem() sets the flag
 *   and zeroes balance before paying — CEI on every ETH exit.
 * - Allowlist (eligible) = permissioned security: transfer restrictions are
 *   the defining difference from a free-floating ERC20 (real-world framing:
 *   Reg D/S transfer restrictions, ERC-1400/1404 standards).
 * - There is deliberately NO transfer function — positions are issuer-
 *   assigned and non-transferable, which sidesteps "is the recipient
 *   eligible" entirely. Adding transferability = enforcing the allowlist
 *   on every transfer path.
 * - balanceOf mimics ERC20 naming but this is NOT an ERC20 (no approve/
 *   transferFrom/events) — wallets can't see it; a production bond would
 *   likely BE a restricted ERC20 for composability.
 * - Trust model is issuer-heavy and worth stating: issuer credits coupons
 *   by fiat (not derived from balance × rate on-chain), and redemption
 *   solvency depends on the issuer funding the contract via receive() —
 *   nothing escrows faceValue at issuance.
 * - Double-redemption is prevented by ZEROING THE BALANCE, full stop — the
 *   coupon claim uses the identical zero-the-credit idiom. An earlier draft
 *   also kept a redeemed[addr] flag: redundant (balance is already the
 *   source of truth) and a latent lockout if issuance rules ever loosen —
 *   one state variable per fact, or the copies drift.
 * - units * faceValue: 0.8 checked arithmetic reverts on overflow for free.
 */
contract TokenizedBond {
    error Unauthorized();
    error NotEligible();
    error Matured();
    error NotMatured();
    error NothingToClaim();

    address public immutable issuer;
    uint64 public immutable maturity;
    uint256 public immutable faceValue;

    mapping(address => bool) public eligible;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public couponCredit;

    constructor(uint64 maturity_, uint256 faceValue_) {
        issuer = msg.sender;
        maturity = maturity_;
        faceValue = faceValue_;
    }

    modifier onlyIssuer() {
        if (msg.sender != issuer) revert Unauthorized();
        _;
    }

    function setEligible(address investor, bool allowed) external onlyIssuer {
        eligible[investor] = allowed;
    }

    function issue(address investor, uint256 units) external onlyIssuer {
        if (block.timestamp >= maturity) revert Matured();
        if (!eligible[investor]) revert NotEligible();
        balanceOf[investor] += units;
    }

    function creditCoupon(address investor, uint256 amount) external onlyIssuer {
        couponCredit[investor] += amount;
    }

    function claimCoupon() external {
        uint256 amount = couponCredit[msg.sender];
        if (amount == 0) revert NothingToClaim();
        couponCredit[msg.sender] = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok);
    }

    function redeem() external {
        if (block.timestamp < maturity) revert NotMatured();
        uint256 units = balanceOf[msg.sender];
        if (units == 0) revert NothingToClaim();
        balanceOf[msg.sender] = 0;
        uint256 amount = units * faceValue;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok);
    }

    receive() external payable {}
}
