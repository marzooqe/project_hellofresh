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
with_metrics AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status     AS pkg_status,
        pm.surface_area_m2_normalised  AS actual_area_m2,
        pm_rec.surface_area_m2_normalised    AS recommended_area_m2,
        ds.recommended_pkg_id,
        cost_per_m2_eur
    FROM   q1 d
    JOIN transform.dim_packaging_master pm    ON d.pkg_id         = pm.pkg_id
    LEFT  JOIN transform.dim_packaging_standards ds ON d.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
    JOIN transform.dim_procurement_cost pc
           ON  d.market     = pc.market
           AND d.order_date BETWEEN pc.valid_from AND pc.valid_to
),
with_cost AS (
    SELECT
        *,
        (actual_area_m2       * cost_per_m2_eur)   AS actual_cost_eur,
        (COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur)   AS ideal_cost_eur,
        GREATEST(actual_area_m2
                 - COALESCE(recommended_area_m2, actual_area_m2), 0) AS waste_m2,
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN (recommended_area_m2 / actual_area_m2 * 100)
            ELSE NULL
        END           AS efficiency_pct
    FROM   with_metrics
)
-- ── Box type performance summary ─────────────────────────────
SELECT
    pkg_id,
    pkg_name,
    material_type,
    pkg_status,
    COUNT(order_id) AS total_orders,
     (SUM(actual_cost_eur)) AS total_cost_eur,
    (AVG(actual_cost_eur)) AS avg_cost_per_order_eur,
    (SUM(waste_m2)) AS total_paper_waste_m2,
    (AVG(waste_m2)) AS avg_waste_per_order_m2,
    SUM(is_damaged) AS damaged_orders,
    (SUM(is_damaged) * 100.0
          / COUNT(order_id)) AS damage_rate_pct,
    (AVG(efficiency_pct)) AS avg_efficiency_pct,
    (SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100)
              AS cost_efficiency_pct
FROM   with_cost
GROUP  BY pkg_id, pkg_name, material_type, pkg_status
ORDER BY avg_efficiency_pct DESC;
