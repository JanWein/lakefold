# Contributing to DataRaft

The root is the `dataraft` metapackage. Implementations live in `packages/` and
must remain independently installable. Add behavior to its owning component;
keep the umbrella package free of engines. Use explicit namespace references
across package boundaries and register S3 methods with their generic's owner.

From the repository root:

```r
source("scripts/install-family.R")
source("scripts/check.R")
```

Use the Posit R package development and testing skills. Format R code with Air.
Edit roxygen source comments, then run `roxygen2::roxygenise()` for the changed
component and the root when re-exports change. Do not edit generated Rd or
NAMESPACE files. Update the owning package's NEWS for behavior changes.

The umbrella tests exercise interactions between packages; component tests
cover independent use. Integration fixtures may inspect internal functions,
but production code must use declared imports and extension protocols.
CI checks every source package, an installation with only core dependencies,
and PostgreSQL coordination. Coverage artifacts are reported per component.

Keep the three shared guides focused. Generate README.md from README.Rmd.
Before 1.0 there are no compatibility aliases, migration guides or stored-format
upgrades. Remove obsolete behavior and documentation with its replacement.
