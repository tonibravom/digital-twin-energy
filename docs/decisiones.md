# Registro de decisiones y cambios respecto al documento maestro v2.0

Este archivo complementa el *Documento maestro v2.0 (15/10/2026)*. Cuando ambos difieren, **prevalece este registro**. Al regenerar el maestro hay que incorporar estos puntos.

## Decisiones del 20/10/2026

| # | Decisión | Afecta a |
|---|---|---|
| D1 | **Modelo de negocio:** venta única de la plataforma con cesión total del código. El comprador contrata y opera su propia infraestructura (Supabase, API, frontend). Cada comprador es una instalación independiente. | §2, §14 |
| D2 | **Supabase es requisito obligatorio** (en la nube o autoalojado). | §14 |
| D3 | **Frecuencia de referencia:** una lectura cada 15 minutos por sensor. | §8, dimensionamiento |
| D4 | **Modelos 3D de EDIFICIO o de RECINTO**, no de planta. Sirve tanto para edificios altos (muchas plantas, pocos recintos por planta) como para edificios extensos (pocas plantas, muchos recintos). Una planta con un único recinto usa el tipo de recinto `PLANTA_COMPLETA`. Como máximo, un modelo activo por edificio y otro por recinto. | §12 (sustituye "edificio o planta") |
| D5 | Dentro de cada instalación se mantiene la jerarquía Administrador → Partner → Cliente → Edificio. El rol `ADMIN_SAAS` corresponde al administrador del comprador. | §6 |

## Decisiones del 21/10/2026

| # | Decisión | Afecta a |
|---|---|---|
| D6 | **Pantallas:** una única plantilla de "ámbito" con tres niveles (Plataforma → Partner → Cliente) y después la página de edificio. Ver `docs/pantallas.md` | §4 |
| D7 | **KPIs:** energía = electricidad + gas (kWh) *(sustituido por D15)*; emisiones = electricidad × **0,183** + gas × **0,182** kgCO₂e/kWh (sustituye el factor común 0,20); agua en m³ aparte; generación renovable = fotovoltaica + solar térmica + geotermia (+ eólica, biomasa) | §9 |
| D8 | Comparación con el **mismo periodo del año anterior**, solo con edificios que tienen datos en ambos periodos | §4 |
| D9 | Los usuarios de cliente con **un solo edificio** entran directamente a la página del edificio (confirmado) | §4 |
| D11 | **HOY** se compara con el **último día equivalente** según el calendario (último laborable si hoy es laborable; último no laborable si no lo es), en el mismo tramo horario | §4, §11 |
| D12 | En el **3D**, el modelo de recinto se elige **en una lista**; no hay etiquetas de recinto en el modelo | §12 |
| D13 | **Ficha** y **Configuración** son pestañas dentro de la página del edificio. Ver `docs/pagina-edificio.md` | §4 |
| D14 | **Diagrama Sankey**: fuentes (red eléctrica, gas, fotovoltaica) → usos (HVAC: climatización y renovación de aire; iluminación; otros). Lo no medido se reparte según configuración o va a "Otros", marcado como estimado | §9 |
| D15 | **Energía consumida** = electricidad importada + gas + renovable consumida (fotovoltaica y eólica autoconsumidas + solar térmica, geotermia y biomasa). Se usa en KPIs, HOY y Sankey. Las emisiones solo cuentan la electricidad importada y el gas. Se añade el % de cobertura renovable | §9 |
| D16 | **Configuración** del edificio en una única pestaña: modo guiado para el alta y navegación libre para editar. Ver `docs/configuracion-edificio.md` | §4 |
| D17 | **Importación desde Excel** de estructura, sensores, coordenadas 3D y calendario, con validación previa | §4 |
| D18 | Al sustituir un GLB, las coordenadas se **copian marcadas "por revisar"** | §12 |
| D19 | **Calendario** en la pestaña Ficha, editable por el Partner y el **cliente avanzado** (este, solo de hoy en adelante). Horario tipo semanal, festivos por país, provincia o municipio, y generación automática del año siguiente desde el 1 de diciembre | §11 |
| D20 | La plataforma admite **edificios con equipos existentes** y **carga de históricos**. Lo anterior al límite de retención se guarda **como resúmenes** diarios o mensuales | §8, §15 |
| D21 | **Alcance actual: solo modalidad BASIC.** PRO y PREMIUM (análisis energético, predicción, **conector Datadis** y **validación de facturas**) quedan para fases posteriores | §3 |
| D22 | **OPC UA** se añade al catálogo de conexiones | §7 |
| D23 | Importación de lecturas en **dos formatos de archivo**: **ancho** (una columna por sensor) y **largo** (fecha, sensor, valor). El formato y el emparejamiento de columnas se guardan como **perfil** reutilizable por edificio | §15 |
| D24 | Al crear una conexión cuyo origen guarda histórico (Sentilo, API REST, OPC UA), el Partner puede pedir la **recuperación automática** del pasado desde una fecha | §7, §15 |
| D25 | **Solo el Partner** (y el administrador) importa históricos: permiso `IMPORTAR_HISTORICOS`. El cliente, ni siquiera el avanzado, no importa | §5 |
| D26 | Toda importación pasa antes por una **simulación** que muestra qué se guardaría, qué se rechazaría y mínimos, máximos y medias por sensor | §15 |
| D27 | **Altas de usuarios sin invitación:** el administrador de la plataforma y el Partner (administrador **y técnico**) crean usuarios con email y **contraseña inicial**. El técnico no puede crear administradores del Partner | §5 |
| D28 | La contraseña inicial se **cambia obligatoriamente** en la primera entrada (mínimo 10 caracteres, letras y números) | §5 |
| D29 | **Doble factor por email:** código de 6 cifras, válido 10 minutos, 5 intentos y máximo 5 códigos cada 15 minutos. Se pide en cada sesión nueva | §5 |
| D30 | Doble factor **obligatorio** para el administrador de la plataforma y los administradores de Partner (`roles.requiere_doble_factor`, configurable) y **voluntario** para el resto | §5 |
| D31 | Conector **Sentilo** (consulta cada 15 min y recuperación de históricos) y **LoRaWAN** por webhook del servidor de red (The Things Stack y ChirpStack), con la carga decodificada en origen | §7 |
| D32 | Los conectores se desarrollan y prueban con **simuladores** integrados en la API (solo desarrollo y demos), sin usar datos de edificios reales hasta tener un edificio propio | §7 |
| D33 | La **tarea periódica** la dispara Supabase (pg_cron + pg_net) llamando a la API cada 15 minutos | §7 |
| D34 | **Conector API REST genérico** configurable (JSON por GET o POST, autenticación, rutas, filtros y periodo). El simulador de demostración es una API REST neutra | §7 |
| D10 | Las **coordenadas 3D** se introducen a mano (X, Y, Z), tomadas de un visor de GLB sobre el archivo final. El visor de la plataforma podrá mostrar las coordenadas bajo el cursor como ayuda | §12 |

## Cambios técnicos aplicados en las migraciones (20/10/2026)

**Seguridad**
- RLS activado en todas las tablas (67 tras la migración 026) desde la migración que las crea. Las particiones también tienen RLS y están en un esquema no expuesto.
- Las tablas de usuarios, roles y asignaciones tienen políticas de lectura por alcance y **no** admiten escritura directa. Las altas se hacen desde el backend con `service_role`.
- El rol anónimo no tiene acceso a ninguna tabla.
- Alta de edificio por Partner mediante `crear_edificio_partner()`.
- Protección de columnas sensibles:
  - cambiar el cliente de un edificio queda reservado al administrador;
  - dar de baja exige `DAR_BAJA_*`.
- Alarmas: no se editan directamente; se reconocen o cierran con `reconocer_alarma()` y `cerrar_alarma()`.
- Auditoría **automática por triggers** en las tablas de configuración (37 tras la 021). Ya no se puede escribir a mano. En las modificaciones solo guarda los campos cambiados.
- Las filas de auditoría sin edificio asociado solo las ve el administrador de plataforma.
- Storage 3D: un archivo solo se puede subir o leer si existe su registro en `modelos_3d` y el usuario tiene permiso sobre ese edificio.

**Integridad**
- Validación de "mismo edificio":
  - reglas de alarma ↔ sensor/magnitud, recintos y usuarios destinatarios;
  - eventos ↔ regla;
  - suministro ↔ dispositivo;
  - Partner ↔ cliente del edificio.
- Detección de ciclos entre magnitudes (A→B→A).
- Histórico de ubicaciones físicas automático. Al mover un dispositivo se mueven sus sensores.
- Como máximo un evento abierto por regla y recinto. Una alarma RECONOCIDA exige fecha.
- Plantas con nivel negativo (sótanos).

**Datos y escalabilidad**
- `lecturas` particionada por mes: 117 bytes por lectura frente a 354 del diseño anterior. El tipo de lectura lo define el sensor, no cada fila.
- `valores_magnitud` particionada por año.
- Retención corregida a **año actual − 4** (antes −5), eliminando particiones completas.
- Tarea diaria `mantenimiento_datos()` con pg_cron.
- Políticas de las tablas grandes evaluadas una vez por consulta.

**Alineación con el maestro**
- Catálogos:
  - conexiones: + BACnet, Modbus TCP;
  - dispositivos: + presencia/ocupación;
  - familias: INTENSIDAD (no CORRIENTE);
  - naturalezas: instantánea, acumulativa, estado, contaje;
  - tratamientos: directo, delta, promedio, máximo, mínimo, suma, estado, contaje.
- Partner y Cliente con estado OPERATIVO / SUSPENDIDO / BAJA.
- Roles:
  - `TECNICO_PARTNER` gestiona usuarios;
  - `USUARIO_CLIENTE` ya no reconoce alarmas (reservado al avanzado).
- Campos añadidos:
  - suministros: % de energía verde (electricidad) y fecha de puesta en marcha (generación);
  - eventos: fecha de fin y comentario;
  - notificaciones: destinatario, reintentos e incidencia de comunicación.
- El factor de CO₂ (`parametros_saas`) es legible por todos los usuarios para mostrarlo junto al KPI.
- La antigua 019 (pruebas) pasa a `supabase/tests/database/`. La nueva 019 contiene la instalación del primer administrador y la verificación de RLS.

## Migración 021 · Parametrización genérica de conectores (21/10/2026)

- Cuatro modos de conexión:
  - CONSULTA (Sentilo, API REST);
  - SUSCRIPCIÓN (MQTT);
  - ENVÍO (HTTP estándar);
  - PASARELA (Modbus TCP y BACnet mediante un equipo en el edificio).
- Cada tipo de conexión define con JSON Schema sus parámetros y cómo se direcciona cada punto. No hay tablas por protocolo (coherente con el maestro).
- Sensores con dirección en el origen, escala, desplazamiento, unidad de origen, rango válido y política de vacíos (DESCARTAR, CERO, MANTENER_ULTIMO). La política se define por sensor, como pide el maestro §8.
- Plantillas de dispositivo, globales o privadas de un Partner, que crean el dispositivo y todos sus sensores.
- Canal único de entrada `procesar_lecturas()`:
  - identifica el punto;
  - interpreta fechas con o sin zona y en epoch;
  - aplica la transformación y el rango;
  - descarta duplicados;
  - actualiza el estado de comunicación;
  - devuelve un resumen con los motivos de cada rechazo.
- Tokens de envío por conexión, guardados como huella SHA-256. Los secretos van en Supabase Vault.
- Nuevo tipo de conexión `ENVIO_HTTP` y nuevo permiso `GESTIONAR_PLANTILLAS`.
- Coherencia con la 002 y la 009:
  - el tipo `IOT` queda desactivado (lo sustituye `ENVIO_HTTP`);
  - `OTRA` se reserva para importaciones de archivos;
  - `sensores.magnitud_origen` pasa a ser solo descriptivo;
  - el umbral de comunicación se toma de `parametros_saas`;
  - la nueva función `revisar_comunicacion()` (pg_cron, cada 15 min) abre las incidencias, y al volver a llegar lecturas se cierran solas.
- Asistente del Partner:
  - estado de configuración por sensor (PENDIENTE/PROBADO/ERROR) e historial `pruebas_lectura`;
  - vista previa `transformar_valor`;
  - lista de comprobación `estado_parametrizacion_edificio` y `cerrar_parametrizacion`, que pasa el edificio a OPERATIVO solo si no falta nada bloqueante (maestro §4).
- Guías: `docs/conectores.md` y `docs/configuracion-partner.md`.

## Migración 022 · KPIs y resúmenes (21/10/2026)

- Factores de CO₂: 0,183 (electricidad) y 0,182 (gas), con fecha de vigencia. La función `factor_co2(codigo, fecha)` devuelve el aplicable a cada día.
- Tecnologías de generación: se añaden SOLAR_TERMICA, GEOTERMIA y BIOMASA. La columna calculada `renovable` excluye la cogeneración.
- Magnitudes por suministro: CONSUMO_ELECTRICIDAD, CONSUMO_GAS, CONSUMO_AGUA, GENERACION_FOTOVOLTAICA, GENERACION_SOLAR_TERMICA, GENERACION_GEOTERMIA y GENERACION_OTRAS_RENOVABLES.
- `resumenes_diarios`: totales por edificio, día e indicador. Los rellena el motor (Fase 5) y alimentan todos los dashboards sin recorrer lecturas.
- `kpis_ambito(nivel, id, fecha)` y `kpis_lista(nivel, id, fecha)` calculan los KPIs y la variación respetando los permisos de cada usuario.

## Migración 023 · Página de edificio (21/10/2026)

- `dia_calendario` y `dia_comparable`: carácter del día según el calendario. Sin calendario: lunes a viernes laborable.
- `hoy_edificio`: la pestaña HOY en una llamada. Incluye energía, emisiones, agua, renovables y autoconsumo; día comparable y variación; potencia actual; consumo fuera de horario; y curva de 15 min de hoy y del día comparable.
- `serie_magnitud` y `serie_sensor`: históricos agrupados (15 min a año) con filtro de calendario. Los contadores acumulativos devuelven el consumo por intervalo.
- `sensores_estado_edificio`: sensores con valor actual, estado, alarma y posiciones 3D (etiquetas y paneles).
- `estado_comunicacion.ultimo_valor` (añadido en la 021): valor de la última lectura de cada sensor.

## Migración 024 · Usos finales y Sankey (21/10/2026)

- Catálogo jerárquico `usos_energia`: HVAC → climatización y renovación de aire; iluminación; otros usos. Ampliable.
- `sensores.id_uso_energia`: uso final que mide cada submedidor. Solo usos finales, no grupos.
- `repartos_uso_edificio`: % de la energía no medida por tipo (electricidad, gas) y uso, con un máximo de 100 %.
- `resumenes_diarios_usos` (lo rellena el motor) y nuevo indicador `ELECTRICIDAD_EXPORTADA`.
- **Aclaración:** `CONSUMO_ELECTRICIDAD` es la electricidad **importada de la red**. La energía consumida por el edificio se calcula según D15.
- Renovables separadas en eléctricas (fotovoltaica, eólica: pueden exportarse) y térmicas (solar térmica, geotermia, biomasa: "calor renovable" en el Sankey).
- `sankey_energia(nivel, id, desde, hasta)`: nodos y enlaces con la parte estimada separada y avisos de incoherencia.

## Migración 025 · Configuración y edición de edificios (21/10/2026)

- No se desactivan plantas o recintos con elementos activos.
- `sustituir_sensor` y `sustituir_dispositivo`: el elemento nuevo mantiene el código y hereda magnitud, uso, posición 3D, reglas, ámbitos y suministros. El antiguo queda inactivo con su histórico (maestro §5).
- `sustituir_modelo_3d`: nueva versión del GLB con coordenadas copiadas "por revisar" (`ubicaciones_3d.por_revisar`, añadida en la 021). Se revisan con `confirmar_coordenadas`, o se confirman solas al corregirlas.
- Calendario:
  - `horarios_tipo_edificio` y `festivos`;
  - `es_festivo` y `generar_calendario`;
  - generación anual dentro de `mantenimiento_datos`;
  - permiso MODIFICAR_CALENDARIO para el cliente avanzado, con bloqueo de días pasados para los usuarios de cliente.

## Migración 026 · Históricos y edificios existentes (21/10/2026)

- `procesar_lecturas(..., p_historico)`: modo histórico, que no altera el estado de comunicación, las incidencias ni el estado de prueba. Admite calidad por lectura. Los rechazos por antigüedad indican importar como resumen. (Cambio aplicado en la 021.)
- `importaciones`, `importaciones_lotes`, `crear_importacion` y `procesar_lote_lecturas`: cargas por lotes, idempotentes y reanudables.
- `recalculos_pendientes`: periodos que el motor debe rehacer.
- `importar_resumenes`: resúmenes diarios o mensuales, para periodos antiguos o datos de factura. `resumenes_diarios.origen` distingue motor e importación.
- `generar_calendario(..., p_incluir_pasado)`: calendario de años pasados para el Partner. (Cambio aplicado en la 025.)
- Tipo de conexión `OPC_UA`.
- Permiso `IMPORTAR_HISTORICOS` (ADMIN_SAAS, ADMIN_PARTNER, TECNICO_PARTNER), exigido por `crear_importacion`, `importar_resumenes` y `solicitar_recuperacion` (D25).
- Simulación: `simular_lecturas` (= `procesar_lecturas(..., p_historico => true, p_simular => true)`, con comprobación de permiso) e `importar_resumenes(..., p_simular => true)`. No guardan nada (D26).
- `puede_importar(edificio)`: la API comprueba el permiso antes de leer un archivo.
- `importar_resumenes` con importación: cuenta lotes y cierra la importación al recibir el último.
- `perfiles_importacion`: formatos ANCHO y LARGO guardados por edificio (D23).
- Recuperación automática: `tipos_conexion.admite_recuperacion`; en `conexiones`, `recuperar_desde`, `recuperacion_estado`, `recuperado_hasta` e `id_importacion_recuperacion`; funciones `solicitar_recuperacion` (ajusta la fecha al límite de retención y avisa) y `avanzar_recuperacion` (la usa la API) (D24).
- Vía API para empresas IoT con el token de la conexión: `crear_importacion_token` y `procesar_lote_token`.
- Guía: `docs/edificios-existentes-historicos.md`.

## Migración 027 · Usuarios, contraseña inicial y doble factor (26/10/2026)

- `roles.requiere_doble_factor` (ADMIN_SAAS y ADMIN_PARTNER), `usuarios.debe_cambiar_contrasena` y `usuarios.doble_factor` (voluntario).
- `private.usuario_actual()` ya no reconoce al usuario mientras deba cambiar la contraseña o le falte el código en esa sesión: **RLS le niega todos los datos** aunque se salte la interfaz. Acepta también `aal2` por si en el futuro se usa el MFA nativo de Supabase.
- `codigos_verificacion`: códigos cifrados (hash) ligados al `session_id` de Supabase Auth. Solo los usa la API (`crear_codigo_verificacion`, `verificar_codigo`).
- `mi_cuenta()`: estado de la entrada para guiar al frontend (código pendiente, contraseña pendiente, acceso completo).
- Altas: `validar_alta_usuario` (con la sesión de quien da de alta) → la API crea la cuenta en Supabase Auth → `registrar_usuario` (solo API, vuelve a comprobar permisos). Si el registro falla, la API borra la cuenta recién creada.
- Gestión: `gestionar_usuario` (baja, reactivar, restablecer contraseña, activar o desactivar el doble factor propio). Nadie se da de baja a sí mismo; un técnico no gestiona a su administrador.
- Guía: `docs/usuarios-acceso.md`.

## Migración 028 · Sentilo, LoRaWAN, secretos y tarea periódica (26/10/2026)

- Tipo de conexión `LORAWAN` (ENVÍO). Dirección del sensor: `dev_eui` + `campo`; el trigger `trg_sensores_clave_lorawan` calcula `clave = DEVEUI/campo`, así `procesar_lecturas` no cambia.
- `conexiones.puntos_detectados`: campos recibidos sin sensor (`registrar_puntos_detectados`). `claves_conexion_token`: la API descarta lo no configurado.
- Secretos en Vault: `conexiones.id_secreto`, `guardar_secreto_conexion` (Partner con MODIFICAR_CONEXION) y `secreto_conexion` (solo API).
- Para la tarea: `conexiones_para_consultar`, `recuperaciones_pendientes`, `registrar_error_conexion`.
- `private.llamar_api_tareas()` y el trabajo de pg_cron `api_ciclo_15min` (URL y secreto en Vault: `api_url`, `api_tareas_secreto`).
- Guía: `docs/conectores.md`, apartados 10 a 13.

## Migración 029 · Conector API REST genérico (26/10/2026)

- `API_REST` pasa a llamarse "API REST (JSON)", admite recuperación de históricos y añade `parametro_desde`/`parametro_hasta`, `formato_parametros` y `ventana_horas`. `cabecera_api_key` se renombra a `cabecera_clave` (el control de secretos rechazaba cualquier clave con "api_key").
- `trg_conexiones_validar_api_rest`: URL http(s), cabecera obligatoria con API_KEY y parámetros de periodo en pareja.
- Guía: `docs/conectores.md`, apartado 10.

## Pendientes funcionales que debe cerrar el comprador

Son decisiones de negocio que el código deja abiertas a propósito:

| Tema | Estado actual en el código |
|---|---|
| Efecto de SUSPENDIDO en Partner/Cliente/Edificio | Se registra el estado, pero no bloquea el acceso. Solo BAJA (inactivo) lo retira |
| Un rol por usuario | Cada usuario tiene un único rol global. Una persona con funciones distintas en dos Partners necesita dos cuentas |
| Catálogo final de KPIs y pantalla HOY | Pendiente (maestro §4) |
| Precios y modalidades BASIC/PRO/PREMIUM | Las tablas existen; la validación de requisitos al cambiar de modalidad se hace en la API |
| Plantillas y destinatarios de notificaciones | Estructura lista; lógica de envío en la API |
| Retención de la auditoría | Indefinida |
| Pasarela Modbus/BACnet | Agente propio o gateways comerciales que envíen por HTTP/MQTT (ver `docs/conectores.md`) |
