// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2020 ZeroEx Intl.

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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../LibERC20Token.sol";
import "../../../libs/LibRichErrors.sol";

contract MixinCurveV2 {
    using LibERC20Token for IERC20;
    using LibRichErrors for bytes;

    struct CurveBridgeDataV2 {
        address curveAddress;
        bytes4 exchangeFunctionSelector;
        int128 fromCoinIdx;
        int128 toCoinIdx;
    }

    function _tradeCurveV2(IERC20 sellToken, IERC20 buyToken, uint256 sellAmount, bytes memory bridgeData)
        internal
        returns (uint256 boughtAmount)
    {
        // Decode the bridge data to get the Curve metadata.
        CurveBridgeDataV2 memory data = abi.decode(bridgeData, (CurveBridgeDataV2));
        sellToken.approveIfBelow(data.curveAddress, sellAmount);

        uint256 beforeBalance = buyToken.balanceOf(address(this));
        (bool success, bytes memory resultData) = data.curveAddress.call(
            abi.encodeWithSelector(
                data.exchangeFunctionSelector,
                data.fromCoinIdx,
                data.toCoinIdx,
                // dx
                sellAmount,
                // min dy
                1
            )
        );
        if (!success) {
            resultData.rrevert();
        }

        return buyToken.balanceOf(address(this)) - beforeBalance;
    }
}
