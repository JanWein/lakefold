# Check each independent source package, then the umbrella integration suite.
source("scripts/install-family.R")
results <- lapply(paths, function(path) {
  name <- read.dcf(file.path(path, "DESCRIPTION"), fields = "Package")[[1L]]
  rcmdcheck::rcmdcheck(
    path = path,
    args = "--no-manual",
    error_on = "never",
    check_dir = file.path("check", name)
  )
})
failed <- vapply(
  results,
  function(result) {
    length(result$errors) + length(result$warnings) > 0L
  },
  logical(1)
)
if (any(failed)) {
  stop("Package checks failed: ", paste(paths[failed], collapse = ", "))
}
