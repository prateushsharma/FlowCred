# FlowCred Architecture

```text
Ethereum Sepolia
  RevenueRegistry.sol
        |
        | RevenuePaymentForCredit
        v
Off-chain Attestcoin Worker
        |
        | Merkle + continuity proof, encoded tx
        v
Creditcoin CC3 Testnet
  RevenueASC.sol
        |
        | verified revenue
        v
  RevenueCreditManager.sol
        |
        v
  LendingVault.sol
```

## Source-chain invariant

The source contract stays minimal. It moves the approved payment token and emits one explicit,
unambiguous event designed for Attestcoin readability. Credit calculation and lending state belong
on Creditcoin.
