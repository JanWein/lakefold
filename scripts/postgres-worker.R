library(tidyweave)
job <- readRDS(commandArgs(trailingOnly = TRUE)[[1]])
result <- tryCatch(
  {
    if (job$action == "hold") {
      hold <- function() {
        lake <- tw_connect_lake(job$config)
        on.exit(tw_close_lake(lake), add = TRUE)
        tidyweave:::assert_writable(lake)
        file.create(job$ready)
        Sys.sleep(30)
      }
      hold()
      list(status = "held")
    } else if (job$action == "report") {
      metrics <- tw_metric_set(
        "shared",
        count = dplyr::n(),
        approved = TRUE,
        code_version = "v1"
      )
      values <- tw_measure(job$previous, metrics = metrics, by = character())
      tw_report_release(values, "same-report", code_version = "v1")
      list(status = "reported")
    } else {
      result <- tw_publish(
        tw_product(job$asset, data.frame(id = job$value)),
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
