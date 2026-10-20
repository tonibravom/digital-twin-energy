begin;

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.usuario_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.usuarios u
  where u.auth_user_id = (select auth.uid())
    and u.activo
    and u.fecha_baja is null
    and u.fecha_alta <= current_date
  limit 1;
$$;

create or replace function private.usuario_tiene_rol(p_rol text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    join public.roles r on r.id = u.id_rol
    where u.id = private.usuario_actual()
      and r.codigo = p_rol
      and r.activo
  );
$$;

create or replace function private.usuario_tiene_permiso(p_permiso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    join public.roles r on r.id = u.id_rol
    join public.roles_permisos rp on rp.id_rol = r.id
    join public.permisos p on p.id = rp.id_permiso
    where u.id = private.usuario_actual()
      and u.activo
      and r.activo
      and p.activo
      and p.codigo = p_permiso
  );
$$;

create or replace function private.usuario_tiene_acceso_cliente(
  p_id_cliente uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.usuario_tiene_rol('ADMIN_SAAS')
    or exists (
      select 1
      from public.usuarios_clientes uc
      where uc.id_usuario = private.usuario_actual()
        and uc.id_cliente = p_id_cliente
        and uc.activo
        and uc.fecha_inicio <= current_date
        and (uc.fecha_fin is null or uc.fecha_fin >= current_date)
        and (
          uc.tipo_alcance = 'MASTER'
          or exists (
            select 1
            from public.usuarios_edificios ue
            join public.edificios e
              on e.id = ue.id_edificio
            where ue.id_usuario = uc.id_usuario
              and e.id_cliente = uc.id_cliente
              and ue.activo
              and ue.fecha_inicio <= current_date
              and (ue.fecha_fin is null or ue.fecha_fin >= current_date)
          )
        )
    )
    or exists (
      select 1
      from public.usuarios_partners up
      join public.proveedores_clientes pc
        on pc.id_proveedor = up.id_proveedor
      join public.proveedores p
        on p.id = up.id_proveedor
      where up.id_usuario = private.usuario_actual()
        and up.activo
        and up.fecha_inicio <= current_date
        and (up.fecha_fin is null or up.fecha_fin >= current_date)
        and p.activo
        and p.fecha_baja is null
        and pc.id_cliente = p_id_cliente
        and pc.activo
        and pc.fecha_inicio <= current_date
        and (pc.fecha_fin is null or pc.fecha_fin >= current_date)
        and (
          up.tipo_alcance = 'MASTER'
          or exists (
            select 1
            from public.proveedores_edificios pe
            join public.edificios e
              on e.id = pe.id_edificio
            join public.usuarios_edificios ue
              on ue.id_edificio = e.id
             and ue.id_usuario = up.id_usuario
            where pe.id_proveedor = up.id_proveedor
              and e.id_cliente = p_id_cliente
              and pe.activo
              and pe.fecha_inicio <= current_date
              and (pe.fecha_fin is null or pe.fecha_fin >= current_date)
              and ue.activo
              and ue.fecha_inicio <= current_date
              and (ue.fecha_fin is null or ue.fecha_fin >= current_date)
          )
        )
    );
$$;

create or replace function private.usuario_tiene_acceso_edificio(
  p_id_edificio uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.usuario_tiene_rol('ADMIN_SAAS')

    or exists (
      select 1
      from public.edificios e
      join public.usuarios_clientes uc
        on uc.id_cliente = e.id_cliente
       and uc.id_usuario = private.usuario_actual()
      where e.id = p_id_edificio
        and uc.activo
        and uc.fecha_inicio <= current_date
        and (uc.fecha_fin is null or uc.fecha_fin >= current_date)
        and (
          uc.tipo_alcance = 'MASTER'
          or exists (
            select 1
            from public.usuarios_edificios ue
            where ue.id_usuario = uc.id_usuario
              and ue.id_edificio = e.id
              and ue.activo
              and ue.fecha_inicio <= current_date
              and (ue.fecha_fin is null or ue.fecha_fin >= current_date)
          )
        )
    )

    or exists (
      select 1
      from public.usuarios_edificios ue
      where ue.id_usuario = private.usuario_actual()
        and ue.id_edificio = p_id_edificio
        and ue.activo
        and ue.fecha_inicio <= current_date
        and (ue.fecha_fin is null or ue.fecha_fin >= current_date)
        and exists (
          select 1
          from public.usuarios u
          where u.id = ue.id_usuario
            and u.activo
            and u.fecha_baja is null
            and u.fecha_alta <= current_date
        )
    )

    or exists (
      select 1
      from public.usuarios_partners up
      join public.proveedores_edificios pe
        on pe.id_proveedor = up.id_proveedor
       and pe.id_edificio = p_id_edificio
      join public.proveedores_clientes pc
        on pc.id_proveedor = up.id_proveedor
      join public.edificios e
        on e.id = pe.id_edificio
       and e.id_cliente = pc.id_cliente
      join public.proveedores p
        on p.id = up.id_proveedor
      where up.id_usuario = private.usuario_actual()
        and up.activo
        and up.fecha_inicio <= current_date
        and (up.fecha_fin is null or up.fecha_fin >= current_date)
        and p.activo
        and p.fecha_baja is null
        and pe.activo
        and pe.fecha_inicio <= current_date
        and (pe.fecha_fin is null or pe.fecha_fin >= current_date)
        and pc.activo
        and pc.fecha_inicio <= current_date
        and (pc.fecha_fin is null or pc.fecha_fin >= current_date)
        and (
          up.tipo_alcance = 'MASTER'
          or exists (
            select 1
            from public.usuarios_edificios ue
            where ue.id_usuario = up.id_usuario
              and ue.id_edificio = p_id_edificio
              and ue.activo
              and ue.fecha_inicio <= current_date
              and (ue.fecha_fin is null or ue.fecha_fin >= current_date)
          )
        )
    );
$$;

create or replace function private.usuario_puede_edificio(
  p_id_edificio uuid,
  p_permiso text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.usuario_tiene_permiso(p_permiso)
     and private.usuario_tiene_acceso_edificio(p_id_edificio);
$$;

create or replace function private.usuario_puede_cliente(
  p_id_cliente uuid,
  p_permiso text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.usuario_tiene_permiso(p_permiso)
     and private.usuario_tiene_acceso_cliente(p_id_cliente);
$$;

-- ---------------------------------------------------------
-- Conjuntos accesibles, evaluados UNA vez por consulta.
-- Se usan en las tablas grandes (lecturas, valores_magnitud...)
-- con "columna in (select private.xxx())" para no ejecutar la
-- comprobación de acceso fila a fila.
-- ---------------------------------------------------------
create or replace function private.edificios_accesibles()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.id
  from public.edificios e
  where private.usuario_tiene_acceso_edificio(e.id);
$$;

create or replace function private.sensores_accesibles()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
  from public.sensores s
  join public.recintos r on r.id = s.id_recinto
  join public.plantas p on p.id = r.id_planta
  where p.id_edificio in (select private.edificios_accesibles());
$$;

revoke all on function private.edificios_accesibles() from public, anon;
revoke all on function private.sensores_accesibles() from public, anon;
grant execute on function private.edificios_accesibles() to authenticated;
grant execute on function private.sensores_accesibles() to authenticated;

revoke all on function private.usuario_actual() from public, anon;
revoke all on function private.usuario_tiene_rol(text) from public, anon;
revoke all on function private.usuario_tiene_permiso(text) from public, anon;
revoke all on function private.usuario_tiene_acceso_cliente(uuid) from public, anon;
revoke all on function private.usuario_tiene_acceso_edificio(uuid) from public, anon;
revoke all on function private.usuario_puede_edificio(uuid, text) from public, anon;
revoke all on function private.usuario_puede_cliente(uuid, text) from public, anon;

grant execute on function private.usuario_actual() to authenticated;
grant execute on function private.usuario_tiene_rol(text) to authenticated;
grant execute on function private.usuario_tiene_permiso(text) to authenticated;
grant execute on function private.usuario_tiene_acceso_cliente(uuid) to authenticated;
grant execute on function private.usuario_tiene_acceso_edificio(uuid) to authenticated;
grant execute on function private.usuario_puede_edificio(uuid, text) to authenticated;
grant execute on function private.usuario_puede_cliente(uuid, text) to authenticated;

commit;