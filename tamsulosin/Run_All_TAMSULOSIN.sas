%include "F:\Users\Wyatt003\Tamsulosin\VDI_Scripts\7_1_tamsulosin_bph_on_treatment.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\Tamsulosin\VDI_Scripts\7_2_tamsulosin_bph_ot_bmi_smoking.sas";

proc datasets library = work kill nolist;
run;
quit;
