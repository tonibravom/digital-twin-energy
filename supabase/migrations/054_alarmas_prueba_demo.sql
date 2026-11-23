-- =========================================================
-- 054 · Alarmas: lecturas poco frecuentes, ir a la alarma y averías simuladas en la demo (D59)
--  1. ventana_sensor: el valor que había al empezar la ventana también cuenta (un dato cada
--     15 min con una regla de 5 min se decidía pocas veces y una alarma podía no resolverse).
--  2. alarmas_edificio: devuelve el recinto (id) para llevar el 3D a su planta.
--  3. Averías simuladas, SOLO en edificios DEMO-*: el simulador de la API envía durante unos
--     minutos los valores de una avería (sin tensión, presión alta…) por el camino normal
--     de las lecturas, para ver cómo se abre, avisa, escala, resuelve y cierra una alarma.
-- =========================================================
begin;

-- 1. Ventana con el valor vigente al inicio
create or replace function private.ventana_sensor(p_id_sensor uuid, p_minutos integer,
  out n integer, out minimo double precision, out maximo double precision, out media double precision)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_desde timestamptz;
  v_primera timestamptz;
  v_previa double precision;
begin
  if p_id_sensor is null then n := 0; return; end if;
  if coalesce(p_minutos, 0) <= 1 then
    select 1, l.valor, l.valor, l.valor into n, minimo, maximo, media
    from public.lecturas l where l.id_sensor = p_id_sensor and l.fecha_hora > pg_catalog.now() - interval '30 minutes'
      and l.fecha_hora <= pg_catalog.now()
    order by l.fecha_hora desc limit 1;
    n := coalesce(n, 0);
    return;
  end if;
  v_desde := pg_catalog.now() - pg_catalog.make_interval(mins => p_minutos);
  -- Valor vigente al empezar la ventana: la última lectura anterior (como mucho 30 min antes)
  select l.valor into v_previa from public.lecturas l
  where l.id_sensor = p_id_sensor and l.fecha_hora <= v_desde and l.fecha_hora > v_desde - interval '30 minutes'
  order by l.fecha_hora desc limit 1;
  select count(*), min(l.valor), max(l.valor), avg(l.valor), min(l.fecha_hora)
    into n, minimo, maximo, media, v_primera
  from public.lecturas l where l.id_sensor = p_id_sensor and l.fecha_hora > v_desde and l.fecha_hora <= pg_catalog.now();
  if v_previa is not null then
    minimo := least(coalesce(minimo, v_previa), v_previa);
    maximo := greatest(coalesce(maximo, v_previa), v_previa);
    media := (coalesce(media, 0) * n + v_previa) / (n + 1);
    n := n + 1;
  elsif n > 0 and v_primera > v_desde + pg_catalog.make_interval(mins => greatest(p_minutos / 2, 1)) then
    n := 0;   -- ventana sin cubrir: no se decide
  end if;
end;
$$;
revoke all on function private.ventana_sensor(uuid, integer) from public, anon, authenticated;

-- 2. Alarmas del edificio con el recinto (para ir a su planta en el 3D)
create or replace function public.alarmas_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(x.fila order by x.orden, x.prioridad desc, x.desde desc), '[]'::jsonb)
  from (
    select case ea.estado when 'ACTIVA' then 0 when 'RECONOCIDA' then 1 else 2 end as orden, n.prioridad, ea.fecha_inicio as desde,
           pg_catalog.jsonb_build_object(
             'tipo', 'ALARMA', 'id', ea.id, 'nivel', n.codigo, 'nivel_nombre', n.nombre, 'prioridad', n.prioridad,
             'titulo', ra.nombre, 'detalle', ea.mensaje, 'estado', ea.estado, 'desde', ea.fecha_inicio,
             'ultima_deteccion', ea.ultima_deteccion, 'resuelta', ea.fecha_resuelta,
             'valor', ea.valor_detectado, 'id_sensor', coalesce(ea.id_sensor, ra.id_sensor),
             'sensor', s.nombre, 'id_recinto', r.id, 'recinto', r.nombre, 'planta', pl.nombre, 'comentario', ea.comentario,
             'reconocida', ea.fecha_reconocimiento, 'reconoce', ur.nombre,
             'silenciada_hasta', case when ea.silenciada_hasta > pg_catalog.now() then ea.silenciada_hasta end,
             'motivo_silencio', ea.motivo_silencio, 'rearme', ra.tipo_rearme, 'reaperturas', ea.reaperturas,
             'se_puede_cerrar', ea.estado = 'RESUELTA') as fila
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    left join public.sensores s on s.id = coalesce(ea.id_sensor, ra.id_sensor)
    left join public.recintos r on r.id = coalesce(ea.id_recinto, s.id_recinto)
    left join public.plantas pl on pl.id = r.id_planta
    left join public.usuarios ur on ur.id = ea.id_usuario_reconoce
    where ea.estado in ('ACTIVA', 'RECONOCIDA', 'RESUELTA')
    union all
    select 0, 2, ic.fecha_inicio,
           pg_catalog.jsonb_build_object(
             'tipo', 'COMUNICACION', 'id', ic.id, 'nivel', 'AVISO', 'nivel_nombre', 'Aviso', 'prioridad', 2,
             'titulo', 'Sin comunicación', 'detalle', 'No llegan lecturas de este sensor', 'estado', 'ACTIVA',
             'desde', ic.fecha_inicio, 'id_sensor', s.id, 'sensor', s.nombre, 'id_recinto', r.id, 'recinto', r.nombre,
             'planta', p.nombre)
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor and s.activo
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    where ic.estado = 'ABIERTA'
      and not exists (select 1 from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                      where ra.tipo_regla = 'SIN_COMUNICACION' and ea.id_sensor = s.id and ea.estado <> 'CERRADA')
  ) x;
$$;
revoke all on function public.alarmas_edificio(uuid) from public, anon;
grant execute on function public.alarmas_edificio(uuid) to authenticated, service_role;

-- 3. Averías simuladas (solo edificios DEMO-*)
create table if not exists public.averias_simuladas (
  id uuid primary key default gen_random_uuid(),
  id_edificio uuid not null references public.edificios(id),
  tipo text not null check (tipo in ('SIN_TENSION', 'FALLO_FASE', 'COS_PHI_BAJO', 'MAXIMETRO', 'SIN_GAS', 'PRESION_GAS_ALTA',
                                     'SIN_AGUA', 'PRESION_AGUA_ALTA', 'CO2_ALTO')),
  valor numeric,                                   -- valor que envía el simulador (si depende del edificio)
  inicio timestamptz not null default pg_catalog.now(),
  fin timestamptz not null,
  id_usuario uuid references public.usuarios(id),
  created_at timestamptz not null default pg_catalog.now(),
  constraint ck_averias_simuladas_fechas check (fin > inicio)
);
alter table public.averias_simuladas enable row level security;
create index if not exists ix_averias_simuladas_fin on public.averias_simuladas (fin);

drop policy if exists averias_simuladas_select on public.averias_simuladas;
create policy averias_simuladas_select on public.averias_simuladas
for select to authenticated
using (private.usuario_tiene_acceso_edificio(id_edificio) and private.usuario_tiene_permiso('VER_ALARMAS'));
-- Sin políticas de escritura: solo con simular_averia / terminar_averia

create or replace function public.tipos_averia_simulada()
returns table (tipo text, nombre text, que_hace text, regla text)
language sql
immutable
set search_path = ''
as $$
  select * from (values
    ('SIN_TENSION', 'Corte de suministro eléctrico', 'Las tres tensiones a 0 V y la potencia a 0', 'ELEC_SIN_SUMINISTRO'),
    ('FALLO_FASE', 'Fallo de una fase', 'La fase L2 baja a 118 V', 'ELEC_FALLO_FASE'),
    ('COS_PHI_BAJO', 'cos φ muy bajo', 'El factor de potencia baja a 0,72', 'ELEC_COS_PHI_MUY_BAJO'),
    ('MAXIMETRO', 'Potencia por encima de la contratada', 'La potencia sube al 115 % de la contratada en el periodo', 'ELEC_MAXIMETRO'),
    ('SIN_GAS', 'Sin presión de gas', 'La presión del gas baja al 30 % de la de operación', 'GAS_SIN_SUMINISTRO'),
    ('PRESION_GAS_ALTA', 'Presión de gas excesiva', 'La presión del gas sube al 145 % de la de operación', 'GAS_PRESION_EXCESIVA'),
    ('SIN_AGUA', 'Sin presión de agua', 'La presión del agua baja a 0,2 bar', 'AGUA_SIN_SUMINISTRO'),
    ('PRESION_AGUA_ALTA', 'Presión de agua excesiva', 'La presión del agua sube a 6,2 bar', 'AGUA_PRESION_EXCESIVA'),
    ('CO2_ALTO', 'CO₂ muy elevado', 'El CO₂ de las oficinas de la planta 5 sube a 1700 ppm', 'CO2_MUY_ELEVADO')
  ) x(tipo, nombre, que_hace, regla);
$$;

create or replace function public.simular_averia(p_id_edificio uuid, p_tipo text, p_minutos integer default 60)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_codigo text;
  v_valor numeric;
  v_id uuid;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Sin permiso para probar alarmas en este edificio' using errcode = '42501';
  end if;
  select codigo into v_codigo from public.edificios where id = p_id_edificio and activo;
  if v_codigo is null or v_codigo not like 'DEMO-%' then
    raise exception 'Las averías simuladas solo se pueden usar en edificios de demostración (DEMO-…)' using errcode = '22023';
  end if;
  if not exists (select 1 from public.tipos_averia_simulada() t where t.tipo = p_tipo) then
    raise exception 'Avería desconocida: %', p_tipo using errcode = '22023';
  end if;
  if p_minutos is null or p_minutos < 15 or p_minutos > 240 then
    raise exception 'La avería dura entre 15 y 240 minutos' using errcode = '22023';
  end if;
  if p_tipo = 'MAXIMETRO' then
    select max(private.potencia_contratada(su.id, pg_catalog.now())) * 1.15 into v_valor
    from public.suministros su where su.id_edificio = p_id_edificio and su.activo and su.tipo = 'ELECTRICIDAD';
    if v_valor is null then raise exception 'El suministro eléctrico no tiene potencias contratadas' using errcode = '22023'; end if;
  elsif p_tipo in ('SIN_GAS', 'PRESION_GAS_ALTA') then
    select max(g.presion_operacion) * case p_tipo when 'SIN_GAS' then 0.30 else 1.45 end into v_valor
    from public.suministros su join public.suministros_gas g on g.id_suministro = su.id
    where su.id_edificio = p_id_edificio and su.activo;
    if v_valor is null then raise exception 'El suministro de gas no tiene presión de operación' using errcode = '22023'; end if;
  end if;
  -- Una sola avería de cada tipo a la vez
  update public.averias_simuladas set fin = pg_catalog.now()
  where id_edificio = p_id_edificio and tipo = p_tipo and fin > pg_catalog.now();
  insert into public.averias_simuladas (id_edificio, tipo, valor, fin, id_usuario)
  values (p_id_edificio, p_tipo, pg_catalog.round(v_valor, 2), pg_catalog.now() + pg_catalog.make_interval(mins => p_minutos),
          private.usuario_actual())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.terminar_averia(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  select id_edificio into v_edificio from public.averias_simuladas where id = p_id;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Avería inexistente o sin permiso' using errcode = '42501';
  end if;
  update public.averias_simuladas set fin = greatest(inicio + interval '1 second', pg_catalog.now())
  where id = p_id and fin > pg_catalog.now();
end;
$$;

-- Para el simulador de la API: averías de los edificios DEMO de los dos últimos días
create or replace function public.averias_simuladas_activas()
returns table (tipo text, valor numeric, inicio timestamptz, fin timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select a.tipo, a.valor, a.inicio, a.fin
  from public.averias_simuladas a join public.edificios e on e.id = a.id_edificio and e.codigo like 'DEMO-%'
  where a.fin > pg_catalog.now() - interval '2 days'
  order by a.inicio;
$$;

revoke all on function public.tipos_averia_simulada() from public, anon;
revoke all on function public.simular_averia(uuid, text, integer) from public, anon;
revoke all on function public.terminar_averia(uuid) from public, anon;
revoke all on function public.averias_simuladas_activas() from public, anon, authenticated;
grant execute on function public.tipos_averia_simulada() to authenticated;
grant execute on function public.simular_averia(uuid, text, integer) to authenticated;
grant execute on function public.terminar_averia(uuid) to authenticated;
grant execute on function public.averias_simuladas_activas() to service_role;
grant select on public.averias_simuladas to authenticated;

commit;
