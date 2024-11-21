// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library LibTransformERC20RichErrors {
    function InsufficientEthAttachedError(uint256 ethAttached, uint256 ethNeeded)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(keccak256("InsufficientEthAttachedError(uint256,uint256)")), ethAttached, ethNeeded
        );
    }

    function TransformerFailedError(address transformer, bytes memory transformerData, bytes memory resultData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(keccak256("TransformerFailedError(address,bytes,bytes)")), transformer, transformerData, resultData
        );
    }

    enum InvalidTransformDataErrorCode {
        INVALID_TOKENS,
        INVALID_ARRAY_LENGTH
    }

    function InvalidTransformDataError(InvalidTransformDataErrorCode errorCode, bytes memory transformData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(keccak256("InvalidTransformDataError(uint8,bytes)")), errorCode, transformData
        );
    }

    function IncompleteTransformERC20Error(address outputToken, uint256 outputTokenAmount, uint256 minOutputTokenAmount)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            bytes4(keccak256("IncompleteTransformERC20Error(address,uint256,uint256)")),
            outputToken,
            outputTokenAmount,
            minOutputTokenAmount
        );
    }

    function UnregisteredTransformerError(address transformer) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(keccak256("UnregisteredTransformerError(address)")), transformer);
    }
}
