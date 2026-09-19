#' Build a pipeline specification
#' @param id Pipeline identifier.
#' @param lake A connection-free dl_config or a connected lake; only
#'   configuration is retained.
#' @param config Optional named alternative to lake for a connection-free
#'   dl_config.
#' @param version Definition version.
#' @param code_version Version of all execution code, e.g. a Git commit SHA.
#'   Change it when imported functions, dependencies or captured values change.
#' @param pipeline Pipeline specification.
#' @param source Source definition.
#' @param using Reader override.
#' @param into Target layer for extraction, or asset id for publication.
#' @param contract Contract definition.
#' @param mode Full replacement or replacement of partitions present in input.
#' @param partition_by Partition columns. Empty or NULL keys are rejected.
#' @param layer Publication schema.
#' @return A pipeline specification, with no open connection or loaded data.
#' @export
#' @examples
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' pipeline <- dl_pipeline("orders.import", dl_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   dl_step_land(dl_source("orders.file", "orders.csv", utils::read.csv)) |>
#'   dl_step_extract() |>
#'   dl_step_validate(contract) |>
#'   dl_step_publish("orders")
#' dl_plan(pipeline)
dl_pipeline <- function(
  id,
  lake = NULL,
  version = "1.0.0",
  code_version,
  config = NULL
) {
  if (!is.null(config) && !is.null(lake)) {
    abort("Supply either lake or config, not both.")
  }
  lake <- config %||% lake
  config <- if (inherits(lake, "dl_config")) {
    lake
  } else {
    assert_lake(lake)
    lake$config
  }
  asset_id(id)
  scalar(version, "version")
  scalar(code_version, "code_version")
  structure(
    list(
      id = id,
      version = version,
      kind = "pipeline",
      code_version = code_version,
      config = config,
      steps = list()
    ),
    class = "dl_pipeline"
  )
}
add_step <- function(pipeline, type, value) {
  if (!inherits(pipeline, "dl_pipeline")) {
    abort("Use dl_pipeline() first.")
  }
  if (type %in% names(pipeline$steps)) {
    abort(paste("Duplicate pipeline step:", type))
  }
  expected <- c("land", "extract", "validate", "publish")
  current <- setdiff(names(pipeline$steps), c("transform", "precheck"))
  if (!identical(type, expected[length(current) + 1L])) {
    abort(
      paste("Next pipeline step must be", expected[length(current) + 1L]),
      "dl_pipeline_invalid"
    )
  }
  pipeline$steps[[type]] <- value
  pipeline
}
#' @rdname dl_pipeline
#' @export
dl_step_land <- function(pipeline, source) {
  if (!inherits(source, "dl_source")) {
    abort("source must be a dl_source.")
  }
  add_step(pipeline, "land", source)
}
#' @rdname dl_pipeline
#' @export
dl_step_extract <- function(pipeline, using = NULL, into = "raw") {
  ident(into)
  if (!is.null(using) && !is.function(using)) {
    abort("using must be a reader function.")
  }
  add_step(pipeline, "extract", list(using = using, layer = into))
}
#' @rdname dl_pipeline
#' @export
dl_step_validate <- function(pipeline, contract) {
  if (!inherits(contract, "dl_contract")) {
    abort("contract must be a dl_contract.")
  }
  add_step(pipeline, "validate", contract)
}
#' @rdname dl_pipeline
#' @export
dl_step_publish <- function(
  pipeline,
  into,
  mode = c("replace", "replace_partition"),
  partition_by = character(),
  layer = "validated"
) {
  asset_id(into)
  ident(layer)
  mode <- match.arg(mode)
  if (mode == "replace_partition" && !length(partition_by)) {
    abort("replace_partition needs partition_by.")
  }
  invisible(lapply(partition_by, ident))
  add_step(
    pipeline,
    "publish",
    list(asset = into, mode = mode, partition_by = partition_by, layer = layer)
  )
}

check_pipeline <- function(p) {
  if (!inherits(p, "dl_pipeline")) {
    abort("Use dl_pipeline() to define the workflow.", "dl_pipeline_invalid")
  }
  order <- names(p$steps)
  if ("precheck" %in% order) {
    if (match("precheck", order) != 3L) {
      abort("Input gate must follow extraction.")
    }
    order <- setdiff(order, "precheck")
  }
  expected <- if ("transform" %in% order) {
    c("land", "extract", "transform", "validate", "publish")
  } else {
    c("land", "extract", "validate", "publish")
  }
  if (!identical(order, expected)) {
    abort(
      "Complete the pipeline: land, extract, optional transforms, validate, publish.",
      "dl_pipeline_invalid"
    )
  }
  if (
    !all(c(p$steps$extract$layer, p$steps$publish$layer) %in% p$config$layers)
  ) {
    abort("Pipeline uses an unconfigured layer.")
  }
}

new_run <- function(lake, id, asset, definition_hash, code_version) {
  run <- uid()
  insert_meta(
    lake,
    "runs",
    list(
      run_id = run,
      pipeline = id,
      asset = asset,
      status = "running",
      started_at = now(),
      finished_at = NA_character_,
      input_hash = NA_character_,
      definition_hash = definition_hash,
      code_version = code_version,
      message = "",
      release_id = NA_character_
    )
  )
  run
}
finish_run <- function(
  lake,
  run,
  status,
  message = "",
  release = NA_character_
) {
  exec(
    lake,
    paste(
      "UPDATE",
      meta(lake, "runs"),
      "SET status = ?, finished_at = ?, message = ?, release_id = ? WHERE run_id = ?"
    ),
    list(status, now(), message, release, run)
  )
}
run_result <- function(run, status, release = NA_character_, quality = NULL) {
  structure(
    list(
      run_id = run,
      status = status,
      release_id = release,
      quality = quality
    ),
    class = "dl_run_result"
  )
}

emit_event <- function(lake, run, asset, type, recipient, message, notify) {
  event <- list(
    event_id = uid(),
    run_id = run,
    asset = asset,
    type = type,
    recipient = recipient,
    created_at = now(),
    status = "pending",
    message = message
  )
  # Suppress repeats for the same input + definition + event type after delivery.
  sql <- paste0(
    "SELECT count(*) AS n FROM ",
    meta(lake, "events"),
    " e JOIN ",
    meta(lake, "runs"),
    " r ON e.run_id=r.run_id JOIN ",
    meta(lake, "runs"),
    " cur ON cur.run_id=? WHERE e.asset=? AND e.type=? AND e.status='delivered' AND r.definition_hash=cur.definition_hash AND COALESCE(r.input_hash,'')=COALESCE(cur.input_hash,'')",
    " AND r.started_at > COALESCE((SELECT MAX(s.started_at) FROM ",
    meta(lake, "runs"),
    " s WHERE s.asset=cur.asset AND s.status IN ('published','cached') AND s.started_at < cur.started_at), '')"
  )
  duplicate <- query(lake, sql, list(run, asset, type))$n[[1]] > 0
  if (duplicate) {
    event$status <- "suppressed"
  }
  insert_meta(lake, "events", event)
  if (!duplicate && !is.null(notify)) {
    status <- tryCatch(
      {
        notify(event)
        "delivered"
      },
      error = function(e) "delivery_failed"
    )
    exec(
      lake,
      paste(
        "UPDATE",
        meta(lake, "events"),
        "SET status = ? WHERE event_id = ?"
      ),
      list(status, event$event_id)
    )
  }
  invisible(event)
}

persist_quality <- function(lake, run, contract, quality) {
  for (i in seq_len(nrow(quality))) {
    insert_meta(
      lake,
      "quality_results",
      c(
        list(
          run_id = run,
          contract = paste(contract$id, contract$version, sep = "@")
        ),
        as.list(quality[i, ])
      )
    )
  }
}
find_cached <- function(
  lake,
  asset,
  input_hash,
  definition_hash,
  current = FALSE
) {
  cached <- query(
    lake,
    paste(
      "SELECT release_id FROM",
      meta(lake, "releases"),
      "WHERE asset = ? AND input_hash = ? AND definition_hash = ? ORDER BY published_at DESC, release_id DESC LIMIT 1"
    ),
    list(asset, input_hash, definition_hash)
  )
  if (
    current &&
      nrow(cached) &&
      !identical(
        cached$release_id[[1]],
        resolve_release(lake, asset)$release_id[[1]]
      )
  ) {
    cached <- cached[0, , drop = FALSE]
  }
  cached
}

compose_candidate <- function(lake, raw, publish, run) {
  old <- tryCatch(
    resolve_release(lake, publish$asset),
    dl_no_release = function(e) NULL
  )
  parent <- if (is.null(old)) NA_character_ else old$release_id[[1]]
  data <- raw
  if (publish$mode == "replace_partition") {
    keys <- publish$partition_by
    if (!all(keys %in% colnames(raw))) {
      abort("Partition columns missing.")
    }
    if (count_rows(raw) == 0) {
      abort("Empty partition delivery cannot identify partitions to replace.")
    }
    for (key in keys) {
      if (count_rows(dplyr::filter(raw, is.na(!!rlang::sym(key)))) > 0) {
        abort("NULL partition values are forbidden.")
      }
    }
    if (!is.null(old)) {
      previous <- dl_tbl(lake, publish$asset, parent)
      if (!setequal(colnames(previous), colnames(raw))) {
        abort(
          "Partition replacement requires the same columns as the prior release."
        )
      }
      parts <- dplyr::distinct(dplyr::select(raw, dplyr::all_of(keys)))
      data <- dplyr::union_all(
        dplyr::anti_join(previous, parts, by = keys),
        dplyr::select(raw, dplyr::all_of(colnames(previous)))
      )
    }
  }
  name <- paste0("candidate_", run)
  candidate <- materialize(lake, data, publish$layer, name)
  list(data = candidate, name = name, parent = parent)
}

publish_candidate <- function(
  lake,
  run,
  publish,
  candidate,
  contract,
  quality,
  dh,
  ih,
  business_date,
  edges,
  before_commit = NULL
) {
  release <- paste0("rel_", run)
  # Publication marker and successful run state are committed in the SAME catalog.
  DBI::dbWithTransaction(lake$con, {
    current <- tryCatch(
      resolve_release(lake, publish$asset)$release_id[[1]],
      dl_no_release = function(e) NA_character_
    )
    if (!identical(current, candidate$parent)) {
      abort(
        "Publication conflict: another release changed this asset. Retry the run.",
        "dl_publication_conflict"
      )
    }
    insert_meta(
      lake,
      "releases",
      list(
        release_id = release,
        asset = publish$asset,
        schema_name = publish$layer,
        table_name = candidate$name,
        run_id = run,
        published_at = now(),
        contract = paste(contract$id, contract$version, sep = "@"),
        definition_hash = dh,
        input_hash = ih,
        quality = if (any(quality$status == "warning")) "warning" else "passed",
        business_date = as.character(business_date),
        parent_release = candidate$parent
      )
    )
    for (edge in edges) {
      insert_meta(
        lake,
        "lineage_edges",
        c(
          list(run_id = run),
          edge,
          list(
            to_id = publish$asset,
            to_version = release,
            relation = "published_from"
          )
        )
      )
    }
    finish_run(lake, run, "published", release = release)
    if (!is.null(before_commit)) before_commit()
  })
  run_result(run, "published", release, quality)
}

#' Run an ingestion pipeline
#' @param pipeline Pipeline specification.
#' @param lake Optional existing connection; otherwise opened from the
#'   specification.
#' @param business_date Business date of this delivery, separate from arrival
#'   time.
#' @param notify Optional function(event) using your existing notification
#'   transport.
#' @param stop_on_failure Stop after persisting failure metadata (recommended
#'   for jobs).
#' @param cache `TRUE` reuses any matching historical release, preserving
#'   idempotent job retries. `"current"` only reuses the current release;
#'   [dl_write()] uses this policy so writing older data makes it current again.
#'   Set `FALSE` to re-evaluate callbacks with external or changing state.
#' @return A run result with run_id, status, release_id and quality results.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' path <- file.path(root, "orders.csv")
#' utils::write.csv(data.frame(order_id = 1:2, amount = c(25, 75)), path,
#'   row.names = FALSE)
#' source <- dl_source("orders.file", path, reader = utils::read.csv)
#' contract <- dl_contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' pipeline <- dl_pipeline("orders.import", config, code_version = "v1") |>
#'   dl_step_land(source) |>
#'   dl_step_extract() |>
#'   dl_step_validate(contract) |>
#'   dl_step_publish("orders")
#' dl_run(pipeline, lake)
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_run <- function(
  pipeline,
  lake = NULL,
  business_date = NA_character_,
  notify = NULL,
  stop_on_failure = TRUE,
  cache = TRUE
) {
  if (is.character(cache)) {
    cache <- match.arg(cache, "current")
  } else {
    flag(cache, "cache")
  }
  check_pipeline(pipeline)
  own <- is.null(lake)
  if (own) {
    lake <- dl_connect(pipeline$config)
    on.exit(dl_disconnect(lake), add = TRUE)
  }
  assert_lake(lake)
  if (!identical(lake$config, pipeline$config)) {
    abort("Pipeline and execution lake configurations differ.")
  }
  src <- pipeline$steps$land
  contract <- pipeline$steps$validate
  input_contract <- pipeline$steps$precheck
  pub <- pipeline$steps$publish
  dl_register(lake, src)
  dl_register(lake, contract)
  if (!is.null(input_contract)) {
    dl_register(lake, input_contract)
  }
  dl_register(lake, pipeline)
  definition <- pipeline
  definition$config <- NULL
  dh <- fingerprint(definition)
  run <- new_run(lake, pipeline$id, pub$asset, dh, pipeline$code_version)
  result <- tryCatch(
    {
      landed <- land_source(lake, src)
      ih <- fingerprint(list(
        source = src$id,
        content = landed$hash,
        business_date = as.character(business_date)
      ))
      exec(
        lake,
        paste(
          "UPDATE",
          meta(lake, "runs"),
          "SET input_hash = ? WHERE run_id = ?"
        ),
        list(ih, run)
      )
      insert_meta(
        lake,
        "inputs",
        list(
          run_id = run,
          source = src$id,
          source_version = src$version,
          fingerprint = landed$hash,
          original_name = basename(src$path),
          landed_path = landed$uri,
          received_at = landed$received_at,
          business_date = as.character(business_date)
        )
      )
      cached <- if (!identical(cache, FALSE)) {
        find_cached(
          lake,
          pub$asset,
          ih,
          dh,
          current = identical(cache, "current")
        )
      } else {
        data.frame()
      }
      if (nrow(cached)) {
        finish_run(lake, run, "cached", release = cached$release_id[[1]])
        run_result(run, "cached", cached$release_id[[1]])
      } else {
        reader <- pipeline$steps$extract$using %||% src$reader
        extracted <- reader(landed$path)
        if (
          !identical(
            digest::digest(
              file = landed$path,
              algo = "sha256",
              serialize = FALSE
            ),
            landed$hash
          )
        ) {
          abort("Reader modified immutable landing input.")
        }
        input_quality <- NULL
        if (!is.null(input_contract)) {
          if (!is.data.frame(extracted)) {
            abort(
              "An input gate requires a materialized data frame from the reader."
            )
          }
          input_quality <- dl_validate(
            extracted,
            input_contract,
            stage = "ingest"
          )
          persist_quality(lake, run, input_contract, input_quality)
          if (!quality_ok(input_quality)) {
            abort(
              "Input quality gate blocked writing the raw table.",
              "dl_input_blocked",
              quality = input_quality
            )
          }
        }
        raw <- materialize(
          lake,
          extracted,
          pipeline$steps$extract$layer,
          paste0("raw_", run)
        )
        insert_meta(
          lake,
          "lineage_edges",
          list(
            run_id = run,
            from_id = src$id,
            from_version = landed$hash,
            to_id = paste0("raw.", pub$asset),
            to_version = run,
            relation = "extracted_from"
          )
        )
        transformed <- raw
        for (step in pipeline$steps$transform) {
          transformed <- tryCatch(
            step$transform(transformed),
            error = function(e) {
              abort(
                paste("Transform failed:", step$id),
                "dl_transform_failed",
                parent = e
              )
            }
          )
          if (
            !inherits(transformed, "tbl_sql") && !is.data.frame(transformed)
          ) {
            abort(
              paste(
                "Transform must return a data frame or lazy table:",
                step$id
              ),
              "dl_transform_failed"
            )
          }
        }
        candidate <- compose_candidate(lake, transformed, pub, run)
        quality <- dl_validate(candidate$data, contract)
        persist_quality(lake, run, contract, quality)
        quality <- dplyr::bind_rows(input_quality, quality)
        if (!quality_ok(quality)) {
          finish_run(
            lake,
            run,
            "blocked",
            "Candidate failed mandatory quality gate."
          )
          emit_event(
            lake,
            run,
            pub$asset,
            "quality_failed",
            contract$producer,
            "Publication blocked; inspect quality_results for this run.",
            notify
          )
          run_result(run, "blocked", quality = quality)
        } else {
          publish_candidate(
            lake,
            run,
            pub,
            candidate,
            contract,
            quality,
            dh,
            ih,
            business_date,
            list(list(from_id = paste0("raw.", pub$asset), from_version = run))
          )
        }
      }
    },
    dl_input_blocked = function(e) {
      finish_run(
        lake,
        run,
        "blocked",
        "Input quality gate blocked raw ingestion."
      )
      emit_event(
        lake,
        run,
        pub$asset,
        "quality_failed",
        input_contract$producer,
        "Input blocked before raw ingestion; inspect quality_results.",
        notify
      )
      run_result(run, "blocked", quality = e$quality)
    },
    error = function(e) {
      status <- if (inherits(e, "dl_missing_delivery")) "missing" else "error"
      # Avoid logging arbitrary exception text, which may contain source values or credentials.
      msg <- if (status == "missing") {
        "Expected source file is missing."
      } else {
        "Execution failed; inspect the local error condition."
      }
      finish_run(lake, run, status, msg)
      emit_event(
        lake,
        run,
        pub$asset,
        if (status == "missing") "delivery_missing" else "run_error",
        contract$producer,
        msg,
        notify
      )
      x <- run_result(run, status)
      x$error <- e
      x
    }
  )
  if (stop_on_failure && !result$status %in% c("published", "cached")) {
    abort(
      paste("Run", run, "ended with", result$status, "; metadata persisted."),
      "dl_run_failed",
      result = result,
      parent = result$error
    )
  }
  result
}
#' @export
print.dl_run_result <- function(x, ...) {
  cat("<dl_run>", x$run_id, "|", x$status, "| release:", x$release_id, "\n")
  invisible(x)
}

#' Identify interrupted runs without changing metadata
#' @param lake Connected lake.
#' @param older_than_hours Age after which a running job may need investigation.
#' @return Runs still marked running. Never auto-cancels a possibly live writer.
#' @export
#' @examples
#' root <- tempfile("lakefold-example-")
#' config <- dl_config(
#'   dl_catalog_duckdb(file.path(root, "lake.db")),
#'   dl_storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- dl_connect(config)
#' dl_interrupted(lake)
#' dl_disconnect(lake)
#' unlink(root, recursive = TRUE)
dl_interrupted <- function(lake, older_than_hours = 1) {
  runs <- dl_registry(lake, "runs")
  started <- as.POSIXct(
    runs$started_at,
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  )
  runs[
    runs$status == "running" &
      as.numeric(difftime(Sys.time(), started, units = "hours")) >
        older_than_hours,
  ]
}
