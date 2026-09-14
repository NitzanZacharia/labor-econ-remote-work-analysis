# Decision Memo: Outside-the-Box Directions for the Extensive-Margin Null

**Status: Proposal, not yet run.** This documents the brainstorm itself and the theoretical
explanation for the hours-vs-binary significance gap. Results for each of the 4 proposed
directions will be added to this memo (or cross-referenced from their own memos) as they're tried,
on branch `explore-employed-heterogeneity`.

## Background

The pooled extensive-margin DiD (`Employed ~ Mother*Post`) is null; the intensive-margin DiD
(`WorkHoursCont`, conditional on employment) is significant and survives Lee-bounds selection
correction. Suggestions #1-4 from the original binary-outcome exploration list are now complete:
child-age heterogeneity (real, validated, WFH-unlinked -- `docs/decisions/
child-age-employment-heterogeneity.md`), Mother's definition tightening and a pooled event-study on
`Post` (both found redundant with existing work, not run separately), and the Jewish/Arab equality
test (clean null, `docs/decisions/jewish-arab-mother-post-equality.md`). Before concluding the
extensive margin is simply flat, this inventories what has NOT been tried, across the whole
project, not just this session's 4 suggestions.

**Already tried (verified before proposing anything below), so excluded from what follows:**
primary DDD (2 specs) and its age-balance/reweighting comparisons, two-way clustering and
wild-cluster bootstrap, single-parent split *inside* the full WFH triple-interaction
(`run_ddd_by_single_parent()`), child-age split (coarse WFH DDD, and this session's granular
reduced-form + granular WFH versions), furlough correction, gender-placebo DDD, Jewish/Arab split
and equality test, first-stage relevance check, MDE/power audit, exposure-cell granularity fix,
Lee bounds on the intensive margin.

## Proposed directions, ranked by effort-to-payoff

1. **`TeudaGvoha` (education) as a heterogeneity axis via `Mother:TeudaGvoha:Post`, not just an
   additive control.** Direct structural analog of the fix that already worked once on this exact
   dataset (`Mother:GilNK` revealed a masked age-increasing penalty, `docs/decisions/
   age-balance-robustness-chain.md`) -- education level plausibly gates WFH access and job security
   the same way age does. Cheapest to run, most directly motivated by prior evidence.

   **Result (tried, `scripts/basic_reg_by_education.R`, n=364,784):** clean null. Joint Wald test
   on the 5 `Mother:TeudaGvoha:Post` terms: F(5, 79069) = 1.19, **p = 0.311** -- not even marginal
   (contrast with the child-age joint test's p=0.072-0.082). Individual coefficients are small,
   mostly insignificant, and don't trace a monotonic education gradient -- the one marginal term
   (`Mother:Post-secondary, non-academic:Post` = -0.0437, p<0.1) isn't part of any coherent
   pattern across adjacent education levels. Unlike `GilNK`, education does not turn out to mask a
   motherhood-penalty heterogeneity here.

2. **Single motherhood as a plain reduced-form `Post` interaction** (`Employed ~
   SingleParent*Post + controls`, no `WFH_Exposure`), not the underpowered full triple-interaction
   version that already exists. Mirrors the "strip out WFH, test `Post` directly" move that
   surfaced the child-age signal this session.

   **Result (tried, `scripts/basic_reg_by_single_parent.R`, n=364,784):** clean null. Sanity check
   first: single motherhood, by the same unverified `MisparHorimYechidim > 0` convention the
   existing split already uses, comes out to ~11% of mothers (26,332 of 239,095) -- a plausible
   rate, so the assumption isn't obviously wrong even though it's unverified against the CBS
   codebook. Joint Wald test on `SingleMother:Post`/`PartneredMother:Post`: F(2, 79069) = 0.61,
   **p = 0.543**. Neither term is significant individually (`SingleMother:Post` = -0.0006,
   `PartneredMother:Post` = -0.0056) -- no reduced-form single-parenthood heterogeneity either.

3. **A two-part model linking the two margins directly** (Tobit/hurdle, or a joint spec over
   `Employed` and `WorkHoursCont`), testing the specific hypothesis that mothers aren't leaving
   employment but substituting toward fewer hours within it -- which would explain the observed
   null-binary/significant-continuous pattern as a structural feature rather than an unexplained
   contrast.

   **Design note:** a true Tobit/hurdle model needs a censored-regression package this project
   doesn't have (`AER`, `censReg`, `survival::survreg`), and `CLAUDE.md` requires flagging a new
   dependency before adding one. Implemented instead as a dependency-free stand-in
   (`scripts/basic_reg_combined_hours_margin.R`): a combined "hours including zeros" outcome
   (`WorkHoursCont` for employed rows, `0` for non-employed, `NA` preserved where `Employed` itself
   is `NA`), run through the exact same `Mother*Post + controls` DiD via plain `feols`.

   **Result (tried, n=364,781):** `Mother:Post` on the combined outcome = **+0.4791** (SE 0.2459,
   p<0.1, marginal) -- not itself a new signal. It decomposes almost exactly as the mechanical sum
   of the two known margins predicts: the intensive-margin effect (+0.8261\*\*\*,
   `outputs/intensive_margin_table.csv`) times the ~77% employment rate (≈+0.64), plus the
   near-zero extensive-margin effect's contribution (≈-0.16), sums to ≈+0.48 -- matching the
   observed +0.4791 almost exactly. **Confirms the intensive margin alone drives any combined
   movement; the extensive margin contributes essentially nothing**, consistent with (not
   independent evidence beyond) the two margins already estimated separately. One correction to
   the working hypothesis stated above: the *direction* is positive, not negative -- mothers who
   stay employed work MORE hours post-2021, not fewer. So the mechanism is "hours up, participation
   flat," not "hours down to avoid exit" -- the "adjustment happens on the cheap margin" story
   still holds, just with the opposite sign from what was guessed going in.

4. **Occupational mobility as the treatment variable**, not employment status -- change in an
   individual's own occupation-exposure score pre/post among those who stay employed. A genuinely
   new outcome construction (no existing script builds it); reframes "extensive margin" as
   job-switching rather than labor-force exit, the one place a null exit result and a real WFH
   story aren't in tension.

   **Design note:** as originally framed (individual-level pre/post change) this isn't viable --
   `docs/decisions/panel-fe-rejected.md` already confirms only 1.88% of individuals (1,514 IDPUFs)
   straddle the `Post` boundary, far too few for within-person tracking. Reformulated as a
   repeated-cross-section DiD instead (`scripts/basic_reg_own_occ_exposure.R`): on the
   `Employed==1` subsample, `OwnOccExposure ~ Mother*Post + controls`, where `OwnOccExposure` is
   each respondent's own occupation's calibrated exposure score (`wfh_exposure_calibrated` from
   `calibrate_isco_exposure()`), joined by her actual `MishlachYad_ISCO_08_2` occupation code --
   NOT the demographic-cell shift-share `WFH_Exposure` used elsewhere, which describes her
   demographic cell rather than her actual job.

   **Result (tried, n=275,710; 6,778 of 288,400 employed rows unmatched to a calibrated occupation
   score, same 2-of-40-occupations-at-theoretical-value note as elsewhere):** clean null.
   `Mother:Post` = **0.0006** (SE 0.0034, n.s.). Employed mothers show no differential sorting into
   more- or less-WFH-exposed occupations post-2021 relative to employed non-mothers.

## Synthesis -- all 4 directions tried

All four come back null or mechanically-explained-by-existing-results: education heterogeneity
(F(5,79069)=1.19, p=0.311), single-parenthood heterogeneity (F(2,79069)=0.61, p=0.543), the
combined hours-including-zeros margin (marginal but fully explained by the known intensive-margin
effect, no independent signal), and occupational sorting (0.0006, n.s.). As anticipated when this
memo was proposed: **this meaningfully strengthens the case that the extensive margin is genuinely
flat, not merely under-explored** -- four structurally distinct, legitimate, previously-untried
angles (a masked-heterogeneity check that already worked once elsewhere in this project, a
high-need subgroup restriction, a linked-margins test, and a treatment-variable reframing) all
failed to surface anything. Combined with the child-age finding (`docs/decisions/
child-age-employment-heterogeneity.md`, the one real, validated heterogeneity result in this whole
family of checks) and the Jewish/Arab equality null (`docs/decisions/
jewish-arab-mother-post-equality.md`), the honest overall picture is: the post-2021 employment
adjustment for mothers happens almost entirely on the intensive margin (hours, positive and
significant, `outputs/intensive_margin_table.csv`), the one real extensive-margin heterogeneity is
by youngest-child age and is not WFH-linked, and every other dimension checked here (education,
single-parenthood, ethnicity/religion, occupational sorting) shows no differential extensive-margin
effect at all.

## Why hours and binary diverge -- explanation

**Behavioral.** Israel's furlough regime (Halat Oved, `docs/decisions/
furlough-employed-contamination.md`) exists specifically to preserve the formal employment
relationship through a disruption rather than end it -- exit carries real costs (job search, lost
seniority/benefits, scarring) an hours cut inside an existing job doesn't. Standard labor-supply
prediction: adjustment happens first, and often only, on the cheaper margin (hours) before it
reaches the expensive one (participation). WFH lowering the marginal cost of an hour worked, not
the fixed cost of holding a job at all, predicts exactly this asymmetry.

**Statistical.** The MDE audit (`docs/decisions/null-vs-power-audit.md`) already showed the
extensive-margin DDD needs an implausibly large effect (~40pp) to be detectable given
`WFH_Exposure`'s cell-level coarseness and ~209 clusters. A continuous outcome
(`WorkHoursCont`) carries strictly more information per observation than a 0/1 collapse of the same
underlying behavior, so part of the divergence is a power artifact stacked on top of the real
behavioral asymmetry above, not purely behavioral on its own.

Both explanations point the same direction and aren't mutually exclusive -- worth stating together
in any writeup rather than picking one.

## What could revisit this

Each proposed direction above either confirms/extends the behavioral story (1, 2, 3) or tests
whether the null is a treatment-variable framing artifact rather than a real flat effect (4). If
all 4 come back null, that would meaningfully strengthen the case that the extensive margin is
genuinely unaffected and the entire adjustment happens on hours -- worth stating explicitly once
(if) that point is reached.
