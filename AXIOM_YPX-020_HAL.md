# AXIOM YPX-020 — HAL: Help Absent Lambda (dead-overlap wallet resurrection)

Spec class: Yellow Paper Extension (YPX). Status: IMPLEMENTED (§2 completion model),
env-validated + shipped — 2026-06-23 (dev CoreID 5564323f). DRAFT spec / pre-mainnet.
Design: AXIOM Origin; adversarially analysed during review.
Scope: protocol-surface (Lambda + Nabla + SDK) + clients (Mac + webclient).
Supersedes the §10 FUTURE_WORK "overlap reduction for dead validators" sketch.
Companion to YPX-018 (HEAL/CLARA): HEAL recovers *partial commits while witnesses live*; HAL
recovers *dead-overlap when the witnesses are gone*.

> **CURRENT MODEL (shipped 2026-06-23): §2 completion — read the "APPROVED — §2 completion"
> section.** `hal_reanchor` mints ONE distress cheque + hibernates; completion = REDEEM that
> cheque (one send + one redeem, one dust cheque). The §6 "Minimal implementation" section
> below is the prior interim build (a second `hal_complete` self-send) — **SUPERSEDED**;
> retained for history. Do not build §6, and do not build the §2 session scaffolding from §2–§3
> (the A12 fix + the binary-hibernation model collapse most of that machinery).

> *"I'm sorry Dave, I'm afraid your witnesses are dead."* — HAL re-anchors a wallet whose
> prior Lambda witnesses have vanished, **without** weakening the S-ABR overlap that stops
> double-spends.

---

## 1. Problem

A returning wallet's next tx (send / redeem / **heal**) requires `k-1` overlapped signatures
from its **specific prior witnesses** — `validation.rs:827-832` + `modes.rs` CL2 (`verify k-1
overlapped sigs`). This overlap is the *synchronous* anti-double-spend gate: it covers the
Nabla SMT's gossip-lag window so a returning wallet can't present an old head to a fresh
disjoint quorum.

**The gap:** if enough of those specific prior witnesses become unreachable, the overlap can't
close and the wallet is **stuck**. The trigger (overlap floor `sabr_overlap(k)`):

| tier | live prior witnesses lost | remaining | overlap floor | stuck? |
|---|---|---|---|---|
| k=3 | 2 | 1 | 2 | yes |
| k=4 | 2 | 2 | 3 | yes |
| k=5 | 3 | 2 | 3 | yes |

**`heal()` does NOT recover this** (re-verified 2026-06-19, `modes.rs` CL2): a TX_HEAL is also a
returning tx and still requires `k-1` *prior-witness* overlap sigs. If the prior witnesses are
dead, heal fails identically to a normal send. Per-tx probability of hitting the trigger ≈
**`3q²`** (q = per-validator unavailability) — small per tx, but **accumulates over a wallet's
lifetime** and is non-negligible at scale on a permissionless, hobbyist-operated validator set.

It is a **liveness** gap, never a safety one: a stuck wallet is *stuck*, never double-spent.

### Design constraints (what killed the easy fixes)

1. **Untrusted wallet** — can't carry an unverified "my head is current" claim; non-supersession
   is a proof-of-absence that no untrusted party can self-authenticate.
2. **Hobbyist Lambda churn** — validators are trivially spun up; assume any quality, dropping at
   any time, possibly permanently. So no fix may depend on the *specific* prior witnesses.
3. **Lambda = proper hardware + DB; Nabla = citizen / low-end mesh.** Authoritative state stays
   on Lambda. Do NOT move the head-of-record onto Nabla.
4. **No new per-tx standing cost** (rules out fan-out / home-shard replication of every head).
5. **Pay-on-demand** — only the rare stuck wallet should pay.

Rejected alternatives: proactive re-anchor (can't predict abrupt loss), VBC-expiry deadness
(too slow / a live-VBC validator can already be gone), fan-out of the S-ABR record (taxes every
tx + overlap needs *live sigs*, not stored records), home-shard head-of-record (moves authority
off Lambda / re-architects S-ABR).

---

## 2. The HAL protocol

HAL is a **pay-on-demand resurrection path**: a special dust self-send cheque, a public distress
broadcast, a long wait that lets the global Nabla SMT *converge* (so it can stand in for the dead
synchronous overlap), an automatic conflict challenge, and a bounded session so Nabla never
stores a perpetual WAL.

Latency core idea: **overlap exists only to cover the SMT's gossip-lag window synchronously. Wait
long enough and the SMT fully converges — then the converged mesh, not the dead witnesses, is the
authority on the wallet's true head.**

> **Safety invariant (load-bearing — read before the rest).** HAL relaxes the *synchronous Lambda
> prior-witness overlap*. It does **NOT** relax the **global Nabla SMT consume-once**. HAL
> completion is, mechanically, an ordinary **global SMT advance `X → X′`**, and that advance
> succeeds **only if `X` is still globally unconsumed** — exactly like any send or redeem. If the
> wallet ever spent `X → Y`, `X` is consumed in the replicated SMT and the `X′` registration hits
> `StateMismatch` **regardless of which confirmers signed**. The confirmer set is therefore a
> **liveness / convergence-assurance** device, **never the safety authority** — it cannot mint a
> second spend even if every confirmer is adversarial. This is why no part of HAL depends on the
> confirmers being honest *for safety*, and why grinding/cherry-picking the confirmer set (A7/A2)
> buys an attacker nothing but griefing.

> **⚠ KI#34 (2026-06-24, code-verified) — the invariant above silently assumes RETENTION.**
> "X is consumed *in the replicated SMT*" only holds on a node that still **holds** that record.
> The consume-once gate is the trustless backstop against *dishonest confirmers* (true), but it is
> NOT resilient to the consumed record being **wiped/partitioned away** — and that is the one axis
> HAL uniquely exposes. Verified in code: a normal send/heal on a wiped network **rejects**
> (`validate_sabr_overlapped` → `lookup_previous_tx_record` reads local storage only →
> `SabrStateChainMismatch` on a miss), so a wiped wallet is **DEAD (liveness-safe)**. **HAL is the
> ONLY re-activation path** for a wiped/dead-overlap wallet — it relaxes the overlap (`modes.rs:479`)
> and reaches fresh validators via `validate_sabr_new` (no record required). So HAL **trades the
> wipe-surviving overlap defense for the Nabla consume-once net** — and that net can *also* be wiped.
> Honest validator-wipe alone ⇒ dead (safe); a coordinated **validator + Nabla wipe** (or a malicious
> node that skips the check) removes consume-once ⇒ a rolled-back wallet can **revive**. Mitigations:
> **check 1** (HAL fails closed at register when no held state — `registration.rs`, SHIPPED) +
> **check 3** (HAL-advance fork-ban via the **endorsement** model — a `HalAdvance` gossip carries
> `old_state` + its k3 sigs, each honest node pairs it against its OWN held `X→Y` (`NablaEntry`
> gained `previous_state`) and emits a `BanAlert` endorsed by ≥3 distinct nodes (`nabla_signatures`)
> → freeze; under-witnessed advances dropped (anti-framing), no held state ⇒ no false-freeze; NO
> per-wallet k3-sig retention. The HONEST mesh detects revivals independent of the processing node —
> **SHIPPED 2026-06-24, master `7154be5a`, live A/B/C passed** (`nabla/examples/ki34_live_inject.rs`)).
> The §6 distress-quorum/reject-latch this doc later sketches was the safety layer
> the shipped binary-HAL dropped; check 3 restores its spirit. See `AXIOM_REPORT_KnownIssues.md` KI#34
> + `AXIOM_THREAT_CollusionWipeRevival.md`.

### Roles / counts
- **7 validators** total: **5** fresh (k=5) sign the distress cheque, **2** fresh witness the
  completion. Resurrection is vouched by more validators than a normal k=5 tx — appropriate for a
  high-stakes recovery.
- **Confirmer set `C`** attests "no conflict observed during the wait" — a **convergence-assurance
  signal that lets a legit stuck wallet complete**, NOT the safety gate (the global SMT consume-once
  is; see the safety invariant above). `C` is **VRF-selected per session by a `t=0` beacon** (TARDIS
  tick hash), a **large sample accepted on supermajority**. VRF selection is kept deliberately —
  **not for safety** (grinding it is moot, A7), but for **liveness / grief-resistance**: an
  unpredictable, wallet-independent set means a colluding minority cannot *pre-position* to
  withhold-certify and **block** a legitimate completion, nor target a specific victim's recovery.
  (The `hash(wallet_id)` home shard is still where W's *SMT entry lives* — that is fine; it is just
  not *who certifies*.)

### Timeline (ticks; ~5 s/tick)
```
t=0        DISTRESS: wallet self-builds a dust self-send "distress cheque" for its current head X,
           witnessed by a FRESH k=5 quorum (5 validators). Presents it to its hash(wallet_id)-derived
           home Nablas, which BROADCAST the distress to the whole mesh. Wallet → RECOVERING mesh-wide
           (a status-only overlay each node applies to ITS OWN head — it does NOT carry/install X;
           a node holding a later head Y keeps Y, see A8). RECOVERING = TOTAL LOCKOUT: for the entire
           0..18000 wait the wallet can do NOTHING — no send, no redeem, no heal, no burn (A10), no
           early completion. The ONLY action it may ever take is the HAL completion, and only once
           t≥18000. Before completion: nothing.
           The session is WAL-PINNED: every Nabla records {wallet, X, session} in its WAL. A second
           HAL registration for W at ANY OTHER Nabla is REJECTED with NO state change until t=20000
           (one live session per wallet, mesh-wide — see A9).
t=0..18000 WAIT / CHALLENGE window (~25 h): every Nabla holding a more-advanced head Y for this
           wallet STOPS propagating the session and AUTO-floods a REJECT carrying receipt(Y). The
           session decision is a ONE-WAY LATCH — ACCEPT/PENDING → REJECT, never back (§2 reject-latch).
           The long wait is the convergence margin: even the single LAST node holding Y has time to
           flood REJECT to every confirmer before completion opens. Any real conflict reaches everyone.
t=18000..20000  COMPLETION window (~2.8 h): a Nabla certifies ONLY if it holds a POSITIVE ACCEPT
           record for the session (converged to X, no REJECT). ABSENCE OF A RECORD ⇒ REJECT — only an
           explicit accept is an accept (fail-closed). On supermajority of positive accepts, the wallet
           redeems the distress cheque (the "special cheque" — normal redeem path), witnessed by 2 NEW
           validators (7 total). New head registers normally (consume-once still applies). FREEZE lifts.
t=20000    EXPIRY: session ends. Nabla PRUNES the transient distress/challenge record (bounded WAL).
           If not completed, freeze lifts; wallet must restart HAL (fresh session, fresh 25 h wait).
```

### Distress cheque + what Nabla compares

The distress request **is** the k=5-signed dust **self-send cheque `X → X′`** — it carries both
states already, no extra fields:
- **`X`** = the wallet's claimed current head, inside the cheque's **`prev_receipt(X)`** (the last
  k-signed receipt the now-dead witnesses produced — *data*, fully verifiable even though the
  signers are gone; this proves X was a *real* witnessed head, so the wallet can't assert a fat
  favorable X).
- **`X′`** = the produced state of the self-send (a re-anchor; dust value, **no value leaves the
  wallet** to any counterparty).
- **k=5 distress sigs** over `X → X′` (fresh validators attest the *transition* is Core-valid; they
  cannot attest *currentness* — that's Nabla's job).

Nabla challenges on **`X` vs its own SMT head — the FROM-state only. `X′` is never compared** (it's
only what the SMT advances to on completion). The only attack is replaying a **stale X** to
resurrect old balance; `X′` carries nothing forward to steal.

| Nabla's SMT head for W | meaning | action |
|---|---|---|
| `== X` | claim matches the global record | silent — X is current |
| `Y`, lineage `X →…→ Y` | wallet already spent X forward | **CHALLENGE** — broadcast `receipt(Y)` |
| `Y`, conflicting/fork | divergence | **CHALLENGE** |
| `X`, but SMT *behind* a k-signed X | witnessed, never registered | advance-on-proof, no challenge |
| no entry | never advanced past X / genesis | no challenge |

A challenge is **the receipt itself** — a Nabla challenges *"I hold a k-signed `Y` that descends
from `X`,"* not *"X ≠ what I have."* The lineage requirement means a merely-lagging honest Nabla
(hasn't seen X yet) does **not** false-challenge; only one holding a genuinely *later* receipt does.
**Nabla never challenges "are you really stuck"** — deadness is unprovable; HAL is *safe for any
wallet to invoke, just expensive*, so abuse is self-deterring, not policed.

### The reject-latch (monotone, one-way — the core safety-liveness primitive)

A HAL session's decision is a **monotone semilattice value**: `PENDING → ACCEPT(provisional) →
REJECT(final)`, and **only that direction** — a node that has latched REJECT never un-rejects.

- **Why one-way is sound.** ACCEPT is a claim about the *absence* of a conflict — provisional,
  falsifiable the moment a conflict surfaces. REJECT is backed by *positive, permanent evidence*
  (a k-signed `Y` with lineage `X →…→ Y` — that never stops being true). So REJECT dominates ACCEPT
  in the join, and the value converges regardless of gossip order or loss — the same semilattice
  argument that makes the SMT merge converge.
- **Stop-and-flood.** The instant a Nabla observes the conflict (holds `Y`, or *receives* a REJECT),
  it **halts propagation of the session approval** and **floods `REJECT{session, receipt(Y)}`** to
  the whole mesh. One honest node's discovery is therefore enough to poison the entire session.
- **Evidence-bound (anti-grief — mandatory).** A node latches REJECT **only after verifying the
  carried receipt** (`Y` is k-signed and descends from this session's `X`). A bare "reject" flag is
  never honoured. A genuinely-stuck wallet at head `X` has **no** descendant `Y`, so no valid REJECT
  can be fabricated against it — the latch carries exactly the existing challenge's evidence bar, so
  it adds **no new false-reject / griefing vector** (a malicious node can only *withhold*, A6).
- **Session-bound.** REJECT binds to `(wallet, X, session_nonce/beacon)`; an old REJECT cannot be
  replayed to poison a *different* later session for a different head.
- **Fail-closed: absence ⇒ REJECT.** At completion a Nabla certifies ONLY on a **positive ACCEPT**
  record (it saw the distress, converged to `X`, latched no REJECT). An **empty / absent record is
  treated as REJECT** — only an explicit accept is an accept. So a Nabla that never participated
  (partitioned, never saw the session) contributes nothing rather than a permissive default; an
  attacker can never harvest a non-participating node's silence as consent. (No-permissive-default,
  per `[[feedback_no_fallback_design]]`.)
- **What 25 h buys.** The wait is sized so the worst-case propagation path — from the single last
  conflict-holder, through anti-entropy, to *every* confirmer — completes before the completion
  window (`18000`) opens. So at completion, a confirmer has either latched REJECT (if a conflict
  exists anywhere reachable) or genuinely holds `X`.

**Safety-liveness consequence: 1-of-N honest.** If even one honest Nabla anywhere holds the
conflicting `Y` and is not partitioned for the full 25 h, the session is rejected mesh-wide — far
stronger than "K confirmers honest." And this sits *above* the zero-trust backstop: even if the
latch were fully suppressed (total 25 h partition, A4) and every confirmer were malicious, the
**consume-once at completion still rejects `X→X′`** on any node holding `Y` (A8-safe head). The
latch is the *global early abort*; the consume-once is the *final, trustless* gate.

### Process diagram

```
                 HAL — Help Absent Lambda   (resurrect a dead-overlap wallet)

 WALLET  (stuck: live prior witnesses  <  sabr_overlap(k))
   │
   │  build dust self-send cheque   X ──► X'      (X' = re-anchor, no value out)
   │  carry  prev_receipt(X)  = k-sigs from the DEAD witnesses  (data, still verifiable)
   │  get 5 FRESH validators to sign the X->X' transition         (k=5 distress)
   v
 +------------------------------------------------------------------------------+
 | t=0   DISTRESS: deliver cheque -> confirmer set  C = sample(beacon_t0, wallet)|
 |       broadcast {wallet, X, X'} to the WHOLE mesh                             |
 |       WALLET -> RECOVERING mesh-wide  (status overlay on each node's OWN head; |
 |       never installs X over a later Y -- see A8)                              |
 +------------------------------------------------------------------------------+
   |
   |  +-----------  t = 0 .. 18000  (~25 h)  WAIT / REJECT-LATCH  --------------+
   |  |  every Nabla:  look up W in MY SMT                                      |
   |  |     SMT head == X .................... silent      (X is current)       |
   |  |     SMT head == Y , lineage X->..->Y . STOP gossip + FLOOD              |
   |  |                                        REJECT{session, receipt(Y)}      |  <- kills replay
   |  |  latch is ONE-WAY: ACCEPT/PENDING --> REJECT, never back                |
   |  |  any node receiving a verified REJECT re-floods it (1 honest node = mesh)|
   |  +-------------------------------------------------------------------------+
   |
   |  +-----------  t = 18000 .. 20000  (~2.8 h)  COMPLETION  ------------------+
   |  |  each confirmer in C signs ONLY if it holds a POSITIVE ACCEPT:           |
   |  |     (a) window elapsed   (b) explicit ACCEPT (absent record => REJECT)   |
   |  |     (c) my SMT == X   (d) no REJECT latched                              |
   |  |  need >= supermajority of C   +   2 NEW validators witness the redeem    |
   |  |  -> SMT advances  X ──► X'    -> FREEZE lifts                            |
   |  +-------------------------------------------------------------------------+
   v
 t=20000   PRUNE the session record    (bounded WAL — O(rate x window))

 compare (Nabla):  challenge iff  EXISTS k-signed Y with  X ->..-> Y   (FROM-state only; X' never compared)
```

### Why each piece is load-bearing
- **k=5 distress quorum** — attests the `X→X′` transition is Core-valid + `prev_receipt(X)` is real.
  Weak *anti-spam* on its own (validators are cheap to spin up, so 5 sybil sigs are near-free); the
  real spam bound is the **owner-key gate (A5) + the WAL-pinned one-session-per-wallet (A9)**, not
  the k=5 cost. The quorum's job is transition-validity, not rate-limiting.
- **Public broadcast** — every Nabla hears it, so a conflict can surface from anywhere.
- **Wait (18000)** — lets the SMT converge so confirmers don't certify on a stale view; it is the
  *convergence/liveness* margin, not the safety gate (the consume-once is — §2 invariant). Must
  exceed worst-case anti-entropy propagation by a wide margin.
- **Reject-latch** — the *early-abort* signal, as a monotone one-way value (ACCEPT→REJECT, never
  back): a Nabla holding a conflicting head stops gossip and floods an evidence-bound REJECT, which
  every receiver re-floods — so one honest node poisons the session mesh-wide, no human in the loop.
  Even if every REJECT were suppressed, the completion's global `X′` advance still fails on the
  consumed `X` (consume-once backstop). NB: the recovery freeze blocks the *wallet's* transactions,
  it does **not** gag a node's challenge/REJECT **gossip** — a `(Y, Recovering)` node still floods
  REJECT (the 1-of-N path is never silenced by the freeze it is subject to).
- **Freeze (RECOVERING) during 0..20000** — prevents racing a normal tx against the in-flight
  resurrection. MUST be a status-only overlay on each node's own head (A8): it changes *who may
  move*, never *where the head points*. (Even if the freeze leaked, the consume-once still
  serializes the race — the freeze is liveness, not the safety gate.)
- **Bounded session + prune** — caps Nabla's per-session WAL; mesh overhead = `O(rate × window)`,
  not an unbounded log (critical at 5M+ wallets).

---

## 2b. Completion enforcement — binary hibernation + the CL5 contract (normative; shipped 2026-06-23)

**Completion = redeem the distress cheque.** `hal_reanchor` mints ONE distress
cheque and hibernates; completion is a normal CL5 redeem of that cheque by 2 NEW
validators — one send + one redeem, one dust cheque. (An interim `hal_complete`
self-send model was built first and then dropped: it doubled the rounds and dust
for no safety gain — see §6, retained for history. The 2nd round's confirmer
honesty was never the anti-double-spend gate; the only authoritative record is
the global Nabla SMT consume-once + `StateMismatch` + the reject-latch, and the
completion redeem advances the SMT identically.)

**Hibernation is a binary flag on the wallet state, NOT a deadline.**

1. While the flag is set, Core **hard-rejects any tx — no comparison**. This
   deletes the entire tick-authority / cross-validator clock-divergence problem:
   there is nothing to compare, and a client cannot time-travel past a boolean.
2. **The flag clears on COMPLETION, not on a clock** — and the completion redeem
   is the ONE tx Core must ACCEPT while the flag is set (if Core rejected
   everything, the wallet could never escape). The time element moves off the
   lockout and onto the completion: the completion redeem is checked against the
   window at the validators/Nabla, where the authoritative TARDIS tick lives —
   sidestepping the client-clock problem the interim tick-deadline design
   tripped over. "Wait" means "finish your HAL," not "wait N ticks before acting."
3. **A wallet that never completes is a non-issue** — its funds are locked behind
   the flag until it completes; the incentive is already aligned. No timeout, no
   auto-clear.
4. **The one real edge case:** if the new k=5 HAL validators also die during
   hibernation, the wallet restarts a fresh HAL (new cheque, new window). This
   single escape hatch is the only liveness mechanism the design needs.

**Core CL5 contract** for redeeming a HAL distress cheque (a `HalReanchor`-kind
self-send `X→X'` cheque):

- **(a) time-lock** — reject before the convergence window elapses (the
  hibernation deadline on `X'`'s state).
- **(b) no-conflict check** — the consume-once / supersession / confirmer-set
  ACCEPT gate, at redeem time (the SMT consume-once remains the backstop; this
  is the cooperative fast-path).
- **(c) un-hibernate** — the produced state carries `hibernation_until = 0`;
  gossip the clear.
- **(d) gate-exempt** — a hibernating wallet may redeem ITS OWN distress cheque
  (the one carve-out to the hard-reject, keyed on the cheque being the wallet's
  own `HalReanchor` self-send).

**Why imperfect enforcement is safe regardless (the scar floor).** Even if a
hibernating wallet's tx slips a gate, it cannot cleanly double-spend. The Nabla
cheque-claim gate is keyed on the cheque's `sender_wallet_pk`, so a cheque a
hibernating wallet issued cannot be claimed: under the default
`RequireConfirmed` the receiver's redeem holds/retries (funds in-flight, no
scar); under opt-in `AcceptScarred` it produces a scarred FACT link (never
compresses, receiver-rejectable, a self-limiting penalty). The actual conflict
hibernation guards against (a concurrent head `Y`) is caught by fork-detection
regardless. The binary gate is a clean-UX early-reject; the authoritative
safety is Nabla + scar + fork-detection, not a perfect time-gate.

**User flow (clients):** re-anchor (one key-proved self-send → hibernate) → wait
the convergence window (banner estimate; ~25 h prod) → "Finish recovery" redeems
the distress cheque; CL5 clears `hibernation_until`. Two clicks, one cheque, one
redeem; a "Restart…" hatch re-enters HAL if the completion round cannot commit.

## 3. Security analysis

Safety does **not** reduce to "do the confirmers attest honestly" — it reduces to the **global
Nabla SMT consume-once** (the safety invariant in §2). HAL completion is a real SMT advance
`X → X′`; it succeeds only if `X` is globally unconsumed. So the question "is there a more-advanced
head `Y`?" is answered by the *replicated SMT itself at registration time*, not by trusting the
confirmers. The confirmers + wait + challenge are a **liveness / convergence** layer that gets a
genuine stuck wallet through (and lets it abort early on a visible conflict); they are not the gate.
Attacks, in that light:

**A1 — replay an old head.** Attacker spent X→Y, replays X via HAL. Defeated **at the hard layer**
by the global SMT consume-once: `X` was consumed when `X→Y` registered, so the HAL completion's
`X′` advance hits `StateMismatch` no matter what the confirmers do. On top of it the **reject-latch**
(§2) makes the soft layer 1-of-N honest: any single Nabla holding `Y` floods a monotone, evidence-
bound REJECT that latches mesh-wide before completion — so the attacker must keep `Y` hidden from
*every* node for the full 25 h **and** defeat the replicated consume-once. Either gate alone already
stops the double-spend.

**A2 — cherry-pick friendly confirmers.** Even if the wallet picks confirmers that only saw `X`,
it gains nothing: those confirmers cannot make the `X′` SMT advance succeed if `X` is globally
consumed. Cherry-picking buys at most a *self-grief* (picking confirmers who then withhold). In
practice the confirmers are VRF/beacon-selected and wallet-independent anyway (see A7) — so even the
griefing angle is closed.

**A3 — collude the confirmers.** Suppose all home/confirmer Nablas are attacker-run. They can ignore
a real challenge and falsely certify "no conflict." **This still does not double-spend** — the
completion is a global SMT advance, and a wallet that already spent `X→Y` cannot also consume `X`
into `X′`; the registration conflicts with the replicated record. So confirmer collusion is a
**liveness/griefing** capability (they can *withhold* certification from, or stall, a legit wallet),
**not a safety break**. The `f^K` "all-home-K-adversarial" probability therefore bounds *grief*, not
*theft*. We still scale the confirmer sample (large sample + supermajority, A7) so a colluding
minority cannot block legit completions — but no value-path safety rests on `f^K` being negligible.

**A4 — partition.** Hide Y from the confirmers by partitioning the mesh. The attacker must sustain a
partition between *every* Y-holder and *every* confirmer for the **full 25 h** so no REJECT reaches
them (the latch re-floods on receipt, so one leaked link anywhere poisons the session). The wait
length is the safety margin the anti-entropy mesh is built to beat. And even a *successful* 25 h
partition does not double-spend: the completion's consume-once still rejects `X→X′` on any node that
holds `Y` once the partition heals — the partition can only *stall* the legit case (liveness), not
mint a second spend. Note the residual is **baseline partition-finality, not a HAL amplification**:
if the attacker fully partitions and registers `X→X′` inside the minority side, a receiver `C2`
there could see a payment that is **reversed on heal** (the `X→Y` / `X→X′` pair is the two-receipt
double-spend proof → `W` banned, `X′` branch scarred). That is the *same* caveat as any normal tx
accepted inside a partition — and HAL is strictly *better* here, because its 25 h window gives far
more time for the partition to heal and the conflict to be detected before any honest receiver would
treat the branch as final.

**A5 — grief a victim.** Can't: the distress cheque is **owner-key-signed** (only the wallet owner
can open HAL on their own wallet). Self-griefing is harmless.

**A6 — DoS the Nabla WAL.** Bounded by: owner-key gate (own wallets only) + k=5 distress cost (5
validator sigs per session) + the 20000-tick prune. At scale, concurrent sessions = `rate × window`;
the bound caps *duration*, but *rate* (`3q²`) still matters → good validator uptime keeps it down.

**A7 — grind the confirmer set (CONSIDERED AND DISMISSED *as a safety leak*, 2026-06-19).** The
first cut feared: if confirmers are `hash(wallet_id) → K`, the attacker grinds keypairs offline
until a `wallet_id` whose confirmer set is `K` Nablas they control, then double-spends by having
those confirmers certify "no conflict" over a head they already spent forward. **This is moot for
safety.** AXIOM **stores no per-wallet authority at the confirmers** — the wallet lives only with
the client, and the *only* authoritative anti-replay record is the **global, replicated Nabla SMT
consume-once**. A ground-out, fully-controlled confirmer set cannot make the completion's `X′` SMT
advance succeed once `X` is consumed: the registration conflicts with the global record
(`StateMismatch`, the A8 disjoint-subset defense). So grinding the selector controls *who waves the
flag*, never *whether `X` is spendable twice* — it does nothing an attacker cares about.
**Why VRF/beacon selection is still kept** (per design decision): not as the safety gate, but for
**liveness + grief-resistance**. `C = VRF(beacon_at_session_open, wallet_id) → large sample`, accept
on **supermajority**. The beacon (TARDIS tick hash at `t=0`, unknown when wallet_ids are ground and
fixed only after the k=5 distress cheque is committed) makes the confirmer set **unpredictable and
wallet-independent**, so a colluding minority cannot *pre-position* to withhold-certify and **block**
a legitimate stuck wallet, nor single out a victim's recovery to stall. Large sample + supermajority
keeps that griefing probability negligible. It is a robustness/anti-grief property layered on top of
the consume-once safety gate — not a substitute for it.

**A8 — roll the head back via the freeze merge-rule (REAL leak found by running the logic against
`nabla/src/types.rs:178` + `node.rs:2904`, 2026-06-19; the design MUST adopt the fix below).** The
anti-entropy merge rule `NablaEntry::superseded_by` ranks **any non-Normal status (Frozen/Tainted/
Banned) strictly above Normal, and that rank dominates tick AND current_state**:
```rust
let (r_self, r_in) = (rank(self.status), rank(incoming.status));
if r_in != r_self { return r_in > r_self; }   // Frozen beats Normal regardless of tick/state
```
This is safe **today** only because the *sole* writer of `Frozen` is `freeze_wallet()`
(`tardis.rs:1822`), which flips status on the node's **own existing entry** and **preserves
`current_state`**, and because a frozen wallet **rejects all transactions** (`is_wallet_blocked`).
HAL breaks both: it freezes off a **claimed** head `X` (not the node's local head) and then
**spends from the frozen wallet at completion**. If HAL's "FROZEN mesh-wide" is propagated as a
`NablaEntry{status:Frozen, current_state:X}`, then on every node holding the attacker's real
spent-forward head `Y` (`Normal`, higher tick), the frozen-`X` **supersedes `Y`** — the mesh rolls
back to `X` — and HAL's completion then registers `X→X′` against the rolled-back head. The
consume-once never fires because the head was rewound *before* the check. **Two spends from one
balance.**
**Fix (MANDATORY — pins §4 decision 5):** HAL's recovery-freeze MUST be a **pure status overlay
keyed by `wallet_id` that each node applies to ITS OWN locally-held head** (read local entry, flip
status, keep `current_state` — exactly `freeze_wallet`'s shape). It MUST NEVER transport a
`current_state`. Consequences: (1) a node holding `Y` freezes `(Y, recovering)`, so at completion
its consume-once still sees `current=Y ≠ old=X` → **rejects `X→X′` and challenges** — the head is
never erased; (2) use a **distinct `Recovering` status**, never the fork-`Frozen` rank, so the
fork→Banned path is untouched and completion can lawfully resume *only* a `Recovering` wallet;
(3) the `Recovering` overlay must **not** inherit the "rank dominates current_state" clause — it may
raise status but never lower `current_state`. In one line: **the freeze may change *who is allowed
to move*, never *where the head points*.**

**A9 — parallel-session / multi-Nabla DDoS.** Attacker opens HAL for the same wallet at many Nablas
at once (flood sessions, or race disjoint subsets that each see only `X`). Defeated by the
**WAL-pinned single live session**: the first `/register` writes `{wallet, X, session}` to the
Nabla WAL and the distress broadcast floods it mesh-wide, so every other Nabla learns a session for
W is open. A second HAL **session-open** for W at **any other Nabla** is **rejected with NO state
change until t=20000** (expiry) — exactly one live HAL session per wallet, mesh-wide. (The pin
rejects a new *open*; it does NOT reject the *completion* of the already-pinned session at t≥18000 —
completion is keyed to the same `{wallet, X, session}`, so a confirmer matches it to the pin rather
than treating it as a second open.) This caps the per-wallet WAL cost at one session and removes the
disjoint-subset race (there is no second subset to certify). Combined with the owner-key gate (A5) +
k=5 distress cost, session spam is bounded to `O(1 per wallet per 20000 ticks)`.

**A10 — burn / heal a wallet that is mid-HAL ("two exits from one state").** Without a gate, an
attacker opens HAL on `X` (re-anchor pending → `X′`) **and** `burn`s or `heal`s `X` on a recovery
path — value lands in a fresh wallet from the burn/heal AND in `X′` from HAL: two exits from one
balance. The replicated consume-once *usually* serializes them (whichever consumes `X` first wins),
but we do **not** lean on that race for a value-critical mutation. **Hard rule — TOTAL LOCKOUT:
while a wallet has an active HAL state (t=0..18000), it can do NOTHING at all — no send, no redeem,
no `burn`, no `heal`, no early completion. The ONLY permitted action is the HAL completion itself,
and only at t≥18000.** Two layers: (1) **Nabla** — `RECOVERING` rejects every tx for W at
`/register`, burn/heal included; (2) **Core** — the burn/heal proof MUST carry a fresh Nabla
attestation that W is **not** in a HAL session, and Core rejects otherwise (stateless Core learns
HAL-state only via a required witnessed input — the SEC-02 "Core requires Nabla blessing" pattern,
never Core-held state). So the two recovery paths are **mutually exclusive in time**: a wallet is
either HAL-recovering OR burn/heal-recovering, never both at once.

**A11 — manufacture an ACCEPT via the attacker's own `prev_receipt(X)` (advance-on-proof
manipulation; considered, contained, hardening required).** The distress cheque carries a real,
k-signed `prev_receipt(X)`. The existing KI#5 *advance-on-proof* path (compare-table row 4) lets a
Nabla whose SMT is *behind* `X` catch up to `X` on that proof. An attacker at real head `Y` (spent
`X→Y`) could supply `prev_receipt(X)` to push *lagging* confirmers to hold `X`, hoping they emit a
positive ACCEPT before anti-entropy delivers the superseding `Y`. **This does not break safety**, on
two independent grounds: (1) the **reject-latch dominates advance-on-proof** — any such node, on
*receiving* the flooded `REJECT{receipt(Y)}`, verifies `Y` (k-signed, descends from `X`) and latches
REJECT, abandoning the catch-up `X`; (2) the **consume-once backstop** — the completion's `X→X′`
registration floods mesh-wide and is rejected by every node holding `Y` (and trips the two-receipt
double-spend ban), so it never finalizes. The manipulation only bites under a full 25 h partition
isolating *every* `Y`-holder (A4), where consume-once still refuses on heal. **Hardening
(mandatory):** a confirmer's ACCEPT MUST rest on **independent convergence to `X`** via ordinary
gossip/anti-entropy — the attacker-supplied `prev_receipt(X)` may prove `X` was *real* (anti-fat-`X`)
but MUST NOT be the sole basis that advances a confirmer to `X` *for ACCEPT eligibility*.
Equivalently: advance-on-proof catch-up is fine for SMT liveness, but ACCEPT requires "`X` is my head
AND I have seen no superseding entry," not "I was just shown a proof of `X`."

**Implementation invariant (consume-once path).** HAL completion MUST register `X→X′` through the
**standard `process_registration` consume-once path** (the same `current_state == old_state` check
every send/redeem takes) — never a HAL-specific shortcut. The "special cheque" is special only in
*how it was authorized* (k=5 distress + confirmer accepts), never in *how it consumes*; the gate is
identical, so a stale `X` is refused identically.

**Implementation invariant (fork-detection priority — surfaced by the model harness,
`tests/hal_model_check.py`).** When two entries/registrations for the same wallet are **siblings**
(share a parent — e.g. `Y` and `X′`, both children of `X`), the merge path MUST treat that as a
**double-spend fork → ban** (`registration.rs:440`), and that detection MUST take **priority over
the `superseded_by` tick-merge**. A node must NEVER silently adopt a higher-tick *sibling* of its
current head — a higher tick wins only for a genuine *forward advance* (descendant), never for a
fork. This is what contains A3/A4 (a colluding subset's `X′` meets an honest `Y`-holder → ban) and
is exactly what A8 evades by erasing `Y` *back to `X`* before `X′` is presented, so the two never
meet as siblings. The harness double-spends on the buggy A8 and is clean on the fix + all of
A1/A3/A4/A11 — confirming both the leak and the fixes mechanically.

**A12 — gossip / anti-entropy head-rollback defeats the consume-once + reject-latch (REAL leak,
found by `tests/hal_model_check.py` + code audit of `nabla/src/node.rs:2904` +
`gossip.rs::apply_state_update`, 2026-06-19).** Both Nabla state-ingestion paths adopt an incoming
entry on **client-signature + `superseded_by` (higher-tick-wins) ONLY** — no lineage check, no fork
detection, no binding to a witnessed receipt. So a wallet owner can fabricate
`NablaEntry{wallet, X, tick=huge, valid_client_sig}` (signing their *own* old state `X`) and gossip
it; every node adopts it by the tick rule and **rolls its head back from `Y` to `X`**, with no
fork/double-spend detection (that fires only on the `/register` path with two k-sig receipts). The
rollback erases `Y` from the Nabla SMT, which **simultaneously blinds the reject-latch** (nodes no
longer see `Y`, so they don't challenge) **and the consume-once** (head is back at `X`, so `X→X′`
passes). Both of HAL's gates read the same gossip-mutable `current_state`, so one injection defeats
both → double-spend.

**Severity / scope (measured).** For a *normal* wallet this is **contained** by Lambda's
*independent* anti-rollback — §15 `verify_state_anchored` + S-ABR overlap, stored in `lambda.db`:
the prior witnesses stored head=`Y` and refuse to witness a fresh `X→Z`, so a Nabla-only rollback
does not re-spend. HAL is exposed **precisely because it relaxes that Lambda overlap** (dead
witnesses → fresh validators + confirmer attestation): that removes the Lambda co-gate and makes the
Nabla consume-once the *sole* gate — and that gate is rollback-able. So A12 is a HAL-specific leak,
not a general break of the running network. (The latent Nabla gossip-path gap — no
witness-binding/fork-detection on `apply_remote_entry`/`apply_state_update` — is worth a **separate
hardening** investigation, but its blast radius today is bounded by the Lambda co-gate.)

**Fix (MANDATORY for HAL).** HAL's consume-once **and** reject-latch MUST be evaluated against the
**durable WITNESSED-receipt set** (k-signed `X→·` records), NOT the gossip-mutable `current_state`.
A self-signed entry can move the head but **cannot forge a k-signed receipt**, so the
witnessed-receipt view is rollback-proof: the retained `X→Y` receipt makes a Nabla challenge (latch
REJECT) and refuse completion regardless of what the current head was rolled to. Equivalently: *the
"is X already spent?" question must be answered from immutable witnessed history, never from the
mutable SMT head.* (Recommended general hardening, separate track: bind the gossip/AE merge tie-break
to a **witnessed** seq/receipt — not a client-chosen tick — and reject a non-descendant adoption as a
fork. That closes the rollback for every wallet, not just HAL.)

**Invariant:** HAL **relaxes the synchronous Lambda prior-witness overlap, and ONLY that.** It never
relaxes the **global Nabla SMT consume-once** *(evaluated against witnessed history, never the
gossip-mutable head — A12)*, never trusts the wallet, never moves authoritative
state onto Nabla, **and never lets the recovery-freeze rewrite `current_state`** (A8). Safety rests
entirely on the replicated consume-once *evaluated against each node's own retained head*: a wallet
that spent `X→Y` can never also consume `X→X′`, whatever the confirmers sign and whatever freeze is
in flight. Above that backstop sits the **monotone reject-latch** (ACCEPT→REJECT only, evidence-
bound, re-flooded by every receiver), which makes the soft layer **1-of-N honest** — one honest
Nabla holding `Y` poisons the session mesh-wide within the 25 h window. Completion is **fail-closed**:
only a positive ACCEPT counts, an absent record is a REJECT. The session is a **WAL-pinned, single
live session per wallet** (A9), and while it is open the wallet can **neither burn nor heal** —
Core-enforced, so the two recovery paths are mutually exclusive in time (A10). The confirmers + wait
+ latch are a **liveness/convergence** layer — a hostile confirmer (or a whole colluding home set)
can only **withhold** (→ the wallet restarts HAL), never **mint a second spend**, and can never flip
a latched REJECT back to ACCEPT.

### Why absolute Nabla sync is NOT required (settles the recurring concern — do not re-litigate)

Every reviewer eventually asks: *"what if a Nabla missed the gossip / is stale / is offline — won't
HAL accept a fraud, or wrongly reject a legit wallet?"* This is settled. **HAL safety is a property
of the replicated majority, never of any individual node.** Demanding perfect convergence is both
impossible (a permissionless, hobbyist, churning mesh is *always* slightly divergent) and
unnecessary. The full argument, so nobody has to reconstruct it again:

1. **The fraud evidence is itself replicated to the majority.** A fraudulent re-anchor exists only
   if `X` was already spent forward (`X→Y`). But `X→Y` is a **witnessed, k-signed, mesh-flooded
   registration** — so by the time the wait elapses, the **majority of Nablas hold `Y`**. The fraud
   doesn't get to hide its own evidence; it created it, mesh-wide, when it spent.
2. **The majority rejects with the *ordinary* consume-once.** Presented with `X→X′` (old=`X`), every
   node holding `Y` runs the existing `current_state == old_state` check, sees `Y ≠ X`, and rejects.
   The fraud **cannot assemble an accepting quorum** because the honest majority is rejecting. No new
   mechanism — the existing gate, applied by replication.
3. **A single absent/stale node is noise — it cannot flip a majority — and both of its possible
   errors are safe:**
   - stale node wrongly **rejects** a legit wallet → *liveness only* (the quorum tolerates a few; the
     wallet retries; the node re-syncs from a snapshot).
   - stale node wrongly **accepts** the fraud → it lands on the **losing side** of the `X′`-vs-`Y`
     fork → fork-detection bans the attacker. This only ever punishes a *real* attacker — a legit
     wallet has no `Y`, so a stale node accepting it is simply *correct*, no fork, no false ban.
4. **Two invariants keep "majority holds `Y`" true** (both already in the build, §6): the **wait**
   guarantees `Y` has propagated to the majority before completion; **witness-backed gossip**
   guarantees an attacker cannot forge a rollback that flips the majority's heads from `Y` back to
   `X`. Together they are *sufficient* — nothing else (perfect sync, mesh-wide head queries,
   per-node re-verification of every entry, "pull-on-completion") buys any safety the majority
   doesn't already provide; it only adds bandwidth and sync.
5. **The only residual is a full mesh-wide partition** (A4): if *every* `Y`-holder is offline for the
   entire window, the conflict surfaces only on their return (resolved by fork-ban on heal). This is
   the **baseline finality assumption of any gossip/replicated ledger** — not specific to HAL, not
   worsened by it, and made vanishingly small by the long wait.

**Rule for reviewers:** if the objection is "but a node might be out of sync," the answer is *yes,
and it doesn't matter* — safety lives in the replicated majority. Do **not** add active queries,
convergence proofs, or per-node sync guarantees to HAL on account of stale individuals. That is
exactly the complexity this section exists to forbid.

---

## 4. Open decisions

1. **Wait vs convergence-proof (v1/v2).** The fixed 18000-tick wait is a **time-gate**, which
   `[[feedback_no_timegates]]` disfavours ("cryptographic proof, not time windows"). It's defensible
   here — it's a recency/convergence margin on a *rare* path, and 25 h-to-unstick beats
   permanently-stuck — so ship the **wait as v1**. The clean **v2** replaces it with a *convergence
   proof*: ≥K Nablas attest "we held W's head stable across N anti-entropy rounds, no conflicting
   entry" — convergence proven by agreement, not assumed by elapsed time.
2. **Confirmer selection + sample size (a liveness/grief parameter, NOT the safety gate — see the
   §2 invariant + A7).** Safety is the global SMT consume-once; the confirmer set only governs how
   robustly a *legit* stuck wallet completes against a colluding minority that would withhold. Keep
   it **VRF-selected by a per-session beacon** (TARDIS tick hash at `t=0`), wallet-independent and
   unpredictable, so a minority can't pre-position to block a completion. A **large sample +
   supermajority** threshold; tie the size to the assumed adversarial Nabla fraction f (negligible
   griefing) and the alert-consensus scaling already in `nabla/`. Do NOT hard-code a small K.
3. **Window params.** `18000` wait / `2000` completion / `20000` expiry — tune the wait to exceed
   worst-case convergence with margin; the completion window must be comfortable for an online
   wallet but short enough to bound the freeze.
4. **Trigger thresholds.** `remaining_live_prior_witnesses < sabr_overlap(k)` per tier (table §1).
5. **Freeze semantics (PINNED by A8 — was open, now constrained).** The `Recovering` state MUST be
   a **status-only overlay** applied by each node to its own locally-held head; it MUST NOT transport
   `current_state` and MUST NOT reuse the fork-`Frozen` merge rank (which dominates tick/state and
   would roll a later head back to the claimed `X` — A8). A **distinct `WalletStatus::Recovering`**
   that blocks ordinary tx (like Frozen) but (a) never lowers `current_state` in the merge and
   (b) is the only status HAL completion may lawfully resume. Remaining open: exact lift-on-expiry,
   what a normal tx against a `Recovering` wallet returns, and interaction with a genuine fork
   detected mid-recovery (fork evidence must still win → Banned).
6. **Completion re-check** — satisfied *by construction* via the monotone reject-latch: a REJECT at
   t=17999 has latched permanently, so a confirmer at t∈[18000,20000] that signs only on `latch !=
   REJECT` is automatically blocked. No separate "accumulated status" bookkeeping needed; just never
   un-latch. **Latch persistence is a LIVENESS concern only, not safety** (re-derived this pass):
   fail-closed (decision built into completion — absence ⇒ REJECT) means a confirmer that restarts
   and loses its in-memory latch comes up with *no positive ACCEPT* → it refuses to certify, the safe
   outcome. And since the SMT itself is durable (WAL/snapshots), a restarted confirmer that truly
   held `Y` re-reads `Y` and re-floods REJECT anyway. So persisting the latch only spares a *legit*
   wallet a needless rejection (liveness); safety holds even if the latch is purely in-memory.

---

## 5. Relationship to existing mechanisms

- **`heal()`** — recovers partial-commit / scar / poisoning while ≥`k-1` prior witnesses are alive;
  does NOT recover dead-overlap (re-verified, `modes.rs` CL2). HAL is the dead-overlap path. The two
  are **mutually exclusive in time** (A10): a wallet mid-HAL can neither heal nor burn until the
  session completes/expires, so a balance is never simultaneously on a HAL re-anchor and a heal/burn
  recovery path.
- **Ark CI (YPX-010)** — offline/cold recovery; load-from-`k=3` + re-witness. HAL is the
  online-but-witnesses-dead path; the two may share the distress-cheque primitive.
- **§10 FUTURE_WORK** — HAL supersedes the "liveness attestation + reduced-overlap" sketch (which
  keyed deadness off VBC expiry; HAL keys safety off convergence + auto-challenge instead).
- **Nabla SMT consume-once** — HAL's auto-challenge is exactly an SMT-head conflict check; HAL adds
  the bounded distress session + the convergence wait that lets the SMT stand in for overlap.

---

## 6. Minimal implementation (v1) — build ONLY this

> The A-series (§3) is the *why-it's-safe* analysis. It is NOT a build list. Most of §2's
> machinery (reject-latch broadcast, VRF confirmers, fail-closed accept records, WAL-pin, the A10
> Core attestation) was designed to make a **mutable-head** consume-once safe by bolting
> convergence-attestation on top. The **A12 fix obsoletes all of it**: once "is `X` already spent?"
> is answered from **immutable witnessed history** and the Nabla SMT is **fully replicated**, the
> *ordinary registration consume-once already gives 1-of-N rejection by itself*. Build the small
> thing; do not build the scaffolding.

> **Minimal ≠ compromise.** Each cut below is safe *only because* a kept piece covers the same
> safety property. The four kept pieces jointly preserve EVERY safety property the scaffolding
> provided — verified by `tests/hal_model_check.py` (all A1–A12 contained; and the `REG-NOFORK` arm
> proves that dropping piece 4 re-opens a double-spend, so it is NOT optional).

**Build (FOUR small, mostly-reuse pieces — all load-bearing):**
1. **Witnessed-history consume-once** (Nabla, `registration.rs`): reject a re-anchor `X→X′` if any
   node holds a **witnessed** receipt `X→(≠X′)`. A predicate over the *receipts already in the SMT* —
   a local filter, no new store, no new wire op (`[[feedback_simple_gears]]`). *Synchronous gate
   (given convergence).*
2. **Overlap relaxation** (Core, at the existing §15 site): one `if/else` — when the tx is a
   key-proved re-anchor self-send with a proven-elapsed wait, verify the witnessed-history
   consume-once *instead of* the `k-1` prior-witness overlap. Mirror CL-MIGRATE's single-site
   substitution (`validation.rs`); never a parallel path. *The feature.*
3. **Convergence wait** (SDK + a reused status flag): the wallet marks "re-anchoring `X`" (reuse the
   existing wallet-status field — do **not** invent a session store), waits `W` ticks, then submits
   the re-anchor with `k` **fresh** witnesses. *Makes the consume-once decision correct — the overlap
   substitute that lets the gate REJECT synchronously if `X` was spent.*
4. **Sibling-fork detection on the merge/reconcile path** (Nabla — the A12-general fix,
   `[[project_nabla_gossip_no_fork_detection]]`): two states sharing a parent (`Y` vs `X′`) = a fork
   → ban, taking priority over the tick-merge. *The BACKSTOP: without it a partitioned/straggler node
   can accept the re-anchor and the tick-merge silently erases `Y` → double-spend (proven by
   `REG-NOFORK`).* It is also a general Nabla improvement — but HAL's safety **depends** on it, so it
   ships in v1, not "later."

**Do NOT build in v1 (each is genuinely redundant GIVEN pieces 1–4, not a dropped defense):**
- ✗ reject-latch broadcast / monotone / re-flood — redundant with the replicated registration
  consume-once (a converged node holding `X→Y` just rejects the register).
- ✗ VRF / beacon confirmer **selection** — there is no selected confirmer set; any converged node
  decides. A7 is moot by construction.
- ✗ fail-closed "accept records" bookkeeping — collapses into "a quorum of converged nodes accept
  the ordinary register."
- ✗ WAL-pinned session (A9) — no session state machine to pin.
- ✗ A10 Core no-burn/heal attestation — burn/heal and the re-anchor pass the **same**
  witnessed-history consume-once, so they serialize; no new Core rule, no Nabla blessing round-trip.
- ✗ 5+2 validator split — just `k` fresh witnesses on the one re-anchor.

Each ✗ is redundant *only because* a kept piece covers it: reject-latch ≡ the register consume-once
on a converged node (piece 1); confirmer-selection grief is moot with no selected set; WAL-pin / A10
disjoint-subset races are caught by fork-detection (piece 4) the same way A4 is. Drop a kept piece
and the corresponding ✗ stops being redundant — that is the line between *minimal* and *compromise*.

**Net new surface:** one Nabla consume-once predicate + one Nabla fork-detection check + one Core
overlap-relax branch + one reused status flag + SDK announce/wait/submit. No VRF, no confirmer
registry, no session store, no new wire op. If a piece needs more than that, it is the old
scaffolding creeping back — stop and re-read this section.

---

## 7. Status

**SHIPPED + env-validated 2026-06-23** (dev CoreID `5564323f`): Core CL5
contract §2b(a–d), SDK completion-as-redeem (`hal_complete`/`TxType::HalComplete`
removed across sdk-core/ffi/python/wasm), Mac wallet 2.17.5 + webclient
single-redeem recovery UX. The env HAL-lifecycle gate passes end-to-end
(re-anchor → hibernate → redeem-to-complete → unlock → send), and the model was
soak-validated (50w/72h endurance). The detailed build and fix log lives in the
repository git history.

---

*Document history: initial public release 2026-07. From this release onward,
every change to this document is recorded here and in the repository git log.*
