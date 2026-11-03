-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DEL PANEL DEL EDIFICIO (migraciones 034 y 036)
-- Ejecutar con:  npx supabase test db
-- Edificio en Europe/Madrid; invierno 01/11–31/03 (eficiencia 19 °C,
-- confort 25 °C) y verano 01/06–30/09 (eficiencia 27 °C, confort 25 °C).
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(20);

insert into proveedores (id, codigo, nombre) values ('fc000000-0000-0000-0000-00000000000a', 'AP', 'Partner panel');
insert into clientes (id, codigo, nombre) values ('fc100000-0000-0000-0000-000000000001', 'AC', 'Cliente panel');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fc200000-0000-0000-0000-000000000001', 'fc100000-0000-0000-0000-000000000001', 'AE', 'Edificio panel', 'Europe/Madrid');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fc300000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'P1', 'Planta 1', 1),
  ('fc300000-0000-0000-0000-000000000000', 'fc200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fc400000-0000-0000-0000-000000000001', 'fc300000-0000-0000-0000-000000000001', 'OF', 'Oficina'),
  ('fc400000-0000-0000-0000-000000000002', 'fc300000-0000-0000-0000-000000000000', 'VE', 'Vestíbulo');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fc700000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', id, 'HTTP', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select x.id::uuid, 'fc700000-0000-0000-0000-000000000001', x.rec::uuid, f.id, n.id, t.id, x.cod, x.cod, x.uni,
       jsonb_build_object('clave', x.cod)
from (values
  ('fc800000-0000-0000-0000-000000000001', 'fc400000-0000-0000-0000-000000000001', 'T1', 'TEMPERATURA', '°C'),
  ('fc800000-0000-0000-0000-000000000002', 'fc400000-0000-0000-0000-000000000001', 'T2', 'TEMPERATURA', '°C'),
  ('fc800000-0000-0000-0000-000000000003', 'fc400000-0000-0000-0000-000000000001', 'H1', 'HUMEDAD', '%'),
  ('fc800000-0000-0000-0000-000000000004', 'fc400000-0000-0000-0000-000000000001', 'C1', 'CO2', 'ppm'),
  ('fc800000-0000-0000-0000-000000000005', 'fc400000-0000-0000-0000-000000000002', 'T3', 'TEMPERATURA', '°C')
) x(id, rec, cod, fam, uni)
join familias_sensor f on f.codigo = x.fam
join naturalezas_sensor n on n.codigo = 'INSTANTANEA'
join tratamientos_sensor t on t.codigo = 'PROMEDIO';
insert into estado_comunicacion (id_sensor, estado, ultima_lectura, ultimo_valor, fecha_cambio_estado, umbral_minutos) values
  ('fc800000-0000-0000-0000-000000000001', 'COMUNICANDO', now(), 22, now(), 30),
  ('fc800000-0000-0000-0000-000000000002', 'COMUNICANDO', now(), 23, now(), 30),
  ('fc800000-0000-0000-0000-000000000003', 'COMUNICANDO', now(), 75, now(), 30),
  ('fc800000-0000-0000-0000-000000000004', 'COMUNICANDO', now(), 850, now(), 30),
  ('fc800000-0000-0000-0000-000000000005', 'SIN_COMUNICACION', now() - interval '3 hours', 18.5, now(), 30);

-- =========================================================
-- 1. Temporadas y colores
-- =========================================================
insert into resultados (t) select is(temporada_edificio('fc200000-0000-0000-0000-000000000001', date '2026-12-15'), 'INVIERNO', 'Invierno que cruza el año (diciembre)');
insert into resultados (t) select is(temporada_edificio('fc200000-0000-0000-0000-000000000001', date '2027-02-01'), 'INVIERNO', 'Invierno que cruza el año (febrero)');
insert into resultados (t) select is(temporada_edificio('fc200000-0000-0000-0000-000000000001', date '2026-07-20'), 'VERANO', 'Verano');
insert into resultados (t) select is(temporada_edificio('fc200000-0000-0000-0000-000000000001', date '2026-10-15'), null, 'Entre temporadas no hay KPI de temperatura');

insert into resultados (t) select is(estado_temperatura(19, 'INVIERNO', 19, 25) || estado_temperatura(22, 'INVIERNO', 19, 25) || estado_temperatura(25, 'INVIERNO', 19, 25)
          || estado_temperatura(25.1, 'INVIERNO', 19, 25),
  'VERDENARANJANARANJAROJO', 'Invierno: ≤19 verde, hasta el confort naranja, por encima rojo');
insert into resultados (t) select is(estado_temperatura(27, 'VERANO', 27, 25) || estado_temperatura(26, 'VERANO', 27, 25) || estado_temperatura(25, 'VERANO', 27, 25)
          || estado_temperatura(24.9, 'VERANO', 27, 25),
  'VERDENARANJANARANJAROJO', 'Verano: ≥27 verde, desde el confort naranja, por debajo rojo');
insert into resultados (t) select is(estado_temperatura(22, null, 19, 25), null, 'Fuera de temporada la temperatura no tiene color');
insert into resultados (t) select is(estado_humedad(30) || estado_humedad(70) || estado_humedad(29) || estado_humedad(71), 'VERDEVERDEROJOROJO',
  'Humedad: 30–70 % verde, fuera rojo');

insert into resultados (t) select throws_ok($$ update edificios set temp_confort_invierno = 19 where id = 'fc200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'En invierno el confort debe ser mayor que la eficiencia');
insert into resultados (t) select throws_ok($$ update edificios set temp_confort_verano = 27 where id = 'fc200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'En verano el confort debe ser menor que la eficiencia');
insert into resultados (t) select throws_ok($$ update edificios set invierno_desde = '13-01' where id = 'fc200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'Las fechas de temporada deben ser MM-DD válidas');

-- =========================================================
-- 2. Ambiente por recinto
-- =========================================================
insert into resultados (t) select is((select jsonb_agg(r->>'recinto') from jsonb_array_elements(ambiente_edificio('fc200000-0000-0000-0000-000000000001')->'recintos') r),
  '["Vestíbulo", "Oficina"]'::jsonb, 'Recintos ordenados de la planta más baja a la más alta');
insert into resultados (t) select is((ambiente_edificio('fc200000-0000-0000-0000-000000000001')->'recintos'->1->'temperatura'->>'valor')::numeric,
  22.5, 'Con dos sondas en el recinto se muestra la media');
insert into resultados (t) select is(ambiente_edificio('fc200000-0000-0000-0000-000000000001')->'recintos'->1->'humedad'->>'estado',
  'ROJO', 'Humedad del 75 %: rojo');
insert into resultados (t) select is(ambiente_edificio('fc200000-0000-0000-0000-000000000001')->'recintos'->1->'co2'->>'valor',
  '850', 'El CO₂ se muestra sin color');
insert into resultados (t) select is(ambiente_edificio('fc200000-0000-0000-0000-000000000001')->'recintos'->0->'humedad',
  'null'::jsonb, 'Un recinto sin sonda de humedad no la muestra');

-- =========================================================
-- 3. Alarmas: sensores sin comunicación y alarmas activas
-- =========================================================
insert into incidencias_comunicacion (id_sensor, fecha_inicio) values ('fc800000-0000-0000-0000-000000000005', now() - interval '2 hours');
insert into reglas_alarma (id, id_edificio, id_sensor, codigo, nombre, condicion, umbral, id_nivel_alarma)
select 'fc900000-0000-0000-0000-000000000001', 'fc200000-0000-0000-0000-000000000001', 'fc800000-0000-0000-0000-000000000004',
       'CO2_ALTO', 'CO₂ alto en la oficina', 'MAYOR_QUE', 800, n.id
from niveles_alarma n where n.codigo = 'IMPORTANTE';
insert into eventos_alarma (id_regla_alarma, id_sensor, valor_detectado, mensaje)
values ('fc900000-0000-0000-0000-000000000001', 'fc800000-0000-0000-0000-000000000004', 850, 'CO₂ 850 ppm');

insert into resultados (t) select is((select jsonb_agg(a->>'tipo') from jsonb_array_elements(alarmas_edificio('fc200000-0000-0000-0000-000000000001')) a),
  '["ALARMA", "COMUNICACION"]'::jsonb, 'Alarmas ordenadas por importancia: primero la alarma, después la falta de comunicación');
insert into resultados (t) select is(alarmas_edificio('fc200000-0000-0000-0000-000000000001')->1->>'recinto', 'Vestíbulo',
  'La falta de comunicación indica sensor y recinto');

-- =========================================================
-- 4. Fuentes de hoy y agrupación semanal
-- =========================================================
insert into resultados (t) select is(fuentes_hoy_edificio('fc200000-0000-0000-0000-000000000001')->'fuentes', '[]'::jsonb,
  'Sin magnitudes configuradas no se muestran fuentes');
insert into resultados (t) select is((select count(*)::integer from serie_sensor('fc800000-0000-0000-0000-000000000001',
            now() - interval '30 days', now(), 'semana')), 0, 'Las series admiten la agrupación por semana');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 20 then
    raise exception 'RESULTADO: % de 20 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
