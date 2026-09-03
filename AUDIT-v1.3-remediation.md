# Zunivo Contracts v1.3 — Remediation Report

**Base audit:** `zunivo-security-audit.md` (commit `a86d148`)
**This pass:** all fixable findings resolved in-code. **91/91 tests pass** (78 original, updated for new semantics, + 13 new fix/PoC tests). Compiler 0.8.24, no warnings that matter.

> These are the contracts to deploy at mainnet. No constructor signatures changed, so the existing deploy scripts still apply. **AgentRecords now depends on `ZunivoNames.nameEpoch`, so Names must be deployed first, then Records pointed at it** (already the deploy order).

## What changed, by finding

| # | Sev | Fix shipped |
|---|-----|-------------|
| **H-1** | High | `ScheduledSends.release()` no longer reverts when the recipient can't receive a native push. It settles the lock and credits `withdrawable[recipient]`; recipient pulls via `withdraw()`. **Permanent-freeze failure mode eliminated.** PoC `test_H1_fixed_grace0_nonReceiving_recipient_recoverable` proves a smart-wallet recipient recovers funds; unit test `test_H1_release_toNonReceiving_creditsInsteadOfReverting` proves release never reverts. |
| **M-1** | Med | `Split.pay()` credits `owed[payee]` in the loop instead of pushing. One reverting payee can no longer brick the split; each payee pulls via `withdraw(account)`. PoC `test_M1_fixed_one_bad_payee_does_not_brick_split`. |
| **M-2** | Med | `ZunivoNames` now bumps a per-token `nameEpoch` on every real transfer; `ZunivoAgentRecords` keys storage by that epoch, so records **auto-invalidate the instant a name changes hands.** Tests `test_M2_recordsInvalidateOnTransfer`, `test_M2_recordsDoNotResurrectOnReturn`. |
| **L-1** | Low | Fee legs made non-reverting across all three: `Router.pay` accrues `owedFees` (pull via `withdrawFees`), ScheduledSends/Split credit the fee to the pull ledger on failure. A bad fee sink can never DoS payments. PoC `test_L1_badFeeCollector_doesNotBlockPayment`. |
| **L-2** | Low | `ZunivoNames.mintReserved(label,to)` (onlyOwner) lets the project claim reserved brand handles. Test `test_mintReserved_ownerClaimsBrand`. |
| **L-3** | Low | All four owned contracts use two-step ownership (`transferOwnership` → `pendingOwner` → `acceptOwnership`). Tests `test_*_twoStep`. |
| **I-1** | Info | `reclaimGrace` upper-bounded at `MAX_LOCK_DURATION` (`GraceTooLong`), removing the "reclaimable in name only" footgun. Test `test_I1_graceTooLong_reverts`. |
| **I-2** | Info | `ZunivoAgentRecords` constructor rejects `_names == address(0)`. |

## Design invariants preserved (re-verified by the updated suite)
- **Zero custody except explicit pull ledgers.** The only balances any contract now holds are unclaimed pull amounts (`owed` / `withdrawable` / `owedFees`) — never un-attributed principal. Conservation fuzz tests updated and passing.
- **Owner still has no power over principal.** New admin surface is only `mintReserved` (a fresh reserved name, no fund access) and `acceptOwnership`. The evil-owner CAN/CANNOT table from the base audit is unchanged except the freeze levers (#H-1/#L-1) are now closed in code, not just by key custody.
- **Reentrancy.** Split `pay()` now makes zero external calls (pure accounting); all `withdraw*` paths zero state before the external call (checks-effects-interactions), covered by `test_withdraw_reentrancy_cannotDoublePay`.

## Residual / accepted
- A recipient/payee that can NEVER receive native value by any means keeps its funds attributed but unpullable — identical to sending value to such an address anywhere on an EVM chain, and out of scope to "rescue" without breaking the wage-irrevocability guarantee. This is a strict improvement over v1.2 (was: release reverts forever; now: settles + attributed + pullable by anything that can receive).
- I-3 (brand-variant squatting) and I-4 (tokenId namespacing) are inherent/forward-compat, not fixed.

## Mainnet deploy order (unchanged constructors)
1. `ArcPayRouter(feeCollector)`
2. `ZunivoNames(treasury, mintPrice)`
3. `ZunivoScheduledSends(treasury, feeBps)`
4. `ZunivoSplit(treasury, feeBps)`
5. `ZunivoAgentRecords(namesAddress)` ← must point at the Names from step 2
Then hand every `owner` to the 2/3 Safe via `transferOwnership` + `acceptOwnership`, and (recommended) run one more independent third-party audit on this v1.3 set before real funds.
