# Run from the repository root.
family <- c("core", "lake", "adapters", "metrics", "dbt", "catalog")
paths <- c(file.path("packages", paste0("dataraft.", family)), ".")
descriptions <- lapply(paths, function(path) {
  read.dcf(file.path(path, "DESCRIPTION"), fields = c("Package", "Imports"))
})
family_names <- vapply(descriptions, function(x) x[1L, "Package"], character(1))
dependencies <- unique(trimws(unlist(strsplit(
  paste(
    vapply(descriptions, function(x) x[1L, "Imports"], character(1)),
    collapse = ","
  ),
  ","
))))
dependencies <- trimws(sub(" \\(.*", "", dependencies))
missing <- setdiff(
  dependencies,
  c(family_names, rownames(installed.packages()))
)
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
for (path in paths) {
  status <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", shQuote(path))
  )
  if (status != 0L) stop("Installation failed: ", path)
}
