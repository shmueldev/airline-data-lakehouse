with source as (
    select * from {{ source('caso6_db', 'weather') }}
)
select
    cast(weather_date as date)                   as weather_date,
    city,
    region,
    country,
    local_time,
    temp_c,
    temp_f,
    humidity,
    wind_kph,
    wind_direction,
    pressure_mb,
    precip_mm,
    cloud_coverage,
    visibility_km,
    condition,
    chance_of_rain,
    case
        when visibility_km >= 10 then 'excelente'
        when visibility_km >= 5  then 'buena'
        when visibility_km >= 2  then 'reducida'
        else 'muy_baja'
    end as visibilidad_categoria,
    case
        when wind_kph < 20 then 'calma'
        when wind_kph < 40 then 'moderado'
        when wind_kph < 60 then 'fuerte'
        else 'muy_fuerte'
    end as viento_categoria,
    case
        when temp_c < 10 then 'frio'
        when temp_c < 20 then 'fresco'
        when temp_c < 28 then 'templado'
        else 'calido'
    end as temperatura_categoria,
    case
        when visibility_km < 2
          or wind_kph > 60
          or precip_mm > 10
          or cloud_coverage > 90
        then true
        else false
    end as condiciones_adversas,
    ingested_at
from source
where weather_date is not null
