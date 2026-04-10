WITH q1 AS (
    SELECT 
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM transform.fact_box_usage
    WHERE pkg_id IS NOT NULL
),
with_fit AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status     AS pkg_status,
        pm.surface_area_m2_normalised  AS actual_area_m2,
        pm_rec.surface_area_m2_normalised AS recommended_area_m2,
        ds.recommended_pkg_id,
        -- Fit category
        CASE
            WHEN ds.recommended_pkg_id IS NULL
                THEN 'Unknown (no standard)'
            WHEN pm.surface_area = COALESCE(
            		pm_rec.surface_area_m2_normalised,
            		pm.surface_area_m2_normalised)
                THEN 'Perfect Fit'
            WHEN pm.surface_area_m2_normalised >
                 pm_rec.surface_area_m2_normalised
                THEN 'Over-boxed'
            ELSE 'Under-boxed'
        END           AS fit_category
    FROM   q1 d
    JOIN transform.dim_packaging_master pm
           ON  d.pkg_id = pm.pkg_id
    LEFT  JOIN transform.dim_packaging_standards ds
               ON  d.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
)
-- ── A: Overall damage rate ───────────────────────────────────
SELECT
    'Overall' AS dimension,
    COUNT(order_id)                                 AS total_orders,
    SUM(is_damaged)                                 AS damaged_orders,
    (SUM(is_damaged) * 100.0
          / COUNT(order_id))                     AS damage_rate_pct
FROM   with_fit
UNION ALL
-- ── B: Damage rate by market ─────────────────────────────────
SELECT
    CONCAT('Market: ', market),
    COUNT(order_id),
    SUM(is_damaged),
    (SUM(is_damaged) * 100.0 / COUNT(order_id))
FROM   with_fit
GROUP  BY market
UNION ALL
-- ── C: Damage rate by box type ───────────────────────────────
SELECT
    CONCAT('Box: ', pkg_id, ' (', pkg_name, ')'),
    COUNT(order_id),
    SUM(is_damaged),
    (SUM(is_damaged) * 100.0 / COUNT(order_id))
FROM   with_fit
GROUP  BY pkg_id, pkg_name
UNION ALL
-- ── D: Damage rate by fit category ───────────────────────────
-- Key test: does over-boxing cause damage?
SELECT
    CONCAT('Fit: ', fit_category),
    COUNT(order_id),
    SUM(is_damaged),
    (SUM(is_damaged) * 100.0 / COUNT(order_id))
FROM   with_fit
GROUP  BY fit_category
ORDER BY dimension;

-- ── E: Order-level damage detail ─────────────────────────────
-- Full detail on every damaged order for root cause investigation
/*
SELECT
    order_id,
    market,
    pkg_id,
    pkg_name,
    material_type,
    meals_count,
    order_date,
    fit_category,
    actual_area_m2,
    recommended_area_m2,
    is_damaged
FROM   with_fit
WHERE is_damaged = 1
ORDER BY order_date;
*/
