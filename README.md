# AXIOM Protocol — Document Repository

Official specification documents for the AXIOM protocol.

## Documents

| Document | Description |
|----------|-------------|
| [AXIOM White Paper](AXIOM_WhitePaper.md) | Architecture, threat model, economic design, and coercion resistance |
| [AXIOM Yellow Paper](AXIOM_YellowPaper.md) | Full protocol specification — the normative reference |
| [Yellow Paper: Errors](AXIOM_YellowPaper_Errors.md) | Error taxonomy companion volume |
| [Yellow Paper: SDK](AXIOM_YellowPaper_SDK.md) | Wallet/SDK behavior companion volume |

## Yellow Paper Extensions (YPX)

The base protocol is extended by numbered YPX documents (`AXIOM_YPX-*.md`), each
the normative source for one subsystem: FACT provenance (001), Nabla verification
(002), TARDIS heartbeat (003), DMAP attestation (006), receiver-defined security
tiers (007), Silicon Pulse audit (009), Ark Confidence Index (010), genesis
integrity (011), oracle distribution (012), Console engine (013), CLARA & tiered
bloom memory (018), HAL resurrection (020), OODS (021), RECALL (022), and more.

**Start with the registry**: Yellow Paper §28.2 is the authoritative map of every
YPX number — including retired numbers and where their content lives today.
Retired/folded numbers keep a stub file so citations always resolve.

## Repository Structure

```
axiom-docs/
├── AXIOM_WhitePaper.md          # Living sources — contributors edit here
├── AXIOM_YellowPaper.md
├── AXIOM_YellowPaper_Errors.md
├── AXIOM_YellowPaper_SDK.md
├── genesis/                      # Signed initial release (frozen)
│   ├── axiom-origin.pub
│   ├── AXIOM_WhitePaper_v2.28.pdf
│   └── sig/
│       └── AXIOM_WhitePaper_v2.28.pdf.sig
└── latex/                        # Build tooling for local PDF generation
    ├── Makefile
    ├── axiom-paper.cls
    └── axiom-template.latex
```

- **Root** — living markdown sources. This is the source of truth.
- **genesis/** — the signed initial publication. Frozen. Will not change.
- **latex/** — LaTeX class and template for local PDF builds.

## Genesis Verification

The `genesis/` directory contains the original signed release of each document. These are historical artifacts — the cryptographic proof of what was published at launch.

**PGP Fingerprint:**
```
029E 9BE8 569B 748A 1E75 8B38 86EF 3679 E216 16D8
```

```bash
gpg --import genesis/axiom-origin.pub
gpg --verify genesis/sig/AXIOM_WhitePaper_v2.28.pdf.sig genesis/AXIOM_WhitePaper_v2.28.pdf
```

## Building PDFs Locally

```bash
cd latex
make whitepaper
```

Requires: `texlive-xetex`, `texlive-latex-extra`, `texlive-fonts-recommended`, `pandoc`

## About AXIOM

AXIOM is a TrustMesh architecture for monetary settlement under adversarial conditions. Lambda is the protocol at its heart — the invariant rules that decide how value is witnessed, verified, and preserved. AXIOM is everything built around Lambda: the Core cryptographic engine, the ANTIE transport layer, the Nabla citizen infrastructure, and the economic model that sustains them.

## Links

- [AXIOM-Origin-Validator](https://github.com/AXIOM-Origin-Validator)
