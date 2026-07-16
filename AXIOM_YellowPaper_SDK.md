# AXIOM Client SDK — Yellow Paper

**Status:** Draft — v2.14 (setup() mandate normalised)
**Date:** 2026-05-13
**Scope:** Client-side library specification, NOT a protocol extension.
The protocol itself is specified in `AXIOM_YellowPaper.md`. This
document specifies how a client should implement the client side of that
protocol — what it must do, what it must expose, and what it must not
assume or touch. It is intentionally named `AXIOM_YellowPaper_SDK.md` to
be the peer of `AXIOM_YellowPaper.md`, not a `YPX-*` extension.

**Why not a YPX number:** YPX documents are extensions to the Yellow
Paper — they specify new protocol mechanisms or add normative rules
that validators enforce. The SDK is the opposite: it implements rules
that already exist in the Yellow Paper, in a form reusable across
clients. No validator ever reads this document. It belongs alongside
the Yellow Paper as a separate "client-side companion spec," not
underneath it as an extension.

**Related protocol references the SDK implements:**
- YP §17.9.4.0 — receiver dedup contract
- YPX-002 §4.6 — receiver Nabla verification
- YPX-007 — wallet identity binding (pk_bind suffix in wallet_id)
- YPX-016 — witness response cache (same-validator retry pattern)
- YPX-018 — CLARA wallet recovery (heal-forward)
- `AXIOM_DESIGN_SelfTransactions.md` — HAL / HEAL / CLAIM / BURN are self-transactions
  (self-send + redeem). **The SDK exposes atomic `send`/`redeem` and never
  auto-completes a multi-step op** (extends CLAUDE.md §14); the app/user drives the
  redeem leg. `claim_genesis_full` is the request leg only (returns
  `pending_cheque_id`, no auto-redeem); BURN is the lone send-only (fund-destroying) op.

---

## 1. Why

Every AXIOM client implementation — `scripts/pmc.py`, `webclient/static/index.html`,
the soak test harness, any future mobile wallet or merchant integration — has
independently re-implemented the same handful of rules:

- How to pick k=3 validators (overlap-first ordering for S-ABR)
- How to retry witness failures (same-validator first for YPX-016, then backup)
- How to dedup cheques on the receiver side (YP §17.9.4.0)
- How to build and sign a redeem bundle
- How to detect drift and trigger CLARA heal
- How to register with Nabla post-send
- How to persist wallet state atomically

Each re-implementation introduced subtle bugs that bit us during multi-day soak
testing. Tonight alone we found dedup issues in 3 clients, a retry-ordering
bug in 1, and a persistence race in another. The protocol is sound; the
clients keep rediscovering the same contracts the hard way.

An SDK consolidates all this logic into one opinionated library. New clients
get a working wallet in a day by calling 10 public functions. The rules live
in one place; the protocol YP defines them, the SDK enforces them, clients
trust the SDK.

## 2. Design principle — filesystem IO, not network IO

**The SDK does not touch the network.** It reads and writes files in a
well-defined directory layout. The front-end (email client, webclient, mobile
app, CLI tool, test harness) is responsible for moving those files to and
from the outside world.

This is the same separation Unix `maildir` uses between the MTA (delivery),
the store (filesystem), and the MUA (reader). The SDK is the store + the MUA
library. The front-end is the MTA (for outgoing) and the fetcher (for
incoming).

**Why this is the right shape:**

- **Zero network dependencies.** No IMAP, SMTP, TLS, HTTP, or socket stacks
  in the SDK crate. Smaller attack surface, faster builds, no flaky tests.
- **Carrier-agnostic.** The same SDK works for email (current), HTTP
  webhooks (future), mobile push notifications, manual paste, or anything
  else a developer invents. The front-end chooses the carrier; the SDK
  doesn't care.
- **Crash-safe by construction.** Filesystem operations are atomic (rename,
  fsync, flock). Losing power mid-write never leaves the store corrupt.
  In-memory state is minimized — everything that matters is on disk.
- **Concurrency via flock.** Multiple processes can operate on the same
  wallet directory (e.g., a background polling daemon + a user-facing CLI)
  as long as they respect the SDK's lock discipline.
- **Testability.** Drop a test cheque into the inbox directory, call
  `wallet.recv()`, assert the outcome. No mock servers, no fake validators.
- **Already proven.** The soak test harness uses this exact model with
  FATMAMA + maildir directories. It works.

**What the front-end is responsible for:**

- Incoming: fetch the raw cheque payload from wherever it came from
  (IMAP, HTTP, mobile push, clipboard), write it as a file into the
  wallet's inbox directory.
- Outgoing: after the SDK writes a cheque payload to the outbox, ship it
  to the recipient via whatever carrier the user prefers.
- Storage encryption and access control: whatever encryption, biometric
  gating, keystore integration, or password UX the platform supports.
  The SDK expects a plain directory it can read/write to; the front-end
  is responsible for ensuring that directory is unlocked and writable
  before calling `Wallet::open`. See §4.2.

**What the SDK is responsible for:**

- Reading inbox files, parsing cheque payloads, deduping, grouping by txid
- Running the full send flow (validator selection, S-ABR, retry, register)
- Running the full redeem flow (dedup, §4.6 pre-check, bundle, CLARA heal)
- Running CLARA heal automatically on drift detection
- Writing outbound cheque payloads to the outbox directory
- Persisting wallet state atomically
- Verifying cryptographic signatures and fact chains

### 2.1 Cross-platform architecture (NORMATIVE)

The SDK targets six platforms: **Linux, macOS, Windows, WASM (browser),
iOS, and Android.**

> **macOS reference apps.** Two example apps in `apps/macos/`
> demonstrate the §2.1 architecture concretely: `AxiomWallet.app`
> consumes the SDK FFI, opens TCP to Nabla, and writes/reads the
> maildir; `AxiomKiddo.app` is the transport daemon that ships
> outbox bytes via SMTP and drops POP3 inbound into the wallet's
> inbox. They are reference examples for SDK consumers — not
> shipping products. See
> `docs/AXIOM_DESIGN_MacOSReferenceApps.md` for the architecture
> rationale, the migration plan that built them, and the
> filesystem-layout-as-IPC contract between them.

The SDK has two distinct IO channels:

1. **Validator communication** — via maildir. The SDK writes UMP
   payloads to a shared maildir `outbox/` and reads responses from
   `inbox/`. The developer provides the transport layer between the
   maildir and the validators. Email via sendmail/ANTIE is the default
   on Linux; on other platforms the developer may use IMAP, a custom
   HTTP carrier, or anything else. The SDK does not care how payloads
   travel — it reads and writes files in a maildir the developer
   configures.

2. **Nabla communication** — direct TCP CBOR. The SDK connects to
   Nabla nodes directly via TCP (wire format: 4-byte BE length + CBOR
   payload) and HTTP (supplemental registration, CLARA). Nabla is
   citizen infrastructure, not a carrier — routing it through maildir
   would be unnecessary indirection. The SDK manages Nabla connections,
   discovery, sticky routing, and peer hints internally.

```
┌──────────────────────────────────────────────────────────────┐
│                     axiom-sdk-core                           │
│              (no_std compatible, pure logic, ZERO IO)        │
│                                                              │
│  Transaction building    ·  Ed25519 signing                  │
│  S-ABR validator select  ·  Witness response parsing         │
│  Cheque dedup + grouping ·  FACT chain build/merge/scan      │
│  Error classification    ·  State machine transitions        │
│  Wallet ID generation    ·  Witness commitment computation   │
│  §4.6 verification logic ·  CLARA attestation logic          │
│  Redeem TX construction  ·  Burn TX construction             │
│  History recording       ·  Protocol constants               │
└────────────────────────────┬─────────────────────────────────┘
                             │
              Depends on 3 traits (ports):
                             │
         ┌───────────────────┼──────────────────────┐
         ▼                   ▼                    ▼
   ┌───────────┐    ┌────────────────┐    ┌────────────┐
   │  Storage   │    │ NablaTransport │    │  Platform  │
   │   trait    │    │     trait      │    │   trait    │
   └─────┬─────┘    └───────┬────────┘    └─────┬──────┘
         │                  │                   │
    Platform-specific implementations (adapters):
         │                  │                   │
   ┌─────┴──────────────────┴───────────────────┴──────┐
   │  Linux / macOS / Windows (desktop default)        │
   │  Storage: std::fs (atomic write + rename)          │
   │  Nabla: TCP CBOR (std::net::TcpStream)             │
   │  Platform: flock / LockFileEx, getrandom, time     │
   ├───────────────────────────────────────────────────┤
   │  WASM / Browser                                    │
   │  Storage: front-end provides (OPFS / IndexedDB)    │
   │  Nabla: front-end provides (fetch-based)           │
   │  Platform: crypto.getRandomValues, Date.now,       │
   │            no locking (single-threaded)             │
   ├───────────────────────────────────────────────────┤
   │  iOS / Android                                     │
   │  Storage: sandboxed app files (std::fs)            │
   │  Nabla: TCP CBOR (same as desktop)                 │
   │  Platform: flock, getrandom, time                  │
   └───────────────────────────────────────────────────┘
```

#### 2.1.1 The traits

**Storage** — read and write wallet state, maildir files, cheques:

```rust
pub trait Storage {
    fn read(&self, path: &str) -> Result<Option<Vec<u8>>>;
    fn write_atomic(&self, path: &str, data: &[u8]) -> Result<()>;
    fn list_dir(&self, path: &str) -> Result<Vec<String>>;
    fn rename(&self, from: &str, to: &str) -> Result<()>;
    fn mkdir_p(&self, path: &str) -> Result<()>;
    fn remove(&self, path: &str) -> Result<()>;
}
```

Desktop and mobile use `std::fs`. WASM uses whatever the front-end
provides — OPFS, IndexedDB, or a custom in-memory store. The SDK
never calls `std::fs` directly.

**NablaTransport** — direct TCP CBOR to Nabla nodes:

```rust
pub trait NablaTransport {
    /// Send a CBOR message to a Nabla node and read the response.
    /// Wire format: [4-byte BE length][CBOR payload].
    fn send_recv(&self, address: &str, payload: &[u8]) -> Result<Vec<u8>>;

    /// HTTP request to a Nabla node (supplemental registration, CLARA).
    fn http_request(&self, address: &str, method: &str, path: &str, body: &[u8]) -> Result<Vec<u8>>;
}
```

Desktop and mobile use `std::net::TcpStream`. WASM provides a
fetch-based implementation. The SDK manages Nabla node discovery,
sticky routing, and peer hints internally — the developer never sees
Nabla directly.

**Platform** — OS-level services:

```rust
pub trait Platform {
    fn acquire_lock(&self, name: &str) -> Result<Box<dyn LockGuard>>;
    fn random_bytes(&self, buf: &mut [u8]);
    fn now_unix_secs(&self) -> u64;
}
```

Locking: `flock` on Unix, `LockFileEx` on Windows, no-op on WASM
(single-threaded). Random: `getrandom` on native,
`crypto.getRandomValues` on WASM. Time: `std::time` on native,
`Date.now()` on WASM.

#### 2.1.2 Platform compatibility matrix

| Capability | Linux | macOS | Windows | WASM | iOS | Android |
|---|---|---|---|---|---|---|
| axiom-sdk-core (pure logic) | Y | Y | Y | Y | Y | Y |
| Default Storage (std::fs) | Y | Y | Y | — | Y | Y |
| Default Nabla (TCP CBOR) | Y | Y | Y | — | Y | Y |
| Default Locking (flock) | Y | Y | Y* | — | Y | Y |
| WASM Storage (front-end) | — | — | — | Y | — | — |
| WASM Nabla (front-end) | — | — | — | Y | — | — |
| Custom Storage | Y | Y | Y | Y | Y | Y |
| Custom NablaTransport | Y | Y | Y | Y | Y | Y |

*Windows uses `LockFileEx`, abstracted behind the Platform trait.

#### 2.1.3 Why this separation is correct

1. **axiom-sdk-core never touches IO.** It compiles to any target Rust
   supports, including `wasm32-unknown-unknown` and `no_std` embedded.
   Every protocol rule lives here — exactly once.

2. **Platform differences are isolated to trait implementations.** Adding
   a new platform means writing Storage + NablaTransport + Platform
   impls, not touching protocol logic.

3. **Desktop developers don't see the traits.** The `axiom-sdk` crate
   re-exports everything with defaults wired in. `Wallet::create` just
   works. The traits are for WASM and custom deployments.

4. **Validator transport is the developer's problem.** The SDK reads
   and writes maildir. How payloads travel between the maildir and
   validators is the developer's choice — email (default), HTTP, push,
   or a custom carrier. The developer can build their own ANTIE.

## 3. Application Layout

The SDK operates on an **application directory** that contains shared
resources (maildir, validator/Nabla discovery) and per-wallet state.

```
{app_dir}/
├── axiom.conf                — application-level configuration (see §3.1)
│
├── maildir/                  — shared maildir for ALL validator communication
│   ├── inbox/                  developer's transport layer delivers here
│   │   ├── new/                — incoming payloads (SDK reads)
│   │   ├── cur/                — processed payloads (SDK moves here)
│   │   └── tmp/                — atomic delivery staging
│   └── outbox/                 SDK writes outgoing payloads here
│       ├── new/                — outgoing payloads (developer ships)
│       ├── cur/                — shipped payloads (developer moves here)
│       └── tmp/                — atomic write staging
│
├── validators.list           — seed validator list (user-editable, plain text)
├── nabla-nodes.list          — seed Nabla node list (user-editable, plain text)
├── validator-state.cbor      — SDK internal: health tracking, discovered hints
├── nabla-state.cbor          — SDK internal: health, sticky routing, NBC branches
│
└── wallets/
    ├── alice/
    │   ├── wallet.axiom         — wallet state (CBOR, AXWL magic + version)
    │   ├── wallet.axiom.lock    — flock writer coordination
    │   ├── cheques/            — cheque store (pending + redeemed)
    │   └── history.cbor        — TX history
    └── bob/
        ├── wallet.axiom
        ├── wallet.axiom.lock
        ├── cheques/
        └── history.cbor
```

**Key design decisions:**

- **One maildir, many wallets.** The developer's transport layer reads
  the `To:` field in each incoming message and routes to the correct
  wallet. The SDK identifies which wallet each message belongs to when
  processing.

- **Validator and Nabla lists are shared.** All wallets on the same
  machine talk to the same network. The seed lists are plain text for
  human readability; the internal state files are CBOR (health tracking,
  discovered hints, fail streaks).

- **Wallet state is per-wallet.** Each wallet has its own CBOR state
  file with flock-guarded writer coordination. Multiple processes can
  operate on different wallets concurrently.

### 3.1 Application configuration (`axiom.conf`)

```
# axiom.conf — one setting: where is the maildir root.
#
# The SDK creates the standard maildir subdirectories (inbox/new,
# inbox/cur, inbox/tmp, outbox/new, outbox/cur, outbox/tmp) under
# this path if they don't exist.
#
# The developer points this to wherever their MTA delivers.
# On Linux with sendmail/FATMAMA: symlink or configure the MTA.
# On mobile: point to wherever the app stores fetched messages.

maildir = /var/mail/axiom
```

The developer sets the maildir root path. What's inside (the standard
maildir subdirectory structure) is fixed by the SDK. The developer may
symlink `maildir/inbox` to an existing sendmail delivery directory, or
configure their MTA to deliver directly into this path.

### 3.2 Seed files (plain text, user-editable)

**`validators.list`** — one validator per line:

```
# Known validators. SDK appends discovered hints.
# Format: name  address  email
alpha   127.0.0.1:9001  alpha@axiom.local
beta    127.0.0.1:9002  beta@axiom.local
gamma   127.0.0.1:9003  gamma@axiom.local
```

**`nabla-nodes.list`** — one Nabla node per line:

```
# Known Nabla nodes. SDK appends discovered hints.
# Format: address
127.0.0.1:7300
127.0.0.1:7301
127.0.0.1:7302
```

These files are the developer's responsibility to populate before first
use. They can be downloaded from a well-known URL, bundled with the app,
or copied from another installation. The SDK reads them on startup and
appends newly discovered nodes (from validator hints and Nabla peer
responses) back to the same files.

### 3.3 Maildir contract

- The `inbox/new/`, `cur/`, `tmp/` structure matches the maildir
  standard exactly. Atomic delivery: the developer's transport writes
  to `tmp/` then `rename()`s into `new/`. The SDK reads from `new/`,
  moves processed files to `cur/`.
- The `outbox/` mirrors the inbox model. The SDK writes to `tmp/` then
  renames to `new/`. The developer's transport reads from `new/`, ships
  the payload, and moves to `cur/` on success.
- All SDK writes use `fsync + flock + rename` for crash safety.

## 4. Public API (the minimum viable)

The SDK exposes **12 user-facing functions** — one process-level
initialiser, eleven wallet operations. Everything else is internal.

```rust
// Process lifecycle — MUST be called once at startup, before any
// wallet open or broadcast. See §4.0.
axiom_sdk::setup() -> Result<()>

// Wallet lifecycle
Wallet::create(name: &str, email: &str, parent_dir: &Path) -> Result<Wallet>
Wallet::open(dir: &Path) -> Result<Wallet>
wallet.close() -> Result<()>                                      // saves + releases lock

// Core operations
wallet.balance() -> u64
wallet.send(to: &str, amount: u64, k: u8, reference: Option<&str>) -> Result<SendResult>
wallet.recv() -> Result<Vec<PendingCheque>>                       // reads inbox/new
wallet.import_cheque(raw: &[u8]) -> Result<usize>                 // out-of-band cheque -> inbox/new
wallet.redeem(cheque_id: &str) -> Result<RedeemResult>
wallet.history(filter: HistoryFilter) -> Result<Vec<TxRecord>>
wallet.list_cheques(status: ChequeStatus) -> Result<Vec<Cheque>>

// Recovery — the four sender-side recoveries (HEAL / BURN / RECALL / HAL;
// see §4.5 and AXIOM_DESIGN_SelfTransactions.md)
wallet.heal() -> Result<HealSummary>                              // fix drift, scars, partials
wallet.burn_scars() -> Result<u32>                                // explicit scar burn (value DESTROYED; user-confirmed)
wallet.recall(send_tx: &[u8]) -> Result<bool>                     // retract a COMPLETED-but-undelivered payment — YPX-022, money RECOVERED
wallet.recall_complete() -> Result<bool>                          // redeem the recall cheque; ends hibernation
wallet.hal_reanchor() / wallet.hal_complete()                     // dead-overlap re-anchor — YPX-020
wallet.complete_registration(txid: &str) -> Result<()>            // finish interrupted registration

// Resumable sends — late-response salvage on a hop timeout (§4.6)
wallet.resume_send() -> Result<SendResult>                        // continue an interrupted round (SAME tx); sweeps late responses
wallet.discard_pending_round() / load_pending_round()             // abandon / inspect a saved interrupted round
```

**Note the absence of a `password` parameter.** Wallet file encryption
at rest is a front-end responsibility — see §4.2. The SDK operates on
plaintext files within a directory it expects to be readable and writable.

**Note the absence of any protocol-internal concept in the function
signatures.** No validators, no Nabla, no S-ABR, no CLARA, no FACT
chains. The developer sees: wallet, amount, recipient, cheque ID. Every
function returns either a success result or an `SdkError` with a clear
recovery action (see §8).

### 4.0 `axiom_sdk::setup()` — NORMATIVE

`setup()` is the SDK's startup gate. It MUST be called exactly once
per process before opening a wallet or running any broadcast op. It:

1. Locates the Core ELF file (`axiom-core.elf`) and verifies it
   can be loaded. Lambda is mandatory-CL1 since beta33; every TX needs
   a Core-signed DMAP execution proof in its witness payload, which
   the SDK generates by running the ELF locally via the embedded DMAP-VM.
   Without the ELF, every broadcast would silently degrade to an empty
   proof and Lambda would reject with the misleading "CL1: missing
   execution proof" — an error that surfaces only after a network
   round-trip and gives no hint about the real cause.
2. Caches the ELF bytes in a process-global `OnceLock<Runtime>` so
   each subsequent CL1 invocation reuses them without re-reading the
   file. The ELF is ~1MB and a busy wallet runs dozens of CL1s per
   minute.
3. Returns a clear error listing every path it searched if the ELF
   isn't found, with explicit guidance on how to fix it (`AXIOM_CORE_ELF`
   env var, or place the ELF at the canonical dev path).

**The gate is enforced inside the SDK.** Every public broadcast
function — `send`, `redeem`, `heal`, `fund_genesis` — calls
`runtime::ensure_setup()` at the entrypoint. If `setup()` wasn't
called, the function returns `ErrorCode::SdkNotInitialized` immediately.
This is fail-fast by design: a misconfigured SDK should not produce
half-formed network traffic.

**ELF discovery order** (checked in order, first match wins; see
`sdk/client/src/cl1.rs`):

1. `$AXIOM_CORE_ELF` environment variable — explicit override.

Then two tiers, each tried `$HOME`-relative → cwd-relative → parent-relative.
The **`core/artifacts/` tier is searched first** — it is the committed,
git-synced published ELF (the one whose CoreID `VERIFYING.md` pins):

2. `$HOME/axiom/src/core/artifacts/axiom-core.elf`
3. `core/artifacts/axiom-core.elf`
4. `../core/artifacts/axiom-core.elf`

Then the `core/avm-guest/target/` tier — a gitignored *local build* output,
the fallback when you built the ELF yourself rather than using the published one:

5. `$HOME/axiom/src/core/avm-guest/target/axiom-core.elf`
6. `core/avm-guest/target/axiom-core.elf`
7. `../core/avm-guest/target/axiom-core.elf`

**Idempotency:** `setup()` is safe to call multiple times. The first
successful call caches the ELF; subsequent calls are no-ops.

**Reference example:** the macOS `AxiomWallet.app` calls `sdkSetup()`
inside `applicationDidFinishLaunching`. On failure, the wallet
refuses to open and shows a fatal-startup screen with the searched
paths and a Quit button. No way to fumble into a broadcast op
without a working SDK runtime.

**Soak harness:** the Python soak (`tests/soak_test_v2.py`) and any
similar harness driving the SDK MUST call `setup()` (via its pyo3
binding) — or set `AXIOM_CORE_ELF` and ensure the ELF exists — at
process boot, otherwise the gate fires on every send/redeem/heal
the harness runs.

### 4.1 `Wallet::create` — what it actually does

Creating a new wallet is the SDK's job on the protocol side (key
generation, wallet_id binding, directory layout, state initialization)
and the front-end's job on the storage side (where the directory lives,
what encryption protects it, who's allowed to read it).

The SDK handles, when you call `create`:

1. **Generate a fresh Ed25519 keypair** using the OS secure RNG. The
   private key is written into `wallet.axiom` as part of the normal state
   serialization. It does not leave the SDK as a separate value the
   front-end has to handle.
2. **Derive the wallet_id** per YPX-007: the wallet_id format includes a
   `pk_bind` suffix cryptographically tied to the Ed25519 public key, so
   the wallet's network identity is verifiable from the public key alone.
3. **Validate the email format** — must match the shape the protocol
   expects (local-part + `@domain`). Uniqueness is not the SDK's concern
   (the front-end / network operator / deployment decides that).
4. **Compute the genesis state_id** — SHA3-256("AXIOM_GENESIS" || pk ||
   balance=0). This is the wallet's initial state before any transaction.
5. **Initialize the wallet state file** (`wallet.axiom`) with: fresh
   public key, fresh private key, zeroed balance, wallet_seq = 0,
   genesis state_id, empty last_receipt, empty fact chain, no active
   CLARA attestation, sdk_version and contract_version fields set.
   The file uses CBOR format with `AXWL` magic header + version byte.
6. **Create the wallet directory** at `{wallets_dir}/{name}/` with
   `cheques/` subdirectory.
7. **Acquire the writer lock** on `wallet.axiom.lock` and return the
   `Wallet` handle ready for immediate use. The returned handle holds the
   lock until `close` is called.

**What the front-end does NOT do:**
- Generate keys (the SDK owns crypto)
- Compute the wallet_id (the SDK owns YPX-007 binding)
- Create directories (the SDK owns the filesystem layout)
- Decide the wallet_seq or state_id starting values (the SDK owns protocol
  invariants)

**What the front-end DOES handle (related to create):**
- Picking `parent_dir`. Typically this is a platform-sandboxed location:
  `Documents/` on iOS, `filesDir` on Android, an OPFS-backed path in the
  web client, `$HOME/.axiom/` or similar on native desktop.
- Ensuring the chosen `parent_dir` has whatever access control /
  encryption the platform provides **already applied before calling
  `create`**.
- Collecting and validating the user-supplied `name` and `email` strings
  via its own UI before passing them in.

**Funding a freshly-created wallet** is NOT part of `create`. A new wallet
has zero balance until it either:
- Receives cheques (via the normal `recv` path), or
- Is funded by a test-network genesis operation (via a dedicated
  `wallet.fund_from_test_genesis(...)` function, available only when the
  SDK is built with the `test-genesis` feature flag — never in production
  builds).

The separation is deliberate: creation is protocol-compliant and works
identically in every environment; funding is network/deployment-specific
and must not leak into the production API surface.

### 4.2 Storage encryption is the front-end's job (NORMATIVE)

**Boundary — the division of responsibility.** `axiom-sdk` (including the
`axiom-sdk-wasm` browser bindings) is **protocol security only**: it owns the
cryptography that makes a transaction valid on the network — Ed25519 signing,
witness / VBC / NBC verification, the YP §39.3 `auth_hash` owner-proof — and
nothing else. Protecting the wallet *bytes at rest* — so a thief holding the
file, the browser `localStorage`, or the disk image cannot read the keys — is
the **application's** responsibility, never the SDK's. The SDK reads and writes
plaintext through its `Storage` trait; the front-end decides how those bytes are
protected before they land and after they are read. **Do not add at-rest
encryption, a password KDF, or a keystore cipher to `axiom-sdk-core` or any
binding** (`encode_wallet` / `decode_wallet` and the wasm bindings stay
plaintext); put it in the application that wraps the `Storage` trait. This is a
standing rule, not a default — local security is the developer's call.

**The SDK does NOT encrypt the wallet state file.** It reads and writes
`wallet.json` and the other directory contents as plaintext. Every
platform the SDK targets already has OS-level or platform-native
encryption at rest, and those mechanisms are strictly better than
anything the SDK could portably implement:

| Platform | Native encryption mechanism | Unlock UX |
|---|---|---|
| **iOS** | Data Protection (`NSFileProtectionComplete`) encrypts app-container files with keys derived from the device passcode and sealed inside the Secure Enclave. Files are inaccessible when the device is locked. | FaceID / TouchID / passcode via iOS; SDK just reads files. |
| **Android** | File-based encryption (FBE) since API 26 plus `EncryptedFile` or `StrongBox` Keystore for hardware-backed wrapping. Per-user directories are encrypted at the filesystem layer. | BiometricPrompt / Keystore / user lock screen; SDK just reads files. |
| **Web (WASM)** | `localStorage` / OPFS have no native at-rest encryption, so the front-end wraps the SDK's `Storage` trait — sealing the keystore before it is written and opening it on read. **Constraint:** the `Storage` trait is *synchronous* (the SDK calls `read` / `write_atomic` from inside synchronous wasm `save()` calls), so the per-write cipher must also be synchronous — WebCrypto `subtle` (async) **cannot** be used per save. Use a synchronous AEAD (XChaCha20 / XSalsa20-Poly1305) for the per-write seal and run the KDF **once at unlock** (async is fine there) via `subtle` PBKDF2 or a WebAuthn-derived wrapper. Reference implementation: the webclient (`apps/webclient/web/vault.js` + the `index.html` storage shim — an `AXEJ` frame, PBKDF2 + TweetNaCl `secretbox`). | Password prompt (PBKDF2) or WebAuthn passkey. |
| **macOS** | The app seals the keystore with a random 256-bit data key held in the **Keychain**, device-bound (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud sync). FileVault + login ACLs underneath. Reference implementation: AxiomWallet `WalletVault.swift` (CryptoKit `AES-256-GCM`, an `AXMK` frame) supplying the generic `WalletCipher` FFI callback (below). The Keychain key never leaves the Mac; portability is an explicit **password-encrypted `AXPW` Export** (Wallets → Export — `"AXPW"|ver|kdf|salt(16)|nonce(12)|AES-256-GCM(ct‖tag)`, key = PBKDF2-HMAC-SHA256(`"AXIOM_PORTABLE_WALLET_v1"||0x00||walletKey`, salt, 600k); `PortableBackup.swift`), so no plaintext keys cross. The webclient import decrypts it with the same wallet key (WebCrypto `subtle`, once at import) and re-seals under its own `AXEJ` envelope; a raw decrypted `AXWL` is still accepted on import for back-compat. | Device login + the app's existing Touch ID (the data key is cached for the session, so seal/open never prompt per-save). |
| **Native desktop (Linux/Windows)** | User's disk encryption (BitLocker, LUKS, dm-crypt) + OS login ACLs; or the OS secret store (Secret Service / DPAPI) holding a data key like macOS does. | Device login. |

**Why this is strictly better than an SDK-managed KDF:**

1. **Platform-native encryption uses hardware-backed keys** (Secure
   Enclave, StrongBox, TPM) that an SDK-portable implementation cannot
   reach from Rust.
2. **Biometric unlock integrates for free.** FaceID, fingerprint, and
   WebAuthn passkeys all work by gating access to the storage key at the
   OS layer. The SDK never sees a password, never runs a KDF, never
   writes a zeroizable password buffer — it just reads the directory the
   OS decrypted for it.
3. **Compliance and regulatory posture** (FIPS 140-3, Common Criteria,
   mobile app store review) is handled by the platform, not by the SDK
   shipping a specific cipher suite.
4. **Wallet portability** between platforms via the SDK's `export` /
   `import` functions, which serialize the **protocol-relevant state, not
   the at-rest encryption envelope** — so moving a wallet is a clean
   re-import under the user's active control, never a "copy the encrypted
   file and hope the KDF parameters match" gamble. The SDK's exported form
   is the plaintext canonical state (`AXWL`); an **app may wrap that for
   transit** under its own password envelope (e.g. macOS `AXPW`), which the
   receiving app decrypts on import and **re-seals under the target
   platform's at-rest envelope** (e.g. the web's `AXEJ`) — so no plaintext
   file need cross, and it is still app-layer transit crypto, never the
   SDK's at-rest envelope.

**Consequence:** `Wallet::open(dir)` takes no password. If the platform
storage at `dir` is locked (device passcode, user logged out,
biometric lock engaged), filesystem reads fail with
`std::io::ErrorKind::PermissionDenied` or similar, the SDK returns
`Error::Io`, and the front-end's job is to show an "unlock to continue"
prompt using whatever mechanism the platform provides. Once the user
unlocks, the front-end retries `Wallet::open(dir)` and it works.

On the **web** there is no OS lock to trip: the front-end derives the at-rest key
from the user's password at unlock, and a wrong password makes the wrapping
layer's decrypt fail authentication — which the front-end surfaces as "wrong
key," replacing any plaintext password check (decryption *is* the gate). The
SDK's `auth_hash` / `verifyKey` owner-proof still runs afterward as an
independent protocol-level check; the two are separate and both apply.

**The SDK ships zero crypto dependencies for wallet-file encryption.**
The only cryptography the SDK carries is protocol cryptography:
Ed25519 (signing), BLAKE3 (hashing), ML-DSA / Dilithium (verification),
SLH-DSA / SPHINCS+ (verification of Nabla signatures, VBC, NBC). No
Argon2, no ChaCha20, no AES-GCM, no scrypt. Smaller binary, smaller
attack surface, simpler threat model.

**The injection seam, per binding (generic — NOT platform-specific).** Each
binding lets the app supply storage so it can wrap the keystore bytes; the SDK
core stays IO-free and crypto-free:
- **WASM** (`axiom-sdk-wasm`): the app passes a `JsStorage` object
  (`createWithJsStorage` / `openWithJsStorage`). The webclient's `vault.js`
  seals inside it.
- **Native / uniffi** (`axiom-sdk-ffi`): the app passes a `WalletCipher`
  callback (`open_encrypted` / `from_file_encrypted` /
  `create_wallet_pair_encrypted`). The Rust side keeps owning filesystem IO +
  atomic writes and only routes the `*/wallet.axiom` bytes through the app's
  `seal`/`unseal`. This is implementable by **any** uniffi consumer — Swift on
  macOS/iOS, Kotlin on Android — so it is a generic seam, not a macOS feature.
  macOS supplies it via `WalletVault` (Keychain + AES-GCM); Android would supply
  the equivalent with the Android Keystore. Nothing platform-specific lives in
  the SDK.

**SDK error taxonomy remains:**

- **ProtocolReject** — the network refused the operation for a cryptographic
  or consensus reason. Rare. The caller should surface to the user and
  investigate.
- **RecoverableDrift** — the SDK detected drift and is auto-recovering
  (CLARA, resync, retry). Returned only when auto-recovery fails after all
  internal retries. The caller should suggest a manual heal or retry later.
- **Io** — filesystem / storage error. Includes "storage locked" as a
  special case where the front-end should prompt for unlock and retry.
- **ClientBug** — the SDK hit an invariant violation. Panics or returns
  this error only for conditions that should never happen. Always report.

### 4.3 `wallet.import_cheque` — out-of-band cheque ingest

`recv()` only sees cheques the transport layer has already dropped into
`maildir/inbox/new/`. A recipient whose wallet client cannot pull mail
itself — or who was handed a cheque offline (a saved message file, a
text snippet) — needs a way in. `import_cheque` is that adapter, and
nothing more:

```rust
wallet.import_cheque(raw: &[u8]) -> Result<usize>
```

It takes the raw bytes of *whatever the user obtained* — a `.eml` /
`.emlx` / `.msg` exported from any mail client, a `.txt`, raw cheque
CBOR, or pasted message text — extracts every cheque payload it can
find, and writes each as a file into this wallet's `maildir/inbox/new/`.
It returns the number of payloads written (`0` ⇒ no recognisable cheque
in the input).

It is **source-agnostic** (the caller supplies bytes; file-picker vs
paste vs drag-drop is a front-end concern, not an SDK one) and
**format-agnostic**: rather than parsing each mail client's MIME
structure, it scans the input for base64 runs (raw and
quoted-printable-decoded) and keeps the runs that decode to a valid
cheque CBOR, plus a whole-input-as-CBOR attempt for raw `.cbor`
hand-offs.

Crucially, `import_cheque` does **only** read-and-write. It does not
group, deduplicate, count toward the k-of-k bundle threshold, or decide
whether a cheque is addressed to this wallet — it deposits payloads
where the SDK already reads them, and the caller's subsequent `recv()`
performs all of that exactly as for a transport-delivered cheque. This
keeps a single ingestion path: `import_cheque` → `inbox/new/` →
`recv()`.

## 4.4 Send Proof — verify & export API (NORMATIVE)

Beyond the core lifecycle, the SDK exposes a **Send Proof** surface: produce a
portable, offline-verifiable proof of a dispatch, export it, and verify it —
including a **Core-attested** path that runs verification *inside the Core ELF*
so the verdict is Core's, not the SDK's. Full design + threat model:
`docs/AXIOM_DESIGN_SendProof.md`.

**Producer (`axiom-sdk`)**

| fn | purpose |
|----|---------|
| `send_retained(wallet, to, amount, message, nabla, config) -> SendResult` | Classical send + retain. Strips witness VBCs (~80× smaller). Library-verifiable only. |
| `send_retained_pq(…)` *(same signature)* | **PQ-durable** send + retain — keeps each witness's VBC chain. **Required for Core (CL12) verification**; use for bank-grade / Core-attested proofs. |
| `export_send_proof(wallet, txid_hex) -> Vec<u8>` | Read the retained canonical CBOR bundle (`RetainedSend`). |

**Offline verifiers**

| fn | checks | forgery-proof |
|----|--------|---------------|
| `verify_send_proof(proof, core_id?, sdid?) -> SendProofVerdict` | client sig, commitment, receipt-commitment, k Ed25519 witness sigs, bundle digest | **No** — does not check validator legitimacy (any 3 keys pass). Fast / offline / WASM-safe. |
| `verify_send_proof_pq(proof, core_id?, sdid?) -> SendProofVerdict` | the above **plus** each witness's VBC chains to `ROOT_AUTHORITY_PKS` | Yes (SDK library, `_no_time`). |
| `verify_send_proof_core(proof, elf_path?) -> CoreSendProofVerdict` | runs **mode CL12 inside the Core ELF** (DMAP-VM): same VBC→genesis check, VBC expiry at `receipt.epoch` | **Yes — AUTHORITATIVE.** Verdict is Core's, reproducible against the published CoreID, zk-attestable. `elf_path = None` uses the runtime's cached canonical ELF (`setup()` first). Rejects a classical (VBC-stripped) proof `InvalidVBC`. |

**Certificate + format**

- `render_send_certificate(verdict, proof) -> String`, `render_send_certificate_pdf(verdict, proof) -> Vec<u8>` — the human/court-readable "Certificate of Irrevocable Dispatch". The PDF **embeds the bundle** as an attachment, prints amounts in atoms (the signed quantity) plus the entered AXC, wraps every line to the page, and carries an evidentiary-scope appendix.
- `axiom_sdk_core::send_proof::extract_bundle_from_certificate_pdf(pdf) -> Option<Vec<u8>>` — recover the embedded bundle from a certificate PDF, so the PDF doubles as the verifiable object.
- **File format `.axproof`** — the raw `RetainedSend` CBOR (the verifiable object), registered as the macOS UTType `org.axiom.proof` ("AXIOM Proof"). The small data file for institutional intake that blocks PDFs; the certificate PDF is the human rendering of the same bundle. Both re-verify identically.

**FFI / Swift bindings (`axiom-sdk-ffi`, uniffi)**

| binding | maps to |
|---------|---------|
| `wallet.sendWithProof(to, amountAtoms, reference, message, deliveryEmailOverride) -> SendResultRow` | `send_retained_pq` (PQ; retains VBCs) |
| `wallet.exportSendProofCbor(txidHex) -> [UInt8]` | `export_send_proof` (the `.axproof` bytes) |
| `wallet.exportSendCertificatePdf(txidHex) -> SendCertificatePdfRow` | verify (CoreID **unpinned**) + render PDF |
| `verifySendProofBytes(proof, expectedCoreId?, expectedSdid?) -> SendProofVerdictRow` | `verify_send_proof` (library) |
| `verifySendProofCoreBytes(proof) -> CoreSendProofVerdictRow` | `verify_send_proof_core` (CL12 via bundled ELF; no local Core build) |
| `proofBundleFromAny(data) -> [UInt8]` | normalize a certificate PDF / `.axproof` / `.cbor` → bundle (extracts the embedded bundle if PDF) |
| `certificatePdfFromProof(proof, …) -> SendCertificatePdfRow` | verify + render from a raw bundle |

Records: `SendProofVerdictRow { valid, reason, senderWalletId, receiverWalletId, amount, message, witnessCount, coreIdHex, sdidHex, txidHex }`; `CoreSendProofVerdictRow { valid, reason, txidHex, coreIdHex }`; `SendCertificatePdfRow { ok, pdf, reason }`.

**CLI** — `tools/verify-send-proof <core-elf-path> <proof.(axproof|cbor)>` pipes a proof straight into the Core ELF (CL12) and prints Core's verdict; zero SDK verification on the path.

**Python** — `send(retain=True, pq=True)`, `verify_send_proof(bytes, core_id, pq=True)`, `verify_send_proof_core(proof_bytes, elf_path)`.

## 4.5 RECALL — retract a completed-but-undelivered payment (YPX-022, NORMATIVE)

The third sender-side recovery: a send that **completed** (3-of-3, sender
debited, cheque completion-registered) but whose cheque **never reached the
receiver** — and which the receiver has NOT redeemed. The value is stranded:
the receiver can't redeem what they never got, the sender can't re-spend what
they paid out. RECALL retracts it through the standard `tx → cheque → redeem`
flow. (Under the quorum gate there is NO failed-send recovery to need — a
sub-quorum send is a no-op, nothing debited.) Full protocol:
`AXIOM_YPX-022_RECALL.md` §2. The four recoveries, side by side:

| recovery | when | money |
|----------|------|-------|
| `heal()` | drift / scars / partial-commit poisoning | kept (re-anchor; no value moves) |
| `burn_scars()` | unresolvable scarred links | **destroyed** (explicit, user-confirmed) |
| `recall(send_tx)` | a completed send, unclaimed past the window, cheque undelivered | **recovered** (retracted) |
| `hal_reanchor()` | dead-overlap (prior witnesses gone) | kept (re-anchor + hibernation) |

**Eligibility (§2.1, enforced at Nabla with zero sender-trust):**
completion-registered + status `NotRedeemed` + aged into the recall
initiation window + OODS-healthy. Deliberate, never failure-reactive.

**Native flow (two legs, client-driven — the SDK never auto-completes):**

1. `wallet.recall(send_tx)` — ENQUIRES first (the standard `query-txid`
   read, surfacing already-redeemed / already-recalled / nothing-to-recall /
   too-early / too-late legibly BEFORE anything is spent), then opens the
   recall RESERVATION at Nabla (§2.2.1 — consume-once, idempotent per
   sender; the receiver's cheque STAYS redeemable and a redeem that
   finalizes during the reservation WINS), then drives the witnessed
   `kind=Recall` self-send whose registration COMMITS the retract at
   hibernation-entry. No debit; the produced state carries the recall
   hibernation window. The completed send's serde-CBOR comes from the
   durable Send Proof store (`retained_send_tx_cbor(txid)` — any session)
   or `wallet.last_send_tx_cbor()` (the session cache).
2. `wallet.recall_complete()` — after the window, redeems the recall
   cheque (delivered to the wallet's own inbox, k-signed for exactly the
   retracted amount). This is the ONLY balance write (B−A + A = B) and it
   clears hibernation — the same completion shape as HAL §2. §2.2.2: Core
   CL5 accepts this hibernation-exit redeem only under a verified-healthy
   OODS reading (`E_OODS_UNHEALTHY_RETRY` = retry later, liveness-only).

**WASM flow (two-phase, mirrors the heal family):**

1. Every successful `sendFund` surfaces the built tx as `sendTxCbor`; the
   front-end stashes it via `wallet.stashLastSendTx(bytes)` (persisted in
   the wallet file — a browser reload does not lose the recallable send).
   `wallet.hasRecallableSend` gates the "Recall a payment" affordance.
   (A failed send stashes nothing — it's a no-op under the quorum gate.)
2. `wallet.recallFund(transport, params, progress)` → resolves the
   witnessed outcome (`recalledTxidHex`, `recallAmount`, `recallTick`,
   `hibernationUntil`, `oodsAttestationCbor`, …) →
   `wallet.commitRecall(...)` persists the recall record + hibernation
   stamp; stash the outcome's OODS reading — the completion redeem
   REQUIRES one under the §2.2.2 exit gate.
3. Finish = redeem the recall self-cheque via the normal redeem path on
   the **'redeem'-typed transport**, then `wallet.clearHibernation()` +
   `wallet.markRecallCompleted(txidHex, chequeId)` (the local mirrors of
   what Core CL5 already cleared / what native `redeem.rs` fills
   implicitly). `wallet.recallRecords()` lists the bookkeeping rows.

**Receiver side:** `query-txid` serves an open reservation as the unsigned
`claim_status = "RETRACT_PENDING"` ("the sender is retracting this payment —
redeem now or it will be recalled"; the cheque is still live and a redeem
that finalizes now wins) and a committed retract as `"RETRACTED"` — both
the native redeem path and the wasm redeem machine surface "this payment
was retracted by the sender" instead of a generic already-redeemed error.

**Boundary (NORMATIVE):** a `Redeemed` txid refuses recall, and a committed
recall permanently kills the cheque mesh-wide — per txid, exactly one of
{recall, redeem} ever settles; first-wins is final. The SDK exposes the
legs; the front-end decides when to invoke them (§6,
AXIOM_DESIGN_SelfTransactions.md).

## 4.6 Resumable sends — late-response salvage (NORMATIVE)

Witnessing has **no protocol expiry**: a signed transaction and any witness
signatures it has collected stay valid until the wallet's state moves (Core
has no epoch-freshness gate; the quorum gate counts the assembled `k` sigs
whenever a receipt is anchored). The **only** timeout in the system is the
*client's per-hop patience* while polling the carrier for a witness response.
So a "timed-out send" is not a dead send — the client merely stopped waiting,
and a response that arrives after the deadline (busy env, slow carrier) still
counts. This is the send-side analogue of the redeem path's late-response
scavenge.

**Mechanism (client-side only — no wire or protocol change, CoreID-neutral):**

1. On a per-hop **timeout** (never a rejection — those keep their partial-
   commit / heal semantics), the round is persisted to
   `{wallet_dir}/pending_round/current.cbor`: the signed transaction (same
   canonical bytes ⇒ same `txid`), the witness sigs + response maps collected
   so far, the ordered validator set, and every issued `request_id`.
2. `wallet.resume_send()` re-enters the **same** send pipeline (not a second
   code path): it first sweeps the inbox for responses that arrived after the
   client gave up (dedup by each sig's own `validator_id`), then continues the
   remaining hops with the same transaction, and runs the unchanged
   finalize/commit/register tail.
3. **Idempotent redelivery**: a hop that was already delivered re-uses its
   original `request_id`, so a validator that committed but whose response was
   lost **replays** its cached witness response (YPX-016 witness idempotency
   cache) instead of rejecting the re-consume.

**Guards (NORMATIVE):**
- A round is resumable only while it still anchors to the wallet's current
  state (`consumed_state_id` + `wallet_seq` match). Any committed TX in
  between — including a heal — invalidates it; a stale round self-discards.
- **Latest-wins**: starting a *new* `send()` from the same state **abandons**
  any pending round before building its tx (a fresh tx racing the old round's
  already-collected commits would be a same-seq divergence). Only the most
  recent interruption is resumable.
- A **validator verdict** (rejection / partial commit) ends the round — the
  pending round is discarded, because a resume would deterministically replay
  the cached rejection. Only a pure timeout persists a resumable round.
- `send_retained` (Send Proof) records its retention intent on the pending
  round; a resumed completion writes the same eager proof the timeout preempted.

The front-end surfaces a resumable round (e.g. an "interrupted send —
resumable" affordance) and invokes `resume_send()` / `discard_pending_round()`;
the SDK never resumes autonomously (§14 posture). The wasm SendMachine twin of
this persistence is a follow-up.

## 5. Internal responsibilities

When the user calls `wallet.send(to, 1000)`, the SDK internally:

1. Loads current wallet state under flock
2. Builds the TX (consumed_state_id, wallet_seq+1, nonce, epoch, sig, owner_proof)
2b. **Fetches one Nabla OODS reading (YPX-021 §8.2)** — `fetch_oods_attestation`
    picks a node and issues the read-only `OodsReadingRequest`, getting back a
    Nabla-signed `NablaOodsAttestation` (network-size estimate + the node's NBC
    baseline). The SAME reading rides every hop of this send, so all k
    validators' Core bind the same health flag into `receipt_commitment`. A
    fetch failure is LOUD-but-non-fatal (the receipt carries no flag — legal in
    Phase 1). The SDK never verifies or acts on the reading itself: Core does
    (CL3 `verify_oods_attestation`), and stamps `Receipt.oods_flag`.
3. Selects k=3 validators with overlap-first ordering per S-ABR
4. Runs serial witness with:
   - Same-validator retry on transient failures (YPX-016 cache path)
   - Backup validator retry on unreachable-original
   - Reactive blacklist on `E_SABR_HASH_MISMATCH`: inline replacement from backup pool,
     preferring overlap-pool candidates (YPX-018 §2.1.1). Persists blacklist on wallet.
   - Overlap requirement derived from previous TX's k (`sabr_overlap(prev_k)`),
     not current TX's k — prevents tier-downgrade double-spend (v2.11.16).
5. If partial witness (ok_count < k): triggers CLARA heal flow
   - Generates TX_HEAL self-send
   - Calls Nabla's `POST /clara` (from front-end: SDK writes request to
     outbox, front-end ships, response comes back via inbox)
   - Attaches attestation to retry TX
6. On k=3 success: registers with Nabla (via outbox → front-end → Nabla)
7. Writes outbound cheque payloads to `outbox/pending/` (one per recipient,
   or one envelope containing k cheques — implementation detail)
8. Updates wallet state: new state_id, new balance, new seq, new last_receipt
9. Appends to `history.json`
10. Releases flock
11. Returns the new txid

**Every step that would normally be a rule a client has to learn from the
Yellow Paper is hidden behind this one function call.** The SDK implements
YP §17.4 (witness flow), §17.9.3 (sender flow), §17.9.4.0 (receiver dedup —
for the reverse path), YPX-016 (cache retry), YPX-018 (CLARA), YPX-002 §4.6
(when `recv` is called), and §23.14 (peer audit signals) automatically.

## 6. Front-end responsibilities

A front-end implementation of any kind (email app, webclient, mobile,
merchant SDK consumer) is responsible for exactly four things:

1. **Inbox delivery:** move incoming cheque payloads from the carrier
   (IMAP, HTTP, push, clipboard) into `inbox/new/`. Use write-to-tmp then
   rename for atomicity.
2. **Outbox shipping:** read pending cheque payloads from `outbox/pending/`,
   ship them to the recipient via whatever carrier, move to `outbox/sent/`
   on success. If shipping fails, leave in `pending/` and retry.
3. **Password management:** handle the user's wallet password UX. Pass the
   password to `Wallet::open` at unlock time. The SDK derives keys from
   there; the front-end never sees or stores derived keys.
4. **UI/UX:** display balance, history, pending cheques, transaction
   status. Call SDK functions on user actions.

**Front-ends explicitly do NOT:**

- Implement validator selection
- Implement retry logic
- Implement dedup
- Implement CLARA heal
- Touch the wallet state file
- Manage Nabla registration
- Verify signatures or fact chains
- Know what S-ABR or YPX-016 are

If a front-end finds itself needing to do any of these things, either (a)
the SDK is missing a function and should grow one, or (b) the front-end
is reinventing something the SDK already does and should just call the
SDK instead.

### 6.0b OODS view-health surfacing is the front-end's job (YPX-021 §8.2, NORMATIVE)

Two OODS signals are available to a wallet UI, both read-only:

1. **The live network-size reading.** The front-end MAY show the current OODS
   estimate by issuing the read-only `OodsReadingRequest` to a Nabla (native
   SDK: `fetch_oods_attestation`; a thin FFI accessor is the clean way to expose
   it to Swift/Kotlin — mirror `sdk_probe_nabla_mode`). Display it as a
   **point-in-time estimate**, never a stored baseline or high-water mark: a
   dormant wallet waking in a legitimately-smaller network is healthy, not
   shrunk (§8.1). `baseline_size == 0` (genesis-exempt dev nodes) reads healthy
   by construction — correct, not a stub.
2. **The stored per-transaction health flag.** Every witnessed receipt now
   carries `Receipt.oods_flag { tick, oods_size, healthy }` (Core-stamped, bound
   into `receipt_commitment`). A front-end MAY surface `healthy` on a
   transaction's detail view ("witnessed under a healthy network view"); a
   `healthy = false` receipt is the SCARRED-not-CLEAN, compression-blocked case
   (§8.2).

The SDK deliberately does NOT decide UX policy here (banner vs chip vs silent) —
same rationale as §6.1: it exposes the data, the application renders it.

### 6.1 Release / version / worldline checking is the front-end's job (NORMATIVE)

Wallets typically want to (a) tell the user when a newer build is
available, (b) **force** an update when the network has moved to a Core
whose CoreID differs from the one they bundle (a mismatched Core diverges
— see the White Paper Core-upgrade section), and (c) read the Console's
*suggested* L$ `digit_version` so balances display on the network's
current scale. The AXIOM reference wallet does all three by fetching two
small JSON files from a distribution host (`releases.json` +
`worldline.json`), comparing versions and CoreIDs, and surfacing an
optional banner / mandatory hard-lock / dv-change notice.

**The SDK does NOT implement this, and deliberately so.** A developer
building on the SDK must implement update- and worldline-checking
themselves. Two independent reasons:

1. **It would violate the network-IO boundary (§2).** The SDK opens
   exactly one kind of network connection — to a **Nabla node**, for
   protocol-mandatory state. Everything else is filesystem IO; carriers
   are the application's job. A release/worldline feed lives on an
   ordinary HTTP host (GitHub raw, a CDN, an operator's server), which is
   **not** Nabla. Fetching it from `axiom-sdk-core` or `axiom-sdk` is a
   layering violation, and it is **mechanically rejected** by
   `scripts/check_layer_boundary.sh` (no `std::net` / HTTP imports in
   those crates). The socket has to live in the application (or in
   `axiom-sdk-transports`).

2. **It is distribution policy, not protocol.** AXIOM is permissionless:
   many independent wallets exist, each with its own release channel,
   feed location, update cadence, and update UX. `digit_version` itself is
   **suggested, not enforced** — any wallet may ignore it and trade in AXC
   only (AXC / atoms are the invariant unit; dv only rescales the L$
   *label*). Baking one feed scheme into the SDK would impose one
   distributor's choices on every other wallet and imply a coordination
   point the protocol does not have. The SDK stays agnostic; the wallet
   decides if, where, and how it checks.

**What the SDK DOES give you** — the protocol-bound primitives, so the
front-end never has to reinvent the consensus-adjacent parts:

- `sdk_canonical_core_id()` — the CoreID the bundled Core ELF hashes to.
  Compare it against the network's live CoreID (however you obtained that)
  to decide *optional* vs *mandatory* update. This value is the one the
  wallet's own CL1 gate trusts, so it is the correct left-hand side of the
  comparison.
- `sdk_build_version()` — the SDK/Core build version string.
- `format_ldollar(atoms, dv)` / `format_ldollar_short(atoms, dv)` — the
  canonical atoms→L$ rendering for a given `digit_version` (full precision
  and 2-decimal "money" form). Use these so every wallet shows the same L$
  for the same dv; do not hand-roll the `10^dv` math.

**What the front-end owns:** the HTTP fetch of whatever feed it chooses;
parsing it; persisting the last-seen dv; deciding the optional-banner /
mandatory-lock / dv-change-notice UX; and where the dv comes from. The
macOS reference implementation lives in
`apps/macos/AxiomWallet/Sources/AxiomWallet/{ReleaseUpdate,ReleaseUpdateWatcher,DigitVersionWatcher}.swift`
— a developer can copy that pattern: fetch bytes → compare against
`sdk_canonical_core_id()` → render with `format_ldollar*`.

> If a future need arises to share the **pure parse/verdict logic**
> (version compare, CoreID compare, dv-change detection) across wallets
> without sharing a feed scheme, the layering-safe way is a no-IO helper
> in `axiom-sdk-core` that takes already-fetched bytes and returns a typed
> verdict — the application still owns the socket. That is an
> optimization, not a requirement; it is explicitly **not** implemented
> today.

## 7. Concurrency

The SDK supports **single-writer, multi-reader** concurrency on a wallet
directory:

- **One writer at a time.** `Wallet::open` acquires an exclusive flock on
  `wallet.json.lock`. Another process calling `open` on the same wallet
  blocks until the first closes. This prevents the dual-file persistence
  race that bit us this week (see `docs/AXIOM_REPORT_HashMismatch.md`
  §2.1.2).
- **Readers can snapshot concurrently.** A read-only API variant
  (`Wallet::snapshot(dir)` — tentative) acquires a shared lock and returns
  a point-in-time view for display purposes. Cannot call send/redeem from
  a snapshot.
- **Front-ends that need concurrent access** run multiple processes, each
  taking the writer lock briefly. This is the maildir pattern: multiple
  delivery agents can drop files into `inbox/new/` without coordination
  (atomic rename), but only one MUA has the wallet open for mutation.

## 8. Error design (NORMATIVE)

### 8.1 Design principle — every error tells you what to do

The developer calling `wallet.send()` should never need to understand
AXIOM protocol internals to handle an error. Every error the SDK returns
carries three things:

1. **A stable error code** — machine-readable, safe to match on, never changes
2. **A human-readable message** — one sentence explaining what happened
3. **A recovery action** — what the developer should do next, expressed as
   an SDK function call or a simple instruction

The developer's error handling is always the same pattern:

```rust
match wallet.send("alice@axiom", amount, 3, None) {
    Ok(result) => { /* success — show txid to user */ },
    Err(e) => match e.recovery {
        Recovery::Retry              => { /* just call send() again */ },
        Recovery::RetryAfter(secs)   => { /* wait, then call send() again */ },
        Recovery::Heal               => { wallet.heal()?; /* then retry send */ },
        Recovery::CheckInbox         => { wallet.recv()?; /* then retry */ },
        Recovery::Fatal              => { /* show e.message to user, stop */ },
    }
}
```

That's it. The developer never asks "what is S-ABR?", "what is CLARA?",
"what is a FACT chain?", or "which Nabla node failed?" Those are the
SDK's problems.

### 8.2 Error structure

```rust
/// Every public SDK function returns Result<T, SdkError>.
pub struct SdkError {
    /// Stable error code. Safe to match on. Never changes across SDK versions.
    pub code: ErrorCode,

    /// Human-readable message. One sentence. Suitable for UI display.
    /// Example: "Insufficient balance: have 500 atoms, need 10,000,000,000"
    pub message: String,

    /// What the developer should do next.
    pub recovery: Recovery,

    /// If this error originated from a network rejection, the raw
    /// network error code is included here for diagnostics/logging.
    /// Developers should NOT match on this — match on `code` instead.
    /// Example: "E_SABR_HASH_MISMATCH", "E_INSUFFICIENT_BALANCE"
    pub network_code: Option<String>,
}

/// What the developer should do to recover from this error.
pub enum Recovery {
    /// Just call the same function again. The SDK has already cleaned up
    /// internal state. Transient failure (network timeout, busy node).
    Retry,

    /// Wait this many seconds, then call the same function again.
    /// The network is temporarily congested or a time-gated check
    /// hasn't matured yet.
    RetryAfter(u64),

    /// Call wallet.heal() first, then retry the original operation.
    /// The SDK detected internal state drift and needs to repair before
    /// the operation can succeed.
    Heal,

    /// Call wallet.recv() first, then retry. The SDK needs incoming data
    /// (e.g., cheques not yet delivered) before it can proceed.
    CheckInbox,

    /// The wallet state has been updated — call wallet.send_complete()
    /// to finish registration. This happens when the core transaction
    /// succeeded but post-transaction registration was interrupted.
    /// The cheques are valid; registration can be completed later.
    CompleteRegistration,

    /// Nothing the developer can do programmatically. Show the message
    /// to the user. Examples: insufficient balance, invalid recipient
    /// address, wallet version mismatch.
    Fatal,
}
```

### 8.3 Error codes

Every error code is permanent. Once assigned, it never changes meaning
and is never removed. New codes may be added in future SDK versions.

#### Send errors

| Code | Message pattern | Recovery | When |
|---|---|---|---|
| `InsufficientBalance` | "Insufficient balance: have {X}, need {Y}" | `Fatal` | amount + fee > balance |
| `InvalidRecipient` | "Invalid recipient address: {detail}" | `Fatal` | malformed wallet_id |
| `SendSuccess_RegistrationPending` | "Transaction sent but network registration incomplete" | `CompleteRegistration` | k witnesses succeeded, Nabla registration failed |
| `NetworkTimeout` | "Network timeout — all retries exhausted" | `Retry` | all validators unreachable after internal retries |
| `NetworkCongested` | "Network congested — try again shortly" | `RetryAfter(5)` | validators returned busy |
| `WalletDrifted` | "Wallet state out of sync — heal required" | `Heal` | state mismatch detected |
| `DustAmount` | "Amount below minimum: {amount} < {dust}" | `Fatal` | amount < 500,000 atoms |

#### Recv errors

| Code | Message pattern | Recovery | When |
|---|---|---|---|
| `InboxEmpty` | "No new cheques" | — (not an error, returns empty vec) | no files in inbox/new/ |
| `MalformedCheque` | "Malformed cheque payload in inbox — skipped" | — (logged, file moved to cur/) | unparseable file |

Note: `recv()` is lenient. Malformed files are logged and skipped, not
thrown as errors. The return value is a list of successfully parsed
cheques. The developer checks if the list is empty.

#### Redeem errors

| Code | Message pattern | Recovery | When |
|---|---|---|---|
| `ChequeNotFound` | "Cheque {id} not found in pending" | `Fatal` | cheque_id doesn't exist |
| `ChequeNotReady` | "Cheque not mature yet — retry in {N} seconds" | `RetryAfter(N)` | §4.6 Timer B not elapsed |
| `ChequeRejected` | "Cheque rejected — sender flagged" | `Fatal` | sender BANNED or double-spend detected |
| `ChequeAlreadyRedeemed` | "Cheque already redeemed" | `Fatal` | dedup: already in redeemed store |
| `RedeemSuccess_RegistrationPending` | "Redeemed but network registration incomplete" | `CompleteRegistration` | k witnesses succeeded, post-redeem registration failed |
| `NetworkTimeout` | (same as send) | `Retry` | validators unreachable |
| `WalletDrifted` | (same as send) | `Heal` | state mismatch |

#### Heal errors

| Code | Message pattern | Recovery | When |
|---|---|---|---|
| `HealNotNeeded` | "Wallet is healthy — nothing to heal" | — (not an error) | no drift, no scars |
| `HealPartial` | "Healed {N} of {M} issues — retry for remaining" | `Retry` | some issues fixed, some remain |
| `HealFailed` | "Heal failed — network unreachable" | `RetryAfter(60)` | Nabla/validators unreachable during heal |

#### Wallet lifecycle errors

| Code | Message pattern | Recovery | When |
|---|---|---|---|
| `WalletAlreadyExists` | "Wallet already exists at {path}" | `Fatal` | directory exists on create |
| `WalletNotFound` | "No wallet at {path}" | `Fatal` | directory missing on open |
| `WalletLocked` | "Wallet locked by another process" | `RetryAfter(1)` | flock held |
| `WalletVersionMismatch` | "Wallet requires SDK version {X}, have {Y}" | `Fatal` | contract_version too new |
| `StorageError` | "Storage error: {detail}" | `Fatal` | disk full, permissions, etc. |
| `InternalError` | "Internal SDK error — please report" | `Fatal` | invariant violation (bug) |

### 8.4 Supplemental registration

When `send()` or `redeem()` returns with `registration: "pending"`, the
core transaction succeeded — the money moved, cheques are valid. But the
post-transaction Nabla register was interrupted (network glitch, lost
ACK on the return path, transient writer unavailability). The resulting
FACT link is scarred (`nabla_confirmation: None`) until a supplemental
register lands the confirmation.

The SDK persists the pending state in
`Wallet.pending_registrations: Vec<PendingRegistration>` — one entry per
scarred outbound TX. Each entry captures
`(txid, old_state, new_state, witness_sigs, is_genesis_claim,
created_at, attempts, last_attempt_at)` — enough to retry the register
without re-running the witness round.

**Auto-retry (default).** Every `send()`, `redeem()`, and `heal()`
sweeps the pending list **in chronological order (oldest first)** before
running its own logic. Each entry is retried; on success the entry is
dropped and the corresponding FACT chain link's `nabla_confirmation` is
populated. The sweep stops on first transient failure — later entries
cannot register before earlier ones (Nabla's SMT advances monotonically).
The caller's primary operation proceeds regardless of how many pending
entries remain after the sweep.

**Explicit retry.** Front-ends that detect a scarred link and want to
retry immediately can call:

```rust
wallet.complete_registration(txid)?;
```

This is an 11th public function (addition to the 10 in §4). It looks up
the matching pending entry, retries the register, and applies the result
the same way the auto-retry does.

**Lost-ACK recovery (idempotency).** Nabla's register handler is
**idempotent** for same-wallet same-txid retries when the SMT is already
at the claimed `new_state` (§17.9.4.3, fix in `nabla/src/registration.rs`).
This guarantees the auto-retry succeeds for the lost-ACK case (Nabla
committed but the ACK was lost in transit). For genuine state divergence
where Nabla has moved past via a *different* TX (rare; would require
malicious or independent state divergence), the retry returns
`StateMismatch[SMT_VS_REG]` and recovery is via `wallet.heal()`.

**Backoff schedule.** Per-entry exponential backoff (1s, 5s, 30s, 5m,
30m, then 1h cap) prevents hot-loop retries against a persistently-
failing Nabla. Throttled entries are skipped in the current sweep and
re-considered on the next cycle.

**The developer does not need to understand what "registration" means.**
They just know: pending registrations heal themselves on the next op,
or the front-end can poke them explicitly with `complete_registration`.

### 8.5 What the developer never sees

The following protocol concepts are **never exposed** in error codes,
messages, or the public API:

- Validators, validator IDs, validator selection
- Nabla, Nabla nodes, Nabla registration, Nabla queries
- S-ABR, overlap, witness accumulation, k-witness
- CLARA, TX_HEAL, attestation, garbage state
- FACT chain, scar, burn proof, supplemental registration details
- YPX-anything, Yellow Paper section numbers
- State ID, wallet sequence, consumed/produced state
- Reactive blacklist, poisoned committers

These concepts appear in SDK debug logs (gated behind a `debug` feature
flag) and in the `network_code` field of `SdkError` (for diagnostics).
They never appear in `code`, `message`, or `recovery`.

**If a developer reads an SDK error message and has to Google an AXIOM
protocol concept to understand it, that is a bug in the SDK.**

## 9. State versioning

The wallet state file includes a `sdk_version` and a `contract_version`:

- `sdk_version` — the SDK library semver that wrote this file. Used for
  migration (an older SDK may not understand a newer state file's fields).
- `contract_version` — the YP revision the SDK targets (e.g., "YP 2.11.15"
  or "YPX-020 r1"). Used to gate behavior on spec evolution — e.g., if a
  future YP revision changes the CLARA attestation format, the SDK knows
  whether to use the old or new format based on this field.

Opening a wallet with a newer contract_version than the SDK supports → SDK
refuses to open (explicit version mismatch error, not silent
miscompatibility).

## 10. Conformance

The SDK ships with a **conformance test suite** that any new client
implementation can run to verify behavior:

```
test_dedup_on_duplicate_delivery      — given 4 cheques for 1 txid, expect bundle of 3 distinct
test_retry_same_validator_on_timeout   — given slow V3, expect YPX-016 retry path
test_partial_witness_triggers_clara    — given ok_count=2, expect TX_HEAL + /clara + attestation
test_drift_triggers_resync             — given stale last_receipt, expect resync + retry
test_redeem_waits_on_timer_b           — given immature cheque, expect §4.6 WAIT
test_send_over_balance_rejects         — given amount > balance, expect ProtocolReject
test_concurrent_open_blocks            — given existing writer lock, expect Io::WouldBlock
```

These tests do not hit the network — they feed synthetic inbox files and
assert the SDK's behavior on state transitions and outbox writes. A Rust
SDK and a Python SDK binding (when it exists) must produce identical
outcomes for every test vector.

## 11. Language bindings (NORMATIVE)

The SDK is implemented in Rust. Language bindings are **permanent parts
of the SDK**, not temporary wrappers. Each binding exposes the same
public API surface (§4) in the target language's idiom.

### 11.1 Crate layout

```
axiom-sdk-core       Rust, no_std, pure logic, zero IO
    ↑
axiom-sdk            Rust, desktop defaults (FsStorage, DesktopPlatform, TcpNabla)
    ↑
axiom-sdk-python     PyO3 binding — `pip install axiom-sdk`
axiom-sdk-wasm       wasm-bindgen — `npm install @axiom/sdk`
axiom-sdk-c          cbindgen — axiom_sdk.h
axiom-sdk-uniffi     UniFFI — Swift + Kotlin
```

### 11.2 Python binding (PyO3)

The Python binding is the first binding and the most critical — it
enables incremental migration of PMC and the soak test harness.

**Migration strategy:** PMC's internal functions are replaced one at a
time with calls to `axiom_sdk`. The soak test never changes — it still
calls PMC functions (`wallet_mgr.create()`, etc.). PMC delegates to the
SDK internally. When every PMC function is replaced, PMC is a thin
Python wrapper around the SDK.

```python
# Developer usage (same API as Rust):
from axiom_sdk import App, Wallet

app = App.init("~/axiom")
wallet = Wallet.create("alice", "alice@axiom", app.wallets_dir)
wallet.send("bob@axiom", 10_000_000_000, k=3)
cheques = wallet.recv(app.maildir)
wallet.redeem(cheques[0].cheque_id)
wallet.close()
```

```python
# PMC migration (internal — soak test unchanged):
# pmc.py WalletManager.create() before:
#   signing_key = SigningKey(seed)
#   wallet = Wallet(name, private_key, public_key)
#   self._save_wallet(name)
#
# pmc.py WalletManager.create() after:
#   import axiom_sdk
#   axiom_sdk.wallet_create(name, email, self.data_dir)
```

### 11.3 Other bindings

| Binding | Target | Install | Status |
|---|---|---|---|
| Python (PyO3) | `pip install axiom-sdk` | PyPI | In progress |
| WASM (wasm-bindgen) | `npm install @axiom/sdk` | npm | Planned (webclient) |
| C ABI (cbindgen) | `#include <axiom_sdk.h>` | Header + .so/.dylib | Planned |
| Swift + Kotlin (UniFFI) | Swift Package / Maven | Package manager | Planned (mobile) |

Each binding is a first-class citizen of the SDK — tested, documented,
and released alongside the Rust crate. The Python binding is built and
tested as part of the standard CI pipeline.

## 12. Migration path

PMC is migrated to the SDK **one function at a time**:

1. SDK implements function N in Rust.
2. PyO3 binding exposes function N to Python.
3. PMC's function N calls `axiom_sdk.function_n()` internally.
4. Soak test runs — unchanged, still calls PMC.
5. If soak passes: old PMC implementation of function N is deleted.
6. Repeat for function N+1.

When all functions are migrated, PMC is a thin Python wrapper around
`axiom_sdk`. The soak test harness shrinks as protocol logic moves into
the SDK — only orchestration and chaos injection remain in Python.

**Migration order:**
1. `Wallet::create` + `open` + `close` + `balance`
2. `recv()`
3. `send()`
4. `redeem()`
5. `heal()`
6. `list_cheques()`, `history()`
7. `fund()` (genesis claim)

Each step is soak-tested before the next begins.

## 12. Resolved design decisions

1. **Language: Rust.** Compiles to native (desktop), WASM (browser),
   and mobile (iOS/Android via C ABI or UniFFI). One codebase, 6
   platforms. See §2.1.

2. **WASM size target: < 4 MB.** Feature-gate heal flow if needed.

3. **Raw/debug mode: yes, behind `debug` feature flag.** Adversarial
   testing needs payload mutation. Normal clients never see it.

4. **Nabla/validator routing: hidden behind Transport trait.** The
   developer never sees Nabla. The SDK calls Transport methods; the
   platform layer routes to the right place. See §2.1.1.

5. **Multi-wallet: one Wallet instance per wallet.** Multi-wallet is
   a front-end concern (open multiple instances).

6. **Async vs sync: sync core.** All IO goes through traits (§2.1.1).
   The trait methods are sync. Async consumers wrap the trait impls
   in their platform's async runtime — the SDK core doesn't care.

## 13. Open questions

1. **UniFFI vs cbindgen for mobile?** UniFFI generates Swift + Kotlin
   bindings automatically but adds a build dependency. cbindgen gives
   a C header that Swift/Kotlin can consume manually. Decision deferred
   to Step 11 of the implementation plan.

2. **Should `complete_registration` auto-retry on every operation?**
   **RESOLVED (2026-05-15):** yes — pending registrations are retried
   on next `send()`, `redeem()`, or `heal()` via the auto-sweep in §8.4.
   The explicit `complete_registration(txid)` exists for front-ends that
   want to retry immediately. Idempotency at the Nabla layer (§17.9.4.3)
   makes the auto-retry safe for the lost-ACK case. Spec'd normatively
   in §8.4 + YP main §17.9.4.3.

## 14. Non-goals

- **Not** a wallet UI framework. The SDK is a library; the UI is the
  front-end's job.
- **Not** a network stack. The SDK never opens sockets.
- **Not** a key management solution. Keys are in the encrypted wallet
  file; the front-end handles passwords.
- **Not** a protocol spec. The protocol is in the Yellow Paper; the SDK
  implements it. Any conflict is resolved by the Yellow Paper being
  authoritative.
- **Not** a replacement for PMC as a debugging tool. PMC's low-level
  protocol commands (inspect raw cheques, bypass heal, replay TXs) remain
  useful for development even after the SDK ships.

## 15. Summary

**The SDK is a filesystem-native wallet library with a 10-function public
surface and the entire client-side protocol state machine hidden inside.**

A front-end developer implements four things (inbox delivery, outbox
shipping, password UX, display) and calls SDK functions for everything
else. The SDK implements every client-side rule the Yellow Paper
specifies, tested to conformance, versioned to the spec, stable across
protocol evolution.

This closes the pattern we've been stuck in for 8+ days: every new client
re-discovers the protocol contracts by breaking things in production.
The SDK discovers them once, documents them in code, and hands them to
every future client for free.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
