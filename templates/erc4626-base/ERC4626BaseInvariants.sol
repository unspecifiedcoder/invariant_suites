// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ERC4626BaseHandler} from "./ERC4626BaseHandler.sol";

/// @title  ERC4626BaseInvariants
/// @notice Reusable base invariants for any ERC-4626-shaped vault.
///         Copy into your engagement's `test/` directory and:
///
///         1. Inherit; deploy your subclass of `ERC4626BaseHandler` in
///            `setUp()` and call `targetContract(address(handler))`.
///         2. Add protocol-specific invariants in your subclass — e.g.
///            `invariant_exchangeRateMonotonic`,
///            `invariant_totalAssetsMatchesStrategy`.
///
///         A vault that fails any of these base invariants is already a
///         finding before you've looked at strategy logic.
abstract contract ERC4626BaseInvariants is StdInvariant, Test {
    IERC4626 internal vault;
    ERC4626BaseHandler internal handler;

    /// @notice No deposit with assets > 0 should ever mint 0 shares.
    ///         Catches the inflation-attack class.
    function invariant_noZeroShareDeposit() public view {
        assertFalse(
            handler.ghost_zeroShareDepositOccurred(),
            "deposit > 0 minted 0 shares (inflation attack class realized)"
        );
    }

    /// @notice `totalAssets()` should be at least the running difference of
    ///         deposits and redemptions, plus any donations. Catches silent
    ///         asset drift (rebases gone wrong, strategy underflow, etc.).
    ///
    ///         Note: this is a LOWER bound — totalAssets can exceed it
    ///         (donations not accounted for in subtraction, strategy yield).
    function invariant_totalAssetsAtLeastTrackedNetDeposits() public view {
        uint256 net = handler.ghost_totalDepositedAssets()
                    + handler.ghost_totalDonatedAssets();
        uint256 redeemed = handler.ghost_totalRedeemedAssets();
        // Skip the assertion if redemptions exceed deposits (donations may
        // have been redeemed by other actors — that's not a violation per se).
        if (redeemed > net) return;
        assertGe(
            vault.totalAssets(),
            net - redeemed,
            "totalAssets dropped below tracked net deposits"
        );
    }
}
