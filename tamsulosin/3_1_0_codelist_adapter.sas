
libname codelist "F:\Users\Wyatt003\Tamsulosin\Disorder_Codes";

data codelist.alopecia;
	infile "F:\Users\Wyatt003\Tamsulosin\Disorder_Codes\Alopecia androgenic_SA.txt" dsd dlm='09'x firstobs=2 truncover;
	length MedCode $19 Observations 8 OriginalReadCode $7 CleansedReadCode $7 Term $102 SnomedCTConceptId 8 SnomedCTDescriptionId 8 EmisCodeCategoryId 8;
	input MedCode :$19. Observations OriginalReadCode :$7. CleansedReadCode :$7. Term :$102. SnomedCTConceptId SnomedCTDescriptionId EmisCodeCategoryId;
run;

data codelist.chronic_liver;
	infile "F:\Users\Wyatt003\Tamsulosin\Disorder_Codes\Chronic liver dis_SA.txt" dsd dlm='09'x firstobs=2 truncover;
	length MedCode $19 Observations 8 OriginalReadCode $7 CleansedReadCode $7 Term $102 SnomedCTConceptId 8 SnomedCTDescriptionId 8 EmisCodeCategoryId 8;
	input MedCode :$19. Observations OriginalReadCode :$7. CleansedReadCode :$7. Term :$102. SnomedCTConceptId SnomedCTDescriptionId EmisCodeCategoryId;
run;
