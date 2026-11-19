-- ============================================================
-- 04_window_functions_views_and_indexes.sql
-- Skills: window functions (RANK, LAG), views, data quality checks, indexing
-- ============================================================


-- Q9. Who are the top 3 distributors in each region by net units sold?
-- Approach: RANK() OVER (PARTITION BY region ...) restarts the ranking inside each region.
SELECT region_name, distributor_id, net_units, rnk AS rank_in_region
FROM (
    SELECT r.region_name,
           a.distributor_id,
           SUM(d.units_shipped - d.units_returned) AS net_units,
           RANK() OVER (PARTITION BY r.region_name
                        ORDER BY SUM(d.units_shipped - d.units_returned) DESC) AS rnk
    FROM shipments d
    JOIN distributors  a ON a.distributor_id  = d.distributor_id
    JOIN regions r ON r.region_id = a.region_id
    GROUP BY r.region_name, a.distributor_id
) ranked
WHERE rnk <= 3
ORDER BY region_name, rnk;


-- Q10. How does monthly billing change from month to month?
-- Approach: LAG() looks at the previous month. Months have different lengths, so the
-- query also shows billing per day, which is the fair way to compare February with March.
WITH monthly AS (
    SELECT invoice_month,
           SUM(amount_billed) AS billed,
           EXTRACT(DAY FROM (invoice_month + INTERVAL '1 month' - INTERVAL '1 day'))::INT AS days_in_month
    FROM invoices
    GROUP BY invoice_month
)
SELECT invoice_month,
       ROUND(billed)                                   AS billed,
       ROUND(billed - LAG(billed) OVER (ORDER BY invoice_month)) AS change_vs_prev_month,
       ROUND(100.0 * (billed - LAG(billed) OVER (ORDER BY invoice_month))
                   / LAG(billed) OVER (ORDER BY invoice_month), 1) AS change_pct,
       ROUND(billed / days_in_month)                   AS billed_per_day
FROM monthly
ORDER BY invoice_month;


-- Q11a. A reusable credit-risk view (this is what a dashboard would read).
-- Risk level is based on how late the distributor pays on average.
CREATE OR REPLACE VIEW v_distributor_risk AS
SELECT i.distributor_id,
       COUNT(*)                                         AS invoices,
       ROUND(AVG(p.paid_date - i.due_date), 1)          AS avg_days_late,
       COUNT(*) FILTER (WHERE p.invoice_id IS NULL)     AS unpaid_invoices,
       CASE WHEN AVG(p.paid_date - i.due_date) > 30 THEN 'High'
            WHEN AVG(p.paid_date - i.due_date) > 10 THEN 'Medium'
            ELSE                                         'Low' END AS risk_level
FROM invoices i
LEFT JOIN payments p ON p.invoice_id = i.invoice_id
GROUP BY i.distributor_id;

SELECT risk_level, COUNT(*) AS distributors
FROM v_distributor_risk
GROUP BY risk_level
ORDER BY risk_level;

-- Q11b. How concentrated is late payment? Share of the value paid more than 30 days late,
-- split by risk level.
WITH late_value AS (
    SELECT i.distributor_id,
           SUM(p.amount_paid) FILTER (WHERE p.paid_date - i.due_date > 30) AS paid_over_30_days_late
    FROM invoices i
    JOIN payments p ON p.invoice_id = i.invoice_id
    GROUP BY i.distributor_id
)
SELECT v.risk_level,
       COUNT(*)                                                   AS distributors,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_distributors,
       ROUND(COALESCE(SUM(l.paid_over_30_days_late), 0))          AS value_paid_over_30_days_late,
       ROUND(100.0 * COALESCE(SUM(l.paid_over_30_days_late), 0)
                   / SUM(SUM(l.paid_over_30_days_late)) OVER (), 1) AS pct_of_late_value
FROM v_distributor_risk v
JOIN late_value l ON l.distributor_id = v.distributor_id
GROUP BY v.risk_level
ORDER BY v.risk_level;


-- Q12. Data quality checks: every line should show 0 issues.
SELECT 'Invoices paid more than once' AS check_name, COUNT(*) AS issues
FROM (SELECT invoice_id FROM payments GROUP BY invoice_id HAVING COUNT(*) > 1) dup
UNION ALL
SELECT 'Payments larger than the invoice', COUNT(*)
FROM payments p JOIN invoices i ON i.invoice_id = p.invoice_id
WHERE p.amount_paid > i.amount_billed
UNION ALL
SELECT 'Returns larger than units sent', COUNT(*)
FROM shipments WHERE units_returned > units_shipped
UNION ALL
SELECT 'Zero or negative units sent', COUNT(*)
FROM shipments WHERE units_shipped <= 0
UNION ALL
SELECT 'Payments dated before the invoice month', COUNT(*)
FROM payments p JOIN invoices i ON i.invoice_id = p.invoice_id
WHERE p.paid_date < i.invoice_month;


-- Q13. Speeding up a query with an index.
-- Run the first EXPLAIN ANALYZE, then create the index, then run the second.
-- Compare the "Execution Time" line at the bottom of each result.
DROP INDEX IF EXISTS idx_ship_distributor_date;

EXPLAIN ANALYZE
SELECT SUM(units_shipped), SUM(units_returned)
FROM shipments
WHERE distributor_id = 42
  AND ship_date >= DATE '2025-06-01' AND ship_date < DATE '2025-07-01';

CREATE INDEX idx_ship_distributor_date ON shipments (distributor_id, ship_date);
ANALYZE shipments;

EXPLAIN ANALYZE
SELECT SUM(units_shipped), SUM(units_returned)
FROM shipments
WHERE distributor_id = 42
  AND ship_date >= DATE '2025-06-01' AND ship_date < DATE '2025-07-01';
