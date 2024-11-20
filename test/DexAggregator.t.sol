// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

import {ITransformERC20Feature} from "contracts/interfaces/ITransformERC20Feature.sol";
import {IMultiplexFeature} from "contracts/interfaces/IMultiplexFeature.sol";
import {FillQuoteTransformer} from "contracts/transformers/FillQuoteTransformer.sol";
import {IBridgeAdapter} from "contracts/transformers/bridges/IBridgeAdapter.sol";
import {MixinUniswapV2, IUniswapV2Router02} from "contracts/transformers/bridges/mixins/MixinUniswapV2.sol";
import {MixinUniswapV3, IUniswapV3Router} from "contracts/transformers/bridges/mixins/MixinUniswapV3.sol";

import {DexAggregatorProxy} from "contracts/test/DexAggregatorProxy.sol";

// deployer
import {DexAggregatorFacetDeployer} from "../script/DexAggregatorDeployer.sol";

contract DexAggregatorFacetTest is Test, DexAggregatorFacetDeployer {
    address owner = address(0x666);
    address user = address(0x666);

    string defauleVal = "https://eth-mainnet.g.alchemy.com/v2/JvMibmM4thQEF_7m7UXF02YSqUW5-pRX";
    address fillQuoteTransformer;
    address bridgeAdapter;
    address dexAggregator;
    DexAggregatorProxy dexAggregatorProxy;
    address internal constant ADDRESS_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant ADDRESS_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant ADDRESS_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant ADDRESS_UNIV2_ROUTER = 0xf164fC0Ec4E93095b804a4795bBe1e041497b92a;
    address internal constant ADDRESS_UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint256 internal constant UNISWAPV2_ID = 2;
    uint256 internal constant UNISWAPV3_ID = 10;
    uint256 private constant HIGH_BIT = 2 ** 255;
    uint256 private constant LOWER_255_BITS = HIGH_BIT - 1;

    function setUp() public {
        uint256 blockNumber = 20487910;
        vm.createSelectFork(vm.envOr("BN_T_RPC", defauleVal), blockNumber);
        (address _bridgeAdapter, address _fillQuoteTransformer, address _dexAggregator) =
            deployDexAggregatorFacetAndFuncSigList(owner, block.chainid);
        bridgeAdapter = _bridgeAdapter;
        fillQuoteTransformer = _fillQuoteTransformer;
        dexAggregator = _dexAggregator;

        dexAggregatorProxy = new DexAggregatorProxy(dexAggregator);

        // prepare tokens for user
        vm.deal(user, 1000 ether); // 1000 eth
        deal(ADDRESS_USDC, user, 100_000 * 10 ** 6); // 100000 usdc
        deal(ADDRESS_USDT, user, 100_000 * 10 ** 6); // 100000 usdt
        deal(ADDRESS_WETH, user, 100_000 * 10 ** 18); // 100000 weth
    }

    function createBridgeData(uint256 protocolId, address inputToken, address outputToken, uint24 fee)
        internal
        pure
        returns (bytes memory bridgeData)
    {
        if (protocolId == UNISWAPV2_ID) {
            // uniswapv2
            IUniswapV2Router02 router = IUniswapV2Router02(ADDRESS_UNIV2_ROUTER);
            IERC20[] memory path = new IERC20[](2);
            path[0] = IERC20(inputToken);
            path[1] = IERC20(outputToken);
            bridgeData = abi.encode(MixinUniswapV2.QuoteFromUniswapV2Params({router: router, path: path}));
        } else if (protocolId == UNISWAPV3_ID) {
            // uniswapv3
            IUniswapV3Router router = IUniswapV3Router(ADDRESS_UNIV3_ROUTER);
            IERC20[] memory path = new IERC20[](2);
            path[0] = IERC20(inputToken);
            path[1] = IERC20(outputToken);
            uint24[] memory fees = new uint24[](1);
            fees[0] = fee;
            bridgeData = abi.encode(MixinUniswapV3.QuoteFromUniswapV3Params({router: router, path: path, fees: fees}));
        }
    }

    function createTransformer(uint256 protocolId, IERC20 inputToken, IERC20 outputToken, uint24 fee)
        internal
        view
        returns (ITransformERC20Feature.Transformation memory transformation)
    {
        bytes memory bridgeData = createBridgeData(protocolId, address(inputToken), address(outputToken), fee);
        uint256 takerTokenAmount = type(uint256).max;
        uint256 makerTokenAmount = 0;
        IBridgeAdapter.BridgeOrder memory bridgeOrder = IBridgeAdapter.BridgeOrder({
            source: bytes32(protocolId << 128),
            takerTokenAmount: takerTokenAmount,
            makerTokenAmount: makerTokenAmount,
            bridgeData: bridgeData
        });

        FillQuoteTransformer.TransformData memory transformData = FillQuoteTransformer.TransformData({
            side: FillQuoteTransformer.Side.Sell,
            sellToken: inputToken,
            buyToken: outputToken,
            bridgeOrder: bridgeOrder,
            fillAmount: type(uint256).max
        });
        transformation =
            ITransformERC20Feature.Transformation({transformer: fillQuoteTransformer, data: abi.encode(transformData)});
    }

    function callTransformERC20ByAggregatorProxy(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        ITransformERC20Feature.Transformation[] memory transformations
    ) public {
        uint256 fromTokenWithFee = uint256(uint160(address(inputToken))) + HIGH_BIT;
        uint256 toTokenWithFee = uint256(uint160(address(outputToken)));
        bytes memory callData = abi.encodeWithSelector(
            ITransformERC20Feature.transformERC20.selector,
            inputToken,
            outputToken,
            inputTokenAmount,
            minOutputTokenAmount,
            transformations
        );
        dexAggregatorProxy.callDexAggregator(fromTokenWithFee, inputTokenAmount, toTokenWithFee, callData);
    }

    function callMultiplexMultiHopSellTokenForTokenByAggregatorProxy(
        address[] memory tokens,
        IMultiplexFeature.MultiHopSellSubcall[] memory multiHopSubcalls,
        uint256 fromAmt,
        uint256 minOutputTokenAmount
    ) public {
        uint256 fromTokenWithFee = uint256(uint160(tokens[0])) + HIGH_BIT;
        uint256 toTokenWithFee = uint256(uint160(tokens[tokens.length - 1]));
        bytes memory callData = abi.encodeWithSelector(
            IMultiplexFeature.multiplexMultiHopSellTokenForToken.selector,
            tokens,
            multiHopSubcalls,
            fromAmt,
            minOutputTokenAmount
        );
        dexAggregatorProxy.callDexAggregator(fromTokenWithFee, fromAmt, toTokenWithFee, callData);
    }

    function callMultiplexBatchSellTokenForTokenByAggregatorProxy(
        IERC20 inputToken,
        IERC20 outputToken,
        IMultiplexFeature.BatchSellSubcall[] memory batchSubCalls,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) public {
        uint256 fromTokenWithFee = uint256(uint160(address(inputToken))) + HIGH_BIT;
        uint256 toTokenWithFee = uint256(uint160(address(outputToken)));
        bytes memory callData = abi.encodeWithSelector(
            IMultiplexFeature.multiplexBatchSellTokenForToken.selector,
            inputToken,
            outputToken,
            batchSubCalls,
            inputTokenAmount,
            minOutputTokenAmount
        );
        dexAggregatorProxy.callDexAggregator(fromTokenWithFee, inputTokenAmount, toTokenWithFee, callData);
    }

    function test_SwapTokenForToken() public {
        IERC20 inputToken = IERC20(ADDRESS_WETH);
        IERC20 outputToken = IERC20(ADDRESS_USDC);
        uint256 inputTokenAmount = 1 * 10 ** 18; // 1 weth
        uint256 minOutputTokenAmount = 0;
        ITransformERC20Feature.Transformation[] memory transformations = new ITransformERC20Feature.Transformation[](1);

        uint256[] memory protocolIds = new uint256[](2);
        protocolIds[0] = UNISWAPV2_ID;
        protocolIds[1] = UNISWAPV3_ID;

        for (uint256 i = 0; i < protocolIds.length; ++i) {
            transformations[0] = createTransformer(protocolIds[i], inputToken, outputToken, 3000);

            vm.startPrank(user);
            inputToken.approve(address(dexAggregatorProxy), type(uint256).max);
            uint256 inputTokenBalanceBefore = inputToken.balanceOf(user);
            uint256 outputTokenBalanceBefore = outputToken.balanceOf(user);
            callTransformERC20ByAggregatorProxy(
                inputToken, outputToken, inputTokenAmount, minOutputTokenAmount, transformations
            );

            uint256 inputTokenBalanceAfter = inputToken.balanceOf(user);
            uint256 outputTokenBalanceAfter = outputToken.balanceOf(user);

            assertEq(inputTokenBalanceBefore - inputTokenBalanceAfter, inputTokenAmount);
            assertGt(outputTokenBalanceAfter - outputTokenBalanceBefore, minOutputTokenAmount);

            // no any tokens remain
            assertEq(inputToken.balanceOf(dexAggregator), 0);
            assertEq(outputToken.balanceOf(dexAggregator), 0);

            vm.stopPrank();
        }
    }

    function test_SwapTokenForTokenByMultiHops() public {
        IERC20 inputToken = IERC20(ADDRESS_WETH);
        IERC20 middleToken = IERC20(ADDRESS_USDT);
        IERC20 outputToken = IERC20(ADDRESS_USDC);
        uint256 inputTokenAmount = 1000 * 10 ** 18; // 1000 usdt
        uint256 minOutputTokenAmount = 0;

        uint256 numHops = 2;
        IMultiplexFeature.MultiHopSellSubcall[] memory multiHopSubcalls =
            new IMultiplexFeature.MultiHopSellSubcall[](numHops);
        {
            ITransformERC20Feature.Transformation[] memory transformations =
                new ITransformERC20Feature.Transformation[](1);
            transformations[0] = createTransformer(UNISWAPV2_ID, inputToken, middleToken, 0);

            IMultiplexFeature.BatchSellSubcall[] memory batchSubCalls = new IMultiplexFeature.BatchSellSubcall[](1);
            uint256 rate = 100; // 100%
            uint256 sellAmount = (rate * 1e18) & LOWER_255_BITS + HIGH_BIT;
            batchSubCalls[0] = IMultiplexFeature.BatchSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.TransformERC20,
                sellAmount: sellAmount,
                data: abi.encode(transformations)
            });
            multiHopSubcalls[0] = IMultiplexFeature.MultiHopSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.BatchSell,
                data: abi.encode(batchSubCalls)
            });
        }

        {
            ITransformERC20Feature.Transformation[] memory transformations =
                new ITransformERC20Feature.Transformation[](1);
            transformations[0] = createTransformer(UNISWAPV2_ID, middleToken, outputToken, 0);

            IMultiplexFeature.BatchSellSubcall[] memory batchSubCalls = new IMultiplexFeature.BatchSellSubcall[](1);
            uint256 rate = 100; // 100%
            uint256 sellAmount = (rate * 1e18) & LOWER_255_BITS + HIGH_BIT;
            batchSubCalls[0] = IMultiplexFeature.BatchSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.TransformERC20,
                sellAmount: sellAmount,
                data: abi.encode(transformations)
            });
            multiHopSubcalls[1] = IMultiplexFeature.MultiHopSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.BatchSell,
                data: abi.encode(batchSubCalls)
            });
        }
        address[] memory tokens = new address[](numHops + 1);
        tokens[0] = address(inputToken);
        tokens[1] = address(middleToken);
        tokens[2] = address(outputToken);

        vm.startPrank(user);
        inputToken.approve(address(dexAggregatorProxy), type(uint256).max);
        uint256 inputTokenBalanceBefore = inputToken.balanceOf(user);
        uint256 outputTokenBalanceBefore = outputToken.balanceOf(user);
        callMultiplexMultiHopSellTokenForTokenByAggregatorProxy(
            tokens, multiHopSubcalls, inputTokenAmount, minOutputTokenAmount
        );

        uint256 inputTokenBalanceAfter = inputToken.balanceOf(user);
        uint256 outputTokenBalanceAfter = outputToken.balanceOf(user);

        assertEq(inputTokenBalanceBefore - inputTokenBalanceAfter, inputTokenAmount);
        assertGt(outputTokenBalanceAfter - outputTokenBalanceBefore, minOutputTokenAmount);

        // no any tokens remain
        assertEq(inputToken.balanceOf(dexAggregator), 0);
        assertEq(outputToken.balanceOf(dexAggregator), 0);
        vm.stopPrank();
    }

    function test_SwapTokenForTokenByBatch() public {
        IERC20 inputToken = IERC20(ADDRESS_WETH);
        IERC20 outputToken = IERC20(ADDRESS_USDC);
        uint256 inputTokenAmount = 1000 * 10 ** 18; // 1000 usdt
        uint256 minOutputTokenAmount = 0;

        IMultiplexFeature.BatchSellSubcall[] memory batchSubCalls = new IMultiplexFeature.BatchSellSubcall[](2);
        {
            ITransformERC20Feature.Transformation[] memory transformations =
                new ITransformERC20Feature.Transformation[](1);
            transformations[0] = createTransformer(UNISWAPV2_ID, inputToken, outputToken, 3000);

            uint256 rate = 50; // 100%
            uint256 sellAmount = (rate * 1e18) & LOWER_255_BITS + HIGH_BIT;
            batchSubCalls[0] = IMultiplexFeature.BatchSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.TransformERC20,
                sellAmount: sellAmount,
                data: abi.encode(transformations)
            });
        }

        {
            ITransformERC20Feature.Transformation[] memory transformations =
                new ITransformERC20Feature.Transformation[](1);
            transformations[0] = createTransformer(UNISWAPV3_ID, inputToken, outputToken, 3000);

            uint256 rate = 50; // 100%
            uint256 sellAmount = (rate * 1e18) & LOWER_255_BITS + HIGH_BIT;
            batchSubCalls[1] = IMultiplexFeature.BatchSellSubcall({
                id: IMultiplexFeature.MultiplexSubcall.TransformERC20,
                sellAmount: sellAmount,
                data: abi.encode(transformations)
            });
        }

        vm.startPrank(user);
        inputToken.approve(address(dexAggregatorProxy), type(uint256).max);
        uint256 inputTokenBalanceBefore = inputToken.balanceOf(user);
        uint256 outputTokenBalanceBefore = outputToken.balanceOf(user);
        callMultiplexBatchSellTokenForTokenByAggregatorProxy(
            inputToken, outputToken, batchSubCalls, inputTokenAmount, minOutputTokenAmount
        );

        uint256 inputTokenBalanceAfter = inputToken.balanceOf(user);
        uint256 outputTokenBalanceAfter = outputToken.balanceOf(user);

        assertEq(inputTokenBalanceBefore - inputTokenBalanceAfter, inputTokenAmount);
        assertGt(outputTokenBalanceAfter - outputTokenBalanceBefore, minOutputTokenAmount);

        // no any tokens remain
        assertEq(inputToken.balanceOf(dexAggregator), 0);
        assertEq(outputToken.balanceOf(dexAggregator), 0);
        vm.stopPrank();
    }

    // NOTE(with multi hops nested in batch route path)
    function test_SwapTokenForTokenByComplexPath() public {}

    function test_SwapETHForToken() public {}

    function test_SwapTokenForETH() public {}
}
