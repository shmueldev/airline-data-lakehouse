-- Dimension condicion climatica: catalogo de condiciones con impacto operativo
with stg as (
    select * from {{ ref('stg_weather') }}
),
condiciones as (
    select distinct
        condition as condicion_texto
    from stg
    where condition is not null
),
metricas as (
    select
        condition,
        count(*)                                    as frecuencia,
        round(avg(visibility_km), 1)                as avg_visibility_km,
        round(avg(wind_kph), 1)                     as avg_wind_kph,
        round(avg(chance_of_rain), 0)               as avg_chance_of_rain,
        round(avg(temp_c), 1)                       as avg_temp_c,
        max(cast(condiciones_adversas as int))      as genera_condiciones_adversas
    from stg
    group by condition
)
select
    c.condicion_texto,
    m.frecuencia,
    m.avg_visibility_km,
    m.avg_wind_kph,
    m.avg_chance_of_rain,
    m.avg_temp_c,
    m.genera_condiciones_adversas,
    -- Nivel de impacto operativo
    case
        when m.genera_condiciones_adversas = 1       then 'alto'
        when m.avg_chance_of_rain > 60               then 'medio'
        when m.avg_visibility_km < 5                 then 'medio'
        else 'bajo'
    end as impacto_operativo,
    -- Grupo de condicion
    case
        when lower(c.condicion_texto) like '%rain%'   then 'lluvia'
        when lower(c.condicion_texto) like '%cloud%'  then 'nublado'
        when lower(c.condicion_texto) like '%sun%'    then 'soleado'
        when lower(c.condicion_texto) like '%clear%'  then 'despejado'
        when lower(c.condicion_texto) like '%fog%'    then 'niebla'
        when lower(c.condicion_texto) like '%storm%'  then 'tormenta'
        when lower(c.condicion_texto) like '%snow%'   then 'nieve'
        else 'otro'
    end as grupo_condicion
from condiciones c
left join metricas m on c.condicion_texto = m.condition
