-- ============================================================
-- FMCG distribution (packaged snacks and tea): returns and credit risk
-- Schema + SYNTHETIC data.
-- All data below is randomly generated for demonstration only.
-- It does not represent any real company, distributor or payment.
-- Safe to re-run: it drops and rebuilds the tables each time.
-- A fixed random seed makes the data identical on every run,
-- so the results in the README can be reproduced exactly.
-- Total run time: about 10 to 60 seconds.
--
-- Business setting: a manufacturer ships packaged snacks and tea to 150
-- distributors every day. Distributors send back units that expire or
-- arrive damaged (returns). Each month the manufacturer invoices every
-- distributor on credit, and distributors pay some time after the due date.
-- ============================================================

-- 0. RESET AND SEED -----------------------------------------
DROP VIEW  IF EXISTS v_distributor_risk;
DROP TABLE IF EXISTS payments, invoices, shipments, distributors, products, regions CASCADE;
SELECT setseed(0.42);

-- 1. REGIONS ------------------------------------------------
CREATE TABLE regions (
    region_id   SERIAL PRIMARY KEY,
    region_name TEXT NOT NULL
);

INSERT INTO regions (region_name) VALUES
('Colombo'), ('Gampaha'), ('Kandy'), ('Galle'),
('Matara'), ('Jaffna'), ('Kurunegala'), ('Anuradhapura');

-- 2. PRODUCTS (three packaged products) ---------------------
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    product_name TEXT NOT NULL,
    list_price   NUMERIC NOT NULL      -- price per unit (pack) in Rs
);

INSERT INTO products (product_name, list_price) VALUES
('Black Tea 200g',      420),
('Cream Crackers 250g', 180),
('Potato Chips 60g',    120);

-- 3. DISTRIBUTORS (150 fake distributors) -------------------
CREATE TABLE distributors (
    distributor_id   SERIAL PRIMARY KEY,
    distributor_name TEXT NOT NULL,
    region_id        INT REFERENCES regions(region_id),
    start_date       DATE,
    credit_limit     NUMERIC
);

INSERT INTO distributors (distributor_name, region_id, start_date, credit_limit)
SELECT 'Distributor ' || g,
       1 + (g % 8),
       DATE '2022-01-01' + (random() * 700)::INT,
       (50 + (random() * 20)::INT * 10) * 1000
FROM generate_series(1, 150) AS g;

-- 4. SHIPMENTS (daily units shipped and returned, 2024-2025) -
CREATE TABLE shipments (
    shipment_id    SERIAL PRIMARY KEY,
    ship_date      DATE NOT NULL,
    distributor_id INT REFERENCES distributors(distributor_id),
    product_id     INT REFERENCES products(product_id),
    units_shipped  INT NOT NULL,
    units_returned INT NOT NULL        -- expired or damaged units sent back
);

INSERT INTO shipments (ship_date, distributor_id, product_id, units_shipped, units_returned)
SELECT d::DATE,
       a.distributor_id,
       p.product_id,
       50 + (a.distributor_id % 40) + (random() * 20)::INT,
       0
FROM generate_series(DATE '2024-01-01', DATE '2025-12-31', INTERVAL '1 day') AS d
CROSS JOIN distributors a
CROSS JOIN products p;

-- normal returns: 5% to 25% of units shipped
UPDATE shipments
SET units_returned = (units_shipped * (0.05 + random() * 0.20))::INT;

-- hidden pattern 1: every 10th distributor has much higher returns in 2025
UPDATE shipments
SET units_returned = (units_shipped * (0.25 + random() * 0.20))::INT
WHERE distributor_id % 10 = 0
  AND ship_date >= DATE '2025-01-01';

-- 5. INVOICES (one per distributor per month) ---------------
CREATE TABLE invoices (
    invoice_id     SERIAL PRIMARY KEY,
    distributor_id INT REFERENCES distributors(distributor_id),
    invoice_month  DATE NOT NULL,
    amount_billed  NUMERIC NOT NULL,
    due_date       DATE NOT NULL
);

-- billed at 70% of list price on net units (shipped minus returned)
INSERT INTO invoices (distributor_id, invoice_month, amount_billed, due_date)
SELECT s.distributor_id,
       DATE_TRUNC('month', s.ship_date)::DATE,
       ROUND(SUM((s.units_shipped - s.units_returned) * p.list_price * 0.7), 2),
       (DATE_TRUNC('month', s.ship_date) + INTERVAL '1 month' + INTERVAL '14 days')::DATE
FROM shipments s
JOIN products p ON p.product_id = s.product_id
GROUP BY s.distributor_id, DATE_TRUNC('month', s.ship_date);

-- 6. PAYMENTS ------------------------------------------------
CREATE TABLE payments (
    payment_id  SERIAL PRIMARY KEY,
    invoice_id  INT REFERENCES invoices(invoice_id),
    paid_date   DATE NOT NULL,
    amount_paid NUMERIC NOT NULL
);

-- hidden pattern 2: every 7th distributor pays 20 to 80 days late;
-- others pay around the due date;
-- about 3% of invoices stay unpaid, about 5% are only partly paid
INSERT INTO payments (invoice_id, paid_date, amount_paid)
SELECT invoice_id,
       due_date + CASE WHEN distributor_id % 7 = 0
                       THEN (20 + random() * 60)::INT
                       ELSE (random() * 20 - 8)::INT END,
       CASE WHEN random() < 0.05 THEN ROUND(amount_billed * 0.6, 2)
            ELSE amount_billed END
FROM invoices
WHERE random() > 0.03;

-- 7. CHECK THE ROW COUNTS -----------------------------------
SELECT 'regions' AS table_name, COUNT(*) AS row_count FROM regions               -- expect 8
UNION ALL SELECT 'products',     COUNT(*) FROM products                          -- expect 3
UNION ALL SELECT 'distributors', COUNT(*) FROM distributors                      -- expect 150
UNION ALL SELECT 'shipments',    COUNT(*) FROM shipments                         -- expect 328,950
UNION ALL SELECT 'invoices',     COUNT(*) FROM invoices                          -- expect 3,600
UNION ALL SELECT 'payments',     COUNT(*) FROM payments;                         -- about 3,490
