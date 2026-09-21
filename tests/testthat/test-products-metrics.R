test_that("products and report metrics pin input versions", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  product <- dr_product(
    "risk.product",
    contract = f$contract,
    code_version = "build-v1"
  ) |>
    dr_add_source(dr_source_release(f$lake, "risk.validated")) |>
    dr_set_target(f$lake)
  built <- dr_run(product)
  expect_equal(built$status, "published")
  expect_equal(dr_run(product, cache = TRUE)$status, "cached")
  metric <- reserve_metric("risk.product")
  result <- dr_measure(f$lake, metric, at = as.Date("2026-08-31"))
  expect_equal(result$value, 300)
  expect_equal(attr(result, "dr_manifest")$release_id, built$release_id)
  by_company <- dr_measure(f$lake, metric, by = "company")
  expect_equal(nrow(by_company), 2)
  report <- dr_report_release(
    f$lake,
    "report-aug-v1",
    list(reserve = result),
    "report-v1"
  )
  expect_equal(report$measures$reserve$values$value, 300)
  expect_equal(nrow(dr_registry(f$lake, "reports")), 1)
  changed <- result
  changed$value <- 999
  expect_error(
    dr_report_release(f$lake, "bad", list(reserve = changed), "v1"),
    "changed"
  )
  expect_error(dr_measure(f$lake, metric, by = "forbidden"), "Unsupported")
  metric$approved <- FALSE
  expect_equal(dr_measure(f$lake, metric)$value, 300)
  expect_error(dr_measure(f$lake, metric, record = TRUE), "Exploratory")
})

test_that("stock metrics refuse summing multiple dates", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  x <- rbind(f$good, transform(f$good, date = as.Date("2026-09-30")))
  f$write(x)
  dr_run(f$pipeline, f$lake)
  expect_error(dr_measure(f$lake, reserve_metric()), "exactly one")
  expect_equal(
    dr_measure(f$lake, reserve_metric(), at = as.Date("2026-08-31"))$value,
    300
  )
})

test_that("catalog exports only metadata and constructs a read-only app", {
  f <- fixture()
  on.exit(fixture_cleanup(f))
  dr_run(f$pipeline, f$lake)
  path <- file.path(f$root, "catalog.json")
  dr_catalog_export(f$lake, path)
  x <- jsonlite::read_json(path)
  expect_false("reports" %in% names(x))
  expect_true(all(
    c("assets", "quality_results", "lineage_edges") %in% names(x)
  ))
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  app <- dr_catalog_app(snapshot = path, launch = FALSE)
  expect_s3_class(app, "shiny.appobj")
  shiny::testServer(app, {
    session$setInputs(asset = "risk.validated", search = "")
    expect_match(output$usage, "risk.validated")
    expect_match(output$overview, "current")
    expect_match(output$quality, "unique_key")
    expect_match(output$lineage_graph$html, "svg")
    session$setInputs(definition_id = "risk.contract@1.0.0")
    expect_match(output$definition, "Validated reserves")
    session$setInputs(search = "RISK")
    expect_match(output$overview, "risk.validated")
  })
})

test_that("identifiers cannot inject SQL", {
  expect_error(
    dr_contract(
      "bad; DROP TABLE",
      "v1",
      "owner",
      "desc",
      "row",
      c(id = "character")
    ),
    "Asset ids"
  )
  expect_error(dr_setup_lake(layers = "raw; DROP"), "Invalid identifier")
})
