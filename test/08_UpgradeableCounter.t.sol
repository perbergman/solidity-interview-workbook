// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../solutions/08_UpgradeableCounter.sol";

// Covers test-specs/08_Upgradeable.md.

// V2: same storage layout (value stays in slot 0 — append-only rule),
// adds decrement() and version(). MUST re-inherit UUPSUpgradeable or the
// upgrade chain would end here, frozen forever.
contract CounterV2 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function increment() external {
        value++;
    }

    function decrement() external {
        value--;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

contract UpgradeableCounterTest is Test {
    UpgradeableCounter internal impl;
    UpgradeableCounter internal counter; // the proxy, seen through the V1 ABI
    address internal owner = makeAddr("owner");

    function setUp() public {
        impl = new UpgradeableCounter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(UpgradeableCounter.initialize, (owner)) // atomic init — no front-run window
        );
        counter = UpgradeableCounter(address(proxy));
    }

    // implementation cannot be initialized directly (_disableInitializers in constructor)
    function test_ImplementationCannotBeInitializedDirectly() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(makeAddr("attacker"));
    }

    // proxy initializes once
    function test_ProxyInitializedOnce() public view {
        assertEq(counter.owner(), owner);
        assertEq(counter.value(), 0);
    }

    // reinitialization rejected
    function test_ReinitializationRejected() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        counter.initialize(makeAddr("attacker"));
    }

    // owner can upgrade
    function test_OwnerCanUpgrade() public {
        CounterV2 v2Impl = new CounterV2();
        vm.prank(owner);
        counter.upgradeToAndCall(address(v2Impl), "");
        assertEq(CounterV2(address(counter)).version(), 2);
    }

    // non-owner cannot upgrade
    function test_NonOwnerCannotUpgrade() public {
        CounterV2 v2Impl = new CounterV2();
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, rando)
        );
        counter.upgradeToAndCall(address(v2Impl), "");
    }

    // state preserved after V2 upgrade — same proxy storage, new code
    function test_StatePreservedAfterUpgrade() public {
        counter.increment();
        counter.increment();
        counter.increment();
        assertEq(counter.value(), 3);

        CounterV2 v2Impl = new CounterV2();
        vm.prank(owner);
        counter.upgradeToAndCall(address(v2Impl), "");

        CounterV2 v2 = CounterV2(address(counter));
        assertEq(v2.value(), 3); // slot 0 untouched by the upgrade
        assertEq(v2.owner(), owner); // ERC-7201 namespaced Ownable storage intact
        v2.decrement(); // new capability works against old state
        assertEq(v2.value(), 2);
    }
}
