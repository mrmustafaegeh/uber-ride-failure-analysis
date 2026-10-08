# Uber Ride-Hailing Analysis — Interview Study Guide

> **DELETE THIS FILE before or after your interviews.**  
> It is excluded from Git via `.gitignore` so it will not be pushed to GitHub.  
> This is your private cheat sheet — the public portfolio is `README.md`.

---

## 1. Your 30-second pitch (memorize this)

> "I analyzed 150,000 ride-hailing bookings from Delhi NCR using PostgreSQL and Tableau. I cleaned messy real-world data — embedded quotes in IDs, literal 'null' strings, duplicates — then ran exploratory SQL to find demand patterns, cancellation outliers, and a data-quality trap around payment methods. My top findings: revenue peaks at 7 PM but volume at 6 PM, weekend revenue is 46% higher per trip due to surge pricing not distance, and two locations have statistically significant cancellation outliers driven by driver-side cancels. I built a Tableau dashboard and documented everything so it's reproducible."

---

## 2. Dataset — what it is and where it came from

| Item | Detail |
|---|---|
| **Source** | [Uber Ride Analytics Dashboard on Kaggle](https://www.kaggle.com/datasets/yashdevladdha/uber-ride-analytics-dashboard) |
| **Author** | Yash Devladdha |
| **File name** | `ncr_ride_bookings.csv` |
| **Rows (raw)** | 150,000 |
| **Rows (after cleaning)** | 148,767 (1,233 duplicates removed) |
| **Geography** | Delhi NCR, India |
| **Currency** | INR (₹) |
| **Date range** | Jan 1, 2024 – Dec 30, 2024 |
| **Important disclaimer** | Public **educational/synthetic** dataset — NOT real proprietary Uber data. Say this if asked. |

### What each row represents
One **booking attempt** — not necessarily a completed ride. A booking can end as:
- Completed
- Cancelled by Customer
- Cancelled by Driver
- Incomplete
- No Driver Found

Only **Completed** rides have `booking_value`, `payment_method`, and ratings.

---

## 3. Column dictionary (know these cold)

| Column | Meaning | Notes |
|---|---|---|
| `ride_date` / `ride_time` | When booking happened | Combined for time analysis |
| `booking_id` | Unique booking identifier | Had embedded `"` quotes in raw data |
| `customer_id` | Customer identifier | Same quote problem |
| `booking_status` | Outcome of the booking | 5 distinct values — never assume `'Cancelled'` exists |
| `vehicle_type` | Auto, Go Sedan, Bike, Premier Sedan, etc. | 7 types |
| `pickup_location` | Where rider was picked up | ~175 locations |
| `drop_location` | Destination | Not heavily analyzed |
| `avg_vtat` | Average **Vehicle** Time to Accept Trip (minutes) | Driver supply signal |
| `avg_ctat` | Average **Customer** Time to Accept Trip (minutes) | Customer-side wait |
| `booking_value` | Fare in ₹ | **Only on completed rides** |
| `ride_distance` | Trip distance in km | Mostly populated on completed rides |
| `driver_ratings` / `customer_rating` | 1–5 stars | Only on completed rides |
| `payment_method` | UPI, Cash, Credit Card, etc. | **Only recorded after completion/charge** |

### Columns dropped during cleaning (redundant)
`cancelled_by_customer`, `customer_cancel_reason`, `cancelled_by_driver`, `driver_cancel_reason`, `incomplete_rides`, `incomplete_rides_reason` — all duplicated info already in `booking_status`.

---

## 4. End-to-end workflow (what we did, in order)

```
Kaggle CSV  →  PostgreSQL staging (rides_raw)  →  Clean (rides_clean)  →  SQL analysis  →  Tableau dashboard  →  GitHub portfolio
```

| Step | What you did | File / tool |
|---|---|---|
| 1 | Downloaded dataset from Kaggle | Kaggle link above |
| 2 | Loaded into PostgreSQL as all-text staging table | `00_data_cleaning.sql` |
| 3 | Profiled raw data BEFORE cleaning | Profiling queries in cleaning script |
| 4 | Built clean table with types, dedup, NULL handling | `CREATE TABLE rides_clean AS SELECT...` |
| 5 | Ran data quality checks again mid-analysis | Section 0 in `01_exploratory_analysis.sql` |
| 6 | Exploratory analysis Q1–Q10 | `01_exploratory_analysis.sql` |
| 7 | Payment method case study | `02_payment_method_case_study.sql` |
| 8 | Built Tableau dashboard | Tableau Public |
| 9 | Documented + structured GitHub repo | `README.md`, images, `.gitignore` |

---

## 5. Data quality problems — what was wrong and how we fixed it

### Problem 1: Embedded quote characters in IDs
- **Raw looked like:** `"CNR5884300"` (quotes stored INSIDE the string)
- **Fix:** `TRIM(BOTH '"' FROM booking_id)`
- **Why it matters:** Joins and dedup would fail silently if quotes stayed

### Problem 2: Literal text `'null'` instead of SQL NULL
- **Raw looked like:** the word `null` in cells, not empty cells
- **Fix:** `NULLIF(column, 'null')` on every affected column
- **Why it matters:** `'null'` becomes its own category in GROUP BY — fake group with thousands of rows
- **Residual gap:** `payment_method` still had literal `'null'` after first clean pass — caught again at query time. **Good interview story:** "One cleaning pass isn't enough; you re-profile before aggregating."

### Problem 3: 1,233 duplicate booking IDs
- **Fix:** `ROW_NUMBER() OVER (PARTITION BY booking_id ORDER BY ride_date, ride_time)` then keep `rn = 1`
- **Why ROW_NUMBER not DISTINCT:** DISTINCT drops entire duplicate rows; ROW_NUMBER lets you pick the earliest booking per ID

### Problem 4: All columns imported as text
- **Fix:** Cast after NULLIF: `NULLIF(booking_value, 'null')::numeric`, `ride_date::date`, `ride_time::time`
- **Why stage as text first:** Raw file has `'null'` strings mixed in — typed import would error

### Problem 5: Fragmented booking status (6 extra columns)
- **Fix:** Dropped redundant reason columns; kept single `booking_status`
- **Trap discovered later:** Cancellations split as `'Cancelled by Customer'` and `'Cancelled by Driver'` — NOT a single `'Cancelled'`. A query `WHERE booking_status = 'Cancelled'` returns **zero rows without error**. Dangerous silent bug.

---

## 6. SQL techniques used (say these in interviews)

| Technique | Where we used it | What to say |
|---|---|---|
| `GROUP BY` + aggregates | Every analysis query | "Segmented metrics by hour, day, location, vehicle type" |
| `CASE WHEN` | Cancellation counting, weekend/weekday split | "Conditional aggregation to count cancels without filtering them out" |
| `EXTRACT(hour FROM ride_time)` | Q3 hourly pattern | "Pulled hour-of-day from timestamp for demand curves" |
| `EXTRACT(dow FROM ride_date)` | Q3, Q6, Q7 | "Day-of-week analysis; DOW 0=Sunday in PostgreSQL" |
| `HAVING COUNT(*) > 500` | Q5c location cancels | "Filtered to locations with enough sample size so rates aren't noise" |
| `ROW_NUMBER() OVER (...)` | Deduplication | "Window function to keep one row per booking_id" |
| `NULLIF()` | Cleaning + payment_method | "Converted fake null strings to real NULLs" |
| `CORR()` | Q9 fare vs distance | "Tested whether fare linearly follows distance" |
| `STDDEV()` + z-score | Q10 outlier validation | "Validated outliers statistically, not just visually" |
| `SUM() OVER (PARTITION BY ...)` | Q7 vehicle mix % | "Window function to compute share within weekend vs weekday" |
| `UNION ALL` | Q8 fleet vs location comparison | "Compared outlier locations against fleet baseline in one result set" |

---

## 7. Every query explained — what it asks and what we found

### File: `00_data_cleaning.sql`

**Profiling queries (Step 1)**
```sql
SELECT booking_status, COUNT(*) FROM rides_raw GROUP BY booking_status;
```
→ Found 5 status values and their counts. Total = 150,000.

```sql
SELECT booking_id, COUNT(*) FROM rides_raw GROUP BY booking_id HAVING COUNT(*) > 1;
```
→ Found 1,233 duplicate IDs.

**Cleaning query (Step 2)**
- Inner query: trim quotes, assign ROW_NUMBER per booking_id
- Outer query: NULLIF + type casts, filter `rn = 1`
- Result: `rides_clean` with 148,767 rows, 15 columns

---

### File: `01_exploratory_analysis.sql`

#### Section 0 — Data quality checks (ALWAYS DO THIS FIRST)
```sql
SELECT DISTINCT booking_status FROM rides_clean;
```
→ Never assume column values. Found 5 statuses.

```sql
SELECT payment_method, COUNT(*) FROM rides_clean GROUP BY payment_method;
```
→ Found literal `'null'` string still present — must NULLIF before grouping.

```sql
SELECT booking_status, COUNT(*), COUNT(driver_ratings) FROM rides_clean GROUP BY booking_status;
```
→ Ratings only exist on completed rides. Confirms NULL pattern is logical, not random.

---

#### Q1 — Overall baseline
```sql
SELECT AVG(booking_value), AVG(ride_distance)
FROM rides_clean WHERE booking_status = 'Completed';
```
**Finding:** Avg fare ~₹508, avg distance ~24.7 km. Your baseline for all comparisons.

**Recruiter tip:** Always filter `Completed` for revenue metrics — cancelled rides have no fare.

---

#### Q2 — Vehicle type breakdown
```sql
SELECT vehicle_type, AVG(booking_value), AVG(ride_distance)
FROM rides_clean WHERE booking_status = 'Completed'
GROUP BY vehicle_type;
```
**Finding:** All vehicle types ~₹500–512 fare and ~24.5–24.8 km. **Flat across types.**

**What it means:** Vehicle category alone doesn't explain fare differences in this dataset.

---

#### Q3 — Time patterns

**Q3a — Hourly**
```sql
SELECT EXTRACT(hour FROM ride_time) AS hour_of_day,
       COUNT(*) AS ride_count,
       SUM(booking_value) AS total_revenue
FROM rides_clean WHERE booking_status = 'Completed'
GROUP BY hour_of_day;
```
**Finding:**
- Volume peaks at **hour 18 (6 PM)** — ~7,617 rides
- Revenue peaks at **hour 19 (7 PM)** — ~₹3.91M

**Business insight:** Busiest ≠ most valuable. Driver incentives tied to 6 PM miss the revenue peak.

**Q3b — Day of week**
```sql
SELECT EXTRACT(dow FROM ride_date) AS day_of_week, COUNT(*), SUM(booking_value)
FROM rides_clean WHERE booking_status = 'Completed'
GROUP BY day_of_week;
```
**Finding:** Ride count flat all week (~13,200–13,450/day). Weekend **daily revenue** ~₹8.7–8.8M vs weekday ~₹5.8–6.1M.

---

#### Q4 — Cancellation by vehicle type
```sql
SELECT vehicle_type,
       COUNT(*) AS total_rides,
       COUNT(CASE WHEN booking_status IN ('Cancelled by Driver','Cancelled by Customer') THEN 1 END) AS cancelled,
       -- rate = cancelled / total * 100
FROM rides_clean GROUP BY vehicle_type;
```
**Finding:** ~24–25% cancellation rate for **every** vehicle type. Flat. Not a driver.

**Key technique:** No `WHERE` filter — you need ALL statuses in denominator to calculate a true rate.

---

#### Q5 — Top locations

**Q5a** — Top 10 by ride count  
**Q5b** — Top 10 by revenue (completed only)  
→ Lists differ. **Busiest location ≠ highest revenue location.**

**Q5c — Cancellation rate by location**
```sql
... GROUP BY pickup_location HAVING COUNT(*) > 500 ...
```
**Finding:** Akshardham & Vinobapuri ~29–30% cancel vs ~25% average. Real outliers.

**Why HAVING 500:** A location with 20 rides and 40% cancel rate is noise. 500+ rides = reliable rate.

---

#### Q6 — Weekend vs weekday deep-dive
```sql
SELECT CASE WHEN EXTRACT(DOW FROM ride_date) IN (0,6) THEN 'Weekend' ELSE 'Weekday' END,
       COUNT(*), AVG(booking_value), AVG(ride_distance)
FROM rides_clean WHERE booking_status = 'Completed'
GROUP BY 1;
```
**Finding:**
| | Weekday | Weekend |
|---|---|---|
| Avg distance | 25.98 km | 26.05 km |
| Avg booking value | ₹448.67 | ₹655.51 |

**Conclusion:** +46% weekend price, same distance → **pricing effect, not longer trips.**

---

#### Q7 — Weekend vehicle mix
```sql
-- Uses SUM(COUNT(*)) OVER (PARTITION BY day_type) for percentage share
```
**Finding:** Premium vehicles (Premier Sedan + Uber XL) = ~14.8% weekend vs ~15.2% weekday. **Nearly identical.**

**Conclusion:** Vehicle mix does NOT explain weekend premium → points to **surge/dynamic pricing**.

---

#### Q8 — Outlier locations: wait times & cancel type
Compares Akshardham, Vinobapuri vs fleet average.

**Finding:**
| Location | Cancel rate | VTAT | Driver cancel | Customer cancel |
|---|---|---|---|---|
| Fleet avg | 25.0% | 8.45 min | ~8.5% | ~8.5% |
| Akshardham | 29.6% | 8.46 min | 20.2% | 9.3% |
| Vinobapuri | 29.6% | 8.37 min | 21.5% | 8.1% |

**Conclusion:** Wait times are normal. **Driver cancellations are ~2.5× customer cancellations** at these locations → supply/acceptance problem, not passenger wait time.

---

#### Q9 — Fare vs distance correlation
```sql
SELECT CORR(booking_value, ride_distance) FROM rides_clean WHERE booking_status = 'Completed';
```
**Finding:** r ≈ **0.005** (essentially zero).

**Conclusion:** Fare is NOT linearly driven by km. Pricing uses tiers, vehicle type, surge — not raw distance.

---

#### Q10 — Statistical outlier validation
```sql
-- CTE: cancellation rate per location (n >= 500)
-- CTE: fleet mean and STDDEV of those rates
-- z_score = (location_rate - mean) / std
```
**Finding:** Akshardham & Vinobapuri z-scores ≈ **3.0** (mean 25.0%, σ ≈ 1.5%).

**What to say:** "At z ≈ 3 with 800+ rides each, these outliers are statistically meaningful, not random noise."

---

### File: `02_payment_method_case_study.sql`

**Scenario:** Finance team asks — does payment method predict cancellation risk or revenue?

#### Query 1 — Cancellation by payment method
**Naive result:** UPI/Cash/Credit Card ~0% cancel; NULL payment ~78% cancel.

**THE TRAP:** Payment is only recorded when a ride **completes and gets charged**. Cancelled rides never reach payment → always NULL payment_method. You're comparing completed rides (0% cancel by definition) vs a bucket of mostly cancelled rides.

**This is your best interview story.** Shows you don't report misleading correlations.

#### Query 2 — Avg booking value by payment method (completed only)
**Finding:** Flat ~₹505–512 across all methods. No signal.

#### Query 3 — Ratings by payment method (completed only)
**Finding:** Customer ~4.40, driver ~4.23 — flat across methods. No signal.

**Case study conclusion:** Payment method is NOT a useful predictor for anything in this dataset.

---

## 8. Top 5 findings — ranked by interview impact

1. **Payment method trap** — Shows analytical integrity and data literacy
2. **6 PM volume vs 7 PM revenue gap** — Actionable ops insight
3. **Weekend +46% price, same distance, same vehicle mix** — Diagnostic thinking (ruled out hypotheses)
4. **Akshardham/Vinobapuri driver-side cancels (z≈3)** — Statistical rigor + ops recommendation
5. **Fare vs distance r≈0** — Challenges naive assumptions about pricing

---

## 9. Recommendations — and the evidence behind each

| Recommendation | Supported by |
|---|---|
| Shift driver incentives to 7 PM | Q3a — revenue peak hour 19, volume peak hour 18 |
| Target driver supply at Akshardham/Vinobapuri | Q5c, Q8, Q10 — high cancel, driver-side, z≈3, normal VTAT |
| Weekend pricing is the revenue lever | Q6 + Q7 — +46% fare, same distance, same mix |
| Deprioritize payment method as risk signal | Case study — artifact + flat value/ratings |
| Don't model fare on distance alone | Q9 — r ≈ 0.005 |

---

## 10. Common recruiter questions — and how to answer

### "Walk me through this project."
Use the 30-second pitch (Section 1), then offer to go deeper on cleaning, analysis, or dashboard.

### "What was the hardest part?"
> "Catching the payment method trap. The data showed 0% vs 78% cancellation by payment type, which looks dramatic. But payment_method is only populated on completed rides, so the comparison is structurally invalid. I validated by checking when payment_method is NULL relative to booking_status."

### "How did you handle dirty data?"
> "Profile first, never assume. I found embedded quotes, literal 'null' strings, duplicates, and fragmented status columns. Staged everything as text, cleaned with NULLIF and TRIM, deduped with ROW_NUMBER, then re-profiled during analysis and found a residual null-string issue in payment_method."

### "Why PostgreSQL instead of Python/Excel?"
> "150K rows with complex cleaning, window functions, and reusable queries — SQL is the right tool. PostgreSQL gives me typed tables, CORR, EXTRACT, and window functions. Tableau for the visual layer. I can explain any finding by pointing to a specific query."

### "What's your biggest finding?"
Pick based on the role:
- **Data quality role:** Payment method trap
- **Business/ops analyst role:** 6 PM vs 7 PM incentive mismatch
- **Analytics role:** Weekend pricing decomposition (ruled out distance AND mix)

### "How do you know Akshardham is a real outlier?"
> "Three checks: enough sample size (800+ rides via HAVING), rate ~5 points above fleet mean, and z-score ~3.0 against the distribution of all location cancellation rates."

### "Is this real Uber data?"
> "No — it's a public educational dataset on Kaggle simulating NCR ride patterns. I treat findings as analytical demonstrations, not operational Uber insights."

### "What would you do next?"
> "Monthly trend analysis across 2024, dashboard KPI cards and cancellation view in Tableau, and driver cancellation reason breakdown at outlier locations if reason codes are available."

### "What SQL concepts did you use?"
GROUP BY, CASE WHEN, EXTRACT, HAVING, window functions (ROW_NUMBER, SUM OVER), NULLIF, CORR, STDDEV, CTEs, UNION ALL.

---

## 11. What NOT to say

| Don't say | Say instead |
|---|---|
| "Payment method causes higher cancellation" | "The apparent link was a data artifact — payment is only recorded on completed rides" |
| "Weekend rides are longer" | "Distance is identical — the premium is pricing" |
| "Akshardham has long wait times" | "Wait times match fleet average — driver cancellations are the signal" |
| "Fare increases with distance" | "Correlation is ~0 — pricing is more complex than km" |
| "This is real Uber data" | "Public Kaggle educational dataset for Delhi NCR" |

---

## 12. Tools map

| Tool | Role |
|---|---|
| **Kaggle** | Dataset source |
| **PostgreSQL** | Storage, cleaning, all analysis queries |
| **Beekeeper Studio** | SQL client (GUI) |
| **Tableau Public** | Interactive dashboard for stakeholders |
| **GitHub** | Portfolio hosting (SQL + README + images only) |

---

## 13. File map — what's in the repo

| File | Purpose |
|---|---|
| `README.md` | Public portfolio — findings, charts, recommendations |
| `00_data_cleaning.sql` | Raw → rides_clean transformation |
| `01_exploratory_analysis.sql` | Q0–Q10 exploratory analysis |
| `02_payment_method_case_study.sql` | Payment method case study |
| `images/` | Dashboard screenshots + before/after cleaning |
| `.gitignore` | Excludes CSVs, this study guide, large files |
| `STUDY_GUIDE_DELETE_ME.md` | **This file — delete when done studying** |

---

## 14. Study plan (suggested)

| Day | Focus |
|---|---|
| Day 1 | Sections 1–5: pitch, dataset, columns, workflow, data quality |
| Day 2 | Sections 6–7: SQL techniques + Q1–Q5 — run them in PostgreSQL if possible |
| Day 3 | Sections 7–9: Q6–Q10 + payment case study + recommendations |
| Day 4 | Section 10: Practice answering recruiter questions out loud |
| Day 5 | Open Tableau dashboard + README — walk through visuals while explaining findings |

---

## 15. Quick numbers reference card

```
Raw rows:           150,000
Clean rows:         148,767
Duplicates removed: 1,233
Completed rides:    ~93,000 (~62% completion)

Avg fare (completed):     ~₹508
Avg distance (completed): ~24.7 km

Volume peak:  hour 18 (6 PM)
Revenue peak: hour 19 (7 PM)

Weekday avg fare:  ₹448.67
Weekend avg fare:  ₹655.51  (+46%)
Weekday distance:  25.98 km
Weekend distance:  26.05 km  (same)

Fleet cancel rate:     ~25.0%
Akshardham cancel:     ~29.6%  (z ≈ 3.0)
Vinobapuri cancel:     ~29.6%  (z ≈ 3.0)

Fare-distance corr:    ~0.005

Premium mix weekend:   ~14.8%
Premium mix weekday:   ~15.2%  (same)
```

---

*When you're confident explaining every section without looking at this file — delete it.*
