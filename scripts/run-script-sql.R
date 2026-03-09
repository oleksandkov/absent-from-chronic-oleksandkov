library(duckdb)
library(DBI)

setwd("C:/Users/muaro/Documents/GitHub/absent-from-chronic-oleksandkov")
sink("scripts/sql-output.txt", split = TRUE)  # tee: write to file AND console
on.exit(sink(), add = TRUE)

con <- dbConnect(duckdb(), database = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE))

run_ddl <- function(label, sql) {
  tryCatch({
    dbExecute(con, sql)
    cat(sprintf("[OK]  %s\n", label))
  }, error = function(e) cat(sprintf("[ERR] %s: %s\n", label, conditionMessage(e))))
}

run_qry <- function(label, sql, print_n = 10) {
  tryCatch({
    res <- dbGetQuery(con, sql)
    cat(sprintf("\n=== %s ===\n", label))
    print(head(res, print_n))
    if (nrow(res) > print_n) cat(sprintf("  ... %d more rows\n", nrow(res) - print_n))
    invisible(res)
  }, error = function(e) cat(sprintf("[ERR] %s: %s\n", label, conditionMessage(e))))
}

cat("--- SECTION 0: Parquet extension ---\n")
run_ddl("INSTALL parquet", "INSTALL parquet")
run_ddl("LOAD parquet",    "LOAD parquet")

cat("\n--- SECTION 1: Parquet file existence ---\n")
f10 <- "data-private/derived/cchs-1-raw/cchs_2010_raw.parquet"
f14 <- "data-private/derived/cchs-1-raw/cchs_2014_raw.parquet"
cat(sprintf("cchs_2010_raw.parquet exists: %s\n", file.exists(f10)))
cat(sprintf("cchs_2014_raw.parquet exists: %s\n", file.exists(f14)))

cat("\n--- SECTION 1: Create views ---\n")
run_ddl("View cchs_2010_raw",
  sprintf("CREATE OR REPLACE TEMP VIEW cchs_2010_raw AS SELECT * FROM read_parquet('%s')", f10))
run_ddl("View cchs_2014_raw",
  sprintf("CREATE OR REPLACE TEMP VIEW cchs_2014_raw AS SELECT * FROM read_parquet('%s')", f14))

cat("\n--- SECTION 2: Row counts ---\n")
run_qry("Row counts",
  "SELECT 'cchs_2010_raw' AS table_name, COUNT(*) AS n_rows FROM cchs_2010_raw
   UNION ALL
   SELECT 'cchs_2014_raw' AS table_name, COUNT(*) AS n_rows FROM cchs_2014_raw")

run_qry("Column counts",
  "SELECT table_name, COUNT(*) AS n_columns
   FROM information_schema.columns
   WHERE table_schema = 'main'
     AND table_name IN ('cchs_2010_raw', 'cchs_2014_raw')
   GROUP BY table_name ORDER BY table_name")

cat("\n--- SECTION 3: Schema (DESCRIBE) ---\n")
run_qry("DESCRIBE cchs_2010_raw", "DESCRIBE cchs_2010_raw", print_n = 999)
run_qry("DESCRIBE cchs_2014_raw", "DESCRIBE cchs_2014_raw", print_n = 999)

cat("\n--- SECTION 3: Parquet schema ---\n")
run_qry("parquet_schema 2010",
  sprintf("SELECT * FROM parquet_schema('%s')", f10), print_n = 999)
run_qry("parquet_schema 2014",
  sprintf("SELECT * FROM parquet_schema('%s')", f14), print_n = 999)

cat("\n--- SECTION 4: Parquet metadata ---\n")
run_qry("parquet_metadata 2010",
  sprintf("SELECT * FROM parquet_metadata('%s')", f10))
run_qry("parquet_metadata 2014",
  sprintf("SELECT * FROM parquet_metadata('%s')", f14))

cat("\n--- SECTION 5: SUMMARIZE (column profiles) ---\n")
run_qry("SUMMARIZE cchs_2010_raw", "SUMMARIZE SELECT * FROM cchs_2010_raw", print_n = 999)
run_qry("SUMMARIZE cchs_2014_raw", "SUMMARIZE SELECT * FROM cchs_2014_raw", print_n = 999)

cat("\n--- SECTION 6: Preview records ---\n")
run_qry("cchs_2010_raw LIMIT 5", "SELECT * FROM cchs_2010_raw LIMIT 5")
run_qry("cchs_2014_raw LIMIT 5", "SELECT * FROM cchs_2014_raw LIMIT 5")

cat("\n--- SECTION 7: Column comparison 2010 vs 2014 ---\n")
run_qry("Column comparison", "
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
  ORDER BY status, column_name
", print_n = 999)

cat("\n--- SECTION 9: First 200 rows of wts_m (both years) ---\n")
run_qry("wts_m - cchs_2010_raw (first 200)",
  "SELECT 'cchs_2010' AS survey_year, wts_m FROM cchs_2010_raw LIMIT 200",
  print_n = 200)
run_qry("wts_m - cchs_2014_raw (first 200)",
  "SELECT 'cchs_2014' AS survey_year, wts_m FROM cchs_2014_raw LIMIT 200",
  print_n = 200)

cat("\nDone.\n")
