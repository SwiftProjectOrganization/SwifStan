//
//  DataInference.swift
//  Stan
//
//  Phase 1 of the ulam port: walk the AST + data dict to decide which
//  symbols are data vs parameter vs derived, and determine the common
//  vector length N.
//

import Foundation

struct InferredModel {
  /// Vector columns referenced by the model (sorted by name for stable output).
  let dataVectors: [(name: String, column: UlamColumn)]
  /// Scalar columns referenced by the model.
  let dataScalars: [(name: String, column: UlamColumn)]
  /// LHS of every Prior — emitted in `parameters {}`.
  let parameters: [String]
  /// LHS of every Link / Deterministic — emitted as local vectors in `model {}`.
  let derived: [String]
  /// Common vector length (Stan's `N`). Nil if no vector data is referenced.
  let N: Int?
  /// Phase 4: parameter-declaration constraint suffix derived from any
  /// truncation on the symbol's Prior. Empty string when unconstrained.
  let parameterConstraints: [String: String]
  /// Phase 4: outcome-array bound constraint for each integer-vector
  /// data symbol that appears as the LHS of a discrete likelihood.
  let outcomeBoundsByLhs: [String: DistributionCatalog.OutcomeBounds]
  /// Phase 5: parameter name → cardinality symbol (e.g. `"N_group"`
  /// auto-derived or `"K"` user-override). Parameters in this map are
  /// emitted as `vector[<countSymbol>] <name>;` rather than scalar
  /// `real <name>;`.
  let vectorParameters: [String: String]
  /// Phase 5: integer data column → cardinality symbol. Drives the
  /// auxiliary `int<lower=1> <countSymbol>;` declaration and the
  /// tightened `<lower=1, upper=<countSymbol>>` constraint on the
  /// column.
  let indexColumns: [String: String]
  /// Phase 6: cardinality symbol → numeric length for VectorPrior-
  /// introduced symbols (e.g. `["K": 2]`). Emitted as
  /// `int<lower=1> <symbol>;` in the data block and as
  /// `<symbol>: <length>` in the data JSON.
  let phaseSixCardinalitySymbols: [String: Int]
  /// Phase 6: Phase-6-shaped data column name → cardinality symbol
  /// it's keyed on. Drives the per-column declaration shape:
  /// `.realVector` → `vector[<symbol>] <col>;`,
  /// `.realCovMatrix` → `cov_matrix[<symbol>] <col>;`,
  /// `.realArrayVector` → `array[N] vector[<symbol>] <col>;`.
  let phaseSixColumnSymbols: [String: String]
  /// Phase 5.5 Slice C: integer data columns that the inference pass
  /// promoted from `array[N] int <col>;` → `vector[N] <col>;` because
  /// they appear as a direct operand of `*` or `/` in some
  /// Link/Deterministic RHS. Index columns are excluded — Stan
  /// requires the array-int form for subscripts. DataMarshaller
  /// emits these as JSON arrays of floats so Stan accepts them as
  /// a vector.
  let promotedIntColumns: Set<String>
  /// Phase 5.5 Slice E: original-name → spec for each VaryingPrior
  /// flagged `nonCentered: true`. BlockEmitter declares `<rawName>`
  /// in `parameters {}`, emits a `transformed parameters {}` block
  /// that defines `<name> = mu + sigma * <rawName>;`, and swaps the
  /// centred sampling line for `<rawName> ~ std_normal();`.
  let nonCenteredVarying: [String: NonCenteredSpec]
  /// SUR Slice A: parameter name → (rows-symbol, cols-symbol) for
  /// every `MatrixPrior`. BlockEmitter declares
  /// `matrix[<rows>, <cols>] <name>;` in `parameters {}` and emits
  /// the iid prior via `to_vector(<name>) ~ <dist>(args);`.
  let matrixParameters: [String: (rows: String, cols: String)]
  /// SUR Slice B: parameter name → cardinality symbol for every
  /// `CovMatrixPrior`. BlockEmitter declares
  /// `cov_matrix[<dim>] <name>;` in `parameters {}` and emits no
  /// explicit prior — Stan's positive-definite constraint suffices.
  let covMatrixParameters: [String: String]
  /// Multivariate hierarchical priors Slice A: parameter name →
  /// cardinality symbol for every `LKJCorrCholeskyPrior`. BlockEmitter
  /// declares `cholesky_factor_corr[<dim>] <name>;` in `parameters {}`
  /// and emits `<name> ~ lkj_corr_cholesky(<eta>);` in the model block.
  let cholFactorParameters: [String: String]
  /// Wishart scale-matrix columns: data column name → the `dim`
  /// cardinality symbol of the companion `WishartPrior`. BlockEmitter
  /// emits `cov_matrix[<dim>] <name>;` for each entry in the data block.
  let wishartScaleColumns: [String: String]
  /// Multivariate hierarchical priors Slice C: parameter name →
  /// (outer-array cardinality symbol, inner-vector length symbol) for
  /// every `VaryingVectorPrior`. BlockEmitter declares
  /// `array[<outer>] vector[<length>] <name>;` in `parameters {}` and
  /// emits the sampling line at the scalar form — Stan vectorises the
  /// `~` operator over the outer array automatically.
  let varyingVectorParameters: [String: (outer: String, length: String)]
  /// Ordered logit / probit (2026-06-02): cutpoints parameter name → K
  /// cardinality symbol. BlockEmitter declares `ordered[<K>-1] <name>;`
  /// in `parameters {}`. The user supplies a separate `Prior(<name>, …)`
  /// to give the iid prior across the K-1 cutpoint values.
  let orderedCutpointParameters: [String: String]
  /// Monotonic effects (2026-06-02): simplex parameter name → length
  /// cardinality symbol. BlockEmitter declares `simplex[<length>] <name>;`
  /// in `parameters {}`. Pair with a `Prior(<name>, .dirichlet(<alpha>))`
  /// for the iid prior across the simplex entries.
  let simplexParameters: [String: String]
  /// Monotonic effects: per-effect spec consumed by BlockEmitter's
  /// `detectMonotonicLoops` pass to fold a matching Link/Deterministic
  /// into a single combined per-row for-loop in the model block.
  let monotonicEffects: [MonotonicSpec]
  /// Gaussian process priors (2026-06-01): latent-name → spec for every
  /// `GaussianProcessPrior`. BlockEmitter declares `<name>` in
  /// `transformed parameters {}` (built from `<rawName>` z-scores plus
  /// the cholesky-decomposed kernel matrix), declares `<rawName>` in
  /// `parameters {}`, and emits `<rawName> ~ std_normal();` in the
  /// model block. Same role as `nonCenteredVarying` but extended with
  /// the kernel-construction spec.
  let gaussianProcessGP: [String: GPSpec]
  /// Data columns the GP code-gen needs emitted as `matrix[N, N]`
  /// instead of `matrix[N, <cols-literal>]`. Populated from each
  /// `GaussianProcessPrior`'s `distanceMatrix` symbol.
  let squareMatrixColumns: Set<String>
  /// User-supplied NUTS warmup inits (2026-06-02). Collected from any
  /// `.inits(...)` statements (last-write-wins on duplicate keys). The
  /// pipeline marshals these into `Results/<model>.init.json`; cmdstan
  /// auto-picks the file up via the `init=<path>` flag.
  let initValues: [String: Double]
}

/// Monotonic effect spec (2026-06-02): per-`MonotonicEffect`
/// bookkeeping. BlockEmitter's detection pass pairs each entry with the
/// Link/Deterministic whose LHS is `targetLhs` and emits one combined
/// per-row for-loop replacing the original vectorised assignment.
struct MonotonicSpec: Hashable, Sendable {
  let name: String           // simplex parameter ("delta")
  let scale: String          // effect-scale parameter ("bE")
  let predictor: String      // ordinal integer data column ("edu")
  let levels: String         // simplex length cardinality symbol ("K_edu")
  let targetLhs: String      // Link/Deterministic LHS we augment ("mu")
}

/// Gaussian process spec (2026-06-01): per-`GaussianProcessPrior`
/// bookkeeping used by BlockEmitter to build the `transformed parameters`
/// block (`vector[N] <name>;` plus the K-matrix construction and the
/// `<name> = cholesky_decompose(K) * <rawName>;` assignment) and the
/// `<rawName> ~ std_normal();` model-block prior.
struct GPSpec: Hashable, Sendable {
  let rawName: String           // "<name>_z"
  let countSymbol: String       // "N"  (v1 hard-codes to the global row count)
  let distanceMatrix: String    // e.g. "Dmat"
  let etasq: DistributionArg
  let rhosq: DistributionArg
  let jitter: Double
}

/// Phase 5.5 Slice E: per-VaryingPrior bookkeeping for the Matt
/// Trick non-centred form.
struct NonCenteredSpec: Hashable, Sendable {
  let rawName: String
  let countSymbol: String
  let muArg: DistributionArg
  let sigmaArg: DistributionArg
}

enum DataInferenceError: Error, CustomStringConvertible {
  case mismatchedVectorLengths([(String, Int)])
  case undeclaredSymbol(String)
  case conflictingParameterConstraints(name: String)
  case conflictingVaryingPriorCardinality(name: String)
  case conflictingIndexColumnCardinality(column: String)
  case parameterIsBothScalarAndVarying(name: String)
  case unboundCardinalitySymbol(symbol: String)
  case multivariateTruncationUnsupported(symbol: String)
  case multipleCardinalitySymbolsAmbiguous([String])
  case cardinalityLengthMismatch(symbol: String, expected: Int, column: String, found: Int)
  case nonCenteredRequiresNormal(name: String)
  case nonCenteredWithTruncationUnsupported(name: String)
  case nonCenteredWithLpdfUnsupported(name: String)
  case constraintsConflictWithTruncation(name: String)
  case nestedVaryingPriorArity(name: String, got: Int)

  var description: String {
    switch self {
    case .mismatchedVectorLengths(let pairs):
      let parts = pairs.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
      return "ulam: data vectors have inconsistent lengths: \(parts)"
    case .undeclaredSymbol(let s):
      return "ulam: symbol '\(s)' is referenced but not declared as data or parameter"
    case .conflictingParameterConstraints(let name):
      return "ulam: parameter '\(name)' has multiple priors with conflicting truncations"
    case .conflictingVaryingPriorCardinality(let name):
      return "ulam: vector parameter '\(name)' has multiple VaryingPriors with disagreeing cardinality symbols"
    case .conflictingIndexColumnCardinality(let column):
      return "ulam: index column '\(column)' is referenced by VaryingPriors with disagreeing cardinality symbols"
    case .parameterIsBothScalarAndVarying(let name):
      return "ulam: '\(name)' is declared as both a scalar Prior and a VaryingPrior — pick one"
    case .unboundCardinalitySymbol(let symbol):
      return "ulam: VectorPrior cardinality symbol '\(symbol)' isn't bound by any Phase-6 data column (vector / cov_matrix / array-of-vectors)"
    case .multivariateTruncationUnsupported(let symbol):
      return "ulam: '\(symbol)' uses a multivariate distribution with truncation — Stan's `T[...]` syntax only supports univariate distributions"
    case .multipleCardinalitySymbolsAmbiguous(let symbols):
      return "ulam: model declares multiple Phase-6 cardinality symbols (\(symbols.joined(separator: ", "))) — v1 supports a single symbol per model; bind each Phase-6 column to one symbol via VectorPrior(length:) once"
    case .cardinalityLengthMismatch(let symbol, let expected, let column, let found):
      return "ulam: column '\(column)' has length \(found) but cardinality symbol '\(symbol)' is bound to \(expected)"
    case .nonCenteredRequiresNormal(let name):
      return "ulam: VaryingPrior '\(name)' has nonCentered: true but its distribution isn't normal — the Matt Trick non-centred form is only defined for `normal(mu, sigma)`"
    case .nonCenteredWithTruncationUnsupported(let name):
      return "ulam: VaryingPrior '\(name)' combines nonCentered: true with a truncation — Stan's truncation auto-normalisation doesn't compose cleanly with the standard-normal raw form"
    case .nonCenteredWithLpdfUnsupported(let name):
      return "ulam: VaryingPrior '\(name)' combines nonCentered: true with useLpdf: true — the non-centred form requires the `~` sampling syntax on `<name>_raw`"
    case .constraintsConflictWithTruncation(let name):
      return "ulam: '\(name)' has both `constraints:` and `truncation:` set — pick one. `truncation:` already drives the parameter declaration constraint; `constraints:` exists for the case where you want the declaration constraint WITHOUT the redundant `T[…]` sampling suffix."
    case .nestedVaryingPriorArity(let name, let got):
      return "ulam: NestedVaryingPrior '\(name)' has indexedBy.count == \(got); v1 supports exactly two grouping dimensions"
    }
  }
}

enum DataInference {
  static func classify(_ model: UlamModel) throws -> InferredModel {
    var parameters: [String] = []
    var derived: [String] = []
    var referenced: Set<String> = []
    // Phase 4: tracked per-symbol while walking statements.
    var parameterTruncationByName: [String: Truncation] = [:]
    var outcomeBoundsByLhs: [String: DistributionCatalog.OutcomeBounds] = [:]
    // Phase 5: vector-typed parameters and the integer columns they index.
    var vectorParameters: [String: String] = [:]
    var indexColumns: [String: String] = [:]
    var scalarPriorNames: Set<String> = []
    var varyingPriorNames: Set<String> = []
    // Phase 6: cardinality symbols declared via VectorPrior(length:).
    // After the statement walk, each Phase-6 data column is bound to
    // the (single, in v1) declared symbol and its numeric length is
    // recorded.
    var phaseSixSymbolsDeclared: Set<String> = []
    // Phase 5.5 Slice E: per-name spec for non-centred VaryingPriors.
    // Populated during the statement walk; consumed by BlockEmitter to
    // emit the `transformed parameters` block + the `_raw ~ std_normal()`
    // sampling line.
    var nonCenteredVarying: [String: NonCenteredSpec] = [:]
    // SUR Slices A + B: matrix- and cov_matrix-typed parameter
    // bookkeeping. Filled during the statement walk; consumed by
    // BlockEmitter.parametersBlock for declarations and modelBlock for
    // the `to_vector(name) ~ dist(args);` prior (matrix only).
    var matrixParameters: [String: (rows: String, cols: String)] = [:]
    var covMatrixParameters: [String: String] = [:]
    // Wishart scale-matrix columns: realCovMatrix data columns used as
    // the `V` arg of a WishartPrior. Excluded from Phase-6 cardinality
    // binding — they're pure data inputs, not cardinality anchors.
    // Maps column name → dim cardinality symbol from the WishartPrior.
    var wishartScaleColumns: Set<String> = []
    var wishartScaleColumnDims: [String: String] = [:]
    // Multivariate hierarchical priors Slice A: cholesky_factor_corr
    // parameter bookkeeping. Filled during the statement walk; consumed
    // by BlockEmitter.parametersBlock for declarations and modelBlock
    // for the `name ~ lkj_corr_cholesky(eta);` sampling line.
    var cholFactorParameters: [String: String] = [:]
    // Multivariate hierarchical priors Slice C: VaryingVectorPrior
    // bookkeeping. Each entry pairs the outer-array cardinality (the
    // group-count symbol from `indexedBy`) with the inner-vector
    // length symbol.
    var varyingVectorParameters: [String: (outer: String, length: String)] = [:]
    // Gaussian process priors (2026-06-01).
    var gaussianProcessGP: [String: GPSpec] = [:]
    var squareMatrixColumns: Set<String> = []
    // Ordered logit / probit (2026-06-02).
    var orderedCutpointParameters: [String: String] = [:]
    // Monotonic effects (2026-06-02).
    var simplexParameters: [String: String] = [:]
    var monotonicEffects: [MonotonicSpec] = []
    // NUTS warmup inits (2026-06-02). Last-write-wins on duplicate keys.
    var initValues: [String: Double] = [:]

    for statement in model.statements {
      switch statement {
      case .likelihood(let lhs, let dist, let trunc, _):
        referenced.insert(lhs)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
        // Record bounds on the outcome variable for the data block.
        let bounds = DistributionCatalog.outcomeBounds(dist)
        if !bounds.isEmpty { outcomeBoundsByLhs[lhs] = bounds }
      case .prior(let name, let dist, let trunc, let constraints, let start, _):
        if !parameters.contains(name) { parameters.append(name) }
        scalarPriorNames.insert(name)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
        // 2026-06-03: `constraints:` is declaration-only — it bypasses
        // the `T[…]` sampling suffix. Co-setting with `truncation:` is
        // always a user error since `truncation:` already drives the
        // declaration constraint too.
        if !constraints.isEmpty && !trunc.isEmpty {
          throw DataInferenceError.constraintsConflictWithTruncation(name: name)
        }
        // Record the constraint for the parameter declaration. Multiple
        // priors with non-equal non-empty truncations / constraints on
        // the same name are rejected — we don't try to compute the
        // intersection. `Constraints` and `Truncation` share the same
        // internal `(lower, upper)` shape.
        let declConstraint = !constraints.isEmpty ? constraints.asTruncation : trunc
        if !declConstraint.isEmpty {
          if let existing = parameterTruncationByName[name],
             existing != declConstraint {
            throw DataInferenceError.conflictingParameterConstraints(name: name)
          }
          parameterTruncationByName[name] = declConstraint
        }
        // 2026-06-03: per-prior `start:` → init JSON. `Inits([:])` walks
        // later and overlays by last-write-wins.
        if let start { initValues[name] = start }
      case .varyingPrior(let name, let indexedBy, let countSymbol, let dist, let trunc, let constraints, let start, let useLpdf, let nonCentered):
        // Phase 5 Slice B: declare `name` as a vector parameter typed by
        // `countSymbol` (or auto-derived `N_<indexedBy>`); register
        // `indexedBy` as an index column.
        varyingPriorNames.insert(name)
        referenced.insert(indexedBy)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
        let symbol = countSymbol ?? "N_\(indexedBy)"
        if nonCentered {
          // Phase 5.5 Slice E: validate the non-centred preconditions.
          guard case .normal(let mu, let sigma) = dist else {
            throw DataInferenceError.nonCenteredRequiresNormal(name: name)
          }
          if !trunc.isEmpty {
            throw DataInferenceError.nonCenteredWithTruncationUnsupported(name: name)
          }
          if useLpdf {
            throw DataInferenceError.nonCenteredWithLpdfUnsupported(name: name)
          }
          let rawName = "\(name)_raw"
          if !parameters.contains(rawName) { parameters.append(rawName) }
          if let existing = vectorParameters[rawName], existing != symbol {
            throw DataInferenceError.conflictingVaryingPriorCardinality(name: name)
          }
          vectorParameters[rawName] = symbol
          nonCenteredVarying[name] = NonCenteredSpec(rawName: rawName,
                                                    countSymbol: symbol,
                                                    muArg: mu,
                                                    sigmaArg: sigma)
        } else {
          if !parameters.contains(name) { parameters.append(name) }
          if let existing = vectorParameters[name], existing != symbol {
            throw DataInferenceError.conflictingVaryingPriorCardinality(name: name)
          }
          vectorParameters[name] = symbol
          // 2026-06-03: same constraints/truncation reconciliation as
          // the scalar `.prior` arm above.
          if !constraints.isEmpty && !trunc.isEmpty {
            throw DataInferenceError.constraintsConflictWithTruncation(name: name)
          }
          let declConstraint = !constraints.isEmpty ? constraints.asTruncation : trunc
          if !declConstraint.isEmpty {
            if let existing = parameterTruncationByName[name],
               existing != declConstraint {
              throw DataInferenceError.conflictingParameterConstraints(name: name)
            }
            parameterTruncationByName[name] = declConstraint
          }
        }
        if let start { initValues[name] = start }
        if let existing = indexColumns[indexedBy], existing != symbol {
          throw DataInferenceError.conflictingIndexColumnCardinality(column: indexedBy)
        }
        indexColumns[indexedBy] = symbol
      case .vectorPrior(let name, let length, let dist, let trunc, _):
        // Phase 6 Slice B: register `name` as a vector parameter of
        // length `<length>` (a cardinality symbol bound below). The
        // cardinality binding happens after the statement walk once we
        // know which Phase-6 data columns are present.
        if !parameters.contains(name) { parameters.append(name) }
        vectorParameters[name] = length
        phaseSixSymbolsDeclared.insert(length)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
        if !trunc.isEmpty {
          // Stan doesn't support `T[...]` on multivariate distributions.
          if DistributionCatalog.isMultivariate(dist) {
            throw DataInferenceError.multivariateTruncationUnsupported(symbol: name)
          }
          if let existing = parameterTruncationByName[name], existing != trunc {
            throw DataInferenceError.conflictingParameterConstraints(name: name)
          }
          parameterTruncationByName[name] = trunc
        }
      case .matrixPrior(let name, let rows, let cols, let dist, let trunc, _):
        // SUR Slice A: register `name` as a matrix-typed parameter and
        // declare its rows/cols cardinality symbols so the data block
        // ends up with `int<lower=1> <rows>;` / `int<lower=1> <cols>;`
        // bound by user-supplied scalar data (or, post-Slice-C, by a
        // matrix data column whose shape supplies them).
        if !parameters.contains(name) { parameters.append(name) }
        matrixParameters[name] = (rows: rows, cols: cols)
        referenced.insert(rows)
        referenced.insert(cols)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
      case .covMatrixPrior(let name, let dim):
        // SUR Slice B: cov_matrix parameter. No distribution, no prior
        // — Stan's positive-definite constraint gives the sampler a
        // workable default.
        if !parameters.contains(name) { parameters.append(name) }
        covMatrixParameters[name] = dim
        referenced.insert(dim)
      case .lkjCorrCholeskyPrior(let name, let dim, let eta):
        // Multivariate hierarchical priors Slice A: cholesky_factor_corr
        // parameter with an LKJ-Cholesky prior on the implied
        // correlation matrix.
        if !parameters.contains(name) { parameters.append(name) }
        cholFactorParameters[name] = dim
        referenced.insert(dim)
        if case .symbol(let s) = eta { referenced.insert(s) }
      case .wishartPrior(let name, let dim, let nu, let V):
        // Wishart prior on a cov_matrix parameter. Shares the
        // covMatrixParameters dict with covMatrixPrior so the
        // parameters block emits `cov_matrix[dim] name;` for free.
        if !parameters.contains(name) { parameters.append(name) }
        covMatrixParameters[name] = dim
        referenced.insert(dim)
        if case .symbol(let s) = nu { referenced.insert(s) }
        if case .symbol(let s) = V  {
          referenced.insert(s)
          // Map scale-matrix column → dim symbol so BlockEmitter can
          // emit `cov_matrix[<dim>] <col>;` in the data block.
          // Also exclude it from Phase-6 cardinality binding — it's a
          // pure data input, not a cardinality anchor.
          wishartScaleColumns.insert(s)
          wishartScaleColumnDims[s] = dim
        }
      case .nestedVaryingPrior(let name, let indexedBy, let countSymbols, let dist, let trunc, _):
        // Nested groupings (2026-06-03): McElreath
        // `a[country, region] ~ dnorm(a_bar, sigma_a)`. v1 requires
        // exactly two grouping dimensions; declares
        // `matrix[N_<col1>, N_<col2>] <name>;` and emits the iid
        // `to_vector(<name>) ~ <dist>(args);` sampling line via
        // `BlockEmitter.modelBlock`. Both index columns are bound for
        // tightened `<lower=1, upper=N_<col>>` declarations.
        guard indexedBy.count == 2, countSymbols.count == 2 else {
          throw DataInferenceError.nestedVaryingPriorArity(
            name: name, got: indexedBy.count)
        }
        if !parameters.contains(name) { parameters.append(name) }
        let col1 = indexedBy[0]
        let col2 = indexedBy[1]
        let sym1 = countSymbols[0] ?? "N_\(col1)"
        let sym2 = countSymbols[1] ?? "N_\(col2)"
        matrixParameters[name] = (rows: sym1, cols: sym2)
        if let existing = indexColumns[col1], existing != sym1 {
          throw DataInferenceError.conflictingIndexColumnCardinality(column: col1)
        }
        if let existing = indexColumns[col2], existing != sym2 {
          throw DataInferenceError.conflictingIndexColumnCardinality(column: col2)
        }
        indexColumns[col1] = sym1
        indexColumns[col2] = sym2
        referenced.insert(col1)
        referenced.insert(col2)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
      case .varyingVectorPrior(let name, let indexedBy, let length, let countSymbol, let dist, let trunc, _):
        // Multivariate hierarchical priors Slice C: vector-valued
        // varying effects with a multivariate prior. Declares
        // `array[<outer>] vector[<length>] <name>;` in `parameters` and
        // tightens the bounds on `indexedBy` as a group index column.
        if !parameters.contains(name) { parameters.append(name) }
        let outerSymbol = countSymbol ?? "N_\(indexedBy)"
        varyingVectorParameters[name] = (outer: outerSymbol, length: length)
        if let existing = indexColumns[indexedBy], existing != outerSymbol {
          throw DataInferenceError.conflictingIndexColumnCardinality(column: indexedBy)
        }
        indexColumns[indexedBy] = outerSymbol
        referenced.insert(indexedBy)
        referenced.insert(length)
        for s in DistributionCatalog.symbolsReferenced(dist) { referenced.insert(s) }
        for s in DistributionCatalog.symbolsReferenced(trunc) { referenced.insert(s) }
      case .simplexPrior(let name, let length):
        // Monotonic effects Slice D: declares `simplex[<length>] <name>;`
        // in `parameters`. Register `length` in `phaseSixSymbolsDeclared`
        // so the existing Phase-6 anchoring (e.g. `alpha` vector) supplies
        // the cardinality value, parallel with `VectorPrior`. The user
        // attaches a separate `Prior(<name>, .dirichlet(<alpha>))` for
        // the iid prior.
        if !parameters.contains(name) { parameters.append(name) }
        simplexParameters[name] = length
        phaseSixSymbolsDeclared.insert(length)
      case .monotonicEffect(let name, let scale, let predictor,
                            let levels, let targetLhs):
        // Monotonic effects: record the spec for BlockEmitter's
        // detection pass. The simplex parameter `name` is declared via
        // a companion `SimplexPrior`; `scale` is a scalar `Prior`;
        // `predictor` is an integer data column (1-indexed). Insert
        // `predictor` as a referenced data column so the data block
        // declares it; the scale parameter is referenced via its
        // `Prior` statement.
        monotonicEffects.append(MonotonicSpec(
          name: name,
          scale: scale,
          predictor: predictor,
          levels: levels,
          targetLhs: targetLhs))
        referenced.insert(predictor)
      case .orderedCutpointsPrior(let name, let K):
        // Ordered logit / probit Slice D: declares `ordered[<K>-1] <name>;`
        // in `parameters`. Register K in `phaseSixSymbolsDeclared` so the
        // existing scalarInt-binding path accepts a `"K": .scalarInt(...)`
        // data entry as the cardinality source (parallels the cafe-style
        // J binding for the multivariate hierarchical priors).
        if !parameters.contains(name) { parameters.append(name) }
        orderedCutpointParameters[name] = K
        phaseSixSymbolsDeclared.insert(K)
        referenced.insert(K)
      case .gaussianProcessPrior(let name, let indexedBy, let distanceMatrix,
                                 let etasq, let rhosq, let jitter):
        // The latent vector `<name>` lives in `transformed parameters`,
        // not `parameters` — mirror the non-centred-varying treatment
        // (don't append to `parameters`, but register it on
        // `gaussianProcessGP` so the known-non-data set picks it up
        // and the transformed-params block emitter declares + builds
        // it). The raw z-vector `<rawName>` is a real parameter.
        let rawName = "\(name)_z"
        let countSymbol = "N"
        if !parameters.contains(rawName) { parameters.append(rawName) }
        vectorParameters[rawName] = countSymbol
        gaussianProcessGP[name] = GPSpec(
          rawName: rawName,
          countSymbol: countSymbol,
          distanceMatrix: distanceMatrix,
          etasq: etasq,
          rhosq: rhosq,
          jitter: jitter)
        squareMatrixColumns.insert(distanceMatrix)
        // Treat `indexedBy` as an integer index column ranging 1..N.
        if let existing = indexColumns[indexedBy], existing != countSymbol {
          throw DataInferenceError.conflictingIndexColumnCardinality(column: indexedBy)
        }
        indexColumns[indexedBy] = countSymbol
        referenced.insert(indexedBy)
        referenced.insert(distanceMatrix)
        if case .symbol(let s) = etasq { referenced.insert(s) }
        if case .symbol(let s) = rhosq { referenced.insert(s) }
      case .inits(let values):
        // 2026-06-02: collect user-supplied warmup inits. No symbol
        // references, no parameter declarations — pure metadata that
        // the marshaller turns into `<model>.init.json`.
        for (k, v) in values { initValues[k] = v }
      case .link(_, let lhs, let rhs):
        if !derived.contains(lhs) { derived.append(lhs) }
        for s in symbolsIn(rhs) { referenced.insert(s) }
      case .deterministic(let lhs, let rhs):
        if !derived.contains(lhs) { derived.append(lhs) }
        for s in symbolsIn(rhs) { referenced.insert(s) }
      }
    }

    // A symbol declared as both a scalar Prior and a VaryingPrior is a
    // model error — picking one resolves the ambiguity in declaration
    // and sampling form.
    for name in scalarPriorNames.intersection(varyingPriorNames) {
      throw DataInferenceError.parameterIsBothScalarAndVarying(name: name)
    }

    // Ordered logit / probit (2026-06-02) post-fix: now that the
    // cutpoints declaration has been observed, patch
    // `outcomeBoundsByLhs[lhs].upper` for any ordered likelihood whose
    // cutpoints arg names a registered ordered parameter. The catalog
    // can't supply the K symbol on its own because it sees one
    // distribution at a time, with no view of the parameter dict.
    for statement in model.statements {
      guard case .likelihood(let lhs, let dist, _, _) = statement else { continue }
      let cutpointsArg: DistributionArg
      switch dist {
      case .orderedLogistic(_, let cp), .orderedProbit(_, let cp):
        cutpointsArg = cp
      default:
        continue
      }
      guard case .symbol(let cutName) = cutpointsArg,
            let K = orderedCutpointParameters[cutName] else { continue }
      let existingLower = outcomeBoundsByLhs[lhs]?.lower
      outcomeBoundsByLhs[lhs] = DistributionCatalog.OutcomeBounds(
        lower: existingLower ?? "1",
        upper: K)
    }

    // Materialise the parameter-constraint suffixes.
    var parameterConstraints: [String: String] = [:]
    for (name, trunc) in parameterTruncationByName {
      parameterConstraints[name] = DistributionCatalog.renderConstraint(trunc)
    }

    // Slice E: non-centred VaryingPriors register the original name
    // (e.g. `a`) as a transformed parameter, so references to it from
    // Link RHS (`a[group]`) must not trip the undeclared-symbol check
    // even though `a` itself isn't in `parameters`.
    let knownNonData = Set(parameters)
      .union(derived)
      .union(nonCenteredVarying.keys)
      .union(gaussianProcessGP.keys)
    let dataReferenced = referenced.subtracting(knownNonData)

    for sym in dataReferenced where model.data[sym] == nil {
      throw DataInferenceError.undeclaredSymbol(sym)
    }

    var vectors: [(String, UlamColumn)] = []
    var scalars: [(String, UlamColumn)] = []
    for name in dataReferenced.sorted() {
      let col = model.data[name]!
      if col.isVector {
        vectors.append((name, col))
      } else {
        scalars.append((name, col))
      }
    }

    var N: Int? = nil
    var lengths: [(String, Int)] = []
    for (name, col) in vectors {
      let c = col.count!
      lengths.append((name, c))
      if N == nil {
        N = c
      } else if N != c {
        throw DataInferenceError.mismatchedVectorLengths(lengths)
      }
    }

    // Phase 6: bind every Phase-6-shaped column (realVector,
    // realCovMatrix, realArrayVector) to a cardinality symbol declared
    // by a VectorPrior. v1 supports a single declared symbol per
    // model; with more than one we ask the user to be explicit (v2
    // adds a `countSymbol:` override on the column).
    var phaseSixCardinalitySymbols: [String: Int] = [:]
    var phaseSixColumnSymbols: [String: String] = [:]
    let phaseSixColumns = (vectors + scalars).filter {
      $0.1.innerLength != nil && !wishartScaleColumns.contains($0.0)
    }
    if !phaseSixColumns.isEmpty {
      if phaseSixSymbolsDeclared.count > 1 {
        throw DataInferenceError.multipleCardinalitySymbolsAmbiguous(
          phaseSixSymbolsDeclared.sorted())
      }
      guard let symbol = phaseSixSymbolsDeclared.first else {
        // Phase-6-shaped data is present but no VectorPrior declared a
        // cardinality symbol — we have no name to bind it to.
        // Identify the first orphan column for the message.
        throw DataInferenceError.unboundCardinalitySymbol(
          symbol: phaseSixColumns[0].0)
      }
      for (colName, col) in phaseSixColumns {
        let length = col.innerLength!
        if let existing = phaseSixCardinalitySymbols[symbol], existing != length {
          throw DataInferenceError.cardinalityLengthMismatch(
            symbol: symbol, expected: existing, column: colName, found: length)
        }
        phaseSixCardinalitySymbols[symbol] = length
        phaseSixColumnSymbols[colName] = symbol
      }
    }
    // A VectorPrior cardinality symbol with no Phase-6 column to anchor
    // it can still be supplied directly by the user as a `.scalarInt`
    // data entry — that's the binding path used by the multivariate
    // hierarchical priors (Slice A/C) where there's no companion
    // Phase-6-shaped data column. Otherwise it's an error.
    for symbol in phaseSixSymbolsDeclared where phaseSixCardinalitySymbols[symbol] == nil {
      if case .scalarInt = model.data[symbol] { continue }
      throw DataInferenceError.unboundCardinalitySymbol(symbol: symbol)
    }

    // Phase 5.5 Slice C: walk every Link/Deterministic RHS for
    // identifiers that appear as direct operands of `*` or `/`. Any
    // such identifier that matches an `.integer(...)` data column —
    // and isn't already serving as an index column — gets promoted
    // to `vector[N]` so Stan's real-typed arithmetic type-checks.
    // Parse failures here are swallowed; BlockEmitter.vectorisationStrategy
    // surfaces the same parse error downstream.
    var multiplicativeOperands: Set<String> = []
    for statement in model.statements {
      let rhs: Expression
      switch statement {
      case .link(_, _, let r):          rhs = r
      case .deterministic(_, let r):    rhs = r
      default:                          continue
      }
      if let node = try? rhs.parsed() {
        collectMultiplicativeOperands(in: node, into: &multiplicativeOperands)
      }
    }
    var promotedIntColumns: Set<String> = []
    for sym in multiplicativeOperands {
      guard let col = model.data[sym] else { continue }
      if case .integer = col, indexColumns[sym] == nil {
        promotedIntColumns.insert(sym)
      }
    }

    return InferredModel(
      dataVectors: vectors,
      dataScalars: scalars,
      parameters: parameters,
      derived: derived,
      N: N,
      parameterConstraints: parameterConstraints,
      outcomeBoundsByLhs: outcomeBoundsByLhs,
      vectorParameters: vectorParameters,
      indexColumns: indexColumns,
      phaseSixCardinalitySymbols: phaseSixCardinalitySymbols,
      phaseSixColumnSymbols: phaseSixColumnSymbols,
      promotedIntColumns: promotedIntColumns,
      nonCenteredVarying: nonCenteredVarying,
      matrixParameters: matrixParameters,
      covMatrixParameters: covMatrixParameters,
      cholFactorParameters: cholFactorParameters,
      wishartScaleColumns: wishartScaleColumnDims,
      varyingVectorParameters: varyingVectorParameters,
      orderedCutpointParameters: orderedCutpointParameters,
      simplexParameters: simplexParameters,
      monotonicEffects: monotonicEffects,
      gaussianProcessGP: gaussianProcessGP,
      squareMatrixColumns: squareMatrixColumns,
      initValues: initValues
    )
  }

  /// Phase 5.5 Slice C: collect identifier names that appear as a
  /// direct lhs/rhs operand of `*` or `/` anywhere in the parsed
  /// expression. Identifiers inside indexed expressions are also
  /// walked, but the outer indexed name itself (whose type is already
  /// fixed by its declaration) is left alone.
  private static func collectMultiplicativeOperands(
    in node: ExpressionNode,
    into set: inout Set<String>
  ) {
    switch node {
    case .binary(let op, let lhs, let rhs):
      if op == .multiply || op == .divide {
        if case .identifier(let name) = lhs { set.insert(name) }
        if case .identifier(let name) = rhs { set.insert(name) }
      }
      collectMultiplicativeOperands(in: lhs, into: &set)
      collectMultiplicativeOperands(in: rhs, into: &set)
    case .unary(_, let operand):
      collectMultiplicativeOperands(in: operand, into: &set)
    case .call(_, let argument):
      collectMultiplicativeOperands(in: argument, into: &set)
    case .indexed(_, let index):
      // Don't promote the outer name; its declaration already fixes
      // the type. Recurse into the index in case it carries its own
      // arithmetic (unusual but legal).
      collectMultiplicativeOperands(in: index, into: &set)
    case .chainedIndexed(_, let outer, let inner):
      // Same rationale as `.indexed` — the outer chain name is
      // already typed by its declaration. Walk both index expressions.
      collectMultiplicativeOperands(in: outer, into: &set)
      collectMultiplicativeOperands(in: inner, into: &set)
    case .subscript2(_, let idx1, let idx2):
      // Nested groupings: same rationale — the outer matrix name is
      // already typed by its declaration; walk both index expressions.
      collectMultiplicativeOperands(in: idx1, into: &set)
      collectMultiplicativeOperands(in: idx2, into: &set)
    case .identifier, .literal:
      break
    }
  }

  /// Pull identifier-like tokens out of an expression string. Stan built-ins
  /// (exp, log, inv_logit, ...) are filtered so they aren't flagged as
  /// undeclared symbols. Numeric literals never match because the leading
  /// character class excludes digits.
  private static func symbolsIn(_ expression: Expression) -> [String] {
    let pattern = "[A-Za-z_][A-Za-z0-9_]*"
    let regex = try! NSRegularExpression(pattern: pattern)
    let nsString = expression.source as NSString
    let matches = regex.matches(in: expression.source,
                                range: NSRange(location: 0, length: nsString.length))
    let tokens = matches.map { nsString.substring(with: $0.range) }
    return tokens.filter { !stanBuiltins.contains($0) }
  }

  /// Stan built-in functions, constants, plus reserved loop-variable
  /// conventions used by the emitter (`i` for Phase 5/5.5 loop
  /// emission, `n` for SUR per-row loops). Names in this set don't
  /// need to resolve to a data column or parameter — they're either
  /// callable in Stan source or bound by a loop the emitter
  /// introduces.
  private static let stanBuiltins: Set<String> = [
    "exp", "log", "sqrt", "abs", "pow",
    "inv_logit", "logit", "inv_cloglog", "cloglog",
    "sin", "cos", "tan", "atan2",
    "sum", "mean", "min", "max",
    "pi", "e",
    // Reserved loop-variable conventions.
    "i", "n",
  ]
}
