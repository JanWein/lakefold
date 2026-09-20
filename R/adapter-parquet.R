#' Read Parquet files or an Arrow dataset
#'
#' Arrow handles local files, directories and supported object-storage URIs.
#' Configure remote credentials through Arrow. A lazy source returns an Arrow
#' Dataset; use dplyr verbs and [collect()] to materialize it. Remote availability
#' is checked when reading, not during structural validation.
#' @param path File, dataset directory or Arrow-supported URI.
#' @param lazy Return a lazy Dataset instead of an ordinary tibble.
#' @param ... Named arguments to [arrow::open_dataset()].
#' @returns A source specification for [add_source()].
#' @export
#' @examplesIf requireNamespace("arrow", quietly = TRUE)
#' path <- tempfile(fileext = ".parquet")
#' arrow::write_parquet(data.frame(id = 1:2), path)
#' read_source(source_parquet(path)) |> collect()
#' unlink(path)
source_parquet <- function(path, lazy = TRUE, ...) {
  scalar(path, "path")
  flag(lazy, "lazy")
  options <- list(...)
  adapter_named_options(options, c("sources", "format"))
  structure(
    list(path = path, lazy = lazy, options = options),
    class = "tw_parquet_source"
  )
}

#' @export
check_component.tw_parquet_source <- function(x, ...) {
  need("arrow")
  if (!adapter_remote_path(x$path) && !file.exists(x$path)) {
    abort("The Parquet source is missing. Check its path.")
  }
  invisible(x)
}

#' @export
read_source.tw_parquet_source <- function(source, ...) {
  check_component(source)
  data <- do.call(
    arrow::open_dataset,
    c(list(sources = source$path, format = "parquet"), source$options)
  )
  if (source$lazy) data else dplyr::collect(data)
}

#' @export
inspect.tw_parquet_source <- function(x, ...) {
  list(type = "Parquet", path = adapter_path_descriptor(x$path), lazy = x$lazy)
}

#' @export
capabilities.tw_parquet_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = x$lazy,
    transactions = FALSE,
    partition = TRUE,
    immutable = FALSE
  )
}

#' Publish a single local Parquet file
#'
#' Writes a temporary file beside its destination, then publishes with one
#' filesystem rename. Writing or rename failure preserves the existing file.
#' Atomic replacement depends on the filesystem: platforms that cannot replace
#' an existing file this way report an error. Coordinate concurrent writers
#' externally. Remote URIs and dataset-directory writes are unsupported here.
#' @param path Local destination file. Its parent directory must already exist.
#' @param overwrite Allow replacing an existing file; defaults to `FALSE`.
#' @param ... Named arguments to [arrow::write_parquet()].
#' @returns A target specification for [set_target()].
#' @export
#' @examplesIf requireNamespace("arrow", quietly = TRUE)
#' path <- tempfile(fileext = ".parquet")
#' product("orders") |>
#'   add_source(data.frame(id = 1:2)) |>
#'   set_target(target_parquet(path)) |>
#'   run()
#' unlink(path)
target_parquet <- function(path, overwrite = FALSE, ...) {
  scalar(path, "path")
  flag(overwrite, "overwrite")
  if (adapter_remote_path(path)) {
    abort("Use a local path for target_parquet().")
  }
  options <- list(...)
  adapter_named_options(options, c("x", "sink"))
  structure(
    list(path = absolute_path(path), overwrite = overwrite, options = options),
    class = "tw_parquet_target"
  )
}

#' @export
check_component.tw_parquet_target <- function(x, ...) {
  need("arrow")
  if (!dir.exists(dirname(x$path))) {
    abort("The Parquet target directory is missing. Create it first.")
  }
  if (dir.exists(x$path)) {
    abort("The Parquet target must be a file, not a directory.")
  }
  if (file.exists(x$path) && !x$overwrite) {
    abort(
      "The Parquet target already exists. Set overwrite = TRUE to replace it."
    )
  }
  invisible(x)
}

#' @export
write_target.tw_parquet_target <- function(target, data, context, ...) {
  check_component(target)
  data <- adapter_frame(data)
  candidate <- tempfile(
    ".tidyweave-",
    tmpdir = dirname(target$path),
    fileext = ".parquet"
  )
  on.exit(unlink(candidate), add = TRUE)
  do.call(
    arrow::write_parquet,
    c(list(x = data, sink = candidate), target$options)
  )
  if (file.exists(target$path) && !target$overwrite) {
    abort("The Parquet target appeared during writing. Nothing was replaced.")
  }
  if (!suppressWarnings(file.rename(candidate, target$path))) {
    abort(
      "Could not publish the Parquet file. The previous file was preserved."
    )
  }
  list(type = "parquet", path = target$path, rows = nrow(data))
}

#' @export
inspect.tw_parquet_target <- function(x, ...) {
  list(type = "Parquet target", path = x$path, overwrite = x$overwrite)
}

#' @export
capabilities.tw_parquet_target <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}

#' @export
read_source.Dataset <- function(source, ...) source
#' @export
read_source.Table <- function(source, ...) source
#' @export
read_source.RecordBatch <- function(source, ...) source
#' @export
read_source.arrow_dplyr_query <- function(source, ...) source
#' @export
check_component.Dataset <- function(x, ...) {
  need("arrow")
  columns <- names(x)
  if (anyNA(columns) || any(!nzchar(columns)) || anyDuplicated(columns)) {
    abort("Arrow source column names must be non-empty and unique.")
  }
  invisible(x)
}
#' @export
check_component.Table <- check_component.Dataset
#' @export
check_component.RecordBatch <- check_component.Dataset
#' @export
check_component.arrow_dplyr_query <- check_component.Dataset
#' @export
inspect.Dataset <- function(x, ...) list(type = "Arrow", columns = names(x))
#' @export
inspect.Table <- inspect.Dataset
#' @export
inspect.RecordBatch <- inspect.Dataset
#' @export
inspect.arrow_dplyr_query <- inspect.Dataset
#' @export
capabilities.Dataset <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = TRUE,
    transactions = FALSE,
    immutable = FALSE
  )
}
#' @export
capabilities.Table <- capabilities.Dataset
#' @export
capabilities.RecordBatch <- capabilities.Dataset
#' @export
capabilities.arrow_dplyr_query <- capabilities.Dataset

adapter_remote_path <- function(path) {
  grepl("^[[:alpha:]][[:alnum:]+.-]*://", path)
}
adapter_path_descriptor <- function(path) {
  if (adapter_remote_path(path)) "remote object storage" else path
}
