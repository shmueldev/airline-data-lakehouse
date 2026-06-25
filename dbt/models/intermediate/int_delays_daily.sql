-- Agregacion diaria de incidentes de soporte
with stg as (
    select * from {{ ref('stg_delays') }}
)
select
    report_date,

    -- Volumenes
    count(*)                                                     as total_incidentes,
    count(case when is_resolved = true  then 1 end)              as incidentes_resueltos,
    count(case when is_resolved = false then 1 end)              as incidentes_pendientes,

    -- Por prioridad
    count(case when prioridad = 'alta'  then 1 end)              as incidentes_alta_prioridad,
    count(case when prioridad = 'media' then 1 end)              as incidentes_media_prioridad,
    count(case when prioridad = 'baja'  then 1 end)              as incidentes_baja_prioridad,

    -- Tasa de resolucion
    round(
        count(case when is_resolved = true then 1 end) * 100.0
        / nullif(count(*), 0), 2
    )                                                             as pct_resolucion,

    -- Tasa de criticos sin resolver
    round(
        count(case when prioridad = 'alta' and is_resolved = false then 1 end) * 100.0
        / nullif(count(case when prioridad = 'alta' then 1 end), 0), 2
    )                                                             as pct_criticos_sin_resolver,

    count(distinct user_id)                                      as num_agentes_activos

from stg
group by report_date
