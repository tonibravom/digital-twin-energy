# Asistente de configuración del Partner

Recorrido que sigue un Partner para dar de alta los dispositivos y sensores de un edificio, desde la conexión hasta su posición en el gemelo 3D. Es la especificación de las pantallas de la Fase 3. Cada paso indica qué parte de la base de datos lo soporta.

## Visión general

```
1 Ubicación ─► 2 Conexión ─► 3 Dispositivo ─► 4 Puntos ─► 5 PRUEBA ─► 6 Magnitud ─► 7 Coordenadas 3D
                                                              │
                                     (se repite por dispositivo)
                                                              ▼
                                   8 Cierre de la parametrización del edificio
```

El asistente funciona **por dispositivo**. Un dispositivo agrupa varios sensores, por ejemplo un analizador de red con energía, potencia, tensión e intensidad. Un sensor suelto, conectado directamente a una conexión, sigue el mismo recorrido con un único punto.

## Pasos

### 1. Ubicación física
Edificio → planta → **recinto** donde está instalado físicamente el equipo.
*Soporte:* `dispositivos.id_recinto`. El histórico de ubicaciones se guarda solo (017).

### 2. Tipo de conexión y parámetros
- El Partner elige el **tipo de conexión**: Sentilo, API REST, MQTT, Modbus TCP, BACnet, Envío HTTP u Otra.
- Puede reutilizar una conexión ya existente del edificio (una conexión sirve a muchos dispositivos) o crear una nueva.
- El formulario se **genera solo** a partir de `tipos_conexion.esquema_configuracion`: muestra exactamente los campos de ese protocolo, con sus valores por defecto y listas de opciones.
- Contraseñas y claves: campo especial que la API guarda en **Supabase Vault**. La base de datos rechaza cualquier secreto en la configuración.
- En el modo Envío HTTP, el asistente genera el **token** y lo muestra una sola vez para copiarlo en el equipo o gateway (`generar_token_conexion`).

*Soporte:* `conexiones`, validación automática de parámetros obligatorios y de zona horaria (021).

### 3. Dispositivo
- **Con plantilla:** se elige el modelo de equipo y se crean el dispositivo y todos sus puntos (`crear_dispositivo_desde_plantilla`). Solo aparecen las plantillas compatibles con el tipo de conexión elegido.
- **Sin plantilla:** se introducen los datos del dispositivo (nombre, código, fabricante, modelo, número de serie) y en el paso 4 se añaden los puntos uno a uno.
- Opción "**Guardar como plantilla**" para reutilizar la configuración en otros edificios (`plantillas_dispositivo`, permiso `GESTIONAR_PLANTILLAS`).

### 4. Puntos de medida (sensores)
Para cada punto:

| Campo | Qué pregunta el asistente |
|---|---|
| Nombre y código | "Energía activa importada", `CONT-01.energia_importada` |
| **Qué mide** | Familia (energía, potencia, temperatura…), naturaleza (instantánea, acumulativa, estado, contaje), tratamiento (delta, promedio…), tipo de energía y flujo (consumo, generación…) |
| **Dónde está en el origen** | Formulario generado desde `tipos_conexion.esquema_punto`: registro Modbus, topic MQTT, id de Sentilo, clave de envío… |
| **Cómo se convierte** | Unidad de origen → unidad, escala, desplazamiento, rango válido, qué hacer con valores vacíos |

La vista previa `transformar_valor(sensor, valor)` muestra al momento cómo quedaría un valor de ejemplo, por ejemplo "2305 Wh → 2,305 kWh ✓ dentro de rango".

### 5. Prueba de lectura
Botón **"Probar lectura"** en cada punto, o "Probar todos" en el dispositivo:

| Modo de la conexión | Qué hace la prueba |
|---|---|
| Consulta (Sentilo, API REST) | La API lee el valor actual en el origen |
| Suscripción (MQTT) | La API escucha el topic durante unos segundos y muestra el primer mensaje |
| Envío HTTP / Pasarela | Muestra "esperando datos…" y la última lectura recibida. Se confirma sola cuando llega la primera |

El resultado se muestra al Partner:
- valor en origen;
- valor convertido con su unidad;
- fecha de la lectura;
- si está dentro del rango válido;
- en caso de fallo, el motivo.

Para que el Partner pueda corregirlo, el motivo debe ser comprensible. Por ejemplo: "No responde 192.168.1.50:502", "El registro 3000 no existe" o "Valor 999 °C fuera de rango".

*Soporte:* la API llama a `registrar_prueba_lectura`, que guarda el historial en `pruebas_lectura` y cambia el estado del sensor:
- **PENDIENTE:** nuevo, o modificado desde la última prueba;
- **PROBADO:** la prueba fue correcta o ya llegó una lectura real;
- **ERROR:** la última prueba falló.

Si después se cambia la dirección, la escala, el rango o la conexión, el sensor vuelve a PENDIENTE automáticamente.

### 6. Magnitud que representa
El Partner indica a qué **magnitud** del motor alimenta cada sensor, y en qué ámbito. Por ejemplo, "Energía consumida — Edificio" o "Energía generada — Cubierta FV". No escribe fórmulas: solo conecta sensores reales a las entradas estándar que define la plataforma (maestro §8).

Si el sensor es un **submedidor** de un uso concreto, el Partner indica también su **uso final**: climatización, renovación de aire, iluminación u otros (`sensores.id_uso_energia`, 024). Con eso se construye el diagrama Sankey.

*Soporte:* `magnitudes_edificio` y `magnitudes_fuentes` (005). La base de datos impide fuentes de otro edificio y ciclos entre magnitudes.

### 7. Posición en el gemelo 3D
Solo si el edificio tiene activo el complemento 3D.

**Cómo se trabaja.** El Partner prepara el GLB a partir de Revit, Blender u otra herramienta. Sobre ese GLB final anota las **coordenadas exactas** de cada sensor o dispositivo.

En el asistente:
1. Elige el modelo: el del **recinto** o el general del **edificio**.
2. Introduce **X, Y, Z** a mano.
3. Opcional, para comprobar: el visor muestra una marca en esas coordenadas. Si no cae donde debe, corrige los números.

- Se puede posicionar el dispositivo entero o cada sensor por separado, y tener posiciones distintas en el modelo general y en el del recinto.
- Si se sustituye un GLB por una versión nueva, hay que revisar las coordenadas respecto al modelo nuevo (maestro §12). Las del modelo anterior se conservan con él.

**Regla para las coordenadas:** se toman **siempre de un visor de GLB, sobre el mismo archivo que se sube a la plataforma**. Nunca de Revit, Blender u otro programa de origen: al exportar a GLB cambian los ejes, las unidades y a veces el origen, y los números dejarían de corresponder.

Si se vuelve a exportar el GLB, aunque sea con cambios pequeños, hay que volver a tomar las coordenadas sobre el archivo nuevo.

*Soporte:* `ubicaciones_3d` (007), con X, Y, Z numéricos respecto al GLB. La base de datos comprueba que el elemento está realmente en ese recinto o edificio.

### 8. Cierre de la parametrización del edificio
El edificio nace en estado **PENDIENTE_PARAMETRIZACION**. Una pantalla de resumen muestra la lista de comprobación (`estado_parametrizacion_edificio`):

| Comprobación | ¿Bloquea el cierre? |
|---|---|
| Plantas, recintos, conexiones y sensores dados de alta | Sí |
| Todos los sensores con dirección están **PROBADOS** | Sí |
| Modalidad asignada (BASIC / PRO / PREMIUM) | Sí |
| Al menos una magnitud con sensores asignados | Sí |
| Modelo 3D general cargado (si tiene complemento 3D) | Sí |
| Sensores sin dirección en el origen | Aviso |
| Calendario del año configurado | Aviso |
| Sensores sin posición en el 3D | Aviso |

Con todo lo bloqueante en verde, el botón **"Cerrar parametrización"** (`cerrar_parametrizacion`) pasa el edificio a **OPERATIVO**. Si falta algo, la base de datos lo impide y dice exactamente qué falta.

## Qué falta construir

| Pieza | Dónde | Fase |
|---|---|---|
| Pantallas del asistente con formularios generados desde los esquemas | Web | 3 |
| Lectura de prueba por protocolo (Sentilo y REST primero) | API | 3–4 |
| Visor 3D que muestra la marca en las coordenadas introducidas, para comprobarlas | Web | 7 |
| Lectura de coordenadas bajo el cursor en el visor de la plataforma, como ayuda para anotarlas (la introducción sigue siendo manual) | Web | 7 |
