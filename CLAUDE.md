# Project: Uniswap Automation with Chainlink CRE

## Goal

Build automation on the Uniswap protocol using the Chainlink Runtime Environment (CRE).

- **Chainlink CRE**: Used to create workflows that automate on-chain actions. Docs: https://docs.chain.link/cre
- **Uniswap Trading API**: Used to execute token swaps programmatically. Docs: https://api-docs.uniswap.org/introduction

## Implementation: Automated LP Rebalancing via ERC-4337 Smart Account

### Overview

Automated concentrated liquidity rebalancing for Uniswap V3 positions, using a CRE workflow as the brain and an ERC-4337 smart account as the executor.

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
│  STEP 2: Send to Smart Account                          │
│  ├─ Input: swap TransactionRequest object               │
│  └─ Smart account executes atomically:                  │
│      1. Withdraw liquidity from current position        │
│      2. Collect accrued fees                            │
│      3. Execute the swap (from API calldata)            │
│      4. Mint new position at updated tick range         │
└─────────────────────────────────────────────────────────┘
```

### Components

1. **ERC-4337 Smart Account** — Owns the Uniswap V3 LP position. Executes the full rebalance atomically in a single UserOperation (withdraw → swap → mint). Enables gasless execution via a Paymaster.

2. **CRE Workflow** — Triggered by on-chain Swap events on the pool. Reads the current tick, checks if the position is out of range, calls the Uniswap Trading API to build the swap calldata, and sends the rebalance instruction to the smart account.

3. **Uniswap Trading API** — Called by CRE to get the optimal swap route. Returns a `TransactionRequest` with pre-encoded calldata (paths, pools, amounts) that the smart account forwards to the Universal Router.

### Key Design Decisions

- **Why ERC-4337**: Atomic multi-step execution (withdraw + swap + mint in one tx), gas sponsorship via Paymaster, no EOA key management in CRE.
- **Why trigger on Swap events**: Every swap moves the tick — checking on each swap tells us immediately when our position goes out of range.
- **Why use the Trading API for swap calldata**: The API handles routing optimization (multi-hop, split routes, fee tier selection) so the smart account contract stays simple.

## Skills

This project has two installed skills:

### chainlink-cre-skill (smartcontractkit/chainlink-agent-skills)
CRE developer onboarding, workflow generation (TypeScript/Go), CLI and SDK help, runtime operations, and capability selection. Trigger when working on CRE workflows, onboarding, or runtime operations.

### swap-integration (uniswap/uniswap-ai)
Integrate Uniswap swaps into frontends, backends, and smart contracts. Covers the Trading API, Universal Router, and Universal Router SDK. Trigger when working on swap logic, token trading, or Uniswap integration.
