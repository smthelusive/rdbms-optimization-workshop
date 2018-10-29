-- test data:
create table foo (c1 integer, c2 text);
insert into foo
  select i, md5(random()::text)
  from generate_series(1, 1000000) as i;
---------------------------------------------------------ANALYZE---------------------------------------------------------
explain select * from foo;
-- let's insert 10 more rows:
insert into foo
  select i, md5(random()::text)
  from generate_series(1, 10) as i;
explain select * from foo; --old statistics
-- to update statistics we do analyze:
analyze foo;
explain select * from foo;
-- so analyze:
-- reads some amount of rows chosen randomly
-- gathers statistics of values for every column of the table
-- the amount of rows to be read by analyze depends on parameter default_statistics_target
-- !!this query will be actually executed:
explain analyze select * from foo;
---------------------------------------------------------CACHE-----------------------------------------------------------
--stop postgres,
--sync && sudo purge
--start postgres
explain (analyze, buffers) select * from foo;
--cache is empty, table is read completely from disk (shared read=8334). for that it needed to read 8334 blocks.
--repeat query:
explain (analyze, buffers) select * from foo;
--shared hit=32 - number of blocks read from cache. postgres fills it's cache after every query.
--read from cache is faster than from disk
--cache size is defined by constant shared_buffers in config file postgresql.conf
---------------------------------------------------------WHERE-----------------------------------------------------------
--query huge part of table:
explain select * from foo where c1 > 500; --seq Scan
--lets create index:
create index on foo(c1);
--try again:
explain select * from foo where c1 > 500; -- seq scan anyway
explain analyze select * from foo where c1 > 500;
-- so, filtered 510 rows out of a million. had to read more than 99,9% of table
--let's try to force use indexes:
set enable_seqscan to off;
explain analyze select * from foo where c1 > 500;
--if we query almost all table use of index makes cost greater and time as well. planner is not a fool :)
--set back:
set enable_seqscan to on;
----query small part of table:
explain select * from foo where c1 < 500; --index is used
--let's try more complex condition:
explain select * from foo where c1 < 500 and c2 like 'abcd%'; -- index used
--what will happen now?
explain analyze select * from foo where c2 like 'abcd%';
----------------------------------------------------------------INDEX ONLY-------------------------------------------------
-- if we do not go to table for the rest of values and select only indexed one:
explain select c1 from foo where c1 < 500; --so it is faster (index only scan)
---------------------------------------------Bitmap Heap Scan - bitmap index scan------------------------------------------
--used when postgresql wants to make sure that records still exist (so it goes to database)
--when number of selected rows is quite big
--some new test data
create table foo2 (c1 integer, c2 text);
insert into foo2
  select i, 'test'||i::text
  from generate_series(1, 20000) as i;
create unique index on foo2(c2);

explain analyze select c1, c2 from foo2 where c1 < 10000 and c2 < 'test100';
---------------------------------------------------------PARALLEL SEQ SCAN--------------------------------------------------
explain analyze select * from foo where c2 like 'abcd%';
---------------------------------------------------------ORDER BY------------------------------------------------------------
--let's drop the index
drop index foo_c1_idx;
explain analyze select * from foo order by c1;
--first seq scan and then sort
--Sort Method: external merge  Disk -> for sorting was used tmp file on the disk of size 15176kB.
explain (analyze, buffers) select * from foo order by c1;
--temp read=2062 written=2069 blocks (written and read from tmp file)
--operations in memory are faster:
set work_mem to '200MB';
explain analyze select * from foo order by c1;
--Sort Method: quicksort. all sorting was done in memory
create index on foo(c1);
explain analyze select * from foo order by c1; --index scan
-------------------------------------------------------------LIMIT------------------------------------------------------------
explain (analyze, buffers) select * from foo where c2 like 'ab%'; --seq scan with filter
explain (analyze, buffers) select * from foo where c2 like 'ab%' limit 10; --scan ends when we have 10 records
--------------------------------------------------------------JOIN------------------------------------------------------------
create table bar (c1 integer, c2 boolean);
insert into bar
  select i, i%2=1
  from generate_series(1, 500000) as i;
analyze bar; --gather statistics

explain (analyze) select * from foo join bar on foo.c1 = bar.c1; --hash join
--1.seq scan of bar, for it's every row hash is calculated.
--2. same for foo.
--3. then compared (Hash Join) by hash condition
--Memory Usage: 22163kB -- for hashes of bar
--add index:
create index on bar(c1);
explain analyze select * from foo join bar on foo.c1 = bar.c1; --merge join
--much faster!
--------------------------------------------------------------left join--------------------------------------------------------
explain analyze select * from foo left join bar on foo.c1 = bar.c1; --seq scan??
--what will happen if we turn off seq scan:
set enable_seqscan TO off;
explain analyze select * from foo left join bar on foo.c1 = bar.c1;
--planner thinks it will cost more than seq scan
--this can happen with quite big work_mem (we increased it)
--if there is less memory he will change his mind:
set work_mem to '15MB';
set enable_seqscan to on;
explain analyze select * from foo left join bar on foo.c1 = bar.c1;
--what will happen now if we turn off index scan?
set enable_indexscan to off;
explain analyze select * from foo left join bar on foo.c1 = bar.c1;
--cost is much bigger
--reason is Batches: 2
--all cache didn't fit in the memory so it was split on two parts
--------------------------------------------------------------nested loop-----------------------------------------------------
explain analyse select * from foo, bar where foo.c2 = 'test100' and foo.c1 = bar.c1;
explain analyse select * from foo join bar on foo.c1 = bar.c1 where foo.c2 = 'test100';
--Hash joins can not look up rows from the inner row source based on values retrieved from the outer row source,
--but nested loops can
--nested loops work well when one side is really small
