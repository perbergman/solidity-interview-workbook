// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);

    function decimals() external view returns (uint8);
}

/*
 * INTERVIEW NOTES
 * - Chainlink-shaped feed. The validation trio is the whole exercise:
 *   (1) answer > 0 — it's int256, feeds CAN return zero/negative;
 *   (2) updatedAt != 0 — incomplete round;
 *   (3) staleness — block.timestamp - updatedAt vs maxAge, where maxAge
 *       should track the feed's heartbeat (feeds update on deviation OR
 *       heartbeat; a "fresh" price can be heartbeat-old and still valid).
 * - Decimals normalization to 1e18 fixed point: feeds are usually 8 dp,
 *   never assume — read decimals(). Mixed-scale math is a whole bug class.
 * - What production adds: min/max answer sanity bounds (circuit-breaker
 *   feeds pin to a cap during crashes — LUNA-style), L2 sequencer-uptime
 *   feed check before trusting freshness on rollups, and a fallback oracle.
 * - The negative space: NEVER use a DEX spot price as an oracle — flash
 *   loans move it within one transaction. TWAPs resist intra-block
 *   manipulation; Chainlink aggregates off-chain signers. This consumer
 *   trusts the feed entirely — the trust boundary IS the feed address.
 * - maxAge immutable per consumer: different uses want different bounds
 *   (liquidations tight, display loose).
 */
contract OracleConsumer {
    error InvalidPrice();
    error StalePrice();

    IPriceFeed public immutable feed;
    uint256 public immutable maxAge;

    constructor(IPriceFeed feed_, uint256 maxAge_) {
        feed = feed_;
        maxAge = maxAge_;
    }

    function latestPrice18() external view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0 || block.timestamp - updatedAt > maxAge) revert StalePrice();

        uint8 d = feed.decimals();
        uint256 value = uint256(answer);
        if (d < 18) return value * (10 ** (18 - d));
        if (d > 18) return value / (10 ** (d - 18));
        return value;
    }
}
