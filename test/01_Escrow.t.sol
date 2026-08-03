// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../solutions/01_Escrow.sol";

// Covers test-specs/01_Escrow.md. Template for the other nine:
// swap the import to ../exercises/... to test your own implementation.

contract ReentrantBuyer {
    Escrow public escrow;
    uint256 public entries;

    function deploy(address seller, uint256 price) external {
        escrow = new Escrow(seller, price);
    }

    function fund() external payable {
        escrow.fund{value: msg.value}();
    }

    function refund() external {
        escrow.refund();
    }

    receive() external payable {
        entries++;
        if (entries < 3) escrow.refund(); // reenter mid-refund
    }
}

contract EscrowTest is Test {
    Escrow internal escrow;
    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    uint256 internal constant PRICE = 1 ether;

    function setUp() public {
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        escrow = new Escrow(seller, PRICE);
    }

    // constructor rejects zero seller or zero price
    function test_ConstructorRejectsZeroSellerOrPrice() public {
        vm.expectRevert(Escrow.InvalidAmount.selector);
        new Escrow(address(0), PRICE);
        vm.expectRevert(Escrow.InvalidAmount.selector);
        new Escrow(seller, 0);
    }

    // only buyer can fund
    function test_OnlyBuyerCanFund() public {
        address rando = makeAddr("rando");
        vm.deal(rando, PRICE);
        vm.prank(rando);
        vm.expectRevert(Escrow.Unauthorized.selector);
        escrow.fund{value: PRICE}();
    }

    // funding amount must equal price
    function test_FundingAmountMustEqualPrice() public {
        vm.startPrank(buyer);
        vm.expectRevert(Escrow.InvalidAmount.selector);
        escrow.fund{value: PRICE - 1}();
        vm.expectRevert(Escrow.InvalidAmount.selector);
        escrow.fund{value: PRICE + 1}();
        vm.stopPrank();
    }

    // cannot fund twice
    function test_CannotFundTwice() public {
        vm.startPrank(buyer);
        escrow.fund{value: PRICE}();
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.fund{value: PRICE}();
        vm.stopPrank();
    }

    // only buyer can release/refund
    function test_OnlyBuyerCanReleaseOrRefund() public {
        vm.prank(buyer);
        escrow.fund{value: PRICE}();
        vm.startPrank(seller);
        vm.expectRevert(Escrow.Unauthorized.selector);
        escrow.release();
        vm.expectRevert(Escrow.Unauthorized.selector);
        escrow.refund();
        vm.stopPrank();
    }

    // cannot release before funding
    function test_CannotReleaseBeforeFunding() public {
        vm.prank(buyer);
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.release();
    }

    // seller receives funds
    function test_SellerReceivesFundsOnRelease() public {
        vm.startPrank(buyer);
        escrow.fund{value: PRICE}();
        escrow.release();
        vm.stopPrank();
        assertEq(seller.balance, PRICE);
        assertEq(address(escrow).balance, 0);
        assertEq(uint8(escrow.state()), uint8(Escrow.State.Released));
    }

    // buyer receives refund
    function test_BuyerReceivesRefund() public {
        vm.startPrank(buyer);
        escrow.fund{value: PRICE}();
        uint256 before = buyer.balance;
        escrow.refund();
        vm.stopPrank();
        assertEq(buyer.balance, before + PRICE);
        assertEq(uint8(escrow.state()), uint8(Escrow.State.Refunded));
    }

    // cannot settle twice
    function test_CannotSettleTwice() public {
        vm.startPrank(buyer);
        escrow.fund{value: PRICE}();
        escrow.release();
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.release();
        vm.expectRevert(Escrow.InvalidState.selector);
        escrow.refund();
        vm.stopPrank();
    }

    // malicious recipient cannot reenter
    function test_MaliciousBuyerCannotReenterRefund() public {
        ReentrantBuyer attacker = new ReentrantBuyer();
        vm.deal(address(attacker), PRICE);
        attacker.deploy(seller, PRICE);
        attacker.fund{value: PRICE}();

        // reentrant refund() hits the state check (already Refunded) inside
        // the nested call; its revert bubbles up through receive() and fails
        // the outer transfer, so the whole refund reverts — funds stay put.
        vm.expectRevert(Escrow.TransferFailed.selector);
        attacker.refund();
        assertEq(address(attacker.escrow()).balance, PRICE);
    }
}
