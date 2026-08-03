// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../solutions/09_PausableTreasury.sol";

// Covers test-specs/09_Treasury.md.

contract ReentrantReceiver {
    PausableTreasury public treasury;

    constructor(PausableTreasury treasury_) {
        treasury = treasury_;
    }

    receive() external payable {
        // holds WITHDRAWER_ROLE in the test, so only the guard stops this
        treasury.withdraw(payable(address(this)), 1 ether);
    }
}

contract PausableTreasuryTest is Test {
    PausableTreasury internal treasury;
    address internal admin = makeAddr("admin");
    address internal payee = makeAddr("payee");

    event Deposited(address indexed from, uint256 amount);

    function setUp() public {
        treasury = new PausableTreasury(admin);
        vm.deal(address(this), 100 ether);
        (bool ok,) = address(treasury).call{value: 10 ether}("");
        assertTrue(ok);
    }

    // receive emits deposit event
    function test_ReceiveEmitsDepositEvent() public {
        vm.expectEmit(true, false, false, true, address(treasury));
        emit Deposited(address(this), 2 ether);
        (bool ok,) = address(treasury).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 12 ether);
    }

    // authorized withdrawal succeeds
    function test_AuthorizedWithdrawalSucceeds() public {
        vm.prank(admin);
        treasury.withdraw(payable(payee), 3 ether);
        assertEq(payee.balance, 3 ether);
        assertEq(address(treasury).balance, 7 ether);
    }

    // unauthorized withdrawal rejected
    function test_UnauthorizedWithdrawalRejected() public {
        address rando = makeAddr("rando");
        bytes32 role = treasury.WITHDRAWER_ROLE(); // cache: a call here would consume the prank
        vm.prank(rando);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, rando, role
            )
        );
        treasury.withdraw(payable(rando), 1 ether);
    }

    // over-withdrawal rejected (plus the other InvalidAmount guards)
    function test_OverWithdrawalRejected() public {
        vm.startPrank(admin);
        vm.expectRevert(PausableTreasury.InvalidAmount.selector);
        treasury.withdraw(payable(payee), 10 ether + 1);
        vm.expectRevert(PausableTreasury.InvalidAmount.selector);
        treasury.withdraw(payable(payee), 0);
        vm.expectRevert(PausableTreasury.InvalidAmount.selector);
        treasury.withdraw(payable(address(0)), 1 ether);
        vm.stopPrank();
    }

    // paused deposits/withdrawals rejected as designed:
    // pause gates BOTH receive() and withdraw()
    function test_PausedBlocksDepositsAndWithdrawals() public {
        vm.prank(admin);
        treasury.pause();

        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertFalse(ok); // deposit bounced (EnforcedPause inside receive)

        vm.prank(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        treasury.withdraw(payable(payee), 1 ether);

        // unpause restores both paths
        vm.prank(admin);
        treasury.unpause();
        (ok,) = address(treasury).call{value: 1 ether}("");
        assertTrue(ok);
        vm.prank(admin);
        treasury.withdraw(payable(payee), 1 ether);
        assertEq(payee.balance, 1 ether);
    }

    // reentrant receiver fails — even WITH the withdrawer role, the guard
    // trips inside its receive(), the send fails, and the outer call reverts
    function test_ReentrantReceiverFails() public {
        ReentrantReceiver attacker = new ReentrantReceiver(treasury);
        vm.startPrank(admin);
        treasury.grantRole(treasury.WITHDRAWER_ROLE(), address(attacker));
        vm.expectRevert(PausableTreasury.TransferFailed.selector);
        treasury.withdraw(payable(address(attacker)), 1 ether);
        vm.stopPrank();
        assertEq(address(treasury).balance, 10 ether); // nothing left the treasury
    }
}
