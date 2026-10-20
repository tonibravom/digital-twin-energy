begin;

create table if not exists public.dispositivos_recintos_ambito (
  id uuid primary key default gen_random_uuid(),
  id_dispositivo uuid not null references public.dispositivos(id) on delete restrict,
  id_recinto uuid not null references public.recintos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint dispositivo_ambito_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint dispositivo_ambito_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_dispositivo_ambito_inicio
  on public.dispositivos_recintos_ambito(id_dispositivo, id_recinto, fecha_inicio);

create unique index if not exists ux_dispositivo_ambito_activo
  on public.dispositivos_recintos_ambito(id_dispositivo, id_recinto)
  where activo;

create table if not exists public.sensores_recintos_ambito (
  id uuid primary key default gen_random_uuid(),
  id_sensor uuid not null references public.sensores(id) on delete restrict,
  id_recinto uuid not null references public.recintos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint sensor_ambito_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint sensor_ambito_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_sensor_ambito_inicio
  on public.sensores_recintos_ambito(id_sensor, id_recinto, fecha_inicio);

create unique index if not exists ux_sensor_ambito_activo
  on public.sensores_recintos_ambito(id_sensor, id_recinto)
  where activo;

create table if not exists public.dispositivos_ubicaciones (
  id uuid primary key default gen_random_uuid(),
  id_dispositivo uuid not null references public.dispositivos(id) on delete restrict,
  id_recinto uuid not null references public.recintos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  descripcion text,
  created_at timestamptz not null default now(),
  constraint dispositivo_ubicacion_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio)
);

create unique index if not exists ux_dispositivo_ubicacion_inicio
  on public.dispositivos_ubicaciones(id_dispositivo, fecha_inicio);

create unique index if not exists ux_dispositivo_ubicacion_actual
  on public.dispositivos_ubicaciones(id_dispositivo)
  where fecha_fin is null;

create table if not exists public.sensores_ubicaciones (
  id uuid primary key default gen_random_uuid(),
  id_sensor uuid not null references public.sensores(id) on delete restrict,
  id_recinto uuid not null references public.recintos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  descripcion text,
  created_at timestamptz not null default now(),
  constraint sensor_ubicacion_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio)
);

create unique index if not exists ux_sensor_ubicacion_inicio
  on public.sensores_ubicaciones(id_sensor, fecha_inicio);

create unique index if not exists ux_sensor_ubicacion_actual
  on public.sensores_ubicaciones(id_sensor)
  where fecha_fin is null;

create or replace function public.obtener_edificio_recinto(p_id_recinto uuid)
returns uuid
language sql
stable
set search_path = ''
as $$
  select p.id_edificio
  from public.recintos r
  join public.plantas p on p.id = r.id_planta
  where r.id = p_id_recinto;
$$;

create or replace function public.validar_ambito_recinto()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_elemento uuid;
  v_edificio_recinto uuid;
begin
  if tg_table_name = 'dispositivos_recintos_ambito' then
    select public.obtener_edificio_recinto(d.id_recinto)
      into v_edificio_elemento
    from public.dispositivos d
    where d.id = new.id_dispositivo;
  else
    select public.obtener_edificio_recinto(s.id_recinto)
      into v_edificio_elemento
    from public.sensores s
    where s.id = new.id_sensor;
  end if;

  if v_edificio_elemento is null then
    raise exception 'No existe el dispositivo o sensor indicado';
  end if;

  v_edificio_recinto := public.obtener_edificio_recinto(new.id_recinto);

  if v_edificio_recinto is null then
    raise exception 'El recinto del ámbito no existe';
  end if;

  if v_edificio_elemento <> v_edificio_recinto then
    raise exception 'El ámbito funcional debe pertenecer al mismo edificio que el elemento';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_dispositivos_ambito_validar
  on public.dispositivos_recintos_ambito;

create trigger trg_dispositivos_ambito_validar
before insert or update of id_dispositivo, id_recinto
on public.dispositivos_recintos_ambito
for each row execute function public.validar_ambito_recinto();

drop trigger if exists trg_sensores_ambito_validar
  on public.sensores_recintos_ambito;

create trigger trg_sensores_ambito_validar
before insert or update of id_sensor, id_recinto
on public.sensores_recintos_ambito
for each row execute function public.validar_ambito_recinto();

create or replace function public.validar_ubicacion_fisica()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_elemento uuid;
  v_edificio_recinto uuid;
begin
  if tg_table_name = 'dispositivos_ubicaciones' then
    select public.obtener_edificio_recinto(d.id_recinto)
      into v_edificio_elemento
    from public.dispositivos d
    where d.id = new.id_dispositivo;
  else
    select public.obtener_edificio_recinto(s.id_recinto)
      into v_edificio_elemento
    from public.sensores s
    where s.id = new.id_sensor;
  end if;

  if v_edificio_elemento is null then
    raise exception 'No existe el dispositivo o sensor indicado';
  end if;

  v_edificio_recinto := public.obtener_edificio_recinto(new.id_recinto);

  if v_edificio_recinto is null then
    raise exception 'El recinto de destino no existe';
  end if;

  if v_edificio_elemento <> v_edificio_recinto then
    raise exception 'La ubicación física debe pertenecer al mismo edificio';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_dispositivos_ubicacion_validar
  on public.dispositivos_ubicaciones;

create trigger trg_dispositivos_ubicacion_validar
before insert or update of id_dispositivo, id_recinto
on public.dispositivos_ubicaciones
for each row execute function public.validar_ubicacion_fisica();

drop trigger if exists trg_sensores_ubicacion_validar
  on public.sensores_ubicaciones;

create trigger trg_sensores_ubicacion_validar
before insert or update of id_sensor, id_recinto
on public.sensores_ubicaciones
for each row execute function public.validar_ubicacion_fisica();

revoke all on function public.obtener_edificio_recinto(uuid) from public, anon;

alter table public.dispositivos_recintos_ambito enable row level security;
alter table public.sensores_recintos_ambito enable row level security;
alter table public.dispositivos_ubicaciones enable row level security;
alter table public.sensores_ubicaciones enable row level security;

commit;