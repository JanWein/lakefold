# Development release policy

Version 0.8 renames **lakefold** to **tidyweave** and replaces experimental
prefixed composition and pipeline interfaces with one product grammar.

The package has not reached its first stable release candidate. There are no
backward-compatibility aliases or stable-API promises during this stage. Update
project definitions against the current documentation and rerun their checks.
Do not assume that renaming a package also migrates a deployed lake, report
archive, remote service or deployment configuration.

Start with the [current lessons](https://janwein.github.io/tidyweave/articles/get-started.html)
and [API overview](API.md). The [validation record](VALIDATION.md) describes
verified behavior and its limits. Stored-data integrity remains a requirement
even while the public API changes.

## Local folder settings

New and upgraded folders persist backend, ordered layers and layer roles in
configuration format 2. Older tidyweave versions reject that format; do not
expect a package downgrade to open an upgraded folder. Legacy custom-layer
folders require their original layers once on a writable open. See
[Create a DuckLake](https://janwein.github.io/tidyweave/articles/create-ducklake.html).


## Metadata schema 4: model products and coordinated PostgreSQL writers

Writable open upgrades the registry marker to 4 without rewriting historical
releases. Older package versions reject the newer schema. Read-only opening
never migrates; open once with the new writable version before reconnecting
read-only. Back up metadata and retained data before a deployment upgrade and
stop old clients during the transition.

PostgreSQL writes now require optional RPostgres, use a database-scoped advisory
lock, and accept libpq keyword/value connection strings or service names. Existing
DuckDB-only workflows have no PostgreSQL dependency. Complete model publication
is atomic; independent workflow products still commit separately.
