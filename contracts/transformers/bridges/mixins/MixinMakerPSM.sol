// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2021 ZeroEx Intl.

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
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../LibERC20Token.sol";

interface IPSM {
    // @dev Get the fee for selling USDC to DAI in PSM
    // @return tin toll in [wad]
    function tin() external view returns (uint256);

    // @dev Get the fee for selling DAI to USDC in PSM
    // @return tout toll out [wad]
    function tout() external view returns (uint256);

    // @dev Get the address of the PSM state Vat
    // @return address of the Vat
    function vat() external view returns (address);

    // @dev Get the address of the underlying vault powering PSM
    // @return address of gemJoin contract
    function gemJoin() external view returns (address);

    // @dev Sell USDC for DAI
    // @param usr The address of the account trading USDC for DAI.
    // @param gemAmt The amount of USDC to sell in USDC base units
    function sellGem(address usr, uint256 gemAmt) external;

    // @dev Buy USDC for DAI
    // @param usr The address of the account trading DAI for USDC
    // @param gemAmt The amount of USDC to buy in USDC base units
    function buyGem(address usr, uint256 gemAmt) external;
}

contract MixinMakerPSM {
    using LibERC20Token for IERC20;

    struct MakerPsmBridgeData {
        address psmAddress;
        address gemTokenAddres;
    }

    // Maker units
    // wad: fixed point decimal with 18 decimals (for basic quantities, e.g. balances)
    uint256 private constant WAD = 10 ** 18;
    // ray: fixed point decimal with 27 decimals (for precise quantites, e.g. ratios)
    uint256 private constant RAY = 10 ** 27;
    // rad: fixed point decimal with 45 decimals (result of integer multiplication with a wad and a ray)
    uint256 private constant RAD = 10 ** 45;

    // See https://github.com/makerdao/dss/blob/master/DEVELOPING.md

    function _tradeMakerPsm(IERC20 sellToken, IERC20 buyToken, uint256 sellAmount, bytes memory bridgeData)
        internal
        returns (uint256 boughtAmount)
    {
        // Decode the bridge data.
        MakerPsmBridgeData memory data = abi.decode(bridgeData, (MakerPsmBridgeData));
        uint256 beforeBalance = buyToken.balanceOf(address(this));

        IPSM psm = IPSM(data.psmAddress);

        if (address(sellToken) == data.gemTokenAddres) {
            sellToken.approveIfBelow(psm.gemJoin(), sellAmount);

            psm.sellGem(address(this), sellAmount);
        } else if (address(buyToken) == data.gemTokenAddres) {
            uint256 feeDivisor = WAD + psm.tout(); // eg. 1.001 * 10 ** 18 with 0.1% fee [tout is in wad];
            uint256 buyTokenBaseUnit = uint256(10) ** uint256(ERC20(address(buyToken)).decimals());
            uint256 gemAmount = sellAmount * buyTokenBaseUnit / feeDivisor;

            sellToken.approveIfBelow(data.psmAddress, sellAmount);
            psm.buyGem(address(this), gemAmount);
        }

        return buyToken.balanceOf(address(this)) - beforeBalance;
    }
}
