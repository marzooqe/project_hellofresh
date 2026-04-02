-- ============================================================
-- 05 · COST PER MEAL EFFICIENCY INDEX
-- HelloFresh Packaging Analysis
-- Normalises packaging cost by meal count to reveal true
-- unit economics — removes the natural size-bias of raw cost
-- ============================================================
-- Formula:
--   Actual CPM  = order_cost_eur / meals_count
--   Ideal CPM   = ideal_cost_eur / meals_count
--   CPM Premium = Actual CPM - Ideal CPM  (0 if perfect fit)
-- ============================================================

WITH deduped AS (
    SELECT DISTINCT
        order_id,
        market,
        pkg_id,
        meals_count,
        order_date,
        is_damaged
    FROM   transform.fact_box_usage
    WHERE  pkg_id IS NOT NULL
),

with_area AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.status                                           AS pkg_status,
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END                                                 AS actual_area_m2
    FROM   deduped d
    JOIN   transform.dim_packaging_master pm ON d.pkg_id = pm.pkg_id
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
        END                                                 AS cost_per_m2_eur
    FROM   with_recommended r
    JOIN   transform.dim_procurement_costs pc
           ON  r.market     = pc.market
           AND r.order_date BETWEEN pc.valid_from AND pc.valid_to
),

with_cpm AS (
    SELECT
        order_id,
        market,
        pkg_id,
        pkg_name,
        recommended_pkg_id,
        meals_count,
        order_date,
        actual_area_m2,
        recommended_area_m2,
        cost_per_m2_eur,
        is_damaged,

        -- Absolute costs
        ROUND(actual_area_m2      * cost_per_m2_eur, 4) AS actual_cost_eur,
        ROUND(recommended_area_m2 * cost_per_m2_eur, 4) AS ideal_cost_eur,

        -- Cost per meal (actual)
        ROUND(actual_area_m2      * cost_per_m2_eur
              / meals_count, 4)                          AS actual_cpm_eur,

        -- Cost per meal (ideal — NULL if no standard defined)
        ROUND(recommended_area_m2 * cost_per_m2_eur
              / meals_count, 4)                          AS ideal_cpm_eur,

        -- Premium paid per meal due to wrong box
        ROUND(
            (actual_area_m2 - COALESCE(recommended_area_m2, actual_area_m2))
            * cost_per_m2_eur / meals_count, 4)          AS cpm_premium_eur,

        -- Efficiency score: ideal / actual (100% = perfect)
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN ROUND(recommended_area_m2 / actual_area_m2 * 100, 1)
            ELSE NULL
        END                                              AS efficiency_pct

    FROM   with_cost
)

-- ── A: Order-level CPM (sorted worst to best) ───────────────
SELECT
    order_id,
    market,
    pkg_id,
    pkg_name,
    recommended_pkg_id,
    meals_count,
    order_date,
    actual_area_m2,
    recommended_area_m2,
    cost_per_m2_eur,
    actual_cost_eur,
    ideal_cost_eur,
    actual_cpm_eur,
    ideal_cpm_eur,
    cpm_premium_eur,
    efficiency_pct,
    is_damaged
FROM   with_cpm
ORDER  BY actual_cpm_eur DESC;


-- ── B: Overall CPM across all orders ────────────────────────
-- Uncomment to run:
/*
SELECT
    ROUND(SUM(actual_cost_eur) / SUM(meals_count), 4) AS overall_actual_cpm_eur,
    ROUND(SUM(ideal_cost_eur)  / SUM(meals_count), 4) AS overall_ideal_cpm_eur
FROM   with_cpm
WHERE  recommended_area_m2 IS NOT NULL;
*/


-- ── C: CPM by market ────────────────────────────────────────
-- Uncomment to run:
/*
SELECT
    market,
    COUNT(order_id)                                 AS orders,
    SUM(meals_count)                                AS total_meals,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_actual_cost_eur,
    ROUND(SUM(actual_cost_eur)
          / SUM(meals_count), 4)                    AS actual_cpm_eur,
    ROUND(SUM(ideal_cost_eur)
          / NULLIF(SUM(meals_count), 0), 4)         AS ideal_cpm_eur,
    ROUND(AVG(efficiency_pct), 1)                   AS avg_efficiency_pct
FROM   with_cpm
GROUP  BY market
ORDER  BY actual_cpm_eur DESC;
*/


-- ── D: Scale scenario — CPM waste at volume ─────────────────
-- What does the DE order 9002 (P-L for 2 meals) pattern cost at scale?
-- Uncomment to run:
/*
SELECT
    scenario_orders_per_month,
    ROUND(scenario_orders_per_month * 2.275, 2)     AS actual_monthly_cost_eur,
    ROUND(scenario_orders_per_month * 0.9625, 2)    AS ideal_monthly_cost_eur,
    ROUND(scenario_orders_per_month * (2.275 - 0.9625), 2)
                                                    AS monthly_waste_eur
FROM (
    VALUES (100), (500), (1000), (5000), (10000)
) AS t(scenario_orders_per_month)
ORDER  BY scenario_orders_per_month;
*/
