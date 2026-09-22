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
            _msgSender() == owner() || isCCIPMinterBurner[_msgSender()],
            CallerNotOwnerOrCCIP(_msgSender())
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
     *      administrator with the address chosen at upgrade time so the token is
     *      registrable with Chainlink's TokenAdminRegistry immediately after the
     *      upgrade; the owner can rotate it later via {setCCIPAdmin}.
     *
     *      The zero address is rejected rather than silently falling back to
     *      `owner()`, so a mis-encoded `upgradeAndCall` payload fails loudly at
     *      upgrade time instead of leaving the role implicitly on the owner.
     * @param ccipAdmin Initial CCIP administrator
     */
    function initializeV3(address ccipAdmin) public reinitializer(3) {
        require(ccipAdmin != address(0), NotAllowedAddress(ccipAdmin));
        emit CCIPAdminTransferred(_ccipAdmin, ccipAdmin);
        _ccipAdmin = ccipAdmin;
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

    /**
     * @dev See {Stablecoin-mint}. Widened to accept a CCIP token pool in addition
     *      to the owner; this is the function Chainlink's BurnMintTokenPool calls
     *      on the destination chain.
     *
     *      The freeze and pause checks are deliberately retained on this path: a
     *      regulated stablecoin must not mint to a frozen address or while
     *      paused, even though a revert here strands the in-flight CCIP message
     *      until it is manually re-executed.
     * @param to Mint to address
     * @param amount Mint amount
     * @return True if successful
     */
    function mint(address to, uint256 amount)
        external
        override
        whenNotPaused
        notFrozen(to)
        onlyOwnerOrCCIP
        returns (bool)
    {
        _mint(to, amount);
        emit Mint(_msgSender(), to, amount);
        return true;
    }

    /**
     * @dev See {Stablecoin-burn}. Widened to accept a CCIP token pool in addition
     *      to the owner; this is the function Chainlink's BurnMintTokenPool calls
     *      on the source chain, burning the tokens the Router just transferred
     *      into the pool.
     *
     *      `whenNotPaused` is deliberately omitted, matching V1: pause already
     *      blocks the outbound path, because moving tokens into the pool goes
     *      through `_transfer`.
     * @param amount Burn amount
     * @return True if successful
     */
    function burn(uint256 amount)
        external
        override
        onlyOwnerOrCCIP
        returns (bool)
    {
        _burn(_msgSender(), amount);
        emit Burn(_msgSender(), _msgSender(), amount);
        return true;
    }

    /**
     * @dev Set the CCIP Token Administrator, the address Chainlink's
     *      RegistryModuleOwnerCustom.registerAdminViaGetCCIPAdmin accepts as the
     *      registrant. Keeping it separate from `owner()` means routine CCIP
     *      administration does not require the owner multisig.
     * @param admin New CCIP administrator
     * Can only be called by the current owner.
     */
    function setCCIPAdmin(address admin) external onlyOwner {
        require(admin != address(0), NotAllowedAddress(admin));
        emit CCIPAdminTransferred(_ccipAdmin, admin);
        _ccipAdmin = admin;
    }

    /**
     * @dev Returns the CCIP Token Administrator, as required by Chainlink's
     *      TokenAdminRegistry registration flow. Falls back to `owner()` when
     *      unset so registration is never blocked by a zero address.
     * @return The CCIP administrator address
     */
    function getCCIPAdmin() external view returns (address) {
        address admin = _ccipAdmin;
        return admin == address(0) ? owner() : admin;
    }
}
