/************************************************/
** 	the Treat-PRYSM project 					**
** 	by Sage Wyatt, Jos Kanning, & Shahab Abtahi **
**	Drug - Tamsulosin							**
**												**
**	File 3_5: Comedication covariates (BPH PP)	**
/************************************************/;

libname rawdata "F:\Users\Wyatt003\BPH_nephrolithiasis\SAS";
libname output "F:\Users\Wyatt003\BPH_nephrolithiasis\Output";
libname codelist "F:\Users\Wyatt003\BPH_nephrolithiasis\3_MagdasCodes";

options fullstimer; 

****************************

* Merge disorders variables with medications variables;

proc sql;
create table output.bph_pp_ps_dismeds as
select p.*, m.antihypertensives, m.lipid_lowering, m.anticoagulants, m.nsaids, m.opioids, m.antiemetics, m.antidiabetics, m.snri, m.dutasteride, m.solifenacin, m.tadalafil
from output.bph_pp_meds as m
inner join output.bph_pp_propscor as p
     on    m.patid  = p.patid;
quit;

* Create drug issue dataset with one row per patient and first prescription date (index date) of each patient;
proc sort data = output.all_bph_episodes;
by patid issuedate;
run;

data extractindex (keep = patid indexdate);
set output.all_bph_episodes;
by patid;
if first.patid;
run;


* keep yes when there are conflicts or more than one measurement;
proc sort data = output.smoking_all;
by patid obsdate descending smk_status;
run;

data output.smoking_all;
set output.smoking_all;
by patid obsdate;
if first.obsdate;
run;

* extract the closest smoking status to the index date;
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


* combine to make one cohort file;
proc sql;
   create table output.bph_cohort_smk as
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


* merge into bph_prop_scor file;

proc sql;
create table output.bph_pp_ps_smk as
select p.*, b.smk_status
from output.bph_cohort_smk as b
inner join output.bph_pp_ps_dismeds as p on p.patid = b.patid;
quit;




* keep highest BMI when there are conflicts or more than one measurement;
proc sort data = output.bmi_all;
by patid obsdate descending bmi_final;
run;

data output.bmi_all;
set output.bmi_all;
by patid obsdate;
if first.obsdate;
run;


* extract the closest bmi value to the index date;
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


* combine to make one cohort file;
proc sql;
   create table output.bph_cohort_bmi as
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


* merge into bph_prop_scor file;

proc sql;
create table output.bph_pp_ps_bmismk as
select p.*, b.bmi_value
from output.bph_cohort_bmi as b
inner join output.bph_pp_ps_smk as p on p.patid = b.patid;
quit;

***************************
***** SANITY CHECKING *****
***************************;

title "acidosis";
proc freq data = output.bph_pp_ps_bmismk;
tables acidosis;
run;

title "aids";
proc freq data = output.bph_pp_ps_bmismk;
tables aids;
run;

title "alcohol";
proc freq data = output.bph_pp_ps_bmismk;
tables alcohol;
run;

title "alzheimers disease";
proc freq data = output.bph_pp_ps_bmismk;
tables alzheimers_disease;
run;

title "cancer";
proc freq data = output.bph_pp_ps_bmismk;
tables cancer;
run;

title "copd";
proc freq data = output.bph_pp_ps_bmismk;
tables copd;
run;

title "stroke";
proc freq data = output.bph_pp_ps_bmismk;
tables stroke;
run;

title "rheumatological disease";
proc freq data = output.bph_pp_ps_bmismk;
tables rheum_disease;
run;

title "diabetes";
proc freq data = output.bph_pp_ps_bmismk;
tables diabetes;
run;

title "heart failure";
proc freq data = output.bph_pp_ps_bmismk;
tables heart_failure;
run;

title "hypercholesterolaemia";
proc freq data = output.bph_pp_ps_bmismk;
tables hypercholesterolaemia;
run;

title "hypertension";
proc freq data = output.bph_pp_ps_bmismk;
tables hypertension;
run;

title "liver failure";
proc freq data = output.bph_pp_ps_bmismk;
tables liver_failure;
run;

title "nephrolithiasis";
proc freq data = output.bph_pp_ps_bmismk;
tables nephrolithiasis;
run;

title "acidosis";
proc freq data = output.bph_pp_ps_bmismk;
tables paralysis;
run;

title "peptic ulcer disease";
proc freq data = output.bph_pp_ps_bmismk;
tables peptic_ulcer;
run;

title "peripheral vascular disease";
proc freq data = output.bph_pp_ps_bmismk;
tables pvd;
run;

title "chronic kidney disease";
proc freq data = output.bph_pp_ps_bmismk;
tables ckd;
run;

title "antihypertensives";
proc freq data = output.bph_pp_ps_bmismk;
tables antihypertensives;
run;

title "lipid-lowering medications";
proc freq data = output.bph_pp_ps_bmismk;
tables lipid_lowering;
run;

title "anticoagulants";
proc freq data = output.bph_pp_ps_bmismk;
tables anticoagulants;
run;

title "nsaids";
proc freq data = output.bph_pp_ps_bmismk;
tables nsaids;
run;

title "opioids";
proc freq data = output.bph_pp_ps_bmismk;
tables opioids;
run;

title "antiemetics";
proc freq data = output.bph_pp_ps_bmismk;
tables antiemetics;
run;

title "antidiabetics";
proc freq data = output.bph_pp_ps_bmismk;
tables antidiabetics;
run;

title "snri";
proc freq data = output.bph_pp_ps_bmismk;
tables snri;
run;

title "dutasteride";
proc freq data = output.bph_pp_ps_bmismk;
tables dutasteride;
run;

title "solifenacin";
proc freq data = output.bph_pp_ps_bmismk;
tables solifenacin;
run;

title "tadalafil";
proc freq data = output.bph_pp_ps_bmismk;
tables tadalafil;
run;

title "smoking";
proc freq data = output.bph_pp_ps_bmismk;
tables smk_status;
run;

 
