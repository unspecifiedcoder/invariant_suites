// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title  VulnerableVault — naive share-based vault, ERC-4626-shaped
/// @notice Reference implementation reproducing the canonical
///         first-depositor inflation attack on ERC-4626-style vaults.
///
///         DELIBERATELY OMITTED MITIGATIONS:
///         - Virtual shares / virtual assets (OZ-style)
///         - Dead-shares-on-deploy bootstrap
///         - Min-shares guard on deposit (`require(shares > 0)`)
///
///         Naive bootstrap + naive rounding-down in convertToShares is what
///         lets an attacker inflate the share price after seeding 1 share,
///         then drain any subsequent depositor whose amount rounds to zero.
contract VulnerableVault {
    IERC20 public immutable asset;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    error NotAuthorized();

    constructor(IERC20 asset_) {
        asset = asset_;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @dev Naive bootstrap + rounding-down. With totalSupply == 0, the very
    ///      first depositor gets exactly `assets` shares (1:1). After that,
    ///      share price is `totalAssets / totalSupply` and small deposits
    ///      can round to zero shares.
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalSupply == 0) return assets;
        return assets * totalSupply / totalAssets();
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply == 0) return shares;
        return shares * totalAssets() / totalSupply;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        // NO `require(shares > 0)` — depositor can pay assets for zero shares.
        asset.transferFrom(msg.sender, address(this), assets);
        balanceOf[receiver] += shares;
        totalSupply += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) revert NotAuthorized();
        assets = convertToAssets(shares);
        balanceOf[owner] -= shares;
        totalSupply -= shares;
        asset.transfer(receiver, assets);
    }
}
