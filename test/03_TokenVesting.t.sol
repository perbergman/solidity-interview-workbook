// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../solutions/03_TokenVesting.sol";

// Covers test-specs/03_Vesting.md.

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    MockToken internal token;
    TokenVesting internal vesting;
    address internal beneficiary = makeAddr("beneficiary");

    uint64 internal start;
    uint64 internal constant CLIFF = 365 days;
    uint64 internal constant DURATION = 4 * 365 days;
    uint256 internal constant TOTAL = 48_000e18;

    function setUp() public {
        token = new MockToken();
        start = uint64(block.timestamp);
        vesting = new TokenVesting(token, beneficiary, start, CLIFF, DURATION, TOTAL);
        token.mint(address(vesting), TOTAL); // pre-fund: solvency is assumed, not checked
    }

    // zero vested before cliff
    function test_ZeroVestedBeforeCliff() public {
        vm.warp(start + CLIFF - 1);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), 0);
        assertEq(vesting.releasableAmount(), 0);
        vm.prank(beneficiary);
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release();
    }

    // correct amount at cliff — the whole first year unlocks at once (catch-up)
    function test_CliffCatchUpAmount() public {
        vm.warp(start + CLIFF);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), TOTAL / 4);
        vm.prank(beneficiary);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL / 4);
    }

    // linear amount midway
    function test_LinearMidway() public {
        vm.warp(start + DURATION / 2);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), TOTAL / 2);
    }

    // full amount at end (exact — the terminal branch returns totalAllocation,
    // so integer-division dust cannot strand tokens)
    function test_FullAmountAtEnd() public {
        vm.warp(start + DURATION);
        assertEq(vesting.vestedAmount(uint64(block.timestamp)), TOTAL);
        vm.prank(beneficiary);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    // repeated release only sends delta
    function test_RepeatedReleaseSendsOnlyDelta() public {
        vm.warp(start + DURATION / 2);
        vm.prank(beneficiary);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), TOTAL / 2);

        vm.warp(start + (3 * uint256(DURATION)) / 4);
        vm.prank(beneficiary);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), (3 * TOTAL) / 4);
        assertEq(vesting.released(), (3 * TOTAL) / 4);

        // nothing new vested, nothing to release
        vm.prank(beneficiary);
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release();
    }

    // only beneficiary can release
    function test_OnlyBeneficiaryCanRelease() public {
        vm.warp(start + DURATION);
        vm.prank(makeAddr("rando"));
        vm.expectRevert(TokenVesting.Unauthorized.selector);
        vesting.release();
    }
}
