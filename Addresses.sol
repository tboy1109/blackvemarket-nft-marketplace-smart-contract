// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Addresses is Ownable {
    address[] contracts;
    mapping(address => bool) verified;

    modifier exists(address contractAddr) {
        require(existingContract(contractAddr), "The contract does not exist");
        _;
    }

    modifier doesNotExist(address contractAddr) {
        require(!existingContract(contractAddr), "The contract already exists");
        _;
    }

    function existingContract(address contractAddr) public view returns (bool) {
        uint256 i;
        uint256 length = contracts.length;
        for (i = 0; i < length; ++i) {
            if (contracts[i] == contractAddr) {
                return true;
            }
        }
        return false;
    }

    function addContract(address contractAddr)
        external
        doesNotExist(contractAddr)
        onlyOwner
    {
        contracts.push(contractAddr);
    }

    function removeContract(address contractAddr)
        external
        exists(contractAddr)
        onlyOwner
    {
        uint256 i;
        uint256 length = contracts.length;
        for (i = 0; i < length; ++i) {
            if (contracts[i] == contractAddr) {
                break;
            }
        }
        require(i < length, "Not Found the Contract");
        contracts[i] = contracts[length - 1];
        contracts.pop();
        verified[contractAddr] = false;
    }

    function verify(address contractAddr)
        external
        exists(contractAddr)
        onlyOwner
    {
        require(
            verified[contractAddr] == false,
            "The contract is already verified"
        );
        verified[contractAddr] = true;
    }

    function getContracts() external view returns (address[] memory) {
        return contracts;
    }

    function getVerifiedContracts() external view returns (address[] memory) {
        address[] memory verifiedContracts;
        uint256 i;
        uint256 length = contracts.length;
        uint256 vlength = 0;
        for (i = 0; i < length; ++i) {
            if (verified[contracts[i]]) {
                verifiedContracts[vlength++] = contracts[i];
            }
        }
        return verifiedContracts;
    }

    function isVerified(address contractAddr) external view returns (bool) {
        return verified[contractAddr];
    }
}
