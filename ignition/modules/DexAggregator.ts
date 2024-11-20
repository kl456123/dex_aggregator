// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const FillQuoteTransformerModule = buildModule("FillQuoteTransformerModule", (m)=>{
    const wrapperTokenAddr = m.getParameter("wrapperToken");
    const bridgeAdapter = m.contract('BridgeAdapter', [wrapperTokenAddr])
    const fillQuoteTransformer = m.contract("FillQuoteTransformer", [bridgeAdapter]);
    return { fillQuoteTransformer }
});

const DexAggregatorModule = buildModule("DexAggregatorModule", (m) => {
  const wrapperTokenAddr = m.getParameter("wrapperToken");
  const contractOwner = m.getParameter("contractOwner");
  const { fillQuoteTransformer } = m.useModule(FillQuoteTransformerModule);

  const dexAggregator = m.contract("DexAggregatorFlashWallet", [contractOwner, [fillQuoteTransformer], wrapperTokenAddr]);

  return { dexAggregator };
});

export default DexAggregatorModule;
