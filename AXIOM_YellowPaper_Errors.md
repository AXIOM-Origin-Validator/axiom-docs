# AXIOM Errors — Yellow Paper

**Status:** Draft — Phase 1 of the structured errors initiative.
**Scope:** Wire format and behavior contract for error responses from
Core, Lambda, Nabla, and ANTIE to client SDKs. Companion spec to
`AXIOM_YellowPaper.md` and `AXIOM_YellowPaper_SDK.md`.

**Not a YPX:** this is a client-facing contract, not a protocol
extension. It specifies how errors are represented on the wire and what
clients are required to do with them. The protocol itself doesn't
change.

**Depends on:** `AXIOM_REF_ErrorTaxonomy.md` (Phase 0 enumeration) for the
complete list of error variants this document assigns codes to.

---

## 1. Why

Tonight's 8-day hash-mismatch debugging marathon had a single
underlying cause: **errors were strings, not structured data, so every
recovery decision was a substring match on a human-readable message**.
The same problem will hit every future client implementation and
every future incident response, so the fix is a one-time protocol-level
investment in how errors cross the wire.

**What this spec delivers:**

1. A stable, machine-readable error code for every error Core, Lambda,
   Nabla, and ANTIE can return (~250 variants today).
2. A four-way category enum that tells the client what it MUST do with
   the error (surface to user, run recovery, retry, fix client code).
3. Typed, optional detail fields that carry the context the client
   needs to dispatch the correct recovery (the validator's stored
   state on a mismatch, the number of overlap sigs available on an
   insufficient-overlap failure, the retry_after timestamp on a rate
   limit).
4. A recovery hint enum that names the exact recovery function the
   client SHOULD call, dispatched by category.
5. A versioned, backward-compatible wire format so old clients continue
   to parse new errors as gracefully degraded strings.
6. A debug-mode gate that exposes internal detail to the wallet owner
   without leaking validator state to unauthorized readers.

The SDK Yellow Paper's "10-function surface + internal state machine"
model assumes this spec exists. Without structured errors, the SDK's
internal dispatch logic has no clean way to decide "run resync" vs
"run CLARA heal" vs "retry in 30s" — it has to substring-match on
string errors and hope. With this spec, the dispatch is a switch on
`category` and `recovery`.

## 2. Wire format

### 2.1 `ErrorResponse` (NORMATIVE)

Every error response from Core, Lambda, Nabla, and ANTIE across any
RPC or HTTP boundary MUST be serializable as the following struct:

```rust
pub struct ErrorResponse {
    /// Stable code identifying the error class. Format: "E_<DOMAIN>_<NAME>".
    /// Examples: "E_SABR_HASH_MISMATCH", "E_INSUFFICIENT_BALANCE".
    /// See §6 for allocation rules and §Appendix A for the full registry.
    /// Clients MUST match on this field for dispatch. MUST NOT match on `message`.
    pub code: ErrorCode,

    /// What the client is required to do with this error. See §3 for the
    /// per-category contract. Clients MUST respect the category semantics.
    pub category: ErrorCategory,

    /// Human-readable message, English, suitable for developer-facing
    /// logs and fallback UI. Never localized (localization is a client
    /// concern, keyed on `code`). MUST be stable enough to grep for, but
    /// client logic MUST NOT depend on the string.
    pub message: String,

    /// Optional structured context. Fields depend on `code`. See §4 for
    /// the per-code detail schemas. Disclosure of this field may be
    /// gated by the debug-mode rules in §7.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<ErrorDetail>,

    /// Recovery hint dispatch. Present only for `RecoverableDrift` and
    /// `Operational` categories. See §5 for the full enum. Clients with
    /// a compatible SDK SHOULD call the recovery function named here
    /// and retry the original request. Clients without an SDK MAY
    /// surface a generic "temporary network issue" to the user.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery: Option<RecoveryHint>,

    /// For Operational errors with a definite retry window. Unix
    /// timestamp (seconds) or seconds-from-now, per enum convention.
    /// If absent on an Operational error, client SHOULD use exponential
    /// backoff starting at 1s with max 60s.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_after_secs: Option<u32>,

    /// Yellow Paper section reference. Client SDK error display SHOULD
    /// include this as a clickable link so developers can find the
    /// authoritative spec. Examples: "§17.9.4.0", "YPX-018 §2.3".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub yp_reference: Option<String>,

    /// Request correlation ID. Echoes the client's `request_id` if
    /// provided. Used for log tracing across layers. Always present
    /// from Lambda; optional from Core and Nabla.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,

    /// Wire format version. Starts at 1. Allows future schema evolution
    /// without breaking old clients. Clients MUST check this field
    /// first and fall back to string-only parsing if the version is
    /// higher than they understand.
    pub version: u8,
}
```

**Serialization:** CBOR (matches the rest of the protocol's wire
format). JSON MAY be used for HTTP admin endpoints but the canonical
form is CBOR.

**Backward compat:** existing clients that parse a free-form
`{"error": "..."}` JSON field SHOULD receive the `message` field as
`error` for a grace period. Specifically, Lambda's HTTP responses
SHOULD include BOTH the legacy `error: <message>` field and the new
`error_response: <ErrorResponse CBOR blob (base64)>` field, until
clients have migrated. §9 details the migration path.

### 2.2 Severity vs category — separate channels

**`ErrorCategory` is client-facing.** It tells the client what to DO
with the error. It does NOT describe operator severity.

**Operator severity goes through a separate channel** — the node's
structured log stream, metrics, and alerting. Some errors that look
equivalent to the client ("this validator's VBC is invalid, pick a
different one") have radically different severity for the operator
(VBCExpired = routine, VBCRootKeyMismatch = possible mirror-universe
attack, halt and investigate). The operator-facing severity is logged
at the appropriate level by the validator when the error is emitted,
with whatever detail the operator needs (stack context, correlation
IDs, metric tags). None of that flows to the client through
`ErrorResponse`.

The client always sees `VBCExpired`, `VBCNotYetValid`, and
`VBCRootKeyMismatch` as the same category (`RecoverableDrift` with
`RetryDifferentValidator` hint). The operator sees them at WARN,
INFO, and CRITICAL log levels respectively. One protocol, two
audiences, two channels — neither leaks into the other.

This means `ErrorResponse` has no "severity" field, and the spec is
simpler for it.

### 2.3 `ErrorCategory` (NORMATIVE)

```rust
pub enum ErrorCategory {
    /// The network refused the operation for a cryptographic, consensus,
    /// or policy reason. The request is WRONG in a way the client cannot
    /// transparently fix. Examples: invalid signature, insufficient
    /// balance, banned wallet, replay, already-redeemed cheque.
    ///
    /// Client contract:
    /// - MUST NOT retry blindly (most rejects are idempotent bads).
    /// - MUST surface the error to the user with actionable guidance.
    /// - MAY offer specific recovery UI per code (e.g. "insufficient
    ///   balance" shows a top-up flow), but those are separate
    ///   user-initiated actions, not automatic retries.
    ProtocolReject,

    /// The request failed because the client's local state or payload
    /// drifted from network reality. A well-known recovery flow exists.
    /// The SDK should dispatch to the recovery named in
    /// `ErrorResponse.recovery` and retry the original request
    /// automatically. The user typically does not see this.
    ///
    /// Examples: E_SABR_HASH_MISMATCH, E_INSUFFICIENT_CHEQUES (needs
    /// dedup), E_INCONSISTENT_CHEQUE_BUNDLE (needs dedup),
    /// E_INVALID_WALLET_SEQ (needs resync).
    ///
    /// Client contract:
    /// - MUST examine `recovery` and call the matching recovery function.
    /// - After recovery completes, MUST retry the original request once.
    /// - If retry also fails with a RecoverableDrift error, SHOULD
    ///   escalate to a generic "network issue" and surface to the user.
    RecoverableDrift,

    /// Transient condition: validator busy, network timeout, Core not
    /// yet calibrated, rate limited, Nabla not-yet-synced. The client
    /// SHOULD retry with bounded exponential backoff. The user may see
    /// a brief "please wait" indicator but typically does not see the
    /// underlying error.
    ///
    /// Client contract (retry policy is entirely client-side — the
    /// protocol does not mandate any specific retry behavior. This
    /// spec only tells the client WHAT class of error it is):
    /// - MAY retry with whatever backoff strategy the client's
    ///   deployment context prefers.
    /// - If the server supplied `retry_after_secs`, the client SHOULD
    ///   NOT retry before that many seconds elapse — it is a hint
    ///   from the server that earlier retries will still fail.
    ///   Otherwise the client picks its own backoff.
    /// - MAY retry on a different validator/Nabla node on each attempt.
    /// - MAY give up after any number of attempts. The reference SDK
    ///   applies an exponential backoff (1s→2s→4s→…→60s cap) with a
    ///   5-minute total budget; other clients MAY differ. See the
    ///   SDK Yellow Paper for the reference policy.
    Operational,

    /// The client sent a malformed or invariant-violating request. The
    /// bug is in the client implementation itself, not the user's data.
    /// Panic in debug builds, always report.
    ///
    /// Examples: InvalidClientSignature (signing bug), ZeroAmount
    /// (didn't validate before sending), MalformedAddress, MissingField.
    ///
    /// Client contract:
    /// - MUST NOT retry. Retrying will hit the same bug.
    /// - MUST log enough context (request_id, code, detail) for the
    ///   developer to reproduce and fix.
    /// - MAY panic in debug builds.
    /// - Production builds SHOULD surface "a client-side problem
    ///   occurred, please report this" rather than exposing the raw
    ///   error to users.
    ClientBug,

    /// Internal failure inside Core, Lambda, Nabla, or ANTIE itself.
    /// Not the client's fault. Rare; always a sign of a bug, resource
    /// exhaustion, or infrastructure failure.
    ///
    /// Examples: StorageError (DB corruption), ConservationViolation
    /// (Core math bug), WalCorruption, InvalidWitnessSignature
    /// (validator signing bug).
    ///
    /// Client contract:
    /// - MAY retry once on a different validator, then give up.
    /// - MUST log the error with full request_id for the network
    ///   operator to investigate.
    /// - Surfacing to user SHOULD be a neutral "a server issue
    ///   occurred" without exposing internals.
    Internal,
}
```

## 3. Per-category behavior contract (NORMATIVE)

The table below is the client state machine for error handling. Every
category has EXACTLY ONE correct default response. SDK implementations
MUST follow this table; deviations require explicit per-code carve-outs.

| Category | Retry? | User-visible? | Action |
|---|---|---|---|
| **ProtocolReject** | NO | YES | Surface with code-specific message. Offer code-specific UI if available (top-up, scar passcode prompt, etc.). |
| **RecoverableDrift** | YES (after recovery) | NO | Dispatch `recovery` hint → call named recovery function → retry original request once. Escalate on second failure. |
| **Operational** | YES (client's own policy) | OPTIONAL | Retry policy is entirely client-side. Respect `retry_after_secs` if present. Otherwise client picks its own backoff + budget. Brief UI indicator acceptable. See SDK Yellow Paper for the reference SDK's policy. |
| **ClientBug** | NO | DEVELOPER-ONLY | Log with full context. Panic in debug. Generic "client issue" to users. Must not expose internals. |
| **Internal** | MAYBE (once, different validator) | NEUTRAL | Log. Try once more against a different validator/node. Surface neutral "server issue" if retry fails. |

## 4. `ErrorDetail` schemas (NORMATIVE per code)

`ErrorDetail` is a discriminated union whose variant is determined by
`ErrorCode`. Only a subset of codes carry structured detail; others
have `detail: None`.

This section lists the detail schema for every code that has one.
Codes not listed here have `detail: None` by default.

### 4.1 State chain errors

```rust
/// For: E_SABR_HASH_MISMATCH, E_INVALID_STATE_ID, E_INVALID_WALLET_SEQ,
///      E_STATE_NOT_ANCHORED (§15 anchor check; carries
///      RecoveryHint::ClaraHealNextSend)
///
/// DEBUG-GATED: `validator_stored_state_id` and `validator_wallet_seq`
/// are only disclosed when the request is authenticated by the wallet
/// owner (via client_pk signature on the request) OR when the
/// responding node is running in --debug-errors mode. In production
/// public endpoints, these fields are None.
pub struct StateChainMismatchDetail {
    pub requested_consumed_state_id: [u8; 32],
    pub requested_wallet_seq: u64,

    // Debug-gated
    pub validator_stored_state_id: Option<[u8; 32]>,
    pub validator_wallet_seq: Option<u64>,
}
```

**`E_STATE_NOT_ANCHORED` (§15 — added 2026-06-04 PM-2):** fires when
the SDK's `current_state.balance` / `wallet_seq` doesn't re-derive
to the k-signed `prev_receipt.state_hash` via
`compute_state_hash(client_pk, balance, wallet_seq)`. Recovery is
`ClaraHealNextSend`. Implemented at
`core/logic/src/validation.rs::verify_state_anchored`, runs inside
`validate_transaction` so it covers CL1 / CL2_PREFILTER / CL2 /
CL3 / CL5 automatically. Closes the cross-validator
`produced_state_id` divergence vector that produced
`FactInsufficientWitnesses` for stale clients (see
`AXIOM_HANDOFF_MacClientStaleState.md` — RESOLVED).

**`E_LAMBDA_CL5_PROOF_MISSING` (§15 — added 2026-06-04 PM-2):**
fires at `process_redeem_request` entry when
`request.cl5_execution_proof` is empty. Mirror of the existing
CL1 mandatory gate at `consensus.rs:2421`. Detail is `None`;
recovery hint is `ClaraHealNextSend` so SDK dispatch surfaces
"Heal wallet…" — but the actual fix is the client running its
own Core CL5 and shipping the DMAP attestation. The pre-§15
"legacy mode (signature-only)" fallback for redeems is gone.

Rationale: `StateChainMismatchDetail` is the single most valuable
structured error in the whole system. It's what was missing from
`E_SABR_HASH_MISMATCH` during the 8-day debugging chase. With
this detail plus the quorum rule in the recovery hint, the SDK can
automatically decide between resync and CLARA heal without the
developer touching the Yellow Paper.

### 4.2 S-ABR overlap errors

```rust
/// For: E_SABR_INSUFFICIENT_OVERLAP
pub struct SabrInsufficientOverlapDetail {
    pub overlap_sigs_provided: u8,
    pub overlap_sigs_required: u8,
    pub is_fresh_validator: bool,
}
```

The client can compute how many more overlap sigs it needs, and
whether it should retry-same-validator (YPX-016 cache) or pick a
different overlap witness.

### 4.3 Balance errors

```rust
/// For: E_INSUFFICIENT_BALANCE, E_REDEEM_BALANCE_OVERFLOW
///
/// DEBUG-GATED: `current_balance` only disclosed to wallet owner.
pub struct BalanceDetail {
    pub requested_amount: u64,
    pub current_balance: Option<u64>,  // debug-gated
}
```

### 4.4 Cheque bundle errors

```rust
/// For: E_INCONSISTENT_CHEQUE_BUNDLE, E_INSUFFICIENT_CHEQUES,
///      E_FACT_DUPLICATE_WITNESS
pub struct ChequeBundleDetail {
    pub distinct_validators: u8,
    pub k_required: u8,
    pub specific_field_mismatch: Option<BundleFieldMismatch>,
}

pub enum BundleFieldMismatch {
    Txid,
    SenderWalletId,
    ReceiverWalletId,
    Amount,
    Epoch,
    DuplicateValidator,
}
```

Tells the client exactly which field in the bundle is inconsistent,
so dedup can target the specific issue instead of blind retrying.

### 4.5 VBC lifecycle

```rust
/// For: E_VBC_EXPIRED, E_VBC_NOT_YET_VALID
pub struct VbcLifecycleDetail {
    pub vbc_expires_at_tick: u64,
    pub current_tick: u64,
    pub ticks_until_valid: Option<i64>,  // negative = expired
}
```

### 4.6 Rate limit

```rust
/// For: E_RATE_LIMIT_EXCEEDED (Lambda), E_RATE_LIMITED (Nabla CLARA),
///      E_RATE_LIMITED (ANTIE witness)
pub struct RateLimitDetail {
    pub limit: u32,
    pub window_secs: u32,
    pub current_count: u32,
}
```

Combined with `retry_after_secs` at the top level, tells the client
both how long to wait AND what the limit actually is.

### 4.7 Ban / freeze / lockup

```rust
/// For: E_WALLET_BANNED, E_WALLET_FROZEN, E_GENESIS_STAKE_LOCKED
pub struct WalletLockDetail {
    pub lock_reason: LockReason,
    pub lock_started_at_tick: u64,
    pub lock_expires_at_tick: Option<u64>,  // None = permanent until manual intervention
    pub challenge_path: Option<String>,     // "POST /ban-challenge" for S6, else None
}

pub enum LockReason {
    S6DoubleSpendBan,
    JfpFreeze { jfp_txid: [u8; 32] },
    GenesisLockup,
}
```

Distinguishes reversible (S6 challenge) from irreversible (lockup
period) locks so the SDK can show different UI.

### 4.8 Scar consent (not an error — see §8)

`FactScarDetected` is NOT an error — it's a user-consent prompt
requiring a passcode. This spec proposes moving it out of the error
enum entirely. See §8 for the new response type.

### 4.9 Remaining codes

Most other codes carry `detail: None`. A full schema table appears in
Appendix B once Phase 2 locks in every variant. For Phase 1 drafting,
the seven schemas above cover every error the SDK's dispatch logic
actually needs to inspect.

### 4.10 Core-binary identity errors (2026-05-12)

```rust
/// For: E_CORE_ID_MISMATCH (CL2 Step −1.5)
pub struct CoreIdMismatchDetail {
    /// 32-byte BLAKE3 of the validator's loaded axiom-core.elf.
    pub validator_core_id: [u8; 32],
    /// 32-byte BLAKE3 the transaction shipped in tx.core_id.
    pub tx_core_id: [u8; 32],
}
```

`E_CORE_ID_MISMATCH` fires when a transaction's embedded `core_id`
doesn't match the validator's loaded `axiom-core.elf` hash (CL2
Step −1.5, commit 4c283ef6, 2026-05-12). **The gate is non-poisoning**:
either side carrying the all-zero `[u8; 32]` disables the check —
this is the genesis-claim path where the client hasn't yet seen the
network's canonical core_id. The same field is covered by
`Receipt.core_id` and rolled into `receipt_commitment`, so a receipt
that successfully validates against the next TX necessarily agreed on
the same core_id.

**Recovery:** the SDK should re-pull `core_id` from the validator's
witness response (carried in `WitnessResponse.core_id`) and retry the
transaction with the corrected value. If mismatch persists across the
quorum, the client is running an out-of-date Core ELF and must rebuild
or pull the canonical ELF from the network.

### 4.11 Cheque claim proof errors (2026-05-13)

```rust
/// For: E_CHEQUE_CLAIM_PROOF_MISSING,
///      E_CHEQUE_CLAIM_PROOF_INVALID_SIG,
///      E_CHEQUE_CLAIM_PROOF_TXID_MISMATCH,
///      E_CHEQUE_CLAIM_PROOF_RECEIVER_MISMATCH,
///      E_CHEQUE_CLAIM_PROOF_UNTRUSTED,
///      E_CHEQUE_CLAIM_PROOF_EXPIRED,
///      E_TXID_ALREADY_IN_RECEIVER_CHAIN
pub struct ChequeClaimProofDetail {
    /// 32-byte cheque txid the proof was bound to.
    pub cheque_id: [u8; 32],
    /// Receiver wallet PK that registered the claim.
    pub receiver_pk: Vec<u8>,
    /// Nabla writer's tick at proof emission, for freshness checks.
    pub nabla_tick: u64,
    /// Validator's current tick (for EXPIRED diagnosis).
    pub current_tick: u64,
}
```

The seven codes above guard the **CL5 Step 3.5b cheque claim gate**
(commits `aa3b7377` WIP + `794fa911` end-to-end, 2026-05-13) plus
the **Step 3.5c chain-txid scan** (the seventh,
`E_TXID_ALREADY_IN_RECEIVER_CHAIN`, fires when the receiver's FACT
chain already carries a redeem link with the same `txid` —
defense-in-depth against replays that bypass Nabla entirely; the
scan is filtered to redeem links via `link.sender_anchor.is_some()`).

`RegisterChequeClaimResponse` carries `proof: Option<ChequeClaimProof>`
as a single typed CBOR value (commit `d8344e44`, 2026-05-14) — *not*
as 6 mirrored byte/uint fields. Any wire decoder must accept a CBOR
Map embedding the typed `axiom_core_logic::types::ChequeClaimProof`
struct directly. See AXIOM_YellowPaper.md §39.9.7a for the full
flow + `ChequeClaimProof.client_pk` binding rule.

**Recovery:** all seven codes map to `RecoveryHint::ClaraHealNextSend`
— §14 makes heal the sole sanctioned drift recovery; the receiver
also re-runs `verify_cheque` to capture a fresh proof before
retrying the redeem.

### 4.12 Same-tick redeem block (2026-05-15)

```rust
/// For: E_REDEEM_BEFORE_COMMIT_PROPAGATED
pub struct SameTickRedeemBlockDetail {
    /// 32-byte cheque txid the receiver attempted to redeem.
    pub cheque_id: [u8; 32],
    /// Sender's FACT-chain tip new_state_id (what the receiver was
    /// trying to anchor against).
    pub sender_state_id: [u8; 32],
    /// The writer-signed commit tick from
    /// `NablaConfirmation.committed_at_tick` on the sender's tip.
    pub committed_at_tick: u64,
    /// Validator's current TARDIS tick at the time of the redeem.
    /// MUST satisfy `current_tick > committed_at_tick` for the
    /// redeem to proceed.
    pub current_tick: u64,
}
```

`E_REDEEM_BEFORE_COMMIT_PROPAGATED` is the CL5 enforcement of YP
§17.10.5.3 (Same-Tick Redeem Block — Nabla Commit-Tick
Attestation). Fires when a receiver attempts to redeem a cheque
against a sender FACT chain whose tip has a `NablaConfirmation`
with `committed_at_tick >= inputs.current_tick`. Forces at least
one TARDIS tick between the sender's Nabla SMT commit and any
receiver redeem against that state — minimum mechanical gap for
Nabla mesh gossip to *start* propagating the commit.

**Sender-side scarred-link exemption.** Scarred FACT links carry
no `NablaConfirmation` (Nabla was unreachable at register time);
they cannot trigger this gate. Ark-mode wallets that scar and
chain forward continue to operate without this check ever firing.
The error is unique to *confirmed-link* redeems where the receiver
beat the propagation window.

**Recovery:** `RecoveryHint::RetryAfter` — the receiver SHOULD
retry the redeem after at least one TARDIS tick has elapsed (≈ 1
second at the default tick cadence). The detail's `current_tick`
and `committed_at_tick` tell the SDK exactly how long to wait
(`committed_at_tick - current_tick + 1` ticks worst case, but in
practice the gap is always 0 or 1 because the receiver only
beats the writer's same-tick window by one mesh hop).

This is a Core-side error (emitted by `core/logic/src/modes.rs`
CL5 redeem path) and reaches the wire via the standard
ValidationError → ErrorResponse path. Wire field carrying the
detail: `error_response.detail = ValidationErrorDetail::SameTickRedeemBlock(SameTickRedeemBlockDetail)`.

### 4.13 RECALL attestation errors (YPX-022, 2026-07-04)

```
/// For: E_RECALL_ATTESTATION_INVALID
///
/// Detail is None — a hard reject carries no structured payload
/// (mirrors E_OODS_ATTESTATION_INVALID). The SDK cannot repair a
/// forged/stripped attestation; it re-runs register_recall to obtain
/// a fresh, valid one.
```

`E_RECALL_ATTESTATION_INVALID` is a **Core CL2 hard reject** on a
RECALL transaction (`TxKind::Recall`, the witnessed self-send request leg
of the forward `tx → cheque → redeem` recall, YP §17.14) whose
`RecallAttestation` fails verification. It maps to
`ValidationError::RecallAttestationInvalid` in `core/logic/src/types.rs`
(Display → `E_RECALL_ATTESTATION_INVALID`). Fires on any of:

- **Bad Nabla Ed25519 signature** — `att.nabla_signature` does not
  verify against `att.nabla_node_pk` over
  `compute_recall_attestation_payload(txid, presend_state_hash, amount, recall_tick)`
  (`core/logic/src/validation.rs::verify_recall_attestation`, step 1).
- **Invalid NBC trust anchor** — empty issuer/signature/commitment,
  an issuer PK not in the Nabla root-authority set
  (`is_nabla_root_authority`), a SPHINCS+ signature that does not
  verify over `BLAKE3(nbc_commitment)`, or a `nabla_node_pk` not bound
  into the NBC commitment window (step 2).
- **Wrong target** — `att.txid != tx.recall_target_tx_id`
  (`core/logic/src/modes.rs`): the attestation is for a different send
  than the one this RECALL reclaims.
- **Amount-inflation attempt** — `tx.amount != att.amount`: the recall
  self-send declares an amount other than the one Nabla stamped from the
  verified failed send. This is the pin that caps the recall cheque at
  exactly the failed send's amount (YP §17.14; YPX-022 §2 "AS BUILT").
  A different amount would not hash to `txid`, so the sender cannot
  obtain a matching attestation for it.
- **Missing attestation** — `inputs.recall_attestation` is `None` on an
  `is_recall` transaction: every RECALL requires it.

The attestation proves only "this txid was recalled, for this amount";
both binds are enforced by Core against the txid hash, never taken from
the attestation on trust — so a hostile Nabla can withhold a recall but
can never forge a favourable reclaim. Full flow:
`docs/AXIOM_YPX-022_RECALL.md`.

**Recovery:** no automatic drift-heal — the RECALL is refused and the
wallet is left untouched. The SDK re-registers via `register_recall`
to obtain a fresh attestation before retrying.

## 5. `RecoveryHint` enum (NORMATIVE)

```rust
#[repr(u8)]  // wire encoding: u8 discriminants 1..=8 in declaration order
pub enum RecoveryHint {
    /// Run the CLARA heal flow: TX_HEAL self-send → POST /clara to
    /// Nabla → attach attestation to the next normal send. CLARA
    /// TX_HEAL re-anchors a wallet that has drifted from the
    /// validators' S-ABR chain, via a key-proved, validator-witnessed
    /// self-send. §14 — clients NEVER resync wallet state from Nabla
    /// (a rollback/replay vector); heal is the sole sanctioned
    /// recovery for state divergence.
    ///
    /// Used for: E_SABR_HASH_MISMATCH (any validator count), S-ABR
    /// state-chain mismatch, E_INVALID_WALLET_SEQ, receiver state
    /// drift, burn-path drift after detection.
    ClaraHealNextSend,

    /// Retry the SAME request with the SAME payload on the SAME
    /// validator first. YPX-016 witness response cache will return
    /// the cached response if the validator already committed but
    /// the response was lost in transit.
    ///
    /// Used for: transient timeout on an overlap validator, network
    /// flakes during witness collection.
    RetrySameValidator,

    /// Try a different validator from the backup pool. The current
    /// validator is unreachable or stuck. The SDK's select_validators
    /// should return a different k=3 set on the retry.
    ///
    /// Used for: E_VBC_EXPIRED, E_CONSENSUS_TIMEOUT,
    /// E_VALIDATOR_BUSY.
    RetryDifferentValidator,

    /// Dedup the cheque list by (txid, validator_id) per YP §17.9.4.0
    /// before retrying the redeem. The bundle submitted had duplicate
    /// entries from the same validator.
    ///
    /// Used for: E_INCONSISTENT_CHEQUE_BUNDLE,
    /// E_INSUFFICIENT_CHEQUES (when duplicates present).
    DedupChequeBundle,

    /// Wait for the duration specified in `retry_after_secs` (top-level
    /// field), then retry. The network is healthy but the operation
    /// can't proceed yet (rate limit, maturity delay, cooldown).
    ///
    /// Used for: E_RATE_LIMITED, E_ORACLE_MATURITY_NOT_REACHED,
    /// E_CLAIM_COOLDOWN_ACTIVE.
    WaitAndRetry,

    /// Run the S6 ban challenge flow: collect ≥k-1 endorsements from
    /// other validators attesting that the ban was wrong, file the
    /// challenge via nabla_client.challenge_ban(), then retry the
    /// original request after the challenge window elapses.
    ///
    /// Used for: E_WALLET_BANNED (only).
    S6BanChallenge,

    /// File a FACT chain compression checkpoint to reduce chain depth,
    /// then retry. Chain has exceeded MAX_FACT_DEPTH.
    ///
    /// Used for: E_FACT_CHAIN_TOO_DEEP.
    FactChainCompress,

    /// Clear local FACT scars via burn path before retrying. Required
    /// for Ark unload and a few other operations.
    ///
    /// Used for: E_ARK_UNLOAD_SCARRED, E_TOO_MANY_UNRESOLVED_SCARS.
    BurnExistingScars,
}
```

**SDK dispatch table:** the SDK maps each `RecoveryHint` to a specific
method call on the `Wallet` object. This is the entire recovery logic.

```rust
match err.recovery {
    Some(ClaraHealNextSend) => { /* next send will auto-heal */ retry(req).await }
    Some(RetrySameValidator) => { retry(req).await }  // YPX-016 cache will handle it
    Some(RetryDifferentValidator) => { retry_with_different_validator(req).await }
    Some(DedupChequeBundle) => { dedup(&mut req); retry(req).await }
    Some(WaitAndRetry) => { sleep(err.retry_after_secs.unwrap_or(1)); retry(req).await }
    Some(S6BanChallenge) => { wallet.challenge_ban().await?; retry_after_challenge_window(req).await }
    Some(FactChainCompress) => { wallet.compress_fact_chain().await?; retry(req).await }
    Some(BurnExistingScars) => { wallet.heal().await?; retry(req).await }
    None => { /* category-level default behavior */ }
}
```

**This is why the spec matters.** The SDK's retry and recovery logic
becomes a switch statement, not a string-matching maze.

## 6. Error code allocation (NORMATIVE)

### 6.1 Format

Error codes are strings of the form `E_<DOMAIN>_<NAME>`:

- `<DOMAIN>` — a short namespace tag identifying where the error
  originated: `CORE`, `LAMBDA`, `NABLA`, `ANTIE`, or protocol-specific
  tags like `SABR`, `VBC`, `CLARA`, `CHEQUE`, `BURN`, `ARK`, `ORACLE`,
  `CONSOLE`, `FACT`, `DWP`, `JFP`, `MVIB`, `FANOUT`, `TXID`, `GROUP`,
  `OWNER`, `HEAL`.
- `<NAME>` — ALL_CAPS_SNAKE_CASE, descriptive but concise. Should
  match the Rust variant name where feasible.

Examples:
- `E_SABR_HASH_MISMATCH`
- `E_CHEQUE_INCONSISTENT_BUNDLE`
- `E_VBC_EXPIRED`
- `E_CLARA_EMPTY_GARBAGE`
- `E_LAMBDA_RATE_LIMIT_EXCEEDED`
- `E_LAMBDA_SCAR_CONSENT_REQUIRED` — the scar-consent gate PAUSED a send whose
  provenance carries unresolved (or inherited-unresolved) scars. NOT a failure:
  nothing was witnessed, no funds moved. The receiver has been notified
  out-of-band with a 6-digit passcode; the sender re-initiates the SAME txid via
  `send_with_scar_passcode` once the receiver shares it. See YP §17.9.3.2 +
  YPX-001 §1.5.1/§1.5.1a.
- `E_LAMBDA_INVALID_SCAR_PASSCODE` — wrong, expired (7d TTL), attempt-capped
  (5 tries), or presented at a validator that never stored it. The client re-runs
  the consent hand-off; a fresh send re-pauses and re-notifies the receiver.

### 6.2 Stability guarantee

**Error codes are STABLE ACROSS RELEASES.** Once a code is assigned, it
MUST NOT change. Renaming a Rust variant does NOT change the code.
New errors get new codes. Deprecated errors may be removed but their
codes MUST NOT be reassigned.

Clients match on codes. If we break code stability, we break every
client.

### 6.3 Allocation process

1. When adding a new error variant, pick a code in the format above.
2. Add the code to the registry in `core/logic/src/error_codes.rs`
   (new file, to be created in Phase 2).
3. Add a row to Appendix A of this document with category, recovery
   hint (if any), YP section ref (if any), and a one-line description.
4. CI enforces the registry file has exactly one entry per code and
   that every Rust error variant maps to exactly one code.

### 6.4 Migration from existing codes

`ValidationError::Display` already emits codes like `E_SABR_HASH_MISMATCH`.
Those become the canonical codes for the new format — no renaming.
For error variants that don't currently have a stable code string
(most of `LambdaError`, `NablaError`, `ClaraRegistrationError`,
`AntieError`), we assign codes during the Phase 2 implementation pass.

## 7. Debug mode disclosure (NORMATIVE)

Some `ErrorDetail` fields are gated behind authentication or a
server-side debug flag to prevent leaking internal state to
unauthorized readers.

### 7.1 Disclosure rules

A detail field is disclosed when ANY of the following holds:

1. **Wallet-owner authenticated:** the request carried a valid
   client_pk signature proving the requester owns the wallet being
   queried. The server can safely disclose that wallet's state
   because the requester is the authoritative owner.
2. **Debug mode:** the responding node was started with
   `--debug-errors` (or equivalent config). Production nodes SHOULD
   NOT enable this. Dev, staging, and operator-owned nodes MAY.
3. **Public field:** the field is not sensitive (e.g. `k_required`,
   `overlap_sigs_provided`). Public fields are always disclosed.

Fields that are NEVER disclosed:
- Validator private keys
- Internal Lambda DB paths
- Raw storage layer errors
- Stack traces (even in debug mode — route those to operator logs)

### 7.2 Specific gated fields

| Detail schema | Field | Gate |
|---|---|---|
| `StateChainMismatchDetail` | `validator_stored_state_id` | Owner-authenticated OR debug |
| `StateChainMismatchDetail` | `validator_wallet_seq` | Owner-authenticated OR debug |
| `BalanceDetail` | `current_balance` | Owner-authenticated OR debug |

All other fields default to public.

### 7.3 Missing gated fields

If a detail field is gated and disclosure is not permitted, the field
MUST be `None` in the response. The client receiving `None` on a gated
field should not treat it as an error; it's just unknown to this
requester. The SDK can still dispatch on `code` and `category` with
no field context.

## 8. Scar consent — the `FactScarDetected` special case

**Problem:** `LambdaError::FactScarDetected { passcode, txid, sender,
receiver, amount, scar_count }` is currently returned as an error when
Lambda detects a redeem attempt against a scarred FACT chain link. But
it's not actually a failure — it's a user-consent prompt. The receiver
needs to be shown the scar details, asked if they want to proceed
anyway, and if so, resubmit with the passcode.

**Proposal (breaking change):** move `FactScarDetected` out of the
error path entirely. Add a new response shape:

```rust
pub enum RedeemResponse {
    Success(RedeemSuccessDetail),
    Error(ErrorResponse),
    ScarConsentRequired(ScarConsentPrompt),
}

pub struct ScarConsentPrompt {
    pub txid: [u8; 32],
    pub sender_wallet_id: String,
    pub receiver_wallet_id: String,
    pub amount: u64,
    pub scar_count: usize,
    pub passcode: u32,        // 6-digit, sent via separate channel in production
    pub prompt_message: String,  // human-readable explanation
}
```

The SDK's `wallet.redeem()` returns an `Err(Error::ScarConsentRequired)`
enum variant, not a conventional error. The front-end displays the
prompt to the user, collects consent + passcode, and calls
`wallet.redeem_with_scar_consent(cheque_id, passcode)`.

**Why breaking change:** any existing client that matches on error
strings containing "FACT scar detected" will stop receiving that
error. Migration is a hard cutover at the release boundary, but it's
strictly better than leaving a user-consent prompt masquerading as
an error forever.

This is the only `ErrorResponse` variant change in Phase 1 that's a
behavioral breaking change. Everything else is additive.

## 9. Migration plan

### 9.1 Dual-format response window

Phase 2 implementation starts by having Lambda emit BOTH the legacy
`{"error": "<message>"}` field AND the new `{"error_response":
<cbor-base64>}` field in HTTP responses. Same for Nabla, ANTIE.

Clients that haven't been updated still parse the legacy `error`
field as they do today. Clients that support the new format parse
`error_response` and gracefully ignore `error`.

Duration of dual-format window: one full release cycle minimum
(probably a month). After that, the legacy `error` field becomes
optional and eventually removed.

### 9.2 Version field

`ErrorResponse.version` starts at 1. Clients that see a higher version
than they understand MUST fall back to the legacy `error` string field
(if present) or produce a generic "unknown error, code: X" to the
developer.

This lets Phase 2 ship v1 → later Phase 2.x ships v2 with additional
detail types → clients upgrade on their own schedule without breaking.

### 9.3 Per-layer rollout

Phase 2 implements in this order:

1. **Core** — add `ErrorResponse` type to `core/logic/src/types.rs`.
   Core's `execute_core` returns `Result<PublicOutputs, ErrorResponse>`
   instead of `Result<PublicOutputs, ValidationError>`. Callers adapt.
   ELF rebuild required; CoreID changes.
2. **Lambda** — Lambda's consensus.rs error returns switch from
   `LambdaError` to `ErrorResponse`. Lambda's HTTP server emits dual
   format. Storage error wrapping gets structured.
3. **Nabla** — `NablaError` and `ClaraRegistrationError` gain
   `ErrorResponse` conversion impls. Nabla's HTTP endpoints emit dual
   format.
4. **ANTIE** — ANTIE's gateway passes structured errors through
   instead of wrapping in strings. `AntieError::ValidationFailed` gets
   preserved discriminant through to the client.
5. **Client SDK** — SDK parses `ErrorResponse`, dispatches on
   category/recovery, implements the per-category behavior contract.
   The SDK Yellow Paper references this spec for error semantics.

Each layer can ship independently once Core's types are stable. The
client SDK gets the most benefit but is the last to land.

### 9.4 Implementation status (2026-04-15)

| Phase | Scope | Status |
|---|---|---|
| **Phase 1** | Design doc + taxonomy + open-question resolution | ✅ shipped |
| **Phase 2a** | `axiom-errors` crate scaffolding — wire types, codes, detail schemas | ✅ shipped (`8e375cf`) |
| **Phase 2b.1** | `From<ValidationError>` / `From<&LambdaError>` conversions | ✅ shipped (`46ec709`) |
| **Phase 2b.2** | Dual-format `GatewayResponse::Error` emission | ✅ shipped (`a94300e`) |
| **Phase 2b.3** | `LambdaError::CoreRejected(Box<ValidationError>)` typed pass-through (no Core API change) | ✅ shipped (`4d4ce42`) |
| **Phase 2b.4** | `error_response` field on `RedeemResponse` / `AckResponse` / `FeeRedemptionResponseEnvelope` | ✅ shipped (`32b5c79`) |
| **Phase 2b.5** | Classify 26 ad-hoc error sites in `consensus.rs` with proper codes + categories | ✅ shipped (`4991817`) |
| **Phase 2b.6** | CBOR roundtrip e2e test for Lambda's dual-format wire | ✅ shipped (`1253e87`) |
| **Phase 2b.7** | Enrich `RecoveryHint` on 6 classified sites | ✅ shipped (`c118ddf`) |
| **Phase 2b.8** | Typed `BalanceDetail` on `InsufficientBalance` | ✅ shipped (`796d000`) |
| **Phase 2b.9** | Typed `ChequeBundleDetail` on `InsufficientCheques` | ✅ shipped (`7d44eac`) |
| **Phase 2b.10** | Typed `RateLimitDetail` + final Nabla HTTP sites | ✅ shipped (`681be38`) |
| **Phase 2b.11** | Typed `WalletLockDetail` + `SabrInsufficientOverlapDetail` | ✅ shipped (`72e2340`) |
| **Phase 2b.12** | Typed `StateChainMismatchDetail` on S-ABR lookup miss | ✅ shipped (`06cb79b`) |
| **Phase 2b.13** | `redact_debug_fields` helper + final `consensus.rs` cleanup | ✅ shipped (`28c76e5`) |
| **Phase 2c.1** | Nabla `/register` dual-format HTTP errors | ✅ shipped (`ed70112`) |
| **Phase 2c.2** | Nabla bulk HTTP handler conversion (40 sites) | ✅ shipped (`a26c002`) |
| **Phase 2c.3** | ANTIE `From<&AntieError>` + health endpoint dual-format | ✅ shipped (`ff8758f`) |
| **Phase 2c.4** | Round-trip wire-contract tests for Nabla + ANTIE | ✅ shipped (`db5d4fc`) |
| **Phase 2c.5** | Final Nabla HTTP sites (3 leftover from bulk) | ✅ shipped (`681be38`) |
| **Phase 2b.14** | VbcLifecycleDetail — Core ValidationError::VBC{Expired,NotYetValid} upgraded to struct variants | ✅ shipped (`088ed76`) |
| **Phase 2b.15** | Legacy `error` string removal — structured `error_response` is the sole wire source of truth across Lambda/Nabla/ANTIE | ✅ shipped |
| **Phase 2d** | SDK consumer helpers in `scripts/pmc.py` (parse_error_response, error_code, error_display, etc.) + migration of all 30+ call sites | ✅ shipped |

**No grace period.** As of Phase 2b.15, every error-emitting path in
Lambda/Nabla/ANTIE carries `error_response` as the single source of
truth. The legacy `error: Option<String>` field was removed from
GatewayResponse::Error, RedeemResponse, AckResponse,
FeeRedemptionResponseEnvelope, and Nabla's HTTP JSON body shape.
ANTIE's lambda_client.rs local GatewayResponse mirror was updated
to read `error_response` structurally.

**7/7 typed ErrorDetail variants wired**: Balance, ChequeBundle,
RateLimit, WalletLock, SabrInsufficientOverlap, StateChainMismatch,
VbcLifecycle.

Remaining Phase 2 work is operational polish: migrating additional
SDK consumers (webclient, future uniffi bindings) to read the
structured field, and wiring `redact_debug_fields` at any future
untrusted-boundary endpoints that need it.

**Wire format is live in production**: Lambda, Nabla, and ANTIE all
emit `error_response` alongside the legacy `error` string on their
respective wire formats (CBOR for Lambda, HTTP JSON for Nabla/ANTIE).
Verified live: a malformed `POST /register` to any Nabla node returns

```json
{"error":"Missing wallet_pk (64 hex chars)",
 "error_response":{"category":"client_bug",
                   "code":"E_NABLA_MISSING_FIELD",
                   "message":"Missing wallet_pk (64 hex chars)",
                   "version":1}}
```

6 of 7 typed `ErrorDetail` variants are wired in at least one
emission site: Balance, ChequeBundle, RateLimit, WalletLock,
SabrInsufficientOverlap, StateChainMismatch. Only `VbcLifecycle` is
unwired, pending a future Core-side change that adds the expiry /
current-tick data to `ValidationError::VbcExpired` (currently a
unit variant).

## 10. Examples

### 10.1 Hash mismatch, owner-authenticated, RecoverableDrift

Client request fails because its local state drifted from the validators' stored S-ABR chain.

```cbor
ErrorResponse {
    code: "E_SABR_HASH_MISMATCH",
    category: RecoverableDrift,
    message: "Wallet state does not match validator's stored state",
    detail: Some(StateChainMismatch(StateChainMismatchDetail {
        requested_consumed_state_id: [0x12, 0x34, ...],
        requested_wallet_seq: 42,
        validator_stored_state_id: Some([0xab, 0xcd, ...]),  // disclosed (owner)
        validator_wallet_seq: Some(44),                       // disclosed (owner)
    })),
    recovery: Some(ClaraHealNextSend),  // wallet drifted — CLARA TX_HEAL on next send
    retry_after_secs: None,
    yp_reference: Some("§17.10.14 CLARA + YPX-018"),
    request_id: Some("pmc-a1b2c3d4-v3"),
    version: 1,
}
```

**SDK dispatch:** reads `recovery = ClaraHealNextSend`; the next
normal send auto-heals via CLARA TX_HEAL, re-anchoring the wallet
before the retry. User sees nothing.

### 10.2 Inconsistent cheque bundle, public, RecoverableDrift

Client tried to redeem a bundle with duplicate validator entries.

```cbor
ErrorResponse {
    code: "E_CHEQUE_INCONSISTENT_BUNDLE",
    category: RecoverableDrift,
    message: "Cheque bundle contains duplicate entries from the same validator",
    detail: Some(ChequeBundle(ChequeBundleDetail {
        distinct_validators: 2,
        k_required: 3,
        specific_field_mismatch: Some(DuplicateValidator),
    })),
    recovery: Some(DedupChequeBundle),
    retry_after_secs: None,
    yp_reference: Some("§17.9.4.0"),
    request_id: Some("pmc-f7e8d9c0-v1"),
    version: 1,
}
```

**SDK dispatch:** reads `recovery = DedupChequeBundle`, runs dedup on
its local cheque store, rebuilds the bundle, retries the redeem.

### 10.3 Validator busy, Operational

Validator rate-limited the request (YPX-015 backpressure).

```cbor
ErrorResponse {
    code: "E_LAMBDA_RATE_LIMIT_EXCEEDED",
    category: Operational,
    message: "Validator is busy; please retry with backoff",
    detail: Some(RateLimit(RateLimitDetail {
        limit: 100,
        window_secs: 60,
        current_count: 100,
    })),
    recovery: Some(WaitAndRetry),
    retry_after_secs: Some(15),
    yp_reference: Some("YPX-015 §2"),
    request_id: Some("pmc-9a8b7c6d-v2"),
    version: 1,
}
```

**SDK dispatch:** sleeps 15 seconds (from `retry_after_secs`), retries
the original request, possibly against a different validator.

### 10.4 Insufficient balance, ProtocolReject

User tried to send more than they have.

```cbor
ErrorResponse {
    code: "E_INSUFFICIENT_BALANCE",
    category: ProtocolReject,
    message: "Requested amount exceeds wallet balance",
    detail: Some(Balance(BalanceDetail {
        requested_amount: 1_000_000_000,
        current_balance: Some(500_000_000),  // owner-authenticated
    })),
    recovery: None,
    retry_after_secs: None,
    yp_reference: None,
    request_id: Some("pmc-12345678-v1"),
    version: 1,
}
```

**SDK dispatch:** does not retry. Returns the error to the front-end,
which displays "You have 0.05 AXC but tried to send 0.1 AXC" (SDK
formats the balance via the detail field).

### 10.5 Client bug: missing signature

Client didn't sign the request properly.

```cbor
ErrorResponse {
    code: "E_INVALID_CLIENT_SIG",
    category: ClientBug,
    message: "Client signature verification failed",
    detail: None,
    recovery: None,
    retry_after_secs: None,
    yp_reference: Some("YPX-007 §39.3"),
    request_id: Some("pmc-bad1bad2-v1"),
    version: 1,
}
```

**SDK dispatch:** panics in debug mode. In production, logs the error
and surfaces "a client-side problem occurred" to the user while the
developer investigates via logs.

## 11. CBOR tag allocation (NORMATIVE)

`ErrorDetail` is a discriminated union. Its CBOR wire representation
uses **CBOR tags from the private-use range** allocated by this spec
in the `axiom-errors` crate. NOT IANA-registered.

### 11.1 Why private-use tags

CBOR tags 65536 and above are reserved for private use without IANA
registration. Within that range, applications are free to define
their own tag allocations, with the constraint that they MUST NOT
interoperate with other CBOR applications at the tag level (which is
fine — AXIOM is a closed protocol ecosystem).

Private-use tags give us:
- Clean wire format (no string discriminator field, more compact than
  a `{"type": "...", "fields": {...}}` envelope)
- No IANA process overhead (registration can take weeks and is
  essentially one-way)
- No global uniqueness constraint (we just need uniqueness within
  AXIOM, enforced by the `axiom-errors` crate registry)
- Forward-compatible: if AXIOM ever needs to interoperate at the
  CBOR level with a third-party tool, we can register the specific
  tags we're already using with IANA at that time

### 11.2 AXIOM CBOR tag space

AXIOM reserves the tag range **`0xAC10_00000000` through
`0xAC10_FFFFFFFF`** for its own protocol use. (`0xAC10` as a memorable
"AXIOM 10" prefix; the 32-bit tail gives us 4 billion tags which is
plenty forever.)

Within that space:

| Sub-range | Purpose |
|---|---|
| `0xAC10_00000001` .. `0xAC10_0000FFFF` | Error detail variants (`ErrorDetail::*`) |
| `0xAC10_00010000` .. `0xAC10_0001FFFF` | Recovery hint variants (if we ever need tagged recovery detail) |
| `0xAC10_10000000` .. `0xAC10_1FFFFFFF` | Future reserved (response types, audit envelopes, etc.) |

Concrete allocations (ErrorDetail variants, Phase 2a starting point):

| Tag | Variant |
|---|---|
| `0xAC10_00000001` | `StateChainMismatchDetail` |
| `0xAC10_00000002` | `SabrInsufficientOverlapDetail` |
| `0xAC10_00000003` | `BalanceDetail` |
| `0xAC10_00000004` | `ChequeBundleDetail` |
| `0xAC10_00000005` | `VbcLifecycleDetail` |
| `0xAC10_00000006` | `RateLimitDetail` |
| `0xAC10_00000007` | `WalletLockDetail` |

Future variants get the next available tag; allocations are append-only
once shipped (never reassigned).

### 11.3 Registry location

Tag allocations live in the `axiom-errors` crate at
`axiom-errors/src/cbor_tags.rs`. CI enforces:

1. No two variants share a tag.
2. No tag is allocated outside the AXIOM private-use range.
3. Once a tag appears in a tagged release, it cannot be renumbered.

### 11.4 Future IANA migration path

If AXIOM becomes important enough that third-party CBOR tooling needs
to understand our detail types (unlikely for a wallet protocol, but
possible for audit tooling, block explorers, etc.), we can submit the
tag allocations to IANA for registration at any time. Private-use
tags can be registered post-hoc — the IANA registry accepts
"grandfathered" private allocations if they're already in production
use. The migration is transparent to clients.

## 12. Request authentication for debug disclosure (NORMATIVE)

Some `ErrorDetail` fields — specifically the debug-gated ones in
§7.2 — should only be disclosed to the wallet owner. This section
defines the `RequestEnvelope` type used to authenticate non-transaction
requests so Lambda, Nabla, and ANTIE know when to disclose those
fields.

### 12.1 `RequestEnvelope<T>` (NORMATIVE)

```rust
pub struct RequestEnvelope<T: Serialize> {
    /// The Ed25519 public key of the wallet claiming ownership of
    /// the request's subject. MUST match the wallet whose state the
    /// request is querying/modifying. For requests that don't have
    /// a subject wallet (e.g. admin operator commands), this field
    /// MUST be the operator's public key instead — and the server
    /// validates against the operator keyring, not the wallet table.
    pub actor_pk: [u8; 32],

    /// The type of request this envelope wraps. Part of the signing
    /// message to prevent cross-purpose signature reuse (a signature
    /// for QueryStoredState cannot be replayed as ExportWalletSeed).
    pub request_type: RequestType,

    /// Strictly monotonic nonce per (actor_pk, request_type). Persisted
    /// server-side per actor to detect replay. The client is responsible
    /// for bumping this on every request. Local nonce counter starts
    /// at 1 and never decreases.
    pub nonce: u64,

    /// Unix timestamp in seconds, client's view. Used for clock-skew
    /// rejection (server rejects if |server_now - timestamp| > 60s).
    /// This is a secondary defense against replay; the nonce is the
    /// primary one.
    pub timestamp_unix: u64,

    /// The actual request payload. Serialized as CBOR for signing.
    pub payload: T,

    /// Ed25519 signature over the signing message defined in §12.2.
    pub signature: [u8; 64],
}

pub enum RequestType {
    QueryStoredState,       // GET wallet state (owner-auth gates debug fields)
    QueryHistory,           // GET TX history
    QueryBalance,           // GET balance with structured detail
    ExportWalletSeed,       // dangerous; admin path
    AdminRestart,           // operator-only
    AdminConfigUpdate,      // operator-only
    // ... extended as new admin operations are added
}
```

### 12.2 Signing message (NORMATIVE)

```
sig_msg = BLAKE3(
    "AXIOM_REQUEST_ENVELOPE_V1"
    || actor_pk                       (32 bytes)
    || (request_type as u16 LE)       (2 bytes)
    || (nonce LE)                     (8 bytes)
    || (timestamp_unix LE)            (8 bytes)
    || BLAKE3(serialize_cbor(payload))  (32 bytes)
)

signature = Ed25519_sign(actor_private_key, sig_msg)
```

Domain-tagged to prevent cross-protocol signature reuse. The payload
is hashed separately so the signing message has a fixed size
regardless of request body length.

### 12.3 Server-side verification (NORMATIVE)

On receiving a `RequestEnvelope`, the server MUST:

1. **Parse and deserialize** the envelope. If deserialization fails,
   return `E_REQUEST_ENVELOPE_MALFORMED` with category `ClientBug`.
2. **Clock-skew check.** If `|now - timestamp_unix| > 60`, return
   `E_REQUEST_ENVELOPE_CLOCK_SKEW` with category `Operational` (client
   can retry after fixing its clock).
3. **Nonce check.** Load the last-seen nonce for `(actor_pk,
   request_type)` from the nonce table. If `nonce <= last_seen`,
   return `E_REQUEST_ENVELOPE_REPLAY` with category `ClientBug`
   (client is replaying or has a buggy nonce counter). Otherwise
   update the stored nonce to the new value.
4. **Signature check.** Reconstruct `sig_msg` per §12.2, verify
   `signature` against `actor_pk`. If invalid, return
   `E_REQUEST_ENVELOPE_INVALID_SIG` with category `ClientBug`.
5. **Authorization check.** Is `actor_pk` authorized for
   `request_type`? For wallet-owner requests, `actor_pk` must equal
   the wallet being queried. For operator requests, `actor_pk` must
   be in the operator keyring.
6. If all checks pass, **mark the request as owner-authenticated**
   (or operator-authenticated) for the duration of its processing.
   Debug-disclosure fields become eligible for inclusion in any
   `ErrorResponse` returned during this request's handling.

### 12.4 Storage requirements

The nonce table is keyed by `(actor_pk, request_type)` and stores
a `u64` per key. Entries never expire (would allow replay after
eviction). Size per entry: ~56 bytes. For 100M wallets × 10 request
types = ~56 GB — large but bounded and sharded across the validator's
existing storage.

**Optimization:** only wallets that actually make authenticated
queries have nonce entries, so the real footprint is a tiny fraction
of the theoretical max. Most wallets will never issue a
`RequestEnvelope` at all — only the ones that hit debug-gated errors
and want the extra detail.

### 12.5 Which endpoints require an envelope

| Endpoint | Envelope required? | Notes |
|---|---|---|
| Witness request (TX submission) | NO | TX already carries `client_pk` + signature, which end-to-end verifies the owner via Core CL2/CL3. No need for a wrapper. |
| Redeem request | NO | Same as above. |
| Admin `/state` query | YES | Envelope with `QueryStoredState`, wallet-owner authenticated. |
| Admin `/history` query | YES | Envelope with `QueryHistory`. |
| Operator `/halt` command | YES | Envelope with operator keyring, not wallet keyring. |
| Nabla `/query` for wallet state | NO (public info) | Nabla's current_state is public by design. No gating. |
| Nabla `/register` | NO | Registration already signed as part of the request payload. |

The envelope is ONLY required for endpoints that have something
sensitive enough to want debug-gated disclosure. Most protocol paths
don't touch it.

### 12.6 Transactions are already authenticated

Witness and redeem requests do NOT need a `RequestEnvelope` because
the transaction itself carries `client_pk` and `client_sig`, and
Core's CL2/CL3 verification already establishes ownership.
`ErrorResponse`s returned during TX processing can safely disclose
debug fields to the requester because the TX's own signature
authenticates them. The envelope is purely for non-transaction admin
and query paths.

## 13. Resolved decisions (Phase 1 review)

All eleven Phase 1 open questions resolved:

| # | Question | Decision |
|---|---|---|
| 1 | FactScarDetected as non-error response type? | **YES** — move to `RedeemResponse::ScarConsentRequired`. Breaking change accepted. See §8. |
| 2 | CBOR vs JSON canonical? | **CBOR only.** Admin endpoints base64-encode the CBOR blob inside a JSON envelope if human-readable debugging is needed. |
| 3 | `ErrorDetail` discrimination strategy? | **CBOR tags from AXIOM private-use range** (`0xAC10_*`), registered in the `axiom-errors` crate. NOT IANA-registered. See §11. |
| 4 | What counts as "owner-authenticated"? | **`RequestEnvelope<T>` with Ed25519 signature + nonce + timestamp.** Only required for admin/query paths; transactions are self-authenticating via `client_pk`. See §12. |
| 5 | Retry budget policy? | **Not a protocol concern.** Retry policy is entirely client-side. `retry_after_secs` is a server hint. Reference SDK default is 5 min, documented in the SDK Yellow Paper. See §2.2, §3. |
| 6 | Error code registry location? | **Separate `axiom-errors` crate.** All layers depend on it. Contains codes, categories, recovery hints, CBOR tag allocations. |
| 7 | Language bindings — auto-gen or hand-maintain? | **uniffi.** Mozilla's Rust→Swift/Kotlin binding generator. Eliminates language drift. |
| 8 | `LambdaError::SABRFailed(String)` preserves Core discriminant? | **YES.** Lambda must preserve the inner Core error discriminant rather than stringify. |
| 9 | VBC lifecycle severity split? | **NO.** Client sees all VBC errors as the same category (`RecoverableDrift` + `RetryDifferentValidator`). Operator-facing severity (INFO/WARN/CRITICAL) is a separate log-stream concern, not in `ErrorResponse`. See §2.2. |
| 10 | NBC errors same treatment as #9? | **YES.** Same rule. |
| 11 | `WalletBanned` vs `GenesisStakeLocked` detail schema? | **`WalletLockDetail` with `LockReason` discriminator.** SDK dispatches on `LockReason` to show different UX (S6 challenge vs 3-year wait). See §4.7. |

Phase 1 is complete. Phase 2a (Core error type + Lambda wrap) can
start whenever engineering bandwidth is available.

## 12. Success criteria

Phase 1 is complete when this document is reviewed and all eleven Open
Questions are resolved. At that point, Phase 2 implementation can
start with a clear spec.

Phase 2 is complete when:
- Every error variant in `AXIOM_REF_ErrorTaxonomy.md` has an assigned
  stable code in the registry
- Lambda/Nabla/ANTIE emit dual-format errors (legacy + structured)
- The SDK can dispatch any error from any layer via its category +
  recovery fields without substring matching
- A conformance test verifies: given a mock ErrorResponse, the SDK
  calls the correct recovery function and retries the correct number
  of times
- The Yellow Paper (§17.9.4.0 and similar sections) references this
  spec for error semantics

---

## Appendix A — Full code registry (TO FILL IN PHASE 2)

Placeholder for the full table mapping every `ValidationError`,
`LambdaError`, `NablaError`, `ClaraRegistrationError`, `AntieError`,
`ArkError`, `OracleError`, and `AvmError` variant to its stable code,
category, recovery hint, YP reference, and detail schema.

This table will be auto-generated from the registry file once Phase 2
is in progress, to guarantee it stays in sync with the Rust source.
Expected size: ~250 rows.

## Appendix B — Full detail schema table (TO FILL IN PHASE 2)

Placeholder for the complete `ErrorDetail` enum with every variant,
its field definitions, and the codes that use it. The seven schemas
listed in §4 cover the dispatch-critical errors but the full table
will enumerate every code that carries structured detail.

---

**Next step:** Phase 2a — scaffold the `axiom-errors` crate, add the
`ErrorResponse` type to Core, and make Lambda wrap Core errors through
it. Estimated ~2 days. See §9.3 for the per-layer rollout order.

Phase 1 review decisions are all in §13 (no more open questions as of
2026-04-15 review pass).

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
