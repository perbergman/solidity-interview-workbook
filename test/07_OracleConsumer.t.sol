// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../solutions/07_OracleConsumer.sol";

// Covers test-specs/07_Oracle.md.

contract MockFeed is IPriceFeed {
    int256 public answer;
    uint256 public updatedAt;
    uint8 private feedDecimals;

    function set(int256 answer_, uint256 updatedAt_, uint8 decimals_) external {
        answer = answer_;
        updatedAt = updatedAt_;
        feedDecimals = decimals_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function decimals() external view returns (uint8) {
        return feedDecimals;
    }
}

contract OracleConsumerTest is Test {
    MockFeed internal feed;
    OracleConsumer internal consumer;
    uint256 internal constant MAX_AGE = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000); // realistic clock so staleness math is meaningful
        feed = new MockFeed();
        consumer = new OracleConsumer(feed, MAX_AGE);
    }

    // positive fresh value returned
    function test_PositiveFreshValueReturned() public {
        feed.set(3000e8, block.timestamp, 8);
        assertEq(consumer.latestPrice18(), 3000e18);
    }

    // decimal normalization up and down
    function test_DecimalNormalization() public {
        feed.set(3000e8, block.timestamp, 8); // scale up: 8 -> 18
        assertEq(consumer.latestPrice18(), 3000e18);

        feed.set(3000e18, block.timestamp, 18); // already 18: unchanged
        assertEq(consumer.latestPrice18(), 3000e18);

        feed.set(3000e20, block.timestamp, 20); // scale down: 20 -> 18
        assertEq(consumer.latestPrice18(), 3000e18);
    }

    // zero/negative answer rejected
    function test_ZeroOrNegativeAnswerRejected() public {
        feed.set(0, block.timestamp, 8);
        vm.expectRevert(OracleConsumer.InvalidPrice.selector);
        consumer.latestPrice18();

        feed.set(-1e8, block.timestamp, 8);
        vm.expectRevert(OracleConsumer.InvalidPrice.selector);
        consumer.latestPrice18();
    }

    // stale timestamp rejected (boundary: exactly maxAge old is still valid)
    function test_StaleTimestampRejected() public {
        feed.set(3000e8, block.timestamp, 8);
        vm.warp(block.timestamp + MAX_AGE);
        assertEq(consumer.latestPrice18(), 3000e18); // age == maxAge: ok

        vm.warp(block.timestamp + 1); // age == maxAge + 1: stale
        vm.expectRevert(OracleConsumer.StalePrice.selector);
        consumer.latestPrice18();
    }

    // zero timestamp rejected (incomplete round)
    function test_ZeroTimestampRejected() public {
        feed.set(3000e8, 0, 8);
        vm.expectRevert(OracleConsumer.StalePrice.selector);
        consumer.latestPrice18();
    }
}
