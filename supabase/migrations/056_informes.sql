-- =========================================================
-- 056 · Informes semanal y mensual del edificio (D61)
--  - informes: una foto de los datos de cada semana o mes (no cambia aunque luego
--    se recalculen datos; se puede volver a generar).
--  - informes_destinatarios: quién lo recibe por email (lo elige el Partner).
--  - Marca: logo del Partner (bucket público «logos») y nombre de la plataforma.
--  - preparar_informes() (pg_cron cada mañana): los lunes el semanal y el día 1 el mensual.
-- =========================================================
begin;

-- 1. Marca
insert into public.parametros_saas (codigo, nombre, valor_texto, descripcion)
select 'NOMBRE_PLATAFORMA', 'Nombre de la plataforma', 'Plataforma de gestión energética',
       'Sale en los informes y emails junto al logo del Partner'
where not exists (select 1 from public.parametros_saas where codigo = 'NOMBRE_PLATAFORMA' and activo);

alter table public.proveedores add column if not exists logo_ruta text;   -- ruta en el bucket «logos»

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos', 'logos', true, 524288, array['image/png', 'image/jpeg', 'image/svg+xml', 'image/webp'])
on conflict (id) do nothing;

-- Escriben el logo de un Partner: el administrador de la plataforma y el administrador de ese Partner
-- (ruta proveedores/<id_proveedor>/logo.<ext>). La lectura es pública (logos en informes y emails).
create or replace function private.puede_cambiar_logo(p_ruta text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_partes text[] := pg_catalog.string_to_array(p_ruta, '/');
  v_proveedor uuid;
  v_rol text := private.rol_usuario(private.usuario_actual());
begin
  if pg_catalog.cardinality(v_partes) <> 3 or v_partes[1] <> 'proveedores' then return false; end if;
  begin
    v_proveedor := v_partes[2]::uuid;
  exception when others then
    return false;
  end;
  return v_rol = 'ADMIN_SAAS' or (v_rol = 'ADMIN_PARTNER' and private.usuario_es_del_partner(v_proveedor));
end;
$$;
revoke all on function private.puede_cambiar_logo(text) from public, anon;
grant execute on function private.puede_cambiar_logo(text) to authenticated;

drop policy if exists logos_insert on storage.objects;
create policy logos_insert on storage.objects for insert to authenticated
with check (bucket_id = 'logos' and private.puede_cambiar_logo(name));
drop policy if exists logos_update on storage.objects;
create policy logos_update on storage.objects for update to authenticated
using (bucket_id = 'logos' and private.puede_cambiar_logo(name)) with check (bucket_id = 'logos' and private.puede_cambiar_logo(name));
drop policy if exists logos_delete on storage.objects;
create policy logos_delete on storage.objects for delete to authenticated
using (bucket_id = 'logos' and private.puede_cambiar_logo(name));

create or replace function public.fijar_logo_partner(p_id_proveedor uuid, p_ruta text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_ruta is not null and (p_ruta not like 'proveedores/' || p_id_proveedor || '/%' or not private.puede_cambiar_logo(p_ruta)) then
    raise exception 'Sin permiso para cambiar el logo de este Partner' using errcode = '42501';
  end if;
  if p_ruta is null and not private.puede_cambiar_logo('proveedores/' || p_id_proveedor || '/logo.png') then
    raise exception 'Sin permiso para cambiar el logo de este Partner' using errcode = '42501';
  end if;
  update public.proveedores set logo_ruta = p_ruta where id = p_id_proveedor;
end;
$$;
revoke all on function public.fijar_logo_partner(uuid, text) from public, anon;
grant execute on function public.fijar_logo_partner(uuid, text) to authenticated;

-- 2. Informes y destinatarios
create table if not exists public.informes (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id),
  tipo text not null check (tipo in ('SEMANAL', 'MENSUAL')),
  desde date not null,
  hasta date not null,
  datos jsonb not null,
  generado_en timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  constraint ck_informes_periodo check (hasta >= desde),
  constraint ux_informes_periodo unique (id_edificio, tipo, desde)
);
alter table public.informes enable row level security;
drop policy if exists informes_select on public.informes;
create policy informes_select on public.informes for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_EDIFICIO'));
grant select on public.informes to authenticated;

create table if not exists public.informes_destinatarios (
  id_edificio uuid not null references public.edificios(id),
  id_usuario uuid not null references public.usuarios(id),
  semanal boolean not null default false,
  mensual boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (id_edificio, id_usuario)
);
alter table public.informes_destinatarios enable row level security;
drop policy if exists informes_destinatarios_select on public.informes_destinatarios;
create policy informes_destinatarios_select on public.informes_destinatarios for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_EDIFICIO'));
grant select on public.informes_destinatarios to authenticated;
-- Sin políticas de escritura: guardar_destinatarios_informes

-- 3. Emails de informes en notificaciones
alter table public.notificaciones drop constraint if exists notificaciones_tipo_check;
alter table public.notificaciones drop constraint if exists ck_notificaciones_tipo;
do $$
declare r record;
begin
  for r in select conname from pg_constraint where conrelid = 'public.notificaciones'::regclass and contype = 'c'
             and (pg_get_constraintdef(oid) like '%tipo%ALARMA%COMUNICACION%' or pg_get_constraintdef(oid) like '%motivo%INMEDIATO%')
  loop
    execute pg_catalog.format('alter table public.notificaciones drop constraint %I', r.conname);
  end loop;
end;
$$;
alter table public.notificaciones add constraint ck_notificaciones_tipo check (tipo in ('ALARMA', 'COMUNICACION', 'INFORME'));
alter table public.notificaciones add constraint ck_notificaciones_motivo check (motivo is null or motivo in
  ('INMEDIATO', 'ESCALADO', 'REAVISO', 'RESUMEN_DIARIO', 'INFORME_SEMANAL', 'INFORME_MENSUAL'));
create unique index if not exists ux_notificaciones_informe on public.notificaciones (id_usuario, ((datos->>'id_informe')))
  where motivo in ('INFORME_SEMANAL', 'INFORME_MENSUAL');

-- 4. Cálculo
-- Energía de un periodo con la misma definición que los KPI (energía consumida = importada + gas + renovable consumida)
create or replace function private.energia_periodo(p_id_edificio uuid, p_desde date, p_hasta date)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with d as (
    select r.indicador, r.fecha, r.valor,
           case r.indicador
             when 'CONSUMO_ELECTRICIDAD' then r.valor * coalesce(private.factor_co2('FACTOR_CO2_ELECTRICIDAD', r.fecha), 0)
             when 'CONSUMO_GAS' then r.valor * coalesce(private.factor_co2('FACTOR_CO2_GAS', r.fecha), 0)
           end as kg
    from public.resumenes_diarios r
    where r.id_edificio = p_id_edificio and r.fecha between p_desde and p_hasta
  ),
  s as (
    select count(distinct fecha) as dias,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_ELECTRICIDAD'), 0) as electricidad,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_GAS'), 0) as gas,
      coalesce(sum(valor) filter (where indicador = 'CONSUMO_AGUA'), 0) as agua,
      coalesce(sum(valor) filter (where indicador = 'ELECTRICIDAD_EXPORTADA'), 0) as exportada,
      coalesce(sum(valor) filter (where indicador in ('GENERACION_FOTOVOLTAICA', 'GENERACION_EOLICA')), 0) as ren_electrica,
      coalesce(sum(valor) filter (where indicador in ('GENERACION_SOLAR_TERMICA', 'GENERACION_GEOTERMIA', 'GENERACION_BIOMASA')), 0) as ren_termica,
      coalesce(sum(valor) filter (where indicador = 'GENERACION_FOTOVOLTAICA'), 0) as fotovoltaica,
      coalesce(sum(valor) filter (where indicador = 'GENERACION_SOLAR_TERMICA'), 0) as solar_termica,
      coalesce(sum(kg), 0) / 1000.0 as tco2
    from d
  )
  select case when s.dias = 0 then null else pg_catalog.jsonb_build_object(
    'dias', s.dias,
    'energia', pg_catalog.round((s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)::numeric, 1),
    'electricidad', pg_catalog.round(s.electricidad::numeric, 1), 'gas', pg_catalog.round(s.gas::numeric, 1),
    'agua', pg_catalog.round(s.agua::numeric, 2), 'exportada', pg_catalog.round(s.exportada::numeric, 1),
    'renovable_generada', pg_catalog.round((s.ren_electrica + s.ren_termica)::numeric, 1),
    'renovable_consumida', pg_catalog.round((greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)::numeric, 1),
    'fotovoltaica', pg_catalog.round(s.fotovoltaica::numeric, 1), 'solar_termica', pg_catalog.round(s.solar_termica::numeric, 1),
    'tco2', pg_catalog.round(s.tco2::numeric, 3),
    'cobertura_renovable_pct', case when s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica > 0
      then pg_catalog.round(((greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica)
             / (s.electricidad + s.gas + greatest(s.ren_electrica - s.exportada, 0) + s.ren_termica) * 100)::numeric, 1) end) end
  from s;
$$;
revoke all on function private.energia_periodo(uuid, date, date) from public, anon, authenticated;

create or replace function private.calcular_informe(p_id_edificio uuid, p_tipo text, p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e public.edificios%rowtype;
  v_ini timestamptz;
  v_fin timestamptz;
  v_dias integer := p_hasta - p_desde + 1;
  v_partner jsonb;
  v_energia jsonb;
  v_diario jsonb;
  v_horario jsonb;
  v_ambiente jsonb;
  v_alarmas jsonb;
  v_comunicacion jsonb;
  v_total double precision;
  v_fuera double precision;
begin
  select * into e from public.edificios where id = p_id_edificio;
  v_ini := p_desde::timestamp at time zone e.zona_horaria;
  v_fin := (p_hasta + 1)::timestamp at time zone e.zona_horaria;

  select pg_catalog.jsonb_build_object('nombre', p.nombre, 'logo', p.logo_ruta) into v_partner
  from public.proveedores_edificios pe join public.proveedores p on p.id = pe.id_proveedor
  where pe.id_edificio = p_id_edificio and pe.activo order by pe.fecha_inicio limit 1;
  if v_partner is null then   -- el Partner del cliente
    select pg_catalog.jsonb_build_object('nombre', p.nombre, 'logo', p.logo_ruta) into v_partner
    from public.proveedores_clientes pc join public.proveedores p on p.id = pc.id_proveedor
    where pc.id_cliente = e.id_cliente and pc.activo limit 1;
  end if;

  -- Energía: el periodo, el anterior y el mismo del año pasado
  v_energia := pg_catalog.jsonb_build_object(
    'actual', private.energia_periodo(p_id_edificio, p_desde, p_hasta),
    'anterior', private.energia_periodo(p_id_edificio, p_desde - v_dias, p_desde - 1),
    'anio_anterior', private.energia_periodo(p_id_edificio, (p_desde - interval '1 year')::date, (p_hasta - interval '1 year')::date));

  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('fecha', g.f,
           'electricidad', x.electricidad, 'gas', x.gas, 'agua', x.agua, 'renovable', x.renovable) order by g.f)
    into v_diario
  from pg_catalog.generate_series(p_desde, p_hasta, interval '1 day') g(f)
  left join lateral (
    select pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_ELECTRICIDAD')::numeric, 1) as electricidad,
           pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_GAS')::numeric, 1) as gas,
           pg_catalog.round(sum(r.valor) filter (where r.indicador = 'CONSUMO_AGUA')::numeric, 2) as agua,
           pg_catalog.round(sum(r.valor) filter (where r.indicador like 'GENERACION_%')::numeric, 1) as renovable
    from public.resumenes_diarios r where r.id_edificio = p_id_edificio and r.fecha = g.f::date
  ) x on true;

  -- Dentro y fuera del horario de uso (calendario del edificio)
  begin
    select sum(valor) into v_total from public.serie_energia(p_id_edificio, 'ENERGIA_CONSUMIDA', v_ini, v_fin, 'dia', 'TODOS');
    select sum(valor) into v_fuera from public.serie_energia(p_id_edificio, 'ENERGIA_CONSUMIDA', v_ini, v_fin, 'dia', 'FUERA_HORARIO');
    if coalesce(v_total, 0) > 0 then
      v_horario := pg_catalog.jsonb_build_object('total_kwh', pg_catalog.round(v_total::numeric, 1),
        'fuera_kwh', pg_catalog.round(coalesce(v_fuera, 0)::numeric, 1),
        'fuera_pct', pg_catalog.round((coalesce(v_fuera, 0) / v_total * 100)::numeric, 1));
    end if;
  exception when others then
    v_horario := null;
  end;

  -- Ambiente (solo el mensual): horas de uso, temperatura respecto a la eficiente y CO₂, por recinto
  if p_tipo = 'MENSUAL' then
    with horas as (
      select h, (h at time zone e.zona_horaria)::date as dia
      from pg_catalog.generate_series(v_ini, v_fin - interval '1 hour', interval '1 hour') h
      where private.en_horario(p_id_edificio, h)
    ),
    temporada as (
      select dia, t, case t when 'INVIERNO' then e.temp_eficiencia_invierno when 'VERANO' then e.temp_eficiencia_verano end as te
      from (select distinct dia, public.temporada_edificio(p_id_edificio, dia) as t from horas) x
    ),
    sens as (
      select s.id, f.codigo as familia, rc.id as id_recinto, rc.nombre as recinto, pl.nombre as planta, pl.nivel
      from public.sensores s
      join public.familias_sensor f on f.id = s.id_familia and f.codigo in ('TEMPERATURA', 'CO2')
      join public.recintos rc on rc.id = s.id_recinto and coalesce(rc.tipo, '') <> 'ZONA_EXTERIOR'
      join public.plantas pl on pl.id = rc.id_planta and pl.id_edificio = p_id_edificio
      where s.activo and s.id_parametro_medidor is null
    ),
    horarias as (
      select se.id_recinto, se.familia, h.h, h.dia, avg(l.valor) as v
      from sens se
      join public.lecturas l on l.id_sensor = se.id and l.fecha_hora >= v_ini and l.fecha_hora < v_fin
      join horas h on h.h = pg_catalog.date_trunc('hour', l.fecha_hora)
      group by 1, 2, 3, 4
    ),
    por_recinto as (
      select r.id_recinto, r.recinto, r.planta, r.nivel,
        count(*) filter (where ho.familia = 'TEMPERATURA') as horas_temp,
        count(*) filter (where ho.familia = 'TEMPERATURA' and public.estado_temperatura(ho.v::numeric, t.t, t.te) in ('EFICIENTE', 'LEVE')) as horas_ok,
        count(*) filter (where ho.familia = 'TEMPERATURA' and public.estado_temperatura(ho.v::numeric, t.t, t.te) in ('ALTO', 'MUY_ALTO')) as horas_alto,
        avg(ho.v) filter (where ho.familia = 'TEMPERATURA') as temp_media,
        avg(ho.v) filter (where ho.familia = 'CO2') as co2_medio,
        max(ho.v) filter (where ho.familia = 'CO2') as co2_max,
        count(*) filter (where ho.familia = 'CO2' and ho.v > 1000) as horas_co2_alto
      from (select distinct id_recinto, recinto, planta, nivel from sens) r
      left join horarias ho on ho.id_recinto = r.id_recinto
      left join temporada t on t.dia = ho.dia
      group by 1, 2, 3, 4
    )
    select pg_catalog.jsonb_build_object(
      'horas_uso', (select count(*) from horas),
      'recintos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'recinto', recinto, 'planta', planta,
        'temp_media', pg_catalog.round(temp_media::numeric, 1),
        'pct_confort', case when horas_temp > 0 then pg_catalog.round((horas_ok::numeric / horas_temp * 100), 0) end,
        'horas_alto', horas_alto,
        'co2_medio', pg_catalog.round(co2_medio::numeric, 0), 'co2_max', pg_catalog.round(co2_max::numeric, 0),
        'horas_co2_alto', horas_co2_alto) order by nivel, recinto), '[]'::jsonb))
    into v_ambiente
    from por_recinto where horas_temp > 0 or co2_medio is not null;
  end if;

  -- Alarmas del periodo
  with ev as (
    select ea.*, n.codigo as nivel, ra.nombre as regla,
           extract(epoch from ea.fecha_reconocimiento - ea.fecha_inicio) / 60 as min_rec,
           extract(epoch from coalesce(ea.fecha_resuelta, ea.fecha_cierre) - ea.fecha_inicio) / 60 as min_res
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    where ea.fecha_inicio >= v_ini and ea.fecha_inicio < v_fin
  ),
  ic as (
    select ic.*, s.nombre as sensor, r.nombre as recinto
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    where ic.fecha_inicio >= v_ini and ic.fecha_inicio < v_fin
  )
  select pg_catalog.jsonb_build_object(
    'total', (select count(*) from ev),
    'muy_criticas', (select count(*) from ev where nivel = 'MUY_CRITICA'),
    'criticas', (select count(*) from ev where nivel = 'CRITICA'),
    'avisos', (select count(*) from ev where nivel = 'AVISO'),
    'sin_comunicacion', (select count(*) from ic),
    'min_reconocer_medio', (select pg_catalog.round(avg(min_rec)::numeric) from ev where min_rec is not null),
    'min_resolver_medio', (select pg_catalog.round(avg(min_res)::numeric) from ev where min_res is not null),
    'por_regla', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('regla', regla, 'nivel', nivel, 'veces', n) order by n desc, regla)
                           from (select regla, nivel, count(*) as n from ev group by 1, 2 order by 3 desc, 1 limit 8) x), '[]'::jsonb),
    'lista_muy_criticas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'regla', ev.regla, 'detalle', ev.mensaje, 'desde', ev.fecha_inicio, 'minutos', pg_catalog.round(ev.min_res::numeric),
        'minutos_reconocer', pg_catalog.round(ev.min_rec::numeric), 'estado', ev.estado,
        'cierra', case when ev.cierre_automatico then 'Automático' else u.nombre end, 'comentario', ev.comentario) order by ev.fecha_inicio)
      from ev left join public.usuarios u on u.id = ev.id_usuario_cierra where ev.nivel = 'MUY_CRITICA'), '[]'::jsonb),
    'lista_avisos', coalesce((select pg_catalog.jsonb_agg(x.f order by x.d desc) from (
        select ev.fecha_inicio as d, pg_catalog.jsonb_build_object('regla', ev.regla, 'detalle', ev.mensaje, 'desde', ev.fecha_inicio,
                 'minutos', pg_catalog.round(ev.min_res::numeric)) as f from ev where ev.nivel = 'AVISO'
        union all
        select ic.fecha_inicio, pg_catalog.jsonb_build_object('regla', 'Sin comunicación', 'detalle', ic.sensor || ' · ' || ic.recinto,
                 'desde', ic.fecha_inicio, 'minutos', pg_catalog.round(extract(epoch from coalesce(ic.fecha_fin, v_fin) - ic.fecha_inicio) / 60))
        from ic order by 1 desc limit 30) x), '[]'::jsonb),
    'abiertas_al_final', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'regla', ra.nombre, 'nivel', n.codigo, 'desde', ea.fecha_inicio, 'detalle', ea.mensaje) order by n.prioridad desc, ea.fecha_inicio)
      from public.eventos_alarma ea
      join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
      join public.niveles_alarma n on n.id = ra.id_nivel_alarma
      where ea.fecha_inicio < v_fin and (ea.fecha_cierre is null or ea.fecha_cierre >= v_fin)), '[]'::jsonb))
  into v_alarmas;

  -- Comunicación: horas con datos de cada sensor activo
  with s as (
    select s.id, s.nombre, rc.nombre as recinto,
      (select count(distinct pg_catalog.date_trunc('hour', l.fecha_hora)) from public.lecturas l
       where l.id_sensor = s.id and l.fecha_hora >= greatest(v_ini, s.fecha_alta::timestamp at time zone e.zona_horaria) and l.fecha_hora < v_fin) as horas,
      greatest(1, extract(epoch from v_fin - greatest(v_ini, s.fecha_alta::timestamp at time zone e.zona_horaria)) / 3600) as esperadas
    from public.sensores s
    join public.recintos rc on rc.id = s.id_recinto
    join public.plantas pl on pl.id = rc.id_planta and pl.id_edificio = p_id_edificio
    where s.activo and s.fecha_alta <= p_hasta
  )
  select pg_catalog.jsonb_build_object(
    'sensores', count(*),
    'pct_datos', case when count(*) > 0 then pg_catalog.round(avg(least(100, horas / esperadas * 100))::numeric, 1) end,
    'con_huecos', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('sensor', nombre, 'recinto', recinto,
        'pct', pg_catalog.round(least(100, horas / esperadas * 100)::numeric, 0)) order by horas / esperadas)
      filter (where horas / esperadas < 0.95), '[]'::jsonb))
  into v_comunicacion
  from s;

  return pg_catalog.jsonb_build_object(
    'tipo', p_tipo, 'desde', p_desde, 'hasta', p_hasta,
    'edificio', pg_catalog.jsonb_build_object('id', e.id, 'nombre', e.nombre, 'codigo', e.codigo, 'municipio', e.municipio,
                                             'zona_horaria', e.zona_horaria, 'superficie_m2', e.superficie_util_m2),
    'marca', pg_catalog.jsonb_build_object('partner', v_partner,
      'plataforma', (select valor_texto from public.parametros_saas where codigo = 'NOMBRE_PLATAFORMA' and activo limit 1)),
    'energia', v_energia, 'diario', coalesce(v_diario, '[]'::jsonb), 'horario', v_horario,
    'ambiente', v_ambiente, 'alarmas', v_alarmas, 'comunicacion', v_comunicacion);
end;
$$;
revoke all on function private.calcular_informe(uuid, text, date, date) from public, anon, authenticated;

-- Periodo cerrado anterior a una fecha: semana de lunes a domingo o mes natural
create or replace function private.periodo_informe(p_tipo text, p_fecha date, out desde date, out hasta date)
language sql
immutable
set search_path = ''
as $$
  select case p_tipo when 'SEMANAL' then (pg_catalog.date_trunc('week', p_fecha) - interval '7 days')::date
                     else (pg_catalog.date_trunc('month', p_fecha) - interval '1 month')::date end,
         case p_tipo when 'SEMANAL' then (pg_catalog.date_trunc('week', p_fecha) - interval '1 day')::date
                     else (pg_catalog.date_trunc('month', p_fecha) - interval '1 day')::date end;
$$;

create or replace function private.guardar_informe(p_id_edificio uuid, p_tipo text, p_desde date, p_hasta date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.informes (id_edificio, tipo, desde, hasta, datos)
  values (p_id_edificio, p_tipo, p_desde, p_hasta, private.calcular_informe(p_id_edificio, p_tipo, p_desde, p_hasta))
  on conflict (id_edificio, tipo, desde) do update set datos = excluded.datos, hasta = excluded.hasta, generado_en = pg_catalog.now()
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.guardar_informe(uuid, text, date, date) from public, anon, authenticated;

-- El Partner puede generar (o volver a generar) el informe de la última semana o mes cerrados
create or replace function public.generar_informe(p_id_edificio uuid, p_tipo text, p_fecha date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p record;
  v_zona text;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_EDIFICIO') then
    raise exception 'Sin permiso para generar informes de este edificio' using errcode = '42501';
  end if;
  if p_tipo not in ('SEMANAL', 'MENSUAL') then
    raise exception 'Tipo de informe no válido' using errcode = '22023';
  end if;
  select zona_horaria into v_zona from public.edificios where id = p_id_edificio;
  select * into v_p from private.periodo_informe(p_tipo, coalesce(p_fecha, (pg_catalog.now() at time zone v_zona)::date));
  return private.guardar_informe(p_id_edificio, p_tipo, v_p.desde, v_p.hasta);
end;
$$;
revoke all on function public.generar_informe(uuid, text, date) from public, anon;
grant execute on function public.generar_informe(uuid, text, date) to authenticated;

-- 5. Cada mañana (pg_cron): los lunes el semanal y el día 1 el mensual, y su email a los destinatarios
create or replace function private.encolar_email_informe(p_id_informe uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  insert into public.notificaciones (tipo, canal, id_usuario, destinatario, motivo, mensaje, datos)
  select 'INFORME', 'EMAIL', u.id, u.email, 'INFORME_' || i.tipo,
         case i.tipo when 'SEMANAL' then 'Informe semanal' else 'Informe mensual' end || ' · ' || e.nombre,
         pg_catalog.jsonb_build_object('id_informe', i.id, 'id_edificio', e.id, 'edificio', e.nombre, 'tipo', i.tipo,
           'desde', i.desde, 'hasta', i.hasta, 'energia', i.datos->'energia', 'alarmas', ((i.datos->'alarmas') - 'lista_avisos' - 'lista_muy_criticas'), 'horario', i.datos->'horario', 'marca', i.datos->'marca')
  from public.informes i
  join public.edificios e on e.id = i.id_edificio
  join public.informes_destinatarios d on d.id_edificio = i.id_edificio
       and ((i.tipo = 'SEMANAL' and d.semanal) or (i.tipo = 'MENSUAL' and d.mensual))
  join public.usuarios u on u.id = d.id_usuario and u.activo
  where i.id = p_id_informe and private.usuario_alcanza_edificio(u.id, e.id)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function private.encolar_email_informe(uuid) from public, anon, authenticated;

create or replace function public.preparar_informes(p_fecha date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  v_hoy date;
  v_p record;
  v_id uuid;
  v_inf integer := 0;
  v_emails integer := 0;
  t text;
begin
  for e in select id, zona_horaria from public.edificios where activo loop
    v_hoy := coalesce(p_fecha, (pg_catalog.now() at time zone e.zona_horaria)::date);
    foreach t in array array['SEMANAL', 'MENSUAL'] loop
      continue when t = 'SEMANAL' and extract(isodow from v_hoy) <> 1;
      continue when t = 'MENSUAL' and extract(day from v_hoy) <> 1;
      select * into v_p from private.periodo_informe(t, v_hoy);
      continue when exists (select 1 from public.informes where id_edificio = e.id and tipo = t and desde = v_p.desde);
      continue when not exists (select 1 from public.resumenes_diarios where id_edificio = e.id and fecha between v_p.desde and v_p.hasta);
      begin
        v_id := private.guardar_informe(e.id, t, v_p.desde, v_p.hasta);
        v_emails := v_emails + private.encolar_email_informe(v_id);
        v_inf := v_inf + 1;
      exception when others then
        raise warning 'Informe % del edificio %: %', t, e.id, sqlerrm;   -- un edificio con problemas no para el resto
      end;
    end loop;
  end loop;
  if v_emails > 0 then perform private.llamar_api_avisos(); end if;
  return pg_catalog.jsonb_build_object('informes', v_inf, 'emails', v_emails);
end;
$$;
revoke all on function public.preparar_informes(date) from public, anon, authenticated;
grant execute on function public.preparar_informes(date) to service_role;

-- Reenviar a los destinatarios un informe ya generado (Partner)
create or replace function public.enviar_informe(p_id_informe uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_n integer;
begin
  select id_edificio into v_edificio from public.informes where id = p_id_informe;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'MODIFICAR_EDIFICIO') then
    raise exception 'Informe inexistente o sin permiso' using errcode = '42501';
  end if;
  delete from public.notificaciones where motivo in ('INFORME_SEMANAL', 'INFORME_MENSUAL')
    and datos->>'id_informe' = p_id_informe::text and estado in ('ENVIADA', 'ERROR');
  v_n := private.encolar_email_informe(p_id_informe);
  if v_n > 0 then perform private.llamar_api_avisos(); end if;
  return v_n;
end;
$$;
revoke all on function public.enviar_informe(uuid) from public, anon;
grant execute on function public.enviar_informe(uuid) to authenticated;

-- 6. Destinatarios (Partner)
create or replace function public.destinatarios_informes(p_id_edificio uuid)
returns table (id uuid, nombre text, email text, rol text, semanal boolean, mensual boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_EDIFICIO') then
    raise exception 'Sin permiso para configurar los informes de este edificio' using errcode = '42501';
  end if;
  return query
  select u.id, pg_catalog.concat_ws(' ', u.nombre, u.apellidos)::text, u.email::text, r.nombre::text,
         coalesce(d.semanal, false), coalesce(d.mensual, false)
  from public.usuarios u join public.roles r on r.id = u.id_rol
  left join public.informes_destinatarios d on d.id_edificio = p_id_edificio and d.id_usuario = u.id
  where u.activo and private.usuario_alcanza_edificio(u.id, p_id_edificio) and r.codigo <> 'ADMIN_SAAS'
  order by private.tipo_rol(r.codigo) desc, u.nombre;
end;
$$;
revoke all on function public.destinatarios_informes(uuid) from public, anon;
grant execute on function public.destinatarios_informes(uuid) to authenticated;

create or replace function public.guardar_destinatarios_informes(p_id_edificio uuid, p_semanal uuid[], p_mensual uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_EDIFICIO') then
    raise exception 'Sin permiso para configurar los informes de este edificio' using errcode = '42501';
  end if;
  foreach u in array coalesce(p_semanal, '{}') || coalesce(p_mensual, '{}') loop
    if not private.usuario_alcanza_edificio(u, p_id_edificio) then
      raise exception 'Un destinatario no tiene acceso a este edificio' using errcode = '22023';
    end if;
  end loop;
  delete from public.informes_destinatarios where id_edificio = p_id_edificio;
  insert into public.informes_destinatarios (id_edificio, id_usuario, semanal, mensual)
  select p_id_edificio, x, x = any (coalesce(p_semanal, '{}')), x = any (coalesce(p_mensual, '{}'))
  from (select distinct pg_catalog.unnest(coalesce(p_semanal, '{}') || coalesce(p_mensual, '{}')) as x) y;
end;
$$;
revoke all on function public.guardar_destinatarios_informes(uuid, uuid[], uuid[]) from public, anon;
grant execute on function public.guardar_destinatarios_informes(uuid, uuid[], uuid[]) to authenticated;

-- 7. Programación: cada mañana a las 5:30 UTC (6:30 / 7:30 en España), después del motor de la noche
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'informes_diario';
  perform cron.schedule('informes_diario', '30 5 * * *', 'select public.preparar_informes()');
exception when others then
  raise notice 'pg_cron no disponible: programe preparar_informes() desde la API';
end;
$$;

commit;
