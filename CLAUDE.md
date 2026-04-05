# Project: Uniswap Automation with Chainlink CRE

## Goal

Build automation on the Uniswap protocol using the Chainlink Runtime Environment (CRE).

- **Chainlink CRE**: Used to create workflows that automate on-chain actions. Docs: https://docs.chain.link/cre
- **Uniswap Trading API**: Used to execute token swaps programmatically. Docs: https://api-docs.uniswap.org/introduction

## Monorepo Structure

```
warsaw-v1/
├── contracts/    ← Foundry project (RebalancerVault, LP rebalancing logic)
├── cre/          ← CRE workflow code (TypeScript/Go)
├── CLAUDE.md
└── README.md
```

- `contracts/`: Solidity smart contracts built with Foundry. Contains the RebalancerVault that owns the LP position and executes atomic rebalances.
- `cre/`: Chainlink CRE workflow that monitors pool ticks and triggers rebalances.

## Implementation: Automated LP Rebalancing via RebalancerVault

### Overview

Automated concentrated liquidity rebalancing for Uniswap V3 positions, using a CRE workflow as the brain and a simple vault contract as the executor. No ERC-4337 needed — the CRE workflow sends a regular transaction from an operator EOA.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    CRE Workflow                          │
│                                                         │
│  TRIGGER: On-chain Swap event on the target pool        │
│  ├─ Read current tick from pool                         │
│  ├─ Compare tick vs position's tickLower/tickUpper      │
│  └─ IF position is out of range → continue              │
│                                                         │
│  STEP 1: Call Uniswap Trading API (POST /quote + /swap) │
│  ├─ Get optimal swap route + TransactionRequest         │
│  └─ The calldata encodes Universal Router execute()     │
│      (multi-hop, split routes, multiple pools)          │
│                                                         │
│  STEP 2: Send tx to RebalancerVault.rebalance()         │
│  ├─ Input: swap calldata, new tick range                │
│  └─ Vault executes atomically:                          │
│      1. Withdraw liquidity from current position        │
│      2. Collect accrued fees                            │
│      3. Execute the swap (from API calldata)            │
│      4. Mint new position at updated tick range         │
└─────────────────────────────────────────────────────────┘
```

### Components

1. **RebalancerVault** — Owns the Uniswap V3 LP NFT position. Has two roles:
   - **owner**: Full admin (can withdraw funds, change operator, emergency actions)
   - **operator**: The CRE workflow's EOA address, authorized to call `rebalance()`

   Executes the full rebalance atomically in a single transaction (withdraw → swap → mint).

2. **CRE Workflow** — Triggered by on-chain Swap events on the pool. Reads the current tick, checks if the position is out of range, calls the Uniswap Trading API to build the swap calldata, and sends the rebalance instruction to the vault.

3. **Uniswap Trading API** — Called by CRE to get the optimal swap route. Returns a `TransactionRequest` with pre-encoded calldata (paths, pools, amounts) that the vault forwards to the Universal Router.

### Key Design Decisions

- **Why a simple vault instead of ERC-4337**: The CRE workflow can sign and send transactions via an operator EOA. A simple contract with `onlyOperator` access control achieves the same atomicity without the complexity of UserOperations, bundlers, and EntryPoint.
- **Why owner + operator roles**: The owner retains full control (withdraw, change operator). The operator (CRE) can only call `rebalance()` — minimizing risk if the operator key is compromised.
- **Why trigger on Swap events**: Every swap moves the tick — checking on each swap tells us immediately when our position goes out of range.
- **Why use the Trading API for swap calldata**: The API handles routing optimization (multi-hop, split routes, fee tier selection) so the vault contract stays simple.

## Skills

This project has two installed skills:

### chainlink-cre-skill (smartcontractkit/chainlink-agent-skills)
CRE developer onboarding, workflow generation (TypeScript/Go), CLI and SDK help, runtime operations, and capability selection. Trigger when working on CRE workflows, onboarding, or runtime operations.

### swap-integration (uniswap/uniswap-ai)
Integrate Uniswap swaps into frontends, backends, and smart contracts. Covers the Trading API, Universal Router, and Universal Router SDK. Trigger when working on swap logic, token trading, or Uniswap integration.
