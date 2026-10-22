-- =========================================================
-- PRUEBAS DE USOS FINALES Y DIAGRAMA SANKEY (migración 024)
-- Ejecutar con:  npx supabase test db
--
-- Edificio con datos de marzo de 2026:
--   Red 1.000 kWh · FV 300 kWh (100 exportados) · Gas 500 kWh · Solar térmica 60 kWh
--   Submedidores eléctricos: climatización 400, renovación 100,
--   iluminación 200. Gas sin submedidor; reparto: 100 % climatización.
-- Esperado: electricidad consumida = 1.000 + 200 = 1.200 kWh;
--   sin medir 500 → "Otros usos" (estimado);
--   gas 500 → HVAC/climatización (estimado);
--   HVAC → climatización 900, renovación 100.
-- =========================================================
begin;
set search_path = public, extensions;

select plan(18);

insert into auth.users (id, email) values
  ('e4000000-0000-0000-0000-000000000001', 'p@sankey.test'),
  ('e4000000-0000-0000-0000-000000000002', 'q@sankey.test');
insert into proveedores (id, codigo, nombre) values
  ('aa100000-0000-0000-0000-00000000000a', 'SP', 'Partner'),
  ('aa100000-0000-0000-0000-00000000000b', 'SQ', 'Otro');
insert into clientes (id, codigo, nombre) values ('aa110000-0000-0000-0000-000000000001', 'SC', 'Cliente');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('aa100000-0000-0000-0000-00000000000a', 'aa110000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('aa120000-0000-0000-0000-000000000001', 'aa110000-0000-0000-0000-000000000001', 'SE', 'Edificio');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('aa100000-0000-0000-0000-00000000000a', 'aa120000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('aa130000-0000-0000-0000-000000000001', 'aa120000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('aa140000-0000-0000-0000-000000000001', 'aa130000-0000-0000-0000-000000000001', 'R', 'Sala');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('aa150000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000001', 'p@sankey.test'),
  ('aa150000-0000-0000-0000-000000000002', 'e4000000-0000-0000-0000-000000000002', 'q@sankey.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('aa150000-0000-0000-0000-000000000001', 'aa100000-0000-0000-0000-00000000000a'),
  ('aa150000-0000-0000-0000-000000000002', 'aa100000-0000-0000-0000-00000000000b');

insert into resumenes_diarios (id_edificio, fecha, indicador, valor) values
  ('aa120000-0000-0000-0000-000000000001', '2026-03-10', 'CONSUMO_ELECTRICIDAD', 1000),
  ('aa120000-0000-0000-0000-000000000001', '2026-03-10', 'GENERACION_FOTOVOLTAICA', 300),
  ('aa120000-0000-0000-0000-000000000001', '2026-03-10', 'ELECTRICIDAD_EXPORTADA', 100),
  ('aa120000-0000-0000-0000-000000000001', '2026-03-10', 'CONSUMO_GAS', 500),
  ('aa120000-0000-0000-0000-000000000001', '2026-03-10', 'GENERACION_SOLAR_TERMICA', 60);
insert into resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, valor)
select 'aa120000-0000-0000-0000-000000000001', '2026-03-10', u.id, 'ELECTRICIDAD', x.v
from (values ('HVAC_CLIMATIZACION', 400), ('HVAC_RENOVACION', 100), ('ILUMINACION', 200)) x(c, v)
join usos_energia u on u.codigo = x.c;

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.enlace(p_origen text, p_destino text, p_campo text default 'valor') returns numeric language sql as $$
  select (e->>p_campo)::numeric
  from jsonb_array_elements(sankey_energia('EDIFICIO', 'aa120000-0000-0000-0000-000000000001', '2026-03-01', '2026-03-31')->'enlaces') e
  where e->>'origen' = p_origen and e->>'destino' = p_destino;
$$;

-- =========================================================
-- 1. Configuración
-- =========================================================
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'aa160000-0000-0000-0000-000000000001', 'aa120000-0000-0000-0000-000000000001', id, 'H', 'Gateway'
from tipos_conexion where codigo = 'ENVIO_HTTP';
select throws_like(
  $$ insert into sensores (id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, id_uso_energia)
     select 'aa160000-0000-0000-0000-000000000001', 'aa140000-0000-0000-0000-000000000001', f.id, n.id, t.id, 'X', 'X', 'kWh', u.id
     from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, usos_energia u
     where f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA' and u.codigo = 'HVAC' $$,
  '%uso final%', 'Un submedidor se asigna a un uso final, no al grupo HVAC');

select pg_temp.login('e4000000-0000-0000-0000-000000000001');
set local role authenticated;
select lives_ok(
  $$ insert into repartos_uso_edificio (id_edificio, tipo_energia, id_uso_energia, porcentaje)
     select 'aa120000-0000-0000-0000-000000000001', 'GAS', id, 100 from usos_energia where codigo = 'HVAC_CLIMATIZACION' $$,
  'El Partner configura: el gas no medido va 100 % a climatización');
select throws_like(
  $$ insert into repartos_uso_edificio (id_edificio, tipo_energia, id_uso_energia, porcentaje)
     select 'aa120000-0000-0000-0000-000000000001', 'GAS', id, 10 from usos_energia where codigo = 'OTROS' $$,
  '%superan el 100%', 'Los porcentajes de reparto no pueden superar el 100 %');

-- =========================================================
-- 2. Diagrama
-- =========================================================
select is(pg_temp.enlace('RED', 'ELECTRICIDAD'), 1000.000, 'Red eléctrica → electricidad consumida: 1.000 kWh');
select is(pg_temp.enlace('FOTOVOLTAICA', 'ELECTRICIDAD'), 200.000, 'Fotovoltaica autoconsumida: 200 kWh');
select is(pg_temp.enlace('FOTOVOLTAICA', 'EXPORTADA'), 100.000, 'Fotovoltaica exportada: 100 kWh');
select is(pg_temp.enlace('ELECTRICIDAD', 'HVAC'), 500.000, 'Electricidad → HVAC: 400 + 100 = 500 kWh');
select is(pg_temp.enlace('ELECTRICIDAD', 'ILUMINACION'), 200.000, 'Electricidad → iluminación: 200 kWh');
select is(pg_temp.enlace('ELECTRICIDAD', 'OTROS'), 500.000, 'Electricidad no medida → otros usos: 1.200 − 700 = 500 kWh');
select is(pg_temp.enlace('ELECTRICIDAD', 'OTROS', 'estimado'), 500.000, '… y se marca como estimada');
select is(pg_temp.enlace('GAS', 'HVAC'), 500.000, 'Gas → HVAC según el reparto configurado');
select is(pg_temp.enlace('HVAC', 'HVAC_CLIMATIZACION'), 900.000, 'HVAC → climatización: 400 eléctricos + 500 de gas');
select is(pg_temp.enlace('HVAC', 'HVAC_RENOVACION'), 100.000, 'HVAC → renovación de aire: 100 kWh');
select is(pg_temp.enlace('SOLAR_TERMICA', 'CALOR_RENOVABLE'), 60.000, 'Solar térmica → calor renovable: 60 kWh');
select is(pg_temp.enlace('CALOR_RENOVABLE', 'OTROS'), 60.000, 'Calor renovable sin reparto configurado → otros usos (estimado)');
select is((sankey_energia('EDIFICIO', 'aa120000-0000-0000-0000-000000000001', '2026-03-01', '2026-03-31')->'totales'->>'energia_consumida_kwh')::numeric,
  1760::numeric, 'Energía consumida = 1.000 red + 200 FV + 500 gas + 60 solar térmica');
select is((select sum((e->>'valor')::numeric)
           from jsonb_array_elements(sankey_energia('EDIFICIO', 'aa120000-0000-0000-0000-000000000001', '2026-03-01', '2026-03-31')->'enlaces') e
           where e->>'destino' in ('EXPORTADA', 'HVAC_CLIMATIZACION', 'HVAC_RENOVACION', 'ILUMINACION', 'OTROS')),
  1860.000, 'Balance: todo lo que entra (1.000 + 300 + 500 + 60) sale por algún uso o exportación');
reset role;

select pg_temp.login('e4000000-0000-0000-0000-000000000002');
set local role authenticated;
select is(jsonb_array_length(sankey_energia('EDIFICIO', 'aa120000-0000-0000-0000-000000000001', '2026-03-01', '2026-03-31')->'enlaces'),
  0, 'Otro Partner no obtiene datos de este edificio');
reset role;

select * from finish();
rollback;
