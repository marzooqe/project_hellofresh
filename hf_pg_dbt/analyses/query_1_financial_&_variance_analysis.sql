WITH with_area AS (
    SELECT
        d.order_id,
        d.market,
        order_date,
        surface_area_m2_normalised
    FROM transform.fact_box_usage d
    INNER JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
    WHERE order_date BETWEEN '2026-01-01' AND '2026-03-31' AND d.pkg_id IS NOT NULL
),
with_cost AS (
    SELECT
        a.*,
        pc.cost_per_m2_eur
    FROM with_area a
    INNER join transform.dim_procurement_cost  pc ON  a.market = pc.market
        AND a.order_date BETWEEN pc.valid_from AND pc.valid_to
),
with_eur AS (
    SELECT
        *,
        surface_area_m2_normalised * cost_per_m2_eur AS order_cost_eur
    FROM with_cost
)
SELECT
    market,
    COUNT(order_id) AS order_count,
    (SUM(surface_area_m2_normalised)) AS total_surface_m2,
    (SUM(order_cost_eur)) AS total_cost_eur
FROM with_eur
GROUP BY market
ORDER BY total_cost_eur DESC