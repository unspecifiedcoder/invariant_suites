// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {ICToken} from "./ICToken.sol";
import {LendingClassBaseHandler} from "./LendingClassBaseHandler.sol";

/// @title  LendingClassBaseInvariants
/// @notice Reusable base invariants for any Compound-v2-fork cToken market.
///         Inherit; deploy your subclass of `LendingClassBaseHandler` in
///         `setUp()` and call `targetContract(address(handler))`. Then add
///         protocol-specific invariants — e.g. `invariant_collateralFactorRespected`,
///         `invariant_reserveAccountingConsistent`, etc.
///
///         The base invariants catch the structurally-common bug classes
///         (rate manipulation, accounting drift) that every Compound fork
///         is exposed to. A fork that fails any of these under the base
///         handler is already a finding.
abstract contract LendingClassBaseInvariants is StdInvariant, Test {
    ICToken internal cToken;
    LendingClassBaseHandler internal handler;

    /// @notice No single handler action should have changed the exchange
    ///         rate by more than `handler.maxJumpFactor()`. Catches the
    ///         empty-market donation primitive (Hundred Finance class).
    function invariant_noExcessiveRateJump() public view {
        assertFalse(
            handler.ghost_excessiveRateJumpOccurred(),
            "exchange rate jumped by > maxJumpFactor() in a single call (donation/inflation class)"
        );
    }

    /// @notice The exchange-rate identity must hold at all observed states.
    ///         If a fork has custom interest accrual or reward logic that
    ///         changes this relationship, that's a finding.
    function invariant_exchangeRateIdentity() public view {
        uint256 supply = cToken.totalSupply();
        if (supply == 0) return; // identity undefined; nothing to check

        uint256 cash     = cToken.getCash();
        uint256 borrows  = cToken.totalBorrows();
        uint256 reserves = cToken.totalReserves();
        uint256 rate     = cToken.exchangeRateStored();

        // Allow up to 1 wei of rounding drift (Compound's stored rate vs.
        // the recomputed identity occasionally diverge by 1 due to integer
        // truncation in the accrue path; the fork should NEVER drift more).
        uint256 expected = (cash + borrows - reserves) * 1e18 / supply;
        uint256 diff = rate > expected ? rate - expected : expected - rate;
        assertLe(diff, 1, "exchange-rate identity broken beyond rounding");
    }

    /// @notice `getCash()` must equal `underlying.balanceOf(cToken)` in
    ///         canonical Compound. If a fork separates these (custom
    ///         accounting layer), that divergence is interesting on its
    ///         own — it may correctly defend against donations OR may
    ///         introduce a new accounting bug. Flag it for review either way.
    function invariant_cashMatchesBalance() public view {
        assertFalse(
            handler.ghost_cashAccountingDrifted(),
            "getCash() drifted from underlying.balanceOf(cToken) — custom accounting layer detected"
        );
    }
}
