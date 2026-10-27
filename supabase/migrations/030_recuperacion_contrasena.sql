-- =========================================================
-- 030 · Recuperación de contraseña con código por email
-- Decisión D36 (27/10/2026): "¿Has olvidado la contraseña?" envía un código
-- de 6 cifras al email; con él, el usuario elige una contraseña nueva.
--   - La API responde siempre lo mismo exista o no el email (no revela usuarios).
--   - Código cifrado (hash), 15 minutos, 5 intentos, máx. 3 códigos por hora.
--   - Solo usuarios activos. Tras usarlo, el código queda anulado.
-- Solo la API (service_role) usa estas funciones.
-- =========================================================
begin;

create table if not exists public.codigos_recuperacion (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  codigo_hash text not null,
  expira_at timestamptz not null,
  intentos smallint not null default 0,
  usado_at timestamptz,
  anulado boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.codigos_recuperacion is
  'Códigos de recuperación de contraseña enviados por email (cifrados). Solo los usa la API.';

create index if not exists ix_codigos_recuperacion_usuario
  on public.codigos_recuperacion(auth_user_id, created_at desc);

alter table public.codigos_recuperacion enable row level security;
revoke all on public.codigos_recuperacion from anon, authenticated;

-- Crea un código para el email si corresponde a un usuario activo.
-- Devuelve null si no existe, está de baja o ha pedido demasiados (la API no lo revela).
create or replace function public.crear_codigo_recuperacion(p_email text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid;
  v_nombre text;
begin
  select u.auth_user_id, u.nombre into v_auth, v_nombre
  from public.usuarios u
  where pg_catalog.lower(u.email) = pg_catalog.lower(pg_catalog.btrim(p_email))
    and u.activo and u.fecha_baja is null;
  if v_auth is null then
    return null;
  end if;
  if (select count(*) from public.codigos_recuperacion
      where auth_user_id = v_auth and created_at > pg_catalog.now() - interval '1 hour') >= 3 then
    return null;
  end if;
  update public.codigos_recuperacion set anulado = true
   where auth_user_id = v_auth and usado_at is null and not anulado;
  insert into public.codigos_recuperacion (auth_user_id, codigo_hash, expira_at)
  values (v_auth,
          pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_auth::text || ':' || p_codigo, 'UTF8')), 'hex'),
          pg_catalog.now() + interval '15 minutes');
  return pg_catalog.jsonb_build_object('auth_user_id', v_auth, 'nombre', v_nombre);
end;
$$;

-- Comprueba el código. Si es correcto lo marca como usado y devuelve el auth_user_id
-- para que la API cambie la contraseña.
create or replace function public.usar_codigo_recuperacion(p_email text, p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid;
  v public.codigos_recuperacion%rowtype;
  v_max constant smallint := 5;
begin
  select u.auth_user_id into v_auth from public.usuarios u
  where pg_catalog.lower(u.email) = pg_catalog.lower(pg_catalog.btrim(p_email)) and u.activo;
  if v_auth is null then
    return pg_catalog.jsonb_build_object('resultado', 'NO_VALIDO');
  end if;

  select * into v from public.codigos_recuperacion
   where auth_user_id = v_auth and not anulado and usado_at is null
   order by created_at desc limit 1
   for update;
  if not found or v.expira_at < pg_catalog.now() then
    return pg_catalog.jsonb_build_object('resultado', 'NO_VALIDO');
  end if;
  if v.intentos >= v_max then
    return pg_catalog.jsonb_build_object('resultado', 'BLOQUEADO');
  end if;

  if v.codigo_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
       v_auth::text || ':' || pg_catalog.btrim(p_codigo), 'UTF8')), 'hex') then
    update public.codigos_recuperacion set usado_at = pg_catalog.now() where id = v.id;
    -- La contraseña la elige el propio usuario: ya no tiene que cambiarla al entrar
    update public.usuarios set debe_cambiar_contrasena = false where auth_user_id = v_auth;
    return pg_catalog.jsonb_build_object('resultado', 'OK', 'auth_user_id', v_auth);
  end if;

  update public.codigos_recuperacion set intentos = intentos + 1 where id = v.id;
  return pg_catalog.jsonb_build_object(
    'resultado', case when v.intentos + 1 >= v_max then 'BLOQUEADO' else 'INCORRECTO' end,
    'intentos_restantes', greatest(v_max - v.intentos - 1, 0));
end;
$$;

revoke all on function public.crear_codigo_recuperacion(text, text) from public, anon, authenticated;
revoke all on function public.usar_codigo_recuperacion(text, text) from public, anon, authenticated;
grant execute on function public.crear_codigo_recuperacion(text, text) to service_role;
grant execute on function public.usar_codigo_recuperacion(text, text) to service_role;

commit;
