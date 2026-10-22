# Plataforma de Gemelo Digital y Gestión Energética de Edificios

Plataforma multi-tenant para monitorizar consumos energéticos e instalaciones de edificios, con gemelo digital 3D (GLB). Un administrador gestiona Partners (integradores, empresas IoT); cada Partner gestiona los edificios de sus clientes.

## Contenido de este repositorio

```
supabase/
  migrations/      26 migraciones SQL: esquema completo, seguridad (RLS), integridad, mantenimiento, conectores, KPIs, página de edificio, usos y Sankey, configuración de edificios, históricos
  tests/database/  Pruebas automáticas de seguridad y aislamiento (pgTAP)
docs/
  instalacion.md       Instalación paso a paso en la infraestructura del comprador
  dimensionamiento.md  Qué contratar en Supabase según edificios y sensores
  seguridad.md         Modelo de seguridad (para revisión técnica)
  conectores.md        Cómo integrar cualquier sensor o dispositivo
  configuracion-partner.md  Asistente de alta de dispositivos, prueba de lectura y cierre
  pantallas.md         Navegación, pantallas de ámbito, KPIs, listas y permisos
  pagina-edificio.md   Página de edificio: HOY, 3D, Históricos, Alarmas, Ficha, Análisis, Configuración
  configuracion-edificio.md  Alta guiada y edición de edificios, sustituciones, GLB, Excel, calendario
  edificios-existentes-historicos.md  Equipos existentes, carga de históricos y resúmenes antiguos
  pruebas_*_sql_editor.sql  Pruebas para ejecutar desde el SQL Editor de Supabase
  decisiones.md        Decisiones y cambios respecto al documento maestro
CLAUDE.md          Instrucciones para desarrollar con Claude Code
.github/workflows/ Pruebas automáticas en cada cambio
```

## Inicio rápido (entorno local)

Requisitos: Node.js LTS y Docker Desktop.

```powershell
npx supabase start
npx supabase db reset
npx supabase test db
```

Para producción, siga `docs/instalacion.md`.

## Modelo de datos (67 tablas)

| Bloque | Tablas |
|---|---|
| Organización | proveedores (Partners), clientes, edificios y sus relaciones |
| Estructura física | plantas, recintos |
| Conectividad | conexiones, dispositivos, sensores, catálogos y plantillas de dispositivo |
| Ámbitos | ámbitos funcionales e histórico de ubicaciones |
| Datos | lecturas (particionada por mes), magnitudes, valores calculados (particionada por año) y resúmenes diarios para KPIs |
| Suministros | electricidad, gas, agua, agua contra incendios, generación |
| 3D | modelos de edificio o recinto, ubicaciones de sensores y dispositivos |
| Alarmas | niveles, reglas, eventos, notificaciones |
| Comunicación | estado e incidencias por sensor |
| Usuarios | roles, permisos y asignaciones de alcance |
| Explotación | calendario (horario tipo y festivos), modalidades, complementos, parámetros, usos finales de la energía y su reparto |
| Importaciones | cargas por lotes reanudables y recálculos pendientes |
| Auditoría | registro automático de cambios de configuración |
