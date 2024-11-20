// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DexAggregatorFlashWallet} from "contracts/DexAggregatorFlashWallet.sol";
import {BridgeAdapter} from "contracts/transformers/bridges/BridgeAdapter.sol";
import {FillQuoteTransformer} from "contracts/transformers/FillQuoteTransformer.sol";

import {ITransformERC20Feature} from "contracts/interfaces/ITransformERC20Feature.sol";
import {IMultiplexFeature} from "contracts/interfaces/IMultiplexFeature.sol";

import {console} from "forge-std/Script.sol";

contract DexAggregatorFacetDeployer {
    function _getWETHAddress(uint256 chainId) private pure returns (address) {
        if (chainId == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (chainId == 56) {
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        revert("DexAggregatorFacetDeployer: invalid chainId");
    }

    function deployDexAggregatorFacetAndFuncSigList(address owner, uint256 chainId)
        public
        returns (address, address, address)
    {
        address bridgeAdapter = address(new BridgeAdapter(_getWETHAddress(chainId)));
        address fillQuoteTransformer = address(new FillQuoteTransformer(bridgeAdapter));
        address[] memory transformers = new address[](1);
        transformers[0] = fillQuoteTransformer;
        address dexAggregator = address(new DexAggregatorFlashWallet(owner, transformers, _getWETHAddress(chainId)));

        return (bridgeAdapter, fillQuoteTransformer, dexAggregator);
    }
}
