-- =========================================================
-- HISTÓRICO DE LOS CONTADORES DE SUMINISTRO DE LA TORRE DE DEMOSTRACIÓN
-- (solo desarrollo y demos; requiere docs/demo_torre_suministros.sql)
-- Pegar entero en el SQL Editor de Supabase y pulsar Run. Se puede ejecutar varias veces.
--
-- El simulador solo genera datos desde que está en marcha, así que el gráfico mensual de la
-- pestaña Suministros (este año frente al anterior) sale casi vacío. Este script rellena los
-- contadores del medidor general de electricidad, gas y agua con una lectura diaria
-- (a las 0:00, hora del edificio) desde el 1 de enero del año pasado hasta la primera lectura
-- que ya existe:
--   · el consumo diario de partida es la media de los datos reales del simulador;
--   · se modula por mes (gas: mucho más en invierno; electricidad: algo más en verano e
--     invierno; agua: algo más en verano), por día de la semana (fin de semana, menos) y con
--     una variación fija de ±8 % por día;
--   · las lecturas se calculan HACIA ATRÁS desde la primera real, así que el contador sigue
--     siendo continuo y creciente.
-- Entran por procesar_lecturas(…, histórico) como cualquier histórico: el motor recalcula los
-- resúmenes de esos días en los siguientes ciclos.
-- =========================================================

drop table if exists pg_temp.demo_resultado_hist;
create temp table demo_resultado_hist (sensor text, desde date, hasta date, lecturas int, guardadas int);

do $$
declare
  v_edif uuid;
  v_z text;
  r record;
  v_t0 timestamptz;      -- primera lectura existente
  v_v0 double precision;
  v_media double precision;
  v_ratio double precision;
  v_dia date;
  v_desde date;
  v_hasta date;
  v_valor double precision;
  v_lote jsonb;
  v_res jsonb;
  v_n int;
  v_f double precision;
  -- factores por mes (enero … diciembre)
  c_elec constant double precision[] := '{1.12,1.08,1.00,0.93,0.95,1.08,1.20,1.15,1.02,0.94,1.00,1.10}';
  c_gas  constant double precision[] := '{1.85,1.65,1.30,0.85,0.45,0.25,0.20,0.20,0.30,0.70,1.25,1.70}';
  c_agua constant double precision[] := '{0.90,0.90,0.95,1.00,1.05,1.15,1.20,1.10,1.05,0.95,0.90,0.90}';
begin
  select id, zona_horaria into v_edif, v_z from public.edificios where codigo = 'DEMO-TORRE';
  if v_edif is null then
    raise exception 'No existe el edificio DEMO-TORRE: créelo antes con docs/demo_torre.sql';
  end if;
  v_desde := (pg_catalog.date_trunc('year', pg_catalog.now() at time zone v_z) - interval '1 year')::date;

  for r in
    -- Contador de consumo del medidor general de cada suministro
    select s.id, s.codigo, s.escala, su.tipo,
           coalesce(s.id_conexion, d.id_conexion) as id_conexion
    from public.suministros su
    join public.suministros_dispositivos sd on sd.id_suministro = su.id and sd.activo and sd.medidor_general
    join public.dispositivos d on d.id = sd.id_dispositivo
    join public.sensores s on s.id_dispositivo = d.id and s.activo
    join public.parametros_medidor pm on pm.id = s.id_parametro_medidor and pm.consumo
    where su.id_edificio = v_edif and su.activo
  loop
    select l.fecha_hora, l.valor into v_t0, v_v0
    from public.lecturas l where l.id_sensor = r.id order by l.fecha_hora limit 1;
    if v_t0 is null then
      raise notice '% no tiene lecturas todavía: espere a que el simulador envíe datos', r.codigo;
      continue;
    end if;
    v_hasta := (v_t0 at time zone v_z)::date - 1;   -- último día a rellenar (a las 0:00)
    if v_hasta < v_desde then
      continue;   -- ya tiene histórico desde el año pasado
    end if;

    -- Consumo diario medio de los datos reales (mínimo, 2 días de datos)
    select (max(l.valor) - min(l.valor)) / nullif(extract(epoch from max(l.fecha_hora) - min(l.fecha_hora)) / 86400, 0)
      into v_media
    from public.lecturas l where l.id_sensor = r.id;
    if v_media is null or v_media <= 0
       or (select max(fecha_hora) - min(fecha_hora) from public.lecturas where id_sensor = r.id) < interval '2 days' then
      raise notice '% tiene menos de 2 días de datos: vuelva a ejecutar el script más adelante', r.codigo;
      continue;
    end if;

    -- procesar_lecturas aplica la escala del sensor (p. ej. litros → m³): se envía el valor de origen
    v_ratio := coalesce(r.escala, 1);

    -- Lecturas hacia atrás: la del día D es la primera real menos lo consumido desde D
    v_valor := v_v0;
    v_lote := '[]'::jsonb;
    v_n := 0;
    -- tramo entre la primera lectura y las 0:00 de su día
    v_valor := v_valor - v_media * extract(epoch from v_t0 - ((v_hasta + 1)::timestamp at time zone v_z)) / 86400;
    v_dia := v_hasta + 1;
    while v_dia > v_desde loop
      v_dia := v_dia - 1;
      v_f := case r.tipo when 'GAS' then c_gas[extract(month from v_dia)::int]
                         when 'ELECTRICIDAD' then c_elec[extract(month from v_dia)::int]
                         else c_agua[extract(month from v_dia)::int] end
             * case when extract(isodow from v_dia) in (6, 7) then case r.tipo when 'GAS' then 0.6 else 0.45 end else 1.12 end
             * (0.92 + 0.16 * ((pg_catalog.hashtext(r.codigo || v_dia::text) & 1023) / 1023.0));
      v_valor := v_valor - v_media * v_f;   -- consumo del día v_dia
      exit when v_valor < 0;                 -- el contador no puede bajar de 0
      v_lote := v_lote || pg_catalog.jsonb_build_object('id_sensor', r.id,
                  'fecha_hora', (v_dia::timestamp at time zone v_z), 'valor', v_valor / v_ratio);
      v_n := v_n + 1;
    end loop;

    v_res := public.procesar_lecturas(r.id_conexion, v_lote, true);
    insert into demo_resultado_hist values (r.codigo, greatest(v_dia, v_desde), v_hasta, v_n,
      coalesce((v_res->>'guardadas')::int, 0));
  end loop;
end;
$$;

select sensor as "Contador", desde as "Desde", hasta as "Hasta", lecturas as "Lecturas", guardadas as "Guardadas"
from demo_resultado_hist order by 1;
