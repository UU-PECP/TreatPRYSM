
/**************************************************************************/
/*  Treat-PRYSM - Tamsulosin and aSAH risk                                */
/*  File 7.1: ON-TREATMENT ANALYSIS (BPH) - censor on switch              */
/*  Adapted from Jos Kanning's amlodipine on-treatment script             */
/*                                                                          */
/*  KEY DIFFERENCE FROM JOS'S VERSION:                                     */
/*  Jos rebuilt bridged coverage in SAS (his Step 21) from AllIndexDrug.   */
/*  Our treatment episodes were built in R with AdhereR, so instead we     */
/*  import bph_treatmentepisodes.csv and use its episode.start/episode.end */
/*  directly as the coverage blocks (AdhereR already did the bridging).    */
/**************************************************************************/

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
options fullstimer;

%macro ontreatment(in =, out =);
/**************************************************************************/
/* STEP 0: Import R-generated treatment episodes                          */
/**************************************************************************/
/* AdhereR compute.treatment.episodes() output, combined across the 3     */
/* exposures via bind_rows(.id="exposure"), written by write.csv (which   */
/* adds a leading row-index column, read here as row_index and dropped).  */
/* patid read as CHARACTER ($19) per CPRD Aurum precision guidance.       */

data output.bph_treatmentepisodes;
	infile "F:\Users\Wyatt003\BPH_nephrolithiasis\Output\bph_treatmentepisodes.csv"
		dsd dlm=',' firstobs=2 truncover;
	length exposure 8 patid $19 episode_ID 8
	       episode_start 8 end_episode_gap_days 8 episode_duration 8 episode_end 8;
	input exposure patid :$19. episode_ID
	      episode_start :yymmdd10. end_episode_gap_days episode_duration episode_end :yymmdd10.;
	format episode_start episode_end date9.;
run;

/**************************************************************************/
/* STEP 19: Determine earliest switch date to a different exposure         */
/**************************************************************************/

/* Map each patient to their index exposure (earliest episode) */
proc sql;
	create table output.IndexDrugs as
	select patid, exposure as index_exposure
	from output.bph_treatmentepisodes
	group by patid
	having episode_start = min(episode_start);
quit;

/* Earliest prescription of a DIFFERENT exposure = switch_date */
proc sql;
	create table output.SwitchDates as
	select r.patid,
		   min(r.issuedate) as switch_date format=date9.
	from &in r
		 inner join output.IndexDrugs i
		 on r.patid = i.patid
	where r.exposure ne i.index_exposure
	group by r.patid;
quit;


/**************************************************************************/
/* STEP 20: Build on-treatment follow-up dataset, censor at switch         */
/**************************************************************************/
/* Uses the earliest episode per patient for index_date/index_exposure,    */
/* your File-1 censordate (already the min of regend/death/lcd/studyend),   */
/* aSAH_gp_dt, and the switch date.                                        */

/* one row per patient: their index (earliest) episode */
proc sql;
	create table output.FirstEpisode as
	select *
	from output.bph_treatmentepisodes
	group by patid
	having episode_start = min(episode_start);
quit;

proc sort data = output.FirstEpisode; by patid; run;
proc sort data = output.bph_cohort out = base_cohort_ot; by patid; run;
proc sort data = output.SwitchDates; by patid; run;

data output.OverallFollowup_OnT;
	merge output.FirstEpisode(in=inE)
		  base_cohort_ot(in=inB keep=patid censordate aSAH_gp_dt) 
		  output.SwitchDates(in=inS);
	by patid;
	if inE and inB;

	index_date     = episode_start;
	index_exposure = exposure;
	end_of_fu      = '31MAR2025'd;

	/* censordate already folds in reg end / death / lcd / study end from File 1 */
	if not missing(censordate)  and censordate  < end_of_fu then end_of_fu = censordate;
	if not missing(aSAH_gp_dt)  and aSAH_gp_dt  < end_of_fu then end_of_fu = aSAH_gp_dt;

	/* additional on-treatment censoring at switch, if earlier */
	if inS and not missing(switch_date) and switch_date < end_of_fu then end_of_fu = switch_date;

	/* keep only valid follow-up */
	if index_date < end_of_fu;

	format index_date end_of_fu date9.;
run;


/**************************************************************************/
/* STEP 21: Coverage blocks for the index drug (from AdhereR episodes)     */
/**************************************************************************/
/* Jos rebuilt bridging here; AdhereR already did it. We just take each     */
/* patient's episodes of their INDEX exposure as the coverage blocks.      */

proc sql;
	create table output.BridgeCoverage_IndexDrug as
	select e.patid,
		   e.episode_start as bridged_coverage_start format=date9.,
		   e.episode_end   as bridged_coverage_end   format=date9.
	from output.bph_treatmentepisodes e
		 inner join output.IndexDrugs i
		 on e.patid = i.patid
	where e.exposure = i.index_exposure
	order by e.patid, e.episode_start;
quit;


/**************************************************************************/
/* STEP 22.0: Build 30-day intervals from index_date to end_of_fu          */
/**************************************************************************/
data output.ThirtyDayIntervals_OnT;
	set output.OverallFollowup_OnT;
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
/* STEP 22.1: Carry most-recent per-Rx dose (mg_value) into each interval  */
/**************************************************************************/
/* mg_value is per-prescription in Rx_bph_PostStart; propagate the most    */
/* recent value forward across intervals (time-varying dose).              */

proc sort data = &in
          out  = rx_sorted(keep=patid issuedate mg_value);
	by patid issuedate;
run;

proc sort data = output.ThirtyDayIntervals_OnT
                 (rename=(interval_window_start = issuedate))
          out  = int_sorted;
	by patid issuedate;
run;

data output.IntervalDose;
	merge rx_sorted(in=inRx)
	      int_sorted(in=inInt);
	by patid issuedate;
	retain last_dose;

	if inRx  then last_dose = mg_value;          /* update on Rx rows */
	if inInt then do;                            /* output interval rows */
		interval_window_start   = issuedate;     /* restore original name */
		mg_value_current        = last_dose;     /* most-recent dose */
		output;
	end;
	drop issuedate last_dose;
run;


/**************************************************************************/
/* STEP 22.2: Last coverage block starting on/before interval_window_start */
/**************************************************************************/
proc sql;
	create table output.IntervalCoverage_OT as
	select i.patid,
		   i.interval_window_start,
		   i.interval_window_end,
		   max(b.bridged_coverage_start) as last_coverage_period_start format=date9.,
		   max(b.bridged_coverage_end)   as last_coverage_period_end   format=date9.
	from output.ThirtyDayIntervals_OnT i
		 left join output.BridgeCoverage_IndexDrug b
			on i.patid = b.patid
			and b.bridged_coverage_start <= i.interval_window_start
	group by i.patid, i.interval_window_start, i.interval_window_end
	order by i.patid, i.interval_window_start;
quit;


/**************************************************************************/
/* STEP 22.3: Classify recency (Current/Recent/Past), flag aSAH, TV age    */
/**************************************************************************/
proc sort data = output.IntervalCoverage_OT; by patid; run;

data &out;
	merge output.IntervalCoverage_OT(in=inI)
	      output.OverallFollowup_OnT(in=inO
			keep = patid index_exposure index_date end_of_fu aSAH_gp_dt);
	by patid;
	if inI and inO;

	if not missing(last_coverage_period_start) then do;
		days_since_last_treatment = interval_window_start - last_coverage_period_end;
		if days_since_last_treatment <= 0 then treatment_recency_status = 'Current';
		else if 0 < days_since_last_treatment <= 120 then treatment_recency_status = 'Recent';
		else treatment_recency_status = 'Past';
	end;
	else do;
		treatment_recency_status = 'Never';  /* should not happen; good to check */
		days_since_last_treatment = .;
	end;

	if treatment_recency_status = 'Current' then
		days_since_bridge_start = interval_window_start - last_coverage_period_start + 1;
	else
		days_since_bridge_start = .;

	/* aSAH flag if event falls within this 30-day window */
	if not missing(aSAH_gp_dt) and
	   aSAH_gp_dt >= interval_window_start and
	   aSAH_gp_dt <= interval_window_end then aSAH_within_interval = 1;
	else aSAH_within_interval = 0;

	fu_days = end_of_fu - index_date + 1;

	format index_date end_of_fu interval_window_start interval_window_end aSAH_gp_dt date9.;
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
	from &out
	group by index_exposure;
quit;

%mend;


%ontreatment(in = output.bphdrugatc_1, out = output.bph_ot_1);
proc datasets library = work kill nolist;
run;
quit;

%ontreatment(in = output.bphdrugatc_2, out = output.bph_ot_2);
proc datasets library = work kill nolist;
run;
quit;

%ontreatment(in = output.bphdrugatc_3, out = output.bph_ot_3);
proc datasets library = work kill nolist;
run;
quit;

%ontreatment(in = output.bphdrugatc_4, out = output.bph_ot_4);
proc datasets library = work kill nolist;
run;
quit;

data output.bph_ot_all;
set output.bph_ot_1 output.bph_ot_2 output.bph_ot_3 output.bph_ot_4;
run;


proc sort data = output.bph_ot_all;
by patid;
run;

data output.test_ot;
set output.bph_ot_all (obs = 100000);
run;
