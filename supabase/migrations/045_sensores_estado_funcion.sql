-- =========================================================
-- 045 · Estado de sensores con su función y su energía
-- Decisión D56 (16/11/2026).
--
--   · sensores_estado_edificio() devuelve también la función del medidor
--     (GENERAL, CUADRO o USO), el tipo de energía y el flujo (consumo,
--     generación o exportación). Con ellos, en la pestaña Hoy con todo el
--     edificio, el visor 3D solo muestra los totales de los cuadros, los
--     consumos de los suministros (red, gas, agua) y la producción renovable.
-- =========================================================
begin;

drop function if exists public.sensores_estado_edificio(uuid);
create function public.sensores_estado_edificio(p_id_edificio uuid)
returns table (
  id_sensor uuid,
  codigo varchar,
  nombre varchar,
  familia varchar,
  unidad varchar,
  id_recinto uuid,
  ultimo_valor double precision,
  ultima_lectura timestamptz,
  estado_comunicacion varchar,
  alarma_activa boolean,
  ubicaciones jsonb,
  id_dispositivo uuid,
  dispositivo varchar,
  funcion_medidor varchar,
  tipo_energia varchar,
  flujo_energia varchar
)
language sql
stable
set search_path = ''
as $$
  select s.id, s.codigo, s.nombre, f.codigo, s.unidad, s.id_recinto,
         ec.ultimo_valor, ec.ultima_lectura, coalesce(ec.estado, 'SIN_DATOS'),
         exists (select 1 from public.eventos_alarma ea
                 join public.reglas_alarma ra on ra.id = ea.id_regla_alarma
                 where ea.estado <> 'CERRADA'
                   and (ea.id_sensor = s.id or ra.id_sensor = s.id)),
         coalesce((
           select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                    'id_modelo_3d', u.id_modelo_3d, 'tipo_modelo', m.tipo_modelo,
                    'x', u.x, 'y', u.y, 'z', u.z, 'visible', u.visible))
           from public.ubicaciones_3d u
           join public.modelos_3d m on m.id = u.id_modelo_3d and m.activo
           where u.id_sensor = s.id
              or (u.id_dispositivo is not null and u.id_dispositivo = s.id_dispositivo)
         ), '[]'::jsonb),
         s.id_dispositivo, d.nombre, s.funcion_medidor, te.codigo, fe.codigo
  from public.sensores s
  join public.familias_sensor f on f.id = s.id_familia
  left join public.dispositivos d on d.id = s.id_dispositivo
  left join public.tipos_energia te on te.id = s.id_tipo_energia
  left join public.flujos_energia fe on fe.id = s.id_flujo_energia
  left join public.estado_comunicacion ec on ec.id_sensor = s.id
  where s.activo
    and public.obtener_edificio_recinto(s.id_recinto) = p_id_edificio;
$$;

revoke all on function public.sensores_estado_edificio(uuid) from public, anon;
grant execute on function public.sensores_estado_edificio(uuid) to authenticated, service_role;

commit;
