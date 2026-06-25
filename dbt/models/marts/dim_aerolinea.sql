-- Dimension aerolinea: catalogo de aerolineas con metricas historicas
with flights as (
    select * from {{ ref('stg_flights') }}
),
aerolineas as (
    select distinct
        airline_iata,
        airline_name
    from flights
    where airline_iata is not null
),
metricas as (
    select
        airline_iata,
        count(*)                                                      as total_vuelos_historico,
        count(case when tiene_retraso = true then 1 end)              as total_retrasos_historico,
        round(
            count(case when tiene_retraso = true then 1 end) * 100.0
            / nullif(count(*), 0), 2
        )                                                             as pct_retraso_historico,
        round(avg(departure_delay_min), 1)                           as avg_retraso_historico_min,
        count(case when flight_status = 'cancelado' then 1 end)      as total_cancelaciones,
        min(flight_date)                                             as primera_operacion,
        max(flight_date)                                             as ultima_operacion
    from flights
    where airline_iata is not null
    group by airline_iata
)
select
    a.airline_iata,
    a.airline_name,
    m.total_vuelos_historico,
    m.total_retrasos_historico,
    m.pct_retraso_historico,
    m.avg_retraso_historico_min,
    m.total_cancelaciones,
    m.primera_operacion,
    m.ultima_operacion,
    -- Clasificacion de confiabilidad
    case
        when m.pct_retraso_historico <= 10 then 'alta'
        when m.pct_retraso_historico <= 25 then 'media'
        else 'baja'
    end as confiabilidad
from aerolineas a
left join metricas m on a.airline_iata = m.airline_iata
