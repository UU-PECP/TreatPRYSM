# Metformin & aSAH — CPRD Aurum/HES APC pipeline

Adapted from the `tamsulosin/` pipeline for the protocol *"The effect of Metformin
use on risk of aneurysmal subarachnoid haemorrhage: A UK population-based cohort
study"* (v5.0).

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

## Structural decisions (see repo/session history for full discussion)

- **Parameterization**: each SAS stage is split into a small per-cohort driver
  (`%let` statements only — dates, caliper, dose cutoff, output paths) that
  `%include`s a shared body script containing the actual logic, referencing
  `&macrovariables` instead of hardcoded literals. No additional `%macro`
  nesting beyond what `tamsulosin/2_1` already has (`%drugdata` wrapping
  `%product`). Drug-specific `%product(...)` calls are written out explicitly
  per cohort (not looped), for auditability.
- **Recency** (on-treatment analysis): current (overlap with an episode) /
  recent (episode ended ≤3 months ago) / past (>3 months ago) — reuses
  `tamsulosin/7_1`'s existing Current/Recent/Past structure, just with the
  120-day cutoff changed to 90 days.
- **Dose**: fixed cutoff on mean daily dose — ≤1000 mg/day (low) vs.
  >1000 mg/day (high) — using the same `mean_daily_dose`/`cumulative_dose`
  variables already computed in the tamsulosin scripts. (Simpler than
  tamsulosin's protocol-specified DDD-based approach, which isn't actually
  implemented in `tamsulosin/` yet.)
- **Exclusions**: patients on a fixed-dose combination product containing
  *both* metformin and the comparator, and patients who initiate metformin and
  the comparator as separate products on the same day, are excluded entirely
  (active-comparator design) — mirrors the shape of `tamsulosin/2_1`'s Step 5
  mono/poly-combo exclusion.
- **Sex**: included as an adjustment covariate in the propensity score model
  and the adjusted Cox model (not stratified).
- **PS trimming**: adds an asymmetric trim (drop propensity scores below the
  2.5th or above the 97.5th percentile) before matching — a step the
  metformin protocol calls for that isn't in the tamsulosin scripts yet.
- **Matching caliper**: 0.02 (as specified in the metformin protocol) — note
  this differs from tamsulosin's amended 0.2.

## Outstanding / not yet built

- Codelists: metformin, sulphonylureas, SGLT2 inhibitors, T2DM diagnosis, and
  drug formulation/route of administration (tablet / slow-release / oral
  solution / oral suspension) — none exist yet.
- Raw data extract: not yet pulled; scripts use placeholder VDI paths
  (`F:\Users\Wyatt003\metformin\...`) to be updated once the extract exists.

## Layout (planned)

Mirrors `tamsulosin/`'s numbering, duplicated per cohort where the logic
differs only by comparator/date parameters (e.g.
`2_1_METFORMIN_metformin_su_cohort.sas` /
`2_1_METFORMIN_metformin_sglt2_cohort.sas`), sharing an `%include`d body
where possible.
