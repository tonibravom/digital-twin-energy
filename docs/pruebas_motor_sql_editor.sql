-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DEL MOTOR DE CÁLCULO (migración 032)
-- Ejecutar con:  npx supabase test db
--
-- Edificio en Europe/Madrid. Día de prueba: martes 20/10/2026 (UTC+2).
--   ELEC  contador eléctrico cada 15 min, +2 kWh por intervalo   → 192 kWh/día
--   GAS   contador de gas en m³, lecturas horarias, +1 m³/hora  → 24 m³ = 280,8 kWh
--   FV    contador fotovoltaico en Wh, +500 Wh cada 15 min       → 48 kWh/día
--   POT   potencia instantánea (kW): 10 y 20 en cada intervalo → media 15
--   CLIMA submedidor eléctrico de climatización, +1 kWh/15 min  → 96 kWh/día
-- Domingo 25/10/2026: cambio de hora (25 horas = 100 intervalos).
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(25);

insert into proveedores (id, codigo, nombre) values ('fa000000-0000-0000-0000-00000000000a', 'MP', 'Partner motor');
insert into clientes (id, codigo, nombre) values ('fa100000-0000-0000-0000-000000000001', 'MC', 'Cliente motor');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fa200000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000001', 'ME', 'Edificio motor', 'Europe/Madrid'),
  ('fa200000-0000-0000-0000-000000000002', 'fa100000-0000-0000-0000-000000000001', 'MS', 'Edificio sin magnitudes', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('fa300000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'P0', 'PB'),
  ('fa300000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000002', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('fa400000-0000-0000-0000-000000000001', 'fa300000-0000-0000-0000-000000000001', 'R1', 'Sala'),
  ('fa400000-0000-0000-0000-000000000002', 'fa300000-0000-0000-0000-000000000002', 'R1', 'Sala');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select x.id::uuid, x.ed::uuid, t.id, 'HTTP', 'Gateway'
from (values ('fa700000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001'),
             ('fa700000-0000-0000-0000-000000000002', 'fa200000-0000-0000-0000-000000000002')) x(id, ed),
     tipos_conexion t where t.codigo = 'ENVIO_HTTP';

insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento,
                      id_tipo_energia, codigo, nombre, unidad, direccion)
select x.id::uuid, x.con::uuid, x.rec::uuid, f.id, n.id, t.id, te.id, x.cod, x.cod, x.uni,
       jsonb_build_object('clave', x.cod)
from (values
  ('fa800000-0000-0000-0000-000000000001', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'ELEC', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'ELECTRICIDAD', 'kWh'),
  ('fa800000-0000-0000-0000-000000000002', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'GAS', 'OTRA', 'ACUMULATIVA', 'DELTA', 'GAS', 'm³'),
  ('fa800000-0000-0000-0000-000000000003', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'FV', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'ELECTRICIDAD', 'Wh'),
  ('fa800000-0000-0000-0000-000000000004', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'POT', 'POTENCIA', 'INSTANTANEA', 'PROMEDIO', 'ELECTRICIDAD', 'kW'),
  ('fa800000-0000-0000-0000-000000000005', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'CLIMA', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'ELECTRICIDAD', 'kWh'),
  ('fa800000-0000-0000-0000-000000000006', 'fa700000-0000-0000-0000-000000000001', 'fa400000-0000-0000-0000-000000000001', 'TEMP', 'TEMPERATURA', 'INSTANTANEA', 'PROMEDIO', null, '°C'),
  ('fa800000-0000-0000-0000-000000000009', 'fa700000-0000-0000-0000-000000000002', 'fa400000-0000-0000-0000-000000000002', 'OTRO', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'ELECTRICIDAD', 'kWh')
) x(id, con, rec, cod, fam, nat, tra, ene, uni)
join familias_sensor f on f.codigo = x.fam
join naturalezas_sensor n on n.codigo = x.nat
join tratamientos_sensor t on t.codigo = x.tra
left join tipos_energia te on te.codigo = x.ene;

-- Magnitudes del edificio y sus fuentes (CONSUMO_NETO = ELEC − FV, de magnitudes)
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'fa200000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('fa600000-0000-0000-0000-000000000001', 'CONSUMO_ELECTRICIDAD'),
             ('fa600000-0000-0000-0000-000000000002', 'CONSUMO_GAS'),
             ('fa600000-0000-0000-0000-000000000003', 'GENERACION_FOTOVOLTAICA'),
             ('fa600000-0000-0000-0000-000000000004', 'POTENCIA_TOTAL'),
             ('fa600000-0000-0000-0000-000000000005', 'ENERGIA_CONSUMIDA'),
             ('fa600000-0000-0000-0000-000000000006', 'ENERGIA_TOTAL')) x(id, cod)
join magnitudes m on m.codigo = x.cod;

-- Lecturas del 20/10 (y la de las 00:00 del 21/10, que cierra el último intervalo)
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000001', t, 1000 + 2 * row_number() over (order by t)
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '15 minutes') t;
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000002', t, 500 + row_number() over (order by t)
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '1 hour') t;
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000003', t, 500 * row_number() over (order by t)
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '15 minutes') t;
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000004', t, case when extract(minute from t)::integer % 15 = 0 then 10 else 20 end
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-20 23:55 Europe/Madrid', interval '5 minutes') t
where extract(minute from t)::integer % 15 in (0, 5);
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000005', t, row_number() over (order by t)
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '15 minutes') t;
insert into lecturas (id_sensor, fecha_hora, valor) values
  ('fa800000-0000-0000-0000-000000000006', timestamptz '2026-10-20 10:00 Europe/Madrid', 21.5),
  ('fa800000-0000-0000-0000-000000000009', timestamptz '2026-10-20 10:00 Europe/Madrid', 5);

-- =========================================================
-- 1. Cola: las lecturas anotan el recálculo de su edificio
-- =========================================================
insert into resultados (t) select is((select desde from motor_pendiente where id_edificio = 'fa200000-0000-0000-0000-000000000001'),
  timestamptz '2026-10-20 00:00 Europe/Madrid', 'Las lecturas nuevas anotan el edificio en la cola desde la más antigua');

delete from motor_pendiente where id_edificio = 'fa200000-0000-0000-0000-000000000001';

-- Al asignar fuentes se recalcula todo el histórico de esos sensores
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor) values
  ('fa600000-0000-0000-0000-000000000001', 'fa800000-0000-0000-0000-000000000001'),
  ('fa600000-0000-0000-0000-000000000002', 'fa800000-0000-0000-0000-000000000002'),
  ('fa600000-0000-0000-0000-000000000003', 'fa800000-0000-0000-0000-000000000003'),
  ('fa600000-0000-0000-0000-000000000004', 'fa800000-0000-0000-0000-000000000004'),
  ('fa600000-0000-0000-0000-000000000006', 'fa800000-0000-0000-0000-000000000006');
insert into magnitudes_fuentes (id_magnitud_edificio, id_magnitud_origen, papel) values
  ('fa600000-0000-0000-0000-000000000005', 'fa600000-0000-0000-0000-000000000001', 'FUENTE'),
  ('fa600000-0000-0000-0000-000000000005', 'fa600000-0000-0000-0000-000000000003', 'RESTA');
update sensores set id_uso_energia = (select id from usos_energia where codigo = 'HVAC_CLIMATIZACION')
 where id = 'fa800000-0000-0000-0000-000000000005';

insert into resultados (t) select is((select motivo || ' ' || (desde = timestamptz '2026-10-20 00:00 Europe/Madrid')::text
           from motor_pendiente where id_edificio = 'fa200000-0000-0000-0000-000000000001'),
  'CONFIGURACION true', 'Asignar fuentes anota el recálculo de todo su histórico');

-- =========================================================
-- 2. Cálculo del día
-- =========================================================
insert into resultados (t) select ok((motor_calcular('fa200000-0000-0000-0000-000000000001',
                          timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid')
           ->'avisos') @> '["Sensor TEMP: no se puede pasar de °C a kWh"]'::jsonb,
  'Una unidad incompatible no se calcula y se avisa');

insert into resultados (t) select is((select count(*)::integer || ' ' || sum(valor)::text from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000001'),
  '96 192', 'Contador cada 15 min: 96 intervalos y 192 kWh');
insert into resultados (t) select is((select min(valor)::text || '-' || max(valor)::text from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000001'),
  '2-2', 'Cada intervalo es la diferencia entre lecturas');

insert into resultados (t) select is((select count(*)::integer || ' ' || round(sum(valor)::numeric, 1)::text from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000002'),
  '96 280.8', 'Gas horario en m³: repartido en 15 min y pasado a kWh (11,70 kWh/m³)');
insert into resultados (t) select is((select max(calidad) from valores_magnitud where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000002'),
  0::smallint, 'Lecturas cada hora: calidad válida');

insert into resultados (t) select is((select round(sum(valor)::numeric, 3) from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000003'),
  48.000, 'Fotovoltaica en Wh pasada a kWh');

insert into resultados (t) select is((select round(avg(valor)::numeric, 3) from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000004'),
  15.000, 'Potencia: media de las lecturas de cada intervalo');

insert into resultados (t) select is((select round(sum(valor)::numeric, 3) from valores_magnitud
           where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000005'),
  144.000, 'Magnitud con fuentes que suman y restan (192 − 48)');

-- =========================================================
-- 3. Resúmenes diarios
-- =========================================================
insert into resultados (t) select is((select string_agg(indicador || '=' || round(valor::numeric, 1) || (case when completo then '' else '*' end), ' ' order by indicador)
           from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001' and fecha = date '2026-10-20'),
  'CONSUMO_ELECTRICIDAD=192.0 CONSUMO_GAS=280.8 GENERACION_FOTOVOLTAICA=48.0',
  'Resúmenes del día local: electricidad, gas y fotovoltaica completos');

insert into resultados (t) select is((select valor from resumenes_diarios_usos
           where id_edificio = 'fa200000-0000-0000-0000-000000000001' and fecha = date '2026-10-20'
             and tipo_energia = 'ELECTRICIDAD'
             and id_uso_energia = (select id from usos_energia where codigo = 'HVAC_CLIMATIZACION')),
  96::double precision, 'Submedidor de climatización: consumo medido por uso para el Sankey');

insert into resultados (t) select is((select round((kpis_ambito('EDIFICIO', 'fa200000-0000-0000-0000-000000000001', date '2026-10-20')
                    ->'indicadores'->0->>'valor')::numeric, 1)),
  520.8, 'Los KPIs del edificio ya muestran la energía consumida (importada + gas + renovable)');

-- Recalcular no duplica
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid');
insert into resultados (t) select is((select sum(valor) from valores_magnitud where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000001'),
  192::double precision, 'Recalcular el mismo periodo no duplica valores');

-- =========================================================
-- 4. Casos especiales
-- =========================================================
-- Hueco de 3 horas en el contador: se reparte como ESTIMADO; el día sigue teniendo todos los intervalos
delete from lecturas where id_sensor = 'fa800000-0000-0000-0000-000000000001'
  and fecha_hora > timestamptz '2026-10-20 10:00 Europe/Madrid' and fecha_hora < timestamptz '2026-10-20 13:00 Europe/Madrid';
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid');
insert into resultados (t) select is((select count(*) filter (where calidad = 1)::integer || ' ' || round(sum(valor)::numeric, 1)::text
           from valores_magnitud where id_magnitud_edificio = 'fa600000-0000-0000-0000-000000000001'),
  '12 192.0', 'Un hueco de 3 horas se reparte (12 intervalos estimados) sin perder consumo');

-- Reinicio del contador: ese tramo se descarta y el día queda incompleto
update lecturas set valor = 3 where id_sensor = 'fa800000-0000-0000-0000-000000000001'
  and fecha_hora >= timestamptz '2026-10-20 20:00 Europe/Madrid';
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid');
insert into resultados (t) select is((select completo from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001'
             and fecha = date '2026-10-20' and indicador = 'CONSUMO_ELECTRICIDAD'),
  false, 'Si el contador baja (reinicio) se descarta ese tramo y el día queda incompleto');

-- Cambio de hora (25/10): el día local tiene 100 intervalos
insert into lecturas (id_sensor, fecha_hora, valor)
select 'fa800000-0000-0000-0000-000000000003', t, 100000 + 500 * row_number() over (order by t)
from generate_series(timestamptz '2026-10-25 00:00 Europe/Madrid', timestamptz '2026-10-26 00:00 Europe/Madrid', interval '15 minutes') t;
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-25 00:00 Europe/Madrid', timestamptz '2026-10-26 00:00 Europe/Madrid');
insert into resultados (t) select is((select round(valor::numeric, 1)::text || ' ' || completo::text from resumenes_diarios
           where id_edificio = 'fa200000-0000-0000-0000-000000000001' and fecha = date '2026-10-25'
             and indicador = 'GENERACION_FOTOVOLTAICA'),
  '50.0 true', 'Día del cambio de hora: 25 horas (100 intervalos) y completo');

-- Un resumen importado no se pisa
insert into resumenes_diarios (id_edificio, fecha, indicador, valor, origen) values
  ('fa200000-0000-0000-0000-000000000001', date '2026-10-25', 'CONSUMO_AGUA', 7, 'IMPORTACION_DIARIA'),
  ('fa200000-0000-0000-0000-000000000001', date '2026-10-25', 'CONSUMO_GAS', 999, 'IMPORTACION_DIARIA');
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-25 00:00 Europe/Madrid', timestamptz '2026-10-26 00:00 Europe/Madrid');
insert into resultados (t) select is((select valor from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001'
             and fecha = date '2026-10-25' and indicador = 'CONSUMO_GAS'),
  999::double precision, 'El motor no sobrescribe resúmenes importados');

-- Sustitución de un sensor: el contador nuevo empieza de cero y el histórico se conserva
select sustituir_sensor('fa800000-0000-0000-0000-000000000003');
insert into lecturas (id_sensor, fecha_hora, valor)
select (select id from sensores where id_sensor_anterior = 'fa800000-0000-0000-0000-000000000003'), t,
       500 * (row_number() over (order by t) - 1)
from generate_series(timestamptz '2026-10-26 00:00 Europe/Madrid', timestamptz '2026-10-27 00:00 Europe/Madrid', interval '15 minutes') t;
select motor_calcular('fa200000-0000-0000-0000-000000000001',
                      timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-27 00:00 Europe/Madrid');
insert into resultados (t) select is((select string_agg(fecha::text || '=' || round(valor::numeric, 1)
                                || case when completo then '' else '*' end, ' ' order by fecha)
           from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001'
             and indicador = 'GENERACION_FOTOVOLTAICA'),
  '2026-10-20=48.0 2026-10-21=13.0* 2026-10-22=13.0* 2026-10-23=13.0* 2026-10-24=13.0* 2026-10-25=50.0 2026-10-26=48.0',
  'Tras sustituir un sensor se conserva el histórico del antiguo, sin mezclar contadores (21-24: hueco de 4 días repartido como estimado)');

-- =========================================================
-- 5. Ejecución por la cola
-- =========================================================
delete from motor_pendiente;
delete from recalculos_pendientes;
insert into lecturas (id_sensor, fecha_hora, valor) values
  ('fa800000-0000-0000-0000-000000000009', timestamptz '2026-10-20 10:15 Europe/Madrid', 7);
insert into resultados (t) select ok(motor_procesar_siguiente() ? 'sin_configuracion', 'Un edificio sin magnitudes ni submedidores sale de la cola sin calcular');
insert into resultados (t) select is((select count(*)::integer from motor_pendiente), 0, 'Al terminar, el edificio sale de la cola');
insert into resultados (t) select is((select count(*)::integer from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000002'), 0,
  'Un edificio sin magnitudes configuradas no genera resúmenes');

-- Recálculo pedido expresamente (importaciones)
insert into recalculos_pendientes (id_edificio, desde, hasta, motivo)
values ('fa200000-0000-0000-0000-000000000001', timestamptz '2026-10-26 00:00 Europe/Madrid', now(), 'IMPORTACION_HISTORICO');
delete from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001' and fecha = date '2026-10-26';
insert into resultados (t) select is((motor_procesar_siguiente()->>'terminado')::boolean, true, 'Los recálculos pedidos pasan a la cola del motor y se procesan');
insert into resultados (t) select is((select count(*)::integer from resumenes_diarios where id_edificio = 'fa200000-0000-0000-0000-000000000001'
             and fecha = date '2026-10-26'), 1, 'El recálculo vuelve a generar los resúmenes del periodo');

-- =========================================================
-- 6. Permisos
-- =========================================================
set local role authenticated;
insert into resultados (t) select throws_ok($$ select motor_calcular('fa200000-0000-0000-0000-000000000001', now() - interval '1 day') $$,
  '42501', null, 'Los usuarios no pueden lanzar el motor');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 25 then
    raise exception 'RESULTADO: % de 25 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
