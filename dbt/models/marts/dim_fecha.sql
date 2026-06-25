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
    day_of_week(fecha)                              as dia_semana_num,  -- 1=domingo, 7=sabado
    -- Nombre del dia
    case day_of_week(fecha)
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
    case when day_of_week(fecha) in (1,7) then true else false end as es_fin_de_semana,
    -- Semana del anio
    week(fecha)                             as semana_anio,
    -- Formato display
    date_format(fecha, 'dd/MM/yyyy')              as fecha_display

from todas_fechas
order by fecha
