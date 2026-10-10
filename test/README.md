The tests retain the original contributor's suite and add adversarial ERC-20 checks,
stateful invariants, and offline Uniswap v4 integration. No production source or
project configuration is changed. All test imports are ordinary files under `test/`.

Run the Solidity suite with `forge build` and `forge test`. During this assignment,
build artifacts can stay inside the permitted scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
python3 test/check_launch.py
```

`check_launch.py` uses only Python's standard library and the installed `forge`.
It separately verifies the manifest's exact schema and launch values, effective
compiler settings, and local import closure. It is not invoked by `forge test`:
the project's unchanged Foundry file permissions do not allow tests to read
`launch.json`. Solidity tests neither read nor depend on the pinned `.imd/reads/`
inputs, environment variables, scratch files, FFI, or RPC endpoints.

Coverage added by file:

| File | Behavior exercised |
| --- | --- |
| `PROOFTokenEdges.t.sol` | Contract deployer versus transaction origin; zero sender/approver; zero-value events; maximum-value attempts; approval scoping, revocation and repeated infinite spending; self-transfer limits; fuzzed failure atomicity; absent administrative, burn, fallback and payable entry points. |
| `PROOFTokenInvariant.t.sol` | A handler mixes transfers, approvals, delegated spending, overdraws, unauthorized spending and invalid recipients. An independent ledger checks every actor balance and every allowance after each operation, as well as fixed supply and conservation. |
| `PROOFTokenPoolManager.t.sol` | The actual pinned upstream PoolManager at the specified Ethereum address; both currency orders; economics-derived opening price; a single-sided 90% seed; whole swarm transfer and claim leg; rounding remainder; fee-bearing buys/sells, exact output, fee collection, double collection, and failed-settlement rollback. |

Fuzz tests use Foundry's default run count. The invariant campaign is bounded to
128 sequences of 32 calls, with unexpected handler reverts treated as failures.
Expected invalid operations use low-level calls and check their revert data.
The handler never reads token balances or allowances to determine its model's
expected results. A deterministic handler test exercises both valid and invalid
actions to guard against vacuous invariant coverage.

Integration scope: the manager executes locally from pinned source, including
its real liquidity math, fees, unlock callback and currency settlement checks.
Its constructor runs at `0x000000000004444c5dc75cB358380D2e3dE08A90` so its
NoDelegateCall immutable remains valid. The pair currency at the order's address
is a minimal test fixture. Factory and trader accounts are test fixtures; no
production factory, initialization guard, or Merkle distributor was supplied in
this repository. The tests cover their token-facing transfers, not Merkle proof
verification or factory deployment logic. A live-mainnet fork comparison against
the deployed manager and IMD remains outside this offline suite.

The token itself has no transfer fee. The integration tests use the requested
12,500 pool fee, assert positive fee growth in both currencies, and check that
token debits and receipts still match PoolManager deltas exactly. Artificial test
actors and the pair token's mint function are fixtures, not launch parameters.

See `vendor/README.md` for dependency provenance and licenses.
