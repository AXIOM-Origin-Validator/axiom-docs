# AXIOM YPX-007 — Receiver-Defined Security Level & Multi-Address Wallet
**Version:** 0.4
**Status:** Implemented
**Date:** 2026-03-11
**Author:** AXIOM Origin  
**Depends on:** Yellow Paper v2.10, YPX-006 (DMAP)  
**Replaces:** v0.3

---

## 0. Summary of Change

This amendment introduces two protocol changes:

1. **Each wallet has 7 pre-generated wallet_ids.** All 7 are created at wallet creation time from the same `(email, WALLET_IDENTITY_KEY, salt)` triple. All 7 share the same master account, balance, and FACT chain. `k` and `proof_type` are baked into the checksum — Core extracts them during validation with zero external calls. The receiver presents whichever ID they want for a given transaction. The sender cannot alter the security level — Core extracts it from the address, not from any sender-controlled field.

2. **ZKP qualification is operator-driven and time-bounded.** A validator self-qualifies as a `zkvm` provider by asking Core to run a timed proof on a random input. Qualification expires on Core restart or after TTL. Core enforces at service time — rejects ZKP requests if unqualified regardless of advertisement.

---

## 1. Design Reversal — The Fundamental Change

**This amendment reverses a core design assumption. This is the primary reason the entire YPX exists. This thought process must never be removed from this document.**

### 1.1 The Original Design

In the original AXIOM design, the sender chose the security level. The sender decided how many validators to use and what proof type to require. The receiver communicated their preference out-of-band — verbally, by message, by agreement — but that preference had no protocol enforcement. The sender could ignore it, misremember it, or deliberately choose otherwise.

### 1.2 The Problem the Original Design Could Not Solve

Consider this scenario under the original design:

- Receiver tells sender: *"Please use AAA+ for this payment"*
- Sender constructs the transaction using Standard instead
- Validators process it — Standard is a perfectly valid security level
- Transaction completes
- Receiver rejects the payment — wrong security level, will not release goods
- **Sender cannot cancel. Receiver cannot claim. Money is gone.**

This is an unresolvable dispute. The transaction is valid from the protocol's perspective. The money has left the sender's wallet. The receiver has not received anything they are willing to accept. Nobody can recover the funds.

Who is responsible? The protocol cannot answer. The security requirement lived outside the transaction — in a verbal instruction, a side agreement, a message. Nothing in the protocol recorded what was agreed. Nothing can prove what the receiver asked for or what the sender chose. The dispute is permanent and unresolvable.

**This is not an edge case. This is a fundamental structural flaw.** Any system where the security requirement exists outside the transaction itself will always produce this failure mode.

### 1.3 The New Design — Security IS the Address

**This amendment closes that failure mode permanently by making the security requirement inseparable from the destination address.**

The receiver has 7 wallet addresses. Each address encodes a specific security level inside its checksum. The security level is not a verbal instruction. It is not metadata. It is not a separate field the sender fills in. It is mathematically bound to the address itself.

When the receiver shares their AAA+ address, the security requirement travels with the address. The sender sends to that address. Core processes the transaction at AAA+ — not because the sender chose it, not because the receiver asked for it, but because the address itself encodes it. There is nothing for the sender to override, ignore, or misremember.

**Every one of the 7 addresses is a legitimate destination. Core never rejects a valid wallet_id.** Core honestly processes whatever valid address it receives at the security level that address encodes. A transaction sent to the Standard address is processed at Standard. A transaction sent to the AAA+ address is processed at AAA+. No exceptions. No negotiation.

### 1.4 Responsibility Is Now Always Traceable

Under the new design, the lost-money scenario cannot happen. Money always arrives — at whatever security level the destination address encodes. The only question is: *which address was used, and who chose it?*

- **Receiver shares AAA+ address, sender sends to AAA+ address** → processed at k=5/Z → receiver's requirement honoured
- **Receiver shares AAA+ address, sender sends to Standard address instead** → processed at k=3/D → money arrives → sender's fault for using a different address than given
- **Receiver shares wrong address by mistake** → processed at that address's security level → money arrives → receiver's fault for sharing the wrong address

In every case, money arrives. In every case, responsibility is traceable to the party who chose which address to use. There is no ambiguity, no limbo, no unresolvable dispute.

This is the core social and contractual insight of the design: **when the security requirement is inseparable from the address, the act of sharing an address is itself a binding commitment.** The receiver who shares their Standard address for a high-value transaction has made a choice. The sender who sends to a different address than the one given has made a choice. Both choices are recorded in the transaction. Both are attributable. Both carry consequences.

---

## 2. Wallet_ID Checksum — Extended Format

### 2.1 Current Format

```
wallet_id: "email / CCCCCC SS"
             email   ^^^^^^ ^^
                     checksum  salt (2 hex)

checksum = BLAKE3(email || WALLET_IDENTITY_KEY || salt)[0..3].to_hex()
```

`WALLET_IDENTITY_KEY` is a protocol-wide constant compiled into core-logic. No per-user key. No external lookup ever needed.

### 2.2 Extended Format

`k` and `proof_type` are added as additional hash inputs:

```
checksum = BLAKE3(email || WALLET_IDENTITY_KEY || salt || k_byte || proof_type_byte)[0..3].to_hex()
```

Where:
- `k_byte` — single byte: `0x00` (ark), `0x03`, `0x04`, or `0x05`
- `proof_type_byte` — single byte: `0x00` = zkvm, `0x01` = dmap, `0x02` = ark
  *(Matches existing wire protocol: `ProofType::Zkp = 0`, `ProofType::Dmap = 1` in `core/avm/src/dmap/mod.rs`)*

The same `email`, `WALLET_IDENTITY_KEY`, and `salt` produce **7 completely different checksums** — one per `(k, proof_type)` combination. The checksums look random and unrelated. The only visible link between them is the shared salt suffix.

### 2.3 Encoding Table

| Wallet Name | k | proof_type | k_byte | proof_type_byte |
|---|---|---|---|---|
| Ark         | 0 | — | `0x00` | `0x02` |
| Standard    | 3 | dmap | `0x03` | `0x01` |
| A+          | 3 | zkvm | `0x03` | `0x00` |
| Secure      | 4 | dmap | `0x04` | `0x01` |
| Secure+     | 4 | zkvm | `0x04` | `0x00` |
| AAA         | 5 | dmap | `0x05` | `0x01` |
| AAA+        | 5 | zkvm | `0x05` | `0x00` |

`k=0` is the natural encoding for Ark — zero validators, zero proof. No special case needed anywhere. Core decodes `k=0` → ark path. `k=3/4/5` → normal transaction path.

### 2.4 Example — Same Wallet, 7 Addresses

Salt chosen once at wallet creation: `7f`

```
Ark:      alice@example.com / 7b4e91 7f   ← BLAKE3(... || 0x00 || 0x02)
Standard: alice@example.com / a3f7b2 7f   ← BLAKE3(... || 0x03 || 0x01)
A+:       alice@example.com / 9d21c8 7f   ← BLAKE3(... || 0x03 || 0x00)
Secure:   alice@example.com / 4fe103 7f   ← BLAKE3(... || 0x04 || 0x01)
Secure+:  alice@example.com / b72a90 7f   ← BLAKE3(... || 0x04 || 0x00)
AAA:      alice@example.com / 1c8d45 7f   ← BLAKE3(... || 0x05 || 0x01)
AAA+:     alice@example.com / e6f312 7f   ← BLAKE3(... || 0x05 || 0x00)
```

All 7 checksums look completely different. Salt `7f` is the only visible link — sufficient to prove they belong to the same wallet. This is intentional and acceptable — AXIOM does not hide wallet linkage.

### 2.5 Backwards Compatibility

The existing Standard wallet_id (generated before this amendment as `BLAKE3(email || MASTER_PK || salt)`) is deprecated at next wallet renewal. All wallets re-issued under the new scheme. No migration path — wallet renewal generates all 7 fresh.

---

## 3. Wallet Creation

### 3.0 Why All 7 Are Generated at Once — Closing the Responsibility Gap

**This is a deliberate design decision about responsibility. The thought process here is the reason for the entire mechanism and must not be removed.**

The responsibility model in §1.4 only works if one condition holds: **the receiver cannot claim they did not have the right address available.**

If high-security addresses had to be explicitly created on demand — navigating a menu, generating a new ID, taking extra steps — a receiver could always argue: *"I did not have my AAA+ address ready at the time."* Or: *"I did not know I needed to generate one."* That argument, whether genuine or not, introduces ambiguity into the responsibility chain. The receiver's choice to share a lower-security address becomes blurred with the possibility that a higher-security address simply was not available.

That ambiguity must not exist. The entire responsibility model depends on the receiver's choice being unambiguously a choice — not a limitation.

**Generating all 7 addresses at wallet creation removes that ambiguity permanently.**

From the moment a wallet exists, every security level is available to its owner. There is no action required to unlock AAA+. There is no step to take to get a Secure+ address. All 7 exist. The receiver who shares their Standard address for a large transaction made a conscious choice from a full set of options. That is unambiguous.

This also means the receiver's responsibility is fixed at the moment of sharing. When a receiver hands a sender their AAA+ address, they have committed to requiring AAA+ for that transaction. When they hand over Standard, they have committed to accepting Standard. The commitment is immediate, irrevocable, and fully attributable — because the full range of choices was available to them at that moment.

**The social contract this creates:**

Every wallet holder in the AXIOM network knows, from the first day they create a wallet, that they have 7 receiving addresses. They know what each one means. They know that sharing an address is a binding choice. There is no learning curve, no upgrade path, no situation where higher security is unavailable. The responsibility for which address gets shared belongs entirely and permanently to the receiver — with no exceptions and no excuses.

At wallet creation, PMC generates all 7 IDs in one shot from a single randomly chosen salt:

```python
salt = random_hex(1)   # 2 hex chars, e.g. "7f"

PARAMS = [
    (0x00, 0x02, "Ark"),       # k=0, proof_type=ark(2)
    (0x03, 0x01, "Standard"),  # k=3, proof_type=dmap(1)
    (0x03, 0x00, "A+"),        # k=3, proof_type=zkp(0)
    (0x04, 0x01, "Secure"),    # k=4, proof_type=dmap(1)
    (0x04, 0x00, "Secure+"),   # k=4, proof_type=zkp(0)
    (0x05, 0x01, "AAA"),       # k=5, proof_type=dmap(1)
    (0x05, 0x00, "AAA+"),      # k=5, proof_type=zkp(0)
]

wallet_ids = {}
for k_byte, pt_byte, name in PARAMS:
    checksum = blake3(email || MASTER_PK || salt || k_byte || pt_byte)[0:3].hex()
    wallet_ids[name] = f"{email}/{checksum}{salt}"
```

All 7 stored in the wallet record. Never regenerated unless the wallet is re-issued.

### 3.1 Wallet UI Display

```
My Wallet — alice@example.com
Balance: L$ 1,234.56

  [Ark]      alice@example.com / 7b4e91 7f   offline / survival mode
  [Standard] alice@example.com / a3f7b2 7f   everyday payments
  [A+]       alice@example.com / 9d21c8 7f
  [Secure]   alice@example.com / 4fe103 7f
  [Secure+]  alice@example.com / b72a90 7f
  [AAA]      alice@example.com / 1c8d45 7f
  [AAA+]     alice@example.com / e6f312 7f   large / high-value transactions
```

Names (`Ark`, `Standard`, `A+`, `Secure`, `Secure+`, `AAA`, `AAA+`) are UX display labels only. They never appear in wire messages, Yellow Paper, or Rust source outside of display strings.

---

## 4. Core Validation — Extraction, Not Verification

When Core receives a TX with wallet_id `alice@example.com / e6f312 7f`:

1. Parse: email = `alice@example.com`, checksum = `e6f312`, salt = `7f`
2. Try all 7 `(k_byte, proof_type_byte)` combinations:
   ```
   for (k_byte, pt_byte) in [(0,2), (3,1), (3,0), (4,1), (4,0), (5,1), (5,0)]:
       candidate = BLAKE3(email || MASTER_PK || salt || k_byte || pt_byte)[0..3].to_hex()
       if candidate == checksum:
           return (k_byte, pt_byte)   # found it
   ```
3. Exactly one combination matches → `k=5, proof_type=zkvm` extracted. Proceed.
4. No combination matches → `E_INVALID_WALLET_ID`. Reject immediately. Sender's state_id not consumed.

**The sender does not choose the security level. Core extracts it from the address.**

The sender receives an address, feeds it to Core, and Core tells them what security level that address requires. There is no field for the sender to fill in, no parameter to override, no way to downgrade. The address IS the instruction.

**No external calls. No Nabla lookup. No network. Pure math.** 7 BLAKE3 hashes is trivial (~1μs total).

`WALLET_IDENTITY_KEY` is already compiled into Core. Salt is in the wallet_id. Everything needed is in the address itself.

### 4.1 The decoder must NEVER panic on hostile input (DoS hardening, 2026-06-14)

A wallet_id reaching the parser is **attacker-controlled** — most importantly a
`receiver_wallet_id` carried inside a TX. The decode functions in
`core/logic/src/wallet_id.rs` (`parse_wallet_id`, `extract_security_level`,
`strip_email_change_suffix`, `strip_encryption_suffix`) MUST therefore fail closed
(`Err`/`None`), never unwind. A panic inside Core on a crafted address is a denial-of-service
on every node that decodes it.

Original bug (`2f264053`): `strip_email_change_suffix` sliced the last **3 bytes**
(`&s[s.len()-3..]`) guarded only by a byte-length check. A wallet_id ending in a multi-byte
UTF-8 character (e.g. a 4-byte emoji) made `len-3` land mid-character → `"byte index N is not a
char boundary"` panic. (`-XX` suffixes and ASCII tails happen to land on boundaries, so it was
intermittent — but any 4-byte tail reliably crashed Core. Repro:
`extract_security_level("🙂@x.com/🙂")`.)

Rule, enforced by `decoders_never_panic_on_hostile_input`:
- guard every `&str` byte index that depends on input length with `is_char_boundary`, or operate
  on `char_indices()` / `str::get(..)` (returns `None` off-boundary) — never raw `&s[i..]`;
- a valid `-XX` change-suffix is exactly 3 ASCII bytes, so a non-boundary tail simply isn't a
  suffix → return `(s, None)`;
- malformed/hostile input → `Err`/`None`, never a panic.

Note this is a CONSENSUS_CRITICAL file (compiled into the Core ELF): the fix is behavior-neutral
for all valid wallet_ids but rotates the CoreID.

---

## 5. Sender Cannot Downgrade — By Construction

There is no downgrade attack because **the sender never chooses the security level.**

Sender receives `AAA+` address (`e6f312 7f`). Sender feeds this address to Core. Core extracts `k=5, proof_type=zkvm` from the checksum. The sender's PMC must now recruit 5 zkvm-capable validators. There is no field to change, no parameter to override.

If the sender wants to pay less, they must ask the receiver for a different address. The receiver decides. That is the entire point.

---

## 6. Transaction Struct Changes

**File:** `core/logic/src/types.rs`
Add to `Transaction`:

```rust
pub required_k:    u8,   // 0, 3, 4, or 5 — Core-filled from wallet_id extraction
pub proof_type:    u8,   // 0 = zkvm, 1 = dmap, 2 = ark — Core-filled from wallet_id extraction
```

**These fields are written by Core, not by the sender.** When Core first processes a TX, it calls `extract_security_level(receiver_wallet_id)` to derive `(k, proof_type)` from the checksum, then fills these fields into the TX struct. From that point on, the values are available to the entire pipeline without re-computation.

**Why store them:**
- **S-ABR overlap:** The next transaction's overlap check needs to know the *previous* TX's `k` to enforce the `k-1` overlap rule. If `k` varies per transaction (different receivers = different addresses = different k), it must be persisted in the TX record.
- **Efficiency:** Extract once from the checksum (7 BLAKE3 hashes), use everywhere. No re-derivation needed by Lambda, Nabla, or audit.

**The sender never sets these fields.** The sender's PMC calls `extract_security_level()` on the receiver's address to learn what the address requires (so it knows how many validators to recruit), but the TX struct fields are always written by Core during validation. If a sender somehow pre-fills them with wrong values, Core overwrites them with the correct extraction result.

**File:** `core/logic/src/wallet_id.rs`
Add:

```rust
/// Extract (k, proof_type) from a wallet_id by trying all 7 combinations.
/// Returns None if no combination matches (invalid wallet_id).
pub fn extract_security_level(wallet_id: &str) -> CoreResult<(u8, u8)>
```

Core calls this during CL2/CL3 validation. The returned `(k, proof_type)` is written into the TX and governs the rest of the transaction pipeline.

---

## 7. Lambda: Variable k Receipt Threshold

**File:** `lambda/src/consensus.rs`
Replace hardcoded `k=3` receipt threshold with `tx.required_k` (Core-filled from wallet_id extraction).

**Current TX:** Lambda uses `tx.required_k` as the receipt threshold — how many validator signatures are needed before the TX is considered complete.

**S-ABR overlap for next TX:** When processing TX N+1, Lambda reads TX N's `required_k` from the stored TX record. The overlap rule is **strict majority**: more than 50% of TX N's validators must also witness TX N+1. This prevents double-spending — an attacker cannot present a conflicting TX to a fresh set of validators.

| TX N's k | Overlap required | Formula |
|---|---|---|
| k=3 | 2 | floor(3/2) + 1 |
| k=4 | 3 | floor(4/2) + 1 |
| k=5 | 3 | floor(5/2) + 1 |

Since `k` varies per transaction (different receivers → different addresses → different k), the previous TX's `required_k` must come from the persisted record, not re-derived.

`k=0` (Ark) → Lambda routes to Ark handler (behavior defined in future Ark YPX, not this document).

---

## 8. SDK Validator Selection — proof_cap-Aware

### 8.1 Discovery field

Every `ValidatorHint` (peer discovery + seed file) carries a
`proof_cap: String` field — either `"dmap"` (default for all
validators) or `"zkvm"` (operator opted-in and Core-qualified
per §9).

**File:** `core/logic/src/types.rs` — `ValidatorHint.proof_cap`.
**File:** `sdk/core/src/app.rs` — `validators.list` 6-column
seed format carries `proof_cap` as column 4.
**File:** `lambda/src/storage.rs` — `validator_hints` DB
schema column `proof_cap TEXT NOT NULL DEFAULT 'dmap'`.

```rust
pub struct StoredValidatorHint {
    pub validator_id: String,
    pub name:         String,
    pub carriers:     Vec<String>,
    pub proof_cap:    String,    // "dmap" or "zkvm"
    pub last_seen:    u64,
    pub stored_at:    u64,
}
```

### 8.2 Selector behavior

`sdk/core/src/send.rs::select_validators` partitions the
available pool by `proof_cap` and applies one of two rules
depending on the receiver's tier extracted via
`extract_security_level(receiver_wallet_id)`:

- **Receiver tier requires ZKP** (`A+`, `Secure+`, `AAA+`):
  hard-filter. Only validators with `proof_cap == "zkvm"`
  are eligible. Validators advertising `dmap` are dropped
  from the pool entirely for this send.

- **Receiver tier requires DMAP** (`Standard`, `Secure`,
  `AAA`, `Ark`): soft-preference. ZKP-capable validators are
  picked first; DMAP-only validators fill the remainder only
  if the ZKP-capable pool can't satisfy `k`. The S-ABR
  overlap algorithm (`sabr_overlap(prev_k)` from prev_set)
  runs on the ordered pool unchanged.

### 8.3 Why ZKP-preferred even for DMAP sends

ZKP-capable validators can produce both proof types. DMAP-only
validators can only produce DMAP. By always picking
ZKP-capable first, a wallet's prior witness set accrues
ZKP-capable `validator_ids` over time. When the wallet later
sends to a ZKP-tier receiver, the S-ABR overlap requirement
is naturally satisfied by validators that already witnessed
the prior (DMAP) send — no tier-transition friction.

The cost to DMAP-only validators is a self-imposed soft
demotion in the selector's pick order. Operators who want
witness traffic deploy ZKP capability.

### 8.4 Economic rationale — market-driven capability supply

The protocol deliberately does not mandate ZKP support. Every
validator is allowed to ship as DMAP-only. The selector's
soft-preference (§8.2) is the only mechanism pushing
operators toward ZKP, and the push is purely a function of
demand.

This is intentional. Two opposite market regimes both work
without protocol changes:

- **Low ZKP demand.** If users rarely send to ZKP-tier
  addresses (most economic activity at
  Standard/Secure/AAA levels), ZKP-capable validators see
  no fee uplift. There is no business case to invest in
  zkVM hardware (GPU rigs, STARK prover pipelines). The
  network self-equilibrates with mostly DMAP-only
  validators. Cost to participants: zero — the
  high-security tiers are still available for the rare
  user who needs them (via §10's force-through), and
  DMAP works the way DMAP has always worked. No
  economic distortion from unused capacity.

- **High ZKP demand.** If users routinely send at ZKP-tier
  (banking-grade, treasury, compliance-driven flows),
  ZKP-capable validators capture more witness traffic AND
  can command a higher fee (operators set `fee_rate_bps`
  per-validator; ZKP-capable validators can price for the
  premium service). DMAP-only validators see their share
  of the market shrink. New operators entering the
  network deploy ZKP from day one to compete. Existing
  DMAP-only operators invest in GPU to retain their fee
  revenue. Supply rises to match demand without any
  protocol mandate.

The protocol's job is to make the choice cheap to express
(one column in `validators.list`, one byte in the receiver's
wallet_id checksum, one selector preference rule) and let the
market signal flow naturally. ZKP is a premium service tier,
priced by the validators who offer it, requested by the users
who need it. Neither side is forced into the trade.

### 8.5 The §10 force-through is the safety valve

Without §10, a user sending to a ZKP-tier address whose prior
overlap pool happens to lack ZKP-capable validators would be
locked out — they couldn't send until natural rotation
refreshed their validator set, which might not happen on any
predictable timeframe. The force-through preserves user
liveness while keeping the market signal intact: validators
who don't want the latency hit qualify for ZKP; those who
don't lose nothing immediately but slowly lose witness share
as wallets rotate.

In a healthy network the force-through almost never fires —
§8.3 keeps the prior set ZKP-rich. When it does fire it's a
clear UX signal ("your wallet's prior validators don't
support zkVM") that the user can route around (ask receiver
for a lower-tier address) without protocol intervention.

### 8.6 Bootstrap

For the first send (no `prev_validator_ids`), the genesis
branch of `select_validators` picks `k` from the
ZKP-preferred ordering with no overlap constraint. A wallet
that never escalates beyond DMAP-tier sees no functional
difference; one that eventually escalates does so without
needing a separate upgrade flow.

---

## 9. ZKP Qualification

### 9.1 Design

Every validator defaults to `dmap`. ZKP qualification is:

- **Operator-initiated** — CLI or dashboard
- **Random input** — Core generates the benchmark input via internal CSPRNG. Lambda cannot supply a fixed constant and reuse it — Core decides what to prove, preventing precomputation attacks.
- **Time-bounded** — expires after `ZKP_QUAL_TTL_SECS` or on Core restart
- **Core-enforced** — Core checks its own qualification state during TX validation. If the receiver's address requires ZKP and Core is not qualified, Core rejects immediately. Lambda never sees the TX.

### 9.2 Qualification Test

1. Operator triggers qualification via `axiom-dash` or CLI
2. Lambda passes qualification request to Core
3. Core generates random benchmark input internally (CSPRNG) — Lambda has no control over what input is used
4. Core records `challenge_issued_at` timestamp, returns random input to Lambda
5. Lambda runs `ZkvmProver::prove_checkpoint()` on Core's random input
6. Lambda returns the **actual STARK proof (receipt)** to Core — not elapsed time
7. Core records `proof_received_at` timestamp
8. Core **verifies the STARK proof** against the random input it generated — must be a valid proof over exactly that input
9. Core computes `elapsed = proof_received_at - challenge_issued_at` (Core's own measurement)
10. Valid proof AND elapsed ≤ `ZKP_QUAL_THRESHOLD_SECS` (5s) → `zkp_qualified = true`
11. Invalid proof OR elapsed > 5s → `zkp_qualified = false`

**Why Core verifies the proof, not just the time:**
- Lambda cannot fake the proof — STARK verification catches invalid proofs
- Lambda cannot precompute — Core generates fresh random input each time
- Lambda cannot lie about timing — Core measures the round-trip itself
- Lambda cannot replay an old proof — the random input changes every qualification attempt

The split is deliberate: Core generates the challenge, verifies the proof, measures the time, and decides qualification (sole authority). Lambda's only role is running the prover hardware (because `ZkvmProver` requires Tokio/GPU, not available inside core-logic's `no_std` environment).

### 9.3 Qualification State

Lives in Core (core-logic), not Lambda:

```rust
struct QualificationState {
    zkp_qualified: bool,
    qualified_at:  Option<u64>,   // Unix timestamp (Core uses u64 time, not Instant)
    qual_ttl_secs: u64,           // default 86400
}

impl QualificationState {
    fn is_valid(&self, current_time: u64) -> bool {
        self.zkp_qualified &&
        self.qualified_at
            .map(|t| current_time.saturating_sub(t) < self.qual_ttl_secs)
            .unwrap_or(false)
    }
}
```

Resets to `false` on every Core startup (fresh AVM instance = unqualified).

### 9.4 Qualification Flow

```
Operator → axiom-dash → Lambda → Core: "QualifyZkp request"
                                  Core: generates random input, records start_time
                         Lambda ← Core: returns random input (challenge)
                         Lambda: runs ZkvmProver on challenge → STARK receipt
                         Lambda → Core: returns STARK receipt (proof)
                                  Core: records end_time
                                  Core: verifies STARK proof against challenge
                                  Core: elapsed = end_time - start_time
                                  Core: valid proof AND elapsed ≤ 5s → qualified
                         Lambda ← Core: QualifyZkpResult { qualified, elapsed_ms }
```

**File:** `core/logic/src/types.rs` — `QualificationState`, `QualifyZkpRequest`, `QualifyZkpResult`
**File:** `lambda/src/consensus.rs` — orchestrates the benchmark flow (passes request to Core, runs prover, reports back)
**File:** `scripts/axiom-dash.py` — "Qualify ZKP" button

### 9.5 Enforcement in Core

During TX validation, after Core extracts `(k, proof_type)` from the receiver's wallet_id (§4):

```rust
// Inside Core validation (CL2/CL3), after extract_security_level()
if proof_type == PROOF_TYPE_ZKP {
    if !self.qualification_state.is_valid(current_time) {
        return Err(ValidationError::ZkpNotQualified);
    }
}
```

Core rejects before any witness work begins. The TX is not processed. Sender's state_id is not consumed.

### 9.6 Operator Responsibility

Advertising `proof_cap: "zkvm"` without qualification → Core rejects ZKP requests → validator loses fees. Market enforces. No protocol penalty.

---

## 10. Tier-Upgrade Sends — When Prior Overlap Lacks ZKP

### 10.1 The case

A wallet sends to a receiver whose address is a ZKP-tier
(`A+` / `Secure+` / `AAA+`), but the wallet's `last_receipt`
witness set contains fewer than `sabr_overlap(prev_k)`
validators with `proof_cap == "zkvm"`. The selector cannot
satisfy the overlap requirement with ZKP-capable validators
alone.

This is rare in steady state — §8.3's "ZKP-preferred always"
rule keeps the prior set ZKP-rich by default — but it does
happen when:

- A wallet's prior sends were all DMAP-tier and ZKP-capable
  validators were not in the available pool at that time.
- The network's ZKP-capable population shrank between sends
  (operator un-qualified, validator went offline).
- A fresh wallet whose first-ever send is ZKP-tier may also
  hit this if the seed list has few ZKP-capable entries.

### 10.2 SDK behavior

The SDK performs a pre-flight check before building the
witness round:

```rust
fn check_zkp_tier_overlap(wallet, receiver_id) -> Option<TierWarning>
```

If the receiver's tier requires ZKP and the prior overlap
pool has fewer than `sabr_overlap(prev_k)` ZKP-capable
validators, the SDK returns a `TierWarning` to the host
application. It does NOT proceed with the send autonomously.

### 10.3 Host UI behavior

The host application (Mac wallet, web client) presents the
warning to the user with two messages:

> *"This transaction will be significantly slower because
> one or more of your prior witnessing validators does not
> advertise zkVM support."*

> *"You may want to ask the receiver to provide a slightly
> lower-security address (e.g. their `Secure` address
> instead of `Secure+`) to avoid the latency cost."*

The user has two paths:

- **Cancel** — abort the send. No state change. Ask the
  receiver for a lower-tier address out-of-band, or wait
  until the wallet's prior set rotates to include
  ZKP-capable validators.
- **Proceed anyway** — the SDK builds the witness request
  normally and ships it to the prior validator set. The
  request asks each validator to produce a ZKP proof.

### 10.4 Validator behavior on a force-through

The witness request reaches each prior validator. Core's
existing §9 qualification gate applies:

- Validator advertised `dmap` but `zkp_qualified == true`
  (operator chose to advertise dmap for selection-preference
  reasons but IS qualified to prove ZKP): Core produces the
  ZKP proof. Slow — see YPX-006 §1 for the latency baseline
  (~200 s CPU / ~4 s GPU per witness vs ~10-50 ms DMAP) —
  but valid. Witness returns a signed receipt.

- Validator advertised `dmap` and `zkp_qualified == false`
  (operator has not run the qualification benchmark or it
  expired per §9.3): Core rejects the request with
  `ValidationError::ZkpNotQualified`. That validator drops
  out of the witness round. If the remaining quorum is
  insufficient, the wallet's send fails with a real error
  (`E_INSUFFICIENT_WITNESSES`). The user was warned this
  could happen.

### 10.5 Why no automatic recovery flow

A "tier-upgrade-heal" flow (SDK auto-runs a self-send to
refresh the validator set before retrying) was considered
and rejected. Rationale:

- Adds a new authenticated automated state mutation that an
  attacker could trigger or time against — every new step
  in an automated multi-step flow is a new attack surface.
- The §8.3 selector preference already drives the wallet's
  prior set toward ZKP-capable validators in steady state.
  The rare case in §10.1 is genuinely rare.
- Latency is a UX concern, not a protocol concern. The
  proper place to surface it is the wallet UI; the proper
  authority to decide whether to wait is the user.
- The receiver always has a lower-tier address available
  (every wallet has all 7 addresses by §3.0); asking the
  receiver to use it is a one-message out-of-band
  resolution with zero protocol latency.

### 10.6 Cross-tier overlap remains S-ABR-correct

The force-through model does not relax S-ABR's double-spend
protection. The `k` validators producing the new (ZKP)
witness sigs MUST still include `sabr_overlap(prev_k)` of
the validators who witnessed the prior TX — that's still the
rotation gate. The only relaxation is the proof TYPE: prior
witnesses re-sign for the new TX with a ZKP proof rather
than (or in addition to) a DMAP attestation. They cannot
fork because they sign exactly once for the new TX's
`commitment_hash`, regardless of which proof type they
produce.

---

## 11. Ark Wallet ID — Reserved, Not Yet Implemented

The Ark wallet_id is generated at wallet creation using `k=0x00, proof_type=0x02`. The encoding is natural — zero validators, ark proof type.

**Ark behavior is defined in YPX-010** (Ark Mode ⟠ Confidence Index). Core types (`ArkArtifact`, `ConfidenceIndex`) in `core/logic/src/ark.rs`. Ark addresses accepted — sending TO Ark wallet loads it via k=3. Offline ⟠-to-⟠ trading with DMAP both sides, CI for risk assessment. Ref: White Paper §6.9, YP §11.5, YPX-010. 

When Core encounters `k=0` in a TX:
- Route to Ark handler
- Ark handler accepts the TX (k=0 loading path) — see YPX-010

The wallet_id is generated and stored now so existing wallets are already Ark-ready when the Ark YPX lands. No wallet re-issuance needed at that point.

---

## 12. What Does NOT Change

- **S-ABR** — overlap rule generalised to strict majority: `floor(k/2) + 1` validators from TX N must witness TX N+1 (k=3→2, k=4→3, k=5→3). Prevents double-spend with >50% overlap. See §7.
- **FACT chain structure** — unchanged.
- **Payment string format** — still bare `wallet_id`. No suffix. No security code in the string.
- **VBC / NBC ceremony** — `proof_cap` is runtime state, not ceremony-time.
- **Wire protocol** — CBOR frame format unchanged. `QualifyZkp` is Lambda-internal (no IPC needed).
- **Genesis validators** — k=5 always satisfiable (10 genesis validators from day one).
- **Marketing names** — `Standard/A+/Secure/Secure+/AAA/AAA+/Ark` are UX labels only. Never in Yellow Paper, wire protocol, or Rust source outside display strings.

---

## 13. Constants

```rust
// k encoding
pub const K_ARK:     u8 = 0;
pub const K_MIN:     u8 = 3;
pub const K_DEFAULT: u8 = 3;
pub const K_MAX:     u8 = 5;

// proof_type encoding (matches existing ProofType enum in core/avm/src/dmap/mod.rs)
pub const PROOF_TYPE_ZKP:  u8 = 0;   // ProofType::Zkp
pub const PROOF_TYPE_DMAP: u8 = 1;   // ProofType::Dmap
pub const PROOF_TYPE_ARK:  u8 = 2;   // Ark (no proof)

// ZKP qualification
pub const ZKP_QUAL_THRESHOLD_SECS: u64 = 5;
pub const ZKP_QUAL_TTL_SECS:       u64 = 86_400;  // 24 hours
```

---

## 14. Mandatory Enforcement

**auth_hash is mandatory for all wallets with `wallet_seq > 0`.** Transactions from
established wallets without `auth_hash` set are rejected by Core with
`ValidationError::AuthHashRequired` at CL1 and CL2 (`core/logic/src/modes.rs`).

The enforcement threshold is `owner_proof_required_epoch` in
`core/logic/protocol_core.toml` (currently `0` — enforced from genesis). It is a
consensus-critical parameter: changing it requires recompiling Core.

**Migration path:** wallets created before this policy was enforced can set
`auth_hash` by submitting a CL6 key rotation transaction. The wallet owner calls
`derive_owner_pubkey(secret)` and includes the result in the rotation payload.

**Deferred surfaces** (designs specified in §8 and §10; not yet implemented): the
SDK validator-selector proof-capability preference (§8), the tier-upgrade
pre-flight warning sheet (§10), and operator tooling (proof_cap in stored hints,
multi-ID wallet display).

---

## 15. Open Questions

- **`ZKP_QUAL_TTL_SECS`** — 24h default. Operator-configurable in `lambda.toml`?
- **Mid-transaction expiry** — qualification expires between first and last validator. Recommendation: hard-reject. Silent dmap fallback means receiver gets less than they asked for without knowing.
- **Ark YPX** — future document. Triggered when Yellow Paper §6.9 is sufficiently detailed for implementation.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
