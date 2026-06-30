 
***********************************************************************************************************************
**
** PROJECT:  Concomitant use of GCs and PPIs and Fx risk in RA patients
**
** PURPOSE: Adding BMI to patient file
** DATE CREATED: 22.01.2019
** CREATED BY: Shahab Abtahi
**
** DATASET USED: Raw_data.Additional
**               Raw_data.Clinical
**               Wrk_data.FinalPx
**
** CODELISTS USED: -
**                 
** DATASET CREATED: Wrk_data.BMI_all
**					Wrk_data.FinalPx_BMI
**		
*************************************************************************************************************************;


/*  Extraxting BMI Records  */

Data BMI;   /* data1 shows weight; data3 shows BMI */
	set raw_data.additional (keep=patid adid data1 data3 enttype);
	where enttype = 13;
	if 10 =< data3 =< 70 or data3 = .;     
	if data3 = . then do;
		if 25 =< data1 =< 250;
	end;
	drop enttype;
run;

Data height;  /* data1 shows height in meters */
	set raw_data.additional (keep=patid adid data1 enttype);
	where enttype = 14;
	if 1 =< data1 =< 2.5;
	drop enttype;
run;


/* Selecting Date for Test Records */

Proc sort data=raw_data.clinical;
	by adid patid;
run;

Proc sort data=BMI nodupkey ;
	by adid patid;
run;

Proc sort data=height nodupkey;
	by adid patid;
run;


Data BMI2;
	merge BMI (in=x) raw_data.clinical (in=y keep=patid adid eventdate);
	by adid patid;
	if x and y;
	if eventdate = . then delete;
	drop adid;
run;

Data height2;
	merge height (in=x) raw_data.clinical (in=y keep=patid adid eventdate);
	by adid patid;
	if x and y;
	if eventdate = . then delete;
	drop adid;
run;


/* Selecting highest BMI value if there are multiple records on a single day */

Proc sort data=BMI2;
	by patid eventdate data3;
run;

Data BMI3;
	set BMI2;
	by patid eventdate data3;
	if last.eventdate;
run;

Data BMI4;
	set BMI3;
	if data3 > 0; 
	bmi = data3* 1; 
	Drop data3;
run;


/* Sorting out the missing BMI values */

Data BMI_mis;
	set BMI3;
	if data3 = .;
	calculated = 1;
run;

Proc sort data=BMI_mis;
	by patid;
run;

Proc sort data=height2;
	by patid;
run;

Data BMI_mis2;
	merge BMI_mis (in=x drop=data3 rename= eventdate=weight_date rename= data1=weight) height2 (in=y rename= eventdate=height_date rename= data1=height);
	by patid;
	if x;
	if height = . then delete;
	datedif = weight_date - height_date;
	if datedif < 0 then datedif = datedif * -1;
run;

Proc sort data=BMI_mis2;
	by patid weight_date datedif;
run;

Data BMI_mis3;
	set BMI_mis2;
	by patid weight_date datedif;
	if first.weight_date;
	BMI = (weight) / (height*height);
run;


/* Adding Systematic BMI + Calculated BMI Sets */

Data BMI_all;
	set bmi4 (in=x keep=patid bmi eventdate  rename= eventdate=bmidate) bmi_mis3 (in=y keep=patid bmi height_date rename= height_date=bmidate);
	if x then calculated = 0;
	if y then calculated = 1;
run;

Proc freq data = BMI_all;
 Tables calculated;
run;


/* Prioritizing Systematic BMI values if 2 tests on a single day */

Proc sort data=BMI_all;
	by patid bmidate calculated descending bmi;
run;

Data wrk_data.BMI_all;
	set BMI_all;
	by patid bmidate calculated descending bmi;
	if first.bmidate;
	if 10 =< bmi =< 70;
run;


/* Merging with patients file */

Proc sort data = wrk_data.bmi_all;
	by patid bmidate;
run;

Proc sort data = wrk_data.FinalPx;
	by patid;
run;

Data bmitmp;
	merge wrk_data.FinalPx (keep=patid indexdate in=x) wrk_data.bmi_all (in=y);
	by patid;
	if x and y and bmidate NE . and (12 =< BMI =< 70);
	bmi_gap = (bmidate - indexdate);
	if bmi_gap < 0 then bmi_gap = bmi_gap * -1;
run;

Proc sort data = bmitmp;
	by patid bmi_gap;
run;

Data bmitmpx;
set bmitmp;
by patid bmi_gap;
if first.patid;
run;

Proc sort data = wrk_Data.FinalPx;
by patid;
run;

Data wrk_data.FinalPx_BMI;
	merge wrk_data.FinalPx (in=x keep = patid age sex end indexdate yob) bmitmpx (in=y keep = patid bmi);
	by patid;
	if x;
run;

Data wrk_data.FinalPx_BMI;
	set wrk_data.FinalPx_BMI;
	if bmi=. then bmimis=1 ; else bmimis=0;
	if bmi <20 and bmi ne . then bmicat1=1; else bmicat1=0;
	if bmi >=20 and bmi <25 then bmicat2=1; else bmicat2=0;
	if bmi >=25 and bmi <30 then bmicat3=1; else bmicat3=0;
	if bmi >=30 and bmi <35 then bmicat4=1; else bmicat4=0;
	if bmi >=35  then bmicat5=1; else bmicat5=0;
	
	label bmicat1="BMI-Cat1 - BMI <20 /MostRecent";  /* Units are kg/m2, Most recent values to indexdate */
	label bmicat2="BMI-Cat2 - BMI 20-25 /MostRecent(Ref)";
	label bmicat3="BMI-Cat3 - BMI 25-30 /MostRecent";
	label bmicat4="BMI-Cat4 - BMI 30-35 /MostRecent";
	label bmicat5="BMI-Cat5 - BMI >35 /MostRecent";
	label bmimis="BMI-MIS - BMI missing /MostRecent";
run;


Proc freq data = wrk_data.FinalPx_BMI;
tables bmicat1 bmicat2 bmicat3 bmicat4 bmicat5 bmimis;
run;

