/**************************************************************************/
/* Extract mg_value from the "strength" column of a drug codelist         */
/*                                                                          */
/* Works for strength formats like:                                        */
/*   400.000microgram          -> 0.4 mg                                   */
/*   80.000microgram/1.000ml   -> 0.08 mg (per Sage's earlier decision:    */
/*                                take the first number as per-unit dose)  */
/*   10.000mg                  -> 10 mg                                    */
/*   1.000gram                 -> 1000 mg                                  */
/*                                                                          */
/* Just change the libname/dataset in the SET statement to reuse for any   */
/* codelist with the same strength column format.                          */
/**************************************************************************/

data want;
    set codelist.tamsulosin_codes;  /* <- change to your codelist */
    length unit_found $20;

    if not missing(strength) then do;
        /* First number in the string (handles decimals) */
        mg_value = input(scan(strength, 1, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ/'), best12.);

        /* First unit word: letters immediately after the first number */
        unit_found = scan(compress(strength, '0123456789. '), 1, '/');

        /* Convert everything to mg */
        if lowcase(unit_found) in ('microgram', 'micrograms', 'mcg') then mg_value = mg_value / 1000;
        else if lowcase(unit_found) in ('gram', 'g') then mg_value = mg_value * 1000;
        /* mg stays as-is */
    end;

    drop unit_found;
run;

/* Sanity check */
proc print data=want (obs=30);
    var productname strength mg_value;
run;
