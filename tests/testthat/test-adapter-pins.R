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
