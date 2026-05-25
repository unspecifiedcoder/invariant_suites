// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ToyVault {
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    error InsufficientShares();

    function deposit() external payable {
        shares[msg.sender] += msg.value;
        totalShares += msg.value;
    }

    /*
        INTENTIONAL BUG:
        totalShares is NOT decremented on withdraw.
        This breaks:
            address(vault).balance == totalShares
    */
    function withdraw(uint256 amount) external {
        if (shares[msg.sender] < amount) {
            revert InsufficientShares();
        }

        shares[msg.sender] -= amount;

        // BUG:
        // totalShares -= amount;

        payable(msg.sender).transfer(amount);
    }

    receive() external payable {}
}
