// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../solutions/06_InterviewNFT.sol";

// Covers test-specs/06_ERC721.md.

contract Receiver is IERC721Receiver {
    address public lastOperator;
    uint256 public lastTokenId;

    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        returns (bytes4)
    {
        lastOperator = operator;
        lastTokenId = tokenId;
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract NonReceiver {} // no onERC721Received — safeTransfer must reject it

contract InterviewNFTTest is Test {
    InterviewNFT internal nft;
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        nft = new InterviewNFT(admin);
    }

    // authorized mint succeeds
    function test_AuthorizedMintSucceeds() public {
        vm.prank(admin);
        uint256 id = nft.mint(alice, "ipfs://token-0");
        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.balanceOf(alice), 1);
    }

    // unauthorized mint rejected
    function test_UnauthorizedMintRejected() public {
        bytes32 role = nft.MINTER_ROLE(); // cache: a call here would consume the prank
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role
            )
        );
        nft.mint(alice, "ipfs://nope");
    }

    // token URI correct
    function test_TokenURICorrect() public {
        vm.prank(admin);
        uint256 id = nft.mint(alice, "ipfs://token-0");
        assertEq(nft.tokenURI(id), "ipfs://token-0");
    }

    // transfer and approvals work
    function test_TransferAndApprovalsWork() public {
        vm.prank(admin);
        uint256 id = nft.mint(alice, "u");

        // owner transfers directly
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);

        // per-token approval lets a third party move it
        vm.prank(bob);
        nft.approve(alice, id);
        assertEq(nft.getApproved(id), alice);
        vm.prank(alice);
        nft.transferFrom(bob, alice, id);
        assertEq(nft.ownerOf(id), alice);
    }

    // safe transfer to receiver works (and the hook sees the operator)
    function test_SafeTransferToReceiverWorks() public {
        Receiver receiver = new Receiver();
        vm.prank(admin);
        uint256 id = nft.mint(alice, "u");

        vm.prank(alice);
        nft.safeTransferFrom(alice, address(receiver), id);
        assertEq(nft.ownerOf(id), address(receiver));
        assertEq(receiver.lastOperator(), alice);
        assertEq(receiver.lastTokenId(), id);

        // counter-case: a contract without the hook is rejected
        NonReceiver nonReceiver = new NonReceiver();
        vm.prank(admin);
        uint256 id2 = nft.mint(alice, "u2");
        vm.prank(alice);
        vm.expectRevert();
        nft.safeTransferFrom(alice, address(nonReceiver), id2);
    }

    // token IDs are unique
    function test_TokenIdsAreUnique() public {
        vm.startPrank(admin);
        uint256 a = nft.mint(alice, "a");
        uint256 b = nft.mint(alice, "b");
        uint256 c = nft.mint(bob, "c");
        vm.stopPrank();
        assertEq(a, 0);
        assertEq(b, 1);
        assertEq(c, 2);
        assertEq(nft.nextTokenId(), 3); // monotonic, never reused
    }
}
