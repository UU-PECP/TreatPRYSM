
/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	File 3_3_0: Covariates - SHARED BODY        **
**	Modelled on tamsulosin/3_1 (comorbidities), **
**	3_4 (comedications), and 3_5 (combine with  **
**	smoking/BMI). %include this from a per-     **
**	cohort driver that has already set          **
**	&cohort_label. Do not run this file         **
**	directly. Assumes 2_1/2_2 and 3_1 (smoking) **
**	/3_2 (BMI) have already been run.            **
**												**
**	NOTE: the comorbidity codelists referenced  **
**	below (codelist.acidosis, codelist.aids,    **
**	etc.) and the comedication ATC patterns are **
**	NOT tamsulosin-specific - they are the same **
**	generic, reusable definitions the team      **
**	already maintains and uses across studies.  **
**	Two changes from the tamsulosin BPH list:   **
**	  - "nephrolith" dropped (BPH/NL-specific,  **
**	    not a metformin protocol covariate)     **
**	  - "sex" (gender) added as a covariate,    **
**	    since unlike the BPH cohort this study  **
**	    includes both sexes                     **
**	Also dropped from comedications: dutasteride**
**	/solifenacin/tadalafil (BPH-treatment       **
**	specific, not relevant to T2DM/metformin).  **
/************************************************/;

libname rawdata "F:\Users\Wyatt003\Metformin\Raw_Data";
libname output "F:\Users\Wyatt003\Metformin\Output";
libname codelist "F:\Users\Wyatt003\Metformin\Disorder_Codes"; /* shared team codelist library - same as tamsulosin */

options fullstimer;

/**************************************************************************/
/* STEP 1: Restrict raw drugissue records to this cohort's patients       */
/* (comedication ATC lookups in Step 3 need this).                        */
/**************************************************************************/

proc sql;
create table output.&cohort_label._drugs_all as
select patid, issuedate, prodcodeid
from rawdata.drugissue_1
where patid in (select patid from output.all_&cohort_label._episodes)
outer union corr
select patid, issuedate, prodcodeid
from rawdata.drugissue_2
where patid in (select patid from output.all_&cohort_label._episodes)
outer union corr
select patid, issuedate, prodcodeid
from rawdata.drugissue_3
where patid in (select patid from output.all_&cohort_label._episodes)
outer union corr
select patid, issuedate, prodcodeid
from rawdata.drugissue_4
where patid in (select patid from output.all_&cohort_label._episodes);
quit;

/**************************************************************************/
/* STEP 2: Comorbidities - as of index_date (ever before/on index)        */
/**************************************************************************/

%macro initialize_ps_table;
proc sql;
	create table indexdate as
	select patid,
		   min(issuedate) as index_date format = ddmmyy10.
	from output.all_&cohort_label._episodes
	group by patid;
quit;

proc sql;
	create table output.&cohort_label._propscor as
	select b.*,
		   i.index_date
	from output.t2dm_cohort AS b
	inner join indexdate as i
	on b.patid = i.patid
	where index_date is not null;
quit;
%mend initialize_ps_table;

%macro create_disorder_cohort(codelist_table, cohort_table);
    proc sql;
        CREATE TABLE &cohort_table AS
        SELECT DISTINCT
            cli.patid, MIN(cli.obsdate) AS obsdate format=ddmmyy10.
        FROM
            output.clinical AS cli
        INNER JOIN
            &codelist_table AS cl
            ON cli.medcodeid = cl.medcode
        GROUP BY cli.patid;
    quit;
%mend create_disorder_cohort;

%macro join_disorder_cohort(cohort_table, flag_column);
    proc sql;
        create table output.&cohort_label._propscor as
        select lpp.*,
               CASE WHEN confounder.obsdate > lpp.index_date OR confounder.obsdate IS NULL THEN 0 ELSE 1 END AS &flag_column
        from output.&cohort_label._propscor as lpp
        left outer join &cohort_table as confounder ON lpp.patid = confounder.patid;
    quit;
%mend join_disorder_cohort;

%macro process_disorders;
    %initialize_ps_table;

    %macro process_disorder(codelist_table, cohort_table, flag_column);
        %create_disorder_cohort(&codelist_table, &cohort_table);
        %join_disorder_cohort(&cohort_table, &flag_column);
    %mend process_disorder;

    data disorders;
        set disorders;
        call execute(cats('%process_disorder(', codelist_table, ',', cohort_table, ',', flag_column, ');'));
    run;
%mend process_disorders;

data disorders;
    infile datalines delimiter=',';
    input codelist_table : $32. cohort_table : $32. flag_column : $32.;
    datalines;
	codelist.acidosis, output.acidosis_cohort, acidosis
	codelist.aids, output.aids_cohort, aids
	codelist.alcohol, output.alcohol_cohort, alcohol
	codelist.alzheimers_disease, output.alzheimers_disease_cohort, alzheimers_disease
	codelist.cancer, output.cancer_cohort, cancer
	codelist.cirrhosis, output.cirrhosis_cohort, cirrhosis
	codelist.copd, output.copd_cohort, copd
	codelist.stroke, output.stroke_cohort, stroke
	codelist.rheum_disease, output.rheum_cohort, rheum_disease
	codelist.heart_failure, output.heart_failure_cohort, heart_failure
	codelist.hypercholesterolaemia, output.hypercholesterolaemia_cohort, hypercholesterolaemia
	codelist.hypertension, output.hypertension_cohort, hypertension
	codelist.paralysis, output.paralysis_cohort, paralysis
	codelist.peptic_ulcer, output.peptic_ulcer_cohort, peptic_ulcer
	codelist.pvd, output.pvd_cohort, pvd
	codelist.ckd, output.ckd_cohort, ckd
;
run;

%process_disorders;

proc sql;
select count(distinct patid) as "File 3_3_0 - after comorbidities"n
from output.&cohort_label._propscor;
quit;

/**************************************************************************/
/* STEP 3: Comedications - ever before/on index_date, generic ATC-based  */
/* (same universal ATC prefixes as tamsulosin/3_4 - not drug-specific)   */
/**************************************************************************/

%macro create_med_cohort(codelist_table, cohort_table, atcpattern);
proc sql;
	CREATE TABLE &codelist_table AS
	SELECT *
	FROM rawdata.product_aurum_atc
	WHERE ATC LIKE "&atcpattern";
quit;

proc sql;
	CREATE TABLE &cohort_table AS
	SELECT r.patid,
		   min(r.issuedate) as obsdate format=ddmmyy10.
	FROM output.&cohort_label._drugs_all as r
		inner join &codelist_table as c
			on strip(c.prodcodeid) = strip(r.prodcodeid)
	group by r.patid;
quit;
%mend create_med_cohort;

%macro join_med_cohort(cohort_table, flag_column);
    proc sql;
        create table output.&cohort_label._meds as
        select lpp.*,
               CASE WHEN confounder.obsdate > lpp.index_date OR confounder.obsdate IS NULL
			        THEN 0 ELSE 1 END AS &flag_column
        from output.&cohort_label._meds as lpp
        left outer join &cohort_table as confounder ON lpp.patid = confounder.patid;
    quit;
%mend join_med_cohort;

%macro initialize_meds_table;
proc sql;
	create table output.&cohort_label._meds as
	select b.*,
		   i.index_date
	from output.t2dm_cohort AS b
	inner join indexdate as i
	on b.patid = i.patid
	where index_date is not null;
quit;
%mend initialize_meds_table;

%macro process_medications;
    %initialize_meds_table;

    %macro process_medication(codelist_table, cohort_table, atcpattern, flag_column);
        %create_med_cohort(&codelist_table, &cohort_table, &atcpattern);
        %join_med_cohort(&cohort_table, &flag_column);
    %mend process_medication;

    data medications;
        set medications;
        call execute(cats('%process_medication(',
                          codelist_table, ',',
                          cohort_table, ',',
                          atcpattern, ',',
                          flag_column, ');'));
    run;
%mend process_medications;

data medications;
    infile datalines delimiter='|' dsd;
    input codelist_table : $32. cohort_table : $32. atcpattern : $32. flag_column : $32.;
    datalines;
codelist.antihypertensives|output.antihypertensives_cohort|C02%|antihypertensives
codelist.lipid_lowering|output.lipid_lowering_cohort|C10%|lipid_lowering
codelist.anticoagulants|output.anticoagulants_cohort|B01A%|anticoagulants
codelist.nsaids|output.nsaids_cohort|M01A%|nsaids
codelist.opioids|output.opioids_cohort|N02A%|opioids
codelist.desuvenlafaxine|output_desuve_cohort|N06AX23|desuvenlafaxine
codelist.duloxetine|output_duloxe_cohort|N06AX21|duloxetine
codelist.levomilnacipran|output_levomi_cohort|N06AX28|levomilnacipran
codelist.milnacipran|output_milnac_cohort|N06AX17|milnacipran
codelist.venlafaxine|output_venlaf_cohort|N06AX16|venlafaxine
codelist.antiemetics|output.antiemetics_cohort|A04A%|antiemetics
;
run;

%process_medications;

data output.&cohort_label._meds;
set output.&cohort_label._meds;
if desuvenlafaxine = 1 or duloxetine = 1 or levomilnacipran = 1 or milnacipran = 1 or venlafaxine = 1 then snri = 1;
else snri = 0;
run;

data output.&cohort_label._meds;
set output.&cohort_label._meds (drop = desuvenlafaxine duloxetine levomilnacipran milnacipran venlafaxine);
run;

/**************************************************************************/
/* STEP 4: Merge comorbidities + comedications + smoking + BMI + imd      */
/**************************************************************************/

proc sql;
create table output.&cohort_label._ps_dismeds as
select p.*, m.antihypertensives, m.lipid_lowering, m.anticoagulants, m.nsaids, m.opioids, m.antiemetics, m.antidiabetics, m.snri
from output.&cohort_label._meds as m
inner join output.&cohort_label._propscor as p
     on    m.patid  = p.patid;
quit;

proc sort data = output.all_&cohort_label._episodes;
by patid issuedate;
run;

data extractindex (keep = patid indexdate);
set output.all_&cohort_label._episodes;
by patid;
if first.patid;
run;

* smoking - closest status to index date;
proc sort data = output.smoking_all;
by patid obsdate descending smk_status;
run;

data output.smoking_all;
set output.smoking_all;
by patid obsdate;
if first.obsdate;
run;

proc sql;
   create table work.smk_latest_date as
   select  a.patid,
   		   a.indexdate,
           max(b.obsdate)  as smk_recent_date format = ddmmyy10.
   from    extractindex  as a
   left join
           output.smoking_all                 as b
     on    a.patid  = b.patid
    and    b.obsdate <= a.indexdate
   group by a.patid,
            a.indexdate;
quit;

proc sql;
   create table output.&cohort_label._cohort_smk as
   select  p.*
         , b.smk_status
   from   extractindex  as p
   left join work.smk_latest_date        as l
          on  p.patid       = l.patid
          and p.indexdate  = l.indexdate
   left join output.smoking_all              as b
          on  l.patid          = b.patid
          and l.smk_recent_date = b.obsdate
   order by p.patid;
quit;

proc sql;
create table output.&cohort_label._ps_smk as
select p.*, b.smk_status
from output.&cohort_label._cohort_smk as b
inner join output.&cohort_label._ps_dismeds as p on p.patid = b.patid;
quit;

* BMI - closest value to index date, highest if tied same day;
proc sort data = output.bmi_all;
by patid obsdate descending bmi_final;
run;

data output.bmi_all;
set output.bmi_all;
by patid obsdate;
if first.obsdate;
run;

proc sql;
   create table work.bmi_latest_date as
   select  a.patid,
   		   a.indexdate,
           max(b.obsdate)  as bmi_recent_date format = ddmmyy10.
   from    extractindex  as a
   left join
           output.bmi_all                 as b
     on    a.patid  = b.patid
    and    b.obsdate <= a.indexdate
   group by a.patid,
            a.indexdate;
quit;

proc sql;
   create table output.&cohort_label._cohort_bmi as
   select  p.*
         , b.bmi_final        as bmi_value
   from   extractindex  as p
   left join work.bmi_latest_date        as l
          on  p.patid       = l.patid
          and p.indexdate  = l.indexdate
   left join output.bmi_all             as b
          on  l.patid          = b.patid
          and l.bmi_recent_date = b.obsdate
   order by p.patid;
quit;

proc sql;
create table output.&cohort_label._ps_final as
select p.*, b.bmi_value
from output.&cohort_label._cohort_bmi as b
inner join output.&cohort_label._ps_smk as p on p.patid = b.patid;
quit;

* incorporate LSOA data;

data rawdata.hes_lsoa;
	infile "F:\Users\Wyatt003\HES APC-LSOA linkage files\Type_2 25_006098\Type_2 25_006098\Aurum_linked\Final\patient_2019_imd_25_006098.txt" dsd dlm='09'x firstobs=2 truncover;
	length patid $19 pracid $5 imd 8;
	input patid :$19. pracid :$5. imd;
run;

proc sql;
create table output.&cohort_label._ps_final as
select a.*, b.imd
from output.&cohort_label._ps_final as a
left join rawdata.hes_lsoa as b on a.patid = b.patid;
quit;

***************************
***** SANITY CHECKING *****
***************************;

title "Covariate flags - metformin &cohort_label per-protocol propensity score set";
proc freq data = output.&cohort_label._ps_final;
tables acidosis aids alcohol alzheimers_disease cancer cirrhosis copd stroke
       rheum_disease diabetes heart_failure hypercholesterolaemia hypertension
       paralysis peptic_ulcer pvd ckd gender
       antihypertensives lipid_lowering anticoagulants nsaids opioids
       antiemetics antidiabetics snri
       smk_status / missing;
run;
title;

proc means data = output.&cohort_label._ps_final n nmiss mean std min max;
var bmi_value;
run;
