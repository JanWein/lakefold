#' Read a table from a pins board
#'
#' Pass a configured pins board; authentication belongs to pins. A version fixes
#' the requested revision when the board supports versioning. Without a version,
#' the current pin is read at execution time. Board credentials are excluded from
#' inspection. Pin contents must be a data frame or tibble.
#' @param board Configured pins board.
#' @param name Pin name.
#' @param version Optional pin version.
#' @returns A source specification for [add_source()].
#' @export
#' @examplesIf requireNamespace("pins", quietly = TRUE)
#' board <- pins::board_temp(versioned = TRUE)
#' pins::pin_write(board, data.frame(id = 1:2), "orders", type = "rds")
#' read_source(source_pins(board, "orders"))
source_pins <- function(board, name, version = NULL) {
  scalar(name, "name")
  if (!is.null(version)) {
    scalar(version, "version")
  }
  structure(
    list(board = board, name = name, version = version),
    class = "tw_pins_source"
  )
}

#' @export
check_component.tw_pins_source <- function(x, ...) {
  need("pins")
  if (!inherits(x$board, "pins_board")) {
    abort("board must be a configured pins board.")
  }
  invisible(x)
}

#' @export
read_source.tw_pins_source <- function(source, ...) {
  check_component(source)
  frame_result(
    pins::pin_read(source$board, source$name, version = source$version),
    "The pin"
  )
}

#' @export
inspect.tw_pins_source <- function(x, ...) {
  list(type = "pins", name = x$name, version = x$version)
}

#' @export
capabilities.tw_pins_source <- function(x, ...) {
  component_capabilities(
    read = TRUE,
    write = FALSE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}

#' Publish a checked table to a pins board
#'
#' Storage, authentication and version retention belong to pins and the board.
#' The output descriptor records the version reported by the board after writing
#' when available. Coordinate writers externally; this adapter does not promise
#' atomic or immutable publication. Extra arguments go to [pins::pin_write()].
#' @param board Configured pins board.
#' @param name Pin name.
#' @param type Storage format accepted by pins. Defaults to `"rds"`.
#' @param ... Named arguments to [pins::pin_write()], such as `versioned = TRUE`.
#' @returns A target specification for [set_target()].
#' @export
#' @examplesIf requireNamespace("pins", quietly = TRUE)
#' board <- pins::board_temp(versioned = TRUE)
#' product("orders") |>
#'   add_source(data.frame(id = 1:2)) |>
#'   set_target(target_pins(board, "orders")) |>
#'   run()
target_pins <- function(board, name, type = "rds", ...) {
  scalar(name, "name")
  scalar(type, "type")
  options <- list(...)
  adapter_named_options(options, c("board", "x", "name", "type", "metadata"))
  structure(
    list(board = board, name = name, type = type, options = options),
    class = "tw_pins_target"
  )
}

#' @export
check_component.tw_pins_target <- check_component.tw_pins_source

#' @export
write_target.tw_pins_target <- function(target, data, context, ...) {
  check_component(target)
  data <- adapter_frame(data)
  do.call(
    pins::pin_write,
    c(
      list(
        board = target$board,
        x = data,
        name = target$name,
        type = target$type,
        metadata = list(
          tidyweave = list(product = context$product, run_id = context$run_id)
        )
      ),
      target$options
    )
  )
  meta <- tryCatch(
    pins::pin_meta(target$board, target$name),
    error = function(e) {
      warning(
        "The pin was written, but its version metadata could not be read.",
        call. = FALSE
      )
      list()
    }
  )
  list(
    type = "pin",
    name = target$name,
    rows = nrow(data),
    version = meta$local$version %||% meta$version,
    hash = meta$pin_hash
  )
}

#' @export
inspect.tw_pins_target <- function(x, ...) {
  list(type = "pins target", name = x$name, format = x$type)
}

#' @export
capabilities.tw_pins_target <- function(x, ...) {
  component_capabilities(
    read = FALSE,
    write = TRUE,
    lazy = FALSE,
    transactions = FALSE,
    partition = FALSE,
    immutable = FALSE
  )
}
