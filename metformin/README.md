# Metformin & aSAH — CPRD Aurum/HES APC pipeline

Adapted from the `tamsulosin/` pipeline for the protocol *"The effect of Metformin
use on risk of aneurysmal subarachnoid haemorrhage: A UK population-based cohort
study"* (v5.0).

**Status: a complete first draft of every stage now exists** (see Layout
below). It has not been run against real data (the raw extract doesn't exist
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
- **On-treatment Cox model** (`7_3_0`): uses a single combined 4-level factor
  (Comparator / Index-Current / Index-Recent / Index-Past) rather than
  tamsulosin's two separate additive terms (index-drug indicator + recency
  factor) - see that file's header comment for why (the protocol asks for
  each of current/recent/past index-drug use to be compared directly against
  a single current-comparator reference, which a combined factor gives
  directly and the additive version doesn't).

## Bugs found in `tamsulosin/7_1` while adapting it (not fixed there, only here)

- `output.BridgeCoverage_IndexDrug` is referenced in Step 2.2 but never built
  anywhere in the tamsulosin scripts, so `7_1` can't actually run past that
  step as committed. `metformin/7_0`'s Step 0.1 builds the equivalent
  explicitly.
- `end_of_fu` is capped at the *first* episode's end date, which means
  follow-up can never extend far enough for recency to leave "Current" -
  Recent/Past become unreachable. `metformin/7_0` doesn't apply that cap.

Worth deciding whether to port these two fixes back into the tamsulosin
scripts as well.

## Outstanding / not yet resolved

- **Raw data extract**: not yet pulled. Every script uses placeholder VDI
  paths (`F:\Users\Wyatt003\Metformin\...`) to be updated once the extract
  exists. Folder naming matches the convention `tamsulosin/`'s VDI paths were
  just renamed to: mother folder `Metformin` (capitalized), `Raw_Data` (raw
  extract), `Drug_Codes` (our metformin/SU/SGLT2i product codelists +
  `mg_value_lookup.txt`), `Disorder_Codes` (RareDiseases/T2DM diagnosis
  codelists, and the shared team comorbidity-flag library used by `3_3_0`) -
  other subfolders (`Output`, `BMI`, `VDI_Scripts`, `Results`) are unchanged.
  Note metformin's `Drug_Codes`/`Disorder_Codes` split didn't exist as named
  folders before this pass - they were both previously lumped into one
  `Codelists` folder, split apart here to match tamsulosin's separation
  between drug and diagnosis/comorbidity codelists.
- **Route of administration / formulation covariate**: the codelists already
  carry a clean `formulation` column, but how to bucket "Powder for oral
  solution" (4 metformin products) against the protocol's four named
  categories (tablet/slow-release/solution/suspension) is still undecided -
  not yet wired into any covariate script.
- **Qtern/Glyxambi** (SGLT2i+DPP-4i combos, no metformin involved) - still in
  the SGLT2i codelist; open question whether they should be excluded for
  monotherapy-only consistency on the comparator side.
- Nothing has been run against real data yet - table/column names for things
  outside our control (e.g. the exact HES APC diagnosis file layout, the
  eligibility table name) are copied from tamsulosin/1_1 on the assumption
  the metformin extract will be structured the same way. Confirm once the
  extract exists.
- This whole draft has not had a line-by-line review pass yet.

## Layout

```
1_0_METFORMIN_large_file_processing.sas    raw extract ingestion (generic, shared, run once)
1_1_METFORMIN_create_base_cohort.sas       T2DM population, aSAH linkage, rare disease exclusion (shared)

3_1_METFORMIN_smoking.sas                  GP-derived smoking status (shared, cohort-agnostic)
3_2_METFORMIN_bmi.sas                      GP-derived BMI (shared, cohort-agnostic)

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
