-- =========================================================
-- 031 · Edición de usuarios
-- Decisión D38 (27/10/2026): pantalla "Editar usuario".
--   - Se modifican nombre, apellidos, teléfono, rol y asignaciones.
--   - El rol solo cambia dentro del mismo tipo: plataforma, Partner (administrador ↔ técnico)
--     o cliente (usuario ↔ avanzado ↔ solo lectura). Para cambiar de tipo: baja y alta nueva.
--   - El Partner de un usuario de Partner no cambia. El email tampoco (es la cuenta de acceso).
--   - Mismas reglas que el alta (comprobar_alta_usuario) y la gestión (puede_gestionar_usuario).
--   - Sobre uno mismo solo se cambian los datos personales, nunca el rol ni las asignaciones.
-- Solo la API (service_role) la usa, después de comprobar la sesión del usuario.
-- =========================================================
begin;

create or replace function private.tipo_rol(p_rol text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_rol = 'ADMIN_SAAS' then 'PLATAFORMA'
    when p_rol in ('ADMIN_PARTNER', 'TECNICO_PARTNER') then 'PARTNER'
    else 'CLIENTE'
  end;
$$;

create or replace function public.modificar_usuario(
  p_id_creador uuid,
  p_id_usuario uuid,
  p_nombre text,
  p_apellidos text,
  p_telefono text,
  p_rol text default null,             -- null = no cambia
  p_alcance text default null,         -- null = asignaciones sin cambios
  p_ids_clientes uuid[] default null,
  p_ids_edificios uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_activo boolean;
  v_rol_actual text;
  v_rol text;
  v_tipo text;
  v_partner uuid;
  v_alcance text;
  v_clientes uuid[];
  v_edificios uuid[];
begin
  select u.activo, r.codigo into v_activo, v_rol_actual
  from public.usuarios u join public.roles r on r.id = u.id_rol
  where u.id = p_id_usuario;
  if v_rol_actual is null then
    raise exception 'El usuario no existe';
  end if;
  if not v_activo then
    raise exception 'El usuario está dado de baja: reactívelo antes de modificarlo';
  end if;
  if not private.usuario_con_permiso(p_id_creador, 'MODIFICAR_USUARIO') then
    raise exception 'Sin permiso para modificar usuarios' using errcode = '42501';
  end if;
  if coalesce(pg_catalog.btrim(p_nombre), '') = '' then
    raise exception 'El nombre es obligatorio';
  end if;

  v_rol := coalesce(p_rol, v_rol_actual);
  v_tipo := private.tipo_rol(v_rol_actual);

  if p_id_creador = p_id_usuario then
    if v_rol <> v_rol_actual or p_alcance is not null then
      raise exception 'No puede cambiar su propio rol ni sus asignaciones' using errcode = '42501';
    end if;
  else
    if not private.puede_gestionar_usuario(p_id_creador, p_id_usuario) then
      raise exception 'Sin permiso para gestionar este usuario' using errcode = '42501';
    end if;
    if private.tipo_rol(v_rol) <> v_tipo then
      raise exception 'El rol solo puede cambiar dentro del mismo tipo de usuario: para otro tipo, dé de baja este usuario y cree uno nuevo';
    end if;

    -- Asignación resultante: la indicada o la actual
    if v_tipo = 'PARTNER' then
      select pg_catalog.min(up.id_proveedor::text)::uuid, pg_catalog.min(up.tipo_alcance)
        into v_partner, v_alcance
      from public.usuarios_partners up
      where up.id_usuario = p_id_usuario and up.activo;
      if (select count(*) from public.usuarios_partners
          where id_usuario = p_id_usuario and activo) > 1 then
        raise exception 'El usuario está asignado a varios Partners: no se puede editar desde aquí';
      end if;
    elsif v_tipo = 'CLIENTE' then
      select pg_catalog.array_agg(uc.id_cliente), pg_catalog.min(uc.tipo_alcance)
        into v_clientes, v_alcance
      from public.usuarios_clientes uc
      where uc.id_usuario = p_id_usuario and uc.activo;
    end if;
    v_alcance := coalesce(v_alcance, 'MASTER');
    select pg_catalog.array_agg(ue.id_edificio) into v_edificios
    from public.usuarios_edificios ue
    where ue.id_usuario = p_id_usuario and ue.activo;

    if p_alcance is not null then
      v_alcance := p_alcance;
      v_edificios := case when p_alcance = 'RESTRINGIDO' then p_ids_edificios else null end;
      if v_tipo = 'CLIENTE' then
        v_clientes := p_ids_clientes;
      end if;
    end if;

    -- Las mismas reglas que el alta: lo que quien edita puede asignar
    perform private.comprobar_alta_usuario(
      p_id_creador, v_rol, v_partner,
      case when v_tipo = 'PLATAFORMA' then 'MASTER' else v_alcance end,
      v_clientes, v_edificios);
  end if;

  update public.usuarios u
     set nombre = pg_catalog.btrim(p_nombre),
         apellidos = nullif(pg_catalog.btrim(p_apellidos), ''),
         telefono = nullif(pg_catalog.btrim(p_telefono), ''),
         id_rol = (select r.id from public.roles r where r.codigo = v_rol)
   where u.id = p_id_usuario;

  if p_alcance is not null and p_id_creador <> p_id_usuario and v_tipo <> 'PLATAFORMA' then
    if v_tipo = 'PARTNER' then
      update public.usuarios_partners set tipo_alcance = v_alcance
       where id_usuario = p_id_usuario and activo and tipo_alcance <> v_alcance;
    else
      update public.usuarios_clientes
         set activo = false, fecha_fin = greatest(current_date, fecha_inicio)
       where id_usuario = p_id_usuario and activo and not (id_cliente = any (v_clientes));
      update public.usuarios_clientes set tipo_alcance = v_alcance
       where id_usuario = p_id_usuario and activo and tipo_alcance <> v_alcance;
      insert into public.usuarios_clientes (id_usuario, id_cliente, tipo_alcance)
      select p_id_usuario, c, v_alcance
      from pg_catalog.unnest(v_clientes) c
      where not exists (select 1 from public.usuarios_clientes uc
                        where uc.id_usuario = p_id_usuario and uc.id_cliente = c and uc.activo);
    end if;

    update public.usuarios_edificios
       set activo = false, fecha_fin = greatest(current_date, fecha_inicio)
     where id_usuario = p_id_usuario and activo
       and not (id_edificio = any (coalesce(v_edificios, '{}')));
    insert into public.usuarios_edificios (id_usuario, id_edificio)
    select p_id_usuario, e
    from pg_catalog.unnest(coalesce(v_edificios, '{}')) e
    where not exists (select 1 from public.usuarios_edificios ue
                      where ue.id_usuario = p_id_usuario and ue.id_edificio = e and ue.activo);
  end if;

  return p_id_usuario;
end;
$$;

revoke all on function private.tipo_rol(text) from public, anon;
grant execute on function private.tipo_rol(text) to authenticated, service_role;
revoke all on function public.modificar_usuario(uuid, uuid, text, text, text, text, text, uuid[], uuid[])
  from public, anon, authenticated;
grant execute on function public.modificar_usuario(uuid, uuid, text, text, text, text, text, uuid[], uuid[])
  to service_role;

commit;
