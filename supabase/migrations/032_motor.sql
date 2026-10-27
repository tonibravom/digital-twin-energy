-- =========================================================
-- 032 · Motor de cálculo (Fase 5): lecturas → magnitudes → resúmenes diarios
-- Decisión D40 (27/10/2026).
--
--   lecturas (brutas, por sensor)
--      │  1. serie de 15 minutos por sensor según su tratamiento
--      │     (DELTA/CONTAJE: consumo entre lecturas repartido en el tiempo;
--      │      PROMEDIO, MAXIMO, MINIMO, SUMA, DIRECTO: agregado del intervalo)
--      │  2. conversión a la unidad de la magnitud (Wh→kWh, m³ de gas→kWh…)
--      ▼
--   valores_magnitud (15 min, por magnitud del edificio = suma de sus fuentes)
--      ▼  3. día local del edificio
--   resumenes_diarios (indicadores de los KPIs) y resumenes_diarios_usos (Sankey)
--
-- Cliente, Partner y Plataforma NO tienen motor propio: kpis_ambito y
-- kpis_lista (022) suman los resúmenes diarios de sus edificios.
--
-- Funcionamiento incremental:
--   · Cada inserción en lecturas anota en motor_pendiente, por edificio,
--     el instante más antiguo recibido (también datos atrasados e
--     importaciones). El motor recalcula desde ahí hasta ahora.
--   · Cambiar la configuración (fuentes de una magnitud, uso de un
--     submedidor) anota el recálculo de todo el histórico afectado.
--   · pg_cron ejecuta motor_ejecutar() cada 15 minutos (minuto 5, 20, 35
--     y 50, después de la recogida de datos), por tramos de 7 días y con
--     un tiempo máximo, confirmando cada tramo.
--
-- Reglas del cálculo:
--   · Intervalos de 15 min alineados (UTC); un valor con fecha_hora = 10:15
--     es el intervalo que empieza a las 10:15 (convención de 023).
--   · DELTA: la diferencia entre dos lecturas consecutivas se reparte
--     proporcionalmente al tiempo entre los intervalos que abarcan.
--     Huecos de más de 1 hora → calidad ESTIMADA. Huecos de más de 7 días
--     no se reparten. Si el contador baja (reinicio o cambio de equipo
--     sin sustituir_sensor) ese tramo se descarta.
--   · Un sensor sustituido (sustituir_sensor) aporta sus lecturas
--     antiguas a la misma magnitud (sensores.id_sensor_anterior), sin
--     mezclar los contadores.
--   · El motor no sobrescribe resúmenes importados (origen IMPORTACION_*).
--   · completo = el día tiene todos sus intervalos (96; 92 o 100 en los
--     cambios de hora) y ninguno es estimado.
-- =========================================================
begin;

-- ---------------------------------------------------------
-- 1. Parámetros y utilidades
-- ---------------------------------------------------------
insert into public.parametros_saas (codigo, nombre, valor_numerico, unidad, descripcion, fecha_inicio)
select 'FACTOR_CONVERSION_GAS', 'Conversión de m³ de gas natural a kWh', 11.70, 'kWh/m3',
       'Poder calorífico superior medio del gas natural. Se usa cuando un contador de gas mide en m³. '
       || 'Para cambiarlo: cierre el vigente (fecha_fin) e inserte uno nuevo, y pida un recálculo del periodo.',
       date '2000-01-01'
where not exists (select 1 from public.parametros_saas where codigo = 'FACTOR_CONVERSION_GAS' and activo);

create or replace function private.parametro_vigente(p_codigo text, p_fecha date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select ps.valor_numerico
  from public.parametros_saas ps
  where ps.codigo = p_codigo and ps.activo
    and ps.fecha_inicio <= p_fecha
    and (ps.fecha_fin is null or ps.fecha_fin > p_fecha)
  order by ps.fecha_inicio desc
  limit 1;
$$;

-- Factor para pasar de la unidad del sensor a la de la magnitud. null = incompatibles.
create or replace function private.motor_factor_unidad(
  p_unidad_sensor text, p_unidad_magnitud text, p_tipo_energia text, p_fecha date)
returns double precision
language plpgsql
stable
set search_path = ''
as $$
declare
  s text := pg_catalog.lower(pg_catalog.replace(pg_catalog.btrim(coalesce(p_unidad_sensor, '')), '³', '3'));
  m text := pg_catalog.lower(pg_catalog.replace(pg_catalog.btrim(coalesce(p_unidad_magnitud, '')), '³', '3'));
  a_kwh double precision;
begin
  if s = m then
    return 1;
  end if;
  -- Energía → kWh
  a_kwh := case s when 'wh' then 0.001 when 'kwh' then 1 when 'mwh' then 1000 when 'gwh' then 1000000
                  when 'mj' then 1 / 3.6 when 'gj' then 1000 / 3.6 when 'th' then 1.163 when 'termias' then 1.163 end;
  if m = 'kwh' and a_kwh is not null then
    return a_kwh;
  end if;
  if m = 'mwh' and a_kwh is not null then
    return a_kwh / 1000;
  end if;
  -- Gas medido en volumen → energía
  if m = 'kwh' and s in ('m3', 'nm3') and p_tipo_energia = 'GAS' then
    return private.parametro_vigente('FACTOR_CONVERSION_GAS', p_fecha);
  end if;
  -- Volumen (agua)
  if m = 'm3' then
    return case s when 'l' then 0.001 when 'litros' then 0.001 when 'hl' then 0.1 end;
  end if;
  -- Potencia → kW
  if m = 'kw' then
    return case s when 'w' then 0.001 when 'mw' then 1000 end;
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------
-- 2. Sustitución de sensores: se guarda el sensor anterior para
--    que el histórico siga contando en sus magnitudes.
-- ---------------------------------------------------------
alter table public.sensores
  add column if not exists id_sensor_anterior uuid references public.sensores(id) on delete restrict;

comment on column public.sensores.id_sensor_anterior is
  'Sensor al que sustituye (sustituir_sensor). El motor suma las lecturas de ambos en las magnitudes, sin mezclar sus contadores.';

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

  -- Sufijo único aunque se sustituya varias veces el mismo día
  v_sufijo := '#' || pg_catalog.to_char(current_date, 'YYYYMMDD') || '-' || pg_catalog.left(v_old.id::text, 8);

  if auth.uid() is not null and not private.usuario_puede_edificio(
       public.obtener_edificio_recinto(v_old.id_recinto), 'MODIFICAR_SENSOR') then
    raise exception 'Sin permiso para sustituir sensores en este edificio' using errcode = '42501';
  end if;

  -- 1) el antiguo se renombra y se desactiva
  update public.sensores
     set codigo = pg_catalog.left(v_old.codigo, 130) || v_sufijo,
         activo = false,
         fecha_baja = current_date
   where id = v_old.id;

  -- 2) el nuevo copia la configuración (y empieza PENDIENTE de prueba)
  insert into public.sensores (
    id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento,
    id_tipo_energia, id_flujo_energia, id_uso_energia, codigo, nombre, magnitud_origen,
    unidad, unidad_origen, escala, desplazamiento, valor_minimo, valor_maximo,
    politica_vacios, direccion, descripcion, id_sensor_anterior)
  values (
    coalesce(p_id_dispositivo_nuevo, v_old.id_dispositivo),
    case when p_id_dispositivo_nuevo is null then v_old.id_conexion end,
    v_old.id_recinto, v_old.id_familia, v_old.id_naturaleza, v_old.id_tratamiento,
    v_old.id_tipo_energia, v_old.id_flujo_energia, v_old.id_uso_energia, v_old.codigo, v_old.nombre,
    v_old.magnitud_origen, v_old.unidad, v_old.unidad_origen, v_old.escala, v_old.desplazamiento,
    v_old.valor_minimo, v_old.valor_maximo, v_old.politica_vacios,
    coalesce(p_direccion, v_old.direccion), v_old.descripcion, v_old.id)
  returning id into v_nuevo;

  -- 3) la configuración ligada pasa al sensor nuevo
  update public.magnitudes_fuentes set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.ubicaciones_3d set id_sensor = v_nuevo where id_sensor = v_old.id;
  update public.reglas_alarma set id_sensor = v_nuevo where id_sensor = v_old.id and activa;
  update public.sensores_recintos_ambito set id_sensor = v_nuevo where id_sensor = v_old.id and activo;

  return v_nuevo;
end;
$$;

-- Fuentes que restan (p. ej. consumo de un recinto = general − otro recinto)
alter table public.magnitudes_fuentes drop constraint if exists magnitudes_fuentes_papel_ck;
alter table public.magnitudes_fuentes add constraint magnitudes_fuentes_papel_ck
  check (papel in ('FUENTE', 'RESTA')) not valid;
comment on column public.magnitudes_fuentes.papel is
  'FUENTE suma su valor a la magnitud; RESTA lo descuenta.';

-- ---------------------------------------------------------
-- 3. Cola de trabajo del motor
-- ---------------------------------------------------------
create sequence if not exists public.motor_pendiente_marca_seq;

create table if not exists public.motor_pendiente (
  id_edificio uuid primary key references public.edificios(id) on delete cascade,
  desde timestamptz not null,
  marca bigint not null default nextval('public.motor_pendiente_marca_seq'),
  motivo varchar(40) not null default 'LECTURAS',
  ultimo_error text,
  intentos integer not null default 0,
  actualizado timestamptz not null default now()
);

comment on table public.motor_pendiente is
  'Por edificio, desde qué instante debe recalcular el motor. La rellenan las inserciones de lecturas y los cambios de configuración; el motor la vacía.';

alter table public.motor_pendiente enable row level security;
revoke all on public.motor_pendiente from anon, authenticated;
revoke all on sequence public.motor_pendiente_marca_seq from public, anon, authenticated;

alter table public.recalculos_pendientes add column if not exists error text;

-- Anota (o adelanta) el recálculo de un edificio
create or replace function private.motor_marcar(p_id_edificio uuid, p_desde timestamptz, p_motivo text default 'LECTURAS')
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.motor_pendiente as mp (id_edificio, desde, motivo)
  select p_id_edificio, p_desde, p_motivo
  where p_id_edificio is not null and p_desde is not null
  on conflict (id_edificio) do update
    set desde = least(mp.desde, excluded.desde),
        marca = nextval('public.motor_pendiente_marca_seq'),
        motivo = case when excluded.desde < mp.desde then excluded.motivo else mp.motivo end,
        actualizado = now();
$$;

-- Sensores (y sus sustituidos) que alimentan al motor en un edificio
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
    where s.id_uso_energia is not null and s.activo
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

-- Primera lectura de un conjunto de sensores (para recalcular todo su histórico)
create or replace function private.motor_primera_lectura(p_sensores uuid[])
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select min(x.f) from pg_catalog.unnest(p_sensores) s(id)
  cross join lateral (select l.fecha_hora as f from public.lecturas l
                      where l.id_sensor = s.id order by l.fecha_hora limit 1) x;
$$;

-- Lecturas nuevas (también atrasadas o importadas) → recálculo del edificio
create or replace function private.motor_tras_lecturas()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.motor_marcar(x.id_edificio, x.desde)
  from (
    select public.obtener_edificio_recinto(s.id_recinto) as id_edificio, min(n.desde) as desde
    from (select id_sensor, min(fecha_hora) as desde from nuevas group by id_sensor) n
    join public.sensores s on s.id = n.id_sensor
    group by 1
  ) x;
  return null;
end;
$$;

drop trigger if exists trg_lecturas_motor on public.lecturas;
create trigger trg_lecturas_motor
after insert on public.lecturas
referencing new table as nuevas
for each statement execute function private.motor_tras_lecturas();

-- Cambios de configuración → recálculo de todo el histórico afectado
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
  elsif tg_table_name = 'magnitudes_edificio' then
    v_edificio := coalesce(new.id_edificio, old.id_edificio);
  else -- sensores: cambio de uso del submedidor
    v_edificio := public.obtener_edificio_recinto(coalesce(new.id_recinto, old.id_recinto));
  end if;

  select pg_catalog.array_agg(id) into v_sensores from private.motor_sensores_edificio(v_edificio) id;
  if tg_table_name = 'sensores' then
    v_sensores := coalesce(v_sensores, '{}') || new.id;
  elsif tg_table_name = 'magnitudes_fuentes' and coalesce(new.id_sensor, old.id_sensor) is not null then
    -- también el sensor que deja de ser fuente: hay que quitar su aporte
    v_sensores := coalesce(v_sensores, '{}') || coalesce(old.id_sensor, new.id_sensor);
  end if;
  perform private.motor_marcar(v_edificio, private.motor_primera_lectura(v_sensores), 'CONFIGURACION');
  return null;
end;
$$;

drop trigger if exists trg_magnitudes_fuentes_motor on public.magnitudes_fuentes;
create trigger trg_magnitudes_fuentes_motor
after insert or update or delete on public.magnitudes_fuentes
for each row execute function private.motor_tras_configuracion();

drop trigger if exists trg_magnitudes_edificio_motor on public.magnitudes_edificio;
create trigger trg_magnitudes_edificio_motor
after update of activa, id_magnitud on public.magnitudes_edificio
for each row execute function private.motor_tras_configuracion();

drop trigger if exists trg_sensores_uso_motor on public.sensores;
create trigger trg_sensores_uso_motor
after update of id_uso_energia on public.sensores
for each row when (old.id_uso_energia is distinct from new.id_uso_energia)
execute function private.motor_tras_configuracion();

-- ---------------------------------------------------------
-- 4. Serie de 15 minutos de un sensor (en su unidad)
-- ---------------------------------------------------------
create or replace function private.motor_serie_sensor(p_id_sensor uuid, p_desde timestamptz, p_hasta timestamptz)
returns table (instante timestamptz, valor double precision, calidad smallint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tratamiento text;
  v_origen constant timestamptz := timestamptz '2000-01-01 00:00:00+00';
begin
  select t.codigo into v_tratamiento
  from public.sensores s join public.tratamientos_sensor t on t.id = s.id_tratamiento
  where s.id = p_id_sensor;

  if v_tratamiento in ('DELTA', 'CONTAJE') then
    return query
    with lect as (
      select l.fecha_hora as t, l.valor as v, l.calidad as q from public.lecturas l
      where l.id_sensor = p_id_sensor and l.fecha_hora >= p_desde and l.fecha_hora <= p_hasta
      union all
      (select l.fecha_hora, l.valor, l.calidad from public.lecturas l
       where l.id_sensor = p_id_sensor and l.fecha_hora < p_desde and l.fecha_hora >= p_desde - interval '7 days'
       order by l.fecha_hora desc limit 1)
      union all
      (select l.fecha_hora, l.valor, l.calidad from public.lecturas l
       where l.id_sensor = p_id_sensor and l.fecha_hora > p_hasta and l.fecha_hora <= p_hasta + interval '7 days'
       order by l.fecha_hora limit 1)
    ),
    pares as (
      select t as t1, pg_catalog.lead(t) over w as t2, v as v1, pg_catalog.lead(v) over w as v2,
             q as q1, pg_catalog.lead(q) over w as q2
      from lect window w as (order by t)
    ),
    validos as (
      select p.*, p.v2 - p.v1 as d,
             extract(epoch from (p.t2 - p.t1)) as dur,
             greatest(p.q1, p.q2, case when p.t2 - p.t1 > interval '1 hour' then 1 else 0 end)::smallint as q
      from pares p
      where p.t2 is not null and p.v2 >= p.v1 and p.t2 - p.t1 <= interval '7 days'
    ),
    trozos as (
      select b as inst,
             x.d * extract(epoch from (least(b + interval '15 minutes', x.t2) - greatest(b, x.t1))) / x.dur as val,
             x.q
      from validos x
      cross join lateral pg_catalog.generate_series(pg_catalog.date_bin('15 minutes', x.t1, v_origen),
                                                    x.t2 - interval '1 microsecond', interval '15 minutes') b
    )
    select tr.inst, sum(tr.val), max(tr.q)::smallint
    from trozos tr
    where tr.inst >= p_desde and tr.inst < p_hasta
    group by tr.inst;
  else
    return query
    select pg_catalog.date_bin('15 minutes', l.fecha_hora, v_origen),
           case v_tratamiento
             when 'MAXIMO' then max(l.valor)
             when 'MINIMO' then min(l.valor)
             when 'SUMA' then sum(l.valor)
             else avg(l.valor) end,
           max(l.calidad)::smallint
    from public.lecturas l
    where l.id_sensor = p_id_sensor and l.fecha_hora >= p_desde and l.fecha_hora < p_hasta
    group by 1;
  end if;
end;
$$;

-- Serie de una fuente: el sensor y los que sustituyó, cada uno con su contador
create or replace function private.motor_serie_fuente(p_id_sensor uuid, p_desde timestamptz, p_hasta timestamptz)
returns table (instante timestamptz, valor double precision, calidad smallint)
language sql
stable
security definer
set search_path = ''
as $$
  with recursive cadena(id) as (
    select p_id_sensor
    union
    select s.id_sensor_anterior from public.sensores s join cadena c on c.id = s.id
    where s.id_sensor_anterior is not null
  )
  select x.instante, sum(x.valor), max(x.calidad)::smallint
  from cadena c
  cross join lateral private.motor_serie_sensor(c.id, p_desde, p_hasta) x
  group by x.instante;
$$;

-- ---------------------------------------------------------
-- 5. Cálculo de un edificio en un periodo
-- ---------------------------------------------------------
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
  r record;
begin
  select e.zona_horaria into v_zona from public.edificios e where e.id = p_id_edificio;
  if v_zona is null then
    raise exception 'Edificio inexistente';
  end if;
  if p_desde is null or p_desde >= v_hasta then
    return pg_catalog.jsonb_build_object('id_edificio', p_id_edificio, 'valores', 0, 'resumenes', 0);
  end if;

  -- Desde el intervalo que contiene la última lectura anterior de cada contador:
  -- el consumo entre esa lectura y la siguiente se reparte también hacia atrás.
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

  -- Magnitudes del edificio y sus fuentes
  if pg_catalog.to_regclass('pg_temp._motor_mag') is null then
    create temporary table _motor_mag (id uuid primary key, unidad text, nivel integer) on commit drop;
    create temporary table _motor_val (id_me uuid, instante timestamptz, valor double precision, calidad smallint) on commit drop;
  else
    truncate _motor_mag;
    truncate _motor_val;
  end if;

  insert into _motor_mag (id, unidad, nivel)
  select me.id, m.unidad, null
  from public.magnitudes_edificio me
  join public.magnitudes m on m.id = me.id_magnitud
  where me.id_edificio = p_id_edificio and me.activa
    and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id);

  -- Por niveles: primero las que solo dependen de sensores
  loop
    update _motor_mag mm set nivel = v_nivel
    where mm.nivel is null
      and not exists (select 1 from public.magnitudes_fuentes mf
                      left join _motor_mag o on o.id = mf.id_magnitud_origen
                      where mf.id_magnitud_edificio = mm.id and mf.id_magnitud_origen is not null
                        and (o.id is null or o.nivel is null));
    get diagnostics v_hechas = row_count;
    exit when v_hechas = 0;

    -- Fuentes sensor
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

    -- Fuentes magnitud (ya calculadas en niveles anteriores, en _motor_val o guardadas)
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

  -- Guardar (sustituye lo calculado antes en el periodo)
  delete from public.valores_magnitud v
  where v.id_magnitud_edificio in (select me.id from public.magnitudes_edificio me where me.id_edificio = p_id_edificio)
    and v.fecha_hora >= v_desde and v.fecha_hora < v_hasta;

  insert into public.valores_magnitud (id_magnitud_edificio, fecha_hora, valor, calidad, version_motor)
  select id_me, instante, sum(valor), max(calidad), '1.0'
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
  on conflict (id_edificio, fecha, indicador) do nothing;  -- no pisa resúmenes importados
  get diagnostics v_resumenes = row_count;

  -- -------- Consumo medido por usos (submedidores) para el Sankey --------
  delete from public.resumenes_diarios_usos ru
  where ru.id_edificio = p_id_edificio and ru.fecha between v_dia_desde and v_dia_hasta;

  insert into public.resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, valor)
  select p_id_edificio, (x.instante at time zone v_zona)::date, s.id_uso_energia,
         case te.codigo when 'GAS' then 'GAS' when 'TERMICA' then 'CALOR_RENOVABLE' else 'ELECTRICIDAD' end,
         sum(x.valor * private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, (x.instante at time zone v_zona)::date))
  from public.sensores s
  join public.tipos_energia te on te.id = s.id_tipo_energia and te.codigo in ('ELECTRICIDAD', 'GAS', 'TERMICA')
  cross join lateral private.motor_serie_fuente(s.id, v_ini_dias, v_fin_dias) x
  where s.activo and s.id_uso_energia is not null
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
    and private.motor_factor_unidad(s.unidad, 'kWh', te.codigo, v_dia_desde) is not null
  group by 2, 3, 4
  having sum(x.valor) is not null;
  get diagnostics v_usos = row_count;

  return pg_catalog.jsonb_build_object(
    'id_edificio', p_id_edificio, 'desde', v_desde, 'hasta', v_hasta,
    'magnitudes', (select count(*) from _motor_mag where nivel is not null),
    'valores', v_valores, 'resumenes', v_resumenes, 'usos', v_usos,
    'avisos', pg_catalog.to_jsonb(v_avisos));
end;
$$;

-- ---------------------------------------------------------
-- 6. Siguiente trabajo pendiente (un tramo de hasta 7 días)
-- ---------------------------------------------------------
create or replace function public.motor_procesar_siguiente(p_excluir uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tramo constant interval := interval '7 days';
  v_pend public.motor_pendiente%rowtype;
  v_hasta timestamptz;
  v_res jsonb;
begin
  -- Los recálculos pedidos expresamente pasan a la cola única
  perform private.motor_marcar(rp.id_edificio, rp.desde, 'RECALCULO')
  from public.recalculos_pendientes rp where rp.estado = 'PENDIENTE';
  update public.recalculos_pendientes
     set estado = 'HECHO', procesado_at = pg_catalog.now()
   where estado in ('PENDIENTE', 'EN_CURSO');

  select * into v_pend from public.motor_pendiente mp
  where not (mp.id_edificio = any (coalesce(p_excluir, '{}')))
  order by mp.desde
  limit 1;
  if not found then
    return null;
  end if;

  -- Edificio sin nada que calcular (sin fuentes ni submedidores): sale de la cola
  if not exists (select 1 from private.motor_sensores_edificio(v_pend.id_edificio)) then
    delete from public.motor_pendiente where id_edificio = v_pend.id_edificio and marca = v_pend.marca;
    return pg_catalog.jsonb_build_object('id_edificio', v_pend.id_edificio, 'sin_configuracion', true, 'terminado', true);
  end if;

  v_hasta := least(v_pend.desde + v_tramo, pg_catalog.now());
  begin
    v_res := public.motor_calcular(v_pend.id_edificio, v_pend.desde, v_hasta);
  exception when others then
    update public.motor_pendiente
       set ultimo_error = pg_catalog.left(sqlerrm, 500), intentos = intentos + 1
     where id_edificio = v_pend.id_edificio;
    return pg_catalog.jsonb_build_object('id_edificio', v_pend.id_edificio, 'error', sqlerrm);
  end;

  -- Si no ha llegado nada nuevo mientras tanto: se avanza o se termina
  if v_hasta >= pg_catalog.now() - interval '1 second' then
    delete from public.motor_pendiente where id_edificio = v_pend.id_edificio and marca = v_pend.marca;
  else
    update public.motor_pendiente
       set desde = v_hasta, ultimo_error = null, intentos = 0
     where id_edificio = v_pend.id_edificio and marca = v_pend.marca;
  end if;

  return v_res || pg_catalog.jsonb_build_object('terminado', v_hasta >= pg_catalog.now() - interval '1 second');
end;
$$;

-- ---------------------------------------------------------
-- 7. Ejecución periódica (pg_cron): confirma cada tramo y para a los
--    p_segundos. Con un bloqueo para que no se solapen dos ejecuciones.
-- ---------------------------------------------------------
create or replace procedure public.motor_ejecutar(p_segundos integer default 240)
language plpgsql
as $$
declare
  v_fin timestamptz := pg_catalog.clock_timestamp() + pg_catalog.make_interval(secs => p_segundos);
  v_hechos uuid[] := '{}';
  v_res jsonb;
begin
  -- (sin "set search_path": un procedimiento con commit no lo admite; todo va cualificado)
  if not pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('motor_ejecutar')) then
    raise notice 'El motor ya se está ejecutando';
    return;
  end if;
  while pg_catalog.clock_timestamp() < v_fin loop
    v_res := public.motor_procesar_siguiente(v_hechos);
    exit when v_res is null;
    -- Un edificio terminado (o con error) no se repite en esta ejecución
    if coalesce((v_res->>'terminado')::boolean, true) then
      v_hechos := v_hechos || (v_res->>'id_edificio')::uuid;
    end if;
    commit;
  end loop;
  perform pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('motor_ejecutar'));
end;
$$;

-- Estado del motor de un edificio (para la interfaz y el soporte)
create or replace function public.estado_motor(p_id_edificio uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'pendiente_desde', mp.desde, 'motivo', mp.motivo, 'ultimo_error', mp.ultimo_error,
    'ultimo_calculo', (select max(v.created_at) from public.valores_magnitud v
                       join public.magnitudes_edificio me on me.id = v.id_magnitud_edificio
                       where me.id_edificio = p_id_edificio
                         and v.fecha_hora > pg_catalog.now() - interval '2 days'),
    'magnitudes_con_fuentes', (select count(*) from public.magnitudes_edificio me
                               where me.id_edificio = p_id_edificio and me.activa
                                 and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id)))
  from (select 1) x
  left join public.motor_pendiente mp on mp.id_edificio = p_id_edificio
  where auth.uid() is null or private.usuario_tiene_acceso_edificio(p_id_edificio);
$$;

-- ---------------------------------------------------------
-- 8. Permisos
-- ---------------------------------------------------------
revoke all on function private.parametro_vigente(text, date) from public, anon, authenticated;
revoke all on function private.motor_factor_unidad(text, text, text, date) from public, anon, authenticated;
revoke all on function private.motor_marcar(uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function private.motor_sensores_edificio(uuid) from public, anon, authenticated;
revoke all on function private.motor_primera_lectura(uuid[]) from public, anon, authenticated;
revoke all on function private.motor_tras_lecturas() from public, anon, authenticated;
revoke all on function private.motor_tras_configuracion() from public, anon, authenticated;
revoke all on function private.motor_serie_sensor(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function private.motor_serie_fuente(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.motor_calcular(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.motor_procesar_siguiente(uuid[]) from public, anon, authenticated;
revoke all on procedure public.motor_ejecutar(integer) from public, anon, authenticated;
revoke all on function public.estado_motor(uuid) from public, anon;
grant execute on function public.motor_calcular(uuid, timestamptz, timestamptz) to service_role;
grant execute on function public.motor_procesar_siguiente(uuid[]) to service_role;
grant execute on function public.estado_motor(uuid) to authenticated, service_role;

-- ---------------------------------------------------------
-- 9. Programación: cada 15 minutos, 5 minutos después de la recogida
-- ---------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron no disponible: ejecute "call public.motor_ejecutar()" cada 15 minutos desde el backend';
    return;
  end if;
  perform cron.unschedule(jobid) from cron.job where jobname = 'motor_15min';
  perform cron.schedule('motor_15min', '5-59/15 * * * *', 'call public.motor_ejecutar()');
end;
$$;

commit;
