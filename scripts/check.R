# Full source-package check, including executable examples and vignettes.
if (!requireNamespace("rcmdcheck", quietly = TRUE)) {
  stop("Install rcmdcheck first.")
}
rcmdcheck::rcmdcheck(
  path = ".",
  args = "--no-manual",
  error_on = "warning",
  check_dir = "check"
)
