
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

with_area AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status                                           AS pkg_status,
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END                                                 AS actual_area_m2
    FROM   deduped d
    JOIN transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
),

with_recommended AS (
    SELECT
        a.*,
        ds.recommended_pkg_id,
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END                                                 AS recommended_area_m2
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
        END                                                 AS cost_per_m2_eur,
        ROUND(r.actual_area_m2 * CASE
            WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
            ELSE pc.cost_per_m2
        END, 4)                                             AS actual_cost_eur,
        ROUND(COALESCE(r.recommended_area_m2, 0) * CASE
            WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
            ELSE pc.cost_per_m2
        END, 4)                                             AS ideal_cost_eur,
        GREATEST(r.actual_area_m2
                 - COALESCE(r.recommended_area_m2, r.actual_area_m2), 0)
                                                            AS waste_m2
    FROM   with_recommended r
    JOIN transform.dim_procurement_costs pc
           ON  r.market     = pc.market
           AND r.order_date BETWEEN pc.valid_from AND pc.valid_to
),

with_efficiency AS (
    SELECT
        *,
        ROUND(actual_area_m2 * cost_per_m2_eur, 4)         AS cost_inefficiency_eur,
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN ROUND(recommended_area_m2 / actual_area_m2 * 100, 1)
            ELSE NULL
        END                                                 AS efficiency_pct
    FROM   with_cost
)

-- ── A: Aggregated by material type ──────────────────────────
SELECT
    material_type,
    COUNT(order_id)                                 AS total_orders,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_actual_cost_eur,
    ROUND(AVG(actual_cost_eur), 4)                  AS avg_order_cost_eur,
    ROUND(SUM(waste_m2), 4)                         AS total_paper_waste_m2,
    ROUND(AVG(waste_m2), 4)                         AS avg_waste_per_order_m2,
    SUM(is_damaged)                                 AS damaged_orders,
    ROUND(SUM(is_damaged) * 100.0
          / COUNT(order_id), 1)                     AS damage_rate_pct,
    ROUND(AVG(efficiency_pct), 1)                   AS avg_efficiency_pct,
    ROUND(SUM(cost_inefficiency_eur), 4)            AS total_cost_inefficiency_eur
FROM   with_efficiency
GROUP  BY material_type
ORDER BY total_actual_cost_eur DESC;


-- ── B: Material type × market cross-tab ─────────────────────
-- Uncomment to run:
/*
SELECT
    material_type,
    market,
    COUNT(order_id)                                 AS orders,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_cost_eur,
    ROUND(SUM(waste_m2), 4)                         AS total_waste_m2,
    SUM(is_damaged)                                 AS damaged,
    ROUND(AVG(efficiency_pct), 1)                   AS avg_efficiency_pct
FROM   with_efficiency
GROUP  BY material_type, market
ORDER BY material_type, market;
*/


-- ── C: YoY same-box same-material price comparison ──────────
-- Isolates the pure price effect on Recycled Paper (DE P-S)
-- between 2025 and 2026 contract rates
-- Uncomment to run:
/*
SELECT
    YEAR(u.order_date)                              AS year,
    u.market,
    u.pkg_id,
    pm.material_type,
    pc.cost_per_m2                                  AS rate_local,
    pc.currency,
    CASE
        WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
        ELSE pc.cost_per_m2
    END                                             AS rate_eur_per_m2,
    ROUND(CASE
        WHEN pm.unit_of_measure = 'cm2'
        THEN pm.surface_area / 10000.0
        ELSE pm.surface_area
    END * CASE
        WHEN pc.currency = 'GBP' THEN pc.cost_per_m2 * 1.17
        ELSE pc.cost_per_m2
    END, 4)                                         AS cost_per_order_eur
FROM transform.fact_box_usage u
JOIN transform.dim_packaging_master pm   ON u.pkg_id    = pm.pkg_id
JOIN transform.dim_procurement_costs pc
       ON  u.market     = pc.market
       AND u.order_date BETWEEN pc.valid_from AND pc.valid_to
WHERE u.market  = 'DE'
  AND  u.pkg_id  = 'P-S'
  AND  u.pkg_id IS NOT NULL
ORDER BY year;
*/
