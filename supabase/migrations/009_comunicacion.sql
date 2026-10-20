begin;

create table if not exists public.estado_comunicacion (
  id uuid primary key default gen_random_uuid(),
  id_sensor uuid not null unique references public.sensores(id) on delete restrict,
  estado varchar(30) not null default 'COMUNICANDO',
  ultima_lectura timestamptz,
  fecha_cambio_estado timestamptz not null default now(),
  umbral_minutos integer not null default 30,
  updated_at timestamptz not null default now(),
  constraint estado_comunicacion_estado_ck
    check (estado in ('COMUNICANDO', 'SIN_COMUNICACION')),
  constraint estado_comunicacion_umbral_ck
    check (umbral_minutos between 15 and 120)
);

create index if not exists ix_estado_comunicacion_estado
  on public.estado_comunicacion(estado);

create table if not exists public.incidencias_comunicacion (
  id uuid primary key default gen_random_uuid(),
  id_sensor uuid not null references public.sensores(id) on delete restrict,
  fecha_inicio timestamptz not null default now(),
  fecha_fin timestamptz,
  duracion_segundos bigint,
  estado varchar(20) not null default 'ABIERTA',
  created_at timestamptz not null default now(),
  constraint incidencias_comunicacion_estado_ck
    check (estado in ('ABIERTA', 'CERRADA')),
  constraint incidencias_comunicacion_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint incidencias_comunicacion_duracion_ck
    check (duracion_segundos is null or duracion_segundos >= 0),
  constraint incidencias_comunicacion_cierre_ck
    check (
      (estado = 'ABIERTA' and fecha_fin is null)
      or (estado = 'CERRADA' and fecha_fin is not null)
    )
);

create unique index if not exists ux_incidencia_comunicacion_abierta
  on public.incidencias_comunicacion(id_sensor)
  where estado = 'ABIERTA';

create index if not exists ix_incidencias_comunicacion_sensor_fecha
  on public.incidencias_comunicacion(id_sensor, fecha_inicio desc);

create index if not exists ix_incidencias_comunicacion_estado_fecha
  on public.incidencias_comunicacion(estado, fecha_inicio desc);

create or replace function public.validar_incidencia_comunicacion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.estado = 'ABIERTA' then
    new.fecha_fin := null;
    new.duracion_segundos := null;
  elsif new.estado = 'CERRADA' then
    if new.fecha_fin is null then
      new.fecha_fin := pg_catalog.now();
    end if;

    if new.fecha_fin < new.fecha_inicio then
      raise exception 'La fecha de cierre no puede ser anterior al inicio';
    end if;

    new.duracion_segundos :=
      pg_catalog.floor(
        extract(epoch from (new.fecha_fin - new.fecha_inicio))
      )::bigint;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_incidencias_comunicacion_validar
  on public.incidencias_comunicacion;

create trigger trg_incidencias_comunicacion_validar
before insert or update of fecha_inicio, fecha_fin, estado
on public.incidencias_comunicacion
for each row execute function public.validar_incidencia_comunicacion();

drop trigger if exists trg_estado_comunicacion_updated_at
  on public.estado_comunicacion;

create trigger trg_estado_comunicacion_updated_at
before update on public.estado_comunicacion
for each row execute function public.set_updated_at();

comment on table public.estado_comunicacion is
  'Estado actual de conectividad por sensor; lo actualiza el proceso de ingesta.';

comment on table public.incidencias_comunicacion is
  'Histórico de periodos sin comunicación, independiente de las alarmas energéticas.';

-- Notificaciones de pérdida de comunicación vinculadas a su incidencia.
alter table public.notificaciones
  add column if not exists id_incidencia_comunicacion uuid
  references public.incidencias_comunicacion(id) on delete restrict;

create index if not exists ix_notificaciones_incidencia
  on public.notificaciones(id_incidencia_comunicacion)
  where id_incidencia_comunicacion is not null;

alter table public.estado_comunicacion enable row level security;
alter table public.incidencias_comunicacion enable row level security;

commit;