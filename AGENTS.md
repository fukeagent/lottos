# Repository Guidelines

## Project Structure & Module Organization

Production Solidity lives in `contracts/`: the token, lottery engine, Uniswap v4 hook, and `mocks/`. Foundry tests live in `test/`; feature-era suites are grouped under `test/v18/`, `test/v21/`, and `test/v22/`. Deployment code is in `script/`, while architecture and security notes are under `docs/`. Treat `_backup/` as archived reference. Do not edit dependencies in `lib/` or generated `out/`, `cache/`, `artifacts/`, and `broadcast/` content.

## Build, Test, and Development Commands

- `forge build --sizes` compiles with Solidity 0.8.26, Cancun EVM settings, optimizer, and IR enabled.
- `forge test -vvv` runs the full Foundry suite with CI-level diagnostics.
- `forge test --match-contract V22RewardPolicyTest -vvv` runs a focused suite; use `--match-test test_Name` for one case.
- `forge fmt` formats Solidity; `forge fmt --check` verifies formatting without changing files.
- `forge snapshot` records gas usage for gas-sensitive changes.
- `anvil` starts a local chain. Deploy locally with `forge script script/DeployLocalV4.s.sol:DeployLocalV4 --rpc-url <url> --broadcast` and a disposable account.

`npm test` is currently a placeholder and should not be used as the validation command.

## Coding Style & Naming Conventions

Let `forge fmt` define indentation and wrapping. Use `PascalCase` for contracts, interfaces, libraries, and enums; `camelCase` for functions and variables; and `UPPER_SNAKE_CASE` for constants. Keep SPDX identifiers and explicit pragmas. Name test files `Feature.t.sol`, test contracts `FeatureTest`, and cases `test_ExpectedBehavior`; use `testFuzz_` for fuzz cases. Document security-sensitive state transitions.

## Testing Guidelines

Tests use `forge-std/Test.sol` and Foundry cheatcodes. Add regressions beside the affected feature/version. Cover success, revert, boundary, authorization, payout-failure, and cleanup paths. Before submitting, run formatting, the focused suite, and the full suite. CI enforces formatting, compilation, and tests; no coverage threshold is configured.

## Commit & Pull Request Guidelines

History favors concise imperative Conventional Commit subjects, especially `fix:`, `feat:`, and `docs:`. Keep commits scoped and exclude generated artifacts. Pull requests should explain behavior and security impact, identify affected contracts, link issues or design notes, and report exact test commands/results. Include gas or storage impact for hot-path changes.

## Security & Configuration

Never commit private keys or populated `.env` files. Hardhat reads `WALLET_PRIVATE_KEY` and network-specific RPC variables. Confirm chain ID, RPC URL, deployer, hook address flags, and constructor arguments before any broadcast. Treat lottery randomness, snapshots, tax routing, and payout retries as security-critical code requiring adversarial tests.
