-- =========================================================
-- 059 · Históricos: comparativas guardadas (D62)
-- La pestaña Históricos dibuja sensores y magnitudes con las funciones que ya existen
-- (serie_sensor, serie_magnitud, serie_energia). Aquí solo se guardan las comparativas:
-- un nombre y la selección (qué datos, modo, periodos, agrupación, líneas o barras).
--  - Las ve quien ve el edificio si están compartidas; si no, solo quien las creó.
--  - Las cambia o retira quien las creó (o un administrador de la plataforma o del Partner). Baja lógica.
-- =========================================================
begin;

create table if not exists public.comparativas (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id),
  nombre text not null check (pg_catalog.length(pg_catalog.btrim(nombre)) between 1 and 120),
  configuracion jsonb not null check (pg_catalog.jsonb_typeof(configuracion) = 'object'),
  compartida boolean not null default true,
  id_usuario uuid not null references public.usuarios(id),
  activo boolean not null default true,
  fecha_baja timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint ck_comparativas_baja check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null))
);
alter table public.comparativas enable row level security;
create index if not exists ix_comparativas_edificio on public.comparativas (id_edificio) where activo;

drop trigger if exists trg_comparativas_updated_at on public.comparativas;
create trigger trg_comparativas_updated_at before update on public.comparativas
for each row execute function public.set_updated_at();

drop policy if exists comparativas_select on public.comparativas;
create policy comparativas_select on public.comparativas for select to authenticated
using (activo and private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_EDIFICIO')
       and (compartida or id_usuario = private.usuario_actual()));
grant select on public.comparativas to authenticated;
-- Sin políticas de escritura: guardar_comparativa / retirar_comparativa

-- Crea (p_id null) o actualiza una comparativa
create or replace function public.guardar_comparativa(p_id_edificio uuid, p_nombre text, p_configuracion jsonb,
                                                      p_compartida boolean default true, p_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario uuid := private.usuario_actual();
  v_actual public.comparativas%rowtype;
  v_id uuid;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'VER_EDIFICIO') then
    raise exception 'Sin acceso a este edificio' using errcode = '42501';
  end if;
  if coalesce(pg_catalog.btrim(p_nombre), '') = '' then
    raise exception 'Ponga un nombre a la comparativa' using errcode = '22023';
  end if;
  if p_configuracion is null or pg_catalog.jsonb_typeof(p_configuracion) <> 'object'
     or coalesce(p_configuracion->>'modo', '') not in ('valores', 'periodos') then
    raise exception 'Comparativa no válida' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.comparativas (id_edificio, nombre, configuracion, compartida, id_usuario)
    values (p_id_edificio, pg_catalog.btrim(p_nombre), p_configuracion, coalesce(p_compartida, true), v_usuario)
    returning id into v_id;
    return v_id;
  end if;
  select * into v_actual from public.comparativas where id = p_id and activo for update;
  if v_actual.id is null or v_actual.id_edificio <> p_id_edificio
     or (v_actual.id_usuario <> v_usuario and private.rol_usuario(v_usuario) not in ('ADMIN_SAAS', 'ADMIN_PARTNER')) then
    raise exception 'Solo quien la creó puede cambiarla' using errcode = '42501';
  end if;
  update public.comparativas set nombre = pg_catalog.btrim(p_nombre), configuracion = p_configuracion,
         compartida = coalesce(p_compartida, compartida)
  where id = p_id;
  return p_id;
end;
$$;
revoke all on function public.guardar_comparativa(uuid, text, jsonb, boolean, uuid) from public, anon;
grant execute on function public.guardar_comparativa(uuid, text, jsonb, boolean, uuid) to authenticated;

create or replace function public.retirar_comparativa(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.comparativas%rowtype;
begin
  select * into v from public.comparativas where id = p_id and activo;
  if v.id is null or not private.usuario_puede_edificio(v.id_edificio, 'VER_EDIFICIO')
     or (v.id_usuario <> private.usuario_actual() and private.rol_usuario(private.usuario_actual()) not in ('ADMIN_SAAS', 'ADMIN_PARTNER')) then
    raise exception 'Solo quien la creó puede quitarla' using errcode = '42501';
  end if;
  update public.comparativas set activo = false, fecha_baja = pg_catalog.now() where id = p_id;
end;
$$;
revoke all on function public.retirar_comparativa(uuid) from public, anon;
grant execute on function public.retirar_comparativa(uuid) to authenticated;

commit;
