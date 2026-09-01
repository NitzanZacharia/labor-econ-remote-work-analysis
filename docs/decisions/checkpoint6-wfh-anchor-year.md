# Decision Memo: WFH-Exposure Index Anchor Year (Checkpoint 6)

**Status: DECIDED — Path B (2021 as the exposure-anchor year).** See "Decision" at the bottom.

## The problem

`motherhood_penalty_wfh_research.md` Part 4 §4 specifies the WFH-Exposure Index's construction explicitly:

> This index will be constructed using the **2020** CBS work-from-home variable to measure actual "WFH Exposure" (e.g., comparing tech workers whose WFH share jumped from 10% to 50% against cleaning workers with a 0% change).

But this project's sample **excludes 2020 entirely** — `data_processing.R`'s filter (`ShnatSeker %in% c(2017,2018,2019,2021,2022,2023)`) treats 2020 as a "transitional year," and confirmed directly against the data folder: **there is no `2020_Data.csv` in `G:/My Drive/Uni/econ/csv_data/` at all.** This isn't a filtering choice that can be reversed in code — the raw 2020 extract was never acquired. `cleaned_df` structurally cannot contain a 2020 WFH measurement, so the index as literally specified cannot be built from the data this pipeline already has.

## Path A — Acquire a separate 2020-only CBS extract

Pull a new raw CBS Labor Force Survey extract for 2020 specifically (outside this project's existing 6-year extract), used only to build the WFH-Exposure Index — not merged into the main DiD sample.

**Pros**
- Matches the research doc's Part 4 §4 specification exactly, as written.
- 2020 is the year of the actual pandemic-driven shock. An exposure measure taken *at the moment occupations were forced to adapt* plausibly captures each occupation's latent/inherent WFH-ability more cleanly than a later year, where practices may have already settled into a new (possibly different) equilibrium — some occupations institutionalizing WFH permanently, others reverting to in-person.

**Cons**
- Requires acquiring genuinely new raw data — this is a data-sourcing/logistics task (CBS access, download, initial inspection), not something resolvable in code.
- Checkpoint 2's schema-drift check already found that 2017's raw schema differs from 2018–2023's (4 missing columns). A never-before-touched 2020 extract could plausibly have its own schema quirks that `check_schema_drift()` would need to validate against — more surface area, not less.
- Creates a second raw-data dependency (a single extra year, used nowhere else in the pipeline) with its own path, caching, and validation needs, parallel to but separate from the main 6-year extract.

## Path B — Formally adopt 2021 as the exposure-anchor year

Use the already-present, already-validated 2021 data (part of the existing 6-year extract) as the WFH-exposure anchor instead of 2020, and document this substitution explicitly wherever the research doc's methodology is written up.

**Pros**
- No new data acquisition — 2021 already flows through the full validated pipeline (schema-drift check, `load_and_clean_data()`, `validate_cleaned_df()`) today. Immediately actionable.
- 2021 is arguably a *more stable* measurement point than 2020: this project's own rationale for excluding 2020 from the main DiD sample (a chaotic, non-representative "transitional year") arguably applies with equal force to using it as an exposure anchor — a WFH measure taken during 2020's emergency/ad-hoc disruption might reflect improvisation rather than each occupation's settled remote-work potential.

**Cons**
- This is a genuine, documented deviation from the research doc's literal specification, not a mechanical substitution — it should be disclosed and justified in the paper's methods section, not silently swapped in.
- Conceptually measures a different quantity than what Part 4 §4 describes: by 2021, occupations had already had a year to adapt their WFH practices in response to the 2020 shock. If adaptation was uneven across occupations (some reverting to in-person, others institutionalizing WFH), a 2021-based index could rank occupations' "exposure" meaningfully differently than a 2020-based one would have.

## Decision

**Path B: 2021 is the WFH-exposure anchor year**, not 2020 as `motherhood_penalty_wfh_research.md` Part 4 §4 literally specifies. `build_wfh_exposure_index()` will default `ref_year = 2021`.

This is a documented deviation from the written research doc, not a mechanical substitution — the "Cons" of Path B above (a real deviation from spec; conceptually measures post-adaptation WFH adoption rather than the occupation's WFH-ability at the moment of the initial 2020 shock) should be carried into the paper's methods section if/when this index's results are written up.
