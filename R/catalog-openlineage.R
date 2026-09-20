#' Send execution lineage to an OpenLineage endpoint
#'
#' Sends a START event using the recorded start time, followed by COMPLETE
#' or FAIL, after execution has finished. This is buffered historical lineage,
#' not live progress monitoring. Both events keep the same deterministic UUID
#' across [retry_catalogs()] calls. Delivery is at least once; a retry can
#' repeat an already accepted START event. Failed and blocked runs have no
#' output datasets. No data rows or executable transformation definitions are
#' sent. Output schema fields are included when available.
#'
#' External business catalogs consume descriptive metadata. They are distinct
#' from [registry()], which records the local lake publication lifecycle.
#' @param endpoint Full HTTP(S) OpenLineage ingestion URL, for example
#'   `https://lineage.example/api/v1/lineage`. Supply authentication through
#'   `request`, never embedded credentials or URL query parameters.
#' @param namespace Job and dataset namespace.
#' @param request Optional httr2 request or function accepting a request and
#'   returning a configured request. A zero-argument request factory is also
#'   accepted. Factories can obtain fresh credentials at delivery time. The
#'   adapter always restores its configured destination URL.
#' @returns A catalog adapter for [add_catalog()].
#' @seealso [catalog_openmetadata()], [retry_catalogs()]
#' @export
#' @examples
#' catalog <- catalog_openlineage("https://lineage.example/api/v1/lineage")
#' inspect(catalog)
catalog_openlineage <- function(
  endpoint,
  namespace = "tidyweave",
  request = NULL
) {
  catalog_endpoint(endpoint)
  scalar(namespace, "namespace")
  check_catalog_request(request)
  structure(
    list(
      id = paste0(
        "openlineage-",
        substr(fingerprint(list(endpoint, namespace)), 1L, 16L)
      ),
      endpoint = endpoint,
      namespace = namespace,
      request = request
    ),
    class = c("tw_openlineage_catalog", "tw_catalog_adapter")
  )
}

#' @export
check_component.tw_openlineage_catalog <- function(x, ...) {
  need("httr2")
  catalog_endpoint(x$endpoint)
  scalar(x$namespace, "namespace")
  check_catalog_request(x$request)
  invisible(x)
}

#' @export
inspect.tw_openlineage_catalog <- function(x, ...) {
  list(
    type = "OpenLineage",
    id = x$id,
    endpoint = x$endpoint,
    namespace = x$namespace,
    delivery = "buffered START and terminal event"
  )
}

#' @export
capabilities.tw_openlineage_catalog <- function(x, ...) {
  catalog_capabilities("OpenLineage", all_statuses = TRUE)
}

#' @export
publish_metadata.tw_openlineage_catalog <- function(catalog, metadata, ...) {
  check_component(catalog)
  events <- openlineage_events(catalog, metadata)
  for (event in events) {
    request <- catalog_request(catalog$endpoint, catalog$request)
    request <- httr2::req_body_json(request, event, auto_unbox = TRUE)
    request <- httr2::req_method(request, "POST")
    httr2::req_perform(request)
  }
  invisible(NULL)
}

openlineage_events <- function(catalog, metadata) {
  scalar(metadata$run_id, "metadata$run_id")
  scalar(metadata$product, "metadata$product")
  producer <- "https://github.com/JanWein/tidyweave"
  dataset <- function(name, schema = NULL) {
    result <- list(namespace = catalog$namespace, name = name)
    if (length(schema)) {
      result$facets <- list(
        schema = list(
          `_producer` = producer,
          `_schemaURL` = paste0(
            "https://openlineage.io/spec/facets/1-1-1/",
            "SchemaDatasetFacet.json#/$defs/SchemaDatasetFacet"
          ),
          fields = unname(lapply(names(schema), function(field) {
            list(name = field, type = as.character(schema[[field]]))
          }))
        )
      )
    }
    result
  }
  inputs <- metadata$inputs %||% list()
  if (is.data.frame(inputs)) {
    inputs <- safe_descriptors(inputs)
  }
  inputs <- unname(lapply(seq_along(inputs), function(i) {
    input <- inputs[[i]]
    source <- input$source %||% input
    name <- source$id %||%
      source$product %||%
      source$table %||%
      source$path %||%
      input$name %||%
      paste0(metadata$product, "/input-", i)
    dataset(paste(as.character(name), collapse = "."))
  }))
  successful <- metadata$status %in% c("completed", "published", "cached")
  event <- list(
    eventTime = event_time(metadata$started_at),
    producer = producer,
    schemaURL = "https://openlineage.io/spec/2-0-2/OpenLineage.json#/$defs/RunEvent",
    eventType = "START",
    run = list(runId = lineage_uuid(metadata$run_id)),
    job = list(namespace = catalog$namespace, name = metadata$product),
    inputs = inputs,
    outputs = list()
  )
  end <- event
  end$eventTime <- event_time(metadata$finished_at)
  end$eventType <- if (successful) "COMPLETE" else "FAIL"
  if (successful) {
    end$outputs <- list(dataset(metadata$product, metadata$schema))
  }
  list(event, end)
}

lineage_uuid <- function(run_id) {
  if (
    grepl(
      "^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$",
      run_id
    )
  ) {
    return(tolower(run_id))
  }
  hash <- digest::digest(
    paste0("tidyweave/run/", run_id),
    algo = "sha256",
    serialize = FALSE
  )
  paste(
    substr(hash, 1, 8),
    substr(hash, 9, 12),
    paste0("8", substr(hash, 14, 16)),
    paste0("8", substr(hash, 18, 20)),
    substr(hash, 21, 32),
    sep = "-"
  )
}

event_time <- function(value) {
  scalar(value, "Event timestamp")
  if (!grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z$", value)) {
    abort("Event timestamps must be ISO 8601 UTC strings ending in Z.")
  }
  value
}

catalog_endpoint <- function(endpoint) {
  scalar(endpoint, "endpoint")
  if (
    !grepl("^https?://[^/]+", endpoint) ||
      grepl("[?#]", endpoint) ||
      grepl("^https?://[^/]*@", endpoint)
  ) {
    abort(
      "Use an HTTP(S) endpoint without credentials, query or fragment; configure authentication with request."
    )
  }
  invisible(endpoint)
}

check_catalog_request <- function(request) {
  if (
    !is.null(request) &&
      !is.function(request) &&
      !inherits(request, "httr2_request")
  ) {
    abort("request must be NULL, an httr2 request or a request factory.")
  }
  invisible(request)
}

catalog_request <- function(endpoint, configure) {
  need("httr2")
  request <- httr2::request(endpoint)
  if (inherits(configure, "httr2_request")) {
    request <- configure
  }
  if (is.function(configure)) {
    request <- if (length(formals(configure))) {
      configure(request)
    } else {
      configure()
    }
  }
  if (!inherits(request, "httr2_request")) {
    abort("The catalog request factory must return an httr2 request.")
  }
  httr2::req_timeout(httr2::req_url(request, endpoint), 30)
}

catalog_capabilities <- function(backend, all_statuses = FALSE) {
  list(
    backend = backend,
    read = FALSE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE,
    metadata = TRUE,
    delivery = "at-least-once",
    statuses = if (all_statuses) {
      c("completed", "published", "cached", "blocked", "error", "missing")
    } else {
      c("completed", "published", "cached")
    }
  )
}
