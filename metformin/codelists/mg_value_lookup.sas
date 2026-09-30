/**************************************************************************/
/* Extract mg_value from a drug codelist's substance strength             */
/*                                                                          */
/* Produces a 2-column lookup: ProdCodeId, mg_value.                       */
/*                                                                          */
/* DEVIATION FROM PRECEDENT: the tamsulosin codelists (see                 */
/* AdditionalScripts/extract_mg_value_from_strength.sas) take the FIRST    */
/* number in the strength string as the per-unit dose. That convention     */
/* silently gives the WRONG value for some metformin combination products, */
/* because CPRD does not consistently list metformin first in either       */
/* drugsubstancename or substancestrength - e.g. Jentadueto is             */
/* "Linagliptin/ Metformin hydrochloride" with strength "2.500mg +         */
/* 1000.000mg", so "first number" would report 2.5 (linagliptin's dose)    */
/* instead of 1000 (metformin's dose, which is what the low/high dose      */
/* covariate actually needs). This version instead splits                  */
/* drugsubstancename on "/" and substancestrength on "+", pairs them       */
/* positionally, and returns the segment matching one of the names in      */
/* &target_substances. For a monotherapy product (single segment, no "/")  */
/* leave &target_substances blank to just take that one segment as-is.     */
/*                                                                          */
/* &target_substances: pipe-delimited list of substance-name substrings to */
/* match within drugsubstancename (e.g. Metformin, or                      */
/* Dapagliflozin|Canagliflozin|Empagliflozin|Ertugliflozin for a           */
/* codelist spanning several drugs in one class). Blank = single-segment   */
/* products only, always take that segment.                                */
/**************************************************************************/

%macro mg_value_lookup(in=, target_substances=, out=);

data &out;
    length unit_found $20 sub_i $100 str_i $40 target_i $100;
    set &in;

    n_subs = countw(drugsubstancename, '/');
    n_strs = countw(substancestrength, '+');

    mg_value = .;

    if n_subs = n_strs then do i = 1 to n_subs;
        sub_i = strip(scan(drugsubstancename, i, '/'));
        str_i = strip(scan(substancestrength, i, '+'));

        is_match = 0;
        if n_subs = 1 and "&target_substances" = "" then is_match = 1;
        else do j = 1 to countw("&target_substances", '|');
            target_i = strip(scan("&target_substances", j, '|'));
            if index(lowcase(sub_i), lowcase(target_i)) > 0 then is_match = 1;
        end;

        if is_match then do;
            /* First number in this segment (handles decimals) */
            raw_value = input(scan(str_i, 1, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ/'), best12.);
            unit_found = scan(compress(str_i, '0123456789. '), 1, '/');

            if lowcase(unit_found) in ('microgram', 'micrograms', 'mcg') then mg_value = raw_value / 1000;
            else if lowcase(unit_found) in ('gram', 'g') then mg_value = raw_value * 1000;
            else mg_value = raw_value; /* mg stays as-is */
        end;
    end;
    /* n_subs ne n_strs: can't safely align segments - leave mg_value missing */
    /* rather than silently guessing; worth a manual look at &in for that id */

    keep ProdCodeId mg_value;
run;

%mend mg_value_lookup;

/**************************************************************************/
/* Build the lookup for the three drug classes we have codelists for.     */
/* Extend with more %mg_value_lookup calls (and add to the final SET)     */
/* once covariate comedication codelists (antihypertensives,              */
/* anticoagulants, etc.) exist.                                            */
/**************************************************************************/

%mg_value_lookup(in=codelist.metformin, target_substances=Metformin, out=mg_metformin);
%mg_value_lookup(in=codelist.sulfonylureas, target_substances=, out=mg_su);
%mg_value_lookup(in=codelist.flozins, target_substances=Dapagliflozin|Canagliflozin|Empagliflozin|Ertugliflozin, out=mg_sglt2i);

data metformin.mg_value_lookup;
    set mg_metformin mg_su mg_sglt2i;
run;

/* Sanity check: anything that failed to parse deserves a manual look */
proc print data=metformin.mg_value_lookup;
    where mg_value = .;
run;
