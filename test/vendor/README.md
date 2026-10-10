These are source dependencies for the offline tests, stored as ordinary files.
There are no submodules, download steps, remappings, or runtime network needs.
Only the transitive source closure required for PoolManager and its state readers
is included; upstream test suites and build configuration are omitted.

| Directory | Upstream revision | Contents and license |
| --- | --- | --- |
| `v4-core/` | [Uniswap/v4-core, v4.0.0](https://github.com/Uniswap/v4-core/tree/e50237c43811bd9b526eff40f26772152a42daba), commit `e50237c43811bd9b526eff40f26772152a42daba` | 45 Solidity files. Upstream SPDX notices retained; MIT and BUSL license texts under `v4-core/licenses/`. |
| `solmate/` | [transmissions11/solmate](https://github.com/transmissions11/solmate/tree/4b47a19038b798b4a33d9749d25e570443520647), commit `4b47a19038b798b4a33d9749d25e570443520647` | `src/auth/Owned.sol` and upstream `LICENSE` (AGPL-3.0-only). This is the Solmate revision pinned by v4-core's git tree. |

The only source adaptation is in `v4-core/src/ProtocolFees.sol`: its import of
`solmate/src/auth/Owned.sol` uses `../../solmate/src/auth/Owned.sol` instead, so it
resolves without changing this project's protected configuration. Contract logic
is unchanged. The submission formatter may also normalize Solidity formatting.

Solmate ownership is a dependency of the test PoolManager. PROOFToken neither
imports nor inherits it and has no ownership or administration functions.
