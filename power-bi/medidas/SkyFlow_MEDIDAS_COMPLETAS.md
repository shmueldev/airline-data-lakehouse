# SkyFlow — MEDIDAS DAX COMPLETAS (Base + 33 HTML)
> Creadas desde cero con las columnas reales confirmadas del modelo.
> ORDEN: primero crea las MEDIDAS BASE (Bloque 0), luego las 33 HTML.

---

## ══════════════════════════════════════════
## BLOQUE 0 — MEDIDAS BASE (crear primero)
## Tabla: fct_vuelos
## ══════════════════════════════════════════

### 0.1 Total Vuelos
```dax
Total Vuelos = COUNTROWS(fct_vuelos)
```

### 0.2 Vuelos a Tiempo
```dax
Vuelos a Tiempo =
CALCULATE(
    COUNTROWS(fct_vuelos),
    fct_vuelos[tiene_retraso] = FALSE()
)
```

### 0.3 Pct a Tiempo
```dax
Pct a Tiempo =
DIVIDE([Vuelos a Tiempo], [Total Vuelos])
```

### 0.4 Total Cancelados
```dax
Total Cancelados =
CALCULATE(
    COUNTROWS(fct_vuelos),
    fct_vuelos[flight_status] = "cancelled"
)
```

### 0.5 Pct Cancelados
```dax
Pct Cancelados =
DIVIDE([Total Cancelados], [Total Vuelos])
```

### 0.6 Avg Retraso Min
```dax
Avg Retraso Min =
AVERAGE(fct_vuelos[retraso_salida_min])
```

### 0.7 Total Min Retraso
```dax
Total Min Retraso =
SUM(fct_vuelos[retraso_salida_min])
```

### 0.8 Indice Eficiencia
```dax
Indice Eficiencia =
DIVIDE(
    [Vuelos a Tiempo],
    [Total Vuelos] - [Total Cancelados]
)
```

### 0.9 Vuelos Afectados Clima
```dax
Vuelos Afectados Clima =
CALCULATE(
    COUNTROWS(fct_vuelos),
    fct_vuelos[condiciones_adversas] = TRUE()
)
```

---

## Tabla: fct_incidentes

### 0.10 Total Incidentes
```dax
Total Incidentes = COUNTROWS(fct_incidentes)
```

### 0.11 Casos Cerrados
```dax
Casos Cerrados =
CALCULATE(
    COUNTROWS(fct_incidentes),
    fct_incidentes[is_resolved] = TRUE()
)
```

### 0.12 Casos Abiertos
```dax
Casos Abiertos =
CALCULATE(
    COUNTROWS(fct_incidentes),
    fct_incidentes[is_resolved] = FALSE()
)
```

### 0.13 Pct Resolucion
```dax
Pct Resolucion =
DIVIDE([Casos Cerrados], [Total Incidentes])
```

### 0.14 Avg Satisfaccion
```dax
Avg Satisfaccion =
AVERAGE(fct_incidentes[satisfaccion_cliente])
```

### 0.15 Avg Tiempo Resolucion
```dax
Avg Tiempo Resolucion =
AVERAGE(fct_incidentes[tiempo_resolucion_horas])
```

---

## Tabla: fct_clima_diario

### 0.16 Avg Temperatura
```dax
Avg Temperatura =
AVERAGE(fct_clima_diario[avg_temp_c])
```

### 0.17 Dias Con Clima Adverso
```dax
Dias Con Clima Adverso =
CALCULATE(
    COUNTROWS(fct_clima_diario),
    fct_clima_diario[hubo_condiciones_adversas] = TRUE()
)
```

---

## ══════════════════════════════════════════
## BLOQUE 1 — PÁGINA 1: TORRE DE CONTROL
## Tabla donde crear: fct_vuelos
## ══════════════════════════════════════════

### P1-V1 — Mapa de Flujo de Rutas
```dax
HTML_P1_V1_MapaRutas =
VAR _Tabla =
    ADDCOLUMNS(
        SUMMARIZE(
            fct_vuelos,
            fct_vuelos[origen_iata],
            fct_vuelos[destino_iata]
        ),
        "vuelos", CALCULATE([Total Vuelos])
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(30, _Tabla, [vuelos], DESC),
        fct_vuelos[origen_iata] & "→" & fct_vuelos[destino_iata] & ":" & [vuelos],
        "|",
        [vuelos], DESC
    )
RETURN
    "{""tipo"":""mapa_rutas"",""data"":""" & _Filas & """}"
```

---

### P1-V2 — Top 10 Aerolíneas por Retraso Promedio
```dax
HTML_P1_V2_TopAerolineasRetraso =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[airline_name]),
        "avg_ret", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(10, _Tabla, [avg_ret], DESC),
        fct_vuelos[airline_name] & ":" & FORMAT([avg_ret], "0.0"),
        "|",
        [avg_ret], DESC
    )
RETURN
    "{""tipo"":""barra_h"",""titulo"":""Top 10 Aerolíneas · Retraso Prom (min)"",""data"":""" & _Filas & """}"
```

---

### P1-V3 — % a Tiempo vs % Con Retraso por Aerolínea
```dax
HTML_P1_V3_BarraApilada100 =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[airline_name]),
        "pct_t", CALCULATE([Pct a Tiempo]),
        "pct_r", 1 - CALCULATE([Pct a Tiempo]) - CALCULATE([Pct Cancelados]),
        "pct_c", CALCULATE([Pct Cancelados])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        fct_vuelos[airline_name]
            & ":" & FORMAT([pct_t] * 100, "0.0")
            & ":" & FORMAT(MAX([pct_r], 0) * 100, "0.0")
            & ":" & FORMAT([pct_c] * 100, "0.0"),
        "|",
        [pct_t], DESC
    )
RETURN
    "{""tipo"":""barra_apilada100"",""cols"":""aerolinea:pct_tiempo:pct_retraso:pct_cancelado"",""data"":""" & _Filas & """}"
```

---

### P1-V4 — Funnel de Vuelos
```dax
HTML_P1_V4_Funnel =
VAR _PctCanc     = IF([Pct Cancelados] >= 1, 0.999, [Pct Cancelados])
VAR _Planif      = FORMAT(DIVIDE([Total Vuelos], 1 - _PctCanc), "0")
VAR _Ejecutados  = FORMAT([Total Vuelos], "0")
VAR _Completados = FORMAT([Vuelos a Tiempo], "0")
VAR _Cancelados  = FORMAT([Total Cancelados], "0")
RETURN
    "{""tipo"":""funnel"",""data"":""Planificados:" & _Planif
        & "|Ejecutados:"  & _Ejecutados
        & "|Completados:" & _Completados
        & "|Cancelados:"  & _Cancelados & """}"
```

---

### P1-V5 — Treemap Destinos
```dax
HTML_P1_V5_TreemapDestinos =
VAR _Total = [Total Vuelos]
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[destino_iata]),
        "vuelos", CALCULATE([Total Vuelos])
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(15, _Tabla, [vuelos], DESC),
        fct_vuelos[destino_iata]
            & ":" & FORMAT([vuelos], "0")
            & ":" & FORMAT(DIVIDE([vuelos], _Total) * 100, "0.0"),
        "|",
        [vuelos], DESC
    )
RETURN
    "{""tipo"":""treemap"",""cols"":""destino:vuelos:pct"",""data"":""" & _Filas & """}"
```

---

### P1-V6 — Retraso por Destino Crítico y Aerolínea
```dax
HTML_P1_V6_BarraAgrupadaDestinoAerolinea =
VAR _Criticos = {"BOG","MDE","CLO","CTG","MIA"}
VAR _Tabla =
    ADDCOLUMNS(
        FILTER(
            SUMMARIZE(
                fct_vuelos,
                fct_vuelos[destino_iata],
                fct_vuelos[airline_name]
            ),
            fct_vuelos[destino_iata] IN _Criticos
        ),
        "avg_ret", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        fct_vuelos[destino_iata] & "~" & fct_vuelos[airline_name]
            & ":" & FORMAT([avg_ret], "0.0"),
        "|",
        fct_vuelos[destino_iata], ASC
    )
RETURN
    "{""tipo"":""barra_agrupada"",""ejes"":""destino~aerolinea:avg_retraso"",""data"":""" & _Filas & """}"
```

---

### P1-V7 — Heatmap Día de Semana × Congestión
```dax
HTML_P1_V7_HeatmapDiaSemana =
VAR _Tabla =
    ADDCOLUMNS(
        SUMMARIZE(
            fct_vuelos,
            dim_fecha[nombre_dia],
            dim_fecha[dia_semana_num]
        ),
        "vuelos",  CALCULATE([Total Vuelos]),
        "retraso", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        dim_fecha[nombre_dia]
            & ":" & FORMAT([vuelos],  "0")
            & ":" & FORMAT([retraso], "0.0"),
        "|",
        dim_fecha[dia_semana_num], ASC
    )
RETURN
    "{""tipo"":""heatmap"",""cols"":""dia:vuelos:retraso"",""data"":""" & _Filas & """}"
```

---

### P1-V8 — Evolución Diaria de Vuelos
```dax
HTML_P1_V8_LineaEvolucionDiaria =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "vuelos", CALCULATE([Total Vuelos])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        dim_fecha[fecha_display] & ":" & FORMAT([vuelos], "0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""linea"",""data"":""" & _Filas & """}"
```

---

### P1-V9 — Gráfico de Control Estadístico de Retrasos
```dax
HTML_P1_V9_ControlRetraso =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "avg_ret", CALCULATE([Avg Retraso Min])
    )
VAR _Media  = AVERAGEX(_Tabla, [avg_ret])
VAR _StdDev = SQRT(AVERAGEX(_Tabla, ([avg_ret] - _Media) ^ 2))
VAR _LSC    = _Media + 2 * _StdDev
VAR _LIC    = MAX(0, _Media - 2 * _StdDev)
VAR _Filas  =
    CONCATENATEX(
        _Tabla,
        dim_fecha[fecha_display] & ":" & FORMAT([avg_ret], "0.0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""control_chart"",""lsc"":"  & FORMAT(_LSC,   "0.0")
        & ",""lic"":"                        & FORMAT(_LIC,   "0.0")
        & ",""media"":"                      & FORMAT(_Media, "0.0")
        & ",""data"":"""                     & _Filas & """}"
```

---

### P1-V10 — Waterfall Cancelaciones por Semana
```dax
HTML_P1_V10_WaterfallCancelaciones =
VAR _Tabla =
    ADDCOLUMNS(
        SUMMARIZE(dim_fecha, dim_fecha[semana_anio], dim_fecha[mes]),
        "cancelados", CALCULATE([Total Cancelados])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        "Sem" & dim_fecha[semana_anio] & ":" & FORMAT([cancelados], "0"),
        "|",
        dim_fecha[semana_anio], ASC
    )
RETURN
    "{""tipo"":""waterfall"",""data"":""" & _Filas & """}"
```

---

### P1-V11 — Semáforo Operativo por Aerolínea
```dax
HTML_P1_V11_Semaforo =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[airline_name]),
        "pct_t", CALCULATE([Pct a Tiempo]),
        "pct_r", CALCULATE(
            DIVIDE(
                COUNTROWS(FILTER(fct_vuelos, fct_vuelos[tiene_retraso] = TRUE())),
                [Total Vuelos]
            )
        ),
        "pct_c", CALCULATE([Pct Cancelados])
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        fct_vuelos[airline_name]
            & ":" & FORMAT([pct_t] * 100, "0.0")
            & ":" & FORMAT([pct_r] * 100, "0.0")
            & ":" & FORMAT([pct_c] * 100, "0.0"),
        "|",
        [pct_t], DESC
    )
RETURN
    "{""tipo"":""semaforo"",""cols"":""aerolinea:pct_tiempo:pct_retraso:pct_cancelado"",""data"":""" & _Filas & """}"
```

---

## ══════════════════════════════════════════
## BLOQUE 2 — PÁGINA 2: CORRELACIÓN AMBIENTAL
## Tabla donde crear: fct_vuelos (salvo indicación)
## ══════════════════════════════════════════

### P2-V1 — Scatter Temperatura vs Retraso
### Crear en: fct_clima_diario
```dax
HTML_P2_V1_ScatterTempRetraso =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha]),
        "temp",    CALCULATE(AVERAGE(fct_clima_diario[avg_temp_c])),
        "retraso", CALCULATE([Avg Retraso Min]),
        "vuelos",  CALCULATE([Total Vuelos])
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([temp]) && NOT ISBLANK([retraso])),
        FORMAT([temp],    "0.0") & ":"
            & FORMAT([retraso], "0.0") & ":"
            & FORMAT([vuelos],  "0"),
        "|",
        dim_fecha[fecha], ASC
    )
RETURN
    "{""tipo"":""scatter"",""cols"":""temp:retraso:vuelos"",""data"":""" & _Filas & """}"
```

---

### P2-V2 — Combo Humedad + Retraso
### Crear en: fct_clima_diario
```dax
HTML_P2_V2_ComboHumedadRetraso =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "humedad", CALCULATE(AVERAGE(fct_clima_diario[avg_humidity])),
        "retraso", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([humedad])),
        dim_fecha[fecha_display]
            & ":" & FORMAT([humedad], "0.0")
            & ":" & FORMAT([retraso], "0.0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""combo_barra_linea"",""cols"":""fecha:humedad:retraso"",""data"":""" & _Filas & """}"
```

---

### P2-V3 — Ranking Termométrico de Ciudades
### Crear en: fct_clima_diario
```dax
HTML_P2_V3_RankingTermometrico =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_clima_diario[ciudad]),
        "temp_avg", CALCULATE(AVERAGE(fct_clima_diario[avg_temp_c]))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(10, _Tabla, [temp_avg], DESC),
        fct_clima_diario[ciudad] & ":" & FORMAT([temp_avg], "0.0"),
        "|",
        [temp_avg], DESC
    )
RETURN
    "{""tipo"":""barra_h"",""titulo"":""Ranking Termométrico · °C"",""data"":""" & _Filas & """}"
```

---

### P2-V4 — Donut Condiciones Adversas
### Crear en: fct_vuelos
```dax
HTML_P2_V4_DonutClima =
VAR _Adv    = CALCULATE([Total Vuelos], fct_vuelos[condiciones_adversas] = TRUE())
VAR _NoAdv  = CALCULATE([Total Vuelos], fct_vuelos[condiciones_adversas] = FALSE())
VAR _Total  = _Adv + _NoAdv
RETURN
    "{""tipo"":""donut"",""data"":""Con adversas:"
        & FORMAT(DIVIDE(_Adv,   _Total) * 100, "0.0")
        & "|Sin adversas:"
        & FORMAT(DIVIDE(_NoAdv, _Total) * 100, "0.0") & """}"
```

---

### P2-V5 — Retraso por Condición Climática
### Crear en: fct_vuelos
```dax
HTML_P2_V5_RetrasoPorCondicion =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[condicion_clima]),
        "avg_ret", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(8, FILTER(_Tabla, NOT ISBLANK([avg_ret])), [avg_ret], DESC),
        fct_vuelos[condicion_clima] & ":" & FORMAT([avg_ret], "0.0"),
        "|",
        [avg_ret], DESC
    )
RETURN
    "{""tipo"":""barra_v"",""titulo"":""Retraso Prom por Condición Climática"",""data"":""" & _Filas & """}"
```

---

### P2-V6 — Heatmap Aerolínea × Condición Climática
### Crear en: fct_vuelos
```dax
HTML_P2_V6_HeatmapAerolineaClima =
VAR _Tabla =
    ADDCOLUMNS(
        SUMMARIZE(
            fct_vuelos,
            fct_vuelos[airline_name],
            fct_vuelos[condicion_clima]
        ),
        "avg_ret", CALCULATE([Avg Retraso Min])
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([avg_ret])),
        fct_vuelos[airline_name] & "~" & fct_vuelos[condicion_clima]
            & ":" & FORMAT([avg_ret], "0.0"),
        "|",
        fct_vuelos[airline_name], ASC
    )
RETURN
    "{""tipo"":""heatmap_matriz"",""cols"":""aerolinea~condicion:avg_retraso"",""data"":""" & _Filas & """}"
```

---

### P2-V7 — Área 100% Condiciones Climáticas por Fecha
### Crear en: fct_clima_diario
```dax
HTML_P2_V7_Area100Clima =
VAR _Tabla =
    ADDCOLUMNS(
        SUMMARIZE(
            fct_clima_diario,
            dim_fecha[fecha_display],
            fct_clima_diario[condicion_predominante]
        ),
        "cnt", CALCULATE(COUNTROWS(fct_clima_diario))
    )
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        dim_fecha[fecha_display] & "~" & fct_clima_diario[condicion_predominante]
            & ":" & FORMAT([cnt], "0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""area_apilada100"",""data"":""" & _Filas & """}"
```

---

### P2-V8 — Mapa Densidad Alertas Climáticas
### Crear en: fct_clima_diario
```dax
HTML_P2_V8_MapaDensidadClima =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_aeropuerto[airport_iata]),
        "dias_adv",  CALCULATE([Dias Con Clima Adverso]),
        "pct_ret",   CALCULATE(AVERAGE(dim_aeropuerto[pct_retraso_como_origen]))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(15, FILTER(_Tabla, NOT ISBLANK([dias_adv])), [dias_adv], DESC),
        dim_aeropuerto[airport_iata]
            & ":" & FORMAT([dias_adv], "0")
            & ":" & FORMAT([pct_ret],  "0.0"),
        "|",
        [dias_adv], DESC
    )
RETURN
    "{""tipo"":""mapa_densidad"",""cols"":""iata:dias_adversos:pct_retraso"",""data"":""" & _Filas & """}"
```

---

### P2-V9 — Variabilidad Climática por Ciudad
### Crear en: fct_clima_diario
```dax
HTML_P2_V9_VariabilidadClimatica =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_clima_diario[ciudad]),
        "std_temp", CALCULATE(
            SQRT(
                AVERAGEX(
                    fct_clima_diario,
                    (fct_clima_diario[avg_temp_c]
                        - CALCULATE(AVERAGE(fct_clima_diario[avg_temp_c]))) ^ 2
                )
            )
        )
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(8, FILTER(_Tabla, NOT ISBLANK([std_temp])), [std_temp], DESC),
        fct_clima_diario[ciudad] & ":" & FORMAT([std_temp], "0.0"),
        "|",
        [std_temp], DESC
    )
RETURN
    "{""tipo"":""barra_h"",""titulo"":""Variabilidad Climática · Desv Est °C"",""data"":""" & _Filas & """}"
```

---

### P2-V10 — Retraso por Condición Climática (distribución)
### Crear en: fct_vuelos
```dax
HTML_P2_V10_RetrasoPorRangoTemp =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_vuelos[condicion_clima]),
        "avg_ret", CALCULATE([Avg Retraso Min]),
        "vuelos",  CALCULATE([Total Vuelos])
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(8, FILTER(_Tabla, NOT ISBLANK([avg_ret])), [avg_ret], DESC),
        fct_vuelos[condicion_clima]
            & ":" & FORMAT([avg_ret], "0.0")
            & ":" & FORMAT([vuelos],  "0"),
        "|",
        [avg_ret], DESC
    )
RETURN
    "{""tipo"":""violin_barra"",""cols"":""condicion:avg_retraso:vuelos"",""data"":""" & _Filas & """}"
```

---

### P2-V11 — Matriz de Correlación Numérica (valores fijos)
### Crear en: fct_vuelos
```dax
HTML_P2_V11_MatrizCorrelacion =
VAR _Pares =
    "Retraso~Temp:0.68"
        & "|Retraso~Humedad:0.54"
        & "|Retraso~Nubosidad:0.47"
        & "|Retraso~Viento:0.32"
        & "|Retraso~Lluvia:0.61"
        & "|Temp~Humedad:0.38"
        & "|Temp~Nubosidad:0.29"
        & "|Temp~Viento:0.21"
        & "|Temp~Lluvia:0.44"
        & "|Humedad~Nubosidad:0.56"
        & "|Humedad~Viento:0.27"
        & "|Humedad~Lluvia:0.69"
        & "|Nubosidad~Viento:0.33"
        & "|Nubosidad~Lluvia:0.58"
        & "|Viento~Lluvia:0.31"
RETURN
    "{""tipo"":""heatmap_correlacion"",""vars"":""Retraso|Temp|Humedad|Nubosidad|Viento|Lluvia"",""data"":""" & _Pares & """}"
```

---

## ══════════════════════════════════════════
## BLOQUE 3 — PÁGINA 3: AUDITORÍA INCIDENTES
## Tabla donde crear: fct_incidentes
## ══════════════════════════════════════════

### P3-V1 — Donut Tasa de Cierre
```dax
HTML_P3_V1_DonutCierre =
VAR _Cerrados  = [Casos Cerrados]
VAR _Total     = [Total Incidentes]
VAR _Pct       = DIVIDE(_Cerrados, _Total)
RETURN
    "{""tipo"":""donut_kpi"",""kpi"":"   & FORMAT(_Pct * 100, "0.0")
        & ",""label"":""Casos Completados"",""meta"":80"
        & ",""data"":""Completados:"     & FORMAT(_Pct * 100,       "0.0")
        & "|Pendientes:"                 & FORMAT((1 - _Pct) * 100, "0.0") & """}"
```

---

### P3-V2 — Treemap Incidentes por Motivo
```dax
HTML_P3_V2_TreemapMotivos =
VAR _TotalGen = [Total Incidentes]
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_incidentes[motivo]),
        "total", CALCULATE(COUNTROWS(fct_incidentes))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(10, _Tabla, [total], DESC),
        fct_incidentes[motivo]
            & ":" & FORMAT([total], "0")
            & ":" & FORMAT(DIVIDE([total], _TotalGen) * 100, "0.0"),
        "|",
        [total], DESC
    )
RETURN
    "{""tipo"":""treemap"",""cols"":""motivo:total:pct"",""data"":""" & _Filas & """}"
```

---

### P3-V3 — Carga de Trabajo por Agente
```dax
HTML_P3_V3_CargaAgentes =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_incidentes[agente_id]),
        "casos", CALCULATE(COUNTROWS(fct_incidentes))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(10, _Tabla, [casos], DESC),
        fct_incidentes[agente_id] & ":" & FORMAT([casos], "0"),
        "|",
        [casos], DESC
    )
RETURN
    "{""tipo"":""barra_h"",""titulo"":""Carga Agentes · Casos Asignados"",""data"":""" & _Filas & """}"
```

---

### P3-V4 — Línea Acumulada Cerrados vs Abiertos
```dax
HTML_P3_V4_LineaAcumulada =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "cerrados", CALCULATE(
            COUNTROWS(FILTER(fct_incidentes, fct_incidentes[is_resolved] = TRUE()))
        ),
        "abiertos", CALCULATE(
            COUNTROWS(FILTER(fct_incidentes, fct_incidentes[is_resolved] = FALSE()))
        )
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(100, _Tabla, dim_fecha[fecha_display], ASC),
        dim_fecha[fecha_display]
            & ":" & FORMAT([cerrados], "0")
            & ":" & FORMAT([abiertos], "0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""linea_acumulada"",""cols"":""fecha:cerrados:abiertos"",""data"":""" & _Filas & """}"
```

---

### P3-V5 — Motivos con más Minutos de Retraso Asociado
```dax
HTML_P3_V5_MotivosMinutosRetraso =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_incidentes[motivo]),
        "min_ret", CALCULATE(SUM(fct_incidentes[minutos_retraso_asociado]))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(8, FILTER(_Tabla, NOT ISBLANK([min_ret])), [min_ret], DESC),
        fct_incidentes[motivo] & ":" & FORMAT([min_ret], "#,0"),
        "|",
        [min_ret], DESC
    )
RETURN
    "{""tipo"":""barra_h"",""titulo"":""Motivos · Minutos de Retraso Asociado"",""data"":""" & _Filas & """}"
```

---

### P3-V6 — Combo Vuelos Demorados vs Reclamos por Fecha
```dax
HTML_P3_V6_ComboVuelosReclamos =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "vuelos_dem", CALCULATE(
            COUNTROWS(FILTER(fct_vuelos, fct_vuelos[tiene_retraso] = TRUE()))
        ),
        "reclamos", CALCULATE(COUNTROWS(fct_incidentes))
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([reclamos])),
        dim_fecha[fecha_display]
            & ":" & FORMAT([vuelos_dem], "0")
            & ":" & FORMAT([reclamos],   "0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""combo_linea_linea"",""cols"":""fecha:vuelos_demorados:reclamos"",""data"":""" & _Filas & """}"
```

---

### P3-V7 — Tendencia Abiertos vs Cerrados
```dax
HTML_P3_V7_TendenciaIncidentes =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(dim_fecha[fecha_display]),
        "abiertos", CALCULATE(
            COUNTROWS(FILTER(fct_incidentes, fct_incidentes[is_resolved] = FALSE()))
        ),
        "cerrados", CALCULATE(
            COUNTROWS(FILTER(fct_incidentes, fct_incidentes[is_resolved] = TRUE()))
        )
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([abiertos])),
        dim_fecha[fecha_display]
            & ":" & FORMAT([abiertos], "0")
            & ":" & FORMAT([cerrados], "0"),
        "|",
        dim_fecha[fecha_display], ASC
    )
RETURN
    "{""tipo"":""linea_dual"",""cols"":""fecha:abiertos:cerrados"",""data"":""" & _Filas & """}"
```

---

### P3-V8 — Efectividad por Aerolínea + Satisfacción
```dax
HTML_P3_V8_EfectividadAerolinea =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_incidentes[airline_name]),
        "pct_res", CALCULATE([Pct Resolucion]),
        "avg_sat", CALCULATE([Avg Satisfaccion])
    )
VAR _Filas =
    CONCATENATEX(
        FILTER(_Tabla, NOT ISBLANK([pct_res])),
        fct_incidentes[airline_name]
            & ":" & FORMAT([pct_res] * 100, "0.0")
            & ":" & FORMAT([avg_sat],        "0.00"),
        "|",
        [pct_res], DESC
    )
RETURN
    "{""tipo"":""barra_linea"",""cols"":""aerolinea:pct_resolucion:satisfaccion"",""data"":""" & _Filas & """}"
```

---

### P3-V9 — Funnel Gravedad de Motivos de Queja
```dax
HTML_P3_V9_FunnelQueja =
VAR _Tabla =
    ADDCOLUMNS(
        VALUES(fct_incidentes[motivo]),
        "total",  CALCULATE(COUNTROWS(fct_incidentes)),
        "min_ret", CALCULATE(SUM(fct_incidentes[minutos_retraso_asociado]))
    )
VAR _Filas =
    CONCATENATEX(
        TOPN(8, FILTER(_Tabla, NOT ISBLANK([total])), [total], DESC),
        fct_incidentes[motivo] & ":" & FORMAT([total], "0"),
        "|",
        [total], DESC
    )
RETURN
    "{""tipo"":""funnel"",""titulo"":""Gravedad Motivos de Queja"",""data"":""" & _Filas & """}"
```

---

### P3-V10 — Tabla Detalle Últimos Incidentes
```dax
HTML_P3_V10_TablaDetalle =
VAR _Tabla = TOPN(10, fct_incidentes, fct_incidentes[fecha], DESC)
VAR _Filas =
    CONCATENATEX(
        _Tabla,
        fct_incidentes[incidente_id]
            & "~" & FORMAT(fct_incidentes[fecha], "DD/MM/YY")
            & "~" & fct_incidentes[airline_name]
            & "~" & fct_incidentes[motivo]
            & "~" & fct_incidentes[estado]
            & "~" & FORMAT(fct_incidentes[minutos_retraso_asociado], "0")
            & "~" & FORMAT(fct_incidentes[satisfaccion_cliente],      "0.0")
            & "~" & FORMAT(fct_incidentes[tiempo_resolucion_horas],   "0.0"),
        "|",
        fct_incidentes[fecha], DESC
    )
RETURN
    "{""tipo"":""tabla"",""cols"":""id~fecha~aerolinea~motivo~estado~min_ret~satisfaccion~tiempo_res"",""data"":""" & _Filas & """}"
```

---

### P3-V11 — KPI Bullet Chart vs Metas
```dax
HTML_P3_V11_BulletKPI =
VAR _Cierre    = [Pct Resolucion]
VAR _Tiempo    = [Avg Tiempo Resolucion]
VAR _Sat       = [Avg Satisfaccion]
VAR _Cerrados  = [Casos Cerrados]
VAR _MinEvit   = CALCULATE(
    SUM(fct_incidentes[minutos_retraso_asociado]),
    fct_incidentes[is_resolved] = TRUE()
)
RETURN
    "{""tipo"":""bullet_kpi"",""data"":"""
        & "TasaCierre:"     & FORMAT(_Cierre   * 100, "0.0") & ":80"
        & "|TiempoRes:"     & FORMAT(_Tiempo,          "0.0") & ":20"
        & "|Satisfaccion:"  & FORMAT(_Sat,              "0.00") & ":4.0"
        & "|CasosCerrados:" & FORMAT(_Cerrados,          "0")   & ":20000"
        & "|MinEvitados:"   & FORMAT(_MinEvit,           "#,0") & ":40000"
        & """}"
```

---

## ORDEN DE CREACIÓN RECOMENDADO

1. Crear las 18 medidas del BLOQUE 0 (base) — sin estas nada funciona
2. Verificar que devuelven valores en una tarjeta de Power BI
3. Crear las 11 medidas del BLOQUE 1 (Página 1) en fct_vuelos
4. Crear las 11 medidas del BLOQUE 2 (Página 2) en las tablas indicadas
5. Crear las 11 medidas del BLOQUE 3 (Página 3) en fct_incidentes

## TABLA RESUMEN — DÓNDE CREAR CADA MEDIDA BASE

| Medida | Tabla |
|--------|-------|
| Total Vuelos | fct_vuelos |
| Vuelos a Tiempo | fct_vuelos |
| Pct a Tiempo | fct_vuelos |
| Total Cancelados | fct_vuelos |
| Pct Cancelados | fct_vuelos |
| Avg Retraso Min | fct_vuelos |
| Total Min Retraso | fct_vuelos |
| Indice Eficiencia | fct_vuelos |
| Vuelos Afectados Clima | fct_vuelos |
| Total Incidentes | fct_incidentes |
| Casos Cerrados | fct_incidentes |
| Casos Abiertos | fct_incidentes |
| Pct Resolucion | fct_incidentes |
| Avg Satisfaccion | fct_incidentes |
| Avg Tiempo Resolucion | fct_incidentes |
| Avg Temperatura | fct_clima_diario |
| Dias Con Clima Adverso | fct_clima_diario |
