#' Export the portable contract subset
#' @param contract Contract definition.
#' @param path YAML output file.
#' @return Output path, invisibly. Executable R rules are described, never serialized as runnable YAML.
#' @export
dl_contract_yaml <- function(contract, path) {
  need("yaml")
  x <- list(format = "dataloom-contract", format_version = "1.0", id = contract$id, version = contract$version,
    owner = contract$owner, producer = contract$producer, description = contract$description, grain = contract$grain,
    columns = contract$columns, required = contract$required, key = contract$key,
    max_age_hours = contract$max_age_hours, allow_empty = contract$allow_empty, allow_extra = contract$allow_extra,
    rules = lapply(contract$rules, function(r) list(name = r$name, engine = r$engine, severity = r$severity, max_failure = r$max_failure, description = r$description %||% "", implementation = "R code in versioned project")))
  yaml::write_yaml(x, path)
  invisible(path)
}

#' Export an explicit declarative definition for data-dict and commons
#' @param metric Registered metric definition for business metadata.
#' @param table Physical table or governed product view name in the consumer environment.
#' @param sql_expr Explicit single-table aggregate expression, e.g. SUM(reserve).
#' @param path Output YAML file.
#' @return Path. This adapter exports metadata; it does not execute or install commons.
#' @export
dl_commons_yaml <- function(metric, table, sql_expr, path) {
  need("yaml"); scalar(table, "table"); scalar(sql_expr, "sql_expr")
  if (grepl(";|--|/\\*", sql_expr)) abort("Supply one expression, not a SQL statement or comments.")
  if (!metric$approved) abort("Export only approved metrics.")
  # SQL is explicit: arbitrary R cannot be translated faithfully into data-dict expressions.
  x <- list(tables = list(list(name = table, definitions = list(list(name = gsub("\\.", "_", metric$id),
    label = metric$id, description = paste(metric$description, "Unit:", metric$unit, "Time:", metric$time_behavior), expr = sql_expr)))))
  yaml::write_yaml(x, path)
  invisible(path)
}

#' Check backend capabilities
#' @param lake Connected lake.
#' @return A named list of explicit implementation capabilities.
#' @export
dl_capabilities <- function(lake) list(backend = lake$config$backend, transactions = TRUE,
  immutable_releases = TRUE, replace = TRUE, replace_partition = TRUE,
  multi_writer = FALSE, automatic_column_lineage = FALSE, own_scheduler = FALSE,
  authentication = FALSE, automatic_retention = FALSE)
