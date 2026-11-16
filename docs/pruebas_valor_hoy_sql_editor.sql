-- VERSIÓN PARA EL SQL EDITOR DE SUPABASE: pegar entero y pulsar Run.
-- Al final sale un mensaje en ROJO a propósito con el resumen;
-- al ser un error, deshace todos los datos de prueba.
-- =========================================================
-- PRUEBAS DEL VALOR DE HOY Y EL SUMINISTRO DE CADA SENSOR (migración 046, D56)
-- Ejecutar con:  npx supabase test db
-- =========================================================
begin;
set search_path = public, extensions;

create temp table resultados (n serial, t text);
grant all on resultados to public;
grant all on sequence resultados_n_seq to public;
select plan(4);

insert into proveedores (id, codigo, nombre) values ('fc700000-0000-0000-0000-00000000000a', 'HA', 'Partner hoy');
insert into clientes (id, codigo, nombre) values ('fc710000-0000-0000-0000-000000000001', 'HC', 'Cliente hoy');
insert into edificios (id, id_cliente, codigo, nombre, zona_horaria) values
  ('fc720000-0000-0000-0000-000000000001', 'fc710000-0000-0000-0000-000000000001', 'HE', 'Edificio hoy', 'Europe/Madrid');
insert into plantas (id, id_edificio, codigo, nombre, nivel) values
  ('fc730000-0000-0000-0000-000000000001', 'fc720000-0000-0000-0000-000000000001', 'P0', 'Planta baja', 0);
insert into recintos (id, id_planta, codigo, nombre) values
  ('fc740000-0000-0000-0000-000000000001', 'fc730000-0000-0000-0000-000000000001', 'CC', 'Cuarto de contadores');
insert into conexiones (id, id_edificio, id_tipo_conexion, codigo, nombre)
select 'fc750000-0000-0000-0000-000000000001', 'fc720000-0000-0000-0000-000000000001', id, 'HTTP', 'Pasarela'
from tipos_conexion where codigo = 'ENVIO_HTTP';
insert into sensores (id, id_conexion, id_recinto, id_familia, id_naturaleza, id_tratamiento, codigo, nombre, unidad, direccion)
select x.id::uuid, 'fc750000-0000-0000-0000-000000000001', 'fc740000-0000-0000-0000-000000000001', f.id, n.id, t.id, x.cod, x.cod, x.u,
       jsonb_build_object('clave', x.cod)
from (values ('fc760000-0000-0000-0000-000000000001', 'RED', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh'),
             ('fc760000-0000-0000-0000-000000000002', 'T', 'TEMPERATURA', 'INSTANTANEA', 'PROMEDIO', '°C')) x(id, cod, fam, nat, tra, u)
join familias_sensor f on f.codigo = x.fam join naturalezas_sensor n on n.codigo = x.nat join tratamientos_sensor t on t.codigo = x.tra;
insert into magnitudes_edificio (id, id_edificio, id_magnitud, ambito)
select 'fc770000-0000-0000-0000-000000000001', 'fc720000-0000-0000-0000-000000000001', id, 'EDIFICIO'
from magnitudes where codigo = 'CONSUMO_ELECTRICIDAD';
insert into magnitudes_fuentes (id_magnitud_edificio, id_sensor) values
  ('fc770000-0000-0000-0000-000000000001', 'fc760000-0000-0000-0000-000000000001');

-- Contador: 1.000 kWh a las 23:45 de ayer y 1.042 kWh ahora (hora del edificio)
insert into lecturas (id_sensor, fecha_hora, valor) values
  ('fc760000-0000-0000-0000-000000000001', ((now() at time zone 'Europe/Madrid')::date::timestamp - interval '15 minutes') at time zone 'Europe/Madrid', 1000),
  ('fc760000-0000-0000-0000-000000000001', now() - interval '1 minute', 1042),
  ('fc760000-0000-0000-0000-000000000002', now() - interval '1 minute', 21.5);

insert into resultados (t) select is((select suministro from sensores_estado_edificio('fc720000-0000-0000-0000-000000000001') where codigo = 'RED'), 'ELECTRICIDAD',
  'El contador que alimenta el consumo de electricidad es el suministro de red');
insert into resultados (t) select is((select valor_hoy from sensores_estado_edificio('fc720000-0000-0000-0000-000000000001') where codigo = 'RED'), 42::double precision,
  'Valor de hoy de un contador: última lectura de hoy menos la última antes de las 0:00');
insert into resultados (t) select is((select valor_hoy from sensores_estado_edificio('fc720000-0000-0000-0000-000000000001') where codigo = 'T'), null,
  'Un sensor instantáneo no tiene valor de hoy (se muestra su último valor)');
insert into resultados (t) select is((select suministro from sensores_estado_edificio('fc720000-0000-0000-0000-000000000001') where codigo = 'T'), null,
  'Un sensor que no alimenta un suministro no lleva suministro');

do $$
declare v_total int; v_fallos int; v_detalle text;
begin
  select count(*), count(*) filter (where t like 'not ok%'),
         string_agg(split_part(t, E'\n', 1), E'\n' order by n) filter (where t like 'not ok%')
    into v_total, v_fallos, v_detalle from resultados;
  if v_fallos = 0 and v_total = 4 then
    raise exception 'RESULTADO: % de 4 pruebas OK. Todo correcto (los datos de prueba se han deshecho).', v_total;
  else
    raise exception E'RESULTADO: % pruebas ejecutadas, % FALLAN:\n%', v_total, v_fallos, coalesce(v_detalle, '(faltan pruebas)');
  end if;
end;
$$;
