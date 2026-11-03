-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE LA CAMPANA DE ALARMAS (migración 035)
-- Ejecutar con:  npx supabase test db
-- Dos Partners con un edificio cada uno: cada uno solo cuenta las suyas.
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(5);

insert into auth.users (id, email) values
  ('e9200000-0000-0000-0000-000000000001', 'a@campana.test'),
  ('e9200000-0000-0000-0000-000000000002', 'b@campana.test');
insert into proveedores (id, codigo, nombre) values
  ('fd000000-0000-0000-0000-00000000000a', 'CA', 'Partner A'),
  ('fd000000-0000-0000-0000-00000000000b', 'CB', 'Partner B');
insert into clientes (id, codigo, nombre) values
  ('fd100000-0000-0000-0000-00000000000a', 'CCA', 'Cliente A'),
  ('fd100000-0000-0000-0000-00000000000b', 'CCB', 'Cliente B');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd100000-0000-0000-0000-00000000000a'),
  ('fd000000-0000-0000-0000-00000000000b', 'fd100000-0000-0000-0000-00000000000b');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('fd200000-0000-0000-0000-00000000000a', 'fd100000-0000-0000-0000-00000000000a', 'EA', 'Edificio A'),
  ('fd200000-0000-0000-0000-00000000000b', 'fd100000-0000-0000-0000-00000000000b', 'EB', 'Edificio B');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fd000000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-00000000000a'),
  ('fd000000-0000-0000-0000-00000000000b', 'fd200000-0000-0000-0000-00000000000b');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('fd300000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-00000000000a', 'P0', 'PB'),
  ('fd300000-0000-0000-0000-00000000000b', 'fd200000-0000-0000-0000-00000000000b', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('fd400000-0000-0000-0000-00000000000a', 'fd300000-0000-0000-0000-00000000000a', 'R', 'Sala'),
  ('fd400000-0000-0000-0000-00000000000b', 'fd300000-0000-0000-0000-00000000000b', 'R', 'Sala');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select x.id::uuid, x.ed::uuid, t.id, 'HTTP', 'Gateway'
from (values ('fd700000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-00000000000a'),
             ('fd700000-0000-0000-0000-00000000000b', 'fd200000-0000-0000-0000-00000000000b')) x(id, ed),
     tipos_conexion t where t.codigo = 'ENVIO_HTTP';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select x.id::uuid, x.con::uuid, x.rec::uuid, f.id, n.id, t.id, x.cod, x.cod, '°C', jsonb_build_object('clave', x.cod)
from (values ('fd800000-0000-0000-0000-0000000000a1', 'fd700000-0000-0000-0000-00000000000a', 'fd400000-0000-0000-0000-00000000000a', 'TA1'),
             ('fd800000-0000-0000-0000-0000000000a2', 'fd700000-0000-0000-0000-00000000000a', 'fd400000-0000-0000-0000-00000000000a', 'TA2'),
             ('fd800000-0000-0000-0000-0000000000b1', 'fd700000-0000-0000-0000-00000000000b', 'fd400000-0000-0000-0000-00000000000b', 'TB1')) x(id, con, rec, cod),
     familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where f.codigo = 'TEMPERATURA' and n.codigo = 'INSTANTANEA' and t.codigo = 'PROMEDIO';

insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values ('fd500000-0000-0000-0000-00000000000a', 'e9200000-0000-0000-0000-000000000001', 'a@campana.test'),
             ('fd500000-0000-0000-0000-00000000000b', 'e9200000-0000-0000-0000-000000000002', 'b@campana.test')) x(id, auth, mail)
join roles r on r.codigo = 'TECNICO_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fd500000-0000-0000-0000-00000000000a', 'fd000000-0000-0000-0000-00000000000a'),
  ('fd500000-0000-0000-0000-00000000000b', 'fd000000-0000-0000-0000-00000000000b');

-- Edificio A: una alarma crítica y un sensor sin comunicación; edificio B: un sensor sin comunicación
insert into reglas_alarma (id, id_edificio, id_sensor, codigo, nombre, condicion, umbral, id_nivel_alarma)
select 'fd900000-0000-0000-0000-00000000000a', 'fd200000-0000-0000-0000-00000000000a', 'fd800000-0000-0000-0000-0000000000a1',
       'T_ALTA', 'Temperatura alta', 'MAYOR_QUE', 30, n.id from niveles_alarma n where n.codigo = 'CRITICA';
insert into eventos_alarma (id_regla_alarma, id_sensor, valor_detectado) values
  ('fd900000-0000-0000-0000-00000000000a', 'fd800000-0000-0000-0000-0000000000a1', 31);
insert into incidencias_comunicacion (id_sensor) values
  ('fd800000-0000-0000-0000-0000000000a2'), ('fd800000-0000-0000-0000-0000000000b1');

create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;

select pg_temp.login('e9200000-0000-0000-0000-000000000001');
set local role authenticated;
insert into resultados (t) select is((resumen_alarmas_usuario()->>'total')::integer, 2, 'El Partner A cuenta sus dos alarmas (alarma y falta de comunicación)');
insert into resultados (t) select is(resumen_alarmas_usuario()->>'nivel', 'CRITICA', 'La campana toma el nivel más grave');
insert into resultados (t) select is(resumen_alarmas_usuario()->'edificios'->0->>'nombre', 'Edificio A', 'Lista por edificio');
reset role;

select pg_temp.login('e9200000-0000-0000-0000-000000000002');
set local role authenticated;
insert into resultados (t) select is((resumen_alarmas_usuario()->>'total')::integer, 1, 'El Partner B NO ve las alarmas del Partner A');
insert into resultados (t) select is((select count(*)::integer from jsonb_array_elements(resumen_alarmas_usuario()->'edificios') e
           where e->>'nombre' = 'Edificio A'), 0, 'El Partner B NO ve el Edificio A en la lista');
reset role;

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 5 then
    raise exception 'RESULTADO: % de 5 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
