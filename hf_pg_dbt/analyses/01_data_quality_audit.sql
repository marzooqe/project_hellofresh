SELECT
    order_id,
    COUNT(*) AS occurrence_count,
    MIN(order_date) AS order_date,
    MAX(market) AS market,
    MAX(pkg_id) AS pkg_id
FROM transform.fact_box_usage
GROUP  BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;

SELECT
    order_id,
    market,
    meals_count,
    order_date,
    is_damaged
FROM transform.fact_box_usage
WHERE pkg_id IS NULL
ORDER BY order_date;

SELECT
    u.order_id,
    u.market,
    u.pkg_id,
    pm.pkg_name,
    pm.status,
    u.meals_count,
    u.order_date
FROM transform.fact_box_usage u
JOIN transform.dim_packaging_master pm ON u.pkg_id = pm.pkg_id
WHERE pm.status = 'Discontinued'
ORDER BY u.order_date;

SELECT
    u.order_id,
    u.market,
    u.pkg_id,
    u.meals_count,
    u.order_date,
    ds.recommended_pkg_id 
FROM transform.fact_box_usage u
LEFT  JOIN transform.dim_packaging_standards ds ON u.meals_count = ds.meals_count
WHERE ds.recommended_pkg_id IS NULL
  AND  u.pkg_id IS NOT NULL  
ORDER BY u.meals_count, u.order_date;

SELECT
    pkg_id,
    pkg_name,
    surface_area,
    unit_of_measure,
    CASE
        WHEN unit_of_measure = 'cm2'
        THEN surface_area / 10000.0
        ELSE surface_area
    END AS surface_area_m2_normalised
FROM transform.dim_packaging_master
ORDER BY pkg_id;


SELECT
    'Duplicate order IDs' AS issue_type,
    COUNT(*)    AS affected_records
FROM (
    SELECT order_id
    FROM transform.fact_box_usage
    GROUP  BY order_id
    HAVING COUNT(*) > 1
) dups

UNION ALL

SELECT
    'Null pkg_id orders',
    COUNT(*)
FROM transform.fact_box_usage
WHERE pkg_id IS NULL

UNION ALL

SELECT
    'Discontinued box in active use',
    COUNT(*)
FROM transform.fact_box_usage u
JOIN transform.dim_packaging_master pm ON u.pkg_id = pm.pkg_id
WHERE pm.status = 'Discontinued'

UNION ALL

SELECT
    'Meal count not in standards table',
    COUNT(*)
FROM transform.fact_box_usage u
LEFT  JOIN transform.dim_packaging_standards ds ON u.meals_count = ds.meals_count
WHERE ds.recommended_pkg_id IS NULL
  AND  u.pkg_id IS NOT NULL;
