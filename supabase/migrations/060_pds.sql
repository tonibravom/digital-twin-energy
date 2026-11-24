-- =========================================================
-- 060 · Peticiones de servicio (PDS) a las empresas mantenedoras (D63)
-- La plataforma solo CREA y ENVÍA la petición, con un formato fijo (PDF, JSON y CSV; ver
-- docs/pds-formato.md). No sigue su estado: eso lo hace la herramienta del mantenedor.
--  - pds_destinos: a quién se envían, por edificio (los configura el Partner).
--  - pds: cada petición, con su número (<CÓDIGO EDIFICIO>-<AÑO>-<0001>) y una foto de su contenido.
--  - pds_envios: registro de cada envío por email (el email lo envía la API con los adjuntos).
--  - Bucket privado «pds»: edificios/<id_edificio>/pds/<id_pds>/<archivo> (PDF, JSON, CSV y fotos).
-- =========================================================
begin;

create table if not exists public.pds_destinos (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id),
  nombre text not null check (pg_catalog.length(pg_catalog.btrim(nombre)) between 1 and 120),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  activo boolean not null default true,
  fecha_baja timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint ck_pds_destinos_baja check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null))
);
alter table public.pds_destinos enable row level security;
drop trigger if exists trg_pds_destinos_updated_at on public.pds_destinos;
create trigger trg_pds_destinos_updated_at before update on public.pds_destinos for each row execute function public.set_updated_at();
drop policy if exists pds_destinos_select on public.pds_destinos;
create policy pds_destinos_select on public.pds_destinos for select to authenticated
using (activo and private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_ALARMAS'));
grant select on public.pds_destinos to authenticated;

create table if not exists public.pds (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id),
  numero text not null unique,
  anio smallint not null,
  secuencia integer not null,
  tipo text not null check (tipo in ('CORRECTIVO', 'PREVENTIVO', 'LEGAL', 'MEJORA')),
  prioridad text not null check (prioridad in ('EMERGENCIA', 'URGENTE', 'NORMAL', 'PROGRAMABLE')),
  titulo text not null check (pg_catalog.length(pg_catalog.btrim(titulo)) between 1 and 200),
  descripcion text,
  id_recinto uuid references public.recintos(id),
  id_sensor uuid references public.sensores(id),
  id_evento_alarma uuid references public.eventos_alarma(id),
  contenido jsonb not null,                      -- el documento completo (formato pds/1.0)
  id_usuario uuid not null references public.usuarios(id),
  created_at timestamptz not null default pg_catalog.now(),
  constraint ux_pds_secuencia unique (id_edificio, anio, secuencia)
);
alter table public.pds enable row level security;
create index if not exists ix_pds_edificio on public.pds (id_edificio, created_at desc);
create index if not exists ix_pds_alarma on public.pds (id_evento_alarma) where id_evento_alarma is not null;
drop policy if exists pds_select on public.pds;
create policy pds_select on public.pds for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_ALARMAS'));
grant select on public.pds to authenticated;

create table if not exists public.pds_envios (
  id uuid primary key default gen_random_uuid(),
  id_pds uuid not null references public.pds(id),
  id_destino uuid references public.pds_destinos(id),
  destinatario text not null,
  id_notificacion uuid references public.notificaciones(id),
  adjuntos text[] not null default '{}',          -- rutas en el bucket «pds»
  id_usuario uuid not null references public.usuarios(id),
  created_at timestamptz not null default pg_catalog.now()
);
alter table public.pds_envios enable row level security;
create index if not exists ix_pds_envios_pds on public.pds_envios (id_pds);
drop policy if exists pds_envios_select on public.pds_envios;
create policy pds_envios_select on public.pds_envios for select to authenticated
using (exists (select 1 from public.pds p where p.id = pds_envios.id_pds
               and private.usuario_tiene_acceso_edificio(p.id_edificio) and private.usuario_tiene_permiso('VER_ALARMAS')));
grant select on public.pds_envios to authenticated;
-- Sin políticas de escritura en las tres tablas: solo con las funciones de abajo

-- Edificio de una PDS (para las reglas)
create or replace function private.edificio_pds(p_id_pds uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select id_edificio from public.pds where id = p_id_pds $$;
revoke all on function private.edificio_pds(uuid) from public, anon;
grant execute on function private.edificio_pds(uuid) to authenticated;

-- Archivos de las PDS: edificios/<id_edificio>/pds/<id_pds>/<archivo>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pds', 'pds', false, 10485760,
        array['application/pdf', 'application/json', 'text/csv', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function private.puede_archivo_pds(p_ruta text, p_permiso text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v text[] := pg_catalog.string_to_array(p_ruta, '/');
  v_edificio uuid;
  v_pds uuid;
begin
  if pg_catalog.cardinality(v) <> 5 or v[1] <> 'edificios' or v[3] <> 'pds' then return false; end if;
  begin
    v_edificio := v[2]::uuid;
    v_pds := v[4]::uuid;
  exception when others then
    return false;
  end;
  return private.edificio_pds(v_pds) = v_edificio and private.usuario_puede_edificio(v_edificio, p_permiso);
end;
$$;
revoke all on function private.puede_archivo_pds(text, text) from public, anon;
grant execute on function private.puede_archivo_pds(text, text) to authenticated;

drop policy if exists pds_archivos_select on storage.objects;
create policy pds_archivos_select on storage.objects for select to authenticated
using (bucket_id = 'pds' and private.puede_archivo_pds(name, 'VER_ALARMAS'));
drop policy if exists pds_archivos_insert on storage.objects;
create policy pds_archivos_insert on storage.objects for insert to authenticated
with check (bucket_id = 'pds' and private.puede_archivo_pds(name, 'RECONOCER_ALARMAS'));
drop policy if exists pds_archivos_update on storage.objects;
create policy pds_archivos_update on storage.objects for update to authenticated
using (bucket_id = 'pds' and private.puede_archivo_pds(name, 'RECONOCER_ALARMAS'))
with check (bucket_id = 'pds' and private.puede_archivo_pds(name, 'RECONOCER_ALARMAS'));

-- La cronología de la alarma también registra sus PDS
alter table public.eventos_alarma_acciones drop constraint if exists eventos_alarma_acciones_accion_check;
alter table public.eventos_alarma_acciones add constraint eventos_alarma_acciones_accion_check check (accion in (
  'ABIERTA', 'EMAIL_ENVIADO', 'EMAIL_ERROR', 'ESCALADA', 'RECONOCIDA', 'SILENCIADA', 'SILENCIO_RETIRADO', 'SILENCIO_CADUCADO',
  'RESUELTA', 'VUELVE_CAUSA', 'REABIERTA', 'CERRADA', 'CERRADA_AUTOMATICA', 'PDS_CREADA', 'PDS_ENVIADA'));

-- Emails de PDS en notificaciones
alter table public.notificaciones drop constraint if exists ck_notificaciones_tipo;
alter table public.notificaciones add constraint ck_notificaciones_tipo check (tipo in ('ALARMA', 'COMUNICACION', 'INFORME', 'PDS'));
alter table public.notificaciones drop constraint if exists ck_notificaciones_motivo;
alter table public.notificaciones add constraint ck_notificaciones_motivo check (motivo is null or motivo in
  ('INMEDIATO', 'ESCALADO', 'REAVISO', 'RESUMEN_DIARIO', 'INFORME_SEMANAL', 'INFORME_MENSUAL', 'PDS'));

-- Destinos (Partner)
create or replace function public.guardar_destino_pds(p_id_edificio uuid, p_nombre text, p_email text, p_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Sin permiso para configurar los destinos de las PDS' using errcode = '42501';
  end if;
  if coalesce(pg_catalog.btrim(p_nombre), '') = '' or coalesce(pg_catalog.btrim(p_email), '') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Indique el nombre y un email válido' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.pds_destinos (id_edificio, nombre, email) values (p_id_edificio, pg_catalog.btrim(p_nombre), pg_catalog.lower(pg_catalog.btrim(p_email)))
    returning id into v_id;
    return v_id;
  end if;
  update public.pds_destinos set nombre = pg_catalog.btrim(p_nombre), email = pg_catalog.lower(pg_catalog.btrim(p_email))
  where id = p_id and id_edificio = p_id_edificio and activo returning id into v_id;
  if v_id is null then raise exception 'Destino inexistente' using errcode = '22023'; end if;
  return v_id;
end;
$$;
revoke all on function public.guardar_destino_pds(uuid, text, text, uuid) from public, anon;
grant execute on function public.guardar_destino_pds(uuid, text, text, uuid) to authenticated;

create or replace function public.retirar_destino_pds(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  select id_edificio into v_edificio from public.pds_destinos where id = p_id and activo;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Destino inexistente o sin permiso' using errcode = '42501';
  end if;
  update public.pds_destinos set activo = false, fecha_baja = pg_catalog.now() where id = p_id;
end;
$$;
revoke all on function public.retirar_destino_pds(uuid) from public, anon;
grant execute on function public.retirar_destino_pds(uuid) to authenticated;

-- Crear una PDS: número propio y documento completo (formato pds/1.0) con lo que sabe la plataforma
create or replace function public.crear_pds(
  p_id_edificio uuid, p_tipo text, p_prioridad text, p_titulo text, p_descripcion text default null,
  p_id_recinto uuid default null, p_id_sensor uuid default null, p_id_evento_alarma uuid default null,
  p_telefono text default null, p_adjuntos jsonb default '[]')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario uuid := private.usuario_actual();
  e public.edificios%rowtype;
  v_anio smallint;
  v_sec integer;
  v_numero text;
  v_recinto uuid := p_id_recinto;
  v_alarma jsonb;
  v_equipo jsonb;
  v_ubicacion jsonb;
  v_solicitante jsonb;
  v_partner text;
  v_doc jsonb;
  v_id uuid := gen_random_uuid();
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'RECONOCER_ALARMAS') then
    raise exception 'Sin permiso para crear peticiones de servicio en este edificio' using errcode = '42501';
  end if;
  if p_tipo not in ('CORRECTIVO', 'PREVENTIVO', 'LEGAL', 'MEJORA') or p_prioridad not in ('EMERGENCIA', 'URGENTE', 'NORMAL', 'PROGRAMABLE') then
    raise exception 'Tipo o prioridad no válidos' using errcode = '22023';
  end if;
  if coalesce(pg_catalog.btrim(p_titulo), '') = '' then
    raise exception 'Indique un título' using errcode = '22023';
  end if;
  select * into e from public.edificios where id = p_id_edificio for update;   -- numeración sin huecos ni repetidos

  -- Lo que viene de una alarma: sensor, recinto y su historia
  if p_id_evento_alarma is not null then
    select pg_catalog.jsonb_build_object(
             'id', ea.id, 'regla', ra.nombre, 'nivel', n.codigo, 'nivel_nombre', n.nombre, 'detalle', ea.mensaje,
             'valor', ea.valor_detectado, 'desde', ea.fecha_inicio, 'estado', ea.estado,
             'cronologia', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fecha', a.fecha, 'accion', a.accion,
                                       'quien', coalesce(nullif(pg_catalog.concat_ws(' ', u.nombre, u.apellidos), ''), 'Plataforma'), 'detalle', a.detalle)
                                       order by a.fecha)
                                     from public.eventos_alarma_acciones a left join public.usuarios u on u.id = a.id_usuario
                                     where a.id_evento_alarma = ea.id), '[]'::jsonb)),
           coalesce(p_id_sensor, ea.id_sensor, ra.id_sensor), coalesce(v_recinto, ea.id_recinto)
      into v_alarma, p_id_sensor, v_recinto
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    where ea.id = p_id_evento_alarma;
    if v_alarma is null then raise exception 'La alarma no es de este edificio' using errcode = '22023'; end if;
  end if;
  if p_id_sensor is not null then
    select pg_catalog.jsonb_build_object('sensor', s.nombre, 'codigo_sensor', s.codigo, 'unidad', s.unidad,
             'dispositivo', d.nombre, 'codigo_dispositivo', d.codigo, 'fabricante', d.fabricante, 'modelo', d.modelo,
             'numero_serie', d.numero_serie, 'tipo', td.nombre),
           coalesce(v_recinto, s.id_recinto)
      into v_equipo, v_recinto
    from public.sensores s
    left join public.dispositivos d on d.id = s.id_dispositivo
    left join public.tipos_dispositivo td on td.id = d.id_tipo_dispositivo
    where s.id = p_id_sensor and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
    if v_equipo is null then raise exception 'El sensor no es de este edificio' using errcode = '22023'; end if;
  end if;
  if v_recinto is not null then
    select pg_catalog.jsonb_build_object('planta', pl.nombre, 'nivel', pl.nivel, 'recinto', r.nombre, 'codigo_recinto', r.codigo, 'tipo', r.tipo)
      into v_ubicacion
    from public.recintos r join public.plantas pl on pl.id = r.id_planta and pl.id_edificio = p_id_edificio
    where r.id = v_recinto;
    if v_ubicacion is null then raise exception 'El recinto no es de este edificio' using errcode = '22023'; end if;
  end if;

  select pg_catalog.jsonb_build_object('nombre', pg_catalog.concat_ws(' ', u.nombre, u.apellidos), 'email', u.email,
           'telefono', coalesce(nullif(pg_catalog.btrim(p_telefono), ''), u.telefono), 'rol', r.nombre,
           'empresa', coalesce((select p.nombre from public.usuarios_partners up join public.proveedores p on p.id = up.id_proveedor
                                where up.id_usuario = u.id limit 1),
                               (select c.nombre from public.usuarios_clientes uc join public.clientes c on c.id = uc.id_cliente
                                where uc.id_usuario = u.id limit 1)))
    into v_solicitante
  from public.usuarios u join public.roles r on r.id = u.id_rol where u.id = v_usuario;
  select p.nombre into v_partner from public.proveedores_clientes pc join public.proveedores p on p.id = pc.id_proveedor
  where pc.id_cliente = e.id_cliente and pc.activo limit 1;

  v_anio := extract(year from pg_catalog.now() at time zone e.zona_horaria);
  select coalesce(max(secuencia), 0) + 1 into v_sec from public.pds where id_edificio = p_id_edificio and anio = v_anio;
  v_numero := pg_catalog.upper(pg_catalog.regexp_replace(e.codigo, '^DEMO-', 'DEMO')) || '-' || v_anio || '-' || pg_catalog.lpad(v_sec::text, 4, '0');

  v_doc := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'formato', 'pds', 'version', '1.0', 'numero', v_numero, 'creada', pg_catalog.now(), 'zona_horaria', e.zona_horaria,
    'tipo', p_tipo, 'prioridad', p_prioridad, 'titulo', pg_catalog.btrim(p_titulo), 'descripcion', nullif(pg_catalog.btrim(p_descripcion), ''),
    'edificio', pg_catalog.jsonb_build_object('codigo', e.codigo, 'nombre', e.nombre, 'direccion', e.direccion, 'codigo_postal', e.codigo_postal,
                                             'municipio', e.municipio, 'provincia', e.provincia, 'pais', e.pais,
                                             'latitud', e.latitud, 'longitud', e.longitud),
    'ubicacion', v_ubicacion, 'equipo', v_equipo,
    'origen', case when v_alarma is null then pg_catalog.jsonb_build_object('tipo', 'MANUAL')
                   else pg_catalog.jsonb_build_object('tipo', 'ALARMA', 'alarma', v_alarma) end,
    'solicitante', v_solicitante, 'partner', v_partner,
    'adjuntos', coalesce(p_adjuntos, '[]'::jsonb)));

  insert into public.pds (id, id_edificio, numero, anio, secuencia, tipo, prioridad, titulo, descripcion, id_recinto, id_sensor,
                          id_evento_alarma, contenido, id_usuario)
  values (v_id, p_id_edificio, v_numero, v_anio, v_sec, p_tipo, p_prioridad, pg_catalog.btrim(p_titulo), nullif(pg_catalog.btrim(p_descripcion), ''),
          v_recinto, p_id_sensor, p_id_evento_alarma, v_doc, v_usuario);
  if p_id_evento_alarma is not null then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
    values (p_id_evento_alarma, 'PDS_CREADA', v_usuario, 'PDS ' || v_numero || ': ' || pg_catalog.btrim(p_titulo));
  end if;
  return pg_catalog.jsonb_build_object('id', v_id, 'numero', v_numero, 'contenido', v_doc);
end;
$$;
revoke all on function public.crear_pds(uuid, text, text, text, text, uuid, uuid, uuid, text, jsonb) from public, anon;
grant execute on function public.crear_pds(uuid, text, text, text, text, uuid, uuid, uuid, text, jsonb) to authenticated;

-- Al terminar de prepararla en la web: lista de archivos (fotos, PDF, JSON, CSV) y enlace a la plataforma
create or replace function public.completar_pds(p_id_pds uuid, p_adjuntos jsonb, p_enlace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc jsonb;
begin
  if not private.usuario_puede_edificio(private.edificio_pds(p_id_pds), 'RECONOCER_ALARMAS') then
    raise exception 'PDS inexistente o sin permiso' using errcode = '42501';
  end if;
  if p_enlace is not null and p_enlace !~ '^https?://' then
    raise exception 'Enlace no válido' using errcode = '22023';
  end if;
  update public.pds
     set contenido = pg_catalog.jsonb_strip_nulls(contenido || pg_catalog.jsonb_build_object('adjuntos', coalesce(p_adjuntos, '[]'::jsonb), 'enlace', p_enlace))
   where id = p_id_pds returning contenido into v_doc;
  return v_doc;
end;
$$;
revoke all on function public.completar_pds(uuid, jsonb, text) from public, anon;
grant execute on function public.completar_pds(uuid, jsonb, text) to authenticated;

-- Enviar por email a un destino: la API manda el email con los archivos indicados (PDF, JSON, CSV y fotos)
create or replace function public.enviar_pds(p_id_pds uuid, p_id_destino uuid, p_adjuntos text[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.pds%rowtype;
  d public.pds_destinos%rowtype;
  v_usuario uuid := private.usuario_actual();
  v_notif uuid;
  v_id uuid;
  a text;
begin
  select * into p from public.pds where id = p_id_pds;
  if p.id is null or not private.usuario_puede_edificio(p.id_edificio, 'RECONOCER_ALARMAS') then
    raise exception 'PDS inexistente o sin permiso' using errcode = '42501';
  end if;
  select * into d from public.pds_destinos where id = p_id_destino and id_edificio = p.id_edificio and activo;
  if d.id is null then raise exception 'Destino no válido para este edificio' using errcode = '22023'; end if;
  foreach a in array coalesce(p_adjuntos, '{}') loop
    if a not like 'edificios/' || p.id_edificio || '/pds/' || p.id || '/%' then
      raise exception 'Adjunto no válido' using errcode = '22023';
    end if;
  end loop;
  insert into public.notificaciones (tipo, canal, id_usuario, destinatario, motivo, mensaje, datos)
  values ('PDS', 'EMAIL', v_usuario, d.email, 'PDS', 'PDS ' || p.numero,
          pg_catalog.jsonb_build_object('id_pds', p.id, 'numero', p.numero, 'destino', d.nombre, 'adjuntos', pg_catalog.to_jsonb(coalesce(p_adjuntos, '{}')),
                                        'pds', p.contenido - 'adjuntos'))
  returning id into v_notif;
  insert into public.pds_envios (id_pds, id_destino, destinatario, id_notificacion, adjuntos, id_usuario)
  values (p.id, d.id, d.email, v_notif, coalesce(p_adjuntos, '{}'), v_usuario) returning id into v_id;
  if p.id_evento_alarma is not null then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
    values (p.id_evento_alarma, 'PDS_ENVIADA', v_usuario, 'PDS ' || p.numero || ' enviada a ' || d.nombre || ' (' || d.email || ')');
  end if;
  perform private.llamar_api_avisos();
  return v_id;
end;
$$;
revoke all on function public.enviar_pds(uuid, uuid, text[]) from public, anon;
grant execute on function public.enviar_pds(uuid, uuid, text[]) to authenticated;

-- Registro de PDS del edificio (con sus envíos y si el email salió)
create or replace function public.pds_edificio(p_id_edificio uuid, p_limite integer default 200)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(x.f order by x.creada desc), '[]'::jsonb) from (
    select p.created_at as creada, pg_catalog.jsonb_build_object(
      'id', p.id, 'numero', p.numero, 'creada', p.created_at, 'tipo', p.tipo, 'prioridad', p.prioridad, 'titulo', p.titulo,
      'id_evento_alarma', p.id_evento_alarma, 'contenido', p.contenido,
      'crea', (select pg_catalog.concat_ws(' ', u.nombre, u.apellidos) from public.usuarios u where u.id = p.id_usuario),
      'envios', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fecha', e.created_at, 'destino', d.nombre,
                                  'email', e.destinatario, 'estado', n.estado, 'error', n.error, 'adjuntos', e.adjuntos) order by e.created_at)
                          from public.pds_envios e left join public.pds_destinos d on d.id = e.id_destino
                          left join public.notificaciones n on n.id = e.id_notificacion where e.id_pds = p.id), '[]'::jsonb)) as f
    from public.pds p where p.id_edificio = p_id_edificio
    order by p.created_at desc limit greatest(1, least(coalesce(p_limite, 200), 1000))
  ) x;
$$;
revoke all on function public.pds_edificio(uuid, integer) from public, anon;
grant execute on function public.pds_edificio(uuid, integer) to authenticated;

commit;
