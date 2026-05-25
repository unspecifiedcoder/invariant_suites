// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Compound-v2 cToken / hToken interface — only the view
///         methods needed for the Hundred Finance reproduction. Hundred is
///         a Compound-v2 fork, so the same selectors work.
interface ICToken {
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function getCash() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function underlying() external view returns (address);
    function comptroller() external view returns (address);
    function accrualBlockNumber() external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}
