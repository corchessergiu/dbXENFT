pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IDBXENFTFactory.sol";

contract DBXENFTMock is ERC721 {
    IDBXENFTFactory public immutable factory;
    uint256 currentTokenId;

    constructor() ERC721("DBXEN NFT", "DBXENFT"){
        factory = IDBXENFTFactory(0x5FA482dd7A8eE5ff4d44c72113626A721b4F4316);

        for(uint256 i; i < 13; i++) {
            _safeMint(msg.sender, currentTokenId);
            currentTokenId++;
        }
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "DBXENFT: URI query for nonexistent token");

        uint256 entryCycle = factory.tokenEntryCycle(tokenId);
        uint256 currentCycle = factory.getCurrentCycle();
        uint256 baseDBXENFTPower = factory.baseDBXeNFTPower(tokenId);
        
        if(baseDBXENFTPower == 0 && currentCycle > entryCycle){
            uint256 dbxenftEntryPower = factory.dbxenftEntryPower(tokenId);
            uint256 entryCycleReward = factory.rewardPerCycle(entryCycle);
            uint256 totalEntryCycleEntryPower = factory.totalEntryPowerPerCycle(entryCycle);
            baseDBXENFTPower = Math.mulDiv(dbxenftEntryPower, entryCycleReward, totalEntryCycleEntryPower);
        }

        if(baseDBXENFTPower == 0) {
            return "ipfs://QmP4DRDtpoPEcr367hxGmEuJztVK4Cuyrq8uQymXeVXu5q";
        } else {
            if(baseDBXENFTPower <= 1e18) {
                return "ipfs://QmYspKLLFYxU6UAxx5tBFUhuLh49wgGMeLXGtgjreHjf9z";
            } else {
                return "ipfs://QmSRgaGtwSrhCUDjGr2jFpW5H9F1u6c42hPp9vhPbmoyu3";
            }
        }
    }
} 