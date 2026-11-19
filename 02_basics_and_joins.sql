-- ============================================================
-- 02_basics_and_joins.sql
-- Skills: SELECT, JOIN, GROUP BY, HAVING, date functions
-- Database: fmcg_db (run schema/01_schema_and_data.sql first)
-- Each query starts with the business question it answers.
-- ============================================================


-- Q1. Which regions sell the most, and which have the highest share of units returned (expired or damaged)?
-- Approach: join shipments -> distributors -> regions, then summarise per region.
SELECT r.region_name,
       SUM(d.units_shipped)                        AS units_shipped,
       SUM(d.units_returned)                    AS units_returned,
       SUM(d.units_shipped - d.units_returned)    AS net_units,
       ROUND(100.0 * SUM(d.units_returned) / SUM(d.units_shipped), 1) AS return_pct
FROM shipments d
JOIN distributors  a ON a.distributor_id  = d.distributor_id
JOIN regions r ON r.region_id = a.region_id
GROUP BY r.region_name
ORDER BY net_units DESC;


-- Q2. How do sales and returns move month by month?
-- Approach: DATE_TRUNC rolls daily rows up to months.
SELECT DATE_TRUNC('month', ship_date)::DATE AS month_start,
       SUM(units_shipped)                     AS units_shipped,
       SUM(units_returned)                 AS units_returned,
       ROUND(100.0 * SUM(units_returned) / SUM(units_shipped), 1) AS return_pct
FROM shipments
GROUP BY DATE_TRUNC('month', ship_date)
ORDER BY month_start;


-- Q3. Which product earns the most each year (net units x list price)?
-- Approach: join to products for the price; EXTRACT pulls the year out of the date.
SELECT EXTRACT(YEAR FROM d.ship_date)::INT AS year,
       t.product_name,
       ROUND(SUM((d.units_shipped - d.units_returned) * t.list_price)) AS net_sales_value
FROM shipments d
JOIN products t ON t.product_id = d.product_id
GROUP BY EXTRACT(YEAR FROM d.ship_date), t.product_name
ORDER BY year, net_sales_value DESC;


-- Q4. Monthly review: which distributors returned more than 25% of their units in January 2025?
-- Approach: WHERE limits the rows to one month; HAVING filters distributors after totals are worked out.
SELECT distributor_id,
       SUM(units_shipped)     AS units_shipped,
       SUM(units_returned) AS units_returned,
       ROUND(100.0 * SUM(units_returned) / SUM(units_shipped), 1) AS return_pct
FROM shipments
WHERE ship_date >= DATE '2025-01-01'
  AND ship_date <  DATE '2025-02-01'
GROUP BY distributor_id
HAVING 100.0 * SUM(units_returned) / SUM(units_shipped) > 25
ORDER BY return_pct DESC;
