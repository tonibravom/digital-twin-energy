begin;

-- =========================================================
-- PARAMETRIZACIÓN GENÉRICA DE CONECTORES Y DISPOSITIVOS
--
-- Objetivo: integrar cualquier sensor o dispositivo SIN escribir
-- código específico por edificio ni crear tablas por protocolo.
--
--   tipos_conexion  -> catálogo de protocolos, con el "esquema" de
--                      su configuración y de cómo se direcciona
--                      cada punto (JSON Schema).
--   conexiones      -> instancia concreta en un edificio
--                      (URL, host, intervalo, zona horaria...).
--   sensores        -> cada punto de medida: su dirección en el
--                      origen + transformación (escala, unidades,
--                      rango válido, valores vacíos).
--   plantillas      -> modelos de dispositivo reutilizables
--                      (p. ej. "Analizador X por Modbus"): crean
--                      el dispositivo y todos sus sensores de golpe.
--   procesar_lecturas() -> canal ÚNICO de entrada de datos para
--                      todos los conectores y para el envío HTTP.
--
-- Los secretos (contraseñas, API keys) NUNCA van en jsonb: se
-- guardan en Supabase Vault y la conexión solo guarda su id.
-- =========================================================

-- ---------------------------------------------------------
-- 1. TIPOS DE CONEXIÓN: modo de funcionamiento y esquemas
-- ---------------------------------------------------------
alter table public.tipos_conexion
  add column if not exists modo varchar(20) not null default 'CONSULTA',
  add column if not exists esquema_configuracion jsonb not null default '{"type": "object"}'::jsonb,
  add column if not exists esquema_punto jsonb not null default '{"type": "object"}'::jsonb;

alter table public.tipos_conexion drop constraint if exists tipos_conexion_modo_ck;
alter table public.tipos_conexion add constraint tipos_conexion_modo_ck
  check (modo in ('CONSULTA', 'SUSCRIPCION', 'ENVIO', 'PASARELA'));

comment on column public.tipos_conexion.modo is
  'CONSULTA: la plataforma pide los datos periódicamente (Sentilo, API REST). SUSCRIPCION: la plataforma escucha un broker (MQTT). ENVIO: el origen envía los datos a la plataforma (HTTP estándar). PASARELA: protocolos de red local (Modbus, BACnet) leídos por un equipo en el edificio que reenvía por ENVIO.';
comment on column public.tipos_conexion.esquema_configuracion is
  'JSON Schema de conexiones.configuracion para este protocolo. La interfaz genera el formulario a partir de él.';
comment on column public.tipos_conexion.esquema_punto is
  'JSON Schema de sensores.direccion: cómo se localiza un punto de medida dentro de esta conexión.';

insert into public.tipos_conexion (codigo, nombre, descripcion) values
  ('ENVIO_HTTP', 'Envío HTTP (formato estándar)',
   'El dispositivo, gateway o plataforma externa envía las lecturas a la API en el formato estándar documentado.')
on conflict (codigo) do nothing;

update public.tipos_conexion set modo = 'CONSULTA',
  esquema_configuracion = '{
    "type": "object",
    "required": ["url_base", "proveedor"],
    "properties": {
      "url_base":  {"type": "string", "title": "URL del servidor Sentilo", "examples": ["https://connectaapi.bcn.cat"]},
      "proveedor": {"type": "string", "title": "Proveedor (provider)"},
      "id_secreto_token": {"type": "string", "title": "Token (referencia en Vault)"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["sensor"],
    "properties": {
      "sensor": {"type": "string", "title": "Identificador del sensor en Sentilo"}
    }
  }'::jsonb
where codigo = 'SENTILO';

update public.tipos_conexion set modo = 'CONSULTA',
  esquema_configuracion = '{
    "type": "object",
    "required": ["url", "autenticacion", "ruta_lista", "campo_fecha"],
    "properties": {
      "url":           {"type": "string", "title": "URL del endpoint"},
      "metodo":        {"type": "string", "enum": ["GET", "POST"], "default": "GET"},
      "autenticacion": {"type": "string", "enum": ["NINGUNA", "BEARER", "API_KEY", "BASIC"]},
      "cabecera_api_key": {"type": "string", "title": "Nombre de la cabecera si autenticación = API_KEY"},
      "id_secreto":    {"type": "string", "title": "Credencial (referencia en Vault)"},
      "ruta_lista":    {"type": "string", "title": "Ruta JSON a la lista de medidas", "examples": ["$.data.items"]},
      "campo_fecha":   {"type": "string", "title": "Campo con la fecha de cada medida", "examples": ["timestamp"]},
      "formato_fecha": {"type": "string", "enum": ["ISO8601", "EPOCH_S", "EPOCH_MS"], "default": "ISO8601"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["ruta_valor"],
    "properties": {
      "ruta_valor": {"type": "string", "title": "Campo con el valor", "examples": ["energy_kwh"]},
      "filtro":     {"type": "object", "title": "Condición para elegir la medida (campo: valor)", "examples": [{"meter_id": "M-01"}]}
    }
  }'::jsonb
where codigo = 'API_REST';

update public.tipos_conexion set modo = 'SUSCRIPCION',
  esquema_configuracion = '{
    "type": "object",
    "required": ["host", "puerto"],
    "properties": {
      "host":    {"type": "string"},
      "puerto":  {"type": "integer", "default": 8883},
      "tls":     {"type": "boolean", "default": true},
      "usuario": {"type": "string"},
      "id_secreto": {"type": "string", "title": "Contraseña (referencia en Vault)"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["topic"],
    "properties": {
      "topic":      {"type": "string", "examples": ["edificio1/contador1/energia"]},
      "ruta_valor": {"type": "string", "title": "Campo del mensaje JSON con el valor (vacío si el mensaje es solo el número)"},
      "ruta_fecha": {"type": "string", "title": "Campo con la fecha (vacío = hora de recepción)"}
    }
  }'::jsonb
where codigo = 'MQTT';

update public.tipos_conexion set modo = 'PASARELA',
  esquema_configuracion = '{
    "type": "object",
    "required": ["host", "puerto", "id_unidad"],
    "properties": {
      "host":      {"type": "string", "title": "IP del equipo en la red del edificio"},
      "puerto":    {"type": "integer", "default": 502},
      "id_unidad": {"type": "integer", "default": 1, "title": "Unit ID / esclavo"},
      "orden_palabras": {"type": "string", "enum": ["BIG", "LITTLE"], "default": "BIG"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["registro", "tipo_registro", "tipo_dato"],
    "properties": {
      "registro":      {"type": "integer", "minimum": 0, "maximum": 65535},
      "tipo_registro": {"type": "string", "enum": ["HOLDING", "INPUT", "COIL", "DISCRETO"]},
      "tipo_dato":     {"type": "string", "enum": ["INT16", "UINT16", "INT32", "UINT32", "INT64", "UINT64", "FLOAT32", "FLOAT64", "BOOL"]},
      "id_unidad":     {"type": "integer", "title": "Solo si difiere del de la conexión"}
    }
  }'::jsonb
where codigo = 'MODBUS_TCP';

update public.tipos_conexion set modo = 'PASARELA',
  esquema_configuracion = '{
    "type": "object",
    "required": ["ip", "instancia_dispositivo"],
    "properties": {
      "ip":     {"type": "string"},
      "puerto": {"type": "integer", "default": 47808},
      "instancia_dispositivo": {"type": "integer"}
    }
  }'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["tipo_objeto", "instancia"],
    "properties": {
      "tipo_objeto": {"type": "string", "enum": ["analogInput", "analogValue", "analogOutput", "binaryInput", "binaryValue", "multiStateInput", "multiStateValue", "accumulator"]},
      "instancia":   {"type": "integer", "minimum": 0},
      "propiedad":   {"type": "string", "default": "presentValue"}
    }
  }'::jsonb
where codigo = 'BACNET';

update public.tipos_conexion set modo = 'ENVIO',
  esquema_configuracion = '{"type": "object", "properties": {}}'::jsonb,
  esquema_punto = '{
    "type": "object",
    "required": ["clave"],
    "properties": {
      "clave": {"type": "string", "title": "Identificador que enviará el origen en cada lectura", "examples": ["CONT-01/energia_activa"]}
    }
  }'::jsonb
where codigo in ('ENVIO_HTTP', 'IOT');

-- 'IOT' (creado en la 002) significaba lo mismo que ENVIO_HTTP: se
-- desactiva para que no haya dos opciones iguales (no se borra por
-- si alguna instalación ya lo usa).
update public.tipos_conexion
   set activo = false,
       descripcion = 'Obsoleto: use ENVIO_HTTP (formato estándar).'
 where codigo = 'IOT';

-- 'OTRA' (002): orígenes sin conector automático, p. ej. importación
-- de históricos en Excel/CSV desde la API. Puntos por clave opcional.
update public.tipos_conexion
   set modo = 'ENVIO',
       descripcion = 'Otros orígenes e importación de archivos (Excel/CSV) desde la API.',
       esquema_configuracion = '{"type": "object", "properties": {}}'::jsonb,
       esquema_punto = '{"type": "object", "properties": {"clave": {"type": "string", "title": "Nombre de la columna o identificador en el archivo"}}}'::jsonb
 where codigo = 'OTRA';

-- Valor de la última lectura de cada sensor (etiquetas 3D, paneles).
alter table public.estado_comunicacion
  add column if not exists ultimo_valor double precision;
comment on column public.estado_comunicacion.ultimo_valor is
  'Valor (ya transformado) de la lectura más reciente. Lo actualiza procesar_lecturas.';

-- ---------------------------------------------------------
-- 2. CONEXIONES: parámetros de funcionamiento y diagnóstico
-- ---------------------------------------------------------
alter table public.conexiones
  add column if not exists intervalo_segundos integer not null default 900,
  add column if not exists zona_horaria_origen text not null default 'UTC',
  add column if not exists token_hash text,
  add column if not exists ultima_ejecucion timestamptz,
  add column if not exists ultimo_ok timestamptz,
  add column if not exists ultimo_error text;

alter table public.conexiones drop constraint if exists conexiones_intervalo_ck;
alter table public.conexiones add constraint conexiones_intervalo_ck
  check (intervalo_segundos between 10 and 86400);

create unique index if not exists ux_conexiones_token
  on public.conexiones(token_hash) where token_hash is not null;

comment on column public.conexiones.zona_horaria_origen is
  'Zona horaria en la que el origen expresa fechas SIN zona (p. ej. "2026-10-21 10:15"). Las fechas con zona o en UTC no se ven afectadas.';
comment on column public.conexiones.token_hash is
  'SHA-256 del token de envío (modo ENVIO). El token en claro solo se muestra una vez al generarlo.';

-- ---------------------------------------------------------
-- 3. SENSORES: dirección en el origen y transformación
-- ---------------------------------------------------------
alter table public.sensores
  add column if not exists direccion jsonb not null default '{}'::jsonb,
  add column if not exists unidad_origen varchar(30),
  add column if not exists escala double precision not null default 1,
  add column if not exists desplazamiento double precision not null default 0,
  add column if not exists valor_minimo double precision,
  add column if not exists valor_maximo double precision,
  add column if not exists politica_vacios varchar(20) not null default 'DESCARTAR';

alter table public.sensores drop constraint if exists sensores_direccion_ck;
alter table public.sensores add constraint sensores_direccion_ck
  check (jsonb_typeof(direccion) = 'object');
alter table public.sensores drop constraint if exists sensores_rango_ck;
alter table public.sensores add constraint sensores_rango_ck
  check (valor_minimo is null or valor_maximo is null or valor_minimo <= valor_maximo);
alter table public.sensores drop constraint if exists sensores_escala_ck;
alter table public.sensores add constraint sensores_escala_ck check (escala <> 0);
alter table public.sensores drop constraint if exists sensores_vacios_ck;
alter table public.sensores add constraint sensores_vacios_ck
  check (politica_vacios in ('DESCARTAR', 'CERO', 'MANTENER_ULTIMO'));

comment on column public.sensores.magnitud_origen is
  'Solo descriptivo: nombre de la variable tal como la llama el origen (p. ej. "Active energy import"). La localización real del punto está en "direccion".';
comment on column public.sensores.direccion is
  'Localización del punto en su conexión, según tipos_conexion.esquema_punto. Vacía = sensor sin mapear (no recibe datos).';
comment on column public.sensores.escala is
  'valor_guardado = valor_origen × escala + desplazamiento. Ej.: Wh → kWh, escala 0.001.';
comment on column public.sensores.politica_vacios is
  'Qué hacer si llega una lectura sin valor: DESCARTAR, CERO o MANTENER_ULTIMO. Se define por sensor/origen (maestro §8).';

-- Conexión efectiva de un sensor (directa o la de su dispositivo).
create or replace function public.conexion_de_sensor(p_id_sensor uuid)
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(s.id_conexion, d.id_conexion)
  from public.sensores s
  left join public.dispositivos d on d.id = s.id_dispositivo
  where s.id = p_id_sensor;
$$;

-- Comprueba que un objeto jsonb tiene las claves "required" de un esquema.
-- (Validación completa del JSON Schema en la API; aquí el mínimo
-- imprescindible para que la base de datos nunca quede incoherente.)
create or replace function public.faltan_claves(p_objeto jsonb, p_esquema jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(r), '{}')
  from pg_catalog.jsonb_array_elements_text(coalesce(p_esquema->'required', '[]'::jsonb)) r
  where not (p_objeto ? r) or p_objeto->>r is null or p_objeto->>r = '';
$$;

create or replace function public.validar_configuracion_conexion()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_esquema jsonb;
  v_faltan text[];
  v_clave text;
begin
  select tc.esquema_configuracion into v_esquema
  from public.tipos_conexion tc where tc.id = new.id_tipo_conexion;

  v_faltan := public.faltan_claves(new.configuracion, v_esquema);
  if pg_catalog.array_length(v_faltan, 1) > 0 then
    raise exception 'Faltan parámetros obligatorios de la conexión: %',
      pg_catalog.array_to_string(v_faltan, ', ');
  end if;

  -- Ningún secreto en claro dentro de la configuración.
  for v_clave in select pg_catalog.jsonb_object_keys(new.configuracion) loop
    if v_clave ~* '(password|contrasena|contraseña|secret|apikey|api_key|^token$|clave_api)' then
      raise exception 'La configuración no puede contener secretos (%). Guárdelo en Supabase Vault y use id_secreto.', v_clave;
    end if;
  end loop;

  if not exists (
    select 1 from pg_catalog.pg_timezone_names where name = new.zona_horaria_origen
  ) then
    raise exception 'Zona horaria no válida: %', new.zona_horaria_origen;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conexiones_validar_configuracion on public.conexiones;
create trigger trg_conexiones_validar_configuracion
before insert or update of id_tipo_conexion, configuracion, zona_horaria_origen
on public.conexiones
for each row execute function public.validar_configuracion_conexion();

create or replace function public.validar_direccion_sensor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_conexion uuid;
  v_esquema jsonb;
  v_faltan text[];
begin
  if new.direccion = '{}'::jsonb then
    return new;  -- sensor sin mapear (calculado, manual o pendiente)
  end if;

  v_conexion := coalesce(
    new.id_conexion,
    (select d.id_conexion from public.dispositivos d where d.id = new.id_dispositivo)
  );

  select tc.esquema_punto into v_esquema
  from public.conexiones c
  join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  where c.id = v_conexion;

  v_faltan := public.faltan_claves(new.direccion, v_esquema);
  if pg_catalog.array_length(v_faltan, 1) > 0 then
    raise exception 'Faltan datos de la dirección del sensor: %',
      pg_catalog.array_to_string(v_faltan, ', ');
  end if;

  if new.activo and exists (
    select 1
    from public.sensores s
    left join public.dispositivos d on d.id = s.id_dispositivo
    where s.id <> new.id
      and s.activo
      and coalesce(s.id_conexion, d.id_conexion) = v_conexion
      and s.direccion = new.direccion
  ) then
    raise exception 'Ya existe otro sensor activo con esa misma dirección en la conexión';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sensores_validar_direccion on public.sensores;
create trigger trg_sensores_validar_direccion
before insert or update of direccion, id_conexion, id_dispositivo, activo
on public.sensores
for each row execute function public.validar_direccion_sensor();

create index if not exists ix_sensores_direccion_clave
  on public.sensores ((direccion->>'clave'))
  where direccion ? 'clave';

-- ---------------------------------------------------------
-- 4. PLANTILLAS DE DISPOSITIVO
-- Globales (id_proveedor nulo, las mantiene el administrador)
-- o privadas de un Partner (p. ej. una empresa IoT con sus
-- propios equipos).
-- ---------------------------------------------------------
create table if not exists public.plantillas_dispositivo (
  id uuid primary key default gen_random_uuid(),
  id_proveedor uuid references public.proveedores(id) on delete restrict,
  codigo varchar(80) not null,
  nombre varchar(200) not null,
  fabricante varchar(120),
  modelo varchar(120),
  id_tipo_dispositivo smallint not null references public.tipos_dispositivo(id) on delete restrict,
  id_tipo_conexion smallint not null references public.tipos_conexion(id) on delete restrict,
  descripcion text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ux_plantillas_codigo_global
  on public.plantillas_dispositivo(codigo) where id_proveedor is null;
create unique index if not exists ux_plantillas_codigo_partner
  on public.plantillas_dispositivo(id_proveedor, codigo) where id_proveedor is not null;

create table if not exists public.plantillas_puntos (
  id uuid primary key default gen_random_uuid(),
  id_plantilla uuid not null references public.plantillas_dispositivo(id) on delete restrict,
  codigo varchar(100) not null,
  nombre varchar(200) not null,
  direccion jsonb not null default '{}'::jsonb,
  unidad varchar(30) not null,
  unidad_origen varchar(30),
  escala double precision not null default 1,
  desplazamiento double precision not null default 0,
  valor_minimo double precision,
  valor_maximo double precision,
  politica_vacios varchar(20) not null default 'DESCARTAR',
  id_familia smallint not null references public.familias_sensor(id) on delete restrict,
  id_naturaleza smallint not null references public.naturalezas_sensor(id) on delete restrict,
  id_tratamiento smallint not null references public.tratamientos_sensor(id) on delete restrict,
  id_tipo_energia smallint references public.tipos_energia(id) on delete restrict,
  id_flujo_energia smallint references public.flujos_energia(id) on delete restrict,
  orden integer not null default 1,
  created_at timestamptz not null default now(),
  constraint plantillas_puntos_codigo_uq unique (id_plantilla, codigo),
  constraint plantillas_puntos_direccion_ck check (jsonb_typeof(direccion) = 'object'),
  constraint plantillas_puntos_escala_ck check (escala <> 0),
  constraint plantillas_puntos_vacios_ck
    check (politica_vacios in ('DESCARTAR', 'CERO', 'MANTENER_ULTIMO'))
);

alter table public.dispositivos
  add column if not exists id_plantilla uuid references public.plantillas_dispositivo(id) on delete restrict;

drop trigger if exists trg_plantillas_dispositivo_updated_at on public.plantillas_dispositivo;
create trigger trg_plantillas_dispositivo_updated_at
before update on public.plantillas_dispositivo
for each row execute function public.set_updated_at();

alter table public.plantillas_dispositivo enable row level security;
alter table public.plantillas_puntos enable row level security;

-- Permiso nuevo
insert into public.permisos (codigo, nombre, modulo) values
  ('GESTIONAR_PLANTILLAS', 'Gestionar plantillas de dispositivo', 'CONFIGURACION')
on conflict (codigo) do nothing;

insert into public.roles_permisos (id_rol, id_permiso)
select r.id, p.id
from public.roles r, public.permisos p
where r.codigo in ('ADMIN_SAAS', 'ADMIN_PARTNER', 'TECNICO_PARTNER')
  and p.codigo = 'GESTIONAR_PLANTILLAS'
on conflict do nothing;

-- ¿Es el usuario actual MASTER activo de ese partner?
create or replace function private.usuario_es_del_partner(p_id_proveedor uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios_partners up
    where up.id_usuario = private.usuario_actual()
      and up.id_proveedor = p_id_proveedor
      and up.activo
  );
$$;

revoke all on function private.usuario_es_del_partner(uuid) from public, anon;
grant execute on function private.usuario_es_del_partner(uuid) to authenticated;

drop policy if exists plantillas_select on public.plantillas_dispositivo;
create policy plantillas_select on public.plantillas_dispositivo
for select to authenticated
using (
  id_proveedor is null
  or private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_es_del_partner(id_proveedor)
);

drop policy if exists plantillas_insert on public.plantillas_dispositivo;
create policy plantillas_insert on public.plantillas_dispositivo
for insert to authenticated
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    id_proveedor is not null
    and private.usuario_tiene_permiso('GESTIONAR_PLANTILLAS')
    and private.usuario_es_del_partner(id_proveedor)
  )
);

drop policy if exists plantillas_update on public.plantillas_dispositivo;
create policy plantillas_update on public.plantillas_dispositivo
for update to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    id_proveedor is not null
    and private.usuario_tiene_permiso('GESTIONAR_PLANTILLAS')
    and private.usuario_es_del_partner(id_proveedor)
  )
)
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    id_proveedor is not null
    and private.usuario_tiene_permiso('GESTIONAR_PLANTILLAS')
    and private.usuario_es_del_partner(id_proveedor)
  )
);

drop policy if exists plantillas_puntos_select on public.plantillas_puntos;
create policy plantillas_puntos_select on public.plantillas_puntos
for select to authenticated
using (exists (select 1 from public.plantillas_dispositivo p where p.id = id_plantilla));

drop policy if exists plantillas_puntos_insert on public.plantillas_puntos;
create policy plantillas_puntos_insert on public.plantillas_puntos
for insert to authenticated
with check (exists (
  select 1 from public.plantillas_dispositivo p
  where p.id = id_plantilla
    and (
      private.usuario_tiene_rol('ADMIN_SAAS')
      or (p.id_proveedor is not null
          and private.usuario_tiene_permiso('GESTIONAR_PLANTILLAS')
          and private.usuario_es_del_partner(p.id_proveedor))
    )
));

drop policy if exists plantillas_puntos_update on public.plantillas_puntos;
create policy plantillas_puntos_update on public.plantillas_puntos
for update to authenticated
using (exists (
  select 1 from public.plantillas_dispositivo p
  where p.id = id_plantilla
    and (
      private.usuario_tiene_rol('ADMIN_SAAS')
      or (p.id_proveedor is not null
          and private.usuario_tiene_permiso('GESTIONAR_PLANTILLAS')
          and private.usuario_es_del_partner(p.id_proveedor))
    )
));

-- Crea un dispositivo y todos sus sensores a partir de una plantilla.
-- Se ejecuta con los permisos del usuario (RLS aplica): necesita
-- CREAR_DISPOSITIVO y CREAR_SENSOR en el edificio.
-- p_direccion_base se añade a la dirección de cada punto
-- (p. ej. {"id_unidad": 3} en Modbus). En puntos con "clave"
-- (envío HTTP), la clave se prefija con el código del dispositivo.
create or replace function public.crear_dispositivo_desde_plantilla(
  p_id_plantilla uuid,
  p_id_recinto uuid,
  p_id_conexion uuid,
  p_codigo varchar,
  p_nombre varchar,
  p_numero_serie varchar default null,
  p_direccion_base jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_plantilla public.plantillas_dispositivo%rowtype;
  v_tipo_conexion smallint;
  v_dispositivo uuid;
begin
  select * into v_plantilla
  from public.plantillas_dispositivo
  where id = p_id_plantilla and activo;

  if not found then
    raise exception 'La plantilla no existe, no está activa o no es accesible';
  end if;

  select c.id_tipo_conexion into v_tipo_conexion
  from public.conexiones c where c.id = p_id_conexion;

  if v_tipo_conexion is distinct from v_plantilla.id_tipo_conexion then
    raise exception 'La conexión no es del tipo que requiere la plantilla';
  end if;

  insert into public.dispositivos (
    id_recinto, id_conexion, id_tipo_dispositivo, id_plantilla,
    codigo, nombre, fabricante, modelo, numero_serie
  )
  values (
    p_id_recinto, p_id_conexion, v_plantilla.id_tipo_dispositivo, v_plantilla.id,
    p_codigo, p_nombre, v_plantilla.fabricante, v_plantilla.modelo, p_numero_serie
  )
  returning id into v_dispositivo;

  insert into public.sensores (
    id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento,
    id_tipo_energia, id_flujo_energia, codigo, nombre, unidad, unidad_origen,
    escala, desplazamiento, valor_minimo, valor_maximo, politica_vacios, direccion
  )
  select
    v_dispositivo, p_id_recinto, pp.id_familia, pp.id_naturaleza, pp.id_tratamiento,
    pp.id_tipo_energia, pp.id_flujo_energia,
    p_codigo || '.' || pp.codigo, pp.nombre, pp.unidad, pp.unidad_origen,
    pp.escala, pp.desplazamiento, pp.valor_minimo, pp.valor_maximo, pp.politica_vacios,
    case
      when pp.direccion ? 'clave'
        then (pp.direccion || coalesce(p_direccion_base, '{}'::jsonb))
             || pg_catalog.jsonb_build_object('clave', p_codigo || '/' || (pp.direccion->>'clave'))
      else pp.direccion || coalesce(p_direccion_base, '{}'::jsonb)
    end
  from public.plantillas_puntos pp
  where pp.id_plantilla = v_plantilla.id
  order by pp.orden, pp.codigo;

  return v_dispositivo;
end;
$$;

revoke all on function public.crear_dispositivo_desde_plantilla(uuid, uuid, uuid, varchar, varchar, varchar, jsonb) from public, anon;
grant execute on function public.crear_dispositivo_desde_plantilla(uuid, uuid, uuid, varchar, varchar, varchar, jsonb) to authenticated;

-- Valor numérico vigente de un parámetro de la plataforma (011).
create or replace function public.parametro_numerico(p_codigo text, p_defecto numeric)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select ps.valor_numerico from public.parametros_saas ps
     where ps.codigo = p_codigo and ps.activo limit 1),
    p_defecto);
$$;

-- ---------------------------------------------------------
-- 5. CANAL ÚNICO DE ENTRADA DE LECTURAS
-- Todos los conectores (Sentilo, REST, MQTT, pasarelas, envío
-- HTTP) entregan aquí las lecturas en el formato estándar:
--   [ {"clave": "CONT-01/energia", "fecha_hora": "2026-10-21T10:15:00Z", "valor": 1234.5},
--     {"id_sensor": "<uuid>",      "fecha_hora": "2026-10-21 12:15",     "valor": 21.3} ]
-- Se aplica: identificación del punto, fecha (con o sin zona),
-- política de vacíos, escala/desplazamiento, rango válido,
-- deduplicación y estado de comunicación.
-- Solo lo ejecuta la API (service_role).
-- ---------------------------------------------------------
create or replace function private.fecha_segura(p_texto text, p_zona text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_texto is null or pg_catalog.btrim(p_texto) = '' then
    return null;
  end if;
  if p_texto ~ '^\d{9,13}$' then
    -- epoch en segundos (≤10 dígitos) o milisegundos
    return pg_catalog.to_timestamp(
      case when pg_catalog.length(p_texto) > 10 then p_texto::numeric / 1000 else p_texto::numeric end);
  end if;
  if p_texto ~* '(z|[+-]\d{2}(:?\d{2})?)$' then
    return p_texto::timestamptz;
  end if;
  return p_texto::timestamp at time zone p_zona;
exception when others then
  return null;
end;
$$;

create or replace function public.procesar_lecturas(
  p_id_conexion uuid,
  p_lecturas jsonb,
  p_historico boolean default false,
  p_simular boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conexion public.conexiones%rowtype;
  v_limite timestamptz := public.limite_retencion_lecturas();
  v_recibidas integer;
  v_guardadas integer := 0;
  v_rechazos jsonb;
  v_rechazadas integer;
  v_desde timestamptz;
  v_hasta timestamptz;
begin
  -- p_historico = true: carga de datos pasados (importaciones). Guarda
  -- las lecturas pero NO toca el estado de comunicación, las
  -- incidencias ni el estado de prueba de los sensores.
  -- p_simular = true: valida y cuenta SIN guardar nada (vista previa
  -- de una importación), con estadísticas por sensor.
  select * into v_conexion from public.conexiones where id = p_id_conexion;

  if not found or not v_conexion.activo then
    raise exception 'Conexión inexistente o inactiva';
  end if;

  if p_lecturas is null or jsonb_typeof(p_lecturas) <> 'array' then
    raise exception 'Se esperaba una lista de lecturas';
  end if;

  v_recibidas := pg_catalog.jsonb_array_length(p_lecturas);
  if v_recibidas > 50000 then
    raise exception 'Máximo 50.000 lecturas por envío (recibidas %)', v_recibidas;
  end if;

  if pg_catalog.to_regclass('pg_temp._lote') is null then
    create temporary table _lote (
      ord integer, id_sensor uuid, fecha timestamptz, valor double precision,
      calidad smallint, rellenar boolean, motivo text
    ) on commit drop;
  else
    truncate _lote;
  end if;

  insert into _lote (ord, id_sensor, fecha, valor, calidad, rellenar, motivo)
  with entrada as (
    select e.ord::integer, e.item
    from pg_catalog.jsonb_array_elements(p_lecturas) with ordinality as e(item, ord)
  ),
  puntos as (
    select s.id, s.direccion->>'clave' as clave, s.escala, s.desplazamiento,
           s.valor_minimo, s.valor_maximo, s.politica_vacios
    from public.sensores s
    left join public.dispositivos d on d.id = s.id_dispositivo
    where s.activo
      and coalesce(s.id_conexion, d.id_conexion) = p_id_conexion
  ),
  resueltas as (
    select en.ord, p.id as id_sensor, p.escala, p.desplazamiento,
           p.valor_minimo, p.valor_maximo, p.politica_vacios,
           private.fecha_segura(en.item->>'fecha_hora', v_conexion.zona_horaria_origen) as fecha,
           case
             when pg_catalog.jsonb_typeof(en.item->'valor') = 'number' then (en.item->>'valor')::double precision
             when pg_catalog.jsonb_typeof(en.item->'valor') = 'boolean' then case when (en.item->>'valor')::boolean then 1 else 0 end
             when pg_catalog.jsonb_typeof(en.item->'valor') = 'string'
                  and en.item->>'valor' ~ '^\s*-?\d+([.,]\d+)?\s*$'
               then pg_catalog.replace(pg_catalog.btrim(en.item->>'valor'), ',', '.')::double precision
           end as valor_origen,
           (en.item->'valor' is null or pg_catalog.jsonb_typeof(en.item->'valor') = 'null'
            or (pg_catalog.jsonb_typeof(en.item->'valor') = 'string' and pg_catalog.btrim(en.item->>'valor') = '')) as vacio,
           -- calidad opcional: 0/1/2 o VALIDA/ESTIMADA/CORREGIDA
           case pg_catalog.upper(coalesce(en.item->>'calidad', '0'))
             when '1' then 1 when 'ESTIMADA' then 1
             when '2' then 2 when 'CORREGIDA' then 2
             else 0 end::smallint as calidad
    from entrada en
    left join puntos p
      on case when en.item ? 'id_sensor' then p.id::text = en.item->>'id_sensor'
              else p.clave = en.item->>'clave' end
  )
  select r.ord, r.id_sensor, r.fecha,
         case
           when r.vacio and r.politica_vacios = 'CERO' then 0
           when r.vacio then null
           else r.valor_origen * r.escala + r.desplazamiento
         end,
         case when r.vacio and r.politica_vacios = 'MANTENER_ULTIMO' then 1::smallint else r.calidad end,
         (r.vacio and r.politica_vacios = 'MANTENER_ULTIMO'),
         case
           when r.id_sensor is null then 'punto desconocido en esta conexión'
           when r.fecha is null then 'fecha no válida'
           when r.fecha < v_limite then 'anterior al límite de retención de lecturas: importe ese periodo como resumen diario o mensual'
           when r.fecha > pg_catalog.now() + interval '1 day' then 'fecha futura'
           when r.vacio and r.politica_vacios = 'DESCARTAR' then 'valor vacío (descartado)'
           when not r.vacio and r.valor_origen is null then 'valor no numérico'
         end
  from resueltas r;

  -- Rango válido (sobre el valor ya transformado)
  update _lote l set motivo = 'valor fuera del rango válido'
  from public.sensores s
  where l.motivo is null and s.id = l.id_sensor
    and ((s.valor_minimo is not null and l.valor < s.valor_minimo)
      or (s.valor_maximo is not null and l.valor > s.valor_maximo));

  -- Vacíos con MANTENER_ULTIMO: última lectura válida anterior, del
  -- propio envío o, si no hay, de las ya guardadas.
  update _lote l
     set valor = coalesce(
       (select b.valor from _lote b
        where b.id_sensor = l.id_sensor and b.fecha < l.fecha
          and b.motivo is null and not b.rellenar and b.valor is not null
        order by b.fecha desc limit 1),
       (select x.valor from public.lecturas x
        where x.id_sensor = l.id_sensor and x.fecha_hora < l.fecha
        order by x.fecha_hora desc limit 1))
   where l.rellenar and l.motivo is null;

  update _lote set motivo = 'valor vacío sin lectura anterior'
  where motivo is null and valor is null;

  if p_simular then
    select count(*) into v_rechazadas from _lote where motivo is not null;

    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('posicion', ord, 'motivo', motivo) order by ord), '[]'::jsonb)
      into v_rechazos
    from (select ord, motivo from _lote where motivo is not null order by ord limit 50) t;

    -- Nuevas = válidas, sin repetir dentro del envío y que no existan ya.
    select count(*), min(fecha), max(fecha) into v_guardadas, v_desde, v_hasta
    from (select distinct id_sensor, fecha from _lote where motivo is null) l
    where not exists (select 1 from public.lecturas x
                      where x.id_sensor = l.id_sensor and x.fecha_hora = l.fecha);

    return pg_catalog.jsonb_build_object(
      'simulacion', true,
      'desde', v_desde,
      'hasta', v_hasta,
      'recibidas', v_recibidas,
      'nuevas', v_guardadas,
      'duplicadas', v_recibidas - v_rechazadas - v_guardadas,
      'rechazadas', v_rechazadas,
      'detalle_rechazos', v_rechazos,
      'por_sensor', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) order by x.codigo)
        from (
          select l.id_sensor, s.codigo, s.unidad, count(*) as lecturas,
                 min(l.valor) as minimo, max(l.valor) as maximo,
                 round(avg(l.valor)::numeric, 4) as media, min(l.fecha) as desde, max(l.fecha) as hasta
          from _lote l join public.sensores s on s.id = l.id_sensor
          where l.motivo is null
          group by l.id_sensor, s.codigo, s.unidad
        ) x), '[]'::jsonb)
    );
  end if;

  with ins as (
    insert into public.lecturas (id_sensor, fecha_hora, valor, calidad)
    select id_sensor, fecha, valor, calidad from _lote where motivo is null
    on conflict (id_sensor, fecha_hora) do nothing
    returning id_sensor, fecha_hora, valor
  ),
  -- Lectura más reciente de cada sensor en este envío
  ultimas as (
    select distinct on (id_sensor) id_sensor, fecha_hora, valor
    from ins
    order by id_sensor, fecha_hora desc
  ),
  estado as (
    insert into public.estado_comunicacion (id_sensor, estado, ultima_lectura, ultimo_valor, fecha_cambio_estado, umbral_minutos)
    select id_sensor, 'COMUNICANDO', fecha_hora, valor, pg_catalog.now(),
           least(greatest(public.parametro_numerico('COMUNICACION_UMBRAL_MINUTOS', 30), 15), 120)::integer
    from ultimas
    where not p_historico
    on conflict (id_sensor) do update
      set ultimo_valor = case
            when public.estado_comunicacion.ultima_lectura is null
              or excluded.ultima_lectura >= public.estado_comunicacion.ultima_lectura
            then excluded.ultimo_valor else public.estado_comunicacion.ultimo_valor end,
          ultima_lectura = greatest(public.estado_comunicacion.ultima_lectura, excluded.ultima_lectura),
          fecha_cambio_estado = case when public.estado_comunicacion.estado <> 'COMUNICANDO'
                                     then pg_catalog.now() else public.estado_comunicacion.fecha_cambio_estado end,
          estado = 'COMUNICANDO'
    returning 1
  ),
  -- La primera lectura real confirma la configuración del sensor.
  confirmados as (
    update public.sensores s
       set estado_configuracion = 'PROBADO', fecha_ultima_prueba = pg_catalog.now()
     where s.id in (select id_sensor from ins)
       and s.estado_configuracion <> 'PROBADO'
       and not p_historico
    returning 1
  ),
  -- Si el sensor tenía una incidencia de comunicación abierta (009), se cierra.
  incidencias as (
    update public.incidencias_comunicacion ic
       set estado = 'CERRADA', fecha_fin = pg_catalog.now()
     where ic.estado = 'ABIERTA'
       and ic.id_sensor in (select id_sensor from ins)
       and not p_historico
    returning 1
  )
  select count(*), min(fecha_hora), max(fecha_hora) into v_guardadas, v_desde, v_hasta from ins;

  select count(*) into v_rechazadas from _lote where motivo is not null;

  -- Detalle de los 50 primeros rechazos (posición en la lista recibida).
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('posicion', ord, 'motivo', motivo) order by ord), '[]'::jsonb)
    into v_rechazos
  from (select ord, motivo from _lote where motivo is not null order by ord limit 50) t;

  if not p_historico then
    update public.conexiones
       set ultima_ejecucion = pg_catalog.now(),
           ultimo_ok = case when v_rechazadas < v_recibidas then pg_catalog.now() else ultimo_ok end,
           ultimo_error = case when v_rechazadas > 0 then v_rechazadas || ' lecturas rechazadas en el último envío' end
     where id = p_id_conexion;
  end if;

  return pg_catalog.jsonb_build_object(
    'historico', p_historico,
    'desde', v_desde,
    'hasta', v_hasta,
    'recibidas', v_recibidas,
    'guardadas', v_guardadas,
    'duplicadas', v_recibidas - v_rechazadas - v_guardadas,
    'rechazadas', v_rechazadas,
    'detalle_rechazos', v_rechazos
  );
end;
$$;

-- Entrada por token (modo ENVIO): la API recibe el POST y llama aquí.
create or replace function public.procesar_lecturas_token(
  p_token text,
  p_lecturas jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conexion uuid;
begin
  select c.id into v_conexion
  from public.conexiones c
  join public.tipos_conexion tc on tc.id = c.id_tipo_conexion
  where c.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token, 'UTF8')), 'hex')
    and c.activo
    and tc.modo in ('ENVIO', 'PASARELA');

  if v_conexion is null then
    raise exception 'Token no válido' using errcode = '28000';
  end if;

  return public.procesar_lecturas(v_conexion, p_lecturas);
end;
$$;

-- Genera (o renueva) el token de envío de una conexión. Devuelve el
-- token en claro UNA sola vez; en la base de datos solo queda su hash.
create or replace function public.generar_token_conexion(p_id_conexion uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_token text;
begin
  select c.id_edificio into v_edificio from public.conexiones c where c.id = p_id_conexion;

  if v_edificio is null then
    raise exception 'La conexión no existe';
  end if;

  if auth.uid() is not null
     and not private.usuario_puede_edificio(v_edificio, 'MODIFICAR_CONEXION') then
    raise exception 'Sin permiso para gestionar esta conexión' using errcode = '42501';
  end if;

  v_token := 'dte_' || pg_catalog.replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  update public.conexiones
     set token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_token, 'UTF8')), 'hex')
   where id = p_id_conexion;

  return v_token;
end;
$$;

-- Marca SIN_COMUNICACION los sensores que superan su umbral sin
-- lecturas y abre su incidencia (009). La API notifica al Partner
-- las incidencias nuevas. Se programa cada 15 minutos.
create or replace function public.revisar_comunicacion()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nuevas integer;
begin
  with caidos as (
    update public.estado_comunicacion e
       set estado = 'SIN_COMUNICACION',
           fecha_cambio_estado = pg_catalog.now()
      from public.sensores s
     where s.id = e.id_sensor
       and s.activo
       and e.estado = 'COMUNICANDO'
       and coalesce(e.ultima_lectura, e.fecha_cambio_estado)
           < pg_catalog.now() - pg_catalog.make_interval(mins => e.umbral_minutos)
    returning e.id_sensor, coalesce(e.ultima_lectura, pg_catalog.now()) as desde
  ),
  abiertas as (
    insert into public.incidencias_comunicacion (id_sensor, fecha_inicio)
    select id_sensor, desde from caidos
    on conflict do nothing
    returning 1
  )
  select count(*) into v_nuevas from abiertas;

  return v_nuevas;
end;
$$;

revoke all on function public.revisar_comunicacion() from public, anon, authenticated;
grant execute on function public.revisar_comunicacion() to service_role;
revoke all on function public.parametro_numerico(text, numeric) from public, anon;

revoke all on function private.fecha_segura(text, text) from public, anon, authenticated;
revoke all on function public.procesar_lecturas(uuid, jsonb, boolean, boolean) from public, anon, authenticated;
revoke all on function public.procesar_lecturas_token(text, jsonb) from public, anon, authenticated;
grant execute on function public.procesar_lecturas(uuid, jsonb, boolean, boolean) to service_role;
grant execute on function public.procesar_lecturas_token(text, jsonb) to service_role;
revoke all on function public.generar_token_conexion(uuid) from public, anon;
grant execute on function public.generar_token_conexion(uuid) to authenticated, service_role;
revoke all on function public.faltan_claves(jsonb, jsonb) from public, anon;
revoke all on function public.conexion_de_sensor(uuid) from public, anon;

-- ---------------------------------------------------------
-- 5 bis. ASISTENTE DE CONFIGURACIÓN DEL PARTNER
-- Flujo: ubicación → conexión → dispositivo/puntos → PRUEBA DE
-- LECTURA → magnitud que alimenta → posición 3D → cierre de la
-- parametrización del edificio. Ver docs/configuracion-partner.md
-- ---------------------------------------------------------

-- Coordenadas copiadas de una versión anterior del GLB, pendientes de revisar
alter table public.ubicaciones_3d
  add column if not exists por_revisar boolean not null default false;
comment on column public.ubicaciones_3d.por_revisar is
  'true si la coordenada se copió de la versión anterior del modelo y aún no se ha confirmado sobre el GLB nuevo.';

-- Estado de configuración de cada sensor
alter table public.sensores
  add column if not exists estado_configuracion varchar(20) not null default 'PENDIENTE',
  add column if not exists fecha_ultima_prueba timestamptz;

alter table public.sensores drop constraint if exists sensores_estado_configuracion_ck;
alter table public.sensores add constraint sensores_estado_configuracion_ck
  check (estado_configuracion in ('PENDIENTE', 'PROBADO', 'ERROR'));

comment on column public.sensores.estado_configuracion is
  'PENDIENTE: sin probar o cambiado desde la última prueba. PROBADO: una prueba de lectura o una lectura real lo confirmó. ERROR: la última prueba falló.';

-- Si cambia cómo se lee el punto, la prueba anterior deja de valer.
create or replace function public.invalidar_prueba_sensor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.direccion, new.escala, new.desplazamiento, new.id_conexion, new.id_dispositivo,
      new.valor_minimo, new.valor_maximo)
     is distinct from
     (old.direccion, old.escala, old.desplazamiento, old.id_conexion, old.id_dispositivo,
      old.valor_minimo, old.valor_maximo)
     and new.estado_configuracion is not distinct from old.estado_configuracion then
    new.estado_configuracion := 'PENDIENTE';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sensores_invalidar_prueba on public.sensores;
create trigger trg_sensores_invalidar_prueba
before update on public.sensores
for each row execute function public.invalidar_prueba_sensor();

-- Historial de pruebas de lectura hechas desde el asistente.
create table if not exists public.pruebas_lectura (
  id uuid primary key default gen_random_uuid(),
  id_conexion uuid not null references public.conexiones(id) on delete restrict,
  id_sensor uuid references public.sensores(id) on delete restrict,
  id_usuario uuid references public.usuarios(id) on delete set null,
  fecha timestamptz not null default now(),
  correcto boolean not null,
  valor_origen double precision,
  valor_transformado double precision,
  fecha_lectura timestamptz,
  mensaje text,
  detalle jsonb not null default '{}'::jsonb,
  constraint pruebas_lectura_detalle_ck check (jsonb_typeof(detalle) = 'object')
);

create index if not exists ix_pruebas_lectura_sensor
  on public.pruebas_lectura(id_sensor, fecha desc);
create index if not exists ix_pruebas_lectura_conexion
  on public.pruebas_lectura(id_conexion, fecha desc);

alter table public.pruebas_lectura enable row level security;

drop policy if exists pruebas_lectura_select on public.pruebas_lectura;
create policy pruebas_lectura_select on public.pruebas_lectura
for select to authenticated
using (
  private.usuario_puede_edificio(private.edificio_de_conexion(id_conexion), 'VER_CONEXION')
);

comment on table public.pruebas_lectura is
  'Pruebas de lectura lanzadas desde el asistente de configuración. Las escribe la API (service_role) tras leer el punto en el origen.';

-- Vista previa de la transformación de un sensor (para el asistente).
create or replace function public.transformar_valor(p_id_sensor uuid, p_valor double precision)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'valor_origen', p_valor,
    'unidad_origen', coalesce(s.unidad_origen, s.unidad),
    'valor_transformado', p_valor * s.escala + s.desplazamiento,
    'unidad', s.unidad,
    'dentro_de_rango',
      (s.valor_minimo is null or p_valor * s.escala + s.desplazamiento >= s.valor_minimo)
      and (s.valor_maximo is null or p_valor * s.escala + s.desplazamiento <= s.valor_maximo)
  )
  from public.sensores s
  where s.id = p_id_sensor;
$$;

revoke all on function public.transformar_valor(uuid, double precision) from public, anon;
grant execute on function public.transformar_valor(uuid, double precision) to authenticated, service_role;

-- La API registra aquí el resultado de una prueba de lectura.
create or replace function public.registrar_prueba_lectura(
  p_id_conexion uuid,
  p_id_sensor uuid,
  p_correcto boolean,
  p_valor_origen double precision default null,
  p_fecha_lectura timestamptz default null,
  p_mensaje text default null,
  p_detalle jsonb default '{}'::jsonb,
  p_id_usuario uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transformacion jsonb;
  v_correcto boolean := p_correcto;
  v_mensaje text := p_mensaje;
begin
  if p_id_sensor is not null
     and public.conexion_de_sensor(p_id_sensor) is distinct from p_id_conexion then
    raise exception 'El sensor no pertenece a esa conexión';
  end if;

  if p_id_sensor is not null and p_valor_origen is not null then
    v_transformacion := public.transformar_valor(p_id_sensor, p_valor_origen);
    if v_correcto and not (v_transformacion->>'dentro_de_rango')::boolean then
      v_correcto := false;
      v_mensaje := coalesce(v_mensaje || '. ', '') || 'Valor leído fuera del rango válido configurado';
    end if;
  end if;

  insert into public.pruebas_lectura (
    id_conexion, id_sensor, id_usuario, correcto, valor_origen,
    valor_transformado, fecha_lectura, mensaje, detalle)
  values (
    p_id_conexion, p_id_sensor, p_id_usuario, v_correcto, p_valor_origen,
    (v_transformacion->>'valor_transformado')::double precision,
    p_fecha_lectura, v_mensaje, coalesce(p_detalle, '{}'::jsonb));

  if p_id_sensor is not null then
    update public.sensores
       set estado_configuracion = case when v_correcto then 'PROBADO' else 'ERROR' end,
           fecha_ultima_prueba = pg_catalog.now()
     where id = p_id_sensor;
  end if;

  update public.conexiones
     set ultima_ejecucion = pg_catalog.now(),
         ultimo_ok = case when v_correcto then pg_catalog.now() else ultimo_ok end,
         ultimo_error = case when v_correcto then null else v_mensaje end
   where id = p_id_conexion;

  return coalesce(v_transformacion, '{}'::jsonb)
         || pg_catalog.jsonb_build_object('correcto', v_correcto, 'mensaje', v_mensaje);
end;
$$;

revoke all on function public.registrar_prueba_lectura(uuid, uuid, boolean, double precision, timestamptz, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.registrar_prueba_lectura(uuid, uuid, boolean, double precision, timestamptz, text, jsonb, uuid)
  to service_role;

-- Lista de comprobación para cerrar la parametrización de un edificio
-- (maestro §4: "validar requisitos obligatorios antes de cerrar").
-- bloqueante = impide pasar a OPERATIVO; el resto son avisos.
create or replace function public.estado_parametrizacion_edificio(p_id_edificio uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_3d boolean;
begin
  if not exists (select 1 from public.edificios where id = p_id_edificio) then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  select count(*) into v_n from public.plantas where id_edificio = p_id_edificio and activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'PLANTAS', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' plantas');

  select count(*) into v_n from public.recintos r join public.plantas p on p.id = r.id_planta
  where p.id_edificio = p_id_edificio and r.activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'RECINTOS', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' recintos');

  select count(*) into v_n from public.conexiones where id_edificio = p_id_edificio and activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'CONEXIONES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' conexiones');

  select count(*) into v_n from public.sensores s
  where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' sensores activos');

  select count(*) into v_n from public.sensores s
  where s.activo and s.direccion = '{}'::jsonb
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES_SIN_DIRECCION', 'bloqueante', false,
    'ok', v_n = 0, 'detalle', v_n || ' sensores sin dirección en el origen (no recibirán datos)');

  select count(*) into v_n from public.sensores s
  where s.activo and s.direccion <> '{}'::jsonb and s.estado_configuracion <> 'PROBADO'
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES_SIN_PROBAR', 'bloqueante', true,
    'ok', v_n = 0, 'detalle', v_n || ' sensores pendientes de prueba o con error');

  select count(*) into v_n from public.modalidades_edificio where id_edificio = p_id_edificio and activa;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MODALIDAD', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', case when v_n > 0 then 'asignada' else 'sin modalidad BASIC/PRO/PREMIUM' end);

  select count(*) into v_n from public.magnitudes_edificio me
  where me.id_edificio = p_id_edificio and me.activa
    and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id);
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MAGNITUDES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' magnitudes con sensores asignados');

  select count(*) into v_n from public.calendario_edificio
  where id_edificio = p_id_edificio
    and fecha between pg_catalog.date_trunc('year', current_date)::date
                  and (pg_catalog.date_trunc('year', current_date) + interval '1 year - 1 day')::date;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'CALENDARIO', 'bloqueante', false,
    'ok', v_n > 0, 'detalle', v_n || ' días configurados este año');

  v_3d := exists (select 1 from public.complementos_edificio
                  where id_edificio = p_id_edificio and codigo = '3D' and activa);
  if v_3d then
    select count(*) into v_n from public.modelos_3d
    where id_edificio = p_id_edificio and tipo_modelo = 'EDIFICIO' and activo;
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MODELO_3D', 'bloqueante', true,
      'ok', v_n > 0, 'detalle', case when v_n > 0 then 'modelo general cargado' else 'falta el modelo 3D general del edificio' end);

    select count(*) into v_n from public.sensores s
    where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
      and not exists (select 1 from public.ubicaciones_3d u
                      join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
                      where u.id_sensor = s.id
                         or u.id_dispositivo = s.id_dispositivo);
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'UBICACION_3D', 'bloqueante', false,
      'ok', v_n = 0, 'detalle', v_n || ' sensores sin posición en el modelo 3D');

    select count(*) into v_n from public.ubicaciones_3d u
    join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
    where m.id_edificio = p_id_edificio and u.por_revisar;
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'COORDENADAS_POR_REVISAR', 'bloqueante', false,
      'ok', v_n = 0, 'detalle', v_n || ' coordenadas copiadas de una versión anterior del GLB pendientes de revisar');
  end if;

  return pg_catalog.jsonb_build_object(
    'completo', not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_items) i
      where (i->>'bloqueante')::boolean and not (i->>'ok')::boolean),
    'comprobaciones', v_items);
end;
$$;

-- Cierra la parametrización: PENDIENTE_PARAMETRIZACION → OPERATIVO,
-- solo si no queda ninguna comprobación bloqueante.
create or replace function public.cerrar_parametrizacion(p_id_edificio uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_estado jsonb;
  v_faltan text;
begin
  v_estado := public.estado_parametrizacion_edificio(p_id_edificio);

  if not (v_estado->>'completo')::boolean then
    select pg_catalog.string_agg(i->>'codigo' || ' (' || (i->>'detalle') || ')', ', ')
      into v_faltan
    from pg_catalog.jsonb_array_elements(v_estado->'comprobaciones') i
    where (i->>'bloqueante')::boolean and not (i->>'ok')::boolean;
    raise exception 'No se puede cerrar la parametrización. Falta: %', v_faltan;
  end if;

  update public.edificios
     set estado = 'OPERATIVO'
   where id = p_id_edificio and estado = 'PENDIENTE_PARAMETRIZACION';

  if not found then
    raise exception 'El edificio no está pendiente de parametrización o no tiene permiso para modificarlo'
      using errcode = '42501';
  end if;

  return v_estado;
end;
$$;

revoke all on function public.estado_parametrizacion_edificio(uuid) from public, anon;
revoke all on function public.cerrar_parametrizacion(uuid) from public, anon;
grant execute on function public.estado_parametrizacion_edificio(uuid) to authenticated, service_role;
grant execute on function public.cerrar_parametrizacion(uuid) to authenticated, service_role;

-- ---------------------------------------------------------
-- 6. AUDITORÍA de las tablas nuevas
-- ---------------------------------------------------------
drop trigger if exists trg_auditoria on public.plantillas_dispositivo;
create trigger trg_auditoria after insert or update or delete on public.plantillas_dispositivo
for each row execute function public.auditar_cambio();
drop trigger if exists trg_auditoria on public.plantillas_puntos;
create trigger trg_auditoria after insert or update or delete on public.plantillas_puntos
for each row execute function public.auditar_cambio();

-- ---------------------------------------------------------
-- 7. PLANTILLAS DE EJEMPLO (globales)
-- Son ilustrativas: los registros Modbus reales dependen de cada
-- fabricante y deben tomarse de su manual.
-- ---------------------------------------------------------
insert into public.plantillas_dispositivo (codigo, nombre, fabricante, modelo, id_tipo_dispositivo, id_tipo_conexion, descripcion)
select 'EJEMPLO_ENVIO_CONTADOR', 'Contador eléctrico por envío HTTP (ejemplo)', null, null,
       td.id, tc.id, 'Plantilla de ejemplo: un contador que envía energía (Wh) y potencia (W).'
from public.tipos_dispositivo td, public.tipos_conexion tc
where td.codigo = 'CONTADOR_ENERGIA' and tc.codigo = 'ENVIO_HTTP'
on conflict do nothing;

insert into public.plantillas_puntos (
  id_plantilla, codigo, nombre, direccion, unidad, unidad_origen, escala,
  valor_minimo, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, id_flujo_energia, orden)
select p.id, x.codigo, x.nombre, pg_catalog.jsonb_build_object('clave', x.clave), x.unidad, x.unidad_origen, x.escala,
       0, f.id, n.id, t.id, te.id, fe.id, x.orden
from public.plantillas_dispositivo p
cross join (values
  ('energia_importada', 'Energía activa importada', 'energia_importada', 'kWh', 'Wh', 0.001::float8, 'ENERGIA', 'ACUMULATIVA', 'DELTA', 1),
  ('potencia_activa',   'Potencia activa total',    'potencia_activa',   'kW',  'W',  0.001::float8, 'POTENCIA', 'INSTANTANEA', 'PROMEDIO', 2)
) as x(codigo, nombre, clave, unidad, unidad_origen, escala, familia, naturaleza, tratamiento, orden)
join public.familias_sensor f on f.codigo = x.familia
join public.naturalezas_sensor n on n.codigo = x.naturaleza
join public.tratamientos_sensor t on t.codigo = x.tratamiento
join public.tipos_energia te on te.codigo = 'ELECTRICIDAD'
join public.flujos_energia fe on fe.codigo = 'CONSUMO'
where p.codigo = 'EJEMPLO_ENVIO_CONTADOR' and p.id_proveedor is null
on conflict (id_plantilla, codigo) do nothing;

commit;

-- Programación de la revisión de comunicación (pg_cron), cada 15 minutos.
do $$
begin
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron no disponible: el backend debe llamar a revisar_comunicacion() cada 15 minutos';
    return;
  end if;

  perform cron.unschedule(jobid) from cron.job where jobname = 'revisar_comunicacion';
  perform cron.schedule('revisar_comunicacion', '*/15 * * * *', 'select public.revisar_comunicacion()');
end;
$$;
