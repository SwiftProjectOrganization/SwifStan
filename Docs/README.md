# README

## Purpose

1. A MacOSv26/Xcode/Swift based CLI (Command Line Interface) to Stan's [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/) executable.

2. Hosting a port of [McElreath](https://www.routledge.com/Statistical-Rethinking-A-Bayesian-Course-with-Examples-in-R-and-STAN/McElreath/p/book/9780367139919)'s R implementation ulam() in [rethinking](https://github.com/rmcelreath/rethinking) to Swift.

This project is work in progress!!! Work still to be done can be found in [TODO](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/TODO.md). Some additional technical details can be found in [CLAUDE](https://github.com/SwiftProjectOrganization/Stan/blob/main/Docs/CLAUDE.md)


## Supported functionality  

**1. Cmdstan pipeline related commands:**  

```gfm
| ------------ | ----------------------------------------- |
| Command      | Effect                                    |
| ------------ | ----------------------------------------- |
| compile      | Compile a Stan model                      |
| sample       | Sample from a compiled model              |
| stansummary  | Stansummary on a sampled model            |
| optimize     | Optimize a compiled model                 |
| pathfinder   | Pathfinder on a compiled model            |
| laplace      | Laplace approximation on a compiled model |
| ------------ | ----------------------------------------- |
```
  
**2. Ulam pipeline related commands:**

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
  

**3. Shared between both pipelines:**

```gfm
| ------------ | -------------------------------------- |
| Command      | Effect                                 |
| ------------ | -------------------------------------- |
| csv2json     | <model>.csv -> <model>.json            |
| ------------ | -------------------------------------- |
```

**Notes**
  
  1. By default `'ulam'` prefers the fast in-process `stancode` path when an `.alist.R` is present.                          
  2. `ulam` falls back to `dsl2stan` against a hand-authored smoke driver.
  3. As with building a Stan binary during `compile`, all commands only operate when the input file lat modification timstamp is newer than the corresponding output timestamp.  
  4. All of these commands operate on a set of files stored in `"~/Documents/<STAN_CASES>/..."`.
  5. The <STAN_CASES> enviroment variable specifies the actual location, by default this is `'StanCases'`.
  6. The cmdstan pipeline only uses files in `"~/Documents/<STAN_CASES>/Results"`.
  7. The ulam pipeline looks for files in `"~/Documents/<STAN_CASES>/Preliminaries"`. Produced files end up in either Preliminaries (`"<Model>.ulam.swift"`) or in Result ( `"<model>.stan"` and `"<model>.data.json"`.


## Working environment  

This [repository](https://github.com/SwiftProjectOrganization/Stan) is an Xcode project. Some familiarity with running Xcode and Swift programs on MacOS is assumed.  

After an initial build (see "Prerequisites" below), the above commands can be run from within Xcode by specifying input arguments before hitting the `'build and run'` button. See below "Usage from within Xcode". 

After the initial build, the intended usage is to run the commands from a shell. This requires an exported alias in that shell. See below under "Usage from the CLI".  
  
  
## Prerequisites  

### Downloading the repository  

To get going, start Xcode and:  
  
  1. Click on `'Integrate'`.
  2. Select `'Clone'`.
  3. Enter the http address for this repository: "https://github.com/SwiftProjectOrganization/Stan".  
  4. Click `'Clone'`.  

The repository will be downloaded and the project will open in Xcode.  
  
### Setup  

  1. Stan's cmdstan expects an environment variable `"CMDSTAN"` to point to the cmdstan directory, see references 1 and 2 below on how to install cmdstan. Note that you can also define environment variables within Xcode. These won't work when running `'stan'` from a shell.
      
  2. Build and run the project.
      
  3. Append to your CMDSTAN definition in your .cshrc an `'alias'` and one more environment variable `'STAN_CASES'`:
  
```.zshrc

export CMDSTAN=/Users/rob/Projects/StanSupport/cmdstan/
launchctl setenv CMDSTAN /Users/rob/Projects/StanSupport/cmdstan/

alias stan="/Users/rob/Library/Developer/Xcode/DerivedData/Stan-fdgdldomabzygigaljlpkwxuqklx/Build/Products/Debug/Stan"

export STAN_CASES="/Users/rob/Documents/StanCases"
launchctl setenv STAN_CASES /Users/rob/Documents/StanCases
```


  4. Swift `'stan ...'` expects files at certain places:
  
All commands read input files and store result files by <model>, e.g. `"bernoulli"` or `"chimpanzees"`. It expects these files in `"~/Documents/<STAN_CASES>/<model>/[Preliminaries|Results]"`.

If the environment variable STAN_CASES is not defined, `"StanCases"` will be used.

In `"~/Documents/<STAN_CASES>/<model>/Preliminaries"` 3 files can be present:

    1. `"<model>.csv"`: A .csv file containing the data for the <model>.
    2. `"<model>.alist.R"`: A .R fragment containing an R alist as used in `'rethinking'`.
    3. `"<model>.ulam.swift"`: Intermediate file for debugging or handcoding Ulam DSL.
    
    If there is an `"<model>.csv"` file, the command `'csv2json'` will create a `"<model>.data.json"` file in the Results subdirectory for <model>.
    
    If there is a `"<model>.alist.R"` file, the command `'stancode'` will create a `"Results/<model>.stan"` file.
    
    Another option is to use the `'ulam'` command. This pipeline is useful for debugging and compiling hand generated smoke files (see below Ulam DSL).

In `"~/Documents/<STAN_CASES>/<model>/Results"` at least 2 files must be present before the cmdstan pipeline can be used:

    1. `"<model>.data.json"`: If data is needed for the model.
    2. `"<model>.stan"`: Stan language program.
    
    Using the cmdstan pipeline many other files can and will be generated in the Results subdirectory.

            
## Usage  

The package can be used from the CLI (Terminal) or from within Xcode.

### Usage from the CLI

Help is available with `'stan -h'` or `'stan compile -h'`.

```.zshrc
rob@Rob-Travel-M5 ~ % stan -h
OVERVIEW: A wrapper for running cmdstan.

USAGE: stan <subcommand>

OPTIONS:
  --version                 Show the version.
  -h, --help                Show help information.

SUBCOMMANDS:
  compile                   Compile the Stan model.
  sample                    Sample the Stan model.
  optimize                  Optimize the Stan model.
  pathfinder                Use Pathfinder approximation.
  stansummary               Run the Stan summary program.
  csv2json                  Read Preliminaries/<model>.csv, writes Results/<model>.data.json.
  dsl2stan                  Compile a Preliminaries/*.ulam.swift, write Results/<model>.stan.
  alist2dsl                 Translate Preliminaries/<model>.alist.R into  Preliminaries/<Model>.ulam.swift.
  stancode                  Translate Preliminaries/<model>.alist.R straight to Results/<model>.stan (in-process, no swiftc).
  ulam                      Run one of the built-in ulam DSL demos (--model Bernoulli|Poisson|Binomial|UCB|Dmvnorm).
  test (default)            Test the CLI functions.

  See 'stan help <subcommand>' for detailed help.
rob@Rob-Travel-M5 ~ % 
```

If the appropriate files are present, a typical Terminal session could continue with:

1. `'stan compile --model=bernoulli'`
2. `'stan sample --model=bernoulli'`

or

3. `'stan ulam --model=chimpanzees'`

    The `'ulam'` pipeline uses Swift to first create an intermediate `'Ulam smoke driver'` which takes roughly 6 seconds longer. But I do like the option to generate Ulam DSL where the structure of the Stan model is clearly labeled and the input data file checked.

### Usage from within Xcode

Edit the schema arguments, e.g. `'compile --model=bernoulli'` and press "build-and-run".


## Ulam DSL

The package includes a Swift port of Richard McElreath's R `ulam()` (from the `rethinking` package).

Instead of writing `.stan` source by hand, you can:

    1. use the `'alist2stan'` command to directly translate a `"<model>/Preliminaries/<model>.alist.R"` to an `"<model>/Results/<model.stan"` file

    2. define the model with a Swift result-builder DSL; the generator emits both `"<model>.stan"` and `"<model>.data.json"` under `"<model>/Results/"` and then hands off to the existing `compile` and `sample` pipeline steps.

The ulam pipeline is split into sub-commands:

    1. `alist2stan` (R "alist" → .stan file)
    2. `alist2dsl` (R "alist" → Swift smoke driver) 
    3. `dsl2stan` (Swift smoke driver → ".stan")
    
    and
    
    4. `csv2json` (CSV → `.data.json`), then `ulam` chains them with `compile` + `sample`.


Canonical Statistical Rethinking opening example — Bernoulli + logit as a smoke file:

```swift
import Foundation

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


## Documentation

- [`CLAUDE.md`](CLAUDE.md) — architecture notes for the `Stan` Swift package (Commands / Methods / Support layering, the `(String, String)` return convention, the Ulam module layout, etc.). Loaded by Claude Code sessions in this workspace.
- [`TODO.md`](TODO.md) — forward-looking punch list for topics beyond v1.5 scope (SUR, LKJ-Cholesky, post-sampling helpers, etc.).


## References

1. [Stan](https://mc-stan.org)
2. [cmdstan](https://mc-stan.org/docs/2_37/cmdstan-guide/)
3. McElreath, *Statistical Rethinking* (2nd ed.) — `ulam()` is from the accompanying R `rethinking` package.
