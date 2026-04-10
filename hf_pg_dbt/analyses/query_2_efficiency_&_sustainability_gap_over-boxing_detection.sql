WITH q1 AS (
    SELECT 
    order_id, market, pkg_id, meals_count, order_date
    FROM  transform.fact_box_usage
    WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31'
    AND   pkg_id IS NOT NULL
),
sized AS (
    SELECT
        d.*,
        pm_act.surface_area_m2_normalised AS actual_area_m2,
        pm_rec.surface_area_m2_normalised AS recommended_area_m2,
        ds.recommended_pkg_id
    FROM q1 d
    JOIN transform.dim_packaging_standards ds ON d.meals_count = ds.meals_count
    JOIN transform.dim_packaging_master pm_act ON d.pkg_id = pm_act.pkg_id
    JOIN transform.dim_packaging_master pm_rec ON ds.recommended_pkg_id = pm_rec.pkg_id
),
overboxed AS (
    SELECT
        s.*,
        (actual_area_m2 - recommended_area_m2) AS waste_m2
    FROM sized s
    WHERE actual_area_m2 > recommended_area_m2
)
SELECT
    o.market,
    COUNT(*)  AS overboxed_orders,
    (SUM(o.waste_m2)) AS total_paper_waste_m2,
    (SUM(o.waste_m2 * cost_per_m2_eur)) AS total_cost_inefficiency_eur
FROM overboxed o
JOIN transform.dim_procurement_cost pc ON  o.market = pc.market
       AND o.order_date BETWEEN pc.valid_from AND pc.valid_to
GROUP BY o.market
ORDER BY total_cost_inefficiency_eur DESC