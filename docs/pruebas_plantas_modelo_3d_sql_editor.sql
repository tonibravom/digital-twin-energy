-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DE PLANTAS DEL MODELO 3D (migración 041)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(7);

insert into proveedores (id, codigo, nombre) values
  ('fa000000-0000-0000-0000-00000000000a', 'MA', 'Partner modelo A'),
  ('fa000000-0000-0000-0000-00000000000b', 'MB', 'Partner modelo B');
insert into clientes (id, codigo, nombre) values ('fa100000-0000-0000-0000-000000000001', 'MC', 'Cliente modelo');
insert into proveedores_clientes (id_proveedor, id_cliente) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa100000-0000-0000-0000-000000000001');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fa200000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000001', 'ME', 'Edificio con modelo', 'Europe/Madrid'),
  ('fa200000-0000-0000-0000-000000000002', 'fa100000-0000-0000-0000-000000000001', 'MO', 'Otro edificio', 'Europe/Madrid');
insert into proveedores_edificios (id_proveedor, id_edificio) values
  ('fa000000-0000-0000-0000-00000000000a', 'fa200000-0000-0000-0000-000000000001');
insert into plantas (id, id_edificio, codigo, nombre, nivel, niveles_modelo) values
  ('fa300000-0000-0000-0000-000000000000', 'fa200000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0, '{"L1 - Block 35","L1 - Block 37"}'),
  ('fa300000-0000-0000-0000-000000000001', 'fa200000-0000-0000-0000-000000000001', 'P1', 'Entreplanta', 1, '{}'),
  ('fa300000-0000-0000-0000-000000000009', 'fa200000-0000-0000-0000-000000000002', 'P0', 'Planta baja', 0, '{}');

insert into resultados (t) select is((select niveles_modelo from plantas where id = 'fa300000-0000-0000-0000-000000000000'),
  '{"L1 - Block 35","L1 - Block 37"}'::text[], 'Una planta guarda varios niveles del modelo');
insert into resultados (t) select is((select niveles_modelo from plantas where id = 'fa300000-0000-0000-0000-000000000001'), '{}'::text[],
  'Sin niveles asignados: lista vacía (el visor asigna por cota)');
insert into resultados (t) select throws_like($$ update plantas set niveles_modelo = '{"M1","M1"}' where id = 'fa300000-0000-0000-0000-000000000001' $$,
  '%repetido en la planta%', 'Un nivel no se repite dentro de la misma planta');
insert into resultados (t) select throws_like($$ update plantas set niveles_modelo = '{"L1 - Block 37"}' where id = 'fa300000-0000-0000-0000-000000000001' $$,
  '%ya está asignado a otra planta%', 'Un nivel del modelo pertenece a una sola planta del edificio');
insert into resultados (t) select lives_ok($$ update plantas set niveles_modelo = '{"L1 - Block 37"}' where id = 'fa300000-0000-0000-0000-000000000009' $$,
  'El mismo nombre de nivel puede usarse en otro edificio');

-- Acceso: el Partner del edificio asigna niveles; otro Partner no
insert into auth.users (id, email) values
  ('e9700000-0000-0000-0000-000000000001', 'a@modelo.test'), ('e9700000-0000-0000-0000-000000000002', 'b@modelo.test');
insert into usuarios (id, auth_user_id, nombre, email, id_rol)
select x.id::uuid, x.auth::uuid, 'U', x.mail, r.id
from (values ('fa900000-0000-0000-0000-000000000001', 'e9700000-0000-0000-0000-000000000001', 'a@modelo.test'),
             ('fa900000-0000-0000-0000-000000000002', 'e9700000-0000-0000-0000-000000000002', 'b@modelo.test')) x(id, auth, mail)
join roles r on r.codigo = 'ADMIN_PARTNER';
insert into usuarios_partners (id_usuario, id_proveedor) values
  ('fa900000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-00000000000a'),
  ('fa900000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-00000000000b');
create function pg_temp.login(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_auth, 'role', 'authenticated', 'aal', 'aal2',
                    'session_id', gen_random_uuid())::text, true);
$$;

select pg_temp.login('e9700000-0000-0000-0000-000000000001');
set local role authenticated;
update plantas set niveles_modelo = '{"M1"}' where id = 'fa300000-0000-0000-0000-000000000001';
reset role;
insert into resultados (t) select is((select niveles_modelo from plantas where id = 'fa300000-0000-0000-0000-000000000001'), '{"M1"}'::text[],
  'El Partner del edificio asigna los niveles del modelo a sus plantas');

select pg_temp.login('e9700000-0000-0000-0000-000000000002');
set local role authenticated;
update plantas set niveles_modelo = '{"INTRUSO"}' where id = 'fa300000-0000-0000-0000-000000000001';
reset role;
insert into resultados (t) select is((select niveles_modelo from plantas where id = 'fa300000-0000-0000-0000-000000000001'), '{"M1"}'::text[],
  'Otro Partner no puede cambiar las plantas del edificio');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 7 then
    raise exception 'RESULTADO: % de 7 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
