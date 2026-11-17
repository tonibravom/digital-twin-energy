-- =========================================================
-- 048 · Pestaña Suministros: ficha, medidor general y consumo mensual
-- Decisión D57 (16/11/2026).
--
--   · Ficha del suministro: comercializadora, distribuidora, nº de
--     contrato o póliza y fecha de alta del contrato (lo demás ya estaba
--     en suministros_electricidad / _gas / _agua).
--   · MEDIDOR GENERAL: cada suministro tiene un dispositivo marcado como
--     medidor general (suministros_dispositivos.medidor_general, uno por
--     suministro). Sus sensores dicen qué miden con el catálogo
--     parametros_medidor (sensores.id_parametro_medidor):
--       - electricidad: OBLIGATORIOS energía activa importada (consumo),
--         potencia activa y factor de potencia (cos φ); opcionales energía
--         exportada y reactiva, potencias reactiva y aparente, tensión e
--         intensidad por fase, intensidad de neutro y frecuencia;
--       - gas: OBLIGATORIO el consumo (m³ o kWh); opcional la presión;
--       - agua: OBLIGATORIO el consumo (m³); opcional el caudal.
--   · BLOQUEO (estado_parametrizacion_edificio): sin un suministro eléctrico
--     activo, o con un suministro eléctrico o de gas sin medidor general con
--     sus parámetros obligatorios, no se cierra la parametrización. En el
--     agua es un aviso.
--   · suministros_edificio(): fichas con el medidor y sus parámetros en
--     vivo (último valor y, en los contadores, lo de hoy).
--   · Las etiquetas 3D de un medidor general muestran solo los parámetros
--     obligatorios (los opcionales, al desplegarla): la distancia mínima
--     entre etiquetas cuenta esas filas (filas_etiqueta_dispositivo).
--   · consumo_mensual_suministro(): consumo de cada mes de este año y del
--     anterior (diferencia de lecturas del contador del medidor general en
--     los cambios de mes, hora del edificio). El gas, en kWh con la
--     conversión del motor; el agua, en m³.
-- =========================================================
begin;

-- 1. Ficha del suministro
alter table public.suministros
  add column if not exists comercializadora varchar(150),
  add column if not exists distribuidora varchar(150),
  add column if not exists numero_contrato varchar(100),
  add column if not exists fecha_alta_contrato date;

comment on column public.suministros.comercializadora is 'Empresa que suministra (factura) la energía o el agua.';
comment on column public.suministros.distribuidora is 'Empresa distribuidora (dueña de la red y del contador de la compañía).';
comment on column public.suministros.numero_contrato is 'Número de contrato o póliza con la comercializadora.';
comment on column public.suministros.fecha_alta_contrato is 'Fecha de alta del contrato vigente.';

-- 2. Catálogo de parámetros del medidor general (de la plataforma)
create table if not exists public.parametros_medidor (
  id smallint generated always as identity primary key,
  codigo varchar(40) not null unique,
  nombre varchar(120) not null,
  tipo_suministro varchar(20) not null,
  familias varchar(30)[] not null,
  unidad varchar(20) not null,
  obligatorio boolean not null default false,
  consumo boolean not null default false,
  orden smallint not null default 0,
  activo boolean not null default true,
  constraint parametros_medidor_tipo_ck check (tipo_suministro in ('ELECTRICIDAD', 'GAS', 'AGUA'))
);
alter table public.parametros_medidor enable row level security;

comment on table public.parametros_medidor is
  'Qué mide cada sensor del medidor general de un suministro (D57). obligatorio = sin él no se cierra la parametrización; consumo = el contador del gráfico mensual.';

drop policy if exists parametros_medidor_select on public.parametros_medidor;
create policy parametros_medidor_select on public.parametros_medidor
for select to authenticated using (true);
revoke all on public.parametros_medidor from anon;
grant select on public.parametros_medidor to authenticated;

create unique index if not exists parametros_medidor_consumo_uq
  on public.parametros_medidor (tipo_suministro) where consumo;

insert into public.parametros_medidor (codigo, nombre, tipo_suministro, familias, unidad, obligatorio, consumo, orden) values
  ('ENERGIA_ACTIVA_IMPORTADA', 'Consumo (energía activa importada)', 'ELECTRICIDAD', '{ENERGIA}', 'kWh', true, true, 1),
  ('POTENCIA_ACTIVA', 'Potencia activa', 'ELECTRICIDAD', '{POTENCIA}', 'kW', true, false, 2),
  ('FACTOR_POTENCIA', 'Factor de potencia (cos φ)', 'ELECTRICIDAD', '{FACTOR_POTENCIA}', '-', true, false, 3),
  ('ENERGIA_ACTIVA_EXPORTADA', 'Energía exportada', 'ELECTRICIDAD', '{ENERGIA}', 'kWh', false, false, 4),
  ('ENERGIA_REACTIVA', 'Energía reactiva', 'ELECTRICIDAD', '{ENERGIA}', 'kvarh', false, false, 5),
  ('POTENCIA_REACTIVA', 'Potencia reactiva', 'ELECTRICIDAD', '{POTENCIA}', 'kvar', false, false, 6),
  ('POTENCIA_APARENTE', 'Potencia aparente', 'ELECTRICIDAD', '{POTENCIA}', 'kVA', false, false, 7),
  ('TENSION_L1', 'Tensión L1', 'ELECTRICIDAD', '{TENSION}', 'V', false, false, 8),
  ('TENSION_L2', 'Tensión L2', 'ELECTRICIDAD', '{TENSION}', 'V', false, false, 9),
  ('TENSION_L3', 'Tensión L3', 'ELECTRICIDAD', '{TENSION}', 'V', false, false, 10),
  ('INTENSIDAD_L1', 'Intensidad L1', 'ELECTRICIDAD', '{INTENSIDAD}', 'A', false, false, 11),
  ('INTENSIDAD_L2', 'Intensidad L2', 'ELECTRICIDAD', '{INTENSIDAD}', 'A', false, false, 12),
  ('INTENSIDAD_L3', 'Intensidad L3', 'ELECTRICIDAD', '{INTENSIDAD}', 'A', false, false, 13),
  ('INTENSIDAD_N', 'Intensidad de neutro', 'ELECTRICIDAD', '{INTENSIDAD}', 'A', false, false, 14),
  ('FRECUENCIA', 'Frecuencia', 'ELECTRICIDAD', '{FRECUENCIA}', 'Hz', false, false, 15),
  ('CONSUMO_GAS', 'Consumo de gas', 'GAS', '{ENERGIA,OTRA}', 'm³', true, true, 1),
  ('PRESION_GAS', 'Presión', 'GAS', '{PRESION}', 'mbar', false, false, 2),
  ('CONSUMO_AGUA', 'Consumo de agua', 'AGUA', '{OTRA,CAUDAL}', 'm³', true, true, 1),
  ('CAUDAL_AGUA', 'Caudal', 'AGUA', '{CAUDAL}', 'm³/h', false, false, 2)
on conflict (codigo) do nothing;

-- 3. Qué mide cada sensor del medidor
alter table public.sensores
  add column if not exists id_parametro_medidor smallint references public.parametros_medidor(id) on delete restrict;
comment on column public.sensores.id_parametro_medidor is
  'Parámetro del medidor general de un suministro que mide este sensor (D57). Un parámetro por dispositivo.';

create unique index if not exists sensores_parametro_medidor_uq
  on public.sensores (id_dispositivo, id_parametro_medidor)
  where activo and id_parametro_medidor is not null;

create or replace function public.validar_parametro_medidor()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_par public.parametros_medidor%rowtype;
  v_familia text;
  v_naturaleza text;
begin
  -- Al sustituir un sensor, el nuevo mide lo mismo que el anterior
  if tg_op = 'INSERT' and new.id_parametro_medidor is null and new.id_sensor_anterior is not null then
    select s.id_parametro_medidor into new.id_parametro_medidor from public.sensores s where s.id = new.id_sensor_anterior;
  end if;
  if new.id_parametro_medidor is null then
    return new;
  end if;

  select * into v_par from public.parametros_medidor where id = new.id_parametro_medidor;
  if new.id_dispositivo is null then
    raise exception 'El parámetro «%» es de un medidor: el sensor tiene que pertenecer a un dispositivo', v_par.nombre
      using errcode = 'check_violation';
  end if;
  select f.codigo into v_familia from public.familias_sensor f where f.id = new.id_familia;
  if not (v_familia = any (v_par.familias)) then
    raise exception 'El parámetro «%» no corresponde a un sensor de la familia %', v_par.nombre, v_familia
      using errcode = 'check_violation';
  end if;
  select n.codigo into v_naturaleza from public.naturalezas_sensor n where n.id = new.id_naturaleza;
  if v_par.consumo and v_naturaleza <> 'ACUMULATIVA' then
    raise exception 'El consumo del medidor tiene que ser un contador (naturaleza ACUMULATIVA)'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sensores_parametro_medidor on public.sensores;
create trigger trg_sensores_parametro_medidor
before insert or update of id_parametro_medidor, id_dispositivo, id_familia, id_naturaleza on public.sensores
for each row execute function public.validar_parametro_medidor();

-- 4. Medidor general de cada suministro
alter table public.suministros_dispositivos
  add column if not exists medidor_general boolean not null default false;
comment on column public.suministros_dispositivos.medidor_general is
  'Dispositivo que mide el suministro completo (D57). Uno por suministro; en electricidad es obligatorio.';
create unique index if not exists suministros_dispositivos_medidor_uq
  on public.suministros_dispositivos (id_suministro) where activo and medidor_general;

-- (que el dispositivo sea del mismo edificio ya lo valida trg_validar_suministro_dispositivo, 017)

-- 5. Parámetros que faltan en el medidor general de un suministro
create or replace function public.parametros_faltan_suministro(p_id_suministro uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.array_agg(pm.nombre::text order by pm.orden), '{}')
  from public.suministros su
  join public.parametros_medidor pm
    on pm.tipo_suministro = case su.tipo when 'AGUA_INCENDIOS' then 'AGUA' else su.tipo end
   and pm.obligatorio and pm.activo
  where su.id = p_id_suministro
    and not exists (
      select 1 from public.suministros_dispositivos sd
      join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
      where sd.id_suministro = su.id and sd.activo and sd.medidor_general
        and s.id_parametro_medidor = pm.id);
$$;

-- 6. Fichas de los suministros del edificio (pestaña Suministros)
create or replace function public.suministros_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with est as (select * from public.sensores_estado_edificio(p_id_edificio))
  select coalesce(pg_catalog.jsonb_agg(f.ficha order by f.orden, f.nombre), '[]'::jsonb)
  from (
    select su.nombre,
           case su.tipo when 'ELECTRICIDAD' then 1 when 'GAS' then 2 when 'AGUA' then 3 else 4 end as orden,
           pg_catalog.jsonb_build_object(
             'id', su.id, 'codigo', su.codigo, 'nombre', su.nombre, 'tipo', su.tipo,
             'tipo_parametros', case su.tipo when 'AGUA_INCENDIOS' then 'AGUA' else su.tipo end,
             'descripcion', su.descripcion, 'fecha_inicio', su.fecha_inicio,
             'comercializadora', su.comercializadora, 'distribuidora', su.distribuidora,
             'numero_contrato', su.numero_contrato, 'fecha_alta_contrato', su.fecha_alta_contrato,
             'detalle', coalesce(
               (select pg_catalog.to_jsonb(x) - 'id_suministro' from public.suministros_electricidad x where x.id_suministro = su.id),
               (select pg_catalog.to_jsonb(x) - 'id_suministro' from public.suministros_gas x where x.id_suministro = su.id),
               (select pg_catalog.to_jsonb(x) - 'id_suministro' from public.suministros_agua x where x.id_suministro = su.id),
               '{}'::jsonb),
             'medidor', (
               select pg_catalog.jsonb_build_object('id', d.id, 'codigo', d.codigo, 'nombre', d.nombre,
                        'fabricante', d.fabricante, 'modelo', d.modelo, 'numero_serie', d.numero_serie)
               from public.suministros_dispositivos sd
               join public.dispositivos d on d.id = sd.id_dispositivo
               where sd.id_suministro = su.id and sd.activo and sd.medidor_general),
             'parametros', coalesce((
               select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                        'codigo', pm.codigo, 'nombre', pm.nombre, 'obligatorio', pm.obligatorio, 'consumo', pm.consumo,
                        'id_sensor', e.id_sensor, 'unidad', coalesce(e.unidad, pm.unidad),
                        'ultimo_valor', e.ultimo_valor, 'ultima_lectura', e.ultima_lectura,
                        'estado_comunicacion', e.estado_comunicacion, 'alarma_activa', e.alarma_activa,
                        'valor_hoy', e.valor_hoy, 'valor_hoy_kwh', e.valor_hoy_kwh, 'valor_comparable', e.valor_comparable)
                      order by pm.orden)
               from public.parametros_medidor pm
               left join lateral (
                 select est.* from public.suministros_dispositivos sd
                 join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo and s.id_parametro_medidor = pm.id
                 join est on est.id_sensor = s.id
                 where sd.id_suministro = su.id and sd.activo and sd.medidor_general
                 limit 1) e on true
               where pm.activo and pm.tipo_suministro = case su.tipo when 'AGUA_INCENDIOS' then 'AGUA' else su.tipo end
                 and (pm.obligatorio or e.id_sensor is not null)), '[]'::jsonb),
             'faltan', pg_catalog.to_jsonb(public.parametros_faltan_suministro(su.id))) as ficha
    from public.suministros su
    where su.id_edificio = p_id_edificio and su.activo and su.tipo <> 'GENERACION'
  ) f;
$$;

-- 7. Consumo mensual del suministro: este año y el anterior
create or replace function public.consumo_mensual_suministro(p_id_suministro uuid)
returns table (anio integer, mes integer, consumo double precision, unidad varchar, consumo_kwh double precision)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_tipo text;
  v_z text;
  v_hoy date;
  v_sensor uuid;
  v_unidad varchar;
  v_energia text;
  v_mes date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_a double precision;
  v_b double precision;
begin
  select su.tipo, e.zona_horaria, (pg_catalog.now() at time zone e.zona_horaria)::date
    into v_tipo, v_z, v_hoy
  from public.suministros su join public.edificios e on e.id = su.id_edificio
  where su.id = p_id_suministro;
  if v_tipo is null then
    return;   -- inexistente o sin acceso (RLS)
  end if;

  -- El contador de consumo del medidor general
  select s.id, s.unidad, te.codigo into v_sensor, v_unidad, v_energia
  from public.suministros_dispositivos sd
  join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
  join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.consumo
  left join public.tipos_energia te on te.id = s.id_tipo_energia
  where sd.id_suministro = p_id_suministro and sd.activo and sd.medidor_general
  limit 1;
  if v_sensor is null then
    return;
  end if;
  v_energia := coalesce(v_energia, case v_tipo when 'AGUA_INCENDIOS' then 'AGUA' else v_tipo end);

  v_mes := (pg_catalog.date_trunc('year', v_hoy) - interval '1 year')::date;
  while v_mes <= v_hoy loop
    -- Última lectura antes del cambio de mes y última del mes (el mes en curso, hasta ahora), en la hora del edificio
    v_ini := v_mes::timestamp at time zone v_z;
    v_fin := least((v_mes + interval '1 month')::timestamp at time zone v_z, pg_catalog.now());
    select l.valor into v_a from public.lecturas l
    where l.id_sensor = v_sensor and l.fecha_hora <= v_ini and l.fecha_hora > v_ini - interval '31 days'
    order by l.fecha_hora desc limit 1;
    select l.valor into v_b from public.lecturas l
    where l.id_sensor = v_sensor and l.fecha_hora <= v_fin and l.fecha_hora > v_ini
    order by l.fecha_hora desc limit 1;

    anio := pg_catalog.date_part('year', v_mes)::integer;
    mes := pg_catalog.date_part('month', v_mes)::integer;
    unidad := v_unidad;
    -- Si el contador se reinicia o se sustituye (resta negativa), el mes queda vacío
    consumo := case when v_b - v_a >= 0 then v_b - v_a end;
    consumo_kwh := case
      when consumo is null or v_energia = 'AGUA' then null
      when pg_catalog.lower(pg_catalog.btrim(v_unidad)) = 'kwh' then consumo
      else consumo * private.factor_kwh_sensor(v_unidad, v_energia, v_mes) end;
    return next;
    v_mes := (v_mes + interval '1 month')::date;
  end loop;
end;
$$;

-- 8. Lista de comprobación: el medidor general es bloqueante (electricidad y gas)
create or replace function public.estado_parametrizacion_edificio(p_id_edificio uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_3d boolean;
  v_sum record;
begin
  if not exists (select 1 from public.edificios where id = p_id_edificio) then
    raise exception 'Edificio inexistente o sin acceso';
  end if;

  select count(*) into v_n from public.plantas where id_edificio = p_id_edificio and activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'PLANTAS', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' plantas');

  select count(*) into v_n from public.recintos r join public.plantas p on p.id = r.id_planta
  where p.id_edificio = p_id_edificio and r.activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'RECINTOS', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' recintos');

  select count(*) into v_n from public.conexiones where id_edificio = p_id_edificio and activo;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'CONEXIONES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' conexiones');

  select count(*) into v_n from public.sensores s
  where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' sensores activos');

  select count(*) into v_n from public.sensores s
  where s.activo and s.direccion = '{}'::jsonb
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES_SIN_DIRECCION', 'bloqueante', false,
    'ok', v_n = 0, 'detalle', v_n || ' sensores sin dirección en el origen (no recibirán datos)');

  select count(*) into v_n from public.sensores s
  where s.activo and s.direccion <> '{}'::jsonb and s.estado_configuracion <> 'PROBADO'
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SENSORES_SIN_PROBAR', 'bloqueante', true,
    'ok', v_n = 0, 'detalle', v_n || ' sensores pendientes de prueba o con error');

  select count(*) into v_n from public.modalidades_edificio where id_edificio = p_id_edificio and activa;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MODALIDAD', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', case when v_n > 0 then 'asignada' else 'sin modalidad BASIC/PRO/PREMIUM' end);

  select count(*) into v_n from public.magnitudes_edificio me
  where me.id_edificio = p_id_edificio and me.activa
    and exists (select 1 from public.magnitudes_fuentes mf where mf.id_magnitud_edificio = me.id);
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MAGNITUDES', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', v_n || ' magnitudes con sensores asignados');

  -- Suministros (D57): sin medidor general de la electricidad no hay seguimiento energético
  select count(*) into v_n from public.suministros
  where id_edificio = p_id_edificio and activo and tipo = 'ELECTRICIDAD';
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'SUMINISTRO_ELECTRICO', 'bloqueante', true,
    'ok', v_n > 0, 'detalle', case when v_n > 0 then v_n || ' suministros eléctricos'
                                   else 'falta el suministro eléctrico del edificio' end);

  for v_sum in
    select su.nombre, su.tipo, public.parametros_faltan_suministro(su.id) as faltan,
           exists (select 1 from public.suministros_dispositivos sd
                   where sd.id_suministro = su.id and sd.activo and sd.medidor_general) as con_medidor
    from public.suministros su
    where su.id_edificio = p_id_edificio and su.activo and su.tipo <> 'GENERACION'
    order by su.tipo, su.nombre
  loop
    v_items := v_items || pg_catalog.jsonb_build_object(
      'codigo', 'MEDIDOR_GENERAL', 'bloqueante', v_sum.tipo in ('ELECTRICIDAD', 'GAS'),
      'ok', v_sum.con_medidor and pg_catalog.cardinality(v_sum.faltan) = 0,
      'detalle', case
        when not v_sum.con_medidor then '«' || v_sum.nombre || '»: falta el medidor general'
        when pg_catalog.cardinality(v_sum.faltan) > 0 then '«' || v_sum.nombre || '»: el medidor general no mide ' || pg_catalog.array_to_string(v_sum.faltan, ', ')
        else '«' || v_sum.nombre || '»: medidor general completo' end);
  end loop;

  select count(*) into v_n from public.calendario_edificio
  where id_edificio = p_id_edificio
    and fecha between pg_catalog.date_trunc('year', current_date)::date
                  and (pg_catalog.date_trunc('year', current_date) + interval '1 year - 1 day')::date;
  v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'CALENDARIO', 'bloqueante', false,
    'ok', v_n > 0, 'detalle', v_n || ' días configurados este año');

  v_3d := exists (select 1 from public.complementos_edificio
                  where id_edificio = p_id_edificio and codigo = '3D' and activa);
  if v_3d then
    select count(*) into v_n from public.modelos_3d
    where id_edificio = p_id_edificio and tipo_modelo = 'EDIFICIO' and activo;
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'MODELO_3D', 'bloqueante', true,
      'ok', v_n > 0, 'detalle', case when v_n > 0 then 'modelo general cargado' else 'falta el modelo 3D general del edificio' end);

    select count(*) into v_n from public.sensores s
    where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio
      and not exists (select 1 from public.ubicaciones_3d u
                      join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
                      where u.id_sensor = s.id
                         or u.id_dispositivo = s.id_dispositivo);
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'UBICACION_3D', 'bloqueante', false,
      'ok', v_n = 0, 'detalle', v_n || ' sensores sin posición en el modelo 3D');

    select count(*) into v_n from public.ubicaciones_3d u
    join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
    where m.id_edificio = p_id_edificio and u.por_revisar;
    v_items := v_items || pg_catalog.jsonb_build_object('codigo', 'COORDENADAS_POR_REVISAR', 'bloqueante', false,
      'ok', v_n = 0, 'detalle', v_n || ' coordenadas copiadas de una versión anterior del GLB pendientes de revisar');
  end if;

  return pg_catalog.jsonb_build_object(
    'completo', not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_items) i
      where (i->>'bloqueante')::boolean and not (i->>'ok')::boolean),
    'comprobaciones', v_items);
end;
$$;

-- 9. Filas de la etiqueta de un dispositivo: los parámetros opcionales del medidor general
--    (tensiones, intensidades…) no ocupan fila; se ven al desplegar la etiqueta en la pestaña
--    Suministros. La distancia mínima entre etiquetas (D53) cuenta solo las filas fijas.
create or replace function public.filas_etiqueta_dispositivo(p_id_dispositivo uuid)
returns integer
language sql
stable
security definer   -- la usa el trigger de validación; solo cuenta sensores
set search_path = ''
as $$
  select pg_catalog.count(*)::integer
  from public.sensores s
  left join public.parametros_medidor pm on pm.id = s.id_parametro_medidor
  where s.id_dispositivo = p_id_dispositivo and s.activo
    and (pm.id is null or pm.obligatorio);
$$;
revoke all on function public.filas_etiqueta_dispositivo(uuid) from public, anon;
grant execute on function public.filas_etiqueta_dispositivo(uuid) to authenticated, service_role;

create or replace function public.validar_etiqueta_3d()
returns trigger
language plpgsql
security definer   -- compara con todas las etiquetas del modelo; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_modelo public.modelos_3d%rowtype;
  v_recinto uuid;
  v_planta uuid;
  v_dispositivo uuid;
  v_filas integer;
  v_cota numeric;
  v_otra record;
  v_comprobar boolean;
begin
  -- Solo se comprueba al colocar o mover una etiqueta, al hacerla visible o al confirmar una copiada;
  -- no en las sustituciones de sensores o dispositivos (que solo cambian a quién pertenece)
  v_comprobar := tg_op = 'INSERT'
    or (new.x, new.z) is distinct from (old.x, old.z)
    or (new.visible and not old.visible)
    or (old.por_revisar and not new.por_revisar);

  select * into v_modelo from public.modelos_3d where id = new.id_modelo_3d;
  if not found then
    return new;   -- validar_ubicacion_3d ya lo rechaza
  end if;

  if new.id_sensor is not null then
    select s.id_recinto, s.id_dispositivo into v_recinto, v_dispositivo from public.sensores s where s.id = new.id_sensor;
    if v_dispositivo is not null and not new.por_revisar and v_comprobar then
      raise exception 'El sensor pertenece a un dispositivo: coloque el dispositivo y sus sensores heredan el punto'
        using errcode = 'check_violation';
    end if;
    v_filas := 1;
  else
    select d.id_recinto into v_recinto from public.dispositivos d where d.id = new.id_dispositivo;
    v_filas := public.filas_etiqueta_dispositivo(new.id_dispositivo);
  end if;
  select r.id_planta into v_planta from public.recintos r where r.id = v_recinto;

  -- Altura fija: 1,5 m sobre el nivel más bajo de la planta en el modelo del edificio
  if v_modelo.tipo_modelo = 'EDIFICIO' then
    select pg_catalog.min((n->>'cota')::numeric) into v_cota
    from public.plantas p, pg_catalog.jsonb_array_elements(v_modelo.niveles) n
    where p.id = v_planta and n->>'nombre' = any (p.niveles_modelo);
    if v_cota is not null then
      new.y := v_cota + (public.parametros_etiquetas_3d()->>'altura_m')::numeric;
    end if;
  end if;

  -- Distancia mínima con las demás etiquetas visibles de la misma planta
  if v_comprobar and new.visible and not new.por_revisar and v_modelo.ancho_m is not null and v_modelo.fondo_m is not null then
    for v_otra in
      select u.x, u.z, coalesce(d.nombre, s.nombre) as nombre,
             case when u.id_dispositivo is not null
                  then public.filas_etiqueta_dispositivo(u.id_dispositivo)
                  else 1 end as filas
      from public.ubicaciones_3d u
      left join public.sensores s on s.id = u.id_sensor
      left join public.dispositivos d on d.id = u.id_dispositivo
      join public.recintos r on r.id = coalesce(s.id_recinto, d.id_recinto)
      where u.id_modelo_3d = new.id_modelo_3d and u.id <> new.id and u.visible and not u.por_revisar
        and r.id_planta = v_planta
    loop
      if pg_catalog.sqrt((v_otra.x - new.x) ^ 2 + (v_otra.z - new.z) ^ 2)
         < public.distancia_minima_etiquetas(new.id_modelo_3d, v_filas, v_otra.filas::integer) then
        raise exception 'Valor no permitido: la etiqueta quedaría a % m de «%» y en este modelo la distancia mínima es % m. Sepárela o use un modelo por recinto',
          pg_catalog.round(pg_catalog.sqrt((v_otra.x - new.x) ^ 2 + (v_otra.z - new.z) ^ 2), 1), v_otra.nombre,
          public.distancia_minima_etiquetas(new.id_modelo_3d, v_filas, v_otra.filas::integer)
          using errcode = 'check_violation';
      end if;
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function public.validar_etiqueta_3d() from public, anon;

revoke all on function public.validar_parametro_medidor() from public, anon;
revoke all on function public.parametros_faltan_suministro(uuid) from public, anon;
revoke all on function public.suministros_edificio(uuid) from public, anon;
revoke all on function public.consumo_mensual_suministro(uuid) from public, anon;
revoke all on function public.estado_parametrizacion_edificio(uuid) from public, anon;
grant execute on function public.parametros_faltan_suministro(uuid) to authenticated, service_role;
grant execute on function public.suministros_edificio(uuid) to authenticated, service_role;
grant execute on function public.consumo_mensual_suministro(uuid) to authenticated, service_role;
grant execute on function public.estado_parametrizacion_edificio(uuid) to authenticated, service_role;

commit;
