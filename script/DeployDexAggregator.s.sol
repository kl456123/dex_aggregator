// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {DexAggregatorFacetDeployer} from "./DexAggregatorDeployer.sol";

contract DeployDexAggregatorScript is Script, DexAggregatorFacetDeployer {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("BN_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("deployer: ", deployer);
        vm.startBroadcast(deployerPrivateKey);

        (address bridgeAdapter, address fillQuoteTransformer, address dexAggregator) =
            deployDexAggregatorFacetAndFuncSigList(deployer, block.chainid);

        console.log("BridgeAdapter: ", bridgeAdapter);
        console.log("FillQuoteTransformer: ", fillQuoteTransformer);
        console.log("DexAggregator: ", dexAggregator);

        vm.stopBroadcast();
    }
}
