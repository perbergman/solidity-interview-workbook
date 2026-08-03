# Solidity Interview Workbook

A teaching workbook for engineers preparing for Solidity / smart-contract interviews — especially those coming from adjacent depth (protocol engineering, backend systems, other ledger stacks) who need the *contract layer* and its idioms, not a from-zero course.

Ten exercises, from a native-ETH escrow to a permissioned tokenized bond, each in three parts:

- `exercises/NN_*.sol` — stubs with TODOs. Work here.
- `solutions/NN_*.sol` — annotated reference implementations, each headed by an `INTERVIEW NOTES` block: the design decisions, security patterns, and production gaps an interviewer probes.
- `test-specs/NN_*.md` — behavior checklists; `test/NN_*.t.sol` implements each checklist one test per line (69 tests total).

Beyond the contracts:

- **`NOTES.md`** — the conceptual backbone: native ETH mechanics (CALL, receive/fallback, forced ETH, Cancun/Pectra updates), WETH and wrap-vs-swap, diamond inheritance, EIP-712, delegatecall and every proxy upgrade pattern, and a map of what's EVM protocol vs. Solidity compiler fiction.
- **`DEFENSE.md`** — a one-page design-defense sheet for architect-level interviews: per contract, the decision / the credible alternative / the why.

## How to use it

1. Implement one contract at a time in `exercises/`; keep `solutions/` closed until you've attempted it.
2. Write tests against the matching `test-specs/` checklist (or run the provided suite against your implementation by flipping the import in `test/NN_*.t.sol` from `../solutions/...` to `../exercises/...`).
3. Explain your design out loud — the `INTERVIEW NOTES` blocks and `DEFENSE.md` show the level of reasoning to aim for.
4. Compare with the reference solution and refactor rather than copy.

## Suggested order

Escrow → ERC20 → Vesting → MultiSig → Voting → ERC721 → Oracle consumer → Upgradeable (UUPS) → Treasury → Tokenized bond

The escrow is deliberately first: it teaches the native-value layer (payable, msg.value, checks-effects-interactions, reentrancy, push-vs-pull) that everything else builds on.

## Environment

Foundry project. OpenZeppelin v5.6 (and Contracts Upgradeable) vendored as git submodules — clone with `--recurse-submodules` or run `git submodule update --init` after cloning.

```bash
forge test                                   # full suite (69 tests)
forge test --match-path test/01_Escrow.t.sol # one contract
./run.sh                                     # full driver, see below
```

`./run.sh` runs the test suite, starts a local anvil, deploys all ten solutions wired and funded (via `script/DeployAll.s.sol`), then performs a live UUPS V1→V2 upgrade drill with cast — printing the EIP-1967 slot before and after, the new `version()`, and the preserved counter state. Anvil runs on port **9545** (not 8545) to avoid colliding with other local nodes.

The contracts are intentionally compact: interview exercises, not production systems. Each solution's notes say explicitly what a production version would add.
