-- =========================================================
-- 055 · Histórico de alarmas y registro de cada paso (D59)
--  - eventos_alarma_acciones: cronología de cada alarma (se abre, email, escalado,
--    reconocida, silenciada, vuelve la causa, resuelta, cerrada…), con hora y persona.
--    La escriben triggers: nadie la edita y nunca se borra.
--  - historico_alarmas(): alarmas e incidencias de comunicación de un periodo, de la
--    más reciente a la más antigua, con duración y tiempos de respuesta.
--  - cronologia_alarma(): los pasos de una alarma.
-- =========================================================
begin;

create table if not exists public.eventos_alarma_acciones (
  id uuid primary key default gen_random_uuid(),
  id_evento_alarma uuid not null references public.eventos_alarma(id),
  accion text not null check (accion in ('ABIERTA', 'EMAIL_ENVIADO', 'EMAIL_ERROR', 'ESCALADA', 'RECONOCIDA', 'SILENCIADA',
                                         'SILENCIO_RETIRADO', 'SILENCIO_CADUCADO', 'RESUELTA', 'VUELVE_CAUSA', 'REABIERTA',
                                         'CERRADA', 'CERRADA_AUTOMATICA')),
  fecha timestamptz not null default pg_catalog.now(),
  id_usuario uuid references public.usuarios(id),          -- null: la plataforma
  detalle text,
  created_at timestamptz not null default pg_catalog.now()
);
alter table public.eventos_alarma_acciones enable row level security;
create index if not exists ix_eventos_alarma_acciones_evento on public.eventos_alarma_acciones (id_evento_alarma, fecha);

drop policy if exists eventos_alarma_acciones_select on public.eventos_alarma_acciones;
create policy eventos_alarma_acciones_select on public.eventos_alarma_acciones
for select to authenticated
using (private.usuario_tiene_acceso_edificio((select ra.id_edificio from public.eventos_alarma ea
                                              join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                                              where ea.id = eventos_alarma_acciones.id_evento_alarma))
       and private.usuario_tiene_permiso('VER_ALARMAS'));
grant select on public.eventos_alarma_acciones to authenticated;
-- Sin políticas de escritura: solo los triggers (security definer)

create or replace function private.registrar_accion_alarma()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quien uuid := private.usuario_actual();
  v_alta boolean := tg_op = 'INSERT';
begin
  if v_alta then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, fecha, detalle)
    values (new.id, 'ABIERTA', new.fecha_inicio, new.mensaje);
    return new;
  end if;

  if old.estado = 'CERRADA' and new.estado <> 'CERRADA' then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, detalle)
    values (new.id, 'REABIERTA', 'La causa ha vuelto antes de una hora: ' || coalesce(new.mensaje, ''));
  elsif old.estado = 'RESUELTA' and new.estado in ('ACTIVA', 'RECONOCIDA') then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, detalle)
    values (new.id, 'VUELVE_CAUSA', new.mensaje);
  end if;
  if old.estado = 'ACTIVA' and new.estado = 'RECONOCIDA'
     or (new.fecha_reconocimiento is not null and old.fecha_reconocimiento is null and new.estado <> 'CERRADA') then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
    values (new.id, 'RECONOCIDA', coalesce(new.id_usuario_reconoce, v_quien), new.comentario);
  end if;
  if new.estado = 'RESUELTA' and old.estado <> 'RESUELTA' then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, detalle)
    values (new.id, 'RESUELTA', 'La causa ha desaparecido');
  end if;
  if new.estado = 'CERRADA' and old.estado <> 'CERRADA' then
    if new.cierre_automatico then
      insert into public.eventos_alarma_acciones (id_evento_alarma, accion, detalle)
      values (new.id, 'CERRADA_AUTOMATICA', coalesce(case when new.comentario is distinct from old.comentario then new.comentario end,
                                                     'Rearme automático: la causa ha desaparecido'));
    else
      insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
      values (new.id, 'CERRADA', coalesce(new.id_usuario_cierra, v_quien),
              case when new.comentario is distinct from old.comentario then new.comentario end);
    end if;
  elsif new.silenciada_hasta is distinct from old.silenciada_hasta then
    if new.silenciada_hasta is not null then
      insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
      values (new.id, 'SILENCIADA', coalesce(new.id_usuario_silencia, v_quien),
              'Hasta ' || pg_catalog.to_char(new.silenciada_hasta at time zone
                 coalesce((select e.zona_horaria from public.reglas_alarma ra join public.edificios e on e.id = ra.id_edificio
                           where ra.id = new.id_regla_alarma), 'Europe/Madrid'), 'DD/MM/YYYY HH24:MI')
              || coalesce(': ' || new.motivo_silencio, ''));
    elsif old.silenciada_hasta <= pg_catalog.now() then
      insert into public.eventos_alarma_acciones (id_evento_alarma, accion, detalle)
      values (new.id, 'SILENCIO_CADUCADO', 'Ha terminado el silencio y la causa sigue');
    else
      insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario)
      values (new.id, 'SILENCIO_RETIRADO', v_quien);
    end if;
  end if;
  if new.escalada_en is not null and old.escalada_en is null then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, fecha, detalle)
    values (new.id, 'ESCALADA', new.escalada_en, 'Sin reconocer: aviso a los destinatarios de escalado');
  end if;
  return new;
end;
$$;
revoke all on function private.registrar_accion_alarma() from public, anon, authenticated;

drop trigger if exists trg_eventos_alarma_acciones on public.eventos_alarma;
create trigger trg_eventos_alarma_acciones
after insert or update on public.eventos_alarma
for each row execute function private.registrar_accion_alarma();

-- Emails de alarmas: cuándo se envió y a quién (o por qué no)
create or replace function private.registrar_email_alarma()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.id_evento_alarma is not null and new.estado is distinct from old.estado and new.estado in ('ENVIADA', 'ERROR') then
    insert into public.eventos_alarma_acciones (id_evento_alarma, accion, id_usuario, detalle)
    values (new.id_evento_alarma, case new.estado when 'ENVIADA' then 'EMAIL_ENVIADO' else 'EMAIL_ERROR' end, null,
            case new.motivo when 'ESCALADO' then 'Escalado' when 'REAVISO' then 'Reaviso' else 'Email' end
            || ' a ' || coalesce(new.destinatario, '') || coalesce(' · ' || new.error, ''));
  end if;
  return new;
end;
$$;
revoke all on function private.registrar_email_alarma() from public, anon, authenticated;

drop trigger if exists trg_notificaciones_acciones on public.notificaciones;
create trigger trg_notificaciones_acciones
after update of estado on public.notificaciones
for each row execute function private.registrar_email_alarma();

-- Lo ya ocurrido antes de esta migración, con los datos que hay
insert into public.eventos_alarma_acciones (id_evento_alarma, accion, fecha, id_usuario, detalle)
select ea.id, x.accion, x.fecha, x.usuario, x.detalle
from public.eventos_alarma ea
cross join lateral (values
  ('ABIERTA', ea.fecha_inicio, null::uuid, ea.mensaje),
  ('RECONOCIDA', ea.fecha_reconocimiento, ea.id_usuario_reconoce, null),
  ('RESUELTA', ea.fecha_resuelta, null, 'La causa ha desaparecido'),
  (case when ea.cierre_automatico then 'CERRADA_AUTOMATICA' else 'CERRADA' end, ea.fecha_cierre, ea.id_usuario_cierra, ea.comentario)
) x(accion, fecha, usuario, detalle)
where x.fecha is not null
  and not exists (select 1 from public.eventos_alarma_acciones a where a.id_evento_alarma = ea.id);

-- Histórico de un edificio: de la más reciente a la más antigua
create or replace function public.historico_alarmas(
  p_id_edificio uuid, p_desde date default null, p_hasta date default null,
  p_nivel text default null, p_estado text default null, p_texto text default null, p_limite integer default 300)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with zona as (
    select coalesce(e.zona_horaria, 'Europe/Madrid') as tz from public.edificios e where e.id = p_id_edificio
  ),
  limites as (
    select case when p_desde is null then '-infinity'::timestamptz else (p_desde::timestamp at time zone z.tz) end as desde,
           case when p_hasta is null then 'infinity'::timestamptz else ((p_hasta + 1)::timestamp at time zone z.tz) end as hasta
    from zona z
  ),
  alarmas as (
    select ea.fecha_inicio as desde, pg_catalog.jsonb_build_object(
      'tipo', 'ALARMA', 'id', ea.id, 'nivel', n.codigo, 'nivel_nombre', n.nombre, 'titulo', ra.nombre, 'detalle', ea.mensaje,
      'estado', ea.estado, 'desde', ea.fecha_inicio, 'resuelta', ea.fecha_resuelta, 'cierre', ea.fecha_cierre,
      'minutos', pg_catalog.round(extract(epoch from coalesce(ea.fecha_resuelta, ea.fecha_cierre, pg_catalog.now()) - ea.fecha_inicio) / 60),
      'minutos_reconocer', pg_catalog.round(extract(epoch from ea.fecha_reconocimiento - ea.fecha_inicio) / 60),
      'reconocida', ea.fecha_reconocimiento, 'reconoce', ur.nombre,
      'cierra', case when ea.cierre_automatico then 'Automático' else uc.nombre end,
      'comentario', ea.comentario, 'reaperturas', ea.reaperturas, 'valor', ea.valor_detectado,
      'silencios', (select count(*) from public.eventos_alarma_acciones a where a.id_evento_alarma = ea.id and a.accion = 'SILENCIADA'),
      'emails', (select count(*) from public.eventos_alarma_acciones a where a.id_evento_alarma = ea.id and a.accion = 'EMAIL_ENVIADO'),
      'id_sensor', coalesce(ea.id_sensor, ra.id_sensor), 'sensor', s.nombre,
      'id_recinto', r.id, 'recinto', r.nombre, 'planta', pl.nombre) as fila,
      n.codigo as nivel, ea.estado, pg_catalog.concat_ws(' ', ra.nombre, ea.mensaje, s.nombre, r.nombre, ea.comentario) as texto
    from public.eventos_alarma ea
    join public.reglas_alarma ra on ra.id = ea.id_regla_alarma and ra.id_edificio = p_id_edificio
    join public.niveles_alarma n on n.id = ra.id_nivel_alarma
    left join public.sensores s on s.id = coalesce(ea.id_sensor, ra.id_sensor)
    left join public.recintos r on r.id = coalesce(ea.id_recinto, s.id_recinto)
    left join public.plantas pl on pl.id = r.id_planta
    left join public.usuarios ur on ur.id = ea.id_usuario_reconoce
    left join public.usuarios uc on uc.id = ea.id_usuario_cierra
    cross join limites l
    where ea.fecha_inicio >= l.desde and ea.fecha_inicio < l.hasta
  ),
  comunicacion as (
    select ic.fecha_inicio as desde, pg_catalog.jsonb_build_object(
      'tipo', 'COMUNICACION', 'id', ic.id, 'nivel', 'AVISO', 'nivel_nombre', 'Aviso', 'titulo', 'Sin comunicación',
      'detalle', 'No llegaban lecturas de este sensor', 'estado', case when ic.estado = 'ABIERTA' then 'ACTIVA' else 'CERRADA' end,
      'desde', ic.fecha_inicio, 'resuelta', ic.fecha_fin, 'cierre', ic.fecha_fin, 'cierra', case when ic.fecha_fin is not null then 'Automático' end,
      'minutos', pg_catalog.round(extract(epoch from coalesce(ic.fecha_fin, pg_catalog.now()) - ic.fecha_inicio) / 60),
      'id_sensor', s.id, 'sensor', s.nombre, 'id_recinto', r.id, 'recinto', r.nombre, 'planta', p.nombre) as fila,
      'AVISO'::text as nivel, case when ic.estado = 'ABIERTA' then 'ACTIVA' else 'CERRADA' end as estado,
      pg_catalog.concat_ws(' ', 'Sin comunicación', s.nombre, r.nombre) as texto
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta and p.id_edificio = p_id_edificio
    cross join limites l
    where ic.fecha_inicio >= l.desde and ic.fecha_inicio < l.hasta
      and not exists (select 1 from public.eventos_alarma ea join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                      where ra.tipo_regla = 'SIN_COMUNICACION' and ea.id_sensor = s.id
                        and ea.fecha_inicio between ic.fecha_inicio - interval '1 hour' and coalesce(ic.fecha_fin, 'infinity'))
  ),
  todo as (
    select * from alarmas union all select * from comunicacion
  ),
  filtrado as (
    select * from todo t
    where (p_nivel is null or t.nivel = p_nivel)
      and (p_estado is null or t.estado = p_estado or (p_estado = 'ABIERTA' and t.estado <> 'CERRADA'))
      and (coalesce(pg_catalog.btrim(p_texto), '') = '' or t.texto ilike '%' || pg_catalog.btrim(p_texto) || '%')
  )
  select pg_catalog.jsonb_build_object(
    'total', (select count(*) from filtrado),
    'filas', coalesce((select pg_catalog.jsonb_agg(f.fila order by f.desde desc)
                       from (select * from filtrado order by desde desc limit greatest(1, least(coalesce(p_limite, 300), 2000))) f), '[]'::jsonb));
$$;
revoke all on function public.historico_alarmas(uuid, date, date, text, text, text, integer) from public, anon;
grant execute on function public.historico_alarmas(uuid, date, date, text, text, text, integer) to authenticated, service_role;

-- Cronología de una alarma
create or replace function public.cronologia_alarma(p_id_evento uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'accion', a.accion, 'fecha', a.fecha, 'quien', coalesce(nullif(pg_catalog.concat_ws(' ', u.nombre, u.apellidos), ''), 'Plataforma'),
    'detalle', a.detalle) order by a.fecha, a.created_at), '[]'::jsonb)
  from public.eventos_alarma_acciones a
  left join public.usuarios u on u.id = a.id_usuario
  where a.id_evento_alarma = p_id_evento;
$$;
revoke all on function public.cronologia_alarma(uuid) from public, anon;
grant execute on function public.cronologia_alarma(uuid) to authenticated, service_role;

commit;
