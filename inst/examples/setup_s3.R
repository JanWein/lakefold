library(dataraft)

required <- c("DATARAFT_S3_BUCKET", "DATARAFT_S3_ENDPOINT")
missing <- required[!nzchar(Sys.getenv(required))]
if (length(missing)) {
  stop("Set configuration variables: ", paste(missing, collapse = ", "))
}

# Credentials are supplied by Workbench / Connect / CI environment variables.
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# Optional AWS_SESSION_TOKEN

# Start locally while a PostgreSQL service is not yet available.
catalog <- dr_registry_duckdb("metadata.ducklake")

# For the later PostgreSQL deployment, replace ONLY the configuration constructor:
# Set DUCKLAKE_PG_CONNECTION in the runtime, not in Git.
# Example format: host=... port=5432 dbname=... user=... password=... sslmode=require
# catalog <- dr_registry_postgres("DUCKLAKE_PG_CONNECTION")
# This configuration connects to a new catalog.

lake <- dr_open_lake(dr_lake_config(
  catalog = catalog,
  storage = dr_storage_s3(
    bucket = Sys.getenv("DATARAFT_S3_BUCKET"),
    prefix = Sys.getenv("DATARAFT_S3_PREFIX", "dataraft/dev"),
    endpoint = Sys.getenv("DATARAFT_S3_ENDPOINT"),
    region = Sys.getenv("AWS_DEFAULT_REGION", "eu-central-1")
  ),
  layers = c("raw", "validated", "products"),
  landing = "landing-cache"
))

# S3 Parquet storage uses DuckDB httpfs.
# S3 originals use paws.storage and conditional PutObject.
# Configure one writer process/job at a time for the dataraft registry.
print(dr_capabilities(lake))
# dr_close_lake(lake)
