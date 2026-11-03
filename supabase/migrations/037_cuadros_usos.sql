-- =========================================================
-- 037 · Cuadros eléctricos, función de cada medidor y Sankey por cuadro
-- Decisión D46 (03/11/2026).
--
-- Cada medidor de energía se configura en este orden:
--   1. Qué mide (sensores.funcion_medidor):
--        GENERAL  contador general (acometida)
--        CUADRO   total de un cuadro eléctrico
--        USO      submedidor de un uso final
--   2. Uso (solo los submedidores), del catálogo usos_energia.
--   3. Cuadro del que depende (sensores.id_cuadro) o ninguno: un medidor
--      independiente, como el contador de gas de la caldera.
--
-- Los cuadros (cuadros_electricos) están en una planta o en un recinto y
-- pueden colgar de otro cuadro (el del local cuelga del de planta baja).
--
-- El motor calcula, por cuadro con medidor y día:
--   otros usos del cuadro = total del cuadro − sus submedidores
--                           − lo medido en los cuadros que cuelgan de él
-- (de un cuadro hijo con medidor se resta su total; de uno sin medidor,
--  sus submedidores y, bajando, lo mismo con sus hijos).
-- Lo que el contador general no reparte entre cuadros y medidores
-- independientes, si no tiene reparto configurado (024), es
-- "Otros usos · no medido" (estimado).
--
-- Usos: tres grupos, como en el Sankey:
--   HVAC        climatización, refrigeración, calefacción, ACS,
--               calefacción y ACS, renovación de aire
--   Alumbrado   (uso final, sin subgrupos)
--   Otros usos  informática, servicios comunes y "otros usos" (resto)
--
-- Sankey (edificio): fuentes → vector → grupo → detalle. El detalle de
-- HVAC es el uso final; el de Alumbrado y Otros usos, el uso y el cuadro
-- ("Alumbrado · Planta 1", "Otros usos · Local comercial").
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Catálogo de usos
-- ---------------------------------------------------------
update public.usos_energia set nombre = 'Alumbrado' where codigo = 'ILUMINACION';
update public.usos_energia set nombre = 'Otros usos' where codigo = 'OTROS';

insert into public.usos_energia (codigo, nombre, id_padre, orden)
select x.codigo, x.nombre, p.id, x.orden
from (values ('HVAC', 'HVAC_REFRIGERACION', 'Refrigeración', 2),
             ('HVAC', 'HVAC_CALEFACCION', 'Calefacción', 3),
             ('HVAC', 'HVAC_ACS', 'Agua caliente sanitaria (ACS)', 4),
             ('HVAC', 'HVAC_CALEFACCION_ACS', 'Calefacción y ACS', 5),
             ('OTROS', 'OTROS_INFORMATICA', 'Informática', 1),
             ('OTROS', 'OTROS_SERVICIOS_COMUNES', 'Servicios comunes', 2),
             ('OTROS', 'OTROS_SIN_DESGLOSE', 'Otros usos', 9)) x(padre, codigo, nombre, orden)
join public.usos_energia p on p.codigo = x.padre
on conflict (codigo) do nothing;
update public.usos_energia set orden = 6 where codigo = 'HVAC_RENOVACION';

-- "Otros usos" pasa a ser un grupo: lo asignado antes al grupo va a su uso final
do $$
declare
  v_otros smallint := (select id from public.usos_energia where codigo = 'OTROS');
  v_final smallint := (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE');
begin
  update public.sensores set id_uso_energia = v_final where id_uso_energia = v_otros;
  update public.repartos_uso_edificio set id_uso_energia = v_final where id_uso_energia = v_otros;
  update public.resumenes_diarios_usos set id_uso_energia = v_final where id_uso_energia = v_otros;
end;
$$;

-- ---------------------------------------------------------
-- 2. Cuadros eléctricos
-- ---------------------------------------------------------
create table if not exists public.cuadros_electricos (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id) on delete restrict,
  id_planta uuid references public.plantas(id) on delete restrict,
  id_recinto uuid references public.recintos(id) on delete restrict,
  id_cuadro_padre uuid references public.cuadros_electricos(id) on delete restrict,
  codigo varchar(40) not null,
  nombre varchar(120) not null,
  activo boolean not null default true,
  fecha_baja date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cuadros_electricos_uq unique (id_edificio, codigo),
  constraint cuadros_electricos_ubicacion_ck check (num_nonnulls(id_planta, id_recinto) = 1),
  constraint cuadros_electricos_baja_ck check ((activo and fecha_baja is null) or (not activo and fecha_baja is not null)),
  constraint cuadros_electricos_padre_ck check (id_cuadro_padre is distinct from id)
);

comment on table public.cuadros_electricos is
  'Cuadros eléctricos del edificio, en una planta o en un recinto, y del que cuelga cada uno. Sus "otros usos" = total del cuadro − submedidores − cuadros que cuelgan de él.';

alter table public.cuadros_electricos enable row level security;

create index if not exists cuadros_electricos_edificio_idx on public.cuadros_electricos (id_edificio);
create index if not exists cuadros_electricos_padre_idx on public.cuadros_electricos (id_cuadro_padre);

-- Planta, recinto y cuadro padre del mismo edificio; sin ciclos
create or replace function public.validar_cuadro_electrico()
returns trigger
language plpgsql
security definer   -- comprueba con todos los datos; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_actual uuid;
  v_vueltas integer := 0;
begin
  if new.id_planta is not null and not exists (
       select 1 from public.plantas where id = new.id_planta and id_edificio = new.id_edificio) then
    raise exception 'La planta del cuadro no es de este edificio';
  end if;
  if new.id_recinto is not null and public.obtener_edificio_recinto(new.id_recinto) is distinct from new.id_edificio then
    raise exception 'El recinto del cuadro no es de este edificio';
  end if;
  if new.id_cuadro_padre is not null then
    if not exists (select 1 from public.cuadros_electricos
                   where id = new.id_cuadro_padre and id_edificio = new.id_edificio and activo) then
      raise exception 'El cuadro del que depende no es de este edificio o está dado de baja';
    end if;
    v_actual := new.id_cuadro_padre;
    while v_actual is not null loop
      if v_actual = new.id then
        raise exception 'Un cuadro no puede depender de sí mismo ni de un cuadro que depende de él';
      end if;
      v_vueltas := v_vueltas + 1;
      exit when v_vueltas > 50;
      select id_cuadro_padre into v_actual from public.cuadros_electricos where id = v_actual;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cuadros_electricos_validar on public.cuadros_electricos;
create trigger trg_cuadros_electricos_validar
before insert or update on public.cuadros_electricos
for each row execute function public.validar_cuadro_electrico();

drop trigger if exists trg_cuadros_electricos_updated_at on public.cuadros_electricos;
create trigger trg_cuadros_electricos_updated_at
before update on public.cuadros_electricos
for each row execute function public.set_updated_at();

drop trigger if exists trg_auditoria on public.cuadros_electricos;
create trigger trg_auditoria after insert or update or delete on public.cuadros_electricos
for each row execute function public.auditar_cambio();

drop policy if exists cuadros_electricos_select on public.cuadros_electricos;
create policy cuadros_electricos_select on public.cuadros_electricos
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio));

drop policy if exists cuadros_electricos_insert on public.cuadros_electricos;
create policy cuadros_electricos_insert on public.cuadros_electricos
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES'));

drop policy if exists cuadros_electricos_update on public.cuadros_electricos;
create policy cuadros_electricos_update on public.cuadros_electricos
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_MAGNITUDES'));

-- Nombre corto de la ubicación del cuadro ("Planta 1", "Local comercial")
create or replace function public.ubicacion_cuadro(p_id_cuadro uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(r.nombre, p.nombre, c.nombre)
  from public.cuadros_electricos c
  left join public.recintos r on r.id = c.id_recinto
  left join public.plantas p on p.id = c.id_planta
  where c.id = p_id_cuadro;
$$;

-- ---------------------------------------------------------
-- 3. Función de cada medidor y cuadro del que depende
-- ---------------------------------------------------------
alter table public.sensores
  add column if not exists funcion_medidor varchar(10),
  add column if not exists id_cuadro uuid references public.cuadros_electricos(id) on delete restrict;

comment on column public.sensores.funcion_medidor is
  'Qué mide un medidor de energía: GENERAL (contador general), CUADRO (total de un cuadro) o USO (submedidor de un uso). Vacío en el resto de sensores.';
comment on column public.sensores.id_cuadro is
  'Cuadro eléctrico que mide (CUADRO) o del que depende el submedidor (USO). Vacío en medidores independientes.';

update public.sensores set funcion_medidor = 'USO' where id_uso_energia is not null and funcion_medidor is null;

alter table public.sensores drop constraint if exists sensores_funcion_medidor_ck;
alter table public.sensores add constraint sensores_funcion_medidor_ck check (
  (funcion_medidor is null and id_uso_energia is null and id_cuadro is null)
  or (funcion_medidor = 'GENERAL' and id_uso_energia is null and id_cuadro is null)
  or (funcion_medidor = 'CUADRO' and id_uso_energia is null and id_cuadro is not null)
  or (funcion_medidor = 'USO' and id_uso_energia is not null));

create index if not exists sensores_cuadro_idx on public.sensores (id_cuadro) where id_cuadro is not null;
drop index if exists public.sensores_un_medidor_por_cuadro_uq;
create unique index sensores_un_medidor_por_cuadro_uq on public.sensores (id_cuadro)
  where funcion_medidor = 'CUADRO' and activo;

-- Sustituye la validación de la 024: uso final, función coherente y cuadro del mismo edificio
create or replace function public.validar_uso_sensor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_tipo text;
begin
  if new.id_uso_energia is not null and not public.es_uso_final(new.id_uso_energia) then
    raise exception 'Asigne un uso final (por ejemplo "Climatización"), no un grupo ("HVAC")';
  end if;
  -- Compatibilidad: un submedidor con uso y sin función es un submedidor de uso
  if new.id_uso_energia is not null and new.funcion_medidor is null then
    new.funcion_medidor := 'USO';
  end if;
  if new.funcion_medidor = 'CUADRO' and new.id_cuadro is null then
    raise exception 'Indique el cuadro eléctrico que mide este medidor';
  end if;
  if new.funcion_medidor = 'USO' and new.id_uso_energia is null then
    raise exception 'Indique el uso que mide este submedidor';
  end if;
  if new.id_cuadro is not null then
    if not exists (select 1 from public.cuadros_electricos c
                   where c.id = new.id_cuadro and c.activo
                     and c.id_edificio = public.obtener_edificio_recinto(new.id_recinto)) then
      raise exception 'El cuadro eléctrico no es de este edificio o está dado de baja';
    end if;
    select te.codigo into v_tipo from public.tipos_energia te where te.id = new.id_tipo_energia;
    if v_tipo is not null and v_tipo <> 'ELECTRICIDAD' then
      raise exception 'Solo los medidores eléctricos pueden depender de un cuadro eléctrico';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sensores_validar_uso on public.sensores;
create trigger trg_sensores_validar_uso
before insert or update of id_uso_energia, funcion_medidor, id_cuadro, id_recinto on public.sensores
for each row execute function public.validar_uso_sensor();

-- Sustituir un sensor conserva su función y su cuadro (versión de la 032 ampliada)
create or replace function public.sustituir_sensor(
  p_id_sensor uuid,
  p_direccion jsonb default null,
  p_id_dispositivo_nuevo uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.sensores%rowtype;
  v_nuevo uuid;
  v_sufijo text;
begin
  select * into v_old from public.sensores where id = p_id_sensor and activo;
  if not found then
    raise exception 'El sensor no existe o ya está inactivo';
  end if;

  v_sufijo := '#' || pg_catalog.to_char(current_date, 'YYYYMMDD') || '-' || pg_catalog.left(v_old.id::text, 8);

  if auth.uid() is not null and not private.usuario_puede_edificio(
       public.obtener_edificio_recinto(v_old.id_recinto), 'MODIFICAR_SENSOR') then
    raise exception 'Sin permiso para sustituir sensores en este edificio' using errcode = '42501';
  end if;

  update public.sensores
     set codigo = pg_catalog.left(v_old.codigo, 130) || v_sufijo,
         activo = false,
         fecha_baja = current_date
   where id = v_old.id;

  insert into public.sensores (
    id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento,
    id_tipo_energia, id_flujo_energia, id_uso_energia, funcion_medidor, id_cuadro, codigo, nombre, magnitud_origen,
    unidad, unidad_origen, escala, desplazamiento, valor_minimo, valor_maximo,
    politica_vacios, direccion, descripcion, id_sensor_anterior)
  values (
    coalesce(p_id_dispositivo_nuevo, v_old.id_dispositivo),
    case when p_id_dispositivo_nuevo is null then v_old.id_conexion end,
    v_old.id_recinto, v_old.id_familia, v_old.id_naturaleza, v_old.id_tratamiento,
    v_old.id_tipo_energia, v_old.id_flujo_energia, v_old.id_uso_energia, v_old.funcion_medidor, v_old.id_cuadro,
    v_old.codigo, v_old.nombre,
    v_old.magnitud_origen, v_old.unidad, v_old.unidad_origen, v_old.escala, v_old.desplazamiento,
    v_old.valor_minimo, v_old.valor_maximo, v_old.politica_vacios,
    coalesce(p_direccion, v_old.direccion), v_old.descripcion, v_old.id)
  returning id into v_nuevo;

  update public.magnitudes_fuentes set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.ubicaciones_3d set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.reglas_alarma set id_sensor = v_nuevo where id_sensor = v_old.id and activa;
  update public.sensores_recintos_ambito set id_sensor = v_nuevo where id_sensor = v_old.id and activo;

  return v_nuevo;
end;
$$;

-- ---------------------------------------------------------
-- 4. Resúmenes por uso y cuadro
-- ---------------------------------------------------------
alter table public.resumenes_diarios_usos
  add column if not exists id_cuadro uuid references public.cuadros_electricos(id) on delete restrict;
alter table public.resumenes_diarios_usos drop constraint if exists resumenes_diarios_usos_pk;
alter table public.resumenes_diarios_usos drop constraint if exists resumenes_diarios_usos_uq;
alter table public.resumenes_diarios_usos add constraint resumenes_diarios_usos_uq
  unique nulls not distinct (id_edificio, fecha, id_uso_energia, tipo_energia, id_cuadro);

comment on column public.resumenes_diarios_usos.id_cuadro is
  'Cuadro eléctrico del submedidor, o del que se calcula "otros usos" por diferencia. Vacío en medidores independientes.';

-- ---------------------------------------------------------
-- 5. Motor: sensores que intervienen, recálculos y cálculo por cuadro
-- ---------------------------------------------------------
create or replace function private.motor_sensores_edificio(p_id_edificio uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive base as (
    select mf.id_sensor as id
    from public.magnitudes_fuentes mf
    join public.magnitudes_edificio me on me.id = mf.id_magnitud_edificio
    where me.id_edificio = p_id_edificio and me.activa and mf.id_sensor is not null
    union
    select s.id from public.sensores s
    where s.funcion_medidor in ('CUADRO', 'USO') and s.activo
      and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
  ),
  cadena(id) as (
    select id from base
    union
    select s.id_sensor_anterior from public.sensores s join cadena c on c.id = s.id
    where s.id_sensor_anterior is not null
  )
  select id from cadena;
$$;

create or replace function private.motor_tras_configuracion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_sensores uuid[];
begin
  if tg_table_name = 'magnitudes_fuentes' then
    select me.id_edificio into v_edificio from public.magnitudes_edificio me
    where me.id = coalesce(new.id_magnitud_edificio, old.id_magnitud_edificio);
  elsif tg_table_name in ('magnitudes_edificio', 'cuadros_electricos') then
    v_edificio := coalesce(new.id_edificio, old.id_edificio);
  else -- sensores: cambio de función, uso o cuadro del medidor
    v_edificio := public.obtener_edificio_recinto(coalesce(new.id_recinto, old.id_recinto));
  end if;

  select pg_catalog.array_agg(id) into v_sensores from private.motor_sensores_edificio(v_edificio) id;
  -- (condiciones anidadas: cada tabla solo tiene sus columnas)
  if tg_table_name = 'sensores' then
    v_sensores := coalesce(v_sensores, '{}') || new.id;
  elsif tg_table_name = 'magnitudes_fuentes' then
    if coalesce(new.id_sensor, old.id_sensor) is not null then
      v_sensores := coalesce(v_sensores, '{}') || coalesce(old.id_sensor, new.id_sensor);
    end if;
  end if;
  perform private.motor_marcar(v_edificio, private.motor_primera_lectura(v_sensores), 'CONFIGURACION');
  return null;
end;
$$;

drop trigger if exists trg_sensores_uso_motor on public.sensores;
create trigger trg_sensores_uso_motor
after update of id_uso_energia, funcion_medidor, id_cuadro on public.sensores
for each row when (old.id_uso_energia is distinct from new.id_uso_energia
                   or old.funcion_medidor is distinct from new.funcion_medidor
                   or old.id_cuadro is distinct from new.id_cuadro)
execute function private.motor_tras_configuracion();

drop trigger if exists trg_cuadros_electricos_motor on public.cuadros_electricos;
create trigger trg_cuadros_electricos_motor
after update of id_cuadro_padre, activo on public.cuadros_electricos
for each row execute function private.motor_tras_configuracion();

-- Versión de la 032 con el consumo por usos y cuadros
create or replace function public.motor_calcular(p_id_edificio uuid, p_desde timestamptz, p_hasta timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_origen constant timestamptz := timestamptz '2000-01-01 00:00:00+00';
  v_zona text;
  v_desde timestamptz;
  v_hasta timestamptz := least(p_hasta, pg_catalog.now() + interval '1 day');
  v_previa timestamptz;
  v_dia_desde date;
  v_dia_hasta date;
  v_ini_dias timestamptz;
  v_fin_dias timestamptz;
  v_avisos text[] := '{}';
  v_nivel integer := 0;
  v_hechas integer;
  v_valores integer;
  v_resumenes integer;
  v_usos integer;
  v_otros integer;
  v_uso_otros smallint;
  r record;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente';
  end if;
  if p_desde is null or p_desde >= v_hasta then
    return pg_catalog.jsonb_build_object('id_edificio', p_id_edificio, 'valores', 0, 'resumenes', 0);
  end if;

  select min(x.f) into v_previa
  from private.motor_sensores_edificio(p_id_edificio) s(id)
  cross join lateral (select l.fecha_hora as f from public.lecturas l
                      where l.id_sensor = s.id and l.fecha_hora < p_desde
                        and l.fecha_hora >= p_desde - interval '7 days'
                      order by l.fecha_hora desc limit 1) x;
  v_desde := pg_catalog.date_bin('15 minutes', least(p_desde, coalesce(v_previa, p_desde)), v_origen);

  perform public.asegurar_particiones_valores_magnitud(
    extract(year from v_desde at time zone 'UTC')::integer,
    extract(year from v_hasta at time zone 'UTC')::integer);

  if pg_catalog.to_regclass('pg_temp._motor_mag') is null then
    create temporary table _motor_mag (id uuid primary key, unidad text, nivel integer) on commit drop;
    create temporary table _motor_val (id_me uuid, instante timestamptz, valor double precision, calidad smallint) on commit drop;
  else
    truncate _motor_mag;
    truncate _motor_val;
  end if;
  if pg_catalog.to_regclass('pg_temp._motor_dia') is null then
    create temporary table _motor_dia (funcion text, id_uso smallint, id_cuadro uuid, tipo text, fecha date,
                                       kwh double precision) on commit drop;
  else
    truncate _motor_dia;
  end if;

  insert into _motor_mag (id, unidad, nivel)
  select me.id, m.unidad, null
  from public.magnitudes_edificio me
  join public.magnitudes m on m.id = me.id_magnitud
  where me.id_edificio = p_id_edificio and me.activa
    and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id);

  loop
    update _motor_mag mm set nivel = v_nivel
    where mm.nivel is null
      and not exists (select 1 from public.magnitudes_fuentes mf
                      left join _motor_mag o on o.id = mf.id_magnitud_origen
                      where mf.id_magnitud_edificio = mm.id and mf.id_magnitud_origen is not null
                        and (o.id is null or o.nivel is null));
    get diagnostics v_hechas = row_count;
    exit when v_hechas = 0;

    for r in
      select mf.id_magnitud_edificio as id_me, mf.id_sensor, mf.papel, mm.unidad as unidad_mag,
             s.unidad as unidad_sensor, s.codigo, te.codigo as tipo_energia
      from public.magnitudes_fuentes mf
      join _motor_mag mm on mm.id = mf.id_magnitud_edificio and mm.nivel = v_nivel
      join public.sensores s on s.id = mf.id_sensor
      left join public.tipos_energia te on te.id = s.id_tipo_energia
    loop
      if private.motor_factor_unidad(r.unidad_sensor, r.unidad_mag, r.tipo_energia, v_desde::date) is null then
        v_avisos := v_avisos || pg_catalog.format('Sensor %s: no se puede pasar de %s a %s', r.codigo, r.unidad_sensor, r.unidad_mag);
        continue;
      end if;
      insert into _motor_val (id_me, instante, valor, calidad)
      select r.id_me, x.instante,
             x.valor * private.motor_factor_unidad(r.unidad_sensor, r.unidad_mag, r.tipo_energia,
                                                   (x.instante at time zone v_zona)::date)
                     * case when r.papel = 'RESTA' then -1 else 1 end,
             x.calidad
      from private.motor_serie_fuente(r.id_sensor, v_desde, v_hasta) x;
    end loop;

    insert into _motor_val (id_me, instante, valor, calidad)
    select mf.id_magnitud_edificio, v.instante,
           v.valor * case when mf.papel = 'RESTA' then -1 else 1 end, v.calidad
    from public.magnitudes_fuentes mf
    join _motor_mag mm on mm.id = mf.id_magnitud_edificio and mm.nivel = v_nivel
    join (select id_me, instante, sum(valor) as valor, max(calidad) as calidad
          from _motor_val group by 1, 2) v on v.id_me = mf.id_magnitud_origen;

    v_nivel := v_nivel + 1;
    exit when v_nivel > 20;
  end loop;

  if exists (select 1 from _motor_mag where nivel is null) then
    v_avisos := v_avisos || 'Algunas magnitudes dependen de otras que no tienen fuentes: no se calculan';
  end if;

  delete from public.valores_magnitud v
  where v.id_magnitud_edificio in (select me.id from public.magnitudes_edificio me where me.id_edificio = p_id_edificio)
    and v.fecha_hora >= v_desde and v.fecha_hora < v_hasta;

  insert into public.valores_magnitud (id_magnitud_edificio, fecha_hora, valor, calidad, version_motor)
  select id_me, instante, sum(valor), max(calidad), '1.1'
  from _motor_val
  group by id_me, instante;
  get diagnostics v_valores = row_count;

  -- -------- Resúmenes diarios de los días locales afectados --------
  v_dia_desde := (v_desde at time zone v_zona)::date;
  v_dia_hasta := ((v_hasta - interval '1 microsecond') at time zone v_zona)::date;
  v_ini_dias := v_dia_desde::timestamp at time zone v_zona;
  v_fin_dias := (v_dia_hasta + 1)::timestamp at time zone v_zona;

  delete from public.resumenes_diarios rd
  where rd.id_edificio = p_id_edificio and rd.origen = 'MOTOR'
    and rd.fecha between v_dia_desde and v_dia_hasta;

  insert into public.resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen)
  select p_id_edificio, d.fecha, d.indicador, d.valor,
         d.intervalos >= extract(epoch from ((d.fecha + 1)::timestamp at time zone v_zona)
                                          - (d.fecha::timestamp at time zone v_zona)) / 900
           and d.calidad = 0,
         'MOTOR'
  from (
    select (v.fecha_hora at time zone v_zona)::date as fecha,
           case m.codigo when 'ENERGIA_EXPORTADA' then 'ELECTRICIDAD_EXPORTADA' else m.codigo end as indicador,
           sum(v.valor) as valor, count(distinct v.fecha_hora) as intervalos, max(v.calidad) as calidad
    from public.valores_magnitud v
    join public.magnitudes_edificio me on me.id = v.id_magnitud_edificio
    join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = p_id_edificio and me.activa and me.ambito = 'EDIFICIO'
      and m.codigo in ('CONSUMO_ELECTRICIDAD', 'CONSUMO_GAS', 'CONSUMO_AGUA', 'ENERGIA_EXPORTADA',
                       'GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA', 'GENERACION_SOLAR_TERMICA',
                       'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')
      and v.fecha_hora >= v_ini_dias and v.fecha_hora < v_fin_dias
    group by 1, 2
  ) d
  on conflict (id_edificio, fecha, indicador) do nothing;
  get diagnostics v_resumenes = row_count;

  -- -------- Consumo por usos y cuadros (Sankey) --------
  -- 1) kWh diarios de cada medidor de cuadro o de uso
  insert into _motor_dia (funcion, id_uso, id_cuadro, tipo, fecha, kwh)
  select s.funcion_medidor, s.id_uso_energia, s.id_cuadro,
         case te.codigo when 'GAS' then 'GAS' when 'TERMICA' then 'CALOR_RENOVABLE' else 'ELECTRICIDAD' end,
         (x.instante at time zone v_zona)::date,
         sum(x.valor * private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, (x.instante at time zone v_zona)::date))
  from public.sensores s
  join public.tipos_energia te on te.id = s.id_tipo_energia and te.codigo in ('ELECTRICIDAD', 'GAS', 'TERMICA')
  cross join lateral private.motor_serie_fuente(s.id, v_ini_dias, v_fin_dias) x
  where s.activo and s.funcion_medidor in ('CUADRO', 'USO')
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
    and private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, v_dia_desde) is not null
  group by 1, 2, 3, 4, 5
  having sum(x.valor) is not null;

  delete from public.resumenes_diarios_usos ru
  where ru.id_edificio = p_id_edificio and ru.fecha between v_dia_desde and v_dia_hasta;

  -- 2) Lo que miden los submedidores, con su cuadro
  insert into public.resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, id_cuadro, valor)
  select p_id_edificio, fecha, id_uso, tipo, id_cuadro, sum(kwh)
  from _motor_dia where funcion = 'USO'
  group by fecha, id_uso, tipo, id_cuadro;
  get diagnostics v_usos = row_count;

  -- 3) "Otros usos" de cada cuadro con medidor, por diferencia
  v_uso_otros := (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE');
  with recursive
  cuadros as (
    select c.id, c.id_cuadro_padre,
           exists (select 1 from public.sensores s where s.id_cuadro = c.id and s.funcion_medidor = 'CUADRO' and s.activo) as con_medidor
    from public.cuadros_electricos c
    where c.id_edificio = p_id_edificio and c.activo
  ),
  -- Para cada cuadro con medidor: él mismo y, bajando, sus hijos; se baja por los
  -- cuadros sin medidor y se para en los que tienen medidor (se resta su total).
  arbol(raiz, id, con_medidor) as (
    select c.id, c.id, c.con_medidor from cuadros c where c.con_medidor
    union all
    select a.raiz, h.id, h.con_medidor
    from arbol a join cuadros h on h.id_cuadro_padre = a.id
    where a.id = a.raiz or not a.con_medidor
  ),
  restar as (
    select a.raiz, d.fecha, sum(d.kwh) as kwh
    from arbol a
    join _motor_dia d on d.id_cuadro = a.id and d.tipo = 'ELECTRICIDAD'
     and ((d.funcion = 'USO' and (a.id = a.raiz or not a.con_medidor))
          or (d.funcion = 'CUADRO' and a.id <> a.raiz and a.con_medidor))
    group by a.raiz, d.fecha
  ),
  totales as (
    select d.id_cuadro, d.fecha, sum(d.kwh) as kwh from _motor_dia d
    where d.funcion = 'CUADRO' group by d.id_cuadro, d.fecha
  )
  insert into public.resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, id_cuadro, valor)
  select p_id_edificio, t.fecha, v_uso_otros, 'ELECTRICIDAD', t.id_cuadro,
         greatest(t.kwh - coalesce(rs.kwh, 0), 0)
  from totales t
  left join restar rs on rs.raiz = t.id_cuadro and rs.fecha = t.fecha
  on conflict (id_edificio, fecha, id_uso_energia, tipo_energia, id_cuadro)
    do update set valor = public.resumenes_diarios_usos.valor + excluded.valor;
  get diagnostics v_otros = row_count;

  if exists (
    select 1 from _motor_dia d
    where d.funcion = 'CUADRO'
    group by d.id_cuadro, d.fecha
    having sum(d.kwh) + 0.5 < coalesce((
      select sum(u.kwh) from _motor_dia u where u.id_cuadro = d.id_cuadro and u.fecha = d.fecha and u.funcion = 'USO'), 0)) then
    v_avisos := v_avisos || 'En algún cuadro los submedidores suman más que el total del cuadro: revise su configuración';
  end if;

  return pg_catalog.jsonb_build_object(
    'id_edificio', p_id_edificio, 'desde', v_desde, 'hasta', v_hasta,
    'magnitudes', (select count(*) from _motor_mag where nivel is not null),
    'valores', v_valores, 'resumenes', v_resumenes, 'usos', v_usos, 'otros_cuadros', v_otros,
    'avisos', pg_catalog.to_jsonb(v_avisos));
end;
$$;

-- ---------------------------------------------------------
-- 6. Sankey con columna de detalle
-- ---------------------------------------------------------
create or replace function public.sankey_energia(
  p_nivel text,
  p_id uuid,
  p_desde date,
  p_hasta date
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with
  edif as (select id from public.edificios_de_ambito(p_nivel, p_id) as id),
  por_cuadro as (select pg_catalog.upper(p_nivel) = 'EDIFICIO' as si),
  fuentes as (
    select r.id_edificio,
      coalesce(sum(r.valor) filter (where r.indicador = 'CONSUMO_ELECTRICIDAD'), 0) as red,
      coalesce(sum(r.valor) filter (where r.indicador = 'GENERACION_FOTOVOLTAICA'), 0) as fv,
      coalesce(sum(r.valor) filter (where r.indicador = 'GENERACION_EOLICA'), 0) as eolica,
      coalesce(sum(r.valor) filter (where r.indicador = 'ELECTRICIDAD_EXPORTADA'), 0) as exportada,
      coalesce(sum(r.valor) filter (where r.indicador = 'CONSUMO_GAS'), 0) as gas,
      coalesce(sum(r.valor) filter (where r.indicador = 'GENERACION_SOLAR_TERMICA'), 0) as solar_termica,
      coalesce(sum(r.valor) filter (where r.indicador = 'GENERACION_GEOTERMIA'), 0) as geotermia,
      coalesce(sum(r.valor) filter (where r.indicador = 'GENERACION_BIOMASA'), 0) as biomasa
    from public.resumenes_diarios r
    where r.id_edificio in (select id from edif) and r.fecha between p_desde and p_hasta
    group by r.id_edificio
  ),
  electricas as (
    select f.*,
           least(f.exportada, f.fv + f.eolica) as exp_total,
           case when f.fv + f.eolica > 0 then least(f.exportada, f.fv + f.eolica) * f.fv / (f.fv + f.eolica) else 0 end as exp_fv,
           case when f.fv + f.eolica > 0 then least(f.exportada, f.fv + f.eolica) * f.eolica / (f.fv + f.eolica) else 0 end as exp_eolica
    from fuentes f
  ),
  totales_tipo as (
    select id_edificio, 'ELECTRICIDAD'::text as tipo, red + fv + eolica - exp_total as total from electricas
    union all
    select id_edificio, 'GAS', gas from fuentes
    union all
    select id_edificio, 'CALOR_RENOVABLE', solar_termica + geotermia + biomasa from fuentes
  ),
  medido as (
    select u.id_edificio, u.tipo_energia::text as tipo, u.id_uso_energia as uso,
           case when (select si from por_cuadro) then u.id_cuadro end as cuadro, sum(u.valor) as valor
    from public.resumenes_diarios_usos u
    where u.id_edificio in (select id from edif) and u.fecha between p_desde and p_hasta
    group by 1, 2, 3, 4
  ),
  resto as (
    select t.id_edificio, t.tipo, t.total,
           coalesce((select sum(m.valor) from medido m where m.id_edificio = t.id_edificio and m.tipo = t.tipo), 0) as medido,
           greatest(t.total - coalesce((select sum(m.valor) from medido m
                                        where m.id_edificio = t.id_edificio and m.tipo = t.tipo), 0), 0) as sin_medir
    from totales_tipo t
  ),
  repartido as (
    select r.id_edificio, r.tipo, ru.id_uso_energia as uso, r.sin_medir * ru.porcentaje / 100.0 as valor
    from resto r
    join public.repartos_uso_edificio ru on ru.id_edificio = r.id_edificio and ru.tipo_energia = r.tipo
    union all
    select r.id_edificio, r.tipo, (select id from public.usos_energia where codigo = 'OTROS_SIN_DESGLOSE'),
           r.sin_medir * (100 - coalesce((select sum(ru.porcentaje) from public.repartos_uso_edificio ru
                                          where ru.id_edificio = r.id_edificio and ru.tipo_energia = r.tipo), 0)) / 100.0
    from resto r
  ),
  flujos_uso as (
    select tipo, uso, cuadro, sum(valor) as valor, false as estimado from medido group by tipo, uso, cuadro
    union all
    select tipo, uso, null::uuid, sum(valor), true from repartido group by tipo, uso
  ),
  uso_info as (
    select h.id, h.codigo, h.nombre, h.orden, coalesce(p.codigo, h.codigo) as grupo, coalesce(p.orden, h.orden) as orden_grupo
    from public.usos_energia h
    left join public.usos_energia p on p.id = h.id_padre
  ),
  -- Detalle (última columna): en HVAC, el uso final; en Alumbrado y Otros usos, uso y cuadro
  flujos as (
    select f.tipo, ui.grupo, f.valor, f.estimado,
           case when f.estimado and ui.codigo = 'OTROS_SIN_DESGLOSE' then 'OTROS_NO_MEDIDO'
                when ui.grupo = 'HVAC' or f.cuadro is null then ui.codigo
                else ui.codigo || ':' || f.cuadro::text end as detalle,
           case when f.estimado and ui.codigo = 'OTROS_SIN_DESGLOSE' then 'Otros usos · no medido'
                when ui.grupo = 'HVAC' or f.cuadro is null then ui.nombre
                else ui.nombre || ' · ' || coalesce(public.ubicacion_cuadro(f.cuadro), '?') end as nombre_detalle,
           ui.orden_grupo * 100000 + ui.orden * 1000
             + case when f.estimado then 998 when f.cuadro is null then 999
                    else coalesce((select p.nivel + 50 from public.cuadros_electricos c
                                   left join public.recintos rc on rc.id = c.id_recinto
                                   join public.plantas p on p.id = coalesce(c.id_planta, rc.id_planta)
                                   where c.id = f.cuadro) * 10
                                  + (select case when c.id_recinto is null then 0 else 1 end
                                     from public.cuadros_electricos c where c.id = f.cuadro), 900) end as orden_detalle
    from flujos_uso f join uso_info ui on ui.id = f.uso
  ),
  enlaces_brutos as (
    select 'RED'::text as origen, 'ELECTRICIDAD'::text as destino, sum(red) as valor, false as estimado from electricas
    union all
    select 'FOTOVOLTAICA', 'ELECTRICIDAD', sum(fv - exp_fv), false from electricas
    union all
    select 'FOTOVOLTAICA', 'EXPORTADA', sum(exp_fv), false from electricas
    union all
    select 'EOLICA', 'ELECTRICIDAD', sum(eolica - exp_eolica), false from electricas
    union all
    select 'EOLICA', 'EXPORTADA', sum(exp_eolica), false from electricas
    union all
    select 'SOLAR_TERMICA', 'CALOR_RENOVABLE', sum(solar_termica), false from fuentes
    union all
    select 'GEOTERMIA', 'CALOR_RENOVABLE', sum(geotermia), false from fuentes
    union all
    select 'BIOMASA', 'CALOR_RENOVABLE', sum(biomasa), false from fuentes
    union all
    select f.tipo, f.grupo, f.valor, f.estimado from flujos f
    union all
    select f.grupo, f.detalle, f.valor, f.estimado from flujos f where f.detalle <> f.grupo
  ),
  enlaces as (
    select origen, destino,
           round(sum(valor)::numeric, 3) as valor,
           round(coalesce(sum(valor) filter (where estimado), 0)::numeric, 3) as estimado
    from enlaces_brutos
    group by origen, destino
    having round(sum(valor)::numeric, 3) > 0
  ),
  nombres(codigo, nombre, nivel, orden) as (
    select 'RED', 'Red eléctrica', 0, 1 union all
    select 'FOTOVOLTAICA', 'Solar fotovoltaica', 0, 2 union all
    select 'EOLICA', 'Eólica', 0, 3 union all
    select 'GAS', 'Gas natural', 0, 4 union all
    select 'SOLAR_TERMICA', 'Solar térmica', 0, 5 union all
    select 'GEOTERMIA', 'Geotermia', 0, 6 union all
    select 'BIOMASA', 'Biomasa', 0, 7 union all
    select 'ELECTRICIDAD', 'Electricidad consumida', 1, 1 union all
    select 'EXPORTADA', 'Exportada a la red', 1, 9 union all
    select 'CALOR_RENOVABLE', 'Calor renovable', 1, 3 union all
    select codigo, nombre, 2, orden from public.usos_energia where id_padre is null union all
    select distinct on (detalle) detalle, nombre_detalle, 3, orden_detalle from flujos where detalle <> grupo
  )
  select pg_catalog.jsonb_build_object(
    'periodo', pg_catalog.jsonb_build_object('desde', p_desde, 'hasta', p_hasta),
    'unidad', 'kWh',
    'nodos', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', n.codigo, 'nombre', n.nombre, 'nivel', n.nivel)
                                  order by n.nivel, n.orden, n.nombre)
      from nombres n
      where n.codigo in (select origen from enlaces union select destino from enlaces)), '[]'::jsonb),
    'enlaces', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'origen', origen, 'destino', destino, 'valor', valor, 'estimado', estimado)
             order by origen, destino)
      from enlaces), '[]'::jsonb),
    'totales', (select pg_catalog.jsonb_build_object(
        'red_kwh', coalesce(sum(red), 0),
        'fotovoltaica_kwh', coalesce(sum(fv), 0),
        'eolica_kwh', coalesce(sum(eolica), 0),
        'exportada_kwh', coalesce(sum(exp_total), 0),
        'gas_kwh', coalesce(sum(gas), 0),
        'calor_renovable_kwh', coalesce(sum(solar_termica + geotermia + biomasa), 0),
        'energia_consumida_kwh', coalesce(sum(red + fv + eolica - exp_total + gas + solar_termica + geotermia + biomasa), 0))
      from electricas),
    'avisos', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id_edificio', id_edificio, 'tipo', tipo,
               'mensaje', 'Los submedidores suman más que el consumo total: revise la asignación de usos'))
      from resto where medido > total * 1.02 and total > 0), '[]'::jsonb)
  );
$$;

-- ---------------------------------------------------------
-- 7. Auditoría (versión de la 012): si el edificio de la fila ya no
--    existe (borrado de un edificio de demostración), se registra sin él
-- ---------------------------------------------------------
create or replace function public.auditar_cambio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ant jsonb;
  v_nue jsonb;
  v_fila jsonb;
  v_accion text;
  v_auth uuid;
  v_usuario uuid;
  v_id text;
  v_edificio uuid;
  k text;
begin
  if tg_op = 'INSERT' then
    v_nue := pg_catalog.to_jsonb(new);
    v_fila := v_nue;
    v_accion := 'ALTA';
  elsif tg_op = 'DELETE' then
    v_ant := pg_catalog.to_jsonb(old);
    v_fila := v_ant;
    v_accion := 'ELIMINACION';
  else
    v_ant := pg_catalog.to_jsonb(old);
    v_nue := pg_catalog.to_jsonb(new);
    v_fila := v_nue;

    -- Guardar solo los campos modificados (sin updated_at).
    for k in select pg_catalog.jsonb_object_keys(v_nue) loop
      if k = 'updated_at' or (v_ant->k) is not distinct from (v_nue->k) then
        v_ant := v_ant - k;
        v_nue := v_nue - k;
      end if;
    end loop;

    if v_nue = '{}'::jsonb then
      return null;
    end if;

    if (v_nue->>'activo' = 'false') or (v_nue->>'activa' = 'false')
       or (v_nue->>'estado' = 'BAJA') then
      v_accion := 'BAJA';
    else
      v_accion := 'MODIFICACION';
    end if;
  end if;

  v_id := coalesce(
    v_fila->>'id',
    v_fila->>'id_suministro',
    concat_ws('|',
      v_fila->>'id_regla_alarma', v_fila->>'id_recinto', v_fila->>'id_usuario',
      v_fila->>'id_rol', v_fila->>'id_permiso')
  );

  begin
    v_auth := auth.uid();
  exception when others then
    v_auth := null;
  end;

  if v_auth is not null then
    select u.id into v_usuario from public.usuarios u where u.auth_user_id = v_auth;
  end if;

  -- Al borrar un edificio (solo los de demostración, demo_limpiar.sql) la auditoría queda sin edificio
  v_edificio := public.edificio_de_fila_auditada(tg_table_name::text, v_fila);
  if v_edificio is not null and not exists (select 1 from public.edificios where id = v_edificio) then
    v_edificio := null;
  end if;

  insert into public.auditoria (
    id_usuario, auth_user_id, rol_bd, id_edificio, tabla, id_registro,
    accion, datos_anteriores, datos_nuevos
  )
  values (
    v_usuario, v_auth, pg_catalog.current_setting('role', true),
    v_edificio,
    tg_table_name, coalesce(nullif(v_id, ''), '?'),
    v_accion, v_ant, v_nue
  );

  return null;
end;
$$;

-- ---------------------------------------------------------
-- 8. Permisos
-- ---------------------------------------------------------
revoke all on function public.auditar_cambio() from public, anon, authenticated;
revoke all on function public.validar_cuadro_electrico() from public, anon;
revoke all on function public.ubicacion_cuadro(uuid) from public, anon;
grant execute on function public.ubicacion_cuadro(uuid) to authenticated, service_role;
revoke all on function private.motor_sensores_edificio(uuid) from public, anon, authenticated;
revoke all on function private.motor_tras_configuracion() from public, anon, authenticated;
revoke all on function public.motor_calcular(uuid, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.motor_calcular(uuid, timestamptz, timestamptz) to service_role;
revoke all on function public.sustituir_sensor(uuid, jsonb, uuid) from public, anon;
grant execute on function public.sustituir_sensor(uuid, jsonb, uuid) to authenticated, service_role;
revoke all on function public.sankey_energia(text, uuid, date, date) from public, anon;
grant execute on function public.sankey_energia(text, uuid, date, date) to authenticated, service_role;

commit;
