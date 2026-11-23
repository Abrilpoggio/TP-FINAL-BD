-- ============================================================================
-- SCRIPT DE CREACIÓN DE TRIGGERS (PROPUESTA 6: COMICS ARCHIVE)
-- Descripción: Definición de funciones trigger y triggers para el control de
-- reglas de negocio complejas, integridad temporal y protección y propagación
-- automática de métricas calculadas.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TRIGGER: trg_unica_portada_principal (Tabla: Cover)
-- Regla de Negocio: Cada número (Issue) puede tener múltiples variant covers,
-- pero únicamente UNA portada principal (esPrincipal = TRUE).
-- Tipo: BEFORE INSERT OR UPDATE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_unica_portada_principal_func()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.esPrincipal = TRUE THEN
        IF EXISTS (
            SELECT 1 
            FROM Cover 
            WHERE idIssue = NEW.idIssue 
              AND esPrincipal = TRUE 
              AND idCover <> COALESCE(NEW.idCover, 0)
        ) THEN
            RAISE EXCEPTION 'El Issue % ya posee una portada principal asignada.', NEW.idIssue;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_unica_portada_principal ON Cover;
CREATE TRIGGER trg_unica_portada_principal
BEFORE INSERT OR UPDATE ON Cover
FOR EACH ROW
EXECUTE FUNCTION trg_unica_portada_principal_func();


-- ----------------------------------------------------------------------------
-- 2. TRIGGER: trg_validar_fecha_runautor (Tabla: RunAutor)
-- Regla de Negocio: La fecha de incorporación de un autor a un Run no puede
-- ser anterior a la fecha de inicio del Run mismo.
-- Tipo: BEFORE INSERT OR UPDATE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_validar_fecha_runautor_func()
RETURNS TRIGGER AS $$
DECLARE
    v_fechaComienzoRun DATE;
BEGIN
    SELECT fechaComienzo INTO v_fechaComienzoRun
    FROM Run
    WHERE idRun = NEW.idRun;

    IF NEW.fechaInicio < v_fechaComienzoRun THEN
        RAISE EXCEPTION 'La fecha de inicio del autor (%) no puede ser anterior al inicio del Run (%)', 
            NEW.fechaInicio, v_fechaComienzoRun;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_fecha_runautor ON RunAutor;
CREATE TRIGGER trg_validar_fecha_runautor
BEFORE INSERT OR UPDATE ON RunAutor
FOR EACH ROW
EXECUTE FUNCTION trg_validar_fecha_runautor_func();


-- ----------------------------------------------------------------------------
-- 3. TRIGGER: trg_proteger_metricas_run (Tabla: Run)
-- Regla de Negocio: Blindar popularidad y ejemplaresVendidos ante inserciones
-- o modificaciones manuales en Run, forzando su cálculo real desde Issue.
-- Tipo: BEFORE INSERT OR UPDATE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_proteger_metricas_run_func()
RETURNS TRIGGER AS $$
BEGIN
    NEW.ejemplaresVendidos := COALESCE(
        (SELECT SUM(ejemplaresVendidos) FROM Issue WHERE idRun = NEW.idRun), 
        0
    );
    NEW.popularidad := COALESCE(
        (SELECT ROUND(AVG(popularidad)::numeric, 2) FROM Issue WHERE idRun = NEW.idRun), 
        0.0
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_proteger_metricas_run ON Run;
CREATE TRIGGER trg_proteger_metricas_run
BEFORE INSERT OR UPDATE OF popularidad, ejemplaresVendidos ON Run
FOR EACH ROW
EXECUTE FUNCTION trg_proteger_metricas_run_func();


-- ----------------------------------------------------------------------------
-- 4. TRIGGER: trg_proteger_metricas_comic (Tabla: Comic)
-- Regla de Negocio: Blindar popularidad y ejemplaresVendidos ante inserciones
-- o modificaciones manuales en Comic, forzando su cálculo real desde Run.
-- Tipo: BEFORE INSERT OR UPDATE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_proteger_metricas_comic_func()
RETURNS TRIGGER AS $$
BEGIN
    NEW.ejemplaresVendidos := COALESCE(
        (SELECT SUM(ejemplaresVendidos) FROM Run WHERE idComic = NEW.idComic), 
        0
    );
    NEW.popularidad := COALESCE(
        (SELECT ROUND(AVG(popularidad)::numeric, 2) FROM Run WHERE idComic = NEW.idComic), 
        0.0
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_proteger_metricas_comic ON Comic;
CREATE TRIGGER trg_proteger_metricas_comic
BEFORE INSERT OR UPDATE OF popularidad, ejemplaresVendidos ON Comic
FOR EACH ROW
EXECUTE FUNCTION trg_proteger_metricas_comic_func();


-- ----------------------------------------------------------------------------
-- 5. TRIGGER: trg_actualizar_ventas_run (Tabla: Issue)
-- Regla de Negocio: Al insertar, modificar o eliminar un Issue, recalcular y
-- propagar automáticamente la suma de ventas y promedio de popularidad a su Run.
-- Tipo: AFTER INSERT OR UPDATE OR DELETE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_actualizar_ventas_run_func()
RETURNS TRIGGER AS $$
DECLARE
    v_idRun INTEGER;
    v_totalVentas INTEGER;
    v_promedioPopularidad FLOAT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_idRun := OLD.idRun;
    ELSE
        v_idRun := NEW.idRun;
    END IF;

    SELECT 
        COALESCE(SUM(ejemplaresVendidos), 0),
        COALESCE(ROUND(AVG(popularidad)::numeric, 2), 0.0)
    INTO v_totalVentas, v_promedioPopularidad
    FROM Issue
    WHERE idRun = v_idRun;

    UPDATE Run
    SET ejemplaresVendidos = v_totalVentas,
        popularidad = v_promedioPopularidad
    WHERE idRun = v_idRun;

    -- Si se actualizó el idRun de un Issue, actualizar también el Run anterior
    IF TG_OP = 'UPDATE' AND OLD.idRun <> NEW.idRun THEN
        SELECT 
            COALESCE(SUM(ejemplaresVendidos), 0),
            COALESCE(ROUND(AVG(popularidad)::numeric, 2), 0.0)
        INTO v_totalVentas, v_promedioPopularidad
        FROM Issue
        WHERE idRun = OLD.idRun;

        UPDATE Run
        SET ejemplaresVendidos = v_totalVentas,
            popularidad = v_promedioPopularidad
        WHERE idRun = OLD.idRun;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actualizar_ventas_run ON Issue;
CREATE TRIGGER trg_actualizar_ventas_run
AFTER INSERT OR UPDATE OR DELETE ON Issue
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_ventas_run_func();


-- ----------------------------------------------------------------------------
-- 6. TRIGGER: trg_actualizar_metricas_comic (Tabla: Run)
-- Regla de Negocio: Al actualizarse un Run (o insertarse/eliminarse), propagar
-- automáticamente las ventas acumuladas y el promedio de popularidad a Comic.
-- Tipo: AFTER INSERT OR UPDATE OR DELETE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_actualizar_metricas_comic_func()
RETURNS TRIGGER AS $$
DECLARE
    v_idComic INTEGER;
    v_totalVentas INTEGER;
    v_promedioPopularidad FLOAT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_idComic := OLD.idComic;
    ELSE
        v_idComic := NEW.idComic;
    END IF;

    SELECT 
        COALESCE(SUM(ejemplaresVendidos), 0),
        COALESCE(ROUND(AVG(popularidad)::numeric, 2), 0.0)
    INTO v_totalVentas, v_promedioPopularidad
    FROM Run
    WHERE idComic = v_idComic;

    UPDATE Comic
    SET ejemplaresVendidos = v_totalVentas,
        popularidad = v_promedioPopularidad
    WHERE idComic = v_idComic;

    IF TG_OP = 'UPDATE' AND OLD.idComic <> NEW.idComic THEN
        SELECT 
            COALESCE(SUM(ejemplaresVendidos), 0),
            COALESCE(ROUND(AVG(popularidad)::numeric, 2), 0.0)
        INTO v_totalVentas, v_promedioPopularidad
        FROM Run
        WHERE idComic = OLD.idComic;

        UPDATE Comic
        SET ejemplaresVendidos = v_totalVentas,
            popularidad = v_promedioPopularidad
        WHERE idComic = OLD.idComic;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actualizar_metricas_comic ON Run;
CREATE TRIGGER trg_actualizar_metricas_comic
AFTER INSERT OR UPDATE OR DELETE ON Run
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_metricas_comic_func();
