library(lakefold)

required <- c("DATALOOM_S3_BUCKET", "DATALOOM_S3_ENDPOINT")
missing <- required[!nzchar(Sys.getenv(required))]
if (length(missing)) {
  stop("Set configuration variables: ", paste(missing, collapse = ", "))
}

# Credentials are supplied by Workbench / Connect / CI environment variables.
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# Optional AWS_SESSION_TOKEN

# Start locally while a PostgreSQL service is not yet available.
catalog <- dl_catalog_duckdb("metadata.ducklake")

# For the later PostgreSQL deployment, replace ONLY the configuration constructor:
# Set DUCKLAKE_PG_CONNECTION in the runtime, not in Git.
# Example format: host=... port=5432 dbname=... user=... password=... sslmode=require
# catalog <- dl_catalog_postgres("DUCKLAKE_PG_CONNECTION")
# This connects to a NEW catalog. It does NOT migrate an existing local catalog.

lake <- dl_setup(
  catalog = catalog,
  storage = dl_storage_s3(
    bucket = Sys.getenv("DATALOOM_S3_BUCKET"),
    prefix = Sys.getenv("DATALOOM_S3_PREFIX", "dataloom/dev"),
    endpoint = Sys.getenv("DATALOOM_S3_ENDPOINT"),
    region = Sys.getenv("AWS_DEFAULT_REGION", "eu-central-1")
  ),
  layers = c("raw", "validated", "products"),
  landing = "landing-cache"
)

# S3 Parquet storage uses DuckDB httpfs.
# S3 originals use paws.storage and conditional PutObject.
# Configure one writer process/job at a time for dataloom 0.2.
print(dl_capabilities(lake))
# dl_disconnect(lake)
