
/**************************************************************************/
/*  Treat-PRYSM - Metformin and aSAH risk                                 */
/*  File 7_0: ON-TREATMENT ANALYSIS - SHARED BODY                         */
/*  Modelled on tamsulosin/7_1_tamsulosin_bph_on_treatment.sas            */
/*                                                                          */
/*  TWO DELIBERATE FIXES vs. tamsulosin/7_1, not just adaptations:        */
/*                                                                          */
/*  1) tamsulosin/7_1's Step 2.2 reads from                                */
/*     output.BridgeCoverage_IndexDrug, but no step in that file (or      */
/*     anywhere else in the tamsulosin scripts) actually builds that      */
/*     table - it's referenced but never created, so 7_1 as committed    */
/*     cannot run past Step 2.2. Its header comment says the intent was  */
/*     to reuse the AdhereR-built episodes directly as coverage blocks   */
/*     (the original amlodipine version built it by hand from raw Rx     */
/*     records - see AdditionalScripts/On_Treatment_Amlodipine_Script.sas)*/
/*     - this file actually does that: STEP 0.1 below builds it from all */
/*     of ALL_&cohort_label._episodes filtered to each patient's own      */
/*     index exposure.                                                    */
/*                                                                          */
/*  2) tamsulosin/7_1 caps end_of_fu at the FIRST episode's end date      */
/*     (episode_end) alongside censordate/aSAH. That means follow-up      */
/*     never extends past the first episode, so a patient's recency      */
/*     status can only ever be "Current" - "Recent"/"Past" become        */
/*     unreachable, which defeats the point of an on-treatment design.   */
/*     Here, end_of_fu runs to the overall censordate/aSAH/study end     */
/*     only (not truncated at episode_end), so recency can actually      */
/*     transition as a patient finishes, restarts, or switches.          */
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

libname rawdata "F:\Users\Wyatt003\Metformin\Raw_Data";
libname output "F:\Users\Wyatt003\Metformin\Output";
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
/* STEP 0.1: Determine each patient's index exposure and index date from  */
/* their FIRST episode of either drug (matches the per-protocol index    */
/* used in 4_0/5_0), then build the bridge-coverage table from ALL of    */
/* that patient's episodes of THEIR OWN index exposure (i.e. if a        */
/* patient's index drug is metformin, track their full metformin usage   */
/* history over time, including any later stop/restart, for recency -    */
/* not the comparator's usage).                                          */
/**************************************************************************/

proc sort data = output.&cohort_label._treatmentepisodes;
by patid episode_start;
run;

data patient_index;
set output.&cohort_label._treatmentepisodes;
by patid;
if first.patid;
index_date = episode_start;
index_exposure = exposure;
keep patid index_date index_exposure;
run;

proc sql;
create table output.BridgeCoverage_&cohort_label as
select e.patid,
       e.episode_ID,
       e.episode_start as bridged_coverage_start,
       e.episode_end as bridged_coverage_end
from output.&cohort_label._treatmentepisodes as e
inner join patient_index as p
on e.patid = p.patid and e.exposure = p.index_exposure;
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
/* STEP 1.1: Create end of follow-up variable (index episode's own start */
/* through overall censoring - NOT capped at the first episode's end;    */
/* see header comment).                                                   */
/**************************************************************************/

proc sort data = output.t2dm_cohort;
by patid;
run;

data output.&cohort_label._episodes_fu;
	merge output.&cohort_label._treatmentepisodes_mgqty(in=inA)
	      patient_index(in=inP)
		  output.t2dm_cohort(in=inB keep=patid censordate aSAH_apc_dt);
	by patid;
	if inA and inP and inB;

	end_of_fu = &study_end;

	if not missing(censordate) and censordate < end_of_fu then end_of_fu = censordate;
	if not missing(aSAH_apc_dt) and aSAH_apc_dt < end_of_fu then end_of_fu = aSAH_apc_dt;

	/* Only keep if valid follow-up (index_date < end_of_fu) */
	if index_date < end_of_fu;

	format index_date end_of_fu date9.;
run;

/**************************************************************************/
/* STEP 2.0: Build 30-day intervals from index_date to end_of_fu          */
/**************************************************************************/

proc sort data = output.&cohort_label._episodes_fu nodupkey out = fu_onerow;
by patid;
run;

data output.ThirtyDayIntervals_&cohort_label;
	set fu_onerow;
	by patid;

	interval_window_start = index_date;
	do while (interval_window_start <= end_of_fu);
		interval_window_end = min(interval_window_start + 29, end_of_fu);
		output;
		interval_window_start = interval_window_end + 1;
	end;

	format interval_window_start interval_window_end date9.;
run;

/**************************************************************************/
/* STEP 2.1: Carry most-recent per-Rx dose (mg_value) into each interval  */
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
/* STEP 2.2: Last coverage block starting on/before interval_window_start */
/**************************************************************************/

proc sql;
	create table output.IntervalCoverage_&cohort_label as
	select i.patid,
		   i.interval_window_start,
		   i.interval_window_end,
		   max(b.bridged_coverage_start) as last_coverage_period_start format=date9.,
		   max(b.bridged_coverage_end)   as last_coverage_period_end   format=date9.
	from output.ThirtyDayIntervals_&cohort_label i
		 left join output.BridgeCoverage_&cohort_label b
			on i.patid = b.patid
			and b.bridged_coverage_start <= i.interval_window_start
	group by i.patid, i.interval_window_start, i.interval_window_end
	order by i.patid, i.interval_window_start;
quit;

/**************************************************************************/
/* STEP 2.3: Classify recency (Current/Recent/Past) and flag aSAH        */
/*                                                                          */
/* Metformin protocol definition (different cutoff from tamsulosin):      */
/*   Current = at least 1 day overlap with a treatment episode            */
/*   Recent  = most recent episode ended <= 3 months (90 days) before     */
/*             the start of this interval                                 */
/*   Past    = most recent episode ended > 90 days before this interval  */
/* (tamsulosin/7_1 uses a single 120-day cutoff for Recent/Past; this     */
/* reuses that exact Current/Recent/Past structure, just changing the    */
/* cutoff to 90 days per the metformin protocol.)                        */
/**************************************************************************/

data output.&cohort_label._ot_all;
	merge output.IntervalCoverage_&cohort_label(in=inI)
	      output.IntervalDose_&cohort_label(in=inD keep=patid interval_window_start mg_value_current)
	      fu_onerow(in=inO keep = patid index_exposure index_date end_of_fu aSAH_apc_dt dose_category duration_category);
	by patid;
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
