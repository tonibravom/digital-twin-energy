-- =========================================================
-- PRUEBAS DE LAS SERIES DE ENERGÍA DEL PANEL Y DEL DÍA COMPARABLE INCOMPLETO (migración 038)
-- Ejecutar con:  npx supabase test db
--
-- Mismo edificio que 019 (martes 20/10/2026, contadores cada 15 min):
--   general 20 · cuadro PB 6 (alumbrado 1) · local 2 (alumbrado 0,5) · planta 1 8 (alumbrado 2)
--   informática 1 (cuadro sin medidor colgado del de planta 1) · gas de caldera 3
-- Por día: alumbrado P1 192 · otros PB 288 · local 144 · P1 480 · informática 96 · no medido 576
-- =========================================================
begin;
set search_path = public, extensions;

select plan(19);

insert into proveedores (id, codigo, nombre) values
  ('f1000000-0000-0000-0000-00000000000a', 'QA', 'Partner cuadros A'),
  ('f1000000-0000-0000-0000-00000000000b', 'QB', 'Partner cuadros B');
insert into clientes (id, codigo, nombre) values ('f1100000-0000-0000-0000-000000000001', 'QC', 'Cliente cuadros');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('f1000000-0000-0000-0000-00000000000a', 'f1100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('f1200000-0000-0000-0000-000000000001', 'f1100000-0000-0000-0000-000000000001', 'QE', 'Edificio cuadros', 'Europe/Madrid'),
  ('f1200000-0000-0000-0000-000000000002', 'f1100000-0000-0000-0000-000000000001', 'QO', 'Otro edificio', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('f1000000-0000-0000-0000-00000000000a', 'f1200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('f1300000-0000-0000-0000-000000000000', 'f1200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0),
  ('f1300000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', 'P1', 'Planta 1', 1),
  ('f1300000-0000-0000-0000-000000000009', 'f1200000-0000-0000-0000-000000000002', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('f1400000-0000-0000-0000-000000000000', 'f1300000-0000-0000-0000-000000000000', 'VE', 'Vestíbulo'),
  ('f1400000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000000', 'LO', 'Local comercial'),
  ('f1400000-0000-0000-0000-000000000002', 'f1300000-0000-0000-0000-000000000001', 'OF', 'Oficina'),
  ('f1400000-0000-0000-0000-000000000009', 'f1300000-0000-0000-0000-000000000009', 'X', 'Otro');
insert into cuadros_electricos (id, id_edificio, id_planta, id_recinto, id_cuadro_padre, codigo, nombre) values
  ('f1500000-0000-0000-0000-000000000000', 'f1200000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000000', null, null, 'CPB', 'Cuadro planta baja'),
  ('f1500000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', null, 'f1400000-0000-0000-0000-000000000001', 'f1500000-0000-0000-0000-000000000000', 'CLOC', 'Cuadro del local'),
  ('f1500000-0000-0000-0000-000000000002', 'f1200000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000001', null, null, 'CP1', 'Cuadro planta 1'),
  ('f1500000-0000-0000-0000-000000000003', 'f1200000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000001', null, 'f1500000-0000-0000-0000-000000000002', 'CNM', 'Cuadro de informática'),
  ('f1500000-0000-0000-0000-000000000009', 'f1200000-0000-0000-0000-000000000002', 'f1300000-0000-0000-0000-000000000009', null, null, 'CX', 'Cuadro de otro edificio');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'f1700000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', id, 'HTTP', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';

create function pg_temp.sensor(p_id text, p_cod text, p_rec text, p_ene text, p_funcion text, p_uso text, p_cuadro text)
returns void language sql as $$
  insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia,
                        codigo, nombre, unidad, direccion, funcion_medidor, id_uso_energia, id_cuadro)
  select p_id::uuid, 'f1700000-0000-0000-0000-000000000001', p_rec::uuid, f.id, n.id, t.id, te.id, p_cod, p_cod, 'kWh',
         jsonb_build_object('clave', p_cod), p_funcion, (select id from usos_energia where codigo = p_uso), p_cuadro::uuid
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA' and te.codigo = p_ene;
$$;
select pg_temp.sensor('f1800000-0000-0000-0000-000000000001', 'GEN', 'f1400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'GENERAL', null, null);
select pg_temp.sensor('f1800000-0000-0000-0000-000000000002', 'TPB', 'f1400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'CUADRO', null, 'f1500000-0000-0000-0000-000000000000');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000003', 'APB', 'f1400000-0000-0000-0000-000000000000', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'f1500000-0000-0000-0000-000000000000');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000004', 'TLOC', 'f1400000-0000-0000-0000-000000000001', 'ELECTRICIDAD', 'CUADRO', null, 'f1500000-0000-0000-0000-000000000001');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000005', 'ALOC', 'f1400000-0000-0000-0000-000000000001', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'f1500000-0000-0000-0000-000000000001');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000006', 'TP1', 'f1400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'CUADRO', null, 'f1500000-0000-0000-0000-000000000002');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000007', 'AP1', 'f1400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'USO', 'ILUMINACION', 'f1500000-0000-0000-0000-000000000002');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000008', 'INF', 'f1400000-0000-0000-0000-000000000002', 'ELECTRICIDAD', 'USO', 'INFORMATICA', 'f1500000-0000-0000-0000-000000000003');
select pg_temp.sensor('f1800000-0000-0000-0000-000000000009', 'GASC', 'f1400000-0000-0000-0000-000000000000', 'GAS', 'USO', 'HVAC_CALEFACCION_ACS', null);

insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select x.id::uuid, 'f1200000-0000-0000-0000-000000000001', m.id, 'EDIFICIO'
from (values ('f1600000-0000-0000-0000-000000000001', 'CONSUMO_ELECTRICIDAD'),
             ('f1600000-0000-0000-0000-000000000002', 'CONSUMO_GAS')) x(id, cod)
join magnitudes m on m.codigo = x.cod;
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor) values
  ('f1600000-0000-0000-0000-000000000001', 'f1800000-0000-0000-0000-000000000001'),
  ('f1600000-0000-0000-0000-000000000002', 'f1800000-0000-0000-0000-000000000009');

insert into lecturas (id_sensor, fecha_hora, valor)
select x.id::uuid, t, 1000 + x.inc * (row_number() over (partition by x.id order by t) - 1)
from (values ('f1800000-0000-0000-0000-000000000001', 20.0), ('f1800000-0000-0000-0000-000000000002', 6.0),
             ('f1800000-0000-0000-0000-000000000003', 1.0), ('f1800000-0000-0000-0000-000000000004', 2.0),
             ('f1800000-0000-0000-0000-000000000005', 0.5), ('f1800000-0000-0000-0000-000000000006', 8.0),
             ('f1800000-0000-0000-0000-000000000007', 2.0), ('f1800000-0000-0000-0000-000000000008', 1.0),
             ('f1800000-0000-0000-0000-000000000009', 3.0)) x(id, inc)
cross join generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', interval '15 minutes') t;

do $$ begin
  perform motor_calcular('f1200000-0000-0000-0000-000000000001',
                         timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid');
end $$;

create function pg_temp.dia(p_serie text) returns numeric language sql as $$
  select round(sum(valor)::numeric, 1) from serie_energia('f1200000-0000-0000-0000-000000000001', p_serie,
    timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', 'dia');
$$;

-- =========================================================
-- 1. Serie de 15 minutos por uso y cuadro
-- =========================================================
select is((select count(*)::integer || ' ' || round(min(valor)::numeric, 1) || ' ' || round(sum(valor)::numeric, 1) from valores_usos
           where id_edificio = 'f1200000-0000-0000-0000-000000000001' and id_cuadro = 'f1500000-0000-0000-0000-000000000002'
             and id_uso_energia = (select id from usos_energia where codigo = 'ILUMINACION')),
  '96 2.0 192.0', 'Alumbrado de la planta 1: 96 cuartos de hora de 2 kWh');
select is((select round(max(valor)::numeric, 1) from valores_usos
           where id_cuadro = 'f1500000-0000-0000-0000-000000000000'
             and id_uso_energia = (select id from usos_energia where codigo = 'OTROS_SIN_DESGLOSE')),
  3.0, 'Otros usos de planta baja en cada cuarto de hora: 6 − 1 − 2');
select is((select round(valor::numeric, 1) from resumenes_diarios_usos
           where id_cuadro = 'f1500000-0000-0000-0000-000000000000' and fecha = '2026-10-20'
             and id_uso_energia = (select id from usos_energia where codigo = 'OTROS_SIN_DESGLOSE')),
  288.0, 'El resumen diario (Sankey) es la suma de la serie');

-- =========================================================
-- 2. serie_energia: mismos datos que el Sankey
-- =========================================================
select is(pg_temp.dia('ILUMINACION:f1500000-0000-0000-0000-000000000002'), 192.0, 'Alumbrado · Planta 1');
select is(pg_temp.dia('ILUMINACION'), 336.0, 'Total alumbrado (grupo)');
select is(pg_temp.dia('INFORMATICA:f1500000-0000-0000-0000-000000000003'), 96.0, 'Informática en su cuadro');
select is(pg_temp.dia('OTROS_NO_MEDIDO'), 576.0, 'Otros usos · no medido = general − cuadros');
select is(pg_temp.dia('OTROS'), 1488.0, 'Total otros usos (sin uso determinado) = diferencias de los cuadros + no medido');
select is(pg_temp.dia('HVAC_CALEFACCION_ACS') || ' ' || pg_temp.dia('HVAC'), '288.0 288.0', 'Calefacción y ACS (gas) y total HVAC');
select is(pg_temp.dia('ENERGIA_CONSUMIDA'), 2208.0, 'Energía total consumida = 1.920 electricidad + 288 gas');
select is(pg_temp.dia('EMISIONES'),
  round((1920 * factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-10-20') + 288 * factor_co2('FACTOR_CO2_GAS', date '2026-10-20'))::numeric, 1),
  'Emisiones: electricidad de la red y gas');
select is((select count(*)::integer || ' ' || round(min(valor)::numeric, 1) from serie_energia('f1200000-0000-0000-0000-000000000001', 'RED',
             timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-21 00:00 Europe/Madrid', 'hora')),
  '24 80.0', 'Por horas: 24 valores de 80 kWh');
select throws_like($$ select * from serie_energia('f1200000-0000-0000-0000-000000000001', 'NO_EXISTE', now() - interval '1 day', now()) $$,
  '%Serie desconocida%', 'Una serie desconocida da un error claro');

-- =========================================================
-- 3. Series disponibles para el selector
-- =========================================================
select ok(series_energia_edificio('f1200000-0000-0000-0000-000000000001') @>
  '[{"id": "ILUMINACION:f1500000-0000-0000-0000-000000000002", "nombre": "Alumbrado · Planta 1", "grupo": "Alumbrado"},
    {"id": "HVAC", "nombre": "Total HVAC"}, {"id": "OTROS_NO_MEDIDO"}, {"id": "ENERGIA_CONSUMIDA", "grupo": "Edificio"}]'::jsonb,
  'El selector ofrece las series del edificio, del Sankey y de cada cuadro');
select ok(not series_energia_edificio('f1200000-0000-0000-0000-000000000001') @> '[{"id": "EXPORTADA"}]'::jsonb,
  'Sin contador de exportación no se ofrece la serie de exportada');

-- =========================================================
-- 4. Día comparable incompleto (martes 20/10 a las 10:07 frente al lunes 19/10)
-- =========================================================
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('f1200000-0000-0000-0000-000000000003', 'f1100000-0000-0000-0000-000000000001', 'QI', 'Edificio comparable', 'Europe/Madrid');
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select 'f1600000-0000-0000-0000-000000000009', 'f1200000-0000-0000-0000-000000000003', id, 'EDIFICIO'
from magnitudes where codigo = 'CONSUMO_ELECTRICIDAD';
insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor)
select 'f1600000-0000-0000-0000-000000000009'::uuid, t, 10
from generate_series(timestamptz '2026-10-20 00:00 Europe/Madrid', timestamptz '2026-10-20 09:45 Europe/Madrid', interval '15 minutes') t
union all
select 'f1600000-0000-0000-0000-000000000009'::uuid, t, 1
from generate_series(timestamptz '2026-10-19 08:00 Europe/Madrid', timestamptz '2026-10-19 09:45 Europe/Madrid', interval '15 minutes') t;

select is((select (j->>'comparable_incompleto') || ' ' || coalesce(j->>'variacion_energia_pct', 'sin variación')
           from (select hoy_edificio('f1200000-0000-0000-0000-000000000003', timestamptz '2026-10-20 10:07 Europe/Madrid') j) x),
  'true sin variación', 'Comparable con 8 de 40 cuartos de hora: no se calcula la variación de la energía');
select is((select (j->>'comparable_incompleto') || ' ' || coalesce(j->'fuentes'->0->>'variacion_pct', 'sin variación')
           from (select fuentes_hoy_edificio('f1200000-0000-0000-0000-000000000003', timestamptz '2026-10-20 10:07 Europe/Madrid') j) x),
  'true sin variación', '… ni la de cada fuente');

insert into valores_magnitud (id_magnitud_edificio, fecha_hora, valor)
select 'f1600000-0000-0000-0000-000000000009'::uuid, t, 8
from generate_series(timestamptz '2026-10-19 00:00 Europe/Madrid', timestamptz '2026-10-19 07:45 Europe/Madrid', interval '15 minutes') t;
select is((select (j->>'comparable_incompleto') || ' ' || (j->>'variacion_energia_pct')
           from (select hoy_edificio('f1200000-0000-0000-0000-000000000003', timestamptz '2026-10-20 10:07 Europe/Madrid') j) x),
  'false 51.5', 'Con el comparable completo vuelve la variación: 400 frente a 32 × 8 + 8 × 1 = 264 kWh');

-- =========================================================
-- 5. Acceso: otro Partner no obtiene la serie
-- =========================================================
insert into auth.users (id, email) values ('e9600000-0000-0000-0000-000000000002', 'b@series.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'f1900000-0000-0000-0000-000000000002', 'e9600000-0000-0000-0000-000000000002', 'U', 'b@series.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('f1900000-0000-0000-0000-000000000002', 'f1000000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claims', json_build_object('sub', 'e9600000-0000-0000-0000-000000000002', 'role', 'authenticated',
                  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select throws_like($$ select * from serie_energia('f1200000-0000-0000-0000-000000000001', 'RED', now() - interval '1 day', now()) $$,
  '%sin acceso%', 'Otro Partner no obtiene las series del edificio');
reset role;

select * from finish();
rollback;
