# Design defense sheet

One page for architect interviews: per contract — the decision made, the credible alternative, and the reason. Lead any answer with the invariant, name the trade-off, then the production gap.

**Cross-cutting narratives** (the six answers most questions reduce to):
1. **State machines make bad states unrepresentable** — double-settlement isn't checked, it's impossible.
2. **Isolation vs pooling** — blast radius vs gas/indexing; per-deal contracts vs singleton mappings vs clones.
3. **Push vs pull** — never fan out payments synchronously; credit entitlements, let payees claim. Scope it: pull is *mandatory* only when a failed push traps value or blocks other payees; push is fine when the recipient is singular and failure is recoverable.
4. **Trust topology** — name exactly who each contract trusts and what happens when they misbehave.
5. **Upgradeability is governance, not mechanism** — the delegatecall is table stakes; who holds the key, behind what timelock, is the design.
6. **Two-layer money** — native value rides the CALL itself (control-flow handoff, atomic revert); token "money" is contract storage. WETH exists to unify them.

---

**01 Escrow**
- *Decision:* per-deal instance; lifecycle enum; effects-before-interactions + lock; exact-amount `fund()` is the only ETH entry (no `receive()`); buyer decides both outcomes.
- *Alternative:* singleton `mapping(id => EscrowData)` (cheaper, one address to index) or EIP-1167 clones; seller-timeout or arbiter for settlement.
- *Why:* isolation makes the invariant trivially auditable (`balance == price` while Funded); pooling concentrates blast radius. Buyer-only settlement strands funds if the buyer vanishes — production adds a timeout. A failed send reverts state too: nothing can end half-settled. Push settlement is legitimate *here* because failure is recoverable (back to Funded, `refund()` still open) and the recipient is singular — pull becomes mandatory the moment either property breaks.

**02 ERC20 token**
- *Decision:* `AccessControl` roles; pause gated at OZ v5's `_update`, the single funnel for mint/burn/transfer.
- *Alternative:* `Ownable`; or pausing transfer paths only.
- *Why:* roles are revocable per capability (rotate a compromised minter without redeploy). Gating `_update` freezes mint too — deliberate policy; if emergency minting while paused must work, gate narrower.

**03 Vesting**
- *Decision:* entitlement derived from a monotone `vested(t)` minus a `released` accumulator; cliff is a mask over linear-from-start accrual.
- *Alternative:* per-period schedule bookkeeping; (the classic bug: accruing from the cliff instead of start).
- *Why:* one storage slot of mutable state cannot drift; claims are idempotent deltas. Trusts pre-funding and a vanilla ERC20 (fee-on-transfer/rebasing break it silently); no `revoke()` — real grants need unvested clawback.

**04 MultiSig**
- *Decision:* on-chain approvals keyed by index; plain CALL only; fixed owners/threshold; `executed` flag set before the arbitrary call.
- *Alternative:* Safe — EIP-712 off-chain signatures verified m-at-once, sequential nonce, self-reconfiguration via its own flow, delegatecall operations (MultiSend/modules).
- *Why:* minimal concept demo of wallet-as-identity (target sees the wallet as `msg.sender`). Gaps to volunteer: no expiry/ordering — a stale approved tx fires forever (Safe's nonce kills it); n approval txs vs one; no events.

**05 Voting**
- *Decision:* one-address-one-vote, timestamp-bounded window, strict majority (tie fails), no quorum.
- *Alternative:* checkpointed token-weighted voting (`ERC20Votes` snapshots) + quorum + execution timelock.
- *Why:* address-count voting is sybil-vulnerable by construction — valid only behind an identity gate. Snapshots stop vote-transfer-revote; a timelock lets users exit before a passed change lands.

**06 NFT**
- *Decision:* per-token URI storage; role-gated `_safeMint`; monotonic never-reused ids.
- *Alternative:* `_baseURI()` + tokenId (one IPFS directory, near-zero marginal cost — the 10k-collection default); `_mint` without the receiver hook.
- *Why:* URIStorage buys heterogeneous metadata at multi-SSTORE cost per mint. `_safeMint` is an external call mid-mint (the classic drop-exploit reentry point) — safe here because minting is role-gated and effects come first.

**07 Oracle consumer**
- *Decision:* validation trio — positive `int256` answer, non-zero `updatedAt`, heartbeat-aware staleness — then decimals-normalize to 1e18. Trust boundary = the feed address, fully.
- *Alternative:* DEX spot (never — flash-loan movable in one tx), TWAP, multi-oracle fallback with min/max sanity bounds, L2 sequencer-uptime check.
- *Why:* feeds update on deviation OR heartbeat, so `maxAge` must track the heartbeat — too tight and spurious staleness reverts become incidents inside liquidation paths.

**08 Upgradeable (UUPS)**
- *Decision:* upgrade logic in the implementation (`upgradeToAndCall` via delegatecall writes the EIP-1967 slot); minimal ERC1967 proxy; atomic initialize; `_disableInitializers()` locks the bare implementation; `onlyOwner` authorization hook.
- *Alternative:* transparent proxy (logic in proxy, ProxyAdmin contract, admin-check cost per call); beacon (fleet-wide upgrades); clones (cheap, non-upgradeable); or no proxy at all.
- *Why:* don't use a proxy unless upgrades are a requirement — immutability is a feature. UUPS risks to name: a V2 that drops `UUPSUpgradeable` freezes the chain forever; `_authorizeUpgrade` is the total-compromise surface → multisig + timelock behind it. Storage: append-only layout, ERC-7201 namespaces in OZ v5.

**09 Treasury**
- *Decision:* three orthogonal mixins — AccessControl (who), Pausable (when), ReentrancyGuard (how); pause gates deposits too; push withdrawals, role-gated; deposit event in `receive()`.
- *Alternative:* pull-payments if payees were permissionless; pausing withdrawals only.
- *Why:* refusing money in and refusing money out are different risks — gating both is an explicit stance. Raw-balance checks are acceptable only while there's no per-user accounting to desync (forced ETH exists).

**10 Tokenized bond**
- *Decision:* pull-based coupons (issuer credits O(1) per investor; holders claim), allowlist gate at issuance, no transfer function, redemption guarded by balance-zeroing alone.
- *Alternative:* loop-over-holders payout (DoS time bomb as holders grow); a restricted ERC20 (ERC-1400-family) for wallet/DEX composability with allowlist enforced on every transfer.
- *Why:* unbounded iteration is a growth-triggered outage. Non-transferability sidesteps recipient-eligibility entirely. Solvency is issuer trust, not code — nothing escrows face value; say that out loud before they ask. One state variable per fact: the removed `redeemed` flag was a redundant copy that could drift.
