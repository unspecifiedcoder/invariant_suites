// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Compound-v2 cToken interface for invariant testing of
///         any Compound fork (Hundred, Cream, Sonne, Compound-on-L2 deployments).
///         Includes the writable surface used in production audits.
interface ICToken {
    // -------- View --------
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function getCash() external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function underlying() external view returns (address);
    function comptroller() external view returns (address);

    // -------- Writable --------
    /// @notice Returns 0 on success per Compound's error-code convention.
    function mint(uint256 mintAmount) external returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function accrueInterest() external returns (uint256);
}
