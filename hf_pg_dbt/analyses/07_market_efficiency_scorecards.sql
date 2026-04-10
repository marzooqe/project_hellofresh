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
with_area AS (
    SELECT
        d.*,
        pm.surface_area_m2_normalised AS actual_area_m2
    FROM   q1 d
    JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),
with_recommended AS (
    SELECT
        a.*,
        pm_rec.surface_area_m2_normalised  AS recommended_area_m2
    FROM   with_area a
    LEFT  JOIN transform.dim_packaging_standards ds
               ON  a.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
),
with_cost AS (
    SELECT
        r.*,
        cost_per_m2_eur,
        (r.actual_area_m2 * cost_per_m2_eur) AS actual_cost_eur,
        (COALESCE(r.recommended_area_m2, r.actual_area_m2) * cost_per_m2_eur) AS ideal_cost_eur,
        GREATEST(r.actual_area_m2
                 - COALESCE(r.recommended_area_m2, r.actual_area_m2), 0) AS waste_m2
    FROM   with_recommended r
    JOIN transform.dim_procurement_cost pc
           ON  r.market = pc.market
           AND r.order_date BETWEEN pc.valid_from AND pc.valid_to
)
-- ── A: Market scorecard — all four dimensions ────────────────
SELECT
    market,
    -- Volume
    COUNT(order_id) AS total_orders,
    SUM(meals_count) AS total_meals,
    -- Cost Efficiency
    (SUM(actual_cost_eur)) AS total_actual_cost_eur,
    (SUM(ideal_cost_eur)) AS total_ideal_cost_eur,
    (SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100) AS cost_efficiency_pct,
    -- Sustainability
    (SUM(waste_m2)) AS total_paper_waste_m2,
    (AVG(waste_m2)) AS avg_waste_per_order_m2,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)  AS overboxed_orders,
    (SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
          / COUNT(order_id) * 100) AS overboxing_rate_pct,
    -- Quality
    SUM(is_damaged) AS damaged_orders,
    (SUM(is_damaged) * 100.0
          / COUNT(order_id)) AS damage_rate_pct,
    -- Overall packaging health index (composite)
    -- Simple average of cost efficiency and (1 - damage rate) and (1 - overboxing rate)
    ((
        SUM(ideal_cost_eur) / NULLIF(SUM(actual_cost_eur), 0) * 100
        + (100 - SUM(is_damaged) * 100.0 / COUNT(order_id))
        + (100 - SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
               / COUNT(order_id) * 100)
    ) / 3.0) AS overall_health_index_pct
FROM with_cost
GROUP  BY market
ORDER BY overall_health_index_pct DESC;

-- ── B: Box type efficiency by market ────────────────────────
-- Uncomment to run:
/*
SELECT
    market,
    pkg_id,
    COUNT(order_id) AS orders,
    (SUM(actual_cost_eur)) AS total_cost_eur,
    (AVG(actual_cost_eur)) AS avg_cost_eur,
    (SUM(waste_m2)) AS total_waste_m2,
    SUM(is_damaged) AS damaged,
    (SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100) AS efficiency_pct
FROM   with_cost
GROUP  BY market, pkg_id
ORDER BY market, efficiency_pct;
*/
