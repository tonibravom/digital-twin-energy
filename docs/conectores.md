# Integración de sensores y dispositivos

Cómo conectar **cualquier** sensor, contador o dispositivo a la plataforma **sin programar nada específico** para cada edificio o fabricante.

## 1. La idea en una línea

```
ORIGEN ──► CONEXIÓN ──► PUNTOS (sensores) ──► CANAL ÚNICO ──► lecturas
(equipo,    (cómo se      (dónde está cada      (valida, convierte,
 gateway,    llega:        medida y cómo         descarta duplicados
 nube)       protocolo)    se transforma)        y guarda)
```

Todos los protocolos acaban entregando las lecturas en un **formato estándar** a un único punto de entrada: la función `procesar_lecturas`. Por eso añadir un protocolo nuevo no obliga a tocar la base de datos, los cálculos ni los dashboards.

## 2. Los cuatro modos de conexión

| Modo | Quién inicia | Protocolos incluidos | Ejemplo |
|---|---|---|---|
| **CONSULTA** | La plataforma pide los datos cada X minutos | Sentilo, API REST | Plataformas municipales, nubes de fabricantes |
| **SUSCRIPCIÓN** | La plataforma escucha un broker | MQTT | Sensores IoT que publican en un broker |
| **ENVÍO** | El origen manda los datos a la plataforma | Envío HTTP (formato estándar), **LoRaWAN** (webhook del servidor de red) | Gateways, sensores inalámbricos LoRaWAN, plataformas IoT de terceros |
| **PASARELA** | Un equipo instalado en el edificio lee y reenvía | Modbus TCP, BACnet | Contadores y autómatas en la red local del edificio |

**Importante sobre Modbus y BACnet.** Son protocolos de red local: la plataforma, que está en la nube, no puede llegar a un contador conectado a la red interna de un edificio. Hace falta un pequeño equipo en el edificio (un gateway comercial o un mini-PC con un agente) que lea los equipos y reenvíe las lecturas por **ENVÍO**. La plataforma guarda igualmente la configuración Modbus/BACnet de cada punto, para que esa pasarela sepa qué leer.

## 3. Pasos para dar de alta un dispositivo

1. **Crear la conexión** del edificio y elegir el tipo de conexión. El formulario pide solo los parámetros de ese protocolo (definidos en `tipos_conexion.esquema_configuracion`).
2. **Crear el dispositivo y sus sensores**, de una de estas dos formas:
   - **Con plantilla** (recomendado): se elige el modelo de equipo y se crean el dispositivo y todos sus puntos de golpe (`crear_dispositivo_desde_plantilla`).
   - **A mano**: sensor a sensor.
3. Para cada sensor, indicar:
   - su **dirección**: dónde está la medida en el origen (`sensores.direccion`, según `tipos_conexion.esquema_punto`);
   - su **transformación**: escala, unidades, rango válido y qué hacer con los vacíos.
4. En modo ENVÍO, **generar el token** de la conexión y entregárselo al origen. Se muestra una sola vez.

La base de datos impide:
- dejar parámetros obligatorios sin rellenar;
- guardar contraseñas en la configuración;
- que dos sensores lean el mismo punto de la misma conexión.

## 4. Formato estándar de envío (modo ENVÍO)

La API expondrá un único endpoint (Fase 4 del plan):

```
POST https://<api>/api/v1/ingesta
Authorization: Bearer <token de la conexión>
Content-Type: application/json
```

```json
{
  "lecturas": [
    { "clave": "CONT-01/energia_importada", "fecha_hora": "2026-10-21T10:15:00Z",      "valor": 1534200 },
    { "clave": "CONT-01/potencia_activa",   "fecha_hora": "2026-10-21 12:15",          "valor": "2500,5" },
    { "clave": "TEMP-SALA-2",               "fecha_hora": "1792577700",                "valor": 21.4 },
    { "id_sensor": "3f0c…-uuid",            "fecha_hora": "2026-10-21T10:15:00+02:00", "valor": null }
  ]
}
```

| Campo | Reglas |
|---|---|
| `clave` o `id_sensor` | Identifica el punto. `clave` es la que figura en `direccion.clave` del sensor |
| `fecha_hora` | ISO 8601 con zona (`Z`, `+02:00`), sin zona (se interpreta en la zona horaria de la conexión) o epoch en segundos/milisegundos. No se admiten fechas más de 1 día en el futuro ni anteriores al periodo de retención |
| `valor` | Número, texto numérico (admite coma decimal), booleano (1/0) o vacío (`null` o `""`) |
| Tamaño | Máximo 50.000 lecturas por envío |
| Repeticiones | Reenviar lo mismo es seguro: las lecturas duplicadas (mismo sensor e instante) se ignoran |

Respuesta:

```json
{
  "recibidas": 4, "guardadas": 3, "duplicadas": 0, "rechazadas": 1,
  "detalle_rechazos": [ { "posicion": 4, "motivo": "valor vacío (descartado)" } ]
}
```

Motivos posibles:
- punto desconocido en esta conexión;
- fecha no válida;
- fecha fuera del periodo admitido;
- valor vacío (descartado);
- valor no numérico;
- valor fuera del rango válido;
- valor vacío sin lectura anterior.

## 5. Transformación de cada punto

```
valor guardado = valor recibido × escala + desplazamiento
```

| Parámetro del sensor | Para qué | Ejemplo |
|---|---|---|
| `unidad_origen` → `unidad` | Unidad en que llega y unidad normalizada de la plataforma | Wh → kWh |
| `escala` | Conversión de unidades o factor del fabricante | 0,001 (Wh→kWh); 0,1 (registro en décimas) |
| `desplazamiento` | Corrección fija | −273,15 (K → °C) |
| `valor_minimo` / `valor_maximo` | Lecturas fuera de rango se rechazan (sobre el valor ya convertido) | Temperatura interior entre −20 y 60 °C |
| `politica_vacios` | Qué hacer si llega sin valor | `DESCARTAR`, `CERO`, `MANTENER_ULTIMO` |

La **naturaleza** del sensor (instantánea, acumulativa, estado, contaje) y su **tratamiento** (delta, promedio, máximo…) indican al motor cómo convertir las lecturas en consumos y magnitudes. Por ejemplo, un contador acumulativo de energía con tratamiento DELTA genera el consumo de cada intervalo.

## 6. Plantillas de dispositivo

Una plantilla describe un **modelo de equipo** una sola vez: sus puntos de medida, direcciones, unidades, escalas y semántica. Después se reutiliza en cualquier edificio.

- **Globales:** las mantiene el administrador de la plataforma y las ven todos los Partners.
- **Privadas de un Partner:** por ejemplo, una empresa IoT con sus propios sensores. Solo las ve y edita ese Partner (permiso `GESTIONAR_PLANTILLAS`).

Al crear un dispositivo desde una plantilla:
- los sensores se llaman `<código dispositivo>.<código punto>`;
- en modo ENVÍO, cada clave se prefija con el código del dispositivo (`CONT-01/energia_importada`). Así el mismo modelo se repite en un edificio sin conflictos;
- se puede añadir una **dirección base** común; por ejemplo, `{"id_unidad": 3}` para un equipo Modbus en el esclavo 3.

La plataforma incluye una plantilla de ejemplo (`EJEMPLO_ENVIO_CONTADOR`). Las plantillas Modbus reales deben crearse a partir del manual de cada fabricante: el mapa de registros cambia entre modelos.

## 7. Parámetros por protocolo

| Protocolo | Configuración de la conexión | Dirección de cada punto |
|---|---|---|
| **Sentilo** | `url_base`, `proveedor`. El token se guarda en Vault (`PUT /v1/conexiones/{id}/secreto`) | `sensor` |
| **API REST** | `url`, `metodo`, `autenticacion` (NINGUNA/BEARER/API_KEY/BASIC), `cabecera_clave`, `ruta_lista`, `campo_fecha`, `formato_fecha`, `parametro_desde`/`parametro_hasta`, `formato_parametros`, `ventana_horas`. La credencial, en Vault | `ruta_valor`, `filtro` |
| **MQTT** | `host`, `puerto`, `tls`, `usuario`, `id_secreto` | `topic`, `ruta_valor`, `ruta_fecha` |
| **Modbus TCP** | `host`, `puerto`, `id_unidad`, `orden_palabras` | `registro`, `tipo_registro` (HOLDING/INPUT/COIL/DISCRETO), `tipo_dato` (INT16…FLOAT64), `id_unidad` |
| **OPC UA** | `endpoint`, `politica_seguridad`, `modo_seguridad`, `usuario`, `id_secreto` | `node_id`, `muestreo_ms` |
| **BACnet** | `ip`, `puerto`, `instancia_dispositivo` | `tipo_objeto`, `instancia`, `propiedad` |
| **Envío HTTP** | (nada; se genera un token) | `clave` |
| **LoRaWAN** | `servidor_red` (THE_THINGS_STACK, CHIRPSTACK u OTRO); se genera un token | `dev_eui`, `campo` (la clave `DEVEUI/campo` se calcula sola) |

Todas las conexiones tienen además:
- `intervalo_segundos`: frecuencia de consulta, 900 por defecto (15 minutos);
- `zona_horaria_origen`;
- campos de diagnóstico: `ultima_ejecucion`, `ultimo_ok` y `ultimo_error`.

## 8. Estado de comunicación

Cada lectura válida actualiza el estado de su sensor a COMUNICANDO. Cada 15 minutos, `revisar_comunicacion()` marca SIN_COMUNICACION los sensores que superan su umbral sin datos y abre una incidencia. El umbral es de 30 minutos por defecto (`parametros_saas`) y puede ir de 15 a 120 por sensor. Cuando vuelven a llegar lecturas, la incidencia se cierra con su duración. La API avisa al Partner de las incidencias nuevas.

## 9. Contraseñas y claves

Nunca se guardan en la configuración: la base de datos lo impide. Se guardan en **Supabase Vault** (cifrado), y la conexión solo guarda su identificador (`id_secreto`). Los tokens de envío se guardan como huella SHA-256: si alguien leyera la base de datos, no podría usarlos.

## 10. API REST genérica (consulta)

Sirve para **cualquier API que entregue medidas en JSON**: plataformas IoT, nubes de fabricantes, Sentilo, sistemas de gestión con API… sin programar nada por cada origen (migración 029).

Ejemplo. La API responde a `GET https://api.ejemplo.com/medidas?desde=…&hasta=…` con:

```json
{"datos": [{"punto": "CONT-GENERAL", "fecha": "2026-10-26T13:45:00Z", "valor": 1520.4}]}
```

| Parámetro | Valor en el ejemplo |
|---|---|
| `url` | `https://api.ejemplo.com/medidas` |
| `autenticacion` / `cabecera_clave` | `API_KEY` / `X-API-Key` (la clave, en Vault) |
| `ruta_lista` | `$.datos` (o `$` si la respuesta es directamente la lista) |
| `campo_fecha` / `formato_fecha` | `fecha` / `ISO8601` (también `EPOCH_S`, `EPOCH_MS`) |
| `parametro_desde` / `parametro_hasta` | `desde` / `hasta` (si la API los admite; sin ellos no se pueden recuperar históricos) |
| `ventana_horas` | 24: horas que se piden en cada petición |
| Sensor: `ruta_valor` / `filtro` | `valor` / `{"punto": "CONT-GENERAL"}` |

Las rutas admiten campos anidados con punto (`data.value`, `meter.id`). Cada 15 minutos se pide lo nuevo desde la última lectura de los sensores, o el último día si aún no tienen. La recuperación de históricos avanza hasta 60 peticiones por ciclo.

## 11. Sentilo (consulta)

- Cada 15 minutos, la tarea de la API (`POST /v1/tareas/ciclo`, ver apartado 13) pide a Sentilo lo nuevo de cada sensor desde su última lectura: `GET {url_base}/data/{proveedor}/{sensor}?from&to&limit`, con la cabecera `IDENTITY_KEY`. Si el sensor no tiene lecturas, se pide el último día.
- Las fechas de Sentilo están en UTC (`dd/MM/yyyyTHH:mm:ss`). Se piden en tramos de 7 días.
- **Recuperación de históricos** (`solicitar_recuperacion`): en cada ciclo avanza hasta 8 semanas por conexión y lo carga como importación. Si Sentilo falla, la recuperación queda en ERROR con el motivo.
- Los errores (token incorrecto, sensor inexistente…) quedan en `conexiones.ultimo_error` para el Partner.

## 12. LoRaWAN (envío por webhook)

Los sensores inalámbricos LoRaWAN hablan con uno o varios **gateways** del edificio. Los gateways entregan los mensajes a un **servidor de red** (The Things Stack, ChirpStack o el que lleva integrado el propio gateway, como Milesight o Kerlink), que los descifra, los **decodifica** con el decodificador del fabricante y los reenvía a la plataforma.

Configuración en el servidor de red:
1. Integración **Webhook / HTTP** hacia `https://<api>/v1/lorawan/uplink`.
2. Cabecera `Authorization: Bearer <token de la conexión>`.
3. Decodificador de carga útil activado para cada tipo de dispositivo.

Formatos admitidos (se detectan solos): The Things Stack v3 (`decoded_payload`) y ChirpStack v4 (`object`, evento `up`; el resto de eventos se ignora).

En la plataforma, cada **campo** decodificado de un dispositivo es un sensor: dirección = `dev_eui` + `campo` (p. ej. `24E124710B000001` + `co2`). Los campos que llegan sin sensor configurado no dan error: se guardan en `conexiones.puntos_detectados` para que el asistente los ofrezca al Partner al configurar.

## 13. Tarea periódica

Supabase llama a la API cada 15 minutos (pg_cron + pg_net, migración 028), así funciona aunque la API se duerma en un plan gratuito. Configuración, una vez por instalación:
1. *Database > Extensions*: active **pg_cron** y **pg_net**.
2. En el SQL Editor, guarde en Vault la dirección de la API y un secreto largo y aleatorio:
   ```sql
   select vault.create_secret('https://<su-api>.onrender.com', 'api_url');
   select vault.create_secret('<secreto>', 'api_tareas_secreto');
   ```
3. Ponga ese mismo secreto en la variable `TAREAS_SECRETO` de la API.
4. Si activó las extensiones después de aplicar la 028, vuelva a ejecutar el bloque `do $$ … $$` del final de esa migración.

## 14. Simuladores (desarrollo y demos)

Con `SIMULADOR_ACTIVO=true`, la API incluye:
- **API REST simulada** en `https://<api>/simulador/api/medidas?desde=…&hasta=…` (cabecera `X-API-Key` = `SIMULADOR_API_KEY`). Puntos: `CONT-GENERAL` (kWh acumulados), `POT-GENERAL` (kW), `FV-PROD` (kWh FV acumulados), `TEMP-EXT` (°C) y `GAS-CONT` (m³ acumulados). Datos realistas de un edificio de oficinas, también del pasado (sirve para probar la recuperación de históricos).
- **Sentilo simulado** en `https://<api>/simulador/sentilo` con los mismos puntos (token = `SIMULADOR_SENTILO_TOKEN`), para probar ese tipo de conexión.
- El script `docs/demo_simuladores.sql` crea un edificio de demostración conectado a la API REST y al LoRaWAN simulados.
- **Servidor LoRaWAN simulado:** en cada ciclo envía, con formato The Things Stack, un mensaje de cada dispositivo a la conexión cuyo token esté en `SIMULADOR_LORAWAN_TOKEN`:

| DevEUI | Dispositivo | Campos |
|---|---|---|
| `24E124710B000001` | Sensor de ambiente (tipo AM307) | `temperature`, `humidity`, `co2`, `battery` |
| `24E124136B000002` | Contador de agua por pulsos (tipo EM300-DI) | `water` (litros acumulados), `battery` |
| `24E124746B000003` | Medidor de energía de climatización | `active_energy` (kWh acumulados), `power` (W) |

En producción, `SIMULADOR_ACTIVO=false`.

## 15. Qué falta por construir (en la API)

| Pieza | Fase del plan |
|---|---|
| Paginación en el conector API REST (APIs que devuelven las medidas en varias páginas) | Cuando haga falta |
| Suscriptor MQTT | Fase 4 o posterior |
| Agente de pasarela Modbus/BACnet para el edificio | Posterior (ver decisión pendiente) |
| Formularios generados a partir de los esquemas | Fase 3 |

**Decisión pendiente:** para Modbus y BACnet, ¿se desarrolla un agente de pasarela propio, o se apoya en gateways comerciales que ya envían por HTTP o MQTT? Lo segundo es más rápido; lo primero da un producto más completo.
