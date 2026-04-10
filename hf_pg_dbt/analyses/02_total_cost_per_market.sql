WITH q1 AS (
    SELECT 
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM transform.fact_box_usage
    WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND  pkg_id IS NOT NULL
),
with_area AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status     AS pkg_status,
        surface_area_m2_normalised
    from q1 d
    JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),
with_cost AS (
    SELECT
        a.*,
        pc.cost_per_m2_eur,
        pc.currency,
        surface_area_m2_normalised * cost_per_m2_eur AS order_cost_eur
    FROM   with_area a
    JOIN transform.dim_procurement_cost pc
   ON  a.market     = pc.market
   AND a.order_date BETWEEN pc.valid_from AND pc.valid_to
)
SELECT
    market,
    COUNT(order_id)         AS order_count,
    (SUM(surface_area_m2_normalised))  AS total_surface_m2,
    (AVG(cost_per_m2_eur))  AS avg_rate_eur_per_m2,
    (SUM(order_cost_eur))   AS total_cost_eur,
    (AVG(order_cost_eur))   AS avg_order_cost_eur,
    SUM(is_damaged)         AS damaged_orders,
    ROUND(SUM(is_damaged) * 100.0
  / COUNT(order_id), 1)     AS damage_rate_pct
FROM   with_cost
GROUP  BY market
ORDER BY total_cost_eur DESC