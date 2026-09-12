# Decision Memo: Individual-Panel Fixed Effects, Rejected on the Real Cross-Period Count

**Status: VERIFIED AGAINST REAL DATA, NOT YET COMMITTED.** Per `CLAUDE.md`'s disclosure-risk rule,
the aggregate count below (not row-level data) came from a one-off local run of `Rscript main.R`
against the real cached CBS extract, reviewed with the user before being written up here.

## Background

As a follow-up to `docs/decisions/exposure-cell-granularity-fix.md`'s power fixes for the primary
DDD (see also the exposure-family Wald test and cross-measure synthesis wired in under
`RUN_EXPOSURE_POWER_DIAGNOSTICS`), an individual-level fixed-effects design was considered: if the
same `IDPUF` appears in both the `Post==0` (2017-2019) and `Post==1` (2021-2023) samples, a
within-person FE regression on `Post`/`Mother:Post`/`Post:WFH_Exposure`/`Mother:Post:WFH_Exposure`
would remove all between-person variance — the dominant noise source in the current cross-sectional
extensive-margin model — potentially at a much better bias-variance tradeoff than aggregating cells
or reweighting.

This depends entirely on how many individuals actually straddle the `Post` boundary.
`scripts/validation.R`'s `check_idpuf_panel_structure()` already computes exactly this
(`cross_period_n`), called unconditionally in `main.R` right after `validate_cleaned_df()`, but its
output had never been read from a real run — it's message-only, deliberately excluded from
`outputs/` per this project's disclosure-risk convention for individual-level tables (row-level
`idpuf_years`/`idpuf_periods` are per-person; only the aggregate counts are ever surfaced).

## The real number

A real-data run of `Rscript main.R` printed:

```
check_idpuf_panel_structure: 80560 distinct IDPUF in cleaned_df.
  36438 (45.23%) appear in more than one ShnatSeker year.
  1514 (1.88%) appear in BOTH Post==0 (2017-2019) and Post==1 (2021-2023) rows -- the same
  individual contributing to both sides of the Mother/Post design.
```

`multi_year_n` (45.23%) is large — confirming this repo's own existing comment
(`scripts/wfh_exposure_cells.R`'s note that a single `IDPUF` can carry 4 rows within *one year*
alone) that CBS's LFS rotating panel mostly re-interviews the same person multiple times *within* a
single year's rotation group, not across the multi-year 2019→2021 boundary. `cross_period_n`
(1.88%, 1,514 individuals) is the number that actually matters for a within-person FE on `Post`, and
it is small both in absolute terms and, more importantly, as a share of `n_idpuf`.

## Why 1,514 is not enough

A within-person FE design on `Post` only uses the ~1,514 cross-period individuals — everyone else
contributes zero identifying variation to `Post`, `Mother:Post`, `Post:WFH_Exposure`, or
`Mother:Post:WFH_Exposure` once individual FE are added (their between-person variation, which the
current cross-sectional design uses, is exactly what individual FE partials out). Within that
1,514, the design further needs:

- enough of them to be mothers (`Mother==1`) for `Mother:Post` and `Mother:Post:WFH_Exposure` to be
  identified at all — a further multiplicative cut of an already-small group, and
- enough spread in `WFH_Exposure` among the cross-period mothers specifically, since `WFH_Exposure`
  is built from demographic-cell variables (`GilNK`, `TeudaGvoha`, `MachozMegurim`,
  `MatzavMishpachti`, `Dat`, `BirthContinent`, `Min`) that are mostly time-invariant per person —
  i.e. even among the 1,514, `WFH_Exposure`'s own within-person variation over time is limited by
  construction, the same aliasing concern (regressor built from largely-fixed demographics) that
  motivated `exposure-cell-granularity-fix.md` in the first place.

Compared to the primary DDD's current estimation sample (355,984 rows, ~210 clusters), a design
that can draw on at most 1,514 individuals — before the further within-mother, within-exposure-
variation cuts above — is not plausibly going to out-perform it on precision. Unlike the earlier
cell-level-WLS proposal (`exposure-cell-granularity-fix.md`'s "Considered and rejected: cell-level
aggregation + WLS" section, rejected because it was algebraically *identical* to the current design
with no power gain), this one is rejected because it would be a **large loss of information**
relative to the current design — the panel-FE sample is 0.4% the size of the current DDD's
estimation sample, and the source of "extra" precision individual FE normally buys (removing
between-person noise) is exactly the variation this design already relies on almost entirely.

## Decision

**Rejected — not built.** No `scripts/ddd_panel_fe_regression.R` was written and no new flag was
added to `main.R`. `check_idpuf_panel_structure()` itself is unchanged and continues to run
unconditionally in `main.R` (it existed, and was useful, before this exploration and remains so for
future panel-related questions) — only the panel-FE *regression* built on top of it was considered
and rejected here.

## What could revisit this

If a future CBS extract is pulled with denser panel retention across the treatment boundary (e.g. a
purpose-built longitudinal file rather than the rotating cross-sectional LFS releases used here), or
if the sample window is extended far enough that `cross_period_n` grows substantially, this decision
should be revisited — the underlying logic (within-person FE removes between-person noise) is sound
in general; it's specifically this dataset's rotation structure that makes it non-viable now.
