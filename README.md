## About

This smart contract is used to perform a lottery

## Methodology

1. User enters the lottery by buting a ticket
   1. Ticket fees are sent to winner during the draw
2. After a period of time, lottery will automatically draw a winner
3. Chainlink VRF and Chainlink Automation is used
   1. Chainlink VRF - Randomness
   2. Chainlink Automation - Time based trigger

### Deployed Contract

- Sepolia - `https://sepolia.etherscan.io/address/0x3c61af2053e5f17d3127a1a75271bbe1111232b9` (Lottery every hour)
- Sepolia - `https://sepolia.etherscan.io/address/0x3205dE9a52E6cd364F64d680ED00e15f7FDb5A9b` (Lottery every 2 mins)
