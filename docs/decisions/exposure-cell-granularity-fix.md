# Decision Memo: Exposure-Cell Granularity Fix for the Underpowered Primary DDD

**Status: Confirmed against real data.**

## Background

`docs/decisions/null-vs-power-audit.md` established that the primary DDD's null
`Mother:Post:WFH_Exposure` result is not a genuine null — the design's minimum detectable effect
(MDE) was ~0.39-0.40 (both specs), roughly 51% of the baseline employment rate, while the actual
point estimates were only 0.103 (Spec 1) / 0.131 (Spec 2). That memo didn't diagnose *why* the
design was underpowered; this memo does, and fixes it.

**Root cause.** `WFH_Exposure` was built by `build_exposure_cells()` on exactly the same three
variables (`GilNK`, `TeudaGvoha`, `MachozMegurim`) used as the primary DDD's own controls (Spec 1,
additively) and fixed effect (Spec 2, fully interacted). Since `WFH_Exposure` is constant within
each such cell by construction, this mechanical alias directly caused Spec 1's collinearity
(R²=0.770, VIF=4.3 against those controls) and Spec 2's near-total loss of identifying power
(`WFH_Exposure`'s bare main effect was exactly collinear with the FE and auto-dropped by `fixest`,
leaving only `Mother`/`Post`'s own within-cell variation to identify the triple interaction).

## The fix

`DEFAULT_CONTROLS` includes two variables NOT part of the old exposure-cell definition:
`MatzavMishpachti` (marital status) and `Dat` (religion) — both pre-period demographic variables
observed for everyone regardless of employment status, so folding them into the exposure-cell
definition doesn't reintroduce the "exposure only defined for the employed" selection problem the
cell-based design exists to avoid (unlike occupation-level exposure, which was considered and
rejected for exactly that reason — see "Options considered" below). Building `WFH_Exposure` on a
partition that additionally varies by `MatzavMishpachti`/`Dat`, while leaving the regression's own
controls/FE (`cell_fe_vars`) unchanged at the original 3 variables, means `WFH_Exposure` now
varies *within* every FE cell — restoring real identifying variation for
`Mother:Post:WFH_Exposure`.

## Empirical validation (real data, four candidates)

Ran the fix hypothesis against the real cached CBS extract, comparing the baseline exposure-cell
definition to three finer candidates, holding `cell_fe_vars`/controls fixed throughout:

| Candidate | `cell_vars` | Distinct cells | `n_cell` (weighted) min / p25 / median | R² on `cell_fe_vars` | VIF | Spec 1 coef / SE / MDE (% baseline) | Spec 2 coef / SE / MDE (% baseline) |
|---|---|---|---|---|---|---|---|
| 0 (baseline) | +4 vars | 490 | 699 / 23,716 / 111,247 | 0.770 | 4.35 | 0.1033 / 0.1419 / 0.3975 (51.4%) | 0.1309 / 0.1399 / 0.3920 (50.7%) |
| 1 (+`MatzavMishpachti`) | +5 vars | 1,859 | 74.6 / 2,478 / 7,966 | 0.567 | 2.31 | 0.0162 / 0.1191 / 0.3338 (43.1%) | 0.0296 / 0.1196 / 0.3350 (43.3%) |
| 2 (+`Dat`) | +5 vars | 1,774 | 107 / 2,635 / 8,747 | 0.537 | 2.16 | −0.0256 / 0.1018 / 0.2853 (36.9%) | −0.0123 / 0.1006 / 0.2819 (36.4%) |
| **3 (+both)** | **+6 vars** | **4,580** | **74.6 / 1,014 / 2,803** | **0.387** | **1.63** | **−0.0331 / 0.0890 / 0.2494 (32.2%)** | **−0.0259 / 0.0881 / 0.2469 (31.9%)** |

Unmatched rows after the join (pre-period cell combination not observed): 0 (Candidate 0), 598
(0.16%, Candidate 1), 607 (0.16%, Candidate 2), 4,908 (1.32%, Candidate 3).

**Decision rule applied:** accept the finest candidate that (a) keeps median `n_cell` comfortably
above 100 (the weighted-mean shift-share construction is less noise-sensitive per observation than
a raw proportion, so 100 is a reasonable floor for the median, not the stricter 200 used for
`build_wfh_exposure_index()`'s realized-proportion measure), and (b) cuts Spec 2's MDE by at least
30% relative to baseline.

**Candidate 3 wins outright:** finest partition, only 2 of 4,580 cells (0.04%) fall below n=100,
and Spec 2's MDE drops from 0.392 to 0.247 — a **37.0%** reduction (Spec 1: 37.3%). No small-cell
backoff safeguard was needed — `build_exposure_cells()`'s signature/default is untouched.

**Directly confirmed, not assumed:** the "variable removed because of collinearity" message that
`fixest` prints for Candidate 0's Spec 2 does **not** appear for Candidates 1/2/3 — `WFH_Exposure`'s
bare main effect survives once the exposure cell is finer than the FE, exactly as hypothesized.
`main.R`'s `check_for_dropped_coefficients(ddd_primary_fe, ...)` call had its
`expected_drops = "WFH_Exposure"` argument removed accordingly, so a warning now fires on ANY
unexpected drop in Spec 2, including this one, rather than silently whitelisting it.

## What changed

- `main.R`: `build_exposure_cells()`'s call now passes `cell_vars = exposure_cell_vars =
  c("Min","GilNK","TeudaGvoha","MachozMegurim","MatzavMishpachti","Dat")` explicitly; the
  function's own default (used by every other call site) is untouched. The `ddd_df` join's `by =`
  list was updated to match, with a new post-join message reporting unmatched-row counts so a
  future key-list drift is caught immediately rather than silently producing all-`NA`
  `WFH_Exposure`. `cell_fe_vars`/`other_controls` (Spec 1's controls, Spec 2's FE) are unchanged.
  Comments at the top of §8a and around the collinearity/clustering rationale were rewritten to
  describe the new, deliberately-finer design instead of the old aliased one.
- **A latent fan-out bug was found and fixed while implementing this**: `robustness/balance_test.R`,
  `robustness/age_balance_robustness.R`, and `robustness/phase2_robustness.R` all receive
  `main.R`'s `exposure_cells` as a parameter and hardcoded the *old* 4-variable join key
  internally. Left unfixed, passing the new 6-variable `exposure_cells` into any of them (e.g. via
  `RUN_AGE_BALANCE_ROBUSTNESS`) would have silently fanned out rows (multiple `exposure_cells` rows
  sharing the old 4-tuple but differing on `MatzavMishpachti`/`Dat`) rather than erroring. Fixed by
  deriving the join key from `exposure_cells`'s own columns
  (`setdiff(names(exposure_cells), c("WFH_Exposure","n_cell"))`) instead of hardcoding it — behavior
  is unchanged for any caller still using the function's 4-variable default (confirmed: all
  existing tests for these files pass unmodified). `scripts/gender_placebo.R` builds its own,
  separate, self-consistent 4-variable `exposure_cells_men` and was left untouched — it isn't
  fed `main.R`'s `exposure_cells`, so there's no fan-out risk there, only a (pre-existing,
  out-of-scope) design difference from the primary spec.
- `tests/testthat/test-primary_ddd_mechanics.R`: added a new synthetic-panel test asserting the
  opposite of the existing "Spec 2 drops WFH_Exposure" test — with exposure cells genuinely finer
  than the FE, `WFH_Exposure`'s main effect now survives. The original test is kept unmodified; it
  still correctly documents the general aliasing mechanism whenever exposure cells match the FE
  exactly.

## Post-fix numbers (Candidate 3, real data, full pipeline)

Confirmed end-to-end against the real CBS extract via a full `main.R` run with
`RUN_NULL_VS_POWER_AUDIT`/`RUN_AGE_BALANCE_ROBUSTNESS` both temporarily on (then reverted to their
committed `FALSE` defaults):

- **Primary DDD, real formulas (including `Mother:GilNK`)**: Spec 1
  `Mother:Post:WFH_Exposure` = −0.0331 (SE 0.0890); Spec 2 = −0.0260 (SE 0.0881) — matches the
  standalone diagnostic almost exactly (tiny difference from `Mother:GilNK`'s inclusion).
  `check_spec1_collinearity()`: R²=0.387, VIF=1.6, condition number=146.0.
- **`WFH_Exposure`'s bare main effect in Spec 2 is printed with a real coefficient
  (−0.0276, SE 0.0755)** — not blank/dropped, confirmed directly in the `etable()` output (unlike
  the pre-fix design, where that row was blank because `fixest` had removed it). No
  "unexpected drop" warning fired from either `check_for_dropped_coefficients()` call on the
  primary DDD.
- **First-stage relevance holds under the new design too**: `WFH_Exposure` → `WFH_RefWeek`
  (`Post==1` only) = 0.9313*** (SE 0.124, level spec), 0.9157*** (dynamic spec) — still large,
  highly significant, and stable across 2021-2023 (2023 vs. 2021: +0.036, p<0.1).
- **MDE, confirmed**: Spec 1 = 0.2494 (32.2% of baseline), Spec 2 = 0.2469 (31.9% of baseline) —
  exact match to the standalone diagnostic script.
- **Age-balance robustness chain (`RUN_AGE_BALANCE_ROBUSTNESS`) ran cleanly** with the
  dynamically-derived join key: `run_balance_test()` matched 199,776 pre-period rows (vs. 201,388
  under the old 4-variable design — the small drop is the same unmatched-cell effect seen in the
  primary DDD, not an error), and the age-interacted/reweighted comparison specs and pretrend Wald
  test all completed without error.
- The **substantive point estimate is now small and slightly negative** (−0.026 to −0.033) rather
  than positive (0.103–0.131 under the old design) — still far short of the (much-improved but
  still large, ~32%-of-baseline) MDE, so this remains an underpowered-not-informative result, not
  a newly-significant finding. The sign flip itself is not evidence of anything beyond sampling
  noise at this SE.

## Options considered and rejected

- **Occupation-level or predicted-continuous exposure** (higher resolution, closer to individual
  variation): rejected — occupation is only observed for the employed, so any occupation-based
  exposure measure structurally excludes non-employed rows from the DDD's third difference, which
  is exactly the problem the cell-based design (measure 4 in
  `docs/decisions/calibrated-exposure-and-cell-ddd.md`) exists to avoid. Out of scope for this fix.
- **Coarser cell definition** (dropping a `cell_fe_vars` dimension, e.g. `MachozMegurim`): tested
  as a sanity check, not a candidate — this would also change `cell_fe_vars` itself, which was held
  fixed by design; predictably increases `n_cell` and (by the same logic in reverse) does not
  restore within-FE-cell variation, since it doesn't change the exposure/FE alias at all.
- **Small-cell backoff/shrinkage** (fall back to a coarser aggregate below a size floor, mirroring
  `calibrate_isco_exposure()`'s pattern): designed but not needed — Candidate 3's cell-size support
  was already adequate (99.96% of cells above n=100).

## Relationship to `docs/decisions/null-vs-power-audit.md`

That memo's root-cause diagnosis (why the null was uninformative) is superseded by this one; its
own real-data numbers are left intact as a historical record of the pre-fix design, not rewritten.

## Update: adding `BirthContinent` (same design, a 7th safe dimension)

**Status: Confirmed against real data.**

**Motivation.** The user asked why `WFH_Exposure` isn't built directly from ISCO-08 occupation
codes. Analysis showed that would reintroduce a selection-on-the-outcome problem (occupation is
only defined for the employed, and `Employed` is the DDD's own dependent variable — the existing
occupation-level robustness specs already demonstrate this: ~9.7x tighter SE than the cell-based
design, but 17.4% of the sample dropped non-randomly along the employment margin). A follow-up
exploration into a continuous/predicted-exposure redesign instead found, somewhat counter-
intuitively, that a naive additive regression is *worse* than the current discrete-cell approach:
`build_exposure_cells()`'s cell-mean construction is already mathematically equivalent to a
fully-saturated interaction model (R²=0.322 against `tele_ext` on the pre-period employed
population), while the same variables fit *additively* only reach R²=0.266 — a 17% relative loss,
plus a small rate of nonsensical out-of-[0,1] fitted values the saturated cell-mean approach is
mechanically immune to. A fully-interacted `lm()` on this data also crashes with an out-of-memory
error; only `feols()`'s FE machinery (already how `build_exposure_cells()` works) handles full
saturation on data this size.

That exploration did surface one genuinely new, safe, high-value covariate: `BirthContinent`
(`scripts/data_processing.R:141-153` — country of birth grouped into
Israel/Asia/Africa/Europe/North America/Other, factor, 6 levels, 0.2% NA, derived from raw
`SemelEretzLeda`). It's pre-determined, defined for everyone regardless of employment status
(unlike e.g. `MachozYishuvAvoda`, workplace municipality, confirmed empirically to be 71% missing
among the non-employed — correctly excluded), and empirically the strongest predictor of `tele_ext`
tested: adding it to the saturated cell design raises R² from 0.322 to 0.375, the largest gain of
any candidate (`Leom` and `MisparHorimYechidim` added almost nothing; the children-count family of
variables were excluded by design since they're the literal source of the `Mother` indicator).

**Empirical validation (real data):**

| Candidate | `cell_vars` | Distinct cells | `n_cell` min / p25 / median | Unmatched rows | R² on `cell_fe_vars` | VIF | Spec 1 MDE (% baseline) | Spec 2 MDE (% baseline) |
|---|---|---|---|---|---|---|---|---|
| 0 (current: 6 vars) | ...+`MatzavMishpachti`+`Dat` | 4,580 | 74.6 / 1,014 / 2,803 | 4,908 (1.32%) | 0.387 | 1.63 | 0.2494 (32.2%) | 0.2469 (31.9%) |
| **1 (+`BirthContinent`: 7 vars)** | **...+`BirthContinent`** | **8,884** | **30.2 / 787.5 / 1,776** | **9,962 (2.67%)** | **0.285** | **1.40** | **0.2031 (26.3%)** | **0.2022 (26.1%)** |

Cell-size support stays very healthy (median cell size 1,776, only 9 of 8,884 cells — 0.1% — below
n=100); the unmatched-row rate roughly doubles (1.32%→2.67%) but remains small. Spec 2's MDE
improves by **18.1%** (0.2469→0.2022). Directly confirmed (not assumed): `spec2$collin.var` is
empty — `WFH_Exposure`'s bare main effect still survives in Spec 2, unaffected by the extra
dimension. **Candidate 1 adopted.**

**What changed:** `main.R`'s `exposure_cell_vars` now includes `BirthContinent` as a 7th element;
`cell_fe_vars`/`other_controls`/the primary DDD formulas are unchanged (`BirthContinent` is not a
regression control or FE dimension, only part of the exposure-cell definition). The `ddd_df` join
already derives its key from `exposure_cell_vars` (a variable, not a hardcoded list, from the
original fix), so no separate join-key edit was needed — confirms that design choice was the right
one. The robustness-chain files (`balance_test.R`, `age_balance_robustness.R`,
`phase2_robustness.R`) already derive their join key dynamically from `exposure_cells`'s own
columns (also from the original fix), so they needed no changes either — confirmed by re-running
`RUN_AGE_BALANCE_ROBUSTNESS` end-to-end against real data.

**Post-change numbers, full pipeline (real data, `Mother:GilNK` included):** Spec 1
`Mother:Post:WFH_Exposure` = −0.0257 (SE 0.0725); Spec 2 = −0.0194 (SE 0.0722). Still well inside
the (now smaller, but still substantial) MDE — this remains an underpowered-not-informative result,
now with somewhat less noise in the exposure measure itself, not a newly-significant finding.

**Options considered and rejected (this update):** a continuous/predicted-occupation regression
(rejected — underperforms the saturated cell design in-sample, per the R² comparison above, and
introduces a small real risk of out-of-range fitted values the cell approach doesn't have); the
children-count variable family (`MisparYeladimAd17MB` etc. — rejected, mechanically adjacent to
the `Mother` indicator itself); `Leom` and `MisparHorimYechidim` (tested, negligible R² gain, not
worth the added cell fragmentation).

## Considered and rejected: cell-level aggregation + WLS

**Proposal.** Aggregate the individual-level DDD sample to cells defined by
`exposure_cell_vars × Mother × Post`, compute each cell's mean `Employed` as the dependent
variable, and refit `Mother*Post*WFH_Exposure + controls` as a weighted least squares (WLS)
regression with weights equal to cell row-count (`n`), on the theory that averaging within cells
would "crush idiosyncratic individual variance" and shrink the SE/MDE further, while keeping
non-employed rows in the sample (unlike occupation-level exposure).

**Why it doesn't work, in theory.** When the right-hand-side variables (`Mother`, `Post`,
`WFH_Exposure`, and all controls) are constant within each aggregation cell — true here by
construction — WLS on cell means weighted by cell size is algebraically identical to the
individual-level regression already being run: same point estimates, and the same standard errors
*if* computed correctly. `main.R`'s existing cluster-robust SEs (clustered at `cell_fe_vars`) exist
specifically to correct for correlated shocks within a cell (the Moulton problem, documented at
`main.R`'s `cell_cluster_formula` comment) — exactly the source of "noise" aggregation would
otherwise appear to crush. A *naive* (unclustered) WLS SE on the aggregated data would look
tighter, but only by silently re-introducing the same problem clustering already fixes — a
spurious, not a genuine, power gain.

**Empirical confirmation (real data, both specs, `n`-weighted WLS, no `MishkalSofi` survey weight
used — applying `MishkalSofi` to an outcome regression needs explicit sign-off per `CLAUDE.md` and
was not given):**

| | Spec 1 SE / MDE (% baseline) | Spec 2 SE / MDE (% baseline) |
|---|---|---|
| Current individual-level (cluster-robust) | 0.0725 / 0.2031 (26.3%) | 0.0722 / 0.2022 (26.1%) |
| Aggregated WLS, naive (unclustered) SE | 0.0749 / 0.2099 (27.1%) | 0.0725 / 0.2033 (26.3%) |
| Aggregated WLS, clustered at `cell_fe_vars` (same level as today) | 0.0726 / 0.2034 (26.3%) | 0.0723 / 0.2024 (26.2%) |

Point estimates matched the individual-level regression to 12 decimal places
(`Mother:Post:WFH_Exposure`: `-0.025732` vs. `-0.025732`, `-0.019363` vs. `-0.019363`), confirming
the algebraic identity. Neither WLS variant improved on the current MDE — the naive version was
even slightly *worse*. Aggregating `exposure_cell_vars × Mother × Post` produced 11,737 cells from
362,779 rows, a **median cell size of 6** (min 1) — cross-classifying the already-fine 7-variable
exposure partition by `Mother` and `Post` leaves almost no individuals per cell to average over, so
there was essentially no aggregation happening in the first place, consistent with the "no free
power" theoretical prediction.

**Decision: rejected.** No wiring into `main.R` — it would add a real aggregation step and a new
WLS spec for a result identical (or fractionally worse) than what's already there.
