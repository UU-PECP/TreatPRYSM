# Tamsulosin & aSAH — CPRD Aurum/HES APC pipeline

Easy access to code now found at https://github.com/UU-PECP/TreatPRYSM/tree/claude/inspiring-lovelace-r9mii8

The Treat-PRYSM project: a UK population-based cohort study of tamsulosin
(an alpha-blocker) and risk of aneurysmal subarachnoid haemorrhage (aSAH),
using linked CPRD Aurum primary-care and HES APC hospital-admission data.
This is the pipeline this study's design was built from, and the one the
`metformin/` pipeline was later adapted from — see that folder's README for
the deviations made there.

## Study design

Two parallel cohorts, both using tamsulosin as the exposure:

- **BPH cohort** (`1_1`, `2_1`, `3_x`, `4_1`, `5_1`, `7_1`-`7_3`): an
  **active-comparator**, new-user design. Men prescribed tamsulosin for
  benign prostatic hyperplasia (BPH), compared against two separate
  alpha-blocker/5-alpha-reductase-inhibitor comparators — **alfuzosin** and
  **finasteride** — each analysed in its own parallel block within the same
  scripts (`index_exposure`: 1 = tamsulosin, 2 = alfuzosin, 3 = finasteride).
- **Nephrolithiasis (NL) cohort** (`1_2`, `2_2`): tamsulosin used
  off-label to aid passage of ureteral stones, compared against standard-of-care
  analgesics. A separate, non-active-comparator indication, run alongside
  the BPH cohort but through its own `1_2`/`2_2` scripts (not integrated into
  `3_x` onward, which are BPH-only).

Both use the same downstream design as metformin was later modelled on: a
per-protocol main analysis (SMR-weighted propensity score, R) plus a
time-dependent on-treatment analysis (interval-level recency/dose, SAS +
R Cox models).

## Script-by-script guide

### Stage 1 — base cohorts and HES linkage

- **`1_0_large_file_processing.sas`** — Generic CPRD Aurum raw-extract
  ingestion: strings together the split patient/practice/observation extract
  files into single base tables. Nothing drug- or disease-specific happens
  here; run once against the raw extract before anything else.
- **`1_1_TAMSULOSIN_create_base_cohorts.sas`** — Builds the BPH cohort's
  outcome and exclusion tables: aSAH cases from HES APC (ICD-10 I60.x),
  and rare-disease exclusions. Sets up the `rawdata`/`output`/`codelist`
  libnames used throughout the rest of the BPH scripts.
- **`1_2_TAMSULOSIN_create_nl_cohort.sas`** — Same idea for the
  nephrolithiasis cohort: identifies each patient's first NL diagnosis date.
  Reuses `output.clinical`, `output.initial_cohort`, `output.aSAH_apc`, and
  `output.rarediseasecases` from `1_0`/`1_1` rather than rebuilding them —
  run those two first.

### Stage 2 — exposure generation (per cohort)

- **`2_1_TAMSULOSIN_tamsulosin_bph_cohort.sas`** — BPH active-comparator
  exposure generation: identifies tamsulosin/alfuzosin/finasteride drug
  records via ATC codelist (`%product` inside `%drugdata`), builds the
  AdhereR-ready episode source table (`output.all_bph_episodes`), and
  restricts to HES-linked patients (`hes_linkage_patients`, joined against
  `rawdata.aurum_eligibility_jan2026`).
- **`2_2_TAMSULOSIN_tamsulosin_nl_cohort.sas`** — Same structure for the NL
  cohort: tamsulosin vs. standard-of-care analgesic drug records, HES-linkage
  attrition, `output.linked_nl_cohort`.

### Stage 3 — covariates (BPH cohort only)

- **`3_1_0_codelist_adapter.sas`** — Reads the shared team comorbidity
  codelist text files (one per condition — alopecia, chronic liver disease,
  etc.) from `Disorder_Codes` into SAS datasets in the `codelist` library.
  Needs to run before `3_1`, which references those datasets by name.
- **`3_1_bph_propensity_score_vars.sas`** — Initializes the main PS covariate
  table (`output.bph_pp_propscor`) from `output.all_bph_episodes`, computing
  each patient's index date and setting up the comorbidity-merge macros used
  later. *Has an open "doublecheck" comment in the file about an apparent
  `codelist`/`codelis` naming inconsistency — not yet resolved.*
- **`3_2_smoking.sas`** — GP-derived smoking status (current/ex/never),
  originally written by Magdalena Gamba. Not BPH-specific in itself; produces
  `output.smoking_all`.
- **`3_3_bmi.sas`** — GP-derived BMI, same origin as the smoking script.
  Produces `output.bmi_all`.
- **`3_4_medication_covariates.sas`** — Comedication flags for the BPH
  cohort (antihypertensives, lipid-lowering drugs, anticoagulants, NSAIDs,
  opioids, antiemetics, antidiabetics, SNRIs, dutasteride, solifenacin,
  tadalafil), built from drug issue records restricted to
  `output.all_bph_episodes` patients.
- **`3_5_bph__pp_propsensity_score_combine_all_variables.sas`** — Merges the
  comorbidity flags, comedication flags, and smoking/BMI tables onto the PS
  covariate table, and adds the deprivation index (`imd`) from the HES-LSOA
  linkage extract (`patient_2019_imd_25_006098.txt`), joined on `patid`. Ends
  with sanity-check `proc freq`/`proc means` on the combined covariate set.

*(There is no Stage 6 — numbering jumps from 5 to 7, matching the on-treatment
scripts' origin as a separate, later addition to the pipeline.)*

### Stage 4 — treatment episodes (R / AdhereR)

- **`4_1_TAMSULOSIN_bph_treatmentepisodes.R`** — Reads
  `output.all_bph_episodes`, splits records into chunks by `patid` and by
  drug (tamsulosin/alfuzosin/finasteride), and runs
  `AdhereR::compute.treatment.episodes()` on each to build treatment
  episodes feeding the per-protocol analysis (file 5).

### Stage 5 — per-protocol analysis (R)

- **`5_1_Tamsulosin_bph_pp.R`** — The main per-protocol analysis. Multiply
  imputes covariates (`mice`), builds SMR-weighted propensity scores
  (`weightthem`, ATT estimand, trimmed at the 97.5th percentile) separately
  against each comparator (alfuzosin, finasteride), and fits weighted Cox
  models for both the main aSAH outcome and an `aSAH_specific` sensitivity
  outcome (excludes non-specific I60.8/I60.9 ICD codes) on the same weighted
  sample. Also produces incidence rates with 95% CIs, a Table 1, a combined
  KM plot, and propensity-score diagnostic histograms/density plots per
  comparator.

### Stage 7 — on-treatment analysis (SAS interval-building, then R Cox models)

**NOTE: MUST BE RUN ON DATALAB COMPUTERS WITH AROUND 60GB OF RAM NEEDED**

- **`7_1_tamsulosin_bph_on_treatment.sas`** — Builds interval-level
  on-treatment data from the treatment episodes: a **recency** flag
  (Current/Recent/Past, 120-day cutoff) and a **dose category**
  (`dose_category_perday`, based on `mean_daily_dose` — mg per prescription
  x quantity / assumed duration — vs. a 0.4 mg/day-equivalent threshold).
  **Two known issues** (found and fixed only in the metformin adaptation of
  this file, `metformin/7_0` — not yet ported back here): Step 2.2 reads
  from `output.BridgeCoverage_IndexDrug`, which is referenced but never
  actually built anywhere in this file or elsewhere in these scripts, so as
  committed this can't run past that step; and `end_of_fu` is capped at the
  *first* treatment episode's end date, which means a patient's recency
  status can never transition away from "Current" during that first episode
  — Recent/Past become unreachable. See `metformin/README.md`'s "Bugs found"
  section for the fixes applied there.
- **`7_2_tamsulosin_bph_ot_bmi_smoking.sas`** — Merges the most-recent
  on-or-before-interval BMI and smoking status onto each on-treatment
  interval from `7_1`, using the same recency logic as the amlodipine
  on-treatment script in `AdditionalScripts/`.
- **`7_3_tamsulosin_ot.R`** — Fits the on-treatment Cox models: patient-level
  crude incidence/Cox/KM against each comparator, a counting-process
  time-varying Cox with recency (as a separate additive term alongside the
  tamsulosin indicator) adjusted for time-varying BMI/smoking/age, and a
  secondary dose-sensitivity Cox model (Comparator / Current-Low /
  Current-High dose, among intervals currently on tamsulosin). There is a transition from the F:... path to the E:... path for files, as the pipeline is built for use on the Datalab computer. 

### Orchestration

- **`Run_All_TAMSULOSIN.sas`** — Runs the full SAS side of the pipeline in
  order: `1_1` → `2_1` → `3_1_0` → `3_1` → `3_2` → `3_3` → `3_4` → `1_2` →
  `2_2` → `3_5`. Does not run the R stages (`4_1`, `5_1`, `7_3`) — those are
  run separately once their SAS inputs exist.
- **`RunAll_OT_only.sas`** — A shorter orchestration covering just the
  on-treatment SAS steps, `7_1` then `7_2`, for re-running that stage alone
  once the rest of the pipeline's outputs already exist.

## File layout

```
1_0_large_file_processing.sas                        raw extract ingestion (generic, run once)
1_1_TAMSULOSIN_create_base_cohorts.sas                BPH cohort: aSAH/HES linkage, rare disease exclusions
1_2_TAMSULOSIN_create_nl_cohort.sas                   NL cohort: nephrolithiasis case identification

2_1_TAMSULOSIN_tamsulosin_bph_cohort.sas              BPH exposure generation (tamsulosin/alfuzosin/finasteride)
2_2_TAMSULOSIN_tamsulosin_nl_cohort.sas                NL exposure generation (tamsulosin vs. standard-of-care)

3_1_0_codelist_adapter.sas                            loads shared comorbidity codelists
3_1_bph_propensity_score_vars.sas                     initializes BPH PS covariate table
3_2_smoking.sas                                       GP-derived smoking status
3_3_bmi.sas                                           GP-derived BMI
3_4_medication_covariates.sas                         BPH comedication flags
3_5_bph__pp_propsensity_score_combine_all_variables.sas   combines covariates + deprivation index (imd)

4_1_TAMSULOSIN_bph_treatmentepisodes.R                AdhereR treatment episodes (BPH)

5_1_Tamsulosin_bph_pp.R                               per-protocol analysis: PS weighting + Cox (R)

7_1_tamsulosin_bph_on_treatment.sas                   on-treatment intervals: recency + dose category
7_2_tamsulosin_bph_ot_bmi_smoking.sas                 time-varying BMI/smoking merge onto intervals
7_3_tamsulosin_ot.R                                   on-treatment Cox models: recency + dose sensitivity (R)

Run_All_TAMSULOSIN.sas                                orchestrates the full SAS pipeline (R stages run separately)
RunAll_OT_only.sas                                    orchestrates just the on-treatment SAS steps (7_1, 7_2)
```
This Readme File was made with the help of Claude. It may contain inaccuracies!