
/**************************************************************************/
/*  Treat-PRYSM - Metformin and aSAH risk                                 */
/*  File 7_0: ON-TREATMENT ANALYSIS - SHARED BODY                         */
/*  Re-adapted from tamsulosin/7_1_tamsulosin_bph_on_treatment.sas's      */
/*  current (post-fix) design, per an explicit decision to structurally  */
/*  match it row-for-row rather than keep this file's earlier,           */
/*  patient-level-only architecture.                                      */
/*                                                                          */
/*  WHAT CHANGED FROM THE EARLIER VERSION OF THIS FILE:                   */
/*                                                                          */
/*  1) Unit of analysis is now the EPISODE, not the patient. The earlier  */
/*     version built ONE continuous 30-day-interval grid per patient      */
/*     (index_date fixed at the patient's first-ever episode, via         */
/*     `nodupkey by patid`). tamsulosin/7_1's current design instead      */
/*     keeps every one of a patient's episodes (of EITHER drug) as its    */
/*     own row, with index_date = THAT episode's own start, and builds    */
/*     a fresh 30-day-interval grid for each one. This is what makes it   */
/*     possible for the on-treatment Cox model below to compare current/  */
/*     recent/past USE OF EITHER DRUG (see point 3) - but it also means   */
/*     the Cox model's time origin resets at each episode's own start     */
/*     rather than running on one continuous timeline from the patient's  */
/*     actual cohort entry. This was flagged explicitly while adapting -  */
/*     see the metformin/README.md "Bugs found" section for the tamsulosin */
/*     side of this - and kept deliberately, to match tamsulosin exactly. */
/*                                                                          */
/*  2) BridgeCoverage_&cohort_label is now built from ALL of a patient's   */
/*     episodes of EITHER drug (previously: only their own index          */
/*     exposure's episodes), each tagged with its own `exposure`. Step 2.2 */
/*     joins on (patid, exposure) so each interval only ever picks up      */
/*     coverage of the SAME drug as its own row's episode.                */
/*                                                                          */
/*  3) STEP 2.3's recency classification and the R-side Cox model (7_3_0)  */
/*     now compute Current/Recent/Past for whichever drug a given row's    */
/*     episode is actually for - including comparator episodes, which      */
/*     used to be lumped into one flat "Comparator" category. Crossed with */
/*     the drug flag (metformin 0/1), this gives a 6-level recency factor   */
/*     (Current/Recent/Past x Comparator/metformin) instead of the         */
/*     earlier 4-level one (Comparator / Index-Current / Index-Recent /    */
/*     Index-Past).                                                        */
/*                                                                          */
/*  TWO KNOWN LIMITATIONS CARRIED OVER UNCHANGED (found while doing this   */
/*  adaptation, deliberately NOT fixed here - flag for a future pass):     */
/*    - STEP 1.0's episode-level `mean_daily_dose` (in                    */
/*      output.&cohort_label._treatmentepisodes_mgqty) is computed as      */
/*      mean(mg_value) - the raw per-tablet strength - not the true        */
/*      per-day dose (mg_value x tablets/day) that 2_0 already computes    */
/*      correctly and carries into output.all_&cohort_label._episodes as   */
/*      its OWN `mean_daily_dose` column. That correct value is not the    */
/*      one read back in here (rx_sorted below only keeps mg_value), so    */
/*      dose_category's 1000mg/day threshold is being compared against     */
/*      per-tablet strength, not true daily dose.                          */
/*    - STEP 2.1/2.1b's "last known dose"/"last known release pattern"     */
/*      carry-forward (mg_sorted/rx_release) is built from ALL of a        */
/*      patient's prescriptions of EITHER drug, not filtered to their      */
/*      own index exposure the way BridgeCoverage now is - so a            */
/*      comparator prescription issued between two metformin fills can     */
/*      overwrite mg_value_current/release_pattern_current mid-episode.    */
/*                                                                          */
/*  Required %let parameters from the driver:                             */
/*    &cohort_label   - e.g. su / sglt2i                                  */
/*    &study_end       - overall database end, the same for both cohorts */
/*                       (not either cohort's own calendar window end):   */
/*                       '31MAR2025'd                                     */
/*    &episodes_csv    - path to the FULL (not per-protocol-filtered)     */
/*                       AdhereR episodes csv from 4_0 (both exposure and */
/*                       comparator episodes, all recurrences)            */
/**************************************************************************/;

libname rawdata "E:\Metformin\Raw_Data";
libname output "E:\Metformin\Output";
libname codelist "E:\Metformin\Drug_Codes";
options fullstimer;

/**************************************************************************/
/* STEP 0.0: Import R-generated treatment episodes (ALL episodes, both    */
/* exposure and comparator, all recurrences - not the per-protocol,       */
/* first-episode-only file used in 4_0/5_0).                              */
/**************************************************************************/

data output.&cohort_label._treatmentepisodes;
	infile "&episodes_csv" dsd dlm=',' firstobs=2 truncover;
	length exposure 8 patid $19 episode_ID 8
	       episode_start 8 end_episode_gap_days 8 episode_duration 8 episode_end 8;
	input exposure patid :$19. episode_ID
	      episode_start :yymmdd10. end_episode_gap_days episode_duration episode_end :yymmdd10.;
	format episode_start episode_end date9.;
run;

/**************************************************************************/
/* STEP 0.1: Build the bridge-coverage table Step 2.2 relies on. Every    */
/* episode of EITHER drug becomes one coverage block, keyed by (patid,    */
/* exposure) - not restricted to each patient's own index exposure - so   */
/* recency can be computed for comparator episodes too (see header).      */
/**************************************************************************/

proc sql;
	create table output.BridgeCoverage_&cohort_label as
	select patid,
	       exposure,
	       episode_start as bridged_coverage_start,
	       episode_end   as bridged_coverage_end
	from output.&cohort_label._treatmentepisodes;
quit;

/**************************************************************************/
/* STEP 1.0: Create mg value and mean daily dose (per episode, from the   */
/* underlying prescriptions - same pattern as tamsulosin/7_1).            */
/**************************************************************************/

proc sort data = output.&cohort_label._treatmentepisodes; by patid exposure; run;
proc sort data = output.all_&cohort_label._episodes out = rx_sorted(keep = patid exposure issuedate quantity mg_value);
  by patid exposure issuedate;
run;

proc sql;
  create table output.episodes_with_qty as
  select e.patid,
         e.exposure,
         e.episode_ID,
         e.episode_start,
         e.episode_end,
         sum(r.quantity) as total_tablets,
		 mean(r.mg_value) as mean_daily_dose
  from output.&cohort_label._treatmentepisodes e
       inner join rx_sorted r
       on e.patid = r.patid
       and e.exposure = r.exposure
       and r.issuedate >= e.episode_start
       and r.issuedate <= e.episode_end
  group by e.patid, e.exposure, e.episode_ID, e.episode_start, e.episode_end;
quit;

proc sort data = output.episodes_with_qty; by patid exposure episode_ID; run;
proc sort data = output.&cohort_label._treatmentepisodes; by patid exposure episode_ID; run;

data output.&cohort_label._treatmentepisodes_mgqty;
  merge output.&cohort_label._treatmentepisodes(in=a)
        output.episodes_with_qty(in=b);
  by patid exposure episode_ID;
  if a;
run;

/**************************************************************************/
/* Dose category, per metformin protocol: <=1000mg/day low, >1000mg/day  */
/* high (fixed threshold on mean daily dose - simpler than tamsulosin's   */
/* DDD-based approach, which isn't implemented anywhere in that repo).   */
/**************************************************************************/

data output.&cohort_label._treatmentepisodes_mgqty;
set output.&cohort_label._treatmentepisodes_mgqty;
cumulative_dose = total_tablets*mean_daily_dose;
if mean_daily_dose ne . then do;
	if mean_daily_dose <= 1000 then dose_category = 'Low';
	else dose_category = 'High';
end;
/* Continuous duration category, per protocol: <1yr / >=1yr */
if episode_duration ne . then do;
	if episode_duration >= 365 then duration_category = '>=1yr';
	else duration_category = '<1yr';
end;
run;

/**************************************************************************/
/* STEP 1.1: Create end of follow-up variable. One row per EPISODE (not   */
/* deduplicated to one row per patient) - index_date/index_exposure are   */
/* this episode's own start/drug, mirroring tamsulosin/7_1 exactly. See   */
/* header comment (point 1) on what this means for the Cox model's time   */
/* origin.                                                                 */
/**************************************************************************/

proc sort data = output.t2dm_cohort;
by patid;
run;

data output.&cohort_label._episodes_fu;
	merge output.&cohort_label._treatmentepisodes_mgqty(in=inA)
		  output.t2dm_cohort(in=inB keep=patid censordate aSAH_apc_dt);
	by patid;
	if inA and inB;
	earliest_rx_date = episode_start;  /* episode_start is the first Rx date of this AdhereR-bridged episode */
	index_date = earliest_rx_date;
	index_exposure = exposure;
	end_of_fu = &study_end;

	if not missing(censordate) and censordate < end_of_fu then end_of_fu = censordate;
	if not missing(aSAH_apc_dt) and aSAH_apc_dt < end_of_fu then end_of_fu = aSAH_apc_dt;

	/* Only keep if valid follow-up (index_date < end_of_fu) */
	if index_date < end_of_fu;

	format index_date end_of_fu date9.;
run;

/**************************************************************************/
/* STEP 2.0: Build 30-day intervals from THIS episode's own start to      */
/* end_of_fu, for every episode row (not just each patient's first).      */
/**************************************************************************/

data output.ThirtyDayIntervals_&cohort_label;
	set output.&cohort_label._episodes_fu;
	by patid;

	interval_window_start = episode_start;
	do while (interval_window_start <= end_of_fu);
		interval_window_end = min(interval_window_start + 29, end_of_fu);
		output;
		interval_window_start = interval_window_end + 1;
	end;

	format interval_window_start interval_window_end date9.;
run;

/**************************************************************************/
/* STEP 2.1: Carry most-recent per-Rx dose (mg_value) into each interval  */
/* (see header - not filtered to the patient's own index exposure, same   */
/* limitation as tamsulosin/7_1's own equivalent step).                   */
/**************************************************************************/

proc sort data = output.all_&cohort_label._episodes
          out  = mg_sorted(keep=patid issuedate mg_value);
	by patid issuedate;
run;

proc sort data = output.ThirtyDayIntervals_&cohort_label
                 (rename=(interval_window_start = issuedate))
          out  = int_sorted;
	by patid issuedate;
run;

data output.IntervalDose_&cohort_label;
	merge mg_sorted(in=inRx)
	      int_sorted(in=inInt);
	by patid issuedate;
	retain last_dose;

	if inRx  then last_dose = mg_value;
	if inInt then do;
		interval_window_start   = issuedate;
		mg_value_current        = last_dose;
		output;
	end;
	drop issuedate last_dose;
run;

/**************************************************************************/
/* STEP 2.1b: Release pattern (formulation) sensitivity analysis - bucket */
/* metformin's own raw formulation strings (from codelist.metformin_cod,  */
/* built in 2_0) into 4 categories, and carry the most recent one forward */
/* per interval the same way mg_value_current is (Step 2.1). "Powder for  */
/* oral solution/ Powder" is grouped with "Oral solution" - reconstituted */
/* before use, consumed as a liquid the same way. The comparator's own    */
/* formulation is never resolved here - the sensitivity model (7_3_0)    */
/* collapses all comparator intervals into one "Comparator" reference     */
/* category regardless, same as the existing dose/duration models.       */
/**************************************************************************/

data release_pattern_lookup;
	set codelist.metformin_cod (keep = prodcodeid formulation);
	length release_pattern $20;
	if formulation = "Tablet/ Oral Tablet" then release_pattern = "Standard tablet";
	else if formulation = "Modified-release tablet" then release_pattern = "Slow-release tablet";
	else if formulation in ("Oral solution", "Powder for oral solution/ Powder") then release_pattern = "Oral solution";
	else if formulation = "Oral suspension" then release_pattern = "Oral suspension";
run;

proc sort data = output.all_&cohort_label._episodes (keep=patid issuedate prodcodeid)
          out  = rx_release;
	by prodcodeid;
run;

proc sort data = release_pattern_lookup; by prodcodeid; run;

data rx_release;
	merge rx_release (in=inRx) release_pattern_lookup (in=inL);
	by prodcodeid;
	if inRx;
run;

proc sort data = rx_release; by patid issuedate; run;

proc sort data = output.ThirtyDayIntervals_&cohort_label
                 (rename=(interval_window_start = issuedate))
          out  = int_sorted_release;
	by patid issuedate;
run;

data output.IntervalRelease_&cohort_label;
	merge rx_release(in=inRx)
	      int_sorted_release(in=inInt);
	by patid issuedate;
	retain last_release;

	if inRx  then last_release = release_pattern;
	if inInt then do;
		interval_window_start   = issuedate;
		release_pattern_current = last_release;
		output;
	end;
	drop issuedate last_release;
run;

/**************************************************************************/
/* STEP 2.2: Last coverage block starting on/before interval_window_start */
/* Joined on exposure as well as patid: BridgeCoverage_&cohort_label      */
/* (Step 0.1) now holds every episode of both drugs, so without the       */
/* exposure match a patient who later used the other drug than the one    */
/* that defines this row would incorrectly pick up that other drug's      */
/* coverage as "last treatment".                                          */
/**************************************************************************/

proc sql;
	create table output.IntervalCoverage_&cohort_label as
	select i.patid,
		   i.episode_ID,
		   i.interval_window_start,
		   i.interval_window_end,
		   max(b.bridged_coverage_start) as last_coverage_period_start format=date9.,
		   max(b.bridged_coverage_end)   as last_coverage_period_end   format=date9.
	from output.ThirtyDayIntervals_&cohort_label i
		 left join output.BridgeCoverage_&cohort_label b
			on i.patid = b.patid
			and i.exposure = b.exposure
			and b.bridged_coverage_start <= i.interval_window_start
	group by i.patid, i.episode_ID, i.interval_window_start, i.interval_window_end
	order by i.patid, i.episode_ID, i.interval_window_start;
quit;

/**************************************************************************/
/* STEP 2.2b: Attach the time-varying dose (Step 2.1) and release pattern */
/* (Step 2.1b) to each interval. Keyed on (patid, episode_ID,             */
/* interval_window_start) - not just (patid, interval_window_start) -    */
/* since a patient can now have more than one episode's worth of          */
/* intervals in play, mirroring tamsulosin/7_1's equivalent step.         */
/**************************************************************************/

proc sort data = output.IntervalCoverage_&cohort_label; by patid episode_ID interval_window_start; run;

proc sort data = output.IntervalDose_&cohort_label (keep = patid episode_ID interval_window_start mg_value_current)
          out  = IntervalDose_sorted;
	by patid episode_ID interval_window_start;
run;

proc sort data = output.IntervalRelease_&cohort_label (keep = patid episode_ID interval_window_start release_pattern_current)
          out  = IntervalRelease_sorted;
	by patid episode_ID interval_window_start;
run;

data output.IntervalCoverage_&cohort_label;
	merge output.IntervalCoverage_&cohort_label (in=inC)
	      IntervalDose_sorted                    (in=inD)
	      IntervalRelease_sorted                 (in=inR);
	by patid episode_ID interval_window_start;
	if inC;
run;

/**************************************************************************/
/* STEP 2.3: Classify recency (Current/Recent/Past) and flag aSAH        */
/*                                                                          */
/* Now computed per episode-row for whichever drug that episode is for -  */
/* i.e. also for comparator episodes, not just the index drug's - so the  */
/* R side (7_3_0) can cross this with the drug flag into a 6-level         */
/* recency factor. See header comment (point 3).                          */
/*                                                                          */
/* Metformin protocol definition (different cutoff from tamsulosin):      */
/*   Current = at least 1 day overlap with a treatment episode            */
/*   Recent  = most recent episode ended <= 3 months (90 days) before     */
/*             the start of this interval                                 */
/*   Past    = most recent episode ended > 90 days before this interval  */
/* (tamsulosin/7_1 uses a single 120-day cutoff; this reuses that exact    */
/* Current/Recent/Past structure, just changing the cutoff to 90 days     */
/* per the metformin protocol.)                                           */
/*                                                                          */
/* output.&cohort_label._episodes_fu (built in Step 1.1) is one row per    */
/* treatment episode, so the merge below is keyed on patid AND episode_ID  */
/* - not patid alone - to avoid a many-to-many merge for patients with     */
/* more than one episode.                                                  */
/**************************************************************************/

proc sort data = output.IntervalCoverage_&cohort_label; by patid episode_ID; run;

proc sort data = output.&cohort_label._episodes_fu
          out  = fu_keep (keep = patid episode_ID index_exposure index_date end_of_fu aSAH_apc_dt dose_category duration_category);
by patid episode_ID;
run;

data output.&cohort_label._ot_all;
	merge output.IntervalCoverage_&cohort_label(in=inI)
	      fu_keep(in=inO);
	by patid episode_ID;
	if inI and inO;

	if not missing(last_coverage_period_start) then do;
		days_since_last_treatment = interval_window_start - last_coverage_period_end;
		if days_since_last_treatment <= 0 then treatment_recency_status = 'Current';
		else if 0 < days_since_last_treatment <= 90 then treatment_recency_status = 'Recent';
		else treatment_recency_status = 'Past';
	end;
	else do;
		treatment_recency_status = 'Never';  /* should not happen; good to check */
		days_since_last_treatment = .;
	end;

	/* aSAH flag if event falls within this 30-day window */
	if not missing(aSAH_apc_dt) and
	   aSAH_apc_dt >= interval_window_start and
	   aSAH_apc_dt <= interval_window_end then aSAH_within_interval = 1;
	else aSAH_within_interval = 0;

	fu_days = end_of_fu - index_date + 1;

	format index_date end_of_fu interval_window_start interval_window_end aSAH_apc_dt date9.;
run;

/**************************************************************************/
/* Quick summary by index exposure                                        */
/**************************************************************************/
proc sql;
	select index_exposure,
		   count(distinct patid) as n,
		   min(fu_days) as min_fu_days,
		   max(fu_days) as max_fu_days,
		   median(fu_days) as median_fu_days,
		   mean(fu_days) as mean_fu_days,
		   sum(aSAH_within_interval) as n_asah_cases
	from output.&cohort_label._ot_all
	group by index_exposure;
quit;

proc sql;
	select treatment_recency_status,
		   count(*) as n_intervals,
		   sum(aSAH_within_interval) as n_asah_cases
	from output.&cohort_label._ot_all
	group by treatment_recency_status;
quit;

proc sort data = output.&cohort_label._ot_all;
by patid;
run;

/**************************************************************************/
/* STEP 3: Time-varying BMI, smoking, and age for the on-treatment        */
/* interval dataset. Folded in here rather than a separate file, to keep */
/* the file count down (tamsulosin's 7_2 was a standalone script that    */
/* did exactly this against 7_1's output).                                */
/**************************************************************************/

proc sort data = output.bmi_all out = bmi_dedup;
	by patid obsdate descending BMI_final;
run;

data bmi_dedup;
	set bmi_dedup;
	by patid obsdate;
	if first.obsdate;
run;

proc sql;
	create table work.bmi_latest_ot as
	select o.patid,
	       o.interval_window_start,
	       max(b.obsdate) as bmi_recent_date format=date9.
	from output.&cohort_label._ot_all as o
	     left join bmi_dedup as b
	       on o.patid = b.patid
	      and b.obsdate <= o.interval_window_start
	group by o.patid, o.interval_window_start;
quit;

proc sql;
	create table output.&cohort_label._ot_bmi as
	select o.*,
	       b.BMI_final as bmi_value
	from output.&cohort_label._ot_all as o
	     left join work.bmi_latest_ot as l
	       on o.patid = l.patid
	      and o.interval_window_start = l.interval_window_start
	     left join bmi_dedup as b
	       on l.patid = b.patid
	      and l.bmi_recent_date = b.obsdate
	order by o.patid, o.interval_window_start;
quit;

proc sort data = output.smoking_all out = smk_dedup;
	by patid obsdate descending smk_cur;
run;

data smk_dedup;
	set smk_dedup;
	by patid obsdate;
	if first.obsdate;
run;

proc sql;
	create table work.smk_latest_ot as
	select o.patid,
	       o.interval_window_start,
	       max(b.obsdate) as smk_recent_date format=date9.
	from output.&cohort_label._ot_bmi as o
	     left join smk_dedup as b
	       on o.patid = b.patid
	      and b.obsdate <= o.interval_window_start
	group by o.patid, o.interval_window_start;
quit;

proc sql;
	create table output.&cohort_label._ot_bmi_smk as
	select o.*,
	       b.smk_cur,
	       b.smk_ex,
	       b.smk_non
	from output.&cohort_label._ot_bmi as o
	     left join work.smk_latest_ot as l
	       on o.patid = l.patid
	      and o.interval_window_start = l.interval_window_start
	     left join smk_dedup as b
	       on l.patid = b.patid
	      and l.smk_recent_date = b.obsdate
	order by o.patid, o.interval_window_start;
quit;

data output.&cohort_label._ot_bmi_smk;
	set output.&cohort_label._ot_bmi_smk;
	if missing(smk_cur) then smk_cur = 0;
	if missing(smk_ex)  then smk_ex  = 0;
	if missing(smk_non) then smk_non = 0;
	if smk_cur = 0 and smk_ex = 0 and smk_non = 0 then smk_unknown = 1;
	else smk_unknown = 0;
run;

proc sql;
create table output.&cohort_label._ot_bmi_smk_age as
select ot.*, year(ot.interval_window_start) - bc.yob as age_at_interval_start,
       bc.gender
from output.&cohort_label._ot_bmi_smk as ot
left join output.t2dm_cohort as bc
on ot.patid = bc.patid;
quit;
