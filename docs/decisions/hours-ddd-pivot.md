# Decision Memo: Hours-Worked Pivot (Intensive-Margin DDD, Pure ISCO-08 Exposure, Generalized Lee Bounds)

**Status: IMPLEMENTED, off by default (`RUN_HOURS_DDD_PIVOT <- FALSE`).** Real-data results below are
confirmed but not yet reviewed for commit per `CLAUDE.md`'s disclosure-risk policy — the regenerated
`outputs/hours_ddd_pivot_*.csv` files are untracked and left for the user to review before staging.

## Motivation

The extensive-margin (`Employed`) primary DDD (`main.R`'s section 8a) remains underpowered even
after two successive, empirically-validated fixes to `WFH_Exposure`'s cell granularity
(`docs/decisions/exposure-cell-granularity-fix.md`): MDE is ~26% of baseline employment, roughly
4x the actual point estimate (-0.019 to -0.026), and cell-level WLS aggregation was confirmed
unable to recover any further power (same memo's "Considered and rejected" section).

This pivots the research focus from the extensive margin to the intensive margin: hours worked
(`WorkHoursCont`) among mothers who remained employed. This changes the exposure-measurement
tradeoff worked through in `exposure-cell-granularity-fix.md`. That memo rejected building
`WFH_Exposure` directly from ISCO-08 occupation codes for the **extensive**-margin DDD specifically
because occupation is undefined for the non-employed, and `Employed` — the extensive DDD's own
outcome — would then be conditioned on itself (a selection-on-the-outcome problem). The same memo's
own occupation-level robustness specs demonstrated the tradeoff concretely: ~9.7x tighter SE than
the cell-based design, but 17.4% of the sample dropped non-randomly along the employment margin.

That objection does not apply to an **hours** outcome: `WorkHoursCont` is already, by construction,
undefined for anyone with `Employed != 1` (`scripts/data_processing.R:184-193`) — conditioning the
hours regression on employment is intrinsic to the question, not introduced by the exposure choice.
This unlocks the pure occupation-level exposure (`exposure_calibrated`'s `wfh_exposure_calibrated`,
~40 ISCO-2 groups) as the DDD's regressor. Dropping non-employed rows to run this regression still
introduces a real selection-on-a-mediator problem for the hours estimate (if WFH differentially
pulls marginal mothers into employment, the post-period employed-mother sample isn't
compositionally comparable to the pre-period one) — exactly the mechanism
`scripts/intensive_margin_lee_bounds.R` already exists to bound, today only for the plain 2x2
`Mother x Post` intensive-margin regression. This pivot generalizes that machinery to the new
triple interaction (`Mother x Post x WFH_Exposure`).

## Design

**Outcome + exposure swap** (`scripts/hours_ddd_regression.R`, `run_hours_ddd_regression()`):
mirrors `scripts/ddd_regression.R`'s `run_ddd_regression()` Model 1 (triple interaction, occupation
join, cluster on occupation for the Moulton reasoning), but with `WorkHoursCont` as the LHS and
without the occupation-by-occupation mechanism second stage (not requested for this pivot).

**Generalized Lee bounds** (`scripts/hours_ddd_lee_bounds.R`, `run_hours_ddd_lee_bounds()`): the
key design decision (confirmed with the user before implementation) is that the Lee-bounds
selection-rate counterfactual is computed **separately within each quartile of the
demographic-cell-based `WFH_Exposure`** (the measure defined for the full sample, employed and
non-employed alike — reusing `robustness/age_balance_robustness.R`'s existing
`compute_pre_period_quartile_breaks()`/`assign_wfh_quartile()` helpers unchanged), while the
outcome regression itself (point estimate and each trimmed bound) uses the **occupation-level**
`WFH_Exposure` as the continuous regressor. Two different exposure measures serve two different
roles: the cell-based measure can stratify selection because it's observable pre-employment; the
occupation-level measure can't stratify selection (undefined for the non-employed) but is the more
precise regressor once someone is known to be employed. This is a genuine, deliberate extension of
Lee (2009)/the existing adaptation — see `hours_ddd_lee_bounds.R`'s header comment for the full
reasoning and stated limitations (the existing function's limitations all still apply, plus a new
one: a quartile with a thin `Mother==1,Post==1` cell makes that quartile's own `trim_prop` noisy —
`run_hours_ddd_lee_bounds()` warns whenever a quartile falls below 30 such rows).

The Imbens-Manski (2004) confidence-interval solver was extracted from
`intensive_margin_lee_bounds.R` into a shared `scripts/imbens_manski_ci.R` so both Lee-bounds files
reuse the same closed-form logic rather than duplicating it.

**Wiring**: `main.R`'s new section 8g, gated by `RUN_HOURS_DDD_PIVOT <- FALSE` (same convention as
`RUN_AGE_BALANCE_ROBUSTNESS`/`RUN_NULL_VS_POWER_AUDIT`) — diagnostic/exploratory, off by default,
not a replacement for the primary extensive-margin DDD.

## Real-data results (confirmed, not yet committed)

**Point estimate** (`run_hours_ddd_regression()`, women 25-59, `Employed == 1`, 281,622 of 288,400
employed rows — 97.6% — retained a matched occupation-level exposure; 275,708 rows after listwise
deletion on controls):

| Term | Coef | SE |
|---|---|---|
| `Mother:Post:WFH_Exposure` | **3.4073** | 0.9302 (clustered by occupation) |

`compute_ddd_mde()`: MDE = 2.6059 (alpha=0.05, power=80%), i.e. **6.8% of mean weekly hours**
(38.24) — the point estimate (3.41) is well outside the MDE, unlike the extensive-margin design.
The coefficient is significant at p<0.001.

**Generalized Lee bounds** (`run_hours_ddd_lee_bounds()`), selection rates and trim proportions by
`WFH_Exposure` quartile (cell-based measure):

| Quartile | s00 | s01 | s10 | s11 | s11* | n(Mother=1,Post=1) | Excess? | trim_prop |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.6284 | 0.6419 | 0.6045 | 0.6478 | 0.6180 | 21,655 | Yes | 4.61% |
| 2 | 0.7624 | 0.7867 | 0.7773 | 0.8037 | 0.8016 | 28,540 | Yes | 0.25% |
| 3 | 0.8167 | 0.8099 | 0.8651 | 0.8619 | 0.8584 | 34,293 | Yes | 0.41% |
| 4 | 0.8674 | 0.8514 | 0.8538 | 0.8501 | 0.8377 | 21,815 | Yes | 1.45% |

All four quartiles show modest excess selection (largest in quartile 1, the least-teleworkable
occupations); none is anywhere near large enough to overturn the point estimate. Resulting bounds:

| Bound | Coef | SE | 95% CI |
|---|---|---|---|
| Lower | 3.441 | 0.9927 | [1.496, 5.387] |
| Point (untrimmed) | 3.408 | 0.9564 | [1.533, 5.282] |
| Upper | 3.457 | 0.8975 | [1.698, 5.216] |

95% Imbens-Manski CI for the identified set: **[1.5035, 5.2091]** — entirely excludes zero.

**Interpretation.** Unlike the extensive-margin primary DDD, the hours-worked triple interaction is
statistically significant, well outside this design's own MDE, and robust to a Lee-bounds
correction for selection into employment stratified by exposure quartile — all three bounds and
the partial-identification CI stay solidly positive and significant. The positive sign indicates
that among mothers who remained employed, those in more WFH-exposed occupations saw a larger
post-2021 relative increase in hours worked than their less-exposed counterparts — the opposite
margin from, and a materially more informative result than, the null/underpowered extensive-margin
finding. This is a new, real finding for the paper to engage with, not a robustness check that
merely fails to overturn a null.

## Not yet decided

Per `CLAUDE.md`, nothing derived from real CBS microdata is committed without the user's explicit
review — the regenerated `outputs/hours_ddd_pivot_*.csv` files sit untracked pending that review.
Whether this becomes a second primary specification (alongside, not replacing, the extensive-margin
DDD) or stays a flagged robustness/exploratory analysis is a separate decision for the user, not
resolved by this memo.
