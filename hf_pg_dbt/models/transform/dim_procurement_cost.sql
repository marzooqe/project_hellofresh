SELECT DISTINCT
      market,
      material_type,
      cost_per_m2,
      currency,
      CASE
        WHEN currency = 'GBP' THEN cost_per_m2 * 1.17
        ELSE cost_per_m2 END AS cost_per_m2_eur,
      valid_from,
      valid_to
FROM {{ source('staging','dim_procurement_cost') }}