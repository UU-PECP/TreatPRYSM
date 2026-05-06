proc sql;
	CREATE TABLE output.clinical_codes_counts as
	SELECT medcodeId, COUNT(*) as observations
	FROM output.clinical
	GROUP BY medcodeId;
run;

proc sql;
	CREATE TABLE code_validation AS
	SELECT code.medcode, code.readterm
	FROM 
		codelists.bph_code AS code
	INNER JOIN
		rawdata.codebrowser_aurum_dec2025 AS brow
		ON input(brow.medcodeId, best19.) = code.medcode;
quit;


* STEP 4: Checking;

proc contents data = codelist.bph_codelist;
run;
* patid is Numeric;

proc contents data = output.clinical;
run;
*patid is Character;

proc contents data = output.initial_cohort;
run;
*patid is Character;

proc print data=output.initial_cohort(obs=3);
run;



******* From shahab, BPH;

data codelist.bph_codelist;
infile "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\2_CleanCodes\bph.txt" dsd dlm='09'x firstobs=2 truncover;
informat medcode best20.;
informat clinicalevents best12.;
informat readcode $14.;
informat readterm $14.;
input medcode clinicalevents readcode $ readterm $ ;
run;


Proc sort data = codelist.bph_codelist ;
by medcode ;
run;

Data BPH_codelist ;
Set codelist.bph_codelist ;
Rename medcode = medcodeid2 ;
run;

Data Clinical1 ;
Set output.clinical_1 ;
medcodeid2 = input (medcodeid, Best20.);
run;

Data COnsult1 ;
Set Rawdata.Consultation_1 ;
medcodeid2 = input (consmedcodeid, best20.);
run;


Proc sort data = Clinical1 ;
by medcodeid2 ;
run;


Proc sort data = COnsult1 ;
by medcodeid2 ;
run;

Data test2;
merge Clinical1 (in=x ) BPH_codelist (in=y);
by medcodeid2 ;
if x and y ;
run;

Data test4;
merge COnsult1 (in=x ) BPH_codelist (in=y);
by medcodeid2 ;
if x and y ;
run;

Proc sort data=test2;
by patid;
run;

Data test3;
Set test2 ;
by patid;
if first.patid;
run;


Data test ;
set codelist.bph_codelist;
where medcode = 5493341000006111;
run;


******* From shahab, NL;

data codelist.nl_codelist;
infile "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\2_CleanCodes\nephrolithiasis.txt" dsd dlm='09'x firstobs=2 truncover;
informat medcode best20.;
informat clinicalevents best12.;
informat readcode $14.;
informat readterm $14.;
input medcode clinicalevents readcode $ readterm $ ;
run;


Proc sort data = codelist.nl_codelist ;
by medcode ;
run;

Data NL_codelist ;
Set codelist.nl_codelist ;
Rename medcode = medcodeid2 ;
run;

Data Clinical1 ;
Set output.clinical_1 ;
medcodeid2 = input (medcodeid, Best20.);
run;

Proc sort data = Clinical1 ;
by medcodeid2 ;
run;

Data test5;
merge Clinical1 (in=x ) NL_codelist (in=y);
by medcodeid2 ;
if x and y ;
run;


*** checking code frequency;

Proc sort data = rawdata.codebrowser_aurum_dec2025 ;
by medcodeid2 ;
run;

data small_aurum;
set rawdata.codebrowser_aurum_dec2025 ;
keep medcodeid term;
run;

