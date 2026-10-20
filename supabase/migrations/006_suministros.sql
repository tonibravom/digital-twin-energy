begin;

create table if not exists public.suministros (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  codigo varchar(80) not null,
  nombre varchar(150) not null,
  tipo varchar(30) not null,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  descripcion text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suministros_codigo_edificio_uq unique (id_edificio, codigo),
  constraint suministros_tipo_ck
    check (tipo in ('ELECTRICIDAD', 'GAS', 'AGUA', 'AGUA_INCENDIOS', 'GENERACION')),
  constraint suministros_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint suministros_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create index if not exists ix_suministros_edificio
  on public.suministros(id_edificio, activo);

create table if not exists public.suministros_electricidad (
  id_suministro uuid primary key references public.suministros(id) on delete restrict,
  cups varchar(40),
  contador varchar(100),
  tipo_contador varchar(20),
  fases varchar(20),
  tarifa varchar(80),
  potencia_p1_kw numeric(12,3),
  potencia_p2_kw numeric(12,3),
  potencia_p3_kw numeric(12,3),
  potencia_p4_kw numeric(12,3),
  potencia_p5_kw numeric(12,3),
  potencia_p6_kw numeric(12,3),
  energia_verde boolean not null default false,
  porcentaje_energia_verde numeric(5,2),
  certificacion_verde text,
  constraint suministro_electricidad_contador_ck
    check (tipo_contador is null or tipo_contador in ('TELEMEDIDA', 'CONVENCIONAL', 'OTRO')),
  constraint suministro_electricidad_verde_ck
    check (
      porcentaje_energia_verde is null
      or (porcentaje_energia_verde between 0 and 100)
    ),
  constraint suministro_electricidad_fases_ck
    check (fases is null or fases in ('MONOFASICA', 'TRIFASICA')),
  constraint suministro_electricidad_potencias_ck
    check (
      (potencia_p1_kw is null or potencia_p1_kw >= 0)
      and (potencia_p2_kw is null or potencia_p2_kw >= 0)
      and (potencia_p3_kw is null or potencia_p3_kw >= 0)
      and (potencia_p4_kw is null or potencia_p4_kw >= 0)
      and (potencia_p5_kw is null or potencia_p5_kw >= 0)
      and (potencia_p6_kw is null or potencia_p6_kw >= 0)
    )
);

create table if not exists public.suministros_gas (
  id_suministro uuid primary key references public.suministros(id) on delete restrict,
  cups varchar(40),
  contador varchar(100),
  tarifa varchar(80),
  presion_operacion numeric(12,4),
  unidad_presion varchar(20)
);

create table if not exists public.suministros_agua (
  id_suministro uuid primary key references public.suministros(id) on delete restrict,
  contrato varchar(100),
  contador varchar(100),
  caudal_contratado numeric(14,4),
  unidad_caudal varchar(20),
  tarifa varchar(80)
);

create table if not exists public.suministros_agua_incendios (
  id_suministro uuid primary key references public.suministros(id) on delete restrict,
  contrato varchar(100),
  contador varchar(100),
  caudal_contratado numeric(14,4),
  unidad_caudal varchar(20),
  tarifa varchar(80)
);

create table if not exists public.suministros_generacion (
  id_suministro uuid primary key references public.suministros(id) on delete restrict,
  tecnologia varchar(30) not null,
  potencia_nominal_kw numeric(14,4),
  potencia_pico_kw numeric(14,4),
  superficie_m2 numeric(14,2),
  fecha_puesta_marcha date,
  energia_verde boolean not null default true,
  descripcion text,
  constraint suministro_generacion_tecnologia_ck
    check (tecnologia in ('FOTOVOLTAICA', 'EOLICA', 'COGENERACION', 'OTRA')),
  constraint suministro_generacion_valores_ck
    check (
      (potencia_nominal_kw is null or potencia_nominal_kw >= 0)
      and (potencia_pico_kw is null or potencia_pico_kw >= 0)
      and (superficie_m2 is null or superficie_m2 >= 0)
    )
);

create table if not exists public.suministros_dispositivos (
  id uuid primary key default gen_random_uuid(),
  id_suministro uuid not null references public.suministros(id) on delete restrict,
  id_dispositivo uuid not null references public.dispositivos(id) on delete restrict,
  fecha_inicio date not null default current_date,
  fecha_fin date,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint suministro_dispositivo_fechas_ck
    check (fecha_fin is null or fecha_fin >= fecha_inicio),
  constraint suministro_dispositivo_estado_fecha_ck
    check ((activo and fecha_fin is null) or (not activo and fecha_fin is not null))
);

create unique index if not exists ux_suministro_dispositivo_activo
  on public.suministros_dispositivos(id_suministro, id_dispositivo)
  where activo;

create index if not exists ix_suministro_dispositivos_dispositivo
  on public.suministros_dispositivos(id_dispositivo, activo);

create or replace function public.validar_tipo_suministro()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_tipo varchar(30);
begin
  select s.tipo
    into v_tipo
  from public.suministros s
  where s.id = new.id_suministro;

  if v_tipo is null then
    raise exception 'El suministro indicado no existe';
  end if;

  if v_tipo <> tg_argv[0] then
    raise exception 'La tabla específica no corresponde al tipo de suministro %', v_tipo;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_suministro_electricidad_tipo
  on public.suministros_electricidad;
create trigger trg_suministro_electricidad_tipo
before insert or update on public.suministros_electricidad
for each row execute function public.validar_tipo_suministro('ELECTRICIDAD');

drop trigger if exists trg_suministro_gas_tipo
  on public.suministros_gas;
create trigger trg_suministro_gas_tipo
before insert or update on public.suministros_gas
for each row execute function public.validar_tipo_suministro('GAS');

drop trigger if exists trg_suministro_agua_tipo
  on public.suministros_agua;
create trigger trg_suministro_agua_tipo
before insert or update on public.suministros_agua
for each row execute function public.validar_tipo_suministro('AGUA');

drop trigger if exists trg_suministro_agua_incendios_tipo
  on public.suministros_agua_incendios;
create trigger trg_suministro_agua_incendios_tipo
before insert or update on public.suministros_agua_incendios
for each row execute function public.validar_tipo_suministro('AGUA_INCENDIOS');

drop trigger if exists trg_suministro_generacion_tipo
  on public.suministros_generacion;
create trigger trg_suministro_generacion_tipo
before insert or update on public.suministros_generacion
for each row execute function public.validar_tipo_suministro('GENERACION');

drop trigger if exists trg_suministros_updated_at
  on public.suministros;

create trigger trg_suministros_updated_at
before update on public.suministros
for each row execute function public.set_updated_at();

alter table public.suministros enable row level security;
alter table public.suministros_electricidad enable row level security;
alter table public.suministros_gas enable row level security;
alter table public.suministros_agua enable row level security;
alter table public.suministros_agua_incendios enable row level security;
alter table public.suministros_generacion enable row level security;
alter table public.suministros_dispositivos enable row level security;

commit;