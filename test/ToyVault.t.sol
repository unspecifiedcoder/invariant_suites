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
}
