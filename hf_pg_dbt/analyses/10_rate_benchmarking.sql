SELECT
    market,
    material_type,
    cost_per_m2_eur rate_eur_per_m2,
    valid_from,
    valid_to
FROM transform.dim_procurement_cost
ORDER BY valid_from DESC, market;

-- ── B: DE premium vs each other market ──────────────────────
-- How much more DE pays per m² than UK and NL in 2026
/*
SELECT
    'DE vs NL' AS comparison,
    (1.75 - 1.25) AS rate_difference_eur,
    ((1.75 - 1.25) / 1.25 * 100) AS de_premium_pct

UNION ALL

SELECT
    'DE vs UK (GBP converted)',
    (1.75 - (1.10 * 1.17)),
    ((1.75 - (1.10 * 1.17)) / (1.10 * 1.17) * 100);
*/


-- ── C: Procurement savings model — DE rate negotiation ───────
-- Estimates monthly savings if DE rate is reduced to various targets
-- Assumes all Q1 2026 DE orders as the representative volume base
/*
WITH de_volume AS (
    SELECT
        SUM(pm.surface_area_m2_normalised)  AS total_area_m2
    FROM transform.fact_box_usage u
    JOIN transform.dim_packaging_master pm ON u.pkg_id = pm.pkg_id
    WHERE u.market = 'DE'
      AND  u.order_date BETWEEN '2026-01-01' AND '2026-03-31'
      AND  u.pkg_id IS NOT NULL
)
SELECT
    target_rate_eur AS target_rate_eur_per_m2,
    (1.75 - target_rate_eur) AS saving_per_m2,
    (total_area_m2 * (1.75 - target_rate_eur)) AS saving_on_q1_volume_eur,
    (total_area_m2 * (1.75 - target_rate_eur) * 4) AS annualised_saving_eur
FROM   de_volume
CROSS JOIN (
    VALUES (1.65), (1.55), (1.45), (1.35), (1.25)
) AS t(target_rate_eur)
ORDER BY target_rate_eur;
*/
