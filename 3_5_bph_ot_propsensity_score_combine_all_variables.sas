
*************************************************************************************************************************;
/* 3. OT: GENERATE MOST RECENT BMI VALUE BEFORE OR ON EACH INTERVAL_WINDOW_START (i.e time-varying) */
*************************************************************************************************************************;

*** Read in episode file from R;




proc sql;
   create table work.bmi_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.bmidate)  as bmi_recent_date         /* latest BMI date before window_start*/
   from    output.lisinopril_ot   as o
   left join
           output.bmi_all         as b
     on    o.patid  = b.patid
    and    b.bmidate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.lisinopril_ot_bmi as
   select  o.*                                   /* all original variables   */                
         , b.bmi        as bmi_value
   from   output.lisinopril_ot   as o            /* original interval table  */
   left join work.bmi_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join output.bmi_all       as b
          on  l.patid          = b.patid
          and l.bmi_recent_date = b.bmidate
   order by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table work.bmi_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.bmidate)  as bmi_recent_date         /* latest BMI date before window_start*/
   from    output.amlodipine_ot   as o
   left join
           output.bmi_all         as b
     on    o.patid  = b.patid
    and    b.bmidate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.amlodipine_ot_bmi as
   select  o.*                                   /* all original variables   */                
         , b.bmi        as bmi_value
   from   output.amlodipine_ot   as o            /* original interval table  */
   left join work.bmi_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join output.bmi_all       as b
          on  l.patid          = b.patid
          and l.bmi_recent_date = b.bmidate
   order by o.patid,
            o.interval_window_start;
quit;



*************************************************************************************************************************;
/* 3. OT: GENERATE MOST RECENT SMOKING VALUE BEFORE OR ON EACH INTERVAL_WINDOW_START (i.e time-varying) */
*************************************************************************************************************************;


proc sql;
   create table work.smk_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.eventdate)  as smk_recent_date
   from    output.lisinopril_ot_bmi   as o
   left join
           work.smk_unique         as b
     on    o.patid  = b.patid
    and    b.eventdate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.lisinopril_ot_bmi_smk as
   select  o.*                                   /* all original variables   */                
         , COALESCE(b.smk_status, 'UNKNOWN') AS smk_status
   from   output.lisinopril_ot_bmi   as o            /* original interval table  */
   left join work.smk_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join work.smk_unique       as b
          on  l.patid          = b.patid
          and l.smk_recent_date = b.eventdate
   order by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table work.smk_latest_ot as
   select  o.patid,
           o.interval_window_start,
           max(b.eventdate)  as smk_recent_date
   from    output.amlodipine_ot_bmi   as o
   left join
           work.smk_unique         as b
     on    o.patid  = b.patid
    and    b.eventdate <= o.interval_window_start
   group by o.patid,
            o.interval_window_start;
quit;

proc sql;
   create table output.amlodipine_ot_bmi_smk as
   select  o.*                                   /* all original variables   */                
         , COALESCE(b.smk_status, 'UNKNOWN') AS smk_status
   from   output.amlodipine_ot_bmi   as o            /* original interval table  */
   left join work.smk_latest_ot  as l
          on  o.patid                = l.patid
          and o.interval_window_start = l.interval_window_start
   left join work.smk_unique       as b
          on  l.patid          = b.patid
          and l.smk_recent_date = b.eventdate
   order by o.patid,
            o.interval_window_start;
quit;



