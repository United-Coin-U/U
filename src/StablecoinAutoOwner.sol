// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

interface IStablecoinAutoMintBurn {
    function autoMint(address to, uint256 amount, uint256 seq, uint256 chain) external returns (bool);
    function autoBurn(uint256 amount, uint256 seq, uint256 chain) external returns (bool);
    function nonce() external view returns (uint256);
    function chainId() external view returns (uint256);
    function autoMintMaxLimit() external view returns (uint256);
}

/**
 * @title StablecoinAutoOwner
 * @notice UUPS-upgradeable controller that sits between the operator and Stablecoin.autoMint/autoBurn.
 *         Enforces an enumerable mint whitelist.
 *         Per-transaction amount is bounded above by Stablecoin.autoMintMaxLimit
 *         for BOTH mint and burn:
 *           - autoMint: delegated to Stablecoin (MintLimitExceeded revert).
 *           - autoBurn: enforced here (Stablecoin.autoBurn itself does not cap).
 *         Burn has no recipient arg; Stablecoin.autoBurn burns from Stablecoin.owner().
 */
contract StablecoinAutoOwner is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    error ZeroAddress();
    error ZeroAmount();
    error NotWhitelisted(address to);
    error LengthMismatch();
    error CallerNotOperator(address caller);
    error IndexOutOfBounds(uint256 index, uint256 length);
    error AmountExceedsMaxLimit(uint256 amount, uint256 limit);

    event StablecoinSet(address indexed stablecoin);
    event WhitelistUpdated(address indexed to, bool flag);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    IStablecoinAutoMintBurn public stablecoin;        // slot N
    EnumerableSet.AddressSet private _whitelist;      // slot N+1, N+2 (2 slots)
    address public operator;                          // slot N+3

    uint256[48] private __gap;

    modifier onlyOperator() {
        if (msg.sender != operator) revert CallerNotOperator(msg.sender);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _stablecoin, address _initialOwner, address _initialOperator)
        external
        initializer
    {
        if (_stablecoin == address(0) || _initialOwner == address(0) || _initialOperator == address(0)) {
            revert ZeroAddress();
        }
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(_initialOwner);
        stablecoin = IStablecoinAutoMintBurn(_stablecoin);
        operator = _initialOperator;
        emit StablecoinSet(_stablecoin);
        emit OperatorTransferred(address(0), _initialOperator);
    }

    function autoMint(address to, uint256 amount, uint256 seq, uint256 chain)
        external
        onlyOperator
        whenNotPaused
        returns (bool)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (!_whitelist.contains(to)) revert NotWhitelisted(to);
        return stablecoin.autoMint(to, amount, seq, chain);
    }

    function autoBurn(uint256 amount, uint256 seq, uint256 chain)
        external
        onlyOperator
        whenNotPaused
        returns (bool)
    {
        if (amount == 0) revert ZeroAmount();
        uint256 limit = stablecoin.autoMintMaxLimit();
        if (amount > limit) revert AmountExceedsMaxLimit(amount, limit);
        return stablecoin.autoBurn(amount, seq, chain);
    }

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        address previous = operator;
        operator = newOperator;
        emit OperatorTransferred(previous, newOperator);
    }

    function setWhitelist(address to, bool flag) external onlyOwner {
        _setWhitelist(to, flag);
    }

    function setWhitelistBatch(address[] calldata addrs, bool[] calldata flags) external onlyOwner {
        if (addrs.length != flags.length) revert LengthMismatch();
        for (uint256 i = 0; i < addrs.length; ++i) {
            _setWhitelist(addrs[i], flags[i]);
        }
    }

    function _setWhitelist(address to, bool flag) internal {
        if (to == address(0)) revert ZeroAddress();
        bool changed = flag ? _whitelist.add(to) : _whitelist.remove(to);
        if (changed) emit WhitelistUpdated(to, flag);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------

    function nonce() external view returns (uint256) {
        return stablecoin.nonce();
    }

    function chainId() external view returns (uint256) {
        return stablecoin.chainId();
    }

    function isWhitelisted(address to) external view returns (bool) {
        return _whitelist.contains(to);
    }

    function whitelistLength() external view returns (uint256) {
        return _whitelist.length();
    }

    function whitelistAt(uint256 index) external view returns (address) {
        uint256 len = _whitelist.length();
        if (index >= len) revert IndexOutOfBounds(index, len);
        return _whitelist.at(index);
    }

    /**
     * @notice Return the full whitelist in one call.
     * @dev Single-call enumeration. For very large whitelists prefer
     *      whitelistLength() + whitelistAt(i) to paginate.
     */
    function getWhitelist() external view returns (address[] memory) {
        return _whitelist.values();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
