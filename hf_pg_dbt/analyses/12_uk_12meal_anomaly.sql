SELECT
    u.order_id,
    u.market,
    u.pkg_id,
    pm.pkg_name,
    pm.status                                       AS pkg_status,
    u.meals_count,
    u.order_date,
    u.is_damaged,
    CASE
        WHEN pm.unit_of_measure = 'cm2'
        THEN pm.surface_area / 10000.0
        ELSE pm.surface_area
    END                                             AS actual_area_m2,
    CASE
        WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
        ELSE pc.cost_per_m2
    END                                             AS cost_per_m2_eur,
    ROUND(
        CASE WHEN pm.unit_of_measure = 'cm2'
             THEN pm.surface_area / 10000.0
             ELSE pm.surface_area END *
        CASE WHEN pc.currency = 'GBP'
             THEN pc.cost_per_m2 * 1.17
             ELSE pc.cost_per_m2 END, 4)            AS actual_cost_eur,
    ROUND(
        CASE WHEN pm.unit_of_measure = 'cm2'
             THEN pm.surface_area / 10000.0
             ELSE pm.surface_area END *
        CASE WHEN pc.currency = 'GBP'
             THEN pc.cost_per_m2 * 1.17
             ELSE pc.cost_per_m2 END / u.meals_count, 4)
                                                    AS apparent_cpm_eur,
    'No standard defined for 12 meals'             AS standards_gap
FROM transform.fact_box_usage u
JOIN transform.dim_packaging_master pm  ON u.pkg_id    = pm.pkg_id
JOIN transform.dim_procurement_costs pc
       ON  u.market     = pc.market
       AND u.order_date BETWEEN pc.valid_from AND pc.valid_to
WHERE u.order_id = 9005;


-- ── B: Scenario cost comparison — what should it have cost? ──
-- Comparing actual vs three correct-sizing scenarios
-- Uncomment to run:
/*
SELECT
    scenario,
    box_config,
    surface_area_m2,
    ROUND(surface_area_m2 * 1.287, 4)              AS cost_eur,       -- UK rate GBP 1.10 × 1.17
    ROUND(surface_area_m2 * 1.287 / 12, 4)         AS cost_per_meal_eur,
    food_risk
FROM (
    VALUES
        ('Actual #9005',         '1× P-S',             0.55, '🚨 Critical — severe under-boxing'),
        ('1× P-L (6 meals max)', '1× P-L',             1.30, '⚠ Moderate — still insufficient'),
        ('Correct: 2× P-L',      '2× P-L',             2.60, '✅ Acceptable — two 6-meal boxes'),
        ('Alt: P-XL + P-M',      '1× P-XL + 1× P-M',  2.70, '⚠ Uses discontinued P-XL stock')
) AS t(scenario, box_config, surface_area_m2, food_risk)
ORDER BY cost_eur;
*/


-- ── C: Standards gap — meal counts without a recommendation ──
-- Reveals which meal counts have no transform.dim_packaging_standards entry
-- Uncomment to run:
/*
SELECT DISTINCT
    u.meals_count,
    ds.recommended_pkg_id,
    CASE
        WHEN ds.recommended_pkg_id IS NULL
        THEN 'NO STANDARD — box assignment undefined'
        ELSE 'Standard defined'
    END                                             AS standards_status,
    COUNT(u.order_id)                               AS affected_orders
FROM transform.fact_box_usage u
LEFT  JOIN transform.dim_packaging_standards ds ON u.meals_count = ds.meals_count
GROUP  BY u.meals_count, ds.recommended_pkg_id
ORDER BY u.meals_count;
*/
