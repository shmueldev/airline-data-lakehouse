with source as (
    select * from {{ source('caso6_db', 'delays') }}
)
select
    cast(report_date as date)                    as report_date,
    incident_id,
    user_id,
    incident_title,
    is_resolved,
    case
        when lower(incident_title) like '%critical%' then 'alta'
        when lower(incident_title) like '%urgent%'   then 'alta'
        when lower(incident_title) like '%error%'    then 'media'
        when lower(incident_title) like '%fail%'     then 'media'
        when lower(incident_title) like '%issue%'    then 'media'
        else 'baja'
    end as prioridad,
    case
        when is_resolved = true then 'resuelto'
        else 'pendiente'
    end as estado_incidente,
    ingested_at
from source
where report_date is not null
