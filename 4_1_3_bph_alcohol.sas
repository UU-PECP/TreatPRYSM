
***********************************************************************************************************************
**
** PROJECT:  Concomitant use of GCs and PPIs and Fx risk in RA patients
**
** PURPOSE: Adding Alcohol to patient file
** DATE CREATED: 23.01.2019
** CREATED BY: Shahab Abtahi
**
** DATASET USED: Wrk_data.FinalPx_SMK
**              
** CODELISTS USED:	 alcohol_yes.txt
**					alcohol_no.txt
**                 
** DATASET CREATED: Wrk_data.Alc_all
**					Wrk_data.FinalPx_all
**					
*************************************************************************************************************************;

/*  Extracting Alcohol Records  */

%let alc_yes = alcohol_yes;
%let alc_no = alcohol_no;

Data alc_yes_cd;
	infile "&projectfolder.\5_Codelists\alcohol_yes.txt" dsd dlm='09'x firstobs=2 truncover;
	input medcode;
	informat 	medcode 20.;
	format 		medcode 20.;
run;

Data alc_no_cd;
	infile "&projectfolder.\5_Codelists\alcohol_no.txt" dsd dlm='09'x firstobs=2 truncover;
	input medcode;
	informat 	medcode 20.;
	format 		medcode 20.;
run;

Proc sort data=raw_data.clinical;
	by medcode;
run;

Proc sort data=alc_yes_cd;
	by medcode;
run;

Proc sort data=alc_no_cd;
	by medcode;
run;

Data alcohol;
	merge raw_data.clinical (in=x) alc_yes_cd (in=y keep=medcode) alc_no_cd (in=z keep=medcode);
	by medcode;
	if (x and y) or (x and z);
	if y then alc_yes = 1;
	if z then alc_no = 1;
run;


Data alc;
	set raw_data.additional;
	where enttype = 5;
run;

Proc sort data=raw_data.clinical;
	by adid patid;
run;

Proc sort data=alc nodupkey;
	by adid patid;
run;

Data alc1;
	format data4_new ddmmyy10.;
	merge alc (in=x) raw_data.clinical (in=y keep=patid adid eventdate);
	by adid patid;
	if x and y;
	if eventdate = . then delete;
	if data4 ne "0" then do;
	data4_new = input(data4, ddmmyy10.);
	end;
	if data4 = "0" then data4_new = 0;
	drop adid data2 data3 data4 data5 data6 data7 enttype;
	rename data4_new = data4;
run;

Data alc2;
	set alc1;
	if data1 = 1 then alc_yes = 1;
	if data1 = 2 then alc_no = 1;
	if data1 = 3 then alc_no = 1;
	if alc_no = 1 or alc_yes = 1;
run;

Data wrk_data.Alc_all;
	set alc2 (keep=patid eventdate alc_yes alc_no) alcohol (keep=patid eventdate alc_yes alc_no);
run;

Proc sort data = wrk_data.alc_all nodupkey;
	by patid eventdate;
run;


/* Merging with Patient file */

Proc sort data = wrk_data.FinalPx_SMK;
	by patid;
run;

Data alc_tmp1;
	merge wrk_data.FinalPx_SMK (in=x keep=patid indexdate) wrk_data.alc_all (in=y);
	by patid;
	if x and y and eventdate NE .;
	gap_alc = (indexdate - eventdate);
	if gap_alc < 0 then gap_alc = gap_alc * -1;
run;

Proc sort data = alc_tmp1;
	by patid gap_alc;
run;

Data alc_tmp2;
	set alc_tmp1;
	by patid gap_alc;
	if first.patid;
	drop eventdate;
run;

Data wrk_data.FinalPx_All;
	merge wrk_data.FinalPx_SMK (in=x) alc_tmp2 (in=y keep = patid alc_yes alc_no);
	by patid;
	if x;
	if y = 0 then alc_mis = 1;
	if alc_mis = . then alc_mis = 0;
	if alc_yes = . then alc_yes = 0;
	if alc_no = . then alc_no = 0;

	label alc_mis="alc_mis - alcohol data missing";
	label alc_yes="alc_yes - alcohol use, MostRecent";
	label alc_no="alc_no - no alcohol use, MostRecent(Ref)";
run;

Proc freq data = wrk_data.FinalPx_all;
Tables alc_mis alc_yes alc_no;
run;


