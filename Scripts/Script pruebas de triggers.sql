-- ============================================================================
-- SCRIPT DE PRUEBAS DE TRIGGERS (PROPUESTA 6: COMICS ARCHIVE)
-- Descripción: Casos de prueba exhaustivos para demostrar el correcto 
-- funcionamiento de los triggers en operaciones de INSERT, UPDATE y DELETE,
-- validando tanto casos exitosos como captura controlada de excepciones.
-- ============================================================================

-- ============================================================================
-- PRUEBA 1: Trigger trg_unica_portada_principal (Tabla: Cover)
-- Regla: Un Issue solo puede tener una portada principal (esPrincipal = TRUE).
-- ============================================================================

-- 1.A [Caso de Error Esperado en INSERT]
-- Intentar insertar una segunda portada principal para el Issue 1:
DO $$
BEGIN
    INSERT INTO Cover (idCover, nombre, fechaCreacion, esPrincipal, idIssue, idArtista)
    VALUES (99, 'Spider-Man #1 Duplicate Main Cover', '1963-02-01', TRUE, 1, 3);
    RAISE EXCEPTION 'FALLO: El trigger no impidió la inserción de portada principal duplicada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO 1.A (Error capturado correctamente): %', SQLERRM;
END $$;

-- 1.B [Caso Exitoso en INSERT]
-- Insertar una portada alternativa (variant cover) para el Issue 1:
INSERT INTO Cover (idCover, nombre, fechaCreacion, esPrincipal, idIssue, idArtista)
VALUES (99, 'Spider-Man #1 Variant de Prueba', '1963-02-01', FALSE, 1, 3);

SELECT idCover, nombre, esPrincipal, idIssue 
FROM Cover 
WHERE idCover = 99;

-- 1.C [Caso de Error Esperado en UPDATE]
-- Intentar modificar la portada alternativa a principal (provocando duplicado):
DO $$
BEGIN
    UPDATE Cover 
    SET esPrincipal = TRUE 
    WHERE idCover = 99;
    RAISE EXCEPTION 'FALLO: El trigger no impidió la actualización a portada principal duplicada.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO 1.C (Error capturado correctamente): %', SQLERRM;
END $$;

-- Limpieza de la tupla de prueba:
DELETE FROM Cover WHERE idCover = 99;


-- ============================================================================
-- PRUEBA 2: Trigger trg_validar_fecha_runautor (Tabla: RunAutor)
-- Regla: fechaInicio del autor no puede ser anterior a fechaComienzo del Run.
-- ============================================================================

-- 2.A [Caso de Error Esperado en INSERT]
-- Run 1 comenzó el '1963-03-01'. Intentar asignar autor con fecha '1960-01-01':
DO $$
BEGIN
    INSERT INTO RunAutor (idRunAutor, rol, fechaInicio, idRun, idAutor)
    VALUES (99, 'Guionista Histórico', '1960-01-01', 1, 2);
    RAISE EXCEPTION 'FALLO: El trigger no impidió asignar fecha previa al inicio del Run.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ÉXITO 2.A (Error capturado correctamente): %', SQLERRM;
END $$;

-- 2.B [Caso Exitoso en INSERT]
-- Asignar autor con fecha válida posterior al inicio del Run:
INSERT INTO RunAutor (idRunAutor, rol, fechaInicio, idRun, idAutor)
VALUES (99, 'Guionista Co-creador', '1965-06-01', 1, 2);

SELECT idRunAutor, rol, fechaInicio, idRun, idAutor 
FROM RunAutor 
WHERE idRunAutor = 99;

-- Limpieza de la tupla de prueba:
DELETE FROM RunAutor WHERE idRunAutor = 99;


-- ============================================================================
-- PRUEBA 3: Triggers trg_proteger_metricas_run y trg_proteger_metricas_comic
-- Regla: Impedir adulteración manual de métricas calculadas en Run y Comic.
-- ============================================================================

-- 3.A [Caso de Blindaje en UPDATE manual]
-- Intentar adulterar ventas a 999999 y popularidad a 1.0 en Run 1:
UPDATE Run 
SET ejemplaresVendidos = 999999, popularidad = 1.0 
WHERE idRun = 1;

-- Verificar que el trigger BEFORE interceptó la carga y mantuvo las métricas reales derivadas de sus Issues:
SELECT idRun, ejemplaresVendidos AS ventas_reales, popularidad AS pop_real
FROM Run 
WHERE idRun = 1;

-- Intentar adulterar ventas y popularidad en Comic 1:
UPDATE Comic 
SET ejemplaresVendidos = 888888, popularidad = 2.0 
WHERE idComic = 1;

-- Verificar que el trigger BEFORE restauró el valor real consolidado de sus Runs:
SELECT idComic, ejemplaresVendidos AS ventas_reales, popularidad AS pop_real
FROM Comic 
WHERE idComic = 1;


-- ============================================================================
-- PRUEBA 4: Triggers en Cascada (Issue -> Run -> Comic)
-- Regla: INSERT, UPDATE y DELETE en Issue recalculan Run y propagan a Comic.
-- ============================================================================

-- Estado previo en Run 1 y Comic 1:
SELECT 'ESTADO PREVIO' AS estado, r.idRun, r.ejemplaresVendidos AS run_ventas, r.popularidad AS run_pop,
       c.idComic, c.ejemplaresVendidos AS comic_ventas, c.popularidad AS comic_pop
FROM Run r JOIN Comic c ON r.idComic = c.idComic
WHERE r.idRun = 1;

-- 4.A [Caso Exitoso en INSERT]
-- Insertar Issue 99 en Run 1 con 50.000 ventas y 5.0 popularidad:
INSERT INTO Issue (idIssue, numero, popularidad, ejemplaresVendidos, idRun)
VALUES (99, 999, 5.0, 50000, 1);

SELECT 'TRAS INSERT' AS estado, r.idRun, r.ejemplaresVendidos AS run_ventas, r.popularidad AS run_pop,
       c.idComic, c.ejemplaresVendidos AS comic_ventas, c.popularidad AS comic_pop
FROM Run r JOIN Comic c ON r.idComic = c.idComic
WHERE r.idRun = 1;

-- 4.B [Caso Exitoso en UPDATE]
-- Modificar ventas del Issue 99 a 80.000 y popularidad a 4.0:
UPDATE Issue 
SET ejemplaresVendidos = 80000, popularidad = 4.0 
WHERE idIssue = 99;

SELECT 'TRAS UPDATE' AS estado, r.idRun, r.ejemplaresVendidos AS run_ventas, r.popularidad AS run_pop,
       c.idComic, c.ejemplaresVendidos AS comic_ventas, c.popularidad AS comic_pop
FROM Run r JOIN Comic c ON r.idComic = c.idComic
WHERE r.idRun = 1;

-- 4.C [Caso Exitoso en DELETE]
-- Eliminar el Issue 99:
DELETE FROM Issue WHERE idIssue = 99;

SELECT 'TRAS DELETE (RESTAURADO)' AS estado, r.idRun, r.ejemplaresVendidos AS run_ventas, r.popularidad AS run_pop,
       c.idComic, c.ejemplaresVendidos AS comic_ventas, c.popularidad AS comic_pop
FROM Run r JOIN Comic c ON r.idComic = c.idComic
WHERE r.idRun = 1;
