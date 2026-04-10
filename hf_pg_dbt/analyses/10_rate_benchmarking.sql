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

/*
-- ============================================================
-- DE IMPACT MODEL: P-L → P-M BOX MIGRATION
-- If X% of Large (P-L) boxes in Germany are migrated to (P-M)
WITH box_areas AS (
    SELECT
        MAX(CASE WHEN pkg_id = 'P-L'
            then surface_area_m2_normalised
            END)                            AS pl_area_m2,
        MAX(CASE WHEN pkg_id = 'P-M'
            then surface_area_m2_normalised
            END)                            AS pm_area_m2
    FROM   dim_packaging_master
    WHERE  pkg_id IN ('P-L', 'P-M')
),
de_rate AS (
    SELECT cost_per_m2                      AS rate_eur
    FROM   dim_procurement_cost
    WHERE  market      = 'DE'
      AND  '2026-01-01' BETWEEN valid_from AND valid_to
),
savings_per_box AS (
    SELECT
        b.pl_area_m2,
        b.pm_area_m2,
        (b.pl_area_m2 - b.pm_area_m2)          AS area_saved_m2,
        r.rate_eur,
        ((b.pl_area_m2 - b.pm_area_m2)
              * r.rate_eur)                          AS saving_per_box_eur
    FROM   box_areas b
    CROSS  JOIN de_rate r
)
-- ── Monthly savings across volume and migration % scenarios ──
SELECT
    monthly_pl_boxes,
    migration_pct,
    (monthly_pl_boxes * migration_pct / 100.0)     AS boxes_migrated,
    s.saving_per_box_eur,
    (monthly_pl_boxes
          * migration_pct / 100.0
          * s.saving_per_box_eur)                    AS monthly_saving_eur,
    (monthly_pl_boxes
          * migration_pct / 100.0
          * s.saving_per_box_eur * 12)               AS annual_saving_eur,
    (monthly_pl_boxes
          * migration_pct / 100.0
          * (s.pl_area_m2 - s.pm_area_m2))           AS monthly_paper_saved_m2
FROM   savings_per_box s
CROSS  JOIN (
    VALUES
        (500,   10), (500,   20), (500,   30),
        (1000,  10), (1000,  20), (1000,  30),
        (5000,  10), (5000,  20), (5000,  30),
        (10000, 10), (10000, 20), (10000, 30)
) AS t(monthly_pl_boxes, migration_pct)
ORDER  BY monthly_pl_boxes, migration_pct;
*/
