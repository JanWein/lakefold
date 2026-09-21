# Accept libpq keyword/value strings without evaluating or logging credentials.
postgres_parameters <- function(value) {
  chars <- strsplit(value, "", fixed = TRUE)[[1]]
  n <- length(chars)
  i <- 1L
  out <- list()
  invalid <- function() {
    abort(
      "Use a libpq keyword=value connection string (or service=name), not a URI."
    )
  }
  whitespace <- function(x) x %in% c(" ", "\t", "\n", "\r")
  while (i <= n) {
    while (i <= n && whitespace(chars[[i]])) {
      i <- i + 1L
    }
    if (i > n) {
      break
    }
    key <- ""
    while (i <= n && grepl("^[A-Za-z0-9_]$", chars[[i]])) {
      key <- paste0(key, chars[[i]])
      i <- i + 1L
    }
    while (i <= n && whitespace(chars[[i]])) {
      i <- i + 1L
    }
    if (!nzchar(key) || i > n || chars[[i]] != "=") {
      invalid()
    }
    i <- i + 1L
    while (i <= n && whitespace(chars[[i]])) {
      i <- i + 1L
    }
    quoted <- i <= n && chars[[i]] == "'"
    if (quoted) {
      i <- i + 1L
    }
    text <- ""
    closed <- !quoted
    while (i <= n) {
      char <- chars[[i]]
      if (quoted && char == "'") {
        i <- i + 1L
        closed <- TRUE
        break
      }
      if (!quoted && whitespace(char)) {
        break
      }
      if (char == "\\") {
        i <- i + 1L
        if (i > n) {
          invalid()
        }
        char <- chars[[i]]
      }
      text <- paste0(text, char)
      i <- i + 1L
    }
    if (!closed || (i <= n && !whitespace(chars[[i]]))) {
      invalid()
    }
    out[[key]] <- text
  }
  if (
    !length(out) ||
      any(
        names(out) %in%
          c("drv", "bigint", "check_interrupts", "timezone", "timezone_out")
      )
  ) {
    invalid()
  }
  out
}

# Each writable API holds a session advisory lock until its calling frame exits.
# Reentrant calls sharing the same lake use the already-held lock.
acquire_lake_writer <- function(lake, frame) {
  if (!identical(lake$config$catalog$type, "postgres")) {
    return(invisible(NULL))
  }
  state <- lake$writer_state
  if (is.null(state)) {
    abort("Reconnect this lake to enable coordinated PostgreSQL writes.")
  }
  if (isTRUE(state$held)) {
    if (!DBI::dbIsValid(state$con)) {
      abort(
        "Writer coordination connection was lost. Reconnect and inspect the last release.",
        "tw_writer_lost"
      )
    }
    # Fail before any new mutation if the coordinator died while user code ran.
    tryCatch(DBI::dbGetQuery(state$con, "SELECT 1"), error = function(e) {
      abort(
        "Writer coordination connection was lost. Reconnect and inspect the last release.",
        "tw_writer_lost"
      )
    })
    return(invisible(NULL))
  }
  need("RPostgres")
  value <- Sys.getenv(lake$config$catalog$connection_env)
  if (!nzchar(value)) {
    abort(paste("Set", lake$config$catalog$connection_env))
  }
  parameters <- postgres_parameters(value)
  parameters$connect_timeout <- parameters$connect_timeout %||% "10"
  con <- tryCatch(
    do.call(DBI::dbConnect, c(list(drv = RPostgres::Postgres()), parameters)),
    error = function(e) {
      abort(
        "PostgreSQL writer coordination failed. Check catalog credentials and connectivity; credentials are omitted."
      )
    }
  )
  acquired <- FALSE
  on.exit(if (!acquired) DBI::dbDisconnect(con), add = TRUE)
  deadline <- Sys.time() + (lake$config$catalog$lock_timeout %||% 30)
  repeat {
    # Database-scoped constant: independent of user, DSN spelling and R session.
    locked <- DBI::dbGetQuery(
      con,
      "SELECT pg_try_advisory_lock(1953981814, 1) AS locked"
    )$locked[[1]]
    if (isTRUE(locked)) {
      break
    }
    if (Sys.time() >= deadline) {
      abort(
        "Another writer is publishing. Retry after it finishes; no changes were made by this operation.",
        "tw_writer_busy"
      )
    }
    Sys.sleep(0.1)
  }
  state$con <- con
  state$held <- TRUE
  acquired <- TRUE
  withr::defer(
    {
      state$held <- FALSE
      state$con <- NULL
      if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
    },
    envir = frame
  )
  invisible(NULL)
}

check_previous_release <- function(lake, asset, previous) {
  if (is.null(previous)) {
    return(invisible(NULL))
  }
  if (
    !inherits(previous, "tw_run_result") ||
      !previous$status %in% c("published", "cached") ||
      !identical(previous$asset, asset)
  ) {
    abort("previous must be a successful publication of this product.")
  }
  previous_config <- previous$output_config
  if (
    is.null(previous_config) ||
      !identical(previous_config$catalog, lake$config$catalog) ||
      !identical(previous_config$storage, lake$config$storage)
  ) {
    abort("previous belongs to a different lake configuration.")
  }
  current <- resolve_release(lake, asset)$release_id[[1]]
  if (!identical(current, previous$release_id)) {
    abort(
      "This product has a newer release. Read it and reconcile your correction before publishing again.",
      "tw_publication_conflict",
      expected_release = previous$release_id,
      current_release = current
    )
  }
  invisible(NULL)
}

assert_table_asset <- function(lake, asset) {
  prior <- tryCatch(resolve_release(lake, asset), tw_no_release = function(e) {
    NULL
  })
  if (!is.null(prior) && grepl("^(model|member)_", prior$table_name[[1]])) {
    abort(
      "This name belongs to a model product. Publish the complete model or choose a different table product name."
    )
  }
  invisible(NULL)
}
