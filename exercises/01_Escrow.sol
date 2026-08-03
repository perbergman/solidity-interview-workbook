// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Escrow {
    // TODO:
    // - buyer and seller
    // - lifecycle enum
    // - fund(), release(), refund()
    // - events and custom errors
    // - prevent double settlement and reentrancy

    string private seller;
    string private buyer;
    uint private amount;
    uint private releaseTime;
    uint private refundTime;

    enum Lifecycle {
        Pending,   // 0
        Shipped,   // 1
        Accepted,  // 2
        Canceled   // 3
    }
    Lifecycle private lifecycle;

   // The constructor runs exactly once when the contract is deployed
    constructor(string memory _initialMessage) {
        owner = msg.sender;       // Sets deployer as the owner
        message = _initialMessage; // Sets the initial string value
    }

    // Function to update the stored message
    function updateMessage(string memory _newMessage) public {
        message = _newMessage;
    }

}
