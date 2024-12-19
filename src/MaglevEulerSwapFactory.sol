// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {MaglevEulerSwap as Maglev, MaglevBase} from "./MaglevEulerSwap.sol";

/// @title MaglevEulerSwapRegistry contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
contract MaglevEulerSwapFactory is Ownable {
    event PoolDeployed(address indexed asset0, address indexed asset1, uint256 indexed feeMultiplier, address pool);

    error InvalidQuery();
    error PoolAlreadyDeployed();

    /// @dev EVC address.
    address public immutable evc;
    /// @dev An array to store all pools addresses.
    address[] public allPools;
    /// @dev Mapping from asset0/asset1/fee => pool address.
    mapping(address => mapping(address => mapping(uint256 => address))) public getPool;

    constructor(address evcAddr) Ownable(msg.sender) {
        evc = evcAddr;
    }

    /// @notice Deploy EulerSwap pool.
    function deployPool(
        address vault0,
        address vault1,
        address holder,
        uint112 debtLimit0,
        uint112 debtLimit1,
        uint256 fee,
        uint256 priceX,
        uint256 priceY,
        uint256 concentrationX,
        uint256 concentrationY
    ) external onlyOwner returns (address) {
        Maglev pool = new Maglev(
            MaglevBase.BaseParams({
                evc: address(evc),
                vault0: vault0,
                vault1: vault1,
                myAccount: holder,
                debtLimit0: debtLimit0,
                debtLimit1: debtLimit1,
                fee: fee
            }),
            Maglev.EulerSwapParams({
                priceX: priceX,
                priceY: priceY,
                concentrationX: concentrationX,
                concentrationY: concentrationY
            })
        );

        address poolAsset0 = pool.asset0();
        address poolAsset1 = pool.asset1();
        uint256 feeMultiplier = pool.feeMultiplier();

        require(getPool[poolAsset0][poolAsset1][feeMultiplier] == address(0), PoolAlreadyDeployed());

        getPool[poolAsset0][poolAsset1][feeMultiplier] = address(pool);
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[poolAsset1][poolAsset0][feeMultiplier] = address(pool);

        allPools.push(address(pool));

        emit PoolDeployed(poolAsset0, poolAsset1, feeMultiplier, address(pool));

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
}
