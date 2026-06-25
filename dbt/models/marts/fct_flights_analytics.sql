with
flights as (select * from {{ ref('int_flights_daily') }}),
weather as (select * from {{ ref('int_weather_daily') }}),
delays as (
    select
        report_date,
        count(*) as total_incidentes,
        count(case when is_resolved = true then 1 end) as incidentes_resueltos,
        count(case when prioridad = 'alta' then 1 end) as incidentes_alta_prioridad,
        cast(count(case when is_resolved = true then 1 end) as double) * 100.0 / cast(count(*) as double) as pct_resolucion
    from {{ ref('stg_delays') }}
    group by report_date
)
select
    f.flight_date as fecha,
    year(f.flight_date) as anio,
    month(f.flight_date) as mes,
    day(f.flight_date) as dia,
    day_of_week(f.flight_date) as dia_semana,
    f.total_vuelos,
    f.vuelos_completados,
    f.vuelos_cancelados,
    f.vuelos_con_retraso,
    f.pct_vuelos_con_retraso,
    f.avg_retraso_salida_min,
    f.avg_retraso_llegada_min,
    f.max_retraso_salida_min,
    f.num_aerolineas,
    w.avg_temp_c,
    w.avg_humidity,
    w.avg_wind_kph,
    w.avg_visibility_km,
    w.avg_chance_of_rain,
    w.max_precip_mm,
    w.hubo_condiciones_adversas,
    w.condicion_predominante,
    w.visibilidad_categoria,
    w.viento_categoria,
    w.temperatura_categoria,
    coalesce(d.total_incidentes, 0) as total_incidentes,
    coalesce(d.incidentes_resueltos, 0) as incidentes_resueltos,
    coalesce(d.incidentes_alta_prioridad, 0) as incidentes_alta_prioridad,
    coalesce(d.pct_resolucion, 0.0) as pct_resolucion_incidentes,
    case
        when f.pct_vuelos_con_retraso > 30
          or f.vuelos_cancelados > 5
          or w.hubo_condiciones_adversas = 1
        then true else false
    end as dia_critico,
    cast(current_timestamp as timestamp) as dbt_updated_at
from flights f
left join weather w on f.flight_date = w.weather_date
left join delays d on f.flight_date = d.report_date
