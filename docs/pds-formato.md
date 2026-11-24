# Formato de las peticiones de servicio · pds/1.0 (D63)

La plataforma genera peticiones de servicio (PDS) para las empresas mantenedoras, pero **no las gestiona**. No controla su estado, su asignación ni si se han ejecutado. Ese seguimiento lo hace la herramienta de mantenimiento (GMAO) del mantenedor.

Este documento describe los archivos para que cualquier herramienta pueda leerlos o importarlos.

## Archivos

Cada petición genera tres archivos y, si hay fotos, las fotos. Todos llevan el número de la petición en el nombre:

| Archivo | Contenido |
|---|---|
| `NUMERO.pdf` | La petición legible, para imprimir o enviar. Si viene de una alarma, incluye la gráfica del sensor con la banda de la alarma y su cronología. Lleva también las fotos. |
| `NUMERO.json` | El documento completo (ver abajo). Es la fuente para importar. |
| `NUMERO.csv` | Los campos principales en una fila, con cabecera. Separador `;`, texto entre comillas dobles (las comillas internas se doblan), UTF-8 con BOM y fin de línea CRLF. Se abre directamente en Excel. |
| `NUMERO-foto-N.jpg` | Fotos (hasta 5), en JPEG de 1400 px de lado como máximo. |

**Número.** Es `CODIGO-AAAA-NNNN`: el código del edificio en mayúsculas (`DEMO-` pasa a `DEMO`), el año y una secuencia por edificio y año. Ejemplo: `TORRE-2026-0007`. Es único en la instalación y sirve como referencia externa.

## Email

«Enviar por email» manda un email a cada destino elegido. Los destinos son los emails de entrada de peticiones del mantenedor, que el Partner configura por edificio.

- **Asunto**: `[PDS NUMERO] Prioridad · Título · Planta · Recinto`. Ejemplo: `[PDS TORRE-2026-0007] Urgente · Fuga en climatizadora · Planta 3 · Sala técnica`. El prefijo `[PDS ` permite filtrar el buzón o crear la orden automáticamente.
- **Cuerpo**: un resumen en texto y en HTML.
- **Adjuntos**: el PDF, el JSON, el CSV y las fotos.

## JSON

```json
{
  "formato": "pds",
  "version": "1.0",
  "numero": "TORRE-2026-0007",
  "creada": "2026-11-24T11:21:04Z",
  "zona_horaria": "Europe/Madrid",
  "tipo": "CORRECTIVO",
  "prioridad": "URGENTE",
  "titulo": "Presión de agua excesiva · Agua",
  "descripcion": "Texto libre (puede tener saltos de línea)",
  "edificio": { "codigo": "TORRE", "nombre": "…", "direccion": "…", "codigo_postal": "…", "municipio": "…", "provincia": "…" },
  "ubicacion": { "planta": "Sótano", "recinto": "Cuarto de contadores", "codigo_recinto": "CC" },
  "equipo": { "dispositivo": "…", "codigo_dispositivo": "…", "sensor": "…", "codigo_sensor": "…", "unidad": "bar",
              "fabricante": "…", "modelo": "…", "numero_serie": "…" },
  "origen": {
    "tipo": "ALARMA",
    "alarma": {
      "regla": "…", "nivel": "MUY_CRITICA", "nivel_nombre": "Muy crítica", "detalle": "…", "valor": 6.3,
      "desde": "2026-11-24T06:21:04Z", "estado": "RECONOCIDA",
      "cronologia": [ { "fecha": "…", "accion": "ABIERTA", "quien": "Plataforma", "detalle": "…" } ]
    }
  },
  "solicitante": { "nombre": "…", "email": "…", "telefono": "…", "empresa": "…" },
  "partner": "…",
  "adjuntos": [ { "nombre": "TORRE-2026-0007.pdf", "tipo": "PDF", "descripcion": "La petición legible" } ],
  "enlace": "https://…/edificio/<id>?pestana=alarmas&alarma=<id>"
}
```

Reglas para quien lo lea:

- **Fechas.** Van en ISO 8601 en UTC. `zona_horaria` es la del edificio, y sirve para mostrarlas en hora local.
- **Campos ausentes.** Los campos sin dato pueden faltar o venir a `null`, así que no deben darse por presentes. `ubicacion` y `equipo` faltan si no se eligió recinto o sensor.
- **Origen.** `origen.tipo` es `MANUAL` o `ALARMA`. Solo con `ALARMA` aparece `origen.alarma`.
- **Valores de `tipo`.** `CORRECTIVO`, `PREVENTIVO`, `LEGAL` (legal o reglamentario) y `MEJORA`.
- **Valores de `prioridad`.** `EMERGENCIA`, `URGENTE`, `NORMAL` y `PROGRAMABLE`. Desde una alarma se propone así: muy crítica → emergencia, crítica → urgente, aviso → normal.
- **Valores de `nivel`.** `MUY_CRITICA`, `CRITICA` y `AVISO`.
- **Valores de `accion` en la cronología.**
  - Ciclo de la alarma: `ABIERTA`, `RECONOCIDA`, `RESUELTA`, `VUELVE_CAUSA`, `REABIERTA`, `CERRADA`, `CERRADA_AUTOMATICA`.
  - Emails y escalado: `EMAIL_ENVIADO`, `EMAIL_ERROR`, `ESCALADA`.
  - Silencio: `SILENCIADA`, `SILENCIO_RETIRADO`, `SILENCIO_CADUCADO`.
  - Peticiones de servicio: `PDS_CREADA`, `PDS_ENVIADA`.
- **Valores de `adjuntos[].tipo`.** `PDF`, `JSON`, `CSV` y `FOTO`.
- **Enlace.** `enlace` abre la alarma (o el edificio) en la plataforma. Solo funciona para usuarios con acceso.
- **Versiones.** Una versión `1.x` solo añade campos. Un cambio incompatible sube a `2.0`. Conviene comprobar `formato` y la versión mayor.

## CSV

Columnas, en este orden:

| Grupo | Columnas |
|---|---|
| Petición | `numero`, `creada`, `tipo`, `prioridad`, `titulo`, `descripcion` |
| Edificio | `edificio_codigo`, `edificio_nombre`, `direccion`, `codigo_postal`, `municipio`, `provincia` |
| Ubicación | `planta`, `recinto`, `codigo_recinto` |
| Equipo | `dispositivo`, `codigo_dispositivo`, `sensor`, `codigo_sensor`, `fabricante`, `modelo`, `numero_serie` |
| Origen | `origen`, `alarma_regla`, `alarma_nivel`, `alarma_detalle`, `alarma_valor`, `alarma_desde` |
| Solicitante | `solicitante_nombre`, `solicitante_email`, `solicitante_telefono`, `solicitante_empresa`, `partner` |
| Archivos | `adjuntos` (nombres separados por ` \| `), `enlace` |

Los códigos (`tipo`, `prioridad`, `alarma_nivel`) y las fechas usan los mismos valores que el JSON.

## Dónde se guardan

- **Base de datos.** El documento se guarda en `pds.contenido`, con el mismo JSON.
- **Archivos.** Van al bucket privado `pds`, en `edificios/<id_edificio>/pds/<id_pds>/`.
- **Envíos.** Cada envío queda en `pds_envios` y su email en `notificaciones` (tipo y motivo `PDS`).
- **Registro.** La pestaña PDS del edificio muestra el registro (`pds_edificio`).
