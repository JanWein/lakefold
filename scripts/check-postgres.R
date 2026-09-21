# Run against a dedicated, disposable PostgreSQL database and shared test folder.
# The database must be empty; never point this script at an existing lake.
library(dataraft)
stopifnot(nzchar(Sys.getenv("DATARAFT_TEST_PG_CONNECTION")))
root <- normalizePath("check", mustWork = FALSE)
root <- file.path(root, "postgres")
dir.create(root, recursive = TRUE, showWarnings = FALSE)
config <- dr_lake_config(
  dr_registry_postgres("DATARAFT_TEST_PG_CONNECTION", lock_timeout = 30),
  dr_storage_local(file.path(root, "data")),
  landing = file.path(root, "landing"),
  backend = "ducklake"
)
lake <- dr_open_lake(config)
dr_close_lake(lake)
worker <- normalizePath("scripts/postgres-worker.R")
launch <- function(job, number) {
  input <- file.path(root, paste0("job-", number, ".rds"))
  output <- file.path(root, paste0("out-", number, ".rds"))
  saveRDS(c(list(config = config, output = output), job), input)
  process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c(worker, input),
    stdout = file.path(root, paste0(number, ".log")),
    stderr = "2>&1"
  )
  list(process = process, output = output)
}
finish <- function(job) {
  job$process$wait(timeout = 120000)
  if (job$process$is_alive()) {
    job$process$kill()
    stop("Worker timed out")
  }
  stopifnot(job$process$get_exit_status() == 0L)
  result <- readRDS(job$output)
  print(result)
  result
}
# Independent clients can publish without duplicate registration or schema races.
a <- launch(list(action = "publish", asset = "left", value = 1L), 1)
b <- launch(list(action = "publish", asset = "right", value = 2L), 2)
stopifnot(finish(a)$status == "published", finish(b)$status == "published")
# Nested publication reuses the process coordinator instead of waiting on itself.
upstream <- dr_product("upstream", data.frame(id = 1L)) |> dr_set_target(config)
stopifnot(
  dr_publish(dr_product("downstream", upstream), to = config)$status ==
    "published"
)
first <- dr_publish(dr_product("shared", data.frame(id = 1L)), to = config)
a <- launch(
  list(action = "publish", asset = "shared", value = 2L, previous = first),
  3
)
b <- launch(
  list(action = "publish", asset = "shared", value = 3L, previous = first),
  4
)
results <- list(finish(a), finish(b))
stopifnot(
  sum(vapply(results, function(x) x$status == "published", logical(1))) == 1L,
  sum(vapply(
    results,
    function(x) "dr_publication_conflict" %in% x$error_class,
    logical(1)
  )) ==
    1L
)
# Same reviewed report is idempotent even when two clients issue it together.
a <- launch(list(action = "report", previous = first), 5)
b <- launch(list(action = "report", previous = first), 6)
stopifnot(finish(a)$status == "reported", finish(b)$status == "reported")
# An interrupted session relinquishes the database lock; no manual lock-file cleanup.
ready <- file.path(root, "writer-ready")
holder <- launch(list(action = "hold", ready = ready), 7)
deadline <- Sys.time() + 15
while (!file.exists(ready) && Sys.time() < deadline) {
  Sys.sleep(0.1)
}
stopifnot(file.exists(ready))
short_wait <- config
short_wait$catalog$lock_timeout <- 0
busy <- tryCatch(
  dr_publish(dr_product("busy", data.frame(id = 1L)), to = short_wait),
  error = identity
)
stopifnot(inherits(busy$result$error, "dr_writer_busy"))
reader <- dr_open_lake(config, read_only = TRUE)
stopifnot(dr_read_release(reader, "shared", first$release_id)$id == 1L)
dr_close_lake(reader)
holder$process$kill()
holder$process$wait(timeout = 10000)
stopifnot(
  dr_publish(
    dr_product("after_crash", data.frame(id = 1L)),
    to = config
  )$status ==
    "published"
)
lake <- dr_open_lake(config)
stopifnot(
  nrow(dr_releases(lake, "shared")) == 2L,
  sum(dr_registry(lake, "reports")$id == "same-report") == 1L,
  identical(dr_collect(first)$id, 1L)
)
model <- dm::dm(
  customers = data.frame(id = 1:2),
  policies = data.frame(id = 1:2)
) |>
  dm::dm_add_pk(customers, id) |>
  dm::dm_add_fk(policies, id, customers)
original <- dr_publish(dr_product("portfolio", model), to = lake)
blocked <- dr_publish(
  dr_product("portfolio", model),
  to = lake,
  sources = list(customers = data.frame(id = 1L)),
  stop_on_failure = FALSE
)
stopifnot(
  blocked$status == "blocked",
  nrow(dr_releases(lake, "portfolio")) == 1L,
  identical(dr_collect(original)$policies$id, 1:2)
)
dr_close_lake(lake)
cat(
  "PostgreSQL/DuckLake: parallel clients, stale correction, report identity and model gate passed.\n"
)
