test_that("contract and commons exports preserve their declared scope", {
  skip_if_not_installed("yaml")
  f <- fixture()
  on.exit(fixture_cleanup(f))
  path <- file.path(f$root, "contract.yaml")
  tw_contract_yaml(f$contract, path)
  x <- yaml::read_yaml(path)
  expect_equal(x$format, "tidyweave-contract")
  expect_equal(x$grain, f$contract$grain)
  expect_equal(x$key, c("id", "date"))
  expect_identical(x$allow_extra, FALSE)
  tw_commons_yaml(reserve_metric(), "published_reserves", "SUM(reserve)", path)
  x <- yaml::read_yaml(path)
  expect_equal(x$tables[[1]]$definitions[[1]]$expr, "SUM(reserve)")
  expect_error(
    tw_commons_yaml(reserve_metric(), "x", "SUM(x); DROP TABLE y", path),
    "one expression"
  )
})

test_that("dm foreign keys reject orphaned references", {
  skip_if_not_installed("dm")
  f <- fixture()
  on.exit(fixture_cleanup(f))
  tw_run(f$pipeline, f$lake)
  companies <- tw_contract(
    "risk.company_contract",
    "1.0.0",
    "Risk",
    "Companies",
    "One company",
    c(company = "character"),
    key = "company"
  )
  p <- tw_product(
    "risk.companies",
    contract = companies,
    code_version = "v1"
  ) |>
    tw_add_source(tw_source_release(f$lake, "risk.validated")) |>
    tw_add_transform(function(data) {
      dplyr::distinct(dplyr::select(data, company))
    }) |>
    tw_set_target(f$lake)
  tw_run(p)
  tables <- c(reserves = "risk.validated", companies = "risk.companies")
  keys <- list(reserves = c("id", "date"), companies = "company")
  foreign <- list(list(
    table = "reserves",
    columns = "company",
    ref_table = "companies",
    ref_columns = "company"
  ))
  expect_s3_class(tw_model(f$lake, tables, keys, foreign), "dm")
  p$transforms[[1]] <- function(data) {
    dplyr::filter(
      dplyr::distinct(dplyr::select(data, company)),
      company == "Alpha"
    )
  }
  p$version <- "2.0.0"
  p$code_version <- "v2"
  tw_run(p)
  expect_error(
    tw_model(f$lake, tables, keys, foreign),
    class = "tw_model_invalid"
  )
})
