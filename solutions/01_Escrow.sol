// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * INTERVIEW NOTES
 * - Explicit lifecycle enum makes every function a state-machine transition;
 *   invalid orderings (release before fund, settle twice) fail on one check.
 * - State is written BEFORE the external call (checks-effects-interactions);
 *   the nonReentrant lock is belt-and-braces on top, not the primary defense.
 * - call{value:}("") + success check, not transfer/send: the 2300-gas stipend
 *   breaks against contracts with non-trivial receive() after gas repricings.
 * - No receive()/fallback: fund() with msg.value == price is the ONLY way ETH
 *   enters — a correctness feature. But never assume balance == price anyway:
 *   ETH can be forced in (selfdestruct push, CREATE2 pre-fund).
 * - immutable buyer/seller/price: set once in constructor, live in code not
 *   storage — cheaper reads, cannot be tampered with post-deploy.
 * - Custom errors vs require strings: 4-byte selectors, far cheaper deploy/
 *   revert than ABI-encoded reason strings.
 * - Design alternatives to raise: singleton with mapping(id => EscrowData)
 *   (cheaper per deal, one address to index, but pooled-funds blast radius);
 *   EIP-1167 clones as middle ground; pull-payments (credit + withdraw()) to
 *   sidestep push-transfer failure modes entirely.
 */
contract Escrow {
    enum State { Created, Funded, Released, Refunded }

    error Unauthorized();
    error InvalidState();
    error InvalidAmount();
    error TransferFailed();
    error ReentrantCall();

    event Funded(uint256 amount);
    event Released(uint256 amount);
    event Refunded(uint256 amount);

    address public immutable buyer;
    address public immutable seller;
    uint256 public immutable price;
    State public state;
    bool private locked;

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert ReentrantCall();
        locked = true;
        _;
        locked = false;
    }

    constructor(address seller_, uint256 price_) {
        if (seller_ == address(0) || price_ == 0) revert InvalidAmount();
        buyer = msg.sender;
        seller = seller_;
        price = price_;
    }

    /// Buyer pays the escrow. `payable` lets ETH ride in on the call; by the
    /// time this body runs, msg.value is ALREADY credited to the contract —
    /// code can only revert to send it back, never "accept" it.
    function fund() external payable onlyBuyer {
        if (state != State.Created) revert InvalidState(); // one-shot: no re-fund, ever
        if (msg.value != price) revert InvalidAmount(); // exact amount — no partial, no excess
        state = State.Funded;
        emit Funded(msg.value);
        // No external calls here, so no reentrancy surface at all.
    }

    /// Buyer settles in the seller's favor. The single Funded check enforces
    /// three rules at once: no release before funding, no double release,
    /// no release after refund.
    function release() external onlyBuyer nonReentrant {
        if (state != State.Funded) revert InvalidState();
        // Effects before interactions: if the recipient reenters during the
        // call below, the state check above already sees Released and reverts.
        // The nonReentrant lock is a second, independent guard.
        state = State.Released;
        // call (not transfer/send): forwards all gas; empty calldata makes it
        // a plain transfer, running the recipient's receive()/fallback().
        (bool ok,) = seller.call{value: price}("");
        // Failed send reverts the WHOLE tx — including the state write above —
        // so the escrow stays Funded and can be retried or refunded. Nothing
        // is ever stranded half-settled.
        if (!ok) revert TransferFailed();
        emit Released(price);
    }

    /// Buyer takes the money back. Symmetric to release(); note the payee is
    /// the caller, so a malicious buyer CONTRACT reentering from its receive()
    /// hits the Funded check mid-flight, reverting the whole refund.
    function refund() external onlyBuyer nonReentrant {
        if (state != State.Funded) revert InvalidState();
        state = State.Refunded;
        (bool ok,) = buyer.call{value: price}("");
        if (!ok) revert TransferFailed();
        emit Refunded(price);
    }

    // Deliberately NO receive()/fallback: fund() is the only sanctioned ETH
    // entry point, so plain transfers bounce. ETH can still be FORCED in
    // (selfdestruct push, CREATE2 pre-fund, block rewards) — that is
    // unpreventable — but nothing here reads address(this).balance, so a
    // desynced balance cannot corrupt the state machine; it just strands.
}
