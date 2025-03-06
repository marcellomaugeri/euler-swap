// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {EulerSwap, IEulerSwap, IEVault} from "./EulerSwap.sol";

contract EulerSwapHook is EulerSwap, BaseHook {
    PoolKey poolKey;

    constructor(IPoolManager _manager, Params memory params, CurveParams memory curveParams)
        EulerSwap(params, curveParams)
        BaseHook(_manager)
    {
        address asset0Addr = IEVault(params.vault0).asset();
        address asset1Addr = IEVault(params.vault1).asset();

        // convert fee in WAD to pips. 0.003e18 / 1e12 = 3000 = 0.30%
        uint24 fee = uint24(params.fee / 1e12);

        poolKey = PoolKey({
            currency0: Currency.wrap(asset0Addr),
            currency1: Currency.wrap(asset1Addr),
            fee: fee,
            tickSpacing: 60, // TODO: fix arbitrary tick spacing
            hooks: IHooks(address(this))
        });

        // create the pool on v4, using starting price as sqrtPrice(1/1) * Q96
        poolManager.initialize(poolKey, 79228162514264337593543950336);
    }

    // TODO: fix salt mining & verification for the hook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {}
    function validateHookAddress(BaseHook) internal pure override {}
}
