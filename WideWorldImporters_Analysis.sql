/*
================================================================================
  WideWorldImporters — SQL Data Analysis
  Author:   Idan (github.com/IdanMx)
  Dataset:  WideWorldImporters (Microsoft sample OLTP database, v1.0)
            https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0
  Engine:   Microsoft SQL Server (T-SQL) / SSMS
  Context:  Course project (John Bryce, "Data Analyst Expert"). Ten business
            questions answered against a large, multi-schema relational database.
  Summary:  Demonstrates advanced analytical SQL — CTEs, window functions
            (RANK/DENSE_RANK/ROW_NUMBER, LAG, running totals), GROUPING SETS,
            PIVOT, STRING_AGG, and multi-table joins across schemas.
            Each block: business question -> query -> takeaway.
================================================================================
*/

USE WideWorldImporters;
GO


/* ===== Q1: Yearly income, normalized, with year-over-year growth =========== */
-- Business question: What is total income per year, and how fast is it growing?
-- Because some years are partial, income is normalized to a full-year figure
-- (monthly average x 12) before computing the YoY growth rate with LAG().
WITH YearlyIncome AS (
    SELECT
        SUM(CT.AmountExcludingTax) AS IncomePerYear,
        YEAR(SO.OrderDate) AS [Year],
        COUNT(DISTINCT MONTH(SO.OrderDate)) AS NumberOfDistinctMonths,
        CAST(ROUND(SUM(CT.AmountExcludingTax) / COUNT(DISTINCT MONTH(SO.OrderDate)) * 12, 2)
             AS DECIMAL(10,2)) AS YearlyLinearIncome
    FROM [Sales].[CustomerTransactions] CT
    JOIN [Sales].[Invoices] SI ON CT.InvoiceID = SI.InvoiceID
    JOIN Sales.Orders SO ON SI.OrderID = SO.OrderID
    GROUP BY YEAR(SO.OrderDate)
),
YearlyPrevious AS (
    SELECT *,
        LAG(YearlyLinearIncome) OVER (ORDER BY [Year]) AS PreviousIncome
    FROM YearlyIncome
)
SELECT
    [Year], IncomePerYear, NumberOfDistinctMonths, YearlyLinearIncome,
    CAST(FLOOR((YearlyLinearIncome - PreviousIncome) / PreviousIncome * 10000) / 100
         AS DECIMAL(10,2)) AS GrowthRate
FROM YearlyPrevious;
-- Takeaway: Normalizing to a full-year figure makes partial years
-- comparable; the LAG-based growth rate shows the year-on-year trend in revenue.


/* ===== Q2: Top 5 customers per quarter by income ========================== */
-- Business question: Each quarter, who are the five highest-earning customers?
-- DENSE_RANK partitioned by year+quarter ranks customers within each period.
WITH RankedTable AS (
    SELECT
        SI.CustomerID AS RealCustomerID,
        YEAR(SO.OrderDate) AS TheYear,
        DATEPART(QQ, SO.OrderDate) AS TheQuarter,
        SUM(CT.AmountExcludingTax) AS IncomePerYear,
        DENSE_RANK() OVER (
            PARTITION BY YEAR(SO.OrderDate), DATEPART(QQ, SO.OrderDate)
            ORDER BY SUM(CT.AmountExcludingTax) DESC) AS DNR
    FROM [Sales].[Invoices] SI
    JOIN [Sales].[CustomerTransactions] CT 
        ON SI.InvoiceID = CT.InvoiceID
    JOIN Sales.Orders SO 
        ON SO.OrderID = SI.OrderID
    GROUP BY SI.CustomerID, YEAR(SO.OrderDate), DATEPART(QQ, SO.OrderDate)
)
SELECT RT.TheYear, RT.TheQuarter, SC.CustomerName, RT.IncomePerYear, RT.DNR
FROM RankedTable RT
JOIN Sales.Customers SC ON RT.RealCustomerID = SC.CustomerID
WHERE DNR <= 5;
-- Takeaway: Surfaces the top-5 customer leaderboard per quarter, so
-- account teams can see which customers drive revenue in each period.


/* ===== Q3: Top 10 stock items by total sales ============================== */
-- Business question: Which ten products generate the most sales revenue?
SELECT TOP 10
    StockItemID,
    [Description] AS StockItemName,
    SUM(Quantity * UnitPrice) AS TotalProfit
FROM [Sales].[InvoiceLines]
GROUP BY StockItemID, Description
ORDER BY SUM(Quantity * UnitPrice) DESC;
-- Takeaway: The ten best-selling products by revenue — the core catalog
-- lines to keep well-stocked and prioritize.


/* ===== Q4: Products ranked by nominal profit margin (valid only) ========== */
-- Business question: Which products have the largest nominal margin
-- (RecommendedRetailPrice - UnitPrice), considering only currently-valid items?
-- DENSE_RANK ranks by margin; ROW_NUMBER gives a clean sequential position.
WITH RankedTable AS (
    SELECT
        StockItemID, StockItemName, UnitPrice, RecommendedRetailPrice,
        RecommendedRetailPrice - UnitPrice AS NominalProductProfit,
        DENSE_RANK() OVER (ORDER BY RecommendedRetailPrice - UnitPrice DESC) AS DNR,
        ValidFrom, ValidTo
    FROM [Warehouse].[StockItems]
)
SELECT
    ROW_NUMBER() OVER (ORDER BY DNR) AS RN,
    StockItemID, StockItemName, UnitPrice, RecommendedRetailPrice,
    NominalProductProfit, DNR
FROM RankedTable
WHERE ValidTo > ValidFrom;
-- Takeaway: Highlights the highest-margin products by absolute markup —
-- candidates for promotion where volume can be grown without hurting margin.


/* ===== Q5: Suppliers with their product lists (rolled up) ================= */
-- Business question: For each supplier, list all the products they provide as a
-- single readable field. STRING_AGG collapses the many product rows per supplier.
SELECT
    CAST(PS.SupplierID AS NVARCHAR(10)) + ' - ' + PS.SupplierName AS SupplierDetails,
    STRING_AGG(CAST(WS.StockItemID AS NVARCHAR(10)) + ' ' + WS.StockItemName, ' /, ')
        AS ProductDetails
FROM [Purchasing].[Suppliers] PS
JOIN [Warehouse].[StockItems] WS ON PS.SupplierID = WS.SupplierID
GROUP BY PS.SupplierID, PS.SupplierName;
-- Takeaway: A one-row-per-supplier product catalog — useful for procurement to
-- see supplier coverage at a glance.


/* ===== Q6: Top 5 customers by revenue, with geography ===================== */
-- Business question: Who are the five highest-revenue customers, and where are
-- they located? A five-table join walks Customer -> City -> State -> Country.
WITH TopCustomers AS (
    SELECT SI.CustomerID, SUM(SIO.ExtendedPrice) AS TotalExtendedPrice
    FROM Sales.Invoices SI
    JOIN Sales.InvoiceLines SIO ON SI.InvoiceID = SIO.InvoiceID
    GROUP BY SI.CustomerID
)
SELECT TOP 5
    TC.CustomerID, AC.CityName, ACOUNT.CountryName, ACOUNT.Continent,
    ACOUNT.Region, TC.TotalExtendedPrice
FROM TopCustomers TC
JOIN Sales.Customers SC ON TC.CustomerID = SC.CustomerID
JOIN Application.Cities AC ON SC.PostalCityID = AC.CityID
JOIN Application.StateProvinces APS ON AC.StateProvinceID = APS.StateProvinceID
JOIN Application.Countries ACOUNT ON APS.CountryID = ACOUNT.CountryID
ORDER BY TotalExtendedPrice DESC;
-- Takeaway: Ties top revenue to geography, showing where the most
-- valuable customers are concentrated for regional sales focus.


/* ===== Q7: Monthly revenue with running cumulative + grand total ========== */
-- Business question: Show monthly revenue per year, a running cumulative total
-- within each year, and a grand total per year. GROUPING SETS produces both the
-- monthly rows and the yearly subtotal; a windowed SUM builds the running total.
SELECT
    OrderYear, OrderMonth, MonthlyTotal,
    SUM(CASE WHEN IsTotal = 0 THEN MonthlyTotal END)
        OVER (PARTITION BY OrderYear ORDER BY IsTotal, MonthNum) AS CumulativeTotal
FROM (
    SELECT
        YEAR(SOD.OrderDate) AS OrderYear,
        CASE WHEN GROUPING(MONTH(SOD.OrderDate)) = 1
             THEN 'Grand Total'
             ELSE CAST(MONTH(SOD.OrderDate) AS VARCHAR(11))
        END AS OrderMonth,
        MONTH(SOD.OrderDate) AS MonthNum,
        GROUPING(MONTH(SOD.OrderDate)) AS IsTotal,
        SUM(SIL.Quantity * SIL.UnitPrice) AS MonthlyTotal
    FROM [Sales].[InvoiceLines] SIL
    JOIN [Sales].[Invoices] SIO ON SIL.InvoiceID = SIO.InvoiceID
    JOIN Sales.Orders SOD ON SIO.OrderID = SOD.OrderID
    GROUP BY GROUPING SETS (
        (YEAR(SOD.OrderDate), MONTH(SOD.OrderDate)),
        (YEAR(SOD.OrderDate))
    )
) AS T1
ORDER BY OrderYear, IsTotal, MonthNum;
-- Takeaway: A month-by-month revenue view with within-year running totals and a
-- year grand total in one result — a compact management reporting layout.


/* ===== Q8: Order counts pivoted by year ================================== */
-- Business question: How many orders were placed in each month, compared across
-- years? PIVOT turns years into columns for an at-a-glance month x year matrix.
SELECT OrderMonth, [2013], [2014], [2015], [2016]
FROM (
    SELECT YEAR(OrderDate) AS OrderYear, MONTH(OrderDate) AS OrderMonth, OrderID
    FROM Sales.Orders
) AS SRC
PIVOT (
    COUNT(OrderID) FOR OrderYear IN ([2013], [2014], [2015], [2016])
) pvt
ORDER BY OrderMonth;
-- Takeaway: A month x year grid of order counts makes seasonal patterns
-- and year-over-year volume changes easy to spot.


/* ===== Q9: Churn detection (gap vs. customer's own average) =============== */
-- Business question: Which customers may be churning? A customer is flagged
-- "Potential Churn" when the time since their last order exceeds 2x their own
-- average gap between orders. LAG computes each inter-order gap; the average is
-- compared against days since their last order (anchored to the latest order in
-- the data, not GETDATE()).
WITH Ranked AS (
    SELECT CustomerID, OrderDate,
        LAG(OrderDate, 1) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PreviousOrderDate
    FROM Sales.Orders
),
CustomerOrders AS (
    SELECT *, DATEDIFF(DAY, PreviousOrderDate, OrderDate) AS DaysSinceLastOrder
    FROM Ranked
),
Averages AS (
    SELECT CustomerID,
        AVG(DaysSinceLastOrder) AS AvgDaysBetweenOrders,
        DATEDIFF(DAY, MAX(OrderDate), (SELECT MAX(OrderDate) FROM Sales.Orders)) AS DaysSinceLastOrder
    FROM CustomerOrders
    GROUP BY CustomerID
)
SELECT
    CO.CustomerID, SC.CustomerName, CO.OrderDate, CO.PreviousOrderDate,
    AV.DaysSinceLastOrder, AV.AvgDaysBetweenOrders,
    CASE WHEN AV.DaysSinceLastOrder > 2 * AV.AvgDaysBetweenOrders
         THEN 'Potential Churn'
         ELSE 'Active'
    END AS CustomerStatus
FROM CustomerOrders CO
LEFT JOIN Averages AV ON CO.CustomerID = AV.CustomerID
JOIN Sales.Customers SC ON CO.CustomerID = SC.CustomerID
ORDER BY CO.CustomerID;
-- Takeaway: Flags churn risk relative to each customer's own ordering rhythm
-- rather than a fixed cutoff — a customer who normally orders weekly is caught
-- far sooner than one who orders quarterly.


/* ===== Q10: Customer distribution by category (% share) ================== */
-- Business question: How is the customer base split across customer categories,
-- and how concentrated is it? A windowed SUM() OVER() gives each category's
-- share of the total for a concentration-risk read.
WITH DistinctCustomerID AS (
    SELECT DISTINCT SCU.BillToCustomerID, SCU.CustomerCategoryID, SCC.CustomerCategoryName
    FROM Sales.Customers SCU
    JOIN Sales.CustomerCategories SCC ON SCU.CustomerCategoryID = SCC.CustomerCategoryID
),
FinalTable AS (
    SELECT
        CustomerCategoryName,
        COUNT(BillToCustomerID) AS CustomerCount,
        SUM(COUNT(*)) OVER () AS TotalCustCount
    FROM DistinctCustomerID
    GROUP BY CustomerCategoryName
)
SELECT *,
    CAST(CAST(100.0 * CustomerCount / TotalCustCount AS DECIMAL(10,2)) AS NVARCHAR(10)) + '%'
        AS DistributionFactor
FROM FinalTable;
-- Takeaway: Customer base is fairly evenly distributed (17.9%-22.4%). Highest
-- concentration — and thus highest exposure — is Novelty Shop (22.43%) and
-- Supermarket (22.05%); Corporate (17.87%) is least concentrated. Overall
-- concentration risk is moderate given the even spread.
