-- ============================================================
-- 04 · DE COST DECOMPOSITION — PRICE HIKE vs OVER-BOXING
-- HelloFresh Packaging Analysis
-- Splits Germany's Q1 2026 cost spike into two distinct drivers:
--   • External: Supplier price increase (Jan 2026 contract)
--   • Internal: Over-boxing (wrong box assignment — controllable)
-- ============================================================
-- Counter-factual logic:
--   Actual Cost         = actual_area_m2  × new_rate (€1.75)
--   Ideal Cost          = recommended_m2  × new_rate (€1.75)
--   Counter-factual     = actual_area_m2  × old_rate (€1.15)
--   Price Hike Impact   = (new_rate - old_rate) × actual_area_m2
--   Over-boxing Impact  = (actual_area_m2 - recommended_m2) × new_rate
-- ============================================================

WITH deduped AS (
    SELECT DISTINCT
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM   fact_box_usage
    WHERE  market  = 'DE'
      AND  order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND  pkg_id IS NOT NULL
),

-- Normalise actual and recommended surface areas
sized AS (
    SELECT
        d.*,
        CASE
            WHEN pm_act.unit_of_measure = 'cm2'
            THEN pm_act.surface_area / 10000.0
            ELSE pm_act.surface_area
        END                             AS actual_area_m2,
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END                             AS recommended_area_m2,
        ds.recommended_pkg_id
    FROM   deduped d
    JOIN   dim_packaging_standards ds
           ON  d.meals_count = ds.meals_count
    JOIN   dim_packaging_master pm_act
           ON  d.pkg_id = pm_act.pkg_id
    JOIN   dim_packaging_master pm_rec
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

        -- ① What was actually paid
        ROUND(actual_area_m2      * 1.75, 4)    AS actual_cost_eur,

        -- ② What should have been paid (right box, 2026 price)
        ROUND(recommended_area_m2 * 1.75, 4)    AS ideal_cost_eur,

        -- ③ Counter-factual: actual boxes at OLD 2025 price
        ROUND(actual_area_m2      * 1.15, 4)    AS counterfactual_cost_eur,

        -- ④ Price hike impact: extra cost purely from rate change
        --    (same boxes, new rate vs old rate)
        ROUND((1.75 - 1.15) * actual_area_m2, 4)
                                                AS price_hike_impact_eur,

        -- ⑤ Over-boxing impact: extra cost from wrong box at 2026 rate
        ROUND(GREATEST(actual_area_m2 - recommended_area_m2, 0) * 1.75, 4)
                                                AS overboxing_impact_eur,

        -- ⑥ Total overspend vs ideal
        ROUND((actual_area_m2 - recommended_area_m2) * 1.75
              + (1.75 - 1.15) * recommended_area_m2, 4)
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
ORDER  BY order_date;


-- ── B: Aggregate totals and attribution split ───────────────
-- Uncomment to run:
/*
SELECT
    SUM(actual_cost_eur)                AS total_actual_eur,
    SUM(ideal_cost_eur)                 AS total_ideal_eur,
    SUM(counterfactual_cost_eur)        AS total_counterfactual_eur,
    SUM(price_hike_impact_eur)          AS total_price_hike_impact_eur,
    SUM(overboxing_impact_eur)          AS total_overboxing_impact_eur,
    -- Attribution split
    ROUND(SUM(price_hike_impact_eur)
          / NULLIF(SUM(price_hike_impact_eur)
                 + SUM(overboxing_impact_eur), 0) * 100, 1)
                                        AS pct_price_hike,
    ROUND(SUM(overboxing_impact_eur)
          / NULLIF(SUM(price_hike_impact_eur)
                 + SUM(overboxing_impact_eur), 0) * 100, 1)
                                        AS pct_overboxing
FROM   decomposed;
*/
