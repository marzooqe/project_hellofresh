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
        pm.pkg_name,
        pm.material_type,
        pm.status AS pkg_status,
        pm.surface_area_m2_normalised AS actual_area_m2
    FROM   q1 d
    JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),
with_recommended AS (
    SELECT
        a.*,
        ds.recommended_pkg_id,
        pm_rec.surface_area_m2_normalised AS recommended_area_m2
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
        (COALESCE(r.recommended_area_m2, 0) * cost_per_m2_eur) AS ideal_cost_eur,
        GREATEST(r.actual_area_m2
                 - COALESCE(r.recommended_area_m2, r.actual_area_m2), 0) AS waste_m2
    FROM   with_recommended r
    JOIN transform.dim_procurement_cost pc
           ON  r.market     = pc.market
           AND r.order_date BETWEEN pc.valid_from AND pc.valid_to
),
with_efficiency AS (
    SELECT
        *,
        (actual_area_m2 * cost_per_m2_eur)         AS cost_inefficiency_eur,
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN (recommended_area_m2 / actual_area_m2 * 100)
            ELSE NULL
        END           AS efficiency_pct
    FROM   with_cost
)
-- ── A: Aggregated by material type ──────────────────────────
SELECT
    material_type,
    COUNT(order_id) AS total_orders,
    (SUM(actual_cost_eur)) AS total_actual_cost_eur,
    (AVG(actual_cost_eur)) AS avg_order_cost_eur,
    (SUM(waste_m2)) AS total_paper_waste_m2,
    (AVG(waste_m2)) AS avg_waste_per_order_m2,
    SUM(is_damaged) AS damaged_orders,
    (SUM(is_damaged) * 100.0
          / COUNT(order_id)) AS damage_rate_pct,
    (AVG(efficiency_pct)) AS avg_efficiency_pct,
    (SUM(cost_inefficiency_eur)) AS total_cost_inefficiency_eur
FROM   with_efficiency
GROUP  BY material_type
ORDER BY total_actual_cost_eur DESC;


-- ── B: Material type × market cross-tab ─────────────────────
/*
SELECT
    material_type,
    market,
    COUNT(order_id) AS orders,
    (SUM(actual_cost_eur)) AS total_cost_eur,
    (SUM(waste_m2)) AS total_waste_m2,
    SUM(is_damaged) AS damaged,
    (AVG(efficiency_pct)) AS avg_efficiency_pct
FROM   with_efficiency
GROUP  BY material_type, market
ORDER BY material_type, market;
*/

-- ── C: YoY same-box same-material price comparison ──────────
-- Isolates the pure price effect on Recycled Paper (DE P-S)
-- between 2025 and 2026 contract rates
/*
SELECT
    (u.order_date) AS year,
    u.market,
    u.pkg_id,
    pm.material_type,
    pc.cost_per_m2_eur AS rate_local,
    pc.currency,
    cost_per_m2_eur AS rate_eur_per_m2,
    (pm.surface_area_m2_normalised * pc.cost_per_m2_eur)   AS cost_per_order_eur
FROM transform.fact_box_usage u
JOIN transform.dim_packaging_master pm   ON u.pkg_id    = pm.pkg_id
JOIN transform.dim_procurement_cost pc
       ON  u.market = pc.market
       AND u.order_date BETWEEN pc.valid_from AND pc.valid_to
WHERE u.market  = 'DE'
  AND  u.pkg_id  = 'P-S'
  AND  u.pkg_id IS NOT NULL
ORDER BY year;
*/
