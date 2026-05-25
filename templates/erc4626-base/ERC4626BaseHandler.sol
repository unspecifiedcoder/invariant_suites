// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title  ERC4626BaseHandler
/// @notice Reusable handler for invariant-fuzzing any ERC-4626-shaped vault.
///         Copy into your engagement's `test/` directory and:
///
///         1. Inherit and override `_fundActor` to fit the asset's funding
///            mechanism (mint for MockERC20, deal for real assets).
///         2. Add protocol-specific actions (`harvest`, `rebalance`, …) as
///            additional external functions in your subclass.
///         3. Override `maxAmount()` for your asset's decimals.
///
///         Distilled from the ERC-4626 inflation-attack reproduction in this repo.
abstract contract ERC4626BaseHandler is Test {
    IERC4626 internal vault;
    IERC20   internal asset;

    address[] internal actors;

    /// @dev Upper bound on bounded amounts. Override in subclasses to match
    ///      the asset's decimals — `100 * 1e6` for USDC, `100 * 1e18` for ETH-decimal.
    function maxAmount() public view virtual returns (uint256) {
        return 100 ether;
    }

    // -------- Trip flags (the "bug realized" booleans) --------

    /// @notice Set when any deposit with assets > 0 minted 0 shares.
    bool public ghost_zeroShareDepositOccurred;

    // -------- Tracking ghosts (for richer invariants) --------

    uint256 public ghost_totalDepositedAssets;
    uint256 public ghost_totalRedeemedAssets;
    uint256 public ghost_totalDonatedAssets;
    uint256 public ghost_seedDeposits;

    constructor(IERC4626 _vault, IERC20 _asset) {
        vault = _vault;
        asset = _asset;

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));
        actors.push(address(0xD00D));
    }

    // -------- Hooks (override in your subclass) --------

    /// @notice Fund `actor` with `amount` of the underlying asset.
    ///         Override to fit your engagement:
    ///           - MockERC20:        `MockERC20(address(asset)).mint(actor, amount);`
    ///           - real ERC-20:      `deal(address(asset), actor, amount);`
    ///           - native-ETH-asset: `vm.deal(actor, amount);` (and adjust deposit path)
    function _fundActor(address actor, uint256 amount) internal virtual;

    // -------- Actor selection --------

    function _getActor(uint256 actorSeed) internal view returns (address) {
        return actors[actorSeed % actors.length];
    }

    // -------- Trip-flag helper --------

    function _checkZeroShareTrip(uint256 amount, uint256 sharesMinted) internal {
        if (amount > 0 && sharesMinted == 0) {
            ghost_zeroShareDepositOccurred = true;
        }
    }

    // -------- Base actions --------

    /// @notice Standard deposit. Amount bounded to `[1, maxAmount()]`.
    function deposit(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, maxAmount());

        _fundActor(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        uint256 sharesMinted = vault.deposit(amount, actor);
        vm.stopPrank();

        ghost_totalDepositedAssets += amount;
        _checkZeroShareTrip(amount, sharesMinted);
    }

    /// @notice Domain-knowledge action: always exactly 1 wei.
    ///         Required to give the fuzzer a path to small `totalSupply`,
    ///         which wide-bound sampling won't reach. Do NOT remove.
    function seedDeposit(uint256 actorSeed) external {
        address actor = _getActor(actorSeed);
        uint256 amount = 1;

        _fundActor(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        uint256 sharesMinted = vault.deposit(amount, actor);
        vm.stopPrank();

        ghost_totalDepositedAssets += amount;
        ghost_seedDeposits += 1;
        _checkZeroShareTrip(amount, sharesMinted);
    }

    /// @notice Raw asset transfer into vault (donation). Attack vector for
    ///         inflation-class bugs.
    function donate(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, maxAmount());

        _fundActor(actor, amount);
        vm.prank(actor);
        asset.transfer(address(vault), amount);

        ghost_totalDonatedAssets += amount;
    }

    /// @notice Redeem bounded to actor's share balance. No revert spam.
    function redeem(uint256 actorSeed, uint256 rawShares) external {
        address actor = _getActor(actorSeed);
        uint256 actorShares = vault.balanceOf(actor);
        if (actorShares == 0) return;

        uint256 shares = bound(rawShares, 1, actorShares);
        vm.prank(actor);
        uint256 assetsOut = vault.redeem(shares, actor, actor);

        ghost_totalRedeemedAssets += assetsOut;
    }
}
