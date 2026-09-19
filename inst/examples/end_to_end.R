# Run after installing lakefold. The example uses synthetic data only.
library(lakefold)
library(dplyr)

root <- Sys.getenv(
  "DATALOOM_DEMO_DIR",
  unset = file.path(tempdir(), "lakefold-demo")
)
dir.create(root, recursive = TRUE, showWarnings = FALSE)
lake <- dl_setup(
  catalog = dl_catalog_duckdb(file.path(root, "metadata.ducklake")),
  storage = dl_storage_local(file.path(root, "tables")),
  landing = file.path(root, "landing"),
  backend = Sys.getenv("DATALOOM_BACKEND", unset = "ducklake")
)

input <- file.path(root, "reserves.csv")
good <- data.frame(
  policy_id = c("V001", "V002", "V003"),
  company = c("Alpha", "Alpha", "Beta"),
  date = as.Date(rep("2026-08-31", 3)),
  reserve = c(100000, 250000, 175000)
)
write.csv(good, input, row.names = FALSE)

contract <- dl_contract(
  id = "risk.reserves_contract",
  version = "1.0.0",
  owner = "Risk Management",
  producer = "data-producer@example.com",
  description = "Policy reserves by company and business date.",
  grain = "One policy at one business date.",
  columns = c(
    policy_id = "character",
    company = "character",
    date = "Date",
    reserve = "numeric"
  ),
  key = c("policy_id", "date"),
  max_age_hours = 48,
  rules = list(dl_rule("reserve_nonnegative", function(data) {
    counts <- data |>
      summarise(
        total = n(),
        failed = sum(as.integer(reserve < 0), na.rm = TRUE)
      ) |>
      collect()
    dl_quality_counts(counts$failed, counts$total)
  }))
)

source <- dl_source("risk.reserves_export", input, reader = function(path) {
  read.csv(path, colClasses = c("character", "character", "Date", "numeric"))
})
pipeline <- dl_pipeline(
  "risk.reserves_import",
  lake,
  code_version = "demo-v1"
) |>
  dl_step_land(source) |>
  dl_step_extract(into = "raw") |>
  dl_step_validate(contract) |>
  dl_step_publish(
    "risk.reserves_validated",
    mode = "replace_partition",
    partition_by = "date"
  )

first <- dl_run(pipeline, lake, business_date = "2026-08-31")
print(first)

product <- dl_product(
  "risk.reserves",
  inputs = c(reserves = "risk.reserves_validated"),
  build = function(inputs) inputs$reserves,
  contract = contract,
  code_version = "demo-v1"
)
dl_build(lake, product, business_date = "2026-08-31")

reserve <- dl_metric(
  "risk.total_reserve",
  product = "risk.reserves",
  expr = sum(reserve, na.rm = TRUE),
  dimensions = "company",
  time_column = "date",
  time_behavior = "stock",
  unit = "EUR",
  owner = "Risk Management",
  description = "Total reserve at the selected business date.",
  approved = TRUE,
  code_version = "demo-v1"
)
result <- dl_measure(
  lake,
  reserve,
  by = "company",
  at = as.Date("2026-08-31")
)
print(result)
report <- dl_report_release(
  lake,
  "monthly-risk-2026-08-v1",
  list(reserve = result),
  code_version = "demo-v1"
)

# Invalid delivery: stays visible in run history but does not change published data.
bad <- good
bad$reserve[1] <- -999
write.csv(bad, input, row.names = FALSE)
blocked <- dl_run(pipeline, lake, stop_on_failure = FALSE)
stopifnot(blocked$status == "blocked")
stopifnot(
  sum(collect(dl_tbl(lake, "risk.reserves_validated"))$reserve) == 525000
)
print(blocked$quality)

# Corrected delivery creates a new immutable release.
corrected <- good
corrected$reserve[1] <- 120000
write.csv(corrected, input, row.names = FALSE)
fixed <- dl_run(pipeline, lake, business_date = "2026-08-31")
stopifnot(fixed$status == "published")
stopifnot(
  sum(
    collect(dl_tbl(lake, "risk.reserves_validated", first$release_id))$reserve
  ) ==
    525000
)
stopifnot(
  dl_run(pipeline, lake, business_date = "2026-08-31")$status == "cached"
)

# The product intentionally stays on its prior release until it is rebuilt.
print(dl_freshness(lake))
dl_catalog_export(lake, file.path(root, "catalog.json"))
dl_disconnect(lake)
message("Demo completed. Catalog snapshot: ", file.path(root, "catalog.json"))
# In a separate interactive process:
# dl_catalog(snapshot = file.path(root, "catalog.json"))
