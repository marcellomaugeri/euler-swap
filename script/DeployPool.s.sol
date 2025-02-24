// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ScriptUtil} from "./ScriptUtil.s.sol";
import {IEulerSwapFactory, EulerSwapFactory} from "../src/EulerSwapFactory.sol";

/// @title Script to deploy EulerSwapFactory & EulerSwapPeriphery.
contract DeployPool is ScriptUtil {
    function run() public {
        // load wallet
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        // load JSON file
        string memory inputScriptFileName = "DeployPool_input.json";
        string memory json = _getJsonFile(inputScriptFileName);

        EulerSwapFactory factory = EulerSwapFactory(vm.parseJsonAddress(json, ".factory"));
        IEulerSwapFactory.DeployParams memory params = IEulerSwapFactory.DeployParams({
            vault0: vm.parseJsonAddress(json, ".vault0"),
            vault1: vm.parseJsonAddress(json, ".vault1"),
            swapAccount: vm.parseJsonAddress(json, ".swapAccount"),
            fee: vm.parseJsonUint(json, ".fee"),
            priceX: vm.parseJsonUint(json, ".priceX"),
            priceY: vm.parseJsonUint(json, ".priceY"),
            concentrationX: vm.parseJsonUint(json, ".concentrationX"),
            concentrationY: vm.parseJsonUint(json, ".concentrationY"),
            debtLimit0: uint112(vm.parseJsonUint(json, ".debtLimit0")),
            debtLimit1: uint112(vm.parseJsonUint(json, ".debtLimit1"))
        });

        vm.startBroadcast(deployerAddress);

        address pool = factory.deployPool(params);

        string memory outputScriptFileName = "DeployPool_output.json";

        string memory object;
        object = vm.serializeAddress("factory", "deployedPool", pool);

        vm.writeJson(object, string.concat(vm.projectRoot(), "/script/", outputScriptFileName));

        vm.stopBroadcast();
    }
}
