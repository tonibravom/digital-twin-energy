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

## Cambios técnicos aplicados en las migraciones (20/10/2026)

**Seguridad**
- RLS activado en las 55 tablas desde la migración que las crea. Las particiones también tienen RLS y están en un esquema no expuesto.
- Las tablas de usuarios, roles y asignaciones tienen políticas de lectura por alcance y **no** admiten escritura directa. Las altas se hacen desde el backend con `service_role`.
- El rol anónimo no tiene acceso a ninguna tabla.
- Alta de edificio por Partner mediante `crear_edificio_partner()`.
- Protección de columnas sensibles:
  - cambiar el cliente de un edificio queda reservado al administrador;
  - dar de baja exige `DAR_BAJA_*`.
- Alarmas: no se editan directamente; se reconocen o cierran con `reconocer_alarma()` y `cerrar_alarma()`.
- Auditoría **automática por triggers** en 35 tablas de configuración. Ya no se puede escribir a mano. En las modificaciones solo guarda los campos cambiados.
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
