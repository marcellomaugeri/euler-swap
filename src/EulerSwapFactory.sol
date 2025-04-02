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
    /// @dev An array to store all pools addresses.
    address[] private allPools;
    /// @dev Vaults must be deployed by this factory
    address public immutable evkFactory;
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
    error SliceOutOfBounds();

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

    /// @inheritdoc IEulerSwapFactory
    function EVC() external view override(EVCUtil, IEulerSwapFactory) returns (address) {
        return address(evc);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolByHolder(address who) external view returns (address) {
        return eulerAccountState[who].pool;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsSlice(uint256 start, uint256 end) external view returns (address[] memory) {
        return _getSlice(allPools, start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function pools() external view returns (address[] memory) {
        return _getSlice(allPools, 0, type(uint256).max);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairLength(address asset0, address asset1) external view returns (uint256) {
        return poolMap[asset0][asset1].length;
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPairSlice(address asset0, address asset1, uint256 start, uint256 end)
        external
        view
        returns (address[] memory)
    {
        return _getSlice(poolMap[asset0][asset1], start, end);
    }

    /// @inheritdoc IEulerSwapFactory
    function poolsByPair(address asset0, address asset1) external view returns (address[] memory) {
        return _getSlice(poolMap[asset0][asset1], 0, type(uint256).max);
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

    /// @notice Updates an element at a specific index in an array
    /// @dev Directly modifies the array element at the given index with a new value
    /// @param arr The storage array to update
    /// @param index The index of the element to update
    /// @param _newValue The new value to set at the specified index
    function _updateInArray(address[] storage arr, uint256 index, address _newValue) internal {
        arr[index] = _newValue;
    }

    /// @notice Adds a new element to the end of an array
    /// @dev Uses the push operation to append a new value to the array
    /// @param arr The storage array to append to
    /// @param _newValue The new value to append to the array
    function _pushInArray(address[] storage arr, address _newValue) internal {
        arr.push(_newValue);
    }

    /// @notice Removes an element from an array at a specific index
    /// @dev Uses the swap-and-pop pattern to remove an element while maintaining array order
    /// @param arr The storage array to remove from
    /// @param index The index of the element to remove
    function _removeFromArray(address[] storage arr, uint256 index) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    /// @notice Retrieves the asset addresses for a given pool
    /// @dev Calls the pool contract to get its asset0 and asset1 addresses
    /// @param pool The address of the pool to query
    /// @return The addresses of asset0 and asset1 in the pool
    function _getAssets(address pool) internal view returns (address, address) {
        return (EulerSwap(pool).asset0(), EulerSwap(pool).asset1());
    }

    /// @notice Returns a slice of an array of addresses
    /// @dev Creates a new memory array containing elements from start to end index
    ///      If end is type(uint256).max, it will return all elements from start to the end of the array
    /// @param arr The storage array to slice
    /// @param start The starting index of the slice (inclusive)
    /// @param end The ending index of the slice (exclusive)
    /// @return A new memory array containing the requested slice of addresses
    function _getSlice(address[] storage arr, uint256 start, uint256 end) internal view returns (address[] memory) {
        uint256 length = arr.length;
        if (end == type(uint256).max) end = length;
        if (end < start || end > length) revert SliceOutOfBounds();

        address[] memory slice = new address[](end - start);
        for (uint256 i; i < end - start; ++i) {
            slice[i] = arr[start + i];
        }

        return slice;
    }
}
