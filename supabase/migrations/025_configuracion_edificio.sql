begin;

-- =========================================================
-- CONFIGURACIÓN Y EDICIÓN DE EDIFICIOS (decisiones 21/10/2026)
--
-- 1. No se desactiva una planta o recinto con elementos activos.
-- 2. Sustituir sensor / dispositivo: entidad nueva, la antigua se
--    desactiva y conserva su histórico (maestro §5). Su configuración
--    (magnitudes, posición 3D, reglas, ámbitos, suministros) pasa a
--    la nueva.
-- 3. Sustituir un GLB: versión nueva, la anterior queda inactiva y
--    las coordenadas se copian marcadas "por revisar".
-- 4. Calendario del edificio: horario tipo semanal, festivos
--    compartidos (país, provincia, municipio), generación anual
--    automática; lo editan el Partner y el usuario cliente avanzado
--    (este último, solo días de hoy en adelante).
-- =========================================================

-- ---------------------------------------------------------
-- 1. Bajas de plantas y recintos
-- ---------------------------------------------------------
create or replace function public.validar_baja_estructura()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_n integer;
begin
  if not (old.activo and not new.activo) then
    return new;
  end if;

  if tg_table_name = 'plantas' then
    select count(*) into v_n from public.recintos where id_planta = new.id and activo;
    if v_n > 0 then
      raise exception 'No se puede desactivar la planta: tiene % recintos activos', v_n;
    end if;
  else
    select (select count(*) from public.sensores where id_recinto = new.id and activo)
         + (select count(*) from public.dispositivos where id_recinto = new.id and activo)
      into v_n;
    if v_n > 0 then
      raise exception 'No se puede desactivar el recinto: tiene % sensores o dispositivos activos. Muévalos o dé de baja antes', v_n;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_plantas_validar_baja on public.plantas;
create trigger trg_plantas_validar_baja
before update of activo on public.plantas
for each row execute function public.validar_baja_estructura();

drop trigger if exists trg_recintos_validar_baja on public.recintos;
create trigger trg_recintos_validar_baja
before update of activo on public.recintos
for each row execute function public.validar_baja_estructura();

-- ---------------------------------------------------------
-- 2. Sustitución de sensores y dispositivos
-- El elemento antiguo conserva sus lecturas y se renombra con el
-- sufijo "#AAAAMMDD-xxxxxxxx" (fecha + inicio de su id) para que el
-- nuevo mantenga el código original.
-- ---------------------------------------------------------
create or replace function public.sustituir_sensor(
  p_id_sensor uuid,
  p_direccion jsonb default null,
  p_id_dispositivo_nuevo uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.sensores%rowtype;
  v_nuevo uuid;
  v_sufijo text;
begin
  select * into v_old from public.sensores where id = p_id_sensor and activo;
  if not found then
    raise exception 'El sensor no existe o ya está inactivo';
  end if;

  -- Sufijo único aunque se sustituya varias veces el mismo día
  v_sufijo := '#' || pg_catalog.to_char(current_date, 'YYYYMMDD') || '-' || pg_catalog.left(v_old.id::text, 8);

  if auth.uid() is not null and not private.usuario_puede_edificio(
       public.obtener_edificio_recinto(v_old.id_recinto), 'MODIFICAR_SENSOR') then
    raise exception 'Sin permiso para sustituir sensores en este edificio' using errcode = '42501';
  end if;

  -- 1) el antiguo se renombra y se desactiva
  update public.sensores
     set codigo = pg_catalog.left(v_old.codigo, 130) || v_sufijo,
         activo = false,
         fecha_baja = current_date
   where id = v_old.id;

  -- 2) el nuevo copia la configuración (y empieza PENDIENTE de prueba)
  insert into public.sensores (
    id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento,
    id_tipo_energia, id_flujo_energia, id_uso_energia, codigo, nombre, magnitud_origen,
    unidad, unidad_origen, escala, desplazamiento, valor_minimo, valor_maximo,
    politica_vacios, direccion, descripcion)
  values (
    coalesce(p_id_dispositivo_nuevo, v_old.id_dispositivo),
    case when p_id_dispositivo_nuevo is null then v_old.id_conexion end,
    v_old.id_recinto, v_old.id_familia, v_old.id_naturaleza, v_old.id_tratamiento,
    v_old.id_tipo_energia, v_old.id_flujo_energia, v_old.id_uso_energia, v_old.codigo, v_old.nombre,
    v_old.magnitud_origen, v_old.unidad, v_old.unidad_origen, v_old.escala, v_old.desplazamiento,
    v_old.valor_minimo, v_old.valor_maximo, v_old.politica_vacios,
    coalesce(p_direccion, v_old.direccion), v_old.descripcion)
  returning id into v_nuevo;

  -- 3) la configuración ligada pasa al sensor nuevo
  update public.magnitudes_fuentes set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.ubicaciones_3d set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.reglas_alarma set id_sensor = v_nuevo where id_sensor = v_old.id and activa;
  update public.sensores_recintos_ambito set id_sensor = v_nuevo where id_sensor = v_old.id and activo;

  return v_nuevo;
end;
$$;

create or replace function public.sustituir_dispositivo(
  p_id_dispositivo uuid,
  p_numero_serie varchar default null,
  p_modelo varchar default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.dispositivos%rowtype;
  v_nuevo uuid;
  v_sufijo text;
  r record;
begin
  select * into v_old from public.dispositivos where id = p_id_dispositivo and activo;
  if not found then
    raise exception 'El dispositivo no existe o ya está inactivo';
  end if;

  v_sufijo := '#' || pg_catalog.to_char(current_date, 'YYYYMMDD') || '-' || pg_catalog.left(v_old.id::text, 8);

  if auth.uid() is not null and not private.usuario_puede_edificio(
       public.obtener_edificio_recinto(v_old.id_recinto), 'MODIFICAR_DISPOSITIVO') then
    raise exception 'Sin permiso para sustituir dispositivos en este edificio' using errcode = '42501';
  end if;

  update public.dispositivos
     set codigo = pg_catalog.left(v_old.codigo, 80) || v_sufijo
   where id = v_old.id;

  insert into public.dispositivos (
    id_recinto, id_conexion, id_tipo_dispositivo, id_plantilla, codigo, nombre,
    fabricante, modelo, numero_serie, descripcion, metadatos)
  values (
    v_old.id_recinto, v_old.id_conexion, v_old.id_tipo_dispositivo, v_old.id_plantilla,
    v_old.codigo, v_old.nombre, v_old.fabricante, coalesce(p_modelo, v_old.modelo),
    p_numero_serie, v_old.descripcion, v_old.metadatos)
  returning id into v_nuevo;

  -- cada sensor del antiguo se sustituye por uno nuevo en el dispositivo nuevo
  for r in select id from public.sensores where id_dispositivo = v_old.id and activo loop
    perform public.sustituir_sensor(r.id, null, v_nuevo);
  end loop;

  update public.ubicaciones_3d set id_dispositivo = v_nuevo where id_dispositivo = v_old.id;
  update public.suministros_dispositivos set id_dispositivo = v_nuevo where id_dispositivo = v_old.id and activo;
  update public.dispositivos_recintos_ambito set id_dispositivo = v_nuevo where id_dispositivo = v_old.id and activo;

  update public.dispositivos
     set activo = false, fecha_baja = current_date
   where id = v_old.id;

  return v_nuevo;
end;
$$;

-- ---------------------------------------------------------
-- 3. Sustitución de un modelo 3D (nueva versión del GLB)
-- ---------------------------------------------------------
create or replace function public.sustituir_modelo_3d(
  p_id_modelo uuid,
  p_archivo text,
  p_nombre varchar default null,
  p_compresion varchar default null,
  p_copiar_coordenadas boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.modelos_3d%rowtype;
  v_nuevo uuid;
begin
  select * into v_old from public.modelos_3d where id = p_id_modelo and activo;
  if not found then
    raise exception 'El modelo no existe o no es la versión activa';
  end if;

  if auth.uid() is not null
     and not private.usuario_puede_edificio(v_old.id_edificio, 'SUSTITUIR_MODELO_3D') then
    raise exception 'Sin permiso para sustituir modelos 3D en este edificio' using errcode = '42501';
  end if;

  update public.modelos_3d set activo = false, fecha_baja = current_date where id = v_old.id;

  insert into public.modelos_3d (id_edificio, id_recinto, tipo_modelo, nombre, archivo, formato,
                                 compresion, version, descripcion)
  values (v_old.id_edificio, v_old.id_recinto, v_old.tipo_modelo, coalesce(p_nombre, v_old.nombre),
          p_archivo, case when p_archivo ~* '[.]gltf$' then 'GLTF' else 'GLB' end,
          coalesce(p_compresion, v_old.compresion), v_old.version + 1, v_old.descripcion)
  returning id into v_nuevo;

  if p_copiar_coordenadas then
    insert into public.ubicaciones_3d (id_modelo_3d, id_dispositivo, id_sensor, x, y, z, visible, descripcion, por_revisar)
    select v_nuevo, u.id_dispositivo, u.id_sensor, u.x, u.y, u.z, u.visible, u.descripcion, true
    from public.ubicaciones_3d u
    join public.sensores s on s.id = u.id_sensor and s.activo
    where u.id_modelo_3d = v_old.id
    union all
    select v_nuevo, u.id_dispositivo, u.id_sensor, u.x, u.y, u.z, u.visible, u.descripcion, true
    from public.ubicaciones_3d u
    join public.dispositivos d on d.id = u.id_dispositivo and d.activo
    where u.id_modelo_3d = v_old.id;
  end if;

  return v_nuevo;
end;
$$;

-- Al guardar una coordenada a mano, deja de estar "por revisar".
create or replace function public.revisar_coordenada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.x, new.y, new.z) is distinct from (old.x, old.y, old.z) then
    new.por_revisar := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ubicaciones_3d_revisar on public.ubicaciones_3d;
create trigger trg_ubicaciones_3d_revisar
before update on public.ubicaciones_3d
for each row execute function public.revisar_coordenada();

-- Confirmar sin cambios las coordenadas copiadas de un modelo.
create or replace function public.confirmar_coordenadas(p_id_modelo uuid, p_ids uuid[] default null)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_n integer;
begin
  update public.ubicaciones_3d
     set por_revisar = false
   where id_modelo_3d = p_id_modelo and por_revisar
     and (p_ids is null or id = any (p_ids));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------
-- 4. Calendario del edificio
-- ---------------------------------------------------------

-- 4.1 Horario tipo semanal (solo sirve para GENERAR los días; el
-- calendario sigue guardándose día a día, como fija el maestro §11)
create table if not exists public.horarios_tipo_edificio (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  dia_semana smallint not null,
  laborable boolean not null default true,
  hora_inicio time,
  hora_fin time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint horarios_tipo_uq unique (id_edificio, dia_semana),
  constraint horarios_tipo_dia_ck check (dia_semana between 1 and 7),
  constraint horarios_tipo_horario_ck check (
    (not laborable and hora_inicio is null and hora_fin is null)
    or (laborable and hora_inicio is not null and hora_fin is not null and hora_fin > hora_inicio))
);

comment on table public.horarios_tipo_edificio is
  'Horario habitual por día de la semana (1 = lunes ... 7 = domingo). Se usa para generar el calendario anual.';

-- 4.2 Festivos compartidos
create table if not exists public.festivos (
  id uuid primary key default gen_random_uuid(),
  id_proveedor uuid references public.proveedores(id) on delete restrict,
  ambito varchar(20) not null,
  pais varchar(100) not null default 'España',
  provincia varchar(120),
  municipio varchar(120),
  fecha date not null,
  nombre varchar(150) not null,
  created_at timestamptz not null default now(),
  constraint festivos_ambito_ck check (
    (ambito = 'PAIS' and provincia is null and municipio is null)
    or (ambito = 'PROVINCIA' and provincia is not null and municipio is null)
    or (ambito = 'MUNICIPIO' and provincia is not null and municipio is not null))
);

create unique index if not exists ux_festivos
  on public.festivos (coalesce(id_proveedor, '00000000-0000-0000-0000-000000000000'::uuid),
                      ambito, lower(pais), lower(coalesce(provincia, '')), lower(coalesce(municipio, '')), fecha);
create index if not exists ix_festivos_fecha on public.festivos(fecha);

comment on table public.festivos is
  'Festivos por país, provincia o municipio. id_proveedor nulo = de la plataforma (todos); con valor = propios de un Partner. Los autonómicos se registran en cada provincia de la comunidad.';

-- ¿Es festivo para este edificio?
create or replace function public.es_festivo(p_id_edificio uuid, p_fecha date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.edificios e
    join public.festivos f on f.fecha = p_fecha
    left join public.proveedores_edificios pe on pe.id_edificio = e.id and pe.activo
    where e.id = p_id_edificio
      and (f.id_proveedor is null or f.id_proveedor = pe.id_proveedor)
      and lower(f.pais) = lower(e.pais)
      and (f.ambito = 'PAIS'
           or (f.ambito = 'PROVINCIA' and lower(f.provincia) = lower(e.provincia))
           or (f.ambito = 'MUNICIPIO' and lower(f.provincia) = lower(e.provincia)
                                      and lower(f.municipio) = lower(e.municipio)))
  );
$$;

-- 4.3 Generación de un año (no pisa los días ya existentes salvo
-- que se pida; nunca días pasados)
create or replace function public.generar_calendario(
  p_id_edificio uuid,
  p_anio integer,
  p_sobrescribir boolean default false,
  p_incluir_pasado boolean default false
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_creados integer;
begin
  if p_anio < 2000 or p_anio > 2100 then
    raise exception 'Año no válido';
  end if;

  with dias as (
    select d::date as fecha, extract(isodow from d)::smallint as dow
    from pg_catalog.generate_series(pg_catalog.make_date(p_anio, 1, 1), pg_catalog.make_date(p_anio, 12, 31), interval '1 day') d
    -- Los días pasados solo con p_incluir_pasado (cargas de históricos);
    -- para los usuarios de cliente los bloquea el trigger de protección.
    where p_incluir_pasado or d::date >= current_date
  ),
  propuesta as (
    select dias.fecha,
           case when public.es_festivo(p_id_edificio, dias.fecha) then false
                else coalesce(h.laborable, dias.dow < 6) end as laborable,
           h.hora_inicio, h.hora_fin
    from dias
    left join public.horarios_tipo_edificio h on h.id_edificio = p_id_edificio and h.dia_semana = dias.dow
  ),
  ins as (
    insert into public.calendario_edificio (id_edificio, fecha, laborable, hora_inicio, hora_fin, descripcion)
    select p_id_edificio, p.fecha, p.laborable,
           case when p.laborable then p.hora_inicio end,
           case when p.laborable then p.hora_fin end,
           case when not p.laborable and public.es_festivo(p_id_edificio, p.fecha) then 'Festivo' end
    from propuesta p
    -- un día laborable sin horario tipo no cumple la restricción: se omite
    where not p.laborable or p.hora_inicio is not null
    on conflict (id_edificio, fecha) do update
      set laborable = excluded.laborable, hora_inicio = excluded.hora_inicio,
          hora_fin = excluded.hora_fin, descripcion = excluded.descripcion
      where p_sobrescribir
    returning 1
  )
  select count(*) into v_creados from ins;

  return v_creados;
end;
$$;

-- 4.4 Generación anual automática para todos los edificios
create or replace function public.generar_calendarios_anio_siguiente(p_hoy date default current_date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total integer := 0;
  r record;
begin
  if extract(month from p_hoy) < 12 then
    return 0;   -- se genera a partir del 1 de diciembre
  end if;

  for r in
    select e.id from public.edificios e
    where e.activo
      and exists (select 1 from public.horarios_tipo_edificio h where h.id_edificio = e.id)
  loop
    v_total := v_total + public.generar_calendario(r.id, extract(year from p_hoy)::integer + 1, false);
  end loop;

  return v_total;
end;
$$;

-- Se añade a la tarea diaria de mantenimiento (018)
create or replace function public.mantenimiento_datos()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ahora timestamp := pg_catalog.now() at time zone 'UTC';
  v_lect integer;
  v_val integer;
  v_ret integer;
  v_cal integer;
begin
  v_lect := public.asegurar_particiones_lecturas(
    v_ahora::date, (v_ahora + interval '3 months')::date);
  v_val := public.asegurar_particiones_valores_magnitud(
    extract(year from v_ahora)::integer, extract(year from v_ahora)::integer + 1);
  v_ret := public.aplicar_retencion_lecturas();
  v_cal := public.generar_calendarios_anio_siguiente(current_date);

  return pg_catalog.jsonb_build_object(
    'particiones_lecturas_creadas', v_lect,
    'particiones_valores_creadas', v_val,
    'particiones_lecturas_eliminadas', v_ret,
    'dias_calendario_generados', v_cal,
    'ejecutado', pg_catalog.now()
  );
end;
$$;

-- 4.5 Permisos del calendario
-- El usuario cliente avanzado puede ajustar el calendario de sus
-- edificios (maestro §11, permisos del avanzado pendientes).
insert into public.roles_permisos (id_rol, id_permiso)
select r.id, p.id from public.roles r, public.permisos p
where r.codigo = 'USUARIO_CLIENTE_AVANZADO' and p.codigo = 'MODIFICAR_CALENDARIO'
on conflict do nothing;

-- Los usuarios de cliente no modifican días pasados (protege los
-- análisis históricos). El Partner y el administrador sí.
create or replace function private.proteger_calendario_pasado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fecha date := case when tg_op = 'DELETE' then old.fecha else new.fecha end;
begin
  if auth.uid() is not null
     and v_fecha < current_date
     and (private.usuario_tiene_rol('USUARIO_CLIENTE_AVANZADO') or private.usuario_tiene_rol('USUARIO_CLIENTE')) then
    raise exception 'Los días pasados del calendario solo los puede modificar el Partner' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.proteger_calendario_pasado() from public, anon;

drop trigger if exists trg_calendario_proteger_pasado on public.calendario_edificio;
create trigger trg_calendario_proteger_pasado
before insert or update or delete on public.calendario_edificio
for each row execute function private.proteger_calendario_pasado();

drop policy if exists calendario_edificio_delete on public.calendario_edificio;
create policy calendario_edificio_delete on public.calendario_edificio
for delete to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));

-- RLS de las tablas nuevas
alter table public.horarios_tipo_edificio enable row level security;

drop policy if exists horarios_tipo_select on public.horarios_tipo_edificio;
create policy horarios_tipo_select on public.horarios_tipo_edificio
for select to authenticated using (private.usuario_tiene_acceso_edificio(id_edificio));
drop policy if exists horarios_tipo_insert on public.horarios_tipo_edificio;
create policy horarios_tipo_insert on public.horarios_tipo_edificio
for insert to authenticated with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));
drop policy if exists horarios_tipo_update on public.horarios_tipo_edificio;
create policy horarios_tipo_update on public.horarios_tipo_edificio
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));
drop policy if exists horarios_tipo_delete on public.horarios_tipo_edificio;
create policy horarios_tipo_delete on public.horarios_tipo_edificio
for delete to authenticated using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_CALENDARIO'));

alter table public.festivos enable row level security;

-- Se ven los de la plataforma y los del propio Partner.
drop policy if exists festivos_select on public.festivos;
create policy festivos_select on public.festivos
for select to authenticated
using (
  id_proveedor is null
  or private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_es_del_partner(id_proveedor)
);
-- Los de la plataforma los mantiene el administrador; cada Partner, los suyos.
drop policy if exists festivos_insert on public.festivos;
create policy festivos_insert on public.festivos
for insert to authenticated
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (id_proveedor is not null
      and private.usuario_tiene_permiso('MODIFICAR_CALENDARIO')
      and private.usuario_es_del_partner(id_proveedor))
);
drop policy if exists festivos_delete on public.festivos;
create policy festivos_delete on public.festivos
for delete to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (id_proveedor is not null
      and private.usuario_tiene_permiso('MODIFICAR_CALENDARIO')
      and private.usuario_es_del_partner(id_proveedor))
);

-- Auditoría y updated_at
drop trigger if exists trg_auditoria on public.horarios_tipo_edificio;
create trigger trg_auditoria after insert or update or delete on public.horarios_tipo_edificio
for each row execute function public.auditar_cambio();
drop trigger if exists trg_auditoria on public.festivos;
create trigger trg_auditoria after insert or update or delete on public.festivos
for each row execute function public.auditar_cambio();
drop trigger if exists trg_horarios_tipo_updated_at on public.horarios_tipo_edificio;
create trigger trg_horarios_tipo_updated_at
before update on public.horarios_tipo_edificio
for each row execute function public.set_updated_at();

-- Festivos nacionales de España de ejemplo (2027). El comprador
-- debe mantener esta tabla cada año para su país.
insert into public.festivos (ambito, pais, fecha, nombre) values
  ('PAIS', 'España', '2027-01-01', 'Año Nuevo'),
  ('PAIS', 'España', '2027-01-06', 'Epifanía del Señor'),
  ('PAIS', 'España', '2027-03-26', 'Viernes Santo'),
  ('PAIS', 'España', '2027-05-01', 'Fiesta del Trabajo'),
  ('PAIS', 'España', '2027-08-15', 'Asunción de la Virgen'),
  ('PAIS', 'España', '2027-10-12', 'Fiesta Nacional de España'),
  ('PAIS', 'España', '2027-11-01', 'Todos los Santos'),
  ('PAIS', 'España', '2027-12-06', 'Día de la Constitución'),
  ('PAIS', 'España', '2027-12-08', 'Inmaculada Concepción'),
  ('PAIS', 'España', '2027-12-25', 'Natividad del Señor')
on conflict do nothing;

-- Permisos de ejecución
revoke all on function public.validar_baja_estructura() from public, anon;
revoke all on function public.sustituir_sensor(uuid, jsonb, uuid) from public, anon;
revoke all on function public.sustituir_dispositivo(uuid, varchar, varchar) from public, anon;
revoke all on function public.sustituir_modelo_3d(uuid, text, varchar, varchar, boolean) from public, anon;
revoke all on function public.confirmar_coordenadas(uuid, uuid[]) from public, anon;
revoke all on function public.es_festivo(uuid, date) from public, anon;
revoke all on function public.generar_calendario(uuid, integer, boolean, boolean) from public, anon;
revoke all on function public.generar_calendarios_anio_siguiente(date) from public, anon, authenticated;
grant execute on function public.sustituir_sensor(uuid, jsonb, uuid) to authenticated, service_role;
grant execute on function public.sustituir_dispositivo(uuid, varchar, varchar) to authenticated, service_role;
grant execute on function public.sustituir_modelo_3d(uuid, text, varchar, varchar, boolean) to authenticated, service_role;
grant execute on function public.confirmar_coordenadas(uuid, uuid[]) to authenticated, service_role;
grant execute on function public.es_festivo(uuid, date) to authenticated, service_role;
grant execute on function public.generar_calendario(uuid, integer, boolean, boolean) to authenticated, service_role;
grant execute on function public.generar_calendarios_anio_siguiente(date) to service_role;

commit;
