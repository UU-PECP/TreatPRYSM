/************************************************/
** 	the Treat-PRYSM project 					**
** 	Drug - Metformin							**
**												**
**	RunAll: SAS orchestration                   **
**	Modelled on tamsulosin/RunAll.sas +         **
**	Run_All_2.sas. R scripts (4_x, 5_x, 7_3/7_4)**
**	are NOT included here - run those           **
**	separately once their SAS inputs exist.     **
/************************************************/;

*** Raw extract processing (generic CPRD ingestion, run once) ***;
/*
%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\1_0_METFORMIN_large_file_processing.sas";

proc datasets library = work kill nolist;
run;
quit;
*/ *** Don't run until data access;
*** Base cohort (shared by both cohorts) ***;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\1_1_METFORMIN_create_base_cohort.sas";

proc datasets library = work kill nolist;
run;
quit;

/*** Shared smoking/BMI derivation (run once, before either cohort's        ***/
*** covariates step - both 3_3 and 3_4 read output.smoking_all/bmi_all)    ***;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\3_1_METFORMIN_smoking.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\3_2_METFORMIN_bmi.sas";

proc datasets library = work kill nolist;
run;
quit;

*** Cohort A: metformin vs. sulphonylureas (2004-2013) ***;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\2_1_METFORMIN_su_cohort.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\3_3_METFORMIN_su_covariates.sas";

proc datasets library = work kill nolist;
run;
quit;

*** Cohort B: metformin vs. SGLT2 inhibitors (2014-2023) ***;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\2_2_METFORMIN_sglt2i_cohort.sas";

proc datasets library = work kill nolist;
run;
quit;

%include "F:\Users\Wyatt003\Metformin\VDI_Scripts\3_4_METFORMIN_sglt2i_covariates.sas";

proc datasets library = work kill nolist;
run;
quit;

/**************************************************************************/
/* NEXT STEPS (outside this file):                                        */
/*   1. Run 4_1_METFORMIN_su_treatmentepisodes.R and                      */
/*      4_2_METFORMIN_sglt2i_treatmentepisodes.R (AdhereR episodes)       */
/*   2. Run 5_1_METFORMIN_su_pp.R and 5_2_METFORMIN_sglt2i_pp.R           */
/*      (per-protocol PS matching + Cox models)                           */
/*   3. Run 7_1_METFORMIN_su_on_treatment.sas and                         */
/*      7_2_METFORMIN_sglt2i_on_treatment.sas (on-treatment intervals -   */
/*      requires step 1's treatment-episode csvs)                        */
/*   4. Run 7_3_METFORMIN_su_ot.R and 7_4_METFORMIN_sglt2i_ot.R           */
/*      (on-treatment Cox models)                                          */
/**************************************************************************/
