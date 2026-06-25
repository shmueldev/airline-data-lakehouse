-- Dimension aeropuerto: catalogo de aeropuertos de origen y destino
with origen as (
    select distinct
        departure_iata  as airport_iata,
        departure_airport as airport_name,
        'origen'        as tipo
    from {{ ref('stg_flights') }}
    where departure_iata is not null
),
destino as (
    select distinct
        arrival_iata    as airport_iata,
        arrival_airport as airport_name,
        'destino'       as tipo
    from {{ ref('stg_flights') }}
    where arrival_iata is not null
),
todos as (
    select airport_iata, airport_name from origen
    union
    select airport_iata, airport_name from destino
),
metricas_origen as (
    select
        departure_iata                                               as airport_iata,
        count(*)                                                     as vuelos_como_origen,
        round(
            count(case when tiene_retraso = true then 1 end) * 100.0
            / nullif(count(*), 0), 2
        )                                                            as pct_retraso_como_origen
    from {{ ref('stg_flights') }}
    where departure_iata is not null
    group by departure_iata
),
metricas_destino as (
    select
        arrival_iata                                                 as airport_iata,
        count(*)                                                     as vuelos_como_destino,
        round(
            count(case when tiene_retraso = true then 1 end) * 100.0
            / nullif(count(*), 0), 2
        )                                                            as pct_retraso_como_destino
    from {{ ref('stg_flights') }}
    where arrival_iata is not null
    group by arrival_iata
)
select
    t.airport_iata,
    t.airport_name,
    coalesce(mo.vuelos_como_origen, 0)          as vuelos_como_origen,
    coalesce(md.vuelos_como_destino, 0)         as vuelos_como_destino,
    coalesce(mo.vuelos_como_origen, 0)
      + coalesce(md.vuelos_como_destino, 0)     as total_movimientos,
    coalesce(mo.pct_retraso_como_origen, 0)     as pct_retraso_como_origen,
    coalesce(md.pct_retraso_como_destino, 0)    as pct_retraso_como_destino
from todos t
left join metricas_origen  mo on t.airport_iata = mo.airport_iata
left join metricas_destino md on t.airport_iata = md.airport_iata
