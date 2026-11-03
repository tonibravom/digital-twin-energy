# Página de edificio

Especificación de la página de un edificio, acordada el 21/10/2026. Completa `docs/pantallas.md` y es el guion de las Fases 6 (dashboard) y 7 (3D).

## 1. Estructura

```
┌─────────────────────────────────────────────────────────────────────┐
│ Plataforma › Partner › Cliente › EDIFICIO CENTRAL                     │
│ ● Operativo  ▲ 2 alarmas  ◌ 1 sensor sin comunicación   PRO · 3D      │
│ Último dato: 12:15            Ámbito: [Edificio completo ▾]           │
├─────────────────────────────────────────────────────────────────────┤
│  HOY │ 3D │ Históricos │ Alarmas │ Ficha │ Análisis │ Configuración   │
├─────────────────────────────────────────────────────────────────────┤
│                      contenido de la pestaña                          │
└─────────────────────────────────────────────────────────────────────┘
```

**Cabecera:**
- ruta de navegación;
- estado del edificio (operativo, alarmas, sensores sin comunicación);
- modalidad y complemento 3D;
- hora del último dato recibido.

**Selector de ámbito:** "Edificio completo", una planta o un recinto. Se aplica a todas las pestañas y usa las magnitudes de ámbito PLANTA o RECINTO que haya configurado el Partner.

**Pestañas visibles según modalidad, complemento y permisos:**

| Pestaña | Quién la ve |
|---|---|
| HOY | Todos |
| 3D | Si el edificio tiene el complemento 3D |
| Históricos | Todos |
| Alarmas | Todos. Reconocer o cerrar según permisos |
| Ficha | Todos. Editar según permisos |
| Análisis energético | Modalidad PRO o PREMIUM |
| Configuración | Partner y administrador (permisos de configuración) |

Un usuario de cliente con un solo edificio entra directamente aquí (no ve la ruta superior).

## 2. HOY

**Con qué se compara:** con el **último día equivalente según el calendario del edificio**, siempre en el mismo tramo horario (desde las 00:00 hasta la hora actual):
- si hoy es laborable → el último día laborable;
- si hoy no es laborable → el último día no laborable.

Ejemplo: el lunes siguiente a un viernes festivo se compara con el jueves. Sin calendario cargado, se considera laborable de lunes a viernes.

**Disposición (D42, 02/11/2026).** La página se divide en tres zonas que ocupan la altura de la ventana:

```
┌───────────────┬──────────────────────────┬────────────┐
│ Pestañas      │ 3D (si está contratado)  │            │
│ (Hoy, Sumi-   │ o lista de sensores,     │  ALARMAS   │
│ nistros de    │ de la planta más baja    │  (fijo)    │
│ red, Produc-  │ a la más alta (fijo, 3/5)│            │
│ ción renova-  ├──────────────────────────┤            │
│ ble)          │ Gráfica (fija, 2/5)      │            │
│               │                          │            │
└───────────────┴──────────────────────────┴────────────┘
     ≈1/3                 ≈1/2               ≈1/8
```

- Solo cambia la zona izquierda al cambiar de pestaña.
- **Gráfica:** por defecto, la energía de hoy frente al día comparable con las horas fuera de horario sombreadas. Selector de magnitud del edificio, periodo (hoy, ayer, 7 días, 30 días, 12 meses) y agrupación (15 min, hora, día, semana, mes). Al pulsar un sensor de la lista (o del 3D) se muestra su gráfica. Sustituye a la pestaña Históricos.
- **Alarmas:** alarmas activas y sensores sin comunicación, por importancia. Sustituye a la pestaña Alarmas. El motor de alarmas (umbrales, fuera de horario…) es la siguiente fase.
- **Ficha** y **Configuración** son botones de la cabecera.
- En pantallas de menos de 1400 px: dos columnas y las alarmas debajo; en tablet y móvil, todo apilado.

**Pestaña Hoy** (D45): desplazamiento vertical con tres bloques del mismo alto. Las pestañas caben sin desplazamiento horizontal.

| Bloque | Contenido |
|---|---|
| 1 | **Energía total consumida**: total y % frente al día comparable; electricidad de la red, gas y renovables con su energía, su **aporte al total** y su % frente al día comparable; **emisiones** totales y separadas en electricidad de la red y gas (las renovables no emiten) |
| 2 | **Diagrama Sankey** (hoy, 7 o 30 días) |
| 3 | **Ambiente por recinto**: temperatura, humedad y CO₂ del último valor. Colores de temperatura con la **eficiencia** y el **confort** de la temporada, configurables por edificio (por defecto, invierno 19 / 25 °C y verano 27 / 25 °C). Humedad 30–70 % verde |
**Suministros de red:** potencia (con su % a la misma hora del día comparable) y factor de potencia; electricidad, gas y agua de hoy. El resto, por diseñar.
**Producción renovable:** generación de hoy, parte consumida, cobertura y %. El resto, por diseñar.

*Soporte:* `hoy_edificio` (023: consumos, curva, horario), `potencia_edificio` (033), `fuentes_hoy_edificio`, `ambiente_edificio` y `alarmas_edificio` (034), `sankey_energia` (024), `serie_magnitud` y `serie_sensor` (023, con semanas desde 034).

## 3. 3D

- Al entrar se carga el **modelo general del edificio**.
- Un desplegable **"Modelo"** lista los modelos de recinto disponibles, con su planta: "Planta 1 · Nave A". Al elegir uno se carga ese modelo; la opción "Edificio completo" vuelve al general.
- En el modelo no hay etiquetas de recinto; el recinto se elige siempre en la lista.
- **Etiquetas de sensores y dispositivos** en sus coordenadas X, Y, Z:
  - muestran nombre corto y **valor actual** con su unidad;
  - color: verde (normal), rojo (alarma activa), naranja (sin comunicación) y gris (sin datos);
  - se reposicionan al girar, desplazar o hacer zoom (maestro §12);
  - filtro por tipo: energía, potencia, temperatura, humedad, CO₂, estado…
- **Al pulsar una etiqueta**, panel lateral con:
  - valor y hora de la última lectura;
  - gráfica de las últimas 24 h;
  - estado de comunicación y alarmas activas;
  - botón "Ver en Históricos".
- **"Localizar en 3D":** desde cualquier sensor de otras pestañas se abre esta con el modelo adecuado y el sensor centrado y resaltado.
- **Solo Partner y administrador:** las coordenadas del punto bajo el cursor, como ayuda para anotarlas en la configuración.
- **Controles:** girar, desplazar, zoom, vista inicial y pantalla completa.

*Soporte (023):* `sensores_estado_edificio(edificio)` devuelve en una llamada todos los sensores, con su valor actual, estado, alarma y posiciones 3D. El archivo GLB se descarga del bucket privado.

## 4. Históricos

| Opción | Valores |
|---|---|
| Qué ver | Una o varias **magnitudes** del edificio (o del ámbito elegido) y/o **sensores** concretos |
| Periodo | Hoy, ayer, semana, mes, año, a medida |
| Agrupación | 15 min (hasta 2 meses), hora (hasta 13 meses), día, mes, año |
| Comparar con | Periodo anterior o mismo periodo del año pasado |
| Filtro de calendario | Todos, solo laborables, solo no laborables, dentro de horario, fuera de horario |
| Tipo de gráfica | Líneas, barras (apiladas por suministro) y **mapa de calor día × hora** |
| Exportar | Excel / CSV con los datos de la gráfica |

Reglas de cálculo:
- Energía, agua y emisiones se **suman** en cada intervalo; potencia, temperatura y similares se **promedian**, indicando mínimo y máximo.
- En los **contadores acumulativos**, la gráfica muestra el **consumo de cada intervalo** (diferencia del contador), no el valor del contador.

*Soporte (023):* `serie_magnitud(...)` y `serie_sensor(...)`, con agrupación, filtro de calendario y límites de periodo para no saturar el sistema.

### Balance energético (diagrama Sankey)

Vista dentro de Históricos, con su propio selector de periodo (por defecto, el año en curso). También aparece en *Análisis › Indicadores* de los niveles Cliente, Partner y Plataforma, sumando sus edificios.

```
Red eléctrica ─┐
Fotovoltaica ──┼─► Electricidad consumida ─┬─► HVAC ─┬─► Climatización
Eólica ────────┤                           │         └─► Renovación de aire
               └─► Exportada a la red      ├─► Iluminación
Gas ───────────────────────────────────────┼─► HVAC
Solar térmica ─┐                           │
Geotermia ─────┼─► Calor renovable ────────┼─► HVAC
Biomasa ───────┘                           └─► Otros usos
```

**Cómo se calcula:**
- Electricidad consumida = importada de la red + fotovoltaica y eólica autoconsumidas (generada − exportada).
- Las renovables térmicas (solar térmica, geotermia, biomasa) forman el **calor renovable**, que se reparte entre usos igual que la electricidad o el gas.
- La suma de todas las entradas menos lo exportado es la **energía consumida** del edificio, la misma cifra del KPI.
- Cada uso recibe lo que miden los **submedidores** asignados a él. El Partner indica el uso de cada submedidor en el paso "Qué representa" del asistente.
- Lo **no medido** (total − submedidores) se reparte con los porcentajes que configure el Partner por tipo de energía; por ejemplo, "gas no medido → 100 % climatización". Lo que no tenga reparto va a **Otros usos**.
- Los flujos estimados se dibujan con **trazo discontinuo**. Al pasar el ratón se ve "estimado" con su valor.
- Si los submedidores suman más que el total, se muestra un aviso para revisar la asignación de usos.
- Usos de partida: HVAC (climatización y renovación de aire), iluminación y otros usos. El catálogo `usos_energia` admite añadir más (ACS, ascensores, ofimática…) sin cambiar el código.

*Soporte (024):* `sankey_energia(nivel, id, desde, hasta)` devuelve nodos y enlaces listos para la librería de gráficos (por ejemplo, ECharts tiene Sankey integrado).

## 5. Alarmas

- **Activas:** nivel, regla, sensor o magnitud, recinto, desde cuándo, valor que la disparó. Botones **Reconocer** y **Cerrar** con comentario (`reconocer_alarma`, `cerrar_alarma`), según permisos.
- **Histórico** filtrable por fechas, nivel y estado.
- **Incidencias de comunicación**, separadas de las alarmas (maestro §5): sensor, inicio, fin y duración.
- **Reglas** del edificio (Partner): crear, editar y desactivar.

## 6. Ficha

- **Datos del edificio:** dirección, mapa, superficies, plantas, año, uso, zona horaria y estado.
- **Suministros:**
  - electricidad: CUPS, tarifa, potencias P1–P6 y energía verde con su %;
  - gas;
  - agua y agua contra incendios;
  - generación: tecnología, potencia y fecha de puesta en marcha.
- **Calendario:** el año por meses, distinguiendo días laborables y no laborables y el horario de cada día (maestro §11). Lo editan el Partner y el **cliente avanzado** (este, de hoy en adelante). Incluye el horario tipo, los festivos aplicados y la generación anual automática. Detalle en `configuracion-edificio.md`, apartado 6.
- **Modalidad y complementos:** lectura para el cliente; cambio para quien tenga permiso.

## 7. Análisis energético (PRO y PREMIUM)

- **PRO:**
  - línea base de consumo y ahorro conseguido;
  - benchmarking avanzado frente a edificios del mismo uso;
  - propuestas de mejora (por ejemplo, reducir el consumo fuera de horario).
- **PREMIUM:** además, previsión del consumo del día y del mes, y detección automática de anomalías.

Su contenido exacto se definirá con el motor (Fase 5 y posteriores).

## 8. Configuración (Partner y administrador)

Especificación completa en `docs/configuracion-edificio.md`.

Acceso a todo lo que define el edificio:
- plantas y recintos;
- conexiones, dispositivos y sensores (asistente de `docs/configuracion-partner.md`);
- magnitudes, **uso final de cada submedidor** y **reparto de la energía no medida** (para el Sankey);
- reglas de alarma;
- modelos 3D y coordenadas;
- calendario y modalidad.

Incluye la **lista de comprobación** y el botón **"Cerrar parametrización"**.

## 9. Pendiente

| Tema | Fase |
|---|---|
| Cálculo de `valores_magnitud` y `resumenes_diarios` (motor) | Hecho (032) |
| Contenido de Análisis energético y predicción | Posterior |
| Mapa de calor de recintos en el 3D (colorear un recinto por su consumo o temperatura) | Posterior; requiere identificar cada recinto dentro del GLB |
