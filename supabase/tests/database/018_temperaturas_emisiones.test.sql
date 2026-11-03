-- =========================================================
-- PRUEBAS DE TEMPERATURAS CONFIGURABLES Y EMISIONES POR FUENTE (migración 036)
-- Ejecutar con:  npx supabase test db
-- Edificio en Europe/Madrid sin calendario (lunes a viernes laborables).
-- "Ahora" = martes 20/10/2026 10:07 → día comparable lunes 19/10.
-- =========================================================
begin;
set search_path = public, extensions;

select plan(12);

insert into proveedores (id, codigo, nombre) values ('fe000000-0000-0000-0000-00000000000a', 'TP', 'Partner temperaturas');
insert into clientes (id, codigo, nombre) values ('fe100000-0000-0000-0000-000000000001', 'TC', 'Cliente temperaturas');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fe200000-0000-0000-0000-000000000001', 'fe100000-0000-0000-0000-000000000001', 'TE', 'Edificio temperaturas', 'Europe/Madrid');

-- =========================================================
-- 1. Temperaturas por temporada
-- =========================================================
select is((select array[temp_eficiencia_invierno, temp_confort_invierno, temp_eficiencia_verano, temp_confort_verano]
           from edificios where id = 'fe200000-0000-0000-0000-000000000001'),
  array[19, 25, 27, 25]::numeric[], 'Valores por defecto: RITE (19 °C y 27 °C) y confort 25 °C');

-- Otro país: eficiencia 20 °C y confort 22 °C en invierno; 26 °C y 24 °C en verano
update edificios set temp_eficiencia_invierno = 20, temp_confort_invierno = 22, temp_eficiencia_verano = 26, temp_confort_verano = 24,
       invierno_desde = '01-01', invierno_hasta = '12-31'
where id = 'fe200000-0000-0000-0000-000000000001';
select is(estado_temperatura(20, 'INVIERNO', 20, 22) || estado_temperatura(21, 'INVIERNO', 20, 22) || estado_temperatura(22.5, 'INVIERNO', 20, 22),
  'VERDENARANJAROJO', 'Invierno con otros límites: ≤ eficiencia verde, ≤ confort naranja, más rojo');
select is(estado_temperatura(26, 'VERANO', 26, 24) || estado_temperatura(24, 'VERANO', 26, 24) || estado_temperatura(23.9, 'VERANO', 26, 24),
  'VERDENARANJAROJO', 'Verano con otros límites: ≥ eficiencia verde, ≥ confort naranja, menos rojo');
select is(ambiente_edificio('fe200000-0000-0000-0000-000000000001') - 'recintos',
  '{"temporada": "INVIERNO", "temperatura_eficiencia": 20.0, "temperatura_confort": 22.0}'::jsonb,
  'El ambiente devuelve la eficiencia y el confort de la temporada en curso');
select throws_ok($$ update edificios set temp_eficiencia_invierno = 23 where id = 'fe200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'Invierno: la eficiencia no puede superar el confort');
select throws_ok($$ update edificios set temp_eficiencia_verano = 40 where id = 'fe200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'Temperaturas fuera de un rango razonable');

-- =========================================================
-- 2. Fuentes: aporte y emisiones
-- =========================================================
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'fe200000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('fe600000-0000-0000-0000-000000000001', 'CONSUMO_ELECTRICIDAD'),
             ('fe600000-0000-0000-0000-000000000002', 'CONSUMO_GAS'),
             ('fe600000-0000-0000-0000-000000000003', 'GENERACION_FOTOVOLTAICA')) x(id, cod)
join magnitudes m on m.codigo = x.cod;
insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor) values
  ('fe600000-0000-0000-0000-000000000001', timestamptz '2026-10-20 09:00 Europe/Madrid', 60),
  ('fe600000-0000-0000-0000-000000000002', timestamptz '2026-10-20 09:00 Europe/Madrid', 30),
  ('fe600000-0000-0000-0000-000000000003', timestamptz '2026-10-20 09:00 Europe/Madrid', 10),
  ('fe600000-0000-0000-0000-000000000001', timestamptz '2026-10-19 09:00 Europe/Madrid', 50);

create temp table f as
select fuentes_hoy_edificio('fe200000-0000-0000-0000-000000000001', timestamptz '2026-10-20 10:07 Europe/Madrid') as j;

select is((select j->>'total_kwh' from f)::numeric, 100::numeric, 'Energía consumida total: electricidad + gas + renovable');
select is((select jsonb_agg((x->>'aporte_pct')::numeric) from f, jsonb_array_elements(j->'fuentes') x),
  '[60, 30, 10]'::jsonb, 'Aporte de cada fuente al total (%)');
select is((select (j->'fuentes'->0->>'emisiones_kg')::numeric from f),
  round(60 * factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-10-20'), 1), 'Emisiones de la electricidad de la red');
select is((select (j->'fuentes'->1->>'emisiones_kg')::numeric from f),
  round(30 * factor_co2('FACTOR_CO2_GAS', date '2026-10-20'), 1), 'Emisiones del gas');
select is((select j->'fuentes'->2->'emisiones_kg' from f), 'null'::jsonb, 'Las renovables no emiten');
select is((select (j->>'emisiones_kg')::numeric from f),
  round(60 * factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-10-20') + 30 * factor_co2('FACTOR_CO2_GAS', date '2026-10-20'), 1),
  'Emisiones totales = electricidad + gas');

select * from finish();
rollback;
