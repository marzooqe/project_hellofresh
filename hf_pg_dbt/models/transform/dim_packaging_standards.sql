SELECT DISTINCT
      meals_count,
      recommended_pkg_id
FROM {{ source('staging','dim_packaging_standards') }}