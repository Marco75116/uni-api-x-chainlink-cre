import {
  EVMClient,
  EVMLog,
  handler,
  logTriggerConfig,
  Runner,
  type Runtime,
} from "@chainlink/cre-sdk";
import { decodeEventLog, type Hex } from "viem";
import UniswapV3PoolABI from "./abi/UniswapV3Pool.json";

// keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)")
const SWAP_EVENT_TOPIC: Hex =
  "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67";

export type Config = {
  poolAddress: Hex;
  chainSelector: string;
};

export const onSwapTrigger = (
  runtime: Runtime<Config>,
  triggerOutput: EVMLog
): string => {
  const topics = triggerOutput.topics.map(
    (t) => ("0x" + Buffer.from(t).toString("hex")) as Hex
  ) as [Hex, ...Hex[]];
  const data = ("0x" + Buffer.from(triggerOutput.data).toString("hex")) as Hex;

  const decoded = decodeEventLog({
    abi: UniswapV3PoolABI,
    eventName: "Swap",
    topics,
    data,
  });

  const args = decoded.args as unknown as {
    sender: Hex;
    recipient: Hex;
    amount0: bigint;
    amount1: bigint;
    sqrtPriceX96: bigint;
    liquidity: bigint;
    tick: number;
  };
  const { sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick } = args;

  runtime.log(
    `Swap detected on pool ${runtime.config.poolAddress}: tick=${tick}, sqrtPriceX96=${sqrtPriceX96}, liquidity=${liquidity}`
  );
  runtime.log(`  sender=${sender}, recipient=${recipient}`);
  runtime.log(`  amount0=${amount0}, amount1=${amount1}`);

  return `swap:tick=${tick}`;
};

export const initWorkflow = (config: Config) => {
  const evmClient = new EVMClient(
    EVMClient.SUPPORTED_CHAIN_SELECTORS[
      config.chainSelector as keyof typeof EVMClient.SUPPORTED_CHAIN_SELECTORS
    ]
  );

  return [
    handler(
      evmClient.logTrigger(
        logTriggerConfig({
          addresses: [config.poolAddress],
          topics: [[SWAP_EVENT_TOPIC]],
          confidence: "LATEST",
        })
      ),
      onSwapTrigger
    ),
  ];
};

export async function main() {
  const runner = await Runner.newRunner<Config>();
  await runner.run(initWorkflow);
}
