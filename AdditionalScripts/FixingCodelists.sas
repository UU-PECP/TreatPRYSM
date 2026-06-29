data codelist.bph_drugs_fixed;
set codelist.tamsulosin_alfuzosin_finisteride;
keep TermfromEMIS ProductName drugsubstancename substancestrength formulation routeofadministration bnfcode DrugIssues Exposure mg_dose;
run;

data codelist.bph_drugs_fixed;
	set codelist.bph_drugs_fixed;
	length ProdCodeId $19;
    set rawdata.drugissue_1;
    if ProductName = "Finasteride 5mg tablets" then ProdCodeId = "576641000033110";
    else if ProductName = "Finasteride 1mg tablets" then ProdCodeId = "2724041000033113";
    else if ProductName = "Finasteride 5mg/5ml oral suspension" then ProdCodeId = "13956641000033113";

    else if ProductName = "Alfuzosin 5mg modified-release tablets" then ProdCodeId = "32541000033112";
    else if ProductName = "Alfuzosin 2.5mg tablets" then ProdCodeId = "38141000033118";
	else if ProductName = "Alfuzosin 10mg modified-release tablets" then ProdCodeId = "2077541000033111";

	else if ProductName = "Tamsulosin 400microgram modified-release capsules" then ProdCodeId = "1406241000033110";
	else if ProductName = "Tamsulosin 400microgram modified-release tablets" then ProdCodeId = "3342941000033112";
    else if ProductName = "Tamsulosin 400microgram / Dutasteride 500microgram capsules" then ProdCodeId = "5632441000033119";
    else if ProductName = "Solifenacin 6mg / Tamsulosin 400microgram modified-release tablets" then ProdCodeId = "8960641000033119";
    else if ProductName = "Tamsulosin 400micrograms/5ml oral solution" then ProdCodeId = "9201141000033115";
    else if ProductName = "Tamsulosin 400micrograms/5ml oral suspension" then ProdCodeId = "11524441000033118";
run;
