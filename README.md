# paylink-core (internal codename)

Non-custodial USDC payment router for Circle's Arc — contract layer of the
payment-link product. Brand name TBD; nothing in this repo depends on it.

## Layout
- `src/ArcPayRouter.sol`   — router contract (zero custody, orderId events, fee switch capped at 1%)
- `test/ArcPayRouter.t.sol` — Foundry suite: 17 tests incl. fuzz + reentrancy probe (all passing)
- `script/Deploy.s.sol`     — Arc testnet deployment script

## Arc Testnet parameters
- Chain ID: `5042002`
- RPC: `https://rpc.testnet.arc.network`
- Explorer: `https://testnet.arcscan.app`
- Gas token: native USDC (faucet: https://faucet.circle.com — select Arc Testnet)

## Run tests
```bash
forge install foundry-rs/forge-std   # if lib/ is empty
forge test -vv
```

## Deploy (secrets via 1Password, never in files)
```bash
export DEPLOYER_PK=$(op read "op://<vault>/arc-deployer/private key")
export FEE_COLLECTOR=0x<your_fee_wallet>
forge script script/Deploy.s.sol:Deploy --rpc-url arc_testnet --broadcast
```

## ZunivoNames (src/ZunivoNames.sol)
On-chain ERC-721 handle registry: tokenId = keccak256(label), mint fee in
native USDC forwarded to treasury in-tx (zero custody), resolution follows
the NFT on transfer. 16 tests; Slither: 0 high/medium.
Deploy: script/DeployNames.s.sol (env: DEPLOYER_PK, NAMES_TREASURY, NAMES_MINT_PRICE).
Requires: git clone --depth 1 https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts

## ZunivoScheduledSends (src/ZunivoScheduledSends.sol)
Committed scheduled payments (trust layer): sender locks native USDC with an
unlock time; irrevocable before unlock (no pause/upgrade/owner path — proven
by tests); release() permissionless after unlock but pays only the fixed
recipient; optional reclaim window (>=30d after unlock) chosen irrevocably at
creation; fee bps snapshotted per lock; treasury immutable. Batch payroll up
to 100. 17 tests; Slither: timestamp-comparison notes only (inherent to
timelocks). Deploy: script/DeployScheduled.s.sol (DEPLOYER_PK, SCHED_TREASURY,
SCHED_FEE_BPS).

## ZunivoSplit (src/ZunivoSplit.sol)
Atomic revenue splitting: immutable payee/bps tables (2-20 payees, sum 10000),
any payment distributed within the same tx (zero custody, rounding dust to
last payee), per-payee ShareSent events for receipts, fee <=1% to immutable
treasury. 11 tests incl. reentrancy + conservation fuzz.
Deploy: script/DeploySplit.s.sol (DEPLOYER_PK, SPLIT_TREASURY, SPLIT_FEE_BPS).
