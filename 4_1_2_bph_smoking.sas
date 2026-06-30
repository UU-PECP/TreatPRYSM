 
***********************************************************************************************************************
**
** PROJECT:  Concomitant use of GCs and PPIs and Fx risk in RA patients
**
** PURPOSE: Adding Smoking to patient file
** DATE CREATED: 22.01.2019
** CREATED BY: Shahab Abtahi
**
** DATASET USED: Wrk_data.FinalPx_BMI
**              
** CODELISTS USED: readcodes_smoking
**                 
** DATASET CREATED: Wrk_data.FinalPx_SMK
**					
**		
*************************************************************************************************************************;

/*  Extracting Smoking Records  */

Proc sort data=rawdata.clinical;
	by medcode;
run;

Proc sort data=codelist.readcodes_smoking;
	by pegasus_co;
run;

Data smoking;
	merge raw_data.clinical (in=x) codelist.readcodes_smoking (in=y keep=pegasus_co current former non rename= pegasus_co=medcode);
	by medcode;
	if x and y;
run;


Data smok;
	set raw_data.additional;
	where enttype = 4;
run;

Proc sort data=raw_data.clinical;
	by adid patid;
run;

Proc sort data=smok nodupkey;
	by adid patid;
run;


Data smok1;
format data6_new ddmmyy10.;
merge smok (in=x) raw_data.clinical (in=y keep=patid adid eventdate);
	by adid patid;
	if x and y;
	if eventdate = . then delete;
	if data6 ne "0" then do;
	data6_new = input(data6, ddmmyy10.);
	end;
	if data6 = "0" then data6_new = 0;
	drop adid data2 data3 data4 data5 data6 data7 enttype;
	rename data6_new = data6;
	
run;

Data smok2;
	set smok1;
	if data1 = 1 then current = 1;
	if data1 = 2 then do;
		if data6 = . then non = 1;
		if 0 < data6 < (eventdate - (365.25*5)) then former = 1;
	end;
	if data1 = 3 then former = 1;
	if current = 1 or former = 1 or non = 1;
run;


Proc sort data=smoking;
by patid eventdate;
run;

Proc sort data=smok2;
by patid eventdate;
run;

Data smok_all;
	set smok2 (keep=patid eventdate current former non) smoking (keep=patid eventdate current former non);
run;

Proc sort data = smok_all;
	by patid eventdate;
run;


/* Correcting for impossible shifts */

Data smok_all1;  /* selecting positive smoking history*/
	set smok_all;
	by patid eventdate;
	if current=1 then current_new=1;
	if non=1 then non_new=0;
	if former=1 then former_new=1;
run;

Data smok_all1;
	set smok_all1;
	if current_new=. then current_new=0;
	if non_new=. then non_new=0;
	if former_new=. then former_new=0;
	total = current_new + non_new + former_new;  /*smoking history is 0/1*/
	drop current_new non_new former_new;
run;


Data smok_all2;  /* counting each record of current/former smoking */
	set smok_all1;
 	by patid;
	if total=1 then do;
		test+1;
		end;
	if first.patid and total=0 then do;   /*restart with new PATID with first record = non-smoke*/
		test=0;
	end;
run;


Data smok_all3;  /* selecting positive smoking history */
	set smok_all2;
	if test =>1 then ex=1;
	if test <1 or test=. then ex=0;
	drop test total;
	if ex=1 then do;
		if current=1 then ex_new=.;
		if current=. then ex_new=1;
	end;
	if non=. then non_new=.;else non_new=1;
	if non=1 then do;
		if ex_new=1 then non_new=.;
		if current=1 then non_new=.;
	end;
	drop ex former non;
	rename  ex_new = former  non_new = non;
run;


/* Merging with Patient file */

Proc sort data = smok_all3 nodupkey;
by patid eventdate;
run;

Data smk_tmp1a;
	merge wrk_data.FinalPx_bmi (in=x) smok_all3 (in=y);
	by patid;
	if x and y and eventdate NE .;
	smok_gap = (eventdate - indexdate); 
	if smok_gap < 0 then smok_gap=smok_gap * -1;
run;

Proc sort data = smk_tmp1a;
	by patid smok_gap;
run;

Data smk_tmp2a;
	set smk_tmp1a;
	by patid smok_gap;
	if first.patid;
	drop eventdate;
run;

Data wrk_data.FinalPx_SMK;
	merge wrk_data.FinalPx_bmi (in=x) smk_tmp2a (in=y keep = patid current former non rename=(current=smk_cur former=smk_ex non=smk_non));
	by patid;
	if x;
	if y = 0 then smk_mis = 1;
	if smk_mis = . then smk_mis = 0;
	if smk_cur = . then smk_cur = 0;
	if smk_ex = . then smk_ex = 0;
	if smk_non = . then smk_non = 0;

	label smk_mis="smk_mis - smoking data missing";
	label smk_non="smk_non - non smoker, MostRecent(Ref)";   /* Most recent values to indexdate */
	label smk_ex="smk_ex - ex smoker, MostRecent";
	label smk_cur="smk_cur - current smoker, MostRecent";
run;


Proc freq data = wrk_data.FinalPx_SMK;
Tables smk_non smk_cur smk_ex smk_mis;
run;

