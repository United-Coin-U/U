// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "./StablecoinV2.sol";

/**
 * @title StablecoinV3
 * @notice Adds Chainlink CCIP (Cross-Chain Token, Burn & Mint) support to the
 *         Stablecoin proxy. A CCIP token pool is granted permission to call
 *         `mint(address,uint256)` and `burn(uint256)` alongside the owner.
 *
 * Storage Layout for StablecoinV3:
 * - Slot 409: isCCIPMinterBurner (mapping)
 * - Slot 410: _ccipAdmin (address)
 * - Slot 411-458: __gapV3 (48 slots)
 *
 * Total new slots used: 2
 * Gap size: 48 (50 - 2 = 48)
 *
 * IMPORTANT: StablecoinV2's own `__gap` (slots 361-408) is deliberately left
 * untouched, so this contract appends at slot 409. That supersedes the guidance
 * in StablecoinV2.sol, which tells future versions to consume V2's gap; doing so
 * would require editing StablecoinV2.sol, which this upgrade explicitly avoids.
 *
 * When adding new state variables in a future upgrade (V4, etc.):
 * 1. Add new variables BEFORE `__gapV3`
 * 2. Reduce `__gapV3` by the number of slots used
 * 3. Verify with `forge inspect StablecoinV4 storage-layout`
 */
contract StablecoinV3 is StablecoinV2 {

    error CallerNotOwnerOrCCIP(address caller);

    event CCIPRolesGranted(address indexed account);
    event CCIPRolesRevoked(address indexed account);
    event CCIPAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    /// @dev Addresses permitted to mint and burn on behalf of CCIP — in practice
    ///      the Chainlink BurnMintTokenPool deployed for this token on this chain.
    mapping(address => bool) public isCCIPMinterBurner;

    /// @dev CCIP Token Administrator, decoupled from `owner()` so that routine
    ///      CCIP administration does not require the owner multisig.
    address private _ccipAdmin;

    uint256[48] private __gapV3;

    /**
     * @dev Throws if the caller is neither the owner nor a CCIP minter/burner.
     */
    modifier onlyOwnerOrCCIP() {
        require(
            msg.sender == owner() || isCCIPMinterBurner[msg.sender],
            CallerNotOwnerOrCCIP(msg.sender)
        );
        _;
    }

    /**
     * @dev Disable initializers for the implementation contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract for the V3 upgrade. Seeds the CCIP
     *      administrator with the current owner so the token is registrable with
     *      Chainlink's TokenAdminRegistry immediately after the upgrade; the
     *      owner can decouple the two later via {setCCIPAdmin}.
     */
    function initializeV3() public reinitializer(3) {
        emit CCIPAdminTransferred(_ccipAdmin, owner());
        _ccipAdmin = owner();
    }

    /**
     * @dev Permit `pool` to mint and burn, in addition to the owner. Intended for
     *      the Chainlink BurnMintTokenPool deployed for this token on this chain.
     * @param pool Token pool address
     * Can only be called by the current owner.
     */
    function grantMintAndBurnRoles(address pool) external onlyOwner {
        require(pool != address(0), NotAllowedAddress(pool));
        isCCIPMinterBurner[pool] = true;
        emit CCIPRolesGranted(pool);
    }

    /**
     * @dev Revoke a pool's permission to mint and burn. Required when rotating to
     *      a redeployed token pool, since a pool's allowlist mode cannot be
     *      changed in place.
     * @param pool Token pool address
     * Can only be called by the current owner.
     */
    function revokeMintAndBurnRoles(address pool) external onlyOwner {
        delete isCCIPMinterBurner[pool];
        emit CCIPRolesRevoked(pool);
    }
}
