// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

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
 *         Enforces a per-recipient mint whitelist with per-recipient per-transaction limits.
 *         Burn is a thin passthrough (Stablecoin.autoBurn has no `from` argument).
 *         Per-recipient limits are bounded above by Stablecoin.autoMintMaxLimit at set time.
 */
contract StablecoinAutoOwner is
    Initializable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    error ZeroAddress();
    error ZeroAmount();
    error NotWhitelisted(address to);
    error PerAddressLimitExceeded(address to, uint256 amount, uint256 limit);
    error LimitAboveGlobalCap(uint256 limit, uint256 globalCap);
    error LengthMismatch();
    error CallerNotOperator(address caller);

    event StablecoinSet(address indexed stablecoin);
    event MaxMintLimitSet(address indexed to, uint256 previousLimit, uint256 newLimit);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    IStablecoinAutoMintBurn public stablecoin;
    mapping(address => uint256) public maxMintLimits;
    address public operator;

    uint256[49] private __gap;

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
        uint256 limit = maxMintLimits[to];
        if (limit == 0) revert NotWhitelisted(to);
        if (amount > limit) revert PerAddressLimitExceeded(to, amount, limit);
        return stablecoin.autoMint(to, amount, seq, chain);
    }

    function autoBurn(uint256 amount, uint256 seq, uint256 chain)
        external
        onlyOperator
        whenNotPaused
        returns (bool)
    {
        return stablecoin.autoBurn(amount, seq, chain);
    }

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        address previous = operator;
        operator = newOperator;
        emit OperatorTransferred(previous, newOperator);
    }

    function setMaxMintLimit(address to, uint256 limit) external onlyOwner {
        _setMaxMintLimit(to, limit);
    }

    function setMaxMintLimitBatch(address[] calldata tos, uint256[] calldata limits) external onlyOwner {
        if (tos.length != limits.length) revert LengthMismatch();
        for (uint256 i = 0; i < tos.length; ++i) {
            _setMaxMintLimit(tos[i], limits[i]);
        }
    }

    function _setMaxMintLimit(address to, uint256 limit) internal {
        if (to == address(0)) revert ZeroAddress();
        if (limit > 0) {
            uint256 globalCap = stablecoin.autoMintMaxLimit();
            if (limit > globalCap) revert LimitAboveGlobalCap(limit, globalCap);
        }
        uint256 previous = maxMintLimits[to];
        maxMintLimits[to] = limit;
        emit MaxMintLimitSet(to, previous, limit);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function nonce() external view returns (uint256) {
        return stablecoin.nonce();
    }

    function chainId() external view returns (uint256) {
        return stablecoin.chainId();
    }

    function maxMintLimitOf(address to) external view returns (uint256) {
        return maxMintLimits[to];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
