begin;

create table if not exists public.magnitudes (
  id uuid primary key default gen_random_uuid(),
  codigo varchar(80) not null unique,
  nombre varchar(150) not null,
  unidad varchar(30) not null,
  descripcion text,
  formula text,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.magnitudes_edificio (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  id_magnitud uuid not null references public.magnitudes(id) on delete restrict,
  ambito varchar(20) not null,
  id_planta uuid references public.plantas(id) on delete restrict,
  id_recinto uuid references public.recintos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activa boolean not null default true,
  configuracion jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint magnitudes_edificio_ambito_ck
    check (
      (ambito = 'EDIFICIO' and id_planta is null and id_recinto is null)
      or (ambito = 'PLANTA' and id_planta is not null and id_recinto is null)
      or (ambito = 'RECINTO' and id_planta is null and id_recinto is not null)
    ),
  constraint magnitudes_edificio_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint magnitudes_edificio_estado_fecha_ck
    check ((activa and fecha_fin is null) or (not activa and fecha_fin is not null)),
  constraint magnitudes_edificio_config_ck
    check (jsonb_typeof(configuracion) = 'object')
);

create unique index if not exists ux_magnitud_edificio_activa
  on public.magnitudes_edificio(id_edificio, id_magnitud)
  where activa and ambito = 'EDIFICIO';

create unique index if not exists ux_magnitud_planta_activa
  on public.magnitudes_edificio(id_edificio, id_magnitud, id_planta)
  where activa and ambito = 'PLANTA';

create unique index if not exists ux_magnitud_recinto_activa
  on public.magnitudes_edificio(id_edificio, id_magnitud, id_recinto)
  where activa and ambito = 'RECINTO';

create index if not exists ix_magnitudes_edificio
  on public.magnitudes_edificio(id_edificio, activa);

create table if not exists public.magnitudes_fuentes (
  id uuid primary key default gen_random_uuid(),
  id_magnitud_edificio uuid not null
    references public.magnitudes_edificio(id) on delete restrict,
  id_sensor uuid references public.sensores(id) on delete restrict,
  id_magnitud_origen uuid references public.magnitudes_edificio(id) on delete restrict,
  papel varchar(50) not null default 'FUENTE',
  orden integer not null default 1,
  created_at timestamptz not null default now(),
  constraint magnitudes_fuentes_origen_ck
    check (num_nonnulls(id_sensor, id_magnitud_origen) = 1),
  constraint magnitudes_fuentes_orden_ck check (orden >= 1)
);

create unique index if not exists ux_magnitud_fuente_sensor
  on public.magnitudes_fuentes(id_magnitud_edificio, id_sensor, papel)
  where id_sensor is not null;

create unique index if not exists ux_magnitud_fuente_magnitud
  on public.magnitudes_fuentes(id_magnitud_edificio, id_magnitud_origen, papel)
  where id_magnitud_origen is not null;

create index if not exists ix_magnitudes_fuentes_destino
  on public.magnitudes_fuentes(id_magnitud_edificio);

create table if not exists public.valores_magnitud (
  id_magnitud_edificio uuid not null
    references public.magnitudes_edificio(id) on delete restrict,
  fecha_hora timestamptz not null,
  valor double precision not null,
  calidad smallint not null default 0,
  version_motor varchar(40),
  created_at timestamptz not null default now(),
  constraint valores_magnitud_pk primary key (id_magnitud_edificio, fecha_hora),
  constraint valores_magnitud_calidad_ck check (calidad in (0, 1, 2))
) partition by range (fecha_hora);

comment on table public.valores_magnitud is
  'Valores calculados por el motor. Se conservan indefinidamente. Particionada por año UTC en el esquema particiones.';
comment on column public.valores_magnitud.calidad is
  '0 = VALIDA, 1 = ESTIMADA, 2 = CORREGIDA.';

create or replace function public.asegurar_particiones_valores_magnitud(
  p_anio_desde integer,
  p_anio_hasta integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anio integer;
  v_nombre text;
  v_creadas integer := 0;
begin
  if p_anio_desde is null or p_anio_hasta is null
     or p_anio_hasta < p_anio_desde
     or p_anio_hasta - p_anio_desde > 30 then
    raise exception 'Rango de años no válido';
  end if;

  for v_anio in p_anio_desde .. p_anio_hasta loop
    v_nombre := 'valores_magnitud_' || v_anio::text;
    if not exists (
      select 1
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'particiones' and c.relname = v_nombre
    ) then
      execute pg_catalog.format(
        'create table particiones.%I partition of public.valores_magnitud
           for values from (%L) to (%L)',
        v_nombre,
        v_anio::text || '-01-01 00:00:00+00',
        (v_anio + 1)::text || '-01-01 00:00:00+00'
      );
      execute pg_catalog.format(
        'alter table particiones.%I enable row level security', v_nombre
      );
      v_creadas := v_creadas + 1;
    end if;
  end loop;

  return v_creadas;
end;
$$;

revoke all on function public.asegurar_particiones_valores_magnitud(integer, integer)
  from public, anon, authenticated;
grant execute on function public.asegurar_particiones_valores_magnitud(integer, integer)
  to service_role;

select public.asegurar_particiones_valores_magnitud(
  extract(year from pg_catalog.now() at time zone 'UTC')::integer - 4,
  extract(year from pg_catalog.now() at time zone 'UTC')::integer + 1
);

create or replace function public.validar_magnitud_edificio()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_planta uuid;
  v_edificio_recinto uuid;
begin
  if new.ambito = 'PLANTA' then
    select p.id_edificio
      into v_edificio_planta
    from public.plantas p
    where p.id = new.id_planta;

    if v_edificio_planta is null
       or v_edificio_planta <> new.id_edificio then
      raise exception 'La planta debe pertenecer al edificio de la magnitud';
    end if;

  elsif new.ambito = 'RECINTO' then
    select p.id_edificio
      into v_edificio_recinto
    from public.recintos r
    join public.plantas p on p.id = r.id_planta
    where r.id = new.id_recinto;

    if v_edificio_recinto is null
       or v_edificio_recinto <> new.id_edificio then
      raise exception 'El recinto debe pertenecer al edificio de la magnitud';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_magnitudes_edificio_validar
  on public.magnitudes_edificio;

create trigger trg_magnitudes_edificio_validar
before insert or update of id_edificio, ambito, id_planta, id_recinto
on public.magnitudes_edificio
for each row execute function public.validar_magnitud_edificio();

create or replace function public.validar_magnitud_fuente()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio_destino uuid;
  v_edificio_origen uuid;
begin
  select me.id_edificio
    into v_edificio_destino
  from public.magnitudes_edificio me
  where me.id = new.id_magnitud_edificio;

  if v_edificio_destino is null then
    raise exception 'La magnitud de destino no existe';
  end if;

  if new.id_sensor is not null then
    select p.id_edificio
      into v_edificio_origen
    from public.sensores s
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta
    where s.id = new.id_sensor;
  else
    if new.id_magnitud_origen = new.id_magnitud_edificio then
      raise exception 'Una magnitud no puede ser fuente de sí misma';
    end if;

    -- ¿El destino ya alimenta (directa o indirectamente) al origen?
    if exists (
      with recursive cadena(id) as (
        select mf.id_magnitud_edificio
        from public.magnitudes_fuentes mf
        where mf.id_magnitud_origen = new.id_magnitud_edificio
        union
        select mf.id_magnitud_edificio
        from public.magnitudes_fuentes mf
        join cadena c on mf.id_magnitud_origen = c.id
      )
      select 1 from cadena where id = new.id_magnitud_origen
    ) then
      raise exception 'La fuente crearía un ciclo entre magnitudes';
    end if;

    select me.id_edificio
      into v_edificio_origen
    from public.magnitudes_edificio me
    where me.id = new.id_magnitud_origen;
  end if;

  if v_edificio_origen is null
     or v_edificio_origen <> v_edificio_destino then
    raise exception 'Las fuentes y la magnitud de destino deben pertenecer al mismo edificio';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_magnitudes_fuentes_validar
  on public.magnitudes_fuentes;

create trigger trg_magnitudes_fuentes_validar
before insert or update of id_magnitud_edificio, id_sensor, id_magnitud_origen
on public.magnitudes_fuentes
for each row execute function public.validar_magnitud_fuente();

drop trigger if exists trg_magnitudes_updated_at
  on public.magnitudes;

create trigger trg_magnitudes_updated_at
before update on public.magnitudes
for each row execute function public.set_updated_at();

drop trigger if exists trg_magnitudes_edificio_updated_at
  on public.magnitudes_edificio;

create trigger trg_magnitudes_edificio_updated_at
before update on public.magnitudes_edificio
for each row execute function public.set_updated_at();

insert into public.magnitudes (codigo, nombre, unidad, descripcion, formula) values
  ('ENERGIA_CONSUMIDA', 'Energía consumida', 'kWh', 'Energía consumida de la red u otras fuentes definidas por configuración.', null),
  ('ENERGIA_GENERADA', 'Energía generada', 'kWh', 'Energía producida por sistemas de generación.', null),
  ('ENERGIA_EXPORTADA', 'Energía exportada', 'kWh', 'Energía exportada a la red.', null),
  ('ENERGIA_AUTOCONSUMIDA', 'Energía autoconsumida', 'kWh', 'Energía generada y consumida localmente.', null),
  ('ENERGIA_TOTAL', 'Balance energético', 'kWh', 'Magnitud de balance; el motor debe definir qué componentes son compatibles.', 'ENERGIA_CONSUMIDA + ENERGIA_GENERADA - ENERGIA_EXPORTADA'),
  ('POTENCIA_TOTAL', 'Potencia total', 'kW', 'Potencia calculada según las fuentes configuradas.', null),
  ('CO2', 'Emisiones de CO2', 'kgCO2e', 'Emisiones calculadas con factores aplicables por energía y periodo.', null),
  ('CO2_EVITADO_ENERGIA_VERDE', 'CO2 evitado por energía verde', 'kgCO2e', 'Emisiones evitadas estimadas por generación renovable o electricidad verde, según el método del SaaS.', null)
on conflict (codigo) do nothing;

alter table public.magnitudes enable row level security;
alter table public.magnitudes_edificio enable row level security;
alter table public.magnitudes_fuentes enable row level security;
alter table public.valores_magnitud enable row level security;

commit;