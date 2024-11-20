// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "./MultiplexFeature.sol";
import "./TransformERC20Feature.sol";

contract DexAggregatorFlashWallet is MultiplexFeature, TransformERC20Feature {
    constructor(address contractOwner, address[] memory transformers, address weth)
        MultiplexFeature(weth)
        TransformERC20Feature(contractOwner, transformers)
    {}
}
