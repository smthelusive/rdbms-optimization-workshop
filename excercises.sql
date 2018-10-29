-----optimize query:
explain analyze select * from bar where c1 in (select c1 from foo where c2 like '%100'); --24316.45
-----think as planner:
create index on foo2(c2,c1);
--which query will work the slowest (the highest cost)?
explain analyze select * from foo2 where c1 = 10 and c2 = 'test10';
explain analyze select * from foo2 where c1 = 10;
explain analyze select * from foo2 where c2 = 'test10';
-----the lowest cost wins:
explain analyze select foo.c2 from foo, foo2 where foo2.c2 = 'test4' and foo.c1 = foo2.c1; --15422.29
-----identical query except date range for filtering rows, different plans:
--this:
-- Sort  (cost=43509.92..43523.14 rows=5291 width=20)
--   Sort Key: (date(charges.date_created))
--   ->  HashAggregate  (cost=43116.55..43182.69 rows=5291 width=20)
--         ->  Hash Join  (cost=186.57..43076.07 rows=5397 width=20)
--               Hash Cond: ((charges.account_id)::text = (accounts.id)::text)
--               ->  Seq Scan on charges  (cost=0.00..42774.71 rows=5409 width=41)
--                     Filter: ((NOT deleted) AND (date_created > '2015-03-16 00:00:00'::timestamp without time zone)
--                                            AND (date_created < '2015-03-24 00:00:00'::timestamp without time zone))
--               ->  Hash  (cost=121.32..121.32 rows=5220 width=21)
--                     ->  Seq Scan on accounts  (cost=0.00..121.32 rows=5220 width=21)
--                           Filter: (NOT admin)
-- --and that:
-- GroupAggregate  (cost=42961.29..42961.32 rows=1 width=20)
--   ->  Sort  (cost=42961.29..42961.30 rows=1 width=20)
--         Sort Key: (date(charges.date_created)), charges.type
--         ->  Nested Loop  (cost=0.00..42961.28 rows=1 width=20)
--               Join Filter: ((charges.account_id)::text = (accounts.id)::text)
--               ->  Seq Scan on charges  (cost=0.00..42774.71 rows=1 width=41)
--                     Filter: ((NOT deleted) AND (date_created > '2015-03-17 00:00:00'::timestamp without time zone)
--                                            AND (date_created < '2015-03-22 00:00:00'::timestamp without time zone))
--               ->  Seq Scan on accounts  (cost=0.00..121.32 rows=5220 width=21)
--                     Filter: (NOT admin)
--what would be the solution?
-----make the query work faster?
explain (analyze, buffers) select * from foo where c1 > 1000;
--                                  QUERY PLAN
-- --------------------------------------------------------------
--  Seq Scan on foo  (cost=0.00..20834.00 rows=999014 width=37)
--                   (actual time=0.216..188.488 rows=999000 loops=1)
--    Filter: (c1 > 1000)
--    Rows Removed by Filter: 1000
--    Buffers: shared hit=8334
--  Planning time: 0.067 ms
--  Execution time: 281.589 ms
-- (6 rows)
