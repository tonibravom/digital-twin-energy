-- =========================================================
-- EDIFICIO DE DEMOSTRACIÓN CON LOS SIMULADORES (solo desarrollo y demos)
-- Pegar entero en el SQL Editor de Supabase y pulsar Run.
--
-- Crea (si no existen) un Partner, un cliente y un edificio de oficinas de
-- demostración con dos conexiones:
--   - API_REST → API REST simulada que la plataforma consulta (GET, JSON) cada 15 min:
--                5 sensores + 30 días de histórico
--   - LORAWAN  → el servidor LoRaWAN simulado (3 dispositivos, 6 sensores)
-- y genera los secretos que hay que poner en Render. Cada ejecución genera
-- secretos NUEVOS: actualice entonces las variables de Render.
--
-- El resultado (tabla al final) contiene secretos: cópielos directamente a
-- Render y no los pegue en ningún chat ni documento.
-- =========================================================

drop table if exists pg_temp.demo_resultado;
create temp table demo_resultado (paso int, variable text, valor text);

do $$
declare
  v_api text := 'https://digital-twin-energy-api.onrender.com';   -- ← cámbielo si su API tiene otra dirección
  v_prov uuid; v_cli uuid; v_edif uuid; v_p0 uuid; v_p1 uuid;
  v_vestibulo uuid; v_oficina uuid; v_sala uuid;
  v_rest uuid; v_lora uuid;
  v_token_lora text; v_clave_api text; v_tareas text;
begin
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

  select id into v_edif from public.edificios where codigo = 'DEMO-OFICINAS';
  if v_edif is null then
    insert into public.edificios (id_cliente, codigo, nombre, direccion, municipio, provincia, latitud, longitud,
                                  superficie_construida_m2, numero_plantas, uso_edificio)
    values (v_cli, 'DEMO-OFICINAS', 'Oficinas de demostración', 'Carrer de la Demostració, 1', 'Sabadell', null,
            41.5463, 2.1086, 2400, 2, 'Oficinas')
    returning id into v_edif;
  end if;
  insert into public.proveedores_edificios (id_proveedor, id_edificio)
  select v_prov, v_edif where not exists (
    select 1 from public.proveedores_edificios where id_proveedor = v_prov and id_edificio = v_edif and activo);

  -- Plantas y recintos
  select id into v_p0 from public.plantas where id_edificio = v_edif and codigo = 'P0';
  if v_p0 is null then
    insert into public.plantas (id_edificio, codigo, nombre, nivel) values (v_edif, 'P0', 'Planta baja', 0) returning id into v_p0;
  end if;
  select id into v_p1 from public.plantas where id_edificio = v_edif and codigo = 'P1';
  if v_p1 is null then
    insert into public.plantas (id_edificio, codigo, nombre, nivel) values (v_edif, 'P1', 'Planta primera', 1) returning id into v_p1;
  end if;
  select id into v_vestibulo from public.recintos where id_planta = v_p0 and codigo = 'VESTIBULO';
  if v_vestibulo is null then
    insert into public.recintos (id_planta, codigo, nombre) values (v_p0, 'VESTIBULO', 'Vestíbulo') returning id into v_vestibulo;
  end if;
  select id into v_sala from public.recintos where id_planta = v_p0 and codigo = 'SALA-INST';
  if v_sala is null then
    insert into public.recintos (id_planta, codigo, nombre) values (v_p0, 'SALA-INST', 'Sala de instalaciones') returning id into v_sala;
  end if;
  select id into v_oficina from public.recintos where id_planta = v_p1 and codigo = 'OFICINA-1';
  if v_oficina is null then
    insert into public.recintos (id_planta, codigo, nombre) values (v_p1, 'OFICINA-1', 'Oficina diáfana') returning id into v_oficina;
  end if;

  -- Conexiones
  select id into v_rest from public.conexiones where id_edificio = v_edif and codigo = 'API_REST';
  if v_rest is null then
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
  end if;
  select id into v_lora from public.conexiones where id_edificio = v_edif and codigo = 'LORAWAN';
  if v_lora is null then
    insert into public.conexiones (id_edificio, id_tipo_conexion, codigo, nombre, configuracion)
    select v_edif, id, 'LORAWAN', 'Gateway LoRaWAN (simulado)', '{"servidor_red": "THE_THINGS_STACK"}'::jsonb
    from public.tipos_conexion where codigo = 'LORAWAN'
    returning id into v_lora;
  end if;

  -- Sensores (código, nombre, recinto, conexión, dirección, familia, naturaleza, tratamiento, unidad, energía, flujo, escala, unidad origen)
  insert into public.sensores (id_conexion, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento,
                               unidad, id_tipo_energia, id_flujo_energia, escala, unidad_origen)
  select x.con, x.rec, x.cod, x.nom, x.dir::jsonb, f.id, n.id, t.id, x.uni, te.id, fe.id, x.esc, x.uni_origen
  from (values
    (v_rest, v_sala, 'CONT-GENERAL', 'Contador general de electricidad', '{"ruta_valor": "valor", "filtro": {"punto": "CONT-GENERAL"}}', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 1.0, null),
    (v_rest, v_sala, 'POT-GENERAL', 'Potencia del contador general', '{"ruta_valor": "valor", "filtro": {"punto": "POT-GENERAL"}}', 'POTENCIA', 'INSTANTANEA', 'PROMEDIO', 'kW', 'ELECTRICIDAD', 'CONSUMO', 1.0, null),
    (v_rest, v_sala, 'FV-PROD', 'Producción fotovoltaica', '{"ruta_valor": "valor", "filtro": {"punto": "FV-PROD"}}', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'GENERACION', 1.0, null),
    (v_rest, v_vestibulo, 'TEMP-EXT', 'Temperatura exterior', '{"ruta_valor": "valor", "filtro": {"punto": "TEMP-EXT"}}', 'TEMPERATURA', 'INSTANTANEA', 'PROMEDIO', '°C', null, null, 1.0, null),
    (v_rest, v_sala, 'GAS-CONT', 'Contador de gas', '{"ruta_valor": "valor", "filtro": {"punto": "GAS-CONT"}}', 'OTRA', 'ACUMULATIVA', 'DELTA', 'm³', 'GAS', 'CONSUMO', 1.0, null),
    (v_lora, v_oficina, 'AMB-T', 'Temperatura oficina', '{"dev_eui": "24E124710B000001", "campo": "temperature"}', 'TEMPERATURA', 'INSTANTANEA', 'PROMEDIO', '°C', null, null, 1.0, null),
    (v_lora, v_oficina, 'AMB-HR', 'Humedad oficina', '{"dev_eui": "24E124710B000001", "campo": "humidity"}', 'HUMEDAD', 'INSTANTANEA', 'PROMEDIO', '%', null, null, 1.0, null),
    (v_lora, v_oficina, 'AMB-CO2', 'CO₂ oficina', '{"dev_eui": "24E124710B000001", "campo": "co2"}', 'CO2', 'INSTANTANEA', 'PROMEDIO', 'ppm', null, null, 1.0, null),
    (v_lora, v_sala, 'AGUA-CONT', 'Contador de agua', '{"dev_eui": "24E124136B000002", "campo": "water"}', 'OTRA', 'ACUMULATIVA', 'DELTA', 'm³', 'AGUA', 'CONSUMO', 0.001, 'L'),
    (v_lora, v_sala, 'CLIMA-E', 'Energía de climatización', '{"dev_eui": "24E124746B000003", "campo": "active_energy"}', 'ENERGIA', 'ACUMULATIVA', 'DELTA', 'kWh', 'ELECTRICIDAD', 'CONSUMO', 1.0, null),
    (v_lora, v_sala, 'CLIMA-P', 'Potencia de climatización', '{"dev_eui": "24E124746B000003", "campo": "power"}', 'POTENCIA', 'INSTANTANEA', 'PROMEDIO', 'kW', 'ELECTRICIDAD', 'CONSUMO', 0.001, 'W')
  ) x(con, rec, cod, nom, dir, fam, nat, tra, uni, ene, flu, esc, uni_origen)
  join public.familias_sensor f on f.codigo = x.fam
  join public.naturalezas_sensor n on n.codigo = x.nat
  join public.tratamientos_sensor t on t.codigo = x.tra
  left join public.tipos_energia te on te.codigo = x.ene
  left join public.flujos_energia fe on fe.codigo = x.flu
  where not exists (select 1 from public.sensores s where s.id_recinto = x.rec and s.codigo = x.cod);

  -- Secretos nuevos
  v_token_lora := public.generar_token_conexion(v_lora);
  v_clave_api := 'sim_' || pg_catalog.replace(gen_random_uuid()::text, '-', '');
  perform public.guardar_secreto_conexion(v_rest, v_clave_api);
  v_tareas := pg_catalog.replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

  if exists (select 1 from vault.secrets where name = 'api_url') then
    perform vault.update_secret((select id from vault.secrets where name = 'api_url'), v_api);
  else
    perform vault.create_secret(v_api, 'api_url', 'Dirección de la API (tarea periódica)');
  end if;
  if exists (select 1 from vault.secrets where name = 'api_tareas_secreto') then
    perform vault.update_secret((select id from vault.secrets where name = 'api_tareas_secreto'), v_tareas);
  else
    perform vault.create_secret(v_tareas, 'api_tareas_secreto', 'Secreto de la tarea periódica de la API');
  end if;

  -- 30 días de histórico de la API REST simulada (la tarea lo irá cargando)
  if (select recuperacion_estado from public.conexiones where id = v_rest) is null then
    perform public.solicitar_recuperacion(v_rest, current_date - 30);
  end if;

  insert into demo_resultado values
    (1, 'SIMULADOR_ACTIVO', 'true'),
    (2, 'TAREAS_SECRETO', v_tareas),
    (3, 'SIMULADOR_API_KEY', v_clave_api),
    (4, 'SIMULADOR_LORAWAN_TOKEN', v_token_lora);
end;
$$;

select variable as "Variable en Render", valor as "Valor" from demo_resultado order by paso;
