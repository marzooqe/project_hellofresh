WITH deduped AS (
    SELECT DISTINCT
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM   fact_box_usage
    WHERE  order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND    pkg_id IS NOT NULL
),

-- normalise
with_area AS (
    SELECT
        d.*,
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END AS surface_area_m2
    FROM   deduped d
    INNER JOIN dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),

with_cost AS (
    SELECT
        a.*,
        pc.cost_per_m2,
        pc.currency
    FROM   with_area a
    INNER JOIN dim_procurement_costs pc
           ON  a.market = pc.market
           AND a.order_date BETWEEN pc.valid_from AND pc.valid_to
),

-- cost conv
with_eur AS (
    SELECT
        *,
        CASE
            WHEN currency = 'GBP'
            THEN cost_per_m2 * 1.17   -- FX rate
            ELSE cost_per_m2
        END AS cost_per_m2_eur,
        surface_area_m2 * CASE
            WHEN currency = 'GBP' THEN cost_per_m2 * 1.17
            ELSE cost_per_m2
        END AS order_cost_eur
    FROM with_cost
)

SELECT
    market,
    COUNT(order_id) AS order_count,
    ROUND(SUM(surface_area_m2), 2) AS total_surface_m2,
    ROUND(SUM(order_cost_eur), 4) AS total_cost_eur
FROM   with_eur
GROUP BY market
ORDER BY total_cost_eur DESC