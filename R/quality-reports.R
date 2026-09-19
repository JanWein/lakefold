#' Export a portable quality report
#'
#' Exports persisted check metadata, counts and segment labels. No source rows
#' are collected. The HTML is self-contained, escapes cell contents and displays
#' status as text. An empty result is explicitly reported as not checked.
#' @param x Quality tibble or a run/dbt result accepted by [dl_quality()].
#' @param path Output file path.
#' @param format HTML or JSON.
#' @param title Human-readable report title.
#' @param overwrite Replace an existing file only when explicitly requested.
#' @returns The normalized output path, invisibly.
#' @seealso [dl_pointblank_report()], [dl_expect_quality()]
#' @export
#' @examples
#' contract <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' quality <- dl_validate(data.frame(id = c(1L, 1L)), contract)
#' path <- tempfile(fileext = ".html")
#' dl_quality_report(quality, path)
#' unlink(path)
dl_quality_report <- function(
  x,
  path,
  format = c("html", "json"),
  title = "lakefold quality report",
  overwrite = FALSE
) {
  format <- match.arg(format)
  scalar(title, "title")
  quality <- dl_quality(x)
  attr(quality, "pointblank_agents") <- NULL
  report_file(path, overwrite, function(temp) {
    if (format == "json") {
      jsonlite::write_json(
        list(
          title = title,
          generated_at = now(),
          publication_allowed = quality_ok(quality),
          checks = quality
        ),
        temp,
        dataframe = "rows",
        auto_unbox = TRUE,
        pretty = TRUE,
        na = "null"
      )
    } else {
      columns <- intersect(
        c(
          "stage",
          "engine",
          "rule",
          "segment",
          "status",
          "n_failed",
          "n_total",
          "failure_rate",
          "threshold",
          "message",
          "details"
        ),
        names(quality)
      )
      rows <- vapply(
        seq_len(nrow(quality)),
        function(i) {
          cells <- vapply(
            columns,
            function(column) {
              value <- quality[[column]][[i]]
              paste0(
                "<td>",
                html_escape(if (is.na(value)) "" else as.character(value)),
                "</td>"
              )
            },
            character(1)
          )
          paste0("<tr>", paste(cells, collapse = ""), "</tr>")
        },
        character(1)
      )
      status <- if (!nrow(quality)) {
        "Not checked"
      } else if (!quality_ok(quality)) {
        "Blocked"
      } else if (any(quality$status == "warning")) {
        "Allowed with warnings"
      } else {
        "Passed"
      }
      html <- paste0(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        "<title>",
        html_escape(title),
        "</title><style>",
        "body{font:16px/1.5 system-ui,sans-serif;color:#172b35;background:#fff;margin:2rem}",
        "main{max-width:100rem;margin:auto}table{border-collapse:collapse;width:100%}",
        "th,td{padding:.6rem;border:1px solid #c7d2d9;text-align:left;vertical-align:top}",
        "th{background:#e9f2f1}td{overflow-wrap:anywhere}.table-wrap{overflow:auto}",
        "</style></head><body><main><h1>",
        html_escape(title),
        "</h1>",
        "<p><strong>Publication gate: ",
        status,
        "</strong></p>",
        "<p>Check metadata only. Warning states permit publication; failed, error and ",
        "not_checked states block it. No source rows are included.</p>",
        '<div class="table-wrap" tabindex="0" aria-label="Quality results table">',
        "<table><caption>Quality evidence</caption><thead><tr>",
        paste0(
          '<th scope="col">',
          html_escape(columns),
          "</th>",
          collapse = ""
        ),
        "</tr></thead><tbody>",
        paste(rows, collapse = ""),
        "</tbody></table></div></main></body></html>"
      )
      writeLines(html, temp, useBytes = TRUE)
    }
  })
}

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}

report_file <- function(path, overwrite, write) {
  scalar(path, "path")
  flag(overwrite, "overwrite")
  if (file.exists(path) && !overwrite) {
    abort("Output exists; choose another path or overwrite = TRUE.")
  }
  if (!dir.exists(dirname(path))) {
    abort("The output directory must exist.")
  }
  temp <- tempfile(
    ".lakefold-report-",
    tmpdir = dirname(path),
    fileext = ".html"
  )
  on.exit(unlink(temp), add = TRUE)
  write(temp)
  if (!file.rename(temp, path)) {
    abort("Could not publish the report; existing output retained.")
  }
  invisible(normalizePath(path))
}

#' Export the native pointblank report from a validation
#'
#' Requires [dl_validate()] with `keep_agents = TRUE`. Agents are held only in
#' memory and are never serialized into the registry. Failed-row extracts and
#' checked-table samples are disabled during interrogation. The native report
#' describes pointblank action levels; the authoritative lakefold gate is shown
#' by [dl_quality_report()], especially when using `policy = "rule"`.
#' @param x A quality tibble containing retained pointblank agents.
#' @param rule Name supplied to [dl_pointblank()].
#' @param path Output HTML path.
#' @param overwrite Replace an existing output.
#' @returns The normalized output path, invisibly.
#' @export
#' @examplesIf requireNamespace("pointblank", quietly = TRUE)
#' contract <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(amount = "numeric"), rules = list(dl_pointblank("amounts", function(data) {
#'     pointblank::create_agent(data) |>
#'       pointblank::col_vals_gte("amount", 0)
#'   })))
#' quality <- dl_validate(data.frame(amount = c(10, -1)), contract,
#'   keep_agents = TRUE)
#' path <- tempfile(fileext = ".html")
#' dl_pointblank_report(quality, "amounts", path)
#' unlink(path)
dl_pointblank_report <- function(x, rule, path, overwrite = FALSE) {
  need("pointblank")
  scalar(rule, "rule")
  agents <- attr(x, "pointblank_agents")
  if (is.null(agents[[rule]])) {
    abort(
      "No retained agent for this rule. Use dl_validate(..., keep_agents = TRUE)."
    )
  }
  report_file(path, overwrite, function(temp) {
    pointblank::export_report(
      agents[[rule]],
      filename = basename(temp),
      path = dirname(temp),
      quiet = TRUE
    )
  })
}

#' Expect that quality evidence permits publication
#'
#' Uses the same gate as ingestion: warning states are allowed; empty results,
#' failures, evaluation errors and skipped checks fail the expectation.
#' @param x Quality tibble or result accepted by [dl_quality()].
#' @returns `x`, invisibly, after recording a testthat expectation.
#' @export
#' @examplesIf requireNamespace("testthat", quietly = TRUE)
#' contract <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' dl_expect_quality(dl_validate(data.frame(id = 1:2), contract))
dl_expect_quality <- function(x) {
  need("testthat")
  quality <- dl_quality(x)
  blocked <- quality$rule[!quality$status %in% c("passed", "warning")]
  testthat::expect(
    quality_ok(quality),
    paste0(
      "Quality gate blocked: ",
      if (!nrow(quality)) "no checks" else paste(blocked, collapse = ", ")
    )
  )
  invisible(x)
}
