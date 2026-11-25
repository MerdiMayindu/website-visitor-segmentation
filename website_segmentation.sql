-- =============================================
-- E-COMMERCE WEBSITE VISITOR SEGMENTATION & CONVERSION ANALYSIS
-- Author: Merdi Mayindu
-- Tool: SQLite (DB Browser)
-- Data: Online Shoppers Purchasing Intention dataset (UCI), table = sessions
--       12,330 website sessions over one year, Google Analytics-style metrics
-- =============================================

-- KEY METRICS (Google Analytics definitions)
-- Conversion rate = sessions that ended in a purchase / all sessions
-- Bounce rate     = % of visitors who entered on a page and left without doing anything else
-- Exit rate       = % of page views where the page was the last in the session
-- Page value      = average value of a page a visitor saw before completing a purchase
--                   (a page value above 0 means the visitor reached pages that usually lead to sales)

-- ---------- PHASE 1: DATA CHECKS ----------

-- 1. How many sessions are there, and how many ended in a purchase?
-- Finding: 12,330 website sessions, of which 1,908 ended in a purchase, an overall
-- conversion rate of 15.5%.
SELECT COUNT(*) AS sessions,
  SUM(CASE WHEN Revenue = 'TRUE' THEN 1 ELSE 0 END) AS purchases,
  ROUND(100.0 * SUM(CASE WHEN Revenue = 'TRUE' THEN 1 ELSE 0 END) / COUNT(*), 1) AS conversion_rate_pct
FROM sessions;

-- 2. What format are the Revenue and Weekend columns in?
-- Finding: Revenue and Weekend are stored as text ('TRUE' / 'FALSE'), so they can't be
-- added up or averaged. Fix: convert Revenue to a 1/0 purchase flag and Weekend
-- to 'Weekend' / 'Weekday' in the clean view.
SELECT Revenue, Weekend, COUNT(*) AS sessions
FROM sessions
GROUP BY Revenue, Weekend;

-- 3. Are the month names consistent, and are any months missing?
-- Finding: June is spelled 'June' while every other month uses 3 letters, so it would
-- sort and group incorrectly. Fix: change it to 'Jun' and add a month number for
-- correct ordering. January and April have no data at all, which needs noting
-- when comparing months.
SELECT Month, COUNT(*) AS sessions
FROM sessions
GROUP BY Month
ORDER BY sessions DESC;

-- 4. Are there any negative durations or impossible rates?
-- Finding: No negative durations and no rates above 100%, so the numeric fields are valid.
SELECT SUM(CASE WHEN Administrative_Duration < 0 OR Informational_Duration < 0
                  OR ProductRelated_Duration < 0 THEN 1 ELSE 0 END) AS negative_durations,
       SUM(CASE WHEN BounceRates > 1 OR ExitRates > 1 THEN 1 ELSE 0 END) AS rates_over_100pct
FROM sessions;

-- 5. Are there duplicate rows, and are they real duplicates?
-- Finding: 125 rows are exact copies of another row, but all of them are 1-2 page
-- sessions with a 20% bounce rate. With no session ID in the data, these are
-- most likely separate visitors who landed and left in the same way, not
-- duplicates. They are kept, since removing them would understate bounces.
SELECT Administrative + Informational + ProductRelated AS pages_viewed,
  BounceRates,
  SUM(copies - 1) AS duplicate_rows
FROM (
  SELECT *, COUNT(*) AS copies
  FROM sessions
  GROUP BY Administrative, Administrative_Duration, Informational, Informational_Duration,
           ProductRelated, ProductRelated_Duration, BounceRates, ExitRates, PageValues,
           SpecialDay, Month, OperatingSystems, Browser, Region, TrafficType,
           VisitorType, Weekend, Revenue
  HAVING COUNT(*) > 1
)
GROUP BY pages_viewed, BounceRates;

-- ---------- PHASE 2: DATA CLEANING ----------

-- 6. Create a clean view with readable fields and a visitor segment
-- Finding: Fixed the June spelling, added month numbers, converted Revenue to a 1/0
-- purchase flag, tidied visitor and day labels, converted time on site to
-- minutes and rates to percentages. Every session is placed in one of 4
-- behaviour segments: Bounced, Casual Browsers, Engaged Browsers (20+ product
-- pages) and High Intent (reached pages that usually lead to a sale).
DROP VIEW IF EXISTS sessions_clean;
CREATE VIEW sessions_clean AS
SELECT
  CASE Month WHEN 'June' THEN 'Jun' ELSE Month END AS month,
  CASE Month
    WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3 WHEN 'May' THEN 5 WHEN 'June' THEN 6
    WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8 WHEN 'Sep' THEN 9 WHEN 'Oct' THEN 10
    WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
  END AS month_num,
  CASE VisitorType
    WHEN 'New_Visitor' THEN 'New'
    WHEN 'Returning_Visitor' THEN 'Returning'
    ELSE 'Other'
  END AS visitor_type,
  CASE WHEN Weekend = 'TRUE' THEN 'Weekend' ELSE 'Weekday' END AS day_type,
  TrafficType AS traffic_source,
  Region AS region,
  Administrative + Informational + ProductRelated AS pages_viewed,
  ProductRelated AS product_pages,
  ROUND((Administrative_Duration + Informational_Duration + ProductRelated_Duration) / 60.0, 1) AS minutes_on_site,
  ROUND(BounceRates * 100, 2) AS bounce_rate_pct,
  ROUND(ExitRates * 100, 2) AS exit_rate_pct,
  ROUND(PageValues, 2) AS page_value,
  SpecialDay AS special_day,
  CASE WHEN Revenue = 'TRUE' THEN 1 ELSE 0 END AS purchased,
  CASE
    WHEN Administrative + Informational + ProductRelated <= 1 OR BounceRates >= 0.2 THEN '1. Bounced'
    WHEN PageValues > 0 THEN '4. High Intent'
    WHEN ProductRelated >= 20 THEN '3. Engaged Browsers'
    ELSE '2. Casual Browsers'
  END AS segment
FROM sessions;

-- ---------- PHASE 3: SEGMENT ANALYSIS ----------

-- 7. How big is each visitor segment, and how well does it convert?
-- Finding: High Intent visitors are just 22.1% of sessions but make 80.5% of all purchases,
-- converting at 56.3%. Casual Browsers are the biggest group (41.6%) but convert
-- at only 2.9%. Bounced visitors (6.2%) almost never buy (1.3%).
SELECT segment,
  COUNT(*) AS sessions,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM sessions_clean), 1) AS pct_of_sessions,
  SUM(purchased) AS purchases,
  ROUND(100.0 * SUM(purchased) / (SELECT SUM(purchased) FROM sessions_clean), 1) AS pct_of_purchases,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY segment
ORDER BY segment;

-- 8. How do buyers behave differently from non-buyers?
-- Finding: Buyers view far more product pages (48 vs 29), spend 74% longer on the site
-- (34 vs 20 minutes) and have bounce and exit rates less than half those of
-- non-buyers.
SELECT CASE WHEN purchased = 1 THEN 'Bought' ELSE 'Did not buy' END AS outcome,
  COUNT(*) AS sessions,
  ROUND(AVG(product_pages), 1) AS avg_product_pages,
  ROUND(AVG(minutes_on_site), 1) AS avg_minutes,
  ROUND(AVG(bounce_rate_pct), 2) AS avg_bounce_rate_pct,
  ROUND(AVG(exit_rate_pct), 2) AS avg_exit_rate_pct
FROM sessions_clean
GROUP BY outcome;

-- 9. Does viewing more product pages lead to more purchases?
-- Finding: Yes. Conversion rises steadily with browsing depth, from 4.3% for visitors
-- who see 5 or fewer product pages to 25.3% for those who see 51 or more.
SELECT CASE
    WHEN product_pages <= 5 THEN '1. 0-5 pages'
    WHEN product_pages <= 20 THEN '2. 6-20 pages'
    WHEN product_pages <= 50 THEN '3. 21-50 pages'
    ELSE '4. 51+ pages'
  END AS product_pages_viewed,
  COUNT(*) AS sessions,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY product_pages_viewed
ORDER BY product_pages_viewed;

-- ---------- PHASE 4: AUDIENCE & TIMING ----------

-- 10. Do new or returning visitors convert better?
-- Finding: New visitors convert at 24.9%, almost double returning visitors (13.9%),
-- even though returning visitors make up 85.6% of all traffic.
SELECT visitor_type,
  COUNT(*) AS sessions,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM sessions_clean), 1) AS pct_of_sessions,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY visitor_type
ORDER BY conversion_rate_pct DESC;

-- 11. Which traffic sources bring the most visitors, and how well do they convert?
--     (traffic sources are coded 1-20 in the data for anonymity)
-- Finding: Traffic source 2 is the biggest and among the best, bringing 31.7% of
-- sessions and 847 purchases at a 21.6% conversion rate. Sources 1 and 3 bring
-- 36.5% of traffic combined but convert at only 10.7% and 8.8%. Source 13 converts
-- worst (5.8%). Smaller sources 8 (27.7%) and 5 (21.5%) convert well and could be
-- scaled up.
SELECT traffic_source,
  COUNT(*) AS sessions,
  ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM sessions_clean), 1) AS pct_of_sessions,
  SUM(purchased) AS purchases,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY traffic_source
HAVING COUNT(*) >= 200
ORDER BY sessions DESC;

-- 12. How do traffic and conversion change month by month?
-- Finding: November is the standout month: 2,998 sessions converting at 25.4%,
-- delivering 760 purchases (40% of the year's total). Conversion climbs steadily
-- from July to November. May has the most traffic of all but converts at just 10.9%.
SELECT month,
  COUNT(*) AS sessions,
  SUM(purchased) AS purchases,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY month, month_num
ORDER BY month_num;

-- 13. Do shoppers convert better at weekends?
-- Finding: Weekend sessions convert slightly better (17.4%) than weekday ones (14.9%).
SELECT day_type,
  COUNT(*) AS sessions,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY day_type;

-- 14. Do visits close to special days (e.g. Valentine's Day, Mother's Day) convert better?
--     special_day runs from 0 (not near a special day) to 1 (the ideal shopping day before it)
-- Finding: Surprisingly, visits close to special days convert much worse (6.2% vs 16.5%).
-- Shoppers seem to browse for gift ideas early but buy elsewhere or later.
SELECT CASE WHEN special_day = 0 THEN 'Normal day' ELSE 'Close to a special day' END AS timing,
  COUNT(*) AS sessions,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct
FROM sessions_clean
GROUP BY timing;

-- 15. Best opportunity: returning visitors who browsed a lot but didn't reach high-value pages
-- Finding: 3,351 returning visitors browsed heavily (53 product pages and 35 minutes on
-- average) but converted at only 5.3%. They are clearly interested, which makes
-- them the best target for retargeting ads and abandoned-browse emails.
SELECT COUNT(*) AS sessions,
  SUM(purchased) AS purchases,
  ROUND(100.0 * AVG(purchased), 1) AS conversion_rate_pct,
  ROUND(AVG(product_pages), 1) AS avg_product_pages,
  ROUND(AVG(minutes_on_site), 1) AS avg_minutes
FROM sessions_clean
WHERE segment = '3. Engaged Browsers'
  AND visitor_type = 'Returning';

-- ---------- SUMMARY & RECOMMENDATIONS ----------
-- 1. Focus on moving visitors to high-intent pages. Reaching them lifts conversion
--    from under 6% to 56%, so improve product recommendations, navigation and
--    calls to action that lead browsers there.
-- 2. Retarget engaged returning browsers. 3,351 sessions showed strong interest
--    but rarely bought, ideal for retargeting ads and abandoned-browse emails.
-- 3. Grow new visitor acquisition. New visitors convert at almost double the rate
--    of returning ones, yet make up only 14% of traffic.
-- 4. Rebalance traffic spend. Put more into source 2 and test scaling sources 8
--    and 5. Review sources 1, 3 and 13, which bring lots of traffic but convert
--    poorly.
-- 5. Plan campaigns around November, which delivers 40% of purchases. For special
--    days, start promotions earlier and add urgency (e.g. delivery deadlines),
--    since visitors browse near these dates but rarely buy.
