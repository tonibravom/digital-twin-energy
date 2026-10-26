# Modelo de seguridad

Resumen para la revisión técnica del comprador.

## Principios

1. **La seguridad está en la base de datos y en la API, no en la interfaz.** Ocultar un botón no concede ni retira permisos.
2. **Aislamiento lógico multi-tenant.** Todos los Partners, clientes y edificios comparten base de datos. Cada consulta se filtra con Row Level Security (RLS) de PostgreSQL según el usuario autenticado.
3. **Cerrado por defecto.** Toda tabla tiene RLS activado desde su creación. Sin una política explícita, nadie accede salvo el backend con `service_role`.

## Capas

| Capa | Mecanismo |
|---|---|
| Autenticación | Supabase Auth con email y contraseña, y el registro público desactivado: solo el administrador o el Partner dan de alta usuarios. Contraseña inicial de cambio obligatorio y **código por email** (doble factor) obligatorio para administradores. Mientras falte un paso, RLS no muestra ningún dato. Las contraseñas nunca se guardan en tablas de la aplicación |
| Rol (qué puede hacer) | `usuarios.id_rol` → `roles_permisos` → `permisos` |
| Alcance (sobre qué) | `usuarios_partners`, `usuarios_clientes` y `usuarios_edificios`, con alcance MASTER o RESTRINGIDO y vigencia por fechas |
| Autorización | Funciones `private.usuario_puede_edificio(edificio, permiso)` y relacionadas, en un esquema no expuesto por la API |
| Filas | Políticas RLS en las 67 tablas |
| Columnas y transiciones | Triggers que protegen cambios sensibles (cliente de un edificio, bajas) y funciones dedicadas para alarmas |
| Integridad entre tenants | Triggers que impiden relacionar elementos de edificios distintos, aunque se use `service_role` |
| Entrada de datos | Un único canal (`procesar_lecturas`), ejecutable solo por la API. Envío externo con token por conexión, guardado como huella SHA-256. Sin secretos en la configuración (Vault) |
| Archivos 3D | Bucket privado. Acceso solo si existe el registro en `modelos_3d` y el usuario tiene permiso sobre el edificio |
| Trazabilidad | Auditoría automática de 40 tablas de configuración. No se puede escribir ni modificar a mano |

## Claves

| Clave | Dónde puede estar |
|---|---|
| `anon` / *publishable* | Frontend (es pública por diseño) |
| `service_role` / *secret* | **Solo** en las variables de entorno del servidor de la API |
| Contraseña de la base de datos | Gestor de contraseñas del administrador |
| Clave del servicio de email (`BREVO_API_KEY` o `SMTP_CONTRASENA`) | **Solo** en las variables de entorno de la API |

## Verificación

- `npx supabase test db` ejecuta 307 pruebas (47 de seguridad, 51 de conectores y configuración, 24 de KPIs, 22 de la página de edificio, 18 de usos y Sankey, 28 de configuración de edificios, 22 de históricos, 28 de importación avanzada, 37 de usuarios y acceso 22 de Sentilo, LoRaWAN y secretos, y 8 de API REST). Entre ellas:
  - anónimo sin acceso;
  - usuario registrado sin ficha que intenta hacerse administrador;
  - Partner A que intenta leer, crear o modificar datos del Partner B;
  - usuario cliente sin permisos de configuración;
  - integridad entre edificios;
  - Storage 3D.
- `select * from public.verificar_rls();` debe devolver 0 filas tras cualquier cambio de esquema.
- Recomendado antes de producción: revisar los *Security Advisors* del dashboard de Supabase.

## Datos personales (RGPD)

En el modelo de venta, el comprador opera la plataforma y suele actuar como **responsable del tratamiento** frente a sus clientes, o como encargado, según sus contratos. La plataforma guarda datos personales mínimos: nombre, apellidos, email y teléfono de usuarios. La auditoría puede contener esos datos cuando se modifican usuarios. Debe confirmarse con asesoría legal.
