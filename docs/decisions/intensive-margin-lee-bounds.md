# Decision Memo: Selection Correction for the Intensive-Margin Regression

**Status: DECIDED — Lee (2009) trimming bounds, adapted to this project's DiD design.** See "Decision" at the bottom.

## The problem

`intensive_margin_regression.R`'s `run_intensive_margin_reg()` (Checkpoint 4) estimates
`WorkHoursCont ~ Mother + Post + Mother:Post + controls` on the `Employed == 1` subsample only —
hours are only meaningful conditional on having a job.

But `Employed` is itself the outcome of this project's own extensive-margin DiD
(`basic_regression.R`). If WFH availability differentially pulls marginal mothers into employment
post-2021 — exactly the mechanism this project's central hypothesis predicts — the post-period
employed-mother sample is compositionally different from the pre-period one for reasons unrelated
to hours choices. This is a textbook selection-on-a-mediator problem: conditioning the hours
regression on a variable (`Employed`) that is downstream of the same treatment (`Mother × Post`,
via WFH) can bias the estimated `Mother:Post` coefficient in the hours equation, in a direction
that isn't signable a priori. Unlike other measurement caveats in this codebase (e.g.
`wfh_exposure_index.R`'s header comment), this one was previously undocumented anywhere in the
repo.

## Options considered

**A. Lee (2009) trimming bounds.** Nonparametric worst-case bounds on the treatment effect that
account for differential selection into the observed (`Employed == 1`) subsample, without assuming
a parametric selection model. Reports a `[lower, upper]` range rather than a point estimate.
*Pros*: no exclusion restriction needed, no distributional assumption beyond monotone selection;
standard in applied micro precisely for this "conditioning on a downstream outcome" problem.
*Cons*: bounds, not a point estimate — can be wide if the excess-selection share is large.

**B. Heckman-style two-step selection correction.** Parametric correction (probit for `Employed`,
inverse Mills ratio in the hours equation) recovering a point estimate. *Cons*: requires an
exclusion restriction — a variable affecting `Employed` but not `WorkHoursCont` — that this
dataset does not obviously have, plus a joint-normality assumption that would be hard to justify
here.

**C. Document only, no statistical correction.** Cheapest, but leaves the existing point estimate's
validity exactly as it was.

**D. Reframe as descriptive ("hours among the employed"), not causal.** Sidesteps the problem by
changing the claim rather than the estimator; loses the causal intensive-margin claim entirely.

## Decision

**Option A.** `intensive_margin_lee_bounds.R`'s `run_intensive_margin_lee_bounds()` implements a
DiD-adapted version of Lee bounds, run alongside (not instead of) the existing point estimate from
`run_intensive_margin_reg()`.

**The adaptation.** Classic Lee bounds compare one treated group to one control group with a fixed
selection rate. This project's design has two dimensions (`Mother`, `Post`), so "treatment" here is
specifically `Post`'s *differential* effect on `Mother == 1`'s selection into employment, relative
to what `Mother == 0`'s own pre/post change in selection implies — a parallel-trends-in-selection
counterfactual:

```
s_ab = P(Employed == 1 | Mother == a, Post == b)     for a, b in {0, 1}
s11_counterfactual = s10 + (s01 - s00)
```

If the actual `s11` exceeds this counterfactual, the excess share
`p = 1 - s11_counterfactual / s11` is trimmed from the `Mother == 1 & Post == 1` cell's
`WorkHoursCont` distribution — from the top for the lower bound, from the bottom for the upper
bound (Lee's standard monotone-selection assumption) — and `Mother:Post` is re-estimated on each
trimmed sample. Every other cell is left untouched.

**Known limitations of this adaptation** (stated in full in `intensive_margin_lee_bounds.R`'s
header comment):
- Only handles excess selection in the `Mother==1,Post==1` cell — the direction this project's own
  hypothesis predicts. Under-selection in that cell (fewer employed mothers than the counterfactual
  implies) is a missing-data problem, not an excess-observed-data problem, and isn't addressed by
  this construction.
- Relies on the same parallel-trends assumption already underlying the extensive-margin DiD itself
  (see `Diagnostics.R`'s pretrend check) to define the selection counterfactual `s11*`.
- Assumes monotone selection (WFH weakly increases, never decreases, a mother's employment
  probability) to justify trimming from a single tail.
- Consistent with this project's separate, deliberate decision not to apply `MishkalSofi` survey
  weights anywhere (see README.md's Known Limitations, `CLAUDE.md`): the selection rates `s_ab` are
  computed unweighted, matching every other regression in this repo.

This is a real methodological choice, not just an implementation detail — the trimmed bounds can be
wide if excess selection is large in the real data, and the direction-only limitation above means a
finding of "no excess selection" in the real data should be read as "this construction found
nothing to correct," not as proof the selection concern doesn't exist.
