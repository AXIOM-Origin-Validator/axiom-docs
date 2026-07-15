# YPX-016: Witness Response Cache — Partial Witness Recovery

> ## ⚠️ ROLE REDUCED by YPX-018 (2026-04-10)
>
> The witness response cache described here is **NOT removed**. The implementation, the `witness_cache` SQLite table, the security analysis (§3), and all tests stay exactly as they are.
>
> What changes is the *role*: YPX-016 is no longer load-bearing for protocol correctness in the partial-witness recovery story. **[YPX-018: CLARA & Tiered Bloom Memory](AXIOM_YPX-018_HEAL_AND_TIERED_MEMORY.md)** introduces the wallet heal protocol (CLARA — Client-Led Attested Reality Alignment), which solves both halves of the 2/3 partial problem:
>
> - **Same-TX retry** — already handled by this cache. Stays as a fast-path optimization.
> - **Move-on to a different TX** — handled by CLARA: the wallet self-issues a TX_HEAL, registers it with Nabla, and presents a `ClaraAttestation` to previously poisoned validators so they roll forward.
>
> Both layers stay. The cache is the fast path for the common-case retry-after-network-blip; CLARA is the correctness path for everything else. **Do not break what works.**
>
> This document remains the spec for the cache itself and for its security argument. Read YPX-018 for the broader recovery story.

---

**Version:** 1.0
**Date:** 2026-04-10
**Status:** Implemented (role reduced — see notice above)
**Discovered:** Soak test v2 (v2.11.14-beta5)

---

## 1. Problem Discovery

During the 72-hour soak test (50 wallets, 5 parallel, 10 validators on a single machine), the success rate degraded from 92% to 19% within 2 hours, then flatlined at 0 new successful TXs for 5+ hours. All 50 wallets became permanently unusable.

The infrastructure was healthy: zero memory leaks (RSS stable 39-57MB), zero WAL growth (5-6MB constant), zero crashes, zero double-spends. The problem was purely in wallet state divergence.

## 2. Root Cause: Partial Witness Poisoning

### How it happens

S-ABR serial witness sending: V1 witnesses → V2 witnesses → V3 witnesses.

If V3 times out (DMAP contention, network, crash):
- V1 committed: state_id A→B, balance 100→20, wallet_seq 0→1
- V2 committed: same
- V3 never processed
- Client: TX "failed" (< k=3), state stays at A

V1 and V2 are now **poisoned** for this wallet:
- Their stored state (B) differs from the client's state (A)
- The client cannot provide a valid `consumed_state_id` that matches V1's stored state
- V1 and V2 reject all future TXs from this wallet with `E_SABR_HASH_MISMATCH`

### Why the wallet becomes unusable

The client's next TX requires S-ABR overlap from the last successful receipt. If the last receipt included V1 and V2, S-ABR **forces** V1 or V2 into the overlap role. They reject (state mismatch). The wallet cannot get k=3.

Over time, as more partial witnesses occur, more validators are poisoned. Eventually no combination of 3 validators can agree on the wallet's state.

### Why state_id check cannot be relaxed

We analysed and rejected multiple approaches to relax the state_id check:

1. **Skip state_id, use wallet_seq only** → double-spend via different validator sets
2. **Accept when wallet_seq higher** → cross-state attack (175 atoms from 100-atom wallet)
3. **Add balance consistency check** → attacker engineers equal remaining balances

All attacks proven with concrete scenarios. Three Core tests guard against future relaxation attempts (YPX-015 §2.9). The state_id check is **essential** for preventing cross-state double-spending.

### What causes the timeout

On a single machine with 10 validators and 5 parallel soak test subprocesses:
- DMAP proof computation: 6-18s per witness (SPHINCS+ verification in RISC-V)
- Queue contention: validators processing multiple requests
- Total response time can exceed 60s timeout

On production hardware (1 validator per machine), DMAP takes 5-7s with no queue. The timeout is primarily a dev-environment issue, but partial witness recovery is needed regardless — validators can go down, networks can partition, clients can crash.

## 3. Solution: Witness Response Cache

### Design

Each validator caches the last witness response per wallet. When the **exact same TX** is retried, the validator returns the cached response without re-executing Core.

**Per-wallet cached state:**
```
wallet_pk → {
    last_tx_hash: [u8; 32],       // Hash of the Transaction struct
    last_witness_response: bytes,  // Full serialized response (~2KB)
    consumed_state_id: [u8; 32],  // State before this witness (for matching)
    wallet_seq: u64,              // Seq of the cached TX
}
```

**Decision logic (in Lambda, before Core execution):**

```
if stored_state_id != tx.consumed_state_id
   AND cached.consumed_state_id == tx.consumed_state_id
   AND cached.wallet_seq == tx.wallet_seq
   AND cached.last_tx_hash == hash(tx):
       → Return cached.last_witness_response (no Core execution)

else if stored_state_id != tx.consumed_state_id
   AND not is_fresh_validator:
       → REJECT (state mismatch, not a retry)

else:
       → Normal processing (execute Core)
```

### Why this is safe

**1. Idempotent — no new value created**

Same TX produces same txid. Nabla txid service prevents double-redeem of the same txid. The receiver can only collect once, regardless of how many times the sender retries.

**2. Same signature — no additional cheques**

The cached response contains the original witness signature. Returning it again doesn't create new cheques — the client already had this signature from the first attempt. The client is just re-collecting a signature it lost (e.g., subprocess crash, network timeout).

**3. No state change on validator**

The validator doesn't rollback or advance state. It returns the cached response as-is. The validator's state remains at B (from the original witness). This is correct — V1 already committed to TX1, and returning the same response is consistent with that commitment.

**4. TX hash match prevents different-TX attacks**

The cache ONLY activates for the exact same TX (same nonce, same amount, same receiver, same everything). An attacker cannot substitute a different TX — the hash won't match.

Attack trace:
- TX1 (hash=H1, 80 atoms): V1 partial → cached
- TX2 (hash=H2, 80 atoms, different nonce): attacker tries cache
  - hash H2 ≠ cached H1 → **REJECT** ✓
  - No cache hit, no response returned

**5. Nabla txid prevents cross-validator double-redeem**

Attack trace:
- TX1 (hash=H1): V1,V2 partial → 2 sigs, cached on V1,V2
- TX1 retry: V1 returns cached sig, V2 returns cached sig, V4 (fresh) witnesses
  - k=3 achieved: {V1 cached, V2 cached, V4 fresh}
  - Receiver redeems → 80 atoms
- TX1 sent to V5,V6,V7 (they have state A, TX1 consumed A → match):
  - k=3 achieved: {V5, V6, V7}
  - Receiver tries to redeem → same txid → **Nabla rejects** ✓

**6. Oracle TX safe — no re-execution**

Oracle TXs require NablaStakeProof which may become stale between attempts. With response caching, there is no re-execution — the original (valid) response is returned. No stale proof issue.

**7. Group wallet safe — same TX structure**

Group wallet TXs use the same Transaction struct with consumed_state_id, wallet_seq, and client_sig. The cache mechanism operates on these fields. JFP vote TXs (1-atom to DWP/ address) are cached identically.

**8. FACT chain consistent**

The cached response includes the original fact_signature. The client collects k=3 fact_signatures (from cache + fresh validator) for the same FACT commitment. The FACT link is valid.

## 4. What this does NOT fix

**Different TX after partial witness:** If the client wants to send a DIFFERENT TX (different amount, different receiver) after a partial witness, the cache won't help (different hash). The client must use the **fresh validator fix** (YPX-015) — the poisoned validator serves as a fresh validator for the new TX, trusting overlap proof.

**Together:**
- Same TX retry → witness response cache (this spec)
- Different TX → fresh validator fix (YPX-015)
- Both cover the full range of partial witness recovery

## 5. Implementation

### Lambda changes

1. Add `WitnessCache` table to SQLite (per wallet_pk):
   - `wallet_pk BLOB PRIMARY KEY`
   - `tx_hash BLOB NOT NULL`
   - `consumed_state_id BLOB NOT NULL`
   - `wallet_seq INTEGER NOT NULL`
   - `witness_response BLOB NOT NULL`
   - `created_at INTEGER NOT NULL`

2. After successful witness production: cache the response.

3. Before Core execution: check cache. If hit → return cached response, skip Core entirely.

4. Cache eviction: overwrite on new witness (1 entry per wallet). Optional TTL for storage cleanup.

### Core changes

None. Core is not involved in the cache decision. Lambda handles it before Core execution.

### Client changes

None. The client retries the exact same TX. The validator transparently returns the cached response. The client doesn't know or care whether it was cached or fresh.

### Storage cost

~2KB per wallet × number of wallets witnessed. For a validator serving 1M wallets: ~2GB. Acceptable. The cache is also naturally bounded — one entry per wallet, overwritten on each new witness.

## 6. Soak Test Evidence

| Metric | Before cache (projected) | After cache (expected) |
|---|---|---|
| Partial witness recovery | Impossible — wallet stuck | Retry same TX → k=3 via cache |
| Wallet lifespan | Degrades to 0 in ~2h | Indefinite (self-healing) |
| Retry count per recovery | 200+ (brute force) | 1 (direct cache hit) |
| Success rate (5 parallel) | 19% after 2h → 0% | >90% sustained |
| Infrastructure stability | Proven stable (7.5h, zero leaks) | Same |
| Double-spend protection | 0 in 157 concurrent tests | Same (txid-based) |

## 7. Relationship to other fixes

This is the final piece in a series of fixes discovered during the soak test:

1. **pmc.py response consumption** — phantom timeouts (fixed)
2. **Parallel redeem → serial S-ABR** — FACT scars (fixed, YP errata)
3. **Lambda early reject** — don't block S-ABR fresh validators (fixed)
4. **ANTIE backpressure** — E_VALIDATOR_BUSY (implemented)
5. **VBC chain-of-trust** — SPHINCS+ O(k) → O(1) (fixed)
6. **Fresh validator state_id** — stale validators serve as fresh (fixed)
7. **State_id security analysis** — relaxation proven unsafe (documented + tests)
8. **Witness response cache** — partial witness recovery (this spec)

The soak test also proved infrastructure stability:
- RSS: 39-57MB stable over 7.5 hours (zero memory leak)
- WAL: 5-6MB constant (no growth)
- DB: normal growth (~1MB/hr during active TXs, flat when stuck)
- Nabla: stable, zero errors after node list fix
- Protocol: zero double-spends in 157+ concurrent fork tests

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
