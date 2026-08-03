# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Solidity teaching workbook for interview preparation. It contains ten paired exercises, reference solutions, and test checklists, set up as a Foundry project.

The user's role is to implement the contracts in `exercises/` themselves, one at a time, and only compare against `solutions/` afterward. When helping, prefer guiding, reviewing, and explaining over writing complete implementations directly into exercise files — pasting a finished solution defeats the workbook's purpose. Do not reveal or copy from `solutions/` unless the user has already attempted the exercise or explicitly asks.

## Structure

Three parallel directories, matched by number prefix (01–10):

- `exercises/NN_*.sol` — stubs with TODO comments describing required features. This is where the user works.
- `solutions/NN_*.sol` — self-contained reference implementations (kept closed until after each attempt).
- `test-specs/NN_*.md` — checklists of behaviors that tests should cover for each contract.

Suggested order: Escrow → ERC20 → Vesting → MultiSig → Voting → ERC721 → Oracle consumer → Upgradeable → Treasury → Tokenized bond.

## Environment and commands

- Foundry project: `forge build` compiles, `forge test` runs the suite, `forge test --match-path test/01_Escrow.t.sol` runs one file, `--match-test <name>` one test.
- `./run.sh` is the full driver: test suite → deploy all ten solutions to anvil (via `script/DeployAll.s.sol`, wired and funded) → live UUPS V1→V2 upgrade drill via cast. Leaves anvil running.
- A local node must use port **9545**, not the default 8545 (kept free for the user's other EVM work): `anvil --port 9545`. The `local` RPC endpoint in foundry.toml points there.
- `src` is `solutions/` — exercises are excluded from the default build because in-progress stubs may not compile; tests import their target by relative path (`../solutions/...` or `../exercises/...`).
- All contracts target `pragma solidity ^0.8.24`. Solutions 02, 03, 06, 08, 09 import OpenZeppelin Contracts v5.6 (08 also Contracts Upgradeable) from git submodules in `lib/`.
- `test/01_Escrow.t.sol` is the template suite: one test per line of the matching test-spec checklist.

## Conventions in the reference solutions

- Custom errors instead of require strings (e.g. `error Unauthorized(); ... revert Unauthorized();`).
- Events for every state transition.
- Checks-effects-interactions plus an explicit `nonReentrant` modifier where ETH is transferred via low-level `call`.
- `immutable` for constructor-set addresses/amounts; explicit lifecycle `enum State` for stateful flows.