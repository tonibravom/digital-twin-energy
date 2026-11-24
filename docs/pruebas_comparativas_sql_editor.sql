-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE LAS COMPARATIVAS GUARDADAS (migración 059, D62)
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(9);

insert into proveedores (id, codigo, nombre) values
  ('fe000000-0000-0000-0000-00000000000a', 'COA', 'Partner alarmas A'),
  ('fe000000-0000-0000-0000-00000000000b', 'COB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('fe100000-0000-0000-0000-000000000001', 'COC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fe000000-0000-0000-0000-00000000000a', 'fe100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fe200000-0000-0000-0000-000000000001', 'fe100000-0000-0000-0000-000000000001', 'COE', 'Edificio alarmas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fe000000-0000-0000-0000-00000000000a', 'fe200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fe300000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fe400000-0000-0000-0000-000000000001', 'fe300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fe500000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fe600000-0000-0000-0000-000000000001', 'fe400000-0000-0000-0000-000000000001', 'fe500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fe500000-0000-0000-0000-000000000001'::uuid end,
         'fe400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('fe700000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('fe700000-0000-0000-0000-000000000002', 'fe600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('fe700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'fe700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fe800000-0000-0000-0000-000000000001', 'fe200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fe800000-0000-0000-0000-000000000001', 'fe600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9e00000-0000-0000-0000-000000000001', 'a1@comparativas.test'), ('e9e00000-0000-0000-0000-000000000002', 'a2@comparativas.test'),
  ('e9e00000-0000-0000-0000-000000000003', 'b@comparativas.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('fe900000-0000-0000-0000-000000000001', 'e9e00000-0000-0000-0000-000000000001', 'Técnica A', 'a1@comparativas.test'),
             ('fe900000-0000-0000-0000-000000000002', 'e9e00000-0000-0000-0000-000000000002', 'Jefe A', 'a2@comparativas.test'),
             ('fe900000-0000-0000-0000-000000000003', 'e9e00000-0000-0000-0000-000000000003', 'Técnico B', 'b@comparativas.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fe900000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-00000000000a'),
  ('fe900000-0000-0000-0000-000000000002', 'fe000000-0000-0000-0000-00000000000a'),
  ('fe900000-0000-0000-0000-000000000003', 'fe000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'fe700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('fe700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('fe700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;


-- 1. Guardar (Técnica A, compartida) y una privada (Jefe A)
select pg_temp.login('e9e00000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select lives_ok($$ select guardar_comparativa('fe200000-0000-0000-0000-000000000001', 'Consumo anual 4 años',
                   '{"modo": "periodos", "tamano": "anio"}') $$, 'Se guarda una comparativa');
insert into resultados (t) select throws_like($$ select guardar_comparativa('fe200000-0000-0000-0000-000000000001', ' ', '{"modo": "valores"}') $$,
  '%nombre%', 'Necesita nombre');
insert into resultados (t) select throws_like($$ select guardar_comparativa('fe200000-0000-0000-0000-000000000001', 'X', '{"modo": "otra"}') $$,
  '%no válida%', 'Y una selección válida');
reset role;
select pg_temp.login('e9e00000-0000-0000-0000-000000000002');
set local role authenticated;
select guardar_comparativa('fe200000-0000-0000-0000-000000000001', 'Mi prueba', '{"modo": "valores"}', false);
insert into resultados (t) select is((select array_agg(nombre order by nombre) from comparativas), '{"Consumo anual 4 años","Mi prueba"}'::text[],
  'Ve las compartidas y las suyas');
insert into resultados (t) select throws_ok($$ select retirar_comparativa((select id from comparativas where nombre = 'Consumo anual 4 años')) $$,
  '42501', null, 'No quita la de otra persona');
reset role;
select pg_temp.login('e9e00000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((select array_agg(nombre) from comparativas), '{"Consumo anual 4 años"}'::text[], 'La privada de otro no se ve');
insert into resultados (t) select lives_ok($$ select retirar_comparativa((select id from comparativas where nombre = 'Consumo anual 4 años')) $$, 'Quien la creó la quita');
insert into resultados (t) select is((select count(*)::integer from comparativas), 0, 'Ya no sale (baja lógica)');
reset role;

-- 2. Partner B
select pg_temp.login('e9e00000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select throws_ok($$ select guardar_comparativa('fe200000-0000-0000-0000-000000000001', 'Intrusa', '{"modo": "valores"}') $$,
  '42501', null, 'El Partner B NO puede guardar en el edificio del Partner A');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'
', 1), E'
' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 9 then
    raise exception 'RESULTADO: % de 9 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:
%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
