// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../solutions/01_Escrow.sol";
import "../solutions/02_InterviewToken.sol";
import "../solutions/03_TokenVesting.sol";
import "../solutions/04_MultiSig.sol";
import "../solutions/05_Voting.sol";
import "../solutions/06_InterviewNFT.sol";
import "../solutions/07_OracleConsumer.sol";
import "../solutions/08_UpgradeableCounter.sol";
import "../solutions/09_PausableTreasury.sol";
import "../solutions/10_TokenizedBond.sol";

// Deploys ALL ten solutions to the local chain, wired up ready to drive with
// cast: vesting pre-funded with tokens, treasury/bond/multisig funded with
// ETH, bond investor allowlisted and issued, oracle fed a live mock price.
// Invoked by ./run.sh, or standalone:
//   forge script script/DeployAll.s.sol --tc DeployAll --rpc-url local --broadcast
// Uses anvil's account 0 unless PRIVATE_KEY is set; anvil accounts 1 and 2
// play the counterparties (seller, beneficiary, co-owners, investor).

contract MockPriceFeed is IPriceFeed {
    int256 public immutable answer;
    uint8 private immutable feedDecimals;

    constructor(int256 answer_, uint8 decimals_) {
        answer = answer_;
        feedDecimals = decimals_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, block.timestamp, block.timestamp, 1); // always fresh
    }

    function decimals() external view returns (uint8) {
        return feedDecimals;
    }
}

contract DeployAll is Script {
    uint256 internal constant ANVIL_KEY_0 =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address internal constant ALICE = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // anvil 1
    address internal constant BOB = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // anvil 2

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", ANVIL_KEY_0);
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // 01 — deployer is buyer, ALICE is seller; fund() it yourself to play
        console.log("01 Escrow:            ", address(new Escrow(ALICE, 1 ether)));

        // 02 — deployer holds all roles
        InterviewToken token = new InterviewToken(deployer);
        console.log("02 InterviewToken:    ", address(token));

        {
            // 03 — ALICE vests 48k tokens over 4y with a 1y cliff; pre-funded
            TokenVesting vesting = new TokenVesting(
                token, ALICE, uint64(block.timestamp), 365 days, 4 * 365 days, 48_000e18
            );
            token.mint(address(vesting), 48_000e18);
            console.log("03 TokenVesting:      ", address(vesting));
        }

        {
            // 04 — 2-of-3 (deployer, ALICE, BOB), funded with 5 ETH
            address[] memory owners = new address[](3);
            owners[0] = deployer;
            owners[1] = ALICE;
            owners[2] = BOB;
            MultiSig multisig = new MultiSig(owners, 2);
            (bool ok,) = address(multisig).call{value: 5 ether}("");
            require(ok);
            console.log("04 MultiSig:          ", address(multisig));
        }

        {
            // 05 — deployer is admin; create a proposal open for a day
            Voting voting = new Voting();
            voting.createProposal(
                "workbook demo", uint64(block.timestamp), uint64(block.timestamp + 1 days)
            );
            console.log("05 Voting:            ", address(voting));
        }

        {
            // 06 — deployer mints token 0 to itself
            InterviewNFT nft = new InterviewNFT(deployer);
            nft.mint(deployer, "ipfs://workbook/0");
            console.log("06 InterviewNFT:      ", address(nft));
        }

        {
            // 07 — mock ETH/USD-style feed at 3000, 8 decimals, 1h staleness bound
            MockPriceFeed feed = new MockPriceFeed(3000e8, 8);
            console.log("07 MockPriceFeed:     ", address(feed));
            console.log("07 OracleConsumer:    ", address(new OracleConsumer(feed, 1 hours)));
        }

        {
            // 08 — UUPS: implementation + proxy with atomic initialize
            UpgradeableCounter impl = new UpgradeableCounter();
            console.log("08 Counter impl:      ", address(impl));
            console.log("08 Counter proxy:     ", address(new ERC1967Proxy(
                address(impl), abi.encodeCall(UpgradeableCounter.initialize, (deployer))
            )));
        }

        {
            // 09 — deployer holds all roles, funded with 5 ETH
            PausableTreasury treasury = new PausableTreasury(deployer);
            (bool ok,) = address(treasury).call{value: 5 ether}("");
            require(ok);
            console.log("09 PausableTreasury:  ", address(treasury));
        }

        {
            // 10 — matures in 30 days; ALICE allowlisted and issued 3 units; solvent
            TokenizedBond bond = new TokenizedBond(uint64(block.timestamp + 30 days), 1 ether);
            (bool ok,) = address(bond).call{value: 10 ether}("");
            require(ok);
            bond.setEligible(ALICE, true);
            bond.issue(ALICE, 3);
            console.log("10 TokenizedBond:     ", address(bond));
        }

        vm.stopBroadcast();

        console.log("deployer/admin/buyer: ", deployer);
        console.log("alice (counterparty): ", ALICE);
        console.log("bob:                  ", BOB);
    }
}
