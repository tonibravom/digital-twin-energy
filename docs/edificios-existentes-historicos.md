# Edificios con equipos existentes y carga de históricos

La plataforma sirve tanto para edificios en los que se instalan sensores nuevos como para edificios que **ya tienen** contadores, sensores o un sistema de gestión, y cuyos **datos pasados** se quieren aprovechar. Acordado el 21/10/2026.

## 1. Conectar equipos existentes

No hace falta instalar nada nuevo: se configura una conexión hacia lo que ya existe (`docs/conectores.md`).

| Lo que tiene el edificio | Tipo de conexión |
|---|---|
| Sistema de gestión del edificio o SCADA con OPC UA | **OPC UA** (por pasarela en el edificio) |
| BMS con BACnet, o contadores Modbus | BACnet / Modbus TCP (por pasarela) |
| Plataforma del fabricante con API | API REST |
| Sensores que publican en un broker | MQTT |
| Gateway de terceros que envía datos | Envío HTTP estándar |
| Exportaciones de datos (Excel, CSV) | Tipo **OTRA** + importación |

Cada punto existente se da de alta como un sensor, con su dirección en el sistema de origen. Las **plantillas** de dispositivo agilizan los equipos repetidos.

## 2. Cargar datos históricos

### Dos caminos según la antigüedad

```
Antigüedad del dato                      Cómo se carga                       Dónde queda
─────────────────────────────────────    ─────────────────────────────────   ──────────────────────────
Desde el 1 de enero del año actual − 4   Lecturas por sensor (cada 15 min,   lecturas (como las
(en 2026: desde 01/01/2022)              horarias…)                          de tiempo real)
Anterior a ese límite                    Resúmenes por edificio: diarios     resumenes_diarios
                                         o mensuales (p. ej. de facturas)    (se conservan siempre)
```

### Tres vías de entrada (solo Partner)

Importar históricos requiere el permiso **`IMPORTAR_HISTORICOS`**, que tienen el administrador, el administrador del Partner y el técnico del Partner. El cliente, incluido el avanzado, **no importa**.

| Vía | Para quién | Cómo |
|---|---|---|
| **Archivo** (Excel o CSV) | Partner, desde Configuración → Conexiones → "Importar histórico" | Asistente de 5 pasos (abajo) |
| **Recuperación automática** | Conexiones cuyo origen guarda su propio histórico: **Sentilo, API REST y OPC UA** | Al crear la conexión, o después: "Recuperar histórico desde…" (`solicitar_recuperacion`). La API pide el pasado por tramos, lo carga por lotes y avanza el cursor (`avanzar_recuperacion`) |
| **API con token** | Empresas IoT que ya tienen los datos | Con el token de envío de la conexión: `crear_importacion_token` y luego `procesar_lote_token` lote a lote. Mismas reglas que un archivo |

En la recuperación automática, si la fecha pedida es anterior al límite de retención, se **ajusta al límite** y se avisa de que ese periodo debe cargarse como resúmenes. No puede haber dos recuperaciones a la vez en la misma conexión.

### Asistente de importación de archivos

1. **Subir el archivo** y elegir un **perfil** guardado, o crear uno nuevo.
2. **Formato:** se admiten los dos habituales.

   **Ancho**: una columna por sensor (típico de exportaciones de BMS y SCADA):

   | Fecha | CONT-01/energia | TEMP-02 | … |
   |---|---|---|---|
   | 01/03/2024 00:00 | 1520,4 | 21,3 | … |

   **Largo**: una fila por lectura (típico de bases de datos y plataformas IoT):

   | Fecha | Sensor | Valor | Calidad (opcional) |
   |---|---|---|---|
   | 2024-03-01T00:00:00+01:00 | CONT-01/energia | 1520.4 | VALIDA |

3. **Emparejar** columnas (ancho) o identificadores (largo) con los sensores del edificio, e indicar formato de fecha, zona horaria, separador decimal y qué hacer con los vacíos. Todo eso se guarda en el **perfil** (`perfiles_importacion`) para repetir la importación con el siguiente archivo del mismo sistema.
4. **Simulación** (vista previa, no guarda nada, `simular_lecturas`): cuántas lecturas se guardarían, cuántas son duplicadas, cuántas se rechazarían y por qué, y por sensor el **mínimo, máximo y media**, para detectar escalas o unidades equivocadas antes de cargar.
5. **Confirmar**: la API convierte el archivo al formato estándar y lo envía por lotes (ver abajo). El avance se ve en la lista de importaciones.

Se ofrecen plantillas descargables de ambos formatos y de resúmenes.

En la API (repositorio `digital-twin-energy-api`), cada paso es una ruta: `vista-previa`, `simular`, confirmar (`POST /v1/edificios/{id}/importaciones`), `reanudar` y estado. Los resúmenes usan `POST /v1/edificios/{id}/resumenes`. El formato de los perfiles está en el README de la API.

### Importación de lecturas (dentro del periodo de retención)

1. El Partner crea una **importación** indicando edificio, conexión, archivo y nº de lotes (`crear_importacion`).
2. La API divide el archivo en **lotes**, por ejemplo de 10.000 filas, y los envía uno a uno (`procesar_lote_lecturas`).
3. Cada lote:
   - entra por el **mismo canal** que las lecturas en tiempo real (`procesar_lecturas`): identificación del punto, fecha con o sin zona, escala y unidades, rango válido, valores vacíos y duplicados;
   - en **modo histórico**: no cambia el "último dato" del sensor, no abre ni cierra incidencias de comunicación y no da el sensor por probado;
   - admite marcar la **calidad** de cada lectura: válida, estimada o corregida;
   - deja un **recálculo pendiente** del periodo para el motor (`recalculos_pendientes`).
4. Si la carga se interrumpe, **se reanuda**: un lote ya procesado no se repite, y una lectura repetida nunca se duplica.
5. La importación guarda sus totales (recibidas, guardadas, duplicadas, rechazadas), el periodo cubierto y el detalle de errores por lote.

Esto cubre lo que pide el maestro (§15): importación idempotente, errores por lote y reanudación. También evita el error de CPU del Excel de 58.843 filas, porque se procesa por partes.

### Importación de resúmenes (anterior al límite, o datos que solo existen agregados)

Función `importar_resumenes(edificio, filas)` con filas como:

```json
[
  { "indicador": "CONSUMO_ELECTRICIDAD", "mes": "2019-03", "valor": 31000 },
  { "indicador": "CONSUMO_GAS", "fecha": "2019-03-14", "valor": 120 }
]
```

- Indicadores: electricidad importada, gas, agua, electricidad exportada y cada tecnología renovable.
- Un valor **mensual** se reparte por igual entre los días del mes y se marca como **no completo**: sirve para comparar meses y años, no para el detalle diario.
- No sobrescribe lo calculado por el motor, salvo que se pida expresamente.
- Admite **simulación** (`p_simular`): devuelve los días que se guardarían sin escribir nada.
- Con estos resúmenes, los KPIs y la comparación interanual funcionan también para años antiguos.

### Calendario de años pasados

Para analizar históricos (laborables, festivos, consumo fuera de horario), el Partner puede generar el calendario de años anteriores (`generar_calendario` con la opción de incluir el pasado). El cliente no puede modificar días pasados.

### Recálculo

Tras cada carga, el motor (migración 032) recalcula automáticamente el periodo cargado —las lecturas nuevas lo anotan en su cola— y rehace `valores_magnitud`, `resumenes_diarios` y los resúmenes por uso de ese periodo. Es un **requisito del motor**: debe poder recalcular cualquier rango de fechas, no solo los datos nuevos.

## 3. Qué no se hace (por ahora)

| Tema | Situación |
|---|---|
| Conector **Datadis** (consumos eléctricos por CUPS de las distribuidoras) | Previsto para PRO/PREMIUM, junto con la **validación de facturas**. No se desarrolla ahora |
| Lecturas por sensor anteriores al límite de retención | No se guardan: se importan como resúmenes |
