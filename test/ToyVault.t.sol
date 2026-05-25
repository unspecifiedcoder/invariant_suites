// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ToyVault} from "../src/ToyVault.sol";

/// @notice Unit tests for ToyVault.
///         Confirms basic deposit/withdraw mechanics. Does NOT assert on
///         `totalShares` after withdraw — that's the invariant the
///         fuzzer is supposed to break.
contract ToyVaultTest is Test {
    ToyVault internal vault;

    function setUp() public {
        vault = new ToyVault();
    }

    receive() external payable {}

    function test_deposit_creditsUserShares() public {
        vault.deposit{value: 1 ether}();
        assertEq(vault.shares(address(this)), 1 ether);
    }

    function test_deposit_increasesTotalShares() public {
        vault.deposit{value: 1 ether}();
        assertEq(vault.totalShares(), 1 ether);
    }

    function test_withdraw_sendsEth() public {
        vault.deposit{value: 1 ether}();
        uint256 balBefore = address(this).balance;
        vault.withdraw(1 ether);
        assertEq(address(this).balance, balBefore + 1 ether);
    }

    function test_withdraw_burnsUserShares() public {
        vault.deposit{value: 1 ether}();
        vault.withdraw(1 ether);
        assertEq(vault.shares(address(this)), 0);
    }

    function test_withdraw_revertsIfInsufficient() public {
        vm.expectRevert(ToyVault.InsufficientShares.selector);
        vault.withdraw(1 ether);
    }

    /// @notice Shrunk-trace → reproducible PoC.
    ///
    /// The invariant fuzzer surfaced a 2-call sequence:
    ///   deposit(99 ether) by Bob, then withdraw(58 ether) by Bob.
    /// Vault balance drops by the withdrawn amount, but totalShares stays
    /// constant (the planted bug). So balance < totalShares afterward —
    /// the vault is insolvent.
    ///
    /// This PoC reproduces that sequence directly (no handler, no fuzzer),
    /// and asserts the BROKEN state. It's a witness, not a guard:
    /// it passes while the bug exists, and would fail if the bug were fixed.
    function test_PoC_insolvencyViaForgottenTotalSharesDecrement() public {
        address alice = address(0xA11CE);
        vm.deal(alice, 99 ether);

        vm.prank(alice);
        vault.deposit{value: 99 ether}();

        // Pre-withdraw: invariant holds.
        assertEq(
            address(vault).balance,
            vault.totalShares(),
            "pre-withdraw: invariant should hold"
        );

        vm.prank(alice);
        vault.withdraw(58 ether);

        // Post-withdraw: vault balance dropped to 41 ether, but totalShares
        // is still 99 ether. The vault is insolvent — fewer assets than the
        // sum of outstanding share claims.
        assertEq(address(vault).balance, 41 ether, "balance after withdraw");
        assertEq(vault.totalShares(), 99 ether, "totalShares NOT decremented (bug)");
        assertLt(
            address(vault).balance,
            vault.totalShares(),
            "vault should be insolvent post-withdraw"
        );
    }
}
