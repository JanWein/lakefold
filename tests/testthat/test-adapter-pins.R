test_that("pins targets expose readable version references without board credentials", {
  skip_if_not_installed("pins")
  board <- pins::board_temp(versioned = TRUE)
  old <- data.frame(id = 1L)
  target <- target_pins(board, "orders")
  output <- write_target(target, old, list(product = "orders", run_id = "r1"))
  expect_true(nzchar(output$version))
  write_target(
    target,
    data.frame(id = 2L),
    list(product = "orders", run_id = "r2")
  )
  expect_equal(read_source(source_pins(board, "orders", output$version))$id, 1L)
  expect_equal(read_source(source_pins(board, "orders"))$id, 2L)
  expect_null(inspect(target)$board)
  expect_false(capabilities(target)$immutable)
  expect_false(capabilities(target)$transactions)
  expect_error(
    check_component(source_pins(list(token = "secret"), "orders")),
    "configured pins board"
  )
  expect_error(target_pins(board, "orders", metadata = list()), "reserved")
})

test_that("same-second pins publications identify their exact version and latest data", {
  skip_if_not_installed("pins")
  # Freeze only pins' timestamp allocation. Serialization, boards, storage and
  # reads are real. Choose descending hashes to reproduce the native ordering bug
  # independently of platform-specific RDS serialization.
  standard_meta <- get("standard_meta", asNamespace("pins"))
  pin_created <- "20000101T000000Z"
  testthat::local_mocked_bindings(
    standard_meta = function(...) {
      meta <- standard_meta(...)
      meta$created <- pin_created
      meta
    },
    .package = "pins"
  )
  board <- pins::board_temp(versioned = TRUE)
  data <- list(tibble::tibble(id = 1L), tibble::tibble(id = 2L))
  for (i in seq_along(data)) {
    pins::pin_write(board, data[[i]], paste0("probe", i), type = "rds")
  }
  hashes <- vapply(
    seq_along(data),
    function(i) {
      pins::pin_meta(board, paste0("probe", i))$pin_hash
    },
    character(1)
  )
  older <- data[[order(hashes)[2L]]]
  newer <- data[[order(hashes)[1L]]]
  target <- target_pins(board, "orders")
  first <- write_target(target, older, list(product = "orders", run_id = "r1"))
  second <- write_target(target, newer, list(product = "orders", run_id = "r2"))
  expect_identical(
    substr(first$version, 1L, 16L),
    substr(second$version, 1L, 16L)
  )
  expect_false(identical(first$version, second$version))
  expect_equal(read_source(source_pins(board, "orders")), newer)
  expect_equal(read_source(source_pins(board, "orders", first$version)), older)
  expect_equal(read_source(source_pins(board, "orders", second$version)), newer)
  expect_identical(
    pins::pin_meta(board, "orders", second$version)$user$tidyweave$run_id,
    "r2"
  )
  same <- write_target(target, newer, list(product = "orders", run_id = "r3"))
  expect_identical(same$version, second$version)
  expect_equal(nrow(pins::pin_versions(board, "orders")), 2L)
  expect_error(
    write_target(target, older, list(product = "orders", run_id = "r4")),
    class = "tw_pin_unconfirmed"
  )
  expect_equal(read_source(source_pins(board, "orders")), newer)
  expect_equal(nrow(pins::pin_versions(board, "orders")), 2L)
  # Forcing the native shortcut is safe once the pin's timestamp can advance.
  # Real pins serialization and storage allocate a distinct content version.
  pin_created <- "20000101T000001Z"
  reverted <- write_target(
    target_pins(board, "orders", force_identical_write = TRUE),
    older,
    list(product = "orders", run_id = "r5")
  )
  expect_false(identical(reverted$version, first$version))
  expect_equal(read_source(source_pins(board, "orders")), older)
  expect_equal(
    read_source(source_pins(board, "orders", reverted$version)),
    older
  )
  expect_equal(read_source(source_pins(board, "orders", second$version)), newer)
  reverted_meta <- pins::pin_meta(board, "orders", reverted$version)
  expect_identical(reverted_meta$user$tidyweave$run_id, "r5")
  expect_equal(reverted_meta$user$tidyweave$publication_order, 3)
  expect_equal(nrow(pins::pin_versions(board, "orders")), 3L)

  # An external write at the same timestamp has no framework ordering metadata.
  # Refuse to guess its position; an explicit reference still reads it normally.
  versions <- pins::pin_versions(board, "orders")$version
  pins::pin_write(board, tibble::tibble(id = 3L), "orders", type = "rds")
  external <- setdiff(pins::pin_versions(board, "orders")$version, versions)
  expect_error(
    read_source(source_pins(board, "orders")),
    class = "tw_pin_ambiguous"
  )
  expect_equal(read_source(source_pins(board, "orders", external))$id, 3L)
})

test_that("external pins and unchanged content keep the board's native reference", {
  skip_if_not_installed("pins")
  board <- pins::board_temp(versioned = TRUE)
  data <- tibble::tibble(id = 7L)
  pins::pin_write(board, data, "external", type = "rds")
  native <- pins::pin_meta(board, "external")$local$version
  expect_equal(read_source(source_pins(board, "external")), data)
  output <- write_target(
    target_pins(board, "external"),
    data,
    list(product = "external", run_id = "r1")
  )
  expect_identical(output$version, native)
  expect_equal(nrow(pins::pin_versions(board, "external")), 1L)
  expect_equal(read_source(source_pins(board, "external")), data)
})
