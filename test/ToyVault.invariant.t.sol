// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {ToyVault} from "../src/ToyVault.sol";
import {ToyVaultHandler} from "./ToyVaultHandler.sol";

contract ToyVaultInvariantTest is StdInvariant, Test {
    ToyVault internal vault;
    ToyVaultHandler internal handler;

    function setUp() public {
        vault = new ToyVault();

        handler = new ToyVaultHandler(vault);

        /*
            Tell Foundry:
            ONLY fuzz the handler.
        */
        targetContract(address(handler));
    }

    /*
        Canonical solvency invariant.

        Should FAIL because withdraw()
        never decrements totalShares.
    */
    function invariant_vaultSolvent() public view {
        assertEq(
            address(vault).balance,
            vault.totalShares(),
            "vault insolvent"
        );
    }
}
