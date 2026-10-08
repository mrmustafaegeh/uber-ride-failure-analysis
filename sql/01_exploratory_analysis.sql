/* ============================================================
   UBER RIDE-HAILING DATA — EXPLORATORY ANALYSIS
   Table: rides_clean (PostgreSQL)
   Author: Mustafa Egeh
   ============================================================ */


/* ------------------------------------------------------------
   0. DATA QUALITY CHECKS
   Before trusting any aggregation, confirm what values actually
   exist in key columns rather than assuming.
   ------------------------------------------------------------ */

-- What booking_status values actually exist? (avoids guessing 'Cancelled')
SELECT DISTINCT booking_status
FROM rides_clean;
-- Result: 'Completed', 'Cancelled by Customer', 'Cancelled by Driver',
--         'Incomplete', 'No Driver Found'

-- Is payment_method missing (NULL) only for non-completed rides,
-- or is there a literal text-string data quality issue too?
SELECT payment_method, COUNT(*)
FROM rides_clean
GROUP BY payment_method
ORDER BY COUNT(*) DESC;
-- Finding: a literal string 'null' exists in this column, distinct
-- from a true SQL NULL — must be handled with NULLIF() before grouping.

-- Confirm ratings are only ever missing on non-completed rides
SELECT booking_status, COUNT(*), COUNT(driver_ratings), COUNT(customer_rating)
FROM rides_clean
GROUP BY booking_status;
-- Finding: cancelled / no-driver-found rides have 0 ratings (expected —
-- a ride that never completed can't be rated).


/* ------------------------------------------------------------
   Q1. OVERALL PERFORMANCE SNAPSHOT
   Baseline booking value and distance for completed rides.
   ------------------------------------------------------------ */

SELECT
    AVG(booking_value) AS avg_booking_value,
    AVG(ride_distance)  AS avg_ride_distance
FROM rides_clean
WHERE booking_status = 'Completed';


/* ------------------------------------------------------------
   Q2. VEHICLE TYPE BREAKDOWN
   Average value and distance per vehicle type, completed rides only.
   ------------------------------------------------------------ */

SELECT
    vehicle_type,
    ROUND(AVG(booking_value), 2)   AS avg_booking_value,
    ROUND(AVG(ride_distance), 2)   AS avg_ride_distance
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY vehicle_type
ORDER BY avg_booking_value DESC;
-- Finding: avg booking value and avg distance are both nearly flat
-- across vehicle types (~500-512 value, ~24.5-24.8 km distance) —
-- fare does not appear to be driven mainly by distance.


/* ------------------------------------------------------------
   Q3. TIME-BASED PATTERNS
   3a. Ride volume + revenue by hour of day
   3b. Ride volume + revenue by day of week
   ------------------------------------------------------------ */

-- 3a. Hourly pattern
SELECT
    EXTRACT(hour FROM ride_time) AS hour_of_day,
    COUNT(*)                     AS ride_count,
    SUM(booking_value)           AS total_revenue
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY hour_of_day
ORDER BY hour_of_day;
-- Finding: ride volume peaks at hour 18 (7,617 rides), but revenue
-- peaks one hour later, at hour 19 (~$3.91M) — volume and revenue
-- peaks are NOT the same hour.

-- 3b. Day-of-week pattern
SELECT
    EXTRACT(dow FROM ride_date) AS day_of_week,   -- 0 = Sunday ... 6 = Saturday
    COUNT(*)                    AS ride_count,
    SUM(booking_value)          AS total_revenue
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY day_of_week
ORDER BY day_of_week;
-- Finding: ride COUNT is nearly flat across all 7 days (~13,200-13,450),
-- but weekend REVENUE (Sun/Sat) is notably higher (~$8.7-8.8M) than
-- weekday revenue (~$5.8-6.1M) despite similar ride counts.


/* ------------------------------------------------------------
   Q4. CANCELLATION PATTERNS BY VEHICLE TYPE
   No WHERE filter here — need both cancelled and completed rows
   in the same query to calculate a meaningful rate.
   ------------------------------------------------------------ */

SELECT
    vehicle_type,
    COUNT(*) AS total_rides,
    COUNT(CASE WHEN booking_status IN
        ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END) AS cancelled_rides,
    ROUND(
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*), 2
    ) AS cancellation_rate_pct
FROM rides_clean
GROUP BY vehicle_type
ORDER BY total_rides DESC;
-- Finding: cancellation rate is essentially flat across vehicle types,
-- clustering around 24-25% for every type. Vehicle type does not
-- meaningfully predict cancellation risk.


/* ------------------------------------------------------------
   Q5. TOP LOCATIONS
   5a. By ride volume
   5b. By total revenue
   5c. By cancellation rate (only locations with enough volume
       to make the rate meaningful)
   ------------------------------------------------------------ */

-- 5a. Top 10 pickup locations by ride count
SELECT pickup_location, COUNT(*) AS ride_count
FROM rides_clean
GROUP BY pickup_location
ORDER BY ride_count DESC
LIMIT 10;

-- 5b. Top 10 pickup locations by total revenue (completed rides only)
SELECT pickup_location, ROUND(SUM(booking_value), 2) AS total_revenue
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY pickup_location
ORDER BY total_revenue DESC
LIMIT 10;
-- Finding: the top-revenue list is NOT identical to the top-ride-count
-- list — some locations (e.g. Pataudi Chowk, Tughlakabad, Subhash Chowk)
-- rank high on revenue without being the single busiest by ride count.

-- 5c. Locations with the highest cancellation rate (min. 500 rides)
SELECT
    pickup_location,
    COUNT(*) AS total_rides,
    ROUND(
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*), 2
    ) AS cancellation_rate_pct
FROM rides_clean
GROUP BY pickup_location
HAVING COUNT(*) > 500
ORDER BY cancellation_rate_pct DESC
LIMIT 10;
-- Finding: unlike vehicle type, LOCATION does show real variation.
-- Akshardham and Vinobapuri both cancel ~29-30% of rides, meaningfully
-- above the ~24-25% dataset-wide average — a genuine, actionable outlier.


/* ------------------------------------------------------------
   Q6. WEEKEND VS WEEKDAY DEEP-DIVE
   Does higher weekend revenue come from longer trips or
   higher prices per trip?
   ------------------------------------------------------------ */

SELECT
    CASE
        WHEN EXTRACT(DOW FROM ride_date) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type,
    COUNT(*) AS total_rides,
    ROUND(AVG(booking_value), 2) AS avg_booking_value,
    ROUND(AVG(ride_distance), 2) AS avg_ride_distance
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY day_type
ORDER BY day_type;
-- Finding: ride distance is nearly identical (25.98 vs 26.05 km),
-- but avg booking value is 46% higher on weekends (655.51 vs 448.67).
-- The weekend revenue gap is driven by price, not trip length.


/* ------------------------------------------------------------
   Q7. WEEKEND VEHICLE MIX
   Does higher weekend revenue come from more premium bookings?
   ------------------------------------------------------------ */

SELECT
    CASE
        WHEN EXTRACT(DOW FROM ride_date) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type,
    vehicle_type,
    COUNT(*) AS ride_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (
        PARTITION BY CASE
            WHEN EXTRACT(DOW FROM ride_date) IN (0, 6) THEN 'Weekend'
            ELSE 'Weekday'
        END
    ), 1) AS pct_of_day_type
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY day_type, vehicle_type
ORDER BY day_type, ride_count DESC;
-- Finding: vehicle mix is nearly identical on weekends vs weekdays
-- (premium vehicles ~14.8% vs ~15.2%). Vehicle mix does NOT explain
-- the 46% weekend price gap — dynamic/surge pricing is the likely driver.


/* ------------------------------------------------------------
   Q8. OUTLIER LOCATIONS — WAIT TIMES & CANCELLATION MIX
   Is Akshardham/Vinobapuri a supply (wait time) or driver issue?
   ------------------------------------------------------------ */

SELECT
    pickup_location,
    COUNT(*) AS total_rides,
    ROUND(AVG(avg_vtat), 2) AS avg_vtat_min,
    ROUND(AVG(avg_ctat), 2) AS avg_ctat_min,
    ROUND(
        COUNT(CASE WHEN booking_status = 'Cancelled by Customer' THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS customer_cancel_pct,
    ROUND(
        COUNT(CASE WHEN booking_status = 'Cancelled by Driver' THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS driver_cancel_pct,
    ROUND(
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS total_cancel_pct
FROM rides_clean
WHERE pickup_location IN ('Akshardham', 'Vinobapuri')
GROUP BY pickup_location

UNION ALL

SELECT
    'Fleet average' AS pickup_location,
    COUNT(*) AS total_rides,
    ROUND(AVG(avg_vtat), 2) AS avg_vtat_min,
    ROUND(AVG(avg_ctat), 2) AS avg_ctat_min,
    ROUND(
        COUNT(CASE WHEN booking_status = 'Cancelled by Customer' THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS customer_cancel_pct,
    ROUND(
        COUNT(CASE WHEN booking_status = 'Cancelled by Driver' THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS driver_cancel_pct,
    ROUND(
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*), 1
    ) AS total_cancel_pct
FROM rides_clean;
-- Finding: wait times at both outlier locations match the fleet
-- average (~8.4 min VTAT). The signal is cancellation TYPE: driver
-- cancellations run ~20-22% vs ~8-9% customer — roughly 2.5× the
-- customer rate. This points to driver-side supply/acceptance issues,
-- not longer passenger wait times.


/* ------------------------------------------------------------
   Q9. FARE VS DISTANCE CORRELATION
   Is booking value actually driven by trip distance?
   ------------------------------------------------------------ */

SELECT
    ROUND(CORR(booking_value, ride_distance)::numeric, 3) AS fare_distance_correlation
FROM rides_clean
WHERE booking_status = 'Completed'
  AND booking_value IS NOT NULL
  AND ride_distance IS NOT NULL;
-- Finding: correlation ≈ 0.005 — effectively zero. Fare is not
-- linearly driven by distance in this dataset; pricing rules (flat
-- tiers, vehicle type, surge) dominate over raw km.


/* ------------------------------------------------------------
   Q10. LOCATION OUTLIER VALIDATION
   Are Akshardham/Vinobapuri statistically meaningful outliers?
   ------------------------------------------------------------ */

WITH location_rates AS (
    SELECT
        pickup_location,
        COUNT(*) AS total_rides,
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*) AS cancellation_rate_pct
    FROM rides_clean
    GROUP BY pickup_location
    HAVING COUNT(*) >= 500
),
fleet_stats AS (
    SELECT
        AVG(cancellation_rate_pct) AS mean_rate,
        STDDEV(cancellation_rate_pct) AS std_rate
    FROM location_rates
)
SELECT
    lr.pickup_location,
    lr.total_rides,
    ROUND(lr.cancellation_rate_pct, 2) AS cancellation_rate_pct,
    ROUND(
        (lr.cancellation_rate_pct - fs.mean_rate) / fs.std_rate, 2
    ) AS z_score
FROM location_rates lr
CROSS JOIN fleet_stats fs
WHERE lr.pickup_location IN ('Akshardham', 'Vinobapuri')
ORDER BY lr.cancellation_rate_pct DESC;
-- Finding: both locations sit at ~29.6% cancellation with z-scores
-- near 3.0 (fleet mean ~25.0%, std ~1.5%). At 800+ rides each,
-- this is unlikely to be random noise.
