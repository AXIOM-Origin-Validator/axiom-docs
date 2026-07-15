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

Unlike Yellow Paper §11.5's original "signed credential" model, the CI in this specification is **computed by the receiver** from the sender's FACT chain. The receiver does not trust a pre-computed score — they verify the raw data themselves. This is stronger: the receiver independently assesses risk from verifiable evidence.

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

## 9. Document Information

| Field | Value |
|-------|-------|
| Specification | YPX-010 — Ark Mode Confidence Index |
| Yellow Paper refs | §6.9 (Ark-Mode), §11.5 (Confidence Index), §26 (FACT chain) |
| YPX deps | YPX-007 (Receiver-Defined Security Level) |
| Academic fields | Disaster infrastructure; behavioural fraud detection; rational choice economics; skin-in-the-game theory; financial anomaly detection; disaster sociology |
| Key constraint | 100% offline verifiable — all five factors computable from FACT chain alone |
| CI outputs | GREEN (proceed), YELLOW (judgment), RED (refuse) |

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
