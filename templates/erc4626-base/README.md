# `erc4626-base` — Starting template for ERC-4626 strategy-vault audits

Reusable starting point for any engagement against an ERC-4626 strategy-vault.
Copy this directory into the engagement repo, wire it up to the protocol's
vault, add protocol-specific actions, and you have the canonical invariants
running on day one.

## What's inside

```
ERC4626BaseHandler.sol     — base handler for any ERC-4626 vault
ERC4626BaseInvariants.sol  — base invariants (the standard 4626 properties)
README.md                  — this file
```

## How to use in an engagement

1. **Copy the two `.sol` files into your engagement's `test/` directory.**
   Rename if needed — e.g. `<Protocol>Handler.sol`, `<Protocol>Invariants.t.sol`.

2. **Update the imports.** Point `IERC4626` and `IERC20` at whatever your
   engagement already uses (OZ, solmate, etc.). If the target vault is a
   strict-spec ERC-4626 implementation, OZ's interfaces from
   `@openzeppelin/contracts/interfaces/IERC4626.sol` are the safe default.

3. **Override `_fundActor`.** The base handler doesn't assume the asset is
   mintable. If the asset is a `MockERC20` you control, override to mint.
   If it's a real ERC-20 (forked mainnet), override to `vm.deal` ETH then
   wrap, or use `deal(address(asset), actor, amount)` from forge-std.

4. **Add protocol-specific actions to the handler subclass.** Examples for
   strategy-vaults:
   - `harvest()` — strategy reward reinvestment.
   - `rebalance()` — strategy position adjustment.
   - `emergencyExit()` — strategy unwinding under stress.
   - `acceptDonation()` if the protocol has a donate path beyond raw transfer.
   Each protocol-specific action is where the BESPOKE bugs live — that's
   where the engagement's value-add concentrates.

5. **Override / extend invariants in your subclass of `ERC4626BaseInvariants`**.
   The base invariants are the standard 4626 properties. The engagement
   adds protocol-specific ones — e.g. `invariant_totalAssetsMatchesStrategyHoldings`
   for a yield aggregator, `invariant_exchangeRateMonotonic` for an
   LRT-style vault.

6. **Tune the `bound()` ranges in the handler** to the protocol's typical
   state. Real vaults have very different scales (1 wei vs. 1e9 vs. 1e18).
   The base template uses `[1, 100 ether]` which is sensible for ETH-asset
   vaults but wrong for, e.g., a USDC vault (use `[1, 1e12]` there).

## What the base invariants cover

- `invariant_noZeroShareDeposit` — no deposit with `assets > 0` ever mints
  zero shares. Catches inflation-attack class.
- `invariant_totalSupplyMatchesSumOfBalances` — bookkeeping integrity.
  Catches accounting drift from mint/burn bugs in custom code.
- `invariant_totalAssetsAtLeastTrackedDeposits` — `totalAssets()` is at least
  the sum of (deposits − redemptions − recorded losses). Catches silent
  asset drift (rebases gone wrong, strategy underflow, etc.).

These are the **3 invariants every ERC-4626 vault should pass without
protocol-specific knowledge.** A vault that fails any of them under the
base handler is already a finding before you've looked at strategy logic.

## Why the `seedDeposit` action is mandatory

`Foundry's bound()` samples uniformly. Without a dedicated 1-wei deposit
action, the fuzzer essentially never establishes the small-`totalSupply`
precondition for inflation. **Don't remove `seedDeposit` from the handler.**

The same lesson applies to other "bug-class openers" you discover during the
engagement — if a bug requires a specific opening move that wide-bound
sampling won't hit, add it as a dedicated action.

## Provenance

Distilled from the `src/VulnerableVault.sol` inflation-attack reproduction
in this repo. The handler shape and the 3 base invariants are exactly what
caught the canonical attack class on a 3-call shrunk sequence.
