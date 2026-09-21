# Instrument one component while exercising the shared integration suite.
component <- Sys.getenv("DATARAFT_COVERAGE_PACKAGE", "core")
stopifnot(
  component %in% c("core", "lake", "adapters", "metrics", "dbt", "catalog")
)
root <- normalizePath(".", winslash = "/")
code <- sprintf(
  'library(dataraft); testthat::test_dir(%s, stop_on_failure = TRUE)',
  encodeString(file.path(root, "tests", "testthat"), quote = '"')
)
coverage <- covr::package_coverage(
  path = file.path("packages", paste0("dataraft.", component)),
  type = "none",
  code = code
)
dir.create("coverage", showWarnings = FALSE)
covr::to_cobertura(
  coverage,
  filename = file.path("coverage", paste0(component, ".xml"))
)
print(coverage)
