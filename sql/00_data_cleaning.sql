/* ============================================================
   DATA CLEANING: rides_raw -> rides_clean
   Source: https://www.kaggle.com/datasets/yashdevladdha/uber-ride-analytics-dashboard
   NCR ride bookings dataset (Kaggle), 150,000 raw rows
   Author: Mustafa Egeh
   ============================================================ */


/* ------------------------------------------------------------
   STEP 0. STAGING TABLE (matches the raw source structure)
   Raw file has 21 columns, including 6 redundant status/reason
   columns and IDs with literal embedded quote characters, e.g.
   the text stored is literally  "CNR5884300"  (quotes included).
   ------------------------------------------------------------ */

CREATE TABLE rides_raw (
    ride_date                text,
    ride_time                text,
    booking_id                text,
    booking_status            text,
    customer_id                text,
    vehicle_type            text,
    pickup_location            text,
    drop_location            text,
    avg_vtat                text,
    avg_ctat                text,
    cancelled_by_customer    text,
    customer_cancel_reason    text,
    cancelled_by_driver        text,
    driver_cancel_reason    text,
    incomplete_rides        text,
    incomplete_rides_reason    text,
    booking_value            text,
    ride_distance            text,
    driver_ratings            text,
    customer_rating            text,
    payment_method            text
);
-- (loaded via \copy from the raw CSV — every column is left as text
--  at this stage, since the source file mixes literal 'null' strings
--  into what should be numeric columns, which would otherwise break
--  a typed import.)


/* ------------------------------------------------------------
   STEP 1. PROFILE THE RAW DATA BEFORE TOUCHING IT
   ------------------------------------------------------------ */

-- How many rows, and what does booking_status actually contain?
SELECT booking_status, COUNT(*)
FROM rides_raw
GROUP BY booking_status;
-- Completed: 93,000 | Cancelled by Driver: 27,000 | No Driver Found: 10,500
-- Cancelled by Customer: 10,500 | Incomplete: 9,000  (total 150,000)

-- Are there duplicate booking IDs?
SELECT booking_id, COUNT(*)
FROM rides_raw
GROUP BY booking_id
HAVING COUNT(*) > 1;
-- 1,233 duplicate booking_id values found in the raw 150,000 rows.

-- Confirm the embedded-quote problem on IDs
SELECT booking_id FROM rides_raw LIMIT 3;
-- Returns values like  "CNR5884300"  — the quote characters are part
-- of the string itself, not CSV formatting artifacts.

-- Confirm the literal 'null' string problem
SELECT payment_method, COUNT(*)
FROM rides_raw
GROUP BY payment_method
ORDER BY COUNT(*) DESC;
-- 'null' appears as literal text across every column with missing
-- data, not just payment_method — this is a source-file convention,
-- not a one-off typo.


/* ------------------------------------------------------------
   STEP 2. BUILD rides_clean FROM rides_raw
   - strip embedded quote characters from ID fields
   - convert every literal 'null' string to true NULL
   - cast numeric-looking text columns to numeric/date/time types
   - drop the 6 redundant status/reason columns (booking_status
     alone already encodes this information for analysis purposes)
   - de-duplicate on booking_id, keeping one row per ID
   ------------------------------------------------------------ */

CREATE TABLE rides_clean AS
SELECT
    booking_id,
    booking_status,
    customer_id,
    vehicle_type,
    pickup_location,
    drop_location,
    NULLIF(payment_method, 'null')                    AS payment_method,
    NULLIF(booking_value, 'null')::numeric            AS booking_value,
    NULLIF(avg_vtat, 'null')::numeric                 AS avg_vtat,
    NULLIF(avg_ctat, 'null')::numeric                 AS avg_ctat,
    NULLIF(ride_distance, 'null')::numeric            AS ride_distance,
    NULLIF(driver_ratings, 'null')::numeric           AS driver_ratings,
    NULLIF(customer_rating, 'null')::numeric          AS customer_rating,
    ride_date::date                                    AS ride_date,
    ride_time::time                                    AS ride_time
FROM (
    SELECT
        TRIM(BOTH '"' FROM booking_id)   AS booking_id,
        booking_status,
        TRIM(BOTH '"' FROM customer_id)  AS customer_id,
        vehicle_type,
        pickup_location,
        drop_location,
        payment_method,
        booking_value,
        avg_vtat,
        avg_ctat,
        ride_distance,
        driver_ratings,
        customer_rating,
        ride_date,
        ride_time,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(BOTH '"' FROM booking_id)
            ORDER BY ride_date, ride_time
        ) AS rn
    FROM rides_raw
) deduped
WHERE rn = 1;   -- keeps exactly one row per booking_id, dropping the
                -- 1,233 duplicate rows found during profiling


/* ------------------------------------------------------------
   STEP 3. VERIFY THE CLEANED TABLE
   ------------------------------------------------------------ */

SELECT COUNT(*) FROM rides_clean;                 -- expect 150,000 - 1,233 duplicates
SELECT COUNT(*) FROM rides_clean WHERE booking_id LIKE '%"%';  -- expect 0 — no quotes left
SELECT COUNT(*) FROM rides_clean WHERE payment_method = 'null'; -- expect 0 — no literal 'null' left


/* ------------------------------------------------------------
   NOTE — a known gap, found honestly rather than hidden:
   Despite this cleaning pass, the actual analysis table still
   contained rows where payment_method held the literal text
   'null' rather than a true NULL. This was caught mid-analysis
   (see 01_exploratory_analysis.sql, Section 0) and handled
   defensively with NULLIF() again at query time. Lesson: a
   single cleaning pass doesn't guarantee every downstream query
   is safe — profiling checks are worth repeating before trusting
   an aggregation, not just once at the start of a project.
   ------------------------------------------------------------ */
