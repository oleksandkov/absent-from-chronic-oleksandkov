-- Explore CCHS raw Parquet files (DuckDB SQL)
-- Files:
--   data-private/derived/cchs-1-raw/cchs_2010_raw.parquet
--   data-private/derived/cchs-1-raw/cchs_2014_raw.parquet

-- 0) Enable parquet support (safe to run more than once)
INSTALL parquet;
LOAD parquet;

-- 1) Register the Parquet files as temporary views
CREATE OR REPLACE TEMP VIEW cchs_2010_raw AS
SELECT *
FROM read_parquet('data-private/derived/cchs-1-raw/cchs_2010_raw.parquet');

CREATE OR REPLACE TEMP VIEW cchs_2014_raw AS
SELECT *
FROM read_parquet('data-private/derived/cchs-1-raw/cchs_2014_raw.parquet');

-- 2) Quick inventory
SHOW TABLES;

-- Row counts
SELECT 'cchs_2010_raw' AS table_name, COUNT(*) AS n_rows FROM cchs_2010_raw
UNION ALL
SELECT 'cchs_2014_raw' AS table_name, COUNT(*) AS n_rows FROM cchs_2014_raw;

-- Column counts
SELECT table_name, COUNT(*) AS n_columns
FROM information_schema.columns
WHERE table_schema = 'main'
	AND table_name IN ('cchs_2010_raw', 'cchs_2014_raw')
GROUP BY table_name
ORDER BY table_name;

-- 3) Schema inspection
DESCRIBE cchs_2010_raw;
DESCRIBE cchs_2014_raw;

-- File-level parquet schema (physical + logical metadata)
SELECT *
FROM parquet_schema('data-private/derived/cchs-1-raw/cchs_2010_raw.parquet');

SELECT *
FROM parquet_schema('data-private/derived/cchs-1-raw/cchs_2014_raw.parquet');

-- 4) Metadata inspection (row groups, compression, stats availability)
SELECT *
FROM parquet_metadata('data-private/derived/cchs-1-raw/cchs_2010_raw.parquet');

SELECT *
FROM parquet_metadata('data-private/derived/cchs-1-raw/cchs_2014_raw.parquet');

-- 5) Column profiling summary (nulls, min/max, distinct-ish stats)
SUMMARIZE SELECT * FROM cchs_2010_raw;
SUMMARIZE SELECT * FROM cchs_2014_raw;

-- 6) Preview records
SELECT * FROM cchs_2010_raw LIMIT 25;
SELECT * FROM cchs_2014_raw LIMIT 25;

-- 7) Compare shared column names between 2010 and 2014
WITH c2010 AS (
	SELECT column_name, data_type
	FROM information_schema.columns
	WHERE table_schema = 'main' AND table_name = 'cchs_2010_raw'
),
c2014 AS (
	SELECT column_name, data_type
	FROM information_schema.columns
	WHERE table_schema = 'main' AND table_name = 'cchs_2014_raw'
)
SELECT
	COALESCE(c2010.column_name, c2014.column_name) AS column_name,
	c2010.data_type AS type_2010,
	c2014.data_type AS type_2014,
	CASE
		WHEN c2010.column_name IS NULL THEN 'only_2014'
		WHEN c2014.column_name IS NULL THEN 'only_2010'
		WHEN c2010.data_type <> c2014.data_type THEN 'type_mismatch'
		ELSE 'match'
	END AS status
FROM c2010
FULL OUTER JOIN c2014 USING (column_name)
ORDER BY status, column_name;

-- 8) Optional template: replace YOUR_COLUMN with a real column name
-- SELECT YOUR_COLUMN, COUNT(*) AS n
-- FROM cchs_2010_raw
-- GROUP BY YOUR_COLUMN
-- ORDER BY n DESC
-- LIMIT 20;

-- 9) First 200 rows of wts_m from both tables (pooled, tagged by year)
SELECT 'cchs_2010' AS survey_year, wts_m FROM cchs_2010_raw LIMIT 200
UNION ALL
SELECT 'cchs_2014' AS survey_year, wts_m FROM cchs_2014_raw LIMIT 200;

