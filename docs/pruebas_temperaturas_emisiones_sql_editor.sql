-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE TEMPERATURAS CONFIGURABLES Y EMISIONES POR FUENTE (migraciones 036 y 043)
-- Ejecutar con:  npx supabase test db
-- Edificio en Europe/Madrid sin calendario (lunes a viernes laborables).
-- "Ahora" = martes 20/10/2026 10:07 → día comparable lunes 19/10.
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(12);

insert into proveedores (id, codigo, nombre) values ('fe000000-0000-0000-0000-00000000000a', 'TP', 'Partner temperaturas');
insert into clientes (id, codigo, nombre) values ('fe100000-0000-0000-0000-000000000001', 'TC', 'Cliente temperaturas');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fe200000-0000-0000-0000-000000000001', 'fe100000-0000-0000-0000-000000000001', 'TE', 'Edificio temperaturas', 'Europe/Madrid');

-- =========================================================
-- 1. Temperaturas por temporada
-- =========================================================
insert into resultados (t) select is((select array[temp_eficiencia_invierno, temp_eficiencia_verano]
           from edificios where id = 'fe200000-0000-0000-0000-000000000001'),
  array[19, 26]::numeric[], 'Valores por defecto: Te de 19 °C en invierno y 26 °C en verano (D55)');

-- Otro edificio: Te de 20 °C en invierno y 25 °C en verano; los tramos se desplazan con la Te
update edificios set temp_eficiencia_invierno = 20, temp_eficiencia_verano = 25,
       invierno_desde = '01-01', invierno_hasta = '12-31'
where id = 'fe200000-0000-0000-0000-000000000001';
insert into resultados (t) select is(estado_temperatura(20, 'INVIERNO', 20) || '/' || estado_temperatura(21, 'INVIERNO', 20) || '/' || estado_temperatura(22.5, 'INVIERNO', 20)
          || '/' || estado_temperatura(24, 'INVIERNO', 20) || '/' || estado_temperatura(24.1, 'INVIERNO', 20),
  'EFICIENTE/LEVE/MODERADO/ALTO/MUY_ALTO', 'Invierno con Te 20: +1, +2,5, +4 y más');
insert into resultados (t) select is(estado_temperatura(25, 'VERANO', 25) || '/' || estado_temperatura(24, 'VERANO', 25) || '/' || estado_temperatura(22.5, 'VERANO', 25)
          || '/' || estado_temperatura(21, 'VERANO', 25) || '/' || estado_temperatura(20.9, 'VERANO', 25),
  'EFICIENTE/LEVE/MODERADO/ALTO/MUY_ALTO', 'Verano con Te 25: −1, −2,5, −4 y menos');
insert into resultados (t) select is(ambiente_edificio('fe200000-0000-0000-0000-000000000001') - 'recintos' - 'volumenes',
  '{"temporada": "INVIERNO", "temperatura_eficiencia": 20.0}'::jsonb,
  'El ambiente devuelve la Te de la temporada en curso (sin temperatura de confort)');
insert into resultados (t) select throws_ok($$ update edificios set temp_eficiencia_invierno = 18.5 where id = 'fe200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'La Te de invierno no baja de 19 °C');
insert into resultados (t) select throws_ok($$ update edificios set temp_eficiencia_verano = 27.5 where id = 'fe200000-0000-0000-0000-000000000001' $$,
  '23514', null, 'La Te de verano no pasa de 27 °C');

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

insert into resultados (t) select is((select j->>'total_kwh' from f)::numeric, 100::numeric, 'Energía consumida total: electricidad + gas + renovable');
insert into resultados (t) select is((select jsonb_agg((x->>'aporte_pct')::numeric) from f, jsonb_array_elements(j->'fuentes') x),
  '[60, 30, 10]'::jsonb, 'Aporte de cada fuente al total (%)');
insert into resultados (t) select is((select (j->'fuentes'->0->>'emisiones_kg')::numeric from f),
  round(60 * factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-10-20'), 1), 'Emisiones de la electricidad de la red');
insert into resultados (t) select is((select (j->'fuentes'->1->>'emisiones_kg')::numeric from f),
  round(30 * factor_co2('FACTOR_CO2_GAS', date '2026-10-20'), 1), 'Emisiones del gas');
insert into resultados (t) select is((select j->'fuentes'->2->'emisiones_kg' from f), 'null'::jsonb, 'Las renovables no emiten');
insert into resultados (t) select is((select (j->>'emisiones_kg')::numeric from f),
  round(60 * factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-10-20') + 30 * factor_co2('FACTOR_CO2_GAS', date '2026-10-20'), 1),
  'Emisiones totales = electricidad + gas');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 12 then
    raise exception 'RESULTADO: % de 12 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
