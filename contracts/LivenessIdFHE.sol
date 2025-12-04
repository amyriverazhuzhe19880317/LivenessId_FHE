// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract LivenessIdFHE is SepoliaConfig {

    struct EncryptedIdentity {
        uint256 id;
        euint32 encryptedBiometric;  // Encrypted biometric template
        euint32 encryptedLivenessChallenge; // Encrypted liveness proof
        uint256 timestamp;
    }

    struct DecryptedIdentity {
        string biometric;
        string livenessChallenge;
        bool isVerified;
    }

    uint256 public identityCount;
    mapping(uint256 => EncryptedIdentity) public encryptedIdentities;
    mapping(uint256 => DecryptedIdentity) public decryptedIdentities;

    mapping(uint256 => uint256) private requestToIdentityId;

    event IdentitySubmitted(uint256 indexed id, uint256 timestamp);
    event DecryptionRequested(uint256 indexed id);
    event IdentityVerified(uint256 indexed id);

    modifier onlyUser(uint256 identityId) {
        _;
    }

    function submitEncryptedIdentity(
        euint32 encryptedBiometric,
        euint32 encryptedLivenessChallenge
    ) public {
        identityCount += 1;
        uint256 newId = identityCount;

        encryptedIdentities[newId] = EncryptedIdentity({
            id: newId,
            encryptedBiometric: encryptedBiometric,
            encryptedLivenessChallenge: encryptedLivenessChallenge,
            timestamp: block.timestamp
        });

        decryptedIdentities[newId] = DecryptedIdentity({
            biometric: "",
            livenessChallenge: "",
            isVerified: false
        });

        emit IdentitySubmitted(newId, block.timestamp);
    }

    function requestIdentityDecryption(uint256 identityId) public onlyUser(identityId) {
        EncryptedIdentity storage identity = encryptedIdentities[identityId];
        require(!decryptedIdentities[identityId].isVerified, "Already verified");

        bytes32[] memory ciphertexts = new bytes32[](2);
        ciphertexts[0] = FHE.toBytes32(identity.encryptedBiometric);
        ciphertexts[1] = FHE.toBytes32(identity.encryptedLivenessChallenge);

        uint256 reqId = FHE.requestDecryption(ciphertexts, this.decryptIdentity.selector);
        requestToIdentityId[reqId] = identityId;

        emit DecryptionRequested(identityId);
    }

    function decryptIdentity(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory proof
    ) public {
        uint256 identityId = requestToIdentityId[requestId];
        require(identityId != 0, "Invalid request");

        EncryptedIdentity storage eIdentity = encryptedIdentities[identityId];
        DecryptedIdentity storage dIdentity = decryptedIdentities[identityId];
        require(!dIdentity.isVerified, "Already verified");

        FHE.checkSignatures(requestId, cleartexts, proof);

        string[] memory results = abi.decode(cleartexts, (string[]));

        dIdentity.biometric = results[0];
        dIdentity.livenessChallenge = results[1];
        dIdentity.isVerified = true;

        emit IdentityVerified(identityId);
    }

    function getDecryptedIdentity(uint256 identityId) public view returns (
        string memory biometric,
        string memory livenessChallenge,
        bool isVerified
    ) {
        DecryptedIdentity storage d = decryptedIdentities[identityId];
        return (d.biometric, d.livenessChallenge, d.isVerified);
    }
}
