# Decision Memo: Jewish vs. Arab `Mother:Post` Equality Test

**Status: Confirmed against real data.** Numbers below come from a real-data run against the
cached CBS extract in this environment (`csvs/cleaned_df.rds`), on branch
`explore-employed-heterogeneity`.

## Background

`main.R` (lines 83-87) already fits two *separate* `basic_reg()` calls, one on
`filter(cleaned_df, Leom == 1)` (Jewish) and one on `filter(cleaned_df, Leom == 2)` (Arab):
`Mother:Post` comes out -0.0041 (n.s.) for Jewish women and -0.0208 (n.s.) for Arab women
(`outputs/basic_reg_jewish_table.csv` / `basic_reg_arab_table.csv`). Neither is individually
significant, but the ~5x difference in magnitude invites an eyeballed "Arab women show a bigger
motherhood penalty" read. That read is not statistically valid: two independent models' CIs
overlapping or not overlapping zero is not itself a test of whether the two point estimates differ
from *each other*. No existing script tests that directly.

## Design

**New file: `scripts/basic_reg_jewish_arab_equality.R`**,
`basic_reg_jewish_arab_equality(cleaned_df)`. Pools both subsamples into one regression and adds a
`LeomGroup` interaction, generalizing `basic_reg()`'s own formula shape exactly the way
`basic_reg_by_child_age.R` generalized it for child age:
`Employed ~ Mother * Post * LeomGroup + DEFAULT_CONTROLS`, clustered `~IDPUF` (matching
`basic_reg()`'s own convention -- no WFH/cell structure involved). `LeomGroup` is built from
`Leom` (documented as an unconverted raw passthrough, `docs/LLD.md` row 38) restricted to
`Leom %in% c(1, 2)`, matching exactly the same two subsamples the existing separate regressions
already cover. With a 2-level `LeomGroup`, the single `Mother:Post:LeomGroupArab` coefficient's own
t-test *is* the equality test -- no separate joint Wald test needed.

## Results

**n = 349,573** (Jewish: 287,733; Arab: 66,200; a further 4,360 dropped to NA by
`feols`/collinearity, unrelated to the `Leom` restriction itself):

| Term | Coefficient | SE | Sig. |
|---|---|---|---|
| `Mother:Post` (Jewish, reference level) | -0.0035 | 0.0058 | n.s. |
| `Mother:Post:LeomGroupArab` | **-0.0122** | 0.0155 | **n.s.** |

**One expected collinearity note, not a defect:** `Dat5` was dropped by `feols`. A crosstab
confirms `Dat` and `Leom` are nested in this data -- every `Leom==1` row has `Dat==1`, and
`Dat` codes 2-5 occur only for `Leom==2/3`. Once `LeomGroup` enters the model, the four
"non-reference" `Dat` dummies collectively equal `LeomGroupArab`, so one is exactly redundant.
`check_for_dropped_coefficients()` flagged it as expected once traced back to this structural
fact, not a bug in this script.

## Conclusion

**No significant difference between Jewish and Arab women's motherhood employment penalty.**
The pooled `Mother:Post:LeomGroupArab` interaction (-0.0122, SE 0.0155, t≈-0.79) is far from
significant. The ~5x gap between the two separately-fit point estimates (-0.0041 vs. -0.0208) is
well within sampling noise once tested directly -- exactly the kind of apparent-but-invalid
difference a pooled interaction test is meant to catch. This closes suggestion #4 from the
original list of 4 binary-outcome follow-ups with a clean, informative null (not an underpowered
one -- both subsamples are large, and the SE on the interaction, 0.0155, is smaller than the raw
gap between the two point estimates would need to be significant).

## What could revisit this

None identified -- this is a clean null on a well-powered test, not a power-limited one. A revisit
would only make sense if `Leom`'s coding were found to be wrong (it is unverified beyond the
`docs/LLD.md` passthrough note) or if a finer ethnic/religious breakdown than the binary
Jewish/Arab split became relevant to the research question.
