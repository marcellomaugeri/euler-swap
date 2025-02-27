// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IERC20, SafeERC20, EulerSwap} from "../src/EulerSwap.sol";
import {SwapUtil} from "./util/SwapUtil.sol";

contract SwapExactIn is ScriptUtil {
    using SafeERC20 for IERC20;

    function run() public {
        // load wallet
        uint256 swapperKey = vm.envUint("WALLET_PRIVATE_KEY");
        address swapperAddress = vm.rememberKey(swapperKey);

        // load JSON file
        string memory inputScriptFileName = "SwapExactIn_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        SwapUtil swapUtil = SwapUtil(vm.parseJsonAddress(json, ".swapUtil"));   // Do not change address of this one unless u manually deploy new one
        EulerSwap pool = EulerSwap(vm.parseJsonAddress(json, ".pool"));
        address tokenIn = vm.parseJsonAddress(json, ".tokenIn");
        address tokenOut = vm.parseJsonAddress(json, ".tokenOut");
        uint256 amountIn = vm.parseJsonUint(json, ".amountIn");

        vm.startBroadcast(swapperAddress);

        IERC20(tokenIn).forceApprove(address(swapUtil), amountIn);

        swapUtil.executeSwap(address(pool), tokenIn, tokenOut, amountIn, true);

        vm.stopBroadcast();
    }
}
