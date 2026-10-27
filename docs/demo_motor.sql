-- =========================================================
-- MOTOR EN EL EDIFICIO DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Pegar entero en el SQL Editor de Supabase y pulsar Run, DESPUÉS de
-- demo_simuladores.sql. Se puede repetir: no duplica nada y NO cambia
-- los secretos de Render.
--
-- Hace lo que hará el Partner en el asistente de configuración:
-- indica a qué magnitud alimenta cada sensor del edificio DEMO-OFICINAS.
--   CONT-GENERAL → Consumo de electricidad (importada de la red)
--   FV-PROD      → Generación fotovoltaica
--   GAS-CONT     → Consumo de gas (m³ → kWh con FACTOR_CONVERSION_GAS)
--   AGUA-CONT    → Consumo de agua
--   POT-GENERAL  → Potencia total
--   FP-GENERAL   → Factor de potencia (crea el sensor si no existe y pide
--                  a la API REST simulada los 30 días de histórico; requiere
--                  la API 0.7.1 o posterior, que simula ese punto)
--   CLIMA-E      → submedidor de Climatización (uso, para el Sankey)
--   Gas sin submedidor: 100 % climatización (reparto estimado)
--   Horario: laborables de lunes a viernes de 08:00 a 19:00 (para
--   "consumo fuera de horario" en la pestaña Hoy)
--
-- Al asignar las fuentes, el motor recalcula todo el histórico en las
-- siguientes ejecuciones (cada 15 minutos, por tramos de 7 días).
-- =========================================================
do $$
declare
  v_edif uuid;
  v_hvac smallint;
  r record;
  v_me uuid;
  v_sensor uuid;
  v_rest uuid;
begin
  select id into v_edif from public.edificios where codigo = 'DEMO-OFICINAS';
  if v_edif is null then
    raise exception 'No existe el edificio DEMO-OFICINAS: ejecute antes demo_simuladores.sql';
  end if;
  select id into v_hvac from public.usos_energia where codigo = 'HVAC_CLIMATIZACION';

  -- Sensor de factor de potencia en la conexión API REST (si no existe)
  select c.id into v_rest from public.conexiones c join public.tipos_conexion t on t.id = c.id_tipo_conexion
  where c.id_edificio = v_edif and t.codigo = 'API_REST' and c.activo limit 1;
  if v_rest is not null and not exists (
       select 1 from public.sensores s where s.codigo = 'FP-GENERAL' and s.activo
         and public.obtener_edificio_recinto(s.id_recinto) = v_edif) then
    insert into public.sensores (id_conexion, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza,
                                 id_tratamiento, unidad, id_tipo_energia, id_flujo_energia, escala)
    select v_rest, rc.id, 'FP-GENERAL', 'Factor de potencia del contador general',
           '{"ruta_valor": "valor", "filtro": {"punto": "FP-GENERAL"}}'::jsonb,
           f.id, n.id, tr.id, '-', te.id, fe.id, 1.0
    from public.recintos rc join public.plantas p on p.id = rc.id_planta,
         public.familias_sensor f, public.naturalezas_sensor n, public.tratamientos_sensor tr,
         public.tipos_energia te, public.flujos_energia fe
    where p.id_edificio = v_edif and rc.codigo = 'SALA-INST'
      and f.codigo = 'FACTOR_POTENCIA' and n.codigo = 'INSTANTANEA' and tr.codigo = 'PROMEDIO'
      and te.codigo = 'ELECTRICIDAD' and fe.codigo = 'CONSUMO';
    -- Histórico de 30 días del punto nuevo (las lecturas ya guardadas no se duplican)
    if (select coalesce(recuperacion_estado, '') from public.conexiones where id = v_rest) not in ('PENDIENTE', 'EN_CURSO') then
      perform public.solicitar_recuperacion(v_rest, current_date - 30);
    end if;
  end if;

  for r in select * from (values
      ('CONSUMO_ELECTRICIDAD', 'CONT-GENERAL'),
      ('GENERACION_FOTOVOLTAICA', 'FV-PROD'),
      ('CONSUMO_GAS', 'GAS-CONT'),
      ('CONSUMO_AGUA', 'AGUA-CONT'),
      ('POTENCIA_TOTAL', 'POT-GENERAL'),
      ('FACTOR_POTENCIA', 'FP-GENERAL')) x(magnitud, sensor)
  loop
    select me.id into v_me
    from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
    where me.id_edificio = v_edif and m.codigo = r.magnitud and me.ambito = 'EDIFICIO' and me.activa;
    if v_me is null then
      insert into public.magnitudes_edificio (id_edificio, id_magnitud, ambito)
      select v_edif, m.id, 'EDIFICIO' from public.magnitudes m where m.codigo = r.magnitud
      returning id into v_me;
    end if;

    select s.id into v_sensor from public.sensores s
    where s.codigo = r.sensor and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
    if v_sensor is null then
      raise notice 'Sensor % no encontrado: se omite', r.sensor;
      continue;
    end if;

    insert into public.magnitudes_fuentes (id_magnitud_edificio, id_sensor)
    select v_me, v_sensor
    where not exists (select 1 from public.magnitudes_fuentes
                      where id_magnitud_edificio = v_me and id_sensor = v_sensor);
  end loop;

  update public.sensores s set id_uso_energia = v_hvac
  where s.codigo = 'CLIMA-E' and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif
    and s.id_uso_energia is distinct from v_hvac;

  insert into public.repartos_uso_edificio (id_edificio, tipo_energia, id_uso_energia, porcentaje)
  select v_edif, 'GAS', v_hvac, 100
  where not exists (select 1 from public.repartos_uso_edificio where id_edificio = v_edif and tipo_energia = 'GAS');

  -- Horario tipo y calendario (año actual, incluido lo ya pasado, y el siguiente)
  insert into public.horarios_tipo_edificio (id_edificio, dia_semana, laborable, hora_inicio, hora_fin)
  select v_edif, d, d <= 5, case when d <= 5 then time '08:00' end, case when d <= 5 then time '19:00' end
  from pg_catalog.generate_series(1, 7) d
  on conflict (id_edificio, dia_semana) do nothing;
  perform public.generar_calendario(v_edif, extract(year from current_date)::integer, false, true);
  perform public.generar_calendario(v_edif, extract(year from current_date)::integer + 1);
end;
$$;

-- Comprobación: magnitudes con su sensor y lo que queda pendiente de calcular
select m.nombre as "Magnitud", s.codigo as "Sensor", s.unidad as "Unidad"
from public.magnitudes_edificio me
join public.magnitudes m on m.id = me.id_magnitud
join public.magnitudes_fuentes mf on mf.id_magnitud_edificio = me.id
join public.sensores s on s.id = mf.id_sensor
join public.edificios e on e.id = me.id_edificio
where e.codigo = 'DEMO-OFICINAS' and me.activa
order by m.nombre;
