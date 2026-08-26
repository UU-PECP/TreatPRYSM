
/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
**	Drug - Tamsulosin							**
**												**
**	File 3_4: Comedication covariates (BPH PP)	**
/************************************************/;

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes";

options fullstimer; 

****;


proc sql; 
create table output.drugs_1 as
select patid, issuedate, prodcodeid
from rawdata.drugissue_1
where patid in (select patid from output.all_bph_episodes);
quit;

proc sql; 
create table output.drugs_2 as
select patid, issuedate, prodcodeid
from rawdata.drugissue_2
where patid in (select patid from output.all_bph_episodes);
quit;

proc sql; 
create table output.drugs_3 as
select patid, issuedate, prodcodeid
from rawdata.drugissue_3
where patid in (select patid from output.all_bph_episodes);
quit;

proc sql; 
create table output.drugs_4 as
select patid, issuedate, prodcodeid
from rawdata.drugissue_4
where patid in (select patid from output.all_bph_episodes);
quit;


data output.drugs;
	set output.drugs_1
	output.drugs_2
	output.drugs_3
	output.drugs_4;
run;



/**************************************************************************/
/* Macro: initialize main table with index_date attached                 */
/**************************************************************************/
%macro initialize_main_table;

proc sql;
	create table indexdate as
	select patid,
		   min(issuedate) as index_date format = ddmmyy10.
	from output.all_bph_episodes
	group by patid;
quit;


proc sql;
	create table output.bph_pp_meds as
	select b.*,
		   i.index_date
	from output.linked_bph_cohort AS b 
	inner join indexdate as i 
	on b.patid = i.patid
	where index_date is not null;
quit;

%mend initialize_main_table;


/**************************************************************************/
/* Macro: build an ATC-based codelist, then find first prescription date  */
/* per patient for that drug class                                        */
/**************************************************************************/
%macro create_cohort(codelist_table, cohort_table, atcpattern);
   
proc sql;
	CREATE TABLE &codelist_table AS
	SELECT *
	FROM rawdata.product_aurum_atc 
	WHERE ATC LIKE "&atcpattern";  /* pattern (incl. any % wildcard) supplied per row */
quit;


proc sql;
	CREATE TABLE &cohort_table AS
	SELECT r.patid, 
		   min(r.issuedate) as obsdate format=ddmmyy10.  
	FROM output.drugs as r   
		inner join &codelist_table as c 
			on strip(c.prodcodeid) = strip(r.prodcodeid)
	WHERE r.issuedate <= MDY(3,31,2025)  
	group by r.patid;
quit;

%mend create_cohort;


/**************************************************************************/
/* Macro: join a class cohort back to main table, add a 0/1 flag          */
/* Flag = 1 if the class was ever prescribed on or before index_date      */
/**************************************************************************/
%macro join_cohort(cohort_table, flag_column);
    proc sql;
        create table output.bph_pp_meds as
        select lpp.*,
               CASE WHEN confounder.obsdate > lpp.index_date OR confounder.obsdate IS NULL 
			        THEN 0 ELSE 1 END AS &flag_column
        from output.bph_pp_meds as lpp
        left outer join &cohort_table as confounder ON lpp.patid = confounder.patid;
    quit;
%mend join_cohort;


*#####################################################################;
*BPH PER PROTOCOL;
*#####################################################################;

/* Main macro to process all comedication classes */
%macro process_medications;
    /* Initialize the main table */
    %initialize_main_table;
    
    /* Macro to process a single medication class */
    %macro process_medication(codelist_table, cohort_table, atcpattern, flag_column);
        %create_cohort(&codelist_table, &cohort_table, &atcpattern);  /* FIXED: now passes atcpattern through */
        %join_cohort(&cohort_table, &flag_column);
    %mend process_medication;
    
    /* Loop through the medications dataset and process each class */
    data _null_;
        set medications;
        call execute(cats('%process_medication(', 
                          codelist_table, ',', 
                          cohort_table, ',', 
                          atcpattern, ',',       /* FIXED: atcpattern now included in the call */
                          flag_column, ');'));
    run;
%mend process_medications;

/* Create the medications dataset */
/* NOTE: atcpattern read as character ($32) - FIXED from original numeric read */
/* Add a trailing % in atcpattern for class-level (prefix) matches; omit for exact matches */
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
codelist.antidiabetics|output.antidiabetics_cohort|A10%|antidiabetics
codelist.dutasteride1|output.dutasteride1_cohort|G04CB02|dutasteride1
codelist.dutasteride2|output.dutasteride2_cohort|G04CA52|dutasteride2
codelist.solifenacin1|output.solifenacin1_cohort|G04BD08|solifenacin1
codelist.solifenacin2|output.solifenacin2_cohort|G04CA53|solifenacin2
codelist.tadalafil1|output.tadalafil1_cohort|C02KX52|tadalafil1
codelist.tadalafil2|output.tadalafil2_cohort|G04CB51|tadalafil2
codelist.tadalafil3|output.tadalafil3_cohort|C02KX54|tadalafil3
codelist.tadalafil4|output.tadalafil4_cohort|G04BE08|tadalafil4
codelist.tadalafil5|output.tadalafil5_cohort|G04CA54|tadalafil5
;
run;

/* Run the main macro to process all medication classes */
%process_medications(d;


data output.bph_pp_meds;
set output.bph_pp_meds ;
if desuvenlafaxine = 1 or duloxetine = 1 or levomilnacipran = 1 or milnacipran = 1 or venlafaxine then snri = 1;
else snri = 0;
run;

data output.bph_pp_meds;
set output.bph_pp_meds ;
if dutasteride1 = 1 or dutasteride2 = 1 then dutasteride = 1;
else dutasteride = 0;
run;

data output.bph_pp_meds;
set output.bph_pp_meds ;
if solifenacin1 = 1 or solifenacin2 = 1 then solifenacin = 1;
else solifenacin = 0;
run;

data output.bph_pp_meds;
set output.bph_pp_meds ;
if tadalafil1 = 1 or tadalafil2 = 1 or tadalafil3 = 1 or tadalafil4 = 1 or tadalafil5 = 1 then tadalafil = 1;
else tadalafil = 0;
run;

data output.bph_pp_meds;
set output.bph_pp_meds (drop = desuvenlafaxine duloxetine levomilnacipran milnacipran venlafaxine 
								dutasteride1 dutasteride2 
								solifenacin1 solifenacin2 
								tadalafil1 tadalafil2 tadalafil3 tadalafil4 tadalafil5) ;
run;

