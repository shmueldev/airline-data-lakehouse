#!/bin/bash
# =============================================================================
# CASO 6 — Proyecto dbt completo con modelo estrella profesional
# Ejecutar desde la carpeta raiz del repositorio
# Uso: bash setup_dbt_v2.sh
# =============================================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
sec()  { echo -e "\n${BOLD}${CYAN}── $1 ──────────────────────────────────────${NC}"; }

echo -e "\n${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   CASO 6 — dbt Modelo Estrella Profesional  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

# ── ESTRUCTURA ────────────────────────────────────────────────────────────────
info "Creando estructura de carpetas..."
mkdir -p airline/dbt_airline/models/staging
mkdir -p airline/dbt_airline/models/intermediate
mkdir -p airline/dbt_airline/models/marts
ok "Estructura lista"

# ═════════════════════════════════════════════════════════════════════════════
sec "dbt_project.yml"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/dbt_project.yml << 'EOF'
name: dbt_airline
version: '1.0.0'
config-version: 2
profile: dbt_airline

model-paths: ['models']
target-path: 'target'
clean-targets: ['target', 'dbt_packages']

models:
  dbt_airline:
    staging:
      +materialized: view
      +schema: caso6_db
    intermediate:
      +materialized: table
      +schema: caso6_db
    marts:
      +materialized: table
      +schema: caso6_db
      +s3_data_dir: s3://caso6-curated/
      +s3_tmp_table_dir: s3://caso6-curated/tmp/
EOF
ok "dbt_project.yml"

# ═════════════════════════════════════════════════════════════════════════════
sec "STAGING — sources.yml"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/staging/sources.yml << 'EOF'
version: 2

sources:
  - name: caso6_db
    database: awsdatacatalog
    schema: caso6_db
    tables:
      - name: flights
        description: Vuelos crudos de AviationStack procesados por Glue ETL
      - name: weather
        description: Clima de Medellin de WeatherAPI procesado por Glue ETL
      - name: delays
        description: Incidentes de soporte de JSONPlaceholder procesados por Glue ETL
EOF
ok "sources.yml"

# ═════════════════════════════════════════════════════════════════════════════
sec "STAGING — stg_flights.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/staging/stg_flights.sql << 'EOF'
-- Limpieza y normalizacion de vuelos
-- Fuente: AviationStack API -> S3 raw -> Glue ETL -> Athena
with source as (
    select * from {{ source('caso6_db', 'flights') }}
)
select
    -- Claves
    flight_date,
    flight_number,
    airline_iata,
    departure_iata,
    arrival_iata,

    -- Descriptivos
    airline_name,
    departure_airport,
    departure_scheduled,
    arrival_airport,
    arrival_scheduled,

    -- Metricas de retraso (null -> 0)
    coalesce(departure_delay_min, 0) as departure_delay_min,
    coalesce(arrival_delay_min, 0)   as arrival_delay_min,

    -- Estado normalizado al espanol
    case
        when lower(flight_status) = 'landed'    then 'completado'
        when lower(flight_status) = 'scheduled' then 'programado'
        when lower(flight_status) = 'active'    then 'en_vuelo'
        when lower(flight_status) = 'cancelled' then 'cancelado'
        else 'desconocido'
    end as flight_status,

    -- Flag de retraso (>15 min se considera retraso operativo)
    case
        when coalesce(departure_delay_min, 0) > 15 then true
        else false
    end as tiene_retraso,

    -- Categoria de severidad del retraso
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
EOF
ok "stg_flights.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "STAGING — stg_weather.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/staging/stg_weather.sql << 'EOF'
-- Limpieza y normalizacion de datos climaticos
-- Fuente: WeatherAPI -> S3 raw -> Glue ETL -> Athena
with source as (
    select * from {{ source('caso6_db', 'weather') }}
)
select
    -- Claves
    weather_date,
    city,
    country,

    -- Descriptivos de ubicacion
    region,
    local_time,
    latitude,
    longitude,

    -- Metricas climaticas
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

    -- Categoria de visibilidad (critica para operaciones aereas)
    case
        when visibility_km >= 10 then 'excelente'
        when visibility_km >= 5  then 'buena'
        when visibility_km >= 2  then 'reducida'
        else 'muy_baja'
    end as visibilidad_categoria,

    -- Categoria de viento
    case
        when wind_kph < 20 then 'calma'
        when wind_kph < 40 then 'moderado'
        when wind_kph < 60 then 'fuerte'
        else 'muy_fuerte'
    end as viento_categoria,

    -- Categoria de temperatura
    case
        when temp_c < 10 then 'frio'
        when temp_c < 20 then 'fresco'
        when temp_c < 28 then 'templado'
        else 'calido'
    end as temperatura_categoria,

    -- Flag de condiciones adversas para aviacion
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
EOF
ok "stg_weather.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "STAGING — stg_delays.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/staging/stg_delays.sql << 'EOF'
-- Limpieza y normalizacion de incidentes de soporte
-- Fuente: JSONPlaceholder API -> S3 raw -> Glue ETL -> Athena
with source as (
    select * from {{ source('caso6_db', 'delays') }}
)
select
    -- Claves
    report_date,
    incident_id,
    user_id,

    -- Descriptivos
    incident_title,
    is_resolved,

    -- Clasificacion de prioridad por palabras clave
    case
        when lower(incident_title) like '%critical%' then 'alta'
        when lower(incident_title) like '%urgent%'   then 'alta'
        when lower(incident_title) like '%error%'    then 'media'
        when lower(incident_title) like '%fail%'     then 'media'
        when lower(incident_title) like '%issue%'    then 'media'
        else 'baja'
    end as prioridad,

    -- Estado legible
    case
        when is_resolved = true then 'resuelto'
        else 'pendiente'
    end as estado_incidente,

    ingested_at

from source
where report_date is not null
EOF
ok "stg_delays.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "INTERMEDIATE — int_flights_daily.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/intermediate/int_flights_daily.sql << 'EOF'
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
EOF
ok "int_flights_daily.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "INTERMEDIATE — int_weather_daily.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/intermediate/int_weather_daily.sql << 'EOF'
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
EOF
ok "int_weather_daily.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "INTERMEDIATE — int_delays_daily.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/intermediate/int_delays_daily.sql << 'EOF'
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
EOF
ok "int_delays_daily.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "MARTS — dim_fecha.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/marts/dim_fecha.sql << 'EOF'
-- Dimension fecha: genera un calendario con todos los atributos de tiempo
-- Se construye a partir de las fechas que existen en los datos
with fechas_flights as (
    select distinct flight_date as fecha from {{ ref('stg_flights') }}
),
fechas_weather as (
    select distinct weather_date as fecha from {{ ref('stg_weather') }}
),
fechas_delays as (
    select distinct report_date as fecha from {{ ref('stg_delays') }}
),
todas_fechas as (
    select fecha from fechas_flights
    union
    select fecha from fechas_weather
    union
    select fecha from fechas_delays
)
select
    fecha,
    year(fecha)                                   as anio,
    month(fecha)                                  as mes,
    day(fecha)                                    as dia,
    dayofweek(fecha)                              as dia_semana_num,  -- 1=domingo, 7=sabado
    -- Nombre del dia
    case dayofweek(fecha)
        when 1 then 'Domingo'
        when 2 then 'Lunes'
        when 3 then 'Martes'
        when 4 then 'Miercoles'
        when 5 then 'Jueves'
        when 6 then 'Viernes'
        when 7 then 'Sabado'
    end as nombre_dia,
    -- Nombre del mes
    case month(fecha)
        when 1  then 'Enero'    when 2  then 'Febrero'
        when 3  then 'Marzo'    when 4  then 'Abril'
        when 5  then 'Mayo'     when 6  then 'Junio'
        when 7  then 'Julio'    when 8  then 'Agosto'
        when 9  then 'Septiembre' when 10 then 'Octubre'
        when 11 then 'Noviembre' when 12 then 'Diciembre'
    end as nombre_mes,
    -- Trimestre
    case
        when month(fecha) in (1,2,3)   then 'Q1'
        when month(fecha) in (4,5,6)   then 'Q2'
        when month(fecha) in (7,8,9)   then 'Q3'
        else 'Q4'
    end as trimestre,
    -- Es fin de semana
    case when dayofweek(fecha) in (1,7) then true else false end as es_fin_de_semana,
    -- Semana del anio
    weekofyear(fecha)                             as semana_anio,
    -- Formato display
    date_format(fecha, 'dd/MM/yyyy')              as fecha_display

from todas_fechas
order by fecha
EOF
ok "dim_fecha.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "MARTS — dim_aerolinea.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/marts/dim_aerolinea.sql << 'EOF'
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
EOF
ok "dim_aerolinea.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "MARTS — dim_aeropuerto.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/marts/dim_aeropuerto.sql << 'EOF'
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
EOF
ok "dim_aeropuerto.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "MARTS — dim_condicion_clima.sql"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/marts/dim_condicion_clima.sql << 'EOF'
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
EOF
ok "dim_condicion_clima.sql"

# ═════════════════════════════════════════════════════════════════════════════
sec "MARTS — fct_flights_analytics.sql (tabla central del modelo estrella)"
# ═════════════════════════════════════════════════════════════════════════════
cat > airline/dbt_airline/models/marts/fct_flights_analytics.sql << 'EOF'
-- Fact central del modelo estrella
-- Une KPIs diarios de vuelos + clima + incidentes
-- Se une con las 4 dimensiones via flight_date / weather_date / report_date
with
flights as (select * from {{ ref('int_flights_daily') }}),
weather as (select * from {{ ref('int_weather_daily') }}),
delays  as (select * from {{ ref('int_delays_daily') }})

select
    -- ── CLAVES (joins con dimensiones) ──────────────────────────────────────
    f.flight_date                              as fecha,          -- -> dim_fecha
    w.city                                     as ciudad_clima,   -- -> dim_condicion_clima
    w.condicion_predominante                   as condicion_clima, -- -> dim_condicion_clima

    -- ── DIMENSIONES DE TIEMPO (desnormalizadas para conveniencia BI) ────────
    year(f.flight_date)                        as anio,
    month(f.flight_date)                       as mes,
    day(f.flight_date)                         as dia,
    dayofweek(f.flight_date)                   as dia_semana,
    case dayofweek(f.flight_date)
        when 1 then 'Domingo'  when 2 then 'Lunes'
        when 3 then 'Martes'   when 4 then 'Miercoles'
        when 5 then 'Jueves'   when 6 then 'Viernes'
        when 7 then 'Sabado'
    end                                        as nombre_dia,
    case when dayofweek(f.flight_date) in (1,7)
        then true else false
    end                                        as es_fin_de_semana,

    -- ── KPIs OPERATIVOS DE VUELOS ────────────────────────────────────────────
    f.total_vuelos,
    f.vuelos_completados,
    f.vuelos_cancelados,
    f.vuelos_programados,
    f.vuelos_en_vuelo,
    f.vuelos_con_retraso,
    f.pct_vuelos_con_retraso,
    f.pct_vuelos_completados,
    f.avg_retraso_salida_min,
    f.avg_retraso_llegada_min,
    f.max_retraso_salida_min,
    f.retrasos_menores,
    f.retrasos_moderados,
    f.retrasos_severos,
    f.retrasos_criticos,
    f.num_aerolineas,
    f.num_aeropuertos_origen,
    f.num_aeropuertos_destino,

    -- ── KPIs CLIMATICOS ──────────────────────────────────────────────────────
    w.avg_temp_c,
    w.avg_temp_f,
    w.avg_humidity,
    w.avg_wind_kph,
    w.avg_visibility_km,
    w.avg_chance_of_rain,
    w.avg_pressure_mb,
    w.max_temp_c,
    w.min_temp_c,
    w.max_wind_kph,
    w.max_precip_mm,
    w.hubo_condiciones_adversas,
    w.visibilidad_categoria,
    w.viento_categoria,
    w.temperatura_categoria,
    w.num_mediciones                           as mediciones_clima,

    -- ── KPIs DE INCIDENTES DE SOPORTE ────────────────────────────────────────
    coalesce(d.total_incidentes, 0)            as total_incidentes,
    coalesce(d.incidentes_resueltos, 0)        as incidentes_resueltos,
    coalesce(d.incidentes_pendientes, 0)       as incidentes_pendientes,
    coalesce(d.incidentes_alta_prioridad, 0)   as incidentes_alta_prioridad,
    coalesce(d.incidentes_media_prioridad, 0)  as incidentes_media_prioridad,
    coalesce(d.incidentes_baja_prioridad, 0)   as incidentes_baja_prioridad,
    coalesce(d.pct_resolucion, 0)              as pct_resolucion_incidentes,
    coalesce(d.pct_criticos_sin_resolver, 0)   as pct_criticos_sin_resolver,
    coalesce(d.num_agentes_activos, 0)         as num_agentes_activos,

    -- ── INDICADORES COMPUESTOS ───────────────────────────────────────────────
    -- Dia operativamente critico (multiples condiciones)
    case
        when f.pct_vuelos_con_retraso > 30
          or f.vuelos_cancelados > 5
          or w.hubo_condiciones_adversas = 1
          or coalesce(d.incidentes_alta_prioridad, 0) > 3
        then true
        else false
    end                                        as dia_critico,

    -- Score de rendimiento operativo (0-100, mayor es mejor)
    round(
        (f.pct_vuelos_completados * 0.5)
        + ((100 - f.pct_vuelos_con_retraso) * 0.3)
        + (coalesce(d.pct_resolucion, 100) * 0.2)
    , 1)                                       as score_rendimiento,

    -- Correlacion clima-retraso (flag cuando hay adversidad Y retrasos altos)
    case
        when w.hubo_condiciones_adversas = 1
         and f.pct_vuelos_con_retraso > 20
        then true
        else false
    end                                        as clima_impacto_operaciones,

    current_timestamp()                        as dbt_updated_at

from flights f
left join weather w on f.flight_date = w.weather_date
left join delays  d on f.flight_date = d.report_date
EOF
ok "fct_flights_analytics.sql"

# ═════════════════════════════════════════════════════════════════════════════
# SUBIR A S3
# ═════════════════════════════════════════════════════════════════════════════
echo ""
info "Subiendo proyecto dbt a S3..."
aws s3 sync airline/dbt_airline/ s3://caso6-processed/dbt-project/ --delete
ok "Proyecto subido a s3://caso6-processed/dbt-project/"

# ═════════════════════════════════════════════════════════════════════════════
# RESUMEN
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║       MODELO ESTRELLA PROFESIONAL LISTO              ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Estructura creada:${NC}"
echo -e "  ${CYAN}staging/${NC}       stg_flights, stg_weather, stg_delays"
echo -e "  ${CYAN}intermediate/${NC}  int_flights_daily, int_weather_daily, int_delays_daily"
echo -e "  ${CYAN}marts/${NC}         dim_fecha, dim_aerolinea, dim_aeropuerto, dim_condicion_clima"
echo -e "  ${CYAN}marts/${NC}         fct_flights_analytics  (tabla central)"
echo ""
echo -e "${BOLD}Modelo estrella:${NC}"
echo -e "  fct_flights_analytics"
echo -e "    ├── dim_fecha           (via fecha)"
echo -e "    ├── dim_aerolinea       (via airline_iata)"
echo -e "    ├── dim_aeropuerto      (via departure_iata / arrival_iata)"
echo -e "    └── dim_condicion_clima (via condicion_clima)"
echo ""
echo -e "${BOLD}Ejecuta el pipeline completo:${NC}"
echo -e "  ${YELLOW}aws stepfunctions start-execution \\${NC}"
echo -e "  ${YELLOW}  --state-machine-arn arn:aws:states:us-east-1:661779457956:stateMachine:caso6-pipeline \\${NC}"
echo -e "  ${YELLOW}  --input '{}'${NC}"
echo ""
