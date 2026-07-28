libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes";

options fullstimer; 



*Doublecheck why some tables are called codelis, but seems to work otherwise;
/* Currently only done for the per protocol vars since I don't think we have enough cases to examine these in a time-varying manner */
/* Also, we have shown that these vars barely differ between AC/main group anyway */

*####################################;
* DEFINE MACROS ;
*#####################################;

/* Macro to initialize the main table with the initial data */
/* Creates data subset for faster process
data output.lil_cohort;
set output.bph_cohort (obs=100);
run;
*/

 */ Since we made file 3 in R, we'll have to reintroduce the index date here /*;

*/ we should figure out a way to reintroduce the file from R instead of using base_cohort;

%macro initialize_main_table;

proc sql;
	create table indexdate as
	select patid,
		   min(issuedate) as index_date format = ddmmyy10.
	from output.all_bph_episodes 
	group by patid;
quit;


proc sql;
	create table output.bph_pp_propscor as
	select b.*,
		   i.index_date
	from output.linked_bph_cohort AS b 
	left outer join indexdate as i 
	on b.patid = i.patid
	where index_date is not null;
quit;

%mend initialize_main_table;

/* Macro to create a cohort table by joining clinical data with the codelist */
%macro create_cohort(codelist_table, cohort_table);
    proc sql;
        CREATE TABLE &cohort_table AS
        SELECT DISTINCT
            cli.patid, MIN(cli.obsdate) AS obsdate format=ddmmyy10.
        FROM 
            output.clinical AS cli 
        INNER JOIN
            &codelist_table AS cl
            ON cli.medcodeid = cl.medcode
        WHERE cli.obsdate <= MDY(3,31,2025)
        GROUP BY cli.patid;
    quit;
%mend create_cohort;

/* Macro to join the cohort table back to the main table and add a flag column */
*now considered ever yes/no. may have window before index dt e.g. 3 for comedication;
%macro join_cohort(cohort_table, flag_column);
    proc sql;
        create table output.bph_pp_propscor as
        select lpp.*,
               CASE WHEN confounder.obsdate > lpp.index_date OR confounder.obsdate IS NULL THEN 0 ELSE 1 END AS &flag_column
        from output.bph_pp_propscor as lpp
        left outer join &cohort_table as confounder ON lpp.patid = confounder.patid;
    quit;
%mend join_cohort;



*#####################################################################;
*BPH PER PROTOCOL;
*#####################################################################;

/* Main macro to process all disorders */
%macro process_disorders;
    /* Initialize the main table */
    %initialize_main_table;
    
    /* Macro to process a single disorder */
    %macro process_disorder(codelist_table, cohort_table, flag_column);
        %create_cohort(&codelist_table, &cohort_table);
        %join_cohort(&cohort_table, &flag_column);
    %mend process_disorder;
    
    /* Loop through the disorders dataset and process each disorder */
    data _null_;
        set disorders;
        call execute(cats('%process_disorder(', codelist_table, ',', cohort_table, ',', flag_column, ');'));
    run;
%mend process_disorders;

/* Create the disorders dataset */
data disorders;
    infile datalines delimiter=',';
    input codelist_table : $32. cohort_table : $32. flag_column : $32.;
    datalines;
    codelist.acidosis, output.acidosis_cohort, acidosis
	codelist.aids, output.aids_cohort, aids
	codelist.alcohol, output.alcohol_cohort, alcohol
    codelist.alzheimers_disease, output.alzheimers_disease_cohort, alzheimers_disease
	codelist.cancer, output.cancer_cohort, cancer
	codelist.copd, output.copd_cohort, copd
	codelist.stroke, output.stroke_cohort, stroke
	codelist.rheum_disease, output.rheum_cohort, rheum_disease
	codelist.diabetes, output.diabetes_cohort, diabetes
	codelist.heart_failure, output.heart_failure_cohort, heart_failure
	codelist.hypercholesterolaemia, output.hypercholesterolaemia_cohort, hypercholesterolaemia
	codelist.hypertension, output.hypertension_cohort, hypertension
	codelist.liver_failure, output.liver_failure_cohort, liver_failure
	codelist.nephrolithiasis, output.nephrolith_cohort, nephrolith
	codelist.paralysis, output.paralysis_cohort, paralysis
	codelist.peptic_ulcer, output.peptic_ulcer_cohort, peptic_ulcer
	codelist.pvd, output.pvd_cohort, pvd
	codelist.ckd, output.ckd_cohort, ckd
;
run;

/* Run the main macro to process all disorders */
%process_disorders;
