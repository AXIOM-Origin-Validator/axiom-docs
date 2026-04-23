# AXIOM Protocol — Document Repository

Official specification documents for the AXIOM protocol.

## Documents

| Document | Description |
|----------|-------------|
| [AXIOM White Paper](AXIOM_WhitePaper.md) | Architecture, threat model, economic design, and coercion resistance |

## Repository Structure

```
axiom-docs/
├── AXIOM_WhitePaper.md          # Living source — contributors edit here
├── genesis/                      # Signed initial release (frozen)
│   ├── AXIOM_WhitePaper_v2.28.pdf
│   ├── AXIOM_WhitePaper_v2.28.pdf.sig
│   └── axiom-origin.pub
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
gpg --verify genesis/AXIOM_WhitePaper_v2.28.pdf.sig genesis/AXIOM_WhitePaper_v2.28.pdf
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
