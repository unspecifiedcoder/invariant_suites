// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICToken} from "./ICToken.sol";

/// @title  LendingClassBaseHandler
/// @notice Reusable handler for invariant-fuzzing any single Compound-v2
///         cToken market. Distilled from the Hundred Finance Optimism
///         reproduction in this repo. Copy into your engagement's `test/` directory and:
///
///         1. Inherit and override `_fundActor` for the underlying's
///            specific funding mechanism (deal for forked mainnet markets,
///            mint for MockERC20).
///         2. Add protocol-specific actions in the subclass — most lending
///            forks have custom hooks (custom interest models, reward
///            harvesters, governance-controlled reserve management) that
///            need their own fuzz coverage.
///         3. Tune `MAX_JUMP_FACTOR` to the protocol's actual organic
///            per-block bound. Default 2× is generous; a real engagement
///            should derive the bound from the interestRateModel.
abstract contract LendingClassBaseHandler is Test {
    ICToken internal cToken;
    IERC20  internal underlying;

    address[] internal actors;

    /// @dev Max ratio allowed for `exchangeRateStored()` change inside a
    ///      single handler call. Donations push this to 1e9+, well past
    ///      any organic bound. Override for protocols with custom interest
    ///      models that may legitimately move the rate faster.
    function maxJumpFactor() public view virtual returns (uint256) {
        return 2;
    }

    /// @dev Upper bound on bounded amounts. Override for the asset's decimals
    ///      — `100 * 1e6` for USDC-decimal markets, `100 * 1e18` for ETH-decimal.
    function maxAmount() public view virtual returns (uint256) {
        return 100 ether;
    }

    // -------- Trip flags --------

    /// @notice Set when any single action changed `exchangeRateStored` by
    ///         more than `MAX_JUMP_FACTOR`. Donations against tiny-supply
    ///         markets trip this immediately.
    bool public ghost_excessiveRateJumpOccurred;

    /// @notice Set when getCash() drifts away from underlying.balanceOf(self).
    ///         Canonical Compound holds these equal; if a fork separates them
    ///         (custom accounting), divergence is interesting on its own.
    bool public ghost_cashAccountingDrifted;

    // -------- Tracking ghosts --------

    uint256 public ghost_totalMinted;
    uint256 public ghost_totalRedeemed;
    uint256 public ghost_totalDonated;

    constructor(ICToken _cToken, IERC20 _underlying) {
        cToken = _cToken;
        underlying = _underlying;

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));
        actors.push(address(0xD00D));
    }

    // -------- Hooks (override in your subclass) --------

    /// @notice Fund `actor` with `amount` of the underlying.
    ///         - MockERC20:       `MockERC20(address(underlying)).mint(actor, amount);`
    ///         - Real ERC-20:     `deal(address(underlying), actor, amount);`
    function _fundActor(address actor, uint256 amount) internal virtual;

    // -------- Helpers --------

    function _getActor(uint256 actorSeed) internal view returns (address) {
        return actors[actorSeed % actors.length];
    }

    function _checkCashAccounting() internal {
        if (cToken.getCash() != underlying.balanceOf(address(cToken))) {
            ghost_cashAccountingDrifted = true;
        }
    }

    // -------- Base actions --------

    /// @notice Mint cTokens by depositing underlying.
    function mint(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, maxAmount());

        uint256 rateBefore = cToken.exchangeRateStored();

        _fundActor(actor, amount);
        vm.startPrank(actor);
        underlying.approve(address(cToken), amount);
        uint256 err = cToken.mint(amount);
        vm.stopPrank();

        if (err == 0) {
            ghost_totalMinted += amount;
        }

        uint256 rateAfter = cToken.exchangeRateStored();
        if (rateBefore > 0 && rateAfter > rateBefore * maxJumpFactor()) {
            ghost_excessiveRateJumpOccurred = true;
        }
        _checkCashAccounting();
    }

    /// @notice Domain-knowledge action: mint with exactly 1 unit of underlying.
    ///         Required to give the fuzzer a path to small `totalSupply`,
    ///         which is the precondition for the donation-inflation attack.
    ///         Without this action, wide-bound sampling almost never lands
    ///         on a small enough mint to establish the inflation precondition.
    ///         Do NOT remove.
    function seedMint(uint256 actorSeed) external {
        address actor = _getActor(actorSeed);
        uint256 amount = 1;
        uint256 rateBefore = cToken.exchangeRateStored();

        _fundActor(actor, amount);
        vm.startPrank(actor);
        underlying.approve(address(cToken), amount);
        uint256 err = cToken.mint(amount);
        vm.stopPrank();

        if (err == 0) {
            ghost_totalMinted += amount;
        }

        uint256 rateAfter = cToken.exchangeRateStored();
        if (rateBefore > 0 && rateAfter > rateBefore * maxJumpFactor()) {
            ghost_excessiveRateJumpOccurred = true;
        }
        _checkCashAccounting();
    }

    /// @notice Redeem cTokens for underlying.
    function redeem(uint256 actorSeed, uint256 rawTokens) external {
        address actor = _getActor(actorSeed);
        uint256 actorBal = cToken.balanceOf(actor);
        if (actorBal == 0) return;

        uint256 tokens = bound(rawTokens, 1, actorBal);
        uint256 rateBefore = cToken.exchangeRateStored();

        vm.prank(actor);
        cToken.redeem(tokens);

        ghost_totalRedeemed += tokens;

        uint256 rateAfter = cToken.exchangeRateStored();
        if (rateBefore > 0 && rateAfter > rateBefore * maxJumpFactor()) {
            ghost_excessiveRateJumpOccurred = true;
        }
        _checkCashAccounting();
    }

    /// @notice Raw asset transfer into cToken (donation). Attack vector for
    ///         empty-market inflation. Without this action the fuzzer will
    ///         never find the bug class.
    function donate(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, maxAmount());

        uint256 rateBefore = cToken.exchangeRateStored();

        _fundActor(actor, amount);
        vm.prank(actor);
        underlying.transfer(address(cToken), amount);

        ghost_totalDonated += amount;

        uint256 rateAfter = cToken.exchangeRateStored();
        if (rateBefore > 0 && rateAfter > rateBefore * maxJumpFactor()) {
            ghost_excessiveRateJumpOccurred = true;
        }
        _checkCashAccounting();
    }

    /// @notice Manually advance interest accrual. Compound's exchange rate
    ///         only updates on accrue or write — explicit calls let the
    ///         fuzzer explore time-based state.
    function accrueInterest() external {
        cToken.accrueInterest();
    }
}
