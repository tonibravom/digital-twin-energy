-- =========================================================
-- 053 · Motor de alarmas
-- Decisión D59 (23/11/2026).
--
--   · Tres niveles, que deciden cómo se avisa:
--       MUY_CRITICA → email inmediato (con escalado si nadie la reconoce);
--       CRITICA     → resumen diario por email;
--       AVISO       → informes semanal y mensual.
--     Todos se ven siempre en la plataforma (campana, pestaña Alarmas, 3D).
--     Las antiguas IMPORTANTE e INFORMATIVA dejan de usarse (pasan a CRITICA y AVISO).
--   · Reglas libres (umbral sobre un sensor, ya existían) y reglas de la
--     plataforma (catálogo tipos_regla_alarma). Todas las activa el Partner,
--     de acuerdo con el cliente, y él decide el nivel de cada una.
--   · Ciclo de vida: ACTIVA (causa presente, sin atender) → RECONOCIDA
--     (alguien se encarga; la causa sigue) → RESUELTA (la causa ha
--     desaparecido; espera cierre manual) → CERRADA. Mientras la causa siga,
--     nadie la puede cerrar. Con rearme automático se cierra sola al
--     resolverse. Si la causa vuelve en menos de 60 min, se reabre la misma.
--     Silenciar con caducidad (obras, mantenimiento): sin avisos hasta la
--     fecha; si sigue al caducar, vuelve a avisar.
--   · motor_alarmas() (pg_cron cada 5 min) evalúa las reglas con las
--     últimas lecturas, abre, actualiza, resuelve y cierra eventos, y deja
--     los emails en notificaciones (la API los envía; las MUY_CRITICA, al
--     momento). preparar_resumen_diario() prepara el resumen de las críticas.
-- =========================================================
begin;

-- 1. Niveles
alter table public.niveles_alarma add column if not exists envio varchar(20) not null default 'INFORMES';
alter table public.niveles_alarma drop constraint if exists niveles_alarma_envio_ck;
alter table public.niveles_alarma add constraint niveles_alarma_envio_ck check (envio in ('INMEDIATO', 'RESUMEN_DIARIO', 'INFORMES'));
comment on column public.niveles_alarma.envio is
  'INMEDIATO: email al momento (MUY_CRITICA). RESUMEN_DIARIO: email diario (CRITICA). INFORMES: informes semanal y mensual (AVISO).';

insert into public.niveles_alarma (codigo, nombre, prioridad, envia_email, envio)
values ('MUY_CRITICA', 'Muy crítica', 5, true, 'INMEDIATO')
on conflict (codigo) do update set nombre = excluded.nombre, envia_email = true, envio = 'INMEDIATO', activo = true;
update public.niveles_alarma set nombre = 'Crítica', envia_email = true, envio = 'RESUMEN_DIARIO', activo = true where codigo = 'CRITICA';
update public.niveles_alarma set nombre = 'Aviso', envia_email = false, envio = 'INFORMES', activo = true where codigo = 'AVISO';
update public.reglas_alarma set id_nivel_alarma = (select id from public.niveles_alarma where codigo = 'CRITICA')
 where id_nivel_alarma = (select id from public.niveles_alarma where codigo = 'IMPORTANTE');
update public.reglas_alarma set id_nivel_alarma = (select id from public.niveles_alarma where codigo = 'AVISO')
 where id_nivel_alarma = (select id from public.niveles_alarma where codigo = 'INFORMATIVA');
update public.niveles_alarma set activo = false, envia_email = false where codigo in ('IMPORTANTE', 'INFORMATIVA');

-- 2. Catálogo de reglas de la plataforma
create table if not exists public.tipos_regla_alarma (
  id smallint generated always as identity primary key,
  codigo varchar(40) not null unique,
  nombre varchar(150) not null,
  descripcion text not null,
  categoria varchar(20) not null,
  tipo_suministro varchar(20),
  nivel_recomendado varchar(30) not null,
  rearme_recomendado varchar(20) not null default 'AUTOMATICO',
  parametros jsonb not null default '{}',
  requiere text[] not null default '{}',
  orden smallint not null default 0,
  activo boolean not null default true,
  constraint tipos_regla_alarma_categoria_ck check (categoria in ('ELECTRICIDAD', 'AGUA', 'GAS', 'PRODUCCION', 'AMBIENTE', 'CONSUMO', 'COMUNICACION')),
  constraint tipos_regla_alarma_suministro_ck check (tipo_suministro is null or tipo_suministro in ('ELECTRICIDAD', 'GAS', 'AGUA', 'FOTOVOLTAICA', 'SOLAR_TERMICA', 'CONSUMO')),
  constraint tipos_regla_alarma_nivel_ck check (nivel_recomendado in ('MUY_CRITICA', 'CRITICA', 'AVISO')),
  constraint tipos_regla_alarma_rearme_ck check (rearme_recomendado in ('AUTOMATICO', 'MANUAL'))
);
alter table public.tipos_regla_alarma enable row level security;
drop policy if exists tipos_regla_alarma_select on public.tipos_regla_alarma;
create policy tipos_regla_alarma_select on public.tipos_regla_alarma for select to authenticated using (true);
revoke all on public.tipos_regla_alarma from anon;
grant select on public.tipos_regla_alarma to authenticated;

comment on table public.tipos_regla_alarma is
  'Reglas de alarma de la plataforma (D59). tipo_suministro: a qué suministro o instalación se aplican (CONSUMO = electricidad, gas o agua). requiere: parámetros del medidor o datos de la ficha sin los que no se pueden activar. parametros: umbrales recomendados (el Partner los ajusta).';

insert into public.tipos_regla_alarma (codigo, nombre, descripcion, categoria, tipo_suministro, nivel_recomendado, rearme_recomendado, parametros, requiere, orden) values
  ('ELEC_SIN_SUMINISTRO', 'Sin suministro eléctrico', 'Las tres tensiones del medidor general caen a cero.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'MUY_CRITICA', 'MANUAL', '{"umbral_v": 20, "duracion": 1}', '{TENSION_L1,TENSION_L2,TENSION_L3}', 1),
  ('ELEC_POSIBLE_CORTE', 'Posible corte de suministro eléctrico', 'El medidor general y buena parte de los equipos del edificio dejan de comunicar a la vez (si se va la luz, el medidor no llega a enviar «tensión 0»).',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'MUY_CRITICA', 'MANUAL', '{"pct_equipos": 50}', '{}', 2),
  ('ELEC_FALLO_FASE', 'Fallo de una fase', 'Una fase cae por debajo del % de la tensión nominal mientras las otras siguen bien.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'MUY_CRITICA', 'MANUAL', '{"umbral_pct": 80, "tension_nominal": 230, "duracion": 1}', '{TENSION_L1,TENSION_L2,TENSION_L3}', 3),
  ('ELEC_COS_PHI_MUY_BAJO', 'cos φ muy bajo', 'Factor de potencia por debajo del umbral de forma sostenida.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'MUY_CRITICA', 'MANUAL', '{"umbral": 0.80, "duracion": 15}', '{FACTOR_POTENCIA}', 4),
  ('ELEC_MAXIMETRO', 'Potencia por encima de la contratada', 'La potencia media del cuarto de hora supera el % de la potencia contratada del periodo horario (P1–P6) en curso.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'MUY_CRITICA', 'MANUAL', '{"umbral_pct": 100, "duracion": 15}', '{POTENCIA_ACTIVA,FICHA_POTENCIAS}', 5),
  ('ELEC_MAXIMETRO_PREAVISO', 'Potencia cerca de la contratada', 'Aviso previo: la potencia media del cuarto de hora supera el % de la contratada del periodo en curso.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'CRITICA', 'AUTOMATICO', '{"umbral_pct": 90, "duracion": 15}', '{POTENCIA_ACTIVA,FICHA_POTENCIAS}', 6),
  ('ELEC_COS_PHI_BAJO', 'cos φ bajo (recargo por reactiva)', 'Factor de potencia por debajo de 0,95 de forma sostenida: la compañía factura la energía reactiva.',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'CRITICA', 'AUTOMATICO', '{"umbral": 0.95, "duracion": 60}', '{FACTOR_POTENCIA}', 7),
  ('ELEC_FUERA_HORARIO', 'Consumo fuera de horario', 'Potencia por encima del umbral fuera del horario del edificio (luces o climatización encendidas de noche o en festivo).',
   'ELECTRICIDAD', 'ELECTRICIDAD', 'CRITICA', 'AUTOMATICO', '{"umbral_kw": null, "duracion": 30}', '{POTENCIA_ACTIVA,HORARIO}', 8),
  ('AGUA_SIN_SUMINISTRO', 'Sin suministro de agua', 'La presión del agua cae por debajo del umbral.',
   'AGUA', 'AGUA', 'MUY_CRITICA', 'MANUAL', '{"umbral_bar": 0.5, "duracion": 5}', '{PRESION_AGUA}', 10),
  ('AGUA_PRESION_EXCESIVA', 'Presión de agua excesiva', 'La presión del agua supera el umbral (riesgo de roturas).',
   'AGUA', 'AGUA', 'MUY_CRITICA', 'MANUAL', '{"umbral_bar": 5, "duracion": 5}', '{PRESION_AGUA}', 11),
  ('AGUA_FUGA', 'Posible fuga de agua', 'Fuera del horario del edificio el caudal no baja nunca del umbral durante horas.',
   'AGUA', 'AGUA', 'CRITICA', 'MANUAL', '{"umbral_m3h": 0.02, "horas": 3}', '{CAUDAL_AGUA,HORARIO}', 12),
  ('GAS_SIN_SUMINISTRO', 'Sin suministro de gas', 'La presión del gas cae por debajo del % de la presión de operación de la ficha.',
   'GAS', 'GAS', 'MUY_CRITICA', 'MANUAL', '{"umbral_pct": 60, "duracion": 5}', '{PRESION_GAS,FICHA_PRESION}', 20),
  ('GAS_PRESION_EXCESIVA', 'Presión de gas excesiva', 'La presión del gas supera el % de la presión de operación de la ficha.',
   'GAS', 'GAS', 'MUY_CRITICA', 'MANUAL', '{"umbral_pct": 130, "duracion": 5}', '{PRESION_GAS,FICHA_PRESION}', 21),
  ('CONSUMO_ANOMALO', 'Consumo anómalo del día', 'Lo consumido hoy supera en un % lo del día comparable a la misma hora.',
   'CONSUMO', 'CONSUMO', 'CRITICA', 'AUTOMATICO', '{"umbral_pct": 30, "minimo_horas": 3}', '{CONSUMO}', 30),
  ('FV_BAJO_RENDIMIENTO', 'Fotovoltaica con bajo rendimiento', 'Con buena irradiancia, la potencia queda por debajo del % de la teórica (PR): suciedad, sombras o averías.',
   'PRODUCCION', 'FOTOVOLTAICA', 'CRITICA', 'AUTOMATICO', '{"umbral_pct": 70, "irradiancia_min": 300, "duracion": 60}', '{FV_POTENCIA,FV_IRRADIANCIA,FICHA_PICO}', 40),
  ('FV_INVERSOR_PARADO', 'Inversor fotovoltaico parado', 'Hay sol (irradiancia por encima del mínimo) y la fotovoltaica no produce.',
   'PRODUCCION', 'FOTOVOLTAICA', 'CRITICA', 'MANUAL', '{"irradiancia_min": 200, "duracion": 30}', '{FV_POTENCIA,FV_IRRADIANCIA,FICHA_PICO}', 41),
  ('ST_SIN_CIRCULACION', 'Solar térmica sin circular', 'Los captadores están mucho más calientes que el acumulador y el circuito no circula (bomba parada).',
   'PRODUCCION', 'SOLAR_TERMICA', 'CRITICA', 'MANUAL', '{"diferencia": 15, "duracion": 30}', '{ST_TEMPERATURA_CAPTADOR,ST_TEMPERATURA_ACUMULADOR,ST_CAUDAL}', 42),
  ('CONFORT_MUY_ALTO', 'Temperatura muy alejada de la eficiente', 'En horario de uso, un recinto está en el tramo «muy alto» de la escala de eficiencia (Ambiente).',
   'AMBIENTE', null, 'CRITICA', 'AUTOMATICO', '{"duracion": 60}', '{TEMPERATURA,HORARIO}', 50),
  ('CO2_MUY_ELEVADO', 'CO₂ muy elevado', 'En horario de uso, el CO₂ de un recinto supera el umbral (ventilación insuficiente).',
   'AMBIENTE', null, 'CRITICA', 'AUTOMATICO', '{"umbral_ppm": 1500, "duracion": 30}', '{CO2,HORARIO}', 51),
  ('CO2_ELEVADO', 'CO₂ elevado', 'En horario de uso, el CO₂ de un recinto supera el umbral.',
   'AMBIENTE', null, 'AVISO', 'AUTOMATICO', '{"umbral_ppm": 1000, "duracion": 30}', '{CO2,HORARIO}', 52),
  ('SIN_COMUNICACION', 'Equipo sin comunicar', 'Un sensor del edificio deja de enviar lecturas (umbral de cada sensor).',
   'COMUNICACION', null, 'AVISO', 'AUTOMATICO', '{}', '{}', 60)
on conflict (codigo) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, categoria = excluded.categoria,
  tipo_suministro = excluded.tipo_suministro, nivel_recomendado = excluded.nivel_recomendado,
  rearme_recomendado = excluded.rearme_recomendado, parametros = excluded.parametros, requiere = excluded.requiere, orden = excluded.orden;

-- 3. Reglas: las de la plataforma no llevan condición ni sensor propio
alter table public.reglas_alarma
  add column if not exists tipo_regla varchar(40) references public.tipos_regla_alarma(codigo),
  add column if not exists id_suministro uuid references public.suministros(id),
  add column if not exists parametros jsonb not null default '{}',
  add column if not exists escalado_minutos integer not null default 15;
alter table public.reglas_alarma alter column condicion drop not null;
alter table public.reglas_alarma drop constraint if exists reglas_alarma_fuente_ck;
alter table public.reglas_alarma add constraint reglas_alarma_fuente_ck check (
  (tipo_regla is null and num_nonnulls(id_sensor, id_magnitud_edificio) = 1 and condicion is not null)
  or (tipo_regla is not null and id_sensor is null and id_magnitud_edificio is null and condicion is null));
alter table public.reglas_alarma drop constraint if exists reglas_alarma_umbral_ck;
alter table public.reglas_alarma add constraint reglas_alarma_umbral_ck check (
  condicion is null
  or (condicion in ('MAYOR_QUE', 'MAYOR_IGUAL', 'MENOR_QUE', 'MENOR_IGUAL', 'IGUAL', 'DISTINTO')
      and umbral is not null and umbral_inferior is null and umbral_superior is null)
  or (condicion in ('ENTRE', 'FUERA_RANGO') and umbral is null and umbral_inferior is not null
      and umbral_superior is not null and umbral_inferior <= umbral_superior));
alter table public.reglas_alarma drop constraint if exists reglas_alarma_escalado_ck;
alter table public.reglas_alarma add constraint reglas_alarma_escalado_ck check (escalado_minutos between 5 and 1440);
create index if not exists ix_reglas_alarma_tipo on public.reglas_alarma (id_edificio, tipo_regla) where activa;
comment on column public.reglas_alarma.tipo_regla is 'Regla de la plataforma (tipos_regla_alarma); null = regla libre sobre un sensor o magnitud.';
comment on column public.reglas_alarma.escalado_minutos is 'MUY_CRITICA: si nadie la reconoce en estos minutos, se avisa a los destinatarios de escalado.';

alter table public.reglas_alarma_usuarios add column if not exists escalado boolean not null default false;
comment on column public.reglas_alarma_usuarios.escalado is 'false: destinatario principal. true: solo recibe la alarma si nadie la reconoce a tiempo (escalado).';

-- El suministro de la regla es del mismo edificio
create or replace function public.validar_regla_alarma_suministro()
returns trigger
language plpgsql
security definer   -- compara edificios aunque el usuario no vea uno de los dos; el permiso lo decide RLS
set search_path = ''
as $$
begin
  if new.id_suministro is not null
     and (select s.id_edificio from public.suministros s where s.id = new.id_suministro) is distinct from new.id_edificio then
    raise exception 'El suministro tiene que ser del mismo edificio que la regla' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke all on function public.validar_regla_alarma_suministro() from public, anon;
drop trigger if exists trg_reglas_alarma_suministro on public.reglas_alarma;
create trigger trg_reglas_alarma_suministro before insert or update of id_suministro, id_edificio on public.reglas_alarma
for each row execute function public.validar_regla_alarma_suministro();

-- 4. Eventos: resuelta, silenciada, cierre automático, escalado
alter table public.eventos_alarma
  add column if not exists fecha_resuelta timestamptz,
  add column if not exists cierre_automatico boolean not null default false,
  add column if not exists silenciada_hasta timestamptz,
  add column if not exists motivo_silencio text,
  add column if not exists id_usuario_silencia uuid,
  add column if not exists reaperturas integer not null default 0,
  add column if not exists escalada_en timestamptz;
alter table public.eventos_alarma drop constraint if exists eventos_alarma_estado_ck;
alter table public.eventos_alarma add constraint eventos_alarma_estado_ck check (estado in ('ACTIVA', 'RECONOCIDA', 'RESUELTA', 'CERRADA'));
alter table public.eventos_alarma drop constraint if exists eventos_alarma_cierre_ck;
alter table public.eventos_alarma add constraint eventos_alarma_cierre_ck check (
  (estado <> 'CERRADA' and fecha_cierre is null and id_usuario_cierra is null)
  or (estado = 'CERRADA' and fecha_cierre is not null and (id_usuario_cierra is not null or cierre_automatico)));
comment on column public.eventos_alarma.fecha_resuelta is 'Cuándo desapareció la causa (el motor). Con rearme manual, la alarma queda RESUELTA hasta que un usuario la cierra.';
comment on column public.eventos_alarma.silenciada_hasta is 'Sin avisos hasta esta fecha (obras, mantenimiento); la alarma sigue visible.';

-- Un evento abierto por regla, recinto y sensor
drop index if exists public.ux_eventos_alarma_abierto;
create unique index if not exists ux_eventos_alarma_abierto on public.eventos_alarma (
  id_regla_alarma, coalesce(id_recinto, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(id_sensor, '00000000-0000-0000-0000-000000000000'::uuid))
  where estado <> 'CERRADA';

-- 5. Notificaciones: motivo y contenido estructurado (la API compone el email)
alter table public.notificaciones
  add column if not exists motivo varchar(20),
  add column if not exists datos jsonb;
alter table public.notificaciones drop constraint if exists notificaciones_motivo_ck;
alter table public.notificaciones add constraint notificaciones_motivo_ck
  check (motivo is null or motivo in ('INMEDIATO', 'ESCALADO', 'REAVISO', 'RESUMEN_DIARIO'));
create unique index if not exists ux_notificaciones_resumen_diario
  on public.notificaciones (id_usuario, ((created_at at time zone 'UTC')::date))
  where motivo = 'RESUMEN_DIARIO';
create index if not exists ix_notificaciones_email_pendiente on public.notificaciones (created_at) where canal = 'EMAIL' and estado = 'PENDIENTE';

-- 6. Utilidades del motor
-- ¿Está el edificio en horario de uso en ese instante? (calendario del día o, si no hay, horario tipo)
create or replace function private.en_horario(p_id_edificio uuid, p_instante timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with l as (select (p_instante at time zone e.zona_horaria) as t from public.edificios e where e.id = p_id_edificio),
  dia as (
    select coalesce(c.laborable, h.laborable, false) as laborable,
           coalesce(c.hora_inicio, h.hora_inicio) as inicio, coalesce(c.hora_fin, h.hora_fin) as fin, l.t
    from l
    left join public.calendario_edificio c on c.id_edificio = p_id_edificio and c.fecha = l.t::date
    left join public.horarios_tipo_edificio h on h.id_edificio = p_id_edificio and h.dia_semana = extract(isodow from l.t)::smallint
  )
  select coalesce(private.cumple_filtro('EN_HORARIO', laborable, inicio, fin, t::time), false) from dia;
$$;

-- Sensor del medidor de un suministro que mide un parámetro
create or replace function private.sensor_de_parametro(p_id_suministro uuid, p_codigo text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id from public.suministros_dispositivos sd
  join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
  join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.codigo = p_codigo
  where sd.id_suministro = p_id_suministro and sd.activo and sd.medidor_general
  limit 1;
$$;

-- Lecturas de un sensor en los últimos minutos: n, mínimo, máximo y media. Con 0–1 min, la última
-- lectura (de la última media hora). Para «sostenido», la ventana tiene que estar cubierta: la
-- primera lectura no puede llegar más de la mitad de la ventana tarde.
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
begin
  if p_id_sensor is null then n := 0; return; end if;
  if coalesce(p_minutos, 0) <= 1 then
    select 1, l.valor, l.valor, l.valor into n, minimo, maximo, media
    from public.lecturas l where l.id_sensor = p_id_sensor and l.fecha_hora > pg_catalog.now() - interval '30 minutes'
    order by l.fecha_hora desc limit 1;
    n := coalesce(n, 0);
    return;
  end if;
  v_desde := pg_catalog.now() - pg_catalog.make_interval(mins => p_minutos);
  select count(*), min(l.valor), max(l.valor), avg(l.valor), min(l.fecha_hora)
    into n, minimo, maximo, media, v_primera
  from public.lecturas l where l.id_sensor = p_id_sensor and l.fecha_hora > v_desde and l.fecha_hora <= pg_catalog.now();
  if n > 0 and v_primera > v_desde + pg_catalog.make_interval(mins => greatest(p_minutos / 2, 1)) then
    n := 0;   -- ventana sin cubrir: no se decide
  end if;
end;
$$;

-- Periodo de potencia (P1–P6) de las tarifas de acceso (península). 3.0TD y 6.xTD: temporadas
-- alta (ene, feb, jul, dic), media alta (mar, nov), media (jun, ago, sep) y baja (abr, may, oct);
-- fines de semana, P6. 2.0TD: P1 (punta y llano, 8–24 h laborables) y P2 (valle).
-- Los festivos nacionales no se tienen en cuenta (se tratan como laborables).
create or replace function private.periodo_potencia(p_tarifa text, p_local timestamp)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_tarifa, '') ilike '2.0%' then
      case when extract(isodow from p_local) >= 6 or extract(hour from p_local) < 8 then 2 else 1 end
    when extract(isodow from p_local) >= 6 or extract(hour from p_local) < 8 then 6
    else (
      -- base de la temporada: alta 1, media alta 2, media 3, baja 4; horas punta = base, llano = base + 1
      (case when extract(month from p_local) in (1, 2, 7, 12) then 1
            when extract(month from p_local) in (3, 11) then 2
            when extract(month from p_local) in (6, 8, 9) then 3 else 4 end)
      + case when extract(hour from p_local) between 9 and 13 or extract(hour from p_local) between 18 and 21 then 0 else 1 end
    )::smallint
  end;
$$;

-- Potencia contratada (kW) del periodo en curso
create or replace function private.potencia_contratada(p_id_suministro uuid, p_instante timestamptz)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case private.periodo_potencia(se.tarifa, p_instante at time zone e.zona_horaria)
           when 1 then se.potencia_p1_kw when 2 then se.potencia_p2_kw when 3 then se.potencia_p3_kw
           when 4 then se.potencia_p4_kw when 5 then se.potencia_p5_kw else se.potencia_p6_kw end
  from public.suministros_electricidad se
  join public.suministros su on su.id = se.id_suministro
  join public.edificios e on e.id = su.id_edificio
  where se.id_suministro = p_id_suministro;
$$;

-- Requisitos de una regla de la plataforma que faltan (nombres legibles)
create or replace function public.requisitos_regla_alarma(p_id_edificio uuid, p_tipo text, p_id_suministro uuid default null)
returns text[]
language plpgsql
stable
security definer   -- solo comprueba existencias; quien llama ya ve el edificio (o es el motor)
set search_path = ''
as $$
declare
  v_tipo public.tipos_regla_alarma%rowtype;
  v_faltan text[] := '{}';
  r text;
begin
  select * into v_tipo from public.tipos_regla_alarma where codigo = p_tipo and activo;
  if not found then return array['Regla desconocida']; end if;
  if v_tipo.tipo_suministro is not null and p_id_suministro is null then
    return array['Elija el suministro o la instalación'];
  end if;
  foreach r in array v_tipo.requiere loop
    if r = 'FICHA_POTENCIAS' then
      if not exists (select 1 from public.suministros_electricidad where id_suministro = p_id_suministro
                     and coalesce(potencia_p1_kw, potencia_p2_kw, potencia_p3_kw, potencia_p4_kw, potencia_p5_kw, potencia_p6_kw) is not null) then
        v_faltan := pg_catalog.array_append(v_faltan, ('Potencias contratadas en la ficha')::text);
      end if;
    elsif r = 'FICHA_PRESION' then
      if not exists (select 1 from public.suministros_gas where id_suministro = p_id_suministro and presion_operacion is not null) then
        v_faltan := pg_catalog.array_append(v_faltan, ('Presión de operación en la ficha')::text);
      end if;
    elsif r = 'FICHA_PICO' then
      if not exists (select 1 from public.suministros_generacion where id_suministro = p_id_suministro and potencia_pico_kw > 0) then
        v_faltan := pg_catalog.array_append(v_faltan, ('Potencia pico en la ficha')::text);
      end if;
    elsif r = 'HORARIO' then
      if not exists (select 1 from public.horarios_tipo_edificio where id_edificio = p_id_edificio and laborable and hora_inicio is not null) then
        v_faltan := pg_catalog.array_append(v_faltan, ('Horario del edificio')::text);
      end if;
    elsif r in ('TEMPERATURA', 'CO2') then
      if not exists (select 1 from public.sensores s join public.familias_sensor f on f.id = s.id_familia and f.codigo = r
                     join public.recintos rc on rc.id = s.id_recinto and coalesce(rc.tipo, '') <> 'ZONA_EXTERIOR'
                     where s.activo and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio) then
        v_faltan := pg_catalog.array_append(v_faltan, (case r when 'CO2' then 'Sensores de CO₂' else 'Sensores de temperatura interior' end)::text);
      end if;
    elsif r = 'CONSUMO' then
      if not exists (select 1 from public.suministros_dispositivos sd
                     join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
                     join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.consumo
                     where sd.id_suministro = p_id_suministro and sd.activo and sd.medidor_general) then
        v_faltan := pg_catalog.array_append(v_faltan, ('Contador de consumo en el medidor general')::text);
      end if;
    elsif private.sensor_de_parametro(p_id_suministro, r) is null then
      v_faltan := pg_catalog.array_append(v_faltan, (coalesce((select nombre::text from public.parametros_medidor where codigo = r), r))::text);
    end if;
  end loop;
  return v_faltan;
end;
$$;

-- 7. Evaluación de una regla: una fila por elemento (sensor o recinto) con cumple = true (la
--    condición se da), false (no se da) o null (sin datos para decidir: no cambia nada)
create or replace function private.evaluar_regla_alarma(p_id_regla uuid)
returns table (id_sensor uuid, id_recinto uuid, cumple boolean, valor numeric, mensaje text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ra public.reglas_alarma%rowtype;
  p jsonb;
  dur integer;
  s1 uuid; s2 uuid; s3 uuid;
  w1 record; w2 record; w3 record;
  v_lim numeric;
  v_ref numeric;
  v_rec uuid;
  v_hoy record;
begin
  select * into ra from public.reglas_alarma where id = p_id_regla;
  p := coalesce((select t.parametros from public.tipos_regla_alarma t where t.codigo = ra.tipo_regla), '{}'::jsonb) || ra.parametros;
  dur := coalesce((p->>'duracion')::integer, ra.duracion_minutos, 0);

  -- Reglas libres: umbral sobre un sensor (o una magnitud) mantenido durante la duración
  if ra.tipo_regla is null then
    if ra.id_sensor is not null then
      w1 := private.ventana_sensor(ra.id_sensor, dur);
    else
      select count(*)::integer as n, min(v.valor) as minimo, max(v.valor) as maximo, avg(v.valor) as media into w1
      from public.valores_magnitud v where v.id_magnitud_edificio = ra.id_magnitud_edificio
        and v.fecha_hora > pg_catalog.now() - pg_catalog.make_interval(mins => greatest(dur, 30));
    end if;
    if w1.n = 0 then return; end if;
    return query select ra.id_sensor, (select s.id_recinto from public.sensores s where s.id = ra.id_sensor),
      case ra.condicion
        when 'MAYOR_QUE' then w1.minimo > ra.umbral when 'MAYOR_IGUAL' then w1.minimo >= ra.umbral
        when 'MENOR_QUE' then w1.maximo < ra.umbral when 'MENOR_IGUAL' then w1.maximo <= ra.umbral
        when 'IGUAL' then w1.minimo = ra.umbral and w1.maximo = ra.umbral
        when 'DISTINTO' then not (w1.minimo = ra.umbral and w1.maximo = ra.umbral)
        when 'ENTRE' then w1.minimo >= ra.umbral_inferior and w1.maximo <= ra.umbral_superior
        when 'FUERA_RANGO' then w1.minimo > ra.umbral_superior or w1.maximo < ra.umbral_inferior
      end, pg_catalog.round(w1.media::numeric, 3), null::text;
    return;
  end if;

  case ra.tipo_regla
  when 'ELEC_SIN_SUMINISTRO', 'ELEC_FALLO_FASE' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'TENSION_L1');
    s2 := private.sensor_de_parametro(ra.id_suministro, 'TENSION_L2');
    s3 := private.sensor_de_parametro(ra.id_suministro, 'TENSION_L3');
    w1 := private.ventana_sensor(s1, dur); w2 := private.ventana_sensor(s2, dur); w3 := private.ventana_sensor(s3, dur);
    if w1.n = 0 or w2.n = 0 or w3.n = 0 then return; end if;
    v_rec := (select s.id_recinto from public.sensores s where s.id = s1);
    if ra.tipo_regla = 'ELEC_SIN_SUMINISTRO' then
      v_lim := (p->>'umbral_v')::numeric;
      return query select s1, v_rec, greatest(w1.maximo, w2.maximo, w3.maximo) < v_lim,
        pg_catalog.round(greatest(w1.media, w2.media, w3.media)::numeric, 1), 'Las tres fases sin tensión'::text;
    else
      v_lim := (p->>'tension_nominal')::numeric * (p->>'umbral_pct')::numeric / 100;
      return query select s1, v_rec,
        (w1.maximo < v_lim or w2.maximo < v_lim or w3.maximo < v_lim)
          and (w1.minimo >= v_lim or w2.minimo >= v_lim or w3.minimo >= v_lim),
        pg_catalog.round(least(w1.media, w2.media, w3.media)::numeric, 1),
        'Tensión baja en ' || pg_catalog.concat_ws(', ', case when w1.maximo < v_lim then 'L1' end,
          case when w2.maximo < v_lim then 'L2' end, case when w3.maximo < v_lim then 'L3' end);
    end if;

  when 'ELEC_COS_PHI_MUY_BAJO', 'ELEC_COS_PHI_BAJO' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'FACTOR_POTENCIA');
    w1 := private.ventana_sensor(s1, dur);
    if w1.n = 0 then return; end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      w1.maximo < (p->>'umbral')::numeric, pg_catalog.round(w1.media::numeric, 3),
      'cos φ medio ' || pg_catalog.round(w1.media::numeric, 3) || ' (umbral ' || (p->>'umbral') || ')';

  when 'ELEC_MAXIMETRO', 'ELEC_MAXIMETRO_PREAVISO' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'POTENCIA_ACTIVA');
    w1 := private.ventana_sensor(s1, greatest(dur, 15));
    v_ref := private.potencia_contratada(ra.id_suministro, pg_catalog.now());
    if w1.n = 0 or coalesce(v_ref, 0) <= 0 then return; end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      w1.media > v_ref * (p->>'umbral_pct')::numeric / 100, pg_catalog.round(w1.media::numeric, 1),
      'Potencia media del cuarto de hora ' || pg_catalog.round(w1.media::numeric, 1) || ' kW · contratada en el periodo P'
        || (select private.periodo_potencia(se.tarifa, pg_catalog.now() at time zone e.zona_horaria)
            from public.suministros_electricidad se join public.edificios e on e.id = ra.id_edificio where se.id_suministro = ra.id_suministro)
        || ': ' || pg_catalog.round(v_ref, 1) || ' kW';

  when 'ELEC_POSIBLE_CORTE' then
    -- El medidor general sin comunicar y, a la vez, el % de los demás sensores del edificio
    return query
    with med as (
      select s.id, s.id_recinto, coalesce(ec.estado, 'SIN_DATOS') as estado
      from public.suministros_dispositivos sd
      join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
      left join public.estado_comunicacion ec on ec.id_sensor = s.id
      where sd.id_suministro = ra.id_suministro and sd.activo and sd.medidor_general
    ),
    resto as (
      select count(*) as total, count(*) filter (where ec.estado = 'SIN_COMUNICACION') as caidos
      from public.sensores s left join public.estado_comunicacion ec on ec.id_sensor = s.id
      where s.activo and public.obtener_edificio_recinto(s.id_recinto) = ra.id_edificio and s.id not in (select med.id from med)
    )
    select (select min(med.id::text)::uuid from med), (select min(med.id_recinto::text)::uuid from med),
      (select bool_and(med.estado = 'SIN_COMUNICACION') from med) and resto.total >= 2
        and resto.caidos * 100 >= resto.total * (p->>'pct_equipos')::numeric,
      resto.caidos::numeric, resto.caidos || ' de ' || resto.total || ' equipos sin comunicar, también el medidor general'
    from resto where exists (select 1 from med);

  when 'ELEC_FUERA_HORARIO' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'POTENCIA_ACTIVA');
    if (p->>'umbral_kw') is null then return; end if;
    if private.en_horario(ra.id_edificio, pg_catalog.now()) then
      return query select s1, (select s.id_recinto from public.sensores s where s.id = s1), false, null::numeric, null::text;
      return;
    end if;
    if private.en_horario(ra.id_edificio, pg_catalog.now() - pg_catalog.make_interval(mins => dur)) then return; end if;
    w1 := private.ventana_sensor(s1, dur);
    if w1.n = 0 then return; end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      w1.minimo > (p->>'umbral_kw')::numeric, pg_catalog.round(w1.media::numeric, 1),
      'Fuera de horario: ' || pg_catalog.round(w1.media::numeric, 1) || ' kW de media (umbral ' || (p->>'umbral_kw') || ' kW)';

  when 'AGUA_SIN_SUMINISTRO', 'AGUA_PRESION_EXCESIVA', 'GAS_SIN_SUMINISTRO', 'GAS_PRESION_EXCESIVA' then
    s1 := private.sensor_de_parametro(ra.id_suministro, case when ra.tipo_regla like 'AGUA%' then 'PRESION_AGUA' else 'PRESION_GAS' end);
    w1 := private.ventana_sensor(s1, dur);
    if w1.n = 0 then return; end if;
    if ra.tipo_regla like 'AGUA%' then
      v_lim := (p->>'umbral_bar')::numeric;
    else
      v_lim := (select g.presion_operacion from public.suministros_gas g where g.id_suministro = ra.id_suministro) * (p->>'umbral_pct')::numeric / 100;
      if v_lim is null then return; end if;
    end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      case when ra.tipo_regla like '%SIN_SUMINISTRO' then w1.maximo < v_lim else w1.minimo > v_lim end,
      pg_catalog.round(w1.media::numeric, 3),
      'Presión ' || pg_catalog.round(w1.media::numeric, 2) || ' (umbral ' || pg_catalog.round(v_lim, 2) || ')';

  when 'AGUA_FUGA' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'CAUDAL_AGUA');
    dur := ((p->>'horas')::numeric * 60)::integer;
    -- Solo se decide con toda la ventana fuera de horario; en horario no cambia nada
    if private.en_horario(ra.id_edificio, pg_catalog.now())
       or private.en_horario(ra.id_edificio, pg_catalog.now() - pg_catalog.make_interval(mins => dur))
       or private.en_horario(ra.id_edificio, pg_catalog.now() - pg_catalog.make_interval(mins => dur / 2)) then return; end if;
    w1 := private.ventana_sensor(s1, dur);
    if w1.n = 0 then return; end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      w1.minimo > (p->>'umbral_m3h')::numeric, pg_catalog.round(w1.minimo::numeric, 3),
      'Fuera de horario el caudal no ha bajado de ' || pg_catalog.round(w1.minimo::numeric, 3) || ' m³/h en ' || (p->>'horas') || ' h';

  when 'CONSUMO_ANOMALO' then
    select s.id, s.id_recinto, vh.valor_hoy, vh.valor_comparable into v_hoy
    from public.suministros_dispositivos sd
    join public.sensores s on s.id_dispositivo = sd.id_dispositivo and s.activo
    join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.consumo
    left join private.valores_hoy_edificio(ra.id_edificio) vh on vh.id_sensor = s.id
    where sd.id_suministro = ra.id_suministro and sd.activo and sd.medidor_general
    limit 1;
    if v_hoy.id is null or v_hoy.valor_hoy is null or coalesce(v_hoy.valor_comparable, 0) <= 0
       or (select extract(epoch from (pg_catalog.now() at time zone e.zona_horaria) - (pg_catalog.now() at time zone e.zona_horaria)::date) / 3600
           from public.edificios e where e.id = ra.id_edificio) < (p->>'minimo_horas')::numeric then return; end if;
    return query select v_hoy.id, v_hoy.id_recinto,
      v_hoy.valor_hoy > v_hoy.valor_comparable * (1 + (p->>'umbral_pct')::numeric / 100),
      pg_catalog.round(v_hoy.valor_hoy::numeric, 1),
      'Hoy ' || pg_catalog.round(v_hoy.valor_hoy::numeric, 1) || ' frente a ' || pg_catalog.round(v_hoy.valor_comparable::numeric, 1)
        || ' el día comparable a la misma hora (+' || pg_catalog.round(((v_hoy.valor_hoy / v_hoy.valor_comparable - 1) * 100)::numeric, 0) || ' %)';

  when 'FV_BAJO_RENDIMIENTO', 'FV_INVERSOR_PARADO' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'FV_POTENCIA');
    s2 := private.sensor_de_parametro(ra.id_suministro, 'FV_IRRADIANCIA');
    v_ref := (select g.potencia_pico_kw from public.suministros_generacion g where g.id_suministro = ra.id_suministro);
    w1 := private.ventana_sensor(s1, dur); w2 := private.ventana_sensor(s2, dur);
    if w1.n = 0 or w2.n = 0 or coalesce(v_ref, 0) <= 0 or w2.minimo < (p->>'irradiancia_min')::numeric then return; end if;
    if ra.tipo_regla = 'FV_BAJO_RENDIMIENTO' then
      return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
        w1.media / (v_ref * w2.media / 1000) * 100 < (p->>'umbral_pct')::numeric,
        pg_catalog.round((w1.media / (v_ref * w2.media / 1000) * 100)::numeric, 1),
        'Rendimiento (PR) ' || pg_catalog.round((w1.media / (v_ref * w2.media / 1000) * 100)::numeric, 0) || ' % con '
          || pg_catalog.round(w2.media::numeric, 0) || ' W/m²';
    else
      return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
        w1.maximo < v_ref * 0.01, pg_catalog.round(w1.maximo::numeric, 2),
        'Sin producción con ' || pg_catalog.round(w2.media::numeric, 0) || ' W/m² de irradiancia';
    end if;

  when 'ST_SIN_CIRCULACION' then
    s1 := private.sensor_de_parametro(ra.id_suministro, 'ST_TEMPERATURA_CAPTADOR');
    s2 := private.sensor_de_parametro(ra.id_suministro, 'ST_TEMPERATURA_ACUMULADOR');
    s3 := private.sensor_de_parametro(ra.id_suministro, 'ST_CAUDAL');
    w1 := private.ventana_sensor(s1, dur); w2 := private.ventana_sensor(s2, dur); w3 := private.ventana_sensor(s3, dur);
    if w1.n = 0 or w2.n = 0 or w3.n = 0 then return; end if;
    return query select s1, (select s.id_recinto from public.sensores s where s.id = s1),
      w1.minimo - w2.maximo > (p->>'diferencia')::numeric and w3.maximo <= 0,
      pg_catalog.round((w1.media - w2.media)::numeric, 1),
      'Captadores ' || pg_catalog.round(w1.media::numeric, 0) || ' °C, acumulador ' || pg_catalog.round(w2.media::numeric, 0) || ' °C y caudal 0';

  when 'CONFORT_MUY_ALTO', 'CO2_ELEVADO', 'CO2_MUY_ELEVADO' then
    -- Un elemento por sensor interior; fuera de horario la condición no se da
    return query
    with par as (
      select private.en_horario(ra.id_edificio, pg_catalog.now()) as horario,
             public.temporada_edificio(ra.id_edificio, (pg_catalog.now() at time zone e.zona_horaria)::date) as temporada,
             case public.temporada_edificio(ra.id_edificio, (pg_catalog.now() at time zone e.zona_horaria)::date)
               when 'INVIERNO' then e.temp_eficiencia_invierno when 'VERANO' then e.temp_eficiencia_verano end as te
      from public.edificios e where e.id = ra.id_edificio
    ),
    sens as (
      select s.id, s.id_recinto, rc.nombre as recinto, w.*
      from public.sensores s
      join public.familias_sensor f on f.id = s.id_familia
        and f.codigo = case when ra.tipo_regla = 'CONFORT_MUY_ALTO' then 'TEMPERATURA' else 'CO2' end
      join public.recintos rc on rc.id = s.id_recinto and coalesce(rc.tipo, '') <> 'ZONA_EXTERIOR'
      cross join lateral private.ventana_sensor(s.id, dur) w
      where s.activo and s.id_parametro_medidor is null and public.obtener_edificio_recinto(s.id_recinto) = ra.id_edificio
    )
    select sens.id, sens.id_recinto,
      case when not par.horario then false
           when ra.tipo_regla = 'CONFORT_MUY_ALTO' then public.estado_temperatura(sens.media::numeric, par.temporada, par.te) = 'MUY_ALTO'
           else sens.minimo > (p->>'umbral_ppm')::numeric end,
      pg_catalog.round(sens.media::numeric, 1),
      sens.recinto || ': ' || case when ra.tipo_regla = 'CONFORT_MUY_ALTO'
        then pg_catalog.round(sens.media::numeric, 1) || ' °C (temperatura eficiente ' || par.te || ' °C)'
        else pg_catalog.round(sens.media::numeric, 0) || ' ppm de CO₂' end
    from sens, par
    where sens.n > 0 or not par.horario;

  when 'SIN_COMUNICACION' then
    return query
    select s.id, s.id_recinto, ic.id is not null, null::numeric,
      case when ic.id is not null then 'Sin lecturas desde ' || pg_catalog.to_char(ic.fecha_inicio at time zone e.zona_horaria, 'DD/MM HH24:MI') end
    from public.sensores s
    join public.edificios e on e.id = ra.id_edificio
    left join public.incidencias_comunicacion ic on ic.id_sensor = s.id and ic.estado = 'ABIERTA'
    where s.activo and public.obtener_edificio_recinto(s.id_recinto) = ra.id_edificio;
  else
    return;
  end case;
end;
$$;
revoke all on function private.en_horario(uuid, timestamptz) from public, anon;
revoke all on function private.sensor_de_parametro(uuid, text) from public, anon, authenticated;
revoke all on function private.ventana_sensor(uuid, integer) from public, anon, authenticated;
revoke all on function private.potencia_contratada(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.evaluar_regla_alarma(uuid) from public, anon, authenticated;
revoke all on function public.requisitos_regla_alarma(uuid, text, uuid) from public, anon;
grant execute on function private.en_horario(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.requisitos_regla_alarma(uuid, text, uuid) to authenticated, service_role;
grant execute on function private.evaluar_regla_alarma(uuid) to service_role;

-- Las reglas de la plataforma no tienen sensor ni magnitud: el trigger de 008 solo valida las libres
create or replace function public.validar_regla_alarma_fuente()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  if new.id_sensor is null and new.id_magnitud_edificio is null and new.tipo_regla is not null then
    return new;   -- regla de la plataforma (su suministro lo valida validar_regla_alarma_suministro)
  end if;
  if new.id_sensor is not null then
    select p.id_edificio into v_edificio
    from public.sensores s
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta
    where s.id = new.id_sensor;
  else
    select me.id_edificio into v_edificio from public.magnitudes_edificio me where me.id = new.id_magnitud_edificio;
  end if;
  if v_edificio is null then
    raise exception 'El sensor o la magnitud de la regla no existe';
  end if;
  if v_edificio <> new.id_edificio then
    raise exception 'El sensor o la magnitud debe pertenecer al edificio de la regla';
  end if;
  return new;
end;
$$;

-- Eventos: en las reglas de la plataforma el sensor es el que ha disparado (del mismo edificio)
create or replace function public.validar_evento_alarma()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_regla public.reglas_alarma%rowtype;
begin
  select * into v_regla from public.reglas_alarma where id = new.id_regla_alarma;
  if not found then
    raise exception 'La regla del evento no existe';
  end if;
  if new.id_sensor is not null then
    if v_regla.tipo_regla is null and new.id_sensor is distinct from v_regla.id_sensor then
      raise exception 'El sensor del evento no coincide con el de la regla';
    end if;
    if v_regla.tipo_regla is not null and (select public.obtener_edificio_recinto(s.id_recinto) from public.sensores s
                                           where s.id = new.id_sensor) is distinct from v_regla.id_edificio then
      raise exception 'El sensor del evento no pertenece al edificio de la regla';
    end if;
  end if;
  if new.id_magnitud_edificio is not null and new.id_magnitud_edificio is distinct from v_regla.id_magnitud_edificio then
    raise exception 'La magnitud del evento no coincide con la de la regla';
  end if;
  if new.id_recinto is not null and public.obtener_edificio_recinto(new.id_recinto) is distinct from v_regla.id_edificio then
    raise exception 'El recinto del evento no pertenece al edificio de la regla';
  end if;
  return new;
end;
$$;

-- 8. Avisos por email (la API los envía; ver app/avisos.py)
create or replace function private.encolar_avisos_evento(p_id_evento uuid, p_motivo text, p_escalado boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  insert into public.notificaciones (id_evento_alarma, id_sensor, tipo, canal, id_usuario, destinatario, motivo, mensaje, datos)
  select ea.id, ea.id_sensor, 'ALARMA', 'EMAIL', u.id, u.email, p_motivo,
         n.nombre || ': ' || ra.nombre || ' · ' || e.nombre,
         pg_catalog.jsonb_build_object(
           'id_evento', ea.id, 'id_edificio', e.id, 'edificio', e.nombre, 'zona_horaria', e.zona_horaria,
           'regla', ra.nombre, 'nivel', n.codigo, 'nivel_nombre', n.nombre, 'mensaje', ea.mensaje,
           'valor', ea.valor_detectado, 'desde', ea.fecha_inicio, 'sensor', s.nombre, 'recinto', rc.nombre,
           'escalado', p_escalado)
  from public.eventos_alarma ea
  join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
  join public.niveles_alarma n on n.id = ra.id_nivel_alarma
  join public.edificios e on e.id = ra.id_edificio
  join public.reglas_alarma_usuarios rau on rau.id_regla_alarma = ra.id and rau.escalado = p_escalado
  join public.usuarios u on u.id = rau.id_usuario and u.activo
  left join public.sensores s on s.id = ea.id_sensor
  left join public.recintos rc on rc.id = coalesce(ea.id_recinto, s.id_recinto)
  where ea.id = p_id_evento
    and private.usuario_alcanza_edificio(u.id, e.id)
    and private.usuario_con_permiso(u.id, 'VER_ALARMAS');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Pide a la API que envíe ya los emails pendientes (POST <api>/v1/tareas/avisos, como el ciclo)
create or replace function private.llamar_api_avisos()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secreto text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'api_url';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'api_tareas_secreto';
  if v_url is null or v_secreto is null then
    return null;   -- sin secretos: los envía el ciclo de la API (cada 15 min)
  end if;
  return net.http_post(
    url := pg_catalog.rtrim(v_url, '/') || '/v1/tareas/avisos',
    headers := pg_catalog.jsonb_build_object('Authorization', 'Bearer ' || v_secreto, 'Content-Type', 'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000);
exception when others then
  return null;   -- sin pg_net o la API no responde: los envía el ciclo
end;
$$;

-- 9. Motor de alarmas (pg_cron cada 5 minutos)
create or replace function public.motor_alarmas()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ra record;
  d record;
  ev public.eventos_alarma%rowtype;
  v_inmediatos integer := 0;
  v_abiertas integer := 0;
  v_cerradas integer := 0;
  v_n integer;
begin
  for ra in
    select r.*, n.envio from public.reglas_alarma r join public.niveles_alarma n on n.id = r.id_nivel_alarma
    join public.edificios e on e.id = r.id_edificio and e.activo
    where r.activa
  loop
    begin
      for d in select * from private.evaluar_regla_alarma(ra.id) loop
        continue when d.cumple is null;
        select * into ev from public.eventos_alarma
        where id_regla_alarma = ra.id and estado <> 'CERRADA'
          and coalesce(id_recinto, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(d.id_recinto, '00000000-0000-0000-0000-000000000000'::uuid)
          and coalesce(id_sensor, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(d.id_sensor, '00000000-0000-0000-0000-000000000000'::uuid);
        if d.cumple then
          if ev.id is not null then
            update public.eventos_alarma
               set ultima_deteccion = pg_catalog.now(), valor_detectado = coalesce(d.valor, valor_detectado),
                   mensaje = coalesce(d.mensaje, mensaje),
                   estado = case when estado = 'RESUELTA' then case when fecha_reconocimiento is null then 'ACTIVA' else 'RECONOCIDA' end else estado end,
                   reaperturas = reaperturas + case when estado = 'RESUELTA' then 1 else 0 end,
                   fecha_resuelta = null
             where id = ev.id;
          else
            -- Si la misma causa se cerró hace menos de una hora, se reabre ese evento (sin volver a avisar)
            select * into ev from public.eventos_alarma
            where id_regla_alarma = ra.id and estado = 'CERRADA' and fecha_cierre > pg_catalog.now() - interval '60 minutes'
              and coalesce(id_recinto, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(d.id_recinto, '00000000-0000-0000-0000-000000000000'::uuid)
              and coalesce(id_sensor, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(d.id_sensor, '00000000-0000-0000-0000-000000000000'::uuid)
            order by fecha_cierre desc limit 1;
            if ev.id is not null then
              update public.eventos_alarma
                 set estado = 'ACTIVA', fecha_cierre = null, id_usuario_cierra = null, cierre_automatico = false,
                     fecha_resuelta = null, fecha_reconocimiento = null, id_usuario_reconoce = null,
                     reaperturas = reaperturas + 1, ultima_deteccion = pg_catalog.now(),
                     valor_detectado = coalesce(d.valor, valor_detectado), mensaje = coalesce(d.mensaje, mensaje)
               where id = ev.id;
            else
              insert into public.eventos_alarma (id_regla_alarma, id_sensor, id_recinto, valor_detectado, mensaje)
              values (ra.id, d.id_sensor, d.id_recinto, d.valor, coalesce(d.mensaje, ra.nombre))
              returning * into ev;
              v_abiertas := v_abiertas + 1;
              if ra.envio = 'INMEDIATO' then
                v_inmediatos := v_inmediatos + private.encolar_avisos_evento(ev.id, 'INMEDIATO');
              end if;
            end if;
          end if;
        elsif ev.id is not null and ev.estado in ('ACTIVA', 'RECONOCIDA') then
          -- La causa ha desaparecido: rearme automático = se cierra sola; manual = queda resuelta
          if ra.tipo_rearme = 'AUTOMATICO' then
            update public.eventos_alarma set estado = 'CERRADA', fecha_resuelta = pg_catalog.now(), fecha_cierre = pg_catalog.now(),
                   cierre_automatico = true, silenciada_hasta = null where id = ev.id;
            v_cerradas := v_cerradas + 1;
          else
            update public.eventos_alarma set estado = 'RESUELTA', fecha_resuelta = pg_catalog.now() where id = ev.id;
          end if;
        end if;
        ev := null;
      end loop;
    exception when others then
      raise warning 'Regla de alarma % (%): %', ra.codigo, ra.id, sqlerrm;   -- una regla rota no para el resto
    end;
  end loop;

  -- Escalado: MUY_CRITICA sin reconocer después de escalado_minutos
  for ev in
    select ea.* from public.eventos_alarma ea
    join public.reglas_alarma r on r.id = ea.id_regla_alarma and r.activa
    join public.niveles_alarma n on n.id = r.id_nivel_alarma and n.envio = 'INMEDIATO'
    where ea.estado = 'ACTIVA' and ea.escalada_en is null
      and (ea.silenciada_hasta is null or ea.silenciada_hasta < pg_catalog.now())
      and ea.fecha_inicio < pg_catalog.now() - pg_catalog.make_interval(mins => r.escalado_minutos)
  loop
    v_n := private.encolar_avisos_evento(ev.id, 'ESCALADO', true);
    v_inmediatos := v_inmediatos + v_n;
    update public.eventos_alarma set escalada_en = pg_catalog.now() where id = ev.id;
  end loop;

  -- Silencios caducados: si la causa sigue, vuelve a avisar
  for ev in
    select ea.* from public.eventos_alarma ea
    where ea.silenciada_hasta is not null and ea.silenciada_hasta < pg_catalog.now() and ea.estado in ('ACTIVA', 'RECONOCIDA')
  loop
    update public.eventos_alarma set silenciada_hasta = null, motivo_silencio = null where id = ev.id;
    if exists (select 1 from public.reglas_alarma r join public.niveles_alarma n on n.id = r.id_nivel_alarma and n.envio = 'INMEDIATO'
               where r.id = ev.id_regla_alarma) then
      v_inmediatos := v_inmediatos + private.encolar_avisos_evento(ev.id, 'REAVISO');
    end if;
  end loop;

  if v_inmediatos > 0 then
    perform private.llamar_api_avisos();
  end if;
  return pg_catalog.jsonb_build_object('abiertas', v_abiertas, 'cerradas', v_cerradas, 'emails', v_inmediatos);
end;
$$;

-- 10. Resumen diario de las alarmas críticas (un email por destinatario; pg_cron cada mañana)
create or replace function public.preparar_resumen_diario()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  insert into public.notificaciones (tipo, canal, id_usuario, destinatario, motivo, mensaje, datos)
  select 'ALARMA', 'EMAIL', u.id, u.email, 'RESUMEN_DIARIO', 'Resumen diario de alarmas críticas',
         pg_catalog.jsonb_build_object('alarmas', pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'id_evento', x.id, 'edificio', x.edificio, 'zona_horaria', x.zona_horaria, 'regla', x.regla, 'mensaje', x.mensaje,
           'estado', x.estado, 'desde', x.fecha_inicio, 'recinto', x.recinto) order by x.edificio, x.fecha_inicio))
  from (
    select distinct on (ea.id, rau.id_usuario) ea.id, ea.estado, ea.mensaje, ea.fecha_inicio, ra.nombre as regla,
           e.id as id_edificio, e.nombre as edificio, e.zona_horaria, rc.nombre as recinto, rau.id_usuario
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma and n.envio = 'RESUMEN_DIARIO'
    join public.edificios e on e.id = ra.id_edificio and e.activo
    join public.reglas_alarma_usuarios rau on rau.id_regla_alarma = ra.id and not rau.escalado
    left join public.recintos rc on rc.id = ea.id_recinto
    where (ea.estado <> 'CERRADA' or ea.fecha_inicio > pg_catalog.now() - interval '24 hours'
           or ea.fecha_cierre > pg_catalog.now() - interval '24 hours')
      and (ea.silenciada_hasta is null or ea.silenciada_hasta < pg_catalog.now())
  ) x
  join public.usuarios u on u.id = x.id_usuario and u.activo
  where private.usuario_alcanza_edificio(u.id, x.id_edificio) and private.usuario_con_permiso(u.id, 'VER_ALARMAS')
  group by u.id, u.email
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n > 0 then perform private.llamar_api_avisos(); end if;
  return v_n;
end;
$$;

-- Emails pendientes (la API los lee y marca el resultado)
create or replace function public.avisos_pendientes(p_limite integer default 50)
returns setof public.notificaciones
language sql
security definer
set search_path = ''
as $$
  select * from public.notificaciones
  where canal = 'EMAIL' and estado = 'PENDIENTE' and intentos < 5
  order by case motivo when 'INMEDIATO' then 0 when 'ESCALADO' then 0 when 'REAVISO' then 1 else 2 end, created_at
  limit p_limite;
$$;

create or replace function public.marcar_aviso(p_id uuid, p_enviado boolean, p_error text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notificaciones
     set intentos = intentos + 1,
         estado = case when p_enviado then 'ENVIADA' when intentos + 1 >= 5 then 'ERROR' else 'PENDIENTE' end,
         fecha_envio = case when p_enviado then pg_catalog.now() else fecha_envio end,
         error = case when p_enviado then null else left(p_error, 500) end
   where id = p_id;
$$;

-- 11. Acciones de los usuarios
-- Cerrar: solo cuando la causa ha desaparecido (RESUELTA). Mientras siga, no se puede.
create or replace function public.cerrar_alarma(p_id_evento uuid, p_comentario text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_estado text;
  v_activa boolean;
  v_usuario uuid := private.usuario_actual();
begin
  select ra.id_edificio, ea.estado, ra.activa into v_edificio, v_estado, v_activa
  from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ea.id = p_id_evento for update of ea;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'CERRAR_ALARMAS') then
    raise exception 'Alarma inexistente o sin permiso para cerrarla' using errcode = '42501';
  end if;
  if v_estado = 'CERRADA' then
    raise exception 'La alarma ya está cerrada' using errcode = '22023';
  end if;
  if v_estado <> 'RESUELTA' and v_activa then
    raise exception 'La causa de la alarma sigue presente: no se puede cerrar hasta que se resuelva (puede reconocerla o silenciarla)'
      using errcode = '22023';
  end if;
  update public.eventos_alarma
     set estado = 'CERRADA', fecha_cierre = pg_catalog.now(), id_usuario_cierra = v_usuario,
         fecha_reconocimiento = coalesce(fecha_reconocimiento, pg_catalog.now()),
         id_usuario_reconoce = coalesce(id_usuario_reconoce, v_usuario),
         comentario = coalesce(p_comentario, comentario), silenciada_hasta = null
   where id = p_id_evento;
end;
$$;

-- Silenciar (sin avisos hasta una fecha, máximo 30 días) o quitar el silencio (p_hasta = null)
create or replace function public.silenciar_alarma(p_id_evento uuid, p_hasta timestamptz, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
  v_estado text;
begin
  select ra.id_edificio, ea.estado into v_edificio, v_estado
  from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ea.id = p_id_evento for update of ea;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'RECONOCER_ALARMAS') then
    raise exception 'Alarma inexistente o sin permiso' using errcode = '42501';
  end if;
  if v_estado = 'CERRADA' then
    raise exception 'La alarma ya está cerrada' using errcode = '22023';
  end if;
  if p_hasta is not null and (p_hasta <= pg_catalog.now() or p_hasta > pg_catalog.now() + interval '30 days') then
    raise exception 'Se puede silenciar como máximo 30 días' using errcode = '22023';
  end if;
  if p_hasta is not null and coalesce(pg_catalog.btrim(p_motivo), '') = '' then
    raise exception 'Indique el motivo (obra, mantenimiento…)' using errcode = '22023';
  end if;
  update public.eventos_alarma
     set silenciada_hasta = p_hasta, motivo_silencio = case when p_hasta is null then null else p_motivo end,
         id_usuario_silencia = case when p_hasta is null then null else private.usuario_actual() end
   where id = p_id_evento;
end;
$$;

-- 12. Configuración de reglas (Partner, de acuerdo con el cliente)
create or replace function public.activar_regla_alarma(
  p_id_edificio uuid, p_tipo text, p_id_suministro uuid default null, p_nivel text default null,
  p_parametros jsonb default '{}', p_rearme text default null,
  p_destinatarios uuid[] default '{}', p_escalado uuid[] default '{}', p_escalado_minutos integer default 15)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo public.tipos_regla_alarma%rowtype;
  v_faltan text[];
  v_param jsonb;
  v_clave text;
  v_codigo text;
  v_id uuid;
  v_tp text;
  u uuid;
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Sin permiso para configurar alarmas en este edificio' using errcode = '42501';
  end if;
  select * into v_tipo from public.tipos_regla_alarma where codigo = p_tipo and activo;
  if not found then raise exception 'Regla desconocida: %', p_tipo using errcode = '22023'; end if;
  if p_id_suministro is not null then
    if (select id_edificio from public.suministros where id = p_id_suministro and activo) is distinct from p_id_edificio then
      raise exception 'El suministro no es de este edificio' using errcode = '22023';
    end if;
    v_tp := private.tipo_parametros_suministro(p_id_suministro);
    if v_tipo.tipo_suministro is distinct from v_tp
       and not (v_tipo.tipo_suministro = 'CONSUMO' and v_tp in ('ELECTRICIDAD', 'GAS', 'AGUA')) then
      raise exception 'La regla «%» no se aplica a este suministro', v_tipo.nombre using errcode = '22023';
    end if;
  elsif v_tipo.tipo_suministro is not null then
    raise exception 'La regla «%» necesita un suministro o una instalación', v_tipo.nombre using errcode = '22023';
  end if;
  v_faltan := public.requisitos_regla_alarma(p_id_edificio, p_tipo, p_id_suministro);
  if pg_catalog.cardinality(v_faltan) > 0 then
    raise exception 'No se puede activar «%»: falta %', v_tipo.nombre, pg_catalog.array_to_string(v_faltan, ', ') using errcode = '22023';
  end if;
  v_param := v_tipo.parametros || coalesce(p_parametros, '{}'::jsonb);
  for v_clave in select k from pg_catalog.jsonb_object_keys(v_param) k loop
    if pg_catalog.jsonb_typeof(v_param->v_clave) = 'null' then
      raise exception 'Indique el valor de «%» para activar «%»', v_clave, v_tipo.nombre using errcode = '22023';
    end if;
  end loop;
  if coalesce(p_nivel, v_tipo.nivel_recomendado) not in ('MUY_CRITICA', 'CRITICA', 'AVISO') then
    raise exception 'Nivel no válido' using errcode = '22023';
  end if;
  if coalesce(p_nivel, v_tipo.nivel_recomendado) = 'MUY_CRITICA' and pg_catalog.cardinality(coalesce(p_destinatarios, '{}')) = 0 then
    raise exception 'Una alarma muy crítica necesita al menos un destinatario del email' using errcode = '22023';
  end if;
  foreach u in array coalesce(p_destinatarios, '{}') || coalesce(p_escalado, '{}') loop
    if not (private.usuario_alcanza_edificio(u, p_id_edificio) and private.usuario_con_permiso(u, 'VER_ALARMAS')) then
      raise exception 'Un destinatario no tiene acceso a las alarmas de este edificio' using errcode = '22023';
    end if;
  end loop;

  v_codigo := p_tipo || coalesce('-' || (select codigo from public.suministros where id = p_id_suministro), '');
  select id into v_id from public.reglas_alarma where id_edificio = p_id_edificio and codigo = v_codigo;
  if v_id is null then
    insert into public.reglas_alarma (id_edificio, codigo, nombre, descripcion, tipo_regla, id_suministro, parametros,
                                      id_nivel_alarma, tipo_rearme, escalado_minutos, duracion_minutos)
    values (p_id_edificio, v_codigo,
            v_tipo.nombre || coalesce(' · ' || (select nombre from public.suministros where id = p_id_suministro), ''),
            v_tipo.descripcion, p_tipo, p_id_suministro, v_param,
            (select id from public.niveles_alarma where codigo = coalesce(p_nivel, v_tipo.nivel_recomendado)),
            coalesce(p_rearme, v_tipo.rearme_recomendado), coalesce(p_escalado_minutos, 15),
            coalesce((v_param->>'duracion')::integer, 0))
    returning id into v_id;
  else
    update public.reglas_alarma
       set parametros = v_param, id_nivel_alarma = (select id from public.niveles_alarma where codigo = coalesce(p_nivel, v_tipo.nivel_recomendado)),
           tipo_rearme = coalesce(p_rearme, v_tipo.rearme_recomendado), escalado_minutos = coalesce(p_escalado_minutos, 15),
           duracion_minutos = coalesce((v_param->>'duracion')::integer, 0), activa = true, fecha_baja = null
     where id = v_id;
  end if;
  delete from public.reglas_alarma_usuarios where id_regla_alarma = v_id;
  insert into public.reglas_alarma_usuarios (id_regla_alarma, id_usuario, escalado)
  select v_id, x, false from pg_catalog.unnest(coalesce(p_destinatarios, '{}')) x
  union select v_id, x, true from pg_catalog.unnest(coalesce(p_escalado, '{}')) x where not (x = any (coalesce(p_destinatarios, '{}')));
  return v_id;
end;
$$;

create or replace function public.desactivar_regla_alarma(p_id_regla uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_edificio uuid;
begin
  select id_edificio into v_edificio from public.reglas_alarma where id = p_id_regla;
  if v_edificio is null or not private.usuario_puede_edificio(v_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Regla inexistente o sin permiso' using errcode = '42501';
  end if;
  update public.reglas_alarma set activa = false, fecha_baja = greatest(current_date, fecha_alta) where id = p_id_regla and activa;
  update public.eventos_alarma
     set estado = 'CERRADA', fecha_resuelta = coalesce(fecha_resuelta, pg_catalog.now()), fecha_cierre = pg_catalog.now(),
         cierre_automatico = true, comentario = coalesce(comentario, 'Regla desactivada')
   where id_regla_alarma = p_id_regla and estado <> 'CERRADA';
end;
$$;

-- Catálogo para la pantalla de configuración: cada regla aplicable al edificio, con su estado
create or replace function public.reglas_alarma_edificio(p_id_edificio uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with destinos as (
    select su.id, su.nombre, su.codigo, private.tipo_parametros_suministro(su.id) as tp
    from public.suministros su where su.id_edificio = p_id_edificio and su.activo
  ),
  aplicables as (
    select t.*, d.id as id_suministro, d.nombre as suministro, d.codigo as codigo_suministro
    from public.tipos_regla_alarma t
    left join destinos d on t.tipo_suministro is not null
      and (d.tp = t.tipo_suministro or (t.tipo_suministro = 'CONSUMO' and d.tp in ('ELECTRICIDAD', 'GAS', 'AGUA')))
    where t.activo and (t.tipo_suministro is null or d.id is not null)
      and exists (select 1 from public.edificios e where e.id = p_id_edificio)   -- RLS: solo quien ve el edificio
  )
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'tipo', a.codigo, 'nombre', a.nombre, 'descripcion', a.descripcion, 'categoria', a.categoria,
    'id_suministro', a.id_suministro, 'suministro', a.suministro,
    'nivel_recomendado', a.nivel_recomendado, 'rearme_recomendado', a.rearme_recomendado, 'parametros_defecto', a.parametros,
    'faltan', pg_catalog.to_jsonb(public.requisitos_regla_alarma(p_id_edificio, a.codigo, a.id_suministro)),
    'regla', (select pg_catalog.jsonb_build_object('id', r.id, 'activa', r.activa, 'nivel', n.codigo, 'parametros', r.parametros,
                     'rearme', r.tipo_rearme, 'escalado_minutos', r.escalado_minutos,
                     'destinatarios', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', u.id, 'nombre', u.nombre, 'email', u.email, 'escalado', rau.escalado))
                                                from public.reglas_alarma_usuarios rau join public.usuarios u on u.id = rau.id_usuario
                                                where rau.id_regla_alarma = r.id), '[]'::jsonb))
              from public.reglas_alarma r join public.niveles_alarma n on n.id = r.id_nivel_alarma
              where r.id_edificio = p_id_edificio and r.codigo = a.codigo || coalesce('-' || a.codigo_suministro, ''))
  ) order by a.orden, a.suministro), '[]'::jsonb)
  from aplicables a;
$$;

-- Personas que pueden recibir los avisos de un edificio (para elegir destinatarios y escalado)
create or replace function public.usuarios_alarmas_edificio(p_id_edificio uuid)
returns table (id uuid, nombre text, email text, rol text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.usuario_puede_edificio(p_id_edificio, 'MODIFICAR_ALARMAS') then
    raise exception 'Sin permiso para configurar alarmas en este edificio' using errcode = '42501';
  end if;
  return query
  select u.id, pg_catalog.concat_ws(' ', u.nombre, u.apellidos)::text, u.email::text, r.nombre::text
  from public.usuarios u join public.roles r on r.id = u.id_rol
  where u.activo and private.usuario_alcanza_edificio(u.id, p_id_edificio) and private.usuario_con_permiso(u.id, 'VER_ALARMAS')
  order by r.codigo = 'ADMIN_SAAS', u.nombre;
end;
$$;

-- 13. Alarmas del edificio y campana: también las resueltas pendientes de cierre; los sensores
--     sin comunicación que ya tienen su alarma (regla SIN_COMUNICACION) no se repiten
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
             'sensor', s.nombre, 'recinto', r.nombre, 'comentario', ea.comentario,
             'reconocida', ea.fecha_reconocimiento, 'reconoce', ur.nombre,
             'silenciada_hasta', case when ea.silenciada_hasta > pg_catalog.now() then ea.silenciada_hasta end,
             'motivo_silencio', ea.motivo_silencio, 'rearme', ra.tipo_rearme, 'reaperturas', ea.reaperturas,
             'se_puede_cerrar', ea.estado = 'RESUELTA') as fila
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    left join public.sensores s on s.id = coalesce(ea.id_sensor, ra.id_sensor)
    left join public.recintos r on r.id = coalesce(ea.id_recinto, s.id_recinto)
    left join public.usuarios ur on ur.id = ea.id_usuario_reconoce
    where ea.estado in ('ACTIVA', 'RECONOCIDA', 'RESUELTA')
    union all
    select 0, 2, ic.fecha_inicio,
           pg_catalog.jsonb_build_object(
             'tipo', 'COMUNICACION', 'id', ic.id, 'nivel', 'AVISO', 'nivel_nombre', 'Aviso', 'prioridad', 2,
             'titulo', 'Sin comunicación', 'detalle', 'No llegan lecturas de este sensor', 'estado', 'ACTIVA',
             'desde', ic.fecha_inicio, 'id_sensor', s.id, 'sensor', s.nombre, 'recinto', r.nombre)
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor and s.activo
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    where ic.estado = 'ABIERTA'
      and not exists (select 1 from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                      where ra.tipo_regla = 'SIN_COMUNICACION' and ea.id_sensor = s.id and ea.estado <> 'CERRADA')
  ) x;
$$;

create or replace function public.resumen_alarmas_usuario()
returns jsonb
language sql
stable
set search_path = ''
as $$
  with alarmas as (
    select ra.id_edificio, n.prioridad
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    where ea.estado in ('ACTIVA', 'RECONOCIDA', 'RESUELTA')
    union all
    select p.id_edificio, 2
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor and s.activo
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta
    where ic.estado = 'ABIERTA'
      and not exists (select 1 from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                      where ra.tipo_regla = 'SIN_COMUNICACION' and ea.id_sensor = s.id and ea.estado <> 'CERRADA')
  ),
  por_edificio as (
    select e.id, e.nombre, count(*) as total, max(a.prioridad) as prioridad
    from alarmas a
    join public.edificios e on e.id = a.id_edificio and e.activo
    group by e.id, e.nombre
  )
  select pg_catalog.jsonb_build_object(
    'total', coalesce(sum(total), 0),
    'nivel', (select n.codigo from public.niveles_alarma n where n.prioridad = max(pe.prioridad)),
    'edificios', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id_edificio', id, 'nombre', nombre, 'total', total,
        'nivel', (select n.codigo from public.niveles_alarma n where n.prioridad = pe.prioridad))
      order by prioridad desc, total desc, nombre), '[]'::jsonb))
  from por_edificio pe;
$$;

-- 14. Programación (pg_cron): motor cada 5 min; resumen diario a las 6:40 UTC (7:40 / 8:40 en España)
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('motor_alarmas_5min', 'resumen_alarmas_diario');
  perform cron.schedule('motor_alarmas_5min', '*/5 * * * *', 'select public.motor_alarmas()');
  perform cron.schedule('resumen_alarmas_diario', '40 6 * * *', 'select public.preparar_resumen_diario()');
exception when others then
  raise notice 'pg_cron no disponible: programe motor_alarmas() y preparar_resumen_diario() desde la API';
end;
$$;

revoke all on function private.encolar_avisos_evento(uuid, text, boolean) from public, anon, authenticated;
revoke all on function private.llamar_api_avisos() from public, anon, authenticated;
revoke all on function public.motor_alarmas() from public, anon, authenticated;
revoke all on function public.preparar_resumen_diario() from public, anon, authenticated;
revoke all on function public.avisos_pendientes(integer) from public, anon, authenticated;
revoke all on function public.marcar_aviso(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.cerrar_alarma(uuid, text) from public, anon;
revoke all on function public.silenciar_alarma(uuid, timestamptz, text) from public, anon;
revoke all on function public.activar_regla_alarma(uuid, text, uuid, text, jsonb, text, uuid[], uuid[], integer) from public, anon;
revoke all on function public.desactivar_regla_alarma(uuid) from public, anon;
revoke all on function public.reglas_alarma_edificio(uuid) from public, anon;
revoke all on function public.usuarios_alarmas_edificio(uuid) from public, anon;
revoke all on function public.alarmas_edificio(uuid) from public, anon;
revoke all on function public.resumen_alarmas_usuario() from public, anon;
grant execute on function public.motor_alarmas() to service_role;
grant execute on function public.preparar_resumen_diario() to service_role;
grant execute on function public.avisos_pendientes(integer) to service_role;
grant execute on function public.marcar_aviso(uuid, boolean, text) to service_role;
grant execute on function public.cerrar_alarma(uuid, text) to authenticated;
grant execute on function public.silenciar_alarma(uuid, timestamptz, text) to authenticated;
grant execute on function public.activar_regla_alarma(uuid, text, uuid, text, jsonb, text, uuid[], uuid[], integer) to authenticated;
grant execute on function public.desactivar_regla_alarma(uuid) to authenticated;
grant execute on function public.reglas_alarma_edificio(uuid) to authenticated, service_role;
grant execute on function public.usuarios_alarmas_edificio(uuid) to authenticated;
grant execute on function public.alarmas_edificio(uuid) to authenticated, service_role;
grant execute on function public.resumen_alarmas_usuario() to authenticated, service_role;

commit;
