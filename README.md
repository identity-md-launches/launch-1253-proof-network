# Proof Network (PROOF)

This repository contains the fixed-supply token, its launch manifest, and five logo options. The selected image-generated wallet mark is [artifacts/logo.png](artifacts/logo.png); the options and generation record are described in [logos/README.md](logos/README.md).

`PROOFToken` mints exactly 1,000,000,000 PROOF with 18 decimals (1e27 minor units) to `msg.sender` in its constructor. It accepts no constructor arguments. Supply, name, symbol and decimals are constants. There are no owner roles, admin functions, further minting, burning, fees, transfer limits, proxies or external calls. The contract exposes the standard ERC-20 metadata, balances, allowances, `approve`, `transfer` and `transferFrom`. A maximum allowance remains unchanged when spent; finite allowances are consumed. Transfers to the zero address revert.

The token performs no distribution. The launch factory receives the entire supply and handles the swarm's 10%, pool funding and remainder. [launch.json](launch.json) records the specified IMD pair, fee 12500, tick spacing 60, provenance price and economics. The launch derives the actual opening price from those economics and the deployed currency order.

## Build and tests

With Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
```

The project requires no downloaded libraries, network access, RPC configuration or environment variables. All Solidity imports resolve within the repository. `foundry.toml` pins Solidity 0.8.26, Cancun, optimization and `bytecode_hash = "none"`.

The 17 local tests cover the constructor allocation and mint event, exact factory/distributor/pool transfer legs, transfer events, zero amounts, self transfers, full-balance transfers, allowance replacement and revocation, finite and infinite allowances, atomic failures, absent privileged functions and forbidden runtime opcodes. Two fuzz tests each run 1,000 cases; the sequence test checks conservation after each of 32 mixed direct and delegated transfers per case.

The pool test exercises ERC-20 movements at the specified PoolManager address. It does not simulate AMM pricing or execute a live Uniswap v4 swap. The supplied platform protection harness depends on the launch platform's contracts and deployment environment and is not included in the local suite. No live fork or deployment was performed; actual pool initialization, seeding and swaps remain checks for the launch platform.
