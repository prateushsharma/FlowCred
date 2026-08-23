# FlowCred Attestcoin Worker

Next vertical slice: listen for `RevenuePaymentForCredit` on Ethereum Sepolia, wait for
Attestcoin attestation, obtain Merkle + continuity proofs with `@gluwa/usc-sdk`, and submit
them to `RevenueASC` on Creditcoin CC3 Testnet.
