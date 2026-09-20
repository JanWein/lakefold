library(tidyweave)

guide_source <- function(data) {
  structure(list(data = data), class = "guide_source")
}
read_source.guide_source <- function(source, ...) source$data
check_component.guide_source <- function(x, ...) {
  if (!is.data.frame(x$data)) {
    stop("Supply an R data frame.")
  }
  invisible(x)
}
inspect.guide_source <- function(x, ...) {
  list(type = "example reader", columns = names(x$data))
}
capabilities.guide_source <- function(x, ...) {
  component_capabilities(
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
check_component.guide_target <- function(x, ...) {
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
inspect.guide_target <- function(x, ...) {
  list(type = "new RDS directory", path = x$path)
}
capabilities.guide_target <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
write_target.guide_target <- function(target, data, context, ...) {
  check_component(target)
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
  rule <- quality_rule("nonnegative", ~ amount >= 0)
  class(rule) <- c("guide_quality", class(rule))
  rule
}
run_quality.guide_quality <- function(rule, data, ...) {
  # A real external engine would supply these aggregate counts.
  failed <- sum(is.na(data$amount) | data$amount < 0)
  total <- nrow(data)
  native <- quality_rule(
    rule$name,
    function(data) quality_counts(failed, total),
    severity = rule$severity,
    max_failure = rule$max_failure
  )
  evidence <- run_quality(native, data)
  evidence$engine <- "example"
  evidence
}

methods <- list(
  read_source.guide_source = read_source.guide_source,
  check_component.guide_source = check_component.guide_source,
  inspect.guide_source = inspect.guide_source,
  capabilities.guide_source = capabilities.guide_source,
  check_component.guide_target = check_component.guide_target,
  inspect.guide_target = inspect.guide_target,
  capabilities.guide_target = capabilities.guide_target,
  write_target.guide_target = write_target.guide_target,
  run_quality.guide_quality = run_quality.guide_quality
)
for (name in names(methods)) {
  registerS3method(
    sub("[.].*$", "", name),
    sub("^[^.]+[.]", "", name),
    methods[[name]],
    envir = asNamespace("tidyweave")
  )
}

workflow <- function(source, target = NULL, check = ~ amount >= 0) {
  product("orders") |>
    add_source(source) |>
    add_transform(function(data) transform(data, amount = amount * 2)) |>
    add_quality(check) |>
    set_target(target)
}
input <- data.frame(id = 1:2, amount = c(10, 20))
path <- tempfile("custom-target-")
native <- run(workflow(input))
extended <- run(workflow(
  guide_source(input),
  guide_target(path),
  guide_quality()
))
stopifnot(identical(collect(native), collect(extended)))
stopifnot(identical(
  readRDS(extended$outputs$path),
  as.data.frame(collect(native))
))

flags <- capabilities(guide_target(tempfile()))
stopifnot(
  setequal(names(flags), names(component_capabilities())),
  all(vapply(flags, function(x) is.logical(x) && length(x) == 1L, logical(1)))
)

blocked_path <- tempfile("blocked-target-")
bad <- workflow(
  guide_source(data.frame(id = 1L, amount = -1)),
  guide_target(blocked_path),
  guide_quality()
)
blocked <- run(bad, stop_on_failure = FALSE)
stopifnot(blocked$status == "blocked", !file.exists(blocked_path))

unlink(path, recursive = TRUE)
method_table <- get(".__S3MethodsTable__.", envir = asNamespace("tidyweave"))
rm(list = names(methods), envir = method_table)
