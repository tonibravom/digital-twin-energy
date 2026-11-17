-- =========================================================
-- PRODUCCIÓN DE LA TORRE DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Requiere la migración 052 y docs/demo_torre_suministros.sql.
-- Pegar entero en el SQL Editor de Supabase y pulsar Run. Se puede ejecutar varias veces.
--
-- Dos instalaciones en la cubierta (datos ficticios), con el mismo criterio que los suministros (D58):
--   · Fotovoltaica «FV cubierta» (40,5 kWp, 90 módulos de 450 W, en dos zonas de la terraza): inversor FV-INV con la energía
--     producida (FV-PROD, ya existente), la potencia, la irradiancia y la temperatura de módulo.
--   · Solar térmica «Solar térmica ACS» (6 captadores planos, 12 m²) de apoyo a la caldera de gas
--     y al ACS: contador de energía térmica ST-CONT con energía, potencia, temperaturas de impulsión,
--     retorno y acumulador, y caudal del primario. Alimenta la magnitud GENERACION_SOLAR_TERMICA y
--     su calor se reparte al uso «Calefacción y ACS», el mismo que el gas de la caldera: en el Sankey
--     se ve qué parte de ese uso viene de las placas.
--   · Las placas no están dibujadas en el modelo de la torre: sus superficies se marcan como
--     polígonos en la cubierta (terraza a 25,25 m, 2,15 m sobre el suelo de la planta Cubierta).
-- =========================================================

drop table if exists pg_temp.demo_resultado_prod;
create temp table demo_resultado_prod (paso int, dato text, valor text);

do $$
declare
  v_edif uuid;
  v_disp uuid;
  v_sum uuid;
  v_me uuid;
  v_cub uuid;
  v_modelo uuid;
  r record;
begin
  select id into v_edif from public.edificios where codigo = 'DEMO-TORRE';
  if v_edif is null then
    raise exception 'No existe el edificio DEMO-TORRE: créelo antes con docs/demo_torre.sql';
  end if;
  select id into v_cub from public.plantas where id_edificio = v_edif and codigo = 'CUB';
  select id into v_modelo from public.modelos_3d where id_edificio = v_edif and tipo_modelo = 'EDIFICIO' and activo;

  -- 1. Medidores de producción: el inversor (con el contador FV-PROD que ya existe) y el contador solar térmico
  for r in select * from (values
      ('FV-INV', 'Inversor fotovoltaico', 'INVERSOR_SOLAR', 'ZONA-TEC', 20.0, 4.0),
      ('ST-CONT', 'Contador solar térmico', 'CONTADOR_ENERGIA', 'SALA-CALDERAS', -20.0, -1.0)) x(codigo, nombre, tipo, recinto, px, pz)
  loop
    select d.id into v_disp from public.dispositivos d
    join public.recintos rc on rc.id = d.id_recinto join public.plantas p on p.id = rc.id_planta
    where p.id_edificio = v_edif and d.codigo = r.codigo and d.activo;
    if v_disp is null then
      insert into public.dispositivos (id_recinto, id_conexion, id_tipo_dispositivo, codigo, nombre)
      select rc.id, s.id_conexion, td.id, r.codigo, r.nombre
      from public.recintos rc
      join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
      cross join public.tipos_dispositivo td
      cross join lateral (select coalesce(s.id_conexion, d.id_conexion) as id_conexion   -- la de la API REST simulada
                          from public.sensores s left join public.dispositivos d on d.id = s.id_dispositivo
                          where s.codigo = 'FV-PROD' and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif) s
      where rc.codigo = r.recinto and td.codigo = r.tipo
      returning id into v_disp;
      if r.codigo = 'FV-INV' then
        -- La etiqueta suelta de FV-PROD pasa al inversor (mismo punto) y el sensor, al dispositivo
        update public.ubicaciones_3d u set id_dispositivo = v_disp, id_sensor = null
        from public.sensores s
        where u.id_sensor = s.id and s.codigo = 'FV-PROD' and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
        update public.sensores s set id_dispositivo = v_disp, id_conexion = null, id_recinto = (select id_recinto from public.dispositivos where id = v_disp)
        where s.codigo = 'FV-PROD' and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
      elsif v_modelo is not null then
        insert into public.ubicaciones_3d (id_modelo_3d, id_dispositivo, x, y, z) values (v_modelo, v_disp, r.px, 0, r.pz);
      end if;
    end if;
  end loop;

  -- 2. Sensores de los medidores (API REST simulada)
  insert into public.sensores (id_dispositivo, id_recinto, codigo, nombre, direccion, id_familia, id_naturaleza, id_tratamiento,
                               unidad, id_tipo_energia)
  select d.id, d.id_recinto, x.cod, x.nom,
         pg_catalog.jsonb_build_object('ruta_valor', 'valor', 'filtro', pg_catalog.jsonb_build_object('punto', x.cod)),
         f.id, n.id, t.id, x.uni, te.id
  from (values
      ('FV-INV', 'FV-POT', 'Potencia fotovoltaica', 'POTENCIA', 'INSTANTANEA', 'kW', 'ELECTRICIDAD'),
      ('FV-INV', 'FV-IRR', 'Irradiancia', 'OTRA', 'INSTANTANEA', 'W/m²', null),
      ('FV-INV', 'FV-TMOD', 'Temperatura de módulo', 'TEMPERATURA', 'INSTANTANEA', '°C', null),
      ('ST-CONT', 'ST-ENERGIA', 'Energía solar térmica', 'ENERGIA', 'ACUMULATIVA', 'kWh', 'TERMICA'),
      ('ST-CONT', 'ST-POT', 'Potencia solar térmica', 'POTENCIA', 'INSTANTANEA', 'kW', 'TERMICA'),
      ('ST-CONT', 'ST-TIMP', 'Temperatura de impulsión solar', 'TEMPERATURA', 'INSTANTANEA', '°C', null),
      ('ST-CONT', 'ST-TRET', 'Temperatura de retorno solar', 'TEMPERATURA', 'INSTANTANEA', '°C', null),
      ('ST-CONT', 'ST-TACU', 'Temperatura del acumulador de ACS', 'TEMPERATURA', 'INSTANTANEA', '°C', null),
      ('ST-CONT', 'ST-CAUDAL', 'Caudal del primario solar', 'CAUDAL', 'INSTANTANEA', 'm³/h', null)) x(disp, cod, nom, fam, nat, uni, ene)
  join public.dispositivos d on d.codigo = x.disp and d.activo
  join public.recintos rc on rc.id = d.id_recinto
  join public.plantas p on p.id = rc.id_planta and p.id_edificio = v_edif
  join public.familias_sensor f on f.codigo = x.fam
  join public.naturalezas_sensor n on n.codigo = x.nat
  join public.tratamientos_sensor t on t.codigo = case x.nat when 'ACUMULATIVA' then 'DELTA' else 'PROMEDIO' end
  left join public.tipos_energia te on te.codigo = x.ene
  where not exists (select 1 from public.sensores s where s.codigo = x.cod and s.activo
                    and public.obtener_edificio_recinto(s.id_recinto) = v_edif);

  -- 3. Qué mide cada sensor
  update public.sensores s set id_parametro_medidor = pm.id
  from (values
      ('FV-PROD', 'FV_ENERGIA'), ('FV-POT', 'FV_POTENCIA'), ('FV-IRR', 'FV_IRRADIANCIA'), ('FV-TMOD', 'FV_TEMPERATURA_MODULO'),
      ('ST-ENERGIA', 'ST_ENERGIA'), ('ST-POT', 'ST_POTENCIA'), ('ST-TIMP', 'ST_TEMPERATURA_IMPULSION'),
      ('ST-TRET', 'ST_TEMPERATURA_RETORNO'), ('ST-TACU', 'ST_TEMPERATURA_ACUMULADOR'), ('ST-CAUDAL', 'ST_CAUDAL')) x(sensor, parametro)
  join public.parametros_medidor pm on pm.codigo = x.parametro
  where s.codigo = x.sensor and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif
    and s.id_parametro_medidor is distinct from pm.id;

  -- 4. Las dos instalaciones, con su ficha y su medidor
  for r in select * from (values
      ('FV-CUB', 'FV cubierta', 'FOTOVOLTAICA', 'FV-INV', date '2023-05-15'),
      ('ST-CUB', 'Solar térmica ACS', 'SOLAR_TERMICA', 'ST-CONT', date '2021-03-01')) x(codigo, nombre, tec, medidor, alta)
  loop
    insert into public.suministros (id_edificio, codigo, nombre, tipo, fecha_inicio, descripcion)
    values (v_edif, r.codigo, r.nombre, 'GENERACION', r.alta,
            case r.tec when 'FOTOVOLTAICA' then 'Autoconsumo con excedentes en la terraza de la cubierta'
                       else 'Apoyo a la caldera de gas para calefacción y agua caliente sanitaria' end)
    on conflict (id_edificio, codigo) do update set nombre = excluded.nombre, descripcion = excluded.descripcion
    returning id into v_sum;

    insert into public.suministros_generacion (id_suministro, tecnologia, potencia_nominal_kw, potencia_pico_kw, superficie_m2,
      fecha_puesta_marcha, energia_verde, numero_modulos, potencia_modulo_w, inversor, potencia_inversor_kw,
      azimut_grados, inclinacion_grados, modalidad_autoconsumo, cau, instalador, mantenedor,
      numero_captadores, tipo_captador, volumen_acumulador_l, caldera_apoyo)
    select v_sum, r.tec,
           case r.tec when 'FOTOVOLTAICA' then 36 else 8.4 end, case r.tec when 'FOTOVOLTAICA' then 40.5 end, null,
           r.alta, true,
           case r.tec when 'FOTOVOLTAICA' then 90 end, case r.tec when 'FOTOVOLTAICA' then 450 end,
           case r.tec when 'FOTOVOLTAICA' then 'Inversor trifásico de 36 kW (demo)' end, case r.tec when 'FOTOVOLTAICA' then 36 end,
           0, case r.tec when 'FOTOVOLTAICA' then 15 else 40 end,
           case r.tec when 'FOTOVOLTAICA' then 'CON_EXCEDENTES_COMPENSACION' end,
           case r.tec when 'FOTOVOLTAICA' then 'ES0000000000000001DM0FA000' end,
           'Instalaciones Demo, S.L.', 'Mantenimientos Demo, S.L.',
           case r.tec when 'SOLAR_TERMICA' then 6 end, case r.tec when 'SOLAR_TERMICA' then 'PLANO' end,
           case r.tec when 'SOLAR_TERMICA' then 1500 end,
           case r.tec when 'SOLAR_TERMICA' then 'Caldera de gas de condensación (sala de calderas)' end
    on conflict (id_suministro) do nothing;

    insert into public.suministros_dispositivos (id_suministro, id_dispositivo, fecha_inicio, medidor_general)
    select v_sum, d.id, r.alta, true
    from public.dispositivos d join public.recintos rc on rc.id = d.id_recinto join public.plantas p on p.id = rc.id_planta
    where p.id_edificio = v_edif and d.codigo = r.medidor and d.activo
      and not exists (select 1 from public.suministros_dispositivos sd where sd.id_suministro = v_sum and sd.activo and sd.medidor_general);

    -- Superficie de las placas, dibujada en la cubierta (el modelo de la torre no las trae)
    insert into public.superficies_produccion (id_suministro, id_planta, nombre, origen, poligono, altura_m, inclinacion_grados, azimut_grados)
    select v_sum, v_cub, x.nombre, 'DIBUJADA', x.poligono::jsonb, 2.15, x.inclinacion, 0
    from (values
        ('FOTOVOLTAICA', 'Terraza oeste', '[[-21, -14], [-14, -14], [-14, -7], [-4, -7], [-4, -4], [-26, -4], [-26, -7], [-21, -7]]', 15),
        ('FOTOVOLTAICA', 'Terraza norte', '[[-5, -14], [13, -14], [13, -12], [-5, -12]]', 15),
        ('SOLAR_TERMICA', 'Captadores', '[[18, -14], [22, -14], [22, -11], [18, -11]]', 40)) x(tec, nombre, poligono, inclinacion)
    where x.tec = r.tec
      and not exists (select 1 from public.superficies_produccion sp where sp.id_suministro = v_sum and sp.activo);
  end loop;

  -- 5. Magnitud de la solar térmica (la fotovoltaica ya la tenía) y uso al que da servicio su calor
  if not exists (select 1 from public.magnitudes_edificio me join public.magnitudes m on m.id = me.id_magnitud
                 where me.id_edificio = v_edif and m.codigo = 'GENERACION_SOLAR_TERMICA' and me.ambito = 'EDIFICIO') then
    insert into public.magnitudes_edificio (id_edificio, id_magnitud, ambito)
    select v_edif, m.id, 'EDIFICIO' from public.magnitudes m where m.codigo = 'GENERACION_SOLAR_TERMICA'
    returning id into v_me;
    insert into public.magnitudes_fuentes (id_magnitud_edificio, id_sensor)
    select v_me, s.id from public.sensores s
    where s.codigo = 'ST-ENERGIA' and s.activo and public.obtener_edificio_recinto(s.id_recinto) = v_edif;
  end if;
  insert into public.repartos_uso_edificio (id_edificio, tipo_energia, id_uso_energia, porcentaje)
  select v_edif, 'CALOR_RENOVABLE', u.id, 100 from public.usos_energia u
  where u.codigo = 'HVAC_CALEFACCION_ACS'
    and not exists (select 1 from public.repartos_uso_edificio ru where ru.id_edificio = v_edif and ru.tipo_energia = 'CALOR_RENOVABLE');

  insert into demo_resultado_prod
  select row_number() over (), f->>'nombre',
         coalesce(f->'medidor'->>'nombre', 'SIN MEDIDOR') || ' · ' || pg_catalog.jsonb_array_length(f->'parametros') || ' parámetros · '
           || pg_catalog.jsonb_array_length(f->'superficies') || ' superficie(s)'
           || case when pg_catalog.jsonb_array_length(f->'faltan') > 0 then ' · faltan: ' || (f->'faltan')::text else '' end
  from pg_catalog.jsonb_array_elements(public.produccion_edificio(v_edif)) f;
end;
$$;

select dato as "Instalación", valor as "Medidor y placas" from demo_resultado_prod order by paso;
