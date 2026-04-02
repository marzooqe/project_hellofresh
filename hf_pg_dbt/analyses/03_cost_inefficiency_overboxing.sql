-- ============================================================
-- 03 · COST INEFFICIENCY — OVER-BOXING DETECTION
-- HelloFresh Packaging Analysis
-- Identifies orders where actual box > recommended box size,
-- quantifying paper waste (m²) and monetary cost inefficiency
-- ============================================================
-- Definition:
--   Cost Inefficiency (EUR) = Waste m² × Cost per m² (EUR)
--   Waste m²               = actual_area_m2 - recommended_area_m2
--                            (clipped to 0; negative = under-box)
--   Fit Ratio              = actual_area_m2 / recommended_area_m2
--                            (1.0 = perfect fit, >1.0 = over-boxed)
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

-- Normalise both actual and recommended box surface areas to m²
sized AS (
    SELECT
        d.*,
        -- Actual box area
        CASE
            WHEN pm_act.unit_of_measure = 'cm2'
            THEN pm_act.surface_area / 10000.0
            ELSE pm_act.surface_area
        END                             AS actual_area_m2,
        pm_act.pkg_name                 AS actual_pkg_name,
        pm_act.material_type            AS actual_material,
        -- Recommended box area
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END                             AS recommended_area_m2,
        ds.recommended_pkg_id,
        pm_rec.pkg_name                 AS recommended_pkg_name
    FROM   deduped d
    JOIN transform.dim_packaging_standards ds
           ON  d.meals_count = ds.meals_count
    JOIN transform.dim_packaging_master pm_act
           ON  d.pkg_id = pm_act.pkg_id
    JOIN transform.dim_packaging_master pm_rec
           ON  ds.recommended_pkg_id = pm_rec.pkg_id
),

-- Compute fit metrics and join procurement rate
with_metrics AS (
    SELECT
        s.*,
        -- Fit ratio: 1.0 = perfect, >1 = over-boxed, <1 = under-boxed
        ROUND(s.actual_area_m2 / s.recommended_area_m2, 4)
                                        AS fit_ratio,
        -- Waste surface area (0 if not over-boxed)
        GREATEST(s.actual_area_m2 - s.recommended_area_m2, 0)
                                        AS waste_m2,
        -- Fit category
        CASE
            WHEN s.actual_area_m2 = s.recommended_area_m2 THEN 'Perfect Fit'
            WHEN s.actual_area_m2 < s.recommended_area_m2 THEN 'Under-boxed'
            WHEN s.actual_area_m2 / s.recommended_area_m2 <= 1.2
                THEN 'Slight Over-box'
            WHEN s.actual_area_m2 / s.recommended_area_m2 <= 1.5
                THEN 'Moderate Over-box'
            ELSE 'Severe Over-box'
        END                             AS fit_category,
        -- Number of box sizes skipped (P-S=1, P-M=2, P-L=3, P-XL=4)
        CASE d2.pkg_id
            WHEN 'P-S'  THEN 1
            WHEN 'P-M'  THEN 2
            WHEN 'P-L'  THEN 3
            WHEN 'P-XL' THEN 4
        END -
        CASE s.recommended_pkg_id
            WHEN 'P-S'  THEN 1
            WHEN 'P-M'  THEN 2
            WHEN 'P-L'  THEN 3
            WHEN 'P-XL' THEN 4
        END                             AS overbox_levels,
        -- Point-in-time EUR cost rate
        CASE
            WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
            ELSE pc.cost_per_m2
        END                             AS cost_per_m2_eur
    FROM   sized s
    JOIN transform.fact_box_usage d2  ON s.order_id = d2.order_id AND d2.pkg_id IS NOT NULL
    JOIN transform.dim_procurement_costs pc
           ON  s.market     = pc.market
           AND s.order_date BETWEEN pc.valid_from AND pc.valid_to
),

-- Final cost calculations
with_cost AS (
    SELECT
        *,
        ROUND(actual_area_m2     * cost_per_m2_eur, 4) AS actual_cost_eur,
        ROUND(recommended_area_m2 * cost_per_m2_eur, 4) AS ideal_cost_eur,
        ROUND(waste_m2           * cost_per_m2_eur, 4) AS cost_inefficiency_eur
    FROM   with_metrics
)

-- ── A: Order-level detail (all orders) ──────────────────────
SELECT
    order_id,
    market,
    pkg_id          AS actual_pkg,
    actual_pkg_name,
    recommended_pkg_id,
    recommended_pkg_name,
    meals_count,
    order_date,
    actual_area_m2,
    recommended_area_m2,
    waste_m2,
    fit_ratio,
    overbox_levels,
    fit_category,
    cost_per_m2_eur,
    actual_cost_eur,
    ideal_cost_eur,
    cost_inefficiency_eur,
    is_damaged
FROM   with_cost
ORDER BY cost_inefficiency_eur DESC, order_date;

-- ── B: Summary by market (aggregated waste & inefficiency) ──
-- Uncomment to run instead of query A:
/*
SELECT
    market,
    COUNT(*)                                AS total_orders,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)
                                            AS overboxed_orders,
    ROUND(SUM(waste_m2), 4)                 AS total_paper_waste_m2,
    ROUND(SUM(cost_inefficiency_eur), 4)    AS total_cost_inefficiency_eur,
    ROUND(AVG(fit_ratio), 4)                AS avg_fit_ratio,
    ROUND(SUM(cost_inefficiency_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1)
                                            AS pct_spend_wasted
FROM   with_cost
GROUP  BY market
ORDER BY total_cost_inefficiency_eur DESC;
*/
