// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IMaglevEulerSwapFactory {
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
    ) external returns (address);

    function evc() external view returns (address);
    function allPools(uint256 index) external view returns (address);
    function getPool(address assetA, address assetB, uint256 fee) external view returns (address);
    function allPoolsLength() external view returns (uint256);
    function getAllPoolsListSlice(uint256 start, uint256 end) external view returns (address[] memory);
}
