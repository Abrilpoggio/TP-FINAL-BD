-- Implementación de la función SQL para obtener el top 10 de creadores según su puntuación máxima
CREATE OR REPLACE FUNCTION fn_top10_creadores_popularidad()
RETURNS TABLE (
    tipo_creador        TEXT,
    id_persona          INTEGER,
    nombre_completo     TEXT,
    popularidad_maxima  FLOAT
)
LANGUAGE sql
STABLE
AS $$
    WITH relaciones AS (
        -- Artistas participantes en la ilustración de páginas interiores
        SELECT ar.idPersona, 'ARTISTA'::TEXT AS tipo, c.popularidad
        FROM ParticipacionArtista pa
        JOIN Artista ar ON ar.idArtista = pa.idArtista
        JOIN Issue i    ON i.idIssue    = pa.idIssue
        JOIN Run r      ON r.idRun      = i.idRun
        JOIN Comic c    ON c.idComic    = r.idComic

        UNION ALL

        -- Ilustradores a cargo de portadas
        SELECT ar.idPersona, 'ARTISTA', c.popularidad
        FROM Cover cv
        JOIN Artista ar ON ar.idArtista = cv.idArtista
        JOIN Issue i    ON i.idIssue    = cv.idIssue
        JOIN Run r      ON r.idRun      = i.idRun
        JOIN Comic c    ON c.idComic    = r.idComic

        UNION ALL

        -- Escritores principales asignados al cómic global
        SELECT au.idPersona, 'AUTOR', c.popularidad
        FROM Comic c
        JOIN Autor au ON au.idAutor = c.idAutor

        UNION ALL

        -- Guionistas participantes dentro de arcos específicos
        SELECT au.idPersona, 'AUTOR', c.popularidad
        FROM RunAutor ra
        JOIN Autor au ON au.idAutor = ra.idAutor
        JOIN Run r    ON r.idRun    = ra.idRun
        JOIN Comic c  ON c.idComic  = r.idComic
    )
    SELECT rel.tipo,
           p.idPersona,
           p.nombre || ' ' || p.apellidos,
           MAX(rel.popularidad)
    FROM relaciones rel
    JOIN Persona p ON p.idPersona = rel.idPersona
    GROUP BY rel.tipo, p.idPersona, p.nombre, p.apellidos
    ORDER BY MAX(rel.popularidad) DESC, p.apellidos, p.nombre
    LIMIT 10;
$$;

-- ----------------------------------------------------------------------------
-- Consulta de artistas con más de 10 años de trayectoria que no hayan ilustrado
-- portadas variantes en los últimos 6 meses (esPrincipal = FALSE).
-- Por defecto toma CURRENT_DATE como fecha base de evaluación.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_artistas_veteranos_sin_variants(
    p_fecha_consulta DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    artista_id      INTEGER,
    nombre_artista  TEXT,
    alias_artista   TEXT,
    fecha_comienzo  DATE,
    anios_en_medio  INTEGER
)
LANGUAGE sql
STABLE
AS $$
    SELECT ar.idArtista,
           p.nombre || ' ' || p.apellidos,
           p.alias,
           p.fechaComienzo,
           DATE_PART('year', AGE(p_fecha_consulta, p.fechaComienzo))::INTEGER
    FROM Artista ar
    JOIN Persona p ON p.idPersona = ar.idPersona
    WHERE p.fechaComienzo < (p_fecha_consulta - INTERVAL '10 years')
      AND NOT EXISTS (
            SELECT 1
            FROM Cover cv
            WHERE cv.idArtista = ar.idArtista
              AND cv.esPrincipal = FALSE
              AND cv.fechaCreacion >  (p_fecha_consulta - INTERVAL '6 months')
              AND cv.fechaCreacion <= p_fecha_consulta
      )
    ORDER BY p.fechaComienzo, p.apellidos, p.nombre;
$$;



-- Limpieza final para restaurar el estado inicial del esquema tras el conjunto de pruebas
DELETE FROM Cover WHERE idCover >= 100;
DELETE FROM ParticipacionArtista WHERE idParticipacionArtista >= 100;
DELETE FROM RunAutor WHERE idRunAutor >= 100;
DELETE FROM Issue WHERE idIssue >= 100;

--===================================================================
-- PRUEBA 5: Función fn_top10_creadores_popularidad()
-- ===================================================================

-- 5.A [Caso Exitoso] Listar los 10 principales artistas y autores con mayor puntaje de popularidad:
SELECT * FROM fn_top10_creadores_popularidad();

DO $$
DECLARE
    v_cant              INTEGER;
    v_ordenado          BOOLEAN;
    v_max               INTEGER;
    v_fila9             TEXT;
    v_fila10            TEXT;
    v_mcfarlane_artista INTEGER;
    v_mcfarlane_autor   INTEGER;
    v_jimlee            INTEGER;
    v_excluidos         INTEGER;
BEGIN
    -- 5.B [Cantidad] Verificar que la función retorne únicamente 10 registros:
    SELECT COUNT(*) INTO v_cant FROM fn_top10_creadores_popularidad();
    RAISE NOTICE '[PRUEBA 5 - Cantidad de filas] % -> % (esperado: 10)',
        CASE WHEN v_cant = 10 THEN 'OK' ELSE 'ERROR' END, v_cant;

    -- 5.C [Orden] Validar la ordenación descendente por puntuación:
    SELECT COALESCE(bool_and(prev IS NULL OR popularidad_maxima <= prev), FALSE) INTO v_ordenado
    FROM (
        SELECT popularidad_maxima,
               LAG(popularidad_maxima) OVER (ORDER BY n) AS prev
        FROM fn_top10_creadores_popularidad()
             WITH ORDINALITY AS t(tipo_creador, id_persona, nombre_completo, popularidad_maxima, n)
    ) x;
    RAISE NOTICE '[PRUEBA 5 - Orden descendente] % -> % (esperado: true)',
        CASE WHEN v_ordenado THEN 'OK' ELSE 'ERROR' END, v_ordenado;

    -- 5.D [Popularidad máxima] Comprobar las 8 tuplas con puntaje de popularidad igual a 5.0:
    SELECT COUNT(*) INTO v_max FROM fn_top10_creadores_popularidad() WHERE popularidad_maxima = 5.0;
    RAISE NOTICE '[PRUEBA 5 - Filas con popularidad 5.0] % -> % (esperado: 8)',
        CASE WHEN v_max = 8 THEN 'OK' ELSE 'ERROR' END, v_max;

    -- 5.E [Desempate] Verificar el desempate alfabético por apellido para el noveno y décimo puesto (popularidad 4.8):
    SELECT tipo_creador || ' ' || nombre_completo INTO v_fila9
    FROM fn_top10_creadores_popularidad()
         WITH ORDINALITY AS t(tipo_creador, id_persona, nombre_completo, popularidad_maxima, n)
    WHERE n = 9;
    SELECT tipo_creador || ' ' || nombre_completo INTO v_fila10
    FROM fn_top10_creadores_popularidad()
         WITH ORDINALITY AS t(tipo_creador, id_persona, nombre_completo, popularidad_maxima, n)
    WHERE n = 10;
    RAISE NOTICE '[PRUEBA 5 - Puesto 9] % -> % (esperado: AUTOR Brian Michael Bendis)',
        CASE WHEN v_fila9 = 'AUTOR Brian Michael Bendis' THEN 'OK' ELSE 'ERROR' END, v_fila9;
    RAISE NOTICE '[PRUEBA 5 - Puesto 10] % -> % (esperado: ARTISTA Steve Ditko)',
        CASE WHEN v_fila10 = 'ARTISTA Steve Ditko' THEN 'OK' ELSE 'ERROR' END, v_fila10;

    -- 5.F [Un creador, un solo rol] Validar que Todd McFarlane figure únicamente como ARTISTA (5.0) y no como AUTOR (4.3):
    SELECT COUNT(*) INTO v_mcfarlane_artista FROM fn_top10_creadores_popularidad()
    WHERE nombre_completo = 'Todd McFarlane' AND tipo_creador = 'ARTISTA' AND popularidad_maxima = 5.0;
    SELECT COUNT(*) INTO v_mcfarlane_autor FROM fn_top10_creadores_popularidad()
    WHERE nombre_completo = 'Todd McFarlane' AND tipo_creador = 'AUTOR';
    RAISE NOTICE '[PRUEBA 5 - McFarlane como ARTISTA] % -> % (esperado: 1)',
        CASE WHEN v_mcfarlane_artista = 1 THEN 'OK' ELSE 'ERROR' END, v_mcfarlane_artista;
    RAISE NOTICE '[PRUEBA 5 - McFarlane como AUTOR] % -> % (esperado: 0)',
        CASE WHEN v_mcfarlane_autor = 0 THEN 'OK' ELSE 'ERROR' END, v_mcfarlane_autor;

    -- 5.G [Un creador, dos roles] Confirmar la doble aparición de Jim Lee al alcanzar 5.0 como artista y autor:
    SELECT COUNT(*) INTO v_jimlee FROM fn_top10_creadores_popularidad()
    WHERE nombre_completo = 'Jim Lee' AND popularidad_maxima = 5.0;
    RAISE NOTICE '[PRUEBA 5 - Jim Lee (ARTISTA y AUTOR)] % -> % (esperado: 2)',
        CASE WHEN v_jimlee = 2 THEN 'OK' ELSE 'ERROR' END, v_jimlee;

    -- 5.H [Fuera del top 10] Constatar la exclusión por criterio alfabético de Fiona Staples y Chip Zdarsky:
    SELECT COUNT(*) INTO v_excluidos FROM fn_top10_creadores_popularidad()
    WHERE nombre_completo IN ('Fiona Staples', 'Chip Zdarsky');
    RAISE NOTICE '[PRUEBA 5 - Creadores fuera del top 10] % -> % (esperado: 0)',
        CASE WHEN v_excluidos = 0 THEN 'OK' ELSE 'ERROR' END, v_excluidos;
END $$;

--===================================================================
--PRUEBA 6: Función fn_artistas_veteranos_sin_variants(fecha)
--===================================================================
-- Portadas alternativas registradas (esPrincipal = FALSE):
--   Cover 11 (Artista 4) 2023-05-10 | Cover 12 (Artista 4) 2023-08-15 | Cover 13 (Artista 4) 2023-10-01
--   Cover 14 (Artista 1) 2023-11-20 | Cover 15 (Artista 7) 2 meses previos a la fecha actual

-- 6.A [Caso Exitoso] Listar artistas con trayectoria mayor a 10 años sin variant covers en los 6 meses anteriores al 2023-06-01:
SELECT * FROM fn_artistas_veteranos_sin_variants('2023-06-01');

DO $$
DECLARE
    v_ids   INTEGER[];
    v_anios INTEGER;
    v_f15   DATE;
BEGIN
    -- 6.B [Variant en los 6 meses] Excluir al Artista 4 por elaborar la portada 11 el 2023-05-10:
    SELECT array_agg(artista_id ORDER BY artista_id) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2023-06-01');
    RAISE NOTICE '[PRUEBA 6 - Consulta al 2023-06-01] % -> % (esperado: {1,2,3,5,6,7,8,9,10})',
        CASE WHEN v_ids = ARRAY[1,2,3,5,6,7,8,9,10] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.C [Límite superior] Considerar el variant 14 del Artista 1 por ser creado el mismo día de la consulta:
    SELECT array_agg(artista_id ORDER BY artista_id) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2023-11-20');
    RAISE NOTICE '[PRUEBA 6 - Consulta al 2023-11-20] % -> % (esperado: {2,3,5,6,7,8,9,10})',
        CASE WHEN v_ids = ARRAY[2,3,5,6,7,8,9,10] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.D [Límite inferior] Verificar que el variant 14 no aplique al situarse a exactamente 6 meses:
    SELECT array_agg(artista_id ORDER BY artista_id) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2024-05-20');
    RAISE NOTICE '[PRUEBA 6 - Consulta al 2024-05-20] % -> % (esperado: {1,2,3,4,5,6,7,8,9,10})',
        CASE WHEN v_ids = ARRAY[1,2,3,4,5,6,7,8,9,10] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.E [Día anterior al límite] Excluir al Artista 1 al ingresar el variant 14 dentro de la ventana de 6 meses:
    SELECT array_agg(artista_id ORDER BY artista_id) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2024-05-19');
    RAISE NOTICE '[PRUEBA 6 - Consulta al 2024-05-19] % -> % (esperado: {2,3,4,5,6,7,8,9,10})',
        CASE WHEN v_ids = ARRAY[2,3,4,5,6,7,8,9,10] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.F [10 años exactos] Comprobar la antigüedad de la Artista 6 (inicio 2006-10-15) al no cumplir más de 10 años exactos:
    SELECT array_agg(artista_id ORDER BY artista_id) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2016-10-15');
    RAISE NOTICE '[PRUEBA 6 - Consulta al 2016-10-15] % -> % (esperado: {1,2,3,4,5,7,8,9,10})',
        CASE WHEN v_ids = ARRAY[1,2,3,4,5,7,8,9,10] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.G [10 años y un día] Incluir a la Artista 6 al día siguiente por superar los 10 años de trayectoria:
    SELECT anios_en_medio INTO v_anios
    FROM fn_artistas_veteranos_sin_variants('2016-10-16') WHERE artista_id = 6;
    RAISE NOTICE '[PRUEBA 6 - Artista 6 al 2016-10-16] % -> % años (esperado: 10)',
        CASE WHEN v_anios = 10 THEN 'OK' ELSE 'ERROR' END, v_anios;

    -- 6.H [Años en el medio] Validar la cantidad de años calculados para Kirby (1936-01-15) y Staples (2006-10-15) al 2024-05-20:
    SELECT anios_en_medio INTO v_anios
    FROM fn_artistas_veteranos_sin_variants('2024-05-20') WHERE artista_id = 1;
    RAISE NOTICE '[PRUEBA 6 - Artista 1 (Kirby)] % -> % años (esperado: 88)',
        CASE WHEN v_anios = 88 THEN 'OK' ELSE 'ERROR' END, v_anios;
    SELECT anios_en_medio INTO v_anios
    FROM fn_artistas_veteranos_sin_variants('2024-05-20') WHERE artista_id = 6;
    RAISE NOTICE '[PRUEBA 6 - Artista 6 (Staples)] % -> % años (esperado: 17)',
        CASE WHEN v_anios = 17 THEN 'OK' ELSE 'ERROR' END, v_anios;

    -- 6.I [Orden] Confirmar la ordenación por fecha de inicio en el medio (cronológica ascendente):
    SELECT array_agg(artista_id ORDER BY n) INTO v_ids
    FROM fn_artistas_veteranos_sin_variants('2024-05-20')
         WITH ORDINALITY AS t(artista_id, nombre_artista, alias_artista, fecha_comienzo, anios_en_medio, n);
    RAISE NOTICE '[PRUEBA 6 - Orden por fecha de comienzo] % -> % (esperado: {1,8,2,9,3,4,5,10,7,6})',
        CASE WHEN v_ids = ARRAY[1,8,2,9,3,4,5,10,7,6] THEN 'OK' ELSE 'ERROR' END, v_ids;

    -- 6.J [Variant reciente] Evaluar la presencia del Artista 7 según la fecha del variant 15:
    SELECT fechaCreacion INTO v_f15 FROM Cover WHERE idCover = 15;
    RAISE NOTICE '[PRUEBA 6 - Artista 7 con variant reciente] % (esperado: no aparece)',
        CASE WHEN NOT EXISTS (
            SELECT 1 FROM fn_artistas_veteranos_sin_variants((v_f15 + INTERVAL '1 month')::DATE)
            WHERE artista_id = 7
        ) THEN 'OK' ELSE 'ERROR' END;

    RAISE NOTICE '[PRUEBA 6 - Artista 7 sin variant reciente] % (esperado: aparece)',
        CASE WHEN EXISTS (
            SELECT 1 FROM fn_artistas_veteranos_sin_variants((v_f15 + INTERVAL '7 months')::DATE)
            WHERE artista_id = 7
        ) THEN 'OK' ELSE 'ERROR' END;

    -- 6.K [Parámetro por defecto] Verificar que el valor omitido coincida con CURRENT_DATE:
    RAISE NOTICE '[PRUEBA 6 - Parámetro por defecto (CURRENT_DATE)] % (esperado: mismo resultado)',
        CASE WHEN NOT EXISTS (
            (SELECT * FROM fn_artistas_veteranos_sin_variants() EXCEPT SELECT * FROM fn_artistas_veteranos_sin_variants(CURRENT_DATE))
            UNION ALL
            (SELECT * FROM fn_artistas_veteranos_sin_variants(CURRENT_DATE) EXCEPT SELECT * FROM fn_artistas_veteranos_sin_variants())
        ) THEN 'OK' ELSE 'ERROR' END;
END $$;
