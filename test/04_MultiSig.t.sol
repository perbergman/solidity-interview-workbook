// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../solutions/04_MultiSig.sol";

// Covers test-specs/04_MultiSig.md.

contract Target {
    uint256 public x;

    function setX(uint256 x_) external payable {
        x = x_;
    }
}

contract MultiSigTest is Test {
    MultiSig internal wallet;
    Target internal target;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function owners() internal view returns (address[] memory o) {
        o = new address[](3);
        o[0] = alice;
        o[1] = bob;
        o[2] = carol;
    }

    function setUp() public {
        wallet = new MultiSig(owners(), 2);
        target = new Target();
        vm.deal(address(wallet), 10 ether); // fundable thanks to receive()
    }

    // duplicate owners rejected
    function test_DuplicateOwnersRejected() public {
        address[] memory dup = new address[](2);
        dup[0] = alice;
        dup[1] = alice;
        vm.expectRevert();
        new MultiSig(dup, 1);
    }

    // invalid threshold rejected
    function test_InvalidThresholdRejected() public {
        vm.expectRevert();
        new MultiSig(owners(), 0);
        vm.expectRevert();
        new MultiSig(owners(), 4);
    }

    // non-owner cannot submit/approve/execute
    function test_NonOwnerCannotSubmitApproveExecute() public {
        vm.prank(alice);
        uint256 id = wallet.submit(address(target), 0, "");

        address rando = makeAddr("rando");
        vm.startPrank(rando);
        vm.expectRevert(MultiSig.NotOwner.selector);
        wallet.submit(address(target), 0, "");
        vm.expectRevert(MultiSig.NotOwner.selector);
        wallet.approve(id);
        vm.expectRevert(MultiSig.NotOwner.selector);
        wallet.execute(id);
        vm.stopPrank();
    }

    // duplicate approval rejected
    function test_DuplicateApprovalRejected() public {
        vm.prank(alice);
        uint256 id = wallet.submit(address(target), 0, "");
        vm.startPrank(alice);
        wallet.approve(id);
        vm.expectRevert(MultiSig.AlreadyApproved.selector);
        wallet.approve(id);
        vm.stopPrank();
    }

    // revoke lowers approvals
    function test_RevokeLowersApprovals() public {
        vm.prank(alice);
        uint256 id = wallet.submit(address(target), 0, "");
        vm.prank(alice);
        wallet.approve(id);
        vm.prank(bob);
        wallet.approve(id);

        vm.prank(bob);
        wallet.revoke(id);

        // back below threshold: execution must fail
        vm.prank(alice);
        vm.expectRevert(MultiSig.ThresholdNotMet.selector);
        wallet.execute(id);
    }

    // below-threshold execute rejected
    function test_BelowThresholdExecuteRejected() public {
        vm.prank(alice);
        uint256 id = wallet.submit(address(target), 0, "");
        vm.prank(alice);
        wallet.approve(id);
        vm.prank(alice);
        vm.expectRevert(MultiSig.ThresholdNotMet.selector);
        wallet.execute(id);
    }

    // target call executes at threshold — calldata runs AND value moves,
    // with the target seeing msg.sender == the wallet
    function test_TargetCallExecutesAtThreshold() public {
        vm.prank(alice);
        uint256 id = wallet.submit(
            address(target), 1 ether, abi.encodeCall(Target.setX, (42))
        );
        vm.prank(alice);
        wallet.approve(id);
        vm.prank(bob);
        wallet.approve(id);

        vm.prank(carol); // any owner may trigger execution
        wallet.execute(id);

        assertEq(target.x(), 42);
        assertEq(address(target).balance, 1 ether);
        assertEq(address(wallet).balance, 9 ether);
    }

    // transaction cannot execute twice
    function test_CannotExecuteTwice() public {
        vm.prank(alice);
        uint256 id = wallet.submit(address(target), 0, abi.encodeCall(Target.setX, (7)));
        vm.prank(alice);
        wallet.approve(id);
        vm.prank(bob);
        wallet.approve(id);
        vm.prank(alice);
        wallet.execute(id);

        vm.prank(alice);
        vm.expectRevert(MultiSig.InvalidTransaction.selector);
        wallet.execute(id);
    }
}
