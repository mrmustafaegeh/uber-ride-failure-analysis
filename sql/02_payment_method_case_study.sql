/* ============================================================
   CASE STUDY: PAYMENT METHOD & REVENUE RISK
   Table: rides_clean (PostgreSQL)
   Author: Mustafa Egeh

   Scenario: finance wants to know if payment method predicts
   cancellation risk, average revenue, or ride quality.
   ============================================================ */


/* ------------------------------------------------------------
   1. CANCELLATION RATE BY PAYMENT METHOD — WITH A CAVEAT
   ------------------------------------------------------------ */

SELECT
    payment_method,
    COUNT(*) AS total_rides,
    ROUND(
        COUNT(CASE WHEN booking_status IN
            ('Cancelled by Driver', 'Cancelled by Customer') THEN 1 END)
        * 100.0 / COUNT(*), 2
    ) AS cancellation_rate_pct
FROM rides_clean
GROUP BY payment_method
ORDER BY cancellation_rate_pct DESC;
/* Result: every real payment method shows ~0% cancellation, while
   the missing/NULL payment_method group shows ~78%.

   IMPORTANT — this is NOT a real finding. payment_method is only
   ever recorded once a ride completes and is charged. A cancelled
   ride never reaches payment, so it always has a NULL payment_method.
   Comparing cancellation rate across payment methods is therefore
   comparing something that's structurally ~0% by definition against
   one catch-all bucket that is mostly made of cancelled rides.
   This is a data-structure artifact, not a business insight. */


/* ------------------------------------------------------------
   2. AVERAGE BOOKING VALUE BY PAYMENT METHOD
   (Meaningful — only completed rides have both a payment method
   and a real booking value, so this comparison is valid.)
   ------------------------------------------------------------ */

SELECT
    payment_method,
    COUNT(*) AS total_rides,
    ROUND(AVG(booking_value), 2) AS avg_booking_value
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY payment_method
ORDER BY avg_booking_value DESC;
-- Finding: average booking value is flat across all payment methods
-- (~505-512). Payment method does not predict trip value.


/* ------------------------------------------------------------
   3. RATINGS BY PAYMENT METHOD
   ------------------------------------------------------------ */

SELECT
    payment_method,
    COUNT(*) AS total_rides,
    ROUND(AVG(customer_rating), 2) AS avg_customer_rating,
    ROUND(AVG(driver_ratings), 2)  AS avg_driver_rating
FROM rides_clean
WHERE booking_status = 'Completed'
GROUP BY payment_method
ORDER BY avg_customer_rating DESC;
-- Finding: customer ratings (~4.40-4.41) and driver ratings (~4.23-4.24)
-- are flat across payment methods. No quality signal tied to how a
-- customer pays.


/* ------------------------------------------------------------
   CASE STUDY CONCLUSION
   Payment method has no meaningful relationship with booking value
   or ratings — every payment type performs almost identically. The
   one apparent signal (cancellation rate) is not a real business
   finding but an artifact of how the data is generated: recognizing
   that distinction, rather than reporting the misleading 0% vs 78%
   numbers at face value, is the actual point of this case study.
   ------------------------------------------------------------ */
