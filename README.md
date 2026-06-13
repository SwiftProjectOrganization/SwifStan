# SwiftStan

1. A macOS / Xcode / Swift CLI wrapping Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/).

2. An experimental port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

3. As an "experiment within an experiment", and for me to further my understanding of the mapping back-and-forth between alternate ways of expressing Stan Language Programs, I asked Claude to plan and implement a reverse mapping from a .stan file to an .alist.r file. See sections 2.2 and 5.2 in Docs/UlamManual.md.

Documentation lives in [`Docs/`](Docs/):

- [`Docs/README.md`](Docs/README.md) — Overview, supported functionality, setup and usage.
- [`Docs/UlamManual.md`](Docs/UlamManual.md) — Ulam pipeline manual (`stancode` → `csv2json` → `CMDSTAN`).
- [`Docs/DSLManual.md`](Docs/DSLManual.md) — Swift+DSL pipeline (`alist2dsl` → `dsl2stan` → `csv2json` → `CMDSTAN`).
- [`Docs/TODO.md`](Docs/TODO.md) — Future work items.
- [`Docs/CLAUDE.md`](Docs/CLAUDE.md) — Guidance for Claude.

As the last item indicates, the ulam port is being worked on using Claude.
