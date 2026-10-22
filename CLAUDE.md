# CLAUDE.md — Plataforma de Gemelo Digital y Gestión Energética de Edificios

Instrucciones para Claude Code. Se leen al inicio de cada sesión. Mantener breve y actualizado.

## Producto
Plataforma multi-tenant de monitorización energética y gemelo digital 3D (GLB) de edificios.
**Se vende como copia única con cesión total del código:** el comprador contrata y opera su propio Supabase, API y frontend. Todo debe ser instalable y comprensible por un tercero sin ayuda del autor.

Jerarquía dentro de una instalación: **ADMIN (rol `ADMIN_SAAS`) → PARTNER (tabla `proveedores`) → CLIENTE → EDIFICIO → PLANTA → RECINTO → DISPOSITIVO/SENSOR**.
- El motor y los catálogos son de la plataforma. El Partner solo parametriza (asigna sensores a entradas), nunca crea fórmulas.
- Referencias:
  - `docs/maestro.md` (documento maestro);
  - `docs/decisiones.md` (prevalece sobre el maestro);
  - `docs/instalacion.md`, `docs/dimensionamiento.md`, `docs/seguridad.md`;
  - `docs/conectores.md` y `docs/configuracion-partner.md` (especificación del asistente de alta de dispositivos);
  - `docs/pantallas.md` (navegación, plantilla de ámbito de 3 niveles, KPIs, listas y permisos);
  - `docs/pagina-edificio.md` (pestañas HOY, 3D, Históricos, Alarmas, Ficha, Análisis y Configuración);
  - `docs/configuracion-edificio.md` (alta guiada, edición, sustituciones, GLB, Excel, calendario);
  - `docs/edificios-existentes-historicos.md` (equipos existentes, importaciones por lotes, resúmenes antiguos, recálculo).
- Si el código contradice esos documentos, PREGUNTAR antes de cambiar nada.

## Alcance actual
**Se desarrolla solo la modalidad BASIC** (decisión D21). PRO/PREMIUM (análisis energético, predicción, Datadis, validación de facturas) quedan fuera por ahora: no implementarlos sin indicación expresa.

## Arquitectura
| Pieza | Tecnología | Repo |
|---|---|---|
| Frontend | HTML + JavaScript, dashboard único | `dashboard-edificio` |
| API / motor | Python + FastAPI | `digital-twin-api` |
| BD | Supabase obligatorio (PostgreSQL + Auth + RLS + Storage bucket privado `modelos-3d`) | `supabase/migrations/` |

## Reglas de seguridad (no negociables)
1. La frontera de seguridad es RLS + API. Ocultar en HTML no es seguridad.
2. **Toda tabla nueva lleva `enable row level security` en la MISMA migración que la crea.** `select * from public.verificar_rls()` debe devolver 0 filas.
3. La `service_role` key solo en variables de entorno de la API. Nunca en el frontend ni en el repositorio.
4. Funciones `security definer`:
   - `set search_path = ''`;
   - nombres totalmente cualificados;
   - `revoke all ... from public, anon`;
   - `grant execute` solo a quien toque.
5. Toda relación entre entidades valida que pertenecen al mismo edificio mediante un trigger, aunque RLS ya filtre.
6. Usuarios, roles y asignaciones solo se escriben desde la API (`service_role`), nunca desde el navegador.
7. **Toda lectura entra por `public.procesar_lecturas()`** (o `procesar_lecturas_token`; los históricos, por `procesar_lote_lecturas` o `procesar_lote_token`). Ningún conector inserta directamente en `lecturas`. Protocolos nuevos = fila en `tipos_conexion` con sus esquemas + conector en la API; nunca tablas por protocolo. Ver `docs/conectores.md`.
8. **Energía consumida** = electricidad importada + gas + renovable consumida (FV y eólica − exportada + térmicas). Emisiones: solo importada y gas. Misma definición en KPIs, HOY y Sankey.
9. Los KPIs de los dashboards salen SIEMPRE de `kpis_ambito` / `kpis_lista` (sobre `resumenes_diarios`), y la página de edificio de `hoy_edificio`, `serie_magnitud`, `serie_sensor` y `sensores_estado_edificio`. Nunca se suman lecturas desde la web.
10. Tablas grandes (`lecturas`, `valores_magnitud`): políticas con `columna in (select private.xxx_accesibles())`, nunca funciones evaluadas por fila.

## Convenciones de base de datos
- Nombres en español, snake_case. PK `id uuid default gen_random_uuid()`; catálogos `smallint identity`.
- Baja lógica con `activo` + fechas y check de coherencia. **Nunca borrado físico**, salvo la retención de `lecturas` (año actual − 4, por particiones).
- Sustituir dispositivo/sensor = `sustituir_sensor` / `sustituir_dispositivo`; nueva versión de GLB = `sustituir_modelo_3d`. Nunca editar "a mano" esas sustituciones.
- `updated_at` mediante el trigger `public.set_updated_at()`. La auditoría es automática (trigger `trg_auditoria`): al crear una tabla de configuración, añadirla a la lista de 012.
- Timestamps `timestamptz` en UTC; la interfaz usa `edificios.zona_horaria`.
- **Modelos 3D: EDIFICIO o RECINTO (nunca planta).** Un modelo activo por edificio y otro por recinto. `modelos_3d.id_edificio` siempre informado. Rutas: `edificios/<id>/modelos/x.glb` y `recintos/<id>/modelos/x.glb`. Primero se crea el registro y luego se sube el archivo.
- `lecturas`: PK (id_sensor, fecha_hora), particionada por mes en el esquema `particiones`. Ingesta con `on conflict do nothing`. Calidad: 0 válida, 1 estimada, 2 corregida.
- Migraciones idempotentes (`if not exists`, `drop ... if exists`). Una migración aplicada nunca se edita: se crea otra nueva.

## Flujo de trabajo
- Nunca ejecutar contra producción. Entornos: local (`supabase start`) → staging → producción.
- Antes de dar por bueno un cambio de BD, deben pasar `npx supabase db reset` y `npx supabase test db`.
- Cada cambio de RLS lleva pruebas pgTAP en `supabase/tests/database/` con dos Partners: lo que SÍ y lo que NO pueden hacer.
- Trabajar en una rama con commits pequeños y abrir PR a `main`. Indicar en el PR qué decisión implementa.
- Si falta una decisión funcional (ver "Pendientes" en `docs/decisiones.md`), preguntar; no inventarla.

## Comandos (Windows, PowerShell)
```powershell
npx supabase start          # BD local (requiere Docker Desktop)
npx supabase db reset       # recrea la BD local aplicando todas las migraciones
npx supabase test db        # pruebas pgTAP (240 a 22/10/2026: 47 seguridad + 51 conectores + 24 KPIs + 22 página de edificio + 18 Sankey + 28 configuración + 22 históricos + 28 importación)
npx supabase db push        # SOLO contra el proyecto enlazado de staging
```
