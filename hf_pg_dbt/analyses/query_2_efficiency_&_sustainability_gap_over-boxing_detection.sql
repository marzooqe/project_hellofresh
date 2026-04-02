WITH deduped AS (
    SELECT DISTINCT order_id, market, pkg_id, meals_count, order_date
    FROM  fact_box_usage
    WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND   pkg_id IS NOT NULL
),

sized AS (
    SELECT
        d.*,
        -- Actual box area
        CASE WHEN pm_act.unit_of_measure = 'cm2'
             THEN pm_act.surface_area / 10000.0
             ELSE pm_act.surface_area
        END AS actual_area_m2,
        -- Recommended box area
        CASE WHEN pm_rec.unit_of_measure = 'cm2'
             THEN pm_rec.surface_area / 10000.0
             ELSE pm_rec.surface_area
        END AS recommended_area_m2,
        ds.recommended_pkg_id
    FROM   deduped d
    JOIN   dim_packaging_standards ds ON d.meals_count       = ds.meals_count
    JOIN   dim_packaging_master   pm_act  ON d.pkg_id            = pm_act.pkg_id
    JOIN   dim_packaging_master   pm_rec  ON ds.recommended_pkg_id = pm_rec.pkg_id
),

overboxed AS (
    SELECT
        s.*,
        (actual_area_m2 - recommended_area_m2) AS waste_m2
    FROM sized s
    WHERE actual_area_m2 > recommended_area_m2   -- over-boxing condition
)

SELECT
    o.market,
    COUNT(*)  AS overboxed_orders,
    ROUND(SUM(o.waste_m2), 4)   AS total_paper_waste_m2,
    ROUND(SUM(o.waste_m2 * CASE
        WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
        ELSE pc.cost_per_m2
    END), 4) AS total_cost_inefficiency_eur
FROM   overboxed o
JOIN   dim_procurement_costs pc
       ON  o.market = pc.market
       AND o.order_date BETWEEN pc.valid_from AND pc.valid_to
GROUP BY o.market
ORDER BY total_cost_inefficiency_eur DESC