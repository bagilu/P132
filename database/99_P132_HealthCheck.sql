-- Read-only P132 health check
select table_name from information_schema.tables where table_schema='public' and table_name like 'TblP132%' order by table_name;
select routine_name from information_schema.routines where routine_schema='public' and routine_name like 'P132_%' order by routine_name;
select c.relname as table_name,c.relrowsecurity as rls_enabled from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'TblP132%' order by c.relname;
-- Cross-project reference scan: expected result = zero rows.
select p.proname,pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'P132_%' and pg_get_functiondef(p.oid) ~ 'TblP(?!132)[0-9]+';
