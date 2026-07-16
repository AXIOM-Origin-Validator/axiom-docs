# Why the Names

I should write this down before I forget why I picked any of it.

## AXIØM

An axiom is something you don't prove. You start there. The whole protocol rests on one claim — that money can move between people without someone in the middle holding it for them — and the name should carry that.

The Ø is the empty set. *Nothing here.* I put it in the middle of the word because that's where the bank used to be. The custodian, the exchange, the trusted third party — gone. The Ø is the shape of their absence. Every time I see the wordmark, the missing piece is the part doing the work.

It also makes the name unmistakable. There are a lot of things called Axiom. There's only one AXIØM.

## Core

Core is the law. Signs, verifies, attests, doesn't bargain. Lives in a sandbox on the user's own machine, keys never leave. *Can crash, must not lie* — the most honest promise software can make. Not "I'll always work." Just "when I work, I'm telling you the truth."

Austere names only in here. Production code that compiles to ELF doesn't need personality. The law shouldn't be funny.

## Lambda

Where the validators argue and eventually agree. λ-calculus, because Lambda is where decisions actually get *evaluated* in the computer-science sense — functions applied, arguments resolved, results returned. Core is the law. Lambda is the courtroom. Same rules, different room.

## Nabla

The one I enjoyed picking.

∇ is an upside-down delta. In maths it's the operator for how things change across space — gradients, flow, where the current runs, where density piles up. It watches money move across the network and records the shape of the flow. So: nabla.

The second reason is the one I actually like. Delta is *change*. Nabla is the thing that watches change and makes sense of it. Lambda handles the individual deltas — every transaction, every yes-or-no. Nabla sits one layer up and integrates. The inverted delta is a quiet way of saying *I am the layer above the layer that handles change.* Most people won't notice. That's fine. I notice.

And Nabla isn't a ledger. It's a web of truth gossiped through the protocol. Nodes whisper what they've witnessed to their neighbours, the neighbours whisper onwards, and out of all that whispering a shared record settles into shape. No central scribe. No master copy. Just the network telling itself what happened until the story stops changing.

Which is why the Doctor's line keeps coming back to me:

> *"People assume that time is a strict progression of cause to effect, but actually from a non-linear, non-subjective viewpoint — it's more like a big ball of wibbly wobbly… timey wimey… stuff."*

That is, almost word for word, the design brief. A blockchain insists time is a strict progression of cause to effect — block N, then block N+1, single file, no exceptions. Nabla doesn't. Settlement is non-linear. Truth arrives out of order, from multiple directions, and the protocol's job is to weave it into something coherent without pretending the arrival was tidy. Wibbly. Wobbly. Timey-wimey. The Doctor got there first.

## Doctor Who

Once you've accepted that Nabla's job is to remember the past correctly, catch anyone trying to rewrite it, and put timelines back together when they split — Doctor Who names start naming themselves.

**TARDIS** — *Temporal Anchor for Rollback Detection and Integrity Sync*. Yes, the acronym is reverse-engineered. It holds time. It's bigger on the inside than the outside. It survives things that should kill it. The first time the chaos test killed every genesis node and the tree kept going, the name was already right.

The rest follow from there — anything in Nabla that handles memory, paradox, or reconciliation across forks gets a name from the canon. They're not jokes. They're mnemonics for components whose job is temporal integrity. The key ones:

**CLARA** — *Client-Led Attested Reality Alignment*. The heal process for a wallet that has fallen out of sync with its validators. Named for the companion who goes back through the Doctor's own timestream to save him, repairing every broken moment — which is exactly the job.

**JUDOON** — *Judgment Upon Divergent Or Offending Nablas*. The pool quarantine. The Judoon are the blunt, procedural police-for-hire of the canon — exactly the register for the mechanism that isolates a misbehaving node until it proves itself again.

**OODS** — *Operational Observer Determination System*. The Ood share a single collective consciousness, and an Ood severed from it *knows* it has been cut off. OODS is the mesh analogue: every node carries a piece of a shared sense of the collective's size, so a partitioned or eclipsed node detects that its own estimate has collapsed.

Doctor Who specifically, over other time-travel stories, because Doctor Who is *optimistic* about time. Things that go wrong can be set right. Histories that diverge can be rewoven. That's the posture Nabla needs. Not "we prevent paradoxes" — "we resolve them."

## FACT — one acronym, two expansions (deliberate)

FACT is spelled out two ways, on purpose, and both are correct.

Canonically it's **Financial Audit Chain of Trust**: every coin carries its
provenance from genesis, and the chain is the audit trail. That's the expansion
the protocol uses — spec (`AXIOM_YPX-001_FACT_TARDIS.md`), Yellow Paper, and the
academic paper. If you're inside the system, that's the name.

The second expansion is **Forensic Audit Chain for Transactions**, and it exists
only for bank-facing / UNCLE material. "Forensic" and "transactions" are the
words a compliance officer already trusts; "Financial ... Chain of Trust" reads
like marketing to that audience, and "provenance from genesis" reads like a
whitepaper. Same mechanism, same acronym — the register just changes with the
room. Protocol and academic docs use *Financial Audit Chain of Trust*;
UNCLE/institutional docs may use *Forensic Audit Chain for Transactions*.

This is deliberate, not a contradiction to reconcile. If you find one expansion
in the spec and the other in UNCLE material, that's the design — do not
"correct" one to match the other.

## CC — Companion Certificate

Nabla doesn't run itself. The tree needs nodes, the nodes need operators, and the operators need a reason to keep their machines on. So Nabla rewards them. The reward is called **CC** — Companion Certificate.

The name follows from the rest. The Doctor doesn't travel alone. Nobody who watches the show would say the Doctor *could* travel alone — the companion is half the point. The Doctor without a companion is just a brilliant lonely person rattling around in a blue box; with one, the show works. Nabla is the same. The protocol can be as elegantly designed as I can make it, but without people running nodes, it's just code on a hard drive somewhere. The operators are what turn it into a living network.

Calling the credit a *certificate* matters more than calling it a *token*. A token is something you trade. A certificate is something you earn and something that says *you were here, you helped, this happened because of you*. Operators aren't liquidity providers. They're not yield farmers. They're citizens of a project that needs them, and CC is the receipt for that citizenship. You held a Nabla node up. The world used it. Here is the record.

This is also the part of AXIØM I'm most stubborn about being a *social* design and not a *financial* one. Nabla is a citizen project. It runs because people choose to run it, and the protocol's job is to honour that choice — not to financialise it into something unrecognisable. CC is small, deliberate, and named after the most human role in the entire mythology. The Doctor needs a companion. So does the protocol.

## ANTIE, UNCLE, COUSIN

The transport layer. Components that carry messages between Cores — email, banking, general protocol bridges. Named after extended family because that's what they are. Relatives at varying distances, each handling a different kind of correspondence. ANTIE for the everyday mail. UNCLE for the banks. COUSIN for whatever else turns up.

UNCLE is also Uncle Sam, which is the joke I'm proudest of in the whole naming scheme. The component that talks to SWIFT, the component that bridges to the dollar rails, the component that has to put on a tie and speak to the banking system in its own language — named after the figure who *is* the banking system, pointing at you from the poster. The relative you only call when something formal needs doing happens to also be the relative who sends the tax bill. Two readings, same name, both true.

SAM — the client half of UNCLE SAM, the desktop app the banks actually run — has
two expansions that co-exist: **SWIFT-Aligned Messaging** and **Settlement Anchor
Mediator**. That is not ambiguity, it is precision: the client plays exactly those
two roles. On one side it speaks the bank's own SWIFT-shaped messaging; on the
other it anchors and mediates AXIOM settlement. Same pattern as FACT's two
registers — the name doesn't change, the reading follows the role.

Not deep. Made me smile. Enough.

## Why I'm Bothering

Honestly — AXIØM isn't mostly a cryptography project. The cryptography is necessary, not the point. The point is social. What happens when you stop asking people to trust an institution and start letting them trust mathematics they could, in principle, verify themselves. Whether the relationship between a person and their money has to involve a third party who can freeze it, lose it, or be subpoenaed for it. I think the answer is no. I've spent a long time trying to prove it.

The names are part of that. A system that takes itself too seriously becomes priestly — only the initiated understand it, only the experts get to interpret it. That's the exact dynamic AXIØM is trying to undo. So the names lean human. Doctor Who is in here because Doctor Who is fun, and a system that removes the bank from the picture should feel like it was built by a person, not handed down by a council of cryptographers.

If anyone reads this far, they probably get it.

---

*Document history: initial public release 2026-07; 2026-07 — added the key Nabla names (CLARA, JUDOON, OODS) with their canonical expansions. Every change to this document is recorded here and in the repository git log.*
