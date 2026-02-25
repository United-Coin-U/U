# United Stables(U)

Upgradeable ERC20 token with freeze and gas-less transaction capability.

Contract conforms to [EIP-20](https://eips.ethereum.org/EIPS/eip-20), [EIP-712](https://eips.ethereum.org/EIPS/eip-712) and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612).

## Setup

To install with [Foundry](https://github.com/foundry-rs/foundry):

```sh
forge install
```

## Test

```sh
forge test
```

## Build

```sh
forge build
```

## Deploy

Deploy and verify sample token with Transparent Proxy [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967):

```sh
export RPC=
export PK=
export ETHERSCAN_API_KEY=

forge script script/DeployStablecoin.s.sol:DeployStablecoinScript --rpc-url $RPC --private-key $PK --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```

Note that some RPCs might have rate limits so concurrent deployments might be rejected. If so, run the script line by line.

## Verify

If the contract is deployed without verification or if the deployed chain is not supported by `forge`, verification could be done independently:

```sh
export ETHERSCAN_API_KEY=

forge verify-contract --chain-id 12345 --compiler-version v0.8.28+commit.7893614a 0x1234 src/StablecoinV2.sol:StablecoinV2 --verifier-url https://api.explorer.com/api
```

Note that the `chain-id` and explorer's `verifier-url` is required.
