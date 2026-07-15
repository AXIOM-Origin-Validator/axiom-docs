# YPX-008: Validator Status Protocol (VSP)

**Status:** FOLDED INTO THE YELLOW PAPER (2026-07-15). The number remains reserved;
code comments citing "YPX-008" refer to the section below.

The Validator Status Protocol — a free, unauthenticated, out-of-band query giving
clients a validator's public profile (proof capability, fee schedule, uptime,
encryption support) plus up to 3 peer referrals for bootstrap discovery — is now
specified in **`AXIOM_YellowPaper.md` §27.11 "Validator Status Protocol (VSP) —
formerly YPX-008"**, where it lives alongside the validator-hints mechanism (§27.5)
it complements.

The full spec moved without loss (overview and motivation, wire/IPC formats,
response fields, peer referrals, security considerations including the encrypted
cheque-delivery convention, and implementation notes). Implementation:
`ValidatorStatusRequest/Response` in `lambda/src/types.rs`,
`ConsensusEngine::validator_status()` in `lambda/src/consensus.rs`,
`discover_from_validator` in `sdk/client/src/discovery.rs`. The original
standalone text is in git history (this file, before 2026-07-15).

---

*Document history: initial public release 2026-07. From this release onward, every change to this document is recorded here and in the repository git log.*
