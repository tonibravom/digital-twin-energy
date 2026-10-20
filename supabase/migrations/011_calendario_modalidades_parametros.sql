begin;

create table if not exists public.calendario_edificio (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha date not null,
  laborable boolean not null default true,
  hora_inicio time,
  hora_fin time,
  descripcion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendario_edificio_fecha_uq unique (id_edificio, fecha),
  constraint calendario_edificio_horario_ck
    check (
      (not laborable and hora_inicio is null and hora_fin is null)
      or
      (laborable and hora_inicio is not null and hora_fin is not null
       and hora_fin > hora_inicio)
    )
);

create index if not exists ix_calendario_edificio_fecha
  on public.calendario_edificio(id_edificio, fecha);

create table if not exists public.modalidades_edificio (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  modalidad varchar(20) not null,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint modalidades_edificio_modalidad_ck
    check (modalidad in ('BASIC', 'PRO', 'PREMIUM')),
  constraint modalidades_edificio_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint modalidades_edificio_estado_fecha_ck
    check ((activa and fecha_fin is null) or (not activa and fecha_fin is not null))
);

create unique index if not exists ux_modalidad_edificio_activa
  on public.modalidades_edificio(id_edificio)
  where activa;

create index if not exists ix_modalidades_edificio_historial
  on public.modalidades_edificio(id_edificio, fecha_inicio desc);

create table if not exists public.complementos_edificio (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  codigo varchar(40) not null,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activa boolean not null default true,
  configuracion jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint complementos_edificio_codigo_ck check (codigo in ('3D')),
  constraint complementos_edificio_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint complementos_edificio_estado_fecha_ck
    check ((activa and fecha_fin is null) or (not activa and fecha_fin is not null)),
  constraint complementos_edificio_config_ck
    check (jsonb_typeof(configuracion) = 'object')
);

create unique index if not exists ux_complemento_edificio_activo
  on public.complementos_edificio(id_edificio, codigo)
  where activa;

create table if not exists public.parametros_saas (
  id uuid primary key default gen_random_uuid(),
  codigo varchar(100) not null,
  nombre varchar(180) not null,
  valor_numerico numeric(24,10),
  valor_texto text,
  valor_booleano boolean,
  unidad varchar(40),
  descripcion text,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parametros_saas_un_valor_ck
    check (num_nonnulls(valor_numerico, valor_texto, valor_booleano) = 1),
  constraint parametros_saas_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint parametros_saas_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_parametros_saas_activo
  on public.parametros_saas(codigo)
  where activo;

create index if not exists ix_parametros_saas_codigo_fecha
  on public.parametros_saas(codigo, fecha_inicio desc);

drop trigger if exists trg_calendario_edificio_updated_at
  on public.calendario_edificio;

create trigger trg_calendario_edificio_updated_at
before update on public.calendario_edificio
for each row execute function public.set_updated_at();

drop trigger if exists trg_modalidades_edificio_updated_at
  on public.modalidades_edificio;

create trigger trg_modalidades_edificio_updated_at
before update on public.modalidades_edificio
for each row execute function public.set_updated_at();

drop trigger if exists trg_complementos_edificio_updated_at
  on public.complementos_edificio;

create trigger trg_complementos_edificio_updated_at
before update on public.complementos_edificio
for each row execute function public.set_updated_at();

drop trigger if exists trg_parametros_saas_updated_at
  on public.parametros_saas;

create trigger trg_parametros_saas_updated_at
before update on public.parametros_saas
for each row execute function public.set_updated_at();

insert into public.parametros_saas
  (codigo, nombre, valor_numerico, unidad, descripcion)
values
  (
    'FACTOR_CO2_ELECTRICIDAD',
    'Factor de emisiones de electricidad',
    0.20,
    'kgCO2e/kWh',
    'Factor de referencia inicial. El motor deberá aplicar el factor vigente para el periodo calculado.'
  ),
  (
    'COMUNICACION_UMBRAL_MINUTOS',
    'Umbral de pérdida de comunicación',
    30,
    'min',
    'Tiempo sin lecturas recibidas antes de considerar un sensor sin comunicación.'
  ),
  (
    'COMUNICACION_UMBRAL_MINIMO_MINUTOS',
    'Umbral mínimo de comunicación',
    15,
    'min',
    'Límite inferior permitido para configurar el umbral de comunicación.'
  ),
  (
    'COMUNICACION_UMBRAL_MAXIMO_MINUTOS',
    'Umbral máximo de comunicación',
    120,
    'min',
    'Límite superior permitido para configurar el umbral de comunicación.'
  )
on conflict do nothing;

alter table public.calendario_edificio enable row level security;
alter table public.modalidades_edificio enable row level security;
alter table public.complementos_edificio enable row level security;
alter table public.parametros_saas enable row level security;

commit;