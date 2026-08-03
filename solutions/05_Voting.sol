// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * INTERVIEW NOTES
 * - One-address-one-vote is SYBIL-VULNERABLE: addresses are free, so this
 *   only works with an off-chain identity gate. Production DAOs use token-
 *   weighted voting with SNAPSHOTS (ERC20Votes checkpoints, "voting power at
 *   proposal-creation block") — otherwise one balance votes, transfers, and
 *   votes again from the next address.
 * - block.timestamp bounds: proposers/validators can nudge seconds, not
 *   minutes — fine for day-long windows, never for tight deadlines.
 * - hasVoted double-mapping mirrors the MultiSig's approvedBy: O(1) dedupe.
 * - Proposal storage pointer (`Proposal storage p`) mutates in place; `memory`
 *   here would be a classic silent bug (writes to a throwaway copy).
 * - Bare require() vs custom errors used inconsistently — fine for a stub,
 *   flag it; also NO events (ProposalCreated/Voted should emit for indexers).
 * - String description stored on-chain is expensive calldata+storage;
 *   production stores a content hash / IPFS pointer.
 * - passed() is simple majority with no quorum and no minimum turnout —
 *   1 yes / 0 no passes. Real governance adds quorum, and usually a timelock
 *   between passing and execution so users can exit before a change lands.
 */
contract Voting {
    struct Proposal {
        string description;
        uint64 start;
        uint64 end;
        uint256 yesVotes;
        uint256 noVotes;
    }

    error VotingClosed();
    error AlreadyVoted();

    address public immutable admin;
    Proposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    constructor() {
        admin = msg.sender;
    }

    function createProposal(string calldata description, uint64 start, uint64 end)
        external
        returns (uint256 id)
    {
        require(msg.sender == admin);
        require(start < end);
        id = proposals.length;
        proposals.push(Proposal(description, start, end, 0, 0));
    }

    function vote(uint256 id, bool support) external {
        Proposal storage p = proposals[id];
        if (block.timestamp < p.start || block.timestamp > p.end) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();
        hasVoted[id][msg.sender] = true;
        if (support) p.yesVotes++;
        else p.noVotes++;
    }

    function passed(uint256 id) external view returns (bool) {
        Proposal storage p = proposals[id];
        require(block.timestamp > p.end);
        return p.yesVotes > p.noVotes;
    }
}
