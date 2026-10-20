begin;

-- =========================================================
-- MODELOS 3D (decisión 20/10/2026)
-- Un modelo es de EDIFICIO (vista general) o de RECINTO (detalle).
-- No existen modelos de planta: una planta con un único recinto
-- se modela con un recinto de tipo PLANTA_COMPLETA. Así sirven
-- tanto edificios en altura (muchas plantas, pocos recintos)
-- como edificios extensos (pocas plantas, muchos recintos).
--
-- id_edificio siempre informado (también en modelos de recinto)
-- para simplificar consultas y RLS.
-- Ruta del archivo en Storage (bucket privado modelos-3d):
--   edificios/<id_edificio>/modelos/<archivo>.glb|gltf
--   recintos/<id_recinto>/modelos/<archivo>.glb|gltf
-- =========================================================

create table if not exists public.modelos_3d (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  id_recinto uuid references public.recintos(id) on delete restrict,
  tipo_modelo varchar(20) not null,
  nombre varchar(200) not null,
  archivo text not null,
  formato varchar(10) not null default 'GLB',
  compresion varchar(20) not null default 'NINGUNA',
  version integer not null default 1,
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  descripcion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint modelos_3d_archivo_uq unique (archivo),
  constraint modelos_3d_tipo_ck
    check (tipo_modelo in ('EDIFICIO', 'RECINTO')),
  constraint modelos_3d_destino_ck
    check (
      (tipo_modelo = 'EDIFICIO' and id_recinto is null)
      or (tipo_modelo = 'RECINTO' and id_recinto is not null)
    ),
  constraint modelos_3d_formato_ck
    check (formato in ('GLB', 'GLTF')),
  constraint modelos_3d_compresion_ck
    check (compresion in ('NINGUNA', 'DRACO')),
  constraint modelos_3d_version_ck
    check (version >= 1),
  constraint modelos_3d_fechas_ck
    check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint modelos_3d_estado_fecha_ck
    check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null))
);

-- Un modelo general activo por edificio y un modelo activo por recinto.
create unique index if not exists ux_modelo_3d_edificio_activo
  on public.modelos_3d(id_edificio)
  where activo and tipo_modelo = 'EDIFICIO';

create unique index if not exists ux_modelo_3d_recinto_activo
  on public.modelos_3d(id_recinto)
  where activo and tipo_modelo = 'RECINTO';

create index if not exists ix_modelos_3d_edificio
  on public.modelos_3d(id_edificio, activo);

create index if not exists ix_modelos_3d_recinto
  on public.modelos_3d(id_recinto)
  where id_recinto is not null;

create table if not exists public.ubicaciones_3d (
  id uuid primary key default gen_random_uuid(),
  id_modelo_3d uuid not null references public.modelos_3d(id) on delete restrict,
  id_dispositivo uuid references public.dispositivos(id) on delete restrict,
  id_sensor uuid references public.sensores(id) on delete restrict,
  x numeric(18,8) not null,
  y numeric(18,8) not null,
  z numeric(18,8) not null,
  visible boolean not null default true,
  descripcion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ubicaciones_3d_elemento_ck
    check (num_nonnulls(id_dispositivo, id_sensor) = 1)
);

create unique index if not exists ux_ubicacion_3d_sensor_modelo
  on public.ubicaciones_3d(id_modelo_3d, id_sensor)
  where id_sensor is not null;

create unique index if not exists ux_ubicacion_3d_dispositivo_modelo
  on public.ubicaciones_3d(id_modelo_3d, id_dispositivo)
  where id_dispositivo is not null;

create index if not exists ix_ubicaciones_3d_modelo
  on public.ubicaciones_3d(id_modelo_3d);

-- ---------------------------------------------------------
-- Validación del destino del modelo y de su ruta de archivo.
-- ---------------------------------------------------------
create or replace function public.validar_modelo_3d_destino()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_recinto uuid;
  v_prefijo text;
begin
  if new.tipo_modelo = 'RECINTO' then
    select p.id_edificio
      into v_edificio_recinto
    from public.recintos r
    join public.plantas p on p.id = r.id_planta
    where r.id = new.id_recinto;

    if v_edificio_recinto is null then
      raise exception 'El recinto del modelo 3D no existe';
    end if;

    if v_edificio_recinto <> new.id_edificio then
      raise exception 'El recinto del modelo 3D no pertenece al edificio indicado';
    end if;

    v_prefijo := 'recintos/' || new.id_recinto::text || '/modelos/';
  else
    v_prefijo := 'edificios/' || new.id_edificio::text || '/modelos/';
  end if;

  if pg_catalog.left(new.archivo, pg_catalog.length(v_prefijo)) <> v_prefijo
     or new.archivo !~* '^[^/]+/[^/]+/modelos/[A-Za-z0-9._-]+[.](glb|gltf)$' then
    raise exception 'La ruta del archivo debe ser %<archivo>.glb|gltf', v_prefijo;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_modelos_3d_validar_destino
  on public.modelos_3d;

create trigger trg_modelos_3d_validar_destino
before insert or update of id_edificio, id_recinto, tipo_modelo, archivo
on public.modelos_3d
for each row execute function public.validar_modelo_3d_destino();

-- ---------------------------------------------------------
-- Validación de ubicaciones: el elemento debe estar en el
-- edificio (modelo de EDIFICIO) o en el recinto (modelo de RECINTO).
-- ---------------------------------------------------------
create or replace function public.validar_ubicacion_3d()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_tipo_modelo varchar(20);
  v_edificio_modelo uuid;
  v_recinto_modelo uuid;
  v_recinto_elemento uuid;
  v_edificio_elemento uuid;
begin
  select m.tipo_modelo, m.id_edificio, m.id_recinto
    into v_tipo_modelo, v_edificio_modelo, v_recinto_modelo
  from public.modelos_3d m
  where m.id = new.id_modelo_3d;

  if not found then
    raise exception 'El modelo 3D indicado no existe';
  end if;

  if new.id_sensor is not null then
    select s.id_recinto into v_recinto_elemento
    from public.sensores s where s.id = new.id_sensor;
  else
    select d.id_recinto into v_recinto_elemento
    from public.dispositivos d where d.id = new.id_dispositivo;
  end if;

  if v_recinto_elemento is null then
    raise exception 'El sensor o dispositivo indicado no existe';
  end if;

  select p.id_edificio into v_edificio_elemento
  from public.recintos r
  join public.plantas p on p.id = r.id_planta
  where r.id = v_recinto_elemento;

  if v_tipo_modelo = 'EDIFICIO' then
    if v_edificio_elemento is distinct from v_edificio_modelo then
      raise exception 'El elemento debe pertenecer al edificio del modelo 3D';
    end if;
  elsif v_recinto_elemento is distinct from v_recinto_modelo then
    raise exception 'El elemento debe estar ubicado en el recinto del modelo 3D';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ubicaciones_3d_validar
  on public.ubicaciones_3d;

create trigger trg_ubicaciones_3d_validar
before insert or update of id_modelo_3d, id_dispositivo, id_sensor
on public.ubicaciones_3d
for each row execute function public.validar_ubicacion_3d();

drop trigger if exists trg_modelos_3d_updated_at
  on public.modelos_3d;

create trigger trg_modelos_3d_updated_at
before update on public.modelos_3d
for each row execute function public.set_updated_at();

drop trigger if exists trg_ubicaciones_3d_updated_at
  on public.ubicaciones_3d;

create trigger trg_ubicaciones_3d_updated_at
before update on public.ubicaciones_3d
for each row execute function public.set_updated_at();

alter table public.modelos_3d enable row level security;
alter table public.ubicaciones_3d enable row level security;

commit;
