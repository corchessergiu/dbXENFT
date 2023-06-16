pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DBXENFT is ERC721 {
    address public immutable factory;
    uint256 currentTokenId;

    constructor() ERC721("DBXEN NFT", "DBXENFT"){
        factory = msg.sender;
    }

    function mintDBXENFT(address _to) external returns(uint256 tokenId){
        require(msg.sender == factory, "Only factory can mint");
        _safeMint(_to, currentTokenId);
        tokenId = currentTokenId;
        currentTokenId++;
        return tokenId;
    }
} 