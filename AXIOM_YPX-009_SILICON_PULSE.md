# YPX-009: Silicon Pulse — Core-Initiated Lambda Audit Protocol

**Version:** 0.6.2
**Status:** §1-11 Implemented (Ignition TX + Argon2id→BLAKE3 audit chain + persistent AVM). §12 Implemented (Nabla WAL audit). §23.14 self-audit spec complete, implementing. **Production activation is gated to multi-host deployment (KI#31)** — audit-demand constants in the Yellow Paper are dev/testnet placeholders until then; the code paths ship but the pulse is not switched on for a single-host network.
**Author:** AXIOM Origin
**Date:** 2026-03-16
**Depends on:** YPX-003 (TARDIS), YPX-002 (NBC/VBC), YPX-006 (DMAP), Yellow Paper §23.13 (NBC lifecycle)

---

## 0. Lineage

This spec descends from **AXIOM v1.5.1 Identity Protocol** (Hardware-Bound Identity &
TARDIS-Locked Succession). That document explored two approaches to binding node identity
to physical hardware: **NBC-T** (TEE/enclave attestation) and **TARDIS-locked liveness**.
Section 2 of that document deprecated NBC-T for AXIOM; this spec formalizes and extends
the surviving approach (Section 3) into a production-ready protocol.

The design evolved through three iterations:

- **v0.1**: Argon2id memory-hard proof-of-work. Rejected — meaningless computation
  that depreciates with hardware. See Appendix C.
- **v0.2**: DMAP self-audit batch. Rejected — Nabla doesn't have transaction data,
  and putting a TX buffer in AVM memory poisons DMAP checkpoints.
- **v0.3**: Dual-region AVM memory + Core-initiated Lambda audit.
  Core accumulates TX digests in a DMAP-exempt storage region, then challenges Lambda
  to re-execute a random subset. Every cycle is meaningful work. Nothing is wasted.
- **v0.3.1**: Nabla WAL audit hardened. Added deep scan for old WAL sections,
  peer cross-verification, and active StatePull protocol for recovery after downtime
  or corruption. Closes two gaps: old corruption detection and missed gossip recovery.
- **v0.3.2**: Client-signed state records. Replaced validator provenance
  commitment (BLAKE3 hash over public data — recomputable, unfixable) with wallet
  owner's Ed25519 signature (unforgeable without private key). Added RangeSync for
  bilateral gap-fill, tick monotonicity, and "never overwrite valid signed records"
  rule. Security analysis: all 3 critical findings resolved.
- **v0.3.3**: Reframed threat model. Primary threat is dishonest behaviour
  (data pollution, collusion, state tampering) — not Sybil quantity. The integrity
  audit is the point; Sybil defense is a natural side effect. Reviewed against
  external memory-hard puzzle proposal and confirmed: purpose-built puzzles solve
  the wrong problem for AXIOM. Sequential PoW resists parallelisation but does not
  detect dishonesty. Core-initiated audit does both.
- **v0.4.0**: Security audit revealed AVM is stateless between TX
  executions — dual-region memory design (§3) is architecturally impossible.
  Replaced with Lambda-held buffer + Core-verified accumulator chain passed
  through PublicInputs/PublicOutputs. Dropped nonce challenges (Core cannot
  access wallet state at tick boundaries); replaced with time-based fallback
  trigger. Defined epoch as global constant. Documented self-attested PulseProofs
  with two-layer defense (DMAP + Silicon Pulse). Added §23.14 coexistence note,
  `SIGNATURE_REQUIRED_FROM_TICK` cutoff, fixed-point W3 scoring, RangeSync
  peer blacklisting. Resolves 9 of 14 audit findings.
  See `docs/AXIOM_YPX-009_SECURITY_AUDIT.md` for full audit trail.
- **v0.4.1**: §12 (Nabla WAL audit + client-signed state records + StatePull/RangeSync) fully
  implemented in production Nabla code. 445 lib tests + 26 bin tests pass. Chaos tests:
  WAL corruption recovery, concurrent writes during corruption, peer re-sync convergence.
  §1-11 (Lambda accumulator pass-through) remains draft — pending implementation.
- **v0.5.0 (current)**: Architectural correction — Lambda-held buffer replaced with
  **AVM-held buffer**. The v0.4.0 design was flawed: Lambda holds the buffer → Lambda
  can read its own stored outputs → Lambda pre-computes audit responses without
  re-execution → audit is meaningless. The fix: the `AvmInterpreter` struct persists
  across TX executions (it already holds `pending_audit` for §23.14). The audit buffer
  lives inside this struct — Lambda cannot access it. Nonce challenges restored: all
  three v0.4.0 blockers (tick-boundary access, wallet count divergence, canonical
  ordering) are solved by AVM-persistent wallet state cache. TxDigest captures
  financial/state integrity fields only (balances, state_id, amount) — DMAP has
  its own independent verification path. See §3 for complete redesign.

- **v0.6.0**: Three major additions:
  1. **Ignition TX**: Core blocked at startup until Lambda sends a TX through the full
     pipeline (Core processes → ZKVM proof → proof back to Core). Core measures its own
     round-trip time. Same mechanism is the restart penalty — pulse audit failure →
     Core self-terminates → restart requires new ignition TX (seconds to minutes of
     operational downtime). Behind `pulse-gate` cargo feature for dev/test flexibility.
  2. **Argon2id→BLAKE3 audit chain**: Each TX accumulation does Argon2id(32MB,t=1) then
     BLAKE3 chain. Memory-hard work per TX creates real resource contention — 2 validators
     sharing one machine = 64MB active simultaneously → memory bus contention. The Argon2id
     output feeds into the BLAKE3 chain; skip it → chain hash diverges → DMAP catches it.
  3. **Linear audit_cap scaling**: Tiers (0-3) replaced with continuous formula.
  - **Two benchmarks at ignition**: (a) ZKVM round-trip (determines ZKP qualification),
    (b) Argon2id throughput (informational only — audit trigger is protocol-constant).
    Both measured by Core, not Lambda.
  - **Persistent AVM in CoreClient**: `Arc<AvmInterpreter>` persists across all TX
    executions. Required for audit buffer, wallet cache, and ignition state.
  - **Nabla unaffected**: Nabla doesn't call `execute()` for registrations/gossip/WAL,
    so the ignition gate naturally blocks only Lambda TX processing.

- **v0.6.2 (current)**: Audit trigger and sample sizing redesign.
  - **Dual trigger**: TIME (every 5 minutes) + COUNT (buffer at 80% of 2000). Replaces
    hardware-scaled `audit_cap = argon2id_per_sec × PULSE_CAP_FACTOR`.
  - **Proportional sampling**: `sample_size = max(1, buffer.len() × 0.10)`. Replaces
    fixed `PULSE_AUDIT_SAMPLE_SIZE`. Scales with buffer contents — low traffic (50 TXs)
    samples 5, high traffic (1600 entries) samples 160.
  - **Argon2id m_cost = 32MB**: Must exceed L3 cache (16-48MB) to force main memory
    access. 1MB (old value) fits entirely in L3 → zero contention detection.
  - **Removed**: `PULSE_CAP_FACTOR`, `PULSE_AUDIT_SAMPLE_SIZE`, `PULSE_AUDIT_CAP`,
    `PULSE_MIN_AUDIT_CAP`, `PULSE_MAX_AUDIT_CAP`. All replaced by fixed buffer limits
    and protocol-constant triggers.
  - **Why dual trigger**: Time trigger catches low-traffic validators (even 1 TX/hour
    gets audited). Count trigger prevents buffer overflow. Both are protocol constants
    — no hardware-dependent scaling of trigger points.

The original v1.5.1 NBC-T reasoning is preserved in Appendix A.

---

## 1. Problem Statement

AXIOM's current Sybil defenses are **economic and social**:

| Defense | What it stops | What it doesn't stop |
|---------|---------------|----------------------|
| 10,000 AXC genesis threshold | Broke attackers | Well-funded attackers |
| 3-MV-set VBC approval | Random strangers | Colluding validators |
| NBC 48h issuer maturity | Instant NBC farms | Patient attackers |
| NBC TX budget (50K) | Infinite NBC abuse | Multiple NBCs |
| W1/W2 CC scoring | Free-riders | Attacker with real uptime |
| SPHINCS+ ceremony cost | Trivial spawning | One ceremony per VM |

**The primary gap:** Nothing verifies that Lambda is honest. Core validates individual
transactions, but nobody audits whether Lambda actually executed all of them correctly,
in order, with the right wallet states. A compromised Lambda could skip validation,
feed altered state, or silently drop transactions. A small group of colluding validators
could pollute the network with fabricated data, tampered wallet balances, or corrupted
gossip — and no mechanism catches them after the fact. The threat is not quantity of
nodes. The threat is **quality of behaviour** — a single dishonest node (or a small
colluding group) doing real damage to data integrity.

**The secondary gap:** Nothing prevents a single physical machine (or a cloud account
with 100 VPSes) from running many Nabla/Lambda instances, each with its own legitimate
NBC. The attacker pays real economic costs per instance, but those costs are
**per-identity**, not **per-physical-device**. A $20/month 64GB VPS could host 30+
Nabla nodes simultaneously.

Silicon Pulse closes both gaps with one mechanism: **Core audits Lambda**, and the
audit cost naturally discourages multi-node farming as a side effect. The integrity
audit is the point. The Sybil defense is emergent.

### 1.1 Threat Model: The Dishonest Operator

**Primary threat — data pollution and collusion:**

A validator operator (or a small colluding group) acts maliciously:

1. Modifies the Core ELF to skip expensive validation checks.
2. Feeds altered wallet states to Core (inflated balances, fabricated state IDs).
3. Drops or reorders transactions to favour specific wallets.
4. Colludes with other validators to produce k=3 receipts for fabricated transactions.
5. Injects corrupted records into the gossip mesh, polluting honest nodes' state.

Without Silicon Pulse, none of this is detectable after the fact. Core validates
each transaction in isolation but nobody audits whether Lambda presented the right
inputs or stored the right outputs. A dishonest Lambda passes every individual
check while systematically corrupting the ledger.

**Secondary threat — cheap Sybil farming:**

An attacker provisions N virtual machines, each running `nabla-node` + `lambda`
with legitimate credentials. Cost: ~$5-20/month per VPS × N nodes. With Silicon
Pulse, each node's Core independently audits its Lambda, requiring heavy AVM
re-execution every audit cycle. Running N nodes on one machine means N independent
audit cycles competing for the same CPU cores within the same time window.

### 1.2 Design Goals

1. **Core audits Lambda.** Core is the trusted authority. Lambda is the untrusted
   executor being verified. This is the primary function — catch dishonest behaviour,
   data pollution, and state tampering. Aligns with "Core is the sole cryptographic
   authority."
2. **No wasted computation.** Every cycle is a real integrity audit of Lambda's work.
   AXIOM does not burn resources for the sake of burning resources. Purpose-built
   puzzles (memory-hard sequential hashing, PoW-style proofs) solve the wrong problem
   — they resist parallelisation but do not detect dishonesty.
3. **No external dependencies.** No TPM, no TEE, no attestation services, no CAs.
   Survives network blackouts.
4. **Raspberry Pi viable.** A Pi 4 (4GB RAM) must comfortably complete audits.
5. **No new key management.** Uses existing Ed25519 key (NBC-bound).
6. **Sybil defense as side effect.** The audit is expensive enough that a second node
   on the same hardware degrades both nodes' ability to complete audits within the
   deadline. This is a natural consequence of real work, not an artificial puzzle.

---

## 2. Design Philosophy

### 2.1 No Proof-of-Waste

AXIOM is built on social science, game theory, and meaningful participation. A protocol
that forces every node to burn gigabytes of RAM computing hashes that serve no purpose
is antithetical to this. Bitcoin burns electricity on SHA256 to achieve consensus.
AXIOM already has consensus (k=3 S-ABR + TARDIS). Adding proof-of-waste on top is
importing a foreign philosophy. See Appendix C for the full Argon2id rejection reasoning.

### 2.2 The Audit Asymmetry

The protocol exploits a fundamental asymmetry:

- **Core accumulates with purpose.** During normal TX processing, Core folds a digest
  of each transaction through Argon2id(32MB)→BLAKE3. Cost: ~55ms per TX (release mode).
  This is intentionally expensive — the memory-hard Argon2id forces main memory access,
  creating contention when multiple validators share hardware. The accumulation IS the
  contention detection mechanism.

- **Lambda re-derives expensively.** When audited, Lambda must re-execute each selected
  transaction through the full AVM/Core pipeline — loading wallet states from DB,
  running the RISC-V interpreter, producing results including the Argon2id→BLAKE3
  chain. Cost: ~55ms per entry for the chain replay alone.

Core accumulates on every TX. Lambda replays a 10% sample on audit. The audit is
cheap to demand (Core already has the expected hash) and expensive to satisfy
(Lambda must re-execute and re-derive the chain). This is the correct direction —
the trusted party (Core) sets the challenge, the untrusted party (Lambda) does the work.

### 2.3 Dual Purpose (Integrity First)

Silicon Pulse serves two functions, but they are not equal:

1. **Integrity audit (primary).** Core verifies that Lambda processed transactions
   correctly. Catches: database corruption, modified Core ELF, tampered wallet states,
   skipped or reordered transactions, colluding validators feeding fabricated data.
   This is why Silicon Pulse exists. A single dishonest node polluting data is a far
   greater threat than a hundred honest Sybils — honest Sybils do real work for the
   network; a dishonest operator destroys trust.

2. **Sybil defense (emergent).** The audit is expensive enough that running N nodes on
   shared hardware causes CPU contention. Each Lambda instance must independently
   satisfy its own Core's audit challenge. The work cannot be shared between identities.
   This is a welcome side effect, not the design objective.

Neither function is artificial. The audit is needed for integrity. The cost is
an inherent property of re-execution. The Sybil defense emerges naturally from
real work. Purpose-built puzzles (memory-hard sequential hashing, cache-thrashing
algorithms) would add Sybil resistance without adding integrity verification —
they solve the wrong problem for AXIOM.

---

## 3. AVM-Held Audit Buffer

### 3.1 Design History and Correction

**v0.3–v0.3.3:** Proposed dual-region AVM memory (RISC-V address space). Rejected —
the RISC-V executor is fresh per TX, address space is 16 MB not 4 GiB.

**v0.4.0:** Moved buffer to Lambda, Core controls accumulator via PublicInputs/Outputs
pass-through. **Flawed** — Lambda holds the buffer, Lambda receives PublicOutputs
containing all TxDigest fields (`produced_state_id`, `new_balance`, `txid`). Lambda
can reconstruct any digest from stored outputs. Lambda pre-computes audit responses
without re-executing. The audit verifies Lambda's consistency with itself, not its
honesty.

**v0.5.0 (current):** The `AvmInterpreter` Rust struct persists across TX executions.
It already holds `pending_audit: Mutex<Option<PendingAudit>>` for §23.14. The audit
buffer lives here — inside the AVM host code, invisible to Lambda.

### 3.2 The Solution: AVM-Held Buffer with DMAP Spot-Check

```
┌──────────────────────────────────────────────────────────────┐
│ Lambda                                                        │
│                                                               │
│  Calls interpreter.execute(inputs) → receives PublicOutputs   │
│  CANNOT access interpreter internals (Rust encapsulation)     │
│  Receives AuditRequest in PublicOutputs (on time/count trigger)│
│  Must re-execute selected TXs through AVM to respond          │
│                                                               │
│  On AuditRequest:                                             │
│    Look up TXs by tx_number from transaction_db               │
│    Re-execute each through interpreter.execute()              │
│    Pass AuditResponse in next PublicInputs                    │
└──────────────────────────────────┬───────────────────────────┘
                                   │ execute() / PublicOutputs
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│ AvmInterpreter (persistent across TX executions)              │
│                                                               │
│  bytecode: Vec<u8>                    ← Core ELF              │
│  pending_audit: Mutex<PendingAudit>   ← §23.14 (existing)    │
│  audit_buffer: Mutex<AuditBuffer>     ← NEW: Silicon Pulse   │
│  wallet_cache: Mutex<WalletCache>     ← NEW: nonce state     │
│                                                               │
│  After each execute() returning Accept:                       │
│    1. Core (guest) validates TX → PublicOutputs               │
│    2. AVM host computes TxDigest from outputs (financial/state)│
│    3. Argon2id(32MB, salt=accumulator, pw=digest) → BLAKE3    │
│    4. AVM host chains result into accumulator                 │
│    5. AVM host caches wallet state for nonces                 │
│    6. If time >= 5 min or count >= 80% of buffer max:        │
│       Attach AuditRequest to PublicOutputs                    │
│    7. Generate NonceChallenge from wallet cache               │
│       Attach to PublicOutputs                                 │
│                                                               │
│  Lambda sees: PublicOutputs + AuditRequest + NonceChallenge   │
│  Lambda does NOT see: buffer contents, accumulator, cache     │
└──────────────────────────────────────────────────────────────┘
```

**Why Lambda cannot cheat:**

| Attack | Defense |
|--------|---------|
| Read buffer contents | Rust struct encapsulation — no public accessor. Modified AVM binary → DMAP catches. |
| Tamper with stored DB data | §23.14 self-audit: Core demands raw DB data, hashes it, compares against audit buffer entry. |
| Pre-compute audit response | Lambda doesn't know which TXs will be selected (accumulator hidden). |
| Feed wrong wallet state during original TX | Nonce challenges verify current DB state against AVM's wallet cache. |
| Modify AVM to expose buffer | DMAP re-execution by peer validators detects modified binary. |
| Skip Argon2id accumulation | Chain hash diverges → DMAP re-execution catches it (§6.3). |

### 3.3 AVM Struct Changes

```rust
pub struct AvmInterpreter {
    bytecode: Vec<u8>,
    runtime_fingerprint: [u8; 32],
    pending_audit: Mutex<Option<PendingAudit>>,     // existing §23.14

    // ── Silicon Pulse (NEW) ──
    /// Audit buffer — ring of TxDigests with BLAKE3 accumulator chain.
    /// Lambda cannot access this. Only AuditRequest/AuditResponse cross the boundary.
    audit_buffer: Mutex<AuditBuffer>,

    /// Wallet state cache — remembers produced_state_id and balance for
    /// wallets processed. Used for nonce challenges.
    wallet_cache: Mutex<WalletCache>,
}
```

### 3.4 TxDigest — Financial/State Integrity Fields

```rust
struct TxDigest {
    tx_number: u64,                     // transaction sequence number
    sender_balance: u64,                // sender balance at time of TX
    receiver_balance: u64,              // receiver balance at time of TX
    state_id: [u8; 32],                 // produced state_id (SHA3-256)
    amount: u64,                        // transaction amount
}
```

TxDigest captures the **financial and state fields** that Core computed and Lambda
stored. These are exactly the fields Lambda could tamper with in its database:
balances, state IDs, amounts. DMAP is a separate verification mechanism with its
own independent verification path (re-execution comparison, Merkle proofs,
Fiat-Shamir challenges) — mixing it into the audit chain would couple two
independent security layers and break ZKP-mode validators that don't use DMAP.

**Self-audit verification (§23.14 self-target):** When Core demands audit of its
own validator, Lambda looks up the trigger TX in its database and sends back the
raw stored fields. Core hashes them and compares against the entry in the audit
buffer. Lambda does zero crypto — just a DB lookup. Core does all hashing.
See §10.6 for the complete self-audit flow.

### 3.5 Audit Buffer

```rust
struct AuditBuffer {
    entries: Vec<TxDigest>,             // up to PULSE_BUFFER_MAX (2000) entries
    accumulator: [u8; 32],             // BLAKE3 chain over all entries
    count: u32,                         // entries accumulated
    last_audit_time: u64,              // Unix time when last audit completed
}

impl AuditBuffer {
    fn accumulate(&mut self, digest: TxDigest) {
        // Phase 1: Argon2id (memory-hard contention detection, §6.3)
        let argon2_output = Argon2id(
            salt = self.accumulator,
            password = digest.to_bytes(),       // all TxDigest fields
            m_cost = 32MB, t_cost = 1, p_cost = 1  // must exceed L3 cache
        );
        // Phase 2: BLAKE3 chain
        self.accumulator = BLAKE3("AXIOM_AUDIT_CHAIN" || self.accumulator || argon2_output);
        self.entries.push(digest);
        self.count += 1;
    }
}
```

**Cost per TX:** One Argon2id(32MB) (~55ms in release) + one BLAKE3 hash (~300ns).
The Argon2id is the intentional cost — memory-hard contention detection (§6.3).
At 55ms/call, a single validator sustains ~18 TX/sec. Two validators on the same
machine = 64MB active simultaneously → memory bus contention degrades both.

Each entry is ~56 bytes (u64 × 3 + [u8; 32]). At `PULSE_BUFFER_MAX = 2000`: ~112 KB.
Negligible.

### 3.6 Nonce Challenges (Restored)

v0.4.0 dropped nonce challenges due to three blockers. With AVM-persistent state,
all three are solved:

| Blocker (v0.4.0) | Solution (v0.5.0) |
|-------------------|-------------------|
| Core can't query wallet state at tick boundaries | Nonces piggyback on each TX — AVM generates challenge in PublicOutputs, Lambda responds in next PublicInputs |
| `known_wallet_count` diverges | AVM maintains its own wallet cache — doesn't use Lambda's count |
| No canonical wallet ordering | AVM's cache IS the canonical ordering — AVM tells Lambda WHICH wallet_pk to look up |

**Wallet cache:** After each successful TX, the AVM host stores:
```rust
struct WalletCacheEntry {
    wallet_pk: [u8; 32],
    produced_state_id: [u8; 32],
    balance: u64,
    last_seen_tx: u64,
}

struct WalletCache {
    entries: HashMap<[u8; 32], WalletCacheEntry>,  // keyed by wallet_pk
    insertion_order: Vec<[u8; 32]>,                 // for deterministic indexing
}
```

**Nonce flow (every TX):**

```
After TX N completes (Accept):
  1. AVM stores wallet state in cache
  2. AVM picks random wallet from cache:
     nonce_seed = BLAKE3("AXIOM_NONCE_SELECT" || txid || accumulator)
     wallet_index = u64_from(nonce_seed[0..8]) % cache.len()
     target_wallet = cache.insertion_order[wallet_index]
  3. AVM emits NonceChallenge in PublicOutputs:
     { target_wallet_pk, expected_state_id (from cache) }
  4. AVM does NOT emit expected_balance (Lambda can't verify without it)

On TX N+1:
  5. Lambda passes NonceResponse in PublicInputs:
     { target_wallet_pk, current_state_id, current_balance }
     (Lambda looks up wallet in its DB to answer)
  6. AVM compares:
     - current_state_id must match cache.expected_state_id
       → exact match: update cache to new state (Core-verified)
     - OR current_balance >= cached.balance (wallet had more TXs since cache entry)
       → accept response but DO NOT update cache (GAP-D fix, v2.11.3)
       → cache keeps old floor values as conservative baseline
       → prevents malicious Lambda from poisoning cache with inflated balances
     - current_balance < cached.balance → Lambda's DB diverged
       → flag as nonce_mismatch, increment mismatch counter
  7. NONCE_MISMATCH_TOLERANCE (3): after 3 consecutive mismatches → audit_failed
```

**What nonces catch that TX digest audit doesn't:**
- Post-hoc DB corruption (Lambda processes honestly, later modifies its DB)
- Wallet deletion (Lambda removes a wallet it already processed)
- Continuous monitoring (every TX, not just at audit trigger)

**Nonce response is NOT included in the accumulator.** Nonces are a separate
verification channel. The accumulator chain contains only TX digests.

### 3.7 Crash Recovery

The audit buffer lives inside the `AvmInterpreter` struct. Lambda creates a new
interpreter on startup. On crash:

1. Buffer is lost (in-memory only). The current audit cycle resets.
2. Wallet cache is lost. Rebuilds as new TXs flow.
3. `PULSE_MISS` tolerance (3 cycles) absorbs occasional resets.
4. Frequent crashes degrade W3 → operational investigation.

**No disk persistence for the buffer.** The buffer is ~112 KB at max — losing it on crash
costs one audit cycle (~5 minutes or up to 2000 TXs). This is acceptable. Not persisting
means Lambda cannot tamper with persisted buffer files. The AVM starts clean, and
the buffer fills naturally from real TX processing.

This is strictly better than the v0.4.0 design, where Lambda-persisted buffer files
and was **always** lost on crash (no persistence possible).

---

## 4. Audit Protocol

### 4.1 Trigger

Core initiates an audit when either of two independent conditions is met:

1. **Time trigger:** `current_time - last_audit_time >= PULSE_AUDIT_INTERVAL_SECS`
   (300 seconds = 5 minutes) AND `buffer.count > 0`.
   Fires regardless of TX count. Catches low-traffic validators — even 1 TX/hour
   gets audited every 5 minutes.
2. **Count trigger:** `buffer.count >= PULSE_BUFFER_MAX × PULSE_BUFFER_TRIGGER_RATIO`
   (2000 × 0.80 = 1600 entries). Prevents buffer overflow on busy validators.

Core checks both conditions on every TX execution. A validator with zero TXs
produces no audit (no entries = nothing to verify = no pulse). This is correct —
a validator doing nothing cannot be dishonest about nothing. Its W3 score degrades
from missing pulses, which is the appropriate consequence.

**Why dual trigger instead of hardware-scaled cap:**

The old design (`audit_cap = argon2id_per_sec × PULSE_CAP_FACTOR`) made the
trigger point hardware-dependent. Problem: the factor (0.05) was low enough that
most hardware clustered at the minimum (10), making the "linear scaling" illusory.
The new design uses protocol constants:

- Time trigger ensures regular audits at any TX volume.
- Count trigger prevents unbounded buffer growth.
- Neither depends on hardware benchmarks.
- Both are simple, predictable, and auditable.

| Scenario | TXs in 5 min | Trigger | Sample size (10%) |
|----------|-------------|---------|-------------------|
| Low-volume validator | 5 | Time (5 min) | 1 entry |
| Normal validator | 50 | Time (5 min) | 5 entries |
| Active validator | 500 | Time (5 min) | 50 entries |
| Busy validator | 1600+ | Count (80% buffer) | 160 entries |
| Idle validator | 0 | Never (no entries) | No audit — W3 degrades |

### 4.2 Random Subset Selection

Core does not audit all entries — it selects a random subset:

```
sample_size = max(1, buffer.count × PULSE_SAMPLE_RATIO)    // 10% of buffer
audit_seed = BLAKE3("AXIOM_AUDIT_SELECT" || buffer.accumulator || validator_ed25519_pk)
selected = fiat_shamir_select(audit_seed, buffer.count, sample_size)
```

The sample scales with buffer contents via `PULSE_SAMPLE_RATIO` (0.10 = 10%).
No fixed cap — the sample grows proportionally. Lambda doesn't know which entries
will be selected until Core tells it (accumulator is hidden).

**Detection probability (if Lambda tampers with X% of TXs):**

| Buffer size | Sample (10%) | 5% tampering | 10% tampering | 20% tampering |
|-------------|-------------|-------------|--------------|--------------|
| 50 entries | 5 | 23% per audit | 41% per audit | 67% per audit |
| 500 entries | 50 | 92% per audit | 99.5% per audit | >99.99% |
| 1600 entries | 160 | 99.98% per audit | >99.99% | >99.99% |

Multiple audits compound: after 3 audits with 50 samples each, detection
probability for 5% tampering exceeds 99.9%. Random selection (Fiat-Shamir)
means Lambda cannot predict which 10% — must keep ALL entries honest.

### 4.3 Audit Request

Core produces an `AuditRequest` (emitted in PublicOutputs):

```rust
struct PulseAuditRequest {
    /// The selected entry indices into the ring buffer (ordered)
    selected_indices: Vec<u32>,
    /// The tx_number for each selected entry (AVM-internal sequence)
    tx_numbers: Vec<u64>,
    /// produced_state_id for each selected entry (Lambda DB lookup key)
    state_ids: Vec<[u8; 32]>,
    /// Core's chain hash over the selected subset (the expected answer)
    expected_hash: [u8; 32],
    /// Global epoch number (for freshness)
    epoch: u64,
}
```

The `expected_hash` is computed by chaining only the selected entries using
Argon2id→BLAKE3 (same memory-hard work as the per-TX accumulator):

```
subset_accumulator = [0u8; 32]
for idx in selected_indices (in order):
    digest = buffer.entries[idx]
    payload = digest.to_bytes()  // "AXIOM_TX_DIGEST" || fields
    argon2_output = Argon2id(salt=subset_accumulator, password=payload, m=32MB, t=1)
    subset_accumulator = BLAKE3("AXIOM_AUDIT_VERIFY" || subset_accumulator || argon2_output)
expected_hash = subset_accumulator
```

### 4.4 Lambda Response

Lambda receives the `PulseAuditRequest` and must look up each selected TX from
its DB. **Lambda does ZERO crypto** — it sends raw fields back to Core:

1. Look up each TX from `transaction_db` by `produced_state_id` (sent in the request).
2. Extract raw fields: `sender_balance`, `amount`, `produced_state_id`.
3. Send raw `Vec<TxDigest>` back to Core — **Lambda does ZERO crypto**.

```rust
struct PulseAuditResponse {
    entries: Vec<TxDigest>,  // Raw DB fields — Core does all hashing
    epoch: u64,
}
```

Lambda passes the `PulseAuditResponse` in `PublicInputs.audit_response` on its
next TX execution. **Core replays the Argon2id→BLAKE3 chain** over the raw entries
and compares the result against its `expected_hash`.

**The Argon2id cost is on Core (AVM), not Lambda.** Each entry requires one
Argon2id(32MB, t=1) + one BLAKE3. Cost scales with sample size:

| Buffer size | Sample (10%) | Replay time (~55ms/entry) |
|-------------|-------------|--------------------------|
| 50 entries | 5 | ~275ms |
| 500 entries | 50 | ~2.75s |
| 1600 entries | 160 | ~8.8s |

Lambda's cost is just DB lookups.

Lambda cannot fake these entries — if Lambda stored wrong balances, amounts, or
state IDs (due to corruption, cheating, or modified DB), the replayed chain hash
diverges from Core's expected hash. The nonce/epoch ensures Lambda cannot
pre-compute the answer before knowing which TXs will be selected.

### 4.5 Verification and Penalty

Core replays `Argon2id→BLAKE3` over `audit_response.entries` and compares
the resulting hash with `expected_hash`.

**Match:** Audit passes. Core resets the accumulator to `[0;32]` and count to 0
(returned in PublicOutputs). Lambda clears its buffer. The successful audit is
reported as a `PulseProof` (see §5). Core emits `PulseProofData` in PublicOutputs.

**Mismatch:** Lambda's execution diverged from Core's records. This indicates
one or more of:
- Lambda's database is corrupted
- Lambda ran a modified Core ELF
- Lambda fed altered wallet states
- Lambda skipped or reordered transactions

**Penalty: Core restarts.**

Per Yellow Paper §23.14, restart incurs:
- VBC re-verification (SPHINCS+ chain walk — expensive)
- ZKP benchmark re-qualification (if ZKP mode)
- Loss of all in-flight transactions
- CC score penalty (W1 uptime gap)

This is an operational penalty, not a slashing. The validator operator is incentivized
to investigate and fix the issue. Persistent mismatches (repeated restarts) degrade
the node's reputation through W1 and W3 scoring.

### 4.6 Audit Timing and Deadline

The deadline for responding to an audit request is clock-based:

```
AUDIT_DEADLINE_TICKS = 60     // 300 seconds (5 minutes) to respond
```

If Lambda does not respond within `AUDIT_DEADLINE_TICKS`, Core treats it as a mismatch
(restart penalty). This prevents a Sybil from indefinitely delaying audits to spread
CPU load.

The 5-minute deadline is generous for honest nodes (worst case: 8.8 seconds of work
at max buffer in a 300-second window) but punishing for a machine running multiple
Lambda instances simultaneously — each must complete its own Argon2id(32MB) replay
within the same window, competing for memory bus bandwidth.

---

## 5. Pulse Proof and Gossip

### 5.1 Pulse Proof Structure

A successful audit produces a `PulseProof` broadcast via Nabla gossip:

```rust
struct PulseProof {
    /// Global epoch number at time of audit
    epoch: u64,
    /// TARDIS root at epoch start (binds to network state)
    tardis_root: [u8; 32],
    /// Core's accumulator over the audited buffer
    full_accumulator: [u8; 32],
    /// Total entries in audit buffer at trigger time
    entry_count: u32,
    /// Number of entries selected for re-execution
    sample_size: u32,
    /// Hash of the audit response (proves Lambda responded correctly)
    audit_hash: [u8; 32],
    /// Ed25519 signature over all above fields
    signature: [u8; 64],
}
```

**Signature payload:**

```
BLAKE3("AXIOM_PULSE_SIG" || epoch || tardis_root || full_accumulator ||
       entry_count || sample_size || audit_hash)
```

### 5.2 Verification and Trust Model

**PulseProofs are self-attested.** Peers verify structural validity but cannot
independently verify that the audit actually occurred. This is by design — peers
(Nabla nodes) have no access to Lambda's transaction data and cannot re-execute
the audit.

Peers verify received `PulseProof`:

1. **Epoch is recent** (`|proof.epoch - my_epoch| <= 1`).
2. **Ed25519 signature valid** against sender's known pubkey.
3. **TARDIS root matches** verifier's own root at that epoch.
4. **entry_count > 0** (audit had real content).
5. **audit_hash present and non-zero** (proves Lambda responded).

All O(1). No re-execution needed.

**Two-layer defense (why self-attestation is sufficient):**

A compromised node would need to defeat both layers simultaneously:

- **DMAP** catches a modified Core ELF. During normal trustmesh interaction,
  validators re-execute each other's transactions and compare DMAP checkpoints.
  A modified Core produces different memory roots → caught by DMAP verification.
  DMAP is the defense against dishonest Core.

- **Silicon Pulse** catches a dishonest Lambda. Core's accumulator chain detects
  tampered wallet states, skipped transactions, and corrupted DB. Silicon Pulse
  is the defense against dishonest Lambda.

A fake PulseProof requires modified Core (to generate fake accumulator data).
Modified Core is caught by DMAP. Therefore, fake PulseProofs are transitively
caught — not by peer spot-checking, but by DMAP's existing verification.

### 5.3 Gossip Integration

```rust
enum GossipMessage {
    // ... existing variants ...
    PulseProof(PulseProof),           // "I audited my Lambda and it passed"
    PeerAuditBanClaim(BanClaim),      // "I peer-audited B and it FAILED — go verify"
}
```

**Broadcast timing:** Immediately after successful audit completion.

**Deduplication:** One pulse per (node_id, epoch). First-seen wins.

**Size:** ~138 bytes per PulseProof. Negligible gossip overhead.

### 5.3a Ban Fan-Out (the failure path)

We must fan out the **ban**, not only the pulse — and it is the higher-value signal.
A private, auditor-local ban (the original design) rejects `B` at only the one
validator that audited it; the rest of the mesh keeps co-witnessing with a corrupt
`B`. So a peer-audit ban is broadcast as a `PeerAuditBanClaim` carrying EVIDENCE:
`{ target_pk, txid, expected_hash, failure_reason, banned_at_tick, auditor_pk, sig }`.

Unlike a `PulseProof` (self-attested, verified only structurally — peers can't re-run
it), a `PeerAuditBanClaim` is **re-auditable**. A recipient treats it as a *trigger,
not authority*: verify the signature (O(1)), then run its OWN peer-audit of `B`, and
adopt the ban into its DMAP-VM ban list **only if its own audit also fails**. This
converges network-wide distrust in one audit round while keeping the §1 "no trusted
node" rule — a false accusation dies because every verifier re-audits and an honest
`B` passes. Enforcement is unchanged (Core rejects banned `witness_pk`s); fan-out only
feeds the AVM ban list *after* the recipient's own confirmation. Full spec:
Yellow Paper §23.14.6a.

### 5.4 Low TX Volume

The dual trigger (§4.1) ensures all active validators get audited regularly.
The time trigger (every 5 minutes) catches low-traffic validators; the count
trigger (80% of 2000 = 1600 entries) prevents overflow on busy validators:

| Scenario | TXs in 5 min | Trigger | Sample (10%) | Replay time |
|----------|-------------|---------|-------------|-------------|
| Low-volume | 5 | Time (5 min) | 1 | ~55ms |
| Normal | 50 | Time (5 min) | 5 | ~275ms |
| Active | 500 | Time (5 min) | 50 | ~2.75s |
| Busy | 1600+ | Count (80%) | 160 | ~8.8s |
| Idle | 0 | Never | — | No audit — W3 degrades |

An idle validator produces no pulse. Its W3 score degrades toward zero. This is
the correct outcome — a validator doing no work provides no integrity guarantees
and should not receive credit for doing so. The CC score calibration (W2=10 vs
W1=1) already ensures that honest validators with registrations outrank idle
Sybils by 5x+ regardless of W3.

---

## 6. Argon2id Parameters and Contention Detection

### 6.1 Two Benchmarks at Ignition

At startup (ignition TX sequence), Core runs two benchmarks:

1. **ZKVM round-trip**: Lambda sends ignition TX → Core processes → ZKVM proof →
   proof back to Core. Measures if validator can produce STARK proofs. Determines
   ZKP qualification (premium proof tier). DMAP validators still pass ignition
   with DMAP attestation instead of STARK.

2. **Argon2id throughput**: Core runs Argon2id(32MB, t=1) iterations for 200ms,
   measures iterations/sec. This is informational — logged and included in
   `PulseProofData` for peer comparison. Audit trigger points are protocol
   constants (§4.1), not hardware-dependent.

### 6.2 Why 32MB Argon2id (m_cost = 32768 KiB)

**Primary purpose:** Ensure Lambda records data honestly. The Argon2id→BLAKE3 chain is
tamper-evident — skip Argon2id → chain hash diverges → DMAP re-execution catches it.

**Secondary purpose:** Detect multi-validator co-location on commodity hardware.

The Argon2id memory parameter is set to 32MB (32768 KiB) based on a threat model analysis:

| CPU class | L3 cache | 32MB m_cost | Threat? |
|-----------|----------|------------|---------|
| Cloud VM / VPS | 4-16MB | Exceeds L3 — contention detected | **Yes — primary attack surface** |
| Desktop (i7/Ryzen 7) | 16-36MB | Exceeds most — contention likely | Moderate |
| High-end desktop (Ryzen 9 V-Cache) | 64MB | Fits in L3 — no contention | Low — traceable |
| Server (EPYC/Xeon) | 64-384MB | Fits in L3 — no contention | **No — operator is traceable** |

**Key insight:** Attackers optimize for anonymity, not compute. An attacker running multiple
validators to manipulate the network will use commodity hardware (cheap VMs, cloud instances)
where traceability is low. 32MB exceeds the L3 cache on all such hardware. An operator with
a $50K/month EPYC server is traceable by definition — they have real infrastructure, real
identity, and real stake at risk. Argon2id contention detection doesn't need to catch them;
skin in the game (permanent ban, VBC stake) does that work.

32MB provides effective contention detection against the actual threat while keeping per-TX
cost reasonable (~30ms/call release mode, ~33 TX/sec single-thread).

### 6.3 Memory-Hard Contention Detection

The key innovation: **Argon2id is the accumulation function, not a separate benchmark.**
Each TX accumulation step does:

```
argon2_output = Argon2id(salt=accumulator, password=tx_digest, m_cost=32MB, t_cost=1)
new_accumulator = BLAKE3("AXIOM_AUDIT_CHAIN" || accumulator || argon2_output)
```

Argon2id allocates 32MB of memory per call. Two validators sharing commodity hardware =
64MB constantly fighting for memory bus bandwidth on every TX. On cloud/desktop hardware
where L3 < 32MB, this contention is unavoidable — memory bandwidth is a shared resource.

The Argon2id output is bound into the BLAKE3 chain. Skip it → chain hash diverges →
DMAP re-execution catches it. This is enforced by the protocol, not by self-reporting.

### 6.4 No Hardware-Dependent Trigger

The old design used hardware benchmarks to set `audit_cap` (the buffer trigger point).
This is removed. Audit triggers are now protocol constants (§4.1):

- **Time trigger**: Every 5 minutes (PULSE_AUDIT_INTERVAL_SECS = 300).
- **Count trigger**: Buffer at 80% of 2000 (PULSE_BUFFER_TRIGGER_RATIO = 0.80).

The Argon2id benchmark at ignition is retained for two purposes:
- **Informational**: Included in `PulseProofData.argon2id_per_sec` so peers can
  compare claimed throughput against actual entry counts.
- **Diagnostic**: Operators see their hardware's Argon2id throughput at startup.

But it does NOT determine when audits fire. A Raspberry Pi and a 64-core server
both audit on the same schedule. The difference is that the Pi processes fewer
TXs between audits (slower Argon2id per TX), so its buffer is smaller at trigger
time, and its sample is proportionally smaller. This is correct — the Pi does
less work, so less work needs auditing.

---

## 7. Liveness Enforcement

### 7.1 Pulse Tracking

Each node tracks peer pulse delivery:

```rust
struct PeerPulseState {
    last_epoch_seen: u64,       // most recent epoch with valid pulse
    consecutive_misses: u32,    // epochs without a pulse
    pulse_score_pct: u64,       // rolling percentage (0–100), fixed-point
}
```

**Epoch definition (global):**
```
epoch = current_tick / EPOCH_LENGTH_TICKS
```

Where `EPOCH_LENGTH_TICKS = 720` (1 hour). Peers evaluate pulse delivery per global
epoch. A node that produced a valid pulse in a given epoch gets credit. A node that
didn't, doesn't. Global epochs allow peers to trivially verify currency without
knowing the prover's TX volume.

### 7.2 Consequences

| Condition | Action |
|-----------|--------|
| `consecutive_misses >= PULSE_MISS_TOLERANCE` (3) | W1 score reduced by 50%. Node deprioritized in gossip. |
| `consecutive_misses >= PULSE_MISS_EVICTION` (10) | Node removed from gossip mesh. Must re-register. |

**Grace period:** Nodes within 6 epochs of NBC issuance are exempt.
This gives new nodes time to accumulate transaction history.

### 7.3 CC Score Integration

Pulse compliance becomes a **W3** weight in the CC score:

```
CC_score = W1 * uptime_ticks + W2 * registrations + W3 * pulse_score_pct / 100
```

Where `pulse_score_pct` is a fixed-point integer (0–100): the percentage of recent
epochs where the node delivered a valid pulse. Fixed-point avoids float in the
scoring path — consistent with existing saturating `u64` arithmetic.

Proposed: `W3 = 5` (between W1=1 and W2=10).

---

## 8. Constants

```rust
// ── Silicon Pulse — YPX-009 ──

// Audit buffer and trigger
pub const PULSE_BUFFER_MAX: u32 = 2000;                 // hard cap on buffer entries
pub const PULSE_BUFFER_TRIGGER_RATIO: f64 = 0.80;       // count trigger at 80% = 1600
pub const PULSE_AUDIT_INTERVAL_SECS: u64 = 300;         // time trigger: every 5 minutes
pub const PULSE_SAMPLE_RATIO: f64 = 0.10;               // audit 10% of buffer
pub const PULSE_CALIBRATION_MS: u64 = 200;              // benchmark duration at startup

// Argon2id parameters (per-TX accumulation)
// m_cost = 32768 (32MB memory), t_cost = 1, p_cost = 1, output = 32 bytes
// 32MB exceeds commodity L3 cache — see §6.2 threat model

// Timing
pub const PULSE_EPOCH_LENGTH_TICKS: u64 = 720;         // 1 hour — evaluation window

// Enforcement
pub const PULSE_MISS_TOLERANCE: u32 = 3;           // miss 3 → degraded
pub const PULSE_MISS_EVICTION: u32 = 10;           // miss 10 → evicted
pub const PULSE_GRACE_CYCLES: u32 = 6;             // new nodes get 6 epochs grace
```

---

## 9. Attack Analysis

### 9.1 VM Farm (Secondary Threat)

**Without Silicon Pulse:**
- 100 VPSes × $5/month = $500/month for 100 nodes.
- Each node processes transactions without any audit overhead.

**With Silicon Pulse:**
- Each node's Core independently audits its Lambda every 5 minutes (or at 1600
  buffer entries via count trigger).
- Per-TX cost: Argon2id(32MB) ~30ms. Two validators on one machine = 64MB
  competing for memory bus on every TX.
- Each audit: 10% sample × ~55ms replay per entry. At 500 TXs: 50 entries × 55ms
  = ~2.75 seconds of memory-hard work.
- On a shared machine running 2+ nodes:
  - Memory bus contention degrades per-TX throughput for ALL nodes.
  - Audits compete for CPU and memory bandwidth. Deadlines at risk.
  - The machine becomes audit-bound, not network-bound.
- **Idle Sybil nodes** produce no pulses (zero TXs = zero buffer entries).
  Their W3 degrades. The CC score calibration (W2=10 vs W1=1) ensures honest
  nodes with registrations outrank idle Sybils by 5x+ regardless.

### 9.2 Pre-computation Attack

Attacker pre-computes audit responses.

**Defense:** The audit selects transactions based on `buffer.accumulator`, which
depends on every TX processed so far. The accumulator is unpredictable until the
buffer fills. Lambda doesn't know which TXs will be selected until the audit fires.

### 9.3 Shared-Work Attack

Two nodes try to share AVM re-execution work.

**Defense:** Each Core has a different `validator_ed25519_pk` in the audit seed.
Different validators select different transaction subsets. The work is independent.

### 9.4 Lambda Shortcut Attack

Lambda reads stored results from DB instead of re-executing through AVM.

**Defense:** This actually works — if Lambda stored correct results. The audit
verifies that Lambda's stored state matches Core's records. If Lambda cheated
during original processing (stored wrong results), the shortcut produces wrong
hashes. If Lambda was honest originally, the shortcut produces correct hashes —
but that means Lambda was honest, which is what we're checking.

The audit catches **divergence**, not laziness. A Lambda that stores correct results
and reads them back is, by definition, honest. The CPU cost of the shortcut (DB reads +
hashing) is lighter than full re-execution but still non-trivial for 50+ TXs.

**Enhancement (if shortcut becomes a concern):** Include a field in `TxDigest` that
can only be derived from re-execution — e.g., a DMAP checkpoint at a specific
instruction count. Lambda can't produce this from stored data; it must re-execute.
This upgrades the audit from "verify stored results" to "prove re-execution."

### 9.5 Raspberry Pi Viability

A Pi 4 (4GB) has ~1-2MB L3 cache and ~4GB/s memory bandwidth. With 32MB Argon2id,
each TX accumulation takes ~200-300ms (slower than x86 ~55ms). At this rate, the
Pi processes ~3-5 TX/sec — a realistic load for a low-volume validator.

| Step | Pi 4 (4GB) | Concern? |
|------|------------|----------|
| Accumulation (per TX) | ~200-300ms | Pi's throughput limit, not a bug |
| Audit sample (5 entries at low volume) | ~1-1.5s | No — deadline is 300s |
| Audit sample (50 entries at normal volume) | ~10-15s | No — deadline is 300s |
| Pulse proof assembly + signature | <1ms | Negligible |
| Buffer memory (2000 entries max) | ~112 KB | Negligible |

The Pi is comfortable. Even at max sample for a Pi's realistic TX volume, the
audit completes well within the 300-second deadline. The 32MB Argon2id working
set fits in the Pi's 4GB RAM with room to spare.

### 9.6 20-Year Hardware Projection

As hardware speeds up, more TXs accumulate between 5-minute audits, so the 10%
sample grows proportionally. The audit cost per entry decreases, but the number
of sampled entries increases. Detection probability only improves.

| Year | Argon2id(32MB)/call | TXs in 5 min | Sample (10%) | Audit time | Memory contention (2 nodes) |
|------|--------------------|--------------|--------------|-----------|-----------------------------|
| 2026 | ~30ms | ~500 | 50 | ~1.5s | 64MB — detectable on commodity |
| 2031 | ~15ms | ~2000 | 160 (capped at trigger) | ~2.4s | 128MB — detectable |
| 2036 | ~5ms | ~2000 | 160 (capped at trigger) | ~0.8s | 128MB — detectable |
| 2046 | ~0.5ms | ~2000 | 160 (capped at trigger) | ~80ms | 128MB — detectable |

The memory contention defense does not depreciate. Memory bandwidth grows slower
than compute speed. 32MB Argon2id exceeds most L3 caches (16-48MB on commodity
hardware) and will remain effective for at least a decade. If L3 caches eventually
reach 32MB, `m_cost` can be increased in a protocol upgrade (same as any protocol
constant). No T_COST yearly escalation is needed — the self-benchmark at startup
adaptively measures hardware capability (Argon2id/sec), and 32MB memory-hardness
is the bottleneck, not iteration count (t_cost=1 is sufficient).

---

## 10. Integration with Existing Architecture

### 10.1 AVM Changes (core/avm)

The `AvmInterpreter` struct gains two new fields:

1. `audit_buffer: Mutex<AuditBuffer>` — ring buffer of TxDigests + accumulator chain.
2. `wallet_cache: Mutex<WalletCache>` — wallet state cache for nonce challenges.

After each `execute()` / `execute_with_dmap()` returning Accept:

1. Extract TxDigest fields from `PublicOutputs` (tx_number, sender_balance,
   receiver_balance, state_id, amount).
2. Accumulate: Argon2id(salt=accumulator, password=digest_bytes, m=32MB) → BLAKE3 chain.
4. Update wallet cache with produced_state_id and balance.
5. Check trigger conditions (time ≥ 5 min or count ≥ 80% of buffer max).
6. On trigger: compute sample_size = max(1, count × 0.10), Fiat-Shamir subset
   selection, expected hash, attach `AuditRequest` to PublicOutputs.
7. Generate NonceChallenge from wallet cache, attach to PublicOutputs.
8. If `NonceResponse` present in PublicInputs: verify against wallet cache.

**RISC-V executor and memory system are untouched.** The audit logic is in the
AVM host code (Rust), not the RISC-V guest. DMAP checkpoint collection is unchanged.

### 10.2 Core Changes (core/logic)

Minimal — only new types and PublicInputs/PublicOutputs fields:

1. Add `nonce_response: Option<NonceResponse>` to `PublicInputs`.
2. Add `audit_request: Option<AuditRequest>` to `PublicOutputs`.
3. Add `nonce_challenge: Option<NonceChallenge>` to `PublicOutputs`.
4. Add `pulse_proof: Option<PulseProofData>` to `PublicOutputs`.
5. Add `audit_failed: bool` to `PublicOutputs`.
6. New types: `AuditRequest`, `AuditResponse`, `NonceChallenge`, `NonceResponse`,
   `PulseProofData`, `TxDigest`, `AuditBuffer`, `WalletCache`.
7. All new fields `#[serde(default)]` for backward compatibility.

**Note:** The accumulator chain, trigger logic, and nonce verification all run in
the AVM host code (`core/avm/src/interpreter.rs`), not in core-logic. Core-logic
only defines the types. This is intentional — the buffer must be invisible to Lambda,
and the AVM host is the trust boundary.

### 10.3 Lambda Changes

1. Handle `AuditRequest` from PublicOutputs (Silicon Pulse buffer audit):
   a. Look up requested TXs from `transaction_db` by tx_number.
   b. Re-execute each through `interpreter.execute()` — AVM produces the chain hash.
   c. Pass `AuditResponse` in `PublicInputs.audit_response` on next TX.
1b. Handle `AuditDemand` from PublicOutputs (§23.14 self-audit):
   a. Check if `target_validator_pk == our Ed25519 PK` (self-target).
   b. Look up `trigger_txid` in `transaction_db`.
   c. Extract raw fields: tx_number, sender_balance, receiver_balance, state_id, amount.
   d. Package into `AuditConfirmation` — Lambda does zero crypto.
   e. Pass in next `PublicInputs.audit_confirmation`. Core hashes and verifies.
2. Handle `NonceChallenge` from PublicOutputs:
   a. Look up target_wallet_pk in `transaction_db`.
   b. Pass `NonceResponse { wallet_pk, current_state_id, current_balance }` in
      next `PublicInputs.nonce_response`.
3. Handle `PulseProofData` from PublicOutputs:
   a. Forward to Nabla via admin API.
4. Handle `audit_failed = true`:
   a. Log audit failure with full detail.
   b. Initiate restart (VBC re-verification, benchmark).

**Lambda does NOT hold the buffer.** Lambda does not accumulate, does not chain,
does not persist audit state. Lambda is a pure executor that responds to AVM
requests. The AVM is the authority.

### 10.4 Nabla Changes

1. Receive `PulseProof` from Lambda (via admin API).
2. Add `GossipMessage::PulseProof` variant.
3. `PeerPulseState` tracking alongside existing peer scoring.
4. W3 integration in CC score calculation (fixed-point, §7.3).
5. Pulse state persisted in existing snapshot mechanism.

### 10.5 Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ Lambda                                                        │
│                                                               │
│  Calls interpreter.execute(inputs) for each TX                │
│  Receives PublicOutputs                                       │
│                                                               │
│  On AuditRequest (Silicon Pulse buffer audit):                │
│    Look up TXs by tx_number from transaction_db               │
│    Re-execute each through interpreter.execute()              │
│    (AVM internally verifies digests match its buffer)         │
│    Pass AuditResponse in next PublicInputs                    │
│                                                               │
│  On AuditDemand (§23.14 self-audit, target == our PK):       │
│    Look up trigger_txid in transaction_db                     │
│    Extract raw fields (balances, state_id, amount)            │
│    Pass AuditConfirmation in next PublicInputs                │
│    Lambda does ZERO crypto — Core hashes and verifies         │
│                                                               │
│  On NonceChallenge:                                           │
│    Look up wallet in DB → NonceResponse in next PublicInputs  │
│                                                               │
│  Cost: 10% sample × ~55ms/entry (THE HEAVY PART)            │
└──────────────────────────────────────┬───────────────────────┘
                                       │ execute() API
                                       ▼
┌──────────────────────────────────────────────────────────────┐
│ AvmInterpreter (persistent, Lambda-opaque)                    │
│                                                               │
│  audit_buffer: Mutex<AuditBuffer>                             │
│    entries[≤2000]: TxDigest ← financial/state fields only     │
│    accumulator: [u8; 32]   ← Argon2id(32MB)→BLAKE3 chain     │
│    count: u32                                                 │
│                                                               │
│  wallet_cache: Mutex<WalletCache>                             │
│    HashMap<wallet_pk, {state_id, balance}>                    │
│                                                               │
│  Per TX:                                                      │
│    1. Execute Core (guest) → PublicOutputs                    │
│    2. Compute TxDigest from outputs (financial/state fields)  │
│    3. Argon2id(32MB, salt=accumulator, pw=digest) → BLAKE3   │
│    4. Update wallet cache                                     │
│    5. Generate NonceChallenge → attach to PublicOutputs        │
│    6. If time≥5min or count≥80% → AuditRequest → PublicOutputs│
│    7. If AuditResponse provided → verify → PulseProof/fail    │
│    8. If NonceResponse provided → verify against cache         │
│    9. If AuditConfirmation provided → hash raw data, compare  │
│                                                               │
│  Lambda sees: PublicOutputs + AuditRequest + NonceChallenge   │
│  Lambda does NOT see: buffer, accumulator, cache              │
└──────────────────────────────────────┬───────────────────────┘
                                       │ PulseProofData
                                       ▼
┌──────────────────────────────────────────────────────────────┐
│ Nabla                                                         │
│                                                               │
│  Receive PulseProof from Lambda (admin API)                   │
│  Broadcast on gossip mesh                                     │
│  Track PeerPulseState per peer                                │
│  Update W3 in CC score (fixed-point)                          │
└──────────────────────────────────────────────────────────────┘
```

### 10.6 Relationship to §23.14 (Audit Demand)

§23.14 audit demands and Silicon Pulse serve different but complementary purposes.
§23.14 has **two distinct modes** depending on the target:

#### 10.6.1 Two Types of §23.14 Audit

| Aspect | Self-Audit (target == our PK) | Peer-Audit (target != our PK) |
|--------|-------------------------------|-------------------------------|
| **What** | Core verifies Lambda's DB integrity | Core forces validator to audit a peer |
| **Who responds** | Lambda (DB lookup) → Core (hash verify) | Lambda contacts external validator |
| **What it catches** | Lambda tampering with stored data | Validators not auditing each other |
| **Lambda crypto** | Zero — Lambda is a dumb pipe | Zero — Lambda carries data, Core verifies |
| **Protocol** | Local DB lookup, no network | Trustmesh: client carries challenge to peer |

#### 10.6.2 Self-Audit Flow (§23.14 Self-Target)

When `target_validator_pk == our own Ed25519 PK`, this is a self-audit. Core is
asking: "Lambda, show me what you stored for this TX. I'll check it myself."

```
┌─────────────────────────────────────────────────────────┐
│ Core (inside AVM)                                        │
│                                                          │
│  1. TX N triggers audit (deterministic from txid)        │
│  2. Target selection → picks our own validator PK        │
│  3. Emits AuditDemand { trigger_txid, challenge_nonce }  │
│     in PublicOutputs                                     │
│  4. AVM starts 10-TX countdown                           │
└──────────────────────────┬──────────────────────────────┘
                           │ PublicOutputs.audit_demand
                           ▼
┌─────────────────────────────────────────────────────────┐
│ Lambda                                                   │
│                                                          │
│  1. Receives AuditDemand from Core                       │
│  2. Detects: target_validator_pk == my Ed25519 PK        │
│  3. Looks up trigger_txid in transaction_db              │
│  4. Extracts raw stored fields:                          │
│     - tx_number (from transaction_record)                │
│     - sender_balance (from wallet state at TX time)      │
│     - receiver_balance (from wallet state at TX time)    │
│     - state_id (produced_state_id from receipt)          │
│     - amount (from transaction_record)                   │
│  5. Packages into AuditConfirmation:                     │
│     { challenge_nonce, target_validator_pk, raw fields }  │
│  6. Passes to Core in next TX's PublicInputs             │
│                                                          │
│  Lambda does ZERO crypto. Just a DB lookup.              │
└──────────────────────────┬──────────────────────────────┘
                           │ PublicInputs.audit_confirmation
                           ▼
┌─────────────────────────────────────────────────────────┐
│ Core (inside AVM) — enforce_audit_pre()                  │
│                                                          │
│  1. Receives AuditConfirmation with raw DB data          │
│  2. Verifies challenge_nonce matches demand              │
│  3. Hashes raw fields with BLAKE3 (same domain tag as    │
│     original accumulation)                               │
│  4. Compares against stored TxDigest entry in audit      │
│     buffer                                               │
│  5. Match → audit satisfied, countdown cleared           │
│     Mismatch → Lambda tampered with DB → audit_failed    │
│                                                          │
│  Core does ALL the crypto. Single hash comparison.       │
└─────────────────────────────────────────────────────────┘
```

**What this catches:**
- Lambda inflating balances in stored wallet state
- Lambda modifying produced_state_id in receipts
- Lambda altering transaction amounts
- Lambda corrupting any field it stores after Core computed it

**What this does NOT catch (that's Silicon Pulse's job):**
- Hardware sharing (Argon2id memory contention)
- Modified AVM binary (DMAP re-execution)
- Wallet state cache manipulation (nonce challenges)

#### 10.6.3 Peer-Audit Flow (§23.14 Peer-Target)

When `target_validator_pk != our own PK`, Lambda must contact the target validator
and obtain proof that they are alive and honest. This is carried by the client
via trustmesh — validators do not talk to each other directly.

**Status:** Peer-audit protocol **implemented** (v2.11.4). Lambda sends
`AXIOM/peer_audit_request` via ANTIE email (txid + hash). Remote Lambda DB lookup →
remote Core verifies hash → sends response. Match → clear, mismatch → ban 24h,
no response → ban 24h. See Yellow Paper §23.14.6 for full specification.

#### 10.6.4 Comparison with Silicon Pulse

| Aspect | §23.14 Self-Audit | YPX-009 Silicon Pulse |
|--------|-------------------|----------------------|
| **What** | DB integrity check | Execution integrity chain |
| **Mechanism** | Core hashes raw DB data, compares | Argon2id→BLAKE3 accumulator chain |
| **Trigger** | ~1 in 100 TXs, random | Every 5 min or at 80% buffer (1600 entries) |
| **Penalty** | AuditTimeout → self-terminate | Restart (VBC re-verify) or W3 degradation |
| **Catches** | Lambda DB tampering | Hardware sharing, modified AVM, state cache manipulation |

Both coexist. Both fire independently. Self-audit is lightweight (one DB lookup +
one hash comparison). Silicon Pulse is heavyweight (Argon2id per TX + full buffer
audit). Together they cover Lambda DB integrity AND execution integrity.

---

## 11. Implementation Plan

### Phase 1: Core Accumulator Fields
- Add audit fields to `PublicInputs` and `PublicOutputs` (`#[serde(default)]`).
- Implement `TxDigest` struct and BLAKE3 chain accumulation in `core/logic`.
- After CL2/CL3 Accept: compute digest, update accumulator.
- Unit tests: accumulator determinism, chain integrity.

### Phase 2: Audit Request Generation
- Fiat-Shamir subset selection from accumulator + validator PK.
- Dual trigger: time (5 min) and count (80% of PULSE_BUFFER_MAX).
- Proportional sample: `max(1, buffer.count × PULSE_SAMPLE_RATIO)`.
- Expected hash computation over selected subset (Argon2id(32MB)→BLAKE3).
- `AuditRequest` as new PublicOutputs field.
- Unit tests: selection determinism, expected hash correctness, both triggers.

### Phase 3: Lambda Audit Handler
- `AuditBuffer` struct with disk persistence.
- Handle `AuditRequest` from PublicOutputs.
- TX lookup from `transaction_db`, re-execution through AVM.
- Chain result computation, `AuditResponse` via PublicInputs.
- Handle `PulseProofData` → forward to Nabla admin API.
- Handle `audit_failed` → restart penalty.
- Unit tests: correct response for honest Lambda, mismatch for tampered state.

### Phase 4: Pulse Proof and Gossip
- `PulseProof` assembly from `PulseProofData` + Ed25519 signature.
- `GossipMessage::PulseProof` variant in Nabla.
- `PeerPulseState` tracking alongside existing peer scoring.
- W3 CC score integration (fixed-point).
- Pulse state persistence in existing snapshot mechanism.

### Phase 5: Testing
- Unit tests: accumulator, audit selection, hash chain, time trigger.
- Integration test: full audit cycle (Core accumulate → audit → Lambda respond → verify).
- Contention test: run 5 Lambda instances on 4-core machine, verify deadline pressure.
- Benchmark: measure actual re-execution times on Pi, x86, server.
- Chaos test: inject tampered wallet state, verify audit catches mismatch.

---

## 12. Nabla WAL Audit (Lightweight Integrity Check)

### 12.1 Different Purpose, Different Design

Lambda's Silicon Pulse is heavy by design — it serves as both integrity audit and
Sybil defense. **Nabla's audit is the opposite.** It must be:

- **Imperceptible.** Nabla runs on citizen devices — gaming PCs, laptops, Raspberry Pis.
  A gamer running Nabla must never notice a frame drop. A developer must never see
  their compile slow down. Target: **< 1ms per check, < 0.1% CPU.**
- **Frequent.** Short intervals catch corruption early, before it propagates via gossip.
- **Focused on WAL integrity.** The concern is not Sybil (multiple Nabla on one machine
  is low-value — citizens don't have validator stake). The concern is data quality:
  did the WAL persist correctly? Is the in-memory state consistent with what was written?

### 12.2 What Can Go Wrong With the WAL

Nabla's WAL (Write-Ahead Log) captures state changes before they're applied:
tick records, registration events, SMT updates, NBC trust changes. Corruption happens:

- **Power loss mid-write.** Partial WAL entry → torn state on recovery.
- **Disk errors.** Silent bit flips corrupt WAL entries (common on consumer SSDs
  without enterprise-grade ECC).
- **OS crash during fsync.** WAL header says entry was written, but data is garbage.
- **Memory corruption.** In-memory state diverges from WAL after a bad pointer or
  buffer overrun (rare, but Nabla is a long-running daemon).

If corrupted state enters the gossip mesh, it pollutes other nodes. Catching it
early — at the source — prevents propagation.

### 12.3 The Check: WAL ↔ Memory Consistency (Recent Audit)

Every `WAL_AUDIT_INTERVAL_TICKS` (default: 10 ticks = 50 seconds), Nabla performs:

```
1. Pick a random recent WAL entry (within last WAL_AUDIT_WINDOW entries)
2. Read the raw WAL entry from disk
3. BLAKE3 hash the WAL bytes
4. Compare against the in-memory state that entry represents:
   - Tick record: does in-memory TARDIS tree hash match WAL?
   - Registration: does SMT leaf match WAL?
   - NBC update: does peer trust record match WAL?
5. If mismatch → discard corrupted state + re-sync from neighbours (§12.7)
```

**Cost per check:** One disk read (~100-500μs on SSD) + one BLAKE3 hash (~1μs) +
one memory comparison (~1μs). **Total: < 1ms.** Invisible to the user.

### 12.3.1 Deep WAL Scan (Old Section Cross-Verification)

The recent audit (§12.3) only covers the last 100 entries. A bit flip from weeks ago
sits undetected — the node gossips correct recent state but carries a corrupted
historical record. When a peer asks for that old entry (e.g., during their own
re-sync), the corruption spreads.

Every `WAL_DEEP_SCAN_INTERVAL_TICKS` (default: 720 ticks = 1 hour), Nabla performs
a random deep scan:

```
1. Pick WAL_DEEP_SCAN_COUNT (default: 5) random entries from the ENTIRE WAL
   (not just recent — any entry from sequence 0 to current)
2. For each: verify checksum (same as §12.3 — BLAKE3 re-derive)
3. If any checksum fails → corruption detected in old section
4. Recovery: discard from corrupted entry forward + re-sync (§12.7)
```

**Cost per deep scan:** 5 disk reads + 5 BLAKE3 hashes = **< 3ms.** Runs once per
hour. Completely invisible. Over 24 hours, 120 random entries scanned — a 10,000-entry
WAL gets ~1.2% coverage per day. Over a week, ~8.4% sampled. Persistent corruption
is caught probabilistically within days.

### 12.3.2 Peer Cross-Verification (The Neighbour Check)

The local audit catches checksum failures (bit flips, truncation). But what if the
WAL checksum was written correctly over already-wrong data? (E.g., in-memory state
was corrupted before the WAL write.) The checksum passes but the data is garbage.

**Solution:** Periodically cross-check a WAL section hash with a neighbour.

Every `WAL_PEER_VERIFY_INTERVAL_TICKS` (default: 2160 ticks = 3 hours), Nabla:

```
1. Pick a random tick range [T, T+50] from the node's WAL history
2. Compute a section hash: BLAKE3("AXIOM_WAL_SECTION" || T || entry_checksums[T..T+50])
   (Hash of the ordered checksums in that range — NOT the full payloads)
3. Send StatePullRequest { mode: WalVerify, tick_range: (T, T+50), section_hash }
   to one random mesh peer
4. Peer computes the same section hash over its own WAL for that tick range
5. Peer responds: match/mismatch/missing (doesn't have that range)
```

**If mismatch:** The node doesn't know who is wrong. But it now knows something is
suspect. Log warning, flag the section, and on the next deep scan prioritize entries
from that range. If the node's checksums all pass locally, the peer may be corrupted
— no action needed. If any local checksum fails, recover per §12.7.

**If peer responds "missing":** Peer doesn't have that tick range (it joined later
or already compacted). Try another peer. If no peer has it, the section is
unverifiable — log and continue. This is not an error; it's an information gap.

**Cost:** One BLAKE3 over ~50 checksums = ~1μs compute. One wire message roundtrip.
Runs every 3 hours. Negligible.

**Privacy:** Only checksums are compared, never payload data. Peers learn nothing
about the node's registration content — only whether their WAL histories agree on
a range of ticks.

### 12.4 WAL Entry Checksums

Each WAL entry carries an inline checksum written at persist time:

```rust
struct WalEntry {
    sequence: u64,              // monotonic sequence number
    entry_type: u8,             // tick=0, registration=1, nbc=2, smt=3
    payload_len: u32,           // bytes
    payload: Vec<u8>,           // serialized state change
    checksum: [u8; 32],         // BLAKE3(sequence || entry_type || payload)
}
```

The audit re-derives the checksum from the stored payload and compares. This catches:
- Bit flips in payload (silent disk corruption)
- Truncated writes (payload_len doesn't match actual data)
- Sequence gaps (missing entries)

### 12.5 What the Audit Does NOT Do

- **No AVM re-execution.** Nabla's WAL audit is pure hash comparison, not Core work.
- **No WAL health broadcast.** A node doesn't announce its WAL health to the network
  — that would leak internal state. The peer cross-verification (§12.3.2) only shares
  section checksums, not results or failure status. Operators see health in logs and
  on the console dashboard.
- **No penalty for peers.** This is self-healing, not enforcement. A node with a
  corrupted WAL repairs itself or halts. It doesn't accuse other nodes.
- **No Sybil defense.** Running 10 Nabla nodes on one machine is not the threat model.
  Citizens don't have validator stake. The risk of multiple Nablas is gossip noise,
  which TARDIS tree structure and NBC probation already handle.

### 12.6 Constants

```rust
// ── Nabla WAL Audit ──
pub const WAL_AUDIT_INTERVAL_TICKS: u64 = 10;       // recent check every 50 seconds
pub const WAL_AUDIT_WINDOW: u64 = 100;               // recent audit: last 100 entries

// Deep scan (old section verification)
pub const WAL_DEEP_SCAN_INTERVAL_TICKS: u64 = 720;  // deep scan every 1 hour
pub const WAL_DEEP_SCAN_COUNT: u32 = 5;              // 5 random entries per deep scan

// Peer cross-verification
pub const WAL_PEER_VERIFY_INTERVAL_TICKS: u64 = 2160; // peer check every 3 hours
pub const WAL_PEER_VERIFY_SECTION_SIZE: u64 = 50;     // compare 50-tick sections

// Recovery
pub const WAL_REPAIR_MAX_RETRIES: u32 = 3;           // re-sync retries before halt

// Client-signed records (§12.9)
pub const SIGNATURE_REQUIRED_FROM_TICK: u64 = 0;     // all records must be signed
                                                      // (set to network launch tick
                                                      // if migrating from unsigned era)

// RangeSync peer trust
pub const SYNC_BLACKLIST_HOURS: u64 = 24;             // blacklist bad peers for 24h
pub const SYNC_REJECTION_THRESHOLD_PCT: u64 = 90;     // >90% rejected = bad peer
pub const SYNC_REJECTION_STRIKES: u32 = 3;            // consecutive bad responses
```

### 12.7 Recovery

Nabla cannot repair corrupted data from its own corrupted data. The WAL is the
source of truth — if the WAL is bad, local state derived from it is also bad.
There is no "self-repair from local data" path.

On checksum mismatch:

1. **Log the corruption** with full detail (sequence number, entry type, expected
   vs actual checksum). Operator visibility is critical.
2. **Discard corrupted state.** Delete the WAL from the corrupted entry forward,
   and the in-memory state derived from it.
3. **Active pull from neighbours** (§12.8). The node sends a `StatePullRequest`
   to mesh peers, requesting the missing state for specific tick ranges.
4. **Passive re-sync** complements the pull: TARDIS anti-entropy (every 6 ticks)
   detects root hash mismatch, orphan recovery (P1→P4) handles tree reconnection,
   and Hello messages re-verify NBC trust.
5. **If re-sync fails** (no reachable peers, network partition): halt cleanly.
   The node removes itself from gossip to prevent propagating bad state.
   On restart, it re-attempts sync from bootstrap peers.

From the network's perspective, a node recovering from WAL corruption looks exactly
like a node that went offline and came back. The TARDIS protocol already handles
this — it's the normal case for citizen nodes on laptops that get closed overnight.

**Fail safe, don't fail silent.** A gaming PC that loses power mid-tick should
discard suspect state and re-sync from peers, not silently gossip corrupted
hashes to the network.

### 12.8 State Sync Protocols

Production `nabla_node` broadcasts TickHash via anti-entropy every 6 ticks. When a
peer's root hash differs, the current code detects the fork but has **no mechanism
to request the missing entries.** Gossip is fire-and-forget — messages missed during
downtime are not retained in the network. A node that was offline for 2 hours cannot
recover those 2 hours of gossip from passive listening alone. It must actively ask
a neighbour.

Two distinct sync protocols handle two distinct situations:

| Situation | Protocol | When |
|-----------|----------|------|
| **New node, empty state** | StatePull (§12.8.1) | Bootstrap — node has nothing |
| **Existing node, gap in state** | RangeSync (§12.8.2) | Downtime, WAL corruption, missed gossip |

#### 12.8.1 StatePull — New Node Bootstrap

A new Nabla has no records, no WAL, no SMT. It cannot compare anything. It must
pull the entire network state from peers, trusting them to provide honest data.

**Trust model:** A new node already trusts its bootstrap peers (operator configured
`bootstrap.toml`). This is the same trust assumption as the Hello/NBC handshake.
After the full pull completes, the node verifies its root hash against multiple
peers — if the majority agree, the data is good.

**Wire messages:**

```rust
enum WireMessage {
    // ... existing variants ...

    /// Request state entries from a peer for a specific tick range.
    /// Used for: (a) new node bootstrap, (b) WAL peer cross-verification (§12.3.2).
    StatePullRequest {
        /// What kind of pull this is
        mode: StatePullMode,
        /// Requesting node's current SMT root hash (so peer knows what we have)
        our_root_hash: [u8; 32],
        /// Start of tick range (inclusive)
        from_tick: u64,
        /// End of tick range (inclusive). Peer stops at STATE_PULL_MAX_BYTES.
        to_tick: u64,
        /// For WalVerify mode: our section hash (§12.3.2)
        section_hash: Option<[u8; 32]>,
    },

    /// Response to StatePullRequest.
    /// Capped at STATE_PULL_MAX_BYTES (5 MB). If the tick range contains more
    /// data, the requester sends another request starting from highest_tick + 1.
    StatePullResponse {
        mode: StatePullMode,
        /// State entries (up to 5MB serialized). Ordered by tick ascending.
        entries: Vec<StatePullEntry>,
        /// Highest tick included in this response (requester resumes from here + 1)
        highest_tick_served: u64,
        /// For WalVerify mode: match/mismatch/missing
        verify_result: Option<WalVerifyResult>,
        /// Earliest tick this peer has (0 if it has everything). If > from_tick,
        /// the requester knows this peer compacted old data.
        available_from_tick: u64,
        /// If true, peer is at serving capacity — requester should try another peer
        overloaded: bool,
    },
}

enum StatePullMode {
    /// Bootstrap: send me all state in this tick range (new node)
    Bootstrap,
    /// WAL verify: compare section hashes only (§12.3.2), don't send entries
    WalVerify,
}

struct StatePullEntry {
    wallet_id: WalletId,
    new_state: StateId,
    tx_hash: TxHash,
    tick: u64,
    client_pk: [u8; 32],    // wallet Ed25519 public key
    client_sig: [u8; 64],   // owner's signature over state (§12.9)
}

enum WalVerifyResult {
    Match,
    Mismatch,
    /// Peer doesn't have this tick range (joined later, compacted)
    Missing,
}
```

**Protocol: Sequential round-robin pull.**

One 5MB chunk at a time, rotating through mesh peers:

- **No burst load.** Parallel pulls would hit every mesh peer simultaneously.
  If 3 new nodes join around the same time, parallel pull × 3 = entire mesh overwhelmed.
- **Natural backpressure.** The node applies entries before requesting more.
  On citizen hardware (Pi, laptop), processing 5MB takes real time.
- **Fair to peers.** Each peer serves one chunk, then rests while the node
  cycles through others.

```
1. New node connects to bootstrap peers, receives Hello with root hashes
2. Determine gap: from_tick = 0, to_tick = peer's current tick
3. Collect available mesh peers: peers[] (shuffled randomly)
4. peer_cursor = 0
5. current_from = 0
6. Loop until current_from >= to_tick:
   a. peer = peers[peer_cursor % len(peers)]
   b. Send StatePullRequest { mode: Bootstrap,
        from_tick: current_from, to_tick, our_root_hash }
   c. Wait for response (STATE_PULL_TIMEOUT_SECS = 30s)
   d. If timeout or overloaded → skip peer, advance cursor, retry same range
   e. If response received:
      - Apply entries via existing gossip engine (apply_state_update)
      - current_from = highest_tick_served + 1
   f. peer_cursor += 1  (rotate to next peer)
7. After all chunks applied, compare root hash against 3 random peers.
   Majority match → bootstrap complete.
   Majority mismatch → discard and re-bootstrap from different peers.
```

**Each response capped at 5MB (`STATE_PULL_MAX_BYTES = 5_242_880`).**
Typically ~100 bytes per entry → ~50,000 entries per chunk → ~10,000 ticks (~14h).

**Example — new node, 50,000 ticks behind (~70 days), 8 mesh peers:**

```
  Chunk 1: ticks     0 – 10,000  → Peer 0, apply, ~2s
  Chunk 2: ticks 10,001 – 20,000 → Peer 1, apply, ~2s
  Chunk 3: ticks 20,001 – 30,000 → Peer 2, apply, ~2s
  Chunk 4: ticks 30,001 – 40,000 → Peer 3, apply, ~2s
  Chunk 5: ticks 40,001 – 50,000 → Peer 4, apply, ~2s

  Total: ~15-25 seconds. Each peer served 1 chunk.
```

#### 12.8.2 RangeSync — Existing Node Gap Fill

An existing node has most of the state but is missing records — from downtime,
WAL corruption, or missed gossip. Unlike bootstrap, it has local state to compare
against. The protocol uses **bilateral range-walking** to find exactly where the
gap is and transfer only the missing records.

**Trigger:** Checksum mismatch (Hello exchange, TickHash anti-entropy, or timed
WAL audit). Either side can initiate.

**Key insight:** Neither side decides who is "right." They compare sequential
record ranges to find divergence, and both sides contribute what the other is
missing. No trust decision — they merge.

**Wire messages:**

```rust
enum WireMessage {
    // ... existing variants ...

    /// Range sync: "here's my hash for records in this range — do you agree?"
    RangeSyncRequest {
        /// Start tick of range (inclusive)
        from_tick: u64,
        /// Number of records in this section
        record_count: u64,
        /// BLAKE3 hash over ordered record checksums in this range
        section_hash: [u8; 32],
        /// Our latest tick (so peer knows our overall position)
        our_latest_tick: u64,
    },

    /// Range sync response
    RangeSyncResponse {
        /// Does our section hash match?
        match_result: RangeSyncMatch,
        /// If mismatch: the records the requester is missing (≤ 5MB)
        missing_entries: Vec<StatePullEntry>,
        /// Peer's latest tick
        peer_latest_tick: u64,
        /// Peer's section hash for the same range (so requester can
        /// send back records the peer is missing)
        peer_section_hash: [u8; 32],
    },
}

enum RangeSyncMatch {
    /// Hashes match — this section is identical, move to next
    Match,
    /// Hashes differ — missing_entries contains what requester needs.
    /// Requester should also check if IT has records the peer is missing
    /// (compare peer_section_hash after applying received entries).
    Mismatch,
    /// Peer doesn't have this range (joined later, compacted)
    Missing,
}
```

**Protocol: Section-by-section range walk.**

```
Phase 1: Trigger
  Checksum mismatch detected (Hello, TickHash, or timed audit)

Phase 2: Range walk (forward from point of divergence)
  1. Initiator picks starting point: its latest tick
  2. Sends RangeSyncRequest for next RANGE_SYNC_SECTION_SIZE (500) records:
     from_tick = latest_tick
     record_count = 500
     section_hash = BLAKE3("AXIOM_RANGE_SYNC" || ordered checksums of records in range)
  3. Peer compares same range against own records:
     a. Section match → respond Match, move to next 500 records
     b. Section mismatch → peer identifies which records differ:
        - Records peer has that initiator doesn't → included in missing_entries
        - Peer also returns its own section_hash so initiator can send back
          records the PEER is missing (bilateral)
     c. Peer doesn't have range → respond Missing, initiator tries another peer
  4. Initiator applies received missing entries
  5. If initiator has records the peer doesn't (comparing peer_section_hash):
     initiator sends those records back to the peer (mutual repair)
  6. Advance to next 500 records, repeat

Phase 3: Walk backward (for old corruption)
  If forward walk completes but root hashes still differ → walk backward:
  from_tick = latest_tick - 500, then - 1000, etc.
  Same section comparison logic. Finds old corruption that the
  deep scan (§12.3.1) flagged.

Phase 4: Convergence
  After walk completes, both sides re-compare root hashes.
  Match → done. Both nodes are consistent.
  Still mismatch → log warning, try another peer (one side may be persistently wrong).
```

**Example — node offline for 2 hours (1,440 ticks), 5 entries/tick = ~7,200 missing:**

```
  Section 1: ticks 8,000–8,500 → Match (both had these before downtime)
  Section 2: ticks 8,500–9,000 → Mismatch! Peer sends 2,500 missing entries (~250KB)
  Section 3: ticks 9,000–9,440 → Mismatch! Peer sends 2,200 missing entries (~220KB)

  Total transferred: ~470KB (not the full SMT, just the gap)
  Total round-trips: 3
  Root hashes now match. Done.
```

**Why not StatePull for gap fill?** StatePull sends everything in a tick range.
RangeSync compares first, sends only differences. For a node that missed 2 hours,
StatePull would transfer the entire 2 hours of data even if the node already has
90% of it (from gossip received before and after the gap). RangeSync transfers
only the 10% that's actually missing.

**Trust model: Client-signed state + Core validation + majority gap-fill.**

See §12.9 for the full trust chain. Each WAL record carries the wallet owner's
Ed25519 signature over the state. This signature is unforgeable without the
client's private key — no validator, no peer, no colluding group can fabricate it.

During RangeSync:

1. Compare section hashes to find divergence.
2. Transfer missing entries (each carries `client_pk` + `client_sig`).
3. Receiving node's **Core** validates `client_sig` before accepting into WAL.
   Nabla does not decide — Core is the sole judge.
4. **Monotonicity:** Core rejects records with tick < existing tick for the same wallet.
5. **Never overwrite:** If node already has a valid signed record, it keeps it —
   regardless of what peers claim. CorrectionHints only fill gaps, never override.
6. On conflict, signature verification settles it — not majority vote.

**Parent corruption:** A corrupted parent sends bad entries during RangeSync.
The child's Core rejects them (invalid `client_sig`, or monotonicity violation).
No trust decision needed — the signature is the proof.

#### 12.8.3 WAL Verify (Peer Cross-Check)

Lightweight hash-only comparison for §12.3.2. No entries transferred.

```
1. Node picks random tick range, computes section hash
2. Send StatePullRequest { mode: WalVerify, from_tick, to_tick, section_hash }
   to one random peer
3. Peer computes same section hash over its WAL, returns WalVerifyResult
4. Mismatch → flag section for deep scan priority (§12.3.1)
```

#### 12.8.4 Constants

```rust
// ── State Pull (Bootstrap) ──
pub const STATE_PULL_MAX_BYTES: usize = 5_242_880;    // 5 MB per response
pub const STATE_PULL_TIMEOUT_SECS: u64 = 30;           // per-chunk timeout
pub const STATE_PULL_COOLDOWN_SECS: u64 = 2;           // pause between chunks

// ── Range Sync (Gap Fill) ──
pub const RANGE_SYNC_SECTION_SIZE: u64 = 500;          // records per section comparison
pub const RANGE_SYNC_MAX_TRANSFER_BYTES: usize = 5_242_880; // 5 MB per response
pub const RANGE_SYNC_TIMEOUT_SECS: u64 = 30;           // per-section timeout
```

#### 12.8.5 Rate Limiting

Both protocols share the same rate limiting:

- **Per-peer rate limit:** Max 1 request per 60 seconds from any single peer.
  Requests beyond this are silently dropped.
- **Response cap:** 5MB hard limit per response.
- **Serving cap:** A peer serves at most `STATE_PULL_MAX_CONCURRENT_SERVE = 3`
  simultaneous sync requests from different nodes. Excess return `overloaded: true`.
- **Sequential by design:** One request in flight at a time per requesting node.
- **Peer blacklisting:** If > `SYNC_REJECTION_THRESHOLD_PCT` (90%) of entries from
  a single peer fail signature verification across `SYNC_REJECTION_STRIKES` (3)
  consecutive sync responses, disconnect and blacklist the peer for
  `SYNC_BLACKLIST_HOURS` (24 hours). Prevents CPU exhaustion from fabricated entries.

#### 12.8.6 Relationship to Existing Anti-Entropy

The current TickHash broadcast (Step 9 in nabla_node.rs) becomes the **detection**
mechanism. RangeSync and StatePull become the **resolution** mechanisms:

```
Existing:    TickHash broadcast → detect root mismatch → log fork warning → ???

New node:    Hello → empty state → StatePull round-robin → bootstrap complete

Existing     TickHash / Hello → root mismatch → RangeSync walk →
  node:      find gap → transfer missing records only → converge
```

This mirrors what the lib-mode simulator already does at sim.rs:2104-2154, but via
explicit wire messages instead of direct memory access. The key improvement: the sim
sends all missing entries from one richer node. RangeSync compares first, sends
only the diff, and the load is distributed across the mesh.

### 12.9 Client-Signed State Records

#### 12.9.1 The Problem: Bare Records Have No Proof

Current Nabla WAL records are bare state updates:
`{wallet_id, new_state, tx_hash, tick}`. No signatures, no provenance, no trace
back to the wallet owner. When a registration arrives, Nabla verifies the k=3
validator signatures and DEED TX — but then **discards all proof** and stores only
the result.

During sync, a malicious peer could fabricate records. A validator-signed provenance
commitment (hashing over validator IDs) would be a hash over public data — anyone
could recompute it. Even carrying validator signatures doesn't help: an attacker who
controls 3 validators can produce perfectly valid k=3 signatures for fabricated
registrations.

#### 12.9.2 The Solution: The Client Signs Their Own State

**Key insight:** It is the **client** who registers with Nabla, not the validator.
The client has an Ed25519 keypair (the wallet key). The client is the only entity
that can authorize state changes to their own wallet. Therefore:

**The client signs their own state record at registration time.**

```rust
struct ClientStateSignature {
    /// Client's Ed25519 public key (= wallet public key)
    client_pk: [u8; 32],
    /// Ed25519 signature over the state record
    client_sig: [u8; 64],
}
```

**Signature payload:**

```
sig = Ed25519_sign(
    client_sk,
    BLAKE3("AXIOM_WALLET_STATE" || wallet_id || new_state || tx_hash || tick)
)
```

**Size:** 32 (pk) + 64 (sig) = **96 bytes per record.** For 100,000 wallets:
~9.6 MB. Lighter than the 136-byte provenance commitment it replaces, and
infinitely more secure.

#### 12.9.3 Why This Is Unforgeable

The previous design (provenance commitment) was a BLAKE3 hash over public fields.
Anyone who knew the fields could recompute it. Even k=3 colluding validators could
fabricate it.

The client signature changes everything:

| Attack | Provenance commitment (old) | Client signature (new) |
|--------|----------------------------|----------------------|
| Peer fabricates record | Recompute hash from public data — **passes** | No client private key — **fails** |
| 3 colluding validators | Include their own signer_ids — **passes** | Still no client private key — **fails** |
| Self-created validator IDs | Create fake IDs, hash them in — **passes** | Client's real Ed25519 key on-chain — **fails** |
| Replay old record | Old commitment still valid — **passes** | Old signature valid but tick monotonicity rejects — **fails** |

**The only entity that can create a valid state record for wallet W is the owner
of wallet W's private key.** Not validators, not Nabla nodes, not peers. The wallet
owner.

#### 12.9.4 Registration Flow (Updated)

```
1. Client prepares registration:
   - wallet_id, new_state (state after TX), tx_hash, tick
   - Signs: BLAKE3("AXIOM_WALLET_STATE" || wallet_id || new_state || tx_hash || tick)
   - Includes client_pk + client_sig in registration payload

2. Client sends Registration + DeedTransaction + ClientStateSignature to Nabla

3. Nabla's Core verifies (existing flow + new checks):
   - Ban check, DEED TX, k=3 receipt, execution proofs
   - NEW: verify client_sig against client_pk
   - NEW: verify client_pk matches wallet's known Ed25519 public key
   - NEW: **cross-check** — the {wallet_id, new_state, tx_hash, amount} that
     the client signed MUST be identical to the fields in the k=3 receipt.
     k=3 receipt proves the data is REAL (validators verified the math).
     client_sig proves the OWNER authorized it. If they disagree → reject.
     This prevents the client from modifying any field before sending to Nabla.

4. Nabla stores entry WITH client signature:
   {wallet_id, new_state, tx_hash, tick, client_pk, client_sig}

5. Gossip carries client_pk + client_sig with StateUpdate:
   GossipMessage::StateUpdate { wallet_id, new_state, tx_hash, tick, client_pk, client_sig }

6. Receiving Nabla nodes verify client_sig before applying to their own SMT
```

**The signature travels with the record forever.** Through gossip, through sync,
through StatePull, through RangeSync. Any node, at any time, can verify that the
wallet owner authorized this specific state.

#### 12.9.5 Sync Validation (Core Authority)

**Critical rule: All WAL writes pass through Core.**

Nabla carries data, Core judges it. Every record entering the WAL — whether from
original registration, gossip, StatePull, or RangeSync — must be validated by Core:

```
Received entry from any source (registration, gossip, sync)
  → Nabla passes to Core for validation
  → Core checks:
    1. client_sig is valid Ed25519 signature over BLAKE3("AXIOM_WALLET_STATE" || fields)
    2. client_pk matches the wallet's known public key (or is the first record for this wallet)
    3. tick is plausible: not future (> local_tick + 2), not impossibly old
    4. Monotonicity: incoming tick >= existing tick for this wallet_id
       (prevents replay of old-but-valid signed records)
    5. Signature cutoff: if tick >= SIGNATURE_REQUIRED_FROM_TICK, client_sig MUST
       be present. Records at or after this tick without a valid signature are rejected.
       Records before this tick may be unsigned (legacy, pre-signature era).
       During RangeSync (gap fill from untrusted peers), ALL records must have
       signatures regardless of tick — gap fill peers are not bootstrap-trusted.
  → Core returns Accept or Reject
  → Nabla stores only if Core accepts
```

**Monotonicity rule (fixes replay attack):** A wallet's state can only move forward.
If we already have a record for wallet W at tick 100, a synced record for wallet W
at tick 50 is rejected — even if its signature is valid. Old signatures are real but
stale. State doesn't go backward.

**This means:**
- Fabricated records are rejected (no valid client_sig)
- Colluding validators can't fake records (they don't have client private keys)
- Replayed old records are rejected (monotonicity)
- Nabla can't bypass validation (Core enforces at every entry point)

#### 12.9.6 Majority Correction Protocol

When a conflict is detected during RangeSync (two peers have different records for
the same wallet at the same tick), the node doesn't guess. It asks the neighbourhood.

```
Phase 1: Conflict Detection
  RangeSync with Peer A reveals: Peer A has entry X for wallet W at tick T.
  We have entry Y for the same wallet W at tick T.
  Signatures differ.

Phase 2: Neighbourhood Poll
  Ask N mesh peers (not Peer A): "What is your record for wallet W at tick T?"
  Each peer responds with: { entry, client_pk, client_sig }

Phase 3: Signature Verification First
  For each response, verify client_sig against client_pk.
  Discard any response with an invalid signature — don't even count it.
  Only valid-signature responses participate in the majority decision.

Phase 4: Majority Decision
  Count valid responses:
  - If majority matches our entry Y → we are correct. Peer A is wrong.
  - If majority matches Peer A's entry X → check:
    * Do we already have a VALID signed record? If yes → keep ours.
      Never overwrite a Core-validated record by majority vote.
      (Majority may be a colluding group. Our record has a real signature.)
    * Are we MISSING this record? If yes → accept it (gap fill).
  - If no majority → inconclusive. Log warning, do not change anything.

Phase 5: Correction Hint
  If Peer A is missing a record we have (gap, not conflict):
    Send CorrectionHint { wallet_id, tick, correct_entry, client_pk, client_sig,
                          supporting_peer_count } to Peer A.
    Peer A's Core validates client_sig before accepting.

  IMPORTANT: CorrectionHint only fills GAPS (missing records).
  It NEVER overwrites an existing record that has a valid client signature.
  A node that holds a valid signed record keeps it, regardless of what
  the neighbourhood claims.
```

**Wire message:**

```rust
enum WireMessage {
    // ... existing variants ...

    /// Correction hint: "you appear to be missing this record."
    CorrectionHint {
        wallet_id: WalletId,
        tick: u64,
        entry: StatePullEntry,  // includes client_pk + client_sig
        /// How many independent peers have this record
        supporting_peers: u8,
    },
}
```

**Rate limiting:** Max 5 CorrectionHints per peer per hour. A node flooding
corrections is either broken or malicious — either way, throttle it.
Global cap: max 20 CorrectionHints per hour total (regardless of source peer).

#### 12.9.7 The Trust Chain (Complete)

```
Wallet owner (Ed25519 keypair — the wallet key)
  ↓ signs
State record: BLAKE3("AXIOM_WALLET_STATE" || wallet_id || state || tx_hash || tick)
  ↓ client_sig (64 bytes) + client_pk (32 bytes)
Registration → Nabla verifies sig + k=3 receipt + DEED
  ↓ stored with signature
WAL entry (wallet_id, state, tx_hash, tick, client_pk, client_sig)
  ↓ gossip carries signature
All peers verify client_sig independently
  ↓ during sync
Core re-validates: sig valid + pk matches wallet + tick monotonic
  ↓ on missing record
Majority poll → CorrectionHint → receiving Core validates sig before accepting
```

**No validator trust needed for record authenticity.** Validators process the
registration (k=3 receipt), but the RECORD is authenticated by the wallet owner.
Even if all 3 validators are compromised, they cannot forge a state record for a
wallet they don't own the private key for.

The trust anchor is the wallet owner's Ed25519 key — the same key that signs
transactions. If that key is compromised, the wallet is compromised regardless
of Nabla. But a compromised key is a per-wallet problem, not a network problem.

#### 12.9.8 Updated WAL Entry Structure

```rust
struct WalEntry {
    sequence: u64,
    entry_type: u8,
    payload_len: u32,
    payload: Vec<u8>,
    checksum: [u8; 32],            // BLAKE3(sequence || entry_type || payload)
    client_pk: Option<[u8; 32]>,   // wallet Ed25519 public key (registration entries)
    client_sig: Option<[u8; 64]>,  // signature over state (registration entries)
}
```

**When signature is present:** Registration records, group wallet updates
(signed by group wallet owner).

**When signature is None:** Tick records (signed by TARDIS parent's Ed25519 key —
already authenticated by the tree structure), snapshot markers, ban records
(authenticated by double-spend evidence, not wallet owner).

#### 12.9.9 Updated StatePullEntry

```rust
struct StatePullEntry {
    wallet_id: WalletId,
    new_state: StateId,
    tx_hash: TxHash,
    tick: u64,
    client_pk: [u8; 32],    // wallet Ed25519 public key
    client_sig: [u8; 64],   // THE proof — unforgeable without private key
}
```

Bootstrap (StatePull) and gap fill (RangeSync) both carry the client signature.
The receiving node's Core validates `client_sig` before the entry enters the WAL.
No exceptions.

#### 12.9.10 Security Analysis Summary

| Finding | Severity | Status |
|---------|----------|--------|
| Record fabrication by peers | was CRITICAL | **Fixed** — client_sig unforgeable |
| k=3 colluding validators forge records | was CRITICAL | **Fixed** — validators don't have client keys |
| Provenance commitment recomputable | was CRITICAL | **Eliminated** — replaced with Ed25519 signature |
| State rollback via old records | was HIGH | **Fixed** — tick monotonicity enforced by Core |
| Majority overwrites valid record | was HIGH | **Fixed** — never overwrite existing signed record |
| Bootstrap majority with 3 peers gameable | was HIGH | **Mitigated** — signatures are independently verifiable regardless of majority |
| DEED TX not verified during sync | was HIGH | **Acceptable** — DEED is an economic gate at registration; client_sig is the authenticity gate during sync |
| Wallet activity patterns visible during sync | HIGH | **Fundamental tradeoff** — cannot sync state without sharing state |

---

## 13. Succession Protocol (Future — Not in Scope)

The original v1.5.1 document described a "Will" mechanism for hardware failure
recovery (§4 Succession & Recovery). This is **deferred** — it requires:

- SMT anchoring of succession intents.
- DEED wallet dual-signing.
- 2,016-tick anti-hijack cooldown.
- Liveness rebuttal protocol.

These are valuable but independent of Silicon Pulse. Succession can be specified
as a future YPX once the pulse mechanism is stable and tested.

---

## 14. Honest Assessment

### What Silicon Pulse Stops

- **Dishonest Lambda:** Core detects database tampering, modified ELF, altered wallet
  state, skipped or reordered transactions. This is the primary value.
- **Data pollution:** Nonce challenges force Lambda to prove it holds correct wallet
  state at random points in time. Corrupted or fabricated state is caught.
- **Colluding validators:** Client-signed state records (§12.9) make record fabrication
  impossible without the wallet owner's private key — even k=3 colluding validators
  cannot forge records.
- **Cheap VPS Sybil farms:** CPU contention from N independent audits on shared cores
  (secondary benefit).
- **Phantom nodes:** No transaction history = no pulse = W3 degradation.
- **Hardware depreciation:** Benchmark-adaptive sample size keeps cost constant across
  hardware generations.

### What It Doesn't Stop

- **Dedicated hardware per identity:** An attacker paying $20/month per VPS with
  exclusive CPU gets honest audit performance. But they're also doing real work for
  the network. The social stack (3-MV-set, NBC lineage, CC history) handles the rest.

- **Lambda shortcut (reading stored results):** If Lambda was honest originally,
  reading from DB produces correct hashes. This reduces CPU cost but doesn't break
  security — it means Lambda was honest. Enhancement in §9.4 can close this if needed.

- **Compromised wallet keys:** If a wallet owner's Ed25519 private key is stolen, the
  attacker can sign valid state records. But this is a per-wallet problem, not a
  protocol problem — and it exists regardless of Silicon Pulse.

### The Right Framing

Silicon Pulse is an **integrity audit first** and a **cost multiplier second**. The
primary function is catching dishonest behaviour — data pollution, state tampering,
collusion. The Sybil defense (making multi-node farming expensive) is a natural side
effect of the audit's computational cost, not a purpose-built puzzle.

Purpose-built puzzles (memory-hard sequential hashing, cache-thrashing, device binding)
resist parallelisation but do not detect dishonesty. A single evil node on dedicated
hardware passes any puzzle perfectly while corrupting the ledger. Silicon Pulse catches
the evil node. The puzzle doesn't.

The mechanical defense (audit verification) buys time for the organic defense (social
trust graph) to mature. A network with 5+ years of NBC lineage depth, CC score history,
and 3-MV-set approval graphs has an immune system that doesn't depend on computation
hardness. Silicon Pulse is the innate immunity. The social graph is the adaptive
immunity. Both needed. Neither sufficient alone.

---

## Appendix A: Why NBC-T (TEE Attestation) Was Deprecated for AXIOM

*Preserved from AXIOM v1.5.1 §2 for architectural record.*

### A.1 The NBC-T Design (Reference)

NBC-T would have bound node identity to a Trusted Execution Environment (TEE):

1. **Enclave Boot:** Node initializes TEE, generates `Node_Priv_Key` inside enclave.
   Private key never exported to disk.
2. **Local Attestation:** CPU produces a signed Quote containing the node's public key,
   binary hash (`SHA256(AXIOM_Binary)`), TEE measurement (`MRENCLAVE`), and the
   platform certificate chain.
3. **Offline Verification:** Peers verify the Quote locally using embedded manufacturer
   Root CAs (Intel, AMD). No external API calls permitted.

### A.2 Why It Was Deprecated

NBC-T fails AXIOM's survival constraints on three axes:

**1. Certificate Authority Expiry (The Killer Problem)**

TEE attestation depends on manufacturer CA certificate chains. These certificates
have finite lifetimes (Intel's root CAs expire, AMD's ASK certificates rotate).
AXIOM is designed to survive extended network blackouts where certificate renewal
services are unreachable. A 2-year blackout would leave every NBC-T node unable
to verify new peers because the CA chain has expired. There is no workaround —
the entire security model depends on a trusted third party (the CPU manufacturer)
maintaining infrastructure.

**2. Vendor Lock-in and Hardware Monoculture**

NBC-T requires specific CPU features: Intel SGX, AMD SEV, or ARM TrustZone.
This excludes Raspberry Pi, Apple Silicon (no attestation API), older x86, and
any future architecture that doesn't implement these specific extensions. AXIOM
explicitly targets heterogeneous hardware — a protocol that only works on Intel
Xeon is not a protocol for everyone.

**3. The Offline Verification Paradox**

AXIOM forbids external API calls for verification (Intel IAS, AMD ASK endpoints).
This means peers must carry embedded root certificates. But embedded certificates:
- Become stale as manufacturers rotate keys.
- Cannot be updated without a binary update (which requires network).
- Create a bootstrap problem: how does a node verify a peer's Quote if its
  embedded CA bundle predates the peer's CPU?

### A.3 What NBC-T Got Right

The *intent* of NBC-T was correct: bind identity to physics, not just cryptography.
Silicon Pulse achieves the same goal through a different mechanism — instead of
asking "does this node run on real hardware?" (TEE attestation), we ask "is this
node doing real work honestly?" (Core audits Lambda). The answer to the second
question doesn't expire, doesn't depend on any manufacturer, and works on a
Raspberry Pi.

### A.4 NBC-T for Other Protocols

The NBC-T design is architecturally sound for protocols that:
- Can tolerate CA expiry (expected lifetime < 5 years).
- Target homogeneous hardware (datacenter deployments).
- Have reliable network access to attestation services.

It was deprecated specifically for AXIOM's survival-grade constraints, not because
the design itself is flawed.

---

## Appendix B: Resource Jitter Detection (Future Enhancement)

*From AXIOM v1.5.1 §5. Not in scope for YPX-009 Phase 1.*

Even with audit-based pulses, nodes attempting to run multiple identities may produce
observable timing artifacts:

- **Inconsistent tick response timing:** A machine running 5 nodes shows periodic
  latency spikes as audit re-executions overlap.
- **Audit completion clustering:** All N nodes on one machine tend to complete audits
  in similar timeframes (same physical CPU).
- **Scheduling jitter:** Context switching between N AVM instances produces
  characteristic sawtooth patterns in tick latency.

A future enhancement could add jitter analysis to the peer scoring system (W1),
using statistical methods to detect correlated timing across suspected sibling nodes.

---

## Appendix C: Argon2id — From Rejected to Repurposed

*Design rationale for the record — v0.1 rejection and v0.6.0 rehabilitation.*

An earlier draft (v0.1) proposed Argon2id memory-hard hashing as a standalone
proof-of-work pulse mechanism. This was rejected for two reasons:

**1. Philosophical rejection of meaningless computation.**
AXIOM is social science + game theory. Every operation should serve the network.
Burning 1GB of RAM on a hash that nobody needs is importing Bitcoin's proof-of-waste
philosophy into a protocol that explicitly rejects it.

**2. Fixed parameters depreciate.**
Argon2id with 1GB memory and t_cost=3 is meaningful in 2026 but trivial by 2046.
The only fix is perpetual parameter escalation — an arms race the protocol cannot win.

**v0.6.0 rehabilitation:** Argon2id was repurposed as the **accumulation function** inside
the audit chain (not as standalone proof-of-work). Each TX does Argon2id(32MB,t=1) →
BLAKE3 chain. The Argon2id output feeds into the audit chain — skip it and the chain
hash diverges, caught by DMAP re-execution. This solves the two original objections:

1. **Not wasted:** The Argon2id work is part of the audit chain. It produces a hash
   that gets verified. Every CPU cycle and memory byte is serving the integrity audit.
2. **No parameter arms race:** The parameters don't need to be "hard enough to be slow."
   They need to be "hard enough to cause memory bus contention when sharing a machine."
   64MB per TX exceeds L3 cache (16-48MB on most CPUs), forcing main memory access.
   Two validators sharing = 128MB competing for memory bandwidth. The contention
   effect doesn't depreciate with faster hardware — memory bandwidth grows slower
   than compute speed.

---

*YPX-009 closes three gaps: Lambda integrity (Core verifies Lambda's honest*
*execution via Argon2id→BLAKE3 audit chain — the primary function), Nabla WAL*
*quality (deep scan + peer cross-verification + client-signed records for*
*unforgeable state provenance), and resource sharing detection (Argon2id 32MB*
*memory pressure makes multi-validator-per-machine farming self-defeating). All*
*computation is meaningful. Nothing is wasted.*

---

## Appendix D: Security Audit (of spec v0.5.0)

> **Why this audit is part of the spec.** The protocol was adversarially reviewed
> at v0.5.0 and the review reshaped the design: a single architectural change —
> moving the audit buffer out of Lambda and into the AVM itself — eliminated both
> CRITICAL findings and three others simultaneously, because Lambda could no longer
> control its own audit input. That fix is §3 of this document (AVM-Held Audit
> Buffer) and is implemented in `core/avm/src/interpreter.rs` (`AuditBuffer`,
> held in interpreter state across executions). The full audit is preserved below
> so readers can follow the reasoning that produced the current architecture,
> including the findings that were dismissed and why.

### Audit record

**Auditor:** Claude (Opus 4.6)
**Date:** 2026-03-14
**Spec version:** v0.5.0
**Scope:** Full protocol review — threat model, cryptographic integrity, integration gaps,
implementation risks.

---

### Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 2 | **Fixed** in v0.4.0 spec (no dual-region needed) |
| HIGH | 3 | 2 eliminated by fix, 1 resolved |
| MEDIUM | 4 | 1 eliminated by fix, 3 open |
| LOW | 3 | Open |
| INFO | 2 | Noted |

**Key outcome:** A single architectural change (Lambda-held buffer with Core-verified
chain) eliminates C1, C2, H1, H2, and M4 simultaneously. See §Proposed Fix below.

> **v0.5.0 note:** The v0.4.0 spec described a Lambda-held buffer with accumulator
> pass-through through PublicInputs/PublicOutputs. v0.5.0 supersedes this: the buffer
> has been moved into the AVM itself (held in interpreter state across executions),
> eliminating the Lambda self-audit flaw where Lambda controlled its own audit input.
> The AVM now owns the accumulator — Lambda cannot tamper with it between TXs.

**Implementation status:** §12 (Nabla WAL audit, client-signed records, StatePull/RangeSync) fully implemented and tested (445 lib + 26 bin tests, 0 clippy warnings). §1-11 AVM audit implementation complete (v0.5.0): AVM-held audit buffer with BLAKE3 accumulator chain, wallet cache with nonce challenges, and DMAP spot-check binding are implemented. §23.14.6 peer-audit protocol fully implemented (v2.11.4): ANTIE email transport, dual-side audit, 24h ban enforcement. Remaining: Nabla PulseProof gossip (Phase 4).

---

### CRITICAL Findings

### C1. AVM Address Space Mismatch — Storage Region Unreachable

**Spec reference:** §3.2

**The problem:** The spec defines the storage region at `0x40000000–0x7FFFFFFF` (1 GiB).
The actual AVM address space is **16 MB** (`MAX_MEMORY = 16 * 1024 * 1024 = 0x01000000`).
Any access to `0x40000000` would return `MemoryAccessOutOfBounds`.

**Evidence:** `core/avm/src/riscv/memory.rs`:
```rust
pub const MAX_MEMORY: u32 = 16 * 1024 * 1024;  // 16 MB = 0x0100_0000
```

Reads/writes are bounds-checked against `MAX_MEMORY` (lines 59, 88). The `memory_root()`
function (line 147) hashes ALL allocated pages — no boundary exclusion exists.

**Impact:** The entire dual-region memory design (§3) cannot be implemented as specified.
The storage region address is 64x beyond the current address space limit.

**Recommendation:** Two options:
1. **Expand AVM address space** to accommodate storage region. This changes `MAX_MEMORY`,
   increases sparse Merkle tree depth, and affects DMAP checkpoint size/cost. Needs
   careful analysis of memory overhead on Pi 4 (4 GB RAM — sparse tree is fine, but
   page table overhead at 4 KB pages for 2 GiB address space = 512K page entries).
2. **Place storage region inside existing 16 MB space** with a smaller boundary.
   E.g., `AVM_STORAGE_BASE = 0x00C0_0000` (12 MB mark). Execution region: 12 MB,
   storage region: 4 MB. This is more than enough for a 14 KB audit buffer, but
   requires verifying the Core ELF doesn't use addresses above 12 MB (stack, heap).

Option 2 is simpler and sufficient. The audit buffer is ~14 KB; 4 MB is generous.
But the boundary must be verified against the actual Core ELF linker script and
risc0 guest memory layout.

---

### C2. Nonce Challenge — Core Cannot Access Wallet State at Tick Boundaries

**Spec reference:** §3.4 Source 2

**The problem:** Nonce challenges require Core to know wallet balances and state IDs:
```rust
NonceChallenge {
    tick,
    nonce,
    target_wallet_pk: target_wallet.pk,
    expected_balance: target_wallet.balance,
    expected_state_id: target_wallet.state_id,
}
```

Core runs inside the AVM — a sandboxed RISC-V interpreter. Core receives data only
via `PublicInputs` during transaction processing. Nonce challenges fire at tick
boundaries (every 20 ticks), when no transaction is being processed. **Core has no
mechanism to query Lambda for wallet state at tick boundaries.**

If Lambda provides the wallet state for the nonce (via some new IPC), then Lambda
controls the input. A dishonest Lambda feeds correct state for the nonce → passes
the nonce check → the nonce fails to detect corruption.

**Impact:** The nonce challenge mechanism as specified is architecturally infeasible.
The entire "idle validator fills buffer from nonces" guarantee (§5.4) depends on this.

**Recommendation:** Three options:
1. **Lambda-initiated nonce injection.** Lambda provides wallet state at tick boundaries
   as a special `PublicInputs` with a "nonce_query" flag. Core processes it, appends
   the nonce to the audit buffer. **Risk:** Lambda controls the input, so it could
   feed correct state even if its DB is corrupted elsewhere. However, the wallet
   selection is deterministic (Core derives it from `validator_pk + tick`), so Lambda
   can't choose WHICH wallet to be queried about. Lambda would need to maintain
   correct state for ALL wallets to pass random nonce challenges. This is actually
   a strong property — Lambda can't selectively corrupt.
2. **Core remembers state from recent transactions.** After each TX, Core stores
   {wallet_pk, balance, state_id} in the storage region. Nonce challenges sample
   from this local cache instead of querying Lambda. **Limitation:** Only covers
   wallets that had recent transactions. But combined with TX digests, this still
   provides good coverage. Idle validators with zero TXs would have no cached
   wallets — nonces would have nothing to check.
3. **Drop nonces, use time-based audit trigger instead.** Instead of nonces filling
   the buffer during idle periods, use a time-based trigger: if buffer hasn't
   reached AUDIT_CAP within MAX_AUDIT_INTERVAL ticks, audit what's accumulated.
   Simpler, no wallet-state query needed. Idle validators audit less frequently
   but honestly (they have less to audit). The spec's concern about idle Sybils
   dodging audits is secondary to the integrity mission (per v0.3.3 reframe).

Option 1 is strongest. Option 3 is simplest and aligns with the v0.3.3 philosophy
(integrity first, Sybil defense second).

---

### HIGH Findings

### H1. Nonce Challenge — `known_wallet_count` Divergence

**Spec reference:** §3.4 Source 2

**The problem:**
```
wallet_index = u64_from(nonce[0..8]) % known_wallet_count
```

`known_wallet_count` changes as wallets register. If Core's view of the count at
nonce generation time differs from Lambda's view at audit re-derivation time (because
new wallets registered between generation and audit), they select different wallets.
The nonce digest won't match → false positive audit failure → honest node penalised.

**Impact:** False positive audit failures for honest validators during periods of
active wallet registration. Could trigger undeserved restart penalties.

**Recommendation:** Include `known_wallet_count` as a field in `NonceChallenge`:
```rust
struct NonceChallenge {
    tick: u64,
    nonce: [u8; 32],
    known_wallet_count: u64,        // snapshot at generation time
    target_wallet_pk: [u8; 32],
    expected_balance: u64,
    expected_state_id: [u8; 32],
}
```

Lambda uses the stored `known_wallet_count` (not current count) when re-deriving
the wallet index. This makes the nonce deterministically reproducible.

Also requires a canonical wallet ordering (see H2).

---

### H2. Nonce Challenge — No Canonical Wallet Ordering

**Spec reference:** §3.4 Source 2

**The problem:** `wallets[wallet_index]` assumes Core and Lambda agree on wallet
ordering. The spec doesn't define this ordering. If Core iterates wallets in one
order (e.g., insertion order in AVM memory) and Lambda in another (e.g., SQLite
rowid order, or pk alphabetical order), the same `wallet_index` selects different
wallets → audit hash mismatch → false positive.

**Impact:** Deterministic false positives unless ordering is canonically defined.

**Recommendation:** Define canonical ordering explicitly:
- **Option A:** Lexicographic order by `wallet_pk` (32 bytes, big-endian compare).
  Simple, deterministic, no state dependency.
- **Option B:** Registration order by `tx_number` of the wallet's genesis/creation TX.
  Requires both sides to agree on the same ordering, which is guaranteed if both
  derive from the same transaction history.

Option A is safer — it requires no shared history, only the current set of known wallets.

---

### H3. Spot Check Protocol Undefined

**Spec reference:** §5.3, §8 (`PULSE_SPOT_CHECK_RATE = 10`)

**The problem:** The spec defines `PulseForgery` gossip and a spot check rate (verify
1 in 10 pulses fully), but never specifies HOW a peer performs a spot check.

A PulseProof is self-attested — signed by the node's own Ed25519 key. Peers verify
the signature and structural fields (§5.2), but cannot verify that the audit actually
happened. A compromised node (modified Core + Lambda) could generate perfectly valid
PulseProofs without running any audit.

To truly spot-check, a peer would need to:
1. Know which transactions the audited node processed (they don't — private data)
2. Access the same wallet states (they don't — Lambda's DB is local)
3. Re-execute through AVM (they could, but they lack the inputs)

Nabla peers have no access to Lambda's transaction data. They cannot re-execute
the audit. The spot check as implied is not feasible with current architecture.

**Impact:** PulseProofs are unfalsifiable by peers. A compromised node can fake
pulses indefinitely without detection.

**Recommendation:** Three options (not mutually exclusive):
1. **Cross-validator audit.** During trustmesh interaction (§23.14 existing), validators
   exchange a subset of recent TX digests. If validator A's digest for tx_number N
   differs from validator B's (both processed the same TX), forgery is detected.
   This leverages the existing trustmesh — no new protocol needed.
2. **PulseProof includes verifiable sub-claim.** E.g., include one nonce challenge
   answer in the PulseProof itself: `{tick, wallet_pk, balance, state_id}`. Nabla
   peers who hold that wallet's state can cross-check. This leaks one wallet's
   balance per pulse — privacy tradeoff.
3. **Accept the limitation.** Document that PulseProof verification is self-attested
   and relies on DMAP (which catches modified Core ELF) to prevent fake pulses.
   A modified Core is caught by DMAP re-execution at the validator layer. Silicon
   Pulse catches dishonest Lambda; DMAP catches dishonest Core. Together they cover
   both. The spot check constant becomes advisory only.

Option 3 is honest and may be sufficient given the DMAP coverage. But the spec
should explicitly state this rather than implying peers can fully verify pulses.

---

### MEDIUM Findings

### M1. Epoch Semantics Undefined

**Spec reference:** §5.1, §5.2

**The problem:** `PulseProof.epoch` is used throughout but never defined. Is epoch:
- A global concept (TARDIS-derived, e.g., every N ticks)?
- Per-validator (the period between consecutive audit triggers)?

Different validators fill their buffers at different rates (depends on TX volume +
nonce rate). If epoch is per-validator, then `epoch: u64` is a local counter with
different values across nodes. Peer verification check "Epoch is recent (current
or previous)" (§5.2) becomes meaningless — peers don't know what "current epoch"
means for the prover.

**Recommendation:** Define epoch as a global concept:
```
epoch = current_tick / EPOCH_LENGTH_TICKS
```
Where `EPOCH_LENGTH_TICKS` is a protocol constant (e.g., 720 ticks = 1 hour).
PulseProof.epoch = the global epoch during which the audit completed. Peers can
trivially verify currency: `|proof.epoch - my_epoch| <= 1`.

---

### M2. §23.14 Relationship Not Addressed

**Spec reference:** (missing)

**The problem:** The existing §23.14 Peer Audit Demand (in `core/logic/src/audit.rs`)
fires ~1 in 100 TXs with a 10-TX countdown. YPX-009 Silicon Pulse fires every 200
entries with a 60-tick deadline. Both are audit mechanisms. The spec doesn't discuss:
- Do they coexist?
- Can both fire simultaneously?
- Does §23.14 remain active, get replaced, or get absorbed into Silicon Pulse?

**Impact:** Implementation ambiguity. If both fire simultaneously, Lambda must handle
two concurrent audit obligations with different deadlines and formats.

**Recommendation:** Add a section (e.g., §10.6) clarifying the relationship:
- §23.14 = **inter-validator audit** (peer demands proof from another validator
  via trustmesh). Catches: validators not auditing each other.
- YPX-009 = **intra-node audit** (Core audits its own Lambda). Catches: dishonest
  Lambda within a single node.
- Both coexist — complementary, not redundant. Different targets, different deadlines.
- §23.14's peer-audit protocol is now fully implemented (v2.11.4). Lambda sends
  peer-audit requests via ANTIE email, Core verifies hashes, ban enforcement in AVM.

---

### M3. Client-Signed Records — Backward Compatibility Cutoff

**Spec reference:** §12.9.8

**The problem:** `client_pk` and `client_sig` are `Option` fields on `WalEntry`:
```rust
client_pk: Option<[u8; 32]>,
client_sig: Option<[u8; 64]>,
```

Records created before the upgrade have no signatures. During RangeSync/StatePull,
an attacker could fabricate records and claim they predate the upgrade (when
signatures weren't required). The receiving node can't distinguish "legitimately
old unsigned record" from "fabricated record claiming to be old."

**Impact:** Attacker can inject unsigned fabricated records for any wallet by
claiming they're from the pre-signature era. The client_sig protection is bypassed
for all historical data.

**Recommendation:** Define a `SIGNATURE_REQUIRED_FROM_TICK` protocol constant.
Records with `tick >= SIGNATURE_REQUIRED_FROM_TICK` MUST have valid `client_sig`
or be rejected. Records below this tick are accepted unsigned during bootstrap
only (trusted from bootstrap peers, verified by root hash majority). During
RangeSync (gap fill from untrusted peers), ALL records must have signatures
regardless of tick — gap fill peers are not bootstrap-trusted.

---

### M4. Historical Wallet State Lookup Not Specified

**Spec reference:** §4.4

**The problem:** For nonce audit entries, Lambda must:
> "Look up the target wallet's state at the specified tick from DB."

The current Lambda DB schema (`transaction_db`) stores current wallet state in the
`wallets` table and transaction history in `transaction_records`. But there is no
`wallet_state_at_tick(wallet_pk, tick)` index. Lambda would need to reconstruct
historical state by replaying transactions backward from current state, which is
expensive for wallets with long history.

**Impact:** Implementation may require schema additions to `transaction_db` (a new
`wallet_state_history` table indexed by `(wallet_pk, tick)`), or the nonce mechanism
needs to be redesigned to avoid historical lookups.

**Recommendation:** If nonce challenges survive C2 resolution (Option 1 or 2), add
a `wallet_snapshots` table:
```sql
CREATE TABLE wallet_snapshots (
    wallet_pk BLOB NOT NULL,
    tick INTEGER NOT NULL,
    balance INTEGER NOT NULL,
    state_id BLOB NOT NULL,
    PRIMARY KEY (wallet_pk, tick)
);
```
Lambda writes a snapshot on every state change. Storage: ~80 bytes per state change.
For 100,000 wallets with avg 10 changes each = ~80 MB. Acceptable.

---

### LOW Findings

### L1. W3 Float-to-Integer Conversion

**Spec reference:** §7.3

**The problem:** CC score is `u64` with saturating arithmetic. `pulse_score` is
`f64` (0.0–1.0). The formula `W3 * pulse_score` produces a float. Existing CC
score computation is pure integer:
```rust
pub fn compute_score(ticks_helped: u64, total_registrations: u64) -> u64 {
    ticks_helped.saturating_mul(SCORE_W1)
        .saturating_add(total_registrations.saturating_mul(SCORE_W2))
}
```

Mixing float into this requires either float-to-int conversion (platform-dependent
rounding) or redesigning pulse_score as fixed-point.

**Recommendation:** Use fixed-point: `pulse_score_pct: u64` (0–100).
```
W3 * pulse_score_pct / 100
```
Avoids float entirely. Consistent with existing saturating arithmetic pattern.

---

### L2. RangeSync — No Peer Disconnection on High Rejection Rate

**Spec reference:** §12.8.2

**The problem:** During RangeSync, a malicious peer could send 5 MB of fabricated
entries (up to ~50,000 records). Each requires Ed25519 sig verification (~50μs).
Total: ~2.5 seconds of CPU per response. Rate limiting (1 req/60s per peer) bounds
this, but there's no mechanism to disconnect persistently malicious peers.

**Recommendation:** Add to §12.8.5: "If > 90% of entries from a single peer fail
signature verification across 3 consecutive sync responses, disconnect and blacklist
the peer for `SYNC_BLACKLIST_HOURS` (default: 24 hours)."

---

### L3. PulseProof Size Not Signed

**Spec reference:** §5.1

**The problem:** The signature payload includes all PulseProof fields EXCEPT the
proof is self-contained — a relay node could strip or modify the PulseProof between
gossip hops. Actually, the signature covers all fields, so tampering would
invalidate it. This is fine.

**Actually:** On re-examination, this is not a real finding. The Ed25519 signature
covers the canonical serialisation. Tampering breaks the signature. **Dismissed.**

---

### INFO

### I1. Audit Buffer Not Crash-Persistent

**Spec reference:** §3.3

The audit buffer lives in AVM memory (storage region). If the validator crashes
mid-cycle, all accumulated entries are lost. On restart, the buffer starts from
scratch — another full cycle (up to 5.5 hours for idle validators) before the next
pulse. With `PULSE_MISS_TOLERANCE = 3`, frequent crashers accumulate misses.

This is not a vulnerability — it's an operational consequence that operators should
understand. The grace period and tolerance are correctly designed for this.

---

### I2. Future Enhancement: Re-execution Proof for §9.4 Shortcut

§9.4 acknowledges that Lambda can pass audits by reading stored results instead of
re-executing. The suggested enhancement (including a DMAP checkpoint at a specific
instruction count in TxDigest) is not specified. This should be tracked as a future
hardening item if the shortcut becomes a practical concern.

---

### Findings Dismissed During Analysis

1. **Accumulator manipulation via TX ordering.** Lambda controls TX ordering →
   influences accumulator → influences audit selection. Dismissed: BLAKE3 chain makes
   steering computationally infeasible. Lambda would need preimage/collision attacks.

2. **TxDigest missing wallet PKs.** Dismissed: `state_id` is SHA3-256 derived from
   wallet-specific data (including wallet_pk). Swapping wallets produces different
   state_id — caught by audit hash.

3. **StatePull bootstrap trust.** Malicious bootstrap peers fabricate records.
   Dismissed: client-signed records (§12.9) make fabrication impossible without
   wallet owner's key. Root hash majority check catches inconsistency. Edge case
   (attacker controls all bootstrap peers) is general network compromise, not
   protocol-specific.

4. **CorrectionHint flooding.** Dismissed: rate limited to 5/peer/hour, 20/hour
   global. CPU impact negligible.

5. **WAL checksum missing payload_len.** Dismissed: truncated payload produces
   different BLAKE3 hash regardless. Corrupted payload_len reads wrong bytes,
   also caught by checksum.

---

### Proposed Fix: Lambda-Held Buffer, Core-Verified Chain

### The Root Cause (Deeper Than C1)

C1 identified the wrong address. The real problem is deeper: **the AVM has no
persistent state between transaction executions.**

Each `AvmInterpreter::execute()` call is stateless — the RISC-V executor is created
fresh for each TX (`core/avm/src/interpreter.rs:255`, `execute_riscv()`). After a TX
completes, all AVM memory (including any hypothetical storage region) is discarded.

The spec's §3 design assumes Core writes to a persistent storage region across
multiple TX executions and reads it back later for audit. This is architecturally
impossible with the current AVM model, regardless of the address range chosen.

**Evidence:** `core/avm/src/interpreter.rs`:
```rust
pub fn execute(&self, inputs: PublicInputs) -> Result<PublicOutputs, AvmError> {
    // ...
    let result = self.execute_riscv(inputs)?;   // fresh executor each call
    return Ok(result.outputs);
    // executor (and all its memory) dropped here
}
```

### The Fix: Drop Dual-Region, Use Accumulator Pass-Through

Move the audit buffer out of AVM memory entirely. Lambda holds the buffer. Core
controls a 32-byte accumulator hash that Lambda transports through
PublicInputs/PublicOutputs.

**New fields:**

```rust
// In PublicInputs (Lambda → Core):
struct PublicInputs {
    // ... existing fields ...
    /// Current audit accumulator (32 bytes). Lambda passes through faithfully.
    /// Core verifies chain continuity.
    audit_accumulator: [u8; 32],
    /// Number of entries accumulated so far.
    audit_entry_count: u32,
    /// AuditResponse from Lambda (when responding to a prior AuditRequest).
    audit_response: Option<AuditResponse>,
}

// In PublicOutputs (Core → Lambda):
struct PublicOutputs {
    // ... existing fields ...
    /// Updated audit accumulator after this TX's digest is chained.
    audit_accumulator: [u8; 32],
    /// Updated entry count.
    audit_entry_count: u32,
    /// If entry_count >= AUDIT_CAP: Core emits AuditRequest.
    audit_request: Option<AuditRequest>,
    /// If AuditResponse was provided and verified: PulseProof data.
    pulse_proof: Option<PulseProofData>,
    /// If AuditResponse was provided and FAILED: restart signal.
    audit_failed: bool,
}
```

**Flow per transaction:**

```
TX N:
  1. Lambda passes {audit_accumulator, audit_entry_count} in PublicInputs
  2. Core validates the TX (existing CL2/CL3 flow)
  3. Core computes TxDigest from TX results
  4. Core chains: new_acc = BLAKE3("AXIOM_AUDIT_CHAIN" || old_acc || digest_payload)
  5. Core returns {audit_accumulator: new_acc, audit_entry_count: count+1}
  6. Lambda stores TxDigest alongside the new accumulator

TX 200 (buffer full):
  7. Core detects audit_entry_count >= AUDIT_CAP
  8. Core generates AuditRequest (Fiat-Shamir selection from accumulator)
  9. Core returns AuditRequest in PublicOutputs
  10. Lambda re-derives selected entries, returns AuditResponse on next TX

TX 201 (audit response):
  11. Lambda passes AuditResponse in PublicInputs
  12. Core verifies: computed_hash == expected_hash
  13. Match → Core emits PulseProofData, resets accumulator to [0;32]
  14. Mismatch → Core sets audit_failed = true → restart penalty
```

**What this changes in the spec:**

| Spec section | Change |
|-------------|--------|
| §3 (Dual-Region Memory) | **Replaced.** No storage region. Buffer in Lambda, accumulator in PublicInputs/Outputs. |
| §3.3 (What Lives in Storage) | **Replaced.** AuditBuffer struct moves to Lambda. Core only sees accumulator + count. |
| §3.4 (Nonce Challenges) | **Removed.** See below. |
| §3.5 (Chain Accumulation) | **Unchanged.** Same BLAKE3 chain formula, just executed via pass-through instead of persistent memory. |
| §4 (Audit Protocol) | **Mostly unchanged.** Trigger, selection, request, response, verification — all identical. Only the delivery mechanism changes (PublicInputs/Outputs instead of storage region reads). |
| §8 (Constants) | Remove `AVM_STORAGE_BASE`. Add `AUDIT_MAX_INTERVAL_TICKS`. |

### Drop Nonce Challenges, Add Time-Based Fallback

Nonce challenges (§3.4 Source 2) are eliminated. They were designed to fill the
buffer for idle validators, but they create three unsolvable problems (C2, H1, H2)
and misalign with the v0.3.3 integrity-first philosophy.

**Replacement: time-based fallback trigger.**

```rust
pub const AUDIT_MAX_INTERVAL_TICKS: u64 = 2160;  // ~3 hours
```

If `AUDIT_MAX_INTERVAL_TICKS` pass without reaching `AUDIT_CAP`, Core audits
whatever has accumulated. Lambda tracks the tick of the last audit and passes it
to Core in PublicInputs. Core checks: `current_tick - last_audit_tick >= AUDIT_MAX_INTERVAL_TICKS`.

**Why this is fine:**

Per v0.3.3, the primary mission is **integrity audit** — catching dishonest Lambda.
An idle validator that processes zero transactions isn't corrupting data. It's just
freeloading. The CC score (W1 + W2) already penalises freeloaders.

| Scenario | With nonces | With time-based fallback |
|----------|-------------|-------------------------|
| Busy validator (500 TX/hr) | Audit every ~24 min | Same — buffer fills from TXs |
| Normal validator (50 TX/hr) | Audit every ~2.3 hr | Audit every ~4 hr (slower, still audited) |
| Idle validator (0 TX/hr) | Audit every ~5.5 hr via nonces | Audit every ~3 hr (time trigger, empty audit = no-op pulse) |
| Idle Sybil | Forced to audit via nonces | No audit needed — zero TXs = zero damage = W3 degraded anyway |

The idle Sybil case is the one nonces were built for. But per the v0.3.3 reframe:
the threat is dishonest behaviour, not quantity of nodes. An idle Sybil that doesn't
process transactions can't pollute data. Its W1 accumulates but W2 stays zero — the
CC score calibration (W2=10 vs W1=1) already ensures honest nodes with registrations
outrank empty Sybils by 5x+.

### Security Properties of the New Design

**What Lambda CANNOT do:**

- **Modify past entries.** The accumulator is a BLAKE3 chain. Altering any entry
  changes all subsequent hashes. Core computes the chain — Lambda transports it.
  A Lambda that presents a tampered accumulator will diverge from Core's computation
  on the very next TX.

- **Skip entries.** Core increments `audit_entry_count` on every TX. If Lambda
  presents `count = 5` but Core has processed 6 TXs, Core detects the discrepancy.
  (The accumulator hash proves what Core has processed — Lambda can't rewind it.)

- **Predict audit selection.** The Fiat-Shamir seed includes the accumulator hash,
  which depends on all processed TXs. Lambda doesn't know the selection until
  Core emits the AuditRequest at TX 200.

**What Lambda CAN do:**

- **Delay.** Lambda could not pass the accumulator back (stall the audit). This
  delays the pulse → `PULSE_MISS` tolerance (3 cycles) → W3 degradation →
  eventual eviction (10 cycles). Lambda delays itself out of the network.

- **Reset.** Lambda could claim the buffer was lost (crash, restart). Same as delay
  — caught by `PULSE_MISS`. Frequent resets degrade W3 and trigger operational
  investigation.

- **Read stored results instead of re-executing.** Already acknowledged in §9.4.
  If Lambda was honest originally, reading correct results is fine — the audit
  verifies stored state matches Core's records. If Lambda cheated originally,
  the stored results are wrong and the audit catches it.

**The trust model is preserved:** Core decides, Lambda executes, Nabla observes.
Lambda is the carrier of the accumulator, not the authority over it.

### Findings Resolution Summary

| Finding | Severity | Resolution |
|---------|----------|------------|
| C1 (AVM address space) | CRITICAL | **Eliminated.** No dual-region needed. Buffer outside AVM. |
| C2 (nonce tick boundary) | CRITICAL | **Eliminated.** Nonces dropped. Time-based fallback instead. |
| H1 (wallet count divergence) | HIGH | **Eliminated.** Nonces dropped — no wallet indexing. |
| H2 (canonical wallet ordering) | HIGH | **Eliminated.** Nonces dropped — no wallet indexing. |
| H3 (spot check undefined) | HIGH | **Resolved.** Accept self-attested PulseProofs. Two-layer defense: DMAP catches modified Core, Silicon Pulse catches dishonest Lambda. Remove `PULSE_SPOT_CHECK_RATE` or make advisory. Document explicitly. |
| M1 (epoch undefined) | MEDIUM | **Open.** Still needs definition. Recommend global: `epoch = tick / EPOCH_LENGTH_TICKS`. |
| M2 (§23.14 overlap) | MEDIUM | **Open.** Still needs clarification. §23.14 = inter-validator, YPX-009 = intra-node. Coexist. |
| M3 (backward compat cutoff) | MEDIUM | **Open.** Still needs `SIGNATURE_REQUIRED_FROM_TICK` constant. |
| M4 (historical wallet state) | MEDIUM | **Eliminated.** Nonces dropped — no historical lookups needed. |
| L1 (W3 float-to-int) | LOW | **Open.** Use fixed-point `pulse_score_pct: u64` (0–100). |
| L2 (RangeSync disconnection) | LOW | **Open.** Add peer blacklist on high rejection rate. |
| L3 (PulseProof signing) | LOW | **Dismissed.** Signature covers all fields. |
| I1 (crash persistence) | INFO | **Noted.** Lambda-held buffer can be persisted to disk (improvement over AVM-only memory, which was always lost on crash). |
| I2 (re-execution proof) | INFO | **Noted.** Future hardening. |

### AVM Changes Required: None

The proposed fix requires **zero changes** to the AVM interpreter, RISC-V executor,
or memory system. The AVM continues to operate exactly as it does today — stateless
per-TX execution with DMAP checkpoint collection. The audit mechanism lives entirely
in the PublicInputs/PublicOutputs interface and Lambda's audit handler.

This is a significant simplification. The original spec's §3 required:
- New memory region constant
- Modified `merkle_root_below()` in Merkle tree builder
- Core ELF guest code changes for fixed-address ring buffer writes

The new design requires:
- Two new fields on PublicInputs (`audit_accumulator`, `audit_entry_count`)
- Two new fields on PublicOutputs (same + `audit_request`, `pulse_proof`, `audit_failed`)
- One BLAKE3 hash per TX in Core (chain accumulation)
- Lambda audit handler (same as before — §4.4 unchanged)

---

### Recommended Actions (Priority Order)

1. **Update YPX-009 spec to v0.4.0.** Apply the proposed fix:
   - Replace §3 (Dual-Region Memory) with Lambda-held buffer + accumulator pass-through.
   - Remove §3.4 Source 2 (nonce challenges). Add time-based fallback trigger.
   - Update §4 (Audit Protocol) for PublicInputs/Outputs delivery mechanism.
   - Update §8 (Constants): remove `AVM_STORAGE_BASE`, `NONCE_INTERVAL_TICKS`.
     Add `AUDIT_MAX_INTERVAL_TICKS`.
   - Update §5.2 (PulseProof verification): document self-attested nature,
     remove or make `PULSE_SPOT_CHECK_RATE` advisory, explain two-layer defense
     (DMAP + Silicon Pulse).
   - Update §9 (Attack Analysis): remove nonce-specific attacks, update §9.1
     idle Sybil analysis.
   - Update §11 (Implementation Plan): Phase 1 becomes PublicInputs/Outputs
     field additions (no AVM changes), Phase 2 becomes Core chain accumulation.
2. **M1: Define epoch** as global `tick / EPOCH_LENGTH_TICKS`.
3. **M2: Add §10.6** clarifying §23.14 coexistence.
4. **M3: Define `SIGNATURE_REQUIRED_FROM_TICK`** cutoff for client-signed records.
5. **H3: Update §5.2/§5.3** to explicitly document self-attested PulseProofs
   and the DMAP + Silicon Pulse two-layer defense.
6. **L1: Specify W3 as fixed-point** `pulse_score_pct: u64` (0–100).
7. **L2: Add peer blacklist** on high RangeSync rejection rate.

### Implementation Status (v0.5.0)

**Completed:**
- Item 1 (spec update to v0.4.0 → v0.5.0): Done — v0.4.0 introduced Lambda-held buffer design;
  v0.5.0 moves buffer into AVM, eliminating the Lambda self-audit flaw.
- §12 Nabla WAL audit: Implemented — BLAKE3 checksums, recent audit, deep scan, peer cross-verify.
- §12.8 StatePull + RangeSync: Implemented — bootstrap, gap-fill, WAL verify wire messages.
- §12.9 Client-signed state records: Implemented — Ed25519 sigs on all state entries, gossip propagation.
- Items 2-7 (M1 epoch, M2 §23.14, M3 signature cutoff, H3 PulseProofs, L1 W3 fixed-point, L2 blacklist): Incorporated into spec v0.4.0.
- §1-11 AVM audit buffer (v0.5.0): Implemented.
  - AVM-held audit buffer: accumulator + entry list held in interpreter state across executions.
  - BLAKE3 accumulator chain: each TX digest chained into accumulator; Lambda cannot alter between TXs.
  - Wallet cache with nonce challenges: AVM caches wallet state from processed TXs; nonce challenges
    sample from this local cache (avoids Lambda-controlled input for wallet state lookup).
  - DMAP spot-check binding: audit accumulator included in DMAP checkpoint Merkle commitment,
    binding audit state to execution proof.

**Pending:**
- Phase 3 (Lambda audit handler): Reads AuditRequest from PublicOutputs, re-derives selected entries,
  returns AuditResponse in PublicInputs. Requires no AVM changes — AVM emits request, Lambda answers.
- Phase 4 (Nabla PulseProof gossip): Lambda emits PulseProof on successful audit; Nabla gossips it
  to peers. Requires Lambda audit handler to be complete first.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
