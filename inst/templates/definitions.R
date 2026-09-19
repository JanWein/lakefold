library(lakefold)

# Customize paths and the code version before scheduling.
# The input file must contain vertrag;stichtag;reserve as CSV columns.
input_path <- Sys.getenv("DATALOOM_INPUT", "bestand.csv")
business_date <- Sys.getenv("DATALOOM_BUSINESS_DATE", as.character(Sys.Date()))
code_version <- Sys.getenv("DATALOOM_CODE_VERSION", "project-v1")

lake <- dl_setup(
  dl_catalog_duckdb("metadata.ducklake"),
  dl_storage_local("data"),
  landing = "landing"
)

contract <- dl_contract(
  "risk.bestand_contract",
  "1.0.0",
  owner = "Risk Management",
  producer = "data-producer@example.com",
  description = "Vertragsreserven je Stichtag.",
  grain = "Ein Vertrag an einem Stichtag.",
  columns = c(vertrag = "character", stichtag = "Date", reserve = "numeric"),
  key = c("vertrag", "stichtag"),
  rules = list(dl_rule("nonnegative", function(data) {
    counts <- dplyr::collect(dplyr::summarise(
      data,
      total = dplyr::n(),
      failed = sum(as.integer(reserve < 0), na.rm = TRUE)
    ))
    dl_quality_counts(counts$failed, counts$total)
  }))
)

pipeline <- dl_pipeline("risk.import", lake, code_version = code_version) |>
  dl_step_land(dl_source("risk.export", input_path, reader = function(path) {
    read.csv2(path, colClasses = c("character", "Date", "numeric"))
  })) |>
  dl_step_extract() |>
  dl_step_validate(contract) |>
  dl_step_publish(
    "risk.bestand",
    mode = "replace_partition",
    partition_by = "stichtag"
  )

dl_disconnect(lake)
rm(lake)
# Optional: define notify <- function(event) { ... existing transport ... }
