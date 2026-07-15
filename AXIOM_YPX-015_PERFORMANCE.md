# YPX-015: Performance Engineering

**Version:** 0.1  
**Date:** 2026-04-08  
**Status:** Draft  
**Source:** Soak test v2 findings (v2.11.14-beta4)

---

## 1. Purpose

This document tracks performance-related findings, design decisions, and improvements identified through sustained load testing. Unlike functional specs (correctness), this document addresses **throughput, latency, and resource efficiency** under production-like conditions.

Findings are added as they are discovered. Each finding includes root cause analysis, proposed solution, and implementation status.

---

## 2. Findings

### 2.1 ANTIE Backpressure — Witness Queue Overload

**Discovered:** 2026-04-08 (Soak test v2, 10 wallets, 3 parallel)  
**Severity:** Medium  
**Status:** Design proposed, not implemented

**Symptom:** Witness requests time out after 60s. The validator is alive and healthy, but ANTIE's processing queue has accumulated multiple requests. Each witness involves Core DMAP proof computation (~2-7s typical, up to 180s in edge cases). With N queued requests, the last request waits N × avg_time before processing begins.

**Root cause:** ANTIE processes Maildir messages serially. There is no admission control — all incoming witness requests are accepted regardless of current queue depth. The client has no way to know a validator is overloaded until the 60s timeout expires.

**Impact:** Client wastes 60s on a timeout, then must select a different validator and retry. In a soak test with 3 concurrent subprocesses and 10 validators, random clustering causes queue depths of 3-4 on some validators, pushing total response time past 60s.

**Proposed design:**

```
┌─────────┐         ┌─────────┐         ┌──────┐
│  Client  │ ──req──▶│  ANTIE  │ ──exec──▶│ Lambda│
│         │ ◀─503───│         │ ◀─stats──│      │
│  retry  │         │ gate()  │         │ avg_ms│
│  other  │         │         │         │      │
│validator│         └─────────┘         └──────┘
└─────────┘
```

**Lambda responsibility:**
- Track rolling average witness processing time (`avg_witness_ms`)
- Expose via admin stats endpoint (already exists: `/stats`)
- No admission control logic — Lambda does not know queue depth

**ANTIE responsibility:**
- Read `avg_witness_ms` from Lambda (periodic poll or shared metric)
- Know current inbox queue depth (count of `new/` messages)
- Compute `estimated_wait = queue_depth × avg_witness_ms`
- If `estimated_wait > BUSY_THRESHOLD_MS` (configurable, e.g. 30000ms):
  - Respond immediately with rejection: `{"error": "E_VALIDATOR_BUSY", "estimated_wait_ms": N}`
  - Do NOT queue the request
- Otherwise: accept and process normally

**Client responsibility:**
- On `E_VALIDATOR_BUSY`: immediately select next validator from pool, retry
- Do NOT count busy rejection as a failure — it's a normal load-balancing signal
- Validator hints (YP §27) can include load information for smarter selection

**Why this separation:**
- Lambda knows processing time (it runs Core)
- ANTIE knows queue depth (it reads Maildir)
- Neither alone has the full picture — ANTIE combines both to make the gate decision
- Client gets instant feedback instead of 60s timeout

**Configuration:**
```toml
# antie.toml
[performance]
busy_threshold_ms = 15000    # reject if estimated wait > 15s
avg_window_size = 20         # rolling average over last 20 witnesses
poll_interval_ms = 2000      # how often ANTIE reads Lambda stats
```

---

### 2.2 DMAP Proof Latency — Root Cause Found (FIXED)

**Discovered:** 2026-04-08 (Soak test v2)  
**Severity:** High  
**Status:** FIXED (v2.11.14-beta5)

**Symptom:** Individual DMAP proof computations occasionally take 120-180s instead of the typical 2-7s.

**Root cause:** Lambda ran DMAP proof on requests that were **already doomed to fail** due to state_id mismatch. The validator had a stale state_id (e.g., from a previous TX that only partially completed). Lambda detected the mismatch and logged "REPLAY DETECTED" but proceeded to run DMAP anyway — wasting minutes before Core rejected with E_SABR_HASH_MISMATCH.

**Fix:** Lambda early-rejects state_id mismatches BEFORE DMAP computation — but ONLY when there are no S-ABR overlap signatures. If overlap signatures are present, Core must verify the S-ABR chain (the validator may be a fresh S-ABR validator with legitimately different stored state). The initial implementation incorrectly rejected ALL mismatches, which broke S-ABR for fresh validators.

**Critical lesson:** Lambda MUST NOT bypass Core's authority. Cheap pre-checks are OK only when they cannot produce false rejections. State_id mismatch + overlap sigs = Core's decision, not Lambda's.

### 2.2.1 PMC Retry for k=3 Collection (FIXED)

**Discovered:** 2026-04-09 (Soak test v2)  
**Status:** FIXED (v2.11.14-beta5)

**Symptom:** When the 3rd validator in serial S-ABR fails (timeout, error), the TX fails with only 2/3 signatures. The 2 validators that committed have diverged state. The wallet becomes permanently stuck.

**Root cause:** PMC gave up after 3 selected validators. No retry on failure.

**Fix:** PMC now retries with a backup validator when any validator in the serial chain fails. The accumulated signatures from prior validators are passed to the backup. Client collects signatures like cheques — keeps trying until k=3 is complete.

**Protocol insight (operator):** Validators witness honestly and record what happened. The client tracks state and only updates after k=3 confirmation. The client is responsible for collecting enough signatures — if the 3rd fails, try a 4th.

---

### 2.3 PMC Response Consumption Bug (FIXED)

**Discovered:** 2026-04-08 (Soak test v2)  
**Severity:** High  
**Status:** FIXED (v2.11.14-beta4)

**Symptom:** Witness requests time out even though the response was delivered to the client's inbox within seconds. Affected both `send_request()` (serial S-ABR) and `send_parallel()` (parallel redeem).

**Root cause:** `pmc.py` `send_request()` called `read_and_consume()` on every non-cheque message in the inbox, moving it from `new/` to `cur/`, THEN checked if the `request_id` matched. If the message belonged to a different request (e.g., validator-2's response arriving while polling for validator-1), it was consumed and lost. The rightful consumer would then time out.

**Fix:** Added `if request_id not in content: continue` before `read_and_consume()` in both `send_request()` and `send_parallel()`. Messages are only consumed when their `request_id` matches the current request.

**Lesson:** Any Maildir-based polling loop MUST check message identity before consuming. Consume-then-check is a data loss pattern.

---

### 2.4 Nabla State Conflict on Wallet Re-use (FIXED)

**Discovered:** 2026-04-08 (Soak test v2)  
**Severity:** High  
**Status:** FIXED (v2.11.14-beta4)

**Symptom:** All Nabla registrations fail with "wallet is BANNED" after the first test run. Wallets that were funded and used in a previous run can never register with Nabla again.

**Root cause:** `init_genesis_dev` resets the wallet's state on validators (new state_id), but Nabla retains the old state from the previous run. When the client registers after a new TX, Nabla sees `old_state != existing.current_state` → interprets as a fork → permanent ban.

**Fix:** Use fresh wallet names per test run (run_id in name: `s2r{run_id}_{i:03d}`). Nabla has never seen these wallets, so no state conflict. Old wallet entries remain in Nabla (dead weight) but serve as incidental stress testing for WAL compaction and SMT growth.

**Lesson:** Nabla's ban detection is correct — re-using wallet identities across genesis resets IS indistinguishable from a fork. The protocol is working as designed. Test infrastructure must not reuse wallet identities.

---

### 2.5 Incomplete Cheque Redeem (FIXED)

**Discovered:** 2026-04-08 (Soak test v2)  
**Severity:** Medium  
**Status:** FIXED (v2.11.14-beta4)

**Symptom:** Wallet attempts to redeem with 1-2 cheques (instead of k=3), causing partial state advances on accepting validators. The wallet becomes stuck — some validators have the new state, others have the old.

**Root cause:** Cheques arrive asynchronously via FATMAMA. The subprocess consumed all cheques from inbox, grouped by txid, and attempted redeem even with incomplete groups (<3). The 1-2 cheque redeem was accepted by some validators but rejected by others (need k=3).

**Fix:** Peek at cheques without consuming. Group by txid. Only consume and redeem complete groups (k=3). Incomplete groups stay in `new/` for the next fork.

**Lesson:** Never attempt redeem with fewer than k=3 cheques. The async delivery model means not all cheques arrive simultaneously — wait for the full set.

---

### 2.6 Parallel Redeem Causes FACT Scars (FIXED — YP ERRATA)

**Discovered:** 2026-04-08 (Soak test v2)  
**Severity:** High  
**Status:** FIXED (v2.11.14-beta4). Yellow Paper corrected.

**Symptom:** Wallets become scarred after a redeem where 2/3 validators responded and 1 timed out. The 2 validators that responded independently committed the state change and created FACT links with no Nabla confirmation (scars). Subsequent TXs fail on those 2 validators with "FACT scar detected" while other validators reject with E_SABR_HASH_MISMATCH (state divergence).

**Root cause:** PMC sent redeem requests to all 3 validators in parallel (`send_parallel`). Each validator independently processed and committed the redeem. When one timed out, 2 validators had new state + unconfirmed FACT link, 1 had old state. The client had no valid k=3 receipt and could not register with Nabla.

The Yellow Paper (§17.9.4) incorrectly stated: "Redeem MAY be sent in parallel or sequentially." This was wrong — redeem is a state transition that changes receiver's state_id. It MUST follow S-ABR serial witness accumulation, identical to the witness (send) path. The k=3 validator creates the FACT link after seeing the first 2 signatures, ensuring atomic k=3 consensus before any state change.

**Fix:**
1. Changed all redeem calls from `send_parallel()` to `send_witness_to_selected()` (serial S-ABR) in soak_test_v2.py, soak_test.py, and chaos_test.py.
2. Yellow Paper §17.9.4 corrected: "Redeem MUST NOT be sent in parallel" with errata note.

**Lesson:** Any operation that changes wallet state (witness, redeem, burn) MUST use serial S-ABR. Parallel sends are only safe for read-only operations (query, status) and genesis initialization. This was not caught earlier because the chaos test runs one TX at a time (no timeouts under zero load), and v1 soak test's shared inbox masked the scars with other failures. The real-world FATMAMA SMTP path in soak test v2 introduced realistic latency that exposed the race.

---

## 3. Soak Test v2 Performance Baseline

**Configuration:** 10 wallets, 3 parallel, fork rate 1/s, 10 validators + 10 Nabla  
**Environment:** Single machine, `axiom-env.py` full stack

| Metric | Value | Notes |
|--------|-------|-------|
| Witness round-trip (typical) | 7-10s | Per validator, serial S-ABR |
| Witness round-trip (spike) | 60-180s | DMAP latency spike (§2.2) |
| FATMAMA delivery | <1s | SMTP receive → Maildir write |
| Genesis funding | 0.1-0.5s | Per validator |
| Nabla registration | 0.5-2s | TCP + CBOR + SMT update |
| k=3 witness (total) | 21-30s | 3 serial validators |
| Cheque delivery | 2-10s | ANTIE → SMTP → FATMAMA → inbox |
| Redeem (parallel k=3) | 10-15s | 3 parallel validators |
| Success rate (v2.11.14-beta5) | 100% | All fixes applied: serial redeem, early reject, PMC retry |

---

## 4. Future Performance Work

Items to investigate and document as findings emerge:

- [ ] §2.1 ANTIE backpressure implementation
- [ ] §2.2 DMAP latency spike root cause
- [ ] §2.3 Per-wallet witness rate limit (ANTIE-side DDoS defense)
- [ ] Nabla gossip convergence time under load
- [ ] SQLite WAL checkpoint impact on witness latency
- [ ] Concurrent Nabla registration throughput
- [ ] FACT chain compression performance with deep chains
- [ ] Multi-host network latency impact on S-ABR serial round-trip

### §2.3 Per-Wallet Witness Rate Limit

**Status:** PLANNED  
**Layer:** ANTIE (transport)  
**Discovery:** Soak test v2 with 5 wallets / 5 parallel demonstrated that concurrent
witness requests for the same wallet create cascading FACT scars and state divergence.
An attacker can reproduce this deliberately at low cost.

**Attack shape:** Create N wallets, send concurrent witness requests from each to
different validator subsets. Validators partially commit conflicting state, producing
FACT scars that require burn or CLARA recovery. The attacker's own wallets are
damaged, but validator CPU is wasted on DMAP proof verification for ultimately-rejected
TXs.

**Defense:** ANTIE tracks `last_witness_request_ts` per `sender_wallet_id`. Requests
arriving within the cooldown window are rejected with `E_WALLET_RATE_LIMITED` before
reaching Lambda or Core. This is the cheapest possible defense — a hash lookup on a
field ANTIE already reads, with zero impact on the consensus boundary.

**Why ANTIE, not Core:** Core is a pure state machine that validates inputs handed to
it. Rate limiting is a transport/routing concern. Placing it in ANTIE keeps the defense
layer-correct (ANTIE filters, Lambda verifies, Core computes) and allows operational
tuning without ELF rebuilds.

**Parameters (implemented):**
- `wallet_witness_cooldown_ms`: minimum ms between witness requests for the same
  wallet_id. Default 2000 ms (0.5 req/sec/wallet). Configurable per-validator.
  Production recommendation: 2000-5000ms depending on expected load.
- Lookup: in-memory HashMap<wallet_id, Instant>. Evict entries older than 2×cooldown.
- Exempt: overlapped (S-ABR) requests from prev-TX validators (they carry
  `overlapped_signatures` — legitimate protocol traffic).

---

## Appendix A: Soak Test v2 Usage

```bash
# Start environment
python3 scripts/axiom-env.py start

# Run soak test (72h, 10 wallets)
python3 tests/soak_test_v2.py --base-dir ~/axiom --wallets 10 --duration 72h

# Short validation run
python3 tests/soak_test_v2.py --base-dir ~/axiom --wallets 10 --duration 1h

# Dry run (prepare wallets only)
python3 tests/soak_test_v2.py --base-dir ~/axiom --wallets 10 --dry-run
```

**Key flags:**
- `--wallets N`: Number of wallets (default 50). Use 10+ to avoid concurrent fork collisions.
- `--max-parallel M`: Concurrent subprocesses (default 10). 3 is good for single-machine testing.
- `--fork-rate R`: New subprocesses per second (default 2).
- `--duration D`: Total run time (default 72h). Supports h/m/s suffixes.

**Fresh wallets per run:** Each run creates wallets with a unique run_id prefix (`s2r{id}_NNN`). This prevents Nabla bans from state_id conflicts with previous runs. Old wallet routes are cleaned from FATMAMA automatically.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
