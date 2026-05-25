# Invariant Suites

[![CI](https://github.com/unspecifiedcoder/invariant_suites/actions/workflows/test.yml/badge.svg)](https://github.com/unspecifiedcoder/invariant_suites/actions/workflows/test.yml)

Bespoke **stateful invariant test suites** for ERC-4626 strategy-vaults and Compound-fork lending markets.

Most audits rely on manual review and Slither. I ship production-ready Foundry invariant tests — complete with handlers, targeted invariants, and reproducible PoCs — tailored to your protocol's specific harvest, rebalance, and accounting logic.

The suite drops into your existing Foundry setup. Your auditor inherits it. Your CI runs it on every commit after launch.

---

## What's inside

- **[`exploits/erc4626-inflation/`](exploits/erc4626-inflation/)** — full reproduction of the canonical ERC-4626 first-depositor inflation attack. Deterministic PoC + autonomous invariant fuzzer that surfaces the bug class on a 3-call shrunk sequence.
- **[`exploits/hundred-finance/`](exploits/hundred-finance/)** — live-fork reproduction of the Hundred Finance Optimism empty-market donation attack (April 2023, ~$6.8M loss). 6.5×10⁹ exchange-rate inflation in a single donation, asserted against the real April-15-2023 fork state.
- **[`templates/erc4626-base/`](templates/erc4626-base/)** — reusable starting handler + invariants for any ERC-4626 strategy-vault audit. Abstract base; subclass and override `_fundActor` + `maxAmount()` per protocol.
- **[`templates/lending-class/`](templates/lending-class/)** — reusable starting handler + invariants for any Compound-v2-fork lending market audit. Same shape; lending surface.

---

## Running it locally

```bash
git clone https://github.com/unspecifiedcoder/invariant_suites.git
cd invariant_suites
forge install
forge test
```

Expected end state on a fresh clone (no RPC configured):

```
7 passed; 2 failed; 1 skipped
```

The **two failures are by design** — they're the invariants catching their respective planted bugs:

- `invariant_vaultSolvent` on `ToyVault` — catches the planted "forgot to decrement totalShares" bug on a 2-call shrunk sequence.
- `invariant_noZeroShareDeposit` on `VulnerableVault` — catches the canonical ERC-4626 inflation attack on a 3-call shrunk sequence.

The **skip** is the Hundred Finance fork test — it self-skips when `OPTIMISM_RPC_URL` isn't set. To run it, drop the env var into a local `.env` (gitignored):

```bash
echo "OPTIMISM_RPC_URL=https://opt-mainnet.g.alchemy.com/v2/<your-key>" > .env
forge test
```

With the env set you'll see `10 passed; 2 failed; 0 skipped`.

---

## What an engagement produces

An invariant-suite engagement against your protocol delivers:

1. **A handler contract** that exercises your protocol's actual state machine — including the bespoke harvest, rebalance, and reward-distribution paths that diverge from canonical base contracts.
2. **A targeted invariant set** that encodes your protocol's actual safety properties — not generic ERC-4626 properties (those are already in the templates here).
3. **Reproducible PoCs** for every finding — written as standalone `forge test` cases your auditors and CI can run forever after.

The suite lives in your repo when the engagement ends. Your auditor inherits it. Your CI keeps running it.

---

## Repo structure

```
src/                              Solidity reference implementations
  ToyVault.sol                    1:1 ETH vault with one planted bug (pedagogical)
  VulnerableVault.sol             Naive ERC-4626 (no inflation mitigation)

test/                             Foundry tests
  ToyVault.t.sol                  Unit tests + PoC for the ToyVault bug
  ToyVault.invariant.t.sol        Invariant fuzzer for ToyVault
  ToyVaultHandler.sol             Handler for the ToyVault fuzzer

  Inflation.t.sol                 Deterministic PoC of the ERC-4626 inflation attack
  Inflation.invariant.t.sol       Invariant fuzzer for the inflation attack
  VulnerableVaultHandler.sol      Handler for the inflation fuzzer

  HundredFinance.fork.t.sol       Live-fork reproduction (Optimism, block 90761917)

  interfaces/ICToken.sol          Minimal Compound-v2 cToken interface
  mocks/MockERC20.sol             Minimal mintable ERC-20 for testing

templates/                        Reusable starting points
  erc4626-base/                   For ERC-4626 strategy-vault audits
  lending-class/                  For Compound-fork lending market audits

exploits/                         Case-study writeups
  erc4626-inflation/              ERC-4626 first-depositor inflation
  hundred-finance/                Hundred Finance Optimism (April 2023)
```

---

## Contact

For audit / pre-audit inquiries: open an issue, or DM on Twitter.
