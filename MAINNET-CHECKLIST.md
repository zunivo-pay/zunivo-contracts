# Zunivo — Mainnet Readiness Checklist

Target: **Arc mainnet launch, Sept 16, 2026**
Last updated: after v1.3 audit + testnet dress rehearsal.

Legend: ✅ done · 🔲 todo · ⏳ blocked on external input

---

## TIER 0 — Fund safety (do NOT launch without these)

- ✅ **Security audit of all 5 contracts** — internal, audit-firm standard, 0 Critical / 1 High / 2 Med / 3 Low, all with reproducible PoCs.
- ✅ **v1.3 hardening** — pull-payment (H-1/M-1/L-1), nameEpoch record-invalidation (M-2), mintReserved (L-2), Ownable2Step (L-3). 91/91 tests pass.
- ✅ **Testnet dress rehearsal** — v1.3 deployed to Arc testnet via DeployAllV13; wiring + M-2 fix verified on-chain.
- ✅ **Pre-mainnet smoke test** — smoke.mjs 6/6 on real testnet: mint+resolve, agent records, M-2 invalidation, router pay, split 70/30 accrual, scheduled create+release. Every critical path exercised on-chain.
- 🔲 **Safe 2/3 multisig** — replace the single deployer key (`0x6963…90c8`) as owner of all owned contracts. Signers: main wallet + hardware wallet + offsite backup. Deploy Safe, then post-mainnet transferOwnership → Safe acceptOwnership on each contract. *No mainnet dependency — can set up now.*
- 🔲 **Independent third-party audit** — send v1.3 to Sherlock / Code4rena / a boutique firm (this is grant milestone M1). *No deploy dependency — send now, report lands before launch.*

## TIER 1 — Deploy correctness (the launch itself)

- ⏳ **Mainnet parameters** — Arc mainnet chainId, RPC, USDC ERC-20 address + decimals. SDK `ARC_MAINNET` is a placeholder that REFUSES to run until filled. *Blocked on Circle publishing mainnet params.*
- 🔲 **Deploy v1.3 to mainnet** — same `DeployAllV13.s.sol`, TREASURY = Safe address, mainnet RPC. (Rehearsed ✓.)
- 🔲 **Verify contracts on mainnet ArcScan** — `forge verify-contract --verifier blockscout`.
- 🔲 **Two-environment split** — testnet stays as the free sandbox; mainnet is separate config across app / server / SDK. No cross-contamination.
- 🔲 **Point app / server / SDK at mainnet addresses** — update `.env.production`, server contract config, SDK. Cut over only after contracts verified.

## TIER 2 — Infrastructure hardening

- ✅ **Load test (testnet)** — smoke 6/6 all critical paths green; load run (20 wallets/180s) PROVED the public RPC gateway is the bottleneck: 1709/1800 failures were `Request exceeds defined limit.` from rpc.testnet.arc.network (not contract or server failures). Contracts/server were never the limiter — the gateway rejected requests at the door.
- 🔲 **Dedicated RPC endpoint (NOW A HARD REQUIREMENT, load-test-proven)** — the public gateway rate-limits under real concurrency; mainnet users would be blocked at the door. Provision a dedicated Arc RPC (Circle ecosystem allocation, or QuickNode/dRPC/Alchemy paid endpoint) for both the app and the server BEFORE launch. Re-run `smoke.mjs load` against it to measure true contract/server throughput (this run couldn't — requests never reached them).
- 🔲 **VPS production-grade** — automated SQLite backups (offsite), pm2 crash alerts.
- 🔲 **Circle Marketplace health** — endpoints must stay up (they health-check listed services); confirm mainnet endpoints pass once cut over.
- 🔲 **Redis consumedStore** (mid-term) — x402 replay store is durable sqlite (fine for Day-1 single instance); move to Redis when multi-instance.

## TIER 3 — Product & business decisions

- 🔲 **Mint pricing** — testnet is free; decide mainnet price (short names premium, long names cheap; Day-1 promo?).
- 🔲 **Testnet-holder claim** — testnet names don't carry to mainnet. Offer early holders a priority claim (snapshot + merkle allowlist)? Announce before launch.
- 🔲 **CCTP on-ramp** — how ordinary users get USDC onto Arc. Day-1: at least an illustrated "Add funds" guide; ideal: in-app CCTP component. Without this, nobody can pay.
- 🔲 **Passkey coverage** (post-launch) — extend Circle Modular Wallets beyond the pay page to send/receive so users never touch a seed phrase.

## TIER 4 — Legal & entity

- 🔲 **Delaware C-Corp** (Stripe Atlas) — required for VC/grants/Alliance; also unblocks the Alliance application entity field.
- 🔲 **Terms of Service + Privacy Policy** — on the site before handling real money.
- 🔲 **83(b) election** — within 30 days of receiving founder shares (hard IRS deadline).

## TIER 5 — Launch-day playbook (Sept 16)

- 🔲 Deploy to mainnet BEFORE the 6pm GMT launch livestream.
- 🔲 First mainnet agent payment on-chain → screenshot as marketing proof.
- 🔲 Live-quote-tweet Circle/Arc official posts during the stream (peak traffic window).
- 🔲 Switch the Agent Marketplace listing to the mainnet endpoint.
- 🔲 Have a rollback/incident plan (who does what if something breaks).

---

## Current live state (don't confuse the two contract sets)

**OLD contracts (testnet) — powering app.zunivo.io / server / SDK RIGHT NOW:**
- Router `0x4210D40a9899e42b4946B9dC7E0C35d3cf14Ea55`
- Names `0x244e0c8bE1Ed59636901F98920413d414B158cc5`
- Records `0x4f405f0aA04FD6FaE0838DeE6FD184B1f3cC306B`
- (+ Scheduled, Split from the original set)

**NEW v1.3 contracts (testnet) — deployed for rehearsal, NOT wired to anything:**
- Router `0x911e434D69F558b864Da8069b429Eb338E910130`
- Names `0xFb9fb4555bb7178E8b9B5f69C38044159D6c5146`
- ScheduledSends `0xDE65b1aa608d027fC26cF1cf801F37Bf1D820bf3`
- Split `0xD7e9668b6F2C65a5B447788E09A29dc9c1b8551B`
- AgentRecords `0x1453f3B30E2648bE9DAFFE72d7bc2424FDadA45F`

At mainnet: a THIRD set (v1.3 on mainnet) becomes the real one; both testnet sets stay as sandbox.

---

## Recommended order of work before Sept 16

1. **Safe multisig** (Tier 0, no dependency) ← do next
2. **Send v1.3 to third-party audit** (Tier 0, no dependency)
3. **Delaware C-Corp** (Tier 4, unblocks Alliance + 83b)
4. **Mint pricing + testnet-holder claim decision** (Tier 3)
5. **VPS backups/alerts** (Tier 2)
6. **CCTP on-ramp guide** (Tier 3)
7. When Circle publishes mainnet params → **fill ARC_MAINNET, deploy, verify, cut over** (Tier 1)
8. **Launch-day playbook rehearsal** (Tier 5)
