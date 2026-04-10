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
sized AS (
    SELECT
        d.*,
        -- Actual box area
 		pm_act.surface_area_m2_normalised  AS actual_area_m2,
        pm_act.pkg_name AS actual_pkg_name,
        pm_act.material_type AS actual_material,
        -- Recommended box area
        pm_rec.surface_area_m2_normalised  AS recommended_area_m2,
        ds.recommended_pkg_id,
        pm_rec.pkg_name AS recommended_pkg_name
    FROM   q1 d
    JOIN transform.dim_packaging_standards ds
           ON  d.meals_count = ds.meals_count
    JOIN transform.dim_packaging_master pm_act
           ON  d.pkg_id = pm_act.pkg_id
    JOIN transform.dim_packaging_master pm_rec
           ON  ds.recommended_pkg_id = pm_rec.pkg_id
),
with_metrics AS (
    SELECT
        s.*,
        -- Fit ratio: 1.0 = perfect, >1 = over-boxed, <1 = under-boxed
        (s.actual_area_m2 / s.recommended_area_m2)
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
        END AS fit_category,
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
        END AS overbox_levels,
        -- Point-in-time EUR cost rate
        cost_per_m2_eur
    FROM   sized s
    JOIN transform.fact_box_usage d2 ON s.order_id = d2.order_id AND d2.pkg_id IS NOT NULL
    JOIN transform.dim_procurement_cost pc
           ON  s.market = pc.market
           AND s.order_date BETWEEN pc.valid_from AND pc.valid_to
),
with_cost AS (
    SELECT
        *,
        (actual_area_m2 * cost_per_m2_eur) AS actual_cost_eur,
        (recommended_area_m2 * cost_per_m2_eur) AS ideal_cost_eur,
        (waste_m2 * cost_per_m2_eur) AS cost_inefficiency_eur
    FROM   with_metrics
)
SELECT
    order_id,
    market,
    pkg_id AS actual_pkg,
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
/*
SELECT
    market,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)
      AS overboxed_orders,
    (SUM(waste_m2)) AS total_paper_waste_m2,
    (SUM(cost_inefficiency_eur)) AS total_cost_inefficiency_eur,
    (AVG(fit_ratio)) AS avg_fit_ratio,
    (SUM(cost_inefficiency_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1)
      AS pct_spend_wasted
FROM   with_cost
GROUP  BY market
ORDER BY total_cost_inefficiency_eur DESC;
*/
