#' Define an input source
#' @param id,version Source identity and version.
#' @param path Local input file.
#' @param reader Function receiving the immutable landed file path.
#' @param owner,description Metadata.
#' @return Source specification. Files are read only at execution time.
#' @export
#' @examples
#' source <- source_file("orders.file", "orders.csv", reader = utils::read.csv)
#' source
source_file <- function(
  id,
  path,
  reader = function(path) utils::read.csv(path),
  version = "1.0.0",
  owner = "",
  description = ""
) {
  asset_id(id)
  scalar(path, "path")
  scalar(version, "version")
  if (!is.function(reader)) {
    abort("reader must be a function.")
  }
  structure(
    list(
      id = id,
      version = version,
      kind = "source",
      path = absolute_path(path),
      reader = reader,
      owner = owner,
      description = description
    ),
    class = "tw_source"
  )
}

land_source <- function(lake, source) {
  if (!file.exists(source$path) || dir.exists(source$path)) {
    abort("Source file is missing.", "tw_missing_delivery")
  }
  # Copy first, then hash the bytes that will actually be parsed.
  tmp <- tempfile("incoming-", tmpdir = lake$config$landing)
  on.exit(unlink(tmp), add = TRUE)
  if (!file.copy(source$path, tmp, overwrite = FALSE)) {
    abort("Unable to stage source file.")
  }
  hash <- digest::digest(file = tmp, algo = "sha256", serialize = FALSE)
  directory <- file.path(lake$config$landing, source$id, hash)
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  target <- file.path(directory, basename(source$path))
  if (file.exists(target)) {
    if (
      !identical(
        digest::digest(file = target, algo = "sha256", serialize = FALSE),
        hash
      )
    ) {
      abort("Landing integrity check failed.")
    }
  } else if (!file.rename(tmp, target)) {
    abort("Unable to commit landed source file.")
  }
  st <- lake$config$storage
  uri <- target
  if (st$type == "s3") {
    need("paws.storage")
    client <- paws.storage::s3(
      config = list(
        region = st$region,
        endpoint = st$endpoint,
        s3_force_path_style = TRUE
      )
    )
    key <- paste(
      c(
        if (nzchar(st$prefix)) st$prefix,
        "landing",
        source$id,
        hash,
        basename(target)
      ),
      collapse = "/"
    )
    # Content-addressed key plus a conditional create protects the original.
    tryCatch(
      client$put_object(
        Bucket = st$bucket,
        Key = key,
        Body = target,
        IfNoneMatch = "*"
      ),
      error = function(e) {
        if (!grepl("PreconditionFailed|412", conditionMessage(e))) {
          abort("S3 landing upload failed.")
        }
      }
    )
    uri <- paste0("s3://", st$bucket, "/", key)
  }
  list(path = target, uri = uri, hash = hash, received_at = now())
}
