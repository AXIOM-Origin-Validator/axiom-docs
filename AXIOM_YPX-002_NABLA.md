**AXIOM Yellow Paper Extension YPX-002**
## Nabla Verification Protocol

**Official Title:** TrustMesh Wallet State Verification Protocol
**Project:** AXIOM (TrustMesh Architecture)
**Type:** Yellow Paper Extension (Phase 3)
**Version:** 0.1 (Draft)
**Date:** 2026-02-07
**Authors:** AXIOM Origin
**Depends On:** Yellow Paper v2.6.0+ (Phase 1), YPX-001 (FACT and TARDIS, Phase 2)
**Symbol:** ∇ Nabla (Unicode U+2207)
**Symbol Origin:** The nabla symbol (∇) is borrowed from mathematics where it represents the gradient operator — a function that shows the direction of steepest change. In AXIOM, ∇ represents the direction of wallet state change: "where is this wallet now?" The inverted triangle also visually suggests a funnel — many transactions flow in, one current state comes out.

---


---

## 0. Purpose

This document specifies the Nabla Verification Protocol, which adds double-spend protection and rollback prevention to the AXIOM TrustMesh.

Nabla answers the one question the base protocol and FACT chain cannot:

```
Base protocol:  "Is this transaction signed by real validators?"     --> VBC
YPX-001 FACT:   "Is this money traceable to genesis?"                --> FACT chain
YPX-002 Nabla:  "Is this the ONLY spend of this wallet state?"      --> Nabla
```

Nabla is a TrustMesh participant, not a separate system. It uses the same VBC trust chain as validators. TrustMesh operates fully without Nabla. Adding Nabla gives receivers optional (but strongly recommended) double-spend protection.

---

## 1. What Is Nabla

### 1.1 Definition

Nabla is a TrustMesh participant that specializes in wallet state verification. Just as validators specialize in witnessing transactions, Nabla nodes specialize in remembering wallet states.

```
TrustMesh participants:
  Validator:   witness transactions (k=3, local, fast)
  Nabla:       remember wallet states (gossip, query, verify)
  Gateway:     transport messages (ANTIE, UNCLE, COUSIN)
  Core:        cryptographic validation (stateless, always)
  
  All connected by VBC trust chains.
  All part of the same mesh.
```

### 1.2 What Nabla Does

- Stores current state_id and tx_hash per wallet (one entry per wallet)
- Answers one question: "What is this wallet's current state?"
- Syncs with other Nabla nodes via gossip
- Compares root_hash with peers at TARDIS ticks
- Detects and permanently bans double-spend wallets
- Charges query fees (economic model TBD)

### 1.3 What Nabla Does NOT Do

- Does not process transactions
- Does not validate transaction rules
- Does not hold balances
- Does not sign as witness
- Does not run Core logic
- Does not store transaction history
- Does not order transactions

### 1.4 Why Nabla Is NOT a Blockchain

```
Blockchain:                              Nabla:
------------------------------------------  ------------------------------------------
Orders every transaction globally        No transaction ordering
Validates every transaction              Validates nothing (just stores state)
Consensus required BEFORE spending       No consensus -- k=3 sufficient to spend
Mandatory for every transaction          Optional -- receiver's choice to check
Stores full transaction history          Stores ONE value per wallet
Grows with transactions                  Grows with wallets (much smaller)
System stops without it                  TrustMesh operates fully without it
```

---

## 2. Database

### 2.1 Schema

```
Nabla database entry:
  wallet_id:      bytes32     // wallet identifier
  current_state:  bytes32     // latest known state_id
  tx_hash:        bytes32     // hash of last registered transaction
  tick:           uint64      // TARDIS tick of last registration

Entry size: approximately 104 bytes per wallet
```

### 2.2 Size Estimates

```
1 million wallets:    104 MB
10 million wallets:   1.04 GB
100 million wallets:  10.4 GB

No pruning needed. Updates replace, not append.
Database size scales with number of wallets, not transactions.
```

---

## 3. Registration Protocol

### 3.1 Who Registers

The spender registers their own state change. Nobody registers on behalf of the receiver.

```
Sender's job:   register OWN state change after k=3 witnessed TX
Receiver's job: verify sender's registration before accepting
```

### 3.2 Registration Flow

```
1. Sender completes transaction (k=3 signed)
2. Sender sends registration to 1 Nabla node:
     - wallet_id
     - old_state_id
     - new_state_id
     - tx_hash
     - k=3 signatures (proof)
3. Nabla node verifies:
     a. k=3 signatures valid over tx_data
     b. Registration fields match signed tx_data
     c. Wallet exists in database?
        YES: old_state_id matches current --> update
        YES: old_state_id does NOT match --> reject (possible double-spend)
        NO:  first spend ever --> verify k=3 proof --> create entry
4. Nabla node gossips update to peers
5. Sender includes Nabla node ID in cheque
```

### 3.3 Registration Pseudocode

```python
def register(self, registration):
    wallet_id = registration["wallet_id"]
    old_state = registration["old_state_id"]
    new_state = registration["new_state_id"]
    tx_hash = registration["tx_hash"]
    k3_sigs = registration["k3_signatures"]
    tx_data = registration["tx_data"]
    
    # Verify k=3 signatures over tx_data
    if not verify_k3_signatures(k3_sigs, tx_data):
        return {"error": "invalid k=3 proof"}
    
    # Verify registration matches signed tx_data
    if old_state != tx_data.old_state_id:
        return {"error": "old_state mismatch with signed TX"}
    if new_state != tx_data.new_state_id:
        return {"error": "new_state mismatch with signed TX"}
    if tx_hash != hash(tx_data):
        return {"error": "tx_hash mismatch"}
    
    if wallet_id in self.db:
        # Existing wallet
        if self.db[wallet_id].current_state != old_state:
            # §3.3 REGRESSION GUARD: return StateMismatch, do NOT ban.
            # Bans are the exclusive domain of gossip-merge (§7.5)
            # which requires two independent k=3 receipts. A single
            # /register mismatch proves only that this node is
            # behind gossip — a ban here produces false positives.
            return {"error": "StateMismatch"}
        self.db[wallet_id] = {
            "current_state": new_state,
            "tx_hash": tx_hash,
            "tick": registration["tick"]
        }
    else:
        # New wallet, first spend ever
        self.db[wallet_id] = {
            "current_state": new_state,
            "tx_hash": tx_hash,
            "tick": registration["tick"]
        }
    
    self.gossip_update(wallet_id, new_state, tx_hash)
    return {"ok": True}
```

**§3.3 applies to BOTH the TCP wire path AND the HTTP /register
endpoint** (2026-04-14 fix). The HTTP handler
(`handle_http_register` in `nabla/src/bin/nabla_node.rs`) historically
wrote directly to the SMT via `put()` without running
`process_registration`, skipping both the receipt verification AND
the state-chain check. The state-chain check is now mirrored into
the HTTP path: on mismatch, the handler returns `409 Conflict` with
an explicit `{"error": "StateMismatch"}` payload and leaves the
stored state untouched. Receipt verification remains deferred on the
HTTP path (acknowledged trade-off for webclient ergonomics) but
§3.3's no-ban invariant now holds across both entry points.

### 3.4 Wallet Lifecycle on Nabla

```
1. Wallet created (genesis, pool claim, or receiving money)
   Nabla knows nothing. That is fine.

2. Wallet SPENDS for the first time
   Spender registers with Nabla.
   Nabla: "wallet not found" --> verify k=3 --> create entry.

3. Wallet spends again
   Spender registers with Nabla.
   Nabla: "wallet exists" --> verify old_state matches --> update.
```

No day-zero initialization. No genesis special cases. All wallets follow the same path. Genesis wallets start at 0 balance, receive from pool or others, and appear on Nabla when they first spend.

---

## 4. Verification Protocol

### 4.1 Receiver's Responsibility

Verification is the receiver's job. Not mandatory at the protocol level. But strongly recommended by the client application.

```
Receiver's job:  check Nabla before accepting
Did not check?   Receiver's risk. Their loss if money is fake.
```

Same as the real world: a shop that accepts cash without checking accepts the risk of counterfeits.

### 4.2 Verification Flow

```
RECEIVER PROTOCOL (client enforced):

  1. Core verification (stateless, always)
     Validate k=3 signatures, VBCs, FACT chain, balance math

  2. Check 3 Nabla nodes:
     Nabla_sender (from cheque's registered_nabla field)
     Nabla_random_1 (different VBC branch, receiver's choice)
     Nabla_random_2 (different VBC branch, receiver's choice)

  3. All 3 must agree on new state (n of n)
     Any disagreement --> WAIT or REJECT

  4. Wait 1 TARDIS tick (gossip catchup window — see §4.5)

  5. Check same 3 Nabla nodes again
     All still agree, same answer --> proceed to step 6
     Any change --> CONFLICT detected --> REJECT

  6. Trace FACT chain on Nabla
     For each FACT link: check sender's wallet state on Nabla
     All links verified --> ACCEPT
     Any link mismatch --> REJECT
     Any link unverified (scar) --> receiver decides risk
```

### 4.3 Why 3 Nabla Nodes

```
Sender's Nabla:   confirms registration happened
Random Nabla 1:   cross-pollination from different VBC branch
Random Nabla 2:   cross-pollination from different VBC branch

Cross-branch selection ensures the receiver checks Nabla nodes
that are in different gossip regions of the network.
If a conflicting registration exists, at least one random Nabla
is likely to have received it via gossip.
```

### 4.4 Why n of n (Not Majority)

```
2 of 3 agree:  could be wrong -- the dissenting 1 might be right
3 of 3 agree:  consensus across branches -- much stronger guarantee

Any disagreement means information is still propagating
or a conflict exists. In both cases: WAIT.
```

### 4.5 Why 1-Tick Wait — and the two timers

The receiver's verification routine uses **two distinct timers** that do
two different jobs. Past versions of this document conflated them; readers
hitting that confusion should treat this section as the authoritative
disambiguation.

**Timer A — query-loop catchup wait (this section, 1 TARDIS tick).**

The receiver queries 3 Nabla nodes once, waits **1 TARDIS tick**, then
queries the same 3 again. The wait exists so that the slowest node in
the receiver's triplet — most often the sender's sticky `nabla_hint`
node, which the receiver hits first — has time to receive any
conflicting registration that may exist. One tick is the AXIOM unit of
"gossip has had time to take a step on every honest node in the mesh."
On a healthy 10-node mesh with 8-peer fanout, gossip touches every node
inside one tick; on a larger or partially-degraded mesh it may take
slightly longer, which is exactly why the maturity window (Timer B)
exists as the protocol-level safety net. The loop wait is for the
receiver's *local* read-your-writes guarantee, not for protocol
convergence.

If both queries return identical states (or a *forward extension* of
the first set — see §4.6 step 5 below), the receiver's view of the
sender's wallet is internally consistent against three independent
nodes from different VBC branches. Any disagreement, or a non-forward
state change between the two queries, is a CONFLICT and the cheque is
rejected.

**Timer B — maturity window (5 ticks target / 7 ticks ceiling).**

This timer is defined in YPX-003 (§5.6, MATURITY_TICKS_MIN=5,
MATURITY_TICKS_MAX=7) and the Yellow Paper §17. It is **not** the loop
wait. A registration is only considered CLEAN when
`current_tick - registration_tick ≥ 5` (target) or `≥ 7` (slow-network
ceiling). Until that threshold, the cheque is SCARRED — registered
but not yet matured. Receivers MAY accept a SCARRED cheque at their
own risk and heal the scar later; receivers concerned about
double-spend defence should wait for CLEAN.

Timer B is the protocol's guarantee that any conflict has had enough
time to propagate everywhere and surface. Timer A is the receiver's
defence against querying a single node that happens to be momentarily
behind. Both are needed; neither subsumes the other.

A receiver running the §4.6 loop on a brand-new registration will
typically see "registered but not mature" on the first iteration,
sleep one tick (Timer A), see the same answer (still mature in
progress), sleep again, and eventually see CLEAN once Timer B
completes. The loop is the same in either case — only the exit
condition differs.

**Verification budget (the worst-case the receiver must tolerate):**

```
IDEAL   — receiver queries exactly when Timer B completes:
            Timer B alone           = 5 ticks  ≈ 25 s
NORMAL  — receiver queries immediately after registration,
          waits 1 Timer A tick, retries once maturity lands:
            Timer A (1) + Timer B (5) = 6 ticks ≈ 30 s
SLOW    — adaptive maturity (YPX-003 §5.6) extends to MAX:
            Timer A (1) + Timer B (7) = 8 ticks ≈ 40 s
```

`6 ticks` is the design point — under a healthy mesh the receiver
gets CLEAN within 30 seconds of cheque arrival, in the worst case.
Beyond 6 ticks the network is degraded (gossip backpressure,
adaptive maturity engaging) and the receiver should treat continued
SCARRED as a network-health signal, not a transaction problem.
Under no circumstances does the receiver loop forever — past
8 ticks the verification call returns SCARRED with an explicit
"network slow" reason and the receiver decides whether to accept
the cheque at risk or wait and retry later.

### 4.6 Verification Pseudocode

```python
def verify_cheque(cheque, nabla_nodes):
    """
    Client-side cheque verification.

    Two timers are used (see §4.5 for the disambiguation):
      • Timer A — query-loop catchup wait, 1 TARDIS tick. Local
        read-your-writes guarantee for the receiver's triplet.
      • Timer B — maturity window, 5–7 TARDIS ticks (YPX-003 §5.6).
        Protocol-level guarantee that any conflict has propagated
        everywhere. Drives the CLEAN/SCARRED status (§4.7).

    Nabla's role in this routine is narrowly scoped:
      • Ban witness: "has this sender been caught double-spending?"
        Answered by gossip-merge bans (§7.5). Stable, useful.
      • Liveness signal: "has Nabla seen any registration for this
        wallet at all?" Answered by current_state != all-zero.
      • Timer B: the signed `registration_tick` on a /query response
        drives the maturity gate.

    Nabla is NOT a state-chain oracle. An earlier draft of this
    pseudocode (pre-2026-04-14) required `nabla.current_state ==
    cheque.produced_state_id`, which failed on ~42% of honest cheques
    under live soak because senders legitimately advance past the
    cheque's state by sending more TXs. The correct "did this cheque
    get registered with Nabla" question is answered by the
    `nabla_confirmation` field on the cheque's own FACT chain tip
    (see YPX-001 §1.5 — scar semantics). That check is local,
    doesn't involve Nabla at runtime, and gives a stable answer.
    """
    # Step 1: Core verification (stateless, always)
    if not core.verify(cheque):
        return reject("Core verification failed")

    # Step 1.5: LOCAL cheque coherence + registration check (2026-04-14).
    #
    # Three in-memory checks against data the cheque already carries.
    # No Nabla query, no signature verification (Core CL5 is the
    # signature authority at redeem time; this is a fast filter).
    #
    # The `nabla_confirmation` presence check is the core of this
    # section: it is the mechanism that enforces "sender must register
    # with Nabla" without asking Nabla a moving-target question.
    if cheque.sender_fact_chain is None or cheque.sender_fact_chain.links == []:
        return scarred("cheque has no sender_fact_chain — provenance unknown")

    tip = cheque.sender_fact_chain.links[-1]

    # (a) Outer cheque state must match the cheque's own inside.
    #     Byte compare in memory. Catches outer-label tampering that
    #     leaves the history file untouched.
    if tip.new_state_id != cheque.produced_state_id:
        return reject("cheque produced_state_id does not match FACT chain tip")

    # (b) The tip FactLink must carry a NablaConfirmation. The
    #     confirmation is the signed receipt Nabla issued when the
    #     sender called /register for this specific TX. Its presence
    #     proves the sender put this cheque through Nabla so the
    #     gossip-merge ban machinery can catch any future conflict.
    #     Core CL5 verifies the Ed25519 signature at redeem (§39.9
    #     trust anchor); this check is presence-only, a fast sanity
    #     filter. An attacker stapling garbage passes the pre-check
    #     but fails at CL5, one validator round-trip later.
    if tip.nabla_confirmation is None:
        return scarred("sender never registered with Nabla — cheque is scarred")

    # Step 2: Select 3 Nabla nodes — sender's sticky + 2 cross-branch
    #
    # YPX-002 §3.2 step 5: the sender pre-declared its sticky Nabla in
    # the witness request, and every witnessing validator stamped it
    # into the cheque as `cheque.nabla_hint = {node_name, address}`.
    # Cross-branch is defined by NBC issuer: two nodes are cross-branch
    # iff their NBCs were signed by different parent CAs (§4.3). This
    # is deterministic from the cert chain — no runtime topology
    # inference required.
    sender_nabla = cheque.nabla_hint  # may be None on first-ever TX
    random_nablas = pick_cross_branch(
        nabla_nodes, count=2, exclude_branch_of=sender_nabla,
    )
    if sender_nabla is not None:
        check_nodes = [sender_nabla] + random_nablas
    else:
        # First TX from a fresh wallet — no sticky yet. Fall back to
        # 3 cross-branch random nodes. The receiver loses the §3.2
        # routing optimization but the n-of-n check still holds.
        check_nodes = pick_cross_branch(nabla_nodes, count=3)

    # Step 3: First check — BAN + liveness only
    #
    # Previous draft: rejected if states_1[0] != cheque.new_state_id.
    # Removed 2026-04-14 — see §4.6 notes above. The registration
    # question is now answered by Step 1.5's nabla_confirmation
    # presence check, not by comparing Nabla's moving-target
    # current_state against the cheque's fixed produced_state_id.
    responses_1 = query_all(check_nodes, cheque.sender_wallet_pk)
    states_1 = [r.current_state for r in responses_1]

    if any(r.status == BANNED for r in responses_1):
        return reject("Sender wallet is BANNED — proven double-spend")
    if not all_equal(states_1):
        return wait("Nabla nodes disagree — waiting for gossip")
    if states_1[0] == ZERO_STATE:
        # Nabla has never heard of this wallet — registration hasn't
        # propagated yet. Transient, retry later.
        return wait("sender not registered yet — waiting for gossip")

    # Step 4: Wait 1 TARDIS tick (Timer A — gossip catchup for the
    # slowest of the 3 queried nodes, usually the sticky). The purpose
    # is to give any conflicting registration time to propagate and
    # fire the ban check on wave 2.
    sleep_ticks(1)

    # Step 5: Second check — BAN only
    #
    # Previous draft: rejected on any non-forward state change. Removed
    # 2026-04-14 — see §4.6 notes above. Any real conflict fires the
    # gossip-merge ban check in `nabla/src/gossip.rs`, which the BAN
    # check below catches. A state advance between waves WITHOUT a
    # ban firing just means the sender sent another legitimate TX
    # during Timer A; that is not a conflict.
    responses_2 = query_all(check_nodes, cheque.sender_wallet_pk)
    states_2 = [r.current_state for r in responses_2]

    if any(r.status == BANNED for r in responses_2):
        return reject("Sender wallet is BANNED — proven double-spend")
    if not all_equal(states_2):
        return wait("Nabla nodes disagree on second check — retry later")

    # Step 6: FACT chain scar count — the BANNED check is already done.
    #
    # CORRECTION (2026-04-14): earlier drafts of this pseudocode called
    # `query_any(nabla_nodes, link.sender_wallet_id)` per-link. That was
    # wrong. YPX-001 §1.2 defines `FactLink` with no `sender_wallet_id`
    # field, and §1.3 rule 3 shows why: every link in a cheque's
    # `sender_fact_chain` is a transition on the SAME wallet (the
    # current holder). Each link's `previous_state_id` must equal the
    # prior link's `new_state_id`, so the chain is a single wallet's
    # own state-transition history, not a multi-hop money-provenance
    # graph across many senders. The BANNED check on "the sender" was
    # therefore already performed in steps 3 and 5 against the Nabla
    # query wave — repeating it per-link would query the same wallet
    # the same number of times and return the same answer.
    #
    # What remains at step 6 is:
    #   1. Count scars (links with `nabla_confirmation == None`) for
    #      display to the receiver. Scars are informational per §4.1:
    #      the receiver, not the client library, decides whether to
    #      accept scarred money.
    #   2. Cryptographic chain integrity (k=3 Dilithium signatures,
    #      state continuity, tick ordering) is Core's job at CL5
    #      redeem — §1.3 rules 1–5 run there. Duplicating them at the
    #      client before redeem is belt-and-suspenders but NOT part
    #      of the §4.6 minimal verification contract.
    #
    # Any future protocol revision that splits `sender_fact_chain`
    # into a true multi-sender provenance graph (e.g. "this money
    # came from Alice who got it from Bob") would need to re-open
    # this section and add the per-link BANNED lookup back in.
    scar_count = sum(
        1 for link in cheque.fact_chain.links
        if link.nabla_confirmation is None
    )

    # Step 7: Maturity check (Timer B — protocol convergence)
    #
    # The cheque's registration must have reached the maturity window
    # before it can be flipped to CLEAN. Until then, it is SCARRED
    # (registered but immature). Receivers may accept SCARRED at their
    # own risk; conservative receivers wait for CLEAN.
    age_ticks = current_tick() - responses_2[0].registration_tick
    if age_ticks >= MATURITY_TICKS_MIN:  # 5 by default, see YPX-003 §5.6
        return accept(status=CLEAN, scarred_links=scar_count)
    else:
        return accept(status=SCARRED, scarred_links=scar_count,
                      reason="immature — wait for maturity")
```

The two-timer split is intentional: Timer A defends the receiver
locally against a single behind-gossip node; Timer B defends the
receiver against a network-wide propagation gap. They compose, they
do not substitute.

### 4.7 Client Recommendation

The client application should auto-check Nabla on every receive and strongly recommend verification:

```
Nabla reachable, verified:     "Verified" --> accept
Nabla reachable, mismatch:     "MISMATCH -- possible fraud" --> reject
Nabla reachable, not registered: "Waiting for sender" --> wait
Nabla unreachable:             "Cannot verify" --> backup + accept or hold
```

---

## 5. Gossip Network

### 5.1 Propagation Model

Nabla nodes form a peer-to-peer gossip mesh. Updates propagate by flood fill.

```
Sender registers on Nabla_A2:
  Nabla_A2 --> peers: Nabla_A3, Nabla_B1, Nabla_C4, ...
  Each peer --> their peers
  Flood fill across network
  
No routing table. No assignments. Anyone can join or leave.
```

### 5.2 TARDIS Tick Sync

At each TARDIS tick, Nabla nodes compare state:

```
Tick N:
  Every Nabla node computes root_hash of entire database
  Broadcasts: "At tick N, my root_hash is X"
  Compares with peers
  
  All agree --> network consistent
  Mismatch --> investigate (rogue node or propagation delay)
```

Between ticks, Nabla nodes may diverge temporarily. This is expected. Ticks are comparison points, not deadlines.

### 5.3 Query Response Format

Every Nabla response includes metadata for automatic auditing:

```
Nabla_response {
    wallet_id:      bytes32
    current_state:  bytes32
    tx_hash:        bytes32
    root_hash:      bytes32     // full database hash
    synced_to_tick: uint64
    signature:      bytes       // Nabla node signs response
    vbc_proof:      VBCProof    // Nabla's own VBC
}
```

Receiver compares root_hash across 3 Nabla nodes. Mismatch at same tick means rogue node.

---

## 6. FACT Scar Integration

### 6.1 Scar Definition

A FACT link without Nabla confirmation (nabla_confirmation = null) is a "scar." See YPX-001 Section 1.5.

### 6.2 Healing a Scar

The wallet owner can heal a scar at any time:

```
Option A: Verify Retroactively (FREE)
  Check Nabla for sender's wallet in scarred link.
  Nabla confirms match --> add nabla_confirmation to FACT link.
  Scar healed. FACT chain can compress.

Option B: Burn Tainted Amount (COSTS MONEY)
  Cannot verify (sender never registered or mismatch).
  Client creates CL2 burn TX to BURN_ADDRESS ("BURN/00000000").
  One burn per scar. Amount must match scarred link exactly.
  Scarred link annotated with BurnProof (not removed).
  Chain can compress. See YPX-001 §1.5.4 for full protocol.

Option C: Revert to Backup (NUCLEAR)
  Revert wallet to backup made before scarred receive.
  All transactions after scar point are lost.
  Clean wallet restored.
```

Owner tries in order: A then B then C.

### 6.3 Market Consequences

```
Short FACT chain:    every hop verified --> trusted --> full value
Long FACT chain:     something unverified --> suspicious --> discounted or rejected

No protocol enforcement needed. The market punishes long chains naturally.
```

---

## 7. BANNED Wallet Mechanism

### 7.1 Conflict Detection

When a Nabla node receives a gossip update that conflicts with its existing record:

```
Existing: Wallet_X old_state=S3, new_state=S4 (valid k=3)
Incoming: Wallet_X old_state=S3, new_state=S5 (valid k=3)

Same old_state. Different new_state. Both have valid k=3.
This is PROOF of deliberate double-spend.
```

### 7.2 Ban Record

```
Nabla stores permanently:
  wallet_id:    Wallet_X
  status:       BANNED
  evidence: {
    registration_1: {
      old_state: S3, new_state: S4,
      k3_signatures: [V1, V2, V3], tx_hash: abc123
    },
    registration_2: {
      old_state: S3, new_state: S5,
      k3_signatures: [V4, V5, V6], tx_hash: def456
    }
  }
```

### 7.3 Ban Properties

- Permanent. Cannot be reversed.
- Evidence-based. Any Nabla node can independently verify.
- Gossip-propagated. All Nabla nodes learn about the ban.
- FACT chains touching BANNED wallets are immediately tainted.
- Corrupt validators exposed by the conflicting k=3 signatures.

### 7.4 Why Bans Cannot Happen By Accident

Two valid k=3 signatures over two DIFFERENT transactions consuming the same state requires deliberate construction of two different payloads and deliberate request to validators to sign both. This cannot result from bugs, crashes, or network issues.

```
Bug: crash --> no double registration, just failed TX
Bug: sign same TX twice --> same output --> no conflict
Bug: corrupt data --> invalid signature --> Core rejects

Two different valid k=3 over same state = intentional fraud
```

### 7.5 Ban Pseudocode

```python
def handle_gossip_update(self, incoming):
    wallet_id = incoming.wallet_id
    
    if wallet_id in self.db:
        existing = self.db[wallet_id]
        
        if existing.status == "BANNED":
            return  # already banned
        
        if incoming.old_state == existing.old_state:
            if incoming.new_state != existing.new_state:
                # CONFLICT: same old state, different new state
                # Authorship gate: ban only if BOTH conflicting states are
                # wallet-authored — client_pk != 0 AND a valid client_sig over each
                # state. k=3 validator signatures alone are insufficient (Nabla holds
                # no validator authority); the wallet's own signature is unforgeable,
                # so no validator set can false-ban an honest wallet.
                if (verify_k3(incoming) and verify_k3(existing)
                        and verify_authorship(incoming)
                        and verify_authorship(existing)):
                    # Proven, wallet-authored double-spend
                    self.db[wallet_id] = {
                        "status": "BANNED",
                        "evidence": {
                            "reg_1": existing,
                            "reg_2": incoming
                        }
                    }
                    self.gossip_ban(wallet_id)
        
        elif incoming.old_state == existing.current_state:
            # Normal sequential update
            self.db[wallet_id] = {
                "current_state": incoming.new_state,
                "tx_hash": incoming.tx_hash,
                "tick": incoming.tick
            }
            self.gossip_update(incoming)
    
    else:
        # New wallet
        self.db[wallet_id] = {
            "current_state": incoming.new_state,
            "tx_hash": incoming.tx_hash,
            "tick": incoming.tick
        }
        self.gossip_update(incoming)
```

---

## 8. Partition Handling

### 8.1 Design Principle

During partition, Nabla is unreachable. Commerce continues. The protocol does not change. The client handles the uncertainty.

This is separate from Ark-Mode (White Paper). Ark-Mode uses a separate Ark wallet for planned offline operation. Partition handling is a client-level feature for temporary Nabla outages using the normal wallet.

### 8.2 Client Behavior During Partition

```
Nabla unreachable:
  Client prompts: "Cannot verify with Nabla. Options:"
  
  Option 1: Redeem to wallet
    Client auto-backs up wallet before redeeming.
    Cheque redeemed. Wallet continues.
    Risk: receiver's. May need to revert later.
  
  Option 2: Hold unredeemed
    Cheque stored in inbox.
    Wallet unchanged. Zero risk.
    Redeem when Nabla returns.
```

### 8.3 Post-Partition Recovery

```
When Nabla becomes reachable:

  No double-spend occurred:
    Everyone registers pending transactions.
    Everyone verifies retroactively (Option A healing).
    All scars healed for free. Economy balances out.
  
  Double-spend occurred:
    Attacker can only register ONE spend.
    All other spends provably invalid.
    Victims verify --> mismatch --> burn or revert.
    Fake money evaporates through recovery.
```

### 8.4 Honest Cost of Partition

All receivers during partition are potential victims. This is the honest cost of continued commerce during network outage. When partition ends, those who received legitimate money heal for free. Those who received fake money burn or revert.

---

## 9. Nabla Node Requirements

### 9.1 NBC Requirement (k=1)

Nabla nodes use NBCs (Nabla Birth Certificates) — the same VBC struct but with
different verification parameters. NBC requires k=1 issuer (vs k=3 for VBC) and
uses NABLA_ROOT_AUTHORITY_PKS as trust anchor (separate from validator root keys).

```
Validator VBC: k=3 issuers, ROOT_AUTHORITY_PKS, CL6
Nabla NBC:     k=1 issuer,  NABLA_ROOT_AUTHORITY_PKS, CL7
Same struct. Different trust parameters. Key isolation.
```

NBC trust model:
- Genesis NBCs (chain_depth=0): signed by 1 Nabla root authority key
- Non-genesis (chain_depth=1+): signed by 1 existing Nabla node
- All chains must trace back to NABLA_ROOT_AUTHORITY_PKS

### 9.2 Peer Requirements

Nabla nodes should maintain peers across multiple VBC branches for effective gossip propagation. This is not enforced by protocol but is recommended for trust scoring.

### 9.3 Economic Model

Nabla operation is a validator responsibility, not a separate fee market. Validators who witness transactions are expected to also run Nabla nodes as part of their TrustMesh duties.

```
Validator earnings:   witness fees from transactions (Yellow Paper Section 25)
Validator costs:      Core, Lambda, Nabla, VBC maintenance

Nabla is not a separate service.
Nabla is infrastructure validators provide.

Sender pays:    nothing extra for Nabla registration
Receiver pays:  nothing for Nabla queries
Validator pays: Nabla operational cost from witness fee earnings
```

Market enforcement (no protocol enforcement needed):

```
Validator with Nabla:     receivers can verify cheques
                          --> trusted --> more transaction volume --> more fees

Validator without Nabla:  receivers cannot verify cheques
                          --> untrusted --> less volume --> fewer fees
```

Detailed fee model and validator compensation adjustments are deferred to a future specification.

---

## 10. Attack Analysis

### 10.1 Summary

```
Attack                          Severity    Defense
-------------------------------  ----------  ---------------------------------
1/9. Race condition              CLOSED      3 cross-branch Nabla + n/n +
     (simultaneous registration              2-sec wait + FACT trace +
     on distant Nabla)                       BANNED wallet on conflict

2.   Own validator + Nabla       LOW         Majority honest, receiver
                                             picks own Nabla nodes

3.   Fake k=3 signatures         NONE        Core blocks via VBC

4.   Bribe validators            LOW         Nabla catches at registration,
                                             BANNED on conflict detection

5.   Sybil Nabla nodes           LOW         Same VBC as validators,
                                             client trust scoring,
                                             cross-branch selection

6.   Fake birth state            NONE        tx_hash stored in Nabla,
                                             cannot fake without
                                             invalidating k=3 sigs

7.   Eclipse attack              CLOSED      Same as 1/9 -- cross-branch
                                             selection + 2-sec wait

8.   Stale registration          LOW         Client backup/revert
```

### 10.2 External Review Attacks (Grok, 2026-02-08)

```
Attack                          Assessed    Defense / Notes
-------------------------------  ----------  ---------------------------------
G1. Gossip propagation delay     LOW         Attacker must control specific
    (NABLA node delays gossip)               nodes randomly selected by
                                             receiver. Timer A (1 tick)
                                             covers receiver-side gossip
                                             catchup; Timer B (5–7 ticks
                                             maturity) is the protocol-level
                                             convergence guarantee. No
                                             economic gain from delay alone.
                                             RESEARCH: Gossip heartbeat
                                             monitoring, reputation scoring.

G2. FACT scar accumulation       MEDIUM      Valid concern. Spam low-value
    (spam TXs + withhold NABLA               TXs to create unresolvable scars.
    confirmations)                           MITIGATIONS:
                                             - Dust limit: 500,000 atoms minimum
                                             per transaction (fees = k*10 = 30
                                             atoms = 3%, spam uneconomic)
                                             - Per-wallet scar cap (reject
                                             new inbound when cap reached)
                                             - Scar auto-resolution timeout
                                             (auto-burn after N ticks)
                                             RESEARCH: Exact scar cap value,
                                             auto-resolution tick count.

G3. TARDIS tick desync via       NOT VALID   TARDIS ticks are network-wide
    network partition                        unix timestamps (see YPX-003
                                             v0.4). During a partition,
                                             nodes in both sides continue
                                             ticking independently from
                                             their local clocks. Cheques
                                             remain SCARRED during partition
                                             because gossip cannot propagate.
                                             When partition heals, TARDIS
                                             cascade reconnects, gossip
                                             reconciles, any double-spend
                                             across partitions is detected
                                             and both cheques REJECTED.

G4. BANNED status forgery via    LOW-MEDIUM  n-of-n requires ALL queried
    NABLA collusion                          nodes agree, selected randomly
                                             by receiver. Evidence must include
                                             cryptographic proof (conflicting
                                             receipts with valid validator sigs).
                                             Cannot fabricate without forging
                                             validator signatures.
                                             IMPLEMENT:
                                             - BANNED gossip must carry
                                             evidence (conflicting receipts)
                                             - Challenge mechanism: wallet
                                             can dispute with counter-proof
                                             RESEARCH: Challenge protocol
                                             specification, timeout for
                                             dispute resolution.

G5. Checkpoint compression       LOW         Original concern assumed Genesis
    bypass griefing                          authority for compression.
                                             CORRECTED: Compression requires
                                             NO external authority. Core
                                             validates FACT chain is clean
                                             (no scars), validator compresses
                                             locally. Genesis validators have
                                             no special role in compression.
                                             Scars are resolved by validators
                                             when requested (query NABLA,
                                             confirm or burn).
                                             Scar auto-resolution timeout
                                             (same as G2) prevents indefinite
                                             bloat.
```

### 10.3 Security Assessment

```
Normal conditions (Nabla reachable, client follows protocol):
  Double-spend:        caught by verification + 2-sec wait
  Fake money:          caught by FACT chain trace
  Laundered money:     caught by FACT scar (cannot checkpoint)
  BANNED wallet:       permanent, evidence-based
  Corrupt validators:  exposed by conflict evidence

Partition (Nabla unreachable):
  Commerce continues:  with risk accepted by all parties
  Post-partition:      verify, heal, burn, or revert
  Fake money:          evaporates through recovery

Receiver skips Nabla:
  Receiver's risk:     their loss if fake
  FACT scar:           prevents taint from being checkpointed
  Market pressure:     drives verification adoption

Confidence: approximately 85-90%
  Limited by: partition window, receiver discipline,
  gossip propagation time (Timer A 1 tick + Timer B 5–7 ticks,
  total verification budget 6 ticks ideal / 8 ticks slow-network)

Mitigations required for 90%+ confidence:
  - Dust limit and per-wallet scar cap (G2, G5)
  - Scar auto-resolution timeout (G2, G5)
  - BANNED evidence proofs in gossip (G4)
  - BANNED challenge mechanism (G4)
```

---

## 11. Open Questions

```
DESIGN DECIDED (v0.1 → YPX-004 design sprint, 2026-02-20):
  - Dust limit: 500,000 atoms minimum per transaction (G2)
  - Compression: no Genesis authority needed, Core + validator local (G5)
  - BANNED gossip must carry evidence proofs (G4) → implement
  - Adaptive peer count: 9 + max(0, ceil(log₁₀(seen_nodes)) - 1)
    Scales from 9 peers at genesis to 13+ at 50,000 nodes.
    Validated by Python simulation: 100% gossip completion within 5 ticks
    at all tested network sizes (10, 100, 1000, 10000, 50000 nodes).
  - Storage: Sparse Merkle Tree (SMT) replaces flat key-value store.
    Provides O(1) root hash computation and merkle proofs for
    lightweight auditing. No full-DB scan at tick boundaries.
  - DEED fee model: 30% of DEED fees to Nabla Runner Pool for
    first 10 years of network operation, 100% thereafter.
    Incentivises early Nabla adoption without permanent tax.
  - Nabla identity: NBC (Nabla Birth Certificate) using same VBC
    function from Core with role = "nabla". Same trust chain,
    different participant type.
  - Companion Certificates (CC): Rolling score accumulators that
    Core produces each tick, chaining to previous certificates.
    Tracks ticks_helped (uptime) and registrations_processed (work).
    Naturally prevents Sybil — empty nodes earn negligible rewards.
  - Positive language: "fewer helpers" not "penalties" for offline
    nodes. Reflects volunteer nature of citizen infrastructure.
  - Maturity window: 25 seconds (5 ticks × 5 seconds) confirmed
    sufficient with adaptive peer count at all network sizes.

RESEARCH NEEDED:
  1. TARDIS tick interval: confirmed 5 seconds per tick — RESOLVED
  2. W1, W2 exact weights in CC score formula: RESOLVED — W1=1, W2=10 (verified via simulation)
  3. Client trust scoring algorithm for Nabla node selection
  4. FACT scar burn transaction: RESOLVED — see YPX-001 §1.5.4 (v0.3), implemented in Core
  5. Nabla node discovery mechanism: RESOLVED — RegisterAck/RegisterRejected carry known_peers hints
  6. Per-wallet scar cap: max unresolved scars before rejecting inbound TXs (G2)
  7. Scar auto-resolution timeout: after how many ticks does scar auto-burn (G2)
  8. BANNED challenge protocol: how does innocent wallet dispute false BANNED (G4)

COMPLETED:
  - FACT scar burn mechanism: BURN_ADDRESS, burn_target_tx_id, BurnProof (YPX-001 §1.5.4)
  - Dust limit enforcement in Core (G2) — MINIMUM_TX_ATOMS = 500,000
    Bypass for protocol addresses: BURN_ADDRESS, DEED_ADDRESS, FEE_ADDRESS
  - Scar resolution via burn transaction (G5) — validate_burn_target() in Core
  - Sparse Merkle Tree wallet state DB — implemented in nabla/src/smt.rs
  - NBC issuance and verification — nabla-ceremony binary, CL7/CL8 wired
  - Registration gossip verification — NablaClient.query(), integration test

IMPLEMENT:
  - BANNED evidence format: conflicting receipt proofs required in gossip (G4)
  - BANNED challenge mechanism (G4)
  - Scar healing propagation: receiver notification via receiver_contact (G5)
  - Companion Certificate generation in Core tick handler
  - Adaptive peer count in gossip layer
```

---

## 12. Glossary

| Term | Definition |
|------|-----------|
| Nabla (∇) | TrustMesh participant specializing in wallet state verification. Symbol: ∇ (U+2207), the mathematical gradient operator — "where is this wallet now?" One entry per wallet. |
| Gossip | Flood-fill propagation of updates between Nabla peer nodes. |
| BANNED | Permanent wallet status. Proven double-spend. Evidence stored. Cannot be reversed. |
| Scar | FACT link without Nabla confirmation. Blocks FACT chain compression. |
| Burn | CL2 transaction to BURN_ADDRESS forfeiting scarred amount. Annotates scar with BurnProof. See YPX-001 §1.5.4. |
| n of n | All queried Nabla nodes must agree. No majority rule. |
| Cross-branch | Selecting Nabla nodes from different VBC genesis branches for diversity. |
| registered_nabla | Cheque field identifying which Nabla node the sender registered with. |

---

## 13. References

| Document | Relevance |
|----------|-----------|
| Yellow Paper v2.6.0+ | Base protocol. Phase 1. Sections 17, 23.13, 24, 26, 28. |
| YPX-001 | FACT Chain and TARDIS Protocol. Phase 2. Required by this document. |
| Security Research | Full design rationale, attack analysis, rejected approaches. |
| White Paper | AXIOM philosophy, Ark-Mode definition, TrustMesh concept. |

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
