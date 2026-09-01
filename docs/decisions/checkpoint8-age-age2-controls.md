# Decision Memo: Age/Age² Controls (Checkpoint 8)

**Status: DECIDED — Path B (formally specify `GilNK`, not continuous age/age²).** See "Decision" at the bottom.

## The problem

`motherhood_penalty_wfh_research.md` Part 4 §2 specifies the control set explicitly:

> **Control Variables (X'ᵢₜ):** Years of education, **age, age²**, marital status, religion/level of religiosity, and district of residence.

But **no continuous age or birth-year variable exists anywhere in the raw CBS extract this project has** — confirmed directly by grepping every year's CSV header for age- and birth-year-related columns (documented in `docs/LLD.md`'s Gap Analysis). What exists is:
- `GilNK` — a categorical age-*group* code (5 bins spanning ages 25–59), already used as a regression control in every model built so far (`basic_reg()`, `basic_reg_comp()`, `employment_by_child_age()`, `Diagnostics.R`'s event study, and Checkpoint 7's DDD model).
- `GilYeledTzairMBNK`, `GilYeledTzairHoreYachidMB`, `GilAliya`, `GilYeledTzairPratNK` — all *child*-age or immigration-year codes, not personal age.
- No `ShnatLeda` (birth year) or equivalent column that could back-calculate continuous age.

Separately, `motherhood_penalty_wfh_research.md` Part 3 §3 (the advisor's actual hands-on feedback, given after Part 4 §2 was drafted) says:

> **Dummy Variables Generation:** Create standard dummy variables for: Religion, Education (Certificate/Degree type), District of Residence.

This is a categorical-controls instruction, consistent with how `GilNK` (and every other control) is actually implemented today, but it doesn't explicitly mention age — leaving Part 4 §2's continuous age/age² spec technically un-superseded even though the project's real, running implementation has never used it.

## Path A — Request a wider CBS data extract with continuous age or birth year

Acquire additional raw data from CBS containing continuous age or birth year, merge it into the existing pipeline, and switch every model's age control from `GilNK` to `age + age²`.

**Pros**
- Matches Part 4 §2's specification exactly, as written.
- A continuous quadratic age term is a more flexible functional form than 5 coarse bins — it can capture a smooth age-employment gradient that `GilNK`'s bins might mask or arbitrarily bin.

**Cons**
- Requires new data acquisition — a data-sourcing/logistics task, not something resolvable in code, same category of blocker as Checkpoint 6's anchor-year question.
- Exact age is often treated as more sensitive/re-identifying than the data already provided, which may affect what CBS is willing to release or under what terms — worth weighing alongside the disclosure-risk note already flagged for Checkpoint 9.
- Would require re-running Checkpoints 1–2 (validation, schema-drift) against the new extract before using it, and touching every regression function that currently references `GilNK` (five files: `basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R`, `Diagnostics.R`, `ddd_regression.R`, plus `DEFAULT_CONTROLS` itself).
- Doesn't resolve the deeper tension with Part 3 §3: even if continuous age became available, the advisor's own more recent, hands-on feedback called for categorical dummies, not continuous controls — so acquiring the data wouldn't by itself settle which specification to actually use.

## Path B — Formally amend Part 4 §2 to specify `GilNK`

Edit `motherhood_penalty_wfh_research.md` Part 4 §2 to list the categorical `GilNK` age-group control in place of continuous age/age², matching what every model already implements.

**Pros**
- No new data needed. The entire existing control set (`MatzavMishpachti`, `Dat`, `GilNK`, `MachozMegurim`, `TeudaGvoha`, all sourced from the single `DEFAULT_CONTROLS` constant since Checkpoint 3) is already internally consistent under this choice — this just makes the written spec match what has actually been running successfully across Checkpoints 0 through 7.
- Directly resolves the standing inconsistency between Part 3 §3 (categorical dummies) and Part 4 §2 (continuous age) noted as far back as this project's original HLD document, rather than continuing to defer it.

**Cons**
- This is a real modeling trade-off, not just documentation cleanup: `GilNK`'s 5 coarse bins are a less flexible functional form than continuous age + age², and could obscure a genuinely non-linear age-employment relationship a quadratic specification would reveal. The researchers should weigh this as a substantive methodological choice, not a formality.

## Decision

**Path B: `GilNK` (the categorical age-group control already used everywhere) formally replaces continuous age/age² in the project's specification.** `motherhood_penalty_wfh_research.md` Part 4 §2 has been edited accordingly.

This is a real methodological choice, not just documentation cleanup — the "Cons" of Path B above (5 coarse age bins are a less flexible functional form than a continuous quadratic, and could mask a genuinely non-linear age-employment relationship) should be kept in mind if this project's results are ever compared against literature using continuous age controls.
