-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE KPIs DE LOS DASHBOARDS (migración 022)
-- Ejecutar con:  npx supabase test db
--
-- Fecha de cálculo fija: 30/06/2026 (año en curso 01/01–30/06,
-- comparado con 01/01–30/06/2025).
-- Partner P: cliente C1 (edificios E1 y E2) y cliente C2 (E3).
-- Partner Q: cliente C3 (E4).
--   E1: 2026 → elec importada 1000, gas 500, agua 10, FV 200 (50 exportados) · 2025 → elec 800, gas 500
--   Energía consumida = importada + gas + renovable consumida (decisión 21/10/2026)
--   E2: 2026 → elec 300 (edificio nuevo, sin datos 2025: no comparable)
--   E3: 2026 → elec 100, gas 100 · 2025 → elec 100, gas 100 (+ agosto 2025 fuera de periodo)
--   E4: 2026 → elec 5000
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(24);

insert into auth.users (id, email) values
  ('e2000000-0000-0000-0000-000000000001', 'saas@kpi.test'),
  ('e2000000-0000-0000-0000-000000000002', 'p@kpi.test'),
  ('e2000000-0000-0000-0000-000000000003', 'q@kpi.test'),
  ('e2000000-0000-0000-0000-000000000004', 'c1@kpi.test');

insert into proveedores (id, codigo, nombre) values
  ('d0000000-0000-0000-0000-00000000000a', 'KP', 'Partner P'),
  ('d0000000-0000-0000-0000-00000000000b', 'KQ', 'Partner Q');
insert into clientes (id, codigo, nombre) values
  ('d1000000-0000-0000-0000-000000000001', 'KC1', 'Cliente C1'),
  ('d1000000-0000-0000-0000-000000000002', 'KC2', 'Cliente C2'),
  ('d1000000-0000-0000-0000-000000000003', 'KC3', 'Cliente C3');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('d0000000-0000-0000-0000-00000000000a', 'd1000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-00000000000a', 'd1000000-0000-0000-0000-000000000002'),
  ('d0000000-0000-0000-0000-00000000000b', 'd1000000-0000-0000-0000-000000000003');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'E1', 'E1'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'E2', 'E2'),
  ('d2000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000002', 'E3', 'E3'),
  ('d2000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000003', 'E4', 'E4');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('d0000000-0000-0000-0000-00000000000a', 'd2000000-0000-0000-0000-000000000001'),
  ('d0000000-0000-0000-0000-00000000000a', 'd2000000-0000-0000-0000-000000000002'),
  ('d0000000-0000-0000-0000-00000000000a', 'd2000000-0000-0000-0000-000000000003'),
  ('d0000000-0000-0000-0000-00000000000b', 'd2000000-0000-0000-0000-000000000004');

insert into resumenes_diarios (id_edificio, fecha, indicador, valor) values
  ('d2000000-0000-0000-0000-000000000001', '2026-03-01', 'CONSUMO_ELECTRICIDAD', 1000),
  ('d2000000-0000-0000-0000-000000000001', '2026-03-01', 'CONSUMO_GAS', 500),
  ('d2000000-0000-0000-0000-000000000001', '2026-03-01', 'CONSUMO_AGUA', 10),
  ('d2000000-0000-0000-0000-000000000001', '2026-03-01', 'GENERACION_FOTOVOLTAICA', 200),
  ('d2000000-0000-0000-0000-000000000001', '2026-03-01', 'ELECTRICIDAD_EXPORTADA', 50),
  ('d2000000-0000-0000-0000-000000000001', '2025-03-01', 'CONSUMO_ELECTRICIDAD', 800),
  ('d2000000-0000-0000-0000-000000000001', '2025-03-01', 'CONSUMO_GAS', 500),
  ('d2000000-0000-0000-0000-000000000002', '2026-03-01', 'CONSUMO_ELECTRICIDAD', 300),
  ('d2000000-0000-0000-0000-000000000003', '2026-04-01', 'CONSUMO_ELECTRICIDAD', 100),
  ('d2000000-0000-0000-0000-000000000003', '2026-04-01', 'CONSUMO_GAS', 100),
  ('d2000000-0000-0000-0000-000000000003', '2025-04-01', 'CONSUMO_ELECTRICIDAD', 100),
  ('d2000000-0000-0000-0000-000000000003', '2025-04-01', 'CONSUMO_GAS', 100),
  ('d2000000-0000-0000-0000-000000000003', '2025-08-01', 'CONSUMO_ELECTRICIDAD', 999),
  ('d2000000-0000-0000-0000-000000000004', '2026-03-01', 'CONSUMO_ELECTRICIDAD', 5000);

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values
  ('d3000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'saas@kpi.test', 'ADMIN_SAAS'),
  ('d3000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'p@kpi.test', 'ADMIN_PARTNER'),
  ('d3000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000003', 'q@kpi.test', 'ADMIN_PARTNER'),
  ('d3000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000004', 'c1@kpi.test', 'USUARIO_CLIENTE')) x(id, auth, mail, rol)
join roles r on r.codigo = x.rol;
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('d3000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-00000000000a'),
  ('d3000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-00000000000b');
insert into usuarios_clientes (id_usuario, id_cliente) values
  ('d3000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;

-- Valor de un indicador de kpis_ambito a 30/06/2026
create function pg_temp.kpi(p_nivel text, p_id uuid, p_codigo text, p_campo text default 'valor')
returns text language sql as $$
  select i->>p_campo
  from jsonb_array_elements(kpis_ambito(p_nivel, p_id, date '2026-06-30')->'indicadores') i
  where i->>'codigo' = p_codigo;
$$;

-- =========================================================
-- 1. Parámetros y catálogos
-- =========================================================
insert into resultados (t) select is(factor_co2('FACTOR_CO2_ELECTRICIDAD', date '2026-06-30'), 0.183::numeric, 'Factor CO2 de electricidad: 0,183 kg/kWh');
insert into resultados (t) select is(factor_co2('FACTOR_CO2_GAS', date '2026-06-30'), 0.182::numeric, 'Factor CO2 de gas: 0,182 kg/kWh');
insert into resultados (t) select ok(exists (select 1 from magnitudes where codigo = 'GENERACION_GEOTERMIA'), 'El catálogo incluye magnitudes por suministro y renovable');
insert into resultados (t) select throws_ok(
  $$ insert into resumenes_diarios (id_edificio, fecha, indicador, valor)
     values ('d2000000-0000-0000-0000-000000000001', '2026-01-01', 'INVENTADO', 1) $$,
  '23514', null, 'Solo se admiten indicadores conocidos');

-- =========================================================
-- 2. Partner P (como administrador del Partner P)
-- =========================================================
select pg_temp.login('e2000000-0000-0000-0000-000000000002');
set local role authenticated;

insert into resultados (t) select is((kpis_ambito('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')->>'edificios')::int, 3,
  'El Partner P tiene 3 edificios en su ámbito');
insert into resultados (t) select is((kpis_ambito('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')->>'edificios_comparables')::int, 2,
  'Solo 2 son comparables con el año anterior (E2 es nuevo)');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'energia')::float8, 2150::float8,
  'Energía consumida = 1.400 importada + 600 gas + 150 FV autoconsumida = 2.150 kWh');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'renovable_consumida')::float8, 150::float8,
  'Renovable consumida = 200 generados − 50 exportados');
insert into resultados (t) select is(kpis_ambito('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')->>'cobertura_renovable_pct', '7.0',
  'Cobertura renovable = 150 / 2.150 = 7,0 %');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'electricidad')::float8, 1400::float8,
  'Electricidad = 1.400 kWh');
insert into resultados (t) select is(round(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'tco2')::numeric, 4), 0.3654,
  'Emisiones = (1.400 × 0,183 + 600 × 0,182) / 1000 = 0,3654 tCO2e');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'agua')::float8, 10::float8,
  'Agua = 10 m3 (aparte de la energía)');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'renovable')::float8, 200::float8,
  'Generación renovable = 200 kWh');
insert into resultados (t) select is(pg_temp.kpi('PARTNER', 'd0000000-0000-0000-0000-00000000000a', 'energia', 'variacion_pct'), '23.3',
  'Variación de energía +23,3 % solo con edificios comparables (1.850 frente a 1.500)');
insert into resultados (t) select is((select variacion_energia_pct from kpis_lista('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')
           where id = 'd1000000-0000-0000-0000-000000000001'), 26.9,
  'En la lista de clientes, C1 sube un 26,9 % (1.650 frente a 1.300)');
insert into resultados (t) select is((select energia_kwh from kpis_lista('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')
           where id = 'd1000000-0000-0000-0000-000000000002'), 200::float8,
  'En la lista de clientes, C2 consume 200 kWh');
insert into resultados (t) select is((select count(*) from kpis_lista('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')), 2::bigint,
  'La lista del Partner P tiene sus 2 clientes');
insert into resultados (t) select is(pg_temp.kpi('PLATAFORMA', null, 'energia')::float8, 2150::float8,
  'El Partner P no suma edificios de otros Partners aunque pida el nivel plataforma');
reset role;

-- =========================================================
-- 3. Aislamiento y otros niveles
-- =========================================================
select pg_temp.login('e2000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select is((kpis_ambito('PARTNER', 'd0000000-0000-0000-0000-00000000000a', date '2026-06-30')->>'edificios')::int, 0,
  'El Partner Q no ve los KPIs del Partner P');
insert into resultados (t) select throws_ok(
  $$ insert into resumenes_diarios (id_edificio, fecha, indicador, valor)
     values ('d2000000-0000-0000-0000-000000000004', '2026-01-02', 'CONSUMO_GAS', 1) $$,
  '42501', null, 'Los usuarios no escriben resúmenes (solo el motor)');
reset role;

select pg_temp.login('e2000000-0000-0000-0000-000000000004');
set local role authenticated;
insert into resultados (t) select is(pg_temp.kpi('PLATAFORMA', null, 'energia')::float8, 1950::float8,
  'Un usuario del cliente C1 solo suma sus edificios');
reset role;

select pg_temp.login('e2000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((select energia_kwh from kpis_lista('PLATAFORMA', null, date '2026-06-30')
           where id = 'd0000000-0000-0000-0000-00000000000b'), 5000::float8,
  'El administrador ve la lista de Partners con su consumo');
reset role;

-- =========================================================
-- 4. Tecnologías de generación
-- =========================================================
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'ST', 'Solar térmica', 'GENERACION'),
  ('d4000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001', 'CG', 'Cogeneración', 'GENERACION');
insert into suministros_generacion (id_suministro, tecnologia) values
  ('d4000000-0000-0000-0000-000000000001', 'SOLAR_TERMICA'),
  ('d4000000-0000-0000-0000-000000000002', 'COGENERACION');
insert into resultados (t) select ok((select renovable from suministros_generacion where id_suministro = 'd4000000-0000-0000-0000-000000000001'),
  'La solar térmica cuenta como renovable');
insert into resultados (t) select ok(not (select renovable from suministros_generacion where id_suministro = 'd4000000-0000-0000-0000-000000000002'),
  'La cogeneración no cuenta como renovable');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 24 then
    raise exception 'RESULTADO: % de 24 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
