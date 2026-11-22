-- ============================================================================
-- SCRIPT DE CREACIÓN DE ROLES Y USUARIOS (PROPUESTA 6: COMICS ARCHIVE)
-- Descripción: Definición de roles con principio de menor privilegio,
-- creación de usuarios del sistema y asignación de permisos sobre tablas,
-- vistas y funciones almacenadas.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Definición de Roles (agrupan privilegios, sin login directo)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_admin') THEN
        CREATE ROLE rol_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_carga') THEN
        CREATE ROLE rol_carga NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_consulta') THEN
        CREATE ROLE rol_consulta NOLOGIN;
    END IF;
END
$$;

-- ----------------------------------------------------------------------------
-- 2. Creación de Usuarios (con credenciales de autenticación)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_comics') THEN
        CREATE USER admin_comics LOGIN PASSWORD 'CAMBIAR_admin_123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'carga_comics') THEN
        CREATE USER carga_comics LOGIN PASSWORD 'CAMBIAR_carga_123';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consulta_comics') THEN
        CREATE USER consulta_comics LOGIN PASSWORD 'CAMBIAR_consulta_123';
    END IF;
END
$$;

GRANT rol_admin    TO admin_comics;
GRANT rol_carga    TO carga_comics;
GRANT rol_consulta TO consulta_comics;

-- ----------------------------------------------------------------------------
-- 3. Asignación de Permisos sobre Tablas y Vistas
-- ----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

-- Administrador: control total sobre todas las entidades del esquema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rol_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO rol_admin;

-- Operativo de Carga: lectura, alta, modificación y baja sobre tablas operativas,
-- y lectura sobre las vistas del sistema
GRANT SELECT, INSERT, UPDATE, DELETE ON
    Persona, Artista, Autor, Empresa, Comic, Run, Issue,
    Cover, ParticipacionArtista, RunAutor
TO rol_carga;

GRANT SELECT ON
    vw_catalogo_comics_detallado,
    vw_runs_con_conteo_issues,
    vw_resumen_variant_covers,
    vw_participacion_exclusiva_artistas,
    vw_trayectoria_artistas
TO rol_carga;

-- Operativo de Consulta: lectura exclusiva sobre tablas relacionales y VISTAS
GRANT SELECT ON
    Persona, Artista, Autor, Empresa, Comic, Run, Issue,
    Cover, ParticipacionArtista, RunAutor,
    vw_catalogo_comics_detallado,
    vw_runs_con_conteo_issues,
    vw_resumen_variant_covers,
    vw_participacion_exclusiva_artistas,
    vw_trayectoria_artistas
TO rol_consulta;

-- ----------------------------------------------------------------------------
-- 4. Asignación de Permisos sobre Funciones
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION fn_top10_creadores_popularidad() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_artistas_veteranos_sin_variants(DATE) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_top10_creadores_popularidad() TO rol_admin, rol_consulta;
GRANT EXECUTE ON FUNCTION fn_artistas_veteranos_sin_variants(DATE) TO rol_admin, rol_consulta;
