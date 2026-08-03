// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/*
 * INTERVIEW NOTES
 * - UUPS: upgrade logic lives in the IMPLEMENTATION (upgradeToAndCall runs
 *   via delegatecall, writes the EIP-1967 slot in proxy storage). Proxy is
 *   a minimal ERC1967Proxy. vs Transparent: logic in proxy, routes admin
 *   calls away from implementation — dearer per call. UUPS is OZ's default.
 * - The odd constructor is a security fix: the bare implementation is ALSO
 *   live on-chain; _disableInitializers() stops anyone initializing IT
 *   directly (historically: initialize as owner, upgrade, selfdestruct —
 *   bricking every proxy pointing at it).
 * - initialize() replaces the constructor because constructors run in the
 *   implementation's context — proxy storage never sees them. The
 *   `initializer` modifier is a run-once latch IN PROXY STORAGE; deploy
 *   must call it atomically or anyone can front-run and become owner.
 * - _authorizeUpgrade is the whole authorization surface: empty body +
 *   onlyOwner is enough; production wants multisig + timelock behind it.
 *   Too-permissive = total compromise. And V2 MUST inherit UUPSUpgradeable
 *   again — ship one without it and the upgrade chain ends, frozen forever.
 * - Storage layout across versions is APPEND-ONLY: `value` owns slot 0 for
 *   eternity; V2 adds below, never reorders/retypes (slots are positional).
 *   OZ upgrades tooling diffs layouts — use it, humans miss slot shifts.
 */
contract UpgradeableCounter is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) external initializer {
        // __UUPSUpgradeable_init() was removed in OZ upgradeable >=5.6 —
        // it was always a stateless no-op; only bases with state need init.
        __Ownable_init(owner_);
    }

    function increment() external {
        value++;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
