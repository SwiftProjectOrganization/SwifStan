# SwiftStan

1. A macOS / Xcode / Swift CLI wrapping Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/).

2. An experimental port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

Documentation lives in [`Docs/`](Docs/):

- [`Docs/README.md`](Docs/README.md) — overview, supported functionality, setup, usage, help screens, and the ulam DSL.
- [`Docs/UlamManual.md`](Docs/UlamManual.md) — ulam manual using `stancode`.
- [`Docs/DSLManual.md`](Docs/DSLManual.md) — ulam manual via the Swift/DSL pipeline (`alist2dsl` → `dsl2stan`).
- [`Docs/TODO.md`](Docs/TODO.md) — forward-looking list of possible future work/refinements to do.[](()
- [`Docs/CLAUDE.md`](Docs/CLAUDE.md) — architecture notes (loaded by Claude Code sessions in this workspace).

As the last item indicates, the ulam port is being worked on using Claude.
