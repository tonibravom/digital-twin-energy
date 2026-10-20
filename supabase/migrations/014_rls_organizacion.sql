begin;

alter table public.proveedores enable row level security;
alter table public.clientes enable row level security;
alter table public.proveedores_clientes enable row level security;
alter table public.edificios enable row level security;
alter table public.proveedores_edificios enable row level security;

-- =========================================================
-- PROVEEDORES
-- =========================================================

drop policy if exists proveedores_select on public.proveedores;
create policy proveedores_select
on public.proveedores
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or exists (
    select 1
    from public.usuarios_partners up
    where up.id_proveedor = proveedores.id
      and up.id_usuario = private.usuario_actual()
      and up.activo
      and up.fecha_inicio <= current_date
      and (up.fecha_fin is null or up.fecha_fin >= current_date)
  )
);

drop policy if exists proveedores_insert on public.proveedores;
create policy proveedores_insert
on public.proveedores
for insert to authenticated
with check (private.usuario_tiene_rol('ADMIN_SAAS'));

drop policy if exists proveedores_update on public.proveedores;
create policy proveedores_update
on public.proveedores
for update to authenticated
using (private.usuario_tiene_rol('ADMIN_SAAS'))
with check (private.usuario_tiene_rol('ADMIN_SAAS'));

-- =========================================================
-- CLIENTES
-- =========================================================

drop policy if exists clientes_select on public.clientes;
create policy clientes_select
on public.clientes
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_tiene_acceso_cliente(id)
);

-- El alta por partner se hace mediante crear_cliente_partner().
-- Se evita que el partner inserte un cliente aislado sin relación.
drop policy if exists clientes_insert on public.clientes;
create policy clientes_insert
on public.clientes
for insert to authenticated
with check (private.usuario_tiene_rol('ADMIN_SAAS'));

drop policy if exists clientes_update on public.clientes;
create policy clientes_update
on public.clientes
for update to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_puede_cliente(id, 'MODIFICAR_CLIENTE')
)
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_puede_cliente(id, 'MODIFICAR_CLIENTE')
);

-- =========================================================
-- ALTA TRANSACCIONAL DE CLIENTE PARA UN PARTNER
-- Crea cliente y relación activa en una única transacción.
-- =========================================================

create or replace function public.crear_cliente_partner(
  p_codigo varchar,
  p_nombre varchar,
  p_cif varchar default null,
  p_email varchar default null,
  p_telefono varchar default null,
  p_descripcion text default null,
  p_id_proveedor uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario uuid;
  v_proveedor uuid;
  v_cliente uuid;
begin
  v_usuario := private.usuario_actual();

  if v_usuario is null then
    raise exception 'Usuario no autenticado o inactivo'
      using errcode = '42501';
  end if;

  if not private.usuario_tiene_permiso('CREAR_CLIENTE') then
    raise exception 'El usuario no tiene permiso para crear clientes'
      using errcode = '42501';
  end if;

  -- Solo un usuario MASTER de un partner activo puede dar de alta
  -- clientes desde el portal del partner.
  select up.id_proveedor
    into v_proveedor
  from public.usuarios_partners up
  join public.proveedores p
    on p.id = up.id_proveedor
  where up.id_usuario = v_usuario
    and (p_id_proveedor is null or up.id_proveedor = p_id_proveedor)
    and up.tipo_alcance = 'MASTER'
    and up.activo
    and up.fecha_inicio <= current_date
    and (up.fecha_fin is null or up.fecha_fin >= current_date)
    and p.activo
    and p.fecha_baja is null
  order by up.fecha_inicio desc
  limit 1;

  if v_proveedor is null then
    raise exception 'No existe una asignación MASTER activa de partner'
      using errcode = '42501';
  end if;

  if p_id_proveedor is null and (
    select count(*) from public.usuarios_partners up2
    where up2.id_usuario = v_usuario and up2.activo and up2.tipo_alcance = 'MASTER'
  ) > 1 then
    raise exception 'El usuario pertenece a varios partners: indique p_id_proveedor'
      using errcode = '22023';
  end if;

  if p_codigo is null or btrim(p_codigo) = ''
     or p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El código y el nombre del cliente son obligatorios'
      using errcode = '22023';
  end if;

  insert into public.clientes (
    codigo,
    nombre,
    cif,
    email,
    telefono,
    descripcion
  )
  values (
    btrim(p_codigo),
    btrim(p_nombre),
    nullif(btrim(p_cif), ''),
    nullif(btrim(p_email), ''),
    nullif(btrim(p_telefono), ''),
    nullif(btrim(p_descripcion), '')
  )
  returning id into v_cliente;

  insert into public.proveedores_clientes (
    id_proveedor,
    id_cliente,
    fecha_inicio,
    activo
  )
  values (
    v_proveedor,
    v_cliente,
    current_date,
    true
  );

  return v_cliente;
end;
$$;

revoke all on function public.crear_cliente_partner(
  varchar, varchar, varchar, varchar, varchar, text, uuid
) from public, anon;

grant execute on function public.crear_cliente_partner(
  varchar, varchar, varchar, varchar, varchar, text, uuid
) to authenticated;

-- =========================================================
-- RELACIÓN PROVEEDOR-CLIENTE
-- Solo ADMIN_SAAS puede crear, cambiar o cerrar la relación.
-- =========================================================

drop policy if exists proveedores_clientes_select
  on public.proveedores_clientes;
create policy proveedores_clientes_select
on public.proveedores_clientes
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_acceso_cliente(id_cliente)
    and exists (
      select 1
      from public.usuarios_partners up
      where up.id_usuario = private.usuario_actual()
        and up.id_proveedor = proveedores_clientes.id_proveedor
        and up.activo
        and up.fecha_inicio <= current_date
        and (up.fecha_fin is null or up.fecha_fin >= current_date)
    )
  )
);

drop policy if exists proveedores_clientes_insert
  on public.proveedores_clientes;
create policy proveedores_clientes_insert
on public.proveedores_clientes
for insert to authenticated
with check (private.usuario_tiene_rol('ADMIN_SAAS'));

drop policy if exists proveedores_clientes_update
  on public.proveedores_clientes;
create policy proveedores_clientes_update
on public.proveedores_clientes
for update to authenticated
using (private.usuario_tiene_rol('ADMIN_SAAS'))
with check (private.usuario_tiene_rol('ADMIN_SAAS'));

-- =========================================================
-- EDIFICIOS
-- =========================================================

drop policy if exists edificios_select on public.edificios;
create policy edificios_select
on public.edificios
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_tiene_acceso_edificio(id)
);

drop policy if exists edificios_insert on public.edificios;
create policy edificios_insert
on public.edificios
for insert to authenticated
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_permiso('CREAR_EDIFICIO')
    and private.usuario_tiene_acceso_cliente(id_cliente)
  )
);

drop policy if exists edificios_update on public.edificios;
create policy edificios_update
on public.edificios
for update to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or private.usuario_puede_edificio(id, 'MODIFICAR_EDIFICIO')
)
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_permiso('MODIFICAR_EDIFICIO')
    and private.usuario_tiene_acceso_cliente(id_cliente)
  )
);

-- =========================================================
-- RELACIÓN PROVEEDOR-EDIFICIO
-- Un partner solo puede asignar a su proveedor edificios de
-- clientes ya vinculados a ese proveedor. La unicidad activa
-- de la migración 001 impide una segunda asignación activa.
-- =========================================================

drop policy if exists proveedores_edificios_select
  on public.proveedores_edificios;
create policy proveedores_edificios_select
on public.proveedores_edificios
for select to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_acceso_edificio(id_edificio)
    and exists (
      select 1
      from public.usuarios_partners up
      where up.id_usuario = private.usuario_actual()
        and up.id_proveedor = proveedores_edificios.id_proveedor
        and up.activo
        and up.fecha_inicio <= current_date
        and (up.fecha_fin is null or up.fecha_fin >= current_date)
    )
  )
);

drop policy if exists proveedores_edificios_insert
  on public.proveedores_edificios;
create policy proveedores_edificios_insert
on public.proveedores_edificios
for insert to authenticated
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
  or (
    private.usuario_tiene_permiso('CREAR_EDIFICIO')
    and exists (
      select 1
      from public.usuarios_partners up
      where up.id_usuario = private.usuario_actual()
        and up.id_proveedor = proveedores_edificios.id_proveedor
        and up.activo
        and up.fecha_inicio <= current_date
        and (up.fecha_fin is null or up.fecha_fin >= current_date)
    )
    and exists (
      select 1
      from public.edificios e
      join public.proveedores_clientes pc
        on pc.id_cliente = e.id_cliente
       and pc.id_proveedor = proveedores_edificios.id_proveedor
      where e.id = proveedores_edificios.id_edificio
        and pc.activo
        and pc.fecha_inicio <= current_date
        and (pc.fecha_fin is null or pc.fecha_fin >= current_date)
    )
  )
);

drop policy if exists proveedores_edificios_update
  on public.proveedores_edificios;
create policy proveedores_edificios_update
on public.proveedores_edificios
for update to authenticated
using (
  private.usuario_tiene_rol('ADMIN_SAAS')
)
with check (
  private.usuario_tiene_rol('ADMIN_SAAS')
);

-- =========================================================
-- ALTA TRANSACCIONAL DE EDIFICIO PARA UN PARTNER
-- Crea el edificio y su asignación al partner en una única
-- transacción (un insert directo no sería visible después
-- para el partner, porque aún no tendría asignación).
-- =========================================================
create or replace function public.crear_edificio_partner(
  p_id_cliente uuid,
  p_codigo varchar,
  p_nombre varchar,
  p_id_proveedor uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario uuid;
  v_proveedor uuid;
  v_edificio uuid;
begin
  v_usuario := private.usuario_actual();

  if v_usuario is null then
    raise exception 'Usuario no autenticado o inactivo' using errcode = '42501';
  end if;

  if not private.usuario_puede_cliente(p_id_cliente, 'CREAR_EDIFICIO') then
    raise exception 'Sin permiso para crear edificios de este cliente' using errcode = '42501';
  end if;

  if p_codigo is null or btrim(p_codigo) = '' or p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El código y el nombre del edificio son obligatorios' using errcode = '22023';
  end if;

  -- Partner del usuario vinculado activamente a ese cliente.
  select up.id_proveedor into v_proveedor
  from public.usuarios_partners up
  join public.proveedores_clientes pc
    on pc.id_proveedor = up.id_proveedor
   and pc.id_cliente = p_id_cliente
   and pc.activo
  where up.id_usuario = v_usuario
    and up.activo
    and up.tipo_alcance = 'MASTER'
    and (p_id_proveedor is null or up.id_proveedor = p_id_proveedor)
  order by up.fecha_inicio desc
  limit 1;

  if v_proveedor is null and not private.usuario_tiene_rol('ADMIN_SAAS') then
    raise exception 'No existe un partner MASTER del usuario vinculado a este cliente'
      using errcode = '42501';
  end if;

  insert into public.edificios (id_cliente, codigo, nombre)
  values (p_id_cliente, btrim(p_codigo), btrim(p_nombre))
  returning id into v_edificio;

  if v_proveedor is not null then
    insert into public.proveedores_edificios (id_proveedor, id_edificio)
    values (v_proveedor, v_edificio);
  end if;

  return v_edificio;
end;
$$;

revoke all on function public.crear_edificio_partner(uuid, varchar, varchar, uuid) from public, anon;
grant execute on function public.crear_edificio_partner(uuid, varchar, varchar, uuid) to authenticated;

-- =========================================================
-- PROTECCIÓN DE COLUMNAS SENSIBLES
-- RLS decide QUÉ filas; estos triggers impiden cambios que
-- requieren permisos distintos del de "modificar".
-- El backend con service_role (sin auth.uid()) no se limita.
-- =========================================================
create or replace function private.proteger_cambios_organizacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or private.usuario_tiene_rol('ADMIN_SAAS') then
    return new;
  end if;

  if tg_table_name = 'edificios' then
    if new.id_cliente is distinct from old.id_cliente then
      raise exception 'Solo el administrador de la plataforma puede cambiar el cliente de un edificio'
        using errcode = '42501';
    end if;
    if new.estado = 'BAJA' and old.estado <> 'BAJA'
       and not private.usuario_tiene_permiso('DAR_BAJA_EDIFICIO') then
      raise exception 'Sin permiso para dar de baja edificios' using errcode = '42501';
    end if;
  elsif tg_table_name = 'clientes' then
    if new.estado = 'BAJA' and old.estado <> 'BAJA'
       and not private.usuario_tiene_permiso('DAR_BAJA_CLIENTE') then
      raise exception 'Sin permiso para dar de baja clientes' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.proteger_cambios_organizacion() from public, anon;

drop trigger if exists trg_edificios_proteger on public.edificios;
create trigger trg_edificios_proteger
before update on public.edificios
for each row execute function private.proteger_cambios_organizacion();

drop trigger if exists trg_clientes_proteger on public.clientes;
create trigger trg_clientes_proteger
before update on public.clientes
for each row execute function private.proteger_cambios_organizacion();

-- =========================================================
-- ROLES, PERMISOS Y USUARIOS
-- Lectura según alcance. Sin políticas de escritura: las altas,
-- cambios de rol y asignaciones se hacen desde el backend
-- (service_role), que además crea el usuario en Supabase Auth.
-- Esto impide que un usuario se asigne roles o alcance a sí mismo.
-- =========================================================
drop policy if exists roles_select on public.roles;
create policy roles_select on public.roles
for select to authenticated using (true);

drop policy if exists permisos_select on public.permisos;
create policy permisos_select on public.permisos
for select to authenticated using (true);

drop policy if exists roles_permisos_select on public.roles_permisos;
create policy roles_permisos_select on public.roles_permisos
for select to authenticated using (true);

-- ¿Puede el usuario actual ver al usuario indicado?
create or replace function private.usuario_visible(p_id_usuario uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_id_usuario = private.usuario_actual()
    or private.usuario_tiene_rol('ADMIN_SAAS')
    or (
      private.usuario_tiene_permiso('VER_USUARIOS')
      and (
        exists (
          select 1 from public.usuarios_partners up_obj
          join public.usuarios_partners up_yo
            on up_yo.id_proveedor = up_obj.id_proveedor
           and up_yo.id_usuario = private.usuario_actual()
           and up_yo.activo and up_yo.tipo_alcance = 'MASTER'
          where up_obj.id_usuario = p_id_usuario and up_obj.activo
        )
        or exists (
          select 1 from public.usuarios_clientes uc
          where uc.id_usuario = p_id_usuario and uc.activo
            and private.usuario_tiene_acceso_cliente(uc.id_cliente)
        )
        or exists (
          select 1 from public.usuarios_edificios ue
          where ue.id_usuario = p_id_usuario and ue.activo
            and private.usuario_tiene_acceso_edificio(ue.id_edificio)
        )
      )
    );
$$;

revoke all on function private.usuario_visible(uuid) from public, anon;
grant execute on function private.usuario_visible(uuid) to authenticated;

drop policy if exists usuarios_select on public.usuarios;
create policy usuarios_select on public.usuarios
for select to authenticated
using (private.usuario_visible(id));

drop policy if exists usuarios_partners_select on public.usuarios_partners;
create policy usuarios_partners_select on public.usuarios_partners
for select to authenticated
using (private.usuario_visible(id_usuario));

drop policy if exists usuarios_clientes_select on public.usuarios_clientes;
create policy usuarios_clientes_select on public.usuarios_clientes
for select to authenticated
using (
  private.usuario_visible(id_usuario)
  and (
    id_usuario = private.usuario_actual()
    or private.usuario_tiene_acceso_cliente(id_cliente)
  )
);

drop policy if exists usuarios_edificios_select on public.usuarios_edificios;
create policy usuarios_edificios_select on public.usuarios_edificios
for select to authenticated
using (
  private.usuario_visible(id_usuario)
  and (
    id_usuario = private.usuario_actual()
    or private.usuario_tiene_acceso_edificio(id_edificio)
  )
);

-- El rol anónimo no tiene ningún acceso a tablas de la aplicación.
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

commit;