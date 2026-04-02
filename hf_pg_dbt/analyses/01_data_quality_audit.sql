-- ============================================================
-- 01 · DATA QUALITY AUDIT
-- HelloFresh Packaging Analysis
-- Identifies all data quality issues before any metric is run
-- ============================================================

-- ── 1A: Duplicate Order IDs ──────────────────────────────────
-- Orders that appear more than once in fact_box_usage.
-- Root cause: scanner re-scan events writing duplicate rows.

SELECT
    order_id,
    COUNT(*)            AS occurrence_count,
    MIN(order_date)     AS order_date,
    MAX(market)         AS market,
    MAX(pkg_id)         AS pkg_id
FROM   fact_box_usage
GROUP  BY order_id
HAVING COUNT(*) > 1
ORDER  BY occurrence_count DESC;


-- ── 1B: Null Package IDs ────────────────────────────────────
-- Orders with no pkg_id — cannot be costed or analysed.
-- Result: entire NL market invisible in Q1 2026.

SELECT
    order_id,
    market,
    meals_count,
    order_date,
    is_damaged
FROM   fact_box_usage
WHERE  pkg_id IS NULL
ORDER  BY order_date;


-- ── 1C: Discontinued Boxes in Active Use ────────────────────
-- Orders where a Discontinued box was shipped after it was
-- marked inactive in dim_packaging_master.

SELECT
    u.order_id,
    u.market,
    u.pkg_id,
    pm.pkg_name,
    pm.status,
    u.meals_count,
    u.order_date
FROM   fact_box_usage u
JOIN   dim_packaging_master pm ON u.pkg_id = pm.pkg_id
WHERE  pm.status = 'Discontinued'
ORDER  BY u.order_date;


-- ── 1D: Meal Counts with No Standard Defined ────────────────
-- Orders where meals_count has no entry in dim_packaging_standards.
-- These orders have no box recommendation — over/under-boxing is undetectable.

SELECT
    u.order_id,
    u.market,
    u.pkg_id,
    u.meals_count,
    u.order_date,
    ds.recommended_pkg_id  -- will be NULL if no standard exists
FROM   fact_box_usage u
LEFT  JOIN dim_packaging_standards ds ON u.meals_count = ds.meals_count
WHERE  ds.recommended_pkg_id IS NULL
  AND  u.pkg_id IS NOT NULL   -- exclude already-null pkg_id rows (caught in 1B)
ORDER  BY u.meals_count, u.order_date;


-- ── 1E: Mixed Units in dim_packaging_master ──────────────────
-- Surface areas stored in inconsistent units (m² and cm²).
-- All downstream cost calculations must normalise to m² first.

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
FROM   dim_packaging_master
ORDER  BY pkg_id;


-- ── 1F: Full Data Quality Summary ───────────────────────────
-- Single-query summary of all issue counts for reporting.

SELECT
    'Duplicate order IDs'             AS issue_type,
    COUNT(*)                          AS affected_records
FROM (
    SELECT order_id
    FROM   fact_box_usage
    GROUP  BY order_id
    HAVING COUNT(*) > 1
) dups

UNION ALL

SELECT
    'Null pkg_id orders',
    COUNT(*)
FROM   fact_box_usage
WHERE  pkg_id IS NULL

UNION ALL

SELECT
    'Discontinued box in active use',
    COUNT(*)
FROM   fact_box_usage u
JOIN   dim_packaging_master pm ON u.pkg_id = pm.pkg_id
WHERE  pm.status = 'Discontinued'

UNION ALL

SELECT
    'Meal count not in standards table',
    COUNT(*)
FROM   fact_box_usage u
LEFT  JOIN dim_packaging_standards ds ON u.meals_count = ds.meals_count
WHERE  ds.recommended_pkg_id IS NULL
  AND  u.pkg_id IS NOT NULL;
