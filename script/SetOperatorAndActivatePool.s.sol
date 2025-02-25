// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {EulerSwap, IEVC} from "../src/EulerSwap.sol";

import "forge-std/console2.sol";

/// @title Script to deploy new pool.
contract SetOperatorAndActivatePool is ScriptUtil {
    function run() public {
        // load wallet
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        // load JSON file
        string memory inputScriptFileName = "SetOperatorAndActivatePool_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwap pool = EulerSwap(vm.parseJsonAddress(json, ".pool"));
        IEVC evc = IEVC(pool.EVC());

        vm.startBroadcast(deployerAddress);

        evc.setAccountOperator(deployerAddress, address(pool), true);

        pool.activate();

        vm.stopBroadcast();
    }
}
