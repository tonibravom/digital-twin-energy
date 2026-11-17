-- =========================================================
-- PRUEBAS DE PRODUCCIÓN: FOTOVOLTAICA Y SOLAR TÉRMICA (migración 052, D58)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

select plan(14);

insert into proveedores (id, codigo, nombre) values
  ('fd000000-0000-0000-0000-00000000000a', 'PA', 'Partner producción A'),
  ('fd000000-0000-0000-0000-00000000000b', 'PB', 'Partner producción B');
insert into clientes (id, codigo, nombre) values ('fd100000-0000-0000-0000-000000000001', 'PC', 'Cliente producción');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fd200000-0000-0000-0000-000000000001', 'fd100000-0000-0000-0000-000000000001', 'PE', 'Edificio producción', 'Europe/Madrid'),
  ('fd200000-0000-0000-0000-000000000002', 'fd100000-0000-0000-0000-000000000001', 'PE2', 'Otro edificio', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fd300000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'CUB', 'Cubierta', 5),
  ('fd300000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000002', 'CUB', 'Cubierta', 5);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fd400000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'TEC', 'Zona técnica');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fd500000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fd600000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', 'fd500000-0000-0000-0000-000000000001', id, 'INV', 'Inversor'
from tipos_dispositivo where codigo = 'INVERSOR_SOLAR';

create function pg_temp.sensor(p_id text, p_cod text, p_fam text, p_nat text, p_uni text, p_par text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, id_parametro_medidor)
  select p_id::uuid, 'fd600000-0000-0000-0000-000000000001', 'fd400000-0000-0000-0000-000000000001', f.id, n.id, t.id, p_cod, p_cod, p_uni,
         (select id from parametros_medidor where codigo = p_par)
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end;
$$;

-- 1. Catálogo
select is((select array_agg(codigo::text order by tipo_suministro, orden) from parametros_medidor
           where tipo_suministro in ('FOTOVOLTAICA', 'SOLAR_TERMICA') and obligatorio),
  '{FV_ENERGIA,FV_POTENCIA,ST_ENERGIA,ST_POTENCIA}'::text[],
  'Obligatorios: energía producida y potencia (fotovoltaica y solar térmica)');

-- 2. Bloqueo: una instalación sin medidor de producción
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fd700000-0000-0000-0000-000000000001', 'fd200000-0000-0000-0000-000000000001', 'FV', 'FV cubierta', 'GENERACION'),
  ('fd700000-0000-0000-0000-000000000002', 'fd200000-0000-0000-0000-000000000001', 'EO', 'Eólica', 'GENERACION'),
  ('fd700000-0000-0000-0000-000000000003', 'fd200000-0000-0000-0000-000000000001', 'RED', 'Red', 'ELECTRICIDAD');
insert into suministros_generacion (id_suministro, tecnologia, potencia_pico_kw) values
  ('fd700000-0000-0000-0000-000000000001', 'FOTOVOLTAICA', 40),
  ('fd700000-0000-0000-0000-000000000002', 'EOLICA', 5);
select ok(exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fd200000-0000-0000-0000-000000000001')->'comprobaciones') c
                  where c->>'codigo' = 'MEDIDOR_GENERAL' and (c->>'bloqueante')::boolean and not (c->>'ok')::boolean
                    and c->>'detalle' like '%FV cubierta%falta el medidor de producción%'),
  'Una fotovoltaica sin medidor de producción bloquea la parametrización');
select ok(not exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fd200000-0000-0000-0000-000000000001')->'comprobaciones') c
                      where c->>'detalle' like '%Eólica%'),
  'Las tecnologías sin catálogo de parámetros (eólica…) todavía no se comprueban');

select pg_temp.sensor('fd800000-0000-0000-0000-000000000001', 'E', 'ENERGIA', 'ACUMULATIVA', 'kWh', 'FV_ENERGIA');
select pg_temp.sensor('fd800000-0000-0000-0000-000000000002', 'P', 'POTENCIA', 'INSTANTANEA', 'kW', 'FV_POTENCIA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fd700000-0000-0000-0000-000000000001', 'fd600000-0000-0000-0000-000000000001', true);
select ok(exists (select 1 from jsonb_array_elements(estado_parametrizacion_edificio('fd200000-0000-0000-0000-000000000001')->'comprobaciones') c
                  where c->>'detalle' like '%FV cubierta%completo%' and (c->>'ok')::boolean),
  'Con energía y potencia, la fotovoltaica queda completa');

-- 3. Superficies de placas
select throws_like($$ insert into superficies_produccion (id_suministro, id_planta, nombre, origen, poligono)
                      values ('fd700000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'X', 'DIBUJADA', '[[0,0],[1,0]]') $$,
  '%superficies_produccion_datos_ck%', 'Una superficie dibujada necesita al menos 3 puntos');
select throws_like($$ insert into superficies_produccion (id_suministro, id_planta, nombre, origen, poligono)
                      values ('fd700000-0000-0000-0000-000000000003', 'fd300000-0000-0000-0000-000000000001', 'X', 'DIBUJADA', '[[0,0],[1,0],[1,1]]') $$,
  '%fotovoltaica o solar térmica%', 'Solo las instalaciones fotovoltaicas o solares térmicas tienen placas');
select throws_like($$ insert into superficies_produccion (id_suministro, id_planta, nombre, origen, poligono)
                      values ('fd700000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000002', 'X', 'DIBUJADA', '[[0,0],[1,0],[1,1]]') $$,
  '%mismo edificio%', 'La planta de las placas es del mismo edificio');
insert into superficies_produccion (id, id_suministro, id_planta, nombre, origen, poligono)
values ('fd900000-0000-0000-0000-000000000001', 'fd700000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001',
        'Terraza', 'DIBUJADA', '[[0,0],[4,0],[4,3],[0,3]]');
select is((select area_m2 from superficies_produccion where id = 'fd900000-0000-0000-0000-000000000001'), 12.00,
  'La superficie de un polígono dibujado se calcula sola');
select lives_ok($$ insert into superficies_produccion (id_suministro, id_planta, nombre, origen, clave_objeto)
                   values ('fd700000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'Modelo', 'MODELO', 'Cubierta sur') $$,
  'Una superficie del modelo 3D se identifica por el nombre del campo («FV: Cubierta sur»)');

-- 4. Ficha y KPIs: potencia de 20 kW con 40 kWp = 50 % de la potencia pico
insert into estado_comunicacion (id_sensor, estado, ultima_lectura, ultimo_valor)
values ('fd800000-0000-0000-0000-000000000002', 'COMUNICANDO', now(), 20);
select is((select (f->'kpis'->>'pct_pico')::numeric from jsonb_array_elements(produccion_edificio('fd200000-0000-0000-0000-000000000001')) f
           where f->>'codigo' = 'FV'), 50.0, 'La ficha de producción da la potencia sobre la potencia pico');

-- 5. Sankey: el calor solar llega al uso al que da servicio, junto al gas
insert into resumenes_diarios (id_edificio, fecha, indicador, valor, completo, origen) values
  ('fd200000-0000-0000-0000-000000000001', current_date, 'CONSUMO_GAS', 30, true, 'MOTOR'),
  ('fd200000-0000-0000-0000-000000000001', current_date, 'GENERACION_SOLAR_TERMICA', 10, true, 'MOTOR');
insert into resumenes_diarios_usos (id_edificio, fecha, id_uso_energia, tipo_energia, valor)
select 'fd200000-0000-0000-0000-000000000001', current_date, id, 'GAS', 30 from usos_energia where codigo = 'HVAC_ACS';
insert into repartos_uso_edificio (id_edificio, tipo_energia, id_uso_energia, porcentaje)
select 'fd200000-0000-0000-0000-000000000001', 'CALOR_RENOVABLE', id, 100 from usos_energia where codigo = 'HVAC_ACS';
select is((select jsonb_object_agg(d->>'tipo', (d->>'valor')::numeric)
           from jsonb_array_elements(sankey_energia('EDIFICIO', 'fd200000-0000-0000-0000-000000000001', current_date, current_date)->'desglose'->'HVAC_ACS') d),
  '{"GAS": 30.000, "CALOR_RENOVABLE": 10.000}'::jsonb,
  'El Sankey desglosa qué energía llega al ACS: gas y calor solar');

-- 6. Acceso: otro Partner no ve ni dibuja las placas
insert into auth.users (id, email) values ('e9a00000-0000-0000-0000-000000000002', 'b@produccion.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select 'fd990000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-000000000002', 'B', 'b@produccion.test', r.id
from roles r where r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values ('fd990000-0000-0000-0000-000000000002', 'fd000000-0000-0000-0000-00000000000b');
select set_config('request.jwt.claims', json_build_object('sub', 'e9a00000-0000-0000-0000-000000000002', 'role', 'authenticated',
                  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select is((select count(*)::integer from superficies_produccion), 0, 'Otro Partner no ve las superficies de placas');
select is(produccion_edificio('fd200000-0000-0000-0000-000000000001'), '[]'::jsonb, 'Ni las fichas de producción');
select throws_like($$ insert into superficies_produccion (id_suministro, id_planta, nombre, origen, poligono)
                      values ('fd700000-0000-0000-0000-000000000001', 'fd300000-0000-0000-0000-000000000001', 'Y', 'DIBUJADA', '[[0,0],[1,0],[1,1]]') $$,
  '%', 'Ni puede dibujar placas en el edificio');
reset role;

select * from finish();
rollback;
