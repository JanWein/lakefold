#' Draft a contract from a table's column types
#'
#' Reads only a zero-row prototype for lazy tables. Required fields, keys,
#' units and business rules are never inferred from sample values. The draft
#' cannot be used for a quality gate or registered until explicitly confirmed.
#' @param data A data frame or lazy database table.
#' @param id,owner,description,grain Explicit business metadata.
#' @param version Contract definition version.
#' @param ... Additional arguments to [dl_contract()], such as `key`,
#'   `required`, `rules`, `operator` or `column_metadata`.
#' @returns A printable `dl_contract_draft` inheriting from `dl_contract`.
#' @seealso [dl_contract_confirm()], [dl_contract_diff()]
#' @export
#' @examples
#' draft <- dl_contract_from(data.frame(id = 1:2, amount = c(10, 20)),
#'   "orders", "Analytics", "Order amounts", "One order", key = "id")
#' contract <- dl_contract_confirm(draft)
#' dl_validate(data.frame(id = 1L, amount = 10), contract)
dl_contract_from <- function(
  data,
  id,
  owner,
  description,
  grain,
  version = "1.0.0",
  ...
) {
  if (!is.data.frame(data) && !inherits(data, "tbl_sql")) {
    abort("data must be a data frame or lazy database table.")
  }
  proto <- if (inherits(data, "tbl_sql")) {
    dplyr::collect(utils::head(data, 0))
  } else {
    data[0, , drop = FALSE]
  }
  columns <- vapply(
    proto,
    function(x) {
      if (inherits(x, "Date")) {
        return("Date")
      }
      if (inherits(x, "POSIXct")) {
        return("POSIXct")
      }
      if (inherits(x, c("factor", "integer64")) || is.object(x)) {
        abort("Convert unsupported classed columns explicitly before drafting.")
      }
      if (is.integer(x)) {
        return("integer")
      }
      if (is.numeric(x)) {
        return("numeric")
      }
      if (is.character(x)) {
        return("character")
      }
      if (is.logical(x)) {
        return("logical")
      }
      abort("Unsupported column type in contract draft.")
    },
    character(1)
  )
  args <- list(...)
  if (!"required" %in% names(args)) {
    args$required <- character()
  }
  contract <- do.call(
    dl_contract,
    c(
      list(
        id = id,
        version = version,
        owner = owner,
        description = description,
        grain = grain,
        columns = columns
      ),
      args
    )
  )
  contract$draft <- TRUE
  class(contract) <- c("dl_contract_draft", "dl_contract")
  contract
}

#' Confirm a reviewed contract draft
#'
#' Confirms that the caller has reviewed the inferred types and supplied the
#' business meaning, nullability, keys and rules. This is a local specification
#' transition, not an approval workflow or a proof that any data passed.
#' @param contract A draft from [dl_contract_from()].
#' @returns A `dl_contract` ready for registration and validation.
#' @export
#' @examples
#' draft <- dl_contract_from(data.frame(id = 1L), "orders", "Analytics",
#'   "Order identifiers", "One order", key = "id")
#' dl_contract_confirm(draft)
dl_contract_confirm <- function(contract) {
  if (!inherits(contract, "dl_contract_draft")) {
    abort("contract must be a draft from dl_contract_from().")
  }
  args <- unclass(contract)
  args[c("draft", "kind")] <- NULL
  args$columns <- unlist(args$columns, use.names = TRUE)
  do.call(dl_contract, args)
}

assert_contract_ready <- function(contract) {
  if (inherits(contract, "dl_contract_draft") || isTRUE(contract$draft)) {
    abort(
      "Review the contract draft and call dl_contract_confirm() first.",
      "dl_contract_draft"
    )
  }
}

#' Compare contract definitions before changing a version
#'
#' Flags schema tightening conservatively. `breaking = NA` means semantic
#' review is required, for example after changing an R rule or row grain.
#' No compatibility result is inferred by running example data.
#' @param old,new Contract specifications.
#' @returns A tibble with `field`, `before`, `after` and `breaking`.
#' @export
#' @examples
#' old <- dl_contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' new <- dl_contract("orders", "2", "Analytics", "Orders", "One order",
#'   c(id = "integer", amount = "numeric"), key = "id")
#' dl_contract_diff(old, new)
dl_contract_diff <- function(old, new) {
  if (!inherits(old, "dl_contract") || !inherits(new, "dl_contract")) {
    abort("old and new must be contract specifications.")
  }
  changes <- list()
  add <- function(field, before, after, breaking) {
    if (!identical(jencode(before), jencode(after))) {
      changes[[length(changes) + 1L]] <<- tibble::tibble(
        field = field,
        before = jencode(before),
        after = jencode(after),
        breaking = breaking
      )
    }
  }
  for (column in union(names(old$columns), names(new$columns))) {
    add(
      paste0("columns.", column),
      old$columns[[column]],
      new$columns[[column]],
      TRUE
    )
  }
  add(
    "required",
    old$required,
    new$required,
    length(setdiff(new$required, old$required)) > 0
  )
  add("key", old$key, new$key, TRUE)
  add("allow_empty", old$allow_empty, new$allow_empty, !new$allow_empty)
  add("allow_extra", old$allow_extra, new$allow_extra, !new$allow_extra)
  for (field in c("grain", "rules", "column_metadata")) {
    add(field, old[[field]], new[[field]], NA)
  }
  for (field in c(
    "id",
    "version",
    "owner",
    "producer",
    "operator",
    "description",
    "max_age_hours"
  )) {
    add(field, old[[field]], new[[field]], FALSE)
  }
  if (!length(changes)) {
    return(tibble::tibble(
      field = character(),
      before = character(),
      after = character(),
      breaking = logical()
    ))
  }
  dplyr::bind_rows(changes)
}

#' @export
print.dl_contract_draft <- function(x, ...) {
  cat("<dl_contract_draft> Review business rules before confirming.\n")
  print.dl_contract(x, ...)
}
