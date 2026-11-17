-- =========================================================
-- 052 · Pestaña Producción: fotovoltaica y solar térmica
-- Decisión D58 (17/11/2026).
--
--   Mismo criterio que Suministros (D57):
--   · Fuente de producción = suministro de tipo GENERACION. Ficha ampliada
--     (módulos, inversor, orientación, inclinación, autoconsumo, CAU,
--     instalador, mantenedor; en solar térmica, captadores, acumulador y
--     caldera de apoyo).
--   · Medidor de producción (medidor_general del suministro) con su catálogo
--     de parámetros. Obligatorios (bloquean la parametrización):
--       - fotovoltaica: energía producida (contador) y potencia;
--       - solar térmica: energía térmica producida (contador) y potencia térmica.
--   · Superficies de placas (superficies_produccion): del modelo 3D (objetos
--     marcados «FV: <campo>» o «ST: <campo>») o dibujadas en una planta
--     (polígono X/Z). El visor las ilumina con la producción del momento.
--   · Usos a los que da servicio la solar térmica: el reparto del calor
--     renovable (repartos_uso_edificio, tipo CALOR_RENOVABLE), ya existente.
--   · produccion_edificio(): fichas con parámetros, superficies y KPIs.
--   · sankey_energia(): añade «desglose» (qué energía llega a cada uso),
--     para ver qué parte de un uso térmico viene de las placas solares.
-- =========================================================
begin;

-- 1. Ficha de la instalación
alter table public.suministros_generacion
  add column if not exists numero_modulos integer,
  add column if not exists potencia_modulo_w numeric(8,1),
  add column if not exists inversor varchar(150),
  add column if not exists potencia_inversor_kw numeric(10,2),
  add column if not exists azimut_grados numeric(6,2),
  add column if not exists inclinacion_grados numeric(5,2),
  add column if not exists modalidad_autoconsumo varchar(30),
  add column if not exists cau varchar(30),
  add column if not exists instalador varchar(150),
  add column if not exists mantenedor varchar(150),
  add column if not exists numero_captadores integer,
  add column if not exists tipo_captador varchar(20),
  add column if not exists volumen_acumulador_l numeric(10,1),
  add column if not exists caldera_apoyo varchar(150);

alter table public.suministros_generacion drop constraint if exists suministros_generacion_ficha_ck;
alter table public.suministros_generacion add constraint suministros_generacion_ficha_ck check (
  (numero_modulos is null or numero_modulos > 0)
  and (potencia_modulo_w is null or potencia_modulo_w > 0)
  and (potencia_inversor_kw is null or potencia_inversor_kw > 0)
  and (azimut_grados is null or azimut_grados between -180 and 180)
  and (inclinacion_grados is null or inclinacion_grados between 0 and 90)
  and (modalidad_autoconsumo is null or modalidad_autoconsumo in
       ('SIN_EXCEDENTES', 'CON_EXCEDENTES_COMPENSACION', 'CON_EXCEDENTES_SIN_COMPENSACION', 'AISLADA'))
  and (numero_captadores is null or numero_captadores > 0)
  and (tipo_captador is null or tipo_captador in ('PLANO', 'TUBO_VACIO', 'OTRO'))
  and (volumen_acumulador_l is null or volumen_acumulador_l > 0));

comment on column public.suministros_generacion.azimut_grados is 'Orientación de las placas: 0 = sur, −90 = este, 90 = oeste.';
comment on column public.suministros_generacion.modalidad_autoconsumo is
  'SIN_EXCEDENTES, CON_EXCEDENTES_COMPENSACION (compensación simplificada), CON_EXCEDENTES_SIN_COMPENSACION o AISLADA.';
comment on column public.suministros_generacion.cau is 'Código de autoconsumo (CAU).';

-- 2. Parámetros del medidor de producción
alter table public.parametros_medidor drop constraint if exists parametros_medidor_tipo_ck;
alter table public.parametros_medidor add constraint parametros_medidor_tipo_ck
  check (tipo_suministro in ('ELECTRICIDAD', 'GAS', 'AGUA', 'FOTOVOLTAICA', 'SOLAR_TERMICA'));

insert into public.parametros_medidor (codigo, nombre, tipo_suministro, familias, unidad, obligatorio, consumo, orden) values
  ('FV_ENERGIA', 'Energía producida', 'FOTOVOLTAICA', '{ENERGIA}', 'kWh', true, true, 1),
  ('FV_POTENCIA', 'Potencia', 'FOTOVOLTAICA', '{POTENCIA}', 'kW', true, false, 2),
  ('FV_IRRADIANCIA', 'Irradiancia', 'FOTOVOLTAICA', '{OTRA}', 'W/m²', false, false, 3),
  ('FV_TEMPERATURA_MODULO', 'Temperatura de módulo', 'FOTOVOLTAICA', '{TEMPERATURA}', '°C', false, false, 4),
  ('FV_TENSION_DC', 'Tensión DC', 'FOTOVOLTAICA', '{TENSION}', 'V', false, false, 5),
  ('FV_INTENSIDAD_DC', 'Intensidad DC', 'FOTOVOLTAICA', '{INTENSIDAD}', 'A', false, false, 6),
  ('FV_TENSION_AC', 'Tensión AC', 'FOTOVOLTAICA', '{TENSION}', 'V', false, false, 7),
  ('FV_INTENSIDAD_AC', 'Intensidad AC', 'FOTOVOLTAICA', '{INTENSIDAD}', 'A', false, false, 8),
  ('FV_ESTADO_INVERSOR', 'Estado del inversor', 'FOTOVOLTAICA', '{ESTADO}', '-', false, false, 9),
  ('ST_ENERGIA', 'Energía térmica producida', 'SOLAR_TERMICA', '{ENERGIA}', 'kWh', true, true, 1),
  ('ST_POTENCIA', 'Potencia térmica', 'SOLAR_TERMICA', '{POTENCIA}', 'kW', true, false, 2),
  ('ST_TEMPERATURA_IMPULSION', 'Temperatura de impulsión', 'SOLAR_TERMICA', '{TEMPERATURA}', '°C', false, false, 3),
  ('ST_TEMPERATURA_RETORNO', 'Temperatura de retorno', 'SOLAR_TERMICA', '{TEMPERATURA}', '°C', false, false, 4),
  ('ST_TEMPERATURA_ACUMULADOR', 'Temperatura del acumulador', 'SOLAR_TERMICA', '{TEMPERATURA}', '°C', false, false, 5),
  ('ST_TEMPERATURA_CAPTADOR', 'Temperatura de captador', 'SOLAR_TERMICA', '{TEMPERATURA}', '°C', false, false, 6),
  ('ST_CAUDAL', 'Caudal del primario', 'SOLAR_TERMICA', '{CAUDAL}', 'm³/h', false, false, 7)
on conflict (codigo) do nothing;

-- Catálogo de parámetros que corresponde a cada suministro (la generación, según su tecnología)
create or replace function private.tipo_parametros_suministro(p_id_suministro uuid)
returns text
language sql
stable
security definer   -- solo traduce el tipo; quien llama ya ve el suministro
set search_path = ''
as $$
  select case su.tipo
           when 'AGUA_INCENDIOS' then 'AGUA'
           when 'GENERACION' then (select case when g.tecnologia in ('FOTOVOLTAICA', 'SOLAR_TERMICA') then g.tecnologia end
                                   from public.suministros_generacion g where g.id_suministro = su.id)
           else su.tipo end
  from public.suministros su where su.id = p_id_suministro;
$$;
revoke all on function private.tipo_parametros_suministro(uuid) from public, anon;
grant execute on function private.tipo_parametros_suministro(uuid) to authenticated, service_role;

create or replace function public.parametros_faltan_suministro(p_id_suministro uuid)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.array_agg(pm.nombre::text order by pm.orden), '{}')
  from public.parametros_medidor pm
  where pm.tipo_suministro = private.tipo_parametros_suministro(p_id_suministro)
    and pm.obligatorio and pm.activo
    and not exists (
      select 1 from public.suministros_dispositivos sd
      join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
      where sd.id_suministro = p_id_suministro and sd.activo and sd.medidor_general
        and s.id_parametro_medidor = pm.id);
$$;

-- 3. Superficies de placas: del modelo 3D o dibujadas en una planta
create table if not exists public.superficies_produccion (
  id uuid primary key default gen_random_uuid(),
  id_suministro uuid not null references public.suministros(id),
  id_edificio uuid not null references public.edificios(id),
  id_planta uuid not null references public.plantas(id),
  nombre varchar(120) not null,
  origen varchar(10) not null,
  clave_objeto varchar(200),
  poligono jsonb not null default '[]',
  altura_m numeric(6,2) not null default 0.3,
  inclinacion_grados numeric(5,2),
  azimut_grados numeric(6,2),
  area_m2 numeric(10,2),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint superficies_produccion_origen_ck check (origen in ('MODELO', 'DIBUJADA')),
  constraint superficies_produccion_datos_ck check (
    pg_catalog.jsonb_typeof(poligono) = 'array'
    and (origen <> 'MODELO' or clave_objeto is not null)
    and (origen <> 'DIBUJADA' or pg_catalog.jsonb_array_length(poligono) >= 3)
    and (inclinacion_grados is null or inclinacion_grados between 0 and 90)
    and (azimut_grados is null or azimut_grados between -180 and 180)
    and (area_m2 is null or area_m2 > 0)
    and altura_m between 0 and 20)
);
alter table public.superficies_produccion enable row level security;

comment on table public.superficies_produccion is
  'Dónde están las placas de cada fuente de producción (D58). MODELO: objetos del GLB marcados «FV: <campo>» o «ST: <campo>» (clave_objeto = <campo>). DIBUJADA: polígono [[x, z], …] en metros sobre el modelo preparado, a altura_m sobre el suelo de la planta.';
create index if not exists superficies_produccion_suministro_ix on public.superficies_produccion (id_suministro) where activo;

create or replace function public.validar_superficie_produccion()
returns trigger
language plpgsql
security definer   -- comprueba edificios aunque el usuario no vea todo; el permiso lo decide RLS
set search_path = ''
as $$
declare
  v_tec text;
  v_area double precision := 0;
  v_n integer;
  i integer;
begin
  select su.id_edificio, g.tecnologia into new.id_edificio, v_tec
  from public.suministros su left join public.suministros_generacion g on g.id_suministro = su.id
  where su.id = new.id_suministro and su.tipo = 'GENERACION';
  if new.id_edificio is null or v_tec not in ('FOTOVOLTAICA', 'SOLAR_TERMICA') then
    raise exception 'Las superficies de placas son de una instalación fotovoltaica o solar térmica'
      using errcode = 'check_violation';
  end if;
  if (select p.id_edificio from public.plantas p where p.id = new.id_planta) is distinct from new.id_edificio then
    raise exception 'La planta tiene que ser del mismo edificio que la instalación' using errcode = 'check_violation';
  end if;
  -- Polígono: puntos [x, z] numéricos; la superficie (en planta, sin inclinación) se calcula si falta
  v_n := pg_catalog.jsonb_array_length(new.poligono);
  for i in 0 .. v_n - 1 loop
    if pg_catalog.jsonb_typeof(new.poligono->i) <> 'array' or pg_catalog.jsonb_array_length(new.poligono->i) <> 2
       or pg_catalog.jsonb_typeof(new.poligono->i->0) <> 'number' or pg_catalog.jsonb_typeof(new.poligono->i->1) <> 'number' then
      raise exception 'Cada punto del polígono es [x, z] en metros' using errcode = 'check_violation';
    end if;
    v_area := v_area + (new.poligono->i->>0)::double precision * (new.poligono->((i + 1) % v_n)->>1)::double precision
                     - (new.poligono->((i + 1) % v_n)->>0)::double precision * (new.poligono->i->>1)::double precision;
  end loop;
  if new.area_m2 is null and v_n >= 3 then
    new.area_m2 := pg_catalog.round((abs(v_area) / 2 / pg_catalog.cos(pg_catalog.radians(coalesce(new.inclinacion_grados, 0))))::numeric, 2);
  end if;
  return new;
end;
$$;
revoke all on function public.validar_superficie_produccion() from public, anon;

drop trigger if exists trg_superficies_produccion_validar on public.superficies_produccion;
create trigger trg_superficies_produccion_validar
before insert or update on public.superficies_produccion
for each row execute function public.validar_superficie_produccion();

drop trigger if exists trg_superficies_produccion_updated_at on public.superficies_produccion;
create trigger trg_superficies_produccion_updated_at
before update on public.superficies_produccion
for each row execute function public.set_updated_at();

drop trigger if exists trg_auditoria on public.superficies_produccion;
create trigger trg_auditoria after insert or update or delete on public.superficies_produccion
for each row execute function public.auditar_cambio();

-- Mismos permisos que los suministros (baja lógica con «activo»: sin borrado)
drop policy if exists superficies_produccion_select on public.superficies_produccion;
create policy superficies_produccion_select on public.superficies_produccion
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_SUMINISTRO'));

drop policy if exists superficies_produccion_insert on public.superficies_produccion;
create policy superficies_produccion_insert on public.superficies_produccion
for insert to authenticated
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_SUMINISTRO'));

drop policy if exists superficies_produccion_update on public.superficies_produccion;
create policy superficies_produccion_update on public.superficies_produccion
for update to authenticated
using (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_SUMINISTRO'))
with check (private.usuario_puede_edificio(id_edificio, 'MODIFICAR_SUMINISTRO'));

revoke all on public.superficies_produccion from anon;
grant select, insert, update on public.superficies_produccion to authenticated;
grant all on public.superficies_produccion to service_role;

-- 4. Lista de comprobación: la producción FV y solar térmica también necesita su medidor (bloqueante)
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
    where su.id_edificio = p_id_edificio and su.activo
      and private.tipo_parametros_suministro(su.id) is not null   -- 052: también la producción FV y solar térmica
    order by su.tipo, su.nombre
  loop
    v_items := v_items || pg_catalog.jsonb_build_object(
      'codigo', 'MEDIDOR_GENERAL', 'bloqueante', v_sum.tipo in ('ELECTRICIDAD', 'GAS', 'GENERACION'),
      'ok', v_sum.con_medidor and pg_catalog.cardinality(v_sum.faltan) = 0,
      'detalle', case
        when not v_sum.con_medidor then '«' || v_sum.nombre || '»: falta el medidor ' || case when v_sum.tipo = 'GENERACION' then 'de producción' else 'general' end
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

-- 5. Sankey con el desglose de la energía que llega a cada uso
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
    -- 052: qué energía (electricidad, gas, calor renovable) llega a cada uso y a cada grupo de usos
    'desglose', coalesce((
      select pg_catalog.jsonb_object_agg(x.nodo, x.fuentes)
      from (
        select y.nodo, pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('tipo', y.tipo, 'valor', y.valor) order by y.valor desc) as fuentes
        from (
          select z.nodo, z.tipo, pg_catalog.round(sum(z.valor)::numeric, 3) as valor
          from (select f.grupo as nodo, f.tipo, f.valor from flujos f
                union all
                select f.detalle, f.tipo, f.valor from flujos f where f.detalle <> f.grupo) z
          group by z.nodo, z.tipo
          having pg_catalog.round(sum(z.valor)::numeric, 3) > 0
        ) y
        group by y.nodo
      ) x), '{}'::jsonb),
    'avisos', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id_edificio', id_edificio, 'tipo', tipo,
               'mensaje', 'Los submedidores suman más que el consumo total: revise la asignación de usos'))
      from resto where medido > total * 1.02 and total > 0), '[]'::jsonb)
  );
$$;

-- Factor de emisiones vigente (parámetro de la plataforma): lo pueden leer los usuarios
create or replace function private.factor_co2(p_tipo text, p_fecha date)
returns numeric
language sql
stable
security definer   -- parametros_saas solo es legible por el servicio; aquí solo se expone el factor de CO₂
set search_path = ''
as $$
  select private.parametro_vigente('FACTOR_CO2_' || p_tipo, p_fecha)
  where p_tipo in ('ELECTRICIDAD', 'GAS');
$$;
revoke all on function private.factor_co2(text, date) from public, anon;
grant execute on function private.factor_co2(text, date) to authenticated, service_role;

-- 6. Fichas de producción (pestaña Producción)
create or replace function public.produccion_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with
  par as (
    select (pg_catalog.now() at time zone e.zona_horaria)::date as hoy from public.edificios e where e.id = p_id_edificio
  ),
  est as (select * from public.sensores_estado_edificio(p_id_edificio)),
  gen as (
    select su.id, su.codigo, su.nombre, su.descripcion, su.fecha_inicio, g.tecnologia,
           pg_catalog.to_jsonb(g) - 'id_suministro' as detalle, g.potencia_pico_kw, g.superficie_m2
    from public.suministros su
    join public.suministros_generacion g on g.id_suministro = su.id
    where su.id_edificio = p_id_edificio and su.activo and g.tecnologia in ('FOTOVOLTAICA', 'SOLAR_TERMICA')
  ),
  -- Parámetros del medidor de cada fuente (obligatorios siempre; opcionales, si tienen sensor)
  pars as (
    select gen.id as id_suministro, pm.codigo, pm.nombre, pm.obligatorio, pm.consumo, pm.orden, pm.unidad as unidad_pm,
           e.id_sensor, e.unidad, e.ultimo_valor, e.ultima_lectura, e.estado_comunicacion, e.alarma_activa,
           e.valor_hoy, e.valor_hoy_kwh, e.valor_comparable
    from gen
    join public.parametros_medidor pm on pm.tipo_suministro = gen.tecnologia and pm.activo
    left join lateral (
      select est.* from public.suministros_dispositivos sd
      join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo and s.id_parametro_medidor = pm.id
      join est on est.id_sensor = s.id
      where sd.id_suministro = gen.id and sd.activo and sd.medidor_general
      limit 1) e on true
  ),
  -- Electricidad del edificio hoy (medidores generales de la red): para autoconsumo y cobertura
  red as (
    select sum(e.valor_hoy) filter (where pm.codigo = 'ENERGIA_ACTIVA_IMPORTADA') as importada,
           sum(e.valor_hoy) filter (where pm.codigo = 'ENERGIA_ACTIVA_EXPORTADA') as exportada
    from public.suministros su
    join public.suministros_dispositivos sd on sd.id_suministro = su.id and sd.activo and sd.medidor_general
    join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
    join public.parametros_medidor pm on pm.id = s.id_parametro_medidor
    join est e on e.id_sensor = s.id
    where su.id_edificio = p_id_edificio and su.activo and su.tipo = 'ELECTRICIDAD'
  ),
  fv_total as (
    select sum(p.valor_hoy) as total from pars p join gen on gen.id = p.id_suministro
    where gen.tecnologia = 'FOTOVOLTAICA' and p.codigo = 'FV_ENERGIA'
  ),
  -- Sankey de hoy: qué energía llega a cada uso (para el aporte de la solar térmica)
  sk as (select public.sankey_energia('EDIFICIO', p_id_edificio, par.hoy, par.hoy) as j from par
         where exists (select 1 from gen where gen.tecnologia = 'SOLAR_TERMICA')),   -- solo si hay solar térmica
  usos_st as (
    select u.codigo, u.nombre, ru.porcentaje
    from public.repartos_uso_edificio ru join public.usos_energia u on u.id = ru.id_uso_energia
    where ru.id_edificio = p_id_edificio and ru.tipo_energia = 'CALOR_RENOVABLE'
  ),
  aporte as (
    select sum((d->>'valor')::numeric) filter (where d->>'tipo' = 'CALOR_RENOVABLE') as solar,
           sum((d->>'valor')::numeric) as total
    from usos_st, sk, pg_catalog.jsonb_array_elements(coalesce(sk.j->'desglose'->usos_st.codigo, '[]')) d
  ),
  fichas as (
    select gen.*,
      (select p.valor_hoy from pars p where p.id_suministro = gen.id and p.consumo) as prod_hoy,
      (select p.valor_comparable from pars p where p.id_suministro = gen.id and p.consumo) as prod_comp,
      (select p.ultimo_valor from pars p where p.id_suministro = gen.id and p.codigo in ('FV_POTENCIA', 'ST_POTENCIA')) as potencia,
      (select p.ultimo_valor from pars p where p.id_suministro = gen.id and p.codigo = 'FV_IRRADIANCIA') as irradiancia,
      (select p.ultimo_valor from pars p where p.id_suministro = gen.id and p.codigo = 'ST_TEMPERATURA_IMPULSION')
        - (select p.ultimo_valor from pars p where p.id_suministro = gen.id and p.codigo = 'ST_TEMPERATURA_RETORNO') as salto,
      coalesce(gen.superficie_m2, (select sum(sp.area_m2) from public.superficies_produccion sp
                                   where sp.id_suministro = gen.id and sp.activo)) as superficie
    from gen
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', f.id, 'codigo', f.codigo, 'nombre', f.nombre, 'tipo', 'GENERACION', 'tecnologia', f.tecnologia,
    'tipo_parametros', f.tecnologia, 'descripcion', f.descripcion, 'fecha_inicio', f.fecha_inicio, 'detalle', f.detalle,
    'medidor', (
      select pg_catalog.jsonb_build_object('id', d.id, 'codigo', d.codigo, 'nombre', d.nombre,
               'fabricante', d.fabricante, 'modelo', d.modelo, 'numero_serie', d.numero_serie)
      from public.suministros_dispositivos sd join public.dispositivos d on d.id = sd.id_dispositivo
      where sd.id_suministro = f.id and sd.activo and sd.medidor_general),
    'parametros', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'codigo', p.codigo, 'nombre', p.nombre, 'obligatorio', p.obligatorio, 'consumo', p.consumo,
               'id_sensor', p.id_sensor, 'unidad', coalesce(p.unidad, p.unidad_pm),
               'ultimo_valor', p.ultimo_valor, 'ultima_lectura', p.ultima_lectura,
               'estado_comunicacion', p.estado_comunicacion, 'alarma_activa', p.alarma_activa,
               'valor_hoy', p.valor_hoy, 'valor_hoy_kwh', p.valor_hoy_kwh, 'valor_comparable', p.valor_comparable) order by p.orden)
      from pars p where p.id_suministro = f.id and (p.obligatorio or p.id_sensor is not null)), '[]'::jsonb),
    'faltan', pg_catalog.to_jsonb(public.parametros_faltan_suministro(f.id)),
    'superficies', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
               'id', sp.id, 'nombre', sp.nombre, 'origen', sp.origen, 'clave_objeto', sp.clave_objeto,
               'poligono', sp.poligono, 'altura_m', sp.altura_m, 'id_planta', sp.id_planta, 'planta', pl.nombre,
               'inclinacion_grados', sp.inclinacion_grados, 'azimut_grados', sp.azimut_grados, 'area_m2', sp.area_m2)
             order by sp.nombre)
      from public.superficies_produccion sp join public.plantas pl on pl.id = sp.id_planta
      where sp.id_suministro = f.id and sp.activo), '[]'::jsonb),
    'usos_servidos', case when f.tecnologia = 'SOLAR_TERMICA' then coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('codigo', u.codigo, 'nombre', u.nombre, 'porcentaje', u.porcentaje)
             order by u.porcentaje desc) from usos_st u), '[]'::jsonb) end,
    'kpis', case f.tecnologia
      when 'FOTOVOLTAICA' then (
        select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'produccion_hoy', f.prod_hoy,
          'variacion_pct', case when f.prod_comp > 0 then pg_catalog.round(((f.prod_hoy / f.prod_comp - 1) * 100)::numeric, 1) end,
          'potencia', f.potencia,
          'pct_pico', case when f.potencia_pico_kw > 0 and f.potencia is not null
                           then pg_catalog.round((f.potencia / f.potencia_pico_kw * 100)::numeric, 1) end,
          -- Lo exportado (medidor general de la red) se reparte entre las fotovoltaicas por su producción
          'exportada_hoy', x.exp,
          'autoconsumo_hoy', case when f.prod_hoy is not null then greatest(f.prod_hoy - coalesce(x.exp, 0), 0) end,
          'autoconsumo_pct', case when f.prod_hoy > 0 then pg_catalog.round((greatest(f.prod_hoy - coalesce(x.exp, 0), 0) / f.prod_hoy * 100)::numeric, 1) end,
          'cobertura_pct', case when f.prod_hoy is not null and coalesce(red.importada, 0) + greatest(f.prod_hoy - coalesce(x.exp, 0), 0) > 0
                                then pg_catalog.round((greatest(f.prod_hoy - coalesce(x.exp, 0), 0)
                                     / (coalesce(red.importada, 0) + greatest(f.prod_hoy - coalesce(x.exp, 0), 0)) * 100)::numeric, 1) end,
          'especifica_kwh_kwp', case when f.potencia_pico_kw > 0 then pg_catalog.round((f.prod_hoy / f.potencia_pico_kw)::numeric, 2) end,
          'emisiones_evitadas_kg', pg_catalog.round((f.prod_hoy * private.factor_co2('ELECTRICIDAD', par.hoy))::numeric, 1),
          -- Rendimiento instantáneo (PR): potencia real frente a la teórica con la irradiancia medida
          'rendimiento_pct', case when f.irradiancia > 50 and f.potencia_pico_kw > 0 and f.potencia is not null
                                  then pg_catalog.round((f.potencia / (f.potencia_pico_kw * f.irradiancia / 1000) * 100)::numeric, 1) end))
        from red, fv_total, par,
             lateral (select case when red.exportada is not null and fv_total.total > 0
                                  then least(red.exportada, fv_total.total) * coalesce(f.prod_hoy, 0) / fv_total.total end as exp) x)
      else (
        select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
          'produccion_hoy', f.prod_hoy,
          'variacion_pct', case when f.prod_comp > 0 then pg_catalog.round(((f.prod_hoy / f.prod_comp - 1) * 100)::numeric, 1) end,
          'potencia', f.potencia,
          'especifica_kwh_m2', case when f.superficie > 0 then pg_catalog.round((f.prod_hoy / f.superficie)::numeric, 2) end,
          'salto_termico', pg_catalog.round(f.salto::numeric, 1),
          -- Parte de la energía de los usos servidos (ACS, calefacción) que viene del calor renovable
          'aporte_solar_pct', case when aporte.total > 0 then pg_catalog.round((aporte.solar / aporte.total * 100)::numeric, 1) end))
        from aporte)
      end) order by f.tecnologia, f.nombre), '[]'::jsonb)
  from fichas f;
$$;

revoke all on function public.produccion_edificio(uuid) from public, anon;
grant execute on function public.produccion_edificio(uuid) to authenticated, service_role;

commit;
