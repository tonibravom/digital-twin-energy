# Alta y edición de edificios

Dónde y cómo se introducen los datos de un edificio: datos generales, plantas, recintos, suministros, conexiones, dispositivos, sensores, modelos GLB, calendario y parametrización. Acordado el 21/10/2026.

## 1. Un solo lugar: pestaña "Configuración" del edificio

Solo la ven el Partner y el administrador. La pestaña se compone de:
- **arriba**, la barra de progreso de la parametrización ("7 de 9") y, cuando todo lo bloqueante está en verde, el botón **"Cerrar parametrización"**;
- **a la izquierda**, un submenú con las secciones en el orden lógico de trabajo.

| # | Sección | Contenido | Soporte en la base de datos |
|---|---|---|---|
| 1 | **Datos generales** | Nombre, código, dirección y posición en el mapa (buscando la dirección o con chincheta), superficies construida, útil y libre, nº de plantas, año, uso, zona horaria | `edificios` |
| 2 | **Estructura** | Árbol **plantas → recintos**: añadir, renombrar, ordenar y desactivar. Nivel (negativos = sótanos), tipo (incluido *Planta completa*), superficie y altura | `plantas`, `recintos` |
| 3 | **Suministros** | Electricidad (CUPS, tarifa, potencias P1–P6, energía verde y %), gas, agua, agua contra incendios, generación (tecnología, potencias, puesta en marcha) | `suministros` y tablas por tipo |
| 4 | **Conexiones** | Alta con el formulario de cada protocolo, token de envío, botón **"Probar conexión"** y diagnóstico (último correcto, último error) | `conexiones` (021) |
| 5 | **Dispositivos y sensores** | Tabla agrupada por recinto, con el estado de cada sensor (pendiente, probado, error). **"Nuevo dispositivo"** abre el asistente de `configuracion-partner.md`. En cada fila: Probar lectura, Editar, **Sustituir**, Desactivar | `dispositivos`, `sensores`, plantillas (021) |
| 6 | **Magnitudes y usos** | A qué magnitud alimenta cada sensor, su **uso final** y el **reparto** de lo no medido | `magnitudes_fuentes`, `repartos_uso_edificio` (024) |
| 7 | **Modelos 3D** | Modelo general y uno por recinto, con versiones. Tabla de **coordenadas X, Y, Z** por sensor o dispositivo y vista previa | `modelos_3d`, `ubicaciones_3d` |
| 8 | **Calendario** | Enlace a la pestaña **Ficha** (ver apartado 6) | `calendario_edificio` (025) |
| 9 | **Alarmas** | Reglas del edificio | `reglas_alarma` |
| 10 | **Modalidad y usuarios** | BASIC / PRO / PREMIUM, complemento 3D y usuarios del cliente con acceso | `modalidades_edificio`, `usuarios_edificios` |

## 2. Alta de un edificio nuevo (modo guiado)

1. En el nivel Cliente, **"Nuevo edificio"** pide solo nombre, código y dirección (`crear_edificio_partner`).
2. El edificio nace en **pendiente de parametrización** y se abre Configuración en **modo guiado**:
   - recorre las secciones 1 a 10 con "Anterior" y "Siguiente";
   - se puede saltar una sección y volver más tarde; todo se guarda al momento;
   - el avance aparece en el panel "Pendientes" del Partner.
3. Con todo lo bloqueante en verde, **"Cerrar parametrización"** pasa el edificio a **operativo** (`cerrar_parametrizacion`).

## 3. Edición de un edificio existente

Las mismas secciones, con navegación libre. Las reglas se aplican automáticamente:

| Acción | Qué ocurre |
|---|---|
| Cambiar cómo se lee un sensor (dirección, escala, rango, conexión) | Vuelve a **pendiente de prueba** |
| **Sustituir** un sensor | Se crea uno nuevo con el **mismo código**. El antiguo se desactiva y se renombra (`código#AAAAMMDD-xxxx`) conservando sus lecturas. Magnitud, uso, posición 3D, reglas de alarma y ámbitos pasan al nuevo (`sustituir_sensor`) |
| **Sustituir** un dispositivo (avería, cambio de equipo) | Dispositivo nuevo, con nuevo número de serie y todos sus sensores sustituidos. Suministros y posición 3D pasan al nuevo (`sustituir_dispositivo`) |
| Subir una **nueva versión del GLB** | La versión anterior queda inactiva. Las coordenadas se **copian marcadas "por revisar"** y la lista de comprobación lo avisa. Al corregir una coordenada, o al confirmarlas en bloque (`confirmar_coordenadas`), dejan de estar pendientes (`sustituir_modelo_3d`) |
| Desactivar una planta o un recinto | **No se permite** si tiene recintos, sensores o dispositivos activos. Primero hay que moverlos o darlos de baja |
| Cambiar el cliente de un edificio | Solo el administrador de la plataforma |

Todos los cambios quedan en la **auditoría**.

**Modelos 3D, paso a paso:**
1. Se crea el registro del modelo, con la ruta `edificios/<id>/modelos/<archivo>.glb` o `recintos/<id>/modelos/<archivo>.glb`.
2. Se sube el archivo al bucket privado. Límite de 200 MB; se admiten GLB, GLTF y compresión Draco.
3. Se escriben las coordenadas tomadas de un **visor de GLB sobre ese mismo archivo** (ver `configuracion-partner.md`).

## 4. Importación desde Excel

Para edificios con muchos elementos, cada sección ofrece **"Descargar plantilla Excel"** e **"Importar"**:

| Plantilla | Columnas principales |
|---|---|
| Estructura | planta (código, nombre, nivel), recinto (código, nombre, tipo, superficie) |
| Dispositivos y sensores | recinto, dispositivo, sensor, qué mide (familia, naturaleza, tratamiento, energía, flujo), unidad de origen y destino, escala, rango, dirección en el origen, uso final |
| Coordenadas 3D | modelo, sensor o dispositivo, X, Y, Z |
| Calendario | fecha, laborable, hora de inicio, hora de fin |

Al importar, la plataforma **valida todo antes de guardar** y muestra un resumen: cuántas filas se crean, cuántas se modifican y la lista de errores por fila. Solo se guarda si el usuario confirma; las filas con errores se descartan o se corrigen y se vuelven a subir. La importación usa las mismas funciones y validaciones que la pantalla, así que no hay atajos que salten reglas. Se construye en la API (Fase 3).

## 5. Quién puede hacer qué

| Sección | Admin plataforma | Admin Partner | Técnico Partner | Cliente avanzado | Cliente |
|---|---|---|---|---|---|
| Configuración (1–7, 9, 10) | ✔ | ✔ | ✔ (sin bajas de edificio) | — | — |
| Calendario (pestaña Ficha) | ✔ | ✔ | ✔ | ✔ (de hoy en adelante) | Solo ver |

## 6. Calendario (pestaña Ficha)

El calendario es **del edificio**, no de sus sensores. Está en la pestaña **Ficha**, accesible al Partner y al **cliente avanzado**. Desde Configuración se enlaza ahí.

- **Horario tipo:** para cada día de la semana, laborable o no y su horario. Ejemplo: lunes a viernes de 8:00 a 18:00 y fin de semana cerrado (`horarios_tipo_edificio`).
- **Festivos compartidos:**
  - por **país, provincia o municipio** (`festivos`), que se aplican solos según la ubicación del edificio;
  - los de la plataforma los mantiene el administrador; cada Partner puede añadir los suyos, que solo afectan a sus edificios;
  - los autonómicos se registran en cada provincia de la comunidad.
- **Generación anual automática:** desde el **1 de diciembre**, la tarea diaria de mantenimiento crea el calendario del año siguiente a partir del horario tipo y los festivos. No pisa días ya ajustados. También se puede generar a mano (`generar_calendario`).
- **Ajustes:** sobre el año generado, el Partner o el cliente avanzado marcan las excepciones (vacaciones, cierres, horarios especiales). El calendario sigue guardándose **día a día**, como fija el maestro.
- **Protección del histórico:** el cliente **no puede modificar días pasados**, para no alterar los análisis ya hechos. El Partner sí, por ejemplo para corregir un error.

Se incluyen de ejemplo los festivos nacionales de España de 2027. El comprador debe mantener cada año los de su país.
