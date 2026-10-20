begin;

-- =========================================================
-- INSTALACIÓN INICIAL
-- El registro público de Supabase Auth debe estar desactivado.
-- El primer administrador se crea así:
--   1. Supabase Dashboard > Authentication > Users > Add user
--      (o invitación por email). Copiar su UUID.
--   2. Ejecutar en el SQL Editor (rol postgres) o desde el
--      backend con service_role:
--        select public.instalar_administrador(
--          '<uuid de auth.users>', 'Nombre', 'email@empresa.com');
-- Solo funciona mientras no exista ningún ADMIN_SAAS activo.
-- =========================================================

create or replace function public.instalar_administrador(
  p_auth_user_id uuid,
  p_nombre varchar,
  p_email varchar,
  p_apellidos varchar default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rol smallint;
  v_usuario uuid;
begin
  if exists (
    select 1 from public.usuarios u
    join public.roles r on r.id = u.id_rol
    where r.codigo = 'ADMIN_SAAS' and u.activo
  ) then
    raise exception 'La plataforma ya tiene un administrador. Use el backend para crear más usuarios.';
  end if;

  if not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception 'No existe el usuario % en Supabase Auth', p_auth_user_id;
  end if;

  select id into v_rol from public.roles where codigo = 'ADMIN_SAAS';

  insert into public.usuarios (auth_user_id, nombre, apellidos, email, id_rol)
  values (p_auth_user_id, p_nombre, p_apellidos, pg_catalog.lower(p_email), v_rol)
  returning id into v_usuario;

  return v_usuario;
end;
$$;

revoke all on function public.instalar_administrador(uuid, varchar, varchar, varchar)
  from public, anon, authenticated;
grant execute on function public.instalar_administrador(uuid, varchar, varchar, varchar)
  to service_role;

-- Comprobación de instalación: lista tablas de public sin RLS.
-- Debe devolver 0 filas. Útil tras cualquier cambio de esquema.
create or replace function public.verificar_rls()
returns table (tabla text)
language sql
stable
set search_path = ''
as $$
  select c.relname::text
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind in ('r', 'p')
    and not c.relrowsecurity
  order by 1;
$$;

revoke all on function public.verificar_rls() from public, anon, authenticated;
grant execute on function public.verificar_rls() to service_role;

commit;
