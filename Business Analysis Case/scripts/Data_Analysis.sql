## changes over time analysis
# business over the years
SELECT 
YEAR(order_date) as order_year,
SUM(quantity) as total_quantity,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date) ;

# business by month
SELECT 
MONTH(order_date) as order_month,
SUM(sales_amount) as total_sales,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY MONTH(order_date)
ORDER BY MONTH(order_date) ;


# business by each month and each year
SELECT 
YEAR(order_date) as order_year,
MONTH(order_date) as order_month,
SUM(sales_amount) as total_sales,
COUNT(DISTINCT customer_key) as total_customers,
SUM(quantity) as total_quantity
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date),MONTH(order_date) ;

SELECT  
    DATE_FORMAT(order_date,'%Y-%m') AS order_month,  -- 格式化为 2024-Oct
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM fact_sales
WHERE order_date IS NOT NULL
  AND YEAR(order_date) <> 0
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY MIN(order_date);


## Cumulative Analysis
# calculate the total sales per month and the running total of sales over time
SELECT
order_year,
order_month,
total_sales,
SUM(total_sales) OVER (
ORDER BY order_year,order_month      # window function:ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS cumulative_sales
FROM
(
SELECT
YEAR(order_date) AS order_year,
MONTH(order_date) AS order_month,
SUM(sales_amount) AS total_sales
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY YEAR(order_date),MONTH(order_date)
)t
ORDER BY order_year, order_month;

SELECT
order_year,
total_sales,
SUM(total_sales) OVER (
ORDER BY order_year    # window function:ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS cumulative_sales
FROM
(
SELECT
YEAR(order_date) AS order_year,
SUM(sales_amount) AS total_sales
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY YEAR(order_date)
)t
ORDER BY order_year;

# we can see the progress of business
SELECT
order_year,
total_sales,
SUM(total_sales) OVER (
ORDER BY order_year    # window function:ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
) AS cumulative_sales,
AVG(avg_price)OVER(
ORDER BY order_year
)AS moving_average_price

FROM
(
SELECT
YEAR(order_date) AS order_year,
SUM(sales_amount) AS total_sales,
AVG(price) AS avg_price
FROM fact_sales
WHERE order_date IS NOT NULL 
      AND YEAR(order_date) <> 0
GROUP BY YEAR(order_date)
)t
ORDER BY order_year;

## performance analysis
# analyze the yearly performance of products by comparing their sales
# to both the average sales performance of the product and the previous year's sales

WITH yearly_product_sales AS(
SELECT
YEAR(f.order_date) AS order_year,
SUM(f.sales_amount) AS total_sales,
AVG(f.sales_amount) AS avg_sales,
p.product_name AS product_name
FROM fact_sales f
     LEFT JOIN dim_products p ON f.product_key = p.product_key
WHERE f.order_date IS NOT NULL 
       AND YEAR(f.order_date) <> 0
GROUP BY YEAR(order_date),p.product_name
) 

SELECT 
order_year,
product_name,
total_sales,
ROUND(AVG(total_sales) OVER(PARTITION BY product_name),0) AS avg_sales,
ROUND(total_sales - AVG(total_sales) OVER(PARTITION BY product_name),0) AS diff_avg,
CASE WHEN ROUND(total_sales - AVG(total_sales) OVER(PARTITION BY product_name),0)>0 THEN 'Above average'
	 WHEN ROUND(total_sales - AVG(total_sales) OVER(PARTITION BY product_name),0)<0 THEN 'Below average'
     ELSE 'Avg'
END AS avg_change,
# year_over_year analysis
LAG(total_sales)OVER(PARTITION BY product_name ORDER BY order_year) AS sales_py,
total_sales - LAG(total_sales)OVER(PARTITION BY product_name ORDER BY order_year) AS diff_py,
CASE WHEN total_sales - LAG(total_sales)OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'increase'
	 WHEN total_sales - LAG(total_sales)OVER(PARTITION BY product_name ORDER BY order_year) <0 THEN 'decrease'
     ELSE 'no change'
END AS change_py
FROM yearly_product_sales
ORDER BY product_name,order_year

### which categories contribute the most to overall sales
WITH gategory_sales AS
(
SELECT 
category,
SUM(sales_amount) AS total_sales
FROM fact_sales f
LEFT JOIN dim_products p
     ON f.product_key = p.product_key
GROUP BY category)

SELECT
category, 
    total_sales, 
    SUM(total_sales) OVER() AS overall_sales,
    CONCAT(ROUND((total_sales / SUM(total_sales) OVER()) * 100, 2), '%') AS percentage_of_total
FROM gategory_sales
ORDER BY total_sales desc

### group numbers into three segments based on their spending behavior
# VIP:customers with at least 12 months of history and spending more than 5,000 euros
# Regular: customer with at least 12 months of history but spending 5,000 euros or less
# New: customera with a lifepan less than 12 months
### And find the total number of customers by each group

WITH customer_spending AS(
SELECT 
c.customer_key,
SUM(f.sales_amount)AS total_spending,
MIN(f.order_date) AS first_date,
MAX(f.order_date) AS last_date,
TIMESTAMPDIFF(month,MIN(f.order_date),MAX(f.order_date)) AS lifespan
FROM dim_customers c
LEFT JOIN fact_sales f
     ON c.customer_key = f.customer_key
GROUP BY c.customer_key)

SELECT
COUNT(customer_key)AS total_customers,
customer_segment
FROM
(
SELECT
customer_key,
total_spending,
lifespan,
CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'vip'
     WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
     ELSE 'new'
END customer_segment
FROM customer_spending
)t1
GROUP BY customer_segment
ORDER BY total_customers desc
