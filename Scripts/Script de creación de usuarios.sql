-- ----------------------------------------------------------------------------
-- 1. Definición de Roles (agrupan privilegios, sin acceso directo de login)
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
-- 2. Creación de Usuarios (con credenciales de inicio de sesión)
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
-- 3. Asignación de Permisos sobre Entidades Relacionales
-- ----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

-- Administrador: acceso y gestión completa sobre el esquema
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO rol_admin;

-- Operativo de carga: alta, lectura, actualización y borrado de datos en tuplas
GRANT SELECT, INSERT, UPDATE, DELETE ON
    Persona, Artista, Autor, Empresa, Comic, Run, Issue,
    Cover, ParticipacionArtista, RunAutor
TO rol_carga;

-- Operativo de consulta: privilegios exclusivos de lectura
GRANT SELECT ON
    Persona, Artista, Autor, Empresa, Comic, Run, Issue,
    Cover, ParticipacionArtista, RunAutor
TO rol_consulta;

-- ----------------------------------------------------------------------------
-- 4. Asignación de Permisos sobre Funciones y Procedimientos
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION fn_top10_creadores_popularidad() FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_artistas_veteranos_sin_variants(DATE) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION fn_top10_creadores_popularidad() TO rol_admin, rol_consulta;
GRANT EXECUTE ON FUNCTION fn_artistas_veteranos_sin_variants(DATE) TO rol_admin, rol_consulta
