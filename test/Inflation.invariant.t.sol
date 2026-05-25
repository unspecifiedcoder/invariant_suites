// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VulnerableVault} from "../src/VulnerableVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {VulnerableVaultHandler} from "./VulnerableVaultHandler.sol";

/// @notice Invariant fuzzing against the first-depositor inflation attack.
///
///         The invariant `invariant_noZeroShareDeposit` asserts that no
///         deposit with asset > 0 ever mints 0 shares. The handler exposes
///         seedDeposit + deposit + donate + redeem; the fuzzer needs to
///         find the sequence (seed -> donate -> deposit) that trips the
///         flag. If it does: the inflation-attack class is realized
///         autonomously.
contract InflationInvariantTest is StdInvariant, Test {
    VulnerableVault internal vault;
    MockERC20 internal asset;
    VulnerableVaultHandler internal handler;

    function setUp() public {
        asset = new MockERC20("Asset", "AST");
        vault = new VulnerableVault(IERC20(address(asset)));
        handler = new VulnerableVaultHandler(vault, asset);
        targetContract(address(handler));
    }

    /// @dev Canonical invariant for the inflation-attack class:
    ///      no honest deposit (assets > 0) should ever mint 0 shares.
    function invariant_noZeroShareDeposit() public view {
        assertFalse(
            handler.ghost_zeroShareDepositOccurred(),
            "deposit > 0 minted 0 shares (inflation attack realized)"
        );
    }
}
