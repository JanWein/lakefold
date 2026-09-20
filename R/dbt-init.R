#' Create a runnable local dbt starter project
#'
#' Write a small dbt-duckdb project with synthetic order data, staging and
#' reporting models, and uniqueness/not-null tests. Existing non-empty
#' directories are never overwritten. No database or subprocess is opened.
#'
#' The generated profile targets the catalog in `config` through the `lake`
#' attachment. Supported configurations use a local metadata catalog and local
#' storage. For S3, PostgreSQL or dbt v2 catalog configuration, create and
#'   verify
#' an appropriate profile yourself and use [dbt_project()]. The starter
#' uses the dbt-duckdb profile format; it does not install dbt or adapters.
#'
#' @param path Character scalar giving a new or empty directory.
#' @param config A [lake_config()] with a local DuckDB catalog and local storage.
#' @param name Character scalar. A dbt project identifier containing letters,
#'   digits and underscores, starting with a letter.
#' @inheritParams dbt_project
#' @returns A [dbt_project()] specification pointing to the written project
#'   and profile. Files contain synthetic data and local paths, no credentials.
#' @seealso [dbt_build()], [product()]
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   catalog = registry_duckdb(file.path(root, "lake.duckdb")),
#'   storage = storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' project <- dbt_init(file.path(root, "dbt"), config)
#' project
#' unlink(root, recursive = TRUE)
#' @export
dbt_init <- function(
  path,
  config,
  name = "tidyweave_demo",
  executable = "dbt"
) {
  need("yaml")
  ident(name)
  if (
    !inherits(config, "tw_config") ||
      config$catalog$type != "duckdb" ||
      config$storage$type != "local"
  ) {
    abort(
      "The starter requires lake_config() with local catalog and storage.",
      "tw_dbt_invalid"
    )
  }
  path <- absolute_path(path)
  if (file.exists(path) && !dir.exists(path)) {
    abort("path is a file.", "tw_dbt_invalid")
  }
  if (
    dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))
  ) {
    abort(
      "Choose a new or empty directory; existing files are never overwritten.",
      "tw_dbt_invalid"
    )
  }
  project <- dbt_project(path, path, target = "dev", executable = executable)
  directories <- c("models/staging", "models/marts", "seeds", "macros")
  for (directory in directories) {
    dir.create(
      file.path(path, directory),
      recursive = TRUE,
      showWarnings = FALSE
    )
  }
  attach <- list(path = config$catalog$path, alias = "lake")
  profile <- list(
    type = "duckdb",
    path = ":memory:",
    database = "lake",
    schema = "staging",
    threads = 1L
  )
  if (config$backend == "ducklake") {
    attach$path <- paste0("ducklake:", config$catalog$path)
    attach$options <- list(DATA_PATH = paste0(config$storage$path, "/"))
    profile$extensions <- list("ducklake")
  }
  profile$attach <- list(attach)
  yaml::write_yaml(
    stats::setNames(
      list(list(target = "dev", outputs = list(dev = profile))),
      name
    ),
    file.path(path, "profiles.yml")
  )
  models <- stats::setNames(
    list(list(
      `+materialized` = "table",
      staging = list(`+schema` = "staging"),
      marts = list(`+schema` = "marts")
    )),
    name
  )
  seeds <- stats::setNames(list(list(`+schema` = "raw")), name)
  yaml::write_yaml(
    list(
      name = name,
      version = "1.0.0",
      `config-version` = 2L,
      profile = name,
      `model-paths` = list("models"),
      `seed-paths` = list("seeds"),
      `macro-paths` = list("macros"),
      models = models,
      seeds = seeds
    ),
    file.path(path, "dbt_project.yml")
  )
  writeLines(
    c("order_id,customer_id,amount", "1,101,25", "2,101,75", "3,102,50"),
    file.path(path, "seeds", "raw_orders.csv")
  )
  writeLines(
    "select order_id, customer_id, amount from {{ ref('raw_orders') }}",
    file.path(path, "models", "staging", "stg_orders.sql")
  )
  writeLines(
    c(
      "select customer_id, sum(amount) as revenue",
      "from {{ ref('stg_orders') }}",
      "group by customer_id"
    ),
    file.path(path, "models", "marts", "customer_revenue.sql")
  )
  yaml::write_yaml(
    list(
      version = 2L,
      models = list(
        list(
          name = "stg_orders",
          description = "One row per synthetic order.",
          columns = list(
            list(name = "order_id", tests = list("unique", "not_null")),
            list(name = "customer_id", tests = list("not_null"))
          )
        ),
        list(
          name = "customer_revenue",
          description = "Revenue by customer.",
          columns = list(
            list(name = "customer_id", tests = list("unique", "not_null"))
          )
        )
      )
    ),
    file.path(path, "models", "schema.yml")
  )
  writeLines(
    c(
      "{% macro generate_schema_name(custom_schema_name, node) -%}",
      "  {{ custom_schema_name | trim if custom_schema_name else target.schema }}",
      "{%- endmacro %}"
    ),
    file.path(path, "macros", "generate_schema_name.sql")
  )
  writeLines(
    c(
      ".tidyweave/",
      "target/",
      "logs/",
      "dbt_packages/",
      "profiles.yml",
      "*.duckdb",
      "*.wal"
    ),
    file.path(path, ".gitignore")
  )
  writeLines(
    c(
      paste0("# ", name),
      "",
      "Synthetic tidyweave starter project.",
      "",
      "Install a compatible dbt CLI and DuckDB adapter, then run from R:",
      "",
      "```r",
      "library(tidyweave)",
      "project <- dbt_project(\".\", profiles_dir = \".\")",
      "result <- dbt_build(project)",
      "dbt_status(result)",
      "dbt_lineage(result)",
      "```",
      "",
      "Close R connections to this catalog before running dbt. Reconnect afterwards.",
      "profiles.yml contains machine-specific paths and is intentionally gitignored.",
      "The schema macro uses exact schema names. Use a separate catalog for each environment.",
      "dbt models are mutable and are not automatically tidyweave releases."
    ),
    file.path(path, "README.md")
  )
  project
}
