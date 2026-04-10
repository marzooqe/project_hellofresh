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
        pm.surface_area_m2_normalised AS actual_area_m2,
        pm_rec.surface_area_m2_normalised AS recommended_area_m2,
        ds.recommended_pkg_id,
        pc.cost_per_m2_eur,
        EXTRACT(YEAR FROM d.order_date) AS yr
    FROM   q1 d
    JOIN transform.dim_packaging_master pm    ON d.pkg_id = pm.pkg_id
    LEFT  JOIN transform.dim_packaging_standards ds ON d.meals_count = ds.meals_count
    LEFT  JOIN transform.dim_packaging_master pm_rec
               ON  ds.recommended_pkg_id = pm_rec.pkg_id
    JOIN transform.dim_procurement_cost pc
           ON  d.market     = pc.market
           AND d.order_date BETWEEN pc.valid_from AND pc.valid_to
),
calculated AS (
    SELECT
        *,
        (actual_area_m2 * cost_per_m2_eur) AS actual_cost_eur,
        (COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur) AS ideal_cost_eur,
        GREATEST(actual_area_m2
                 - COALESCE(recommended_area_m2, actual_area_m2), 0) AS waste_m2,
        (actual_area_m2       * cost_per_m2_eur
              / meals_count) AS actual_cpm_eur,
        (COALESCE(recommended_area_m2, actual_area_m2)
                                   * cost_per_m2_eur
              / meals_count) AS ideal_cpm_eur
    FROM enriched
)
SELECT
    COUNT(order_id) AS total_clean_orders,
    SUM(meals_count) AS total_meals,
    (SUM(actual_cost_eur)) AS total_actual_cost_eur,
    (SUM(ideal_cost_eur)) AS total_ideal_cost_eur,
    (SUM(actual_cost_eur) - SUM(ideal_cost_eur)) AS total_cost_inefficiency_eur,
    ((SUM(actual_cost_eur) - SUM(ideal_cost_eur))
          / NULLIF(SUM(actual_cost_eur), 0) * 100) AS pct_spend_wasted,
    (SUM(ideal_cost_eur)
          / NULLIF(SUM(actual_cost_eur), 0) * 100) AS overall_cost_efficiency_pct,
    (SUM(actual_cost_eur) / NULLIF(SUM(meals_count), 0)) AS overall_actual_cpm_eur,
    (SUM(ideal_cost_eur)  / NULLIF(SUM(meals_count), 0)) AS overall_ideal_cpm_eur,
    (SUM(waste_m2)) AS total_paper_waste_m2,
    (AVG(waste_m2)) AS avg_waste_per_order_m2,
    SUM(CASE WHEN waste_m2 > 0 THEN 1 ELSE 0 END)  AS overboxed_orders,
    (SUM(CASE WHEN waste_m2 > 0 THEN 1.0 ELSE 0.0 END)
          / COUNT(order_id) * 100) AS overboxing_rate_pct,
    SUM(is_damaged) AS damaged_orders,
    (SUM(is_damaged) * 100.0
          / COUNT(order_id)) AS overall_damage_rate_pct,
    (SELECT COUNT(*) FROM transform.fact_box_usage WHERE pkg_id IS NULL) AS null_pkg_id_orders,
    (SELECT COUNT(*) - COUNT(DISTINCT order_id)
     FROM transform.fact_box_usage WHERE pkg_id IS NOT NULL) AS duplicate_order_rows
FROM calculated
