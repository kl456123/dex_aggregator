// SPDX-License-Identifier: Apache-2.0
/*
  Copyright 2023 ZeroEx Intl.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

/// @dev Storage helpers for the `TransformERC20` feature.
library LibTransformERC20Storage {
    /// @dev Storage bucket for this feature.
    struct Storage {
        // The transformer deployer address.
        mapping(address => bool) isTransformerRegistered;
        address contractOwner;
    }

    /// events and errors
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TransformerUpdated(address indexed transformer, bool flag);

    error OnlyContractOwner();

    bytes32 internal constant NAMESPACE = keccak256("com.binance.w3w.dexAggregator.transformERC20");

    /// @dev Get the storage bucket for this contract.
    function getStorage() internal pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

    function setContractOwner(address _newOwner) internal {
        Storage storage ds = getStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function enforceIsContractOwner() internal view {
        if (msg.sender != getStorage().contractOwner) {
            revert OnlyContractOwner();
        }
    }

    function isTransformerRegistered(address transformer) internal view returns (bool) {
        return getStorage().isTransformerRegistered[transformer];
    }

    function updateTransformer(address transformer, bool addFlag) internal {
        getStorage().isTransformerRegistered[transformer] = addFlag;
        emit TransformerUpdated(transformer, addFlag);
    }
}
