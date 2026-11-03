-- =========================================================
-- 035 · Campana de alarmas en la cabecera
-- Decisión D44 (02/11/2026): la cabecera muestra el número de alarmas
-- activas de todos los edificios que ve el usuario (alarmas activas o
-- reconocidas y sensores sin comunicación) y, al pulsarla, la lista por
-- edificio.
--   · resumen_alarmas_usuario(): se ejecuta con los permisos del usuario
--     (RLS): solo cuenta lo de sus edificios.
-- =========================================================
begin;

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
    where ea.estado in ('ACTIVA', 'RECONOCIDA')
    union all
    select p.id_edificio, 2
    from public.incidencias_comunicacion ic
    join public.sensores s on s.id = ic.id_sensor and s.activo
    join public.recintos r on r.id = s.id_recinto
    join public.plantas p on p.id = r.id_planta
    where ic.estado = 'ABIERTA'
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

revoke all on function public.resumen_alarmas_usuario() from public, anon;
grant execute on function public.resumen_alarmas_usuario() to authenticated, service_role;

commit;
