// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {JuvantiaAsset} from "../JuvantiaAsset.sol";
import {JuvantiaRevenueDistributor} from "../JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../JuvantiaAerarium.sol";
import {Consortium} from "./Consortium.sol";

/// @notice Factory for deploying governed Juvantia Consortium clones and their fixed 100,000 APU share tokens.
contract ConsortiumFactory is UUPSUpgradeable, OwnableUpgradeable, EIP712Upgradeable {
    using SafeERC20 for IERC20;
    struct ConsortiumDeploymentVoucher {
        bytes32 draftId;
        string name;
        string symbol;
        address magister;
        address[] founders;
        uint256[] founderShares;
        uint256 treasuryShares;
        uint256 deadline;
        bytes32 salt;
    }

    bytes32 public constant CONSORTIUM_VOUCHER_TYPEHASH = keccak256(
        "ConsortiumDeploymentVoucher(bytes32 draftId,string name,string symbol,address magister,address[] founders,uint256[] founderShares,uint256 treasuryShares,uint256 deadline,bytes32 salt)"
    );

    address public immutable consortiumImplementation;
    address public immutable assetImplementation;
    JuvantiaRevenueDistributor public immutable revenueDistributor;
    JuvantiaAerarium public immutable aerarium;

    address public authorizer;
    mapping(bytes32 => bool) public usedDrafts;
    mapping(bytes32 => address) public consortiumById;
    mapping(bytes32 => address) public assetById;
    address[] public consortia;

    event AuthorizerSet(address indexed authorizer);
    event ConsortiumCreated(
        bytes32 indexed draftId,
        address indexed consortium,
        address indexed shareToken,
        address magister
    );

    constructor(
        address consortiumImpl,
        address assetImpl,
        address distributor,
        address aerariumAddr
    ) {
        require(consortiumImpl.code.length > 0 && assetImpl.code.length > 0, "Invalid implementations");
        require(distributor.code.length > 0, "Invalid distributor");
        _disableInitializers();
        consortiumImplementation = consortiumImpl;
        assetImplementation = assetImpl;
        revenueDistributor = JuvantiaRevenueDistributor(distributor);
        aerarium = JuvantiaAerarium(aerariumAddr);
    }

    function initialize(address admin, address authorizerAddr) external initializer {
        require(admin != address(0) && authorizerAddr != address(0), "Invalid parameters");
        __Ownable_init(admin);
        __EIP712_init("ConsortiumFactory", "1");
        authorizer = authorizerAddr;
        emit AuthorizerSet(authorizerAddr);
    }

    function setAuthorizer(address newAuthorizer) external onlyOwner {
        require(newAuthorizer != address(0), "Invalid authorizer");
        authorizer = newAuthorizer;
        emit AuthorizerSet(newAuthorizer);
    }

    function consortiaCount() external view returns (uint256) {
        return consortia.length;
    }

    function _hashAddresses(address[] calldata addrs) internal pure returns (bytes32) {
        bytes32[] memory words = new bytes32[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            words[i] = bytes32(uint256(uint160(addrs[i])));
        }
        return keccak256(abi.encodePacked(words));
    }

    function _hashUints(uint256[] calldata uints) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(uints));
    }

    function hashVoucher(ConsortiumDeploymentVoucher calldata voucher) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            CONSORTIUM_VOUCHER_TYPEHASH,
            voucher.draftId,
            keccak256(bytes(voucher.name)),
            keccak256(bytes(voucher.symbol)),
            voucher.magister,
            _hashAddresses(voucher.founders),
            _hashUints(voucher.founderShares),
            voucher.treasuryShares,
            voucher.deadline,
            voucher.salt
        )));
    }

    /// @notice Deploy a new Consortium clone and share token clone using a Core-authorized voucher.
    function createConsortium(
        ConsortiumDeploymentVoucher calldata voucher,
        bytes calldata signature
    ) external returns (address consortiumClone, address assetClone) {
        require(block.timestamp <= voucher.deadline, "Voucher expired");
        require(voucher.draftId != bytes32(0), "Invalid draft ID");
        require(!usedDrafts[voucher.draftId], "Draft already used");
        require(voucher.founders.length == voucher.founderShares.length, "Founders length mismatch");

        bytes32 digest = hashVoucher(voucher);
        address recovered = ECDSA.recover(digest, signature);
        require(recovered == authorizer, "Invalid voucher signature");

        usedDrafts[voucher.draftId] = true;

        // Verify total shares = 100,000 ether (JuvantiaAsset.FIXED_SUPPLY)
        uint256 total = voucher.treasuryShares;
        for (uint256 i = 0; i < voucher.founderShares.length; i++) {
            require(voucher.founders[i] != address(0), "Invalid founder");
            total += voucher.founderShares[i];
        }
        require(total == 100_000 ether, "Total shares must equal 100,000 ether");

        bytes32 consortiumSalt = keccak256(abi.encodePacked(voucher.salt, "CONSORTIUM"));
        bytes32 assetSalt = keccak256(abi.encodePacked(voucher.salt, "ASSET"));

        consortiumClone = Clones.cloneDeterministic(consortiumImplementation, consortiumSalt);
        assetClone = Clones.cloneDeterministic(assetImplementation, assetSalt);

        // Asset mints 100,000 ether to this factory initially
        JuvantiaAsset(assetClone).initialize(
            voucher.name,
            voucher.symbol,
            address(this),
            owner(),
            address(revenueDistributor)
        );

        Consortium(consortiumClone).initialize(
            address(revenueDistributor.revenueToken()),
            assetClone,
            address(revenueDistributor),
            voucher.magister,
            owner()
        );

        // Register asset in RevenueDistributor with consortium ledger observer FIRST
        revenueDistributor.registerAsset(assetClone, consortiumClone);

        // Distribute founder shares
        for (uint256 i = 0; i < voucher.founders.length; i++) {
            if (voucher.founderShares[i] > 0) {
                IERC20(assetClone).safeTransfer(voucher.founders[i], voucher.founderShares[i]);
            }
        }

        // Transfer treasury reserve to consortium clone
        if (voucher.treasuryShares > 0) {
            IERC20(assetClone).safeTransfer(consortiumClone, voucher.treasuryShares);
        }

        consortiumById[voucher.draftId] = consortiumClone;
        assetById[voucher.draftId] = assetClone;
        consortia.push(consortiumClone);

        emit ConsortiumCreated(voucher.draftId, consortiumClone, assetClone, voucher.magister);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
