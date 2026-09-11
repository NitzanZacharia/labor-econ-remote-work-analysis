# Decision Memo: Null-vs-Power Audit of the Primary DDD

**Status: VERIFIED AGAINST REAL DATA, NOT YET COMMITTED.** The two diagnostics below
(`scripts/wfh_first_stage_check.R`, `scripts/ddd_mde_diagnostics.R`) are built, unit-tested, and
have been run once against the real CBS extract to produce the numbers in this memo. Per
`CLAUDE.md`'s disclosure-risk rule, nothing derived from that run — including this memo's numbers
— should be committed until a human has explicitly reviewed it. `RUN_NULL_VS_POWER_AUDIT` is
`FALSE` in the committed `main.R`; the numbers below came from a one-off local run with the flag
temporarily flipped to `TRUE`, then reverted.

## Background

A 2026-09-11 audit (prompted by the pipeline's insignificant/unstable DDD results) ruled out the
classic bug hypotheses — miscoded `Mother`/`Post`/`Employed`, bad merges, unintended
collinearity — for the primary DDD (see `main.R`'s own comments at lines ~184-249 and
`scripts/ddd_collinearity_diagnostics.R`). `WFH_Exposure`'s main-effect drop in Spec 2 is
confirmed to be the intended, documented, unit-tested mechanism by which a shift-share regressor's
collinearity with its own cell-defining controls is resolved (`test-primary_ddd_mechanics.R`), not
a defect. That left one open question: **does this design have enough identifying variation to
detect a real effect, or is the null genuine?** This memo answers that question with two new
diagnostics.

## B1 — First-stage relevance check

`check_wfh_first_stage_relevance()` tests whether `WFH_Exposure` (the pre-period, 2017-2019,
demographic-cell shift-share measure) actually predicts realized WFH behavior once that becomes
measurable (`WFH_RefWeek` is only non-missing for `Post == 1`, so this is a within-post-period
check, not a differenced first stage — see the function's header comment for why a differenced
version isn't estimable here).

**Result, real data, `Post == 1` subsample (n = 113,844):**

| Spec | `WFH_Exposure` coefficient | Interpretation |
|---|---|---|
| Level | **1.787*** (SE 0.137)** | A cell one full unit higher in exposure has a ~1.79 percentage-point-per-unit higher probability of realized WFH — highly significant, large, and the expected sign. |
| Dynamic, `x ShnatSeker=2022` | 0.012 (SE 0.020, n.s.) | No detectable widening of the exposure gradient in 2022 relative to 2021. |
| Dynamic, `x ShnatSeker=2023` | 0.042. (SE 0.022, p<0.1) | A small, only marginally significant widening by 2023. |

**Conclusion: the shift-share design's core relevance assumption holds, strongly.**
`WFH_Exposure` is not a broken or noise regressor — it predicts real WFH-taking behavior with a
large, highly significant coefficient, essentially stable across 2021-2023. This rules out
"the exposure measure itself doesn't mean anything" as an explanation for the null DDD result.

## B2 — Minimum detectable effect (MDE)

`compute_ddd_mde()` computes the closed-form MDE (`SE * (qnorm(1 - α/2) + qnorm(power))`,
α=0.05, power=80%) for `Mother:Post:WFH_Exposure` in both primary-DDD specs, using each model's
own cluster-robust SE.

**Result, real data:**

| Spec | Point estimate | SE | MDE | Baseline employment rate | MDE as % of baseline |
|---|---|---|---|---|---|
| Spec 1 (additive controls) | 0.1033 | 0.1419 | **0.3975** | 0.7737 | **51.4%** |
| Spec 2 (interacted cell FE) | 0.1309 | 0.1399 | **0.3920** | 0.7737 | **50.7%** |

**Conclusion: this design is severely underpowered for the effect sizes actually in play.** To be
statistically distinguishable from zero at conventional power, `Mother:Post:WFH_Exposure` would
need to be roughly **0.39-0.40** — i.e., moving from the lowest to the highest exposure cell would
have to change mothers' *relative* post-2021 employment probability by about half the entire
baseline employment rate. That is not a plausible effect size for this kind of labor-market
mechanism. Both actual point estimates (0.103, 0.131) sit well inside their respective MDEs.

## Verdict

**Underpowered, not a genuine null.** The null `Mother:Post:WFH_Exposure` result is not
informative about whether a WFH-exposure-driven motherhood employment effect exists — the design
could not have detected a real effect unless that effect were implausibly large. This is not a
data-quality or specification problem: B1 confirms the exposure regressor is measuring something
real. It's a power problem, most likely rooted in `WFH_Exposure` being defined only at a coarse
demographic-cell level (≤~210 distinct cells) rather than varying at the occupation or individual
level, combined with Spec 1's ~74-77% collinearity with its own controls and Spec 2's
within-cell-only identification — both documented in
`docs/decisions/calibrated-exposure-and-cell-ddd.md` and
`scripts/ddd_collinearity_diagnostics.R`, and now shown here to cost enough precision that the
triple interaction cannot be read as evidence either for or against a WFH-mediated effect.

**Not pursued (deferred per the 2026-09-11 scoping decision):** B3 (leave-one-occupation-out
influence check on the calibrated occupation-level spec's sign flip) and B4 (post-window
sensitivity around the significant `Mother:2023` event-study coefficient). Both were designed as
follow-ups only if B1/B2 didn't settle the question — they did, so B3/B4 remain optional future
work if a higher-power version of the design (e.g., occupation-level rather than cell-level
exposure, at the cost of the demographic-cell shift-share's other advantages) is pursued instead.

## What this does NOT mean

This does not mean the underlying research question is unanswerable — it means the current
cell-based primary DDD, as specified, cannot answer it with the available sample size and this
demographic-cell granularity. A design change (finer exposure cells, occupation-level exposure
with a different collinearity tradeoff, or a much larger sample) would be needed before a null
result here could be read as evidence of no effect.

## What was wired into `main.R`

Behind `RUN_NULL_VS_POWER_AUDIT` (default `FALSE`, so no behavior change for existing runs unless
explicitly enabled): `check_wfh_first_stage_relevance()` and `compute_ddd_mde()` (both specs),
exported (when the flag is on) as `null_vs_power_audit` in `outputs/`, aggregate-only (an etable
and two closed-form MDE summaries — no row-level output).
