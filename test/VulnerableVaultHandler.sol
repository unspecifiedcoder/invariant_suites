// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Handler for the inflation-attack invariant fuzzer.
///
///         Exposes 4 actions:
///         - `deposit`     — normal-range deposit, amount in [1, 100 ether].
///         - `seedDeposit` — domain-knowledge action: deposit exactly 1 wei.
///                           This is the "tiny first deposit" that opens the
///                           inflation window. WITHOUT this, the fuzzer's
///                           wide-range deposit sampler virtually never
///                           lands on a small-enough first deposit to
///                           establish a tiny totalSupply.
///         - `donate`      — raw asset transfer to vault, amount in [1, 100 ether].
///                           This is the attack vector — inflates totalAssets
///                           without minting shares.
///         - `redeem`      — bound to actor's share balance, no revert spam.
///
///         Trip flag `ghost_zeroShareDepositOccurred` is set when any
///         deposit with assets > 0 mints 0 shares. The invariant asserts
///         this flag is always false. A fired flag = the inflation attack
///         class has been realized in this run.
contract VulnerableVaultHandler is Test {
    VulnerableVault internal vault;
    MockERC20 internal asset;

    address[] internal actors;

    bool public ghost_zeroShareDepositOccurred;
    uint256 public ghost_seedDeposits;
    uint256 public ghost_donations;
    uint256 public ghost_regularDeposits;

    constructor(VulnerableVault _vault, MockERC20 _asset) {
        vault = _vault;
        asset = _asset;

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));
        actors.push(address(0xD00D));
    }

    function _getActor(uint256 actorSeed) internal view returns (address) {
        return actors[actorSeed % actors.length];
    }

    function _checkZeroShareTrip(uint256 amount, uint256 sharesMinted) internal {
        if (amount > 0 && sharesMinted == 0) {
            ghost_zeroShareDepositOccurred = true;
        }
    }

    function deposit(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, 100 ether);

        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        uint256 sharesMinted = vault.deposit(amount, actor);
        vm.stopPrank();

        ghost_regularDeposits += 1;
        _checkZeroShareTrip(amount, sharesMinted);
    }

    function seedDeposit(uint256 actorSeed) external {
        address actor = _getActor(actorSeed);
        uint256 amount = 1;

        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        uint256 sharesMinted = vault.deposit(amount, actor);
        vm.stopPrank();

        ghost_seedDeposits += 1;
        _checkZeroShareTrip(amount, sharesMinted);
    }

    function donate(uint256 actorSeed, uint256 rawAmount) external {
        address actor = _getActor(actorSeed);
        uint256 amount = bound(rawAmount, 1, 100 ether);

        asset.mint(actor, amount);
        vm.prank(actor);
        asset.transfer(address(vault), amount);

        ghost_donations += 1;
    }

    function redeem(uint256 actorSeed, uint256 rawShares) external {
        address actor = _getActor(actorSeed);
        uint256 actorShares = vault.balanceOf(actor);
        if (actorShares == 0) return;

        uint256 shares = bound(rawShares, 1, actorShares);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }
}
