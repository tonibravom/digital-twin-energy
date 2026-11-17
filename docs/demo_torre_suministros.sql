-- =========================================================
-- SUMINISTROS DE LA TORRE DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Requiere la migración 048 y el edificio DEMO-TORRE con su modelo 3D
-- (docs/demo_torre.sql y docs/demo_torre_modelo3d.sql).
-- Pegar entero en el SQL Editor de Supabase y pulsar Run. Se puede ejecutar varias veces.
--
-- 1. Crea los suministros de electricidad, gas y agua con su ficha (datos ficticios).
-- 2. Medidor general de cada suministro (D57):
--      · electricidad: el contador general (CONT-GEN), con los obligatorios (consumo, potencia
--        y cos φ) y los opcionales del simulador: exportada, reactiva, aparente, tensión e
--        intensidad por fase y frecuencia;
--      · gas: nuevo dispositivo GAS-GEN con el contador de gas y la presión;
--      · agua: nuevo dispositivo AGUA-GEN (LoRaWAN) con el contador y el caudal.
-- 3. Las etiquetas 3D del gas y del agua pasan del sensor suelto a su dispositivo.
-- =========================================================

drop table if exists pg_temp.demo_resultado_sum;
create temp table demo_resultado_sum (paso int, dato text, valor text);

do $$
declare
  v_edif uuid;
  v_modelo uuid;
  v_sum uuid;
  v_disp uuid;
  r record;
begin
  select id into v_edif from public.edificios where codigo = 'DEMO-TORRE';
  if v_edif is null then
    raise exception 'No existe el edificio DEMO-TORRE: créelo antes con docs/demo_torre.sql';
  end if;
  select id into v_modelo from public.modelos_3d where id_edificio = v_edif and tipo_modelo = 'EDIFICIO' and activo;

  -- 1. Sensores opcionales del contador general (API REST simulada)
  insert into public.sensores (id_dispositivo, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento,
                               unidad, id_tipo_energia)
  select d.id, d.id_recinto, x.cod, x.nom,
         pg_catalog.jsonb_build_object('ruta_valor', 'valor', 'filtro', pg_catalog.jsonb_build_object('punto', x.cod)),
         f.id, n.id, t.id, x.uni, te.id
  from (values
      ('Q-GENERAL', 'Potencia reactiva del contador general', 'POTENCIA', 'kvar'),
      ('S-GENERAL', 'Potencia aparente del contador general', 'POTENCIA', 'kVA'),
      ('V-L1-GENERAL', 'Tensión L1 del contador general', 'TENSION', 'V'),
      ('V-L2-GENERAL', 'Tensión L2 del contador general', 'TENSION', 'V'),
      ('V-L3-GENERAL', 'Tensión L3 del contador general', 'TENSION', 'V'),
      ('I-L1-GENERAL', 'Intensidad L1 del contador general', 'INTENSIDAD', 'A'),
      ('I-L2-GENERAL', 'Intensidad L2 del contador general', 'INTENSIDAD', 'A'),
      ('I-L3-GENERAL', 'Intensidad L3 del contador general', 'INTENSIDAD', 'A'),
      ('F-GENERAL', 'Frecuencia de la red', 'FRECUENCIA', 'Hz')) x(cod, nom, fam, uni)
  join public.dispositivos d on d.codigo = 'CONT-GEN' and d.activo
  join public.recintos rc on rc.id = d.id_recinto
  join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.familias_sensor f on f.codigo = x.fam
  join public.naturalezas_sensor n on n.codigo = 'INSTANTANEA'
  join public.tratamientos_sensor t on t.codigo = 'PROMEDIO'
  join public.tipos_energia te on te.codigo = 'ELECTRICIDAD'
  where not exists (select 1 from public.sensores s where s.codigo = x.cod and s.activo
                    and public.obtener_edificio_recinto(s.id_recinto) = v_edif);

  -- 2. Dispositivos del gas y del agua, con sus sensores
  for r in select * from (values
      ('GAS-GEN', 'Contador de gas', 'GAS-CALDERA', 'CONTADOR_ENERGIA'),
      ('AGUA-GEN', 'Contador de agua', 'AGUA-CONT', 'CONTADOR_ENERGIA')) x(codigo, nombre, sensor, tipo)
  loop
    select d.id into v_disp from public.dispositivos d
    join public.recintos rc on rc.id = d.id_recinto join public.plantas p on p.id = rc.id_planta
    where p.id_edificio = v_edif and d.codigo = r.codigo and d.activo;
    if v_disp is null then
      insert into public.dispositivos (id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
      select s.id_recinto, s.id_conexion, td.id, r.codigo, r.nombre
      from public.sensores s, public.tipos_dispositivo td
      where s.codigo = r.sensor and s.activo and s.id_conexion is not null and td.codigo = r.tipo
        and public.obtener_edificio_recinto(s.id_recinto) = v_edif
      returning id into v_disp;
      -- La etiqueta del sensor suelto pasa al dispositivo (mismo punto)
      update public.ubicaciones_3d u set id_dispositivo = v_disp, id_sensor = null
      from public.sensores s
      where u.id_sensor = s.id and s.codigo = r.sensor and s.activo
        and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
      update public.sensores s set id_dispositivo = v_disp, id_conexion = null
      where s.codigo = r.sensor and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
    end if;
  end loop;

  insert into public.sensores (id_dispositivo, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento,
                               unidad, id_tipo_energia)
  select d.id, d.id_recinto, x.cod, x.nom, x.dir::jsonb, f.id, n.id, t.id, x.uni, te.id
  from (values
      ('GAS-GEN', 'PRES-GAS', 'Presión del gas', 'PRESION', 'mbar', 'GAS',
       '{"ruta_valor": "valor", "filtro": {"punto": "PRES-GAS"}}'),
      ('AGUA-GEN', 'CAUDAL-AGUA', 'Caudal de agua', 'CAUDAL', 'm³/h', 'AGUA',
       '{"dev_eui": "24E124136B000002", "campo": "flow"}')) x(disp, cod, nom, fam, uni, ene, dir)
  join public.dispositivos d on d.codigo = x.disp and d.activo
  join public.recintos rc on rc.id = d.id_recinto
  join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.familias_sensor f on f.codigo = x.fam
  join public.naturalezas_sensor n on n.codigo = 'INSTANTANEA'
  join public.tratamientos_sensor t on t.codigo = 'PROMEDIO'
  join public.tipos_energia te on te.codigo = x.ene
  where not exists (select 1 from public.sensores s where s.codigo = x.cod and s.activo
                    and public.obtener_edificio_recinto(s.id_recinto) = v_edif);

  -- 3. Qué mide cada sensor del medidor general
  update public.sensores s set id_parametro_medidor = pm.id
  from (values
      ('CONT-GENERAL', 'ENERGIA_ACTIVA_IMPORTADA'), ('POT-GENERAL', 'POTENCIA_ACTIVA'), ('FP-GENERAL', 'FACTOR_POTENCIA'),
      ('EXP-GENERAL', 'ENERGIA_ACTIVA_EXPORTADA'), ('Q-GENERAL', 'POTENCIA_REACTIVA'), ('S-GENERAL', 'POTENCIA_APARENTE'),
      ('V-L1-GENERAL', 'TENSION_L1'), ('V-L2-GENERAL', 'TENSION_L2'), ('V-L3-GENERAL', 'TENSION_L3'),
      ('I-L1-GENERAL', 'INTENSIDAD_L1'), ('I-L2-GENERAL', 'INTENSIDAD_L2'), ('I-L3-GENERAL', 'INTENSIDAD_L3'),
      ('F-GENERAL', 'FRECUENCIA'),
      ('GAS-CALDERA', 'CONSUMO_GAS'), ('PRES-GAS', 'PRESION_GAS'),
      ('AGUA-CONT', 'CONSUMO_AGUA'), ('CAUDAL-AGUA', 'CAUDAL_AGUA')) x(sensor, parametro)
  join public.parametros_medidor pm on pm.codigo = x.parametro
  where s.codigo = x.sensor and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif
    and s.id_parametro_medidor is distinct from pm.id;

  -- 4. Suministros con su ficha (empresas y números ficticios) y su medidor general
  for r in select * from (values
      ('ELEC-RED', 'Electricidad · red', 'ELECTRICIDAD', 'CONT-GEN', 'Comercializadora Demo Energía, S.A.',
       'Distribuidora Demo Redes, S.A.', 'CT-E-2024-00187', date '2024-01-01'),
      ('GAS-RED', 'Gas natural', 'GAS', 'GAS-GEN', 'Comercializadora Demo Gas, S.L.',
       'Distribuidora Demo Gas, S.A.', 'CT-G-2023-04412', date '2023-10-01'),
      ('AGUA-RED', 'Agua de red', 'AGUA', 'AGUA-GEN', 'Aguas Demo, S.A.',
       'Aguas Demo, S.A.', 'PZ-A-0098231', date '2019-06-15')) x(codigo, nombre, tipo, medidor, com, dis, contrato, alta)
  loop
    insert into public.suministros (id_edificio, codigo, nombre, tipo, fecha_inicio, comercializadora, distribuidora,
                                    numero_contrato, fecha_alta_contrato)
    values (v_edif, r.codigo, r.nombre, r.tipo, r.alta, r.com, r.dis, r.contrato, r.alta)
    on conflict (id_edificio, codigo) do update
      set nombre = excluded.nombre, comercializadora = excluded.comercializadora, distribuidora = excluded.distribuidora,
          numero_contrato = excluded.numero_contrato, fecha_alta_contrato = excluded.fecha_alta_contrato
    returning id into v_sum;

    if r.tipo = 'ELECTRICIDAD' then
      insert into public.suministros_electricidad (id_suministro, cups, contador, tipo_contador, fases, tarifa,
        potencia_p1_kw, potencia_p2_kw, potencia_p3_kw, potencia_p4_kw, potencia_p5_kw, potencia_p6_kw, energia_verde)
      select v_sum, 'ES0000000000000001DM0F', 'Telegestionado 3F', 'TELEMEDIDA', 'TRIFASICA', '3.0TD',
             150, 150, 150, 150, 150, 200, false
      where not exists (select 1 from public.suministros_electricidad where id_suministro = v_sum);
    elsif r.tipo = 'GAS' then
      insert into public.suministros_gas (id_suministro, cups, contador, tarifa, presion_operacion, unidad_presion)
      select v_sum, 'ES0000000000000002DM', 'G25', 'RL.3', 22, 'mbar'
      where not exists (select 1 from public.suministros_gas where id_suministro = v_sum);
    else
      insert into public.suministros_agua (id_suministro, contrato, contador, caudal_contratado, unidad_caudal, tarifa)
      select v_sum, r.contrato, 'DN40', 10, 'm³/h', 'Uso comercial'
      where not exists (select 1 from public.suministros_agua where id_suministro = v_sum);
    end if;

    insert into public.suministros_dispositivos (id_suministro, id_dispositivo, fecha_inicio, medidor_general)
    select v_sum, d.id, r.alta, true
    from public.dispositivos d join public.recintos rc on rc.id = d.id_recinto join public.plantas p on p.id = rc.id_planta
    where p.id_edificio = v_edif and d.codigo = r.medidor and d.activo
      and not exists (select 1 from public.suministros_dispositivos sd where sd.id_suministro = v_sum and sd.activo and sd.medidor_general);
  end loop;

  insert into demo_resultado_sum
  select row_number() over (), f->>'nombre',
         coalesce(f->'medidor'->>'nombre', 'SIN MEDIDOR') || ' · ' || pg_catalog.jsonb_array_length(f->'parametros') || ' parámetros'
           || case when pg_catalog.jsonb_array_length(f->'faltan') > 0 then ' · faltan: ' || (f->'faltan')::text else '' end
  from pg_catalog.jsonb_array_elements(public.suministros_edificio(v_edif)) f;
end;
$$;

select dato as "Suministro", valor as "Medidor general" from demo_resultado_sum order by paso;
