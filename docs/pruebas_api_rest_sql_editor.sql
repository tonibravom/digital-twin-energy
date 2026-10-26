-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DEL CONECTOR API REST GENÉRICO (migración 029)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(8);

insert into clientes (id, codigo, nombre) values ('f1100000-0000-0000-0000-000000000001', 'RC', 'Cliente');
insert into edificios (id, id_cliente, codigo, nombre) values
  ('f1200000-0000-0000-0000-000000000001', 'f1100000-0000-0000-0000-000000000001', 'RE', 'Edificio');
insert into plantas (id, id_edificio, codigo, nombre) values
  ('f1300000-0000-0000-0000-000000000001', 'f1200000-0000-0000-0000-000000000001', 'P0', 'PB');
insert into recintos (id, id_planta, codigo, nombre) values
  ('f1400000-0000-0000-0000-000000000001', 'f1300000-0000-0000-0000-000000000001', 'R', 'Sala');

create function pg_temp.conexion(p_cod text, p_conf jsonb) returns uuid language sql as $$
  insert into conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
  select 'f1200000-0000-0000-0000-000000000001', id, p_cod, p_cod, p_conf from tipos_conexion where codigo = 'API_REST'
  returning id;
$$;

insert into resultados (t) select ok((select modo = 'CONSULTA' and admite_recuperacion and nombre = 'API REST (JSON)' from tipos_conexion where codigo = 'API_REST'),
  'El tipo API REST es de consulta y admite recuperar históricos');
insert into resultados (t) select ok(pg_temp.conexion('OK', '{"url": "https://api.ejemplo.com/medidas", "autenticacion": "API_KEY", "cabecera_clave": "X-API-Key",
          "ruta_lista": "$.datos", "campo_fecha": "fecha", "parametro_desde": "desde", "parametro_hasta": "hasta"}') is not null,
  'Se crea una conexión API REST con clave en cabecera y parámetros de periodo');
insert into resultados (t) select throws_like($$ select pg_temp.conexion('URL', '{"url": "ftp://x", "autenticacion": "NINGUNA", "ruta_lista": "$", "campo_fecha": "t"}') $$,
  '%http%', 'La URL debe ser http o https');
insert into resultados (t) select throws_like($$ select pg_temp.conexion('CAB', '{"url": "https://x", "autenticacion": "API_KEY", "ruta_lista": "$", "campo_fecha": "t"}') $$,
  '%cabecera_clave%', 'Con API_KEY hay que indicar la cabecera');
insert into resultados (t) select throws_like($$ select pg_temp.conexion('PER', '{"url": "https://x", "autenticacion": "NINGUNA", "ruta_lista": "$", "campo_fecha": "t", "parametro_desde": "from"}') $$,
  '%desde y hasta%', 'Los parámetros de periodo van en pareja');
insert into resultados (t) select throws_like($$ select pg_temp.conexion('SEC', '{"url": "https://x", "autenticacion": "BEARER", "ruta_lista": "$", "campo_fecha": "t", "api_key": "abc"}') $$,
  '%secretos%', 'La clave nunca puede ir en la configuración');

insert into sensores (id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select c.id, 'f1400000-0000-0000-0000-000000000001', f.id, n.id, t.id, 'CONT', 'Contador', 'kWh',
       '{"ruta_valor": "valor", "filtro": {"punto": "CONT-GENERAL"}}'
from conexiones c, familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
where c.codigo = 'OK' and f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA';
insert into resultados (t) select is((select count(*) from sensores s join conexiones c on c.id = s.id_conexion
           where s.codigo = 'CONT' and c.codigo = 'OK' and c.id_edificio = 'f1200000-0000-0000-0000-000000000001'), 1::bigint, 'Un punto se define con el campo del valor y un filtro');
insert into resultados (t) select throws_like(
  $$ insert into sensores (id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
     select c.id, 'f1400000-0000-0000-0000-000000000001', f.id, n.id, t.id, 'MAL', 'Mal', 'kWh', '{"filtro": {"punto": "X"}}'
     from conexiones c, familias_sensor f, naturalezas_sensor n, tratamientos_sensor t
     where c.codigo = 'OK' and f.codigo = 'ENERGIA' and n.codigo = 'ACUMULATIVA' and t.codigo = 'DELTA' $$,
  '%ruta_valor%', 'El campo del valor es obligatorio');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 8 then
    raise exception 'RESULTADO: % de 8 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
