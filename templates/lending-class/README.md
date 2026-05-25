# `lending-class` — Starting template for Compound-fork lending audits

Reusable starting point for any Compound-v2-fork lending market audit.
Complementary to `templates/erc4626-base/` — same handler/invariant shape,
applied to the lending half of the share-vault design space.

Distilled from the Hundred Finance Optimism 2023 reproduction in this repo.

## What's inside

```
ICToken.sol                          — minimal Compound-v2 cToken interface
LendingClassBaseHandler.sol          — base handler for one cToken market
LendingClassBaseInvariants.sol       — base invariants (rate jump + accounting)
README.md                            — this file
```

## How to use in a lending engagement

1. **Copy this directory into your engagement repo's `test/` tree.** Rename
   to match your protocol — e.g. `test/sonne/SonneHandler.sol`.

2. **Update the imports.** Point `ICToken` and `IERC20` at whatever your
   engagement uses. If the target is a strict Compound-v2 fork, the
   interface here works as-is. If the fork has custom selectors (extended
   storage layout, custom mint/redeem signatures), extend the interface.

3. **Override `_fundActor`** in your handler subclass:
   - Forked mainnet: `deal(address(underlying), actor, amount);`
   - MockERC20:      `MockERC20(address(underlying)).mint(actor, amount);`

4. **Add protocol-specific actions to the handler subclass.** Lending
   protocols routinely add custom hooks — these are the high-yield bug
   surface:
   - Custom interest models that read external state (oracles, governance).
   - Reward-harvesting paths that compound back into the market.
   - Reserve management (`_addReserves`, custom `_reduceReserves`).
   - Cross-market actions (collateral seizure, liquidation paths).
   Each of these belongs as a fuzzable handler action in your subclass.

5. **Add protocol-specific invariants.** The 3 base invariants below catch
   structurally-common bugs; engagement value-add is in protocol-specific
   properties. Examples that real lending audits should always include:
   - `invariant_collateralFactorRespected` — sum of borrows ≤ collateral × CF.
   - `invariant_reserveOnlyGrows` — `totalReserves` should only increase
     except via explicit governance `_reduceReserves`.
   - `invariant_borrowIndexMonotonic` — Compound's interest index is
     non-decreasing.
   - `invariant_liquidationSolvent` — post-liquidation, the protocol
     never enters bad debt.

6. **Tune `MAX_JUMP_FACTOR`** in the handler to the protocol's actual
   interest-rate-model bound. Default 2× is generous (covers years of
   compound interest). A real engagement should derive the bound from
   the deployed `InterestRateModel`'s parameters and call it explicitly.

## What the base invariants cover

- **`invariant_noExcessiveRateJump`** — single-action `exchangeRateStored`
  change is bounded by `MAX_JUMP_FACTOR`. Catches the empty-market
  donation class (Hundred Finance, all Compound-fork "donation
  manipulation" exploits historically).
- **`invariant_exchangeRateIdentity`** — `(cash + borrows - reserves) * 1e18
  / supply == exchangeRateStored` (with 1 wei rounding tolerance). Catches
  forks that drift from the canonical Compound math via custom interest
  / harvest logic.
- **`invariant_cashMatchesBalance`** — `getCash() == underlying.balanceOf(self)`.
  In canonical Compound this is the definition; in forks with custom
  cash accounting, drift is interesting either way (mitigates donations
  OR introduces a new bug, depending on which side broke first).

A fork that fails any of these under the base handler — even before you've
read a single line of strategy code — is **already a finding**.

## Why the `donate` action is mandatory

The empty-market inflation primitive is the canonical Compound-fork bug.
The handler MUST include `donate` (raw asset transfer to the cToken)
because Compound's `getCash() == balanceOf(self)` makes donations
externally manipulable. Without `donate` in the handler, the fuzzer has
no path to expose this class.

## Provenance

Distilled from `test/HundredFinance.fork.t.sol` —
`test_reproduce_emptyMarketInflation_hWBTC` produced a 6.5×10⁹ exchange-rate
inflation in a single donation on the real April-15-2023 fork state. The
base invariants here capture the exact property that test asserted, but
generalized to any cToken-shaped market.
