// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Owned} from "solmate/src/auth/Owned.sol";

abstract contract ProtocolFee is Owned {
    uint256 public protocolFee;
    address public protocolFeeRecipient;
    uint256 public immutable deploymentTimestamp;

    uint256 public constant MIN_PROTOCOL_FEE = 0.1e18; // 10%
    uint256 public constant MAX_PROTOCOL_FEE = 0.25e18; // 25%

    error InvalidFee();
    error RecipientSetAlready();

    constructor(address _feeOwner) Owned(_feeOwner) {
        deploymentTimestamp = block.timestamp;
    }

    /// @notice Permissionlessly enable a minimum protocol fee after 1 year
    function enableProtocolFee() external {
        require(block.timestamp >= (deploymentTimestamp + 365 days) && protocolFeeRecipient != address(0), InvalidFee());
        protocolFee = MIN_PROTOCOL_FEE;
    }

    /// @notice Set the protocol fee, expressed as a percentage of LP fee
    /// @param newFee The new protocol fee, in WAD units (0.10e18 = 10%)
    function setProtocolFee(uint256 newFee) external onlyOwner {
        require(MIN_PROTOCOL_FEE <= newFee && newFee <= 0.25e18 && protocolFeeRecipient != address(0), InvalidFee());
        protocolFee = newFee;
    }

    function setProtocolFeeRecipient(address newRecipient) external onlyOwner {
        require(protocolFeeRecipient == address(0), RecipientSetAlready());
        protocolFeeRecipient = newRecipient;
    }
}
