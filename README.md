# zunivo contracts

The five verified, zero-custody contracts behind [zunivo](https://zunivo.io) —
non-custodial USDC rails on Circle's Arc.

| contract | address (Arc Testnet) | role |
| --- | --- | --- |
| `ArcPayRouter` | [`0x4210…Ea55`](https://testnet.arcscan.app/address/0x4210D40a9899e42b4946B9dC7E0C35d3cf14Ea55) | atomic order-bound settlement, payer→payee in one tx, fee hard-capped at 1% on-chain |
| `ZunivoNames` | [`0x244e…8cc5`](https://testnet.arcscan.app/address/0x244e0c8bE1Ed59636901F98920413d414B158cc5) | `.agent` payment names — ERC-721, art & metadata 100% on-chain, payments follow the holder |
| `ZunivoScheduledSends` | [`0xad51…47c02`](https://testnet.arcscan.app/address/0xad5121668867a234Bd1f7D62eC40D09Ee3f47c02) | keyless committed sends: irrevocable payroll/budgets, permissionless release |
| `ZunivoSplit` | [`0x12F2…53eCF`](https://testnet.arcscan.app/address/0x12F21A2AC582061598445874c6C5f4F3bcE53eCF) | immutable revenue-share tables (2–20 payees), one payment splits atomically |
| `ZunivoAgentRecords` | [`0x4f40…306B`](https://testnet.arcscan.app/address/0x4f405f0aA04FD6FaE0838DeE6FD184B1f3cC306B) | service discovery for `.agent` names — endpoint / x402 / description text records, writes gated by name ownership |

All five are **verified on ArcScan** and covered by a **78-test adversarial
Foundry suite** (fuzzing, reentrancy probes, owner-powerlessness proofs).

## Layout

- `src/` — the five contracts above
- `test/` — 78 tests across five suites (`forge test -vv`)
- `script/` — deployment scripts (`Deploy`, `DeployNames`, `DeployRecords`, …)

## Arc Testnet parameters

- Chain ID: `5042002`
- RPC: `https://rpc.testnet.arc.network`
- Explorer: `https://testnet.arcscan.app`
- Gas token: native USDC (faucet: https://faucet.circle.com — select Arc Testnet)

## Run tests

```bash
forge install foundry-rs/forge-std   # if lib/ is empty
forge test -vv                        # 78/78
```

## Deploy

Secrets are entered at the prompt or via env — never committed to files.

```bash
read -s "DEPLOYER_PK?deployer key: " && export DEPLOYER_PK="0x${DEPLOYER_PK#0x}"
forge script script/Deploy.s.sol:Deploy --rpc-url arc_testnet --broadcast
```

## Ecosystem

- App: [app.zunivo.io](https://app.zunivo.io) · Docs: [docs.zunivo.io](https://docs.zunivo.io)
- Agent SDK: [`zunivo-x402-arc`](https://www.npmjs.com/package/zunivo-x402-arc) (x402 payments on Arc)
- MCP server: [`zunivo-mcp`](https://www.npmjs.com/package/zunivo-mcp) (agents pay from Claude/ChatGPT/Cursor)
