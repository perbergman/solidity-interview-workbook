// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../solutions/05_Voting.sol";

// Covers test-specs/05_Voting.md.

contract VotingTest is Test {
    Voting internal voting;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint64 internal start;
    uint64 internal end;

    function setUp() public {
        voting = new Voting(); // this test contract is admin
        start = uint64(block.timestamp + 1 hours);
        end = uint64(block.timestamp + 1 days);
    }

    function createOpenProposal() internal returns (uint256 id) {
        id = voting.createProposal("prop", start, end);
        vm.warp(start);
    }

    // unauthorized proposal creation rejected
    function test_UnauthorizedProposalCreationRejected() public {
        vm.prank(alice);
        vm.expectRevert();
        voting.createProposal("prop", start, end);
    }

    // invalid time window rejected
    function test_InvalidTimeWindowRejected() public {
        vm.expectRevert();
        voting.createProposal("prop", end, start); // start >= end
        vm.expectRevert();
        voting.createProposal("prop", start, start);
    }

    // vote before start rejected
    function test_VoteBeforeStartRejected() public {
        uint256 id = voting.createProposal("prop", start, end);
        vm.prank(alice);
        vm.expectRevert(Voting.VotingClosed.selector);
        voting.vote(id, true);
    }

    // duplicate vote rejected
    function test_DuplicateVoteRejected() public {
        uint256 id = createOpenProposal();
        vm.startPrank(alice);
        voting.vote(id, true);
        vm.expectRevert(Voting.AlreadyVoted.selector);
        voting.vote(id, false); // switching sides doesn't help either
        vm.stopPrank();
    }

    // vote after end rejected
    function test_VoteAfterEndRejected() public {
        uint256 id = createOpenProposal();
        vm.warp(end + 1);
        vm.prank(alice);
        vm.expectRevert(Voting.VotingClosed.selector);
        voting.vote(id, true);
    }

    // passed() only after close
    function test_PassedOnlyAfterClose() public {
        uint256 id = createOpenProposal();
        vm.prank(alice);
        voting.vote(id, true);

        vm.expectRevert(); // still open (and boundary: timestamp == end is still open)
        voting.passed(id);
        vm.warp(end);
        vm.expectRevert();
        voting.passed(id);

        vm.warp(end + 1);
        assertTrue(voting.passed(id));
    }

    // tie behavior documented: strict majority required — a tie FAILS
    function test_TieFails() public {
        uint256 id = createOpenProposal();
        vm.prank(alice);
        voting.vote(id, true);
        vm.prank(bob);
        voting.vote(id, false);
        vm.warp(end + 1);
        assertFalse(voting.passed(id)); // 1-1: yesVotes > noVotes is false
    }
}
