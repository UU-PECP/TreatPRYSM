# Metformin & aSAH — CPRD Aurum/HES APC pipeline

Adapted from the `tamsulosin/` pipeline for the protocol *"The effect of Metformin
use on risk of aneurysmal subarachnoid haemorrhage: A UK population-based cohort
study"* (v5.0).

**Status: a complete first draft of every stage now exists** (see Script-by-script
guide below). It has not been run against real data (the raw extract doesn't exist
yet - see Outstanding) and has not been reviewed line-by-line by the team, so
treat it as a draft to check, not a finished pipeline.

## Study design

Two active-comparator, new-user cohorts, split by calendar period (not by
diagnosis, unlike the tamsulosin study):

- **Cohort A**: metformin vs. sulphonylureas, 1 Jan 2004 – 31 Dec 2013
- **Cohort B**: metformin vs. SGLT2 inhibitors, 1 Jan 2014 – 31 Mar 2023

Both cohorts use the same design: per-protocol main analysis (censor at
switch/discontinuation) plus a time-dependent on-treatment analysis — closely
modelled on `tamsulosin/2_1`, `3_1`-`3_5`, `4_1`, `5_1`, and `7_1`-`7_3`
(the BPH active-comparator scripts), rather than the nephrolithiasis
non-user-comparator scripts (`1_2`/`2_2`).

Almost every stage follows the same **shared body + per-cohort driver**
pattern: a `_0`/`_body` file (e.g. `2_0`, `3_3_0`, `4_0`, `5_0`, `7_0`, `7_3_0`)
holds the actual logic and is never run directly; two tiny driver files (one
per cohort) set a handful of `%let`/R-variable parameters — dates, file
paths, labels — and then `%include`/`source()` the body. This keeps the two
cohorts from drifting into two copy-pasted, slowly-diverging scripts.

## Script-by-script guide

### Stage 1 — base cohort (shared by both cohorts)

- **`1_0_METFORMIN_large_file_processing.sas`** — Generic CPRD Aurum raw-extract
  ingestion (stringing together the split patient/practice/observation files,
  excluding Welsh practices). Reused unchanged in shape from
  `tamsulosin/1_0_large_file_processing.sas` — nothing drug-specific happens
  here. Run once against metformin's own raw extract (a separate pull from
  tamsulosin's, since the underlying patient population differs — T2DM here,
  BPH/nephrolithiasis there) before `1_1` can build the T2DM base cohort.
- **`1_1_METFORMIN_create_base_cohort.sas`** — Builds the T2DM base cohort and
  links it to HES APC for the aSAH outcome (same ICD-10 I60.x definition as
  tamsulosin — the outcome doesn't change between studies). Shared by both
  cohorts; `2_1`/`2_2` subset this further by calendar window and drug
  exposure. Uses a placeholder path for the shared HES/LSOA linkage extract
  (see Outstanding).

### Stage 2 — exposure generation (per cohort)

- **`2_0_METFORMIN_exposure_body.sas`** *(shared body, not run directly)* —
  Identifies metformin and comparator drug records by ATC/product codelist,
  builds the AdhereR-ready episode source table, restricts to HES-linked
  patients, and assigns an `index_exposure` code. Modelled on
  `tamsulosin/2_1`'s active-comparator design. Takes `&cohort_label`,
  `&startdate`, `&enddate`, `&comparator_file`, `&comparator_name` from
  whichever driver includes it.
- **`2_1_METFORMIN_su_cohort.sas`** — Driver for Cohort A: sets the 2004–2013
  window and the sulphonylurea codelist, then includes `2_0`.
- **`2_2_METFORMIN_sglt2i_cohort.sas`** — Driver for Cohort B: sets the
  2014–2023 window and the SGLT2 inhibitor (flozin) codelist, then includes `2_0`.

### Stage 3 — covariates (smoking/BMI shared; comorbidities/comedications per cohort)

- **`3_1_METFORMIN_smoking.sas`** — GP-derived smoking status (current/ex/never).
  Reused unchanged from Magdalena Gamba's original script — not drug- or
  cohort-specific. Shared by both cohorts; the combine step (`3_3_0`) merges
  it in per cohort using each cohort's own index date.
- **`3_2_METFORMIN_bmi.sas`** / **`3_2_METFORMIN_ALT_bmi.sas`** — GP-derived BMI,
  same origin and same patid-level, cohort-agnostic scope as the smoking
  script. Two versions currently exist side by side with slightly different
  header comments about which study-end cutoff date they're meant to
  represent — **not yet resolved which one is canonical**; check before
  running either.
- **`3_3_0_METFORMIN_covariates_body.sas`** *(shared body, not run directly)* —
  Merges comorbidity flags, comedication flags, and the smoking/BMI tables
  from above into one per-cohort covariate set. Modelled on
  `tamsulosin/3_1` (comorbidities), `3_4` (comedications), and `3_5`
  (combine). Two protocol-driven differences from the tamsulosin BPH
  covariate list: `nephrolith` is dropped (BPH/NL-specific) and `sex` is
  added (the BPH cohort is male-only; this study includes both sexes).
  `dutasteride`/`solifenacin`/`tadalafil` are also dropped from comedications
  (BPH-treatment specific). Assumes `2_1`/`2_2` and the smoking/BMI scripts
  have already run. Takes `&cohort_label` from its driver.
- **`3_3_METFORMIN_su_covariates.sas`** — Driver for Cohort A: sets
  `cohort_label=su`, includes `3_3_0`.
- **`3_4_METFORMIN_sglt2i_covariates.sas`** — Driver for Cohort B: sets
  `cohort_label=sglt2i`, includes `3_3_0`.

*(There is no Stage 6 in this pipeline — numbering jumps from 5 to 7, matching
the tamsulosin scripts it was adapted from.)*

### Stage 4 — treatment episodes (R / AdhereR, per cohort)

- **`4_0_METFORMIN_treatmentepisodes_body.R`** *(shared body, not run
  directly)* — Reads the per-cohort episode source table, splits records by
  drug (metformin vs. comparator) and by patient chunk, and runs
  `AdhereR::compute.treatment.episodes()` to build treatment episodes for the
  per-protocol analysis. Modelled on
  `tamsulosin/4_1_TAMSULOSIN_bph_treatmentepisodes.R`. Expects its driver to
  have set the episode/PS/base-cohort file paths, the study start/end dates,
  and the AdhereR follow-up window.
- **`4_1_METFORMIN_su_treatmentepisodes.R`** — Driver for Cohort A: 2004
  study start, 22-year follow-up window (covers index dates through the
  2025-03-31 database end, not just the 2013 initiation cutoff).
- **`4_2_METFORMIN_sglt2i_treatmentepisodes.R`** — Driver for Cohort B: 2014
  study start, 12-year follow-up window.

### Stage 5 — per-protocol analysis (R, per cohort)

- **`5_0_METFORMIN_pp_body.R`** *(shared body, not run directly)* — Multiple
  imputation, propensity-score trim + 1:1 match, and Cox model for the
  per-protocol design. Modelled on `tamsulosin/5_1_Tamsulosin_bph_pp.R`, but
  simplified to one comparator per cohort (tamsulosin's script handles two
  comparators — alfuzosin and finasteride — in parallel; each metformin
  cohort only has one). Three protocol-driven deviations from the tamsulosin
  script: **asymmetric PS trimming** (drop scores below the 2.5th or above
  the 97.5th percentile before matching — tamsulosin's script doesn't trim),
  **caliper 0.02 without replacement** (tamsulosin's amended value is a 0.2
  caliper *with* replacement — these are different choices for different
  stated reasons, not just a caliper change), and **`sex` included as a
  covariate** (irrelevant in the male-only BPH cohort).
- **`5_1_METFORMIN_su_pp.R`** — Driver for Cohort A: comparator label
  "Sulphonylureas", cohort-specific output paths.
- **`5_2_METFORMIN_sglt2i_pp.R`** — Driver for Cohort B: comparator label
  "SGLT2 inhibitors", cohort-specific output paths.

### Stage 7 — on-treatment analysis (SAS interval-building, then R Cox models; per cohort)

- **`7_0_METFORMIN_on_treatment_body.sas`** *(shared body, not run directly)* —
  Builds interval-level on-treatment data with a **recency** flag
  (Current/Recent/Past, 90-day cutoff — vs. tamsulosin's 120-day cutoff) and
  a **dose category** (≤1000 mg/day vs. >1000 mg/day mean daily dose).
  Modelled on `tamsulosin/7_1_tamsulosin_bph_on_treatment.sas`, but fixes two
  bugs discovered in that script while adapting it (see Bugs found below) —
  these are deliberate corrections, not just format changes.
- **`7_1_METFORMIN_su_on_treatment.sas`** — Driver for Cohort A: includes
  `7_0` with the Cohort A episode csv and the shared `31MAR2025` database-end
  date.
- **`7_2_METFORMIN_sglt2i_on_treatment.sas`** — Driver for Cohort B: same
  shape, Cohort B episode csv.
- **`7_3_0_METFORMIN_ot_analysis_body.R`** *(shared body, not run directly)* —
  Fits the on-treatment Cox models from `7_0`'s interval data: incidence
  rates, crude Cox, KM, and a counting-process time-varying Cox adjusted for
  BMI/smoking/age. One structural change from
  `tamsulosin/7_3_tamsulosin_ot.R`: instead of two separate additive terms
  (index-drug indicator + recency factor, which only recovers each term's
  marginal effect), this builds **one combined 4-level factor**
  (Comparator / Index-Current / Index-Recent / Index-Past) with "Comparator"
  as the reference — giving each of current/recent/past index-drug use as a
  direct contrast against current comparator use in a single coefficient, no
  interaction term needed. Matches what the metformin protocol explicitly
  asks for.
- **`7_3_METFORMIN_su_ot.R`** — Driver for Cohort A: comparator label
  "Sulphonylureas", 2004 study start (filters spurious pre-study intervals).
- **`7_4_METFORMIN_sglt2i_ot.R`** — Driver for Cohort B: comparator label
  "SGLT2 inhibitors", 2014 study start.

### Orchestration and codelists

- **`RunAll_METFORMIN.sas`** — Runs the SAS stages in order: `1_1` → (`2_1` →
  `3_3`) → (`2_2` → `3_4`), with `3_1`/`3_2` (smoking/BMI) run once in between
  since they're shared. Does **not** run the R stages (`4_x`/`5_x`/`7_3x`) —
  those are run separately once their SAS inputs exist, per the comment block
  at the bottom of the file.
- **`codelists/mg_value_lookup.sas`** — Macro that extracts a per-product
  `mg_value` from a codelist's substance-strength string. Deliberately NOT
  the same convention as tamsulosin's codelists (which just take the first
  number in the strength string): several metformin combination products
  (e.g. Jentadueto: "Linagliptin/Metformin hydrochloride", "2.500mg +
  1000.000mg") don't list metformin first, so "first number" would silently
  report the wrong drug's dose. This version matches strength segments to
  named substances instead.
- **`codelists/raw_cprd_browser_exports/`** — The actual CPRD codebrowser
  exports the pipeline reads: `metformin.txt`, `sulfonylureas.txt`,
  `flozins.txt`, `diabetes_t2dm.txt`, and the generated
  `mg_value_lookup.txt`.
- **`File path shift`** — there is a shift from file path F:... to E:..> in files 7_x. They are intended to be run on the datalab computers, which do not have access to the F: folder. 

## Structural decisions

- **Parameterization**: each stage is split into a small per-cohort driver
  (`%let`/R-variable assignments only — dates, caliper, dose cutoff, output
  paths) that `%include`s/`source()`s a shared body script containing the
  actual logic. No additional `%macro` nesting beyond what `tamsulosin/2_1`
  already has (`%drugdata` wrapping `%product`).
- **Recency** (on-treatment analysis): current (overlap with an episode) /
  recent (episode ended ≤3 months ago) / past (>3 months ago) — reuses
  `tamsulosin/7_1`'s Current/Recent/Past structure, with the 120-day cutoff
  changed to 90 days.
- **Dose**: fixed cutoff on mean daily dose — ≤1000 mg/day (low) vs.
  >1000 mg/day (high).
- **Exposure codelist**: metformin monotherapy plus combination products with
  non-comparator drugs (TZDs, DPP-4 inhibitors) - combination products with
  either comparator class (SGLT2i) were removed from both codelists at the
  source, so there's no ProdCodeId overlap to exclude at runtime. No
  sulphonylurea+metformin combo products were found in the CPRD Aurum
  codebrowser at all.
- **mg_value lookup** (`codelists/mg_value_lookup.sas` /
  `.txt`): built with substance-aware parsing (matches the segment naming the
  target drug in `drugsubstancename`/`substancestrength`), not tamsulosin's
  "first number in the string" convention — two metformin combo products
  (Jentadueto, Vipdomet) list their partner drug before metformin, so "first
  number" would report the wrong drug's dose.
- **Sex**: included as an adjustment covariate in the propensity score model
  and the adjusted Cox model (not stratified).
- **PS trimming**: asymmetric trim (drop propensity scores below the 2.5th or
  above the 97.5th percentile) before matching, implemented as a manual
  per-imputation `glm()` + `matchit()` loop (see `5_0`'s header comment for
  why this isn't done via `MatchThem`, unlike `tamsulosin/5_1`).
- **Matching**: 1:1 nearest-neighbour, caliper 0.02, WITHOUT replacement (the
  metformin protocol doesn't specify replacement; tamsulosin's amended 0.2
  caliper is specifically WITH replacement - these are different choices for
  different reasons, not just a caliper-value change. Worth double-checking
  this is what's intended).
- **On-treatment Cox model** (`7_3_0`): uses multi-level interaction variable 
  to calculate recency and dose interactions

## File layout

```
1_0_METFORMIN_large_file_processing.sas    raw extract ingestion (generic, shared, run once)
1_1_METFORMIN_create_base_cohort.sas       T2DM population, aSAH linkage, rare disease exclusion (shared)

3_1_METFORMIN_smoking.sas                  GP-derived smoking status (shared, cohort-agnostic)
3_2_METFORMIN_bmi.sas / _ALT_bmi.sas       GP-derived BMI (shared, cohort-agnostic - two versions, see Outstanding)

2_0_METFORMIN_exposure_body.sas            shared body: exposure generation
2_1_METFORMIN_su_cohort.sas                driver: Cohort A (metformin vs. SU)
2_2_METFORMIN_sglt2i_cohort.sas            driver: Cohort B (metformin vs. SGLT2i)

3_3_0_METFORMIN_covariates_body.sas        shared body: comorbidities + comedications + smoking/BMI merge
3_3_METFORMIN_su_covariates.sas            driver: Cohort A
3_4_METFORMIN_sglt2i_covariates.sas        driver: Cohort B

4_0_METFORMIN_treatmentepisodes_body.R     shared body: AdhereR treatment episodes
4_1_METFORMIN_su_treatmentepisodes.R       driver: Cohort A
4_2_METFORMIN_sglt2i_treatmentepisodes.R   driver: Cohort B

5_0_METFORMIN_pp_body.R                    shared body: PS trim + match + Cox (per-protocol)
5_1_METFORMIN_su_pp.R                      driver: Cohort A
5_2_METFORMIN_sglt2i_pp.R                  driver: Cohort B

7_0_METFORMIN_on_treatment_body.sas        shared body: 30-day intervals, recency, dose, BMI/smoking merge
7_1_METFORMIN_su_on_treatment.sas          driver: Cohort A
7_2_METFORMIN_sglt2i_on_treatment.sas      driver: Cohort B

7_3_0_METFORMIN_ot_analysis_body.R         shared body: time-varying Cox (recency/dose/duration)
7_3_METFORMIN_su_ot.R                      driver: Cohort A
7_4_METFORMIN_sglt2i_ot.R                  driver: Cohort B

RunAll_METFORMIN.sas                       orchestrates the SAS stages (1_1 through 3_4); R stages run separately

codelists/
  raw_cprd_browser_exports/
    metformin.txt          72 ProdCodeIds - monotherapy + non-comparator combos
    sulfonylureas.txt       51 ProdCodeIds - monotherapy only
    flozins.txt              22 ProdCodeIds - SGLT2i, metformin combos excluded
    diabetes_t2dm.txt       80 Read/medcodes - T2DM diagnosis + DESMOND education codes
    mg_value_lookup.txt     145 rows - ProdCodeId -> mg_value, substance-aware
  mg_value_lookup.sas       reusable macro that generates mg_value_lookup.txt
```
