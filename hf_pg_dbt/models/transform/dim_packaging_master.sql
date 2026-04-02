SELECT 
      pkg_id,
      pkg_name,
      material_type,
      surface_area,
      unit_of_measure,
      CASE
            WHEN unit_of_measure = 'cm2' THEN surface_area / 10000.0
            ELSE surface_area
        END AS surface_area_m2_normalised,
      status
FROM {{ source('staging','dim_packaging_master') }}