-- ============================================================================
-- SCRIPT DE PRUEBAS DE FUNCIONES (PROPUESTA 6: COMICS ARCHIVE)
-- Descripción: Casos de prueba y demostraciones de ejecución para las funciones
-- fn_top10_creadores_popularidad y fn_artistas_veteranos_sin_variants.
-- ============================================================================

-- ============================================================================
-- PRUEBA 1: Función fn_top10_creadores_popularidad()
-- ============================================================================

-- 1.A [Ejecución General]
-- Listar los 10 creadores (artistas y autores) con mayor popularidad:
SELECT * FROM fn_top10_creadores_popularidad();

-- 1.B [Validaciones de Negocio]
DO $$
DECLARE
    v_cant              INTEGER;
    v_max               FLOAT;
    v_mcfarlane_artista INTEGER;
    v_mcfarlane_autor   INTEGER;
BEGIN
    -- Validar que devuelva exactamente 10 filas:
    SELECT COUNT(*) INTO v_cant FROM fn_top10_creadores_popularidad();
    RAISE NOTICE '[PRUEBA 1.B - Cantidad de filas] % (esperado: 10, obtenido: %)',
        CASE WHEN v_cant = 10 THEN 'OK' ELSE 'ERROR' END, v_cant;

    -- Validar que la puntuación máxima sea 5.0:
    SELECT MAX(popularidad_maxima) INTO v_max FROM fn_top10_creadores_popularidad();
    RAISE NOTICE '[PRUEBA 1.B - Puntuación máxima] % (esperado: 5.0, obtenido: %)',
        CASE WHEN v_max = 5.0 THEN 'OK' ELSE 'ERROR' END, v_max;

    -- Validar que Todd McFarlane figure como ARTISTA (popularidad alta):
    SELECT COUNT(*) INTO v_mcfarlane_artista 
    FROM fn_top10_creadores_popularidad()
    WHERE nombre_completo = 'Todd McFarlane' AND tipo_creador = 'ARTISTA';
    
    RAISE NOTICE '[PRUEBA 1.B - McFarlane presente como ARTISTA] % (obtenido: %)',
        CASE WHEN v_mcfarlane_artista >= 1 THEN 'OK' ELSE 'ERROR' END, v_mcfarlane_artista;
END $$;


-- ============================================================================
-- PRUEBA 2: Función fn_artistas_veteranos_sin_variants(DATE)
-- ============================================================================

-- 2.A [Ejecución General con Fecha Actual]
-- Listar artistas con más de 10 años de trayectoria que no hayan ilustrado
-- variant covers en los últimos 6 meses:
SELECT * FROM fn_artistas_veteranos_sin_variants(CURRENT_DATE);

-- 2.B [Ejecución con omisión de parámetro (toma DEFAULT CURRENT_DATE)]
SELECT * FROM fn_artistas_veteranos_sin_variants();

-- 2.C [Validación de Exclusión por Variant Cover Reciente]
-- Chip Zdarsky (idArtista = 7) posee la Cover 15 creada hace 2 meses (variant cover).
-- Debe quedar excluido en la consulta a la fecha actual:
DO $$
DECLARE
    v_existe_zdarsky BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 
        FROM fn_artistas_veteranos_sin_variants(CURRENT_DATE)
        WHERE artista_id = 7
    ) INTO v_existe_zdarsky;

    RAISE NOTICE '[PRUEBA 2.C - Exclusión de Artista 7 por Variant reciente] % (esperado: false, obtenido: %)',
        CASE WHEN v_existe_zdarsky = FALSE THEN 'OK' ELSE 'ERROR' END, v_existe_zdarsky;
END $$;

-- 2.D [Prueba con fecha de corte histórica]
-- Al consultar con fecha 2023-06-01:
SELECT * FROM fn_artistas_veteranos_sin_variants('2023-06-01');
