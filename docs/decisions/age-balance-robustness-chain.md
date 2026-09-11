# Decision Memo: Age-Balance Robustness Chain (Phase 1b/1c/2)

**Status: PARTIALLY DECIDED.** The balance-test/age-imbalance diagnostic chain (`robustness/balance_test.R`, `robustness/age_balance_robustness.R`, `robustness/pretrend_wald_test.R`) is verified against real data and wired into `main.R` behind an opt-in flag. Whether either comparison spec it produces (age-interacted or `GilNK`-reweighted) should *replace* `main.R`'s primary DDD is **not decided** — see "Open question" below. `robustness/phase2_robustness.R` is **not** wired in at all — see "Not wired in."

## Background

Commit `21b30b2` ("Add pre-trend/balance robustness chain and gender-placebo DDD extension") added four new robustness files (`robustness/balance_test.R`, `age_balance_robustness.R`, `phase2_robustness.R`, `pretrend_wald_test.R`) plus a DDD extension to `gender_placebo.R`, each with test coverage, but with no corresponding `docs/ROADMAP.md` entry, HLD/LLD update, or decision memo — and, more importantly, no orchestrator ever called any of it against real data. `age_balance_robustness.R`'s own header comment asserted, as an already-established finding, that "`GilNK` (age group) is imbalanced between `Mother==1` and `Mother==0` in the pre-period, concentrated in the lowest `WFH_Exposure` quartile." A 2026-09-09 audit flagged this as **narrative, not evidence**: the claim had only ever been exercised against synthetic unit-test fixtures, never the real CBS extract.

## What was verified (2026-09-09, against the real CBS extract)

Ran `diagnose_gilnk_by_quartile()` and `run_balance_test()` against the real, locally-available CBS data (`load_and_clean_data()` on the actual `folder_path`, not a fixture), using `exposure_cells` built from the broadened population frame (`exposure_population_df` — see `docs/decisions/calibrated-exposure-and-cell-ddd.md`'s addendum). Output was printed to console only; nothing derived from this run was committed, per `CLAUDE.md`'s disclosure-risk rule (aggregate counts only, no row-level output persisted).

**`GilNK` (age-group) gap, Mother==1 minus Mother==0, pre-period (2017-2019), by `WFH_Exposure` quartile** (n = 201,388 pre-period rows with a matched exposure cell):

| Quartile | mean GilNK, Mother=0 | mean GilNK, Mother=1 | gap (Mother1 − Mother0) | t-stat | p-value |
|---|---|---|---|---|---|
| Q1 (lowest exposure) | 6.02 | 5.22 | **−0.797** | −80.9 | ~0 |
| Q2 | 5.74 | 5.03 | −0.714 | −64.3 | ~0 |
| Q3 | 5.15 | 4.81 | −0.346 | −24.8 | 3.6e-134 |
| Q4 (highest exposure) | 4.49 | 4.73 | **+0.239** | +21.2 | 5.4e-99 |

**The claim is confirmed, not just statistically significant by virtue of a large n.** The gap is not only significant everywhere (unsurprising with n in the tens of thousands per cell) but *monotonically shrinks in magnitude from Q1 to Q3 and reverses sign at Q4* — exactly the pattern the header comment described ("concentrated in the lowest quartile"), and roughly 0.8 `GilNK` units at Q1 is a substantively meaningful age gap (`GilNK` bands span ages 25-59 in 5 groups), not a rounding artifact. `run_balance_test()`'s categorical-control chi-square tests (`MatzavMishpachti`, `Dat`, `MachozMegurim`, `TeudaGvoha`) are also all significant at every quartile (p ≈ 0 throughout) — expected given the sample size, and consistent with `GilNK` not being the only pre-period imbalance, though it's the one this chain specifically investigates because it's a `DEFAULT_CONTROLS` term whose imbalance *varies systematically with the DDD's own exposure regressor* (the other controls' imbalance isn't shown here to vary the same way with quartile, though this memo doesn't formally test that).

**Why this matters for identification:** `GilNK` enters the primary DDD only additively (as a `DEFAULT_CONTROLS` term, or absorbed into Spec 2's cell FE). An additive control cannot correct for an imbalance whose *size* varies with the regressor of interest (`WFH_Exposure` quartile) the way this one does — if age also predicts `Employed` differently across quartiles (plausible, since age effects on employment are rarely linear or quartile-invariant), this is a live confound risk for `Mother:Post:WFH_Exposure`, not a settled non-issue.

## What was wired into `main.R`

Behind `RUN_AGE_BALANCE_ROBUSTNESS` (default `FALSE`, so no behavior changes for existing runs unless explicitly enabled):
- `run_balance_test()` — full covariate-balance table.
- `diagnose_gilnk_by_quartile()` — the table above.
- `run_ddd_age_interacted()` — `main.R`'s primary DDD formulas + `Mother:GilNK`.
- `run_ddd_reweighted()` — primary DDD formulas, pre-period `GilNK`-raking weights applied via `weights = ~rake_weight`.
- `run_pretrend_joint_test(diagnostics_results$pretrend_model)` — joint Wald test on the existing pre-trend event-study coefficients (console-only, not exported — see below).

Exported (when the flag is on) as `age_balance_robustness` in `outputs/`, aggregate-only: `balance_test` (the 4 non-row-level pieces of `run_balance_test()`'s return), `age_imbalance_by_quartile`, `ddd_age_interacted`, `ddd_reweighted`. The row-level `pre_df` frames both `run_balance_test()` and `diagnose_gilnk_by_quartile()` return are deliberately excluded from export, same disclosure-risk logic `main.R` already applies to `idpuf_panel_check`.

## Not wired in: `robustness/phase2_robustness.R`

This file layers three further checks on top of the reweighted spec (`run_ddd_twoway_cluster()`, `run_ddd_education_checks()`, `run_ddd_weights_check()`). It is **not** sourced by `main.R` and not part of `RUN_AGE_BALANCE_ROBUSTNESS`, for one specific reason: `run_ddd_weights_check()` (line 150 of that file) fits `feols(..., weights = ~MishkalSofi, ...)` and `feols(..., weights = ~combined_weight, ...)` where `combined_weight = rake_weight * MishkalSofi` — i.e., it applies the CBS survey design weight as a regression weight. `CLAUDE.md` is explicit: *"CBS survey weights ... are intentionally NOT applied in any outcome regression ... Do not add `weights =` to a `feols()`/`lm()` call in this repo without raising it with the user first."* That sign-off was never obtained before this file was committed. The function's own stated purpose — confirming `MishkalSofi` isn't applied elsewhere, then checking whether it *would* materially change the reweighted spec if it were — is a defensible sensitivity-check design, and the file itself never claims otherwise. But per the rule's plain text, that decision belongs to the user, not to whoever wrote the check. `run_ddd_twoway_cluster()` and `run_ddd_education_checks()` also use `weights = ~rake_weight` (the local raking weight, not a survey weight) — a narrower case, arguably already implicitly sanctioned by `run_ddd_reweighted()` being wired in, but left out of `main.R` for now since they're built on `prepare_reweighted_ddd_df()`'s specific reweighted baseline, which is itself part of the still-open question below.

**Action needed from the user:** decide whether `run_ddd_weights_check()` may be run at all (even as a one-off sensitivity check never used for a headline result), and if so, whether `phase2_robustness.R` as a whole should be wired into `main.R` the same way this memo wires in `balance_test.R`/`age_balance_robustness.R`/`pretrend_wald_test.R`.

## Update (2026-09-11): `Mother:GilNK` added to the primary spec; full reweighting still open

Before deciding whether to promote a comparison spec wholesale, `run_ddd_age_interacted()` and `run_ddd_reweighted()` were run against the real data to see whether the confirmed `GilNK` imbalance actually changes the paper's headline conclusion. It doesn't: `Mother:Post:WFH_Exposure` stays statistically insignificant and similar in magnitude across the primary (0.107 additive / 0.136 cell-FE), age-interacted (0.103 / 0.131), and reweighted (0.029 / 0.074) specs — the reweighted spec if anything shrinks the point estimate further toward zero. **The imbalance does not rescue or overturn the WFH-mechanism result either way.**

It does, however, surface a separate, real finding: adding `Mother:GilNK` reveals a significant, age-increasing motherhood employment penalty that the primary spec's purely-additive `GilNK` control was masking (cell-FE spec: base `Mother` effect goes from an insignificant −0.001 to a significant −0.077***, with `Mother:GilNK5/6/7` themselves significant and increasing, 0.033 → 0.039 → 0.033). This is unrelated to WFH exposure, but it's a legitimate reason on its own to include the interaction.

**Decision: `Mother:GilNK` is added to `main.R`'s primary DDD** (both specs), on top of the full `Mother*Post*WFH_Exposure` interaction and `DEFAULT_CONTROLS`, using the same corrected cell-level clustering as the rest of the primary spec. In Spec 2, `GilNK`'s own main effect stays absorbed into the cell FE as before; `Mother:GilNK` is not collinear with that FE (the FE groups by the joint `GilNK^TeudaGvoha^MachozMegurim` cell, not by an individual's own `Mother` status within it) and is confirmed to survive in both specs.

**Not decided by this update**: whether to also promote the full reweighted spec (pre-period `GilNK`-raking weights) to primary. That remains the open question this memo originally posed — `run_ddd_reweighted()` stays a comparison spec, surfaced only when `RUN_AGE_BALANCE_ROBUSTNESS` is on.

**A separate, unresolved inconsistency this update surfaced**: `run_ddd_age_interacted()`/`run_ddd_reweighted()` (this file) still cluster at `~IDPUF`, not the cell level — they predate the C2 audit fix and were never updated to match it, unlike `main.R`'s own primary spec. The comparison numbers above therefore understate their true SEs relative to the (now Mother:GilNK-augmented) primary spec's corrected clustering. Worth fixing for consistency in a future pass, but doesn't change the conclusion above (the point estimates, not just the SEs, already stay small and similar across specs).
