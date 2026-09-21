library(tidyweave)

guide_source <- function(data) {
  structure(list(data = data), class = "guide_source")
}
tw_read_source.guide_source <- function(source, ...) source$data
tw_check_component.guide_source <- function(x, ...) {
  if (!is.data.frame(x$data)) {
    stop("Supply an R data frame.")
  }
  invisible(x)
}
tw_inspect.guide_source <- function(x, ...) {
  list(type = "example reader", columns = names(x$data))
}
tw_capabilities.guide_source <- function(x, ...) {
  tw_component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}

guide_target <- function(path) {
  structure(list(path = path), class = "guide_target")
}
tw_check_component.guide_target <- function(x, ...) {
  if (
    !is.character(x$path) ||
      length(x$path) != 1L ||
      is.na(x$path) ||
      !nzchar(x$path)
  ) {
    stop("Supply one destination path.")
  }
  if (!dir.exists(dirname(x$path))) {
    stop("Create the parent directory first.")
  }
  if (file.exists(x$path)) {
    stop("Choose a new directory for this output.")
  }
  invisible(x)
}
tw_inspect.guide_target <- function(x, ...) {
  list(type = "new RDS directory", path = x$path)
}
tw_capabilities.guide_target <- function(x, ...) {
  tw_component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
tw_write_target.guide_target <- function(target, data, context, ...) {
  tw_check_component(target)
  if (!dir.create(target$path, showWarnings = FALSE)) {
    stop("Could not create the new destination.")
  }
  complete <- FALSE
  on.exit(if (!complete) unlink(target$path, recursive = TRUE))
  path <- file.path(target$path, "data.rds")
  saveRDS(as.data.frame(data), path)
  complete <- TRUE
  list(path = path, product = context$product, rows = nrow(data))
}

guide_quality <- function() {
  rule <- tw_quality_rule("nonnegative", ~ amount >= 0)
  class(rule) <- c("guide_quality", class(rule))
  rule
}
tw_run_quality.guide_quality <- function(rule, data, ...) {
  # A real external engine would supply these aggregate counts.
  failed <- sum(is.na(data$amount) | data$amount < 0)
  total <- nrow(data)
  native <- tw_quality_rule(
    rule$name,
    function(data) tw_quality_counts(failed, total),
    severity = rule$severity,
    max_failure = rule$max_failure
  )
  evidence <- tw_run_quality(native, data)
  evidence$engine <- "example"
  evidence
}

methods <- list(
  tw_read_source.guide_source = tw_read_source.guide_source,
  tw_check_component.guide_source = tw_check_component.guide_source,
  tw_inspect.guide_source = tw_inspect.guide_source,
  tw_capabilities.guide_source = tw_capabilities.guide_source,
  tw_check_component.guide_target = tw_check_component.guide_target,
  tw_inspect.guide_target = tw_inspect.guide_target,
  tw_capabilities.guide_target = tw_capabilities.guide_target,
  tw_write_target.guide_target = tw_write_target.guide_target,
  tw_run_quality.guide_quality = tw_run_quality.guide_quality
)
for (name in names(methods)) {
  registerS3method(
    sub("[.].*$", "", name),
    sub("^[^.]+[.]", "", name),
    methods[[name]],
    envir = asNamespace("tidyweave")
  )
}

guide_workflow <- function(source, target = NULL, check = ~ amount >= 0) {
  tw_product("orders") |>
    tw_add_source(source) |>
    tw_add_transform(function(data) transform(data, amount = amount * 2)) |>
    tw_add_quality(check) |>
    tw_set_target(target)
}
input <- data.frame(id = 1:2, amount = c(10, 20))
path <- tempfile("custom-target-")
native <- tw_run(guide_workflow(input))
extended <- tw_run(guide_workflow(
  guide_source(input),
  guide_target(path),
  guide_quality()
))
stopifnot(identical(tw_collect(native), tw_collect(extended)))
stopifnot(identical(
  readRDS(extended$outputs$path),
  as.data.frame(tw_collect(native))
))

flags <- tw_capabilities(guide_target(tempfile()))
stopifnot(
  setequal(names(flags), names(tw_component_capabilities())),
  all(vapply(flags, function(x) is.logical(x) && length(x) == 1L, logical(1)))
)

blocked_path <- tempfile("blocked-target-")
bad <- guide_workflow(
  guide_source(data.frame(id = 1L, amount = -1)),
  guide_target(blocked_path),
  guide_quality()
)
blocked <- tw_run(bad, stop_on_failure = FALSE)
stopifnot(blocked$status == "blocked", !file.exists(blocked_path))

unlink(path, recursive = TRUE)
method_table <- get(".__S3MethodsTable__.", envir = asNamespace("tidyweave"))
rm(list = names(methods), envir = method_table)
