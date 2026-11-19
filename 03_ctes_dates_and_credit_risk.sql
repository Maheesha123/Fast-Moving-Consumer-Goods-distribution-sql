-- ============================================================
-- 03_ctes_dates_and_credit_risk.sql
-- Skills: CTEs (WITH), CASE, date arithmetic, LEFT JOIN, ageing analysis
-- ============================================================


-- Q5. Which distributors keep returning too many units (more than 25% in at least 3 months of 2025)?
-- Approach: a CTE works out each distributor's monthly return rate; the main query counts bad months.
WITH monthly AS (
    SELECT distributor_id,
           DATE_TRUNC('month', ship_date)::DATE AS month_start,
           100.0 * SUM(units_returned) / SUM(units_shipped) AS return_pct
    FROM shipments
    WHERE ship_date >= DATE '2025-01-01'
    GROUP BY distributor_id, DATE_TRUNC('month', ship_date)
)
SELECT distributor_id,
       COUNT(*)                   AS months_above_25pct,
       ROUND(AVG(return_pct), 1)  AS avg_return_pct_in_those_months
FROM monthly
WHERE return_pct > 25
GROUP BY distributor_id
HAVING COUNT(*) >= 3
ORDER BY months_above_25pct DESC, distributor_id;


-- Q5b. What does the high-return group cost? Their 2025 returns above the normal rate
-- (the rate of all other distributors), valued at list price.
-- Approach: chained CTEs: monthly rates -> flagged distributors -> benchmark rate -> cost.
WITH monthly AS (
    SELECT distributor_id,
           100.0 * SUM(units_returned) / SUM(units_shipped) AS return_pct
    FROM shipments
    WHERE ship_date >= DATE '2025-01-01'
    GROUP BY distributor_id, DATE_TRUNC('month', ship_date)
),
flagged AS (
    SELECT distributor_id
    FROM monthly
    WHERE return_pct > 25
    GROUP BY distributor_id
    HAVING COUNT(*) >= 3
),
benchmark AS (
    SELECT 1.0 * SUM(units_returned) / SUM(units_shipped) AS normal_rate
    FROM shipments
    WHERE ship_date >= DATE '2025-01-01'
      AND distributor_id NOT IN (SELECT distributor_id FROM flagged)
)
SELECT COUNT(DISTINCT d.distributor_id)                                        AS flagged_distributors,
       SUM(d.units_shipped)                                                AS units_shipped,
       SUM(d.units_returned)                                            AS units_returned,
       ROUND(100.0 * SUM(d.units_returned) / SUM(d.units_shipped), 1)     AS their_return_pct,
       ROUND(100 * (SELECT normal_rate FROM benchmark), 1)               AS other_distributors_return_pct,
       ROUND(SUM(d.units_returned)
             - SUM(d.units_shipped) * (SELECT normal_rate FROM benchmark)) AS excess_returned_units,
       ROUND(SUM((d.units_returned - d.units_shipped * (SELECT normal_rate FROM benchmark))
                 * t.list_price))                                       AS excess_value_at_list_price
FROM shipments d
JOIN products t ON t.product_id = d.product_id
WHERE d.ship_date >= DATE '2025-01-01'
  AND d.distributor_id IN (SELECT distributor_id FROM flagged);


-- Q6a. Which distributors pay latest? (average days between due date and payment date)
-- Approach: paid_date - due_date gives days late (negative = early).
WITH distributor_delay AS (
    SELECT i.distributor_id,
           ROUND(AVG(p.paid_date - i.due_date), 1) AS avg_days_late,
           COUNT(*)                                AS paid_invoices
    FROM invoices i
    JOIN payments p ON p.invoice_id = i.invoice_id
    GROUP BY i.distributor_id
)
SELECT distributor_id, avg_days_late, paid_invoices
FROM distributor_delay
ORDER BY avg_days_late DESC
LIMIT 10;

-- Q6b. How many distributors are slow payers (average more than 15 days late)?
WITH distributor_delay AS (
    SELECT i.distributor_id,
           AVG(p.paid_date - i.due_date) AS avg_days_late
    FROM invoices i
    JOIN payments p ON p.invoice_id = i.invoice_id
    GROUP BY i.distributor_id
)
SELECT COUNT(*) FILTER (WHERE avg_days_late > 15)  AS slow_payers,
       COUNT(*)                                    AS total_distributors,
       ROUND(100.0 * COUNT(*) FILTER (WHERE avg_days_late > 15) / COUNT(*), 1) AS slow_payer_pct
FROM distributor_delay;


-- Q7. Ageing report: how much is outstanding, and how overdue is it, as of 31 January 2026?
-- Approach: LEFT JOIN keeps invoices with no payment; only payments made on or before
-- the report date count; CASE puts each open balance into an ageing bucket.
WITH params AS (
    SELECT DATE '2026-01-31' AS as_of
),
open_items AS (
    SELECT i.invoice_id,
           i.amount_billed - COALESCE(p.amount_paid, 0) AS outstanding,
           params.as_of - i.due_date                    AS days_past_due
    FROM invoices i
    CROSS JOIN params
    LEFT JOIN payments p
           ON p.invoice_id = i.invoice_id
          AND p.paid_date <= params.as_of
)
SELECT CASE WHEN days_past_due <= 0  THEN '0. Not yet due'
            WHEN days_past_due <= 30 THEN '1. 1-30 days'
            WHEN days_past_due <= 60 THEN '2. 31-60 days'
            WHEN days_past_due <= 90 THEN '3. 61-90 days'
            ELSE                          '4. Over 90 days' END AS ageing_bucket,
       COUNT(*)                   AS open_invoices,
       ROUND(SUM(outstanding))    AS outstanding_value
FROM open_items
WHERE outstanding > 0
GROUP BY 1
ORDER BY 1;


-- Q8. How many invoices are unpaid, part-paid, or paid in full, and what is the shortfall?
SELECT CASE WHEN p.invoice_id IS NULL             THEN 'Unpaid'
            WHEN p.amount_paid < i.amount_billed  THEN 'Part-paid'
            ELSE                                       'Paid in full' END AS payment_status,
       COUNT(*)                                                  AS invoices,
       ROUND(SUM(i.amount_billed))                               AS billed_value,
       ROUND(SUM(i.amount_billed - COALESCE(p.amount_paid, 0)))  AS shortfall_value
FROM invoices i
LEFT JOIN payments p ON p.invoice_id = i.invoice_id
GROUP BY 1
ORDER BY 1;
