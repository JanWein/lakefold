# DuckLake folder usability regression

This is an executed simulation, not an independent human study. The scope is a
local DuckLake with DuckDB's real DuckLake extension, optional custom layers,
checked publication, closing and reopening, another publication, and read-only
access. Remote S3/PostgreSQL services are outside this test.

The baseline reproduced the previous failure: custom layers were forgotten on
`tw_open_lake(folder)`, default schemas were added, and publishing again into `core`
failed although the earlier data remained readable.

The implementation has one path/configuration resolver for `tw_open_lake()`,
`tw_setup_lake(path = )` and `tw_lake_config(path = )`. It preserves ordered layers and
named roles as well as the backend. Different explicit choices and stale config
objects fail before opening the database. No source callbacks are needed.

Iteration 1 fixes the baseline round trip. Iteration 2 checks the same path with
a real DuckLake and extends it to read-only access, named layer roles, stale
definitions, corrupt configuration and legacy folders. The tutorial in
`vignettes/create-ducklake.Rmd` is the canonical user path; its extracted
`inst/examples/create_ducklake.R` is also executed against an installed package.

Acceptance: create `raw`, `staging`, `core`, `marts`; store 350 in `core`; close;
open using only the folder; store 380 in `core`; read the original 350 and the
current 380; verify no `validated` or `products` schema was introduced. A separate
R process must read the same saved settings and data using only the folder.

Executed result: the installed-package tutorial and rendered vignette completed.
A separate creation process stored 350; a fresh process reopened using only the
folder, retained the four custom layers, stored 380 in `core`, read back the
original 350, and confirmed that no default `validated` or `products` schema
had been introduced. The real DuckLake engine was verified in the integration
test, rather than substituting the ordinary DuckDB backend.

Legacy format-1 folders lack the original layer order and role names. Default
folders upgrade on writable open. Custom folders request the original layers
once; the suggested schema names are evidence, not an inferred business ordering.
Read-only access never migrates the marker. Format 2 prevents older package
versions from silently interpreting custom folders as default-layer folders.
