test_that("products and report metrics pin input versions", {
  f <- fixture(); on.exit(cleanup(f))
  dl_run(f$pipeline, f$lake)
  product <- dl_product("risk.product", c(reserves = "risk.validated"), function(inputs) inputs$reserves,
    contract = f$contract, code_version = "build-v1")
  built <- dl_build(f$lake, product)
  expect_equal(built$status, "published")
  expect_equal(dl_build(f$lake, product)$status, "cached")
  metric <- reserve_metric("risk.product")
  result <- dl_measure(f$lake, metric, at = as.Date("2026-08-31"))
  expect_equal(result$value, 300)
  expect_equal(attr(result, "dl_manifest")$release_id, built$release_id)
  by_company <- dl_measure(f$lake, metric, by = "company")
  expect_equal(nrow(by_company), 2)
  report <- dl_report_release(f$lake, "report-aug-v1", list(reserve = result), "report-v1")
  expect_equal(report$measures$reserve$values$value, 300)
  expect_equal(nrow(dl_registry(f$lake, "reports")), 1)
  changed <- result; changed$value <- 999
  expect_error(dl_report_release(f$lake, "bad", list(reserve = changed), "v1"), "changed")
  expect_error(dl_measure(f$lake, metric, by = "forbidden"), "Unsupported")
  metric$approved <- FALSE
  expect_error(dl_measure(f$lake, metric), "not approved")
})

test_that("stock metrics refuse summing multiple dates", {
  f <- fixture(); on.exit(cleanup(f))
  x <- rbind(f$good, transform(f$good, date = as.Date("2026-09-30")))
  f$write(x); dl_run(f$pipeline, f$lake)
  expect_error(dl_measure(f$lake, reserve_metric()), "exactly one")
  expect_equal(dl_measure(f$lake, reserve_metric(), at = as.Date("2026-08-31"))$value, 300)
})

test_that("catalog exports only metadata and constructs a read-only app", {
  f <- fixture(); on.exit(cleanup(f))
  dl_run(f$pipeline, f$lake)
  path <- file.path(f$root, "catalog.json"); dl_catalog_export(f$lake, path)
  x <- jsonlite::read_json(path)
  expect_false("reports" %in% names(x))
  expect_true(all(c("assets", "quality_results", "lineage_edges") %in% names(x)))
  skip_if_not_installed("shiny"); skip_if_not_installed("bslib")
  app <- dl_catalog(snapshot = path, launch = FALSE)
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
  expect_error(dl_contract("bad; DROP TABLE", "v1", "owner", "desc", "row", c(id = "character")), "Asset ids")
  expect_error(dl_setup(layers = "raw; DROP"), "Invalid identifier")
})
