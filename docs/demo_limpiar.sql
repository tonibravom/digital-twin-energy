-- =========================================================
-- BORRAR UN EDIFICIO DE DEMOSTRACIÓN (solo desarrollo y demos)
-- Pegar entero en el SQL Editor de Supabase y pulsar Run.
--
-- Borra FÍSICAMENTE el edificio cuyo código se indica abajo y todo lo que
-- cuelga de él: plantas, recintos, cuadros, conexiones (y sus secretos),
-- dispositivos, sensores, lecturas, magnitudes, resúmenes, alarmas,
-- calendario, modelos 3D (solo el registro; los archivos del bucket no) e
-- importaciones. El Partner y el cliente de demostración se conservan.
--
-- ¡ATENCIÓN! Es la única excepción a la regla "nunca borrado físico" y
-- solo se usa con edificios de demostración. Nunca con datos reales.
-- No se puede deshacer.
-- =========================================================
do $$
declare
  v_codigo constant text := 'DEMO-OFICINAS';   -- ← código del edificio de demostración que se borra
  v_edif uuid;
  v_sensores uuid[];
  v_conexiones uuid[];
  v_reglas uuid[];
  v_me uuid[];
  v_disp uuid[];
  v_recintos uuid[];
  v_n bigint;
begin
  if v_codigo not like 'DEMO-%' then
    raise exception 'Por seguridad solo se borran edificios cuyo código empieza por DEMO-';
  end if;
  select id into v_edif from public.edificios where codigo = v_codigo;
  if v_edif is null then
    raise notice 'No existe el edificio %: nada que borrar', v_codigo;
    return;
  end if;

  select coalesce(array_agg(s.id), '{}') into v_sensores from public.sensores s
  where public.obtener_edificio_recinto(s.id_recinto) = v_edif
     or s.id_conexion in (select id from public.conexiones where id_edificio = v_edif);
  select coalesce(array_agg(id), '{}') into v_conexiones from public.conexiones where id_edificio = v_edif;
  select coalesce(array_agg(id), '{}') into v_reglas from public.reglas_alarma where id_edificio = v_edif or id_sensor = any (v_sensores);
  select coalesce(array_agg(id), '{}') into v_me from public.magnitudes_edificio where id_edificio = v_edif;
  select coalesce(array_agg(r.id), '{}') into v_recintos from public.recintos r join public.plantas p on p.id = r.id_planta
  where p.id_edificio = v_edif;
  select coalesce(array_agg(id), '{}') into v_disp from public.dispositivos
  where id_conexion = any (v_conexiones) or id_recinto = any (v_recintos);

  -- Alarmas y comunicación
  delete from public.notificaciones where id_sensor = any (v_sensores)
     or id_evento_alarma in (select id from public.eventos_alarma where id_regla_alarma = any (v_reglas) or id_sensor = any (v_sensores))
     or id_incidencia_comunicacion in (select id from public.incidencias_comunicacion where id_sensor = any (v_sensores));
  delete from public.eventos_alarma where id_regla_alarma = any (v_reglas) or id_sensor = any (v_sensores)
     or id_magnitud_edificio = any (v_me) or id_recinto = any (v_recintos);
  delete from public.reglas_alarma_recintos where id_regla_alarma = any (v_reglas) or id_recinto = any (v_recintos);
  delete from public.reglas_alarma_usuarios where id_regla_alarma = any (v_reglas);
  delete from public.reglas_alarma where id = any (v_reglas);
  delete from public.incidencias_comunicacion where id_sensor = any (v_sensores);
  delete from public.estado_comunicacion where id_sensor = any (v_sensores);
  delete from public.pruebas_lectura where id_sensor = any (v_sensores) or id_conexion = any (v_conexiones);

  -- Datos y cálculo
  delete from public.lecturas where id_sensor = any (v_sensores);
  get diagnostics v_n = row_count;
  raise notice 'Lecturas borradas: %', v_n;
  delete from public.valores_magnitud where id_magnitud_edificio = any (v_me);
  delete from public.magnitudes_fuentes where id_magnitud_edificio = any (v_me) or id_sensor = any (v_sensores);
  delete from public.resumenes_diarios_usos where id_edificio = v_edif;
  delete from public.resumenes_diarios where id_edificio = v_edif;
  delete from public.repartos_uso_edificio where id_edificio = v_edif;
  delete from public.motor_pendiente where id_edificio = v_edif;
  delete from public.recalculos_pendientes where id_edificio = v_edif;

  -- Sensores, dispositivos y conexiones
  delete from public.sensores_recintos_ambito where id_sensor = any (v_sensores) or id_recinto = any (v_recintos);
  delete from public.sensores_ubicaciones where id_sensor = any (v_sensores) or id_recinto = any (v_recintos);
  delete from public.ubicaciones_3d where id_sensor = any (v_sensores)
     or id_modelo_3d in (select id from public.modelos_3d where id_edificio = v_edif)
     or id_dispositivo = any (v_disp);
  update public.sensores set id_sensor_anterior = null where id = any (v_sensores);
  delete from public.sensores where id = any (v_sensores);
  delete from public.dispositivos_recintos_ambito where id_dispositivo = any (v_disp) or id_recinto = any (v_recintos);
  delete from public.dispositivos_ubicaciones where id_dispositivo = any (v_disp) or id_recinto = any (v_recintos);
  delete from public.suministros_dispositivos where id_dispositivo = any (v_disp);
  delete from public.dispositivos where id = any (v_disp);
  delete from public.magnitudes_edificio where id = any (v_me);

  begin
    delete from vault.secrets where id in (select id_secreto from public.conexiones where id = any (v_conexiones) and id_secreto is not null);
  exception when others then
    raise notice 'Los secretos de las conexiones no se han podido borrar del Vault (%): bórrelos a mano si quiere', sqlerrm;
  end;
  update public.conexiones set id_importacion_recuperacion = null where id = any (v_conexiones);
  delete from public.importaciones_lotes where id_importacion in (select id from public.importaciones where id_edificio = v_edif or id_conexion = any (v_conexiones));
  delete from public.importaciones where id_edificio = v_edif or id_conexion = any (v_conexiones);
  delete from public.conexiones where id = any (v_conexiones);
  delete from public.perfiles_importacion where id_edificio = v_edif;

  -- Estructura y configuración del edificio
  update public.cuadros_electricos set id_cuadro_padre = null where id_edificio = v_edif;
  delete from public.cuadros_electricos where id_edificio = v_edif;
  delete from public.modelos_3d where id_edificio = v_edif;
  delete from public.suministros_electricidad where id_suministro in (select id from public.suministros where id_edificio = v_edif);
  delete from public.suministros_gas where id_suministro in (select id from public.suministros where id_edificio = v_edif);
  delete from public.suministros_agua where id_suministro in (select id from public.suministros where id_edificio = v_edif);
  delete from public.suministros_agua_incendios where id_suministro in (select id from public.suministros where id_edificio = v_edif);
  delete from public.suministros_generacion where id_suministro in (select id from public.suministros where id_edificio = v_edif);
  delete from public.suministros where id_edificio = v_edif;
  delete from public.recintos where id_planta in (select id from public.plantas where id_edificio = v_edif);
  delete from public.plantas where id_edificio = v_edif;
  delete from public.calendario_edificio where id_edificio = v_edif;
  delete from public.horarios_tipo_edificio where id_edificio = v_edif;
  delete from public.modalidades_edificio where id_edificio = v_edif;
  delete from public.complementos_edificio where id_edificio = v_edif;
  delete from public.usuarios_edificios where id_edificio = v_edif;
  delete from public.proveedores_edificios where id_edificio = v_edif;
  delete from public.edificios where id = v_edif;

  raise notice 'Edificio % borrado (% sensores, % conexiones)', v_codigo, cardinality(v_sensores), cardinality(v_conexiones);
end;
$$;
