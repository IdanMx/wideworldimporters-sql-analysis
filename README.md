# WideWorldImporters — SQL Data Analysis

Ten business questions answered in T-SQL against Microsoft's **WideWorldImporters**
sample database — a large, multi-schema OLTP system (Sales, Purchasing, Warehouse,
Application). Written and run in SQL Server Management Studio (SSMS) as a course
project for the John Bryce "Data Analyst Expert" program.

This project focuses on **advanced analytical SQL**: CTEs, window functions,
`GROUPING SETS`, `PIVOT`, and multi-schema joins — the techniques you reach for once
basic aggregation isn't enough.

**File:** [`WideWorldImporters_Analysis.sql`](./WideWorldImporters_Analysis.sql) — all
ten queries, documented with the business question and a takeaway for each.

## The questions

| #  | Business question | Key techniques |
|----|-------------------|----------------|
| 1  | Yearly income, normalized to a full year, with YoY growth | CTE, `LAG`, normalization |
| 2  | Top 5 customers per quarter by income | `DENSE_RANK` partitioned by year+quarter |
| 3  | Top 10 stock items by total sales | `GROUP BY`, `TOP`, `ORDER BY` |
| 4  | Products ranked by nominal profit margin (valid items only) | `DENSE_RANK` + `ROW_NUMBER`, validity filter |
| 5  | Each supplier's full product list, rolled up | `STRING_AGG` |
| 6  | Top 5 customers by revenue, with geography | 5-table join across schemas |
| 7  | Monthly revenue with running cumulative + grand total | `GROUPING SETS` + windowed `SUM` |
| 8  | Monthly order counts compared across years | `PIVOT` |
| 9  | Churn risk vs. each customer's own ordering rhythm | `LAG`, `DATEDIFF`, `CASE` |
| 10 | Customer distribution by category (% share) | `SUM() OVER()`, concentration read |

## Techniques demonstrated

- **Window functions** — `RANK` / `DENSE_RANK` / `ROW_NUMBER`, `LAG` for
  period-over-period comparison, and running totals with an ordered `SUM() OVER()`.
- **`GROUPING SETS`** to return detail rows and subtotals in a single result (Q7).
- **`PIVOT`** to reshape rows into a year-by-month matrix (Q8).
- **`STRING_AGG`** to collapse many child rows into one readable field (Q5).
- **CTEs** to structure multi-step logic readably (used throughout).
- **Multi-schema joins** across Sales, Purchasing, Warehouse, and Application.

## A couple of decisions worth noting

- **Q1 normalizes partial years.** Comparing a full year against a partial one is
  misleading, so income is scaled to a full-year equivalent (monthly average x 12)
  before the growth rate is computed.
- **Q9 measures churn relative to each customer's own behavior**, not a fixed
  cutoff. A customer who normally orders weekly is flagged far sooner than one who
  orders quarterly — and "now" is anchored to the latest order in the data, not the
  real-world date, since the dataset is historical.

## How to run

1. Download WideWorldImporters (v1.0) and restore it in SQL Server:
   https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0
2. Open `WideWorldImporters_Analysis.sql` in SSMS.
3. Run each block independently (each is a standalone query).

---

Part of my data-analyst portfolio, alongside a
[Northwind SQL analysis](../NorthwindProject). Next: Python/Pandas and Power BI.
