begin;

-- =========================================================
-- EDIFICIOS EXISTENTES Y CARGA DE HISTÓRICOS (decisiones 21/10/2026)
--
-- · Importaciones registradas y por lotes, idempotentes y
--   reanudables (maestro §15).
-- · Las lecturas históricas entran por el canal único en modo
--   histórico (no tocan estado de comunicación ni incidencias).
-- · Cada lote deja un recálculo pendiente para el motor (Fase 5).
-- · Periodos anteriores al límite de retención: se importan como
--   RESÚMENES diarios o mensuales, que se conservan siempre.
-- · Nuevo tipo de conexión OPC UA.
-- =========================================================

-- ---------------------------------------------------------
-- 1. OPC UA
-- ---------------------------------------------------------
insert into public.tipos_conexion (codigo, nombre, descripcion) values
  ('OPC_UA', 'OPC UA', 'Servidores OPC UA de sistemas SCADA y de gestión de edificios.')
on conflict (codigo) do nothing;

update public.tipos_conexion set modo = 'PASARELA',
  esquema_configuracion = '{
    "type": "object",
    "required": ["endpoint", "politica_seguridad", "modo_seguridad"],
    "properties": {
      "endpoint":           {"type": "string", "title": "URL del servidor", "examples": ["opc.tcp://192.168.1.20:4840"]},
      "politica_seguridad": {"type": "string", "enum": ["None", "Basic256Sha256", "Aes128_Sha256_RsaOaep", "Aes256_Sha256_RsaPss"]},
      "modo_seguridad":     {"type": "string", "enum": ["None", "Sign", "SignAndEncrypt"]},
      "usuario":            {"type": "string"},
      "id_secreto":         {"type": "string", "title": "Contraseña o certificado (referencia en Vault)"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["node_id"],
    "properties": {
      "node_id":     {"type": "string", "title": "NodeId", "examples": ["ns=2;s=Planta1.Contador1.Energia"]},
      "muestreo_ms": {"type": "integer", "title": "Intervalo de muestreo (ms)", "default": 60000}
    }
  }'::jsonb
where codigo = 'OPC_UA';

-- Permiso de importación: solo Partner y administrador (decisión 21/10/2026)
insert into public.permisos (codigo, nombre, modulo) values
  ('IMPORTAR_HISTORICOS', 'Importar datos históricos', 'DATOS')
on conflict (codigo) do nothing;

insert into public.roles_permisos (id_rol, id_permiso)
select r.id, p.id from public.roles r, public.permisos p
where r.codigo in ('ADMIN_SAAS', 'ADMIN_PARTNER', 'TECNICO_PARTNER') and p.codigo = 'IMPORTAR_HISTORICOS'
on conflict do nothing;

-- ---------------------------------------------------------
-- 2. Registro de importaciones
-- ---------------------------------------------------------
create table if not exists public.importaciones (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  id_conexion uuid references public.conexiones(id) on delete restrict,
  tipo varchar(20) not null,
  origen varchar(20) not null,
  nombre_archivo text,
  estado varchar(20) not null default 'EN_CURSO',
  total_lotes integer,
  lotes_procesados integer not null default 0,
  recibidas bigint not null default 0,
  guardadas bigint not null default 0,
  duplicadas bigint not null default 0,
  rechazadas bigint not null default 0,
  desde timestamptz,
  hasta timestamptz,
  id_usuario uuid references public.usuarios(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint importaciones_tipo_ck check (tipo in ('LECTURAS', 'RESUMENES')),
  constraint importaciones_origen_ck check (origen in ('EXCEL', 'CSV', 'API', 'CONECTOR')),
  constraint importaciones_estado_ck check (estado in ('EN_CURSO', 'COMPLETADA', 'CON_ERRORES', 'CANCELADA')),
  constraint importaciones_conexion_ck check (tipo <> 'LECTURAS' or id_conexion is not null)
);

create index if not exists ix_importaciones_edificio on public.importaciones(id_edificio, created_at desc);

create table if not exists public.importaciones_lotes (
  id_importacion uuid not null references public.importaciones(id) on delete restrict,
  numero integer not null,
  estado varchar(20) not null,
  resultado jsonb not null default '{}'::jsonb,
  procesado_at timestamptz not null default now(),
  constraint importaciones_lotes_pk primary key (id_importacion, numero),
  constraint importaciones_lotes_estado_ck check (estado in ('OK', 'CON_ERRORES', 'FALLIDO'))
);

comment on table public.importaciones is
  'Cargas de datos (históricos o masivas). Se procesan por lotes numerados; repetir un lote ya procesado no hace nada, así una importación interrumpida se reanuda sin duplicar.';

-- ---------------------------------------------------------
-- 3. Recálculos pendientes para el motor (Fase 5)
-- ---------------------------------------------------------
create table if not exists public.recalculos_pendientes (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  desde timestamptz not null,
  hasta timestamptz not null,
  motivo varchar(40) not null,
  id_importacion uuid references public.importaciones(id) on delete set null,
  estado varchar(20) not null default 'PENDIENTE',
  created_at timestamptz not null default now(),
  procesado_at timestamptz,
  constraint recalculos_estado_ck check (estado in ('PENDIENTE', 'EN_CURSO', 'HECHO', 'ERROR')),
  constraint recalculos_periodo_ck check (hasta >= desde)
);

create index if not exists ix_recalculos_pendientes on public.recalculos_pendientes(estado, created_at)
  where estado in ('PENDIENTE', 'EN_CURSO');

comment on table public.recalculos_pendientes is
  'Periodos que el motor debe volver a calcular (valores_magnitud y resúmenes) tras cargar datos pasados o corregirlos.';

-- ---------------------------------------------------------
-- 4. Crear importación y procesar lotes
-- ---------------------------------------------------------
create or replace function public.crear_importacion(
  p_id_edificio uuid,
  p_tipo text,
  p_origen text,
  p_id_conexion uuid default null,
  p_nombre_archivo text default null,
  p_total_lotes integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is not null
     and not private.usuario_puede_edificio(p_id_edificio, 'IMPORTAR_HISTORICOS') then
    raise exception 'Sin permiso para importar datos en este edificio' using errcode = '42501';
  end if;

  if p_id_conexion is not null
     and (select id_edificio from public.conexiones where id = p_id_conexion) is distinct from p_id_edificio then
    raise exception 'La conexión no pertenece al edificio';
  end if;

  insert into public.importaciones (id_edificio, id_conexion, tipo, origen, nombre_archivo, total_lotes, id_usuario)
  values (p_id_edificio, p_id_conexion, p_tipo, p_origen, p_nombre_archivo, p_total_lotes, private.usuario_actual())
  returning id into v_id;

  return v_id;
end;
$$;

-- Lote de lecturas históricas. Si el lote ya se procesó, no se repite.
create or replace function public.procesar_lote_lecturas(
  p_id_importacion uuid,
  p_numero integer,
  p_lecturas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_imp public.importaciones%rowtype;
  v_res jsonb;
begin
  select * into v_imp from public.importaciones where id = p_id_importacion for update;

  if not found or v_imp.tipo <> 'LECTURAS' then
    raise exception 'Importación de lecturas inexistente';
  end if;
  if v_imp.estado = 'CANCELADA' then
    raise exception 'La importación está cancelada';
  end if;

  if exists (select 1 from public.importaciones_lotes
             where id_importacion = p_id_importacion and numero = p_numero) then
    return pg_catalog.jsonb_build_object('lote', p_numero, 'ya_procesado', true);
  end if;

  v_res := public.procesar_lecturas(v_imp.id_conexion, p_lecturas, true);

  insert into public.importaciones_lotes (id_importacion, numero, estado, resultado)
  values (p_id_importacion, p_numero,
          case when (v_res->>'rechazadas')::integer > 0 then 'CON_ERRORES' else 'OK' end, v_res);

  update public.importaciones
     set lotes_procesados = lotes_procesados + 1,
         recibidas = recibidas + (v_res->>'recibidas')::integer,
         guardadas = guardadas + (v_res->>'guardadas')::integer,
         duplicadas = duplicadas + (v_res->>'duplicadas')::integer,
         rechazadas = rechazadas + (v_res->>'rechazadas')::integer,
         desde = least(desde, (v_res->>'desde')::timestamptz),
         hasta = greatest(hasta, (v_res->>'hasta')::timestamptz),
         estado = case when total_lotes is not null and lotes_procesados + 1 >= total_lotes
                       then case when rechazadas + (v_res->>'rechazadas')::integer > 0 then 'CON_ERRORES' else 'COMPLETADA' end
                       else estado end,
         updated_at = pg_catalog.now()
   where id = p_id_importacion;

  if (v_res->>'guardadas')::integer > 0 then
    insert into public.recalculos_pendientes (id_edificio, desde, hasta, motivo, id_importacion)
    values (v_imp.id_edificio, (v_res->>'desde')::timestamptz, (v_res->>'hasta')::timestamptz,
            'IMPORTACION_HISTORICO', p_id_importacion);
  end if;

  return v_res || pg_catalog.jsonb_build_object('lote', p_numero, 'ya_procesado', false);
end;
$$;

-- ---------------------------------------------------------
-- 5. Resúmenes históricos (periodos anteriores a la retención o
--    datos que solo existen agregados, p. ej. facturas)
-- Filas: {"indicador": "CONSUMO_GAS", "fecha": "2019-03-14", "valor": 120}
--     o  {"indicador": "CONSUMO_ELECTRICIDAD", "mes": "2019-03", "valor": 3100}
-- Un valor mensual se reparte por igual entre los días del mes y se
-- marca como no completo. No pisa resúmenes calculados por el motor
-- salvo que se pida.
-- ---------------------------------------------------------
alter table public.resumenes_diarios
  add column if not exists origen varchar(20) not null default 'MOTOR';

alter table public.resumenes_diarios drop constraint if exists resumenes_diarios_origen_ck;
alter table public.resumenes_diarios add constraint resumenes_diarios_origen_ck
  check (origen in ('MOTOR', 'IMPORTACION_DIARIA', 'IMPORTACION_MENSUAL'));

create or replace function public.importar_resumenes(
  p_id_edificio uuid,
  p_filas jsonb,
  p_sobrescribir boolean default false,
  p_id_importacion uuid default null,
  p_simular boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_validos constant text[] := array[
    'CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'CONSUMO_AGUA', 'ELECTRICIDAD_EXPORTADA',
    'GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA', 'GENERACION_SOLAR_TERMICA',
    'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA'];
  v_recibidas integer;
  v_dias integer := 0;
  v_rechazos jsonb;
  v_desde date;
  v_hasta date;
begin
  if auth.uid() is not null
     and not private.usuario_puede_edificio(p_id_edificio, 'IMPORTAR_HISTORICOS') then
    raise exception 'Sin permiso para importar datos en este edificio' using errcode = '42501';
  end if;

  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then
    raise exception 'Se esperaba una lista de filas';
  end if;
  v_recibidas := pg_catalog.jsonb_array_length(p_filas);

  with entrada as (
    select e.ord::integer, e.item,
           e.item->>'indicador' as indicador,
           case when pg_catalog.jsonb_typeof(e.item->'valor') = 'number' then (e.item->>'valor')::double precision end as valor,
           case when e.item->>'fecha' ~ '^\d{4}-\d{2}-\d{2}$' then (e.item->>'fecha')::date end as fecha,
           case when e.item->>'mes' ~ '^\d{4}-(0[1-9]|1[0-2])$' then ((e.item->>'mes') || '-01')::date end as mes
    from pg_catalog.jsonb_array_elements(p_filas) with ordinality as e(item, ord)
  ),
  clasificadas as (
    select en.*,
           case
             when en.indicador is null or not (en.indicador = any (v_validos)) then 'indicador no válido'
             when en.valor is null or en.valor < 0 then 'valor no válido'
             when en.fecha is null and en.mes is null then 'falta "fecha" (AAAA-MM-DD) o "mes" (AAAA-MM)'
             when coalesce(en.fecha, en.mes) > current_date then 'fecha futura'
           end as motivo
    from entrada en
  ),
  expandidas as (
    select c.indicador, c.fecha as dia, c.valor, 'IMPORTACION_DIARIA'::text as origen, true as completo
    from clasificadas c where c.motivo is null and c.fecha is not null
    union all
    select c.indicador, d::date, c.valor / extract(day from (c.mes + interval '1 month - 1 day'))::double precision,
           'IMPORTACION_MENSUAL', false
    from clasificadas c
    cross join pg_catalog.generate_series(c.mes, c.mes + interval '1 month - 1 day', interval '1 day') d
    where c.motivo is null and c.fecha is null
  ),
  -- Días que no se pueden escribir: ya calculados por el motor y sin permiso de sobrescribir
  bloqueados as (
    select e.dia, e.indicador from expandidas e
    join public.resumenes_diarios r
      on r.id_edificio = p_id_edificio and r.fecha = e.dia and r.indicador = e.indicador
    where r.origen = 'MOTOR' and not p_sobrescribir
  ),
  ins as (
    insert into public.resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen)
    select p_id_edificio, dia, indicador, valor, completo, origen from expandidas
    where not p_simular
    on conflict (id_edificio, fecha, indicador) do update
      set valor = excluded.valor, completo = excluded.completo, origen = excluded.origen,
          actualizado = pg_catalog.now()
      where p_sobrescribir or public.resumenes_diarios.origen <> 'MOTOR'
    returning fecha
  )
  select case when p_simular then (select count(*) from expandidas) - (select count(*) from bloqueados)
              else (select count(*) from ins) end,
         case when p_simular then (select min(dia) from expandidas) else (select min(fecha) from ins) end,
         case when p_simular then (select max(dia) from expandidas) else (select max(fecha) from ins) end,
         (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('posicion', ord, 'motivo', motivo) order by ord), '[]'::jsonb)
          from (select ord, motivo from clasificadas where motivo is not null order by ord limit 50) x)
    into v_dias, v_desde, v_hasta, v_rechazos;

  if p_id_importacion is not null and not p_simular then
    update public.importaciones
       set recibidas = recibidas + v_recibidas,
           guardadas = guardadas + v_dias,
           rechazadas = rechazadas + pg_catalog.jsonb_array_length(v_rechazos),
           desde = least(desde, v_desde::timestamptz),
           hasta = greatest(hasta, v_hasta::timestamptz),
           lotes_procesados = lotes_procesados + 1,
           estado = case when total_lotes is not null and lotes_procesados + 1 >= total_lotes
                         then case when rechazadas + pg_catalog.jsonb_array_length(v_rechazos) > 0
                                   then 'CON_ERRORES' else 'COMPLETADA' end
                         else estado end,
           updated_at = pg_catalog.now()
     where id = p_id_importacion and id_edificio = p_id_edificio;
  end if;

  return pg_catalog.jsonb_build_object(
    'simulacion', p_simular,
    'recibidas', v_recibidas,
    'dias_guardados', v_dias,
    'desde', v_desde,
    'hasta', v_hasta,
    'rechazadas', pg_catalog.jsonb_array_length(v_rechazos),
    'detalle_rechazos', v_rechazos);
end;
$$;

-- ---------------------------------------------------------
-- 5 bis. Simulación de lecturas (vista previa, no guarda nada)
-- ---------------------------------------------------------
create or replace function public.simular_lecturas(p_id_conexion uuid, p_lecturas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  select c.id_edificio into v_edificio from public.conexiones c where c.id = p_id_conexion;
  if v_edificio is null then
    raise exception 'La conexión no existe';
  end if;
  if auth.uid() is not null
     and not private.usuario_puede_edificio(v_edificio, 'IMPORTAR_HISTORICOS') then
    raise exception 'Sin permiso para importar datos en este edificio' using errcode = '42501';
  end if;
  return public.procesar_lecturas(p_id_conexion, p_lecturas, true, true);
end;
$$;

-- La API lo consulta antes de leer un archivo (asistente de importación).
create or replace function public.puede_importar(p_id_edificio uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.usuario_puede_edificio(p_id_edificio, 'IMPORTAR_HISTORICOS');
$$;

-- ---------------------------------------------------------
-- 5 ter. Perfiles de importación (formato y emparejamiento guardados)
-- configuracion, según el formato:
--   ANCHO: {"hoja": "Datos", "fila_cabecera": 2, "fila_inicio": 4,
--           "columna_fecha": "A", "formato_fecha": "DD/MM/YYYY HH:mm",
--           "zona_horaria": "Europe/Madrid", "separador_decimal": ",",
--           "vacios": "DESCARTAR",
--           "columnas": [{"columna": "B", "clave": "CONT-01/energia"}, ...]}
--   LARGO: {"fila_inicio": 2, "columna_fecha": "A", "columna_sensor": "B",
--           "columna_valor": "C", "columna_calidad": "D", ...}
--   RESUMENES: {"columna_indicador": "A", "columna_periodo": "B",
--               "columna_valor": "C", "periodo": "MES"}
-- ---------------------------------------------------------
create table if not exists public.perfiles_importacion (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  nombre varchar(120) not null,
  tipo varchar(20) not null,
  formato varchar(20) not null,
  configuracion jsonb not null default '{}'::jsonb,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint perfiles_importacion_uq unique (id_edificio, nombre),
  constraint perfiles_importacion_tipo_ck check (tipo in ('LECTURAS', 'RESUMENES')),
  constraint perfiles_importacion_formato_ck check (
    (tipo = 'LECTURAS' and formato in ('ANCHO', 'LARGO'))
    or (tipo = 'RESUMENES' and formato in ('ANCHO', 'LARGO'))),
  constraint perfiles_importacion_config_ck check (
    jsonb_typeof(configuracion) = 'object'
    and (configuracion ? 'columna_fecha' or tipo = 'RESUMENES'))
);

comment on table public.perfiles_importacion is
  'Formatos de archivo guardados por edificio (filas, columnas, fechas, emparejamiento de columnas con sensores) para repetir importaciones.';

alter table public.perfiles_importacion enable row level security;

drop policy if exists perfiles_importacion_select on public.perfiles_importacion;
create policy perfiles_importacion_select on public.perfiles_importacion
for select to authenticated using (private.usuario_puede_edificio(id_edificio, 'IMPORTAR_HISTORICOS'));
drop policy if exists perfiles_importacion_insert on public.perfiles_importacion;
create policy perfiles_importacion_insert on public.perfiles_importacion
for insert to authenticated with check (private.usuario_puede_edificio(id_edificio, 'IMPORTAR_HISTORICOS'));
drop policy if exists perfiles_importacion_update on public.perfiles_importacion;
create policy perfiles_importacion_update on public.perfiles_importacion
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'IMPORTAR_HISTORICOS'))
with check (private.usuario_puede_edificio(id_edificio, 'IMPORTAR_HISTORICOS'));

drop trigger if exists trg_perfiles_importacion_updated_at on public.perfiles_importacion;
create trigger trg_perfiles_importacion_updated_at
before update on public.perfiles_importacion
for each row execute function public.set_updated_at();

drop trigger if exists trg_auditoria on public.perfiles_importacion;
create trigger trg_auditoria after insert or update or delete on public.perfiles_importacion
for each row execute function public.auditar_cambio();

-- ---------------------------------------------------------
-- 5 quater. Recuperación automática de históricos al conectar
-- Orígenes que guardan su propio histórico (Sentilo, API REST,
-- OPC UA). La API (tarea en segundo plano) pide el pasado por
-- tramos, lo carga con procesar_lote_lecturas y avanza el cursor.
-- ---------------------------------------------------------
alter table public.tipos_conexion
  add column if not exists admite_recuperacion boolean not null default false;

update public.tipos_conexion set admite_recuperacion = true
where codigo in ('SENTILO', 'API_REST', 'OPC_UA');

alter table public.conexiones
  add column if not exists recuperar_desde date,
  add column if not exists recuperacion_estado varchar(20),
  add column if not exists recuperado_hasta timestamptz,
  add column if not exists id_importacion_recuperacion uuid references public.importaciones(id) on delete set null;

alter table public.conexiones drop constraint if exists conexiones_recuperacion_ck;
alter table public.conexiones add constraint conexiones_recuperacion_ck
  check (recuperacion_estado is null or recuperacion_estado in ('PENDIENTE', 'EN_CURSO', 'COMPLETADA', 'ERROR'));

create or replace function public.solicitar_recuperacion(p_id_conexion uuid, p_desde date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_con public.conexiones%rowtype;
  v_admite boolean;
  v_limite date := (public.limite_retencion_lecturas() at time zone 'UTC')::date;
  v_desde date := p_desde;
  v_imp uuid;
  v_aviso text;
begin
  select c.*, tc.admite_recuperacion into v_con
  from public.conexiones c join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  where c.id = p_id_conexion;

  if not found then
    raise exception 'La conexión no existe';
  end if;

  if auth.uid() is not null
     and not private.usuario_puede_edificio(v_con.id_edificio, 'IMPORTAR_HISTORICOS') then
    raise exception 'Sin permiso para importar datos en este edificio' using errcode = '42501';
  end if;

  select tc.admite_recuperacion into v_admite
  from public.tipos_conexion tc where tc.id = v_con.id_tipo_conexion;
  if not v_admite then
    raise exception 'Este tipo de conexión no permite recuperar históricos automáticamente: use la importación de archivos';
  end if;

  if v_con.recuperacion_estado in ('PENDIENTE', 'EN_CURSO') then
    raise exception 'Ya hay una recuperación en marcha para esta conexión';
  end if;

  if p_desde is null or p_desde >= current_date then
    raise exception 'Indique una fecha de inicio anterior a hoy';
  end if;

  if v_desde < v_limite then
    v_desde := v_limite;
    v_aviso := 'Las lecturas anteriores a ' || v_limite || ' no se conservan: para ese periodo importe resúmenes';
  end if;

  v_imp := public.crear_importacion(v_con.id_edificio, 'LECTURAS', 'CONECTOR', p_id_conexion,
                                    'Recuperación automática desde ' || v_desde, null);

  update public.conexiones
     set recuperar_desde = v_desde,
         recuperacion_estado = 'PENDIENTE',
         recuperado_hasta = null,
         id_importacion_recuperacion = v_imp
   where id = p_id_conexion;

  return pg_catalog.jsonb_build_object('id_importacion', v_imp, 'desde', v_desde, 'aviso', v_aviso);
end;
$$;

-- La tarea de la API informa de su avance (cursor) y de su final.
create or replace function public.avanzar_recuperacion(
  p_id_conexion uuid,
  p_recuperado_hasta timestamptz,
  p_estado text default 'EN_CURSO',
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_estado not in ('EN_CURSO', 'COMPLETADA', 'ERROR') then
    raise exception 'Estado no válido';
  end if;

  update public.conexiones
     set recuperado_hasta = greatest(recuperado_hasta, p_recuperado_hasta),
         recuperacion_estado = p_estado,
         ultimo_error = case when p_estado = 'ERROR' then p_error else ultimo_error end
   where id = p_id_conexion;

  if p_estado in ('COMPLETADA', 'ERROR') then
    update public.importaciones i
       set estado = case when p_estado = 'ERROR' then 'CON_ERRORES'
                         when i.rechazadas > 0 then 'CON_ERRORES' else 'COMPLETADA' end
     where i.id = (select id_importacion_recuperacion from public.conexiones where id = p_id_conexion);
  end if;
end;
$$;

-- ---------------------------------------------------------
-- 5 quinquies. Vía API para empresas IoT (con el token de la conexión)
-- ---------------------------------------------------------
create or replace function private.conexion_de_token(p_token text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
  from public.conexiones c
  join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  where c.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8')), 'hex')
    and c.activo
    and tc.modo in ('ENVIO', 'PASARELA');
$$;

create or replace function public.crear_importacion_token(p_token text, p_total_lotes integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_con uuid := private.conexion_de_token(p_token);
begin
  if v_con is null then
    raise exception 'Token no válido' using errcode = '28000';
  end if;
  return public.crear_importacion(
    (select id_edificio from public.conexiones where id = v_con), 'LECTURAS', 'API', v_con, null, p_total_lotes);
end;
$$;

create or replace function public.procesar_lote_token(
  p_token text,
  p_id_importacion uuid,
  p_numero integer,
  p_lecturas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_con uuid := private.conexion_de_token(p_token);
begin
  if v_con is null then
    raise exception 'Token no válido' using errcode = '28000';
  end if;
  if not exists (select 1 from public.importaciones where id = p_id_importacion and id_conexion = v_con) then
    raise exception 'La importación no pertenece a esta conexión' using errcode = '42501';
  end if;
  return public.procesar_lote_lecturas(p_id_importacion, p_numero, p_lecturas);
end;
$$;

revoke all on function public.simular_lecturas(uuid, jsonb) from public, anon;
revoke all on function public.puede_importar(uuid) from public, anon;
grant execute on function public.puede_importar(uuid) to authenticated;
revoke all on function public.solicitar_recuperacion(uuid, date) from public, anon;
revoke all on function public.avanzar_recuperacion(uuid, timestamptz, text, text) from public, anon, authenticated;
revoke all on function private.conexion_de_token(text) from public, anon, authenticated;
revoke all on function public.crear_importacion_token(text, integer) from public, anon, authenticated;
revoke all on function public.procesar_lote_token(text, uuid, integer, jsonb) from public, anon, authenticated;
grant execute on function public.simular_lecturas(uuid, jsonb) to authenticated, service_role;
grant execute on function public.solicitar_recuperacion(uuid, date) to authenticated, service_role;
grant execute on function public.avanzar_recuperacion(uuid, timestamptz, text, text) to service_role;
grant execute on function public.crear_importacion_token(text, integer) to service_role;
grant execute on function public.procesar_lote_token(text, uuid, integer, jsonb) to service_role;

-- ---------------------------------------------------------
-- 6. Seguridad
-- ---------------------------------------------------------
alter table public.importaciones enable row level security;
alter table public.importaciones_lotes enable row level security;
alter table public.recalculos_pendientes enable row level security;

drop policy if exists importaciones_select on public.importaciones;
create policy importaciones_select on public.importaciones
for select to authenticated
using (private.usuario_puede_edificio(id_edificio, 'VER_CONEXION'));

drop policy if exists importaciones_lotes_select on public.importaciones_lotes;
create policy importaciones_lotes_select on public.importaciones_lotes
for select to authenticated
using (exists (select 1 from public.importaciones i
               where i.id = id_importacion
                 and private.usuario_puede_edificio(i.id_edificio, 'VER_CONEXION')));

drop policy if exists recalculos_select on public.recalculos_pendientes;
create policy recalculos_select on public.recalculos_pendientes
for select to authenticated
using (private.usuario_puede_edificio(id_edificio, 'VER_CONEXION'));

drop trigger if exists trg_importaciones_updated_at on public.importaciones;
create trigger trg_importaciones_updated_at
before update on public.importaciones
for each row execute function public.set_updated_at();

revoke all on function public.crear_importacion(uuid, text, text, uuid, text, integer) from public, anon;
revoke all on function public.procesar_lote_lecturas(uuid, integer, jsonb) from public, anon, authenticated;
revoke all on function public.importar_resumenes(uuid, jsonb, boolean, uuid, boolean) from public, anon;
grant execute on function public.crear_importacion(uuid, text, text, uuid, text, integer) to authenticated, service_role;
grant execute on function public.procesar_lote_lecturas(uuid, integer, jsonb) to service_role;
grant execute on function public.importar_resumenes(uuid, jsonb, boolean, uuid, boolean) to authenticated, service_role;

commit;
