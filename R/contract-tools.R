#' Draft a contract from a table's column types
#'
#' Reads only a zero-row prototype for lazy tables. Required fields, keys,
#' units and business rules are never inferred from sample values. The draft
#' cannot be used for a quality gate or registered until explicitly confirmed.
#' @param data A data frame, lazy database table or Arrow table.
#' @param id Contract identifier.
#' @param owner,description,grain Optional business metadata.
#' @param version Contract definition version.
#' @param ... Additional arguments to [contract()], such as `key`,
#'   `required`, `rules`, `operator` or `column_metadata`.
#' @returns A printable `tw_contract_draft` inheriting from `contract`.
#' @seealso [contract_confirm()], [contract_diff()]
#' @export
#' @examples
#' draft <- contract_from(data.frame(id = 1:2, amount = c(10, 20)),
#'   "orders", "Analytics", "Order amounts", "One order", key = "id")
#' contract <- contract_confirm(draft)
#' validate(data.frame(id = 1L, amount = 10), contract)
contract_from <- function(
  data,
  id,
  owner = "",
  description = "",
  grain = "",
  version = "1.0.0",
  ...
) {
  columns <- infer_column_types(data)
  args <- list(...)
  if (!"required" %in% names(args)) {
    args$required <- character()
  }
  contract <- do.call(
    contract,
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
  class(contract) <- c("tw_contract_draft", "tw_contract")
  contract
}

infer_column_types <- function(data) {
  proto <- table_prototype(data)
  vapply(
    proto,
    function(x) {
      x <- contract_column_value(x)
      if (inherits(x, "Date")) {
        return("Date")
      }
      if (inherits(x, "POSIXct")) {
        return("POSIXct")
      }
      if (inherits(x, "integer64")) {
        return("integer64")
      }
      if (is.factor(x)) {
        return("character")
      }
      if (is.object(x)) {
        abort(paste0(
          "Column class `",
          class(x)[[1]],
          "` has no contract type. Convert it explicitly before validation."
        ))
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
      if (is.list(x)) {
        return("list")
      }
      abort("Unsupported column type in contract draft.")
    },
    character(1)
  )
}

table_prototype <- function(data) {
  if (is.data.frame(data)) {
    return(data[0, , drop = FALSE])
  }
  if (is_lazy_table(data)) {
    return(dplyr::collect(utils::head(data, 0)))
  }
  abort("data must be a data frame, lazy database table or Arrow table.")
}

contract_column_value <- function(x) {
  if (inherits(x, "AsIs")) {
    remaining <- setdiff(class(x), "AsIs")
    class(x) <- if (length(remaining)) remaining else NULL
  }
  x
}

contract_type_matches <- function(x, type) {
  x <- contract_column_value(x)
  switch(
    type,
    numeric = is.numeric(x) && !is.object(x),
    integer = is.integer(x) && !is.object(x),
    character = is.character(x) || is.factor(x),
    logical = is.logical(x) && !is.object(x),
    Date = inherits(x, "Date"),
    POSIXct = inherits(x, "POSIXct"),
    integer64 = inherits(x, "integer64"),
    list = is.list(x) && !is.object(x),
    FALSE
  )
}

#' Confirm a reviewed contract draft
#'
#' Confirms that the caller has reviewed the inferred types and chosen the
#' nullability, keys, rules and optional metadata. This is a local specification
#' transition, not an approval workflow or a proof that any data passed.
#' @param contract A draft from [contract_from()].
#' @returns A `contract` ready for registration and validation.
#' @export
#' @examples
#' draft <- contract_from(data.frame(id = 1L), "orders", "Analytics",
#'   "Order identifiers", "One order", key = "id")
#' contract_confirm(draft)
contract_confirm <- function(contract) {
  if (!inherits(contract, "tw_contract_draft")) {
    abort("contract must be a draft from contract_from().")
  }
  args <- unclass(contract)
  args[c("draft", "kind")] <- NULL
  args$columns <- unlist(args$columns, use.names = TRUE)
  do.call(tidyweave::contract, args)
}

assert_contract_ready <- function(contract) {
  if (inherits(contract, "tw_contract_draft") || isTRUE(contract$draft)) {
    abort(
      "Review the contract draft and call contract_confirm() first.",
      "tw_contract_draft"
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
#' old <- contract("orders", "1", "Analytics", "Orders", "One order",
#'   c(id = "integer"), key = "id")
#' new <- contract("orders", "2", "Analytics", "Orders", "One order",
#'   c(id = "integer", amount = "numeric"), key = "id")
#' contract_diff(old, new)
contract_diff <- function(old, new) {
  if (!inherits(old, "tw_contract") || !inherits(new, "tw_contract")) {
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
print.tw_contract_draft <- function(x, ...) {
  cat("<tw_contract_draft> Review business rules before confirming.\n")
  print.tw_contract(x, ...)
}
