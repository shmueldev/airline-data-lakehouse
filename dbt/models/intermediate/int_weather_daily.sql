-- Agregacion diaria de clima (puede haber multiples mediciones por dia)
with stg as (
    select * from {{ ref('stg_weather') }}
)
select
    weather_date,
    city,
    country,

    -- Promedios del dia
    round(avg(temp_c), 1)          as avg_temp_c,
    round(avg(temp_f), 1)          as avg_temp_f,
    round(avg(humidity), 0)        as avg_humidity,
    round(avg(wind_kph), 1)        as avg_wind_kph,
    round(avg(visibility_km), 1)   as avg_visibility_km,
    round(avg(chance_of_rain), 0)  as avg_chance_of_rain,
    round(avg(pressure_mb), 1)     as avg_pressure_mb,

    -- Maximos del dia
    max(temp_c)                    as max_temp_c,
    min(temp_c)                    as min_temp_c,
    max(wind_kph)                  as max_wind_kph,
    max(precip_mm)                 as max_precip_mm,
    max(cloud_coverage)            as max_cloud_coverage,

    -- Condicion predominante (la mas frecuente)
    max(condition)                 as condicion_predominante,

    -- Flag: hubo condiciones adversas en algun momento del dia
    max(cast(condiciones_adversas as int))  as hubo_condiciones_adversas,

    -- Categoria predominante de visibilidad
    max(visibilidad_categoria)     as visibilidad_categoria,
    max(viento_categoria)          as viento_categoria,
    max(temperatura_categoria)     as temperatura_categoria,

    count(*)                       as num_mediciones

from stg
group by weather_date, city, country
