// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../solutions/02_InterviewToken.sol";

// Covers test-specs/02_ERC20.md.

contract InterviewTokenTest is Test {
    InterviewToken internal token;
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new InterviewToken(admin);
    }

    // admin receives roles
    function test_AdminReceivesRoles() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }

    // minter can mint
    function test_MinterCanMint() public {
        vm.prank(admin);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.totalSupply(), 100e18);
    }

    // unauthorized account cannot mint
    function test_UnauthorizedCannotMint() public {
        bytes32 role = token.MINTER_ROLE(); // cache: a call here would consume the prank
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role
            )
        );
        token.mint(alice, 1);
    }

    // transfers work while unpaused
    function test_TransfersWorkWhileUnpaused() public {
        vm.prank(admin);
        token.mint(alice, 100e18);
        vm.prank(alice);
        token.transfer(bob, 40e18);
        assertEq(token.balanceOf(alice), 60e18);
        assertEq(token.balanceOf(bob), 40e18);
    }

    // pauser can pause
    function test_PauserCanPause() public {
        vm.prank(admin);
        token.pause();
        assertTrue(token.paused());
        vm.prank(admin);
        token.unpause();
        assertFalse(token.paused());
    }

    // transfers/mint behavior matches intended paused policy:
    // _update is gated, so pause blocks transfer AND mint (and burn).
    function test_PausedPolicyBlocksTransferAndMint() public {
        vm.startPrank(admin);
        token.mint(alice, 100e18);
        token.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(alice, 1);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 1);
    }

    // unauthorized account cannot pause
    function test_UnauthorizedCannotPause() public {
        bytes32 role = token.PAUSER_ROLE();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role
            )
        );
        token.pause();
    }
}
