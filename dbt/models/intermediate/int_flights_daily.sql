-- Agregacion diaria de vuelos con KPIs operativos completos
with stg as (
    select * from {{ ref('stg_flights') }}
)
select
    flight_date,

    -- Volumenes por estado
    count(*)                                                      as total_vuelos,
    count(case when flight_status = 'completado' then 1 end)     as vuelos_completados,
    count(case when flight_status = 'cancelado'  then 1 end)     as vuelos_cancelados,
    count(case when flight_status = 'programado' then 1 end)     as vuelos_programados,
    count(case when flight_status = 'en_vuelo'   then 1 end)     as vuelos_en_vuelo,

    -- Metricas de retraso
    count(case when tiene_retraso = true then 1 end)             as vuelos_con_retraso,
    round(
        count(case when tiene_retraso = true then 1 end) * 100.0
        / nullif(count(*), 0), 2
    )                                                             as pct_vuelos_con_retraso,
    round(avg(departure_delay_min), 1)                           as avg_retraso_salida_min,
    round(avg(arrival_delay_min), 1)                             as avg_retraso_llegada_min,
    max(departure_delay_min)                                     as max_retraso_salida_min,

    -- Retrasos por severidad
    count(case when severidad_retraso = 'menor'    then 1 end)   as retrasos_menores,
    count(case when severidad_retraso = 'moderado' then 1 end)   as retrasos_moderados,
    count(case when severidad_retraso = 'severo'   then 1 end)   as retrasos_severos,
    count(case when severidad_retraso = 'critico'  then 1 end)   as retrasos_criticos,

    -- Diversidad operativa
    count(distinct airline_iata)                                 as num_aerolineas,
    count(distinct departure_iata)                               as num_aeropuertos_origen,
    count(distinct arrival_iata)                                 as num_aeropuertos_destino,

    -- Tasa de completitud
    round(
        count(case when flight_status = 'completado' then 1 end) * 100.0
        / nullif(count(*), 0), 2
    )                                                             as pct_vuelos_completados

from stg
group by flight_date
