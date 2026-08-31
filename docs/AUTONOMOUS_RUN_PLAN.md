# Autonomous Run Plan — Claude Code CLI × `labor-econ-remote-work-analysis`

**Goal:** drive Claude Code (CLI) through `docs/ROADMAP.md`'s 10 checkpoints to close the gap between
the current pipeline and the full empirical strategy in `motherhood_penalty_wfh_research.md`, while
interleaving the test suite specified in `TESTING_BLUEPRINT.md`.

**Read this first — the honest constraint:** the Roadmap itself bakes in three points where a human,
not the agent, has to decide something (Checkpoints 5, 6, 8), and almost every Roadmap "Verification
Step" is `Rscript main.R` against your real CBS microdata at a hardcoded local path. That means this
can't responsibly run as a single unattended `cron`/`dontAsk` job from Checkpoint 1 to 10. What it
*can* do is run each checkpoint's implementation and fixture-based testing autonomously, and pause
cleanly at defined gates for you to run the real-data step and/or make the call. That's the model this
plan uses throughout: **Lane A** (agent can do this alone, no real data needed) vs. **Lane B** (needs
your real data / your judgment).

---

## Quick Start — running this with Claude Code CLI

**0. Confirm Claude Code is installed and you're in the repo.**

```bash
claude --version
cd /path/to/labor-econ-remote-work-analysis
```

Not installed? macOS/Linux/WSL: `curl -fsSL https://claude.ai/install.sh | bash`. Windows
PowerShell: `irm https://claude.ai/install.ps1 | iex`.

**1. Do the one-time setup interactively, not headless.** Start a normal session (`claude`, no `-p`)
and say:

```
Read AUTONOMOUS_RUN_PLAN.md in full. Do the two fixes in its Section 0, then create the CLAUDE.md
and .claude/settings.json files exactly as specified in its Section 1.
```

Review the diff it proposes, approve, let it commit.

**2. Kick off Checkpoint 0 the same way** — low-risk, but worth watching once:

```
Implement Checkpoint 0 from AUTONOMOUS_RUN_PLAN.md. Follow the loop in Section 2. Stop and report
if run_tests.R doesn't pass — don't force it green by weakening a test.
```

**3. From Checkpoint 1 onward, this is the one prompt you reuse, checkpoint by checkpoint:**

```
Implement Checkpoint <N> from AUTONOMOUS_RUN_PLAN.md, following the loop in Section 2 and the Lane
A/Lane B split for that checkpoint. If you hit a ⛔ human gate, stop there, tell me exactly what you
need from me, and don't proceed past it.
```

That one sentence works every time because the plan file carries all the checkpoint-specific detail —
you're pointing at it, not retyping the Roadmap.

**4. Checkpoints with no gate and no shared-file risk (0, 1, 2, most of 9) are fine to run headless
once you trust the pattern:**

```bash
claude -p "Implement Checkpoint 2 from AUTONOMOUS_RUN_PLAN.md, Lane A only. Report pass/fail." \
  --allowedTools "Read,Write,Edit,Bash(Rscript run_tests.R),Bash(git *)" \
  --permission-mode acceptEdits
```

A plain interactive `claude` session now auto-approves most routine edits itself via a background
classifier (Auto mode is the default starting mode for interactive sessions on Pro/Max/Team plans),
so you may not need `--permission-mode` at all when working interactively. Headless (`-p`) sessions
still default to asking before every action — without an explicit `--permission-mode` or
`--allowedTools`, a headless run just hangs waiting for an approval no one's there to give.

**5. Never run Checkpoints 3, 5, 6, or 8 headless.** Start those interactively (plain `claude`) so
you're present for the byte-diff check and the ⛔ gates — that's the entire point of them.

**6. Flags drift between CLI versions.** Run `claude --help`, or check
[the CLI reference](https://code.claude.com/docs/en/cli-reference), before relying on any exact flag
name above — this list reflects the CLI as of writing, not necessarily your installed version.

---

## 0. Two repo issues to fix before Checkpoint 1

These aren't in the Roadmap but will silently break automation if left alone.

| Issue | Where | Fix |
|---|---|---|
| `source("diagnostics.R")` (lowercase) vs. actual file `Diagnostics.R` | `main.R` | Rename the `source()` call to `source("Diagnostics.R")`. Currently only "works" on case-insensitive filesystems (Windows/Mac); a Claude Code sandbox is typically Linux and will fail on `source()` before any checkpoint logic runs. |
| `.gitignore` has a blanket `*.csv` rule | repo root | Add `!tests/testthat/fixtures/*.csv` so the fixture CSVs that `TESTING_BLUEPRINT.md` §5 and Checkpoint 0 below create don't get silently untracked. |

Do both in a single tiny commit before anything else: `git commit -m "fix: case-sensitive source path; unignore test fixtures"`.

---

## 1. One-time setup for Claude Code

**`CLAUDE.md`** (repo root) — the standing context every invocation should have without you re-typing it:

```markdown
# Project conventions for Claude Code

- This is a set of R scripts (no package layout). Dependencies: tidyverse + fixest only.
  Do not add a new dependency without flagging it in your response first.
- `main.R` is the orchestrator; every other .R file defines one function and is `source()`d.
- Raw CBS CSVs are gitignored and live outside the repo (real path is set locally in main.R's
  `folder_path`). Never assume they're present in a sandbox; check before running Rscript against them.
- `DEFAULT_CONTROLS <- c("MatzavMishpachti","Dat","GilNK","MachozMegurim","TeudaGvoha")` is the
  single source of truth once Checkpoint 3 lands — don't reintroduce a local copy in any new file.
- Before implementing anything, read: docs/ROADMAP.md (the checkpoint in question),
  docs/LLD.md (schema/contracts), docs/HLD.md (why the gap exists), TESTING_BLUEPRINT.md
  (how to test it). Don't implement from the research doc directly — LLD/HLD already reconcile
  it against the real codebase.
- Every change that touches a function used elsewhere (data_processing.R, the controls list)
  needs the full `Rscript run_tests.R` suite green before you consider the task done.
- Never commit anything derived from real CBS microdata (cell counts, tables, plots) without a
  human explicitly reviewing it first — see the disclosure-risk note in Checkpoint 9 below.
```

**`.claude/settings.json`** — scope what it can touch:

```json
{
  "permissions": {
    "allow": [
      "Read(*)",
      "Edit(*.R)",
      "Write(tests/**)",
      "Write(docs/decisions/**)",
      "Bash(Rscript *)",
      "Bash(R -q -e *)",
      "Bash(git *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "WebFetch",
      "WebSearch"
    ]
  }
}
```

Adjust the `Bash(Rscript *)` scope down further if you want (e.g. `Bash(Rscript run_tests.R)` only,
requiring you to approve any other Rscript invocation by hand).

**Branching:** one branch per checkpoint — `checkpoint/00-test-bootstrap`, `checkpoint/01-validation`,
etc. — merged only after its gate (below) is satisfied. This gives you a clean revert point per
checkpoint and makes the CP3 "byte-identical diff" requirement checkable in a PR.

---

## 2. The per-checkpoint loop

Every checkpoint below follows this shape:

1. **Prime** — point Claude Code at the relevant Roadmap section + LLD/HLD context (by file reference,
   not pasted text — let it read the files itself).
2. **Plan** — for anything touching a shared file (`data_processing.R`, the controls list, `main.R`),
   ask for a short implementation plan before edits start. These files are sourced everywhere; a wrong
   assumption compounds.
3. **Implement** (Lane A) — agent writes code + tests.
4. **Test** (Lane A) — `Rscript run_tests.R` must be green.
5. **Gate** — see the ⛔/✅ markers per checkpoint below. Some checkpoints stop here for you.
6. **Verify** (Lane B, when applicable) — you run the Roadmap's literal `Rscript main.R` verification
   step against real data, since the agent likely can't.
7. **Commit** — `[CP<n>] <what> — verifies: <Roadmap verification step, abbreviated>`.

---

## 3. Checkpoint-by-checkpoint

### Checkpoint 0 — Test-suite bootstrap *(not in Roadmap; do first)*

**Why first:** Checkpoint 3 requires a byte-identical before/after diff of regression output — you
need a safety net in place before anyone (agent or you) touches shared code. `TESTING_BLUEPRINT.md`
also says this can run in parallel with the Roadmap, so there's no reason to defer it.

- **Lane:** A, fully.
- **Scope:** `tests/testthat/` structure, `run_tests.R`, fixture CSVs (~10–20 rows, all edge-case
  codes per `TESTING_BLUEPRINT.md` §"Integration tests"), Priority-1 table-driven recode tests
  (`Employed`, `WorkHoursCont`, `TeudaGvoha`, `BirthContinent`, `WorksOutsideLocality`, the filter
  block, factor conversion), the schema-presence test for the 7 positional column drops, and the
  `controls`-vector cross-file consistency test.
- **Do not touch:** logic in any of the 7 existing `.R` files.
- **Gate:** ✅ auto — `Rscript run_tests.R` exits 0, and every Priority-1 row in
  `TESTING_BLUEPRINT.md` has a corresponding test.

First command:

```bash
claude -p "Read TESTING_BLUEPRINT.md, docs/LLD.md, and docs/ROADMAP.md in full. Implement the
test-suite bootstrap: tests/testthat/ layout per TESTING_BLUEPRINT.md §5, run_tests.R, fixture
CSVs covering every edge-case code listed in TESTING_BLUEPRINT.md's integration-test section, the
Priority-1 table-driven recode tests, the schema-presence test for the positional column drops in
data_processing.R, and the controls cross-file consistency test across basic_regression.R,
basic_reg_compared_data.R, and employment_by_child_age.R. Do not modify the logic of any existing
.R file. Run Rscript run_tests.R at the end and report pass/fail." \
  --allowedTools "Read,Write,Edit,Bash(Rscript run_tests.R),Bash(R -q -e *)" \
  --permission-mode acceptEdits
```

---

### Checkpoint 1 — Data Validation & Quality Guard Layer

- **Lane A:** `validation.R` + `validate_cleaned_df()` with the hard-fail (`stop()`) and soft-fail
  (`warning()`) checks exactly as specified in `docs/LLD.md`'s Validation & Thresholds table; unit
  tests against a small synthetic tibble covering each check (both pass and trigger cases). Wire the
  call into `main.R` right after the cache load/build step.
- **Lane B (you run):** `Rscript main.R` end-to-end with real data — confirm no unexpected `stop()`
  or warning; then the negative test (`df_bad$Min[1] <- 1; validate_cleaned_df(df_bad)`) in an
  interactive session.
- **Gate:** ✅ auto for Lane A once tests pass. Lane B is informational — report back if a soft-fail
  warning fires on real data that Checkpoint 1's thresholds didn't anticipate (e.g., a control's NA
  rate has drifted past 5% since `docs/LLD.md` was written); that's new information, not a bug.

---

### Checkpoint 2 — Schema-Drift Check

- **Lane A:** `check_schema_drift(folder_path)` in `validation.R`, reading only CSV headers, checking
  the 7 named boundary-column pairs from `docs/ROADMAP.md`. Unit test: two tiny fixture header-only
  CSVs, one with columns in the expected order (passes) and one with two positions swapped (must
  throw a clear error). Wire the call into `main.R` before `load_and_clean_data()`.
- **Lane B (you run):** point `check_schema_drift()` at your real CSV folder — passes silently — then
  the negative test (copy one CSV, swap two header positions, confirm it throws).
- **Gate:** ✅ auto for Lane A. No decision needed.

---

### Checkpoint 3 — Shared `controls` Constant *(pure refactor — highest blast radius)*

- **Lane A:** define `DEFAULT_CONTROLS` once in `data_processing.R`; replace the local `controls <-
  c(...)` block in `basic_regression.R`, `basic_reg_compared_data.R`, `employment_by_child_age.R`,
  and the inline list in `Diagnostics.R`'s formula. The Checkpoint-0 consistency test should now be
  trivially satisfied (it's testing that these are all the same object).
- **Lane B (you run, required — this is the actual correctness check):** before merging, save the
  current `etable()` output for `basic_reg()` on real data (`saveRDS` or a printed capture); after the
  refactor, regenerate and diff. **Must be byte-identical** — this is a refactor, not a logic change.
  If it's not identical, treat that as a bug in the refactor, not a reason to update the baseline.
- **Gate:** ⛔ human — don't merge `checkpoint/03-*` until you've confirmed the before/after diff
  yourself. This is the one checkpoint where "tests pass" isn't sufficient evidence, because the
  Checkpoint-0 test suite doesn't yet cover full-pipeline numeric regression output.

---

### Checkpoint 4 — Intensive-Margin Regression

- **Lane A:** `intensive_margin_regression.R`, `run_intensive_margin_reg(cleaned_df, controls =
  DEFAULT_CONTROLS)` — `WorkHoursCont ~ Mother + Post + Mother:Post + controls`, filtered to
  `Employed == 1`, clustered by `IDPUF`. Contract tests per `TESTING_BLUEPRINT.md` §3: structure of
  the returned list, `fixest` class check, expected coefficient names present, plus a synthetic
  2×2 group-by-period dataset with a hand-computed true DiD effect. Wire a call into `main.R`.
- **Lane B (you run):** confirm `nobs(model)` matches the expected filtered row count on real data;
  read the `Mother:Post` coefficient.
- **Gate:** ⛔ human on the coefficient's plausibility only. The agent can check `nobs()` and that the
  model fit without error, but "is single-to-low-double-digit hours a sane magnitude given the
  employment-margin baseline" is a domain judgment call — have the agent report the number, don't let
  it self-certify "plausible."

---

### Checkpoint 5 — Gender Placebo Test *(breaking signature change + human-judgment step)*

- **Lane A:** change `load_and_clean_data()`'s signature to
  `load_and_clean_data(folder_path, sex_filter = c("women", "men"))`, defaulting to `"women"`
  (`Min==2`, unchanged behavior for every existing caller — **the full Checkpoint-0 suite must still
  pass unmodified**, since that's your guarantee the default path didn't regress). New
  `gender_placebo.R`, `run_gender_placebo(folder_path)`.
- **Lane B (you run):** `Rscript -e 'source("main.R"); run_gender_placebo("<your path>")'`; confirm no
  `fixest` collinearity/singularity error.
- ⛔ **Human gate, explicit, before trusting any output:** re-check every control's category sizes
  within the male subsample (a category sparse for women, e.g. single-father counts in
  `MisparHorimYechidim`, may be near-empty for men). Have the agent *compute and report* the category
  counts — do not have it decide unilaterally whether to collapse a sparse category; that's a modeling
  choice for you.
- ⛔ **Human gate, explicit, on interpretation:** an insignificant `Mother:Post` coefficient supports
  the motherhood-specific reading per the research doc's own success criterion — but that's a research
  conclusion. Have the agent report the coefficient and p-value; don't let it declare the placebo
  test "passed" or "failed" in the commit message or anywhere else.

---

### Checkpoint 6 — WFH-Exposure Index *(decision-first, no code until resolved)*

`docs/ROADMAP.md` is explicit that this checkpoint starts with **"a decision required first (not
code)"**: the 2020 WFH variable is the doc's specified anchor, but 2020 is excluded from the sample
entirely. Don't let the agent pick a side.

- ⛔ **Step 1 — human gate, before any implementation:** have Claude Code write a short decision memo
  to `docs/decisions/checkpoint6-wfh-anchor-year.md` laying out both paths from `docs/LLD.md`'s Gap
  Analysis — (a) pull a separate 2020-only CBS extract, or (b) formally use 2021 as the anchor year —
  with the tradeoffs already named there. **Stop after writing the memo.** You choose; record the
  choice in the same file.
- **Step 2 — Lane A**, once the decision is recorded: `wfh_exposure_index.R`,
  `build_wfh_exposure_index(cleaned_df, isco_col, wfh_col, ref_year)` per the `docs/LLD.md` signature.
  Unit test with a small synthetic occupation-level fixture (a handful of ISCO codes with known WFH
  shares) confirming the aggregation math.
- **Lane B (you run):** inspect real `idx` for silent NA propagation; the plausibility check against
  Bloom / Cohen & Manor (2024) is explicitly *not* an automated test per the Roadmap — the agent should
  print the ranking, not assert it's correct.
- **Gate:** ⛔ human at Step 1 (mandatory), then ✅ auto for Step 2's unit tests, ⛔ human again for the
  literature-plausibility read in Lane B.

---

### Checkpoint 7 — DDD Mechanism Regression

- **Depends on:** Checkpoint 6's `exposure_index` and its recorded anchor-year decision.
- **Lane A:** `ddd_regression.R`, `run_ddd_regression(cleaned_df, exposure_index, controls =
  DEFAULT_CONTROLS)` — the triple-interaction model and the second-stage `β_j ~ WFH_Exposure_j`
  mechanism regression. Structural/contract tests against synthetic exposure_index + synthetic panel
  data (both models fit, expected coefficient names present).
- **Lane B (you run):** confirm both models fit without collinearity errors on real data; check γ₁'s
  sign.
- **Gate:** ⛔ human on the sign/magnitude interpretation, same reasoning as Checkpoint 4 — the agent
  reports, you judge whether it supports the mechanism hypothesis.

---

### Checkpoint 8 — Age/Age² Escalation *(no-autonomy zone)*

This checkpoint has **no implementation task** — `docs/ROADMAP.md` confirms continuous age is
genuinely absent from the raw CBS extract (not a coding gap). Do not let Claude Code attempt to
fabricate an age proxy, back-calculate one, or request new data on its own.

- **Correct agent task:** produce a one-page decision-support note (not a code change) summarizing
  the two paths already named in `docs/LLD.md`'s Gap Analysis — (a) request a wider CBS extract, or
  (b) formally amend `motherhood_penalty_wfh_research.md` Part 4 §2 to specify `GilNK` (which is what
  Part 3 §3's advisor feedback already called for) — and then **stop**.
- **Gate:** ⛔ human, entirely. "Done" for this checkpoint is a recorded decision, not a test result.

---

### Checkpoint 9 — Persisted Output/Export Layer

- **Lane A:** `export_results.R`, `export_all_results(results_list, output_dir = "outputs")` writing
  each `etable()`/tibble to CSV and each `ggplot` to PNG. Unit tests using synthetic `fixest`/`ggplot`
  objects, confirming file creation and naming, not real content.
- **Lane B (you run):** `Rscript main.R` then `ls outputs/`; confirm one file per table/plot and that
  a sampled CSV/PNG matches console output from the same run.
- ⚠️ **Disclosure-risk flag before you commit anything under `outputs/`:** this pipeline aggregates
  CBS Labor Force Survey *microdata*. Several breakdowns in this repo produce small cells by
  construction — the Arab-women-only stratified regression, the youngest-child-age bins, the
  Jewish/Arab × mobility-by-year crosstab. Statistical agencies commonly restrict publishing
  tabulations below a minimum cell size under their microdata use terms. Have a human check CBS's
  actual disclosure rules for this extract before any `outputs/*.csv` derived from real data goes into
  a (potentially public) git history — this isn't something the agent can assess on its own, and it's
  a one-way door once committed.
- **Gate:** ✅ auto for Lane A tests; ⛔ human before committing any real-data-derived file under
  `outputs/`.

---

### Checkpoint 10 — Full-Pipeline Rollup Verification

- **Lane:** B, entirely — this is an integration checkpoint over the real pipeline, not a build step.
- **You run:** `Rscript main.R` end to end; confirm exit status 0, no hard-fail validation errors
  (Checkpoint 1), full `outputs/` artifact set (Checkpoint 9).
- **You tick, by hand:** every row of `docs/HLD.md`'s "HLD Gap Analysis" table against what now
  actually runs — each row should land on either "implemented" (Checkpoints 3–7) or "explicitly
  deferred with a recorded reason" (Checkpoint 8's memo, Checkpoint 9's deferred formatted-report
  dependency).
- **Gate:** ⛔ human sign-off closes the Roadmap. There's no automated criterion for "the roadmap is
  done" beyond this manual reconciliation — that's by design, since several rows resolve to
  deliberate deferrals rather than code.

---

## 4. Quick-reference table

| CP | What | Lane A (agent alone) | Lane B (you, real data) | Human decision gate | Depends on |
|---|---|---|---|---|---|
| 0 | Test bootstrap | ✅ | — | — | — |
| 1 | Validation guard | ✅ | confirm on real data | — | 0 |
| 2 | Schema-drift check | ✅ | confirm on real CSVs | — | 0 |
| 3 | Controls dedup | ✅ (refactor) | **byte-diff required** | ⛔ before merge | 0 |
| 4 | Intensive-margin reg | ✅ | nobs + coefficient | ⛔ plausibility | 0, 3 |
| 5 | Gender placebo | ✅ (signature+fn) | run against men | ⛔ sparsity + interpretation | 0, 3 |
| 6 | WFH-exposure index | memo only, then ✅ | plausibility vs. lit. | ⛔ anchor-year decision (first!) | 0 |
| 7 | DDD mechanism reg | ✅ | sign/magnitude read | ⛔ interpretation | 6 |
| 8 | Age/Age² | memo only | — | ⛔ entirely, no code | — |
| 9 | Export layer | ✅ | confirm outputs match | ⛔ before committing real-data output | 0 |
| 10 | Full rollup | — | full run + gap-table tick | ⛔ closes the roadmap | 1–9 |

---

## 5. Notes on the CLI mechanics

Claude Code's headless invocation is `claude -p "<prompt>"` (aliases `--print`). The flags used in the
example commands above (`--allowedTools`, `--permission-mode`, `--output-format`, `--max-turns`,
`--append-system-prompt`, `--resume`) are current as of this writing, but the CLI surface moves fast —
run `claude --help` or check the official reference before wiring these into a script you'll reuse,
rather than trusting flag names from memory.

A reasonable default for this project: `--permission-mode acceptEdits` (auto-accepts file edits, still
asks before anything else) for Checkpoints 0–4 and 9 where the risk is low and reversible via git;
drop back to interactive (no `-p`) for Checkpoints 5–8, since those are exactly the ones with a human
gate baked in and you'll want to be watching anyway.
