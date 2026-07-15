# YPX-013: Console Engine — Core-Signed Governance Chain

**Version:** 1.0
**Date:** 2026-03-25
**Status:** Draft
**Depends on:** CL10 (Fan-Out), DWP Group Wallet, JFP Voting, TARDIS
**Yellow Paper:** §21.5, §21.8–§21.12
**White Paper:** §7.4, §7.8, J.13–J.17, G.1–G.8

---

## 1. Overview

The Console is a **parameter adjustment mechanism** (not governance) that manages L$ digit_version migration. It operates through a **Core-signed group wallet** that carries a generational chain — each Console term produces a new wallet inheriting the chain from its predecessor.

### 1.1 Design Philosophy

Console reuses all existing AXIOM infrastructure:

| Mechanism | Reuses |
|-----------|--------|
| Console wallet | DWP group wallet |
| Proposals & votes | 1-atom TXs with BLAKE3 hash in reference (JFP pattern) |
| Election announcements | CL10 Fan-Out |
| Seat assignments | Core-signed Console Certificate |
| Random seed | TARDIS tick + chain hash |
| Secret ballots | Nabla type-1 unnamed entries |

No new transport, no new voting infrastructure, no new consensus mechanism.

### 1.2 Constants

```rust
pub const CONSOLE_SIZE: usize = 15;
pub const TICKS_PER_YEAR: u64 = 6_311_520;        // 365 × 86400 / 5
pub const ELECTION_WINDOW_TICKS: u64 = 120_960;    // 1 week at 5s/tick
pub const ELECTION_RETRY_TICKS: u64 = 525_960;     // ~1 month cooldown
pub const MAX_ELECTION_ATTEMPTS: u8 = 3;            // after 3 failures, Console dies
pub const CONSOLE_CHAIN_DEPTH: u32 = 30;            // generations kept in full
pub const SELECTOR_COUNT: usize = 3;                // random selectors per election
pub const PICKS_PER_SELECTOR: usize = 5;            // each selector picks 5
pub const CONSOLE_MAX_PROPOSALS_PER_YEAR: usize = 2;
pub const CONSOLE_COOLDOWN_TICKS: u64 = 1_555_200;  // 3 months
pub const CONSOLE_VOTING_WINDOW_TICKS: u64 = 518_400; // 30 days
pub const CONSOLE_MAX_MAGNITUDE: u8 = 2;
pub const CONSOLE_COMPENSATION: u64 = 1;            // 1 AXC per full service year

// BLOOM_PHASE_OUT constitutional limits (YPX-018 §4.3)
// These bound what the Console can phase out, regardless of unanimous vote.
// The Console cannot override them — only a new Core ELF (worldline change) can.
pub const MIN_PHASE_OUT_AGE_TICKS: u64 = 50 * TICKS_PER_YEAR;   // 315,576,000 (50 years)
pub const MIN_PHASE_OUT_GRACE_TICKS: u64 = 5 * TICKS_PER_YEAR;  //  31,557,600 (5 years)
// Combined effect: any cheque issued in tick T cannot become unreachable
// before tick T + 55 years. Constitutional cheque-lifetime floor.
```

---

## 2. Console Certificate (Core-Signed Artifact)

The Console Certificate is a new signed artifact type, analogous to VBC/NBC but for the Console cohort.

### 2.1 Structure

```rust
pub struct ConsoleCertificate {
    /// Generation number (0 = genesis, increments each term)
    pub generation: u32,

    /// The 15 validator seats (validator_id for each)
    pub seats: Vec<[u8; 32]>,  // exactly CONSOLE_SIZE entries

    /// Term boundaries (TARDIS ticks)
    pub term_start_tick: u64,
    pub term_end_tick: u64,     // term_start_tick + TICKS_PER_YEAR

    /// Chain link to previous generation
    pub previous_link_hash: [u8; 32],  // BLAKE3 of previous ConsoleCertificate

    /// Election metadata
    pub election_attempt: u8,   // which attempt produced this (0 = first try)

    /// Console group wallet address
    pub group_wallet_id: String,

    /// Core signature over the certificate (Ed25519)
    pub core_signature: Vec<u8>,
}
```

### 2.2 Certificate Hash (Chain Link)

```
link_hash = BLAKE3("AXIOM_CONSOLE_CHAIN" ||
    generation.to_le_bytes() ||
    seats[0] || seats[1] || ... || seats[14] ||
    term_start_tick.to_le_bytes() ||
    term_end_tick.to_le_bytes() ||
    previous_link_hash)
```

### 2.3 Genesis Certificate (Generation 0)

At G1 ceremony:
- `generation = 0`
- `seats` = the 10 genesis validators (NOT padded to 15)
- `term_start_tick = 0`
- `term_end_tick = TICKS_PER_YEAR` (6,311,520)
- `previous_link_hash = [0; 32]` (no predecessor)
- `election_attempt = 0`
- Core signs the certificate

**Console is INERT at genesis.** With only 10 seats (below CONSOLE_SIZE = 15), no Console tasks can execute (Yellow Paper §21.10.4). The Console exists as a chain anchor but cannot perform digit migration, self-dismissal, or core update recommendations.

The Console becomes **active** only after the first election fills all 15 seats. This requires the network to grow beyond the 10 genesis validators — at least 5 more validators must join before the Console can function. **Implementation note (v2.11.13):** The 5-non-genesis minimum is enforced by the 15-seat requirement (CONSOLE_SIZE=15) — elections cannot succeed with fewer than 15 unique validator_ids. No explicit `start_nomination()` gate checks network size; the constraint is implicit in the election resolution logic (`resolve_election` requires 15 valid seats).

A Console group wallet is created with the 10 genesis validators as initial members. The 15 AXC injection from the pool occurs only when the Console reaches full capacity (15 seats).

---

## 3. Console Chain

### 3.1 Chain Model

Each Console generation produces one link:

```
Link #0 (genesis) → Link #1 (year 1) → Link #2 (year 2) → ... → Link #N
```

Each link is a `ConsoleCertificate`. The chain provides provenance — you can trace Console authority back to genesis, just like tracing AXC back to FACT #0.

### 3.2 Chain Compression

At depth `CONSOLE_CHAIN_DEPTH` (30 generations), older links are merkle-compressed:

```
Full links: [Link #(N-29), Link #(N-28), ..., Link #N]
Compressed: merkle_root(Link #0, Link #1, ..., Link #(N-30))
```

The compressed root is stored in a `compressed_ancestry` field on the earliest full link. This keeps the chain bounded regardless of system lifetime (~30 years of full history at annual rotation).

### 3.3 Storage

Console chain links are stored in Nabla as type-1 named entries:
- Key: `CONSOLE/gen/{generation}`
- Value: CBOR-encoded `ConsoleCertificate`

This makes Console history available to any node querying Nabla, without requiring Lambda state.

---

## 4. Election Process

### 4.1 Trigger

Election is triggered when TARDIS tick reaches the current Console's `term_end_tick`.

Lambda detects: `current_tick >= active_console.term_end_tick`

### 4.2 Phase 1: Nomination (CL10 Fan-Out)

1. Lambda builds a **Console Election Fan-Out** message:
   ```
   content_type: FANOUT_CONSOLE_ELECTION (0x0102)
   payload: {
       generation: current_generation + 1,
       attempt: N,           // 0-indexed
       max_attempts: MAX_ELECTION_ATTEMPTS,
       nomination_deadline: current_tick + ELECTION_WINDOW_TICKS,
       previous_chain_hash: current_console.link_hash,
   }
   ```
2. Core signs the Fan-Out (CL10 verification)
3. ANTIE relays to all validators via email

The Fan-Out message explicitly states the attempt number: "This is election attempt 2/3. If this election fails, the Console will be permanently dissolved for this Core version."

### 4.3 Phase 2: Self-Nomination

Validators self-nominate by sending a **1-atom TX** to the current Console group wallet:
- `reference` field contains: `BLAKE3("AXIOM_CONSOLE_NOMINATE" || validator_id || generation || attempt)`
- This is a standard CL1 TX — no new Core logic needed
- Lambda collects nominations from the Console group wallet's incoming TXs

Collection window: `ELECTION_WINDOW_TICKS` (1 week / 120,960 ticks)

### 4.4 Phase 3: Selector Selection

After the nomination window closes:

1. Compute deterministic seed:
   ```
   seed = BLAKE3("AXIOM_CONSOLE_ELECTION" ||
       election_tick.to_le_bytes() ||
       previous_console_chain_hash)
   ```

2. Select 3 unique indices from current Console's 15 seats:
   ```rust
   fn select_selectors(seed: &[u8; 32], console_size: usize) -> [usize; 3] {
       let mut indices = [0usize; 3];
       let mut used = BTreeSet::new();
       let mut offset = 0;
       for i in 0..3 {
           loop {
               let idx = u64::from_le_bytes(seed[offset..offset+8].try_into().unwrap())
                   as usize % console_size;
               offset += 8; // advance through seed bytes
               if used.insert(idx) {
                   indices[i] = idx;
                   break;
               }
           }
       }
       indices
   }
   ```

3. The 3 selected Console members are the **Selectors** for this election.

Nobody can predict who the Selectors will be until the election tick arrives and the previous chain hash is known.

### 4.5 Phase 4: Selector Picks

Each Selector picks 5 validators from the nomination list:

1. Selector reviews the nomination list
2. Selector submits picks as a **Nabla type-1 secret** (like JFP):
   - Key: `CONSOLE/picks/{generation}/{selector_validator_id}`
   - Value: encrypted list of 5 validator_ids
3. After all 3 Selectors submit (or deadline expires), picks are revealed

### 4.6 Phase 5: Resolution

1. Union all picks: up to 15 unique validator_ids
2. If union < 15:
   - Fill remaining seats by **randomly selecting** from current Console members (using same seed + offset)
   - This ensures continuity — old validators fill gaps
3. If total active validators < 15:
   - **Election FAILS** — not enough validators to form a Console
4. If any Selector fails to submit picks:
   - **Election FAILS** — incomplete selection

### 4.7 Phase 6: Core Signing

If election succeeds:
1. Lambda constructs the new `ConsoleCertificate`
2. Core signs it via **CL11** (new Core Logic mode)
3. CL11 validates:
   - Generation increments by exactly 1
   - `previous_link_hash` matches the current Console certificate's hash
   - All 15 seats are valid validator_ids (exist in Nabla)
   - `term_start_tick` == previous `term_end_tick`
   - `term_end_tick` == `term_start_tick` + `TICKS_PER_YEAR`
   - Selector picks are cryptographically verifiable
4. New Console group wallet created (inherits chain)
5. Certificate registered in Nabla
6. CL10 Fan-Out announces the new Console

### 4.8 Election Failure and Dissolution

If election fails:

```
failed_attempts += 1;
if failed_attempts >= MAX_ELECTION_ATTEMPTS {
    // No more Fan-Out messages. No more elections.
    // Console is permanently dissolved for this Core version.
    // Only a new Core ELF (new worldline) can reinstate Console.
}
```

**Implementation is simple:** Lambda stops sending election Fan-Out messages. No special flags, no complex state. The Console dies by silence, not by decree.

**This is a one-way ticket.** If the network cannot sustain 15 validators willing to participate across 3 monthly attempts (~4 months total), the Console is gone. Economically, this means AXIOM isn't generating enough activity to justify parameter management. The protocol continues to function — only L$ digit adjustment capability is lost.

**This MUST be clearly documented in:**
1. Yellow Paper §21.5 — "Console dissolves permanently after N failed elections"
2. Core CL11 — comment explaining the one-way nature
3. Every election Fan-Out message — "Attempt N/3. Failure = permanent dissolution."

---

## 5. Console Operations (During Term)

All Console operations pass through the Console group wallet, exactly like JFP.

### 5.1 Proposals

A Console member initiates a digit migration proposal:

1. **TX to Console group wallet:**
   - 1-atom TX
   - `reference`: `BLAKE3("AXIOM_CONSOLE_PROPOSE" || proposal_data_cbor)`
   - Proposal data: `{ direction, magnitude, rationale }`

2. **Lambda detects** the proposal TX in the Console wallet's incoming TXs
3. **CL10 Fan-Out** broadcasts the proposal to all Console members
4. **Voting window opens** (30 days / 518,400 ticks)

### 5.2 Voting (Objection-Based)

Consensus = absence of sustained objection (White Paper §G.5.3)

Each Console member may respond:
- **ACK** — 1-atom TX with `BLAKE3("AXIOM_CONSOLE_ACK" || proposal_id)` in reference
- **OBJECT** — 1-atom TX with `BLAKE3("AXIOM_CONSOLE_OBJECT" || proposal_id)` in reference
- **WITHDRAW** — 1-atom TX with `BLAKE3("AXIOM_CONSOLE_WITHDRAW" || proposal_id)` in reference

### 5.3 Finalization

When voting window expires:
- **No sustained objections** → Approved. Lambda updates `digit_version`. Fan-Out announces.
- **Any sustained objection** → Rejected. Fan-Out announces.
- **Missing votes (first time)** → Retry with same 24h window
- **Missing votes (second time)** → Console cohort dissolved. New election triggered.

### 5.4 Self-Dismissal (White Paper §7.7A)

Any Console member may initiate a vote to dismiss the current cohort:
- 1-atom TX with `BLAKE3("AXIOM_CONSOLE_DISMISS" || generation)` in reference
- Follows same objection-based voting
- If approved → cohort dissolved, new election triggered
- If no votes (second occurrence) → cohort dissolved automatically

### 5.5 Bloom Phase-Out (YPX-018 §4)

A Console member may propose retiring one or more frozen bloom eras from the tiered bloom memory architecture (YPX-018 §3). This is a coordination signal authorizing Nabla nodes to drop the era's authoritative hash records and bloom files at a future tick.

**Proposal payload:**

```rust
pub struct ConsoleProposal_BloomPhaseOut {
    /// Bloom eras scheduled for phase-out
    pub era_ids: Vec<u64>,

    /// TARDIS tick at which phase-out becomes effective
    pub effective_tick: u64,

    /// Human-readable rationale (storage pressure, archive coverage, etc.)
    pub rationale: String,
}
```

**Lifecycle:**

1. **Propose:** Member sends 1-atom TX to Console group wallet with `BLAKE3("AXIOM_CONSOLE_PHASEOUT" || cbor(payload))` in reference.
2. **Deliberate:** Standard 24h deliberation window, identical to other Console actions.
3. **Vote:** Unanimous ACK required. Any single OBJECT kills the proposal. Members vote with 1-atom TXs carrying `BLAKE3("AXIOM_CONSOLE_ACK" || proposal_id)` or `BLAKE3("AXIOM_CONSOLE_OBJECT" || proposal_id)`.
4. **Finalize via CL11:** On unanimous ACK, Lambda asks Core CL11 to validate and sign a `ConsoleCertificate` authorizing the phase-out. CL11 enforces the constitutional limits (§6.2.3). If any limit is violated, CL11 rejects — the Console *cannot* override.
5. **Fan-Out:** The signed certificate is broadcast via CL10 (`FANOUT_CONSOLE_BLOOM_PHASE_OUT`) to all Nabla nodes.
6. **Schedule:** Each Nabla node updates its Bloom Age Index for the affected eras: `status = ScheduledPhaseOut { effective_tick, console_cert_hash }`.
7. **Grace period:** From now until `effective_tick`, queries against the affected eras still return real answers BUT are tagged with a phase-out warning so cheque holders know to redeem.
8. **Effective:** At `effective_tick`, archive nodes are FREE to drop the era's full hash records. Light nodes are FREE to drop the era's bloom file. The Bloom Age Index entry remains forever, with status updated to `PhasedOut`. Future queries against the era return a signed `PHASED_OUT` response referencing the original `ConsoleCertificate` as proof.

**Why this is non-discretionary at Core but discretionary at Console:**

The Console's role is to *coordinate* when phase-out should happen — observing storage burden, archive coverage, public notice, real network conditions. These are exactly the kinds of judgments Console exists for (§21.10.7).

The Core's role is to *forbid* phase-out from violating the constitutional cheque-lifetime guarantee. CL11 cannot be bypassed by any vote, no matter how unanimous.

Per YPX-018 §4.4:
- `era.end_tick + MIN_PHASE_OUT_AGE_TICKS <= effective_tick` (era is at least 50 years past its close)
- `effective_tick - proposal_proposed_tick >= MIN_PHASE_OUT_GRACE_TICKS` (at least 5 years of warning)
- `effective_tick > current_tick` (phase-out is in the future)
- Era exists in the Bloom Age Index AND is not already `PhasedOut` or `ScheduledPhaseOut`

If a Console proposal violates any of these, CL11 returns an error and the certificate is never signed. The proposal effectively dies.

**Reversibility:** Until `effective_tick`, the Console may pass a subsequent proposal cancelling the phase-out (a `BLOOM_PHASE_OUT_CANCEL` action — deferred to a follow-up YPX, not in this version). After `effective_tick`, archive nodes may have already dropped data, so cancellation is no longer safe.

---

## 6. CL11 — Console Validation (Core Logic Mode)

New Core Logic mode for Console operations.

### 6.1 CL11 Inputs

```rust
pub struct CL11Inputs {
    /// The Console operation type
    pub operation: ConsoleOperation,

    /// Current Console Certificate (for chain verification)
    pub current_certificate: ConsoleCertificate,

    /// New certificate (for election finalization OR phase-out signing)
    pub new_certificate: Option<ConsoleCertificate>,

    /// Selector picks (for election verification)
    pub selector_picks: Option<Vec<SelectorPick>>,

    /// Bloom phase-out payload (for FinalizeBloomPhaseOut operation)
    pub phase_out_payload: Option<ConsoleProposal_BloomPhaseOut>,

    /// Current TARDIS tick (for grace-period validation)
    pub current_tick: u64,
}

pub enum ConsoleOperation {
    /// Finalize an election — sign new Console Certificate
    FinalizeElection,
    /// Verify a Console proposal/vote TX
    VerifyConsoleAction,
    /// Finalize a BLOOM_PHASE_OUT — sign authorization certificate (YPX-018 §4)
    FinalizeBloomPhaseOut,
}
```

### 6.2 CL11 Validation Rules

#### 6.2.1 FinalizeElection
1. `new_certificate.generation == current_certificate.generation + 1`
2. `new_certificate.previous_link_hash == hash(current_certificate)`
3. `new_certificate.seats.len() == CONSOLE_SIZE`
4. All seats are distinct validator_ids
5. `new_certificate.term_start_tick == current_certificate.term_end_tick`
6. `new_certificate.term_end_tick == new_certificate.term_start_tick + TICKS_PER_YEAR`
7. Selector picks are valid (each selector is a current Console member, picked from nomination list)
8. All 3 selectors submitted picks
9. Union of picks resolves to exactly 15 seats

#### 6.2.2 VerifyConsoleAction
1. TX sender is in current Console's seats
2. Reference field contains valid BLAKE3 commitment
3. TX target is the Console group wallet

#### 6.2.3 FinalizeBloomPhaseOut

These are the **constitutional limits** for the BLOOM_PHASE_OUT action (YPX-018 §4.3, §4.4). They are enforced by Core CL11 and **cannot** be overridden by any Console vote.

1. The proposing certificate must reference a valid `ConsoleProposal_BloomPhaseOut` payload.
2. Unanimous Console ACK MUST have been received within the standard deliberation window (existing rule, §5.2).
3. For every `era_id` in `phase_out_payload.era_ids`:
   - The era MUST exist in the Bloom Age Index (verified via Nabla TARDIS gossip).
   - `era.end_tick + MIN_PHASE_OUT_AGE_TICKS <= phase_out_payload.effective_tick`
     (the era must be at least 50 years past its close before it can be phased out)
   - The era MUST NOT already be in status `PhasedOut` or `ScheduledPhaseOut`.
4. `phase_out_payload.effective_tick - proposal_proposed_tick >= MIN_PHASE_OUT_GRACE_TICKS`
   (at least 5 years of grace between approval and effective tick)
5. `phase_out_payload.effective_tick > current_tick`
   (effective tick must be in the future)

If any rule fails, CL11 returns `E_CONSOLE_PHASE_OUT_INVALID` and refuses to sign. The proposal dies even if 15/15 voted ACK.

### 6.3 CL11 Outputs

- For `FinalizeElection`: signed `ConsoleCertificate` (election certificate)
- For `VerifyConsoleAction`: ACCEPT/REJECT
- For `FinalizeBloomPhaseOut`: signed `ConsoleCertificate` of variant `BloomPhaseOut` referencing the original payload, ready for CL10 Fan-Out as `FANOUT_CONSOLE_BLOOM_PHASE_OUT`

---

## 7. Console Compensation

Per White Paper §G.4:
- **15 AXC injected** from oracle reserve pool into Console group wallet at creation
- **1 AXC per member** distributed at term end if Console completed full term
- All members forfeit if ANY member fails (mutual accountability)
- **Dissolution:** remaining AXC in Console wallet returns to oracle reserve pool (same pattern as JFP — no locked/lost funds)
- Distribution and return are regular TXs through the existing pipeline

---

## 8. Integration with Existing Systems

### 8.1 Fan-Out Content Types

```rust
// Already defined (extend):
const FANOUT_CONSOLE_APPOINTMENT: u16 = 0x0100;  // → used for new Certificate announcement
const FANOUT_CONSOLE_RESIGNATION: u16 = 0x0101;  // → used for dissolution announcement

// New (this YPX):
const FANOUT_CONSOLE_ELECTION: u16 = 0x0102;     // Election open
const FANOUT_CONSOLE_RESULT: u16 = 0x0103;        // Election result

// New (YPX-018 §4):
const FANOUT_CONSOLE_BLOOM_PHASE_OUT: u16 = 0x0104;  // Bloom era phase-out scheduled
```

### 8.2 DWP/ Address Prefix

Console wallet uses the existing `DWP/` protocol address prefix:
- Console group wallet: `DWP/CONSOLE/{generation}`
- 1-atom TXs to this address bypass dust limit (already implemented)

### 8.3 Nabla Storage

Console chain stored as Nabla named entries:
- `CONSOLE/cert/{generation}` — ConsoleCertificate
- `CONSOLE/picks/{generation}/{selector_id}` — Selector picks (encrypted until reveal)

---

## 9. Yellow Paper Updates Required

The following Yellow Paper sections need updates:

1. **§21.5** — Add election mechanics (trigger, phases, failure), reference YPX-013
2. **§21.10.3** — Replace "uniform random sampling" with 3-pick-5 selector mechanism
3. **§21.10.4** — Add dissolution after MAX_ELECTION_ATTEMPTS (one-way ticket)
4. **§18.8.6** — Add FANOUT_CONSOLE_ELECTION (0x0102) and FANOUT_CONSOLE_RESULT (0x0103)
5. **New §21.13** — Console Chain specification (compression, Nabla storage)
6. **CL mode table** — Add CL11 for Console operations

---

## 10. Implementation Plan

### Phase 1: Core Types (core/logic/src/types.rs)
- `ConsoleCertificate` struct
- `ConsoleOperation` enum
- `SelectorPick` struct
- CL11 constants and error variants
- `FANOUT_CONSOLE_ELECTION`, `FANOUT_CONSOLE_RESULT` content types

### Phase 2: Core Logic (core/logic/src/console.rs — NEW)
- `compute_console_chain_hash()` — BLAKE3 with domain tag
- `verify_console_certificate()` — all 9 validation rules
- `select_selectors()` — deterministic 3-from-15 selection
- `resolve_election()` — union picks, fill gaps, verify 15 seats

### Phase 3: CL11 Mode (core/logic/src/modes.rs)
- `execute_cl11()` — FinalizeElection + VerifyConsoleAction paths
- Wire into `execute_core()` dispatch

### Phase 4: Lambda Console Engine (lambda/src/console_engine.rs — REWRITE)
- Replace DB-direct approach with group wallet TX approach
- Election state machine: trigger → nominate → select → pick → resolve → sign
- Failed attempt counter (simple integer, dies at MAX_ELECTION_ATTEMPTS)
- Compensation logic

### Phase 5: Integration
- Lambda consensus: detect election trigger from TARDIS tick
- CL10 Fan-Out: election messages with attempt number
- Nabla: store Console certificates
- ANTIE: relay election Fan-Out emails

### Phase 6: Tests
- Core: certificate chain validation, selector selection, election resolution
- Lambda: full election lifecycle, failure/dissolution, proposal via group wallet
- Integration: multi-validator election simulation

### Phase 7: BLOOM_PHASE_OUT Console Action (YPX-018 §4)
- Core types: `ConsoleProposal_BloomPhaseOut`, `MIN_PHASE_OUT_AGE_TICKS`, `MIN_PHASE_OUT_GRACE_TICKS`, `E_CONSOLE_PHASE_OUT_INVALID`
- Core CL11: `FinalizeBloomPhaseOut` operation, validation rules §6.2.3, certificate variant
- Lambda console_engine: detect `AXIOM_CONSOLE_PHASEOUT` reference in proposals, route through deliberation/voting/finalization, call CL11 for signing
- Lambda Fan-Out: `FANOUT_CONSOLE_BLOOM_PHASE_OUT` (0x0104)
- Nabla: receive Fan-Out, update Bloom Age Index, transition era status
- Tests:
  - CL11 rejects proposal under 50-year minimum age
  - CL11 rejects proposal with under 5-year grace
  - CL11 accepts properly aged + graced proposal
  - CL11 rejects re-phase-out of an already PhasedOut era
  - End-to-end: propose → ACK × 15 → CL11 sign → CL10 Fan-Out → Nabla age-index update

---

## 11. Security Considerations

### 11.1 Capture Resistance
- 3 random selectors each pick 5 → no single entity controls outcome
- Selector identity unknown until election tick (seed depends on tick + chain hash)
- Selectors are from CURRENT Console → they have skin in the game

### 11.2 Sybil Prevention
- Only validators can nominate (requires VBC/NBC)
- Minimum stake requirements apply (NablaStakeProof)
- Console group wallet validates membership through CL1

### 11.3 Coercion Resistance
- Selector picks submitted as Nabla secrets (encrypted until reveal)
- No individual can be targeted before selection is known
- Self-dismissal vote provides escape valve (WP §7.7A)

### 11.4 Graceful Death
- Console dissolution is permanent per Core version
- No backdoor, no restart, no override
- The protocol continues without Console — only L$ digit adjustment is lost
- New Core ELF (major update) is the only path to reinstatement

---

*The Console is an interface for coordination, not a source of authority. Its death, when it comes, is by design.*

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
