// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract RebalancerVault {
    address public owner;
    address public operator;

    error NotOwner();
    error NotOperator();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        operator = msg.sender;
    }
}
