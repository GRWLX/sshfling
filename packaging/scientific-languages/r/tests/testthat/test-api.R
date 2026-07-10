testthat::test_that("the installed launcher exposes integer statuses", {
  testthat::expect_identical(sshfling::run(c("--version")), 0L)
  testthat::expect_identical(sshfling::run(c("--invalid-option")), 2L)
})
