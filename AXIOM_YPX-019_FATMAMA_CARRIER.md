# YPX-019: FATMAMA Carrier Scheme

**Version:** 0.2
**Status:** SUPERSEDED for production by TOT
(`docs/AXIOM_DESIGN_TOT.md`). The raw-TCP `length || CBOR` wire
format defined in §3-§4 below was the **original** production
design but was never built — the direct cluster client-intake role
moved to TOT (one port serving raw-TCP for native clients and
WebSocket for browser clients). The only currently-running
implementation under the FATMAMA name is the **SMTP-based dev tool**
`scripts/fatmama.py` (port 2525), retained because it drives ANTIE's
SMTP code path end-to-end in the dev env. The raw-TCP sections are
preserved here as the historical design record; the maildir-delivery
(§5) and validator-reply outbound (§6) sections still describe the
dev tool's behaviour accurately.
**Author:** AXIOM Origin
**Date:** 2026-05-16 (initial); 2026-05-20 (TOT supersession).
**Depends on:** Yellow Paper §27 (Validator Hints), §27.5.2 (Carrier URI Format)
**Related:** `docs/AXIOM_DESIGN_TOT.md` (supersedes the production
cluster-direct client-intake role); `docs/AXIOM_DESIGN_FATMAMA.md`
(current dev-tool implementation in `scripts/fatmama.py`).

---

## 1. Overview

> **Note (2026-05-20):** FATMAMA was originally the production
> direct-TCP cluster intake (§3-§4 below). That role is now **TOT**
> (`docs/AXIOM_DESIGN_TOT.md`) — one port serving raw-TCP for
> native clients and WebSocket for browsers. **The raw-TCP FATMAMA
> receiver described below was never built and will not be.** The
> only thing running under the FATMAMA name today is the
> SMTP-based dev tool (`scripts/fatmama.py`, port 2525), retained
> as a dev-env exerciser for ANTIE's SMTP code path. Sections
> 3-4 are historical record.

The FATMAMA carrier scheme defines a cluster-scoped, **inbound-only**
transport for AXIOM UMP envelopes. Validators advertise the scheme
in their `validator_hints[].carriers` array (per Yellow Paper §27.5.2)
using URIs of the form:

```
fatmama:<host>:<port>
```

A FATMAMA-protocol receiver running at `<host>:<port>` accepts direct
TCP connections from clients, parses the UMP envelope, and drops the
payload into the matching validator's `maildir/inbox/` for ANTIE to
pick up.

The scheme is intentionally narrower than `email:`. It is **not** a
general-purpose mail carrier; it is one half of a deliberately
asymmetric design.

### 1.1 Why a separate scheme?

`email:` covers everything mail-shaped — clients addressing a
validator via real email infrastructure, with all of SMTP's MX
lookups, queueing, retry semantics, and store-and-forward behaviour.
That works, but for clients talking to a known validator cluster
the overhead is unnecessary:

* DNS MX lookup adds round-trips even when the client already knows
  the host.
* SMTP envelope framing (`MAIL FROM` / `RCPT TO` / `DATA` /
  dot-stuffing) adds bytes the application doesn't need.
* SMTP server software brings its own queue management, retry
  schedule, and security surface.

A direct TCP carrier scoped to a single cluster cuts all of that.
The FATMAMA receiver is a single-purpose process that:

* Accepts a TCP connection.
* Reads one UMP envelope as length-prefixed bytes.
* Looks up the recipient address in its local routing table.
* Writes the message to the matching validator's `maildir/inbox/`.
* Closes the connection.

That is the entire protocol surface on the wire.

### 1.2 Relationship to `email:`

A validator MAY advertise both `email:alpha@axiom` and
`fatmama:<host>:<port>` simultaneously. Clients SHOULD prefer
`fatmama:` when the cluster is known to be reachable; `email:` is
the fallback when the cluster is not directly addressable (e.g.,
the client and validator are on different networks with no direct
TCP route).

The scheme order in `validator_hints[].carriers` reflects the
validator's preferred contact path, in line with the YP §27.5.2
"Clients SHOULD try carriers in order of preference" rule.

---

## 2. Directionality (NORMATIVE)

FATMAMA is **strictly asymmetric**.

| Direction | Carrier |
|---|---|
| Client → Validator | FATMAMA receiver at `fatmama:host:port` |
| Validator → Client | **Not FATMAMA.** ANTIE writes the reply to its local `maildir/outbox/`. Standard MTA infrastructure (`sendmail`, `postfix`, `qmail`, or equivalent) ships from the outbox via whatever transport the recipient's address resolves to. |

This asymmetry is deliberate:

* The inbound side is high-volume (every client of the cluster
  pushes TXs through it) and benefits from a dedicated lightweight
  receiver.
* The outbound side is low-volume (validators reply to k=3 clients
  per request) and benefits from leveraging standard mail
  infrastructure: per-recipient routing, retry policies, queue
  durability, security hardening, all already solved by the
  decades-old MTA ecosystem.

A conforming FATMAMA receiver **MUST NOT** open outbound connections
on behalf of a validator. Outbound mail flow is the MTA's domain,
not FATMAMA's.

ANTIE **MUST NOT** open SMTP connections to a FATMAMA receiver as
an outbound transport. ANTIE writes to `maildir/outbox/`; the MTA
takes responsibility from there.

---

## 3. URI Format (NORMATIVE)

```
fatmama:<host>:<port>
```

| Field | Type | Constraints |
|---|---|---|
| `<host>` | hostname or IPv4 / IPv6 literal | Must be reachable from clients that want to use this scheme |
| `<port>` | TCP port number | 1–65535 |

Examples:

```
fatmama:axiom-dev.mooo.com:2525
fatmama:fatmama.example.com:9100
fatmama:[2001:db8::1]:9100
```

There is no path component, no query string, no fragment. The
receiver listens on `<host>:<port>` for raw TCP connections.

---

## 4. Wire Format (NORMATIVE)

### 4.1 Frame shape

Each TCP connection carries **exactly one UMP envelope**. After
parsing, the receiver MUST close the connection. Long-lived
connections are not supported; clients MUST open a fresh connection
per envelope.

The wire format is length-prefixed:

```
+--------+--------+------------------------------------+
| length |  CBOR  | UMP envelope (CBOR-encoded bytes)  |
| (u32   |  body  | per AXIOM_DESIGN_PublicMailCarriers|
|  LE)   |        | §3 — Plain or Encrypted variant)   |
+--------+--------+------------------------------------+
```

* `length` is a 4-byte little-endian unsigned integer.
* `length` MUST equal the byte count of the UMP envelope that
  follows.
* The maximum permitted `length` is `2^24` (16 MiB) to bound the
  receiver's allocation. Frames larger than that MUST be rejected
  with the connection closed before reading the body.

### 4.2 No SMTP framing

A conforming FATMAMA receiver MUST NOT speak SMTP. There is no
`HELO`, no `MAIL FROM`, no `DATA`. Clients MUST NOT prepend any
mail header. The bytes on the wire are exactly `length || CBOR`.

This is what distinguishes `fatmama:` from `email:` at the
transport level — the receiver is purpose-built for AXIOM UMP, not
a general mail server.

### 4.3 Recipient resolution

The receiver derives the recipient validator from the UMP envelope's
`To` field after CBOR-decoding the outer frame. This is the same
field ANTIE would read from the `To:` header in an SMTP-delivered
message.

The receiver maintains a routing table mapping recipient identities
(typically `<name>@axiom` addresses, but any string the validator
configured) to `maildir/inbox/` paths on the local filesystem.
Receivers MUST be configurable in how this table is populated;
hot-reload (as in `scripts/fatmama.py`'s `routes.json` mtime watch)
is RECOMMENDED.

Unroutable recipients MUST be logged and dropped. The receiver
MUST NOT return a delivery-status notification — DSNs are a mail-
infrastructure concern, not a FATMAMA-protocol concern.

---

## 5. Maildir Delivery (NORMATIVE)

The receiver MUST follow the Maildir protocol (RFC 2822 / Bernstein
Maildir) when writing to `maildir/inbox/`:

1. Ensure `tmp/`, `new/`, and `cur/` subdirectories exist.
2. Generate a unique filename:
   `{unix_timestamp:.6f}.{pid}.{hostname}.{unique_id}`.
3. Write the message bytes to `maildir/inbox/tmp/<filename>`.
4. Atomically rename to `maildir/inbox/new/<filename>`.

The atomic rename is what guarantees ANTIE never observes a partial
message.

The receiver MAY add transport-layer metadata (e.g., a fictitious
`Received:` header) but MUST NOT modify the UMP envelope bytes
themselves. ANTIE reads the envelope; transport metadata is
informational only.

---

## 6. Outbound (Reference, NON-NORMATIVE)

This section describes the recommended **outbound** path for
validator replies. The path itself is not part of YPX-019 — it is
standard Unix mail infrastructure, recorded here so implementors
have a complete picture of the cluster shape.

```
ANTIE
  └── maildir/outbox/    ← ANTIE writes one file per reply
            │
            ▼
       sendmail / postfix / qmail
            │
            ▼
       transport_maps → per-recipient delivery
            │
   ┌────────┴────────┐
   ▼                 ▼
 local maildir    MX lookup + SMTP
 (cluster-local   to real internet
  recipients)
```

ANTIE's outbound responsibility ends at writing to
`maildir/outbox/new/`. The MTA picks up from there. Per-recipient
routing rules (which addresses are local-cluster, which are real-
email, what relay host to use, how to authenticate, retry schedule,
DSN handling) live entirely in the MTA's configuration.

The result: a single ANTIE binary works against any MTA. Swap
sendmail for postfix, point at a different relay host, add TLS —
zero ANTIE changes.

---

## 7. Implementations

### 7.1 `scripts/fatmama.py` (dev tool — current canonical implementation)

`scripts/fatmama.py` is the dev-time relay invoked by
`scripts/axiom-env.py`. **It is the only currently-running
implementation under the FATMAMA name** and is what `fatmama:`
carrier URIs in dev-environment seed lists resolve to.

It is **not** a raw-TCP §3-§4 implementation, and never was:

* It speaks SMTP on the inbound side (port 2525), not raw
  `length || CBOR`. This is intentional — the dev tool exercises
  ANTIE's SMTP code path so the production-shape `[outbound.smtp]`
  config is testable in dev.
* It also bidirectionally serves outbound mail (POP3 on 2527, HTTP
  pull) as a dev convenience. The original §3-§4 spec called for
  inbound-only; the dev tool's bidirectionality is a developer-
  experience shortcut.

The naming mismatch (a tool called "FATMAMA" that doesn't speak the
§4 FATMAMA wire format) is historical: when the dev tool was
written, a separate raw-TCP receiver was planned for production
(§7.2). Now that the production role has moved to TOT and the
raw-TCP receiver will never be built, the SMTP dev tool is what the
name FATMAMA denotes in practice. The design doc lives at
`docs/AXIOM_DESIGN_FATMAMA.md`.

Production deployments MUST NOT use `scripts/fatmama.py`. There is
no production FATMAMA receiver — cluster-direct client intake in
production is TOT.

### 7.2 Reference receiver (WILL NOT be built — superseded by TOT)

A reference raw-TCP YPX-019 receiver was on the roadmap when this
document was written. **It will not be built.** The production
direct-cluster client-intake role it was meant to fill is now TOT's
job (`docs/AXIOM_DESIGN_TOT.md` §5 — one port carrying both raw-TCP
for native clients and WebSocket for browsers, with a unified
intake state machine on the validator side). A separate raw-TCP-only
FATMAMA receiver would duplicate what TOT already does and add a
second cluster-intake surface to harden, monitor, and operate. TOT
is the single point of evolution for cluster-direct ingress.

The §4 wire format (`length || CBOR`) remains a useful design
artifact — TOT's raw-TCP intake reuses the same length-prefixed
framing decision, so the design notes here informed TOT even though
no FATMAMA-named binary will run them.

---

## 8. Security Considerations

### 8.1 Authentication

A conforming FATMAMA receiver does **not** authenticate the TCP
connection itself. Authentication of the **message** is the UMP
envelope's responsibility:

* The envelope is signed by the sending wallet's private key
  (Ed25519).
* The envelope's payload may be encrypted to the target validator's
  Ed25519→X25519 derived public key (`UmpEnvelope::Encrypted` per
  `AXIOM_DESIGN_PublicMailCarriers.md` §3.4).

The receiver MUST NOT attempt to authenticate or rate-limit by IP,
TLS client cert, or any other transport-level signal. Those would
add stateful security policy at the wrong layer — application-
layer signature verification in ANTIE is the authoritative check.

The receiver MAY implement transport-level rate limiting purely
for DoS resistance (e.g., max connections per second per source IP),
clearly framed as a resource-protection mechanism, not an
authentication boundary.

### 8.2 TLS

TLS at the FATMAMA layer is OPTIONAL. The UMP envelope already
provides payload confidentiality (when sealed to the validator's
key) and integrity (via the wallet signature). TLS adds:

* Metadata protection (passive observers can see that *some* wallet
  is talking to this cluster, but not which wallet or how much).
* Defence against active MITM that swaps the entire envelope (the
  signature would catch a tampered payload, but TLS prevents
  silent connection rerouting).

Production deployments SHOULD offer TLS. Dev deployments MAY skip
it.

### 8.3 Routing table integrity

The receiver's routing table (recipient → maildir path mapping)
is operator-controlled out-of-band. If an attacker can mutate the
routing table, they can redirect inbound mail. Standard filesystem
ACLs apply.

The dev tool's `XAXIOM-REGISTER` SMTP verb (which lets unauthenticated
clients add routes) MUST NOT be honoured by YPX-019 receivers in
production mode. The dev tool gates it behind a `--mode=production`
flag; a YPX-019 reference receiver would not implement the verb at
all.

---

## 9. References

* Yellow Paper §27.5 — Validator Hints (carrier-list shape).
* Yellow Paper §27.5.2 — Carrier URI Format (per-scheme table).
* `docs/AXIOM_DESIGN_FATMAMA.md` — dev-tool implementation
  (`scripts/fatmama.py`).
* `docs/AXIOM_DESIGN_PublicMailCarriers.md` — UMP envelope shape
  (the bytes on the wire after the length prefix).
* RFC 2822 / Bernstein Maildir — Maildir delivery protocol.

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
