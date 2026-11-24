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
- **Gráfica (D47):** por defecto, la energía total de hoy frente al día comparable con las horas fuera de horario sombreadas. El desplegable, con buscador, ofrece todas las series de energía (KPI, usos y cuadros del Sankey), las demás magnitudes y todos los sensores. Pulsar un dato del panel (KPI, valores de ambiente, usos finales del Sankey ampliado, sensores, alarmas, pestañas) lo muestra en la gráfica y lo resalta. Energía en líneas (15 min, horas) o barras (días, semanas, meses). Selector de magnitud del edificio, periodo (hoy, ayer, 7 días, 30 días, 12 meses) y agrupación (15 min, hora, día, semana, mes). Al pulsar un sensor de la lista (o del 3D) se muestra su gráfica. Sustituye a la pestaña Históricos.
- **Alarmas:** alarmas abiertas y sensores sin comunicación, por estado e importancia, con Reconocer, Silenciar y Cerrar, y la configuración de las reglas (§5, D59).
- **Ficha** y **Configuración** son botones de la cabecera.
- En pantallas de menos de 1400 px: dos columnas y las alarmas debajo; en tablet y móvil, todo apilado.

**Pestaña Hoy** (D50): KPI de energía y, debajo, el Sankey ocupando el resto del alto. El **ambiente por recinto** pasa a la mitad inferior de la columna de alarmas (las dos mitades con desplazamiento vertical). Las pestañas caben sin desplazamiento horizontal.

| Bloque | Contenido |
|---|---|
| 1 | **Energía total consumida**: total y % frente al día comparable; electricidad de la red, gas y renovables con su energía, su **aporte al total** y su % frente al día comparable; **emisiones** totales y separadas en electricidad de la red y gas (las renovables no emiten) |
| 2 | **Diagrama Sankey** (hoy, 7 o 30 días), compacto; al pulsarlo se amplía con el detalle por uso y cuadro |
| 3 | **Ambiente por recinto**: temperatura, humedad y CO₂ del último valor. Colores de temperatura con la **eficiencia** y el **confort** de la temporada, configurables por edificio (por defecto, invierno 19 / 25 °C y verano 27 / 25 °C). Humedad 30–70 % verde |
**Suministros** (D57): una ficha desplegable por suministro (electricidad, gas, agua), una debajo de otra; la primera, abierta:
- **medidor general**: sus parámetros en vivo (consumo de hoy, potencia, cos φ y los opcionales que mida: exportada, reactiva, aparente, tensiones, intensidades, frecuencia; presión del gas; caudal, presión y temperatura del agua). Cada uno abre su gráfica. Si falta el medidor o un parámetro obligatorio, aviso en rojo;
- **consumo mensual**: barras de este año frente al anterior (electricidad y gas en kWh; agua en m³);
- **contrato**: comercializadora, distribuidora, CUPS, nº de contrato o póliza, alta, tarifa, potencias contratadas P1–P6, contador de la compañía, energía verde y medidor general.
La generación renovable va en Producción.
**Producción** (D58): una ficha desplegable por instalación (fotovoltaica y solar térmica; las demás tecnologías, más adelante), como en Suministros:
- **KPIs de hoy.** Fotovoltaica: producción y variación frente al día comparable, potencia y % de la potencia pico, autoconsumo y excedente exportado (del medidor general de la red), cobertura del consumo eléctrico, producción específica (kWh/kWp), rendimiento (PR, con irradiancia) y emisiones evitadas. Solar térmica: producción y variación, potencia térmica, **aporte solar** (parte de la energía de los usos a los que da servicio que viene de las placas), producción específica (kWh/m²) y salto térmico impulsión − retorno;
- **medidor** (inversor o contador de energía) en vivo, con cada parámetro pulsable;
- **producción mensual** de este año frente al anterior (kWh);
- **datos de la instalación**: potencia pico y módulos, inversor, modalidad de autoconsumo y CAU (FV); captadores, acumulador, usos servidos y caldera de apoyo (ST); superficie, orientación, inclinación, placas en el 3D, puesta en marcha, instalador y mantenedor.
- **Sankey:** el calor de la solar térmica llega al uso al que da servicio (el reparto del calor renovable) junto al gas o la electricidad; al pasar el ratón por el uso se ve qué parte viene de cada energía.

*Soporte:* `suministros_edificio` y `consumo_mensual_suministro` (048), `produccion_edificio` (052), `hoy_edificio` (023: consumos, curva, horario), `potencia_edificio` (033), `fuentes_hoy_edificio`, `ambiente_edificio` y `alarmas_edificio` (034), `sankey_energia` (024), `serie_magnitud` y `serie_sensor` (023, con semanas desde 034).

## 3. 3D

**Implementado (D51 y D52, 11/11/2026):** con modelo 3D, el visor ocupa todo el panel salvo la columna de pestañas (Hoy · Suministros · Ambiente · Producción · Alarmas):
- selector **Planta**: «Todo el edificio» (solo el sensor seleccionado y los que tienen alarma) o una planta (oculta las superiores, acerca la vista y muestra las etiquetas de sus sensores);
- **etiquetas**: un punto en la posición X, Y, Z exacta (verde comunicando, gris sin comunicación o sin datos, rojo alarma) y el valor con su unidad pegado a él; el nombre y el recinto, al pasar el ratón. No se apilan: si un valor tapa a otro de más prioridad, solo se ve su punto;
- pulsar una etiqueta abre la **gráfica flotante** (semitransparente, sobre la parte baja del 3D, con Ampliar y Cerrar); también se abre desde los KPI, el Sankey ampliado, el ambiente y las alarmas, que además llevan el 3D a la planta del recinto o del sensor;
- pulsar el modelo identifica el elemento (categoría, tipo, planta, id del modelo) y, a Partner y administrador, el punto X / Y / Z con botón para copiarlo;
- **Encuadrar** vuelve a la vista inicial; el zoom no puede alejarse más que el encuadre y la cámara no baja de 35° (D53). Pendiente: modelos de recinto, filtro por tipo y pantalla completa.
- **Etiquetas por dispositivo** (D53): una fila por sensor; pulsar una fila abre su gráfica.
- **Pestaña Hoy** (D56): con «Todo el edificio», edificio al 40 % y solo las etiquetas de suministro (Electricidad de la red, Gas, Renovables, Agua) con el color del KPI, el consumo de hoy y la variación frente al día comparable; con una planta, esa planta opaca, las de debajo como referencia y todo lo de encima de su techo recortado, con todas sus etiquetas. El gas muestra m³ y kWh. Los contadores muestran el consumo de hoy, no la lectura acumulada.
- **Sin modelo 3D** (D56): corte esquemático del edificio (franjas por planta, recintos como cajas, etiquetas por dispositivo) con la gráfica fija debajo.
- **3D | Esquema** (D56): en los edificios con modelo, el mismo corte esquemático como vista alternativa, con la gráfica flotante.
- **Pestaña Producción** (D58): todo el edificio al 40 %, sin selector de planta; las placas iluminadas según lo que producen y una etiqueta por instalación sobre ellas (compacta: producción de hoy, potencia y % del pico; desplegada: todo el medidor). En el esquema, una caja «Placas» en la planta donde están, con la misma etiqueta.
- **Pestaña Suministros** (D57): todo el edificio al 40 %, sin selector de planta, con una etiqueta por suministro en su medidor general: compacta (obligatorios) y, al pulsar la cabecera o abrir su ficha, desplegada con todos sus parámetros. En el **esquema** (3D | Esquema y edificios sin 3D), igual: solo la etiqueta de cada suministro en el recinto de su medidor, compacta o desplegada. En las demás pestañas, las etiquetas del medidor no llevan los parámetros opcionales.
- **Pestaña Ambiente** (D55): edificio semitransparente, volúmenes de los recintos con el color del tramo de temperatura y leyenda de la temporada; en las etiquetas solo los sensores ambientales (temperatura, humedad y CO₂); bajo la leyenda, el clima exterior en grande (icono, temperatura, estado del cielo, humedad, viento, UV y lluvia, con la previsión al pulsar); fila «Exterior» en la tabla.
- **Clima exterior** (D54): recuadro en la barra del visor (en la de sensores si no hay 3D) con el tiempo; al pulsarlo, próximas horas y días.

Sin modelo 3D: corte esquemático del edificio y gráfica fija en el centro (D56).

Especificación original:

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
- Cada uso recibe lo que miden los **submedidores** asignados a él. El Partner indica, en el paso "Magnitud que representa" del asistente, si un medidor es el contador general, el total de un cuadro o un submedidor, su uso y su cuadro (D46).
- **Otros usos de cada cuadro** = total del cuadro − sus submedidores − los cuadros que cuelgan de él (lo calcula el motor, 037).
- Lo **no medido** (total − cuadros − medidores independientes) se reparte con los porcentajes que configure el Partner por tipo de energía; por ejemplo, "gas no medido → 100 % climatización". Lo que no tenga reparto va a **Otros usos · no medido**.
- Los flujos estimados se dibujan con **trazo discontinuo**. Al pasar el ratón se ve "estimado" con su valor.
- Si los submedidores suman más que el total, se muestra un aviso para revisar la asignación de usos.
- Usos principales (D48): **HVAC** (climatización, refrigeración, calefacción, ACS, calefacción y ACS, renovación de aire), **Alumbrado**, **Informática**, **Servicios comunes** y **Otros usos**, que es solo lo que no tiene uso determinado (diferencias de los cuadros y lo no medido). El catálogo `usos_energia` admite añadir más sin cambiar el código.
- **Columnas (D46):** fuentes → electricidad o gas → HVAC, Alumbrado y Otros usos → **detalle**: en HVAC, el uso final; en Alumbrado y Otros usos, el uso y el cuadro ("Alumbrado · Planta 1", "Otros usos · Local comercial", "Informática · Cubierta"), ordenados por planta. En la pestaña Hoy se ve compacto (sin el detalle); **al pulsarlo** se abre a pantalla completa con el detalle (D48). En Cliente, Partner y Plataforma el detalle es solo por uso, sin cuadros.

*Soporte (024):* `sankey_energia(nivel, id, desde, hasta)` devuelve nodos y enlaces listos para la librería de gráficos (por ejemplo, ECharts tiene Sankey integrado).

## 5. Alarmas

Implementado (D59, migración 053). Pestaña **Alarmas** del panel, ordenada por estado e importancia:
- cada alarma: nivel (**Muy crítica**, **Crítica**, **Aviso**), regla, detalle, sensor y recinto, desde cuándo, estado y quién la ha reconocido, silencio y comentario. Pulsarla lleva el 3D al sensor y abre su gráfica;
- **estados**: *Activa* (causa presente, sin atender) → *Reconocida* (alguien se ocupa) → *Resuelta* (la causa ha desaparecido) → *Cerrada*. **Cerrar solo es posible en Resuelta**: mientras la causa siga, se reconoce o se **silencia** hasta una fecha (máximo 30 días) con un motivo. Con rearme automático la alarma se cierra sola. Si la causa vuelve antes de una hora, se reabre la misma;
- botones según permisos (`reconocer_alarma`, `silenciar_alarma`, `cerrar_alarma`): administrador, Partner y cliente avanzado; los demás, solo ver;
- sensores sin comunicación como **aviso** (si el edificio tiene la regla «Equipo sin comunicar», sale una sola vez);
- **Configurar alarmas** (administrador y Partner): catálogo de reglas de la plataforma aplicables al edificio, con lo que falta para activarlas, nivel, rearme, umbrales, destinatarios del email y escalado (`reglas_alarma_edificio`, `activar_regla_alarma`, `desactivar_regla_alarma`, `usuarios_alarmas_edificio`);
- el enlace de los emails (`/edificio/<id>?pestana=alarmas&alarma=<id>`) abre esta pestaña con la alarma resaltada; la campana lleva también aquí;
- en el 3D, el punto del sensor queda en rojo mientras la alarma no esté cerrada (también resuelta);
- **pulsar una alarma** (o su línea 📍 sensor · recinto · planta) lleva el 3D a la planta del recinto, resalta la etiqueta del sensor con el nombre de la alarma y el punto latiendo, y abre su gráfica. Arriba del 3D, un cartel indica la alarma y dónde está (o que no tiene etiqueta en el 3D). Lo mismo al llegar desde el enlace del email (054);
- en edificios `DEMO-*`, **Configurar alarmas → Probar en el edificio de demostración** simula una avería durante 30 min a 2 h para ver todo el tratamiento.
- **Histórico** (055): selector **Abiertas | Histórico** arriba de la pestaña. De la más reciente a la más antigua, con filtros de periodo, nivel y estado y buscador; cada alarma con su duración, tiempo hasta reconocerla, quién la cerró y con qué comentario. Al pulsarla se despliega su **cronología** (cada paso con hora y persona). 📍 lleva el 3D a su planta y abre la gráfica del sensor de esos días con la franja de la alarma en rojo. **Descargar a Excel** baja la lista filtrada;
- el 3D de la pestaña Alarmas es el mismo que el de Hoy: edificio completo con los suministros, y por plantas y recintos todas sus etiquetas.

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


## Informes (D61, migración 056)
Botón **Informes** en la cabecera del edificio:
- lista de informes semanales (cada lunes, semana anterior) y mensuales (cada día 1, mes anterior), del más reciente al más antiguo; cada uno se abre en su página (`/edificio/<id>/informe/<id>`), sin menús, con **Descargar PDF** (A4);
- **Partner**: «Generar el de la semana pasada / del mes pasado» (o volver a generarlo), «Enviar por email» y **quién los recibe** (semanal y mensual por persona);
- **administrador de la plataforma o del Partner**: el **logo del Partner**, que sale en los informes y sus emails junto al nombre de la plataforma (`NOMBRE_PLATAFORMA`).
Contenido: resumen (energía, emisiones, renovable, agua y fuera de horario, con el periodo anterior y, en el mensual, el mismo mes del año pasado), consumo por día y por suministro, producción renovable, ambiente por recinto en horario de uso (mensual), alarmas y avisos (por nivel y regla, tiempos medios hasta reconocer y resolver, muy críticas, sin cerrar, avisos) y calidad de los datos.
