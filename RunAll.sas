%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\1_1_TAMSULOSIN_create_base_cohorts.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\2_1_TAMSULOSIN_tamsulosin_bph_cohort.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\3_1_bph_propensity_score_vars.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\3_2_smoking.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\3_3_bmi.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\3_4_medication_covariates.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\BPH_nephrolithiasis\VDI_Scripts\3_5_bph__pp_propsensity_score_combine_all_variables.sas";

proc datasets library = work kill nolist;
run;
quit;

