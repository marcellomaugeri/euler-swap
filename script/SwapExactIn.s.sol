// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IERC20, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapPeriphery} from "../src/EulerSwapPeriphery.sol";

import "forge-std/console2.sol";

contract SwapExactIn is ScriptUtil {
    function run() public {
        // load wallet
        uint256 swapperKey = vm.envUint("WALLET_PRIVATE_KEY");
        address swapperAddress = vm.rememberKey(swapperKey);

        // load JSON file
        string memory inputScriptFileName = "SwapExactIn_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwap pool = EulerSwap(vm.parseJsonAddress(json, ".pool"));
        EulerSwapPeriphery periphery = EulerSwapPeriphery(vm.parseJsonAddress(json, ".periphery"));

        address tokenIn = vm.parseJsonAddress(json, ".tokenIn");
        address tokenOut = vm.parseJsonAddress(json, ".tokenOut");
        uint256 amountIn = vm.parseJsonUint(json, ".amountIn");
        bool isAsset0In = tokenIn < tokenOut;

        uint256 expectedAmountOut = periphery.quoteExactInput(address(pool), tokenIn, tokenOut, amountIn);
        uint256 swapperBalanceBefore = IERC20(tokenOut).balanceOf(swapperAddress);

        vm.startBroadcast(swapperAddress);

        IERC20(tokenIn).transfer(address(pool), amountIn);

        (isAsset0In) ? pool.swap(0, expectedAmountOut, swapperAddress, "") : pool.swap(expectedAmountOut, 0, swapperAddress, "");

        require(IERC20(tokenOut).balanceOf(swapperAddress) > swapperBalanceBefore, "noo");

        vm.stopBroadcast();
    }
}
