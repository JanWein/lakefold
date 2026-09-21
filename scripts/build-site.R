# Publish the metapackage guides and each component's native reference together.
root <- normalizePath(".")
site <- file.path(root, "site")
base_url <- "https://dataraft-r.github.io/dataraft/"
components <- paste0(
  "dataraft.",
  c("core", "lake", "adapters", "metrics", "dbt", "catalog")
)
pkgdown::build_site(new_process = FALSE, install = FALSE)
for (component in components) {
  pkgdown::build_site(
    pkg = file.path(root, "packages", component),
    examples = FALSE,
    new_process = FALSE,
    install = FALSE,
    override = list(
      destination = file.path(site, "components", component),
      url = paste0(base_url, "components/", component, "/"),
      template = list(bootstrap = 5)
    )
  )
}
# pkgdown falls back to rdrr for packages that are not indexed yet. Point those
# links at the references built above, including aliases with a shared Rd topic.
for (component in components) {
  rd_files <- list.files(
    file.path(root, "packages", component, "man"),
    pattern = "\\.Rd$",
    full.names = TRUE
  )
  aliases <- list()
  for (rd_file in rd_files) {
    rd <- tools::parse_Rd(rd_file)
    for (element in rd) {
      if (identical(attr(element, "Rd_tag"), "\\alias")) {
        aliases[[paste0(unlist(element), collapse = "")]] <-
          sub("\\.Rd$", "", basename(rd_file))
      }
    }
  }
  pages <- list.files(
    site,
    pattern = "\\.html$",
    recursive = TRUE,
    full.names = TRUE
  )
  for (page in pages) {
    html <- readLines(page, warn = FALSE)
    prefix <- paste0("https://rdrr.io/pkg/", component, "/man/")
    if (!any(grepl(prefix, html, fixed = TRUE))) {
      next
    }
    for (alias in names(aliases)) {
      html <- gsub(
        paste0(prefix, alias, ".html"),
        paste0(
          base_url,
          "components/",
          component,
          "/reference/",
          aliases[[alias]],
          ".html"
        ),
        html,
        fixed = TRUE
      )
    }
    # rdrr also uses the Rd topic name instead of an alias.
    html <- gsub(
      prefix,
      paste0(base_url, "components/", component, "/reference/"),
      html,
      fixed = TRUE
    )
    writeLines(html, page)
  }
}
