// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITransformERC20Feature {
    struct Transformation {
        address transformer;
        bytes data;
    }

    struct TransformERC20Args {
        IERC20 inputToken;
        IERC20 outputToken;
        uint256 inputTokenAmount;
        uint256 minOutputTokenAmount;
        bool useSelfBalance;
        Transformation[] transformations;
        address payable recipient;
        address payable taker;
    }

    /// @dev Raised upon a successful `transformERC20`.
    /// @param taker The taker (caller) address.
    /// @param inputToken The token being provided by the taker.
    ///        If `0xeee...`, ETH is implied and should be provided with the call.`
    /// @param outputToken The token to be acquired by the taker.
    ///        `0xeee...` implies ETH.
    /// @param inputTokenAmount The amount of `inputToken` to take from the taker.
    /// @param outputTokenAmount The amount of `outputToken` received by the taker.
    event TransformedERC20(
        address indexed taker,
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 outputTokenAmount
    );

    /// @dev Raised when `updateTransformer()` is called.
    /// @param transformer The new transformer address.
    /// @param addFlag be true if add, otherwise be false
    event TransformerUpdated(address transformer, bool addFlag);

    /// @dev Executes a series of transformations to convert an ERC20 `inputToken`
    ///      to an ERC20 `outputToken`.
    /// @param inputToken The token being provided by the sender.
    ///        If `0xeee...`, ETH is implied and should be provided with the call.`
    /// @param outputToken The token to be acquired by the sender.
    ///        `0xeee...` implies ETH.
    /// @param inputTokenAmount The amount of `inputToken` to take from the sender.
    /// @param minOutputTokenAmount The minimum amount of `outputToken` the sender
    ///        must receive for the entire transformation to succeed.
    /// @param transformations The transformations to execute on the token balance(s)
    ///        in sequence.
    /// @return outputTokenAmount The amount of `outputToken` received by the sender.
    function transformERC20(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        Transformation[] memory transformations
    ) external payable returns (uint256 outputTokenAmount);

    function _transformERC20(TransformERC20Args memory args) external payable returns (uint256 outputTokenAmount);

    /// @dev Update transformer, maybe add a new transformer or delete a existed one.
    /// @param transformer The new transformer address.
    /// @param addFlag be true if add, otherwise be false
    function updateTransformer(address transformer, bool addFlag) external;
}
