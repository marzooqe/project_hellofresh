WITH q1 AS (
    SELECT 
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM transform.fact_box_usage
    WHERE market  = 'DE'
      AND  order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND  pkg_id IS NOT NULL
),
sized AS (
    SELECT
        d.*,
        pm_act.surface_area_m2_normalised AS actual_area_m2,
        pm_rec.surface_area_m2_normalised AS recommended_area_m2,
        ds.recommended_pkg_id
    FROM   q1 d
    JOIN transform.dim_packaging_standards ds
           ON  d.meals_count = ds.meals_count
    JOIN transform.dim_packaging_master pm_act
           ON  d.pkg_id = pm_act.pkg_id
    JOIN transform.dim_packaging_master pm_rec
           ON  ds.recommended_pkg_id = pm_rec.pkg_id
),
-- Hard-code both rate periods for DE (Recycled Paper)
-- 2025 rate: €1.15/m²   2026 rate: €1.75/m²
decomposed AS (
    SELECT
        order_id,
        market,
        pkg_id,
        recommended_pkg_id,
        meals_count,
        order_date,
        actual_area_m2,
        recommended_area_m2,
        --What was actually paid
        (actual_area_m2      * 1.75)    AS actual_cost_eur,
        --What should have been paid (right box, 2026 price)
        (recommended_area_m2 * 1.75)    AS ideal_cost_eur,
        --Counter-factual: actual boxes at OLD 2025 price
        (actual_area_m2      * 1.15)    AS counterfactual_cost_eur,
        --Price hike impact: extra cost purely from rate change
        --    (same boxes, new rate vs old rate)
        ((1.75 - 1.15) * actual_area_m2) AS price_hike_impact_eur,
        --Over-boxing impact: extra cost from wrong box at 2026 rate
        (GREATEST(actual_area_m2 - recommended_area_m2, 0) * 1.75) AS overboxing_impact_eur,
        --Total overspend vs ideal
        ((actual_area_m2 - recommended_area_m2) * 1.75
              + (1.75 - 1.15) * recommended_area_m2)
          AS total_overspend_vs_ideal_eur
    FROM   sized
)
-- ── A: Order-level decomposition ────────────────────────────
SELECT
    order_id,
    pkg_id,
    recommended_pkg_id,
    meals_count,
    order_date,
    actual_area_m2,
    recommended_area_m2,
    actual_cost_eur,
    ideal_cost_eur,
    counterfactual_cost_eur,
    price_hike_impact_eur,
    overboxing_impact_eur,
    total_overspend_vs_ideal_eur
FROM   decomposed
ORDER BY order_date;


-- ── B: Aggregate totals and attribution split ───────────────
-- Uncomment to run:
/*
SELECT
    SUM(actual_cost_eur) AS total_actual_eur,
    SUM(ideal_cost_eur) AS total_ideal_eur,
    SUM(counterfactual_cost_eur) AS total_counterfactual_eur,
    SUM(price_hike_impact_eur) AS total_price_hike_impact_eur,
    SUM(overboxing_impact_eur) AS total_overboxing_impact_eur,
    -- Attribution split
    (SUM(price_hike_impact_eur) / NULLIF(SUM(price_hike_impact_eur)
                 + SUM(overboxing_impact_eur), 0) * 100) AS pct_price_hike,
    (SUM(overboxing_impact_eur) / NULLIF(SUM(price_hike_impact_eur)
                 + SUM(overboxing_impact_eur), 0) * 100) AS pct_overboxing
from decomposed;
*/
