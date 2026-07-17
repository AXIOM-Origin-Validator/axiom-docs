# YPX-010: Ark Mode ⟠ Confidence Index

**Version:** 0.3
**Status:** Implementing
---

## 0. Summary

This extension specifies the Ark Mode Confidence Index (CI) — a protocol for evaluating offline ⟠ (k=0) transactions without network connectivity, validators, or Nabla. The CI is computed entirely from the sender's FACT chain and the receiver's own judgment. No external data sources are required.

Every factor in this design is grounded in published academic research across six fields: disaster infrastructure studies, behavioural fraud detection, rational choice economics, skin-in-the-game theory, financial anomaly detection, and disaster sociology.

---

## 1. Context

### 1.1 What Ark Mode Is

Ark mode is the k=0 security tier in YPX-007. A wallet operating in Ark mode makes offline transfers with zero validator involvement. No k=3 consensus. No Nabla gossip. The transaction is validated purely by local Core/AVM execution with DMAP attestation on both sender and receiver sides.

Loading an Ark wallet requires k=3 (online, full pipeline). Offline trading is ⟠-to-⟠ only. Reconciliation requires k=3 (back online). Ark mode is for **survival** — when infrastructure has failed.

### 1.2 The Infrastructure Reality

Cell towers and internet connectivity fail in disasters in predictable, measurable patterns:

| Time Window | Infrastructure State | Disaster Tier |
|-------------|---------------------|---------------|
| 0–30 min | Battery backup fully active on most towers. K=3 network almost certainly live. | None or pre-event |
| 30–300 min | Within standard 2–8 hour battery backup window. Some towers degrading. | Tier 1 — localized |
| 300–720 min | Past battery backup. Generator territory. FCC mandates up to 12h for first responders. | Tier 1–2 transition |
| > 720 min | Past mandatory FCC backup window. Commercial power not restored. | Tier 2+ major disaster |

Sources: FCC DIRS disaster reporting data; IEEE Spectrum cell tower disaster studies; Hurricane Harvey, Irma, Maria incident records.

### 1.3 Why Nabla Is Absent

When the internet fails, Nabla is gone entirely. No pending records, no gossip propagation, no network confirmation of any kind. The receiver has exactly three things available:

1. **The FACT chain** the sender physically carries — cryptographically verifiable offline
2. **A clock** — to measure elapsed time since last k=3
3. **Human judgment** — informed by the visible signals in the chain

This specification defines how to use those three things systematically.

### 1.4 Reconciliation: Re-Registration Without Re-Payment

An offline ⟠ (k=0) transfer is executed with zero validator involvement, so it is **never registered with Nabla** — the spend never enters the global consume-once check, and its FACT link is *scarred* (pending). This is the source of Ark's disclosed risk: while unregistered, a spend is invisible to the mesh, so an honest offline transfer is indistinguishable from a double-spend until the network returns. (Note: the scar is the *non-registration itself*, not a missing k≥3 confirmation — Nabla will not confirm a k=0 transaction in any case.)

When connectivity returns, the sender **re-registers** each offline Ark transaction with validators through a **special witness process**: a full k=3 witness round that anchors the state into Nabla's SMT and marks it consumed. The critical difference from an ordinary send is that this witness round is **registration-only — it does not issue or send a cheque to the receiver.** The receiver already holds the cheque from the offline hand-off; re-issuing would double-pay. The special round carries only the provenance anchor and the consume-once mark, never a second value transfer.

Re-registration does three things at once:

1. **Heals the scar.** The k=0 link becomes k=3-registered; `nabla_confirmation` is now present and provenance is no longer in question.
2. **Closes the deterrence loop.** Registering the state enters it into the global consume-once check. If the same predecessor state was spent to more than one receiver offline, the conflicting registrations are now detected — the same-sequence fork ban fires and the wallet is permanently banned. **Reconciliation is where an offline double-spend is caught.**
3. **Resets the freshness clock.** The new k=3 anchor updates the wallet's last-k=3 timestamp (Factor 1), returning the wallet to FRESH.

Re-registration is idempotent per txid (consume-once): a state already registered by some validator re-registers as a no-op, and a chain of offline transactions re-registers in order. Until reconciliation completes, offline transfers carry the disclosed, bounded risk that the Confidence Index (§2–§4) exists to price.

---

## 2. The Five Trust Factors

Every factor is computable offline from the FACT chain alone. No external queries. No network calls. No assumptions about infrastructure state.

### Factor 1: K=3 Staleness

**Research field:** Disaster infrastructure studies (FCC DIRS data, Hurricane field research)

Time since the wallet's last k=3 transaction. Cell towers have 2–8 hours of battery backup (FCC documentation), legally mandated up to 12 hours for first responders. After Hurricane Maria, 95.6% of Puerto Rico cell sites were immediately out of service. During Hurricane Harvey, 96% of towers remained operational within days.

The staleness bands are calibrated to these infrastructure failure curves:

| Band | Window | Meaning |
|------|--------|---------|
| **FRESH** | < 30 min | K=3 anchor is current. Network almost certainly live. |
| **WARM** | 30–300 min | Within battery backup window. K=3 recent. |
| **STALE** | 300–720 min | Past battery, within FCC 12h mandatory backup. |
| **COLD** | > 720 min | Past all mandatory backup. Tier 2+ disaster territory. |

These are not arbitrary thresholds — they map to measured infrastructure states.

**FACT chain source:** Timestamp of the last FactLink with k=3 witness signatures.

### Factor 2: Ark Transaction Count Since Last K=3

**Research field:** Behavioural fraud detection (Jurgovsky et al. 2018, Bahnsen et al. 2016, Carminati et al. 2015–18)

Modern fraud detection establishes that consistent historical behaviour is the strongest predictor of honest future behaviour. Jurgovsky et al. (2018) quantified "behavioral drift" — accounts with drift scores above 0.7 had fraud rates 5.1x higher than stable accounts. Bahnsen et al. (2016) showed spending periodicity features improved detection by 23%.

**Key inversion:** More Ark transactions means MORE trust, not less. Each prior Ark transaction required transient Nabla connectivity, creating an observable trail across multiple independent nodes. A premeditated double-spender would have needed to seed real transactions at real cost weeks in advance. The dangerous profile is the silent wallet.

| Level | Count | Meaning |
|-------|-------|---------|
| **HIGH** | > 15 | Dense behavioral baseline. Strongest offline trust signal. |
| **MEDIUM** | 4–15 | Reasonable history. Combined with other factors for CI. |
| **LOW** | 1–3 | Thin history. Insufficient alone for trust. |
| **NONE** | 0 | Zero Ark history. Most dangerous profile. |

**FACT chain source:** Count of FactLinks with k=0 (Ark) proof_type since last k=3 link.

**Recency weighting.** Count is not enough — a dense trail that went *quiet* is worth less than a *live* one. Weight each prior Ark tx by recency, A = Σ_i e^(−(now − t_i)/T) (all TARDIS ticks), so a wallet transacting minutes ago counts fully while one whose last tx was hours ago decays. A long gap since the last transaction discounts trust: in that gap the wallet could have gone dark, depleted its balance, or prepared a fork. Density *and* recency both matter.

### Factor 3: Stakes Ratio (K=3 Balance / Ark Transaction Amount)

**Research field:** Rational choice economics (Becker 1968, Taleb 2018, Columbia Law deterrence survey 2021)

Gary Becker's 1968 Nobel-prize-winning work established that criminal behavior follows rational cost-benefit analysis. Taleb (2018) formalizes this as "skin in the game": bearing no downside means no skin in the game, which is the source of many evils. The Columbia Law deterrence survey (2021) finds that permanent, irreversible consequences are the most efficient deterrent.

The permanent ban in AXIOM has no resolution path. No appeal. No JFP reversal. The wallet is gone forever. A wallet holder with 10x their Ark transaction amount in k=3 balance is betting their entire accumulated history for a one-time gain of a fraction of what they own.

| Level | Ratio | Meaning |
|-------|-------|---------|
| **SAFE** | ≥ 10x | Fraud is irrational. Sender loses 10x what they gain. |
| **MODERATE** | 3–10x | Fraud is costly but not catastrophic. Caution. |
| **THIN** | 1–3x | Weak deterrence. Sender has relatively little to lose. |
| **UNDERWATER** | < 1x | Deterrence inverted. Sender gains more than they lose. **Always RED.** |

**FACT chain source:** **Current** balance = balance field of the last k=3 FactLink **minus the sum of all offline (k=0) spends since** — computable offline from the chain. Transaction amount from current artifact.

**⚠️ Use current balance, not the last-k=3 balance.** The stakes ratio must reflect the balance the sender *still holds*, not the balance frozen at the last k=3 anchor. Otherwise the *depletion attack* opens: a sender builds dense history with legitimate small spends, drains the balance toward empty, and double-spends the last chunk — at which point the deterrent is gone but the stale k=3 balance still reports it as intact. Reading the running balance closes this: as the balance drains, the stakes ratio falls and the CI drops with it (the deterrence term is a hard ceiling — confidence can never exceed remaining skin-in-the-game).

### Factor 4: Transaction Amount vs Established History Pattern

**Research field:** Financial anomaly detection (ScienceDirect 2021, BankSealer, FraudBuster)

The anomaly detection literature universally identifies sudden deviation from established baseline as the strongest single fraud signal. Carminati et al.'s FraudBuster framework detects fraud as transactions that deviate from the learned model and change the user spending profile. A comprehensive study found fraudulent transactions showed monetary values 28% higher than legitimate transactions.

| Level | Assessment | Meaning |
|-------|-----------|---------|
| **NORMAL** | Within established range | Consistent with prior behavior. |
| **ANOMALOUS** | Far above historical range | Sudden large amount. Classic fraud signal. |

**FACT chain source:** Transaction amounts from all prior FactLinks. Compute mean and compare current.

### Factor 5: Ark Validator Ecosystem Depth

**Research field:** Telecommunications disaster resilience (FCC disaster reports, IEEE Spectrum)

FCC documentation establishes that priority restoration favors critical users and core networks first. A wallet that has only ever settled through a single Ark-supporting validator faces settlement risk when the network returns — not fraud, but fragility.

| Level | Validators | Meaning |
|-------|-----------|---------|
| **DEEP** | ≥ 3 distinct | Multiple independent settlement paths confirmed. |
| **SHALLOW** | 1–2 | Single point of failure. Settlement fragile. |
| **UNKNOWN** | 0 prior Ark | No evidence any Ark validator has ever processed this wallet. |

**FACT chain source:** Validator PKs from prior Ark-mode FactLink witness signatures.

### Aggregation: the Two Clocks and the Overlap Model

**Two clocks.** The CI runs on two distinct TARDIS clocks, and they must not be confused:

- **Per-wallet freshness** τ — time since *this wallet's* last k=3 registration (Factor 1). It measures how exposed the current coin is.
- **Global disaster clock** D_t — how deep the outage is, which tightens the whole trust bar. As D_t grows, the shadow of the future shortens (a wallet's reputation is worth less if it may never transact again, so deterrence weakens) and tool-contagion risk rises, so the same signals must be *stronger* to reach GREEN.

D_t is estimated endogenously — no oracle, no observing the disaster directly — from attested TARDIS registration ticks:

> **D_t = TARDIS-now − older( sender's, receiver's last-k=3 tick ).**

The *older* (more-stale) of the two parties sets the danger level (conservative); the receiver's own tick is un-gameable because it knows, on its own monotonic TARDIS clock, when it last registered. In a total, prolonged, isolated outage — no fresher peer anywhere — the bar rises until the index trusts no one: the correct fail-safe, held off in practice by any contact with a fresher peer.

**Overlap model (how the factors combine).** Trust is the *intersection* of the factors, not their sum — a soft AND. Picture three circles whose size is each factor's strength: **balance** (the dominant, largest circle), **time from last registration** (shrinks as the wallet goes stale), and **tx history** (the additive tiebreaker). Their three-way overlap is the confidence, and its position across four quadrants — from HIGH-TRUST to LOW-TRUST — is the CI. Because it is an intersection, any factor collapsing to zero collapses trust: a depleted balance, a stale wallet, or a deep disaster each pulls the overlap out of the high-trust corner on its own. This is why the deterrent (balance) is a hard ceiling and why dense history alone can never rescue a stale or depleted wallet.

---

## 3. Unconditional Overrides

Checked first, before any factor evaluation. These conditions override the CI matrix entirely.

| Condition | Rule | Reasoning |
|-----------|------|-----------|
| **FACT scar present** | Always RED | Chain provenance is broken. A scarred FACT chain means money origin is in question — Ark with no validators is precisely where this is most dangerous. |
| **No K=3 ever** | Always RED | No trust anchor exists. No FACT chain root. Wallet has never been verified by the network. |
| **Stakes underwater** (**current** balance < Ark amount) | Always RED | Deterrence mechanism inverts. Sender gains more than they lose from fraud. Rational choice theory: deterrence fails when cost < gain. Uses *current* balance (§Factor 3), so a wallet depleted during the outage is caught. |
| **Ecosystem UNKNOWN + significant amount** | Always RED | No prior Ark settlement history. Payment may be honest and still permanently unresolvable. |

---

## 4. Confidence Index Matrix

Applied after all overrides clear. Each row represents a distinct combination of observable signals, all readable from the FACT chain offline.

### 4.1 FRESH — K=3 Under 30 Minutes Ago

| Ark TX Count | Stakes Ratio | TX Pattern | Ecosystem | CI | Reasoning |
|---|---|---|---|---|---|
| Any | Safe ≥10x | Normal | Deep | **GREEN** | K=3 anchor current. All signals maximally positive. |
| Any | Safe ≥10x | Normal | Shallow | **YELLOW** | Honest but settlement bottleneck. Proceed for smaller amounts. |
| Any | Moderate 3–10x | Normal | Any | **GREEN** | Fresh K=3 dominates. Moderate stakes remain strong deterrent. |
| Any | Thin 1–3x | Normal | Any | **YELLOW** | K=3 current but deterrence weak. Sender has little to lose. |
| Any | Any | Anomalous | Any | **YELLOW** | Sudden large amount. Flag regardless of fresh K=3. |

### 4.2 WARM — K=3 30–300 Minutes Ago

| Ark TX Count | Stakes Ratio | TX Pattern | Ecosystem | CI | Reasoning |
|---|---|---|---|---|---|
| High >15 | Safe ≥10x | Normal | Deep | **GREEN** | Dense trail + high stakes + consistent pattern. Strongest offline trust profile. |
| High >15 | Safe ≥10x | Normal | Shallow | **YELLOW** | Trust signals strong but settlement fragile. |
| High >15 | Moderate 3–10x | Normal | Deep | **GREEN** | High frequency compensates for moderate stakes in WARM window. |
| Medium 4–15 | Safe ≥10x | Normal | Deep | **GREEN** | Solid trail + strong deterrence covers K=3 gap. |
| Medium 4–15 | Moderate 3–10x | Normal | Deep | **YELLOW** | Neither signal decisive alone. |
| Low 1–3 | Safe ≥10x | Normal | Deep | **YELLOW** | High stakes offsets thin history. Small amounts only. |
| Low 1–3 | Moderate 3–10x | Normal | Any | **YELLOW** | Two mediocre signals. Human context must close gap. |
| None 0 | Safe ≥10x | Normal | Any | **YELLOW** | Zero Ark history but very high stakes. Trivial amounts only. |
| None 0 | Thin/Moderate | Any | Any | **RED** | No trail and weak deterrence. Nothing sufficient. |
| Any | Any | Anomalous | Any | **RED** | TX dramatically exceeds pattern. Classic fraud signal. |

### 4.3 STALE — K=3 300–720 Minutes Ago

| Ark TX Count | Stakes Ratio | TX Pattern | Ecosystem | CI | Reasoning |
|---|---|---|---|---|---|
| High >15 | Safe ≥10x | Normal | Deep | **GREEN** | High-frequency commerce through generator-backup period. Consistent with merchant in Tier 1 disaster. |
| High >15 | Safe ≥10x | Normal | Shallow | **YELLOW** | Good signals but settlement fragile. |
| High >15 | Moderate 3–10x | Normal | Deep | **YELLOW** | Activity compensates but stale K=3 + moderate stakes require caution. |
| Medium 4–15 | Safe ≥10x | Normal | Deep | **YELLOW** | Decent activity + high stakes but K=3 meaningfully old. |
| Medium 4–15 | Moderate 3–10x | Normal | Any | **RED** | No signal strong enough to carry the others. |
| Low 1–3 | Any | Any | Any | **RED** | Stale K=3 + thin Ark history. No reliable trust signal. |
| None 0 | Any | Any | Any | **RED** | Silent wallet during active outage. Most dangerous fraud profile. |

### 4.4 COLD — K=3 Over 720 Minutes Ago

| Ark TX Count | Stakes Ratio | TX Pattern | Ecosystem | CI | Reasoning |
|---|---|---|---|---|---|
| High >15 | Safe ≥10x | Normal | Deep | **YELLOW** | All signals strong but major disaster territory. Too wide a window for GREEN. |
| High >15 | Safe ≥10x | Normal | Shallow/Unknown | **RED** | Strong signals cannot overcome both disaster window and fragile settlement. |
| High >15 | Moderate 3–10x | Normal | Deep | **YELLOW** | High activity compensates for moderate stakes even at 12h+. Judgment call. |
| Medium 4–15 | Safe ≥10x | Normal | Deep | **YELLOW** | High stakes partially compensates. Still Tier 2 range. |
| Medium 4–15 | Moderate 3–10x | Any | Any | **RED** | 12+ hours, average activity, average stakes. Insufficient. |
| Low/None | Any | Any | Any | **RED** | Cold wallet, thin/zero history. Most dangerous profile at worst time. |

### 4.5 Settlement Modifier

Applied on top of the base CI from §4.1–§4.4:

| Ecosystem Depth | Effect |
|---|---|
| Deep (≥3 validators) | No change |
| Shallow (1–2) | Downgrade one level (GREEN→YELLOW, YELLOW→RED) |
| Unknown (no prior Ark) | YELLOW floor — cannot be GREEN regardless of other signals |

---

## 5. Research Foundations

Each factor maps to a distinct, well-established academic field:

| CI Factor | Academic Field | Key Works |
|-----------|---------------|-----------|
| K=3 staleness boundaries | Disaster infrastructure studies; FCC telecommunications regulation | FCC DIRS data; Harvey/Maria/Irma field studies; IEEE Spectrum disaster coverage |
| Ark TX count as accumulated trust | Behavioural fraud detection; financial anomaly detection | Jurgovsky et al. 2018 (behavioral drift); Bahnsen et al. 2016 (spending periodicity); Carminati et al. 2015–18 (BankSealer, FraudBuster) |
| Stakes ratio / permanent ban | Rational choice economics; law and economics | Becker (1968) — crime and punishment; Taleb (2018) — Skin in the Game; Columbia Law deterrence survey (2021) |
| TX vs history pattern anomaly | Financial anomaly detection; ML fraud detection | ScienceDirect 2021 fraud detection survey; Persistent Systems behavioural anomaly; Springer Nature fintech forensics (2025) |
| Validator ecosystem depth | Telecom disaster resilience; network restoration | FCC DIRS reports; IEEE Spectrum flying cell towers; Cat5 Resources hurricane restoration |
| Base assumption: most people are honest | Disaster sociology; social psychology | Quarantelli & Dynes — Disaster Research Center; Dynes (2006) social capital; PMC 2020 Catastrophe Compassion; Solnit (2009) A Paradise Built in Hell |

### 5.1 The Convergence Argument

The strongest validation is that the design converges on the same conclusions as multiple independent fields:

- **Fraud detection researchers** arrive at "consistent history = trust" from millions of credit card transactions.
- **Rational choice economists** arrive at "skin in the game = deterrence" from mathematical models.
- **Disaster sociologists** arrive at "most disaster behaviour is pro-social" from decades of field studies.
- **FCC infrastructure data** arrives at specific time windows from measuring actual tower failure rates.

These four fields have never been combined before for offline payment trust assessment. This is the first design that integrates all four as computable protocol factors rather than operator judgment.

---

## 6. The Human Behaviour Foundation

The entire CI model rests on a foundational assumption: **most people in a disaster are not trying to commit fraud.**

> *Extensive social science research undertaken since the end of World War II lends little support to the widespread belief that looting and antisocial behaviors are common in the emergency time periods of community crises.* — Quarantelli, Disaster Research Center, University of Delaware

> *Disaster sociologists have compiled extensive evidence of pro-social behaviour during disaster... Overwhelming evidence demonstrates that pro-social behaviour is more common than antisocial behaviour.* — Jamba: Journal of Disaster Risk Studies, PMC

> *In their wake, survivors develop communities of mutual aid, engage in widespread acts of altruism, and report a heightened sense of solidarity with one another.* — Catastrophe Compassion, PMC 2020

This matters for CI in a precise way. Because:
- The base rate of malicious behaviour in disasters is low (sociology)
- The threat profile is specific: dormant wallet, thin history, underwater stakes (fraud detection)
- The deterrence mechanism is strong: permanent irrevocable ban (rational choice)

...the model can be permissive for wallets with established honest patterns, and conservative only for wallets matching the actual threat profile.

### 6.1 When the Model Breaks Down

The literature also establishes failure conditions:
- Pre-existing severe social inequality (Haiti 2010)
- Absence of any social order (Katrina — institutional collapse)
- Civil disturbance context, not pure disaster

These map to the RED tier: UNDERWATER wallet + zero Ark history + COLD window = the profile consistent with opportunistic fraud in high-stress, low-order conditions. The CI correctly identifies these as RED not because people are assumed dishonest — but because this specific profile eliminates the deterrence mechanisms that make honest behaviour rational.

---

## 7. Implementation Notes

### 7.1 Everything Is Offline Verifiable

A receiver in a disaster with a paper printout of the FACT chain and a clock can make every determination in the matrix:

- K=3 timestamp: embedded in FACT chain — readable offline
- Ark link count: countable from chain — readable offline
- K=3 wallet balance: carried in chain — readable offline
- Transaction history pattern: computable from chain links — readable offline
- Validator IDs from prior Ark settlements: in chain — readable offline

### 7.2 CI Is Computed by Receiver, Not Pre-Issued

The CI is **computed by the receiver** from the **Core-signed information the sender presents** — the sender's FACT chain, whose links carry k-witness signatures and Core (DMAP) attestations. The receiver does not trust a pre-computed score; it verifies the raw, Core-signed evidence and scores GREEN/YELLOW/RED locally. This is stronger than a pre-issued credential: the receiver independently assesses risk from verifiable evidence. (Yellow Paper §11.5.3 is now aligned to this model — ruling 2026-07-17; the earlier "pre-issued signed credential issued at last online validation" is retired.)

**CI machinery is REUSED, not rebuilt (ruling 2026-07-17).** Keep the `ConfidenceIndex` struct, the `evaluate_ci` matrix, and `compute_ci_signing_message`/`verify_ci_signature`. What changes: **Core** computes the real static factors from the wallet's k=3 state and signs them into the sender's normal **k=3 receipt** (this is the "Core-signed information" the sender presents) — replacing Lambda's `issue_confidence_index`-on-every-TX with hardcoded placeholders (to be removed). Offline, the sender presents that Core-signed CI; the **receiver** verifies the signature, adds the time-dependent staleness factor from its own clock, and runs `evaluate_ci` → GREEN/YELLOW/RED. The score is the receiver's, over Core-signed static evidence + a live local clock.

### 7.3-A Same-Core Only (ASSUMPTION + HARD RULE, 2026-07-17)

An Ark↔Ark offline trade requires **both wallets to run the same CoreID**. A cross-CoreID Ark trade is REJECTED: the offline Ark evidence / `ReceiverWitness` carries the CoreID, and the receiver refuses a counterparty on a different Core version. This is a deliberate simplifying assumption for now — it avoids all cross-version offline execution/verification semantics. **Reconciliation across a *network* rotation** (the network's canonical CoreID moved while the parties traded offline on an older one) is handled separately by the **CoreID-lineage accept-set** (`AXIOM_DESIGN_CoreUpgradeMigration.md` §11): the outage-era CoreID is blessed as a prior, so the offline chain's DMAP attestations verify at re-registration. Net: **same-Core for the TRADE; accept-set for the RECONCILE-across-rotation.**

### 7.3 Core Is the Law

CI evaluation logic lives in Core (`core/logic/src/ark.rs`). The receiver's device runs Core locally to compute CI from the FACT chain. Core is the sole authority on what the factors mean and how they map to GREEN/YELLOW/RED.

### 7.4 Permanent Ban

A double-spender's wallet is permanently banned. No JFP reversal. No appeal. This is the keystone of the deterrence model. The ban is recorded in the FACT chain as a scar with conflict_count > 0, making it visible to all future offline receivers.

---

## 8. Core Design Principles

1. **More activity means more trust.** High Ark TX count = dense trail = stronger trust (inverts naive frequency-fraud assumption).
2. **Skin in the game is computable.** Stakes ratio is the single most powerful factor. Visible to receiver, no network required.
3. **The permanent ban amplifies everything.** 10x threshold grounded in asymmetry of permanent destruction vs one-time gain.
4. **Risk is visible, not hidden.** GREEN/YELLOW/RED with factor breakdown. Receiver retains final discretion.
5. **Ark mode does not promise a safe world.** It promises a world that still works when things are not safe.

---

## 10. Wallet Identity — Ark Is the k=0 Tier of the Same Keypair

Sections 2–8 price the risk of an offline transfer. Sections 10–12 specify the *mechanics* that produce and settle those transfers: the identity that authorizes value to enter Ark (§10), the offline hand-off where the receiver stands in for the validators (§11), and the return to k=3 where every offline spend is registered and any double-spend is caught (§12). All three are constrained by the **same-Core rule** (§11.8): an Ark trade requires the identical CoreID on both sides.

> **Model correction (2026-07-17).** An earlier draft of this section specified two independent keypairs bound by a *PairBinding* certificate. That is **retired.** It contradicted both YP §11.9.1 ("the same identity — same wallet PK, different tier addresses") and the actual `wallet_id` system, which already derives every tier address from one key. The two-keypair implementation was a workaround the 2026-05-16 keying-decision record (`AXIOM_DESIGN_WalletPairCollapse.md`) explicitly deferred "until the Ark protocol is built" — which is now. This section adopts the single-keypair model; the certificate, `pairs.json`-as-authority, and the email-string identity checks all go away.

### 10.1 One Keypair, Seven Tier Addresses

An AXIOM wallet is **one Ed25519 keypair.** From it, `generate_all_wallet_ids` (wallet_id.rs) derives **seven addresses**, one per security tier (YPX-007). `WALLET_ID_PARAMS[0]` is `(K_ARK=0, PROOF_TYPE_ARK)` — so **the Ark wallet is simply the k=0 tier address of that same key.** The other six (k=3/4/5 × DMAP/ZKP) are the wallet's online tiers. The tier is folded into the unforgeable `wallet_id` checksum, so the sender cannot choose or spoof it (Core extracts it via `extract_security_level`).

There is **no separate Ark keypair, no binding certificate, and no `pairs.json` as authority.** "Normal" and "Ark" are two tier-addresses of one identity, exactly as YP §11.9.1 specifies.

### 10.2 "Same Owner" Is the Shared pk

Because both addresses derive from one `pk`, *"these two wallets are the same owner"* is **provable, not asserted.** `verify_pk_binding(wallet_id, pk)` confirms an address belongs to a given key (the `pk_bind` bytes baked into the wallet_id). Two consequences fall out for free:

- **Exclusivity is automatic.** One `pk` yields exactly one k=0 address, so a wallet cannot be bound to a second, unrelated Ark wallet, and there is no "relink" primitive to attack — the entire class of binding-forgery / deterrent-double-count concerns that a certificate would have introduced simply does not exist.
- **Factor 3 works natively.** The receiver already holds the Ark wallet's `pk` (it needs it for `pk_bind` / redemption). From that same `pk` it regenerates the k=3 ("Standard") tier address and reads *its* balance as the deterrent behind the Ark spend. The two-keypair design's known **"accepted cost"** — that the offline CI could not see the shared k=3 stake (`AXIOM_DESIGN_WalletPairCollapse.md`) — disappears.

### 10.3 Charge, Unload, and Self-Ark: One pk-Binding Check

Value crosses the k=3 ↔ k=0 boundary through two witnessed (online, full-pipeline) operations, gated in Core at `validate_transaction` Step -0.4 (§11.9):

| Op | Shape | Direction | Meaning |
|----|-------|-----------|---------|
| **Charge** | normal → own Ark | load | a k=3 tier debits; the k=0 tier is funded for offline use |
| **Unload** | own Ark → normal | recede-complete | reconciled Ark value returns to a k=3 tier |

Both are transfers between two tier-addresses of the **same key**. The three §11.9 rules (charge-by-owner, Ark→non-Ark with the unload exception, and the self-send ban) previously used **email-string equality** (`sender_wallet_id.split('/') == receiver_wallet_id.split('/')`) as a proxy for "same owner" — a weak proxy that existed *only* because two independent keypairs shared nothing cryptographic to compare. That proxy is **replaced by the pk-binding check**: the counterpart address must `verify_pk_binding` against the transaction's established `pk`. **Same key = same owner, unforgeable;** email equality is deleted, not kept alongside (a second weaker check is exactly the seam that drifts). This also removes the latent unload-unreachable interaction the email checks caused.

No new identity errors are needed (`ArkChargeNotOwner`, `ArkToNonArkRejected`, `ArkUnloadScarred`, `SelfSendRejected` already exist); the *check* behind them changes from string-compare to pk-binding.

#### 10.3.1 Scar Scoping

- **Unload requires a fully-healed chain.** An unload is refused if the Ark chain carries any scarred (unreconciled) link — `has_scars()` must be clean. Unloading with an open scar would let unregistered, possibly-double-spent value re-enter k=3 ahead of the consume-once check that settlement (§12) exists to run. Value recedes to k=3 only after every offline spend it carries has been registered.
- **Which chain feeds which factor.** The §3 unconditional scar override (any scar ⇒ RED) reads the **presented k=3 chain only** — a broken *provenance* root is disqualifying. A wallet's *own* open k=0 scars (its unreconciled recent spends) are not a provenance break; they feed **Factor 2** (Ark tx count / recency) as ordinary offline history. Conflating the two would make every actively-trading Ark wallet permanently RED, defeating the mode.

### 10.4 Ban Propagation Is Automatic Across Tiers

The permanent ban (§7.4) is the keystone deterrent, and Factor 3 makes it bite by staking the k=3 reserve behind the Ark spend. Under one keypair that economic link **is** already a protocol link: when the k=0 tier is banned for a double-spend caught at settlement (§12.3), the ban covers the **whole keypair** — every tier address, including the k=3 reserve — because they are the same `pk`. There is nothing to "link"; they were never separate. This is what makes Factor 3's deterrent real: forfeiting the Ark conduct forfeits the staked reserve, because it is one key. Propagation runs at the Nabla layer and reuses the KI#34 endorsement-ban model, with the ban target being the `pk` (hence all of its wallet_ids). No certificate is needed to prove the tie.

### 10.5 Tier-Aware State Identity (the enabling change)

Historically a wallet's on-ledger state was keyed on `pk` **alone**, with no tier — so under one shared key the k=3 and k=0 states would collide. Convergence makes state identity tier-aware. This is the **one substantive protocol change** the single-keypair model requires:

- **Genesis `state_id` — and ONLY genesis** — folds the tier `(k, proof_type)` into the hash: `SHA3("AXIOM_GENESIS" ‖ pk ‖ balance ‖ k ‖ proof_type)`. Because every `produced_state_id` chains through `consumed_state_id` back to genesis, tier-distinctness **propagates through the entire state chain automatically**, and `validate_transaction`'s `consumed_state_id == prev_receipt.produced_state_id` chain check (the "Core independent double-spend check") rejects any cross-tier receipt *before* `state_hash` is ever compared. So **`state_hash`, `produced_state_id`, and `redeem_state_id` do NOT need the tier** — the chain check already discriminates. (This corrects an earlier conservative draft that said `state_hash` carries the tier; it does not, and adding it there would have touched ~15 extra call sites for no safety gain.) Proven by the cross-tier collision test `genesis::tests::genesis_tier_distinct_and_propagates`, which ships before the CoreID rotates.
- **Lambda** keys the authoritative wallet-state row by **`wallet_id`** (equivalently `(pk, k, proof_type)`) instead of `public_key` — the `wallets`, `genesis_states`, and `witness_cache` tables plus the `get/set_wallet_state` accessors. **Nabla is already `wallet_id`-keyed** (its SMT / consume-once), so it needs no change.

This is `CONSENSUS_CRITICAL`: it **rotates the CoreID**, regenerates golden/conformance vectors, and requires a **clean `--data`** (pre-mainnet, no backward-compat per CLAUDE.md §13). It touches no commitment *value* beyond the state-identity formulas above; cheque/receipt/FACT commitments that already carry `wallet_id`/`txid` are unaffected.

### 10.6 Creation: the SDK Surface Stays the Same

The user-visible onboarding is **unchanged**: `create_pair` still returns a normal wallet and an Ark wallet, two wallet directories, the same FFI, the same backup ceremony. The **only** internal change is that the keypair and `wallet_secret` are **generated once and shared by both members** (the Ark member reuses the normal's key material) instead of each minting fresh randomness. `pairs.json` survives as a **UI cache**; the load-bearing link between the two is now the shared `pk` (derivable, never stored — lose the file and the pairing is recomputable).

**Security note (honest).** One key means the k=0 and k=3 authority share a secret, so an offline compromise of the device exposes the reserve too. This is accepted because the Ark deployment already keeps both on the same mobile device — both must be present to charge and to trade — so the two-keypair "isolation" was mostly notional. True key isolation is the one property that would break Factor 3's shared-stake visibility (§10.2), which is the stronger requirement.

---

## 11. Receiver-as-Witness — The Offline k=0 Trade

### 11.1 The Model: the Receiver Stands In for the Validators

In a k=3 send, three VBC-anchored validators witness the transition. Offline, in the flood, there are none. YPX-010's answer is not to trust the sender's word but to make **the receiver the witness**: the party with everything to lose runs canonical Core itself, over the sender's Core-signed evidence, and co-signs the transition it accepts. The k=0 "witness set" is exactly `{receiver}`, size 1 — but it is the *right* one, because the receiver is the only party whose incentive is to reject a bad transfer, and its acceptance is what the §2–§4 Confidence Index informs.

This is why the CI is mandatory and receiver-computed (§11.6): the witness *is* the risk-bearer, so the witness decision *is* the CI decision.

### 11.2 The Offline Session

The trade is a four-message exchange over the mobile p2p channel (BUILD Gate 0 — BLE primary, animated-QR fallback), auto-advancing inside one screen-to-screen hold:

| Leg | From → To | UMP envelope | Payload |
|-----|-----------|--------------|---------|
| R0 | Receiver → Sender | payment request | amount, receiver identity |
| S1 | Sender → Receiver | `WitnessRequest` | the tx + sender sig (+ CI evidence: the tip k=3 link, delta-synced) — the sender's `pk` rides the sig, so the receiver derives the k=3 tier address itself (§10.2), no cert on the wire |
| R2 | Receiver → Sender | witness response | the `ReceiverWitness` (receiver's co-signature) — emitted only after an explicit CI accept |
| S3 | Sender → Receiver | cheque UMP | the k=0 cheque the receiver will redeem locally |

Every leg is an **existing** typed UMP envelope under the k=0 profile — no new envelope kinds (BUILD §3.3, Rule 0.2). QR/BLE chunking is app-level framing around the UMP bytes, never a re-encoding.

The DMAP attestation does **not** cross the channel. It is ~14 KB and, more importantly, unnecessary on the wire: each wallet keeps its own attestations for reconciliation (§12), and the receiver **re-executes Core at the till**, which is strictly stronger than verifying the sender's attestation (BUILD Gate 0). The leg payloads therefore stay small enough for single frames; only the CI *evidence* (the k=3 chain) can exceed one frame, and it is tip-only + delta-synced against a repeat counterparty's held prefix.

#### 11.2.1 ReceiverWitness and Chain Building

The receiver's co-signature is a dedicated typed struct — **not** a reused validator `FactWitness`:

```
struct ReceiverWitness {
    receiver_pk: [u8; 32],   // Ed25519
    signature:   [u8; 64],   // over the transition commitment
}
```

A validator `FactWitness` carries Dilithium `Vec<u8>` fields and a `BLAKE3(sphincs_pk)` id; reusing it for a 32-byte Ed25519 key would force algorithm-guessing by length — a §13 ambiguity. `ReceiverWitness` is unambiguous. It lives on `FactLink` as `receiver_witness: Option<ReceiverWitness>`, **outside** `compute_fact_commitment` (all witness material sits outside the commitment), so no commitment formula changes. It survives settlement *in place* — the ordinary FACT-link validation confirms this receiver-Core signature, which is what proves the settled link was a real ⟠ trade (§12.2) — while validators later append their Dilithium `FactWitness` entries into the separate `witnesses` vector.

**Each party's own Core builds only its own link** (BUILD §3.1). The sender's Core builds the *send* link at leg-2 ingest (finalize-at-round-success, exactly as online); the receiver's Core builds the *redeem* link at its local CL5 (leg 3). The session orchestrates the exchange; neither SDK assembles anything — Core is the sole cryptographic authority on both devices. Mobile does no Dilithium *signing* (verify-only); PQ signing is re-applied at reconciliation.

### 11.3 The k=0 Witness Floor

Quorum is not hardcoded. One shared function decides the required witness count for every tier and operation:

```
required_witness_floor(tier, op) -> u8
```

- k=0 Ark wallet, ⟠-trade anchor → **1** (the receiver), and
- everything else → **3**, unchanged.

`verify_state_anchored`'s former hardcoded `>= 3` is modified to call it (BUILD §3.1) — a floor bug is then fixed in one place, and the k≥3 path is provably untouched (it still resolves to 3). Tier is read from the unforgeable wallet_id checksum via `extract_security_level`, so the floor cannot be spoofed by claiming a lower tier.

**Witness eligibility** branches on the same function: for a k≥3 anchor only VBC-anchored validator signatures count; for a k=0 trade anchor exactly the receiver's wallet key counts, matched against the `receiver_wallet_id` pk binding (exclusivity, §11.7). One verifier, one tier branch — not a second `validate_ark_transaction`.

### 11.4 The k=0 CL2 / CL5 Profiles

- **CL2 (witness leg).** The receiver validates the sender's transition through the **same** `validate_transaction` path a validator runs; the k=0 profile only selects the witness-eligibility branch above. No parallel Ark validator.
- **CL5 (redeem leg).** `execute_cl5`'s required-input set is tier-defined: the k=0 profile drops `txid_attestation` / `cheque_claim_proof` — they are Nabla-registration artifacts and cannot exist offline. This is a **profile, not an `Option` fallback**: the k≥3 path still hard-requires them (no `serde(default)`, no "if present"). The receiver then runs its ordinary local single-cheque redeem.

### 11.5 S1: `NablaConfirmation` Forbidden on a k=0 Link

Offline, Nabla is absent, so a k=0 link *cannot* legitimately carry a `NablaConfirmation`. Its presence on a k=0 link is malformed and **rejected** (BUILD §3.1). The rule is stated as the rejection-of-presence, not merely the default-of-absence, so a forged confirmation cannot smuggle a k=0 spend into looking registered before reconciliation has actually registered it.

### 11.6 The Confidence Index at the Till

The receiver's accept decision **is** the witness, and it is computed locally:

1. **The sender presents Core-signed evidence.** The trust factors are not the sender's word — Core computes the real factors (last-k=3 timestamp, k=3 balance, Ark tx history, amounts, ecosystem) and signs them into the sender's k=3 receipt during ordinary online activity. The sender carries that Core-signed FACT chain; the receiver **verifies the signatures**, then recomputes the factors from the chain to confirm they match what Core signed. The deprecated Lambda-issued "signed CI credential" (`issue_confidence_index`) is **retired** — no online authority pre-blesses an offline trade.
2. **The receiver adds the live factor.** Staleness (Factor 1) and the two-clock model (§2 aggregation) depend on *now*, which no past signature can carry. The receiver reads them against its own monotonic TARDIS clock — the receiver's own last-k=3 tick is un-gameable — and folds them into the score. The global disaster clock `D_t` uses the *older* of the two parties' last-k=3 ticks (§2), so a stale sender cannot hide the depth of the outage.
3. **The receiver scores and decides.** The existing `ark.rs::evaluate_ci` produces GREEN / YELLOW / RED from the five factors, the §3 unconditional overrides, and the §2 overlap model. The **CI machinery is reused, not rebuilt** — `ConfidenceIndex`, `evaluate_ci`, the factor readers, and the receipt-signing path all stay; only the *issuer* changes from Lambda-placeholder to Core-signs-factors / receiver-scores.

**Mandatory CI, no auto-witness.** The receiver session computes the CI on every trade and will **not** emit leg R2 without an explicit, app-supplied accept decision. GREEN is a recommendation, never an auto-accept; the risk-bearer retains final discretion (§8 principle 4). A RED (any unconditional override — scar on the presented k=3 chain, no-k=3-ever, underwater stakes, unknown-ecosystem-plus-significant-amount) surfaces the refusal reason.

### 11.7 Level Enforcement, Exclusivity, and the Online-Trade Ban

- **Both parties must be k=0.** The Ark session opens only if *both* wallet_ids are the Ark tier (§11.3 floor read). A k=3 wallet does not trade in Ark mode; it charges its own Ark (k=0) address (§10.3) and trades online.
- **Witness exclusivity.** For a k=0 anchor the *only* eligible witness key is the receiver's, pk-matched to `receiver_wallet_id`; a validator signature does not count toward a k=0 floor and a receiver signature does not count toward a k≥3 floor (§11.3).
- **No online Ark trade.** `S=ARK && R=ARK` presented to the *witnessed* (online) pipeline is rejected with `ArkOnlineTradeRejected` (`E_ARK_ONLINE_TRADE_REJECTED`, BUILD §2.2, W7). Ark-to-Ark is the offline mode by construction; an online Ark-to-Ark transfer is a category error and is refused rather than silently re-routed.

### 11.8 Same-Core Hard Rule (Assumption)

**An Ark trade requires the identical CoreID on both sides.** A trade whose two parties present evidence bound to different CoreIDs is **rejected**. This is adopted as both a hard rule and a simplifying assumption for the current design (project ruling, 2026-07-17): the offline evidence carries the CoreID it was produced under, both devices re-execute Core, and cross-version offline consensus is out of scope. See §7.3-A.

This does **not** strand value across a *network*-wide CoreID rotation that happens during an outage. That case is handled at reconciliation by the CoreID-lineage **accept-set** (`AXIOM_DESIGN_CoreUpgradeMigration.md` §11): the outage-era CoreID is blessed as a non-revoked prior, so the offline chain's DMAP attestations verify against `{current} ∪ {blessed priors}` when the wallet comes back online (§12.6). Same-Core governs the *peer-to-peer trade*; the accept-set governs the *return to k=3*.

---

## 12. Settlement — Recede to k=3

Settlement is the "recede" leg (§1.4), and it is the **second step of a two-step Ark transaction**:

1. **Step 1 — the offline trade (§11).** Value moves ⟠→⟠ with the receiver's Core as the witness (receiver-as-witness). Because the transfer is never registered, each resulting FACT link is **scarred** (unregistered) — the disclosed risk the CI priced.
2. **Step 2 — settlement.** When an online path returns, each piled-up scarred link is **replayed through the ordinary transaction path** to register it, heal the scar, and — if the same state was spent twice offline — catch the double-spend.

The design rule for Step 2 is **total reuse, zero clone** (BUILD §0.1): settlement is *not* a bespoke re-witnessing pipeline. **Core and Lambda run the existing transaction code with minimum change.** The only addition is **one flag** on the transaction, and its single behavioral effect is this: **when Lambda sees the flag, it does not emit the cheque.** Everything else — Core validation, consume-once, the fork ban, k=3 witnessing, and (should validators be dead) HAL resurrection — is byte-identical to a normal transaction.

### 12.1 The Settlement Flag — the One New Thing

`Transaction.is_settlement: bool` follows the **exact** `is_recall` / `is_hal_reanchor` precedent: a boolean field on the existing `Transaction`, bound into `to_canonical_value` the same way those two are, and audited at **every** strip-and-reconstruct site (`sdk/client/src/cl1.rs`, `send.rs`, the wasm `cl1_inputs.rs`) — the `is_recall` "unknown field" lesson applies (`[[feedback_strict_dispatch_audits_call_sites]]`). It is **not** a new `TxKind` variant and **not** a cloned `validate_ark_settlement` path. Like `is_recall`, the flag rides the tx canonical value, so **zero** receipt / cheque / FACT commitment formula moves.

**Core** treats the flag as an ordinary canonical-value field — the signatures cover it, and validation is otherwise unchanged. **Lambda** reads exactly one branch off it: **skip cheque issuance.** In a normal send Lambda validates → registers (consume-once) → witnesses → **issues a cheque to the receiver**. A settlement runs the first three identically and **omits the last step**, because the receiver already redeemed its cheque offline in Step 1 (§11, leg 3). Issuing a second cheque would double-pay. That omission *is* the feature; there is no other behavioral change.

Consequently settlement is **registration-only** and idempotent per txid: a state some validator already registered settles as a no-op, and a chain of offline spends settles in order.

### 12.2 Settlement Is the Normal Transaction Path

At settlement the wallet walks its scarred FACT links and pushes each — in chain order, `is_settlement = true` — through the **ordinary** pipeline. Because it *is* the ordinary pipeline (minus the cheque), settlement inherits, with no Ark-specific code:

- **consume-once + the fork ban** — the double-spend catch (§12.3) is the normal path's `SeqForkBan`, not an Ark twin;
- **k=3 witnessing** — a normal witness round anchors the state into Nabla's SMT and marks it consumed; the scar heals and `nabla_confirmation` becomes present;
- **HAL** — if the wallet's prior witnesses happen to be dead, the normal path already resurrects via HAL (§12.5). Ark builds nothing for this.

This is the whole point of routing through the normal path: every hard problem of "get a state witnessed and consume-once-checked" is already solved there, once, for all transaction kinds. The offline link the flag settles already carries its Step-1 receiver-Core signature (§11.2.1), so the ordinary FACT-link validation confirms a real ⟠ trade — no separate settlement-only gate is added.

### 12.3 Double-Spend Is Caught by the Normal Path

Settling the offline state enters it into the **global consume-once check** for the first time. If the sender spent the same predecessor state to more than one offline receiver, the two settlements collide: the normal path's same-sequence fork ban fires, the wallet is permanently banned (§7.4), and because every tier address is the same `pk`, the ban covers the whole keypair including the k=3 reserve (§10.4). Settlement is *the* place an offline double-spend is adjudicated — offline, the CI only *priced* the risk. The consume-once refusal + fork evidence drive the existing `SeqForkBan` machinery; **no new conflict pipeline**.

Both offline receivers may have correctly accepted (the CI bounds risk, it does not eliminate it). First-settlement-wins; the loser's link is fork-refused and resolved by burn (§12.4).

### 12.4 Conservation and Burn Resolution

The resolution of a caught double-spend must not create or destroy value — the quarantine ledger nets to **zero, atom-exact**, asserted automatically in every Ark soak (a conservation invariant as CI, not prose). Two rules make it hold:

**(a) Full-amount resolution burn.** A burn resolving a fork-refused k=0 link requires `amount == the scarred amount`. The KI#13 `min()` cap explicitly **does not** apply to this class: the cap defends against *fake* scars by refusing to burn more than the disputed value, but this scar is *proven real* by the fork-refusal evidence, so a capped burn would leak the uncovered remainder as phantom value. `validate_burn_target` requires the full amount for this class only. If the victim's balance is short, the documented path is an ordinary W2 charge to top up, then burn — value is conserved, not invented.

**(b) Burn-first bridging.** So the victim is not blocked behind the fork, the burn advances Nabla's SMT ahead of full downstream settlement, reusing the KI#5 advance-on-proof (`PartialBridgeReceipt`) with its accepted-proof shape extended to include a burn-resolved k=0 segment.

### 12.5 Dead Validators and HAL — Rides In For Free

There is **no Ark-specific dead-validator work**. If a settling wallet's prior witnesses have died (the dead-overlap condition), the settlement tx — being an ordinary tx on the normal path — is resurrected by **HAL** (YPX-020, shipped) exactly as any other stuck tx is. Settlement has no machinery of its own for HAL to "compose" with; it *is* the normal path, and the normal path already carries HAL. The logic is identical, so nothing is duplicated.

**For the current design we assume a healthy network — no dead validators** — so this path is not exercised yet. It is called out only to record that when it *is* exercised, it is automatic. (This supersedes an earlier open "dead-overlap × HAL" item that wrongly assumed Ark needed its own HAL integration.)

### 12.6 CoreID Rotation During the Outage

Because Ark trades are same-Core (§11.8), an offline chain is internally consistent under one CoreID — the one in force when the outage began. If the *network* rotates CoreID while the wallet is offline, settlement would normally fail with `WrongCore` (the offline attestations are bound to the retired CoreID). This is resolved by the **CoreID-lineage accept-set**: the outage-era CoreID is blessed as a non-revoked prior compiled into the guest ELF, so the offline chain's attestations verify against `{current} ∪ {blessed priors}` at settlement (`AXIOM_DESIGN_CoreUpgradeMigration.md` §11). The accept-set check runs first on the normal path and is unaffected by the settlement flag. No offline value is stranded by a rotation the trader could not have known about.

### 12.7 OODS Gate

Settlement registration requires `oods_view_healthy` — the same gate `advance_fact_checkpoint` already enforces. A settlement does not register against a divergent or unhealthy OODS view; the offline spend waits for a healthy anchor rather than committing to a fork.

---

## 13. Document Information

| Field | Value |
|-------|-------|
| Specification | YPX-010 — Ark Mode Confidence Index |
| Yellow Paper refs | §6.9 (Ark-Mode), §11.5 (Confidence Index), §11.9 (charge/unload/pair), §26 (FACT chain), §32 (parallel-TX fork ban) |
| YPX deps | YPX-007 (Receiver-Defined Security Level) |
| Design/Build refs | `AXIOM_BUILD_ARK_v1.md` (implementation plan, §-keyed to §10-12); `AXIOM_DESIGN_CoreUpgradeMigration.md` §11 (CoreID accept-set) |
| Academic fields | Disaster infrastructure; behavioural fraud detection; rational choice economics; skin-in-the-game theory; financial anomaly detection; disaster sociology |
| Key constraint | 100% offline verifiable — all five factors computable from FACT chain alone; same-CoreID on both sides of a trade (§11.8) |
| CI outputs | GREEN (proceed), YELLOW (judgment), RED (refuse) |
| Normative scope | §0-9 CI evaluation; §10 single-keypair identity (Ark = k=0 tier of the same key, YP §11.9.1); §11 Receiver-as-Witness offline trade; §12 Settlement (two-step: offline trade + settlement flag, no open items) |

---

*Document history: initial public release 2026-07 (§0-9, CI evaluation). v0.3 2026-07-17 — added the normative money-movement mechanics §10 PairBinding, §11 Receiver-as-Witness, §12 Settlement, against the 2026-07-17 rulings (two-keypair bound pair; receiver-computed CI from Core-signed evidence; "Asynchronous Resilience Ketch"; same-CoreID-only trades; CI machinery reused). §12 was then simplified to the **two-step model** (project ruling, 2026-07-17): an Ark tx is (1) an offline ⟠→⟠ trade witnessed by the receiver's Core, then (2) settlement — each scarred link replayed through the **existing** transaction path with a single `is_settlement` flag whose only behavioral effect is that Lambda skips cheque issuance. Consume-once, the fork ban, and HAL are inherited from the normal path unchanged; the earlier "§12.6 dead-overlap × HAL" open item is dissolved (HAL rides in free). §10 was then corrected (project ruling, 2026-07-17) from the two-keypair PairBinding-certificate model to the **single-keypair model** (YP §11.9.1): the Ark wallet is the k=0 tier address of the *same* keypair, identity/self-ark is the shared `pk` (`verify_pk_binding`, retiring the email-string checks and the certificate), and the enabling change is tier-aware state identity (genesis/`state_hash` fold in the tier; Lambda keys state by `wallet_id`). From this release onward, every change to this document is recorded here and in the repository git log.*
