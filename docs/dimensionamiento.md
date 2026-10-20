# Guía de dimensionamiento de la base de datos

Esta guía ayuda a decidir qué recursos de Supabase hay que contratar según el número de Partners, clientes, edificios y sensores. Las cifras salen de mediciones reales del esquema de la plataforma (PostgreSQL 16, octubre 2026) y suponen **una lectura cada 15 minutos por sensor**.

## 1. Qué ocupa espacio

Casi todo el volumen lo generan dos tablas:

| Tabla | Qué guarda | Cuánto se conserva | Tamaño medido |
|---|---|---|---|
| `lecturas` | Valores brutos de cada sensor | Año en curso + 4 años completos anteriores (en 2026, desde el 01/01/2022) | ~117 bytes por lectura, índice incluido |
| `valores_magnitud` | Magnitudes calculadas por el motor (consumo, generación, CO₂…) | Indefinidamente | ~117 bytes por valor |

El resto (organización, configuración, usuarios, alarmas, auditoría) ocupa poco: decenas o cientos de MB incluso en instalaciones grandes.

Partners y clientes **no** influyen en el tamaño. Lo que cuenta es el número total de **sensores** y la **frecuencia** de lectura.

Un sensor a 15 minutos genera 35.040 lecturas al año, unos **4,1 MB/año**.

## 2. Tamaños de referencia

Suposiciones: 20 magnitudes calculadas por edificio a 15 minutos.

| Instalación | Edificios × sensores | Lecturas por año | Lecturas retenidas (máx. 5 años) | Magnitudes por año (se acumulan) | Total aproximado a 5 años | Escrituras/s |
|---|---|---|---|---|---|---|
| **Pequeña** | 20 × 50 = 1.000 | 4 GB | 20 GB | 1,6 GB | **~30 GB** | ~1 |
| **Mediana** | 200 × 100 = 20.000 | 82 GB | 410 GB | 16 GB | **~500 GB** | ~22 |
| **Grande** | 2.000 × 100 = 200.000 | 820 GB | 4,1 TB | 164 GB | **~4,9 TB** | ~222 |

Fórmula para un caso propio:

```
GB por año de lecturas  = sensores × 0,0041
GB máximo retenido      = GB por año × 5
GB por año de magnitudes = edificios × magnitudes por edificio × 0,0041
```

Hay que añadir un **30 %** de margen para índices temporales, WAL (registro de cambios de PostgreSQL) y crecimiento. Las copias de seguridad de Supabase no ocupan disco de la base de datos.

## 3. Qué contratar en Supabase

Los nombres y precios de los planes cambian. Consulte la oferta vigente en https://supabase.com/pricing y elija por **disco** y por **capacidad de cómputo** (CPU/RAM).

| Instalación | Plan | Cómputo orientativo | Disco | Copias de seguridad |
|---|---|---|---|---|
| Pequeña (hasta ~50 edificios) | De pago (no usar el gratuito en producción: se pausa por inactividad) | 2 vCPU, 4 GB RAM | 50 GB | Diarias |
| Mediana (50–500 edificios) | De pago | 4 vCPU, 16 GB RAM | 0,5–1 TB | Diarias + Point-in-Time Recovery |
| Grande (500–2.000 edificios) | De pago o Enterprise | 8–16 vCPU, 32–64 GB RAM | 5–6 TB | Point-in-Time Recovery |
| Muy grande (> 2.000 edificios) | Ver apartado 5 | | | |

Señales para subir de nivel:
- CPU sostenida por encima del 70 % en horario laboral.
- Consultas del dashboard por encima de 1 segundo.
- Disco por encima del 75 %.

Supabase muestra estas métricas en *Reports* y *Database > Query Performance*.

## 4. Cómo escala el diseño

- **Particiones mensuales.** `lecturas` está dividida en una tabla por mes (esquema `particiones`, que la API no expone). Las consultas de un periodo solo leen los meses afectados, y la retención elimina meses completos de golpe, sin borrados lentos.
- **Particiones anuales** para `valores_magnitud`.
- **Mantenimiento automático.** La función `mantenimiento_datos()` crea las particiones de los 3 meses siguientes y aplica la retención. Se programa a diario con pg_cron (migración 018). Si pg_cron no está activo, el backend debe llamarla una vez al día con la `service_role`.
- **Control de acceso que escala.** Las políticas de seguridad de las tablas grandes calculan **una vez por consulta** los sensores accesibles para el usuario, no fila a fila.
- **Los dashboards deben consultar `valores_magnitud`**, no `lecturas`, para periodos largos (semanas, meses, años). `lecturas` se reserva para el detalle de un sensor en un periodo corto.
- **La ingesta escribe con la `service_role` desde el backend**, en lotes. Ejemplo: Sentilo cada 15 minutos, una inserción con todas las lecturas del edificio, con `on conflict (id_sensor, fecha_hora) do nothing` para que sea idempotente.

## 5. Más allá de una instalación grande

Una única base de datos llega cómodamente a unos 2.000 edificios con 100 sensores a 15 minutos. Para crecer más hay tres opciones, de menos a más complejas:

1. **Reducir la retención de lecturas brutas** (por ejemplo, 2 años) cambiando `limite_retencion_lecturas()`. Las magnitudes calculadas se siguen conservando indefinidamente.
2. **Archivar antes de borrar.** Exportar cada partición antigua a un archivo (CSV o Parquet) en Storage antes de que la retención la elimine.
3. **Una instalación independiente por Partner grande.** El código es el mismo y cada instalación tiene su propio proyecto Supabase. El documento maestro ya contempla esta "modalidad Enterprise".

## 6. Si cambia la frecuencia

Todas las cifras escalan linealmente con la frecuencia:

| Frecuencia | Factor sobre la tabla del apartado 2 |
|---|---|
| 15 minutos | ×1 |
| 5 minutos | ×3 |
| 1 minuto | ×15 |

A 1 minuto, una instalación "mediana" ya necesita los recursos de una "grande".
