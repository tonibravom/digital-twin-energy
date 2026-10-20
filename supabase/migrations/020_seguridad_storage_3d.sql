begin;

-- =========================================================
-- 1. BUCKET PRIVADO PARA MODELOS 3D
-- =========================================================

-- Límite de 200 MB por archivo. Ajustar si hay modelos mayores
-- (el plan de Supabase también fija un límite global de subida).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'modelos-3d', 'modelos-3d', false, 209715200,
  array['model/gltf-binary', 'model/gltf+json', 'application/octet-stream']
)
on conflict (id)
do update set public = false,
              file_size_limit = excluded.file_size_limit,
              allowed_mime_types = excluded.allowed_mime_types;

-- =========================================================
-- 2. RESOLVER EL EDIFICIO A PARTIR DE LA RUTA
-- Formatos admitidos (extensión .glb o .gltf):
--   edificios/<uuid>/modelos/<archivo>
--   recintos/<uuid>/modelos/<archivo>
-- El edificio de un recinto se obtiene por recintos -> plantas.
-- Decisión 20/10/2026: los modelos 3D son de EDIFICIO o RECINTO.
-- Además, la ruta debe corresponder a un registro de modelos_3d
-- (se crea primero el registro y después se sube el archivo).
-- =========================================================

create or replace function private.edificio_de_ruta_modelo_3d(
  p_nombre text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_partes text[];
  v_id uuid;
  v_edificio uuid;
begin
  if p_nombre is null then
    return null;
  end if;

  if p_nombre !~* '^(edificios|recintos)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/modelos/[A-Za-z0-9._-]+[.](glb|gltf)$' then
    return null;
  end if;

  v_partes := pg_catalog.string_to_array(p_nombre, '/');
  v_id := v_partes[2]::uuid;

  if pg_catalog.lower(v_partes[1]) = 'edificios' then
    select e.id
      into v_edificio
    from public.edificios e
    where e.id = v_id;

    return v_edificio;
  end if;

  select p.id_edificio
    into v_edificio
  from public.recintos r
  join public.plantas p on p.id = r.id_planta
  where r.id = v_id;

  return v_edificio;
end;
$$;

-- =========================================================
-- 3. VALIDAR SI EL USUARIO PUEDE OPERAR SOBRE LA RUTA
-- =========================================================

create or replace function private.puede_operar_modelo_3d(
  p_nombre text,
  p_permiso text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1 from public.modelos_3d m
      where m.archivo = p_nombre
        and m.id_edificio = private.edificio_de_ruta_modelo_3d(p_nombre)
    )
    and private.usuario_puede_edificio(
      private.edificio_de_ruta_modelo_3d(p_nombre),
      p_permiso
    ),
    false
  );
$$;

revoke all on function private.edificio_de_ruta_modelo_3d(text)
  from public, anon;
revoke all on function private.puede_operar_modelo_3d(text, text)
  from public, anon;

grant execute on function private.edificio_de_ruta_modelo_3d(text)
  to authenticated;
grant execute on function private.puede_operar_modelo_3d(text, text)
  to authenticated;

-- =========================================================
-- 4. RLS EN STORAGE.OBJECTS
-- =========================================================

-- storage.objects ya tiene RLS activado en Supabase (y la tabla
-- pertenece al servicio de Storage, no se altera desde aquí).

drop policy if exists modelos_3d_select on storage.objects;
create policy modelos_3d_select
on storage.objects
for select to authenticated
using (
  bucket_id = 'modelos-3d'
  and (
    private.puede_operar_modelo_3d(name, 'VER_3D')
    or private.puede_operar_modelo_3d(name, 'VER_MODELOS_3D')
  )
);

drop policy if exists modelos_3d_insert on storage.objects;
create policy modelos_3d_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'modelos-3d'
  and private.puede_operar_modelo_3d(name, 'CARGAR_MODELO_3D')
);

drop policy if exists modelos_3d_update on storage.objects;
create policy modelos_3d_update
on storage.objects
for update to authenticated
using (
  bucket_id = 'modelos-3d'
  and private.puede_operar_modelo_3d(name, 'SUSTITUIR_MODELO_3D')
)
with check (
  bucket_id = 'modelos-3d'
  and private.puede_operar_modelo_3d(name, 'SUSTITUIR_MODELO_3D')
);

-- No se permite borrado físico desde el cliente: la baja del modelo
-- se registra en public.modelos_3d y los ficheros antiguos se conservan.

commit;
