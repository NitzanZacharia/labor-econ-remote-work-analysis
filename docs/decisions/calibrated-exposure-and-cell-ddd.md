# Decision Memo: Calibrated WFH-Exposure Index & Cell-Based Primary DDD

**Status: DECIDED — statistically-calibrated occupation exposure, swapped into a pre-period demographic-cell shift-share measure, is the primary DDD regressor.** See "Decision" at the bottom.

## The problem

Checkpoint 6/7 (`docs/ROADMAP.md`) built a single realized-WFH occupation index (`wfh_exposure_index.R`'s `build_wfh_exposure_index()`, anchored to 2021 per `docs/decisions/checkpoint6-wfh-anchor-year.md`) and fed it directly into the DDD mechanism regression (`ddd_regression.R`'s `run_ddd_regression()`). Two problems surfaced with using that index — or the external Dingel & Neiman teleworkability score alone — as the *primary* DDD regressor:

1. **Post-treatment contamination.** A purely realized (2021, or later 2022-23) WFH index is measured *after* the treatment period begins. Feeding it into the DDD as if it were an exogenous exposure measure risks the exposure regressor itself absorbing part of the treatment effect it's supposed to explain.
2. **Small-cell instability.** An earlier version of the pipeline combined the external and realized measures by swapping to realized values wherever the raw gap between them exceeded an arbitrary threshold, with no account of sampling noise. This let a 4-observation occupation cell (ISCO 63, subsistence farmers) swing the ranking on the strength of a single person surveyed 4 times in one year — the gap looked large (0.000 → 0.750) but was statistically indistinguishable from noise given how few observations backed it.
3. **Both problems compound in the DDD's exposure regressor specifically**, since that's the variable the paper's causal claim rests on.

## Options considered

**A. Keep a single occupation-level index (Checkpoint 6/7 as originally scoped), accept both problems.** Simplest, but leaves the DDD's central regressor exposed to exactly the two risks above with no mitigation.

**B. Statistically calibrate the swap decision; keep the DDD occupation-level.** Fixes problem 2 (small-cell instability) via a principled test, but not problem 1 (the calibration still draws on 2022-23 realized data, so it's a documented compromise rather than a clean pre-treatment measure) or the third-difference's implicit conditioning on `Employed` (an occupation code only exists for the employed, so an occupation-level DDD regressor structurally excludes non-employed rows from the third difference).

**C. Calibrate the swap decision (fixing problem 2), AND move the DDD's primary regressor to a pre-period (2017-2019) demographic-cell shift-share measure built from the calibrated occupation scores (mitigating problem 1 and the employment-conditioning issue).** Four separate exposure measures are kept, each reported, rather than collapsed into one "best" index — see the Decision below for why.

## Decision

**Option C.** Four exposure measures are built, each for a different purpose, and none is treated as a strict replacement for the others:

1. **External** (`build_exposure_isco2()`, `wfh_exposure_cells.R`) — the raw Dingel & Neiman teleworkability score via an O\*NET/SOC→ISCO crosswalk. Pre-period by construction (a US-task-based measure, immune to Israel's own COVID-era WFH behavior), but misclassifies occupations where Israeli institutional practice diverges sharply from the US task-content prediction — teaching (ISCO 23) is the clear case: D&N scores it near-ceiling teleworkable (0.966), but Israeli schools stayed in-person by Ministry of Education policy, and realized 2022-23 usage among Israeli teachers is 0.063.

2. **Calibrated** (`calibrate_isco_exposure()`, `wfh_exposure_cells.R`) — corrects the external score only where the realized-vs-external gap is large *and* well-powered enough that it can't plausibly be sampling noise: a one-sided, cluster-robust test (`cluster = ~IDPUF`, this project's clustering convention everywhere) of whether the true gap exceeds a substantive threshold (`gap_threshold = 0.5`) by more than the realized estimate's own sampling uncertainty, at `conf_level` confidence (default 95%). Occupations too thin to compute a cluster-robust SE at all (e.g. ISCO 63 — its 4 rows all belong to one `IDPUF`, so `feols()` reports "infinite or missing values") fail the test automatically and keep their theoretical value — the same outcome a flat sample-size floor would give, but derived from the estimator's own precision rather than a second, independently-chosen number. Still draws on 2022-23 realized data internally, so this remains a documented compromise, not a fully pre-treatment measure — reported alongside (3) and the primary measure (4) specifically so the paper can show whether conclusions depend on it.

3. **Realized** (`build_wfh_exposure_index()`, `wfh_exposure_index.R`) — the original Checkpoint 6 occupation index, 2021-anchored, `min_n = 200` to drop occupations too thin to trust. Post-treatment by construction — reported as a robustness check, not the primary measure.

4. **Cell-based shift-share** (`build_exposure_cells()`, `wfh_exposure_cells.R`) — **the primary DDD regressor.** Built entirely from **pre-period (2017-2019)** rows: each demographic cell (`Min × GilNK × TeudaGvoha × MachozMegurim`) gets a weighted average (by `MishkalSofi`) of the calibrated occupation exposure score (2), weighted by that cell's own pre-period occupational composition. Unlike (1)-(3), this is defined for **every row of `cleaned_df`, employed and non-employed alike** — it's the only one of the four that doesn't condition the DDD's third difference on `Employed`, the regression's own outcome variable.

**The primary DDD** (`main.R` §8a) regresses `Employed ~ Mother*Post*WFH_Exposure + controls` using measure (4), in two specs:
- **Spec 1 (additive controls):** `WFH_Exposure` is built from `(GilNK, TeudaGvoha, MachozMegurim)` — the same three variables `DEFAULT_CONTROLS` already includes additively — so it carries substantial overlap with its own controls. `ddd_collinearity_diagnostics.R`'s `check_spec1_collinearity()` reports this at runtime (R², VIF, design-matrix condition number) rather than leaving it as a static, unverified comment.
- **Spec 2 (interacted cell fixed effects):** the standard fix for a shift-share regressor like this. Fully interacted cell FE (`GilNK^TeudaGvoha^MachozMegurim`) absorb `WFH_Exposure`'s own cross-cell level entirely — its bare main effect becomes exactly collinear with the FE and `fixest` drops it automatically — so identification comes only from `Mother`'s and `Post`'s within-cell variation against the (cell-constant) exposure value. The triple interaction remains identified either way, since `Mother` and `Post` vary within a cell even though `WFH_Exposure` itself doesn't.

**The three occupation-level DDDs** (`run_ddd_regression()`, called once each with measures (2), (1), and (3) — `main.R` §8b-8d) remain as robustness checks, not the primary result, precisely because an occupation-level regressor structurally excludes non-employed rows from the third difference.

**Why not collapse to one index?** Doing so was the earlier version's actual mistake (problem 2 above) — a single combined index hides exactly the sensitivity (to the calibration threshold, to the pre-/post-treatment measurement choice, to employment-conditioning) that reporting all four, side by side, makes visible instead.
