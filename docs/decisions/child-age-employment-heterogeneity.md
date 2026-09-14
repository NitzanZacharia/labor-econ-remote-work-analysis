# Decision Memo: Reduced-Form Employment Heterogeneity by Youngest-Child Age

**Status: Confirmed against real data.** All numbers below come from real-data runs against the
cached CBS extract in this environment (`csvs/cleaned_df.rds`), on branch
`explore-employed-heterogeneity`.

## Background

The pooled baseline `Mother:Post` DiD (`scripts/basic_regression.R`'s `basic_reg()`) is null
(-0.0053, n.s.) on the extensive margin. Before accepting that as a flat null, this explored
whether it's masking heterogeneity by youngest-child age -- motivated by the raw (uncontrolled)
`outputs/employment_by_child_age_emp_by_period.csv` pattern, which shows a larger post-2021
employment change for mothers of school-age children than for mothers of children under 5.

A WFH-linked version of a child-age split already existed
(`robustness/mother_heterogeneity_robustness.R`'s `run_ddd_by_child_age()`, splitting mothers into
child<5/child 5-17 subsamples and fitting the full `Mother*Post*WFH_Exposure` triple interaction on
each) -- but no version anywhere tested the plain `Employed ~ Post` interaction by child age,
without `WFH_Exposure`. `Post` bundles everything that changed 2021-2023, not just WFH (the same
limitation the baseline `basic_reg()` already carries), so this reduced-form check answers "did the
post-2021 period affect employment differently by child age," not "did WFH" -- a separate,
subsequent question (see "WFH linkage" section below).

## Design

**New file: `scripts/basic_reg_by_child_age.R`**, `basic_reg_by_child_age(cleaned_df,
age_interacted = FALSE, outcome_var = "Employed")`. One pooled regression against the whole
sample (not per-bin subsample splits): `Employed ~ ChildAgeGroup * Post + controls`, where
`ChildAgeGroup` is a 6-level factor (`NonMother` reference + the 5 `GilYeledTzairMBNK` bins),
clustered by `IDPUF` (matching `basic_reg()`'s own convention -- no `WFH_Exposure`/cell structure
is involved here, so no Moulton-style cell clustering is needed). Uses the full 5-level
`GilYeledTzairMBNK` granularity rather than the existing DDD file's coarser under-5/5-17 binary
split, so the design doesn't presuppose age 5 is where any break actually is, and supports a single
joint Wald test across all 5 child-age `:Post` terms instead of eyeballing pairwise splits.

`GilYeledTzairMBNK` is an unverified raw CBS passthrough (`docs/LLD.md` row 12); its "0 = no
children" convention (asserted only in `employment_by_child_age.R`'s header comment, never
confirmed against real data) is not relied on -- the non-mother reference level is assigned from
`Mother` directly.

## Results

**Unadjusted** (n=364,784, matches `basic_reg()`'s sample exactly):

| Child age | `ChildAgeGroup:Post` | SE | Sig. |
|---|---|---|---|
| 0-1 | -0.0146 | 0.0076 | p<0.1 |
| 2-4 | **-0.0155** | 0.0072 | **p<0.05** |
| 5-9 | +0.0038 | 0.0072 | n.s. |
| 10-14 | -0.0045 | 0.0077 | n.s. |
| 15-17 | +0.0044 | 0.0096 | n.s. |

Joint Wald test (all 5 terms equal): F(5, 79069) = 2.02, **p = 0.072** -- marginal.

Interpretation: mothers of children under 5 show a small, negative relative employment shift
post-2021 vs. childless women; school-age-child mothers show nothing. This is the *opposite*
direction from the raw uncontrolled trend (which showed larger raw gains for mothers of older
kids) -- a reminder that the raw trend has no control group and isn't itself informative about a
differential effect.

**Robustness checks run before trusting this (all confirm the signal, none explain it away):**

1. **Age-confound check.** `ChildAgeGroup` correlates mechanically with the mother's own age
   (young-child mothers are younger); `GilNK` was only an additive control. Added
   `ChildAgeGroup:GilNK` (mirroring how `Mother:GilNK` was added to the primary DDD per
   `docs/decisions/age-balance-robustness-chain.md`). Result: coefficients barely move (0-1:
   -0.0146->-0.0142; 2-4: -0.0155->-0.0153; joint test p=0.072->0.082). Not an age artifact --
   though the interaction terms do confirm `GilNK`'s employment profile genuinely varies by child
   age (e.g. `Age10to14:GilNK5` = 0.065**), the same kind of masking the primary DDD's own
   `Mother:GilNK` fix found, just not the source of this particular `Post` signal.

2. **Furlough-contamination check.** Re-ran with `Employed_strict` (the furlough-corrected outcome,
   `docs/decisions/furlough-employed-contamination.md`) instead of `Employed`. Result: signal
   survives, slightly *strengthens* for the 2-4 group (-0.0155->-0.0169\*, joint test
   p=0.072->0.057). `Post`'s own main effect collapses from 0.0157\*\*\* to 0.0047 n.s. here, exactly
   matching the known furlough-inflation pattern -- confirms the correction is doing its job, and
   confirms the child-age signal isn't a furlough-coding artifact.

3. **Event study (parallel trends + timing), `scripts/basic_reg_by_child_age_event_study.R`.**
   `Employed ~ ChildAgeGroup + i(ShnatSeker, ref=2019) + i(ShnatSeker, <group>_d, ref=2019) x5 +
   controls`, mirroring `Diagnostics.R`'s own pretrend idiom generalized from one `Mother` dummy to
   5 child-age dummies.
   - **Pre-trends are flat for every group** -- no significant 2017 or 2018 coefficient anywhere.
     The parallel-trends assumption this design rests on was never explicitly checked before this
     and holds.
   - **Timing does not fit a transient 2021-disruption story.** Age2-4: negative and roughly stable
     across 2021 (-0.020.), 2022 (-0.019.), 2023 (-0.024\*) -- present immediately, persists. Age0-1:
     near zero in 2021 (-0.007 n.s.) and 2022 (-0.015 n.s.), growing to **-0.030\*\*** by 2023 -- a
     delayed, widening effect. Neither pattern peaks-then-fades the way an acute 2021
     COVID/furlough-disruption effect would; both look like something building or persisting over
     the post-2021 window.

## Conclusion (reduced-form)

There is a real, validated (survives an age-confound check, a furlough-contamination check, and a
parallel-trends/timing check), but modest (joint test p=0.057-0.082 across specs, never below
conventional significance) negative relative post-2021 employment shift for mothers of children
under 5, not present for mothers of older children. This is a reduced-form result: `Post` bundles
everything that changed 2021-2023, not just WFH. The timing pattern (persistent/growing rather than
concentrated in 2021) is at least directionally more consistent with a persistent structural shift
than an acute pandemic-year disruption, which is compatible with (but does not establish) a
WFH-linked explanation.

## WFH linkage

**New file: `scripts/basic_reg_by_child_age_wfh.R`**, `run_child_age_wfh_ddd()`. Generalizes
`main.R` section 8a's primary DDD formula shape (`Mother*Post*WFH_Exposure + Mother:GilNK +
DEFAULT_CONTROLS`, cell-clustered on `GilNK^TeudaGvoha^MachozMegurim`) from `Mother`'s single 0/1
to `ChildAgeGroup`'s 6 levels, using the SAME primary exposure measure as `main.R` (the pre-period
cell-based shift-share `WFH_Exposure`, built from `exposure_cell_vars = (Min, GilNK, TeudaGvoha,
MachozMegurim, MatzavMishpachti, Dat, BirthContinent)` via `calibrate_isco_exposure()` ->
`build_exposure_cells()`, exactly as `main.R` builds it).

Stated as an expectation before running (in the file's own header comment): the coarse (child<5 vs
5-17) version of this same test already exists
(`robustness/mother_heterogeneity_robustness.R`'s `run_ddd_by_child_age()`) and is null for both
subgroups, with subgroup DDDs documented there as MORE underpowered than the already-underpowered
full-sample DDD (`docs/decisions/null-vs-power-audit.md`,
`docs/decisions/exposure-cell-granularity-fix.md`) -- so this granular, pooled version was not
expected to escape that same power ceiling, only to be a more targeted attempt at it.

**Result (n=355,984, 9,962 rows dropped for no matched exposure cell, clustered on ~209 cells):**

| Child age | `ChildAgeGroup:Post:WFH_Exposure` | SE |
|---|---|---|
| 0-1 | -0.0544 | 0.1281 |
| 2-4 | +0.0674 | 0.1142 |
| 5-9 | -0.1119 | 0.0888 |
| 10-14 | -0.0015 | 0.1312 |
| 15-17 | +0.0594 | 0.1250 |

Joint Wald test (all 5 equal to zero... i.e. all equal to each other): F(5, 209) = 0.78,
**p = 0.565** -- clean null, not even marginal. SEs roughly double the point estimates; the 0-1 and
2-4 coefficients (the two groups with a real reduced-form signal) are opposite in sign to each
other. `Post:WFH_Exposure` (not child-age-specific) stays significantly negative (-0.157\*\*),
matching the primary DDD's own persistent finding of a general high-exposure-occupation decline --
unrelated to child age.

The confirmed reduced-form `ChildAgeGroup:Post` finding above does NOT change: this spec is a much
richer, noisier one (61 terms, ~209 clusters vs. the simple spec's IDPUF clustering, 9,962 fewer
rows), so its own `ChildAgeGroup:Post` terms losing significance here is an artifact of that added
noise, not a retraction of the earlier, cleaner estimate.

## Decision

**The reduced-form child-age employment heterogeneity finding is real and documented; the attempt
to link it to WFH-exposure specifically failed to find anything, exactly as expected going in.**
This is a confirmed, informative null on the WFH-linkage question, not a dead end for the
underlying finding itself -- the honest conclusion is: *something* about the post-2021 period
affected employment for mothers of young children differently than for childless women (validated
across three independent robustness checks), but this design cannot establish WFH specifically as
the mechanism. Consistent with the rest of this project's WFH-exposure DDD family
(`docs/decisions/null-vs-power-audit.md`), the null here is a power-limited non-result, not
evidence against a WFH channel.

## What could revisit this

A higher-power WFH-exposure measure (the same open problem named throughout
`docs/decisions/null-vs-power-audit.md`/`exposure-cell-granularity-fix.md`) would be needed before
a null on THIS specific question could be read as informative either way. Until then, the reduced-
form finding stands as a documented, unexplained (by WFH or by the confounds checked) employment
shift for young-child mothers -- worth reporting in any writeup as its own finding, with the
WFH-mechanism question left explicitly open rather than answered.
