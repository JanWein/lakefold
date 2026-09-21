#' Export the portable contract subset
#' @param contract Contract definition.
#' @param path YAML output file.
#' @return Output path, invisibly. Executable R rules are described, never
#'   serialized as runnable YAML.
#' @export
#' @examples
#' contract <- tw_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' path <- tempfile(fileext = ".yml")
#' tw_contract_yaml(contract, path)
#' cat(readLines(path), sep = "\n")
#' unlink(path)
tw_contract_yaml <- function(contract, path) {
  need("yaml")
  x <- list(
    format = "tidyweave-contract",
    format_version = "1.0",
    id = contract$id,
    version = contract$version,
    owner = contract$owner,
    producer = contract$producer,
    operator = contract$operator %||% contract$owner,
    column_metadata = contract$column_metadata %||% list(),
    description = contract$description,
    grain = contract$grain,
    columns = contract$columns,
    required = contract$required,
    key = contract$key,
    max_age_hours = contract$max_age_hours,
    allow_empty = contract$allow_empty,
    allow_extra = contract$allow_extra,
    rules = lapply(contract$rules, function(r) {
      list(
        name = r$name,
        engine = r$engine,
        severity = r$severity,
        max_failure = r$max_failure,
        policy = r$policy %||% "rule",
        description = r$description %||% "",
        implementation = "R code in versioned project"
      )
    })
  )
  yaml::write_yaml(x, path)
  invisible(path)
}

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
#' @examples
#' metric <- tw_metric(
#'   "orders.total", "orders", expr = sum(amount), time_behavior = "flow",
#'   unit = "EUR", owner = "Analytics", description = "Total order value",
#'   approved = TRUE, code_version = "v1"
#' )
#' path <- tempfile(fileext = ".yml")
#' tw_commons_yaml(metric, "orders", "SUM(amount)", path)
#' cat(readLines(path), sep = "\n")
#' unlink(path)
tw_commons_yaml <- function(metric, table, sql_expr, path) {
  need("yaml")
  scalar(table, "table")
  scalar(sql_expr, "sql_expr")
  if (grepl(";|--|/\\*", sql_expr)) {
    abort("Supply one expression, not a SQL statement or comments.")
  }
  if (!metric$approved) {
    abort("Export only approved metrics.")
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
