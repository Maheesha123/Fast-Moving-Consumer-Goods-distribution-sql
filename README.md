# FMCG Distribution: Returns and Credit Risk Analytics (SQL Case Study)

A PostgreSQL case study on a packaged snacks and tea distributor: which distributors send back too much expired or damaged stock, who pays late, and how much money is stuck in old invoices.

> **All data in this project is synthetic.** It was randomly generated for demonstration and does not represent any real company, distributor or payment.

**Author:** Maheesha Piyumanthi Gunathilake | [LinkedIn](https://www.linkedin.com/in/maheesha-gunathilake)
**Tools:** PostgreSQL 16, pgAdmin, SQL (CTEs, window functions, views, indexes)

---

## Business questions

1. Which regions and products sell the most, and where do returns come from?
2. Did the return rate change over time, and which distributors are responsible?
3. Which distributors pay late, and how concentrated is late payment?
4. How much money is outstanding, and how old is it?

## Key findings

All figures come from the queries in [`queries/`](queries/). Money is in Rs, and sales values use list price.

**1. Returns jumped in January 2025, and 15 distributors explain it.**
The share of units returned (expired or damaged) rose from 15.0% in 2024 to 16.9% in 2025, a step change in January 2025 that never reversed, while units shipped stayed flat (12.96M vs 12.93M). Net units sold fell 2.5%, and net sales value fell from Rs 2,644.1M to Rs 2,578.3M (Rs 65.8M).

![Monthly return rate](images/01_monthly_return_rate.png)

**2. The cause is a small group of distributors.**
15 of 150 distributors (10%) returned more than 25% of their units in every month of 2025, averaging 34.9%, against 15.0% for all other distributors. Their returns above the normal rate come to about 249,000 units, worth about Rs 59.6M at list price, roughly 90% of the fall in net sales value. These distributors are concentrated in four regions (Colombo, Kandy, Kurunegala and Matara).

![Distributor return rates](images/02_distributors_return_rate_2025.png)

**3. Late payment is concentrated in 21 distributors.**
21 distributors (14%) pay 49 days late on average; the other 129 pay within about 2 days of the due date on average (none averages more than 6). Those 21 distributors account for 100% of the Rs 396.5M paid more than 30 days late.

![Payment delay](images/04_payment_delay.png)

**4. Most of the outstanding balance is old.**
As of 31 January 2026, Rs 204.4M was outstanding across 303 invoices, and 76% of it (Rs 155.4M, 243 invoices) was over 90 days past due. In total, Rs 172.9M of the Rs 3,655.7M billed (4.7%) was not recovered: 102 invoices had no payment (Rs 103.9M) and 170 were only partly paid (Rs 69.1M short).

![Ageing of outstanding balances](images/03_ageing_outstanding.png)

**5. A calendar effect hides the real trend in billing.**
Month-to-month billing changes of up to 10% look dramatic, but most of that is the number of days in the month. Billing per day was flat at about Rs 5.06M through 2024 and dropped about 2.2% to about Rs 4.94M from January 2025, matching the return-rate step.

### What I would recommend

- Review order sizes for the 15 high-return distributors. They are shipped more stock than they sell, so it expires or gets damaged.
- Put the 21 slow payers on shorter credit terms or a stricter follow-up routine.
- Review the 243 invoices older than 90 days for escalation or write-off.

## Data model

```mermaid
erDiagram
    regions ||--o{ distributors : "has"
    distributors ||--o{ shipments : "receives"
    products ||--o{ shipments : "is shipped in"
    distributors ||--o{ invoices : "is billed"
    invoices ||--o| payments : "is paid by"

    regions {
        int region_id PK
        text region_name
    }
    distributors {
        int distributor_id PK
        text distributor_name
        int region_id FK
        date start_date
        numeric credit_limit
    }
    products {
        int product_id PK
        text product_name
        numeric list_price
    }
    shipments {
        int shipment_id PK
        date ship_date
        int distributor_id FK
        int product_id FK
        int units_shipped
        int units_returned
    }
    invoices {
        int invoice_id PK
        int distributor_id FK
        date invoice_month
        numeric amount_billed
        date due_date
    }
    payments {
        int payment_id PK
        int invoice_id FK
        date paid_date
        numeric amount_paid
    }
```

The database holds 8 regions, 3 products (Black Tea 200g, Cream Crackers 250g, Potato Chips 60g), 150 distributors, 328,950 daily shipment rows (2024 to 2025), 3,600 monthly invoices and about 3,500 payments. A fixed random seed makes the data identical on every run, and two patterns are built into it for the analysis to find: a group of distributors with high returns from 2025, and a group of distributors who pay late.

## Skills shown

| Skill | Where |
| --- | --- |
| Joins across 3 tables, aggregation, `HAVING` | Q1, Q3, Q4 |
| Date functions (`DATE_TRUNC`, `EXTRACT`, date arithmetic) | Q2, Q3, Q6, Q10 |
| CTEs, including chained CTEs | Q5, Q5b, Q6, Q7 |
| `CASE`, `LEFT JOIN`, ageing analysis as of a report date | Q7, Q8 |
| Window functions (`RANK`, `LAG`, `SUM() OVER`) | Q9, Q10, Q11b |
| Views for reuse (`v_distributor_risk`) | Q11 |
| Data quality checks | Q12 |
| Indexing and `EXPLAIN ANALYZE` (31 ms to 0.12 ms on 329k rows) | Q13 |

## Repository structure

```
schema/01_schema_and_data.sql                       creates the tables and the synthetic data
queries/02_basics_and_joins.sql                     Q1-Q4
queries/03_ctes_dates_and_credit_risk.sql           Q5-Q8
queries/04_window_functions_views_and_indexes.sql   Q9-Q13
images/                                             charts used above
```

## How to run

1. Install PostgreSQL (which includes pgAdmin) and create an empty database called `fmcg_db`.
2. In pgAdmin, open a Query Tool on `fmcg_db`, open `schema/01_schema_and_data.sql` and press F5. This takes 10 to 60 seconds. The script can be re-run safely.
3. Open and run the three files in `queries/` in order, one query at a time (select it, then press F5).

## Notes and limitations

- The numbers above come from a run on PostgreSQL 16. Other versions may give slightly different random data, so figures such as exact rupee totals may differ a little, but the patterns will be the same. The index timings depend on your computer.
- The data is simplified. Real distribution data would also include seasonality, promotions, shelf-life by product, price changes and distributors who join part-way through a month.
- "Value at list price" uses the list price, not the price invoiced to distributors (70% of list price in this data) or the cost of making the product.
