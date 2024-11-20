// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DexAggregatorProxy is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant FEE_PERCENTAGE_BASE = 10000;
    uint256 private constant HIGH_BIT = 2 ** 255;

    address private immutable aggregator;

    constructor(address _aggregator) {
        require(_aggregator != address(0) && _aggregator.code.length > 100, "AggregatorProxy: invalid aggregator");
        aggregator = _aggregator;
    }

    function _parseAddressAndFee(uint256 tokenWithFee)
        internal
        pure
        returns (address token, uint16 fee, bool preTransfer)
    {
        token = address(uint160(tokenWithFee));
        fee = uint16(tokenWithFee >> 160);
        require(fee < FEE_PERCENTAGE_BASE, "AggregatorProxy: invalid fee");
        // top bit
        preTransfer = (tokenWithFee & HIGH_BIT) == HIGH_BIT;
    }

    function callDexAggregator(
        uint256 fromTokenWithFee,
        uint256 fromAmount,
        uint256 toTokenWithFee,
        bytes calldata callData
    ) external payable nonReentrant {
        uint256 ethBalanceBefore = address(this).balance - msg.value;
        (address fromToken,,) = _parseAddressAndFee(fromTokenWithFee);
        (address toToken,,) = _parseAddressAndFee(toTokenWithFee);

        uint256 value;

        if (fromToken == address(0)) {
            value = fromAmount;
        } else {
            IERC20(fromToken).safeTransferFrom(msg.sender, aggregator, fromAmount);
        }

        uint256 toTokenBalanceBefore;
        if (toToken != address(0)) {
            toTokenBalanceBefore = IERC20(toToken).balanceOf(address(this));
        }

        Address.functionCallWithValue(aggregator, callData, value);

        if (toToken == address(0)) {
            uint256 balanceDiff = address(this).balance - ethBalanceBefore;
            if (balanceDiff > 0) {
                Address.sendValue(payable(msg.sender), balanceDiff);
            }
        } else {
            uint256 balanceDiff = IERC20(toToken).balanceOf(address(this)) - toTokenBalanceBefore;
            if (balanceDiff > 0) {
                IERC20(toToken).safeTransfer(msg.sender, balanceDiff);
            }
        }
    }
}
