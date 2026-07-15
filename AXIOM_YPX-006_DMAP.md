# AXIOM Yellow Paper Extension
## YPX-006: DMAP-VM Deterministic Memory Attestation Protocol (DMAP)
### Status: IMPLEMENTED
### Version: 0.4
### Date: 2026-03-11
### Depends On: Yellow Paper §31 (Build Architecture), DMAP-VM Development Guide v1.2, Core architecture, FACT lifecycle, Nabla node protocol, TARDIS tick system

---

## 0. Preamble — Why This Document Exists

This extension resolves the fundamental TrustMesh execution integrity problem without requiring:
- GPU hardware (RISC Zero / Jolt / any zk-VM prover)
- Trusted Execution Environments (Intel SGX / AMD SEV)
- Manufacturer attestation
- Blockchain consensus chain
- Central authority

### 0.1 The Insight

Yellow Paper §31 specifies that Core compiles ONCE to RISC-V ELF and DMAP-VM contains a RISC-V interpreter that executes it on every platform. This architecture — which is specified but not yet fully implemented — gives DMAP-VM a **deterministic, platform-independent memory model**. Any two conforming DMAP-VM interpreters executing the same RISC-V ELF with the same inputs produce byte-identical memory states at every instruction boundary.

DMAP exploits this property for lightweight execution attestation: instead of generating a 500KB STARK proof in 200 seconds, sample the DMAP-VM interpreter's memory at deterministic checkpoints and verify that the prover's memory matches an honest re-execution. Cost: milliseconds, any hardware, ~20KB attestation.

### 0.2 Relationship to Current Implementation

**Current state (v2.10.33):** DMAP-VM calls `execute_core()` directly as a Rust function (see `core/avm/src/interpreter.rs`). There is no RISC-V interpreter. The `host_functions.rs` syscall table is defined but unused. This was an intentional deferral — the interface is correct, only the internals need upgrading.

**DMAP requires:** A real RISC-V interpreter inside DMAP-VM, as §31 specifies. This document covers both:
1. Completing the §31 DMAP-VM interpreter (prerequisite)
2. DMAP attestation protocol on top of it (the new capability)

### 0.3 Threat Model

```
Without DMAP:
  Evil validator runs Modified_Core
  Modified_Core skips fee deduction / inflates balances / fabricates witnesses
  Without ZK proofs, 5-layer security cannot detect modified execution
  TrustMesh integrity collapses

With DMAP:
  Validator must prove DMAP-VM memory state at random checkpoints
  DMAP-VM memory state is deterministic function of
    canonical Core ELF (identified by CoreID) + transaction inputs
  Modified_Core produces different memory state at divergent instructions
  Caught by receiver/validator independent re-execution
  Collusion produces isolated world line — cannot interact with honest TrustMesh
```

---

## 1. Prerequisites — Completing §31 DMAP-VM Interpreter

### 1.1 Current Architecture vs §31 Specification

Yellow Paper §31.5 is explicit:

```
COMPILED ONCE (platform-independent):
  Core → RISC-V ELF        One binary for all nodes
         + IMAGE_ID         Hash of the binary

CROSS-COMPILED PER PLATFORM:
  DMAP-VM  → native binary      Contains interpreter, prover, and verifier
```

§31.6 Invariant 1: "Core is compiled to RISC-V ELF exactly once per release. It is never compiled to native code."

**Current code violates this invariant.** `AvmInterpreter::execute()` in `core/avm/src/interpreter.rs` (line 105) calls `execute_core(inputs)` — native Rust, not RISC-V interpretation. The `bytecode` field exists only for fingerprinting. The `host_functions.rs` syscall table (`SHA3_256`, `BLAKE3`, `ED25519_VERIFY`, `DILITHIUM_VERIFY`, `GET_TIME`, `GET_RUNTIME_FINGERPRINT`) is created but immediately discarded as `_host`.

### 1.2 What Must Change

To comply with §31 and enable DMAP, DMAP-VM needs:

| Component | Current | Required |
|-----------|---------|----------|
| Core binary | Rust native (recompiled per platform) | RISC-V ELF (compiled once) |
| DMAP-VM interpreter | Direct `execute_core()` call | Real RV32IM instruction interpreter |
| Host functions | Defined, unused | Wired as `ecall` handler |
| Memory model | Host allocator (platform-dependent) | Interpreter-managed (deterministic) |
| Program counter | None | RV32IM PC, pausable at checkpoints |

### 1.3 Standalone DMAP-VM Guest (New Crate: `core/avm-guest`)

The existing `core/zkvm-guest` is tied to RISC Zero's runtime (`risc0_zkvm::guest::env::{read, commit}`). A standalone RISC-V guest is needed that uses a generic syscall ABI.

```
core/avm-guest/           ← NEW: standalone RISC-V guest
├── Cargo.toml            depends on axiom-core-logic (no_std)
├── .cargo/config.toml    target = riscv32im-unknown-none-elf
└── src/
    └── main.rs           #![no_std] #![no_main], uses ecall for I/O

core/zkvm-guest/          ← UNCHANGED: RISC Zero-specific guest for ZK proofs
```

**I/O Contract (ecall-based, maps to existing host_functions.rs):**

```
ecall a7=0x01  read_inputs:   a0=buf_ptr, a1=buf_len → a0=bytes_read
ecall a7=0x02  write_outputs: a0=buf_ptr, a1=buf_len → a0=0 on success
ecall a7=0x10  host_call:     a0=func_id, a1=in_ptr, a2=in_len, a3=out_ptr → a0=out_len
```

The `host_call` syscall (0x10) maps directly to `HostFunctions::call(function_id, input)` already implemented in `core/avm/src/host_functions.rs`. No new crypto code needed.

**Both guests compile the same `axiom-core-logic` crate.** Validation logic is identical. They differ only in I/O glue.

**Build output:**

```
axiom-core.elf            RISC-V ELF binary (same for all platforms)
avm-image-id.hex          BLAKE3(axiom-core.elf) — the CoreID
```

### 1.4 RISC-V Interpreter in DMAP-VM

**Instruction set:** RV32IM (32-bit integer + multiply/divide). This matches RISC Zero's guest architecture. The same `core-logic` compiles to the same instruction set whether it runs inside RISC Zero's prover or DMAP-VM's interpreter.

**Interpreter approach:** RV32IM is ~50 instructions. A purpose-built interpreter (< 2000 lines of Rust) gives full control over the syscall interface and memory model, with zero external dependency risk over a 100-year horizon. This aligns with Yellow Paper's immutability philosophy. If expedient, `rrs-lib` (existing Rust RV32IM crate) can bootstrap the implementation, replaced later by a custom interpreter.

**Changes to `core/avm/src/interpreter.rs`:**

```rust
// NATIVE FALLBACK (used when no ELF loaded or riscv-interpreter disabled):
// Production builds always enable riscv-interpreter (default feature + Lambda/ANTIE Cargo.toml).
// This path exists as a fallback for unit tests and standalone DMAP-VM builds without ELF.
pub fn execute(&self, inputs: PublicInputs) -> Result<PublicOutputs, AvmError> {
    let _host = HostFunctions::new(0, self.runtime_fingerprint);
    let outputs = execute_core(inputs);  // ← direct Rust call (fallback only)
    Ok(outputs)
}

// AFTER (§31-compliant, enables DMAP):
pub fn execute(&self, inputs: PublicInputs) -> Result<PublicOutputs, AvmError> {
    #[cfg(feature = "riscv-interpreter")]
    if self.has_valid_elf() {
        let result = self.execute_riscv(inputs)?;
        return Ok(result.outputs);
    }
    // Native fallback (no real ELF loaded, e.g. axiom-core-bin with feature unification)
    let _host = HostFunctions::new(0, self.runtime_fingerprint);
    let outputs = execute_core(inputs);
    Ok(outputs)
}
```

**Feature-gated transition:** The `riscv-interpreter` feature flag enables real RISC-V interpretation when a valid ELF is loaded. `has_valid_elf()` checks for the ELF magic bytes (`\x7FELF`) and falls through to native `execute_core()` when the bytecode is a sentinel (e.g. `"AXIOM_CORE_V2"` used by the axiom-core-bin crate). This handles Cargo workspace feature unification, where `riscv-interpreter` may be enabled globally even in crates that don't load a real ELF. All 760+ existing tests pass with both paths.

### 1.5 CoreID and Artifact Management

**CoreID** (Yellow Paper §31.4.5):

```
CoreID = BLAKE3(axiom-core.elf)

Properties:
  - Unique per Core version
  - Computed identically on all platforms (it's a hash of the ELF, not native code)
  - Changes if any Core instruction changes
  - Published in Yellow Paper for each release
  - Validators must run CoreID matching current network canonical version
```

**Environment variables** (parallel to existing `AXIOM_ZKVM_ELF` / `AXIOM_ZKVM_IMAGE_ID`):

```
AXIOM_AVM_ELF       path to axiom-core.elf
AXIOM_AVM_IMAGE_ID  path to avm-image-id.hex (BLAKE3 of ELF)
```

**Deployment:** Both `axiom-core.elf` and `avm-image-id.hex` ship in tarballs alongside the existing `image-id.hex` (ZK artifacts). The DMAP-VM ELF is loaded at startup by `AvmInterpreter::new()`.

### 1.6 Performance Expectations

```
Current (native Rust):     execute_core() completes in < 1ms
Interpreted (RV32IM):      ~10-100ms per transaction (10-100x slowdown)
ZK proving (RISC Zero):    ~200 seconds per proof (CPU), ~4s (GPU)

Interpretation overhead:   Negligible compared to ZK proving
                          10ms vs 200,000ms = 20,000x faster
                          Acceptable on smartphones
```

### 1.7 Coexistence with ZK Pipeline

The DMAP-VM interpreter and ZK pipeline are independent:

```
                    ┌─── DMAP-VM Interpreter (DMAP path)
                    │    RV32IM execution + memory sampling
                    │    ~10-50ms, any hardware
core-logic          │
(validation rules) ─┤
                    │
                    └─── zk-VM Guest (ZK path)
                         RISC Zero execution + STARK proof
                         ~200s CPU / ~4s GPU
```

Both compile the same `core-logic`. Both produce the same `PublicOutputs`. The difference is the proof mechanism:
- DMAP: probabilistic memory attestation (fast, lightweight)
- ZK: mathematical STARK proof (slow, heavyweight, optional premium)

Lambda chooses the path per transaction based on configuration (see §5).

---

## 2. DMAP Protocol Specification

### 2.1 Foundational Property

```
Property DMAP-P1: Determinism

  Given:
    Core ELF B (identified by CoreID = BLAKE3(B))
    Transaction inputs I (PublicInputs struct)
    DMAP-VM interpreter conforming to §31

  Then:
    DMAP-VM memory state at instruction N is identical
    across all conforming interpreters on all platforms

    mem_state(B, I, N) = constant
    ∀ conforming interpreters on any platform
```

This holds because the RISC-V interpreter:
- Owns its entire memory space (not host allocator)
- Uses fixed-width types (RV32IM: 32-bit registers, byte-addressable memory)
- Has a canonical stack/heap layout defined by the ELF
- Does not use platform allocators, ASLR, or OS calls during execution
- All external operations go through deterministic `ecall` handlers

### 2.2 Checkpoint Definition

A **Checkpoint** is a snapshot of DMAP-VM interpreter state at a specific instruction count:

```rust
pub struct DmapCheckpoint {
    /// Instruction count when snapshot was taken
    pub instruction_count: u64,

    /// Program counter (RV32IM PC value)
    pub pc: u32,

    /// BLAKE3 of all 32 RV32IM registers at snapshot time
    /// Improvement E: Catches computational divergence that has not yet
    /// propagated to memory. Without this field, an attacker who modifies
    /// register arithmetic (e.g. balance calculations) can escape detection
    /// until the divergence lands in a memory page — potentially never
    /// if the modified register is discarded before a write.
    pub register_hash: [u8; 32],

    /// Merkle root of guest memory pages (4KB pages, sparse Merkle tree)
    pub memory_root: [u8; 32],
}
```

**Computing `register_hash`:**

```rust
// Collect all 32 general-purpose registers (x0–x31, each 4 bytes, RV32IM)
// x0 is hardwired to zero but must still be included for canonical serialization.
let reg_bytes: Vec<u8> = registers.iter()
    .flat_map(|r: &u32| r.to_le_bytes())
    .collect();
register_hash = blake3::hash(&reg_bytes).into();
```

This is **Improvement E**. It supersedes the previously referenced "Improvement A" label used in the v0.2 security analysis. The security analysis in §6.1 already incorporated register hashing in its detection probability calculations — this change brings the struct definition into alignment with that analysis.

Checkpoints are collected automatically during DMAP-VM execution at a configurable interval:

```
DMAP_CHECKPOINT_INTERVAL = 50_000  // snapshot every 50K instructions
```

For a typical transaction execution (~1M instructions), this produces ~100 checkpoints. Each checkpoint is 76 bytes (8 + 4 + 32 + 32). Total trace: ~7.6KB.

**Implementation note — collection semantics + JIT memory tracking.** Interior checkpoints are taken at the first instruction boundary **at or after** each interval step, not at exact multiples: the JIT executes whole basic blocks and the interpreter fuses instruction pairs, so `instruction_count` advances in jumps and rarely lands on an exact multiple of 10,000. The collector (`fast_executor.rs::run_with_checkpoints`) uses a monotonic threshold — `instruction_count >= next_checkpoint_at`, then `next_checkpoint_at += interval` (with catch-up if a block jumped past more than one boundary) — so checkpoints land "at least every interval + one block." Separately, a checkpoint's `memory_root` must reflect all writes since the previous checkpoint; JIT-compiled blocks store to guest memory through a raw pointer and bypass the interpreter's page-dirty tracking, so the JIT emits a per-page dirty-bit write after every store into a flat `jit_dirty` bytemap that `memory_root()` folds into its dirty set. (Before 2026-07-11 both mechanisms were broken — interior checkpoints never fired and JIT-written pages were invisible to the root — so production attestations carried a single, JIT-blind checkpoint; see KnownIssues KI#39.)

**Bounded collection + interval (`MAX_COLLECTED_CHECKPOINTS`, `DMAP_CHECKPOINT_INTERVAL`).** Each snapshot costs one `memory_root()` — a page-Merkle build — so collection cost is linear in the checkpoint count, and the count matters twice: at the tail (a CL5 redeem is ~600M instructions ⇒ at the original 10K interval, ~60,000 snapshots, which collapsed throughput to ~10M instr/s and made redeem hops take 60–70 s, past the SDK's 60 s poll → the finalizer's correct response mis-reported as "did not carry receiver_fact_chain"), and in the body (a typical ~8M-instruction redeem still took ~840 snapshots ⇒ ~5.5 s). Two bounds address both: **(1)** the collector caps the collected set at `MAX_COLLECTED_CHECKPOINTS` (1024) — on hitting the cap it doubles the effective interval and keeps every other checkpoint (in-stream power-of-two decimation), so a huge run coarsens instead of collecting unboundedly (total `memory_root` work `O(instructions/interval)` → `O(MAX · log(instructions/interval))`); **(2)** the base `DMAP_CHECKPOINT_INTERVAL` is 50K (was 10K), 5× fewer snapshots on the common path (~840 → ~170, ~1 s). Both are **security-transparent**: the Merkle commitment and the K reveals are taken over whatever set was collected, the verifier re-executes to each revealed checkpoint's *exact* `instruction_count`, and `N` in the detection model below is just `min(instructions/interval, 1024)`. Neither bound weakens detection — `P = 1 − (1−f)^(vK)` depends on the corrupted *fraction* `f` and reveals `K`, not `N`; a propagating cheat taints a large fraction of the (still-uniform) sample at any interval.

**Improvement F — Guaranteed Final Checkpoint:**

A final checkpoint is always appended at program termination, regardless of whether the last instruction count falls on an interval boundary:

```rust
// Inside execute_riscv() after the main instruction loop:
checkpoints.push(DmapCheckpoint {
    instruction_count: self.instruction_count,
    pc: self.pc,
    register_hash: blake3_registers(&self.registers),
    memory_root: self.memory.merkle_root(),
});
// Mark as final so verifier can identify it
// (instruction_count may not be a multiple of DMAP_CHECKPOINT_INTERVAL)
```

**Why this matters:** Without a guaranteed final checkpoint, an adversary could craft a Modified_Core that executes correctly through all interval-sampled checkpoints and then diverges in the final partial interval (e.g. instruction 1,000,001 through 1,002,347). The Fiat-Shamir challenge samples from the collected checkpoint list — if divergence occurs after the last collected checkpoint, all sampled indices precede the attack window and detection probability drops to zero for that window. The final checkpoint closes this gap unconditionally.

### 2.3 Challenge Derivation

After execution completes, a deterministic challenge selects which K checkpoints to reveal. The challenge is derived via Fiat-Shamir from public transaction data — computable by any party, unpredictable before execution completes.

```rust
/// Improvement G: validator_pk is now a required parameter.
/// §6.2 (Grinding Attack Resistance) already included validator_pk in the
/// canonical challenge formula. This update brings §2.3 into alignment with
/// §6.2. Each validator independently samples a different subset of
/// checkpoints — detection probability multiplies across k validators and
/// colluding validators cannot pre-compute a safe attestation without
/// knowing which checkpoints each honest verifier will sample.
pub fn derive_challenges(
    core_id: &[u8; 32],
    input_hash: &[u8; 32],
    output_hash: &[u8; 32],
    validator_pk: &[u8],           // Improvement G: per-validator derivation
    total_checkpoints: u64,
    num_challenges: u64,          // K, protocol constant = 24 (see §2.3.1)
) -> Vec<u64> {
    let mut indices = Vec::new();
    for i in 0..num_challenges {
        let digest = blake3::keyed_hash(
            b"AXIOM_DMAP_CHALLENGE_V1_______", // 32-byte key
            &[
                core_id.as_ref(),
                input_hash.as_ref(),
                output_hash.as_ref(),
                validator_pk,
                &i.to_le_bytes(),
            ].concat(),
        );
        let raw = u64::from_le_bytes(digest.as_bytes()[0..8].try_into().unwrap());
        indices.push(raw % total_checkpoints);
    }
    indices
}
```

**Security property:** The challenge depends on `output_hash`, which commits to all execution outputs. Before execution, outputs are unknown → challenge is unpredictable. After execution, outputs are fixed → challenge is deterministic. The prover cannot selectively modify memory at challenged checkpoints post-hoc because the challenge changes if any output changes.

### 2.3.1 Choosing K (challenge count) — why K = 24

`DMAP_NUM_CHALLENGES = 24`. This is the size↔detection sweet spot; the derivation matters because a wrong K either weakens detection or (as happened — see KnownIssues KI#39) bloats the attestation until it breaks message delivery.

**Detection model.** Let `N` be the number of checkpoints (≈ instructions ÷ `DMAP_CHECKPOINT_INTERVAL`), `f` the fraction of checkpoints a divergent execution corrupts, `v` the number of independent validators (each derives its own challenge set from its `validator_pk`, §6.2), and `K` the reveals per validator. A cheat is caught if any revealed checkpoint lands on a corrupted one. With `S = v·K` independent samples (K ≪ N, so sampling ≈ with replacement):

```
P_detect = 1 − (1 − f)^(vK)
```

**Solving for K.** For a target detection `p`, miss budget `ε = 1 − p`:

```
(1 − f)^(vK) ≤ ε
K ≥ ln(ε) / (v · ln(1 − f))   ≈   ln(1/ε) / (v · f)     (small f)
```

K grows only **logarithmically** in the confidence target (`ln(1/ε)`) and **linearly in 1/f**. The threat model — how *small* a corruption we must catch — sets the scale, not the confidence.

**The table** (p = 99.9%, so `ln(1/ε) ≈ 6.9`; v = 3; size ≈ `K·(76 + depth·32)` B, `depth = ⌈log₂N⌉ ≈ 10`):

| cheat taints f of checkpoints | samples S | K per validator | attestation size |
|---|---|---|---|
| 50% | 10 | 4 | ~3 KB |
| 25% | 24 | 8 | ~4 KB |
| **10%** | 66 | **22** | **~10 KB** |
| 5% | 138 | 46 | ~19 KB |
| 3.6% | 192 | 64 (previous) | ~26 KB |
| 1% | 690 | 230 | ~90 KB (infeasible) |
| 1 checkpoint (~0.15%) | ~4 600 | ~1 500 | impossible |

Size is **linear in K**; detection **saturates** in K for fixed f. The curve knees hard at **K ≈ 20–24**: below it you lose real coverage, above it you pay linear bytes for a shrinking threat slice.

**Why the knee is the right place — cheating DMAP is already hard.** Interior checkpoints are defence-in-depth on top of two stronger locks:

1. **CoreID binding (primary).** Every attestation carries `core_id = BLAKE3(the ELF that ran)`, and verifiers pin the canonical CoreID (Nabla `verify_zkp_proofs`, Lambda CL2/CL5). A *modified* (cheating) binary has a *different* CoreID → the attestation is rejected before a single checkpoint is examined. You cannot cheat by swapping the Core.
2. **Output binding + guaranteed final checkpoint.** `output_hash` is bound into the signed payload and Improvement F pins end-state, so tampering the *answer*, or diverging in the last partial interval, is caught directly.

The *only* residual threat the interior checkpoints address is **"canonical binary, corrupted execution"** — running the correct ELF but with execution diverging anyway (fault injection, a subverted VM, memory corruption). Such a corruption **propagates**: the wrong value flows into all downstream memory/register state, tainting a *large* fraction of checkpoints. Any divergence before ~90% of the way through execution taints `f ≥ 10%`; divergence in the last ~10% is the final checkpoint's job. At `f = 10%`, **K = 24 → 99.9% per validator ⇒ ≈ 1 − 10⁻¹⁸ across the k = 3 quorum.**

**Why not K = 64.** K = 64 (S = 192) only extends coverage from f ≥ 10% to f ≥ 3.6% — a razor-thin slice of *late-diverging, non-propagating, single-region* cheats already largely covered by the final-checkpoint guarantee — at **~2.6× the attestation size**. Because each cheque/receipt embeds k = 3 attestations and receipts chain, that increase pushed messages past the delivery caps and broke end-to-end redeem (KI#39). K = 64 also does *not* solve the minimal-cheat case it nominally targets: a single corrupted checkpoint is caught with only ~64/N ≈ 10% probability. So high K is neither necessary for propagating cheats nor sufficient for surgical ones.

**Decision.** `K = 24`, interval unchanged (10 000). Holds detection ≈ 1 − 10⁻¹⁸ against any propagating cheat across the quorum, keeps fine interior sampling, and returns the attestation to ~14 KB — the size that delivers end-to-end. A future need to catch a *surgical, non-propagating* cheat calls for a per-instruction commitment or a stronger interval guarantee, not brute-force K.

### 2.4 AttestationProof

```rust
pub struct DmapAttestation {
    /// Which axiom-core.elf was executed
    pub core_id: [u8; 32],

    /// BLAKE3 of serialized PublicInputs
    pub input_hash: [u8; 32],

    /// BLAKE3 of serialized PublicOutputs
    pub output_hash: [u8; 32],

    /// Total checkpoints collected during execution
    pub total_checkpoints: u64,

    /// Merkle root of all checkpoint hashes (commitment)
    pub checkpoint_commitment: [u8; 32],

    /// The K challenged checkpoints with Merkle proofs
    pub revealed_checkpoints: Vec<RevealedCheckpoint>,

    /// Dilithium signature over (core_id || input_hash || output_hash || checkpoint_commitment || tick)
    pub signature: Vec<u8>,

    /// TARDIS tick at time of execution
    pub tick: u64,

    /// Validator public key used for challenge derivation (Improvement G)
    /// Each validator derives different challenges, giving k×K independent samples.
    pub validator_pk: [u8; 32],
}

pub struct RevealedCheckpoint {
    /// Index in the checkpoint sequence
    pub index: u64,

    /// The checkpoint snapshot
    pub checkpoint: DmapCheckpoint,

    /// Merkle proof from this checkpoint to checkpoint_commitment
    pub merkle_proof: Vec<[u8; 32]>,
}
```

### 2.5 Verification

```rust
pub fn verify_dmap_attestation(
    attestation: &DmapAttestation,
    expected_core_id: &[u8; 32],
    public_inputs: &PublicInputs,
    public_outputs: &PublicOutputs,
    verifier_avm: &AvmInterpreter,
) -> DmapResult {

    // Step 1: Verify CoreID matches canonical
    if attestation.core_id != *expected_core_id {
        return DmapResult::WrongCore;
    }

    // Step 2: Verify input/output hash consistency
    let input_hash = blake3::hash(&serialize(public_inputs));
    let output_hash = blake3::hash(&serialize(public_outputs));
    if attestation.input_hash != *input_hash.as_bytes() {
        return DmapResult::InputHashMismatch;
    }
    if attestation.output_hash != *output_hash.as_bytes() {
        return DmapResult::OutputHashMismatch;
    }

    // Step 3: Re-derive challenges independently (Improvement G: include attester's pk)
    let expected_indices = derive_challenges(
        expected_core_id,
        &attestation.input_hash,
        &attestation.output_hash,
        &attestation.validator_pk,  // attester's pk, NOT verifier's — must match prover
        attestation.total_checkpoints,
        DMAP_NUM_CHALLENGES,
    );

    // Step 4: Verify each revealed checkpoint
    for (i, revealed) in attestation.revealed_checkpoints.iter().enumerate() {
        // 4a: Verify Merkle proof against commitment
        if !verify_merkle_proof(
            &revealed.checkpoint,
            &revealed.merkle_proof,
            revealed.index,
            &attestation.checkpoint_commitment,
        ) {
            return DmapResult::MerkleProofInvalid(i);
        }

        // 4b: Verify challenge index matches derivation
        if revealed.index != expected_indices[i] {
            return DmapResult::ChallengeMismatch(i);
        }
    }

    // Step 5: Re-execute on own DMAP-VM and spot-check
    // (Verifier runs the same inputs through their own DMAP-VM interpreter,
    //  collects checkpoints at the same indices, compares memory_root)
    let own_trace = verifier_avm.execute_with_checkpoints(
        public_inputs.clone(),
        &expected_indices,
    );
    for (i, revealed) in attestation.revealed_checkpoints.iter().enumerate() {
        if revealed.checkpoint.memory_root != own_trace[i].memory_root {
            return DmapResult::MemoryMismatch {
                index: revealed.index,
                expected: own_trace[i].memory_root,
                claimed: revealed.checkpoint.memory_root,
            };
        }
        // Improvement E: also compare register state
        if revealed.checkpoint.register_hash != own_trace[i].register_hash {
            return DmapResult::RegisterMismatch {
                index: revealed.index,
                expected: own_trace[i].register_hash,
                claimed: revealed.checkpoint.register_hash,
            };
        }
    }

    // Step 6: Verify Dilithium signature
    let signed_data = [
        attestation.core_id.as_ref(),
        attestation.input_hash.as_ref(),
        attestation.output_hash.as_ref(),
        attestation.checkpoint_commitment.as_ref(),
    ].concat();
    if !verify_dilithium(&attestation.signature, &signed_data) {
        return DmapResult::InvalidSignature;
    }

    DmapResult::Valid
}
```

---

## 3. Transaction Lifecycle with DMAP

### 3.1 Client (Sender) Flow

```
Client prepares TX:
  1. Assemble PublicInputs {mode: CL1, transaction, current_state, ...}
  2. Execute Core on DMAP-VM interpreter (real RV32IM execution)
  3. DMAP-VM collects checkpoints every DMAP_CHECKPOINT_INTERVAL instructions
  4. Compute input_hash = BLAKE3(PublicInputs)
  5. Compute output_hash = BLAKE3(PublicOutputs)
  6. Build checkpoint_commitment (Merkle root of all checkpoints)
  7. Derive challenges from (core_id, input_hash, output_hash)
  8. Reveal challenged checkpoints with Merkle proofs
  9. Sign DmapAttestation with client Ed25519 key
  10. Include DmapAttestation in TX submission
```

### 3.2 Validator (Witness) Flow

```
Validator receives TX:
  1. Verify TX structure and client signature
  2. Verify client DmapAttestation:
     a. Re-derive challenges from (core_id, input_hash, output_hash)
     b. Verify Merkle proofs for revealed checkpoints
     c. Re-execute Core on own DMAP-VM at challenged checkpoints
     d. Compare memory_root at each challenged checkpoint
     e. Mismatch → REJECT TX
  3. Verify outputs match own re-execution outputs
  4. If all pass → sign ValidatorWitness
  5. Include validator's OWN DmapAttestation in witness
     (proves validator also ran canonical Core)
```

### 3.3 Receiver Verification Flow

```
Receiver receives cheque (k=3 witnessed FACTs):
  1. Re-execute Core on own DMAP-VM
  2. Verify client DmapAttestation (same as validator step 2)
  3. Verify each of k validator DmapAttestations
  4. All k+1 attestations must agree on memory state at challenged checkpoints
  5. Any mismatch → REJECT cheque
  6. All pass → accept cheque as valid
```

### 3.4 FACT Extension

```
Existing FACT wire format gains:
  Key 20: client_dmap_attestation    (CBOR bytes, optional)
  Key 21: validator_dmap_attestations (CBOR array of bytes, optional)

Backward compatible: missing keys = no DMAP attestation (ZK proof expected instead)
```

---

## 4. Collusion Analysis

### 4.1 Evil Client Only

```
Client runs Modified_Core, submits fake attestation

Validator re-executes canonical Core independently
Derives same challenges (deterministic from output_hash)
Samples own memory → gets correct memory_root
Compares with client claim → MISMATCH
→ TX rejected at validator layer
```

### 4.2 Evil Client + Partial Validators (< k)

```
Client and 1 or 2 validators collude, fabricate attestations

Requires k=3 validator witnesses
Honest validators also re-execute Core
Honest validator memory_root ≠ colluding claim
→ Honest validator rejects TX, insufficient witnesses
```

### 4.3 Evil Client + All k Validators

```
All parties collude, fabricate consistent attestations
3 matching (but wrong) memory_root values
k witnesses obtained

Receiver re-executes Core independently
Derives same challenges
Samples own memory → correct memory_root
Compares with all k validator claims → MISMATCH
→ Cheque rejected at receiver layer
```

### 4.4 Evil Client + All k Validators + Evil Receiver

```
All parties including receiver collude

Transaction "succeeds" within colluding group
But colluding FACTs cannot be spent in honest TrustMesh:
  Any honest Nabla node re-executes Core
  Memory hash mismatch detected
  FACT rejected as invalid provenance

Result: Colluding group exists on isolated world line
        Cannot interact with honest TrustMesh
        Gains nothing of value
```

### 4.5 World Line Isolation Property (Formal)

```
For any set of colluding nodes C that fabricates attestations:

  C produces DmapAttestations with memory_root values
  derived from Modified_Core (not canonical Core)

  Any honest node H ∉ C:
    H re-executes canonical Core
    H derives same challenges (deterministic)
    H's memory_root ≠ C's memory_root
    H rejects all FACTs originating from C

  Therefore:
    FACTs from C are universally rejected by honest TrustMesh
    C is cryptographically isolated
    No explicit ban mechanism required
    Mathematics enforces isolation automatically
```

---

## 5. Proof Tiering — ZK as Optional Premium

### 5.1 Two-Tier Architecture

```
Standard Transactions (DMAP only):
  DMAP-VM re-execution + memory checkpoint sampling
  ~10-50ms per transaction
  ~20KB attestation payload
  Any hardware (smartphone to desktop)
  Probabilistic security (high confidence, not mathematical certainty)

Premium Transactions (DMAP + ZK):
  Standard DMAP attestation PLUS RISC Zero STARK proof
  ~200s CPU / ~4s GPU additional cost
  ~500KB additional proof payload
  Mathematical certainty (100% — no probabilistic residual)
  For: property transfers, large-value contracts, regulatory requirements
```

### 5.2 Lambda Configuration

```toml
[proof]
# Default attestation tier for standard transactions
default_tier = "dmap"

# Atom threshold above which ZK proof is mandatory
zkp_threshold_atoms = 1_000_000

# DMAP checkpoint interval (instructions between snapshots)
dmap_checkpoint_interval = 50_000

# Number of challenged checkpoints per attestation
dmap_num_challenges = 64
```

### 5.3 Wire Protocol

```
ProofType enum:
  0 = Zkp    (RISC Zero STARK proof — existing behavior)
  1 = Dmap   (Deterministic Memory Attestation)

CBOR tag: proof_type field in witness/cheque messages
Backward compatibility: missing proof_type defaults to Zkp
```

### 5.4 Verification at Trust Boundaries

All existing trust boundary checks (CL1 inbound, CL5 cheque redeem, Nabla registration) gain a DMAP branch:

```
if proof_type == Zkp:
    existing 3-layer STARK verification (STARK valid + Accept + nonce)
elif proof_type == Dmap:
    1. Deserialize DmapAttestation
    2. Verify validator Dilithium signature
    3. Re-execute via DMAP-VM (same inputs)
    4. Verify challenged checkpoints match
    5. Verify output_hash matches
```

---

## 6. Security Analysis

### 6.1 Detection Probability

With K challenged checkpoints out of N total, and D divergent checkpoints (where Modified_Core's memory differs from canonical):

```
P(catch) = 1 - ((N - D) / N)^S    where S = K × k (independent samples)

Example (v0.2 with improvements A-D):
  N = 20 checkpoints (1M instructions / 50K interval)
  D = 10 divergent (conservative — most modifications affect many more)
  K = 64 challenges per validator
  k = 3 independent validators (per-validator Fiat-Shamir via validator_pk)
  S = 64 × 3 = 192 independent samples

  P(catch) = 1 - (90/100)^192 = 1 - 10^(-8.8) = 99.99999984%  (8.8 nines)

For security-critical attacks (modification in first 75% of execution, r ≥ 0.25):
  P(catch) = 1 - (0.75)^192 = 1 - 10^(-24) = 99.999...9%  (≥24 nines)
```

With register hashing (Improvement A), any code modification causes ALL subsequent
checkpoints to diverge. For typical attacks (sig bypass, balance manipulation, fee
skip) D ranges from 25% to 90% of N, giving ≥13 nines detection confidence.

See `docs/DMAP_SECURITY_ANALYSIS.md` for complete mathematical proofs.

### 6.2 Grinding Attack Resistance

```
The attacker IS the validator — they produce their own attestation.
All Fiat-Shamir inputs are fixed and uncontrollable:

  challenge = BLAKE3_keyed(core_id || input_hash || output_hash || validator_pk || counter)

  - core_id: hash of canonical ELF (fixed)
  - input_hash: hash of transaction inputs (fixed by the transaction)
  - output_hash: if modified → consensus rejects (other k-1 validators disagree)
  - validator_pk: attacker's identity (fixed, can't impersonate)

There is nothing to grind. The challenge is a single deterministic value.
The attacker gets one roll of the dice per transaction.
```

### 6.3 Memory Layout Reverse Engineering

```
Attack: Study DMAP-VM memory layout, craft Modified_Core that preserves
        memory at most checkpoint-sampled regions

Mitigation:
  Challenge indices are pseudorandom over ALL checkpoints
  Attacker must preserve correct memory at EVERY checkpoint
  (because they don't know which K will be challenged)
  This is equivalent to running the correct Core

  Multi-checkpoint sampling (§2.2) captures memory_root = Merkle root
  of ALL memory pages. Changing any byte in any page changes the root.
  Modified_Core cannot "hide" modifications within a page.
```

### 6.4 Comparison with ZK

```
                    DMAP                    ZK (RISC Zero STARK)
Certainty:          Probabilistic           Mathematical
                    (>99.99% with k=3)      (100%)
Proof time:         ~10-50ms                ~200s CPU / ~4s GPU
Proof size:         ~20KB                   ~500KB
Verification:       Re-execution (~10ms)    STARK verify (~44ms)
Hardware:           Any (smartphone OK)     GPU recommended for proving
Complexity:         ~2000 lines interpreter ~50K lines prover
```

---

## 7. Interaction with Existing Protocol Layers

### 7.1 WAL Integration

```
Each WAL record includes:
  Existing fields (tick, sender, receiver, amount, fee, nonces)
  New field: attestation_hash = BLAKE3(serialized DmapAttestation)

WAL hash chain now commits to DMAP attestations
Tampering with attestations breaks WAL hash chain
Detected by existing WAL gossip verification
```

### 7.2 TARDIS Integration

```
DMAP attestations include tick value
Tick is part of PublicInputs
Therefore part of input_hash
Therefore part of challenge derivation

Backdated TX uses old tick → different input_hash → different challenges
Existing TARDIS protection still applies
DMAP adds no new exposure here
```

### 7.3 Scar Propagation

```
Scar flag is part of TransactionInputs
Therefore affects DMAP-VM memory state during execution
Therefore affects memory_root at checkpoints

Attempting to strip scar:
  DMAP-VM memory state differs (no scar_flag processing)
  memory_root differs at divergent checkpoints
  → Detected by receiver verification

DMAP strengthens scar propagation enforcement
```

### 7.4 S-ABR Overlap

```
S-ABR requires k overlapping validators to independently verify
Each validator runs its own DMAP-VM interpreter
Each produces its own DmapAttestation
All attestations must agree on memory state at challenged checkpoints

Combined with DMAP: k independent re-executions
Each catches modifications with probability P(catch)
Combined probability: 1 - (1 - P(catch))^k → extremely high

This is the strongest layer of DMAP security
```

---

## 8. Implementation Plan

### Phase 1: DMAP-VM RISC-V Interpreter (§31 Compliance)

```
Priority: HIGH — prerequisite for everything else

New files:
  core/avm-guest/Cargo.toml              New crate: standalone RISC-V guest
  core/avm-guest/src/main.rs             Guest entry point with ecall I/O
  core/avm-guest/.cargo/config.toml      RISC-V target configuration
  core/avm/src/riscv/mod.rs              RV32IM interpreter module
  core/avm/src/riscv/decoder.rs          Instruction decoder (~50 instructions)
  core/avm/src/riscv/executor.rs         Instruction executor + memory model
  core/avm/src/riscv/memory.rs           Guest memory with page-level Merkle tree
  core/avm/src/riscv/elf_loader.rs       Minimal ELF parser for loading sections
  core/avm/src/config.rs                 DMAP-VM ELF configuration (env vars)

Modified files:
  core/avm/Cargo.toml                    Add riscv-interpreter feature
  core/avm/src/interpreter.rs            Real RV32IM execution path
  core/avm/src/host_functions.rs         Wire as ecall handler
  core/avm/src/lib.rs                    Export riscv module
  core/bin/src/main.rs                   Load DMAP-VM ELF from config
  Cargo.toml (workspace)                 Add core/avm-guest to workspace
  scripts/build_all.sh                   Add axiom-core.elf build step

Verification:
  All 760 existing tests pass (feature-gated, default = direct call)
  New tests verify RV32IM path produces identical PublicOutputs
  Cross-platform determinism test: same inputs → same memory state
```

### Phase 2: DMAP Protocol

```
Priority: HIGH — the payoff

New files:
  core/avm/src/dmap/mod.rs               DMAP types, constants
  core/avm/src/dmap/checkpoint.rs         Checkpoint collection during execution
  core/avm/src/dmap/challenge.rs          Challenge derivation (Fiat-Shamir)
  core/avm/src/dmap/attestation.rs        AttestationProof construction
  core/avm/src/dmap/verification.rs       AttestationProof verification
  core/avm/src/dmap/merkle.rs             Sparse Merkle tree for memory pages

Modified files:
  core/avm/src/interpreter.rs             Checkpoint collection in execute loop
  core/avm/src/core_handle.rs             Return DmapTrace alongside PublicOutputs
  core/avm/src/lib.rs                     Export dmap module
  core/logic/src/types.rs                 DMAP protocol constants
  core/ipc/src/codec.rs                   CBOR tags for DMAP attestation
  lambda/src/core_client.rs               DMAP proving path in produce_witness
  nabla/src/registration.rs               DMAP verification path

Verification:
  Determinism: same inputs → same checkpoints → same memory_roots
  Modified_Core detection: altered logic → caught by DMAP verification
  Replay prevention: different TX → different challenges → replayed proof rejected
  Full lifecycle: client attest → validator verify + re-attest → receiver verify
  Collusion isolation: colluding group's FACTs rejected by honest nodes
```

### Phase 3: ZK Becomes Optional Premium Tier

```
Priority: MEDIUM — optimization, not correctness

Modified files:
  lambda/src/config.rs                    Add [proof] config section
  lambda/src/core_client.rs               Tier routing logic
  core/logic/src/types.rs                 ProofType enum (Zkp, Dmap)
  core/ipc/src/codec.rs                   CBOR tag for proof_type
  nabla/src/transport.rs                  proof_type in wire messages
  nabla/src/registration.rs               Dual verification (DMAP or ZK)

SubprocessProver and zk-VM pipeline remain unchanged.
ZK path is always available for high-value transactions.
```

---

## 9. Protocol Constants

```rust
/// CoreID = BLAKE3(axiom-core.elf)
/// Published per protocol version. All validators must match.
pub const CANONICAL_CORE_ID: [u8; 32] = [...]; // TBD at first build

/// Instructions between DMAP checkpoints
pub const DMAP_CHECKPOINT_INTERVAL: u64 = 50_000;

/// Number of checkpoints challenged per attestation (Fiat-Shamir)
pub const DMAP_NUM_CHALLENGES: u64 = 64;

/// BLAKE3 domain separation for challenge derivation
/// Must be exactly 32 bytes (BLAKE3 keyed hash requirement)
pub const DMAP_CHALLENGE_DOMAIN: &[u8; 32] = b"AXIOM_DMAP_CHALLENGE_V1\x00\x00\x00\x00\x00\x00\x00\x00\x00";

/// Guest memory page size for Merkle tree (4KB)
pub const DMAP_PAGE_SIZE: u32 = 4096;

/// Maximum guest memory (16MB — sufficient for Core execution)
pub const DMAP_MAX_MEMORY: u32 = 16 * 1024 * 1024;
```

---

## 10. Open Questions

```
Q1: RV32IM vs RV32IMAC
    RISC Zero uses rv32im. Do we need atomics (A) or compressed (C)?
    Recommendation: Start with rv32im to match zk-VM guest compatibility.

Q2: Checkpoint interval tuning
    50K instructions is the current interval (raised from 10K for throughput). Profile actual Core execution
    to determine optimal interval (balance: more checkpoints = higher
    detection probability but larger attestation).

Q3: Memory Merkle granularity
    4KB pages is standard but may be too coarse for small modifications.
    Consider 256-byte pages (more Merkle nodes but finer detection).

Q4: Client attestation key
    Clients currently use Ed25519. Should DMAP client attestations use
    Ed25519 (fast, existing) or Dilithium (post-quantum, consistent with
    validator attestations)? Recommendation: Ed25519 for clients
    (matching existing CL1 client signature), Dilithium for validators.

Q5: Attestation size budget
    Current ZK proof: ~500KB. DMAP target: ~20KB.
    Verify this fits within existing wire message size limits.

Q6: Backward compatibility period
    How long to support mixed DMAP/ZK networks during transition?
    Recommendation: one protocol version (until next mandatory upgrade).
```

---

## 11. Relationship to ZK — Final Position

DMAP is not ZK. It is **probabilistic deterministic execution attestation**. The distinction:

```
ZK (RISC Zero):
  Mathematical proof of execution
  100% certainty
  GPU recommended for production
  200 seconds (CPU) / 4 seconds (GPU)
  ~500KB proof

DMAP:
  Probabilistic evidence of correct execution
  >99.99% confidence (with k=3 validators)
  Any hardware (smartphone to desktop)
  ~10-50ms
  ~20KB attestation
  Combined with 5-layer security + S-ABR overlap = sufficient
  for TrustMesh threat model

Decision:
  DMAP replaces ZK as PRIMARY execution attestation
  ZK retained as OPTIONAL premium tier
  for maximum-assurance transactions
  Standard transactions: DMAP only
  High-value transactions: DMAP + ZK (configurable threshold)
```

---


---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
