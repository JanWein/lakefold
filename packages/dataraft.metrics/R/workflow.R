#' @export
#' @noRd
#' @importFrom dataraft.core dr_execute
dr_execute.dr_metric <- function(object, lake = NULL, ...) {
  dataraft.lake::with_execution_lake(lake, function(con) {
    dr_measure(con, object, ...)
  })
}

#' @export
print.dr_metric <- function(x, ...) {
  cat(
    "<metric>",
    x$id,
    "@",
    x$version,
    "|",
    if (x$approved) "approved" else "not approved",
    "\n"
  )
  cat(
    "Product:",
    x$product,
    "| Time:",
    x$time_behavior,
    "| Unit:",
    x$unit,
    "\n"
  )
  cat("Dimensions:", paste(x$dimensions, collapse = ", "), "\n")
  invisible(x)
}
