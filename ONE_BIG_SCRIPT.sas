
/* 	Create Smoking Variable
	Magdalena Gamba
	September 28, 2021 */

* Set Libraries;
libname data       "F:\Users\Wyatt003\BPH_nephrolithiasis\output";
libname medcode    "F:\Users\Wyatt003\BPH_nephrolithiasis\BMI";
libname numunit    "F:\Users\Wyatt003\BPH_nephrolithiasis\BMI";

* Required files: Observation File, smoking medcodes-units; 

* Set value for cutoff date in Observation file; 
%let cutoff_date="31Mar2025"d;


%macro smoking_obs (obs= );

* Read in files;
* Observation File;
*data Observation (drop = pracid enterdate staffid parentobsid obstypeid numrangelow numrangehigh probobsid consid); 
*	set &obs. ;	
*	* Delete records with both missing medcodeid and numunitid values; 
*	if numunitid eq . and medcodeid eq '' then delete;
*	* Delete records whose dates are greater than the date of data extraction;
*	if obsdate  > &cutoff_date then delete;	
*run; 

* Remove duplicate data from observation file; 
proc sort data = observation noduprecs;
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


data data.smoking_all (drop=total _found updated exdate);
set patid_smk;
if current = 1 then smk_cur = 1; else smk_cur = 0;
if former = 1 then smk_ex = 1; else smk_ex = 0;
if nonsmoker = 1 then smk_non = 1; else smk_non = 0;
run;



%mend smoking_obs;

%smoking_obs (obs=data.clinical);


proc sort data=data.smoking_all;
by patid obsdate;
run;




/*	Create BMI Variable  
    Magdalena Gamba
    September 29, 2021 */

* Set Library Paths ;
libname data       "F:\Users\Wyatt003\BPH_nephrolithiasis\output";
libname medcode    "F:\Users\Wyatt003\BPH_nephrolithiasis\BMI";
libname numunit    "F:\Users\Wyatt003\BPH_nephrolithiasis\BMI";

* Required files: Observtion File, BMI-Weight-HeightMedcodeIDList,BMI-Weight-HeightNumunitIDList; 

* Set value for cutoff date in Observation file; 
%let cutoff_date="31Mar2025"d;


data temp (drop = pracid enterdate staffid parentobsid obstypeid numrangelow numrangehigh probobsid consid);
set data.observation1;
run;

proc append base=temp data=data.observation2 force; run;
proc append base=temp data=data.observation3 force; run;


%macro BMI_obs (obs=);

* Read in files;
* Observation File;
data Observation (drop = pracid enterdate staffid parentobsid obstypeid numrangelow numrangehigh probobsid consid); 
	set &obs. ;	
	* Delete records with missing numunitid values; 
	if value eq . or value eq 0 then delete;
	* Delete records whose dates are greater than the date of data extraction;
	if obsdate  > &cutoff_date then delete;	
run; 

* Remove duplicate data from observation file; 
proc sort data = observation noduprecs;
	by patid medcodeid obsid obsdate numunitid value;
run;

* BMI/Weight/Height related medcodeids (provided file); 
* Contains a list of BMI/Weight/Height related medcodeIDs with their corresponding terms and classified into 3 measurement type groups: BMI, Weight and Height; 
data BMIWtHtMedcodeIDList (drop = CleansedReadCode SnomedCTConceptID SnomedCTDescriptionID Release EmisCodeCategoryID OriginalReadCode); 
	retain medcodeid term measurement_type;
	set medcode.BMIWeightHeight_medcodes;
run; 

* BMI/Weight/Height related numunitids (provided file); 
* Contains a list of BMI/Weight/Height related numunitIDs with their corresponding description, classified into 3 measurement type groups: BMI, Weight and Height;
data BMIWtHtNumunitIDList; 
	set numunit.BMIWeightHeight_numunitcodes;
run;

* Merge Observation and BMIWtHtMedcodeIDList;
proc sort data = observation; 
	by medcodeid;
run; 

proc sort data = BMIWtHtMedcodeIDList; 
	by medcodeid;
run; 

* Merge Observation and Medcodeid files on medcodeid;
data Observation_BMIWtHtMedcodeIDList;
	merge observation (in = ina) BMIWtHtMedcodeIDList (in = inb);
	by medcodeid;
	if ina and inb;
run; 


* For records in Observation file with missing medcodeids -> use the numunitid file to filter out BMI-Weight-Height related records; 
* Create a subset of records with missing medcodeids;
data observation_medcodeid_missing;
	set observation;
	if medcodeid eq ""; 
run; 

* Merge Observation data with missing medcodeids with the BMIWtHtNumunitIDList;
proc sort data = observation_medcodeid_missing; 
	by numunitid;
run; 

proc sort data = BMIWtHtNumunitIDList; 
	by numunitid;
run; 

data Observation_BMIWtHtNumunitIDList;
	merge observation_medcodeid_missing (in = ina) BMIWtHtNumunitIDList (in = inb);
	by numunitid;
	if ina and inb;
run;

* Concatenate BMIWtHtMedcodeid Observation subset with BMIWtHtNumunitID Observation subset; 
data BMIWtHtRecords;
	retain patid obsid obsdate medcodeid term numunitid value description measurement_type;
	set Observation_BMIWtHtMedcodeIDList Observation_BMIWtHtNumunitIDList;
run; 

* Create 3 columns: BMI, WeightKG, HeightM 
* For values in cm, convert to meters (for numunitIDs 122, 408 and 1863); 
data BMIWtHtRecords_cols;
	set BMIWtHtRecords;
	if Measurement_type eq 'Body Mass Index' then BMI = value;
	else if Measurement_type eq 'Weight' then WeightKG = value;
	else if Measurement_type eq 'Height' and numunitid in (122, 408, 1863) then 
		do;
			HeightM = value/100;
			description = 'm';
		end;
	else HeightM = value; 
run; 

* Create a subset of records with BMI values that fall withing a given min-max range (I chose minimum and maximum BMI values ever recorded in adults);
* Drop duplicates i.e. same value from the same day;
data BMIEntered_WithinRange;
	set BMIWtHtRecords_cols;
	if BMI ne .;
	if 7 =< BMI =< 260;
run; 

proc sort data = BMIEntered_WithinRange nodupkey; 
	by patid obsdate BMI;
run;

* Create a subset of records with Weight values that fall within a given min-max range (I chose minimum and maximum Weight values ever recorded in adults); 
* Drop duplicates i.e. same value from the same day;
* Count the number of weight values entered in each day per patient. If more than 1 then delete ; 
data WtEntered_WithinRange;
	set BMIWtHtRecords_cols; 
	if WeightKG ne .;
	if 2 =< WeightKG =< 450; 
	* round up values;
	WeightKG = round(WeightKG, 0.1);
run; 
 
proc sort data = WtEntered_WithinRange nodupkey; 
	by patid obsdate WeightKG;
run;

proc sql;
	create table WtEntered_WithinRange1 as
	select	*, count(WeightKG) as wt_entries_ct
	from  WtEntered_WithinRange
	group by patid, obsdate;
quit;

data WtEntered_WithinRange;
	set WtEntered_WithinRange1; 
	if wt_entries_ct > 1 then delete; 
run; 

* Create a subset of records with Height values that fall within a given min-max range (I chose minimum and maximum Weight values ever recorded in adults); 
* Drop duplicates i.e. same value from the same day;
* Count the number of weight values entered in each day per patient. If more than 1 then delete ; 
data HtEntered_WithinRange; 
	set BMIWtHtRecords_cols; 
	if HeightM ne .;
	if 0.5 =< HeightM =< 2.8;
	HeightM = round(HeightM, 0.01);
run; 

proc sort data = HtEntered_WithinRange nodupkey; 
	by patid obsdate HeightM;
run;

proc sql;
	create table HtEntered_WithinRange1 as
	select	*, count(HeightM) as ht_entries_ct
	from  HtEntered_WithinRange
	group by patid, obsdate;
quit;

data HtEntered_WithinRange;
	set HtEntered_WithinRange1; 
	if ht_entries_ct > 1 then delete; 
run; 

* Concatenate weight and height records *; 
data WtHtEntered_WithinRange (drop = wt_entries_ct ht_entries_ct value numunitid BMI); 
	set WtEntered_WithinRange HtEntered_WithinRange;
run; 

proc sort data = WtHtEntered_WithinRange; 
	by patid obsdate;
run; 

* Put height and weight on the same row for each patientid/date;
data WtHtEntered_samerow;
  update WtHtEntered_WithinRange(obs=0) WtHtEntered_WithinRange;
  by  patid obsdate;
  output;
run;

proc sort data = WtHtEntered_samerow; 
	by patid obsdate descending HeightM;
run; 

data WtHtEntered_samerow1;
  update WtHtEntered_samerow(obs=0) WtHtEntered_samerow;
  by  patid;
  output;
run;

* Delete rows where Weight does not have a corresponding Height value (for the same patient, same day);
data WtHtEntered_samerow2;
	set WtHtEntered_samerow1;
	if WeightKG eq . then delete;
	if HeightM eq . then delete;
run;

* Remove any duplicates;
proc sort data = WtHtEntered_samerow2 nodupkey; 
	by patid obsdate WeightKG HeightM;
run;

* Calculate BMI based on Height and Weight Measurements;
data BMICalculated_WithinRange;
	set WtHtEntered_samerow2;
	BMI_calc = round((WeightKG/(HeightM * HeightM)), 0.01);
	if 7 =< BMI_calc =< 260;
run; 

* Clean Up!;
proc delete data=work.Observation_BMIWtHtRecords_cols; run;
proc delete data=work.Observation_bmiwthtnumunitidlist; run;

* Concatenate records with BMI previously entered with those with BMI calculated;
proc sort data = BMIEntered_WithinRange; 
	by patid obsdate;
run; 

proc sort data = BMICalculated_WithinRange;
	by patid obsdate; 
run; 

data BMI_both (drop = term numunitid value description measurement_type WeightKG HeightM); 
	set BMIEntered_WithinRange BMICalculated_WithinRange;
	by patid;
	rename BMI = BMI_entered;
run; 

* Put BMI values (entered & calculated) on the same row per patient per obsdate);
proc sort data = BMI_both;
	by patid obsdate descending BMI_entered;
run; 

data BMI_both1;
  update BMI_both(obs=0) BMI_both;
  by  patid;
  output;
run;

proc sort data = BMI_both1;
	by patid obsdate descending BMI_calc;
run; 

data BMI_both2;
  update BMI_both1(obs=0) BMI_both1;
  by  patid;
  output;
run;

* Remove any duplicates;
proc sort data = BMI_both2 nodupkey; 
	by patid obsdate BMI_entered BMI_calc;
run;

* Create a column with the final BMI value;
* If BMI is present in the records then use this value;
* If BMI is missing, then use the calculated BMI value;
data FINAL_BMI (drop = BMI_entered BMI_calc);
	set BMI_both2;
	if BMI_entered ne . then BMI_final = BMI_entered; 
	if BMI_entered eq . and BMI_calc ne . then BMI_final = BMI_calc;
run; 


data data.bmi_all;
set final_bmi;
run;

%mend BMI_obs;

%BMI_obs (obs=data.clinical);







 



