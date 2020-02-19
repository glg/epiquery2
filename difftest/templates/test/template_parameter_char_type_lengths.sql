/*
executionMasks:
  a_valid_bitmask: 1

--@myParam1 varchar
--@myParam2 varchar(12)
--@myParam3 varchar(256)
--@myParam4 varchar(7002)
--@myParam5 varchar
--@myParam6 varchar
--@myParam7 varchar(max)


*/
  select 
    -- this relies on the knowledge that epiquery prepends a comment to the exeucting query that contains the
    -- template path information. So we're taking everything up to the template path that epi is prepending
    -- thus in the case of a parameterized query (executed via sp_executesql) this first portion will be the param 
    -- declaration
    LEFT(st.text, CHARINDEX('-- ', st.text)-1) queryParamText
  from
    sys.dm_exec_requests as er
    cross apply sys.dm_exec_query_plan(er.plan_handle) as qp
    cross apply sys.dm_exec_sql_text(er.plan_handle) as st
  where 
   session_id = @@spid