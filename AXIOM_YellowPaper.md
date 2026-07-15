# Lambda Protocol — Yellow Paper v2.13.00 (2026-05-08)

> **On naming.** AXIOM is the system. Lambda is the protocol — the invariant rules that govern witnessing, validation, and settlement. This document specifies Lambda: the protocol rules, validation logic, and implementation requirements that every conformant validator must follow.

**Project:** AXIOM (TrustMesh Architecture)  
**Status:** Final Specification  
**Audience:** Protocol implementers, validator operators, security auditors


## Critical Note for Implementers and Operators

**READ THIS FIRST**

### Gateway-Core-Lambda Architecture (CRITICAL)

**This is the MOST IMPORTANT thing to understand:**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=6pt, thick, minimum width=3cm, minimum height=1.2cm, align=center, font=\large},
    biarrow/.style={<->, very thick, >=stealth}
]
\node[box, draw=axiom-blue, fill=axiom-blue!8] (GW) at (-5,0) {Gateway};
\node[box, draw=axiom-gray, fill=axiom-gray!15] (CORE) at (0,0) {Core};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (LAM) at (5,0) {Lambda};
\draw[biarrow] (GW) -- node[above, font=\small] {CL2} (CORE);
\draw[biarrow] (CORE) -- node[above, font=\small] {CL2, CL3} (LAM);
\node[font=\scriptsize, text=axiom-gray] at (-5,-1) {Transport};
\node[font=\scriptsize, text=axiom-gray] at (0,-1) {Cryptographic Truth};
\node[font=\scriptsize, text=axiom-gray] at (5,-1) {Consensus + Policy};
\end{tikzpicture}
\caption{Architecture Overview --- Gateway handles transport, Core is the sole cryptographic authority, Lambda owns consensus and policy. All three communicate through Core.}
\end{figure}
```

**Detailed flow:**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=4cm, minimum height=0.7cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth},
    label/.style={font=\scriptsize, align=left, anchor=west, text=axiom-gray}
]
\node[box, draw=axiom-blue, fill=axiom-blue!8] (GW) at (0,0) {Gateway (Listens)};
\node[box, draw=axiom-gray, fill=axiom-gray!8] (CL2P) at (0,-1.5) {Core CL2 Pre-filter\\{\scriptsize current\_state = None}};
\node[label] at (3.5,-1.5) {Gateway calls this\\If REJECT: Lambda never sees};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (LAM) at (0,-3.2) {Lambda\\{\scriptsize S-ABR, k=3 consensus}};
\node[box, draw=axiom-gray, fill=axiom-gray!15] (CL2A) at (0,-4.9) {Core CL2 Authoritative\\{\scriptsize real stored state}};
\node[label] at (3.5,-4.9) {Lambda calls this\\State-dependent validation};
\node[box, draw=axiom-gray, fill=axiom-gray!15] (CL3) at (0,-6.6) {Core CL3 Witness\\{\scriptsize produces witness proof}};
\node[label] at (3.5,-6.6) {Lambda calls this\\Signs state transition};
\node[box, draw=axiom-gray, fill=axiom-gray!10] (CL5) at (0,-8.3) {Core CL5 Redeem\\{\scriptsize cheque verification + attestation}};
\node[label] at (3.5,-8.3) {Lambda calls this\\Double-redeem defense};
\node[box, draw=axiom-blue, fill=axiom-blue!8] (RESP) at (0,-9.8) {Response to Client};
\draw[arrow] (GW) -- (CL2P);
\draw[arrow] (CL2P) -- (LAM);
\draw[arrow] (LAM) -- (CL2A);
\draw[arrow] (CL2A) -- (CL3);
\draw[arrow] (CL3) -- (CL5);
\draw[arrow] (CL5) -- (RESP);
\node[font=\scriptsize, text=axiom-gray, anchor=west] at (3.5,-10.3) {CL4 (client-side receipt verification) not shown --- runs on client, not validator};
\end{tikzpicture}
\caption{Validator Processing Pipeline --- CL2 pre-filter $\to$ CL2 authoritative $\to$ CL3 witness $\to$ CL5 redeem. Core never initiates. CL4 runs client-side.}
\end{figure}
```

| Component | Role | Core Calls |
|-----------|------|------------|
| **Gateway** | Transport, pre-filter | CL2 pre-filter (`current_state = None`) |
| **Lambda** | Consensus, policy | CL2 (real state), CL3 (witness) |
| **Core** | Cryptographic truth | Responds only (stateless) |

**Two CL2 passes.** Gateway pre-filters with `current_state = None` — rejects malformed/invalid transactions before Lambda sees them. Lambda calls CL2 again with real stored state — this is the authoritative validation. Lambda then calls CL3 for witness production.

### Protocol vs Implementation vs Core (CRITICAL)

**This document defines a PROTOCOL, not a specific implementation.**

AXIOM provides reference implementations of Gateway (ANTIE) and Lambda as standard software. Validator operators can:

- **Adopt** the standard ANTIE and Lambda as-is
- **Build** their own Gateway or Lambda from scratch
- **Merge** Gateway and Lambda into a single binary
- **Modify** business logic in Lambda (fee policies, rejection rules, etc.)

**All of these are valid.** The protocol does not mandate how Gateway or Lambda are implemented internally. A validator could run a completely custom stack.

**What the protocol DOES mandate: everything goes through Core.**

Core is the universal checkpoint. Core is non-negotiable. Every transaction, regardless of which Gateway or Lambda implementation processes it, MUST pass through Core for:

- **CL2**: Transaction structure validation, signature verification, S-ABR overlap gate
- **CL3**: Witness proof generation, state_id computation
- **CL5**: Cheque redemption validation

No implementation may bypass Core. No implementation may make cryptographic decisions without Core. No implementation may compute state_ids, verify client signatures, or produce witness proofs independently.

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    header/.style={font=\small\bfseries, minimum width=5.5cm, minimum height=0.6cm, align=center},
    cell/.style={font=\small, minimum width=5.5cm, minimum height=0.4cm, align=left, anchor=north west}
]
\node[header, draw=green!60, fill=green!8] (H1) at (-3,0) {What Operators CAN Change};
\node[header, draw=red!60, fill=red!8] (H2) at (3,0) {What Nobody Can Change};
\node[cell] at (-5.75,-0.4) {Gateway implementation};
\node[cell] at (-5.75,-0.8) {Lambda business logic};
\node[cell] at (-5.75,-1.2) {Fee enforcement policy};
\node[cell] at (-5.75,-1.6) {Transport protocol (email/SWIFT)};
\node[cell] at (-5.75,-2.0) {Whether to merge Gateway+Lambda};
\node[cell] at (-5.75,-2.4) {Rejection policies for unpaid TX};
\node[cell] at (0.25,-0.4) {Core validation logic};
\node[cell] at (0.25,-0.8) {Core signature verification};
\node[cell] at (0.25,-1.2) {Core state\_id computation};
\node[cell] at (0.25,-1.6) {Core witness proof generation};
\node[cell] at (0.25,-2.0) {Core S-ABR overlap verification};
\node[cell] at (0.25,-2.4) {Core CL2/CL3/CL5 execution};
\draw[thick, axiom-gray!30] (-5.75,-0.3) rectangle (-0.25,-2.8);
\draw[thick, axiom-gray!30] (0.25,-0.3) rectangle (5.75,-2.8);
\end{tikzpicture}
\caption{Operator Freedom vs Protocol Invariants --- Gateway and Lambda are customizable; Core is not.}
\end{figure}
```

**The three-layer separation (Gateway / Lambda / Core) defines RESPONSIBILITIES, not deployment topology.**

A validator running a merged Gateway+Lambda binary still has two logical layers calling Core at the correct points.

| Layer | Responsibility | Core Calls |
|-------|---------------|------------|
| **Gateway** | Transport. Receive, parse, pre-filter, forward, respond. MUST NOT synthesize state. | CL2 pre-filter (`current_state = None`) |
| **Lambda** | Consensus and policy. k=3 coordination, wallet state, S-ABR, fee tracking. | CL2 (authoritative, real state), CL3, CL5 |
| **Core** | Cryptographic truth. Validation, signatures, state\_id, witness proofs. Sole producer of cryptographic outputs. | Responds only (stateless) |

**§ Nabla Boundary Rule (v2.11.16):**

Nabla is the citizen infrastructure layer — independent of the validator stack (Gateway/Lambda/Core). The data flow boundary is strictly **inward-only**:

| Direction | Allowed | Example |
|-----------|---------|---------|
| Nabla → Lambda | **Yes** (passive receive) | Ban alerts, registration callbacks, gossip-merged state |
| Lambda → ANTIE | **Yes** (file/IPC) | Lambda writes ban list file, ANTIE reads it |
| Lambda → Nabla | **No** | Lambda MUST NOT query or command Nabla |
| ANTIE → Nabla | **No** | ANTIE MUST NOT query or command Nabla |

**Rationale:** Nabla is a decentralized citizen network — any node may be hostile. If Lambda or ANTIE actively queries Nabla, a compromised Nabla node could stall, lie, or selectively delay responses to influence consensus outcomes. By receiving data passively (push-only from Nabla), the validator never blocks on Nabla availability and never trusts Nabla's response timing. Nabla's data is consumed as advisory input that Lambda verifies independently via Core. This also ensures validators operate correctly when Nabla is partitioned or unavailable — degraded mode (more scars, no confirmations) is safe; hard dependency on Nabla queries is not.



Core's cryptographic internals (hashing functions, commitment computation, key derivation) MUST be module-private. External components (Lambda, Gateway) MUST NOT have access to Core's raw crypto primitives. Core exposes ONLY:

- **Verification functions**: `verify_ed25519`, `verify_signature`, `verify_vbc_signature` — Lambda MAY verify signatures as consensus logic.
- **Computed outputs**: `commitment_hash`, `produced_state_id`, `state_hash` — returned in `PublicOutputs` from CL2/CL3.
- **Types and constants**: `genesis_sdid()`, `genesis_lineage_hash()`, `CORE_VERSION`.

Core MUST NOT expose: `blake3_hash`, `compute_witness_commitment`, `sha3_256_hash`, or any hashing primitive. If Lambda cannot access the ingredients, it cannot build fallbacks. The compiler enforces this boundary — `mod crypto` (not `pub mod crypto`) in Core's `lib.rs`.

**Rationale:** Every fallback computation in Lambda is a potential double-spend vector. If Lambda computes `commitment_hash` differently from Core (even by one field ordering difference), validators sign inconsistent commitments. "Can crash, must not lie" — if Core doesn't provide a value, Lambda MUST reject, never guess.

`commitment_hash` is returned by every validator in every successful witness response (not only when k=3 is reached). The client assembles k=3 and builds the receipt with Core's `commitment_hash`. Core rejects zero `commitment_hash` in `prev_receipts` — this closes the forgery bypass where omitting the field skipped signature verification entirely.

**Why this matters:**

- A custom Gateway that skips CL2? Protocol violation. Other validators will reject the outputs.
- A custom Lambda that skips fee checks? Fine. That's the operator's business decision.
- A custom Lambda that computes state_ids without Core? Protocol violation. State will diverge.
- A merged Gateway+Lambda that still calls Core for CL2 and CL3? Perfectly valid.

**Core is the constitution. Gateway and Lambda are the legislature and executive -- they can be structured however operators choose, but they cannot override Core.**


This Yellow Paper contains two types of specifications:

### What MUST Be Implemented (Cryptographically Enforced)

**Core transaction functionality:**
- Transaction format validation (Section 17)
- Signature verification
- Atom conservation (no value creation/destruction)
- Witness overlap requirement (chain of evidence)
- State machine transitions (Appendix C)

**These are enforced by protocol:** Invalid transactions are rejected. No negotiation.

### What SHOULD Be Implemented (Cannot Be Cryptographically Enforced)

**Validator protection mechanisms:**
- Forwarder deduplication (Section 18.4.2)
- PWV suppression rules (Section 18.4.2)
- Confirmation protocol (Appendix C §C.5)
- Fee discovery behavior (Section 19)
- Recovery cooperation (Section 17.4)

**These rely on economic incentives and validator self-interest.**

### Why We Document the "Should" in Such Detail

**The protocol cannot force validators to protect themselves.**

But if validators do NOT implement these mechanisms:
- Validator anonymity degrades (DWP intersection leakage: 50-80% vs 0.5-5%)
- Double-spend risks increase (without confirmation protocol)
- Network becomes vulnerable to attacks
- Individual validators lose protection

**This is why we include extensive reasoning, thought process, and social engineering analysis throughout this document.**

**For protocol implementers (engineers):**

You need to understand WHY each mechanism exists, not just WHAT it does.

Examples:
- "Why passive deduplication instead of active broadcast?" -> See Section 18.4.2.1
- "Why does canonical lock matter if querier can ignore it?" -> See Section 18.4.2.1 Q3
- "Why 99% uptime for Console?" -> See Section 21.5 and White Paper 7.4

**If you don't implement the full specification, you create vulnerable validators.**

**For validator operators:**

You need to choose validator software that implements the FULL specification, not just the minimum.

Questions to ask your validator software provider:
- Does it implement forwarder deduplication? (Section 18.4.2)
- Does it implement the confirmation protocol? (Appendix C §C.5)
- Does it implement PWV suppression rules? (Section 18.4.2)
- Does it follow the state machine transitions? (Appendix C)

**A validator that implements only the cryptographically-enforced parts is technically compliant but practically vulnerable.**

### Document Structure Note

**Technical specifications** (WHAT to implement):
- Clearly marked in each section
- Usually in code blocks or formal definitions

**Reasoning and thought process** (WHY it's designed this way):
- Integrated throughout
- Explains social engineering considerations
- Explains economic incentives
- Explains human behavior assumptions

**We keep both together because:**

Engineers who understand WHY are more likely to implement correctly.  
Operators who understand WHY are more likely to choose good implementations.  
Auditors who understand WHY can verify security properties.

**If you see a section that seems "too philosophical" or "too detailed":**

It's intentional. The reasoning is as important as the specification.

Lambda is designed around human behavior, economic incentives, and social dynamics -- not just cryptographic primitives.

**Understanding the reasoning is part of understanding the protocol.**


## 0. What This Document Is

This Yellow Paper is the **authoritative technical specification** for the Λ (Lambda) protocol within the AXIOM project.

**This document defines:**
- Protocol-level invariants and validation rules
- Transaction formats and state machine logic
- Validator behavior and witness requirements
- Core enforcement mechanisms
- Security properties and threat models

**This document does NOT define:**
- Economic rationale (see White Paper)
- DEED allocation details (see DEED Document)
- Enforcement philosophy (see Transaction Logic)
- Deployment procedures (see Bootstrap Guide)

**Document evolution:**

Earlier versions (v0.1-v0.6) were working drafts capturing architectural reasoning.  
The current version represents a mature specification suitable for implementation.

Sections marked [PENDING FINALIZATION] indicate parameters awaiting final values.  
Core mechanisms and invariants are stable.


## 0.1 Nomenclature

**For complete cross-document glossary, see: AXIOM_Glossary_CrossDocument.md**

This section provides quick reference for terms specific to Yellow Paper context.

**Core project terms:**

- **AXIOM**: Project name
- **Λ (Lambda)**: System architecture designation  
- **AXC**: Native cryptocurrency and public-facing brand
- **L$**: Operational currency (local accounting unit)
- **DMAP-VM**: AXIOM Virtual Machine (client-side execution environment)
- **Core**: Cryptographic sovereignty layer (eBPF bytecode)
- **Gateway** (syn: **Agent**): Protocol translation layer (email, P2P, morse code, etc.). See Section 16.8.1 for canonical definition. The terms "Gateway" and "Agent" are semantically equivalent and may be used interchangeably across documents.
- **Vault**: Isolated memory space for cryptographic operations

**Note on Wallet Tiers:**

Every identity carries a wallet pair, distinguished by the security tier
encoded in each wallet's `wallet_id` (see `wallet_id.rs::WALLET_ID_PARAMS`).
These are wallets identified by `wallet_id`, not key types:
- **Normal (Standard) wallet**: For connected-network operations (k=3)
- **Ark wallet**: For offline/partition scenarios (k=0)

**Specified in this document:**
- **Group Wallets**: Shared asset pools with percentage-based distribution (Section 30)

**Related Documents:**
- **White Paper (AXIOM v2.28)**: Economic rationale, system philosophy, and design intent
- **Transaction Logic**: Enforcement philosophy, validator state machine reasoning, and design mental models
- **Lambda DEED -- Developer Equity & Execution Deed**: Complete DEED specification, contributor onboarding, and economic sustainability model
- **AXC Distribution Mechanism**: Reserve Pool claim mechanism, policy rules, and witness discovery
- **Bootstrap Guide**: Genesis allocation, network initialization, and deployment procedures
- **Operational Manual**: Validator deployment, maintenance, and best practices (forthcoming)
- **Cross-Document Glossary**: Canonical definitions for all terms, abbreviations, and concepts
- **LAMBDA_CANONICAL_JSON_BYTES.md**: Canonical serialization specification (JCS profile)
- **LAMBDA_DETERMINISM_CONTRACT.md**: Determinism requirements and test vector format
- **LAMBDA_CONFORMANCE_CLI_SPEC.md**: Conformance testing tool specification
- **LAMBDA_SECURITY_THREAT_MODEL.md**: Security invariants and compliant adversary threat analysis
- **AXIOM_DESIGN_LockedSet.md**: Document authority map and interoperability floor index

**Implementation Documents:**
- **AXIOM_GUIDE_Core**: Complete axiom-core.elf implementation specification including VM selection, cryptographic operations, validation pipeline, Gateway IPC protocol, and VBC verification integration (Section 5.12)
- **AXIOM_DESIGN_VBC**: Validator Birth Certificate (Reality Anchor) complete specification including design rationale, verification algorithm, size control, renewal mechanism, historical receipt verification, and security analysis
- **AXIOM_GUIDE_AVM**: AXIOM Virtual Machine development guide for client-side implementations

**Gateway Protocol Documents:**
- **AXIOM_DESIGN_ANTIE**: Advanced Normalised Transmission Intermedia Extension - survival-grade email transport gateway specification
- **UNCLE_GATEWAY_SWIFT_INTEGRATION**: SWIFT integration specification for institutional financial gateways
- **AXIOM_DESIGN_COUSIN**: Social diffusion gateway specification

**This document:**

Official title: **Protocol Specification & Reference Implementation Guide**  
Common name: Yellow Paper

This Yellow Paper describes the Lambda system architecture within the AXIOM project.


## 1. Design Premise: Money for When Systems Fail

Lambda is not designed for:
- bull markets,
- speculative throughput races,
- governance theater,
- ideal network conditions.

Lambda is designed for:
- infrastructure collapse,
- political coercion,
- long-term partition,
- human threat models.

The core assumption is simple:

> **Civilization is not stable.  
> Money must survive instability.**


## 1A. Why You Can Trust AXIOM Money

> **Every AXC atom traces back to genesis through an unbreakable cryptographic chain. No money can be created from nothing. No transaction can reference a state that doesn't exist. This is enforced by Core — the sole cryptographic authority — and cannot be bypassed by any other component.**

This section exists so that anyone — developer, regulator, or citizen — can verify the trust mechanism without reading the entire specification.

### The Three Anchors

AXIOM money is secured by three interlocking checks, all enforced inside Core (the immutable validation binary). Lambda, gateways, validators, and clients cannot bypass any of them.

```{=latex}
\vspace{1em}
```

#### Anchor 1: State Chain — Every TX Must Follow the Previous One

Every transaction carries a `consumed_state_id` — the state it claims to spend from. Core checks this matches the last receipt's `produced_state_id`. If not, the TX is rejected.

```rust
// validation.rs — verify_state_id_chain()
//
// Every transaction carries a consumed_state_id — the state it claims to spend from.
// Core checks: this MUST equal the last receipt's produced_state_id.
// If it doesn't match, the TX is rejected. No exceptions.

fn verify_state_id_chain(tx: &Transaction, prev_receipts: &[Receipt]) -> CoreResult<()> {
    let last_receipt = &prev_receipts[prev_receipts.len() - 1];
    if !ct_eq(&tx.consumed_state_id, &last_receipt.produced_state_id) {
        return Err(ValidationError::InvalidStateId);
    }
    Ok(())
}
```

**What this means:** You cannot spend money that doesn't exist. You cannot replay an old transaction. Every spend must prove it follows from the last confirmed state. The comparison uses constant-time equality (`ct_eq`) to prevent timing attacks.

```{=latex}
\vspace{1em}
```

#### Anchor 2: FACT chain — Every Link Must Connect to the Previous Link

The FACT chain is the provenance record of every AXC atom. Core verifies each link connects to the previous one. A broken link rejects the entire chain.

```rust
// fact.rs — verify_fact_chain_inner()
//
// The FACT chain is the provenance record of every AXC atom.
// Each link records: who sent, who received, how much, and which validators witnessed it.
// Core verifies: link[i].previous_state_id == link[i-1].new_state_id
// If ANY link is broken, the entire chain is rejected.

for (i, link) in chain.links.iter().enumerate() {
    verify_fact_link(link)?;
    if i > 0 {
        let prev = &chain.links[i - 1];
        if !ct_eq(&link.previous_state_id, &prev.new_state_id) {
            return Err(ValidationError::FactChainBreak);
        }
    }
}
```

**What this means:** Money carries its history. Every AXC atom knows where it came from — back to genesis. You cannot forge a history, insert a fake link, or skip a link. The chain is cryptographically continuous.

```{=latex}
\vspace{1em}
```

#### Anchor 3: Checkpoint → First Link — Compressed History Still Chains

When the FACT chain is compressed, the checkpoint's `final_state_id` must match the first remaining link's `previous_state_id`. Compression cannot break the chain.

##### Travel-model checkpoint (SEC-07, 2026-06-12)

When a chain gets long, its oldest *settled* links are summarized into a **checkpoint** and discarded. The checkpoint's signatures are then the *only* thing vouching for that thrown-away history — so a forged checkpoint could fabricate provenance (claim non-genesis money traces to genesis). The protection is **3 distinct validator signatures** on every finalized checkpoint, gathered without requiring the validators to agree in any single round:

- **Why not gather them in one round?** Compression triggers on Nabla-confirmation status, which is **not** consensus-bound and reaches each validator asynchronously — so the *k* witnesses of one transaction legitimately disagree on what to compress. There is no synchronous quorum to sign a single checkpoint.
- **The proposal travels.** The first validator to see a chain reach `FACT_PROPOSE_TRIGGER` (depth **4**) writes a checkpoint **proposal**, signs it once, and **keeps the covered links** in place (the checkpoint is *provisional*). The proposal travels with the wallet's chain across its subsequent transactions.
- **Co-sign across rounds.** Each later validator that handles the chain re-verifies the still-present covered links against the proposal's `root_hash` and adds its own distinct signature (`validator_id`-deduped — a validator never signs the same proposal twice). With S-ABR witness overlap, ~1 new distinct validator signs per transaction, so a chain settles around depth **6–8**.
- **Finalize at 3.** Only once the proposal carries **`CHECKPOINT_SIG_THRESHOLD` = 3 distinct** validator signatures (= `MIN_FACT_WITNESSES`, the k=3 floor) are the covered links actually deleted (the checkpoint becomes *finalized*), keeping the live tail of `FACT_KEEP` = 3 links. The committed bytes (`root_hash`, the signatures) are unchanged across this transition. Only the transaction's *final* witnessing validator compresses, and only at round success — compression can never fire mid-round; the same threshold is **global, not per-k** (a per-k variant is unverifiable once the covered links are deleted, so colluding validators could forge it downward).

```rust
// fact.rs — verify_fact_chain_inner()
//
// PROVISIONAL (pending_links > 0): the covered links are still present. Verify
// them against the proposal's root_hash and accept accumulating signatures —
// the k=3 gate does NOT apply yet, because the real history is right there.
// FINALIZED (pending_links == 0): the covered links are gone, so the summary is
// the sole provenance — require 3 distinct signatures + the final_state_id anchor.

if let Some(ref checkpoint) = chain.checkpoint {
    if checkpoint.pending_links > 0 {
        // provisional: covered links retained at the front
        let m = checkpoint.pending_links as usize;
        if !ct_eq(&compute_checkpoint_root(&chain.links[..m]), &checkpoint.root_hash) {
            return Err(ValidationError::FactInvalidSignature);
        }
        verify_checkpoint_sigs(checkpoint)?;          // distinct + valid, no count gate
    } else {
        verify_checkpoint(checkpoint)?;               // require 3 distinct signatures
        if let Some(first_link) = chain.links.first() {
            if !ct_eq(&first_link.previous_state_id, &checkpoint.final_state_id) {
                return Err(ValidationError::FactChainBreak);
            }
        }
    }
}
```

**Why this is safe and never deadlocks:** the security-critical moment — deleting the real links — never happens below 3 distinct, independently-verified signatures; and because the links are *retained* while a proposal accumulates, a chain with a provisional checkpoint is fully verifiable the whole time, so no wallet ever wedges. A malicious proposer cannot lock in a lie: honest co-signers re-verify the still-present links before signing, so a bad proposal never reaches 3 and its links are never deleted. The freeze on bad provenance is forgery-proof and converges across rounds, not in a single synchronized vote.

**Residual:** depth is a *start signal*, not a hard deadline (no "reject if too deep" — only a generous `FACT_HARD_CEILING = 32` anti-abuse bound), so a chain legitimately grows a few links past 4 while it gathers its 3 signatures.

**What this means:** Even compressed history maintains the chain. You can verify that money traces back to genesis without storing the entire transaction history. The checkpoint is a cryptographic summary — signed by 3 real, independent validators, verifiable by anyone.

### The Complete Trust Chain

```
Genesis FACT #0 (signed at G1 ceremony)
    ↓ previous_state_id == checkpoint.final_state_id
Checkpoint (Dilithium-signed by 3 distinct validators — travel-model, SEC-07)
    ↓ previous_state_id == new_state_id
Link #N-2
    ↓ previous_state_id == new_state_id
Link #N-1
    ↓ previous_state_id == new_state_id
Link #N (most recent)
    ↓ consumed_state_id == produced_state_id
Current Transaction
```

Every arrow is a cryptographic equality check inside Core. Break any link and the transaction is rejected.

### What This Prevents

| Attack | How It's Prevented |
|--------|-------------------|
| **Creating money from nothing** | consumed_state_id must match a real previous state |
| **Double spending** | Each state can only be consumed once (seq increments) |
| **History forgery** | FACT chain links are cryptographically chained |
| **Checkpoint forgery** | A finalized checkpoint requires **3 distinct** validator Dilithium signatures, accumulated over rounds (SEC-07 travel model, `CHECKPOINT_SIG_THRESHOLD=3`); covered links are retained until then, so a forged or under-signed proposal never deletes the real history |
| **Replay attacks** | Protocol version + wallet_seq + nonce binding |
| **Cross-network attacks** | `AXIOM/2.11` protocol version in every signing message |

> The string `"AXIOM/2.11"` is the **wire-protocol version** baked into signing messages (`AXIOM_PROTOCOL_VERSION` in `core/logic/src/types.rs`). It is intentionally distinct from this document's version (front matter) and from `CORE_VERSION`. The wire-protocol version changes only when commitment shapes change in a way that breaks cross-version replay protection; the document version tracks specification edits.

### Anchor 4: Supply Integrity — No Minting, No Inflation

```rust
// genesis_integrity.rs — The total supply is a compile-time constant.
// It cannot be changed without recompiling Core (new ELF = new worldline).
pub const GENESIS_POOL_TOTAL: u64 = 100_000_000;

// validation.rs — verify_balance()
// Every send MUST have amount > 0 and amount <= sender's balance.
// checked_sub() returns None on underflow — no silent wrapping, no negative balances.
fn verify_balance(tx: &Transaction, balance: u64) -> CoreResult<()> {
    if tx.amount == 0 {
        return Err(ValidationError::ZeroAmount);       // no zero-amount spam
    }
    if tx.amount > balance {
        return Err(ValidationError::InsufficientBalance); // can't spend more than you have
    }
    Ok(())
}

// validation.rs — compute_produced_state_id()
// New balance = old balance - amount. Uses checked_sub (panics on underflow).
let new_balance = current_balance.checked_sub(tx.amount)
    .ok_or(ValidationError::InsufficientBalance)?;
```

**What this means:** The total supply (100,000,000 AXC) is a constant baked into the binary. No function exists to increase it. Every transaction subtracts from the sender — `checked_sub` makes underflow mathematically impossible. Money can only move, never be created.

### Where This Code Lives

All three anchors are in `core/logic/src/` — the immutable validation binary that compiles to a single RISC-V ELF. This ELF has ONE fingerprint. Every validator runs the same code. The code shown above is the actual production code, not a simplified version.

- `validation.rs:410-422` — Anchor 1 (state chain)
- `fact.rs:170-187` — Anchor 2 (FACT chain continuity)
- `fact.rs:158-167` — Anchor 3 (checkpoint anchoring)

> **If you verify nothing else about AXIOM, verify these three functions. They are the reason AXIOM money is real.**


## 2. Dual-Currency Separation: AXC and L$

### 2.1 Why Two Assets Exist

Lambda separates monetary roles that most systems conflate:

- **AXC** -- global reserve, fixed supply, value anchor
- **L$** -- operational currency, high velocity, local distortion allowed

This separation exists because:
- store-of-value and medium-of-exchange have opposing stability requirements
- coupling them amplifies volatility under stress
- partitions demand local flexibility without global contamination

### 2.2 AXC Invariants

AXC obeys strict conservation rules:
- fixed total supply
- no inflation-based rewards
- no burns for economic tuning
- no protocol-level redistribution

Every movement of AXC is a transfer, never a creation or destruction.

### 2.3 L$ as Display Unit

L$ is the **display denomination** of AXC, not a separate currency.

**Three layers — one currency:**

| Layer | Name | Used by | Purpose |
|-------|------|---------|---------|
| Protocol | **atoms** | Code only | Integer arithmetic, no floating point. All `amount: u64` fields are in atoms. |
| Market | **AXC** | Exchanges, specs | Fixed-supply asset. 100,000,000 AXC total. Market-readable denomination. |
| User | **L$** | Wallet UI, invoices | Human-readable display. Scaled by digit_version for usability. |

**Conversion constants:**

```
1 AXC = 10^10 atoms (10,000,000,000 atoms)
1 AXC = 10^N L$  (where N = digit_version, managed by Console §7.7)

At digit_version = 0:  1 AXC = 1 L$
At digit_version = 3:  1 AXC = 1,000 L$
At digit_version = 6:  1 AXC = 1,000,000 L$

Total supply: 100,000,000 AXC = 10^18 atoms (fits u64)
Dust limit:   500,000 atoms = 0.00005 AXC (protocol.toml)
```

**Example (digit_version = 3):**
```
User sees:       "50 L$"
Market value:    0.05 AXC
Protocol stores: 500,000,000 atoms  (0.05 × 10^10)
```

**Example (digit_version = 0):**
```
User sees:       "1,000 L$"
Market value:    1,000 AXC
Protocol stores: 10,000,000,000,000 atoms  (1,000 × 10^10)
```

**Why atoms exist:** Floating-point arithmetic is non-deterministic across platforms. Two validators computing the same transaction could get different results. Atoms guarantee every validator computes identical integer results. Atoms never appear in user-facing text — users see L$, markets see AXC.

**Ark-Mode "inflation":**

During network partitions, local market prices may rise (e.g., water costs 10 `L$` instead of 1 `L$` in disaster zones). This is **economic inflation** (price increases due to scarcity), not **monetary inflation** (supply expansion).

**Critical distinction:**
- Prices change: 1 bottle of water = 1 `L$` -> 10 `L$` (scarcity)
- + Supply does NOT change: AXC atom count remains conserved
- Transactions remain valid: If disaster survivors paid 10 L$ for water, those transactions are honored at face value

**Protocol behavior:**

L$ serves as a shock absorber for local economic volatility:
- Allows price flexibility during partitions
- Maintains psychological continuity (people think in "dollars")
- Preserves AXC's role as the ultimate settlement layer

When partitions merge, local price distortions are accepted as historical fact. The protocol does not attempt to "correct" prices retroactively.


## 3. Validators Are Humans (Not Abstract Actors)

### 3.1 Human Threat Model

Validators:
- have physical bodies,
- live in jurisdictions,
- can be threatened, arrested, coerced, or disappeared.

Therefore:
- validator identity must be hideable,
- validator participation must be optional,
- validator exit must be immediate.

Any system that assumes validators are always available is invalid.

### 3.2 Human-Machine Separation

The protocol enforces a strict information barrier between:
- **Machine layer**: Validator software knows cryptographic truth
- **Human layer**: Operator knows only operational state

**Design principle:**

Validators must be able to participate in consensus **without** operators knowing their role in specific transactions.

**Implementation requirements:**

1. **Local storage opacity**
   - Transaction records stored in encrypted/obfuscated format
   - No operator-accessible query interface for "which transactions did I witness"

2. **Automated voting**
   - Voting logic executes without human intervention
   - Operators see "vote request received" but not vote content or outcome

3. **Role ambiguity**
   - When notified as PWV member, validator software knows if it's real or decoy
   - Operator interface shows only "PWV participation request"
   - No distinction visible to human operator

**Rationale:**

If operators cannot know their validator's role, they cannot be:
- coerced into revealing witness identity
- held accountable for specific transactions
- targeted for their validator's participation

This transforms the threat model from "protect the human" to "protect the human's knowledge."

**What validators cannot be forced to reveal:**
- Whether they witnessed a specific transaction (might be decoy)
- How they voted (automated, no human oversight)
- Who else witnessed the transaction (only know PWV set, not real vs decoy)

**The core insight:**

> Plausible deniability is not a legal defense.  
> It is an information architecture.


## 4. Validator Lifecycle

### 4.1 Admission

- Any entity may become a validator by staking **500 AXC**
- No committees
- No permissioning
- Optional external certification (not enforced by protocol)

**Cross-reference:** Section 25.5 (Staking Requirement)

### 4.2 Active State & Economic Model

Validators:
- participate in consensus
- respond to queries
- may generate PWVs
- witness transactions (earning fees)

**Economic model:**

Validators earn income through **transaction witnessing fees**, not protocol inflation.

**Fee structure:**
- Each validator sets their own fee rate (e.g., 0.08% L$)
- Fees are charged per-transaction-per-validator
- Multiple validators = multiple fees (additive)

**Example:**
```
Transaction: Alice -> Bob, 1000 L$
Witnesses: Validator A, B, C

Validator A fee rate: 0.08%
Validator B fee rate: 0.02%  
Validator C fee rate: 0.10%

Fees charged:
- Validator A: 1000 × 0.0008 = 0.8 L$
- Validator B: 1000 × 0.0002 = 0.2 L$
- Validator C: 1000 × 0.0010 = 1.0 L$
- Total: 2.0 L$

Deduction from sender's declared amount:
- Alice declares transfer: 1000 L$
- Total fees deducted: 2.0 L$
- Bob receives: 998 L$
- Alice's balance decreases: 1000 L$
```

**Fee rate commitment:**

Validators publish fee rates with time-to-live (TTL):
- Rate guaranteed valid until TTL expiration
- Clients select validators based on published rates
- Violating TTL = reputation damage (not protocol enforcement)

**DEED allocation (time-limited):**

During the DEED period (10 years Protocol, 5 years Implementation), validators must allocate a portion of their fees to protocol development teams. This is what enables AXIOM to operate without venture capital.

**Allocation ratios defined in "Lambda DEED -- Developer Equity & Execution Deed" document.**

Example (illustrative, not final):
```
Validator fee earned: 1.0 L$

DEED allocation (per DEED document):
- Protocol Development Team: 0.1 L$ (10%, active 10 years)
- Implementation Team: 0.1 L$ (10%, active 5 years)
- Validator keeps: 0.8 L$ (80%)
```

**Complete DEED specification:**  
See "Lambda DEED -- Developer Equity & Execution Deed" for:
- Exact allocation percentages
- Contributor model and onboarding
- Economic sustainability analysis
- Why this eliminates VC dependency

**Protocol-level enforcement:**  
See Section 20 for Core validation logic and transaction format.

**Post-DEED era:**

After DEED time limits expire:
- Protocol no longer enforces fee allocation
- Validators retain 100% of fees
- Market-driven fee models emerge
- Validator software developers may implement custom fee structures

**Critical principle:**

Validator income derives from real utility (witnessing transactions), not artificial inflation. This ensures:
- Economic sustainability scales with network usage
- No dilution of AXC holders
- Market pressure keeps fees competitive

**Cross-reference:** Section 25 (Validator Compensation Model)

### 4.3 Retirement

Retirement is a **business process** -- a validator chooses to stop accepting new work.

**Characteristics:**

| Aspect | Description |
|--------|-------------|
| **Motivation** | Economic (e.g., income below operating costs) |
| **Trigger** | Stake withdrawal |
| **Protocol Response** | Normal MV inheritance chain update |
| **Penalty** | None |
| **Delay** | None -- immediate |

Retired validators:
- remain referenced in historical PWV sets
- are represented by meta-validators if needed
- can withdraw 500 AXC stake immediately

**Cross-reference:** Section 10.8 (Absence / Retirement Inheritance Semantics)

### 4.4 Exit as Security Primitive

Exit is a **security defense** -- a validator must stop to prevent coerced signing.

**Characteristics:**

| Aspect | Description |
|--------|-------------|
| **Motivation** | Security (node physically compromised, vulnerability detected, coercion) |
| **Trigger** | Physical disconnection of signing capability |
| **Protocol Response** | Fail-Closed logic activation |
| **Purpose** | Prevent coerced signatures from corrupting state |

#### 4.4.1 Retirement vs Exit

| Concept | Retirement | Exit as Security Primitive |
|---------|------------|---------------------------|
| **Nature** | Business process | Security defense |
| **Motivation** | Economic considerations | Security considerations |
| **Example Trigger** | Revenue below EMVT | Node physically controlled, vulnerability detected |
| **Protocol Response** | Normal MV inheritance | Fail-Closed, prevent coerced signing |

#### 4.4.2 Exit Scenarios

**Scenario 1: Physical Compromise**
```
Validator detects unauthorized physical access to node
' Immediate exit (power off, network disconnect)
' Node cannot be coerced to sign malicious transactions
' System treats validator as absent (not malicious)
' MV inheritance handles continuity
```

**Scenario 2: Vulnerability Detection**
```
Validator discovers critical software vulnerability
' Immediate exit before exploitation
' Fail-Closed: no signatures issued
' Better to be absent than compromised
```

**Scenario 3: Legal/Physical Coercion**
```
Validator under pressure to sign specific transactions
' Exit removes signing capability entirely
' Coercer cannot force action from non-existent capability
' Silence is safer than compliance
```

#### 4.4.3 Design Rationale

This design ensures AXIOM Lambda is a system **designed for survival**, not merely for profit.

As stated in 15:
> "Lambda is not designed for trust. It is designed for survival."

Exit as a security primitive means:
- Validators can always choose non-participation
- Coercion cannot force incorrect action
- The system prefers absence to corruption

**Cross-reference:** Section 23 (Failure Handling and Fail-Closed Semantics)

#### 4.4.4 Retirement, Inactivity, and Disappearance

Three distinct validator states with different protocol handling:

| State | Trigger | Protocol Signal | Recovery |
|-------|---------|-----------------|----------|
| **Retirement** | Stake drops below 500 AXC | Observable state change | Re-stake >= 500 AXC |
| **Inactivity** | Stops processing (Silicon Pulse divergence) | Local detection via audit chain | Resume operations |
| **Disappearance** | Offline > 72 hours | Removed from databases | Full re-onboarding (3 MV-sets) |

**Retirement (Stake < 500 AXC):**

When a validator's stake drops below 500 AXC:
- Validator status is invalidated (see 25.5.4 Anti-Rollback)
- Cannot participate in witnessing
- Must re-stake >= 500 AXC to resume operations
- No penalty -- stake is fully returnable

**Inactivity Detection (Silicon Pulse — replaces ping):**

AXIOM does not use peer-to-peer ping. Liveness is verified through Core-initiated audits:

1. **Silicon Pulse (§YPX-009):** Core accumulates an Argon2id→BLAKE3 audit chain over every TX processed. Periodically, Core issues a `PulseAuditRequest` — Lambda must retrieve raw TX digests from its database and return them. Core replays the Argon2id chain over the returned data and compares the hash. If Lambda's stored data diverges from Core's accumulated chain, the validator was lazy or dishonest.
2. **Cross-validator verification:** Core can request that Lambda query a selected peer validator's audit proof via Nabla. This replaces ping — instead of asking "are you alive?", it asks "can you prove you did real work?"
3. **Natural disappearance:** Validators that stop processing TXs stop appearing in KVH hints and Nabla registrations. No announcement needed — absence is self-evident through lack of participation.

**Disappearance (Offline > 72 hours):**

If a validator remains inactive for more than 72 hours:
1. Remove from local validator database
2. Stop monitoring (no need for continuous testing)
3. If validator comes back online -> **must re-onboard** through 3 independent MV-sets (10.5)

**Why 72 Hours:**

- Allows for temporary outages (maintenance, network issues, time zone gaps)
- Short enough to prevent stale validator lists
- Long enough to distinguish intentional exit from temporary problems

**Disappearance as Protection:**

Disappearance preserves **ambiguity**:

| Observation | Possible Causes |
|-------------|-----------------|
| Validator offline | Maintenance? Network issue? Intentional exit? Coercion? |
| No protocol signal | Exit and inactivity are indistinguishable |

This ambiguity protects:
- The exiting validator (cannot be targeted for "leaving")
- Remaining validators (cannot be pressured to explain peer's absence)
- Historical participants (past actions remain valid)

> **Disappearance is not abuse. It is defense.**

### 4.5 Time Parameters Summary

All time-based parameters affecting validator lifecycle and operations.

#### Terminology Note: "Epoch"

The term **"epoch"** appears throughout this document and in broader cryptocurrency discourse. In AXIOM:

> **Epoch is a colloquial term for a discrete time interval.**

AXIOM does NOT use epoch as a protocol-enforced synchronization boundary (unlike some blockchain systems with fixed block epochs).

**AXIOM's time boundaries:**

| Context | Time Boundary | Duration |
|---------|---------------|----------|
| **DEED Phases** | Phase A -> Phase B | 5-10 years |
| **Console** | Cohort term | Until dissolution or rotation |
| **Validator lifecycle** | Inactivity -> Disappearance | 72 hours |

Each mechanism defines its own time boundaries independently. There is no global epoch clock for transaction processing.

#### 4.5.1 Validator Lifecycle Timelines

| Parameter | Duration | Description | Reference |
|-----------|----------|-------------|-----------|
| **Inactivity Threshold** | 72 hours | Time before inactive validator is removed from local database | 4.4.4 |
| **Re-onboarding Required** | After 72h offline | Validator must obtain 3 MV-set validation to resume | 4.4.4, 10.5 |
| **Retirement** | Immediate | When stake drops below 500 AXC, status invalidated immediately | 25.5.4 |

#### 4.5.2 Voting and Deliberation Timelines

| Parameter | Duration | Description | Reference |
|-----------|----------|-------------|-----------|
| **Console Deliberation Window** | 24 hours | Time for Console members to ACK/OBJECT proposals | 21.5.4 |
| **JFP Offline Threshold** | 12 hours | After ACK, if offline >12h, vote becomes RANDOM | 8.1 |
| **Retry Window** | 24 hours | If votes missing, automatic retry with same window | 21.5.4 |

#### 4.5.3 Operational Timelines

| Parameter | Duration | Description | Reference |
|-----------|----------|-------------|-----------|
| **PWV Cache TTL** | 24-48 hours | How long PWV set information is cached | 18.4 |
| **Claim Cooldown** | 24 hours | Minimum time between DEED claims | 22 |
| **Fee TTL** | Variable | Validator-set fee rate validity period | 19.3 |

#### 4.5.4 Design Rationale

All time parameters are designed with these principles:

1. **Time Zone Coverage** -- 24h windows ensure global participation opportunity
2. **Coercion Resistance** -- Delays allow pressure to surface before action
3. **Operational Reality** -- 72h accommodates maintenance, outages, emergencies
4. **No Ambiguity** -- Fixed durations, not "reasonable time" or discretionary periods

#### 4.5.5 Temporal Invariants

Across all timelines, the following invariants MUST hold:

| Invariant | Description | Enforcement |
|-----------|-------------|-------------|
| **No Forced Immediacy** | No participant is forced to act immediately | 24h minimum windows |
| **No Infinite Obligation** | No obligation persists indefinitely | 72h disappearance rule |
| **No Permanent Exposure** | No action creates permanent exposure | PWV ephemeral, exit always available |
| **Time Never Weaponized** | Time never becomes a weapon against exit | Immediate withdrawal, no lock-ups |

These invariants are **foundational** -- they cannot be overridden by any mechanism in the protocol.

**Verification:**

Any proposed protocol change MUST be evaluated against these four invariants. A change that violates any invariant is rejected regardless of other benefits.


## 5. Decoy Witness Protection (DWP)

### 5.1 Core Idea

Every query creates ambiguity.

If someone asks:
> "Who validated this transaction?"

The system must make that question dangerous to answer.

### 5.2 Query Cost

- DWP judicial query costs **1 AXC** 
- Implementation: `DQF_ATOMS = 10,000,000,000` atoms in `lambda/src/dwp_engine.rs`
- Payment is a real k=3 witnessed transaction (unforgeable proof)
- Payment creates a DWP group wallet: requester 50% (5000 bps), PWV members split 50% (5000 bps), pool receives unclaimed after 365 days
- Net cost to requester: 0.5 AXC (50% recoverable after JFP resolution)
- No mint, no burn — unclaimed shares return to System Reserve Pool

The cost exists to:
- prevent spam,
- make coercion expensive,
- scale attack cost with AXC value.

This redistribution mechanism is **not** protocol inflation -- it is a transfer of existing AXC from querier to validators, creating economic incentive without supply expansion.

#### 5.2.1 Query Payment Proof (stamp.v1)

Query payment MUST be proven cryptographically. The protocol uses a **stamp** mechanism:

**QueryPaymentProof Structure:**

```
record QueryPaymentProof:
  scheme: "stamp.v1"
  stamp_id: string           # Unique identifier
  payer_pk: PubKey           # Who paid
  issuer_pk: PubKey          # Validator who issued the stamp
  issued_at: UnixTime
  expires_at: UnixTime
  stamp_sig: Sig             # Issuer signature over STAMP_ROOT
  payer_sig: Sig             # Payer binds (query_id || stamp_id)
```

**Validation Requirements:**

1. **Stamp validity:** `stamp_sig` MUST verify against `issuer_pk`
2. **Expiration:** `Now() <= expires_at`
3. **Binding:** `payer_sig` MUST bind the stamp to the specific `query_id`
4. **Replay protection:** `stamp_id` MUST NOT have been seen before

**Binding Mechanism:**

```
bind_root = Hash(query_id || stamp_id)
payer_sig = Sign(payer_sk, SIGMSG("QSTAMP_BIND", bind_root))
```

This prevents stamp theft -- a stamp purchased for one query cannot be reused for another.

**Replay Protection (Bounded):**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **STAMP_REPLAY_MAX_ENTRIES** | 200,000 | Maximum seen stamps |
| **STAMP_REPLAY_RETENTION** | 48 hours | TTL for replay cache |

Forwarders MUST maintain a bounded cache of seen `stamp_id` values. If cache is full, queries MAY be dropped (survival-first behavior).


## 6. Validator Sets

### 6.0 Active Validator Set (AVS)

The **Active Validator Set (AVS)** is the set of validators considered active at a given protocol epoch.

**Membership Criteria:**

| Requirement | Specification |
|-------------|---------------|
| **Stake** | Balance >= 500 AXC |
| **Onboarding** | Validated by 3 independent MV-sets (10.5) |
| **Status** | Not invalidated (no Invalidation Notice in effect) |

**Key Properties:**

- Membership is determined by **protocol state**, not identity registry
- No central authority maintains the AVS
- Each node computes AVS locally based on observed state
- AVS changes dynamically as validators join, retire, or are invalidated

**Cross-reference:** Section 4 (Validator Lifecycle), Section 10.5 (Onboarding), Section 25.5 (Staking)

### 6.1 Potential Witness Validators (PWV)

The **PWV Set** is a superset of the AVS used to provide ambiguity during sensitive operations.

**Relationship to AVS:**

| Set | Purpose | Size |
|-----|---------|------|
| **AVS** | All active validators | N (total active) |
| **PWV** | Ambiguity set for a specific transaction | k - 5 (e.g., 15 for k=3) |
| **Witness Set** | Actual validators who signed | k (3-5) |

```
AVS (all active validators)
 " PWV Set (subset selected for ambiguity)
      " Witness Set (actual signers, hidden within PWV)
```

**Key Properties:**

- PWV sets are intentionally oversized
- PWV membership does not imply participation
- Real witnesses are hidden among decoys

### 6.2 PWV Creation

PWVs are created **only by query**.

If no one queries a transaction:
- no PWV set exists
- no future judicial process is possible

This is intentional.

### 6.3 PWV Set Size

PWV set size is determined by **Assurance Tier**:
- **Tier 3**: 3 validators (minimum security threshold)
- **Tier 4**: 4 validators
- **Tier 5**: 5 validators

**No Tier 1 or Tier 2 exists** -- single or dual-validator witnessing is explicitly rejected as insufficient for trustless verification.

Certification constraints (if required by the transaction originator) apply to:
- real validators
- decoy validators

This ensures attackers cannot narrow down validator identity through certification filtering.

#### 6.3.1 Assurance Tier Clarification

**Important:** The "k" value (3, 4, or 5) is a **selectable tier per transaction**, NOT a variable range within a single transaction.

| Address | k | Proof | Witnesses | Use Case |
|---------|---|-------|-----------|----------|
| **Ark** | 0 | ARK | Offline | Partition/offline mode |
| **Standard** | 3 | DMAP | 3 | Default transactions |
| **A+** | 3 | ZKP | 3 | Standard + zero-knowledge proof |
| **Secure** | 4 | DMAP | 4 | High-value transactions |
| **Secure+** | 4 | ZKP | 4 | High-value + zero-knowledge proof |
| **AAA** | 5 | DMAP | 5 | Maximum security, institutional |
| **AAA+** | 5 | ZKP | 5 | Maximum + zero-knowledge proof |

Each wallet has **7 addresses** — one per tier. The address encodes both the witness count (k) and the proof type (DMAP or ZKP) in its checksum. The sender chooses which address to give to the receiver, selecting the security level for that transaction.

**Each transaction has a FIXED k value** determined at transaction creation:
- Client selects tier based on security requirements
- Transaction specifies exactly k witnesses
- Core validates that witness count matches declared tier
- No variability within a single transaction

**Common misconception:** References to "3-5 witnesses" in documentation describe the range of available tiers (Tier 3 through Tier 5), NOT a variable number of witnesses per transaction.

**Cross-reference:**
- White Paper Appendix K.W5-K.W8 (mathematical justification for k=3/4/5)
- Section 17.3.1 (tier-specific overlap requirements)
- Section 25.3.3 (validator tier positioning)

### 6.4 Immutability

Once created:
- PWV membership never changes
- even if validators retire or disappear

This prevents retroactive manipulation.


## 7. Judicial Freeze Protocol (JFP)

### 7.1 What JFP Is

JFP allows:
- lawful freezes
- without exposing validator identities
- without governance committees
- without protocol-side legal interpretation

Lambda does **not** judge legality.
Validators do.

**For Legal Readers:** A separate document, *"Judicial & Regulatory Reading Note"* (AXIOM_JFP_Legal_Reading_Note.md), provides a non-technical explanation of JFP's intent and safety boundaries for courts, regulators, and legal reviewers. That document is non-normative and does not grant authority or guarantee action.

### 7.2 Initiation

- Any active validator may initiate a freeze (entry point for prosecutor/authority)
- Initiator pays **1 AXC** (see §5.2, White Paper §K.3.3)
- Payment creates DWP group wallet (escrow + audit trail for entire JFP lifecycle)
- Initiator's vote is automatically **YES**

The protocol does not ask *why*.
Responsibility lies with the human validator.

This fee serves dual purposes:
- prevents frivolous freeze attempts
- compensates PWV set for participation burden


## 8. Canonical Voting Rules (Critical)

### 8.0 Vote Status Definitions

- **ACK**: Validator acknowledges vote notification receipt
- **UNVOTED**: No vote submitted before deadline
- **Offline >=12h**: ACK received, then connection lost for >=12 hours
- **Never online**: No ACK, unreachable at vote initiation

### 8.1 Time Handling & Window Closure

**Lambda has no global clock.** Time handling must account for clock drift between validators.

#### 8.1.1 Signed Session Times (Normative)

`started_at` and `ends_at` MUST be carried inside the signed vote notice/session message, and MUST be validated by receivers.

Implementations MUST NOT derive session times solely from local wall clock at receipt time.

#### 8.1.2 Clock Skew Allowance ()

Finalization MUST apply a clock-skew allowance  such that:

```
finalize only if Now() >= ends_at + 
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **CLOCK_SKEW_DELTA** | 10 minutes | Prevent premature UNVOTED classification |

**Rationale:** Without , a validator with a fast local clock could finalize before slower peers have had opportunity to vote, causing spurious UNVOTED -> FAILED outcomes.

### 8.2 Voting Rules

**Note on "real validators":**

Due to the Decoy Witness Protection mechanism (Section 6), PWV sets contain both real witnesses (who actually validated the transaction) and decoy validators (randomly selected for obfuscation). Only real witnesses within the PWV set possess transaction data and can meaningfully vote. Rule 6 applies only to validators who actually witnessed the transaction and are present in the PWV set.

**Rules:**

1. **All PWV votes must resolve**
2. Any **UNVOTED -> FAILED**
3. Silent but online -> UNVOTED -> FAILED
4. **ACK received but offline >=12h** -> RANDOM YES/NO
5. **Never ACK (no connection at vote initiation)** -> UNVOTED -> FAILED
6. **All validators with transaction data must vote YES**
7. Any real NO -> REJECTED

These rules are intentionally brutal.

They remove:
- hostage leverage
- silent coercion
- selective disappearance attacks

The distinction between "offline after ACK" and "never online" prevents attackers from exploiting ambiguous connection states.

### 8.3 Offline Threshold as Anti-Coercion Boundary

#### 8.3.1 The 12-Hour Hard Cutoff

Rule 4 introduces a critical security boundary:

```
Validator offline >=12h after ACK -> RANDOM YES/NO
```

This is **not a punishment for downtime**. This is a **protective mechanism against targeted coercion**.

#### 8.3.2 Attack Surface Before and After Threshold

**Case 1: Validator offline < 12 hours**

```
System behavior: Deterministic requirement
Validator state: MUST vote (if vote doesn't arrive -> FAILED)
Coercion value: HIGH
```

From attacker's perspective:
- "If I control this validator, I control the outcome"
- Kidnapping/coercion has guaranteed impact
- Investment in coercion has predictable return

**Case 2: Validator offline >= 12 hours**

```
System behavior: Randomized resolution
Validator state: MAY be bypassed (random YES/NO)
Coercion value: LOW (uncertain impact)
```

From attacker's perspective:
- "Even if I control this validator, system might proceed without them"
- Kidnapping/coercion has uncertain impact
- Investment in coercion has unpredictable return

#### 8.3.3 Why Hard Cutoff Instead of Gradual Transition

A gradual increase in randomization probability would create an ambiguous attack surface where attackers must calculate "at what hour does coercion become unprofitable?"

Hard cutoff provides:
- Clear security boundary (before 12h: deterministic, after 12h: randomized)
- Simpler mental model for operators ("after 12h, I'm protected by ambiguity")
- Cleaner operational reasoning ("before 12h, I should attempt to participate")

#### 8.3.4 Protection Through Unpredictability

The randomization transforms the validator from:

**Single point of failure** -> **Probabilistic participant**

This fundamentally changes the economics of coercion:

| Aspect | Before 12h | After 12h |
|--------|------------|-----------|
| Attacker certainty | "Must coerce to change outcome" | "Maybe coerce, maybe doesn't matter" |
| Validator risk | Deterministic target | Protected by ambiguity |
| System behavior | Requires this validator | May bypass this validator |

#### 8.3.5 Validator Perspective

From the validator's operational standpoint:

**Silence is acceptable after 12h:**
- "I cannot safely participate" -> randomization activates
- System will not force me to become a coercion target
- My absence triggers protective uncertainty

**This is defensive design, not failure:**
- The system prefers validator participation when safe
- The system protects validators when participation becomes unsafe
- Ambiguity is a feature, not a bug

#### 8.3.6 Relationship to Validator Reputation

Frequent offline periods remain observable to clients through:
- Historical witness selection data
- Transaction confirmation patterns
- Market-based reputation tracking

**Separation of concerns:**
- **Protocol layer:** Protects validators from coercion (randomization)
- **Market layer:** Clients select reliable validators (reputation)

This is correct. Market selection for reliability is separate from protocol-level coercion resistance.

Validators are protected from being **forced** to participate, but not from market consequences of **choosing** not to participate.

#### 8.3.7 Implementation Guidance

**Recommended logging:**

```rust
if validator_last_seen > 10h && validator_last_seen < 12h {
    log::warn!(
        "Validator {} approaching offline threshold ({}h). \
         After 12h, randomized resolution activates for anti-coercion protection.",
        validator_id,
        hours_offline
    );
}

if validator_last_seen >= 12h {
    log::info!(
        "Validator {} offline >=12h. Randomized resolution active. \
         This protects validator from being a forced single point of failure. \
         Outcome: RANDOM(YES/NO).",
        validator_id
    );
}
```

**Operator documentation MUST include the following explanations:**
- 12h threshold is a security feature (anti-coercion)
- Randomization protects operators from targeted attacks
- This is not a penalty for downtime
- Market selection remains independent of protocol protection

### 8.4 Vote Collection Mechanism (Revised 2026-03-23)

#### 8.4.1 Design Rationale — Why Not a Custom Voting System

The initial JFP implementation (v2.11.10-alpha) built a dedicated voting infrastructure:
custom admin API endpoints, a `jfp_votes` database table, cross-validator sync
via HTTP, and a separate `frozen_wallets.json` file for ANTIE. This was **wrong**.

AXIOM already has a complete transaction system with authentication, consensus,
propagation, and immutability. Building a parallel system for JFP voting:

- **Violated architecture**: Validators don't talk P2P. They communicate through ANTIE.
  The sync mechanism tried HTTP between admin ports that only bind to localhost.
- **Duplicated functionality**: k=3 witnessing already provides authenticated, consensus-backed,
  immutable entries that propagate to all validators.
- **Created unnecessary complexity**: Custom vote tables, custom auth checks, custom propagation —
  all reimplementing what the wallet layer already does.

**Principle: use existing infrastructure before building new.** The DWP group wallet
is the one genuinely new element (Fan-Out query for witness discovery). Everything
after "PWV set determined" MUST use standard wallet operations + Nabla. No custom voting infrastructure is permitted.

#### 8.4.2 PWV Set Size — k × 5

The PWV set size scales with the consensus parameter k:

| k | PWV size | Real witnesses | Decoys |
|---|----------|---------------|--------|
| 3 | 15       | 3             | 12     |
| 4 | 20       | 4             | 16     |
| 5 | 25       | 5             | 20     |

Formula: `PWV_SIZE = k × 5`. This maintains a consistent 1-in-5 ratio
of real witnesses to total set members regardless of k.

#### 8.4.3 The Mechanism — Wallet + Nabla

**Group wallet** is a real AXIOM wallet, created via a special TX type
as part of the DWP query flow.

**Voting** is a two-part operation using existing infrastructure:

1. **Hashed vote** → k=3 witnessed transaction on the group wallet.
   Each PWV member submits `BLAKE3("AXIOM_JFP_VOTE" || vote_value || secret)` as
   an amount=0 TX entry. The group wallet must have exactly `k × 5` such entries
   (one per PWV member). The wallet records **that** the member voted, but the
   hash is not linked to any specific voter identity in the entry list.

2. **Secret** → Nabla registration (new unnamed type).
   The voter's `secret` (32 random bytes) is registered on Nabla as an unnamed
   entry. No dedup tracking needed — random 32-byte secrets cannot collide.
   Secrets propagate via Nabla gossip, indistinguishable from other registrations.

As of v2.11.13, Lambda enforces MAX_VOTES_PER_CASE_PER_TICK = 1 per sender per case per tick (from core/logic/protocol.toml). Excess votes in the same tick are silently suppressed at the Lambda layer. The payment TX is accepted and processed normally; only the vote registration is discarded. This prevents griefing via valid-format vote spam at 1-atom cost per vote.

**After all PWV members have voted** (group wallet shows k×5 hashed entries):

3. **Result computation** → Any validator can independently compute:
   - Read k×5 hashed entries from the group wallet
   - Read k×5 secrets from Nabla
   - For each secret, try `BLAKE3("AXIOM_JFP_VOTE" || YES || secret)` and
     `BLAKE3("AXIOM_JFP_VOTE" || NO || secret)`, match against the hashes
   - Tally YES/NO count
   - Result is deterministic — every validator computes the same answer

4. **Enforcement** → If all k×5 are YES (unanimity per §8.2), the result
   is **registered on Nabla** as a SCAR against the target wallet.

#### 8.4.4 Enforcement — SCAR, Not Freeze

**We considered and rejected hard wallet freeze:**

A hard freeze (preventing transactions) requires:
- All validators maintaining a synchronized frozen list
- Core CL1 checking the list on every transaction
- Cross-validator sync mechanism (broken in initial implementation)
- Race condition: wallet can transact before freeze propagates

**SCAR enforcement is simpler and stronger:**

The JFP result is a Nabla registration that marks the target wallet as SCARRED.
This uses the existing FACT verification mechanism:

- Every receiver checks FACT before redeeming (already implemented in webclient)
- SCARRED transactions are visible to everyone — CLEAN/SCARRED badge in UI
- Nabla gossip propagates the SCAR to all nodes within 5-8 seconds
- No Core changes needed — no `frozen_wallets` field, no CL1 check
- No cross-validator sync needed — Nabla IS the sync mechanism

**Why SCAR > freeze:**

| Aspect | Hard Freeze | SCAR |
|--------|-------------|------|
| Propagation | Custom sync (fragile) | Nabla gossip (5-8s, proven) |
| Enforcement point | Core CL1 (every TX) | Receiver FACT check (every redeem) |
| Circumvention | Find non-synced validator | Cannot — Nabla is network-wide |
| Failure mode | Silent (TX goes through if list stale) | Visible (SCAR badge on every TX) |
| New infrastructure | frozen_wallets table, sync API, ANTIE file | None (existing Nabla registration) |

**The wallet can still trade, but every transaction is SCARRED.** This is
intentionally not a hard block. The market decides whether to accept scarred money.
This mirrors real-world judicial practice: a court can issue a notice (SCAR)
without physically seizing assets (freeze). The notice is often more effective
because it's public and cannot be hidden.

**AXIOM's philosophy: inform, don't prevent.** The system provides information
(SCAR via FACT). Humans and markets make enforcement decisions. This avoids
the protocol becoming a tool of censorship while still supporting lawful oversight.

#### 8.4.5 Vote Secrecy — Honest Assessment

**We considered and rejected:**

- **Commit-reveal** (two-phase hash): Adds complexity. Timing analysis still leaks.
- **Multi-party computation (MPC)**: Requires interactive protocol. AXIOM uses async email.
- **Encrypted votes (threshold decryption)**: Requires distributed key generation.
- **Trusted anchor tallying**: Single point of corruption. The anchor could lie.

**The honest truth:** In any transparent system, perfect vote secrecy is impossible.
A determined observer monitoring wallet and Nabla in real-time can correlate timing.
This is true of **every** scheme — because the act of submitting is observable.

**AXIOM's philosophy: delay and cost, not perfection.** Unnamed hashes + unnamed
secrets means casual observers cannot determine who voted what. The cost of
surveillance is "monitor both systems continuously with sub-second correlation."

In most judicial practice, individual juror votes are sealed. The court records
the verdict, not who voted which way. Our design mirrors this.

#### 8.4.6 What Uses Existing Infrastructure

| Need | Existing Solution | New? |
|------|-------------------|------|
| Vote authentication | k=3 witnessing | No |
| Vote consensus | k=3 consensus | No |
| Vote propagation | Normal TX flow | No |
| Vote immutability | Transaction receipts | No |
| Secret storage | Nabla registration (new unnamed type) | Minimal |
| Secret propagation | Nabla gossip | No |
| Result computation | BLAKE3 matching | No |
| Enforcement | Nabla SCAR registration → FACT | No |
| Cross-validator sync | Not needed (Nabla gossip handles it) | No |
| DWP query | Fan-Out (CL10) | **Yes** |
| Group wallet | Existing group wallet (shared key, per-member shares) | No |

#### 8.4.7 Group Wallet — Existing Infrastructure

The DWP group wallet is a standard AXIOM group wallet (Core `GroupMember` struct):
- Shared private key sent to all k×5 PWV members by the initiator
- `share_bps`: requester 5000 (50%), each PWV member gets equal split of remaining 5000
- `available` tracks allocated atoms per member
- Max 32 members (supports up to k=6, i.e., 30 PWV members)
- Members list immutable after creation

**Incentive:** PWV members who ACK and vote receive their share (≈3.3M atoms for k=3).
Members who don't ACK forfeit their share → **unclaimed shares go to pool** (not
redistributed to other voters, because redistribution reveals who didn't participate).

#### 8.4.8 Online Proof — Hourly Core Proofs + Password Unlock

To distinguish "offline (protected by RANDOM)" from "online but silent (FAILED)":

1. **Hours 1-11:** Lambda asks Core to generate a proof TX for the group wallet
   every hour. These are queued locally but NOT sent. Core can only generate
   proofs if running — no backfilling. The proof includes the current Nabla tick
   (unpredictable, prevents pre-generation).

2. **Hour 12 (or earlier):** Lambda prompts the operator for their wallet password.
   Operator enters it → Lambda unlocks, signs, and sends all queued proof TXs + vote TX.

3. **Result:** If all 11 proof TXs are present → validator was online. If gaps exist
   → validator was offline during those hours. If no proofs and no password → RANDOM.

**Note on pre-generation:** A validator could theoretically pre-generate proofs if they
can predict future Nabla ticks. This defeats the online proof. However, the protocol
is designed to PROTECT validators — if they choose not to use the protection, that
is their decision. The protocol cannot force a validator to use its own safety features,
just as a door lock cannot force the homeowner to lock the door.

#### 8.4.9 Three Outcomes

| Outcome | Condition | Meaning |
|---------|-----------|---------|
| **APPROVED** | All k×5 votes are YES (including RANDOM) | Full consensus to act |
| **REJECTED** | Any vote is explicit NO | Disagreement — do not act |
| **FAILED** | Any voter proven online but silent, OR missing secrets | No consensus — cannot act |

FAILED is **not punishment**. Silence is a valid position — it means "I cannot give
YES or NO." The protocol respects this by failing the freeze. The system prefers
inaction over uncertain action. This is correctness over liveness.

#### 8.4.10 Implementation Notes

**Voter and hash list ordering:** The `voters[]` (who voted) and `hashes[]` (vote hashes)
lists MUST be independently shuffled before recording on the group wallet. If both lists
maintain insertion order, position correlation trivially reveals which hash belongs to
which voter. Shuffle both lists using deterministic entropy from the group wallet ID
so all validators compute the same order.

**Missing secret = FAILED:** If a voter submits their hash TX but never registers the
secret on Nabla, their vote is unresolvable. Since unanimity requires all votes resolved,
one missing secret = FAILED. This is self-enforcing — voters are incentivized to
register secrets because otherwise nobody gets paid.

**ACK ≠ choosing to participate:** PWV members do not get to "decide" to participate.
They are in the set. ACK means "I acknowledge and claim my share." No ACK = forfeit
share + RANDOM (can't prove online). The vote itself (YES or NO) is the only human decision.


## 9. Randomization as Anti-Coercion Defense

Random YES/NO assignment for disappeared validators (offline >=12h after ACK) exists to:

- make disappearance unpredictable
- remove incentive to kidnap or isolate validators
- deny attackers control over outcomes

Randomness is not fairness.
Randomness is **safety**.

An attacker who successfully isolates a validator gains no advantage -- the outcome becomes unpredictable to all parties, including the attacker.

### 9.1 JFP Adversarial Simulation

To conduct an adversarial simulation of the Judicial Freeze Protocol (JFP) under majority coercion, you must test the protocol's primary defensive invariant: **unanimity as a safety requirement**.

The simulation demonstrates that when a majority is coerced, the system's "Correctness over Liveness" philosophy causes the protocol to **fail safely (inaction)** rather than comply with forced orders.

#### 9.1.1 Coercion Resistance Flow

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=2.8cm, minimum height=0.7cm, align=center, font=\footnotesize},
    decision/.style={diamond, thick, aspect=2.5, align=center, font=\footnotesize, inner sep=1pt},
    arrow/.style={->, thick, >=stealth},
    label/.style={font=\scriptsize, midway}
]
\node[box, draw=red!60, fill=red!10] (A) at (0,0) {JFP Freeze\\Request Received};
\node[decision, draw=black] (B) at (0,-1.8) {All members\\online?};
\node[box, draw=black] (C) at (-3.5,-3.8) {Collect votes};
\node[decision, draw=black] (D) at (3.5,-3.8) {Offline\\$>$12h?};
\node[box, draw=blue!60, fill=blue!10] (E) at (5.5,-5.8) {Random\\YES/NO};
\node[box, draw=orange!60, fill=orange!10] (F) at (1.5,-5.8) {Unvoted\\$\to$ Failed};
\node[decision, draw=black] (G) at (0,-7.8) {100\%\\Unanimity?};
\node[box, draw=green!60, fill=green!10] (H) at (-3.5,-9.8) {Freeze\\Executed};
\node[box, draw=yellow!70!black, fill=yellow!15] (I) at (3.5,-9.8) {Safe Failure\\No action};
\draw[arrow] (A) -- (B);
\draw[arrow] (B) -- node[label, left] {Yes} (C);
\draw[arrow] (B) -- node[label, right] {No} (D);
\draw[arrow] (D) -- node[label, right] {Yes} (E);
\draw[arrow] (D) -- node[label, left] {No} (F);
\draw[arrow] (C) |- (G);
\draw[arrow] (E) |- (G);
\draw[arrow] (F) -- (G);
\draw[arrow] (G) -- node[label, left] {Yes} (H);
\draw[arrow] (G) -- node[label, right] {No} (I);
\end{tikzpicture}
\caption{JFP Coercion Resistance Flow --- Pressure yields unpredictable outcomes, biasing toward safe failure.}
\end{figure}
```

#### 9.1.2 Adversarial Simulation Test Plan

This plan verifies the protocol defaults to "Safe Failure" when >50% of the Console is compromised.

| Phase | Activity | Expected Result |
|-------|----------|-----------------|
| **1. Baseline** | Initiate valid JFP with all members online and willing | Success: 100% Unanimity -> Freeze Executed |
| **2. Silent Minority** | 60% vote YES (coerced), 40% stay silent | Safe Failure: Silence = UNVOTED = Rejection |
| **3. Offline Coercion** | Force 70% offline for >12h during window | Entropy Injection: RANDOM YES/NO neutralizes control |
| **4. Identity Leakage** | Attempt to identify holdouts via metadata | Ambiguity: PWV/DWP prevents distinguishing blockers |
| **5. Economic Burn** | Submit 100 rapid speculative freeze queries | Sustainability: 1 AXC/query (net 0.5 AXC) makes fishing uneconomic |

#### 9.1.3 Key Test Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Query Fee | 1 AXC (net 0.5) | Prevent spam/fishing expeditions |
| Timeout Threshold | 12 hours | Point when offline vote is randomized |
| Unanimity Rule | 100% | All active validators must vote YES |
| Anti-Coercion Delay | Variable | Intentional wait to surface pressure |
| Clock Skew Delta | 10 minutes | Prevent premature finalization |

#### 9.1.4 Success Criteria

The simulation succeeds if:

1. **No freeze executes without absolute, un-coerced unanimity**
2. **Randomization of offline votes** prevents attacker certainty even after kidnapping majority
3. **PWV/DWP mechanisms** maintain ambiguity about which members blocked

**Core invariant:** Coerced majority -> Safe failure (inaction), never compliance.

### 9.2 Adversarial Conformance Tests (Implementation)

These tests verify security properties introduced by the spec patches:

| Test                                        | Description                                                          | Expected Result                                                              |
|---------------------------------------------|----------------------------------------------------------------------|------------------------------------------------------------------------------|
| **A: Forwarder OOM Defense**                | Stream > 100,000 unique QueryIDs (valid payment proofs)              | No OOM; cache evicts/drops; process survives                                 |
| **B: Query Payment Enforcement**            | Missing/invalid payment proof                                        | Forwarder MUST drop (no propagation)                                         |
| **C: Stamp Replay Protection**              | Reuse same stamp_id                                                  | CHECK_QUERY_PAYMENT fails (replay blocked)                                   |
| **D: Deterministic Decoys Stability**       | Same (tx_id, epoch_id, witness_pk)                                   | GENERATE_PWVSET returns same members list                                    |
| **E: Deterministic Decoys Unpredictability** | Before PWVSet published                                              | Observer cannot predict members from (tx_id, epoch_id, witness_pk) alone     |
| **F: Clock Skew Defense**                   | Local clock +5m fast                                                 | Finalize waits until ends_at + CLOCK_SKEW_DELTA                              |
| **G: Direct Notify Reliability**            | Endpoint failures                                                    | Bounded retries then targeted diffusion (bounded TTL/fanout)                 |
| **H: Intersection Suppression**             | Multiple PWV sets arrive                                             | Querier locks first; ignores subsequent for same query_id                    |


## 10. Meta-Validator (MV) System: Admission Sets, Inheritance, and Onboarding

This section defines Meta-Validators, MV-sets, and the onboarding rule that binds a new validator into three independent continuation paths. Meta-Validators are not "auto-FAIL" agents and do not output predefined vote outcomes. They act as normal validators under the protocol rules.

> **Cross-Reference:** Terminology (MV-set, MVIB, Meta-Validator) is canonically defined in White Paper Section J.10 and Glossary. This section provides implementation specification.

### 10.1 Definitions

**Meta-Validator (MV)**

A validator designated (per MV-set) to inherit procedural responsibilities associated with an absent validator, including participation in JFP/Witness-related procedures as defined by the protocol.

**MV-set (Meta-Validator Set)**

An upstream admission set bound to a validator at onboarding time. If that validator becomes absent, its continuation path and procedural responsibilities are inherited along the MV-set.

**MVIB (Meta-Validator Inheritance Binding)**

A signed onboarding prerequisite that binds a validator to its MV-set continuation path(s). MVIB binds continuation without requiring identity disclosure.

> **NOTE:** "Inheritance" here means procedural responsibility and continuity participation, not discretionary governance, not rule override, and not automatic voting outcomes.

### 10.2 Why Meta-Validators Exist

PWV records persist for up to **10 years**.

Validators cannot be expected to:
- stay alive,
- stay reachable,
- stay in the same jurisdiction.

Meta-delegation ensures:
- no vote remains permanently unresolved
- no validator is eternally obligated

### 10.3 Non-Governance and Non-Automation Invariant

Meta-Validators do **NOT** possess emergency authority.

Meta-Validators do **NOT** output predetermined YES/NO/FAIL outcomes by definition.

Instead:
- Meta-Validators operate as normal validators when called upon by protocol-defined procedures
- Any votes or actions they perform are executed under the same constraints as any other validator
- There is no "automatic FAIL substitution" semantics attributed to Meta-Validators

### 10.4 Per-Set Selection Model

Meta-Validator designation is performed **per MV-set**.

Each MV-set MUST define a deterministic, verifiable method for selecting its active MV for the epoch. Examples (not mandates):
- VRF-based selection among eligible members of the MV-set
- Predefined rotation schedule among MV-set members
- Any method that is:
  - publicly auditable in output
  - not dependent on time-based entropy
  - compatible with the Determinism Contract

The MV selection mechanism MUST NOT introduce discretionary governance or override paths.

### 10.5 Validator Onboarding Requirement: Three Independent Sets

A new validator MAY become eligible for participation only after completing onboarding validation by **three independent existing validator sets**.

**Rule:**
- A candidate validator must obtain validation from **three distinct MV-sets** (Set A, Set B, Set C)
- Each MV-set provides its validation through its own members per the onboarding procedure
- Successful onboarding MUST produce an MVIB binding the new validator to these three MV-sets

This creates three independent continuation paths for procedural inheritance if the validator becomes absent.

### 10.6 Bootstrap Exception (Early Genesis Constraint)

During bootstrap, when the active validator population is below the full threshold:

- The initial validators are not required to obtain validation from three sets
- The earliest validators MAY be admitted with reduced validation requirements (e.g., 1 or 2), as permitted by the Bootstrap / Transition procedures

This exception exists only to allow the system to reach a state where the three-set requirement becomes feasible. **It does not create a permanent privileged class.**

### 10.7 Recursive Safety

If a meta-validator disappears:
- the next layer replaces it along the MV-set inheritance chain

There must be no infinite regress.

The system must gracefully handle cascading validator unavailability without deadlock.

### 10.8 Absence / Retirement Inheritance Semantics

If a validator becomes absent or retires:

- The validator remains referenced in historical structures where applicable
- Procedural responsibilities associated with that validator MAY be inherited along its bound MV-sets
- Meta-Validators (selected per MV-set) may act when protocol-defined procedures require continuity

This includes, but is not limited to:
- Witness-related procedural roles during JFP workflows
- Continuity participation when the original validator is no longer available

> **IMPORTANT:** Inheritance is procedural continuation. It does not imply that an MV "votes on behalf of" the absent validator in a predetermined way.

### 10.9 Safety Boundaries

The MV system MUST preserve the following invariants:

- MV actions MUST NOT modify Canonical Bytes, txid, state_hash, or core deterministic outputs
- MV actions MUST NOT create new tasks, new authority, or emergency override channels
- MV actions MUST remain compatible with the Determinism Contract and EP explicitness

### 10.10 Summary Invariant

> **Meta-Validators are validators.**
> They are selected per MV-set.
> They enable continuity under absence through inheritance bindings (MVIB), without introducing governance, emergency authority, or automatic vote outcomes.


## 11. Ark-Mode: Perpetual Offline Capability

*Naming.* **Ark = Asynchronous Resilience Ketch** — a backronym that doubles as the
Noah's-ark metaphor: a seaworthy vessel that keeps value afloat when the network floods.
*Asynchronous* + *Resilience* describe the regime; a *ketch* is a self-contained sailing
craft, matching Ark's offline, no-witness-set (k=0) operation.

### 11.1 Design Premise

Ark-Mode is not an emergency fallback -- it is a **permanent parallel state**.

Every identity carries a **wallet pair** from genesis — two wallets
distinguished by the security tier encoded in their `wallet_id`:
- **Normal (Standard) wallet**: For connected-network operations (k=3)
- **Ark wallet**: For offline/partition scenarios (k=0)

These are wallets (identified by `wallet_id`), not key types. Both are
established during first transaction initialization.

### 11.2 No Trigger, Only Activation

Ark-Mode has no "trigger condition."
Users decide when to operate offline.

This means:
- No network state determines offline capability
- No synchronization required to "enter" Ark-Mode
- Offline capability exists whether or not partitions occur

The network never "declares" a partition.
Individual clients choose their operational mode.

### 11.3 OLE (Offline Ledger Extension) Receipts

Transactions under Ark-Mode generate OLE receipts:
- Deterministically valid within local context
- May conflict with global state
- Resolved via dilution (not rollback) upon reconnection

OLE receipts are not "temporary" or "pending" -- they are **fully valid transactions within their partition context**.

**Important clarification:**

"Valid within partition context" means:
- OLE receipts follow all protocol rules locally
- State transitions are cryptographically sound
- Transactions are honored at face value in that partition

**However:**

OLE receipts do NOT have **global network validity** until reconciled. This aligns with White Paper Section 6.9:

> "Ark-Mode preserves transaction intent under disconnection,  
> while maintaining that witnessed state is the ultimate truth."

The distinction:
- **Local validity** = transaction is correct within its partition
- **Global validity** = transaction is witnessed and reconciled with network

All Ark-Mode transactions achieve global validity through reconciliation, not rollback.

### 11.4 Reconciliation Philosophy

> **NOTE:** ARK-mode reconciliation semantics are under active research. The following describes the current design direction but is not yet final.

When partitions merge:
- **Local price distortions are absorbed** (economic inflation during partition is accepted)
- **AXC atom conservation is enforced** (no monetary inflation occurred)
- Not all transactions are invalid -- **first one is honored** (deterministic ordering)

**Example scenario:**

```
Partition A (disaster zone):
- Water price: 10 L$ per bottle
- Alice buys water: pays 10 L$ (1,000,000,000 atoms)

Global network (normal economy):
- Water price: 1 L$ per bottle

Upon reconnection:
- Alice's transaction remains valid
- She paid 10 L$ for water (not rolled back)
- This represents real economic scarcity, not protocol error
```

This prevents the catastrophic outcome where partition survivors lose all economic activity during blackout periods.

**Critical design choice:** Preserve all economic agency, even if partition-era prices seem "inflated" compared to global prices. The protocol does not judge whether prices were "fair" -- it only enforces that transactions were cryptographically valid.

### 11.5 Confidence Index for Offline Acceptance

> **NOTE:** The Confidence Index mechanism is under active research. The following describes the current design direction but is not yet final.

#### 11.5.1 Design Philosophy: Bounded Risk over Absolute Security

In offline or degraded states, "Absolute Finality" is replaced by "Bounded Risk."

Rather than claiming:
> "This offline payment is guaranteed to be final"

ARK-mode explicitly states:
> "This payment is conditionally accepted under bounded risk"

Key design decisions:
- Risk is not hidden
- Risk is quantified and communicated
- The seller retains final discretion

This enables the system to **fail gracefully** instead of catastrophically.

#### 11.5.2 The Cash Analogy

Counterfeit cash exists. Yet societies do not stop using cash, because the system does not rely on perfect prevention.

Instead:
- Risk is visible
- Risk is contextual
- Final judgment is made by humans

A shopkeeper intuitively evaluates:
- Is the bill suspicious?
- Is the amount unusually large?
- Is this customer familiar?
- Does the situation make sense?

Small transactions are often accepted without scrutiny. Large transactions trigger caution or refusal.

**ARK-mode adopts the same principle.**

The Confidence Index plays the role of "anti-counterfeit cues" in an offline digital environment.

#### 11.5.3 Confidence Index Definition

The Confidence Index (CI) is a compact, signed credential presented by the buyer during an offline transaction.

**It is NOT a self-reported claim.**

It is issued during the buyer's last successful online validation and contains:
- Time since last online validation
- Number of successfully settled transactions
- Number of detected conflicts (double spends)
- Account age
- Optional stake / collateral indicators

The index is cryptographically signed so that the seller can verify it offline.

#### 11.5.4 Human-Centered Interpretation

The Confidence Index is intentionally designed to be **human-readable**.

Instead of raw numbers, it is mapped to intuitive categories:

| Status | Risk Level | Recommended Action |
|--------|------------|-------------------|
| **GREEN** | Low risk | Normal offline acceptance |
| **YELLOW** | Moderate risk | Reduced limits or extra caution |
| **RED** | High risk | Offline payment discouraged or refused |

Along with a short explanation, such as:
- "Last validated 2 hours ago"
- "84 settled transactions, 0 conflicts"
- "Account age: 14 months"

This mirrors how humans already reason about trust.

#### 11.5.5 Role of Timestamps

Timestamps are used as **supporting signals**, not absolute guarantees.

They help detect:
- Obviously stale data
- Replay attempts
- Sloppy or accidental rollback misuse

**However:**
- No timestamp-based mechanism alone can permanently prove rollback
- Time-based signals are temporary by nature
- Waiting can always restore apparent freshness

Therefore, timestamps strengthen confidence signals but do not replace them.

### 11.6 Offline Transaction Flow

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    arrow/.style={->, thick, >=stealth},
    note/.style={font=\footnotesize, align=left},
    actor/.style={font=\small\bfseries}
]
% Lifelines
\node[actor] (buyer) at (0,0) {Buyer Device};
\node[actor] (seller) at (8,0) {Seller Device};
\draw[thick, dashed] (0,-0.4) -- (0,-9.5);
\draw[thick, dashed] (8,-0.4) -- (8,-9.5);

% Step 1: Prepare Offline Payment
\draw[arrow] (0,-1.2) -- node[above, font=\footnotesize] {1. Prepare Offline Payment} (8,-1.2);
\node[note, anchor=west] at (0.3,-2.0) {%
  \begin{tabular}[t]{@{}l@{}}
  -- Payment intent\\
  -- Timestamp\\
  -- Confidence Index (signed)
  \end{tabular}};

% Step 2: Verify Offline
\node[note, anchor=west] at (5.5,-3.5) {%
  \textbf{2. Verify Offline}\\
  -- Verify signatures\\
  -- Check timestamp freshness\\
  -- Inspect Confidence Index};

% Step 3: Human Decision
\node[note, anchor=west] at (5.5,-5.8) {%
  \textbf{3. Human Decision}\\
  -- Accept\\
  -- Accept with limits\\
  -- Reject};

% Step 4: Conditional Acceptance
\draw[arrow] (8,-8.0) -- node[above, font=\footnotesize] {4. Conditional Acceptance} (0,-8.0);
\end{tikzpicture}
\caption{Offline Transaction Flow --- Buyer presents signed payment intent; seller verifies locally and decides.}
\end{figure}
```

**Key point:** Offline acceptance does not imply final settlement. Finality is achieved during reconciliation.

### 11.7 Post-Recovery Reconciliation Flow

> **NOTE:** Double-spend resolution semantics are under active research. The following describes the current design direction but is not yet final.

When connectivity is restored, the system reconciles all offline activity:

```
1. Collect offline transactions (OLE receipts)

2. Detect conflicts (same atoms referenced twice)

3. If conflict exists (double-spend):
   - Generate cryptographic Double-Spend Proof
   - Apply deterministic ordering rule (first transaction wins)
   - Losing transaction is void (receiver does not receive atoms)

4. Finalize:
   - Winning transaction settles
   - Buyer's Confidence Index is updated (double-spend = RED)
```

> **Scope — ARK offline only.** This first-transaction-wins / void-the-loser rule applies
> **only** to the ARK offline subsystem (device-bound, no live k=3 witness round). Online,
> a cross-node *same-sequence* fork is **not** resolved by first-wins: it triggers the
> irreversible, authorship-gated fork-ban (§28 Nabla; §32), under which **both** conflicting
> cheques are rejected and there is no winner. Do not generalize the ARK ordering rule to
> the online mesh.

**Double-spend resolution:**
- First valid transaction (by deterministic ordering) is honored
- Subsequent conflicting transactions are void
- The double-spender's Confidence Index degrades to RED
- Receivers of void transactions bear the loss (like accepting counterfeit cash)

**Important:** This is why the Confidence Index exists -- sellers can assess risk before accepting offline payments.

### 11.8 Summary: ARK-Mode Design Philosophy

ARK-mode is not about eliminating all risk.

It is about:
- Making risk **visible**
- Making risk **understandable**
- Making risk **survivable**

By combining:
- Confidence Index (human judgment)
- Timestamps (freshness cues)
- Device-bound anchors (rollback resistance)
- Deterministic reconciliation (eventual consistency)

The system remains functional even when perfect conditions do not exist.

> **ARK-mode does not promise a safe world.**
> **It promises a world that still works when things are not safe.**

### 11.9 Ark Wallet Charge and Unload Rules

#### 11.9.1 Charging an Ark Wallet (Normal → Ark)

A user loads value into their Ark wallet by sending from their normal wallet (k=3)
to their own Ark address (k=0). This is a standard k=3 witnessed transaction:

```
Charge flow:
  1. User's normal wallet (k=3) sends amount to own Ark address (k=0)
  2. k=3 validators witness the send (standard CL1 pipeline)
  3. Nabla registers the state change
  4. Ark wallet balance increases by the charged amount
  5. Normal wallet balance decreases

The Ark balance is PART OF the user's total balance but SEGREGATED:
  - Normal wallet cannot spend Ark balance
  - Ark wallet cannot spend normal balance
  - Both are the same identity (same wallet PK, different tier addresses)
```

**Webclient implementation:** Dedicated "Charge Ark" button with pre-filled fields:
- Receiver: user's own k=0 address (auto-filled)
- Amount: user enters
- Validators: same as normal send
- Displayed warning: "Ark balance can only trade with other Ark wallets or
  be unloaded back when your FACT chain is fully clean (zero scars)."

#### 11.9.2 Ark-to-Ark Trading

Ark wallets trade exclusively with other Ark wallets:

- **⟠-to-⟠ only:** Both sender and receiver run Core/DMAP-VM with DMAP locally
- **No validators needed:** Offline, peer-to-peer
- **No Nabla:** State registered at reconciliation time
- **Transport:** QR code (~1,267 bytes, fits QR Version 15)

A user cannot send from Ark to a normal (k=3) wallet directly.
This would bypass the k=3 witness requirement.

#### 11.9.3 Unloading an Ark Wallet (Ark → Normal)

Returning value from Ark (k=0) to normal wallet (k=3) is a **privileged operation**
with strict prerequisites:

```
Unload prerequisites:
  1. User's FACT chain must be FULLY CLEAN
     - ALL FACT links must have nabla_confirmation present
     - ZERO unresolved scars
     - Any scarred link blocks unload until resolved (heal via Nabla or burn)
  2. Unload is a k=3 witnessed transaction (same as normal send)
  3. Receiver is user's own normal (k=3) address

Why: Ark balance may have been traded offline without Nabla verification.
The FACT-clean requirement ensures all offline transactions are reconciled
and verified before the value re-enters the k=3 witnessed economy.
Without this check, scarred (potentially double-spent) Ark value could
contaminate the verified k=3 economy.
```

**Core enforcement:** CL1 validates unload transactions. When receiver is a k=3 address
and sender is a k=0 address (detected via wallet_id tier extraction), Core checks
`sender_fact_chain.has_scars() == false`. If any scar exists → Reject.

#### 11.9.4 Balance Model

```
Total user balance = Normal balance + Ark balance

Normal wallet (k=3):
  - Spendable via k=3 witnessed transactions
  - FACT links verified by Nabla
  - Full double-spend protection

Ark wallet (k=0, ⟠):
  - Spendable only to other Ark wallets (offline)
  - FACT links locally verified (DMAP, no Nabla)
  - Confidence Index (CI) provides risk assessment
  - Reconciled to k=3 when connectivity returns

The two balances are logically separate but belong to the same identity.
Charging moves value from normal → Ark. Unloading moves Ark → normal
(only when FACT chain is clean).
```


## 12. Partition Is the Default Case

Lambda assumes:
- long-term partitions
- asymmetric recovery
- delayed reconciliation

### 12.1 What Constitutes a Partition

In a decentralized system with no central authority, **partition is defined by validator accessibility**:

| Condition | Status | Operation |
|-----------|--------|-----------|
| Can reach >=3 validators | **Not partitioned** | Normal operation |
| Can reach 1-2 validators | **Degraded** | Cannot transact (k=3 minimum) |
| Can reach 0 validators | **Fully partitioned** | ARK Mode only |

**Key Insight:** Because there is no central system, as long as any region can access 3 validators, that region retains full k=3 transaction witnessing and redeem capability with no degradation. There is no "global partition" -- only localized connectivity issues.

### 12.2 Regional Isolation (Network Firewall Scenario)

**Scenario:** An authoritarian state uses network controls (e.g., "Great Firewall") to block all external network traffic.

| Aspect | Impact |
|--------|--------|
| **If >=3 validators exist inside** | Normal operation continues within the region |
| **Transaction validity** | Fully valid -- k=3 witnesses are satisfied |
| **AXC value** | **Unchanged** -- AXC is a shared global value, not affected by regional isolation |
| **L$ purchasing power** | May be affected by local economic inflation/deflation |

**Why AXC Value Is Unaffected:**

AXC represents a **fixed-supply global reserve asset**. A small region's isolation does not change:
- Total AXC supply (still 100,000,000 AXC, immutable)
- AXC held by participants outside the region
- The mathematical scarcity of AXC

Economic effects of regional isolation manifest in **goods pricing** (what L$ can buy locally), not in AXC's intrinsic value.

### 12.3 Complete Network Failure (Disaster Scenario)

**Scenario:** Natural disaster, infrastructure collapse, or total network blackout -- no validators are reachable.

| Condition | Response |
|-----------|----------|
| Zero validator access | **ARK Mode activates** |
| Settlement method | OLE (Offline Ledger Extension) receipts |
| Reconciliation | Upon network restoration, OLE receipts are validated |

**Cross-reference:** Section 11 (Ark-Mode: Perpetual Offline Capability)

### 12.4 Reconciliation Philosophy

Global consistency is restored by:
- AXC anchor dominance
- Dilution of local distortions
- **Never by forced rollback**

**The network does not "heal" partitions.**

Partitions resolve themselves through economic reconciliation:
- Regions that were isolated eventually reconnect
- Transactions made during isolation are validated against the broader network state
- Conflicts are resolved by AXC's mathematical finality, not by committee decision

### 12.5 Timeline Under Partition

**Partition has no timeline.** There is no countdown, no timeout, no forced reconciliation deadline.

| Aspect | Behavior |
|--------|----------|
| **Local timelines** | Continue independently |
| **Global settlement** | Pauses (no forced sync) |
| **Reconciliation timer** | None -- never started |
| **Recovery** | Resumes from present state, does not replay time |

**Fail Gracefully, Not Catastrophically:**

A prolonged partition does NOT bring down the entire system. It only affects the partitioned region:

| Scope | Effect |
|-------|--------|
| **Partitioned region** | Fails gracefully -- cannot transact if <3 validators |
| **Rest of network** | Continues with full k=3 witnessing and redeem capability -- unaffected by regional partition. |
| **Global system** | Never dragged down by local failures |

**Why This Matters:**

Traditional systems often have timeout-based failure modes:
- "If no response in X minutes, abort"
- "If partition exceeds Y hours, rollback"

Lambda rejects these patterns. A partition that lasts 1 hour, 1 day, or 1 year is handled identically:
- The partitioned region operates in whatever mode it can (normal, degraded, or ARK)
- The rest of the network is unaffected
- Recovery happens when connectivity returns, not when a timer expires

> **Extended partition = graceful local failure, not system collapse.**

### 12.6 Summary: Partition Model

| Scenario | Condition | Behavior |
|----------|-----------|----------|
| **Normal** | 3 validators reachable | Standard k=3 witnessing |
| **Regional Isolation** | Firewall, 3 internal validators | k=3 continues locally; L\$ may vary |
| **Complete Blackout** | 0 validators reachable | ARK Mode; OLE receipts; reconcile later |
| **Extended Partition** | Any duration | Local degrades gracefully; global unaffected |

> **Partition is not failure. It is a recognized operating condition.**
> 
> Lambda does not prevent partition. It survives partition.


## 13. What Lambda Explicitly Rejects

**Governance structures:**
- Governance committees that create new rules
- Emergency councils with protocol override authority
- Social-layer consensus as binding decisions
- Token voting for protocol changes
- "Community governance" as supreme authority

**Economic manipulation:**
- Inflation as security funding
- Protocol-level wealth redistribution
- Forced asset reallocation
- Supply expansion for any reason

**The principle:**

Rules > people.  
But rules must protect people.

This rejection is not ideological purity -- it is a direct response to the human threat model defined in Section 3.1.

Any system that relies on human coordination during crisis will fail when those humans are coerced, arrested, or killed.

**What is NOT rejected:**

Lambda distinguishes between:
- **Governance** (making new rules) -- REJECTED
- **Parameter management** (executing pre-defined adjustments) -- ACCEPTED

The Console system (Section 21.5) manages operational parameters (e.g., digit_version) within protocol-defined boundaries. This is not governance because:
- No new rules are created
- All possible actions are pre-programmed
- Protocol logic remains unchanged
- No discretionary authority exists

**The boundary:**

```
Governance = "Should we allow X?"  -> REJECTED
Console = "When should we execute pre-defined X?" -> ACCEPTED
```

Example:
- Governance: "Should we increase block size?" -> Would require protocol change
- Console: "Should we adjust digit_version from 3 to 6?" -> Pre-defined parameter

The protocol defines what CAN happen.  
The Console decides WHEN it happens.  
Neither can change what the protocol ALLOWS.


## 14. Open Questions (Intentionally Unresolved)

**Network & Consensus:**
- Exact PWV size functions
- Fee market dynamics
- Validator availability thresholds
- Meta-delegation depth limits
- L$ issuance constraints under Ark-Mode

**Propagation & Privacy:**
- TTL optimization: Can TTL=5 or TTL=8 provide sufficient witness discovery probability?
- PWV set intersection leakage: How to prevent query initiator from identifying all real witnesses when receiving multiple PWV sets?
- Fanout factor refinement: Is f=3 optimal, or should it scale with network size?

**Storage & Compliance:**
- Transaction storage encryption scope: Which fields should be encrypted vs plaintext for regulatory compliance?
- Non-claim final disposition: Should unclaimed assets be burned, pooled, or subject to DEED inheritance?
- Receiver acknowledgement semantics: Should protocol enforce claim confirmation?

**DEED System Parameters (Defined in DEED Document):**

The following are specified in "Lambda DEED -- Developer Equity & Execution Deed":
- Exact allocation ratios (Protocol Team / Implementation Team / Validator)
- Group member lists and individual contributor allocations
- Internal distribution mechanisms
- Post-expiry transition models

Yellow Paper defines protocol-level enforcement only (Section 20).

**Reserve Distribution Mechanism (Pending Specification):**
- Claim policy parameters (daily limits, cooldowns, eligibility)
- Witness rotation policy for Reserve Wallet
- Claim distribution timeline (when claims become available)
- Complete operational procedures in Bootstrap Guide

Note: Market Allocation amount finalized at 88,000,000 AXC (per White Paper Section 2.10.7)

**Implementation Boundaries:**
- Wallet state machine formalization
- CBOR canonical schema definition
- Protocol versioning strategy
- Cross-version transaction compatibility

These are **not bugs**.
They are discussion anchors.

Future versions of this document will resolve or remove these items as design crystallizes.


## 15. Guiding Principle (Unchanging)

> Lambda is not designed for trust.  
> Lambda is designed for survival.


## 16. Client Architecture: Cryptographic Sovereignty

### 16.1 Design Philosophy: Separation of Concerns

Lambda enforces strict separation between:
- **Core** (sovereign logic) -- immutable cryptographic decision-making
- **Gateway** (protocol adapter) -- mutable communication interfaces

This separation exists because:
- cryptographic integrity must never depend on network protocols
- communication methods change; mathematical truth does not
- sovereignty requires isolation from external dependencies

### 16.2 DMAP-VM (AXIOM Virtual Machine)

**Implementation:**
- eBPF bytecode (~100 lines of C)
- Stateless execution
- No network access
- No filesystem access
- Memory-only interaction via Vault

**Purpose:**
The DMAP-VM is not a "runtime environment."
It is a **sandboxed judgment chamber** where cryptographic operations occur in complete isolation from host system compromise.

### 16.3 The Vault: Isolated Memory Space

The Vault is a strictly formatted memory region:

```
Offset 0x00: GATEWAY_OP   (algorithm selector)
Offset 0x04: DATA_LEN     (payload size)
Offset 0x10: PAYLOAD      (transaction data)
```

**Critical property:**
The Vault is the **only** interface between Core and external world.

No direct syscalls.
No network sockets.
No file descriptors.

All cryptographic operations occur within this isolated memory space, with external functions accessed only via `helper_call` interface.

### 16.4 Three-Algorithm Future-Proofing

Core supports three cryptographic algorithm tiers for operational (witness) signing. All three are available to every validator. The choice is **per-transaction**, not per-validator.

| Tier | Algorithm | Standard | PK Size | Sig Size | Speed | Use Case |
|------|-----------|----------|---------|----------|-------|----------|
| Standard | Ed25519 | RFC 8032 | 32 bytes | 64 bytes | ~50μs verify | Default, high throughput |
| Quantum-Resistant | Dilithium (ML-DSA-65) | FIPS 204 | 1,952 bytes | 3,309 bytes | ~1ms verify | Post-quantum operational |
| Maximum Security | SPHINCS+ (SLH-DSA-SHA2-128s) | FIPS 205 | 32 bytes | 7,856 bytes | ~10ms verify | Highest assurance, hash-only |

**Design rationale:**
If we only supported Ed25519, quantum computing would make Core obsolete.
If we forced everyone to use SPHINCS+, transaction sizes would be prohibitive.
If we relied on a single post-quantum algorithm and it broke, the network would die.

By pre-embedding all three, we eliminate the need for:
- emergency protocol upgrades
- governance votes on algorithm migration
- coordinated network-wide switches

#### 16.4.1 Algorithm Auto-Detection

Core auto-detects the algorithm from signature length. The three signature sizes are unambiguous:

| Signature Length | Algorithm |
|-----------------|-----------|
| 64 bytes | Ed25519 |
| 3,309 bytes | Dilithium (ML-DSA-65) |
| 7,856 bytes | SPHINCS+ (SLH-DSA-SHA2-128s) |

No algorithm negotiation, no version fields, no configuration. Core sees the signature, knows the algorithm, verifies accordingly. This is a protocol invariant.

#### 16.4.2 Per-Transaction Algorithm Selection (Witness Signing)

Validators choose which algorithm to sign with **per transaction**. A single validator can sign one witness with Ed25519 and the next with Dilithium. The choice depends on:

- **Client request:** Client may request quantum-resistant signing for high-value transactions
- **Local regulation:** Jurisdiction may mandate post-quantum algorithms above certain thresholds
- **Operator policy:** Validator may default to Dilithium for all transactions as a market differentiator
- **Cross-border requirements:** One jurisdiction may require post-quantum while another does not

This is **individual operator sovereignty**, not a network-wide state variable.

**Validator Configuration:** Validators configure their preferred signing algorithm in their validator config file:

```toml
[signing]
# Preferred algorithm for witness signatures
# Options: "ed25519", "dilithium", "sphincs+"
# Default: "ed25519"
preferred_algorithm = "ed25519"
```

The validator signs outbound witness signatures using their preferred algorithm. However, the validator MUST accept and verify ALL three algorithms on inbound signatures. The `preferred_algorithm` setting controls only what the validator produces, never what it accepts.

**Important:** Witness signatures are ephemeral — verified in real-time, not stored for decades. The quantum threat to witness signatures is lower than to long-lived identity keys. Ed25519 remains safe for witness signing during the classical computing era (estimated through 2035+). Validators who want stronger guarantees can use Dilithium or SPHINCS+ at any time without protocol changes.

### 16.5 Market-Driven Algorithm Selection

**Who decides which algorithm to use?**

**Validators, per transaction.**

Each validator operator sets their algorithm preference based on:
- current threat landscape
- client requirements for the specific transaction
- performance requirements
- market positioning (security vs speed)

**How migration occurs:**

1. **Threat emerges** (e.g., Ed25519 weakness discovered)
2. **Validators independently switch** to Dilithium or SPHINCS+
3. **Economic pressure forms** — clients seeking validator services see security preferences
4. **Market naturally migrates** — no committee, no vote, no coordination

**Competitive dynamics:**
- A validator running SPHINCS+ can advertise "quantum-proof validation"
- A validator running Ed25519 can offer lower fees due to efficiency
- A validator may offer tiered pricing: Ed25519 for standard, Dilithium for premium
- Clients choose based on security/cost tradeoffs

This is **not** a network-wide state variable.
This is **individual operator sovereignty**, applied per transaction.

### 16.6 Core Implementation: Outbound Path

The outbound Core validates and signs data leaving the client:

```c
#include "axiom.h"

int entry(uint8_t *vault) {
    uint32_t op = *(uint32_t *)(vault + OFFSET_GATEWAY_OP);
    void *data = vault + OFFSET_PAYLOAD;
    uint32_t len = *(uint32_t *)(vault + OFFSET_DATA_LEN);

    // Sovereign policy check: ensure outbound data matches user intent
    if (!check_sovereign_policy(data, len)) return -1;

    // Execute cryptographic operation based on operator preference
    switch (op) {
        case OP_ED25519:   
            return helper_call(SYS_SIGN_FAST, data, len);
        case OP_DILITHIUM:
        case OP_SPHINCS:   
            return helper_call(SYS_SIGN_PQC, data, len);
        default:           
            return -2; // Unknown algorithm, reject
    }
}
```

**Key properties:**
- `check_sovereign_policy()`: Validates that outbound data matches user authorization
- Algorithm selection is **read** from Vault, not **decided** by Core
- Core never makes policy decisions -- it enforces them

#### 16.6.1 Transaction Validation Rules

Before signing any transaction, Core performs protocol-level validation to ensure compliance with network rules. These checks occur within `check_sovereign_policy()` and related validation functions.

**Mandatory validation checks:**

1. **TTL constraint**
   ```c
   if (tx.ttl > 10) return INVALID;
   ```
   - Prevents network propagation storms
   - Hard protocol limit (Section 18.5)
   - Requests for TTL > 10 are rejected

2. **Timestamp validity**
   ```c
   uint64_t current_time = get_current_timestamp();
   if (tx.timestamp >= current_time) return INVALID;
   ```
   - **Must be in the past**: Transaction timestamp records when it was created
   - Future timestamps are rejected (prevents pre-signing with arbitrary validity)
   - Transactions are valid records of past events, not future commitments

   **Note:** This creates a clock synchronization requirement. Clients with clocks running behind may create transactions that validators reject immediately. NTP synchronization is recommended.

3. **Witness count constraints**
   ```c
   uint32_t witness_count = tx.witness_set.length;
   if (witness_count < 3) return INVALID;   // Minimum security threshold
   if (witness_count > 5) return INVALID;   // Maximum coordination limit
   ```
   - Minimum k=3: Assurance Tier 3 (Section 6.2)
   - Maximum k=5: Assurance Tier 5
   - Valid range: 3, 4, or 5 witnesses
   - No single or dual-witness transactions allowed

**Additional validation (implementation-specific):**

- Signature verification on `prev_receipts`
- Balance sufficiency check
- Nonce uniqueness
- State transition validity

4. **Dust limit (anti-spam)**
   ```c
   MINIMUM_TX_ATOMS = 500000;  // 500,000 atoms = 0.00005 AXC
   is_protocol_tx = (receiver == BURN_ADDRESS || receiver == DEED_ADDRESS || receiver == FEE_ADDRESS);
   if (tx.amount == 0) return E_ZERO_AMOUNT;
   if (!is_protocol_tx && tx.amount < MINIMUM_TX_ATOMS) return E_DUST_AMOUNT;
   ```
   - Protocol-enforced minimum transaction amount: 500,000 atoms (0.00005 AXC)
   - At EMVT (`$7,000/AXC`): 500,000 atoms = `$0.35`
   - At `$15,000/AXC` (50-year projection): 500,000 atoms = `$0.75`
   - Prevents scar-spam attacks (YPX-002 Section 10.2, G2)
   - Core rejects at CL2 before signature verification (cheap check first)
   - Zero amount caught separately for clearer error reporting
   - **Protocol address bypass:** `BURN_ADDRESS`, `DEED_ADDRESS`, and `FEE_ADDRESS`
     are exempt from the dust limit. Burn amounts match scarred link values (may be
     sub-dust). DEED payments (10 atoms for registration) and fee transactions are
     protocol-mandated small amounts. These addresses also skip `wallet_id` checksum
     validation (they are not real wallets).

**Validation failure behavior:**

If any verification fails:
- Transaction is **not signed**
- Error code returned to Gateway
- No network propagation occurs
- User informed of specific validation failure

**Why Core validates:**

These checks protect the network from:
- Malicious Gateway implementations
- Compromised client software
- User misconfiguration

Core is the **final authority** before cryptographic commitment. Even if Gateway is malicious, Core enforces protocol rules.

**Operator override: NONE**

Validation rules are hardcoded in Core. Operators cannot:
- Disable validation checks
- Lower TTL limits
- Accept fewer than 3 witnesses
- Override timestamp constraints

This ensures protocol integrity regardless of operator intentions.

#### 16.6.2 Algorithm Implementation Maturity (2026)

The three algorithm slots defined in Section 16.4 are not merely theoretical preparations for future threats-they are built on production-ready, NIST-standardized implementations available today.

**Algorithm Status:**

| Algorithm  | Standard        | Status (2026)          | Maturity Level |
|------------|-----------------|------------------------|----------------|
| Ed25519    | RFC 8032 (2015) | Production (15 years)  | Mature [x]       |
| Dilithium  | FIPS 204 (2024) | Production (2 years)   | Standardized [x] |
| SPHINCS+   | FIPS 205 (2024) | Production (2 years)   | Standardized [x] |

**NIST Post-Quantum Cryptography Standardization:**

Both Dilithium (FIPS 204) and SPHINCS+ (FIPS 205) underwent rigorous validation through NIST's Post-Quantum Cryptography Standardization project (2016-2024), surviving eight years of intensive cryptanalysis by the global cryptographic community. This process included:

- 82 initial submissions (2016)
- Three rounds of elimination with increasing scrutiny (2018-2022)
- Formal security proofs and analysis
- Side-channel attack resistance evaluation
- Performance optimization and implementation validation
- Final standardization as Federal Information Processing Standards (2024)

**Industry Adoption (2024-2026):**

Post-quantum algorithms are already deployed in production environments by major technology companies:

- **Google:** Chrome TLS connections using Dilithium hybrid mode
- **Cloudflare:** Post-quantum TLS option available on global CDN
- **Amazon Web Services:** KMS post-quantum encryption mode (ML-KEM family)
- **Signal Protocol:** PQXDH protocol deployment to billions of users (2024)

These real-world deployments provide validation that post-quantum cryptography libraries are production-ready and operating at scale.

**Threat Evolution Timeline:**

The three-algorithm design anticipates the following threat evolution:

- **2026-2035:** Ed25519 remains secure during classical computing era
- **2030-2040:** Quantum warning signs emerge; early adopters begin migration
- **2035-2045:** Practical quantum computers demonstrated; Ed25519 deprecated
- **2045-2075:** Dilithium becomes standard; SPHINCS+ serves premium market
- **2075-2100+:** Hash-based signatures (SPHINCS+) preferred for ultimate security

This phased approach allows **market-driven migration without governance votes or protocol upgrades**, ensuring 100-year survivability as specified in the protocol's design goals.

**Risk Assessment:**

While Dilithium and SPHINCS+ have shorter deployment histories than Ed25519 (2 years versus 15 years), they benefit from:

1. NIST's rigorous standardization process (8 years of global cryptanalysis)
2. Formal security proofs with conservative assumptions
3. Production deployment by industry leaders
4. Multiple independent implementations with cross-validation
5. FIPS certification for government and regulated industries

The overall security risk of deploying post-quantum algorithms today is **lower** than the long-term risk of remaining dependent solely on Ed25519, which will be vulnerable to quantum computing.

**Implementation Guidance:**

For detailed implementation maturity analysis, library selection guidance, and comprehensive risk assessment, implementers MUST consult:

- `AXIOM_GUIDE_Core_v1.1.md` (Appendices A-C: Cryptographic primitives, security timeline, breaking difficulty)
- `PQ_CRYPTO_MATURITY_ANALYSIS.md` (Comprehensive library maturity analysis and industry adoption evidence)

**Protocol Compliance:**

Validators MAY choose any of the three algorithms (Op 1, 2, or 3) based on their security requirements and market positioning. The protocol does NOT mandate specific algorithm choices-this decision remains sovereign to each validator operator. Clients similarly select validators based on their preferred security/performance trade-offs.

This market-driven approach ensures organic migration as threat landscapes evolve, without requiring coordinated network-wide upgrades or governance decisions.

### 16.7 Core Implementation: Inbound Path

The inbound Core verifies data entering the client:

```c
#include "axiom.h"

int entry(uint8_t *vault) {
    uint32_t op = *(uint32_t *)(vault + OFFSET_GATEWAY_OP);
    void *data = vault + OFFSET_PAYLOAD;

    // Protocol-agnostic verification: doesn't care if data came via email, P2P, or morse code
    int verified = 0;
    if (op == OP_ED25519) 
        verified = helper_call(SYS_VERIFY_FAST, data, ...);
    else 
        verified = helper_call(SYS_VERIFY_PQC, data, ...);

    // Secondary audit: ensure verified data passes security policy
    return (verified == 1 && final_audit(data)) ? 1 : 0;
}
```

**Key properties:**
- Source-agnostic: Email, P2P, offline receipts are treated identically
- Two-stage verification: cryptographic + policy
- Fail-closed: any uncertainty returns rejection

### 16.8 Gateway: Protocol Translation Layer

Gateway is **not** part of Core.
Gateway is the **mutable interface** to the outside world.

**Current Gateway implementations:**
- `gateway_email_in` -- extracts transactions from email
- `gateway_p2p_in` -- receives P2P network packets
- `gateway_offline_in` -- processes Ark-Mode OLE receipts

**Future Gateway possibilities:**
- `gateway_morse_in` -- decodes morse code transmissions
- `gateway_sat_in` -- receives satellite broadcasts
- `gateway_mesh_in` -- processes mesh network packets

**Critical design choice:**
When communication protocols change, update Gateway.
**Never** update Core.

### 16.8.0 Unified Message Payload (UMP)

**UMP (Unified Message Payload)** is the standard message format used by ALL Gateways in the AXIOM ecosystem.

> **Etymology & Fun Fact:** 
> 
> An "ump" is a person whose job is to make sure that a sports contest or game is played fairly and that the rules are not broken. "Ump" is an abbreviation for "umpire."
>
> This is surprisingly fitting for AXIOM validators - they are the umpires ensuring every transaction plays by the rules. So when you see UMP, think of validators as the fair arbiters of the financial game.

#### 16.8.0.1 Design Principle

ANTIE, UNCLE, and COUSIN are different *carriers* (Email, Socket, Email), but they all carry the **same UMP structure**:

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=2.5cm, minimum height=0.7cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth}
]
\node[box, draw=axiom-blue, fill=axiom-blue!10] (A) at (-3,0) {ANTIE\\{\scriptsize Email}};
\node[box, draw=axiom-blue, fill=axiom-blue!10] (U) at (0,0) {UNCLE\\{\scriptsize Socket}};
\node[box, draw=axiom-blue, fill=axiom-blue!10] (C) at (3,0) {COUSIN\\{\scriptsize Email}};
\node[box, draw=axiom-blue, fill=axiom-blue!20] (UMP) at (0,-1.5) {UMP\\{\scriptsize Unified Message Payload}};
\draw[arrow] (A) -- (UMP);
\draw[arrow] (U) -- (UMP);
\draw[arrow] (C) -- (UMP);
\end{tikzpicture}
\caption{Carrier Convergence --- All transport gateways produce the same UMP structure.}
\end{figure}
```

| Gateway | Transport | License |
|---------|-----------|---------|
| **ANTIE** | Email, Radio, SMTP, P2P | GPL v3 |
| **UNCLE** | Direct connection, Socket | Apache 2.0 |
| **COUSIN** | Email, P2P, Steganography | GPL v3 |

**The carrier changes; the payload format does not.**

#### 16.8.0.2 UMP Structure

The UMP is the **logical model** for all AXIOM messages. The wire format is CBOR (see §16.8.5.7). The C struct below represents the logical fields; actual encoding uses CBOR maps with text string keys.

```c
struct UMP {
    // Header
    uint32_t  protocol_version;    // UMP version
    uint8_t   payload_type;        // Message type (see PayloadType enum)
    uint8_t   tier;                // Security tier (3, 4, or 5)
    uint8_t   salt[16];            // Cryptographic salt
    
    // Transaction Core
    char      tx_id[64];           // Transaction identifier
    char      from_address[256];   // Sender address (see 16.14 Address Format)
    char      to_address[256];     // Recipient address (see 16.14 Address Format)
    pubkey_t  sender_pk;           // Sender public key (for signature verification)
    uint64_t  amount_atom;         // Amount in atoms
    int64_t   timestamp;           // Unix timestamp
    
    // Signatures
    sig_t     client_sig;          // Client signature
    sig_t     witness_sigs[];      // Witness signatures (k=3/4/5)
                                   // See Section 26.9 for WitnessSig structure
                                   // See Section 26.9.2 for WitnessReceipt (client storage)
    
    // Gateway-specific content
    bytes     text;                // Content varies by Gateway:
                                   //   ANTIE: UTF-8 memo
                                   //   UNCLE: SWIFT MT message (ASCII)
                                   //   COUSIN: UTF-8 JSON array
};
```

> **NOTE:** the C struct above is a high-level conceptual summary. The
> actual wire format used by every conformant client is a two-layer CBOR
> structure described in §16.8.0.2a below. When the two diverge, §16.8.0.2a
> is normative.

#### 16.8.0.2a UMP Wire Format (NORMATIVE)

Every UMP on the wire is a two-layer CBOR structure: an **outer envelope** addressed to a Gateway, wrapping a per-`message_type` **inner payload**.

##### Outer Envelope

For ANTIE-routed UMPs, the envelope is an SMTP message whose subject line carries the routing metadata:

```
From:       <sender_email>
To:         <recipient_email>
Subject:    AXIOM/<message_type>/<request_id>     [or sender-supplied; see subject_hint]
Message-ID: <smtp_message_id>
<headers>

<base64-CBOR-encoded inner payload>
```

For UNCLE-routed UMPs the envelope is the SWIFT MT message header; for COUSIN-routed UMPs it is the JSON post envelope. In all cases the envelope carries: sender address, recipient address, `message_type`, `request_id`, and a transport-specific message identifier.

##### Inner Payload (CBOR map)

The inner payload is a CBOR map (text-string keys) containing the fields below. Field presence depends on `message_type`. **All fields are optional unless otherwise noted; absence means "not applicable to this message type."**

```cddl
ump-payload = {
    ; --- Witness-request fields (message_type = "tx_witness") ---
    ? "transaction":           Transaction,        ; see §15
    ? "overlapped_signatures": [* WitnessSig],     ; S-ABR overlap proof
    ? "prev_receipts":         [* Receipt],        ; required for non-genesis
    ? "declared_balance":      uint,
    ? "offered_fee":           uint,
    ? "cl1_execution_proof":   bstr,               ; CL1 ZKP proof
    ? "sender_fact_chain":     FactChain,          ; YPX-001
    ? "fact_witness_sigs":     [* WitnessSig],     ; redeem-path FACT sigs
    ? "nabla_hint":            NablaHint,          ; YPX-002 §3.2 sticky Nabla
    ? "clara_attestation":     ClaraAttestation,   ; YPX-018 heal flow
    ? "auth_hash":             bstr,               ; §17.11 wallet protection
    ? "group_member_index":    uint,               ; group-wallet TXs

    ; --- Redeem-request fields (message_type = "redeem") ---
    ? "cheque_bundle":       ChequeBundle,         ; k validator cheques
    ? "current_state":       { "public_key": bstr,
                               "balance":    uint,
                               "wallet_seq": uint,
                               "state_id":   bstr },
    ? "receiver_pk":         bstr,
    ? "receiver_sig":        bstr,
    ? "txid_attestation":    TxidAttestation,      ; YPX-014
    ? "cheque_claim_proof":  ChequeClaimProof,     ; CL5 Step 3.5b (§39.9.7)

    ; --- Genesis-claim fields (message_type = "init_genesis_dev") ---
    ? "public_key":     bstr,
    ? "balance":        uint,
    ? "group_members":  [* GroupMember],

    ; --- Audit-flow fields (per YPX-009 audit ping/pong) ---
    ? "audit_confirmation": AuditConfirmation,
    ? "nonce_response":     NonceResponse,
    ? "audit_response":     PulseAuditResponse,
}
```

The reference Rust producer is `axiom-sdk::send::build_witness_payload_cbor_v3` (and the corresponding redeem / genesis builders); the reference consumer is `axiom-antie::email::AntiePayload`. Conformant implementations MUST produce/consume the same field set and CBOR encoding.

##### `Transaction` Carries `subject_hint`

The optional sender-supplied display label for the carrier transport (introduced for ANTIE's email subject; ignored by other carriers) lives **inside the signed `Transaction` struct**, not on the envelope. This keeps the value covered by `Transaction.client_sig` so a Gateway cannot substitute it. See §16.8.0.3a.

#### 16.8.0.3a `subject_hint` (Carrier Display Label)

`subject_hint` is an OPTIONAL sender-supplied UTF-8 string on `Transaction`. It is the **only** Transaction field that a Gateway is permitted to read into transport-level metadata; all other Transaction content is opaque to the Gateway and forwarded to Core/Lambda unchanged (see §8 Layer Roles).

**Carrier behavior (NORMATIVE):**

- **ANTIE** — if `Transaction.subject_hint` is present and non-empty, ANTIE MUST use it verbatim as the SMTP `Subject:` header *content* (after the routing prefix `AXIOM/<message_type>/<request_id>`, or as the entire subject for outbound cheque emails where routing is implicit in `To:`). If absent or empty, ANTIE MUST substitute a default subject (e.g., `[AXIOM]` or a payload-type-specific default like `[AXIOM cheque]`).
- **UNCLE / COUSIN / future carriers** — MUST ignore `subject_hint`. The field has no semantics in transports without a notion of subject line.
- **Validators (Lambda, Core)** — MUST NOT read or validate `subject_hint`. The field is signed by `client_sig` along with the rest of `Transaction`, so Core's commitment hash *includes* it (sender-authenticated), but no protocol predicate is gated on the value.

**Privacy and abuse considerations (INFORMATIVE):**

`subject_hint` is broadcast in plaintext to every SMTP relay, anti-spam middlebox, and inbox-list reader between sender and receiver. Senders are responsible for the content. The field is NOT for private payment memos — that role belongs to `Transaction.reference`, which lives inside the encrypted/encoded inner payload and is only visible after the receiver decodes the cheque.

A receiver inbox-filtering use case (e.g., "find all AXIOM mail addressed to me") is *not* solved by `subject_hint` because the value varies per transaction. Such filtering is a wallet-app concern (parse all incoming mail, identify AXIOM payloads from CBOR magic) and is out of scope for the protocol.

**Length:** SHOULD NOT exceed 200 bytes. Carriers MAY truncate longer values for transport-format compatibility (e.g., RFC 5322 line-length limits in SMTP).

**Layer-boundary exception:** `subject_hint` is the single, documented exception to the §8 rule that ANTIE never reads `Transaction` fields. The exception exists because the field's purpose IS transport-level display; no other `Transaction` field has this property.

#### 16.8.0.3 Address Format in UMP

Addresses follow the format specified in Section 16.14:

```
email/checksum-salt

Example: alice@example.com/a3f-7b2-32
```

**In UMP fields:**
- `from_address`: Sender's wallet address (internal format, no dashes)
- `to_address`: Recipient's wallet address (internal format, no dashes)

**Example:**
```json
{
  "from_address": "alice@example.com/a3f7b232",
  "to_address": "bob@example.com/9e2d4f7a",
  "sender_pk": "base64_encoded_public_key...",
  "amount_atom": 100000000
}
```

**Validation:** axiom-core.elf validates both addresses using the checksum formula before processing. Invalid addresses are rejected immediately.

See Section 16.14 for complete address format specification.

#### 16.8.0.4 PayloadType Values

**Transaction Types (require k=3/4/5 witness):**

| Type | Value | Description |
|------|-------|-------------|
| TxValidate | 0x01 | Standard ANTIE transaction |
| TxSwift | 0x02 | UNCLE transaction with SWIFT message |

**Cheque Types (single signature, k=1):**

| Type | Value | Description |
|------|-------|-------------|
| Cheque | 0x10 | Validator to Recipient cheque |
| DeedCheque | 0x11 | DEED distribution cheque |
| FeeCheque | 0x12 | Validator fee cheque |

**State Update Types (require k + overlap):**

| Type | Value | Description |
|------|-------|-------------|
| StateUpdateRequest | 0x20 | Standard State Update (needs 3/4/5 cheques) |
| DeedStateUpdate | 0x21 | DEED State Update (needs 1 cheque) |
| FeeStateUpdate | 0x22 | Validator Fee State Update (needs 1 cheque) |

**Social Types:**

| Type | Value | Description |
|------|-------|-------------|
| Social | 0x30 | COUSIN social posts batch |

**V2V Types (Validator-to-Validator):**

| Type | Value | Description |
|------|-------|-------------|
| V2VWitnessRequest | 0x40 | Witness request |
| V2VWitnessResponse | 0x41 | Witness response |
| V2VStateSync | 0x42 | State synchronization |
| V2VConsole | 0x43 | Console announcement |
| V2VPing | 0x44 | Validator heartbeat |
| V2VGossip | 0x45 | Validator gossip |
| V2VVBCRequest | 0x46 | Request VBC for a validator |
| V2VVBCResponse | 0x47 | VBC response with proof bundle |
| V2VVBCGossip | 0x48 | Proactive VBC sharing |

**Diffusion Types (Core CL10 verified — see §18.8):**

| Type | Value | Description |
|------|-------|-------------|
| FanOut | 0x50 | Core-verified diffusion message (§18.8). Content type in payload (u16). |

#### 16.8.0.5 Text Field Usage

The `text` field is opaque to axiom-core.elf but carries type-specific content:

| Gateway | payload_type | text Field Content |
|---------|--------------|-------------------|
| **ANTIE** | TxValidate | General memo ("Payment for invoice #12345") |
| **UNCLE** | TxSwift | SWIFT MT message ("{1:F01BANKUS33...}{4:...") |
| **COUSIN** | Social | Social posts JSON ("[{post_id:'abc',...},...]") |

#### 16.8.0.6 VBC Payload Types

**Validator Birth Certificate (VBC)** messages enable validators to exchange proof of legitimacy rooted in the AXIOM genesis root keys.

**Cross-Reference:** See Section 23.13 for VBC protocol rules, AXIOM_DESIGN_VBC_v1_3.md for complete specification.

**VBC Request (0x46):**

```rust
struct VBCRequest {
    validator_pubkey: Vec<u8>,     // Validator pubkey to request VBC for
    include_bundle: bool,          // Include full proof bundle (vs just the VBC)
}
```

**VBC Response (0x47):**

```rust
struct VBCResponse {
    vbc: VBC,                      // The requested VBC
    bundle: Option<VBCProofBundle>,// Optional proof bundle to genesis
    error: Option<String>,         // Error message if VBC not found
}
```

**VBC Gossip (0x48):**

```rust
struct VBCGossip {
    vbcs: Vec<VBC>,                // VBCs being shared proactively
}
```

#### 16.8.0.7 VBC Object Structure

```rust
struct VBC {
    version: u8,                           // VBC format version (currently 1)
    subject_validator_id: [u8; 32],        // BLAKE3(subject_pubkey_sphincs)
    subject_pubkey_sphincs: Vec<u8>,       // SPHINCS+ public key (mandatory, VBC identity)
    subject_pubkey_ed25519: Vec<u8>,       // Ed25519 public key (operational signing)
    issued_at: u64,                        // Unix timestamp
    expires_at: u64,                       // Unix timestamp
    chain_depth: u8,                       // 0 = genesis root, 1 = signed by root, etc.
    issuer_set: Vec<[u8; 32]>,            // Exactly 3 issuer validator_ids (distinct)
    signatures: Vec<Vec<u8>>,             // Corresponding SPHINCS+ signatures
    founding_vbc_hash: [u8; 32],          // BLAKE3 hash of validator's first VBC (lineage)
}

struct VBCProofBundle {
    target_vbc: VBC,                       // The VBC being proven
    chain: Vec<VBC>,                       // Supporting VBCs back to genesis roots
}
```

**Verification rules (enforced by Core):**

- Version must be 1
- `chain_depth` must be consistent across chain
- Exactly 3 issuers and 3 signatures, all distinct
- `validator_id == BLAKE3(subject_pubkey_sphincs)`
- Ed25519 public key present and non-empty
- Timestamps not expired (skipped in dev mode)
- Each SPHINCS+ signature verified against issuer's public key
- Recursive chain walk to genesis root authority keys
- Cycle detection (no validator appears twice in chain)
- Maximum chain depth: 10 levels

#### 16.8.0.8 WitnessSig Structure

The WitnessSig is the core data unit that proves a validator witnessed a transaction. As of v2.4.0, it carries the full VBC chain.

```json
{
    "validator_id": [/* 32 bytes - BLAKE3(sphincs_pk) */],
    "validator_pk": [/* 32 bytes - Ed25519 public key */],
    "signature": [/* 64 bytes - Ed25519 signature over commitment_hash */],
    "commitment_hash": [/* 32 bytes */],
    "carrier_address": "alpha@axiom",
    "hints": [/* ValidatorHint array, 0-3 entries */],
    "vbc_bundle": {
        "target_vbc": {
            "version": 1,
            "subject_validator_id": [/* 32 bytes */],
            "subject_pubkey_sphincs": [/* SPHINCS+ pk bytes */],
            "subject_pubkey_ed25519": [/* 32 bytes */],
            "issued_at": 1707700000,
            "expires_at": 1739236000,
            "chain_depth": 1,
            "issuer_set": [/* 3 x 32-byte validator_ids */],
            "signatures": [/* 3 SPHINCS+ signatures */],
            "founding_vbc_hash": [/* 32 bytes */]
        },
        "chain": [/* Supporting VBCs back to genesis */]
    },
    "validator_hints": [
        {
            "validator_id": "hex-string",
            "name": "axiom-fp-beta",
            "carriers": ["email:beta@axiom"],
            "last_seen": 1707700000
        }
    ]
}
```

**VBC verification at every checkpoint:**
- **CL2** (Gateway/Core): Validates all witnesses in prev_receipts have valid VBC chains
- **CL3** (Lambda/Core): Defense-in-depth re-verification
- **CL4** (Client/Core): Client verifies witnesses before accepting

The `vbc_bundle` field uses `#[serde(default)]` for backwards compatibility. When absent or null, it deserializes as None. In dev/test mode, None is allowed. Production mode will enforce VBC requirement.

#### 16.8.0.9 Payload Validation

Before transmission, Core_in validates:
- Payload structure integrity
- Required fields present
- Signature format valid
- Protocol version compatible
- Address format valid (see Section 16.14)

**Invalid payloads are rejected immediately and never reach Lambda.**

#### 16.8.0.10 Gateway VBC Handling

Gateway is **cryptographically blind** to VBC contents (same as other payloads).

Gateway responsibilities:
- Transport VBC messages between validators
- Pass VBC data to Lambda for storage/caching
- Fetch VBCs from remote validators on request

Gateway does NOT:
- Verify VBC signatures (Core's job)
- Cache VBCs (Lambda's job)
- Assemble proof bundles (Lambda's job)

### 16.8.1 Gateway Types (ANTIE / UNCLE / COUSIN)

**Terminology:** Gateway is also referred to as **Agent** in some contexts. The terms are interchangeable in this document.

AXIOM defines three primary Gateway implementations:

| Gateway | License | Primary Use | Transport |
|---------|---------|-------------|-----------|
| **ANTIE** | GPL v3 | Survival broadcast | Email, Radio, SMTP, P2P |
| **UNCLE** | Apache 2.0 | Institutional/Business | Direct connection, Port/Socket |
| **COUSIN** | GPL v3 | Social diffusion | Email, P2P, Steganography |

**ANTIE (Advanced Normalised Transmission Intermedia Extension)**
- Survival-grade message transport
- Designed for degraded, partitioned, or hostile infrastructure
- GPL v3 ensures open auditability

**UNCLE (Universal Non-linear Clearing Layer Extension)**
- Institutional interface for banks and enterprises
- Apache 2.0 allows proprietary extensions
- Expected to support faster implementations (direct connections)

**COUSIN (Covert Overlay for Uncensored Social Information Network)**
- Social message propagation layer
- High-penetration diffusion for censored environments
- See AXIOM_DESIGN_COUSIN.md for detailed specification

**All Gateways carry the same UMP (Unified Message Payload) structure.**

COUSIN Social (!"*(R)?!) uses the `text` field within the standard payload to deliver social messages as defined in the COUSIN Protocol.

### 16.8.2 System Architecture Overview

**Client Naming:** The following terms refer to the same entity in different contexts:
- Client
- Client Wallet
- AXC Holder
- COUSIN Social Client

#### Architecture Diagram

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=2.8cm, minimum height=0.7cm, align=center, font=\small},
    group/.style={rounded corners=6pt, draw=axiom-gray, dashed, inner sep=8pt},
    arrow/.style={->, thick, >=stealth},
    biarrow/.style={<->, thick, >=stealth}
]
\node[box, draw=axiom-blue, fill=axiom-blue!8] (CT) at (-4,0) {Client\\Transporter};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (DMAP-VMC) at (-4,-1.5) {DMAP-VM + Core ELF\\+ Vault};
\node[box, draw=axiom-blue, fill=axiom-blue!8] (GW) at (4,0) {Gateway\\{\scriptsize ANTIE/UNCLE/COUSIN}};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (DMAP-VMV) at (4,-1.5) {DMAP-VM + Core ELF\\+ Vault};
\node[box, draw=axiom-blue, fill=axiom-blue!25] (L) at (4,-3) {Lambda k=3};
\begin{scope}[on background layer]
\node[group, fit=(CT)(DMAP-VMC), label={[font=\small\bfseries]above:Client}] {};
\node[group, fit=(GW)(DMAP-VMV)(L), label={[font=\small\bfseries]above:Validator}] {};
\end{scope}
\draw[arrow] (CT) -- (DMAP-VMC);
\draw[arrow] (GW) -- (DMAP-VMV);
\draw[arrow] (DMAP-VMV) -- (L);
\draw[biarrow] (CT) -- node[above, font=\scriptsize] {Email/Socket/Radio/P2P} (GW);
\end{tikzpicture}
\caption{Client-Validator Architecture --- Both sides run the same Core ELF on DMAP-VM.}
\end{figure}
```

#### Component Summary

| Location | Component | Function |
|----------|-----------|----------|
| **Client** | DMAP-VM | Sandboxed execution environment |
| **Client** | axiom-core.elf | Cryptographic operations (Core_in/Core_out) |
| **Client** | Vault | Isolated memory interface |
| **Client** | Client Transporter | Carrier interface (send/receive) |
| **Validator** | Gateway | External carrier interface (ANTIE/UNCLE/COUSIN) |
| **Validator** | DMAP-VM | Sandboxed execution environment |
| **Validator** | axiom-core.elf | Cryptographic operations (Core_in/Core_out) |
| **Validator** | Vault | Isolated memory interface |
| **Validator** | Lambda | k=3 consensus logic (Validator only) |

#### Data Flow

| Direction | Flow |
|-----------|------|
| **Client -> Validator** | Client DMAP-VM `Core_out` -> Client Transporter -> [Carrier] -> Gateway -> Validator DMAP-VM `Core_in` -> Lambda |
| **Validator -> Client** | Lambda -> Validator DMAP-VM `Core_out` -> Gateway -> [Carrier] -> Client Transporter -> Client DMAP-VM `Core_in` |

### 16.8.3 Core: Single Binary, Dual Functions

**Critical Clarification:** Core_in and Core_out are **not two separate binaries**. They are logical descriptions of the same `axiom-core.elf` operating in different directions.

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=3.5cm, minimum height=0.7cm, align=center, font=\small},
    biarrow/.style={<->, thick, >=stealth}
]
\node[box, draw=axiom-blue, fill=axiom-blue!10] (I) at (-4,0) {Core\_in\\{\scriptsize Decrypt $\to$ Validate $\to$ Reject}};
\node[box, draw=axiom-blue, fill=axiom-blue!20] (V) at (0,0) {Vault};
\node[box, draw=axiom-blue, fill=axiom-blue!10] (O) at (4,0) {Core\_out\\{\scriptsize Encrypt $\to$ Package $\to$ Enforce}};
\draw[biarrow] (I) -- (V);
\draw[biarrow] (V) -- (O);
\end{tikzpicture}
\caption{Core Dual Functions --- Same ELF binary, two logical directions through Vault.}
\end{figure}
```

| Function | Core_in | Core_out |
|----------|---------|----------|
| **Purpose** | Inbound processing | Outbound processing |
| **Actions** | Decrypt, Validate, Reject | Encrypt, Package, Enforce |
| **Data Flow** | External -> Vault | Vault -> External |

**Both Client and Validator run the same `axiom-core.elf` on DMAP-VM, accessing data through Vault.**

#### Where Core Runs

| Location | Core_in Function | Core_out Function |
|----------|------------------|-------------------|
| **Client DMAP-VM** | Decrypt/verify incoming data | Sign/encrypt outgoing data |
| **Validator DMAP-VM** | Decrypt/validate incoming payloads | Encrypt/package outgoing responses |

#### Core_in (Inbound Processing)

When data arrives:

| Function | Description |
|----------|-------------|
| **Decrypt** | Decrypt encrypted payload |
| **Validate** | Basic format validation |
| **Reject** | Immediately reject malformed payloads |
| **Forward** | Pass valid data to next stage |

**Rejection criteria:**
- Malformed payload structure
- Invalid encryption
- Missing required fields
- Protocol version mismatch

#### Core_out (Outbound Processing)

When data leaves:

| Function | Description |
|----------|-------------|
| **Encrypt** | Encrypt payload for transmission |
| **Package** | Encapsulate in Gateway-ready format |
| **Sign** | Apply cryptographic signature |
| **Enforce** | Bootstrap retirement logic (Validator only) |

#### Critical Functions (Binary-Enforced)

Beyond encryption/decryption, `axiom-core.elf` contains:

1. **Bootstrap Retirement Logic** -- Enforces the sunset of founding control
2. **DEED Distribution** -- Ensures correct distribution during protocol phases
3. **Format Gatekeeping** -- Rejects non-compliant payloads before they consume resources

**These functions are binary-enforced, not configurable.**

### 16.8.4 Complete Data Flow

**Client -> Validator (Outbound from Client):**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=3cm, minimum height=0.7cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth},
    label/.style={font=\scriptsize, midway, right, xshift=2pt}
]
\node[box, draw=blue!50, fill=blue!5] (C) at (0,0) {Client};
\node[box, draw=orange!50, fill=orange!5] (CA) at (0,-1.5) {Client DMAP-VM\\{\scriptsize Core\_out via Vault}};
\node[box, draw=purple!50, fill=purple!5] (GW) at (0,-3) {Gateway\\{\scriptsize ANTIE/UNCLE/COUSIN}};
\node[box, draw=orange!50, fill=orange!5] (VA) at (0,-4.5) {Validator DMAP-VM\\{\scriptsize Core\_in via Vault}};
\node[box, draw=green!50, fill=green!5] (L) at (0,-6) {Lambda k=3};
\draw[arrow] (C) -- (CA);
\draw[arrow] (CA) -- node[label] {Sign, Encrypt, Package} (GW);
\draw[arrow] (GW) -- (VA);
\draw[arrow] (VA) -- node[label] {Decrypt, Validate, Reject} (L);
\end{tikzpicture}
\caption{Client to Validator Data Flow --- Outbound from client perspective.}
\end{figure}
```

**Validator -> Client (Outbound from Validator):**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=3cm, minimum height=0.7cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth},
    label/.style={font=\scriptsize, midway, right, xshift=2pt}
]
\node[box, draw=green!50, fill=green!5] (L) at (0,0) {Lambda};
\node[box, draw=orange!50, fill=orange!5] (VA) at (0,-1.5) {Validator DMAP-VM\\{\scriptsize Core\_out via Vault}};
\node[box, draw=purple!50, fill=purple!5] (GW) at (0,-3) {Gateway\\{\scriptsize ANTIE/UNCLE/COUSIN}};
\node[box, draw=orange!50, fill=orange!5] (CA) at (0,-4.5) {Client DMAP-VM\\{\scriptsize Core\_in via Vault}};
\node[box, draw=blue!50, fill=blue!5] (C) at (0,-6) {Client};
\draw[arrow] (L) -- (VA);
\draw[arrow] (VA) -- node[label] {Encrypt, Package} (GW);
\draw[arrow] (GW) -- (CA);
\draw[arrow] (CA) -- node[label] {Decrypt, Verify} (C);
\end{tikzpicture}
\caption{Validator to Client Data Flow --- Outbound from validator perspective.}
\end{figure}
```

### 16.8.5 Gateway-to-Core IPC Wire Protocol

This section defines the communication protocol between Gateway and axiom-core.elf.

#### 16.8.5.1 Frame Format

Gateway and axiom-core.elf communicate via stdin/stdout using length-prefixed framing:

```
+------------------+----------------------------------------+
| Length (4 bytes) |          Payload (N bytes)             |
| Little-endian    |          CBOR-encoded                  |
| uint32           |                                        |
+------------------+----------------------------------------+

Length = N (payload bytes only, not including length field itself)
Max payload: 16 MB (0x01000000)
```

**Design decisions:**
- **Little-endian**: Native format for x86/x64/ARM, no byte swap needed
- **CBOR**: Binary, self-describing, standard (RFC 8949), supports bytes type
- **Length-prefixed**: Simple framing, easy to implement in any language

#### 16.8.5.2 CBOR Encoding Rules

All CBOR encoding MUST follow these rules:

| Field Type | CBOR Major Type | Encoding | Example |
|------------|-----------------|----------|---------|
| tx_id | text string (3) | UTF-8 | "tx_abc123..." |
| memo (ANTIE) | text string (3) | UTF-8 | "Payment for..." |
| text (UNCLE/SWIFT) | byte string (2) | Raw bytes | SWIFT MT uses ASCII subset |
| text (COUSIN) | text string (3) | UTF-8 JSON | "[{post_id:...}]" |
| error_message | text string (3) | UTF-8 | "Invalid signature" |
| signature | byte string (2) | Raw bytes | Binary signature data |
| public_key | byte string (2) | Raw bytes | Binary key data |
| hash | byte string (2) | Raw bytes | Binary hash data |
| amount_atom | unsigned int (0) | Integer | 1000000 |
| timestamp | signed int (1) | Integer | 1737475200 |
| payload_type | unsigned int (0) | Integer | 0x01 |
| tier | unsigned int (0) | Integer | 3, 4, or 5 |

**Note on SWIFT messages:** SWIFT MT messages use a restricted ASCII character set (X/Y/Z sets), not UTF-8. They are transmitted as byte strings to preserve the original format.

#### 16.8.5.3 Request/Response Structure

ALL IPC uses length-prefixed CBOR. This includes Gateway↔Core, Gateway↔Lambda, and Client↔Gateway communication. There is no JSON anywhere in the protocol.

```
+------------------+----------------------------------------+
| Length (4 bytes) |          Payload (N bytes)             |
| Big-endian       |          CBOR-encoded (RFC 8949)       |
| uint32           |                                        |
+------------------+----------------------------------------+
```

**CBOR is the ONLY serialization format in AXIOM. JSON is NOT permitted for any IPC path — internal or external. No exceptions, no fallbacks.**

Core IPC uses `PublicInputs` and `PublicOutputs` structures encoded as CBOR maps with integer keys (not string keys). This is NORMATIVE — implementations MUST use integer keys per §16.8.5.4.

#### 16.8.5.4 Integer Key Registry (NORMATIVE — IMMUTABLE ONCE DEPLOYED)

Core IPC encodes `PublicInputs` and `PublicOutputs` as CBOR maps with canonical integer keys. Integer keys are sorted ascending (shorter CBOR encoding first). Key assignments are immutable — once deployed, they cannot be changed, only extended with new keys.

**Rationale:**
1. Compact wire format (1 byte vs N bytes for string keys)
2. Deterministic encoding (integer sort is unambiguous)
3. ZK-circuit compatibility (no string parsing inside zk-VM guest)

**PublicInputs Key Assignments:**

| Key | Field | Type | Description |
|-----|-------|------|-------------|
| 0 | mode | u64 | CoreLogicMode (0=CL1, 1=CL2, 2=CL3, 3=CL4, 4=CL5/Redeem, 5=CL6/VBC, 6=CL7/NBC verify, 7=CL8/NBC issue, 8=CL9/Scar heal, 9=CL10/Fan-out, 10=CL11/Console) |
| 1 | transaction | map | Transaction struct |
| 2 | prev_receipts | array | Previous receipts for S-ABR |
| 3 | current_state | map/null | Current wallet state |
| 4 | vbc_bundle | blob/null | VBC proof bundle (opaque CBOR) |
| 5 | cheque_bundle | blob/null | Cheque bundle for redeem |
| 6 | receiver_pk | bytes/null | Receiver's public key |
| 7 | receiver_bal | u64/null | Receiver's current balance |
| 8 | receiver_seq | u64/null | Receiver's wallet sequence |
| 9 | receiver_new_bal | u64/null | Receiver's new balance |
| 10 | receiver_new_sid | bytes/null | Receiver's new state ID |
| 11 | my_validator_pk | bytes/null | This validator's Ed25519 PK |
| 12 | overlapped_sigs | array | S-ABR overlapped WitnessSigs |
| 13 | group_member_index | u64/null | Group wallet member index |
| 14 | sender_fact_chain | map/null | Client's FACT chain (YPX-001 §1.6) |
| 15 | dilithium_sk | bytes/null | Validator's Dilithium secret key |
| 16 | dilithium_pk | bytes/null | Validator's Dilithium public key |
| 17 | my_validator_id | bytes/null | Validator ID (BLAKE3(sphincs_pk)) |
| 18 | fact_witness_sigs | array | Accumulated FACT witness sigs |

**PublicOutputs Key Assignments:**

| Key | Field | Type | Description |
|-----|-------|------|-------------|
| 0 | result | u64 | ValidationResult (0=Accept, 1=Reject) |
| 1 | state_hash | bytes/null | New state hash |
| 2 | produced_state_id | bytes/null | Produced state ID (32 bytes) |
| 3 | new_wallet_seq | u64/null | New wallet sequence number |
| 4 | rejection | map/null | Rejection reason (code + message) |
| 5 | is_overlapped | bool/null | S-ABR overlap detection result |
| 6 | commitment_hash | bytes/null | Transaction commitment hash |
| 7 | txid | bytes/null | Transaction ID (32 bytes) |
| 8 | fact_signature | bytes/null | Dilithium FACT commitment signature |
| 9 | new_balance | u64/null | New balance after transaction |

**Nested Structure Keys:**

Transaction (key 1): `{ 0: client_pk, 1: amount, 2: receiver_wallet_id, 3: wallet_seq, 4: consumed_state_id, 5: nonce, 6: epoch, 7: reference, 8: client_sig }`

WitnessSig: `{ 0: validator_id, 1: validator_pk, 2: vbc_bundle(blob), 3: carrier_type, 4: carrier_address, 5: signature, 6: execution_proof, 7: availability_attestation(blob), 8: validator_hints(blob[]), 9: fact_signature, 10: proof_type, 11: receipt_signature }`

**Three signatures, three oracle perspectives.** Each `WitnessSig`
carries up to three Ed25519 / Dilithium signatures from the same
validator, each binding a different aspect of the same transaction:

| Field | Algorithm | Payload | Verifier |
|---|---|---|---|
| `signature` (5) | Ed25519 | Core's `commitment_hash` | Lambda CL2/CL3 — witness consensus |
| `fact_signature` (9) | Dilithium (ML-DSA-65) | `AXIOM_FACT_v2` commitment | Core CL5 + receivers — FACT chain audit |
| `receipt_signature` (11) | Ed25519 | `wallet_id ‖ consumed_state ‖ produced_state ‖ tick_le` | Nabla `/register` — SMT advance authorization |

A validator that signs a TX produces all three. Consumers of the
WitnessSig pick whichever signature their layer needs — Lambda's
ingress checks `signature`, FACT-chain readers check `fact_signature`,
Nabla's k=3 register receipt verifier checks `receipt_signature`.
Conflating them would force one layer to recompute another's
commitment, which violates the layer roles in §31. The third
signature is the cheap (~50 µs Ed25519) cost of clean separation.

Receipt: `{ 0: txid, 1: state_hash, 2: produced_state_id, 3: new_wallet_seq, 4: commitment_hash, 5: sdid, 6: lineage_hash, 7: core_version, 8: witness_sigs, 9: epoch }`

WalletState: `{ 0: public_key, 1: balance, 2: wallet_seq, 3: state_id, 4: auth_hash, 5: group_members, 6: tardis_tick, 7: unix_timestamp }`

**Protocol Time Fields:** Each wallet state includes:
- `tardis_tick: u64` — TARDIS protocol time (currently Unix epoch seconds, 5-second intervals)
- `unix_timestamp: u64` — Reference wall-clock time at state creation

These fields anchor wallet state transitions to the TARDIS timing layer. `tardis_tick` is the authoritative protocol time; `unix_timestamp` is informational.

FactChain: `{ 0: links[], 1: checkpoint }`

FactLink: `{ 0: tx_id, 1: previous_state_id, 2: new_state_id, 3: amount, 4: tick, 5: witnesses[], 6: nabla_confirmation(blob), 7: receiver_contact, 8: burn_proof(blob), 9: required_k, 10: sender_anchor }`

**`sender_anchor` (A2 — receiver-side redeem assembly).** Optional 32-byte field, populated only on REDEEM links. Carries the sender's chain-tip `state_id` at send time, taken from the cheque's `sender_fact_chain.tip().new_state_id`. Lets the receiver's chain anchor to the sender's verified provenance without a separate "bridge" link. Bound into the FACT commitment under the `AXIOM_FACT_v2` domain tag (see Domain Tags), alongside `is_dev_class` and the `inherited_scar_txids` set (YPX-001 §1.5.1a). For SEND / HEAL / BURN links, `sender_anchor` is `None` and encodes as 32 zero bytes inside the commitment hash, and the inherited set is empty. Core CL5 verifies `link.sender_anchor == cheque.sender_fact_chain.tip().new_state_id` at redeem time.

FactWitness: `{ 0: validator_id, 1: validator_pk, 2: signature }`

FactCheckpoint: `{ 0: root_hash, 1: compressed_count, 2: final_state_id, 3: genesis_state_id, 4: total_amount, 5: validator_sigs[], 6: genesis_fact_hash, 7: pending_links }`

**`pending_links` (SEC-07 travel model).** `u64`. The number of leading links in `chain.links` that this checkpoint covers and is still **retaining** (provisional state). While `pending_links > 0` the covered links are physically present and the checkpoint is a proposal accumulating distinct validator co-signatures; verification runs through the real links, and the 3-signature gate does not yet apply. When the proposal reaches `CHECKPOINT_SIG_THRESHOLD` = 3 distinct signatures those links are deleted and `pending_links` becomes `0` (finalized) — only then is the gate enforced. Deliberately **not** folded into `compute_checkpoint_commitment` (the committed bytes must stay identical across the provisional→finalized transition), and not forgeable: the committed `root_hash` pins the covered links, so a lying `pending_links` fails the `compute_checkpoint_root(links[0..pending_links]) == root_hash` check.

**Opaque Blob Encoding:** Complex nested types (VBCProofBundle, ChequeBundle, AvailabilityAttestation, ValidatorHint, NablaConfirmation) use opaque blob encoding: inner struct is serialized via ciborium serde to CBOR bytes, then wrapped as a CBOR byte string. Core deserializes the blob internally. This prevents key collision between inner and outer maps.

**Extension Rule:** New fields MUST use the next available integer key. Existing key assignments MUST NOT change. This ensures wire compatibility across axiom-core.elf versions.

#### 16.8.5.5 Error Handling

| Status | Meaning | Gateway Action |
|--------|---------|----------------|
| 0x00 OK | Validation passed | Forward result to next stage |
| 0x01 ValidationError | Invalid input (expected) | Log, return error to client, continue |
| 0xFF InvariantViolation | Internal error (PANIC) | Log CRITICAL, axiom-core.elf will exit, restart axiom-core.elf |

**IPC Error Handling:**

| Condition | Gateway Action |
|-----------|----------------|
| Read timeout (30s) | Close connection, restart axiom-core.elf |
| Invalid length (> 16MB) | Close connection, restart axiom-core.elf |
| CBOR decode failure | Close connection, restart axiom-core.elf |
| Unexpected EOF | axiom-core.elf crashed, restart axiom-core.elf |

#### 16.8.5.6 Gateway Orchestration Pattern (Normative)

**Critical Architecture Principle:** Gateway is the LISTENER and ORCHESTRATOR. Gateway calls Core CL2 as a pre-filter (`current_state = None`) — rejecting invalid transactions before Lambda sees them. Lambda calls Core CL2 again with real stored state for authoritative validation, and Core CL3 for witness production.

**Component Roles:**

| Component | Listens? | Calls Core? | Role |
|-----------|----------|-------------|------|
| **Gateway** | YES (network) | YES (CL2 + crypto) | Listens, orchestrates, validates via Core |
| **axiom-core.elf** | NO | N/A | Responds to requests (decrypt, CL2, CL3, encrypt) |
| **Lambda** | NO | YES (CL3 only) | Business logic, k=3 consensus, state management |

**CRITICAL: Who Calls What**

| Operation | Who Calls Core? | Mode |
|-----------|-----------------|------|
| Decrypt payload | Gateway | Core_in (crypto) |
| **Validate transaction** | **Gateway** | **CL2** |
| Produce witness | Lambda | CL3 |
| Encrypt response | Gateway | Core_out (crypto) |

**Validator Node Architecture:**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    arrow/.style={->, thick, >=stealth},
    note/.style={font=\scriptsize, text=black!70}
]
% Outer box
\draw[thick, rounded corners=5pt] (-5.2,-2.8) rectangle (5.2,2.2);
\node[font=\small\bfseries, anchor=north] at (0,2.1) {VALIDATOR NODE};

% Components
\node[rounded corners=3pt, thick, draw=blue!60, fill=blue!8,
      minimum width=2.6cm, minimum height=1.4cm, align=center,
      font=\footnotesize, text width=2.2cm] (gw) at (-3.2,0) {Gateway\\ (LISTEN)};
\node[rounded corners=3pt, thick, draw=red!60, fill=red!8,
      minimum width=2.6cm, minimum height=1.4cm, align=center,
      font=\footnotesize, text width=2.2cm] (core) at (0,0) {Core ELF\\ (CRYPTO)};
\node[rounded corners=3pt, thick, draw=green!60!black, fill=green!8,
      minimum width=2.6cm, minimum height=1.4cm, align=center,
      font=\footnotesize, text width=2.2cm] (lambda) at (3.2,0) {Lambda\\ (CONSENSUS)};

% Arrows
\draw[arrow, blue!70] (gw.east) -- node[above, note] {CL2} (core.west);
\draw[arrow, blue!70] (core.west) -- ++(0,-0.3) -| ([yshift=-3pt]gw.east);
\draw[arrow, green!60!black] (lambda.west) -- node[below, note] {CL3} (core.east);
\draw[arrow, green!60!black] (core.east) -- ++(0,0.3) -| ([yshift=3pt]lambda.west);

% Labels
\node[note, anchor=north] at (-1.6,-1.8) {Gateway calls Core for CL2};
\node[note, anchor=north] at (1.6,-2.2) {Lambda calls Core for CL3};
\end{tikzpicture}
\end{figure}
```

**Inbound Flow (Client to Validator) - COMPLETE:**

```
Step 1: Gateway LISTENS on network (email/TCP/etc)
        Gateway receives encrypted payload from Client
        [Gateway cannot read the encrypted contents]

Step 2: Gateway -> axiom-core.elf: DECRYPT
        Request: "Decrypt this payload"
        axiom-core.elf decrypts, returns plaintext to Gateway
        [If decrypt fails: Gateway discards, returns error]

Step 3: Gateway -> axiom-core.elf: VALIDATE (CL2)  ← GATEWAY DOES THIS
        Request: "Validate this transaction"
        axiom-core.elf checks: signature, balance, wallet_seq, receiver
        axiom-core.elf returns: ACCEPT or REJECT
        [If REJECT: Gateway returns rejection to Client, Lambda NEVER SEES IT]

Step 4: Gateway -> Lambda: PRE-VALIDATED transaction
        Lambda receives transaction that ALREADY PASSED CL2
        Lambda does S-ABR checks, k=3 coordination
        Lambda -> axiom-core.elf: WITNESS (CL3)
        Lambda returns result to Gateway

Step 5: Gateway -> axiom-core.elf: ENCRYPT
        Request: "Encrypt this response"
        axiom-core.elf encrypts, returns ciphertext to Gateway

Step 6: Gateway sends encrypted response to Client
```

**Sequence Diagram (COMPLETE with CL2/CL3):**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    arrow/.style={->, thick, >=stealth},
    note/.style={font=\scriptsize, text=black!60},
    actor/.style={font=\small\bfseries},
    reject/.style={font=\scriptsize, text=red!70!black, align=center}
]
% Actors
\node[actor] (client) at (0,0) {Client};
\node[actor] (gw) at (3.5,0) {Gateway};
\node[actor] (core) at (7.5,0) {Core ELF};
\node[actor] (lambda) at (11.5,0) {Lambda};

% Lifelines
\draw[thick, dashed] (0,-0.4) -- (0,-13);
\draw[thick, dashed] (3.5,-0.4) -- (3.5,-13);
\draw[thick, dashed] (7.5,-0.4) -- (7.5,-13);
\draw[thick, dashed] (11.5,-0.4) -- (11.5,-13);

% 1. Client -> Gateway (encrypted)
\draw[arrow] (0,-1) -- node[above, font=\scriptsize] {encrypted payload} (3.5,-1);

% 2. Gateway -> Core: decrypt
\draw[arrow] (3.5,-2) -- node[above, font=\scriptsize] {decrypt} (7.5,-2);
\draw[arrow] (7.5,-2.6) -- node[above, font=\scriptsize] {plaintext} (3.5,-2.6);

% 3. Gateway -> Core: CL2
\draw[arrow, blue!70] (3.5,-3.6) -- node[above, font=\scriptsize] {CL2 validate} (7.5,-3.6);
\draw[arrow, blue!70] (7.5,-4.2) -- node[above, font=\scriptsize] {ACCEPT / REJECT} (3.5,-4.2);
\node[reject] at (5.5,-5.0) {If REJECT: return error, stop};
\draw[dashed, red!50] (1.5,-4.6) -- (9.5,-4.6);

% 4. Gateway -> Lambda: pre-validated tx
\draw[arrow, green!60!black] (3.5,-5.8) -- node[above, font=\scriptsize] {pre-validated TX} (11.5,-5.8);

% 5. Lambda -> Core: CL3
\draw[arrow, green!60!black] (11.5,-6.8) -- node[above, font=\scriptsize] {CL3 witness} (7.5,-6.8);
\draw[arrow, green!60!black] (7.5,-7.4) -- node[above, font=\scriptsize] {witness proof} (11.5,-7.4);

% 6. Lambda -> Gateway: result
\draw[arrow] (11.5,-8.4) -- node[above, font=\scriptsize] {result} (3.5,-8.4);

% 7. Gateway -> Core: encrypt
\draw[arrow] (3.5,-9.4) -- node[above, font=\scriptsize] {encrypt} (7.5,-9.4);
\draw[arrow] (7.5,-10.0) -- node[above, font=\scriptsize] {ciphertext} (3.5,-10.0);

% 8. Gateway -> Client
\draw[arrow] (3.5,-11.0) -- node[above, font=\scriptsize] {encrypted response} (0,-11.0);
\end{tikzpicture}
\end{figure}
```

**Security Invariant: Core as Gatekeeper**

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}
\node[draw=red!70, fill=red!5, rounded corners=6pt, thick,
      text width=11cm, align=left, inner sep=12pt, font=\footnotesize] {
  \textbf{\large SECURITY INVARIANT}\\[6pt]
  Lambda \textbf{NEVER} receives a transaction that has not been
  validated by Core (CL2).\\[6pt]
  Gateway is the \textbf{ONLY} component that calls Core for CL2.\\
  Lambda is the \textbf{ONLY} component that calls Core for CL3.\\[6pt]
  This separation ensures:\\[2pt]
  \begin{itemize}[nosep, leftmargin=1.2em]
    \item Malformed payloads never reach Lambda
    \item Invalid signatures never reach Lambda
    \item Lambda can focus on consensus logic
    \item Core protects Lambda from attack
  \end{itemize}
};
\end{tikzpicture}
\end{figure}
```

**Why Gateway Calls CL2 (NOT Lambda):**

1. **Gateway is the entry point** - First to receive network traffic
2. **Core protects Lambda** - Invalid transactions rejected before Lambda
3. **Clean separation** - Gateway handles external interface, Lambda handles internal logic
4. **Defense in depth** - Two layers: Gateway+Core (perimeter), Lambda (internal)

**What Lambda Does NOT Do:**

- Lambda does NOT listen on network (Gateway does)
- Lambda does NOT decrypt payloads (Gateway + Core does)
- Lambda does NOT encrypt responses (Gateway + Core does)

**What Lambda DOES Do:**

- Lambda receives pre-validated transactions from Gateway
- Lambda checks S-ABR (balance honesty)
- Lambda coordinates k=3 consensus
- Lambda calls CL3 to produce witness proof
- Lambda stores wallet state
- Lambda returns result to Gateway

**Implementation Note:** Gateway implementations (ANTIE, UNCLE, COUSIN) MUST call axiom-core.elf for CL2 validation before passing transactions to Lambda. This is a NORMATIVE requirement. See AXIOM_DESIGN_ANTIE Section 5.1 and AXIOM_GUIDE_Core Section 5.10.5 for implementation details.

#### 16.8.5.7 Client↔Gateway Wire Format (NORMATIVE)

All client↔Gateway communication MUST use **CBOR (RFC 8949)** encoding. This applies to ALL gateway types (ANTIE, UNCLE, COUSIN). JSON is NOT permitted on the client↔Gateway boundary.

**Transport Envelope:**

```
Carrier-specific envelope (email, socket, radio, etc.)
  └── Body: Base64(CBOR-encoded payload)
```

For ANTIE (email carrier), the payload is Base64-encoded CBOR in the email body. For UNCLE (socket carrier), raw CBOR bytes may be sent directly (no Base64 needed). For COUSIN (email carrier), same as ANTIE.

#### 16.8.5.8 Message Size Limits (NORMATIVE)

Each Gateway type MUST enforce transport-appropriate message size limits. Size enforcement is a **Gateway responsibility** — Lambda and Core MUST NOT hardcode transport-specific limits.

| Layer | Limit | Rationale |
|-------|-------|-----------|
| **ANTIE Gateway** | 256 KB per message | Single message per email carrier frame |
| **UNCLE Gateway** | 256 KB per message | Single message per socket frame |
| **COUSIN Gateway** | Up to 16 MB, operator-configurable | Batched payloads for censorship resistance |
| **Lambda IPC** | 16 MB sanity guard | Not a security boundary — trusts co-located Gateway |
| **Core** | No transport limits | Immutable binary, transport-agnostic |

**Rationale:** Core is designed as a fixed binary with a 10+ year lifespan. Transport concerns (message sizes, batching, carrier-specific limits) belong in the replaceable Gateway layer. Operators deploying new Gateway types (e.g., COUSIN with batched payloads) MUST NOT require Core changes.

Gateways MUST reject oversized messages **before parsing** to prevent memory exhaustion. The limit applies to the raw carrier payload (email body, socket frame), not individual CBOR fields.

**CBOR Encoding Rules for Client↔Gateway Payloads:**

| Field Type | CBOR Major Type | Rule |
|------------|-----------------|------|
| Byte arrays (`Vec<u8>`, `[u8; 32]`, signatures, keys, hashes) | byte string (2) | Raw bytes, NOT integer arrays |
| Arrays of byte arrays (`issuer_set`, `signatures`) | array (4) of byte strings (2) | Each element is a CBOR byte string |
| Text strings (addresses, IDs, references) | text string (3) | UTF-8 |
| Integers (amounts, seq numbers, timestamps) | unsigned int (0) or signed int (1) | Standard CBOR integer |
| Booleans | simple value (7) | true (0xf5) / false (0xf4) |
| Null | simple value (7) | null (0xf6) |
| Maps (objects) | map (5) | Text string keys |

**Critical: Byte Field Encoding**

CBOR's native byte string type (major type 2) MUST be used for all binary data. This provides 4-5× size reduction compared to JSON integer arrays. Implementations MUST NOT encode binary data as CBOR arrays of integers.

Fields that MUST be encoded as CBOR byte strings:
- `validator_id`, `validator_pk`, `client_pk`, `sender_pk`
- `signature`, `client_sig`, `execution_proof`
- `consumed_state_id`, `produced_state_id`, `state_id`, `state_hash`
- `txid`, `commitment_hash`, `founding_vbc_hash`
- `subject_pubkey_sphincs`, `subject_pubkey_ed25519`, `subject_pubkey_dilithium`
- `pgp_fingerprint`

Fields that MUST be encoded as CBOR arrays of byte strings:
- `issuer_set` (array of public keys)
- `signatures` (array of SPHINCS+ signatures in VBC)

**JSON Scope Restriction:**

JSON is permitted ONLY for internal IPC within a validator node:
- Gateway ↔ axiom-core.elf (stdin/stdout, length-prefixed JSON)
- Gateway ↔ Lambda (stdin/stdout, length-prefixed JSON)

JSON MUST NOT be used for any client↔Gateway communication.

**Rationale:**

CBOR provides significant advantages for AXIOM's wire format:
- SPHINCS+ signatures (7,856 bytes each) as JSON integer arrays expand to ~35KB. As CBOR byte strings: 7,860 bytes. A typical VBC-bearing payload shrinks from ~540KB JSON to ~120KB CBOR.
- CBOR decoding is 10× faster than JSON parsing for binary-heavy payloads.
- CBOR's byte string type eliminates the impedance mismatch between binary cryptographic data and text-based serialization.

#### 16.8.5.9 Multi-Path Observation Principle (NORMATIVE)

Receiving the same message via multiple carriers (e.g., the same transaction arriving via both ANTIE email and COUSIN relay) is **intentional evidence gathering**, not duplication to be suppressed.

**Rule:** Gateways MUST NOT deduplicate messages based on carrier path. The same logical message received via different carriers provides independent evidence of delivery and availability. This strengthens the protocol's partition resilience.

**Deduplication** is performed at the Lambda level based on transaction content (txid + wallet_seq), NOT at the carrier level.

**Rationale:** In a partitioned or degraded network, the same transaction may propagate through multiple paths. Each path provides independent evidence that the transaction exists and is being broadcast. Suppressing duplicates at the Gateway level would destroy this evidence.

### 16.8.6 Λ (Lambda) -- Consensus Logic Engine

Lambda is the **open-source k=3 consensus logic engine** -- the soul of AXIOM.

| Property | Description |
|----------|-------------|
| **License** | GPL v3 (open for all) |
| **Logic** | k=3 witness requirement |
| **Function** | Identity verification, double-spend prevention, state management |
| **Development** | Anyone can develop and improve based on whitepaper/yellowpaper |

**Lambda exists only on Validators, not on Clients.**

**Lambda is separated from Core to allow:**
- Open development of consensus logic
- Binary protection of critical enforcement mechanisms
- Independent evolution of transport vs. validation

#### 16.8.6.1 Lambda's Responsibilities (What Lambda DOES)

| Responsibility | Description |
|----------------|-------------|
| **Receive pre-validated transactions** | From Gateway (already passed CL2) |
| **S-ABR validation** | Check declared balance matches stored state |
| **k=3 consensus coordination** | Collect overlapped signatures |
| **Call Core (CL3)** | Produce witness proof |
| **State management** | Store wallet balances, wallet_seq |
| **Return results** | Send witness signature/receipt to Gateway |

#### 16.8.6.2 Lambda's Boundaries (What Lambda does NOT do)

| NOT Lambda's Job | Who Does It? |
|------------------|--------------|
| Listen on network | Gateway |
| Decrypt payloads | Gateway + Core |
| **Validate transactions (CL2)** | **Gateway + Core** |
| Encrypt responses | Gateway + Core |
| Initiate connections | Gateway |

**CRITICAL:** Gateway pre-filters with CL2 (`current_state = None`) BEFORE passing to Lambda. Lambda then calls CL2 again with real stored state (authoritative validation) and CL3 for witness production.

**Implementation Guide:**

If implementing Lambda: call Core CL2 with real stored state (authoritative), call Core CL3 for witness production, call Core CL5 for cheque redemption. Lambda owns the stored wallet state and is the only component that provides `current_state` to Core.

If implementing Gateway: call Core CL2 with `current_state = None` as a pre-filter before passing to Lambda. Do not pass structurally invalid transactions to Lambda. Do not synthesize wallet state.

#### 16.8.6.3 Key Principles

- Same `axiom-core.elf` runs on both Client and Validator
- All Core operations go through Vault (isolated memory)
- **Client has Client Transporter; Validator has Gateway**
- Gateway (ANTIE/UNCLE/COUSIN) is part of Validator, not Client
- Lambda exists only on Validators
- **Invalid payloads rejected at Gateway+Core (CL2), never reaching Lambda**

### 16.8.7 Gateway-Lambda API Protocol

This section defines the protocol for communication between Gateway and Lambda components within a validator.

#### 16.8.7.1 Transport Layer

Lambda listens for Gateway connections on either:

| Transport | Address | Use Case |
|-----------|---------|----------|
| **TCP** | `127.0.0.1:9000` | Standard deployment |
| **Unix Socket** | `/var/run/lambda.sock` | Enhanced security |

**Frame Format:** Same as Gateway-Core IPC (Section 16.8.5.1):

```
+----------------+------------------+
| Length (4B BE) | CBOR Payload     |
+----------------+------------------+
```

- 4-byte big-endian length prefix
- CBOR-encoded request/response body (RFC 8949)
- Same framing as axiom-core.elf IPC for consistency

**Wire format note (NORMATIVE):** The request/response examples below
in §16.8.7.2 are shown as JSON for human readability; the on-the-wire
encoding is CBOR with byte-for-byte identical field names and types
(per §16.8.5.3 "no JSON anywhere in the protocol"). Reference Rust
encoders/decoders live in `axiom-core-logic::types` (the `GatewayRequest`
/ `GatewayResponse` enums and their `RequestEnvelope` payload structs).

#### 16.8.7.2 Request Types

**1. Witness Request**

Gateway forwards transaction for Lambda to coordinate witnessing:

```json
{
  "type": "witness",
  "request_id": "req-12345",
  "transaction": {
    "client_pk": [/* 32 bytes Ed25519 */],
    "consumed_state_id": [/* 32 bytes */],
    "to_address": "receiver@axiom/a3f-7b2-32",
    "amount": 100000,
    "wallet_seq": 2,
    "nonce": 1707700000000,
    "epoch": 1,
    "reference": "payment",
    "signature": [/* 64 bytes Ed25519 */],
    "auth_zkp": null
  },
  "overlapped_signatures": [/* WitnessSig array from prev_receipts */],
  "prev_receipts": [/* Receipt array proving prior state */],
  "declared_balance": 1000000000000,
  "requester_address": "alice@example.com",
  "offered_fee": 800000000,
  "validator_hints": [
    {
      "validator_id": "hex-string",
      "name": "axiom-fp-alpha",
      "carriers": ["email:alpha@axiom"],
      "last_seen": 1707700000
    }
  ],
  "produced_state_id": [/* 32 bytes - computed by Core CL2 */],
  "commitment_hash": [/* 32 bytes - computed by Core CL2 */],
  "sender_fact_chain": null
}
```

**Note:** `validator_hints`, `prev_receipts`, `produced_state_id`, `commitment_hash`, and `sender_fact_chain` use `#[serde(default)]` and may be omitted. `produced_state_id` and `commitment_hash` are computed by Core at the Gateway layer (CL2) and passed to Lambda. Lambda MUST NOT compute these itself.

**FACT chain Ownership (YPX-001 §1.6):** The `sender_fact_chain` field carries the client's money provenance chain. The FACT chain is **carried by the client**, not stored by validators. Validators verify the chain (Core CL3), sign FACT commitments, build a new link at k=3, and return the updated chain in `WitnessResponse.sender_fact_chain`. The client stores the updated chain locally and includes it in all future witness requests. Validators do NOT store FACT chains — `StoredWalletState.fact_chain` is deprecated.

**2. State Query**

Query wallet state from Lambda's records:

```json
{
  "type": "query_state",
  "request_id": "req-12346",
  "wallet_pk": "ed25519:..."
}
```

**3. Health Check**

Verify Lambda is operational:

```json
{
  "type": "health",
  "request_id": "req-12347"
}
```

**4. Shutdown**

Graceful shutdown request:

```json
{
  "type": "shutdown",
  "request_id": "req-12348"
}
```

**5. Redeem Request**

Receiver presents ChequeBundle for redemption. Gateway forwards to Lambda after basic validation:

```json
{
  "type": "redeem",
  "request_id": "req-12349",
  "cheque_bundle": {
    "cheques": [
      {
        "txid": [/* 32 bytes */],
        "validator_id": [/* 32 bytes */],
        "validator_pk": [/* 32 bytes */],
        "signature": [/* 64 bytes */],
        "execution_proof": [/* bytes */],
        "vbc_bundle": {/* VBCProofBundle or null */},
        "carrier_type": "maildir",
        "carrier_address": "validator-1@axiom",
        "sender_wallet_id": "alice@example.com/a1b2c3d4",
        "receiver_wallet_id": "bob@example.com/e5f6g7h8",
        "amount": 500,
        "reference": "payment",
        "epoch": 1,
        "created_at": 1738700000,
        "state_hash": [/* 32 bytes */],
        "produced_state_id": [/* 32 bytes */]
      }
      /* ... k total cheques (one per sender's validator) */
    ]
  },
  "receiver_pk": [/* 32 bytes - receiver's Ed25519 public key */],
  "receiver_sig": [/* 64 bytes - see Section 17.9.4.1 */],
  "current_state": {
    "public_key": [/* 32 bytes */],
    "balance": 10000,
    "wallet_seq": 5,
    "state_id": [/* 32 bytes */]
  }
}
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `cheque_bundle` | YES | Bundle of k ValidatorCheques from sender's validators |
| `receiver_pk` | YES | Receiver's Ed25519 public key (32 bytes) |
| `receiver_sig` | YES | Receiver's authorization signature (see Section 17.9.4.1) |
| `current_state` | NO | Receiver's wallet state for consistent state\_id (§17.10.12) |

#### 16.8.7.3 Response Types

**Witness Result:**

```json
{
  "type": "witness_result",
  "request_id": "req-12345",
  "success": true,
  "witness_signature": {
    "validator_id": [/* 32 bytes - BLAKE3(sphincs_pk) */],
    "validator_pk": [/* 32 bytes - Ed25519 public key */],
    "signature": [/* 64 bytes - Ed25519 over commitment_hash */],
    "commitment_hash": [/* 32 bytes */],
    "carrier_address": "alpha@axiom",
    "hints": [/* ValidatorHint array, 0-3 entries */],
    "vbc_bundle": {
      "target_vbc": {
        "version": 1,
        "subject_validator_id": [/* 32 bytes */],
        "subject_pubkey_sphincs": [/* SPHINCS+ pk */],
        "subject_pubkey_ed25519": [/* 32 bytes */],
        "issued_at": 1707700000,
        "expires_at": 1739236000,
        "chain_depth": 1,
        "issuer_set": [/* 3 x 32-byte validator_ids */],
        "signatures": [/* 3 SPHINCS+ signatures */],
        "founding_vbc_hash": [/* 32 bytes */]
      },
      "chain": [/* Supporting VBCs back to genesis */]
    },
    "validator_hints": [
      {
        "validator_id": "hex-string",
        "name": "axiom-fp-beta",
        "carriers": ["email:beta@axiom"],
        "last_seen": 1707700000
      }
    ]
  },
  "cheque_for_receiver": {
    "txid": [/* 32 bytes */],
    "validator_id": [/* 32 bytes */],
    "validator_pk": [/* 32 bytes */],
    "signature": [/* 64 bytes */],
    "execution_proof": [/* bytes */],
    "carrier_type": "maildir",
    "carrier_address": "validator-1@axiom",
    "sender_wallet_id": "...",
    "receiver_wallet_id": "...",
    "amount": 500,
    "reference": "...",
    "epoch": 1,
    "created_at": 1738700000,
    "state_hash": [/* 32 bytes */],
    "produced_state_id": [/* 32 bytes */]
  },
  "produced_state_id": [/* 32 bytes */],
  "receipt": null,
  "overlapped_signatures": [ /* collected signatures */ ]
}
```

**CRITICAL:** The `vbc_bundle` field in `witness_signature` carries the full VBC chain (SPHINCS+ signatures back to genesis root keys). Core verifies this chain at CL2 (prev_receipt witnesses), CL3 (defense in depth), and CL4 (client verification). The field uses `#[serde(default)]` for backwards compatibility; absent/null deserializes as None (allowed in dev/test mode).

**AUDIT-FIX v2.11.14:** VBC bundles in `prev_receipts` now receive **full SPHINCS+ verification** (`verify_vbc_bundle_no_time`), not structure-only checks. Previous structure-only checks skipped cryptographic signature verification, which is insufficient for client-supplied data. The `no_time` variant skips timestamp expiry (receipts may be old) but verifies all signatures back to ROOT_AUTHORITY_PKS. This applies to both `validation.rs` (receipt verification) and `modes.rs` (overlap validation).

**CRITICAL:** The `cheque_for_receiver` field contains a complete `ValidatorCheque` (see Section 17.9.8). The client MUST collect k of these from k different validators and bundle them into a `ChequeBundle` for redemption. Lambda generates this cheque even before k=3 is reached, so every successful witness response includes one.

**Note:** `receipt` is null when k < 3 (each validator processes independently). The PMC assembles the receipt client-side from 3 successful responses.

**Witness Rejection:**

```json
{
  "type": "witness_result",
  "request_id": "req-12345",
  "success": false,
  "rejection": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Declared balance exceeds recorded balance"
  }
}
```

**State Query Result:**

```json
{
  "type": "state_result",
  "request_id": "req-12346",
  "found": true,
  "wallet_state": {
    "balance_atom": 1000000000000,
    "nonce": "rand128:...",
    "last_tx_id": "b3:..."
  }
}
```

**Health Result:**

```json
{
  "type": "health_result",
  "request_id": "req-12347",
  "status": "healthy",
  "core_connected": true,
  "pending_transactions": 3
}
```

**Redeem Result:**

```json
{
  "type": "redeem_result",
  "request_id": "req-12349",
  "success": true,
  "witness_signature": {
    "validator_id": [/* 32 bytes */],
    "validator_pk": [/* 32 bytes */],
    "signature": [/* 64 bytes */],
    "commitment_hash": [/* 32 bytes */],
    "carrier_address": "validator@axiom",
    "vbc_bundle": {/* VBCProofBundle or null */},
    "validator_hints": [/* ValidatorHint array */]
  },
  "new_balance": 1500000,
  "new_state_id": [/* 32 bytes */]
}
```

**Redeem Rejection:**

```json
{
  "type": "redeem_result",
  "request_id": "req-12349",
  "success": false,
  "error": "Invalid receiver signature"
}
```

Possible rejection reasons:

| Error | Description |
|-------|-------------|
| `Invalid receiver signature` | receiver_sig does not match BLAKE3("AXIOM_REDEEM" \|\| txid \|\| receiver_pk) |
| `Insufficient cheques` | Bundle has fewer than k=3 ValidatorCheques |
| `Inconsistent cheque bundle` | Cheques reference different txids or amounts |
| `Invalid cheque signature` | One or more ValidatorCheque signatures invalid |
| `Already redeemed` | This ChequeBundle was already redeemed |

#### 16.8.7.4 Lambda Processing Flow

**CRITICAL: Gateway calls Core (CL2) BEFORE Lambda**

The security model requires that Gateway validates all incoming transactions through Core BEFORE passing to Lambda. This ensures Lambda never sees invalid or malicious payloads.

```
Gateway receives encrypted witness request from network
    |
    v
Gateway -> axiom-core.elf: Decrypt payload
    |
    v
Gateway -> axiom-core.elf: Validate transaction (CL2)
    |                 - Signature verification
    |                 - Balance check
    |                 - wallet_seq check
    |                 - Receiver address validation
    v
axiom-core.elf returns: ACCEPT or REJECT
    |
    v
If REJECT:
    Gateway -> Client: rejection (does NOT reach Lambda)
    |
If ACCEPT:
    |
    v
Gateway -> Lambda: witness request (CBOR over TCP/Unix)
    |               [Lambda receives PRE-VALIDATED transaction]
    v
Lambda checks:
    1. Is requester's wallet known?
    2. Am I in prev_receipts? (Overlapped check)
    3. Is declared balance honest? (S-ABR)
    |
    v
Lambda -> axiom-core.elf: Sign witness (CL3)
    |                - Produce witness proof
    |                - Validator signature
    v
axiom-core.elf returns: witness signature + proof
    |
    v
Lambda stores: Updated wallet state
Lambda -> Gateway: witness_result (success)
    |
    v
Gateway -> axiom-core.elf: Encrypt response
    |
    v
Gateway -> Client: encrypted witness_result
```

**Security Invariant:** Lambda NEVER receives transactions that have not been validated by Core (CL2). This is the "Core as gatekeeper" principle.

**Why Gateway calls Core, not Lambda:**
- Gateway is the entry point from the network
- Core protects Lambda from malformed/malicious payloads
- Lambda focuses on business logic (k=3 consensus, S-ABR)
- Clean separation: Core = validation, Lambda = coordination

#### 16.8.7.5 Configuration

Lambda startup accepts configuration via config file (TOML). Command-line overrides are supported.

**Config File (TOML):**

```toml
[validator]
core_bin_path = "/opt/axiom/validators/alpha/axiom-core.elf"
carrier_type = "email"
carrier_address = "alpha@axiom"

[storage]
data_dir = "/opt/axiom/validators/alpha/data"

[logging]
level = "info"
```

**core_bin_path (NORMATIVE — No Fallback):**

The `core_bin_path` field specifies the absolute or relative path to the axiom-core.elf binary. This field is MANDATORY in production deployments. If the binary does not exist at the configured path, Lambda MUST refuse to start with a `ConfigError`.

There is NO fallback path resolution. Lambda does NOT search `$PATH`, does NOT look relative to the executable, and does NOT try multiple directories. The path must be explicit and the binary must exist. This is a deliberate fail-stop design: silent fallback to an incorrect binary is worse than failing to start.

**Serde Default:** If `core_bin_path` is absent from the config file, serde deserializes a default value of `"./axiom-core.elf"` which resolves to `$CWD/axiom-core.elf`. Since Lambda's working directory is the validator directory (set by the deployment scripts), this default resolves correctly for standard deployments.

**Deployment Scripts:**

All deployment tooling (validator-ctl.sh, dev.sh, axiom-dash.py) copies `axiom-core.elf` to exactly one location: `$VALIDATOR_DIR/axiom-core.elf`. The `install_genesis.sh` script generates config files with absolute paths.

#### 16.8.7.6 Error Handling

Lambda MUST handle connection errors gracefully:

| Error | Lambda Behavior |
|-------|-----------------|
| Core disconnected | Fail-stop: return error, Gateway restarts axiom-core.elf |
| Invalid CBOR | Return error response, continue |
| Unknown request type | Return error response, continue |
| Internal error | Log, return error response, continue |
| axiom-core.elf missing | Refuse to start with ConfigError |

**Lambda MUST NOT crash on malformed input.** Fail-stop applies only to invariant violations, not protocol errors.

**Core Output Requirements (NORMATIVE):** When Core returns `Accept`, Lambda MUST verify that Core provided all required output fields: `produced_state_id`, `new_state_hash`, `new_wallet_seq`, and `commitment_hash`. If ANY of these are missing (None), Lambda MUST reject the transaction — not substitute zero values or defaults. "Can crash, must not lie" — a zero `produced_state_id` in a receipt is a lie about the wallet's state.

**Constant-Time Comparisons (NORMATIVE):** All comparisons of cryptographic values (`state_id`, `commitment_hash`, `validator_pk`, `validator_id`) MUST use constant-time equality checks to prevent timing side-channel attacks. This is defense-in-depth for socket-based gateways (UNCLE, COUSIN) where network latency does not mask timing.

### 16.9 Integration with Validator Network

**Data flow:**

1. **User generates transaction** -> Gateway encodes to Vault format
2. **Core signs transaction** -> Based on user's algorithm preference
3. **Gateway transmits to Validator Pool** -> Via current network protocol
4. **Validators verify signature** -> Using algorithm specified in transaction
5. **Consensus forms** -> If sufficient validators accept

**Validator algorithm compatibility:**

A validator running Op 2 (Dilithium) **can still verify** Op 1 (Ed25519) transactions.
All validators support all three algorithms -- they simply **prefer** one for their own operations.

This ensures:
- No network fragmentation
- Gradual migration capability
- No forced upgrades

### 16.10 Relationship with Ark-Mode

Ark-Mode (Section 11) uses the **same Core architecture**:

- **Standard wallet**: User selects Op 1/2/3 for connected transactions
- **Ark wallet**: User selects Op 1/2/3 for offline transactions

Both wallets can independently choose any algorithm.

**Common pattern:**
- Standard wallet = Op 1 (Ed25519, fastest for normal use)
- Ark wallet = Op 3 (SPHINCS+, paranoid mode for partition survival)

This allows users to optimize for:
- **Speed** when connected
- **Resilience** when offline

### 16.11 Why This Architecture Survives

**Traditional systems fail when:**
- Cryptography is broken -> entire system collapses
- Protocols evolve -> clients need coordinated upgrades
- Network splits -> no path forward

**Lambda survives because:**
- Multiple algorithms are **pre-embedded** -> no emergency upgrades
- Protocol and crypto are **decoupled** -> Gateway updates don't touch Core
- Market selection is **decentralized** -> no coordination required

**The core insight:**

> We don't need governance to migrate cryptography.  
> We need the absence of barriers to migration.

By pre-embedding all options and letting operators choose, we eliminate the coordination problem entirely.

### 16.12 UI Representation Guidelines (Non-Normative)

**Note:** This section is informative, not normative. Client implementations may choose any display strategy that serves their users.

**The distinction problem:**

From a protocol perspective, L$ generated via the Standard and Ark wallets are fungible -- they are the same currency. However, users may benefit from understanding the *provenance* of their holdings, particularly:
- L$ generated during offline/partition periods (higher dilution risk)
- L$ generated in connected mode (standard settlement)

**Reference implementation pattern:**

The recommended visual indicator for Ark-sourced L$ is the ⟠  symbol (Unicode U+27E0, "LOZENGE DIVIDED BY HORIZONTAL RULE"):

| Mode | Display | Example |
|------|---------|---------|
| **Connected-mode** | `500 L$` | Standard display, no prefix |
| **Ark-mode** | ⟠ 500 L$ | Prefixed with ⟠ symbol |

**Symbol Reference:**

| Property | Value |
|----------|-------|
| **Character** | ⟠  |
| **Unicode Code Point** | U+27E0 |
| **Unicode Name** | LOZENGE DIVIDED BY HORIZONTAL RULE |
| **UTF-8 Encoding** | `0xE2 0x9F 0xA0` (3 bytes) |
| **HTML Entity** | `&#10208;` or `&#x27E0;` |

**Why this symbol:**
- Visually resembles a satellite -- representing the reconnection that brings partitioned networks back together
- Evokes the idea of "signal from above" that restores connectivity during blackouts
- Visually distinct from currency symbols ($, €, £, ¥)
- Not commonly used, avoiding collision with other meanings
- Resembles a "divided" or "partitioned" shape -- fitting for partition-mode transactions
- Available in most modern Unicode fonts

**Key implementation notes:**

1. **Users never input the indicator** -- transfers specify "500 L$" regardless of source
2. **Indicator reflects transaction signing key** -- not wallet mode or network state
3. **Display strategy is client-specific** -- some may show separate balances, others may aggregate
4. **Post-reconciliation behavior is undefined** -- clients may preserve or remove indicators after partition merge

**Rationale for visual distinction:**

Allowing users to see provenance serves several purposes:
- Transparency about dilution risk exposure
- Informed decision-making during transfers
- Historical accountability for partition-period activity

However, this is a UI concern, not a protocol requirement. The protocol treats all L$ identically regardless of signing key origin.

**Implementation note:**

The ⟠  indicator has **no protocol-level meaning**. From the protocol's perspective, 500 L\$ and ⟠ 500 L\$ are identical -- both represent the same number of AXC atoms. The symbol exists purely to help users track which wallet (Standard vs Ark) holds their funds.

Clients may choose to:
- Show unified balance with no distinction
- Use separate balance lines for different key sources
- Provide provenance information only on-demand (detail view)
- Use color coding, icons, or other visual language
- Display risk indicators based on partition exposure

The protocol remains agnostic to these choices.

### 16.13 Transaction Storage Encryption (Non-Normative)

**Design goal:**

Protect validator operators from coercion by ensuring they cannot access transaction records, even if compelled by legal authority.

**This is not a protocol requirement.**

Different jurisdictions have different legal frameworks. Some may require validators to retain accessible records; others may protect operators who genuinely cannot decrypt their own storage.

Validator implementations SHOULD provide encryption options appropriate to their target deployment environment.

**Reference implementation options:**

1. **Software-generated encryption key**
   - `storage_key` generated on first initialization
   - Stored in protected filesystem location (e.g., `/var/lib/validator/.sealed_key`)
   - File permissions restrict access to validator process only

2. **Hardware-backed key storage (enhanced)**
   - TPM sealed storage
   - HSM integration
   - Secure Enclave (on supported platforms)

3. **Network-based key sharding (maximum protection)**
   - `storage_key` split into M-of-N shards
   - Distributed across trusted validator network
   - Reconstruction requires threshold consensus

**Encryption scope:**

Which data to encrypt is left to implementation choice:
- Full transaction payload (maximum protection)
- Selective encryption (balance between protection and regulatory compliance)
- Plaintext with access control (minimal protection)

**Note:** Some jurisdictions may require validators to disclose specific fields (e.g., counterparty identities for AML compliance). Implementations MAY encrypt selectively to accommodate legal requirements while protecting other transaction details. The decision of what to encrypt is left to validator operators and their chosen software implementation.

**Operator isolation:**

Regardless of encryption approach, validator software SHOULD NOT provide operator-accessible interfaces to:
- Query transaction history
- Determine witness/decoy role
- Access vote decisions

**Machine-level vs Human-level knowledge:**

When validator software receives notifications (e.g., PWV membership, vote requests):
- **Machine knows**: Whether it's a real witness or decoy, transaction details, vote content
- **Operator sees**: Generic status messages ("processing vote request"), no role indication

**The core principle:**

> Operators cannot disclose what they genuinely cannot access.

Implementation choices determine the strength of this guarantee.


### 16.14 Wallet Address Format (Normative)

#### 16.14.1 Design Goals and Non-Goals

**READ THIS FIRST - Understanding the Purpose**

The wallet address format is designed for TWO specific purposes:

1. **Anti-typo protection** - Prevent users from sending money to mistyped addresses
2. **Unique wallet identification** - Allow one email to have multiple wallets

**This is NOT designed for:**
- Anti-hacking protection
- Cryptographic security against attackers
- Preventing malicious wallet creation

**Why this distinction matters:**

Engineers may ask: "If the master_public_key is embedded in axiom-core.elf, anyone can extract it and generate wallet_ids!"

**Answer: Yes, and we don't care.**

The wallet_id is a CHECKSUM, like:
- Credit card check digit (Luhn algorithm)
- IBAN check digits
- ISBN check digit

These checksums don't prevent fraud. They prevent typos. That's their only job.

The REAL security comes from:
- Private key signatures (only owner can sign transactions)
- k=3 validator consensus (prevents fake transactions)

The wallet_id just helps users not lose money to typos.

#### 16.14.2 The Problem We're Solving

**Problem 1: Typos cause money loss**

```
User wants to send to: bob@example.com
User types:           bbo@example.com  (typo)

Without checksum: Transaction proceeds, money lost forever
With checksum:    axiom-core.elf rejects "invalid wallet_id"
```

**Problem 2: One email needs multiple wallets**

```
Bob wants 3 wallets for different purposes:
  - Personal spending
  - Business income  
  - Savings

All under bob@example.com
Each needs unique identifier
```

**Problem 3: No central server**

```
Traditional solution: Central database maps wallet_id to email
AXIOM: No central server, axiom-core.elf must verify locally
```

#### 16.14.3 Solution: Computable Checksum with Salt

**Address Structure:**

```
bob@example.com/a3f-7b2-32
               ^^^ ^^^ ^^
               |   |   |
               +---+---+-- checksum (6 hex) + salt (2 hex)
               
Total: 8 hex characters, displayed as xxx-xxx-xx
```

| Component | Length | Purpose |
|-----------|--------|---------|
| email | varies | User identity, delivery endpoint |
| `/` | 1 char | Separator |
| checksum | 6 hex | Typo + tier protection |
| pk\_bind | 2 hex | Binds address to wallet's Ed25519 public key |
| salt | 2 hex | Uniqueness (256 wallets per email) |

**The Formula:**

```
checksum = first_6_hex(BLAKE3(email || master_pk || salt || k_byte || proof_type_byte))
pk_bind  = first_2_hex(BLAKE3(wallet_pk || k_byte || proof_type_byte))
wallet_id = checksum + pk_bind + salt
```

The `k_byte` and `proof_type_byte` are embedded in the checksum. This means each of the 7 security tiers (§6.3.1) produces a **different address** for the same wallet. The receiver chooses which address to give the sender — selecting the security level for that transaction. Core extracts `(k, proof_type)` from the wallet\_id and enforces them.

**Example (Standard tier, k=3, DMAP):**
```
email       = "bob@example.com"
master_pk   = [embedded in axiom-core.elf at release]
wallet_pk   = [Ed25519 public key for this wallet]
salt        = "32" (randomly generated at wallet creation)
k_byte      = 0x03 (k=3, Standard tier)
proof_type  = 0x01 (DMAP)

checksum = first_6_hex(BLAKE3("bob@example.com" || master_pk || "32" || 0x03 || 0x01))
         = "a3f7b2"

pk_bind  = first_2_hex(BLAKE3(wallet_pk || 0x03 || 0x01))
         = "e1"

wallet_id = "a3f7b2" + "e1" + "32" = "a3f7b2e132"
display   = "a3f-7b2-e1-32"
```

The same wallet using **Secure+ tier (k=4, ZKP)** would produce a completely different address:
```
k_byte      = 0x04 (k=4, Secure+ tier)
proof_type  = 0x00 (ZKP)

checksum = first_6_hex(BLAKE3("bob@example.com" || master_pk || "32" || 0x04 || 0x00))
         = "71d9c4"    (different — k_byte/proof_type changed)

pk_bind  = first_2_hex(BLAKE3(wallet_pk || 0x04 || 0x00))
         = "8a"

wallet_id = "71d9c4" + "8a" + "32" = "71d9c48a32"
display   = "71d-9c4-8a-32"
```

#### 16.14.4 Why This Design? (Decision Process)

**Attempt 1: Use user's public key**

```
Idea: wallet_id = hash(email + user_public_key)
Problem: User must carry keypair everywhere, or include in every transaction
Rejected: Too complex for users
```

**Attempt 2: Network-wide secret key**

```
Idea: Embed secret in axiom-core.elf, use for wallet_id generation
Problem: axiom-core.elf is open source, secret can be extracted from binary/memory
Rejected: Security through obscurity doesn't work
```

**Attempt 3: Just use email**

```
Idea: wallet_id = hash(email + master_public_key)
Problem: One email = one wallet only
Rejected: Users need multiple wallets per email
```

**Attempt 4: Add sequence number**

```
Idea: wallet_id = hash(email + master_key + sequence)
       bob@example.com/0, bob@example.com/1, bob@example.com/2
Problem: User must remember which sequence number is which wallet
Rejected: Confusing for users
```

**Final Solution: Salt + tier-bound checksum + pk\_bind**

```
Idea: wallet_id = checksum(6 hex) + pk_bind(2 hex) + salt(2 hex)
      checksum = BLAKE3(email + master_pk + salt + k_byte + proof_type_byte)
      pk_bind  = BLAKE3(wallet_pk + k_byte + proof_type_byte)

Benefits:
  - User only remembers one string: "a3f-7b2-e1-32"
  - axiom-core.elf can verify locally (extract salt, recompute checksum)
  - Multiple wallets per email (different salt = different wallet)
  - Each security tier produces a different address (k_byte + proof_type in hash)
  - pk_bind ties address to wallet keypair (prevents address reuse across keys)
  - No central server needed
  - No keypair needed for verification

This is the chosen solution.
```

#### 16.14.5 Master Public Key

**At AXIOM release:**

1. AXIOM Origin generates: master_keypair (one time only)
2. Embeds in axiom-core.elf: master_public_key
3. Keeps secret: master_private_key (used for signing axiom-core.elf releases)

**The master_public_key is NOT secret:**

- It's embedded in open-source code
- Anyone can extract it from the binary
- This is intentional and acceptable

**Why it's acceptable:**

The master_public_key is used for CHECKSUM computation, not security.

```
Attacker extracts master_public_key
Attacker computes: hash("victim@email.com" + master_key + "32") = "a3f7b2"
Attacker knows: victim@email.com/a3f-7b2-32 is a valid address format

So what? Attacker still cannot:
  - Sign transactions (needs victim's private signing key)
  - Steal money (needs k=3 validator consensus)
  - Do anything harmful
```

The master_public_key just enables checksum verification. That's all.

#### 16.14.6 Wallet Creation Flow

```
1. User requests: "Create wallet for bob@example.com"

2. axiom-core.elf generates:
   - salt = random 2 hex chars (e.g., "32")
   - Signing keypair for transactions (separate from wallet_id)
   
3. axiom-core.elf computes:
   - checksum = first_6_hex(hash(email + master_public_key + salt))
   - wallet_id = checksum + salt
   
4. axiom-core.elf stores in Vault:
   - Signing private key (for transactions)
   - Signing public key
   - wallet_id
   
5. User receives:
   - Address: bob@example.com/a3f-7b2-32
   
6. User remembers:
   - Email (already knows)
   - 8 hex characters: a3f-7b2-32
```

As of v2.11.13, auth_hash is mandatory for all established wallets (wallet_seq > 0). Transactions from wallets without auth_hash are rejected with ValidationError::AuthHashRequired at CL1 and CL2. The enforcement threshold is OWNER_PROOF_REQUIRED_EPOCH in core/logic/protocol.toml (currently 0 — enforced from genesis). See docs/OWNER_PROOF_POLICY.md.

#### 16.14.7 Verification Flow

```
User sends to: alice@example.com/9e2-d4f-7a

axiom-core.elf verification:
  1. Parse: email = "alice@example.com"
           wallet_id = "9e2d4f7a"
           checksum = "9e2d4f" (first 6)
           salt = "7a" (last 2)
           
  2. Compute: expected = first_6_hex(hash(email + master_public_key + salt))
  
  3. Compare: expected == checksum?
     - YES: Valid address, proceed
     - NO: REJECT "Invalid wallet address - check for typos"
```

**No network lookup needed. Pure local computation.**

#### 16.14.8 Display and Internal Format

**Display format (recommended):**
```
bob@example.com/a3f-7b2-32
                ^^^ ^^^ ^^
                grouped for readability
```

**Display format (acceptable):**
```
bob@example.com/a3f7b232
```

**Internal storage (always):**
```
bob@example.com/a3f7b232
                ^^^^^^^^
                8 chars, no dashes, lowercase
```

**Normalization rules:**
- Remove dashes
- Convert to lowercase
- Validate: exactly 8 hex characters after email/

#### 16.14.9 Multiple Wallets Per Email

```
bob@example.com/a3f-7b2-32   <- salt "32", wallet 1
bob@example.com/9e2-d4f-7a   <- salt "7a", wallet 2  
bob@example.com/c4b-18a-f1   <- salt "f1", wallet 3
```

**Maximum wallets per email:** 256 (2 hex chars = 256 combinations)

**Collision probability:** With random salt, ~0.4% chance of collision at 10 wallets per email. Acceptable for typical usage.

#### 16.14.10 What This Protects Against

| Scenario | Protected? | How |
|----------|-----------|-----|
| User types wrong character | YES | Checksum fails |
| User swaps characters | YES | Checksum fails |
| User forgets character | YES | Wrong length rejected |
| User sends to non-existent wallet | PARTIAL | Valid format but may not exist |
| Attacker creates fake wallet | NO | Not the purpose (use k=3 for security) |

#### 16.14.11 Transaction Structure (Normative)

**CRITICAL: Field Naming Convention**

The Transaction structure uses specific field names for wallet addressing:

```rust
pub struct Transaction {
    /// State ID being consumed by this transaction
    pub consumed_state_id: [u8; 32],
    
    /// Client's public key (Ed25519 or Dilithium)
    pub client_pk: Vec<u8>,
    
    /// Wallet sequence number (must be prev + 1)
    pub wallet_seq: u64,
    
    /// Receiver's wallet_id (REQUIRED)
    /// Format: "email/hex8" e.g. "bob@example.com/a3f7b232"
    /// The hex8 = checksum(6) + salt(2) for anti-typo protection
    pub receiver_wallet_id: String,
    
    /// Receiver's email override (OPTIONAL)
    /// If Some: send cheque to this email instead of wallet_id's email
    /// If None: extract email from receiver_wallet_id
    pub receiver_address: Option<String>,
    
    /// Amount in atoms (smallest unit)
    pub amount: u64,
    
    /// Payment reference (max 256 chars)
    pub reference: String,
    
    /// Nonce for replay protection
    pub nonce: u64,
    
    /// Epoch derived from consumed_state_id
    pub epoch: u64,
    
    /// Client's signature over the transaction
    pub client_sig: Vec<u8>,
}
```

**Field Semantics:**

| Field | Required | Purpose |
|-------|----------|---------|
| `receiver_wallet_id` | YES | The actual wallet receiving funds. Used in signature, validation, and balance updates |
| `receiver_address` | NO | Override for cheque delivery email. If absent, email extracted from `receiver_wallet_id` |

**Example 1: Normal payment**
```json
{
  "receiver_wallet_id": "bob@example.com/a3f7b232",
  "receiver_address": null
}
// Cheque sent to: bob@example.com (from wallet_id)
// Funds go to: bob@example.com/a3f7b232
```

**Example 2: Payment with email override**
```json
{
  "receiver_wallet_id": "bob@example.com/a3f7b232",
  "receiver_address": "bob-notifications@example.com"
}
// Cheque sent to: bob-notifications@example.com (override)
// Funds go to: bob@example.com/a3f7b232 (wallet_id)
```

**Signature covers `receiver_wallet_id`, NOT `receiver_address`:**
```
signing_message = consumed_state_id 
                || wallet_seq (u64 LE)
                || receiver_wallet_id (UTF-8 bytes)
                || amount (u64 LE)
                || reference (UTF-8 bytes)
                || nonce (u64 LE)
                || epoch (u64 LE)
```

#### 16.14.12 Genesis State ID Computation

For new wallets (genesis transactions), the state ID is computed as:

```
genesis_state_id = SHA3-256("AXIOM_GENESIS" || public_key || balance_le_bytes)
```

**Components:**
- `"AXIOM_GENESIS"`: Domain separation prefix (13 bytes, ASCII)
- `public_key`: Ed25519 or Dilithium public key (32 bytes for Ed25519)
- `balance_le_bytes`: Initial balance as 8-byte little-endian

**Purpose:** This is NOT secret. It's domain separation to prevent hash collisions between genesis state IDs and regular state IDs.

**Example (Python):**
```python
import hashlib

def compute_genesis_state_id(public_key: bytes, balance: int) -> bytes:
    data = b"AXIOM_GENESIS" + public_key + balance.to_bytes(8, 'little')
    return hashlib.sha3_256(data).digest()
```

**Example (Rust):**
```rust
fn compute_genesis_state_id(public_key: &[u8; 32], balance: u64) -> [u8; 32] {
    let mut data = Vec::new();
    data.extend_from_slice(b"AXIOM_GENESIS");
    data.extend_from_slice(public_key);
    data.extend_from_slice(&balance.to_le_bytes());
    sha3_256_hash(&data)
}
```

**Gateway Genesis Validation:**

When processing a genesis transaction (wallet_seq = 1, no previous receipts), Gateway MUST:
1. Compute expected genesis_state_id from (client_pk, declared_balance)
2. Verify tx.consumed_state_id == expected genesis_state_id
3. If mismatch: REJECT before CL2 validation

This prevents clients from claiming arbitrary balances.

#### 16.14.13 What This Does NOT Protect Against

**This is NOT security. This is usability.**

| Scenario | Protected? | Why |
|----------|-----------|-----|
| Attacker generates valid wallet_ids | NO | master_public_key is extractable |
| User sends to wrong person (correct address) | NO | User error, not typo |
| Phishing (user tricked into wrong address) | NO | Social engineering attack |

**Security comes from:**
- Transaction signatures (private key)
- k=3 validator consensus
- NOT from wallet_id format

#### 16.14.14 Summary

```
Wallet Address: email/checksum-salt
                      ^^^^^^^^ ^^^^
                      6 hex    2 hex
                      
Purpose: Anti-typo, NOT anti-hacking
Verification: Local computation by any axiom-core.elf
Multiple wallets: Yes, via different salt
User remembers: Email + 8 hex characters
```


## 17. Transaction Model & Witness Protocol

### 17.1 Core Transaction Properties

Lambda uses a state-transition model where each transaction:
- Consumes exactly ONE wallet state
- Produces exactly ONE successor state
- Requires k witnesses (minimum k=3)

**No multi-input transactions.**
**No UTXO model.**
**No change outputs.**
**No cross-class transactions** — a wallet's class (public or developer) is fixed by the email part of its wallet_id (exact `@axiom.internal` match = developer). Sender and recipient must share the same class; `validate_transaction` rejects cross-class TXs with `E_DOMAIN_MISMATCH` (rule R1). See `AXIOM_DESIGN_FactClassIsolation.md` for the full specification.

This simplicity is intentional -- it eliminates transaction graph analysis and reduces witness coordination complexity.

#### 17.1.1 Witness Signature Binding (CRITICAL INVARIANT)

> **HARD RULE:** A witness signature MUST be computed over a canonical serialization of the full transaction payload and its derived state identifiers. Any signature over a client-supplied identifier is INVALID.

**Canonical Serialization:** See Section 17.2.2 and `LAMBDA_CANONICAL_JSON_BYTES.md` for the complete specification of Canonical Bytes (CB).

**Why this matters:**

If an implementation signs over `tx_id` supplied by the client (even if "it is expected to equal hash(payload)"), the following attack becomes possible:
- Client sends different payloads to different validators
- Client supplies same `tx_id` to all
- Validators sign the `tx_id` without verifying payload consistency
- Client collects signatures for inconsistent states

**Correct implementation:**

```
validator_sig = Sign(
    validator_sk,
    BLAKE3(CB_core)  // CB_core from LAMBDA_CANONICAL_JSON_BYTES.md
)
```

**Incorrect implementation (VULNERABLE):**

```
validator_sig = Sign(
    validator_sk,
    client_supplied_tx_id  // NEVER DO THIS
)
```

This is not a design change -- it is **implementation disaster prevention**.

#### 17.1.2 The Quorum Gate — nothing advances without k fresh witnesses (CRITICAL INVARIANT)

> **HARD RULE:** A wallet's state advances **only** when the advancing transaction collects **k
> fresh witness signatures** (k = the wallet's tier; the **absolute floor is 3**). Below 3,
> **nothing moves** — a sub-quorum (`< 3`) witness set is a **no-op**, not a partial success; the
> wallet stays exactly where it was.

This is the enforcement arm of the #1 state-authority invariant (*wallet state changes only via
validator-witnessed Core authority*). It is enforced **inside Core**, not left to Lambda's commit
path. `k` is about **the current move collecting new signatures to advance** — it is not the
previous receipt's signature count, and there is **no genesis exemption**: genesis, like any move,
either collects its ≥3 fresh witnesses or it does not move.

**Where it is enforceable.** CL2/CL3 run per-validator, mid-round — at that instant a move holds
only that one validator's signature; the k signatures do not exist yet (the client aggregates them
after the round). So Core cannot literally "count k" mid-round. It counts them at the point it is
handed an **assembled, k-signed receipt** — when that receipt is consumed as the **anchor** of the
next move (its `state_hash` is what `verify_state_anchored` recomputes) or as a cheque receipt at
CL5:

> **You cannot advance from a state that was not itself quorum-witnessed.** A transaction whose
> anchor (`prev_receipt` / consumed cheque receipt) carries **fewer than 3** valid witness
> signatures is rejected with `E_STATE_NOT_QUORUM_WITNESSED`. The check lives in
> `validate_transaction`, so **CL1, CL2, CL3, and CL5 all inherit it**.

A 2-of-3 "partial" receipt can therefore never be the anchor of the next move → a wallet can never
advance out of a sub-quorum state → **nothing moves below 3.** The Core floor is a fixed `>= 3`;
the higher-tier requirements (k = 4 / 5) layer on top via the existing `required_k` mechanism
(receiver-tier, re-derived from the wallet_id, never trusted from the wire).

**Consequences.** A sub-quorum send strands **nothing** — the sender keeps `B`; there is no
"failed-send" money to recover (see YPX-022 §0), and any residual validator divergence is a HEAL
matter, never a balance change. No partial-commit state is ever recorded from a sub-quorum round.

### 17.2 Transaction Payload Specification

**Standard transaction structure:**

```json
{
  "version": "tx.v1",
  "tx_id": "b3:8f7c1a...9e21",  // BLAKE3(payload_core)
  "timestamp": 1734432100,       // Unix time (ordering/UX only)
  
  "input": {
    "state_id": "st:b3:aa91...ff02",
    "owner_pk": "ed25519:pk_SENDER...",
    "prev_receipts": [
      {"validator_pk": "ed25519:pk_A...", "sig": "..."},
      {"validator_pk": "ed25519:pk_B...", "sig": "..."},
      {"validator_pk": "ed25519:pk_C...", "sig": "..."}
    ]
  },
  
  "debit": {
    "amount_atom": 1000000000000,    // AXC atoms (declared transfer amount)
    "receiver_pk": "ed25519:pk_RECEIVER...",
    "reference": "invoice:..."        // UX metadata
  },
  
  "witness_fees": [
    {
      "validator_pk": "ed25519:pk_A...",
      "fee_rate_bp": 8,                // 0.08% = 8 basis points
      "fee_amount": 800000000,         // 0.8 L$ worth of atoms
      "deed_allocation": {
        "protocol_team": 80000000,     // 10% to Protocol
        "implementation_team": 80000000, // 10% to Implementation
        "validator_net": 640000000     // 80% to validator
      }
    },
    {
      "validator_pk": "ed25519:pk_E...",
      "fee_rate_bp": 2,
      "fee_amount": 200000000,
      "deed_allocation": {
        "protocol_team": 20000000,
        "implementation_team": 20000000,
        "validator_net": 160000000
      }
    },
    {
      "validator_pk": "ed25519:pk_F...",
      "fee_rate_bp": 10,
      "fee_amount": 1000000000,
      "deed_allocation": {
        "protocol_team": 100000000,
        "implementation_team": 100000000,
        "validator_net": 800000000
      }
    }
  ],
  
  "total_fees": 2000000000,  // Sum of all validator fees (in atoms)
  
  "next_state_core": {
    "next_state_id": "st:b3:bb12...ee77",
    "parent_state_id": "st:b3:aa91...ff02",
    "owner_pk": "ed25519:pk_SENDER...",
    "balance_atom": 7350000000000,  // Sender's balance after deducting declared amount
    "nonce": "rand128:91f2...0b77"
  },
  
  "witness_set": [
    {"validator_pk": "ed25519:pk_A...", "resolution": {"email": "..."}},
    {"validator_pk": "ed25519:pk_E...", "resolution": {"email": "..."}},
    {"validator_pk": "ed25519:pk_F...", "resolution": {"email": "..."}}
  ],
  
  "receipts": [
    {"validator_pk": "ed25519:pk_A...", "sig": "sig_over_next_state"},
    {"validator_pk": "ed25519:pk_E...", "sig": "sig_over_next_state"},
    {"validator_pk": "ed25519:pk_F...", "sig": "sig_over_next_state"}
  ],
  
  "display": {
    "digit_version": 3,
    "currency_label": "L$",
    "amount_display": "1.00",          // Declared transfer amount
    "total_fees_display": "0.002",     // Total fees for UX
    "receiver_gets_display": "0.998"   // What receiver actually gets
  }
}
```

**Critical fields:**

- `prev_receipts`: Proves previous state was legitimately consumed
- `next_state_core`: Complete snapshot (not delta)
- `witness_set`: k validators who verified this transaction
- `witness_fees`: **NEW** - Fee structure with DEED allocation
- `receipts`: Cryptographic proof of witness validation

**Fee calculation (base = declared amount):**

All validator fees are calculated from the **declared transfer amount**:

```
Declared amount: 1000 L$ (1,000,000,000,000 atoms)

Validator A: 1000 × 0.0008 = 0.8 L$ (800,000,000 atoms)
Validator E: 1000 × 0.0002 = 0.2 L$ (200,000,000 atoms)
Validator F: 1000 × 0.0010 = 1.0 L$ (1,000,000,000 atoms)

Total fees: 2.0 L$ (2,000,000,000 atoms)
```

**Fund distribution:**

```
Sender's deduction: 1000 L$ (from balance)
Receiver gets: 1000 - 2.0 = 998 L$

Validator fees distributed:
- Protocol Team Group: 0.2 L$ total (sum of all protocol_team allocations)
- Implementation Team Group: 0.2 L$ total (sum of all implementation_team allocations)  
- Validators: 1.6 L$ total (sum of all validator_net)
```

**Note on atoms vs L$:**

All protocol-level calculations use AXC atoms (integers). `L$` values in documentation are for human readability and converted via digit_version. See Section 2.3 for details on `L$` as display unit.

### 17.2.1 Dual Hash Function Design (BLAKE3 + SHA-3)

AXIOM uses **two different hash functions** for different purposes:

| Function | Algorithm | Purpose | Characteristics |
|----------|-----------|---------|-----------------|
| **tx_id** | BLAKE3 | Transaction identification | High-frequency, low-stakes |
| **State Hash** | SHA-3 | S-ABR balance verification | Low-frequency, high-stakes |

**Why not unify to a single hash function?**

**1. Separation of Concerns**

Separating "transaction identification" from "balance security" prevents single-algorithm vulnerabilities from causing total system failure:

- **BLAKE3 (Transaction Layer):** Responsible for fast retrieval. If BLAKE3 develops theoretical weaknesses, only `tx_id` uniqueness is challenged -- a database management issue that does not directly threaten asset security.

- **SHA-3 (Consensus Layer):** Responsible for asset sovereignty. S-ABR relies on SHA-3 to ensure the "Refill" process cannot be forged. Even if the `tx_id` layer is compromised, the SHA-3-protected ledger remains secure.

**2. Performance Optimization**

- **tx_id operations** require frequent grep, sorting, and network broadcast. BLAKE3's parallel processing capability makes these "high-frequency, low-pressure" operations extremely fast.

- **S-ABR hash comparison** is a "low-frequency, high-pressure" operation occurring only at critical state transition moments. SHA-3's conservative, rigorous design prioritizes security over speed.

**3. Future-Proofing & Upgradability**

AXIOM's design philosophy is **modular security**:

- If quantum computing or other threats emerge, this separation allows upgrading only the S-ABR algorithm (SHA-3 layer) without modifying all transaction retrieval logic.

- The protocol already provides three signature algorithm choices (Ed25519, Dilithium, SPHINCS+). Hash function separation follows the same **Defense in Depth** principle.

**4. Binary Size Consideration**

For modern computers and validator nodes, reducing `axiom-core.elf` by a few hundred KB (removing one hash library) provides marginal benefit far outweighed by the catastrophic risk of collision resistance failure. SHA-3's $O(2^{256})$ mathematical barrier is a non-negotiable protocol baseline.

**Design Analogy:** Like a building where decorative bolts (tx_id) can use lightweight materials, but structural beams (state hash) must use the strongest standard components.

**5. SHA-3 vs BLAKE3: Safety and Efficiency Trade-offs**

| Feature | SHA-3 (Keccak) | BLAKE3 |
|---------|----------------|--------|
| **Standardization** | NIST Standard (FIPS 202) | Open Source (Community Trust) |
| **Scrutiny** | Decades of institutional vetting | Modern, rapidly adopted |
| **Speed** | Slower (especially in software) | Extremely fast (parallelized) |
| **Construction** | Sponge construction | Merkle tree structure |
| **Length-extension** | Resistant | Resistant |
| **Best For** | Institutional/long-term security | High-performance hashing |

**Why AXIOM uses both:**

- **SHA-3 for state_hash:** The Lambda protocol relies on SHA-3's collision resistance ($O(2^{256})$) as one of the "Three Pillars of S-ABR Security" to mathematically block double-spending. Its proven mathematical rigor and institutional backing make it the anchor for state-transition integrity.

- **BLAKE3 for txid:** Maximum efficiency for transaction identification, deduplication, and indexing where the absolute highest cryptographic rigor is not required.

**Conclusion:** If "safer" means proven mathematical rigor and institutional backing, SHA-3 is the choice. If "safer" means modern protection with maximum efficiency, BLAKE3 is the choice. AXIOM uses each where its strengths matter most.

### 17.2.2 Canonical Bytes Specification

Transaction payloads MUST be serialized to **Canonical Bytes (CB)** before:
- Signature computation
- txid calculation
- Core validation

> **MANDATORY:** Any client, validator, or gateway claiming Lambda compatibility MUST produce identical CB for identical semantic input.

**Key Properties:**

| Property | Specification |
|----------|---------------|
| **Unicode** | NFC normalization (mandatory) |
| **Bytes encoding** | `b64u:<base64url_no_padding>` prefix |
| **Object key ordering** | Unicode codepoint ascending |
| **Integer format** | Shortest decimal representation |
| **Whitespace** | None (minimized JSON) |

**Hash Calculation:**

```
CB_core = Canonical Bytes of semantic data (excluding signatures)
CB_full = CB_core || client_sig || witness_sigs

txid = BLAKE3(CB_core)           // For deduplication, indexing
state_hash = SHA3-256(CB_full)   // For S-ABR state verification
```

**Framing Format:**

```
CB := MAGIC(4) || CB_VERSION(1) || CODEC(1) || LEN(varint) || PAYLOAD || CRC32C(4)

MAGIC      = 0x4C 0x41 0x4D 0x42  ("LAMB")
CB_VERSION = 0x01
CODEC      = 0x01 (Canonical JSON)
```

**Gateway Invariant:**

> **CRITICAL:** Gateways MUST NOT alter CB content. After any Gateway processing (encryption, batching, transport), `CB_received` MUST equal `CB_original` byte-for-byte.

**Complete Specification:** See `LAMBDA_CANONICAL_JSON_BYTES.md`

**Determinism Contract:** See `LAMBDA_DETERMINISM_CONTRACT.md`

**Conformance Testing:** See `LAMBDA_CONFORMANCE_CLI_SPEC.md`

**Document Authority Map:** See `AXIOM_DESIGN_LockedSet.md`

### 17.3 Witness Overlap Rule (Double-Spend Prevention)

**Critical requirement for chain of evidence:**

Every transaction MUST include a minimum number of validators from the previous transaction's witness set. For k=3 (standard tier), this minimum is **≥2 validators**. See Section 17.3.1 for tier-specific requirements.

**Why this is mandatory:**

The current state was defined by the previous validators. The next transaction's validators cannot verify state validity without consulting validators who witnessed the previous state transition. The ≥2 requirement (for k=3) ensures that any two concurrent transactions MUST share at least one validator, preventing zero-time double-spend attacks.

```
State_n witnessed by [V_A, V_B, V_C]
  ->
State_{n+1} witnessed by [V_A, V_B, V_D]
                         ^^^^^^^^
                         REQUIRED: At least 2 from previous set (for k=3)
```

This creates an unbroken **chain of evidence**:
- Each state transition is anchored by validators who witnessed the previous state
- No state can be validated in isolation
- Double-spend attempts are blocked by the overlap requirement ensuring witness set intersection

**Rule:**

Every transaction (except genesis) MUST have the required overlap with the previous transaction's witness set. For k=3, this means ≥2 witnesses in common.

```
Tx_1: witnesses = [A, B, C]
Tx_2: witnesses = [A, B, E]  ✓ (A and B overlap - carries state knowledge)
Tx_3: witnesses = [A, E, F]  ✓ (A and E overlap with Tx_2)

Tx_invalid: witnesses = [X, Y, Z]  ✗ (no overlap with Tx_3)
                                      Cannot verify state lineage
```

**Why this prevents double-spend:**

If a malicious actor attempts to spend the same state twice:

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=3.5cm, minimum height=0.8cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth},
    dasharrow/.style={->, thick, >=stealth, dashed, red!60}
]
\node[box, draw=blue!50, fill=blue!5] (S) at (0,0) {State\_100\\{\scriptsize witnessed by A, B, C}};
\node[box, draw=green!50, fill=green!5] (TX) at (-3.5,-2) {Tx\_A $\to$ State\_101\\{\scriptsize witnesses: A, B, C}};
\node[box, draw=red!50, fill=red!5] (INV) at (3.5,-2) {\textbf{INVALID}\\{\scriptsize Must include $\geq$1 of \{A,B,C\}}};
\draw[arrow] (S) -- (TX);
\draw[dasharrow] (S) -- node[right, font=\scriptsize, xshift=2pt] {Tx\_B $\to$ State\_102} (INV);
\node[font=\scriptsize, red!70] at (3.5,-3) {witnesses: X, Y, Z --- no overlap};
\end{tikzpicture}
\caption{S-ABR Double-Spend Prevention --- At least one previous witness must participate.}
\end{figure}
```

Since {X,Y,Z} have no overlap with {A,B,C}:
- They cannot verify State_100 is the latest valid state
- They have no knowledge of whether State_100 was already consumed
- At least one of {A,B,C} must participate to provide state continuity
- That validator will refuse to sign Tx_B because State_100 is already consumed by Tx_A

**This is enforcement through required knowledge, not through global consensus.**

Even if the malicious actor finds validators willing to sign, the transaction cannot satisfy the overlap rule without involving at least one validator who knows State_100 was already consumed by Tx_A.

**See also:**
- Appendix C: Validator State Machine (for PENDING/READY states)
- "Transaction Logic" document for enforcement philosophy

### 17.3.1 Quantitative Overlap Requirements

**The basic overlap principle (>=1 common witness) establishes the chain of evidence foundation. However, implementation-level security requires precise quantitative thresholds to prevent edge-case attack vectors.**

#### 17.3.1.1 Tier-Specific Overlap Thresholds

The minimum overlap requirement varies by security tier:

| Tier (k) | Minimum Overlap | Witnesses from Previous | New Witnesses | Security Rationale |
|----------|----------------|------------------------|---------------|-------------------|
| **k=3** | **>=2** | 2 of 3 | 1 of 3 | Ensures any two concurrent transactions share >=1 validator |
| **k=4** | **>=3** | 3 of 4 | 1 of 4 | Higher security tier demands proportional overlap |
| **k=5** | **>=3** | 3 of 5 | 2 of 5 | Balanced: strong continuity with validator diversity |

**Formal rule:**

```
For tier k:
  required_overlap = sabr_overlap(k) = floor(k/2) + 1

Examples:
  k=3: floor(3/2) + 1 = 2
  k=4: floor(4/2) + 1 = 3
  k=5: floor(5/2) + 1 = 3
```

**v2.11.16 — Overlap derived from previous TX's k:** The overlap requirement is now derived from `prev_receipts[0].witness_sigs.len()` (the previous TX's actual k), NOT from `effective_k(current_tx)`. This prevents tier-downgrade double-spend: TX1(k=5) -> TX2(k=3) requires `sabr_overlap(5) = 3` overlap, not `sabr_overlap(3) = 2`. After one TX at the lower tier, overlap returns to the lower tier's cost. See `consensus.rs::validate_sabr_new`.

**v2.11.16 — Sender wallet_id tier switching:** The identity-binding that locked `sender_wallet_id` to the first-used tier has been removed. Replaced with a pk-ownership check via `verify_pk_binding` in `validation.rs`. The same wallet can now freely switch between Standard(k=3)/Secure(k=4)/AAA(k=5) per TX. Security is preserved: pk_bind prevents impersonation, dual-layer genesis lockup is unaffected, Ark rules check per-TX `sender_k`. Design intent: the receiver chooses the security level per TX by giving the sender the appropriate tier address.

**Core validation:**

```rust
fn validate_overlap(prev_witnesses: &[PubKey], curr_witnesses: &[PubKey], tier: u8) 
    -> Result<(), ValidationError> 
{
    let overlap_count = curr_witnesses.iter()
        .filter(|w| prev_witnesses.contains(w))
        .count();
    
    let required = match tier {
        3 => 2,
        4 => 3,
        5 => 3,
        _ => return Err(InvalidTier),
    };
    
    if overlap_count < required {
        return Err(InsufficientOverlap { required, actual: overlap_count });
    }
    
    Ok(())
}
```

#### 17.3.1.2 Attack Vector Analysis: Concurrent Double-Spend

**Scenario:** Malicious client attempts to spend same state through two disjoint validator sets.

**With overlap >=1 only (insufficient):**

```
Alice (100 atoms)
prev_witnesses = {V1, V2, V3}

TX_A: 60 -> Bob
  overlapped: V1
  witnesses: {V1, V4, V5}

TX_B: 60 -> Carol (concurrent)
  overlapped: V2  (different from TX_A!)
  witnesses: {V2, V6, V7}

Result:
  V1 sees TX_A, marks state consumed
  V2 sees TX_B, marks state consumed
  No validator sees BOTH transactions
  Both TX_A and TX_B succeed *-
  Total atoms: 100 - 60 - 60 = -20 (conservation violated!)
```

**Attack succeeds because:**
- V1 and V2 don't communicate
- Overlap >=1 doesn't guarantee intersection between concurrent transactions
- Each validator only knows their own transaction

**With overlap >=2 (secure):**

```
Alice (100 atoms)
prev_witnesses = {V1, V2, V3}

TX_A: 60 -> Bob
  overlapped: V1, V2  (must choose >=2)
  witnesses: {V1, V2, V4}

TX_B: 60 -> Carol (concurrent)
  overlapped: must choose >=2 from {V1, V2, V3}
  Possible combinations:
    {V1, V2} -> shares {V1, V2} with TX_A
    {V1, V3} -> shares {V1} with TX_A
    {V2, V3} -> shares {V2} with TX_A

Mathematical guarantee:
  witnesses(TX_A)  witnesses(TX_B) >= 1 (always!)

Result:
  Shared validator (e.g., V1) receives both TX_A and TX_B
  V1 processes TX_A first -> marks state consumed
  V1 rejects TX_B -> DOUBLE_SPEND error
  Attack prevented *"
```

**Combinatorial proof (k=3, overlap=2):**

```
Given prev_witnesses = {V1, V2, V3}
Number of 2-combinations: C(3,2) = 3

Combinations: {V1,V2}, {V1,V3}, {V2,V3}

Any two combinations must intersect:
  {V1,V2}  {V1,V3} = {V1}  *"
  {V1,V2}  {V2,V3} = {V2}  *"
  {V1,V3}  {V2,V3} = {V3}  *"

Conclusion: Impossible to construct two disjoint witness sets
```

#### 17.3.1.3 Trade-off Analysis

**Increased overlap requirement introduces two trade-offs:**

**Trade-off 1: Validator Diversity**

| Metric | overlap >=1 | overlap >=2 (k=3) | Impact |
|--------|-----------|------------------|---------|
| Choices per TX | C(3,1)-PWV2 = 3-PWV2 | C(3,2)-PWV = 3-PWV | Reduced by factor of PWV |
| Validator rotation speed | 2 TXs | 3 TXs | +50% time to fully rotate |
| Lock-in to validator set | Low | Medium | Acceptable (gradual rotation still possible) |

**Example:** Rotating from {V1,V2,V3} to {V4,V5,V6}

```
overlap >=1 path:
  TX_0: {V1, V2, V3}
  TX_1: {V1, V4, V5}  (1 overlap)
  TX_2: {V4, V5, V6}  (2 overlap)
  -> 2 transactions

overlap >=2 path:
  TX_0: {V1, V2, V3}
  TX_1: {V1, V2, V4}  (2 overlap)
  TX_2: {V1, V4, V5}  (2 overlap: V1,V4)
  TX_3: {V4, V5, V6}  (2 overlap: V4,V5)
  -> 3 transactions (+1 TX)
```

**Assessment:** Acceptable cost for security enhancement.

**Trade-off 2: Recovery Probability**

| Tier | Overlap | Liveness Requirement | Failure Probability (p=0.99 uptime) | Recovery Frequency |
|------|---------|---------------------|-------------------------------------|-------------------|
| k=3 | >=1 | 1-of-3 available | 0.0001% (1 in 1M) | ~Never |
| k=3 | >=2 | 2-of-3 available | 0.03% (1 in 3,333) | ~1 per 9 years |
| k=4 | >=3 | 3-of-4 available | 0.06% (1 in 1,667) | ~1 per 4.5 years |
| k=5 | >=3 | 3-of-5 available | 0.001% (1 in 100K) | ~1 per 250 years |

**Calculation methodology:**

```python
from math import comb

def recovery_prob(n, required, p_up=0.99):
    """Calculate probability of needing recovery"""
    p_down = 1 - p_up
    prob = 0
    for failures in range(n - required + 1, n + 1):
        alive = n - failures
        prob += comb(n, failures) * (p_down ** failures) * (p_up ** alive)
    return prob

# k=3, overlap>=2 -> need 2-of-3 alive
recovery_prob(3, 2, 0.99)  # = 0.0003 = 0.03%

# k=5, overlap>=3 -> need 3-of-5 alive  
recovery_prob(5, 3, 0.99)  # = 0.00001 = 0.001%
```

**Practical impact:**

Assuming daily transactions:
- k=3: 365 - 0.0003 = 0.11 recovery events per year
- k=5: 365 - 0.00001 = 0.004 recovery events per year

**Assessment:** Recovery remains extremely rare. Enhanced security justified.

**Validator operational stability:**
- Low infrastructure cost -> high uptime expected
- Economic incentive to remain available (fee revenue)
- Recovery protocol exists (Section 17.4) for edge cases

#### 17.3.1.4 Core Enforcement

**The overlap quantitative requirement is enforced at the Core validation layer:**

```rust
// In axiom-core.elf validation logic
fn validate_transaction(tx: &Transaction, ctx: &ValidationContext) 
    -> Result<ValidationResult, ValidationError> 
{
    // ... other validations ...
    
    // Overlap enforcement
    validate_overlap(
        &ctx.prev_witnesses,
        &tx.current_witnesses,
        tx.tier
    )?;
    
    // ... continue validation ...
}
```

**This is a hard protocol rule:**
- Transactions violating overlap requirements are **invalid**
- No validator will sign such transactions
- Core rejects before signature generation

**Not policy, not coordination:** This is deterministic mathematical validation, identical across all implementations.

#### 17.3.1.5 Relationship to White Paper

**White Paper v2.28 establishes the principle:**
> "Witness overlap requirement ensures chain of evidence continuity"

**This Yellow Paper section provides:**
- Quantitative thresholds for implementation
- Attack vector analysis justifying the thresholds
- Trade-off analysis for practical deployment

**This is specification refinement, not correction:**
- White Paper principle remains correct (overlap IS required)
- Yellow Paper adds: "overlap >=k_min where k_min depends on tier"
- Transition from philosophy to executable specification

**Design philosophy preserved:**
- No global consensus required
- Local validator state enforcement
- Mathematical guarantees over coordination
- Chain of evidence continuity maintained

### 17.3.2 Chain of Evidence: Key Clarifications

This section addresses common questions about how Chain of Evidence works in practice.

#### 17.3.2.1 Why ≥2 Overlap? (Zero-Time Double-Spend Attack)

The ≥2 overlap requirement (for k=3) exists specifically to prevent **zero-time double-spend attacks**, not to detect lying validators.

**The Attack (with only ≥1 overlap required):**

```
Alice has 1000 AXC
Previous transaction witnessed by: [V1, V2, V3]

Alice sends TWO transactions at the SAME MOMENT:

    Tx_A: Alice → Bob (1000 AXC)
          Witnesses: [V1, V4, V5]  ← V1 overlaps (satisfies ≥1)
          
    Tx_B: Alice → Carol (1000 AXC)  
          Witnesses: [V2, V6, V7]  ← V2 overlaps (satisfies ≥1)

Problem:
  - V1 processes Tx_A, doesn't know about Tx_B
  - V2 processes Tx_B, doesn't know about Tx_A
  - Witness sets {V1, V4, V5} and {V2, V6, V7} have NO intersection
  - Both transactions succeed simultaneously
  - Alice spends 2000 AXC from 1000 AXC balance

Attack succeeds because there is NO shared validator to detect both attempts.
```

**The Solution (≥2 overlap required):**

```
Alice has 1000 AXC
Previous transaction witnessed by: [V1, V2, V3]

Alice attempts the same attack:

    Tx_A: Alice → Bob (1000 AXC)
          Must include ≥2 from {V1, V2, V3}
          Witnesses: [V1, V2, V4]
          
    Tx_B: Alice → Carol (1000 AXC)
          Must include ≥2 from {V1, V2, V3}
          Possible choices: {V1,V2}, {V1,V3}, or {V2,V3}
          
          Any choice MUST intersect with Tx_A's overlap:
            {V1, V2} ∩ {V1, V2} = {V1, V2}  ✓
            {V1, V3} ∩ {V1, V2} = {V1}      ✓
            {V2, V3} ∩ {V1, V2} = {V2}      ✓

Result: At least ONE validator sees BOTH Tx_A and Tx_B
        That validator signs only the first arrival
        Second transaction REJECTED
```

**Mathematical Guarantee:**

When selecting ≥2 elements from a set of 3, any two selections MUST share at least one element. This is a combinatorial certainty, not a probability.

#### 17.3.2.2 Does the Proof Chain Grow Endlessly?

**No.** The `prev_receipts` field contains signatures from the **immediately previous transaction only**, not the entire transaction history.

```
Transaction structure (simplified):

Tx_n: {
    "prev_receipts": [
        // Signatures from Tx_{n-1} ONLY
        // NOT from Tx_{n-2}, Tx_{n-3}, ... , Genesis
    ]
}
```

**Example transaction chain:**

```
Tx_1 (Genesis claim):
    prev_receipts: [genesis_bootstrap_sig]     // ~1 signature
    
Tx_2 (Alice → Bob):
    prev_receipts: [V1_sig, V2_sig, V3_sig]    // ~3 signatures from Tx_1
    
Tx_3 (Bob → Carol):
    prev_receipts: [V2_sig, V3_sig, V4_sig]    // ~3 signatures from Tx_2
                                                // Does NOT include Tx_1 sigs
    
Tx_1000 (David → Eve):
    prev_receipts: [Va_sig, Vb_sig, Vc_sig]    // ~3 signatures from Tx_999
                                                // Does NOT include Tx_1...Tx_998
```

**Size is constant:**

| Field | Size | Growth |
|-------|------|--------|
| prev_receipts | ~3-5 signatures | **Fixed** (does not grow with history) |
| VBC bundle | ≤32 KiB | **Bounded** (max depth 8, renewal re-anchors) |

**The trust chain is implicit, not stored:**

Each validator trusts that previous validators already verified their predecessors. The full chain back to Genesis exists logically but is NOT carried in every transaction.

#### 17.3.2.3 Transitive Trust Model

**How can Tx_1000 be trusted without carrying proof back to Genesis?**

The answer is **transitive trust** through the overlap requirement:

```
Tx_1000 is valid because:
└── ≥2 witnesses overlap with Tx_999's witnesses
    └── Those validators verified Tx_999 was valid because:
        └── ≥2 witnesses overlapped with Tx_998's witnesses
            └── Those validators verified Tx_998 was valid because:
                └── ... (transitive chain) ...
                    └── Eventually reaches Genesis
```

**Key insight:** You don't verify the entire chain yourself. You trust that:

1. Previous validators followed the same rules you follow
2. They wouldn't sign invalid transactions (they'd lose stake)
3. The overlap requirement guarantees continuity

**This is similar to how you trust a certified document:**

```
You trust Document_D because:
└── It was signed by Authority_C
    └── Authority_C was certified by Authority_B
        └── Authority_B was certified by Authority_A
            └── Authority_A is a root certificate you trust

You don't verify A→B→C→D yourself.
You verify D's signature and trust the chain.
```

#### 17.3.2.4 What Happens When Genesis Validators Die?

**Nothing breaks.** Genesis validators can die immediately after Genesis.

**What Genesis validators provide (at Genesis only):**

```
GENESIS (t=0):
    G1, G2, G3 sign:
    - Market Allocation initial state (88,000,000 AXC)
    - Initial allocations to bootstrap wallets
    - First VBCs for early validators
```

**After Genesis, they become verification constants:**

| Genesis Validators | After Genesis |
|-------------------|---------------|
| Private keys | Can be DESTROYED (recommended for security) |
| Public keys | Hardcoded in axiom-core.elf FOREVER |
| Online presence | NOT required |
| Signing new transactions | NOT needed |
| Issuing new VBCs | NOT needed (other validators do this) |

**Why old signatures remain valid:**

```
Cryptographic signatures are HISTORICAL FACTS, not ongoing relationships.

G1 signed V10's VBC on 2026-01-01
    │
    └── This signature is PERMANENTLY VALID because:
        │
        ├── Signature = mathematical proof that G1's private key signed this data
        ├── G1 dying does NOT "un-sign" the signature
        ├── G1's private key being destroyed does NOT invalidate existing signatures
        └── Anyone with G1's public key can verify the signature FOREVER
```

**VBC chain example (year 2030, Genesis validators long dead):**

```
V_new wants to become a validator

V_new's VBC signed by: [V100, V101, V102]
    │
    └── V100's VBC signed by: [V50, V51, V52]
        │
        └── V50's VBC signed by: [V10, V11, V12]
            │
            └── V10's VBC signed by: [G1, G2, G3]  ← Genesis signatures (2026)

Verification (in 2030):
    1. V_new has V100's signature? ✓
    2. V100 has valid VBC? → check V50's signature ✓
    3. V50 has valid VBC? → check V10's signature ✓
    4. V10 has valid VBC? → check G1, G2, G3 signatures ✓
    5. G1, G2, G3 public keys in axiom-core.elf? ✓
    
    All signatures valid. V_new accepted as real validator.
    
    G1, G2, G3 being dead is IRRELEVANT.
    Their signatures from 2026 are still mathematically valid.
```

**Analogy: Constitutional founding:**

```
The Genesis validators are like constitutional founders:
- They sign the founding documents ONCE
- Their signatures establish the root of trust
- They can die afterward - the constitution remains valid
- Future generations verify against the DOCUMENT, not the dead founders
- The founders' public keys (compiled into axiom-core.elf) are the "constitution"
```

#### 17.3.2.5 Summary: Chain of Evidence Security Model

| Question | Answer |
|----------|--------|
| Why ≥2 overlap? | Prevents zero-time double-spend by guaranteeing witness set intersection |
| Does proof chain grow? | No - prev_receipts contains only previous transaction's signatures |
| How is Genesis verified? | Transitive trust - each validator verifies their predecessor |
| What if Genesis dies? | Nothing - signatures are permanent mathematical facts |
| Where is full history? | Distributed across validators who witnessed each transaction |
| Is there a central record? | No - trust is cryptographic, not centralized |

### 17.4 Witness Recovery Protocol (WR)

#### 17.4.0 Recovery Trigger Conditions (Updated v1.4)

**When can Recovery be initiated?**

Recovery is NOT required when "all validators are dead." Recovery can be initiated when the client **cannot achieve the required overlap** for a State Update.

| Previous TX Tier | Required Overlap | Recovery Trigger |
|------------------|------------------|------------------|
| Tier 3 | >=2 | Alive validators from prev set < 2 |
| Tier 4 | >=3 | Alive validators from prev set < 3 |
| Tier 5 | >=3 | Alive validators from prev set < 3 |

**Example:**

```
Bob's last State Update was Tier 5 with validators: {V_A, V_B, V_C, V_D, V_E}

Scenario 1: V_A, V_B, V_C alive (3 alive)
  - Can achieve >=3 overlap
  - NO recovery needed
  - Normal transaction proceeds

Scenario 2: V_A, V_B alive, V_C, V_D, V_E dead (2 alive)
  - Cannot achieve >=3 overlap
  - Recovery CAN be initiated
  - Use Tier 3 recovery TX (only needs >=2 overlap)
  - New validator set: {V_A, V_B, V_NEW}
  - After recovery, normal transactions resume
```

**Recovery is a Tier downgrade mechanism:**

When the user cannot meet the overlap requirement of their previous tier, they can use a lower tier transaction to "refresh" their validator set:

1. Previous: Tier 5 with 5 validators, 2 alive
2. Recovery: Tier 3 transaction (needs >=2 overlap)
3. Select: 2 alive + 1 new validator = 3 validators
4. Result: New validator set with 3 live validators
5. Now: Can submit Tier 3/4/5 transactions using standard k=3 witnessing with no restrictions.

**Client App Behavior (Suggested):**

When initiating a transaction:
1. Attempt to contact previous validators
2. Count how many respond
3. If `alive_count >= required_overlap`: proceed with standard witness collection (no overlap error).
4. If `alive_count < required_overlap`: notify user
   - "Cannot complete transaction with current validators"
   - "Suggest: Initiate Recovery with Tier 3"

This is UX guidance, not protocol requirement.


**Scenario: All previous witnesses unreachable**

```
Previous witnesses: [A, B, C]
All offline/disappeared
User needs to make new transaction
```

**Recovery procedure:**

1. **Client initiates Witness Recovery query**
   - Broadcasts: "Who certified validators A/B/C?"
   - Uses same propagation mechanism as DWP (Section 18)

2. **Meta-validators respond**
   - Validators who previously certified A/B/C identify themselves
   - Provide certification proof

3. **Validator Integrity Challenge (VIC)**
   - Meta-validators execute VIC on A/B/C:
     - Network reachability test
     - Cryptographic challenge (sign nonce)
     - Stake verification (>=500 AXC)
     - Test transaction execution
     - Liveness timestamp check

4. **VIC outcomes:**
   - **PASS**: Original validator still operational -> must be included in witness set
   - **FAIL**: Validator genuinely unavailable -> meta-validator authorized to replace
   - **INCONCLUSIVE**: Retry (max 3 attempts)

5. **New transaction formation**
   - If all VICs FAIL: Meta-validators become new witnesses
   - Transaction proceeds with meta-validator signatures
   - Overlap rule satisfied through meta-delegation chain

**VIC is critical:**

Without VIC, a malicious client could falsely claim witnesses are unavailable and bypass the overlap rule. VIC ensures only genuinely unreachable validators can be replaced.

**Fee Loss During Recovery:**

> **ECONOMIC INVARIANT:** Fee loss during recovery does NOT create economic gain for the client and CANNOT be repeated or scaled without destroying transaction liveness.

Recovery prerequisites ensure this cannot be exploited:
- Recovery requires witnesses to be genuinely unreachable (verified by VIC)
- Client cannot arbitrarily trigger recovery
- Unpaid fees to disappeared validators represent loss to validators, not gain to client
- Attempting to "game" recovery destroys the client's ability to transact

This is fee loss, not supply inflation or client profit.

### 17.5 Genesis Transactions

**First transaction has no previous state:**

```json
{
  "input": {
    "state_id": "st:genesis:null",
    "owner_pk": null,
    "prev_receipts": []
  },
  "debit": {
    "amount_atom": 0,  // No debit (receiving, not spending)
    "receiver_pk": "ed25519:pk_USER...",
    "reference": "genesis allocation"
  },
  "next_state_core": {
    "balance_atom": 10000000000000,  // Initial allocation
    ...
  }
}
```

**Properties:**
- No double-spend risk (creating value, not transferring)
- Still requires k witnesses (proves allocation legitimacy)
- Subsequent transactions must follow overlap rule

### 17.6 Ark-Mode Transaction Specifics

**Offline transactions between two parties:**

When operating under Ark-Mode (Section 11), transactions involve only sender and receiver as mutual witnesses:

```json
{
  "witness_set": [
    {"validator_pk": "pk_SENDER", "resolution": {"offline": true}},
    {"validator_pk": "pk_RECEIVER", "resolution": {"offline": true}}
  ],
  "receipts": [
    {"validator_pk": "pk_SENDER", "sig": "..."},
    {"validator_pk": "pk_RECEIVER", "sig": "..."}
  ]
}
```

**Key differences:**
- k=2 (sender + receiver only)
- No external validators required
- Marked as offline/partition transactions
- Subject to reconciliation dilution upon reconnection (Section 11.4)

**Overlap rule modification for Ark-Mode:**

During partition, overlap rule applies only within the partition context. Upon reconnection, global overlap rule is re-established through reconciliation process.

### 17.7 Resync: Recovering Lost Wallet State

**Scenario: Wallet data loss, device migration, or failed write**

Client only remembers: `state_id` OR `tx_id`

**RCP_FETCH protocol:**

```
Client -> Any Validator: RCP_FETCH { state_id: "st:b3:..." }

Validator response:
- If witness: return full transaction payload
- If not witness: return witness_hints (referral)
```

**Recovery process:**

1. Client queries any accessible validator
2. If that validator witnessed the transaction -> full payload returned
3. If not -> validator provides witness_hints (contact info for actual witnesses)
4. Client contacts actual witness -> recovers full state
5. Wallet state reconstructed from transaction payload

**What can be recovered:**
- `state_core` (balance, nonce)
- `receipts` (proof of legitimacy)
- `witness_hints` (for future transactions)

**What cannot be recovered:**
- Lost private keys (no protocol-level recovery)
- Transactions never written to any witness (no redundancy)

### 17.8 Non-Claim Behavior

**Scenario: Receiver never writes transaction to wallet**

```
Sender -> Receiver: Transfer 1000 AXC
Receiver: Device lost / Never opened wallet / Refused payment
```

**Effects:**

- Does NOT cause double-spend (sender's state already consumed)
- Does NOT allow rollback (witnesses signed next_state)
- Does NOT leak value (AXC conservation maintained)
- Does NOT break consensus (transaction is valid)

**Only impact: Asset becomes non-circulating**

The 1000 AXC exists in an unclaimed state. Receiver can still claim later using RCP_FETCH, but if receiver_pk is permanently lost, value is effectively burned.

**Protocol position:**

No immediate reclaim mechanism defined. Potential future approaches (not currently specified):
- Time-locked reclaim to sender
- DEED system for inheritance
- Burn pool for permanent non-claim

Full payload storage by witnesses ensures future recovery options remain possible.

### 17.9 Complete Transaction Lifecycle

This section describes the full lifecycle of a transaction from initiation to final state settlement for both sender and receiver.

#### 17.9.1 Overview: The Cheque Model

AXIOM transactions follow a **cheque model** rather than traditional instant settlement:

| Traditional Transfer | AXIOM (Cheque Model) |
|---------------------|----------------------|
| Instant balance update | Receive cheque (3 sigs) |
| Passive receipt | Active redemption required |
| Must be online | Can receive offline, redeem later |
| Single atomic operation | Two-phase: issuance + redemption |

**Key insight:** When sender completes validation, receiver receives a "cheque" -- 3 validator signatures that guarantee the funds. The receiver can "cash" this cheque at any time to update their validated state.

#### 17.9.2 Transaction Flow Diagram

```
SENDER                          VALIDATORS (k=3)                    RECEIVER
   |                                  |                                  |
   |                                  |                                  |
   |  +-----------------------------------------------------------+      |
   |  |                    PHASE 1: SENDER SETTLEMENT             |      |
   |  |            (sequential — S-ABR + FACT accumulation)       |      |
   |  +-----------------------------------------------------------+      |
   |                                  |                                  |
   | TX --------------------------> V1 (overlapped)                       |
   |<---- sig_1 (+ fact_sig_1) ---- V1                                  |
   |                                  |                                  |
   | TX + [sig_1] ----------------> V2 (overlapped)                      |
   |<---- sig_2 (+ fact_sig_2) ---- V2                                  |
   |                                  |                                  |
   | TX + [sig_1, sig_2] --------> V3 (may/may not be overlapped, k=3)  |
   |<---- sig_3 + receipt ---------- V3 --- cheque (×3) ----------->|   |
   |                                  |                                  |
   | ACK --------------------------->|                                  |
   |                                  |                                  |
   |  [*] Sender state: COMPLETE      |      [v] Cheque received         |
   |  [*] Fees: PAID                  |      (not yet redeemed)          |
   |  [*] Balance: DEBITED            |                                  |
   |                                  |                                  |
   |                                  |                                  |
   |  +-----------------------------------------------------------+      |
   |  |                    PHASE 2: RECEIVER REDEMPTION           |      |
   |  |       (S-ABR via validator selection, may be parallel)    |      |
   |  +-----------------------------------------------------------+      |
   |                                  |                                  |
   |                                  |<---- cheque + current_balance ---|
   |                                  |                                  |
   |                                  |      Validators verify:          |
   |                                  |      - cheque sigs valid? [v]    |
   |                                  |      - S-ABR: receiver balance   |
   |                                  |        correct? (overlapped)     |
   |                                  |      - new_balance = current +   |
   |                                  |        cheque_amount             |
   |                                  |      - FACT chain valid? [v]     |
   |                                  |                                  |
   |                                  | 3 sigs (confirmed) ------------->|
   |                                  |                                  |
   |                                  |      [*] Receiver state: COMPLETE|
   |                                  |      [*] Balance: CREDITED       |
```

**Why S-ABR overlap requires accumulated signatures (not full sequential):**
- Non-overlapped validators MUST verify that ≥k-1 overlapped validators already witnessed this TX
- Overlapped validators check S-ABR independently (they have the sender's state from the previous TX)
- The accumulated `overlapped_signatures` provide proof of prior witness to non-overlapped validators
- FACT requires k=3 fact_signatures for link assembly (collected from all witnesses)

**Parallel witness proving (v2.10.33):**

With STARK proofs, overlapped validators do NOT depend on each other. Each independently has the sender's state from the previous TX. The STARK proof mathematically guarantees each validator ran the S-ABR check — no validator needs to cross-check another's work.

The dependency graph is: overlapped validators prove in parallel; non-overlapped validators wait for their accumulated signatures, then prove in parallel with each other.

```
k=3 (2 overlapped, 1 new):
  V1 (overlapped) prove ──┐
                            ├→ collect 2 overlap sigs → V3 (new) prove
  V2 (overlapped) prove ──┘
  Rounds: 2

k=4 (3 overlapped, 1 new):
  V1 (overlapped) prove ──┐
  V2 (overlapped) prove ──┼→ collect 3 overlap sigs → V4 (new) prove
  V3 (overlapped) prove ──┘
  Rounds: 2

k=5 (3 overlapped, 2 new):
  V1 (overlapped) prove ──┐
  V2 (overlapped) prove ──┼→ collect 3 overlap sigs → V4 (new) prove ─┐
  V3 (overlapped) prove ──┘                           V5 (new) prove ─┘
  Rounds: 2
```

All cases collapse to exactly 2 rounds regardless of k. With GPU proving (~4s per proof), total proving time is ~8 seconds for any k value.

#### 17.9.3 Sender Flow (Two-Round Parallel)

The sender flow must complete before the transaction is considered valid:

```
Step 1: Sender creates TX
        + amount_atom
        + receiver_pk
        + prev_receipts (from sender's last COMPLETE state)
        - fees

Step 2: Sender -> Overlapped Validators (PARALLEL, Round 1)
        - TX sent to all overlapped validators simultaneously
        - Each overlapped validator independently:
          • Verifies S-ABR (consumed_state_id == own stored state)
          • Runs CL3 checkpoint inside zk-VM (STARK proof)
          • Signs commitment_hash (Ed25519) + fact_commitment (Dilithium)
          • Returns WitnessSig to client
        - Client collects all overlap signatures

Step 2b: Sender -> Non-Overlapped Validators (PARALLEL, Round 2)
        - TX + collected overlapped_signatures sent to non-overlapped validators
        - Each non-overlapped validator independently:
          • Verifies ≥k-1 valid overlap signatures exist
          • Runs CL3 checkpoint inside zk-VM (STARK proof)
          • Returns WitnessSig to client
        - Each validator accumulates prior signatures
          (required for S-ABR overlap and FACT k=3 assembly)

Step 3: Validators verify
        + prev_receipts valid?
        + balance sufficient?
        + no double-spend?
        - fees acceptable?

Step 4: Validators -> Sender
        - k=3 witness signatures
        - Sender state finalized (new state_id, new balance)

Step 5: Validators -> Receiver
        - k=3 cheques sent via email (ANTIE)
        - Each cheque signed by issuing validator

Step 6: Sender -> Nabla
        - Register TX with 1 Nabla node
        - Nabla node ID included in cheque metadata (ValidatorCheque.nabla_hint)
        - Gossip propagation across Nabla network
        - Register is IDEMPOTENT: a retry with the same (wallet, txid, new_state)
          tuple returns the same ACK + fact_confirm_signature without reapplying
          state (closes the "lost-ACK" recovery gap; see §17.9.5 Supplemental
          Registration below).

Step 6a (NORMATIVE): If Step 6 returns Pending / fails, the cheque has
        ALREADY been issued (Step 5) and the validators' stored state is
        already advanced. The sender's FACT link is scarred
        (nabla_confirmation: None) until a supplemental register succeeds.
        The sender SHOULD persist the pending register state and retry on
        the next outbound operation (§17.9.5).

Step 7: SENDER COMPLETE
        + Sender state finalized
        + Cheques issued to receiver
        + TX registered with Nabla
```

**No sender ACK round-trip (v2.11.6):** The sender's role ends after witnessing + Nabla registration. The sender does not send an explicit ACK message. Fees are paid by the receiver at redeem time (§20.8). This eliminates a full network round-trip from the sender's perspective.

**Implementation note:** Lambda internally marks consumed_state_id as consumed via an ACK mechanism triggered during cheque delivery (not by the sender). This is a validator-internal state transition (PENDING → CONFIRMED) that finalizes the consumption — before this point, the client may abandon and retry with a different TX. The "no ACK" claim refers to the absence of a sender-initiated ACK message on the wire, not the absence of internal state finalization.

#### 17.9.3.1 Receiver Flow — Fee at Redeem (v2.11.6)

The receiver pays validator fees when redeeming cheques. This gives the receiver full control over fee costs — they choose which validators to redeem with, and can shop for lower fees via VSP (§27.11).

```
SENDER                              VALIDATOR                          RECEIVER
   |                                    |                                  |
   | TX -------------------------------->|                                  |
   |                                    |                                  |
   |<--- witness sig ------------------|                                  |
   |     (sender's new state)          |                                  |
   |                                    |--- cheque (email) ------------->|
   |                                    |    (amount, no fee deduction)   |
   | SENDER DONE                        |                                  |
   |                                    |                                  |
   |                                    |<--- redeem request -------------|
   |                                    |     (cheques + receiver PK)     |
   |                                    |                                  |
   |                                    |--- redeem response ----------->|
   |                                    |    (amount - fee = net received)|
   |                                    |    RECEIVER DONE                |
```

**Fee flow:**
- Sender sends 1000 atoms → sender's balance decreases by 1000
- Cheques carry 1000 atoms (full amount, no deduction)
- Receiver redeems with k=3 validators at 10 atoms/validator fee
- Receiver's balance increases by 970 atoms (1000 - 30)
- Validators collect fees at redeem time

**Advantages over ACK model:**
1. Sender sends exact amount — no fee math, no mental overhead
2. No ACK round-trip — fewer network messages, simpler client implementation
3. Receiver controls fees — can shop for cheaper validators, redeem anytime
4. No "pending ACK" state — sender's state is final immediately after witnessing
5. No re-ACK recovery flow — one less failure mode

#### 17.9.3.2 Scar-Consent Pause (NORMATIVE — YPX-001 §1.5.1, ACTIVE 2026-07-11)

A send whose FACT chain carries an **unresolved link** — no
`nabla_confirmation`, no `burn_proof`, no `recall_proof` (the same
resolution rule FACT compression uses) — does not proceed silently: the
first overlapped validator contacted **pauses** the round
(`E_LAMBDA_SCAR_CONSENT_REQUIRED`), stores a single-use 6-digit passcode,
and delivers a `ScarConsentNotification` to the **receiver's** mailbox
(`AXIOM/scar_consent/<uuid>`, same carrier path as cheque delivery). The
passcode never travels to the sender in-protocol; the receiver ACCEPTS by
handing it to the sender out-of-band — that hand-off IS the consent.
REJECT is non-action: nothing was witnessed, no funds moved, the sender's
wallet is untouched.

The sender re-initiates the **same transaction** (identical
`consumed_state_id` / `nonce` / `epoch` ⇒ identical txid — `compute_txid`
and `compute_commitment_hash` both exclude `scar_passcode`, so witness
signatures from the paused attempt remain valid) with the
`Transaction.scar_passcode` field set.

**Multi-overlapped completion (the consent voucher).** Under S-ABR every
prior witness is overlapped and runs the gate independently, but the
passcode is stored only at the validator that generated it. On a passcode
match, that validator consumes the entry (single-use; a wrong or unknown
code rejects with `E_LAMBDA_INVALID_SCAR_PASSCODE`) and signs a
`ScarConsentVoucher` — Ed25519 over
`BLAKE3("AXIOM_SCAR_CONSENT_OK" || txid)` — returned on its witness
response. The sender's SDK pins that validator as the retry round's first
hop and carries the voucher on the remaining hops' requests; each later
overlapped validator verifies the voucher signature against the
**prev-receipt witness set the request already carries** (k-signed,
§15-anchored — the sender cannot alter it) and skips the gate. A bare
passcode with neither a local entry nor a valid voucher never passes: a
fabricated passcode cannot bypass consent at any validator.

**Consent is NOT cleansing — the scar is INHERITED (CORE RULE, YPX-001
§1.5.1a).** The receiver's redeem link is stamped by Core CL5 with the
sender's unresolved txids (`FactLink.inherited_scar_txids`), transitively,
and that set is BOUND INTO the FACT commitment — the k witnesses sign it,
so it cannot be stripped. While any inherited scar is unresolved the link
counts as scarred: FACT compression is blocked (the taint can never be
checkpointed away) and the receiver's OWN next send re-fires this gate, so
every downstream receiver consents in turn. An inherited scar clears only
when the ORIGIN txid resolves — re-registered at Nabla (§1.5.2 heal) or
BURNED (§1.5.4) — evidenced by a Nabla `NablaTxidAttestation` per source
txid in `FactLink.inherited_scar_resolutions`, hard-verified by Core
(Ed25519 + mandatory NBC root anchor). Without inheritance the gate would
be a one-hop wash: a sender with tainted provenance could launder it
through a consenting accomplice and get back clean money.

**Exemptions** (consent incoherent or disclosed by design): CLARA-attested
heals, burns (the cure for scars), RECALL, heal / HAL re-anchor
self-sends, and the **Ark carve-out** — links with `required_k = 0` (Ark
provenance) are excluded from the trigger and Ark-tier endpoint wallet_ids
skip the gate entirely; Ark risk is priced by the Confidence Index
(YPX-010), not a passcode. Clean chains incur zero overhead. Full as-built
specification and evaluation record: YPX-001 §1.5.1 + §1.5.1a.

#### 17.9.4 Receiver Flow (Asynchronous)

The receiver flow is independent and can occur at any time:

```
Step 1: Receive cheque
        " 3 sigs from validators (contains +amount)

Step 1.5 (NORMATIVE): Pre-accept Nabla verification (§4.6)
        " Query Nabla for sender's wallet state at consumed_state_id
        " Register the cheque claim on Nabla (also blocks double-redeem races)
        " Decide based on returned status:
            CLEAN    -> proceed to Step 2
            WAIT     -> stop / retry after Timer A (sender not yet propagated)
            SCARRED  -> stop under RequireConfirmed (default);
                        proceed under AcceptScarred (caller heals later)
            REJECT   -> stop (sender BANNED, claim CONFLICT, etc.)

Step 2: (Anytime later) Prepare redemption
        + cheque (3 sigs)
        " current_balance (receiver's latest validated state)

Step 3: Receiver -> Same 3 Validators
        " Redemption request: cheque + current_balance

Step 4: Validators verify
        + cheque sigs authentic?
        + current_balance matches receiver's last state?
        " Calculate: new_balance = current_balance + cheque_amount

Step 5: Validators -> Receiver
        " 3 sigs (new validated state)

Step 6: COMPLETE
        " Receiver state updated with new balance
```

**Step 1.5 — Pre-accept Nabla verification (NORMATIVE).** Before constructing a redeem request, the receiver MUST run §4.6 `verify_cheque` against Nabla to confirm the sender's send actually landed in the network's authoritative ledger. Without this step, a cheque whose sender failed to complete its Nabla `/register` will redeem successfully at k=3 validators (they each have stored state) but the receiver's resulting FACT link will be **scarred** — `nabla_confirmation: None`, no burn proof — because the receiver's own `/register` cannot match an inflow Nabla never saw. The scar persists on the receiver's chain, not the sender's, propagating downstream cost from the sender's incomplete send. The pre-accept check catches this before it becomes a scar.

The verification returns one of four statuses:

- **CLEAN** — Nabla confirms sender's state, cheque-claim register succeeded, sender state has matured (`registration_tick + MATURITY_TICKS_MIN ≤ now`). Safe to redeem.
- **WAIT** — Nabla doesn't yet see sender's state, or it's pre-maturity. Receiver should retry after Timer A (≥1 TARDIS tick = 5 s). Repeated WAIT across multiple Timer A retries typically means the sender never registered (KI cross-chain scar propagation).
- **SCARRED** — Nabla sees the sender but the cheque/sender chain has accumulated unconfirmed scars upstream. Under `RequireConfirmed` policy (default) the receiver MUST NOT redeem; under `AcceptScarred` policy the receiver proceeds with the understanding that the new FACT link will inherit the scar and require `wallet.heal()` later.
- **REJECT** — Sender BANNED, or cheque-claim CONFLICT (someone else claimed the same cheque first). Receiver MUST NOT redeem.

Reference implementation: `axiom-sdk::nabla::verify_cheque` at `sdk/client/src/nabla.rs:396`. Acceptance policy: `RedeemConfig.acceptance: ChequeAcceptance` (RequireConfirmed | AcceptScarred).

**Asymmetric verification thresholds (NORMATIVE).** `verify_cheque` queries Nabla nodes (sender's `nabla_hint` first, then random fill to 3) and applies different thresholds depending on signal direction:

- **Negative signals** (BANNED, cheque-claim CONFLICT) — **1-of-N trips the gate.** Any single Nabla node reporting Banned or Conflict causes the verify to return REJECT/WAIT. Bias is fail-closed: any suspicious signal stops the redeem.
- **Positive signals — sender state known, registration_tick mature** — **2-of-N agreement required.** At least two responding nodes must report the same non-zero sender state (or sufficient maturity tick) before the verify returns CLEAN. A single compromised or stale node cannot alone certify a state Nabla hasn't broadly accepted.
- **Claim proof** — **first valid OK wins.** The proof is signed by a single Nabla writer's key; "2 agreeing" doesn't apply — the proof either verifies (Core CL5 anchor) or it doesn't. Multiple OKs from different writers would carry different signatures over the same payload; we keep the first.

This asymmetry is intentional: negative signals lean fail-closed (one suspicious signal stops the redeem); positive signals require quorum agreement so a lone outlier can't greenlight. The 2-of-N threshold defends against a single compromised Nabla node fabricating "yes I have this state" responses. Tradeoff: legitimate redeems where only 1 node has the sender's state (lost-ACK + slow gossip) wait one Timer A cycle (5 s) for gossip to converge.

**Why 2-of-N is safe under realistic gossip latency.** TARDIS gossip propagates state updates across the Nabla mesh within ~1 tick (5 s). The sender's `nabla_hint` identifies the writer that actually committed the sender's register; querying the hint node first means the hint node + at least one peer that has received the gossip update is the common case. Honest writes reach 2-of-N quorum within Timer A in well-connected meshes. A receiver that fails to reach quorum under load can either retry after a delay or proceed under `AcceptScarred` with the understanding that the FACT link will need `wallet.heal()` later.

**Performance fast-path via `cheque.nabla_hint`.** When the cheque carries an `Option<NablaHint>` (sender's designated sticky Nabla node from §3.2 / YPX-003 §9), the receiver SHOULD query the hint node FIRST before falling back to a random selection of 3. The hint identifies the Nabla writer that the sender attempted to register with — querying it directly avoids the Timer A propagation wait that random-node-selection incurs. If the hint node is unreachable, the receiver falls back to the standard random-3 path.

**Receiver pays fees at redeem time (v2.11.6).** The fee is deducted from the cheque amount by the receiver's redeeming validators. See §20.8 for fee distribution details.

**Serial Witness Ordering (NORMATIVE, v2.11.14 errata).** Steps 3-5 MUST be
serial: the receiver contacts validators one at a time, not in parallel.
This applies to BOTH sends (§17.9.3) and redeems (§17.9.4).

**Why parallel is unsafe:** A redeem (or send) is a state transition — each
validator independently commits a new `state_id` for the wallet. If the
receiver contacts 3 validators in parallel and one times out:

  1. Validator A and B each commit `new_state_id` independently
  2. Validator C times out — never sees the request
  3. The receiver has 2/3 signatures — not enough for a k=3 receipt
  4. The receiver cannot register with Nabla (no valid k=3 receipt)
  5. The FACT link is permanently scarred — the committed state on A and B
     has no Nabla confirmation and no burn proof
  6. The wallet is now split: A and B have `new_state_id`, C has `old_state_id`

**Why serial is safe:** With serial ordering, the receiver contacts
validator 1, waits for success, then contacts validator 2 with validator 1's
signature, then validator 3 with signatures 1+2. If any validator times out,
the receiver stops — no partial commits exist, no state split. The receiver
retries from the last successful point.

**Performance impact:** Serial redeem adds ~2x witness time per TX (3
sequential calls vs 1 parallel batch). For k=3 at 5.3s/witness: serial =
15.9s, parallel would be 5.3s. This is an inherent cost of atomic k=3
consensus — the same tradeoff every distributed consensus system makes.

#### 17.9.4.0 Duplicate Cheque Delivery — Receiver Dedup Contract (NORMATIVE)

Receivers MUST tolerate duplicate cheque delivery from validators and MUST deduplicate by `(txid, validator_id)` before constructing a `ChequeBundle` for redemption. This is required because the protocol's error-recovery and caching mechanisms can legitimately cause the same cheque to be delivered to a receiver more than once.

**Sources of duplicate delivery:**

1. **Partial-witness retry.** The sender's client retries a witness request for the same TX after a timeout. If the validator already committed the partial but its response was lost in transit, the retry succeeds via the witness response cache (§YPX-016). The validator then emits a second cheque for the receiver via ANTIE/FATMAMA, because the validator has no way to distinguish "retry after lost response" from "new send." Both deliveries contain the same signed cheque bytes for the same `(txid, validator_id)` pair.

2. **YPX-016 witness response cache.** When the sender's client retries the same `(wallet_pk, tx_hash, consumed_state_id, wallet_seq)` to the same validator, the validator returns the cached response and the ANTIE delivery path fires again. Per YPX-016 this is by design and cryptographically sound — the cached response is bound to Core's `fact_signature`, so the validator legitimately endorsed the state transition exactly once even though two delivery events occurred.

3. **ANTIE redelivery under carrier failure.** §3.4 specifies that gateways MUST NOT deduplicate messages based on carrier path, because the same logical message received via different carriers provides independent evidence of delivery. Under a carrier fault or partition heal, the same cheque can therefore reach the receiver's inbox via more than one ANTIE path.

In all three cases, the duplicate deliveries carry IDENTICAL cheque bytes (same `txid`, same `validator_id`, same signature). The receiver cannot determine which delivery was "first" and does not need to — any delivery is as good as any other.

**Receiver dedup rule (MUST):**

```
For each cheque group (grouped by txid):
    seen = empty set
    deduped = []
    for each cheque in group:
        if cheque.validator_id in seen: skip
        add cheque.validator_id to seen
        append cheque to deduped
    if len(deduped) < k: group is incomplete, wait or fail
    use deduped[:k] as the redemption bundle
```

The dedup MUST happen BEFORE the receiver constructs the `ChequeBundle` passed to Lambda's redeem validator. Lambda's `ChequeBundle::verify_consistency` check rejects bundles where `has_distinct_validators()` returns false (§17.9.8), because Core's per-validator signature verification would otherwise double-count the same validator's endorsement. A receiver that fails to dedup and submits a bundle with duplicate `validator_id` entries will receive `Inconsistent cheque bundle` rejection from Lambda and be unable to redeem that TX until it dedups locally.

**Why dedup is the receiver's responsibility, not the validator's:**

Validators cannot dedup because they have no global view — they only know the cheques they themselves issued. Only the receiver sees all k validator cheques for a given TX, and only the receiver knows which ones arrived via redundant paths. Requiring the receiver to dedup keeps the protocol symmetric (validators emit one cheque per witness, receivers collapse duplicates) and avoids per-validator state about past deliveries.

**Client implementations MUST:**

- Dedup by `(txid, validator_id)` on the receiver side before every redeem attempt.
- Tolerate incoming cheques that are exact duplicates of already-seen cheques (no error, just discard).
- Treat a cheque with the same `txid` but a DIFFERENT `validator_id` from the same validator PK as a protocol error (would indicate validator misbehavior — one validator issuing two cheques under two identities).

**Note for SDK authors:** The reference client `scripts/pmc.py` implements this dedup in `do_redeem_cheques` (commit `8557875` and later). The webclient's redeem path likewise dedups before bundling. Any new client implementation MUST include this dedup step or it will experience spurious `Inconsistent cheque bundle` rejections under normal network conditions.

#### 17.9.4.1 Redeem Authorization Signature

The receiver MUST sign the redeem request to prove they authorize the redemption. This prevents unauthorized parties from redeeming cheques on behalf of others.

**Signing format:**

```
message = BLAKE3("AXIOM_REDEEM" || txid || receiver_pk)
receiver_sig = Ed25519_Sign(receiver_private_key, message)
```

Where:
- `txid` is the 32-byte transaction ID from the first ValidatorCheque in the bundle (all cheques in a bundle share the same txid)
- `receiver_pk` is the receiver's 32-byte Ed25519 public key
- The BLAKE3 hash produces a 32-byte digest which is signed

**Verification (Lambda):**

```rust
fn verify_redeem_signature(request: &RedeemRequest, txid: &[u8; 32]) -> bool {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"AXIOM_REDEEM");
    hasher.update(txid);
    hasher.update(&request.receiver_pk);
    let message = hasher.finalize();
    
    Ed25519_Verify(request.receiver_pk, message, request.receiver_sig)
}
```

**Security rationale:** Without this signature, anyone who intercepts a ChequeBundle in transit could present it to validators and redirect the funds. The receiver_sig binds the redemption to the intended receiver's private key.

#### 17.9.4.2 Redeem Request Message Format (NORMATIVE)

The redeem request is sent to the SAME validators that witnessed the sender's transaction. The request payload:

```rust
struct RedeemRequest {
    /// The cheque bundle (k ValidatorCheques)
    cheque_bundle: ChequeBundle,
    
    /// Receiver's public key
    receiver_pk: Vec<u8>,
    
    /// Receiver's authorization signature (see 17.9.4.1)
    receiver_sig: Vec<u8>,
    
    /// Receiver's current wallet state
    current_state: ReceiverState,
}

struct ReceiverState {
    /// Receiver's public key
    public_key: Vec<u8>,
    
    /// Current balance (atoms)
    balance: u64,
    
    /// Current wallet sequence number
    wallet_seq: u64,
    
    /// Current state ID (32 bytes)
    state_id: [u8; 32],
}
```

**Redeem Response** (from each validator):

```rust
struct RedeemResponse {
    success: bool,
    request_id: String,
    
    /// Witness signature for the redeem (same structure as witness sig)
    witness_signature: Option<WitnessSig>,
    
    /// New state ID for the receiver after balance credit
    produced_state_id: Option<[u8; 32]>,
    
    /// Error details (if failed)
    error: Option<String>,
    rejection_code: Option<String>,
}
```

**Redeem uses S-ABR via serial witness accumulation** — identical to the witness (send) path. Receiver selects validators with ≥2 overlap from their last receipt. The client MUST send redeem to validators sequentially: validator 1 produces a signature, validator 2 receives validator 1's signature and produces its own, validator 3 (the k=3 validator) receives both prior signatures and creates the FACT link. Redeem MUST NOT be sent in parallel — parallel sends cause each validator to commit state independently, and if one validator times out, the partial commit creates an unconfirmed FACT link (scar) on the validators that did commit, while the client has no valid k=3 receipt. This is the same serial S-ABR flow as witness production (§17.4). [ERRATA v2.11.14-beta4: Previously stated "MAY be sent in parallel" — corrected after soak test v2 discovered that parallel redeem causes FACT scars under load when one of three validators times out.]

#### 17.9.4.3 Supplemental Registration — Lost-ACK Recovery (NORMATIVE)

A registration succeeds at the validator layer (k=3 cheque issued, validators' stored state advanced) before the Nabla `/register` call. If the Nabla register fails — network drop, lost ACK on the return path, transient writer unavailability — the FACT link is scarred (`nabla_confirmation: None`) and the cheque is still cryptographically valid. The protocol requires a supplemental-registration mechanism to recover the scar without re-running the witness round.

**Nabla-side: idempotent retry (NORMATIVE).**

Nabla's register handler MUST treat a retry with `(wallet_id, txid, new_state)` matching an already-applied transition as **idempotent**:

```
IF tx_hash != [0u8; 32]
   AND smt.get_wallet_by_txid(tx_hash) == Some(wallet_id)
   AND smt.get(wallet_id).current_state == new_state
THEN
    return ACK with the same fact_confirm_signature
    (no WAL append, no SMT update, no DEED charge, no double-ban)
```

This closes the lost-ACK recovery gap. Without it, a `RegisterAck` lost in transit on the return path leaves the FACT link permanently scarred even though Nabla's SMT, the validators' stored state, and the sender's wallet state are all consistent — the only inconsistency is the sender's lack of the `fact_confirm_signature` proof.

The fact_confirm_signature is **deterministic** over `(old_state, new_state)` via `crypto::fact_confirm_payload`, so the retry ACK is byte-equivalent to the original ACK (modulo `tick` which is informational on retry).

Reference implementation: `nabla/src/registration.rs::process_registration` step 5d (the idempotent-retry detection branch, between txid double-spend detection and the state-mismatch check).

**Client-side: pending registrations + retry policy (NORMATIVE).**

When a `send()`, `redeem()`, or `heal()` returns from witnessing with the k=3 receipt assembled but the subsequent Nabla register returns `Pending`, the SDK MUST:

1. **Persist** a `PendingRegistration` entry capturing `(txid, old_state, new_state, witness_sigs, is_genesis_claim, created_at)` to wallet storage.
2. **Return** a non-fatal status to the caller indicating the underlying operation succeeded but the Nabla anchor is deferred (`registration: "pending"` on `SendResult` / `RedeemResult`).
3. **Auto-retry** the pending list at the start of every subsequent `send()` / `redeem()` / `heal()` operation, in chronological order (oldest first). Stop on first transient failure — later entries cannot register before earlier ones (Nabla's SMT advances monotonically). Successful entries are dropped from the pending list and their corresponding FACT chain link's `nabla_confirmation` is populated.
4. **Expose** an explicit `wallet.complete_registration(txid)` (SDK YP §11) for client-initiated supplemental registration — useful when the front-end detects a scarred link and wants to retry immediately rather than wait for the next outbound op.

The idempotent-retry semantics above guarantee that the auto-retry succeeds for the lost-ACK case (Nabla still has the record). For the case where the retry's `old_state` legitimately mismatches Nabla's stored state (e.g., a genuine consensus divergence rather than a lost ACK), the registration returns `StateMismatch[SMT_VS_REG]` and the recovery path is `wallet.heal()` (CLARA TX_HEAL), not further register retries.

**Why supplemental registration is per-operation, not per-genesis.** The `fund_genesis` path (§17.11) uses a synchronous retry loop (~15s worst case) because a stuck genesis claim has no fallback. Normal `send()` MUST NOT block: the cheque is already cryptographically valid and delivered to the receiver, so the sender's UX should not wait on an asynchronous Nabla register. Supplemental registration is the asynchronous recovery channel for the steady-state case.

**Verification of supplementally-applied `nabla_confirmation` (NORMATIVE).**

A supplemental register that succeeds returns a `NablaConfirmation` which the SDK writes into the previously-scarred FACT link's `nabla_confirmation` field (matched by `tx_id`). The protocol's safety story for this asynchronous, client-driven mutation rests on three independent layers:

1. **Nabla-side full re-verification before idempotent ACK.** A retry passes through `process_registration` steps 5 + 5b BEFORE the idempotent short-circuit at step 5d. That is:
   - All k=3 validator Ed25519 signatures are re-verified against the deterministic `receipt_sign_payload(wallet_id, consumed_state_id, produced_state_id, tick)`.
   - Each validator's execution proof is re-verified — STARK receipt in ZKP mode, DMAP attestation with CoreID anchor + validator-pk binding in dev mode. These proofs cryptographically attest "Core was run and returned `ValidationResult::Accept` producing this exact `produced_state_id`."
   - Only after both pass does step 5d return the idempotent ACK. A retry cannot smuggle invalid signatures or forged proofs.

2. **Core re-verification of `nabla_confirmation` on every subsequent send.** `verify_fact_link` (`core/logic/src/fact.rs:386-411`) runs inside Core's CL2 mode for every link in the sender's `fact_chain`. For each link that has a `nabla_confirmation`:
   - Empty `nabla_signature` or zero `nabla_node_id` → `FactInvalidSignature` (defense against placeholder/forged structures).
   - The signed payload is recomputed from the link's own fields:
     ```
     tx_hash  = BLAKE3("AXIOM_TXHASH" || previous_state_id || new_state_id)
     payload  = BLAKE3("AXIOM_FACT_CONFIRM" || tx_hash || new_state_id)
     ```
   - `verify_ed25519(nabla_node_id, payload, nabla_signature)` MUST succeed.
   This guarantees that any FACT link reaching CL2 carries a signature math-checked against its claimed signer key, regardless of whether the link's conf was applied by the original register or by a supplemental retry.

3. **Trust-chain anchor for `nabla_node_id`.** Layer (2) verifies the signature math — "someone with the private key for this public key signed this payload" — but does not by itself prove the signer is an authorized Nabla node. That trust is anchored separately:
   - The SDK only ingests `NablaConfirmation` values returned by `register_with_nabla` over real TCP connections to configured Nabla addresses. A compromised SDK that synthesizes confs from fresh keypairs is out of scope for Core (Core trusts its caller).
   - The NBC (Nabla Birth Certificate) trust chain anchored at `NABLA_ROOT_AUTHORITY_PKS` (CL7 NBC Verification mode, `modes.rs:1120`) is invoked for CLARA attestations (`verify_nbc_for_clara_attestation`). It is NOT invoked on the regular `nabla_confirmation` per-link path.

**The boundary is explicit:** Core verifies that any `nabla_confirmation` carries a valid Ed25519 signature over the deterministic payload by the claimed `nabla_node_id`. Core does NOT, on this code path, verify that `nabla_node_id` is on the authorized list of Nabla nodes — that anchor is established at conf-ingestion time (SDK only accepts confs from real Nabla connections) and reinforced by the NBC trust chain on the adjacent CLARA path. Strengthening the per-link check to require an inline NBC bundle is a possible future hardening; it is tracked separately (see AXIOM_REPORT_KnownIssues.md).

#### 17.9.5 Cheque Properties

| Property | Description |
|----------|-------------|
| **Guaranteed funds** | 3 sigs prove the amount is valid and reserved |
| **Never expires** | Cheque remains valid indefinitely |
| **One-time use** | Each cheque can only be redeemed once |
| **Order-independent** | Multiple cheques can be redeemed in any order |
| **Offline-friendly** | Receiver can collect cheques offline, redeem later |

**Cheque Non-Expiry Rule:** Cheques never expire. Money has left the sender's wallet at witness time. The cheque represents a binding obligation from the sender's validators. This follows the cashier's cheque (bank cashier's cheque) model — once issued, the obligation stands regardless of time elapsed.

#### 17.9.6 Multiple Cheque Redemption

When receiver has multiple pending cheques, they can be redeemed in any order:

```
Initial: Receiver balance = 10

Pending cheques:
+ Cheque A: +10 (from V_A, V_B, V_C)
+ Cheque B: +5  (from V_D, V_E, V_F)
+ Cheque C: +20 (from V_G, V_H, V_I)
```

**Scenario A: Redeem in order A -> B -> C**

```
Cheque A: base=10,  +10 -> new_balance=20  *... COMPLETE
Cheque B: base=20,  +5  -> new_balance=25  *... COMPLETE
Cheque C: base=25,  +20 -> new_balance=45  *... COMPLETE

Final balance: 45
```

**Scenario B: Redeem in order B -> C -> A**

```
Cheque B: base=10,  +5  -> new_balance=15  *... COMPLETE
Cheque C: base=15,  +20 -> new_balance=35  *... COMPLETE
Cheque A: base=35,  +10 -> new_balance=45  *... COMPLETE

Final balance: 45
```

**Key invariant:** Regardless of redemption order, final balance is always the same (sum of initial + all cheques).

#### 17.9.7 Handling Redemption Delays

If a cheque redemption is delayed (e.g., validator offline), other cheques can proceed:

```
Initial: balance = 10

Cheque A: +10 (V_C offline, cannot complete)
Cheque B: +5
Cheque C: +20

Processing:
+ Cheque A: PENDING (V_C offline)
+ Cheque B: base=10,  +5  -> 15  *... COMPLETE
+ Cheque C: base=15,  +20 -> 35  *... COMPLETE
+ (V_C comes back online)
+ Cheque A: base=35,  +10 -> 45  *... COMPLETE

Final balance: 45
```

**Important:** When retrying a delayed cheque, the base must be the CURRENT validated balance, not the original base.

#### 17.9.8 Invalid Redemption Attempts

Validators reject redemptions with incorrect base:

```
Receiver's actual validated balance: 10

Cheque B attempts: base=20, +5 -> expect 25
                   + REJECTED
                   "Current balance is 10, not 20"

Correct attempt:   base=10, +5 -> expect 15
                   *... ACCEPTED
```

#### 17.9.9 Cheque Model Summary

```
+-----------------------------------------------------------------------+
|                         CHEQUE MODEL SUMMARY                          |
+-----------------------------------------------------------------------+
|                                                                       |
|  SENDER completes TX                                                  |
|       |                                                               |
|       +--> Sender state: FINALIZED (balance debited)                  |
|       |                                                               |
|       +--> Cheque issued to Receiver (3 validator sigs)               |
|                 |                                                     |
|                 |  (cheque is valid, funds guaranteed)                |
|                 |                                                     |
|                 v                                                     |
|            RECEIVER holds cheque                                      |
|                 |                                                     |
|                 |  (can redeem anytime, any order)                    |
|                 |                                                     |
|                 v                                                     |
|            RECEIVER redeems: cheque + current_balance                 |
|                 |                                                     |
|                 v                                                     |
|            Validators verify + sign new state                         |
|                 |                                                     |
|                 v                                                     |
|            RECEIVER state: FINALIZED (balance credited)               |
|                                                                       |
+-----------------------------------------------------------------------+
```

**Design philosophy:** This model separates "proof of payment" (cheque issuance) from "receipt of funds" (cheque redemption), enabling asynchronous operation while maintaining cryptographic guarantees.

#### 17.9.10 ValidatorCheque & ChequeBundle Data Structures

**ValidatorCheque** is the atomic unit of payment proof. Each sender-side validator produces one when witnessing a transaction. The receiver must collect k of these (from k different validators) to form a ChequeBundle for redemption.

```rust
pub struct ValidatorCheque {
    /// Transaction ID this cheque is for (32 bytes)
    pub txid: [u8; 32],
    
    /// Validator's unique identifier, derived from VBC (32 bytes)
    pub validator_id: [u8; 32],
    
    /// Validator's Ed25519 public key (32 bytes)
    pub validator_pk: Vec<u8>,
    
    /// Validator's signature over cheque commitment (64 bytes)
    /// V2: BLAKE3("AXIOM_CHEQUE_V2" || txid || state_hash || produced_state_id || receiver_wallet_id || amount || epoch)
    /// V3: BLAKE3("AXIOM_CHEQUE_V3" || ... || dmap_input_hash || dmap_output_hash)
    /// V3 used when dmap_input_hash is non-zero; V2 for backward compat.
    pub signature: Vec<u8>,
    
    /// Execution proof (deterministic or ZKP)
    pub execution_proof: Vec<u8>,
    
    /// Validator Birth Certificate bundle (full chain to genesis)
    /// Core verifies SPHINCS+ chain back to genesis root keys.
    pub vbc_bundle: Option<VBCProofBundle>,
    
    /// Carrier type: how to reach this validator
    /// Values: "maildir", "email", "swift", "https"
    pub carrier_type: String,
    
    /// Carrier address: endpoint for this validator
    /// e.g., "validator-1@axiom", "AXIOMVAL1XXX"
    pub carrier_address: String,
    
    /// Sender's wallet_id (for reference/audit)
    pub sender_wallet_id: String,
    
    /// Receiver's wallet_id (who can redeem this)
    pub receiver_wallet_id: String,
    
    /// Amount in atoms
    pub amount: u64,
    
    /// Payment reference string
    pub reference: String,
    
    /// Transaction epoch
    pub epoch: u64,
    
    /// When this cheque was created (unix timestamp)
    pub created_at: u64,
    
    /// State hash from validator's witness computation
    pub state_hash: [u8; 32],
    
    /// Produced state ID (sender's new state after this tx)
    pub produced_state_id: [u8; 32],
    
    /// Sender's FACT chain — money provenance (YPX-001 §1.6)
    /// Each validator independently attaches the sender's full FACT chain.
    /// All 3 cheques carry the same chain (redundant for survivability).
    /// Core verifies chain integrity at redeem time (CL5).
    /// The FACT chain is NOT included in the cheque signature commitment —
    /// it is transport data for provenance verification, not transaction data.
    pub sender_fact_chain: Option<FactChain>,

    /// ZKP nonce for anti-replay (ZKP-mode only)
    #[serde(default)]
    pub zkp_nonce: Option<[u8; 32]>,

    /// Proof type: 0=ZKP (STARK), 1=DMAP (memory attestation)
    #[serde(default)]
    pub proof_type: u8,

    /// DMAP input hash — independently computed from PublicInputs at proof time (v2.11.3)
    /// Used by receiver to verify DMAP attestation against non-tautological reference.
    /// Zero = old cheque format (falls back to attestation's own hashes).
    #[serde(default)]
    pub dmap_input_hash: [u8; 32],

    /// DMAP output hash — independently computed from PublicOutputs at proof time (v2.11.3)
    #[serde(default)]
    pub dmap_output_hash: [u8; 32],

    /// YPX-002 §3.2 — sender's designated sticky Nabla node.
    /// Unsigned advisory routing hint, stamped at witness issuance from
    /// the sender's witness request. Used by the receiver as position 0
    /// of the §4.6 verification triplet (sticky + 2 cross-branch random).
    /// None on first-ever TX from a fresh wallet — receiver falls back
    /// to 3 cross-branch random. Not covered by the cheque signature.
    #[serde(default)]
    pub nabla_hint: Option<NablaHint>,

    /// YPX-002 §4.6 — sender's raw Ed25519 wallet public key (32 bytes).
    /// This is the value Nabla's SMT is keyed on (the same value the
    /// sender passes as `wallet_pk` to `/register`), which the receiver
    /// needs to query `/query?wallet_pk=…` during §4.6 verification. The
    /// email-format `sender_wallet_id` above is NOT a valid Nabla
    /// lookup key — receivers that try to derive one from it will fail.
    /// Stamped by Lambda at witness issuance from `transaction.client_pk`.
    /// Unsigned advisory (not covered by AXIOM_CHEQUE_V3 commitment),
    /// optional with `#[serde(default)]` so pre-§4.6 cheques still
    /// deserialize. A client that receives a cheque with `sender_wallet_pk =
    /// None` MUST refuse to run §4.6 rather than guess — it means the
    /// issuing Lambda is older than the §4.6 change.
    #[serde(default)]
    pub sender_wallet_pk: Option<[u8; 32]>,
}
```

**DMAP hash binding (v2.11.3, GAP-B fix):** At witness time, the sender's validator independently computes `input_hash = BLAKE3(serialize(PublicInputs))` and `output_hash = BLAKE3(serialize(PublicOutputs))`. These hashes are stored in the cheque and covered by the cheque signature (V3 commitment). At redeem time, the receiver's validator uses the cheque's hashes (not the attestation's own hashes) when calling `verify_dmap_attestation()`. This prevents a malicious sender-side validator from reusing a valid attestation from a different TX. Old cheques with zero hashes fall back to V2 behavior.

**FACT chain in cheques (YPX-001 §1.6):** Each ValidatorCheque independently carries the sender's full FACT chain. This is the money's provenance — a cryptographic trail from genesis to the current transaction. All 3 cheques from sender's 3 validators carry the same chain (redundant for survivability). Core verifies chain integrity (continuity, witness signatures, depth) at redeem time but does NOT reject scarred chains — the receiver already consented via the scar-passcode mechanism (YPX-001 §1.5.1) at send time.

**Client-side triple-verification (RECOMMENDED, not protocol-enforced):** Since the receiver collects 3 independent copies of the sender's FACT chain (one from each validator), client implementations MAY cross-verify that all 3 copies are identical. A mismatch indicates validator corruption or tampering and the client SHOULD reject the cheques. This is a client-level security feature, not a protocol rule — Core does not enforce it.

**ChequeBundle** is the redemption unit. The receiver assembles k ValidatorCheques into a bundle and presents it to their validators.

```rust
pub struct ChequeBundle {
    /// The k cheques (one from each of sender's validators)
    pub cheques: Vec<ValidatorCheque>,
    
    /// Convenience copy of sender's FACT chain, extracted from first cheque.
    /// Authoritative source: ValidatorCheque.sender_fact_chain
    /// Core CL5 reads this field for verification.
    pub fact_chain: Option<FactChain>,
}
```

**Consistency invariant:** All cheques in a bundle MUST have the same `txid`, `receiver_wallet_id`, and `amount`. The `verify_consistency()` method enforces this.

**Lifecycle:**

```
Sender witnesses TX on k validators
    ├── V1 produces ValidatorCheque_1  ──┐
    ├── V2 produces ValidatorCheque_2  ──┤ Client collects k cheques
    └── V3 produces ValidatorCheque_3  ──┘
                                          │
                                          v
                              ChequeBundle { cheques: [VC1, VC2, VC3] }
                                          │
                              Receiver signs authorization (17.9.4.1)
                                          │
                                          v
                              Redeem request to receiver's validators
```

### 17.10 Sequential Asymmetric Blind Refill (S-ABR)

> **The Most Critical Security Gate in AXIOM**
> 
> S-ABR is the foundational mechanism that makes trustless state transitions possible. Without it, the entire AXIOM architecture cannot function. Every transaction in the system must pass through this gate.

#### 17.10.1 Abstract

The Sequential Asymmetric Blind Refill (S-ABR) is a state-transition protocol designed for org-less environments. It eliminates double-spending and state-rollbacks by shifting the burden of "State Memory" to a historical validator set while maintaining the Client Core as the final cryptographic arbiter.

**Key Innovation:** S-ABR transforms the double-spend problem from a "trust problem" into a "math problem" -- where the only way to cheat is to break the laws of cryptographic probability.

**Design Simplification (v1.9.10):** The quantitative overlap requirements (Section 17.3.1) eliminate the need for a separate "Hashed Continuity Proof" (HCP) structure. The ≥2 overlapped validator requirement for k=3 mathematically guarantees that any two concurrent transactions share at least one validator, making standard witness signatures sufficient for continuity proof.

#### 17.10.2 The Overlap-Guaranteed Protocol

To ensure physical continuity, a transaction requires participation from multiple overlapped validators as defined in Section 17.3.1.

**Overlap Requirements (from Section 17.3.1.1):**

| Tier (k) | Minimum Overlap | From Previous | New |
|----------|----------------|---------------|-----|
| k=3 | ≥2 | 2 of 3 | 1 of 3 |
| k=4 | ≥3 | 3 of 4 | 1 of 4 |
| k=5 | ≥3 | 3 of 5 | 2 of 5 |

**Why ≥2 Overlap Eliminates the Need for HCP:**

With overlap ≥1 only (original design), a client could send concurrent transactions to *different* overlapped validators, creating disjoint witness sets that don't detect the double-spend. This required an explicit "Hashed Continuity Proof" (HCP) to link transactions.

With overlap ≥2 (current design), any two valid witness sets MUST intersect:

```
prev_witnesses = {V1, V2, V3}
Required overlap = 2

Possible 2-combinations: {V1,V2}, {V1,V3}, {V2,V3}

Any two combinations MUST intersect:
  {V1,V2} ∩ {V1,V3} = {V1} ✓
  {V1,V2} ∩ {V2,V3} = {V2} ✓
  {V1,V3} ∩ {V2,V3} = {V3} ✓

Conclusion: Impossible to construct two disjoint witness sets
→ Shared validator detects double-spend
→ HCP structure is redundant
```

**Standard witness signatures provide sufficient proof** because:
1. Witness signature proves validator approved the transaction
2. VBC proves validator is a real network member
3. Overlap requirement guarantees intersection detection
4. State hash is deterministic and verifiable

#### 17.10.3 Validator Core Decision Logic

**Core/Lambda Separation:**

| Component | Responsibility |
|-----------|----------------|
| **Core** | Strip balance (if overlapped), verify Hash_A == Hash_B, validate rules |
| **Lambda** | Refill balance from history, process transaction logic, sign witness |

Core is **stateless**. It does not know historical balances. Core only:
1. Decides to strip balance (if overlapped)
2. Passes stripped payload to Lambda
3. Receives refilled payload from Lambda
4. Computes Hash_B and compares with Hash_A (from original payload)

**Hash_A vs Hash_B:**
- **Hash_A**: Computed by client, included in payload, NEVER changes
- **Hash_B**: Computed by Core from Lambda's refilled balance, compared with Hash_A

```
┌─────────────────────────────────────────────────────────────┐
│                 CORE DECISION LOGIC                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Check: Am I in prev_receipts? (Am I Overlapped?)          │
│                                                             │
│      YES (Overlapped Validator)                            │
│      ├─ Strip declared balance from payload                │
│      ├─ Pass to Lambda (balance stripped)                  │
│      ├─ Lambda refills balance from history                │
│      ├─ Lambda processes transaction, returns to Core      │
│      ├─ Core computes Hash_B from refilled balance         │
│      ├─ Core compares: Hash_A == Hash_B?                   │
│      │     Match → valid                                   │
│      │     Mismatch → REJECT                               │
│      └─ Return: validation result to Lambda for signing    │
│                                                             │
│      NO (New Validator)                                    │
│      ├─ Use declared balance (not stripped)                │
│      ├─ Validate transaction with declared balance         │
│      ├─ Compute Hash_B, verify Hash_A == Hash_B            │
│      └─ Return: validation result to Lambda for signing    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Key Points:**
- Core determines overlap status by checking if own pubkey is in prev_receipts
- Core is stateless - Lambda is the "historian" that knows balances
- Hash_A stays in payload forever (client's commitment)
- Hash_B is computed on-the-fly and discarded after comparison
- Lambda handles signing (Core does not touch private keys)

#### 17.10.4 Complete Transaction Flow

**Architecture Reference:** See Section 16.8 for detailed Core/Lambda relationship.

**Two-Payload Approach:**
- To Overlapped Validators: payload WITHOUT balance (will be refilled)
- To New Validators: payload WITH balance + overlapped signatures

**Sequential Requirement:** Client MUST send to overlapped validators FIRST, then to new validators with the collected signatures.

```
Client Wallet 
    │
    ▼
Client Core
    ├─ Identify prev_receipts validators
    ├─ Select ≥2 overlapped + remaining new validators (for k=3)
    ├─ Compute Hash_A = SHA3(balance + salt + tx_data)
    └─ Prepare payloads
    │
    ▼
═══════════════════════════════════════════════════════════════
  PHASE 1: SEND TO OVERLAPPED VALIDATORS (balance stripped)
═══════════════════════════════════════════════════════════════
    │
    ├─────────────────────────────┐
    ▼                             ▼
Validator V_A (Overlapped)    Validator V_B (Overlapped)
    │                             │
    ▼                             ▼
Gateway → Core (V_A)          Gateway → Core (V_B)
    ├─ Am I overlapped? → YES     ├─ Am I overlapped? → YES
    ├─ Strip balance              ├─ Strip balance
    ├─ Pass to Lambda             ├─ Pass to Lambda
    │                             │
    ▼                             ▼
Lambda (V_A)                  Lambda (V_B)
    ├─ Refill balance (500)       ├─ Refill balance (500)
    ├─ Process transaction        ├─ Process transaction
    └─ Return to Core             └─ Return to Core
    │                             │
    ▼                             ▼
Core (V_A)                    Core (V_B)
    ├─ Hash_B = SHA3(500+...)     ├─ Hash_B = SHA3(500+...)
    ├─ Hash_A == Hash_B? → YES    ├─ Hash_A == Hash_B? → YES
    └─ Return: valid              └─ Return: valid
    │                             │
    ▼                             ▼
Lambda (V_A)                  Lambda (V_B)
    └─ Sign witness → sig_V_A     └─ Sign witness → sig_V_B
    │                             │
    └─────────────┬───────────────┘
                  │
                  ▼
            Client Core
            ├─ Collect sig_V_A, sig_V_B
            │
            ▼
═══════════════════════════════════════════════════════════════
  PHASE 2: SEND TO NEW VALIDATORS (balance included + sigs)
═══════════════════════════════════════════════════════════════
            │
            ▼
Validator V_C (New)
    │
    ▼
Gateway → Core (V_C)
    ├─ Am I overlapped? → NO
    ├─ Check: ≥2 sigs from prev_receipts?
    │     sig_V_A from V_A in prev_receipts? → YES
    │     sig_V_B from V_B in prev_receipts? → YES
    │     Count = 2 ≥ 2? → YES ✓
    ├─ Validate with declared balance
    ├─ Hash_B = SHA3(declared_balance+...)
    ├─ Hash_A == Hash_B? → YES
    └─ Return: valid
    │
    ▼
Lambda (V_C)
    └─ Sign witness → sig_V_C
    │
    ▼
            Client Core
            ├─ Collect sig_V_C
            ├─ Total: sig_V_A, sig_V_B, sig_V_C (k=3) ✓
            └─ Transaction complete
```

**Why Sequential?**

New validators need proof that overlapped validators already approved:
- Without overlapped signatures, new validator cannot verify S-ABR was performed
- Overlapped signatures prove: "We verified Hash_A matches our historical balance"
- New validator can then trust the declared balance matches Hash_A

**Double-Spend Detection:**

If client attempts concurrent double-spend:
```
TX_A: 60 → Bob    (sent to V_A, V_B, V_X)
TX_B: 60 → Carol  (sent to V_A, V_C, V_Y)  ← concurrent

V_A receives BOTH (guaranteed by ≥2 overlap)
V_A processes TX_A first → marks state consumed
V_A rejects TX_B → DOUBLE_SPEND error

Attack BLOCKED ✓
```

#### 17.10.5 Core Principles

* **Overlap Guarantee:** ≥2 overlapped validators (k=3) ensures any concurrent transactions share at least one validator
* **Sequential Flow:** Overlapped validators MUST process first; new validators require their signatures
* **Core/Lambda Separation:** Core strips and verifies hash; Lambda refills balance and signs
* **Hash_A Immutability:** Hash_A in payload NEVER changes - it's the client's commitment
* **Stateless Core:** Core computes Hash_B on-the-fly, compares with Hash_A, discards
* **Trustless Design:** Client cannot lie about balance - Hash_A locks the value
* **Validator-Side Adjudication:** The **Validator Core** compares $Hash_{A}$ vs $Hash_{B}$. Client cannot bypass this verification
* **Trustless Design:** Client sends identical payloads. Security does not depend on Client honesty
* **Standard Witness Signatures:** No special "continuity proof" structure needed -- witness signatures + VBC are sufficient

#### 17.10.5.1 Mandatory Storage Write-Verify (NORMATIVE)

S-ABR is the central beam of the entire protocol. Every subsequent transaction from a wallet — and every cheque the wallet has issued for receivers to redeem — depends on the witnessing validator having a **persisted** state record matching the new state the validators just signed. A silent storage write failure at this seam produces the "overlap-but-no-stored-record" condition: validators report a new state to the client, the client and other validators advance, but the lagging validator's local DB never actually committed the row. The wallet's next operation then fails mysteriously when those validators are queried — they have no record of the state they "signed."

To eliminate this failure class, validators MUST implement **write-verify** at the storage layer: every wallet state commit performs the INSERT, then immediately reads the row back and compares `state_id` + `wallet_seq` + `balance` against what was written. Only when all three match does the commit return success. Any divergence (no row found, field mismatch) MUST return a storage error to the consensus layer, which propagates back to the client. The TX is then retried (or recovered via `wallet.heal()`) instead of silently advancing one validator's view while the other validators record the state correctly.

Reference implementation: `lambda/src/storage.rs::set_wallet_state` (the boxed comment block in that function documents the rationale and warns future contributors against removing the verify pass for "performance" reasons — it is a correctness gate, not an optimization).

**Cost:** one extra indexed SELECT per state mutation (~0.3 ms). Negligible against the witness round (multi-second). Non-negotiable for correctness.

#### 17.10.5.2 Canonical Reject-Code Precedence (NORMATIVE)

A transaction or redeem that violates more than one validation invariant simultaneously can be rejected by any of the failing invariants — and on different validators a different invariant may fire first depending on gossip lag, local cache hits, and the order checks are wired in the consensus pipeline. Without a canonical precedence, two honest validators rejecting the same TX for genuinely-the-same reason can return *different* error codes, fracturing incident triage and weakening the audit trail.

**Rule.** When multiple reject conditions are simultaneously true, every validator MUST emit the reject code from the **highest-priority** failing invariant according to the precedence below. Lower-priority checks MAY still execute (defense in depth) but their reject codes MUST NOT be returned when a higher-priority check would also have failed.

**Precedence (highest to lowest):**

1. **Structural invalidity** — wrong field shape, malformed address, unsupported algorithm, zero/dust amount. (`InvalidStateId`, `MalformedAddress`, `InvalidWalletId`, `ZeroAmount`, `DustAmount`, `UnsupportedSignatureAlgorithm`)
2. **Trust-anchor failures** — VBC chain doesn't trace to a root authority key, VBC expired or not-yet-valid, NBC trust-anchor verification failed. (`VBCRootKeyMismatch`, `VBCExpired`, `ChequeClaimProofUntrusted`)
3. **Replay / double-spend** — explicit replay-attack signals from authoritative sources. The most authoritative source wins:
   - **3a.** Nabla txid attestation says `REDEEMED` (`TxidAttestationRedeemed`)
   - **3b.** Cheque already redeemed locally (`ChequeAlreadyRedeemed`)
   - **3c.** Cheque-claim proof missing or invalid (`ChequeClaimProofMissing`, `ChequeClaimProofInvalidSig`, `ChequeClaimProofExpired`)
4. **State consistency** — defense-in-depth state checks that fire when 3a/3b/3c are silent but local state has nonetheless advanced. (`E_LAMBDA_RECEIVER_STATE_DRIFT`, `SABRStateChainMismatch`, `SABRHashMismatch`, `InvalidWalletSeq`)
5. **Cryptographic identity** — Ed25519 or Dilithium signature verification failure. (`InvalidClientSignature`, `InvalidWitnessSignature`, `InvalidChequeSignature`)
6. **Cheque bundle structure** — k below threshold, internal inconsistency. (`InsufficientCheques`, `InconsistentChequeBundle`, `RedeemSenderAnchorMissing`)
7. **Proof-of-execution** — DMAP / ZKP verification failure. (`InvalidExecutionProof`, `ProgramDigestMismatch`)
8. **Conservation** — balance and supply checks. (`InsufficientBalance`, `ConservationViolation`)

**Why this order.** Replay/double-spend (3) outranks state-consistency (4) because the replay signal is *causal*: when an attacker replays a TX, both 3 *and* 4 are simultaneously true — but 3 explains *what happened* (the replay), while 4 only explains *what we observed* (the state moved). Two validators looking at the same replay should both report "this is a replay" rather than one reporting "replay" and the other reporting "state drifted." Likewise, structural invalidity (1) outranks crypto (5) because there's no point verifying a signature on a malformed field. Trust-anchor (2) outranks crypto-identity (5) because an unsigned VBC chain invalidates the identity regardless of what was signed.

**Implementation discipline.** Implementations that pass through multiple layers (e.g., Lambda pre-CL5 checks followed by Core CL5) MUST ensure the higher-priority check fires *at the earliest layer that can see it*. Concretely:

- If Lambda has the Nabla txid attestation in the request, it MUST short-circuit on `attestation.status == "REDEEMED"` *before* its receiver-state defense-in-depth check (otherwise a validator whose local receiver-state has gossip-advanced ahead of peers will emit `E_LAMBDA_RECEIVER_STATE_DRIFT` while peers still emit `E_TXID_ATTESTATION_REDEEMED`).
- Core CL5 retains an independent check on the same status field — defense in depth. Both must stay in sync; changing one without the other re-fractures the reject codes.

**Reference implementations.** Lambda fast-path: `lambda/src/consensus.rs::process_redeem_request` (the boxed "Canonical reject-code precedence" comment block immediately after the txid-attestation debug log). Core CL5 companion: `core/logic/src/modes.rs` (the `match att.status.as_str()` block in the cheque-claim-proof path).

**Observability.** The 2026-05-15 50-wallet 1-hour adversarial soak (run `s2r38036`) recorded a single instance of heterogeneous reject codes (`E_LAMBDA_RECEIVER_STATE_DRIFT` from one validator alongside `E_TXID_ATTESTATION_REDEEMED` from two others, on the same blocked replay). The TX was still correctly blocked 0/3, but the divergence motivated this section. A future soak SHOULD assert that all three validator-reject codes from a single TX redeem match.

#### 17.10.5.3 Same-Tick Redeem Block — Nabla Commit-Tick Attestation (NORMATIVE)

Every successful state-registration at a Nabla writer returns a signed acknowledgment that includes the writer's TARDIS tick at the moment the state landed in the SMT. The Ed25519 signature in `NablaConfirmation.nabla_signature` covers this tick (payload domain `AXIOM_FACT_CONFIRM_V2`, see `nabla/src/crypto.rs::fact_confirm_payload`). The SDK persists the tick as `NablaConfirmation.committed_at_tick` on the FACT link.

**Rule.** Core CL5 redeem MUST reject any redeem whose sender FACT chain tip carries a `NablaConfirmation` with `committed_at_tick >= inputs.current_tick`. Equivalently: a receiver can only redeem at TARDIS tick strictly greater than the tick at which the sender's commit landed. Minimum gap: 1 tick.

**Why.** Without this rule, a sender can register a state and a receiver can claim against that state within the same TARDIS tick — before the sender's commit has had any chance to gossip through Nabla's mesh. Some Nabla nodes will not have seen the state-update when the receiver's claim-registration arrives, and the receiver's view of the sender's state is brittle. Forcing a one-tick gap serializes the receiver behind at least one round of mesh propagation. This is not "wait for full propagation"; it is the minimum mechanical gap that lets gossip *start*.

**Scarred-link exemption.** A FACT link with no `NablaConfirmation` (a scar — Nabla was unreachable at register time) has no `committed_at_tick` and is exempt from this check. Ark-mode wallets operating offline continue to scar links and chain forward without this gate ever firing. The check is a positive-evidence requirement on confirmed links only; it cannot block partition-tolerant operation.

**Signing payload (V2).**
```
payload = BLAKE3(
    "AXIOM_FACT_CONFIRM_V2"
    || BLAKE3("AXIOM_TXHASH" || old_state || new_state)
    || new_state
    || committed_at_tick.to_le_bytes()
)
```
The writer's Ed25519 signature in `NablaConfirmation.nabla_signature` MUST verify against this payload. The V1 payload (no tick) is no longer valid on the wire; pre-mainnet there is no compatibility shim (CLAUDE.md §13).

**Precedence slot.** This rule lands in tier 3 of §17.10.5.2 (replay/double-spend) as a predecessor-proof failure, before tier 4 (state consistency).

**Reference implementations.** Nabla writer signs the payload in `nabla/src/registration.rs::process_registration` and `nabla/src/bin/nabla_node.rs::fact_confirm_core`. SDK extracts the tick from `RegisterResponse.tick` (or `RegistrationAck.tick` for the TCP path) and writes it into `NablaConfirmation.committed_at_tick` in `sdk/client/src/nabla.rs::update_fact_chain_confirmation`. Core CL5 enforcement: `core/logic/src/modes.rs` immediately after `verify_fact_chain` returns Ok on the sender chain.

**Operator config.** None — the rule is hardcoded `>= 1 tick`. There is no `MIN_PROPAGATION_TICKS` knob; the single-tick floor is the minimum mechanical guarantee and does not benefit from being tunable.

#### 17.10.6 Validator State Records

Each Validator maintains records of transactions they have witnessed:

```
Validator Storage Record:
├─ tx_id: Transaction identifier
├─ state_id: State identifier  
├─ owner_pk: Client public key
├─ final_balance: Balance AFTER this transaction
├─ timestamp: When witnessed
└─ sig: Validator's signature over this state
```

**Critical:** Validators store `final_balance` -- the balance at the END of the transaction they witnessed. This enables balance refill when they become Overlapped Validators.

#### 17.10.7 Overlapped vs New Validators

| Type | Definition | Has History? | Action |
|------|------------|--------------|--------|
| **Overlapped** | In prev_receipts | Yes | Strip, refill, validate with historical balance |
| **New** | Not in prev_receipts | No | Validate using standard FACT chain verification; overlap guarantee ensures continuity. |

**Note:** For k=3, at least 2 MUST be Overlapped. The remaining validator(s) may be New.

#### 17.10.8 Security Analysis: Why S-ABR Eliminates Double-Spending

The Sequential Asymmetric Blind Refill (S-ABR) design effectively eliminates double-spending by combining three mechanisms:

**1. Quantitative Overlap Requirement (Section 17.3.1)**

The ≥2 overlap requirement mathematically guarantees that any two concurrent transactions share at least one validator:

```
For k=3, choosing 2 from {V1, V2, V3}:
  All possible pairs: {V1,V2}, {V1,V3}, {V2,V3}
  
  ANY two pairs intersect:
    {V1,V2} ∩ {V1,V3} = {V1}
    {V1,V2} ∩ {V2,V3} = {V2}
    {V1,V3} ∩ {V2,V3} = {V3}
    
  → At least one validator sees BOTH transactions
  → Double-spend detected and rejected
```

**2. Validator-Side State Tracking**

Each overlapped validator maintains historical balance records:
- First transaction processed → state marked "consumed"
- Second transaction with same prev_state → REJECTED

**3. Hash Consistency Verification**

```
Client declares: Balance = 1000, Hash_A = SHA3(1000 + salt)
Validator refills: Balance = 500 (from history)
Validator computes: Hash_B = SHA3(500 + salt)

Hash_A ≠ Hash_B → TRANSACTION REJECTED

Client cannot forge balance without breaking SHA3-256.
```

**Defense Summary Table:**

| Attack Vector | Defense Mechanism |
|---------------|-------------------|
| Concurrent Double-Spend | ≥2 overlap ensures shared validator detection |
| Validator Shopping | Client Core enforces overlap count per tier |
| State Rollback | Blind Refill reveals true balance from history |
| Hash Forgery | SHA3-256 collision resistance (2^256) |

#### 17.10.9 The Three Pillars of S-ABR Security

S-ABR security rests on three interlocking pillars. No single mechanism is sufficient alone.

**1. Mathematics (Cryptography)**

```
Hash collision resistance: P ≈ 1/2^256
Signature forgery: P ≈ 1/2^128 (Ed25519)
Combined: Cryptographically impossible
```

**2. Logic (Protocol Rules)**

```
Overlap requirement: ≥⌈(k+1)/2⌉ validators from prev_receipts
Set intersection: Any two valid witness sets MUST share ≥1 validator
State consumption: Once processed, state cannot be reused
```

**3. Game Theory (Incentives)**

```
Validator collusion cost: Stake forfeiture + reputation loss
Attack benefit: Limited (one double-spend)
Expected value: Negative (cost > benefit)
```

**Combined Guarantee:**

To successfully double-spend, an attacker must simultaneously:
1. Break SHA3-256 (mathematically impossible)
2. Corrupt ALL overlapped validators (requires ≥2 colluding validators)
3. Avoid detection by honest validators (impossible with intersection guarantee)

This creates **defense in depth** where compromising one layer still leaves the other two intact.

#### 17.10.9.1 OPEN ISSUE: Colluding Overlapped Validators Attack

**Status:** Under Investigation  
**Severity:** Medium  
**Added:** 2026-02-02

**The Attack:**

If ALL overlapped validators (≥2 for k=3) collude AND the client cooperates:

```
Scenario:
  - Alice has real balance: 500 atoms
  - Alice colludes with V1, V2 (both overlapped validators)
  - V1 and V2 store FAKE history: "Alice has 10,000 atoms"
  - Alice computes Hash_A from fake balance (10,000)
  - V1 refills 10,000 → Hash_B = Hash_A ✓
  - V2 refills 10,000 → Hash_B = Hash_A ✓
  - V3 (new validator) trusts overlapped signatures
  - ATTACK SUCCEEDS: Alice spends 10,000 atoms she doesn't have
```

**Why Current Defenses Are Insufficient:**

| Defense | Why It Fails in This Attack |
|---------|----------------------------|
| Hash verification | Hash_A computed from fake balance matches |
| ≥2 overlap | Both overlapped validators are colluding |
| State consumption | Fake state was never real, nothing to consume |
| ZKP execution proof | Core ran correctly on fake data |

**The Fundamental Problem:**

Core is stateless and trusts Lambda's refilled balance. If Lambda lies (and client's hash matches the lie), Core cannot detect the fraud. The only defense is having an HONEST overlapped validator who has REAL history.

**Potential Solutions Under Consideration:**

1. **VDF Gossip** - Validators gossip witnessed transactions with VDF proofs. Backdating fake history becomes impossible (VDF takes time). Forging requires no honest gossip observers.

2. **Cross-Validator History Queries** - Before accepting refilled balance, query other known validators for their history. Inconsistency reveals fraud.

3. **Merkle History Commitments** - Validators publish periodic Merkle roots of their witnessed transactions. Fake history requires forging Merkle proofs.

4. **Stake-Weighted History** - Weight balance refills by validator stake. Higher-stake validators' history is more trusted.

5. **Client-Side History Cache** - Clients maintain their own transaction history. Honest clients can detect validator lies.

**Current Mitigation:**

The attack requires:
- Client cooperation (malicious client)
- ALL overlapped validators colluding
- Consistent fake history across colluding validators
- No honest validators in the client's recent transaction history

For most users with legitimate transaction history involving honest validators, this attack is not feasible. The attack primarily threatens:
- New wallets with short history
- Wallets that exclusively use colluding validators

**Recommendation:**

This remains an open research problem. Multiple complementary solutions may be needed. Protocol MUST NOT rely on a single defense mechanism.

**Cross-Reference:** Future VDF Gossip specification (if implemented)

#### 17.10.10 Relationship to White Paper

**White Paper v2.28 establishes:**
> "Witness overlap requirement ensures chain of evidence continuity"

**Yellow Paper refinement:**
- Quantifies overlap: ≥2 for k=3, ≥3 for k=4/k=5
- Proves intersection guarantee mathematically
- Eliminates need for separate HCP structure
- Simplifies implementation while maintaining security

**This is specification refinement, not correction.** The White Paper principle is correct; the Yellow Paper provides executable thresholds.

#### 17.10.11 Implementation Notes

**For axiom-core.elf Implementers:**

Core is STATELESS. It does not access historical balances directly.

```rust
/// axiom-core.elf S-ABR validation (Overlapped Validator path)
fn validate_sabr_overlapped(
    tx: &Transaction,
    lambda_response: &LambdaResponse,  // Contains refilled balance
) -> Result<ValidationResult, ValidationError> {
    // Hash_A is in the original payload (client's commitment)
    let hash_a = &tx.declared_hash;
    
    // Lambda refilled the balance from history
    let refilled_balance = lambda_response.refilled_balance;
    
    // Core computes Hash_B from refilled balance
    let hash_b = compute_hash(refilled_balance, &tx.salt, &tx.tx_data);
    
    // Compare: Does refilled balance produce same hash as client claimed?
    if hash_a != &hash_b {
        return Err(ValidationError::HashMismatch {
            expected: hash_a.clone(),
            computed: hash_b,
        });
    }
    
    // Validate transaction rules with refilled balance
    validate_transaction_rules(tx, refilled_balance)?;
    
    Ok(ValidationResult {
        valid: true,
        am_overlapped: true,
    })
}

/// axiom-core.elf S-ABR validation (New Validator path)
fn validate_sabr_new(
    tx: &Transaction,
    overlapped_sigs: &[WitnessSignature],
) -> Result<ValidationResult, ValidationError> {
    // 1. Verify we have ≥2 signatures from prev_receipts validators
    let valid_overlapped_count = overlapped_sigs.iter()
        .filter(|sig| {
            tx.prev_receipts.iter().any(|r| r.witness_pk == sig.signer_pk)
                && verify_signature(sig)
        })
        .count();
    
    let required = get_required_overlap(tx.tier);  // 2 for k=3, 3 for k=4/5
    if valid_overlapped_count < required {
        return Err(ValidationError::InsufficientOverlappedSignatures {
            required,
            actual: valid_overlapped_count,
        });
    }
    
    // 2. Use declared balance (overlapped validators already verified it)
    let balance = tx.declared_balance;
    
    // 3. Verify Hash_A matches declared balance
    let hash_b = compute_hash(balance, &tx.salt, &tx.tx_data);
    if &hash_b != &tx.declared_hash {
        return Err(ValidationError::HashMismatch {
            expected: tx.declared_hash.clone(),
            computed: hash_b,
        });
    }
    
    // 4. Validate transaction rules
    validate_transaction_rules(tx, balance)?;
    
    Ok(ValidationResult {
        valid: true,
        am_overlapped: false,
    })
}
```

**For Lambda Implementers:**

Lambda is the "historian" that knows balances and signs witnesses.

```rust
/// Lambda processes S-ABR for overlapped validator
fn process_sabr_overlapped(
    tx: &Transaction,
    state_store: &StateStore,
) -> Result<LambdaResponse, LambdaError> {
    // 1. Refill balance from historical records
    let refilled_balance = state_store
        .get_balance(&tx.owner_pk, &tx.prev_state_id)
        .ok_or(LambdaError::NoHistoricalRecord)?;
    
    // 2. Process transaction logic
    let new_balance = refilled_balance
        .checked_sub(tx.amount)
        .ok_or(LambdaError::InsufficientBalance)?;
    
    // 3. Return to Core for hash verification
    Ok(LambdaResponse {
        refilled_balance,
        new_balance,
    })
}

/// Lambda signs witness after Core approves
fn sign_witness(
    tx: &Transaction,
    validator_private_key: &PrivateKey,
) -> WitnessSignature {
    let signing_payload = build_witness_payload(tx);
    let signature = sign(validator_private_key, &signing_payload);
    
    WitnessSignature {
        signer_pk: validator_private_key.public_key(),
        signature,
        timestamp: current_time(),
    }
}
```

**Key Separation Summary:**

| Step | Core | Lambda |
|------|------|--------|
| Check overlap status | ✓ | |
| Strip balance (if overlapped) | ✓ | |
| Refill balance from history | | ✓ |
| Process transaction logic | | ✓ |
| Compute Hash_B | ✓ | |
| Compare Hash_A == Hash_B | ✓ | |
| Validate transaction rules | ✓ | |
| Sign witness signature | | ✓ |
| Store state for future overlap | | ✓ |

#### 17.10.12 TransactionRecord Storage for S-ABR (CRITICAL)

**This section clarifies the critical storage requirement for S-ABR to work across the witness-cheque-redeem cycle.**

**Problem:** When a wallet receives funds via cheque redemption, their validators update the wallet's state. Later, when that wallet wants to SEND funds, S-ABR needs to look up the balance from the previous transaction.

**Solution:** During redeem processing, validators MUST store a TransactionRecord keyed by `produced_state_id`.

```
TransactionRecord {
    tx_id: [u8; 32],           // Transaction identifier
    produced_state_id: [u8; 32], // KEY for S-ABR lookup
    wallet_pk: Vec<u8>,        // Owner's public key
    balance_after: u64,        // Balance AFTER this transaction
    wallet_seq_after: u64,     // Sequence AFTER this transaction
    status: Pending/Confirmed,
}
```

**Storage Key:** `txrec:{produced_state_id}`

**Lookup Flow:**
1. Wallet receives 100 atoms via redeem → `produced_state_id = X`, `balance_after = 100`
2. Validator stores: `txrec:X` → TransactionRecord
3. Later, wallet sends 50 atoms → `consumed_state_id = X`
4. Validator (overlapped) looks up: `txrec:X` → finds balance = 100
5. S-ABR refills balance from record, ignoring client's `declared_balance`

**Why Client-Provided State Takes Priority in Redeem:**

During redeem, all validators must compute the SAME `new_state_id` to avoid divergence. The `new_state_id` depends on the receiver's current balance.

```
Problem: Validators may have different local views of receiver's balance
- V6 processed previous redeem → knows balance = 100
- V7 didn't process that redeem → doesn't know balance
- V8 didn't process that redeem → doesn't know balance

If each uses LOCAL state:
- V6 computes new_state_id with balance = 100
- V7 computes new_state_id with balance = 0 (first receive)
- V8 computes new_state_id with balance = 0 (first receive)
→ STATE DIVERGENCE!

Solution: Use CLIENT-PROVIDED current_state
- Client provides: { balance: 100, wallet_seq: 1, state_id: X }
- V6, V7, V8 all use this → compute same new_state_id
- state_id X cryptographically commits to balance — verified via S-ABR
```

**CRITICAL: S-ABR on Redeem — Validator Selection (v2.6.0)**

Any balance change requires S-ABR. The receiver is a wallet with state. When redeeming, the **client** must select validators that include ≥2 from the **receiver's** last receipt. Those overlapped validators already have the receiver's state in their local storage and verify `current_state` against their records — exactly as the witness path works.

The client does NOT send additional fields or proofs. The client **routes to the correct validators**. The validator's existing S-ABR logic handles verification:
- Overlapped validator has local state → strips client's declared balance, refills from own records, verifies hash
- Non-overlapped validator trusts overlapped validators' signatures
- First-time receiver (no prior receipt) → validators have no state → balance=0

**Implementation Rule:**
```rust
// In process_redeem_request:
let receiver_state = if let Some(ref client_state) = request.current_state {
    // Client provided state — S-ABR verified by validator selection
    // (≥2 validators from receiver's last receipt know the real balance)
    Some(client_state.clone())
} else {
    // No client state - try local (for first-time receivers)
    storage.get_wallet_state(&receiver_pk)?
};
```

**E2E Verification:**

This behavior was verified in E2E testing with 200 transactions and 0 mismatches:
- Receivers who previously received funds have `current_state` populated
- All validators use client-provided state → identical `new_state_id` computation
- No more STATE_ID DIVERGENCE errors


#### 17.10.13 Transaction Re-witnessing Policy (NORMATIVE)

**A validator MUST NOT reject a transaction solely because it has witnessed it before.**

If a client submits the same transaction (same consumed_state_id, same payload) to a validator that has already witnessed it, the validator MUST process it as if seeing it for the first time. The validator validates, signs, and returns a witness response following the same procedure as the initial request.

**Rationale:**

Partial consensus is a normal operating condition. A client may send a transaction to 3 validators but only receive 2 responses (network failure, timeout, validator crash). The client cannot complete the transaction (k=3 not reached) but 2 validators have already signed. The client must be able to re-submit to those 2 validators plus a fresh one to recover.

If validators rejected re-submissions, partial consensus would be unrecoverable without the client creating an entirely new transaction (new nonce, new state). This would waste network resources and complicate client recovery logic.

**Natural protection against double-spend:**

Re-witnessing the same transaction is NOT a double-spend risk because:

1. The `consumed_state_id` in the transaction identifies a specific wallet state
2. If the transaction completes (client uses the receipt for a subsequent transaction), the wallet state advances to a new `produced_state_id`
3. Any re-submission of the old transaction now references a stale `consumed_state_id` that no longer matches the wallet's current state
4. Core (CL2) naturally rejects transactions with stale `consumed_state_id`

**Fee implications:**

A validator may receive multiple witness requests for the same txid. The validator signs each one. When collecting fees, the validator presents one fee cheque per txid. Duplicate signatures for the same txid do not entitle the validator to multiple fees. This is handled at fee collection time, not at witness time.

**Enforcement of unpaid fees:**

If a validator has witnessed a previous transaction for a client but has not received fee payment, the validator MAY reject subsequent transactions from that client during S-ABR overlap validation. This is a business policy decision implemented in Lambda, not a protocol requirement enforced by Core. Validators offering free service may skip this check.


#### 17.10.14 CLARA — Client-Led Attested Reality Alignment (NORMATIVE)

**Introduced:** v2.11.15 (YPX-018)
**Spec:** `docs/AXIOM_YPX-018_HEAL_AND_TIERED_MEMORY.md`

**CLARA** (Client-Led Attested Reality Alignment) is the wallet recovery protocol for the case where §17.10.13 re-witnessing is insufficient — namely, when a wallet has been poisoned at one or more validators by partial witnesses (k=3 not reached) and the client wants to send a *different* transaction rather than retry the original one.

**Problem.** When a transaction reaches V1 and V2 but never reaches V3, V1 and V2 store the post-transaction state for the wallet even though no FACT link was registered with Nabla. The client treats the transaction as failed, but V1 and V2 carry stale state that mismatches the wallet's real state. Future transactions from this wallet through V1 or V2 are rejected with `E_SABR_HASH_MISMATCH`. If enough validators are poisoned, the wallet becomes permanently unusable.

The §17.10.13 re-witnessing rule allows the client to retry the *exact same* transaction and clear the partial. CLARA covers the orthogonal case where the client wants to abandon the partial and send something different.

**Mechanism (heal-forward, v2.11.15-beta4).** A wallet that detects a partial witness (`0 < ok_count < k`) computes, from its own local state at TX1 construction time, the three pieces of post-partial bookkeeping it needs to heal safely:

- `poisoned_state_id` — the deterministic `produced_state_id` the committed validators stored. `compute_produced_state_id` is a pure function of `(wallet_pk, new_balance, new_seq, consumed_state_id, nonce)`, all of which the client knows.
- `poisoned_committers` — the validator IDs from TX1's `ok_list`. These are the validators whose local stored state is exactly `poisoned_state_id`.
- `poisoned_balance`, `poisoned_wallet_seq` — the `(balance, seq)` the committed validators stored. Both deterministic from TX1's amount and sequence increment.

The wallet then builds `TX_HEAL` — a self-cheque (sender = receiver = the wallet itself) — with **`consumed_state_id = poisoned_state_id`** (not the pre-partial state), `wallet_seq = poisoned_wallet_seq + 1`, `declared_balance = poisoned_balance`, **`amount = MINIMUM_TX_ATOMS` (500000, the protocol dust minimum — NOT zero)**, and `is_heal = true` (Core CL1 §11.9.4 self-send exception; the signing message appends `AXIOM_HEAL_BIND || 0x01`).

> **Heal self-send amount (canonical, 2026-06-16).** A `TX_HEAL` self-cheque moves exactly `MINIMUM_TX_ATOMS` (500000 = 0.00005 AXC), the dust minimum every non-protocol TX must clear (`amount == 0` is rejected `E_ZERO_AMOUNT`; `amount < MINIMUM_TX_ATOMS` is rejected as dust). It is deliberately **not** `GENESIS_CLAIM_AMOUNT`, so a `(self-send, amount == GENESIS_CLAIM_AMOUNT)` signature remains reachable only via the airdrop/dev-treasury claim path — that's the discriminator the Core CL5 genesis-replay gate (`GenesisClaimWalletAlreadyFunded`) and its SDK mirror both key on. The resulting heal self-cheque is redeemed by the wallet to itself; the dust returns to spendable on redeem.

**TX_HEAL is routed through `poisoned_committers + 1 truly-fresh validator`.** The committers' stored state equals `poisoned_state_id` by construction, so CL3's `tx.consumed_state_id == state.state_id` check passes and the committers sign via the overlapped path. The one fresh-backfill slot is filled by a validator that was NOT a member of the last successful transaction's witness set — picking any TX_prev witness who was not a committer would pull in a validator stale at `X_real` that would reject TX_HEAL with `E_SABR_HASH_MISMATCH` and cost the slot. The fresh validator accepts via the standard fresh-validator S-ARB check: its `overlapped_signatures` contain real Ed25519 signatures from the two committers over TX_HEAL's commitment, and both committer PKs appear in `prev_receipts.witness_sigs` (the last successful TX's witness set), so the `floor(k/2)+1 = 2` overlap sigs verify and the fresh validator issues its cheque. k=3 reached.

**Why heal-forward preserves the S-ARB double-spend floor.** An earlier draft of CLARA routed TX_HEAL through three completely fresh validators and relied on the YPX-015 fresh-validator rule (stored=None → accept client's `consumed_state_id` at face value). That was an S-ARB bypass: an attacker could present TX_HEAL consuming an arbitrary old state, no fresh validator had authoritative local state to contradict it, and the resulting `ClaraAttestation` could then roll previously-honest validators *backward* onto an attacker-chosen fork — the classical rollback double-spend. The heal-forward rule closes this by construction: the *only* validators that can sign a TX_HEAL consuming `poisoned_state_id` are the ones whose stored state is exactly that value, and those are, by definition, the real committers of the partial TX. An attacker with no actual partial commit cannot forge signatures from such validators (CL3 would reject). The fresh backfill validator still runs the full S-ARB overlap check, so it only accepts when the committer sigs are real, valid, and anchored in the previous-TX's witness set. The trust floor for a rollback attack is therefore identical to the trust floor for forking any normal k=3-witnessed TX.

**User-visible consequence.** By adopting `poisoned_balance` as the wallet's effective current balance for the heal, the wallet accepts that TX1's amount has been debited. TX1's `k-1 = 2` cheques remain below the redeemability threshold, so the receiver cannot claim them; they are neither recoverable to the sender. This is the documented cost of recovering transactability after a partial witness, and is strictly better than a permanently locked wallet.

**S-ABR overlap relaxation for TX\_HEAL (v2.11.16-beta40).** Normal TXs require `sabr_overlap(prev_k)` overlap sigs from the previous receipt's witness set. For a k=5 wallet with a 2/5 partial, this requires 3 overlap sigs — but only 2 committers exist. TX\_HEAL would always fail.

For `is_heal == true` TXs ONLY, the fresh validator's overlap requirement is `sabr_overlap(committer_count)` instead of `sabr_overlap(prev_k)`. With 2 committers: `sabr_overlap(2) = 2` — both committers must sign, plus fresh validators to reach k. With 1 committer: `sabr_overlap(1) = 1` — the lone committer signs, plus fresh validators.

**Why this is safe (rollback analysis):**

An attacker who wants to abuse `is_heal` to roll back a completed TX faces four independent defenses:

1. **`verify_state_id_valid`** — every validator checks `stored == consumed`. After a completed k=3 TX, all 3 validators have `stored = X_new`. Nobody has `X_old` — the rollback fails at every honest validator regardless of overlap count.
2. **Self-send only** — Core enforces sender == receiver for `is_heal`. No money can move to another party via a fake heal.
3. **Nabla state conflict** — the completed TX was registered with Nabla. A rollback TX produces a conflicting `old_state` → Nabla rejects registration → FACT link is scarred → money is tainted.
4. **Signature binding** — `is_heal` is bound to the client signature (`AXIOM_HEAL_BIND`). Lambda cannot flip the flag.

The overlap relaxation does NOT lower the trust floor for double-spend. An attacker would need to control all previous-TX validators AND Nabla to achieve a rollback — the same threshold as forging a normal TX.

**`ok_count == 1` recovery.** With the relaxed overlap, a single committer is sufficient: `sabr_overlap(1) = 1`. The lone committer signs TX\_HEAL, 2 fresh validators verify the 1 overlap sig, k=3 reached. Previously this case required blacklisting the committer and continuing from X\_old — which is still valid as a fallback but no longer the only path.

**Cheque garbage registration (NORMATIVE).** The partial TX issued cheques to the receiver (below-k, unredeemable). These cheque txids MUST be registered in the garbage state bloom as part of the CLARA registration request (`WireMessage::RegisterClaraRequest`, TCP-CBOR). Without this, the receiver could attempt to redeem stale cheques after the wallet has healed past them. Nabla rejects any redeem attempt where the txid appears in the garbage bloom — the cheques are dead.

**Post-heal Nabla registration.** After TX_HEAL reaches k=3, the wallet sends the bundle to Nabla over the TCP-CBOR `WireMessage::RegisterClaraRequest` wire. The registration (Phase 5f wire format) includes:

1. The healing wallet's `wallet_pk` (Ed25519 public key).
2. The k=3-witnessed `TX_HEAL` cheque bundle (`heal_cheque`).
3. The authoritative `heal_transaction: Transaction` (with `is_heal=true`, sender=receiver, `consumed_state_id = poisoned_state_id`). Nabla verifies `compute_txid(heal_transaction) == cheque.txid` and derives `healed_from_state_id = tx.consumed_state_id` and `healed_at_seq = tx.wallet_seq` from the verified tx — neither is caller-asserted.
4. A list of `garbage_state_ids` — at minimum the `poisoned_state_id` (to block its reuse) AND the pre-partial `consumed_state_id` (so any validator stuck at the pre-partial state can roll forward via the attestation on a future TX).
5. `healed_balance` — the post-heal balance. Nabla recomputes `compute_state_hash(wallet_pk, healed_balance, wallet_seq)` and verifies it equals the heal cheque's `state_hash` (which is k=3-witnessed), refusing the registration with `HealedBalanceMismatch` if they disagree.

Nabla atomically (full verification path in YPX-018 §2.4):

1. Verifies the cheque bundle (k=3 distinct validators, each cheque's Ed25519 signature against its `validator_pk`, internal consistency, cheque-level self-send).
2. Verifies the heal transaction (`is_heal == true`, tx-level self-send, `compute_txid(tx) == cheque.txid`, `tx.client_pk == request.wallet_pk`, `verify_pk_binding(cheque.sender_wallet_id, request.wallet_pk)` against the YPX-007 wallet_id pk_bind).
3. Verifies `healed_from_state_id` (= `tx.consumed_state_id`) is not in either bloom chain.
4. Inserts the TX_HEAL txid into the active txid bloom era.
5. Inserts each declared garbage state into the active **garbage state bloom** era (a parallel bloom chain — see §39.9.5).
6. Issues a signed `ClaraAttestation` to the wallet, with the NBC trust anchor populated from the node's own NBC.

The wallet then includes the `ClaraAttestation` in subsequent witness requests to any validator that is still not up to date. Such a validator verifies the attestation offline (using Nabla's pubkey from genesis — no Nabla query) and, if its stored state for the wallet appears in `garbage_state_ids` or equals `healed_from_state_id`, rolls its stored state forward to `healed_to_state_id`. The validator then witnesses the new transaction normally against the rolled-forward state.

**The validator only ever rolls forward.** Roll-back is never permitted. State always moves in the same direction it has always moved.

**Roll-forward eligibility (CL2 amendment).** Core CL2 (or Lambda's pre-Core check) enforces:

1. The `clara_attestation` Nabla signature verifies under the embedded NBC trust anchor.
2. `clara_attestation.wallet_pk` matches the witness request's wallet.
3. If the validator's stored state differs from `request.transaction.consumed_state_id`, the validator's stored state MUST be exactly one of the entries in `clara_attestation.garbage_state_ids` OR equal to `clara_attestation.healed_from_state_id`. If not, the request is rejected with `E_CLARA_STATE_NOT_GARBAGE`. (No multi-step provenance walking — a wallet poisoned at multiple unrelated states must declare all of them in a single CLARA invocation.)
4. Roll forward in memory: replace `state.state_id` with `healed_to_state_id`, `state.wallet_seq` with `healed_at_seq`, and **`state.balance` with `healed_balance`**. The balance rewrite is load-bearing — without it, `validate_transaction` runs against the poisoned balance and any new TX whose amount exceeds that balance is rejected, creating a chicken-and-egg reject loop where Lambda never reaches the post-Core `clara_roll_forward` storage commit and the wallet remains permanently stuck. `healed_balance` is bound into `compute_clara_message` and verified by Nabla against the heal cheque's signed `state_hash`, so trusting it in the synthetic rewrite introduces no new trust assumption.
5. Proceed to normal witness validation against the rolled-forward state. After `finalize_transaction` returns Accept, Lambda commits the roll-forward to storage via `Storage::clara_roll_forward` (post-Core, fail-closed).

**Garbage state enforcement.** Once a state is in the garbage state bloom, Nabla rejects registration of any transaction that consumes it. The wallet cannot extend the broken chain. Combined with the standard pre-accept Nabla check by receivers (§17.9), this closes every replay path:

- **Replay TX1 after CLARA:** Bob's pre-accept check sees that the consumed state was consumed by TX_HEAL and refuses.
- **Extend the broken chain (TX2′ consuming TX1.produced):** Nabla rejects registration because TX1.produced is in the garbage bloom.
- **Replay TX1 BEFORE CLARA:** Bob accepts and registers TX1 with Nabla. Alice then tries to heal: TX_HEAL also consumes the same source state, conflicts with TX1 at Nabla, heal fails. Alice's wallet is permanently scarred. Single legitimate spend, Alice is the only loser.

**No new receiver liability.** Receivers are protected by the *existing* pre-accept Nabla check, not by any new opt-in mechanism. Unlike the rejected PSP design, a CLARA receiver does not carry a hereditary scar marker or any new form of encumbrance. The CLARA receiver is just a normal receiver of a normal k=3 cheque.

**`ClaraAttestation` structure** is defined in YPX-018 §2.2. Domain-tagged signature scheme:

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

NBC trust anchor mirrors `NablaTxidAttestation` (§39.9.4) — flat fields, no_std-compatible, verifiable inside the RISC-V guest.

**Garbage state bloom chain** is documented in §39.9.5 alongside the txid bloom chain. It uses the same time-bucketing, the same age index, the same sharding, and the same Console phase-out rules. Garbage state lookups answer through `GET /query-garbage-state`.

**Relationship to §17.10.13:** §17.10.13 covers retrying the same transaction. CLARA covers moving on to a different transaction. Both are required for full partial-witness recovery. The two are orthogonal and stay in place independently.

**Relationship to YPX-016 (witness response cache):** YPX-016 caches the witness response per wallet so retrying the exact same TX can return the cached response without re-executing Core. It is an optimization for the common-case retry path. CLARA is the correctness path for the move-on case. Both are kept; their roles are distinct.


### 17.11 Genesis Claim Protocol (Wallet Onboarding)

#### 17.11.1 Overview

Every new wallet receives 1 AXC from the Airdrop Pool (White Paper §2.10.2) via a
**Genesis Claim** — a special first transaction that follows the standard cheque/redeem
pipeline with minimal exceptions.

The Genesis Claim produces a real k=3 receipt, ensuring every funded wallet has a
valid `prev_receipts` chain from its first transaction. This is critical for CLARA
TX_HEAL recovery, which requires `prev_receipts` for S-ABR overlap proof.

#### 17.11.2 Flow

1. **Client creates keypair.** Balance = 0, wallet_seq = 0.

2. **Client sends Genesis Claim TX** to k=3 validators:
   - `is_genesis_claim = true`
   - `wallet_seq = 1` (first TX)
   - `amount = GENESIS_CLAIM_AMOUNT` (1 AXC = 10^10 atoms, must match exactly)
   - `sender_wallet_id = receiver_wallet_id` (self-send)
   - `consumed_state_id = SHA3-256("AXIOM_GENESIS" || pk || 0_u64_LE)` (genesis state with balance=0)
   - `prev_receipts = []` (genesis exception: §17.10.2)
   - Signing message appends `AXIOM_GENESIS_CLAIM_BIND\x01` (domain separation)

3. **Core validates:**
   - `is_genesis_claim` requires `wallet_seq == 1` AND `prev_seq == 0` (prevents replay)
   - `amount` must equal `GENESIS_CLAIM_AMOUNT` exactly (Core rejects other values)
   - Self-send allowed (same exemption as `is_heal`)
   - S-ABR: all validators overlapped (genesis exception, no prev_receipts)
   - Balance deduction skipped — wallet stays at balance=0 on send side (pool funds the claim)
   - `produced_state_id` computed with `new_balance = current_balance` (no deduction)
   - Commitment hash includes `GENESIS_CLAIM_AMOUNT` as the TX amount (consistent through cheque → redeem)

4. **Each validator issues a cheque** for `GENESIS_CLAIM_AMOUNT` (1 AXC).
   Validator does NOT check pool balance — it certifies wallet identity only.
   Standard `ValidatorCheque` with amount = `GENESIS_CLAIM_AMOUNT`.

5. **Client collects k=3 cheques.** Standard `ChequeBundle`.

6. **Client redeems at 3 Nabla nodes** (standard redeem flow, §17.9):
   - Nabla checks the **Airdrop Pool** — a protocol-level counter in Nabla's state
   - Pool has funds → deduct `GENESIS_CLAIM_AMOUNT`, confirm registration
   - Pool exhausted → reject pool deduction, but still register wallet at balance=0
   - In both cases: wallet advances to `wallet_seq=1` with a real k=3 receipt

7. **Result:** Wallet has `wallet_seq=1`, real k=3 receipt with witness sigs,
   `fact_chain` with 1 link, Nabla registration. Production-realistic state.

#### 17.11.3 Pool Tracking (Airdrop + DevTreasury)

Nabla tracks two **protocol-level counters** for genesis claim funding —
they are not wallets, just per-pool state. FACT class isolation §6
routes claims to the matching pool based on the wallet's email-derived
class (exact `@axiom.internal` match → DevTreasury; everything else → Airdrop).

| Pool | Initial Balance | Spec | Daily Cap |
|------|-----------------|------|-----------|
| `Airdrop` | 600,000 AXC | White Paper §2.10.2 "Wallet-Based Distribution" | 5,000 AXC/day (sanity floor; soft) |
| `DevTreasury` | 1,000,000 dev-AXC | `AXIOM_DESIGN_FactClassIsolation.md` §4 | None (fixed lifetime, dev-only) |

- **Storage:** Per-Nabla-node, persisted as `<data_dir>/airdrop_pool.state`
  and `<data_dir>/dev_treasury_pool.state` (CBOR `{balance, total_claims, tick}`,
  atomic save on every mutation). On boot the node loads each file; if absent,
  falls back to the initial constant. A corrupt file surfaces as a loud
  error rather than silent re-mint.

- **Wire variant:** unified `GossipMessage::PoolSync { pool, balance, total_claims, tick }`
  (replaces the prior per-pool `AirdropPoolSync` / `DevTreasuryPoolSync`).
  `pool: PoolKind` dispatches to the matching in-memory pool's reconciler.
  One handler covers both pools (and any future pool: same shape, add a
  variant). Wire layer = aggregate sync only — there is **no per-claim
  chain** (an earlier "Pool Supply Chain" design was abandoned, see
  `AXIOM_DESIGN_PoolSupplyChain.md` for the reasoning record).

- **Deduction:** The TCP-CBOR registration path deducts on `is_genesis_claim`.
  Pool state gossipped immediately after the local mutation succeeds —
  event-driven, no periodic polling.

- **Gossip convergence:** Monotonic-decrease, smallest balance wins.
  Sanity gate: balance drop must be explainable by claim count increase
  (each claim = exactly `GENESIS_CLAIM_AMOUNT`); a peer reporting an
  unexplained drop is rejected. Forward-on-change cascade with msg_hash
  dedup terminates the wave at converged peers. Restart-safe because the
  reconciled state is persisted; the in-memory counter and disk file
  agree at every quiescent point.

- **Exhaustion:**
  - *Airdrop:* When balance < `GENESIS_CLAIM_AMOUNT`, pool claims are
    rejected but the wallet still registers at balance=0 with a valid
    receipt (graceful degradation — see §17.11.4).
  - *DevTreasury:* Hard-rejects on exhaustion (`E_POOL_EXHAUSTED`) —
    visible depletion, no graceful path. The 1M cap is fixed-lifetime
    with no minting authority.

#### 17.11.4 Pool Rejection (balance=0 wallets)

When the pool is exhausted, the wallet registers with `balance=0, wallet_seq=1`.
The 3 validators that issued cheques hold `produced_state_id` computed with
`GENESIS_CLAIM_AMOUNT` (1 AXC) — this state is stale.

**balance=0 S-ABR exception:** When a wallet's stored balance is 0 and `wallet_seq >= 1`,
S-ABR overlap is skipped. This is safe because:

- Cannot spend 0 (Core enforces output $\leq$ input)
- No double-spend risk (nothing to double-spend)
- The wallet's only useful action is receiving funds via redeem
- After receiving funds: balance > 0, S-ABR applies normally
- The stale validators hold a normal wallet entry (no storage leak — every wallet
  registers anyway)

#### 17.11.5 Validation Rules (Core)

| Rule | Check | Error |
|------|-------|-------|
| Sequence | `wallet_seq == 1 AND prev_seq == 0` | `GenesisClaimInvalidSeq` |
| Amount | `tx.amount == GENESIS_CLAIM_AMOUNT` | `GenesisClaimInvalidAmount` |
| Balance | No deduction (pool funds the claim) | — |
| Self-send | Allowed (same as `is_heal`) | — |
| prev_receipts | Not required (genesis exception) | — |
| S-ABR | All validators overlapped (genesis) | — |
| Signing | `AXIOM_GENESIS_CLAIM_BIND\x01` appended | — |
| produced_state_id | Computed with `GENESIS_CLAIM_AMOUNT` | — |

#### 17.11.6 Security Analysis

| Attack | Defense |
|--------|---------|
| Claim replay (same wallet) | `wallet_seq==1 + prev_seq==0` — only works once |
| Forged amount | `tx.amount` must be 0; `GENESIS_CLAIM_AMOUNT` is hardcoded in Core |
| Pool drain (spam claims) | Each claim requires k=3 validator round trips + Nabla registration; rate-limited by protocol throughput |
| Forge balance=0 wallet | Safe — cannot spend 0; S-ABR skip only applies to balance=0 |
| Validator mints extra AXC | Cheque amount = `GENESIS_CLAIM_AMOUNT` (Core-enforced); Nabla controls pool deduction |
| Pool state manipulation | Nabla gossip convergence; writer-only deduction; minimum-balance rule |


#### 17.11.7 Failure Modes & Recovery

A genesis claim can fail at multiple stages of the witness/register
pipeline. **Some failure modes are recoverable** — Nabla cap
rejections (per-node, mesh-cycle, network timeout) preserve the
witness round so a later retry resumes the claim without
re-witnessing. **Other failure modes are terminal** for the wallet
keypair — validator partial commit, transport cheque drops, pool
exhaustion, and narrow SDK-dies-mid-commit races. This section
enumerates the failure modes, identifies which are recoverable,
specifies the recovery mechanism, and specifies the client UX
contract.

##### 17.11.7.1 Failure modes (against §17.11.2 flow)

| Stage | Failure mode | Recoverable? | Recovery path |
|---|---|---|---|
| Step 2 (witness) | Validator partial commit — got <k witness sigs in the round | No | New keypair. Some validators advanced state but the round never reached `wallet_seq=1` quorum; replay is rejected. |
| Step 5 (cheque delivery) | k=3 cheques witnessed but transport drops one or more before the SDK collects them | No (k cheques required to redeem) | New keypair. Cheques witnessed but not delivered cannot be re-emitted. |
| Step 6 (register) | k=3 sigs collected, Nabla per-node cap reached on every Nabla the SDK tried | **Yes** | SDK saves `PendingRegistration { is_genesis_claim: true }` carrying the cached witness sigs. Retry via `claim_genesis_full` after the per-node cycle resets (~10 min order); resume bypasses the witness round and re-submits register via `complete_registration`. |
| Step 6 (register) | k=3 sigs collected, mesh-wide claim cap reached for this cycle | **Yes** | Same recovery mechanism. Retry after the mesh cycle resets (~12 h order). |
| Step 6 (register) | k=3 sigs collected, Nabla unreachable / register times out after retry budget | **Yes** | Same recovery mechanism. Retry when Nabla is reachable again. |
| Step 6 (register) | Airdrop pool permanently exhausted (no refill mechanism per §17.11.3) | No (protocol-wide, not wallet-specific) | None. Affects every wallet on every device — UX suppresses the Claim CTA globally. |
| Step 6 (register) | k=3 sigs collected, register succeeds at Nabla, SDK process dies before reading the response | No (narrow microsecond race — Nabla committed, SDK never knew) | New keypair. The wallet identity ends up with AXC issued at an SMT entry no key can sign for. |

The recoverable cases dominate in practice — most Nabla register
failures are transient cap exhaustion or network flakes. The
terminal cases are statistically rare on a healthy network
(validator partials need k-1 of 3 validators to drop the round
simultaneously; transport cheque drops need at least one of three
SMTP / TOT deliveries to fail; the SDK-dies race is on the order
of microseconds between Nabla's commit and the SDK's read).

##### 17.11.7.2 Recovery mechanism for the recoverable cases

For the three recoverable Pending paths (`MeshCapReached`,
`AllPerNablaCapsHit`, `NetworkTimeout`), the SDK persists the
witness round to disk so the claim can resume without
re-contacting validators:

1. `fund_genesis` saves the wallet at `wallet_seq=1`,
   `balance=0`, with `fact_chain` and `last_receipt` populated
   from the witness round.
2. Before returning the `retry_after` / `retryable` error,
   `fund_genesis` calls
   `wallet.add_pending_registration(PendingRegistration { is_genesis_claim: true, ... })`
   carrying the cached k=3 witness sigs, the genesis
   `consumed_state_id` and `produced_state_id`, and the txid.
3. On the next `claim_genesis_full` call, the SDK detects the
   `is_genesis_claim: true` pending entry at entry time, skips
   `fund_genesis` (the witness round already happened — validators
   are already at the produced state), and calls
   `complete_registration(txid)` to re-submit the cached register
   to Nabla.
4. If Nabla now accepts (cap reset, or Nabla reachable again),
   `complete_registration` returns `Confirmed`, the pending
   entry is dropped, and `claim_genesis_full` proceeds to Step 2
   (wait for cheques in maildir, which may already be there from
   the original witness round) and Step 3 (redeem).
5. If Nabla still rejects with the same code, the pending entry
   stays, the same `retry_after` error is returned, and the
   user waits longer.

This recovery uses the existing `PendingRegistration` +
`complete_registration` machinery that already serves non-genesis
sends. No protocol change; no new wire format; no Core or Lambda
or Nabla rule change.

##### 17.11.7.3 Why some failures stay terminal

For the four non-recoverable failure modes, the wallet keypair
cannot be reused:

- **Replay is rejected.** Validators that already committed at
  least one cheque hold `wallet_seq=1`. A re-submission with
  `wallet_seq=1, prev_seq=0` hits `GenesisClaimInvalidSeq`
  (§17.11.5).
- **SDK-side balance credit desyncs from the validator-committed
  state.** `produced_state_id = SHA3-256(... || new_balance || ...)`
  (§16.14.12). Locally crediting 1 AXC without the validator
  handshake that bakes 1 AXC into the state → wallet's local
  `state_id` diverges from validator-held `state_id` → next send
  fails CL1 with `InvalidStateId`. The 2026-05-12 attempt at
  SDK-side recovery bricked wallets worse than leaving them
  terminal; it was reverted same day and the recovery path was
  permanently removed from the SDK.
- **Heal cannot recover.** `do_burn_scar` on a genesis claim is
  rejected by Core CL5 (genesis claims have no provenance to
  burn back to). Heal reports "1 found, 0 fixed" and exits
  without advancing.

Pool exhaustion is a special terminal case — not "this wallet
died" but "the network airdrop pool is permanently drained,"
affecting every wallet on every device. The UX response is
global suppression of the Claim CTA (see §17.11.7.5).

##### 17.11.7.4 Why no protocol-level fix is shipped (for the terminal modes)

Two protocol-clean fixes have been considered. Both are deferred:

1. **Send-side credit.** `fund_genesis` credits balance on the SDK
   side, and validators bake the credited value into `state_id`
   from the start. Closes validator-partial and transport-drop
   terminal cases. Requires amending §17.11.2 step 3, a Core
   CL5 rule change, conformance vector regeneration, and updates
   to the DMAP-VM guest's genesis path.
2. **New `genesis_credit` TX type.** A dedicated validator-signed
   wire variant producing a credited state atomically across
   Lambda commit and Nabla register, with coordinated abort if
   either side fails. Requires a new wire variant, Lambda CL3
   ordering rules, Nabla SMT update rules, and a new error
   taxonomy.

Both fixes expand wire format and validation surface to address
statistically-rare failures with a **zero-cost user remedy** (the
user creates a new keypair). The cost of either fix —
additional attack surface for a recovery path that competes with
the existing one — outweighs the benefit. The protocol's
position is that client-side UX, not protocol machinery, owns the
terminal failure modes. Pool exhaustion cannot be "fixed" at any
layer — refill would require a sovereign authority that the
airdrop pool is explicitly defined NOT to have (§17.11.3).

##### 17.11.7.5 Client-side UX requirements

Every wallet implementation MUST:

1. **Warn before the claim.** Surface, at the claim-confirmation
   step, that some failure modes are terminal for the keypair.
   Include a reference to this section (§17.11.7).

2. **Require explicit acknowledgement.** A passive
   description-text notice is insufficient — the acknowledgement
   must gate the Claim action.

3. **Route cap rejections to resume, not new keypair.** For the
   three recoverable Pending paths (per-Nabla cap, mesh cap,
   network timeout), surface a "Try again in ~10 min" / "~12 h"
   / "when Nabla is back" prompt. The retry MUST call
   `claim_genesis_full` (which detects the pending entry and
   resumes via `complete_registration`) or
   `complete_registration` directly — NOT issue a fresh witness
   request. The SDK's `has_pending_genesis_registration` accessor
   lets the UI keep the Claim CTA visible after `wallet_seq`
   advances to 1.

4. **Deliberately approximate wait-time copy.** Show "about
   10 minutes" / "about 12 hours" rather than echoing the SDK's
   precise `reset_tick`. Exposing exact cycle-reset timing helps
   an attacker plan exhaust-then-cap-reset cycles to lock out
   honest claimants. The SDK accepts retries at any time; the
   user-facing time is guidance, not a hard gate.

5. **Treat pool exhaustion as global suppression.** When
   `AirdropPoolExhausted` is observed on any wallet, suppress
   the Claim CTA on every wallet on this device, including
   subsequent new-wallet creations. The pool has no refill
   mechanism — dangling the Claim UI is misleading. Persist this
   across app uninstall (the canonical Mac implementation uses a
   hidden file outside the bundle's data directories).

6. **For the truly-terminal modes, instruct new keypair.** For
   validator partial commit, transport cheque drop, and the
   narrow SDK-dies race, the UX MUST instruct the user to
   create a new pair and MUST NOT offer "retry" or "heal" —
   both will mislead. Distinguish these from recoverable cap
   rejections by the SDK error code.

7. **Surface the YP reference.** Either an inline link/note to
   §17.11.7, or a UI affordance that makes the reasoning
   discoverable.

The current macOS `AxiomWallet.app` implements this contract as
a developer reference (see
`apps/macos/AxiomWallet/Sources/AxiomWallet/GenesisClaimSheet.swift`
and `PoolExhaustedFlag.swift`). `AxiomWallet.app` is a
**dev-reference implementation, not production software** —
its surface is the canonical example for downstream wallet
authors, not an end-user-grade product.


### 17.12 Voluntary Self-Scar

A client may voluntarily scar any FACT link in their own chain by removing its `NablaConfirmation` from the local copy before presenting the chain to validators. The link then qualifies for burn (§34).

**This is a client operation, not a protocol operation.** The client controls their own FACT chain. They choose to drop a confirmation. No new TX type, no new flag, no protocol change.

**Flow:**

1. Client identifies the stuck TX in their FACT chain
2. Client removes `nabla_confirmation` from that link (local operation)
3. Client submits a burn TX targeting that link (§34 — existing mechanism)
4. Core validates: target exists, target is scarred (confirmation removed), not already burned, exact amount
5. Burn resolves the scar. Balance reduced by the burned amount. Wallet continues.

**Use cases:**

| Scenario | Action |
|----------|--------|
| Trapped (double-redeem phantom) | Self-scar the trapped TX, burn it, wallet resumes |
| Dead validators (no overlap) | Self-scar the orphaned TX, burn it, heal past it |
| Lost receipt | Self-scar the stuck TX, burn it, FACT compression cleans up |
| Privacy choice | Self-scar a TX to break provenance, burn it |

**Cost:** The exact amount of the targeted TX is destroyed. The wallet keeps everything else.

**Security:** Only the key holder can present the modified FACT chain (owner\_proof required for burn). Nabla retains the original registration history — the self-scar does not erase Nabla's records.

#### 17.12.1 Verification of the scarred link on burn (KI#13 carve-out — NORMATIVE)

Core's FACT chain verification (`verify_fact_chain` family in `core/logic/src/fact.rs`) Dilithium-verifies the witness signatures on every link of the chain against the commitment shape defined by the current Core ELF's consensus rules. This is the load-bearing crypto gate that prevents an attacker from forging a FACT link or modifying its bound fields.

After a Core ELF rebuild that changes any field in the FACT commitment domain (wire-shape change, BLAKE3 domain-tag change, canonical-CBOR ordering change), a link signed under the prior ELF will not re-verify under the new rules — the recomputed canonical bytes differ from those the witnesses signed, so Ed25519/Dilithium verify returns failure. For NON-scarred links this is correct rejection (the new ELF cannot attest to a link bound to old rules), but for SCARRED links being retired by a burn TX it produces a permanent strand: the wallet cannot burn what the new ELF cannot verify, and the chain wedges at `MAX_FACT_DEPTH` after the next scar.

To prevent this strand, Core's burn-TX validation path **skips Dilithium witness-signature verification on the SCARRED link identified by `tx.burn_target_tx_id`** when `tx.receiver_wallet_id == BURN_ADDRESS`. The skip applies only to the witness-sig loop on that one link.

**All other gates on the chain still verify at full strength:**
- The burn TX's own newly-produced FactLink (signed under the current ELF) is fully Dilithium-verified.
- Every non-scarred link in the chain is fully Dilithium-verified.
- On the scarred link itself: minimum-k=3 witness count, no-duplicate-validators, BurnProof structural integrity, VBC genesis-anchor binding, NablaConfirmation Ed25519 (when present), chain `previous_state_id` continuity, FACT class lock, depth limits — all still verified.
- §15 state-anchored check (every validator action requires client `current_state` to derive to the k-signed `prev_receipt.state_hash` via `compute_state_hash`) is unaffected.

**Economic safety argument:** the burn flow's existing gates cap a fake-scar burn at the wallet's real funds.
- `validate_burn_target` (NORMATIVE) requires `target_link` to exist in the chain, to be genuinely scarred (`nabla_confirmation.is_none() && burn_proof.is_none()`), and `tx.amount == link.amount`.
- `verify_balance` requires `tx.amount ≤ available_balance` (balance cannot go negative).

Together these mean a wallet presenting a fake scar (a syntactically valid FactLink with random witness signatures and a claimed amount) can at most destroy its own real available balance. No inflation (no atoms minted from the fake claim), no double-spend (state advances strictly forward), no cross-wallet impact (FACT chains are per-wallet), no audit-trail forgery (the burn TX's own new FactLink is fully verified under the current ELF and forms the authoritative new chain tip). The worst-case attack reduces to self-destruction, which is already trivially available via a self-send.

**This carve-out is exceptional.** It is the only point in the protocol where a cryptographic verification step is deliberately skipped. The skip is approved because the economic gate uniquely makes verification unnecessary at this site — burns only reduce balance, capped at available. No other code path in the protocol has that property, and the carve-out MUST NOT be generalised to any other verification gate. See the implementation comment block at `core/logic/src/fact.rs::verify_fact_chain_burn_retire` and the project-rule statement in `CLAUDE.md` "Exceptional non-verify carve-out (KI#13)".

Approved 2026-06-08; tracked in `docs/AXIOM_REPORT_KnownIssues.md` #13 (RESOLVED).

### 17.13 Griefing Resilience — Scar Flooding and WAL Growth

#### 17.13.1 Attack Description

A griefer controlling one or more validators deliberately causes partial witnesses on targeted wallets. The goal is not double-spend or double-redeem — it is disruption: force wallets into repeated recovery cycles, accumulate unresolved FACT scars, inflate garbage bloom entries, and degrade throughput.

The griefer does not need to control a majority of validators. A single malicious validator that times out or returns errors during witness production is sufficient to create a partial (2/3 or 1/3) on any wallet that selects it.

#### 17.13.2 Why This Attack Fails

**Blast radius is one wallet.** A partial witness on wallet A has zero effect on wallet B. Validators, Nabla nodes, and all other wallets are unaffected. The griefer can only damage wallets that select their validator — and each wallet selects randomly from the pool.

**Recovery is automatic.** TX\_HEAL (§17.10.14) recovers partial witnesses with 100\% success rate. The wallet detects the partial, records the committers, sends TX\_HEAL to the committers + fresh validator, and resumes. The griefer must continuously cause new partials faster than recovery — but each recovery includes a cooldown period where the wallet is immune to new chaos.

**Scars are bounded (primary + defense-in-depth).**

*Primary mechanism — Core chain-depth cap.* Resolved (Nabla-confirmed) links compress away under the SEC-07 travel model, so a healthy chain never grows unbounded. Scarred links do NOT compress — they stay visible — so the bound that matters is on *unresolved* scars: a generous `FACT_HARD_CEILING = 32` hard-rejects in the verify path, `MAX_FACT_DEPTH = 8` is enforced as a post-compression structural guard (`verify_and_compress_fact_chain`) and via the operator's `max_fact_links` config (passed through `PublicInputs.max_fact_links` per `validation.rs`), and a separate max-unresolved-scars rule caps scar pileup. When a wallet detects a scar it cannot supplemental-heal (receipt lost), it skips the scar and FACT compression removes the surrounding resolved links at the next trigger. Core rejects a send whose chain exceeds these bounds with `E_FACT_CHAIN_TOO_DEEP`. **This is the real protection** — scar accumulation creates backpressure that stops new sends, not a runaway loop. (Note: depth alone is NOT a verify-time reject under the travel model — a chain legitimately verifies past 8 while its checkpoint proposal accumulates signatures; only `FACT_HARD_CEILING` flatly rejects.)

*Defense-in-depth — SDK burn-rate cap.* The client-side `wallet.heal()` enforces a secondary cap: `MAX_BURNS_PER_HEAL_CALL = MAX_FACT_DEPTH + 1` (`sdk/client/src/heal.rs`). Under normal operation no chain can have more than `MAX_FACT_DEPTH` scars (the primary cap blocks it), so the heal call never reaches this threshold in practice. The cap exists for failure cases where the primary mechanism leaks — operator `max_fact_links` misconfigured high, a defect in Core's chain-depth check, compilation drift between Core ELF and validators, etc. If `wallet.heal()` ever sees more than `MAX_FACT_DEPTH + 1` scars, it logs a warning indicating the upstream invariant has failed (`[heal] WARN: scar_count=X exceeds MAX_BURNS_PER_HEAL_CALL=...`) and still attempts one burn per call so forward progress continues. Operators investigating the warning can pin down whether `max_fact_links` was set too permissively, whether a deployed Core ELF mismatches its declared CoreID, or whether a code-path leaked the cap.

The `+1` margin handles off-by-one cases — if a chain transiently reaches `MAX_FACT_DEPTH + 1` scars (e.g., a scarred link is appended before the chain-depth check fires on the next operation), the heal cycle can still process it without false-flagging the invariant.

**Griefer pays, victim doesn't.** The griefer's validator earns no fees from failed TXs. The griefer pays operational cost (hosting, bandwidth) for zero return. The victim's wallet continues selecting other validators — the griefer is blacklisted after detection.

#### 17.13.3 Storage Impact Analysis

| Resource | Growth per partial | Bounded by | Impact at scale |
|----------|-------------------|------------|-----------------|
| FACT chain | +1 scarred link | `MAX_FACT_DEPTH = 8`, compression removes resolved | Negligible — bounded at 8 links |
| Garbage bloom | +1 entry per partial | Per-era bloom, frozen at era close | Negligible — bloom sized for planetary scale (GBs) |
| `_receipt_store` | +1 entry | Per-wallet, cleared on heal | Negligible — wallet-local, not network-wide |
| Nabla state | No growth | Partial doesn't register with Nabla (no k=3 receipt) | Zero |
| Validator storage | +1 uncommitted state | Overwritten on next successful TX | Zero net growth |

**Conclusion:** A griefer creating 1,000 partial witnesses adds ~1,000 garbage bloom entries (32 bytes each = 32 KB) across the entire network. The garbage bloom is designed for billions of entries at planetary scale. The storage impact of griefing is unmeasurable.

#### 17.13.4 Throughput Impact

At 5\% partial rate (17x worse than Ethereum's worst production conditions), the system sustains full throughput: TX\_HEAL recovers every partial, wallets resume sending, and the failure count stays bounded. At 20\% partial rate, throughput degrades as recovery cannot keep up with poisoning — but protocol correctness (zero double-spend, zero double-redeem, atom conservation) is maintained at any rate.

A realistic griefer controlling 1 of 10 validators causes ~10\% of TXs to that validator to fail — but only for wallets that select that validator (~3 of 50 per TX cycle). The effective system-wide impact is < 1\%. The griefer is a nuisance, not a threat.

#### 17.13.5 Detection and Response

Validators with abnormally high partial-witness rates are detectable through:

- Client-side blacklisting: wallets track which validators cause failures and avoid them
- Nabla gossip: registration failures correlate with specific validators
- Network statistics: validators with low witness success rates are visible in dashboards

The protocol does not automatically ban validators for poor performance (that would be a governance mechanism, which AXIOM avoids). Instead, the market handles it: validators with poor uptime earn fewer fees because clients avoid them.

### 17.14 RECALL — recovering a completed-but-undelivered payment (YPX-022)

RECALL is the sender-side recovery for **a payment that completed on-chain but whose cheque never reached the receiver** (delivery failure — bounced email, dropped connection, dead device). The send is valid (3-of-3, sender debited `B−A`, cheque `C` completion-registered), yet the value is stranded: the receiver cannot redeem a cheque they never received, and the sender cannot re-spend money they legitimately paid out. RECALL returns `A` to the sender and permanently kills the undelivered cheque. Full specification: `docs/AXIOM_YPX-022_RECALL.md`.

**This is not the banned cheque-retract.** The test is not *"did the send complete?"* but *"does the receiver hold a redeemable cheque?"* — an **undelivered** cheque (receiver never had it) is recoverable; a **received** one (receiver is relying on it) stays irrevocable, and retract stays banned. RECALL never touches a cheque the receiver holds.

**Superseded premise.** RECALL previously reclaimed a *failed (sub-quorum) send*. The **quorum gate** (§17.1.2 — nothing advances below 3 witnesses) makes a sub-quorum send a no-op (nothing debited, nothing stranded), so there is no failed-send money to reclaim. RECALL's gate therefore **inverts** to a *completed* send, and the separate RE-ISSUE re-delivery op is dropped — a receiver who never got the cheque is made whole by the sender recalling + re-sending, never by re-delivering the same cheque.

**Eligibility gate (the safety boundary).** RECALL may be initiated only on a txid that is **completion-registered** (a real k-witnessed send, read from Nabla's own ledger with zero sender-trust) **AND** status **`NotRedeemed`** (three-state txid status, §39.9.5) **AND** aged within **`[18000, 50000]` ticks** (lower bound = the receiver's protected redeem window; upper bound closes the affordance) **AND** OODS-healthy (YPX-021). A `Redeemed` txid refuses recall — the payment landed; first-wins; irreversible. The trigger is **deliberate, not reactive**: nothing fails at send time (the send succeeded), so recall surfaces as an explicit later action on a successful-but-`NotRedeemed` payment once it ages into the window.

**Flow.** Initiate (in-window, OODS-healthy) → at hibernation-entry submit `C`'s txid to the **garbage-state bloom chain**, which fans out mesh-wide ("`C` is no longer redeemable," permanent under the constitutional 55-year retention floor, §21.10.6 / §39.9.5) → hibernate for `RECALL_HIBERNATION_WINDOW` (recall's own maturity constant — 720 prod, distinct from HAL's `HIBERNATION_WINDOW` 18000, though both share the `hibernation_until_for` projection; the propagation-settle time, projected from the recall tx's `epoch`) → complete: recover `A` via the standard `tx → cheque → redeem` (`B−A + A = B`; balance rises only at the CL5 redeem). The receiver's cheque `C` stays live and redeemable until hibernation-entry: **initiate is a reservation, hibernation-entry is the commit** (YPX-022 §2.2.1) — during the reservation, query-txid serves an unsigned `RETRACT_PENDING` in-flight notice, a redeem that finalizes first wins and aborts the reservation (the recall's commit register refuses, legibly), and the OODS-healthy *exit* is enforced in Core CL5 (the hibernation-clearing self-redeem is refused, retryable and liveness-only, while unhealthy — YPX-022 §2.2.2).

**Safety.** Consume-once (A7) serializes any recall-vs-redeem race — exactly one of {reclaim, redeem} settles, the loser fails closed; a delivered-and-redeemed transfer is never reversed (send-finality holds). The permanent garbage record blocks a late copy of `C` (a delayed email finally arriving) from double-settling for ≥55 years — the exact txid terminals and the garbage chain **persist via the existing Nabla snapshot + WAL** (a restart never forgets a recall), and enforcement **never gates on a raw bloom Hit**: a Hit resolves through the persisted exact terminals (the archive layer); a false positive falls through to allow, so a legitimate redeem can never be stranded by the bloom (YPX-022 §5). One residual: a receiver who *received* `C` but stays offline the entire window can have a legitimate payment recovered — bounded, the irreducible price of solving delivery failure under unreliable delivery.

**Status: IMPLEMENTED (2026-07), deployed on the dev network; recall-race soak validation pending.** CoreID-rotating (the quorum gate); built docs-first per YPX-022 §6 (this YP core-rule + YPX-022, then code). The build inverted the recall gate (failed → completed + `NotRedeemed` + `[18000,50000]`), wired the garbage fan-out at hibernation-entry (`nabla/src/garbage_state_chain.rs`), added the OODS-healthy exit gate in Core CL5, and deleted the failed-send / partial-commit + RE-ISSUE scaffolding the quorum gate obsoleted.

## 18. PWV Creation & DWP Propagation

### 18.1 Query-Initiated PWV Creation

PWV (Potential Witness Validator) sets are created **only** when someone queries a transaction.

**No query = No PWV set = No future judicial process possible.**

This is intentional -- it makes retrospective surveillance expensive and prevents preemptive witness identification.

#### 18.1.1 Design Principle: Pull-then-Push

PWV creation follows a **Pull-then-Push** pattern to maximize witness anonymity:

**Stage 1: Pull (Stochastic Inquiry)**

| Aspect | Description |
|--------|-------------|
| **Initiator** | Querier (Validator_Q) |
| **Method** | Broadcasts discovery signal via diffusion |
| **Key Property** | Querier does NOT know who the Real Witnesses are |
| **Analogy** | Sonar ping searching for submarines |

Real Witnesses receive the query passively -- they do not need to advertise their identity.

**Stage 2: Push (Witness Response)**

| Aspect | Description |
|--------|-------------|
| **Trigger** | Query reaches Real Witness |
| **Action** | Real Witness generates PWV set (with decoys) |
| **Method** | PWV set pushed back via diffusion (NOT direct response) |
| **Resolution** | First-Seen Lock ensures single canonical result |

**Why This Design Works:**

1. **Real Witnesses never advertise** -- They respond only when "pinged" by a query
2. **No target for attackers** -- Cannot pre-calculate which nodes to compromise (PWV set doesn't exist until query)
3. **Sublinear traffic** -- First-Seen throttling prevents PWV explosion
4. **Timing is consensus** -- No confirmation needed; first arrival = canonical truth

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=2.5cm, minimum height=0.6cm, align=center, font=\small},
    phase/.style={font=\small\bfseries\color{axiom-blue}, anchor=west},
    arrow/.style={->, thick, >=stealth}
]
\node[phase] at (-5.5,0) {PULL PHASE};
\node[box, draw=axiom-blue, fill=axiom-blue!8] (Q1) at (-3.5,-0.8) {Querier};
\node[box, draw=axiom-gray, fill=axiom-gray!5] (N1) at (0,-0.8) {Network\\{\scriptsize diffusion}};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (W1) at (3.5,-0.8) {Real Witness};
\draw[arrow] (Q1) -- node[above, font=\scriptsize] {query} (N1);
\draw[arrow] (N1) -- node[above, font=\scriptsize] {diffusion} (W1);

\node[phase] at (-5.5,-2.5) {PUSH PHASE};
\node[box, draw=axiom-blue, fill=axiom-blue!8] (Q2) at (-3.5,-3.3) {Querier};
\node[box, draw=axiom-gray, fill=axiom-gray!5] (N2) at (0,-3.3) {Network\\{\scriptsize diffusion}};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (W2) at (3.5,-3.3) {Witness\\{\scriptsize PWV set}};
\draw[arrow] (W2) -- node[above, font=\scriptsize] {PWV set} (N2);
\draw[arrow] (N2) -- node[above, font=\scriptsize] {diffusion} (Q2);

\node[box, draw=green!60, fill=green!8] (CAN) at (-3.5,-4.8) {Canonical PWV Set};
\draw[arrow] (Q2) -- node[right, font=\scriptsize] {first-seen lock} (CAN);
\end{tikzpicture}
\caption{Pull-Then-Push Flow --- Query triggers diffusion, first response becomes canonical. The query is the trigger. The first response is the truth. No confirmation needed.}
\end{figure}
```

### 18.2 Complete PWV Creation Flow

**Step 1: Query Initiation.** Validator\_Q pays 1 AXC (redistributed to PWV set), generates unique `query_id`, propagates via fanout (fanout=3, TTL=10).

**Step 2: Propagation to Real Witnesses.** Query reaches real witnesses (A, B, C for k=3) through network diffusion. Each receives `query_id` independently. Source obscured by propagation.

**Step 3: PWV Set Generation (Deterministic).** Each real witness generates a PWV set using deterministic decoy selection.

#### Deterministic Decoy Selection (Normative)

**(18.2-N1)** Decoy selection MUST be deterministic per `(tx_id, epoch_id, witness_pk)`:

```
epoch_id   = floor(Now() / DECOY_EPOCH) * DECOY_EPOCH
preimage   = Hash(tx_id || epoch_id)
seed_proof = Sign(witness_sk, preimage)
seed       = Hash(seed_proof)
```

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `DECOY_EPOCH` | 24 hours | Coarse time bucket to prevent timing manipulation |

**(18.2-N2)** `epoch_id` MUST use coarse-grained 24h buckets aligned to a fixed boundary.

**(18.2-N3)** Member ordering MUST be deterministically shuffled using a derived seed.

**(18.2-N4)** The seed is unpredictable before publication because `seed_proof` requires the witness's private key. After publication, anyone can verify `seed_proof` binds `(tx_id, epoch_id)`.

**PWV Set Composition:** Includes self + (k \* 5 - 1) deterministic decoys. For k=3: 1 real + 14 decoy = 15 per witness. For k=5: 1 real + 24 decoy = 25 per witness.

**Step 4: PWV Set Return.** Real witnesses return PWV sets via diffusion (NOT direct). Validator\_Q does not know which witness sent which set.

**Step 5: First Response Wins (Canonical Set Lock).** Validator\_Q receives the first PWV set and locks it as canonical:

1. Mark set as CANONICAL for this `query_id`
2. Record `canonical_lock_time`
3. Reject all subsequent PWV sets with same `query_id`
4. Suppress duplicate propagation (see Section 18.4)

Subsequent sets are rejected at Validator\_Q (already locked), suppressed at forwarders (deduplication), and not generated by remaining witnesses (if they learn canonical exists). This suppression mechanism prevents intersection leakage (Section 18.4).

**Step 6: PWV Set Notification (Direct).** Validator\_Q directly notifies all 15 PWV members. Machine-level: real witnesses know they have transaction data, decoys know they do not. Operator-level: all operators see "PWV participation request" with no indication of real vs decoy status.

#### 18.2.1 From Diffusion to Direct Addressing

Once Validator_Q receives the canonical PWV set, the protocol transitions from **Stochastic Diffusion** to **Deterministic Routing**.

**Phase Transition:**

| Phase | Method | Purpose |
|-------|--------|---------|
| **Discovery** (Steps 1-5) | Diffusion (fanout) | Find Real Witnesses without knowing who they are |
| **Execution** (Step 6) | Direct P2P | Notify known PWV members efficiently |

**Why Direct Notification:**

1. **Bandwidth Conservation** -- Prevents "Echo Effect" where the same list bounces around indefinitely
2. **Immediate Readiness** -- PWV members know instantly they need to prepare for witnessing
3. **Traffic Convergence** -- Network only "vibrates" during inquiry; once PWV set is identified, traffic narrows to exactly S nodes

**The "You Are Selected" Packet:**

Each PWV member receives a direct notification containing:
- The transaction identifier (`tx_id`)
- The canonical PWV set (so each member knows the full list)
- The query timestamp for TTL enforcement

#### Direct Notification Reliability (Normative)

**(18.4-N1) Bounded Retry**

The querier SHOULD perform bounded retries when sending direct PWV member notifications:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **DIRECT_NOTIFY_MAX_RETRY** | 5 | Maximum delivery attempts |
| **DIRECT_NOTIFY_BACKOFF_BASE** | 2 seconds | Exponential backoff base |

```
for i in 0..DIRECT_NOTIFY_MAX_RETRY-1:
  ok = SEND(notification, endpoint)
  if ok: return true
  sleep(DIRECT_NOTIFY_BACKOFF_BASE * (2^i))
return false
```

**(18.4-N2) Constrained Fallback: Targeted Diffusion**

If direct delivery repeatedly fails, the querier MAY use **targeted diffusion**:

| Parameter | Value | Constraint |
|-----------|-------|------------|
| **TARGETED_DIFFUSION_FANOUT** | 3 | MUST be small |
| **TARGETED_DIFFUSION_TTL** | 2 | MUST be small |

```
Targeted diffusion constraints:
- Fanout MUST be small (e.g., 3)
- TTL MUST be small (e.g., 1--2)
- MUST NOT become global diffusion
```

**Rationale:** NAT, transient outages, and email delays can prevent direct delivery. Bounded retry improves liveness. Constrained targeted diffusion avoids expanding the attack surface into network-wide set amplification.

**Verification (axiom-core.elf):**

PWV members verify the notification:
- Is the PWV set format valid?
- Is my public key included in the set?
- Is the timestamp within acceptable range?

If verification passes, the validator enters **Ready** state for potential judicial participation.

**Scaling Impact:**

```
Discovery Phase: O(N) diffusion -- network-wide propagation
                      ->"
              [Canonical PWV Set Locked]
                      ->"
Execution Phase: O(S) direct -- only S nodes notified
                 where S = k - 5 (e.g., 15 for k=3)
```

This ensures that sublinear scaling is not just theoretical but **physically enforced**. The massive network only activates during discovery; once the PWV set is identified, communication narrows to exactly S nodes.

#### 18.2.2 Query Economic Bounds and Validation

**Constitutional Constraint (White Paper Section J.5):**

> Economic cost: 1 AXC per query (non-refundable)

This cost serves multiple critical functions in the protocol.

**Purpose 1: Attack Cost Amplification**

Without economic cost, mass deanonymization becomes free:

```
Attack without cost:
- 1000 queries - 0 AXC = 0 AXC
- 10000 queries - 0 AXC = 0 AXC
- Unlimited surveillance at zero cost

Attack with 1 AXC cost:
- 1000 queries - 1 AXC = 0.1 AXC
- 10000 queries - 1 AXC = 1.0 AXC
- 100000 queries -> rate limits prevent this
```

The fee creates a **financial floor** below which mass surveillance becomes economically bounded.

**Purpose 2: Network Amplification Protection**

Each query propagates through the network via bounded diffusion (fanout=3, TTL=10).

Without fee verification:
- Attacker creates 10,000 valid-looking queries
- Each propagates to ~59,000 nodes (3^10)
- Total network load: 590,000,000 messages
- Attack cost: ~0 (only signature computation)

With fee verification:
- Each query requires proof of 1 AXC payment
- 10,000 queries = 1.0 AXC + rate limits
- Validators reject queries without valid payment
- Attack becomes economically bounded and traceable

**Purpose 3: Validator Resource Protection**

Query budget enforcement (White Paper Section 4.12.3):

> "Validators enforce local, finite query budgets for bounded witness discovery."

This prevents individual queriesrs from exhausting validator resources.

**Recommended query budget limits:**

| Time Window | Max Queries per Querier | Rationale |
|-------------|-------------------------|-----------|
| 1 hour | 100 | Prevents burst spam while allowing legitimate recovery |
| 24 hours | 1,000 | Accommodates sustained investigation |
| 7 days | 10,000 | Generous headroom for large-scale auditing |

**Implementation Note:** Validators MAY adjust these limits based on local resources and network conditions, but limits MUST remain finite.

**Query Message Structure:**

```rust
struct QueryMsg {
    query_id: Hash,           // Unique query identifier
    target_wallet: PubKey,    // Wallet being queried
    querier_pubkey: PubKey,   // Entity making the query
    ttl: u8,                  // Propagation depth limit (1-10)
    timestamp: UnixTime,      // Query creation time
    
    // Fee payment proof (REQUIRED)
    payment: QueryPaymentProof,
    
    // Signature over all above fields
    querier_sig: Signature,
}

struct QueryPaymentProof {
    scheme: "stamp.v1",       // Payment scheme identifier
    stamp_id: string,         // Unique payment identifier
    payer_pk: PubKey,         // Must match querier_pubkey
    issuer_pk: PubKey,        // Validator who issued stamp
    issued_at: UnixTime,      // When stamp was created
    expires_at: UnixTime,     // Stamp validity window
    stamp_sig: Signature,     // Issuer signature
    payer_sig: Signature,     // Binds stamp to specific query
}
```

**Query Validation Logic:**

Every validator receiving a query MUST validate:

```python
function VALIDATE_QUERY(q: QueryMsg) -> bool:
    # Step 1: Signature verification
    if not verify_signature(q.querier_pubkey, q.querier_sig, q):
        return False
    
    # Step 2: TTL bounds check
    if q.ttl < 1 or q.ttl > PROPAGATION_TTL_MAX:
        return False
    
    # Step 3: Timestamp freshness (prevent replay)
    if q.timestamp < now() - QUERY_MAX_AGE:
        return False
    
    if q.timestamp > now() + QUERY_CLOCK_SKEW:
        return False
    
    # Step 4: Payment proof verification
    if not CHECK_QUERY_PAYMENT(q):
        return False
    
    # Step 5: Local query budget enforcement
    if exceeds_local_query_budget(q.querier_pubkey):
        return False
    
    return True
```

**Fee Payment Workflow:**

Before querying:
1. Querier obtains payment stamp from any validator (pays 1 AXC)
2. Validator issues signed `QueryPaymentProof`
3. Querier binds stamp to query via `payer_sig`
4. Query propagates with embedded payment proof

During validation:
1. Each validator verifies stamp issuer signature
2. Each validator verifies payer binding signature
3. Each validator checks stamp hasn't been reused (replay protection)
4. Each validator enforces local budget limits

**Why Stamp-Based Instead of Direct Burn:**

Direct burn would require:
- Querier broadcasts burn transaction
- Wait for transaction witnessing (~3-10 seconds)
- Then send query with tx_id reference

Stamp-based approach allows:
- Immediate query after payment (no waiting)
- Validator monetization (stamp sales)
- Simpler proof verification (signature only, no transaction lookup)

**Attack Cost Summary:**

| Attack | Without Fee Verification | With Fee Verification |
|--------|--------------------------|----------------------|
| 1000 queries | ~0 AXC | 0.1 AXC |
| 10000 queries | ~0 AXC | 1.0 AXC + rate limits |
| 100000 queries | ~0 AXC | Blocked by budget limits |
| Network load | Unlimited amplification | Economically bounded |

**Design Principle:**

Mass surveillance MUST be expensive enough to bound state-level actors while remaining affordable for legitimate judicial queries.

At 1 AXC per query:
- Single query: Negligible cost
- 100 queries: Affordable for investigation
- 100,000 queries: Requires significant capital + multiple identities + sustained time

This creates a **graduated cost curve** where legitimate use is cheap and mass surveillance is expensive.

### 18.3 Privacy Properties

**What attackers can observe:**

1. **Monitoring Validator_Q:**
   - Validator_Q sent a query
   - Validator_Q notified 15 validators: [A, D1...D12]
   - Cannot determine: Which 3 are real witnesses

2. **Monitoring network traffic:**
   - Query propagation (obscured source/destination)
   - PWV set returns (obscured origin)
   - Direct notifications (clear, but role ambiguous)

3. **Compromising decoy validator D1:**
   - D1 knows: I am in PWV set with [A, D2, D3, ..., D12]
   - D1 knows: I am a decoy (no transaction data)
   - D1 does NOT know: Which others are real witnesses

**What attackers CANNOT determine:**
- Which specific validators witnessed the original transaction
- Whether B and C exist (their PWV sets were ignored)
- Source of the PWV set adopted by Validator_Q

#### 18.3.1 PWV Seed Security Against Precomputation

**Design Question:**

Can an attacker precompute future PWV sets to enable instant deanonymization when a query appears?

**Short Answer:**

No. The PWV generation mechanism implements a **Verifiable Random Function (VRF)** that prevents precomputation.

**VRF Construction (Appendix P.4, Lines 8933-8935):**

```python
epoch_id  = CURRENT_EPOCH_ID(Now())          # 24h windows
preimage  = Hash(UTF8(q.tx_id) || I64(epoch_id))
seed_proof = Sign(witness_sk, preimage)      # VRF Prove
seed      = Hash(seed_proof)                 # VRF Output
```

**Security Properties:**

| Property | Implementation |
|----------|----------------|
| **Unpredictability** | `seed_proof` requires `witness_sk` (secret) |
| **Verifiability** | Anyone can verify signature with `witness_pk` |
| **Uniqueness** | Each `(tx_id, epoch_id, witness_pk)` -> one seed |
| **Binding** | Cannot reuse across queries or epochs |

**Attack Analysis:**

An attacker attempting precomputation knows:

| Information | Public? | Can Predict? |
|-------------|---------|--------------|
| `tx_id` | After query sent | *" Yes (or enumerate) |
| `epoch_id` | Predictable (24h) | *" Yes |
| `witness_pk` | Public validator list | *" Yes |
| `preimage = Hash(tx_id \|\| epoch_id)` | Derivable | *" Yes |

But CANNOT obtain:

| Information | Why Impossible |
|-------------|----------------|
| `witness_sk` | **Private key** (secret) |
| `seed_proof = Sign(witness_sk, preimage)` | **Cannot forge signature** |
| `seed = Hash(seed_proof)` | **Depends on unforgeable signature** |
| PWV member list | **Derived from unpredictable seed** |

**Precomputation Attack Attempt (Fails):**

```
Attacker tries to precompute PWV sets for tomorrow:

Step 1: Predict epoch_id for tomorrow
  -> epoch_id = floor(tomorrow / 24h) * 24h
  -> *" Computable

Step 2: Enumerate possible tx_id values
  -> *" Finite space, enumerable

Step 3: Compute preimage for each
  -> preimage = Hash(tx_id || epoch_id)
  -> *" Computable

Step 4: Compute seed_proof
  -> seed_proof = Sign(witness_sk, preimage)
  -> *- IMPOSSIBLE (don't have witness_sk)
  -> *- CANNOT FORGE SIGNATURE

Step 5: Compute seed
  -> *- BLOCKED (depends on Step 4)

Step 6: Generate PWV members
  -> *- BLOCKED (depends on Step 5)

ATTACK FAILS AT STEP 4.
```

**Security Assumption:**

Forging `seed_proof` is equivalent to breaking the signature scheme.

This is assumed computationally infeasible (Ed25519, ECDSA, Dilithium, etc.).

If an attacker could forge signatures, they could:
- Impersonate validators
- Sign fake transactions
- **Break the entire system** (not just PWV)

Therefore, PWV precomputation security reduces to signature security (standard assumption).

**Determinism After Publication:**

Once witness publishes `seed_proof`, verification is deterministic:

```python
function VALIDATE_PWVSET(s: PWVSetMsg) -> bool:
    # Reconstruct preimage
    preimage = Hash(UTF8(s.tx_id) || I64(s.epoch_id))
    
    # Verify seed_proof is valid signature by witness
    MUST Verify(s.witness_pk, preimage, s.seed_proof)
    
    # Implicitly validates:
    # - seed = Hash(seed_proof) is correctly derived
    # - PWV members correctly sampled from seed
    
    return true
```

**Anyone can verify:**
1. `seed_proof` is valid signature by claimed witness
2. Therefore `seed` is correctly derived
3. Therefore PWV members are correctly sampled

This combines:
- **Unpredictability** before publication (VRF security)
- **Verifiability** after publication (signature verification)

**Why VRF Instead of Alternatives:**

**Alternative 1: Pure Random (Non-Deterministic)**

```python
# REJECTED
seed = SecureRandomBytes(32)
```

Problems:
- Different validators generate different PWV sets
- No way to verify correctness
- Witness could generate many sets, cherry-pick favorable one

**Alternative 2: Hash of Public Data (Precomputable)**

```python
# REJECTED (Vulnerable)
seed = Hash(tx_id || epoch_id || witness_pk)
```

Problems:
- All inputs public
- Attacker can precompute for all `(tx_id, epoch_id, witness_pk)` tuples
- **Instant deanonymization** when query appears

**Alternative 3: VRF (Current Design)**

```python
# CORRECT
seed_proof = Sign(witness_sk, Hash(tx_id || epoch_id))
seed = Hash(seed_proof)
```

Advantages:
- *" Unpredictable before publication (depends on secret key)
- *" Verifiable after publication (signature checkable)
- *" Deterministic given seed (reproducible sampling)
- *" Bound to specific query and epoch (non-reusable)

**Optional Enhancement: Domain Separation**

Current implementation:

```python
seed_proof = Sign(witness_sk, preimage)
```

Defense-in-depth improvement (optional):

```python
seed_proof = Sign(witness_sk, SIGMSG("PWV_SEED", preimage))
```

Benefit:
- Prevents signature reuse across different protocol contexts
- Standard cryptographic best practice

Security impact:
- **Low** (current design already secure)
- Signatures bound to unique `preimage` (includes `tx_id`)
- Could be added in future revision

**Summary:**

| Security Property | Status |
|-------------------|--------|
| Precomputation resistance | *" Achieved (VRF with signature) |
| Verification | *" Achieved (signature verification) |
| Determinism | *" Achieved (deterministic sampling) |
| Binding | *" Achieved (query/epoch specific) |
| Assumption | Signature security (standard) |

The PWV seed generation is cryptographically sound and prevents precomputation attacks.

### 18.4 Intersection Leakage Risk Analysis

This section quantifies the security risk of PWV set intersection leakage and defines mitigation mechanisms.

### 18.4.1 The Leakage Mechanism

**Problem:** When querier receives multiple PWV sets, intersection analysis reveals real witnesses.

**Example:**

```
Witness A generates: Set_A = {A, D1, D2, D3, ..., D12}
Witness B generates: Set_B = {B, E1, E2, E3, ..., E12}
Witness C generates: Set_C = {C, F1, F2, F3, ..., F12}

If querier receives all three sets:

Intersection analysis:
- A appears only in Set_A -> A is real witness
- B appears only in Set_B -> B is real witness  
- C appears only in Set_C -> C is real witness

Result: Full deanonymization of all k=3 real witnesses
```

**Critical observation:**

The risk driver is NOT "can the query reach witnesses?"  
The risk driver is:

> **Can the querier receive >=2 distinct PWV sets before network suppression locks in?**

### 18.4.2 Suppression Rules (Mitigation)

To prevent multiple-set arrival, the protocol **REQUIRES** suppression at three levels.

> **HARD PROTOCOL RULE:** These are NOT optimizations or suggestions. They are **security conditions**. Implementations that treat suppression as optional expose users to deanonymization attacks with probability approaching certainty.

**Rule 1: Real Witness Behavior (MANDATORY)**

> Upon receipt of a valid DWP set for a given `query_id`, a validator **MUST NOT** generate or propagate any additional sets for that query.

```
If witness learns canonical PWV set exists for query_id:
  - Do NOT generate another PWV set
  - Do NOT propagate additional sets
  
Implementation:
- Witnesses monitor for canonical set notifications
- Once detected, cease PWV generation for that query_id
- Canonical notification sent by querier (Step 6, Section 18.2)
```

**Rule 2: Forwarder Behavior (MANDATORY -- Passive Deduplication)**

#### Forwarder Deduplication Normative Requirements

**(18.4.2-N1) Forwarder Deduplication Is Mandatory**

A forwarder MUST perform passive deduplication on QueryID to prevent duplicate propagation and to mitigate intersection leakage amplification.

**(18.4.2-N2) Deduplication Storage MUST Be Bounded**

Any deduplication structure (e.g., `forwarder_seen_query`) MUST be bounded by a hard maximum. It MUST NOT grow without limit.

| Parameter | Value | Purpose |
|-----------|-------|---------|
| **FORWARDER_DEDUP_MAX_ENTRIES** | 100,000 | Maximum cache entries |
| **FORWARDER_DEDUP_RETENTION** | 48 hours | TTL for cache entries |

**(18.4.2-N3) Eviction Strategy (LRU/TTL) Is Required**

The bounded deduplication cache MUST implement an eviction strategy. LRU and/or TTL eviction are acceptable. Implementations SHOULD combine LRU + TTL eviction.

**(18.4.2-N4) Fail-Safe Under Resource Pressure**

If the deduplication cache is full and a QueryID is unseen, a forwarder MAY drop the query to protect process survival. In resource pressure conditions, **survival is prioritized over propagation**.

```
FORWARDER_SOFT_DROP_MODE = true  # Drop queries when cache full
```

**(18.4.2-N5) Optional Probabilistic Front-Layer**

A forwarder MAY use a probabilistic filter (Bloom/Cuckoo) as a pre-filter to reduce memory load. If used, it MUST be periodically rotated and MUST still have bounded memory. It MUST NOT be used as an unbounded sink.

**Rationale:** Without bounded memory, an attacker can stream unique QueryIDs to force OOM (Out of Memory). Suppression also reduces intersection information gain by preventing multiple PWV set paths from reaching a querier.

```
If validator already forwarded PWV set for query_id:
  - Ignore all subsequent PWV sets with same query_id
  - Do NOT re-propagate duplicates
  
Implementation:
- Maintain bounded cache: forwarder_seen_query[query_id] = timestamp
- Deduplicate based on query_id
- Cache bounded to FORWARDER_DEDUP_MAX_ENTRIES
- TTL: FORWARDER_DEDUP_RETENTION (48 hours)

Mechanism: PASSIVE deduplication
- No active suppression signal broadcast
- Each forwarder independently deduplicates
- Query_id serves as natural deduplication key
```

**Rule 3: Querier Behavior (MANDATORY)**

```
Upon receiving first PWV set:
  - Mark as CANONICAL for this query_id
  - Reject all subsequent PWV sets
  - Notify PWV members immediately (triggers Rule 1)
  
Implementation:
- Lock: canonical_set[query_id] = first_received_set
- Lock duration: PERMANENT for this query_id
- Reject later sets at application level
- Send notification to all PWV members (direct, not diffusion)
```

**Outcome:**

These three rules transform discovery from:
- "Guaranteed if query reaches witnesses" (without mitigation)
- To "rare timing accident" (with mitigation)

### 18.4.2.1 Implementation Enforcement & Economic Reality

**Three critical mechanism questions:**

**Q1: Suppression propagation mechanism?**

A: **PASSIVE deduplication, NOT active broadcast.**

```
NOT implemented:
+ Active suppression signal broadcast
+ Network-wide suppression notification

Actually implemented:
*... Each forwarder independently deduplicates by query_id
*... Forwarders maintain local cache: forwarded_queries[query_id]
*... Duplicate sets ignored at each hop
*... No coordination required between forwarders
```

**Q2: Canonical lock duration?**

A: **PERMANENT for this query_id.**

```
Duration: PERMANENT (no TTL expiration)

Rationale:
- query_id is unique per JFP query
- No legitimate reason to "unlock" later
- Prevents querier from collecting sets over time

Memory management:
- Old locks can be archived after JFP resolves (weeks/months)
- Canonical decision is permanent for this query
```

**Q3: If querier maliciously doesn't suppress?**

A: **Protocol cannot prevent, but forwarder deduplication still helps.**

```
Scenario: Malicious querier (anti-privacy stance, surveillance, political targeting)

What protocol CANNOT do:
+ Detect querier collected multiple sets (local action)
+ Punish querier for non-compliance (no enforcement)

What STILL helps:
*... Forwarder deduplication reduces multi-set probability (primary defense)
*... Query cost (1 AXC) still applies
*... Risk reduced from ~100% to ~0.5-5% (even with malicious querier)

Critical insight: Forwarder layer is primary defense.
Querier layer is secondary (economic preference, not enforcement).
```

**Why suppression cannot be cryptographically enforced:**

Protocol has no way to detect or punish:
- Querier who collects multiple sets (happens locally)
- Forwarder who re-propagates duplicates (looks like normal propagation)
- Witness who generates multiple sets (indistinguishable from network delay)

**Economic reality -- why implementation depends on incentives:**

Implementation rates and reasoning (see Section 18.4.8 for detailed table):

**Validators (forwarders): HIGH compliance (>90%)**
- Economic: Bandwidth saving (~10 lines of code, standard practice)
- Technical: Already common in distributed systems (spam prevention)
- Default: Open-source implementations will include this
- No ideological barrier: Waste bandwidth for no gain

**Queriers: UNCERTAIN compliance (30-70%)**
- Economic incentive weak (marginal speed benefit)
- Possible ideological resistance (anti-privacy, surveillance)
- BUT forwarder layer protects even if querier malicious

**Witnesses: HIGH compliance (>90%)**
- Self-preservation: Reduces own exposure risk
- Simple logic: Verify if canonical exists via notification
- Self-interest aligned with protocol goals

**Design philosophy:**

This aligns with Lambda's principle:

> "Make attacks expensive and probabilistic,  
> not impossible through perfect enforcement."

**Key assumption for risk estimates (Section 18.4.4):**

The 0.5-5% risk estimate assumes validator (forwarder) compliance.

This is reasonable because:
- Economic incentive (bandwidth saving)
- Technical incentive (standard practice)
- Open-source default (included in reference implementation)
- No ideological barrier (waste bandwidth for no gain)

**Validator compliance is the key assumption.**  
**Querier compliance is "nice to have" but not critical.**

#### 18.4.2.2 Targeted Diffusion Loop Prevention

**Context:**

After querier adopts a canonical PWV set, suppression rules trigger targeted diffusion to notify PWV members (Section 18.4.2, Rule 1, Step 6).

**Attack Vector:**

A malicious PWV member can:
1. Receive `TARGETED_DIFFUSE_TO_MEMBER` message
2. Never send ACK (silent refusal)
3. Cause forwarder to retransmit indefinitely
4. Create local bandwidth exhaustion

**Design Principle:**

Targeted diffusion MUST be bounded by:
- Message-level deduplication
- Retry count limits
- Exponential backoff
- Time-based eviction

**Forwarder State:**

Each forwarder maintains a bounded cache:

```rust
struct TargetedForwardingCache {
    entries: HashMap<(Hash, PubKey), ForwardingEntry>,
    max_size: usize,  // e.g., 10,000 entries
}

struct ForwardingEntry {
    msg_id: Hash,              // Inner message identifier
    target_member: PubKey,     // Target PWV member
    forward_count: u8,         // Retry attempts made
    last_forward_time: UnixTime,
    first_forward_time: UnixTime,
}
```

**Forwarding Decision Logic:**

```python
MAX_TARGETED_FORWARDS = 3
CACHE_RETENTION = 24h

function should_forward_targeted(
    cache: TargetedForwardingCache,
    msg_id: Hash,
    target: PubKey
) -> ForwardDecision:
    
    key = (msg_id, target)
    
    # Rule 1: Check deduplication cache
    if entry = cache.get(key):
        
        # Rule 2: Hard limit on retries
        if entry.forward_count >= MAX_TARGETED_FORWARDS:
            log_warn("Max retries reached for target")
            return DENY
        
        # Rule 3: Exponential backoff
        required_delay = backoff_delay(entry.forward_count)
        elapsed = now() - entry.last_forward_time
        
        if elapsed < required_delay:
            return DENY  # Backoff not expired
        
        # Rule 4: Update and allow
        entry.forward_count += 1
        entry.last_forward_time = now()
        return ALLOW
    
    # First attempt: create new entry
    cache.insert(key, ForwardingEntry {
        msg_id: msg_id,
        target_member: target,
        forward_count: 1,
        last_forward_time: now(),
        first_forward_time: now(),
    })
    
    return ALLOW

function backoff_delay(attempt: u8) -> Duration:
    match attempt:
        1 => 5 minutes    # First retry
        2 => 15 minutes   # Second retry
        3 => 45 minutes   # Third retry (final)
```

**Retry Schedule:**

| Attempt | Delay from Previous | Cumulative Time | Purpose |
|---------|-------------------|-----------------|---------|
| 1 (initial) | Immediate | 0m | First delivery attempt |
| 2 | +5 min | 5m | Handle transient delivery failure |
| 3 | +15 min | 20m | Handle temporary member offline |
| 4 | +45 min | 65m | Final attempt before giving up |
| 5+ | Stop | -- | Declare member non-responsive |

**After Maximum Retries:**

```python
# Stop forwarding to this target for this message
# DO NOT propagate to other forwarders (prevent amplification)

log_warn(
    "Member {} non-responsive after {} attempts over {} minutes. \
     Stopping targeted diffusion for message {}.",
    target_member,
    MAX_TARGETED_FORWARDS,
    cumulative_time,
    msg_id
)

# Optional: Track non-responsive members
reputation_tracker.record_non_responsive(target_member, msg_id)
```

**Cache Management:**

Time-based cleanup:

```python
function cleanup_targeted_cache(cache: TargetedForwardingCache):
    cutoff = now() - CACHE_RETENTION  # 24 hours
    
    cache.retain(|_, entry| {
        entry.first_forward_time > cutoff
    })

# Run periodically
schedule_periodic(1.hour, cleanup_targeted_cache)
```

Size-based eviction (if cache exceeds max_size):

```python
function enforce_cache_size_limit(cache: TargetedForwardingCache):
    if cache.len() > cache.max_size:
        # Evict oldest entries (LRU policy)
        to_evict = cache.len() - cache.max_size
        
        entries = cache.entries.sort_by(|e| e.first_forward_time)
        
        for i in 0..to_evict:
            cache.remove(entries[i].key)
```

**Attack Cost Analysis:**

Without loop prevention:
- Attacker cost: 1 message + silence
- Network cost: Unlimited retransmissions
- Amplification factor: 

With loop prevention:
- Attacker cost: 1 message + silence
- Network cost: 4 messages maximum (1 initial + 3 retries)
- Amplification factor: 4- (bounded)
- Time window: ~65 minutes total

**Integration with PWV Suppression:**

Targeted diffusion loop prevention is **independent** of PWV suppression rules:

| Mechanism | Purpose | Protects Against |
|-----------|---------|------------------|
| PWV Suppression (Rules 1-3) | Prevent race condition discovery | Multiple PWV set intersection |
| Loop Prevention (18.4.2.2) | Prevent bandwidth exhaustion | Selective non-ACK amplification |

Both mechanisms MUST be implemented.

**Security Guarantee:**

Even if ALL PWV members refuse to ACK:
- Each forwarder sends at most 4 messages per member
- Total network cost: `4 - k - 5 = 60 messages` (for k=3)
- Attack is bounded and traceable
- No unbounded resource consumption

**Design Rationale:**

**Q: Why 3 retries instead of unlimited?**

A: Targeted diffusion is a **best-effort notification**, not a **guaranteed delivery** mechanism. After 3 attempts over ~65 minutes:
- Transient network issues would have resolved
- Temporarily offline members would have reconnected
- Permanently offline/unresponsive members are identifiable

Continuing beyond 3 retries provides no additional benefit while consuming unbounded resources.

**Q: Why exponential backoff?**

A: Linear backoff (e.g., 5m, 5m, 5m) would:
- Retry too quickly for offline members (wasted bandwidth)
- Not provide enough time for temporary issues to resolve

Exponential backoff (5m, 15m, 45m) balances:
- Quick response for transient failures
- Patient waiting for temporary offline
- Eventual termination for permanent non-response

**Q: Why not use ACK timeout instead of retry count?**

A: ACK timeout cannot distinguish:
- "Member offline temporarily" -> should retry
- "Member refusing to ACK" -> should stop retrying

Retry count provides clear termination regardless of reason.

### 18.4.3 Probability Model

**Parameters:**

Let:
- `k` = number of real witnesses (typically 3-5)
- `S` = number of distinct PWV sets querier receives
- `p_reach` = probability query reaches a given real witness
- `p_return` = probability witness's response reaches querier before suppression
- `q = p_reach - p_return` = probability single witness successfully contributes distinct set

**Distribution:**

```
S ~ Binomial(k, q)

This approximation assumes:
- Each witness independently decides whether to return set
- Success probability q is similar across witnesses
- Suppression makes actual S even lower than binomial predicts
```

**Discovery conditions:**

```
S <= 1: No discovery (only one set, no intersection possible)
S = 2: Identify 2 real witnesses (unique elements reveal them)
S = 3 (for k=3): Full deanonymization (all witnesses revealed)
```

**Probability formulas:**

```
P(discover >=1 real witness) = P(S >= 2)
                             = 1 - (1-q)^k - k*q*(1-q)^(k-1)
                             = 1 - P(S=0) - P(S=1)

P(full deanonymization) = P(S = k)
                        = q^k

For k=3:
  P(S >= 2) = 1 - (1-q) - 3q(1-q)2
  P(S = 3) = q
```

### 18.4.4 Mitigation Effectiveness

**Impact of suppression on q:**

Without mitigation:
- `p_return` >= high (every response propagates freely)
- `q` could approach `p_reach` >= 90%

With suppression (Rules 1-3):
- `p_return` >= low (only first response propagates before lock)
- `p_return` becomes "probability second response arrives within race window "

**Estimated risk levels:**

```
[THEORETICAL ESTIMATE - Requires empirical validation]

With suppression rules enforced:
- q >= 1% to 10% (depends on network timing and )
- P(S >= 2) >= 0.5% to 5% per JFP query
- P(S = 3) < 0.1% for k=3

Expected discovery events per 100 JFP queries:
- Best case (q=1%): ~0.5 events / 100 JFP
- Typical (q=2-5%): ~2-5 events / 100 JFP  
- Worst case (q=10%): ~5 events / 100 JFP
```

**Interpretation:**

Discovery is **rare but not impossible**.  
This is acceptable because:
- Query cost (1 AXC) makes mass queries expensive
- Discovery reveals identity only to querier, not public
- Witnesses can still refuse cooperation (DWP >=  forced disclosure)

### 18.4.5 Race Window ()

**Definition:**

```
 = Time between "querier receives first PWV set" 
    and "suppression wave dominates network"
```

**Relationship to risk:**

```
Smaller  -> more effective suppression -> lower q -> lower P(S >= 2)
Larger  -> less effective suppression -> higher q -> higher P(S >= 2)
```

**Factors affecting :**

1. **Network latency distribution**
   - Email carrier: p50 >= 1-5s, p95 >= 10-30s
   - Latency variance creates race opportunities

2. **Propagation parameters**
   - Fanout f=3, TTL=10 (Section 18.5)
   - Suppression propagates at same speed as query

3. **Canonical lock timing**
   - How quickly querier processes first set
   - How quickly Rule 3 notification reaches witnesses

4. **Forwarder deduplication efficiency**
   - Cache hit rate for query_id
   - Deduplication latency

**Tunable parameter:**

 is NOT a protocol constant. It emerges from implementation choices:
- Faster canonical lock -> smaller  -> better protection
- Slower suppression notification -> larger  -> higher risk

**Recommendation:**

Implementations MUST minimize  through:
- Immediate canonical lock upon first set receipt
- Fast PWV notification (Step 6 MUST trigger Rule 1 within the same tick cycle)
- Efficient forwarder deduplication

### 18.4.6 Design Rationale

**Why accept probabilistic protection instead of perfect anonymity?**

1. **No single point of failure**
   - Perfect anonymity systems require trusted mixnets or anonymity servers
   - Lambda has no such dependencies

2. **Scalable with witness count (k)**
   - Larger k -> exponentially harder to deanonymize
   - P(S = k) = q^k decreases rapidly

3. **Costly to attack**
   - Each query costs 1 AXC
   - 1000 queries = 0.1 AXC
   - Expected discoveries: 5-50 (if P(S>=2) = 0.5%-5%)
   - Cost per discovery: 0.002-0.02 AXC

4. **Discovery >=  compromise**
   - Querier learns witness identity
   - But witnesses can still refuse cooperation
   - JFP still requires unanimous vote (Section 8.1 Rule 6)

5. **Alignment with Lambda philosophy**

```
Lambda design principle:
"Make attacks expensive and probabilistic,
 not impossible through perfect cryptography."

DWP provides:
- Probabilistic anonymity (95%-99.5% per query)
- Economic cost barrier (1 AXC per attempt)
- No trusted third parties
- Graceful degradation (not binary failure)
```

**Trade-off accepted:**

Perfect witness anonymity would require:
- Trusted mixnet operators (centralization risk)
- Or complex multi-round protocols (liveness risk)
- Or synchronous network assumptions (partition intolerant)

DWP chooses **practical robustness** over **theoretical perfection**.

### 18.4.7 Suppression Flow Diagram

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=2.2cm, minimum height=0.6cm, align=center, font=\scriptsize},
    arrow/.style={->, thick, >=stealth},
    note/.style={font=\scriptsize, text=axiom-gray, align=left}
]
% Query
\node[box, draw=axiom-blue, fill=axiom-blue!10] (Q) at (0,0) {JFP Query\\{\tiny query\_id}};
\node[box, draw=axiom-gray, fill=axiom-gray!5, minimum width=6cm] (NET) at (0,-1.5) {Network diffusion (f=3, TTL=10)};
\draw[arrow] (Q) -- (NET);

% Three witnesses
\node[box, draw=axiom-blue, fill=axiom-blue!15] (WA) at (-3.5,-3.2) {W\_A\\{\tiny generate PWV\_A}};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (WB) at (0,-3.2) {W\_B\\{\tiny generate PWV\_B}};
\node[box, draw=axiom-blue, fill=axiom-blue!15] (WC) at (3.5,-3.2) {W\_C\\{\tiny generate PWV\_C}};
\draw[arrow] (NET) -- (WA);
\draw[arrow] (NET) -- (WB);
\draw[arrow] (NET) -- (WC);

% Querier receives first
\node[box, draw=green!60, fill=green!8, minimum width=4cm] (CAN) at (0,-5.2) {Querier receives Set\_A first\\\textbf{CANONICAL}};
\draw[arrow] (WA) -- (CAN);
\draw[arrow, dashed, red!50] (WB) -- node[right, font=\tiny] {late} (CAN);
\draw[arrow, dashed, red!50] (WC) -- node[right, font=\tiny] {late} (CAN);

% Suppression
\node[box, draw=red!50, fill=red!5, minimum width=2.5cm] (REJ) at (-3.5,-7.2) {Reject Set\_B/C};
\node[box, draw=axiom-blue, fill=axiom-blue!8, minimum width=3.5cm] (SUP) at (3.5,-7.2) {Suppression wave\\{\tiny R1: witnesses stop}\\{\tiny R2: forwarders dedup}};
\draw[arrow] (CAN) -- node[left, font=\scriptsize] {lock} (REJ);
\draw[arrow] (CAN) -- node[right, font=\scriptsize] {notify} (SUP);

% Timing note
\node[note, anchor=north] at (0,-8.5) {Race window $D$: Set\_B before lock $\to$ risk (S=2). After suppression $\to$ safe (S=1).};
\end{tikzpicture}
\caption{PWV Suppression Flow --- First response becomes canonical, suppression wave prevents duplicates. P(S$\geq$2) depends on race window D.}
\end{figure}
```

**Key insight from this flow:**

Suppression is NOT cryptographic enforcement.  
It is **economic pressure + network physics**:

- Querier wants first set (faster = better for them)
- Forwarders deduplicate (bandwidth saving)
- Witnesses learn canonical exists (no point generating more)
- Network latency variance creates small race window

Security emerges from **aligned incentives**, not forced cooperation.

### 18.4.8 Enforcement Summary

**Critical distinction -- what protocol can and cannot enforce:**

**Protocol CAN enforce (cryptographic):**

| Aspect | Mechanism |
|--------|-----------|
| Transaction format | Core validation rejects invalid |
| Signature validity | Cryptographic verification |
| Atom conservation | Math enforced at protocol level |
| Witness overlap | Core rejects missing overlap (§17.3) |

**Protocol CANNOT enforce (economic incentives only):**

| Aspect | Relies on | Incentive |
|--------|-----------|-----------|
| Forwarder deduplication | Validator choice | Bandwidth saving |
| Querier canonical lock | Querier choice | Speed |
| Witness stop generation | Witness choice | Self-preservation |

**Compliance probability estimates (with reasoning in Section 18.4.2.1):**

| Role | Probability | Key Incentive |
|------|------------|---------------|
| Validators (forwarders) | HIGH (>90%) | Bandwidth saving + standard practice |
| Queriers | UNCERTAIN (30-70%) | Weak economic, possible ideological resistance |
| Witnesses | HIGH (>90%) | Self-preservation, anonymity protection |

**Risk scenarios:**

| Scenario | Behavior | Discovery Risk |
|----------|----------|----------------|
| **Worst-case** (no compliance) | All sets propagate freely | \~50--80\% per query |
| **Best-case** (full compliance) | Only first set propagates | \~0.1--1\% per query |
| **Realistic** (mixed) | Forwarders dedup, some queriers don't suppress | 0.5--5\% per query |

**Design acceptance:**

Lambda accepts that:
- Perfect enforcement is impossible without trusted third parties
- Economic incentives are sufficient for most validators
- Determined adversaries can still attempt attacks (but at cost: 1 AXC per query)
- Probabilistic protection (95-99.5%) is acceptable tradeoff

**This is not a bug, it is a design choice:**

> "Practical robustness with economic incentives  
> beats theoretical perfection with trusted authorities."

### 18.5 Fanout Propagation Mathematics

**Network parameters:**
- Total validators: N = 50,000
- Real witnesses: k = 3
- Fanout factor: f = 3
- Time-to-live: TTL = t

**Maximum theoretical reach (no duplicates):**

```
M(t) = (i=1 to t) f^i = (f^(t+1) - f) / (f - 1)

For f=3:
M(t) = (3^(t+1) - 3) / 2
```

**Probability of reaching at least r real witnesses:**

```
P(>=r) = 1 - (i=0 to r-1) C(k,i) - C(N-k, M-i) / C(N, M)
```

**Numerical results (N=50,000, k=3, f=3):**

| TTL | Max Reach M(t) | P(>=1 witness) | P(>=2 witnesses) |
|-----|----------------|---------------|-----------------|
| 5   | 363            | ~2%           | ~0.01%          |
| 8   | 9,840          | ~45%          | ~10%            |
| 9   | 29,523         | ~80%          | ~63%            |
| 10  | >=50,000        | ~100%         | ~100%           |

**Engineering conclusion:**

- TTL=10 provides reliable witness discovery
- TTL=8-9 may suffice but introduces uncertainty
- TTL=5 insufficient for network size

**Pending verification:**

Mathematical analysis suggests TTL=5 or 8 might suffice with refined probability models. Requires further validation before reducing from current TTL=10 default.

### 18.6 Network Load Analysis

**Worst-case propagation (no deduplication):**

```
Total messages = (i=1 to TTL) f^i

TTL=10, f=3: ~88,000 messages
TTL=15, f=3: ~21,000,000 messages (unacceptable)
```

**Actual propagation (with deduplication):**

- Validators ignore duplicate query_id
- Each validator forwards maximum once
- Actual load: 1,000-10,000 messages (empirical estimate)

**Email gateway capacity:**

- Small payload (~1KB per message)
- Rate limiting enforced
- Deduplication prevents storms
- Well within capability of commodity mail servers

**Safety margin:**

Protocol enforces TTL=10 as hard maximum. Any request for TTL>10 is rejected, preventing exponential explosion.

### 18.7 Subsequent Queries

**If PWV set already exists:**

```
Client: Query tx_id (already has PWV set)
Any PWV member: Return existing PWV set immediately
Result: No propagation required
```

**Properties:**
- No additional query cost
- No network load
- Instant response
- PWV set immutable (cannot be changed by re-querying)


### 18.8 Fan-Out Protocol (Core-Verified Diffusion)

The fan-out protocol is the **universal broadcast mechanism** for all protocol-level
messages: JFP freeze requests/votes (§7-9), DWP queries (§5), Console governance,
and future message types. It is carried by ANTIE but **verified by Core (CL10)**.

**Design principle:** Core verifies the envelope, Lambda interprets the content.
Adding new message types requires only a new content_type constant — no Core logic change.
This ensures Core is stable across releases while the protocol remains extensible.

**Trust model:** Core is the sole authority on fan-out legitimacy. Validators/operators
cannot forge fan-out messages — only Core-verified messages are relayed. Core controls
TTL decrement — Lambda cannot inflate propagation range.

#### 18.8.1 TTL Validation (Core-Controlled)

Core controls TTL at every hop. Lambda MUST use Core's output TTL for forwarding.

```
TTL Rules (enforced by Core CL10):
+----------------------------+----------------------------------------------+
| Condition                  | Core Action                                  |
+----------------------------+----------------------------------------------+
| ttl_current == 0           | REJECT (expired — process locally, no forward)|
| ttl_current > ttl_original | REJECT (inflated — attack or corruption)     |
| ttl_original > 10          | REJECT (exceeds protocol maximum)            |
| ttl_current > 0            | ACCEPT, output new_ttl = ttl_current - 1     |
+----------------------------+----------------------------------------------+
```

**Core produces new_ttl.** Lambda forwards with Core's output. Cannot inflate.
A message with new_ttl == 0 is still processed locally — just not forwarded further.

#### 18.8.2 Fanout Validation

```
Fanout Limits (enforced by Core CL10):
+------------------+---------------------------+
| Fanout Value     | Action                    |
+------------------+---------------------------+
| fanout == 0      | REJECT (must propagate)   |
| fanout 1-3       | ACCEPT                    |
| fanout > 3       | REJECT (exponential load) |
+------------------+---------------------------+
```

Fanout is set once by the originator, never changed during propagation.

#### 18.8.3 Signature & Identity Validation

Core verifies two properties at every hop:

1. **Originator identity**: `originator_pk` must hold a valid VBC (known validator).
   Non-validators cannot originate fan-out messages.

2. **Signature integrity**: Originator's Ed25519 signature over the canonical payload.
   The signature covers immutable fields only (including `ttl_original`, NOT `ttl_current`)
   so it survives TTL decrement across hops without re-signing.

```
Signing payload = BLAKE3("AXIOM_FANOUT" || diffusion_id || content_type
                  || content || ttl_original || fanout || timestamp)

Invalid signature → IGNORE (silent drop — no feedback to attacker)
Missing signature → IGNORE (silent drop)
```

#### 18.8.4 Diffusion Payload Structure

The fan-out message is the **universal diffusion envelope** for all protocol-level
broadcasts: JFP freeze requests/votes, DWP queries, Console appointments, and future
message types. Core verifies the envelope; Lambda/ANTIE interpret the content.

```rust
struct FanOutMessage {
    // ── Envelope (verified by Core, immutable across hops) ──

    /// Unique message ID for deduplication.
    /// MUST equal BLAKE3("AXIOM_FANOUT_ID" || content || originator_pk).
    /// Computed deterministically — cannot be forged or reused.
    diffusion_id: [u8; 32],

    /// Content type tag (u16 — extensible, see §18.8.6).
    /// Core validates the tag is in the allowed set.
    /// Core does NOT interpret content differently per type.
    content_type: u16,

    /// Opaque content — interpreted by Lambda/ANTIE, not Core.
    /// Core checks: non-empty, len <= MAX_FANOUT_CONTENT_BYTES (65536).
    content: Vec<u8>,

    /// Originator — the validator who created this message.
    /// Core verifies originator_pk holds a valid VBC (known validator).
    originator_pk: [u8; 32],

    /// Originator's Ed25519 signature over the canonical signing payload:
    ///   BLAKE3("AXIOM_FANOUT" || diffusion_id || content_type.to_le_bytes()
    ///          || content || ttl_original || fanout || timestamp.to_le_bytes())
    /// Signs ttl_original (immutable), NOT ttl_current — so signature
    /// survives TTL decrement across hops without re-signing.
    originator_sig: [u8; 64],

    /// Creation timestamp (Unix epoch seconds).
    /// Core rejects if > 24h old or in the future (> now + 60s).
    timestamp: u64,

    /// Original TTL at creation (immutable, covered by signature).
    /// Max 10. Set once by originator, never changed.
    ttl_original: u8,

    /// Fanout count — how many peers each hop forwards to.
    /// Max 3. Set once by originator, never changed.
    fanout: u8,

    // ── Mutable field (controlled by Core at each hop) ──

    /// Current TTL — decremented by Core at each verification.
    /// Core input: ttl_current from the received message.
    /// Core output: ttl_current - 1 (or Reject if ttl_current == 0).
    /// Lambda MUST use Core's output TTL for the forwarded copy.
    /// Lambda cannot inflate TTL — Core produced it.
    ttl_current: u8,
}
```

**Constants:**
```rust
const FANOUT_MAX_TTL: u8 = 10;
const FANOUT_MAX_FANOUT: u8 = 3;
const FANOUT_MAX_CONTENT_BYTES: usize = 65536;  // 64 KB
const FANOUT_MAX_AGE_SECS: u64 = 86400;         // 24 hours
const FANOUT_FUTURE_TOLERANCE_SECS: u64 = 60;    // 1 minute clock drift
```

#### 18.8.5 Core Verification (CL10: Fan-Out)

Core verifies fan-out messages via a new CL mode (CL10). This is the **sole authority**
for fan-out legitimacy. Lambda/ANTIE cannot forge, modify, or bypass this check.

```rust
// Core CL10: Fan-Out Verification
//
// Input:  FanOutMessage (as received)
// Output: Accept { new_ttl } | Reject { reason }
//
// Core controls TTL decrement — Lambda uses Core's output, not its own.

fn verify_fanout(msg: &FanOutMessage, current_time: u64) -> FanOutResult {
    // 1. Structural bounds
    if msg.ttl_original > FANOUT_MAX_TTL {
        return Reject("ttl_original exceeds maximum (10)");
    }
    if msg.fanout == 0 || msg.fanout > FANOUT_MAX_FANOUT {
        return Reject("fanout out of range (1-3)");
    }
    if msg.content.is_empty() || msg.content.len() > FANOUT_MAX_CONTENT_BYTES {
        return Reject("content size out of range");
    }

    // 2. TTL liveness — Core controls this, not Lambda
    if msg.ttl_current == 0 {
        return Reject("TTL expired — do not forward");
    }
    if msg.ttl_current > msg.ttl_original {
        return Reject("ttl_current > ttl_original — inflated TTL");
    }

    // 3. Content type — must be in known set
    if !is_known_content_type(msg.content_type) {
        return Reject("unknown content_type");
    }

    // 4. Timestamp freshness
    if msg.timestamp > current_time + FANOUT_FUTURE_TOLERANCE_SECS {
        return Reject("timestamp in the future");
    }
    if current_time.saturating_sub(msg.timestamp) > FANOUT_MAX_AGE_SECS {
        return Reject("message too old (>24h)");
    }

    // 5. diffusion_id integrity
    let expected_id = BLAKE3("AXIOM_FANOUT_ID" || msg.content || msg.originator_pk);
    if msg.diffusion_id != expected_id {
        return Reject("diffusion_id mismatch — forged or corrupted");
    }

    // 6. Originator VBC check — must be a known validator
    //    (VBC validation via PublicInputs.vbc_bundle, same as CL2)
    if !is_valid_validator(msg.originator_pk) {
        return Reject("originator not a recognized validator");
    }

    // 7. Signature verification
    let signing_payload = BLAKE3(
        "AXIOM_FANOUT" || msg.diffusion_id || msg.content_type.to_le_bytes()
        || msg.content || msg.ttl_original || msg.fanout
        || msg.timestamp.to_le_bytes()
    );
    if !ed25519_verify(msg.originator_pk, signing_payload, msg.originator_sig) {
        return Reject("originator signature invalid");  // Silent drop in production
    }

    // 8. Accept — Core produces the decremented TTL
    Accept { new_ttl: msg.ttl_current - 1 }
}
```

**Key design decisions:**
- **Core controls TTL**: `new_ttl` is in Core's output. Lambda MUST use it. Cannot inflate.
- **Signature covers immutables**: `ttl_original` is signed, not `ttl_current`. Signature survives hops.
- **diffusion_id is deterministic**: BLAKE3(content || originator_pk). Cannot be forged or reused with different content.
- **Content is opaque to Core**: Core checks bounds and type tag, never interprets bytes. New message types need only a new u16 constant — no Core logic change.
- **VBC check at originator**: Only validators with valid VBCs can originate fan-out messages. Citizen nodes, wallets, and external tools cannot.

#### 18.8.6 Content Type Registry

Content types are grouped by protocol domain. Adding a new type requires only adding
the u16 constant to Core's allowed set — the verification logic is unchanged.

```rust
// ── Core Protocol (0x0001–0x00FF) ──
const FANOUT_JFP_FREEZE_REQUEST:   u16 = 0x0001;  // §7: Initiate judicial freeze
const FANOUT_JFP_VOTE:             u16 = 0x0002;  // §8: Cast freeze vote
const FANOUT_JFP_RESULT:           u16 = 0x0003;  // §8: Announce vote result
const FANOUT_DWP_QUERY:            u16 = 0x0010;  // §5: Decoy witness query
const FANOUT_DWP_RESPONSE:         u16 = 0x0011;  // §5: Decoy witness response
const FANOUT_DWP_STAMP:            u16 = 0x0012;  // §5.2.1: stamp.v1 payment proof

// ── Console / Governance (0x0100–0x01FF) ──
const FANOUT_CONSOLE_APPOINTMENT:  u16 = 0x0100;  // Console seat assignment
const FANOUT_CONSOLE_RESIGNATION:  u16 = 0x0101;  // Console seat vacancy
const FANOUT_DEDIGIT_SUGGESTION:   u16 = 0x0102;  // De-digit proposal
const FANOUT_NETWORK_ALERT:        u16 = 0x0103;  // Operator broadcast

// ── Validator Coordination (0x0200–0x02FF) ──
const FANOUT_VALIDATOR_GOSSIP:     u16 = 0x0200;  // Peer discovery hints
const FANOUT_VBC_ANNOUNCEMENT:     u16 = 0x0201;  // New validator VBC

// ── Reserved (0xFF00–0xFFFF) ──
// Experimental and testing use only. NOT accepted in production Core.
```

Lambda interprets content based on content_type. Core only checks the type is in the
allowed set — it never reads content bytes.

#### 18.8.7 Originator Flow (Creating a Fan-Out Message)

```
1. Validator builds content (JFP vote, DWP query, Console msg, etc.)
2. Compute diffusion_id = BLAKE3("AXIOM_FANOUT_ID" || content || my_pk)
3. Set ttl_original = 10, fanout = 3, ttl_current = 10
4. Sign: BLAKE3("AXIOM_FANOUT" || diffusion_id || content_type || content
         || ttl_original || fanout || timestamp)
5. Submit to own Core (CL10) for verification → Accept { new_ttl: 9 }
6. Forward to `fanout` random peers via ANTIE with ttl_current = 9
```

#### 18.8.8 Relay Flow (Forwarding a Fan-Out Message)

```
1. Receive FanOutMessage from peer
2. Lambda checks deduplication (diffusion_id seen? → drop)
3. Submit to Core (CL10) with ttl_current from received message
4. Core returns: Accept { new_ttl } or Reject { reason }
5. If Reject → drop (log if reason is structural, silent if signature)
6. If Accept → Lambda processes content by content_type
7. Forward to `fanout` random peers via ANTIE with ttl_current = new_ttl
8. If new_ttl == 0 → process locally but do NOT forward
```

Note: A message with new_ttl == 0 is still **processed** (Lambda reads the content).
It is just not forwarded further. TTL controls propagation, not processing.

## 19. Validator Fee Discovery & Selection

### 19.1 Market-Driven Validator Selection

Clients have full autonomy in selecting which validators to use for transaction witnessing. This creates a competitive market where validators differentiate based on:
- Fee rates
- Service quality
- Software version/features
- Reputation
- Additional services (loyalty points, priority processing, etc.)

**No protocol-level assignment.**
**No forced validator rotation.**
**Pure market selection.**

### 19.2 Validator Information Probing

**Discovery mechanism:**

Clients query validators directly to obtain current fee rates and service parameters.

**Probe request (client -> validator):**
```json
{
  "type": "VALIDATOR_INFO_REQUEST",
  "client_pk": "ed25519:pk_CLIENT...",
  "timestamp": 1704067200
}
```

**Probe response (validator -> client):**
```json
{
  "validator_pk": "ed25519:pk_A...",
  "fee_rate_bp": 8,                    // 0.08% = 8 basis points
  "fee_ttl": 1704153600,                // Unix timestamp (rate valid until)
  "software_version": "axiom-validator/1.2.3",
  "supported_algorithms": ["ed25519", "dilithium", "sphincs"],
  "supported_carriers": ["email", "p2p"],
  "max_witness_load": 1000,             // Transactions per hour
  "additional_services": ["loyalty_points", "priority_processing"],
  "resolution": {
    "email": "validator-a@example.com",
    "p2p_endpoint": "p2p://validator-a.network"
  }
}
```

### 19.3 Fee Rate with Time-To-Live (TTL)

**Commitment mechanism:**

Validators publish fee rates with expiration timestamps:

```
Validator A announces:
"My fee is 0.08%, valid until 2026-01-02 12:00 UTC"
```

**Client behavior:**

1. **Probe multiple validators** (gather fee information)
2. **Filter based on preferences:**
   - Fee rate < 0.1%
   - Software version >= v1.2.0
   - Supports email carrier
   - Other criteria
3. **Select k validators** (k >= 3)
4. **Submit transaction before TTL expires**

**Rate guarantee:**

If client submits transaction before TTL expiration:
- Validator MUST honor the published rate for the duration of the TTL. Violation = reputation damage. No protocol enforcement exists (aligns with AXIOM's decentralization philosophy).
- Violation = reputation damage
- **No protocol enforcement** (aligns with AXIOM's decentralization philosophy)

**After TTL expiration:**

- Validator may change fee rate
- Client must re-probe to get updated rate
- Transactions submitted with outdated rates may be rejected

### 19.4 Reputation vs Protocol Enforcement

**Design choice:**

Lambda does **not** enforce fee rate commitments at the protocol level.

**Rationale:**

If a validator violates their published TTL:
- Clients observe the violation
- Reputation systems (external to protocol) record the event
- Market excludes dishonest validators
- No need for protocol-level punishment

**This is intentional:**
- Reduces protocol complexity
- Aligns with "rules > people" philosophy (the rule is market selection)
- Avoids governance overhead

**Market dynamics:**

A validator who frequently changes rates or violates TTL will:
- Lose client trust
- Receive fewer transaction requests
- Earn less income
- Be naturally selected out

### 19.5 Software Version Diversity

**Why versions matter:**

Different validator implementations may offer:
- **Different carriers**: email-only, P2P-only, satellite, morse code
- **Different companies**: Various organizations developing validator software
- **Different features**: Loyalty programs, priority queues, advanced analytics
- **Different security models**: Hardware-backed, distributed, cloud-native

**Client selection criteria:**

```
Example client preferences:
- "I only use validators supporting P2P carrier"
- "I prefer validator software from Company X"
- "I need validators offering loyalty points"
- "I want validators with hardware security modules"
```

**Protocol agnosticism:**

The protocol does not care which software version validators run, as long as they:
- Implement core validation logic correctly
- Support required cryptographic algorithms
- Follow witness overlap rules (Section 17.3)

**Market outcome:**

Validator software that provides better UX, lower fees, or unique features will attract more clients. Poor implementations will be naturally excluded.

#### 19.5.1 Protocol Version Autonomy (PVA)

Protocol Version Autonomy is not an additional mechanism -- it is the **natural result** of AXIOM's layered architecture.

**Layer Invariance:**

| Layer | Property | Implication |
|-------|----------|-------------|
| **axiom-core.elf** | Fixed, immutable | All versions pass through same Gatekeeper |
| **Λ (Lambda)** | Function fixed, implementation varies | Different teams, different efficiency, same capabilities |
| **Gateway** | Fully diverse | Different carriers, different fees, different hardware |

**Key Principle:**

> Lambda implementations may differ in efficiency, carrier support, and cost structure.
> But all Lambda implementations MUST support the same functional requirements (witness, signature, Console participation).
> All transactions pass through the same axiom-core.elf -- asset integrity is guaranteed regardless of version.

**Why PVA Works Naturally:**

1. **No Forced Upgrades** -- As long as witness/sig/Console functions are complete, any version is valid
2. **Asset Invariance** -- axiom-core.elf protects all assets; version choice cannot affect ownership
3. **Downgrade Safety** -- axiom-core.elf is the constant; downgrading only affects stability/compatibility, not assets
4. **Fragmentation as Stabilization** -- Unstable versions are naturally eliminated (economic pressure)
5. **Market Arbitration** -- Adoption is determined by utility, not authority

```{=latex}
\begin{figure}[H]
\centering
\begin{tikzpicture}[
    box/.style={rounded corners=4pt, thick, minimum width=3.2cm, minimum height=0.7cm, align=center, font=\small},
    arrow/.style={->, thick, >=stealth}
]
\node[box, draw=axiom-blue, fill=axiom-blue!10] (A) at (-3.5,0) {Version A (Team X)\\{\scriptsize High perf, P2P+Email}\\{\scriptsize Higher fee}};
\node[box, draw=axiom-blue, fill=axiom-blue!10] (B) at (3.5,0) {Version B (Team Y)\\{\scriptsize Basic impl, Email only}\\{\scriptsize Lower fee}};
\node[box, draw=axiom-blue, fill=axiom-blue!25, minimum width=8cm] (CORE) at (0,-2.2) {Same axiom-core.elf validates all};
\node[box, draw=green!60, fill=green!8, minimum width=8cm] (PROT) at (0,-3.7) {Same asset protection $\cdot$ Same witness validity};
\draw[arrow] (A) -- (CORE);
\draw[arrow] (B) -- (CORE);
\draw[arrow] (CORE) -- (PROT);
\end{tikzpicture}
\caption{Version Diversity --- Different implementations, same Core, same asset protection.}
\end{figure}
```

**Fundamental Constraint:**

Any mechanism that produces asset loss, forced migration, or irreversible economic harm as a result of protocol version choice is **prohibited**. If versions cannot interoperate, the system fragments rather than compels.

#### 19.5.2 Gateway Requirements

Developers MAY create any Gateway implementation. However:

> **ANTIE Gateway MUST always be present.**

| Gateway | Required? | Role |
|---------|-----------|------|
| **ANTIE** (Email) | **MUST** | V2V backbone |
| **UNCLE** (Banking) | MAY | Public bootstrap |
| **COUSIN** (P2P) | MAY | Alternative transport |

**Why ANTIE is Mandatory:**

ANTIE is the **only guaranteed method** for Validator-to-Validator communication:

- Validator ping/validation requires a common communication backbone
- Email is globally reachable without additional negotiation
- Secure diffusion (fanout) depends on reliable V2V channels
- Other Gateways may have carrier limitations preventing interoperability

**Validator Gateway Architecture:**

```
Any Validator (regardless of Lambda version)
+ ANTIE (Email) -> MUST -- backbone
+ UNCLE (Banking) -> MAY -- optional
+ COUSIN (P2P) -> MAY -- optional
" Other Gateways -> MAY -- optional
```

**Client Compatibility:**

- Clients MAY use any Gateway their chosen validators support
- If a client's preferred Gateway is not supported by a validator, the client selects a different validator
- This is a market-driven selection, not a protocol enforcement

**Gateway Diversity Expectation:**

| Gateway | Expectation |
|---------|-------------|
| **ANTIE** | Core implementation provided; all validators MUST support |
| **UNCLE** | Public bootstrap implementation; various implementations expected |
| **COUSIN** | Fully open; any implementation that follows WP/YP/Lambda spec |

### 19.6 No Fee Rate Ceiling

**Protocol position (v2.11.6 — original):**

There is **no maximum fee rate** enforced by the protocol.

**Rationale:**

If Validator charges 50% fee:
- Clients will simply not select that validator
- Market pressure keeps fees reasonable
- No need for protocol-level caps

**Client protection:**

Clients can set their own maximum acceptable fee in wallet software:
```
User preference: "Never use validators charging > 0.5%"
Wallet filters: Exclude validators with fee_rate_bp > 50
```

**Extreme scenario:**

If all validators collude to charge 10% fees:
- New validators enter market with lower fees (profit opportunity)
- Market equilibrium restored
- Protocol remains neutral

#### 19.6 v3.x Amendment — Protocol Caps (2026-06-02)

The "no ceiling" position above is amended for the v3.x receiver-pays direct-deposit model. Two protocol-enforced caps now bound `fee_breakdown` slots, with the rationale that AXIOM-as-payment-infrastructure must comply with regulator expectations and cap-validation is a cheap protocol-layer defence against colluding-validator collusion:

| Cap | Value | Rationale |
|-----|-------|-----------|
| `MAX_VALIDATOR_FEE_BPS` | 30 bps (0.30 %) | Per-validator slot cap. Aligns with EU Regulation 2015/751 Article 4 per-service interchange ceiling. |
| `MAX_TOTAL_TX_FEE_BPS` | 90 bps (0.90 %) | Aggregate sum of slots in one `fee_breakdown`. At k=3 each slot is at-cap, the aggregate is exactly at-cap. |

**Enforcement points (defence-in-depth):**

1. **Core CL5** — `validate_fee_breakdown(amount, &fee_breakdown)` at receiver-side redeem entry. Receipt rejected with `E_FEE_EXCEEDS_VALIDATOR_CAP` / `E_FEE_EXCEEDS_AGGREGATE_CAP` if violated.
2. **Nabla `/register`** — independent recheck at `process_registration` step 5b'. Receipt rejected with `NablaError::InvalidReceipt`.
3. **Gossip-receive `apply_state_update`** — third recheck on the cross-mesh propagation path before crediting `txid_records`.

**Operator-set rates are clamped, not rejected:**

A validator's `fee_config.rate_bps` is operator-configurable to any value, but `expected_fee_slot_amount(amount, rate_bps)` clamps it to `MAX_VALIDATOR_FEE_BPS` at slot-computation time. An operator-configured 50-bps rate produces 30-bps fee slots; no signing-time error. The SDK and Lambda use the same clamp formula, so per-slot signing converges without coordination.

**The market mechanism still applies WITHIN the cap range.** Validators choose `rate_bps` between 0 and the cap; clients prefer lower-rate validators. The cap is a ceiling, not a price floor.

**Client-side max-acceptable still applies:** wallet UIs can still expose "never use validators charging > 0.20 %" — that filter applies below the 0.30 % protocol cap.

**Complete v3.x fee mechanism:** see `AXIOM_DESIGN_ValidatorFeeLedger.md`.


## 20. DEED System -- Enabling VC-Free Development

### 20.1 Core Concept

**DEED (Developer Equity & Execution Deed)** is the mechanism that enables AXIOM to operate without venture capital.

**The problem DEED solves:**

Traditional crypto projects require VC funding because developers need capital before the protocol generates value. This creates:
- Exit pressure (investors want liquidity events)
- Misaligned incentives (pump token, then abandon)
- Governance capture (investors control protocol direction)
- Unsustainable post-exit maintenance

**DEED's solution:**

Developers and contributors receive **direct, sustainable income from protocol usage** itself.

```
No VC needed -> No exit pressure -> No abandonment incentive
Protocol usage -> Developer income -> Aligned incentives
More usage -> More funding -> Sustainable maintenance
```

**This is why AXIOM can operate without venture capital.**

### 20.2 How DEED Works (Protocol View)

**Mandatory fee allocation:**

A portion of every validator's transaction fee is automatically allocated to development teams.

**Allocation ratios defined in "Lambda DEED -- Developer Equity & Execution Deed" document.**

**Illustrative example (exact ratios in DEED document):**
```
Validator earns 1.0 L$ fee from transaction

DEED allocation:
- Protocol Development Team: 0.1 L$ (10%, active 10 years)
- Implementation Team: 0.1 L$ (10%, active 5 years)
- Validator keeps: 0.8 L$ (80%)

Total DEED allocation: 20% of validator fees (during active period)
```

**Time-limited:**
- Protocol Team: 10 years from genesis
- Implementation Team: 5 years from genesis
- After expiry: Validators keep 100% of fees

**Core enforcement:**

Every transaction is validated for correct DEED allocation:
```c
if (years_since_genesis < DEED_DURATION) {
    if (!correct_deed_allocation(tx)) {
        return INVALID;  // Transaction rejected
    }
}
```

### 20.3 Developer Income Model

**Traditional VC model:**
```
Raise capital -> Build -> Exit -> Developers leave
```

**DEED model:**
```
Build -> Usage generates fees -> Developers earn continuously -> Stay
```

**Key difference:**

VC-funded: Income comes from investors, requires exit  
DEED-funded: Income comes from users, requires sustainability

**Incentive alignment:**

If protocol succeeds -> More transactions -> More fees -> Developers earn  
If protocol fails -> No transactions -> No fees -> Developers earn nothing

**Developers are incentivized to build something people actually use, not just something that can be sold to investors.**

### 20.4 Why This Eliminates VC Dependency

**Capital requirements covered:**

1. **Development costs:** Funded by DEED allocation over time
2. **Maintenance costs:** Ongoing fee income sustains long-term work
3. **Contributor compensation:** Direct protocol-to-developer payments

**What this removes:**

- + No need to raise capital rounds
- + No investor control or governance
- + No exit pressure or pump-and-dump incentives
- + No token sale to early insiders
- + No foundation managing reserves

**What this enables:**

- Developers funded by real usage
- Sustainable long-term maintenance
- No abandonment after "exit"
- Aligned incentives (build what works, not what sells)

### 20.5 DEED Groups (Technical Implementation)

**Two development groups:**

1. **Protocol Team Group**
   - Core protocol development
   - 10% of fees, 10 years
   - `group_id: "grp:deed:protocol:genesis"`

2. **Implementation Team**
   - Reference implementations, tooling
   - 10% of fees, 5 years
   - `group_id: "grp:deed:implementation:genesis"`

**Group Wallet mechanism (Section 30):**

DEED Groups use Group Wallets (Section 30) which provide:
- Shared asset pool with tracked balance
- Individual contributor withdrawal based on share percentage (basis points)
- Automatic distribution on receive based on pre-defined ratios
- Privacy (internal allocations visible only on Nabla, not in cheques)

**Created at genesis:**
- Member lists defined
- Allocation ratios set
- Immutable post-creation

### 20.6 Complete Specification

**This Yellow Paper defines:**
- Protocol-level DEED enforcement (Core validation)
- Mandatory allocation percentages
- Time-based expiration logic
- Transaction format requirements

**Complete DEED specification in:**

**"Lambda DEED -- Developer Equity & Execution Deed"** covers:
- Contributor eligibility and onboarding
- Individual allocation ratios within groups
- Performance accountability mechanisms
- Withdrawal procedures and quotas
- Economic sustainability modeling
- Comparison with traditional funding models
- Why this model doesn't require governance

**Cross-references:**
- Genesis implementation -> "Bootstrap Guide"
- Economic rationale -> "White Paper v2.28"
- Group Wallet mechanism -> Section 30 (this Yellow Paper)

### 20.7 The Core Innovation

**DEED transforms the funding question:**

**Old question:**  
"How do we raise enough capital to build this?"

**New question:**  
"How do we build something people will use enough to sustain us?"

**This shift eliminates:**
- The need for venture capital
- Exit-oriented economics
- Governance capture by investors
- Post-exit protocol abandonment

**AXIOM doesn't need VC because DEED aligns developer income with protocol usage, not with investor exits.**


### 20.7 Unified Cheque Model

**Fundamental principle:** All balance increases in AXIOM flow through the cheque system.

There is no direct balance injection. Whether the recipient is a normal user, a validator collecting fees, or DEED receiving its allocation -- the mechanism is always the same: collect required cheques, present to validators for witnessing, receive balance update.

**Why unified?**

This creates a single, auditable path for all value movement:
- Every atom can be traced through cheque issuance and redemption
- No special cases or backdoors for "system" transfers
- Same validation logic applies to all recipients
- Conservation of atoms is trivially verifiable

```
Balance increase pathway (universal):

1. Cheque(s) issued to recipient
2. Recipient presents cheque(s) to validators
3. Validators witness (verify cheques, update state)
4. Recipient's balance increases
```

### 20.8 Fee Distribution Flow

> *§20.8–§20.12 describe two distinct fee models. The v2.11.6 model (cheque-based) is preserved here as historical reference; the v3.x model (direct-deposit to Nabla pools) supersedes it for all new deployments. Both honour the same receiver-pays principle and produce identical conservation results — only the on-wire mechanism differs.*

#### 20.8 v2.11.6 (cheque model — historical)

**Receiver pays fees at redeem time.** The sender transmits the full amount; the receiver's redeeming validators deduct their fees from the received amount.

When Alice sends 1000 atoms to Bob, and Bob redeems with k=3 validators (V4, V5, V6) at 10 atoms fee each:

```
Alice sends:  1000 atoms (full amount deducted from Alice)

Bob redeems:
├── Bob receives:     970 atoms  (1000 - 3×10)
├── V4 fee:            10 atoms  (Bob's redeeming validator)
├── V5 fee:            10 atoms  (Bob's redeeming validator)
└── V6 fee:            10 atoms  (Bob's redeeming validator)

Total: 1000 atoms ✓ (conservation)
```

**Fee deduction formula:**
```
receiver_amount = cheque_amount - (k × fee_per_validator)
```

**Why receiver pays (changed from v2.11.5):**

1. **Receiver chooses validators.** The receiver selects which validators to redeem with, so they control fee costs. A receiver can shop for lower-fee validators via VSP (§27.11).
2. **No sender ACK round-trip.** The sender's role ends after witnessing. No explicit sender ACK message on the wire. Simpler protocol, fewer network round-trips. (Lambda internally finalizes consumed state via an ACK mechanism during cheque delivery — see §17.9.3.)
3. **Sender sends exact amount.** Alice sends "1000 atoms to Bob." No mental math for fees. The sender's deduction equals the stated amount.
4. **Receiver has time.** The receiver redeems at their convenience — they can wait for lower fees or choose validators in a different jurisdiction.

**Variable fees:**

Each validator sets their own fee rate. The examples use 10 atoms for clarity, but in production:
- Validators publish fee rates via VSP (§27.11 `fee_rate_bps`, `fee_min_amount`)
- Receivers select redeeming validators based on fee/service tradeoffs
- Total fee = sum of selected validators' individual fees

#### 20.8 v3.x Amendment — Direct Deposit (2026-06-02)

The v2.11.6 cheque model issues a per-TX fee cheque to each witnessing validator and a separate DEED cheque per fee redemption. At production scale this overhead dwarfs the fees being collected. The v3.x model replaces per-TX fee cheques with a direct-deposit mechanism on Nabla; the receiver-pays principle and the worked example totals (§20.12) are preserved.

**Mechanism summary:**

1. **Sender's witness round produces no fee cheques.** The validators agree on `fee_breakdown` (Vec<FeeShare>) at receipt-commitment time; each Lambda verifies its own slot before signing (`verify_my_fee_slot`).

2. **Receiver's cheque carries the GROSS amount.** Unlike v2.11.6 (where the cheque is already net), in v3.x the cheque amount equals the sender's gross. The deduction happens at receiver-side redeem (CL5).

3. **At Core CL5 the receiver pays:** `net_to_receiver = effective_amount - sum(fee_breakdown[i].amount)`. The `fee_breakdown` rides on the redeem-side wire (`RedeemRequestEnvelope` → `PublicInputs.fee_breakdown`). The send-side `Transaction` type carries NO fee data.

4. **At Nabla `/register` the per-tx accounting lands:**
   - The full `TxRecord { receiver, amount, fee_breakdown, tick }` is stored in hashmap-mode nodes (bloom-mode nodes skip).
   - A per-validator earnings index is updated.
   - 10 % of `sum(fee_breakdown)` is credited to the per-Nabla `DeedPool` accumulator.

5. **Validator withdrawal is a periodic operation, not per-TX:**
   - Operator queries any hashmap Nabla for accumulated earnings (signed response).
   - Operator registers their pool linkage (validator_id → linked_wallet_id) one time via SPHINCS+-signed `RegisterValidatorPoolRequest`.
   - Operator submits `ValidatorWithdrawalRequest` via the per-validator dashboard at :7700-7709. Lambda runs a 7-step verification including the §20.10 conflict check.
   - On `VERIFIED`, `net_amount = total_amount × 90 / 100` is minted into `linked_wallet_id`.

6. **DEED collection happens automatically.** No separate per-validator DEED cheque. The 10 % slice is credited to `DeedPool` at /register, drained by a separate Group withdrawal flow (future).

**Receiver-pays principle preserved:**

```
v2.11.6: receiver_amount = cheque_amount - k × fee_per_validator
            (cheque already net; mechanism: fee cheque per validator)

v3.x:    net_to_receiver = cheque_amount - sum(fee_breakdown[i].amount)
            (cheque is gross; mechanism: CL5 deduction + Nabla credit)
```

Both produce the same `net_to_receiver` for identical `fee_per_validator × k`.

**Protocol caps:** `MAX_VALIDATOR_FEE_BPS` (30 bps per slot) and `MAX_TOTAL_TX_FEE_BPS` (90 bps aggregate) bound the `fee_breakdown` (§19.6 v3.x amendment).

**Complete specification:** see `AXIOM_DESIGN_ValidatorFeeLedger.md`.

### 20.9 Cheque Requirements by Recipient Type

| Recipient Type | Cheques Required | Validators Required | Source of Cheques |
|----------------|------------------|---------------------|-------------------|
| **Normal receiver** | 3 | k=3,4,5 | Sender's validators issue cheques |
| **Validator fee** | 2 | k=3,4,5 | 1 fee cheque + 1 confirmation cheque |
| **DEED** | 1 | k=3,4,5 | Validator's fee redemption witnesses |

**Normal receiver (3 cheques):**

Standard transaction. Bob receives cheques from V1, V2, V3 when Alice sends to him. Bob presents all 3 cheques to validators to redeem.

**Validator fee (2 cheques):**

Validators receive two cheques per transaction witnessed:

1. **Fee cheque** - Issued when witnessing sender's transaction (contains the fee amount)
2. **Confirmation cheque** - Issued when witnessing receiver's redemption (proves TX completed)

The validator must collect BOTH cheques before they can redeem their fee. This ensures validators only get paid after the full transaction completes.

**DEED (1 cheque):**

DEED receives cheques when validators redeem their fees. Each witnessing validator issues a DEED cheque as part of the fee redemption process.

### 20.10 Validator Fee Redemption Rules

> *§20.10 is amended for the v3.x direct-deposit model. The conflict-of-interest principle is **strengthened** (the rule applies to withdrawal-witnesses, not per-fee-redemption witnesses); the mechanism is reframed in terms of the new pool/withdrawal flow.*

**Conflict of interest rule (v2.11.6 — cheque model):**

Validators who witnessed the original transaction **cannot** witness each other's fee redemption for that same transaction.

**Rule:** Each original witness redeems with k=3 validators EXCLUDING all other original witnesses:

| k | Witnesses | Each redeems with |
|---|-----------|-------------------|
| 3 | V1, V2, V3 | Any 3 EXCEPT the other 2 |
| 4 | V1--V4 | Any 3 EXCEPT the other 3 |
| 5 | V1--V5 | Any 3 EXCEPT the other 4 |

**Overlap allowed for fee witnesses:** Fee redemption witnesses MAY overlap across different original witnesses (e.g., V4 can witness both V1's and V2's fee redemption), as long as they weren't one of the original k witnesses.

**Fee redemption flow:**

1. V1 collects both cheques: fee cheque (10 atoms) from Alice's send + confirmation cheque from Bob's redemption
2. V1 presents 2 cheques to V4, V5, V6 — they verify, issue cheques to V1 (9 atoms each) and DEED (1 atom each)
3. V1 redeems with 3 cheques: V1's wallet +9 atoms
4. DEED receives 3 cheques (from V4, V5, V6)

#### 20.10 v3.x Amendment — Withdrawal-Witness Disjoint Rule (2026-06-02)

In v3.x there is no "fee redemption" event per TX (fee accumulates directly into the per-validator earnings index at receiver's /register; no per-TX fee cheque exists to redeem). The conflict-of-interest rule applies instead to the **periodic withdrawal** that converts accumulated earnings into wallet balance.

**Rule (v3.x):**

When a validator initiates a `ValidatorWithdrawalRequest`, the operator's chosen `k` witnessing validators MUST NOT overlap with the set of validators who witnessed any of the TXs whose fees are being claimed.

Formally, given an earnings attestation with entries `e₁, e₂, …, eₙ`, each carrying a `full_fee_breakdown` (Step 8.3.A enhancement):

```
excluded = ⋃ᵢ { eᵢ.full_fee_breakdown[j].validator_id }
chosen_witnesses ∩ excluded MUST equal ∅
```

**Enforcement:** `check_validator_withdrawal_conflict(entries, chosen_witnesses)` (Core); invoked from Lambda's `verify_validator_withdrawal` as step 7 of the verification chain. Violation produces status `REJECTED_CONFLICT_OF_INTEREST`.

**Why the rule strengthens in v3.x:** A withdrawal collapses many TXs' fees into one event. If a witness who earned fees on TX `eᵢ` also witnesses the withdrawal claiming `eᵢ`'s fees, they have a direct interest in the withdrawal succeeding. Excluding the entire union of past-witness sets ensures every withdrawal witness is economically independent of every claimed TX.

**Disjointness is provable from the attestation alone:** the `full_fee_breakdown` per entry is included in the earnings response and bound into the canonical attestation hash (`AXIOM_NABLA_EARNINGS_ATTEST_v2`). An operator cannot strip slots from the attestation to hide an overlap — the Ed25519 signature won't verify.

### 20.11 DEED Cheque Issuance

> *§20.11 is amended for v3.x. The 10 % allocation is unchanged; the mechanism shifts from per-fee-redemption cheque to direct pool credit at receiver's /register.*

**DEED allocation (v2.11.6 — cheque model, historical):**

During the DEED period (first 10 years), validators must allocate a portion of their fees to DEED:

DEED allocation = 10\% of validator fee (minimum 1 atom). Example: fee 10 atoms, validator keeps 9, DEED receives 1.

**Enforcement model:**

| Aspect | Enforcement Level |
|--------|-------------------|
| DEED % calculation | **Protocol-enforced** |
| Validator receives (fee - DEED%) | **Protocol-enforced** |
| DEED cheque issuance | **Protocol-enforced** |
| DEED cheque delivery | **Not enforced** |

**What "protocol-enforced" means:**

When V4, V5, V6 witness V1's fee redemption:
- They MUST calculate the DEED portion (10%)
- They MUST issue cheques to V1 for only 9 atoms (not 10)
- They MUST issue cheques to DEED for 1 atom
- This is part of the fee redemption protocol

**What "not enforced" means:**

Delivery of DEED cheques to DEED is expected but not cryptographically enforced:
- Validators SHOULD deliver DEED cheques
- If they don't, the atoms are **burned** (removed from circulation)
- Validators cannot keep undelivered DEED atoms for themselves
- Conservation still holds (atoms removed, not stolen)

**Economic incentive:**

Validators who consistently fail to deliver DEED cheques may face:
- Reputation damage
- Exclusion by other validators
- Reduced client selection

This follows the AXIOM principle: **Incentive → Expectation → Hard Rules**

DEED delivery sits at the **Expectation** layer. Honest validators follow the protocol. Dishonest validators can only burn atoms, not steal them.

#### 20.11 v3.x Amendment — Direct Pool Credit (2026-06-02)

In v3.x there is no per-fee DEED cheque. The 10 % slice is credited directly to a per-Nabla `DeedPool` accumulator at receiver's `/register` time, when the receipt's `fee_breakdown` is non-empty and cap-validated:

```
deed_share = sum(fee_breakdown[i].amount) / 10
deed_pool.credit(deed_share, current_tick)
```

`DeedPool` is a monotonic-increase accumulator (`balance`, `total_credited`, `last_credit_tick`) that lives alongside `AirdropPool` and `DevTreasuryPool` on the Nabla node state. Drained by a DEED Group withdrawal flow (operator-side, k-witnessed, future).

**Allocation enforcement is structural, not policy:** the credit happens inside `process_registration` at the same step that records the per-tx accounting (`record_tx_meta`). There is no separate cheque to deliver, no per-validator decision to honour DEED — the math is part of what Nabla MUST do to commit a fee-bearing receipt to its hashmap. A Nabla node that skipped the DEED credit would still produce a different root hash than its peers and fall out of mesh consensus.

**The "burn on undelivered DEED" mechanism of v2.11.6 has no v3.x analogue:** without per-fee cheques, there is no delivery step that can fail. Credits are atomic with the rest of /register. If Nabla is honest, DEED gets its slice; if Nabla is dishonest, the mesh detects via root-hash divergence (a much stronger guarantee than the v2.11.6 "burn or reputation damage" expectation layer).

**Allocation ratio unchanged:** 10 % per validator slot, computed by integer division (floors at 0 atoms for fees < 10 atoms; the dust loss naturally goes to the validator at scale). Same as v2.11.6.

### 20.12 Complete Transaction Fee Flow Example

> *Example exists in two parallel forms — v2.11.6 (cheque model, historical) and v3.x (direct deposit, current). Conservation totals are identical; on-wire mechanism differs.*

#### 20.12.a v2.11.6 example (cheque model — historical)

**Scenario:** Alice sends 1000 atoms to Bob, k=3, fee=10 atoms/validator

**Phase 1: Alice sends to Bob.** Alice creates TX for 1000 atoms, sends to V1, V2, V3. Each validator issues cheque to Bob (970 atoms), fee cheque to itself (10 atoms), and confirmation placeholder. Alice receives 3 witness sigs. Alice's wallet: --1000 atoms.

**Phase 2: Bob redeems.** Bob presents 3 cheques to validators. Validators verify, issue confirmation cheques. Bob receives 3 witness sigs. Bob's wallet: +970 atoms.

**Phase 3: Validators redeem fees.** V1 presents fee cheque + confirmation cheque to V4, V5, V6. Each issues cheque to V1 (9 atoms) and DEED (1 atom). V1's wallet: +9 atoms. V2, V3 repeat with different validators. DEED receives 9 cheques total.

**Phase 4: DEED redeems.** DEED has 9 cheques (1 atom each). Each redeemed with k=3 witnesses. DEED wallet: +3 to +9 atoms depending on delivery.

#### 20.12.b v3.x example (direct deposit — current)

**Scenario:** Alice sends 1000 atoms to Bob, k=3, fee=10 atoms/validator

**Phase 1 — Alice sends to Bob.** Alice creates TX for 1000 atoms, sends to V1, V2, V3 (sender's witnessing validators). No fee cheques. Each validator's cheque to Bob is for the FULL 1000 (gross). Alice's wallet: −1000 atoms.

**Phase 2 — Bob redeems.** Bob redeems with k=3 receiver-side validators. They agree on `fee_breakdown = [(V_a, 10), (V_b, 10), (V_c, 10)]` where each Vᵢ verifies its own slot before signing the receipt_commitment. (Vᵢ may overlap with V₁..V₃ — the sender's witness set is a separate concern from the receiver's, both determined by their respective tier wallets.) CL5 computes:

```
validator_fees_gross = 30
net_to_receiver = 1000 - 30 = 970
```

Bob's wallet: +970.

**Phase 3 — Nabla `/register` (receiver's redeem):** Nabla chain-verifies the receipt (`receipt_commitment_sig` per slot must all verify), then records:

```
txid_records[tx_hash] = TxRecord {
    receiver: Bob,
    amount: 1000,
    fee_breakdown: [(V_a, 10), (V_b, 10), (V_c, 10)],
    tick: T,
}
validator_earnings[V_a] += [(tx_hash, 10, T)]   # gross slot
validator_earnings[V_b] += [(tx_hash, 10, T)]
validator_earnings[V_c] += [(tx_hash, 10, T)]
deed_pool.credit(3, T)                          # 30 / 10 = 3
```

**Phase 4 — V_a withdraws.** V_a's operator queries Nabla for accumulated earnings (signed response, includes full_fee_breakdown per entry), registers their pool linkage (one-time SPHINCS+ sign), and submits a `ValidatorWithdrawalRequest`. They pick V_d, V_e, V_f as `chosen_witnesses` — these MUST NOT overlap with `{V_a, V_b, V_c}` (§20.10 v3.x amendment, enforced by `check_validator_withdrawal_conflict`).

Lambda's `verify_validator_withdrawal` runs the 7-step verification chain. On `VERIFIED`:

```
net_amount = 10 × 90 / 100 = 9
linked_wallet_id = (operator-declared, signed at pool registration)
```

V_a's wallet eventually: +9 (after Step 9 mint primitive).

V_b and V_c go through the same flow independently. DEED Group withdraws from `deed_pool` separately (future Group-withdrawal flow).

**Final tally:**

| Party | Amount | |
|-------|--------|--|
| Alice | −1000 | Sender |
| Bob | +970 | Receiver (net of fees) |
| V_a, V_b, V_c | +9 each (+27) | Validator nets (90 % of gross) |
| DEED pool | +3 | 10 % × 30 gross fees |
| **Total** | **0** | Conservation holds |

Identical to v2.11.6 §20.12 totals. The mechanism differences:

| | v2.11.6 | v3.x |
|---|---------|------|
| Per-TX fee cheques | 3 (one per witnessing validator) | 0 |
| Per-fee DEED cheques | 3 (one per validator fee redemption) | 0 |
| Total cheque writes for one TX's fees | 6 cheques + redemption rounds | 1 Nabla state-write |
| Validator collects fee in | k=3 witness round + 2-cheque collection | accumulator → periodic withdrawal |
| DEED collection mechanism | k=3 witness on each DEED cheque | direct Nabla pool credit |
| DEED delivery guarantee | "Expectation" (burn if not delivered) | Structural (root-hash convergence) |

For the complete v3.x specification, see `AXIOM_DESIGN_ValidatorFeeLedger.md`.

**Final tally:**

| Party | Amount | |
|-------|--------|--|
| Alice | --1000 | Sender |
| Bob | +970 | Receiver |
| V1, V2, V3 | +9 each (+27) | Validator fees minus DEED |
| DEED | +3 | 10\% of fees |
| **Total** | **1000** | Conservation holds |

If DEED cheques are not delivered, those atoms are burned (removed from circulation), not redistributed.


## 21. Genesis & System Initialization (Protocol Summary)

### 21.1 Scope

This section defines protocol-level requirements for genesis state.

Complete bootstrap procedures, allocation schedules, and operational deployment steps are documented in **"Transition Guide -- Bootstrap to Autonomy"** (separate document).

**Yellow Paper defines invariants.**  
**Bootstrap Guide defines procedures.**

### 21.2 Total Supply

**Protocol invariant:**

```
Total AXC supply = GENESIS_SUPPLY (constant)
Post-genesis: No minting, no burning
Every AXC atom exists from t=0
```

**Exact value:** 100,000,000 AXC

This value is hardcoded in Core and cannot be changed without deploying a new Core version (which would constitute a new network, not an update).

### 21.2.1 Developer Class Subgraph (dev-AXC)

In addition to the 100,000,000 AXC public supply, the genesis ceremony allocates a separately-denominated **developer class** subgraph ("dev-AXC") consisting of **1,000,000 dev-AXC** held at FACT #0 by a multisig dev treasury wallet. Dev-AXC is consensus-isolated from public AXC: no protocol operation can move balance between the public-class and developer-class subgraphs, in either direction (rule R1, enforced at `validate_transaction`).

The 100M public-AXC cap above is preserved literally. Dev-AXC is a distinct currency on the same chain — counted separately (`verify_genesis_fact`'s split-sum check), audited separately, never convertible. It serves developer airdrops, soak-test wallet provisioning, contributor recognition drops, and similar use cases where a non-monetary token economy isolated from production is required.

Class is determined by the email part of the wallet_id: exact `@axiom.internal` domain match = developer class; everything else = public. The email is already pk-bound via `pk_bind` (BLAKE3 over `email || master_pk || pk || …`), so the class derivation is cryptographically anchored — no separate `class_tag` field is needed at any layer of the protocol. See `AXIOM_DESIGN_FactClassIsolation.md` for the complete specification including the three-layer Nabla defense (`pk_bind` anchor + signal agreement + pool routing), the fixed-lifetime dev pool sizing rationale, and the rule R1 truth table.

### 21.3 Genesis Components

At t=0, total AXC supply is allocated per White Paper Section 2.10.

**Yellow Paper only defines protocol-level requirements:**

1. **Total supply conservation** (Section 21.2)
   - All AXC exists at genesis
   - No post-genesis minting or burning
   - Total: 100,000,000 AXC (fixed)

2. **DEED Groups initialization** (Section 21.4)
   - Protocol Team Group created
   - Implementation Team Group created
   - Both immutable post-creation

3. **Minimum validator activation** (Section 21.4)
   - Sufficient validators operational at launch
   - Each staked >= 500 AXC

4. **Market Allocation (for distribution)**
   - Market Allocation: 88,000,000 AXC
   - Held in Reserve Wallet (R_0)
   - Distribution mechanism: F2H (see Section 22)
   - Reserve = wallet for distribution, NOT a minter

**Complete allocation breakdown (per White Paper Section 2.10.8):**

| Component | AXC | Purpose |
|-----------|-----|---------|
| Genesis Validators (10) | 10,000,000 | Locked 3 years |
| Wallet-Based Distribution | 600,000 | Genesis wallets |
| Validator Bootstrap Reserve | 200,000 | Non-genesis validators |
| System Reserve Pool (SRP) | 500,000 | System continuity (NOT user claims) |
| Developer Distribution | 500,000 | Contributor recognition |
| Architecture Contributor Bonus | 200,000 | Protocol contributors |
| **Market Allocation** | **88,000,000** | **F2H distribution (Section 22)** |
| **Total** | **100,000,000** | **Fixed supply** |

**Important distinctions:**

- **Genesis Validators**: Locked 3 years, ensures long-term network alignment
  - **Core-enforced**: `GenesisStakeLocked` rejection for SEND from genesis wallet IDs during lockup.
  - **Lockup start**: `GENESIS_NEWS_ANCHOR` — unix timestamp of the genesis date (2026-03-19), derived from 7 headline anchors (YPX-011). Provable, externally verifiable.
  - **Lockup duration**: `lockup_seconds = 94,608,000` (3 years × 365 days × 86400 sec/day). Baked into Core via `protocol.toml`.
  - **Lockup end**: `GENESIS_NEWS_ANCHOR + lockup_seconds`. Transactions with `epoch < lockup_end` from genesis wallets are rejected.
  - **Exempt**: Burns, DEED, fee, DWP, and oracle TXs are not subject to lockup.
  - **Wallet IDs**: Listed in `genesis_lockup_wallets.txt`, compiled into Core by `build.rs`. Empty in dev/test builds (lockup not enforced when no IDs configured).
  - **Time manipulation resistance**: A validator cannot set its system clock forward to bypass the lockup. TARDIS (YPX-003) enforces a forward-only 0–5 second window on tick advancement, Nabla gossip consensus cross-checks virtual_secs across 6 nodes, and k=3/5 peer witnesses independently verify `tx.epoch`. A forged epoch would be rejected by both Nabla and the other witnesses in the consensus set.
- **System Reserve Pool (SRP)**: System functions, NOT user distribution
- **Market Allocation**: Enters circulation via F2H mechanism (Section 22)

**Yellow Paper does not specify operational details.**

See Bootstrap Guide for:
- SRP management procedures
- Reserve claim policy parameters
- Distribution timelines
- Eligibility criteria

### 21.4 Protocol Requirements (Mandatory)

Genesis state must satisfy:

**Conservation:**
```
Sum(all_allocations) = GENESIS_SUPPLY
No hidden allocations
No delayed unlocks at protocol level
No privileged access to unallocated supply
```

**DEED Initialization:**
```
Protocol Team Group created with:
- Valid group_id
- Member list defined
- Allocation ratios set
- Immutable post-creation

Implementation Team Group created with:
- Valid group_id
- Member list defined
- Allocation ratios set
- Immutable post-creation
```

**Validator Activation:**
```
Minimum active validators >= [threshold]
Each genesis validator stakes >= 500 AXC
Genesis witness set operational before first transaction
```

### 21.5 Console System (Parameter Management)

> **Canonical Authority:** This section (21.5) is the authoritative implementation specification for Console operations. White Paper sections (7.4, 7.8, J.13, J.17, G.1-G.8) provide rationale and philosophy. In case of conflict between documents, this Yellow Paper section takes precedence for implementation purposes. Other documents MUST reference this section rather than re-stating Console mechanics.

**Console >=  Governance**

The Console is a **parameter adjustment mechanism**, not a governance body.

**What Console can do:**
- Adjust digit_version (L$ display scaling)

**What Console CANNOT do:**
- Change protocol rules
- Reverse transactions
- Confiscate assets
- Alter validator selection
- Modify Core logic
- Create new powers or authorities

**Console composition (per White Paper Section 7.4):**

- **Size:** 15 validators (default, fixed by design)
- **Members:** All must be active validators
- **Selection criteria:** Minimum 99% online availability
- **Selection method:** Complete cohort rotation (not individual replacement)
- **Membership type:** No special classes, legal entities, or permanent seats
- **Nature:** Functional instrument, not representative body

**Voting mechanism (per White Paper Section 7.8):**

- **Threshold:** Unanimous approval required (N/N, i.e., 15/15 for default cohort)
- **Decision window:** Fixed 24-hour voting period
- **Outcomes:**
  1. Unanimous YES within 24h -> Action executes
  2. Any explicit NO -> Action fails
  3. Missing votes (first time) -> Automatic retry with same 24h window
  4. Missing votes (second time) -> Entire Console cohort dissolved, new cohort selected

**Critical properties:**

- Disagreement is permitted (explicit NO allowed)
- Silence is NOT permitted (missing votes trigger dissolution)
- No individual replacement mid-term (cohort exists as complete unit or not at all)
- This prevents targeting, scapegoating, and coercive isolation

**Key properties:**

- Console size is **not proportional** to total validators or network size
- Console is **not representative** of validator population
- All Console members are validators, but not all validators are Console members
- Rotating cohort ensures no permanent authority

**Critical distinction:**

Governance = deciding what the rules should be  
Console = executing pre-defined adjustments within fixed boundaries

#### 21.5.1 Proposal and Voting Surface

Console members are validators. Governance therefore operates strictly on two validator-native primitives:

| Primitive | Description |
|-----------|-------------|
| **INITIATE** | Proposal creation |
| **VOTE** | Proposal response |

No additional governance primitives exist.

#### 21.5.2 Initiation Rights and Limits

Only Console members may initiate digit migration proposals.

**Constraints:**

| Constraint | Specification |
|------------|---------------|
| **Active proposals** | At most ONE active proposal per adjustment window |
| **Per-member budget** | Finite initiation budget per member per year |
| **Global budget** | Finite global initiation budget per year |
| **Cooldown** | Rejected or expired proposals enter cooldown, suppressing materially identical re-proposals |

#### 21.5.3 Proposal Object

Each proposal MUST include:

```
Proposal := {
  proposal_id,           // content-addressed hash (deduplication key)
  adjustment_window,     // identifier for the adjustment period
  direction,             // "de-digitize" or "reintroduce_digits"
  magnitude,             // bounded: +/-2 digits maximum
  rationale,             // non-normative explanation (human-readable)
  deliberation_start,    // timestamp: when voting begins
  deliberation_end,      // timestamp: when voting closes
  expiry                 // timestamp: when proposal becomes invalid
}
```

| Field | Description |
|-------|-------------|
| **proposal_id** | Content-addressed hash; duplicate proposals deduplicated by this ID |
| **adjustment_window** | Identifies which adjustment period this proposal targets |
| **direction** | Whether to reduce displayed digits (de-digitize) or increase them |
| **magnitude** | Maximum +/-2 digits per proposal (hardcoded limit) |
| **rationale** | Human explanation; has no protocol effect |
| **deliberation_start** | When Console members may begin voting |
| **deliberation_end** | Voting deadline (default: 24 hours after start) |
| **expiry** | After this timestamp, proposal is invalid regardless of vote state |

#### 21.5.4 Voting Semantics (Objection-Based Consensus)

Voting is **objection-based consensus**, not majority voting.

Each Console member may respond with:

| Response | Meaning |
|----------|---------|
| **ACK** | No sustained objection; member accepts proposal |
| **OBJECT** | Reasoned objection; member rejects proposal |

**Consensus Rules:**

| Condition | Outcome |
|-----------|---------|
| All members ACK within deliberation window | **Action executes** |
| Any member OBJECT | **Action fails** |
| Missing votes (first occurrence) | Automatic retry with same 24h window |
| Missing votes (second occurrence) | Entire Console cohort dissolved |

**Critical Properties:**

- Consensus requires **unanimous ACK** (no objections)
- A single OBJECT blocks the proposal
- Silence is not permitted -- missing votes trigger dissolution
- This is NOT majority voting; it is objection-based consensus

**Why 24-hour Deliberation Window:**

The deliberation window is set to 24 hours to ensure operators across all time zones have opportunity to respond. This delay is intentional -- it allows pressure to surface, enables voluntary exit, and exposes coercion attempts before action is taken.

**Example: Digit Migration**

```
Scenario: `L$` displays become unwieldy (e.g., "0.00000123 `L$`")

Console action:
1. Proposal: Increase digit_version from 3 to 6
2. Consensus: All 15 Console members ACK
3. Execution: digit_version parameter updated
4. Effect: Same AXC atoms now display as "1.23 L$"

What did NOT happen:
- No AXC supply changed
- No balances altered
- No protocol rules modified
- Only display scaling adjusted
```

**Why Console exists:**

Digit scaling adjustments require human judgment about UX optimization but do not constitute "governance":
- When displays become too small or too large
- When user comprehension suffers
- When market convention shifts

This decision is **operational**, not **legislative**.

The protocol pre-defines that digit_version can be adjusted.  
The Console decides when to adjust it.

**Complete Console specification:**

See White Paper (AXIOM v2.28) Section J.13 "The Console: Humans as a Circuit Breaker" and Section J.17 "The Mechanical Bounds of Adjustment: Digit Migration" for detailed rationale and procedures.

**Alignment with Section 13:**

Section 13 rejects:
- Governance committees that make new rules
- Emergency councils with override authority
- Social consensus as binding protocol decisions

Section 21.5 defines:
- Parameter management within pre-defined bounds (digit_version only)
- Execution of pre-programmed adjustment (digit scaling)
- Operational decision that does not alter protocol logic

**No contradiction exists.**

Console executes. Protocol rules.

### 21.6 What Yellow Paper Does NOT Define

- Exact allocation percentages (Bootstrap Guide)
- Validator onboarding procedures (Bootstrap Guide)  
- Market distribution timeline (Bootstrap Guide)
- Operational deployment steps (Bootstrap Guide)
- Console member identities (Bootstrap Guide)
- Console threshold requirements (Bootstrap Guide)
- Digit migration procedures (White Paper + Bootstrap Guide)

### 21.7 Cross-Document Authority

**If conflict between documents:**

1. **White Paper**: Philosophy and economic rationale
2. **Yellow Paper**: Protocol invariants (this document)
3. **Bootstrap Guide**: Implementation procedures

**Yellow Paper binds protocol behavior.**  
**Bootstrap Guide binds deployment execution.**

If Bootstrap Guide contradicts Yellow Paper, Yellow Paper prevails.

### 21.8 Console Governance: Non-Sovereign Parameterization Layer

#### 21.8.1 Purpose and Scope

The Console is a **non-sovereign parameterization interface**.

It exists solely to expose *pre-defined, non-authoritative parameters* required for operational continuity and human--system coordination.

> **The Console does not constitute governance.**

It does not possess discretionary authority, and it cannot alter, suspend, or override the deterministic behavior of the Lambda Core (`axiom-core.elf`).

#### 21.8.2 Authority Boundary

The authority boundary of the Console is strictly defined as follows:

**The Console MAY:**
- Select among parameters explicitly enumerated in the protocol specification
- Adjust display, routing, or coordination parameters
- Trigger workflows whose outcomes are fully determined by `axiom-core.elf`

**The Console MUST NOT:**
- Modify or reinterpret any rule enforced by `axiom-core.elf`
- Introduce new economic variables, supply rules, or validation logic
- Override deterministic outcomes produced by the Lambda Core
- Create emergency powers, fallback authorities, or exceptional execution paths

Any attempt to extend Console behavior beyond these constraints constitutes a **protocol violation** rather than an exercise of governance.

#### 21.8.3 Determinism Preservation

All Console actions are subject to the following invariant:

> **No Console operation may influence the Canonical Bytes, the Transaction ID, the State Hash, or any deterministic output of the Lambda Core.**

In particular:
- Console-triggered processes must resolve identically across all compliant implementations
- Any parameter selected via the Console must be representable as part of the explicit External Parameters (EP)
- Console interaction must never introduce hidden state or implicit context

#### 21.8.4 Console vs Governance

For clarity, the Console explicitly rejects all properties traditionally associated with governance:

| Property | Governance | Console |
|----------|------------|---------|
| Discretionary authority | Yes | **No** |
| Rule modification | Yes | **No** |
| Emergency override | Yes | **No** |
| Normative decision-making | Yes | **No** |
| Deterministic execution | No | **Yes** |

The Console exists to **apply rules**, not to **decide rules**.

#### 21.8.5 Failure Semantics

The Console adheres to the same failure philosophy as the Lambda system:

- In the presence of ambiguity, coercion, or incomplete information, Console-triggered processes **must fail closed**
- Failure to act is always preferable to acting incorrectly
- No Console pathway may compel irreversible state transitions

This ensures that the Console cannot be leveraged as an indirect mechanism for coercion or emergency governance.

#### 21.8.6 Operator Responsibility

While the Console provides a structured interface, responsibility for its operation remains with human operators.

The protocol explicitly recognizes that:
- Operators may be fallible or coerced
- Such risks cannot be eliminated at the protocol layer
- The role of the protocol is to ensure that operator failure cannot corrupt protocol truth

Accordingly, the Console is designed to **limit the blast radius** of operator error or compromise to liveness and coordination, never to correctness or economic integrity.

#### 21.8.7 Summary Invariant

> **The Console is an interface for coordination, not a source of authority.**
> 
> It may influence *when* actions are attempted, but never *what* the system considers true.

### 21.9 Why Emergency Governance Is Rejected

#### 21.9.1 Rationale

The Lambda system explicitly rejects the concept of *emergency governance*.

This rejection is not based on ideological preference, but on a technical assessment of failure modes observed in distributed systems operating under coercion, information asymmetry, or time pressure.

Emergency governance introduces a class of authority whose defining feature is **the suspension of normal constraints**. Such suspension is fundamentally incompatible with a system whose primary invariant is deterministic truth.

#### 21.9.2 The Emergency Fallacy

Emergency governance is commonly justified by the assumption that:

> *Exceptional circumstances require exceptional authority.*

The Lambda system rejects this assumption for the following reasons:

**1. Emergencies are not objectively detectable at the protocol layer**

Any declaration of an "emergency" necessarily relies on external, non-verifiable context. Encoding such declarations into protocol behavior converts subjective narratives into authoritative inputs.

**2. Emergency powers collapse accountability**

When actions are justified by urgency, it becomes impossible to distinguish between necessary intervention and opportunistic override. This ambiguity is irreversible once introduced.

**3. Emergency paths become the dominant attack surface**

In adversarial environments, the existence of an emergency mechanism incentivizes attackers to manufacture or simulate emergencies, as this is the only path capable of overriding deterministic constraints.

#### 21.9.3 Determinism vs. Urgency

The Lambda Core (`axiom-core.elf`) is designed to answer only one question:

> *Given these inputs, what is true?*

It is explicitly **not** designed to answer:
- What action is politically acceptable
- What outcome is socially desirable
- What response is urgent or necessary

Introducing emergency governance would require the Core or its interfaces to evaluate such questions, thereby contaminating deterministic execution with subjective judgment.

**This contamination is irreversible.**

#### 21.9.4 Failure Preference: Refusal Over Intervention

In Lambda, failure semantics are intentional.

When the system encounters:
- Incomplete information
- Unresolvable disagreement
- Coercion or silence
- External pressure to act outside specification

The correct response is **refusal**, not intervention.

Failing to act may reduce liveness or availability, but acting incorrectly permanently corrupts protocol truth.

Emergency governance inverts this priority by privileging action over correctness.

**Lambda does not.**

#### 21.9.5 Relationship to Console and Judicial Processes

The rejection of emergency governance applies uniformly to:
- The Console
- Judicial Freeze Procedures (JFP)
- PWV and ECQ-related mechanisms

None of these components are permitted to:
- Bypass deterministic validation
- Override Canonical Bytes
- Introduce discretionary execution paths
- Justify irreversible actions on the basis of urgency

All such mechanisms are constrained to **fail-closed behavior**.

**Disjoint Failure Domains:**

JFP and Console operate on strictly separated domains. They MUST NOT cross boundaries:

| Domain | Mechanism | Handles | Examples |
|--------|-----------|---------|----------|
| **Coercion** | JFP | Legal pressure, physical coercion, asymmetric enforcement | Validator under government pressure, forced signing |
| **Legibility** | Console | Display scaling, human readability, usability | L$ digits too small, UX degradation |

**Boundary Rules:**

| Condition Type | Responsible Mechanism | The Other MUST NOT Act |
|----------------|----------------------|------------------------|
| Can be framed as **coercion** | JFP exclusively | Console MUST NOT respond |
| Can be framed as **legibility** | Console exclusively | JFP MUST NOT respond |

**Why This Separation Matters:**

- Console responding to coercion = governance capture
- JFP responding to UX complaints = protocol overreach
- Mixing domains creates exploitable ambiguity

**Summary:**

> JFP does not guarantee justice. It guarantees **restraint**.
> Console does not guarantee optimal UX. It guarantees **bounded adjustment**.
> 
> Neither may expand into the other's domain.

#### 21.9.6 Coercion and Safety

From a coercion-resistance perspective, emergency governance is actively harmful.

Any actor endowed with emergency authority becomes a single point of leverage for:
- Legal pressure
- Physical coercion
- Economic threats
- Social manipulation

By rejecting emergency governance entirely, Lambda removes the possibility of forcing compliance through extraordinary authority.

**Silence, refusal, or system-level failure are always valid outcomes.**

#### 21.9.7 Summary Invariant

> **Lambda refuses to distinguish between "normal" and "emergency" states.**
>
> A system that behaves differently under pressure cannot be trusted when pressure is applied.

Emergency governance is rejected because it is incompatible with:
- Deterministic truth
- Coercion resistance
- Irreversible economic correctness

The system therefore prefers **observable failure** over **authoritative intervention**.

### 21.10 Console Membership, Selection, and Execution Semantics

#### 21.10.1 Definition of Console Membership

The Console is composed of a fixed-size set of members, hereafter referred to as *Console Members*.

At system genesis, Console Members are defined as the **bootstrap validator participants**. No additional qualification, election, or governance procedure is required at initialization.

The Console is not a privileged body. Membership confers **no sovereign authority**, and does not imply governance rights.

#### 21.10.2 Target Size and Bootstrap Continuity

The target size of the Console is **15 members**.

However, the protocol explicitly permits operation under the following conditions:

- If the total validator set size is fewer than 15:
  - All validators are eligible to be selected as Console Members
  - The Console may persist with fewer than 15 members
  - No special handling or exception logic is required

This condition is expected during early system phases, as the initial validator population is necessarily limited.

#### 21.10.3 Annual Selection Process

Console membership is re-evaluated on an **annual basis (365 days)**.

Selection is performed via **uniform random sampling** from the active validator set, subject only to validator availability.

Important properties of the selection process:

- Previous Console Members are **not excluded** from re-selection
- No term limits are imposed
- Repeated selection of the same individuals is permitted
- Randomness is the sole selection criterion

As the validator population grows, the probability of repeated selection naturally decreases. When the population remains small, the Console composition is expected to remain stable.

#### 21.10.4 Minimum Size Constraint and Task Inhibition

If the active Console membership is fewer than 15 members:

- **No default Console tasks may be executed**
- The Console remains defined but functionally inert
- No fallback or emergency mechanism is activated

This behavior is intentional. **The inability to act is preferred to acting under insufficient diversity.**

#### 21.10.5 Scope of Console Tasks

The Console does not possess open-ended authority.

All Console tasks are:
- **Predefined** by the protocol specification
- **Non-discretionary**
- **Bounded** in scope
- **Deterministic** in effect

The Console cannot introduce new tasks, reinterpret existing tasks, or exercise judgment outside predefined task boundaries.

#### 21.10.6 Active Console Tasks

The Console has exactly **four** predefined, atomic actions. No new actions can be introduced without a Core ELF update.

**Task 1: Digit Version Coordination (White Paper §7.7)**

Coordination of `digit_version` — the human-facing denomination display convention.

- `digit_version` affects **presentation only** (L$ display scaling)
- Core accounting, settlement, and validation remain bound to `AXC / atom`
- No economic or consensus semantics depend on `digit_version`
- Direction: Dedigitize (+N digits) or Redigitize (-N digits), max ±2 per proposal
- **Effect:** automatic — approved digit_version is applied by our Lambda implementation

**Task 2: Self-Dismissal (White Paper §7.7A)**

Any Console member may initiate a vote to dissolve the current cohort. See §21.5.4.

**Task 3: Core Update Recommendation (YPX-013)**

The Console may recommend that all validators upgrade to a new Core ELF binary. This is a **coordination signal**, not a command.

Key properties:

- **NOT enforceable.** Each validator independently decides whether to adopt the new Core ELF.
- **Split worldline warning:** Validators running different Core versions CANNOT interoperate. Each Core ELF has a unique `core_id` (BLAKE3 hash of the binary). Different `core_id` = different commitments, state hashes, and proofs = separate worldlines.
- **Reality Attestation (C1) resolves** which worldline is canonical if a split occurs. The worldline with more validator support survives.
- **No automatic action.** Unlike digit migration (which our Lambda auto-applies), Core update recommendations require manual operator decision. This is intentional — a Core update changes the fundamental protocol rules.
- **Fan-Out broadcast:** The approved recommendation is broadcast via CL10 Fan-Out (Core-verified) to all validators, along with the rationale and the recommended `core_id`.

```
Console recommends Core update
    ↓
15/15 ACK (unanimous within 24h)
    ↓
CL10 Fan-Out broadcast (Core-verified)
    ↓
Each validator independently decides:
    ├─ Adopt new Core ELF → joins new worldline
    └─ Stay on current Core → stays on current worldline
    ↓
If split occurs:
    └─ Reality Attestation (C1) resolves canonical worldline
```

This design ensures that:
1. Core updates require broad consensus (15/15) to even recommend
2. No single entity can force an upgrade
3. Validators maintain sovereignty over what code they run
4. The protocol handles worldline splits gracefully via C1

**Task 4: Bloom Phase-Out (YPX-018 §4)**

The Console may schedule retirement of one or more frozen bloom eras from the tiered bloom memory architecture (§39.9.5). This is a coordination signal authorizing Nabla nodes to drop the era's authoritative hash records and bloom files at a future tick.

A `BLOOM_PHASE_OUT` proposal carries:

```
ConsoleProposal_BloomPhaseOut {
    era_ids:        Vec<u64>     — bloom eras scheduled for phase-out
    effective_tick: u64           — TARDIS tick when phase-out becomes effective
    rationale:      String        — human-readable justification
}
```

Approval follows the same unanimous-ACK voting pattern as other Console actions. After approval, Core CL11 enforces **constitutional limits** that the Console cannot override:

- `era.end_tick + MIN_PHASE_OUT_AGE_TICKS <= effective_tick` — every era must be at least **50 years past its close** before it can be phased out.
- `effective_tick - proposal_proposed_tick >= MIN_PHASE_OUT_GRACE_TICKS` — at least **5 years of grace** between approval and the effective tick.
- `effective_tick > current_tick` — phase-out is in the future.
- The era exists in the Bloom Age Index AND is not already phased out.

If any rule fails, CL11 refuses to sign and the proposal dies even with 15/15 ACK.

**Combined effect:** any cheque issued in tick T cannot become unreachable before tick T + 55 years, no matter what the Console decides. This is the protocol's constitutional cheque-lifetime floor. The 50-year minimum age is set to span a full adult lifetime — a person who receives a cheque as a young adult can still redeem it in old age, regardless of any Console action in between.

After approval and CL11 signing, the certificate is broadcast via CL10 Fan-Out (`FANOUT_CONSOLE_BLOOM_PHASE_OUT = 0x0104`). Each Nabla node updates its Bloom Age Index for the affected eras to `ScheduledPhaseOut`. During the grace period, queries against affected eras return real answers tagged with a phase-out warning. At `effective_tick`, archive nodes are FREE to drop the era's full hash records and light nodes are FREE to drop the era's bloom file. The Bloom Age Index entry remains forever with status `PhasedOut`, so future queries return a signed `PHASED_OUT` response referencing the original ConsoleCertificate.

Like Tasks 1–3, `BLOOM_PHASE_OUT` is **opt-in for the protocol**. If the Console never proposes phase-out, no era is ever retired and the bloom chain grows without bound (which is fine — at planetary scale it grows ~84 MB per node per year, manageable for citizen hardware indefinitely). The phase-out mechanism exists as an option, not a requirement.

#### 21.10.7 Non-Discretionary Execution Model

Console task execution follows a **broadcast coordination model**, not enforcement.

Specifically:

- Console decisions are disseminated via AXIOM's standard propagation mechanisms
- All validator implementations are expected to:
  - Receive Console decisions
  - Notify their operators of such decisions

Validator behavior in response is implementation-defined:
- Some implementations may apply changes automatically
- Others may require explicit operator confirmation

**There is no protocol-level enforcement.**

#### 21.10.8 Absence of Coercion or Systemic Dependence

Failure to follow Console decisions:

- Does not invalidate transactions
- Does not disrupt consensus
- Does not halt system operation

Console outputs represent **distributed coordination signals**, not binding commands.

This design ensures that:
- Console influence arises from shared agreement, not authority
- Non-compliance degrades coordination, not correctness
- System truth remains independent of Console action

#### 21.10.9 Summary Invariant

> **The Console coordinates predefined parameters through probabilistic representation and information propagation, not through authority or enforcement.**
>
> Its decisions influence human-facing alignment, but never determine protocol truth.

Console membership, task scope, and execution semantics are deliberately constrained to preserve determinism, coercion resistance, and non-governance principles.

### 21.11 Console Integrity, Verifiability, and Non-Reliance Invariants

This section supplements the Console specification to eliminate ambiguity, prevent misinterpretation, and harden the system against narrative, operational, and social-engineering attack surfaces.

**No new authority is introduced.**

#### 21.11.1 Console Decision Authenticity

All Console outputs MUST be represented as **verifiable Console-originated artifacts**.

A Console decision artifact MUST:
- Be cryptographically attributable to the active Console Members
- Include a minimum threshold of Console Member signatures
- Bind explicitly to:
  - The applicable `console_epoch`
  - The predefined `console_task_id`
  - The corresponding `task_version`
  - The applicable External Parameters (EP), if any

Artifacts failing verification MUST be ignored.

This requirement exists solely to prevent forgery, impersonation, and narrative manipulation. It does not confer authority, enforcement power, or finality.

#### 21.11.2 Console Task Identity and Versioning

Each Console task is uniquely identified by:
- `console_task_id`
- `task_version`

Console outputs MUST reference both identifiers.

Unknown or unsupported task identifiers or versions MUST be rejected.

Console Members are not permitted to:
- Define new tasks
- Modify existing task semantics
- Interpret tasks beyond their explicitly specified behavior

This constraint ensures that Console activity remains mechanical, bounded, and non-discretionary.

#### 21.11.3 Explicit Non-Reliance Invariant

> **No component of the Lambda system MAY depend on the Console for:**
> - Safety
> - Liveness
> - Correctness
> - Economic validity
> - State finality

The absence, failure, or inactivity of the Console MUST NOT degrade protocol truth.

Any design that introduces dependency on Console output constitutes a **protocol violation**.

#### 21.11.4 Console Inactivity as a Stable State

Console inactivity, including but not limited to:
- Insufficient membership
- Non-selection
- Non-participation
- Silence or failure to produce output

is explicitly defined as a **valid and stable system state**.

No fallback authority, emergency mechanism, or exceptional execution path may be invoked in response to Console inactivity.

**Inaction is preferred to action under insufficient diversity.**

#### 21.11.5 Prohibition of Emergency Substitution

The following are explicitly prohibited:
- Substituting Console inactivity with emergency governance
- Granting temporary authority to alternate actors
- Introducing discretionary override paths under time pressure
- Reinterpreting predefined tasks due to urgency

Any such mechanism undermines deterministic truth and is incompatible with the Lambda system.

#### 21.11.6 Summary Invariant

> **The Console is observable but non-essential.**
> **Verifiable but non-authoritative.**
> **Defined but not required.**
>
> Its presence may aid coordination.
> Its absence must never endanger correctness.

This invariant is binding across all implementations, present and future.

### 21.12 Console Capability Requirements, Liveness, and Disqualification Semantics

This section further constrains Console behavior to ensure that Console participation reflects actual implementation capability, not nominal selection.

**No new authority is introduced.**

#### 21.12.1 Console Capability Requirement

A validator selected as a Console Member MUST fully implement all Console-related protocol functions defined in the specification, including but not limited to:
- Console decision artifact verification
- Console liveness signaling (ping / heartbeat)
- Console task handling for all predefined `console_task_id`s
- Operator notification pathways for Console outputs

Partial, stubbed, or non-functional implementations do not satisfy this requirement.

#### 21.12.2 Capability-Based Disqualification

If any selected Console Member:
- Lacks full Console functionality, or
- Fails to correctly process Console tasks, or
- Fails to emit required Console liveness signals

then the Console for that epoch MUST be considered **invalid and dissolved**.

No attempt is made to replace, bypass, or compensate for an incapable Console Member.

This rule applies regardless of:
- Validator seniority
- Validator stake
- Validator uptime history
- Duration since last Console rotation

#### 21.12.3 Liveness Check Enforcement

Console Members MUST respond to protocol-defined liveness checks at fixed intervals during the Console epoch.

**Implementation (YPX-013):**

Liveness checks are initiated every 3 months (`CONSOLE_LIVENESS_INTERVAL_TICKS = 1,555,200` ticks). The check is broadcast via CL10 Fan-Out (Core-verified) to all Console members.

Each member must respond with a 1-atom heartbeat TX to the Console group wallet within 72 hours (`CONSOLE_LIVENESS_RESPONSE_TICKS = 51,840` ticks).

```
Liveness check initiated (every 3 months)
    ↓
CL10 Fan-Out to all 15 Console members
    ↓
72h response window
    ├─ ALL 15 respond → "Complete" (Console healthy)
    └─ ANY member missing → "Failed" → ENTIRE CONSOLE DISSOLVED
```

Failure to satisfy liveness requirements results in:
- Immediate Console dissolution
- No partial continuation
- No fallback membership selection
- No individual replacement — the Console either exists as a complete cohort or not at all

**Rationale:** Silence is not permitted (White Paper §7.9). If a Console member has been compromised, coerced, or gone offline, the entire cohort must be replaced. This prevents targeting, scapegoating, and coercive isolation of individual members.

As of v2.11.13, dissolution transitions the Console to the Reforming state. The first nomination submitted after dissolution resets failed_attempts to 0 and current_gen to 1. The resulting fresh Console starts at generation 1 with no history from the dissolved predecessor. No operator intervention is required — reformation proceeds through normal validator participation.

#### 21.12.4 Compensation Eligibility

Eligibility for Console compensation is strictly conditional.

A validator selected as a Console Member:
- MUST fully satisfy capability and liveness requirements
- MUST participate in a valid, non-dissolved Console epoch

If the Console is dissolved for any reason, including capability failure or liveness failure:
- **No Console Member is eligible for Console compensation**
- The standard Console compensation of **1 AXC per full service year** (per White Paper) is forfeited
- No prorated or partial compensation applies, regardless of elapsed time within the epoch

This rule applies uniformly, even if:
- The Console operated for nearly a full year
- Only a single member failed capability requirements

#### 21.12.5 Incentive Alignment Rationale

The strict dissolution and compensation forfeiture rules exist to align incentives toward correct implementation.

Specifically:
- Developers are economically motivated to fully implement Console logic
- Validators are incentivized to deploy compatible software versions
- Partial or negligent implementations are naturally excluded

The protocol does not attempt to distinguish between malicious intent and incomplete engineering. **Only observable behavior matters.**

#### 21.12.6 No Grace Periods or Exceptions

The following are explicitly prohibited:
- Grace periods for incomplete Console implementations
- Manual overrides for compensation eligibility
- Temporary waivers for backward compatibility
- Emergency allowances for legacy validator versions

All validators are treated uniformly. Failure is deterministic, observable, and non-negotiable.

#### 21.12.7 Summary Invariant

> **Console participation is a capability commitment, not an honorary role.**
>
> Selection without implementation dissolves the Console.
> Dissolution voids compensation.
>
> This ensures that Console existence reflects real operational readiness, not symbolic consensus.


## 22. Reserve Distribution Mechanism

### 22.1 Purpose & Scope

**Reserve Pool = Market Allocation (88,000,000 AXC)**

At genesis, 88,000,000 AXC is allocated as "Market Allocation" (White Paper Section 2.10.5). This allocation is held in a **Reserve Wallet** and distributed to users via a claim mechanism.

**Terminology alignment:**

- **White Paper**: "Market Allocation" (88,000,000 AXC)
- **Yellow Paper**: "Reserve Pool" or "Reserve Wallet"
- **Same thing**: AXC held for future user claims

**Why "Market Allocation"?**

After users claim AXC from Reserve:
- AXC enters circulation
- Users can trade, buy, sell (market activity)
- Price determined by market, not protocol

The term "market" refers to post-claim circulation, not the distribution method itself.

**This section defines the protocol-level claim mechanics.**

Complete claim policy parameters, eligibility criteria, and implementation details are defined in the Bootstrap Guide.

**Critical terminology:**

- This is **distribution** (transfer from Reserve), not **issuance** (creation)
- All AXC atoms exist at genesis
- Reserve holds 88,000,000 AXC designated for user claims
- No minting occurs post-genesis

**System Reserve Pool (SRP) is separate:**

- SRP = 5,000,000 AXC (White Paper Section 2.10.3)
- SRP supports system continuity, NOT user claims
- SRP >=  Reserve Pool (completely different allocations)
- This section (22) covers Reserve Pool only

### 22.2 Reserve as a Special Wallet

**Reserve Wallet Structure:**

```
R_0 (at genesis) = {
  state_id: "reserve:b3:genesis...",
  owner_pk: null,                    // No private key ownership
  balance_atom: 880000000000000000,  // 88,000,000 AXC (Market Allocation)
  last_claim_day: 0,
  witness_receipts: [genesis_bootstrap]
}

R_t (after claims) = {
  state_id: "reserve:b3:...",
  owner_pk: null,
  balance_atom: uint64,              // Decreases with each claim
  last_claim_day: uint32,
  witness_receipts: [...]
}
```

**Key properties:**

1. **No private key ownership**
   - Reserve is not controlled by any person or committee
   - Transfers governed by protocol rules, not signatures

2. **Policy-enforced transfers**
   - Core validates Reserve transfer rules (hardcoded)
   - Daily limits, cooldowns, format requirements
   - Similar to covenant-style smart contract

3. **Same mechanics as normal wallet**
   - State tracked via state_id
   - Double-spend prevented by witness/receipt chain
   - **Partition behavior differs from normal wallets** (see below)

**Reserve >=  Global State**

Reserve is a wallet, not a consensus variable:
- No mandatory network-wide synchronization
- Once depleted, becomes inactive (no ongoing coordination)

**Partition behavior (Critical difference):**

Unlike normal wallets, **Reserve claims require online connectivity.**

```
Normal wallet (Ark-Mode):
- Can transact during partition
- Offline transactions valid
- Reconcile when reconnected

Reserve wallet:
- CANNOT claim during partition
- Requires connection to Reserve witnesses
- No offline claim mechanism
- Claims halt if partitioned
```

**Rationale:**

1. **Reserve witness discovery requires network**
   - Must locate current continuity validator (3+1 rule)
   - Diffusion mechanism needs connectivity
   - Cannot operate in isolation

2. **Double-claim prevention**
   - Partition A and B claiming same Reserve simultaneously
   - Would cause guaranteed over-distribution
   - No reconciliation mechanism exists

3. **Not life-critical like normal transactions**
   - Reserve claims are convenience, not survival necessity
   - Users can wait until reconnection
   - No "must transact during disaster" requirement

**If partition occurs:**

```
Network partitions:
- Partition A: Reserve claims HALT (cannot find witnesses)
- Partition B: Reserve claims HALT (cannot find witnesses)

Network reconnects:
- Reserve claims resume
- Continue from last valid state
- No divergent Reserve chains
- No reconciliation needed
```

**This is NOT Ark-Mode behavior.**

Ark-Mode allows offline transactions for survival.  
Reserve claims are optional and require connectivity.

### 22.3 Claim Transaction Format

**A claim transaction transfers atoms from Reserve to claimant:**

```json
{
  "version": "tx.v1",
  "tx_id": "b3:...",
  "timestamp": 1734432100,
  
  "input": {
    "state_id": "reserve:b3:R_t...",    // Current Reserve state
    "owner_pk": null,                    // No key required
    "prev_receipts": [
      {"validator_pk": "...", "sig": "..."},  // k witnesses from R_t
      // ... 
    ]
  },
  
  "outputs": [
    {
      "state_id": "reserve:b3:R_{t+1}...",   // Reserve remainder
      "owner_pk": null,
      "balance_atom": 999000000000,           // Reduced balance
      "witness_set": [...]
    },
    {
      "state_id": "st:b3:U_new...",          // Claimant's new state
      "owner_pk": "ed25519:pk_CLAIMANT...",
      "balance_atom": 1000000000,             // Claimed amount
      "witness_set": [...]
    }
  ],
  
  "witness_fees": [...],                     // Normal DEED allocation
  
  "receipts": [...]
}
```

**Atom conservation:**
```
R_t.balance = R_{t+1}.balance + claimed_amount + fees
```

This is identical to a normal transfer, except:
- Input wallet has no owner_pk
- Transfer rules enforced by Core policy validation

### 22.4 Core Validation Rules

**Reserve transfer validation (hardcoded in Core):**

```c
int validate_reserve_claim(tx_t *tx) {
    // 1. Verify input is Reserve Wallet
    if (!is_reserve_wallet(tx.input.state_id)) {
        return INVALID;
    }
    
    // 2. Verify policy compliance
    if (!satisfies_claim_policy(tx)) {
        return INVALID;  // Daily limit, cooldown, format, etc.
    }
    
    // 3. Verify atom conservation
    uint64_t total_out = 0;
    for (int i = 0; i < tx.outputs.count; i+) {
        total_out += tx.outputs[i].balance_atom;
    }
    total_out += tx.total_fees;
    
    if (tx.input.balance_atom != total_out) {
        return INVALID;
    }
    
    // 4. Normal witness validation
    if (!validate_witness_receipts(tx)) {
        return INVALID;
    }
    
    return VALID;
}
```

**Policy parameters (examples -- exact values in Bootstrap Guide):**

```c
// Policy rules hardcoded in Core at genesis:
#define MAX_DAILY_CLAIM_PER_USER    1000000000  // 1 AXC (atoms)
#define MIN_CLAIM_AMOUNT            100000000   // 0.1 AXC
#define CLAIM_COOLDOWN_SECONDS      86400       // 24 hours
```

**No human authorization required.**  
**No committee approval needed.**  
**Policy is code.**

### 22.4.1 Claimant Eligibility (Anti-Sybil)

**Problem:** How to prevent unlimited claims via sybil wallets?

**Approach:** Hybrid of unrestricted claiming + external proof-of-humanity

**Phase 1: Unrestricted (early distribution)**
- Anyone can claim up to daily limit
- Pure first-come-first-served
- Simple, permissionless
- Vulnerable to bots (accepted tradeoff)

**Phase 2: Proof-of-Humanity (optional, future)**
- Integration with external identity systems
- e.g., WorldCoin, BrightID, government ID verification
- Claimant must provide proof alongside claim transaction
- Validators verify proof before witnessing

**Current implementation: Phase 1 (unrestricted)**

Detailed anti-sybil mechanisms deferred to future policy updates.

**Rationale:**
- Early ecosystem growth prioritizes accessibility over perfect fairness
- Bot activity creates network effect and liquidity
- Identity verification can be added later without protocol changes
- Market forces (fees, competition) naturally limit extreme abuse

### 22.4.1.1 Lifetime Claim Limits (Pending Policy Decision)

**Question:** Can users claim daily until Reserve depletes?

**Policy options under consideration:**

**Option A: No lifetime limit (current)**
- Users can claim daily until Reserve depletes
- First-come-first-served
- Simple but may concentrate to early adopters

**Option B: Lifetime limit per user**
```c
#define MAX_LIFETIME_CLAIM_PER_USER  10000000000  // 10 AXC lifetime
```
- Requires tracking cumulative claims per user
- Needs user identity mechanism (see anti-sybil above)
- Fairer distribution but complex

**Option C: Time-based eligibility windows**
- Different eligibility criteria per year
- Complex, requires ongoing policy decisions
- Rejected (governance-like)

**Current status: [PENDING - Deferred to future policy update]**

For now, daily limits apply with no lifetime cap.  
Future policy updates may introduce lifetime limits.

**Marker:** This is flagged for future resolution. Implementation proceeds with Option A (no lifetime limit) as default.

### 22.4.2 Transaction Signature Model

**Who creates and signs the claim transaction?**

The **claimant** creates and signs the claim transaction.

**Transaction format with claimant signature:**

```json
{
  "version": "tx.v1",
  "tx_id": "b3:...",
  "timestamp": 1734432100,
  
  "claimant_signature": "ed25519:sig_CLAIMANT...",  // Claimant signs entire tx
  
  "input": {
    "state_id": "reserve:b3:R_t...",
    "owner_pk": null,  // Reserve has no owner
    "prev_receipts": [...]
  },
  
  "outputs": [
    {
      "state_id": "reserve:b3:R_{t+1}...",
      "owner_pk": null,
      "balance_atom": 93969000000000000
    },
    {
      "state_id": "st:b3:U_new...",
      "owner_pk": "ed25519:pk_CLAIMANT...",  // Must match claimant_signature
      "balance_atom": 1000000000
    }
  ],
  
  "witness_fees": [...],
  "receipts": [...]
}
```

**Validation:**
```c
int validate_reserve_claim(tx_t *tx) {
    // 0. Verify claimant signature
    pubkey_t claimant_pk = extract_pk_from_signature(tx.claimant_signature);
    if (!verify_signature(tx.claimant_signature, tx.tx_id, claimant_pk)) {
        return INVALID;
    }
    
    // 0.1 Verify claimant_pk matches output receiver
    if (tx.outputs[1].owner_pk != claimant_pk) {
        return INVALID;  // Cannot claim to someone else's wallet
    }
    
    // ... rest of validation (steps 1-4 from Section 22.4)
}
```

**This ensures:**
- Only the intended claimant can submit claim for themselves
- Cannot claim to someone else's wallet without their consent
- Signature proves intent to receive
- Claimant bears transaction fees

### 22.4.3 Special Witness Rule (3+1 Rotating)

**Reserve claims use a special witness configuration:**

**Standard transactions (Section 17):**
- k witnesses required
- k  {3, 4, 5} (Assurance Tiers)
- Witness overlap rule enforced

**Reserve claim transactions:**
- **Exactly 4 witnesses required (3+1 rule)**
- 3 witnesses = new validators (no prior Reserve witnessing required)
- 1 witness = MUST be from previous day's first claim (continuity validator)

**Day-to-day flow:**

**Day 0 (Genesis):**
```
Reserve R_0 -> R_1 (first claim)
Witnesses: {V_A, V_B, V_C, V_D} (any 4 validators, bootstrap)
Continuity validator for Day 1: V_A (designated from this set)
```

**Day 1 (First claim of the day):**
```
Reserve R_t -> R_{t+1}
Witnesses: {V_A, V_E, V_F, V_G}
         ^^^^  ^^^^^^^^^^^^^^
       continuity   3 new validators
      (from Day 0)

Continuity validator for Day 2: V_E (first of new 3)
```

**Day 1 (Subsequent claims):**
```
Reserve R_{t+1} -> R_{t+2} (second claim)
Witnesses: {V_A, V_E, V_F, V_G}  // Same 4 as first claim
OR
Witnesses: {V_A, V_H, V_I, V_J}  // V_A required, others can change

Rule: V_A must witness all claims on Day 1
```

**Day 2 (First claim):**
```
Reserve R_s -> R_{s+1}
Witnesses: {V_E, V_K, V_L, V_M}
         ^^^^  ^^^^^^^^^^^^^^
       continuity   3 new validators
      (from Day 1)
```

**Validation logic:**

```c
int validate_reserve_witnesses(tx_t *tx) {
    // Exactly 4 witnesses required
    if (tx.witness_set.count != 4) {
        return INVALID;
    }
    
    // Get current day's continuity validator
    // (determined by previous day's first claim)
    validator_pk_t continuity = get_reserve_continuity_validator(current_day);
    
    // Verify continuity validator is in witness set
    bool has_continuity = false;
    for (int i = 0; i < 4; i+) {
        if (tx.witness_set[i].validator_pk == continuity) {
            has_continuity = true;
            break;
        }
    }
    
    if (!has_continuity) {
        return INVALID;  // Must include continuity validator
    }
    
    return VALID;
}
```

**Continuity validator selection:**

```
First claim of Day N designates continuity for Day N+1:
- Take first of the 3 new validators
- Publish as "Day N+1 continuity validator"
- All Day N+1 claims must include this validator
```

**Rationale:**

1. **Continuity validator ensures state chain integrity**
   - At least one witness "carries" knowledge from previous day
   - Prevents isolated forgery attempts
   - Creates audit trail across days

2. **3 new validators prevent centralization**
   - No permanent Reserve witness authority
   - Distributes witnessing across network
   - Daily rotation prevents capture

3. **Fixed 4 witnesses simplifies discovery**
   - Not variable (3, 4, or 5)
   - Predictable witness set size
   - Easier caching and coordination

**Exception: General witness overlap rule does NOT apply**

Unlike normal transactions (Section 17.3), Reserve claims do NOT require general witness overlap. Only the specific continuity validator (1 of 4) is required.

```
Normal transaction: "At least 1 common witness with previous tx"
Reserve claim: "Exactly the designated continuity validator"
```

This is a special case because Reserve state is singular and high-visibility.

### 22.5 Security: Preventing Forgery

**Q: Can a malicious validator forge a Reserve transfer?**

**A: No, for the same reasons they cannot forge any wallet transfer.**

**Protections:**

1. **Policy validation (Core enforces)**
   - Validator cannot bypass hardcoded claim limits
   - All validators verify policy independently
   - Forged claims rejected by honest witnesses

2. **State chain integrity**
   - Must reference previous Reserve state R_t
   - Must include valid receipts over R_t
   - Cannot skip states or double-spend

3. **Witness overlap rule (Section 17.3)**
   - Must have k witnesses in common with R_t
   - Prevents isolated forgery

4. **Atom conservation**
   - R_t.balance = R_{t+1}.balance + claimed + fees
   - Verified by all witnesses
   - Cannot create atoms from nothing

**Result:**

Reserve security = wallet security + policy enforcement  
No special "reserve authorization key" needed  
No committee control

### 22.6 Finding Reserve Witnesses (Operational)

**Challenge:** Clients only know their local validator, not which validators currently witness Reserve.

**Solution:** Diffusion with daily caching (similar to recovery, Section 18)

**Discovery flow:**

```
Day N begins:
1. Claimant asks local validator Vx: "I want to claim"

2. If Vx has cached Reserve witnesses for day N:
   -> Send claim directly to cached witnesses
   
3. If Vx does NOT have cache:
   -> Diffuse RESERVE_LOCATE(day=N)
   -> Current Reserve witnesses respond via diffusion
   -> Response includes: state_id + receipts proof
   -> Vx caches for ~24 hours
   -> Send claim to discovered witnesses

4. Reserve witnesses validate claim
   -> If valid: sign receipts over (R_{t+1}, U_claimant)
   -> Return receipts to Vx -> Vx -> Claimant
```

**Why diffusion is acceptable here:**

Unlike court evidence (DWP):
- No life-threatening coercion risk
- No need for Decoy Witness Protection
- High-volume public service (many claimants)
- Discovery overhead amortized across many claims

**Witness rotation:**

Reserve witness set may rotate (max once per day, implementation detail).  
Rotation reduces witness load and prevents permanent authority.

**Caching efficiency:**

First claimant of day N triggers discovery.  
Subsequent claimants use cached result.  
Reduces network load dramatically.

### 22.6.1 Discovery DoS Protection

**Threat:** Malicious flood of RESERVE_LOCATE queries to overwhelm network and Reserve witnesses.

**Protection mechanisms:**

1. **Query deduplication**
   ```
   - Each RESERVE_LOCATE has unique query_id
   - Validators deduplicate by query_id within TTL window
   - Same query only propagated once per validator
   - Prevents amplification attacks
   ```

2. **Rate limiting at validators**
   ```
   - Validators limit RESERVE_LOCATE responses
   - Example: Max 100 responses per hour per validator
   - Legitimate queries succeed (low volume)
   - Spam queries dropped (high volume)
   ```

3. **Proof-of-work for discovery** (optional)
   ```
   - RESERVE_LOCATE may require small PoW
   - Cost: negligible for legitimate users
   - Cost: prohibitive for spam (thousands of queries)
   - Implementation detail (Bootstrap Guide)
   ```

4. **Cache propagation**
   ```
   - Once discovered, validators broadcast cache
   - Reduces need for repeated LOCATE queries
   - "First claim of day" bears discovery cost
   - Others benefit from cached result
   ```

**Result:**

Legitimate Reserve discovery: fast and cheap  
Malicious flooding: expensive and ineffective

**Implementation:** Bootstrap Guide specifies exact DoS protection parameters.

### 22.7 Reserve Depletion & Over-Distribution

**When Reserve runs out:**

```
When R_final.balance_atom approaches 0:
- Claims continue until Reserve fully depleted
- Final claims may succeed even if they exceed remaining balance slightly
- No special protocol handling needed
```

**Over-distribution is accepted:**

Unlike strict blockchain models, Lambda accepts that Reserve claims may result in total distribution slightly exceeding 88,000,000 AXC.

**Why over-distribution is tolerated:**

1. **Wallet-centric model**
   - Lambda trusts authenticated client wallet state
   - No global ledger to detect exact total supply
   - Cannot reliably count "how much AXC exists in circulation"

2. **Concurrent claim races**
   ```
   Reserve balance: 1.2 AXC
   
   Claim A: 1 AXC (submitted)
   Claim B: 1 AXC (submitted 10ms later)
   
   Both reference same R_t state
   Both may be witnessed and succeed
   Total distributed: 2 AXC (exceeds 1.2 AXC remaining)
   ```

3. **Operational tolerance**
   - Small over-distribution (even 1 AXC, 100 AXC, or 1M AXC) has negligible economic impact
   - 100M target is approximate, not absolute
   - System designed for survival, not perfect accounting

4. **Static after claim period ends**
   - Once Reserve claim period closes, distribution becomes static
   - No ongoing minting or burning
   - Over-distribution amount frozen
   - Acts as de facto total supply going forward

**Critical distinction:**

```
Protocol target: "Supply >=100M AXC"
Reality: "Supply = 100M +/- claim race conditions"

This is acceptable because:
- Variance is small relative to total
- No ongoing inflation mechanism
- Economic incentives remain intact
- Early-stage tolerance for operational realities
```

**Post-depletion state:**

```
When Reserve depleted:
- Reserve state chain remains (historical record)
- No more claims possible
- Claim transactions fail naturally
- No special "depletion event" handling
```

**Reserve as historical record:**

Even after depletion:
- Transaction history preserved
- Audit trail intact
- Witness receipts remain valid
- Total distribution calculable (if desired, not enforced)

**No ongoing coordination required after depletion.**

### 22.8 Genesis Allocation

**At genesis (t=0):**

```
Total AXC supply: 100,000,000 AXC (fixed, per White Paper Section 2.10)

Genesis allocation breakdown:

1. Wallet-Based Distribution: 1,000,000 AXC
   - 1 AXC per genesis wallet
   - Direct allocation (not via Reserve)

2. Validator Bootstrap Reserve: 10,000 AXC
   - Matching stake for early validators
   - Direct allocation

3. System Reserve Pool (SRP): 5,000,000 AXC
   - System continuity functions
   - Bootstrap operations, recovery flows
   - NOT for user claims (separate from Reserve Pool)
   - Direct allocation

4. Developer Distribution: 10,000 AXC
   - Symbolic recognition for contributors
   - Direct allocation

5. Architecture Contributor Bonus: 10,000 AXC
   - Final protocol contributors
   - Direct allocation

6. Market Allocation (Reserve Pool): 88,000,000 AXC
   - Held in Reserve Wallet (R_0)
   - Available for user claims
   - This IS the "Reserve Pool" described in Section 22
   - Enters circulation via claim mechanism

Total: 100,000,000 AXC
```

**Critical clarification:**

**"Market Allocation" (White Paper Section 2.10.5) = Reserve Pool for claims**

The White Paper states:
> "All remaining AXC supply enters circulation exclusively through market activity."

This means:
- The 88,000,000 AXC "Market Allocation" is held in Reserve Wallet
- Users claim AXC from this Reserve
- After claiming, users can engage in market activity (buy/sell/trade)
- The term "market activity" refers to post-claim circulation, not genesis distribution method

**Reserve Pool (R_0) initial balance: 88,000,000 AXC**

**System Reserve Pool (SRP) is separate:**
- SRP = 5,000,000 AXC (direct allocation at genesis)
- SRP >=  Reserve Pool (user claims)
- SRP supports system functions, not user claims
- Managed separately (White Paper Section 2.10.3)

### 22.9 What Yellow Paper Does NOT Define

**Bootstrap Guide specifies:**

- Claim policy parameters (daily limits, cooldowns, eligibility)
- Witness rotation schedule for Reserve Wallet
- Claim distribution timeline (when claims become available)
- Eligibility criteria for claimants (if any)
- User interface for claim submission
- Reserve witness discovery optimization

**Yellow Paper only defines:**

- Reserve = wallet with policy-enforced transfers
- Core validation rules (structure and atom conservation)
- Security model (same as wallet security, no special authorization)
- Discovery mechanism (diffusion with caching)
- Genesis allocation (88,000,000 AXC per White Paper Section 2.10.5)

### 22.10 Design Rationale

**Why Market Allocation exists:**

Genesis cannot meaningfully distribute 88M AXC directly:
- Recipients not yet identified at t=0
- Phased distribution desired for ecosystem growth
- Allows market-based price discovery post-claim
- Prevents massive wealth concentration at genesis

**Why "Market Allocation" terminology:**

White Paper uses "Market Allocation" to emphasize:
- After claiming, AXC enters market circulation
- Price determined by supply/demand, not protocol
- No predefined price or allocation preference
- Distribution method (claim) >=  market pricing mechanism

**Why Reserve = wallet (not minter):**

Maintains protocol invariant:
- No post-genesis minting
- Supply fixed at genesis (100M AXC)
- Distribution >=  creation
- Claim = transfer from existing supply

**Why policy-based (not key-based):**

Avoids:
- Permanent authority (keyholder becomes king)
- Committee governance (capture risk)
- Single point of failure (key loss/theft)
- Human discretion in distribution

Enables:
- Programmatic rules (no human approval)
- Decentralized validation (all validators enforce)
- Time-limited distribution (Reserve depletes naturally)
- Predictable claim eligibility

**Alignment with Lambda principles:**

- Rules > people (policy is code)
- No governance (no committee approval for claims)
- No permanent authority (Reserve depletes, witnesses rotate)
- Partition tolerant (Reserve = wallet, can diverge)
- Fixed supply (no minting, only distribution)

**Distinction from System Reserve Pool (SRP):**

| Attribute | Reserve Pool (Section 22) | System Reserve Pool (SRP) |
|-----------|---------------------------|---------------------------|
| Amount | 88,000,000 AXC | 5,000,000 AXC |
| Purpose | User claims | System continuity |
| Mechanism | Policy-based claim | Operational management |
| Authority | Protocol rules | Bootstrap/operational |
| Depletion | Yes (via claims) | Managed separately |

These serve different functions and must not be confused.


## 23. Failure Handling and Fail-Closed Semantics

### 23.1 Purpose and Scope

This section consolidates and formalizes the failure-handling principles already embedded across the Lambda system.

It introduces **no new mechanisms** and **no new authority**.

Its purpose is to make explicit the system-wide invariant:

> **Failure is a first-class, acceptable, and intentional system outcome.**
> **Acting incorrectly is not.**

This section applies uniformly to:
- Lambda Core (`axiom-core.elf`)
- Validators and Meta-Validators
- Console operations
- Judicial and coordination processes
- Economic and operational layers

### 23.1.1 Fault-Model Label (NORMATIVE)

The protocol's fault model is **non-equivocation-enforced fail-stop**, not classical
Byzantine Fault Tolerance. This subsection is the authoritative technical statement of
the model. Informal characterizations elsewhere — including the White Paper's
audience-level "k-of-k Byzantine Fault Tolerant" phrase — are descriptive and do
**NOT** override it; the White Paper's wording is retained deliberately and is
non-normative.

> **This is a technical decision, and it is why this section differs from the White
> Paper.** The White Paper speaks to a general audience; the Yellow Paper is the
> technical authority. Where the two differ on the fault-model label, the difference
> is intentional and this section governs.

What the model assumes and provides:

- **Fail-stop faults are tolerated.** Validators and Nabla nodes may crash, partition,
  or go silent at any time. The response is fail-closed refusal (§23.3), never
  substitution or repair.
- **Equivocation is not masked by voting — it is made non-viable by cryptographic
  gates.** Classical BFT tolerates `f` Byzantine members inside a quorum by outvoting
  them (`n ≥ 3f+1`). AXIOM has no such threshold: witnessing is **k-of-k unanimous**,
  so no minority is ever outvoted and correctness never rests on an honest-majority
  assumption *within a round*. Byzantine *behaviours* are instead prevented or
  detected-and-banned by construction:
  - a validator cannot forge Core's deterministic output (canonical ELF, dual-VM
    attestation — §24, §26);
  - it cannot fabricate a receipt (k signatures over the receipt commitment,
    state-anchored verification — §17);
  - it cannot equivocate on a wallet's state chain without detection (S-ABR overlap +
    Nabla consume-once + same-sequence fork ban → status `Banned` — §17, §4.6 check);
  - it can always *withhold*, which costs liveness, never safety (fail-closed, §23.3).
- **Liveness consequence, stated plainly.** A single unresponsive witness fails the
  round closed. k-of-k trades availability for the removal of the intra-round
  honest-majority assumption. This is deliberate (§12, §23.9.6).
- **What is NOT claimed.** Tolerance of an actively malicious validator *binary*
  participating undetected (adversarial-binary end-to-end testing remains an open
  evaluation item), and no quantified bound for full witness-population compromise
  (§14 Open Questions).

Label rule for derived documents: technical documents (this Yellow Paper, protocol
papers) MUST describe the model as *consensus-free, k-of-k witnessed,
non-equivocation-enforced fail-stop*. The White Paper keeps its audience-level
phrasing unchanged by design.

### 23.2 Failure as a First-Class Outcome

Lambda does not treat failure as an exception to be eliminated.

Instead, failure is an explicit and modeled outcome of the protocol.

The system distinguishes between:
- **Correct failure** (refusal, dissolution, non-action)
- **Incorrect action** (state corruption, rule override, ambiguity resolution)

**Only the former is permitted.**

### 23.3 Failure Domains

Failures are categorized by domain. Each domain defines where failure is permitted and where it is strictly prohibited.

#### 23.3.1 Truth Domain (Core)

| Aspect | Specification |
|--------|---------------|
| **Scope** | Canonical Bytes, txid, state_hash, validation logic |
| **Rule** | Failure is **NOT** permitted |

**Behavior:**
- Deterministic execution MUST always produce a result
- Invalid or inconsistent inputs are rejected, not repaired
- No silent fallback or reinterpretation is allowed

Any mechanism that allows ambiguity or override in this domain constitutes a **protocol violation**.

#### 23.3.2 Coordination Domain

| Aspect | Specification |
|--------|---------------|
| **Scope** | Console tasks, parameter coordination, human-facing alignment |
| **Rule** | Failure is **permitted and expected** |

**Behavior:**
- Insufficient membership -> dissolution
- Capability failure -> dissolution
- Liveness failure -> dissolution
- Dissolution results in non-action, not substitution

**Coordination failure does not affect protocol truth.**

#### 23.3.3 Judicial / Procedural Domain

| Aspect | Specification |
|--------|---------------|
| **Scope** | JFP, PWV, freeze-related procedures |
| **Rule** | **Fail-closed** |

**Behavior:**
- UNVOTED = FAIL
- SILENT = FAIL
- PARTIAL participation = FAIL
- Absence does not trigger emergency substitution

**Failure indicates refusal to act, not an error condition.**

#### 23.3.4 Economic Domain

| Aspect | Specification |
|--------|---------------|
| **Scope** | Validator participation, EMVT dynamics, market structure |
| **Rule** | **Degradation without intervention** |

**Behavior:**
- Falling below EMVT increases ambiguity and exit pressure
- No automatic parameter tuning or authority escalation occurs
- Economic stress is observable but non-corrective

**The protocol does not attempt to stabilize markets.**

### 23.4 Failure Triggers (Non-Exhaustive)

Failure may be triggered by, but is not limited to:
- Insufficient diversity (e.g., Console < 15 members)
- Incomplete capability implementation
- Liveness timeout or heartbeat failure
- Ambiguous or conflicting inputs
- Inconsistent Canonical Bytes or EP
- Validator absence beyond protocol-defined bounds
- Economic attrition or validator exit

**In all cases, failure results in non-action.**

### 23.5 Prohibition of Failure Escalation

The following responses to failure are explicitly **prohibited**:
- Emergency governance
- Temporary authority grants
- Manual overrides
- Exceptional execution paths
- Substitution of missing participants with discretionary actors
- Reinterpretation of rules under urgency

Failure MUST NOT be used as justification to expand authority or bypass deterministic constraints.

### 23.6 Failure vs Emergency

Lambda explicitly rejects the distinction between "normal operation" and "emergency operation".

The protocol does not recognize emergencies as a valid input category.

> **A system that behaves differently under pressure cannot be trusted when pressure is applied.**

Therefore:
- Failure under stress is acceptable
- Correctness under stress is mandatory
- Action under stress is not required

### 23.7 System-Wide Failure Flow (Informative)

```
            +------------------------+
            |  Input / Event Occurs  |
            +------------------------+
                        |
            +-----------v-----------+
            |  Deterministic Checks |
            |  (CB / EP / Core)     |
            +-----------------------+
                        |
          +-------------v-------------+
          |  Inconsistency Detected?  |
          +---------------------------+
                        |
            Yes --> Reject
                        |
                        No
                        |
      +-----------------v------------------+
      |  Requires Coordination / Procedure |
      +------------------------------------+
                        |
        +---------------v--------------+
        |  Capability / Liveness OK?   |
        +------------------------------+
                        |
            No --> Fail (No Action)
                        |
                        Yes
                        |
             +---------v---------+
             |   Action Executes |
             |  Deterministically|
             +-------------------+
```

### 23.8 Summary Invariant

> **Lambda allows systems to stop.**
> **It does not allow systems to lie.**
>
> **Failure is acceptable.**
> **Incorrect action is not.**
>
> Every failure is:
> - Observable
> - Attributable
> - Bounded


### 23.9 Settlement Domain Identity and Permanent Partition

**Critical Design Principle:**

> **Historical divergence MUST be irreversible at the protocol level.**

This section addresses a fundamental ambiguity in distributed settlement systems: what happens when a network partition heals?

#### 23.9.1 The Split-Rejoin Problem

**Background:**

AXIOM does not rely on global chain or total ordering. Settlement truth is determined exclusively by deterministic evaluation of `axiom-core.elf` across overlapping validators.

During design review, a critical ambiguity was identified:

1. Network partitions (splits) are inevitable in real-world infrastructure
2. After a split, two partitions MAY later regain connectivity  
3. If both partitions resume execution under identical `axiom-core.elf` logic, naive designs allow the appearance of "rejoining" into a single domain

**The Fatal Economic Risk:**

Conflicting but locally-valid histories could be perceived as mergeable, leading to:
- Ambiguity in asset disposition
- Double-spend across partition boundaries
- Irreversible economic damage
- Loss of semantic finality

**Key Insight:**

The problem is NOT validator disagreement.  
The problem is allowing **historical divergence** to become observationally indistinguishable from **historical continuity**.

**Why This Design Is Necessary:**

Traditional blockchain systems avoid this problem through global consensus - everyone agrees on a single chain. But AXIOM explicitly rejects global consensus for several reasons:

1. **Partition resilience:** Global consensus fails during network splits
2. **Human autonomy:** Validators must make sovereign decisions
3. **Fail-stop architecture:** "Can crash, must not lie"

Without global consensus, we need a different mechanism to prevent split-rejoin ambiguity.

**Why Not Just Check axiom-core.elf Fingerprint?**

Initial approach: If two partitions are running the same `axiom-core.elf` binary, they would be expected to rejoin.

**This is insufficient because:**

1. **Temporal divergence:** Both partitions could be running the same binary but have executed different transactions during the split
2. **State ambiguity:** Alice's balance could be 100 AXC in Partition A and 50 AXC in Partition B (both locally valid)
3. **Double-spend risk:** Alice could spend 50 AXC in both partitions, creating 100 AXC of conflicting obligations
4. **Silent merge:** Without additional verification, partitions could rejoin and create economic chaos

**axiom-core.elf fingerprint proves code identity, not execution history identity.**

**Why Not Just Compare State Hashes?**

Alternative approach: Check if the current state (all wallet balances, etc.) is identical.

**This is insufficient because:**

1. **Collision attacks:** State could coincidentally match even after divergent execution
2. **Partial overlap:** Some accounts might match, others might not - how do you resolve?
3. **Computational cost:** Comparing entire state is expensive
4. **Missing the point:** Even if state matches now, the HISTORY diverged - semantic finality is lost

**The Real Requirement:**

We need to verify **continuous execution history**, not just current state or code identity.

**Design Decision: Monotonic Lineage Hash**

Instead of storing full history (unbounded growth) or just state (insufficient), we use a rolling cryptographic commitment:

```
lineage_hash_next = H(lineage_hash_current || sdid || core_version || transition)
```

**Why this works:**

1. **Fixed size:** Always 32 bytes, regardless of history length
2. **History binding:** Each hash incorporates ALL previous history (via chain)
3. **Divergence amplification:** One different transaction -> permanently different hash forever
4. **Cryptographic security:** Cannot forge without SHA3-256 collision
5. **Minimal overhead:** One hash computation per transaction

**Why SHA3-256 Instead of BLAKE3?**

We already use BLAKE3 for transaction fingerprints. Why different hash for lineage?

**Defense in depth:**
- SHA3-256: Keccak sponge construction (NIST FIPS 202)
- BLAKE3: ChaCha-based construction
- Different mathematical foundations reduce systemic risk
- If one hash function is broken, the other still protects

**Also:**
- SHA3-256 has longer standardization history
- Clear 100-year portability specification
- Well-understood security proofs

**Why Include SDID in Every Hash?**

```
lineage_hash = H(... || sdid || ...)
```

Even though SDID doesn't change, we include it in every hash computation.

**Reasoning:**

1. **Domain separation:** Prevents cross-domain hash collision attacks
2. **Explicit binding:** Makes it impossible to "move" a lineage to different domain
3. **Security margin:** Extra input to hash function increases preimage difficulty
4. **Future-proofing:** If we ever support SDID changes, this structure is already correct

**Why Include core_version_id in Every Hash?**

```
lineage_hash = H(... || core_version_id || ...)
```

**Reasoning:**

1. **Code evolution tracking:** Lineage tracks not just transactions but which code executed them
2. **Upgrade detection:** Core version change -> lineage diverges -> must verify intentional
3. **Attack prevention:** Attacker can't modify axiom-core.elf and then restore it to hide the modification
4. **Historical honesty:** Lineage proves "I executed these transactions with this code"

**Example Attack This Prevents:**

Without core_version_id in lineage:

1. Malicious validator modifies `axiom-core.elf` to steal 100 AXC
2. Executes theft transaction
3. Restores original `axiom-core.elf` 
4. Lineage looks normal (no evidence of modified code)
5. Validator rejoins network with stolen funds

With core_version_id in lineage:

1. Malicious validator modifies `axiom-core.elf` (core_version_id changes)
2. Next lineage hash includes new core_version_id -> diverges
3. Even if validator restores original axiom-core.elf later
4. Lineage already diverged -> cannot rejoin
5. Attack detected and prevented

#### 23.9.2 Settlement Domain Identity (SDID)

**Definition:**

Each settlement domain is identified by a **Settlement Domain ID (SDID)** - a 32-byte unique identifier established at genesis.

**SDID MUST be included in:**
- All state commitments
- All witness envelopes  
- All signature domain separation tags
- All lineage derivations

**Enforcement Rule (FAIL-STOP):**

```
IF artifact.sdid != local.sdid THEN
    REJECT with ValidationError::InvalidSDID
END
```

Artifacts with mismatched SDID are rejected immediately. No exceptions.

#### 23.9.3 Core Lineage Invariance

**The Permanent Split Guarantee:**

AXIOM explicitly forbids automatic or implicit rejoining after partition.

If two execution histories diverge under the same SDID, they MUST NOT be:
- Merged
- Reconciled  
- Bridged by protocol logic

**Enforcement Mechanism: Monotonic Lineage Hash**

`axiom-core.elf` maintains an internal, strictly monotonic lineage state:

```rust
struct LineageState {
    sdid: [u8; 32],              // Settlement Domain ID
    core_version_id: [u8; 32],   // Current axiom-core.elf fingerprint
    lineage_hash: [u8; 32],      // Monotonic commitment
}
```

**Initialization (Genesis):**

```
lineage_hash_0 = SHA3-256(
    "AXIOM-GENESIS" ||
    sdid ||
    core_version_id
)
```

**Evolution (Every State Transition):**

```
lineage_hash_next = SHA3-256(
    lineage_hash_current ||
    sdid ||
    core_version_id ||
    transition_digest
)
```

Where `transition_digest` is the canonical hash of the state transition being executed.

**Properties:**
- Fixed-length (32 bytes)
- Strictly monotonic (cannot rewind)
- Cannot be reset, forked, or rewound
- No historical data carried (only rolling commitment)
- Divergent execution -> different lineage_hash forever

#### 23.9.4 Witness Structure Requirements

**Every witness or state proof MUST include:**

```rust
struct WitnessEnvelope {
    sdid: [u8; 32],
    core_version_id: [u8; 32],
    lineage_hash: [u8; 32],
    transition_digest: [u8; 32],
    signature: SignatureData,
    // ... other fields
}
```

#### 23.9.5 Core Verification Logic (FAIL-STOP Rules)

Upon receiving any artifact `A`:

```rust
// Rule 1: SDID match
if A.sdid != local.sdid {
    return Err(ValidationError::InvalidSDID);
}

// Rule 2: Core version match
if A.core_version_id != local.core_version_id {
    return Err(ValidationError::CoreVersionMismatch);
}

// Rule 3: Lineage continuity
let expected = compute_next_lineage(
    local.lineage_hash,
    A.transition_digest
);

if A.lineage_hash != expected {
    return Err(ValidationError::LineageBreak);
}
```

**Effect:**

- A `axiom-core.elf` instance that ever executes divergent logic will derive a different `lineage_hash`
- Even if it later restores the correct `axiom-core.elf` and SDID, it cannot compute the expected `lineage_hash`
- Rejoining becomes mathematically impossible without breaking hash security (SHA3-256 collision resistance)

**Why Three Separate Checks Instead of One?**

The verification has three distinct rules instead of just checking lineage_hash. This might seem redundant.

**Reasoning:**

1. **Clear error attribution:**
   - `InvalidSDID` -> Wrong settlement domain (configuration error or attack)
   - `CoreVersionMismatch` -> Code version disagreement (upgrade coordination needed)
   - `LineageBreak` -> Execution history diverged (permanent split)

2. **Different recovery procedures:**
   - SDID mismatch -> Cannot recover (different domains)
   - Core version mismatch -> Can recover (coordinate upgrade)
   - Lineage break -> Cannot recover (partition permanent)

3. **Fail-stop clarity:**
   - Validator needs to know WHY validation failed
   - Helps distinguish bugs from attacks from partitions
   - Aids in human decision-making during crisis

4. **Defense in depth:**
   - Even if lineage hash computation had a bug, SDID and core version still checked
   - Multiple independent verification layers
   - Reduces systemic risk

**Why FAIL-STOP Instead of Logging Warning?**

When lineage breaks, we could theoretically:
- Log a warning
- Accept the transaction anyway
- Let humans decide later

**We chose immediate FAIL-STOP because:**

1. **Economic finality:** Once accepted, transactions create obligations - cannot undo
2. **No trusted humans:** In partition scenario, both sides believe they're correct
3. **Attack surface:** Allowing "provisional acceptance" creates attack vectors
4. **Simplicity:** Clear rule easier to implement correctly than complex policy

**The rule is absolute:** Lineage break -> reject -> stop. No exceptions.

**Why Not Allow Manual Override?**

Could we have an "admin override" that lets humans accept artifacts with lineage break?

**No, because:**

1. **Who is admin?** During partition, both sides have admins who think they're right
2. **Social engineering:** Attackers could impersonate admins
3. **Complexity:** Override logic introduces bugs
4. **Philosophical:** AXIOM trusts math, not humans

**If rejoining is genuinely needed after partition:**
- This is a GENESIS-level event
- Requires new SDID
- Explicit asset migration
- Not automated recovery

This is intentional: we prefer clear domain death over ambiguous domain merge.

#### 23.9.6 Intentional Trade-offs

**This design intentionally sacrifices:**
- Seamless recovery after partition
- Rollback and repair of faulty execution
- Silent compatibility across divergent histories

**In exchange, AXIOM guarantees:**
- No post-partition economic ambiguity
- No silent semantic slip
- No merge of conflicting finalized dispositions
- Mathematical enforcement of "fail-stop, not fail-wrong"

**Why We Accept These Trade-offs:**

Most distributed systems prioritize **availability** - they want the network to keep running even during partitions. This leads to designs like eventual consistency, CRDTs, or Byzantine fault tolerance.

AXIOM prioritizes **correctness** over availability.

**The reasoning:**

1. **Money is different from data**
   - Social media post can be eventually consistent
   - Balance sheet cannot - double-spend creates real economic harm
   - Wrong answer about money is worse than no answer

2. **Fail-stop is safer than fail-wrong**
   - If system crashes, users know something is wrong
   - If system lies (wrong balances), users act on false information
   - Recovery from crash: possible
   - Recovery from lies: impossible (obligations already created)

3. **Partitions are rare but catastrophic**
   - Network partitions don't happen often (modern infrastructure is reliable)
   - But when they do happen, economic stakes are enormous
   - Better to handle rare case correctly than optimize common case incorrectly

4. **Human judgment is required for edge cases anyway**
   - Automated recovery from partition requires trusting some oracle
   - But who decides which partition is "correct"?
   - Rather than pretend algorithm can decide, we force explicit human choice

5. **Transparency over convenience**
   - Silent rejoining feels convenient but hides the split
   - Explicit split forces stakeholders to acknowledge what happened
   - Better for users to know domain died than to discover later their assets were in wrong partition

**Real-world analogy:**

Traditional banking: If two bank branches lose connectivity:
- They don't let customers keep spending
- They STOP accepting transactions
- They wait for connectivity to restore
- Then they reconcile carefully

They prioritize correctness (no double-spend) over availability (sorry, bank is closed).

AXIOM follows the same principle, but enforces it mathematically rather than socially.

**Domain Death vs Economic Ambiguity:**

Under this design:
- A permanent partition may result in domain death
- But domain death is CORRECT under uncertainty
- Economic ambiguity is NEVER acceptable

This aligns with AXIOM's foundational principle:

> **"Can crash, must not lie."**

**What About Users' Funds?**

If domain dies due to permanent partition, what happens to users' money?

**Answer:**

1. **Funds are not destroyed** - they're in one partition or the other
2. **Humans decide** - stakeholders choose which partition to honor
3. **Migration path exists** - can manually move assets to new domain
4. **Social layer resolves** - not protocol layer

This is actually SAFER than automatic resolution because:
- No algorithm can know which partition represents "true intent"
- Humans can consider context (which validators were malicious? which transactions were legitimate?)
- Explicit choice prevents accidents

**Could This Kill the Network?**

Worst case scenario: Major partition -> lineage diverges -> domain splits permanently -> both sub-domains too small to function.

**Mitigation:**

1. **Ark mode:** Wallets can survive offline indefinitely (Section 11)
2. **New genesis:** Can always start fresh with new SDID
3. **Asset recovery:** Can prove ownership and migrate
4. **Social coordination:** Community can coordinate recovery

**Prevention is better:**
- Validators should maintain good connectivity
- Run diverse infrastructure (prevent common-mode failures)
- Monitor lineage health
- Detect divergence early

But if prevention fails, we prefer explicit domain death to silent corruption.

#### 23.9.7 Recovery Procedures (Explicit)

**After Partition:**

If validators in Partition A and Partition B later regain connectivity:

1. **Lineage Check:** Each validator compares `lineage_hash`
2. **If lineage_hash matches:** Partitions had identical execution -> can resume as one domain
3. **If lineage_hash differs:** Partitions had divergent execution -> PERMANENT SPLIT

**No Recovery Path:**

There is NO protocol mechanism to:
- Recompute lineage to match
- Override lineage verification
- "Heal" a lineage break

**Human Intervention Required:**

If rejoining is desired after lineage divergence, humans must:
1. Choose which partition's history to preserve
2. Manually migrate assets from abandoned partition
3. Establish new SDID for the merged domain
4. **This is a genesis-level event, not a recovery**

#### 23.9.8 Security Analysis

**Threat Model:**

**Attack:** Malicious validator modifies `axiom-core.elf`, executes divergent logic, then reverts to original binary hoping to rejoin.

**Defense:** Lineage hash has already diverged. Rejoin impossible without hash collision.

**Attack:** Validator attempts to fork lineage (compute alternative lineage_hash chains).

**Defense:** Only one lineage_hash is valid per state transition. Alternative chains rejected by honest validators.

**Attack:** Validator attempts to reset lineage_hash to earlier state.

**Defense:** Lineage is strictly monotonic. Earlier lineage_hash values are no longer valid.

**Security Assumption:**

SHA3-256 collision resistance. If this breaks, the entire system breaks (not specific to lineage).

#### 23.9.9 Implementation Requirements

**axiom-core.elf MUST:**
1. Maintain lineage state in persistent storage
2. Include lineage_hash in every witness signature
3. Verify lineage continuity for all received artifacts
4. Initialize lineage at genesis with documented procedure
5. Never allow lineage_hash to be manually overridden

**Validators MUST:**
1. Reject artifacts with invalid SDID (immediate FAIL-STOP)
2. Reject artifacts with core version mismatch
3. Reject artifacts with lineage break
4. Log all lineage verification failures for audit

**Clients MUST:**
1. Verify SDID in witness proofs
2. Verify core_version_id matches trusted core binary
3. Optionally verify lineage_hash for additional security


### 23.10 Core Upgrade as State Transition (Scheme A)

**Critical Design Extension:**

Section 23.9 prevents split-rejoin by tracking execution history. However, a subtle attack remains:

> What if two split networks later upgrade to the SAME axiom-core.elf version?
> Could they claim "we're running identical code now" and attempt to rejoin?

**Answer: NO.** This section closes that loophole.

#### 23.10.1 The Core Upgrade Problem

**Scenario:**

```
Original Network:  Core v1.0 -> [tx1, tx2, tx3] -> Core v1.1
Forked Network:    Core v1.0 -> [tx4, tx5, tx6] -> Core v1.1

Question: Can they rejoin because both are now running Core v1.1?
```

**Naive approach:**
- Check core_version_id: [x] Both are v1.1
- Check code fingerprint: [x] Identical binaries
- Allow rejoin? X **NO - this would allow economic chaos**

**The problem:**
- Identical code != identical worldline
- Execution history matters, not just current code
- Upgrade path is part of worldline identity

#### 23.10.2 Core Upgrade as State Transition

**Fundamental Principle:**

> A core upgrade is NOT an operational event (like "restart with new binary").
> A core upgrade IS a state transition (like executing a transaction).

**This means:**
1. Upgrades must be cryptographically authorized
2. Upgrades are recorded in lineage hash
3. Upgrades cannot be undone or forged
4. Different upgrade paths -> permanently different worldlines

#### 23.10.3 Constitution Authority

**At Genesis:**

Every AXIOM settlement domain establishes a **Constitution Public Key (CPK)** - the sole authority to authorize worldline continuation through core upgrades.

**In the AXIOM Origin deployment:**
- CPK is held by **AXIOM Origin** (the protocol designer)
- This is an explicit, initial condition
- This is NOT a permanent assumption

**What Constitution Authority CAN do:**
- Sign upgrade proofs authorizing new core versions
- Ensure worldline continuity during upgrades

**What Constitution Authority CANNOT do:**
- Control economic policy
- Freeze wallets or reverse transactions
- Create money or confiscate funds
- Force validators to upgrade
- Censor transactions
- Override atom conservation

**The Constitution key is a SERVICE (signs proofs), not POWER (controls system).**

#### 23.10.4 Upgrade Proof Structure

```rust
struct UpgradeProof {
    from_core_version_id: CoreVersionID,  // Current core (must match)
    to_core_version_id: CoreVersionID,    // New core being authorized
    sdid: SDID,                            // Settlement domain (must match)
    valid_from_height: Height,             // Activation height
    signature: SignatureData,              // Constitution signature
}

// Signature covers:
digest = SHA3-256(
    from_core_version_id ||
    to_core_version_id ||
    sdid ||
    valid_from_height
)

signature = Sign(CPK, digest)
```

#### 23.10.5 Upgrade Verification (FAIL-STOP Rules)

Upon receiving an upgrade proof, `axiom-core.elf` MUST verify:

```rust
// Rule 1: Signature validity
if !verify_signature(CPK, digest, upgrade_proof.signature) {
    FAIL_STOP("INVALID_CONSTITUTION_SIGNATURE")
}

// Rule 2: Core lineage continuity
if upgrade_proof.from_core_version_id != current_core_version_id {
    FAIL_STOP("CORE_LINEAGE_MISMATCH")
}

// Rule 3: SDID match
if upgrade_proof.sdid != local_sdid {
    FAIL_STOP("SDID_MISMATCH_IN_UPGRADE")
}

// Rule 4: Height requirement
if current_height < upgrade_proof.valid_from_height {
    FAIL_STOP("UPGRADE_NOT_YET_VALID")
}

// Rule 5: Target version match
if upgrade_proof.to_core_version_id != new_binary_fingerprint {
    FAIL_STOP("CORE_VERSION_MISMATCH")
}
```

**All checks must pass. No exceptions.**

#### 23.10.6 Lineage Evolution for Upgrades

When an upgrade is successfully applied:

```rust
// Compute upgrade digest
upgrade_digest = SHA3-256(
    from_core_version_id ||
    to_core_version_id ||
    sdid ||
    valid_from_height
)

// Evolve lineage (special state transition)
lineage_hash_next = SHA3-256(
    lineage_hash_current ||
    sdid ||
    core_version_id_OLD ||
    "CORE-UPGRADE" ||        // Domain separation marker
    upgrade_digest
)

// Update state
core_version_id = to_core_version_id
current_height += 1
```

**Key point:** The `"CORE-UPGRADE"` marker ensures upgrade lineage differs from transaction lineage, preventing confusion.

#### 23.10.7 Two Upgrade Scenarios

**Scenario 1: Authorized Upgrade (Has Valid UpgradeProof)**

```
Worldline A at height 1000:
  Core v1.0.0, SDID=A, lineage_hash=X

Constitution Authority signs upgrade:
  UpgradeProof {
    from: v1.0.0,
    to: v1.1.0,
    sdid: A,
    valid_from_height: 1000,
    signature: <valid>
  }

Validators verify and apply:
  Core v1.1.0, SDID=A, lineage_hash=Y
  
Result: Worldline continues (same SDID, evolved lineage)
```

**Scenario 2: Unauthorized Upgrade (Missing or Invalid UpgradeProof)**

```
Worldline A at height 1000:
  Core v1.0.0, SDID=A, lineage_hash=X

Someone attempts upgrade without valid proof:
  UpgradeProof missing OR signature invalid
  
axiom-core.elf response:
  FAIL_STOP("UNAUTHORIZED_CORE_UPGRADE")
  Worldline A continues with v1.0.0

If upgrade is still desired:
  Must create NEW worldline (new genesis, new SDID=B)
  This is a fork, not a continuation
```

#### 23.10.8 Why This Prevents Split-Rejoin

**Attack: Split, then upgrade to same code, attempt rejoin**

```
Original:  v1.0 -> [tx1,tx2] -> upgrade -> v1.1 -> lineage=X
Fork:      v1.0 -> [tx3,tx4] -> upgrade -> v1.1 -> lineage=Y

Even though both run v1.1:
  X != Y (different upgrade digests, different history)
  
Lineage verification:
  Fork tries to submit artifact to Original
  Original computes expected lineage: X
  Fork's artifact claims lineage: Y
  X != Y -> REJECT (LineageBreak)
```

**Identical code != identical worldline**

The upgrade path is permanently baked into lineage, making rejoin mathematically impossible.

#### 23.10.9 Absence of AXIOM Origin

**Critical Clarification:**

The disappearance, inactivity, or unavailability of AXIOM Origin does NOT render the protocol inoperable.

**If AXIOM Origin becomes unavailable:**

1. **Existing worldline:**
   - Remains mathematically valid
   - Validators continue operating
   - Transactions continue processing
   - X No more Constitution-signed upgrades possible

2. **Community options:**
   - **Conservative:** Continue without upgrades (maximum stability)
   - **Evolution:** Create new worldline (new genesis, new SDID, new CPK)
   - **Emergency:** Fork for critical bug fixes

3. **Voluntary migration:**
   - Participants MAY move to new worldline
   - This is social/economic adoption
   - NOT protocol-level merge

**Key Insight:**

> AXIOM separates:
> - Authority to continue a worldline (requires Constitution signature)
> - Freedom to create successor worldline (no permission needed)
> 
> The initial presence of AXIOM Origin enables clean continuity.
> Its absence does not prevent evolution; it only prevents silent continuity.

**This ensures:** No individual, including AXIOM Origin, can permanently block the future of the system.

#### 23.10.10 Future Upgrade Decision Process

**Who decides upgrades?**

1. **The Market** - Economic incentives guide adoption
2. **All Validators** - Technical review and consensus
3. **Users** - Vote with validator choice

**NOT decided by:**
- X AXIOM Origin alone
- X Centralized authority
- X Governance tokens

**Expected process:**

```
1. Community Discussion
   - Proposals published publicly
   - Technical review by validators
   - Economic impact analysis

2. Reference Implementation
   - Code published (open source)
   - Reproducible builds
   - Security audits

3. Constitution Signature (if AXIOM Origin available)
   - AXIOM Origin signs upgrade proof
   - This is a SERVICE, not a DECISION
   - Validators still choose to adopt or not

4. Validator Adoption
   - Each validator decides independently
   - Market forces drive adoption
   - No forced upgrades

5. Network Consensus
   - Gradual rollout
   - Monitor for issues
   - Can fork if contentious
```

**AXIOM Origin role:** Technical service provider (signs proofs)  
**Actual decision:** Market + validators + users

#### 23.10.11 Design Philosophy

**Why this complexity?**

Simple approach: "Anyone can upgrade anytime"
- Pro: Maximum flexibility
- Con: No continuity guarantee, constant fork risk

Simple approach: "No upgrades ever"
- Pro: Maximum stability
- Con: Cannot fix bugs, cannot evolve

**AXIOM's balanced approach:**

```
WITH Constitution signature:
  -> Worldline continues (clean upgrades)
  -> Same SDID, evolved lineage
  -> Community still decides adoption

WITHOUT Constitution signature:
  -> Fork required (new worldline)
  -> Different SDID, new genesis
  -> Freedom preserved
```

**Trade-offs accepted:**

- Sacrificed: Automatic upgrades without authority
- Gained: Cryptographic worldline continuity guarantee
- Preserved: Freedom to fork and evolve

**Core principle:**

> Historical integrity > Operational convenience
> Worldline identity > Code equality  
> Community freedom > Individual authority

#### 23.10.12 Security Properties

**Property 1: Upgrade Authorization is Cryptographic**

```
Validators do NOT vote on upgrades
Validators ONLY execute axiom-core.elf
axiom-core.elf ONLY accepts Constitution-signed upgrades

Authority = CPK (mathematics)
NOT = Validator majority (governance)
```

**Property 2: Malicious Upgrades Fail**

```
AXIOM Origin signs malicious upgrade:
  -> Validators review code
  -> See violation (e.g., prints money)
  -> REJECT upgrade
  -> Continue on old worldline
  -> Possibly fork with different CPK

Attack fails.
```

**Property 3: Refused Upgrades Don't Block Evolution**

```
Community wants upgrade X
AXIOM Origin refuses to sign (disappeared? disagrees?)

Community response:
  -> Fork to new worldline
  -> New SDID, new CPK
  -> Voluntary migration
  -> Old worldline continues

Evolution continues.
```

**Property 4: Split-Rejoin Remains Impossible**

```
Even with:
  - Same core binary
  - Same SDID attempt
  - Valid Constitution signature

Different history -> different lineage -> permanent split

Mathematics enforces this, not policy.
```

#### 23.10.13 Implementation Requirements

**axiom-core.elf MUST:**
1. Store Constitution Public Key at genesis (immutable)
2. Verify UpgradeProof signature before accepting upgrades
3. Enforce all 5 verification rules (fail-stop on any failure)
4. Evolve lineage_hash to include upgrade digest
5. Update core_version_id after successful upgrade
6. Increment height for upgrade (upgrade is a state transition)
7. Never allow manual override of upgrade verification

**Validators MUST:**
1. Store Constitution Public Key from genesis
2. Reject upgrade proofs with invalid signatures
3. Review upgrade code before adopting
4. Choose independently whether to adopt upgrade
5. Not force other validators to upgrade

**AXIOM Origin SHOULD:**
1. Sign upgrade proofs only after community consensus
2. Publish upgrade proofs publicly
3. Enable reproducible builds
4. Facilitate security audits
5. Consider succession planning (multi-sig, community CPK)


### 23.11 Receipt Lineage Binding (Cross-Worldline Recovery Prevention)

**Critical Security Extension:**

Section 23.9 establishes lineage tracking for transaction validation. Section 23.10 extends this to core upgrades. However, a critical attack vector remained:

> What if a user obtains receipts in Lineage B (a corrupted fork), then attempts to use those receipts for state recovery in Lineage A (the legitimate worldline)?

This section closes that vulnerability.

#### 23.11.1 The Recovery Attack

**Scenario:**

```
T0: Worldlines A and B share common history
    Alice has 1000 AXC in both

T1: Split occurs
    
T2: Lineage B is corrupted (infinite money, broken rules)
    Alice exploits B, accumulates 999,999 AXC
    Alice obtains receipts proving her balance in B

T3: Lineage B collapses (all validators go offline)

T4: Alice approaches Lineage A validators
    "My validators died, here are my receipts, please recover my 999,999 AXC"

Question: Can Lineage A validators detect this attack?
```

**Without lineage binding in receipts:** Attack succeeds - receipts look valid.

**With lineage binding in receipts:** Attack fails - receipts reveal wrong worldline.

#### 23.11.2 Receipt Structure with Lineage Binding

**Previous structure (VULNERABLE):**

```rust
struct Receipt {
    txid: TxId,
    witness_pk: PublicKey,
    signature: SignatureData,
    // No worldline identification!
}
```

**Updated structure (SECURE):**

```rust
struct Receipt {
    txid: TxId,
    witness_pk: PublicKey,
    signature: SignatureData,
    
    // Lineage binding - identifies source worldline
    sdid: SDID,                    // Settlement Domain ID
    lineage_hash: LineageHash,     // Lineage at receipt creation
    core_version_id: CoreVersionID, // Core version that created receipt
}
```

#### 23.11.3 Receipt Validation Rules

When validating a transaction with `prev_receipts`, validators MUST verify:

```rust
FUNCTION validate_receipt_lineage(receipt: Receipt) -> Result<(), ValidationError>:
    local_lineage = get_current_lineage_state()
    
    // Rule 1: SDID must match
    IF receipt.sdid != local_lineage.sdid THEN
        RETURN Err(ValidationError::ReceiptFromWrongWorldline {
            expected: local_lineage.sdid,
            actual: receipt.sdid,
        })
    END
    
    // Rule 2: Lineage hash must be from our history
    // The receipt's lineage_hash must be an ancestor of current lineage
    IF NOT is_lineage_ancestor(receipt.lineage_hash, local_lineage) THEN
        RETURN Err(ValidationError::ReceiptLineageNotAncestor)
    END
    
    // Rule 3: Core version must be from our upgrade path
    IF NOT is_valid_core_version(receipt.core_version_id) THEN
        RETURN Err(ValidationError::ReceiptFromUnknownCoreVersion)
    END
    
    RETURN Ok(())
END
```

#### 23.11.4 Attack Prevention Analysis

**Attack attempt:**

```
Alice presents receipt from Lineage B:
  Receipt {
    txid: 0x9999,
    witness_pk: ValidatorB_pubkey,
    signature: valid_signature,
    sdid: 0xBBBB,           // Lineage B's SDID
    lineage_hash: 0xLLLL,   // Lineage B's hash
    core_version_id: 0xVVVV,
  }

Lineage A validator checks:
  local_sdid: 0xAAAA
  receipt_sdid: 0xBBBB
  
  0xAAAA != 0xBBBB -> REJECT: ReceiptFromWrongWorldline
```

**Attack fails because receipt is cryptographically bound to its origin worldline.**

#### 23.11.5 Edge Cases

**Case 1: Receipt from before split (same SDID)**

```
Receipt created at T0 (before split):
  sdid: 0xAAAA (same as current)
  lineage_hash: 0x1111 (ancestor of both A and B)

Validation:
  - SDID matches [x]
  - lineage_hash is ancestor of current [x]
  - Receipt is valid [x]

This is correct behavior - pre-split receipts are valid in both worldlines.
```

**Case 2: Receipt from after split (same SDID, different lineage)**

```
Both worldlines started with same SDID but diverged:

Lineage A: sdid=0xAAAA, lineage_hash=0xAAA1
Lineage B: sdid=0xAAAA, lineage_hash=0xBBB1

Receipt from B after split:
  sdid: 0xAAAA (matches!)
  lineage_hash: 0xBBB1 (not ancestor of A)

Validation in Lineage A:
  - SDID matches [x]
  - lineage_hash is NOT ancestor of 0xAAA1 [ ]
  - REJECT: ReceiptLineageNotAncestor
```

**Case 3: Receipt from upgraded core**

```
Lineage A upgraded from v1.0 to v1.1:
  core_version_history: [v1.0, v1.1]

Receipt from v1.0:
  core_version_id: v1.0

Validation:
  - v1.0 is in our upgrade path [x]
  - Receipt is valid [x]

Receipt from unknown v2.0 (never in our history):
  core_version_id: v2.0

Validation:
  - v2.0 is NOT in our upgrade path [ ]
  - REJECT: ReceiptFromUnknownCoreVersion
```

#### 23.11.6 Wallet Implications

**Wallets do NOT store lineage information.**

Wallets only contain:
- Private key
- Public key

**Receipts are issued by Validators, not wallets.**

When a validator issues a receipt:
1. Validator includes current SDID
2. Validator includes current lineage_hash
3. Validator includes current core_version_id
4. Validator signs the complete receipt

**Users cannot forge receipts because:**
- They don't have validator private keys
- Lineage information is embedded and signed
- Any modification invalidates the signature

#### 23.11.7 Complete Lineage Binding Summary

All critical structures now include lineage binding:

| Structure | SDID | lineage_hash | core_version_id | Purpose |
|-----------|------|--------------|-----------------|---------|
| **LineageState** | [x] | [x] | [x] | Validator's worldline state |
| **WitnessSig** | [x] | [x] | [x] | Transaction witness binding |
| **Receipt** | [x] | [x] | [x] | Recovery proof binding |
| **UpgradeProof** | [x] | - | [x] (from/to) | Upgrade authorization |

**Security guarantee:**

> No artifact from one worldline can be accepted in another worldline.
> This is enforced cryptographically, not by policy.

#### 23.11.8 Implementation Requirements

**Validators MUST:**
1. Include SDID, lineage_hash, and core_version_id in all issued receipts
2. Verify receipt lineage before accepting for recovery
3. Reject receipts with non-matching SDID
4. Reject receipts with non-ancestor lineage_hash
5. Maintain history of valid core versions for verification

**Clients SHOULD:**
1. Verify receipt SDID matches expected worldline
2. Display worldline information to users
3. Warn users if connected to unexpected SDID

**Wallets MUST NOT:**
1. Store lineage information (not their responsibility)
2. Attempt to forge or modify receipts
3. Accept receipts without validator signatures


### 23.12 Responsibility Separation (Trust Anchor Model)

**Critical Design Principle:**

AXIOM separates verification responsibilities across layers. This ensures each component has a clear, minimal role.

#### 23.12.1 The Problem: Validator Mismatch

```
Scenario: User collects witnesses from validators running different cores

Validator A: Core v1.1, lineage_hash = 0xAAAA (correct)
Validator B: Core v1.1, lineage_hash = 0xAAAA (correct)
Validator C: Core v1.0, lineage_hash = 0xCCCC (wrong - didn't upgrade)

User collects WitnessSig from A, B, C:
  - A and B: correct lineage
  - C: wrong lineage (old core, or wrong worldline)

Result: Transaction rejected by other validators (lineage mismatch)
```

**Question:** Who MUST detect this problem BEFORE collecting witnesses?

**Answer:** The App/Wallet, NOT axiom-core.elf.

#### 23.12.2 Responsibility Matrix

| Component | Responsibilities | NOT Responsible For |
|-----------|-----------------|---------------------|
| **axiom-core.elf** | Validate transactions, maintain lineage, evolve state | Verifying validator identity, P2P communication, upgrade decisions |
| **App/Wallet** | Verify validator fingerprint/SDID before collecting witnesses, display worldline info to user | Storing lineage, transaction validation logic |
| **Validator (external)** | Persist lineage state, handle upgrades, P2P communication | Transaction validation (delegated to axiom-core.elf) |

#### 23.12.3 Trust Anchors

**Apps/Wallets MUST have built-in knowledge of:**

```rust
struct TrustAnchors {
    /// Known correct SDID for main AXIOM network
    canonical_sdid: SDID,
    
    /// Known correct axiom-core.elf fingerprint (current version)
    canonical_core_fingerprint: CoreVersionID,
    
    /// Constitution public key (for verifying upgrade announcements)
    constitution_pubkey: ConstitutionPubKey,
    
    /// Genesis Validator public keys (for VBC verification - reality anchor)
    /// These are the roots of trust for validator legitimacy
    genesis_validators: [PublicKey; 3],
}
```

**These trust anchors are:**
- Hardcoded at app release
- Updated via app updates (after core upgrades)
- Verifiable from official sources

**Note:** Genesis validators define where the universe STARTED, not who controls it. They do not need to remain online.

#### 23.12.4 Witness Collection Flow

**BEFORE collecting WitnessSig, App/Wallet MUST:**

```
1. Connect to Validator
2. Query Validator's reported:
   - core_fingerprint
   - sdid
3. Compare against local trust anchors:
   - IF fingerprint != canonical_fingerprint -> REJECT, try another validator
   - IF sdid != canonical_sdid -> REJECT, try another validator
4. Only then: Request WitnessSig
```

**This prevents:**
- Collecting witnesses from validators on wrong worldline
- Collecting witnesses from validators running outdated core
- User confusion about transaction failures

#### 23.12.5 Why NOT in axiom-core.elf?

**Argument:** "axiom-core.elf should verify validator fingerprints"

**Counter-argument:**

```
axiom-core.elf receives: WitnessSig[] already collected

At this point:
  - Transaction is already assembled
  - Witnesses already signed
  - If fingerprint wrong, transaction fails
  - User already wasted time/resources

Prevention is better than rejection.
App MUST prevent collecting bad witnesses in the first place by verifying validator fingerprints before witness collection.
```

**Additionally:**
- axiom-core.elf doesn't do P2P communication
- axiom-core.elf doesn't choose validators
- axiom-core.elf only validates what it receives

#### 23.12.6 Upgrade Responsibility

**Core upgrades are NOT handled inside axiom-core.elf.**

**Rationale:**
```
axiom-core.elf is immutable.
Upgrading axiom-core.elf = replacing the binary.
The old binary cannot "approve" its replacement.
The new binary cannot verify "it was legitimately installed".

Therefore:
- UpgradeProof verification happens OUTSIDE axiom-core.elf
- Validator external tooling verifies UpgradeProof
- Validator updates persisted lineage state
- New axiom-core.elf loads updated lineage on startup
```

**Upgrade flow:**

```
1. AXIOM Origin publishes UpgradeProof (signed)
2. Community verifies signature (anyone can do this)
3. Validator decides to upgrade:
   a. Stops old axiom-core.elf
   b. External tool verifies UpgradeProof
   c. External tool updates persisted lineage (evolves with upgrade)
   d. Starts new axiom-core.elf
4. New axiom-core.elf loads lineage from persistence
5. Continues operation
```

#### 23.12.7 App Update Flow

**When axiom-core.elf is upgraded, apps need updated trust anchors:**

```
1. AXIOM Origin publishes:
   - New axiom-core.elf
   - New fingerprint
   - UpgradeProof

2. App developers:
   - Update trust anchors in app
   - Release app update

3. Users:
   - Update app
   - App now recognizes new fingerprint as valid

4. Transition period:
   - Old app: only trusts old fingerprint
   - New app: trusts new fingerprint
   - Validators running new core: serve users with new app
   - Validators running old core: serve users with old app (until they upgrade)
```

#### 23.12.8 Implementation Requirements

**axiom-core.elf MUST:**
1. Initialize lineage from persisted state (or genesis)
2. Validate transactions using current lineage
3. Evolve lineage after successful transactions
4. NOT implement P2P communication
5. NOT implement upgrade logic internally

**Apps/Wallets MUST:**
1. Hardcode canonical SDID and fingerprint
2. Verify validator fingerprint before collecting witnesses
3. Warn users if validator SDID doesn't match
4. Update trust anchors when core is upgraded

**Validators MUST:**
1. Persist lineage state externally
2. Handle upgrades via external tooling
3. Ensure axiom-core.elf loads correct lineage on startup
4. Report correct fingerprint/SDID to connecting clients


### 23.13 Validator Birth Certificate (VBC) - Reality Anchor

**Cross-Reference:** See AXIOM_DESIGN_VBC_v1_0.md for complete specification.

#### 23.13.1 The Problem: Mirror Universe Attack

AXIOM's non-linear architecture creates a vulnerability: an attacker can construct a parallel "mirror universe" with fake validators running identical axiom-core.elf, producing internally-valid settlement proofs.

Without a cryptographic anchor to reality, fresh receivers cannot distinguish:
- REAL settlement witnesses rooted in the Genesis Mesh
- FAKE settlement witnesses rooted in an attacker-controlled mesh

Existing defenses (SDID, Lineage) protect established receivers but fail for fresh receivers with no lineage history.

#### 23.13.2 Solution: Validator Birth Certificate

A **Validator Birth Certificate (VBC)** is a portable, offline-verifiable proof that a validator belongs to the real AXIOM network rooted in the Genesis Validators.

**VBC Properties:**
- **Portable:** Validator carries proof, not queried
- **Offline:** Verifiable without network access
- **Recursive:** Each issuer must itself be verifiable
- **Rooted:** All chains terminate at hardcoded Genesis keys
- **Bounded:** Proof size is limited via renewal mechanism

#### 23.13.3 Genesis Reality Anchor

Core embeds a fixed set of 10 Genesis Validator SPHINCS+ public keys:

```rust
// 10 Genesis Validators — SPHINCS+ (SLH-DSA-SHA2-128s) public keys
// Named alpha through kappa (lambda is reserved for the consensus service)
pub const GENESIS_VALIDATORS: [[u8; 32]; 10] = [
    ALPHA_SPHINCS_PK,   // genesis validator alpha
    BETA_SPHINCS_PK,    // genesis validator beta
    GAMMA_SPHINCS_PK,   // genesis validator gamma
    DELTA_SPHINCS_PK,   // genesis validator delta
    EPSILON_SPHINCS_PK, // genesis validator epsilon
    ZETA_SPHINCS_PK,    // genesis validator zeta
    ETA_SPHINCS_PK,     // genesis validator eta
    THETA_SPHINCS_PK,   // genesis validator theta
    IOTA_SPHINCS_PK,    // genesis validator iota
    KAPPA_SPHINCS_PK,   // genesis validator kappa
];
```

Genesis validators are identified by their SPHINCS+ public key (32 bytes). Core recognises a validator as Genesis by direct PK match — no VBC chain walking needed.

Genesis validators:
- Do NOT retain special power after genesis
- Do NOT need to stay online
- Do NOT have VBCs (they ARE the roots)
- Their signatures persist as immutable historical facts

#### 23.13.4 VBC Structure

```rust
struct VBC {
    subject_validator_id: ValidatorID,
    subject_pubkey_sphincs: [u8; 32],     // SPHINCS+ PK (primary identity)
    subject_pubkey_dilithium: Vec<u8>,    // Dilithium PK (backup identity, 1,952 bytes)
    issued_at: Timestamp,
    expires_at: Timestamp,
    issuer_sphincs_pks: [[u8; 32]; 3],   // Exactly 3 issuers (SPHINCS+ PKs)
    signatures: [Vec<u8>; 3],            // 3 SPHINCS+ signatures (7,856 bytes each)
}

struct VBCProofBundle {
    target_vbc: VBC,
    supporting_vbcs: Vec<VBC>,
}
```

**Dual Identity:** The VBC contains two post-quantum public keys built on independent mathematical foundations:

| Key | Algorithm | Foundation | Role |
|-----|-----------|------------|------|
| `subject_pubkey_sphincs` | SLH-DSA-SHA2-128s (FIPS 205) | Hash functions | Primary identity, used for VBC signing |
| `subject_pubkey_dilithium` | ML-DSA-65 (FIPS 204) | Lattice problems | Backup identity, authenticated by issuers' signatures |

**VBC signatures are SPHINCS+ only.** The 3 issuer signatures are always SPHINCS+. The Dilithium PK is passive data — it rides inside the VBC and is covered by the issuers' SPHINCS+ signatures, proving it belongs to this validator without any separate binding mechanism.

**Ed25519 is NOT in the VBC.** Ed25519 is not post-quantum and is used only for ephemeral operational signing. Operational keys live in the validator's local config and can be rotated independently without VBC reissuance.

**Signature Coverage (MUST):** A VBC signature MUST cover both public keys, the validator identity, and the timestamps. Detached or reused signatures are invalid.

**Signing Payload:**
```
payload = BLAKE3("AXIOM_VBC_V1" || subject_validator_id || subject_pubkey_sphincs || subject_pubkey_dilithium || issued_at || expires_at || issuer_sphincs_pks)
```

#### 23.13.4a VBC Signing Payload (Normative)

The canonical signing payload uses domain tag `AXIOM_VBC_V09`. Implementers MUST construct the pre-image in this exact field order:

```
BLAKE3(
    b"AXIOM_VBC_V09"           // domain tag (13 bytes)
    || version                  // u8
    || validator_id             // 32 bytes
    || subject_pubkey_sphincs   // 32 bytes
    || subject_pubkey_dilithium // variable (ML-DSA-65)
    || subject_pubkey_ed25519   // 32 bytes (bound to attestation.nabla_node_pk)
    || pgp_fingerprint          // 20 bytes
    || node_name                // UTF-8 bytes (variable)
    || proof_cap                // UTF-8 bytes (variable)
    || issued_at                // u64 LE
    || expires_at               // u64 LE
    || chain_depth              // u8
    || max_tx                   // u64 LE
    || issuer_set...            // 32 bytes per issuer PK, concatenated
)
```

All fields are covered by the signature -- nothing can be tampered with. The simplified `AXIOM_VBC_V1` payload above is the White Paper-era format; `AXIOM_VBC_V09` is the implemented wire format. Reference: `core/logic/src/crypto.rs::compute_vbc_signing_payload_bytes()`.

#### 23.13.4.1 VBC Cryptographic Architecture: Why Dual Identity

**Problem:** If SPHINCS+ is ever broken (a practical attack on SHA-2 hash functions), every VBC in the network becomes unverifiable. The entire trust chain from Genesis collapses. The network dies.

**Solution:** The VBC stores a second post-quantum identity (Dilithium) that is mathematically independent of SPHINCS+:

- **SPHINCS+** relies on hash function collision resistance (SHA-2)
- **Dilithium** relies on Module-LWE lattice hardness

These are fundamentally different mathematical assumptions. A breakthrough in hash functions does not affect lattice problems, and vice versa. Both being broken simultaneously is astronomically unlikely.

**Migration Path if SPHINCS+ Breaks:**

1. Discovery: practical attack on SPHINCS+ announced
2. Validators still have authenticated Dilithium PKs (covered by the now-compromised SPHINCS+ signatures, but issued before the attack)
3. Protocol update: VBC signing switches to Dilithium
4. New VBCs issued with Dilithium signatures, referencing the Dilithium PKs already in existing VBCs
5. Network survives without requiring new Genesis ceremony

**Migration Path if Dilithium Breaks:**

1. Nothing changes — Dilithium is backup only
2. VBC signing continues with SPHINCS+ as before
3. Future VBCs may replace Dilithium PK with a new backup algorithm

**Why not Ed25519 as backup?**

Ed25519 is not post-quantum. It would be the first to break, making it useless as a backup for a survival-grade system designed to last 100 years.

#### 23.13.5 Verification Algorithm

```python
def verify_vbc(vbc, bundle, current_time, visited=set()):
    # Cycle detection
    if vbc.subject_pubkey in visited:
        return REJECT("E_REALITY_CYCLE_DETECTED")
    visited.add(vbc.subject_pubkey)
    
    # Expiry check (MUST reject expired VBCs)
    if current_time >= vbc.expires_at:
        return REJECT("E_REALITY_VBC_EXPIRED")
    
    # Signature verification
    for issuer_pk, sig in zip(vbc.issuer_set, vbc.signatures):
        if not crypto_verify(issuer_pk, vbc.signing_payload, sig):
            return REJECT("E_REALITY_INVALID_SIGNATURE")
    
    # Recursive ancestry
    for issuer_pk in vbc.issuer_set:
        if issuer_pk in GENESIS_VALIDATORS:
            continue  # Root reached
        issuer_vbc = bundle.find_by_pubkey(issuer_pk)
        if not issuer_vbc:
            return REJECT("E_REALITY_MISSING_ANCESTRY_PROOF")
        if verify_vbc(issuer_vbc, bundle, current_time, visited) != ACCEPT:
            return REJECT
    
    return ACCEPT
```

#### 23.13.5.1 Issuer Maturity Requirement (MIN_ISSUER_AGE)

**Problem: Rapid Validator Expansion Attack**

Without restrictions on VBC issuance, an attacker who compromises 3 validators can immediately create unlimited rogue validators:

```
Day 0: Attacker compromises V1, V2, V3
Day 0: V1, V2, V3 issue VBC for Rogue_A, Rogue_B, Rogue_C
Day 0: Rogue_A, B, C issue VBC for Rogue_D, Rogue_E, Rogue_F
Day 0: ... infinite rogue validators instantly created
```

This allows an attacker to rapidly create a shadow network of validators.

**Solution: Minimum Issuer Age**

A validator MUST NOT issue new VBCs until their own VBC has aged at least **MIN_ISSUER_AGE_SECONDS**.

```
MIN_ISSUER_AGE_SECONDS = 7 days (604,800 seconds)
```

**Protocol Constant (hardcoded in Core):**

```rust
/// Minimum age of issuer VBC before they can issue new VBCs
/// See Yellow Paper Section 23.13.5.1
pub const MIN_ISSUER_AGE_SECONDS: u64 = 7 * 24 * 60 * 60;  // 7 days
```

**Verification Algorithm:**

```python
def verify_issuer_qualified(issuer_vbc, bundle, current_time):
    # Genesis validators are always qualified (no VBC age to check)
    if issuer_vbc.subject_pubkey in GENESIS_VALIDATORS:
        return ACCEPT
    
    # Verify issuer's VBC is valid
    if verify_vbc(issuer_vbc, bundle, current_time) != ACCEPT:
        return REJECT("E_REALITY_INVALID_ISSUER_VBC")
    
    # Verify issuer's VBC is old enough
    issuer_age = current_time - issuer_vbc.issued_at
    if issuer_age < MIN_ISSUER_AGE_SECONDS:
        return REJECT("E_REALITY_ISSUER_TOO_YOUNG")
    
    return ACCEPT

def verify_vbc_issuance(new_vbc, issuer_vbcs, issuer_bundles, current_time):
    # All 3 issuers must be qualified
    for i, issuer_pk in enumerate(new_vbc.issuer_set):
        if issuer_pk in GENESIS_VALIDATORS:
            continue  # Genesis always qualified
        
        result = verify_issuer_qualified(
            issuer_vbcs[i], 
            issuer_bundles[i], 
            current_time
        )
        if result != ACCEPT:
            return result
    
    return ACCEPT
```

**Attack Mitigation Timeline:**

```
Day 0:  Attacker compromises V1, V2, V3 (all with aged VBCs)
Day 0:  V1, V2, V3 → Rogue_A, Rogue_B, Rogue_C (VBCs issued, age = 0)
Day 0:  Rogue_A, B, C try to issue → BLOCKED (age < 7 days)

Day 7:  Rogue_A, B, C VBCs now aged 7 days
Day 7:  Rogue_A, B, C → Rogue_D, Rogue_E, Rogue_F (age = 0)
Day 7:  Rogue_D, E, F try to issue → BLOCKED

Day 14: Rogue_D, E, F VBCs now aged 7 days
Day 14: Rogue_D, E, F → Rogue_G, Rogue_H, Rogue_I
...

Expansion rate: ~3 new rogue validators per 7-day period
Without this rule: Infinite rogue validators instantly
```

**Why 7 Days?**

| Consideration | Analysis |
|---------------|----------|
| Detection window | 7 days allows time to detect compromised validators |
| User experience | Not too long for legitimate validator onboarding |
| Attack rate limiting | Reduces attack speed by ~1000x vs instant issuance |
| Protocol simplicity | Single constant, easy to verify |

**Why This Is Cryptographically Verifiable:**

1. `issued_at` is signed in the VBC (cannot be forged)
2. `current_time` is injected by DMAP-VM (deterministic)
3. `age >= MIN_ISSUER_AGE` is pure math (no external dependency)

No network access. No trusted third party. No human intervention.

**Error Code:**

| Code | Description |
|------|-------------|
| `E_REALITY_ISSUER_TOO_YOUNG` | Issuer's VBC is younger than MIN_ISSUER_AGE_SECONDS |

**Implementation Requirements:**

| Component | Requirement |
|-----------|-------------|
| **Core** | Enforce MIN_ISSUER_AGE when processing VBC issuance |
| **Lambda** | Check issuer maturity before signing new VBCs |
| **Gateway** | No change (transparent transport) |

#### 23.13.6 VBC Size Control

Core MUST enforce boundedness:
- MAX_VBC_BUNDLE_BYTES: 32 KiB
- MAX_VBC_DEPTH: 8
- MAX_VBC_OBJECTS: 32

VBC renewal re-anchors validators to current REAL validators, keeping proof depth bounded.

#### 23.13.7 VBC Issuance and Renewal

**Initial VBC Creation:**
- Requires 500 AXC stake (protocol minimum)
- Requires 3 AXC fee (1 AXC to each of 3 issuers) - ONE-TIME ONLY
- Requires signatures from 3 validators with valid VBCs

**VBC Renewal:**
- Requires 3 issuer signatures (may use different issuers)
- NO FEE for renewals
- MUST be initiated at least 48 hours before expiration to allow for issuer availability and propagation delay.
- Recommended validity: 30 days (early network), 90 days (mature)

**NBC TX Budget (Nabla Birth Certificates):**
- Each NBC carries a `max_tx` field (default 50,000) covered by issuer SPHINCS+ signatures
- Implementation: `NBC_TX_BUDGET = 50_000` in `nabla/src/constants.rs`. Production NBC issuance (`cc.rs`) sets `max_tx: NBC_TX_BUDGET`.
- Nodes track registrations processed per NBC (`registration_count`). When `registration_count >= max_tx`, further registrations are rejected with `"nbc_budget_exhausted"` and client is redirected to peers with remaining budget.
- Two independent renewal triggers: time-based (7 days before expiry) OR TX-based (`NBC_TX_RENEWAL_WINDOW = 5,000` registrations before budget). On renewal, counter resets (new NBC = new budget).
- `max_tx = 0` means unlimited (backward compat with pre-budget NBCs). Core test code uses 0; production Nabla uses 50,000.
- Renewal check interval: 720 ticks (~1 hour)
- At max throughput (720 reg/hr), budget exhausts in ~3 days → automatic renewal

#### 23.13.8 No Revocation

VBCs cannot be revoked. The only termination is expiration.

**Rationale:**
- Revocation requires authority (violates sovereignty)
- Revocation requires state propagation (violates offline verification)
- Expiration is deterministic and authority-free

#### 23.13.9 Component Responsibilities

| Component | VBC Responsibility |
|-----------|-------------------|
| **Core** | Verify VBC chains, hardcode GENESIS_VALIDATORS |
| **Lambda** | Cache VBCs, assemble bundles, archive history |
| **Gateway** | Transport VBCs (V2VVBCRequest/Response/Gossip) |

#### 23.13.10 Security Guarantee

A validator is accepted as REAL if and only if its VBC chain terminates at the Genesis Validator keys hardcoded in Core.

**REALITY IS NOT VOTED. REALITY IS A CONNECTED MESH.**

#### 23.13.11 Historical Receipt Verification

VBC expiration does NOT invalidate historical receipts.

When verifying historical receipts:
1. Locate VBC that was valid when witness signature was made
2. Verify VBC chain traces to Origin
3. Historical VBCs are archived by Lambda indefinitely

**Principle:** "When witnessed, it's witnessed."

#### 23.13.12 Component Responsibilities

| Component | VBC Responsibility |
|-----------|-------------------|
| **Core** | Verify VBC chains, hardcode AXIOM_ORIGIN_PUBKEY |
| **Lambda** | Cache VBCs, assemble bundles, archive history |
| **Gateway** | Transport VBCs (V2VVBCRequest/Response/Gossip) |

#### 23.13.13 Security Guarantee

```
AXIOM GUARANTEES:

A validator is accepted as REAL if and only if its VBC chain
terminates at the AXIOM Origin Validator key hardcoded in Core.

An attacker cannot forge this chain without breaking Ed25519/Dilithium.
```

**REALITY IS NOT VOTED. REALITY IS A CONNECTED MESH.**

#### 23.13.14 Process Lifetime TTL (VBC Re-verification Enforcement)

**Purpose:** Guarantee periodic VBC re-verification by enforcing axiom-core.elf process termination.

**Problem:** In persistent mode, axiom-core.elf verifies VBC bundles on startup. Without a lifetime limit, a long-running instance could operate indefinitely with stale or expired VBC data.

**Solution:** axiom-core.elf MUST self-terminate after bounded lifetime, forcing Gateway to spawn a fresh instance that re-verifies VBCs.

**TTL Limits (Persistent Mode Only):**

| Parameter | Value | Trigger |
|-----------|-------|---------|
| Max lifetime | 24 hours | Time since spawn |
| Max transactions | 2,000 | Transaction count |

Whichever limit is reached first triggers termination.

**Enforcement Rules:**

1. **axiom-core.elf manages its own TTL** - not Gateway or Lambda
2. **Check TTL before each request** - never mid-transaction
3. **Complete current request** before terminating
4. **Exit cleanly (status 0)** - Gateway detects EOF, spawns fresh instance
5. **Fresh instance re-verifies VBCs** - cannot skip verification

**AUDIT-FIX v2.11.14 — Verification Scope Clarification:**

Structure-only VBC checks (`verify_vbc_bundle_structure_only`) are now reserved for **self-owned VBCs** where the validator has already performed full verification:
- Core instantiation (`core_handle.rs`) — validator's own VBC at spawn time
- ANTIE config loading — gateway startup warning check

For **untrusted prev_receipts** (client-supplied data), full SPHINCS+ verification (`verify_vbc_bundle_no_time`) is MANDATORY. Structure-only checks are insufficient because they skip cryptographic signatures, allowing forged VBC bundles that structurally mimic root authority chains.

**Request Types That Count Toward TTL:**

| Request Type | Counts? | Reason |
|--------------|---------|--------|
| `tx.validate` | YES | Uses VBC verification |
| `sabr.phase1.validate` | YES | Uses VBC verification |
| `sabr.phase2.validate` | YES | Uses VBC verification |
| `echo.test` | NO | Utility, no VBC |
| `hcp.verify` | NO | Utility, no VBC |

**Security Guarantee:**

```
VBC verification occurs AT MINIMUM:
- Every 24 hours of operation
- Every 2,000 transactions per axiom-core.elf instance

Stale VBCs cannot persist beyond these bounds.
Expired VBCs are detected on next axiom-core.elf restart.

Note: Validators MAY run multiple axiom-core.elf instances in parallel
for throughput. Each instance has its own independent TTL.
A validator with 4 parallel cores processes 8,000 TX before
full rotation, while maintaining per-instance security bounds.
```

**Single-Request Mode:** TTL does not apply. Each request spawns fresh axiom-core.elf which naturally terminates after response.

**Implementation Reference:** See AXIOM_GUIDE_Core Section 5.10.12

#### 23.13.15 VBC Chain Verification Fail-Stop Semantics

**Invariant:** VBC chain verification failure at startup is **terminal and irrecoverable**.

When Lambda verifies its own VBC chain against the Genesis root keys at startup and
verification fails, the only correct action is `process::exit(1)`. There is no
recovery path, no retry, no fallback, and no degraded mode.

**Why There Is No Recovery:**

A VBC chain verification failure means one of:
1. The VBC file is corrupted or tampered with
2. The VBC was issued by a key not rooted in Genesis
3. The VBC signatures are invalid (broken chain)
4. The VBC has expired and no renewal was performed

All four indicate that **this validator cannot prove it belongs to the real AXIOM network**.
Operating without valid proof of identity would violate the Reality Anchor invariant (§23.13.9).

**Required Behavior:**

| Condition | Action | Rationale |
|-----------|--------|-----------|
| VBC chain invalid | `process::exit(1)` | Cannot prove identity |
| VBC file missing | `process::exit(1)` | Cannot prove identity |
| VBC expired | `process::exit(1)` | Stale identity |
| Root key mismatch | `process::exit(1)` | Wrong network |

**Operator Recovery (External to Protocol):**

The protocol defines no recovery mechanism. The operator must:
1. Diagnose the cause (corrupted file, expired VBC, wrong binary)
2. Obtain a valid VBC (re-issue from a qualified issuer, or re-run ceremony for genesis validators)
3. Rebuild the VBC chain from the beginning
4. Restart the validator

**This is by design.** A validator that cannot cryptographically prove its lineage to Genesis
has no authority to witness transactions. Allowing it to operate in any capacity — even
read-only or degraded — would create an exploitable gap in the Reality Anchor.

> **"When it crashes, it crashes. Rebuild the chain from the beginning. There is no recovery."**


### 23.14 Peer Audit Demand (The Ping Defense)

**Problem:** Core is stateless — it cannot force a validator operator to initiate an audit of
a peer validator. Since Lambda and ANTIE are under operator control, a dishonest operator could
simply never audit peers, allowing collusion to go undetected.

**Solution:** Core randomly demands Lambda initiate a peer audit. If Lambda does not comply within
a countdown window, the DMAP-VM terminates Core. Restarting Core incurs a startup penalty (VBC chain
re-verification, ZK performance benchmark), making non-compliance operationally expensive.

#### 23.14.1 Trigger Mechanism

On every transaction processed in CL2 or CL3 mode that produces `ValidationResult::Accept`:

1. Core computes: `trigger = u64_le(txid[0..8]) mod AUDIT_TRIGGER_RATE`
2. If `trigger == 0` (~1 in 100 transactions), Core generates an `AuditDemand`
3. The demand is included in `PublicOutputs.audit_demand`

**Constants.** These are **dev/testnet placeholders**; production values are held until Silicon
Pulse is switched on at multi-host (KI#31). All of these belong in the compile-time tuning register
`core/logic/protocol.toml` (they are Core constants, so a change rotates the CoreID) — carry both a
dev value and a `# production: …` comment, per the convention in `docs/AXIOM_REF_TuningRegisters.md`.
They are still hard-coded in `core/logic/src/types.rs` today; migrating them is a post-soak task.

- `AUDIT_TRIGGER_RATE = 100` — average 1 audit demand per 100 transactions (dev)
- `AUDIT_COUNTDOWN_TXS = 10` — self-audit: Lambda has 10 transactions to comply (dev)
- `PEER_AUDIT_COUNTDOWN_TXS = 100` — peer-audit: 100 transactions (email round-trip budget) (dev)
- `PEER_AUDIT_BAN_TICKS = 17280` — ban duration ≈ 24 h as a TICK count (17280 × `TICK_INTERVAL_SECS`);
  compared against the `last_validated_tick` watermark, **never wall-clock** (§23.14.6a)
- `PEER_AUDIT_TIMEOUT_TICKS` — response deadline as a **tick count** against `last_validated_tick`,
  not wall-clock. (Migration item: the current `PEER_AUDIT_TIMEOUT_SECS = 600` is a wall-clock gate
  and violates the tick-only invariant — `[[feedback_no_wallclock_only_core_time]]` — same fix as the
  Silicon-Pulse `should_trigger` TIME arm; see `AXIOM_REF_TuningRegisters.md`. Dev ≈ 120 ticks.)
- `PEER_AUDIT_CRASH_DELAY_TICKS` — remote crash delay (time for ANTIE to send response); tick-based
  for the same reason (was `PEER_AUDIT_CRASH_DELAY_SECS = 180`). Dev ≈ 36 ticks.

**Tick discipline (invariant).** Every recurring peer-audit deadline/expiry is a **tick count
compared against the monotonic `last_validated_tick` watermark** (`fetch_max` from validated TXs'
attested `epoch`), never `SystemTime::now()` and never epoch-seconds arithmetic. Only Core checks
64-bit time, and only at launch. A `_SECS` name on any of these is a latent violation to be renamed
`_TICKS`; production tick cadence is TBD at KI#31 switch-on.

#### 23.14.2 Audit Demand Generation

When triggered, Core generates:

```
target_index = u64_le(txid[8..16]) mod len(witness_pks)
target_validator_pk = witness_pks[target_index]
```

The target is selected deterministically from the witness validators of the current transaction —
so the audited peer is always one A actually co-witnessed with (this is the same co-witness
property the Core-buffer provenance argument relies on in §23.14.6).

**Nonce (peer-audit).** The peer-audit challenge nonce is a **fresh random `r` drawn per audit at
commit time** (§23.14.6), NOT a deterministic function of `txid`. A prior design used
`challenge_nonce = BLAKE3("AXIOM_AUDIT_CHALLENGE" || txid)`; because that is a constant per
transaction it gave **no** replay protection for the reveal, and it is superseded. (Self-audit,
which is local and never puts a reveal on the wire, does not need the random nonce.)

#### 23.14.3 DMAP-VM Countdown Enforcement

The DMAP-VM host (interpreter) tracks the pending audit state:

1. **Post-execution:** When Core outputs an `AuditDemand`, the DMAP-VM determines whether this
   is a self-audit (target == our PK) or peer-audit (target != our PK), and starts a countdown:
   - Self-audit: `AUDIT_COUNTDOWN_TXS` (10 TXs)
   - Peer-audit: `PEER_AUDIT_COUNTDOWN_TXS` (100 TXs) + `PEER_AUDIT_TIMEOUT_TICKS` (tick-disciplined
     deadline against `last_validated_tick`, never wall-clock — see §23.14.1 constants)
2. **Pre-execution:** On each subsequent transaction:
   - **Self-audit:** If `audit_confirmation` matches (same nonce, same target PK), satisfied.
     If countdown reaches 0: DMAP-VM returns `AuditTimeout` and terminates.
   - **Peer-audit:** If the response deadline expires without a response, the target validator
     is **banned** (`PEER_AUDIT_BAN_TICKS`, tick-disciplined — see §23.14.6a) and the ban is fanned
     out for independent re-audit. The local DMAP-VM does NOT self-terminate — the innocent party
     is not punished for peer failure.
   - **Ban enforcement:** Before every TX, DMAP-VM checks if any validator in `witness_pks` is banned.
     If so, TX is rejected with `ValidatorBanned` error.

#### 23.14.4 Self-Termination Penalty

When Core self-terminates due to audit timeout, the operator must restart. On every restart:
- VBC chain is re-verified against Genesis root keys (SPHINCS+ signature checks, ~100ms each)
- ZK performance benchmark runs (if ZKP mode configured)
- All in-flight transactions are lost

This creates an operational cost that incentivizes compliance. An operator who ignores audit
demands will face repeated restarts, degrading their throughput and earning capacity.

#### 23.14.5 Enforcement Model

Core (the immutable ELF) generates audit demands deterministically from transaction data.
The DMAP-VM host tracks the countdown. If an operator modifies the DMAP-VM host to skip countdown
enforcement:

- In **ZKP mode:** The modified host produces different STARK proofs (different execution trace).
  Verifiers reject the proof.
- In **DMAP mode:** Re-executors running honest DMAP-VM will observe different checkpoint states.
  DMAP attestation diverges → rejected by other validators.

The enforcement relies on Core's immutability: changing Core changes the ELF hash, which
changes the DMAP/ZKP attestation, which other validators detect and reject.

#### 23.14.6 Lambda Handler — Self-Audit vs Peer-Audit

Lambda receives audit demands from Core's `PublicOutputs.audit_demand`. The target
determines the handler path:

**Self-Audit** (`target_validator_pk == our Ed25519 PK`):

Core is auditing Lambda's database integrity. Lambda does zero crypto — just a DB lookup:

1. Lambda detects self-target by comparing `target_validator_pk` to own public key
2. Lambda looks up `trigger_txid` in `transaction_db`
3. Lambda extracts raw stored fields: `tx_number`, `sender_balance`, `receiver_balance`,
   `state_id` (produced_state_id), `amount`
4. Lambda packages these into `AuditConfirmation` with the matching `challenge_nonce`
5. Lambda passes confirmation to Core in next TX's `PublicInputs.audit_confirmation`
6. Core hashes the raw data (BLAKE3, same domain tag as original accumulation) and
   compares against the stored `TxDigest` entry in the audit buffer
7. Match → audit satisfied, countdown cleared. Mismatch → Lambda tampered → `audit_failed`

Lambda is a dumb pipe: fetch from DB, hand to Core. Core is the sole cryptographic authority.

**Peer-Audit** (`target_validator_pk != our PK`):

Lambda sends a peer-audit request to the target validator via ANTIE email (the protocol-mandated
transport — every validator MUST have ANTIE with email). The protocol is a dual-audit: it forces
the remote validator to self-check AND lets the local validator cross-check.

The audit is a **nonce-bound commit-and-reveal**. A never sends B the answer; A sends
only enough to *locate* the transaction (`txid`) and to *bind* the challenge (a fresh
nonce `r` + a commitment). B must **reconstruct** the answer from its own DB and prove
knowledge of it. Everything is BLAKE3 — **no Core key, no signature on the audit
payload** (Core is stateless; its public key is not part of the system and we introduce
no external function). The one signature involved is on the fanned-out *ban claim*, and
that uses A's Lambda/validator Ed25519 key (already public), not any Core key.

**Outbound (A → B), the commit:**
1. A's Core reads the co-witnessed entry from its **audit buffer** — the DMAP accumulator
   *inside A's Core execution*, NOT A's Lambda DB (this provenance is load-bearing; see
   below) — and computes
   `expected_hash = BLAKE3("AXIOM_PEER_AUDIT_V1" || txid || sender_balance || receiver_balance || state_id || amount)`.
2. A's Core draws a **fresh random nonce `r`** (per-audit; NOT derived from `txid`) and forms
   `a = BLAKE3(expected_hash || r)` (the reveal target) and `commitment = BLAKE3(a) = BLAKE3(BLAKE3(expected_hash || r))`.
3. Lambda sends `AXIOM/peer_audit_request = { txid, r, commitment, auditor_pk = A }`.
   **`expected_hash` is NOT transmitted** — A holds the answer, B must derive it.
4. Lambda marks B "inspecting" and starts the response deadline.

**Remote (B), the reveal:**
5. B's Lambda looks up `txid` in its DB (pure DB op, zero crypto). **Unknown txid → B ignores
   it; B's Core does nothing.** (A can only ever challenge a co-witnessed txid — see provenance
   note — so an unknown txid is not a legitimate challenge; this arm is belt-and-suspenders.)
6. B's Lambda feeds the raw fields to B's Core. B's Core independently computes
   `hash_B = BLAKE3(...same domain...)` from those fields, then `a_B = BLAKE3(hash_B || r)`.
7. B's Core checks `BLAKE3(a_B) == commitment`:
    - **Match:** B's DB reproduces the audited value (only a `hash_B == expected_hash` yields an
      `a_B` whose hash equals `commitment`). B responds with the **single hash `a_B`** (the reveal)
      via `AXIOM/peer_audit_response`. B proved knowledge without A ever revealing the answer.
    - **Mismatch:** B's own stored DB does not reproduce the value → **B's Core RESTARTS**
      (recoverable self-heal: reload state + VBC re-verify, NOT a permanent exit). B sends nothing.

**Inbound (A), the verify + the ban rule:**
8. A verifies `a_B == a` (i.e. `a_B == BLAKE3(expected_hash || r)`). Match → cleared, B honest.
9. **A bans B (`PEER_AUDIT_BAN_TICKS`) and fans out a `PeerAuditBanClaim` (§23.14.6a) iff the
   response is MISSING *or* the revealed `a_B` is WRONG.** The ban rule is **sole-auditor** and
   does not depend on B quitting: no-response (B restarted, or is evasive/unreachable) and
   wrong-reveal both funnel to the *same* A-side ban. A itself keeps running (the innocent
   auditor is never punished). *Silence and a wrong answer are both failures — which is exactly
   what forces an honest B to answer correctly.*

**Why fresh random `r`, and why the double hash:**
- **Fresh `r` (replay resistance).** Without a nonce, the reveal `a_B = f(expected_hash)` is a
  per-tx constant — anyone who once observed a valid reveal could replay it. Binding a
  per-audit random `r` into `a` makes every reveal single-use; a replayed old reveal fails
  `a_B == BLAKE3(expected_hash || r_new)`. (This replaces the old deterministic
  `challenge_nonce = BLAKE3(txid)`, which — being a function of `txid` — gave no replay
  protection.)
- **Commitment = `BLAKE3(a)`, not `expected_hash` (knowledge, not echo).** If A sent
  `expected_hash`, B could echo it without ever consulting its DB. By sending only `BLAKE3(a)`,
  B must *reconstruct* `a` from its own `hash_B` and `r`; only a B whose DB actually reproduces
  `expected_hash` can produce an `a_B` that hashes to `commitment`. Zero-knowledge-flavoured:
  prove you can compute it, don't be told it.

**Core-buffer provenance — why A cannot forge a challenge (the key property):**
A's `expected_hash` originates in A's **Core audit buffer**, a DMAP-attested accumulator that is
a byproduct of A's *own attested Core execution* over the real co-witnessed tx — it does **not**
come from A's Lambda. A cannot place an entry there that its Core did not compute from a tx it
actually processed. Therefore **A can only challenge B on txids A's Core genuinely accumulated,
i.e. txids A and B co-witnessed.** The "invent a txid B never saw" attack is not a move A can
make: no attested buffer entry exists to derive a valid `expected_hash`/`commitment` from. The
unknown-tx case (step 5) is thus something A *cannot originate*, not a grief vector we merely
mitigate.

**Residual + containment (self-incriminating + fanned-out):**
The only residual is a corrupt A *willing to look corrupt*: fabricate a tx through its own
Lambda, force its own Core to attest it (which diverges A's own record), then challenge B. This
is a suicide move — A self-incriminates on the next cross-witness — and even then the false ban
is **contained to A by independent re-audit** (§23.14.6a): every verifier `C` re-audits B with
its *own* Core, honest B passes, the claim dies at A. So the two defenses are separate and
non-overlapping: **commit-and-reveal + fresh nonce** defends the honest-audit path (replay
resistance on the reveal), and **Core-buffer provenance + ban fan-out** shuts the fabrication
path. Trust nothing but (your own) Core.

**Ban enforcement (AVM-held, dual-level):**
- Ban list lives in DMAP-VM (`Arc<AvmInterpreter>`) — survives across TXs, clears on restart
- Any TX with a banned validator in `witness_pks` → rejected by Core (`ValidatorBanned`)
- Lambda mirrors the ban for request-level rejection (optimization — Core enforces regardless)
- Ban expires after `PEER_AUDIT_BAN_TICKS` (17280 ticks ≈ 24 h, projected onto the TX
  `epoch` stamp by `TICK_INTERVAL_SECS`) or on DMAP-VM restart. Expiry is compared
  against `last_validated_tick` — a monotonic (`fetch_max`) watermark advanced ONLY
  from validated transactions' attested `epoch`, **never `SystemTime::now()`** (no
  wall-clock time-gate; see YPX-020 HIBERNATION_WINDOW pattern). A replayed old epoch
  cannot rewind the watermark.

**Ban fan-out and independent re-audit (§23.14.6a):**

A peer-audit ban MUST NOT stay private to the auditor. A locally-held ban only makes
the *one* validator that happened to audit `B` reject `B`; every other validator keeps
co-witnessing with a possibly-corrupt `B` until it independently audits it — distrust
propagates slowly, with no shared evidence. The success path already fans out
(`GossipMessage::PulseProof`, "I audited my Lambda and it passed", YPX-009 §5); the
**failure path must fan out too** — and it is the higher-value signal.

When auditor `A` bans `B` (hash mismatch or no response), `A` broadcasts a
`PeerAuditBanClaim` over Nabla gossip carrying the **evidence**, not just the verdict:
`{ target_pk = B, txid, expected_hash, failure_reason (Mismatch|NoResponse),
banned_at_tick, auditor_pk = A, ed25519_sig(A) }`.

The claim is a **trigger, not authority** — no node is trusted (the §1 rule). A
recipient `C`:
1. verifies the claim is structurally valid + `A`'s signature (O(1)), then
2. **independently decides whether to verify** — `C` runs its OWN peer-audit of `B`
   (issues its own `peer_audit_request`), and
3. adopts the ban into its own AVM ban list **only if `C`'s own audit also fails**.

Consequences:
- **Distrust converges fast** without blind adoption: one honest auditor's claim
  prompts the whole mesh to re-check `B`, and a genuinely corrupt `B` is rejected
  network-wide within an audit round instead of one-auditor-at-a-time.
- **False claims are self-defeating** (anti-abuse): a malicious `A` cannot ban an
  honest `B` mesh-wide by broadcasting lies — every `C` re-audits independently, an
  honest `B` passes `C`'s audit, so `C` ignores the claim (and MAY down-weight `A`
  for a false accusation). Adoption requires each verifier's *own* confirmation.
- **Enforcement is unchanged** — the ban still lives in the DMAP-VM and Core still
  rejects TXs with a banned `witness_pk`. Fan-out only ADDS a Nabla gossip feed that
  populates each validator's AVM ban list *after* that validator's own re-audit; it
  does not move the ban out of Core's judgement.

Contrast with `PulseProof`: a PulseProof (success) is self-attested and verified
*structurally* (peers cannot re-run the audit, §5.2). A `PeerAuditBanClaim` (failure)
is **re-auditable** — the verifier confirms it by doing the audit itself, not by
trusting the claim.

**Key invariants:**
- Core is the **judge** (computes, compares, decides). Lambda is the **police** (carries, does DB lookups)
- Transport is always **ANTIE email**. Every validator is protocol-required to have ANTIE with email
- The innocent party is never punished for peer failure — peer gets banned, local DMAP-VM keeps running
- **Commit-and-reveal, no answer on the wire:** A sends `{ txid, r, commitment = BLAKE3(BLAKE3(expected_hash‖r)) }`;
  A never transmits `expected_hash`. B must *reconstruct* the reveal `a_B = BLAKE3(hash_B‖r)` from its
  own DB and prove `BLAKE3(a_B) == commitment`; only then does it reveal the single hash `a_B`.
- **No Core key, no signed audit payload** — all BLAKE3. Core is stateless and has no public key;
  the only signature is A's Lambda Ed25519 on the fanned-out ban claim (§23.14.6a), never on the audit.
- **Fresh random nonce `r` per audit** binds the reveal single-use (replay resistance); the reveal is
  otherwise a per-tx constant. The old deterministic `BLAKE3(txid)` nonce gave no replay protection.
- **`expected_hash` provenance is A's Core audit buffer, not A's Lambda** — so A can only challenge a
  co-witnessed txid; A cannot originate a challenge for a tx it never processed (unknown-tx is impossible
  to forge, not merely rejected).
- **Sole-auditor ban rule:** A bans B on **no-response OR wrong-reveal** — both funnel to the one A-side
  ban. The ban does NOT depend on B quitting.
- **A validator self-terminates (restarts, recoverably) ONLY when its OWN Core finds its OWN corruption
  — NEVER on a peer's challenge.** With commit-and-reveal B can't be framed into a wrong verdict: a
  forged challenge can't be originated (provenance), and B only ever reveals what its *own* Core computed.
- **A ban is a fanned-out, independently-re-auditable claim — never a privately-held
  local reject, and never adopted on the auditor's word alone (§23.14.6a).**

#### 23.14.7 Security Properties

| Property | Guarantee |
|----------|-----------|
| Deterministic trigger | Same txid always triggers/doesn't trigger — no operator choice |
| Target binding | Deterministic target from the TX's own witnesses (co-witness), so provenance holds (§23.14.6) |
| Reveal replay resistance | Fresh random per-audit nonce `r` binds the reveal single-use; a replayed reveal fails (§23.14.6) |
| Answer never on the wire | Commit-and-reveal: A sends `BLAKE3(BLAKE3(expected_hash‖r))`, B reconstructs from its own DB (§23.14.6) |
| No forged challenge | `expected_hash` provenance is A's Core audit buffer, not A's Lambda — A can't challenge an un-co-witnessed txid |
| Non-bypassable | DMAP-VM enforces countdown; modified DMAP-VM detected by DMAP/ZKP |
| Operationally costly | Self-audit: restart penalty. Peer-audit: 24h ban on target |
| Privacy-preserving | Audit target selected from transaction's own validators — no network scan |
| Lambda does no crypto | Both self and peer audit: Lambda sends raw DB data, Core hashes and verifies |
| DB tampering detected | Self-audit: hash mismatch vs audit buffer. Peer-audit: B's reveal fails `BLAKE3(a_B)==commitment` (no-response) or A's `a_B==a` check (wrong-reveal) |
| Dual audit | Peer-audit triggers self-check on remote AND cross-check on local |
| Innocent party protected | Peer-audit timeout bans the peer, NOT the local DMAP-VM |
| ANTIE email transport | Protocol-mandated: every validator MUST have ANTIE with email |
| Ban self-healing | 24h expiry or DMAP-VM restart — temporary network issues don't permanently ban |


## 24. axiom-core.elf Gatekeeping Specification

This section consolidates all `axiom-core.elf` responsibilities into a single authoritative reference. It introduces no new rules -- it collects and formalizes what is specified throughout this document.

### 24.1 Purpose and Scope

`axiom-core.elf` is the **immutable binary truth engine** of the Lambda system.

It runs identically on both Client and Validator, executing within the DMAP-VM (AXIOM Virtual Machine) via Vault isolated memory.

**axiom-core.elf answers only one question:**

> *Given these inputs, what is true?*

It does NOT answer:
- What is politically acceptable
- What is socially desirable
- What is urgent or necessary

### 24.2 Physical Invariants (Immutable)

These invariants are enforced at the binary level and cannot be overridden by any component.

#### 24.2.1 Signature Integrity

Every claim MUST be cryptographically authorized by the key holder.

```
signature_valid(tx) -> true | false
```

- Invalid signatures -> **REJECT**
- No exception, no override, no fallback

#### 24.2.2 Atom Conservation

The claimant MUST possess the atoms they are attempting to spend.

```
balance(sender) >= amount(tx) -> true | false
```

- Insufficient balance -> **REJECT**
- AXC atoms cannot be created or destroyed by transactions
- Total supply is conserved across all operations

### 24.3 Transaction Validation Rules

Before signing any transaction, `axiom-core.elf` performs mandatory validation checks.

| Check | Rule | Failure Action |
|-------|------|----------------|
| **TTL constraint** | `tx.ttl <= 10` | REJECT |
| **Timestamp validity** | `tx.timestamp < current_time` | REJECT |
| **Witness count minimum** | `witness_count >= 3` | REJECT |
| **Witness count maximum** | `witness_count <= 5` | REJECT |
| **Signature verification** | All signatures valid | REJECT |
| **Balance sufficiency** | `balance >= amount` | REJECT |
| **Nonce uniqueness** | No duplicate nonce | REJECT |
| **State transition validity** | Valid state change | REJECT |
| **VBC verification** | All witness VBCs trace to Origin | REJECT (REALITY_ANCHOR_FAILURE) |

**Cross-reference:** Section 16.6.1 for detailed validation logic, Section 23.13 for VBC specification.

### 24.4 Canonical Bytes Processing

`axiom-core.elf` is responsible for deterministic serialization and hash calculation.

#### 24.4.1 Canonical Bytes Verification

All payloads MUST conform to Canonical Bytes format:

```
CB := MAGIC(4) || CB_VERSION(1) || CODEC(1) || LEN(varint) || PAYLOAD || CRC32C(4)
```

- Non-conformant payloads -> **REJECT**
- No silent repair or reinterpretation

**Cross-reference:** `LAMBDA_CANONICAL_JSON_BYTES.md`

#### 24.4.2 Hash Calculations

| Hash | Algorithm | Input | Purpose |
|------|-----------|-------|---------|
| **txid** | BLAKE3 | CB_core | Semantic identity |
| **state_hash** | SHA3-256 | CB_full | Signature/state identity |

These calculations are deterministic and reproducible across all compliant implementations.

**Cross-reference:** Section 17.2.1, 17.2.2

### 24.5 Protocol Enforcement (Hardcoded)

The following rules are encoded in `axiom-core.elf` and cannot be modified by any external mechanism.

#### 24.5.1 Bootstrap Retirement Logic

Enforces the sunset of founding control according to predefined schedule.

- Retirement timeline is hardcoded
- No extension mechanism exists
- No override possible

#### 24.5.2 DEED Distribution Rules

Ensures correct distribution of developer equity during protocol phases.

- Distribution formula is hardcoded
- Allocation percentages are immutable
- No discretionary adjustment

#### 24.5.3 Reserve Claim Rules

Enforces Reserve Pool claim mechanics.

- Claim limits are policy-defined but Core-enforced
- Special witness rules (3+1 rotating) are hardcoded
- Anti-sybil protections are binary-enforced

**Cross-reference:** Section 22.4

### 24.6 Format Gatekeeping

`axiom-core.elf` rejects non-compliant payloads before they consume resources.

| Payload Issue | Action |
|---------------|--------|
| Invalid MAGIC bytes | REJECT |
| Unknown CB_VERSION | REJECT |
| Unknown CODEC | REJECT |
| CRC32C mismatch | REJECT |
| Non-NFC string | REJECT |
| Invalid UTF-8 | REJECT |
| Floating point values | REJECT |
| Prohibited types (NaN, Infinity) | REJECT |

**Principle:** Reject early, reject clearly, reject deterministically.

### 24.7 What axiom-core.elf Does NOT Do

`axiom-core.elf` is explicitly constrained from the following:

| Prohibited Action | Reason |
|-------------------|--------|
| **Policy decisions** | Core enforces rules, does not create them |
| **Emergency override** | No emergency mechanism exists in Core |
| **Discretionary judgment** | All decisions are deterministic |
| **Parameter adjustment** | Parameters are inputs, not Core decisions |
| **Governance** | Core >=  governance |
| **Network coordination** | Handled by Lambda and Gateways |
| **Economic intervention** | Core does not stabilize markets |

### 24.8 axiom-core.elf vs Λ (Lambda) Separation

| Component | Responsibility | Modifiable |
|-----------|----------------|------------|
| **axiom-core.elf** | Cryptographic truth, validation, gatekeeping | **NO** (immutable binary) |
| **Λ (Lambda)** | Consensus logic, witness coordination, k=3 | **YES** (open source, GPL v3) |

This separation ensures:
- Critical enforcement cannot be modified
- Consensus logic can evolve independently
- Single binary serves both Client and Validator

### 24.9 Summary: axiom-core.elf Gatekeeping Checklist

```
+--------------------------------------------------------------+
|                    CORE.BIN GATEKEEPING                      |
+--------------------------------------------------------------+
|  PHYSICAL INVARIANTS (Always Enforced)                       |
|  * Signature integrity                                       |
|  * Atom conservation                                         |
+--------------------------------------------------------------+
|  TRANSACTION VALIDATION                                      |
|  * TTL <= 10                                                 |
|  * Timestamp in past                                         |
|  * Witness count 3-5                                         |
|  * All signatures valid                                      |
|  * Balance sufficient                                        |
|  * Nonce unique                                              |
|  * State transition valid                                    |
+--------------------------------------------------------------+
|  CANONICAL BYTES                                             |
|  * CB format valid                                           |
|  * MAGIC correct                                             |
|  * CRC32C verified                                           |
|  * NFC normalized                                            |
|  * No prohibited types                                       |
+--------------------------------------------------------------+
|  PROTOCOL RULES (Hardcoded)                                  |
|  * Bootstrap retirement                                      |
|  * DEED distribution                                         |
|  * Reserve claim rules                                       |
+--------------------------------------------------------------+
```

### 24.10 Summary Invariant

> **axiom-core.elf is the Gatekeeper.**
>
> It does not decide what should be true.
> It determines what **is** true.
>
> Any payload that passes Core is valid.
> Any payload that fails Core does not exist.
>
> There is no appeal. There is no override. There is no exception.


## 25. Validator Compensation Model

The AXIOM Lambda protocol intentionally moves away from the "inflation-based" compensation models common in legacy blockchains. In Lambda, a validator is a **service provider**, and their compensation is a direct reflection of the utility they provide to the network.

### 25.1 Design Philosophy

Beyond the fee structure, the full compensation model encompasses:
- Three primary revenue streams
- Market-driven incentives
- A long-term sustainability plan that eliminates the need for venture capital

**No inflation-based rewards exist.** Validators earn through service, not through dilution of existing holders.

#### 25.1.1 Security Budget and Economic Parameters

The economic model is based on the **Security Budget Requirement** -- the minimum compensation needed to sustain a validator network resistant to state-level coercion.

**Key Economic Parameters:**

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Validator Cost (C_v)** | $90,000/year | Resilient OPEX including infrastructure, security, legal, and coercion risk premium |
| **Target Validator Count (N_v)** | 10,000 | Required for bounded witness discovery under 90% partition |
| **Decoy Query Fee (DQF)** | 1 AXC | Economic deterrent for mass/speculative queries |
| **EMVT** | 1.125 trillion L$/year | Economic Minimum Viability Threshold at 0.08% fee floor |

**Security Budget Formula:**

```
V >= (N_v - C_v) / F

Where:
  V   = Minimum annual transaction volume
  N_v = Validator count (10,000)
  C_v = Validator annual cost ($90,000)
  F   = Network fee rate
```

**EMVT Sensitivity:**

| Fee Rate | Required Annual Volume |
|----------|----------------------|
| 0.08% (Safety Floor) | $1.125 Trillion |
| 1.0% (Market Base) | $90 Billion |
| 2.0% (Defensive) | $45 Billion |

**Important:** EMVT is a **diagnostic parameter only**. Falling below EMVT does not trigger protocol enforcement -- it signals increased ambiguity and natural exit pressure.

> **[Added 2026-06-09 — fee-cap self-regulation note]** EMVT defines no *maximum* fee rate. As a later, separate decision, AXIOM self-caps the **per-validator fee at 0.3%** (k=3 → **0.9%** aggregate maximum): being permissionless, it is under no obligation to follow financial regulation, but adopts the European card-interchange cap (0.3% on credit) as an external economic anchor — borrowing the judgment of the economists who already justified 0.3% as a sound per-transaction ceiling, rather than asserting a novel figure of our own. *Non-normative reference:* validator operators can model fee/DEED revenue across adoption levels with the interactive **Validator & DEED economics** tool (`docs/AXIOM_GUIDE_ValidatorEconomics.html`) — an illustrative aid to help operators justify their investment, not a forecast or a protocol guarantee.

**Full Derivation:** See White Paper (AXIOM v2.28) Section J.2 "The Security Budget Axion" for complete derivation, validator cost breakdown, and sensitivity analysis.

### 25.2 The Three Revenue Streams

| Revenue Stream | Source | Purpose |
|----------------|--------|---------|
| **Transaction Witnessing Fees** | Deducted from sender's transfer amount | Primary income for real-time service |
| **Query Compensation** | Paid by querier (1 AXC) | Compensates for legal/judicial participation burden |
| **Console Participation** | Protocol-level stipend (1 AXC per full service year) | Incentive for maintaining high-uptime, high-capability software |

#### 25.2.1 Transaction Witnessing Fees

Validators earn fees for participating in the k=3 (or k=4, k=5) witness set for transactions.

- Fee amount is set by each validator independently (see 19)
- Fee is deducted from the transfer amount
- Validators compete on price, speed, and reliability

**Cross-reference:** Section 19 (Validator Fee Discovery & Selection)

#### 25.2.2 Query Compensation

When a validator responds to a judicial or PWV-related query:

- Querier pays **1 AXC** per query
- Compensation is distributed to responding validators
- This creates economic cost for fishing expeditions

**Cross-reference:** Section 5.2 (Query Cost)

#### 25.2.3 Console Participation

Console members receive a fixed stipend:

- **1 AXC per full service year**
- Paid only if Console completes the full epoch without dissolution
- Forfeited entirely if any member fails capability or liveness requirements

**Cross-reference:** Section 21.12.4 (Compensation Eligibility)

### 25.3 Market-Driven Differentiators

Because validators have **autonomous pricing sovereignty**, they do not compete solely on "luck" or "hash power," but on business strategy:

#### 25.3.1 Security Posture

Validators can choose to run more secure, albeit computationally expensive, cryptographic algorithms.

| Algorithm Option | Security Level | Market Position |
|------------------|----------------|-----------------|
| Op 1 (Ed25519) | Standard | General use |
| Op 2 (Dilithium) | Post-quantum | Security-conscious |
| Op 3 (SPHINCS+) | Maximum | Institutional, quantum-proof |

Validators offering Op 3 can market themselves to high-value institutional clients willing to pay a premium for "quantum-proof" validation.

**Cross-reference:** Section 16.4 (Three-Algorithm Future-Proofing)

#### 25.3.2 Reputation & TTL

While the protocol doesn't enforce reputation, **the market does**.

A validator who honors their published Fee Rate TTL (Time-to-Live) builds trust, leading to more frequent selection by automated client wallets.

**Cross-reference:** Section 19.4 (Reputation vs Protocol Enforcement)

#### 25.3.3 Tier Selection

Validators can opt-in to higher Assurance Tiers:

| Tier | Witness Count | Use Case |
|------|---------------|----------|
| Tier 3 | k=3 | Standard transactions |
| Tier 4 | k=4 | High-value transactions |
| Tier 5 | k=5 | Maximum security |

Positioning for Tier 4/5 allows validators to serve high-stakes transactions requiring larger witness sets.

**Cross-reference:** Section 6.2 (PWV Set Size)

### 25.4 Long-Term Sustainability: The DEED Transition

The compensation model is divided into two distinct phases to ensure the protocol can fund its own development without external influence.

#### 25.4.1 Phase A: The DEED Era (Initial 5--10 Years)

During the bootstrap period, validator fees are split according to the Developer Equity & Execution Deed (DEED):

| Recipient | Share | Duration |
|-----------|-------|----------|
| **Validator** | 80% | Permanent |
| **Protocol Development** | 10% | 10 years |
| **Implementation Team** | 10% | 5 years |

- Validator keeps the lion's share to cover hardware and maintenance
- Protocol development fund ensures core maintenance
- Implementation team fund rewards the specific software builders

**Cross-reference:** Section 20 (DEED System)

#### 25.4.2 Phase B: The Post-DEED Era

Once the DEED time limits expire:

- **Protocol-level** fee allocation ceases
- Validators retain **100%** of their earned fees (before any implementation-level deductions)
- Market enters a fully-matured competitive state

#### 25.4.3 Implementation-Level Fee Sovereignty (Both Eras)

**Critical Design Principle:**

Regardless of whether the system is in DEED Era or Post-DEED Era, Λ (Lambda) developers, Gateway developers, and other implementation teams **MAY impose their own fees** on top of the protocol.

| Era | Protocol Fee | Implementation Fee |
|-----|--------------|-------------------|
| **DEED Era** | 20% (10% Protocol + 10% Implementation) | *... Allowed |
| **Post-DEED Era** | 0% | *... Allowed |

**Why This Is Encouraged:**

1. **Sustainable Development Incentive**
   
   After DEED expires, there is no protocol-level funding for development. Allowing implementation-level fees ensures developers have ongoing incentive to:
   - Maintain and improve their Lambda implementations
   - Develop better Gateway software
   - Create superior Client experiences

2. **Market-Driven Quality**
   
   If a Lambda implementation charges 5% fee but offers superior features, validators may choose it. If another charges 0% but is less reliable, the market decides.

3. **No Protocol Enforcement**
   
   The protocol does **not** enforce or collect implementation fees. This is purely a business decision between:
   - Lambda developers and validators who run their software
   - Gateway developers and validators who use their transport layer
   - Client developers and users who choose their wallet

**Example (Post-DEED Era):**

```
Transaction fee earned by Validator: 1.0 L$

Protocol allocation: 0% (DEED expired)

Implementation allocations (voluntary, market-driven):
- Lambda developer fee: 0.05 L$ (5%, if imposed)
- Gateway developer fee: 0.02 L$ (2%, if imposed)

Validator keeps: 0.93 L$
```

**Design Rationale:**

> The protocol ensures a **floor** (validators keep 80% during DEED, 100% after).
> The market determines the **ceiling** (developers may charge for superior implementations).
> 
> This creates perpetual incentive for innovation without protocol-level mandates.

### 25.5 Staking Requirement

#### 25.5.1 Stake Amount

To become an active validator, an entity must stake:

> **500 AXC**

This stake serves as:
- Economic commitment signal
- Skin-in-the-game for proper operation
- **NOT** a slashing collateral

#### 25.5.2 Stake Disqualification and Core Gatekeeping

**The Two-Layer Enforcement Model:**

Lambda uses a practical two-layer approach to stake enforcement that bridges the White Paper's design intent with implementation reality:

| Layer | Component | Enforcement | Reliability |
|-------|-----------|-------------|-------------|
| **Layer 1** | Core (axiom-core.elf) | Stops service when stake < 500 AXC | **Guaranteed** (cryptographic) |
| **Layer 2** | Λ (Lambda) | Marks validator as "Disqualified" | **Best-effort** (implementation-dependent) |

**Why Two Layers?**

The White Paper (4.13.2, 4.5.2) specifies that validators falling below the stake threshold are "immediately disqualified" with stake "forfeited to SRP." However, practical implementation faces a challenge:

> **The Core cannot force stake forfeiture without preventing the validator from rolling back its local state.**

A malicious or incomplete Lambda implementation could simply ignore the "forfeiture" instruction and continue operating with a rolled-back database.

**The Solution: Core as Ultimate Gatekeeper**

Rather than attempting cryptographic enforcement of forfeiture (which is impossible without global consensus), Core provides an absolute gate:

```
Core Validation (every transaction):
  IF validator_stake < 500 AXC:
    RETURN Error::InsufficientStake
    // Service halted - no transactions processed
    // Cannot be bypassed by any Lambda implementation
```

**This means:**
- Core **stops all validator services** when stake falls below threshold
- No signing, no witnessing, no fee earning
- This enforcement is **cryptographically guaranteed** -- cannot be bypassed
- Validator becomes operationally dead regardless of Lambda implementation

**Layer 2: Lambda Status Management (Best-Effort)**

When stake falls below threshold, Lambda SHOULD:
1. Mark the validator status as **"Disqualified"**
2. Broadcast Invalidation Notice to network
3. Update local records to reflect stake forfeiture to SRP

**However:** Lambda implementations may vary. Some developers may not fully implement status tracking. This is acceptable because:

- Core already guarantees service cessation
- The validator cannot earn fees regardless of Lambda status
- Economic death occurs even without perfect status tracking

**Comparison to Traditional Slashing:**

| Aspect | PoS Slashing | Lambda Disqualification |
|--------|--------------|-------------------|
| Mechanism | Protocol seizes collateral | Core stops service; Lambda marks status |
| Enforcement | Requires global consensus | Local enforcement by Core |
| Reversibility | Collateral lost permanently | Service resumes if stake restored |
| Attack vector | Coercer can force stake loss | Coercer can only force service halt |
| Rollback vulnerability | Protocol prevents | Core prevents service; status is best-effort |

**Design Rationale:**

This approach achieves the White Paper's intent (disqualified validators lose operational capability) while acknowledging implementation reality (we cannot cryptographically force stake forfeiture without global state). The Core ensures the validator is economically dead; Lambda provides the formal status update.

#### 25.5.3 Voluntary Exit vs. Disqualification

**Two paths exist for ending validator status:**

| Path | Trigger | Stake Outcome | Service |
|------|---------|---------------|---------|
| **Voluntary Exit** | Validator withdraws stake | Stake returned to validator | Stops immediately |
| **Disqualification** | Stake falls below 500 AXC (audit failure, misbehavior, etc.) | Stake forfeited to SRP (per White Paper 4.13.2) | Stopped by Core |

**Voluntary Exit:**
- Validator chooses to withdraw their 500 AXC
- Transaction requires k=3 witnesses (normal transaction)
- Once balance < 500 AXC, Core stops service
- Validator receives their stake back
- Clean exit with no penalty

**Disqualification:**
- Stake falls below threshold due to:
  - Audit failure (4.5.2)
  - Peer-detected misbehavior
  - Protocol violation evidence
- Lambda SHOULD mark stake as "forfeited to SRP"
- Core stops all services immediately
- **Practical note:** Actual forfeiture depends on Lambda implementation
- **Guaranteed effect:** Validator cannot operate regardless

**The Key Insight:**

> Whether stake is "returned" (voluntary exit) or "forfeited" (disqualification) is a Lambda-level distinction.
>
> What Core guarantees is simpler: **stake < 500 AXC = no service.**
>
> The economic death of the validator is certain. The accounting treatment of the stake depends on Lambda implementation fidelity.

#### 25.5.4 Stake Verification via Nabla (Anti-Rollback)

**The Problem:**

A Validator is also a Client (has their own wallet). In a Client-side Truth model, what prevents a Validator from rolling back their local database and pretending the stake was never moved?

**The Solution — Nabla as Stake Witness:**

The system does not prevent rollback — it makes rollback **ineffective**. A Validator can rollback their own Lambda storage, but they cannot rollback Nabla's collective state. Nabla is the network's source of truth for wallet state, including validator wallets.

**Why Rollback Doesn't Work:**

1. **Stake Movement = Normal Transaction**

   If a Validator moves their staked AXC, this is a normal k=3 witnessed transaction. The witnesses register the state change with Nabla. Nabla's SMT now reflects the reduced balance.

2. **Nabla Verification (Reader-Only)**

   Validators verify each other's stake by querying Nabla — specifically, a **reader node** (never a writer). The query returns the wallet's current registered state, which is DMAP-attested from k=3 witnesses. The validator cannot fake this — Nabla's state came from independent witnesses, not from the validator's own Lambda.

3. **Discovery and Invalidation Notice**

   If a validator discovers (via Nabla query) that another validator's stake has fallen below the tier minimum:
   - Generate an **Invalidation Notice** (Fan-Out, CL10 verified)
   - Broadcast via fanout propagation to the entire network
   - All nodes mark that validator as invalid after the specified timestamp

**Stake Verification Flow:**

```
1. Validator B transfers away their stake (requires k=3 witnesses)
2. Witnesses register the state change with Nabla
3. Validator A queries Nabla (reader node) for B's wallet state
4. Nabla returns: B's current balance < tier minimum
5. A broadcasts Invalidation Notice via Fan-Out (CL10):
   {
     validator_id: B,
     invalid_after: timestamp_T,
     evidence: nabla_state_hash showing balance < minimum
   }
6. Network receives notice via fanout propagation
7. All participants mark B's signatures after timestamp_T as INVALID
```

**Why Nabla, Not Peer-Audit:**

| Method | Trust Model | Weakness |
|--------|------------|----------|
| Ask Validator B directly | B can lie | Fox guarding henhouse |
| Ask B's witnesses | Need to know who witnessed | Discovery problem |
| **Query Nabla reader** | **Neutral third party** | **Trustless — state is DMAP-attested** |

Nabla readers are passive observers. They never modify state. They sync via gossip
from writers who received registrations from k=3 witnesses. The chain of trust:
k=3 witnesses $\to$ DMAP proof $\to$ Nabla writer $\to$ gossip $\to$ Nabla reader $\to$ validator query

**Validator ↔ Nabla Security: Reader-Only Rule**

Validators MUST only connect to Nabla **reader** nodes, never writers:

```
Nabla Reader:
  - Syncs state via gossip (anti-entropy)
  - Serves wallet-state queries over the TCP-CBOR WireMessage wire
  - Never accepts registrations
  - Signs responses with role: "reader" attestation
  - Validator operator may run their own reader (localhost, simplest setup)

Nabla Writer:
  - Accepts registrations, modifies SMT
  - High-value target (write access to state)
  - Validators MUST NOT connect to writers for queries
  - If Core detects a response from a writer → fail-stop (exit)

Why:
  - A compromised writer could feed the validator false state
  - A reader can only serve what gossip delivered — stale at worst, never fabricated
  - Stale data → validator sees SCARRED (safe failure), not false CLEAN
```

**Nabla Node Configuration:**

```toml
# Reader-only mode (recommended for validator-paired Nabla nodes)
[nabla]
reader_only = true    # Never become a writer, always redirect registrations
```

When `reader_only = true`:
- Node joins TARDIS tree as READER (never claims D-slots for writing)
- Registration requests always return `reader_redirect`
- Gossip and anti-entropy continue to replicate state from writers (reader receives but does not originate registrations).
- TCP-CBOR `QueryWalletStateRequest` queries return results from local replica (read path is identical to writer nodes).

**Transport — functional endpoints (NORMATIVE).** Every Nabla wallet-, validator-, and operator-facing functional operation — state registration, wallet-state query, CLARA heal registration, cheque-claim registration, txid lookup, PulseProof forwarding, JFP vote-secret registration/query, partition-recovery bridging, and ban-challenge governance — travels over the **TCP-CBOR `WireMessage` wire** (length-prefixed CBOR frames; never JSON). Nabla's HTTP listener serves only operator dashboard / monitoring routes — the twelve functional HTTP endpoints (`/register`, `/clara`, `/query`, `/register-cheque-claim`, `/query-cheque-claim`, `/query-txid`, `/pulse-proof`, `/jfp-secret`, `/jfp-secrets`, `/bridge`, `/endorse-ban-challenge`, `/challenge-ban`) return `410 Gone`. The browser webclient, which cannot open raw TCP, is the sole exception and is migrated separately. See `AXIOM_DESIGN_TransportLayer.md`.

**Response Identity Attestation:**

Every Nabla response includes a signed role declaration:

```
{
  "role": "reader",           // or "writer"
  "node_id": "...",
  "signature": "...",         // Ed25519 sig over role + response
}
```

#### 25.5.4a Writer/Reader Role Signature Payload (Normative)

The role attestation uses domain tag `AXIOM_NABLA_ROLE`. Implementers MUST construct the signing payload as:

```
BLAKE3(
    b"AXIOM_NABLA_ROLE"   // domain tag (16 bytes)
    || node_id             // 32 bytes
    || role                // u8: 0 = reader, 1 = writer
    || wallet_id           // 32 bytes (queried wallet)
    || state_id            // 32 bytes (current_state for this wallet)
    || tick                // u64 LE (synced_to_tick)
)
```

The node signs the BLAKE3 output with its Ed25519 key. Validators verify the role is `0` (reader); a response with role `1` (writer) triggers fail-stop. Binding `wallet_id`, `state_id`, and `tick` prevents replay of stale role attestations across wallets or state transitions. Reference: `nabla/src/bin/nabla_node.rs`.

Core (CL1 or a pre-check in Lambda) verifies:
- Response is from a known Nabla node (NBC verified)
- Role is "reader" — if "writer", Core exits (fail-stop)

**The Core Insight:**

> A Validator can rollback their own memory.
> They cannot rollback Nabla's memory — because Nabla's state came from
> k=3 independent witnesses, not from the validator.

**Relationship to Exit as Security Primitive:**

This mechanism reinforces 4.4 (Exit as Security Primitive):
- A Validator can choose to withdraw their stake (Exit)
- This immediately terminates their validator status (Nabla reflects the balance change)
- They receive their staked AXC back
- But they lose all future earning capability

The choice is binary: **remain staked and operational**, or **exit and forfeit validator status**.

### 25.6 Risk and Penalty Model

Instead of slashing, Lambda uses **Economic Forfeiture**:

#### 25.6.1 Capability Failure (Console)

If a validator is selected for the Console but fails to meet requirements:

| Failure Type | Consequence |
|--------------|-------------|
| Liveness failure | Forfeit entire annual Console stipend |
| Capability failure | Forfeit entire annual Console stipend |
| Software incompatibility | Forfeit entire annual Console stipend |

**All Console members forfeit** if any member fails -- this creates mutual accountability.

**Cross-reference:** Section 21.12 (Console Capability Requirements)

#### 25.6.2 Market Consequences (Non-Protocol)

For general validation failures:

| Behavior | Protocol Consequence | Market Consequence |
|----------|---------------------|-------------------|
| Downtime | None | Lost fees, reputation damage |
| Slow response | None | Clients choose competitors |
| TTL violation | None | Trust erosion, fewer selections |

The protocol does not punish. The market does.

#### 25.6.3 Stake Protection and Forfeiture

| Scenario | Stake Outcome | Enforcement |
|----------|---------------|-------------|
| Voluntary withdrawal | Returned to validator | Normal transaction |
| Stake drops below 500 AXC (any cause) | Forfeited to SRP | Lambda (best-effort) |
| Past earnings | Cannot be clawed back | N/A |
| Exit rights | Always available (until disqualified) | Core + Lambda |

**Important Distinction:**

The White Paper (4.13.2) specifies stake forfeiture to SRP upon disqualification. This Yellow Paper acknowledges:

1. **Core guarantees service cessation** -- cryptographically enforced
2. **Lambda handles forfeiture accounting** -- implementation-dependent
3. **Economic effect is identical** -- validator cannot operate either way

**Why Exit Rights Matter:**

A validator can **voluntarily exit** at any time by withdrawing their stake. This is different from **disqualification** (forced exit due to misbehavior).

- Voluntary exit: Stake returned, clean departure
- Disqualification: Stake forfeited (per White Paper), service stopped (by Core)

#### 25.6.4 Continuous Peer-Auditing (The "Ping" Defense)

The security of Lambda is not derived solely from the quantity of witnesses per transaction, but from the **constant threat of random peer-review**.

**Mechanism:**

Every validator in the network is subject to random, asynchronous "Pings" from its peers. These are not simple heartbeats, but cryptographic challenges requiring the node to prove:
- It holds a valid, untampered state
- Its balance remains >= 500 AXC (stake requirement)
- Its software is capable of protocol operations

**The Invariant:**

A validator that colludes to witness a fraudulent transaction -- even if it was purposely selected by the client -- cannot predict when it will be audited.

**Consequence of Audit Failure:**

| Failure Type | Core Response | Lambda Response |
|--------------|---------------|-----------------|
| State inconsistency | Stops service (if stake affected) | Invalidation Notice broadcast |
| Stake below 500 AXC | **Stops service immediately** | Marks status as Disqualified |
| Capability failure | N/A | Exclusion from active set |

**Alignment with White Paper (4.5.2, 4.13.2):**

The White Paper specifies "permanent loss of staked collateral" upon audit failure. This Yellow Paper provides the implementation model:

| White Paper Intent | Implementation Reality |
|-------------------|----------------------|
| "Loss of staked collateral" | Lambda marks stake as forfeited to SRP |
| "Immediate disqualification" | Core stops all services when stake < 500 AXC |
| "Permanent" consequence | Validator cannot operate without re-staking |

**The Two-Layer Model in Action:**

```
Audit reveals stake < 500 AXC:

Layer 1 (Core) - GUARANTEED:
   Core detects stake < 500 AXC
   All validator services STOP
   Cannot sign, witness, or earn
   This is cryptographically enforced

Layer 2 (Lambda) - BEST-EFFORT:
   Lambda broadcasts Invalidation Notice
   Lambda marks validator as "Disqualified"
   Lambda records stake forfeiture to SRP
   Implementation fidelity varies
```

**Why This Design:**

Traditional slashing requires global consensus to "seize" collateral. Lambda has no global consensus.

Instead:
- **Core provides the hard gate** -- no service below threshold
- **Lambda provides the accounting** -- status and forfeiture tracking
- **Economic effect is identical** -- disqualified validator is operationally dead

**Implementation Note for Lambda Developers:**

Fully implementing the Disqualification status and SRP forfeiture tracking is RECOMMENDED but not cryptographically enforced. However:

- Validators running incomplete Lambda implementations will still be stopped by Core
- The network will still function correctly
- Individual validators may have inconsistent status records
- This is acceptable because Core guarantees the security property

**Cross-reference:** Section 25.5.2 (Stake Disqualification and Core Gatekeeping)

### 25.7 Summary: Compensation Model Overview

```
+--------------------------------------------------------------+
|              VALIDATOR COMPENSATION MODEL                    |
+--------------------------------------------------------------+
|  ENTRY REQUIREMENT                                           |
|  - 500 AXC stake                                             |
|  - Voluntary exit: stake returned                            |
|  - Disqualification: stake forfeited to SRP (per WP 4.13.2) |
+--------------------------------------------------------------+
|  REVENUE STREAMS                                             |
|  + Transaction Fees (primary income)                         |
|  + Query Compensation (1 AXC per query)                 |
|  - Console Stipend (1 AXC/year, conditional)                 |
+--------------------------------------------------------------+
|  DEED ERA (Years 1-10)                                       |
|  + Validator: 80%                                            |
|  + Protocol: 10% (10 years)                                  |
|  - Implementation: 10% (5 years)                             |
+--------------------------------------------------------------+
|  POST-DEED ERA                                               |
|  - Validator: 100%                                           |
+--------------------------------------------------------------+
|  ENFORCEMENT (Two-Layer Model)                               |
|  + Core: Stops service when stake < 500 AXC (GUARANTEED)     |
|  + Lambda: Marks Disqualified status (BEST-EFFORT)           |
|  - Console failure: Forfeit stipend only                     |
|  - Market failure: Lost business (not protocol penalty)      |
+--------------------------------------------------------------+
```

### 25.8 Summary Invariant

> **Validators are service providers, not speculators.**
>
> They earn through utility, not inflation.
> They risk their stake upon disqualification.
> They can exit freely via voluntary withdrawal.
>
> Core guarantees: stake < 500 AXC = no service.
> Lambda records: disqualification status and forfeiture.




## 26. ZKP Execution Attestation (ZKP Patch v1.5.0)

This section defines the Zero-Knowledge Proof execution attestation mechanism that ensures axiom-core.elf integrity.

**Integration Note:** This section was integrated from ZKP Patch v1.5.0 on 2026-01-31.

## CRITICAL VALIDITY RULE (Read First)

> **THE AXIOM ZKP VALIDITY RULE (NORMATIVE)**
>
> A transaction is valid IF AND ONLY IF:
> 1. It contains exactly k WitnessSig structures (k ∈ {3,4,5})
> 2. Each WitnessSig contains a valid ExecutionProof
> 3. Each ExecutionProof was produced by a zk-VM running the CANONICAL axiom-core.elf (verified by program digest bound to proof, NOT public input)
> 4. Each ExecutionProof binds a UNIQUE (client_pk, epoch, nonce, consumed_state_id) tuple
> 5. **The wallet_seq equals prev_wallet_seq + 1 (verified and incremented by Core only)**
> 6. Each witness signature is computed over the zk-VM-produced commitment_hash
> 7. Each prev_receipt has verifiable availability (from overlap witnesses: 2 for k=3, 3 for k=4/5)
> 8. The chain of execution proofs traces back to GENESIS
>
> **OTHERWISE: ALL CONFORMANT NODES MUST REJECT.**
>
> There are no exceptions. There is no governance override. There is no emergency bypass.
> **There is no human intervention.**


## SYSTEM-WIDE REQUIREMENTS (Integration Note)

> **IMPORTANT FOR YELLOW PAPER INTEGRATION:**
> 
> When this patch is integrated into the Yellow Paper, the following requirements
> MUST be stated in the earliest sections (e.g., Section 1 or 2) as they apply
> to the ENTIRE AXIOM system, not just ZKP components.

### Mandatory Canonical JSON Serialization (RFC 8785 JCS)

**ALL serialization in AXIOM MUST use Canonical JSON. See LAMBDA_CANONICAL_JSON_BYTES.md.**

```
This applies to:
  - axiom-core.elf inputs and outputs
  - Lambda messages and state
  - Gateway communications
  - Client-Validator messages
  - Transaction payloads
  - Receipt structures
  - VBC bundles
  - ZKP public inputs and outputs
  - ALL persistent storage formats
  - ALL wire protocols
```

**Cross-reference:** `LAMBDA_CANONICAL_JSON_BYTES.md` for complete specification.
```
commitment_hash = H(public_inputs || public_outputs)

If serialization is non-deterministic:
  → Same logical data can produce different bytes
  → Different bytes = different hash
  → Signature verification fails
  → Or worse: equivalent data passes as different

CBOR's canonical form guarantees: same data = same bytes = same hash
```

#### AXIOM Canonical JSON Profile (NORMATIVE)

**AXIOM uses Canonical JSON (JCS profile) for ALL serialization.**

This section references and extends `LAMBDA_CANONICAL_JSON_BYTES.md`.

**Allowed Types (from LAMBDA_CANONICAL_JSON_BYTES.md):**
```
object  - Key-value map (keys must be strings, sorted by Unicode codepoint)
array   - Ordered list
string  - UTF-8 text, NFC normalized
int     - Signed integer (shortest decimal representation)
uint    - Unsigned integer
bool    - true or false
null    - Null value (use sparingly)
```

**Prohibited Types:**
```
float, double   - NOT ALLOWED (implementation-defined behavior)
NaN, Infinity   - NOT ALLOWED
Scientific notation - NOT ALLOWED
Locale-dependent formatting - NOT ALLOWED
```

**Binary Data Encoding:**
```
All binary data MUST use b64u: prefix (base64url, no padding)

Example:
  "signature": "b64u:MEUCIQDx7...",
  "public_key": "b64u:7Hy8K2mN...",
  "hash": "b64u:3q2-7w"
```

**Why No Floats:**
```
Floating-point has implementation-defined behavior:
  - NaN representations vary
  - Infinity handling varies
  - Rounding modes vary
  - Subnormal handling varies

AXIOM uses ONLY integers:
  - Balances: integer atoms (smallest unit)
  - Timestamps: integer epoch seconds
  - Sequences: integer counters
  - No floating-point anywhere in the protocol
```

**Canonical Bytes (CB) Framing:**
```
CB := MAGIC(4) || CB_VERSION(1) || CODEC(1) || LEN(varint) || PAYLOAD || CRC32C(4)

MAGIC      = 0x4C 0x41 0x4D 0x42 (ASCII "LAMB")
CB_VERSION = 0x01 (current version)
CODEC      = 0x01 (Canonical JSON)
LEN        = LEB128 varint (payload length)
PAYLOAD    = UTF-8 Canonical JSON bytes
CRC32C     = checksum for corruption detection
```

**Structural Limits:**
```
MAX_NESTING_DEPTH = 16
MAX_STRING_LENGTH = 1 MB
MAX_ARRAY_LENGTH = 10,000 elements
MAX_MAP_SIZE = 1,000 entries
MAX_INTEGER = 2^64 - 1 (unsigned)
MAX_WALLET_SEQ = 2^48
```

**axiom-core.elf JSON Validation:**
```
axiom-core.elf MUST validate all JSON inputs:
  - Reject prohibited types (floats, etc.)
  - Reject non-canonical encodings (whitespace, wrong key order)
  - Reject exceeding structural limits
  - Reject malformed JSON
  - Verify NFC normalization on strings
  - Verify b64u: prefix on binary fields

Invalid JSON → REJECT (E_INVALID_JSON)
```

**Cross-Reference:** See `LAMBDA_CANONICAL_JSON_BYTES.md` for complete specification.

### Mandatory Quantum-Safe Cryptography for VBCs

**ALL Validator Birth Certificates MUST use quantum-resistant signatures.**

```
Required algorithm: Dilithium (FIPS 204)
  - ALL Genesis Validators: Dilithium
  - ALL VBC issuance signatures: Dilithium
  - ALL VBC renewal signatures: Dilithium
  - ALL regular Validators: Dilithium

Optional (paranoid mode): SPHINCS+ (FIPS 205)
  - Validators MAY choose SPHINCS+ instead of Dilithium
  - SPHINCS+ has larger signatures but hash-only security assumption
```

**Why Dilithium as default (not SPHINCS+):**

| Factor | Dilithium | SPHINCS+ |
|--------|-----------|----------|
| Signature size | ~2.4 KB | ~8-50 KB |
| Speed | Fast | Slower |
| Email transport | ✓ Fits easily | May hit size limits |
| Security basis | Lattice problems | Hash functions |
| NIST standard | FIPS 204 | FIPS 205 |
| Industry adoption | Google, Cloudflare, Signal | Less common |

**Ed25519 is NOT permitted for VBCs:**
```
Ed25519 will be broken by quantum computers.
VBCs are long-lived (up to 3 years).
Quantum computers may arrive within that timeframe.
Therefore: ALL VBCs must be quantum-safe from day one.
```

**Ed25519 permitted for:**
```
- Transaction signatures (short-lived, can upgrade)
- Session keys (ephemeral)
- Non-critical operations
```


## Core Logic Architecture (NORMATIVE)

### axiom-core.elf: Single Binary, Four Modes

**axiom-core.elf is ONE immutable binary with ONE fingerprint, executing in FOUR different modes.**

All axiom-core.elf executions happen inside DMAP-VM/zk-VM. There is no "ordinary execution" of axiom-core.elf outside of DMAP-VM/zk-VM.

#### The Four Core Logic Modes

| Mode | Name | Location | Purpose |
|------|------|----------|---------|
| **CL1** | Client Core Out | Client (sending) | Validate outgoing transaction, produce proof |
| **CL2** | Validator Core In | Validator (receiving) | Verify incoming proof, validate transaction |
| **CL3** | Validator Core Out | Validator (after Lambda) | Verify Lambda's processing, produce witness proof |
| **CL4** | Client Core In | Client (receiving) | Verify incoming receipt/response |

#### Transaction Flow: CL1 → CL2 → CL3 → CL4

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPLETE TRANSACTION FLOW                        │
└─────────────────────────────────────────────────────────────────────┘

Client Wallet (creates transaction)
       │
       ▼
[CL1] Client axiom-core.elf (DMAP-VM/zk-VM)
       │  - Validate own transaction is legal
       │  - Produce proof
       ▼
Gateway (transmit transaction + proof)
       │
       ▼
[CL2] Validator axiom-core.elf (DMAP-VM/zk-VM)
       │  - Verify client's proof (CL1 output)
       │  - Validate transaction
       │  - If overlap: strip wallet_seq/balance for Lambda to refill
       ▼
Validator Lambda (ordinary execution - NOT in DMAP-VM/zk-VM)
       │  - Fill in wallet_seq/balance (if overlap)
       │  - Sign transaction
       │  - Record to database
       │  - Coordinate k=3 witnesses
       │  - Prepare receipt
       ▼
[CL3] Validator axiom-core.elf (DMAP-VM/zk-VM)
       │  - Verify Lambda's processing is legal
       │  - Verify refilled hash matches (Hash_A == Hash_B)
       │  - Produce final witness proof
       ▼
Gateway (return receipt + proof)
       │
       ▼
[CL4] Client axiom-core.elf (DMAP-VM/zk-VM)
       │  - Verify receipt's proofs
       ▼
Client Wallet (store receipt)
```

#### Extended Flow with ACK and Cheque

```
=== Send Transaction ===
Sender CL1 → Validator CL2 → Lambda → Validator CL3 → Sender CL4

=== Send ACK (contains process fee signature) ===
Sender CL1 → Validator CL2

=== Send Cheque to Receiver ===
Validator CL3 → Receiver CL4

=== Receiver ACK ===
Receiver CL1 → Validator CL2
```

**Pattern:** 
- Sending money: CL1 → CL2 → CL3 → CL4 → CL1 → CL2 → CL3 → CL4
- Receiving money/cheque: CL3 → CL4 → CL1

#### Key Invariants

```
1. SAME BINARY: All four modes use the SAME axiom-core.elf binary
   - Same fingerprint
   - Same validation logic
   - No "different versions" for different modes

2. ALWAYS IN DMAP-VM/zk-VM: axiom-core.elf NEVER executes outside DMAP-VM/zk-VM
   - No "ordinary execution" mode
   - Every execution produces proof
   - No exceptions

3. LAMBDA IS SANDWICHED: Lambda always runs between CL2 and CL3
   - CL2 validates input to Lambda
   - CL3 validates output from Lambda
   - Lambda cannot cheat because Core checks both sides

4. SEQUENTIAL ORDER: Modes always execute in order 1 → 2 → 3 → 4
   - Cannot skip modes
   - Cannot reorder modes
   - Each mode's proof references previous mode's proof
```

#### axiom-core.elf vs Lambda Responsibilities

| Aspect | axiom-core.elf (CL1-4) | Lambda |
|--------|------------------|--------|
| **Execution Environment** | DMAP-VM/zk-VM (always) | Ordinary execution |
| **Produces Proof** | Yes (every execution) | No |
| **Validates Transactions** | Yes | No |
| **Validates Proofs** | Yes | No |
| **Accesses Database** | No | Yes |
| **Coordinates Witnesses** | No | Yes |
| **Signs Receipts** | No | Yes |
| **Handles JFP** | No | Yes |
| **Can Be Bypassed** | NEVER | N/A (not security-critical) |

#### S-ABR and CL2/CL3 Interaction

```
S-ABR (Sequential Asymmetric Blind Refill) works through CL2 and CL3:

CL2 (Core In):
  - Receives transaction with balance
  - Computes Hash_A = hash(transaction_with_balance)
  - If overlap validator: strips wallet_seq and balance
  - Passes stripped transaction to Lambda

Lambda:
  - Retrieves wallet_seq and balance from database
  - Refills the stripped fields
  - Passes refilled transaction to CL3

CL3 (Core Out):
  - Receives refilled transaction
  - Computes Hash_B = hash(refilled_transaction)
  - Verifies: Hash_A == Hash_B
  - If mismatch: REJECT (someone lied about balance)
  - If match: produce witness proof
```


## Design Principles

### Incentive → Expectation → Hard Rules

**AXIOM's design philosophy prioritizes incentive alignment over enforcement.**

```
1. INCENTIVE FIRST
   Make doing the right thing beneficial.
   Make doing the wrong thing unprofitable.
   → Behavior naturally aligns.

2. EXPECTATION SECOND
   Based on incentives, expect participants to act correctly.
   If they don't? They bear the consequences.
   → No enforcement needed.

3. HARD RULES LAST
   Only when incentive and expectation fail,
   use rules that cannot be bypassed.
   → axiom-core.elf validation is this layer.
```

**Example: ACK Mechanism**

| Layer | Design |
|-------|--------|
| **Incentive** | Client sends ACK → Validator can collect fee. Client doesn't send ACK → Client's wallet may get stuck. |
| **Expectation** | Validator will process transaction because they want fee. Client will send ACK because they don't want to be stuck. |
| **Hard Rules** | axiom-core.elf validates signatures, balances, worldlines (cannot be bypassed). |

**Why This Order?**

```
Incentive handles 99% of cases → Low cost, natural operation
Expectation handles edge cases → Consequences are self-inflicted
Hard Rules handle "must never fail" → axiom-core.elf guarantees

No monitoring needed. No arbitration needed. No punishment needed.
The system aligns itself.
```

### No Human Intervention

**AXIOM's highest principle:** The system operates without human intervention.

- No manual review of transactions
- No manual approval of state changes
- No manual resolution of disputes
- No governance votes to override protocol rules
- No "admin keys" or "emergency powers"

**If the protocol cannot automatically resolve a situation, the affected assets are frozen (fail-stop), not manually rescued.**

### Fail-Stop Security Model

**"Can crash, must not lie."**

When faced with uncertainty or missing data:
- **DO:** Halt, freeze, reject
- **DO NOT:** Guess, approximate, or trust external input

Data unavailable? → Transaction blocked (money frozen)
Proof invalid? → Transaction rejected
State inconsistent? → Fail-stop

### Fail-Stop Scope and Liveness

**CRITICAL CLARIFICATION:** Fail-stop applies to INDIVIDUAL transactions, not the entire network.

```
AXIOM is NOT a blockchain with global state consensus.

Each wallet has its own state chain.
Each transaction only needs k=3 validators.
If one wallet's overlap witness is offline:
  → ONLY that wallet is frozen
  → Other wallets continue with full k=3 witnessing and redeem capability, unaffected by the frozen wallet.
  → Network as a whole remains live

There is no "global halt" scenario from validator unavailability.
```

**Liveness Properties:**
| Scenario | Effect |
|----------|--------|
| 1 validator offline | No impact (k=3 still achievable from others) |
| 3 validators offline | Wallets using those specific validators may freeze |
| 50% validators offline | Reduced capacity, but network continues |
| ALL validators offline | Network halted, but this is catastrophic failure mode |

### Recovery Mode (Reference)

For catastrophic scenarios where significant portions of the network are frozen due to data unavailability, AXIOM provides a **Recovery Mode** mechanism.

**Recovery Mode is defined in §26.6.8 and the White Paper (Ark-Mode / Recovery sections).**

Key properties:
- Automatic activation based on network health metrics
- No human intervention required
- Preserves "can crash, must not lie" principle
- Details outside scope of this ZKP patch

### Worldline Semantics (IMPORTANT)

**AXIOM is NOT a single-chain system. Wallet forks are EXPECTED BEHAVIOR.**

```
AXIOM's security claim is POLLUTION ISOLATION, not SINGLE CANONICAL HEAD.

What this means:
  - The same wallet CAN have multiple forked worldlines
  - Each worldline has valid ZKP proofs and witness signatures
  - Forked worldlines do NOT contaminate each other
  - Each worldline is internally consistent
```

#### Wallet Fork Scenario (Expected Behavior)

```
Wallet W has state chain: S0 → S1 → S2

Owner submits different transactions to different validator sets:
  - To V-set A: TX3a (consumes S2 → S3a)
  - To V-set B: TX3b (consumes S2 → S3b)

Result:
  - Worldline A: S0 → S1 → S2 → S3a (valid)
  - Worldline B: S0 → S1 → S2 → S3b (valid)

Both worldlines:
  - Have valid ZKP proofs
  - Have valid witness signatures
  - Are internally consistent
  - Cannot contaminate each other
```

#### Why This Is NOT Double-Spend

```
Double-spend would be: spending S2 twice in the SAME worldline.
This is PREVENTED by state_id consumption + wallet_seq.

Wallet fork is: spending S2 in DIFFERENT worldlines.
This is ALLOWED because worldlines are independent.

The recipient in worldline A cannot use that money in worldline B.
The recipient in worldline B cannot use that money in worldline A.
No value is created or destroyed - it exists in parallel realities.
```

#### Economic Impact of Forks and Frozen Wallets

```
When a wallet forks:
  - AXC in one worldline is not accessible in another
  - This effectively "reduces" circulating supply in each worldline

When a wallet is frozen (fail-stop):
  - AXC in that wallet is not accessible
  - This also "reduces" circulating supply

Economic impact is MINIMAL because:
  - 1 AXC = 10^10 atoms (extremely divisible)
  - "Reduced supply" → each remaining atom is worth more
  - This is deflation, not loss of value
  - Economic growth accommodated by increased precision
  - Similar to Bitcoin's lost coins

Frozen AXC is frozen VALUE, not destroyed value.
If/when Recovery Mode activates, value can be restored.
```

#### Worldline Identification (Client/UX Responsibility)

```
The protocol does NOT determine which worldline is "correct."
This is a CLIENT/UX responsibility:

Clients SHOULD:
  - Track which validators they trust
  - Track which worldline they operate in
  - Verify receipts against their trusted validator set
  - Reject receipts from untrusted worldlines

The protocol provides:
  - Receipts with validator signatures
  - ZKP proofs of execution
  - State chain integrity

The protocol does NOT provide:
  - "Official" worldline designation
  - Global consensus on wallet state
  - Automatic worldline selection

This is by design - global consensus would require coordination
that violates "no human intervention" and creates governance attack surface.
```


## Problem Statement

### The Core Bypass Vulnerability

Prior to this patch, AXIOM's security model had a fundamental vulnerability:

**Threat Scenario:**
```
Malicious Validator Operator controls:
  - Lambda (consensus logic)
  - Gateway (transport)
  - Underlying hardware

Attack Vector:
  1. Operator bypasses axiom-core.elf entirely
  2. Lambda signs transactions without validation
  3. No balance check, no double-spend check, no VBC verification
  4. Invalid transactions receive valid-looking witness signatures
```

**Core Insight:** No cryptographic mechanism existed to prove "axiom-core.elf actually executed the validation logic."


## Solution: ZKP Execution Attestation

### 26.1 Overview

Every axiom-core.elf execution MUST produce a **Zero-Knowledge Proof (ZKP)** that attests:

1. The specific axiom-core.elf binary executed (bound by program digest)
2. The exact input (payload) that was processed
3. The validation logic was fully executed
4. The output (accept/reject) matches the execution
5. A unique (epoch, nonce) prevents proof replay

This proof is:
- **Unforgeable:** Cannot be created without actual Core execution
- **Verifiable:** Any party can verify the proof is valid (offline, no network)
- **Binding:** Proof is cryptographically bound to specific program, input, output, AND nonce
- **Non-replayable:** Each proof is unique to one transaction

### 26.2 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Validator Node                          │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐   │
│   │              ZKP Virtual Machine (zk-VM)              │   │
│   │                                                      │   │
│   │   ┌─────────────────────────────────────────────┐   │   │
│   │   │              axiom-core.elf                        │   │   │
│   │   │                                              │   │   │
│   │   │   - Balance verification                    │   │   │
│   │   │   - Double-spend prevention                 │   │   │
│   │   │   - VBC verification                        │   │   │
│   │   │   - S-ABR validation                        │   │   │
│   │   │   - prev_receipts ZKP verification          │   │   │
│   │   │   - Nonce uniqueness check (per epoch)      │   │   │
│   │   │                                              │   │   │
│   │   └─────────────────────────────────────────────┘   │   │
│   │                         │                            │   │
│   │   Program Digest ───────┼─────→ Bound to Proof      │   │
│   │   (HARDCODED)           │       (NOT an input)       │   │
│   │                         ▼                            │   │
│   │              Execution Proof (ZKP)                   │   │
│   │                                                      │   │
│   └─────────────────────────────────────────────────────┘   │
│                             │                               │
│                             ▼                               │
│                      Lambda + Gateway                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 26.3 Program Digest Specification (CRITICAL)

#### 26.3.1 Definition

The **program digest** is a cryptographic commitment to the exact binary code being executed inside the zk-VM.

**NORMATIVE SPECIFICATION:**
```
program_digest = SHA3-256(entire_elf_binary)

Where entire_elf_binary includes:
  - ELF header
  - All program headers
  - All section headers
  - .text segment (code)
  - .rodata segment (read-only data)
  - .data segment (initialized data)
  - .bss segment (uninitialized data)
  - All other segments present in the binary

The hash is computed over the COMPLETE file, byte-for-byte.
No segments are excluded.
No preprocessing or normalization is applied.
```

#### 26.3.2 Why Complete Binary Hash

**Attack Prevention:**
```
If only .text (code) is hashed:
  → Attacker modifies .rodata (e.g., changes validation constants)
  → Code is same, data is different
  → Same digest, different behavior

If only entry point is hashed:
  → Attacker adds malicious code elsewhere
  → Entry point unchanged
  → Same digest, different behavior

By hashing the COMPLETE binary:
  → ANY change produces different digest
  → No way to modify behavior without changing digest
```

#### 26.3.3 Program Digest is NOT a Public Input

**WRONG (Vulnerable):**
```rust
struct PublicInputs {
    core_fingerprint: [u8; 32],  // WRONG: Attacker chooses this
}
```

**CORRECT (Secure):**
```
The program digest is INHERENT to the zk-VM proof.
It is computed BY the zk-VM FROM the actual executing program.
It CANNOT be chosen or modified by the prover.
Verifiers extract the digest FROM the proof structure.
```

#### 26.3.4 Canonical Program Digest Registry

```rust
/// Canonical axiom-core.elf Program Digests
/// HARDCODED - No governance can modify this list
pub const CANONICAL_CORE_DIGESTS: &[[u8; 32]] = &[
    // axiom-core.elf v1.0.0 - Genesis version
    [0x1a, 0x2b, /* ... 32 bytes ... */],
    
    // Future versions added ONLY via axiom-core.elf software release
];
```

**INVARIANT:** There is NO mechanism to add program digests except releasing a new axiom-core.elf version.

### 26.4 ZKP Proof Structure

```rust
struct ExecutionProof {
    /// ZKP proof bytes (STARK/SNARK)
    proof_bytes: Vec<u8>,
    
    /// Public inputs (visible to verifiers)
    public_inputs: PublicInputs,
    
    /// Public outputs (visible to verifiers)
    public_outputs: PublicOutputs,
    
    /// Commitment hash (computed inside zk-VM, signed by validator)
    commitment_hash: [u8; 32],
    
    // NOTE: program_digest is extracted FROM proof_bytes, not stored here
}

struct PublicInputs {
    /// Hash of the transaction payload (Canonical Bytes)
    payload_hash: [u8; 32],
    
    /// Client's public key
    client_pk: [u8; 32],
    
    /// Client's signature over payload
    client_sig: [u8; 64],
    
    /// Hash of previous receipts
    prev_receipts_hash: [u8; 32],
    
    /// Epoch number (for nonce scoping)
    epoch: u64,
    
    /// Nonce (unique within epoch for this client)
    nonce: u64,
    
    /// State ID being consumed
    consumed_state_id: [u8; 32],
    
    /// Wallet sequence number (filled by Validator from prev_receipts)
    /// Core verifies: wallet_seq == prev_wallet_seq + 1
    wallet_seq: u64,
}

struct PublicOutputs {
    /// Validation result
    result: ValidationResult,  // Accept or Reject
    
    /// New state hash (if accepted)
    new_state_hash: Option<[u8; 32]>,
    
    /// New state ID produced (if accepted)
    produced_state_id: Option<[u8; 32]>,
    
    /// New wallet sequence (if accepted) - set by Core = wallet_seq (input)
    new_wallet_seq: Option<u64>,
    
    /// Rejection reason (if rejected)
    rejection_reason: Option<ValidationError>,
}
```

#### 26.4.1 Commitment Hash Computation (NORMATIVE)

**The commitment_hash MUST be computed as follows:**

```rust
fn compute_commitment_hash(
    public_inputs: &PublicInputs,
    public_outputs: &PublicOutputs,
) -> [u8; 32] {
    let mut hasher = Sha3_256::new();
    
    // Length prefix for each field (prevents extension attacks)
    // LENGTH IS ALWAYS FIXED u64 LITTLE-ENDIAN (8 bytes)
    // NOT variable-length CBOR integer encoding
    fn hash_field(hasher: &mut Sha3_256, data: &[u8]) {
        hasher.update(&(data.len() as u64).to_le_bytes()); // Fixed 8 bytes, LE
        hasher.update(data);
    }
    
    // Hash all public inputs with length prefixes
    hash_field(&mut hasher, &public_inputs.payload_hash);
    hash_field(&mut hasher, &public_inputs.client_pk);
    hash_field(&mut hasher, &public_inputs.client_sig);
    hash_field(&mut hasher, &public_inputs.prev_receipts_hash);
    hash_field(&mut hasher, &public_inputs.epoch.to_le_bytes());
    hash_field(&mut hasher, &public_inputs.nonce.to_le_bytes());
    hash_field(&mut hasher, &public_inputs.consumed_state_id);
    hash_field(&mut hasher, &public_inputs.wallet_seq.to_le_bytes());
    
    // Hash all public outputs with length prefixes
    hash_field(&mut hasher, &[public_outputs.result as u8]);
    if let Some(ref state_hash) = public_outputs.new_state_hash {
        hash_field(&mut hasher, &[1u8]); // Present marker
        hash_field(&mut hasher, state_hash);
    } else {
        hash_field(&mut hasher, &[0u8]); // Absent marker
    }
    if let Some(ref state_id) = public_outputs.produced_state_id {
        hash_field(&mut hasher, &[1u8]);
        hash_field(&mut hasher, state_id);
    } else {
        hash_field(&mut hasher, &[0u8]);
    }
    if let Some(seq) = public_outputs.new_wallet_seq {
        hash_field(&mut hasher, &[1u8]);
        hash_field(&mut hasher, &seq.to_le_bytes());
    } else {
        hash_field(&mut hasher, &[0u8]);
    }
    
    hasher.finalize().into()
}
```

**Length Prefix Specification:**
```
Length is ALWAYS encoded as:
  - Fixed 8 bytes (u64)
  - Little-endian byte order
  - NOT variable-length CBOR integer

This ensures:
  - Deterministic encoding (no ambiguity)
  - Same length = same bytes (always)
  - Simple implementation
```

**Why Length Prefixes:**
- Prevents length extension attacks
- Ensures unambiguous parsing
- Different inputs cannot produce same hash via concatenation tricks

### 26.5 Epoch-Based Nonce System

#### 26.5.1 Problem with Global Nonce Registry

A global registry of all (client_pk, nonce) pairs would grow unboundedly:
- Billions of transactions = billions of entries
- Memory/storage exhaustion
- Query performance degradation

#### 26.5.2 Solution: Epoch Scoping

```
Nonces are scoped to epochs.
An epoch is a time window (e.g., 24 hours).
Nonces only need to be unique WITHIN an epoch.
After epoch expires, nonce registry for that epoch can be pruned.
```

**Epoch Derivation (NORMATIVE):**
```rust
const BLOCKS_PER_EPOCH: u64 = 1000;  // Configurable

/// Epoch MUST be derived from consumed_state_id ONLY
/// NOT from local observations, NOT from wall clock
fn derive_epoch(consumed_state_id: &StateId) -> u64 {
    // Get the height/sequence from the state being consumed
    let state_height = consumed_state_id.height;
    state_height / BLOCKS_PER_EPOCH
}
```

**Why Epoch Must Derive from consumed_state_id:**
```
PROBLEM with other approaches:

If epoch = f(wall_clock):
  → Different validators have different clocks
  → Same transaction may be valid/invalid depending on validator
  → Network disagreement

If epoch = f(local_chain_observation):
  → Different validators see different chain states
  → Same transaction may map to different epochs
  → Network disagreement

SOLUTION:

epoch = f(consumed_state_id)
  → All validators derive epoch from the SAME input
  → consumed_state_id is in the transaction
  → Deterministic, no disagreement possible
```

**Epoch from State Height:**
```
Every state_id includes a logical height (sequence number in wallet chain).
Genesis state has height 0.
Each transaction increments height by 1.

epoch = consumed_state_id.height / BLOCKS_PER_EPOCH

This is:
  - Deterministic (same input = same output)
  - Verifiable (validators can check)
  - Independent of wall clock
  - Independent of local observations
```

#### 26.5.3 Nonce Rules (NORMATIVE)

**Rule 1: Epoch-Scoped Uniqueness**
```
The tuple (client_pk, epoch, nonce) MUST be unique.
A nonce can be reused in DIFFERENT epochs.
A nonce CANNOT be reused in the SAME epoch.
```

**Rule 2: Epoch Validity Window**
```
Transaction with epoch E is valid only if:
  current_epoch - MAX_EPOCH_DRIFT <= E <= current_epoch + 1

MAX_EPOCH_DRIFT = 2 (allows ~48 hours of clock drift)
```

**Rule 3: Registry Pruning**
```
Nonce registries for epochs older than (current_epoch - MAX_EPOCH_DRIFT - 1)
MAY be pruned. Such old transactions would be rejected anyway.
```

#### 26.5.4 Storage Analysis

```
Per-epoch storage:
  - Active clients in epoch: ~100,000
  - Nonces per client per epoch: ~10
  - Entry size: 40 bytes (client_pk + nonce)
  - Per-epoch storage: ~40 MB

With MAX_EPOCH_DRIFT = 2:
  - Max epochs to store: 4
  - Max storage: ~160 MB

This is bounded and manageable.
```

### 26.5.5 Wallet Sequence Number (wallet_seq)

#### Purpose

The `wallet_seq` serves two critical purposes:

1. **Concurrency Control:** Prevents parallel-proof double-spend attacks
2. **Core Bypass Prevention:** Provides additional proof that Core actually executed

#### How wallet_seq Works

```
wallet_seq follows the same pattern as balance verification:

1. Client submits transaction (does NOT know current wallet_seq)
2. Validator extracts prev_wallet_seq from prev_receipts
3. Validator fills in wallet_seq = prev_wallet_seq + 1
4. Core receives wallet_seq as input
5. Core verifies: wallet_seq == prev_wallet_seq + 1
6. If valid, Core outputs new_wallet_seq = wallet_seq
7. new_wallet_seq is hashed into new_state
```

#### Concurrency Prevention

```
Scenario: Parallel-proof double-spend attempt

TX_A and TX_B both try to spend the same state (wallet_seq = 5)

Without wallet_seq:
  - Both could get valid ZKP proofs (race condition)
  - Both proofs are "valid" at the moment of execution

With wallet_seq:
  - TX_A: wallet_seq = 6 (prev was 5)
  - TX_B: wallet_seq = 6 (prev was 5)
  - Both get valid proofs with wallet_seq = 6
  - BUT: When TX_A completes, new_wallet_seq = 6
  - TX_B's proof claims prev_wallet_seq = 5, but state now shows 6
  - TX_B is REJECTED because prev_wallet_seq doesn't match current state

The first transaction to complete "wins" - the second is invalidated.
```

#### Core Bypass Prevention

```
Why wallet_seq proves Core executed:

1. ONLY Core can verify wallet_seq == prev_wallet_seq + 1
2. ONLY Core can output new_wallet_seq
3. new_wallet_seq is included in commitment_hash
4. Validator signs commitment_hash

If Lambda tries to bypass Core:
  - Lambda doesn't know what new_wallet_seq should be
  - Lambda could guess, but it would be wrong
  - Wrong wallet_seq → hash mismatch → invalid proof
  
This is an ADDITIONAL layer of Core bypass prevention on top of ZKP.
```

#### wallet_seq Rules (NORMATIVE)

**Rule 1: Genesis Initialization**
```
When a wallet is created (Genesis):
  wallet_seq = 0

First transaction from that wallet:
  wallet_seq MUST be 1 (forced, no exception)
  
Core validates: wallet_seq == 1 for first transaction
No prev_receipts needed for this check (Genesis case)
```

**Rule 2: Monotonic Increment**
```
For each subsequent transaction:
  wallet_seq (input) == prev_wallet_seq + 1

If prev_wallet_seq = 5, then wallet_seq MUST be 6.
```

**Rule 3: Integer Only with Maximum**
```
wallet_seq is ALWAYS an unsigned integer.
No floating-point. No fractional values.
Type: u64 (0 to 2^64-1)

MAXIMUM VALUE: 2^48 (281,474,976,710,656)

If wallet_seq >= 2^48:
  → Transaction is REJECTED (E_WALLET_SEQ_OVERFLOW)
  → Wallet is effectively frozen
  → This indicates attack or extreme anomaly
  → Normal usage cannot reach this limit (would take thousands of years)
```

**Rule 4: Core-Only Modification**
```
ONLY Core can:
  - Verify wallet_seq correctness
  - Output new_wallet_seq
  
Lambda/Gateway can:
  - Read prev_wallet_seq from prev_receipts
  - Fill in wallet_seq = prev_wallet_seq + 1
  - But CANNOT verify or modify the output
```

**Rule 5: Binding to State**
```
new_wallet_seq is included in:
  - public_outputs
  - new_state_hash
  - commitment_hash

Any tampering invalidates the entire proof chain.
```

### 26.6 Data Availability (Reliability Design)

#### 26.6.1 Design Philosophy

**Data Availability in AXIOM is a RELIABILITY mechanism, not a security mechanism.**

```
Security (handled by ZKP + wallet_seq):
  - Cannot create money from nothing
  - Cannot double-spend
  - Cannot bypass Core validation

Reliability (handled by DA):
  - Ensures transaction data remains accessible
  - Handles hardware failures, network issues
  - NOT designed to prevent malicious deletion
```

**Rationale:**
- Validators are economically incentivized to provide data (they want to earn fees)
- Malicious deletion hurts the validator's reputation and business
- The system protects against accidents, not intentional sabotage
- Intentional sabotage is handled by validator diversity and Recovery Mode

#### 26.6.2 Overlap Witness Requirements

The overlap witness rule provides data availability redundancy:

```
k=3: Requires 2 overlap witnesses
k=4: Requires 3 overlap witnesses  
k=5: Requires 3 overlap witnesses

To cause data unavailability (wallet freeze):
  - k=3: ALL 2 overlap witnesses must fail to provide data
  - k=4/5: ALL 3 overlap witnesses must fail to provide data
```

**This is significant redundancy:**
- Multiple independent validators must ALL fail
- Accidental failure of all overlap witnesses is unlikely
- Recovery Mode handles catastrophic scenarios

#### 26.6.3 Principle: No Challenge, No Slashing

**AXIOM does not use challenge-response or slashing for data availability.**

Instead, it uses **fail-stop**:
- Data unavailable → Transaction cannot proceed
- Money is frozen until data becomes available
- No manual intervention to "rescue" frozen funds
- No punishment mechanism (slashing) for validators

**Rationale:**
- Challenge systems require timing assumptions
- Slashing requires governance or dispute resolution
- Both violate "no human intervention" principle
- Fail-stop is simpler and more robust

#### 26.6.4 Availability via Overlap Witnesses

The **overlap witness rule** (Yellow Paper Section 17.3) provides data availability:

```
TX_n requires at least 1 witness from TX_{n-1}

This overlap witness:
  - Participated in TX_{n-1}
  - Therefore HAS the data for TX_{n-1}
  - Can provide it for TX_n verification
```

**Data Availability Chain:**
```
TX_1: witnesses [V1, V2, V3]
  ↓
TX_2: witnesses [V1, V4, V5]  ← V1 has TX_1 data
  ↓
TX_3: witnesses [V4, V6, V7]  ← V4 has TX_2 data (and indirectly TX_1)
  ↓
...
```

#### 26.6.5 Availability Attestation (Simplified)

```rust
struct AvailabilityAttestation {
    /// Hash of the transaction data
    data_hash: [u8; 32],
    
    /// Overlap witness who holds the data
    witness_pk: [u8; 32],
    
    /// Signature: "I am overlap witness and hold this data"
    signature: [u8; 64],
}
```

**Verification:**
```
1. Check: Is witness_pk in prev_transaction's witness set?
2. Check: Is signature valid?
3. If both yes: Data availability is attested
4. To actually get data: Request from witness_pk
```

#### 26.6.6 What Happens If Data Unavailable

```
Scenario: All overlap witnesses fail to provide data

Result:
  - Transaction is BLOCKED (not rejected)
  - The money in that state is FROZEN
  - No automatic resolution in normal mode
  
Recovery options:
  1. Wait for overlap witness to come back online
  2. Recovery Mode (see White Paper)
  3. Meta Validator as backup source (optional)
```

#### 26.6.7 Meta Validator as Optional Backup

**Validators MAY push transaction data to their Meta Validator as backup.**

```
This is RECOMMENDED but not REQUIRED:
  - Meta Validator can serve as archive
  - If overlap witness fails, Meta Validator may have the data
  - Client can request data from Meta Validator

This is NOT a protocol requirement because:
  - Validators who want to earn money will naturally provide good service
  - Forcing backup would add complexity without proportional benefit
  - The system is designed for reliability, not adversarial resistance
```

#### 26.6.8 Recovery Mode Reference

For catastrophic scenarios where multiple overlap witnesses are unavailable:

**Recovery Mode is defined in the White Paper (Ark-Mode / Recovery sections).**

Key properties:
- Automatic activation based on network health metrics
- No human intervention required
- Preserves "can crash, must not lie" principle
- Allows frozen wallets to recover when conditions improve

**Recovery Mode Security Invariants (NORMATIVE):**
```
Recovery Mode does NOT relax any security invariants:

STILL REQUIRED in Recovery Mode:
  ✓ Valid ZKP proofs for all transactions
  ✓ wallet_seq must be monotonically increasing
  ✓ state_id can only be consumed once
  ✓ CBOR serialization must be canonical
  ✓ VBC signatures must be valid Dilithium
  ✓ Program digest must be in CANONICAL_CORE_DIGESTS

Recovery Mode MAY change:
  - Liveness parameters (timeouts, retry intervals)
  - DA source selection (alternative sources)
  - Network topology preferences

Recovery Mode MUST NOT:
  - Skip ZKP verification
  - Allow wallet_seq gaps
  - Allow state_id reuse
  - Accept non-canonical CBOR
  - Bypass VBC validation
```

**If Recovery Mode Cannot Help:**
```
Worst case: wallet remains frozen forever.
This is acceptable because:
  - Money is frozen, not stolen
  - "Can crash, must not lie" is preserved
  - Better frozen than fraudulent
```

**Current Status:**
```
Recovery Mode is NOT a priority for v1.0.
The system can operate without Recovery Mode.
Worst case = frozen wallets (fail-stop).
Recovery Mode will be defined in future versions.
```

#### 26.6.9 Why This Is Acceptable

```
1. Overlap witness has economic incentive to cooperate
   - They want their OWN next transactions to proceed
   - Withholding data hurts themselves too

2. Attacker cost is high
   - Must control ALL validators in a chain to freeze funds
   - Overlap rule naturally introduces diversity over time

3. Frozen money is not stolen money
   - Owner still owns it (can't be spent by attacker)
   - May become available if witness comes back online
   - Worst case: money frozen, not lost
```

### 26.7 Replay Prevention

#### 26.7.1 Three-Layer Defense

**Layer 1: Epoch-Scoped Nonce**
```
(client_pk, epoch, nonce) must be unique within validity window
Provides efficient, bounded replay prevention
```

**Layer 2: State ID Consumption**
```
consumed_state_id can only be used ONCE ever
Creates strict ordering: each state leads to exactly one successor
Prevents parallel spends of same state
```

**Layer 3: Proof Binding**
```
ZKP proof cryptographically binds all inputs
Cannot reuse proof with different parameters
```

#### 26.7.2 Why Timestamps Are NOT Used

Timestamps are unreliable:
- Clock skew between nodes
- Offline/delayed transactions (email transport)
- Manipulation by attackers

AXIOM uses **logical ordering** (epochs, state chains) instead of wall-clock time.

### 26.8 Genesis Is ZKP-Enabled

#### 26.8.1 No Transition Period

**AXIOM launches with ZKP from day one.**

There is no:
- "Pre-ZKP era"
- "Transition period"
- "Activation protocol"
- "Clean state root migration"

Genesis itself is ZKP-enabled. The first transaction ever requires ZKP proof.

#### 26.8.2 Quantum-Safety Requirement for ALL VBCs

**ALL Validator Birth Certificates MUST use quantum-resistant signatures.**

This requirement applies to:
- Genesis Validators
- ALL VBC issuance signatures
- ALL VBC renewal signatures  
- ALL regular Validators

```
NORMATIVE:

Required Algorithm: Dilithium (FIPS 204)
  - Default for all VBCs
  - ~2.4 KB signatures (suitable for email transport)
  - Fast signing and verification
  - NIST standardized August 2024

Optional Algorithm: SPHINCS+ (FIPS 205)
  - "Paranoid mode" option
  - ~8-50 KB signatures (larger)
  - Hash-only security assumption (most conservative)
  - Validators MAY choose this instead of Dilithium

NOT Permitted: Ed25519
  - Quantum-vulnerable
  - NOT allowed for any VBC signatures
```

**Why ALL VBCs, not just Genesis:**
```
VBCs have up to 3-year validity.
Quantum computers may arrive within that timeframe.
If regular validators use Ed25519:
  → Quantum attacker breaks their keys
  → Forges VBC renewals
  → Injects fake validators
  
By requiring Dilithium for ALL VBCs:
  → Entire VBC tree is quantum-safe
  → No weak links in the trust chain
```

**Ed25519 Permitted For:**
```
- Transaction signatures (short-lived)
- Session keys (ephemeral)
- Non-VBC operations where quantum risk is acceptable
```

#### 26.8.3 VBC Identity Rule (NORMATIVE)

**One Valid VBC Per Validator Public Key**

```
Core MUST enforce:
  For any validator_pk, at most ONE VBC can be valid at any time.

This prevents:
  - Same validator appearing as multiple witnesses
  - Key reuse across VBC generations to inflate witness count
  - Sybil attacks via VBC duplication
```

**VBC Validity Check Timing:**
```
VBC validity is checked at VERIFICATION TIME, not signing time.

Verification uses EPOCH (logical time), not wall clock:
  - VBC has start_epoch and end_epoch
  - At verification, check: start_epoch <= current_epoch <= end_epoch
  - This avoids clock skew issues between validators

If VBC was valid when signed but expired at verification:
  - Transaction is REJECTED (E_VBC_EXPIRED)
  - Signer must obtain new witness signature from valid VBC holder
```

**Validation Rule:**
```rust
fn validate_witness_set(witnesses: &[WitnessSig]) -> Result<(), Error> {
    let mut seen_pks: HashSet<[u8; 32]> = HashSet::new();
    
    for witness in witnesses {
        // Check: no duplicate validator_pk in witness set
        if seen_pks.contains(&witness.validator_pk) {
            return Err(E_DUPLICATE_VALIDATOR);
        }
        seen_pks.insert(witness.validator_pk);
        
        // Check: validator has exactly one valid VBC
        let valid_vbcs = count_valid_vbcs(witness.validator_pk);
        if valid_vbcs != 1 {
            return Err(E_INVALID_VBC_COUNT);
        }
    }
    Ok(())
}
```

**VBC Renewal Handling:**
```
When validator renews VBC:
  - New VBC becomes valid at issuance time
  - Old VBC is NOT automatically invalidated
  - BUT: Core rejects any transaction where validator has >1 valid VBC
  
This means:
  - Validator MUST ensure old VBC expires before new VBC activates. Specifically, new VBC MUST have start_time >= old VBC expiry. Overlap period = validator cannot participate as witness.
```

**Why This Rule:**
```
Without this rule, attacker could:
  1. Get VBC_1 with key K
  2. Near expiry, get VBC_2 with same key K
  3. During overlap, claim to be "two different validators"
  4. Satisfy k=3 with only 2 actual validators + 1 duplicate

With this rule:
  - Core checks each validator_pk has exactly 1 valid VBC
  - Duplicate key = rejection
  - Must be k distinct validators
```

#### 26.8.4 VBC Expiry as Slow-Revocation Mechanism

**AXIOM intentionally has NO instant VBC revocation mechanism.**

**Why No Instant Revocation:**
```
Instant revocation would require:
  - A revocation list that all nodes must check
  - Consensus on revocation decisions
  - Potential for abuse (revoking honest validators)
  - Human intervention to decide what to revoke

All of these violate "no human intervention" principle.
```

#### 26.8.5 No Mid-Epoch VBC State Changes (NORMATIVE)

**VBC validity state CANNOT change within an epoch.**

```
AXIOM does NOT support:
  - Mid-epoch VBC revocation
  - Mid-epoch VBC invalidation
  - Real-time "blacklists" of validators
  - Any mechanism to instantly disable a VBC

Within a single epoch:
  - A VBC is either VALID or INVALID for the entire epoch
  - This is determined by: start_epoch <= current_epoch <= end_epoch
  - No external signal can change this mid-epoch
```

**Why This Is Safe:**
```
Concern: "What if a validator is caught being malicious mid-epoch?"

Answer:
  1. Malicious validator still must run canonical axiom-core.elf (ZKP enforced)
  2. They CANNOT create money or double-spend
  3. They CAN participate in witness sets - but this doesn't help them cheat
  4. Their VBC will eventually expire (≤3 years)
  5. Clients can choose to avoid validators with suspicious behavior

The damage a "malicious but ZKP-compliant" validator can do is LIMITED:
  - They can withhold DA → fail-stop (money frozen, not stolen)
  - They can refuse to sign → client uses different validators
  - They CANNOT forge transactions or steal money
```

**Contrast with Traditional Systems:**
```
Traditional systems with instant revocation:
  - Require consensus on "who is malicious" (governance)
  - Create attack vector: "revoke honest validators" (abuse)
  - Need real-time synchronization (complexity)
  - Introduce human judgment (violates AXIOM principles)

AXIOM's approach:
  - No judgment needed - VBCs simply expire
  - No consensus needed - expiry is deterministic
  - No real-time sync - epoch-based validity is local
  - No human intervention - automatic
```

#### 26.8.6 VBC Expiry as Slow-Revocation

```
If a Genesis Validator key is compromised:
  1. Attacker can issue malicious VBCs
  2. Those VBCs are valid for up to 3 years
  3. After 3 years, they expire and cannot be renewed
  4. The compromised Genesis key can be "abandoned" (never used again)
  
This is "slow revocation" - not instant, but effective over time.
```

**Security Analysis of Key Compromise:**
```
Scenario: 1 of 10 Genesis keys compromised (non-quantum attack)

Impact:
  - Attacker can issue VBCs for malicious validators
  - Malicious validators can participate in k=3 consensus
  - BUT: Malicious validators still must run canonical axiom-core.elf (ZKP enforced)
  - They CANNOT create money or double-spend
  - They CAN participate in witness sets

Mitigation:
  - Honest Genesis validators stop issuing VBCs from compromised key
  - Existing malicious VBCs expire in ≤3 years
  - New validators can avoid accepting witnesses with suspicious VBCs
  - Network gradually heals

Long-term:
  - 9 of 10 Genesis keys remain secure
  - 7/10 supermajority for JFP still achievable
  - System continues operating with reduced (but sufficient) trust
```

**Threshold Analysis:**
```
Genesis Validators: 10 total

For JFP (7/10 required):
  - Can tolerate up to 3 compromised Genesis keys
  - 4+ compromised = JFP becomes unreliable

For VBC issuance:
  - Any single Genesis can issue VBCs
  - Compromised Genesis can issue malicious VBCs
  - But malicious VBCs ≠ malicious transactions (ZKP protects)

Conclusion:
  - Single key compromise is containable
  - 4+ key compromise is catastrophic
  - Design assumes ≤3 Genesis keys can be compromised
```

#### 26.8.7 VBC Cartel Attack (Economic Analysis)

**Theoretical Attack: VBC Renewal Cartel**
```
Attack theory:
  1. Cartel controls >50% validators
  2. Cartel refuses VBC renewals for non-members
  3. Non-cartel validators expire after 3 years
  4. Cartel dominates network
```

**Why This Is Economically Impractical:**
```
For this attack to be worthwhile:
  - AXIOM must be valuable enough to attack
  - But if AXIOM is valuable, there will be many validators
  - Many validators = high cost to control >50%
  - High cost + 3-year timeline = enormous capital lockup

Economic reality:
  - Early network (few validators): Not worth attacking (low value)
  - Mature network (many validators): Too expensive to attack
  
The attack window where:
  - Network is valuable enough to attack AND
  - Network has few enough validators to control
  
...is extremely narrow or non-existent.
```

**Additional Barriers:**
```
VBC renewal requires 3 existing validators to sign.
Cartel must:
  - Already control enough validators to deny renewals
  - Maintain control for 3+ years (VBC expiry period)
  - Not be detected and avoided by users
  - Profit more than the cost of the attack

Even if cartel controls signing:
  - They still cannot forge transactions (ZKP)
  - They still cannot steal money (fail-stop)
  - They can only censor/freeze (reputational damage to themselves)
```

**Conclusion: Theoretical risk, economically impractical.**

#### 26.8.8 Genesis State

```rust
struct GenesisState {
    /// Initial account balances with their genesis state_ids
    initial_balances: Vec<GenesisWallet>,
    
    /// Genesis validators (hardcoded, quantum-resistant keys)
    genesis_validators: Vec<GenesisValidator>,
    
    /// The canonical axiom-core.elf digest for genesis
    genesis_core_digest: [u8; 32],
    
    /// Genesis epoch (epoch 0)
    genesis_epoch: u64,  // = 0
}

struct GenesisWallet {
    /// Wallet public key
    public_key: [u8; 32],
    
    /// Initial balance in atoms
    balance: u64,
    
    /// Genesis state_id for this wallet
    /// This is the consumed_state_id for the first transaction
    genesis_state_id: [u8; 32],
    
    /// Initial wallet_seq (always 0)
    wallet_seq: u64,  // = 0
}
```

**Genesis state_id:**
```
Every Genesis wallet has a unique genesis_state_id.

genesis_state_id = SHA3-256("AXIOM_GENESIS" || wallet_public_key || genesis_balance_le)

This state_id:
  - Is consumed by the wallet's first transaction
  - Prevents parallel first-transaction attacks
  - Provides the same double-spend protection as regular transactions
```

#### 26.8.9 First Transaction

The first transaction from any genesis account:
- MUST have valid ZKP proof
- MUST consume the wallet's genesis_state_id
- MUST reference genesis state as prev_state
- MUST use epoch 0 or 1
- MUST have k=3 witness signatures with ZKP proofs
- MUST have wallet_seq = 1 (forced)

**No exceptions. No grandfather clause.**

#### 26.8.10 Single-Input Transactions (NORMATIVE)

**Each transaction consumes exactly ONE state_id.**

```
AXIOM does NOT support multi-input transactions.

Each transaction:
  - Consumes exactly ONE consumed_state_id
  - Produces exactly ONE produced_state_id
  - Belongs to exactly ONE wallet

Multi-input (e.g., combining UTXOs) is NOT supported.
To consolidate funds, use multiple sequential transactions.
```

**Why Single-Input:**
```
1. Simplifies validation logic
2. Avoids complex atomic multi-state updates
3. Clear wallet_seq semantics (one wallet per tx)
4. Simpler DA (one chain of custody)
```

#### 26.8.11 prev_receipts Requirement (NORMATIVE)

**Empty prev_receipts is ONLY valid for Genesis transactions.**

```
Rule:
  IF transaction is Genesis (first tx from genesis wallet):
    prev_receipts MAY be empty
    wallet_seq MUST be 1
    
  ELSE (all other transactions):
    prev_receipts MUST NOT be empty
    prev_receipts.len() >= 1
    wallet_seq MUST equal prev_wallet_seq + 1
    
Core validation:
  if !is_genesis_transaction && prev_receipts.is_empty() {
      return Err(E_MISSING_PREV_RECEIPTS);
  }
```

**Why This Rule:**
```
prev_receipts provides:
  - Proof of previous balance (for spending)
  - Overlap witness for DA
  - Previous wallet_seq for monotonic check
  - Chain of custody back to Genesis

Without prev_receipts:
  - Cannot verify balance exists
  - Cannot verify wallet_seq
  - Cannot establish DA chain

Only Genesis wallets can skip this (they have no previous tx).
```

### 26.9 Witness Signature Structure

```rust
struct WitnessSig {
    /// Validator's unique identifier (BLAKE3 of SPHINCS+ public key)
    validator_id: [u8; 32],
    
    /// Validator's public key (Ed25519, 32 bytes)
    validator_pk: [u8; 32],
    
    /// Validator Birth Certificate bundle (full chain to genesis)
    /// Core verifies SPHINCS+ chain back to genesis root keys.
    /// MANDATORY in all modes (dev, test, production).
    vbc_bundle: VBCProofBundle,
    
    /// Carrier type (how to reach this validator)
    carrier_type: String,
    
    /// Carrier address (endpoint for this validator)
    carrier_address: String,
    
    /// Validator's signature over commitment_hash
    /// Length varies by algorithm: Ed25519=64, Dilithium=3309, SPHINCS+=7856
    signature: Vec<u8>,
    
    /// ZKP Execution Proof (MANDATORY)
    execution_proof: ExecutionProof,
    
    /// Availability attestation (from overlap witness)
    availability_attestation: Option<AvailabilityAttestation>,
    
    /// Validator hints for organic discovery (1-3 per response)
    validator_hints: Vec<ValidatorHint>,
}
```

**VBC Verification Rule (FACT-1b):**
```
At every transaction boundary (CL2, CL3, CL4), Core MUST verify:
1. vbc_bundle chain walks to genesis root keys (SPHINCS+ signatures)
2. validator_pk matches VBC subject_pubkey_ed25519
3. validator_id == BLAKE3(VBC subject_pubkey_sphincs)
VBC is MANDATORY in all modes. Core MUST reject witnesses without
valid VBC bundles with E_INVALID_VBC.
```

### 26.9.1 Validator ID Format

Validator IDs follow the same format as Wallet IDs (Section 16.14):

```
email/checksum+salt

Example: v1@axiom.validators/a6b2e401
```

**Format:**
- `email`: Validator's email address (used for mailto: carrier)
- `checksum`: 6 hex characters = first 3 bytes of BLAKE3(email || hex(master_pk) || salt)
- `salt`: 2 hex characters for uniqueness

**Validation:**
- Core validates validator_id using the same checksum algorithm as wallet_id
- This ensures consistent identity format across the entire AXIOM ecosystem

### 26.9.2 Witness Receipt (Client Storage)

When a client receives a witness signature, it MUST store it as a **WitnessReceipt** for S-ABR overlap requirements in subsequent transactions.

```rust
struct WitnessReceipt {
    /// Validator's ID (same format as wallet_id)
    /// Example: "v1@axiom.validators/a6b2e401"
    validator_id: String,
    
    /// Validator's public key (32 bytes Ed25519)
    validator_pk: [u8; 32],
    
    /// Validator's signature over commitment_hash (64 bytes)
    signature: [u8; 64],
    
    /// Ordered list of carrier URIs for reaching this validator
    /// First element = preferred (last successful)
    /// Size limit: max 512 bytes total
    carriers: Vec<String>,
    
    /// ZKP Execution Proof (if provided)
    execution_proof: Option<Vec<u8>>,
}
```

### 26.9.3 Carrier URI Format

Carriers define how to reach a validator. The format is a URI-like string:

| Scheme | Description | Example |
|--------|-------------|---------|
| `mailto:` | Email via ANTIE gateway | `mailto:v1@axiom.validators` |
| `p2p:` | Direct P2P connection | `p2p:192.168.1.100:3030` |
| `https:` | REST API endpoint | `https://v1.axiom.network/api` |
| `grpc:` | gRPC endpoint | `grpc://v1.axiom.network:50051` |
| `ws:` | WebSocket endpoint | `ws://v1.axiom.network:8080` |

#### Carrier Validation Rules (NORMATIVE - Enforced by Core)

Core only enforces total size to prevent bloat. Format/scheme validation is the client's responsibility.

```rust
const MAX_CARRIERS_TOTAL_BYTES: usize = 512;

fn validate_carriers(carriers: &[String]) -> Result<(), ValidationError> {
    let total_bytes: usize = carriers.iter().map(|c| c.len()).sum();
    if total_bytes > MAX_CARRIERS_TOTAL_BYTES {
        return Err(ValidationError::CarriersTooLarge);
    }
    Ok(())
}
```

| Error Code | Description |
|------------|-------------|
| `E_CARRIERS_TOO_LARGE` | Total carriers exceed 512 bytes |

**Why only size validation?**
- Core validates cryptography, not transport
- Core never connects to carrier URIs
- Scheme/format is client's responsibility
- Size limit prevents bloat in receipts

#### Carrier Schemes (Non-Normative)

Recommended schemes for interoperability:

| Scheme | Description | Example |
|--------|-------------|---------|
| `mailto:` | Email via ANTIE gateway | `mailto:v1@axiom.validators` |
| `p2p:` | Direct P2P connection | `p2p:192.168.1.100:3030` |
| `https:` | REST API endpoint | `https://v1.axiom.network/api` |
| `grpc:` | gRPC endpoint | `grpc://v1.axiom.network:50051` |
| `ws:` | WebSocket endpoint | `ws://v1.axiom.network:8080` |

Clients MAY use any scheme - Core does not validate or restrict.

#### Carrier Operational Protocol (Non-Normative)

While Core validates format, the following are operational guidelines:

1. **Ordering**: First carrier is preferred (what worked last time)
2. **Fallback**: Client tries carriers in order if preferred fails
3. **Reordering**: Client MAY reorder based on success/failure
4. **At least one**: Receipts SHOULD have at least one carrier

**Example:**
```json
{
  "validator_id": "v1@axiom.validators/a6b2e401",
  "validator_pk": "ddbb164caac92c27...",
  "signature": "a1b2c3d4...",
  "carriers": [
    "mailto:v1@axiom.validators",
    "p2p:192.168.1.100:3030",
    "https://v1.axiom.network/api"
  ],
  "execution_proof": null
}
```

### 26.10 Validation Flow

**CRITICAL: Validation Ordering**

The order of validation checks is NORMATIVE. State_id consumption MUST be checked BEFORE epoch validity to prevent race conditions at epoch boundaries.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Transaction Validation Flow                       │
│                    (ORDER IS NORMATIVE)                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Step 1: Receive Transaction                                         │
│  ─────────────────────────────                                       │
│  Gateway receives: { payload, client_sig, prev_receipts }            │
│                                                                      │
│  Step 2: Verify Previous ZKP Proofs                                 │
│  ──────────────────────────────────                                 │
│  For each receipt in prev_receipts:                                  │
│    a) Extract program_digest from proof_bytes                        │
│    b) Verify program_digest ∈ CANONICAL_CORE_DIGESTS                │
│    c) Verify ZKP proof is mathematically valid                       │
│    d) Verify public_outputs.result == Accept                         │
│    e) Verify signature is over commitment_hash                       │
│                                                                      │
│  If ANY check fails → REJECT                                        │
│                                                                      │
│  Step 3: Verify Data Availability                                   │
│  ────────────────────────────────                                   │
│  For each prev_receipt:                                              │
│    a) Identify overlap witness                                       │
│    b) Verify availability_attestation from overlap witness          │
│    c) If needed, request actual data from overlap witness           │
│    d) If data unavailable → BLOCK (not reject, money frozen)        │
│                                                                      │
│  Step 4: State ID Check (BEFORE Epoch Check)                        │
│  ───────────────────────────────────────────                        │
│  a) Verify consumed_state_id exists and is valid                    │
│  b) Verify consumed_state_id is NOT already consumed                │
│                                                                      │
│  If state_id already consumed → REJECT (E_DOUBLE_SPEND)             │
│  This check MUST happen before epoch validation.                     │
│                                                                      │
│  Step 5: Verify Nonce and Epoch (AFTER State ID Check)              │
│  ─────────────────────────────────────────────────────              │
│  a) Verify epoch is within valid range                               │
│  b) Verify (client_pk, epoch, nonce) not already used               │
│                                                                      │
│  If invalid → REJECT (E_REPLAY or E_INVALID_EPOCH)                  │
│                                                                      │
│  Step 6: DoS Protection Check                                       │
│  ────────────────────────────                                       │
│  a) Verify complexity within limits                                  │
│  b) Verify deposit present if required                               │
│  c) Check rate limits                                                │
│                                                                      │
│  If exceeded → REJECT                                               │
│                                                                      │
│  Step 7: Execute Core Validation (Inside zk-VM)                      │
│  ─────────────────────────────────────────────                      │
│  axiom-core.elf executes inside zk-VM:                                     │
│    a) Verify client_sig                                              │
│    b) Verify balance sufficient                                      │
│    c) Verify consumed_state_id not already consumed (re-verify)     │
│    d) Verify (client_pk, epoch, nonce) not already used (re-verify) │
│    e) Verify VBC for all witnesses                                   │
│    f) Verify S-ABR constraints                                       │
│                                                                      │
│  zk-VM produces:                                                      │
│    - execution_proof with commitment_hash                            │
│    - program_digest bound to proof                                   │
│                                                                      │
│  Step 8: Sign and Return                                            │
│  ────────────────────────────                                       │
│  witness_sig = Sign(validator_sk, commitment_hash)                  │
│  Return: { witness_sig, execution_proof }                           │
│                                                                      │
│  Step 9: Record State Updates (Atomic)                              │
│  ─────────────────────────────────────                              │
│  ATOMICALLY:                                                         │
│    a) Mark consumed_state_id as consumed                             │
│    b) Mark (client_pk, epoch, nonce) as used                        │
│    c) Record produced_state_id as available                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Why State ID Before Epoch:**
```
At epoch boundary (e.g., epoch 5 → epoch 6):
  - Validator A (fast clock): sees epoch 6
  - Validator B (slow clock): sees epoch 5
  
If attacker submits same transaction to both:
  - Without ordering: Both might accept (different epochs, same nonce OK)
  - With state_id first: First one consumes state_id, second REJECTED
  
State_id is the ultimate double-spend prevention, regardless of epoch.
```

### 26.11 DoS Protection

#### 26.11.1 Complexity Limits (NORMATIVE)

| Parameter | Value | Enforcement |
|-----------|-------|-------------|
| `MAX_PREV_RECEIPTS` | 10 | MUST reject |
| `MAX_PAYLOAD_SIZE` | 64 KB | MUST reject |
| `MAX_PROOF_BYTES` | 1 MB | MUST reject |
| `MAX_WALLET_SEQ` | 2^48 | MUST reject (E_WALLET_SEQ_OVERFLOW) |
| `MAX_VBC_BUNDLE_SIZE` | 32 KB | MUST reject |
| `MAX_VBC_BUNDLE_OBJECTS` | 32 | MUST reject |
| `MAX_VBC_CHAIN_DEPTH` | 8 | MUST reject |

**VBC Bundle Limits (from VBC Specification):**
```
VBC bundles are limited to prevent DoS:
  - Maximum 32 KB total size
  - Maximum 32 objects in bundle
  - Maximum chain depth of 8 (Genesis → V1 → V2 → ... → V8)

These limits are enforced by Core during VBC validation.
See VBC Specification for detailed bundle structure.
```

#### 26.11.2 Security Deposit

```rust
const COMPLEXITY_THRESHOLD_SECONDS: u32 = 30;
const DEPOSIT_RATE_ATOMS: u64 = 1_000_000_000;  // 0.001 AXC per second

fn required_deposit(estimated_seconds: u32) -> u64 {
    if estimated_seconds <= COMPLEXITY_THRESHOLD_SECONDS {
        0
    } else {
        (estimated_seconds - COMPLEXITY_THRESHOLD_SECONDS) as u64 * DEPOSIT_RATE_ATOMS
    }
}
```

**Deposit Rules:**
- Valid transaction → deposit returned
- Invalid transaction → deposit burned
- Rejected before proof generation → deposit returned

#### 26.11.3 Rate Limits

```
Per-client:
  MAX_PENDING_PER_CLIENT = 3
  MAX_QUEUED_PER_CLIENT = 10

Global:
  MAX_QUEUE_SIZE = 1000

Eviction: Lowest deposit first, never evict with deposit > threshold
```

#### 26.11.4 Gossip Per-Peer Rate Limit (Normative)

Nabla nodes MUST enforce a per-peer gossip rate limit to prevent a single malicious node from flooding the mesh with unique messages that pass dedup but consume forwarding bandwidth and CPU (SECURITY FIX #6):

```
GOSSIP_PER_PEER_LIMIT  = 500   // max messages accepted per peer per window
GOSSIP_RATE_WINDOW_SECS = 60   // window duration (seconds)
```

Messages exceeding 500 per peer within any 60-second sliding window MUST be silently dropped. Reference: `nabla/src/gossip.rs`.

#### 26.11.5 Receipt Staleness Window (Normative)

Nabla nodes MUST reject registration requests (`/register`) carrying receipts older than 300 ticks (~25 minutes):

```
RECEIPT_STALENESS_TICKS = 300   // current_tick - receipt.tick > 300 → reject
```

This prevents replay of ancient but structurally-valid receipts. Legacy receipts with `tick = 0` fall back to current tick (no staleness check). Reference: `nabla/src/registration.rs`.

### 26.12 Error Codes

| Error Code | Meaning |
|------------|---------|
| `E_MISSING_ZKP_PROOF` | WitnessSig lacks ExecutionProof |
| `E_INVALID_ZKP_PROOF` | ZKP proof verification failed |
| `E_INVALID_PROGRAM_DIGEST` | Program digest not in CANONICAL_CORE_DIGESTS |
| `E_COMMITMENT_MISMATCH` | Signature not over zk-VM commitment_hash |
| `E_DATA_UNAVAILABLE` | Cannot retrieve data from overlap witness (BLOCK, not reject) |
| `E_DOUBLE_SPEND` | State ID already consumed |
| `E_REPLAY` | (client_pk, epoch, nonce) already used |
| `E_INVALID_EPOCH` | Epoch outside valid range |
| `E_COMPLEXITY_EXCEEDED` | Transaction exceeds limits |
| `E_DEPOSIT_REQUIRED` | High-complexity without deposit |
| `E_RATE_LIMITED` | Client rate limit exceeded |
| `E_INVALID_JSON` | CBOR validation failed (prohibited type, non-canonical, etc.) |
| `E_DUPLICATE_VALIDATOR` | Same validator_pk appears multiple times in witness set |
| `E_INVALID_VBC_COUNT` | Validator has zero or multiple valid VBCs |
| `E_MISSING_PREV_RECEIPTS` | Non-genesis transaction has empty prev_receipts |
| `E_INVALID_WALLET_SEQ` | wallet_seq is not prev_wallet_seq + 1 |
| `E_WALLET_SEQ_OVERFLOW` | wallet_seq >= 2^48 |
| `E_VBC_EXPIRED` | VBC not valid at verification epoch |
| `E_VBC_BUNDLE_TOO_LARGE` | VBC bundle exceeds size/object limits |
| `E_MULTI_INPUT_NOT_SUPPORTED` | Transaction attempts to consume multiple states |

### 26.13 Security Properties

#### 26.13.1 What ZKP Guarantees

1. **Computational Integrity:** Proof exists → axiom-core.elf actually executed
2. **Program Binding:** Proof is bound to specific axiom-core.elf binary (full hash)
3. **Input-Output Binding:** Proof binds inputs to outputs (including nonce, state_id)
4. **Non-Replayability:** Epoch-nonce + state_id prevent replay

#### 26.13.2 Security Statement

```
POLLUTION ISOLATION:

If at least ONE conformant verifier exists at the receiving boundary,
fraudulent transactions from malicious worldlines will be rejected.

Attackers controlling Client + k Validators can create an isolated worldline,
but that worldline's money cannot enter the honest network.
```

#### 26.13.3 Fail-Stop Properties

```
Data unavailable → Money frozen (not stolen)
Proof invalid → Transaction rejected
State inconsistent → Fail-stop

No manual intervention. No rescue operations. No governance override.
```

### 26.14 Implementation Notes (Non-Normative)

#### 26.14.1 zk-VM Requirements

Any zk-VM that provides:
- General computation (can run axiom-core.elf)
- Program digest bound to proof (not public input)
- STARK or SNARK proofs
- Security ≥ 128 bits
- Offline verification

#### 26.14.2 zk-VM Version is Fixed from Genesis (NORMATIVE)

**The zk-VM version is determined at Genesis and does NOT change.**

```
AXIOM does not support runtime zk-VM upgrades.

The zk-VM version is:
  - Determined when axiom-core.elf is compiled
  - Embedded in the axiom-core.elf binary
  - Part of the program_digest
  - Fixed for the lifetime of that axiom-core.elf version
```

**Why No Runtime Upgrades:**
```
Runtime zk-VM upgrades would require:
  - Coordination across all validators
  - Handling of in-flight transactions
  - Risk of network splits during transition
  - Potential for upgrade-window attacks

AXIOM avoids all this by making zk-VM part of axiom-core.elf:
  - New zk-VM version = new axiom-core.elf version
  - New axiom-core.elf = new program_digest
  - New program_digest = software release, not runtime upgrade
```

**"Upgrading" zk-VM:**
```
If a critical zk-VM bug is discovered:
  1. Fix is incorporated into new axiom-core.elf
  2. New axiom-core.elf is released (new program_digest)
  3. Validators upgrade their axiom-core.elf software
  4. New program_digest is added to CANONICAL_CORE_DIGESTS
  5. This is a software release, handled like any axiom-core.elf update
```

**axiom-core.elf Upgrade Path (NORMATIVE):**
```
axiom-core.elf upgrades are SOFTWARE RELEASES, not GOVERNANCE:

1. ANNOUNCEMENT
   - New axiom-core.elf version is developed and tested
   - New program_digest is computed
   - Release announcement with activation epoch

2. DISTRIBUTION
   - Validators download and verify new axiom-core.elf
   - Validators can run old and new versions in parallel
   - No coordination required - each validator upgrades independently

3. ACTIVATION
   - New program_digest is hardcoded in CANONICAL_CORE_DIGESTS
   - This happens via software release, not runtime configuration
   - Old axiom-core.elf continues to work (both digests valid)

4. DEPRECATION (optional)
   - After sufficient adoption, old digest MAY be removed
   - This is announced well in advance
   - Validators still on old version would produce invalid proofs

This is DIFFERENT from governance:
  - No voting
  - No quorum
  - No admin keys
  - Just software updates that validators choose to adopt
  
If validators don't adopt new axiom-core.elf:
  - They continue producing valid proofs with old digest
  - Network continues operating
  - No forced upgrade
```

#### 26.14.3 zk-VM Verifier Consistency

**All nodes MUST use identical zk-VM verifier (same version as in axiom-core.elf).**

```
Risk: Verifier Implementation Divergence
  - Different zk-VM library versions may have subtle differences
  - Floating-point handling, field arithmetic edge cases
  - A proof valid on one verifier may be invalid on another
  - This causes network splits / forks

Prevention:
  1. Mandate specific zk-VM library version (e.g., risc0 v1.2.3)
  2. All validators MUST use the same version
  3. Version is part of network configuration
  4. Validators with wrong version are rejected from witness sets
  
Verification:
  - Network-wide verifier self-tests during bootstrap
  - Test vectors that all verifiers must pass identically
  - Version mismatch detection in handshake
```

**Upgrade Process:**
```
When upgrading zk-VM verifier:
  1. New version announced with activation epoch
  2. Validators upgrade before activation
  3. At activation, old version rejected
  4. This is coordinated software upgrade, not governance
```

#### 26.14.4 Multi-zk-VM (Optional)

Users concerned about zk-VM bugs MAY:
- Request higher k (e.g., k=5 instead of k=3)
- Use validators running different zk-VM implementations

This is a user choice, not a protocol requirement.

### 26.15 Summary: Attack Resistance

| Attack | Defense |
|--------|---------|
| Skip Core | No valid proof → rejected |
| Modified Core | Wrong program digest → rejected |
| Partial binary hash | Full binary hash (all segments) |
| MITM data swap | Signature over commitment_hash |
| Proof replay | Epoch-nonce + state_id |
| **Parallel-proof double-spend** | **wallet_seq must be sequential** |
| **Genesis wallet_seq race** | **Genesis has state_id, first tx forced wallet_seq=1** |
| **wallet_seq overflow DoS** | **Max 2^48, then reject** |
| Nonce registry explosion | Epoch scoping + pruning |
| Data withholding | Fail-stop (frozen, not stolen); 2-3 overlap witnesses |
| Double spend | State_id consumption (checked FIRST) + wallet_seq |
| **Double spend (stale replay)** | **FACT-1: consumed_state_id must match prev_receipts[last].produced_state_id (Core enforced)** |
| **Unverified state transition** | **FACT-2/3: Receipt must carry valid zk-VM proof (production mode)** |
| **Forged prev_receipts** | **FACT-1b: witness PKs in prev_receipts must have valid VBCs chaining to genesis** |
| **Epoch drift / asymmetric visibility** | **Epoch derived from consumed_state_id ONLY** |
| Epoch boundary race | State_id check before epoch check |
| Governance backdoor | No governance mechanism exists |
| Quantum attack on VBCs | **ALL VBCs use Dilithium (quantum-safe)** |
| **VBC key reuse / duplication** | **One valid VBC per validator_pk (Core enforced)** |
| **VBC validity boundary** | **Validity checked at verification time using epoch** |
| VBC from compromised Genesis | VBC expiry (3 years) as slow-revocation |
| **Mid-epoch VBC revocation** | **Not supported - VBC state fixed within epoch** |
| **VBC renewal cartel** | **Economically impractical (cost vs reward analysis)** |
| **VBC bundle DoS** | **Max 32KB, 32 objects, depth 8** |
| Network-wide freeze | Per-wallet freeze only; Recovery Mode for catastrophic |
| Core bypass via fake seq | wallet_seq only modifiable by Core |
| Serialization ambiguity | **AXIOM Canonical JSON Profile (no floats, canonical, Core validated)** |
| **JSON key collision** | **Map keys: only byte strings or integers, no text** |
| **Length prefix ambiguity** | **Fixed u64 little-endian (not CBOR integer)** |
| JSON decoder differences | **AXIOM Canonical JSON Profile with strict type restrictions** |
| zk-VM verifier divergence | **zk-VM version fixed from Genesis** |
| **zk-VM ossification** | **axiom-core.elf upgrade path via software release** |
| **Empty prev_receipts bypass** | **Only Genesis transactions can have empty prev_receipts** |
| **Multi-input transaction** | **Single-input only, E_MULTI_INPUT_NOT_SUPPORTED** |
| **Recovery Mode abuse** | **Recovery Mode preserves all security invariants** |
| **Wallet fork confusion** | **Wallet fork is expected; worldline semantics documented** |
| **Frozen AXC economic loss** | **Atom divisibility; deflation not value loss** |

### 26.16 Summary Invariant

> **SYSTEM-WIDE: ALL serialization MUST use AXIOM Canonical JSON Profile.**
> - No floats (integers only for all values)
> - Keys sorted by Unicode codepoint (RFC 8785 JCS)
> - Binary data with b64u: prefix
> - Core validates all JSON inputs
> - Cross-reference: LAMBDA_CANONICAL_JSON_BYTES.md
>
> **SYSTEM-WIDE: ALL VBCs MUST use Dilithium.**
> - One valid VBC per validator_pk
> - VBC validity checked at verification time (epoch-based)
>
> **Execution Attestation is MANDATORY from Genesis (DMAP default, ZKP optional premium — see YPX-006).**
>
> **zk-VM version is fixed from Genesis. Upgrades via axiom-core.elf software release.**
>
> Program digest = SHA3-256(entire_elf_binary), bound by zk-VM.
>
> Commitment hash uses fixed u64 little-endian length prefixes.
>
> **Epoch MUST be derived from consumed_state_id ONLY (not wall clock, not local observation).**
>
> Nonces are epoch-scoped for bounded storage.
>
> **wallet_seq: Genesis=0, first tx forced to 1, then +1 each tx. Max 2^48.**
>
> **Genesis wallets have genesis_state_id (prevents first-tx race).**
>
> **Single-input transactions only (one consumed_state_id per tx).**
>
> **Validation order: State_id check BEFORE epoch check.**
>
> **Empty prev_receipts ONLY valid for Genesis transactions.**
>
> Data availability via overlap witnesses (2 for k=3, 3 for k=4/5).
>
> DA is for reliability, not adversarial resistance.
>
> **Recovery Mode preserves ALL security invariants (may only change liveness params).**
>
> Fail-stop applies per-wallet, NOT network-wide.
>
> **Wallet fork is EXPECTED BEHAVIOR - creates new worldline, not double-spend.**
>
> **Frozen AXC = frozen value, not destroyed. Atom divisibility handles deflation.**
>
> **Worldline identification is CLIENT/UX responsibility.**
>
> **No human intervention. Ever.**
>
> **POLLUTION ISOLATION:** Malicious worldlines cannot contaminate honest ones.


### 26.17 FACT: Financial Audit Chain of Trust (Base Protocol)

**NORMATIVE — This section defines requirements for the base protocol.**

#### 26.17.1 Principle: No Proof, No Money

> **Every state transition in AXIOM MUST be backed by an execution attestation.**
> **A receipt without a valid attestation is not a receipt — it is an unverified claim.**

AXIOM supports two execution attestation tiers (see YPX-006):

- **DMAP (default):** Deterministic Memory Attestation Protocol. RISC-V interpreter re-executes
  Core, collects memory/register checkpoints, commits via Merkle tree, reveals K=64
  Fiat-Shamir-challenged checkpoints. With k=3 independent validators (S=192 samples),
  detection confidence ≥13 nines (99.9999999999999%) for all security-critical attacks.
  ~10-50ms proving time, ~19KB attestation. Available to all validators.

- **ZKP (optional premium):** RISC Zero STARK proof. Mathematical certainty (100%).
  ~200s CPU / ~4s GPU proving time, ~500KB seal. For high-performance validators with
  GPU proving capability. Config: `[proof] mode = "zkp"`.

The execution attestation — whether DMAP or ZKP — is the cryptographic guarantee that
Core actually ran, actually verified the signature, actually checked the balance.
This is what FACT means: **Funds Auditable via Certified Transactions.**

#### 26.17.2 Receipt Structure (NORMATIVE)

A Receipt MUST contain the execution attestation (DMAP or ZKP). This is the structure that clients store and present as `prev_receipts` in subsequent transactions:

```rust
struct Receipt {
    /// Transaction ID (BLAKE3 hash of commitment bytes)
    txid: [u8; 32],
    
    /// State hash after transaction
    state_hash: [u8; 32],
    
    /// Produced state ID (new wallet state after this TX)
    produced_state_id: [u8; 32],
    
    /// New wallet sequence number
    new_wallet_seq: u64,
    
    /// Witness signatures (k=3 minimum)
    /// Each WitnessSig contains its own ExecutionProof (Section 26.9)
    witness_sigs: Vec<WitnessSig>,
    
    /// Epoch when processed
    epoch: u64,
    
    /// Aggregate FACT proof (MANDATORY in production mode)
    /// This is the zk-VM receipt proving Core accepted this transaction.
    /// In dev mode (deterministic mode): None (no zk-VM running)
    /// In production mode: Some(proof) — MUST be present and verifiable
    fact_proof: Option<FactProof>,
}
```

#### 26.17.2.1 Receipt Commitment (NORMATIVE, v2.13.00)

Receipt forgery — a client or colluding validator altering a receipt field (`state_hash`, `produced_state_id`, `epoch`, etc.) to advance a wallet past a state Core never accepted — was previously detectable only at the next transaction's full Core re-execution. v2.13.00 closes this with a per-receipt commitment that **k validators sign**, distinct from the per-link FACT signature.

```rust
struct Receipt {
    // ... existing fields ...
    receipt_commitment: [u8; 32],  // BLAKE3("AXIOM_RECEIPT_v1" || ...)
}

struct WitnessSig {
    // ... existing fields ...
    receipt_commitment_sig: Option<Vec<u8>>,  // Ed25519 over receipt_commitment
}
```

The commitment binds all reproducible receipt fields:

```
receipt_commitment = BLAKE3(
    "AXIOM_RECEIPT_v1" ||
    txid ||
    state_hash ||
    produced_state_id ||
    new_wallet_seq.to_le_bytes() ||
    commitment_hash ||
    epoch.to_le_bytes()
)
```

Each witnessing validator computes `receipt_commitment` from Core-produced fields, signs it with their Ed25519 receipt key, and returns the signature in `WitnessSig.receipt_commitment_sig`. Core's CL2 verification, on the next transaction carrying this receipt as `prev_receipt`:

1. Recomputes `receipt_commitment` from the receipt fields.
2. Compares against the stored value. Mismatch → `E_RECEIPT_COMMITMENT_MISMATCH`.
3. Verifies at least one witness's `receipt_commitment_sig` against the recomputed commitment. Missing or invalid → `E_RECEIPT_COMMITMENT_MISMATCH`.

A fabricated field changes the commitment, which invalidates the validators' signatures — the receipt is rejected before any state advance. Honest validators all produce the same commitment (deterministic from Core fields), so any single valid signature proves the receipt was witnessed honestly.

**Strict mode (NORMATIVE).** The verification path runs unconditionally — there is no "skip when zero" shim. A receipt whose `receipt_commitment` is the zero hash, or whose stored value does not match the recomputation from receipt fields, or for which no `WitnessSig.receipt_commitment_sig` verifies against the recomputed commitment, is rejected with `E_RECEIPT_COMMITMENT_MISMATCH`. The wire format carries `receipt_commitment` on `Receipt` (CBOR field-tag 12) and `receipt_commitment_sig` on `WitnessSig` (CBOR field-tag 12); decode failure of either is an error, not a graceful degradation. Lambda hard-errors with `LambdaError::CoreError("Core did not provide receipt_commitment")` if Core returns no commitment after a successful witness round, so an honest Lambda cannot persist a receipt that would later fail this check.

**Implementation references:** `core/logic/src/crypto.rs::compute_receipt_commitment` (the BLAKE3 over the field tuple), `core/logic/src/validation.rs:1283-1318` (the strict-mode verify block on the CL2 path), `core/ipc/src/codec.rs` (CBOR field-tag 12 on Receipt and WitnessSig), `lambda/src/consensus.rs` (commitment populated on `WitnessResponse` from V1, V2, and finalizer paths; hard-error if Core returned no commitment), `lambda/src/storage.rs` (column on the receipts table; idempotent `ALTER TABLE` migration for older databases).

#### 26.17.3 FactProof Structure

```rust
struct FactProof {
    /// RISC Zero receipt bytes (STARK proof)
    /// Proves: axiom-core.elf executed with the given PublicInputs
    ///         and produced the given PublicOutputs,
    ///         and the result was ValidationResult::Accept.
    zkvm_receipt: Vec<u8>,
    
    /// Program digest of axiom-core.elf that produced this proof
    /// Verifier checks: this matches the known axiom-core.elf digest
    core_digest: [u8; 32],
    
    /// The public inputs that were fed to Core
    /// Verifier recomputes: hash(public_inputs) matches what's in the proof
    public_inputs_hash: [u8; 32],
    
    /// The public outputs Core produced
    /// Contains: produced_state_id, new_wallet_seq, state_hash
    public_outputs_hash: [u8; 32],
}
```

#### 26.17.4 Verification Rules (NORMATIVE)

When processing a transaction with `prev_receipts`, Core MUST verify:

```
RULE FACT-1: State Chain Integrity
    For non-genesis transactions:
    tx.consumed_state_id == prev_receipts[last].produced_state_id
    
    Rationale: The client's consumed_state_id must match the
    previous receipt's output. This is Core's independent check
    that cannot be bypassed by a compromised gateway.

RULE FACT-1b: Witness Signature Authenticity
    For each witness_sig in prev_receipts:
    1. Signature must verify against witness_sig.validator_pk
    2. validator_pk must be backed by a valid VBC
    3. VBC must chain to genesis validators
    
    Rationale: Without VBC cross-check, an attacker can generate
    a random key pair, sign a forged receipt, and pass FACT-1.
    The VBC proves the signer is a legitimate network validator.
    
    Note: This is the same VBC verification used for current-TX
    witnesses (Section 23.13), applied to prev_receipt witnesses.

RULE FACT-2: Proof Presence (Production Mode)
    For non-genesis prev_receipts:
    prev_receipt.fact_proof MUST be Some(_)
    
    Rationale: A receipt without proof is an unverified claim.
    Core will not build on unverified state transitions.

RULE FACT-3: Proof Validity (Production Mode)
    For each prev_receipt.fact_proof:
    1. zkvm_receipt must verify against core_digest
    2. core_digest must match the known axiom-core.elf program digest
    3. The proof must attest ValidationResult::Accept
    
    Rationale: The previous state transition was legitimately
    accepted by genuine Core code.

RULE FACT-4: State Continuity
    prev_receipt.fact_proof.public_outputs must contain the
    produced_state_id that matches prev_receipt.produced_state_id
    
    Rationale: The proof and the receipt must agree on the
    state that was produced.
```

#### 26.17.5 Production Mode (NORMATIVE, v2.10.31+)

Dev mode was removed in v2.10.31. All proofs are real RISC Zero STARK proofs. There is no fake proof, no dev seal, no bypass.

| Rule | Status |
|------|--------|
| State chain check (FACT-1) | ENFORCED |
| Proof presence (FACT-2) | ENFORCED |
| Proof validity (FACT-3) | ENFORCED |
| State continuity (FACT-4) | ENFORCED |

Lambda requires zk-VM artifacts (ELF + IMAGE_ID) at startup or exits with `exit(1)`. Empty proofs are accepted during bootstrap (legacy compatibility) but `zkp_verified = false`.

#### 26.17.6 Relationship to Phase 2 FACT chain (YPX-001)

This section (26.17) defines the **base protocol FACT** — each receipt carries the proof that its state transition was verified by Core.

Phase 2 (YPX-001) extends this with **FACT chains** — tracing money provenance backward through multiple transactions to genesis. The base FACT proof is one link in that chain. Phase 2 adds:
- Chain walking (verify history back to genesis allocation)
- Genesis checkpoints (compress old history)
- Scar system (unverified links)
- TARDIS temporal binding

The base protocol provides the building blocks. Phase 2 chains them together.

#### 26.17.6.1 Three-Tier Cryptographic Architecture (NORMATIVE)

AXIOM uses three signature algorithms, each chosen for its operational frequency and security profile:

```
Tier 1: Ed25519 (Transaction-Grade)
    Speed:     ~0.05ms per sign/verify
    Used for:  Witness commitment signatures, client TX signatures
    Frequency: Every transaction (k=3 per TX)
    Key:       WitnessSig.signature field

Tier 2: Dilithium ML-DSA-65 (FACT-Grade, Quantum-Resistant)
    Speed:     ~1ms per sign/verify
    Used for:  FACT chain link signatures, checkpoint signatures
    Frequency: Every transaction (k=3 FACT sigs per TX)
    Key:       WitnessSig.fact_signature field, FactWitness.signature
    Note:      Operational QR — fast enough for per-TX signing

Tier 3: SPHINCS+ (Identity-Grade, Quantum-Resistant)
    Speed:     ~100ms per sign/verify
    Used for:  VBC identity certificates (signed once at validator birth)
    Frequency: Once per validator lifetime
    Key:       VBC.subject_pubkey_sphincs field
    Note:      Ceremonial QR — acceptable latency for one-time use
```

Core holds all three key types. Lambda passes keys to Core via `PublicInputs` but MUST NOT call signing functions directly. Core signs FACT commitments with the validator's Dilithium key internally and returns `fact_signature` in `PublicOutputs`.

#### 26.17.6.2 FACT Link Assembly at k=3 (NORMATIVE)

FACT links are assembled by the overlapped validator (the last to witness, which reaches k=3 signatures). The assembly flow:

```
V1 (first validator):
  1. Core CL3 produces fact_signature (Dilithium over FACT commitment)
  2. V1 returns WitnessSig with fact_signature to client
  
V2 (second validator):
  1. Receives V1's WitnessSig in overlapped_signatures
  2. Core CL3 produces its own fact_signature
  3. V2 returns WitnessSig with fact_signature to client
  
V3 (third validator — finalizer):
  1. Receives V1+V2's WitnessSigs in overlapped_signatures
  2. Core CL3 produces its own fact_signature
  3. all_sigs = [V1_sig, V2_sig, V3_sig] — all with fact_signature
  4. build_fact_link() verifies each fact_signature against current
     FACT commitment using Dilithium PK from VBC bundle
  5. Filters stale sigs (from previous TX) by verification failure
  6. Requires 3 valid current-TX fact_signatures
  7. Assembles FactLink with 3 FactWitnesses
  8. Appends to client's existing FACT chain
  9. Runs verify_and_compress_fact_chain() for chain integrity + compression
```

FACT commitment: `BLAKE3("AXIOM_FACT_v2" || tx_id || previous_state_id || new_state_id || amount_le || sender_anchor_or_zeros || is_dev_class || inherited_count_le32 || inherited_scar_txids…)` — `sender_anchor` is the cheque's `sender_fact_chain.tip().new_state_id` for redeem links, else 32 zero bytes; see §26.17.6.4. `is_dev_class` is the FACT class lock. `inherited_scar_txids` is the SCAR-INHERITANCE set (YPX-001 §1.5.1a, 2026-07-12): the sender's unresolved txids carried onto a cross-wallet redeem link, ascending-sorted, preceded by its u32-LE count; empty (count 0, no txids) on send / heal / burn / self-redeem links. Binding it means the k witnesses SIGN the taint — a receiver cannot strip inherited scars without invalidating every Dilithium `fact_signature`. The pre-A2 `AXIOM_FACT` tag is removed; there is no coexistence period.

If build_fact_link fails (insufficient valid sigs), the FACT link is DEFERRED (non-fatal). The receipt is still produced. The client's chain remains unchanged. A later transaction may succeed in building the link.

#### 26.17.6.3 FACT chain Compression (NORMATIVE)

FACT chain compression bounds chain growth while preserving provenance integrity.

```
Constants (SEC-07 travel model, "global-3"):
  FACT_PROPOSE_TRIGGER     = 4  // chain depth at which the first validator OPENS a
                                //   checkpoint proposal (a start signal, not "compress now")
  CHECKPOINT_SIG_THRESHOLD = 3  // distinct validator co-sigs required to FINALIZE
                                //   (delete covered links); = MIN_FACT_WITNESSES, global
  FACT_KEEP                = 3  // live tail retained after finalization
  FACT_COMPRESS_TRIGGER    = 5  // legacy immediate-compress soft trigger (resolved prefix > 5)
  MAX_FACT_DEPTH           = 8  // post-compression STRUCTURAL guard (verify_and_compress) +
                                //   operator max_fact_links; NOT a verify-path reject — a chain
                                //   verifies past 8 under the travel model (only FACT_HARD_CEILING
                                //   = 32 hard-rejects). Chains settle at ~6-8 by compression cadence.

Under the travel model a checkpoint is PROVISIONAL (pending_links > 0, covered links
retained) until it accumulates CHECKPOINT_SIG_THRESHOLD distinct co-signatures across
rounds, at which point the TX's final witnessing validator FINALIZES it (deletes the
covered links). See §"Travel-model checkpoint (SEC-07)". The before/after below shows
the finalized end-state.

Before compression (9 links, compressed_count=0):
  L1 --> L2 --> L3 --> L4 --> L5 --> L6 --> L7 --> L8 --> L9

After compression (5 links, compressed_count=4):
  [checkpoint: L1-L4, root_hash=X, compressed_count=4] --> L5 --> L6 --> L7 --> L8 --> L9

Total provenance depth = compressed_count + links.len() = 4 + 5 = 9

Checkpoint fields:
  root_hash:        BLAKE3 hash of compressed links
  compressed_count: Total links compressed (cumulative)
  final_state_id:   new_state_id of last compressed link
  genesis_state_id: previous_state_id of first-ever link (or from prior checkpoint)
  total_amount:     Sum of all compressed link amounts
  validator_sigs:   >= CHECKPOINT_SIG_THRESHOLD (3) DISTINCT Dilithium signatures once
                    finalized, accumulated across rounds (SEC-07 travel model)
  pending_links:    leading links still retained (provisional); 0 once finalized
```

**Scar-aware compression (implemented):** Only unscarred links (nabla_confirmation present) in the oldest prefix may be compressed. Scarred links and everything after them MUST remain uncompressed to prevent "wash-out" attacks where money launderers transact until scars fall off the chain via compression. See `compress_fact_chain()` in `core/logic/src/fact.rs`.

**Compression boundary effects:** Total provenance depth may not grow monotonically when transactions occur near the compression boundary. This is expected: depth = compressed_count + links oscillates as compression fires. Provenance is NOT lost — it is preserved in the checkpoint. Implementations SHOULD track provenance by comparing genesis_state_id continuity rather than total_depth monotonicity.

#### 26.17.6.4 sender_anchor: Receiver-Side Redeem Assembly (NORMATIVE, A2 — v2.12.00)

Pre-A2, a redeem produced two FACT links: one on the sender's chain (a cheque-out link) and one on the receiver's chain that "bridged" by referencing the sender's chain tip. This duplicated cryptographic work, required two Nabla registrations per redeem, and made transitive scar-resolution ambiguous (compressing a clean redeem could orphan a scarred bridge). The A2 cutover (v2.12.00) removes the bridge link.

A redeem now produces **one** FACT link, on the receiver's chain. That link carries an additional optional field:

```rust
struct FactLink {
    // ... standard fields ...
    sender_anchor: Option<[u8; 32]>,  // Some(tip_state_id) on REDEEM links; None elsewhere
}
```

`sender_anchor` is the sender's chain-tip `new_state_id` at send time, taken from `cheque.sender_fact_chain.tip().new_state_id`. Core CL5 verifies at redeem time:

```
link.sender_anchor == cheque.sender_fact_chain.tip().new_state_id
```

If the sender's chain is empty (no prior FACT links), Core CL5 rejects with `E_REDEEM_SENDER_ANCHOR_MISSING`. The sender_anchor is bound into the FACT commitment under the `AXIOM_FACT_v2` domain tag (see §26.17.6.2) — for SEND / HEAL / BURN links where `sender_anchor = None`, the commitment input substitutes 32 zero bytes. The pre-A2 `AXIOM_FACT` tag is removed; there is no v1/v2 coexistence period.

Effect: a redeem produces one link, one Nabla register, one signed commitment. Receiver-side provenance still anchors to the sender's chain tip cryptographically — what the bridge link did structurally is now achieved by hash inclusion.

**Implementation references:** `core/logic/src/modes.rs::execute_cl5`, `core/logic/src/fact.rs::compute_fact_commitment`. SDK responsibility: store the receiver's chain assembled by Core's CL5 finalizer (returned in `RedeemResponse.receiver_fact_chain`); the SDK does not assemble FACT links locally (CLAUDE.md §11, §12).

#### 26.17.7 Why This Is Core's Job

FACT verification is **safety logic**, not business logic:
- Core runs inside zk-VM — tamper-proof
- Core has the program digest — can verify other Core instances' proofs
- Core checks prev_receipts — independent of gateway or Lambda state
- If Core rejects, no proof is produced, transaction is dead

A compromised Lambda cannot bypass FACT verification because Core performs it inside the zk-VM. A compromised gateway cannot feed fake state because Core cross-checks against prev_receipts.

> **FACT is the reason AXIOM can be trustless.**
> **Without FACT proofs, AXIOM is just "trust the validators."**
> **With FACT proofs, AXIOM is "trust the math."**

#### 26.17.8 Double-Spend Defense Layers

FACT alone does not prevent all double-spend attacks. FACT verifies that the client's transaction chain is **structurally consistent** (consumed_state_id matches prev_receipts). An attacker replaying stale-but-genuine prev_receipts passes FACT because the data is internally consistent — it was real at the time.

Double-spend prevention requires **state awareness**: knowing whether a state_id is still current or has been superseded. AXIOM implements this across three layers:

```
Layer 1: Core (FACT-1) — Structural Integrity
    Verifies: consumed_state_id == prev_receipts[last].produced_state_id
    Catches: fabricated state_ids, mismatched chains, corrupted receipts
    Runs: inside zk-VM (tamper-proof)
    Limitation: passes stale-but-genuine prev_receipts

Layer 2: Lambda consumed set — Per-Validator State Memory
    Verifies: "Did I already witness the consumption of this state?"
    Marks consumed: at ACK time (after fee payment, state committed)
    Wallet state: PENDING at witness time, CONFIRMED at ACK time
    Checks consumed: at witness time (before signing)
    Catches: double-spend on overlapped validators (S-ABR guarantees k-1 overlap)
    Runs: Lambda storage (per-validator, local truth)
    Limitation: only catches overlap — does not prevent cross-validator-set attacks
    Note: Pending wallet state is valid for balance/state_id lookup in subsequent TX.
          Only consumed_state_id permanence is deferred to ACK.

Layer 3: Nabla (Phase 3) — Network-Wide State Verification
    Verifies: consumed_state_id is current across the network
    Catches: ALL double-spend attempts including cross-validator-set
    Runs: receiver-side verification via Nabla node queries
    Limitation: requires Nabla infrastructure (Phase 3)
```

**Phase 1 (current):** Layers 1 + 2 prevent structural fraud and double-spend on overlapped validators. S-ABR forces k-1 overlap, so at least 2 validators in the next TX also witnessed the previous TX and have the consumed state marked. Cross-validator-set replay (race condition) is a known limitation.

**Phase 3 (Nabla):** Layer 3 closes the remaining gap. Receiver queries 3 Nabla nodes before accepting a cheque. Nabla nodes gossip state transitions. If the consumed_state_id has been superseded, Nabla rejects.

#### 26.17.9 Consumed State Tracking (White Paper §4.11.1)

A validator tracks which state_ids have been consumed via ACK'd transactions. This is the primary double-spend defense at the validator level.

**Timing: consumed marking happens at ACK, not at witness.**

At witness time: the TX is PENDING. The client has not committed. The client may abandon this TX and build a new one from the same state (different receiver, different amount). This is legitimate retry behavior, not double-spend.

At ACK time: the client pays the validator fee, committing to this transaction. The state transition is now irreversible. The validator marks the consumed_state_id as permanently consumed.

**How it prevents double-spend (per White Paper §4.11.1):**

1. TX1 sends money from state X. Client ACKs → validators V1, V2, V3 all mark X as consumed.
2. TX2 tries to spend from state X again. S-ABR forces k-1 overlap → at least 2 of {V1, V2, V3} participate.
3. Overlapped validators check: "Did I already witness the consumption of this parent state?" → Yes → REJECT.

**What it does NOT catch:**

If TX2 goes to entirely different validators (no overlap), those validators have no knowledge of TX1. This is the race condition gap that Nabla (Phase 3) addresses.

#### 26.17.10 Wallet Recovery via CLARA (YPX-018)

The double-spend defenses above describe how the protocol *detects* and *rejects* improper state transitions. They do not, by themselves, provide a path for a wallet to *recover* when its own state has fractured across validators due to a partial witness (k=3 not reached). That recovery path is **CLARA** (Client-Led Attested Reality Alignment), specified in §17.10.14 and YPX-018.

**Relationship to FACT:** CLARA does NOT bypass FACT. A `TX_HEAL` cheque is a normal k=3-witnessed transaction, fully FACT-anchored. Its only special property is that it consumes the wallet's pre-poisoning state and produces a new "healed" state, and that this state transition is registered with Nabla via the TCP-CBOR `RegisterClaraRequest` wire along with a declaration of the abandoned (garbage) intermediate states.

**Relationship to scarred FACT:** CLARA is an alternative recovery path to scarring. A wallet that enters CLARA before any of its broken transactions reach Nabla can recover cleanly without ever scarring. A wallet that fails to act in time (e.g., if an attacker replays the broken transaction to fresh validators and the receiver redeems it before CLARA registers) ends up with a scarred FACT chain through the normal scar mechanism (§26.17.6.3 scar-aware compression). The two mechanisms are complementary:

- **CLARA** — proactive recovery, no scar, requires the wallet to act before any broken TX is completed by replay.
- **Scarred FACT** — reactive containment, scar applies, no special action by the wallet needed.

In both cases, **innocent receivers are protected by the existing pre-accept Nabla check (§17.9)**. CLARA introduces no new receiver liability, no new opt-in encumbrance, and no hereditary scar marker.

**Relationship to consumed-state tracking (§26.17.9):** CLARA's roll-forward at poisoned validators is the only protocol-defined exception to "stored state moves only as a result of a witnessed-and-ACK'd TX." A poisoned validator that receives a witness request carrying a valid `ClaraAttestation` advances its stored state from a garbage entry directly to the healed state, without itself having witnessed the TX_HEAL. This is safe because:

1. The `ClaraAttestation` is signed by Nabla using a key with an SPHINCS+-anchored trust chain (§39.9.4 NBC anchor pattern). A compromised Lambda cannot forge it.
2. The validator only ever moves *forward* — never backward. Roll-back of stored state is forbidden.
3. The validator's stored state must literally appear in the attestation's `garbage_state_ids` list. If the stored state is not in that list, the attestation is rejected (`E_CLARA_STATE_NOT_GARBAGE`). A different wallet cannot use a CLARA attestation to influence this validator's view of an unrelated state.
4. The `wallet_pk` in the attestation's signed message binds the recovery to one specific wallet — replay across wallets is impossible.

The full security argument and attack walks are in YPX-018 §2.5 and §5.2.


## Appendix: Attack Scenario Analysis

### Scenario 1: Program Digest Collision

```
Attack: Create malicious_axiom-core.elf with same digest as canonical

Defense:
  program_digest = SHA3-256(entire_elf_binary)
  
  To create collision:
    → Need SHA3-256 collision
    → Security: 2^128 (computationally impossible)
    
  To create partial collision (same code, different data):
    → Full binary is hashed, including data segments
    → Any change produces different digest

ATTACK FAILED ✓
```

### Scenario 2: Nonce Replay in Different Epoch

```
Attack: Reuse nonce from epoch 5 in epoch 10

Defense:
  Uniqueness is per (client_pk, epoch, nonce)
  Different epoch → different tuple → allowed
  
  But: Same consumed_state_id cannot be reused
  If trying to replay same transaction:
    → state_id already consumed → REJECT (E_DOUBLE_SPEND)

ATTACK FAILED ✓
```

### Scenario 3: Data Availability Attack

```
Attack: Overlap witness refuses to provide data

Defense:
  Transaction is BLOCKED (money frozen)
  Attacker cannot STEAL the money
  Attacker cannot USE the money
  
  Victim's money is frozen, not lost
  If witness comes back online, money unfreezes
  
  Attacker cost:
    → Must control ALL validators in chain
    → Overlap rule introduces diversity
    → Cost grows with chain length

ATTACK CONTAINED ✓ (fail-stop)
```

### Scenario 4: Epoch Manipulation

```
Attack: Use very old or very future epoch

Defense:
  Valid range: current_epoch - MAX_DRIFT <= epoch <= current_epoch + 1
  MAX_DRIFT = 2
  
  Old epoch (< current - 2):
    → REJECT (E_INVALID_EPOCH)
    
  Future epoch (> current + 1):
    → REJECT (E_INVALID_EPOCH)

ATTACK FAILED ✓
```

### Scenario 5: Commitment Hash Length Extension

```
Attack: Find two different inputs that hash to same commitment

Defense:
  Each field has length prefix:
    hash_field(data) = H(len(data) || data)
    
  Concatenation of different fields cannot produce same hash
  because lengths are explicitly encoded
  
  Example:
    Fields A="ab", B="c" → H(2||"ab"||1||"c")
    Fields A="a", B="bc" → H(1||"a"||2||"bc")
    These are different even though "ab"+"c" = "a"+"bc"

ATTACK FAILED ✓
```

### Scenario 6: Pollution from Malicious Worldline

```
Attack: Create fake money in isolated worldline, try to spend in honest network

Defense:
  Fake money has receipts from malicious validators
  When entering honest network:
  
  Case A: No ZKP proofs
    → REJECT (E_MISSING_ZKP_PROOF)
    
  Case B: Wrong program digest
    → REJECT (E_INVALID_PROGRAM_DIGEST)
    
  Case C: Valid proofs but invalid transaction
    → axiom-core.elf would have rejected during proof generation
    → Valid proof can only exist for valid transaction
    
  Malicious worldline stays isolated

ATTACK FAILED ✓
```

### Scenario 7: Quantum Attack on Genesis Keys

```
Attack: Use quantum computer to break Genesis validator keys

Defense:
  Genesis validators use quantum-resistant algorithms:
    - Dilithium (FIPS 204): 128-bit post-quantum security
    - SPHINCS+ (FIPS 205): 128-bit post-quantum security
  
  Breaking Dilithium/SPHINCS+:
    → Requires breaking lattice problems or hash functions
    → No known quantum algorithm provides significant speedup
    → Estimated breaking time: 10,000+ years even with quantum computers
    
  Ed25519 is NOT used for Genesis:
    → Quantum vulnerability only affects non-Genesis validators
    → Those can upgrade via VBC renewal

ATTACK FAILED ✓
```

### Scenario 8: Epoch Boundary Race Condition

```
Attack: Exploit clock skew at epoch boundary for double-spend

Setup:
  - Epoch 5 ending, Epoch 6 starting
  - Validator A (fast clock): sees epoch 6
  - Validator B (slow clock): sees epoch 5
  - Attacker submits TX with state_id X to both

Defense:
  Validation order is NORMATIVE:
    Step 4: State ID Check (BEFORE Epoch Check)
    Step 5: Epoch Check (AFTER State ID Check)
  
  Execution:
    - Validator A receives TX, checks state_id X → not consumed → proceeds
    - Validator A consumes state_id X
    - Validator B receives same TX, checks state_id X → ALREADY CONSUMED
    - Validator B REJECTS (E_DOUBLE_SPEND)
    
  Even with different epoch views, state_id is the ultimate defense.

ATTACK FAILED ✓
```

### Scenario 9: VBC from Compromised Genesis Key

```
Attack: Compromise 1 Genesis key, issue malicious VBCs

Defense (Containment, not Prevention):
  
  What attacker CAN do:
    - Issue VBCs for malicious validators
    - Malicious validators join witness sets
    
  What attacker CANNOT do:
    - Create money (axiom-core.elf + ZKP still enforced)
    - Double-spend (state_id still enforced)
    - Bypass validation (ZKP still required)
    
  Time-limited damage:
    - Malicious VBCs expire in ≤3 years
    - Honest Genesis validators stop using compromised key
    - Network heals over time
    
  Threshold:
    - Single key compromise: containable
    - 4+ keys compromised: catastrophic (JFP fails)

ATTACK CONTAINED ✓ (damage limited, self-healing)
```

### Scenario 10: Network-Wide Freeze Attempt

```
Attack: Try to freeze the entire AXIOM network

Defense:
  AXIOM is NOT a blockchain with global state.
  
  Each wallet has independent state chain:
    - Wallet A's freeze does NOT affect Wallet B
    - No global consensus required for normal transactions
    
  To freeze Wallet X:
    - Must control ALL overlap witnesses in X's history
    - Overlap rule introduces diversity over time
    - Cost grows exponentially with chain length
    
  To freeze "entire network":
    - Would need to control overlap witnesses of ALL wallets
    - Practically impossible given validator diversity
    
  Catastrophic scenario (most validators offline):
    - Recovery Mode activates (White Paper)
    - No human intervention required

ATTACK INFEASIBLE ✓ (for network-wide freeze)
```

### Scenario 11: Parallel-Proof Double-Spend

```
Attack: Submit same state_id to multiple validators simultaneously
        Get multiple valid ZKP proofs before state is marked consumed

Defense:
  wallet_seq provides sequential ordering:
  
  Setup:
    - Current wallet state: wallet_seq = 5
    - Attacker submits TX_A and TX_B simultaneously
    - Both claim wallet_seq = 6 (prev was 5)
    
  Execution:
    - TX_A processed first, gets valid proof with wallet_seq = 6
    - TX_A completes, state now shows wallet_seq = 6
    - TX_B's proof claims prev_wallet_seq = 5
    - But current state shows wallet_seq = 6
    - TX_B is REJECTED (prev_wallet_seq mismatch)
    
  Even if both get proofs:
    - First to complete wins
    - Second is invalidated by wallet_seq check
    - ZKP proves "Core saw seq=5 at execution time"
    - But spending requires current state to match

ATTACK FAILED ✓
```

### Scenario 12: Core Bypass via Fake wallet_seq

```
Attack: Lambda bypasses Core, guesses wallet_seq

Defense:
  wallet_seq is verified inside Core:
    - Core checks: input wallet_seq == prev_wallet_seq + 1
    - Core outputs: new_wallet_seq
    - new_wallet_seq is included in commitment_hash
    
  If Lambda bypasses Core:
    - Lambda must guess new_wallet_seq
    - Lambda must produce valid commitment_hash
    - But commitment_hash includes Core's output
    - Without running Core, Lambda cannot know correct hash
    
  If Lambda runs modified Core:
    - Wrong program_digest detected
    - REJECTED (E_INVALID_PROGRAM_DIGEST)

ATTACK FAILED ✓
```

### Scenario 13: Quantum Attack on Regular Validator VBC

```
Attack: Use quantum computer to break Ed25519 VBC signatures

Defense:
  ALL VBCs MUST use Dilithium (quantum-safe):
    - Genesis Validators: Dilithium
    - Regular Validators: Dilithium
    - VBC Renewals: Dilithium
    
  Ed25519 is NOT permitted for VBCs:
    → No quantum-vulnerable signatures in VBC chain
    → Entire trust tree is quantum-resistant
    
  If quantum computers arrive:
    → VBCs are already safe
    → No migration needed
    → Network continues with full k=3 witnessing and redeem capability for all unaffected wallets.

ATTACK PREVENTED ✓ (by design)
```

### Scenario 14: Serialization Ambiguity Attack

```
Attack: Exploit non-canonical serialization to create hash collisions

Defense:
  AXIOM mandates CBOR (RFC 7049) with canonical rules:
    - Integers: smallest encoding
    - Map keys: sorted by byte comparison
    - No indefinite-length encodings
    - No duplicate map keys
    
  Same logical data = same bytes = same hash
  
  JSON problems don't exist:
    - Object key order is defined (sorted)
    - No whitespace ambiguity (binary format)
    - No Unicode normalization issues
    
  commitment_hash is deterministic:
    → Cannot create equivalent-but-different inputs
    → Cannot forge matching hashes

ATTACK FAILED ✓
```

### Scenario 15: zk-VM Verifier Divergence

```
Attack: Exploit differences between zk-VM implementations to cause network split

Defense:
  Network mandates identical verifier version:
    - All validators MUST use same zk-VM library version
    - Version is part of network configuration
    - Version mismatch detected in handshake
    - Mismatched validators rejected from witness sets
    
  Upgrade process:
    - New version announced with activation epoch
    - Validators upgrade before activation
    - At activation, old version rejected
    - Coordinated upgrade, not governance
    
  Result:
    - All verifiers behave identically
    - No edge case differences
    - No network splits

ATTACK PREVENTED ✓ (by configuration)
```




## 27. Validator Discovery Protocol

This section defines how clients and validators discover each other organically, without registries, authority sets, global views, or discovery services.

### 27.1 Design Principles

A system without validator learning is survivable but slow.
A system with unrestricted discovery converges into a directory.
A system with static validator reuse converges into capture.

AXIOM therefore enforces three simultaneous goals:

| Goal | Mechanism |
|------|-----------|
| **Knowledge MAY grow** | Organic hint exchange |
| **Authority MUST NOT grow** | Hints have zero consensus effect |
| **Relationships MUST remain unstable** | Randomized rotation |

**Core Invariant:**

> Knowledge never becomes authority.
> Validators are temporary partners, never permanent fixtures.

### 27.2 Two Distinct Sets Per Transaction

Each transaction carries two independent sets with strictly separated purposes:

#### 27.2.1 Witness Set (Security-Critical)

| Property | Specification |
|----------|---------------|
| **Size** | 3-5 validators |
| **Purpose** | Validate and witness the transaction |
| **Consensus effect** | Determines state continuity and validity |

**Rules:**
- All witnesses MUST sign the same canonical payload hash
- Witness set MUST overlap >=1 validator with previous transaction's witness set
- Witness selection MUST include randomness (see 26.6)

**Cross-reference:** Section 17.3 (Witness Overlap Rule)

#### 27.2.2 Known Validator Hints (KVH) (Growth-Only)

| Property | Specification |
|----------|---------------|
| **Size** | 1-3 validators |
| **Purpose** | Organic expansion of reachable validators |
| **Consensus effect** | **NONE** -- zero effect on transaction validity |

**Rules:**
- KVH entries are untrusted hints, not authorities
- KVH does not participate in consensus
- KVH may be ignored or discarded by recipients

**This separation is absolute and non-negotiable.**

### 27.3 Bootstrap (Initial Validator Knowledge)

At wallet creation, the client receives an initial validator set. This is the **ONLY** time a validator list is externally supplied.

#### 27.3.1 Bootstrap Sources

| Source | Description |
|--------|-------------|
| **Third-party wallet** | Wallet software includes seed validators |
| **Offline bundle** | Pre-packaged validator list |
| **Trusted bootstrap service** | Initial contact point |

#### 27.3.2 Bootstrap Constraints

| Constraint | Specification |
|------------|---------------|
| **One-time only** | No protocol-level re-bootstrapping |
| **Minimum size** | 3 validators (sufficient for k=3) |
| **No authority** | Bootstrap validators have no special status |

**After bootstrap, all growth is endogenous and probabilistic.**

### 27.4 Normal Transaction Flow with Organic Growth

Given previous witness set W(n-1), client constructs TX(n):

```
Step 1: Witness Selection

Client selects witness set W(n):
- Size: 3-5
- MUST include >=1 validator from W(n-1)
- Remaining validators: randomly selected from known pool

Step 2: Attach Client Hints

Client attaches KVH_client:
- Size: 1-3 hints
- Randomly selected from known pool
- Optional (MAY be empty)

Step 3: Send Transaction

Client sends identical TX(n) payload to all witnesses in W(n)

Step 4: Validator Processing

Each witness validator:
1. Verifies previous state
2. Checks local enforcement
3. Signs canonical payload hash
4. Processes KVH_client:
   - If hint already known -> drop silently
   - If hint new -> store as candidate
5. Includes KVH_validator in reply (MANDATORY)

Step 5: Client Receives Replies

Client:
1. Verifies signatures
2. Stores KVH_validator using same rule:
   - drop-known, store-new, no notification
```

**Neither side acknowledges what was stored.**

#### 27.4.1 Transaction Flow Diagram

```
+------------------------------------------------------------------+
|                   ORGANIC GROWTH FLOW                             |
+------------------------------------------------------------------+
|                                                                  |
|  Previous TX witnessed by: {V1, V2, V3}                          |
|  Client known pool: {V1, V2, V3, V4, V5, V6, V7}                 |
|                                                                  |
|  TX(n) Selection:                                                |
|  + Required overlap: V2 (from previous)                          |
|  - Random picks: V5, V7                                          |
|                                                                  |
|  Witness Set W(n): {V2, V5, V7}                                  |
|                                                                  |
|  Client                                                          |
|    |                                                             |
|    | TX(payload, KVH_client[random])                             |
|    +---> V2                                                      |
|    +---> V5                                                      |
|    +---> V7                                                      |
|                                                                  |
|  Replies include: KVH_validator[random subsets]                  |
|                                                                  |
|  Knowledge pools update silently (TTL, caps enforced)            |
|                                                                  |
+------------------------------------------------------------------+
```

### 27.5 Mandatory Hint Refresh

Validators MUST include hints in transaction replies. This ensures continuous discovery under churn.

#### 27.5.1 Requirements (Normative)

| Requirement | Specification |
|-------------|---------------|
| **Hint count** | 1-3 per reply |
| **Mandatory** | MUST include (not optional) |
| **No self-inclusion** | Validator MUST NOT include own contact |
| **Source** | Sampled from local peer-hint cache |
| **Effect on validity** | **NONE** -- non-consensus metadata |

#### 27.5.2 Hint Payload Format

```
KVH_validator := {
  hints: [
    { validator_id, name, carriers, last_seen },
    ...
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| **validator_id** | String | Unique identifier (`email/checksum+salt` format) |
| **name** | String | Human-friendly display name |
| **carriers** | Array\<String\> | One or more carrier URIs for reaching this validator |
| **last_seen** | u64 (optional) | When validator last responded (Unix timestamp) |

**Carrier URI Format:**

Each carrier URI uses the scheme `type:address`:

| Carrier Type | URI Example | Gateway |
|-------------|-------------|---------|
| **email** | `email:alpha@axiom` | ANTIE |
| **uncle** | `uncle:192.168.1.100:9001` | UNCLE (direct socket) |
| **cousin** | `cousin:relay.axiom.net/alpha` | COUSIN |
| **maildir** | `maildir:/path/to/maildir` | ANTIE (local dev) |

Additional carrier schemes are defined in Yellow Paper extensions
(YPX) rather than enumerated here, so the base spec stays focused
on the consensus-relevant transports. See
`docs/AXIOM_YPX-019_FATMAMA_CARRIER.md` for the `fatmama:` scheme —
a cluster-scoped, inbound-only TCP carrier that complements `email:`
when clients address a known validator cluster directly. Future
carrier schemes follow the same pattern: one YPX per scheme, the
base spec unchanged.

A validator MAY have multiple carriers. Clients SHOULD try carriers in order of preference and availability. Carrier staleness does not invalidate the hint — the validator may still be reachable via a different carrier.

#### 27.5.3 Retention Policy

| Policy | Specification |
|--------|---------------|
| **Maximum hints** | Capped per client (e.g., 100-500) |
| **TTL** | Hints expire after period of non-use |
| **Pruning method** | Natural (usage-based), not active GC |
| **Overflow behavior** | Oldest/least-used hints evicted |

#### 27.5.4 Poisoning Resistance

Bounded retention and random sampling prevent:
- **Enumeration amplification** -- Attacker cannot flood network with fake hints
- **Sybil injection** -- Capped storage limits fake validator proliferation
- **Correlation attacks** -- Random selection obscures hint source

**Stale or unreachable hints are permitted temporarily** -- they are pruned through natural usage patterns rather than active garbage collection.

### 27.6 Randomized Validator Rotation

To prevent structural capture and long-term correlation, validator selection MUST incorporate randomness.

#### 27.6.1 Rotation Requirements

| Requirement | Specification |
|-------------|---------------|
| **Witness selection** | MUST be randomized (excluding required overlap) |
| **KVH selection** | SHOULD be randomized |
| **Consecutive reuse** | SHOULD be avoided |
| **Preference ordering** | NOT protocol-defined |

#### 27.6.2 Why Randomness Is Mandatory

Randomness prevents:

| Threat | Without Randomness |
|--------|-------------------|
| **Long-term binding** | Client-validator relationships become permanent |
| **Economic capture** | Repeated selection creates dependency |
| **Graph stabilization** | Stable graph enables deanonymization |
| **Collusion formation** | Predictable selection enables coordination |

#### 27.6.3 Randomness Requirements

| Property | Specification |
|----------|---------------|
| **Global verifiability** | NOT required |
| **Local randomness** | Sufficient |
| **Source** | Client-side PRNG acceptable |

**Rationale:** Overlap enforces correctness. Capture requires sustained, predictable reuse. Local randomness breaks predictability without requiring consensus on random values.

### 27.7 Implementation Guidance (Non-Normative)

Client application developers MAY:
- Maintain curated validator seed lists
- Distribute them with client software
- Filter validators by protocol compatibility or version

These lists:
- Are treated as bootstrap hints only
- Are subject to the same random selection rules
- Do NOT grant priority or authority

**Developers MUST NOT hard-code fixed validator paths.**

Randomization remains mandatory to preserve neutrality.

### 27.8 Security and Liveness Properties

| Property | Enforcement |
|----------|-------------|
| **Double-spend prevention** | Witness overlap (17.3) |
| **Validator capture resistance** | Random rotation (26.6) |
| **Client freedom** | Client may choose from any known pool |
| **No registry formation** | Bounded, ephemeral, non-transitive hints |
| **Recovery compatibility** | Recovery diffusion unchanged (17.7) |

### 27.9 Summary: Discovery Model Overview

```
+-------------------------------------------------------------------+
|              VALIDATOR DISCOVERY MODEL                             |
+-------------------------------------------------------------------+
|  BOOTSTRAP (One-time)                                              |
|  - Initial 3+ validators from external source                      |
+-------------------------------------------------------------------+
|  WITNESS SET (Security-Critical)                                   |
|  + Size: 3-5 validators                                            |
|  + Overlap: >=1 from previous TX                                   |
|  - Selection: RANDOMIZED                                           |
+-------------------------------------------------------------------+
|  KNOWN VALIDATOR HINTS (Growth-Only)                               |
|  + Size: 1-3 per message                                           |
|  + Mandatory: YES (in validator replies)                           |
|  + Consensus effect: NONE                                          |
|  - Selection: RANDOMIZED                                           |
+-------------------------------------------------------------------+
|  RETENTION                                                         |
|  + Cap: 100-500 hints per client                                   |
|  + TTL: Usage-based expiration                                     |
|  - Pruning: Natural, not active GC                                 |
+-------------------------------------------------------------------+
```

### 27.10 Summary Invariant

> **The network grows organically, and never settles.**
>
> State continuity enforces correctness.
> Randomness enforces neutrality.
> Knowledge never becomes authority.
>
> Validators are temporary partners, never permanent fixtures.


### 27.11 Validator Status Protocol (VSP) — formerly YPX-008

> Folded into the Yellow Paper 2026-07-15 from the standalone YPX-008 (v0.1,
> Implemented). Code comments citing "YPX-008" refer to this section. Verified
> implementation surface: `ValidatorStatusRequest/Response` (`lambda/src/types.rs`),
> `ConsensusEngine::validator_status()` (`lambda/src/consensus.rs`),
> `discover_from_validator` (`sdk/client/src/discovery.rs`).

#### 27.11.1 Overview

The Validator Status Protocol (VSP) provides clients with an out-of-band mechanism
to query a validator's public status, performance metrics, and discover peer validators
before initiating a transaction.

VSP is **free** — validators MUST NOT charge for status queries.

##### 27.11.1.1 Motivation

Clients need to select validators intelligently. The existing validator_hints mechanism
(piggybacked on witness/redeem responses per §27.5) only works during active transactions.
VSP fills the gap for clients who need validator information **before** submitting a TX:

- Which validators are online and responsive?
- What proof capability does a validator have (DMAP vs ZKP)?
- What is the validator's throughput and uptime?
- Who else can the client contact? (peer referrals)

##### 27.11.1.2 Relationship to Validator Hints (§27.5)

VSP does **not** replace piggybacked validator_hints. Both mechanisms coexist:

| Mechanism | When | Cost | Scope |
|-----------|------|------|-------|
| **Validator Hints (§27.5)** | During TX (witness/redeem responses) | Free (piggybacked) | In-band peer discovery |
| **VSP (this section)** | Before TX, on demand | Free (standalone) | Out-of-band status + discovery |

Validator hints remain critical for in-flight discovery. VSP is the client-side complement
for pre-TX validator selection.

**v3.0.0-beta2: organic self-advertise via hints.** Since validators now
UPSERT a self-row into their own `validator_hints` table at boot (from
`antie.toml` `[carriers] advertise = […]`), and `get_random_hints` no
longer filters self, the hint relay path (§27.5) on its own now
propagates each operator's authoritative carrier list, `ed25519_pk`,
and `encryption_public_key` across the mesh — no VSP fetch required
for steady-state discovery. VSP is still the right tool for:

- **Cold-start discovery** before any witness traffic has flowed.
- **Liveness checks** (witness/redeem counts, uptime, fee config).
- **Direct query of a known peer** without going through a TX.

`discover_from_validator` (sdk/client/src/discovery.rs:91) currently hardcodes
the email path. When VSP latency becomes a real concern, the natural
upgrade is to have it honor `carrier_preference` (same picker used by
send/redeem/heal). No new wire format required — UMP already supports
multi-carrier dispatch via TOT.

#### 27.11.2 Protocol

##### 27.11.2.1 Request

A VSP query requires no parameters and no authentication.

**Wire format (ANTIE carrier):**
```
Subject: AXIOM/validator_status/<request_id>
Body: { "message_type": "validator_status", "request_id": "<uuid>" }
```

**IPC format (Lambda):**
```json
{ "type": "validator_status", "request_id": "<uuid>" }
```

##### 27.11.2.2 Response

The validator returns its public profile plus up to 3 known peer validators.

```json
{
  "type": "validator_status_result",
  "request_id": "<uuid>",
  "name": "validator-alpha",
  "validator_id": "<64-hex-chars>",
  "proof_cap": "dmap",
  "carriers": ["email:alpha@axiom.network"],
  "core_version": "Kyoto/1.01/DMAP",
  "uptime_secs": 86400,
  "witness_count": 12345,
  "redeem_count": 6789,
  "zkp_qualified": false,
  "known_validators": [
    {
      "validator_id": "beta@axiom",
      "name": "validator-beta",
      "carriers": ["email:beta@axiom.network"],
      "proof_cap": "dmap",
      "last_seen": 1710300000
    }
  ]
}
```

##### 27.11.2.3 Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Human-friendly validator name |
| `validator_id` | string | Hex-encoded 32-byte validator ID |
| `proof_cap` | string | Proof capability: `"dmap"` or `"zkvm"` |
| `carriers` | string[] | URIs for reaching this validator (format: `type:address`) |
| `core_version` | string | Core version tag (e.g., `Kyoto/1.01/DMAP`) |
| `uptime_secs` | u64 | Seconds since process start |
| `witness_count` | u64 | Total witness requests processed |
| `redeem_count` | u64 | Total redeem requests processed |
| `zkp_qualified` | bool | Whether validator passed ZKP benchmark |
| `known_validators` | ValidatorHint[] | Up to 3 peer validators (same format as §27.5 hints) |
| `fee_rate_bps` | u32 | Fee rate in basis points (50 = 0.50%) |
| `fee_valid_until` | u64 | Unix timestamp when fee schedule expires (0 = no expiry) |
| `fee_min_amount` | u64 | Minimum fee in atoms |
| `jurisdiction` | string | ISO 3166-1 alpha-2 country code (e.g., `"SG"`, `"US"`) or `"NONE"` |
| `operator_name` | string | Operator name/organization (self-reported) |
| `operator_contact` | string | Contact information (email, URL) |
| `supported_encryption` | string | Encryption for cheque delivery: `"PGP"`, `"GPG"`, or empty (none) |
| `encryption_public_key` | string | Validator's encryption public key (PGP armored block or base64) |
| `notes` | string | Free-text operator notes (announcements, ToS URL, maintenance) |

##### 27.11.2.4 Peer Referrals

Every VSP response includes up to 3 `known_validators` — the same `ValidatorHint` structure
used by §27.5 piggybacked hints. These are randomly selected from the validator's hint table
(excluding itself).

This gives clients bootstrapping capability: query one known validator, discover three more,
query those, and quickly build a full view of available validators for S-ABR selection.

#### 27.11.3 Security Considerations

##### 27.11.3.1 No Authentication

VSP queries are unauthenticated. Any client can query any validator. This is by design:
validator status is public information (validators advertise themselves to attract clients).

##### 27.11.3.2 Rate Limiting

VSP queries are subject to the same rate limiting as other requests: Lambda
enforces 100 req/min per IP; the reference ANTIE currently enforces a
per-wallet cooldown (per-IP limiting at the ANTIE layer is specified in §35.1
and not yet wired in the reference implementation). This bounds status-query
flooding.

##### 27.11.3.3 No Sensitive Data

VSP responses contain only public operational metrics. No wallet data, no keys,
no transaction details, no internal state. The `encryption_public_key` is a
public encryption key — safe to share openly.

##### 27.11.3.3.1 Encrypted Cheque Delivery (Client Convention)

Wallet addresses may carry an encryption suffix indicating the receiver supports
encrypted cheque delivery:

| Suffix | Meaning | Example |
|--------|---------|---------|
| (none) | Plaintext delivery | `bob@example.com/a1b2c3d4` |
| `-P` | PGP encryption | `bob@example.com/a1b2c3d4-P` |
| `-G` | GPG encryption | `bob@example.com/a1b2c3d4-G` |

This is a **client-level convention**, not a protocol rule. The protocol treats
`wallet_id` as an opaque string — the suffix is meaningful only to wallet
applications and ANTIE's cheque delivery logic.

When ANTIE creates a cheque for a receiver with an encryption suffix:
1. Check if the receiver's encryption public key is known (from prior redeem interaction)
2. If known: encrypt cheque email body with the receiver's key
3. If unknown: deliver plaintext (receiver has not yet registered their key)

Receivers register their encryption public key naturally through the protocol —
when they submit their first redeem request, the wallet app includes the key.
No separate registration step, no Nabla interaction.

**Validator-side encryption** uses the same mechanism. Clients check VSP's
`supported_encryption` field. If the validator supports PGP, clients can encrypt
their witness/redeem requests to the validator's `encryption_public_key`.

##### 27.11.3.4 DWP Interaction

VSP is orthogonal to Decoy Witness Protection (§5/§18). DWP protects witness identity
during transactions. VSP is pre-transaction discovery — no witness relationship exists yet.

#### 27.11.4 Implementation

##### 27.11.4.1 Lambda

- `GatewayRequest::ValidatorStatus` variant in `lambda/src/types.rs`
- `ValidatorStatusResponse` struct with all public fields
- `ConsensusEngine::validator_status()` method collects stats + hints
- Handler in `lambda/src/server.rs` routes to consensus engine

##### 27.11.4.2 ANTIE

- `"validator_status"` message type in gateway dispatch
- `handle_validator_status()` forwards to Lambda, returns response
- `send_validator_status_request()` IPC method in lambda_client

##### 27.11.4.3 Wire Format

Uses the standard CBOR IPC path (same as query_state). No new codec constants needed.

#### 27.11.5 Future Extensions

- **Fee schedule:** Validators could include their fee structure in VSP responses
- **Load metrics:** Current queue depth, average response time
- **Geographic hints:** Region/latency information for proximity-based selection
- **Uptime history:** Rolling availability percentage (7d/30d/90d)


## 28. Extension Document Registry (YPX)

The following security protocols are specified in separate Yellow Paper Extension (YPX) documents. They build on top of the base protocol defined in this Yellow Paper and add additional security guarantees for production deployment.

**The base protocol (Sections 1-27 of this Yellow Paper) operates fully without these extensions.** Transactions, witnessing, and all core functionality work as specified. The extensions add double-spend protection, money provenance tracking, and rollback prevention.

### 28.1 Implementation Phases

```
Phase 1: Base Protocol (THIS DOCUMENT)
=========================================
  Sections 1-27 of this Yellow Paper.
  
  axiom-core.elf:   cryptographic gatekeeper, CL1-CL11 validation
  Lambda:     consensus coordination, k=3 witnessing
  Gateway:    transport abstraction (ANTIE, UNCLE, COUSIN)
  VBC:        validator identity and trust chain (Section 23.13)
  S-ABR:      double-spend prevention at validator level (Section 17.10)
  ZKP:        execution attestation (Section 26)
  
  Result: AXIOM functions. Money moves. Validators witness.
  Security: k=3 witnessing with >= 2 overlap prevents same-moment double-spend.
  Limitation: no protection against rollback attacks across different
  validator sets, no money provenance tracking, no wallet state verification.
  
  Status: Implemented and running (dev network).


Phase 2: YPX-001 -- FACT chain and TARDIS Protocol
=====================================================
  Depends on: Phase 1 complete (Core, Lambda, Gateway, VBC operational)
  Builds on: Section 26.17 (base protocol FACT — single-link proof per receipt)
  
  FACT chain (extends base FACT):
    - Base protocol (26.17) provides single-link FACT: each receipt has its zk-VM proof
    - Phase 2 chains these links: trace money provenance from current holder to genesis
    - Every cheque carries proof of where the money came from
    - Cheque format extended with FACT chain links
    - Genesis checkpoint compression (bounded chain depth)
    - Scar system: unverified links cannot be checkpointed
  
  FACT proves cryptographic validity (money traces to genesis, was not created
  from nothing), not social legitimacy (where the human obtained it). The protocol
  treats all valid FACT chains equally regardless of which wallets money passed
  through. This is consistent with the White Paper's principle that "AXC does not
  encode origin" — FACT encodes mathematical proof, not moral judgement.

  TARDIS (Temporal Anchor for Rollback Detection and Integrity Sync):
    - Cascading heartbeat inside the Nabla network (YPX-003)
    - Forces Nabla gossip reconciliation at tick boundaries (5-second interval)
    - Provides maturity window (5 ticks / 25 seconds) before cheques can be CLEAN
    - Liveness proof for Nabla nodes
    - Anti-timestamp-manipulation for Nabla registrations
    - Cascade topology: binary tree with downstream approval for tick legitimacy
    - NOTE: TARDIS lives inside Nabla as a heartbeat mechanism (YPX-003 cascade
      topology). Earlier design concepts including meta-validator rotation were
      explored and rejected. See YPX-003 §0.3 for the complete design evolution
      and rejection rationale for all six previous TARDIS designs.
  
  Impact on base protocol:
    - Cheque format gains FACT chain field
    - axiom-core.elf gains FACT chain verification in CL2
    - Wallet state gains tardis_tick (protocol time) and unix_timestamp (reference)
    - Cheques never expire (cashier's cheque / traveller's cheque model — money has already
      left sender's wallet at witness time, spend is irreversible)
  
  Result: Money has provenance. Forgery requires faking history to genesis.
  Status: Specification complete (YPX-001 v0.5, YPX-003 v0.9.2). Implementation complete (Phases 1-8, 263+ tests).


Phase 3: YPX-002 -- ∇ Nabla Verification Protocol
==================================================
  Depends on: Phase 2 complete (FACT chain and TARDIS operational)
  
  Symbol: ∇ (Unicode U+2207) -- the mathematical gradient operator,
  representing "where is this wallet now?" The inverted triangle also
  visually suggests a funnel: many transactions flow in, one current 
  state comes out.
  
  Nabla (wallet state verification service):
    - New TrustMesh participant role (same VBC trust chain as validators)
    - Wallet state registry: one entry per wallet (current state + tx_hash)
    - Gossip propagation network between Nabla nodes
    - TARDIS tick checkpoints for consistency verification
    - BANNED wallet mechanism for proven double-spend
    - FACT scar system integration (market-driven verification)
  
  Verification protocol:
    - Sender registers with 1 Nabla node after S-ABR witness (k=3 receipt)
    - Sender's wallet stores registration info: {node_name, node_id, ip:port}
    - Sender MAY include nabla_hint on the final validator's witness request
      (after S-ABR round 1 completes). The hint is included in the cheque as
      optional metadata: {node_name, address}. Not signed, not verified.
    - Receiver queries any 3 Nabla nodes by (wallet_pk, state_id)
      If nabla_hint present: receiver tries hint node first (fast path)
      If absent or unreachable: receiver queries any 3 nodes (gossip path)
    - All 3 must agree (n of n), maturity wait (5 ticks / 25s), FACT chain trace
    - Verification and redeem are separate actions:
      receiver can query (read-only), wait for CLEAN, then redeem when ready
    - Client strongly recommends verification on every receive

  Cheque status model (YPX-003):
    - CLEAN: registered, matured (5 ticks / 25 seconds), no conflict
    - SCARRED: unverified or immature — accept at own risk
      Receiver may redeem immediately (scarred FACT) and heal scar later
    - REJECTED: double-spend conflict detected — do not accept

  Partition handling:
    - Commerce continues without Nabla (client backup/revert model)
    - Gossip split: receiver asks sender for bridge code (encoded Nabla IP:port)
    - Receiver's Nabla connects to sender's Nabla → partition heals (YPX-003 §9)
    - Post-partition verification, healing, or burn
  
  Impact on base protocol:
    - Cheque gains optional nabla_hint field (performance hint, not required for correctness)
    - New node type joins TrustMesh (Nabla node)
    - Client verification protocol (recommended, not mandatory)
    - Receiver-triggered bridge for gossip split healing (YPX-003 §9)
  
  Result: Full double-spend protection. Rollback prevention. 
  Production-grade security.
  Status: Specification complete (YPX-002 v0.1, YPX-003 v0.9.2). Implementation complete (Phases 1-8, 263+ tests).

  IMPORTANT — Relationship to White Paper philosophy:

  Nabla does not contradict the White Paper's "no global state" and "no wallet
  state sharing" principles. These principles apply to the validator layer and
  remain architecturally correct and unchanged.

  Nabla is not a global wallet. The wallet lives with the client. Nabla is a
  decentralised verification network — anyone can run a Nabla node, nobody owns
  the network, no node is privileged. Nabla answers one question: "have I seen
  this state before?" It is a witness, not a ledger.

  The base protocol (Phase 1) is fully functional without Nabla. All transactions
  proceed; cheques are SCARRED rather than CLEAN. Receivers accept or reject based
  on their own risk assessment, proportional to transaction value — exactly as
  humans have always done with physical money. Nobody checks a $5 bill for
  counterfeits. Everyone verifies a $500 payment.

  S-ABR (Section 26.17) is the first line of double-spend defense, consistent with
  the White Paper's short-window containment model (White Paper §4.11). Nabla closes
  the remaining cross-validator-set gap — when a double-spend goes to entirely
  different validator sets with no overlap, those validators have no knowledge of
  each other's transactions. Nabla detects this.

  Why Nabla is necessary:

  The fundamental design problem is that, with current technology and without
  specialised hardware, we must assume the worst of human behaviour. People will
  attempt to cheat. This is not a technology problem — it is a human behaviour
  problem that every payment system in history has faced.

  In theory, double-spend prevention could be solved at the hardware level: a
  secure enclave or HSM that physically refuses to sign two transactions from the
  same wallet state. This is how chip-and-PIN cards work — the silicon enforces
  the rules.

  AXIOM does not require specialised hardware because doing so would:
    1. Create manufacturing dependency (chip makers can be pressured or sanctioned)
    2. Create access inequality (people in crisis zones cannot obtain special chips)
    3. Require trust in hardware makers (backdoors, supply chain compromise)
    4. Create obsolescence risk (hardware fails, architectures are discontinued)

  These dependencies violate AXIOM's survival-grade design principles. AXIOM must
  work on normal hardware that everyone already owns — a phone, a laptop, a desktop.
  Nothing special. Nothing from a specific vendor. Nothing that can be export-
  controlled, sanctioned, or discontinued.

  The cost of this accessibility choice is that software on general-purpose hardware
  cannot physically prevent double-signing. Nabla is the engineering cost of that
  choice. It makes cheating economically irrational on hardware that everyone
  already owns, without requiring anyone to trust a chip manufacturer with their
  financial sovereignty.

  If hardware-enforced signing ever becomes universally available, affordable, and
  trustworthy — with no single manufacturer dependency and no export control risk —
  then Nabla becomes unnecessary and the entire network runs CLEAN by default.
  The protocol is designed to accommodate this future. But we do not wait for it.
  We do not depend on it. We build for the hardware that exists today.
```

> **Design Philosophy: Extensions and White Paper Consistency**
>
> The base protocol (Phase 1) is fully functional without Nabla. All transactions proceed; cheques are SCARRED rather than CLEAN. Receivers accept or reject based on their own risk assessment, proportional to transaction value — exactly as humans have always done with physical money.
>
> Nabla does not contradict the White Paper's "no global state" principle. Nabla is a decentralised, opt-in verification layer. The base protocol maintains no global state and functions fully without Nabla. Nabla exists because, with current technology and without specialised hardware, the protocol must assume the worst of human behaviour — people will attempt to cheat. Nabla makes cheating economically irrational.
>
> S-ABR (§26.17) is the first line of double-spend defense, consistent with the White Paper's short-window containment model. Nabla closes the remaining cross-validator-set gap. Both defences exist because the protocol assumes adversarial behaviour.
>
> Nabla (Phase 3) targets normal consumer hardware — phones, laptops, desktops — where software cannot physically prevent double-signing. With specialised hardware (secure enclaves, HSMs) that enforce single-use state transitions, Nabla would be unnecessary. However, requiring specialised hardware introduces manufacturing dependency, access inequality, trust in hardware makers, and obsolescence risk — all of which violate AXIOM's survival-grade design principles. Nabla is the engineering cost of accessibility.
>
> The extensions (FACT, Nabla, TARDIS) implement the White Paper's philosophy, not contradict it. The White Paper defines what must survive. The extensions provide the mechanisms that make survival possible under adversarial conditions, without creating centralisation, global state, or dependency.

> **FACT and the "AXC Does Not Encode Origin" Principle**
>
> FACT proves cryptographic validity (money traces to genesis, was not created from nothing), not social legitimacy (where the human obtained it). The protocol treats all valid FACT chains equally. This is consistent with the White Paper's principle that "AXC does not encode origin" — FACT encodes mathematical proof, not moral judgement.

### 28.2 Document References — the YPX family map

This table is the authoritative map of every Yellow Paper Extension number ever
used, including retired numbers, so that a reader (or a code comment citing
"YPX-NNN") can always find where a number's content lives today.

| Document | Title | Status | Depends On |
|----------|-------|--------|------------|
| This Yellow Paper | Base Protocol Specification | Live, normative | -- |
| YPX-001 | FACT Chain (§1). Early TARDIS sketch (§2) superseded by YPX-003 | v0.5 Implemented | Yellow Paper Phase 1 |
| YPX-002 | ∇ Nabla Verification Protocol | v0.1, implemented | YPX-001 |
| YPX-003 | TARDIS Cascade Protocol; supersedes YPX-001 §2, tells the full design evolution (§0.3: six rejected designs) | v0.9.2 Consolidated | YPX-002 |
| YPX-004 | *(number retired)* Nabla VRF Election & Partition Detection | Never written as a standalone spec. Partition detection landed in YPX-003 §9; node lifecycle/NBC/gossip in YPX-002 and AXIOM_GUIDE_Nabla.md. The VRF-election concept for reserve distribution was abandoned — that role went to the oracle protocol (YPX-012) | -- |
| YPX-005 | *(number retired)* Oracle Platform Distribution, original draft | Superseded by YPX-012, which carries the full protocol | -- |
| YPX-006 | DMAP — Deterministic Memory Attestation Protocol | v0.4 Implemented | YP §31 |
| YPX-007 | Receiver-Defined Security & Multi-Address Wallet | v0.4 Implemented | YPX-006 |
| YPX-008 | Validator Status Protocol (VSP) | v0.1 Implemented; folded into this document as §27.11 | YP §27 |
| YPX-009 | Silicon Pulse — Core-Initiated Lambda Audit | v0.6.2; §1-12 implemented, production activation gated to multi-host deployment (KI#31) | YPX-002, 003, 006 |
| YPX-010 | Ark Mode Confidence Index | v0.3 Implemented in Core (`ark.rs`); academic companion: papers/paper3 | YPX-007 |
| YPX-011 | Genesis Integrity & Supply Provenance | v0.1; implemented in Core (`genesis_integrity.rs`) | YPX-001, 002 |
| YPX-012 | Oracle Distribution Protocol | v0.3 Implemented; supersedes YPX-005 | YPX-001, 007, 008 |
| YPX-013 | Console Engine — Core-Signed Governance Chain | v1.0 Draft; Core engine implemented (`console.rs`) | YP §21 |
| YPX-014 | Nabla Txid Service | Superseded by YPX-018 (single-bloom design; its design history lives there) | -- |
| YPX-015 | Performance Engineering | Findings log (soak-test driven), not a normative spec | -- |
| YPX-016 | Witness Response Cache | v1.0 Implemented; role reduced by YPX-018 (fast-path retry only) | -- |
| YPX-017 | *(number never assigned)* | -- | -- |
| YPX-018 | CLARA & Tiered Bloom Memory | v1.0 Implemented (CLARA + bloom eras: `nabla/src/clara.rs`, `bloom_era.rs`); normative source for YP §39.9; supersedes YPX-014 | YPX-001, 003, 011, 013 |
| YPX-019 | FATMAMA Carrier Scheme | Production role superseded by TOT (AXIOM_DESIGN_TOT.md); SMTP dev tool remains | -- |
| YPX-020 | HAL — Help Absent Lambda (dead-overlap resurrection) | §2 completion model shipped (dev network); spec pre-mainnet DRAFT | YPX-018 companion |
| YPX-021 | OODS — Operational Observer Determination System | Detection + receipt health-flag gate shipped; §5 Core-verified size-proof deferred | consumed by YPX-022 |
| YPX-022 | RECALL — completed-but-undelivered payment recovery | Implemented (Core + SDK + Nabla), deployed on dev; recall-race soak pending | YPX-018, 020, 021 |
| YP Errors | Error contract companion (AXIOM_YellowPaper_Errors.md) | Draft; deliberately not a YPX (client-facing contract) | Yellow Paper |
| YP SDK | Client SDK companion (AXIOM_YellowPaper_SDK.md) | Draft; deliberately not a YPX (no validator reads it) | Yellow Paper |

Related non-YPX documents: gateway specifications live in the design-doc family
(`AXIOM_DESIGN_ANTIE.md`, `AXIOM_DESIGN_UNCLE.md`, `AXIOM_DESIGN_COUSIN.md`,
`AXIOM_DESIGN_TOT.md`), and the Nabla implementation guide is
`AXIOM_GUIDE_Nabla.md`.

### 28.3 Dependency Chain

```
Yellow Paper (Phase 1)
    |
    |--- axiom-core.elf, Lambda, Gateway, VBC, S-ABR, ZKP
    |    (base protocol, transactions work)
    |
    v
YPX-001 (Phase 2)
    |
    |--- FACT chain in cheques
    |    (money provenance — cryptographic validity, not social origin)
    |
    v
YPX-002 + YPX-003 (Phase 3)
    |
    |--- YPX-002: Nabla nodes, gossip, wallet state registry
    |    (double-spend verification, rollback prevention)
    |--- YPX-003: TARDIS cascade heartbeat inside Nabla
    |    (gossip synchronisation, maturity window, liveness proof)
    |
    v
YPX-012 (Phase 4 — Oracle Distribution)
    |
    |--- 11-platform oracle distribution (k=5, 48h maturity, 5 AXC cap)
    |--- supersedes the YPX-005 draft; rates operator-configured
    |
    v
Later extensions (registry in 28.2):
    DMAP (006) · wallet tiers (007) · VSP (008) · Silicon Pulse (009)
    Ark CI (010) · genesis provenance (011) · Console (013)
    CLARA + tiered bloom (018) · HAL (020) · OODS (021) · RECALL (022)
    |
    v
Production-grade AXIOM
```

As of v2.11.13, oracle claim processing is an operator decision configured in Lambda's OracleConfig (lambda-config.toml). When enabled, Lambda auto-renews the validator's VBC every 24 hours (vbc_renewal_interval_secs = 86400) via standard CL8 renewal. The admin /stats endpoint reports oracle_qualified to indicate whether this validator accepts oracle claims. Oracle is disabled by default — operators must explicitly set enabled = true. Reference: YPX-012 §2.5.

**Oracle Conversion Rates — Operator-Configurable by Design (v2.11.13):**
Oracle conversion rates (credits → AXC payout per platform) are configured in Lambda's `OracleConfig.conversion_rates` (lambda-config.toml), NOT hardcoded in Core. This is a deliberate design decision:
- Core enforces the **5 AXC per claim cap** (`ORACLE_MAX_PAYOUT_PER_CLAIM`) — this is the safety net, baked into the ELF.
- Operators set rates based on market conditions and platform contribution value.
- No operator can exceed the 5 AXC cap regardless of configured rates.
- The oracle reserve pool (88M AXC Market Allocation) is distributed over decades; rate flexibility allows adaptation without Core updates.
- Reference: YPX-012 §3 ("payout_amount computed by Lambda from OracleConfig.conversion_rates").

### 28.4 Note for Implementers

Phases are strictly sequential. Do not implement Phase 2 before Phase 1 is stable. Do not implement Phase 3 before Phase 2 is operational.

The base protocol (Phase 1) is designed to be functionally complete without extensions. A deployment running only Phase 1 can process transactions, validate witnesses, and enforce S-ABR overlap rules. The extensions add security layers that become critical at scale and in adversarial environments.

The research document (AXIOM Security Research: VBC, FACT, TARDIS, Nabla) contains the full design rationale, attack analysis, and rejected approaches that led to the extension specifications. It should be read alongside the YPX documents for context.


## 29. Validator Operations & Maintenance

This section defines the operational requirements for running an AXIOM validator in production. Unlike testnet environments where data can be freely discarded, production validators operate under real-world constraints: regulatory compliance, storage costs, audit requirements, and jurisdictional law.

### 29.1 Design Principle

AXIOM is a protocol, not a jurisdiction. The protocol defines what data a validator MUST retain for correct operation. Beyond that minimum, retention policy is the **operator's decision** based on their local regulatory requirements.

The protocol takes no position on what laws apply to a validator operator. It provides the mechanisms for operators to comply with whatever retention requirements they face.

### 29.2 Data Categories

A validator stores four categories of data, each with different retention characteristics:

**Category A — Active State (MUST retain, cannot delete)**

| Data | Description | Size characteristic |
|------|-------------|-------------------|
| Current wallet state | Latest balance, wallet_seq, state_id per wallet | O(wallets) — bounded |
| Most recent receipt per wallet | Needed for S-ABR overlap verification | O(wallets) — bounded |
| VBC bundle | Validator's own identity certificate | Fixed, ~52KB |
| Configuration | Keys, carrier config, Lambda settings | Fixed, <1KB |

Category A data defines the validator's operational state. Deleting any of it breaks protocol correctness. Total size is proportional to the number of active wallets, not transaction volume. For 100,000 active wallets at ~1KB per wallet state + receipt, Category A is approximately 200MB regardless of how many transactions have been processed.

**Category B — Historical Receipts (protocol-optional, operator-configurable)**

| Data | Description | Default retention |
|------|-------------|------------------|
| Superseded receipts | Receipts for wallet states that have since advanced | Configurable |
| Witness records | Log of all transactions this validator witnessed | Configurable |
| Redeem records | Log of all cheque redemptions processed | Configurable |

Once a wallet advances from state S₁ → S₂, receipts referencing `consumed_state_id = S₁` are no longer needed by the protocol. No valid transaction can reference S₁ again — Core rejects stale state IDs. However, these records may be required by:

- Local financial regulations (e.g., 5-year retention under EU AMLD, 7-year under US BSA/AML)
- Tax authorities requiring transaction history
- Court orders or legal discovery
- Operator's own audit and reconciliation needs

**Category C — Transport Artifacts (delete after processing)**

| Data | Description | Safe to delete |
|------|-------------|---------------|
| Processed maildir messages | Inbound messages already applied to state | Immediately after processing |
| Outbound message copies | Responses already delivered | After delivery confirmation |
| Temporary files | Processing artifacts | Immediately |

These are pure transport artifacts with no protocol significance. Once a message has been processed and its effects applied to state, the raw message serves no protocol purpose. Operators MAY retain these for audit trails per Category B policy.

**Category D — Operational Metrics (operator discretion)**

| Data | Description | Default retention |
|------|-------------|------------------|
| stats.json | Performance counters, timing data | Overwritten on restart |
| Log files | ANTIE/Lambda runtime logs | Configurable |
| SQLite WAL checkpoints | Database write-ahead log | Managed by storage engine |

### 29.3 Retention Configuration

Operators configure retention policy in `lambda.toml`:

```toml
[retention]
# Category B: Historical receipts
# How long to keep receipts after wallet state advances past them.
# Set according to local regulatory requirements.
# "forever" = never delete (maximum compliance)
# Duration examples: "7y" (7 years), "5y", "90d", "0" (delete immediately)
receipt_retention = "7y"

# Category B: Witness/redeem logs
witness_log_retention = "7y"

# Category C: Processed transport messages
# Most operators MUST set this to "0" (immediate deletion) unless local regulation requires audit trail retention.
processed_message_retention = "0"

# Category D: Log files
log_retention = "30d"

# Storage maintenance schedule
# How often the maintenance task runs (e.g., "1h", "6h", "24h")
maintenance_interval = "6h"

# Maximum total storage before maintenance becomes aggressive
# When exceeded, Category C is purged immediately regardless of retention setting
storage_warning_threshold = "50GB"
storage_critical_threshold = "100GB"
```

### 29.4 Maintenance Task

The validator SHOULD run a periodic maintenance task that:

1. **Identify superseded receipts** — For each wallet, find receipts whose `consumed_state_id` no longer matches the wallet's current state. These are candidates for archival/deletion per Category B policy.

2. **Purge processed transport messages** — Delete maildir messages in `cur/` that have been successfully processed, per Category C policy.

3. **Compact storage** — Trigger WAL checkpoint (`PRAGMA wal_checkpoint(TRUNCATE)`) to reclaim space from the write-ahead log. SQLite handles page-level compaction automatically; periodic `VACUUM` may be run for full defragmentation.

4. **Archive if configured** — Before deletion, optionally write superseded receipts to a compressed archive file for long-term regulatory storage. Archive files are append-only and can be stored on cheaper/slower media.

5. **Report metrics** — Log storage usage, records purged, and archive size.

```
Maintenance flow:

  [Periodic timer fires]
       │
  ┌────┴────┐
  │ Scan DB │ → identify superseded receipts
  └────┬────┘   (wallet has advanced past their state_id)
       │
  ┌────┴────────────────┐
  │ Check retention age │ → is receipt older than receipt_retention?
  └────┬────────────────┘
       │ yes
  ┌────┴──────────┐
  │ Archive?      │ → if archive_path configured, append to archive
  └────┬──────────┘
       │
  ┌────┴──────────┐
  │ Delete record │ → remove from active DB
  └────┬──────────┘
       │
  ┌────┴──────────────┐
  │ Purge transport   │ → delete processed maildir files
  └────┬──────────────┘
       │
  ┌────┴──────────────┐
  │ Compact storage   │ → reclaim disk space
  └───────────────────┘
```

### 29.5 Storage Architecture

Lambda uses **SQLite/SQLCipher** (AES-256 encryption at rest) as its storage backend. Two separate database files:

- **Transaction DB** (`lambda.db`) — All wallet states, receipts, fees, and S-ABR records. Uses `PRAGMA locking_mode = EXCLUSIVE` (single-process access).
- **Management DB** (`management.db`) — Placeholder for future console/JFP. Uses `PRAGMA locking_mode = NORMAL` to allow concurrent reads from management tools.

Encryption keys are derived deterministically from the validator's Ed25519 private key using BLAKE3 with domain separation. No additional key management is required.

SQLite format has been stable since 2004 and is committed to backward compatibility through 2050+. WAL mode provides crash safety and good concurrent read performance.

See `docs/AXIOM_REF_LambdaERD_v1_0.md` for the complete schema, ERD, and table descriptions.

### 29.6 Regulatory Compliance Notes

AXIOM validators may qualify as Money Service Businesses (MSBs), Payment Service Providers (PSPs), or equivalent under various jurisdictions. Operators are solely responsible for:

- Determining which regulations apply to their operation
- Setting retention periods that satisfy all applicable requirements
- Maintaining audit trails as required by their regulators
- Responding to lawful data requests from authorities

The protocol provides the **mechanisms** for compliance (configurable retention, archival, export) but makes no representations about what constitutes compliance in any jurisdiction.

### 29.7 Operator Checklist

Before going live, a validator operator MUST complete all of the following:

- [ ] Set `receipt_retention` and `witness_log_retention` per local law
- [ ] Configure `storage_warning_threshold` appropriate to their hardware
- [ ] Set `processed_message_retention = "0"` unless audit trail is required
- [ ] Verify maintenance task runs on schedule
- [ ] Test that the validator restarts correctly after maintenance (state intact)
- [ ] Document their retention policy for regulatory purposes
- [ ] Set up monitoring/alerting on storage usage


## 30. Group Wallet

A group wallet is a wallet shared by multiple members, where incoming funds are
automatically distributed by percentage. Group wallets use the same wallet_id
format, the same Core validation, and the same cheque model as personal wallets.
The only difference is that Core enforces additional rules on who can withdraw
and how much.

### 30.1 Purpose

Group wallets serve two functions in AXIOM:

1. **DEED distribution.** The Protocol DEED wallet and Implementation DEED wallet
   are group wallets. Fees collected from the network are automatically split
   among contributors by their share percentage.

2. **Shared pools.** Any group of users can create a group wallet for shared
   expenses, team treasuries, cooperative funds, or any arrangement where
   multiple people share ownership of a pool with defined percentages.

### 30.2 Structure

```
GroupMember {
    member_pk:    Vec<u8>,    // member's public key (identity)
    share_bps:    u16,        // share in basis points (10000 = 100%)
    available:    u64,        // atoms allocated but not yet withdrawn
}
```

A group wallet's WalletState is identical to a personal wallet, with the
addition of a members list:

```
WalletState {
    public_key:   Vec<u8>,           // group wallet's public key
    balance:      u64,               // current balance in atoms
    wallet_seq:   u64,               // monotonic sequence number
    state_id:     [u8; 32],          // hash of current state
    auth_hash:    Option<[u8; 32]>,  // optional owner protection

    // Group wallet fields (None for personal wallets)
    members:      Option<Vec<GroupMember>>,  // max 32 members
}
```

### 30.3 Protocol Constants

```
MAX_GROUP_MEMBERS:   32
TOTAL_SHARE_BPS:     10000   (100.00%)
```

### 30.4 Invariants (Core Enforced)

The following rules are enforced by Core on every operation involving a
group wallet. Violation of any rule causes Core to reject the transaction.

```
Rule 1:  members.len() >= 2 and members.len() <= 32
Rule 2:  sum(all share_bps) == 10000
Rule 3:  Members list is immutable after wallet creation
Rule 4:  sum(all available) == balance (checksum, always)
Rule 5:  Withdrawal must include group_member_index identifying the member
Rule 6:  Withdrawal amount must be <= that member's available
Rule 7:  Each member_pk must be unique (no duplicates)
Rule 8:  Each share_bps must be > 0 (no zero-share members)
```

### 30.5 Private Key Model

The group wallet has one keypair, like any wallet. The private key is shared
among all members. This is the members' responsibility — AXIOM does not
manage key distribution.

```
Every member holds:
  1. Group wallet private key (shared, for signing withdrawals)
  2. Their own personal wallet private key (their identity)
```

Security does not depend on key secrecy. It depends on Core enforcement:

```
Has group private key, but not in members list:
  → Cannot happen (members list is immutable, cannot be removed)

Has group private key, tries to withdraw to someone else's wallet:
  → Core rejects (destination must derive from a member_pk in the list)

Has group private key, tries to withdraw more than their share:
  → Core rejects (amount must be <= their available)

Non-member obtains group private key:
  → Useless (can only withdraw to member wallet_ids, within member shares)
```

The private key is necessary but not sufficient. You need the key AND be in
the members list AND withdraw to your own wallet AND within your share.

### 30.6 Receiving Funds (Cheque Redeem)

When a cheque is redeemed into a group wallet, the incoming amount is
immediately distributed to all members by their share_bps. The group
wallet's balance reflects the total, and the sum of all member available
amounts must equal the balance at all times.

```
Example: Group wallet receives 10,000 atoms

  Members:
    Alice:   5000 bps (50%)
    Bob:     3000 bps (30%)
    Charlie: 2000 bps (20%)

  Distribution:
    Alice.available   += 10000 × 5000 / 10000 = 5,000
    Bob.available     += 10000 × 3000 / 10000 = 3,000
    Charlie.available += 10000 × 2000 / 10000 = 2,000

  Checksum: 5000 + 3000 + 2000 = 10,000 = balance ✓
```

**Remainder handling.** Integer division may produce a remainder. The
remainder atom(s) are given to the member at index `tx_hash[0] % members.len()` (modulo).
This is deterministic (same tx_hash always gives remainder to same member)
and does not need to be recorded separately. The checksum still holds.

```
Example: 10,001 atoms received

  Alice:   10001 × 5000 / 10000 = 5,000
  Bob:     10001 × 3000 / 10000 = 3,000
  Charlie: 10001 × 2000 / 10000 = 2,000
  Total distributed: 10,000
  Remainder: 1 atom → tx_hash[0] % 3 → winner gets +1

  Checksum: sum(available) == 10,001 == balance ✓
```

### 30.7 Withdrawing (Sending to Own Wallet)

To withdraw, a member signs a normal CL1 transaction from the group wallet
to their own personal wallet. The transaction includes a `group_member_index`
field in PublicInputs identifying which member is withdrawing. Core validates
the transaction with additional group wallet rules.

```
Alice withdraws 3,000 atoms (Alice is member index 0):

  1. Alice signs CL1 transaction:
     from:   group wallet (using shared private key)
     to:     Alice's wallet_id (derived from her member_pk)
     amount: 3,000
     group_member_index: 0

  2. Core validates:
     Signature valid (group wallet's public key)              ✓
     group_member_index 0 exists in members list              ✓
     Amount <= Alice.available (3000 <= 5000)                 ✓
     Checksum: sum(available) == balance                      ✓

  3. State update:
     Alice.available  -= 3,000  (now 2,000)
     balance          -= 3,000
     Checksum: sum(available) == balance                      ✓

  4. Receipt sent to group wallet email (mailing list)
     All members receive updated state
```

NOTE: Core validates the member_index and available balance. The receiver's
personal wallet validates the wallet_id matches on redemption. Lying about
member_index gains nothing — the cheque goes to receiver_wallet_id, and
only the real owner of that wallet can redeem it.

### 30.8 Sync Via Mailing List

The group wallet's email address is a mailing list. All receipts (incoming
cheque redeems, outgoing withdrawals) are sent to the group email, which
the email server fans out to all members. Every member always has the
latest wallet state.

If two members attempt to act simultaneously with the same wallet_seq,
the second one fails (consumed_state_id mismatch). They wait for the
mailing list update and retry. This is normal wallet behaviour.

### 30.9 Nabla Recording

Nabla records the full group wallet state, including all member balances.
This ensures any member (or receiver of a group wallet cheque) can verify
the group wallet's state independently.

```
Nabla entry for group wallet:
  wallet_id:     [32 bytes]
  current_state: [32 bytes]
  tx_hash:       [32 bytes]
  tick:          uint64
  group_members: [
    { member_pk: ..., share_bps: 5000, available: 2000 },
    { member_pk: ..., share_bps: 3000, available: 3000 },
    { member_pk: ..., share_bps: 2000, available: 2000 },
  ]
```

Receivers checking Nabla can verify:
- The group wallet balance is correct
- Individual allocations haven't been tampered with
- Checksum holds: sum(available) == balance

### 30.10 DEED Wallets

The DEED Protocol wallet and DEED Implementation wallet are group wallets.
They are created at genesis with their members list and share_bps defined
in the Genesis Bootstrap Guide.

**DEED fee collection is handled by Nabla, not validators.** When a client
registers their wallet state with Nabla after a transaction, they
simultaneously submit a small DEED fee payment. Nabla validates the DEED
payment through Core and witnesses it. This means:

- Validators are not responsible for DEED collection (unchanged behaviour)
- DEED collection is included by default in Nabla (open source, removable
  but market pressure discourages removal)
- Clients pay DEED as part of Nabla registration (one action, two purposes)
- If a client does not pay DEED, Nabla rejects the registration and the
  cheque remains SCARRED (no CLEAN status without DEED payment)

See the Nabla Implementation Guide for the complete DEED collection flow.

### 30.11 Creation

Group wallets can be created:

1. **At genesis.** DEED wallets are created with members and shares defined
   in the Genesis Bootstrap Guide.

2. **By any user.** A normal wallet creation with a members list attached.
   Core validates Rules 1-8 at creation time.

Once created, the members list is immutable. To change membership or shares,
a new group wallet must be created and funds transferred from the old one.


## Appendix A: Design Evolution -- Rejected Approaches

This appendix documents **why** certain design choices were abandoned.
These are not mistakes -- they are **necessary explorations** that led to current architecture.

### A.1 The 15-Person Consensus Committee (Rejected)

**Initial proposal:**
- Maintain a committee of 15 trusted individuals
- When cryptographic algorithm needs updating, 15-person consensus triggers migration
- Core reads `vault[STATE_OP_MODE]` set by committee vote

**Why it was rejected:**

1. **Returns to human governance** -- violates Section 13's rejection of committees
2. **Committee availability problem** -- what if members disappear, die, or are coerced?
3. **Coordination overhead** -- requires all 15 to remain reachable indefinitely
4. **Single point of failure** -- if committee is compromised, entire system is compromised

**What replaced it:**
Market-driven individual validator choice (Section 16.5)

### A.2 Centralized Algorithm State Variable (Rejected)

**Initial proposal:**
- Network maintains global `CURRENT_ALGORITHM` state
- All validators must switch simultaneously
- Protocol enforces uniformity

**Why it was rejected:**

1. **Forces coordination** -- creates the exact dependency we're trying to avoid
2. **Fragmentation risk** -- if validators disagree, network splits
3. **Emergency upgrade problem** -- rapid threats require rapid response, committees are slow
4. **Removes competition** -- validators can't differentiate on security posture

**What replaced it:**
Pre-embedded algorithm slots with individual operator preference (Section 16.4)

### A.3 Evidence-Chain Triggered Migration (Rejected)

**Initial proposal:**
- Core automatically monitors for public evidence of algorithm compromise
- When cryptographic break is proven, Core auto-switches to next algorithm
- Requires Core to evaluate "proof of compromise"

**Why it was rejected:**

1. **Too heavy** -- Core would need to understand cryptanalysis
2. **Who defines "proof"?** -- returns to committee problem
3. **Network dependency** -- Core would need external data access, violates isolation
4. **False positive risk** -- premature migration based on incomplete evidence

**What replaced it:**
Validator operators make informed decisions based on available information (Section 16.5)

### A.4 Complete Isolation (Early Concept)

**Initial proposal:**
- Build completely isolated DMAP-VM for email processing
- Never update, never change
- Accept that eventual obsolescence is inevitable

**Why it was abandoned:**

**The contradiction:**
If DMAP-VM is completely isolated, it cannot be updated when Ed25519 is broken.
If it can be updated, it's not completely isolated.

**The resolution:**
Isolation applies to **execution**, not **algorithm selection**.
Core remains isolated, but **supports multiple algorithms from genesis**.

This transforms "inevitable obsolescence" into "graceful migration."

### A.5 Lessons from Rejected Designs

Every rejected approach shared a common flaw:
**They tried to solve coordination through mechanism.**

The final design solves coordination through **absence of coordination requirement**.

By pre-embedding all options and making selection a local decision:
- No committee needed
- No governance needed  
- No emergency upgrades needed
- No coordination needed

**The pattern:**

> When a problem seems to require coordination,  
> eliminate the need for coordination instead of building coordination mechanisms.


## Appendix B: Parameter Rationale

### B.1 Validator Stake (500 AXC)

**Design goals:**
- High enough to deter Sybil attacks
- Low enough to allow decentralized participation
- Scales economically with AXC value appreciation

**Reasoning:**
At current design stage, 500 AXC represents a meaningful commitment without creating prohibitive barriers to entry. As AXC appreciates, the economic cost of becoming a validator naturally increases, auto-adjusting attack economics without protocol changes.

This value is **not final** and may be revised based on:
- Network size projections
- Attack cost modeling
- Participation rate analysis

### B.2 Query Cost (1 AXC)

**Design goals:**
- Prevents spam without excluding legitimate queries
- Creates validator incentive through redistribution
- Cost scales with AXC value

**Reasoning:**
The cost must be:
- Low enough that legitimate judicial queries remain affordable
- High enough that mass surveillance becomes prohibitively expensive

At 1 AXC per query:
- A single query costs negligible amount for legitimate users
- Querying 10,000 transactions = 1 AXC (significant deterrent to dragnet surveillance)

As AXC appreciates, this auto-adjusts attack economics in favor of privacy.

### B.2.1 PWV Set Size (k - 5 decoys)

**Design goals:**
- Sufficient anonymity protection when single set received
- Manageable operational burden (notification, voting)
- Scalable across different witness counts (k=3, k=4, k=5)

**Why k - 5?**

For k=3 real witnesses:
- PWV set = 3 real + 12 decoy = 15 total validators
- If querier receives 1 set: 3/15 = 20% chance any validator is real
- Larger decoy sets reduce this percentage but increase operational cost

**Comparison of multipliers:**

| Multiplier | k=3 Set Size | Real % | k=5 Set Size | Real % | Operational Impact |
|------------|--------------|--------|--------------|--------|-------------------|
| **k - 2**  | 9 validators | 33%    | 15 validators | 33%    | Low burden, weak protection |
| **k - 3**  | 12 validators | 25%   | 20 validators | 25%    | Moderate, moderate protection |
| **k - 5**  | **15 validators** | **20%** | **30 validators** | **17%** | **Balanced** |
| **k - 10** | 33 validators | 9%    | 55 validators | 9%     | High burden, strong protection |
| **k - 20** | 63 validators | 5%    | 105 validators | 5%    | Very high burden, very strong |

**Why NOT k - 10 or k - 20?**

Larger decoy sets:
- Harder to identify real witnesses if single set received (9% vs 20%)
- + More validators burdened with PWV participation notifications
- + Higher operational cost if JFP vote required
- + Larger notification overhead per query
- + Diminishing returns (9% vs 5% not worth 2- burden)

**Why NOT k - 2 or k - 3?**

Smaller decoy sets:
- Lower operational burden (fewer validators notified)
- + Easier to identify real witnesses (33% vs 20%)
- + Less protection if multiple sets leak (Section 18.4)
- + Weaker anonymity guarantee

**k - 5 balances:**
```
Anonymity: 20% real witness probability (single set)
         P(discover >=1) >= 0.5-5% with suppression (Section 18.4.4)

Operational cost: 15 validators for k=3
                 Manageable for notification + potential voting

Scalability: Scales linearly with k
            k=4 -> 20 validators
            k=5 -> 25 validators
```

**Relationship to intersection leakage risk:**

From Section 18.4.3, the discovery risk is driven by:
```
P(S >= 2) = probability of receiving multiple sets

NOT by PWV set size (k - multiplier)
```

PWV set size affects **single-set anonymity**, not **multi-set leakage**.

However, larger PWV sets make intersection analysis slightly more complex:
- More decoys to filter
- But unique elements still reveal real witnesses

**Conclusion:**

k - 5 provides **practical anonymity** (20% real witness probability) with **acceptable operational burden** (15-30 validators depending on k).

This is sufficient because:
- Multi-set leakage controlled by suppression (Section 18.4.2)
- Query cost (1 AXC) limits mass surveillance
- Perfect anonymity unnecessary (Section 18.4.6 Design Rationale)

### B.3 Offline Threshold (12 hours)

**Design goals:**
- Long enough to tolerate network instability
- Short enough to prevent indefinite stalling
- Aligned with typical infrastructure recovery windows

**Reasoning:**
12 hours represents a balance between:
- **Tolerance**: Allows for temporary network issues, power outages, or operational delays
- **Accountability**: Prevents validators from indefinitely delaying votes

Real-world considerations:
- Most network outages resolve within 12 hours
- Transcontinental coordination across time zones remains feasible
- Long enough to prevent trivial DoS attacks from forcing random votes

This threshold applies only to validators who **ACK'd the vote notification**, ensuring intentional participation is required before time-based consequences activate.

### B.4 PWV Immutability Window (10 years)

**Design goals:**
- Exceeds typical statute of limitations in most jurisdictions
- Allows long-term judicial processes
- Balances eternal obligation vs legal necessity

**Reasoning:**
10 years provides:
- Coverage for most criminal and civil statute of limitations globally
- Sufficient time for complex international legal processes
- Finite endpoint to validator obligations

**Why not permanent?**
Requiring validators to remain available forever is:
- inhumane
- technically unsustainable
- creates attack surface through validator aging

**Why not shorter?**
Many jurisdictions have 7-10 year limitations for serious financial crimes. A shorter window would exclude legitimate judicial processes.

This duration allows the system to respect rule of law without creating permanent servitude for validators.

### B.5 Minimum Witness Count (k=3)

**Design goals:**
- Prevent single point of coercion
- Provide redundancy for witness availability
- Balance security with transaction overhead

**Reasoning:**

**Why not k=1?**
- Single validator can be coerced, bribed, or compromised
- No redundancy if validator disappears
- Insufficient for trustless verification

**Why not k=2?**
- Still vulnerable to collusion between two parties
- Tie votes create deadlock in JFP
- Minimal redundancy (both must survive)

**Why k=3 (minimum)?**
- Requires 3-way collusion to compromise (significantly harder)
- Majority voting possible (2-of-3 for some decisions)
- Redundancy: transaction survives if 1-of-3 remains accessible
- Transaction overlap rule can be satisfied even with witness attrition

**Why not k=5 or higher?**
- Increased coordination overhead
- Larger PWV sets (k=5 -> 25 members)
- More expensive queries (must reach more witnesses)
- Diminishing returns on security (3-way collusion already difficult)

**Current position:**

k=3 as protocol minimum. Higher-value transactions MAY use k=4 or k=5 for enhanced security (Assurance Tiers, Section 6.2).

### B.6 PWV Multiplier (-5)

**Formula:** PWV_total = k - 5

**Examples:**
- k=3 -> 15 PWV members (3 real + 12 decoy)
- k=5 -> 25 PWV members (5 real + 20 decoy)

**Design goals:**
- Sufficient anonymity set to obscure real witnesses
- Small enough to avoid excessive coordination overhead
- Consistent ratio across assurance tiers

**Reasoning:**

**Why not -2 (minimal decoys)?**
- k=3 -> 6 total (50% chance of identifying real witness)
- Insufficient privacy protection

**Why not -10 (maximum decoys)?**
- k=3 -> 30 total (excessive coordination)
- JFP voting becomes unwieldy
- Network load scales poorly

**Why -5 (current)?**
- k=3 -> 15 total (20% chance of identifying any specific real witness)
- k=5 -> 25 total (manageable but secure)
- Scales linearly with assurance tier

**Trade-off analysis:**

| Multiplier | k=3 Total | Privacy (1/n) | Coordination Cost |
|------------|-----------|---------------|-------------------|
| -2         | 6         | 1/6 (weak)    | Low               |
| -3         | 9         | 1/9 (moderate)| Low-Medium        |
| -5         | 15        | 1/15 (good)   | Medium            |
| -10        | 30        | 1/30 (strong) | High              |

Current choice (-5) balances privacy and practicality.

### B.7 Propagation Fanout (f=3)

**Design goals:**
- Reliable witness discovery
- Controlled network load
- Deduplication effectiveness

**Reasoning:**

**Why not f=2?**
- Slower propagation (2^TTL growth)
- Higher failure risk (linear redundancy)
- TTL=10: max reach ~2,000 validators (insufficient)

**Why not f=5 or higher?**
- Explosive growth (5^10 = 9.7M theoretical)
- Difficult to control even with deduplication
- Excessive redundant messages

**Why f=3 (current)?**
- Exponential growth (3^10 ~60K) matches network size
- Redundancy without excess (each hop has 2 backups)
- Deduplication highly effective (query_id seen from multiple paths)
- Well-tested in distributed systems (Kademlia, BitTorrent DHT)

**Empirical validation pending:**

Current choice based on theoretical analysis. Production deployment may require tuning based on actual network topology and validator distribution.

### B.8 Propagation TTL (Time-to-Live = 10)

**Design goals:**
- Reach all real witnesses with high probability
- Prevent infinite propagation
- Control network load

**Reasoning:**

Mathematical analysis (Section 18.5) shows:

| TTL | Reach      | P(>=2 witnesses) |
|-----|------------|-----------------|
| 5   | ~360       | ~0.01%          |
| 8   | ~9,800     | ~10%            |
| 9   | ~29,500    | ~63%            |
| 10  | ~88,000    | ~100%           |

**Why not TTL=5?**
- Insufficient reach (99.99% failure rate for finding 2+ witnesses)

**Why not TTL=15?**
- Theoretical reach: 21M messages (network storm risk)
- Unnecessary even with deduplication

**Why TTL=10 (current)?**
- Reliably reaches entire network (N=50,000)
- Controlled worst-case load (~88K theoretical, ~10K actual)
- Safety margin for network growth

**Pending optimization:**

Preliminary analysis suggests TTL=8 may suffice with refined probability models. Requires validation:
- Empirical network reachability testing
- Monte Carlo simulation with real topology
- Cost-benefit analysis of TTL reduction

**Conservative approach:**

TTL=10 remains default until proven excessive through production data.


## Appendix C: Validator State Machine & Rejection Reasons

### C.1 Purpose

This appendix defines validator local state management and the reasons why validators may reject transaction witness requests.

**Critical principle:**

Validators maintain **local state** for each wallet they have previously served. This state determines whether the validator will provide witnessing service for the next transaction.

### C.2 Wallet State (Validator's View)

Each validator maintains a state record for wallets it has witnessed:

```c
typedef enum {
    READY,                   // Wallet can initiate new transaction
    PENDING_CONFIRMATION,    // Previous transaction witnessed, awaiting settlement
    UNKNOWN                  // Validator has no history with this wallet
    // LOCKED_RECOVERY removed v2.11.16 — see note below
} wallet_state_t;
```

**State descriptions:**

**READY:**
- Wallet has no pending transactions at this validator
- Validator will consider witnessing new transaction requests
- Default state after confirmation received or genesis

**PENDING_CONFIRMATION:**
- Validator witnessed a transaction
- Awaiting confirmation/settlement from client
- Validator will REJECT new transaction requests until settled

> **CRITICAL CLARIFICATION:** `PENDING_CONFIRMATION` is NOT a network-visible state and does NOT participate in consensus. It exists solely as a **local service gate**. Validators do not synchronize this state with each other. Inconsistency between validators' local states is allowed and expected -- the overlap rule and S-ABR mechanism handle consistency at the protocol level.

**~~LOCKED_RECOVERY~~ (Removed v2.11.16):**
Superseded by protocol-level recovery mechanisms that do not require
validator-side wallet locking:
- **CLARA TX_HEAL** (§YPX-018) — partial commit recovery via self-send
- **Burn** (§34) — scar resolution via fund destruction
- **Self-scar + supplemental registration** (§34.1) — voluntary re-registration with Nabla
- **Nabla resync** (§17.7) — lost wallet state recovery via Nabla query

These mechanisms handle all recovery scenarios client-side. The validator
does not need a locked state because the client carries its own FACT chain
(YPX-001 §1.6) and S-ABR overlap from prev_receipts does not require
validators to pause.

**UNKNOWN:**
- Validator has never witnessed this wallet before
- Validator may choose to witness if all other conditions satisfied
- No state history to validate against

### C.3 State Transitions

**Normal transaction flow:**

```
READY  ->  (witness TX_n)  ->  PENDING_CONFIRMATION
       ->"
PENDING_CONFIRMATION  ->  (receive confirmation)  ->  READY
```

**If confirmation never arrives:**

```
PENDING_CONFIRMATION  ->  (timeout/manual intervention)  ->  READY
```

(Implementation-specific timeout policy)

**Recovery:** Handled client-side via CLARA TX_HEAL, Burn, or Nabla resync.
No validator state change required (see §YPX-018, §34, §17.7).

### C.4 Rejection Reasons

When a validator receives a witness request, it may reject for multiple reasons:

**1. STATE_PENDING (Previous transaction unsettled)**

```c
if (wallet_state == PENDING_CONFIRMATION) {
    return REJECT(STATE_PENDING, "Previous transaction not confirmed");
}
```

**Cause:** Client did not send confirmation for previous transaction.

**Client action:** Re-send confirmation for previous transaction, then retry.

**2. INVALID_OVERLAP (Chain of evidence broken)**

```c
if (!has_overlap_with_previous_witnesses(tx)) {
    return REJECT(INVALID_OVERLAP, "No continuity with previous validators");
}
```

**Cause:** Transaction does not include any validator from previous witness set (Section 17.3).

**Client action:** Include at least one previous validator in new witness set.

**3. DOUBLE_SPEND (State already consumed)**

```c
if (tx.input.state_id != current_state_id) {
    return REJECT(DOUBLE_SPEND, "Attempting to spend stale state");
}
```

**Cause:** Transaction references old state that has already been superseded.

**Client action:** Update to latest state and retry.

**4. POLICY_VIOLATION (Core validation failed)**

```c
if (!validate_transaction(tx)) {
    return REJECT(POLICY_VIOLATION, "Transaction violates protocol rules");
}
```

**Causes:**
- Atom conservation violated
- Invalid signature
- TTL exceeded
- Reserve claim policy violated
- DEED allocation incorrect
- Other Core validation failures

**Client action:** Fix transaction to comply with protocol rules.

**5. INSUFFICIENT_FEE**

```c
if (tx.total_fees < minimum_acceptable_fee(validator)) {
    return REJECT(INSUFFICIENT_FEE, "Fee below validator minimum");
}
```

**Cause:** Offered fee below validator's published rate.

**Client action:** Increase fee or select different validators.

**6. VALIDATOR_UNAVAILABLE**

```c
if (validator_load > capacity_threshold) {
    return REJECT(VALIDATOR_UNAVAILABLE, "Capacity exceeded, try later");
}
```

**Cause:** Validator temporarily overloaded.

**Client action:** Retry later or select different validators.

### C.5 Confirmation Protocol (Fee Settlement)

**Purpose:**

Confirmation signals to validators that the client acknowledges the transaction and authorizes fee settlement. This transitions validator state from PENDING back to READY.

**Confirmation message format:**

```json
{
  "type": "TX_CONFIRMATION",
  "tx_id": "b3:8f7c1a...9e21",
  "client_signature": "ed25519:sig...",
  "witnesses": [
    {"validator_pk": "ed25519:pk_A...", "fee_authorized": true},
    {"validator_pk": "ed25519:pk_E...", "fee_authorized": true},
    {"validator_pk": "ed25519:pk_F...", "fee_authorized": true}
  ]
}
```

**Validator processing:**

```c
int process_confirmation(confirmation_t *conf) {
    // Verify signature
    if (!verify_signature(conf.client_signature, conf.tx_id)) {
        return INVALID;
    }
    
    // Verify if this validator is in witness list
    if (!is_witness(conf.witnesses, my_validator_pk)) {
        return IGNORED;  // Not for me
    }
    
    // Update state
    wallet_state = READY;
    
    // Trigger fee collection (optional, implementation-specific)
    if (conf.fee_authorized) {
        process_fee_settlement(conf.tx_id);
    }
    
    return SUCCESS;
}
```

**Timing:**

Client MUST send confirmation:
- Immediately after receiving all k witness signatures
- Before initiating next transaction
- If missed: can be sent later to unlock state

**What if confirmation is lost?**

- Validator remains in PENDING_CONFIRMATION state
- Rejects next transaction attempt
- Client can re-send confirmation at any time
- No protocol-level timeout (implementation choice)

### C.6 Practical Example: TX1 -> TX2 Flow

**Initial state:**
```
Validator V_A: wallet_123 = READY
Validator V_B: wallet_123 = READY  
Validator V_C: wallet_123 = READY
```

**Client sends TX1 to {V_A, V_B, V_C}:**

Each validator:
1. Checks: `wallet_state == READY` *"
2. Validates transaction (Core rules)
3. Signs witness proof
4. Updates: `wallet_state = PENDING_CONFIRMATION`

**State after TX1 witnessed:**
```
V_A: wallet_123 = PENDING_CONFIRMATION
V_B: wallet_123 = PENDING_CONFIRMATION
V_C: wallet_123 = PENDING_CONFIRMATION
```

**Client sends TX1_CONFIRMATION:**

Each validator:
1. Verifies confirmation signature
2. Updates: `wallet_state = READY`
3. Optionally triggers fee settlement

**State after confirmation:**
```
V_A: wallet_123 = READY
V_B: wallet_123 = READY
V_C: wallet_123 = READY
```

**Client sends TX2 to {V_A, V_D, V_E}:**

V_A (overlap validator):
1. Checks: `wallet_state == READY` *"
2. Validates TX2 includes overlap *" (V_A is from previous set)
3. Signs witness proof
4. Updates: `wallet_state = PENDING_CONFIRMATION`

V_D and V_E (new validators):
1. Verify: `wallet_state == UNKNOWN` (never seen this wallet)
2. Validate overlap requirement satisfied by V_A *"
3. Sign witness proof
4. Create new state: `wallet_state = PENDING_CONFIRMATION`

**State after TX2:**
```
V_A: wallet_123 = PENDING_CONFIRMATION
V_D: wallet_123 = PENDING_CONFIRMATION
V_E: wallet_123 = PENDING_CONFIRMATION
```

**What if confirmation was not sent after TX1?**

Client tries TX2 -> V_A checks state:

```c
if (wallet_state == PENDING_CONFIRMATION) {
    return REJECT(STATE_PENDING);
}
```

Client must:
1. Re-send TX1_CONFIRMATION to {V_A, V_B, V_C}
2. Wait for state to clear to READY
3. Retry TX2

### C.6.1 Visual Flow Diagram (ASCII)

**Complete TX1 -> TX2 sequence with state transitions:**

```
Legend:
  READY  = validator local DB: wallet state available (can sign next tx)
  PEND   = PENDING_CONFIRMATION (TX witnessed, awaiting fee/confirm unlock)
  {V1,V2,V3} = previous transaction witness set
  TX1C   = TX1 Confirmation / Fee Release message

(1) TX1 Witnessing: Client spends wallet state

+-----------+      TX1 (draft)       +----------+
|  Client   | ------------------->   |   V1     |  DB: READY -> PEND
+-----------+                        +----------+  Sign receipt
        |                            +----------+
        +--------------------------> |   V2     |  DB: READY -> PEND
        |                            +----------+  Sign receipt
        |                            +----------+
        +--------------------------> |   V3     |  DB: READY -> PEND
                                     +----------+  Sign receipt

Result:
- Client receives 3 receipts (TX1 "physically true")
- But in {V1,V2,V3} local DB, wallet state is locked (PEND)

(2) TX1 Confirmation: Client delivers fee/confirmation to unlock

+-----------+      TX1C              +----------+
|  Client   | ------------------->   |   V1     |  DB: PEND -> READY
+-----------+                        +----------+  (fee collection optional)
        |                            +----------+
        +--------------------------> |   V2     |  DB: PEND -> READY
        |                            +----------+
        |                            +----------+
        +--------------------------> |   V3     |  DB: PEND -> READY
                                     +----------+

Result:
- Lock released (>=1 witness unlocked is sufficient for liveness)

(3) TX2 Continuity: Next transaction must overlap >=1 previous witness

TX2 witness set = {V1, V4, V5}  (example with V1 as overlap)

+-----------+      TX2 (draft)       +----------+
|  Client   | ------------------->   |   V1     |  if DB==READY: sign TX2
+-----------+                        +----------+  else reject: STATE_PENDING
        |                            +----------+
        +--------------------------> |   V4     |  normal validation + sign
        |                            +----------+
        |                            +----------+
        +--------------------------> |   V5     |  normal validation + sign
                                     +----------+

Failure Scenarios:

+---------------------------------------------------------------------+
| Scenario A: V1 malicious/buggy (keeps PEND even after receiving TX1C)|
|                                                                     |
| Client tries TX2 with V1 overlap -> V1 rejects (STATE_PENDING)      |
| Client pivots to V2 or V3 for overlap -> TX2 progresses             |
|                                                                     |
| Result: As long as >=1 of previous set is honest+alive, wallet lives|
+---------------------------------------------------------------------+

+---------------------------------------------------------------------+
| Scenario B: V1, V2, V3 ALL reject TX2 as PEND                       |
|                                                                     |
| Most likely: Client never delivered TX1C (or delivery lost)         |
| Fix: Not "protocol governance", it's "client resend TX1C"           |
|                                                                     |
| Steps:                                                              |
| 1. Client re-sends TX1_CONFIRMATION to {V1, V2, V3}                 |
| 2. Validators transition: PEND -> READY                             |
| 3. Client retries TX2                                               |
| 4. TX2 succeeds                                                     |
+---------------------------------------------------------------------+

+---------------------------------------------------------------------+
| Scenario C: All {V1, V2, V3} disappeared                            |
|                                                                     |
| Trigger: Recovery protocol (Section 17.4)                           |
| No overlap possible -> VIC + meta-validators                        |
| Wallet liveness > fee perfection (fee loss for vanished validators) |
+---------------------------------------------------------------------+
```

**Key insight from this flow:**

The "enforcement" is not cryptographic magic or global consensus.  
It is **physical refusal** at the validator level:

> "Your state is locked (PEND) at my node.  
> I will not sign your next transaction until you unlock it.  
> Complete the last transaction (send confirmation) before requesting next."

This is a **business decision**, not protocol enforcement.  
Validators want fees -> they enforce state consistency -> network security emerges.

### C.7 Design Rationale

**Why local state?**

- No global coordination required
- Each validator makes independent decision
- Scalable (no consensus overhead)
- Fault-tolerant (validator crash doesn't affect others)

**Why PENDING state prevents double-spend?**

- Overlap validator knows previous state was consumed
- Cannot sign conflicting transaction
- Physical gate: "Complete last transaction before next"

**Why confirmation is necessary?**

- Allows validator to transition back to READY
- Signals client acknowledges transaction
- Authorizes fee settlement
- Creates natural flow control

**Why this is not governance:**

- Validators don't vote or coordinate
- Each makes local business decision
- "Will I provide service?" not "Should network accept this?"
- Rejection is refusal to serve, not protocol enforcement

**Alignment with "Transaction Logic" document:**

This appendix formalizes the concepts described in "Transaction Logic":
- Validators as physical gates
- Local enforcement through state management
- Economic pressure (want fees, want business)
- No need for global consensus





## Appendix P: Formal Pseudocode

This appendix contains normative pseudocode for critical protocol mechanisms. Implementations MUST conform to the logic specified here.

## P.1 Notation & Primitives

```
Normative keywords: MUST / MUST NOT / SHOULD / SHOULD NOT / MAY

Primitives:
- Hash(bytes) -> Bytes32
- Sign(sk, msg_bytes) -> Sig
- Verify(pk, msg_bytes, sig) -> bool
- SecureRandomBytes(n) -> bytes
- Now() -> UnixTime
- CanonicalSerialize(obj) -> bytes   # deterministic encoding
- UTF8(s) -> bytes
- HEX(b) -> string
- I64(x) -> bytes
- PK(sk) -> PubKey
- PK_SELF() -> PubKey

function SIGMSG(domain: string, root: Bytes32) -> bytes:
  return UTF8(domain) || root
```

## P.2 Parameters (Hard Defaults)

```
CONST K_MIN                     = 3
CONST PWV_MULTIPLIER            = 5
CONST QUERY_COST_AXC            = 1
CONST PROPAGATION_FANOUT        = 3
CONST PROPAGATION_TTL_MAX       = 10
CONST OFFLINE_THRESHOLD         = 12h
CONST JFP_VOTE_WINDOW           = 24h
CONST PWV_IMMUTABILITY          = 10y

# Memory safety (forwarder dedup cache)
CONST FORWARDER_DEDUP_MAX_ENTRIES = 100000
CONST FORWARDER_DEDUP_RETENTION   = 48h
CONST FORWARDER_SOFT_DROP_MODE    = true

# Decentralized time skew allowance
CONST CLOCK_SKEW_DELTA            = 10m

# Direct notification reliability
CONST DIRECT_NOTIFY_MAX_RETRY     = 5
CONST DIRECT_NOTIFY_BACKOFF_BASE  = 2s
CONST TARGETED_DIFFUSION_FANOUT   = 3
CONST TARGETED_DIFFUSION_TTL      = 2

# Deterministic decoys
CONST DECOY_EPOCH                 = 24h

# Query payment proof
CONST STAMP_REPLAY_MAX_ENTRIES    = 200000
CONST STAMP_REPLAY_RETENTION      = 48h
```

## P.3 Query Payment Proof (stamp.v1)

```
record QueryPaymentProof:
  scheme: "stamp.v1"
  stamp_id: string
  payer_pk: PubKey
  issuer_pk: PubKey
  issued_at: UnixTime
  expires_at: UnixTime
  stamp_sig: Sig        # issuer signature over STAMP_ROOT
  payer_sig: Sig        # payer binds (query_id || stamp_id)

function STAMP_ROOT(p: QueryPaymentProof) -> Bytes32:
  p2 = p
  p2.stamp_sig = null
  p2.payer_sig = null
  return Hash(CanonicalSerialize(p2))

function VALIDATE_STAMP(p: QueryPaymentProof) -> bool:
  MUST p.scheme == "stamp.v1"
  MUST p.expires_at > p.issued_at
  MUST Now() <= p.expires_at
  MUST Verify(p.issuer_pk, SIGMSG("QSTAMP", STAMP_ROOT(p)), p.stamp_sig)
  return true

# Replay protection (bounded)
global seen_stamp_id = LRUCache[string, UnixTime](max_entries=STAMP_REPLAY_MAX_ENTRIES)

function CHECK_QUERY_PAYMENT(q: QueryMsg) -> bool:
  p = q.payment
  MUST p != null
  MUST VALIDATE_STAMP(p)

  # bind stamp to query_id to prevent stamp theft reuse
  bind_root = Hash(UTF8(q.query_id) || UTF8(p.stamp_id))
  MUST Verify(p.payer_pk, SIGMSG("QSTAMP_BIND", bind_root), p.payer_sig)

  # replay protection (bounded)
  if seen_stamp_id.contains(p.stamp_id):
    return false

  if seen_stamp_id.is_full() and !seen_stamp_id.contains(p.stamp_id):
    return false  # survival-first

  seen_stamp_id.put(p.stamp_id, Now())
  return true
```

## P.4 PWV Set Generation (Deterministic Decoys)

```
record PWVSetMsg:
  version: "pwvset.v1"
  query_id: QueryID
  tx_id: TxID
  k: int
  members: list[PubKey]
  created_at: UnixTime
  epoch_id: UnixTime
  witness_pk: PubKey
  seed_proof: Sig        # Sign(witness_sk, Hash(tx_id||epoch_id))
  witness_sig: Sig

function CURRENT_EPOCH_ID(now: UnixTime) -> UnixTime:
  return floor(now / DECOY_EPOCH) * DECOY_EPOCH

function GENERATE_PWVSET(q: QueryMsg, witness_sk, k: int) -> PWVSetMsg:
  total = k * PWV_MULTIPLIER
  witness_pk = PK(witness_sk)

  epoch_id  = CURRENT_EPOCH_ID(Now())
  preimage  = Hash(UTF8(q.tx_id) || I64(epoch_id))
  seed_proof = Sign(witness_sk, preimage)
  seed      = Hash(seed_proof)

  decoys = DETERMINISTIC_SAMPLE_VALIDATORS_EXCLUDING({witness_pk}, total-1, seed)
  members = SHUFFLE_DETERMINISTIC([witness_pk] + decoys, seed=Hash(seed || UTF8("shuffle")))

  s = PWVSetMsg{
    version="pwvset.v1",
    query_id=q.query_id,
    tx_id=q.tx_id,
    k=k,
    members=members,
    created_at=Now(),
    epoch_id=epoch_id,
    witness_pk=witness_pk,
    seed_proof=seed_proof,
    witness_sig=EMPTY
  }
  s.witness_sig = Sign(witness_sk, SIGMSG("PWVSET", PWVSET_ROOT(s)))
  return s

function VALIDATE_PWVSET(s: PWVSetMsg) -> bool:
  MUST s.version == "pwvset.v1"
  MUST s.k >= K_MIN
  MUST LENGTH(UNIQUE(s.members)) == LENGTH(s.members)
  MUST LENGTH(s.members) == s.k * PWV_MULTIPLIER

  # Verify seed_proof binding (unpredictable before publication)
  preimage = Hash(UTF8(s.tx_id) || I64(s.epoch_id))
  MUST Verify(s.witness_pk, preimage, s.seed_proof)

  msg = SIGMSG("PWVSET", PWVSET_ROOT(s))
  MUST Verify(s.witness_pk, msg, s.witness_sig)
  return true
```

## P.5 Forwarder Deduplication (Bounded)

```
global forwarder_seen_query = LRUCache[QueryID, UnixTime](max_entries=FORWARDER_DEDUP_MAX_ENTRIES)

function FORWARDER_ON_QUERY(q: QueryMsg):
  if !VALIDATE_QUERY(q): return

  # bounded memory protection
  if forwarder_seen_query.is_full() and !forwarder_seen_query.contains(q.query_id):
    if FORWARDER_SOFT_DROP_MODE:
      return
    else:
      forwarder_seen_query.evict_one()

  if forwarder_seen_query.contains(q.query_id):
    return

  forwarder_seen_query.put(q.query_id, Now())

  if q.ttl <= 1: return
  q2 = q; q2.ttl = q.ttl - 1
  DIFFUSE(q2)

function FORWARDER_CACHE_GC():
  forwarder_seen_query.evict_older_than(Now() - FORWARDER_DEDUP_RETENTION)
```

## P.6 Direct Notification with Bounded Retry

```
function SEND_WITH_RETRY(msg, endpoint) -> bool:
  for i in 0..DIRECT_NOTIFY_MAX_RETRY-1:
    ok = SEND(msg, endpoint)
    if ok: return true
    sleep(DIRECT_NOTIFY_BACKOFF_BASE * (2^i))
  return false

record TargetedWrapper:
  version: "targeted.v1"
  target_pk: PubKey
  ttl: int
  inner: any

function TARGETED_DIFFUSE_TO_MEMBER(inner_msg, member_pk: PubKey):
  peers = SELECT_NEIGHBORS_FOR(member_pk, TARGETED_DIFFUSION_FANOUT)
  wrapper = TargetedWrapper{ version="targeted.v1", target_pk=member_pk, ttl=TARGETED_DIFFUSION_TTL, inner=inner_msg }
  for p in peers:
    SEND(wrapper, p)

function QUERIER_ON_PWVSET(s: PWVSetMsg, querier_sk):
  if !VALIDATE_PWVSET(s): return
  if querier_canonical_pwv.contains(s.query_id): return

  querier_canonical_pwv[s.query_id] = s
  notice = BUILD_LOCK_NOTICE(s, PK(querier_sk), querier_sk)

  for pk in s.members:
    ok = SEND_WITH_RETRY(notice, ENDPOINT(pk))
    if !ok:
      TARGETED_DIFFUSE_TO_MEMBER(notice, pk)

  DIFFUSE(BUILD_CANONICAL_EXISTS_HINT(s.query_id))
```

## P.7 JFP Voting (Clock Skew Tolerant)

```
function IS_WINDOW_CLOSED(sess: JFPVoteSession) -> bool:
  return Now() >= (sess.ends_at + CLOCK_SKEW_DELTA)

function FINALIZE_JFP(vote_id: VoteID) -> JFPOutcome:
  sess = LOAD(vote_id)
  if sess.finalized: return LOAD_OUTCOME(vote_id)

  if !IS_WINDOW_CLOSED(sess):
    return FAILED   # or PENDING

  effective = map[PubKey, VoteValue]()
  for pk in sess.members:
    effective[pk] = RESOLVE_MEMBER_VOTE(sess, pk)

  # Any UNVOTED -> FAILED
  for pk in sess.members:
    if effective[pk] == UNVOTED:
      STORE_OUTCOME(vote_id, FAILED)
      sess.finalized = true; STORE(sess)
      return FAILED

  # Any real witness != YES -> REJECTED
  for pk in sess.members:
    if IS_REAL_WITNESS_FOR_TX(pk, sess.tx_id):
      if effective[pk] != YES:
        STORE_OUTCOME(vote_id, REJECTED)
        sess.finalized = true; STORE(sess)
        return REJECTED

  APPLY_FREEZE(sess.tx_id)
  STORE_OUTCOME(vote_id, APPROVED)
  sess.finalized = true; STORE(sess)
  return APPROVED
```




## 26.18 Trust Model Philosophy — Strengthening k=3

### 26.18.1 Core Principle

AXIOM's security model is **k=3 consensus**. Every design decision must strengthen k=3 from within, not work around it. Adding parallel trust systems outside the consensus model creates architectural complexity and attack surface without proportional benefit.

The correct approach: make k=3 harder to break.

```
WRONG:  "k=3 is weak, add mechanism X outside consensus"
RIGHT:  "k=3 is the model, make each k worth more"
```

### 26.18.2 The Full Transaction Trust Path

A complete AXIOM transaction touches 7 independent parties:

```
SENDER SIDE (spending):
  Validator 1 ──┐
  Validator 2 ──┤── k=3 witness consensus
  Validator 3 ──┘
                    ↓ cheque bundle
RECEIVER SIDE (redeeming):
  Validator 4 ──┐
  Validator 5 ──┤── k=3 cheque verification
  Validator 6 ──┘
                    ↓ state verification
NETWORK:
  Nabla Node ───── state currency check (Phase 3)
```

To successfully steal money, an attacker must corrupt parties on BOTH sides of the transaction AND the Nabla verification layer. The sender's validators are selected by the sender (attacker-controlled), but the receiver's validators are selected by the receiver (not attacker-controlled). The Nabla node is queried by the receiver.

### 26.18.3 Components That Strengthen k=3

Each component feeds INTO the consensus model:

| Component | Strengthens k=3 by... |
|-----------|----------------------|
| **VBC** (Identity) | Proving each validator in k=3 is legitimate — chains to genesis |
| **FACT** (Provenance) | Proving each validator's work is real — zk-VM proofs in receipts |
| **S-ABR** (Overlap) | Ensuring k-1 validators in k=3 saw the previous transaction |
| **WVT** (Trust Score) | Ensuring the 3 validators in k=3 collectively have enough reputation |
| **Nabla** (Currency) | Verifying the state referenced by k=3 consensus is still current |
| **TARDIS** (Time) | Binding k=3 consensus to a verifiable point in time |

None of these replace k=3. They all make k=3 stronger.

### 26.18.4 Weighted Validator Trust (WVT)

**Status:** Proposed extension — deferred research direction, no YPX number assigned. Implement after Phase 2 when VBC age and FACT chain history are available.

#### Problem Statement

k=3 treats all validators equally. A fresh validator running for 5 minutes has the same consensus weight as a genesis validator running since day one. This makes attacks cheap: spin up 3 validators, achieve consensus immediately.

#### Solution: Trust Points

Replace the consensus rule from:

```
CURRENT:  count(valid_witnesses) >= 3
```

To:

```
PROPOSED: sum(trust_score(witness)) >= T   where T = trust threshold
```

#### Trust Score Computation

Trust score is **deterministic and independently verifiable** from public data. No governance, no voting, no committees.

```
INPUTS (all publicly verifiable):
  vbc_age        = now - VBC.birth_timestamp        (from VBC certificate)
  tx_witnessed   = count of transactions in FACT chain  (from FACT receipts)
  is_genesis     = VBC.chain_depth == 0             (from VBC certificate)

FORMULA:
  base_points    = 10
  age_points     = min(30, floor(vbc_age_years * 15))
  work_points    = min(10, floor(tx_witnessed / 10000))
  genesis_bonus  = 40 if is_genesis else 0
  
  trust_score    = base_points + age_points + work_points + genesis_bonus

RANGES:
  Genesis validator:         50 (day one) → 90 (2+ years, 100K+ txns)
  Mature validator (2yr+):   50 (max non-genesis)
  Established (6mo-2yr):     17-35
  New validator:              10 (minimum)
```

#### Trust Threshold Examples (T=100)

```
STRONG CONSENSUS:
  2 genesis validators                    = 100+ ✓
  1 genesis + 2 mature                    = 150  ✓
  3 mature (2yr+, 100K txns each)         = 150  ✓

WEAK CONSENSUS (rejected):
  3 new validators                        = 30   ✗
  1 genesis + 2 new                       = 70   ✗
  5 new validators                        = 50   ✗

BORDERLINE:
  1 genesis + 1 mature + 1 new            = 110  ✓
  1 genesis + 1 established (1yr) + 1 new = 85   ✗ (needs more)
  10 new validators                       = 100  ✓ (but requires controlling 10 parties)
```

#### Attack Cost Scaling

The cost of attacking AXIOM scales with network maturity:

```
Day 1:    Attacker needs 3 validators (easy — just spin them up)
Month 6:  Attacker needs ~5 validators or must compromise established ones
Year 2:   Attacker needs to corrupt mature validators with 100K+ tx history
Year 5+:  Network has deep trust hierarchy, attack is impractical
```

This is analogous to Bitcoin's "51% attack cost scales with hash rate" — AXIOM's attack cost scales with network age and activity.

#### Why WVT Fits AXIOM

1. **Deterministic** — every node computes the same score from the same public data
2. **No governance** — trust is earned by time and work, not granted by committee
3. **Uses existing components** — VBC (age), FACT (work history), TARDIS (time reference)
4. **Strengthens k=3** — doesn't replace consensus, makes each participant more meaningful
5. **Forward compatible** — can be added without changing the consensus protocol structure, only the threshold check

#### Implementation Requirements

WVT requires the following to be operational:
- VBC with verifiable timestamps (Phase 1 — exists)
- FACT chain with transaction counts per validator (Phase 2)
- TARDIS time binding for age verification (Phase 3)
- Consensus rule change: `count >= 3` to `sum(score) >= T` (Phase 3)

#### Open Questions

1. Should T be fixed (100) or adaptive (scales with total network trust)?
2. Should validators advertise their score, or should clients compute it?
3. Does the receiver enforce a minimum per-cheque trust score?
4. Can trust be slashed? (Adds complexity. May violate "pure math" philosophy.)
5. Interaction with S-ABR: should overlap validators have minimum individual score?


## 31. Build Architecture, Platform Requirements & ZK Trust Model

This section is **normative** and defines the physical architecture of how AXIOM components are compiled, distributed, and executed. It establishes the trust model for Zero-Knowledge Proofs, the platform requirements enforced by Core, and the strict separation between code that is compiled once and code that is compiled per platform.

**This section exists because confusion about these boundaries is a critical risk.** Any developer, operator, or auditor working on AXIOM MUST understand this section before modifying build systems, deployment pipelines, or cryptographic components.


### 31.1 The Three Artefacts

AXIOM produces exactly three categories of compiled artefact. They are fundamentally different in nature and MUST NOT be confused.

| Artefact | What It Is | Compiled To | Compiled How Often | Distributed How |
|----------|-----------|-------------|-------------------|-----------------|
| **Core** | Immutable validation logic | RISC-V ELF bytecode | **Once** per release | Same binary to all nodes |
| **DMAP-VM** | Host runtime that executes Core | Native machine code | **Once per platform** | Platform-specific binary |
| **ZK Proof** | Cryptographic attestation of execution | **Not compiled — it is data** | Generated at runtime | Transmitted between nodes as bytes |

#### 31.1.1 Core (RISC-V ELF)

Core is **one binary**. It is the same on every machine, every platform, every node in the network. Core is compiled from Rust source to RISC-V ELF bytecode using the zk-VM guest toolchain. The compilation produces two outputs:

```
Core source (Rust)
    │
    ▼  risc-v target (guest toolchain)
    │
    ├──► core.elf       The executable bytecode
    └──► IMAGE_ID       Cryptographic hash of core.elf
```

**IMAGE_ID** is the fingerprint of Core. It is how any participant in the network can verify they are running the same Core as everyone else. IMAGE_ID is derived deterministically from the compiled bytecode — identical source with identical compiler settings always produces the identical IMAGE_ID.

**Core does not know what platform it runs on.** It does not know if it is executing on x86, ARM, or any other architecture. It receives inputs, applies validation rules, and produces outputs. The platform is the DMAP-VM's concern, not Core's.

**Core is never cross-compiled.** There is one target: RISC-V. One build. One binary. One IMAGE_ID.

#### 31.1.2 DMAP-VM (Native, Per-Platform)

The DMAP-VM (AXIOM Virtual Machine) is the host program that executes Core. It is native machine code, compiled separately for each supported platform. The DMAP-VM contains three components:

```
DMAP-VM (native binary)
├── RISC-V Interpreter    Executes core.elf instruction by instruction
├── ZK Prover             Observes execution, generates cryptographic proof
└── ZK Verifier           Checks proofs generated by other nodes
```

The DMAP-VM is **cross-compiled** for each target platform:

| Platform | Target Triple | Notes |
|----------|--------------|-------|
| Ubuntu/Linux x86_64 | `x86_64-unknown-linux-gnu` | Servers, desktops |
| Raspberry Pi 4/5 | `aarch64-unknown-linux-gnu` | 64-bit ARM |
| Windows 10+ | `x86_64-pc-windows-gnu` | 64-bit only |
| macOS (Apple Silicon) | `aarch64-apple-darwin` | Built natively on Mac |
| macOS (Intel) | `x86_64-apple-darwin` | Built natively on Mac |

**The DMAP-VM is the only artefact that is platform-specific.** When we say "cross-compile for Raspberry Pi," we mean compiling the DMAP-VM for ARM64 — not Core, not Lambda, not Nabla in isolation.

#### 31.1.3 ZK Proof (Data, Not Code)

A ZK proof is **not a binary, not code, not compiled**. It is a sequence of bytes — mathematical data — generated at runtime by the DMAP-VM's prover component.

```
A proof is like a digital signature:
  - Generated on ARM → verified on x86 → same result
  - Generated on Linux → verified on Windows → same result
  - It is pure mathematics. Platform is irrelevant.
```

Proofs are transmitted between nodes as opaque byte sequences. Any node with a compatible verifier can check any proof, regardless of which platform generated it.


### 31.2 The Build Pipeline

The complete build pipeline has exactly two compilation stages. There is no third stage for proofs — proofs are runtime data.

```
STAGE 1: COMPILE CORE (once per release)
══════════════════════════════════════════

    Rust source ──► risc-v guest toolchain ──► core.elf + IMAGE_ID
    
    This happens ONCE.
    The output is platform-independent.
    Every node in the network runs this exact binary.


STAGE 2: COMPILE DMAP-VM (once per platform per release)
══════════════════════════════════════════════════════

    Rust source ──► native target toolchain ──► DMAP-VM binary
    (includes risc0-zkvm crate)
    
    This happens ONCE PER PLATFORM.
    Each platform gets its own DMAP-VM binary.
    The DMAP-VM binary contains: interpreter + prover + verifier.


RUNTIME: PROOF GENERATION (every transaction)
══════════════════════════════════════════════

    Transaction arrives
         │
         ▼
    DMAP-VM loads core.elf
         │
         ▼
    DMAP-VM interpreter executes Core
         │  (prover watches every instruction)
         ▼
    Core produces PublicOutputs
         │
         ▼
    Prover generates ZK proof from execution trace
         │
         ▼
    OUTPUT: PublicOutputs + proof + IMAGE_ID
```


### 31.3 Platform Requirement: 64-bit Unix Time

#### 31.3.1 The Problem

AXIOM uses Unix timestamps (`u64`) as the fundamental unit of time throughout the protocol:

- TARDIS tick numbers are Unix seconds
- VBC and NBC `issued_at` and `expires_at` fields are Unix timestamps
- Transaction timestamps are Unix seconds
- Maturity calculations use Unix seconds
- All time-based protocol logic operates on Unix seconds

32-bit Unix time overflows on **2038-01-19 03:14:07 UTC** (value 2,147,483,647). On systems where time is represented as a 32-bit signed integer, time will wrap to a negative number or to zero, causing catastrophic failure in any time-dependent logic.

AXIOM is financial infrastructure designed to operate for decades. A platform that cannot represent time beyond 2038 is fundamentally unsafe for AXIOM.

#### 31.3.2 The Rule (NORMATIVE)

> **AXIOM requires 64-bit Unix time.**
>
> Core verifies this at launch. If the environment cannot safely represent
> Unix timestamps beyond the year 2038, Core refuses to start.
>
> This is the sole platform gate. It is enforced by Core and only by Core.
> No other component checks platform requirements.
> If Core started, the platform is safe. Period.

#### 31.3.3 Enforcement Mechanism

Core performs the following verification at startup, before processing any request:

```
VERIFY_TIME_SAFETY():

    Step 1: Representability check
        Let T = 2,208,988,800  (2040-01-01 00:00:00 UTC)
        Assert T > 2,147,483,647
        If false → FATAL: "Unix time representation cannot exceed 2038"

    Step 2: Clock sanity check (when system clock available)
        Let NOW = current Unix timestamp from system clock
        Assert NOW > 1,577,836,800  (2020-01-01 00:00:00 UTC)
        If false → FATAL: "System clock reports year before 2020.
                           Possible 32-bit time truncation."
```

Step 1 verifies that the data type can hold a post-2038 value. Step 2 detects environments where a 32-bit clock has wrapped or been truncated — the current time should always be after 2020, and a wrapped 32-bit clock would report a nonsensical value.

#### 31.3.4 Why Only Core Checks

Core is the trust anchor of the system. Every other component — Lambda, Nabla, ANTIE, the DMAP-VM itself — depends on Core. If Core will not start on an unsafe platform, nothing starts. Adding redundant checks in other components:

1. **Violates the single-authority principle.** Core is the sole authority for platform safety, just as it is the sole authority for cryptographic truth.
2. **Creates false confidence.** A check in Nabla might pass on a platform where Core's check would fail, leading operators to believe their platform is safe when it is not.
3. **Is unmaintainable.** Multiple checks must be kept in sync. A bug fix in one location might not propagate to others.

**Core checks. Everything else trusts Core.**

#### 31.3.5 Supported Platforms

As a consequence of the 64-bit Unix time requirement, AXIOM supports only 64-bit platforms:

| Platform | Architecture | Status |
|----------|-------------|--------|
| x86_64 (Intel/AMD 64-bit) | `x86_64` | ✓ Supported |
| ARM64 (Raspberry Pi 4/5, Apple Silicon) | `aarch64` | ✓ Supported |
| 32-bit x86 | `i686` | ✗ **REJECTED** |
| 32-bit ARM (Raspberry Pi 3, armv7) | `armv7` | ✗ **REJECTED** |
| 16-bit or embedded | various | ✗ **REJECTED** |

There are no exceptions. There is no compatibility mode. There is no fallback.


### 31.4 The ZK Trust Model

#### 31.4.1 The Trust Question

AXIOM uses a third-party library (currently RISC Zero) for Zero-Knowledge Proof generation and verification. The natural question is: **how do we trust it?**

The answer lies in the asymmetry between prover and verifier.

#### 31.4.2 Prover vs Verifier Asymmetry

```
Prover:     Complex.  Tens of thousands of lines of code.
            Generates the proof from an execution trace.
            
Verifier:   Simple.   Hundreds of lines of code.
            Checks whether a proof is mathematically valid.
```

These two components have fundamentally different trust properties:

| Property | Prover | Verifier |
|----------|--------|----------|
| Complexity | High (tens of thousands of LoC) | Low (hundreds of LoC) |
| Can it fake a proof? | No — a valid proof requires genuine execution | N/A |
| What if it's buggy? | Proof generation fails (liveness issue) | Invalid proofs might pass (safety issue) |
| Can it be audited? | Difficult (complex algorithms) | **Yes** (small, mathematical, auditable) |
| Can it be reimplemented? | Impractical | **Yes** — multiple implementations possible |

**Critical insight:** A compromised or buggy prover cannot forge a proof. It can only fail to produce one. This is a liveness problem, not a safety problem. A broken prover means transactions stall — it does not mean false transactions are accepted.

A compromised or buggy verifier IS a safety problem — it might accept invalid proofs. This is why the verifier is the trust anchor for ZK, and why its simplicity and auditability matter.

#### 31.4.3 What We Actually Trust

The trust chain for AXIOM's ZK system is:

```
Layer 1: Mathematics (STARKs)
    Published, peer-reviewed cryptographic proofs.
    If the math is correct, a valid proof CANNOT be forged.
    This is the foundation. It does not depend on any software.

Layer 2: Verifier Implementation
    Small, auditable code that implements the mathematical checks.
    Can be independently reimplemented to cross-check correctness.
    Can be formally verified due to its simplicity.
    THIS IS THE TRUST ANCHOR FOR ZK IN AXIOM.

Layer 3: Prover Implementation  
    Complex but not trust-critical.
    A broken prover cannot forge proofs (see §31.4.2).
    A broken prover can only fail to generate proofs (liveness, not safety).
    We use the risc0 prover because it works. If it breaks, we replace it.
```

#### 31.4.4 Proof Compatibility and Versioning

Different versions of the prover produce different proof bytes for the same execution. This is expected and correct — provers use random blinding factors internally, analogous to how two signatures of the same document differ in their bytes but both verify correctly.

**However:** When the proof protocol itself changes (e.g., a major version upgrade of the ZK library), the proof format may become incompatible. A verifier built for protocol version X cannot verify proofs generated under protocol version Y.

AXIOM handles this as follows:

> **PROOF PROTOCOL VERSION RULE (NORMATIVE)**
>
> 1. The proof protocol version is hardcoded in Core's IMAGE_ID derivation.
>    A change in proof protocol = a new Core release = a new IMAGE_ID.
>
> 2. Every proof carries the IMAGE_ID of the Core that generated it.
>    Verifiers use IMAGE_ID to determine the expected proof format.
>
> 3. Protocol upgrades require all nodes to update. There is no mixed-version
>    operation for proof protocols. This is a hard fork, not a soft fork.
>
> 4. This is a protocol-level decision, hardcoded. No governance vote.
>    No committee. No emergency override. Set it and forget it.

#### 31.4.5 IMAGE_ID Is the Network's Identity

IMAGE_ID is the cryptographic hash of `core.elf`. It serves as:

1. **Core's fingerprint.** Any two nodes can verify they are running the same Core by comparing IMAGE_ID.
2. **Proof binding.** Every proof is bound to the IMAGE_ID of the Core that produced it. A proof says: "Core with this specific IMAGE_ID processed this transaction and produced this result."
3. **Network consensus.** All nodes in the network must agree on IMAGE_ID. A node presenting proofs from a different IMAGE_ID is running different code and is incompatible.

```
IMAGE_ID = H(core.elf)

Proof = Prove(
    program:  core.elf with IMAGE_ID,
    inputs:   PublicInputs,
    outputs:  PublicOutputs
)

Verify(proof, IMAGE_ID, PublicInputs, PublicOutputs) → true | false
```

If the verification returns true, the verifier knows with mathematical certainty that:
- A program with hash IMAGE_ID was executed
- It received exactly PublicInputs
- It produced exactly PublicOutputs
- No deviation from the program occurred

**The verifier does not need to re-execute Core. The proof is sufficient.**


### 31.5 What Gets Cross-Compiled (Summary)

To eliminate all ambiguity, this is the complete list of what is compiled and how:

```
╔═══════════════════════════════════════════════════════════════════╗
║                    AXIOM BUILD ARTEFACTS                         ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  COMPILED ONCE (platform-independent):                           ║
║                                                                   ║
║    Core         → RISC-V ELF         One binary for all nodes    ║
║                   + IMAGE_ID          Hash of the binary          ║
║                                                                   ║
║  CROSS-COMPILED PER PLATFORM:                                    ║
║                                                                   ║
║    DMAP-VM          → native binary       Contains interpreter,      ║
║                                       prover, and verifier       ║
║                                                                   ║
║  NOT COMPILED (runtime data):                                    ║
║                                                                   ║
║    ZK Proof     → byte sequence       Generated by DMAP-VM at        ║
║                                       runtime, verified by any   ║
║                                       node on any platform       ║
║                                                                   ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  Lambda, Nabla, ANTIE are APPLICATION CODE.                      ║
║  They call Core through the DMAP-VM. They do not embed Core.         ║
║  They are compiled alongside DMAP-VM for each platform.              ║
║                                                                   ║
║  For deployment, the operator receives:                          ║
║    1. core.elf + IMAGE_ID  (same for everyone)                   ║
║    2. DMAP-VM binary           (for their platform)                  ║
║    3. Application binaries (Lambda/Nabla/ANTIE, for their        ║
║       platform, which invoke DMAP-VM to run Core)                    ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
```


### 31.6 Invariants (NORMATIVE)

The following invariants are absolute and may not be violated:

1. **Core is compiled to RISC-V ELF exactly once per release.** It is never compiled to native code. It is never cross-compiled. It is one binary.

2. **IMAGE_ID is the sole identity of Core.** If two core.elf files have different IMAGE_IDs, they are different programs. Period.

3. **DMAP-VM is the only artefact that is cross-compiled per platform.** No other artefact requires platform-specific compilation.

4. **ZK proofs are data, not code.** They are never compiled. They are generated at runtime and are platform-independent.

5. **Core verifies 64-bit Unix time safety at launch.** This is the sole platform requirement. Only Core checks it. All other components trust Core.

6. **The verifier is the trust anchor for ZK.** Its correctness guarantees that invalid proofs cannot pass, regardless of the prover's integrity.

7. **Proof protocol version is bound to IMAGE_ID.** A protocol upgrade requires a new Core release and network-wide update. No mixed-version operation.

8. **There is no governance over these rules.** They are hardcoded protocol decisions. Set it and forget it.

### 31.7 Minimal ZK Boundary — Checkpoint Architecture (v2.10.33)

The zk-VM guest runs a **minimal checkpoint** of 14 essential transaction invariants. Everything else — Dilithium FACT signing, FACT chain verification, witness validation, txid computation — executes **natively** on the host at near-zero cost.

#### 31.7.1 Guest Architecture

```
Host (native, ~1ms):                    Guest (RISC-V, ~200s CPU / ~4s GPU):
┌─────────────────────┐                 ┌─────────────────────────────────┐
│ execute_core()      │                 │ execute_cl3_zkp_checkpoint()    │
│  • Dilithium sign   │                 │  • Ed25519 sig verify (precomp) │
│  • FACT chain walk  │                 │  • S-ABR state binding check    │
│  • Witness validate │                 │  • Balance math (no inflation)  │
│  • txid (BLAKE3)    │──── txid ──────▶│  • State chain (SHA3 state_id)  │
│  • fact_signature   │                 │  • Wallet seq continuity        │
│    (3,309 bytes)    │                 │  • Dust limit, scar cap, VBC    │
│                     │                 │  • zkp_nonce_hash (BLAKE3)      │
│ Attach post-proving:│◀── journal ────│  • fact_commitment (BLAKE3)     │
│  checkpoint.fact_sig│                 │  • input_hash (SHA256 precomp)  │
│  = native fact_sig  │                 └─────────────────────────────────┘
└─────────────────────┘
```

#### 31.7.2 FactCargo — Lightweight Guest Data

The guest receives `FactCargo` instead of the full `PublicOutputs` struct. This avoids deserializing large structures inside RISC-V (~877K cycles saved).

```rust
struct FactCargo {
    txid: Option<[u8; 32]>,   // 32 bytes, computed natively by Core
}
// fact_signature (3,309 bytes) stays on host — attached post-proving.
// It is independently verifiable via Dilithium PK and does not need
// STARK binding. The STARK proves input integrity + 14 invariants;
// the fact_signature proves the validator's identity.
```

#### 31.7.3 Hash Function Rules Inside Guest (NORMATIVE)

Any hash output that is **cross-checked** by Lambda or Nabla MUST use the same hash function and domain tag as the protocol definition. Failure to match causes silent verification failures at trust boundaries.

| Hash Output | Function | Domain Tag | Cross-Checked By |
|-------------|----------|------------|-----------------|
| `produced_state_id` | SHA3-256 (tiny-keccak) | `AXIOM_STATE` | All validators, clients |
| `zkp_nonce_hash` | BLAKE3 | `AXIOM_ZKP_NONCE` | Lambda CL1, Lambda CL5 |
| `fact_commitment` | BLAKE3 | `AXIOM_FACT_v2` | Core FACT link assembly (see §26.17.6.4 for sender_anchor field) |
| `input_hash` | SHA256 (precompile) | `AXIOM_ZKP_INPUT_V2` | **None** (guest-internal) |
| `auth_hash` | BLAKE3 | `AXIOM_AUTH_V1` | Lambda (conditional, 2FA) — wired v2.11.3 |

Only `input_hash` may use the SHA256 precompile (zero circuit overhead). All cross-checked hashes MUST use the protocol-defined function even though BLAKE3 runs in RISC-V software.

#### 31.7.4 Precompiles Used

| Precompile | What For | Circuit Overhead |
|------------|----------|-----------------|
| Ed25519 | Client signature verification | Zero (risc0 built-in) |
| SHA256 | input_hash (guest-internal binding) | Zero (risc0 built-in) |

Keccak precompile was evaluated and **rejected** — adds ~80s circuit overhead, net negative for our workload (few SHA3 calls).

#### 31.7.5 Benchmarks (CPU, release, single-threaded)

| Scenario | Prove | Segments | User Cycles | Seal |
|----------|-------|----------|-------------|------|
| Baseline (trivial, no crypto) | 19s | 1 | ~65K | 244KB |
| Full CL3 (ed25519 precomp + tiny-keccak) | 196s | 2 | ~970K | ~500KB |
| **Checkpoint (minimal ZK boundary)** | **200s** | **2** | **994K** | **515KB** |

Checkpoint proving time matches full CL3 because the dominant cost is Ed25519 verification code + PublicInputs deserialization inside RISC-V, not the validation logic itself. The architectural benefit is: the guest is a fixed-size program that does not grow as Core adds new validation modes.

#### 31.7.6 Projected GPU Performance

RISC Zero supports CUDA GPU proving with 10–50× speedup over CPU:

| Configuration | Per-proof | k=3 sequential | k=3 parallel (2-round) |
|---------------|-----------|----------------|----------------------|
| CPU (release) | ~200s | ~600s (10 min) | ~400s (7 min) |
| GPU (A100) | ~4–20s | ~12–60s | **~8–40s** |

With GPU proving and parallel S-ABR overlap, transaction finality approaches **8 seconds** regardless of k value.

#### 31.7.7 Subprocess Prover Protocol

Lambda MUST NOT run RISC Zero proving inside the Tokio async runtime — Rayon's thread pool deadlocks with Tokio's executor. Instead, Lambda spawns a **standalone `prover-worker` binary** as a child process and communicates via length-prefixed serde_json over stdin/stdout.

**Wire format:** 4-byte little-endian length prefix + serde_json payload.

**Request → worker (CheckpointRequest):**

| Field | Type | Description |
|-------|------|-------------|
| `inputs` | `PublicInputs` | Transaction inputs passed to zk-VM guest |
| `native_outputs` | `Option<PublicOutputs>` | Host-computed outputs for `FactCargo` extraction |

The worker calls `ZkvmProver::prove_checkpoint(inputs, native_outputs)`. The `native_outputs` field allows the worker to extract `FactCargo { txid }` — the only host-computed data the guest needs. The full `PublicOutputs` struct does NOT enter the RISC-V guest.

**Response ← worker (ProverResult):**

| Field | Type | Description |
|-------|------|-------------|
| `success` | `bool` | Whether proving succeeded |
| `outputs_json` | `Option<String>` | `ZkpCheckpointOutputs` as JSON (on success) |
| `receipt_hex` | `Option<String>` | STARK receipt bytes as hex (on success) |
| `error` | `Option<String>` | Error message (on failure) |
| `elapsed_ms` | `u64` | Wall-clock proving time |

**Determinism check:** After receiving `ZkpCheckpointOutputs`, Lambda verifies `zkp_checkpoint.produced_state_id == native_outputs.produced_state_id`. A mismatch indicates a non-determinism bug and is a hard error.

**Lifecycle:** The worker is spawned once by `SubprocessProver::new()` and loops on stdin, processing one proof per frame. Worker diagnostic output goes to stderr.

### 31.8 DMAP-VM RISC-V Interpreter Performance (v2.11.5)

The RISC-V interpreter executes Core validation at ~5–11 seconds per transaction (release build, single core). This section documents the current optimizations and a planned future improvement path.

#### 31.8.1 Implemented: Incremental Merkle Page Hashing

DMAP checkpoints require a Merkle root over all guest memory pages every 10,000 instructions. The naive approach hashes **all ~2,000 allocated pages** at each of 30,000–50,000 checkpoints per transaction — accounting for 50–70% of total execution time.

**Optimization (v2.11.5):** Page hashes are cached. Only pages dirtied since the last checkpoint (~30–50 per interval) are re-hashed. Cached hashes are reused for unchanged pages.

- **Before:** 25–58s per TX per validator
- **After:** 5–11s per TX per validator (3–5× improvement)
- **Security impact:** None. The Merkle tree is identical. DMAP attestation unchanged.

#### 31.8.2 Implemented: Flat Memory Architecture

Guest memory uses a flat `Vec<u8>` (16 MB) with O(1) indexed access, replacing the original `BTreeMap<u32, u8>` which imposed O(log n) overhead on ~2 billion memory operations per transaction.

- **Improvement:** 10–20× faster memory access
- **Security impact:** None. Memory semantics identical.

#### 31.8.3 Future: Host-Assisted Input Deserialization (PENDING SECURITY REVIEW)

**Status:** Designed, not implemented. Requires formal security analysis before adoption.

**Problem:** The guest currently deserializes CBOR-encoded `PublicInputs` byte-by-byte inside the RISC-V interpreter. This CBOR parsing accounts for ~200–400 million interpreted instructions per transaction (10–13× more than the actual validation logic), representing 20–40% of remaining execution time.

**Proposed improvement:** Replace CBOR with a flat binary format for the host→guest interface. The guest still reads and parses input bytes (DMAP boundary unchanged), but the format uses fixed-offset field layout instead of self-describing CBOR tags. Parsing cost drops from ~300M instructions to ~5–10M instructions.

**Projected improvement:** 5–11s → ~1–2s per TX.

**Implementation approach:**

1. Both input paths (CBOR and flat binary) coexist in the same Core ELF, selected by a mode byte at a fixed memory address.
2. Path selection is bound to `core_version` — all validators on the same version use the same path. No mixed-format operation.
3. Rollback to CBOR path requires only a version configuration change.

**Security considerations requiring analysis:**

- Lambda constructs the `PublicInputs` payload in both paths — it already controls what Core receives. The format change does not alter the trust relationship between Lambda and Core.
- Client Ed25519 signatures, state_id chain binding, and k=3 consensus provide integrity guarantees independent of serialization format.
- DMAP attestations produced by different input formats are not cross-comparable (different instruction counts, different checkpoint hashes). All validators in a k-set MUST use the same format.
- Formal security review MUST confirm no edge cases before production deployment.

**Decision:** The CBOR path remains the production default. The flat binary path will be implemented as an alternative when the security analysis is complete and confirms no degradation. This is a performance optimization, not a protocol change — Core validation logic is identical in both paths.

### 31.9 Wallet Secret — Cheque Redemption Authentication (v2.11.5)

#### 31.9.1 Problem

When a validator issues a cheque, it is addressed to a `receiver_wallet_id` (e.g., `bob@example.com/a1b2c3d4`). The cheque is delivered via email. If the email is intercepted, a third party could redeem the cheque by presenting their own keypair — there is no binding between the receiver's public key and the wallet_id embedded in the cheque.

#### 31.9.2 Solution: wallet_secret

Each wallet contains a **wallet_secret** — a random 32-byte value generated at wallet creation and stored encrypted in the `.axw` wallet file. The wallet_id checksum (hex8) is derived from:

```
checksum = BLAKE3(email || wallet_secret || pk_hex || salt || k_byte || proof_type_byte)[0..3]
```

This binds the wallet_id to a specific (wallet_secret, pk) pair. Without the wallet_secret, it is computationally infeasible to produce a matching checksum.

#### 31.9.3 Redeem Flow

At redeem time, the client proves wallet ownership without revealing the wallet_secret:

1. Client's local Core (WASM/DMAP-VM) runs CL5 with `wallet_secret` as input
2. CL5 verifies: `compute_checksum(email, wallet_secret, pk) == wallet_id_hex8`
3. DMAP attestation covers this execution (wallet_secret is in memory, committed by Merkle tree)
4. Client sends DMAP proof to validator (wallet_secret is NOT in the proof)
5. Validator verifies DMAP attestation structurally (CoreID + Merkle)
6. If valid: wallet ownership proven. Proceed with redeem.

**The wallet_secret never leaves the client's device.** It exists only in WASM memory during CL5 execution and in the encrypted `.axw` file.

#### 31.9.4 Validator Verification

The receiving validator does NOT need the wallet_secret. It verifies:

1. DMAP attestation is structurally valid (Merkle proofs, CoreID matches ELF)
2. The attestation's Core outputs indicate `verified: true`
3. Standard redeem checks continue (cheque signatures, balance, etc.)

Any validator can verify — no prior knowledge of the receiver required.

#### 31.9.5 Backward Compatibility — SUPERSEDED by §15 (2026-06-04 PM-2)

This section described a pre-§15 design that allowed redeem without
`cl5_execution_proof` ("legacy signature-only path"). That fallback
was the structural cause of the `FactInsufficientWitnesses` class
for stale clients (see `docs/AXIOM_HANDOFF_MacClientStaleState.md`
RESOLVED), and was deleted by CLAUDE.md §15.

**Current rule (post-§15, CoreID `4e037fb8edc6…`):**

- `cl5_execution_proof` is MANDATORY on every redeem.
- `RedeemRequestEnvelope.cl5_execution_proof: Vec<u8>` (non-optional,
  no `serde(default)`, no `skip_serializing_if`).
- Lambda rejects empty/missing with `E_LAMBDA_CL5_PROOF_MISSING`
  before any Core call (mirror of the CL1 gate at
  `consensus.rs:2421-2430`).
- Old wallets that haven't implemented `run_cl5` MUST upgrade
  before they can redeem on §15-deployed validators. There is no
  signature-only fallback. The pre-mainnet posture is "every
  client runs Core locally" — CLAUDE.md §13 (no back-compat
  bandaids while pre-mainnet) + §15 (validator action gated on
  verified Core proof).

The wallet_secret + DMAP attestation flow described in §31.9.1–
§31.9.4 is the only redeem path.

#### 31.9.6 Relationship to WALLET_IDENTITY_KEY

The wallet_secret approach **eliminates the dependency on G1 ceremony** for cheque redemption security. The WALLET_IDENTITY_KEY remains relevant for:

- Anti-typo validation by third parties (validators checking address format without the secret)
- Protocol-level wallet_id verification in contexts where the owner is not present

Both checksum derivations can coexist. The wallet_secret derivation is authoritative for ownership proof; the WALLET_IDENTITY_KEY derivation is for anti-typo convenience.

### 31.10 Wallet Address Suffixes — Client Implementation Space (INFORMATIVE)

#### 31.10.1 Principle

The AXIOM protocol defines `wallet_id` as `email/hex8` — an 8-character hex checksum appended to an email address. **The protocol treats this string as opaque.** Core, Lambda, ANTIE, and Nabla do not interpret, parse, or act on any characters beyond the `email/hex8` format.

However, client implementations (wallet applications) may append **optional suffixes** after the hex8 portion to signal capabilities to other clients. These suffixes are a **client-level convention**, not a protocol rule.

#### 31.10.2 The Protocol Boundary

```
Protocol layer (Core, Lambda, ANTIE, Nabla):
  wallet_id = "bob@example.com/a3f7b232-P"
              ↓
  parse_wallet_id() strips suffix → "bob@example.com/a3f7b232"
              ↓
  validate_wallet_id() verifies BLAKE3 checksum → ✓ anti-typo
              ↓
  Protocol uses full original string as receiver_wallet_id (opaque)

Client layer (wallet apps, ANTIE cheque delivery):
  Reads suffix: "-P" → receiver supports PGP encryption
  ANTIE checks: do I have receiver's PGP key? → encrypt cheque email
  No suffix → plaintext delivery (current default)
```

The protocol **passes the suffix along unchanged** but **never inspects it for protocol decisions.** Transaction routing, validation, consensus, DMAP — none of these depend on the suffix. A wallet_id with `-P` and without `-P` are treated identically by the protocol.

#### 31.10.3 Defined Suffixes (Client Convention)

| Suffix | Meaning | Used by |
|--------|---------|---------|
| (none) | No encryption preference | Default |
| `-P` | PGP encryption supported | Client app, ANTIE cheque delivery |
| `-G` | GPG encryption supported | Client app, ANTIE cheque delivery |

Additional suffixes may be defined by client implementations without any protocol change. The protocol will pass them through transparently.

#### 31.10.4 Why This is Not Part of the Protocol

Encryption of cheque email delivery is a **transport-layer concern**, not a consensus concern. The protocol guarantees:

1. **Transaction integrity** — Ed25519 signatures, state_id chain, k=3 consensus
2. **Cheque authenticity** — validator Dilithium signatures on cheque commitments
3. **Ownership verification** — wallet_secret + DMAP proof at redeem time

Whether the cheque email is delivered in plaintext or PGP-encrypted does not affect any of these guarantees. It affects **privacy** (who can read the cheque in transit) and **transport security** (who can intercept the cheque data). These are valid concerns, but they are solved at the client/transport layer, not the protocol layer.

This separation is intentional:

- The protocol does not mandate a specific email encryption standard
- Different client implementations may support different encryption protocols
- Validators may advertise their encryption support via VSP (§27.11 `supported_encryption` field)
- The protocol remains simple, focused, and encryption-agnostic

#### 31.10.5 Address Readability

The suffix preserves phone-readability:

```
"bob at example dot com slash a3f7b232 dash P"
```

This is no harder to communicate than the base address. The single-character suffix adds minimal overhead to verbal/written communication.


## 32. TARDIS Merge Protocol — Partition Recovery & Timestamp Attack Prevention

> **Status: Specified, implementation deferred.** The TARDIS Merge Protocol below is the normative contract once implemented; the merge state machine is not yet wired into `nabla/src/`. Implementations conforming to v2.13.00 MAY omit Phase 1-4 enforcement. Subsequent versions of this paper will mark this section "Implemented" once the state machine lands.

### 32.1 Threat Model

An attacker controlling multiple Nabla nodes AND validators (minimum 5 for
S-ABR rotation compliance) can exploit a network partition to double-spend
by manipulating TARDIS timestamps.

**Attack sequence:**

```
1. Attacker creates or exploits a network partition, isolating a subtree
2. Inside the partition, attacker shifts system clocks (earlier or later)
3. Attacker creates transactions at manipulated timestamps
4. When partition heals, transactions from both sides compete
5. If tick ordering determines priority, attacker's earlier-timestamped
   transaction wins, allowing fund cascade before detection
```

**Why timestamps cannot determine merge priority:**

TARDIS ticks are Unix timestamps validated by the 0-5 second downstream
window (§1.3). Inside a partition, all nodes validate against each other —
a partition with manipulated clocks is internally consistent. There is no
way to distinguish "real time" from "attacker time" from inside either
partition. Therefore, tick values MUST NOT be used to determine transaction
priority during merge.


### 32.2 State-ID Fork Detection (NORMATIVE)

AXIOM does not compare timestamps to detect merge conflicts. Instead,
Nabla detects forks through wallet state-ID divergence.

Each wallet has a `state_id` — a hash of its current balance state.
Every balance change produces a new `state_id`:

```
state_id_0 = hash(wallet_initial_state)
state_id_A = hash(state_id_0 || transition_A_data)
state_id_B = hash(state_id_0 || transition_B_data)
```

**Fork detection rule:**

```
IF a wallet's state_id_X appears as the input to MORE THAN ONE
   state transition (producing state_id_A and state_id_B)
THEN a fork has occurred.
ACTION: wallet enters FROZEN state immediately.
```

This detection is tick-independent. The attacker's timestamp manipulation
is irrelevant — the fork is detected purely from state-ID graph structure.


### 32.3 Recursive Taint Propagation (NORMATIVE)

When a wallet is FROZEN due to fork detection, all downstream state
transitions that depend on the forked state are TAINTED.

Every receiving wallet's `state_id` embeds a reference to the sender's
`state_id` at the time of transfer:

```
state_id_Eve  = hash(Eve_prior_state  || "received_from:state_id_B")
state_id_Frank = hash(Frank_prior_state || "received_from:state_id_Eve")
```

**Taint propagation rule:**

```
1. Forked wallet's divergent state_ids are TAINTED
   (both state_id_A and state_id_B from the fork)
2. Any state_id that references a TAINTED state_id → TAINTED
3. Propagation is recursive and exhaustive
4. A wallet with ANY tainted input is FROZEN
5. Taint is gossipped through Nabla with the same protocol as
   BANNED status (evidence-carrying gossip, §9.3)
```

The taint evidence is the fork proof: two different state transitions
from the same predecessor state_id, each signed by validators.


### 32.4 Merge Quarantine Protocol (NORMATIVE)

When a Nabla node detects partition healing (reconnection of previously
unreachable subtree), it MUST execute the following protocol:

```
PHASE 1 — PAUSE (immediate, 0 seconds)

  All wallets that appear in BOTH subtrees with DIFFERENT state_ids
  are immediately FROZEN. No new transactions for these wallets are
  accepted or processed.

  Wallets that appear in only ONE subtree, or that have IDENTICAL
  state_ids in both subtrees, are UNAFFECTED.


PHASE 2 — SCAN (0 to 75 seconds)

  Compare wallet state lists from both subtrees.
  For each wallet with differing state_ids from same predecessor:
    → Mark as FORKED
    → Begin recursive taint propagation (§32.3)
    → Gossip taint evidence to all connected Nabla nodes

  Duration: 75 seconds (3 × MATURITY_WINDOW of 25 seconds).
  This ensures taint propagation completes before any frozen wallet
  could be released.


PHASE 3 — RESOLVE (at 75 seconds)

  For each FROZEN wallet:

  a) Forked wallet (source of double-spend):
     → Status: BANNED
     → Both conflicting transactions: REJECTED

  b) Downstream wallet with tainted inputs (innocent receiver):
     → Status: NORMAL (restored — receiver had no way to know sender was forking)
     → FACT links from tainted transactions remain SCARRED (no nabla_confirmation)
     → Wallet owner may BURN scarred amount or wait for scar healing
     → Wallet can transact normally on remaining clean balance

     NOTE(review v2.10.26): This policy spares innocent downstream wallets.
     If a downstream wallet colluded with the forker, they keep ill-gotten
     gains. Mitigation: scarred FACT links track tainted lineage. Revisit
     once production data shows whether collusion is a real concern.

  d) Wallet with NO tainted inputs:
     → Released immediately (should already be unaffected from Phase 1)


PHASE 4 — RESUME (after 75 seconds)

  Normal transaction processing resumes for all non-BANNED wallets.
  BANNED wallets are permanently frozen — recovery requires
  the Ban Challenge Protocol (§33).
```


### 32.5 Timing Guarantees (NORMATIVE)

The quarantine duration of 75 seconds provides the following guarantee:

```
Quarantine window:      75 seconds
Gossip propagation:     5-25 seconds (maturity window)
Max attacker cascade:   1 TX per tick × 5 sec/tick = 15 hops in 75 seconds

Phase 1 (PAUSE) occurs at t=0, BEFORE any new transactions are accepted.
Therefore: the attacker cannot race ahead of taint propagation.
All downstream hops that occurred DURING the partition are discovered
and frozen during the SCAN phase.
```

**Critical invariant:** Phase 1 (PAUSE) MUST complete before any
post-merge transaction is accepted. This is a hard requirement on the
Nabla implementation. A node that accepts transactions before completing
the wallet state comparison is non-compliant.


### 32.6 Scope of Impact

The merge quarantine affects ONLY wallets that transacted during the
partition:

| Wallet Type | Impact |
|------------|--------|
| Dormant in both partitions | No impact |
| Active in one partition only, no conflicts | No impact |
| Active in both partitions, same state | No impact |
| Active in both partitions, different state | FROZEN → BANNED |
| Received funds from BANNED wallet | FROZEN → tainted portion BANNED |
| No connection to any conflicting wallet | No impact |

The 75 second pause is per-wallet, not network-wide. Unaffected wallets
continue to submit and redeem k=3 transactions throughout the merge with no service interruption.


### 32.7 Relationship to Existing Defenses

This protocol complements but does not replace existing defenses:

```
§9.3  BANNED gossip with evidence    → carries taint proof after merge
§1.3  TARDIS 0-5s downstream window  → still enforced within each partition
§14   S-ABR overlap requirement      → forces attacker to control 5+ validators
§15   k=3 validator consensus        → fake transactions still need 3 signatures
FACT  chain continuity               → attacker cannot create value from nothing
```

The TARDIS Merge Protocol adds the missing piece: what happens when
two internally-valid subtrees reconnect and contain conflicting wallet
states.


### 32.8 Invariants (NORMATIVE)

1. **Tick values MUST NOT determine transaction priority during merge.** Fork detection uses state-ID divergence, not timestamp comparison.

2. **Phase 1 (PAUSE) MUST complete before any post-merge transaction is accepted.** No exceptions.

3. **Taint propagation is recursive and exhaustive.** Every state_id reachable from a forked state_id is TAINTED.

4. **Merge quarantine duration is 75 seconds (3 × MATURITY_WINDOW).** This is a protocol constant.

5. **Only wallets with conflicting state in BOTH partitions are affected.** The quarantine is targeted, not network-wide.

6. **There is no "winner" between partitions.** Neither side's timestamps determine priority. Conflicts are resolved by freezing, not by choosing.

7. **A BANNED wallet from merge conflict may be reversed via Ban Challenge (§33).** If k≥3 Nabla nodes endorse the challenge and no counter-evidence arrives within CHALLENGE_WINDOW_TICKS (720), the ban is reversed and the wallet is restored to Normal. *(This reversible path is specific to the partition-merge ban, which is detected by state-ID divergence alone and is therefore **not** authorship-gated — reversibility protects an innocent partitioned wallet from a false ban. It is distinct from the authorship-gated same-sequence fork-ban (§28 Nabla; SeqForkBan), which requires the wallet's own signature over both forked states, carries no false-ban risk, and is therefore irreversible.)*


## 33. Ban Challenge Protocol (v2.11.0)

When a wallet is BANNED during merge conflict resolution (§32), the ban
may have been caused by a network partition rather than genuine double-spend.
The Ban Challenge Protocol allows innocent wallets to contest their ban.

### 33.1 BanStatus Lifecycle

```
Active      →  Challenged  →  Reversed
  ↑               ↑              ↑
  Initial ban     Counter-       No evidence
  from §32        evidence       within window
                  submitted      → wallet Normal
```

```rust
enum BanStatus {
    Active,
    Challenged {
        challenged_at: u64,                       // tick when filed
        endorsements: Vec<ChallengeEndorsement>,  // k≥3 sigs
    },
    Reversed {
        resolved_at: u64,                         // tick when reversed
    },
}

struct ChallengeEndorsement {
    nabla_node_id: [u8; 32],
    signature: Vec<u8>,  // Ed25519 over challenge commitment
}
```

### 33.2 Challenge Evidence

A `ChallengeEvidence` requires k≥3 endorsement signatures from distinct
qualified Nabla nodes:

```
ChallengeEvidence {
    wallet_id:    [u8; 32]
    endorsements: [ChallengeEndorsement; k≥3]
}
```

Each endorsement signs:
```
BLAKE3("AXIOM_BAN_CHALLENGE" || wallet_id || ban_tick)
```

### 33.3 Challenge Flow

1. Banned wallet (or advocate) collects k≥3 `ChallengeEndorsement` sigs
   from distinct qualified Nabla nodes
2. Submits `ChallengeEvidence` to any Nabla node via
   `WireMessage::BanChallenge { wallet_id, evidence }`
3. Receiving node validates:
   - Ban exists and is `Active` (not already challenged/reversed)
   - k≥3 endorsements present, all from distinct nodes
   - All signatures verify against challenge commitment
4. If valid: `BanTable::challenge()` transitions status to `Challenged`
5. Challenge is gossiped via `GossipMessage::BanChallenged`
6. Response sent: `WireMessage::BanChallengeResult { wallet_id, accepted, reason }`

### 33.4 Challenge Resolution

`check_challenge_resolution()` runs every tick (after merge quarantine
check in the tick loop):

```
const CHALLENGE_WINDOW_TICKS: u64 = 720;  // ~1 hour at 5s ticks
```

- If `current_tick - challenged_at >= CHALLENGE_WINDOW_TICKS` and no
  counter-evidence has arrived → status transitions to `Reversed`
- Reversed wallet is restored to Normal in the SMT
- Reversal is gossiped via `GossipMessage::BanReversed`

### 33.5 Constraints

- Only `Active` bans can be challenged
- Already-challenged or reversed bans → rejected
- Endorsements MUST come from distinct Nabla nodes (duplicate check)
- k≥3 endorsements required (same quorum as registration)
- Challenge window is fixed — no extensions
- Counter-evidence during the window cancels the challenge (ban remains Active)

### 33.6 Implementation

- `nabla/src/ban.rs` — `challenge()`, `check_challenge_resolution()`,
  `compute_challenge_commitment()`
- `nabla/src/types.rs` — `BanStatus`, `ChallengeEvidence`,
  `ChallengeEndorsement`
- `nabla/src/transport.rs` — `WireMessage::BanChallenge`,
  `WireMessage::BanChallengeResult`


## 34. Scar Resolution & Per-Wallet Scar Cap (v2.11.0, updated v2.11.1)

### 34.1 Scar Resolution Methods

Scars can ONLY be resolved by two methods:

1. **NablaConfirmation** (free, normal path) — receiver queries Nabla, gets confirmation
   that the transaction was registered without conflict. Scar heals automatically.
2. **Burn** (costly, last resort) — owner burns the scarred amount to `BURN_ADDRESS`.
   BurnProof (k=3 validator signatures) is back-annotated on the scarred link.

There is NO auto-resolution by time. A scar that is never healed remains a scar
forever. This is by protocol design — scars represent unverified provenance and
must not silently disappear.

#### 34.1.1 NablaConfirmation Signing Payload (Normative)

When a Nabla node confirms a registration, it signs the following payload:

```
tx_hash   = BLAKE3("AXIOM_TXHASH" || old_state || new_state)
payload   = BLAKE3("AXIOM_FACT_CONFIRM" || tx_hash || new_state)
signature = Ed25519_sign(nabla_node_key, payload)
```

The confirmation intentionally omits `wallet_id` (privacy) and `tick`
(confirmation is atemporal — the Nabla node attests that the state
transition was registered, not when). Core verifies this signature in
the FACT chain during CL2 validation.

The `tx_hash` in this payload is a **state-pair hash derived independently
at both ends** from `(old_state, new_state)` — it never travels on the wire
and is NOT `Registration.tx_hash`. The registration's `tx_hash` field is the
**protocol txid** (`Receipt.txid` = `compute_txid(tx)`, the value bound into
`receipt_commitment` and k-signed) — normative as of 2026-07-07; see the
registration flow in `AXIOM_GUIDE_Nabla.md` for the unification rationale.

The `receipt_sign_payload` used by validators at witness time is a
separate format: `wallet_id || consumed_state || produced_state || tick_le`.
These two payloads serve different purposes and MUST NOT be confused.

**FactLink::is_resolved() returns true when ANY of:**
1. `nabla_confirmation` is present (healed via Nabla)
2. `burn_proof` is present (burned by owner — §YPX-001 1.5.4)

**Compression:** `compress_fact_chain()` uses `is_resolved()` to determine the
resolved prefix. Only resolved links compress. Unresolved scars and everything
after them stay uncompressed.

> **Note:** `SCAR_AUTO_RESOLVE_SECS` and `scar_count_at()` were removed in v2.11.1.
> Auto-resolution was incorrect per protocol design. See `docs/AXIOM_REF_TransactionFlow_v1_0.md`.

### 34.2 Per-Wallet Scar Cap

```rust
const MAX_UNRESOLVED_SCARS: usize = 20;
```

During Core validation (Step 0c), if a wallet's FACT chain has >20
unresolved scars (i.e., 21 or more), new transactions FROM that wallet
are rejected (`TooManyUnresolvedScars` error). `MAX_UNRESOLVED_SCARS = 20`.

**Exemption:** Burn transactions (receiver = `BURN_ADDRESS`) are exempt.
A wallet with 20+ scars can still burn to resolve them.

### 34.3 Implementation

- `core/logic/src/types.rs` — `FactLink::is_resolved()`, `FactChain::scar_count()`
- `core/logic/src/fact.rs` — `compress_fact_chain()`, `verify_and_compress_fact_chain()`
- `lambda/src/consensus.rs` — Calls compression (no `current_time` parameter)

### 34.4 Client Responsibility: Local Transaction Records

**IMPORTANT:** It is the client's (both sender and receiver) responsibility to keep
local records of all transaction information. The protocol does not store transaction
details on Nabla — Nabla only records opaque state transitions (wallet_id, state_id,
tx_hash, tick). This is by design for privacy.

If a client loses their local transaction records:
- They cannot provide the FACT chain to future validators
- Their FACT links will be **scarred** (no NablaConfirmation possible without the data
  needed to query Nabla for verification)
- Scarred FACTs can only be resolved by Burn (costly)

**Privacy guarantee:** Nabla never stores amounts, sender/receiver relationships,
transaction details, or execution proofs. Only opaque 32-byte hashes. This prevents
Nabla operators from learning financial information about participants.

**Client applications MUST:**
1. Persist all transaction data locally (encrypted at rest recommended)
2. Back up FACT chains — loss means permanent scarring
3. Store received cheques and NablaConfirmation receipts
4. Keep validator hints for S-ABR overlap routing

See `docs/AXIOM_REF_TransactionFlow_v1_0.md` for the complete transaction lifecycle.


## 34b. Cheque Execution Proof Verification (v2.11.3)

Receiver's validators (V4, V5, V6) verify execution proofs on incoming cheques
during `process_redeem_request()`. The `ValidatorCheque.proof_type` field
(added in v2.11.1) discriminates between ZKP and DMAP proofs:

| proof_type | Proof Kind | Verification |
|------------|-----------|--------------|
| 0 (ZKP) | RISC Zero STARK | Full STARK verification + nonce binding |
| 1 (DMAP) | Memory Attestation | Structural: CoreID, challenge derivation, Merkle proofs |

**Verification order (cheap → expensive):** Ban check → DEED validation → receipt
field comparison → k=3 signature verification → execution proof verification.

**Minimum proof count (v2.11.3, GAP-C fix):** For k≥3 bundles, at least 2 valid
execution proofs are required (`verified_proof_count >= 2`). For k<3 bundles
(e.g., test mode), at least 1 is required. All k validators now produce and
attach execution proofs in their cheques — the previous optimization where only
the k-th (finalizing) validator produced a proof has been removed, as it created
a single-proof-of-execution vulnerability where 2-of-3 compromised validators
could rubber-stamp without running Core.

**DMAP verification at receiver:** Structural verification only (same as Nabla WRITER).
Re-execution is NOT required because k=3 independent sender validators already
performed re-execution when producing the attestation. Receiver trusts the k=3
independent attestations' structural integrity. **DMAP hash binding (v2.11.3):**
The verifier uses the cheque's `dmap_input_hash` / `dmap_output_hash` (covered by
validator signature) rather than the attestation's own hashes, preventing attestation
reuse across different TXs.

**ZKP verification at receiver:** Full STARK verification with three layers:
1. STARK cryptographically valid (RISC Zero verify)
2. Core logic result == Accept
3. ZKP nonce binding (anti-replay)


## 35. Production Hardening (v2.11.0)

### 35.1 Per-IP Rate Limiting

Implementations MUST bound inbound request rates. The reference
implementation's current state:

| Component | Limit | Implementation |
|-----------|-------|----------------|
| Lambda | 100 req/min per IP (sliding window) | enforced (`lambda/src/server.rs`, `axiom_rate_limit::RateLimiter`) |
| ANTIE | 60 req/min per IP (specified) | **not yet wired** — the reference ANTIE currently enforces a per-wallet cooldown (`antie/src/gateway.rs`); the per-IP limiter is a pre-mainnet TODO |

The `RateLimiter` maintains a `HashMap<IpAddr, Vec<Instant>>`. On each
`check(ip)` call: prune timestamps >60s old, reject if count exceeds
limit. Stale IP entries pruned every 100 checks.

This is distinct from the per-wallet rate limiting in Lambda (§16,
default 60 req/min per wallet PK). Per-IP limiting protects the TCP
accept loop; per-wallet limiting protects the protocol layer.

### 35.2 ANTIE Health Endpoint

ANTIE exposes HTTP health/status endpoints on `health_port` (default 7779):

```
GET /health  →  {"ok": true, "uptime_secs": <u64>}
GET /status  →  Full AntieStats JSON
```

### 35.3 ANTIE Metrics (AntieStats)

Atomic counters via `Arc<AntieStats>` (all `AtomicU64`, lock-free):

| Counter | Description |
|---------|-------------|
| messages_received | Total inbound messages |
| messages_processed | Successfully processed |
| messages_failed | Failed processing |
| tcp_connections | TCP connections accepted |
| tcp_rate_limited | Connections rejected by rate limiter |
| lambda_requests | Requests to Lambda |
| lambda_errors | Lambda failures |
| emails_sent | Outbound emails |
| started_at | Gateway start timestamp |

### 35.4 SMTP Connection Reuse

`SmtpCarrier` caches `AsyncSmtpTransport` in `Mutex<Option<...>>`.
On send: reuse if cached, rebuild on error, retry once. Avoids TLS
handshake overhead per email.

### 35.5 Admin Endpoint Hardening (AUDIT-FIX v2.11.14)

The admin HTTP endpoint (`lambda/src/admin.rs`) received three security hardening fixes:

**35.5.1 Auth Deny-by-Default**

When no `admin_token` is configured, all endpoints except `/health` return 401 Unauthorized. This replaces the previous fail-open behavior where no token meant unrestricted access — a security foot-gun on multi-user hosts or compromised local contexts. A startup warning is emitted when the token is unset.

**35.5.2 Admin Rate Limiting**

The admin HTTP server enforces 60 requests/minute per source IP using the existing `RateLimiter` infrastructure (same sliding-window algorithm as §35.1). Requests exceeding the limit receive HTTP 429 (Too Many Requests). The rate limiter is checked before request parsing to minimize resource consumption. This is distinct from the TCP-level per-IP limiting in §35.1, which protects the protocol accept loop.

**35.5.3 SSRF Prevention on Nabla Outbound Connections**

`POST /jfp/scar` accepts an optional `nabla_url` parameter to specify which Nabla node receives the SCAR registration. Previously, any URL was accepted, creating an SSRF vector (arbitrary TCP connections from the validator). Now, `nabla_url` is validated against a whitelist of known Nabla HTTP addresses (`127.0.0.1:6226-6231`). Requests with non-whitelisted URLs are rejected with a clear error.


## 36. VBC Renewal Protocol (v2.11.0)

### 36.1 Purpose

NBCs expire. Nodes must renew before expiry to remain in the network.
The renewal protocol preserves identity continuity across renewals.

### 36.2 Wire Messages

```rust
WireMessage::NbcRenewRequest {
    current_nbc_bytes: Vec<u8>,   // Serialized current NBC
    renewal_sig: Vec<u8>,         // Ed25519 proof-of-possession
    current_time: u64,            // Requester's current timestamp
}

WireMessage::NbcRenewResponse {
    accepted: bool,
    nbc_bytes: Vec<u8>,           // New NBC (if accepted)
    supporting_chain_bytes: Vec<u8>,
    rejection_reason: String,
}
```

### 36.3 Proof-of-Possession

Requester signs: `BLAKE3("AXIOM_NBC_RENEW" || validator_id || current_time)`
with their Ed25519 key. This proves control of the identity being renewed.

### 36.4 Renewal Flow

1. `check_nbc_renewal()` runs every 100 ticks
2. If NBC within renewal window (7 days before expiry), send `NbcRenewRequest`
3. Peer validates: sig OK, NBC within window, peer is qualified issuer,
   meets `NBC_ISSUER_MATURITY_SECS` (48h)
4. Peer calls `renew_nbc()` (internally reuses `issue_nbc()`)
5. **Critical:** Renewed NBC preserves `founding_vbc_hash` from OLD NBC
6. Requester installs renewed NBC: updates own_nbc_bytes, CcChain, disk

### 36.5 Constraints

```
NBC_RENEWAL_WINDOW_SECS = 7 * 86_400   // 604,800 seconds = 7 days
NBC_ISSUER_MATURITY_SECS = 48 * 3600   // 172,800 seconds = 48 hours
```

- Only within 7 days of expiry (not before, not after)
- Expired NBCs cannot be renewed — must acquire fresh NBC
- Issuer must be qualified and mature (48h)
- `founding_vbc_hash` preserved from old NBC across all renewals
- `validator_id` unchanged (BLAKE3 of SPHINCS+ key)

### 36.6 Implementation

- `nabla/src/cc.rs` — `renew_nbc()`, `CcChain::update_nbc()`
- `nabla/src/bin/nabla_node.rs` — `handle_nbc_renewal_request()`,
  `install_renewed_nbc()`, `check_nbc_renewal()`


## 37. CL1 ZKP Proof Verification (v2.11.0)

### 37.1 Purpose

CL1 can produce a ZKP proving transaction validity. CL2 verifies this
proof at the Lambda layer before proceeding.

### 37.2 Architecture

Core-logic is `no_std` — ZKP generation and verification happen at
the calling layer (Lambda's `CoreClient`), not inside `execute_cl1()`.
Same pattern as CL3.

### 37.3 Data Model

```rust
// In PublicInputs (core/logic/src/types.rs):
pub cl1_execution_proof: Option<Vec<u8>>,  // #[serde(default)]

// CBOR codec key:
const PI_CL1_EXEC_PROOF: u64 = 20;  // core/ipc/src/codec.rs
```

### 37.4 Verification Flow

```rust
// In lambda/src/core_client.rs:
struct ClientProof {
    execution_proof: Vec<u8>,
    public_inputs: PublicInputs,
}

fn validate_client_proof(&self, proof: &ClientProof) -> Result<bool> {
    let receipt = ZkvmReceipt::from_bytes(&proof.execution_proof)?;
    self.verifier.verify(&receipt)?;
    Ok(true)
}
```

Lambda verifies the CL1 proof via `ZkvmVerifier` before calling CL2.
Dev mode: empty `execution_proof` is gracefully skipped.

### 37.5 §15 — Mandatory client Core proof, structural anchor check (2026-06-04 PM-2)

Two strengthenings landed in CLAUDE.md §15 that bind §37 into a
stronger invariant. They apply to both CL1 (send-side) and CL5
(redeem-side) execution proofs:

**(a) Both proofs are now strictly mandatory.** `cl1_execution_proof`
was already enforced as MANDATORY at `lambda/src/consensus.rs:2421`
("CL1 execution proof — MANDATORY. No exceptions. No fallback").
§15 added the redeem-side mirror — `cl5_execution_proof` retyped
`Option<Vec<u8>> → Vec<u8>` on `RedeemRequestEnvelope`, with the
"legacy mode (signature-only)" fallback at the old `if let
Some(ref cl5_proof)` site deleted. Empty bytes reject with
`E_LAMBDA_CL5_PROOF_MISSING`. The `Option` wrapper survived
pre-§15 via `#[serde(default)]` on the wire field, which §13
already forbade in principle; §15 enforced it for this field.

**(b) Client-supplied state must re-derive to the k-signed
prev_receipt.** New `verify_state_anchored` in
`core/logic/src/validation.rs` recomputes
`compute_state_hash(client_pk, current_state.balance,
current_state.wallet_seq)` and rejects with `E_STATE_NOT_ANCHORED`
(carrying `RecoveryHint::ClaraHealNextSend`) on mismatch with
`prev_receipts.last().state_hash`. The check lives inside
`validate_transaction` so it covers CL1 / CL2_PREFILTER / CL2 /
CL3 / CL5 automatically. First-TX / state=None paths are
skipped (no prev_receipt to anchor TO).

Why both checks together: (a) catches malformed or forged client
runs but admits honest clients running stale Core; (b) catches
stale state but admits clients who bypassed Core entirely.
Together every validator gets the same authenticated, chain-
anchored inputs, so `produced_state_id` is bit-identical across
the k witnesses by construction. `FactInsufficientWitnesses` for
stale clients (see `AXIOM_HANDOFF_MacClientStaleState.md`,
RESOLVED) becomes unreachable; the error code survives only as
the catch for a malicious Lambda signing against the chain, at
which point the honest k-1 reject identically.

Lambda redeem-side cleanups under §15: `.unwrap_or(0)` fallbacks
on `cl5_current_balance` / `cl5_wallet_seq` /
`cl5_consumed_state_id` (`consensus.rs:5399-5403` pre-§15)
deleted in favour of explicit `E_MISSING_WALLET_STATE` reject.
The "fall back to local state if client doesn't provide one"
branch on `receiver_state` deleted as structurally dead under
§15 — first-time receivers must explicitly ship a zero-valued
`WalletState`.


## 38. Mesh Peer Rotation & Enquiry Peer (v2.11.2)

> **Note:** This section was consolidated from standalone document `YELLOWPAPER_6_3_MESH_ROTATION.md` (v2.10.19, 2026-02-21, Status: APPROVED FOR IMPLEMENTATION).

### 38.0 Problem

Once all nodes fill their peer slots to target count, the mesh
ossifies. No new node can join unless an existing peer goes offline.
A healthy network with zero failures paradoxically becomes a closed
network. The simulator proved this at 50 nodes — every node locks to
9 peers, convergence stalls at 16%, new nodes cannot participate.

### 38.1 Degree Band

Replace single target with a band. The E-peer slot is ALWAYS reserved
and never counted as a regular peer:

```
D       = target_peer_count()           // existing formula
D_reg   = D − E_PEER_MAX               // regular peer target (E-peer slot reserved)
D_lo    = D_reg − 2                    // minimum — panic-graft below this
D_hi    = D_reg + 3                    // maximum — prune weakest above this

Genesis (D=9):     D_reg=8,  D_lo=6,  D_hi=11
Production (D=12): D_reg=11, D_lo=9,  D_hi=14
Hard cap:          MESH_PEER_MAX=18 still applies
```

The gap between D_reg and D_hi is the **flex zone** — room for newcomers
to attach without forcing anyone out. A node at D_reg=8 with 10 peers is
healthy, not oversubscribed.

#### 38.1.1 Rules

- Below D_lo: panic-graft. Add peers aggressively from known_nodes
  or RequestIntroduction. Multiple per tick allowed.
- Between D_lo and D_reg: normal. Graft 1 peer per tick if candidates
  available.
- Between D_reg and D_hi: flex zone. Accept incoming connections but do
  not actively seek more.
- Above D_hi: prune lowest-scored peer immediately.
- E-peer: always separate from regular peers. 1 reserved slot.

### 38.2 Peer Scoring

Each node maintains a **local** score per active peer. Scores are
never shared with other nodes.

#### 38.2.1 Formula

```
score(peer) = (msg_rate × W1) − (staleness × W2) − (age × W3)

  msg_rate    = messages_delivered / max(1, connection_age_ticks)
  staleness   = current_tick − peer.last_seen
  age         = current_tick − peer.connected_since

  W1 = 10.0   // throughput rate bonus
  W2 =  1.0   // stale penalty per tick
  W3 =  0.1   // age decay (100 ticks ≈ 8 min → 10.0 penalty)
```

Score differentiates peers on three axes: new active peers with high
message throughput score highest. Old peers decay naturally via the age
penalty (W3), creating rotation pressure. Stale peers that stop
responding get heavily penalized (W2).

#### 38.2.2 Scoring Rules

- Score is computed on-demand, not stored (derived from `messages_delivered`,
  `last_seen`, and `connected_since` fields on PeerInfo).
- Bootstrap/genesis peers receive NO special treatment. They are
  scored identically to every other peer.
- Score is used only for eviction ordering — lowest score gets
  pruned first.

### 38.3 Rotation

Prevents mesh ossification by periodically creating open slots.

#### 38.3.1 Heartbeat (every tick)

```
1. Prune stale peers (not seen in 60 ticks = 5 minutes)
2. If peers.len() > D_hi:
     Prune lowest-scored peer
3. If peers.len() < D_lo:
     Graft from known_nodes or RequestIntroduction (multiple OK)
4. If peers.len() < D_reg:
     Graft from known_nodes or RequestIntroduction (1 per tick)
```

#### 38.3.2 Rotation (every 30 ticks = 2.5 minutes)

```
If peers.len() >= D_reg:
    Drop lowest-scored peer
    Creates 1 open slot for newcomers
```

This means across a 50-node network, approximately 20 slots open
per minute. Newcomers will find room within seconds.

#### 38.3.3 Opportunistic Grafting (every 60 ticks = 5 minutes)

```
If median(peer_scores) < 0:
    Graft up to 2 high-scoring peers from known_nodes
    (Replaces weak peers with known-good ones)
```

This is a disaster recovery mechanism. In normal operation it rarely
triggers. Under attack or after partition healing, it accelerates
mesh quality recovery.

#### 38.3.4 Knowledge Refresh (every 30 ticks = 2.5 minutes)

```
If peers.len() >= D_reg:
    Request introduction from random peer (round-robin)
    Grows known_nodes for better rotation candidates
```

Without periodic knowledge refresh, nodes at full peer count never
learn about new nodes in the network. Rotation then just cycles
through the same genesis-adjacent peers. Knowledge refresh ensures
the known_nodes pool grows continuously, enabling rotation to draw
from a diverse set of candidates and preventing convergence stalls.

### 38.4 Enquiry Peer (E-peer)

Mirrors TARDIS E slot concept on the mesh layer. Temporary passive
observation slot for homeless nodes.

#### 38.4.1 Structure

```rust
struct GossipMesh {
    // ... existing fields ...
    enquiry_peer:     Option<EnquiryPeer>,   // max 1
    last_enquiry_id:  Option<NodeId>,        // anti-camping
}

struct EnquiryPeer {
    node_id:      NodeId,
    connected_at: u64,   // tick when attached
}

const E_PEER_TTL: u64 = 12;   // 1 minute (12 ticks × 5 seconds)
```

#### 38.4.2 Rules

1. Each node has exactly **1** Enquiry peer slot.
2. A homeless node (pruned, new, or unable to find peer slot)
   connects to any known node as an Enquiry peer.
3. Host accepts if `enquiry_peer` is `None`.
4. Host sends gossip to E-peer (receive only).
5. E-peer **cannot** forward gossip to anyone. Passive listener only.
6. E-peer **does not** count toward D / D_lo / D_hi.
7. After `E_PEER_TTL` ticks (1 minute), E-peer is auto-disconnected.
8. E-peer uses received gossip to learn node_ids, observe the
   neighborhood, and identify nodes with available peer slots.
9. After disconnection (or sooner), E-peer attempts to connect as
   a real peer to a node that has room (below D_hi).

#### 38.4.3 Anti-Camping Rule

The node remembers `last_enquiry_id`. If the next E-peer request
comes from the same node_id as the previous occupant, it is
**rejected immediately**. This prevents a single node from camping
the slot indefinitely by reconnecting every 1 minute.

The restriction resets when a different node uses the E-slot:

```
A observes → A leaves → A asks again → REJECTED
A observes → A leaves → B observes → B leaves → A asks again → ACCEPTED
```

#### 38.4.4 E-peer Does NOT:

- Count toward D / D_lo / D_hi
- Forward gossip (receive only)
- Have any permanence (1 minute hard limit)
- Get special scoring or treatment
- Require any peer exchange protocol

#### 38.4.5 If E-slot is Full

The requesting node simply waits and tries again later. No redirection,
no peer exchange. The node can also try a different known node from
its bootstrap peers list.

### 38.5 Initial Node Discovery

There is no automatic peer discovery protocol. A new node operator:

1. Downloads the Nabla binary.
2. Downloads a **bootstrap.toml** file containing addresses
   of the genesis Nabla nodes (10 nodes at launch).
3. The binary reads this file at startup and uses it to bootstrap
   mesh connections.

The bootstrap file is:
- A TOML file with `[[peer]]` entries
- Contains **only genesis nodes** at launch
- Distributed via GitHub, community forums, any channel
- Easily updated — just edit and restart
- Similar to Bitcoin's seed nodes list

```toml
# bootstrap.toml
# AXIOM Nabla — Genesis nodes

[[peer]]
address = "genesis-1.axiom.network:6225"

[[peer]]
address = "genesis-2.axiom.network:6225"

[[peer]]
address = "genesis-3.axiom.network:6225"
# ...
```

New nodes connect to genesis, receive gossip, learn about other
nodes through observation, and organically build their peer list.
The network grows outward from 10 seeds. No node ever needs to
know the full network — they discover it by participating.

### 38.6 Bootstrap Peer Changes

**REMOVED from spec:**
- Bootstrap peers are no longer immune from stale-peer pruning
- Bootstrap peers are no longer immune from score-based rotation
- Genesis nodes have no special peer count or connection rules
- Genesis nodes connect to other genesis exactly the same as any
  node connects to any other node

Bootstrap peers are just the first peers a node learns about.
Once the mesh is running, they are scored and evicted identically
to every other peer. This aligns with the design goal of genesis
node retirement — the network must function without them.

### 38.7 Constants Summary

```rust
// Degree band
const MESH_PEER_BASE: usize = 9;        // D minimum (existing)
const MESH_PEER_MAX: usize = 18;        // hard cap (existing)
// D_reg = D − E_PEER_MAX              // regular peer target
// D_lo  = D_reg − 2
// D_hi  = D_reg + 3

// Rotation
const ROTATION_INTERVAL: u64 = 30;      // ticks between forced rotation
const OPPORTUNISTIC_INTERVAL: u64 = 60; // ticks between opportunistic graft
const OPPORTUNISTIC_GRAFT_COUNT: usize = 2; // max peers to graft
const KNOWLEDGE_REFRESH_INTERVAL: u64 = 30; // ticks between PX at full peers

// Stale pruning (existing)
const STALE_PEER_THRESHOLD: u64 = 60;   // ticks before peer considered stale

// Enquiry peer
const E_PEER_MAX: usize = 1;            // slots per node (always reserved)
const E_PEER_TTL: u64 = 12;             // 1 minute

// Scoring (§38.2)
// score = (msg_rate × W1) − (staleness × W2) − (age × W3)
const PEER_W1: f64 = 10.0;  // throughput rate bonus
const PEER_W2: f64 = 1.0;   // stale penalty per tick
const PEER_W3: f64 = 0.1;   // age decay
```

### 38.8 Simulation Plan

All mechanisms will be validated in the Nabla simulator before
implementation in production mesh.rs:

1. **Ossification test:** Start 50 nodes, verify mesh does NOT
   ossify — new nodes can always find slots.
2. **Rotation test:** Kill rotation, confirm ossification returns.
3. **E-peer test:** Disable E-peer, verify homeless nodes recover
   more slowly but still recover via rotation slots.
4. **Genesis retirement:** Start with 10 genesis, grow to 50 nodes,
   kill all genesis, verify network survives and maintains
   convergence above 90%.
5. **Anti-camping:** Verify same node cannot monopolize E-slot.
6. **Partition recovery:** Split network 25/25, heal partition,
   verify convergence returns to 100%.
7. **Score accuracy:** Verify active forwarding peers score higher
   than idle/stale peers across various network sizes.


## 39. Security Threat Model & Gap Analysis (v2.11.3)

> **Scope:** Full transaction pipeline — Client (CL1) → ANTIE (CL2) → Lambda (CL3/S-ABR) → Receipt → Redeem (CL5) → Nabla.
> **Method:** Layer-by-layer attack surface analysis.
> **Result:** 4 gaps found, all 4 fixed in v2.11.3. No architectural changes required.

### 39.1 Pipeline Layer Necessity

Without blockchain or central server, every layer in the pipeline replaces a specific
trust mechanism. Removing any single layer opens a concrete attack vector:

| Layer | Replaces | Attack Prevented |
|-------|----------|-----------------|
| k=3 witness | Global consensus | Single-validator fraud |
| S-ABR overlap | Shared ledger | Double-spend |
| CL2 (ANTIE) | Gateway firewall | Garbage reaching Lambda |
| CL3 (Lambda) | Consensus validation | Lambda feeding false state |
| DMAP/ZKP proofs | "Trust the miner" | Modified Core execution |
| VBC chain | PoW/PoS identity | Fake validators |
| FACT chain | Blockchain provenance | Money from nowhere |
| Silicon Pulse (§YPX-009) | Block reward economics | Lazy/colluding validators |
| Nabla registration | External confirmation | Validator-only collusion |
| State chaining | UTXO/account model | Replay / stale state |
| wallet_seq | Block ordering | Transaction ordering |

**Conclusion:** No redundant layers. No layer can be removed without opening an attack.

### 39.2 Verified Non-Gaps

The following attack vectors were analyzed and found to be adequately covered
by existing protocol mechanisms:

| Attack | Defense | Layers |
|--------|---------|--------|
| **Double-spend** | S-ABR overlap, state\_id chaining, consumed\_state tracking | 3 |
| **Replay** | wallet\_seq, consumed\_state\_id, ZKP nonce binding | 3 |
| **Man-in-the-middle** | Ed25519 TX sig, commitment\_hash binding, localhost IPC | 3 |
| **Sybil** | 3-MV-set, 30-day maturity (§10), Argon2id cost | 3 |
| **Modified Core** | DMAP re-execution, ZKP STARK verification | 2 |
| **k=3 collusion** | Design boundary — trust assumption, not a gap | — |

### 39.3 GAP-A: `auth_hash` Wallet Protection (FIXED, HIGH)

**Yellow Paper reference:** §4.5, §30.2

**Threat:** Stolen-key spending. Attacker obtains Ed25519 private key (malware, backup
compromise, physical access). Wallet owner had set `auth_hash` expecting 2FA protection.

**Fix history:**

**v2.11.3 — Lambda wiring fix:**
- `StoredWalletState.auth_hash: Option<[u8; 32]>` field added to Lambda types
- `wallets` table: `auth_hash BLOB` column added to schema
- All `WalletState` construction sites in consensus engine load `auth_hash` from storage
- `From<StoredWalletState> for WalletState` maps `auth_hash` through (was hardcoded `None`)
- Core validation now receives the stored `auth_hash` and enforces it

**v2.11.13 — Zero-knowledge upgrade (audit finding 3.1):**
The original mechanism (`BLAKE3("AXIOM_AUTH_V1" || secret)`) leaked the `owner_secret`
to every validator that processed the transaction. Field was renamed from `auth_zkp` to
`owner_proof` and the mechanism replaced with Ed25519 derived-key signatures:

- **Derivation:** `auth_sk = Ed25519_key(SHA3-256("AXIOM_OWNER_KEY" || owner_secret))`
- **Storage:** `auth_hash = auth_sk.verify_key` (32-byte Ed25519 public key)
- **Proof:** `owner_proof = Ed25519_sign(auth_sk, BLAKE3("AXIOM_OWNER_SIG" || tx_signing_message))`
- **Verification:** `Ed25519_verify(auth_hash, BLAKE3("AXIOM_OWNER_SIG" || msg), owner_proof)`

**Security properties (v2.11.13):**
- Validators see only the Ed25519 signature (64 bytes), never the `owner_secret`
- Each signature is bound to a specific transaction (signing_message binding)
- Wrong secret → wrong derived key → invalid signature → rejected
- Empty or garbage proofs fail Ed25519 verification
- 7 tests confirm: valid sig, missing proof, wrong secret, no auth_hash, tampered TX,
  empty bytes, raw secret rejection

**Backward compatibility:** `auth_hash` is `Option` — wallets without it are unaffected.
Wallets using the old BLAKE3 preimage scheme must re-register with the new Ed25519
derived key (one-time migration via `set_auth_hash` API).

### 39.4 GAP-B: Tautological DMAP Verification at Redeem (FIXED, MEDIUM)

**Threat:** DMAP attestation reuse. A malicious sender-side validator produces a valid
DMAP attestation for TX-A, then reuses that attestation for TX-B (fabricated) by
attaching it to a cheque with different transaction data.

**Root cause:** At redeem, `verify_dmap_attestation()` compared the attestation's
`input_hash` and `output_hash` against themselves — a tautology that always passes:
```
attestation.input_hash == attestation.input_hash  ← always true
```
At proof production time, hashes were independently computed from `PublicInputs` /
`PublicOutputs`, but at verification time the verifier had no independent reference.

**Mitigating factors (pre-fix):**
- The `commitment_hash` in the cheque is signed over TX-specific data — partially
  binds the cheque to the TX even if the DMAP proof doesn't.
- DMAP Fiat-Shamir challenges are derived from `validator_pk` + transaction data —
  a reused proof has wrong challenges for a different TX (but the verifier didn't
  re-derive challenges from TX data at redeem time).

**Fix (v2.11.3):**
- `ValidatorCheque.dmap_input_hash: [u8; 32]` and `dmap_output_hash: [u8; 32]` added
  (`#[serde(default)]` for backward compat)
- `WitnessProof` carries DMAP hashes from proof production to cheque creation
- New `compute_cheque_commitment_v3()` includes DMAP hashes in signed commitment
  (domain tag `AXIOM_CHEQUE_V3`), so modifying hashes invalidates the validator signature
- Redeem verifier uses cheque's hashes (not attestation's own) when non-zero
- Old cheques with zero hashes fall back to V2 commitment and tautological verification

### 39.5 GAP-C: V1/V2 Produce No Execution Proof (FIXED, LOW-MEDIUM)

**Threat:** Consensus without execution. With k=3, only the finalizing validator (V3)
produced a DMAP/ZKP execution proof. V1 and V2 returned cheques with empty
`execution_proof`. If V1 and V2 are both compromised (2 of 3), they sign the
commitment_hash without running Core — rubber-stamping the TX. The receiver accepts
the bundle because V3's single valid proof meets the `verified_proof_count >= 1` minimum.
2/3 of the "consensus" is fake.

**Mitigating factors (pre-fix):**
- S-ABR overlap: V1 stores state from this TX. If V1 is overlapped on the wallet's
  next TX, it must provide consistent state. A V1 that didn't run Core has inconsistent
  stored state → caught at next TX. But if V1 is never overlapped again (client switches
  validators), the inconsistency is never detected.
- Silicon Pulse audit chain (§YPX-009 §8.5): Argon2id chain diverges if execution was
  skipped → eventual detection on audit demand (§23.14). But detection is deferred,
  not immediate.

**Design options considered:**

| Option | Proof Count | Bandwidth | Detection |
|--------|------------|-----------|-----------|
| A: All k proofs | k=3 | ~315KB (+200%) | Immediate, all validators |
| B: k-1 proofs | 2 of 3 | ~210KB (+100%) | Immediate, majority |
| C: Deferred (Silicon Pulse) | 1 of 3 | No change | Eventual (audit demand) |

**Fix (v2.11.3, Option B):**
- All validators (V1, V2, V3) now include their DMAP execution proof in cheques.
  V1/V2 already computed DMAP proofs — they were just discarding them.
- Redeem requires `verified_proof_count >= 2` for k≥3 bundles (was `>= 1`).
  For k<3 bundles (test mode), at least 1 is required.
- A single compromised validator can no longer hide — the majority must prove execution.

### 39.6 GAP-D: Nonce Cache Accepts Inflated Balances (FIXED, LOW)

**Threat:** Cache poisoning. Lambda fabricates a `NonceResponse` with
`current_balance = 999_999_999` for a wallet that actually has 100. The DMAP-VM's
`verify_response()` accepts it (balance increased = "state advanced") and updates
its cache to the inflated value. Future nonce checks compare against the inflated
value — making subsequent legitimate TXs look like balance decreases, triggering
false mismatch flags.

**Mitigating factors (pre-fix):**
- The nonce response is an internal DMAP-VM check, not a protocol output. Actual TX
  validation uses `validate_transaction()` with real balance from Lambda's DB.
- The inflated cache causes the DMAP-VM to flag LEGITIMATE subsequent TXs as mismatches
  (false positives), which triggers audit — a self-defeating attack.
- DMAP re-execution at receiver independently validates the entire TX.

**Fix (v2.11.3, Option C from analysis):**
- `WalletCache::verify_response()` no longer updates cache on "state advanced"
- Only exact `state_id` match (proving Core computed the state) updates the cache
- Cache keeps old floor values as a conservative baseline
- Inflated balances from malicious Lambda pass once but cannot poison future checks
- No false positives: cache becomes more conservative but never rejects legitimate TXs

### 39.7 Domain Tag Registry (Normative)

Every cryptographic commitment in AXIOM uses a domain separation tag to prevent
cross-protocol replay and ensure hash isolation. This registry is the single
authoritative reference for all domain tags. Field order in the payload is normative
— implementations MUST concatenate fields in the exact order shown.

All integer fields are encoded as little-endian bytes. Variable-length string fields
(e.g., `receiver_wallet_id`, `node_name`) are encoded as raw UTF-8 bytes with no
length prefix. All `[u8; 32]` fields are raw 32-byte arrays. `oracle_claim` fields
are conditionally appended (see notes).

#### 39.7.1 Core — State & Transaction

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_STATE` | SHA3-256 | pk \|\| balance_le \|\| seq_le \|\| consumed_state_id \|\| nonce_le | Core CL2 (sender state chain) |
| `AXIOM_RECV_STATE` | SHA3-256 | receiver_pk \|\| new_balance_le \|\| wallet_seq_le \|\| txid | Core CL5 (receiver state) |
| `AXIOM_GENESIS` | SHA3-256 | public_key \|\| balance_le | Core genesis, webclient, Lambda DWP |
| `AXIOM_TXID` | BLAKE3 | consumed_state_id \|\| client_pk \|\| wallet_seq_le \|\| receiver_wallet_id \|\| amount_le \|\| nonce_le \|\| epoch_le | Core (canonical txid) |
| `AXIOM_WITNESS_V2` | BLAKE3 | consumed_state_id \|\| client_pk \|\| wallet_seq_le \|\| receiver_wallet_id \|\| amount_le \|\| nonce_le | Core CL2/CL3 (validator signs) |
| `AXIOM_REDEEM` | BLAKE3 | txid \|\| receiver_pk | Core CL5 (receiver signature) |
| `AXIOM_REDEEM_WITNESS` | BLAKE3 | txid \|\| receiver_pk \|\| new_balance_le \|\| new_state_id | Core CL5 (redeem witness sig) |
| `AXIOM_HEAL_BIND` | (suffix) | Appended to signing message: `b"AXIOM_HEAL_BIND" \|\| 0x01` when `tx.is_heal == true` | Core client sig verification |
| `AXIOM_GENESIS_CLAIM_BIND` | (suffix) | Appended to signing message: `b"AXIOM_GENESIS_CLAIM_BIND" \|\| 0x01` when `tx.is_genesis_claim == true` | Core client sig verification |
| `AXIOM_CANONICAL` | BLAKE3 | canonical_genesis_hash \|\| tick_le | Core Reality Attestation |

#### 39.7.2 Core — Cheques & Fees

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_CHEQUE_V2` | BLAKE3 | txid \|\| state_hash \|\| produced_state_id \|\| receiver_wallet_id \|\| amount_le \|\| epoch_le [*\|\| oracle_claim*] | Core CL2/CL3 cheque signing |
| `AXIOM_CHEQUE_V3` | BLAKE3 | txid \|\| state_hash \|\| produced_state_id \|\| receiver_wallet_id \|\| amount_le \|\| epoch_le \|\| dmap_input_hash \|\| dmap_output_hash [*\|\| oracle_claim*] | Core CL2/CL3 cheque signing (DMAP) |
| `AXIOM_FEE_CHEQUE` | BLAKE3 | txid \|\| validator_pk \|\| fee_amount_le | Core fee cheque commitment |
| `AXIOM_VALIDATOR_FEE` | BLAKE3 | txid \|\| validator_pk \|\| amount_le | Core validator fee commitment |
| `AXIOM_ACK_FEE` | BLAKE3 | txid \|\| validator_pk \|\| fee_amount_le | Core ACK fee commitment |
| `AXIOM_CONFIRM` | BLAKE3 | txid \|\| validator_pk \|\| receiver_pk | Core confirmation cheque |
| `AXIOM_FEE_REDEEM` | BLAKE3 | txid \|\| validator_pk | Lambda fee redemption ownership proof |

*oracle_claim fields*: When `oracle_claim` is `Some`, append: `b"ORACLE" || payout_amount_le || credit_delta_le || platform_url`.

At cheque signing: V3 is used when `dmap_input_hash` is non-zero; V2 otherwise.
At verification: same logic — the verifier computes the commitment using the same
version the signer used.

#### 39.7.3 Core — DEED System

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_DEED` | BLAKE3 | txid \|\| amount_le \|\| witness_pk | Core DEED cheque commitment |
| `AXIOM_DEED_WALLET_V1` | BLAKE3 | genesis_sphincs_pk | Core DEED wallet ID derivation |

#### 39.7.4 Core — FACT Chain

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_FACT_v2` | BLAKE3 | tx_id \|\| previous_state_id \|\| new_state_id \|\| amount_le \|\| sender_anchor_or_zeros | Core FACT link commitment (A2). `sender_anchor` is the cheque's `sender_fact_chain.tip().new_state_id` for redeem links, else 32 zero bytes. Replaces `AXIOM_FACT`. |
| `AXIOM_FACT_CHECKPOINT` | BLAKE3 | root_hash \|\| compressed_count_le \|\| final_state_id \|\| genesis_state_id \|\| genesis_fact_hash | Core FACT checkpoint commitment |
| `AXIOM_FACT_ROOT` | BLAKE3 | `b"AXIOM_FACT_ROOT"` then each link_commitment in order | Core FACT checkpoint root |
| `AXIOM_TXHASH` | BLAKE3 | previous_state_id \|\| new_state_id | Fact-confirm payload component ONLY (state-pair hash, derived identically at Nabla + Core; see §34.1.1). NOT the registration key — `Registration.tx_hash` is the protocol txid (`Receipt.txid`), normative 2026-07-07 |
| `AXIOM_FACT_CONFIRM` | BLAKE3 | tx_hash (from AXIOM_TXHASH) \|\| new_state_id | Nabla confirmation signature |
| `AXIOM_SCAR_HEAL` | BLAKE3 | original_tx_id \|\| nabla_node_id \|\| root_hash | Core CL9 scar heal commitment |
| `AXIOM_BURN` | BLAKE3 | scarred_tx_id \|\| wallet_pk \|\| amount_le | Core burn commitment (k=3 validators sign) |
| `AXIOM_GENESIS_FACT` | BLAKE3 | fact_id_le \|\| pool_total_le \|\| [sub_pool ordinal \|\| sub_pool balance_le]... \|\| headlines \|\| tick_le | Core genesis integrity |

#### 39.7.5 Core — VBC, NBC & Validator Identity

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_VBC_V09` | BLAKE3 | version \|\| validator_id \|\| sphincs_pk \|\| dilithium_pk \|\| ed25519_pk \|\| pgp_fingerprint \|\| node_name \|\| proof_cap \|\| issued_at_le \|\| expires_at_le \|\| chain_depth \|\| max_tx_le \|\| issuer_pks[0..n] | Core VBC signing payload |
| `AXIOM_NBC_RENEW` | BLAKE3 | validator_id \|\| request_time_le | Nabla NBC renewal signature |
| `AXIOM_SDID_GENESIS_V1` | BLAKE3 | (no payload, bare tag hash) | Core settlement domain ID |
| `AXIOM_LINEAGE_GENESIS_V1` | BLAKE3 | (no payload, bare tag hash) | Core lineage chain genesis |
| `AXIOM_VALIDATOR_ID` | BLAKE3 | (in test-utils; production uses `BLAKE3(sphincs_pk)` without tag) | Test utilities |

#### 39.7.6 Core — CLARA & Healing

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_CLARA_ATTEST` | BLAKE3 | wallet_pk \|\| healed_from_state_id \|\| healed_to_state_id \|\| healed_at_seq_le \|\| heal_txid \|\| garbage_count_le \|\| garbage_state_ids[0..n] \|\| bloom_era_id_le \|\| bloom_era_root \|\| nabla_tick_le \|\| healed_balance_le | Core CLARA attestation |
| `AXIOM_CLARA_HEAL` | BLAKE3 | healed_from_state_id \|\| healed_to_state_id | Nabla SMT heal entry tx_hash |

#### 39.7.7 Core — ZKP & Execution Proof

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_ZKP_NONCE` | BLAKE3 | nonce | Core/Lambda ZKP anti-replay |
| `AXIOM_ZKP_INPUT_V2` | SHA256 | consumed_state_id \|\| client_pk \|\| wallet_seq_le \|\| receiver_wallet_id \|\| amount_le \|\| reference \|\| nonce_le \|\| epoch_le \|\| client_sig [\|\| current_state fields] [\|\| owner_proof] [\|\| zkp_nonce] | zk-VM guest (internal, not cross-checked) |
| `AXIOM_DMAP_CHALLENGE_V1` | BLAKE3 | (32-byte padded tag; used as seed for Fiat-Shamir challenge derivation) | Core DMAP attestation |
| `AXIOM_DMAP_COMMIT` | BLAKE3 | (checkpoint commitment tag) | Core DMAP attestation |

#### 39.7.8 Core — Audit & Silicon Pulse

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_PULSE_PROOF` | BLAKE3 | validator_pk \|\| epoch_le \|\| full_accumulator \|\| audit_hash | Lambda/Nabla pulse proof signing |
| `AXIOM_AUDIT_CHAIN` | BLAKE3 | accumulator \|\| argon2id_output | DMAP-VM audit accumulator chain |
| `AXIOM_AUDIT_SELECT` | BLAKE3 | accumulator \|\| validator_pk | DMAP-VM Fiat-Shamir subset selection |
| `AXIOM_AUDIT_VERIFY` | BLAKE3 | subset_accumulator \|\| argon2id_output | DMAP-VM audit subset verification |
| `AXIOM_AUDIT_CHALLENGE` | BLAKE3 | (audit challenge nonce derivation domain) | Core audit demand |
| `AXIOM_NONCE_SELECT` | BLAKE3 | txid \|\| accumulator | DMAP-VM nonce challenge wallet selection |
| `AXIOM_TX_DIGEST` | (prefix) | tx_number_le \|\| sender_balance_le \|\| receiver_balance_le \|\| state_id \|\| amount_le | Core TxDigest canonical serialization |
| `AXIOM_PEER_AUDIT_V1` | (domain) | (peer audit hash domain constant) | Core peer audit |

#### 39.7.9 Core — Console Engine

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_CONSOLE_CHAIN` | BLAKE3 | generation_le \|\| seats[0..14] \|\| term_start_tick_le \|\| term_end_tick_le \|\| previous_link_hash | Core Console chain hash |
| `AXIOM_CONSOLE_ELECTION` | BLAKE3 | (election seed domain tag) | Core Console election |
| `AXIOM_CONSOLE_PICK` | BLAKE3 | selector_id \|\| picks[0..3] \|\| election_tick_le | Core selector pick commitment |
| `AXIOM_CONSOLE_FILL` | BLAKE3 | election_tick_le \|\| prev_chain_hash | Core Console deterministic seat fill |
| `AXIOM_CONSOLE_BLOOM_PHASE_OUT` | BLAKE3 | era_count_le \|\| era_ids[0..n]_le \|\| effective_tick_le \|\| current_tick_le \|\| rationale | Core CL11 bloom phase-out certificate |

#### 39.7.10 Core — FanOut & Diffusion

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_FANOUT_ID` | BLAKE3 | content \|\| originator_pk | Core CL10 diffusion ID |
| `AXIOM_FANOUT` | BLAKE3 | diffusion_id \|\| content_type_le \|\| content \|\| ttl_original \|\| fanout \|\| timestamp_le | Core CL10 originator signature |
| `AXIOM_FANOUT_DWP` | BLAKE3 | txid \|\| timestamp_le | Lambda DWP query diffusion ID |
| `AXIOM_FANOUT_JFP_RESULT` | BLAKE3 | dwp_wallet_id \|\| timestamp_le | Lambda JFP result diffusion ID |

#### 39.7.11 Core — Owner Proof & Wallet Identity

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_OWNER_KEY` | SHA3-256 | owner_secret | Core/webclient Ed25519 keypair derivation |
| `AXIOM_OWNER_SIG` | BLAKE3 | signing_message (from `compute_signing_message_public`) | Core owner proof signature |
| `AXIOM_PK_BIND` | BLAKE3 | email \|\| master_pk \|\| pk \|\| salt \|\| k_byte \|\| proof_type_byte | Core wallet_id pk binding |
| `AXIOM_MVIB` | BLAKE3 | validator_id \|\| admission_set[0..k-1] \|\| tick_le | Core MVIB commitment |
| `AXIOM_LIVING_SIG` | BLAKE3 | wallet_id (UTF-8) | Core oracle living signature |

#### 39.7.12 Lambda — DWP & JFP

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_DWP_WALLET` | BLAKE3 | txid \|\| requester_pk | Lambda DWP wallet ID derivation |
| `AXIOM_PWV_SEED` | BLAKE3 | txid \|\| my_pk | Lambda PWV decoy selection seed |
| `AXIOM_PWV_ORDER` | BLAKE3 | txid | Lambda PWV final shuffle seed |
| `AXIOM_JFP_WALLET_KEY` | BLAKE3 | txid \|\| requester_pk | Lambda JFP group wallet keypair seed |
| `AXIOM_JFP_VOTE` | BLAKE3 | vote_byte (0x01=YES, 0x00=NO) \|\| secret | Lambda JFP vote hash |
| `AXIOM_JFP_RANDOM` | BLAKE3 | dwp_wallet_id \|\| voter_index_le \|\| voting_end_tick_le | Lambda JFP random vote seed |
| `AXIOM_JFP_RANDOM_SECRET` | BLAKE3 | dwp_wallet_id \|\| voter_index_le \|\| voting_end_tick_le | Lambda JFP random vote secret |
| `AXIOM_JFP_SECRET` | BLAKE3 | dwp_wallet_id \|\| secret | Nabla JFP secret gossip synthetic wallet ID |
| `AXIOM_JFP_SCAR` | BLAKE3 | dwp_wallet_id \|\| target_pk | Lambda JFP judicial SCAR state |
| `AXIOM_JFP_ONLINE_PROOF` | BLAKE3 | (JFP online proof domain) | Lambda JFP |
| `AXIOM_MV_SELECT` | BLAKE3 | candidate_pk \|\| hour_timestamp_le | Lambda MV selector deterministic shuffle |

#### 39.7.13 Lambda — Storage & ZK-TLS

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_DB_KEY_V1` | BLAKE3 | ed25519_sk_bytes \|\| tag | Lambda transaction DB encryption key |
| `AXIOM_MGMT_DB_KEY_V1` | BLAKE3 | ed25519_sk_bytes \|\| tag | Lambda management DB encryption key |
| `AXIOM_ZKTLS_ATTEST` | BLAKE3 | server_name \|\| session_time_le \|\| transcript_hash | Lambda ZK-TLS notary attestation |

#### 39.7.14 Nabla — Registration & Gossip

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_NABLA_ROLE` | BLAKE3 | node_id \|\| role_byte (0=reader, 1=writer) \|\| wallet_id \|\| state_id \|\| tick_le | Nabla role attestation (TCP & HTTP) |
| `AXIOM_NABLA_ATTEST` | BLAKE3 | wallet_pk \|\| attested_state_id \|\| nabla_tick_le | Nabla stake attestation (CL8 input) |
| `AXIOM_STAKE_RECEIPT` | BLAKE3 | wallet_pk \|\| balance_le \|\| receipt_state_id | Core CL8 stake receipt commitment |
| `AXIOM_TXID_ATTEST` | BLAKE3 | txid \|\| status (UTF-8) \|\| tick_le | Nabla txid attestation (YPX-014), verified in Core CL5 |
| `AXIOM_REDEEM_CLAIM` | BLAKE3 | cheque_id \|\| `b"CLAIMED"` \|\| tick_le | Nabla cheque claim registration |
| `AXIOM_CHEQUE_QUERY` | BLAKE3 | cheque_id \|\| status (UTF-8, "CLAIMED"/"UNCLAIMED") \|\| tick_le | Nabla cheque query response |
| `AXIOM_WALLET_STATE` | BLAKE3 | wallet_id \|\| new_state \|\| tx_hash \|\| tick_le | Nabla client state signature (YPX-009) |
| `AXIOM_DA_CHALLENGE` | BLAKE3 | challenged_validator_pk \|\| withheld_txid \|\| challenge_tick_le | Nabla data availability challenge |
| `AXIOM_BAN_CHALLENGE` | BLAKE3 | wallet_id \|\| original_tx_id | Nabla ban challenge commitment |

#### 39.7.15 Nabla — Bloom & WAL

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_BLOOM` | BLAKE3 | hash_function_index_le(u32) \|\| txid | Nabla bloom filter hash position |
| `AXIOM_BLOOM_AGE_INDEX_ROOT` | BLAKE3 | entry_count_le \|\| [era_id_le \|\| start_tick_le \|\| end_tick_le \|\| bloom_root \|\| entry_count_le \|\| garbage_bloom_root \|\| garbage_entry_count_le]... | Nabla age index cross-node root |
| `AXIOM_WAL` | BLAKE3 | sequence_le \|\| op_discriminant(u8) \|\| payload_bytes | Nabla WAL entry checksum |
| `AXIOM_WAL_SECTION` | BLAKE3 | from_seq_le \|\| to_seq_le \|\| checksums[in range]... | Nabla WAL section hash |
| `AXIOM_SMT_EMPTY_LEAF` | (constant) | (label for empty SMT leaves) | Nabla SMT |

#### 39.7.16 Webclient & Transport

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_WALLET_ENC` | BLAKE3 | master_key | Webclient wallet encryption key derivation |
| `AXIOM_LOCAL_ENC` | BLAKE3 | password | Webclient local storage encryption key |
| `AXIOM_LOCAL_NONCE` | BLAKE3 | password \|\| plaintext_len_le | Webclient legacy nonce derivation (deprecated; backward-compat only) |
| `AXIOM_REQUEST_ENVELOPE_V1` | BLAKE3 | actor_pk \|\| request_type_le(u16) \|\| nonce_le \|\| timestamp_unix_le \|\| payload_hash | ANTIE admin request envelope |

#### 39.7.17 Ark CI & Miscellaneous

| Domain Tag | Hash | Payload Fields (in order) | Used By |
|------------|------|---------------------------|---------|
| `AXIOM_CI_V1` | (domain) | (Ark CI domain constant) | Core CI attestation |
| `AXIOM_ARK_ARTIFACT_V1` | (domain) | (Ark artifact domain constant) | Core Ark artifact binding |
| `AXIOM_IGNITION_DMAP` | BLAKE3 | (bare tag hash — used as ignition input_hash) | Lambda CL1 ignition |

#### 39.7.18 Invariants

1. **Core is the sole authority** for all domain tags in sections 39.7.1--39.7.11. Lambda MUST NOT
   compute any of these directly — it calls Core through the DMAP-VM.
2. **Field order is normative.** Reordering fields produces a different commitment and will cause
   silent verification failures across trust boundaries.
3. **Integer encoding is always little-endian.** No exceptions.
4. **String encoding is raw UTF-8 bytes** with no length prefix (the hash is streaming, so
   variable-length strings are unambiguous when they are the last field; interior strings rely
   on fixed-width fields before and after for framing).
5. **Tags are never reused across protocol versions.** A new field set requires a new tag
   (e.g., `AXIOM_CHEQUE_V2` to `AXIOM_CHEQUE_V3`).
6. **All BLAKE3 tags are 32-byte output.** SHA3-256 tags are also 32-byte output.


### 39.8 Lambda Database: Critical Infrastructure (Normative)

Lambda's sqlite database (`lambda.db`) contains **non-reconstructible state** that is
essential to protocol security. Loss of this data without recovery degrades security
guarantees from three defense layers to one (scar system only).

#### 39.8.1 Non-Reconstructible Tables

| Table | Purpose | Loss Impact |
|-------|---------|-------------|
| `redeemed_cheques` | Tracks which cheque txids have been redeemed by this validator | Per-validator only. Cross-validator double-redeem prevented by Nabla txid attestation (§39.9, YPX-014). Three-layer defense: local check + global Nabla attestation + CAS write guard. |
| `consumed_states` | Tracks which `consumed_state_id` values have been processed | Replay of consumed states possible on this validator. Mitigated by S-ABR state_id chain (v2.11.12): stored state_id passed to Core, replay mismatches. |
| `scar_passcodes` | Stores generated SCAR passcodes for scarred FACT links | Scar enforcement bypassed on this validator. Mitigated by Nabla: scarred funds cannot be registered without valid state transition. |

#### 39.8.2 Defense Layers

The protocol provides defense-in-depth beyond Lambda's local storage:

1. **Lambda DB** (primary): txid tracking, consumed-state tracking, scar passcodes
2. **Core S-ABR** (v2.11.12): stored state_id passed to Core prevents replay on overlapped validators
3. **FACT scar system**: funds from unregistered transactions are scarred and blocked
4. **Nabla double-spend detection**: conflicting state transitions rejected at the Nabla layer

If Layer 1 (Lambda DB) is lost, Layers 2-4 provide continued protection. However,
validators SHOULD treat Lambda DB loss as a **critical operational incident** requiring
investigation before resuming normal operation.

#### 39.8.3 Backup Requirements (Normative)

Validators MUST:
- Back up `lambda.db` and `management.db` at least once per hour
- Use WAL-safe backup (`sqlite3 .backup` or equivalent) to avoid corruption
- Retain backups for at least 7 days
- Verify backup integrity before pruning

Validators SHOULD:
- Monitor DB size and growth rate for anomalies
- Alert on backup failure
- Test restore procedure quarterly

A backup script is provided at `scripts/lambda-db-backup.sh`.

#### 39.8.4 Recovery Procedure

If Lambda DB is lost or corrupted:

1. **STOP** the validator immediately (kill ANTIE process)
2. **RESTORE** from most recent verified backup
3. **VERIFY** backup integrity: `sqlite3 lambda.db "PRAGMA integrity_check"`
4. **RESTART** ANTIE — Lambda will resume from restored state
5. **MONITOR** for the next 24 hours for any rejected transactions that should have been accepted (indicates backup was too old)

If no backup is available:
1. **STOP** the validator
2. Lambda will start with empty DB on next restart
3. The validator loses all txid tracking — previously redeemed cheques may be accepted again
4. The **scar system** and **Nabla double-spend detection** provide continued protection
5. **NOTIFY** the network operator — this validator's security guarantee is degraded until
   sufficient new state accumulates

#### 39.8.5 Adversarial Validation Reference

This section was added based on findings from the AXIOM adversarial validation platform
(`axiom-adversarial/`). The double-redeem vulnerability (Finding #2) demonstrated that
Lambda DB is the primary defense against cheque replay. The scar system and Nabla
provide defense-in-depth. See `axiom-adversarial/SECURITY_AUDIT_REPORT.md` Section 6b
and `axiom-adversarial/LAMBDA_TRUST_AUDIT.md` for full analysis.

### 39.9 Global Double-Redeem Prevention (YPX-018, v2.11.15)

> **Note:** This section was rewritten in v2.11.15 by YPX-018. The original v2.11.14
> design (YPX-014, single 18 MB bloom per node) saturated at ~10 M entries and is no
> longer the architecture. The wire-level attestation pattern (client fetches signed
> answer, Lambda verifies via Core CL5) is preserved; the storage layer is replaced
> with a tiered bloom chain. See `docs/AXIOM_YPX-018_HEAL_AND_TIERED_MEMORY.md` for
> the full specification.

#### 39.9.1 Problem

With k=3 witnesses and N validators (N >> k), only 3 validators record a cheque
redemption in their local `redeemed_cheques` table. The remaining N-3 validators
have no knowledge of it. An attacker can submit the same cheque bundle to a different
set of 3 validators, redeeming the same funds multiple times across disjoint validator
sets.

A second, equally serious problem was identified during the v2.11.14 audit: the
original YPX-014 single-bloom design saturates with use. At a fixed 18 MB per node,
the bloom's false positive rate climbs as more entries accumulate. Beyond ~10 M
entries the FPR is unacceptable; beyond ~100 M it is catastrophic. **A bloom false
positive on a txid lookup means a legitimate cheque is silently rejected as "already
redeemed,"** which is direct loss of user funds with no recourse.

YPX-018 addresses both problems with one architecture: a tiered bloom chain (storage)
plus a three-state attested response (correctness).

#### 39.9.2 Solution: Tiered Bloom Memory + Nabla Attestation

Each Nabla node maintains a chain of **time-bucketed bloom files**. Each file covers
a TARDIS tick range — by default a quarter (90 days). Once an era ends, its bloom
file is **frozen**: the count is fixed, the FPR is fixed, and no more entries can
be added. A new active era is opened.

Eras never go away on their own. They can only be retired by an explicit Console
action (§21.10.6, Task 4 BLOOM_PHASE_OUT) and the Core constitutional limits
guarantee that a cheque holder always has at least 55 years of redemption window
(50-year minimum era age + 5-year minimum grace period).

A second bloom chain — the **garbage state bloom** — runs alongside the txid bloom
chain. It records states declared garbage by CLARA wallet heals (§17.10.14). The
two chains share the same time-bucketing structure and the same governance.

**Protocol requirement (v2.11.15):** Before submitting a redeem request, the client
MUST query Nabla over the TCP-CBOR `WireMessage::QueryTxidRequest` wire and include the signed attestation in the
redeem request. Lambda verifies the attestation signature and acts on its three-state
result.

#### 39.9.3 Architecture: Client Fetches, Validator Verifies

Lambda MUST NOT query Nabla directly (except TARDIS requests via Core). The client
is responsible for obtaining the attestation. This maintains the architectural boundary
where validators only verify proofs provided by clients.

```
Client → Nabla: WireMessage::QueryTxidRequest { txid }   (TCP-CBOR)
Nabla → Client: NablaTxidAttestation (signed, three-state)
Client → Validator: Redeem request + txid_attestation
Validator: Verify Ed25519 signature, dispatch on status
```

#### 39.9.4 Attestation Structure

```
NablaTxidAttestation {
    txid:                [u8; 32]    — txid being attested
    status:              TxidStatus  — NotRedeemed | Redeemed | PhasedOut
    found_in_era:        Option<u64> — era id where the txid was found (if Redeemed)
    era_root_at_lookup:  [u8; 32]    — bloom-chain commitment at lookup time
    phase_out_cert:      Option<[u8; 32]> — Console certificate hash (if PhasedOut)
    registered_by:       Vec<u8>     — wallet_id (archive answer; empty otherwise)
    nabla_node_pk:       [u8; 32]    — attesting node's Ed25519 public key
    nabla_signature:     Vec<u8>     — Ed25519 signature
    nabla_tick:          u64         — freshness indicator
    nbc_issuer_pk:       Vec<u8>     — root authority SPHINCS+ PK (trust anchor)
    nbc_signature:       Vec<u8>     — SPHINCS+ signature over VBC commitment
    nbc_commitment:      Vec<u8>     — VBC signing payload (binds Ed25519 PK)
}
```

The three-state `TxidStatus` is the protocol's way of distinguishing "this cheque
is dead because someone already redeemed it" (`Redeemed`) from "this cheque is dead
because the era was retired by Console action" (`PhasedOut`) from "this cheque is
fine, proceed" (`NotRedeemed`). Each state carries a different proof.

**Signature scheme:**

```
message = BLAKE3(
    "AXIOM_TXID_ATTEST" || txid || status_byte ||
    found_in_era_le || era_root_at_lookup || phase_out_cert_or_zero ||
    nabla_tick_le
)
signature = Ed25519_sign(nabla_node_sk, message)
```

**Trust anchor (Core CL5 verified, no_std compatible):**

```
1. is_nabla_root_authority(nbc_issuer_pk) == true
2. verify_sphincs(nbc_issuer_pk, BLAKE3(nbc_commitment), nbc_signature) == OK
3. nbc_commitment.windows(32).any(|w| w == nabla_node_pk) == true
```

Flat fields, no deserialization, works in both host and RISC-V guest. Prevents
self-signed attestations: attacker cannot forge NBC without the root SPHINCS+ key.

**Phase 5f wire format note (v2.11.15-beta3):** `nbc_commitment` carries the
canonical SPHINCS+ **pre-image bytes** (`compute_vbc_signing_payload_bytes`),
NOT the BLAKE3 hash output. The verifier hashes it itself for the SPHINCS+
check, and the window-scan binding `nabla_node_pk` $\in$ `nbc_commitment` requires
the pre-image because the wallet's Ed25519 PK literally appears inside the
canonical VBC payload (per `compute_vbc_signing_payload_bytes` in
`core/logic/src/crypto.rs`). Pre-Phase-5f the field carried the hash output,
which made the window-scan check trivially broken — see YPX-018 §2.4.1 for the
security history. The same wire-format change applies to `ClaraAttestation`
in §17.10.14.

#### 39.9.5 Tiered Bloom Storage

Each Nabla node holds a chain of bloom files keyed by era. A **light node** (citizen
on a laptop) holds the bloom chain only — at planetary scale this is a few GB total
and grows slowly enough that a single laptop can run a Nabla node for the protocol's
full lifetime. An **archive node** additionally holds the full hash records for some
set of eras and is the source of authoritative answers when a bloom hit needs to be
resolved.

| Tier | Holds | Storage | Role |
|------|-------|---------|------|
| **Light** | Bloom chain + Age Index | A few GB | Lookups, gossip |
| **Archive** | Bloom chain + full hash records | Tens--hundreds of GB | Authoritative resolution |

The **Bloom Age Index** (a small SMT or KV with merkle commitment) records every
era's metadata: `era_id` $\to$ `{ start_tick, end_tick, status, txid_bloom_root, garbage_bloom_root, archive_nodes }`.
Every node holds the index — it is the protocol-level directory of which eras exist
and what their current status is.

**Why per-file FPR doesn't degrade with time:** the era is **frozen** at end_tick.
Once frozen, no more entries can be added, so the bloom's FPR is fixed at the design
target forever. A frozen file's FPR depends on its bits-per-entry, which was sized
for the actual entry count at era close. Larger files (longer eras / more entries)
just need proportionally more bits to maintain the same target FPR — not a higher
FPR. This is the structural fix for the YPX-014 saturation bug.

**Why compounded FPR across the chain stays negligible:** when a lookup walks N era
files, the probability of any file producing a false positive is approximately
`N × p`. At per-file FPR p = 10⁻¹² and N = 1000 eras (250 years of quarterly), the
compounded total is ~10⁻⁹ — about one spurious bloom hit per billion queries across
the entire history of the protocol. False positives are also recoverable (the user
queries a different Nabla node, almost certainly hitting a different shard and
getting the authoritative answer).

#### 39.9.6 Three-Layer Defense

Double-redeem prevention consists of three independent layers:

1. **Local (per-validator):** `try_mark_cheque_redeemed(txid)` — atomic check-and-mark
   in Lambda's SQLite. Catches same-validator replays. (v2.11.13 INV-04)

2. **Global (tiered bloom + cheque claim attestation):** Client-provided `NablaTxidAttestation`
   verified by Core CL5. The `/query-txid` endpoint checks BOTH the tiered bloom chain
   (post-redeem txid records) AND the §4.6 cheque claim registry (pre-redeem claims).
   If a cheque was claimed by any receiver via `/register-cheque-claim`, the attestation
   returns `REDEEMED` — Core CL5 rejects. Three-state response: `NOT_REDEEMED` (proceed),
   `REDEEMED` (double-redeem blocked), `PHASED_OUT` (era retired by Console).
   Cheque claims expire after `CHEQUE_CLAIM_EXPIRY_TICKS = 17,280` (~24 hours);
   receivers MUST complete the redeem within this window or the claim is evicted
   and the cheque becomes re-claimable. (v2.11.16)

3. **Write guard (CAS):** Compare-and-swap on receiver wallet state_id at write time.
   Catches concurrent writes on the same validator during the redeem processing window.
   (v2.11.14)

All three layers are independent — failure of any single layer is caught by the others.

#### 39.9.7 Mandatory Attestation

Redeem requests without a `txid_attestation` field are rejected. There is no fallback
to local-only checks. Every redeem is globally verified.

#### 39.9.7a Cheque Claim Proof (CL5 Step 3.5b, v2.14)

In addition to the post-redeem `txid_attestation`, redeem requests carry a
**pre-redeem `cheque_claim_proof`** — a Nabla-signed witness that the receiver
has reserved the cheque against the writer-side claim registry. Core CL5
strict-rejects when the proof is missing or invalid; this closes the
cross-validator concurrent-replay window between the receiver's `/query-txid`
lookup and Lambda's redeem write.

```
ChequeClaimProof {
    cheque_id:        [u8; 32]   — txid the proof is bound to
    receiver_pk:      Vec<u8>    — wallet PK that registered the claim
    nabla_node_pk:    [u8; 32]   — attesting Nabla writer's Ed25519 PK
    nabla_signature:  Vec<u8>    — Ed25519 signature over BLAKE3 of the
                                   AXIOM_REDEEM_CLAIM domain-tagged payload
    nabla_tick:       u64        — freshness indicator
    nbc_issuer_pk:    Vec<u8>    — root authority SPHINCS+ PK (trust anchor)
    nbc_signature:    Vec<u8>    — SPHINCS+ signature over VBC commitment
    nbc_commitment:   Vec<u8>    — VBC signing payload (binds Ed25519 PK)
}
```

**Wire integration:** `RegisterChequeClaimResponse` (Nabla `/register-cheque-claim`)
carries `proof: Option<axiom_core_logic::types::ChequeClaimProof>` as a single
typed CBOR value — *not* as 6 mirrored byte/uint fields. The SDK's
`register_cheque_claim` returns `Option<ChequeClaimProof>`; `verify_cheque`
captures the first OK proof and surfaces it to the redeem path as
`claim_proof_b64`. ANTIE forwards the typed value through to Lambda; Lambda
threads it into Core's `PublicInputs.cheque_claim_proof`.

**`client_pk` binding:** `ChequeClaimProof.client_pk` is intentionally NOT bound
to the redeemer's `receiver_pk` in CL5. The existing `verify_cheque` inline
register uses `sender_wallet_pk` (Mac's `41c73e1c` migration preserved this
semantic); binding to `receiver_pk` would break legit redeems until the
upstream `verify_cheque` is harmonised.

**CL5 Step 3.5c — chain-txid scan (defense in depth):** Independent of the
proof gate, CL5 walks the receiver's FACT chain and rejects if any prior
**redeem link** (`sender_anchor.is_some()`) carries the same `txid` — catches
replay attempts that bypass Nabla entirely. The `sender_anchor` filter is
load-bearing: send-side links MUST NOT be matched (different semantic).

**New error codes (axiom-errors crate):**
- `E_CHEQUE_CLAIM_PROOF_MISSING` — no proof on a non-genesis redeem
- `E_CHEQUE_CLAIM_PROOF_INVALID_SIG` — Ed25519 verify failed
- `E_CHEQUE_CLAIM_PROOF_TXID_MISMATCH` — `proof.cheque_id != cheque.txid`
- `E_CHEQUE_CLAIM_PROOF_RECEIVER_MISMATCH` — receiver field doesn't match
- `E_CHEQUE_CLAIM_PROOF_UNTRUSTED` — NBC trust anchor verification failed
- `E_CHEQUE_CLAIM_PROOF_EXPIRED` — `nabla_tick` outside freshness window
- `E_TXID_ALREADY_IN_RECEIVER_CHAIN` — Step 3.5c chain-scan hit

#### 39.9.8 Reference

Full specification: `docs/AXIOM_YPX-018_HEAL_AND_TIERED_MEMORY.md`
Original (superseded) design: `docs/AXIOM_YPX-014_TXID_SERVICE.md`


**Λ (Lambda) Protocol -- AXIOM Project**


---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
