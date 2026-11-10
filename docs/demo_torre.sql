-- =========================================================
-- TORRE DE OFICINAS DE DEMOSTRACIÓN CON LOS SIMULADORES (solo desarrollo y demos)
-- Requiere la migración 037 y la API 0.8.0 o posterior (simula todos sus puntos).
-- Pegar entero en el SQL Editor de Supabase y pulsar Run.
--
-- Crea el edificio DEMO-TORRE (si ya existe, bórrelo antes con demo_limpiar.sql
-- poniendo v_codigo := 'DEMO-TORRE'):
--   Sótano      aparcamiento                      cuadro: total y alumbrado
--   Planta baja vestíbulo, cuarto de contadores   cuadro: total y alumbrado
--               y local comercial                 cuadro del local (cuelga del de planta baja):
--                                                 total y alumbrado; ambiente por LoRaWAN
--   Plantas 1-5 oficinas                          cuadro: total y alumbrado; ambiente
--   Cubierta    zona técnica y sala de calderas   cuadro general de cubierta: total, refrigeración,
--                                                 renovación de aire, alumbrado e informática;
--                                                 fotovoltaica; caldera de gas (calefacción y ACS)
--   Contador general (importación y exportación), potencia y factor de potencia;
--   contador de agua (LoRaWAN).
-- Conexiones:
--   API_REST → API REST simulada (todos los medidores y el ambiente de las
--              oficinas) + 30 días de histórico
--   LORAWAN  → servidor LoRaWAN simulado (ambiente del local y agua)
-- Configura además las magnitudes del edificio, la función de cada medidor, su
-- uso y su cuadro, y el horario (laborables de 08:00 a 19:00).
--
-- El resultado (tabla al final) contiene secretos: cópielos directamente a
-- Render y no los pegue en ningún chat ni documento.
-- =========================================================

drop table if exists pg_temp.demo_resultado;
create temp table demo_resultado (paso int, variable text, valor text);

do $$
declare
  v_api text := 'https://digital-twin-energy-api.onrender.com';   -- ← cámbielo si su API tiene otra dirección
  v_prov uuid; v_cli uuid; v_edif uuid;
  v_rest uuid; v_lora uuid;
  v_token_lora text; v_clave_api text; v_tareas text;
  r record;
  v_me uuid;
begin
  if exists (select 1 from public.edificios where codigo = 'DEMO-TORRE') then
    raise exception 'El edificio DEMO-TORRE ya existe: bórrelo antes con demo_limpiar.sql (v_codigo := ''DEMO-TORRE'')';
  end if;

  -- Organización
  select id into v_prov from public.proveedores where codigo = 'DEMO';
  if v_prov is null then
    insert into public.proveedores (codigo, nombre) values ('DEMO', 'Partner de demostración') returning id into v_prov;
  end if;
  select id into v_cli from public.clientes where codigo = 'DEMO';
  if v_cli is null then
    insert into public.clientes (codigo, nombre) values ('DEMO', 'Cliente de demostración') returning id into v_cli;
  end if;
  insert into public.proveedores_clientes (id_proveedor, id_cliente)
  select v_prov, v_cli where not exists (
    select 1 from public.proveedores_clientes where id_proveedor = v_prov and id_cliente = v_cli and activo);

  insert into public.edificios (id_cliente, codigo, nombre, direccion, municipio, latitud, longitud,
                                superficie_construida_m2, numero_plantas, uso_edificio)
  values (v_cli, 'DEMO-TORRE', 'Torre de oficinas de demostración', 'Carrer de la Demostració, 1', 'Sabadell',
          41.5463, 2.1086, 6500, 8, 'Oficinas')
  returning id into v_edif;
  insert into public.proveedores_edificios (id_proveedor, id_edificio) values (v_prov, v_edif);

  -- Plantas y recintos
  insert into public.plantas (id_edificio, codigo, nombre, nivel)
  select v_edif, x.cod, x.nom, x.niv
  from (values ('SOT', 'Sótano', -1), ('P0', 'Planta baja', 0), ('P1', 'Planta 1', 1), ('P2', 'Planta 2', 2),
               ('P3', 'Planta 3', 3), ('P4', 'Planta 4', 4), ('P5', 'Planta 5', 5), ('CUB', 'Cubierta', 6)) x(cod, nom, niv);
  insert into public.recintos (id_planta, codigo, nombre)
  select p.id, x.cod, x.nom
  from (values ('SOT', 'APARCAMIENTO', 'Aparcamiento'), ('P0', 'VESTIBULO', 'Vestíbulo'),
               ('P0', 'CUARTO-CONT', 'Cuarto de contadores'), ('P0', 'LOCAL', 'Local comercial'),
               ('P1', 'OFICINAS-P1', 'Oficinas planta 1'), ('P2', 'OFICINAS-P2', 'Oficinas planta 2'),
               ('P3', 'OFICINAS-P3', 'Oficinas planta 3'), ('P4', 'OFICINAS-P4', 'Oficinas planta 4'),
               ('P5', 'OFICINAS-P5', 'Oficinas planta 5'), ('CUB', 'ZONA-TEC', 'Zona técnica de cubierta'),
               ('CUB', 'SALA-CALDERAS', 'Sala de calderas')) x(planta, cod, nom)
  join public.plantas p on p.id_edificio = v_edif and p.codigo = x.planta;

  -- Cuadros eléctricos (el del local cuelga del de planta baja)
  insert into public.cuadros_electricos (id_edificio, id_planta, codigo, nombre)
  select v_edif, p.id, x.cod, x.nom
  from (values ('SOT', 'C-SOT', 'Cuadro de sótano'), ('P0', 'C-PB', 'Cuadro de planta baja'),
               ('P1', 'C-P1', 'Cuadro de planta 1'), ('P2', 'C-P2', 'Cuadro de planta 2'), ('P3', 'C-P3', 'Cuadro de planta 3'),
               ('P4', 'C-P4', 'Cuadro de planta 4'), ('P5', 'C-P5', 'Cuadro de planta 5'),
               ('CUB', 'C-CUB', 'Cuadro general de cubierta')) x(planta, cod, nom)
  join public.plantas p on p.id_edificio = v_edif and p.codigo = x.planta;
  insert into public.cuadros_electricos (id_edificio, id_recinto, id_cuadro_padre, codigo, nombre)
  select v_edif, rc.id, c.id, 'C-LOCAL', 'Cuadro del local comercial'
  from public.recintos rc join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.cuadros_electricos c on c.id_edificio = v_edif and c.codigo = 'C-PB'
  where rc.codigo = 'LOCAL';

  -- Conexiones
  insert into public.conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
  select v_edif, id, 'API_REST', 'API REST de medidas (simulada)',
         pg_catalog.jsonb_build_object(
           'url', v_api || '/simulador/api/medidas', 'metodo', 'GET',
           'autenticacion', 'API_KEY', 'cabecera_clave', 'X-API-Key',
           'ruta_lista', '$.datos', 'campo_fecha', 'fecha', 'formato_fecha', 'ISO8601',
           'parametro_desde', 'desde', 'parametro_hasta', 'hasta', 'formato_parametros', 'ISO8601',
           'ventana_horas', 24)
  from public.tipos_conexion where codigo = 'API_REST'
  returning id into v_rest;
  insert into public.conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
  select v_edif, id, 'LORAWAN', 'Gateway LoRaWAN (simulado)', '{"servidor_red": "THE_THINGS_STACK"}'::jsonb
  from public.tipos_conexion where codigo = 'LORAWAN'
  returning id into v_lora;

  -- Sensores: conexión, recinto, código, nombre, dirección, familia, naturaleza, tratamiento, unidad,
  -- energía, flujo, escala, unidad de origen, función del medidor, uso y cuadro
  create temp table demo_sensores on commit drop as
  select * from (values
    -- Contador general, potencia y factor de potencia
    ('R', 'CUARTO-CONT', 'CONT-GENERAL', 'Contador general · importación de la red', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'GENERAL', null, null),
    ('R', 'CUARTO-CONT', 'EXP-GENERAL', 'Contador general · exportación a la red', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'EXPORTACION', 'GENERAL', null, null),
    ('R', 'CUARTO-CONT', 'POT-GENERAL', 'Potencia del contador general', 'POTENCIA', 'INSTANTANEA', 'PROMEDIO', 'kW', 'ELECTRICIDAD', 'CONSUMO', null, null, null),
    ('R', 'CUARTO-CONT', 'FP-GENERAL', 'Factor de potencia del contador general', 'FACTOR_POTENCIA', 'INSTANTANEA', 'PROMEDIO', '-', 'ELECTRICIDAD', 'CONSUMO', null, null, null),
    -- Producción y gas
    ('R', 'ZONA-TEC', 'FV-PROD', 'Producción fotovoltaica', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'GENERACION', null, null, null),
    ('R', 'SALA-CALDERAS', 'GAS-CALDERA', 'Contador de gas de la caldera', 'OTRA', 'ACUMULATIVA', 'DELTA', 'm³', 'GAS', 'CONSUMO', 'USO', 'HVAC_CALEFACCION_ACS', null),
    -- Cuadros de planta: total y alumbrado
    ('R', 'APARCAMIENTO', 'E-SOT-T', 'Cuadro de sótano · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-SOT'),
    ('R', 'APARCAMIENTO', 'E-SOT-A', 'Cuadro de sótano · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-SOT'),
    ('R', 'VESTIBULO', 'E-PB-T', 'Cuadro de planta baja · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-PB'),
    ('R', 'VESTIBULO', 'E-PB-A', 'Cuadro de planta baja · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-PB'),
    ('R', 'LOCAL', 'E-LOC-T', 'Cuadro del local · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-LOCAL'),
    ('R', 'LOCAL', 'E-LOC-A', 'Cuadro del local · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-LOCAL'),
    ('R', 'OFICINAS-P1', 'E-P1-T', 'Cuadro de planta 1 · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-P1'),
    ('R', 'OFICINAS-P1', 'E-P1-A', 'Cuadro de planta 1 · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-P1'),
    ('R', 'OFICINAS-P2', 'E-P2-T', 'Cuadro de planta 2 · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-P2'),
    ('R', 'OFICINAS-P2', 'E-P2-A', 'Cuadro de planta 2 · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-P2'),
    ('R', 'OFICINAS-P3', 'E-P3-T', 'Cuadro de planta 3 · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-P3'),
    ('R', 'OFICINAS-P3', 'E-P3-A', 'Cuadro de planta 3 · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-P3'),
    ('R', 'OFICINAS-P4', 'E-P4-T', 'Cuadro de planta 4 · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-P4'),
    ('R', 'OFICINAS-P4', 'E-P4-A', 'Cuadro de planta 4 · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-P4'),
    ('R', 'OFICINAS-P5', 'E-P5-T', 'Cuadro de planta 5 · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-P5'),
    ('R', 'OFICINAS-P5', 'E-P5-A', 'Cuadro de planta 5 · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-P5'),
    -- Cuadro general de cubierta
    ('R', 'ZONA-TEC', 'E-CUB-T', 'Cuadro de cubierta · total', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'CUADRO', null, 'C-CUB'),
    ('R', 'ZONA-TEC', 'E-CUB-REF', 'Cuadro de cubierta · refrigeración', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'HVAC_REFRIGERACION', 'C-CUB'),
    ('R', 'ZONA-TEC', 'E-CUB-REN', 'Cuadro de cubierta · renovación de aire', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'HVAC_RENOVACION', 'C-CUB'),
    ('R', 'ZONA-TEC', 'E-CUB-A', 'Cuadro de cubierta · alumbrado', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'ILUMINACION', 'C-CUB'),
    ('R', 'ZONA-TEC', 'E-CUB-INF', 'Cuadro de cubierta · informática', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 'USO', 'INFORMATICA', 'C-CUB'),
    -- Agua (LoRaWAN, pulsos en litros)
    ('L', 'CUARTO-CONT', 'AGUA-CONT', 'Contador de agua', 'OTRA', 'ACUMULATIVA', 'DELTA', 'm³', 'AGUA', 'CONSUMO', null, null, null)
  ) x(con, rec, cod, nom, fam, nat, tra, uni, ene, flu, funcion, uso, cuadro);

  insert into public.sensores (id_conexion, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento,
                               unidad, id_tipo_energia, id_flujo_energia, escala, unidad_origen,
                               funcion_medidor, id_uso_energia, id_cuadro)
  select case x.con when 'R' then v_rest else v_lora end, rc.id, x.cod, x.nom,
         case x.con when 'R' then pg_catalog.jsonb_build_object('ruta_valor', 'valor', 'filtro', pg_catalog.jsonb_build_object('punto', x.cod))
                    else '{"dev_eui": "24E124136B000002", "campo": "water"}'::jsonb end,
         f.id, n.id, t.id, x.uni, te.id, fe.id,
         case x.cod when 'AGUA-CONT' then 0.001 else 1.0 end, case x.cod when 'AGUA-CONT' then 'L' end,
         x.funcion, u.id, c.id
  from demo_sensores x
  join public.recintos rc on rc.codigo = x.rec
  join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.familias_sensor f on f.codigo = x.fam
  join public.naturalezas_sensor n on n.codigo = x.nat
  join public.tratamientos_sensor t on t.codigo = x.tra
  left join public.tipos_energia te on te.codigo = x.ene
  left join public.flujos_energia fe on fe.codigo = x.flu
  left join public.usos_energia u on u.codigo = x.uso
  left join public.cuadros_electricos c on c.id_edificio = v_edif and c.codigo = x.cuadro;

  -- Ambiente: temperatura, humedad y CO₂ (API REST en sótano, planta baja y oficinas; LoRaWAN en el local)
  insert into public.sensores (id_conexion, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento, unidad)
  select case when x.amb = 'LOC' then v_lora else v_rest end, rc.id, 'AMB-' || x.amb || '-' || m.suf,
         m.nom || ' · ' || rc.nombre,
         case when x.amb = 'LOC' then pg_catalog.jsonb_build_object('dev_eui', '24E124710B000001', 'campo', m.campo_lora)
              else pg_catalog.jsonb_build_object('ruta_valor', 'valor', 'filtro',
                     pg_catalog.jsonb_build_object('punto', 'AMB-' || x.amb || '-' || m.suf)) end,
         f.id, n.id, t.id, m.uni
  from (values ('SOT', 'APARCAMIENTO'), ('PB', 'VESTIBULO'), ('LOC', 'LOCAL'), ('P1', 'OFICINAS-P1'), ('P2', 'OFICINAS-P2'),
               ('P3', 'OFICINAS-P3'), ('P4', 'OFICINAS-P4'), ('P5', 'OFICINAS-P5')) x(amb, rec)
  cross join (values ('T', 'Temperatura', 'TEMPERATURA', '°C', 'temperature'), ('HR', 'Humedad', 'HUMEDAD', '%', 'humidity'),
                     ('CO2', 'CO₂', 'CO2', 'ppm', 'co2')) m(suf, nom, fam, uni, campo_lora)
  join public.recintos rc on rc.codigo = x.rec
  join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.familias_sensor f on f.codigo = m.fam
  join public.naturalezas_sensor n on n.codigo = 'INSTANTANEA'
  join public.tratamientos_sensor t on t.codigo = 'PROMEDIO';

  -- Magnitudes del edificio y el sensor que las alimenta
  for r in select * from (values
      ('CONSUMO_ELECTRICIDAD', 'CONT-GENERAL'), ('ENERGIA_EXPORTADA', 'EXP-GENERAL'),
      ('GENERACION_FOTOVOLTAICA', 'FV-PROD'), ('CONSUMO_GAS', 'GAS-CALDERA'), ('CONSUMO_AGUA', 'AGUA-CONT'),
      ('POTENCIA_TOTAL', 'POT-GENERAL'), ('FACTOR_POTENCIA', 'FP-GENERAL')) x(magnitud, sensor)
  loop
    insert into public.magnitudes_edificio (id_edificio, id_magnitud, ambito)
    select v_edif, m.id, 'EDIFICIO' from public.magnitudes m where m.codigo = r.magnitud
    returning id into v_me;
    insert into public.magnitudes_fuentes (id_magnitud_edificio, id_sensor)
    select v_me, s.id from public.sensores s
    where s.codigo = r.sensor and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
  end loop;

  -- Horario tipo y calendario (año actual, incluido lo ya pasado, y el siguiente)
  insert into public.horarios_tipo_edificio (id_edificio, dia_semana, laborable, hora_inicio, hora_fin)
  select v_edif, d, d <= 5, case when d <= 5 then time '08:00' end, case when d <= 5 then time '19:00' end
  from pg_catalog.generate_series(1, 7) d;
  perform public.generar_calendario(v_edif, extract(year from current_date)::integer, false, true);
  perform public.generar_calendario(v_edif, extract(year from current_date)::integer + 1);

  -- Secretos de las conexiones (nuevos) y de la tarea periódica (se conserva si ya existe)
  v_token_lora := public.generar_token_conexion(v_lora);
  v_clave_api := 'sim_' || pg_catalog.replace(gen_random_uuid()::text, '-', '');
  perform public.guardar_secreto_conexion(v_rest, v_clave_api);

  if exists (select 1 from vault.secrets where name = 'api_url') then
    perform vault.update_secret((select id from vault.secrets where name = 'api_url'), v_api);
  else
    perform vault.create_secret(v_api, 'api_url', 'Dirección de la API (tarea periódica)');
  end if;
  if not exists (select 1 from vault.secrets where name = 'api_tareas_secreto') then
    v_tareas := pg_catalog.replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    perform vault.create_secret(v_tareas, 'api_tareas_secreto', 'Secreto de la tarea periódica de la API');
  end if;

  -- 30 días de histórico de la API REST simulada (la tarea periódica lo va cargando)
  perform public.solicitar_recuperacion(v_rest, current_date - 30);

  insert into demo_resultado values
    (1, 'SIMULADOR_ACTIVO', 'true'),
    (2, 'TAREAS_SECRETO', coalesce(v_tareas, '(sin cambios: deje el valor que ya tiene en Render)')),
    (3, 'SIMULADOR_API_KEY', v_clave_api),
    (4, 'SIMULADOR_LORAWAN_TOKEN', v_token_lora);
end;
$$;

select variable as "Variable en Render", valor as "Valor" from demo_resultado order by paso;
