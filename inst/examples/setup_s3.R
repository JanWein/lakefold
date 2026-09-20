library(tidyweave)

required <- c("TIDYWEAVE_S3_BUCKET", "TIDYWEAVE_S3_ENDPOINT")
missing <- required[!nzchar(Sys.getenv(required))]
if (length(missing)) {
  stop("Set configuration variables: ", paste(missing, collapse = ", "))
}

# Credentials are supplied by Workbench / Connect / CI environment variables.
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# Optional AWS_SESSION_TOKEN

# Start locally while a PostgreSQL service is not yet available.
catalog <- registry_duckdb("metadata.ducklake")

# For the later PostgreSQL deployment, replace ONLY the configuration constructor:
# Set DUCKLAKE_PG_CONNECTION in the runtime, not in Git.
# Example format: host=... port=5432 dbname=... user=... password=... sslmode=require
# catalog <- registry_postgres("DUCKLAKE_PG_CONNECTION")
# This connects to a NEW catalog. It does NOT migrate an existing local catalog.

lake <- setup_lake(
  catalog = catalog,
  storage = storage_s3(
    bucket = Sys.getenv("TIDYWEAVE_S3_BUCKET"),
    prefix = Sys.getenv("TIDYWEAVE_S3_PREFIX", "tidyweave/dev"),
    endpoint = Sys.getenv("TIDYWEAVE_S3_ENDPOINT"),
    region = Sys.getenv("AWS_DEFAULT_REGION", "eu-central-1")
  ),
  layers = c("raw", "validated", "products"),
  landing = "landing-cache"
)

# S3 Parquet storage uses DuckDB httpfs.
# S3 originals use paws.storage and conditional PutObject.
# Configure one writer process/job at a time for the tidyweave registry.
print(capabilities(lake))
# disconnect_lake(lake)
