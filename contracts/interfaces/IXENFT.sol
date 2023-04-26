// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IXENFT {
    function vmuCount(uint256 tokenId) external view returns (uint256);

    function mintInfo(uint256 tokenId) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}