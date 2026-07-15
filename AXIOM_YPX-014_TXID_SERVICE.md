# AXIOM YPX-014: Nabla Txid Service

**Status:** SUPERSEDED by YPX-018 (2026-04-10). The number remains reserved; code
comments citing "YPX-014" refer to the design summarized below.
**Version:** 1.0 (frozen) · **Date:** 2026-04-07 · **Author:** AXIOM Origin

YPX-014 specified cross-validator double-redeem prevention via a **single 18 MB
monolithic bloom filter** per Nabla node over all redeemed txids in the network's
history, with an optional authoritative HashMap mode, a client-carried signed
`NablaTxidAttestation`, and cross-node txid gossip.

The single-bloom storage shape was fatally flawed: it saturates at ~10 M txids and
its compounding false-positive rate silently destroys user funds (a false "already
redeemed" answer permanently rejects a legitimate cheque). The protocol shape was
right and survives: the signed-attestation pattern (client fetches, Lambda verifies
via Core CL5, extended in YPX-018 §4.6 with era and three-state status
`NotRedeemed | Redeemed | PhasedOut`), the bloom primitive (now per-quarter eras),
and the operator-tier idea all live on in YPX-018 and in code
(`core/logic/src/nabla_wire.rs`, `core/logic/src/cl5_inputs.rs`,
`nabla/src/bloom_era.rs`). No data migration was required — AXIOM had not released.

**The full design history — what this document proposed, why it looked right, the
saturation math that broke it, and what survived — is preserved for readers in
`AXIOM_YPX-018_HEAL_AND_TIERED_MEMORY.md` §1.3.** The frozen original text of this
document is in git history (this file, before 2026-07-15).

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
