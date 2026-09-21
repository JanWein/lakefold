# dataraft.adapters

Read and write external data through database, API, Parquet and pins adapters. Each adapter declares its engine dependency. Borrowed database connections remain owned by the caller.

This is an independently installable DataRaft component. The `dataraft`
metapackage provides the shared introduction and re-exports the family API.
See `help(package = "dataraft.adapters")` for the component reference.
