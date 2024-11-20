import { TronWeb, utils, Contract } from "tronweb";
import DexAggregatorFacet from "../out/DexAggregatorProxy.sol/DexAggregatorProxy.json";
import DexAggregatorFlashWallet from "../out/DexAggregatorFlashWallet.sol/DexAggregatorFlashWallet.json";
import BridgeAdapterJson from "../out/BridgeAdapter.sol/BridgeAdapter.json";
import FillQuoteTransformerJson from "../out/FillQuoteTransformer.sol/FillQuoteTransformer.json";
import IERC20 from "../out/IERC20.sol/IERC20.json";
import IWETH from "../out/IWETH.sol/IWETH.json";
import { ethers, BigNumberish } from "ethers";

import dotenv from "dotenv";
dotenv.config();

// global constants
const univ2RouterAddress = "TPnTVkeymNYy32VurhGeycx9UkqB7gJb5M";
const univ3RouterAddress = "";

const wtrx = "TLi1ygS2MEr926gyFUWYNxeBJ24yVGDZse";
const meme = "TA3HgieqKUBXEt799FDZmGibzn69dH9z8P";
const usdc = "";

const bridgeAdapterAddress = "TR7ifF26gNYo3gEASzwVWhJ65qsstRM7q5";
const fillQuoteTransformerAddress = "TG2rPuuK9cv4MsTmhEgkjTQENnh8j2jNgK";
const dexAggregatorAddress = "TPiwEBFpdqUwh1ZG4SP4PthF5orqEoPPaf";
const dexAggregatorFacetAddress = "TFyVNyE4kLXbWwXCFe3qf6DLpLPWZt6RDT";

const defaultSendOptions = {
  shouldPollResponse: true,
  feeLimit: 1000 * 1e6,
};

async function deploy(tronWeb: TronWeb, wethAddress: string) {
  // about ~839 trx
  // address: TR7ifF26gNYo3gEASzwVWhJ65qsstRM7q5
  const bridgeAdapter = await tronWeb.contract().new({
    abi: BridgeAdapterJson.abi,
    bytecode: BridgeAdapterJson.bytecode.object,
    feeLimit: 1000 * 1e6,
    callValue: 0,
    parameters: [wethAddress],
  });
  console.log(bridgeAdapter.address);
  // about 164 trx
  // address: "TG2rPuuK9cv4MsTmhEgkjTQENnh8j2jNgK"
  const fillQuoteTransformer = await tronWeb.contract().new({
    abi: FillQuoteTransformerJson.abi,
    bytecode: FillQuoteTransformerJson.bytecode.object,
    feeLimit: 1000 * 1e6,
    callValue: 0,
    userFeePercentage: 0,
    parameters: ["TR7ifF26gNYo3gEASzwVWhJ65qsstRM7q5"],
  });
  console.log(fillQuoteTransformer.address);
  // 781 trx
  // address: TPiwEBFpdqUwh1ZG4SP4PthF5orqEoPPaf
  const dexAggregator = await tronWeb.contract().new({
    abi: DexAggregatorFlashWallet.abi,
    bytecode: DexAggregatorFlashWallet.bytecode.object,
    feeLimit: 1000 * 1e6,
    callValue: 0,
    parameters: [wethAddress],
  });
  console.log(dexAggregator.address);

  // trx
  // address: TFyVNyE4kLXbWwXCFe3qf6DLpLPWZt6RDT
  const dexAggregatorFacet = await tronWeb.contract().new({
    abi: DexAggregatorFacet.abi,
    bytecode: DexAggregatorFacet.bytecode.object,
    feeLimit: 1000 * 1e6,
    callValue: 0,
    parameters: ["TPiwEBFpdqUwh1ZG4SP4PthF5orqEoPPaf"],
  });
  console.log(dexAggregatorFacet.address);
  return {
    bridgeAdapter: "",
    fillQuoteTransformer: { address: "" },
    dexAggregator: "",
    dexAggregatorFacet,
  };
}

function getContract(tronWeb: TronWeb) {
  const bridgeAdapter = tronWeb.contract(
    BridgeAdapterJson.abi,
    bridgeAdapterAddress
  );

  const fillQuoteTransformer = tronWeb.contract(
    FillQuoteTransformerJson.abi,
    fillQuoteTransformerAddress
  );

  const dexAggregator = tronWeb.contract(
    DexAggregatorFlashWallet.abi,
    dexAggregatorAddress
  );

  const dexAggregatorFacet = tronWeb.contract(
    DexAggregatorFacet.abi,
    dexAggregatorFacetAddress
  );
  return {
    bridgeAdapter,
    fillQuoteTransformer,
    dexAggregator,
    dexAggregatorFacet,
  };
}

function toEvmAddress(tronAddress: string) {
  return "0x" + TronWeb.address.toHex(tronAddress).slice(2);
}

export function encodeBridgeSourceId(protocol: number, name: string): string {
  const nameBuf = Buffer.from(name);
  if (nameBuf.length > 16) {
    throw new Error(
      `"${name}" is too long to be a bridge source name (max of 16 ascii chars)`
    );
  }
  return ethers.hexlify(
    ethers.concat([
      ethers.zeroPadValue(ethers.getBytes(ethers.toBeHex(protocol)), 16),
      ethers.getBytes(ethers.encodeBytes32String(name)).slice(0, 16),
    ])
  );
}

function createTransformations(
  inputToken: string,
  outputToken: string,
  transformerAddress: string
) {
  inputToken = toEvmAddress(inputToken);
  outputToken = toEvmAddress(outputToken);
  const abiEncoder = ethers.AbiCoder.defaultAbiCoder();
  const bridgeOrderData = abiEncoder.encode(
    ["tuple(address router,address[] path)"],
    [
      {
        router: toEvmAddress(univ2RouterAddress),
        path: [inputToken, outputToken],
      },
    ]
  );

  const bridgeOrder = {
    source: encodeBridgeSourceId(2, "UniswapV2"),
    makerTokenAmount: 0,
    takerTokenAmount: ethers.MaxUint256,
    bridgeData: bridgeOrderData,
  };

  const transformData = abiEncoder.encode(
    [
      "tuple(uint8 side, address sellToken, address buyToken, tuple(bytes32 source, uint256 takerTokenAmount, uint256 makerTokenAmount, bytes bridgeData) bridgeOrder, uint256 fillAmount)",
    ],
    [
      {
        side: 0,
        sellToken: inputToken,
        buyToken: outputToken,
        bridgeOrder,
        fillAmount: ethers.MaxUint256,
      },
    ]
  );

  return [transformerAddress, transformData];
}

interface Fixture {
  fillQuoteTransformer: Contract;
  dexAggregator: Contract;
  dexAggregatorFacet: Contract;
  tronWeb: TronWeb;
  wtrxToken: Contract;
  sender: string;
}

enum MultiplexSubcall {
  Invalid,
  TransformERC20,
  BatchSell,
  MultiHopSell,
}

async function prepareTokenForContract(
  wtrxToken: Contract,
  inputTokenAmount: BigNumberish,
  target: string,
  sender: string
) {
  const balance = await wtrxToken.balanceOf(sender).call();
  console.log(balance);
  if (balance < BigInt(inputTokenAmount)) {
    await wtrxToken
      .deposit()
      .send({ ...defaultSendOptions, callValue: inputTokenAmount });
  }
  if ((await wtrxToken.allowance(sender, target)) < BigInt(inputTokenAmount)) {
    await wtrxToken.approve(target, ethers.MaxUint256).send(defaultSendOptions);
  }
}

async function testTransformERC20(fixture: Fixture) {
  const { fillQuoteTransformer, tronWeb, dexAggregator, wtrxToken, sender } =
    fixture;
  const inputToken = wtrx; // wtrx
  const outputToken = meme; // meme
  const inputTokenAmount = 1 * 1e5;
  const minOutputTokenAmount = 0;
  const transformations = [
    createTransformations(
      inputToken,
      outputToken,
      fillQuoteTransformer.address as string
    ),
  ];

  // approve before trade
  await prepareTokenForContract(
    wtrxToken,
    inputTokenAmount,
    dexAggregator.address as string,
    sender as string
  );
  await dexAggregator
    .transformERC20(
      inputToken,
      outputToken,
      inputTokenAmount,
      minOutputTokenAmount,
      transformations
    )
    .send({
      feeLimit: 1000 * 1e6,
      shouldPollResponse: true,
    });
}

function encodeSellAmount(rate: number) {
  const HIGH_BITS = 1n << 255n;
  const BASE = 1n << 18n;
  return ((BigInt(rate) * BASE) % HIGH_BITS) + HIGH_BITS;
}

function encodeTokenWithFee(token: string, fee: number) {
  return BigInt(toEvmAddress(token));
}

async function testMultiHopSell(fixture: Fixture) {
  const {
    dexAggregator,
    fillQuoteTransformer,
    dexAggregatorFacet,
    tronWeb,
    wtrxToken,
    sender,
  } = fixture;
  const defaultAbiCoder = ethers.AbiCoder.defaultAbiCoder();
  const inputToken = wtrx; // wtrx
  const outputToken = meme; // meme
  const tokens = [inputToken, outputToken];
  const inputTokenAmount = 1 * 1e5;
  const minOutputTokenAmount = 0;
  const transformation = createTransformations(
    inputToken,
    outputToken,
    fillQuoteTransformer.address as string
  );

  const transformations = [
    { transformer: toEvmAddress(transformation[0]), data: transformation[1] },
  ];
  const encodedTransformData = defaultAbiCoder.encode(
    ["tuple(address transformer,bytes data)[]"],
    [transformations]
  );
  const batchSubcalls = [
    {
      id: MultiplexSubcall.TransformERC20,
      sellAmount: encodeSellAmount(100),
      data: encodedTransformData,
    },
  ];
  const encodedBatchCalls = defaultAbiCoder.encode(
    ["tuple(uint8 id,uint256 sellAmount,bytes data)[]"],
    [batchSubcalls]
  );

  const multiHopSubcalls = [
    { id: MultiplexSubcall.BatchSell, data: encodedBatchCalls },
  ];

  const iface = new ethers.Interface(DexAggregatorFlashWallet.abi);
  const callData = iface.encodeFunctionData(
    "multiplexMultiHopSellTokenForToken",
    [
      tokens.map(toEvmAddress),
      multiHopSubcalls,
      inputTokenAmount,
      minOutputTokenAmount,
    ]
  );
  const fromTokenWithFee = encodeTokenWithFee(inputToken, 0);
  const toTokenWithFee = encodeTokenWithFee(outputToken, 0);

  await prepareTokenForContract(
    wtrxToken,
    inputTokenAmount,
    dexAggregatorFacet.address as string,
    sender as string
  );
  await dexAggregatorFacet
    .callDexAggregator(
      fromTokenWithFee,
      inputTokenAmount,
      toTokenWithFee,
      callData
    )
    .send(defaultSendOptions);
}

async function testBatchSell(fixture: Fixture) {
  const {
    dexAggregator,
    fillQuoteTransformer,
    dexAggregatorFacet,
    tronWeb,
    wtrxToken,
    sender,
  } = fixture;
  const defaultAbiCoder = ethers.AbiCoder.defaultAbiCoder();
  const inputToken = wtrx; // wtrx
  const outputToken = meme; // meme
  const inputTokenAmount = 1 * 1e5;
  const minOutputTokenAmount = 0;
  const transformation = createTransformations(
    inputToken,
    outputToken,
    fillQuoteTransformer.address as string
  );

  const transformations = [
    { transformer: toEvmAddress(transformation[0]), data: transformation[1] },
  ];
  const encodedTransformData = defaultAbiCoder.encode(
    ["tuple(address transformer,bytes data)[]"],
    [transformations]
  );
  const batchSubcalls = [
    {
      id: MultiplexSubcall.TransformERC20,
      sellAmount: encodeSellAmount(100),
      data: encodedTransformData,
    },
  ];
  const iface = new ethers.Interface(DexAggregatorFlashWallet.abi);
  const callData = iface.encodeFunctionData("multiplexBatchSellTokenForToken", [
    toEvmAddress(inputToken),
    toEvmAddress(outputToken),
    batchSubcalls,
    inputTokenAmount,
    minOutputTokenAmount,
  ]);
  const fromTokenWithFee = encodeTokenWithFee(inputToken, 0);
  const toTokenWithFee = encodeTokenWithFee(outputToken, 0);

  await prepareTokenForContract(
    wtrxToken,
    inputTokenAmount,
    dexAggregatorFacet.address as string,
    sender
  );
  await dexAggregatorFacet
    .callDexAggregator(
      fromTokenWithFee,
      inputTokenAmount,
      toTokenWithFee,
      callData
    )
    .send(defaultSendOptions);
}

async function main() {
  const API_KEY = "ffdbac96-0284-4df9-840c-5e5c32499698";
  // const rpcUrl = "https://api.trongrid.io";
  const rpcUrl = "https://api.shasta.trongrid.io";
  const tronWeb = new TronWeb({
    fullHost: rpcUrl,
    headers: { "TRON-PRO-API-KEY": API_KEY },
    privateKey: process.env.TRON_PRIVATE_KEY,
  });

  // const {bridgeAdapter, fillQuoteTransformer, dexAggregator} = await deploy(tronWeb, wtrx);
  const {
    dexAggregator,
    fillQuoteTransformer,
    bridgeAdapter,
    dexAggregatorFacet,
  } = getContract(tronWeb);
  // await testTransformERC20({ dexAggregator, tronWeb, fillQuoteTransformer });
  // await testMultiHopSell({
  // dexAggregator,
  // tronWeb,
  // fillQuoteTransformer,
  // dexAggregatorFacet,
  // });

  const sender = tronWeb.defaultAddress.base58 as string;
  const wtrxToken = tronWeb.contract([...IERC20.abi, ...IWETH.abi], wtrx);

  await testBatchSell({
    dexAggregator,
    tronWeb,
    fillQuoteTransformer,
    dexAggregatorFacet,
    wtrxToken,
    sender,
  });
}

main();
