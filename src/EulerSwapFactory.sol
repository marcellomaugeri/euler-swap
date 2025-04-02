// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IEulerSwapFactory, IEulerSwap} from "./interfaces/IEulerSwapFactory.sol";
import {EulerSwap} from "./EulerSwap.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";

/// @title EulerSwapFactory contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract EulerSwapFactory is IEulerSwapFactory, EVCUtil {
    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;
    /// @dev An array to store all pools addresses.
    address[] public allPools;
    /// @dev Mapping between euler account and EulerAccountState
    mapping(address eulerAccount => EulerAccountState state) private eulerAccountState;
    mapping(address asset0 => mapping(address asset1 => address[])) private poolMap;

    event PoolDeployed(
        address indexed asset0,
        address indexed asset1,
        address vault0,
        address vault1,
        uint256 indexed feeMultiplier,
        address eulerAccount,
        uint256 reserve0,
        uint256 reserve1,
        uint256 priceX,
        uint256 priceY,
        uint256 concentrationX,
        uint256 concentrationY,
        address pool
    );
    event PoolUninstalled(address indexed asset0, address indexed asset1, address indexed eulerAccount, address pool);

    error InvalidQuery();
    error Unauthorized();
    error OldOperatorStillInstalled();
    error OperatorNotInstalled();
    error InvalidVaultImplementation();

    constructor(address evc, address evkFactory_) EVCUtil(evc) {
        evkFactory = evkFactory_;
    }

    /// @inheritdoc IEulerSwapFactory
    function deployPool(IEulerSwap.Params memory params, IEulerSwap.CurveParams memory curveParams, bytes32 salt)
        external
        returns (address)
    {
        require(_msgSender() == params.eulerAccount, Unauthorized());
        require(
            GenericFactory(evkFactory).isProxy(params.vault0) && GenericFactory(evkFactory).isProxy(params.vault1),
            InvalidVaultImplementation()
        );

        EulerSwap pool = new EulerSwap{salt: keccak256(abi.encode(params.eulerAccount, salt))}(params, curveParams);

        checkAndUpdateEulerAccountState(params.eulerAccount, address(pool));

        EulerSwap(pool).activate();

        emit PoolDeployed(
            pool.asset0(),
            pool.asset1(),
            params.vault0,
            params.vault1,
            pool.feeMultiplier(),
            params.eulerAccount,
            params.currReserve0,
            params.currReserve1,
            curveParams.priceX,
            curveParams.priceY,
            curveParams.concentrationX,
            curveParams.concentrationY,
            address(pool)
        );

        return address(pool);
    }

    /// @inheritdoc IEulerSwapFactory
    function computePoolAddress(
        IEulerSwap.Params memory poolParams,
        IEulerSwap.CurveParams memory curveParams,
        bytes32 salt
    ) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            keccak256(abi.encode(address(poolParams.eulerAccount), salt)),
                            keccak256(
                                abi.encodePacked(type(EulerSwap).creationCode, abi.encode(poolParams, curveParams))
                            )
                        )
                    )
                )
            )
        );
    }

    function EVC() external view override(EVCUtil, IEulerSwapFactory) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwapFactory
    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function getEulerAccountState(address eulerAccount) external view returns (address, uint48, uint48) {
        return (
            eulerAccountState[eulerAccount].pool,
            eulerAccountState[eulerAccount].allPoolsIndex,
            eulerAccountState[eulerAccount].poolMapIndex
        );
    }

    /// @inheritdoc IEulerSwapFactory
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

    /// @notice Validates operator authorization for euler account and update the relevant EulerAccountState.
    /// @param eulerAccount The address of the euler account.
    /// @param newOperator The address of the new pool.
    function checkAndUpdateEulerAccountState(address eulerAccount, address newOperator) internal {
        require(evc.isAccountOperatorAuthorized(eulerAccount, newOperator), OperatorNotInstalled());

        (address newOpAsset0, address newOpAsset1) = _getAssets(newOperator);
        address oldOperator = eulerAccountState[eulerAccount].pool;

        if (oldOperator != address(0)) {
            require(!evc.isAccountOperatorAuthorized(eulerAccount, oldOperator), OldOperatorStillInstalled());

            // replace pool address in allPools array
            _updateInArray(allPools, eulerAccountState[eulerAccount].allPoolsIndex, newOperator);

            eulerAccountState[eulerAccount].pool = newOperator;

            (address oldOpAsset0, address oldOpAsset1) = _getAssets(oldOperator);

            // if deploying new pool for same assets pair, just update poolMap without pop()
            // else, we need to go the traditional path, reduce the array size, update eulerAccount poolMapIndex and push new one
            if (oldOpAsset0 == newOpAsset0 && oldOpAsset1 == newOpAsset1) {
                _updateInArray(
                    poolMap[newOpAsset0][newOpAsset1], eulerAccountState[eulerAccount].poolMapIndex, newOperator
                );
            } else {
                _removeFromArray(poolMap[oldOpAsset0][oldOpAsset1], eulerAccountState[eulerAccount].poolMapIndex);

                eulerAccountState[eulerAccount].poolMapIndex = uint48(poolMap[newOpAsset0][newOpAsset1].length);

                _pushInArray(poolMap[newOpAsset0][newOpAsset1], newOperator);
            }

            emit PoolUninstalled(oldOpAsset0, oldOpAsset1, eulerAccount, oldOperator);
        } else {
            address[] storage poolMapArray = poolMap[newOpAsset0][newOpAsset1];

            eulerAccountState[eulerAccount] = EulerAccountState({
                pool: newOperator,
                allPoolsIndex: uint48(allPools.length),
                poolMapIndex: uint48(poolMapArray.length)
            });

            _pushInArray(allPools, newOperator);
            _pushInArray(poolMapArray, newOperator);
        }
    }

    function _updateInArray(address[] storage arr, uint256 index, address _newValue) internal {
        arr[index] = _newValue;
    }

    function _pushInArray(address[] storage arr, address _newValue) internal {
        arr.push(_newValue);
    }

    function _removeFromArray(address[] storage arr, uint256 index) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function _getAssets(address pool) internal view returns (address, address) {
        return (EulerSwap(pool).asset0(), EulerSwap(pool).asset1());
    }
}
