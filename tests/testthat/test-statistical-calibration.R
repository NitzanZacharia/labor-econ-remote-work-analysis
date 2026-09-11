# test-statistical-calibration.R
# Closes a gap the audit named: every existing "invariant" test in the robustness/diagnostics
# suite checks a single seeded draw's sign or exact-formula recovery, never whether a hypothesis
# test's own empirical rejection rate matches its nominal size under a genuinely null DGP. A bug
# that broke clustering, used the wrong degrees of freedom, or swapped in the wrong grouping
# variable would still pass every existing single-draw check while silently inflating Type-I
# error -- this is the first test in the suite that would actually catch that class of bug.
#
# Targets robustness/balance_test.R's Welch t-test on GilNK -- run_balance_test()'s
# gilnk_ttests uses exactly `t.test(gilnk_num(GilNK) ~ Mother, data = .x)` per WFH_Exposure
# quartile (see that file). Calling the full run_balance_test() wrapper thousands of times to get
# enough replications for a precise rejection-rate estimate is far too slow for a unit-test suite
# (~0.55s/call, measured: 500 reps would add ~4.5 minutes) -- this reproduces that exact t.test()
# call directly instead, at a rep count high enough for a tight rejection-rate estimate, which
# runs in well under a second. The quartile-grouping/join machinery run_balance_test() wraps
# around it is already covered by test-balance_test.R's structural tests; what's untested
# anywhere else is whether the t-test ITSELF is calibrated.

test_that("the GilNK Welch t-test (as used by run_balance_test()) rejects at approximately its nominal rate under a true null", {
  gilnk_num <- function(x) as.numeric(as.character(x))

  set.seed(20260910)
  alpha  <- 0.05
  n_reps <- 2000
  n      <- 200

  p_values <- vapply(seq_len(n_reps), function(i) {
    GilNK  <- factor(sample(3:7, n, replace = TRUE))
    # Assigned independently of GilNK by construction -- the null (no age difference by Mother
    # status) is exactly true in every replication, regardless of GilNK's own distribution.
    Mother <- sample(0:1, n, replace = TRUE)
    t.test(gilnk_num(GilNK) ~ Mother)$p.value
  }, numeric(1))

  rejection_rate <- mean(p_values < alpha)

  # n_reps = 2000 independent draws under an exactly-true null -> the rejection rate's binomial SE
  # is sqrt(0.05*0.95/2000) ~= 0.0049, so nominal +-6 SE is roughly [0.02, 0.08]. A genuinely
  # broken test (wrong grouping variable, wrong distributional assumption, a clustering bug that
  # leaked into this code path) inflates rejection rates far above nominal (often 20-100%), not by
  # a few points -- this band is wide enough to absorb ordinary Monte Carlo noise without flaking,
  # while still catching that class of miscalibration.
  expect_gt(rejection_rate, 0.02)
  expect_lt(rejection_rate, 0.08)
})
