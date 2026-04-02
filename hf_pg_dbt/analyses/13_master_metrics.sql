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
enriched AS (
    SELECT
        d.*,
        pm.pkg_name,
        pm.material_type,
        pm.status AS pkg_status,
        CASE
            WHEN pm.unit_of_measure = 'cm2'
            THEN pm.surface_area / 10000.0
            ELSE pm.surface_area
        END AS actual_area_m2,
        CASE
            WHEN pm_rec.unit_of_measure = 'cm2'
            THEN pm_rec.surface_area / 10000.0
            ELSE pm_rec.surface_area
        END AS recommended_area_m2,
        ds.recommended_pkg_id,
        CASE
            WHEN pc.currency = 'GBP' THEN ROUND(pc.cost_per_m2 * 1.17, 4)
            ELSE pc.cost_per_m2
        END AS cost_per_m2_eur,
        YEAR(d.order_date) AS yr
    FROM   q1 d
    JOIN transform.dim_packaging_master pm    ON d.pkg_id = pm.pkg_id
    LEFT  JOIN transform.dim_packaging_standards ds ON d.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
    JOIN transform.dim_procurement_costs pc
           ON  d.market     = pc.market
           AND d.order_date BETWEEN pc.valid_from AND pc.valid_to
),
calculated AS (
    SELECT
        *,
        ROUND(actual_area_m2 * cost_per_m2_eur, 4) AS actual_cost_eur,
        ROUND(COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur, 4) AS ideal_cost_eur,
        GREATEST(actual_area_m2
                 - COALESCE(recommended_area_m2, actual_area_m2), 0) AS waste_m2,
        ROUND(actual_area_m2       * cost_per_m2_eur
              / meals_count, 4) AS actual_cpm_eur,
        ROUND(COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur
              / meals_count, 4) AS ideal_cpm_eur
    FROM enriched
)
SELECT
    COUNT(order_id)                                 AS total_clean_orders,
    SUM(meals_count)                                AS total_meals,
    ROUND(SUM(actual_cost_eur), 4)                  AS total_actual_cost_eur,
    ROUND(SUM(ideal_cost_eur), 4)                   AS total_ideal_cost_eur,
    ROUND(SUM(actual_cost_eur) - SUM(ideal_cost_eur), 4) AS total_cost_inefficiency_eur,
    ROUND((SUM(actual_cost_eur) - SUM(ideal_cost_eur))
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1) AS pct_spend_wasted,
    ROUND(SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100, 1) AS overall_cost_efficiency_pct,
    ROUND(SUM(actual_cost_eur) / NULLIF(SUM(meals_count), 0), 4) AS overall_actual_cpm_eur,
    ROUND(SUM(ideal_cost_eur)  / NULLIF(SUM(meals_count), 0), 4) AS overall_ideal_cpm_eur,
    ROUND(SUM(waste_m2), 4) AS total_paper_waste_m2,
    ROUND(AVG(waste_m2), 4) AS avg_waste_per_order_m2,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)  AS overboxed_orders,
    ROUND(SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
          / COUNT(order_id) * 100, 1) AS overboxing_rate_pct,
    SUM(is_damaged) AS damaged_orders,
    ROUND(SUM(is_damaged) * 100.0
          / COUNT(order_id), 1) AS overall_damage_rate_pct,
    (SELECT COUNT(*) FROM transform.fact_box_usage WHERE pkg_id IS NULL) AS null_pkg_id_orders,
    (SELECT COUNT(*) - COUNT(DISTINCT order_id)
     FROM transform.fact_box_usage WHERE pkg_id IS NOT NULL) AS duplicate_order_rows
FROM calculated
