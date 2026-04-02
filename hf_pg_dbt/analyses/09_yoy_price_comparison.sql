
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

with_area_cost AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
surface_area_m2_normalised,
        pc.cost_per_m2,
        pc.currency,
        cost_per_m2_eur,
        (surface_area_m2_normalised * cost_per_m2_eur)   AS order_cost_eur,
        YEAR(d.order_date)                                  AS yr
    FROM   q1 d
    JOIN transform.dim_packaging_master pm  ON d.pkg_id    = pm.pkg_id
    JOIN transform.dim_procurement_costs pc
           ON  d.market     = pc.market
           AND d.order_date BETWEEN pc.valid_from AND pc.valid_to
)

-- ── A: YoY average cost per order by market and year ────────
SELECT
    market,
    yr,
    COUNT(order_id)                                 AS orders,
    ROUND(AVG(cost_per_m2_eur), 4)                  AS avg_rate_eur_per_m2,
    ROUND(AVG(order_cost_eur), 4)                   AS avg_order_cost_eur,
    ROUND(SUM(order_cost_eur), 4)                   AS total_cost_eur
FROM   with_area_cost
GROUP  BY market, yr
ORDER BY market, yr;


-- ── B: Same-box YoY comparison (DE P-S — identical order type) ─
-- Isolates the pure price effect with no behavioral change
-- Uncomment to run:
/*
SELECT
    yr,
    market,
    pkg_id,
    material_type,
    cost_per_m2_eur                                 AS rate_eur_per_m2,
    surface_area_m2,
    order_cost_eur,
    ROUND(order_cost_eur / meals_count, 4)          AS cost_per_meal_eur
FROM   with_area_cost
WHERE market = 'DE'
  AND  pkg_id = 'P-S'
ORDER BY yr, order_date;
*/


-- ── C: Rate change percentage by market ─────────────────────
-- Uncomment to run:
/*
SELECT
    market,
    MIN(CASE WHEN yr = 2025 THEN cost_per_m2_eur END) AS rate_2025_eur,
    MIN(CASE WHEN yr = 2026 THEN cost_per_m2_eur END) AS rate_2026_eur,
    ROUND(
        (MIN(CASE WHEN yr = 2026 THEN cost_per_m2_eur END)
         - MIN(CASE WHEN yr = 2025 THEN cost_per_m2_eur END))
        / NULLIF(MIN(CASE WHEN yr = 2025 THEN cost_per_m2_eur END), 0) * 100
    , 1)      AS yoy_rate_change_pct
FROM   with_area_cost
GROUP  BY market
HAVING MIN(CASE WHEN yr = 2025 THEN cost_per_m2_eur END) IS NOT NULL
   AND MIN(CASE WHEN yr = 2026 THEN cost_per_m2_eur END) IS NOT NULL;
*/
