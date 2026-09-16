// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @dev Mirrors Chainlink's IBurnMintERC20 exactly: neither function declares a
 *      return value. StablecoinV3's mint/burn return bool, and this interface is
 *      how we prove the extra return data is harmless to a real token pool.
 */
interface IBurnMintERC20 {
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
}

/**
 * @dev Test double for Chainlink's BurnMintTokenPool. Reproduces the two calls
 *      the real pool makes:
 *        - _lockOrBurn  -> IBurnMintERC20(i_token).burn(amount)     (pool's own balance)
 *        - _releaseOrMint -> IBurnMintERC20(i_token).mint(receiver, amount)
 */
contract MockBurnMintPool {
    IBurnMintERC20 public immutable i_token;

    constructor(address token_) {
        i_token = IBurnMintERC20(token_);
    }

    function lockOrBurn(uint256 amount) external {
        i_token.burn(amount);
    }

    function releaseOrMint(address receiver, uint256 amount) external {
        i_token.mint(receiver, amount);
    }
}
