# YPX-011: Genesis Integrity & Supply Provenance

**Version:** 0.1
**Status:** Proposed
**Author:** AXIOM Origin
**Date:** 2026-03-18
**Depends on:** Yellow Paper v2.11.5, YPX-001 (FACT chain), YPX-002 (NBC/VBC)

---

## 0. Summary

This extension specifies the genesis mechanism for AXIOM's total supply, the proof-of-fair-launch anchor, and the permanent storage of FACT #0 in Nabla. Together these provide cryptographically verifiable proof that:

- The total supply is exactly 100,000,000 AXC
- No AXC was created before the publicly announced genesis moment
- Every AXC in existence is mathematically traceable to FACT #0

---

## 1. Genesis Reserved Pool

### 1.1 Hardcoded Constant

Nabla contains a hardcoded protocol constant:

```rust
pub const GENESIS_POOL_TOTAL: u64 = 100_000_000;
```

This value is set once, at compile time, and cannot be altered by any operator, configuration, or runtime input. It is the absolute supply ceiling.

### 1.2 Sub-Pool Structure

The Genesis Reserved Pool is partitioned into sub-pools at genesis. All sub-pools are declared in FACT #0 and sum exactly to `GENESIS_POOL_TOTAL`.

| Sub-Pool ID | Name | Intended Purpose | Authorization |
|---|---|---|---|
| `GENESIS` | Genesis Validators | 10 genesis validators x 1,000,000 AXC | Protocol -- validator position 1-10 |
| `BOOTSTRAP` | Bootstrap Validators | Sliding scale for early validators | Protocol -- join sequence |
| `FAH` | Fold@Home Rewards | F@h contribution rewards | Protocol -- F@h engine |
| `AIRDROP` | Airdrop | 1 AXC per new wallet | Protocol -- wallet registration |
| `DEVELOPER` | Developer Pool | GitHub contributors | Operator-authorized |

Sub-pool sizes are declared in FACT #0 and are immutable after genesis signing.

### 1.3 Supply Accounting

At any point in time:

```
circulating_supply = GENESIS_POOL_TOTAL - sum(all sub-pool balances)
```

Nabla enforces: no distribution may reduce any sub-pool below zero. Any such request is rejected before Core signing is requested.

---

## 2. Proof-of-Fair-Launch Anchor

### 2.1 The Problem

Core is stateless. TARDIS time is self-referential -- it proves ordering relative to its own genesis but cannot prove when genesis occurred relative to the external world. An operator could theoretically run Nabla privately, create AXC, then restart with a clean genesis.

### 2.2 Solution: 7-Headline Anchor

On genesis day, the operator collects the top headline from 7 publicly funded, government-backed news organisations spanning 7 countries and 5 continents. These headlines are:

1. Publicly announced **before** TARDIS starts
2. Embedded in FACT #0, signed by Core
3. Permanently stored in Nabla (never compressed)

Because the headlines cannot be known before publication, and because Core signs FACT #0 (requiring Core's private key), no pre-genesis AXC creation is possible.

### 2.3 Canonical Headline Sources

| # | Country | Organisation | URL |
|---|---|---|---|
| 1 | USA | Associated Press (AP) | https://apnews.com |
| 2 | Japan | NHK World | https://www3.nhk.or.jp/nhkworld/en/news |
| 3 | UK | BBC News | https://www.bbc.com/news |
| 4 | Taiwan | Central News Agency (CNA) | https://www.cna.com.tw |
| 5 | Australia | ABC Australia | https://www.abc.net.au/news |
| 6 | Germany | Deutsche Welle | https://www.dw.com/en/top-stories |
| 7 | France | Le Monde | https://www.lemonde.fr |

All seven are publicly funded or state-backed organisations with permanent digital archives. No single geopolitical event can remove all seven simultaneously.

### 2.4 Headline Format

Each headline entry in FACT #0 must follow this exact format:

```
[ISO-8601 date] | [Organisation] | [Exact headline text as published]
```

---

## 3. FACT #0 -- Genesis Entry

### 3.1 Structure

FACT #0 is the root of the entire AXIOM supply. It is not a wallet-to-wallet transaction. It is a protocol-level genesis declaration.

```rust
pub struct GenesisFact {
    pub fact_id: u64,                    // always 0
    pub fact_type: FactType,             // FactType::Genesis
    pub pool_total: u64,                 // 100_000_000
    pub sub_pools: Vec<SubPoolDeclaration>,
    pub headlines: Vec<HeadlineAnchor>,  // exactly 7 entries
    pub tick: u64,                       // TARDIS genesis tick #1
    pub core_signature: [u8; 64],        // Ed25519 signature by Core
}

pub struct HeadlineAnchor {
    pub date: String,        // ISO-8601
    pub organisation: String,
    pub headline: String,
}

pub struct SubPoolDeclaration {
    pub pool_id: SubPoolId,
    pub initial_balance: u64,
}
```

### 3.2 Core Signing

Core signs FACT #0 over the canonical CBOR serialisation of all fields excluding `core_signature`. This is a one-time operation. Core must refuse any second genesis signing request -- this is a protocol invariant, not a configuration option.

```
signature_input = CBOR(fact_id || pool_total || sub_pools || headlines || tick)
core_signature  = Ed25519_Sign(MASTER_PRIVATE_KEY, signature_input)
```

The signing key is the private half of `WALLET_IDENTITY_KEY` -- the same key produced by the genesis ceremony (G1). This key signs wallet address checksums AND FACT #0. It is the root authority for the entire protocol.

### 3.3 Verification

Any party can verify FACT #0 by:

1. Fetching FACT #0 from Nabla public endpoint (`GET /genesis`)
2. Reconstructing `signature_input` from the fields
3. Verifying `core_signature` against `WALLET_IDENTITY_KEY` (protocol-wide constant)
4. Summing `sub_pools` -- must equal `pool_total`
5. Looking up each headline at its canonical source URL

Step 5 is human-verifiable by anyone with an internet connection.

---

## 4. Permanent Storage of FACT #0

### 4.1 Rationale

Normal FACT chains in AXIOM compress after depth 5 (YPX-001 section 1.4). Without special treatment, FACT #0 would eventually be compressed away, severing the direct chain link from any wallet back to the genesis headlines.

FACT #0 is stored permanently and in full in Nabla, while its hash propagates forward through all compression events.

### 4.2 Permanent Storage Rule

FACT #0 is stored permanently in a dedicated Nabla table:

```sql
CREATE TABLE genesis_fact (
    fact_id     INTEGER PRIMARY KEY CHECK (fact_id = 0),
    payload     BLOB NOT NULL,   -- canonical CBOR of GenesisFact
    tick        INTEGER NOT NULL,
    signature   BLOB NOT NULL,   -- Core signature (64 bytes)
    stored_at   INTEGER NOT NULL -- unix timestamp of Nabla write
);
```

This table:
- Has exactly one row, forever
- Is append-only (no UPDATE, no DELETE)
- Is checked at Nabla startup -- absence is a fatal error

### 4.3 Genesis Hash Propagation Through Compression

When a FACT chain compresses at depth 5, the compressed root carries the `genesis_fact_hash`:

```rust
pub struct CompressedFactRoot {
    pub compressed_at_depth: u8,
    pub root_balance: u64,
    pub root_tick: u64,
    pub genesis_fact_hash: [u8; 32],  // BLAKE3(CBOR(GenesisFact))
    pub core_signature: [u8; 64],
}
```

`genesis_fact_hash` must be preserved through every subsequent compression. It is never dropped.

### 4.4 Verification Path

Any wallet can prove its connection to genesis:

```
wallet FACT chain
  -> compressed root
       -> genesis_fact_hash  <-- must match BLAKE3(Nabla genesis_fact record)
                                   -> Nabla genesis_fact record
                                         -> headlines (human-verifiable)
                                         -> core_signature (cryptographically verifiable)
```

### 4.5 Public Query Endpoint

Nabla exposes a public endpoint requiring no authentication:

```
GET /genesis
```

Returns FACT #0 payload, headlines, sub-pool balances, circulating supply (live), and genesis_fact_hash. `circulating_supply` and `pool_balances` are computed at query time.

---

## 5. Genesis Configuration File

Headlines are **never edited directly in source code**. They are declared in `genesis.toml`, read at compile time by `build.rs`, and baked into the binary.

### 5.1 Compile-Time Validation

`build.rs` enforces before the binary is produced:
- All 7 headline fields are non-empty
- All 7 dates match the same ISO-8601 date
- Sub-pools sum exactly to `genesis_pool_total`
- `genesis_pool_total` = 100,000,000

**Binary will not compile if any of these fail.**

---

## 6. Genesis Boot Sequence

```
Step 1: Collect 7 headlines from canonical sources
Step 2: Announce publicly BEFORE compiling (establishes public witness)
Step 3: Fill genesis.toml, compile binary (build.rs validates)
Step 4: Release binary publicly (GitHub, reproducible build)
Step 5: Start Core (loads WALLET_IDENTITY_KEY)
Step 6: Start TARDIS (genesis tick #1)
Step 7: Nabla initialises (Core signs FACT #0, permanent storage)
Step 8: Genesis distributions (10 validators x 1M AXC)
Step 9: Network opens (bootstrap, airdrop, F@h)
```

---

## 7. Distribution Authorization

| Sub-Pool | Authorized By | Mechanism |
|---|---|---|
| `GENESIS` | Protocol | Validator position 1-10, automatic |
| `BOOTSTRAP` | Protocol | Join sequence, sliding scale, automatic |
| `FAH` | Protocol | F@h engine, automatic per contribution |
| `AIRDROP` | Protocol | Wallet registration, 1 AXC automatic |
| `DEVELOPER` | Operator | Manual, operator private key signature |

---

## 8. Bootstrap Sliding Scale

| Validator Position | AXC per Validator |
|---|---|
| 1-10 | 1,000,000 (Genesis sub-pool) |
| 11-20 | 10,000 |
| 21-X | TBD (decreasing until BOOTSTRAP exhausted) |

After BOOTSTRAP pool exhaustion: standard AIRDROP allocation (1 AXC) only.

---

## 9. Security -- Residual Gap (Honest Disclosure)

The only theoretical attack: operator ran private TARDIS+Nabla+Core before genesis day, created AXC with a different keypair, then restarted publicly. This fails because those AXC would carry a different Core signature -- rejected by protocol as invalid. `WALLET_IDENTITY_KEY` is fixed and public. Any AXC not signed by that key is worthless.

---

## 10. Implementation Dependencies

| Dependency | Status |
|---|---|
| G1: Genesis ceremony (WALLET_IDENTITY_KEY) | Pending -- blocks all genesis implementation |
| YPX-001: FACT chain compression | Implemented -- genesis_fact_hash field needed |
| YPX-002: NBC/VBC validator identity | Implemented -- k=3 witness for positions 11+ |

### Protocol Rules (Non-Negotiable)

- FACT #0 is never compressed
- `genesis_fact_hash` survives every compression event
- Sub-pool balances never go below zero
- Core refuses second genesis signing -- always, no override
- `GENESIS_POOL_TOTAL` = 100,000,000 -- immutable

---

## 11. Document Information

| Field | Value |
|-------|-------|
| Specification | YPX-011 -- Genesis Integrity & Supply Provenance |
| White Paper refs | §2.3 (AXC supply), §2.10 (genesis distribution) |
| YPX deps | YPX-001 (FACT chain), YPX-002 (NBC/VBC) |
| Key constraint | Cryptographic proof + human-verifiable 7-headline anchor |
| Blocked by | G1 (genesis ceremony) |

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
