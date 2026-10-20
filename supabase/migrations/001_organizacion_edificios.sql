begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create table if not exists public.proveedores (
  id uuid primary key default gen_random_uuid(),
  codigo varchar(50) not null unique,
  nombre varchar(200) not null,
  cif varchar(20),
  email varchar(255),
  telefono varchar(50),
  descripcion text,
  estado varchar(20) not null default 'OPERATIVO',
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint proveedores_estado_ck
    check (estado in ('OPERATIVO', 'SUSPENDIDO', 'BAJA')),
  constraint proveedores_fechas_ck
    check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint proveedores_estado_fecha_ck
    check (
      (estado <> 'BAJA' and activo and fecha_baja is null)
      or (estado = 'BAJA' and not activo and fecha_baja is not null)
    )
);

create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  codigo varchar(50) not null unique,
  nombre varchar(200) not null,
  cif varchar(20),
  email varchar(255),
  telefono varchar(50),
  descripcion text,
  estado varchar(20) not null default 'OPERATIVO',
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clientes_estado_ck
    check (estado in ('OPERATIVO', 'SUSPENDIDO', 'BAJA')),
  constraint clientes_fechas_ck
    check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint clientes_estado_fecha_ck
    check (
      (estado <> 'BAJA' and activo and fecha_baja is null)
      or (estado = 'BAJA' and not activo and fecha_baja is not null)
    )
);

create table if not exists public.proveedores_clientes (
  id uuid primary key default gen_random_uuid(),
  id_proveedor uuid not null references public.proveedores(id) on delete restrict,
  id_cliente uuid not null references public.clientes(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint proveedores_clientes_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint proveedores_clientes_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_proveedores_clientes_activo
  on public.proveedores_clientes(id_proveedor, id_cliente)
  where activo;

create index if not exists ix_proveedores_clientes_cliente
  on public.proveedores_clientes(id_cliente, activo);

create table if not exists public.edificios (
  id uuid primary key default gen_random_uuid(),
  id_cliente uuid not null references public.clientes(id) on delete restrict,
  codigo varchar(50) not null,
  nombre varchar(200) not null,
  descripcion text,
  direccion varchar(300),
  codigo_postal varchar(15),
  municipio varchar(120),
  provincia varchar(120),
  pais varchar(100) not null default 'España',
  latitud numeric(10,7),
  longitud numeric(10,7),
  superficie_construida_m2 numeric(14,2),
  superficie_util_m2 numeric(14,2),
  superficie_libre_m2 numeric(14,2),
  numero_plantas integer,
  anio_construccion integer,
  uso_edificio varchar(100),
  zona_horaria text not null default 'Europe/Madrid',
  estado varchar(40) not null default 'PENDIENTE_PARAMETRIZACION',
  motivo_estado text,
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint edificios_codigo_cliente_uq unique (id_cliente, codigo),
  constraint edificios_estado_ck
    check (estado in ('PENDIENTE_PARAMETRIZACION', 'OPERATIVO', 'SUSPENDIDO', 'BAJA')),
  constraint edificios_latitud_ck
    check (latitud is null or latitud between -90 and 90),
  constraint edificios_longitud_ck
    check (longitud is null or longitud between -180 and 180),
  constraint edificios_superficies_ck
    check (
      (superficie_construida_m2 is null or superficie_construida_m2 >= 0)
      and (superficie_util_m2 is null or superficie_util_m2 >= 0)
      and (superficie_libre_m2 is null or superficie_libre_m2 >= 0)
    ),
  constraint edificios_plantas_ck
    check (numero_plantas is null or numero_plantas >= 0),
  constraint edificios_anio_ck
    check (anio_construccion is null or anio_construccion between 1000 and 3000),
  constraint edificios_fechas_ck
    check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint edificios_estado_fecha_ck
    check (
      (estado <> 'BAJA' and activo and fecha_baja is null)
      or (estado = 'BAJA' and not activo and fecha_baja is not null)
    )
);

create index if not exists ix_edificios_cliente
  on public.edificios(id_cliente, activo);

create table if not exists public.proveedores_edificios (
  id uuid primary key default gen_random_uuid(),
  id_proveedor uuid not null references public.proveedores(id) on delete restrict,
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint proveedores_edificios_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint proveedores_edificios_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_proveedores_edificios_activo
  on public.proveedores_edificios(id_edificio)
  where activo;

create index if not exists ix_proveedores_edificios_proveedor
  on public.proveedores_edificios(id_proveedor, activo);

create table if not exists public.plantas (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  codigo varchar(50) not null,
  nombre varchar(150) not null,
  nivel integer not null default 0,
  tipo varchar(50),
  superficie_m2 numeric(14,2),
  altura_m numeric(8,2),
  descripcion text,
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plantas_codigo_edificio_uq unique (id_edificio, codigo),
  constraint plantas_nivel_ck check (nivel between -20 and 300),
  constraint plantas_superficie_ck check (superficie_m2 is null or superficie_m2 >= 0),
  constraint plantas_altura_ck check (altura_m is null or altura_m >= 0),
  constraint plantas_fechas_ck check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint plantas_estado_fecha_ck
    check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null))
);

create index if not exists ix_plantas_edificio
  on public.plantas(id_edificio, activo);

create table if not exists public.recintos (
  id uuid primary key default gen_random_uuid(),
  id_planta uuid not null references public.plantas(id) on delete restrict,
  codigo varchar(50) not null,
  nombre varchar(150) not null,
  tipo varchar(40) not null default 'OTRO',
  superficie_m2 numeric(14,2),
  altura_m numeric(8,2),
  descripcion text,
  activo boolean not null default true,
  fecha_alta date not null default current_date,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recintos_codigo_planta_uq unique (id_planta, codigo),
  constraint recintos_tipo_ck
    check (tipo in (
      'PLANTA_COMPLETA', 'ZONA_COMERCIAL', 'NAVE', 'OFICINA', 'SALA_TECNICA',
      'ALMACEN', 'HABITACION', 'ZONA_EXTERIOR', 'CUBIERTA',
      'APARCAMIENTO', 'OTRO'
    )),
  constraint recintos_superficie_ck check (superficie_m2 is null or superficie_m2 >= 0),
  constraint recintos_altura_ck check (altura_m is null or altura_m >= 0),
  constraint recintos_fechas_ck check (fecha_baja is null or fecha_baja >= fecha_alta),
  constraint recintos_estado_fecha_ck
    check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null))
);

create index if not exists ix_recintos_planta
  on public.recintos(id_planta, activo);

drop trigger if exists trg_proveedores_updated_at on public.proveedores;
create trigger trg_proveedores_updated_at
before update on public.proveedores
for each row execute function public.set_updated_at();

drop trigger if exists trg_clientes_updated_at on public.clientes;
create trigger trg_clientes_updated_at
before update on public.clientes
for each row execute function public.set_updated_at();

drop trigger if exists trg_proveedores_clientes_updated_at on public.proveedores_clientes;
create trigger trg_proveedores_clientes_updated_at
before update on public.proveedores_clientes
for each row execute function public.set_updated_at();

drop trigger if exists trg_edificios_updated_at on public.edificios;
create trigger trg_edificios_updated_at
before update on public.edificios
for each row execute function public.set_updated_at();

drop trigger if exists trg_proveedores_edificios_updated_at on public.proveedores_edificios;
create trigger trg_proveedores_edificios_updated_at
before update on public.proveedores_edificios
for each row execute function public.set_updated_at();

drop trigger if exists trg_plantas_updated_at on public.plantas;
create trigger trg_plantas_updated_at
before update on public.plantas
for each row execute function public.set_updated_at();

drop trigger if exists trg_recintos_updated_at on public.recintos;
create trigger trg_recintos_updated_at
before update on public.recintos
for each row execute function public.set_updated_at();

-- RLS activo desde la creación: sin políticas, nadie accede salvo service_role.
alter table public.proveedores enable row level security;
alter table public.clientes enable row level security;
alter table public.proveedores_clientes enable row level security;
alter table public.edificios enable row level security;
alter table public.proveedores_edificios enable row level security;
alter table public.plantas enable row level security;
alter table public.recintos enable row level security;

comment on table public.proveedores is
  'Partners/integradores. En la interfaz se denominan Partner.';
comment on column public.plantas.nivel is
  'Nivel de la planta: 0 planta baja, negativos sótanos.';
comment on table public.recintos is
  'Ubicación física dentro de una planta. Unidad base de los modelos 3D de detalle.';

commit;