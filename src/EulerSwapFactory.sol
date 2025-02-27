// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEulerSwapFactory} from "./interfaces/IEulerSwapFactory.sol";
import {IEulerSwap, EulerSwap} from "./EulerSwap.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil {
    /// @dev An array to store all pools addresses.
    address[] public allPools;
    /// @dev Mapping between a swap account and deployed pool that is currently set as operator
    mapping(address swapAccount => address operator) public swapAccountToPool;

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address vault0,
        address vault1,
        uint256 indexed feeMultiplier,
        address swapAccount,
        uint256 priceX,
        uint256 priceY,
        uint256 concentrationX,
        uint256 concentrationY,
        address pool
    );

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();

    constructor(address evc) EVCUtil(evc) {}

    /// @notice Deploy EulerSwap pool.
    function deployPool(DeployParams memory params, bytes32 salt) external returns (address) {
        require(_msgSender() == params.swapAccount, Unauthorized());

        EulerSwap pool = new EulerSwap{salt: keccak256(abi.encode(params.swapAccount, salt))}(
            IEulerSwap.Params({
                vault0: params.vault0,
                vault1: params.vault1,
                myAccount: params.swapAccount,
                debtLimit0: params.debtLimit0,
                debtLimit1: params.debtLimit1,
                fee: params.fee
            }),
            IEulerSwap.CurveParams({
                priceX: params.priceX,
                priceY: params.priceY,
                concentrationX: params.concentrationX,
                concentrationY: params.concentrationY
            })
        );

        checkSwapAccountOperators(params.swapAccount, address(pool));

        EulerSwap(pool).activate();

        allPools.push(address(pool));

        emit PoolDeployed(
            pool.asset0(),
            pool.asset1(),
            params.vault0,
            params.vault1,
            pool.feeMultiplier(),
            params.swapAccount,
            params.priceX,
            params.priceY,
            params.concentrationX,
            params.concentrationY,
            address(pool)
        );

        return address(pool);
    }

    /// @notice Get the length of `allPools` array.
    /// @return `allPools` length.
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Get a slice of the deployed pools array.
    /// @param _start Start index of the slice.
    /// @param _end End index of the slice.
    /// @return An array containing the slice of the deployed pools.
    function getAllPoolsListSlice(uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = allPools.length;
        if (_end == type(uint256).max) _end = length;
        if (_end < _start || _end > length) revert InvalidQuery();

        address[] memory allPoolsList = new address[](_end - _start);
        for (uint256 i; i < _end - _start; ++i) {
            allPoolsList[i] = allPools[_start + i];
        }

        return allPoolsList;
    }

    function checkSwapAccountOperators(address swapAccount, address newPool) internal {
        address operator = swapAccountToPool[swapAccount];

        if (operator != address(0)) {
            require(!evc.isAccountOperatorAuthorized(swapAccount, operator), OldOperatorStillInstalled());
        }

        require(evc.isAccountOperatorAuthorized(swapAccount, newPool), OperatorNotInstalled());

        swapAccountToPool[swapAccount] = newPool;
    }
}
