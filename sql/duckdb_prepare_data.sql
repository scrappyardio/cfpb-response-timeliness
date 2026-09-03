-- ============================================================
-- CFPB Consumer Complaints — data preparation with DuckDB
--
-- Source: CFPB Consumer Complaint Database (full export)
--         https://www.consumerfinance.gov/data-research/consumer-complaints/
--         ~17.4M rows, ~9 GB uncompressed CSV
--
-- Output: complaints_filtered.parquet — 1,145,121 rows, ~254 MB
--         Feeds the Power BI model.
--
-- Run from the folder containing complaints.csv:
--   cd /d E:\...\consumer_finance
--   duckdb
-- ============================================================


-- ------------------------------------------------------------
-- 1. Inspect the schema without reading the whole file
-- ------------------------------------------------------------
-- DuckDB reads only what it needs from disk, so this returns
-- instantly even on a 9 GB file.

DESCRIBE SELECT * FROM read_csv_auto('complaints.csv', ignore_errors=true) LIMIT 1;

-- Columns returned:
--   Date received                  date
--   Product                        varchar
--   Sub-product                    varchar
--   Issue                          varchar
--   Sub-issue                      varchar
--   Consumer complaint narrative   varchar
--   Company public response        varchar
--   Company                        varchar
--   State                          varchar
--   ZIP code                       varchar
--   Tags                           varchar
--   Submitted via                  varchar
--   Date sent to company           date
--   Company response to consumer   varchar
--   Timely response?               boolean
--   Complaint ID                   bigint
--
-- Note: 'Consumer disputed?' is NOT present. CFPB stopped
-- publishing that field after 2017, so any dispute-rate metric
-- has to be replaced (see Monetary Relief Rate in the model).


-- ------------------------------------------------------------
-- 2. Filter to the analysis scope and write Parquet
-- ------------------------------------------------------------
-- Scope decisions:
--   * 2024-01-01 onward — two full years plus a partial 2026,
--     enough for year-over-year comparison.
--   * Four products only. 'Credit reporting' (11.9M rows) is
--     excluded on purpose: it would outweigh everything else
--     5-10x and make every breakdown unreadable.
--   * Parquet, not CSV — types are preserved, file is ~5x
--     smaller, and Power BI loads it without type guessing.

COPY (
    SELECT *
    FROM read_csv_auto('complaints.csv', ignore_errors=true)
    WHERE "Date received" >= '2024-01-01'
      AND "Product" IN (
            'Debt collection',
            'Credit card',
            'Checking or savings account',
            'Mortgage'
          )
) TO 'complaints_filtered.parquet' (FORMAT PARQUET);


-- ------------------------------------------------------------
-- 3. Profile the result — completeness of key fields
-- ------------------------------------------------------------
-- COUNT(col) skips NULLs, COUNT(*) does not, so the gap between
-- them is the number of missing values. Run this BEFORE building
-- the model: a metric built on a half-empty column is worthless.

SELECT
    COUNT(*)                               AS total,
    COUNT("Date sent to company")          AS has_sent_date,
    COUNT("State")                         AS has_state,
    COUNT("Company response to consumer")  AS has_response,
    COUNT("Sub-issue")                     AS has_subissue
FROM 'complaints_filtered.parquet';


-- ------------------------------------------------------------
-- 4. Distribution checks
-- ------------------------------------------------------------

-- Row counts per product. Confirms the filter worked and shows
-- the imbalance: debt collection is ~57% of the filtered set,
-- so comparisons must use rates, not absolute counts.
SELECT "Product", COUNT(*) AS n
FROM 'complaints_filtered.parquet'
GROUP BY 1
ORDER BY n DESC;

-- Possible outcomes of a complaint. Drives the
-- Monetary Relief Rate measure — the exact string has to match.
SELECT "Company response to consumer", COUNT(*) AS n
FROM 'complaints_filtered.parquet'
GROUP BY 1
ORDER BY n DESC;


-- ------------------------------------------------------------
-- 5. Optional — drop the narrative column
-- ------------------------------------------------------------
-- 'Consumer complaint narrative' is free text, often empty, and
-- dominates model memory. Unused by the dashboard.

-- COPY (
--     SELECT * EXCLUDE ("Consumer complaint narrative")
--     FROM 'complaints_filtered.parquet'
-- ) TO 'complaints_clean.parquet' (FORMAT PARQUET);


-- ------------------------------------------------------------
-- 6. Optional — CSV export
-- ------------------------------------------------------------
-- Only needed to load into a database that cannot read Parquet
-- (e.g. SQL Server). Power BI reads Parquet directly.

-- COPY 'complaints_filtered.parquet'
--   TO 'complaints_clean.csv' (FORMAT CSV, HEADER);


-- ------------------------------------------------------------
-- Utility
-- ------------------------------------------------------------
-- List files in the current working directory — useful when
-- DuckDB reports "No files found" and you need to confirm
-- where the session actually started.
--   SELECT * FROM glob('*');
--
-- Exit:
--   .quit
