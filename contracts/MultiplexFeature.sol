// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IMultiplexFeature.sol";
import "./interfaces/IEtherToken.sol";
import "./multiplex/MultiplexTransformERC20.sol";

contract MultiplexFeature is IMultiplexFeature, MultiplexTransformERC20 {
    using Math for uint256;
    using SafeERC20 for IERC20;
    /// @dev The highest bit of a uint256 value.

    uint256 private constant HIGH_BIT = 2 ** 255;
    /// @dev Mask of the lower 255 bits of a uint256 value.
    uint256 private constant LOWER_255_BITS = HIGH_BIT - 1;

    /// @dev The WETH token contract.
    IEtherToken private immutable WETH;

    constructor(address weth) {
        WETH = IEtherToken(weth);
    }

    function _executeBatchSell(BatchSellParams memory params) private returns (BatchSellState memory state) {
        for (uint256 i = 0; i < params.calls.length; ++i) {
            if (state.soldAmount >= params.sellAmount) {
                break;
            }
            BatchSellSubcall memory subcall = params.calls[i];
            uint256 inputTokenAmount = _normalizeSellAmount(subcall.sellAmount, params.sellAmount, state.soldAmount);
            if (i == params.calls.length - 1) {
                // use up remain tokens
                inputTokenAmount = params.sellAmount - state.soldAmount;
            }
            if (subcall.id == MultiplexSubcall.MultiHopSell) {
                _nestedMultiHopSell(state, params, subcall.data, inputTokenAmount);
            } else if (subcall.id == MultiplexSubcall.TransformERC20) {
                _batchSellTransformERC20(state, params, subcall.data, inputTokenAmount);
            } else {
                revert("MultiplexFeature::_executeBatchSell/INVALID_SUBCALL");
            }
        }

        require(state.soldAmount == params.sellAmount, "MultiplexFeature::_executeBatchSell/INCORRECT_AMOUNT_SOLD");
    }

    function _executeMultiHopSell(MultiHopSellParams memory params) private returns (MultiHopSellState memory state) {
        state.outputTokenAmount = params.sellAmount;
        state.from = computeHopTarget(params, 0);
        // If the input tokens are currently held by `msg.sender` but
        // the first hop expects them elsewhere, perform a `transferFrom`.
        if (state.from != msg.sender) {
            IERC20(params.tokens[0]).safeTransferFrom(msg.sender, state.from, params.sellAmount);
        }

        for (state.hopIndex = 0; state.hopIndex < params.calls.length; ++state.hopIndex) {
            MultiHopSellSubcall memory subcall = params.calls[state.hopIndex];
            state.to = computeHopTarget(params, state.hopIndex + 1);
            if (subcall.id == MultiplexSubcall.BatchSell) {
                _nestedBatchSell(state, params, subcall.data);
            } else {
                revert("MultiplexFeature::_executeBatchSell/INVALID_SUBCALL");
            }
            state.from = state.to;
        }
    }

    /// @dev Sells attached ETH for `outputToken` using the provided
    ///      calls.
    /// @param outputToken The token to buy.
    /// @param calls The calls to use to sell the attached ETH.
    /// @param minBuyAmount The minimum amount of `outputToken` that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of `outputToken` bought.
    function multiplexBatchSellEthForToken(IERC20 outputToken, BatchSellSubcall[] memory calls, uint256 minBuyAmount)
        public
        payable
        override
        returns (uint256 boughtAmount)
    {
        // Wrap ETH.
        WETH.deposit{value: msg.value}();
        // WETH is now held by this contract,
        // so `useSelfBalance` is true.
        return _multiplexBatchSell(
            BatchSellParams({
                inputToken: WETH,
                outputToken: outputToken,
                sellAmount: msg.value,
                calls: calls,
                useSelfBalance: true,
                recipient: msg.sender
            }),
            minBuyAmount
        );
    }

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
        BatchSellSubcall[] memory calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) public override returns (uint256 boughtAmount) {
        // The outputToken is implicitly WETH. The `recipient`
        // of the WETH is set to  this contract, since we
        // must unwrap the WETH and transfer the resulting ETH.
        boughtAmount = _multiplexBatchSell(
            BatchSellParams({
                inputToken: inputToken,
                outputToken: WETH,
                sellAmount: sellAmount,
                calls: calls,
                useSelfBalance: true,
                recipient: address(this)
            }),
            minBuyAmount
        );
        // Unwrap WETH.
        WETH.withdraw(boughtAmount);
        // Transfer ETH to `msg.sender`.
        Address.sendValue(payable(msg.sender), boughtAmount);
    }

    function multiplexBatchSellTokenForToken(
        IERC20 inputToken,
        IERC20 outputToken,
        BatchSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) public override returns (uint256 boughtAmount) {
        return _multiplexBatchSell(
            BatchSellParams({
                inputToken: inputToken,
                outputToken: outputToken,
                sellAmount: sellAmount,
                calls: calls,
                useSelfBalance: true,
                recipient: msg.sender
            }),
            minBuyAmount
        );
    }

    function _multiplexBatchSell(BatchSellParams memory params, uint256 minBuyAmount)
        private
        returns (uint256 boughtAmount)
    {
        uint256 balanceBefore = params.outputToken.balanceOf(params.recipient);
        BatchSellState memory state = _executeBatchSell(params);
        uint256 balanceDelta = params.outputToken.balanceOf(params.recipient) - balanceBefore;
        boughtAmount = Math.min(balanceDelta, state.boughtAmount);

        require(boughtAmount >= minBuyAmount, "MultiplexFeature::_multiplexBatchSell/UNDERBOUGHT");
    }

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
        address[] memory tokens,
        MultiHopSellSubcall[] memory calls,
        uint256 minBuyAmount
    ) public payable override returns (uint256 boughtAmount) {
        // First token must be WETH.
        require(tokens[0] == address(WETH), "MultiplexFeature::multiplexMultiHopSellEthForToken/NOT_WETH");
        // Wrap ETH.
        WETH.deposit{value: msg.value}();
        // WETH is now held by this contract,
        // so `useSelfBalance` is true.
        return _multiplexMultiHopSell(
            MultiHopSellParams({
                tokens: tokens,
                sellAmount: msg.value,
                calls: calls,
                useSelfBalance: true,
                recipient: msg.sender
            }),
            minBuyAmount
        );
    }

    /// @dev Sells `sellAmount` of the input token (`tokens[0]`)
    ///      for ETH via the given sequence of tokens and calls.
    ///      The last token in `tokens` must be WETH.
    /// @param tokens The sequence of tokens to use for the sell,
    ///        i.e. `tokens[i]` will be sold for `tokens[i+1]` via
    ///        `calls[i]`.
    /// @param calls The sequence of calls to use for the sell.
    /// @param sellAmount The amount of `inputToken` to sell.
    /// @param minBuyAmount The minimum amount of ETH that
    ///        must be bought for this function to not revert.
    /// @return boughtAmount The amount of ETH bought.
    function multiplexMultiHopSellTokenForEth(
        address[] memory tokens,
        MultiHopSellSubcall[] memory calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) public override returns (uint256 boughtAmount) {
        // Last token must be WETH.
        require(
            tokens[tokens.length - 1] == address(WETH), "MultiplexFeature::multiplexMultiHopSellTokenForEth/NOT_WETH"
        );
        // The `recipient of the WETH is set to  this contract, since
        // we must unwrap the WETH and transfer the resulting ETH.
        boughtAmount = _multiplexMultiHopSell(
            MultiHopSellParams({
                tokens: tokens,
                sellAmount: sellAmount,
                calls: calls,
                useSelfBalance: true,
                recipient: address(this)
            }),
            minBuyAmount
        );
        // Unwrap WETH.
        WETH.withdraw(boughtAmount);
        // Transfer ETH to `msg.sender`.
        Address.sendValue(payable(msg.sender), boughtAmount);
    }

    function multiplexMultiHopSellTokenForToken(
        address[] calldata tokens,
        MultiHopSellSubcall[] calldata calls,
        uint256 sellAmount,
        uint256 minBuyAmount
    ) public override returns (uint256 boughtAmount) {
        return _multiplexMultiHopSell(
            MultiHopSellParams({
                tokens: tokens,
                sellAmount: sellAmount,
                calls: calls,
                useSelfBalance: true,
                recipient: msg.sender
            }),
            minBuyAmount
        );
    }

    function _multiplexMultiHopSell(MultiHopSellParams memory params, uint256 minBuyAmount)
        private
        returns (uint256 boughtAmount)
    {
        require(
            params.tokens.length == params.calls.length + 1,
            "MultiplexFeature::_multiplexMultiHopSell/MISMATCHED_ARRAY_LENGTHS"
        );
        IERC20 outputToken = IERC20(params.tokens[params.tokens.length - 1]);
        uint256 balanceBefore = outputToken.balanceOf(params.recipient);
        MultiHopSellState memory state = _executeMultiHopSell(params);
        uint256 balanceDelta = outputToken.balanceOf(params.recipient) - balanceBefore;
        boughtAmount = Math.min(balanceDelta, state.outputTokenAmount);

        require(boughtAmount >= minBuyAmount, "MultiplexFeature::_multiplexMultiHopSell/UNDERBOUGHT");
    }

    function _nestedBatchSell(MultiHopSellState memory state, MultiHopSellParams memory params, bytes memory data)
        private
    {
        BatchSellParams memory batchSellParams;
        batchSellParams.calls = abi.decode(data, (BatchSellSubcall[]));
        batchSellParams.inputToken = IERC20(params.tokens[state.hopIndex]);
        batchSellParams.outputToken = IERC20(params.tokens[state.hopIndex + 1]);
        // the output token from previous sell is input token for current batch sell
        batchSellParams.sellAmount = state.outputTokenAmount;
        batchSellParams.recipient = state.to;
        batchSellParams.useSelfBalance = state.hopIndex > 0 || params.useSelfBalance;

        state.outputTokenAmount = _executeBatchSell(batchSellParams).boughtAmount;
    }

    function _nestedMultiHopSell(
        BatchSellState memory state,
        BatchSellParams memory params,
        bytes memory data,
        uint256 sellAmount
    ) private {
        MultiHopSellParams memory multiHopSellParams;
        (multiHopSellParams.tokens, multiHopSellParams.calls) = abi.decode(data, (address[], MultiHopSellSubcall[]));
        multiHopSellParams.sellAmount = sellAmount;
        multiHopSellParams.recipient = params.recipient;
        multiHopSellParams.useSelfBalance = params.useSelfBalance;

        uint256 outputTokenAmount = _executeMultiHopSell(multiHopSellParams).outputTokenAmount;
        state.soldAmount = state.soldAmount + sellAmount;
        state.boughtAmount = state.boughtAmount + outputTokenAmount;
    }

    // This function computes the "target" address of hop index `i` within
    // a multi-hop sell.
    // If `i == 0`, the target is the address which should hold the input
    // tokens prior to executing `calls[0]`. Otherwise, it is the address
    // that should receive `tokens[i]` upon executing `calls[i-1]`.
    function computeHopTarget(MultiHopSellParams memory params, uint256 i) private view returns (address target) {
        if (i == params.calls.length) {
            // The last call should send the output tokens to the
            // multi-hop sell recipient.
            target = params.recipient;
        } else {
            if (i == 0) {
                // the input token are held by msg.sender for the first time
                target = msg.sender;
            } else {
                // the intermediate token only held by self
                target = address(this);
            }
        }
    }

    // If `rawAmount` encodes a proportion of `totalSellAmount`, this function
    // converts it to an absolute quantity. Caps the normalized amount to
    // the remaining sell amount (`totalSellAmount - soldAmount`).
    function _normalizeSellAmount(uint256 rawAmount, uint256 totalSellAmount, uint256 soldAmount)
        private
        pure
        returns (uint256 normalized)
    {
        if ((rawAmount & HIGH_BIT) == HIGH_BIT) {
            // If the high bit of `rawAmount` is set then the lower 255 bits
            // specify a fraction of `totalSellAmount`.
            return Math.min(
                (totalSellAmount * Math.min(rawAmount & LOWER_255_BITS, 1e18)) / 1e18, totalSellAmount - soldAmount
            );
        } else {
            return Math.min(rawAmount, totalSellAmount - soldAmount);
        }
    }
}
