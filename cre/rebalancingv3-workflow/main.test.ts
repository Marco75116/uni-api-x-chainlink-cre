import { describe, expect } from "bun:test";
import { newTestRuntime, test } from "@chainlink/cre-sdk/test";
import { onSwapTrigger, initWorkflow } from "./main";
import type { Config } from "./main";

const TEST_POOL = "0x254aa3A898071D6A2dA0DB11dA73b02B4646078F";
const TEST_CONFIG: Config = {
  poolAddress: TEST_POOL,
  chainSelector: "ethereum-testnet-sepolia",
};

describe("initWorkflow", () => {
  test("returns one handler with EVM logTrigger", async () => {
    const handlers = initWorkflow(TEST_CONFIG);

    expect(handlers).toBeArray();
    expect(handlers).toHaveLength(1);
    expect(handlers[0].trigger.capabilityId()).toContain("evm");
    expect(handlers[0].trigger.capabilityId()).toContain("@1.0.0");
  });

  test("trigger config includes the pool address", async () => {
    const handlers = initWorkflow(TEST_CONFIG);
    const triggerConfig = handlers[0].trigger.config;

    expect(triggerConfig.addresses.length).toBe(1);
    expect(triggerConfig.topics.length).toBeGreaterThanOrEqual(1);
    // First topic array should contain the Swap event signature
    expect(triggerConfig.topics[0].values.length).toBe(1);
  });
});

describe("onSwapTrigger", () => {
  test("decodes swap event and returns tick", async () => {
    const runtime = newTestRuntime();
    runtime.config = TEST_CONFIG;

    // Swap event signature: keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)")
    const swapEventSig = Buffer.from(
      "c42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67",
      "hex"
    );
    // Indexed: sender (address padded to 32 bytes)
    const senderTopic = Buffer.from(
      "0000000000000000000000000000000000000000000000000000000000000001",
      "hex"
    );
    // Indexed: recipient (address padded to 32 bytes)
    const recipientTopic = Buffer.from(
      "0000000000000000000000000000000000000000000000000000000000000002",
      "hex"
    );

    // ABI-encoded non-indexed params:
    // amount0 (int256) = 1000
    // amount1 (int256) = -500
    // sqrtPriceX96 (uint160) = 100
    // liquidity (uint128) = 200
    // tick (int24) = 42
    const data = Buffer.from(
      "00000000000000000000000000000000000000000000000000000000000003e8" + // amount0 = 1000
      "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0c" + // amount1 = -500
      "0000000000000000000000000000000000000000000000000000000000000064" + // sqrtPriceX96 = 100
      "00000000000000000000000000000000000000000000000000000000000000c8" + // liquidity = 200
      "000000000000000000000000000000000000000000000000000000000000002a",  // tick = 42
      "hex"
    );

    const mockLog = {
      address: new Uint8Array(20),
      topics: [
        new Uint8Array(swapEventSig),
        new Uint8Array(senderTopic),
        new Uint8Array(recipientTopic),
      ],
      txHash: new Uint8Array(32),
      blockHash: new Uint8Array(32),
      data: new Uint8Array(data),
      eventSig: new Uint8Array(swapEventSig),
    };

    const result = onSwapTrigger(runtime as any, mockLog as any);

    expect(result).toBe("swap:tick=42");
    const logs = runtime.getLogs();
    expect(logs.some((l: string) => l.includes("tick=42"))).toBe(true);
    expect(logs.some((l: string) => l.includes("sqrtPriceX96=100"))).toBe(true);
    expect(logs.some((l: string) => l.includes("amount0=1000"))).toBe(true);
    expect(logs.some((l: string) => l.includes("amount1=-500"))).toBe(true);
  });

  test("handler wiring passes log to onSwapTrigger", async () => {
    const runtime = newTestRuntime();
    runtime.config = TEST_CONFIG;
    const handlers = initWorkflow(TEST_CONFIG);

    const swapEventSig = Buffer.from(
      "c42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67",
      "hex"
    );
    const data = Buffer.from(
      "00000000000000000000000000000000000000000000000000000000000003e8" +
      "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0c" +
      "0000000000000000000000000000000000000000000000000000000000000064" +
      "00000000000000000000000000000000000000000000000000000000000000c8" +
      "000000000000000000000000000000000000000000000000000000000000002a",
      "hex"
    );
    const mockLog = {
      address: new Uint8Array(20),
      topics: [
        new Uint8Array(swapEventSig),
        new Uint8Array(Buffer.alloc(32, 0)),
        new Uint8Array(Buffer.alloc(32, 0)),
      ],
      txHash: new Uint8Array(32),
      blockHash: new Uint8Array(32),
      data: new Uint8Array(data),
      eventSig: new Uint8Array(swapEventSig),
    };

    const result = handlers[0].fn(runtime as any, mockLog as any);
    expect(result).toBe("swap:tick=42");
  });
});
