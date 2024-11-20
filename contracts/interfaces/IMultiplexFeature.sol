// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMultiplexFeature {
    enum MultiplexSubcall {
        Invalid,
        TransformERC20,
        BatchSell,
        MultiHopSell
    }

    struct BatchSellParams {
        IERC20 inputToken;
        IERC20 outputToken;
        bool useSelfBalance;
        uint256 sellAmount;
        BatchSellSubcall[] calls;
        address recipient;
    }

    struct BatchSellSubcall {
        MultiplexSubcall id;
        uint256 sellAmount;
        bytes data;
    }

    struct BatchSellState {
        uint256 soldAmount;
        uint256 boughtAmount;
    }

    struct MultiHopSellParams {
        address[] tokens;
        uint256 sellAmount;
        MultiHopSellSubcall[] calls;
        address recipient;
        bool useSelfBalance;
    }

    struct MultiHopSellSubcall {
        MultiplexSubcall id;
        bytes data;
    }

    struct MultiHopSellState {
        uint256 outputTokenAmount;
        address from;
        address to;
        uint256 hopIndex;
    }

    /// @dev Sells attached ETH for `outputToken` using the provided
    ///      calls.
    /// @param outputToken The token to buy.
    /// @param calls The calls to use to sell the attached ETH.
    /// @param minBuyAmount The minimum amount of `outputToken` that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of `outputToken` bought.
    function multiplexBatchSellEthForToken(IERC20 outputToken, BatchSellSubcall[] calldata calls, uint256 minBuyAmount)
        external
        payable
        returns (uint256 boughtAmount);

    /// @dev Sells `sellAmount` of the given `inputToken` for ETH
    ///      using the provided calls.
    /// @param inputToken The token to sell.
    /// @param calls The calls to use to sell the input tokens.
    /// @param sellAmount The amount of `inputToken` to sell.
    /// @param minBuyAmount The minimum amount of ETH that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of ETH bought.
    function multiplexBatchSellTokenForEth(
        IERC20 inputToken,
        BatchSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external returns (uint256 boughtAmount);

    function multiplexBatchSellTokenForToken(
        IERC20 inputToken,
        IERC20 outputToken,
        BatchSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external returns (uint256 boughtAmount);

    /// @dev Sells attached ETH via the given sequence of tokens
    ///      and calls. `tokens[0]` must be WETH.
    ///      The last token in `tokens` is the output token that
    ///      will ultimately be sent to `msg.sender`
    /// @param tokens The sequence of tokens to use for the sell,
    ///        i.e. `tokens[i]` will be sold for `tokens[i+1]` via
    ///        `calls[i]`.
    /// @param calls The sequence of calls to use for the sell.
    /// @param minBuyAmount The minimum amount of output tokens that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of output tokens bought.
    function multiplexMultiHopSellEthForToken(
        address[] calldata tokens,
        MultiHopSellSubcall[] calldata calls,
        uint256 minBuyAmount
    ) external payable returns (uint256 boughtAmount);

    /// @dev Sells `sellAmount` of the input token (`tokens[0]`)
    ///      for ETH via the given sequence of tokens and calls.
    ///      The last token in `tokens` must be WETH.
    /// @param tokens The sequence of tokens to use for the sell,
    ///        i.e. `tokens[i]` will be sold for `tokens[i+1]` via
    ///        `calls[i]`.
    /// @param calls The sequence of calls to use for the sell.
    /// @param minBuyAmount The minimum amount of ETH that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of ETH bought.
    function multiplexMultiHopSellTokenForEth(
        address[] calldata tokens,
        MultiHopSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external returns (uint256 boughtAmount);

    function multiplexMultiHopSellTokenForToken(
        address[] calldata tokens,
        MultiHopSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) external returns (uint256 boughtAmount);
}
