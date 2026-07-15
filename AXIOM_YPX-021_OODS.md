# AXIOM YPX-021 — OODS: Operational Observer Determination System

Spec class: Yellow Paper Extension (YPX). Status: **detection layer implemented and tested; the
§8.2 health-flag enforcement gate SHIPPED + deployed (2026-07-03, CoreID `a14e13278e4f09f5…`);
the full §5 Core-verified size-proof-as-required-input (Phase 2 / CL14) still deferred** (full
status and test roster in §12). Scope: a Nabla-layer estimator plus a Core-stamped receipt health
flag (Phase 1, shipped) building toward a Core-verified size proof on confirmations and
checkpoints (Phase 2) — consensus-critical; Phase 1 already rotated the CoreID.

OODS does **not** *close* the collusion/partition wash-out gap (§1); that gap is irreducible in a
consensus-free, no-global-view system. What OODS does is **price** it — converting a free,
grindable, amortizable attack into one that costs the attacker approximately a standing, bonded
fraction of the mesh ("lying about the network's size costs as much as being it"). The central
pricing claim (§5) is validated analytically (Appendix A) and empirically (§12.2); the full
residual analysis is §11.

> **Name.** In *Doctor Who*, the Ood share a single collective consciousness; an Ood severed
> from it *knows* it has been cut off. OODS is the mesh analogue: each Nabla node carries a piece
> of a shared, gossip-propagated sense of the collective's size, so a partitioned or eclipsed
> node detects that its estimate has collapsed. The name sits in Nabla's *Doctor Who* naming
> culture alongside TARDIS (see `CLAUDE.md`).

---

## 1. Problem — the wash-out laundering gap

AXIOM's connected-mode double-spend safety is real (S-ABR overlap + k-witnessing + the
receiver's asymmetric Nabla check). Its partition-mode safety, however, ultimately rests on
an honest-Nabla fraction `h`, which is **unpriced and unenforced**. The concrete attack:

1. A colluding sender **A** + receiver **B** eclipse their own view (point their Nabla list at
   only colluder nodes — nothing stops a wallet choosing its own nodes).
2. **A** double-spends a state `X`: one copy to an honest party, one to **B**. Inside a
   partition no node sees both branches, so each confirms locally.
3. Before the partition heals, A/B run a handful of transactions to trigger **FACT
   compression**, which *deletes* the double-spend provenance link ("wash-out").
4. At heal the fork is detected via the honest side's retained anchor → the sacrificial
   wallet **A** is banned — but **B**'s laundered copy now has clean, compressed provenance:
   untraceable, unscarred. **B keeps clean money.**

Why the existing defenses miss it: a node **cannot tell it is partitioned** (no global view),
so it issues a locally-true / globally-false CLEAN. The attack is positive-EV and amortizable
(B always recovers principal via the laundered copy). Stake pricing fails (amortizable, locked
not burned, and the wash-out destroys the evidence a forfeit would need). See
`AXIOM_THREAT_CollusionWipeRevival.md` and the §9 residual in the paper.

The gap is the intersection of three properties AXIOM chooses: **partition tolerance +
no global consensus + provenance-destroying compression.** Compression is the leg that turns a
*heal-able* divergence into a *permanent* laundering.

### 1.1 The wash-out is one symptom of a general disease

The wash-out is the sharpest case, but the *root* — "a node cannot tell whether its view is
global or a partition, so it emits locally-true / globally-false results" — is not specific to
compression. **Every AXIOM double-spend defence implicitly assumes the acting node's view is
representative of the global mesh:**

- the redeem-side **§4.6 asymmetric check** (2-of-3 positive / 1-of-N conflict) assumes the
  receiver's three chosen nodes see the *real* conflict state, not a partitioned subset's;
- **CLEAN vs SCARRED** finalization assumes a positive confirmation reflects global, not local,
  agreement;
- **fork detection / ban propagation** assumes a "no conflict seen" answer came from a mesh that
  *would* have seen the conflict;
- the **maturity window** assumes gossip actually propagated network-wide within it.

Each of these is safe *iff the node's view is healthy*, and unsafe (silently) when it is
eclipsed — the same failure the wash-out exploits. **OODS makes "is my view healthy?" a
first-class, per-transaction, checkable quantity.** So OODS is not only a wash-out fix: it is a
**per-transaction view-health indicator** that hardens *every* defence above by letting a node
weight its own confidence — biasing toward SCARRED / caution when its view is degraded, rather
than emitting a confident-but-globally-false result. This broader role is the intended purpose;
the wash-out is merely the case that forced the mechanism into existence. (Scope/limits of the
broad role: §12.4.)

---

## 2. Core idea

Give every Nabla node a cheap, continuous estimate of **the size of the network it can
actually see**, and make the two dangerous operations — **issuing CLEAN** and **compressing a
FACT chain** — conditional on that estimate being *healthy relative to a trusted baseline*. A
node whose visible network has collapsed (partition / eclipse) refuses to finalize or compress,
so the wash-out cannot proceed and no false CLEAN is issued. The security then reduces to: how
expensive is it to make an eclipsed node *believe* its network is still healthy? OODS's job is
to make that cost proportional to the network size being faked.

Two guarantees are needed and they compose:
- **Detection** (§4): a node knows when its visible network has shrunk hugely.
- **Un-forgeability under cost** (§5): faking a healthy reading costs ≈ a standing bonded pool
  proportional to the faked size.

---

## 3. Prerequisites (all already in AXIOM)

- **TARDIS tick** — a signed unix-second heartbeat that cascades and is validated in transit.
  OODS rides one number on it (§6).
- **NBC** — Nabla Bond Certificates chain to genesis, carry a probation delay (`NBC_ISSUER_
  MATURITY_SECS`, currently 48 h) before a node may contribute/write, and are periodically
  renewed. OODS stamps a baseline into the NBC at issuance/renewal (§7) and derives the
  estimator's per-node draw from the NBC identity (§4–§5).
- **Writer/leaf role** — `is_writer()` already gates SMT writes on TARDIS cascade position
  (`downstream_approvals ≥ 2`); a non-writer's ticks/writes are already rejected
  (`RejectNotWriter`). OODS adds a size clause to writer eligibility (§8).
- **FACT compression** — `is_resolved()` gates which links compress. OODS adds a size gate (§8).
- **Anti-entropy sync** — nodes already diff-sync over *rotating* peers. OODS cross-checks the
  size there (§8, sync).

Nothing here is a new subsystem; OODS extends existing rails.

---

## 4. The estimator — Extrema Propagation (IMPLEMENTED, isolated)

> **Semantics — "estimate" is a *present measurement*, not a forecast.** `N̂` is a *statistical
> measurement of the network's size right now* (a point-in-time reading tied to the current
> tick), **not** a prediction of future size and **not** a value to be stored and compared
> against later. Consumers use the *current* reading against the *current* view (§8.1); nobody
> keeps a stale `N̂` as a baseline. (The word "estimate" is the statistical term for "measure an
> unknown from a sample"; it does not mean "guess the future.")

**Notation.** `N` — true network size; `N̂` — its estimate; `m` — number of extrema channels
(`m = 128`); `P` — an attacker's standing pool of registered identities; `c` — an inflation
factor (`N̂ = c·P`); `P_reg` — the NBC issuer probation delay (§3, ≈48 h); `H` — the seed
predictability horizon; and the epoch triple `(n, E, D)` — epoch index, window length in ticks,
and the fixed seed offset (§5.1.1).

The base technique is **Extrema Propagation** [1]. Each node draws `m` random values; the mesh
gossips the per-channel **minimum**; the network size is recovered from the minima.

- Per node `i`, per channel `j ∈ [0, m)`: a value `x_{i,j} ~ Exp(1)`.
- The minimum of `N` independent `Exp(1)` draws is `Exp(N)`, so `E[min] = 1/N`.
- Gossip propagates the running minimum per channel (monotone → trivial to aggregate).
- Estimate: **`N̂ = m / Σ_j min_j`**, with relative error `≈ 1/√m` (independent of `N`).

`m = 100` gives ~10 % error for `m` floats of state and a tiny gossip payload. Plain Extrema
Propagation is **not adversary-resistant** (it assumes honest draws); the hardening in §5 is
the actual contribution.

Reference implementation: `nabla/src/oods.rs` — `estimate_size()`, `merge_minima()`, unit
tests including a simulated grinding/pool attack (§10, F1). This module is standalone: it
touches no consensus code.

---

## 5. Adversarial hardening — identity-bound draws + un-grindable epoch (THE CLAIM)

Vanilla Extrema Propagation is forgeable at *constant* cost: an attacker grinds keypairs
offline for one tiny hash and injects a small minimum, faking a huge `N̂` with ~1 identity per
channel — cost decoupled from the faked size (external-review finding F1, §10). Two changes fix
this.

**(a) Identity-bound draws.** The draw is derived from the node's NBC identity, not chosen:

```
u_{i,j} = Hash(NBC_pubkey_i ‖ epoch_seed ‖ j) / 2^bits         ∈ (0,1)
x_{i,j} = −ln(u_{i,j})                                          ~ Exp(1)
```

One NBC identity contributes exactly one draw per channel. Injecting arbitrary numbers is
impossible; the only freedom is *which registered identities you advertise*.

**(b) Un-grindable epoch.** `epoch_seed` derives from **recent, unpredictable** mesh data (a
hash of recent TARDIS ticks / SMT roots), so epoch `E`'s seed is unknowable more than a short
horizon `H` before `E`. NBC registration has a probation delay `P_reg` (≈48 h). **Set
`H ≪ P_reg`.**

*Consequence.* To inject a small minimum for epoch `E`, an attacker needs an **already-
registered** (probation-passed) identity whose hash *for E* is tiny — but `E`'s seed was not
known `P_reg` ago when they would have had to begin registering. So they **cannot grind-and-
register for a specific future epoch.** Their only option is a **standing pool** of already-
registered NBCs; the minimum of a pool of `P` fresh draws is `~1/P` *every* epoch. So they can
fake `N̂ ≈ P` and no more, and faking `N̂ = N` requires **~N standing, bonded, probation-passed
NBCs** — i.e. actually being that fraction of the network.

**Claim.** Under un-grindability the minimum *evidences a standing population* (it is no longer
a cheap extreme), restoring pricing proportional to the faked size — "lying costs as much as
being." `m` channels + averaging concentrate the estimate so single-epoch variance does not
sustain a large fake across the attack window.

**Status: the estimator-variance bypass is closed (analytic and empirical).** For `m` i.i.d.
per-channel minima each `~Exp(P)`, the inflation probability reduces to a Gamma tail,
`Pr[N̂ > c·P] = Pr[Gamma(m,1) < m/c]`, which shrinks super-exponentially in `m` (Appendix A;
`≈1.3×10⁻¹²` at `c=2`, `≈4×10⁻⁸⁰` at `c=10`, for `m=128`). The `oods.rs` simulation matches
(zero >10× spikes in 2000 epochs). The single-lucky-epoch fake therefore does not exist at
`m=128`: the minimum evidences a standing population, so faking `N̂ = N` requires `P ≈ N` standing
certs. One caveat carries to the threshold choice (§9): under mass retry, inflation factors
`c ∈ {2, 3, 10}` remain safe but `c = 1.5` does not — a consensus-critical threshold must not sit
near 1.5×. `K`-epoch hysteresis is retained regardless.

The remaining pricing risks are not estimator variance but the epoch seed (§5.1), cert economics
(§5.2), and the timing/liveness surface (§8, §11).

### 5.1 The epoch seed — the new #1 attack surface (seed grinding)

With identity grinding closed, the estimator's remaining cryptographic weakness is **seed
grinding.** Even if the attacker cannot choose *identities* after seeing the seed, they win if
they can choose the *seed* to suit their existing pool. If the attacker can pick among `K`
candidate epoch seeds (by proposing ticks, selectively including ticks, exploiting multiple valid
recent histories, or steering proposer entropy), their success probability at inflation `c`
becomes ≈ `K · Pr[Gamma(m,1) < m/c]` — seed choice multiplies the tail by `K`. A large `K` can
drag `c = 2` or `c = 3` back into reach. **This is the load-bearing cryptographic requirement.**

The epoch seed derivation MUST therefore be:
- **Canonical** — exactly one valid seed per epoch; no local choice among histories.
- **Unbiasable** — no proposer-controlled entropy, no selective tick inclusion; derive from a
  *fixed-offset* committed past tick / SMT root, not "any recent" data.
- **Unpredictable** beyond horizon `H ≪ P_reg` (so identity grinding stays closed).
- **Partition-aware for the sync cross-check only.** The *baseline* comparison (live vs. carried)
  works with any per-epoch seed. But two honest partitions genuinely derive *different* seeds
  from their different recent histories, so their minima are not directly comparable — the §8
  sync cross-check must compare *estimates over a common recent seed both sides can verify*, or
  fall back to "smaller-with-proof" on a seed both hold. Specifying this precisely is open work.

Seed grinding is quantified by the `oods.rs` test `seed_grinding_best_of_k`. Empirical result
(pool = 100, `m = 128`): best-of-`K` inflation is `K=1 → 1.30×`, `K=8 → 1.30×`, `K=64 → 1.34×`,
`K=256 → 1.36×` (the `K=1` figure is the estimator's own upper-tail noise over the trials). At
`m=128` the surface is quantitatively weak for realistic `K`: because the tail is so thin
(`Pr[2×] ≈ 10⁻¹²`), reaching even 2× would need `K ≈ 10¹²` candidate seeds, infeasible to
*propose*. A **canonical seed (`K = 1`) is the requirement**, though a modest seed-choice leak
(dozens to hundreds of candidates) still holds inflation well under the 1.5× line — the
requirement is real, and the mechanism degrades gracefully if it is imperfect.

#### 5.1.1 Canonical epoch-seed derivation

The construction that satisfies all four requirements (canonical, unbiasable, unpredictable
beyond `H ≪ P_reg`, Core-verifiable):

**Epoch.** An OODS epoch is a fixed window of `E` ticks; epoch `n` covers ticks `[n·E,(n+1)·E)`.
`E` sets the estimator's refresh cadence (a wallet gets a fresh reading each epoch).

**Seed = a hash of a fixed-offset *committed* artifact.**
```
epoch_seed(n) = BLAKE3( "AXIOM_OODS_EPOCH_v1" ‖ n_le ‖ A(n) )
```
where `A(n)` is a committed mesh artifact at a **fixed** past tick offset — `A(n)` = the
converged **SMT root** (and/or a **nonce-bound commit-reveal** value, below) committed at tick
`(n·E − D)` for a protocol constant `D`. **Fixed offset ⇒ exactly one valid `A(n)` ⇒ `K = 1`:**
there are no candidate seeds to grind; "any recent tick" (which gives the attacker a menu) is
explicitly forbidden.

**Unbiasability — why a committed artifact, not a proposer's tick.** A bare "hash of the
proposing node's tick" is unacceptable: the proposer grinds its own tick content to steer the
seed. Two acceptable sources, in increasing strength:
- **Converged SMT root** at `(n·E − D)` — reflects *all* registered mesh state; no single node
  controls it. Cheapest.
- **Nonce-bound commit-reveal** — the mechanism already present in the codebase for this exact
  need (peer-audit §23.14.6): contributors commit `H(nonce)` at `t−δ` and reveal `nonce` at `t`,
  so no participant can bias the combined value after seeing others'. Strongest against a
  *tick-influencing* attacker; OODS reuses it rather than introducing a new primitive.

Likely: SMT root as the base; commit-reveal folded in if a tick-influence attack is priced in.

**Predictability vs probation.** `A(n)` is fixed the instant tick `(n·E − D)` lands — i.e. `D`
ticks before epoch `n` begins — so the predictability horizon is `H = D` ticks. Require
`D · TICK_INTERVAL_SECS ≪ P_reg` (48 h). Even `D = 1` closes **identity** grinding: knowing the
seed one tick (≈5 s) early is useless when registering a lucky identity needs the full 48 h
probation (§5). `D > 0` is mandatory — the seed must derive from *past, committed* data, or a
node could pre-position for the current epoch.

**Core-verifiability (the §6 gate).** `epoch_seed(n)` is a deterministic function of `(n, A(n))`.
Core is handed `A(n)` (the committed SMT root / the commit-reveal transcript), **recomputes
`epoch_seed(n)`, and rejects any OODS proof whose seed ≠ the canonical value.** Core needs no
global view — it verifies the seed exactly as it verifies identities (§6, CL6/CL7): by
recomputation from committed inputs against its trust root. A forged/chosen seed fails here.

**Partition handling (the one genuinely open sub-problem).** Under a real partition the two
sides derive `A(n)` from their *own* recent history and may compute *different* `epoch_seed(n)`.
That is fine for the **current-vs-current wallet check** (§8.1) — the wallet compares its view
against the current attested reading *on the seed it holds*. But the §8 **sync cross-check**
across a partition needs both sides on a **common** seed: use the most recent epoch for which
*both* sides can present a committed `A` (an older, mutually-committed seed), or fall back to
"smaller-with-Core-verified-proof" on a shared seed. **Precise cross-partition seed
reconciliation is the remaining open item** — everything else in this derivation is settled.

**Open constants to tune:** `E` (epoch length ↔ refresh rate), `D` (offset ↔ predictability
horizon, `D·TICK ≪ P_reg`), and the `A(n)` source (SMT-root vs commit-reveal vs both). None
change the structure; they are deployment parameters set from measured cadence.

### 5.2 Cert economics — anti-renting and pool amortization (governance, not math)

Two economic limits bound the pricing:
- **Renting.** If NBC/VBC certs can be rented / delegated / leased / pooled, the attacker's cost
  is *rental* of `N` certs, not *ownership* — "lying costs as much as **renting**." So certs
  MUST be **non-transferable**, bond-locked, identity-bound, with anti-delegation limits and a
  reputation/slashing cost for signing into a fake pool. Without this the pricing leaks.
- **Amortization.** One standing pool of `P` is reusable across *many* laundering attempts, so
  OODS prices attack **capacity** (owning `P`), not each individual attack. This is unavoidable
  unless a bond is *risked/burned per compression event* — which is a separate design axis (and
  is exactly what the wash-out defeats via evidence destruction, so per-event forfeit remains
  hard). State this plainly: OODS raises the *fixed* cost of being able to attack; it does not
  charge per attack.

---

## 6. Propagation — ride the TARDIS tick + its cascade agreement

The OODS proof rides the TARDIS tick, and reuses the tick's **existing cascade agreement**
(a tick is writer-approved only with ≥2 downstream approvals, `is_writer`): the same two child
Nabla that must agree on the *time* also **co-sign the OODS payload** before it propagates. This
is the AXIOM-native mechanism — no new gossip protocol — and it composes with §8.1.

**What the proof carries.** Per channel: `{ min_value, achieving_identity }` — the channel
minimum *and the VBC/NBC identity that produced it* — plus the `epoch_seed`. (You reveal only
the one identity that achieved each channel's min, not all N — that is the whole point of
Extrema Propagation.)

**What the cascade agreement buys — and what it does NOT.** Two (or `k`) child Nabla each
recompute the minima from their own view and co-sign only if they *match*, so forging a value
requires `k` **colluding** Nabla to agree, not one — a real forgery-bar increase, and it
distributes the proof for free. **But agreement is NOT trust.** This is the key contrast with
*time*: a tick's *time* is trustworthy because every node independently checks it against its
own NTP clock — an **external anchor**. *Size has no external anchor*, so no amount of Nabla
co-signing makes it *true* (`k` colluders can agree on a lie, and Nabla is untrusted). Agreement
**corroborates and prices**; it does not certify.

**Core is still the trust (why this rotates the CoreID).** For a *decision* (§8), **Core
verifies the carried proof by recomputation**: for each channel it checks `achieving_identity`
is a valid VBC/NBC that **chains to genesis** — **reusing the existing CL6/CL7 VBC/NBC
verification modes** (`core/logic/src/lib.rs`: CL6 verifies VBC bundles against
`ROOT_AUTHORITY_PKS`, CL7 verifies NBC bundles against `NABLA_ROOT_AUTHORITY_PKS`; Core already
runs these, and hosts refuse to start without a valid cert — Lambda `server.rs`, Nabla
`nabla_node.rs` FATAL-exit). OODS does **not** reinvent cert verification; on top of CL6/CL7 it
adds only the extrema recomputation `−ln(Hash(identity ‖ epoch_seed ‖ channel)/2^64) == min_value`
for a **canonical** `epoch_seed` (§5.1). This makes a **fake-small min impossible without
revealing a real genesis-chained identity that produces it** — i.e. you cannot claim a bigger
network than you can back with real bonded certs (the §5 pricing). The tick + cascade is
transport + corroboration; **Core's per-channel-identity recomputation is the trust.**

### 6.1 The boundary rule: "sign" means "through Core"

Core is AXIOM's sole cryptographic authority (`CLAUDE.md` §1), so **"sign" means "through
Core."** A signature produced by Nabla or Lambda directly attests *authorship, not truth*;
relying on it for a security decision breaks that boundary. Every OODS attestation a decision
depends on MUST therefore be **Core-mediated**: the value is bound into a Core execution output
carrying a DMAP/zk attestation, verifiable by any node against the canonical CoreID (the same
mechanism §15 uses so that a validator cannot sign a state Core did not produce). A bare Nabla
signature on an OODS value gates nothing. (The current NBC-Ed25519 tick signature is the
placeholder the code flags — `prev_sig`: "Empty until Core integration provides real
signatures"; Core-mediated tick signing is the intended state, and OODS rides that.)

### 6.2 Two derived readings — OODS-gossip (network size) vs the tick-accumulator reading

The OODS estimator (§4) is applied over two different propagation topologies, producing two
distinct readings. **Do not conflate them** — they measure different things.

- **OODS-gossip = the size of the Nabla network.** Extrema Propagation over the node's
  **verified-NBC mesh view** (`nabla::oods::estimate_from_ids` over `verified_nbcs`). This is
  the forgery-resistant network-size estimate; it drops under a partition/eclipse. It is the
  value carried in the `NablaOodsAttestation` (§8.2) and stamped into `Receipt.oods_flag`.

- **The tick-accumulator reading (field: `tardis_depth`) ≈ a rough estimate of the writer set.**
  The OODS estimate (`oods_verify::oods_estimate`) over the tick's **down-cascade accumulator** —
  the extrema the TARDIS tick collects as it circulates. The fold happens only on the downstream
  path and only at tick-*forwarding* nodes, which are the **Writers**, so the accumulator counts
  writers, not consumers.

  **What it is NOT (correction — 2026-07-08).** An earlier draft of this section called it
  "TARDIS depth" and described it as a node's depth-from-root. **That framing is wrong**, because
  TARDIS has **no root**: the topology is a **closed ring** — every node (including the top
  Writers) has an upstream (`has_upstream() == true` mesh-wide; `new_with_ring_links` wires an
  upstream *and* a downstream at bootstrap, "after bootstrap, this node is identical to any other
  — no special treatment"). With no root there is no well-defined "depth from root." The live env
  confirms it: the values **do not order by tree position** (a consumer leaf can read higher than
  a Writer) and they **cluster below the true writer count** (observed: 2–4 against 5 Writers).

  So the honest characterization is: a **noisy, per-node, *under*-counting estimate of the writer
  set** — bounded by the true writer count and under it, because the down-only fold captures only
  the writers between the current origin and each node before the tick laps the ring. It is
  **low-signal in this form** (per-node variance, undercount) and is retained only as an
  informational demo reading; the field name `tardis_depth` is historical.

  **Why it isn't yet trustworthy — and what fixes it.** Its writers are only *presence*-checked,
  not lineage-verified (the tick's `prev_sig` is carried but not cryptographically verified —
  §6.1 / the deferred grandpa-sig check; see `AXIOM_YPX-003_TARDIS.md §7.6`). Until
  that lands, a hostile node can inflate the accumulator, so the reading is **not** Core-verified
  and gates nothing.

  **Future use (decision-grade).** Once tick lineage is cryptographically verified, the same
  writer-set measure becomes a **hard-to-forge tiebreaker for gossip conflicts** — when two
  branches conflict, favor the one backed by more verified-writer weight (defeats the self-signed
  high-tick roll-back; see `AXIOM_REPORT_KnownIssues.md` on Nabla gossip fork detection).
  Arbitrating a *branch* (vs one node's path) also wants the branch's total writer-weight
  (up-aggregation), deferred with the rest of the decision-grade promotion.

---

## 7. Baseline — inherited through the certificate chain, anchored to genesis

Every non-genesis node is **born with a baseline**: its issuer stamps the current (proven)
network size into the certificate it grants. **Both certificate types carry the OODS number:
NBC (Nabla) and VBC (validator) — except genesis, which is the root and has none.** Validators
carry it too because they also gate on a healthy view (writer-adjacent decisions, CLEAN, and
the compression they witness); the baseline is a network-wide health anchor, not a Nabla-only
one. Certificates chain to genesis, so the baseline inherits that trust chain. To hand a new
node a *fake* baseline you need a colluder **issuer** whose own certificate chains to genesis —
a **genesis-rooted colluder lineage** (deep historical Sybil), not mere current node control.

- At **renewal** (the sanctioned periodic mesh-touch), the baseline is refreshed to the
  node's current proven view. A renewal is refused against an unhealthy view (§8: search,
  don't accept) — the node keeps its prior, higher baseline and searches for a healthy issuer.
- Genesis nodes are baseline-less (they are the root of trust); their baseline is set
  out-of-band at the genesis ceremony. **DEFERRED** — not solved here.
- **Certificate-format change.** Adding the OODS field to VBC + NBC is a wire/format break on
  both certs. It is part of the deferred, CoreID-rotating step (§12) — genesis certs are exempt
  (no field).
- **Baseline is a RANGE, not a scalar.** Stamp `{estimate, confidence interval,
  timestamp, issuer diversity, renewal epoch}`, not a bare number. A scalar false-triggers on
  legitimate size drift between renewals, and a stale low scalar can make a partial eclipse look
  "healthy." The dip test is "live estimate below the baseline's lower band," with the band
  widening as the baseline ages.
- **Issuer scarcity is load-bearing.** Baseline inheritance is only as strong as "how
  hard is it to become an issuer." If issuer status is cheap, an attacker acquires a genesis-
  rooted lineage and stamps fake baselines into nodes born under it (the "born-eclipsed"
  problem in *lineage* form — such nodes never search outward because their fake world matches
  their fake baseline). Issuer status MUST be scarce, bonded, reputation-bearing, and audited.

---

## 8. Response and gates

**On a dip (live estimate ≪ baseline): SEARCH, do not die.** The node does **not** accept the
eclipsed view, does **not** renew against it, and does **not** self-suppress on a peer's mere
*claim*. It stays **fail-closed** (no CLEAN, no write, no renew) and **keeps searching** its
peer set for a node that can *prove* a healthy size (§5). It resumes the instant it finds one.

- A *partial* eclipse is escaped by finding any one honest peer.
- A *transient* outage just reconnects — **no node death, no re-bootstrap** (this replaces an
  earlier "the node dies" design, which was weaponizable: an attacker could assassinate honest
  nodes by eclipsing-at-renewal).
- Discovery must draw from **multiple independent sources** — hardcoded seeds + the
  genesis-rooted NBC issuer chain + gossip'd peers — so a *complete* eclipse means owning the
  whole surface.

**Provable, not claimed (kills the griefing vector).** Everywhere a size is consulted — the
search, the sync cross-check, and the CLEAN/compression gate — it is a **verifiable proof**
(§5), checkable by Core as an input (Core stays networkless). A liar cannot inflate a *claimed*
size to make honest nodes stand down, because standing down requires a *proof* of the larger
size, which requires a real standing pool.

**The three gates**, all triggered by a proven-unhealthy view:
- **No FACT compression** — the double-spend link stays scarred and survives to heal (no
  wash-out). **Freshness rule:** a wash-out is a *cascade* of ~6–8 txs, so a *single*
  healthy epoch proof MUST NOT authorize the whole cascade. Compression requires healthy OODS
  observations **across a window at least as long as the compression path** (multiple ticks /
  `K`-epoch persistence), each bound to the specific FACT checkpoint. This denies the attacker a
  "wait for one favorable epoch, then batch the compression" play.
- **Registrations → SCARRED, not CLEAN** — no false CLEAN under an undetectable partition.
- **Writer eligibility suspended** — extends `is_writer()` with the size clause; a suspended
  writer's writes are already rejected (`RejectNotWriter`).

**Search amplification (liveness note).** Search-on-dip removes the *griefing* vector,
but an attacker can induce many transient dips → many nodes enter search → discovery traffic
spikes → more nodes fail to find proofs → more fail closed. Mitigate: rate-limited search with
exponential backoff, **cached recent healthy proofs** (a node re-uses a still-fresh proof instead
of re-searching), tiered discovery, and a local grace window before gating. OODS converts the
adversary's cheapest attack from *steal/launder* to *stall/degrade-finality* — a real
improvement, but the paper must say so directly (§11).

**Timescales.** The baseline is anchored/refreshed at *renewal* (periodic); the size is
*checked continuously* (per registration / on the tick) against it, because the wash-out
finishes *between* renewals. Renewal enforces the patient/sustained eclipse; the continuous
check catches the fast smash-and-grab.

### 8.1 Recommended enforcement — client-carried, Core-verified OODS confidence

Per §6.1, the trust anchor for an OODS value is Core's recomputation, never a Nabla signature;
enforcement therefore requires a Core change and rotates the CoreID. The wallet-driven flow:

1. **The OODS proof is carried to the wallet** — the per-channel minima + the contributing
   **VBC/NBC identities** + the **epoch seed**. It may ride the TARDIS tick or a Nabla response,
   but *that transport is not the trust* — see (2).
2. **CORE verifies it by RECOMPUTATION** (this is the load-bearing step, and why the CoreID
   rotates). Core, trusting no one, recomputes `N̂` from the presented evidence: it checks each
   contributing identity is a valid VBC/NBC that **chains to genesis** (Core anchors the genesis
   constants), recomputes each identity's draw `−ln(Hash(id ‖ epoch_seed ‖ ch)/2^64)`, confirms
   the presented minima are those draws' minima, verifies the **epoch seed is the canonical one**
   (§5.1 — Core must be able to check the seed independently, not trust the tick signer), and
   emits the attested `N̂`. A forged number fails recomputation; a signature buys nothing.
3. **The wallet checks its view against the CURRENT network-wide reading — NOT a stored
   baseline.** On every Nabla interaction, the wallet receives the *latest*, tick-stamped,
   Core-attested OODS reading of the network's state **at that time** (the "latest odds of the
   time"), and compares its *own* current view against *that current* reading. It does **not**
   keep a high-water baseline and measure drift against it over time.
   *Why this matters:* a wallet can be **dormant for a long time**, and the
   network legitimately **grows or shrinks** meanwhile (e.g. adoption declines → the mesh is
   genuinely smaller). A stored baseline would then false-fire on wake-up — the wallet would
   read "I collapsed from 100 000 to 1 000" and lock itself out, even though it is perfectly
   healthy and just living in a now-smaller network. The correct question is **not** "is the
   network smaller than I remember?" (a prediction about the past/future) but **"is my view
   smaller than the network's *current, attested* state?"** (a point-in-time consistency check).
   Current-vs-current: a dormant wallet in a legitimately-shrunk network sees a small current
   reading *and* a small own-view → they **match** → healthy; it is flagged only when its view
   is smaller than the network's *current* attested reading → eclipse. This makes the value a
   **state-of-the-network-at-tick-T fact, never a forecast or a persistent baseline.**
4. **On a confidence drop, the wallet self-limits: it STOPS compressing its FACT chain** (no
   wash-out) — client-side, no scar, no protocol state change.
5. **It surfaces a visible "this wallet may be out of sync" signal** whose credibility rests on
   the **Core-verified** proof it carries (not a self-claim, not a Nabla signature). Owner,
   validators, and receivers weight CLEAN-vs-SCARRED accordingly (graduated, §12.4). **NOT a
   scar** — an orthogonal, lighter *health* annotation.

Why this is the AXIOM way:
- **Client-driven, network-only-refuses.** The wallet governs its own chain and *carries a
  Core-verified proof* of its view-health.
- **Provable-not-claimed, trust rooted in Core.** Faking "healthy" needs the actual
  identity-bound minima of a real standing population (§5 pricing) *and* they must survive Core's
  recomputation — a Nabla can't sign the lie into truth. This is *why* the un-grindable canonical
  seed (§5.1) and cert economics (§5.2) are load-bearing: Core's recomputation only prices the
  attack if the seed is canonical and the identities are real bonded certs.
- **CoreID rotation is intrinsic.** CLEAN/SCARRED weighting and compression self-limit are
  SDK-side, but the value they trust must be Core-attested, so the Core-verified size proof
  (§5, §12.3) is unavoidable; the SDK and Nabla-wire parts are additive around it.

This flow is graduated and fail-safe (§12.4). Its residual — that a fully-colluding
sender+receiver in a closed loop can ignore their own advisory, so the mechanism *contains*
laundered value from the honest economy rather than seizing it — is the irreducible
consensus-free residual stated once in §11 (R1).

### 8.2 The health flag (concrete enforcement)

A Nabla stamps a health flag onto a wallet's receipt at each transaction. It carries forward
with the wallet's state, so the next validator knows whether the wallet's previous step happened
under a healthy view.

Stored on the receipt:

```
oods_flag = { tick: u64, oods_size: u32, healthy: bool }
```

`tick` — when it was stamped; `oods_size` — the network size the witnessing Nabla saw; `healthy`
— `true` if `oods_size` is in range of the Nabla's NBC baseline (§7), `false` if collapsed
(eclipse / partition).

**Set by Core.** When a Nabla witnesses a transaction, Core reads the Nabla's Core-verified NBC
baseline and its current `oods_size`, sets `healthy`, and binds `{tick, oods_size, healthy}` into
the signed receipt — so an eclipsed Nabla cannot forge `healthy = true`.

**Read on the next transaction.** `healthy = true` → normal (CLEAN eligible); `healthy = false` →
the previous state was set under an eclipse → SCARRED, do not finalize clean. The wash-out is
blocked at point-of-use with one boolean on the receipt chain already in place; the un-fakeable
`oods_size` (§4–§5) is what stops an eclipsed Nabla earning a `true`.

**SHIPPED + deployed 2026-07-03 (Phase 1).** CoreID rotated
`5564323f…` → `a14e13278e4f09f54f13d9e5404f1f810ffd3e45586ca5e06174b3f419f670ae` (a
Receipt-commitment + NBC-format break; clean `--data` on this rollout). Four pieces landed
together (master `93808689`):

1. **NBC/VBC baseline (§7).** `VBC.network_size_baseline` + `baseline_tick`, stamped by the
   issuer from its current proven view at issuance/renewal (`nabla-node` →
   `cc.rs::{issue,renew}_nbc[_via_core]`). Bound into the issuer signatures via a fixed 12-byte
   suffix on `compute_vbc_signing_payload_bytes`, appended ONLY when the baseline is non-zero —
   so genesis / pre-baseline certs keep a byte-identical pre-image and their existing signatures
   stay valid (the §7 genesis exemption).
2. **`Receipt.oods_flag: Option<OodsFlag>`**, bound (presence AND values) into
   `compute_receipt_commitment` — a flag cannot be added, stripped, or flipped after the k
   witnesses sign. No `serde(default)` (clean format break).
3. **Core sets it.** A new `NablaOodsAttestation` (Ed25519 reading + NBC trust anchor + baseline
   suffix binding) is fetched by the SDK per send/redeem over a new `OodsReadingRequest` TCP wire
   op, forwarded verbatim ANTIE→Lambda→Core, and verified by Core CL3/CL5
   (`validation::verify_oods_attestation`) — a **hard reject** (`E_OODS_ATTESTATION_INVALID`) on
   any invalid attestation, never a silent downgrade to "no flag". `healthy = oods_size ·
   OODS_DIP_FACTOR ≥ baseline` (integer; dip factor 3 per §9; `baseline == 0` ⇒ genesis-exempt ⇒
   always healthy). Nabla-side attestation crypto lives in `registration.rs::build_oods_attestation`
   (the sanctioned synchronous-crypto hot-path file).
4. **Next-tx read = wash-out block.** `advance_fact_checkpoint` takes an `oods_view_healthy` arg;
   `false` ⇒ no PROPOSE, no CO-SIGN, no FINALIZE — the chain retains its links exactly like the
   scarred case (§8.1 step 4). Liveness-only: never a fund rejection (§8 search-don't-die).

**Enforcement verified three ways (all GREEN):** core-logic unit tests
(`oods_healthy` boundaries, `verify_oods_attestation` hard-rejects, the checkpoint gate);
two deployed-ELF harnesses run against the live binary —
`nabla/examples/oods_tamper_inject.rs` (a real NBC-anchored attestation fetched from the mesh,
then forged four ways → all rejected, 6/6) and `nabla/examples/oods_eclipse_inject.rs` (a
root-signed baselined attestation with an eclipsed size → Core stamps `healthy = false` in-guest
at the dip-factor-3 boundary, and that flag blocks compression, 6/6); and a **sustained live
adversary** in the soak (`soak_test_v2.py --oods-inject-rate N` corrupts the fetched attestation
on healthy sends) — 4/4 tampered attestations BLOCKED with real
`Lambda error: E_OODS_ATTESTATION_INVALID`, 0 leaked.

**Phase-1 residuals (closed in Phase 2 / CL14):** (a) an honestly-eclipsed Nabla cannot report
`healthy` (it holds a baselined NBC + a collapsed live estimate), but a **malicious** Nabla lying
about its live estimate is only priced once the §5 Core-verified size-proof recomputation is a
required CL14 input — Phase 1 closes the honest-but-eclipsed case; (b) a cert issued WITH a
baseline that claims `baseline_size == 0` skips the suffix check (dev NBCs are baseline-0 by the
genesis exemption, so the whole live dev mesh currently reads healthy — correct, not a stub);
(c) heal / genesis-claim / WASM paths carry a `None` flag (no Nabla reading). Phase 2 (CL14 verify
mode + canonical §5.1 seed source) stays blocked on Core-mediated tick signing (§12.3).

---

### 8.3 OODS as a recovery precondition — it scars, it never blocks

The Nabla-driven recovery operations (HAL YPX-020, HEAL YPX-018, RECALL YPX-022) lean on the
global Nabla SMT consume-once for their double-spend safety — HAL and RECALL relax the S-ABR
overlap outright and rest entirely on it. A wallet acting on an **eclipsed / partitioned** view
may not see a conflicting state, so the consume-once it relies on is only as trustworthy as its
view is healthy. OODS is exactly that signal.

**One dedicated verdict.** Core exposes a single `oods_verdict() → {Safe, Unsafe, Unavailable}`
computed from the same NBC-baseline-anchored attestation §8.2 already carries:
- **Safe** — valid attestation, `healthy` (§9 threshold met).
- **Unsafe** — valid attestation, but the live estimate has collapsed below baseline (eclipse / partition).
- **Unavailable** — no valid attestation to decide from.

One source of truth for "is my view trustworthy?"; every consumer reads it, none re-derives it.

**It scars — it never blocks.** OODS MUST NOT stop a wallet from acting. `oods_verdict()` is a
**tag on the outcome, not a gate on the operation**: an op always runs, and its receipt is
stamped healthy (`Safe`) or **scarred** (`Unsafe` / `Unavailable`). Containment is entirely the
existing §8.2 machinery — a scarred receipt blocks FACT compression/finalization and an honest
counterparty treats it as SCARRED (suspect, not trusted for finality, not washable into the
honest economy). Nothing is rejected; the risk of recovering under an untrusted view is
*contained*, in keeping with OODS's stance throughout — **a price, not a proof of closure.**

The recovery ops inherit this unchanged: HAL / HEAL / RECALL tag their receipts through the same
path. An `Unsafe` view does not fail the recovery — it scars it, and the scar quarantines it
until it can be re-validated under a healthy view. The wallet is always usable; the only thing
traded is **immediacy for cleanliness** (a clean, unscarred recovery wants `Safe`; a scarred one
still works, contained). This also removes any incentive to fake `Unsafe`: there is no recovery
to block, only a scar to add, which the wallet clears by re-validating.

**Faking `Safe` is priced, not free.** A `Safe` tag cannot be cheaply forged: the estimate is
over identity-bound draws (§5), so counterfeiting a healthy view costs a standing pool of real
bonded certificates proportional to the network — the intended cost curve, fully enforced once
the §5 size-proof becomes a required input (§12.3). The scar-based model rests on that pricing.

---

### 8.4 Implementation — `oods_verdict()`, the tag site, and reuse

The recovery precondition (§8.3) is almost entirely reuse. Net-new surface is one thin verdict
function, one per-op tag stamp, and one representation choice for the `Unavailable` state.
Everything else is §8.2 machinery already shipped.

**(1) The verdict — a wrapper, not a new mechanism.** `oods_verdict(attestation) → {Safe, Unsafe,
Unavailable}`:
- **Unavailable** — no attestation, or `verify_oods_attestation` (`validation.rs:396`) rejects it
  (forged / invalid anchor / bad signature). Nothing trustworthy to read.
- **Unsafe** — the attestation verifies, but `oods_healthy(oods_size, baseline)`
  (`validation.rs:372`) is false (the live estimate collapsed below the §9 threshold).
- **Safe** — verifies *and* healthy.

No new crypto, no new estimator: it composes the shipped `verify_oods_attestation` + `oods_healthy`.

**(2) The tag — reuse `Receipt.oods_flag`.** The receipt already carries
`oods_flag: Option<OodsFlag { tick, oods_size, healthy }>`, bound into `compute_receipt_commitment`
(§8.2). Verdict → tag: `Safe` → `Some(healthy = true)`; `Unsafe` → `Some(healthy = false)`;
`Unavailable` → **scarred**.

> **The one behavioural rule — `Unavailable` must scar, not default-healthy.** Normal Phase-1
> flagless receipts (heal / genesis / WASM historically carried `None`) are read *permissively*:
> Lambda's `receipt.oods_flag.map_or(true, |f| f.healthy)` treats a *missing* flag as healthy. A
> recovery op that acted with **no trustworthy reading** MUST NOT inherit that permissive default —
> it must scar. So `Unavailable` on a recovery receipt is stamped scarred *explicitly*
> (`healthy = false` with sentinel `oods_size = 0 / tick = 0`, or a dedicated third flag state),
> never left as a permissive `None`.

**(3) Where it's applied — the recovery ops carry the flag they already receive.** HAL / HEAL /
RECALL already obtain the Nabla attestation on the register ACK (the same fold sends use). Today
they build their receipt with `oods_flag = None`. The change: they call `oods_verdict()` on that
attestation and stamp the resulting tag — going from *flagless* to *OODS-tagged* through the
identical `oods_flag` path a normal send uses. **One tag path, three ops; no per-op OODS logic.**

**(4) Containment — entirely §8.2, already shipped.** A `healthy = false` (scarred) receipt already
blocks FACT compression via `advance_fact_checkpoint(healthy = false)`, and an honest counterparty
already treats a scarred receipt as SCARRED (suspect, not trusted for finality). A scarred recovery
is contained by code that already runs. **No new containment.**

**(5) Never a gate.** `oods_verdict()` is read *only at receipt-build*, to choose the tag — never
to allow or reject an operation. The wallet always acts (§8.3).

**Net-new, in full:** `oods_verdict()` (~15 lines over the two existing helpers); the recovery ops
stamping `flag = verdict()` instead of `None` (a one-liner each at receipt-build); and the
`Unavailable → scarred` representation. The `Safe` tag stays priced, not free (§5, §11 R8) — the
implementation assumes no free-forgery.

---

## 9. Threshold

The dip threshold sits in a **wide valley**: normal churn is single-digit percent, while a real
eclipse (one that isolates a victim) is an *order-of-magnitude* collapse. So the exact number
is not razor-sensitive. Rules:

- **Derive it empirically** from AXIOM's own measured churn, not from first principles. Bonded,
  probation-gated membership makes AXIOM's population *more stable* than free-join P2P
  (cf. Stutzbach & Rejaie, IMC 2006; session times are heavy-tailed with a stable core), so
  thresholds can likely be *tighter* than the P2P literature suggests.
- **Direction caveat.** Under ordinary churn, relative volatility scales `~√(1/N)` — large
  networks are *relatively more stable* and small networks *more volatile*. So a size-adaptive
  threshold most likely wants to be *looser for small N* (noise) — the opposite of a naive
  "tighten for small." For small N there is a genuine security↔noise tension (tight = catch
  eclipses but false-positive on churn); small networks are inherently less protectable.
- **Hysteresis / debounce.** A dip must persist `K` epochs before it gates, so a one-epoch
  blip does not flap (guards against external-review findings F4 (oscillation) and F5
  (denial-of-finality); §10).
- **Security scales with size (stated honestly).** Faking a small early network is cheap; faking
  a large mature one is enormous. OODS's protection *grows with the network*, like hashpower
  security — lean on it less at launch, more at scale. Concretely, the cost to fake a healthy
  view is `≈ N × per-NBC cost` (bond + hardware/pulse + bond locked over the probation window),
  so the economic line is `N × per-NBC-cost > attack payoff`, tuned by the **NBC bond** (currently
  unpriced — R3). Two things bound the small-`N` exposure: **(i)** the primary double-spend
  defenses (S-ABR overlap, k-witnessing, detect-and-ban) do **not** weaken with size, so a small
  network is not undefended — OODS is only the wash-out backstop, not the sole defense; and
  **(ii)** a small network is also a **low-value target**, so the attack incentive is lowest
  exactly where OODS is weakest — a game-theoretic self-mitigation, not a guarantee. The line is
  therefore soft until the NBC bond is priced.
- **Concrete safe zone (from the Gamma tail at m=128).** Inflation factor `c`:
  `c=10` statistically safe; `c=3` extremely safe; `c=2` very safe; **`c=1.5` UNSAFE under mass
  retry** (≈1e-5 per attempt × millions of attempts = real successes). **Do not place a
  consensus-critical threshold near 1.5×.** The "order-of-magnitude drop = eclipse" instinct is
  statistically strong; a subtle 1.5×–2× boundary must not be load-bearing.

---

## 10. External adversarial review — findings and responses

The estimator and its hardening were subjected to two rounds of independent adversarial review
(attributed in Acknowledgements; chronology in Appendix B). The findings, and where §5–§9
answer each, are tabulated below.

| # | Finding | Response |
|---|---|---|
| F1 | "A minimum proves an extreme, not a population" — estimator fakeable at constant cost | §5 un-grindable epoch → forces a standing pool of ~N. **The open question:** does min-variance let a small pool fake large N on one lucky epoch? (§11) |
| F2 | Selective-minimum / precompute / channel-farm / replay | Blocked by unpredictable `epoch_seed` (`H ≪ P_reg`) + probation (§5b) |
| F3 | Sync "smaller stands down" = griefing | §8 provable-not-claimed + search-not-stand-down |
| F4 | Oscillation between honest partitions | §8 search-not-hard-fail + §9 hysteresis + trusted (not per-epoch) baseline |
| F5 | "Everything scars" = cheap denial-of-finality | §8 search (stay alive, keep trying) + §9 hysteresis; trigger needs a *proven* dip |
| F6 | Threshold is tuning, not a theorem | §9 acknowledged; empirical + wide valley + hysteresis make mis-tuning non-catastrophic |
| F7 | Prove *observed diversity*, not *inferred size* | §5 folds this in: a provable "large size" now *requires* a real standing population — the size proof only exists if the participants do |

**Second round.** A re-review against the implemented estimator and the tail math confirmed
F1 is fixed: `Pr[N̂ > c·P] = Pr[Gamma(m,1) < m/c]`, so variance-faking is effectively impossible
at `m=128` (≈10⁻¹² at 2×, ≈10⁻⁸⁰ at 10×), matching the simulation. It also assessed that, under
strong epoch-seed and NBC-economic assumptions, faking `N` costs approximately maintaining `N`
standing certs (the `h`-floor), that the gap is not closed absolutely, and that the residual
cheap attack becomes a liveness/DoS rather than inflation. It surfaced the load-bearing surfaces
now captured in §5.1 (seed grinding), §5.2 (cert economics), §7 (issuer lineage, baseline
range), §8 (compression freshness, search amplification), and §9 (thresholding). These are the
remaining open work items (§12.3).

---

## 11. What OODS does NOT claim (honest residuals)

- **R1 — Not closed, PRICED.** An adversary who genuinely maintains a standing, bonded,
  genesis-reachable pool of ~N nodes can still forge — at the true cost of *being* that much of
  the network. That is the `h` floor; nothing consensus-free gets under it.
- **R2 — Genesis bootstrap deferred.** Baseline-less genesis roots are set at ceremony, not
  solved here.
- **R3 — Contingent on bonded NBCs.** The pricing is real only if NBCs actually cost
  (they are unpriced in the current dev build).
- **R4 — Central variance claim CONFIRMED.** §5's proportional-pricing argument passed
  the adversarial teardown analytically (Gamma tail) and empirically. Faking `N` via estimator
  variance is closed; faking `N̂ = N` requires `P ≈ N` standing certs. This residual is *retired*
  — but note it converts into the surviving surfaces below, not into "solved."
- **R5 — Consensus-class change.** The size proof as a Core-verified input rotates the CoreID
  and needs an adversarial soak; the §8 wiring is mainnet-class, not a patch.
- **R6 — Surviving sub-proportional surfaces, NOT estimator variance:**
  (a) **seed grinding** (§5.1) — the new #1 surface; rests entirely on a canonical, unbiasable
  epoch seed; (b) **cert renting/delegation** (§5.2) — pricing leaks to *rental* cost without
  non-transferable, bonded certs; (c) **pool amortization** (§5.2) — OODS prices attack
  *capacity*, not each attack (unavoidable without per-event bond risk); (d) **weak issuer
  lineage** (§7) — cheap issuer status ⇒ fake baselines; (e) **compression-timing / proof
  freshness** (§8) — a single healthy epoch must not authorize the cascade.
- **R7 — The residual attack is now LIVENESS, not theft.** OODS converts the adversary's
  cheapest move from *steal/launder* into *stall/degrade-finality* (search amplification, seed-
  divergence, regional isolation). That is a real improvement, and the paper must state it as
  such — the class isn't closed; the *cheap* member of it becomes a DoS rather than an
  inflation.
- **R8 — Two distinct claims; do NOT conflate them (a recurring reasoning trap).** Two separate
  properties get muddled, and conflating them produces the false conclusion "OODS is cheaply
  fakeable." Keep them apart:
  - **Claim A — the estimator is expensive to fake** (see R1, R4). Counterfeiting size `N` costs a
    standing pool of ~`N` bonded, un-grindable, genesis-reachable identities. This is a property of
    the *estimator itself* and holds unconditionally: identity-bound draws (§5) + an un-grindable
    epoch seed (§5.1) make "lying costs as much as being that size" a structural fact. Settled.
  - **Claim B — Phase 1 does not yet *recompute* the reading** (see R5, §12.3). The shipped §8.2
    health flag verifies the attestation's *signature* + NBC anchor, but Core does **not yet**
    recompute the per-channel minima against the claiming identities (that is the deferred §5
    size-proof / CL14). So a hostile Nabla can *sign* a false `oods_size` until recompute lands —
    mitigated meanwhile by client cross-check and by the scar-not-block containment (§8.3, a
    scarred reading is contained regardless of forgery).
  These are **not in tension**: **A** is *whether* the estimate can be forged (expensively — no);
  **B** is *when Core enforces* that cost (fully at Phase 2). "A hostile Nabla can sign a false
  reading in Phase 1" (B) is **not** "faking the network size is cheap" (¬A). The estimator's
  pricing is settled; only the *enforcement timing* is phased. Reasoning that slides from B to ¬A
  is the specific error to avoid.

---

## 12. Implementation surface, verification evidence & deferred work

### 12.1 The detection layer (read-only, CoreID-neutral)

- **Estimator** (`nabla/src/oods.rs`): Extrema Propagation (`N̂ = m/Σ minⱼ`, `m = 128`),
  identity-bound draws `x = −ln(Hash(id ‖ epoch_seed ‖ ch)/2^64)`.
- **Live telemetry**: every Nabla node computes a live `oods_estimate` (in `NodeStatusSnapshot`,
  serialized into the status/dashboard JSON) from its mesh view.
- **NBC anchoring** (§5.2): the production `nabla-node` binary feeds the estimator the keys of
  `verified_nbcs` — only cryptographically-verified, bonded NBCs count, so gossip noise / an
  unverified Sybil does not inflate the reading.
- **Dashboard**: a "Network Size (OODS)" row on the per-node cockpit, beside the naive
  Sybil-forgeable "Network Size (est.)".

### 12.1b The §8.2 health-flag enforcement gate (shipped, CoreID-rotating)

Full implementation surface + the four pieces are documented at §8.2. Enforcement is
verified three ways, all GREEN:

| Vehicle | Demonstrates |
|---|---|
| core-logic unit tests (`validation::tests::ypx021_*`, `fact::tests::ypx021_*`) | `oods_healthy` boundary math; `verify_oods_attestation` hard-rejects a forged sig / re-paired baseline / missing anchor; `advance_fact_checkpoint(false)` makes no compression progress. |
| `nabla/examples/oods_tamper_inject.rs` (deployed ELF) | Fetches a REAL NBC-anchored attestation from the live mesh, runs a CL3 send through `core/artifacts/axiom-core.elf` via the RV32IM VM: pristine → accept + flag stamped; four tampers → all `OodsAttestationInvalid`. **6/6.** |
| `nabla/examples/oods_eclipse_inject.rs` (deployed ELF) | Mints a valid baselined attestation (NBC signed by the real `NABLA_ROOT_1` ceremony key) with an eclipsed size → Core stamps `healthy = false` in-guest exactly at the dip-factor-3 boundary; that flag then blocks `advance_fact_checkpoint`. **6/6.** |
| `soak_test_v2.py --oods-inject-rate N` (sustained live adversary) | On 1-in-N healthy sends, corrupts the SDK-fetched attestation; the live validators' Core hard-rejects every one (`Lambda error: E_OODS_ATTESTATION_INVALID`). 3w/8m run: **4/4 blocked, 0 leaked.** |

**Still Phase-2 (below):** the §5 Core-verified size-PROOF as a required CL14 input — the piece
that prices a *lying* (vs honestly-eclipsed) Nabla. Phase 1 makes the flag un-forgeable and the
honest-eclipse case enforced; Phase 2 makes the *estimate itself* un-fakeable.

### 12.2 Test roster (all GREEN, Mac + Linux)

| Test | Demonstrates |
|---|---|
| `estimate_tracks_true_size` | `N̂ ≈ N` within the error band for N=10…10 000. |
| `more_channels_tighter` / `merge_is_order_independent` | 1/√M accuracy; gossip merge is a commutative-idempotent monoid (order/dup-independent). |
| `standing_pool_cannot_exceed_its_own_size` *(heavy)* | A colluder pool of P estimates ≈ P, no runaway — the empirical "lying costs as much as being". |
| `single_epoch_spike_probability_is_bounded` *(heavy)* | 2000 epochs, pool=100: **zero** single-epoch estimates > 10× — the variance-fake does not exist at m=128 (matches Appendix A). |
| `seed_grinding_best_of_k` *(heavy)* | Best-of-K seeds: K=1→1.30×, K=256→1.36× — seed grinding is weak at m=128 (§5.1); reaching 2× needs K≈8×10¹¹. |
| `epoch_reshuffles_the_minimum` | An unpredictable epoch seed reshuffles the minimum-holder → forces a standing pool, not one ground identity. |
| `partition_detection_end_to_end` | 30-node view → ~30; a 5-node partition view → ~5; dip ratio ~0.17 — detection works. |
| `washout_eclipse_detected_and_evasion_is_priced` | **OODS vs the initial gap**: an 8-node colluder eclipse vs a 200-node baseline is a ~0.04 dip (DETECTED); evading it needs ~N verified certs (PRICED). |
| `dynamic_network_churn_vs_eclipse` | **Production dynamism**: 50 epochs of churn (membership rotation + ±15% size) keeps the worst dip > 0.5, while an eclipse hits < 0.15 — >3× separation, so a threshold in the valley discriminates churn from attack. |

*(Heavy statistical tests are `#[ignore]`-by-default — run:
`cargo test -p axiom-nabla oods -- --ignored --nocapture`. Fast tests run in CI.)*

**What the roster establishes:** detection catches the exact eclipse the wash-out needs;
faking/hiding the network size is priced at ~N verified NBCs (analytic Appendix A + empirical);
and the churn-vs-eclipse discrimination is wide enough to be usable in a dynamic mesh. **What it
does NOT establish:** the real mainnet churn *magnitude* (unmeasured until a live network — set
the threshold from measured volatility, §9), and end-to-end *blocking* of the wash-out (needs
the deferred gate, below).

### 12.3 Deferred — the §5 Core-verified size PROOF (Phase 2 / CL14, mainnet-class)

> The §8.2 health-flag half of the gate is SHIPPED (§12.1b). What remains deferred is the
> §5 size-proof-as-required-input — the half that prices a *lying* Nabla. Do not build
> until the two open surfaces below are specified:

1. **Canonical, unbiasable epoch seed** (§5.1) — the new #1 requirement; specify the
   fixed-offset committed-tick derivation + `K≈1`.
2. **Cert economics** (§5.2) — non-transferable, bonded VBC/NBC.

Then, and only then, behind an adversarial soak:
3. Ride the minima on the TARDIS tick (§6); baseline-as-range stamped into VBC/NBC at
   issuance/renewal (§7); the size clause on `is_writer()` + the FACT-compression gate +
   CLEAN/SCARRED gate (§8); and the **Core-verified size proof** as a required input (§5) —
   this is the step that rotates the CoreID. The gate is what turns the (working, tested)
   *detector* into an *enforcer* — the detector must remain read-only until then.

### 12.4 Broader role — a per-transaction view-health indicator (design intent, deferred)

Per §1.1, OODS's value is not limited to compression: it is a per-transaction confidence signal
that hardens *every* double-spend defence. The intended integration, once the gate lands:

- **Graduated, fail-safe — NOT a hard binary gate everywhere.** OODS should *bias* decisions
  toward caution under a degraded view: a positive §4.6 result taken as **SCARRED instead of
  CLEAN** when `oods_estimate ≪ baseline`; a redeem confidence weighted by view-health; a
  compression refused (the §8 hard case). Making it a *soft* indicator (uncertainty → more
  conservative) is fail-safe: a mis-read makes the node *more* cautious, never less. A hard
  binary gate on the per-tx path would instead turn any false-positive into a per-tx liveness
  failure — do not do that.
- **Cost is trivial per-tx.** The estimate is a cached read (recomputed on the periodic
  status/mesh-update cadence, not per transaction), so putting it on the hot path is a field
  read, not a recompute.
- **The stakes of tuning rise.** As a *per-tx* indicator the threshold/hysteresis (§9) now
  affects *every* transaction's CLEAN/SCARRED, not just compression — so it MUST be calibrated
  from measured mainnet churn and carry hysteresis, and the graduated (soft) form above is what
  keeps a mis-tuning non-catastrophic (extra SCARREDs, not blocked transactions).
- **Same residuals, broader blast radius.** The honest-fraction floor, the canonical-seed
  requirement (§5.1), and cert economics (§5.2) now matter for the whole tx path, not just the
  wash-out. This raises the bar for shipping the gate, but the *upside* is that a single,
  cheap, NBC-anchored signal strengthens the entire double-spend surface at once.

**Status: design intent, deferred.** The per-tx indicator is the same CoreID-rotating gate
work (§12.3) applied more broadly; it does not change what's built today (read-only detection)
or what's owed first (canonical seed + cert economics + soak).

---

## Appendix A — Estimator tail analysis

The load-bearing pricing claim (§5) rests on this closed-form tail bound. It is the reason that
faking `N` via estimator variance is not a viable attack at `m = 128`.

**Setup.** An attacker holds a standing pool of `P` registered identities. Per channel `j`, each
identity draws `x ~ Exp(1)` (the identity-bound `−ln(u)` of §5). The attacker's advertised
per-channel value is the minimum over its `P` identities:

```
min_j = min over P i.i.d. Exp(1)  =  Exp(P)          (min of P rate-1 exponentials is rate-P)
```

The estimator sums the `m` channel minima and inverts:

```
S   = Σ_{j=1..m} min_j   ~  Gamma(shape = m, rate = P)     (sum of m i.i.d. Exp(P))
N̂  = m / S
```

**Inflation event.** The attacker fakes a network `c×` larger than its true pool when
`N̂ > c·P`. Substitute and normalise with `Y = P·S`:

```
N̂ > c·P
⟺  m / S > c·P
⟺  S < m / (c·P)
⟺  P·S < m / c
⟺  Y < m / c ,     where   Y = P·S ~ Gamma(shape = m, rate = 1)
```

The pool size `P` cancels — the inflation *factor's* probability depends only on `m` and `c`:

```
Pr[ N̂ > c·P ]  =  Pr[ Gamma(m, 1) < m / c ]              (★)
```

This is the regularised lower incomplete gamma function `Q = P(m, m/c)` (a.k.a. the CDF of a
`Gamma(m,1)` at `m/c`). It is the probability that a sum of `m` unit-mean exponentials lands a
factor `c` below its mean `m` — a large-deviation event that shrinks super-exponentially in `m`.

**Values at m = 128:**

| inflation `c` | `Pr[N̂ > c·P]` = `Pr[Gamma(128,1) < 128/c]` |
|---|---|
| 1.5× | ≈ 1.0 × 10⁻⁵ |
| 2×   | ≈ 1.3 × 10⁻¹² |
| 3×   | ≈ 5.1 × 10⁻²⁶ |
| 5×   | ≈ 4.4 × 10⁻⁴⁷ |
| 10×  | ≈ 4.2 × 10⁻⁸⁰ |

**Cross-check vs simulation.** Expected count of >10× single-epoch spikes in the 2000-epoch
`single_epoch_spike_probability_is_bounded` test: `2000 × 4.2e-80 ≈ 8.4e-77` → observing **zero**
is exactly predicted. The analytic bound and the simulation agree.

**Mass-retry (many epochs × many victims).** A determined attacker retries; success over
`A` independent attempts is `≈ 1 − (1−p)^A ≈ A·p` for small `p`:

```
c = 2   :  p ≈ 1.3e-12  → even A = 1e9 gives ≈ 0.0013 expected successes   (safe)
c = 1.5 :  p ≈ 1.0e-5   → A = 1e6 gives ≈ 10 expected successes            (UNSAFE)
```

**Consequence for thresholds (§9).** `c ∈ {10, 3, 2}` are statistically safe even under mass
retry; **`c = 1.5` is not.** A consensus-critical gate MUST trigger on an order-of-magnitude
drop, never on a subtle 1.5×–2× boundary.

**Seed grinding (§5.1) interaction.** Choosing the best of `K` candidate epoch seeds multiplies
(★) by ≈ `K`: `Pr[fake c×] ≈ K · Pr[Gamma(m,1) < m/c]`. To reach `c = 2` an attacker needs
`K ≈ 1/1.3e-12 ≈ 8e11` proposable seeds — infeasible — which is *why* the empirical
`seed_grinding_best_of_k` test shows only ~1.36× at K = 256. A canonical seed (`K = 1`) is the
requirement; the thin tail makes a modest leak survivable.

**Why m matters.** Relative estimator error is `≈ 1/√m`, but the *adversarial* tail (★) shrinks
`≈ exp(−m · d(1/c))` for a rate function `d`, i.e. **super-exponentially in `m`.** Larger `m`
buys disproportionate adversarial robustness for linear state/bandwidth cost. `m = 128` puts 2×
faking at `≈10⁻¹²`; `m = 256` would put it near `≈10⁻²⁴`. This is the single most important
estimator parameter.

---

## References

[1] C. Baquero, P. S. Almeida, R. Menezes, and P. Jesus. "Extrema Propagation: Fast Distributed
Estimation of Sums and Network Sizes." *IEEE Transactions on Parallel and Distributed Systems*,
23(4):668–675, 2012.

[2] D. Stutzbach and R. Rejaie. "Understanding Churn in Peer-to-Peer Networks." *Proc. 6th ACM
SIGCOMM Conference on Internet Measurement (IMC '06)*, 189–202, 2006.

---

## Acknowledgements

The mechanism was designed by the AXIOM author. The estimator and its adversarial hardening
were developed with AI assistance (Anthropic Claude) and subjected to independent adversarial
review (OpenAI ChatGPT) across two rounds; the findings and responses are recorded in §10 and
the chronology in Appendix B. Review provenance is included for completeness and does not bear
on the technical argument, which stands on §5, §9, and Appendix A.

---

## Appendix B — Design History

This appendix preserves the engineering chronology; it is non-normative.

- **Round 1 (external adversarial review).** Findings F1–F7 (§10) identified constant-cost
  forgeability of vanilla Extrema Propagation (F1), selective-minimum/precompute/replay variants
  (F2), the sync griefing vector (F3), inter-partition oscillation (F4), cheap denial-of-finality
  (F5), the empirical (not first-principles) nature of the threshold (F6), and the
  diversity-vs-size distinction (F7). §5–§9 were written in response.
- **Round 2 (external adversarial review).** A re-review against the implemented estimator
  confirmed F1 was fixed by the Gamma-tail argument (Appendix A) and surfaced the next-order
  surfaces: seed grinding (§5.1), cert economics (§5.2), issuer lineage and the baseline range
  (§7), compression freshness and search amplification (§8), and threshold placement (§9).
- **Trust-model correction.** An early draft of §8.1 proposed trusting a Nabla-signed estimate;
  this was corrected to the Core-verified model of §6.1 (a Nabla signature attests authorship,
  not truth), which is why enforcement rotates the CoreID.
- **Baseline semantics correction.** An early draft compared a wallet's live view against a
  stored high-water baseline; this was corrected to the current-vs-current model of §8.1 (a
  stored baseline false-fires when the network legitimately shrinks under a dormant wallet).

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
