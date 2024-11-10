# HODL Helper Contracts
Smart contracts powering HODL Helper, the app that helps believe in something and just HODL.

## About
The onchain protocol is built around the concept of a "Lock". A Lock escrows any amount of a single token, along with a user-specified holding period. 

To setup a Lock, a small fee of 0.00069 ETH is charged as part of the transaction. This fee helps fund the development of the app. It's pretty easy for infrastructure for the frontend and backend (planned for future) to need to scale with traffic, which costs money.

You can always add more tokens to an existing Lock, which again incurs the same small transaction fee (0.00069 ETH).

The tokens in a Lock can be withdrawn at any point, however, if withdrawn prior to the holding period ending, a 10% penalty is applied. This penalty is not applied if withdrawing after the holding period ends.

For more information about the project, see this link: https://hackmd.io/@mpeyfuss/hodl-helper

## Deployments
Each version is deployed to the same address across all supported EVM chains. The following chains are supported:
- Ethereum
- Arbitrum
- Base
- Optimism

Details for deployments are in `deployments.json`. Deployment addresses can be found below.

| Version | Address                                    |
|---------|--------------------------------------------|
| 1.0.0   |  |

## Development

Foundry is used as the smart contract framework and Poetry is used for installing slither-analyzer for auditing purposes.

1. Install Foundry
2. Install Poetry
3. Run `poetry install`
4. Run `make test`

## Disclaimer
This is experimental software and is provided on an "as is" and "as available" basis.

We do not give any warranties and will not be liable for any loss incurred through any use of this codebase.

While this code has been heavily tested, there may be parts that may exhibit unexpected emergent behavior when used with other code, or may break in future Solidity versions.

Please always include your own thorough tests when using Solady to make sure it works correctly with your code.