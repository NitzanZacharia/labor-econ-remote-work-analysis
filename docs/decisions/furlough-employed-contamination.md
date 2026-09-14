# Decision Memo: Furlough (Halat) Contamination of `Employed`, Corrected via `Employed_strict`

**Status: Confirmed against real data and the real CBS codebook** (`H20231031Codebook.xlsx`).

## Background

Devil's-advocate review of the extensive-margin design asked whether `Employed`
(`if_else(!is.na(Muasak) & Muasak == 1, 1L, 0L)`) conflates genuinely-working people with people on
Israel's Halat (חל"ת) furlough program — temporary, often state-subsidized leave where the worker
stays formally attached to an employer. Standard ILO/LFS convention codes such a worker as
"employed, temporarily absent," which is exactly what `Muasak` (CBS's own collapsed employed/
not-employed variable) does — indistinguishable from someone actually working.

This project's own research-design doc (`docs/motherhood_penalty_wfh_research.md:96`) originally
specified employment via "worked last week" (`AvadBeshavua`), not `Muasak` — the implemented
definition is an undocumented deviation from that spec.

## The real numbers

The raw column `SibaNeedar` ("reason for absence from work last week," asked whenever a `Muasak==1`
person reports `AvadBeshavua==4`) has value **9 = "צמצום בהיקף העבודה / הפסקה זמנית עד 30 יום"**
("reduction in work scope / temporary suspension up to 30 days") per the actual CBS codebook — the
CBS's own operational definition of Halat. Among `Muasak==1` rows in `cleaned_df` (women 25-59):

| Year | n employed | SibaNeedar==9 (furloughed) | rate |
|---|---|---|---|
| 2017 | 52,898 | 60 | 0.11% |
| 2018 | 50,861 | 128 | 0.25% |
| 2019 | 50,230 | 146 | 0.29% |
| **2021** | 45,780 | **1,496** | **3.27%** |
| 2022 | 44,480 | 133 | 0.30% |
| **2023** | 44,151 | **528** | **1.20%** |

A stable ~0.1-0.3% pre-period baseline, a ~11-30x spike in 2021, a near-baseline 2022, and a ~4x
re-elevation in 2023. `check_furlough_incidence()`'s consistency check confirms `SibaNeedar` is
populated if and only if `AvadBeshavua==4` (100.0% of 30,452 populated rows, real data, no
exceptions).

**Mechanism check** — furlough rate by `Post x Mother x WFH_Exposure` quartile (real data):

| Post | Mother | Q1 | Q2 | Q3 | Q4 |
|---|---|---|---|---|---|
| 0 | 0 | 0.23% | 0.19% | 0.25% | 0.21% |
| 0 | 1 | 0.23% | 0.24% | 0.19% | 0.22% |
| 1 | 0 | 1.82% | 1.74% | 1.93% | 1.15% |
| 1 | 1 | 1.81% | 1.84% | 1.52% | 1.28% |

Two findings: (1) pre-period rates are flat and low across every cell — the contamination is
genuinely `Post`-specific, not a pre-existing pattern; (2) in `Post==1`, furlough rate declines from
Q1 to Q4 for **both** Mother groups (roughly -0.5 to -0.7pp from Q1 to Q4), confirming the
exposure-gradient mechanism (low-teleworkability jobs furloughed more) — but the Mother-vs-non-Mother
gap *within* a given quartile is small and inconsistent in sign (Q1: ~equal, Q2: mothers higher,
Q3: mothers lower, Q4: mothers higher). The contamination loads primarily onto the `Post x
WFH_Exposure` margin, not distinctly onto a `Mother`-specific channel.

## The corrected-outcome comparison

`run_basic_reg_furlough_corrected()` (simple 2x2 DiD): `Mother:Post` barely moves
(-0.0053 → -0.0056, both null) — consistent with the mechanism check above (furlough isn't
differentially a Mother phenomenon). `Post`'s own main effect drops sharply (0.0153\*\*\* → 0.0043,
n.s.) — the furlough-inflated employment "increase" in the raw `Post` coefficient is real and gets
removed by the correction, exactly as expected.

`run_primary_ddd_furlough_corrected()` (primary DDD, both specs):

| Term | Spec 1 original | Spec 1 corrected | Spec 2 original | Spec 2 corrected |
|---|---|---|---|---|
| Mother:Post:WFH_Exposure | -0.0257 (0.0725) | -0.0150 (0.0715) | -0.0194 (0.0722) | -0.0079 (0.0710) |
| Post:WFH_Exposure | -0.1555\*\* | -0.1610\*\* | -0.1516\*\* | -0.1577\*\* |
| Mother:WFH_Exposure | -0.1404. | -0.1306 | -0.0818 | -0.0717 |

The triple interaction moves *closer* to zero after correction, not away from it, in both specs.
`Post:WFH_Exposure` stays significant and gets slightly *more* negative/precise.

## Decision

**The furlough-conflation theory is real and now corrected for** (`Furloughed`/`Employed_strict` in
`data_processing.R`, run as a standing comparison spec under `RUN_FURLOUGH_CORRECTION` in `main.R`)
— this was a genuine measurement gap, independent of whether it rescues the headline null, and
`SibaNeedar` staying dropped from the pipeline (via the "Needar" prefix sweep) was collateral
damage from an undifferentiated drop rule, not a considered choice.

**It does not rescue the null `Mother:Post:WFH_Exposure` result.** The mechanism check explains why:
furlough concentrates by `WFH_Exposure` quartile as hypothesized, but not differentially by `Mother`
within quartile — so the correction mainly cleans up the `Post` level effect and sharpens
`Post:WFH_Exposure`, without changing the Mother-specific triple-interaction conclusion. This is a
confirmed, informative null on this specific avenue, not a dead end for the correction itself
(`Employed_strict` is the more defensible outcome variable going forward regardless).

## What could revisit this

If a future refinement finds a channel where furlough incidence *does* differ by Mother status
conditional on exposure (e.g. within specific occupation families, or interacted with child age —
not tested here), the correction is already in place to rerun against. The occupation-level
robustness DDDs (calibrated/external/realized) were not rerun with `Employed_strict` in this pass —
a natural, cheap follow-up given the infrastructure already exists.
