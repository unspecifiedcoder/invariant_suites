// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ToyVault} from "../src/ToyVault.sol";

contract ToyVaultHandler is Test {
    ToyVault internal vault;

    address[] internal actors;

    uint256 public ghost_totalDeposits;
    uint256 public ghost_totalWithdrawals;

    constructor(ToyVault _vault) {
        vault = _vault;

        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCAFE));
        actors.push(address(0xD00D));
    }

    /*
        Pick one actor from the small actor set.
    */
    function _getActor(uint256 actorSeed)
        internal
        view
        returns (address)
    {
        return actors[actorSeed % actors.length];
    }

    /*
        Fuzzer calls this.

        Handler:
        - bounds amount
        - funds actor
        - pranks actor
        - forwards call
    */
    function deposit(
        uint256 actorSeed,
        uint256 rawAmount
    ) external {
        address actor = _getActor(actorSeed);

        uint256 amount = bound(rawAmount, 1 ether, 100 ether);

        vm.deal(actor, amount);

        vm.startPrank(actor);

        vault.deposit{value: amount}();

        vm.stopPrank();

        ghost_totalDeposits += amount;
    }

    /*
        Withdraw only valid share amounts.
        Prevents revert spam.
    */
    function withdraw(
        uint256 actorSeed,
        uint256 rawAmount
    ) external {
        address actor = _getActor(actorSeed);

        uint256 actorShares = vault.shares(actor);

        if (actorShares == 0) {
            return;
        }

        uint256 amount = bound(
            rawAmount,
            1,
            actorShares
        );

        vm.startPrank(actor);

        vault.withdraw(amount);

        vm.stopPrank();

        ghost_totalWithdrawals += amount;
    }

    receive() external payable {}
}
