-- ============================================================
-- 11 · BOX TYPE ECONOMICS & EFFICIENCY SCORING
-- HelloFresh Packaging Analysis
-- Ranks each box type by cost efficiency, paper waste,
-- damage rate and compliance status
-- ============================================================

WITH deduped AS (
    SELECT DISTINCT
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM transform.fact_box_usage
    WHERE pkg_id IS NOT NULL
),

with_metrics AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status                                           AS pkg_status,
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END                                                 AS actual_area_m2,
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END                                                 AS recommended_area_m2,
        ds.recommended_pkg_id,
        CASE
            WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
            ELSE pc.cost_per_m2
        END                                                 AS cost_per_m2_eur
    FROM   deduped d
    JOIN transform.dim_packaging_master pm    ON d.pkg_id         = pm.pkg_id
    LEFT  JOIN transform.dim_packaging_standards ds ON d.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
    JOIN transform.dim_procurement_costs pc
           ON  d.market     = pc.market
           AND d.order_date BETWEEN pc.valid_from AND pc.valid_to
),

with_cost AS (
    SELECT
        *,
        ROUND(actual_area_m2       * cost_per_m2_eur, 4)   AS actual_cost_eur,
        ROUND(COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur, 4)   AS ideal_cost_eur,
        GREATEST(actual_area_m2
                 - COALESCE(recommended_area_m2, actual_area_m2), 0)
                                                            AS waste_m2,
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN ROUND(recommended_area_m2 / actual_area_m2 * 100, 1)
            ELSE NULL
        END                                                 AS efficiency_pct
    FROM   with_metrics
)

-- ── Box type performance summary ─────────────────────────────
SELECT
    pkg_id,
    pkg_name,
    material_type,
    pkg_status,
    COUNT(order_id)                                 AS total_orders,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_cost_eur,
    ROUND(AVG(actual_cost_eur), 4)                  AS avg_cost_per_order_eur,
    ROUND(SUM(waste_m2), 4)                         AS total_paper_waste_m2,
    ROUND(AVG(waste_m2), 4)                         AS avg_waste_per_order_m2,
    SUM(is_damaged)                                 AS damaged_orders,
    ROUND(SUM(is_damaged) * 100.0
          / COUNT(order_id), 1)                     AS damage_rate_pct,
    ROUND(AVG(efficiency_pct), 1)                   AS avg_efficiency_pct,
    ROUND(SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1)
                                                    AS cost_efficiency_pct
FROM   with_cost
GROUP  BY pkg_id, pkg_name, material_type, pkg_status
ORDER BY avg_efficiency_pct DESC;
