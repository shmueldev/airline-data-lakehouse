with source as (
    select * from {{ source('caso6_db', 'flights') }}
)
select
    cast(flight_date as date)                    as flight_date,
    flight_number,
    airline_name,
    airline_iata,
    departure_airport,
    departure_iata,
    departure_scheduled,
    coalesce(departure_delay_min, 0)             as departure_delay_min,
    arrival_airport,
    arrival_iata,
    arrival_scheduled,
    coalesce(arrival_delay_min, 0)               as arrival_delay_min,
    case
        when lower(flight_status) = 'landed'    then 'completado'
        when lower(flight_status) = 'scheduled' then 'programado'
        when lower(flight_status) = 'active'    then 'en_vuelo'
        when lower(flight_status) = 'cancelled' then 'cancelado'
        else 'desconocido'
    end as flight_status,
    case
        when coalesce(departure_delay_min, 0) > 15 then true
        else false
    end as tiene_retraso,
    case
        when coalesce(departure_delay_min, 0) = 0    then 'sin_retraso'
        when coalesce(departure_delay_min, 0) <= 15  then 'menor'
        when coalesce(departure_delay_min, 0) <= 60  then 'moderado'
        when coalesce(departure_delay_min, 0) <= 180 then 'severo'
        else 'critico'
    end as severidad_retraso,
    ingested_at
from source
where flight_date is not null
  and flight_number is not null
