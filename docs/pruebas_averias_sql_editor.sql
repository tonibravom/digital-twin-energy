-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE LAS AVERÍAS SIMULADAS Y LA VENTANA DE LECTURAS (migración 054, D59)
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(10);

insert into proveedores (id, codigo, nombre) values
  ('fb000000-0000-0000-0000-00000000000a', 'AVA', 'Partner alarmas A'),
  ('fb000000-0000-0000-0000-00000000000b', 'AVB', 'Partner alarmas B');
insert into clientes (id, codigo, nombre) values ('fb100000-0000-0000-0000-000000000001', 'AVC', 'Cliente alarmas');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fb000000-0000-0000-0000-00000000000a', 'fb100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fb200000-0000-0000-0000-000000000001', 'fb100000-0000-0000-0000-000000000001', 'DEMO-ALE', 'Edificio alarmas', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fb000000-0000-0000-0000-00000000000a', 'fb200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fb300000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fb400000-0000-0000-0000-000000000001', 'fb300000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fb500000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into dispositivos (id, id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
select 'fb600000-0000-0000-0000-000000000001', 'fb400000-0000-0000-0000-000000000001', 'fb500000-0000-0000-0000-000000000001', t.id, 'CAG', 'Contador de agua'
from tipos_dispositivo t where t.codigo = 'CONTADOR_ENERGIA';
create function pg_temp.sensor(p_id text, p_disp text, p_cod text, p_fam text, p_nat text, p_uni text, p_ene text) returns void language sql as $$
  insert into sensores (id, id_dispositivo, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, id_tipo_energia, codigo, nombre, unidad)
  select p_id::uuid, p_disp::uuid, case when p_disp is null then 'fb500000-0000-0000-0000-000000000001'::uuid end,
         'fb400000-0000-0000-0000-000000000001', f.id, n.id, t.id, te.id, p_cod, p_cod, p_uni
  from familias_sensor f, naturalezas_sensor n, tratamientos_sensor t, tipos_energia te
  where f.codigo = p_fam and n.codigo = p_nat and t.codigo = case p_nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
    and te.codigo = p_ene;
$$;
select pg_temp.sensor('fb700000-0000-0000-0000-000000000001', 'fb600000-0000-0000-0000-000000000001', 'AGUA', 'OTRA', 'ACUMULATIVA', 'm³', 'AGUA');
select pg_temp.sensor('fb700000-0000-0000-0000-000000000002', 'fb600000-0000-0000-0000-000000000001', 'PRES', 'PRESION', 'INSTANTANEA', 'bar', 'AGUA');
select pg_temp.sensor('fb700000-0000-0000-0000-000000000003', null, 'TEMP', 'TEMPERATURA', 'INSTANTANEA', '°C', 'OTRA');
update sensores set id_parametro_medidor = (select id from parametros_medidor where codigo = 'CONSUMO_AGUA') where id = 'fb700000-0000-0000-0000-000000000001';
insert into suministros (id, id_edificio, codigo, nombre, tipo) values
  ('fb800000-0000-0000-0000-000000000001', 'fb200000-0000-0000-0000-000000000001', 'AGUA', 'Agua', 'AGUA');
insert into suministros_dispositivos (id_suministro, id_dispositivo, medidor_general) values
  ('fb800000-0000-0000-0000-000000000001', 'fb600000-0000-0000-0000-000000000001', true);

-- Usuarios: dos técnicos del Partner A (el segundo recibe el escalado) y uno del Partner B
insert into auth.users (id, email) values
  ('e9b00000-0000-0000-0000-000000000001', 'a1@averias.test'), ('e9b00000-0000-0000-0000-000000000002', 'a2@averias.test'),
  ('e9b00000-0000-0000-0000-000000000003', 'b@averias.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, x.nom, x.mail, r.id
from (values ('fb900000-0000-0000-0000-000000000001', 'e9b00000-0000-0000-0000-000000000001', 'Técnica A', 'a1@averias.test'),
             ('fb900000-0000-0000-0000-000000000002', 'e9b00000-0000-0000-0000-000000000002', 'Jefe A', 'a2@averias.test'),
             ('fb900000-0000-0000-0000-000000000003', 'e9b00000-0000-0000-0000-000000000003', 'Técnico B', 'b@averias.test')) x(id, auth, nom, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fb900000-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-00000000000a'),
  ('fb900000-0000-0000-0000-000000000002', 'fb000000-0000-0000-0000-00000000000a'),
  ('fb900000-0000-0000-0000-000000000003', 'fb000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;
create function pg_temp.presion(p_valor numeric) returns void language sql as $$
  delete from lecturas where id_sensor = 'fb700000-0000-0000-0000-000000000002';
  insert into lecturas (id_sensor, fecha_hora, valor) values
    ('fb700000-0000-0000-0000-000000000002', now() - interval '4 minutes', p_valor),
    ('fb700000-0000-0000-0000-000000000002', now() - interval '1 minute', p_valor);
$$;
create function pg_temp.evento() returns setof eventos_alarma language sql as $$
  select ea.* from eventos_alarma ea join reglas_alarma ra on ra.id = ea.id_regla_alarma
  where ra.codigo = 'AGUA_PRESION_EXCESIVA-AGUA';
$$;

-- Un edificio que no es de demostración
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fb200000-0000-0000-0000-000000000002', 'fb100000-0000-0000-0000-000000000001', 'REAL', 'Edificio real', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fb000000-0000-0000-0000-00000000000a', 'fb200000-0000-0000-0000-000000000002');

-- 1. Ventana: con un dato cada 15 min, una regla de 5 min usa el valor vigente
insert into lecturas (id_sensor, fecha_hora, valor) values ('fb700000-0000-0000-0000-000000000002', now() - interval '12 minutes', 6.2);
insert into resultados (t) select is((select n from private.ventana_sensor('fb700000-0000-0000-0000-000000000002', 5)), 1, 'Sin lecturas en la ventana cuenta la vigente');
insert into resultados (t) select is((select minimo from private.ventana_sensor('fb700000-0000-0000-0000-000000000002', 5)), 6.2::double precision, 'con su valor');
insert into lecturas (id_sensor, fecha_hora, valor) values ('fb700000-0000-0000-0000-000000000002', now() - interval '2 minutes', 2.5);
insert into resultados (t) select is((select array[minimo, maximo] from private.ventana_sensor('fb700000-0000-0000-0000-000000000002', 5)),
  array[2.5, 6.2]::double precision[], 'La vigente y las de la ventana');

-- 2. Averías simuladas
select pg_temp.login('e9b00000-0000-0000-0000-000000000003');
set local role authenticated;
insert into resultados (t) select throws_ok($$ select simular_averia('fb200000-0000-0000-0000-000000000001', 'SIN_AGUA', 30) $$,
  '42501', null, 'El Partner B NO puede simular averías en el edificio del Partner A');
reset role;
select pg_temp.login('e9b00000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select throws_like($$ select simular_averia('fb200000-0000-0000-0000-000000000002', 'SIN_AGUA', 30) $$,
  '%solo se pueden usar en edificios de demostración%', 'Nunca en un edificio real');
insert into resultados (t) select throws_like($$ select simular_averia('fb200000-0000-0000-0000-000000000001', 'SIN_AGUA', 500) $$,
  '%entre 15 y 240%', 'Duración limitada');
insert into resultados (t) select lives_ok($$ select simular_averia('fb200000-0000-0000-0000-000000000001', 'PRESION_AGUA_ALTA', 30) $$,
  'El Partner A simula una avería en su edificio de demostración');
insert into resultados (t) select is((select count(*)::integer from averias_simuladas where fin > now()), 1, 'Queda activa');
insert into resultados (t) select lives_ok($$ select terminar_averia((select id from averias_simuladas limit 1)) $$, 'Y la puede terminar antes');
reset role;
insert into resultados (t) select is((select count(*)::integer from averias_simuladas_activas()), 1, 'El simulador la recibe (también las terminadas hace poco)');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'
', 1), E'
' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 10 then
    raise exception 'RESULTADO: % de 10 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:
%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
