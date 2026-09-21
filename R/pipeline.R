#' Build a pipeline specification
#' @param id Pipeline identifier.
#' @param lake A connection-free lake_config or a connected lake; only
#'   configuration is retained.
#' @param config Optional named alternative to lake for a connection-free
#'   lake_config.
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
#' @examples
#' contract <- contract(
#'   "orders", "1.0.0", "Analytics", "Order amounts", "One order",
#'   c(order_id = "integer", amount = "numeric"), key = "order_id"
#' )
#' pipeline <- tw_pipeline("orders.import", lake_config(backend = "duckdb"),
#'   code_version = "v1") |>
#'   tw_step_land(source_file("orders.file", "orders.csv", utils::read.csv)) |>
#'   tw_step_extract() |>
#'   tw_step_validate(contract) |>
#'   tw_step_publish("orders")
#' plan(pipeline)
#' @noRd
tw_pipeline <- function(
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
  config <- if (inherits(lake, "tw_config")) {
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
    class = "tw_pipeline"
  )
}
add_step <- function(pipeline, type, value) {
  if (!inherits(pipeline, "tw_pipeline")) {
    abort("Use tw_pipeline() first.")
  }
  if (type %in% names(pipeline$steps)) {
    abort(paste("Duplicate pipeline step:", type))
  }
  expected <- c("land", "extract", "validate", "publish")
  current <- setdiff(names(pipeline$steps), c("transform", "precheck"))
  if (!identical(type, expected[length(current) + 1L])) {
    abort(
      paste("Next pipeline step must be", expected[length(current) + 1L]),
      "tw_pipeline_invalid"
    )
  }
  pipeline$steps[[type]] <- value
  pipeline
}
#' @rdname tw_pipeline
#' @noRd
tw_step_land <- function(pipeline, source) {
  if (!inherits(source, "tw_source")) {
    abort("source must be a source_file.")
  }
  add_step(pipeline, "land", source)
}
#' @rdname tw_pipeline
#' @noRd
tw_step_extract <- function(pipeline, using = NULL, into = "raw") {
  ident(into)
  if (!is.null(using) && !is.function(using)) {
    abort("using must be a reader function.")
  }
  add_step(pipeline, "extract", list(using = using, layer = into))
}
#' @rdname tw_pipeline
#' @noRd
tw_step_validate <- function(pipeline, contract) {
  if (!inherits(contract, "tw_contract")) {
    abort("contract must be a contract.")
  }
  add_step(pipeline, "validate", contract)
}
#' @rdname tw_pipeline
#' @noRd
tw_step_publish <- function(
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
  invisible(lapply(partition_by, column_name))
  add_step(
    pipeline,
    "publish",
    list(asset = into, mode = mode, partition_by = partition_by, layer = layer)
  )
}

check_pipeline <- function(p) {
  if (!inherits(p, "tw_pipeline")) {
    abort("Use tw_pipeline() to define the workflow.", "tw_pipeline_invalid")
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
      "tw_pipeline_invalid"
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
  insert_meta(lake, "run_owners", c(list(run_id = run), writer_identity()))
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
    class = "tw_run_result"
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
    tw_no_release = function(e) NULL
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
      previous <- tbl(lake, publish$asset, parent)
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
      tw_no_release = function(e) NA_character_
    )
    if (!identical(current, candidate$parent)) {
      abort(
        "Publication conflict: another release changed this asset. Retry the run.",
        "tw_publication_conflict"
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

#' Execute a product
#'
#' Checks the complete definition and dependency graph before acquiring data.
#' Sources are acquired once, transformations run in order, and contract and
#' quality failures block publication. Shared upstream products run once within
#' the same execution. Without a target, the result retains its checked table;
#' [collect()] materializes lazy output when it is needed.
#'
#' Product execution options passed through `...` include:
#' * `data`: a new delivery replacing the sole primary input while retaining
#'   its name, transformations and checks. If the primary input is a product,
#'   its single-primary-input chain is followed to the ordinary delivery,
#'   retaining every intermediate product and gate. Ambiguous branches require
#'   an explicit name through `sources`.
#' * `sources`: a named list of replacements using [replace_sources()] names.
#'   Use either `data` or `sources`. The original definition and unselected
#'   pinned results remain unchanged. Both options replace whole inputs, not
#'   individual rows; partition replacement requires an explicit target policy.
#' * `execution`: an optional [execution_config()] value, overriding defaults
#'   stored by `product(execution = )`. Engine defaults
#'   propagate through dependencies; explicit step choices win. Destination and
#'   layer defaults apply only to the root product. Untargeted dependencies stay
#'   in memory, and existing dependency targets are preserved. Stored defaults
#'   on nested products are not activated during dependency execution.
#' * `stop_on_failure`: defaults to `TRUE`. Set `FALSE` to receive failed or
#'   blocked run results for programmatic inspection.
#' * `evidence`: an optional directory for durable run records. Defaults to
#'   `getOption("tidyweave.evidence")`; no evidence directory is required.
#' * `cache`: lake targets default to `FALSE`. `TRUE` reuses a matching current
#'   release and requires an explicit product `code_version`. Live reference
#'   quality checks cannot reuse cached releases.
#' * `business_date` and `notify`: optional lake publication context and an
#'   existing notification callback.
#'
#' Selecting a quality engine through execution defaults preserves the declared
#' contract's fingerprint. Execution evidence separately records the resolved
#' checking engine. An explicit product code version still identifies its
#' execution choices; a changed business promise needs a new contract version.
#'
#' Metrics and dbt project specifications also have execution methods; see
#' [measure()] and [dbt_build()] for their operation-specific options/results.
#' Managed dbt projects also accept `sources`, a named list of successful lake
#' releases. Bindings are validated before the dbt command runs.
#' @param pipeline Product to execute.
#' @param lake Optional connected lake or lake configuration, overriding the
#'   product's target for this run. Prefer [set_target()] in reusable definitions.
#' @param ... Execution options described above or provided by an adapter.
#' @returns For products, a run result containing status, timestamps, input and
#'   output descriptors, quality, metadata and lifecycle. On failure an error
#'   contains the same result in `condition$result`.
#' @seealso [publish()], [collect()], [inspect()], [run_history()]
#' @export
#' @examples
#' orders <- product("orders") |>
#'   add_source(data.frame(id = 1:2, amount = c(25, 75))) |>
#'   add_quality(~ amount >= 0)
#' result <- run(orders)
#' collect(result)
#' inspect(result)
run <- function(pipeline, lake = NULL, ...) UseMethod("run")

#' @export
#' @noRd
run.tw_pipeline <- function(
  pipeline,
  lake = NULL,
  business_date = NA_character_,
  notify = NULL,
  stop_on_failure = TRUE,
  cache = TRUE,
  ...
) {
  rlang::check_dots_empty()
  if (is.character(cache)) {
    cache <- match.arg(cache, "current")
  } else {
    flag(cache, "cache")
  }
  check_pipeline(pipeline)
  own <- is.null(lake)
  if (own) {
    lake <- connect_lake(pipeline$config)
    on.exit(disconnect_lake(lake), add = TRUE)
  }
  assert_writable(lake)
  expected_config <- pipeline$config
  expected_config$read_only <- expected_config$read_only %||% FALSE
  if (!identical(lake$config, expected_config)) {
    abort("Pipeline and execution lake configurations differ.")
  }
  src <- pipeline$steps$land
  contract <- pipeline$steps$validate
  input_contract <- pipeline$steps$precheck
  pub <- pipeline$steps$publish
  assert_table_asset(lake, pub$asset)
  register(lake, src)
  if (!isTRUE(pipeline$infer_contract)) {
    register(lake, contract)
  }
  if (!is.null(input_contract) && !isTRUE(pipeline$infer_input_contract)) {
    register(lake, input_contract)
  }
  register(lake, pipeline)
  definition <- pipeline
  definition$config <- NULL
  dh <- fingerprint(definition)
  run <- attr(pipeline, "tw_run_id")
  if (is.null(run)) {
    run <- new_run(lake, pipeline$id, pub$asset, dh, pipeline$code_version)
  } else {
    prior <- metadata_filter(lake, "runs", run_id = run)
    if (
      nrow(prior) != 1L ||
        prior$status[[1]] != "running" ||
        prior$pipeline[[1]] != pipeline$id ||
        prior$asset[[1]] != pub$asset
    ) {
      abort("The prepared product run is missing or no longer running.")
    }
    exec(
      lake,
      paste(
        "UPDATE",
        meta(lake, "runs"),
        "SET definition_hash = ? WHERE run_id = ?"
      ),
      list(dh, run)
    )
  }
  result <- tryCatch(
    {
      landed <- land_source(lake, src)
      ih <- fingerprint(list(
        source = src$id,
        content = landed$hash,
        business_date = as.character(business_date),
        product_inputs = lapply(
          attr(pipeline, "tw_product_inputs"),
          function(x) {
            x[c("source", "source_version", "fingerprint")]
          }
        )
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
      extra_inputs <- attr(pipeline, "tw_product_inputs") %||% list()
      for (input in if (isTRUE(attr(pipeline, "tw_inputs_recorded"))) {
        list()
      } else {
        extra_inputs
      }) {
        insert_meta(
          lake,
          "inputs",
          c(
            list(run_id = run),
            input,
            list(business_date = as.character(business_date))
          )
        )
      }
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
        if (isTRUE(pipeline$infer_input_contract)) {
          resolver <- attr(pipeline, "tw_resolve_input_contract")
          if (!is.function(resolver)) {
            abort(
              "Rebuild the ingestion from project code before executing it."
            )
          }
          input_contract <- resolver(extracted)
          assert_contract_ready(input_contract)
          register(lake, input_contract)
        }
        if (!is.null(input_contract)) {
          if (!is.data.frame(extracted)) {
            abort(
              "An input gate requires a materialized data frame from the reader."
            )
          }
          input_quality <- validate(
            extracted,
            input_contract,
            stage = "ingest"
          )
          persist_quality(lake, run, input_contract, input_quality)
          if (!quality_ok(input_quality)) {
            abort(
              "Input quality gate blocked writing the raw table.",
              "tw_input_blocked",
              quality = input_quality,
              diagnostic = list(data = extracted, contract = input_contract)
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
                "tw_transform_failed",
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
              "tw_transform_failed"
            )
          }
        }
        candidate <- compose_candidate(lake, transformed, pub, run)
        if (isTRUE(pipeline$infer_contract)) {
          resolver <- attr(pipeline, "tw_resolve_contract")
          if (!is.function(resolver)) {
            abort(
              "Rebuild this product from its project code before executing it."
            )
          }
          contract <- resolver(candidate$data)
          register(lake, contract)
        }
        quality_data <- if (!is.null(pipeline$composition)) {
          collect(candidate$data)
        } else {
          candidate$data
        }
        candidate_contract <- contract
        if (isTRUE(pipeline$input_rules_only)) {
          candidate_contract$rules <- list()
        }
        quality <- validate(quality_data, candidate_contract)
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
          blocked <- run_result(run, "blocked", quality = quality)
          blocked$diagnostic <- list(
            lake = lake,
            config = lake$config,
            schema = pub$layer,
            table = candidate$name,
            contract = candidate_contract
          )
          blocked
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
            c(
              list(list(
                from_id = paste0("raw.", pub$asset),
                from_version = run
              )),
              lapply(extra_inputs, function(input) {
                list(
                  from_id = input$source,
                  from_version = input$source_version
                )
              })
            )
          )
        }
      }
    },
    tw_input_blocked = function(e) {
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
      blocked <- run_result(run, "blocked", quality = e$quality)
      blocked$diagnostic <- e$diagnostic
      blocked
    },
    error = function(e) {
      status <- if (inherits(e, "tw_missing_delivery")) "missing" else "error"
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
  result$asset <- result$asset %||% pub$asset
  if (stop_on_failure && !result$status %in% c("published", "cached")) {
    abort(
      paste(
        run_result_message(result),
        "For diagnosis, rerun with stop_on_failure = FALSE and save the result. Inspect quality_report(result) and quality_rows(result)."
      ),
      "tw_run_failed",
      result = result,
      parent = run_result_parent(result)
    )
  }
  result
}
#' @export
print.tw_run_result <- function(x, ...) {
  cat(run_result_message(x), "\n")
  if (!x$status %in% c("completed", "published", "cached")) {
    cat(
      "Inspect quality_report(result) for checks and quality_rows(result) for affected rows.\n"
    )
  }
  invisible(x)
}

#' Identify interrupted runs without changing metadata
#' @param lake Connected lake.
#' @param older_than_hours Age after which a running job may need investigation.
#' @return Runs still marked running. Never auto-cancels a possibly live writer.
#' @export
#' @examplesIf requireNamespace("duckdb", quietly = TRUE)
#' root <- tempfile("tidyweave-example-")
#' config <- lake_config(
#'   registry_duckdb(file.path(root, "lake.db")),
#'   storage_local(file.path(root, "data")),
#'   landing = file.path(root, "landing"), backend = "duckdb"
#' )
#' lake <- connect_lake(config)
#' interrupted(lake)
#' disconnect_lake(lake)
#' unlink(root, recursive = TRUE)
interrupted <- function(lake, older_than_hours = 1) {
  runs <- registry(lake, "runs")
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

#' @export
run.default <- function(pipeline, lake = NULL, ...) {
  tw_execute(pipeline, lake, ...)
}
