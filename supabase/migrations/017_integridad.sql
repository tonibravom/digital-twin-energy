begin;

-- =========================================================
-- INTEGRIDAD ENTRE ENTIDADES
-- Complementa las validaciones de 002, 003, 005, 007 y 008.
-- Regla general: toda relación debe quedar dentro del mismo
-- edificio, aunque RLS ya filtre por usuario.
-- =========================================================

-- 1. Suministro y dispositivo del mismo edificio.
create or replace function public.validar_suministro_dispositivo()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_dispositivo uuid;
  v_edificio_suministro uuid;
begin
  select public.obtener_edificio_recinto(d.id_recinto)
    into v_edificio_dispositivo
  from public.dispositivos d
  where d.id = new.id_dispositivo;

  select s.id_edificio into v_edificio_suministro
  from public.suministros s
  where s.id = new.id_suministro;

  if v_edificio_dispositivo is null then
    raise exception 'El dispositivo o su recinto/planta no existen';
  end if;
  if v_edificio_suministro is null then
    raise exception 'El suministro no existe';
  end if;
  if v_edificio_dispositivo <> v_edificio_suministro then
    raise exception 'El dispositivo y el suministro deben pertenecer al mismo edificio';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_suministro_dispositivo on public.suministros_dispositivos;
create trigger trg_validar_suministro_dispositivo
before insert or update of id_dispositivo, id_suministro
on public.suministros_dispositivos
for each row execute function public.validar_suministro_dispositivo();

-- 2. Recinto de una regla de alarma en el edificio de la regla.
create or replace function public.validar_regla_alarma_recinto()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_regla uuid;
  v_edificio_recinto uuid;
begin
  select ra.id_edificio into v_edificio_regla
  from public.reglas_alarma ra where ra.id = new.id_regla_alarma;

  v_edificio_recinto := public.obtener_edificio_recinto(new.id_recinto);

  if v_edificio_regla is null then
    raise exception 'La regla de alarma no existe';
  end if;
  if v_edificio_recinto is null then
    raise exception 'El recinto de la regla de alarma no existe';
  end if;
  if v_edificio_regla <> v_edificio_recinto then
    raise exception 'La regla de alarma y el recinto deben pertenecer al mismo edificio';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_regla_alarma_recinto on public.reglas_alarma_recintos;
create trigger trg_validar_regla_alarma_recinto
before insert or update of id_regla_alarma, id_recinto
on public.reglas_alarma_recintos
for each row execute function public.validar_regla_alarma_recinto();

-- 3. Un usuario destinatario de una regla debe tener acceso al edificio.
create or replace function private.usuario_alcanza_edificio(
  p_id_usuario uuid,
  p_id_edificio uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.usuarios u
    join public.roles r on r.id = u.id_rol
    where u.id = p_id_usuario and u.activo and r.codigo = 'ADMIN_SAAS'
  )
  or exists (
    select 1 from public.usuarios_edificios ue
    where ue.id_usuario = p_id_usuario and ue.id_edificio = p_id_edificio and ue.activo
  )
  or exists (
    select 1 from public.usuarios_clientes uc
    join public.edificios e on e.id_cliente = uc.id_cliente
    where uc.id_usuario = p_id_usuario and e.id = p_id_edificio
      and uc.activo and uc.tipo_alcance = 'MASTER'
  )
  or exists (
    select 1 from public.usuarios_partners up
    join public.proveedores_edificios pe on pe.id_proveedor = up.id_proveedor
    where up.id_usuario = p_id_usuario and pe.id_edificio = p_id_edificio
      and up.activo and pe.activo and up.tipo_alcance = 'MASTER'
  );
$$;

revoke all on function private.usuario_alcanza_edificio(uuid, uuid) from public, anon;
grant execute on function private.usuario_alcanza_edificio(uuid, uuid) to authenticated;

create or replace function public.validar_regla_alarma_usuario()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  select ra.id_edificio into v_edificio
  from public.reglas_alarma ra where ra.id = new.id_regla_alarma;

  if v_edificio is null then
    raise exception 'La regla de alarma no existe';
  end if;

  if not private.usuario_alcanza_edificio(new.id_usuario, v_edificio) then
    raise exception 'El usuario destinatario no tiene acceso al edificio de la regla';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_regla_alarma_usuario on public.reglas_alarma_usuarios;
create trigger trg_validar_regla_alarma_usuario
before insert or update on public.reglas_alarma_usuarios
for each row execute function public.validar_regla_alarma_usuario();

-- 4. El partner asignado a un edificio debe estar vinculado al cliente.
create or replace function public.validar_proveedor_edificio()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.activo and not exists (
    select 1
    from public.edificios e
    join public.proveedores_clientes pc
      on pc.id_cliente = e.id_cliente
     and pc.id_proveedor = new.id_proveedor
     and pc.activo
    where e.id = new.id_edificio
  ) then
    raise exception 'El partner debe tener una relación activa con el cliente del edificio';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_proveedor_edificio on public.proveedores_edificios;
create trigger trg_validar_proveedor_edificio
before insert or update on public.proveedores_edificios
for each row execute function public.validar_proveedor_edificio();

-- 5. Histórico automático de ubicaciones físicas.
-- Al crear o mover un dispositivo/sensor se cierra la ubicación
-- vigente y se abre otra. Mover un dispositivo mueve sus sensores.
create or replace function public.registrar_ubicacion_fisica()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.id_recinto is not distinct from old.id_recinto then
    return null;
  end if;

  if tg_table_name = 'dispositivos' then
    update public.dispositivos_ubicaciones
       set fecha_fin = current_date
     where id_dispositivo = new.id and fecha_fin is null;

    insert into public.dispositivos_ubicaciones (id_dispositivo, id_recinto, fecha_inicio)
    values (new.id, new.id_recinto, current_date)
    on conflict (id_dispositivo, fecha_inicio)
    do update set id_recinto = excluded.id_recinto, fecha_fin = null;

    if tg_op = 'UPDATE' then
      update public.sensores
         set id_recinto = new.id_recinto
       where id_dispositivo = new.id
         and id_recinto <> new.id_recinto;
    end if;
  else
    update public.sensores_ubicaciones
       set fecha_fin = current_date
     where id_sensor = new.id and fecha_fin is null;

    insert into public.sensores_ubicaciones (id_sensor, id_recinto, fecha_inicio)
    values (new.id, new.id_recinto, current_date)
    on conflict (id_sensor, fecha_inicio)
    do update set id_recinto = excluded.id_recinto, fecha_fin = null;
  end if;

  return null;
end;
$$;

revoke all on function public.registrar_ubicacion_fisica() from public, anon, authenticated;

drop trigger if exists trg_dispositivos_ubicacion_historico on public.dispositivos;
create trigger trg_dispositivos_ubicacion_historico
after insert or update of id_recinto on public.dispositivos
for each row execute function public.registrar_ubicacion_fisica();

drop trigger if exists trg_sensores_ubicacion_historico on public.sensores;
create trigger trg_sensores_ubicacion_historico
after insert or update of id_recinto on public.sensores
for each row execute function public.registrar_ubicacion_fisica();

commit;
