/* 	Create Smoking Variable
	Originally by Magdalena Gamba, September 28, 2021
	Reused unchanged for the metformin project (patid-level GP-derived
	smoking status - not drug or cohort specific). Shared by both the
	SU and SGLT2i cohorts; the combine step (3_3) merges this in per
	cohort using each cohort's own index date. */

* Set Libraries;
libname data       "F:\Users\Wyatt003\metformin\SAS";
libname medcode    "F:\Users\Wyatt003\metformin\BMI";
libname numunit    "F:\Users\Wyatt003\metformin\BMI";
libname output    "F:\Users\Wyatt003\metformin\output";

* Required files: Observation File, smoking medcodes-units;

* Set value for cutoff date in Observation file - end of the metformin
  study period (later of the two cohorts, SGLT2i, ends 31MAR2023);
%let cutoff_date="31Mar2023"d;


%macro smoking_obs (obs= , out= );

* Read in files;
* Observation File;
data Observation (drop = pracid enterdate staffid parentobsid obstypeid numrangelow numrangehigh probobsid consid);
	set &obs. ;
	* Delete records with both missing medcodeid and numunitid values;
	if numunitid eq . and medcodeid eq '' then delete;
	* Delete records whose dates are greater than the date of data extraction;
	if obsdate  > &cutoff_date then delete;
run;

* Remove duplicate data from observation file;
proc sort data = Observation noduprecs;
	by patid medcodeid obsid obsdate numunitid value;
run;

* Smoking MedcodeID List;
* Contains smoking medcodeids, their description and smoking status as derived from the description;
* Smoking status can be:
		* 1. current
		* 2. former
		* 3. non-smoker
		* 4. check values (smoking status dependent on the corresponding numunit value e.g.
			 smoking free weeks: if value is 0 or missing, then patient is marked as a current smoker/if the value is >0 then the patient is marked as a former smoker or
             tobacco consumption: if value > 0 then patient is marked as a current smoker/if value is 0 or missing then the patient is marked as a former smoker);
data SmokingMedcodeIDList;
	set medcode.SmokingMedcodeIDList;
run;

* NumunitID List;
data NumUnitIDList;
	set numUnit.NumunitIDList;
run;

* Merge Observation and SmokingMedcodeIDList;
proc sort data = Observation;
	by medcodeid;
run;

proc sort data = SmokingMedcodeIDList;
	by medcodeid;
run;

data Observation_SmokingMedcodeIDs;
	merge Observation (in = ina) SmokingMedcodeIDList (in = inb);
	by medcodeid;
	if ina and inb;
run;

* Merge file with NumunitIDs to add numunitID descriptions;
proc sort data = Observation_SmokingMedcodeIDs;
	by numunitid;
run;

proc sort data = NumUnitIDList;
	by numunitid;
run;

data Observation_SmokingMedcodeIDs_1;
	merge Observation_SmokingMedcodeIDs (in = ina) NumUnitIDList (in = inb);
	by numunitid;
	if ina;
run;

* If smoking status is check value and numunitID is missing then delete records;
data Observation_SmokingMedcodeIDs_2;
	set Observation_SmokingMedcodeIDs_1;
	if SmokingStatus = 'check value' and numunitid = . then delete;
run;

* Create SmokingStatus column - non-smoker, smoker, former smoker;
data SmokingStatus;
	set Observation_SmokingMedcodeIDs_2;
	* For Smoking Status of check value;
	if SmokingStatus eq 'check value' then do;
	* if medcode term is related to consumption, status or use and the value of numunits (cigs per day) > 0, then patient is a current smoker.
	  if value of numunits (cigs per day) = 0 then the patient could be a former smoker or a non smoker, hence unknown (these records will be dropped as it is impossible to determine smoking status);
		if index(lowcase(term), 'consumption') > 0 or index(lowcase(term), 'status') > 0 or index(lowcase(term), 'use') > 0 then do;
			if value > 0 then SmokingStatus = 'current';
			else SmokingStatus = 'unknown';
		end;
	* if medcode term is related to smoke free weeks and the value of weeks is 0, then patient is a current smoker, if it is more than 0, then patient is a former smoker;
	* *** the cut off number of smoke free weeks can be changed i.e. a person who has 1 smoke free week could be still considered a current smoker - this depends on what you chose as a cut off period);
		if term eq 'Smoking free weeks' then do;
			if value > 0 then SmokingStatus = 'former';
			else SmokingStatus = 'current';
		end;
	end;
run;

* Clean up of SmokingStatus file, addition of individual columns for each Smoking Status;
data SmokingStatusFinal (drop = value numunitid term Description SmokingStatus);
	retain patid obsid obsdate medcodeid current former nonsmoker;
	set SmokingStatus;
	if SmokingStatus eq 'unknown' then delete;
	if SmokingStatus eq 'current' then current = 1; else current = 0;
	if SmokingStatus eq 'former' then former = 1; else former = 0;
	if SmokingStatus eq 'non-smoker' then nonsmoker = 1; else nonsmoker = 0;
run;


*Next cleaning step BY Annemariek Driessen.
- There are records with different somking sttuses on the same day
- If patient has been former smoker, it cannot become nonsmoker later on
- If patient has been current smoker, it cannotbecome nonsmoker later on, that should be a former;



data current;
set  SmokingStatusFinal;
if current = 1;
run;

proc sort data = current nodupkey;
by patid obsdate;
run;

data nonsmoker;
set  SmokingStatusFinal;
if nonsmoker = 1;
run;

proc sort data = nonsmoker nodupkey;
by patid obsdate;
run;

data former;
set  SmokingStatusFinal;
if former = 1;
run;

proc sort data = former nodupkey;
by patid obsdate;
run;


data all;
set current (keep = patid obsdate current)
	  former (keep = patid obsdate former)
	  nonsmoker ( keep = patid obsdate nonsmoker) ;
by patid;
if nonsmoker = 1 then total = 2;
if former = 1 then total = 1;
if current = 1 then total = 0;
run;

proc sort data = all ;
by patid obsdate total;
run;

data all2;
set all;
run;


data check_non;
	set all2;
	if nonsmoker=1;
run;

data check_cur_ex;
	set all2;
	if current=1 or former=1;
run;

data check_cur_ex;
	set check_cur_ex;
	rename obsdate=date;
run;

proc sort data=check_non;
by patid obsdate;
run;

proc sort data=check_cur_ex;
by patid date;
run;

/* Step 1: Add 'ok' column initialized to 0 */
data check_non1;
    set check_non;
    ok = 0;
	updated=0;
run;

/* Step 2: Sort datasets by PATID and date */
proc sort data=check_non1;
    by patid obsdate;
run;

proc sort data=check_cur_ex;
    by patid date;
run;
**the first record is important, after that no return possible;

proc sort data=check_cur_ex out=check_cur_ex_uniq nodupkey;
by  patid;
run;



/* Step 3: Merge and update ok flag */
data check_non1_updated;
    merge check_non1(in=a) check_cur_ex_uniq(in=b rename=(date=exdate) keep=patid date);
    by patid;

    retain _found 0;

    if a then do;
        if b then do;
            if exdate > obsdate then ok = 1;
            else ok = 0;
        end;
		if not b then ok=1;
    end;
run;

/* Step 4: Keep only the updated observations from check_non1 */

data check_non1_final;
set check_non1_updated;
if total<2 then delete;
run;

data check_non1_final;
set check_non1_final;
updated=1;
run;

data temp;
set check_non1_final;
run;

proc append base=temp data=check_non1 force; run;

proc sort data=temp;
by  patid obsdate descending updated;
run;


proc sort data=temp out=temp2 nodupkey;
by  patid obsdate;
run;


data nonsmoker_final;
set temp2;
if ok=0 then nonsmoker=0;
if ok=0 then former=1;
run;


data nonsmoker_final (drop=ok);
set nonsmoker_final;
run;

data patid_smk;
set nonsmoker_final;
run;

data check_cur_ex2;
set check_cur_ex;
rename date=obsdate;
run;

proc append base=patid_smk data=check_cur_ex2 force;
run;

proc sort data=patid_smk;
by patid obsdate;
run;


data &out (drop=total _found updated exdate);
set patid_smk;
if current = 1 then smk_cur = 1; else smk_cur = 0;
if former = 1 then smk_ex = 1; else smk_ex = 0;
if nonsmoker = 1 then smk_non = 1; else smk_non = 0;
run;



%mend smoking_obs;

%smoking_obs (obs=data.observation_1, out=output.smoking_all_1);
proc datasets library = work kill nolist;
run;
quit;
%smoking_obs (obs=data.observation_2, out=output.smoking_all_2);
proc datasets library = work kill nolist;
run;
quit;
%smoking_obs (obs=data.observation_3, out=output.smoking_all_3);
proc datasets library = work kill nolist;
run;
quit;
%smoking_obs (obs=data.observation_4, out=output.smoking_all_4);
proc datasets library = work kill nolist;
run;
quit;

data output.smoking_all;
set output.smoking_all_1 output.smoking_all_2 output.smoking_all_3 output.smoking_all_4;
run;

data output.smoking_all;
set output.smoking_all;
if smk_cur = 1 then smk_status = 1;
else if smk_ex = 1 then smk_status = 2;
else smk_status = 0;
run;
