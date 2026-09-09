/*	Create BMI Variable
    Originally by Magdalena Gamba, September 29, 2021
    Reused unchanged for the metformin project (patid-level GP-derived
    BMI - not drug or cohort specific). Shared by both the SU and
    SGLT2i cohorts; the combine step (3_3) merges this in per cohort
    using each cohort's own index date. */

* Set Library Paths ;
libname data       "F:\Users\Wyatt003\metformin\SAS";
libname medcode    "F:\Users\Wyatt003\metformin\BMI";
libname numunit    "F:\Users\Wyatt003\metformin\BMI";
libname output "F:\Users\Wyatt003\metformin\Output";

* Required files: Observtion File, BMI-Weight-HeightMedcodeIDList,BMI-Weight-HeightNumunitIDList;

* Set value for cutoff date in Observation file - end of the metformin
  study period (later of the two cohorts, SGLT2i, ends 31MAR2023);
%let cutoff_date="31Mar2023"d;


%macro BMI_obs (obs=, out=);

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
* Updated possible range based on Shahab's CPRD gold BMI script.
data BMIEntered_WithinRange;
	set BMIWtHtRecords_cols;
	if BMI ne .;
	if 12 =< BMI =< 70;
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
	if 25 =< WeightKG =< 250;
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
	if 1 =< HeightM =< 2.5;
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
data &out (drop = BMI_entered BMI_calc);
	set BMI_both2;
	if BMI_entered ne . then BMI_final = BMI_entered;
	if BMI_entered eq . and BMI_calc ne . then BMI_final = BMI_calc;
run;


%mend BMI_obs;

%BMI_obs (obs=data.observation_1, out=output.bmi_all_1);
proc datasets library = work kill nolist;
run;
quit;
%BMI_obs (obs=data.observation_2, out=output.bmi_all_2);
proc datasets library = work kill nolist;
run;
quit;
%BMI_obs (obs=data.observation_3, out=output.bmi_all_3);
proc datasets library = work kill nolist;
run;
quit;
%BMI_obs (obs=data.observation_4, out=output.bmi_all_4);
proc datasets library = work kill nolist;
run;
quit;

data output.bmi_all;
set output.bmi_all_1 output.bmi_all_2 output.bmi_all_3 output.bmi_all_4;
run;
