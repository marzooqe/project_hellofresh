
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
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END           AS actual_area_m2
    FROM   q1 d
    JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),

with_recommended AS (
    SELECT
        a.*,
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END           AS recommended_area_m2
    FROM   with_area a
    LEFT  JOIN transform.dim_packaging_standards ds
               ON  a.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
),

with_cost AS (
    SELECT
        r.*,
        CASE
            WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
            ELSE pc.cost_per_m2
        END           AS cost_per_m2_eur,
        ROUND(r.actual_area_m2 * CASE
            WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
            ELSE pc.cost_per_m2
        END, 4)       AS actual_cost_eur,
        ROUND(COALESCE(r.recommended_area_m2, r.actual_area_m2) * CASE
            WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
            ELSE pc.cost_per_m2
        END, 4)       AS ideal_cost_eur,
        GREATEST(r.actual_area_m2
                 - COALESCE(r.recommended_area_m2, r.actual_area_m2), 0)
                      AS waste_m2
    FROM   with_recommended r
    JOIN transform.dim_procurement_costs pc
           ON  r.market     = pc.market
           AND r.order_date BETWEEN pc.valid_from AND pc.valid_to
)

-- ── A: Market scorecard — all four dimensions ────────────────
SELECT
    market,

    -- Volume
    COUNT(order_id)                                 AS total_orders,
    SUM(meals_count)                                AS total_meals,

    -- Cost Efficiency
    ROUND(SUM(actual_cost_eur), 4)                  AS total_actual_cost_eur,
    ROUND(SUM(ideal_cost_eur), 4)                   AS total_ideal_cost_eur,
    ROUND(SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1)
              AS cost_efficiency_pct,

    -- Sustainability
    ROUND(SUM(waste_m2), 4)                         AS total_paper_waste_m2,
    ROUND(AVG(waste_m2), 4)                         AS avg_waste_per_order_m2,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)  AS overboxed_orders,
    ROUND(SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
          / COUNT(order_id) * 100, 1)               AS overboxing_rate_pct,

    -- Quality
    SUM(is_damaged)                                 AS damaged_orders,
    ROUND(SUM(is_damaged) * 100.0
          / COUNT(order_id), 1)                     AS damage_rate_pct,

    -- Overall packaging health index (composite)
    -- Simple average of cost efficiency and (1 - damage rate) and (1 - overboxing rate)
    ROUND((
        SUM(ideal_cost_eur) / NULLIF(SUM(actual_cost_eur), 0) * 100
        + (100 - SUM(is_damaged) * 100.0 / COUNT(order_id))
        + (100 - SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
               / COUNT(order_id) * 100)
    ) / 3.0, 1)                                     AS overall_health_index_pct

FROM   with_cost
GROUP  BY market
ORDER BY overall_health_index_pct DESC;


-- ── B: Box type efficiency by market ────────────────────────
-- Uncomment to run:
/*
SELECT
    market,
    pkg_id,
    COUNT(order_id)                                 AS orders,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_cost_eur,
    ROUND(AVG(actual_cost_eur), 4)                  AS avg_cost_eur,
    ROUND(SUM(waste_m2), 4)                         AS total_waste_m2,
    SUM(is_damaged)                                 AS damaged,
    ROUND(SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1)
              AS efficiency_pct
FROM   with_cost
GROUP  BY market, pkg_id
ORDER BY market, efficiency_pct;
*/
