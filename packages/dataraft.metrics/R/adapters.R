#' Export an explicit declarative definition for data-dict and commons
#' @param metric Registered metric definition for business metadata.
#' @param table Physical table or governed product view name in the consumer
#'   environment.
#' @param sql_expr Explicit single-table aggregate expression, e.g.
#'   SUM(reserve).
#' @param path Output YAML file.
#' @return Path. This adapter exports metadata; it does not execute or install
#'   commons.
#' @export
#' @examplesIf requireNamespace("yaml", quietly = TRUE)
#' metric <- dr_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' path <- tempfile(fileext = ".yml")
#' dr_commons_yaml(metric, "orders", "SUM(amount)", path)
#' cat(readLines(path), sep = "\n")
#' unlink(path)
dr_commons_yaml <- function(metric, table, sql_expr, path) {
  dataraft.core::need("yaml")
  dataraft.core::scalar(table, "table")
  dataraft.core::scalar(sql_expr, "sql_expr")
  if (grepl(";|--|/\\*", sql_expr)) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Supply one expression, not a SQL statement or comments."
    )
  }
  if (!metric$approved) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Export only approved metrics."
    )
  }
  # SQL is explicit: arbitrary R cannot be translated faithfully into data-dict expressions.
  x <- list(
    tables = list(list(
      name = table,
      definitions = list(list(
        name = gsub("\\.", "_", metric$id),
        label = metric$id,
        description = paste(
          metric$description,
          "Unit:",
          metric$unit,
          "Time:",
          metric$time_behavior
        ),
        expr = sql_expr
      ))
    ))
  )
  yaml::write_yaml(x, path)
  invisible(path)
}
