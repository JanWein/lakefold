library(tidyweave)
job <- readRDS(commandArgs(trailingOnly = TRUE)[[1]])
result <- tryCatch(
  {
    if (job$action == "report") {
      metrics <- metric_set(
        "shared",
        count = dplyr::n(),
        approved = TRUE,
        code_version = "v1"
      )
      values <- measure(job$previous, metrics = metrics, by = character())
      report_release(values, "same-report", code_version = "v1")
      list(status = "reported")
    } else {
      result <- publish(
        product(job$asset, data.frame(id = job$value)),
        to = job$config,
        previous = job$previous
      )
      list(status = result$status, release = result$release_id)
    }
  },
  error = function(e) {
    condition <- e$result$error
    if (is.null(condition)) {
      condition <- e
    }
    list(
      status = "error",
      error_class = class(condition),
      message = conditionMessage(condition)
    )
  }
)
saveRDS(result, job$output)
