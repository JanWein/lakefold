#' Extension implementation helper
#'
#' Internal implementation interface for the DataRaft package family.
#' @usage NULL
#' @keywords internal
#' @export
#' @name measurement_quality

measurement_quality <- function(x) {
  rlang::local_error_call(rlang::caller_env())
  if (inherits(x, "dr_measurement_set")) {
    validate_measurement_set(x)
  }
  out <- lapply(x, function(value) {
    manifest <- attr(value, "dr_manifest")
    reference <- attr(value, "dr_quality_reference")
    unavailable <- function() {
      rlang::local_error_call(rlang::caller_env())
      dataraft.core::quality_row(
        "input_release",
        "not_checked",
        stage = "input",
        message = "Exact input quality evidence is unavailable for this measurement."
      )
    }
    checks <- if (
      !identical(
        manifest$result_hash,
        dataraft.core::report_fingerprint(as.data.frame(value))
      ) ||
        !is.list(reference) ||
        !identical(reference$asset, manifest$product) ||
        !(identical(reference$release, manifest$release_id) ||
          (identical(manifest$input_published, FALSE) &&
            identical(reference$run_id, manifest$input_run)))
    ) {
      unavailable()
    } else if (identical(manifest$input_published, FALSE)) {
      reference$trial_quality %||% unavailable()
    } else {
      tryCatch(
        {
          borrowed <- inherits(reference$lake, "dr_lake") &&
            DBI::dbIsValid(reference$lake$con)
          if (borrowed) {
            lake <- reference$lake
            if (
              !identical(
                lake$config[c("backend", "catalog", "storage")],
                reference$config[c("backend", "catalog", "storage")]
              )
            ) {
              dataraft.core::abort(
                subclass = "dataraft_error_metrics",
                "The retained quality reference does not match the lake."
              )
            }
          } else {
            lake <- dataraft.lake::dr_connect_lake(
              reference$config,
              read_only = TRUE
            )
            on.exit(dataraft.lake::dr_disconnect_lake(lake), add = TRUE)
          }
          dataraft.core::dr_quality(
            lake,
            asset = reference$asset,
            release = reference$release
          )
        },
        error = function(e) unavailable()
      )
    }
    if (!nrow(checks)) {
      checks <- unavailable()
    }
    checks$.metric <- manifest$metric
    checks$.asset <- manifest$product
    checks$.release <- manifest$release_id
    checks
  })
  dataraft.core::dr_quality(dplyr::bind_rows(out))
}


#' Extension implementation helper
#'
#' Internal implementation interface for the DataRaft package family.
#' @usage NULL
#' @keywords internal
#' @export
#' @name diagnostic_measurements

diagnostic_measurements <- function(x) {
  rlang::local_error_call(rlang::caller_env())
  if (inherits(x, "dr_measurement_set")) {
    validate_measurement_set(x)
    return(x)
  }
  manifest <- attr(x, "dr_manifest")
  if (
    !identical(
      manifest$result_hash,
      dataraft.core::report_fingerprint(as.data.frame(x))
    )
  ) {
    dataraft.core::abort(
      subclass = "dataraft_error_metrics",
      "Metric result changed after calculation."
    )
  }
  list(x)
}
