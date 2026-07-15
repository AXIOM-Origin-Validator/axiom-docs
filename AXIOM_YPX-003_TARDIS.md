**AXIOM Yellow Paper Extension YPX-003**
## TARDIS Cascade Protocol

**Official Title:** Temporal Anchor for Rollback Detection and Integrity Sync — Cascade Heartbeat Protocol
**Project:** AXIOM (TrustMesh Architecture)
**Type:** Yellow Paper Extension (Phase 2)
**Version:** 0.9.2 (Consolidated)
**Date:** 2026-04-27
**Authors:** AXIOM Origin
**Depends On:** Yellow Paper v2.6.0+ (Phase 1), YPX-002 (Nabla Verification Protocol)
**Required By:** YPX-001 (FACT Chain — tick field in FACT links)
**Supersedes:** YPX-001 Section 2 (TARDIS), AXIOM_SECURITY_RESEARCH Section 5 (TARDIS designs 1-5, meta-validator concept)

> **Note:** This document consolidates TARDIS v0.6 through v0.9 into a single reference. All errata from v0.9 have been applied inline.

---

## 0. Purpose

TARDIS provides three functions for the AXIOM TrustMesh:

```
1. HEARTBEAT:     Forces Nabla nodes to gossip and reconcile on a rhythm
2. LIVENESS:      Proves a Nabla node is alive, current, and trustworthy
3. ANTI-TAMPER:   Prevents Nabla nodes from faking registration timestamps
```

TARDIS does NOT directly prevent double-spend. That is Nabla's job (YPX-002). TARDIS ensures Nabla can do its job by shrinking the gossip propagation window and providing verifiable temporal ordering.

### 0.1 Why TARDIS Exists

Without TARDIS, the following attack is possible:

```
Alice double-spends:
  TX₁ → registers with Nabla node N1 (Tokyo)
  TX₂ → registers with Nabla node N2 (London)

  N1 and N2 haven't gossiped yet.
  Both accept. Both think they're first.

  Alice gives cheque₁ to Bob, cheque₂ to Charlie.
  Bob checks N1 → clean ✓
  Charlie checks N2 → clean ✓

  By the time N1 and N2 gossip... too late.
```

The attack window is the gossip propagation delay between Nabla nodes. TARDIS shrinks this window by:

1. Forcing all Nabla nodes to reconcile at every tick boundary
2. Requiring a maturity window before cheques can be redeemed as CLEAN
3. Providing verifiable timestamps that Nabla nodes cannot fake

### 0.2 What TARDIS Is NOT

```
TARDIS is NOT:
  - A global clock or wall-clock time source
  - A meta-validator rotation engine (removed from design)
  - A consensus mechanism
  - A double-spend prevention system (that's Nabla)
  - A system validators participate in (TARDIS is Nabla-only)
  - A consumer of gossip-distributed peer metadata
    (TARDIS decides chain attachment from TARDIS-internal
    signal only — see §1.7. Cross-contamination renders
    Nabla nodes unusable.)

TARDIS IS:
  - A cascading signature heartbeat inside the Nabla network
  - A liveness proof for Nabla nodes
  - A temporal anchor for Nabla registrations
  - A gossip synchronization mechanism for non-TARDIS state
    (gossip carries who exists and where to reach them;
    TARDIS chain attachment decisions never read it)
```

### 0.3 Design Evolution

TARDIS evolved through several designs before reaching the current cascade model. Each previous design was rejected for specific reasons documented in AXIOM_SECURITY_RESEARCH_VBC_FACT_TARDIS.md Section 5:

| Design | Concept | Rejection Reason |
|--------|---------|------------------|
| Design 1 | Continuous tick / clock | Who produces tick without central server? |
| Design 2 | Gossip-based (Hashgraph) | Requires persistent real-time connections |
| Design 3 | Genesis as time source | Genesis must stay alive forever |
| Design 4 | Vertical attestation up VBC tree | Easy to capture entire branch |
| Design 5 | ZK proof as time cost | No global chain to compare against |
| Design 6 | Meta-validator rotation | Moves corruption one step away, doesn't solve it |

The cascade design (this document) solves these problems by:
- No central server needed after first tick (Design 1 solved)
- Works over standard internet connections (Design 2 solved)
- Genesis seeds retire naturally (Design 3 solved)
- Trust is horizontal, not vertical (Design 4 solved)
- Time advances by cascade propagation, not computation (Design 5 solved)
- No meta-validators needed (Design 6 eliminated entirely)

One principle from the earliest sketch (YPX-001 §2, the genesis-tick design)
survived every redesign and remains the reason tick divergence is safe:

> **Ticks provide ORDERING, not SYNCHRONIZATION.** Ticks are not global
> state — they are values embedded in FACT links; each wallet's FACT chain
> carries its own sequence. During a partition, each side keeps ticking and
> tick values may diverge. That is not a vulnerability: if a wallet transacts
> in BOTH partitions, its FACT chains conflict → double-spend → BANNED. Tick
> desync does not cause "merge chaos" — conflicting state_ids do, and
> conflicting state_ids are exactly what Nabla detects (§9 partition healing).

---

### 0.4 Layer Boundary — Headline Rule

> **TARDIS attach decisions consume TARDIS-internal signal only.
> Gossip-distributed peer metadata MUST NOT inform any attach
> decision. Crossing this boundary renders Nabla nodes unusable.**

The detailed rule, allowed/forbidden inputs, failure mode, and
the proper E → P → D discovery primitive are normative and
specified in §1.7 below. Every TARDIS picker implementation
MUST satisfy §1.7 to be spec-conforming.

---


### 0.5 Relationship to the neighboring specs

**YPX-001 (FACT):** YPX-001 Section 2 (the early TARDIS sketch) is superseded by
this document; YPX-001 Section 1 (FACT Chain) remains valid and references TARDIS
ticks as defined here — the `tick` field in FACT links uses these ticks.

**YPX-002 (Nabla):** YPX-002 defines the wallet state registration and verification
protocol. TARDIS (this document) defines the heartbeat that ensures Nabla gossip is
timely and Nabla node liveness is verifiable. TARDIS lives INSIDE the Nabla
network — every Nabla node is a TARDIS cascade participant.

---

## 1. Cascade Topology

### 1.1 Node Slots

Every Nabla node maintains exactly five connection slots:

```
UP:   Upstream parent (receives ticks from)          — exactly 1
D1:   Downstream child 1 (sends ticks to)            — 0 or 1
D2:   Downstream child 2 (sends ticks to)            — 0 or 1
P:    Pending node (receives ticks, seeking D slot)   — 0 or 1
E:    Enquiry slot (connect, query, disconnect)       — stateless
```

Properties:
- UP is the authority — ticks flow DOWN from UP
- D1 and D2 APPROVE the tick (downstream approval makes ticks legitimate)
- P receives ticks and works normally but is seeking a permanent D slot
- E is stateless — new nodes connect, receive network topology info, disconnect

### 1.2 Tick Legitimacy

A tick is legitimate ONLY when downstream nodes approve it. This prevents upstream nodes from faking ticks.

```
Tick production flow:

1. Node A generates its own tick from unix time
2. A sends tick to D1, D2, P
3. D1 validates: tick ≤ D1's clock, age ≤ 5s, not future
4. D1 signs approval → sends back to A
5. D2 validates and signs approval → sends back to A
6. A now has: tick + sig_A + approval_D1 + approval_D2
7. This is a LEGITIMATE tick (requires BOTH D1 AND D2)

Without D1 and D2 approval, A's tick is just A's claim.
Leaf nodes (no downstream) receive and verify ticks but cannot produce legitimate ticks.
```

#### 1.2.1 Writer and Reader Tiers

In a binary tree (fan-out 2: D1+D2), at most 50% of nodes can have 2 children. This is a geometric invariant — no tree reorganization can exceed it. Therefore:

**WRITER nodes (~50%):** Have D1+D2 approval AND have approved their upstream's tick within the current interval → LEGITIMATE ticks → can record transactions with proven timestamps.

**READER nodes (~50%):** Leaf nodes that receive ticks from parent but cannot produce LEGITIMATE ticks. Readers serve enquiry responses (balance lookups, state queries) using their parent's approved tick as a freshness proof:

```
Enquiry response from a READER node:
  root_hash:    [SMT root — current wallet state]
  as_of_tick:   1740163800
  tick_proof:   parent's tick + D1 signature + D2 signature
  my_ack:       reader's signature acknowledging receipt
```

The receiver verifies tick_proof independently. A malicious reader cannot fake freshness because it cannot forge the parent's D1+D2 signatures.

##### Per-tick write qualification (NORMATIVE)

Write authority is **per-tick**, not permanent. A node qualifies as WRITE at tick `T` if and only if **all three** conditions hold during the interval `[T, T+TICK_INTERVAL)`:

```
WRITE_QUALIFIED(N, T) ≜
    1. downstream_count(N) == 2          (both D1 and D2 slots filled)
AND 2. has_upstream(N) == true           (N has an attached parent)
AND 3. N has approved a tick from its upstream during interval T
       (i.e., N's process_tick(parent_tick) returned Ok within T)
```

Qualification **expires at `T+1`** and must be re-established each interval. A node that loses any one of the three conditions stops being a WRITER the moment its qualification expires — it has no fresh proof that it is structurally in the mesh AND being approved from above.

`downstream_count == 2` is enforced **exactly**, not as `>= 2`. The slot manager (`add_downstream`) structurally rejects a 3rd child — `dc > 2` is unreachable by code path — so the check is precisely "both slots full." A node observed with `dc > 2` indicates a slot-manager defect, not a protocol-allowed state, and MUST be treated as not-write-qualified.

##### Why this rule is what it is

The three conditions encode three independent properties the network requires of every writer:

| Condition | What it proves |
|---|---|
| `dc == 2` | The node is **chosen by the network** — two peers below have actively selected it as parent. No central authority makes this decision; it's organic and bilateral. |
| `has_upstream` | The node is **anchored in the mesh** — not an isolated subtree of one. Required because writers must continue seeking upper link (§1.2). A writer without upstream is a candidate writer still searching; it does not yet have authority. |
| approved-parent's-tick-this-interval | The node is **currently in the consensus chain** — has fresh proof its upstream is alive and producing legitimate ticks. Prevents a writer that was qualified an hour ago but has since lost contact from continuing to claim authority. |

A writer that meets all three has earned its authority from the structure itself — children approve it (`dc==2` D1+D2 approvals), the chain reaches it (has_upstream), and the chain is alive (recent tick approved). No additional approval is needed; **no central authority grants writer status**.

##### Sender routing — dynamic, not static

A sender connecting to a node MUST be redirected to a known WRITE-QUALIFIED node if the target is not currently write-qualified:

1. Sender connects to any Nabla node.
2. The Nabla evaluates `WRITE_QUALIFIED(self, current_tick)`.
3. If qualified → record transaction immediately.
4. If not qualified → redirect to a known write-qualified peer (parent, or gossip-known).
5. Sender connects to that peer → record transaction.

This is a **dynamic** check at the moment of receiving the registration — not a static configuration flag. An operator-only `reader_only` deployment flag MAY additionally force redirect, but the qualification check is the protocol-correct path.

Through mesh gossip and §2.2 slot availability, every node knows multiple write-qualified peers. Maximum one extra hop.

Writer/Reader is not a permanent role — it transitions per-interval based on the three conditions above. As new nodes join below, a node gains children and (with upstream + fresh tick) becomes a WRITER. As children leave or die, or upstream stalls, a WRITER drops back to READER. The roles rotate naturally with network state — no scheduled rotation interval is required for the qualification mechanism to work, though §2.4 separately addresses anti-ossification rotation.

##### Validator Lambda ↔ Nabla connection pattern (INFORMATIVE)

A validator's Lambda needs to query a Nabla for several admin operations (DWP query, withdrawal mint witness collection, wallet state lookup). When it does, it makes an outbound call to a Nabla — either its local co-located Nabla (the default in dev) or a configured remote Nabla in production.

**Architectural intent:** a validator's Lambda *should ideally* connect to a Reader-mode Nabla rather than a Writer. Two reasons:

1. **Separation of concerns.** A Writer is the consensus-active surface — it accepts `/register` from SDK clients and signs ticks via D1+D2. A validator's Lambda is the operator surface — it issues VBCs, performs audits, runs withdrawal mints. Co-locating these on the same Nabla means one node carries both consensus-write authority and validator-host duties, which couples two responsibilities that the rest of the protocol treats as independent.
2. **Failure-mode isolation.** If the validator-host Nabla is also a Writer, then a fault on the validator host (Lambda hang, admin DoS, operator reconfig) co-causes loss of a Writer slot in the mesh. Decoupling them means a single host failure costs at most one role.

**Current policy:** the protocol accepts Lambda connecting to either a Writer or a Reader Nabla. There is no protocol-level rejection. In dev colocation (the canonical 10-penguin setup), every Nabla is co-located with a Lambda, so by construction the rule cannot be enforced — TARDIS election will elect roughly 50% of those Nablas as Writers, and each of those is co-located with a Lambda. This is acceptable for dev; production deployments are expected to use separate hosts for Writer-eligible Nablas vs. validator-host Nablas.

**Future enforcement (deferred):** an operator-only `reader_only` deployment flag for nabla-node would make a Nabla decline Writer qualification regardless of `dc==2 + has_upstream + fresh_tick`. The TARDIS election would re-flow around such nodes. This flag is mentioned in the §"Sender routing" subsection above as an existing concept; the wiring is not yet implemented. When implemented, validator-host Nablas in production should set it.

**Dashboard signal:** the per-validator dashboard (`console/src/static/index.html`) surfaces the connected Nabla's TARDIS slot in the Nabla card. Writer is shown as `WRITER` on an `info` pill (interesting state — currently signing ticks); D0/D1/D2 are shown as `READER (D0)` etc. on an `ok` pill (rule-aligned). Orphan is shown as `ORPHAN` on a `warn` pill (degraded — no upstream, the only state that's actually a problem). No pill is marked as a violation because the protocol accepts both connection targets.

### 1.3 Tick Timing and the Forward-Only Ratchet

#### 1.3.1 Design Philosophy: No One Left Behind

TARDIS does NOT seek accurate time synchronization. TARDIS forces every Nabla node's time to move FORWARD. No node can claim a past time. No node can fall behind.

```
TARDIS is NOT:
  - An accurate clock (NTP does that)
  - A consensus on "what time is it?" (irrelevant)

TARDIS IS:
  - A forward-only ratchet
  - A guarantee that every node is current
  - A proof that no node is stuck in the past
```

Why this matters: If a node can claim an old timestamp, it can backdate registrations and create the appearance that a double-spend came first. By forcing all nodes forward, TARDIS ensures Nabla registrations happen in real-time with no backdating possible.

#### 1.3.2 Reference Time Servers

Every Nabla node SHOULD synchronize its system clock via NTP using the following
servers in priority order. These are Stratum 1 and Stratum 2 sources operated
by national metrology institutes and major infrastructure providers:

```
server time.nist.gov iburst        # US — NIST (National Institute of Standards)
server time.cloudflare.com iburst  # Global — Cloudflare (anycast)
server time.google.com iburst      # Global — Google (leap smear)
server ptbtime1.ptb.de iburst      # Germany — PTB (Physikalisch-Technische Bundesanstalt)
server ntp1.npl.co.uk iburst       # UK — NPL (National Physical Laboratory)
server ntp.nict.jp iburst          # Japan — NICT (National Institute of ICT)
server ntp.bipm.org iburst         # France — BIPM (Bureau International des Poids et Mesures)
server time.apple.com iburst       # Global — Apple
server time.facebook.com iburst    # Global — Meta
server pool.ntp.org iburst         # Global — NTP Pool Project (fallback)
```

TARDIS does NOT require sub-millisecond accuracy. The 0-5 second validation
window is deliberately generous. NTP typically achieves < 100ms accuracy, which
is more than sufficient. The list above provides geographic diversity and
redundancy — if any single time source is unavailable, the others maintain sync.

Nabla operators SHOULD configure their system NTP client (chrony, ntpd, or
systemd-timesyncd) with these servers. The Nabla binary itself reads system
time via standard Unix clock calls — it does NOT implement its own NTP client.

#### 1.3.3 Tick Number IS Unix Time

The tick number is NOT a sequential counter. It IS Unix time in seconds.

```
tick.number = Unix timestamp (seconds since epoch)

Example:
  Tick at 2026-02-21 19:30:05 UTC → tick.number = 1740163805
  Next tick 5s later               → tick.number = 1740163810
```

This means every node can independently verify the tick against its own local clock. No need to track "what tick number are we on" — just look at the clock.

#### 1.3.4 Tick Bounds — Asymmetric by Design (NORMATIVE)

When a downstream node `D` receives a tick from upstream `A`, the bounds are checked with **two independent comparisons against two different oracles**:

```
Downstream D receives tick from upstream A:

  forward bound (uses wall clock — only on the + side):
    REJECT if tick.number > now_secs + TICK_INTERVAL_SECS    (more than 5s in the future)

  backward bound (uses tick-time — never wall clock):
    REJECT if tick.number < D.current_tick                   (going backward)
```

**Wall clock is allowed in AXIOM in exactly two places: tick generation (origin) and this forward-side verification (`+5s`). Nothing else uses wall clock.** The backward bound uses `current_tick` (the receiver's accumulated tick state, advanced by previously-accepted ticks) so the comparison is purely in tick-time. Equality (`tick.number == D.current_tick`) is accepted — the very first tick on a fresh node (where `current_tick == 0`) passes cleanly.

##### Why the bounds are asymmetric

The asymmetry directly implements the design philosophy ("time is moving forward"). Each bound has a distinct purpose:

```
Forward bound (tick.number ≤ now + 5s, wall clock):
  A node whose clock drifts FORWARD claims too-future ticks.
  Children at the bound see "future" → reject → ejected from writer pool.
  Result: bad clocks (running fast) self-eject. No central
  authority decides who has a "good clock" — the network discovers it
  by construction.

Backward bound (tick.number ≥ current_tick, tick-time):
  A node whose clock drifts BACKWARD claims older ticks than the chain
  has already advanced past. The receiver's `current_tick` already
  moved forward via prior accepted ticks; a regression is impossible.
  Result: bad clocks (running slow / replays / actual rollback attacks)
  self-eject — their ticks fall below `current_tick` and are silently
  dropped.
```

##### Why there is no wall-clock "stale" check on the past side

A previous design (pre-2026-05-28) compared `now_secs - tick.number > TICK_INTERVAL_SECS` and rejected as stale. **This was wrong** — it used wall clock on the past side, violating the "wall clock only on the `+` side" rule. The proper backward-bound is the tick-time check above: replay defense lives in the monotonic `current_tick` advance, not in a wall-clock staleness window.

Three benefits of removing the wall-clock past-side check:

1. **No spurious rejections** from `now_secs` lagging behind `tick.number` (e.g. the receiver's local "now" sample was taken N seconds ago — a parent tick generated more recently appears "future" relative to that stale sample).
2. **Replay defense is stronger**, not weaker — a replayed tick can only succeed if `tick.number > D.current_tick`, which means it would have to be from the FUTURE of the chain (impossible if the original tick was already processed).
3. **The wall-clock surface stays minimal** — exactly the two intended uses, no others.

##### Tick from the future (forward-bound rejection rationale)

```
Upstream creates tick at time T.
Network delivers it (latency > 0).
Downstream receives at T + latency.

A tick claiming tick.number > now_secs + 5 means:
  - Upstream's clock is running > 5s fast (badly out of sync), OR
  - Upstream is malicious (crafting future ticks to game maturity windows,
    forge cheque ordering, or backdate cancellations).

Either way: REJECT. The 5-second buffer absorbs realistic clock skew
(NTP achieves < 100ms on healthy nodes; 5s is generous). Anything past
that is presumed malicious or critically misconfigured.
```

##### Tick from before current_tick (backward-bound rejection rationale)

```
A node has accumulated current_tick = T from its prior chain history.
Any subsequent tick claiming tick.number < T means:
  - This is a replay of an old tick, OR
  - The sender's chain has regressed (impossible in honest operation), OR
  - The sender is colluding with downstream nodes to fork their history.

Either way: REJECT. The current_tick value is THE consensus anchor —
it represents "the latest moment we have proof of." Going below it would
mean accepting a chain that contradicts our own accumulated history.
```

The asymmetry is the entire mechanism: **forward drift gets rejected by the wall-clock gate, backward drift gets rejected by the tick-time gate. Either kind of bad clock self-ejects. No clock-quality authority needed.**

#### 1.3.5 Approval Verification (Complete)

```
D receives tick from A:
  1. Is A my upstream? (identity match against D's stored UP slot)
  2. Bounds:
     a. tick.number ≤ now_secs + TICK_INTERVAL_SECS  (forward bound, wall clock — only here)
     b. tick.number ≥ D.current_tick                 (backward bound, tick-time)
  3. Is A's Ed25519 signature valid against the NBC-anchored verification key?
     (authenticity — see §1.3.5a)
  4. If all YES → D signs approval, sends back to A; D.current_tick = tick.number
  5. If NO → D drops the tick (silent — no broadcast of "bad actor" since this
     could be honest network noise; only persistent failures elevate to mesh-wide
     alert)
```

The mesh-wide alert path (a `QuestionableAlert` cascaded down the subtree below
a suspect upstream) is specified in `AXIOM_GUIDE_Nabla.md` §5.5. **The cascade
re-forward MUST be hardened** — signature-verify against the reporter's
NBC-anchored key, a freshness bound, dedup, a self-forward guard, and a
per-reporter rate limit — else one alert loops forever on a transiently-cyclic
(thrashing) tree and becomes a mesh-wide CPU storm. That was the KI#37 root
cause (misfiled all of 2026-07 as a "load-triggered perf regression" and as the
KI#37b "retained mixed-domain state"); see `AXIOM_GUIDE_Nabla.md` §5.5.1–§5.5.2
and `AXIOM_REPORT_KnownIssues.md` #37b. Nabla also runs a type-agnostic outbound
storm circuit breaker as a backstop that never sheds tick-authority messages.

Note: pre-v0.2 used sequential ticks (`tick = last + 1`). The protocol uses Unix-time ticks (§1.3.3); a node that misses a tick simply accepts the next valid one — no gap tracking needed. Pre-2026-05-28, step 2 used a symmetric `0 ≤ (now - tick.number) ≤ 5` window; corrected to the asymmetric rule above (§1.3.4 — wall clock only on `+` side, tick-time on `−` side).

#### 1.3.5a Tick Signature Verification — NBC-Anchored

A receiver verifies the tick's Ed25519 signature using the verification key extracted from the **sender's NBC** — NOT from any field in the tick itself.

```
Receiver D's verification path:

  1. Extract sender's node_id from tick.upstream_pk.
     (Note: upstream_pk == node_id == BLAKE3(sphincs_pk).
      It is a 32-byte hash, NOT a curve point. Cannot be used as
      an Ed25519 public key directly.)

  2. Look up the sender's NBC in D's verified_nbcs map.
     (D rejected the tick at the recv loop if the NBC isn't present.)

  3. Extract the sender's Ed25519 PK from the NBC:
       sender_ed25519_pk = nbc.subject_pubkey_ed25519
     This is the verification key established at NBC issuance time,
     cryptographically bound to the sender's identity by the NBC chain
     back to a genesis-known issuer.

  4. Verify the tick signature (over the COMMITMENT — §7.6):
       Ed25519.verify(sender_ed25519_pk, tick_commitment(tick), tick.signature)
  5. Verify tick LINEAGE (§7.6): reconstruct the grandparent's commitment from
     `gp_commitment` and verify `prev_sig` against the grandparent's NBC key, plus
     freshness (|drift| ≤ 3) and strict-parent (sender ∈ gp.child_pks). Reject on failure.
```

The NBC chain serves as the **identity ↔ key binding** that lets receivers know which Ed25519 PK to trust for which `node_id`. A node cannot substitute a different Ed25519 key without breaking the NBC chain — and the NBC chain is verified at NBC accept time (separate path), long before any tick from that peer is processed.

The tick itself does NOT carry the verification key. Putting the key in the tick would be trust-on-first-byte (anyone could claim to be `node_id = X` by signing with their own key and asserting `tick.signer_pk = their_key`). The NBC binding closes this hole.

**Implementation note (KI#18 fix history):** pre-2026-05-28, the verifier passed `tick.upstream_pk` (the BLAKE3 hash) directly to `Ed25519.verify` as the public key. Since a BLAKE3 hash is almost never a valid Ed25519 curve point, every verify failed — silently, because the failure path returned `Ok(TardisAction::None)` rather than `Err`. The net effect: TARDIS rotation never fired (KI#18 root cause). Verification was decorative. The NBC-anchored path described above is the correction.

#### 1.3.6 Transaction Completion Target

```
TARGET:  5 ticks  = 25 seconds (normal completion)
MAXIMUM: 7 ticks  = 35 seconds (under network stress)

Transaction lifecycle:
  Tick 0:  Alice spends → k=3 validators witness → registers with Nabla
  Tick 1:  Gossip propagation begins
  Tick 2:  Most Nabla nodes have the registration
  Tick 3:  Full propagation across network
  Tick 4:  Any conflicts detected and flagged
  Tick 5:  MATURITY — cheque eligible for CLEAN     ← TARGET
  Tick 6:  Safety margin for large/stressed networks
  Tick 7:  Hard ceiling for dynamic maturity         ← MAXIMUM

If a transaction cannot achieve CLEAN within 7 ticks (35 seconds),
something is wrong with the network, not the transaction.
```

This target drives TARDIS tick interval selection: 5 seconds per tick balances propagation time (tree cascade completes in ~2s even for 1M nodes) against user experience (25–35 second verification is acceptable for real-world payments — see §4.5).

### 1.4 Seed Layer (Network Bootstrap)

The network starts with 10 genesis nodes that form a ring. Genesis nodes form a ring because they launch simultaneously and are the only nodes present. Each connects to the next as D1 and the previous as UP: G0→G1→G2→...→G9→G0. Each node approves the previous node's tick through the standard process_tick validation — no special handling. Once public nodes join, the ring is indistinguishable from any other section of the tree.

```
GENESIS RING (tick 0):

G0: UP:G9   D1:G1   D2:(open)   P:(open)   E:(open)
G1: UP:G0   D1:G2   D2:(open)   P:(open)   E:(open)
G2: UP:G1   D1:G3   D2:(open)   P:(open)   E:(open)
...
G9: UP:G8   D1:G0   D2:(open)   P:(open)   E:(open)

Tick flow: G0 → G1 → G2 → ... → G9 → G0 (circular ring)
Each node approves the previous node's tick through standard process_tick validation.
```

Genesis nodes:
- Are operated by the project founder during bootstrap (Years 1-3)
- ALL 10 genesis nodes are regular Nabla nodes
- Form the initial topology
- Participate indefinitely as regular nodes, may go offline at any time like any other node
- If a genesis node dies, its slots are freed by standard orphan recovery — same as any other node
- The tree continues to function without any specific node — genesis or otherwise
- NO quorum logic — seeds just kickstart; the tree is self-sustaining

### 1.5 Public Node Joining

After the 10 genesis nodes form the ring, public nodes join through the standard E → P → D flow:

```
Step 1: First public nodes fill genesis D2 slots

N1:  Enquires G0 → D2 open → connects as G0.D2
N2:  Enquires G1 → D2 open → connects as G1.D2
...
N10: Enquires G9 → D2 open → connects as G9.D2

G0: UP:G9  D1:G1  D2:N1   P:(open)  E:(open)
G1: UP:G0  D1:G2  D2:N2   P:(open)  E:(open)
...

Step 2: More nodes join below first public nodes

N11: Enquires N1 → D1 open → connects as N1.D1
N12: Enquires N1 → D2 open → connects as N1.D2
...

Step 3: Tree grows naturally via E → P → D migrations
```

### 1.6 Tick-Producing Capacity After Bootstrap

```
After 10 genesis nodes form ring + 10 public nodes join as D2:

Genesis nodes with BOTH D1+D2 (LEGITIMATE ticks):
  G0: D1=G1(ring), D2=N1(public)     ✅ LEGITIMATE
  G1: D1=G2(ring), D2=N2(public)     ✅ LEGITIMATE
  ...
  G9: D1=G0(ring), D2=N10(public)    ✅ LEGITIMATE

Public nodes (leaf — no downstream yet):
  N1-N10: no D1, no D2               ❌ READER (enquiry only)

IMPORTANT: A node needs BOTH D1 AND D2 approvals for WRITER status.
  - 2 approvals = WRITER ✅  (LEGITIMATE tick, can record transactions)
  - 1 approval  = PARTIAL ⚠  (insufficient — tick is just a claim)
  - 0 approvals = READER 📖  (serves enquiries using parent's approved tick)

Once more public nodes join below N1-N10:
  N11 → N1.D1, N12 → N1.D2
  N1 now has D1+D2 → WRITER ✅
  N1 can produce approved ticks and record transactions.

STEADY STATE: In a binary tree (fan-out 2), at most 50% of nodes can
have 2 children. This is a geometric invariant. Therefore:
  ~50% WRITERS (record transactions with LEGITIMATE ticks)
  ~50% READERS (serve enquiries, redirect senders to WRITERs)
  100% SYNC (all nodes receive ticks and maintain current state)

This is correct and healthy — not a deficiency. READERS are essential
infrastructure: they serve enquiries, reduce load on WRITERs, and become
WRITERs when new nodes join below them.
```

---

### 1.7 Layer Boundary — Gossip vs TARDIS (NORMATIVE)

TARDIS attach decisions MUST be made from TARDIS-internal signal
only. Gossip-distributed peer metadata MUST NOT inform the choice
of who to attach to, who to refuse, or who to detach from.
Discovery (knowing a peer's network address) is fine through
gossip. Decisions (chain attachment, accept/reject, parent
selection) are not.

#### 1.7.1 Allowed vs forbidden inputs

```
ALLOWED — TARDIS-internal signal:
  • Ticks received and signature-verified locally (signature over
    tick_commitment; §7.6)
  • A CRYPTOGRAPHICALLY-VERIFIED grandpa-sig on those ticks — prev_sig
    is verified against the grandparent's NBC key over its reconstructed
    commitment, plus freshness + strict-parent (§7.6). (Historically this
    was a presence-only check; §7.6 made it a real verification.)
  • Recovery candidates piggybacked on signed ticks (§2.2)
  • Referrals returned by a node we just queried directly
  • Our own d1/d2/up/pending state
  • NBC verification of an inbound TardisAttachRequest
  • An attach response we ourselves received (accept / reject
    + referrals)

FORBIDDEN — gossip-distributed claim:
  • peer.tardis_up read from PeerInfo (gossip)
  • peer.has_d_open / peer.open_slots from PeerInfo (gossip)
  • mesh.available_slots populated from
    Gossip(Topology(SlotAvailable))
  • Any "looks healthy in gossip so attach to them" heuristic
  • Any multi-hop chain-validity check that walks gossip's
    declared topology
```

#### 1.7.2 Why this is normative

Gossip is eventually consistent. The propagation delay between
"node X dies" and "every peer's gossip table no longer lists X
as tardis_up=Some(...)" is tens of seconds. During that window,
gossip-trusting attach decisions:

1. Choose dead-but-gossiped peers as parents → attach silently
   fails (no response, no error) → orphan re-picks → lands on
   another stale claim → cascade.

2. Once cascading, the picker reads gossip about peers that are
   *themselves* re-orphaning. Their declared `tardis_up` lags
   their actual state, so any multi-hop chain-validity check
   (e.g. "candidate's grandparent must also be attached")
   passes for entries that have already collapsed. The orphan
   cannot identify a viable parent. The mesh writer count
   monotonically decreases until manual intervention.

This is not theoretical. The 2026-05-29 development soak
exhibited exactly this failure mode (see §2.4.7). A 2-hop
gossip filter added as a fix made the cascade worse by
doubling down on the layer crossing.

#### 1.7.3 The proper discovery primitive

The orphan-recovery path is **E → P → D** (§2.1). The orphan
sends `TardisAttachRequest` directly to a peer. The peer
decides accept/reject from its own TARDIS state (own d/p
slots, own grandpa-tick verification, own NBC checks). On
reject, the peer answers with **referrals** built from its
TARDIS-internal children (BFS down its own subtree — not from
gossip about anyone else's topology).

Discovery propagates honestly:
- Dead peers don't respond at all → orphan times out and tries
  another known peer.
- Live peers in a broken chain refuse based on their own
  TARDIS observation (their grandpa-tick check is failing) →
  orphan learns this from a real signal, not a stale claim.
- Live peers with capacity accept → attach succeeds → orphan
  begins receiving ticks → exits orphan state.

Gossip is used here only as the contact-list source: "who do I
know exists, by address". That is its legitimate role.

#### 1.7.4 Consequence of crossing the boundary

A Nabla node whose picker consults gossip-declared chain state
enters cycles where every chosen parent fails grandpa-tick
within `GRANDPA_MISS_DETACH_THRESHOLD` ticks. The node never
holds an upstream long enough to participate in tick
production. To other peers it appears intermittent: NBC valid,
listening port open, occasional gossip presence, but never
approving a tick chain. It cannot serve as a Nabla writer; it
cannot temporally certify wallets via cascade; it accumulates
orphan-recovery state without progress. Other peers begin
detaching from *their* parents because partial chain
participation propagates.

**Treat any code path that crosses the gossip → TARDIS
boundary as a node-killing bug.** Spec-conformance reviews
MUST grep the picker, the rotation picker, the introduction
handler, and any orphan-recovery branch for the forbidden
fields above. A passing review is one where none of those
fields appear in any TARDIS attach decision.

---

## 2. Node Lifecycle

### 2.1 Joining the Network

New nodes follow the E → P → D path:

```
1. ENQUIRY: New node Z connects to any known node as E
   - Receives: slot availability for this node and its subtree
   - Available D slots, available P slots, tree depth info
   - Z disconnects immediately (E is stateless)

2. PENDING: Z connects to a node with available P slot
   - Z receives ticks from its host (fully functional)
   - Z listens for D slot openings in tick broadcasts
   - Z is NOT degraded — it participates in the network

3. DOWNSTREAM: Z sees an available D slot elsewhere
   - Z disconnects P from current host
   - Z connects as D to the node with the opening
   - Z is now a permanent tree member with own D1, D2, P, E slots

4. TICK PRODUCER: Another node connects to Z as D
   - Z now has downstream → Z can produce approved ticks
```

### 2.2 Slot Availability Propagation

Every tick broadcast includes slot availability information:

```
Tick message from A to D1, D2, P:
{
  tick:         uint64,         // current tick number
  signature:    bytes,          // A's signature over tick_commitment(tick) — §7.6
  prev_sig:     bytes,          // UP's signature over UP's commitment (chain proof, §7.6)
  child_pks:    [node_id],      // A's downstream set — bound into the commitment (strict-parent, §7.6)
  gp_commitment: {              // the grandparent's (=UP's) commitment fields, so a child can
    number, timestamp_ms,       //   recompute UP's commitment and cryptographically verify prev_sig
    payload, downstream_approvals,
    prev_sig, child_pks, oods_hash,
  },                            // None on a self-originated / bootstrap tick (no upstream lineage)
  slot_info: {
    d1_status:  "full" | "available" | "reserved",
    d2_status:  "full" | "available" | "reserved",
    p_status:   "full" | "available",
    subtree_d_available:  uint32,   // total D slots open in subtree
    subtree_p_available:  uint32,   // total P slots open in subtree
  }
}
```

Each node aggregates slot info from both D1 and D2 subtrees. An E enquiry at any node reveals the availability picture for that node's entire subtree. An E enquiry near the root reveals near-complete network availability.

**Normative:** slot availability rides on TICKS (signed, chain-verified) and on direct E-enquiry responses (live round-trip with the answering node). It MUST NOT be sourced from gossip-distributed `Gossip(Topology(SlotAvailable))` broadcasts when making attach decisions. The wire may carry such hints for monitoring and dashboard purposes, but the TARDIS picker MUST NOT consume them — see §1.7.

### 2.3 D Slot Reservation (Offline Tolerance)

When a D node goes offline, its slot is RESERVED for X ticks:

```
D node goes offline:
  Tick 100:     D last seen (missed tick approval)
  Tick 100+X:   Reservation expires

  During reservation (X ticks):
    D slot marked "reserved" — not given to P nodes
    D can rejoin and resume immediately at its old position
    Announced as "reserved" in slot_info

  After reservation expires:
    D slot marked "available"
    First eligible P node migrates in
```

Recommended X = 10 ticks (50 seconds at 5s/tick). Long enough for brief network hiccups, short enough that dead nodes don't block the tree permanently.

### 2.4 Tree Rotation (Anti-Ossification)

Two complementary mechanisms prevent the TARDIS tree from calcifying into fixed positions. Both use only local state — no global knowledge required. All decision logic lives in the protocol layer (tardis.rs), never in the simulator or network layer.

#### 2.4.1 Parent-Side: Drop Slowest Child (every 24 hours)

Every 24 hours (PARENT_ROTATION_INTERVAL), a writer (dc=2 node) evaluates its two children and drops the one with more approval misses:

```
Every PARENT_ROTATION_INTERVAL + jitter ticks:
  1. Am I a writer? (have D1 and D2)  → if no, skip
  2. Have either child missed approvals? → if both perfect, skip
  3. Drop child with more misses
  4. Dropped child becomes orphan → recovered by orphan recovery next tick
  5. Reset miss counters, reset rotation timer
```

The node tracks `d1_misses` and `d2_misses` locally, incremented each tick a child fails to approve. This provides a performance-based eviction: slow or unreliable children get rotated out naturally.

**Constants:**
- `PARENT_ROTATION_INTERVAL_TICKS = 17280` (24h at 5s/tick). Testing: 50.
- `PARENT_ROTATION_JITTER_TICKS = 1440` (~2h). Testing: 20.

**Single-child ghost cleanup (v2.11.15-beta10 escape hatch).** The interval-based rotation above requires **both** d1 and d2 filled before it fires. This left a pathological scenario where a node with `{d1 = ghost child, d2 = None}` would forward ticks to the ghost forever, because:
- The non-responsive child kept `d1_misses` climbing
- `wants_drop_slow_child` returned `None` every tick because `d2.is_none()`
- No other cleanup path watches `d1_misses`

Discovered in the 2026-04-13 soak: three parents spammed 6,500+ rejected ticks at three single-child ghosts over three hours. The receiver side correctly dropped the ticks (TARDIS clock unaffected), but the mesh wasted bandwidth and the ghost slots stayed permanently occupied, blocking real child attachments.

**Fix:** `wants_drop_slow_child` now also checks, before the interval-gated rotation:

```rust
const GHOST_CHILD_MISS_THRESHOLD: u32 = 10; // ~50s of misses

if self.d1.is_some() && self.d2.is_none() && self.d1_misses >= GHOST_CHILD_MISS_THRESHOLD {
    // drop d1 immediately — no interval required
}
// symmetric for d2
```

The ghost is dropped after ~50 seconds of missed approvals without interval gating. A real child that catches up within 10 ticks is unaffected (its miss counter resets on the next approval).

**Why the threshold is 10 misses (~50s) rather than the full 24h interval:** single-child ghosts are a *bootstrap failure mode*, not a *performance-tuning decision*. The regular 24h rotation is for picking between two working children based on relative performance; the 50s threshold is for recognizing that a single child was never really there.

#### 2.4.2 Writer-Side: Voluntary Disassembly (every 72 hours)

Every 72 hours (CHILD_ROTATION_INTERVAL), a writer voluntarily disassembles — releasing its children, then detaching from its parent. All three nodes become orphans and scatter into recovery:

```
Every CHILD_ROTATION_INTERVAL + jitter ticks:
  1. Am I a writer? (dc=2)             → if no, skip (leaves don't rotate)
  2. Do I have a parent?               → if no, skip (can't detach from nonexistent parent)
  3. Am I off cooldown?                → if no, skip
  4. Release children (they become orphans)
  5. Detach from parent (I become orphan)
  6. Set rebalance cooldown
  7. All orphans recovered by orphan recovery next tick
```

**Why writers only:** Leaves rotating would be a no-op — they'd just detach and reattach as a leaf somewhere else. Nothing structural changes. When a WRITER rotates, its released children scatter into recovery and land on dc=1 nodes (via pass-0 preference), turning those nodes into writers. This is the mechanism that prevents leaves from being permanent leaves.

**Constants:**
- `CHILD_ROTATION_INTERVAL_TICKS = 51840` (72h at 5s/tick). Testing: 150.
- `CHILD_ROTATION_JITTER_TICKS = 14400` (~120min). Testing: 20.

#### 2.4.3 Per-Node Jitter (Preventing Synchronized Rotation)

Without jitter, all nodes that joined around the same time hit their rotation interval simultaneously, causing mass disassembly and temporary network instability.

Each node derives deterministic jitter from its own public key:

```
jitter(max) = PK_bytes[0..8] XOR-folded into u64 → mod max

Effective interval = BASE_INTERVAL + jitter(JITTER_MAX)
```

Properties:
- **Deterministic:** Same node always gets same jitter. No extra state.
- **Unique:** Different PKs produce different jitter values.
- **Local:** No coordination or global knowledge needed.

With 50 nodes and jitter=20 ticks: rotations spread across 20 ticks instead of all firing on the same tick. At most 2-3 nodes rotate per tick.

#### 2.4.4 Why These Intervals

No direct academic study exists for binary approval tree rotation intervals. Closest analogues from distributed systems research:

- Ethereum sync committees rotate every ~27 hours (256 epochs × 6.4 min)
- Solana epochs (leader schedule recomputation) last 2-3 days
- libp2p GossipSub mesh heartbeat is 1s, peer TTL is 60s, explicit peer reconnect is 300 ticks

These are different problems (block proposal rotation vs mesh peer management), but the 24h/72h values fall in the same order of magnitude as Ethereum's committee rotation. The key constraint is: rotation interval >> recovery time. Since orphan recovery takes 1-2 ticks (5-10 seconds), even 1-hour rotation would work. 24h/72h provides massive safety margin and minimal churn.

This is a deliberate design choice, documented here as such.

#### 2.4.5 Rotation Rate Mathematics — the "spray rate"

The **spray rate** quantifies how fast writer identity diffuses
across the eligible population: the rate at which a given node's
expected writer-time approaches the population mean. The model
is a two-state continuous-time Markov chain per node, plus a
mesh-coupling argument for the spread mixing-time.

**Symbols.**

| Symbol | Meaning |
|---|---|
| `N` | number of Nabla nodes |
| `W̄` | average writer count (≈ N/2 by §1.2.1) |
| `T_C` | `CHILD_ROTATION_INTERVAL_TICKS` |
| `T_P` | `PARENT_ROTATION_INTERVAL_TICKS` |
| `p` | equilibrium P[node = writer] = `W̄ / N` |
| `τ_node` | per-node mixing time (state-flip timescale) |
| `τ_spread` | mesh-spread mixing time (max − min decay timescale) |

**Step 1 — mesh-wide event rate.** Only writers can initiate
child rotation; parent rotation also fires from writers when
conditioned on d1/d2 misses. The mesh-wide rate of
rotation-driven D-slot reshuffles is:

```
R = R_child + R_parent_eff
  = W̄/T_C  +  (W̄/T_P) · p_miss              [events / tick]

with 1 tick = 5 seconds (§1.3.3).
```

Each event sheds one writer (the rotator drops to dc < 2) and
admits one new writer (a released child re-attaches at a dc = 1
peer, lifting that peer to dc = 2). At equilibrium the
populations are balanced, so out- and in-transitions occur at
equal rates.

**Step 2 — per-node two-state CTMC.**

```
                    λ_RW = R / (N − W̄)
                    ─────────────────→
        ┌──────────┐                 ┌──────────┐
        │  Reader  │                 │  Writer  │
        │  P = 1−p │                 │  P = p   │
        └──────────┘                 └──────────┘
                    ←─────────────────
                    λ_WR = R / W̄
```

Equilibrium check:  `p = λ_RW / (λ_RW + λ_WR) = W̄/N`  ✓.

Per-node mixing time (1/e decay of any initial offset from
equilibrium):

```
                  1                T_C · W̄ · (N − W̄)
τ_node  =  ─────────────────  =  ──────────────────────  ticks
           λ_RW + λ_WR             W̄ · N             (child-only R)
```

When `W̄ ≈ N/2` this reduces to a clean closed form:

```
τ_node  ≈  T_C · (N − W̄) / N
        ≈  T_C / 2                  (W̄ ≈ N/2)
```

For testing constants — `T_C = 600 ticks = 3000 sec = 50 min`,
1 tick = 5 sec — the child-only prediction is:

```
τ_node  ≈  T_C / 2  ≈  1500 sec  ≈  25 min
```

Parent rotation adds a second term to `R`. Empirically the
mesh-wide event rate measured during the 4 h soak was
50 events / h, which corresponds to an effective `T_C` of:

```
T_C_eff  =  W̄ / R_observed
        =  4.7 / (50/3600)         ≈  338 sec  ≈  5.6 min
```

so `τ_node_eff ≈ T_C_eff / 2 ≈ 170 sec ≈ 2.8 min`. Both numbers
(25 min spec-only, 2.8 min observed effective) are used below
as bookends.

**Step 3 — mesh-spread mixing time.** The spread (max − min
writer-time across nodes) is the range of `N` independent
Bernoulli time-averages. Extreme-value statistics for the
maximum of `N` near-Gaussian samples scales as `σ · √(2 ln N)`,
so the spread relaxes to zero on the order:

```
τ_spread  ≈  τ_node · ln N
```

For `N = 10`, `ln N ≈ 2.3`:

```
τ_spread(spec-only)      ≈  25 min · 2.3   ≈  58 min     ≈  1 h
τ_spread(observed R_eff) ≈  2.8 min · 2.3  ≈  6.4 min
```

**Predicted spread decay (uniform-rotation model, spec-only `R`):**

```
Predicted spread vs time   ─ uniform-rotation model, τ = 58 min
  pp
 100 +*
     |  *
  80 +     *
     |        *
  60 +            *
     |                *
  40 +                    *
     |                          *
  20 +                                  *
     |                                            *
  10 +- - - - - - - - - - - - - - - - - - - - - - - - -[target]
     |                                                    *
   0 +-----+-----+-----+-----+-----+-----+-----+-----+----> t  (h)
     0    0.5   1.0   1.5   2.0   2.5   3.0   3.5  4.0
     model predicts spread ≤ 10 pp by  ≈ 2.2 h
```

**Step 4 — measured 4-hour soak (2026-05-29).**

```
Measured spread vs time during 4 h soak — testing constants
  pp
 100 +    *  1h: 95.8
     |
  90 +              *  2h: 91.8
     |
  80 +
     |
  70 +
     |
  60 +                          *  3h: 61.7  <-- eta unlocked
     |                                  '.
  50 +                                       *  4h: 48.2
     |                                          '...
  40 +                                              '...
     |                                                  '.. best-fit
  30 +                                                       exp:
     |                                                        τ = 4.4 h
  20 +                                                            '.
     |                                                              '..
  10 +- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -[target]
     |                                                                   '
   0 +-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+----> t (h)
     0     1     2     3     4     5     6     7     8     9    10
                                              measured τ_spread ≈ 4.4 h
                                              vs predicted ≈ 1 h
```

Fit: `Spread(t) = 117 pp · exp(−t / 4.4 h)` (R² ≈ 0.91 on the
four data points; the 1 h → 2 h plateau drives the residual).

**The 4.3× gap.** Spec-only model predicts `τ_spread ≈ 61 min`.
Measured `τ_spread ≈ 4.4 h = 264 min`. (The observed-R model
predicts `≈ 6.9 min`, giving a 38× gap — even more dramatic.)
Either bookend points to the same conclusion: the discrepancy
is not noise — it is structural and explains exactly what the
4 h sample shows:

```
Per-node writer-time at t = 4 h
                                                       expected
node     0%   10%   20%   30%   40%   50%   60%   70%  envelope
         |    |     |     |     |     |     |     |    36%–58%
eta      |+++++++++++++++++++++++++++++++++++.....| 68.7%
theta    |+++++++++++++++++++++++++++++++.......  | 63.1%
iota     |+++++++++++++++++++++++++++++++.......  | 62.3%
gamma    |++++++++++++++++++++++++++++.........   | 54.2%
alpha    |+++++++++++++++++++++++++++..........   | 53.0%
kappa    |+++++++++++++++++++++++++++..........   | 53.0%
delta    |++++++++++++++++++++++++++...........   | 50.3%
beta     |+++++++++++.........  <- structural cluster| 23.0%
zeta     |++++++++++++.........                   | 21.9%
epsilon  |+++++++++++..........                   | 20.5%
                          ^^^^^^^^^^^^^^^^^^
                          uniform-rotation envelope
                          (47% ± 11.5 pp, predicted)
                                            ^
                                       population mean
                                       p = 0.47
```

Seven of ten nodes land within or just above the predicted
envelope. **Three nodes are 2–3 σ below.** The bottom cluster
is not random sampling error; it is a frozen sub-population.

**Step 5 — why the model breaks.** The CTMC assumes uniform
`λ_RW` across nodes. In practice, when a writer rotates, its
released children re-attach to dc = 1 candidates *visible via
TARDIS-internal signal* — referral lists from neighbours,
recovery-candidates piggybacked on the tick chain the orphan
was just on. Deep leaves appear in neither source. For such a
node:

```
effective λ_RW  →  0
effective τ_node →  ∞
```

The bottleneck dominates `τ_spread`. Until the deepest leaf is
promoted at least once, the spread cannot collapse:

```
τ_spread(measured)  ≈  max_i  τ_node(i)
```

The 4.3× gap (spec-only model) is the ratio
`τ_node(stuck-cluster) / τ_node(uniform-cluster)` integrated over
the observation window.

**Step 6 — three knobs.**

| Knob | Effect on τ_spread | Side-effect |
|---|---|---|
| Halve `T_C` | halves τ_node — halves τ_spread for the *non-stuck* part of the distribution | doubles mesh-wide rotation churn and grandpa-tick interruption rate (§2.4.6) |
| Picker fairness rule: prefer never-been-writer candidates | restores λ_RW > 0 for the stuck cluster, recovers the CTMC's predicted τ_spread ≈ τ_node · ln N | adds one bit of per-peer state and a tie-break rule in the picker |
| Accept the bimodal distribution | none | leaves a permanent 20–30 pp asymmetry; protocol-correct but not fair |

The picker fairness rule is the cheap, structural fix.
Reducing `T_C` cannot close the gap because the bottleneck is
`λ_RW = 0`, not slow uniform mixing.

**Step 7 — production scaling.**

| Constant / Quantity | Testing | Mainnet |
|---|---|---|
| `T_C` (ticks → seconds) | 600 → 3 000 s (50 min) | 51 840 → 259 200 s (72 h) |
| `τ_node` (spec-only, ≈ T_C/2) | ≈ 25 min | ≈ 36 h |
| `τ_spread` (predicted, uniform · ln N) | ≈ 58 min ≈ 1 h | ≈ 83 h ≈ 3.5 days |
| `τ_spread` (measured / scaled by 4.3× stuck-cluster factor) | ≈ 4.4 h | ≈ 15 days |

Without the fairness rule, mainnet writer-time equilibrium is
reached on the order of two weeks — long enough that
operational tooling (monitoring dashboards, alarms) may flag the
asymmetry before it self-resolves. With the fairness rule,
mainnet `τ_spread` returns to ≈ 3.5 days, the spec-conforming
timescale.

**Operational tuning lever.** For a target `τ_target`:

```
T_C_target  ≈  T_C_current · (τ_target / τ_current)
```

Halving `τ_target` requires halving `T_C` and accepting ~2× the
rotation churn rate — and is only effective for the uniform part
of the distribution; the stuck cluster needs the picker fix.

#### 2.4.6 Spec-Honest Picker — Headline Constraint

The orphan-recovery picker and any rotation-time parent-pick
path MUST conform to §1.7. Concretely:

```
A spec-conforming picker:
  • Sends TardisAttachRequest to N (typically 3) peers
    drawn from any contact source (gossip address list is fine).
  • Does NOT filter candidates by gossip-declared
    tardis_up / has_d_open / open_slots / chain depth.
  • Relies on the receiver's TARDIS-state-driven accept/reject
    + referrals to converge.
  • Tracks pending_attach with TTL so non-responses (dead
    peers) free the slot for a retry next tick.
```

The two TARDIS-internal candidate sources that ARE allowed:

1. **Tick-piggyback `recovery_candidates`** (§2.2) — peers
   whose own ticks recently advertised an open D slot. This is
   signature-anchored to a TARDIS chain.
2. **Referrals** returned by a peer we ourselves queried — the
   peer built the referral list from its own d1/d2 subtree.

Both are TARDIS-internal. Any third candidate source must come
from a direct E-enquiry round-trip, not from passive gossip
aggregation.

#### 2.4.7 Development note — 2026-05-29 cascade and fix

A 4 h development soak on 2026-05-29 exposed the consequences of
crossing the §1.7 boundary. The orphan-recovery picker (and
several adjacent attach paths) read `peer.tardis_up`,
`peer.has_d_open`, `peer.open_slots` from gossip-distributed
`PeerInfo` to filter candidates.

Failure timeline:
- **Idle steady state** — held 4–5 writers but with sustained
  detach churn (~6 / minute) as gossip lag caused brief stale
  filters and re-attaches.
- **Kick test** — kill one writer. Surviving writers whose chains
  routed through the dead node began emitting
  `GrandpaTickMissing`. Their detach updated their gossiped
  `tardis_up` to `None`. Orphans applying a "candidate's
  grandparent must also have `tardis_up = Some`" filter now
  excluded every recovering writer, finding no viable parent.
- **Cascade** — writer count fell to 2; the mesh could not
  recover. Manual restart required.

A 2-hop chain-validity filter intended as a fix (require
candidate's grandparent in gossip to also have
`tardis_up = Some`) made the failure mode strictly worse: it
held idle steady state slightly better but failed the kick test
with deterministic cascade.

The fix (committed 2026-05-29) was structural: strip every
gossip-field read from every TARDIS attach path. The orphan
sends `TardisAttachRequest` to any known peer; the receiver
decides from its own TARDIS state; referrals propagate
discovery. Post-fix the same kick test:

| Phase | Writers | Detach events (4 min window) |
|---|---|---|
| Pre-kick idle (5 min) | 5 stable | 0 |
| Kick writer | 5 → 4 instantly | 0 |
| 4 min post-kick | 4 stable | 0 |
| Revive killed writer | re-joins as reader, mesh re-balances to 5 | 0 |

This document's §1.7 codifies the rule that exposes such bugs
mechanically: any TARDIS picker code that reads the forbidden
fields fails spec review.

### 2.5 Tree Rebalancing (Writer Count Optimization)

Rebalancing increases the writer percentage by moving leaves from fully-loaded parents (dc=2) to half-loaded parents (dc=1).

A leaf node volunteers to rebalance when:

```
Protocol-level decision (wants_rebalance):
  1. Am I a leaf?                      → if no, skip
  2. Do I have a parent?               → if no, skip (orphans don't rebalance)
  3. Am I off cooldown?                → if no, skip
  4. Is my parent in open_slots list?  → if no, skip (parent is already dc=2)
  5. Is there another node with open slots? → if no, skip (nowhere to go)
  6. Detach from parent → become orphan
  7. Set rebalance cooldown (3 ticks)
  8. Orphan recovery (next tick) places me at dc=1 node via pass-0 preference
  9. That dc=1 node becomes dc=2 (writer) → net +1 writer
```

**Why next-tick recovery works:** The volunteer detaches after orphan recovery has already run for this tick. Next tick, recovery sees the old parent (now dc=0, 2 open slots) and the volunteer as an orphan. Pass-0 prefers dc=1 parents, so the volunteer goes to a DIFFERENT dc=1 node, not back to the old parent.

**Constants:**
- `REBALANCE_COOLDOWN_TICKS = 3` (15 seconds)
- `MAX_REBALANCE_PER_TICK = 5` (prevents churn storms)

### 2.6 Protocol / Simulator Separation Rule

**Architectural rule:** All protocol decisions MUST live in the protocol layer (tardis.rs, mesh.rs, constants.rs). The simulator (sim.rs) ONLY orchestrates — it calls protocol methods and executes the resulting actions (detach, attach, send message). The simulator NEVER makes protocol decisions using global state.

```
CORRECT:
  Protocol: tardis.wants_rebalance() → true/false (uses local state only)
  Sim: if wants_rebalance() { execute detach }

WRONG:
  Sim: iterate all nodes, find chain tails, match donors to receivers
  (This uses global knowledge that real nodes don't have)
```

This rule ensures that behavior observed in simulation matches what the real binary will produce. If the sim makes protocol decisions, it creates a divergence between simulated behavior and production behavior.

Verified: all rotation, rebalancing, and orphan recovery decisions use only node-local state (self.up, self.d1, self.d2, self.last_known_open_slots, self.rebalance_cooldown, self.ticks_since_parent_rotation, self.ticks_with_current_parent, self.d1_misses, self.d2_misses).

---

### 2.7 Protocol/Simulator Audit Results

#### 2.7.1 Audit Scope

Complete review of `sim.rs` (2555 lines) for violations of the §2.6 Protocol/Simulator Separation Rule. Every code path that makes a protocol-level decision was checked against the rule: "All protocol decisions MUST live in the protocol layer (tardis.rs, mesh.rs, constants.rs). The simulator ONLY orchestrates."

#### 2.7.2 Violations Found and Fixed

**V1 — Recovery Placement Strategy (FIXED)**

*Before:* The two-pass orphan recovery logic (`prefer_one_child` based on `orphan_has_children`) was implemented directly in sim.rs. The sim decided:
- Whether an orphan should prefer dc=1 parents (based on orphan's downstream count)
- Whether a candidate parent was acceptable (filtering by `downstream_count() == 1`)

*After:* Two protocol methods added to `TardisNode`:
- `recovery_prefers_writer_parent(&self) -> bool` — Protocol decision: orphans with children prefer dc=1 parents
- `recovery_candidate_acceptable(candidate_dc: usize, prefer_writer: bool) -> bool` — Protocol decision: strict vs relaxed candidate filtering

Sim now calls these methods and executes the returned result. Zero protocol logic in sim.

**V2 — MAX_REBALANCE_PER_TICK (FIXED)**

*Before:* `const MAX_REBALANCE_PER_TICK: usize = 5` was a local constant in sim.rs.

*After:* Moved to `constants.rs` as a protocol constant. Both sim and production binary import from the single source of truth.

#### 2.7.3 Accepted Sim Shortcuts (Documented, Not Violations)

These use global state for simulation convenience but do NOT make protocol decisions:

**S1 — global_open_slots (Tick Piggyback Simulation)**

Sim iterates all nodes to compute which D slots are open, then passes this to `update_known_slots()`. In production, this information travels via tick message piggyback (§2.2). Marked `AUDIT-OK`.

**S2 — P4 BFS Recovery (Global Fallback)**

P4 orphan recovery does BFS over `tardis_links` (global tree). Sim-only safety net for chaos testing. Production recovers via P1-P3. Marked `SIM SHORTCUT`.

**S3 — add_node() Initial Placement**

New node attachment uses global BFS. In production, new nodes use `mesh.find_tardis_parent()`. Marked `AUDIT-OK`.

#### 2.7.4 Verification

Post-audit, all protocol decisions confirmed in protocol layer:

| Decision | Method | Location |
|----------|--------|----------|
| Should I rebalance? | `wants_rebalance()` | tardis.rs |
| Should I drop slow child? | `wants_drop_slow_child()` | tardis.rs |
| Should I rotate? | `wants_rotate()` | tardis.rs |
| Do I prefer writer parent? | `recovery_prefers_writer_parent()` | tardis.rs |
| Is candidate acceptable? | `recovery_candidate_acceptable()` | tardis.rs |
| Which children to release? | `children_to_release()` | tardis.rs |
| Is this tick valid? | `validate_parent_tick()` | tardis.rs |
| Is this node a writer? | `is_writer()` | tardis.rs |
| Is parent a writer? | `validate_parent_tick_full()` | tardis.rs |
| E-enquiry subtree slots? | `e_enquiry_open_slots()` | sim.rs / network layer |
| Find mesh parent? | `find_tardis_parent()` | mesh.rs |

---

### 2.8 Core Integration Interface

#### 2.8.1 CoreSigner Trait

```rust
pub trait CoreSigner {
    fn sign(&self, data: &[u8]) -> Vec<u8>;
    fn verify(&self, pk: &[u8; 32], data: &[u8], signature: &[u8]) -> bool;
    fn extract(&self, signed_data: &[u8]) -> Option<Vec<u8>>;
}
```

Production: `CoreClient` via IPC to axiom-core. Simulation: `StubCore` (placeholder sigs, always valid).

#### 2.8.2 Integration Points (all `signature: vec![]` stubs)

| Operation | Where | Core Method |
|-----------|-------|-------------|
| Tick signing | tardis.rs | `core.sign(tick_data)` |
| Approval signing | tardis.rs | `core.sign(approval_data)` |
| Tick verification | tardis.rs | `core.verify(pk, tick, sig)` |
| Registration VBC | registration.rs | `core.verify(pk, vbc, sig)` |
| NBC issuance | cc.rs | `core.sign(nbc_data)` |
| CC chaining | cc.rs | `core.sign(cc_data)` |

---

### 2.9 Library Crate Structure

Public API (protocol): types, constants, tardis, mesh, gossip, smt, CoreSigner, StubCore
Internal: sim (nabla-sim binary only, `#[doc(hidden)]`)
Binaries: nabla (legacy), nabla-sim (simulator), nabla-node (production scaffold)

---

### 2.10 Isolated Tree Detection

#### 2.10.1 The Problem

After rotation or rebalance, orphaned nodes recover by attaching to the first parent candidate with an open D slot. If the candidate is *itself* freshly detached (or part of a disconnected cluster), the orphan and candidate form a mutual subtree that is disconnected from the tree roots.

These isolated subtrees are invisible to existing health metrics:

| Metric | What it checks | Why it misses isolated trees |
|--------|---------------|------------------------------|
| Sync% | `!needs_parent()` | Isolated nodes have upstream → pass |
| Write% | `downstream_count >= 2` | Isolated nodes approve each other → pass |
| Orphans | `needs_parent()` | Isolated nodes are not orphans → pass |

An isolated subtree of N nodes reduces effective Write% without triggering any alert. A node with `upstream = Some(x)` and `downstream_count = 2` can be completely disconnected from the tree roots and still report as a healthy writer.

#### 2.10.2 Detection: Reachability from Tree Roots

A node is **connected** if and only if there exists a path through TARDIS tree links from that node upward to any tree root.

A node is **isolated** if it is alive, has upstream set, but no upward path reaches any tree root.

```
Definition: Reachable(node) iff
  node.is_tree_root OR
  (node.upstream ≠ None AND upstream.alive AND Reachable(parent(node)))

Where: is_tree_root = alive AND (upstream is None OR upstream is dead)
```

In practice, BFS starts from all tree roots and walks downward through `tardis_links`. Any alive node NOT in the visited set is isolated.

At steady state with all genesis nodes alive, the genesis ring nodes are tree roots (the ring is circular — each has the previous as parent, but conceptually the BFS can start from any of them). After genesis nodes die, surviving orphaned subtree tops become tree roots. The algorithm is identical.

#### 2.10.3 Classification

After a tree connectivity check, every alive node falls into exactly one category:

| Code | Name | Condition |
|------|------|-----------|
| `[W]` | Writer | Reachable, dc ≥ 2 |
| `[R]` | Reader | Reachable, dc < 2 |
| `[O]` | Orphan | `needs_parent()` = true |
| `[I]` | Isolated | Has upstream, NOT reachable from any tree root |

Target at steady state: `[I]` = 0, `[O]` ≤ 3 (transient, recovered next tick).

#### 2.10.4 Root Cause: Recovery Race Condition

The isolation happens during same-tick batch recovery:

```
Tick T:
  1. Rotation detaches nodes A, B, C (all become orphans)
  2. Orphan recovery runs in order: A, B, C
  3. A's P1 candidate list (from stale tick cache) points to B
  4. B has not yet recovered → but B has dc=0, so "has_d_open" = true
  5. A attaches to B ✓ (B now has upstream=old_parent, dc=1)
  6. C's P1 candidate list points to A (also stale)
  7. C attaches to A ✓ (A is now a "writer" with dc=1... getting there)
  8. B later attaches to some node D (also from the same rotation batch)
  9. Result: A→B→D→...→A circular, or A→B and C→A with B not reaching any seed

None of them reach a seed. All report as healthy.
```

#### 2.10.5 Sim-Level Fix: Reachability Guard

Recovery passes P1 through P3 now check `reachable.contains(&candidate_idx)` before attaching. The `reachable` set is computed once (BFS from tree roots) before the recovery loop and updated incrementally as orphans attach to reachable parents.

P4 (BFS from tree roots) is inherently safe — it only finds candidates by walking down from tree roots.

After recovery, `find_isolated_nodes()` detects any remaining isolated subtrees and force-detaches every node, converting them to orphans for recovery next tick.

This is a **simulation-level safeguard** using global state. The protocol-level fix is §2.16.3 (Parent Tick Liveness).

---

### 2.11 Upstream Approval Verification

#### 2.11.1 Bug: Forwarded downstream_approvals

The `TickMessage.downstream_approvals` field was designed to carry the **sender's** approval count from the previous round. However, `process_tick()` forwarded the **parent's** value unchanged:

```rust
// BUG (v0.7): passes through parent's count, not own count
let forward_tick = TickMessage {
    downstream_approvals: tick.downstream_approvals, // grandparent's count!
    ..
};
```

A child node checking `tick.downstream_approvals >= 2` was actually checking its **grandparent's** writer status, not its immediate parent's. In a healthy tree this usually works (if grandparent is a writer, parent likely is too), but fails at tree edges and after rotation.

#### 2.11.2 Fix: Report Own Approval Count

Each node must set `downstream_approvals` to its own approval count from the **previous** tick round, not pass through the received value:

```rust
// FIXED (v0.8): each node reports its OWN approval count
let forward_tick = TickMessage {
    downstream_approvals: self.prev_round_approval_count,
    ..
};
```

`prev_round_approval_count` is updated at the end of each tick after approvals are collected. This means a newly joined node reports 0 for its first tick (correct — it hasn't been approved yet), and its children tolerate this via `WRITER_GRACE_TICKS`.

#### 2.11.3 Writer Check Activation

The writer check in `process_tick()` (§2.7 in v0.6) is fully implemented but was disabled in simulation to avoid cascade detachments during early tree formation. With stable rotation and the reachability guard, it can now be activated:

```
process_tick() writer check (already in tardis.rs):

  1. If tick.downstream_approvals >= 2 → parent is writer → reset streak
  2. If tick.downstream_approvals < 2 AND I have children → stay (can't orphan my subtree)
  3. If tick.downstream_approvals < 2 AND I'm a leaf → increment streak
  4. If streak >= WRITER_GRACE_TICKS (3) → DetachUpstream(ParentNotWriter)
```

Only **leaf nodes** detach from non-writer parents. This is critical — a node with children that detaches would orphan its entire subtree. The "detach pressure" flows downward to the leaves, which are free to move. Over time, non-writer subtrees shed their leaves until the non-writer itself has no children and can detach.

#### 2.11.4 Limitations

The writer check catches degraded parents (lost a child, dc dropped below 2) but does **not** catch isolated subtrees where nodes mutually approve each other. In an isolated cluster, every node with 2 children genuinely has `downstream_approvals = 2`. The check passes because they ARE writers — just disconnected ones.

This is why §2.16.3 (Parent Tick Liveness) and §2.10.5 (Reachability Guard) are required as complementary mechanisms.

---

### 2.12 Seed Epoch Beacon

[Section removed in v0.9 — superseded by Section 2.16.3 Parent Tick Liveness]

---

### 2.13 Simulation Diagnostics

#### 2.13.1 Orphan Diagnostic with Tree Dump

The `dump_orphan_diag()` command now includes a complete tree state with per-node reachability:

```
── TREE STATE ──
alive=50 writers=25 readers=22 orphans=0 isolated=3
  node  0: UP=Some(9) D1=Some(1) D2=Some(10) dc=2 [W] seed=true reach=true
  node 25: UP=Some(12) D1=None D2=None dc=0 [R] seed=false reach=true
  node 30: UP=Some(42) D1=None D2=None dc=0 [I] seed=false reach=false
```

Each node shows: upstream index, D1/D2 indices, downstream count, role classification (`[W]`/`[R]`/`[O]`/`[I]`), seed status, and reachability from the seed ring.

This enables immediate visual identification of isolated subtrees without needing to manually trace links.

#### 2.13.2 Auto-Dump on Low Write%

The simulator automatically dumps the full diagnostic (orphan counters + tree state) when:

1. All target nodes have been deployed (`alive >= node_count`)
2. Write% drops below 40%

The dump triggers once per episode. The flag resets when Write% recovers above 40%, allowing subsequent dumps if the condition recurs.

```
Console output:
  ⚠ AUTO-DUMP: Write% 23.0% < 40% at tick 878 → orphan_diagnostic.txt
```

#### 2.13.3 Dashboard: Isolated Counter

The web dashboard displays isolated node count alongside existing metrics:

```
⏱ TARDIS: Sync 100% | Write 50% | Orphans 0 | Isolated 0
```

Isolated count appears red when > 0, green when 0.

#### 2.13.4 Console Output

Console log line now includes isolated count:

```
[T   500] alive=50/50 msgs=42 conv=100.0% tardis=sync:100%|write:50%|orph:0|isol:0
```

---

### 2.14 E-Enquiry Recovery (§2.1 Implementation)

#### 2.14.1 Background

The YPX-003 §2.1 spec defines E as a stateless enquiry slot:

```
E: Enquiry slot (connect, query, disconnect) — stateless
```

And §2.2 states: "An E enquiry at any node reveals the availability picture for that node's entire subtree."

This was never implemented for orphan recovery. The existing E-peer mechanism in `mesh.rs` serves a different purpose (passive gossip observation for mesh-homeless nodes, not TARDIS slot discovery).

#### 2.14.2 The Gap

Without E-enquiry, the orphan recovery priority is:

| Pass | Source | Scope | Production? |
|------|--------|-------|-------------|
| P1 | Tick cache (`last_known_open_slots`) | Last tick's piggyback data | Yes |
| P2 | `find_tardis_parent()` | 1-hop SlotAvailable gossip | Yes |
| P3 | `known_nodes` with `has_d_open` | Passive gossip knowledge | Yes |
| P4 | Global BFS from seeds | All nodes in network | Sim only |

If an orphan's P1-P3 all point to stale or disconnected nodes, **there is no production recovery path**. The node stays orphan indefinitely. P4 (global BFS) only exists in simulation.

#### 2.14.3 E-Enquiry as Production P4

The E-enquiry fills this gap as a protocol-correct recovery mechanism:

```
Orphan recovery with E-enquiry:

  P1: Check last_known_open_slots (instant, from tick cache)
  P2: Check mesh.find_tardis_parent() (1-hop gossip hints)
  P3: Check known_nodes with has_d_open (passive knowledge)
  PE: E-enquiry to known writer (subtree walk — production path)
  P4: Global BFS (sim-only emergency fallback)
```

#### 2.14.4 Protocol

When P1-P3 fail, the orphan performs an E-enquiry:

```
1. Orphan selects a known writer (from mesh knowledge or well-known address list)
2. Orphan connects to target via E slot (stateless TCP connection)
3. Orphan sends: EnquiryRequest { type: SLOT_DISCOVERY }
4. Target walks its subtree using aggregated subtree_d_available info
5. Target responds: EnquiryResponse {
     open_slots: [(node_id, address, open_count), ...]
   }
6. Orphan disconnects E slot
7. Orphan attempts to attach to one of the returned nodes
```

Key properties:
- **Stateless**: E connection lasts < 1 second. No persistent state.
- **Writer-directed**: Orphans query known writers (good subtree coverage). Genesis addresses serve as fallback contacts.
- **Subtree-scoped**: Each writer knows its subtree. Querying multiple writers covers the network.
- **Reachability-safe**: Writers only report nodes in their own subtree (guaranteed reachable).

The well-known address list includes the genesis node addresses but is not limited to them. Any node can be added to the list. The list is a bootstrap aid, not a protocol authority.

#### 2.14.5 Subtree Slot Aggregation

For E-enquiry to work, each node must track open D slots in its subtree. This information flows bottom-up through tick approvals:

```
When child approves parent's tick, the approval includes:
  TickApproval {
    tick_number: u64,
    approver_pk: PeerId,
    signature: Vec<u8>,
    subtree_open_d: u32,   // NEW: open D slots in child's subtree (including self)
  }
```

Each node computes its `subtree_open_d`:
```
  my_open = if has_d_open() { 2 - downstream_count() } else { 0 }
  subtree_open_d = my_open + d1_subtree_open_d + d2_subtree_open_d
```

This is updated every tick with zero additional messages — it piggybacks on existing approvals.

#### 2.14.6 Simulation Implementation

In the simulator, `e_enquiry_open_slots(target_idx, reachable)` walks the target's subtree through `tardis_links` and returns indices of nodes with open D slots. This simulates what the production node would compute from its aggregated subtree data.

The PE pass iterates through alive writers, calls `e_enquiry_open_slots()` for each, and attaches to the first acceptable candidate. This correctly models the stateless E connect → query → disconnect flow.

---

### 2.15 Writer Density Optimization

#### 2.15.1 The dc=1 Problem

With N nodes, the writer count is governed by: **W = (N − M) / 2** where M = number of dc=1 (half-loaded) nodes. Every dc=1 node costs exactly 0.5 writers. In a perfect binary tree, M=0 and W=N/2 (50%). After rotation shuffles, M>0 and Write% drops.

The dc=1 count (M) is the key metric to minimize.

#### 2.15.2 Recovery Placement Fix

**Previous (incorrect):** Only orphans with children used strict recovery (prefer dc=1 parents). Leaf orphans accepted any slot, including dc=0 nodes — creating new dc=1 waste instead of filling existing dc=1 nodes.

**Corrected:** ALL orphans prefer dc=1 parents via strict recovery pass:
```
recovery_prefers_writer_parent() → always true

Two-pass recovery:
  Pass 0 (strict): only accept dc=1 parents → creates writers
  Pass 1 (relaxed): accept any open slot → fallback when no dc=1 available
```

This ensures dc=1 nodes are filled first, maximizing writer count. Only when all dc=1 nodes are full do orphans accept dc=0 parents.

#### 2.15.3 Rebalance: Disabled in Steady State

**Analysis:** Moving a leaf from a dc=2 parent to a dc=1 target is always zero-sum:
```
Before: parent=dc=2 (writer), target=dc=1 (reader) → 1 writer
After:  parent=dc=1 (reader), target=dc=2 (writer) → 1 writer
Net writer change: 0
```

Writer density is controlled entirely by **recovery placement** (§2.15.2): when rotation creates orphans, strict recovery places them at dc=1 nodes first, maximizing writer count. This is self-correcting without rebalance.

In testing, rebalance caused churn storms: 740 unnecessary orphan cycles in 54 ticks, same nodes bouncing every 2 ticks, with zero Write% improvement (already at 50%).

**Decision:** `wants_rebalance()` returns `false`. Rebalance infrastructure retained for future activation with growth-detection logic when dynamic node joining (GAP-03/04) is implemented. In growing networks where new nodes join at structurally imbalanced positions, rebalance may have value — but only with growth-triggered activation, not continuous polling.

#### 2.15.4 D Slot Reservation (§2.3 Implementation)

When a downstream child goes offline (crash, network hiccup), its D slot is RESERVED for `D_RESERVATION_TICKS = 10` ticks (50 seconds). During reservation:

- The slot appears as "not open" to other nodes
- The original child can reclaim immediately (priority access)
- Other nodes must wait for reservation expiry
- After expiry, slot becomes truly open for any node

Reservations apply ONLY to involuntary disconnection (death). Voluntary operations (rotation, rebalance) use immediate slot release.

```
Implementation:
  TardisNode.d1_reserved: Option<(PeerId, tick_when_reserved)>
  TardisNode.d2_reserved: Option<(PeerId, tick_when_reserved)>

  remove_peer():          immediate release (rotation, rebalance)
  remove_peer_reserved(): reserved release (child offline)
  check_reservations():   expire after D_RESERVATION_TICKS
  add_downstream():       original peer can reclaim reserved slot
  has_d_open():           false if slot is reserved (blocks others)
```

#### 2.15.5 Writer-Preserving Rotation

Full rotation (writer releases children + detaches from parent) creates a structural imbalance:

```
Before: Grandparent P (dc=2) → Node X (dc=2) → [child_A, child_B]

Without fix:
  X releases child_A → orphan          (1 orphan)
  X releases child_B → orphan          (2 orphans)
  X detaches from P  → P becomes dc=1  (3 orphans, 1 dc=1 hole)

  Recovery: 1 orphan fills P (dc=1→dc=2), 2 orphans land at dc=0
  Net: +2 dc=1 nodes per rotation → Write% drops over time

With fix (writer-preserving):
  X releases child_A                    (released)
  X releases child_B                    (released)
  X detaches from P → P has open slot
  Place child_A at P directly           (child_A stays connected, P→dc=2)

  Only 2 orphans (child_B + X), 0 dc=1 holes from P
  Net: 0 dc=1 from this mechanism
```

Implementation: after rotation detaches from grandparent P, immediately attempt to attach the first released child (preferring children with subtrees) directly to P. This is a local operation — no recovery needed. The remaining orphans enter normal recovery.

This prevents the structural Write% degradation that occurs when rotation creates more orphans than dc=1 holes.

#### 2.15.6 Writer Check Bounce Prevention

**The Problem:** When strict recovery fails (no dc=1 parent available), relaxed recovery places the orphan at a dc=0 parent. The parent becomes dc=1 (one child). A dc=1 parent has only 1 downstream approval — not a writer. After `WRITER_GRACE_TICKS=3`, the writer check detaches the leaf. Recovery places it at dc=0 again. Infinite bounce loop.

Observed in testing: node 15 bounced every 3 ticks for 50+ ticks, generating 91 writer_check orphan events (52% of all events).

**The Fix — Settle Period:** New constant `WRITER_SETTLE_TICKS = 10` (50 seconds). After arriving at a new parent, the writer check is suppressed for 10 ticks. This gives time for rotation to create orphans that fill the sibling slot.

```
In process_tick, writer check for leaf nodes:
  if ticks_with_current_parent < WRITER_SETTLE_TICKS:
      streak = 0           # suppressed, still settling
  else:
      streak += 1
      if streak >= WRITER_GRACE_TICKS: detach

Total time before detach: SETTLE + GRACE = 13 ticks = 65 seconds
```

**Rationale:** The settle period distinguishes two scenarios:
- **Degradation** (parent had dc=2, lost a child): `ticks_with_current_parent` is high, settle period already passed. Writer check fires promptly after GRACE_TICKS.
- **Building** (orphan just landed at dc=0): `ticks_with_current_parent` is low. 10-tick settle period lets the network self-correct via rotation orphans filling the sibling slot.

Constants:
```rust
pub const WRITER_GRACE_TICKS: u8 = 3;     // streak before detach (unchanged)
pub const WRITER_SETTLE_TICKS: u32 = 10;   // minimum ticks with new parent (NEW)
```

#### 2.15.7 Seed Child Approval

[Section removed in v0.9 — see Section 2.16 Genesis Normalization]

---

### 2.16 Genesis Normalization

#### 2.16.1 Principle

A genesis Nabla is the same as every other Nabla.

Genesis nodes have no special protocol code, no exemptions from validation rules, no privileged role in tick generation, and no ongoing authority after the network starts. Their only distinction is operational:

1. They are launched together at network start
2. Their addresses are well-known (hardcoded in initial config)
3. They form the initial topology because they are the only nodes present

Once public nodes join, genesis nodes participate in rotation, recovery, writer checks, and every other protocol mechanism identically to any other node. A genesis node that loses both children is a READER. A genesis node whose parent dies is an orphan. A genesis node that fails the writer check detaches.

This is consistent with the White Paper's principle (§3.2):

> "Genesis defines WHERE THE UNIVERSE STARTED, not WHO CONTROLS IT."
> "Bootstrap status grants no permanent privilege. It exists only to allow the system to begin."

#### 2.16.2 Why 10 Genesis Nodes

The genesis count was increased from 3 to 7 to 10 through simulation. The reason is purely topological:

- At tick 0, the genesis nodes are the entire network
- They connect to each other in a ring: G0→G1→G2→...→G9→G0
- Each has UP=previous, D1=next, D2=open
- This gives 10 interconnected nodes with open D2 slots for the first public nodes

With fewer genesis nodes, the initial tree is shallower and has fewer open slots. With 10, the first 10 public nodes each get a D2 slot immediately, and the network reaches 50% writer coverage from tick 1.

If the majority of genesis nodes go offline, the network degrades (fewer writers, more orphans). But the surviving nodes — genesis or not — continue operating. If ALL nodes go offline, the network stops. When any small set of nodes with well-known addresses comes back online, the network reignites from them. This is not a genesis-specific property — it works with any set of known addresses.

#### 2.16.3 Parent Tick Liveness (replaces §2.12)

Every parent generates its tick from NTP and sends it to children. The tick itself serves the same purpose as the former Seed Epoch Beacon — proof that the approval chain is alive and current.

A child that stops receiving valid ticks from its parent knows the parent is dead or disconnected. The existing mechanisms handle this:

| Condition | Detection | Response |
|-----------|-----------|----------|
| Parent dies | No tick received | D slot reservation (§2.3), then orphan recovery |
| Parent falls behind | Tick fails 0-5s window | Reject tick (§1.3.3) |
| Parent not a writer | `downstream_approvals < 2` | Writer check detach (§2.11) |
| Network partition | All ticks stale | Nodes in each partition operate independently; reconcile on reconnect (§9.3) |
| Isolated subtree | Reachability guard blocks formation | Recovery only attaches to reachable nodes (§2.10.5) |

No node needs to be a beacon source. Every parent-child link IS a liveness proof.

**TickMessage update:** The `beacon: Option<SeedBeacon>` field (former §2.12.7) is removed:

```rust
pub struct TickMessage {
    pub number: u64,
    pub upstream_pk: PeerId,
    pub payload: Vec<u8>,
    pub signature: Vec<u8>,
    pub timestamp_ms: u64,
    pub available_slots: Vec<(PeerId, u32)>,
    pub downstream_approvals: u8,       // sender's OWN count (§2.11)
    pub subtree_d_available: u32,       // §2.2 slot availability
    // beacon field REMOVED — parent tick IS the liveness proof
}
```

**Constants removed:**
```
BEACON_INTERVAL          — removed (no separate beacon)
BEACON_STALE_THRESHOLD   — removed (tick timing handles staleness)
```

#### 2.16.4 Partition Recovery via Mesh (resolves Open Question #5)

Partition recovery does NOT depend on genesis nodes, beacons, or any TARDIS mechanism. It is handled entirely by the gossip mesh layer (see mesh.rs implementation).

##### Natural splits are rare — analysis reference

Before describing the recovery mechanism, note that under the TARDIS + 9-mesh-peers design, **natural partitions are vanishingly rare**. The split-resistance analysis lives in [`docs/AXIOM_GUIDE_Nabla.md` §15.3](AXIOM_GUIDE_Nabla.md#153-mesh-resilience) ("Mesh Resilience"). Key results from that analysis (Monte Carlo simulation, not formal proof — empirical bounds):

```
                  Tree-Only Split    Tree+9-Mesh Split
  Single-node loss       69-100%          0.0%  (every trial, 10-1,000 nodes)
  50% random failure     100%             0.0%-2.0%  (50-1,000 nodes)
  Deliberate partition   trivial          "impossible at ≥5,000 nodes"
```

The TARDIS tree alone is brittle (cutting one near-root node splits up to 100% of trials), but the 9-mesh-peer overlay makes splits **practically impossible** at production scale. The cited numbers are simulation-derived — formal percolation analysis is a future-work item, but the simulation results align with classical percolation theory predictions (per-node connectivity > 1/k_critical → giant-component connectivity preserved under high failure rates).

Therefore: the partition recovery mechanism below is for the **rare** events that do occur (e.g. operator-induced shutdowns, regional cable cuts) — not the steady-state expectation. Most "splits" observed in early-stage dev meshes (e.g. during rolling restarts on a 10-node soak env) are recovery-window artifacts, not stable splits.

##### The Problem

When a network partition occurs, nodes on each side lose contact with the other side. TARDIS tree links across the boundary stop delivering ticks. Gossip messages are blocked. Each partition operates independently — both sides maintain their own TARDIS trees, their own writer coverage, their own state.

Over time (60 ticks / 5 minutes), stale-peer pruning removes cross-partition peers from each node's active peer list. Known_nodes entries for cross-partition nodes also age out as same-side peers are observed more recently (LRU eviction, capped at 256 entries). After sustained partition, neither side has mesh knowledge of the other.

##### Detection

Detection is automatic — **UMP-driven (NORMATIVE).** When a sender broadcasts a transaction, the UMP carries the sender's **expected-register Nabla** — the specific Nabla node the sender intends to register the transaction with (typically the writer it has been pinning to, per `nabla_hint` §1.4 and YPX-002 §3.2). The receiver's wallet forwards the UMP to its own Nabla. The receiver's Nabla inspects the expected-register Nabla and asks: *"Is that node in my mesh-known set, and does it share a subtree with me?"* If the answer is no — the sender's Nabla is in a different subtree or unknown — the receiver's Nabla **automatically triggers a bridge** to reconnect to that node. **The client wallet never bridges. It only passes the sender's branch info in the UMP; the Nabla decides whether bridging is needed and does it.**

This automation closes the original-design gap that made the strict-write-qualified gate produce `E_TXID_ATTESTATION_MISSING` in early integration testing: when subtrees were briefly split, transactions across subtrees failed because no Nabla automatically detected the cross-subtree intent. The UMP-driven trigger gives the receiver's Nabla everything it needs to bridge proactively, before redeem.

```
Automated bridge trigger flow:

  Sender's wallet:
    1. Picks expected-register Nabla N_s (its writer)
    2. Includes {node_id: N_s, address} in the UMP

  SDK builds + signs UMP → SMTP/TOT transport → receiver's wallet

  Receiver's wallet:
    3. Receives UMP, extracts expected-register Nabla N_s
    4. Sends UMP to its own Nabla N_r

  Receiver's Nabla N_r:
    5. Checks if N_s is in mesh-known peers and same subtree
    6. If NOT same subtree → fire bridge_core(N_s.address)
         → IntroductionRequest exchange (§6.6 mechanism)
         → Cross-subtree gossip + anti-entropy unifies state within ~30 ticks
    7. Once subtrees converged, redeem proceeds with txid attestation
       resolvable on both sides

  Client wallets do NOT initiate bridges — they only carry the
  expected-register Nabla in the UMP. Bridging is a Nabla concern.
```

The receiver's Nabla SHOULD cache "bridge-attempted-recently" against `(N_s.address, current_tick)` so repeated UMPs naming the same N_s within a short window don't trigger redundant bridge calls. A successful bridge unifies state for the whole subtree pair; subsequent cross-subtree TX from any wallet pair benefits.

**There is no manual fallback path.** AXIOM has no operator-override design — either the automated UMP-driven trigger works correctly, or the design is incomplete and must be fixed. The admin endpoint `/bridge` (`bridge_core` handler) exists in the codebase for ops/debug purposes only; it is **NOT** part of the protocol design and MUST NOT be relied upon by any normative flow.

##### Observation vs Intervention

Partition states and bridge events ARE observable — operators may see a `root_hash` mismatch in dashboard data, watch `bridge_core` invocations in logs, or notice SCARRED outcomes when expecting CLEAN. **Observation is allowed and useful** (for debugging, capacity planning, and incident analysis). What is NOT allowed is acting on those observations to change the protocol's outcome. The protocol determines outcomes; a human reading logs cannot route the protocol differently, cannot manually invoke recovery, and cannot resolve a SCARRED link by choosing "burn vs heal" on the wallet's behalf — those are wallet-code decisions driven by `diagnose()`. AXIOM is a non-human-intervention, non-centralized mesh: observability is a property of the system, but intervention is not a protocol primitive.

##### The Bridge Mechanism (mesh.rs §6.6)

The bridge primitive itself — invoked automatically via the UMP-driven trigger above — is a one-shot peer exchange that reconnects two partitions. The legacy name "human bridge" reflects an earlier implementation phase before the automated trigger existed; the underlying primitive is unchanged but the trigger is now part of the protocol, not an operator action.

Three things happen in sequence:

```
1. Physical path restored
   The blocked links are cleared. Messages can flow again.

2. Bridge nodes become direct active peers
   Node A (partition 1) and Node B (partition 2) add each other
   as active mesh peers. This creates an immediate gossip link
   across the partition boundary.

3. Peer exchange (PX)
   Both sides exchange their full known_nodes tables.
   A learns about all nodes B knows. B learns about all nodes A knows.
   Cross-partition entries are inserted with last_seen = current_tick
   (marked fresh, won't be immediately pruned).
```

After the bridge:

```
Tick +1 to +30:  periodic_peer_check grafts from new known_nodes.
                 Mesh rotation (every 30 ticks) drops lowest-scored
                 peers, creating slots for cross-partition peers.
                 Within 1-2 rotation cycles, multiple mesh links
                 span the partition boundary.

Tick +6:         Anti-entropy fires. Nodes compare root_hash with
                 a random peer. If roots differ, the richer node
                 sends missing SMT entries to the poorer node.
                 State sync begins immediately.

Tick +6 to +30:  Anti-entropy fires repeatedly (every 6 ticks).
                 Each cycle syncs more state across the boundary.
                 Convergence recovers progressively.

Tick +200:       Full convergence (>90%) restored in testing.
```

##### Implementation (mesh.rs)

```rust
// mesh.rs — §6.6 Human Bridge

pub fn human_bridge_px(
    &mut self,
    remote_known: &[PeerInfo],
    current_tick: u64,
) -> (usize, usize, usize) {
    // Inject all remote known_nodes into local known_nodes.
    // Mark as fresh (last_seen = current_tick) so they survive pruning.
    // Returns (received, new_nodes, updated_nodes).
}

pub fn known_nodes_snapshot(&self) -> Vec<PeerInfo> {
    // Export full known_nodes for PX exchange.
}
```

```rust
// sim.rs — orchestration

pub fn human_bridge(&mut self, a_idx: usize, b_idx: usize) {
    // 1. Clear all blocked links
    self.blocked.clear();

    // 2. Bridge nodes become direct active peers
    self.nodes[a_idx].mesh.add_peer_direct(b_info);
    self.nodes[b_idx].mesh.add_peer_direct(a_info);

    // 3. Exchange known_nodes
    let a_known = self.nodes[a_idx].mesh.known_nodes_snapshot();
    let b_known = self.nodes[b_idx].mesh.known_nodes_snapshot();
    self.nodes[a_idx].mesh.human_bridge_px(&b_known, self.tick);
    self.nodes[b_idx].mesh.human_bridge_px(&a_known, self.tick);
}
```

##### Why This Works Without Beacons

The former Seed Epoch Beacon (§2.12) was designed to detect disconnection from seeds. Partition recovery was one motivation. But the beacon solved the wrong problem at the wrong layer:

| Concern | Layer | Mechanism |
|---------|-------|-----------|
| "Am I receiving valid ticks?" | TARDIS | Parent tick validation (§1.3.3) |
| "Is my parent a writer?" | TARDIS | Writer check (§2.11) |
| "Am I in an isolated subtree?" | TARDIS | Reachability guard blocks formation (§2.10.5) |
| "Is the network partitioned?" | Mesh | Root hash mismatch detection |
| "How do I reconnect?" | Mesh | Human bridge PX (mesh.rs §6.6) |
| "How do I resync state?" | Mesh | Anti-entropy pull sync (every 6 ticks) |

Partition is a network-layer problem. The mesh handles network-layer problems. TARDIS handles time and approval. Clean separation.

##### Constants

```rust
// Mesh constants relevant to partition recovery
pub const STALE_PEER_THRESHOLD: u64 = 60;       // 5 min — prune unresponsive peers
pub const KNOWN_NODES_MAX: usize = 256;          // LRU cap on known_nodes
pub const ROTATION_INTERVAL: u64 = 30;           // 2.5 min — drop lowest-scored peer
pub const ANTI_ENTROPY_INTERVAL: u64 = 6;        // 30s — pull-based state sync
pub const KNOWLEDGE_REFRESH_INTERVAL: u64 = 30;  // 2.5 min — PX even at full peers
```

##### Tested

Simulation test `split_heal_human_bridge` verifies:
1. Pre-split: 100% convergence
2. During partition (100 ticks): convergence drops
3. Human bridge triggers PX between one node from each side
4. Post-bridge (200 ticks): convergence recovers to >90%

##### Relationship to §32 TARDIS Merge Protocol (Yellow Paper v2.10.1)

This section (§2.16.4) covers **network-layer** partition recovery: restoring mesh connectivity and gossip propagation via human bridge and peer exchange. It does not address what happens to **conflicting wallet states** that may have diverged during the partition.

Yellow Paper §32 (TARDIS Merge Protocol) handles the complementary **protocol-layer** concern: detecting state-ID forks (same wallet registered with different state on each side of the partition) and resolving them via merge quarantine. See also Security Issue C4 (Partition Timestamp Manipulation) in `SECURITY_ISSUES_CONSOLIDATED.md`.

#### 2.16.5 Receiver-Triggered Bridge (Gossip Split Healing via Cheque Verification)

The human bridge in §2.16.4 is an operator-level action. This section describes how **ordinary receivers** trigger partition healing as a natural consequence of cheque verification — turning economic incentive into network repair.

##### Problem

Sender and receiver are on different gossip partitions. The sender registers their TX on partition A. The receiver queries partition B — no record found. The cheque is SCARRED. Neither side knows the other partition exists.

##### Detection

The receiver queries 3 Nabla nodes for the sender's `(wallet_pk, state_id)`:
- All 3 return "no record" → SCARRED (sender may not have registered, or gossip split)
- Root hashes across the 3 nodes are consistent → no split, just unregistered
- Root hashes differ → gossip split detected (rare but possible)

##### Receiver-Triggered Healing Protocol

When a receiver sees SCARRED and suspects a gossip split (or the sender confirms they did register), the protocol is:

```
1. Receiver asks sender (out-of-band): "Give me your Nabla code"

2. Sender provides BRIDGE INFO — their Nabla node's identity:
   - IP:port address (current, at time of registration)
   - Node name (permanent NBC identity, e.g. "nabla-tokyo-42")
   Sender's wallet stores both at registration time.

3. Receiver enters the bridge info into their wallet client

4. Receiver's client resolves the Nabla node (IP first, name fallback):
   a. Try IP:port directly — fast, works if node hasn't moved
   b. If IP unreachable: query any known Nabla node for the node name
      → mesh returns current IP:port (nodes track each other via gossip)
   c. If both fail: bridge cannot connect, cheque stays SCARRED
   Nabla nodes are citizen-run (dynamic IPs), so name-based fallback
   is essential. IP is tried first because it's faster and works
   across partition boundaries (name resolution requires gossip,
   which may be split).

5. Receiver's client sends BRIDGE REQUEST to receiver's local Nabla node:
     POST /bridge {"address": "resolved_ip:port"}

6. Receiver's Nabla node connects to the sender's Nabla node:
   - Sends IntroductionRequest
   - Receives IntroductionResponse with known_nodes
   - Calls human_bridge_px() — imports all cross-partition peers
   - Both partitions now have mesh links across the boundary

7. Anti-entropy (every 6 ticks / 30s) syncs SMT state across
   the new mesh links. The sender's registration propagates to
   the receiver's partition.

8. Receiver re-queries their Nabla nodes:
   - Registration now visible → cheque transitions to CLEAN
   - If double-spend detected during sync → cheque becomes REJECTED
```

**Sender's registration record** (stored locally in wallet):
```
{ node_id: "2969...", node_name: "nabla-tokyo-42", address: "85.123.45.67:6225" }
```
The sender provides IP + name to the receiver when asked. The receiver's client tries both.

##### Why This Works

The receiver has **economic incentive** to heal the split: they want CLEAN money, not SCARRED. By providing a bridge code, the sender proves they registered (they know which Nabla node they used). The receiver's Nabla node uses the bridge to reconnect the partitions — healing the split for everyone, not just this transaction.

This is a **protocol-level incentive for network repair**: the natural act of verifying a cheque drives gossip convergence. The more transactions flow across partition boundaries, the faster partitions heal.

##### Security Properties

- **No trust required**: The bridge only exchanges peer lists (known_nodes). No wallet state is directly transferred — state syncs via anti-entropy after mesh reconnection.
- **No false CLEAN**: Even after bridging, if the sender double-spent across partitions, anti-entropy will detect the conflict and the cheque becomes REJECTED, not CLEAN.
- **Receiver cannot forge**: The bridge code is a real IP:port. If the sender provides a fake code, the connection fails and the cheque stays SCARRED.
- **One-shot**: The bridge is a single peer exchange. If the partition heals, future queries work normally. If it splits again, a new bridge is needed.

##### Bridge Code Format

The bridge info contains both IP:port and node name:

```
Format: "ip:port/node_name"
  Example: "85.123.45.67:6225/nabla-tokyo-42"

Human-friendly (phone/chat):
  "85 dot 123 dot 45 dot 67, port 6225, name nabla-tokyo-42"

QR code: encode the full string for in-person exchange.

Resolution order:
  1. Parse IP:port → try direct TCP connection
  2. If unreachable → extract node_name → query mesh for current address
  3. Both fail → bridge cannot connect
```

The code is designed to be readable over phone, chat, or in person — matching the "survival-grade" philosophy where technology degrades gracefully to human communication. Both IP and name are provided because citizen-run Nabla nodes have dynamic IPs — the name is the permanent identity, the IP is the fast path.

##### Implementation

- **Nabla node**: HTTP API endpoint `POST /bridge` accepts `{"address": "ip:port"}` and triggers `human_bridge_px()`. Uses the existing `--bridge-peer` CLI mechanism internally.
- **Client (webclient/PMC)**: Encode/decode bridge code, prompt user, call Nabla API.
- **Existing code**: `mesh.rs::human_bridge_px()`, `nabla_node.rs::--bridge-peer` flag.

##### Cheque Verification Summary (with Bridge)

| Receiver Query Result | Status | Action |
|---|---|---|
| 3/3 Nabla confirm, matured, no conflict | **CLEAN** | Redeem normally |
| 0/3 Nabla confirm, consistent root_hash | **SCARRED** | Sender didn't register, or gossip pending. Wait or accept risk. |
| 0/3 Nabla confirm, root_hash mismatch | **SCARRED (split)** | Ask sender for bridge code → heal → re-query |
| 3/3 Nabla confirm, conflict detected | **REJECTED** | Double-spend. Do not accept. |

Note: the cheque DOES carry the sender's designated Nabla as
`cheque.nabla_hint = {node_name, address}` per YPX-002 §3.2 step 5
and Yellow Paper §17. The sender pre-declares this in the witness
request; every witnessing validator stamps it into the cheque at
issuance. The receiver uses it as the sender's-side node in the YP §4.6
verification triplet (sender's sticky + 2 cross-branch random). The
hint is informational metadata: not signed, not verified by Core,
and on first-ever-TX wallets it is absent (the receiver falls back
to 3 cross-branch random nodes). Earlier drafts of this document
asserted the opposite — that text was stale and has been removed.

---

## 3. Tree Capacity Analysis

### 3.1 Growth Mathematics

Binary tree with fan-out 2:

```
Level 0 (genesis):  10 nodes (ring topology, each has D2 open)
Level 1:            up to 10 nodes (fill genesis D2 slots)
Level 2:            up to 20 nodes (fill Level 1 D1+D2 slots)
Level n:            2^(n-1) × 10 nodes

Total nodes in full tree of depth d:
  Total = 2^(d+1) - 1
```

| Depth | Total Nodes | Pending Slots | Leaf D Slots |
|-------|------------|---------------|-------------|
| 5     | 63         | 63            | 64          |
| 10    | 1,023      | 1,023         | 2,048       |
| 15    | 32,767     | 32,767        | 65,536      |
| 20    | 1,048,575  | 1,048,575     | 2,097,152   |

### 3.2 Absorption Capacity

The tree can always absorb more nodes than it currently contains:

```
Full tree of depth d:
  Leaf nodes = 2^d
  Each leaf has D1:(empty) D2:(empty) = 2 open D slots
  Available D slots at leaves = 2^(d+1)
  Available P slots (1 per node) = 2^(d+1) - 1

  Total absorption = D slots + P slots > 3× current nodes
```

Every new node that fills a D slot creates 2 new D slots at the next level. The tree can never fill up. Growth is exponential and self-sustaining.

### 3.3 Pending Node Availability

Pending nodes are practically never exhausted:

```
For P slots to be full:
  Number of newcomers waiting > total nodes in tree

  With 1,000 nodes: 1,000 P slots
  All 1,000 would need new nodes simultaneously.

  In practice: arrivals are staggered, migrations to D are fast,
  P exhaustion is a theoretical impossibility.
```

### 3.4 Tick Propagation Depth

The real constraint is not capacity but propagation latency:

```
Tick latency = depth × per-hop round-trip time

Per-hop (send tick + receive approval):
  Same region:      ~50ms
  Cross continent:  ~200ms
  Average:          ~100ms

| Nodes     | Depth | Propagation Time |
|-----------|-------|-----------------|
| 100       | ~7    | ~700ms          |
| 1,000     | ~10   | ~1 second       |
| 10,000    | ~14   | ~1.4 seconds    |
| 100,000   | ~17   | ~1.7 seconds    |
| 1,000,000 | ~20   | ~2 seconds      |
```

Even with 1 million Nabla nodes, tick propagation completes within 2 seconds. This is well within the maturity window.

**Comparison with gossip protocols:** Research shows Bitcoin's random gossip takes ~12 seconds to propagate an 80KB block to 90% of ~15,000 nodes (Croman et al., 2016; Park et al., 2019). AXIOM's directed tree cascade achieves comparable coverage in ~1.4 seconds for similar node counts because the path is deterministic, not probabilistic.

### 3.5 Wallet State Gossip Propagation (Push-Epidemic)

The TARDIS tree cascade (§3.4) propagates **tick hashes** — a deterministic
structure with known depth. **Wallet state updates** (registrations from
`/register`) use a separate mechanism: push-based epidemic gossip. When a
writer node accepts a registration, it immediately floods the update to all
connected peers (no anti-entropy wait). Each peer that receives a novel
update forwards it to its own peers.

**Propagation model.** For N nodes with fanout f (peers per node), the
number of gossip rounds to reach all nodes is:

```
rounds ≈ ceil(log_f(N))
```

Each round = 1 network hop (RTT + processing). With deduplication, each
node processes each update at most once.

**Per-round latency (empirical estimates):**

```
Same region (single cloud AZ):    1–5ms RTT + ~5ms processing ≈ 10ms
Cross-region (e.g., US ↔ EU):     80–120ms RTT + ~5ms processing ≈ 110ms
Global (e.g., US ↔ Asia):         150–250ms RTT + ~5ms processing ≈ 205ms
```

**Estimated propagation time (fanout f = 10):**

| Nodes  | Rounds (log₁₀N) | Same region | Multi-region | Global     |
|--------|------------------|-------------|--------------|------------|
| 100    | 2                | ~20ms       | ~220ms       | ~410ms     |
| 1,000  | 3                | ~30ms       | ~330ms       | ~615ms     |
| 10,000 | 4                | ~40ms       | ~450ms       | ~820ms     |
| 50,000 | 5                | ~50ms       | ~550ms       | ~1.0s      |

**p95 / p99 estimates** account for stragglers, retransmission, and TCP
connection setup. Multiply the table values by ~1.5× for p95 and ~2.5×
for p99:

| Nodes  | Global p50 | Global p95 | Global p99 |
|--------|-----------|-----------|-----------|
| 1,000  | ~600ms    | ~900ms    | ~1.5s     |
| 10,000 | ~800ms    | ~1.5s     | ~3s       |
| 50,000 | ~1.0s     | ~2s       | ~4s       |

**Bandwidth at scale.** Each gossip message is ~1 KB (wallet state update).
At 100 TX/sec network-wide with fanout 10, each node processes
~100 messages/sec × ~4 hops ≈ 400 KB/s inbound gossip. Negligible for
modern networks.

**Comparison with external systems:**

| System    | Nodes   | Propagation  | Mechanism                 |
|-----------|---------|-------------|---------------------------|
| Bitcoin   | ~10,000 | 6–12s       | Random push, 80 KB blocks |
| Ethereum  | ~6,000  | 1–6s        | Push gossip, attestations |
| Cassandra | 10,000  | ~13s        | Pull gossip, 1s interval  |
| **AXIOM** | 10,000  | **~0.8–1.5s** | Push-flood, ~1 KB msgs  |

AXIOM's advantage: push-flood on small messages (~1 KB vs 80 KB blocks)
with immediate trigger (no polling interval). The TARDIS maturity window
(25–35 seconds, §4.2) provides 15–25× headroom over the worst-case
global propagation time at 10,000 nodes.

**Soak measurement (v2.11.16-beta42, 10 nodes, single host):** All gossip
invariant checks (5/5) showed 10/10 node convergence within 5 seconds.
Point query latency: 24–60ms per node. YP §4.6 WAIT rate (gossip not yet
propagated at redeem time): ~6% of redeems, all retry-recovered on next
fork. At 10,000 global nodes this rate is projected to rise to 10–15%,
still within the retry budget.

---

## 4. Tick Interval and Maturity Window

### 4.1 Tick Interval

```
TARDIS tick interval: 5 seconds

One tick = one complete cascade cycle:
  UP sends tick → D1, D2, P verify → approvals return → tick complete

  5 seconds allows:
  - Full cascade propagation (up to ~2s for large networks)
  - Time validation window (0-5s forward-only)
  - Network jitter tolerance
  - Gossip reconciliation at each boundary
```

### 4.2 Maturity Window

```
MATURITY_TICKS_MIN = 5   (target — normal network conditions)
MATURITY_TICKS_MAX = 7   (ceiling — stressed/large networks)

Since tick.number is Unix time (seconds):
  Maturity in seconds = maturity_ticks × TICK_INTERVAL (5s)

  Target maturity:  5 × 5 = 25 seconds
  Maximum maturity: 7 × 5 = 35 seconds

A cheque is NOT considered CLEAN until:
  current_tick - registration_tick >= maturity_ticks × TICK_INTERVAL

  (Both current_tick and registration_tick are Unix seconds.
   The difference is real elapsed time, not a counter gap.)

Before maturity:
  Cheque is SCARRED (registered but not mature)
  Receiver decides whether to accept the risk

After maturity:
  Nabla nodes have reconciled ≥5 times
  If no conflict detected → CLEAN
  If conflict detected → REJECTED
```

Dynamic maturity adapts between MIN and MAX based on network size and peer count (see implementation). Small networks settle quickly (5 ticks). Large networks with many hops may need up to 7 ticks for gossip to fully propagate. Beyond 7 ticks indicates a network health problem, not a transaction problem.

### 4.3 Maturity Enforcement

Core enforces maturity at redeem time:

```
Redeem validation (Nabla check):

  Registered + matured (≥25s elapsed) + no conflict  → CLEAN ✅
  Registered + conflict found                         → REJECTED ✗
  Registered + not mature yet (<25s)                  → SCARRED ⚠ (wait)
  NOT registered at all                               → SCARRED ⚠ (unverified)
```

The maturity window guarantees that Nabla gossip has propagated across the entire network before any cheque can achieve CLEAN status. During 5–7 tick intervals (25–35 seconds of real time), any double-spend conflict will surface and be detected.

### 4.4 Cheque Lifecycle with Maturity

```
All tick values are Unix time (seconds). Example using T₀ = 1740163800.

T₀ + 0s:   Alice spends → k=3 validators witness → registers with Nabla
T₀ + 5s:   First gossip cycle complete (tick +1)
T₀ + 10s:  Second gossip cycle — most Nabla nodes have the record
T₀ + 15s:  Third gossip cycle — conflicts detectable
T₀ + 20s:  Fourth gossip cycle — all Nabla nodes have the record
T₀ + 25s:  TARGET maturity reached (5 ticks)               ← NORMAL
T₀ + 30s:  Sixth cycle — safety margin for large networks
T₀ + 35s:  MAXIMUM maturity reached (7 ticks)              ← CEILING

Bob redeems at T₀ + 25s:
  Bob's Nabla node: (current_tick - registration_tick) = 25s ≥ 25s → CLEAN ✅

If Alice double-spent:
  TX₂ registered on different Nabla node at T₀
  By T₀ + 10–15s: gossip reveals conflict
  Both registrations marked REJECTED
  Bob's Nabla node at T₀ + 25s: conflict found → REJECTED ✗
  Alice gained nothing.
```

### 4.5 Justification: 25-Second Maturity Is Acceptable

Research on customer payment tolerance supports a 25-second verification window.

**Actual payment transaction times (current systems):**

| Method | Time |
|--------|------|
| Contactless card tap | 2-5 seconds |
| Chip + PIN | 8-15 seconds |
| Cash (counting change) | 10-20 seconds |
| Bitcoin (1 confirmation) | ~10 minutes |
| Bank wire transfer | 1-3 business days |

**Customer tolerance studies:**

A survey of 13,000 customers found that 79% were extremely or very satisfied with checkout wait times of approximately four minutes or less. Satisfaction dropped considerably after four minutes across all retail channels including grocery, electronics, and department stores (Box Technologies / Retail Wire, 2010).

Research on customer satisfaction and waiting shows that customers tolerate waiting longer than expected up to a certain point, and that waiting shorter than expected substantially increases satisfaction (Journal of Marketing Research, Schlereth et al., 2023).

The petroleum industry requires sub-second credit card authorization because customers will leave if approval takes too long, demonstrating that critical infrastructure providers already think carefully about transaction latency (Box Technologies / Retail Wire, 2010).

A study of over 4,000 point-of-sale transactions using digital chronography found that cash remains the fastest payment method, while contactless cards and NFC mobile payments are comparably fast (Polasik & Piotrowski, 2013).

**AXIOM positioned against existing systems:**

| System | Verification Time | Security Model |
|--------|------------------|----------------|
| Card tap (NFC) | 2-5 seconds | Probabilistic (chargebacks exist) |
| Chip + PIN | 8-15 seconds | Probabilistic (chargebacks exist) |
| AXIOM (25s maturity) | ~25-49 seconds | Deterministic (clean or rejected) |
| Bitcoin (1 conf) | ~10 minutes | Probabilistic (reorg possible) |
| Bitcoin (6 conf) | ~60 minutes | Probabilistic (very unlikely reorg) |
| Bank transfer | Hours to days | Institutional trust |

AXIOM's 25-49 second total time is slower than card tap but provides deterministic finality that no card network offers (card payments can be charged back for months). The verification window is well within the 4-minute customer tolerance threshold.

---

## 5. Transaction Timing Simulation

### 5.1 Coffee Purchase (Email Carrier — ANTIE)

Complete timeline for buying a coffee using AXIOM with email-based transport:

```
SCENARIO: Buyer purchases coffee from seller using AXIOM
CARRIER: ANTIE (email-based, sequential validator communication)
EMAIL DELIVERY: ~1-3 seconds per hop (typical)

T=0s      Seller presents QR code
          Buyer scans → phone builds transaction

          VALIDATOR 1 (round trip):
T=0-3s    Phone → email → V1           (email delivery ~1-3s)
T=3-4s    V1 processes via Core         (Core validation ~1s)
T=4-7s    V1 → email → Phone           (receipt to buyer)
T=4-7s    V1 → email → Seller          (receipt to seller, PARALLEL)

          VALIDATOR 2 (round trip):
T=7-10s   Phone → email → V2
T=10-11s  V2 processes
T=11-14s  V2 → email → Phone
T=11-14s  V2 → email → Seller          (PARALLEL)

          VALIDATOR 3 (round trip):
T=14-17s  Phone → email → V3
T=17-18s  V3 processes
T=18-21s  V3 → email → Phone
T=18-21s  V3 → email → Seller          (PARALLEL)

T=21s     Phone has k=3 receipts ✓
          Seller has k=3 receipts ✓

          NABLA REGISTRATION (only after k=3 confirmed):
T=21-24s  Phone registers with Nabla node
          (Must wait for k=3 — if spending failed, registration
           of partial TX would corrupt wallet state on Nabla)

T=24s     Nabla receives registration
          TARDIS heartbeat begins propagating

T=24-49s  MATURITY WINDOW (5 ticks × 5 seconds = 25s)
          Seller's phone shows: "Payment received, verifying..."

T=49s     Maturity reached → CLEAN ✅

TOTAL: ~49 seconds (typical, 3s email delivery)
```

**Note on validator communication:** Each validator requires a full round trip (send TX → process → receive receipt) before the next validator can be contacted. This is because each subsequent validator performs S-ABR overlap verification against previous witnesses. The 3 round trips are sequential, not parallel.

**Note on Nabla registration timing:** The buyer MUST wait for k=3 confirmation before registering with Nabla. If registration happens after only 1-2 receipts and a subsequent validator rejects the transaction, Nabla would have a record of a spend that never completed, corrupting wallet state.

**Note on receipt delivery:** Validators send receipts to BOTH the buyer AND the seller directly (Yellow Paper protocol). The seller begins receiving receipts from T=7s, not T=21s. The seller sees progressive confirmation: 1/3, 2/3, 3/3.

### 5.2 Email Delivery Assumptions

Email delivery time varies. Research shows:

Direct SMTP routing typically completes in under 3 seconds for well-configured servers (SMTP2GO, 2025; Campaign Refinery, 2024). The fastest measured email deliveries complete in approximately 0.3 seconds end-to-end (GreenArrow Email, 2020). Average email routing and processing takes approximately 0.1-0.15 seconds for the network transit portion, with server-side processing adding variable delay (Cables & Kits, 2025).

However, delays of minutes or hours are possible due to spam filtering, greylisting, server queuing, and network congestion (Ask Leo, 2018; SMTP2GO, 2025).

| Email Speed | Per Round Trip | 3 Round Trips | + Maturity | Total |
|-------------|---------------|---------------|------------|-------|
| Fast (1s) | 3s | 9s | 25s | ~34s |
| Typical (3s) | 7s | 21s | 25s | ~49s |
| Slow (5s) | 11s | 33s | 25s | ~58s |

### 5.3 Direct HTTPS Carrier (Future)

With a direct HTTPS gateway (sub-second delivery):

```
T=0-1s    TX to V1, process, return       (~200ms × 2 + 1s process)
T=1-2.5s  TX to V2, process, return
T=2.5-4s  TX to V3, process, return
T=4-5s    Register with Nabla
T=5-30s   Maturity window (25s)

TOTAL: ~30 seconds with direct carrier
```

### 5.4 Practical User Experience

For small purchases, the seller does NOT need to wait for maturity:

```
SMALL PURCHASE ($5 coffee):
  T=0s:     Scan QR
  T=7-21s:  Receipts arrive at seller (progressive 1/3, 2/3, 3/3)
  T=21s:    k=3 confirmed → seller hands over coffee (SCARRED)
  T=49s:    Maturity confirms in background → CLEAN

  Seller accepted SCARRED for a $5 item. Rational business decision.
  If double-spend: seller loses $5. Acceptable risk.

LARGE PURCHASE ($500 electronics):
  T=0s:     Scan QR
  T=21s:    k=3 confirmed → seller waits for maturity
  T=49s:    CLEAN → seller hands over goods

  49 seconds total. Well under 4-minute customer tolerance.

HIGH VALUE ($50,000 vehicle):
  Wait for CLEAN + additional ticks for extra confidence.
  No different from a bank requiring extra verification for large transfers.
```

This mirrors real-world payment acceptance:
- Cash: instant acceptance, no verification (counterfeit risk)
- Credit card small purchase: no PIN required (fraud risk accepted)
- Credit card large purchase: PIN + ID required (additional verification)
- Wire transfer: hours of verification for large amounts

---

## 6. Double-Spend Defense (TARDIS + Nabla Combined)

### 6.1 Complete Defense Stack

```
Layer 1 — S-ABR (Witness Time):
  Catches double-spend when validators overlap.
  Effective for sequential spends from same wallet.

Layer 2 — Nabla Registration (Post-Witness):
  Sender MUST register with Nabla after k=3 confirmation.
  If not registered → cheque is SCARRED → receiver accepts at own risk.
  Once registered → Nabla catches conflict if double-spend attempted.

Layer 3 — TARDIS Maturity (Redemption):
  Receiver cannot redeem CLEAN until 5 ticks (25s) after registration.
  During maturity window, Nabla gossips and reconciles.
  Any conflict surfaces before maturity expires.

Layer 4 — FACT Chain (Forensic):
  Permanent cryptographic proof of transaction history.
  Fork in FACT chain = undeniable proof of double-spend.
  Used for VBC revocation of corrupt validators.
```

### 6.2 Alice's Attack Options

```
Option 1: Register TX₁ only
  TX₁ → CLEAN (after maturity)
  TX₂ → SCARRED (never registered)
  Charlie rejects scarred cheque.
  Alice gains nothing extra.

Option 2: Register both TX₁ and TX₂
  Both registered on different Nabla nodes.
  Nabla gossip detects conflict within 1-3 ticks.
  Both marked REJECTED.
  Neither Bob nor Charlie can redeem.
  Alice gains nothing. Both cheques are dead.

Option 3: Register neither
  Both cheques SCARRED.
  Neither Bob nor Charlie accepts (rational behaviour).
  Alice gains nothing.

Option 4: Register TX₁, give TX₂ to Charlie as scarred
  TX₁ → CLEAN (after maturity)
  TX₂ → SCARRED → Charlie might accept for small amounts
  If Charlie accepts and TX₂ turns out to be double-spend:
    Charlie's loss. Protocol warned him (SCARRED).
    Protocol is not at fault.
```

### 6.3 Economic Incentives

If Alice double-spends and both cheques are caught:

```
Alice had 1000 atoms.
Created two 1000-atom cheques (double-spend attempt).
Both REJECTED by Nabla.
Neither redeemable as CLEAN.

Receivers burn the rejected cheques:
  1000 atoms destroyed from total supply.
  Alice LOST her money.
  System supply DECREASED (deflationary).

Double-spend doesn't create inflation — it creates DEFLATION.
The attacker loses money. The system gets stronger.
```

Note: The receiver who accepted a scarred cheque and gave goods is the victim. The protocol cannot prevent bad business decisions. It can only provide accurate information (CLEAN / SCARRED / REJECTED) for the receiver to make informed choices.

---

## 7. Rollback Defense

### 7.1 The Rollback Attack

The existential threat to AXIOM (Security Research Document Section 6):

```
T=1: Alice's wallet = 10,000 AXC (state S1)
T=2: Alice spends 9,000 → balance = 1,000 (state S2)
T=3: Alice spends 500 → balance = 500 (state S3)

Months later:
  Corrupt validator rolls wallet back to S1.
  Alice has 10,000 again.
  Previous recipients still have their 9,500.
  Total AXC inflated. Money printed from nothing.
```

### 7.2 Nabla + TARDIS Solve Rollback

This attack was previously marked "UNSOLVED" in the Security Research document. With Nabla + TARDIS, it is now solved:

```
T=1: Alice at S1 → registered on Nabla (balance 10,000)
T=2: Alice spends → S2 → registered on Nabla (balance 1,000)
T=3: Alice spends → S3 → registered on Nabla (balance 500)

Months later, corrupt validator tries rollback to S1:
  Alice takes S1 receipt to new validators.
  Receiver checks Nabla.
  Nabla says: "Alice's current state is S3, balance 500"
  S1 doesn't match current state → REJECTED.
```

Nabla IS the "someone who still remembers the newer state" that Section 6.3 of the Security Research document identified as necessary. Alice was required to register each spend with Nabla (otherwise her cheques would be SCARRED and rejected by receivers). Those registrations are permanent — Nabla remembers.

### 7.3 Nabla Data Retention for Rollback Prevention

AXIOM cheques follow the 銀行本票 (cashier's cheque / bank draft) and traveller's cheque model:

- Money has already left the sender's wallet. Spend is spend. No rollback.
- Cheques never expire. (Traveller's cheques have no expiration date per American Express, Visa, and industry standard. Research confirms this: traveller's cheques remain backed by the issuer indefinitely.)
- Lost cheque = lost money (same as losing cash or a cashier's cheque).

Because cheques never expire, Nabla must retain current wallet state indefinitely. However, this is practical:

```
Nabla stores ONE record per wallet (current state only):
  wallet_id:       bytes32
  current_state:   bytes32
  balance:         uint64
  last_tick:       uint64

  Size per wallet: ~100 bytes
  1 million wallets: ~100 MB
  100 million wallets: ~10 GB

  Old states are REPLACED, not accumulated.
  Storage grows with number of wallets, NOT number of transactions.
  10 GB for 100 million wallets is trivial even for 100 years.
```

### 7.4 Nabla Node Continuity

Individual Nabla nodes come and go, but data survives through replication:

```
Year 1:  N1, N2, N3 running, holding wallet states
Year 3:  N4 joins → syncs from N1, N2, N3 (full state copy)
Year 5:  N1 dies → doesn't matter, N2, N3, N4 have the data
Year 6:  N5 joins → syncs from N2, N3, N4
Year 8:  N2, N3 die → N4, N5 still have everything

Data never dies. New nodes sync before old ones disappear.
Each tick's state incorporates all prior ticks, forming a forward-only chain.
```

TARDIS tick serves as the sync checkpoint:

```
N5 joins at tick 50,000.
N5 asks N4: "give me wallet state snapshot at tick 50,000"
N4 sends complete state + TARDIS cascade proof.
N5 verifies: cascade signatures prove snapshot legitimacy.
N5 is now fully synced and operational.
```

---

### 7.6 Tick Lineage Verification (defeats the self-signed-tick rollback)

**Layer:** Nabla (tick signatures are NBC-bound Ed25519, produced + verified inside Nabla).
**CoreID impact:** none. **Closes:** the self-signed-high-tick roll-back (a forged tick with an
arbitrary `number`/`root_hash` seeding a fork; see `AXIOM_REPORT_KnownIssues.md` KI#34).

**The gap.** TARDIS is a **closed ring** — no root, every node has an upstream
(`new_with_ring_links` wires upstream+downstream at bootstrap, "no special treatment"). With no
privileged root, all tick integrity rests on **verifiable lineage**. Each tick already carries
`prev_sig` (the grandparent's signature) + `grandparent_pk`, but historically the grandpa-tick rule
only *presence*-checked them (`chain_present = grandparent_pk.is_some() && !prev_sig.is_empty()`) —
so a self-signed tick with garbage `prev_sig` passed. A cryptographic check was deferred because
"the grandparent's signed payload isn't carried on the wire."

**The property.** A tick `T` from sender `P` claiming grandparent `GP` is accepted only if
`prev_sig` is a valid Ed25519 signature by `GP`'s NBC-bound key over `GP`'s **actual, fresh** tick,
**and** `P` appears in `GP`'s signed child set. Because every honest node enforces this, lineage is
**inductive** — a node can only *relay* real lineage, never fabricate it. One-hop suffices (there is
no root to chain to).

**Mechanism.**
- The tick signature is over a fixed-size **commitment** `H(number ‖ timestamp_ms ‖ upstream_pk ‖
  payload ‖ downstream_approvals ‖ prev_sig ‖ child_pks ‖ H(oods_tardis))` — a digest-signature is
  as sound as signing the raw bytes, keeps the lineage proof ~150 B, and attests `oods_tardis` by
  its hash without re-carrying it.
- The tick carries `GP`'s commitment preimage (`gp_*` fields) so the receiver recomputes `GP`'s
  commitment and verifies `prev_sig` against `GP`'s NBC key.
- **Checks (every tick):** `gp_key` is a known NBC · `prev_sig` verifies · **freshness**
  `|gp_number − tick.number| ≤ 2–3` (delivery-delay tolerance; both stamp NTP-synced `now_secs`) ·
  **strict-parent** `P ∈ gp_child_pks` (GP cryptographically attested it parented P — closes lineage
  *borrowing*).
- **Enforcement:** a tick that *claims* lineage but fails verification is **hard-rejected** (drop;
  do not adopt its `root_hash`; count toward KI#34 fork-ban evidence). No lineage claimed
  (bootstrap/degraded) → the existing soft `grandpa_miss` path.

**Status — SHIPPED + live-validated 2026-07-08 (Nabla-only, CoreID unchanged).**
- **Phase 1 (master `e2082e55`):** de-risked observation — carried the grandparent's existing
  `tick_sign_payload` and verified `prev_sig` against it with the current signature scheme (no
  format change), **log-only**. Confirmed the crypto on live traffic (LINEAGE-OK flowing, 0 FAIL,
  `drift=0`) before touching the tick signature.
- **Phase 2 (master `24ed9ee3`):** the compact **commitment** + `child_pks` (strict-parent) +
  flip log→**enforce** (`[LINEAGE-REJECT]` hard-drop). Signing-format change → deployed via a
  full-mesh restart. Live: 10/10 up, roots=1, 0 honest false-rejects, TICK-SIG-FAIL=0.
- **Fork-ban wiring (master `ae31d018`):** a `[LINEAGE-REJECT]` accuses the sender into the
  KI#34/KI#37 quarantine-consensus channel (`flag_lineage_violation` → `QuestionableAlert`,
  rate-limited + deduped), gated by **anti-framing** (accuse only if the sender's own tick-sig
  verifies — a spoofed `upstream_pk` is dropped, never accused). Honest traffic: 0 accusations.
- **Adversarial validation (harness at master `c98e6b3a`, since removed):** self-signed injection
  → `LINEAGE-REJECT sig_ok=false`; stale gp tick → `fresh=false` (drift=1000); unknown gp → `SKIP`
  (not rejected). Tests: nabla lib 719/0, crypto 7/0, tardis 93/0.

**Why this is the *only* fork-related piece TARDIS needs — a tree fork is BENIGN.** TARDIS is a
**clock, not a ledger**: the tick `number` is unix-seconds validated against each node's own NTP
clock, so two forked branches keep the *same correct time*; wallet state / double-spend / txid
consume-once merge via **gossip + SMT + anti-entropy** (KI#38), **not** tree topology, and
transactions never compare against a tick's tree/branch. So lineage verification hardens the
*authorized-time* guarantee (each tick descends from a real bonded-writer cascade); it does not —
and need not — resolve state forks (those are the KI#34 consume-once / AE defenses). When the
partition heals, the gossip/state merge is what matters and the TARDIS tree just reattaches on top.

**Considered and DROPPED:** up-aggregation of the writer set (a network-wide verified-writer total
to arbitrate a *branch* at merge) — unnecessary (a losing tree still tells correct time; the merge
is a gossip/state event, not a tree decision) and redundant with gossip-OODS. Not to be built.
Remaining ideal (not required): Core-mediated tick signing (§6.1) — this design stays NBC-Ed25519.

---

## 8. Cheque Status Model

### 8.1 Status Definitions

```
CLEAN:     Nabla confirms registration, maturity window passed,
           no conflict detected.
           → Safe to accept.

SCARRED:   No Nabla registration found, OR registration exists
           but maturity window has not passed, OR Nabla node
           has no data (stale/offline).
           → Accept at own risk. May heal to CLEAN with time.

REJECTED:  Nabla found conflicting registrations for the same
           consumed_state_id. Double-spend detected.
           → Do NOT accept. Receiver can burn the cheque.
```

### 8.2 Scar Healing

Most scars are temporary:

```
Tick 100:  TX happens, not registered yet         → SCARRED
Tick 101:  Sender registers with Nabla
Tick 106:  5 ticks matured, no conflict            → CLEAN ✅

The scar was temporary. Just needed time.
```

Permanent scars occur when:
- Sender never registers with Nabla (intentional or lost connectivity)
- Double-spend detected (transitions to REJECTED, not healable)
- All Nabla nodes that held the record have died (data loss)

### 8.3 Receiver Risk Model

The receiver decides their risk tolerance based on cheque status and transaction value:

```
Coffee shop ($5):      SCARRED? Accept. Low risk.
Electronics ($500):    SCARRED? Wait for CLEAN.
Car dealership ($30K): CLEAN + extra ticks matured.
House purchase ($500K): CLEAN + check multiple Nabla nodes.
```

This mirrors existing payment acceptance practices. The protocol provides information; the receiver makes business decisions.

---

## 9. Security Analysis

### 9.1 Corrupt Nabla Node

A corrupt Nabla node could attempt to:

```
Attack: N_evil accepts both TX₁ and TX₂ registrations without
        detecting conflict, enabling double-spend.

Defense: Receiver should check MULTIPLE Nabla nodes.
         Even if N_evil is corrupt, honest nodes will catch the
         conflict once gossip propagates.

         TARDIS ensures gossip propagates within 5 ticks.
         Maturity window ensures the check happens after propagation.
```

### 9.2 Stale Nabla Node

```
Attack: Receiver queries a stale Nabla node that hasn't synced.
        Stale node says "no record" → SCARRED.

Defense: SCARRED is the correct response. The receiver is warned.
         A stale node cannot produce a false CLEAN.
         No registration = no confidence = scar.
```

### 9.3 Network Partition

```
Attack: Network splits. Alice registers TX₁ in partition A,
        TX₂ in partition B. Neither partition knows about the other.

Defense: Both transactions are SCARRED until partitions heal.
         Receivers in each partition see only their local registration.
         Once partition heals, TARDIS cascade reconnects, gossip
         reconciles, conflict detected → both REJECTED.

         Maturity window means: if partition lasts longer than 25s,
         cheques in both partitions remain SCARRED (no CLEAN possible
         without full network connectivity).
```

### 9.4 Cascade Signature Forgery

```
Attack: Node forges tick signatures to claim a later tick than reality.

Defense: Each tick carries the chain of previous signatures.
         Verifier traces: sig_current → sig_parent → ... → sig_tree_root.
         The chain terminates at the current tree root, which may be any
         node whose upstream is absent.
         Forging requires compromising all nodes in the chain.
         One honest node in the path = forgery detected.
```

### 9.5 Comparison with Bitcoin

Double-spend probability analysis (from AXIOM v2.6.0 security analysis):

| System | P(double-spend) | Time to Finality | Security Model |
|--------|-----------------|------------------|----------------|
| AXIOM (k=3) | ~2.9×10⁻⁶ | ~49 seconds (email) | Structural (network isolation + Nabla) |
| Bitcoin (6 conf, q=0.1) | ~6×10⁻⁵ | ~60 minutes | Economic (hashrate cost) |
| Bitcoin (6 conf, q=0.25) | ~7×10⁻³ | ~60 minutes | Economic (hashrate cost) |

AXIOM achieves better security (~20× lower double-spend probability) with ~70× faster finality compared to Bitcoin at standard parameters.

---

## 10. Protocol Constants

```
TICK_INTERVAL                     = 5 seconds
MATURITY_TICKS_MIN                = 5 (target — 25 seconds)
MATURITY_TICKS_MAX                = 7 (ceiling — 35 seconds)
MATURITY_WINDOW                   = 25–35 seconds (TICK_INTERVAL × maturity ticks)
TIME_BUFFER                       = 0–5 seconds (tick must be in the past, never future)
D_RESERVATION_TICKS               = 10 (offline slot reservation)
MAX_TREE_DEPTH                    = 30 (advisory, not enforced)
GENESIS_COUNT                     = 10 (all genesis Nabla nodes)
PARENTLESS_TIMEOUT_TICKS          = 6
WRITER_GRACE_TICKS                = 3
WRITER_SETTLE_TICKS               = 10 (minimum ticks with new parent before writer check)

# Tree rotation (§2.4)
PARENT_ROTATION_INTERVAL_TICKS    = 17280 (24h). Testing: 50.
PARENT_ROTATION_JITTER_TICKS      = 1440 (~2h). Testing: 20.
CHILD_ROTATION_INTERVAL_TICKS     = 51840 (72h). Testing: 150.
CHILD_ROTATION_JITTER_TICKS       = 14400 (~2h). Testing: 20.

# Tree rebalancing (§2.5)
REBALANCE_COOLDOWN_TICKS          = 10 (50 seconds)
MAX_REBALANCE_PER_TICK            = 5 (prevents churn storms)
```

---

## 11. Implementation Notes

### 11.1 Seller QR Code with Nabla Hint (Client Implementation)

This is NOT a protocol requirement but a recommended client implementation pattern that significantly improves user experience:

```
Seller's QR code includes a Nabla hint:
{
  wallet_id:    "seller_wallet_id",
  amount:       500,
  nabla_hint:   "nabla-node-xyz.example.com"
}

Buyer's phone reads the hint:
  → Registers TX with seller's recommended Nabla node
  → Seller checks the SAME Nabla node
  → Both parties see the same record instantly
  → No cross-node gossip delay for initial confirmation
  → Maturity still enforced (gossip to other nodes for CLEAN)
```

This reduces the seller's perceived wait time because the seller's local Nabla node has the registration immediately. The maturity window still applies for CLEAN status, but the seller sees "registered, awaiting maturity" instead of "no data yet."

There is no security risk from the seller recommending a Nabla node. Even if the seller recommends a corrupt Nabla node:
- The buyer's registration is also gossiped to all other Nabla nodes
- Other receivers checking other Nabla nodes will still see the record
- The corrupt Nabla node cannot prevent gossip propagation

### 11.2 Aligned Incentives: Nobody Wants Scarred

Both buyer and seller have aligned incentives to achieve CLEAN status:

```
BUYER wants CLEAN because:
  - Seller may reject SCARRED cheque → buyer gets no goods
  - Repeated scarred payments damage buyer's reputation
  - No rational buyer benefits from paying with scarred money

SELLER wants CLEAN because:
  - CLEAN = guaranteed, verified payment
  - SCARRED = risk of double-spend
  - Seller naturally prefers verified payments

ATTACKER (double-spender) is the ONLY party who might want scarred:
  - But both cheques end up REJECTED (not just scarred)
  - Attacker loses money (deflationary)
  - No rational attacker benefits
```

This alignment mirrors real-world behaviour: nobody checks a $5 bill for counterfeits, but everyone verifies a $500 payment. The protocol provides the information; rational actors naturally use it proportionally to the transaction value.

---

## 12. Open Questions

```
1. Tick interval adaptive adjustment: Should tick interval change based
   on network size or load?
2. Seed retirement protocol: Exact mechanism for seeds to hand off to
   successor root nodes.
3. ~~Tree rebalancing~~ RESOLVED (v0.6): §2.5 implements protocol-level
   rebalancing. Leaves volunteer to move from dc=2 parents to dc=1
   parents using only local state. §2.4 writer rotation provides
   long-term structural shuffling. Both mechanisms proven in simulation.
4. ~~Cross-tree verification~~ RESOLVED (v0.8): §2.12 Seed Epoch Beacon
   provides cross-branch verification. Every node receives proof of seed
   connectivity via beacon propagation. UPDATE (v0.9): §2.12 superseded
   by §2.16.3 Parent Tick Liveness + §2.10.5 Reachability Guard.
5. ~~Partition recovery without seed beacons~~ RESOLVED (v0.9): Partition
   recovery is a mesh-layer concern, not a TARDIS concern. §2.16.4
   documents the human bridge mechanism. Already implemented and tested.
6. Incentive model: What motivates operators to run Nabla nodes?
7. Minimum Nabla node count: What is the minimum number of Nabla nodes
   for the network to be considered operational?
```

---

## 13. Glossary

| Term | Definition |
|------|-----------|
| TARDIS | Temporal Anchor for Rollback Detection and Integrity Sync. Cascade heartbeat inside Nabla network. |
| Tick | TARDIS counter. Advances every 5 seconds via cascade. Provides temporal ordering. |
| Cascade | The propagation path of ticks through the Nabla tree: UP → D1, D2, P → their subtrees. |
| Genesis Node | One of 10 genesis Nabla nodes forming the initial ring topology. Regular Nabla nodes whose only distinction is being launched first with well-known addresses. |
| UP | Upstream parent slot. Receives ticks from. Exactly 1 per node. |
| D1, D2 | Downstream child slots. Sends ticks to. Approves parent's tick. |
| P | Pending slot. Receives ticks, fully functional, seeking permanent D slot. |
| E | Enquiry slot. Stateless. Connect, query topology, disconnect. |
| Maturity | The required wait time (5 ticks / 25s) before a cheque can be CLEAN. |
| CLEAN | Cheque status: registered, matured, no conflict. Safe to accept. |
| SCARRED | Cheque status: unverified or immature. Accept at own risk. |
| REJECTED | Cheque status: double-spend conflict detected. Do not accept. |
| WRITER | Node with D1+D2 children (~50% of network). Has legitimate approved tick. Records transactions. |
| READER | Leaf node (~50% of network). Serves enquiries using parent's approved tick as freshness proof. |
| Tree Root | Any alive node whose upstream is absent or dead. BFS reachability starts from tree roots. |
| Parent Rotation | Every 24h, a writer drops its slowest child (most approval misses). Anti-collusion + performance eviction. |
| Writer Rotation | Every 72h, a writer releases its children and detaches, scattering all into orphan recovery. Anti-ossification. |
| Rebalancing | Leaf volunteer mechanism: leaf detaches from dc=2 parent, re-enters recovery, lands on dc=1 parent → +1 writer. |
| Rotation Jitter | Per-node random offset (derived from PK) added to rotation intervals. Prevents synchronized mass-rotation. |
| Reservation | D slot held for offline node for X ticks before being freed. |
| Isolated | A node with upstream set but no path to any tree root. Detected by reachability check. |

---

## 14. References

### AXIOM Internal Documents

| Document | Relevance |
|----------|-----------|
| Yellow Paper v2.6.0 | Base protocol. Validator witnessing, S-ABR, cheque format. |
| YPX-001 v0.1 | FACT Chain specification. TARDIS tick field in FACT links. |
| YPX-002 v0.1 | Nabla Verification Protocol. Registration, gossip, BANNED mechanism. |
| Security Research v0.1 | Full design rationale. Previous TARDIS designs. Rollback attack analysis. |
| White Paper v2.28.11 | AXIOM philosophy and high-level architecture. |

### External References

| Reference | Topic |
|-----------|-------|
| Croman et al., "On Scaling Decentralized Blockchains" (2016) | Bitcoin block propagation: ~12s for 80KB block to 90% of nodes |
| Park et al., "Nodes in the Bitcoin Network" (IEEE Access, 2019) | Bitcoin transaction propagation: 6 nodes in first 13 seconds, then increased variance |
| Kim et al., "Reducing the propagation delay of compact block in Bitcoin network" (Int'l J. Network Management, 2024) | Bitcoin compact block relay timing analysis |
| PLOS ONE, "Cloud-native simulation framework for gossip protocol" (2025) | Multi-zone gossip: propagation times increase significantly beyond 70 nodes across geographic zones |
| High Scalability, "Gossip Protocol Explained" (2024) | Gossip interval of 10ms can propagate across large data centers in ~3 seconds; 128 nodes consume <2% CPU |
| Demers et al., "Epidemic Algorithms for Replicated Database Maintenance" (1987) | Original gossip protocol design and epidemic propagation mathematics |
| Box Technologies / Retail Wire, "Checkout Time Limit" (2010) | 13,000-customer survey: 79% satisfied at ≤4 minutes checkout; petroleum requires sub-second authorization |
| Schlereth et al., Journal of Marketing Research (2023) | Asymmetric satisfaction response: waiting shorter than expected substantially increases satisfaction |
| Polasik & Piotrowski, "Time Efficiency of Point-of-Sale Payment Methods" (2013) | 4,000+ POS transactions: cash fastest, contactless NFC comparable |
| American Express, Travelers Cheques policy | Traveller's cheques have no expiration date, remain backed indefinitely |
| GreenArrow Email, "Transactional Email Speed" (2020) | Fastest email delivery: ~0.3 seconds; median under 1 second for optimized SMTP |
| SMTP2GO, "When is a Delay Actually a Delay?" (2025) | Most emails delivered within seconds; 15-30 minute delays indicate problems |
| Cables & Kits, "How Fast Does Email Travel?" (2025) | Email routing/processing averages 0.1-0.15 seconds; server sorting adds variable delay |
| RBI India, cheque validity guidelines (2012) | India: 3-month cheque validity. US UCC: 6-month personal cheques. UK: 6-month convention. |

---

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
