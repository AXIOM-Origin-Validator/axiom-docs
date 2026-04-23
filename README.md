# AXIOM Protocol — Document Repository

Official published documents for the AXIOM protocol.

## Documents

| Document | Description | Status |
|----------|-------------|--------|
| [AXIOM White Paper](pdf/AXIOM_WhitePaper.pdf) | Architecture, threat model, economic design, and coercion resistance | v2.28 |

- `pdf/` — published documents
- `sig/` — detached PGP signatures
- `src/` — markdown sources

## Verification

All documents are signed with the AXIOM Origin Validator PGP key.

**Fingerprint:**
```
029E 9BE8 569B 748A 1E75 8B38 86EF 3679 E216 16D8
```

To verify a document:

```bash
gpg --import axiom-origin.pub
gpg --verify sig/AXIOM_WhitePaper.pdf.sig pdf/AXIOM_WhitePaper.pdf
```

The public key is available from:
- This repository (`axiom-origin.pub`)
- [keys.openpgp.org](https://keys.openpgp.org)

## About AXIOM

AXIOM is a TrustMesh architecture for monetary settlement under adversarial conditions. Lambda is the protocol at its heart — the invariant rules that decide how value is witnessed, verified, and preserved. AXIOM is everything built around Lambda: the Core cryptographic engine, the ANTIE transport layer, the Nabla citizen infrastructure, and the economic model that sustains them.

- No global consensus
- No blockchain sequencing
- k=3 physical finality per transaction
- Post-quantum cryptographic stack (Ed25519 + Dilithium + SPHINCS+)
- Designed to persist when infrastructure, institutions, and assumptions fail

## License

Copyright AXIOM Project. All rights reserved.

## Links

- [AXIOM-Origin-Validator](https://github.com/AXIOM-Origin-Validator)
