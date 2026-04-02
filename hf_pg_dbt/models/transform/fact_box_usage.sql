SELECT DISTINCT
      order_id,
      market,
      pkg_id,
      meals_count,
      order_date,
      is_damaged
FROM {{ source('staging','fact_box_usage') }}