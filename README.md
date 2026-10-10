# Proof Network (PROOF)

This repository contains the fixed-supply token, its launch manifest, and five logo options. The selected image-generated wallet mark is [artifacts/logo.png](artifacts/logo.png); the options and generation record are described in [logos/README.md](logos/README.md).

`PROOFToken` mints exactly 1,000,000,000 PROOF with 18 decimals (1e27 minor units) to `msg.sender` in its constructor. It accepts no constructor arguments. Supply, name, symbol and decimals are constants. There are no owner roles, admin functions, further minting, burning, fees, transfer limits, proxies or external calls. The contract exposes the standard ERC-20 metadata, balances, allowances, `approve`, `transfer` and `transferFrom`. A maximum allowance remains unchanged when spent; finite allowances are consumed. Transfers to the zero address revert.

The token performs no distribution. The launch factory receives the entire supply and handles the swarm's 10%, pool funding and remainder. [launch.json](launch.json) records the specified IMD pair, fee 12500, tick spacing 60, provenance price and economics. The launch derives the actual opening price from those economics and the deployed currency order.

Deployment targets Ethereum mainnet (chain ID 1), as selected by the launch order. The manifest intentionally has no chain field. Deploy `src/PROOFToken.sol:PROOFToken` through the launch factory with no constructor arguments and no ETH. The build artifact is `out/PROOFToken.sol/PROOFToken.json`; its creation bytecode needs no linked libraries. The factory is the constructor's `msg.sender`, receives all `1000000000000000000000000000` units, and gains no privileged token permissions. There are no application contracts or initialization calls.

| Launch parameter | Fixed value |
| --- | --- |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Uniswap v4 PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Pool fee / tick spacing | `12500` (1.25%) / `60` |
| Provenance `initialPrice` | `"125270724187523965593206900"` (sqrtPriceX96, assuming PROOF is currency0) |
| Pool allocation | `poolBps = 9000`: 900,000,000 PROOF (90% of total supply) |
| Opening market cap | `initialMarketCapWei = "2500000000000000000000"`: 2,500 IMD |
| Remainder recipient | `0x000000000000000000000000000000000000dead`, explicitly specified by the order |

The factory forwards 100,000,000 PROOF (10% of total supply) to the launch's Merkle distributor, seeds the pool from the remaining deployer balance, and sends any remainder to the specified recipient. The requested 90% pool allocation plus 10% swarm share accounts for the full supply; any unspent pool allocation from liquidity rounding is handled by the factory's remainder flow. The distributor handles claims. These services belong to the launch platform and are not deployed by this repository. Sending tokens to the remainder address is an ordinary transfer and does not reduce `totalSupply`.

The launch operator is responsible for deploying the compiled token, deriving the actual opening price from the economics and deployed currency order, executing distribution and pool settlement, and verifying the deployed source with the pinned compiler settings. Pool initialization, seed settlement and swaps in both directions are checked by the platform's protected harness. The pair and PoolManager addresses above are the order's supplied values; local tests exercise token transfers without querying mainnet. After launch, the token needs no configuration or administrator. Holders control their own transfers and allowances.

## Build and tests

With Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

The project requires no downloaded libraries, network access, RPC configuration or environment variables. All Solidity imports resolve within the repository. `foundry.toml` pins Solidity 0.8.26, Cancun, optimization and `bytecode_hash = "none"`.

The 18 local tests cover the constructor allocation and mint event, exact factory/distributor/pool transfer legs, transfer events, zero amounts, self transfers, full-balance transfers, allowance replacement and revocation, finite and infinite allowances, atomic failures, absent privileged functions and forbidden runtime opcodes. The direct-transfer failure smoke test also confirms that an over-balance attempt leaves balances intact and the holder can subsequently transfer their entire balance. Two fuzz tests each run 1,000 cases; the sequence test checks conservation after each of 32 mixed direct and delegated transfers per case.

The pool test exercises ERC-20 movements at the specified PoolManager address. It does not simulate AMM pricing or execute a live Uniswap v4 swap. The supplied platform protection harness depends on the launch platform's contracts and deployment environment and is not included in the local suite. No live fork or deployment was performed; actual pool initialization, seeding and swaps remain checks for the launch platform.
