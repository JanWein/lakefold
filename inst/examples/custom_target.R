## ----setup, include=FALSE-----------------------------------------------------
library(lakefold)
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")


## ----target-------------------------------------------------------------------
rds_target <- function(path) {
  structure(list(path = path), class = "example_rds_target")
}

dl_check_component.example_rds_target <- function(x, ...) {
  if (
    !is.character(x$path) ||
      length(x$path) != 1L ||
      is.na(x$path) ||
      !nzchar(x$path)
  ) {
    stop("The RDS target needs one non-empty path.")
  }
  if (!dir.exists(dirname(x$path))) {
    stop("Create the destination directory first.")
  }
  if (file.exists(x$path)) {
    stop("Choose a new directory; this adapter never replaces data.")
  }
  invisible(x)
}

dl_inspect.example_rds_target <- function(x, ...) {
  list(type = "new RDS directory", path = x$path)
}

dl_write_target.example_rds_target <- function(target, data, context, ...) {
  # Recheck because availability can change after preflight.
  dl_check_component(target)
  if (!dir.create(target$path, showWarnings = FALSE)) {
    stop("The destination could not be created exclusively.")
  }
  complete <- FALSE
  on.exit(if (!complete) unlink(target$path, recursive = TRUE))
  output <- file.path(target$path, "data.rds")
  saveRDS(data, output)
  complete <- TRUE
  list(path = output, product = context$product, rows = nrow(data))
}


## ----register-----------------------------------------------------------------
registerS3method(
  "dl_check_component",
  "example_rds_target",
  dl_check_component.example_rds_target,
  envir = asNamespace("lakefold")
)
registerS3method(
  "dl_inspect",
  "example_rds_target",
  dl_inspect.example_rds_target,
  envir = asNamespace("lakefold")
)
registerS3method(
  "dl_write_target",
  "example_rds_target",
  dl_write_target.example_rds_target,
  envir = asNamespace("lakefold")
)


## ----execute------------------------------------------------------------------
path <- tempfile("orders-output-")
product <- dl_product("orders") |>
  dl_add_source(data.frame(id = 1:2, amount = c(10, 20))) |>
  dl_add_quality(~ amount >= 0) |>
  dl_add_target(rds_target(path))

result <- dl_run(product)
stopifnot(result$status == "published")
stopifnot(identical(
  readRDS(result$outputs$path),
  as.data.frame(dl_collect(result))
))
result$outputs
unlink(path, recursive = TRUE)


## ----custom-quality-----------------------------------------------------------
# In a real adapter, obtain these counts from your external engine.
dl_run_quality.example_quality <- function(rule, data, ...) {
  native <- dl_rule(
    rule$name,
    function(data) {
      dl_quality_counts(sum(data$amount < 0 | is.na(data$amount)), nrow(data))
    },
    severity = rule$severity,
    max_failure = rule$max_failure
  )
  evidence <- dl_run_quality(native, data)
  evidence$engine <- "example"
  evidence
}
