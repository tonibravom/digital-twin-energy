-- =========================================================
-- 027 · Alta de usuarios, contraseña inicial y doble factor por email
-- Decisiones D27–D30 (26/10/2026):
--   - El administrador de la plataforma y el Partner (administrador y técnico)
--     dan de alta usuarios con email y contraseña inicial. Sin invitaciones.
--   - La contraseña inicial se cambia obligatoriamente en la primera entrada.
--   - Doble factor: código de 6 cifras enviado por email. Obligatorio por rol
--     (roles.requiere_doble_factor) y voluntario para el resto (usuarios.doble_factor).
--   - Mientras falte un paso, private.usuario_actual() no reconoce al usuario:
--     RLS le niega todos los datos aunque se salte la interfaz.
-- La API (service_role) crea la cuenta en Supabase Auth, envía los códigos y
-- llama a las funciones de este archivo. El navegador nunca escribe usuarios.
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Columnas nuevas
-- ---------------------------------------------------------
alter table public.roles
  add column if not exists requiere_doble_factor boolean not null default false;

comment on column public.roles.requiere_doble_factor is
  'Si es true, los usuarios con este rol deben verificar un código enviado por email en cada sesión.';

update public.roles set requiere_doble_factor = true
where codigo in ('ADMIN_SAAS', 'ADMIN_PARTNER');

alter table public.usuarios
  add column if not exists debe_cambiar_contrasena boolean not null default false,
  add column if not exists doble_factor boolean not null default false;

comment on column public.usuarios.debe_cambiar_contrasena is
  'true al darse de alta o al restablecer la contraseña: hasta que la cambie no accede a ningún dato.';
comment on column public.usuarios.doble_factor is
  'Doble factor activado voluntariamente por el usuario (además del que exija su rol).';

-- ---------------------------------------------------------
-- 2. Códigos de verificación (solo la API los lee y escribe)
-- ---------------------------------------------------------
create table if not exists public.codigos_verificacion (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  id_sesion uuid not null,
  codigo_hash text not null,
  expira_at timestamptz not null,
  intentos smallint not null default 0,
  verificado_at timestamptz,
  anulado boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.codigos_verificacion is
  'Códigos de doble factor enviados por email, ligados a una sesión de Supabase Auth (claim session_id). Se guardan cifrados (hash).';

create index if not exists ix_codigos_verificacion_sesion
  on public.codigos_verificacion(auth_user_id, id_sesion, created_at desc);

create index if not exists ix_codigos_verificacion_verificados
  on public.codigos_verificacion(auth_user_id, id_sesion)
  where verificado_at is not null;

alter table public.codigos_verificacion enable row level security;
-- Sin políticas: ningún usuario los ve. Solo service_role (y funciones security definer).
revoke all on public.codigos_verificacion from anon, authenticated;

-- ---------------------------------------------------------
-- 3. Usuario actual: exige contraseña cambiada y, si aplica, doble factor
-- ---------------------------------------------------------
create or replace function private.sesion_verificada(p_auth_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt()) ->> 'aal', '') = 'aal2'   -- por si se usa MFA nativo de Supabase
      or exists (
        select 1 from public.codigos_verificacion v
        where v.auth_user_id = p_auth_user_id
          and v.id_sesion = nullif((select auth.jwt()) ->> 'session_id', '')::uuid
          and v.verificado_at is not null
      );
$$;

create or replace function private.usuario_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.usuarios u
  join public.roles r on r.id = u.id_rol
  where u.auth_user_id = (select auth.uid())
    and u.activo
    and u.fecha_baja is null
    and u.fecha_alta <= current_date
    and not u.debe_cambiar_contrasena
    and (not (r.requiere_doble_factor or u.doble_factor)
         or private.sesion_verificada(u.auth_user_id))
  limit 1;
$$;

revoke all on function private.sesion_verificada(uuid) from public, anon;
grant execute on function private.sesion_verificada(uuid) to authenticated;

-- ---------------------------------------------------------
-- 4. Mi cuenta: lo que la interfaz necesita para guiar la entrada
-- (funciona aunque falte un paso, por eso no usa usuario_actual)
-- ---------------------------------------------------------
create or replace function public.mi_cuenta()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', u.id,
    'nombre', u.nombre,
    'apellidos', u.apellidos,
    'email', u.email,
    'rol', r.codigo,
    'rol_nombre', r.nombre,
    'debe_cambiar_contrasena', u.debe_cambiar_contrasena,
    'requiere_doble_factor', r.requiere_doble_factor or u.doble_factor,
    'doble_factor_obligatorio', r.requiere_doble_factor,
    'doble_factor_verificado', private.sesion_verificada(u.auth_user_id),
    'acceso_completo', private.usuario_actual() is not null)
  from public.usuarios u
  join public.roles r on r.id = u.id_rol
  where u.auth_user_id = (select auth.uid())
    and u.activo
    and u.fecha_baja is null;
$$;

-- ---------------------------------------------------------
-- 5. Reglas de quién da de alta / gestiona a quién
-- ---------------------------------------------------------
create or replace function private.rol_usuario(p_id_usuario uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select r.codigo from public.usuarios u join public.roles r on r.id = u.id_rol where u.id = p_id_usuario;
$$;

create or replace function private.usuario_con_permiso(p_id_usuario uuid, p_permiso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    join public.roles r on r.id = u.id_rol and r.activo
    join public.roles_permisos rp on rp.id_rol = r.id
    join public.permisos p on p.id = rp.id_permiso and p.activo
    where u.id = p_id_usuario and u.activo and p.codigo = p_permiso);
$$;

-- Partners activos a los que pertenece un usuario
create or replace function private.partners_de_usuario(p_id_usuario uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select up.id_proveedor
  from public.usuarios_partners up
  join public.proveedores p on p.id = up.id_proveedor and p.activo
  where up.id_usuario = p_id_usuario and up.activo
    and up.fecha_inicio <= current_date and (up.fecha_fin is null or up.fecha_fin >= current_date);
$$;

create or replace function private.comprobar_alta_usuario(
  p_id_creador uuid,
  p_rol text,
  p_id_proveedor uuid,
  p_alcance text,
  p_ids_clientes uuid[],
  p_ids_edificios uuid[]
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rol_creador text := private.rol_usuario(p_id_creador);
  v_es_partner_destino boolean := p_rol in ('ADMIN_PARTNER', 'TECNICO_PARTNER');
  v_clientes uuid[] := coalesce(p_ids_clientes, '{}');
  v_edificios uuid[] := coalesce(p_ids_edificios, '{}');
begin
  if v_rol_creador is null or not private.usuario_con_permiso(p_id_creador, 'CREAR_USUARIO') then
    raise exception 'Sin permiso para dar de alta usuarios' using errcode = '42501';
  end if;

  if not exists (select 1 from public.roles where codigo = p_rol and activo) then
    raise exception 'Rol desconocido: %', p_rol;
  end if;

  if p_alcance not in ('MASTER', 'RESTRINGIDO') then
    raise exception 'Alcance no válido: use MASTER o RESTRINGIDO';
  end if;

  -- Coherencia de lo que se asigna según el rol
  if p_rol = 'ADMIN_SAAS' then
    if p_id_proveedor is not null or pg_catalog.cardinality(v_clientes) > 0 or pg_catalog.cardinality(v_edificios) > 0 then
      raise exception 'Un administrador de la plataforma no se asigna a Partners, clientes ni edificios';
    end if;
  elsif v_es_partner_destino then
    if p_id_proveedor is null or pg_catalog.cardinality(v_clientes) > 0 then
      raise exception 'Un usuario de Partner se asigna a un Partner (y, si es restringido, a edificios), no a clientes';
    end if;
    if not exists (select 1 from public.proveedores where id = p_id_proveedor and activo) then
      raise exception 'El Partner no existe o está dado de baja';
    end if;
  else
    if p_id_proveedor is not null or pg_catalog.cardinality(v_clientes) = 0 then
      raise exception 'Un usuario de cliente se asigna al menos a un cliente';
    end if;
    if exists (select 1 from pg_catalog.unnest(v_clientes) c(id)
               where not exists (select 1 from public.clientes cl where cl.id = c.id and cl.activo)) then
      raise exception 'Algún cliente no existe o está dado de baja';
    end if;
  end if;

  if p_alcance = 'RESTRINGIDO' and pg_catalog.cardinality(v_edificios) = 0 then
    raise exception 'Un usuario restringido necesita al menos un edificio';
  end if;
  if p_alcance = 'MASTER' and pg_catalog.cardinality(v_edificios) > 0 then
    raise exception 'Los edificios solo se indican para usuarios restringidos';
  end if;

  -- Edificios: de los clientes indicados (usuarios de cliente) o del Partner (usuarios de Partner)
  if exists (
    select 1 from pg_catalog.unnest(v_edificios) e(id)
    where not exists (
      select 1 from public.edificios ed
      where ed.id = e.id and ed.activo
        and ((not v_es_partner_destino and ed.id_cliente = any (v_clientes))
          or (v_es_partner_destino and exists (
                select 1 from public.proveedores_edificios pe
                where pe.id_edificio = ed.id and pe.id_proveedor = p_id_proveedor and pe.activo))))
  ) then
    raise exception 'Algún edificio no pertenece a los clientes o al Partner indicados';
  end if;

  -- Quién puede crear qué
  if v_rol_creador = 'ADMIN_SAAS' then
    return;
  end if;

  if v_rol_creador not in ('ADMIN_PARTNER', 'TECNICO_PARTNER') then
    raise exception 'Sin permiso para dar de alta usuarios' using errcode = '42501';
  end if;
  if p_rol = 'ADMIN_SAAS' then
    raise exception 'Solo el administrador de la plataforma crea administradores de la plataforma' using errcode = '42501';
  end if;
  if p_rol = 'ADMIN_PARTNER' and v_rol_creador <> 'ADMIN_PARTNER' then
    raise exception 'Un técnico no puede crear administradores del Partner' using errcode = '42501';
  end if;

  if v_es_partner_destino then
    if p_id_proveedor not in (select private.partners_de_usuario(p_id_creador)) then
      raise exception 'Solo puede crear usuarios de su propio Partner' using errcode = '42501';
    end if;
  else
    if exists (
      select 1 from pg_catalog.unnest(v_clientes) c(id)
      where not exists (
        select 1 from public.proveedores_clientes pc
        where pc.id_cliente = c.id and pc.activo
          and pc.id_proveedor in (select private.partners_de_usuario(p_id_creador)))
    ) then
      raise exception 'Algún cliente no pertenece a su Partner' using errcode = '42501';
    end if;
    if exists (
      select 1 from pg_catalog.unnest(v_edificios) e(id)
      where not exists (
        select 1 from public.proveedores_edificios pe
        where pe.id_edificio = e.id and pe.activo
          and pe.id_proveedor in (select private.partners_de_usuario(p_id_creador)))
    ) then
      raise exception 'Algún edificio no lo gestiona su Partner' using errcode = '42501';
    end if;
  end if;
end;
$$;

create or replace function private.puede_gestionar_usuario(p_id_creador uuid, p_id_usuario uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with c as (select private.rol_usuario(p_id_creador) as rol),
       o as (select private.rol_usuario(p_id_usuario) as rol)
  select case
    when (select rol from o) is null then false
    when (select rol from c) = 'ADMIN_SAAS' then true
    when (select rol from c) not in ('ADMIN_PARTNER', 'TECNICO_PARTNER') then false
    when (select rol from o) = 'ADMIN_SAAS' then false
    when (select rol from o) = 'ADMIN_PARTNER' and (select rol from c) <> 'ADMIN_PARTNER' then false
    when (select rol from o) in ('ADMIN_PARTNER', 'TECNICO_PARTNER') then exists (
      select 1 from public.usuarios_partners up
      where up.id_usuario = p_id_usuario and up.activo
        and up.id_proveedor in (select private.partners_de_usuario(p_id_creador)))
    else exists (
      select 1 from public.usuarios_clientes uc
      join public.proveedores_clientes pc on pc.id_cliente = uc.id_cliente and pc.activo
      where uc.id_usuario = p_id_usuario and uc.activo
        and pc.id_proveedor in (select private.partners_de_usuario(p_id_creador)))
  end;
$$;

-- ---------------------------------------------------------
-- 6. Funciones que usa la API
-- ---------------------------------------------------------
-- Comprobación previa, con la sesión de quien da de alta (antes de crear la cuenta en Auth)
create or replace function public.validar_alta_usuario(
  p_email text,
  p_rol text,
  p_id_proveedor uuid default null,
  p_alcance text default 'MASTER',
  p_ids_clientes uuid[] default null,
  p_ids_edificios uuid[] default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_yo uuid := private.usuario_actual();
begin
  if v_yo is null then
    raise exception 'Sesión sin acceso completo (falta el código o el cambio de contraseña)' using errcode = '42501';
  end if;
  if exists (select 1 from public.usuarios where pg_catalog.lower(email) = pg_catalog.lower(pg_catalog.btrim(p_email))) then
    raise exception 'Ya existe un usuario con ese email' using errcode = '23505';
  end if;
  perform private.comprobar_alta_usuario(v_yo, p_rol, p_id_proveedor, p_alcance, p_ids_clientes, p_ids_edificios);
  return v_yo;
end;
$$;

-- Registro de la ficha (la API ya creó la cuenta en Auth). Vuelve a comprobar los permisos.
create or replace function public.registrar_usuario(
  p_id_creador uuid,
  p_auth_user_id uuid,
  p_email text,
  p_nombre text,
  p_apellidos text,
  p_telefono text,
  p_rol text,
  p_id_proveedor uuid default null,
  p_alcance text default 'MASTER',
  p_ids_clientes uuid[] default null,
  p_ids_edificios uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform private.comprobar_alta_usuario(p_id_creador, p_rol, p_id_proveedor, p_alcance, p_ids_clientes, p_ids_edificios);

  insert into public.usuarios (auth_user_id, nombre, apellidos, email, telefono, id_rol, debe_cambiar_contrasena)
  select p_auth_user_id, pg_catalog.btrim(p_nombre), nullif(pg_catalog.btrim(p_apellidos), ''),
         pg_catalog.lower(pg_catalog.btrim(p_email)), nullif(pg_catalog.btrim(p_telefono), ''), r.id, true
  from public.roles r where r.codigo = p_rol
  returning id into v_id;

  if p_id_proveedor is not null then
    insert into public.usuarios_partners (id_usuario, id_proveedor, tipo_alcance)
    values (v_id, p_id_proveedor, p_alcance);
  end if;

  insert into public.usuarios_clientes (id_usuario, id_cliente, tipo_alcance)
  select v_id, c, p_alcance from pg_catalog.unnest(coalesce(p_ids_clientes, '{}')) c;

  insert into public.usuarios_edificios (id_usuario, id_edificio)
  select v_id, e from pg_catalog.unnest(coalesce(p_ids_edificios, '{}')) e;

  return v_id;
end;
$$;

-- Acciones sobre un usuario existente. Devuelve su auth_user_id para que la API actúe en Auth.
--   BAJA / REACTIVAR             → permiso DESACTIVAR_USUARIO
--   RESTABLECER_CONTRASENA       → permiso MODIFICAR_USUARIO (vuelve a exigir el cambio)
--   CONTRASENA_CAMBIADA          → el propio usuario, tras cambiarla
--   ACTIVAR_DOBLE_FACTOR / DESACTIVAR_DOBLE_FACTOR → el propio usuario (si su rol no lo exige)
create or replace function public.gestionar_usuario(p_id_creador uuid, p_id_usuario uuid, p_accion text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid;
  v_permiso text;
begin
  select auth_user_id into v_auth from public.usuarios where id = p_id_usuario;
  if v_auth is null then
    raise exception 'El usuario no existe';
  end if;

  if p_accion in ('CONTRASENA_CAMBIADA', 'ACTIVAR_DOBLE_FACTOR', 'DESACTIVAR_DOBLE_FACTOR') then
    if p_id_creador <> p_id_usuario then
      raise exception 'Solo el propio usuario puede hacerlo' using errcode = '42501';
    end if;
  else
    v_permiso := case p_accion
      when 'BAJA' then 'DESACTIVAR_USUARIO'
      when 'REACTIVAR' then 'DESACTIVAR_USUARIO'
      when 'RESTABLECER_CONTRASENA' then 'MODIFICAR_USUARIO'
    end;
    if v_permiso is null then
      raise exception 'Acción no válida: %', p_accion;
    end if;
    if p_id_creador = p_id_usuario then
      raise exception 'No puede hacerlo sobre su propio usuario' using errcode = '42501';
    end if;
    if not private.usuario_con_permiso(p_id_creador, v_permiso)
       or not private.puede_gestionar_usuario(p_id_creador, p_id_usuario) then
      raise exception 'Sin permiso para gestionar este usuario' using errcode = '42501';
    end if;
  end if;

  case p_accion
    when 'BAJA' then
      update public.usuarios set activo = false, fecha_baja = greatest(current_date, fecha_alta)
       where id = p_id_usuario and activo;
    when 'REACTIVAR' then
      update public.usuarios set activo = true, fecha_baja = null where id = p_id_usuario;
    when 'RESTABLECER_CONTRASENA' then
      update public.usuarios set debe_cambiar_contrasena = true where id = p_id_usuario;
    when 'CONTRASENA_CAMBIADA' then
      update public.usuarios set debe_cambiar_contrasena = false where id = p_id_usuario;
    when 'ACTIVAR_DOBLE_FACTOR' then
      update public.usuarios set doble_factor = true where id = p_id_usuario;
    when 'DESACTIVAR_DOBLE_FACTOR' then
      if exists (select 1 from public.usuarios u join public.roles r on r.id = u.id_rol
                 where u.id = p_id_usuario and r.requiere_doble_factor) then
        raise exception 'Su rol exige el doble factor: no se puede desactivar';
      end if;
      update public.usuarios set doble_factor = false where id = p_id_usuario;
  end case;
  return v_auth;
end;
$$;

-- Códigos de verificación: la API genera el código, lo envía por email y la BD guarda su hash.
create or replace function public.crear_codigo_verificacion(p_auth_user_id uuid, p_id_sesion uuid, p_codigo text)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expira timestamptz := pg_catalog.now() + interval '10 minutes';
begin
  if (select count(*) from public.codigos_verificacion
      where auth_user_id = p_auth_user_id and created_at > pg_catalog.now() - interval '15 minutes') >= 5 then
    raise exception 'Demasiados códigos solicitados. Espere unos minutos.' using errcode = 'P0429';
  end if;
  update public.codigos_verificacion set anulado = true
   where auth_user_id = p_auth_user_id and id_sesion = p_id_sesion and verificado_at is null and not anulado;
  insert into public.codigos_verificacion (auth_user_id, id_sesion, codigo_hash, expira_at)
  values (p_auth_user_id, p_id_sesion,
          pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_id_sesion::text || ':' || p_codigo, 'UTF8')), 'hex'),
          v_expira);
  return v_expira;
end;
$$;

create or replace function public.verificar_codigo(p_auth_user_id uuid, p_id_sesion uuid, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.codigos_verificacion%rowtype;
  v_max constant smallint := 5;
begin
  select * into v from public.codigos_verificacion
   where auth_user_id = p_auth_user_id and id_sesion = p_id_sesion and not anulado
   order by created_at desc limit 1
   for update;

  if not found then
    return pg_catalog.jsonb_build_object('resultado', 'SIN_CODIGO');
  end if;
  if v.verificado_at is not null then
    return pg_catalog.jsonb_build_object('resultado', 'OK');
  end if;
  if v.intentos >= v_max then
    return pg_catalog.jsonb_build_object('resultado', 'BLOQUEADO');
  end if;
  if v.expira_at < pg_catalog.now() then
    return pg_catalog.jsonb_build_object('resultado', 'CADUCADO');
  end if;

  if v.codigo_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_id_sesion::text || ':' || pg_catalog.btrim(p_codigo), 'UTF8')), 'hex') then
    update public.codigos_verificacion set verificado_at = pg_catalog.now() where id = v.id;
    return pg_catalog.jsonb_build_object('resultado', 'OK');
  end if;

  update public.codigos_verificacion set intentos = intentos + 1 where id = v.id;
  return pg_catalog.jsonb_build_object(
    'resultado', case when v.intentos + 1 >= v_max then 'BLOQUEADO' else 'INCORRECTO' end,
    'intentos_restantes', greatest(v_max - v.intentos - 1, 0));
end;
$$;

-- ---------------------------------------------------------
-- 7. Permisos de ejecución
-- ---------------------------------------------------------
revoke all on function public.mi_cuenta() from public, anon;
grant execute on function public.mi_cuenta() to authenticated, service_role;

revoke all on function public.validar_alta_usuario(text, text, uuid, text, uuid[], uuid[]) from public, anon;
grant execute on function public.validar_alta_usuario(text, text, uuid, text, uuid[], uuid[]) to authenticated;

revoke all on function public.registrar_usuario(uuid, uuid, text, text, text, text, text, uuid, text, uuid[], uuid[]) from public, anon, authenticated;
grant execute on function public.registrar_usuario(uuid, uuid, text, text, text, text, text, uuid, text, uuid[], uuid[]) to service_role;

revoke all on function public.gestionar_usuario(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.gestionar_usuario(uuid, uuid, text) to service_role;

revoke all on function public.crear_codigo_verificacion(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.crear_codigo_verificacion(uuid, uuid, text) to service_role;

revoke all on function public.verificar_codigo(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.verificar_codigo(uuid, uuid, text) to service_role;

revoke all on function private.rol_usuario(uuid) from public, anon, authenticated;
revoke all on function private.usuario_con_permiso(uuid, text) from public, anon, authenticated;
revoke all on function private.partners_de_usuario(uuid) from public, anon, authenticated;
revoke all on function private.comprobar_alta_usuario(uuid, text, uuid, text, uuid[], uuid[]) from public, anon, authenticated;
revoke all on function private.puede_gestionar_usuario(uuid, uuid) from public, anon, authenticated;

commit;
