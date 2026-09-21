# Run after installing dataraft. Synthetic local workload; no external services.
# Example: benchmark_dataraft(100000, "duckdb")
benchmark_dataraft <- function(n = 100000L, backend = "duckdb") {
  stopifnot(length(n) == 1L, is.finite(n), n >= 10, n <= .Machine$integer.max)
  n <- as.integer(n)
  root <- tempfile("dataraft-benchmark-")
  lake <- dataraft::dr_open_lake(root, backend = backend)
  on.exit({
    dataraft::dr_close_lake(lake)
    unlink(root, recursive = TRUE)
  })
  data <- data.frame(
    id = seq_len(n),
    month = as.Date("2026-08-31"),
    amount = (seq_len(n) %% 1000) / 10
  )
  elapsed <- numeric()
  elapsed[["first_write"]] <- system.time(dataraft::dr_write_data(
    lake,
    data,
    "orders",
    partition_by = "month"
  ))[["elapsed"]]
  data$amount[seq_len(10)] <- data$amount[seq_len(10)] + 1
  elapsed[["partition_correction"]] <- system.time(dataraft::dr_write_data(
    lake,
    data,
    "orders",
    partition_by = "month"
  ))[["elapsed"]]
  elapsed[["comparison"]] <- system.time(
    difference <- dataraft::dr_compare(lake, "orders", key = c("id", "month"))
  )[["elapsed"]]
  stopifnot(difference$counts[["changed"]] == 10)
  files <- list.files(
    root,
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE
  )
  data.frame(
    backend = backend,
    rows = n,
    operation = names(elapsed),
    seconds = unname(elapsed),
    folder_bytes_before_close = sum(file.info(files)$size, na.rm = TRUE)
  )
}
