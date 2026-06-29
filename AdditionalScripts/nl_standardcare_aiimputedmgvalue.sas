/**************************************************************************/
/* Create mg_value from productname in nl_standardcare codelist          */
/**************************************************************************/
/* Logic:
   - mg/Xml or mg/ml (concentration) formats -> take the mg number as-is
     (treated as per-unit strength, per Sage's decision)
   - % formulations (topical/gel) -> mg_value left missing (not oral dosing)
   - micrograms/mcg -> converted to mg (divided by 1000)
   - g -> converted to mg (multiplied by 1000)
   - mg -> kept as-is
   - No unit found, or ambiguous brand-name-only products -> missing      */

libname codelist "C:\Users\Wyatt003\OneDrive - Universiteit Utrecht\Documents\Codelists\3_MagdasCodes";

data codelist.nl_standardcare;
    set codelist.nl_standardcare;
    length unit_found $20. num_str $20.;
    retain patid_re;

    /* Compile regex once: capture group 1 = number, group 2 = unit */
    if _n_ = 1 then patid_re = prxparse('/(\d+\.?\d*)\s*(mg|micrograms?|mcg|g)\b/i');

    /* Leave missing entirely if % appears anywhere in the name (topical) */
    if index(productname, '%') > 0 then do;
        mg_value = .;
    end;
    else if prxmatch(patid_re, productname) > 0 then do;
        call prxposn(patid_re, 1, num_start, num_len);
        call prxposn(patid_re, 2, unit_start, unit_len);

        num_str = substr(productname, num_start, num_len);
        unit_found = substr(productname, unit_start, unit_len);

        mg_value = input(num_str, best12.);

        if lowcase(unit_found) in ('microgram','micrograms','mcg') then mg_value = mg_value / 1000;
        else if lowcase(unit_found) = 'g' then mg_value = mg_value * 1000;
        /* if mg, leave as-is */
    end;
    else do;
        mg_value = .;
    end;

    drop unit_found num_str num_start num_len unit_start unit_len patid_re;
run;

/* Sanity check */
proc print data=codelist.nl_standardcare (obs=40);
    var productname mg_value;
run;

proc sql;
    select count(*) as n_total,
           sum(mg_value is not missing) as n_populated,
           sum(mg_value is missing) as n_missing
    from codelist.nl_standardcare;
quit;
