# AXIOM YPX-022 — RECALL: recovering a completed-but-undelivered payment

Spec class: Yellow Paper Extension (YPX). Status: **IMPLEMENTED (Core + Lambda + Nabla +
SDK), deployed on the dev network 2026-07; recall-race soak validation pending.** Built
docs-first from this spec. CoreID-rotating (depends on the **quorum gate**, a Yellow-Paper
core rule).
Scope: protocol-surface (Core + Lambda + Nabla + SDK).
Companion to YPX-018 (HEAL/CLARA), YPX-020 (HAL), and the Yellow-Paper **quorum gate** core rule.

> **RECALL recovers a payment that COMPLETED on-chain but whose cheque never reached the
> receiver** (a delivery failure — bounced email, dropped connection, dead device). The sender
> gets their money back; the undelivered cheque is permanently killed. It never touches a cheque
> the receiver actually holds.

---

## 0. The sender-side recoveries

AXIOM has one recovery primitive per distinct failure mode. They are **separate operations**.
Named by what happens to the money:

| # | Op | Failure it recovers | Money | Spec |
|---|----|--------------------|-------|------|
| 1 | **HEAL** | wallet stuck / diverged after a fault; make it operable again | (state repair) | YPX-018 |
| 2 | **BURN** | a scarred FACT link to retire | **destroyed** | YP §17.12 / KI#13 |
| 3 | **RECALL** | a **completed** send whose cheque **never reached the receiver** | **recovered** to sender | **this doc** |
| 4 | **HAL** | dead-overlap; prior witnesses gone | (re-anchor) | YPX-020 |

**There is no "failed send" recovery — and there is no RE-ISSUE.** Both are dissolved by two
decisions:

- **The quorum gate** (Yellow-Paper core rule: *a wallet advances only on ≥3 fresh witness
  signatures; below 3, nothing moves*). A sub-quorum send is a **no-op** — the sender keeps `B`,
  nothing is debited, nothing is stranded. So there is no failed-send money to reclaim.
- **No re-delivery** (design decision). A receiver who never got the cheque is made whole by the sender
  **recalling** the money (then re-sending if they still wish) — never by re-delivering the same
  cheque. The old "RE-ISSUE / copy-back-to-sender" idea is dropped; it only invited a "did you
  really not receive it?" dispute the protocol must not adjudicate.

RECALL is therefore the **only** thing left for a completed send to need: recovering value that
completed on-chain but that the receiver can never redeem because it never arrived.

---

## 1. Problem

A send can **complete** — reach 3-of-3, debit the sender `B → B−A`, produce a valid redeemable
cheque `C` — and yet the receiver **never receives `C`**. Delivery is off-chain and unreliable:
the email bounces, the connection drops, the device dies before the cheque is stored. On-chain
the payment happened; off-chain it vanished.

Now the value is **stranded**:
- the **receiver cannot redeem `C`** — they never got it, and a cheque you don't hold can't be
  redeemed;
- the **sender cannot re-spend `A`** — they legitimately paid it out; their balance is `B−A`.

Nobody can touch it. And it is the one failure the **social layer cannot fix**: a receiver
cannot refund a payment they never received. Every other "I want my money back" case is either a
completed-and-received payment (a social refund) or a sub-quorum no-op (nothing moved) — only
delivery failure produces value that is simultaneously spent and unredeemable.

---

## 2. The RECALL protocol

RECALL is a **deliberate, later** action on the sender's own completed-but-unredeemed payment:
a key-proved, k-witnessed recovery that permanently kills the undelivered cheque and returns `A`
to the sender through the standard `tx → cheque → redeem` flow.

### 2.1 The eligibility gate (the safety boundary)

RECALL may be **initiated** only on a txid that is **all** of:

1. **Completion-registered at Nabla** — a real 3-of-3 send. This is Nabla's own ledger record,
   read with zero sender-trust: a completion registration requires k distinct validator
   signatures (`nabla/src/registration.rs`, `>= MIN_FACT_WITNESSES`) — it cannot be forged,
   removed, or under-reported by the self-interested sender. *(This is the same k-threshold CL5's
   redeem depends on; recall and redeem read it from opposite sides.)*
2. **Status `NotRedeemed`** — the receiver has not redeemed `C` (the three-state txid status,
   §5 / YP §39.9.5: `NotRedeemed` / `Redeemed` / `PhasedOut`). A `Redeemed` txid refuses recall —
   the payment landed; first-wins; it is final and irreversible.
3. **Aged into the window** — `18000 ≤ (now − send_tick) ≤ 50000` ticks. The **lower bound is the
   receiver's protected fair-chance window**: delivery may still succeed and the receiver may
   redeem; only a cheque that has gone **un-redeemed for a long, protected period** is the
   fingerprint of genuine non-delivery. The **upper bound** bounds the exposure and closes the
   affordance.
4. **OODS-healthy** — the network is not partitioned/eclipsed (the shared hibernation gate; §2.2).

**The trigger is deliberate, not reactive.** Nothing fails at send time — the send *succeeded* —
so there is nothing for the wallet to react to. Recall surfaces as an explicit later action on a
successful-but-`NotRedeemed` payment once it ages into the window: *"this payment is still
unclaimed and old enough — recall it."*

**Enquire before recall (like redeem).** The SDK's deliberate trigger first runs the standard
`query-txid` enquiry (the same read-only enquiry the redeem path uses) and surfaces the legible
answer — already-redeemed / nothing-to-recall / too-early / too-late — **before** spending the
consume-once reservation (§2.2.1). The enquiry is advisory; the Nabla-side gate stays the
authority.

**This inverts the pre-quorum-gate design** (which gated on an *un-registered* failed send).
Under the quorum gate that case no longer exists; recall now gates on the **opposite** predicate —
a *completed* send.

### 2.2 The flow

*Initiate (in window + OODS-healthy) → enter hibernation → garbage the cheque, fan out → hibernate
(HAL window, OODS-healthy to exit) → complete: recover `A` via redeem.*

1. **Initiate.** The wallet submits a `RecallRequest` (the signed completed tx — proves ownership;
   Nabla recomputes `txid = compute_txid(tx)` and enforces `sender_pk == tx.client_pk` + Ed25519
   over `BLAKE3("AXIOM_RECALL" || txid)`). Gate (§2.1) checked. **The receiver's cheque `C` is
   still live and redeemable up to this point** — recall cannot cut it off before it commits.
2. **Enter hibernation → garbage the cheque.** At hibernation-entry, `C`'s txid is submitted to
   the **garbage-state bloom chain** (§5, the existing mechanism) → **fans out to every Nabla**:
   `C` is **no longer redeemable**, mesh-wide, permanently (inherits the constitutional **55-year
   retention floor**, YP §21.10.6 / §39.9.5). This is the point of no return for the receiver.
3. **Hibernate (recall window).** The wallet hibernates for `RECALL_HIBERNATION_WINDOW` ticks —
   recall's **own** maturity constant (720 prod), distinct from HAL's `HIBERNATION_WINDOW` (18000);
   only the constant differs, the projection `hibernation_until_for` is shared (§2.2.4). This is the
   **propagation-settle** time: it lets the "`C` is dead" record reach every Nabla before the sender
   takes `A` back, so no lagging node still honors a redeem while the sender recovers. The deadline
   is projected from the recall self-send's **`tx.epoch`** (stamped when the tx is built — the start
   of the witness round, not its completion): `hibernation_until = tx.epoch + WINDOW·TICK_INTERVAL_SECS`.
   A witness round that runs longer than the window therefore consumes it; harmless against the prod
   720-tick window (no round approaches it), and the reason the dev-wallet window (§2.2.4) is sized
   to exceed a dev round.
4. **Complete → recover via redeem (OODS-healthy).** After the window, and only if OODS is still
   healthy, the sender completes: a normal `tx → cheque → redeem` returns exactly `A` to the
   sender (`B−A → B`). **Balance rises only through the CL5 redeem** — no revert, no mint; the
   recovered `A` is the same `A` that was debited. Fees land at redeem like any redeem.

**Race + fail-closed.** If `C` was delivered late and the receiver redeems around the same moment,
**consume-once serializes it**: exactly one of {receiver-redeems, sender-recovers} settles, never
both. First-to-settle wins; the loser fails closed (a receiver redeem that beat the recall → the
recall aborts, sender keeps the debit; a recall that won → the receiver's later redeem hits
"consumed"). **A delivered-and-redeemed transfer is never reversed** — send-finality holds.

### 2.2.1 The reservation — initiate is a reservation, hibernation-entry is the commit

"`C` stays redeemable until hibernation-entry" (step 2) makes the recall **two-phase** at Nabla:

- **Initiate = RESERVATION.** `register_recall` checks the §2.1 gate and records a
  *reservation* (first-wins between conflicting recallers; **idempotent** for the same sender —
  a retry after a died witness round re-serves the attestation). `C` is **still live**: query-txid
  keeps serving `NotRedeemed` (the attestation the receiver's redeem needs), plus an UNSIGNED
  `claim_status = "RETRACT_PENDING"` so a receiver who enquires sees *"the sender is in the
  process of retracting this payment — redeem now or it will be recalled."* Informational only;
  no signed field changes, CL5 untouched.
- **Hibernation-entry = COMMIT.** The recall self-send's *registration* — the same event that
  stamps the hibernation lock — flips the reservation to the terminal `Recalled` marker, submits
  `C`'s txid to the garbage chain (§2.2 step 2), and floods the Recall gossip. This is the point
  of no return, and it is the SAME Nabla-lock event as the hibernation stamp, so there is no gap
  between "cheque killed" and "window started."
- **Redeem wins the reservation window.** A redeem that *finalizes* while the reservation is open
  wins: the redeem terminal aborts the reservation, and the recall's commit register is REFUSED
  with the legible *"redeemed while the recall was in progress"* error. The recall self-send never
  lands; it is a no-debit self-send, so nothing is lost — the sender's wallet recovers via the
  standard heal, and the payment stands (fail-closed, send-finality holds).
- **A dangling reservation is harmless.** If the recall's witness round dies (sub-quorum = no-op
  under the quorum gate), the reservation just sits there: `C` stays redeemable, the receiver is
  never blocked by it, and the sender's retry is idempotent. No expiry machinery needed.

### 2.2.2 OODS-healthy to exit — where it is enforced

§2.2 step 4's "only if OODS is still healthy" is enforced **in Core CL5**: the hibernation-exit
self-redeem (the completion that clears the lock — HAL's and RECALL's alike) is REFUSED with a
**retryable, liveness-only** error while the carried OODS attestation says unhealthy. Never a
fund reject — the sender completes when the view is healthy again. A normal self-redeem with no
hibernation lock (e.g. a genesis claim) is untouched, and the genesis baseline-0 exemption
(healthy by definition) applies as everywhere else.

### 2.2.4 Windows, and why the dev-wallet short window cannot touch real money

There is **one** hibernation-deadline projection, `core_logic::types::hibernation_until_for(base,
is_hal, is_recall, is_dev_class)`, shared by Core (the §15 state-hash binding via
`produced_hibernation_until`), Nabla (the register stamp), and the SDK (the local mirror). Kind
selects the constant; class selects the length:

| Kind | Public wallet | Dev wallet (`@axiom.internal`) |
|---|---|---|
| HAL (`is_hal`) | `HIBERNATION_WINDOW` 18000 (dev-build 50) | `DEV_WALLET_HIBERNATION_WINDOW` 50 |
| RECALL (`is_recall`) | `RECALL_HIBERNATION_WINDOW` 720 (dev-build 20) | `DEV_WALLET_RECALL_HIBERNATION_WINDOW` **60** |

The dev-wallet override gives an `@axiom.internal` wallet a short window **even in a prod build**, so
recovery is smoke-testable without the full wait. It is `DEV_WALLET_RECALL_HIBERNATION_WINDOW = 60`
ticks (300 s projected at 5 s/tick), sized to exceed a dev witness round (~120 s) so the
hibernate→finish transition is observable rather than elapsing mid-round (§2.2 step 3).

**The short window can never shorten a real (public) wallet's recall, via two independent guarantees:**

1. **Core computes the window from the wallet's own signed identity.** `produced_hibernation_until`
   passes `is_dev_class = is_dev_wallet(tx.sender_wallet_id)` — a fresh exact-`@axiom.internal` domain
   check on the **signed** `sender_wallet_id`, not a client-supplied bool. The value is folded into
   `produced_state_id` (compute_new_state_hash, §15) **and** into `receipt_commitment` (k-signed), and
   Nabla verifies both unconditionally (`reg.new_state == receipt.produced_state_id` + the ZK/DMAP
   `verify_zkp_proofs`). A public wallet's k-witnessed state therefore **always** carries the full
   720-tick window; a forged short-window state cannot pass the proof.
2. **A dev wallet never holds real money.** FACT class isolation rule R1 (`check_domain_isolation`,
   enforced in `validate_transaction`) requires sender and receiver to share a class — `public→dev`
   and `dev→public` are both rejected `DomainMismatch`. So a dev wallet only ever holds dev-AXC (the
   isolated 1M pool that cannot mint public AXC). The short window only ever governs dev-AXC.

**Nabla finish-gate stamp — authenticated on every register.** Nabla stamps the finish-gate deadline
from `reg.receipt.is_dev_class` (it holds only the wallet pubkey at that point, so it uses the
k-signed flag rather than re-deriving from the email). The receipt-commitment signature that binds
`is_dev_class` is verified on **every** hibernation-stamping register (`is_recall` / `is_hal_reanchor`)
— not gated on a non-empty `fee_breakdown` — so a client cannot ship a forged `is_dev_class=true` on
an empty-fee recall to obtain the short finish-gate window. (Recall/HAL are always k-witnessed, so the
signature is always present; only bootstrap/legacy registers are sig-less, and those never stamp a
hibernation lock.)

---

## 3. Security analysis

**Claim: RECALL cannot double-spend, and cannot reverse a payment the receiver received.**

- **No reversal of a received payment.** Status `Redeemed` refuses recall (§2.1.2). A cheque the
  receiver holds and redeems is irrevocable — RECALL is structurally incapable of touching it.
- **Recall-vs-redeem race → consume-once (A7).** Both hit the Nabla SMT consume-once; whichever
  settles first wins, the loser fails closed. Exactly one of {reclaim, redeem} settles per txid.
  Same guarantee HAL + double-redeem prevention already rely on.
- **The window's lower bound is a Nabla-enforced head-start, NOT the safety net.** 18000 ticks is a
  wide protected redeem window: against an HONEST mesh a receiver who holds `C` has ample time to
  redeem before recall is even eligible. But the window is enforced at the issuing Nabla against its
  own `completion_tick`; Core owns the constants + the projection (`ticks_to_secs`) but does NOT
  re-execute the age check, so a sender colluding with an adversarial *blessed* Nabla can issue an
  out-of-window recall attestation and Core accepts it. That does **not** enable theft: the
  receiver's real protection is consume-once first-wins (above), which is mesh-enforced and
  independent of any single Nabla — an active receiver who redeems wins the race regardless of the
  window. The bypass only erodes the *guaranteed head-start* against the §4.3 residual (an offline
  receiver). Making the head-start itself adversary-proof would require Core to check the age between
  two k-witnessed epochs (the failed send's own epoch + the recall round's epoch) — CoreID-rotating,
  optional future hardening only, not needed for theft-safety (§4.4).
- **Permanent garbage prevents late double-settle.** A delayed copy of `C` surfacing years later
  (the bounced email finally arriving) hits the 55-year garbage record → refused.
- **Untrusted wallet.** k validators verify the gate against Nabla's own registration + status;
  the wallet cannot self-authenticate a fake claim.
- **The residual (§4.3):** a receiver who *received* `C` but stays offline the entire window can
  have a legitimate payment recovered. Bounded (one payment; the receiver's own long inaction);
  the irreducible price of solving delivery failure under unreliable delivery.

RECALL is on the double-spend-critical path, so its build **must** ship a targeted adversarial
soak hammering the recall-vs-redeem race (analogous to the double-redeem replay arm).

---

## 4. Why RECALL is legitimate — recovering an *undelivered* payment, not repudiating a *received* one

RECALL exists to fix one real, otherwise-unrecoverable failure: **a payment that completed
on-chain but whose cheque never reached the receiver.** The send is valid (3-of-3, sender debited
`B−A`, cheque `C` completion-registered), yet the money is stranded — receiver can't redeem what
they never got, sender can't re-spend what they paid out. This is the one failure the social
layer cannot fix.

This is **not** the cheque-retract we deliberately banned. The distinguishing question is **not**
*"did the send complete?"* — it is **"does the receiver actually hold a redeemable cheque?"**

| | **Retract a RECEIVED cheque** (BANNED — repudiation) | **RECALL an UNDELIVERED cheque** (this doc — recovery) |
|---|---|---|
| Send completed (3-of-3)? | yes | yes |
| Receiver holds the cheque? | **yes** — delivered; can redeem at will | **no** — never delivered; can't redeem what they don't have |
| Anyone relying on the value? | yes — receiver is counting on it | no — receiver never received it / never knew |
| What breaks if allowed? | repudiation, disputes, double-spend | nothing — we return money nobody could ever touch |
| Human fix exists? | yes — receiver redeems, refunds socially | no — can't refund what was never received |

RECALL fills only the right column, and the §2 safeguards keep it structurally there — it can
never reach a cheque the receiver holds.

### 4.1 The safeguards that keep it honest
- **Receiver's protected fair-chance window** (§2.1.3): recall can't even initiate until `C` is
  `[18000, 50000]` old; a delivered-and-redeemed cheque inside that window makes the payment stand.
- **Consume-once → first-wins** (§2.2): a delivered-and-redeemed transfer is never reversed.
- **Permanent garbage** (§2.2 / §5): the undelivered cheque is dead mesh-wide for ≥55 years.

### 4.2 What this replaces
The pre-2026-07-07 recall gated on an *un-registered* failed send. The quorum gate makes that a
no-op (nothing stranded), so recall's gate inverts to a *completed* send (§2.1). RE-ISSUE (a
separate receiver-side re-delivery op) is **dropped** — no re-delivery; recall + re-send instead.

### 4.3 The one residual — stated honestly
A receiver who *did* receive `C` but is offline/slow for the **entire** window can have a
legitimately-received payment recovered. The long window + "redeem promptly" UX mitigate it; it is
the irreducible price of solving delivery failure at all, narrowly bounded, and far smaller than
the dispute surface the received-cheque ban still closes. **Retracting a *received* cheque remains
banned** (standing design decision): reversing a payment the receiver *holds* is a social action
that opens the repudiation / dispute / double-spend flood-gate the design exists to close.

### 4.4 Window enforcement model + the tick-projection guard (2026-07-12)
The init-window bounds `RECALL_INIT_WINDOW_LOW/HIGH` (18000 / 50000 prod) are TICK COUNTS; the recall
age is a difference of tick VALUES (`recall_tick − completion_tick`, both unix-second stamps, i.e. an
age in SECONDS). They MUST be compared on the same scale — `age_secs ∈ [LOW.to_secs(), HIGH.to_secs()]`
— projected through the single `axiom_core_logic::types::ticks_to_secs` (`× TICK_INTERVAL_SECS`). A
2026-07-12 audit (Mac) found `register_recall` comparing the seconds-age against the RAW tick counts
with no projection, so the window opened `TICK_INTERVAL_SECS`× early (~5× at 5 s/tick — 18000 s
instead of 90000 s), shortening the receiver's guaranteed head-start. **Fixed + guarded:** the window
constants are now typed `TickCount`, whose only projection is `.to_secs()`, so a raw
`age < RECALL_INIT_WINDOW_LOW` is a COMPILE ERROR — the 3rd recurrence of the tick-count-vs-value
confusion cannot happen a 4th time. CoreID-neutral: the check is Nabla host code and Core execution
never referenced these constants.

**Enforcement decision (2026-07-12) — keep it simple: Nabla-enforcement is the design, not a
stopgap.** Core owns the constants + the projection, and Core CL2 still authorizes the recall itself
(`verify_recall_attestation` + txid-bind + amount-pin), but Core does NOT re-execute the age check.
An adversarial *blessed* Nabla can therefore bypass the head-start (§3) — and that is **accepted by
design, not a fix owed**, because **consume-once, not the window, is the theft protection**. The bypass
creates no new vector: it only tightens the bound on the *already-accepted* §4.3 offline-receiver
residual (from a guaranteed 18000-tick head-start to a head-start not guaranteed against a *colluding*
Nabla), and can never steal from a receiver who redeems.

A Core age-check between the two **k-witnessed** epochs (the failed send's own epoch + the recall
round's epoch — unforgeable by a rogue Nabla, unlike a Nabla-signed tick) is available as **optional
future hardening**, warranted *only if* the threat model is later elevated to require the head-start
*guarantee* itself to survive a malicious blessed Nabla. It would rotate the CoreID and reinstate a
corrected form of the `failed_send_epoch` check removed 2026-07-06. It is **not needed for correctness
or theft-safety** under the current model. See KnownIssues KI#40 (accepted residual, not a deferred
fix).

---

## 5. Relationship to existing mechanisms (reuse map)

RECALL is almost entirely composition of parts AXIOM already has:

- **Quorum gate** (Yellow-Paper core rule) — makes failed sends a no-op; recall's premise. *Given.*
- **Garbage-state bloom chain + 55-yr retention** (YP §21.10.6 / §39.9.5, `CLARA_Bloom`) — the
  permanent "`C` is dead" record + its Console-governed rotation floor. **Reused, never rebuilt**
  (see memory: never build a new retention/rotation/WAL system). Only *possible* addition: a
  terminal txid status (`Retracted`) inside the existing three-state machinery.
- **Nabla consume-once (A7)** — recall-vs-redeem serialization. *Reused.*
- **HAL binary hibernation + OODS gate (YPX-020/021)** — the maturity window (OODS-healthy to
  enter and to exit, the general hibernation gate) + `hibernation_until_for`. *Reused.*
- **k-witness round + `tx → cheque → redeem`** — recall's completion is a normal redeem; balance
  rises only through CL5. *Reused.*
- **Snapshot + WAL persistence** (the existing `NablaSnapshot` + `WalOp` recovery pair) — the
  three exact txid terminals (`completed` / `redeemed` / `recalled`) **and** the garbage chain
  ride the SAME snapshot-plus-WAL-replay recovery every other durable Nabla record uses. A node
  restart MUST NOT forget a recall — without this the "permanent" record is process-lifetime only.
  *Reused, never a new persistence system.*
- **Archive resolution — never gate on a raw bloom Hit.** The garbage chain is a bloom: a `Hit`
  may be a false positive, and naively refusing on it would strand a legitimate redeem. The
  **persisted exact terminals ARE the archive layer**: a garbage `Hit` resolves locally against
  them — exact-hit ⇒ refuse (the terminal is the authority, as today); exact-miss ⇒ false
  positive ⇒ allow, logged. (Remote archive enquiry for a node that lost its exact record is the
  bloom chain's deferred Phase-3 path; with mesh-wide insert + persistence the exact map and the
  chain converge at every node, so local resolution is consistent.)
- **Mesh-wide garbage insert.** Every node inserts `C`'s txid into its OWN garbage chain when the
  (commit-phase) Recall gossip arrives — not just the initiating node. The gossip marker merge
  (`recalled_txids`) and the durable chain insert happen together at every node.
- **New surface (small):** the inverted eligibility gate (completion-registered + `NotRedeemed` +
  window + OODS), the two-phase reservation/commit (§2.2.1), the garbage submit at
  hibernation-entry, and the SDK's deliberate enquire-then-initiate flow.
  If a piece needs more than this, it is scope-creep — re-read this section.

---

## 6. Remaining work

The protocol is implemented and deployed (see the Status header); built docs-first
from this spec. Still open, in build order:

1. **Garbage-chain persistence + archive-resolution enforcement** (§5) — the
   mesh currently serializes the recall terminal via the `recalled_txids`
   marker map + committed gossip flood; the bloom-chain persistence (snapshot +
   WAL) and archive-resolution enforcement specified in §5 remain to be built.
2. **Mesh-wide garbage insert on gossip receipt** (§6.4(b)) — every Nabla
   inserting into its own garbage chain when the committed marker arrives.
3. **Recall-vs-redeem adversarial soak** (`--recall-race-rate`) — the race
   validation is still pending; run on a quiet env.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
