# README

## Purpose of SwiftStan package

1. A MacOSv26/Xcode/Swift based CLI (Command Line Interface) to Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) executable.

2. Hosting a port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

This project is work in progress!!! Work completed or still to be done can be found in [TODO](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/TODO.md). Some additional technical details can be found in [CLAUDE](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/CLAUDE.md). Lots of testing and more examples are needed for the ulam pipeline.


## Supported functionality  

### Cmdstan pipeline related commands 

```gfm
| ------------ | ------------------------------------------ |
| Command      | Effect                                     |
| ------------ | ------------------------------------------ |
| compile      | Compile a Stan model                       |
| sample       | Sample from a compiled model               |
| stansummary  | Stansummary on a sampled model             |
| optimize     | Optimize a compiled model                  |
| pathfinder   | Pathfinder on a compiled model             |
| laplace      | Laplace approximation on a compiled model  |
| runinfo      | See note 5      |
| ------------ | ------------------------------------------ |
```
**Notes**

1. The option `runinfo` is currently not yet used in either pipeline. It parses the "<name>.output.config.json" file which is by default written during the `sample` step. A slightly simplified version is stored as "<name>.runinfo.json".

 
### Ulam pipeline related commands

```gfm
| ------------ | -------------------------------------- |
| Command      | Effect                                 |
| ------------ | -------------------------------------- |
| ulam         | Run the ulam pipeline end-to-end       |
| stancode     | alist -> .stan                         |
| alist2dsl    | alist -> smoke driver                  |
| dsl2stan     | smake driver -> .stan                  |
| ------------ | -------------------------------------- |
```
**Notes**

1. By default `ulam` prefers the fast in-process `stancode` path when an "<name>.alist.R" is present.                          
2. Command `ulam` falls back to `dsl2stan` against a hand-authored smoke driver.


### Shared between both pipelines

```gfm
| ------------ | -------------------------------------- |
| Command      | Effect                                 |
| ------------ | -------------------------------------- |
| csv2json     | "<name>.csv" -> "<name>.json"            |
| ------------ | -------------------------------------- |
```

**Notes**
  
1. As with building a Stan binary during `compile`, all commands only operate when the input file's modification timestamp is newer than the corresponding output timestamp. 
2. Run `csv2json` preferably after a "<name>.stan" file has been set up. In that case the "<name>.data.json" file reflects what is needed. It also adds items like 'N', the number of observations, and other needed data items such as 'N\_blocks'.



## Prerequisites  

This [repository](https://github.com/SwiftProjectOrganization/Stan) is an Xcode project. Some familiarity with running Xcode and Swift programs on MacOS is assumed. To edit documentation files, if not from within Xcode, I use [Clearly](https://clearly.md).

### 1. Clone the repository  

To get going, start Xcode and:  
  
  1. Click on `'Integrate'`.
  2. Select `'Clone'`.
  3. Enter the http address for this repository: "https://github.com/SwiftProjectOrganization/SwiftStan".  
  4. Click `'Clone'`.  

The repository will be downloaded and the project will open in Xcode.  
  
### 2. Setup steps

  1. To use Stan's cmdstan, typically an environment variable `"CMDSTAN"` is defined to point to the cmdstan directory. See references 1 and 2 below on how to install cmdstan and below .zshrc fragment how it can be included.
      
  2. `'build and run'` the project.
      
  3. Expand your CMDSTAN definition in your .zshrc with an `'alias'` and two more environment variables, `'STAN_CASES'` and `'SWIFTSTAN_PROJECT_ROOT'`:
  
```.zshrc

export CMDSTAN=/Users/rob/Projects/StanSupport/cmdstan/
launchctl setenv CMDSTAN /Users/rob/Projects/StanSupport/cmdstan/

alias swiftstan="/Users/rob/Library/Developer/Xcode/DerivedData/SwiftStan-*/Build/Products/Debug/SwiftStan"

export STAN_CASES="/Users/rob/Documents/StanCases"
launchctl setenv STAN_CASES /Users/rob/Documents/StanCases

export SWIFTSTAN_PROJECT_ROOT="/Users/rob/Projects/Swift/SwiftStan"
launchctl setenv SWIFTSTAN_PROJECT_ROOT /Users/rob/Projects/Swift/SwiftStan
```

Make sure "SwiftStan-*" points to the most recent version of SwiftStan in "../Xcode/DerivedData"

Environment variables used by the pipeline:

  - `CMDSTAN` — location of the cmdstan installation (required for `compile`/`sample`).
  - `STAN_CASES` — case-root directory name under `~/Documents/`; defaults to `StanCases`.
  - `SWIFTSTAN_PROJECT_ROOT` — location of the SwiftStan source checkout, used by the DSL pipeline's `dsl2stan` to compile the smoke driver against the project's `Ulam/` sources. When unset it defaults to `/Users/rob/Projects/Swift/SwiftStan` and `dsl2stan` prints a notice that the default is being used. Set it if your checkout lives elsewhere.

### 3. Testing SwiftStan

After finishing the setup steps, in a (MacOS or other) Terminal:

1. Navigate to the SwiftStan directory, e.g. `cd ~/Project/Swift/SwiftStan`.

2. Enter `swift test`.

To run individual tests, use `swift test --filter "chimpanzeesHappyPath()"`.


## Working environment  

After the initial build, the intended usage is to run the commands from a shell. This requires the exported alias in that shell as setup above. It's not always necessary, but advisable, to run `swifstan ...` from the SwiftStan directory.

The above commands can also be run from within Xcode by specifying input arguments before hitting the `'build and run'` button. See below "Usage from within Xcode".  

### File system assumptions
 
All pipeline commands operate on a set of files stored in the directory `"~/Documents/<STAN_CASES>/<name>/..."`. Here <name> is the name of a model, e.g. bernoulli or chimpanzees.

The <STAN_CASES> enviroment variable specifies the actual location, by default this is `'StanCases'`. 

The cmdstan pipeline only uses files in `"~/Documents/<STAN_CASES>/name>/Results"`. All cmdstan output files also end up in Results.

The ulam pipeline looks for files in `"~/Documents/<STAN_CASES>/<name>/Preliminaries"`.

Produced files end up in either Preliminaries (`"<Name>.ulam.swift"`) or in Results ( `"<name>.stan"` and `"<name>.data.json"`.


### Files read when using the pipelines

In `"~/Documents/<STAN_CASES>/<name>/Preliminaries"` 3 files can be present:

    1. `"<name>.csv"`: A .csv file containing the data for the <name>.
    2. `"<name>.alist.R"`: A .R fragment containing an R alist as used in `'rethinking'`.
    3. `"<Name>.ulam.swift"`: Intermediate file for debugging or handcoding Ulam DSL.
    
    If there is an `"<name>.csv"` file, the command `'csv2json'` will create a `"<name>.data.json"` file in the Results subdirectory for <name>.
    
    If there is a `"<name>.alist.R"` file, the command `'stancode'` will create a `"Results/<name>.stan"` file.
    
    Another option is to use the `'ulam'` command. This pipeline is useful for debugging and compiling hand generated smoke files (see below Ulam DSL).

In `"~/Documents/<STAN_CASES>/<name>/Results"` at least 2 files must be present before the cmdstan pipeline can be used:

    1. `"<name>.data.json"`: If data is needed for the model.
    2. `"<name>.stan"`: Stan language program.
    
    Using the cmdstan pipeline many other files can and will be generated in the Results subdirectory.

            
### Per-invocation logs

Every cmdstan call (`compile`, `sample`, `optimize`, `laplace`, `pathfinder`, `stansummary`) writes its raw stdout and stderr to the model's `Results/` directory as:

```
~/Documents/<STAN_CASES>/name>/Results/<name>.<method>.log         # captured stdout
~/Documents/<STAN_CASES>/name>/Results/<name>.<method>.error.log   # captured stderr
```

Both files are written on every run (zero bytes means "ran but emitted nothing"); each invocation overwrites the previous log. cmdstan emits most diagnostics (warmup banners, divergence messages, treedepth warnings) to **stdout**, so the `.log` file is normally where to look first; `.error.log` is reserved for hard failures and a few compile-time messages.

The `sample` command uses `save_cmdstan_config=true` by default and writes "<Name>_output_config.json" to the Results directory. The `runinfo` subcommand reads that JSON into a typed `RunInfo` value and writes a slightly simplified, "<name>.runinfo.json" to Results.


## Usage  

The package can be used from the CLI (Terminal) or from within Xcode.

### Usage from the CLI

Help is available with `'swiftstan -h'` or `'swiftstan compile -h'`.

```.zshrc
rob@Rob-Travel-M5 ~ % stan -h
OVERVIEW: A wrapper for running cmdstan.

USAGE: swiftstan <subcommand>

OPTIONS:
  --version                 Show the version.
  -h, --help                Show help information.

SUBCOMMANDS:
  compile                   Compile the Stan model.
  sample                    Sample the Stan model.
  optimize                  Optimize the Stan model.
  pathfinder                Use Pathfinder approximation.
  laplace                   Run cmdstan's Laplace approximation on a compiled model.
  stansummary               Run the Stan summary program.
  csv2json                  Read Preliminaries/<name>.csv, writes Results/<name>.data.json.
  dsl2stan                  Compile a Preliminaries/*.ulam.swift, write Results/<name>.stan.
  alist2dsl                 Translate Preliminaries/<name>.alist.R into  Preliminaries/<Name>.ulam.swift.
  stancode                  Translate Preliminaries/<name>.alist.R straight to Results/<name>.stan (in-process, no swiftc).
  runinfo                   Read Results/<name>_output_config.json and write a cleaned Results/<name>.runinfo.json.
  ulam                      Run one of the built-in ulam DSL demos (--model Bernoulli|Poisson|Binomial|UCB|Dmvnorm).
  test (default)            Test the CLI functions.

  See 'swiftstan help <subcommand>' for detailed help.
rob@Rob-Travel-M5 ~ % 
```

If the appropriate files are present, a typical Terminal session could continue with:

1. `'swiftstan compile --model=bernoulli'`
2. `'swiftstan sample --model=bernoulli'`

or

3. `'swiftstan ulam --model=chimpanzees'`

    The `'ulam'` pipeline uses Swift to first create an intermediate `'Ulam smoke driver'` which takes roughly 6 seconds longer. But I do like the option to generate Ulam DSL where the structure of the Stan model is clearly labeled and the input data file checked.

### Usage from within Xcode

Edit the schema arguments, e.g. `'compile --model=bernoulli'` and press "build-and-run".

### Bootstrapping the bernoulli example

Use the -I switch to install required files to compile and sample a bernoulli Stan Language Program.

In the SwiftStan directory:

1. `swiftstan compile -I`
2. `swiftstan sample -I`


## Ulam DSL

The package includes a Swift port of Richard McElreath's R `ulam()` (from the `rethinking` package).

Instead of writing `.stan` source by hand, you can:

    1. use the `'alist2stan'` command to directly translate a `"<name>/Preliminaries/<name>.alist.R"` to an `"<name>/Results/<model.stan"` file

    2. define the model with a Swift result-builder DSL; the generator emits both `"<name>.stan"` and `"<name>.data.json"` under `"<name>/Results/"` and then hands off to the existing `compile` and `sample` pipeline steps.

The ulam pipeline is split into sub-commands:

    1. `alist2stan` (R "alist" → .stan file)
    2. `alist2dsl` (R "alist" → Swift smoke driver) 
    3. `dsl2stan` (Swift smoke driver → ".stan")
    
    and
    
    4. `csv2json` (CSV → `.data.json`), then `ulam` chains them with `compile` + `sample`.


Canonical Statistical Rethinking opening example — Bernoulli + logit as a smoke file:

```swift
import Foundation
import SwiftStan

let data: UlamData = [
  "y": .integer([0, 1, 0, 1, 1, 0, 1, 1, 1, 0]),
  "x": .real([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]),
]

let model = UlamModel(data: data) {
  Likelihood("y", .bernoulli(p: "p"))
  Link(.logit, lhs: "p", rhs: "a + b*x")
  Prior("a", .normal(0, 1.5))
  Prior("b", .normal(0, 0.5))
}

let result = ulam(model,
                  directory: "StanCases",
                  name: "Bernoulli",
                  cmdstan: cmdstan)
```

The generated `Bernoulli.stan` is:

```stan
// Generated by Stan ulam port (DSL → Stan source).
data {
  int<lower=1> N;
  vector[N] x;
  array[N] int<lower=0, upper=1> y;
}
parameters {
  real a;
  real b;
}
model {
  vector[N] p;
  p = inv_logit(a + b*x);
  a ~ normal(0, 1.5);
  b ~ normal(0, 0.5);
  y ~ bernoulli(p);
}
```

The built-in demo is wired to the `'ulam'` subcommand — run `'stan ulam -V'` to compile and sample the example end-to-end. For a generator-only check (no cmdstan), the public `stancode(_:)` function returns the source as a string.


## Additional project documentation

- [`CLAUDE.md`](CLAUDE.md) — architecture notes for the `Stan` Swift package (Commands / Methods / Support layering, the `(String, String)` return convention, the Ulam module layout, etc.). Loaded by Claude Code sessions in this workspace.
- [`TODO.md`](TODO.md) — forward-looking punch list for topics beyond v1.5 scope (SUR, LKJ-Cholesky, post-sampling helpers, etc.).


## References

1. [Stan](https://mc-stan.org)
2. [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/)
3. [McElreath, *Statistical Rethinking* (2nd ed.)}(https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919) — `ulam()` is from the accompanying R `rethinking` package.
