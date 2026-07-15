# YPX-018: CLARA & Tiered Bloom Memory

> **CLARA** — *Client-Led Attested Reality Alignment*
> Named after Clara Oswald, the companion who walked the Doctor's fractured timestream
> and restored every broken version of him. CLARA does the same for an AXIOM wallet whose
> state has fractured across poisoned validators.

**Status:** Implemented — CLARA (`nabla/src/clara.rs`, TX_HEAL) and tiered bloom eras (`nabla/src/bloom_era.rs`, `garbage_state_chain.rs`) are live; Phase 5e/5f hardening closed 2026-05-11 (§2.1.2, §2.4.1)
**Version:** 1.0
**Date:** 2026-04-10
**Authors:** AXIOM Origin
**Supersedes:** YPX-014 (Nabla Txid Service), YPX-016 (Witness Response Cache)
**Depends on:** YPX-001 (FACT Chain), YPX-003 (TARDIS), YPX-011 (Genesis Integrity), YPX-013 (Console Engine)
**Yellow Paper:** §17.10.14, §21.10.6, §26.17.7, §39.8, §39.9 (rewrite)

---

## Abstract

This spec resolves two related architectural problems that surfaced during soak testing:

1. **The 2/3 partial witness problem.** When a transaction reaches 2 of 3 witnesses but not the third, the wallet's state diverges from the two committed validators' state, and the wallet becomes permanently unable to transact through them. Previous proposed solutions (PSP, two-phase commit, witness response cache, validator state rollback) all failed security or usability analysis.

2. **The single-bloom storage flaw in YPX-014.** The current 18 MB monolithic txid bloom saturates at ~10 M entries. At any meaningful adoption, false positive rate climbs and innocent users are randomly told their cheques are already redeemed. This is a real bug in pre-release infrastructure.

The unified solution has three pieces, all reusing existing AXIOM primitives:

- **CLARA (Client-Led Attested Reality Alignment)** — a wallet recovers from a 2/3 partial by self-issuing a healing cheque, registering it with Nabla, and presenting a Nabla-signed `ClaraAttestation` to the previously poisoned validators so they can roll their stored state forward.
- **Tiered Bloom Memory** — time-bucketed bloom files + an age index + light/archive node tiers. Storage stays small for citizens; correctness stays absolute.
- **Console-Governed Phase-Out** — a fourth Console action type lets the protocol announce phase-out of the oldest bloom eras, with constitutional minimums in Core that the Console cannot override.

Together these solve the 2/3 problem permanently, fix the YPX-014 storage flaw, and give AXIOM a forever-by-default memory model with a graceful path for managing storage when needed.

---

## 1. Background

### 1.1 The 2/3 partial witness problem

S-ABR (§17.10) requires k=3 witness signatures to complete a transaction. If V1 and V2 sign but V3 never responds, the client holds 2 sigs and considers TX1 failed. V1 and V2, however, have *already committed* their state — they store `TX1.produced_state_id` as the wallet's current state, even though no FACT link was ever registered with Nabla.

The wallet is now **poisoned at V1 and V2**: any future TX from this wallet that consumes the wallet's "real" pre-TX1 state will mismatch what V1/V2 stored. V1/V2 reject with `E_SABR_HASH_MISMATCH`. The wallet cannot use those validators.

If enough partial witnesses accumulate, no combination of k validators can agree on the wallet's state and the wallet becomes permanently unusable.

This was observed in the v2.11.14 soak test. Success rate degraded from 92% → 0% in approximately 2 hours, with all 50 wallets stuck. Infrastructure was healthy throughout — the failure was purely state divergence.

### 1.2 Why prior approaches failed

| Approach | Failure mode |
|---|---|
| Relax `state_id` check | Cross-state double-spend (proven, 175 atoms from a 100-atom wallet — see YPX-015 §2.9) |
| `wallet_seq` only | Cross-state attack with engineered equal balances |
| Witness Response Cache (YPX-016) | Only fixes *retry-same-TX*. Does not let the client move on to a *different* TX. |
| PSP (Potential Scarred Payment) | The PSP receiver carries an unhealable scar — burning the cheque mints money out of thin air, because the abandoned TX can replay later and Bob redeems while Joe has already burned. |
| Two-phase commit | Adds protocol round, time-delay attack surface, and significant complexity. |
| Tick-bounded witness sigs | Reshapes a core invariant for one edge case. Wrong layer. |

The pattern across all of these: they assume validators must somehow *unwind* a partial commit, or that the client must accept a permanent encumbrance. **Neither is necessary.**

### 1.3 Design history: YPX-014, the single-bloom txid service, and why it was replaced

This section preserves the full reasoning of YPX-014 (Nabla Txid Service, v1.0,
2026-04-07), which this document supersedes. Understanding what YPX-014 got right —
and exactly where it broke — is what motivates the tiered design in §3 and §4.

**What YPX-014 proposed.** Nabla nodes answer one question for redeem-time safety:
"was this txid already redeemed anywhere in the mesh?" The design: every Nabla node
keeps a single 18 MB bloom filter over all redeemed txids in the network's history,
with an optional HashMap mode (authoritative, zero false positives, ~640 MB at 10 M
txids) for well-resourced operators, incentivised by a CC-score multiplier. Clients
fetch a signed `NablaTxidAttestation` from Nabla's query endpoint and present it at
redeem; Lambda never queries Nabla directly — it only verifies the client-carried
attestation signature. Cross-node sync gossips new txids between peers.

**Why it looked right.** 18 MB fits on every citizen node — a phone can carry the
whole network's redeem history. Bloom lookups are O(1). At the design date the mesh
had processed well under a million txids; 10 M looked years away, and the documented
plan was to "reset" the bloom periodically as the false-positive rate drifted up
(blooms accumulate bits permanently — there is no delete).

**What broke it.** Two compounding facts:

1. A bloom false positive on a txid lookup tells the receiver "this cheque was
   already redeemed," and the receiver permanently rejects a legitimate cheque —
   **silent loss of user funds**, the worst failure class in the protocol.
2. AXIOM at any meaningful adoption blows past 10 M txids in months, and the
   single-bloom FPR curve is catastrophic past that point:

| Stored entries | FPR |
|---|---|
| 1 M | 0.0005% |
| 10 M | 0.5% |
| 100 M | ~50% |
| 1 B | ~99% (useless) |

The information-theoretic floor for distinguishing N items at false-positive rate ε is `N · log₂(1/ε)` bits. There is no clever bloom variant that escapes this — only structural changes to *how* bloom is used. The periodic-reset idea fails the same way: a reset discards the network's redeem history, and a discarded txid is exactly a double-redeem waiting to happen.

**What survived from YPX-014.** The failure was in the *storage shape*, not the
protocol shape, and the parts that were right are load-bearing today:

- The **client-carried signed attestation** pattern (client queries Nabla, presents
  `NablaTxidAttestation` at redeem, Lambda verifies without ever contacting Nabla)
  is preserved verbatim and extended in §4.6 with era and three-state status
  (`NotRedeemed | Redeemed | PhasedOut`). It is implemented across
  `core/logic/src/nabla_wire.rs` (wire types), `core/logic/src/cl5_inputs.rs`
  (redeem-time verification), and `nabla/src/transport.rs` (query serving).
- The **bloom primitive itself** survived — sliced into time-bucketed eras
  (`nabla/src/bloom_era.rs`, one bloom per quarter-year), each era sized so its FPR
  stays below 10⁻⁹ for the protocol's full lifetime (§3.4). The single bloom was
  the bug; blooms per era are the fix.
- The **HashMap-mode tiering idea** (different operators carry different service
  levels) became the light/archive node tiers of §3.1.

---

## 2. CLARA — Client-Led Attested Reality Alignment

CLARA is the heal protocol. Throughout this section the protocol is referred to as **CLARA**, the verb is **heal** ("the wallet heals via CLARA"), and the on-disk artifact carrying the proof is the **`ClaraAttestation`**.

### 2.1 Design — heal-forward with preserved S-ARB

When a wallet detects a 2/3 partial (or any state where it diverged from validator-stored state), it initiates a **heal-forward**: TX_HEAL consumes the *poisoned* state the validators actually stored, not the wallet's pre-partial view. This preserves the S-ARB trust chain — the validators that sign TX_HEAL are the same ones that really committed the partial, so their overlap signatures are cryptographically anchored in authoritative previous state.

1. **Partial-witness detection.** After TX1 completes with `0 < ok_count < k`, the wallet's client records, for the first partial only:
   - `poisoned_state_id` — the deterministic `produced_state_id` the committed validators stored (`SHA3-256("AXIOM_STATE" || pk || new_balance || new_seq || consumed || nonce)`).
   - `poisoned_committers` — the validator IDs drawn from TX1's `ok_list`. These are the validators whose stored state is exactly `poisoned_state_id`.
   - `poisoned_balance`, `poisoned_wallet_seq` — the `(balance, seq)` the committed validators stored (pre-partial balance minus TX1.amount, pre-partial seq + 1). TX_HEAL's sig_msg must use these values, otherwise the poisoned validators reject with `SABRHashMismatch`.
   - The pre-partial state (`consumed_state_id` of TX1) is *also* recorded in `garbage_state_ids`, so that any TX_prev-witness that was not a committer (likely still stale at `X_real`) can roll forward via the CLARA attestation on the next TX.

2. **Wallet builds TX_HEAL** as a self-cheque (sender = receiver = itself) with:
   - `consumed_state_id = poisoned_state_id` (not the pre-partial state)
   - `wallet_seq = poisoned_wallet_seq + 1`
   - `declared_balance = poisoned_balance`
   - `is_heal = true` (Core CL1 §11.9.4 self-send exception; signing message appends `AXIOM_HEAL_BIND || 0x01`)

3. **Wallet routes TX_HEAL to `poisoned_committers + 1 truly-fresh validator`.** The truly-fresh validator MUST NOT be a member of the last-known witness set minus the committers — those are stale at `X_real` and would reject TX_HEAL with `SABRHashMismatch`. The client computes the safe pool as `(all validators) − poisoned_committers − (prev_witness_set − poisoned_committers)`.

4. **Witness propagation under standard S-ARB:**
   - **Committers sign first** via the overlapped path: their stored state equals `poisoned_state_id`, which equals `consumed_state_id`, so CL3's chain check passes. Their PKs appear in `prev_receipts.witness_sigs` (the last successful TX's k=3 set), so they are "overlapped from the previous TX" in the CL2 sense.
   - **Fresh validator accepts last** via the fresh-validator path. Its CL2 check requires ≥ `k-1 = 2` valid overlap sigs from PKs in `prev_receipts.witness_sigs`, signed over TX_HEAL's commitment. The committers have just signed TX_HEAL's commitment (not replayed old sigs), and their PKs are in `prev_receipts`, so the overlap check passes. k=3 reached.

5. **Wallet registers TX_HEAL with Nabla** via `POST /clara`. The cheque bundle carries the k=3 sigs from the heal witness set. Nabla verifies the bundle cryptographically (Phase 5e/5f checks all still apply), derives `healed_from_state_id = tx.consumed_state_id = poisoned_state_id` and `healed_at_seq = tx.wallet_seq` from the authoritative TX, and issues a signed `ClaraAttestation` with `declared_garbage = {poisoned_state_id, X_real}`.

6. **Wallet attaches the `ClaraAttestation`** to the next outgoing TX. Any validator whose stored state is in `garbage_state_ids` — including TX_prev witnesses stale at `X_real` that weren't in TX_HEAL's set — rolls forward via the standard CL2 CLARA eligibility check, synthetic rewrite (state_id + wallet_seq + **balance**, see §2.3), and post-Core commit to Lambda storage.

**Why heal-forward preserves the S-ARB double-spend floor.** The earlier CLARA draft routed TX_HEAL through 3 fresh validators that accepted the client-supplied `consumed_state_id` at face value (YPX-015 fresh-validator rule). That broke S-ARB: an attacker could claim any historical state as "the state I'm healing from", no validator had the authoritative record to contradict it, and the resulting CLARA attestation could then roll previously-honest validators *backward* onto an attacker-chosen fork — the classical rollback double-spend.

The heal-forward rule closes this by construction. The *only* validators that can sign a TX_HEAL consuming `X_pending` are the ones whose stored state is exactly `X_pending` — and those are, by definition, the real committers of the partial TX. An attacker with no actual partial commit cannot produce valid signatures from such validators (they would reject the TX at CL3 for state mismatch). The fresh backfill validator still runs the full S-ARB overlap check, and will only accept if the committer sigs are real, valid, and anchored in `prev_receipts`. The trust floor for a rollback attack is therefore identical to the trust floor for forking any normal k=3-witnessed TX: an attacker must collude with 2 of the actual previous-TX witnesses, which S-ARB already protects against network-wide.

**User-visible consequence: the in-flight TX1 is finalized as a loss on the sender side.** By adopting `poisoned_balance` as the wallet's effective current balance for the heal, the wallet accepts that TX1's amount has been debited. TX1's 2/k-1 cheques remain below the redeemability threshold, so the receiver cannot claim them, but they are not refundable either — the value sits in the FACT chain as a scarred link that the sender may burn to reclaim provenance, but not to recover the funds. This is the documented cost of recovering transactability after a partial witness, and is strictly better than the alternative (a permanently locked wallet).

### 2.1.1 `ok_count == 1` — reactive blacklist recovery (added 2026-04-16)

**Previously** heal-forward required at least 2 poisoned committers (`ok_count >= 2`) to seed the fresh validator's overlap check, so the `ok_count == 1` case was deferred as a known limitation. An adversarial soak (v2.11.15-beta14, 2026-04-16) discovered that this class of partial is actually common under high fork rates: ~50% of chaos-injected partials land in the 1-poisoned case. 38/100 wallets were observed stuck in this state after 5 hours of adversarial traffic.

**The insight**: the `ok_count == 1` case is not really a heal-forward problem at all. It's a *routing* problem. After a 1/k partial:

- 1 validator holds `X_poison` (the one that accepted and committed the partial TX).
- `k−1` validators still hold `X_old` (they weren't consulted, or their responses were lost).
- The wallet's `state_id` is still `X_old` because `send_witness_to_selected` only advances `state_id` when `len(ok_list) >= k`.

So the wallet has `k−1` clean overlap candidates — exactly enough to satisfy S-ABR's `k−1` overlap requirement on the next send. All it needs to do is **route around** the one stale validator. The TX_HEAL machinery (build a self-send, POST /clara, force roll-forward) is overkill for this case; a local client-side blacklist suffices.

**Reactive detection and replacement** (`scripts/pmc.py::MultiValidatorClient::send_witness_to_selected`):

1. Client sends witness request to validator `v`. S-ABR accumulation proceeds serially.
2. If `v` rejects with `E_SABR_HASH_MISMATCH`, that is a cryptographically-authoritative signal: `v` holds a stored state for this wallet that does not match the `consumed_state_id` in the current request. This means `v` is stale relative to the wallet's view.
3. The client appends `v`'s ID to `client.last_reactive_poisoned` and pops a replacement from `backup_pool`, preferring candidates whose ID is in `prev_validator_ids` (free overlap sig). If no overlap-pool candidate is available, any fresh backup will do as long as `accumulated_sigs >= k−1` by the time Lambda processes it.
4. The slot retries inline with the replacement. On success, the slot is recorded normally; on second failure (rare — implies another stale peer happens to be in the backup pool head), the slot falls through to Pass 2 or remains failed and caller handles it via the existing fallback path.
5. After the send returns, caller invokes `wallet.mark_reactively_poisoned(client.last_reactive_poisoned)`, persisting the detected IDs into `wallet.reactive_blacklist`. Future sends auto-exclude these validators via the `blacklist=` parameter on `select_validators`.

**Why this is safe**:

- The protocol path is unchanged. Validators still reject mismatches (correctly). S-ABR still requires `k−1` overlap from prev_receipts (correctly). The only difference is that the client treats `E_SABR_HASH_MISMATCH` as a *routing signal* instead of a fatal error.
- The reactive blacklist is **wallet-local**. Different wallets may see different validators as poisoned, which is correct — stale state is per-(wallet, validator) in Lambda's storage.
- The stranded `X_poison` at the blacklisted validator stays dangling until **tiered bloom GC / cold-state eviction** (see §3). This is consistent with how we design the rest of the tiered memory path: old state is eventually forgotten, without needing active cleanup.
- `clear_clara_after_success()` drops the reactive blacklist after a clean send cycle, so the list doesn't accumulate indefinitely. If the validator is still stale, the next send re-detects it on first touch — with no correctness cost, only one extra round-trip to probe.

**Generalized overlap-math rule**: reactive heal works for **any k ≥ 3** iff `clean_count ≥ sabr_overlap(k)`, where `sabr_overlap(k) = ⌊k/2⌋ + 1` (strict majority; `core/logic/src/wallet_id.rs::sabr_overlap`). Equivalently, `max_tolerated_poisoned = k − sabr_overlap(k)`:

| k | `sabr_overlap(k)` | max poisoned reactive tolerates |
|---|---|---|
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | **2** |

Per-case breakdown:

| Case | Poisoned | Clean | Overlap required | Reactive works? | Path |
|---|---|---|---|---|---|
| **1/3** | 1 | 2 | 2 | ✅ | Reactive replacement |
| **2/3** | 2 | 1 | 2 | ❌ | TX_HEAL (heal-forward) |
| **1/4** | 1 | 3 | 3 | ✅ | Reactive replacement |
| **2/4** | 2 | 2 | 3 | ❌ | TX_HEAL |
| **3/4** | 3 | 1 | 3 | ❌ | TX_HEAL |
| **1/5** | 1 | 4 | 3 | ✅ | Reactive replacement |
| **2/5** | 2 | 3 | 3 | ✅ | Reactive replacement (2 slots) |
| **3/5** | 3 | 2 | 3 | ❌ | TX_HEAL |
| **4/5** | 4 | 1 | 3 | ❌ | TX_HEAL |

**k=5 tolerates two poisoned validators** because strict-majority overlap is 3, not 4. The reactive loop naturally handles this: each `E_SABR_HASH_MISMATCH` rejection triggers one inline replacement, and the loop iterates over all slots — so two sequential rejections get two sequential replacements as long as the backup pool has enough fresh candidates with `accumulated_sigs >= sabr_overlap(k)` at the time they're consulted. The implementation is k-agnostic and needs no k-specific branching.

**Note on the pmc.py select_validators `required_overlap = k - 1` formulation**: for k ∈ {3, 4} this matches `sabr_overlap(k)`, but for k=5 it over-selects (picks 4 overlap when Core only requires 3). This is safe — more overlap than required never breaks anything — but Core's `sabr_overlap(k)` is the authoritative rule for whether overlap is sufficient, and `send_with_reactive_heal` uses the Core rule for the reactive replacement eligibility check.

**S-ABR overlap derived from previous TX's k (v2.11.16, consensus.rs)**: the overlap requirement for a transaction is now derived from the *previous* TX's witness count (`prev_receipts[0].witness_sigs.len()`), not from `effective_k(current_tx)`. Rule: `overlap = sabr_overlap(prev_k)`. This prevents a tier-downgrade double-spend: if TX1 was witnessed at k=5, the next TX requires `sabr_overlap(5) = 3` overlap regardless of whether it targets k=3. After one TX at the lower tier, the chain is back to the lower tier's overlap cost. The extra cost is paid exactly once on downgrade. Example chain: TX1(k=5)->TX2(k=3): overlap=3. TX2(k=3)->TX3(k=5): overlap=2. TX3(k=5)->TX4(k=3): overlap=3. This interacts with the reactive blacklist: the overlap-math table above remains correct for same-tier sends; on a tier downgrade the effective overlap threshold may be higher, which tightens the `max_tolerated_poisoned` bound for that single transition.

**Deferred — reactive CLARA attestation emit (future work)**: the current reactive fix does not notify the poisoned validator that its state is stale; it relies on tiered bloom GC to eventually clean `X_poison` at `v`. A future enhancement would be a lightweight `/clara-reactive` endpoint on Nabla that accepts `{wallet_pk, poisoned_validator_id, garbage_state_id, healed_to_state_id, healing_txid}` without requiring a separate TX_HEAL self-send. Lambda's existing `clara_roll_forward` at CL2 would handle the roll-forward. This would collapse the cleanup delay from hours (tiered memory cold eviction) to seconds (first touch after the attestation propagates). It is not required for correctness — the reactive fix is already complete — but it would reduce stale-state churn. Tracked in `docs/AXIOM_REPORT_FutureWork.md`.

**SDK surface**: clients should call the one-shot wrapper `MultiValidatorClient.send_with_reactive_heal(wallet, payload)` which handles selection + send + reactive blacklist + persistence in a single call. See `AXIOM_GUIDE_Client.md §Reactive heal API` for usage.

The `ok_count == 0` case does not need CLARA — no validator committed, so the wallet's state is unchanged and normal retry or fresh TXs proceed without recovery.

The `ok_count >= 2` case (including the 3-of-3 case where all validators committed but response delivery was lossy) is the design target. Under that path, TX_HEAL reaches k=3 through the heal-forward rule above and the wallet is recovered.

### 2.1.2 SDK boundary rule — clearing CLARA state

`wallet.clear_clara_state()` is the **only** sanctioned way to clear CLARA
bookkeeping (`garbage_state_ids`, `poisoned_committers`, `poisoned_balance`,
`poisoned_wallet_seq`); the fields themselves are `pub(crate)` by design.
Tooling and harness code must never write these attributes directly — the one
end-to-end CLARA recovery failure observed in testing was a harness bypassing
this API, not a protocol fault. Wallet persistence is a single-file canonical
CBOR with `flock`-protected atomic writes (v2.13.00), which structurally
eliminates split-state drift between wallet and receipt records.

### 2.2 `ClaraAttestation` structure

```rust
/// CLARA — Client-Led Attested Reality Alignment.
/// Carries a Nabla-signed proof that a wallet has healed past one or more
/// poisoned states, allowing previously poisoned validators to roll their
/// stored state forward and resume normal witness service.
pub struct ClaraAttestation {
    /// Healing wallet's public key
    pub wallet_pk: [u8; 32],

    /// State the wallet is healing FROM (pre-broken-TX state)
    pub healed_from_state_id: [u8; 32],

    /// State the wallet is healing TO (TX_HEAL produced state)
    pub healed_to_state_id: [u8; 32],

    /// Wallet sequence at heal point (TX_HEAL.wallet_seq)
    pub healed_at_seq: u64,

    /// YPX-018 Phase 5f Finding 4: canonical post-heal balance.
    /// Bound by `BLAKE3(wallet_pk || healed_balance || healed_at_seq) ==
    /// cheque.state_hash` (the cheque is k=3-witnessed). Lambda's
    /// `clara_roll_forward` uses this to refresh the stored balance on
    /// previously poisoned validators — fixes the liveness degradation
    /// where rolled-forward validators stayed at the lower poisoned balance.
    pub healed_balance: u64,

    /// txid of the heal cheque
    pub heal_txid: [u8; 32],

    /// Abandoned states declared garbage by this heal
    pub garbage_state_ids: Vec<[u8; 32]>,

    /// Era and bloom-chain commitment at heal time (for tier resolution)
    pub bloom_era_id: u64,
    pub bloom_era_root: [u8; 32],

    /// TARDIS tick at attestation time (freshness)
    pub nabla_tick: u64,

    /// Attesting Nabla node identity + NBC trust anchor
    pub nabla_node_pk:   [u8; 32],
    pub nabla_signature: Vec<u8>,    // Ed25519 over the canonical message
    pub nbc_issuer_pk:   Vec<u8>,    // root authority SPHINCS+ PK
    pub nbc_signature:   Vec<u8>,    // SPHINCS+ over commitment
    pub nbc_commitment:  Vec<u8>,    // VBC payload binding nabla_node_pk
}
```

**Signature scheme** (Phase 5f Finding 4 added the `healed_balance` suffix):

```
message = BLAKE3(
    "AXIOM_CLARA_ATTEST" ||
    wallet_pk || healed_from_state_id || healed_to_state_id ||
    healed_at_seq.to_le_bytes() || heal_txid ||
    garbage_count.to_le_bytes() || garbage_state_ids[..] ||
    bloom_era_id.to_le_bytes() || bloom_era_root ||
    nabla_tick.to_le_bytes() ||
    healed_balance.to_le_bytes()       // Phase 5f Finding 4
)
signature = Ed25519_sign(nabla_node_sk, message)
```

NBC trust anchor mirrors `NablaTxidAttestation` (§4.6 below) — flat fields, no_std-compatible, verifiable inside the RISC-V guest.

### 2.3 Validator roll-forward rule (CL2 amendment)

A witness request may carry an optional `clara_attestation` field. If present, Core CL2 (or Lambda's pre-Core check) MUST:

1. Verify the Nabla signature on the attestation using the embedded NBC trust anchor.
2. Verify `wallet_pk` matches the witness request's wallet.
3. **Roll-forward eligibility check:** If the validator's stored state for this wallet differs from `request.transaction.consumed_state_id`, the validator's stored `state_id` MUST be **exactly one of** the entries in `clara_attestation.garbage_state_ids`. If the stored state is not in that list AND not equal to `healed_from_state_id`, **reject the attestation** with `E_CLARA_STATE_NOT_GARBAGE`. (No chain walking, no multi-step provenance.)
4. **Roll forward:** replace stored `state_id` with `healed_to_state_id`, stored `wallet_seq` with `healed_at_seq`, and stored `balance` with `healed_balance`. The balance rewrite is load-bearing — without it, `validate_transaction` runs against the poisoned balance and any new TX whose amount exceeds that poisoned balance is rejected, creating a chicken-and-egg reject loop where Lambda never reaches the post-Core `clara_roll_forward` storage commit and the wallet remains permanently stuck. `healed_balance` is already bound into `compute_clara_message` and verified by Nabla's `register_clara` against the heal cheque's signed `state_hash`, so trusting it in the synthetic rewrite introduces no new trust assumption.
5. Proceed to normal witness validation against the rolled-forward state.

If the validator's stored state already matches the request (no poisoning), the `ClaraAttestation` is informational and the validator simply records that this wallet has healed past the listed garbage states and proceeds normally.

**Why no multi-step:** A wallet poisoned at multiple unrelated states must declare *all* of them in `garbage_state_ids` of a single CLARA invocation. The wallet's client knows everywhere it tried to send and which sigs failed, so the wallet can compute every poisoned state locally. Multi-step state walking is forbidden — it complicates verification and offers no functional advantage.

### 2.4 CLARA registration endpoint

**Phase 5f wire format** (current — see §2.4.1 below for the security history):

```
POST /clara
Body: {
    wallet_pk:        [u8; 32],          // healing wallet's Ed25519 PK
    heal_cheque:      ChequeBundle,      // k=3 cheques, each with real
                                         // Ed25519 sig over cheque commitment
    heal_transaction: Transaction,       // the authoritative TX_HEAL
                                         // (is_heal=true, self-send)
    declared_garbage: Vec<[u8; 32]>,     // states being abandoned (≤32)
    healed_balance:   u64,               // post-heal balance — verified by
                                         // Nabla against cheque.state_hash
}
```

Note that `healed_from_state_id` and `healed_at_seq` are **not in the request** —
both are derived authoritatively from `heal_transaction.consumed_state_id` and
`heal_transaction.wallet_seq` after the tx ↔ cheque binding is verified. The
`healed_balance` IS in the request, but Nabla verifies it via `cheque.state_hash`
before signing the attestation, so the validator side trusts a value that has
been independently attested by k=3 fresh validators.

Nabla MUST:

1. Verify the heal cheque has at least 3 cheques in the bundle.
2. Verify bundle internal consistency (matching txid/receiver/amount/epoch and distinct validators).
3. Verify the cheque-level self-send invariant (`cheque.sender_wallet_id == cheque.receiver_wallet_id`).
4. Verify each cheque's `signature` against `cheque.validator_pk` over the canonical cheque commitment.
5. **Phase 5f tx binding:** verify `heal_transaction.is_heal == true`.
6. **Phase 5f tx binding:** verify `heal_transaction` is itself a self-send (`tx.sender_wallet_id == tx.receiver_wallet_id`).
7. **Phase 5f tx binding:** verify `compute_txid(heal_transaction) == cheque.txid` (binds the tx to the bundle).
8. **Phase 5f wallet binding:** verify `heal_transaction.client_pk == request.wallet_pk` (binds wallet_pk to the tx).
9. **Phase 5f wallet binding:** verify `verify_pk_binding(cheque.sender_wallet_id, request.wallet_pk)` (binds wallet_pk to the cheque's wallet_id via YPX-007 pk_bind).
10. Verify `declared_garbage` is non-empty.
11. Derive `heal_txid` and `healed_to_state_id` from the verified cheque.
12. Derive `healed_from_state_id = heal_transaction.consumed_state_id` and `healed_at_seq = heal_transaction.wallet_seq` from the verified tx.
13. Verify `heal_txid` is NOT already in the txid bloom chain (idempotency).
14. Verify `healed_from_state_id` is NOT in either bloom chain (freshness).
15. Verify no `declared_garbage` entry is already-redeemed in the txid bloom chain.
16. Insert `heal_txid` into the active txid bloom era.
17. Insert each entry in `declared_garbage` into the active garbage state bloom era.
18. Construct and sign a `ClaraAttestation` with the NBC trust anchor populated from the node's own NBC.
19. Register `healed_to_state_id` in the SMT as the wallet's current state and trigger gossip propagation. This makes the heal link immediately queryable (unscar) without a separate POST /register.
20. Return the attestation and a `confirmation` object (`root_hash`, `tick`, `node_id`) to the client.

`TX_HEAL` is a self-send transaction with `is_heal=true` (CL1 §11.9.4 exception); CLARA is the protocol that wraps it with Nabla attestation and validator roll-forward semantics.

#### 2.4.1 Security hardening history (Phases 5e + 5f)

The initial Phase 3 implementation accepted multiple classes of caller assertion that the protocol now rejects. They are documented here so that future audits can verify nothing has regressed:

| Issue (era) | Old behavior | Fix |
|---|---|---|
| **C1 — `witness_sig_count` shortcut** (pre-5e) | Request carried a `witness_sig_count: usize` integer; Nabla trusted it without seeing real cheques. Any client could obtain a CLARA attestation by claiming `witness_sig_count = 3`. | **Phase 5e:** request now requires a real `ChequeBundle`. Each cheque's `signature` is verified against its `validator_pk` over the canonical cheque commitment. |
| **C2 — empty NBC trust anchor** (pre-5e) | Nabla node returned a `ClaraAttestation` with empty `nbc_issuer_pk` / `nbc_signature` / `nbc_commitment` fields, and CL2 logged-but-continued. | **Phase 5e:** Nabla node populates the trust-anchor fields from `own_nbc_bytes`. CL2 hard-rejects with `ClaraNbcTrustFailed` on empty/invalid NBC. |
| **C3 — broken `nbc_commitment` window-scan** (pre-5f) | `nbc_commitment` was the BLAKE3 *hash* of the VBC pre-image. The verifier's `windows(32).any(|w| w == nabla_node_pk)` binding check could not work — the hash output is not the pre-image bytes, so the binding check was always trivially false (or trivially true on collisions). | **Phase 5f:** `nbc_commitment` wire format changed to the canonical pre-image bytes (`compute_vbc_signing_payload_bytes`). The verifier recomputes BLAKE3 for the SPHINCS+ check, and the window-scan now actually proves `nabla_node_pk` is bound into the NBC. |
| **C4 — `wallet_pk` not bound to cheque identity** (pre-5f) | `request.wallet_pk` was never compared to anything. The `WalletPkMismatch` error variant existed but was unreachable. An attacker could register a CLARA attestation against any wallet by quoting that wallet's `wallet_id` in the cheques while supplying their own `wallet_pk` in the request. | **Phase 5f:** `request.wallet_pk` is bound to `heal_transaction.client_pk` (cryptographic via `compute_txid`) AND to `cheque.sender_wallet_id` (via YPX-007 `verify_pk_binding`). |
| **C5 — `healed_from_state_id` / `healed_at_seq` caller-asserted** (pre-5f) | Both fields were caller-asserted scalars in the request. A misbehaving client could declare a `healed_from_state_id` that did not match its actual pre-heal state, causing CL2's roll-forward eligibility check to misfire. | **Phase 5f:** request now carries the authoritative `heal_transaction: Transaction`. After step (7) binds the tx to the cheque, both fields are derived from `tx.consumed_state_id` and `tx.wallet_seq` and cannot be overridden. |
| **C6 — Lambda emits cheques with synthetic `sender_wallet_id`** (pre-5f follow-up) | `lambda::consensus::sign_cheque` was building cheques with `sender_wallet_id = format!("sender-{}/00000000", hex(client_pk[..4]))` instead of `transaction.sender_wallet_id`. Real heal cheques would have failed CLARA registration because the synthetic placeholder fails `verify_pk_binding`. | **Phase 5f follow-up:** use `transaction.sender_wallet_id` directly. Regression test in `nabla/src/clara.rs::test_register_clara_rejects_synthetic_sender_wallet_id` proves CLARA refuses pre-fix Lambda cheques. |
| **C7 — CLARA only verifies V2 cheque commitments** (pre-5f follow-up) | `nabla/src/clara.rs::verify_cheque_signature` only computed V2 commitments. Lambda signs V3 (with DMAP hashes) when `dmap_input_hash != 0` — the production case. Real DMAP heal cheques were silently rejected with `InvalidValidatorSignature`. | **Phase 5f follow-up:** mirror Lambda's selector exactly — V3 when DMAP hashes are present, V2 otherwise. Regression test in `test_register_clara_v3_dmap_cheques_verify`. |
| **C8 — `is_heal` flag not bound into client signing message** (pre-5f follow-up) | Lambda could flip the `is_heal` flag on a TX after the client signed, converting a normal self-send (rejected for non-Ark wallets) into an accepted heal — letting an attacker generate arbitrary heal cheques on behalf of any wallet they could forward TXs for. | **Phase 5f follow-up:** `compute_signing_message` appends `b"AXIOM_HEAL_BIND" || 0x01` when `is_heal == true`. Conditional append: non-heal TXs get a byte-identical pre-fix message, so existing wallets and the WASM webclient keep working without rebuild. |
| **C9 — Unbounded `declared_garbage` (DoS)** (pre-5f follow-up) | One valid heal cheque could ship millions of garbage entries, each costing a bloom lookup + insertion under both bloom-chain write locks AND inflating the active era's fill level past its FPR target. | **Phase 5f follow-up:** `MAX_DECLARED_GARBAGE = 32` cap, enforced before any bloom work. New error variant: `TooManyGarbageStates`. |
| **C10 — No per-wallet rate limit on `POST /clara` (DoS)** (pre-5f follow-up) | An attacker could flood `/clara` with verify-then-reject requests using a small set of valid wallets, burning CPU on Ed25519 verification + `compute_txid` + `verify_pk_binding` for each. | **Phase 5f follow-up:** new `ClaraRateLimiter` struct on `NablaNodeState`. Per-`wallet_pk` cap: 3 attempts / hour. Counts attempts (not just successes) so verify-then-reject floods can't bypass it. Runs BEFORE any verify CPU. Periodic prune bounds memory. New error variant: `RateLimited` (HTTP 429). |
| **C11 — Balance not corrected during CLARA roll-forward (Liveness)** (pre-5f follow-up) | A "poisoned" validator's stored balance was wrong (lower than reality) because it processed a partial TX whose debit was never finalized k=3-wide. Without correction, the validator stayed functionally broken — it would reject the wallet's next TX larger than its (lowered) stored balance. | **Phase 5f follow-up:** added `healed_balance: u64` to `ClaraAttestation` and the `POST /clara` request. Nabla recomputes `BLAKE3(wallet_pk \|\| healed_balance \|\| healed_at_seq)` and verifies it equals the heal cheque's `state_hash` (which is k=3-witnessed and signed by each fresh validator). Lambda's `clara_roll_forward` refreshes the stored balance to the verified value. No new trust assumption — every party in the chain has either observed or cryptographically attested to this balance. New error variant: `HealedBalanceMismatch`. |
| **C12 — `sender_wallet_id` not in cheque consistency check** (pre-5f follow-up, defense-in-depth) | `ChequeBundle::verify_consistency` did not check `sender_wallet_id` across cheques (the cheque commitment binds receiver only — design decision per `crypto.rs:144`). For CLARA the authoritative tx-binding closes the exploit, but the consistency check is added as defense-in-depth. | **Phase 5f follow-up:** additive check in `verify_consistency`. No signature change, no hard fork. A future protocol revision can add `sender_wallet_id` to the V4 cheque commitment for full coverage. |

The Phase 5f reject paths are exhaustively unit-tested in `nabla/src/clara.rs::tests` (23 tests) and walked over the HTTP wire format in `tests/test_clara_attack_walks.py` (11 attacks against a live env). Lambda's `clara_roll_forward` balance refresh has a dedicated regression test in `lambda/src/storage.rs::test_clara_roll_forward_refreshes_poisoned_balance`.

### 2.5 Attack walks

**Attack 1: Heal then replay TX1.**

1. Alice does TX1 to Bob (2/3 partial).
2. Alice heals via TX_HEAL. `pre-TX1 state` is now consumed in the txid bloom; `TX1.produced_state_id` is in the garbage bloom.
3. Alice replays TX1 to a fresh V8. V8 has no prior state, accepts at face value, witnesses TX1. Alice now has k=3 sigs on TX1 in artifact form.
4. Alice delivers the now-complete TX1 cheque to Bob.
5. Bob's wallet performs the standard pre-accept Nabla check: "is the consumed_state_id of this cheque (`pre-TX1 state`) still fresh?"
6. Nabla checks: `pre-TX1 state` was consumed by TX_HEAL. **Returns conflict.**
7. Bob refuses. Alice gains nothing.

**Attack 2: Extend the broken chain — TX2′ consuming TX1.produced.**

1. Alice tries to register TX2′ with Nabla.
2. Nabla checks the garbage bloom: `TX1.produced_state_id` is in the garbage bloom.
3. **Nabla rejects TX2′'s registration.** No FACT link is ever created.
4. Even without the garbage bloom, the standard scarred-FACT check (TX2′'s parent TX1 is unknown to Nabla → broken chain → scar) catches it. The garbage bloom is the explicit fast-path defense.

**Attack 3: Replay TX1 BEFORE healing.**

1. Alice replays via V8 without healing. TX1 reaches k=3 in artifact form, Alice delivers to Bob.
2. Bob's pre-accept check: `pre-TX1 state` is fresh (TX_HEAL hasn't happened). Bob accepts.
3. Bob redeems → TX1's FACT link registered with Nabla → `pre-TX1 state` now consumed by TX1.
4. Alice now tries to heal: TX_HEAL also consumes `pre-TX1 state`. **Heal fails** (state already consumed).
5. Alice's wallet is permanently scarred. Single legitimate spend. Alice is the only loser.

**Attack 4: Heal twice from the same state.**

Both TX_HEALs consume `pre-TX1 state`. Standard double-spend detection. First registers; second is rejected.

**Attack 5: Forge a `ClaraAttestation`.**

The attestation's NBC trust anchor requires a SPHINCS+ signature from a root authority key. Without that key, no valid attestation can be forged.

### 2.6 Why no scar to receivers

In every above scenario, receivers are protected by the *existing* pre-accept Nabla check (§17.9 cheque delivery), not by any new mechanism. No receiver carries a "PSP scar" or a "potential scar." The only party who can lose money to attempted double-spend is the attacker themselves (their wallet ends up scarred), or innocent receivers who fail to perform the standard pre-accept Nabla check (already required by protocol).

This is the qualitative win over PSP: **no new receiver liability**.

---

## 3. Tiered Bloom Memory

### 3.1 Architecture

Two storage layers and two node tiers replace the YPX-014 single-bloom design.

**Storage layers:**

1. **Bloom files (time-bucketed).** Each bloom file covers a TARDIS tick range — call it an *era*. The default era duration is **one quarter (90 days)**. Each era has its own bloom file, sized for the expected entry count of that era at a configurable false positive rate.

2. **Bloom Age Index** — a small SMT (or simple KV with merkle commitment) that records `era_id → { start_tick, end_tick, status, era_root }`. The age index is the directory of "which bloom files exist and what eras they cover." Status is one of: `ACTIVE`, `FROZEN`, `SCHEDULED_PHASE_OUT(effective_tick, console_cert_hash)`, `PHASED_OUT(effective_tick, console_cert_hash)`.

**Node tiers:**

1. **Light Nabla node** (citizen with a laptop). Holds the bloom chain only. Storage at planetary scale: a few GB. Can answer the common-case "definitely not in this era" authoritatively.

2. **Archive Nabla node** (volunteer / explorer). Holds the bloom chain *plus* the actual hash records (txids and garbage state_ids with metadata) for some set of eras. Archive nodes are the resolution layer for false positives and the source of cryptographic proofs of inclusion / exclusion.

The **Bloom Age Index** also includes, per era, a list of archive node IDs known to hold that era's full records. When a light node needs archive resolution, it forwards the query to one of the listed archives.

### 3.2 The two bloom chains

Two separate bloom chains share the same time-bucketing structure and the same age index, but track different things:

- **Txid bloom chain** — replaces the YPX-014 single bloom. One bloom file per era, containing every redeemed-and-Nabla-registered txid in that era's tick range.
- **Garbage state bloom chain** — new. One bloom file per era, containing every state_id declared garbage by a heal in that era's tick range.

Both share `BloomEra` metadata in the age index. Both are sharded the same way. Both are subject to the same Console-governed phase-out rules.

### 3.3 BloomEra structure

```rust
pub struct BloomEra {
    pub era_id: u64,                  // monotonic
    pub start_tick: u64,
    pub end_tick: u64,                // start_tick + ERA_DURATION_TICKS
    pub txid_bloom_root: [u8; 32],    // BLAKE3 of txid bloom file at era close
    pub garbage_bloom_root: [u8; 32], // BLAKE3 of garbage bloom file at era close
    pub txid_count: u64,              // exact count for FPR computation
    pub garbage_count: u64,
    pub status: EraStatus,
    pub archive_nodes: Vec<[u8; 32]>, // node_pks known to hold this era's full records
}

pub enum EraStatus {
    Active,                                       // current era, writes accepted
    Frozen,                                       // closed era, immutable
    ScheduledPhaseOut {
        effective_tick: u64,
        console_cert_hash: [u8; 32],
    },
    PhasedOut {
        effective_tick: u64,
        console_cert_hash: [u8; 32],
    },
}
```

### 3.4 Bloom sizing and false-positive math

At era close, the bloom is sized for the actual entry count at the protocol's target FPR. For 90-day eras:

| Entries per era | Per-file FPR target | Bits/entry | File size |
|---|---|---|---|
| 10 M | 10⁻¹² | 57 | ~68 MB |
| 100 M | 10⁻¹² | 57 | ~680 MB |

Across 200 eras (50 years × 4) at 100 M entries each: **~136 GB total** — bounded by entry count, not by time, and trivially shardable across the Nabla mesh.

**Per-file FPR is fixed at era close, not amortized over time.** Era freezing is the structural fix for the YPX-014 saturation bug: once an era is frozen, its bloom file does not accept more entries, so its FPR stays at the design target forever. Larger files (longer eras / higher entry counts) just need proportionally more bits to maintain the same target FPR — not a higher FPR.

**Compounded FPR across the chain.** When a lookup walks N era files, the probability of *any* file producing a false positive is `1 - (1 - p)ᴺ ≈ Np` for small `p`. At p = 10⁻¹² and N = 1000 eras (250 years of quarterly), the compounded FPR is ~10⁻⁹ — about 1 spurious bloom hit per billion queries across the entire history of the protocol.

This means the choice between annual / quarterly / monthly era duration is FPR-invisible. Quarterly is selected for finer phase-out granularity and reasonable active-era memory (~70 MB for an active era at 100 M entries), not because it changes the error rate.

False positives are also recoverable in practice (§3.6) — the user simply queries a different Nabla node — so the FPR bound governs how often the slow path is taken, not whether anyone loses money.

### 3.5 Active-era write path

A new transaction's txid (or a new heal's garbage state) is inserted into the **active era**'s bloom file. The active era is the one whose `[start_tick, end_tick)` range contains the current TARDIS tick. When the current tick crosses `end_tick`:

1. The active era is **frozen**: bloom file is finalized, `txid_bloom_root` and `garbage_bloom_root` are computed, `txid_count` and `garbage_count` are recorded, status is set to `Frozen`.
2. A new era is opened with `era_id = previous + 1`, `start_tick = previous.end_tick`, `end_tick = start_tick + ERA_DURATION_TICKS`.
3. The age index is updated atomically (frozen era's metadata is written; new era's metadata is written; both are gossiped via TARDIS).

### 3.6 Lookup flow

A client (or receiver doing a pre-accept check) queries any Nabla node:

```
GET /query-txid?txid=<hex>
GET /query-garbage-state?state_id=<hex>
```

The node walks the bloom chain in **reverse era order** (newest first, since most queries hit recent eras) and returns one of three signed answers:

1. **`NEGATIVE`** — no bloom hit in any walked era. The txid (or state) is definitively absent. Fast path; single round trip. **>99.9999% of queries.**

2. **`POSITIVE`** — the responding node found the txid in an era's bloom AND has the actual hash record for that era (i.e. it is an archive node for that era). The signed response includes the actual record, so the answer is authoritative.

3. **`PHASED_OUT(effective_tick, console_cert_hash)`** — the era containing this txid has been phased out by Console action. The cheque is irrevocably dead. The signed response references the authorizing certificate so the client can verify.

**If the responding node has a bloom hit but does NOT hold the actual hash record for that era**, it returns `NEGATIVE` (since it cannot answer authoritatively) along with a hint listing archive node IDs known to hold that era. The client retries against an archive. This is the only "two round trip" case in the design and it is purely an optimization detail — there is no separate FP resolution protocol.

**If the bloom hit is genuine, the archive returns `POSITIVE` with the real record. If the bloom hit is a false positive, the archive returns `NEGATIVE` (the actual record is absent) and the client treats the cheque as valid.** Either way the answer comes from the archive's exact hash store, never from a bloom alone.

**False positive UX (rare — ~10⁻⁹ to 10⁻¹² per query):** the user's wallet retries the query against a different Nabla node. Different node, different shard mapping, different active bloom fragment — the false positive almost certainly does not recur. If the user happened to hit the only path that produced the FP, the wallet falls through to an archive node which gives the authoritative answer. **No new protocol mechanism is needed for this case** — it's a one-line documented fallback in the wallet client, not a separate spec component. At a 10⁻⁹ rate the fallback is taken approximately once per billion queries across the history of the protocol.

The signed wire-level answer is always sourced from an exact hash record (archive) or from definitive bloom-chain absence (full chain walk). **Bloom is never the final word for a positive answer.**

### 3.7 Sharding

The Nabla mesh shards bloom files across nodes. The default sharding key is `era_id mod shard_count`. Each shard is replicated to at least 3 nodes. A light node may choose to hold:

- All eras (small at planetary scale: ~tens of GB)
- Only the most recent N eras (the common case for active wallets)
- Only specific shards (if running constrained hardware)

Archive nodes additionally hold the full hash records for the eras they archive. Archive coverage need not be uniform — some eras may have many archives, others few. The protocol requires only that **at least one archive holds each non-phased-out era**. The Console may consider archive coverage when deciding whether to phase out an era.

---

## 4. Console-Governed Phase-Out

### 4.1 Why this is a Console action

The protocol cannot determine on its own when bloom data should be retired. That decision involves:

- Storage burden across the citizen-runnable node fleet
- How many users still hold cheques from old eras
- Archive coverage for the affected eras
- Public notice and grace period

These are exactly the kind of decisions the Console exists to coordinate (YPX-013). A new fourth Console action type, `BLOOM_PHASE_OUT`, fits cleanly alongside the three existing actions (Digit Migration, Self-Dismissal, Core Update Recommendation).

### 4.2 ConsoleAction: BLOOM_PHASE_OUT

```rust
pub struct ConsoleProposal_BloomPhaseOut {
    pub era_ids: Vec<u64>,           // eras to schedule for phase-out
    pub effective_tick: u64,         // when phase-out takes effect
    pub rationale: String,           // human-readable justification
}
```

The proposal is voted on through the existing Console mechanism (§21.10.6 — ACK/OBJECT/WITHDRAW pattern, unanimous within 24h to approve).

### 4.3 Constitutional limits (Core-enforced, not Console-overridable)

These constants live in Core and are validated in CL11 when Core signs the resulting ConsoleCertificate. The Console **cannot** override them — only a new Core ELF (a worldline change, per YPX-013) can.

```rust
/// Minimum age of any era before it may be phased out.
/// 50 years in TARDIS ticks. Set to span a full adult lifetime —
/// anyone who received a cheque as a young adult can still redeem it
/// as an old person, regardless of any Console decision.
pub const MIN_PHASE_OUT_AGE_TICKS: u64 = 50 * TICKS_PER_YEAR;  // 315,576,000

/// Minimum grace period from proposal approval to effective phase-out.
/// 5 years in TARDIS ticks.
pub const MIN_PHASE_OUT_GRACE_TICKS: u64 = 5 * TICKS_PER_YEAR; // 31,557,600
```

**Combined effect:** Any cheque issued in tick T cannot become unreachable before tick T + 50y + 5y = **55 years minimum**, no matter what the Console decides. This is the protocol's constitutional memory floor.

**Why so generous:** The storage math shows there is no pressure to phase out for decades. At planetary scale (100 M txids per quarterly era), per-node bloom growth is ~84 MB/year on a sharded 1000-node mesh with replication factor 3. After 100 years a citizen laptop holds ~8.5 GB total. The constitutional minimum is therefore set by user-rights philosophy, not by storage math: 55 years guarantees that a person who receives a cheque as a young adult can still redeem it in old age, no matter what the protocol's governance decides in the meantime.

The Console can still choose to never phase out anything. The 50/5 floor is a minimum, not a target.

### 4.4 CL11 validation rules for BLOOM_PHASE_OUT

When CL11 verifies a Console action of type `BLOOM_PHASE_OUT`, it MUST check:

1. The proposal is signed by a current Console seat.
2. Unanimous ACK was received within 24h (existing rule).
3. For every `era_id` in the proposal:
   - The era exists in the bloom age index (gossiped via TARDIS).
   - `era.end_tick + MIN_PHASE_OUT_AGE_TICKS <= effective_tick`.
   - The era is not already `PhasedOut` or `ScheduledPhaseOut`.
4. `effective_tick - proposal_proposed_tick >= MIN_PHASE_OUT_GRACE_TICKS`.
5. The proposal's `effective_tick` is in the future relative to the current TARDIS tick.

If all rules pass, Core signs the ConsoleCertificate authorizing the phase-out. The certificate is broadcast via CL10 Fan-Out and recorded permanently in the FACT chain.

### 4.5 Effect of phase-out

On receipt of the signed phase-out certificate, every Nabla node:

1. Updates its bloom age index for the affected eras: `status = ScheduledPhaseOut { effective_tick, console_cert_hash }`.
2. During the grace period (now until `effective_tick`), queries against affected eras return both the answer AND a warning: "this era will be phased out at tick T, redeem any cheques from this era before then."
3. At `effective_tick`, archive nodes are FREE to drop the era's full records. Light nodes are FREE to drop the era's bloom file. The age index entry remains forever, with status updated to `PhasedOut` — so any future query against the era returns a `PHASED_OUT` response with the original ConsoleCertificate as proof.

**Reversibility:** Until `effective_tick`, the Console may pass a subsequent proposal cancelling the phase-out (a `BLOOM_PHASE_OUT_CANCEL` action — Phase 2, not in this spec). After `effective_tick`, archive nodes may have already dropped the data, so cancellation is no longer safe.

### 4.6 NablaTxidAttestation (revised structure)

The existing `NablaTxidAttestation` is extended to include era and bloom-chain commitment fields, so the attestation is verifiable against any era root in the chain:

```rust
pub struct NablaTxidAttestation {
    pub txid: [u8; 32],
    pub status: TxidStatus,        // NotRedeemed | Redeemed | PhasedOut

    // For Redeemed: which era the txid was found in
    pub found_in_era: Option<u64>,
    pub era_root_at_lookup: [u8; 32],

    // For PhasedOut: the authorizing certificate
    pub phase_out_cert: Option<[u8; 32]>,

    pub registered_by: Vec<u8>,    // for hashmap-archive responses
    pub nabla_node_pk: [u8; 32],
    pub nabla_signature: Vec<u8>,
    pub nabla_tick: u64,

    // NBC trust anchor (unchanged from YPX-014)
    pub nbc_issuer_pk:  Vec<u8>,
    pub nbc_signature:  Vec<u8>,
    pub nbc_commitment: Vec<u8>,
}

pub enum TxidStatus {
    NotRedeemed,
    Redeemed,
    PhasedOut,
}
```

The Core CL5 verification rules (§39.9.4) are extended to handle the three-state `TxidStatus` and to recognize `PhasedOut` as an irrecoverable terminal state.

---

## 5. Security Analysis

### 5.1 Threat model

We assume:

- An attacker can run any number of Nabla light nodes.
- An attacker can compromise some Nabla archive nodes.
- An attacker cannot forge SPHINCS+ root-authority signatures (Genesis ceremony assumption).
- An attacker can construct any TX their wallet keys can sign.
- The Console mechanism (YPX-013) is honest in aggregate but individual seats may be compromised.

### 5.2 CLARA invariants

**I-CLARA-1:** A wallet can heal only by self-issuing a `TX_HEAL` with its own valid Ed25519 sig. No third party can force or fake a CLARA invocation on a wallet they do not control.

**I-CLARA-2:** A `ClaraAttestation` validates exactly one wallet's state transition. The `wallet_pk` is bound into the signed message. Replay across wallets is impossible.

**I-CLARA-3:** A poisoned validator only ever rolls *forward* on a `ClaraAttestation`. Rolling backward is never permitted.

**I-CLARA-4:** A wallet cannot heal off a state that has already been consumed by a registered FACT link. Nabla rejects the CLARA registration. (Defends against Attack 3 — replay then heal.)

**I-CLARA-5:** Garbage states declared by CLARA cannot be used as inputs to future TXs. Nabla rejects registration of any TX consuming a garbage state. (Defends against Attack 2 — extending the broken chain.)

### 5.3 Tiered bloom invariants

**I-BLOOM-1:** A bloom hit is *never* an authoritative answer. All bloom hits must be resolved against an archive node holding the actual hash record. (Defends against false positives causing user fund loss.)

**I-BLOOM-2:** A bloom MISS is authoritative *for the era walked*. If every era in the chain returns a bloom miss, the txid was never registered (or is in a future era).

**I-BLOOM-3:** Era `bloom_era_root` is fixed at era close. New entries cannot be added to a frozen era. This prevents an attacker from "back-dating" a registration into an old era.

**I-BLOOM-4:** Era close is gossiped via TARDIS like any other Nabla event. All honest nodes converge on the same era boundaries.

### 5.4 Phase-out invariants (constitutional)

**I-PHASE-1:** No era may be phased out until at least `MIN_PHASE_OUT_AGE_TICKS` (30 years) after its `end_tick`. Hard rule in CL11.

**I-PHASE-2:** Phase-out requires at least `MIN_PHASE_OUT_GRACE_TICKS` (5 years) of grace between proposal approval and `effective_tick`. Hard rule in CL11.

**I-PHASE-3:** Phase-out requires unanimous Console ACK. Existing Console rule (§21.10.6).

**I-PHASE-4:** A phased-out era's age-index entry persists forever. Phase-out is a marker, not a deletion of the record that the era existed.

**I-PHASE-5:** A phased-out era's `console_cert_hash` is permanently auditable via the FACT chain. Anyone in 2076 can see exactly when an era was phased out and by whose decision.

### 5.5 Combined: cheque lifetime guarantee

**Lifetime guarantee:** A cheque issued in tick T can be redeemed at any time `t` where:

- `t >= T` (it's been issued)
- `t >= T + maturity_ticks` (any time-lock has elapsed)
- The era containing T is not `PhasedOut`

The Console's constitutional limits guarantee that the third condition cannot become true before `T + 35 years`. Therefore **every cheque has a guaranteed minimum 35-year redemption window**, independent of any Console action.

If no Console action is ever taken, eras remain `Frozen` indefinitely and cheques remain redeemable forever. Phase-out is opt-in for the protocol, not automatic.

---

## 6. What this supersedes

### 6.1 YPX-014 (Nabla Txid Service)

YPX-014 specified a single 18 MB bloom per Nabla node, with optional hashmap mode for opt-in archive nodes. This spec replaces it with the tiered bloom architecture (§3) — same wire-level pattern (client fetches signed attestation, Lambda verifies via Core CL5), but durable for the protocol's full lifetime.

The `NablaTxidAttestation` structure is extended (§4.6) — strict superset of YPX-014's fields, with new era / phase-out fields. Old YPX-014 attestations cannot be used (the version field bumps), but no on-network data needs migration because **AXIOM has not released yet**.

### 6.2 YPX-016 (Witness Response Cache) — kept in place

YPX-016 cached the witness response per wallet so that retry-the-same-TX would not require Core re-execution. This solved one of the two pieces of the 2/3 partial problem (retry) but did NOT solve the other (move-on to a new TX).

CLARA (§2) is the answer for the move-on case. **YPX-016 itself is NOT removed.** It remains in Lambda as a performance optimization for the common case where a network hiccup causes a same-TX resend before any CLARA invocation is attempted. Its security analysis (YPX-016 §3) is unchanged. Its `witness_cache` SQLite table, code paths, and tests stay exactly as implemented.

What changes is YPX-016's *role*: it is no longer load-bearing for protocol correctness in the partial-witness recovery story. CLARA covers correctness; the cache covers fast-path performance. Both stay.

### 6.3 PSP, two-phase commit, tick-bounded sigs

These were design alternatives discussed and rejected. They are not in any prior spec; this section records that they are *not* the chosen approach so future readers don't re-invent them.

---

## 7. Implementation references

Implementation file scope, test plan, and rollout order are in:

`docs/AXIOM_HEAL_BLOOM_IMPLEMENTATION.md` (separate document)

Yellow Paper sections updated by this YPX:

- **§17.10.14** (NEW) — CLARA normative spec
- **§21.10.6 Task 4** (NEW) — BLOOM_PHASE_OUT Console action
- **§26.17.7** (NEW) — CLARA's relationship to existing FACT/scar mechanisms
- **§39.8.1** — Add `nabla_garbage_state_bloom` row
- **§39.9** (REWRITE) — Replace YPX-014 description with tiered bloom architecture
- **§3 / CL mode notes** — CL2 accepts and verifies `ClaraAttestation`
- **Version history** — v2.11.15 entry

YPX-013 sections updated:

- **§1.2 Constants** — Add `MIN_PHASE_OUT_AGE_TICKS`, `MIN_PHASE_OUT_GRACE_TICKS`
- **§5 Console Operations** — Add §5.5 BLOOM_PHASE_OUT
- **§6.2 CL11 Validation Rules** — Extend with phase-out validation
- **§8.1 Fan-Out Content Types** — Add `FANOUT_CONSOLE_BLOOM_PHASE_OUT`
- **§10 Implementation Plan** — Add Phase 7 (Console BLOOM_PHASE_OUT integration)

---

## 8. Decisions and open items

### 8.1 Decisions (made during design)

1. **Era duration: 90 days (quarterly).** Active-era memory ~70 MB at 100 M entries; quarterly gives 4× finer phase-out granularity than annual without meaningful overhead. Settled.

2. **Garbage bloom enforcement: strict reject.** Any TX that consumes a state in the garbage bloom is rejected at Nabla registration with no soft-scar fallback. The wallet can re-heal if it ends up in an unexpected garbage state. Settled.

3. **Validator roll-forward: single-step only.** A wallet poisoned at multiple states must declare all garbage states in one heal. No multi-step provenance walking. Settled.

4. **Constitutional limits: 50-year minimum age + 5-year minimum grace = 55-year cheque lifetime guarantee.** Set by user-rights philosophy, not storage math. Settled.

5. **Witness Response Cache (YPX-016): kept as-is.** It works as a same-TX retry optimization. The heal protocol supersedes its load-bearing role for protocol correctness, but the cache stays in Lambda as a performance optimization for the common-case retry-after-network-blip scenario. Do not break what works.

### 8.2 Open items (defer to implementation or follow-up)

1. **Archive node incentives for old eras.** The CC scoring for archive nodes (5× multiplier from YPX-014) carries over. Whether old eras (queried less, more storage-expensive) need additional incentives can be decided after observing real network economics.

2. **Phase-out cancellation action.** A `BLOOM_PHASE_OUT_CANCEL` Console action would let the Console reverse a scheduled phase-out before the effective tick. Useful but not load-bearing — can be added in a follow-up YPX if needed.

3. **Heal frequency rate-limiting.** Per-wallet rate limit at Nabla (e.g., one heal per wallet per hour, configurable) to prevent heal-spam DoS. Implementation detail, not protocol.

---

## 9. References

- YPX-013 Console Engine — `docs/AXIOM_YPX-013_CONSOLE_ENGINE.md`
- YPX-014 (superseded) — `docs/AXIOM_YPX-014_TXID_SERVICE.md`
- YPX-015 §2.9 State_id security analysis — `docs/AXIOM_YPX-015_STATE_ID_ANALYSIS.md`
- YPX-016 (superseded) — `docs/AXIOM_YPX-016_WITNESS_RESPONSE_CACHE.md`
- Yellow Paper §17.9 Cheque delivery & pre-accept Nabla check
- Yellow Paper §17.10 S-ABR
- Yellow Paper §26.17 FACT chain
- Yellow Paper §39.8 Lambda database
- Yellow Paper §39.9 Global double-redeem prevention
- Soak test v2 evidence — `tests/soak_test_v2.py`

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
