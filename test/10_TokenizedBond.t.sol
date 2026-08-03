// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../solutions/10_TokenizedBond.sol";

// Covers test-specs/10_Bond.md.
//
// Solvency assumptions (documented per spec): nothing escrows faceValue at
// issuance and coupon credits are issuer-fiat numbers — claims/redemptions
// are only as good as the ETH the issuer parks here via receive(). Tests
// fund the contract explicitly; the underfunded case is exercised last.

contract TokenizedBondTest is Test {
    TokenizedBond internal bond;
    address internal investor = makeAddr("investor");
    address internal outsider = makeAddr("outsider");

    uint64 internal maturity;
    uint256 internal constant FACE = 1 ether;

    function setUp() public {
        maturity = uint64(block.timestamp + 30 days);
        bond = new TokenizedBond(maturity, FACE); // this test contract is issuer
        vm.deal(address(this), 100 ether);
        (bool ok,) = address(bond).call{value: 50 ether}(""); // issuer funds solvency
        assertTrue(ok);
    }

    // only issuer can allowlist and issue
    function test_OnlyIssuerCanAllowlistAndIssue() public {
        vm.startPrank(outsider);
        vm.expectRevert(TokenizedBond.Unauthorized.selector);
        bond.setEligible(investor, true);
        vm.expectRevert(TokenizedBond.Unauthorized.selector);
        bond.issue(investor, 1);
        vm.expectRevert(TokenizedBond.Unauthorized.selector);
        bond.creditCoupon(investor, 1 ether);
        vm.stopPrank();
    }

    // ineligible investor rejected
    function test_IneligibleInvestorRejected() public {
        vm.expectRevert(TokenizedBond.NotEligible.selector);
        bond.issue(investor, 5);

        // eligibility can be revoked again
        bond.setEligible(investor, true);
        bond.issue(investor, 5);
        bond.setEligible(investor, false);
        vm.expectRevert(TokenizedBond.NotEligible.selector);
        bond.issue(investor, 1);
    }

    // issue after maturity rejected
    function test_IssueAfterMaturityRejected() public {
        bond.setEligible(investor, true);
        vm.warp(maturity);
        vm.expectRevert(TokenizedBond.Matured.selector);
        bond.issue(investor, 1);
    }

    // coupon credit is pull-based: issuer credits O(1), investor claims
    function test_CouponCreditIsPullBased() public {
        bond.creditCoupon(investor, 2 ether);
        assertEq(bond.couponCredit(investor), 2 ether);
        assertEq(investor.balance, 0); // nothing pushed

        vm.prank(investor);
        bond.claimCoupon();
        assertEq(investor.balance, 2 ether);
        assertEq(bond.couponCredit(investor), 0);
    }

    // coupon cannot be claimed twice
    function test_CouponCannotBeClaimedTwice() public {
        bond.creditCoupon(investor, 1 ether);
        vm.startPrank(investor);
        bond.claimCoupon();
        vm.expectRevert(TokenizedBond.NothingToClaim.selector);
        bond.claimCoupon();
        vm.stopPrank();
    }

    // redemption only after maturity
    function test_RedemptionOnlyAfterMaturity() public {
        bond.setEligible(investor, true);
        bond.issue(investor, 3);

        vm.prank(investor);
        vm.expectRevert(TokenizedBond.NotMatured.selector);
        bond.redeem();

        vm.warp(maturity);
        vm.prank(investor);
        bond.redeem();
        assertEq(investor.balance, 3 * FACE);
        assertEq(bond.balanceOf(investor), 0);
    }

    // redemption cannot happen twice (balance zeroing is the guard)
    function test_RedemptionCannotHappenTwice() public {
        bond.setEligible(investor, true);
        bond.issue(investor, 3);
        vm.warp(maturity);
        vm.startPrank(investor);
        bond.redeem();
        vm.expectRevert(TokenizedBond.NothingToClaim.selector);
        bond.redeem();
        vm.stopPrank();
    }

    // contract solvency assumptions documented: an underfunded bond's
    // redemption reverts at the transfer — issuer trust, not code, backs it
    function test_UnderfundedRedemptionReverts() public {
        TokenizedBond broke = new TokenizedBond(maturity, FACE); // never funded
        broke.setEligible(investor, true);
        broke.issue(investor, 3);
        vm.warp(maturity);
        vm.prank(investor);
        vm.expectRevert();
        broke.redeem();
    }
}
