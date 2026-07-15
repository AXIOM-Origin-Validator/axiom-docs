# AXIOM YPX-012: Oracle Distribution Protocol

**Version:** 0.3
**Status:** Implemented (Core wired, security audited, webclient dashboard)
**Depends on:** YPX-001 (FACT Chain), YPX-007 (Receiver Security), YPX-008 (VSP)
**Author:** AXIOM Origin
**Date:** 2026-03-24

---

## 1. Overview

The Oracle Distribution Protocol governs how AXIOM's Market Reserve Pool of 88,000,000 AXC enters circulation. Contributors earn AXC by doing verified citizen science work on 11 whitelisted platforms.

### 1.1 Design Principle

Oracle claims are **transactions**, not a separate protocol. They flow through the same CL1-CL5 pipeline as every other AXIOM transaction. No new infrastructure, no external library dependencies in Core.

### 1.2 Key Properties

- k=5 witnesses required (each >= 1M AXC stake via NablaStakeProof)
- Self-payout only (sender == receiver, Core-enforced)
- 48-hour cheque maturity before redeem
- 5 AXC per claim maximum
- 24-hour interval per (platform, user_id) binding
- Daily platform pool caps total extraction
- VBC freshness: oracle witnesses must renew VBC every 24 hours (ORACLE_VBC_RENEWAL_TICKS)
- Stake FACT clean: scar_count == 0 required (OracleStakeScarred if scarred)

---

## 2. Security Model — 4 Defenses

All enforced using BLAKE3 + Ed25519 only. No external dependencies.

### 2.1 Defense 1: Cross-Validator Verification (k=5)

k=5 independent validators each query the platform API independently, observe the contributor's credit count, and witness the transaction. Standard CL2/CL3 flow with higher k.

### 2.2 Defense 2: Claim Chain (FACT Chain)

Every oracle payout produces a FACT link. Retroactive insertion of fake past claims breaks the FACT chain hash. Automatic — no new code.

### 2.3 Defense 3: Velocity Cap

| Limit | Value | Enforcement |
|---|---|---|
| Per claim | 5 AXC max | Core CL5 |
| Per (platform, user_id) | 24h interval | Core `process_oracle_claim_inner` |
| Per platform per day | ~2,410 AXC (F@H, 10%) | DailyPoolState |
| Total daily emission | 24,109 AXC | All platforms combined |

### 2.4 Defense 4: 48-Hour Cheque Maturity

Oracle cheques cannot be redeemed until 48 hours after witnessing. `ORACLE_MATURITY_TICKS = 34,560`. Checked at CL5 redeem time.

### 2.5 Defense 5: VBC Freshness (24-Hour Renewal)

Oracle witnesses must have a VBC issued within the last 24 hours (ORACLE_VBC_RENEWAL_TICKS = 17_280 ticks × 5 sec = 86_400 sec). This is stricter than the standard 30-day VBC window (Yellow Paper §25.5.4).

A validator who drops below 1M AXC stake cannot continue oracle witnessing for more than 24 hours before the freshness check rejects them.

VBC renewal uses the standard CL8 path. Operators configure their validator to trigger CL8 renewal on a 24-hour schedule via vbc_renewal_interval_secs in OracleConfig. No oracle-specific renewal function exists.

Core enforcement: ValidationError::OracleVBCTooOld if any witness VBC has issued_at older than ORACLE_VBC_RENEWAL_TICKS ticks before tx.epoch.

### 2.6 Defense 6: Clean Stake FACT Chain

The validator's stake wallet must have zero unresolved FACT scars (scar_count == 0 in NablaStakeProof). A scarred FACT chain indicates the validator's wallet was involved in a disputed transaction or network partition event — their state is not fully settled.

Core enforcement: ValidationError::OracleStakeScarred if NablaStakeProof.scar_count > 0. Fires after the stake balance check.

A scarred validator can resume oracle witnessing only after their FACT chain is healed (NablaConfirmation received) or burned (YPX-001 §1.5.4). Reference: Yellow Paper §34 (Scar semantics), YPX-001 §1.5.

### 2.7 Defense 7: ZK-TLS Lambda Verification + NablaStakeProof

Lambda verifies oracle claims before passing them to Core:

1. **ZK-TLS verification** (consensus.rs): If `oracle_claim.zktls_proof` is present, Lambda calls `oracle_zktls::verify_zktls_proof()` before Core witness production. Invalid proofs are rejected immediately — Core never sees the TX. Stub implementation accepts any non-empty blob; production replaces with `tlsn_core::verify()`.

2. **NablaStakeProof fetch** (consensus.rs): For oracle TXs, Lambda queries Nabla `/query` to confirm the validator's wallet is registered and cross-checks the state_id with local storage. Both VBC balance AND Nabla registration are required — VBC alone is insufficient because balance may have moved since VBC issuance. The proof includes:
   - `balance`: from local storage (current wallet balance in atoms)
   - `scar_count`: counted from stored FACT chain (`FactChain::scar_count()`)
   - `attested_state_id`: from Nabla query (cross-checked against stored state_id)
   - `nabla_tick`: from Nabla query (freshness)

   Core step 3e (`validation.rs`) rejects if balance < 1M AXC (`OracleInsufficientStake`) or scar_count > 0 (`OracleStakeScarred`).

Lambda implementation: `consensus.rs::fetch_own_nabla_stake_proof()` (async, queries Nabla HTTP, builds proof). Wired at both CL3 call sites (process_witness_request, finalize_transaction). Non-oracle TXs pass `None`.

---

## 3. Core Implementation (Wired into CL1-CL5)

### 3.1 Transaction Structure

Oracle claims use the standard `Transaction` struct with an additional field:

```rust
pub struct Transaction {
    // ... standard fields ...
    pub oracle_claim: Option<OracleClaimData>,  // YPX-012
}

pub struct OracleClaimData {
    pub platform_url: String,     // Must match whitelist exactly
    pub user_id: u64,             // Platform's immutable ID
    pub username: String,         // Must contain Living Signature
    pub credit_total: u64,        // Current credits observed by validators
    pub credit_delta: u64,        // Growth since last claim
}
```

The `OracleClaimData` is also propagated to `ValidatorCheque` for CL5 maturity and payout checks.

### 3.2 CL1/CL2 Validation (`validation.rs`)

When `tx.oracle_claim.is_some()`, Core enforces:

1. **sender == receiver** — self-payout only (like Ark Rule 1)
2. **Platform whitelisted** — URL must match `WHITELIST` exactly
3. **Living Signature** — username contains `AXM_<BLAKE3("AXIOM_LIVING_SIG" || wallet_id)[0..8].hex()>`
4. **credit_delta > 0** — must have new work
5. **amount == 0** — payout computed from credits, not from amount field
6. **k >= 5** — Core-extracted from receiver wallet_id (YPX-007), checked AFTER extraction (not client-supplied)

Oracle TXs are exempt from dust limit (amount is 0).

### 3.3 CL5 Redeem (`modes.rs`)

When redeeming oracle cheques:

1. **Maturity check** — `cheque.created_at + 48h <= current_tick`
2. **Oracle consistency** — ALL k cheques must have identical `oracle_claim` data (prevents unsigned-field tampering)
3. **Amount cross-check** — oracle cheques MUST have `amount == 0` (prevents hybrid TX attack)
4. **credit_delta sanity** — `credit_delta <= credit_total`
5. **Payout validation** — `payout_amount` is computed by Lambda (from `OracleConfig.conversion_rates`), Core enforces `payout_amount <= ORACLE_MAX_PAYOUT_PER_CLAIM` (5 AXC)
6. **Velocity cap** — per-claim cap only; daily/per-address limits enforced at Lambda layer
7. **Balance math** — `current_balance + effective_amount == new_balance`

### 3.4 Constants

```rust
pub const ORACLE_K: usize = 5;                    // k=5 witnesses required
pub const ORACLE_MIN_STAKE: u64 = 1_000_000;      // 1M AXC minimum per witness
pub const ORACLE_MATURITY_TICKS: u64 = 34_560;    // 48h at 5s/tick
pub const ORACLE_MAX_PAYOUT_PER_CLAIM: u64 = 5;    // 5 AXC per claim
pub const TOTAL_RESERVE: u64 = 88_000_000;         // Total oracle reserve
pub const DAILY_EMISSION: u64 = 24_109;            // AXC/day across all platforms
pub const CLAIM_INTERVAL_TICKS: u64 = 17_280;     // 24h between claims per binding
```

### 3.5 Error Variants

```
E_ORACLE_SENDER_MISMATCH        — sender != receiver
E_ORACLE_INSUFFICIENT_K         — k < 5 (Core-extracted, not client-supplied)
E_ORACLE_PLATFORM_INVALID       — URL not in whitelist
E_ORACLE_LIVING_SIG_MISSING     — username missing AXM_<hex>
E_ORACLE_ZERO_DELTA             — no new work
E_ORACLE_NONZERO_AMOUNT         — oracle TX must have amount == 0
E_ORACLE_MATURITY_NOT_REACHED   — cheque < 48h old
```

---

## 4. Security Audit Results

Two rounds of attack analysis were performed. All vulnerabilities found were fixed.

### 4.1 First Audit (White-Hat)

| ID | Attack | Severity | Fix |
|---|---|---|---|
| G1 | 48h maturity not checked at CL5 | CRITICAL | Added maturity check in `execute_cl5()` |
| G2 | Velocity cap defined but not enforced | HIGH | Added `payout > MAX` check at CL5 |
| G3 | Oracle TX could use k=3 instead of k=5 | HIGH | k check moved after Core wallet_id extraction |
| G5 | Oracle checks not in CL1/CL2 pipeline | CRITICAL | Oracle validation inlined in `validation.rs:107-142` (sender==receiver, whitelist, living sig, amount==0, delta>0). `validate_oracle_tx()` in oracle.rs used for unit tests. |

### 4.2 Second Audit (Black-Hat)

| ID | Attack | Severity | Fix |
|---|---|---|---|
| A1 | k bypass: `required_k = 0` skips check | CRITICAL | Check uses Core-extracted k, not client-supplied |
| A3 | Hybrid TX: `amount > 0` + oracle_claim | HIGH | Oracle TX requires `amount == 0` |
| A5 | Forge oracle_claim on normal cheque | HIGH | CL5 cross-checks `amount == 0` for oracle |
| A6 | credit_delta inflation | MEDIUM | `credit_delta <= credit_total` sanity check |
| B6 | Modify credit_delta on signed cheque | HIGH | All k cheques must have identical oracle_claim |

### 4.3 Attacks Verified as Blocked

| Attack | Why it fails |
|---|---|
| Mix oracle + normal cheques | `verify_consistency` forces matching amounts |
| Double-redeem at different validator | Lambda per-validator tracking + Nabla state |
| Front-run someone's F@H work | Living Signature binds account to specific wallet_id (BLAKE3 hash, unforgeable) |
| 5-validator cartel | 274 years to recover 5M stake at 5 AXC/claim |
| Sybil F@H accounts | Each needs real k=5 witnessing; daily pool caps total |

---

## 5. Transaction Flow

### 5.1 Witness Phase (Day 1)

```
Contributor → builds oracle TX (sender == receiver, amount=0, oracle_claim data)
  → sends to k=5 validators
  → each validator independently queries platform API
  → each verifies: credits match, Living Signature present
  → each witnesses via CL2/CL3 (standard flow)
  → each sends cheque back (with oracle_claim propagated)
  → contributor holds 5 cheques
```

### 5.2 Redeem Phase (Day 3, 48h+ later)

```
Contributor → bundles 5 cheques
  → submits for CL5 redemption
  → Core checks: maturity >= 48h, all oracle_claim identical, amount == 0
  → Lambda computes: payout_amount from OracleConfig.conversion_rates
  → Core checks: payout_amount <= 5 AXC, credit_delta <= credit_total
  → Core updates balance: current + payout = new
  → AXC credited to contributor's wallet
```

---

## 6. Credit Conversion

### 6.1 Current Model

```
payout_amount = credit_delta / conversion_rate (integer division, floor)
# Computed by Lambda from OracleConfig; Core only enforces the 5 AXC cap
```

### 6.2 Conversion Rates (Initial Estimates)

| Platform | Rate (credits/AXC) | Category | Notes |
|---|---|---|---|
| Folding@Home | 10,000 | Compute | ~1 day GPU work = 1 AXC |
| Einstein@Home | 8,000 | Compute | |
| Rosetta@Home | 8,000 | Compute | |
| LHC@Home | 8,000 | Compute | |
| Milkyway@Home | 8,000 | Compute | |
| Universe@Home | 8,000 | Compute | |
| World Community Grid | 8,000 | Compute | |
| Zooniverse | 2 | Classification | 2 classifications = 1 AXC |
| iNaturalist | 20 | Classification | 20 observations = 1 AXC |
| OpenStreetMap | 3 | Mapping | 3 edits = 1 AXC |
| Wikipedia | 5 | Mapping | 5 edits = 1 AXC |

### 6.3 Known Limitation

These rates are initial estimates. The relative effort across platform categories (compute vs classification vs mapping) is not well-calibrated. A Zooniverse user doing 20 classifications (~10 minutes) earns 5 AXC, while a F@H user running a GPU for a day earns 1 AXC. This imbalance may cause:

- Contributors flock to easiest platform
- Easy platform pools drain early in the day
- Hard platform pools sit unused

**Mitigating factors:**
- Daily pool caps limit total extraction per platform
- Self-balancing: when easy pool drains, users switch to available pools
- Console governance can propose rate adjustments (future)

**CRITICAL PRE-LAUNCH:** Before official release, the following must be reviewed:
1. Conversion rates must be calibrated against real platform data (see Section 11)
2. Rate computation is now in Lambda (`OracleConfig.conversion_rates` in TOML) — Core only enforces the 5 AXC/claim cap
3. Core's security role is the cap and balance math, not the rate
4. Operators can adjust rates via Lambda config without Core ELF rebuild

See Section 11 for research requirements.

**KNOWN TRUST TRADEOFF (M2 from static review):**

Oracle payout amounts are computed by Lambda, not Core. Core enforces only the hard cap
(`ORACLE_MAX_PAYOUT_PER_CLAIM = 5 AXC`). This means:

- Oracle correctness depends on **validator/Lambda agreement** for conversion rate logic
- Core guarantees: no single claim can exceed 5 AXC (blast radius is bounded)
- Core does NOT guarantee: the conversion rate itself is fair or correct
- This is a **deliberate design tradeoff**: rates need operational flexibility (different platforms, changing values) that doesn't belong in an immutable Core ELF

This is NOT a hidden vulnerability. It is a disclosed trust boundary:
- **Core controls:** maximum payout, balance math, sender==receiver, k=5 minimum
- **Lambda controls:** conversion rate computation, platform whitelisting
- **Operator controls:** rate adjustment via TOML config

For public messaging: Oracle distribution is "Core-capped, Lambda-computed" — not "fully trustless."

---

## 7. Reserve Lifecycle

| Parameter | Value |
|---|---|
| Total reserve | 88,000,000 AXC |
| Daily emission | 24,109 AXC |
| Target drain time | ~10 years (3,650 days) |
| Required active contributors | ~5,000 daily for 10-year drain |
| Exhaustion behavior | Oracle stops permanently. No inflation. |

---

## 8. Platform Pool Distribution

| Platform | Weight | Daily Pool (AXC) |
|---|---|---|
| Folding@Home | 10% | 2,410 |
| Einstein@Home | 10% | 2,410 |
| Rosetta@Home | 10% | 2,410 |
| LHC@Home | 9% | 2,169 |
| Milkyway@Home | 9% | 2,169 |
| Universe@Home | 9% | 2,169 |
| World Community Grid | 7% | 1,687 |
| Zooniverse | 9% | 2,169 |
| iNaturalist | 9% | 2,169 |
| OpenStreetMap | 10% | 2,410 |
| Wikipedia | 8% | 1,928 |
| **Total** | **100%** | **24,100** |

---

## 9. Validator Responsibilities

### 9.1 Witnessing (Day 1)

0. Ensure own VBC was issued within the last 24 hours. Renew via CL8 if older. Reference: YPX-012 §2.5, ORACLE_VBC_RENEWAL_TICKS = 17_280 ticks.
   Stake wallet must have zero unresolved FACT scars. A scarred wallet disqualifies oracle witnessing until healed or burned (YPX-001 §1.5).
1. Extract oracle_claim from TX metadata
2. Query platform API independently — verify credits match
3. Verify Living Signature in username
4. Verify own stake >= 1M AXC (NablaStakeProof)
5. Witness via standard CL2/CL3
6. Propagate oracle_claim to cheque

### 9.2 Redeeming (Day 3)

1. Verify cheque bundle (k=5, standard CL5)
2. Core checks maturity, consistency, payout
3. Re-query platform API for credit verification
4. Credit AXC to contributor's wallet

---

## 10. Test Coverage

| Category | Count | What |
|---|---|---|
| Whitelist | 4 | Weights sum to 100, lookup valid/invalid, 11 entries |
| Living Signature | 3 | Format, verify pass, verify fail |
| Binding | 3 | Create/lookup, immutability, address match |
| Daily Pool | 4 | Allocation, deduct, cap, reset |
| Reserve | 3 | Initial, distribute, exhaustion |
| Credit Delta | 3 | Basic, floor, zero rate |
| Business Logic | 12 | Valid claims, duplicate, wrong binding, pool/reserve exhaustion |
| TX Validation | 4 | sender==receiver, whitelisted, living sig, constants |
| Proof Gate | 3 | Empty proof, claim blocked, invalid proof |
| **Total** | **40** | All real crypto, no mocks |

---

## 11. Open Research: Conversion Rate Calibration

The conversion rates in Section 6.2 are initial estimates. Before launch, research is needed on:

1. **Real-world credit generation rates** — How many F@H points does an average GPU generate per day? How many Zooniverse classifications does an average user do per hour?

2. **Cross-platform equivalence** — What is "equal effort" across compute, classification, and mapping? Is 1 hour of GPU folding equivalent to 100 Zooniverse classifications?

3. **Existing crypto models** — How do projects like Banano (F@H), Gridcoin (BOINC), and Curecoin (F@H) convert points to tokens? What rates do they use?

4. **Abuse potential per platform** — Which platforms are easiest to game? Compute platforms are harder (real CPU/GPU needed), classification platforms may be easier (click-farming).

These questions are documented for pre-launch research. The code supports any conversion rate — it's just `credit_delta / rate`. The rates are hardcoded constants that require a Yellow Paper upgrade to change. Future Console governance could enable rate adjustments.

---

## 12. Relationship to Other YPX Specifications

| YPX | Relationship |
|---|---|
| YPX-001 (FACT) | Oracle payouts produce FACT links (claim chain) |
| YPX-007 (Receiver Security) | Oracle addresses use k=5 tier |
| YPX-008 (VSP) | Validators discoverable for oracle witnessing |
| YPX-009 (Silicon Pulse) | Oracle validators audited like all validators |
| YPX-010 (Ark CI) | Oracle earnings reflected in Confidence Index |
| YPX-011 (Genesis) | Oracle reserve defined in Genesis FACT #0 sub-pools |

---

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
