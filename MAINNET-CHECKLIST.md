# Zunivo — Mainnet Readiness Checklist

Target: **Arc mainnet launch, Sept 16, 2026**
Last updated: **Sept 17, 2026 — v1.3 DEPLOYED + VERIFIED + SMOKE 8/8 ON ARC MAINNET.** Cut-over of app/server/SDK still pending.

> **Status: contracts are live on mainnet (block 21240365). Nothing user-facing points at them yet.** See `deployments/arc-mainnet-v1.3.json` for the canonical record.

Legend: ✅ done · 🔲 todo · ⏳ blocked on external input

---

## TIER 0 — Fund safety (do NOT launch without these)

- ✅ **Security audit of all 5 contracts** — internal, audit-firm standard, 0 Critical / 1 High / 2 Med / 3 Low, all with reproducible PoCs.
- ✅ **v1.3 hardening** — pull-payment (H-1/M-1/L-1), nameEpoch record-invalidation (M-2), mintReserved (L-2), Ownable2Step (L-3). 91/91 tests pass.
- ✅ **Testnet dress rehearsal** — v1.3 deployed to Arc testnet via DeployAllV13; wiring + M-2 fix verified on-chain.
- ✅ **Pre-mainnet smoke test** — smoke.mjs 6/6 on real testnet: mint+resolve, agent records, M-2 invalidation, router pay, split 70/30 accrual, scheduled create+release. Every critical path exercised on-chain.
- 🔲 **Safe 2/3 multisig — NOW THE #1 OPEN RISK.** Mainnet owner + treasury + feeCollector of all 5 contracts is a single EOA (`0xD9ca…4311`, fresh key generated for mainnet). Deploy a Safe on Arc mainnet, then on each contract: `transferOwnership(safe)` → Safe calls `acceptOwnership()` (Ownable2Step). Treasury/feeCollector on Router/Split/Scheduled are immutable or setter-controlled — check each; where immutable, the EOA stays the payout address (acceptable short-term, funds are pulled not held). Signers: main wallet + hardware wallet + offsite backup.
- 🔲 **Independent third-party audit** — send v1.3 to Sherlock / Code4rena / a boutique firm (this is grant milestone M1). *No deploy dependency — send now, report lands before launch.*

## TIER 1 — Deploy correctness (the launch itself)

- ✅ **Mainnet parameters (confirmed on-chain)** — chainId **5042**, RPC `https://rpc.mainnet.arc.io`, native USDC `0x3600000000000000000000000000000000000000` (ERC-20 iface 6 dec; gas/`msg.value` 18 dec), explorer **`https://arc.etherscan.io`** (Etherscan-built ArcScan — the primary one) + `https://explorer.arc.io` (Circle Blockscout). CCTP domain 26. SDK `ARC_MAINNET` placeholder still needs these filled.
- ✅ **Deploy v1.3 to mainnet** — `DeployAllV13.s.sol`, block 21240365, total gas 0.164 USDC. Deployer/owner/treasury = `0xD9ca…4311` (EOA, Safe pending). Params: mintPrice 1 USDC, feeBps 50 (Router fee set post-deploy via `setFeeBps(50)` — the script only passes FEE_BPS to Scheduled/Split by design).
- ✅ **Post-deploy wiring check (cast)** — 9/9: all owners/treasury/feeCollector = deployer, mintPrice 1e18, feeBps 50 ×3, `records.names()` = Names.
- ✅ **Verify contracts** — 5/5 "Pass - Verified" on arc.etherscan.io via Etherscan V2 API. Gotchas recorded: `explorer.arc.io/api` is behind a Cloudflare challenge (CLI blocked); Etherscan verifier needs `--verifier-url "https://api.etherscan.io/v2/api?chainid=5042" --etherscan-api-key`, one contract at a time, and Etherscan rate-limits at 3 req/s (a failed *status check* ≠ failed verification — re-check the GUID).
- ✅ **Mainnet smoke (real USDC)** — `NET=mainnet node smoke.mjs smoke` → **8/8**: mint+resolve, records, M-2 invalidation, Router pay (merchant gets amount−fee, fee pushed to collector), Split 70/30 with fee to treasury + `withdraw` pull-path, Scheduled create+release. Total burn ≈ 0.06 USDC across two runs.
- 🔲 **Two-environment split** — testnet stays as the free sandbox; mainnet is separate config across app / server / SDK. No cross-contamination.
- 🔲 **Point app / server / SDK at mainnet addresses** — `.env.production`, server contract config, SDK `ARC_MAINNET`. Addresses in `deployments/arc-mainnet-v1.3.json`. **Do this only after the dedicated RPC is in place** (Tier 2) — the public gateway will rate-limit real users.

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

**MAINNET v1.3 (chainId 5042) — LIVE, verified, smoke 8/8, NOT YET WIRED to app/server/SDK:**
- Router `0xAa8c293495446d04a51A32e2e4557EDE3BfC7119`
- Names `0x824218447E8Dbf10E535dC7fB6ab7b68105c7dDa`
- ScheduledSends `0x8d2193555Ad7C3f2EEfe66Ede0F8A3477774050c`
- Split `0x3c07F894A14AA080191b2Cc95dd4d0BfA31E5715`
- AgentRecords `0xFE9fca63CaA64FBf0B2F089786A706f0C99dCbB1`
- Owner/treasury/feeCollector: `0xD9caCa6583b5F60CA60ABF4f0f0204f0CeC94311` (EOA → Safe pending)

Both testnet sets stay as sandbox.

---

## Recommended order of work now (contracts are live)

1. **Safe multisig on Arc mainnet + transferOwnership/acceptOwnership ×5** (Tier 0) ← do next; single EOA owns everything
2. **Dedicated RPC** (Tier 2, load-test-proven) — required before any user traffic hits mainnet
3. **Cut over app / server / SDK to mainnet** (Tier 1) — two-env split, `ARC_MAINNET` filled, Marketplace listing → mainnet endpoint
4. **First real mainnet agent payment → screenshot** (Tier 5 marketing proof; the smoke already did it, but do one through the product)
5. **Send v1.3 to third-party audit** (Tier 0)
6. **Delaware C-Corp** (Tier 4)
7. **CCTP on-ramp guide** (Tier 3) — without it nobody can pay
8. **VPS backups/alerts** (Tier 2)
9. **Testnet-holder claim** (Tier 3) — decide + announce honestly (what, when, how)
