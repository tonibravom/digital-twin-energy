# Plataforma de Gemelo Digital y Gestión Energética de Edificios

Plataforma multi-tenant para monitorizar consumos energéticos e instalaciones de edificios, con gemelo digital 3D (GLB). Un administrador gestiona Partners (integradores, empresas IoT); cada Partner gestiona los edificios de sus clientes.

## Contenido de este repositorio

```
supabase/
  migrations/      20 migraciones SQL: esquema completo, seguridad (RLS), integridad, mantenimiento
  tests/database/  Pruebas automáticas de seguridad y aislamiento (pgTAP)
docs/
  instalacion.md       Instalación paso a paso en la infraestructura del comprador
  dimensionamiento.md  Qué contratar en Supabase según edificios y sensores
  seguridad.md         Modelo de seguridad (para revisión técnica)
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

## Modelo de datos (55 tablas)

| Bloque | Tablas |
|---|---|
| Organización | proveedores (Partners), clientes, edificios y sus relaciones |
| Estructura física | plantas, recintos |
| Conectividad | conexiones, dispositivos, sensores y catálogos |
| Ámbitos | ámbitos funcionales e histórico de ubicaciones |
| Datos | lecturas (particionada por mes), magnitudes y valores calculados (particionada por año) |
| Suministros | electricidad, gas, agua, agua contra incendios, generación |
| 3D | modelos de edificio o recinto, ubicaciones de sensores y dispositivos |
| Alarmas | niveles, reglas, eventos, notificaciones |
| Comunicación | estado e incidencias por sensor |
| Usuarios | roles, permisos y asignaciones de alcance |
| Explotación | calendario, modalidades, complementos, parámetros |
| Auditoría | registro automático de cambios de configuración |
