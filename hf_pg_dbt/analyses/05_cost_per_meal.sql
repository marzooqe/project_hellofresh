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
        pm.status     AS pkg_status,
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
        cost_per_m2_eur
    FROM   with_recommended r
    JOIN transform.dim_procurement_cost pc
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
        (actual_area_m2      * cost_per_m2_eur) AS actual_cost_eur,
        (recommended_area_m2 * cost_per_m2_eur) AS ideal_cost_eur,
        -- Cost per meal (actual)
        (actual_area_m2      * cost_per_m2_eur / meals_count)                          AS actual_cpm_eur,
        -- Cost per meal (ideal — NULL if no standard defined)
        (recommended_area_m2 * cost_per_m2_eur
              / meals_count)                          AS ideal_cpm_eur,
        -- Premium paid per meal due to wrong box
        (
            (actual_area_m2 - COALESCE(recommended_area_m2, actual_area_m2))
            * cost_per_m2_eur / meals_count)          AS cpm_premium_eur,
        -- Efficiency score: ideal / actual (100% = perfect)
        CASE
            WHEN recommended_area_m2 IS NOT NULL
            THEN (recommended_area_m2 / actual_area_m2 * 100)
            ELSE NULL
        END        AS efficiency_pct
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
ORDER BY actual_cpm_eur DESC;


-- ── B: Overall CPM across all orders ────────────────────────
/*
SELECT
    (SUM(actual_cost_eur) / SUM(meals_count)) AS overall_actual_cpm_eur,
    (SUM(ideal_cost_eur)  / SUM(meals_count)) AS overall_ideal_cpm_eur
FROM   with_cpm
WHERE recommended_area_m2 IS NOT NULL;
*/

-- ── C: CPM by market ────────────────────────────────────────
/*
SELECT
    market,
    COUNT(order_id) AS orders,
    SUM(meals_count) AS total_meals,
    (SUM(actual_cost_eur)) AS total_actual_cost_eur,
    (SUM(actual_cost_eur)
          / SUM(meals_count)) AS actual_cpm_eur,
    (SUM(ideal_cost_eur)
          / NULLIF(SUM(meals_count), 0)) AS ideal_cpm_eur,
    (AVG(efficiency_pct)) AS avg_efficiency_pct
FROM   with_cpm
GROUP  BY market
ORDER BY actual_cpm_eur DESC;
*/

-- ── D: Scale scenario — CPM waste at volume ─────────────────
-- What does the DE order 9002 (P-L for 2 meals) pattern cost at scale?
/*
SELECT
    scenario_orders_per_month,
    (scenario_orders_per_month * 2.275)     AS actual_monthly_cost_eur,
    (scenario_orders_per_month * 0.9625)    AS ideal_monthly_cost_eur,
    (scenario_orders_per_month * (2.275 - 0.9625)) AS monthly_waste_eur
FROM (
    VALUES (100), (500), (1000), (5000), (10000)
) AS t(scenario_orders_per_month)
ORDER BY scenario_orders_per_month;
*/
