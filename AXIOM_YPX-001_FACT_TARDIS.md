**AXIOM Yellow Paper Extension YPX-001**
## FACT Chain and TARDIS Protocol

**Official Title:** Financial Audit Chain of Trust (FACT) and Temporal Anchor for Rollback Detection and Integrity Sync (TARDIS)
**Project:** AXIOM (TrustMesh Architecture)
**Type:** Yellow Paper Extension (Phase 2)
**Version:** 0.5 (Implemented)
**Date:** 2026-03-11
**Authors:** AXIOM Origin
**Depends On:** Yellow Paper v2.6.0+ (Phase 1 complete)
**Required By:** YPX-002 (Nabla Verification Protocol)

---

## 0. Purpose

This document specifies two interconnected protocols that extend the base AXIOM protocol:

- **FACT (Financial Audit Chain of Trust):** Tracks money provenance from genesis to current holder. Every cheque carries cryptographic proof of where the money came from. (FACT has a second, sanctioned bank-facing expansion — *Forensic Audit Chain for Transactions* — used only in UNCLE/institutional material. Same mechanism; see `AXIOM_DESIGN_Naming.md` §FACT for why both are correct.)
- **TARDIS (Temporal Anchor for Rollback Detection and Integrity Sync):** Provides tick-based temporal ordering for the network without requiring a central clock.

Together, FACT and TARDIS answer two questions the base protocol cannot:

```
Base protocol (Yellow Paper):
  "Is this transaction signed by k=3 real validators?"  --> VBC
  "Is this transaction internally valid?"                --> Core CL1-CL4
  
FACT adds:
  "Is this money real? Can it be traced to genesis?"     --> FACT chain

TARDIS adds:
  "Are the credentials current? When did this happen?"   --> TARDIS tick
```

---

## 1. FACT Chain

### 1.1 What Is FACT

FACT is a chain of cryptographic links embedded in every cheque. Each link represents one transaction in the money's history, tracing back to genesis.

```
FACT chain example:
  Genesis (G1 created 7M AXC)
    --> G1 sends 1000 to Alice (link 1)
      --> Alice sends 500 to Bob (link 2)
        --> Bob sends 200 to Charlie (link 3)
          --> Charlie sends 100 to Dave (link 4)

Dave's cheque carries links 1-4.
Anyone can verify: the 100 AXC traces back to G1's genesis allocation.
```

### 1.2 FACT Link Structure

Each FACT link contains:

```
FACT_link {
    tx_id:                  bytes32     // unique transaction identifier
    previous_state_id:      bytes32     // sender's state before TX
    new_state_id:           bytes32     // sender's state after TX
    amount:                 uint64      // amount transferred
    tick:                   uint64      // TARDIS tick when TX occurred
    validator_signatures:   [FactWitness; 3]  // k=3 validator sigs
    nabla_confirmation:     NablaConf?  // null = SCAR (see §1.5)
    receiver_contact:       String?     // receiver's email for scar healing (see §1.5.3)
    burn_proof:             BurnProof?  // null until burned (see §1.5.4)
}

FactWitness {
    validator_id:           bytes32     // BLAKE3(sphincs_pk) — ties to VBC
    validator_pk:           bytes       // Dilithium ML-DSA-65 public key (operational QR)
    signature:              bytes       // Dilithium signature over FACT commitment
}

NablaConf {                             // defined in YPX-002
    nabla_node_id:          bytes32
    nabla_signature:        bytes
    nabla_vbc_proof:        VBCProof
    root_hash:              bytes32
    synced_to_tick:         uint64
}

BurnProof {                             // see §1.5.4
    burn_tx_id:             bytes32     // tx_id of the burn transaction
    validator_sigs:         [FactWitness; 3]  // k=3 sigs over burn commitment
}
```

### 1.3 Verification Rules

Core verifies FACT chain as part of CL2 validation:

```
For each FACT link in chain:
  1. Validate k=3 signatures against tx_data
  2. Validate each VBC traces to genesis
  3. Validate previous_state_id connects to prior link's new_state_id
  4. Validate amounts are consistent (no money created)
  5. Validate tick values are monotonically increasing

First link must trace to genesis:
  - Genesis wallets: FACT starts with genesis state computation
  - Pool claims: FACT starts with pool emission proof
```

```python
def verify_fact_chain(fact_chain):
    """
    Core CL2: Verify FACT chain integrity.
    """
    for i, link in enumerate(fact_chain):
        # Verify k=3 signatures
        for sig in link.validator_signatures:
            if not verify_signature(link.tx_data, sig.signature, sig.validator_pk):
                return False, "invalid witness signature"
            if not verify_vbc_to_genesis(sig.vbc_proof, sig.validator_pk):
                return False, "VBC does not trace to genesis"
        
        # Verify chain continuity
        if i > 0:
            prev_link = fact_chain[i - 1]
            if link.previous_state_id != prev_link.new_state_id:
                return False, "FACT chain break: state discontinuity"
        
        # Verify tick ordering
        if i > 0 and link.tick < fact_chain[i - 1].tick:
            return False, "FACT chain break: tick regression"
    
    # Verify first link traces to genesis
    if not verify_genesis_origin(fact_chain[0]):
        return False, "FACT chain does not trace to genesis"
    
    return True, "valid"
```

### 1.4 Chain Depth and Checkpoint Compression

FACT chains grow with every transaction. Without compression, chains become impractically large. Checkpoint compression bounds the depth.

**Design principle:** Compression requires NO external authority and NO synchronous validator coordination. A checkpoint is a *proposal* that **travels with the wallet's chain** and accumulates distinct validator co-signatures across rounds; the compressed links are physically **retained until the proposal is fully signed**, so the chain is verifiable the whole time and nothing can wedge.

**Why travel, not a one-round vote (SEC-07, 2026-06-12).** Compression triggers on Nabla-confirmation status (`is_resolved()`), which is **not** consensus-bound and reaches each validator asynchronously. So the *k* witnesses of any single transaction legitimately disagree on what to compress — there is no synchronous quorum that can sign one checkpoint together. Instead each validator signs the *stored* proposal whenever its own view reaches that compression point; the identical stored bytes mean there is nothing to diverge.

```
Checkpoint rules (travel model — simple "global-3" config):
  FACT_PROPOSE_TRIGGER:     4  (total chain depth at which the FIRST validator
                               writes the checkpoint proposal — a START signal,
                               not "compress now")
  CHECKPOINT_SIG_THRESHOLD: 3  (distinct validator signatures required before the
                               covered links are actually deleted / finalized;
                               = MIN_FACT_WITNESSES, the k=3 floor — GLOBAL, not per-k)
  FACT_KEEP:                3  (live tail retained after finalization)
  FACT_HARD_CEILING:        32 (anti-abuse only — NOT the compression trigger;
                               depth is a signal, never a hard deadline)
  → chains settle at ~6-8 deep (was ~10-14 under the earlier 7/5/5 config).

  PROPOSE (chain depth >= 4, no checkpoint yet):
    The first validator computes root_hash of the oldest resolved
    (resolved_prefix - FACT_KEEP) links, builds the checkpoint, signs it ONCE,
    and KEEPS the covered links (checkpoint.pending_links = M). Provisional.

  CO-SIGN (provisional checkpoint present, < 3 distinct sigs):
    A later validator re-verifies the M retained links against root_hash and
    appends its own distinct signature (validator_id-deduped). With S-ABR witness
    overlap, ~1 new distinct validator signs per transaction.

  FINALIZE (>= 3 distinct sigs):
    Only the transaction's FINAL witnessing validator, at round success, DELETES
    the M covered links (pending_links -> 0) once the proposal carries 3 distinct
    sigs. Compression never fires mid-round. The committed bytes (root_hash, sigs)
    are unchanged; the accumulator resets for the next compression cycle.

  Checkpoint contains:
    root_hash:        bytes32       // BLAKE3 hash of compressed links
    validator_sigs:   [FactWitness] // distinct Dilithium sigs; 3 once finalized
    compressed_count: uint64        // how many links compressed (cumulative)
    final_state_id:   bytes32       // state at end of compressed section
    genesis_state_id: bytes32       // first-ever previous_state_id (traces to genesis)
    total_amount:     uint64        // sum of all compressed link amounts
    genesis_fact_hash:bytes32       // YPX-011 genesis-headline binding
    pending_links:    uint64        // leading links retained (provisional); 0 = finalized

  Genesis validators have NO special role. Any validator that can verify the
  chain may propose or co-sign; the CLIENT wallet's Core never counts toward 3.
```

```
Provisional (depth 6, proposal has 2/3 sigs — covered links RETAINED):
  [ckpt: L1-L3, root=abc, pending_links=3, sigs=2/3]
      L1 -> L2 -> L3 -> L4 -> L5 -> L6              (all links present)

Finalized (3rd distinct sig lands — covered links DELETED):
  [ckpt: L1-L3, root=abc, pending_links=0, sigs=3] -> L4 -> L5 -> L6
```

**Security:** the security-critical act — deleting the real links — never happens below 3 distinct, independently-verified signatures. Honest co-signers re-verify the still-present links before signing, so a forged or under-signed proposal never reaches 3 and its links are never deleted. The threshold is GLOBAL, not per-k: once the covered links are deleted a verifier can't cross-check a per-k value, so colluding validators could forge it downward — global-3 has no such gap. Forgery-proof; converges across rounds rather than in one synchronized vote.

### 1.5 Scar System: Unverified Links Block Compression

A FACT link without Nabla confirmation (nabla_confirmation = null) is a "scar." Scars cannot be compressed by checkpoint — unless the scar has been burned (see §1.5.4).

```
A FACT link is COMPRESSIBLE (resolved) when ANY of:
  nabla_confirmation != null          (healed via Nabla)
  OR burn_proof != null               (burned by owner)

Compression scan (oldest to newest):
  L1(verified) --> L2(verified) --> L3(SCAR) --> L4(verified) --> L5(verified)

  L1-L2: verified, compressible
  L3: SCAR (no nabla_confirmation, no burn_proof), cannot compress
  Compression stops at L3.

  Result: [checkpoint: L1-L2] --> L3(SCAR) --> L4 --> L5

  The scar keeps the chain long.
  Long chains are suspicious and may be rejected by receivers.

After burn:
  L1(verified) --> L2(verified) --> L3(BURNED) --> L4(verified) --> L5(verified)

  L3 now has burn_proof → compressible.
  All five links compress normally.

  Result: [checkpoint: L1-L5, root_hash=xyz, compressed_count=5]
```

#### 1.5.1 Scar-Passcode Bypass (Receiver Consent)

When a sender's money is scarred, the receiver MUST be informed before their wallet inherits the scar. The S-ABR overlapped validator acts as gatekeeper:

```
SCAR-PASSCODE FLOW:

1. Sender initiates TX → k=3 validators (including overlapped)
2. Overlapped validator checks sender's FACT chain → sees scar(s)
3. Overlapped validator PAUSES the TX (does not sign yet)
4. Overlapped validator sends notification to receiver:
     "Incoming payment of {amount} AXC from {sender_info}.
      This money has {scar_count} unverified link(s) in its provenance.
      If you accept, your wallet will inherit these scars.
      Passcode: {6-digit code}"
5. Receiver decides:
     REJECT → does nothing, TX dies
     ACCEPT → tells sender the 6-digit passcode
6. Sender reinitiates TX with same txid + scar_passcode field
7. Core processes via S-ABR: strips passcode (like balance), Lambda refills
8. Overlapped validator verifies passcode → match → TX proceeds normally
9. Receiver's wallet inherits the scar in their FACT chain (§1.5.1a)

SECURITY PROPERTIES:
  - Passcode generated by overlapped validator — sender cannot forge
  - Core strips passcode like balance in S-ABR — cannot bypass
  - Receiver has informed consent — no surprise tainted money
  - Clean money (no scars) skips this entirely — zero overhead
  - Not censorship: validator doesn't refuse, just ensures consent
```

**STATUS (2026-07-11): ACTIVE.** The historical deferral ("without Nabla, all money
is scarred — the gate would fire on every payment") was lifted after the deployed
env demonstrated Nabla confirms reliably (165 soak wallets / 768 retained links /
1 unresolved — the gate now fires only on genuinely scarred provenance).

**As built (Lambda `consensus.rs` witness path, overlapped validator only):**

- **Trigger:** the sender's client-carried FACT chain (§1.6) has ≥1 link with
  no `nabla_confirmation`, no `burn_proof`, and no `recall_proof` — the same
  resolution rule compression uses (§1.5). NOT the under-witnessed
  (`witnesses < required_k`) count: under the Quorum Gate (YP §17.1.2) a
  sub-quorum link can never anchor, so that older trigger was unreachable.
- **Ark carve-out (YPX-010):** links with `required_k = 0` (Ark provenance) are
  excluded from the trigger count, and a TX whose sender or receiver wallet_id
  decodes to the Ark tier (`K_ARK = 0`) skips the gate entirely. In Ark mode
  every payment is scarred BY DESIGN and disclosed up front — the receiver
  prices risk via the Confidence Index (YPX-010 §2), not a passcode dance.
  Only connected-mode individual scars gate.
- **Exemptions (no external receiver to consent / consent incoherent):** burn
  (`burn_target_tx_id` — burns are the cure), recall (self-send recovery,
  YPX-022), heal + HAL re-anchor (self-sends), CLARA attestation present
  (wallet healed through a witnessed TX_HEAL; the heal link's confirmation
  legitimately lives on the /clara channel).
- **Receiver notification:** the overlapped validator's Lambda piggybacks a
  `ScarConsentNotification` (txid, sender, amount, scar_count, passcode) on the
  witness response; ANTIE delivers it to the RECEIVER's mailbox as an
  `AXIOM/scar_consent/<uuid>` email (PGP-encrypted when the receiver's key is
  known) — same carrier path as cheque delivery. The sender sees only
  `E_LAMBDA_SCAR_CONSENT_REQUIRED` — the passcode NEVER travels to the sender
  in-protocol (consent must flow receiver → sender out-of-band).
- **Re-initiation:** `compute_txid` excludes `scar_passcode`, so the sender
  re-initiates the SAME tx (same consumed_state_id / nonce / epoch → same txid)
  with the passcode field set. The SDK persists the pending send's parameters
  (`scar_pending/{txid}.cbor` in the wallet dir) and exposes
  `send_with_scar_passcode`; the stored passcode is deleted on first
  successful verification (single-use). A wrong or unknown passcode rejects
  with `E_LAMBDA_INVALID_SCAR_PASSCODE`.
- **Consent voucher (the multi-overlapped completion).** The spec's singular
  "overlapped validator" does not exist under S-ABR — every prior witness is
  overlapped, each independently runs the gate, and the passcode is stored
  only at the validator that generated it. The retry round therefore
  completes via a `ScarConsentVoucher`: the SDK pins the passcode-storing
  validator as hop 1 (its id persists in the pending record); on a passcode
  match that validator signs Ed25519 over
  `BLAKE3("AXIOM_SCAR_CONSENT_OK" || txid)` and returns the voucher on its
  witness response; the SDK carries it on the round's remaining requests,
  and each later overlapped hop verifies the signature against the
  prev-receipt witness set the request already carries (the same k-signed,
  §15-anchored set it already validates — no cross-validator state, no new
  trust edge: "one of MY OWN prior witnesses attests the receiver
  consented"). A bare passcode with neither a local entry nor a valid
  voucher NEVER skips the gate — a fabricated passcode cannot bypass
  consent at any validator.
- **Reject path:** the receiver does nothing; the paused TX simply never
  re-initiates. Nothing was witnessed, nothing moved — the sender's wallet is
  untouched. The stored passcode is pruned with the normal retention sweep.

**AUDIT-FIX v2.11.14:** Scar passcode recovery is now via `POST /scar-passcode/recover` (was `GET /scar-passcode?recover=true`). GET requests on `/scar-passcode` are read-only and do not mutate state. This prevents CSRF-style accidental recovery and complies with HTTP semantics (GET must be safe/idempotent).

#### 1.5.1a Scar Inheritance (CORE RULE — as-built 2026-07-12)

**Consent is not cleansing.** Without inheritance, the passcode gate is a
one-hop wash: a wallet with unverifiable provenance sends to an accomplice
(who consents), and the money exits the redeem with a pristine chain — the
taint disappears from forward provenance and the next receiver never
consents. Scar status therefore CARRIES ACROSS the redeem hop as a Core
rule, enforced inside the ELF.

```
INHERITANCE (stamped by Core CL5 when building the receiver's redeem link):

  inherited_scar_txids = [ link.tx_id
      for link in verified_sender_chain
      if link.tx_id != cheque.txid            # the cheque's own tx is resolved
                                              # by THIS redeem's txid attestation
      and link is unresolved                  # no nabla_confirmation, no
                                              # burn_proof, no recall_proof, and
                                              # no fully-resolved inherited set
      and link.required_k > 0 ]               # Ark provenance excluded (YPX-010)

  Stamped ONLY on cross-wallet redeems (sender ≠ receiver). Self-redeems
  (genesis claim, HAL/RECALL completion) inherit nothing — the scar already
  lives on the same chain; nothing crosses a wallet boundary.

  BOUND INTO compute_fact_commitment — the k witnesses sign it; a receiver
  cannot strip the marker without invalidating every witness signature.
  (Formula change ⇒ CoreID rotation + pre-mainnet chain wipe, per §13.)

RESOLUTION (client-carried, per source txid — mirror of recall_proof):

  FactLink.inherited_scar_resolutions: one NablaTxidAttestation per source
  txid, attached POST-round (NOT in the commitment — witness sigs stay
  valid), verified by Core at verify_fact_link time. An inherited scar
  clears when the SOURCE transition became network-verified — i.e. the
  sender's scarred txid is attested at Nabla (the sender healed via
  register; §1.5.2). The receiver's SDK fetches attestations opportunistically
  (send pre-flight / supplemental sweep) — pull-based; no new push
  infrastructure needed for v1. §1.5.3's push propagation remains the
  UX-latency upgrade, not a correctness requirement.

CONSEQUENCES while any inherited scar is unresolved:
  - The consent gate counts the link as scarred → the receiver's OWN next
    send re-gates (the next receiver consents too — taint stays visible
    hop after hop until the origin heals).
  - FACT compression is blocked (same wash-out rule as ordinary scars).

OPEN (v2, deferred with §1.5.3): the burn-resolution case. If the ORIGIN
wallet burns its scarred link instead of healing, the source txid never
becomes attested and downstream inherited markers cannot clear via
attestation. Downstream recourse pending the ScarRecoveryProof design
(burn_proof is only visible on the origin's own chain). Pre-mainnet this
is acceptable: burns destroy the origin's funds, so the laundering economics
already collapsed; the downstream wallet holds consented-tainted money
exactly as it agreed to.
```

**CLIENT DISPLAY (required — the "looks clean while tainted" trap).** An
inherited scar sits on a redeem link whose OWN transition is fully resolved
(it has its own `nabla_confirmation`) — the taint is in `inherited_scar_txids`,
not in a missing confirmation. Therefore the **own-scar counter does NOT count
it**: `wallet.count_fact_scars()` (SDK) / `fact_scar_count()` (FFI) is
*own-scars only* — deliberately, because those are the burn targets and an
inherited scar is NOT burnable (burning it destroys sound money). A client that
drives its "scarred?" indicator solely off the own-scar count will show an
inherited-tainted wallet as **clean**, hiding the taint the whole mechanism
exists to make visible. Clients MUST surface inherited taint separately:
  - `wallet.count_inherited_scars()` (SDK) / `inherited_scar_count()` (FFI) —
    the count for display.
  - `diagnose()` emits an `inherited_scar_wait` action (call = `none`,
    informational — it self-resolves when the origin heals/burns; no user
    action). Render it.
The macOS wallet does both (Overview "Inherited provenance — pending" banner +
FACT-chain subtitle, `b68b9b5e`). The webclient scar-consent support
(`1bd0916e`) MUST mirror this or it inherits the same blind spot.

Note the layering: inherited taint is a *protocol-correct scar* (Core keeps the
link scarred via `inherited_unresolved() > 0`, which blocks compression and
re-gates the next send) — the only place it can silently vanish is the *display*
if the client reads the wrong counter.

#### 1.5.2 Scar Healing via Nabla

**Healing a scar:** When a wallet's FACT link receives Nabla confirmation, the scar is healed and compression can proceed.

#### 1.5.3 Scar Healing Propagation (Downstream Recovery)

When A sends scarred money to B, and B sends to C, all three wallets carry scars. When A's scar heals via Nabla, B and C must be notified.

**Mechanism:** Every FACT link includes a `receiver_contact` field (email/wallet_id). This creates a notification chain for healing propagation:

```
HEALING PROPAGATION:

A's FACT link: {tx_id, ..., receiver_contact: "bob@example.com"}
B's FACT link: {tx_id, ..., receiver_contact: "charlie@example.com"}

A's scar heals (Nabla confirmation received):
  1. Validator builds ScarRecoveryProof:
       - Original tx_id
       - Nabla confirmation (node_id, signature, root_hash, tick)
       - k=3 validator signatures over the healing
  2. Validator sends ScarRecoveryProof to B via receiver_contact
  3. Client app (A's wallet) ALSO sends recovery proof to B
     (redundant delivery — belt and suspenders)
  4. B's validator receives proof, verifies, heals B's scar
  5. B's validator forwards to C via B's FACT link receiver_contact
  6. Process continues down the chain until all healed

DUAL DELIVERY:
  Validator sends: authoritative, but may be offline
  Client app sends: redundant, covers validator downtime
  Either is sufficient — the proof is self-verifying (k=3 sigs)
```

#### 1.5.4 Burning Tainted Money

If a scarred link cannot be healed (fraudulent origin confirmed, Nabla node offline, or owner chooses not to wait), the owner can **burn** the tainted amount. Burning forfeits the money permanently but clears the scar, allowing checkpoint compression to proceed.

**Design principle:** A burn is a normal CL2 transaction to a special address. It goes through the standard CL1→CL2→Lambda→CL3→CL4 pipeline. No new Core Logic mode is needed.

**One burn per scar.** Each burn transaction targets exactly one scarred FACT link. If a wallet has multiple scars, the owner creates one burn transaction for each.

**Lambda bypasses for burns (v2.11.15-beta10):** Burn transactions skip two Lambda gates that apply to normal sends, because both are incoherent for burns:

1. **Scar passcode gate.** Lambda's `validate_sabr_overlapped` normally requires receiver consent (via a 6-digit passcode) before a scarred sender can spend. For burns the "receiver" is `BURN_ADDRESS` — there is no human receiver to ask for consent. Core's `validate_burn_target` already pins the hard invariants (target exists, target scarred, target not already burned, exact amount match), so burns cannot be abused as a passcode-bypass vector for normal transfers.

2. **S-ABR overlap requirement.** Lambda's `validate_sabr_new` normally requires ≥2 overlapped witness signatures from the prior TX. The TX that *created* the scar is often the wallet's last successful TX — meaning the wallet has no usable witness sigs to overlap with. Without this bypass, burns deadlock exactly when they are most needed. Core's burn-target verification still runs, and the wallet's balance is still debited normally, so this bypass cannot manufacture balance.

Both bypasses trigger on `tx.burn_target_tx_id.is_some()`. See `lambda/src/consensus.rs`.

##### Burn Address

```
BURN_ADDRESS: "BURN/00000000"

This is a well-known sink address. Money sent here is permanently destroyed.
Core recognizes this address and applies special CL2 rules (see below).
```

##### Transaction Extension

```
Transaction {
    // ... existing fields ...
    burn_target_tx_id:  bytes32?    // NEW: points at the scarred link's tx_id
}
```

When `burn_target_tx_id` is set and receiver is `BURN_ADDRESS`, this is a burn transaction.

##### Burn Commitment

Validators sign over a deterministic burn commitment:

```
burn_commitment = BLAKE3("AXIOM_BURN" || scarred_tx_id || wallet_pk || amount)
```

This binds the burn to a specific scar, wallet, and amount — preventing replay.

##### Burn Protocol Flow

```
BURN FLOW (one scar):

1. CLIENT creates burn transaction:
     receiver:           BURN_ADDRESS ("BURN/00000000")
     amount:             scarred_link.amount (must match exactly)
     burn_target_tx_id:  scarred_link.tx_id

2. CL1 (client validation):
     Normal signature and format checks.
     burn_target_tx_id is opaque data — CL1 does not interpret it.

3. CL2 (validator semantic validation):
     Recognizes receiver == BURN_ADDRESS:
       a. Skip receiver wallet validation (no real receiver)
       b. Skip cheque generation (no money to deliver)
       c. Verify burn_target_tx_id matches a scarred link in sender's FACT chain
       d. Verify amount == scarred_link.amount (exact match required)
       e. Allow conservation exception: atoms are destroyed, not transferred
       f. Compute burn_commitment, sign with Dilithium

4. LAMBDA (consensus):
     Normal k=3 consensus over the transaction.
     No cheque produced (BURN_ADDRESS has no wallet).
     Sender balance decreased by burn amount.

5. CL3 (witness production):
     Normal witness signing.
     Finalizing validator:
       a. Adds burn FACT link to sender's chain (normal link, amount = burn amount)
       b. Annotates the ORIGINAL scarred link with burn_proof:
            burn_proof = BurnProof {
                burn_tx_id:      this_burn_tx.tx_id,
                validator_sigs:  [k=3 FactWitness signatures over burn_commitment]
            }

6. CL4 (response):
     Normal response to client.

7. NABLA registration:
     Normal state transition (new state_id reflects reduced balance).
     Scarred link now has burn_proof → compressible.
```

##### Forward and Back Links

The burn creates a bidirectional reference between the burn transaction and the scarred link:

```
FORWARD LINK (burn TX → scar):
  burn_transaction.burn_target_tx_id = scarred_link.tx_id
  "This burn transaction is paying for THAT scar."

BACK LINK (scar → burn TX):
  scarred_link.burn_proof.burn_tx_id = burn_transaction.tx_id
  "This scar was resolved by THAT burn transaction."

Both directions are cryptographically committed:
  - Forward: included in burn TX signature (signed by client + k=3)
  - Back: burn_proof.validator_sigs sign over burn_commitment (k=3)
```

##### CL2 Burn Rules

```python
def validate_cl2_burn(tx, sender_fact_chain):
    """
    CL2 special handling when receiver == BURN_ADDRESS.
    """
    assert tx.receiver == "BURN/00000000"
    assert tx.burn_target_tx_id is not None

    # Find the scarred link
    target = find_link(sender_fact_chain, tx.burn_target_tx_id)
    if target is None:
        return Reject("burn_target_tx_id not found in sender's FACT chain")

    if target.nabla_confirmation is not None:
        return Reject("target link is not scarred (already confirmed)")

    if target.burn_proof is not None:
        return Reject("target link already burned")

    if tx.amount != target.amount:
        return Reject("burn amount must exactly match scarred link amount")

    # Conservation exception: atoms destroyed
    # Normal CL2 enforces sender_out + receiver_in = sender_in
    # Burn CL2 enforces sender_out = sender_in - burn_amount (no receiver_in)
    return Accept()
```

##### Compression After Burn

Once a scarred link has `burn_proof`, it is treated identically to a link with `nabla_confirmation` for compression purposes:

```
compressible(link) =
    link.nabla_confirmation != null    // healed
    OR link.burn_proof != null         // burned

Compression proceeds normally. The checkpoint's final_state_id reflects
the post-burn balance (reduced by the burned amount). The burn FACT link
itself is also a normal compressible link (it has k=3 validator sigs
and will receive Nabla confirmation through normal registration).
```

##### Multiple Scars

```
Wallet with 3 scars:
  L1(verified) → L2(SCAR, 500) → L3(verified) → L4(SCAR, 200) → L5(SCAR, 100)

Owner creates 3 burn transactions (one per scar):
  Burn TX α: amount=500, burn_target_tx_id=L2.tx_id
  Burn TX β: amount=200, burn_target_tx_id=L4.tx_id
  Burn TX γ: amount=100, burn_target_tx_id=L5.tx_id

After all 3 burns:
  L2.burn_proof = BurnProof{burn_tx_id=α, ...}
  L4.burn_proof = BurnProof{burn_tx_id=β, ...}
  L5.burn_proof = BurnProof{burn_tx_id=γ, ...}

All links now compressible. Wallet balance reduced by 800 total.
Burns can be done in any order — each targets a specific scar independently.
```

#### 1.5.5 FACT Link Complete Structure

```rust
FACT_link {
    tx_id:                  bytes32
    previous_state_id:      bytes32
    new_state_id:           bytes32
    amount:                 uint64
    tick:                   uint64
    validator_signatures:   [FactWitness; 3]
    nabla_confirmation:     NablaConf?          // null = SCAR (see §1.5)
    receiver_contact:       ReceiverContact?    // for scar healing (see §1.5.3)
    burn_proof:             BurnProof?          // null until burned (see §1.5.4)
}

ReceiverContact {
    wallet_id:              String          // receiver's wallet_id (validator lookup)
    email:                  String          // receiver's email (delivery address)
}
```

The `receiver_contact` is set at witness time: wallet_id from `transaction.receiver_wallet_id`, email extracted from wallet_id (format: "email/hex8"). It is None for the current holder (end of chain).

#### 1.5.6 ScarRecoveryProof: Self-Verifying Healing Package

When a scar heals, a `ScarRecoveryProof` is sent to downstream receivers. This is a self-verifying package — the receiver's validator checks it independently regardless of who delivered it.

```rust
ScarRecoveryProof {
    original_tx_id:         bytes32             // TX whose FACT link was scarred
    nabla_confirmation:     NablaConf           // proof of healing from Nabla
    healing_witnesses:      [FactWitness; 3]    // k=3 signatures over the healing
    receiver_wallet_id:     String              // who to deliver to
    fact_link_index:        uint64?             // hint for matching in chain
}

// healing_witnesses sign: BLAKE3("AXIOM_SCAR_HEAL" || original_tx_id || nabla_node_id || root_hash)
```

**Trust model:** Neither the validator nor the client app is trusted individually. Either one sends the `ScarRecoveryProof` via email. The proof carries k=3 validator signatures over the Nabla confirmation — the receiving validator verifies these signatures independently. If the proof is valid, the scar heals. If forged, verification fails. Belt and suspenders.

#### 1.5.7 Scar Resolution Methods (v0.5)

Scars can ONLY be resolved by two methods:

1. **NablaConfirmation** (free, normal path) — receiver queries Nabla, gets confirmation
   that the transaction was registered without conflict. Scar heals automatically.
2. **Burn** (costly, last resort) — owner burns the scarred amount to `BURN_ADDRESS`.
   BurnProof (k=3 validator signatures) is back-annotated on the scarred link.

There is NO auto-resolution by time. A scar that is never healed remains a scar
forever. This is by protocol design — scars represent unverified provenance and
must not silently disappear.

**Resolution check (`FactLink::is_resolved()`):**

```rust
pub fn is_resolved(&self) -> bool {
    self.nabla_confirmation.is_some() || self.burn_proof.is_some()
}
```

**Compression:** `compress_fact_chain()` uses `is_resolved()` to determine the
resolved prefix. Only resolved links compress. Unresolved scars and everything
after them stay uncompressed to prevent wash-out attacks.

#### 1.5.8 Per-Wallet Scar Cap (v0.4)

To prevent wallets from accumulating unbounded unresolved scars (which
could be used for chain-bloating attacks), a per-wallet cap is enforced:

```rust
const MAX_UNRESOLVED_SCARS: usize = 20;
```

**Enforcement:** During Core validation (Step 0c), if a wallet's FACT chain
already has `MAX_UNRESOLVED_SCARS` or more unresolved scars, new
transactions FROM that wallet are rejected with `TooManyScars` error.

**Exemptions:** Burn transactions (receiver = `BURN_ADDRESS`) are exempt
from the scar cap. A wallet with 20+ scars can still burn to resolve them.
This prevents a deadlock where a heavily-scarred wallet cannot clean itself up.

### 1.6 Cheque Format Extension

The base protocol cheque format (Yellow Paper Section 17) is extended with a FACT chain field:

```
Cheque {
    // Base protocol fields (Yellow Paper)
    tx_data:            TxData
    witness_receipts:   [WitnessReceipt; k]
    
    // FACT extension (YPX-001)
    fact_chain:         [FACT_link]      // money provenance
    checkpoint:         Checkpoint?      // compressed history (if applicable)
    
    // Nabla extension (YPX-002)
    registered_nabla:   bytes32?         // Nabla node ID where sender registered
}
```

### 1.7 Impact on axiom-core.elf

axiom-core.elf CL2 validation gains FACT chain verification and burn handling:

```
CL1: signature and format validation (unchanged)
CL2: semantic validation (EXTENDED)
  - Existing: balance math, state transitions
  - New: FACT chain integrity (Section 1.3)
  - New: checkpoint verification (if present)
  - New: scar detection (for information, not rejection)
  - New: BURN address recognition (§1.5.4)
    - Skip receiver validation for BURN_ADDRESS
    - Verify burn_target_tx_id points to a scarred link
    - Verify burn amount matches scarred link amount
    - Allow conservation exception (atoms destroyed)
CL3: ZKP attestation (EXTENDED)
  - New: finalizing validator annotates scarred link with burn_proof
  - New: burn FACT link added to sender's chain
CL4: response signing (unchanged)
```

Core does NOT reject cheques with scars. Core verifies the FACT chain is cryptographically valid. Whether to accept scarred money is the receiver's decision (see YPX-002).

### 1.8 Client App Transaction History Recommendation

The FACT chain is a **protocol-level rolling window** — it captures "what is now," not "what was." After checkpoint compression, individual FACT links are replaced by a single cryptographic commitment (root_hash). The protocol guarantees that compressed links *existed and were valid*, but their details (amounts, counterparties, timestamps) are no longer available from the chain itself.

**Recommendation:** Client app implementations SHOULD maintain their own local transaction history database. This database stores every transaction the wallet has participated in, providing users with full history even after FACT chain compression.

```
SEPARATION OF CONCERNS:

Protocol layer (FACT chain):
  - Rolling window of recent links (≤ MAX_FACT_DEPTH)
  - Checkpoint compression of verified/burned links
  - Cryptographic proof of current state
  - "What is now" — sufficient for validation

Application layer (client database):
  - Full transaction history (sender, receiver, amount, date, memo)
  - Burn records (which scars were burned, when, how much forfeited)
  - Search, filter, export for user-facing features
  - "What was" — sufficient for user experience

The protocol does not mandate this database. It is a client app concern.
Wallets that only implement the protocol layer will function correctly
but cannot show historical transactions older than the compression window.
```

---

## 2. TARDIS

> **SUPERSEDED (2026-02-13):** This entire section is superseded by YPX-003
> (TARDIS Cascade Protocol v0.2). The design below described a genesis-based
> tick with meta-validator rotation. That design was rejected because:
> (1) genesis cannot retire if it produces ticks, (2) meta-validator rotation
> moves corruption one step away but doesn't solve it.
>
> YPX-003 replaces this with a cascade heartbeat inside the Nabla network:
> binary tree topology, downstream approval for tick legitimacy, 5-second tick
> interval, 5-tick maturity window. TARDIS now serves as Nabla gossip heartbeat,
> liveness proof, and anti-timestamp-manipulation.
>
> The sketch's full text lives in git history (this file, before 2026-07-15);
> the summary below records where each idea went. For the current TARDIS
> specification, see YPX-003.

**Where the sketch went.** The genesis-advanced tick and meta-validator
rotation specified here became Designs 3 and 6 in TARDIS's design evolution;
YPX-003 §0.3 records all six rejected designs and the rejection reasoning, and
the full research record is `docs/archive/AXIOM_SECURITY_RESEARCH_VBC_FACT_TARDIS.md`
§5. The one idea from this sketch that survived every redesign — **ticks provide
ordering, not synchronization**, so partition tick-divergence is safe and only
conflicting state_ids matter — is carried forward as a design principle in
YPX-003 §0.3. For the current normative TARDIS specification (cascade topology,
tick interval, maturity window, partition healing), see YPX-003.

## 3. Security Properties

### 3.1 What FACT Proves

```
With FACT:
  - Money traces to genesis (no creation from nothing)
  - Every transfer has k=3 witness proof
  - History is cryptographically linked and unforgeable
  - Forgery requires compromising genesis private keys

Without FACT (base protocol only):
  - Current transaction has k=3 witnesses
  - No proof of prior history
  - Attacker could present fabricated history
```

### 3.2 What TARDIS Proves

```
With TARDIS:
  - Credentials have temporal context
  - Stale VBCs detectable (tick too old)
  - Network has shared time reference for coordination
  
Without TARDIS (base protocol only):
  - No temporal ordering
  - Cannot detect stale credentials
  - No coordination reference point
```

### 3.3 Combined with YPX-002 (Nabla)

```
FACT alone:     proves money is real, but can't detect double-spend
TARDIS alone:   provides time reference, but doesn't track state
Nabla alone:    tracks wallet state, but needs FACT for provenance

FACT + TARDIS + Nabla:
  - Money is real (FACT to genesis)
  - Time is tracked (TARDIS ticks)
  - Double-spend detected (Nabla wallet state)
  - Rollback prevented (Nabla + FACT scar)
  - Full production-grade security
```

---

## 4. Open Questions

```
RESOLVED:
1. TARDIS tick interval: 5 seconds (fixed). See YPX-003 §4.1.
2. Tick advancement mechanism: cascade with downstream approval (not genesis).
   See YPX-003 §1.4. All 10 genesis seeds form initial ring, retire when network
   has sufficient public Nabla nodes.
3. FACT chain maximum depth before mandatory compression: 5 links. See §1.4 above.
4. Checkpoint computation: any k=3 validator set that can verify the chain can
   sign the checkpoint. No genesis authority needed. See §1.4 above.

RESOLVED (continued):
6. Burn transaction: uses existing CL2 path with BURN_ADDRESS recognition.
   No new CL mode. See §1.5.4. burn_target_tx_id on Transaction,
   burn_proof on FactLink. Conservation exception for destroyed atoms.

RESOLVED (continued):
5. VBC size in FACT links: checkpoint compression eliminates old links entirely.
   Remaining VBC references use BLAKE3 hashes (32 bytes). See §1.4.
```

---

## 5. Glossary

| Term | Definition |
|------|-----------|
| FACT | Financial Audit Chain of Trust. Money provenance chain embedded in cheques. |
| FACT link | Single entry in FACT chain representing one transaction with k=3 proof. |
| TARDIS | Temporal Anchor for Rollback Detection and Integrity Sync. Tick-based time. |
| Tick | TARDIS counter. Monotonically increasing. Not wall-clock time. |
| Scar | Unverified FACT link (nabla_confirmation = null). Blocks checkpoint compression. |
| Checkpoint | Compression of old verified FACT links into a single root_hash, signed by any k=3 validator set. |
| Burn | CL2 transaction to BURN_ADDRESS that forfeits scarred amount. Annotates scar with BurnProof, enabling compression. See §1.5.4. |
| BurnProof | Back-link from scarred FACT link to the burn TX that resolved it. Contains burn_tx_id + k=3 validator signatures over burn commitment. |
| BURN_ADDRESS | Well-known sink address "BURN/00000000". Money sent here is permanently destroyed. |

---

## 6. References

| Document | Relevance |
|----------|-----------|
| Yellow Paper v2.6.0+ | Base protocol. Phase 1. Sections 17, 23.13, 24, 26. |
| YPX-002 | ∇ Nabla Verification Protocol. Phase 3. Depends on this document. Symbol: ∇ (U+2207). |
| YPX-003 | TARDIS Cascade Protocol v0.2. Supersedes Section 2 of this document. Defines tick interval, cascade topology, maturity window. |
| Security Research | Full design rationale, attack analysis, rejected approaches. |
| White Paper | AXIOM philosophy and high-level architecture. |
| White Paper | AXIOM philosophy and high-level architecture. |

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
