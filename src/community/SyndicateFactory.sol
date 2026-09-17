// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Syndicate} from "./Syndicate.sol";

/// @notice Factory for deploying gaming Syndicate clones without ERC-20 tokens.
contract SyndicateFactory is UUPSUpgradeable, OwnableUpgradeable, EIP712Upgradeable {
    struct SyndicateDeploymentVoucher {
        bytes32 draftId;
        string name;
        address primus;
        uint8 presetType;
        uint8 gradeCount;
        address[] members;
        uint8[] memberGrades;
        uint256 deadline;
        bytes32 salt;
    }

    bytes32 public constant SYNDICATE_VOUCHER_TYPEHASH = keccak256(
        "SyndicateDeploymentVoucher(bytes32 draftId,string name,address primus,uint8 presetType,uint8 gradeCount,address[] members,uint8[] memberGrades,uint256 deadline,bytes32 salt)"
    );

    address public immutable syndicateImplementation;
    address public immutable paymentToken;

    address public authorizer;
    mapping(bytes32 => bool) public usedDrafts;
    mapping(bytes32 => address) public syndicateById;
    address[] public syndicates;

    event AuthorizerSet(address indexed authorizer);
    event SyndicateCreated(bytes32 indexed draftId, address indexed syndicate, address indexed primus);

    constructor(address syndicateImpl, address token) {
        require(syndicateImpl.code.length > 0, "Invalid implementation");
        require(token.code.length > 0, "Invalid token");
        _disableInitializers();
        syndicateImplementation = syndicateImpl;
        paymentToken = token;
    }

    function initialize(address admin, address authorizerAddr) external initializer {
        require(admin != address(0) && authorizerAddr != address(0), "Invalid parameters");
        __Ownable_init(admin);
        __EIP712_init("SyndicateFactory", "1");
        authorizer = authorizerAddr;
        emit AuthorizerSet(authorizerAddr);
    }

    function setAuthorizer(address newAuthorizer) external onlyOwner {
        require(newAuthorizer != address(0), "Invalid authorizer");
        authorizer = newAuthorizer;
        emit AuthorizerSet(newAuthorizer);
    }

    function syndicatesCount() external view returns (uint256) {
        return syndicates.length;
    }

    function _hashAddresses(address[] calldata addrs) internal pure returns (bytes32) {
        bytes32[] memory words = new bytes32[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            words[i] = bytes32(uint256(uint160(addrs[i])));
        }
        return keccak256(abi.encodePacked(words));
    }

    function _hashUint8s(uint8[] calldata vals) internal pure returns (bytes32) {
        bytes32[] memory words = new bytes32[](vals.length);
        for (uint256 i = 0; i < vals.length; i++) {
            words[i] = bytes32(uint256(vals[i]));
        }
        return keccak256(abi.encodePacked(words));
    }

    function hashVoucher(SyndicateDeploymentVoucher calldata voucher) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            SYNDICATE_VOUCHER_TYPEHASH,
            voucher.draftId,
            keccak256(bytes(voucher.name)),
            voucher.primus,
            voucher.presetType,
            voucher.gradeCount,
            _hashAddresses(voucher.members),
            _hashUint8s(voucher.memberGrades),
            voucher.deadline,
            voucher.salt
        )));
    }

    /// @notice Deploy a new Syndicate clone using a Core-authorized voucher.
    function createSyndicate(
        SyndicateDeploymentVoucher calldata voucher,
        bytes calldata signature
    ) external returns (address clone) {
        require(block.timestamp <= voucher.deadline, "Voucher expired");
        require(voucher.draftId != bytes32(0), "Invalid draft ID");
        require(!usedDrafts[voucher.draftId], "Draft already used");
        require(voucher.members.length == voucher.memberGrades.length, "Members and grades length mismatch");

        bytes32 digest = hashVoucher(voucher);
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == authorizer, "Invalid voucher signature");

        usedDrafts[voucher.draftId] = true;

        bytes32 salt = keccak256(abi.encodePacked(voucher.salt, "SYNDICATE"));
        clone = Clones.cloneDeterministic(syndicateImplementation, salt);

        Syndicate(clone).initialize(
            Syndicate.SyndicateInitParams({
                token: paymentToken,
                primus: voucher.primus,
                preset: Syndicate.PresetType(voucher.presetType),
                grades: voucher.gradeCount,
                members: voucher.members,
                memberGrades: voucher.memberGrades
            })
        );

        syndicateById[voucher.draftId] = clone;
        syndicates.push(clone);

        emit SyndicateCreated(voucher.draftId, clone, voucher.primus);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
