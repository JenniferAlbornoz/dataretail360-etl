/* =====================================================================
   DataRetail 360 · Consultas de evidencia para SSMS (capturas del informe)
   Ejecutar después de correr el notebook completo.
   ===================================================================== */
USE DataRetail360;
GO

-- 1. Arquitectura Medallion: tablas y filas por esquema
SELECT s.name AS esquema, t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.schemas s    ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE s.name IN ('bronze', 'silver', 'gold', 'audit', 'sem')
GROUP BY s.name, t.name
ORDER BY CASE s.name WHEN 'bronze' THEN 1 WHEN 'silver' THEN 2 WHEN 'gold' THEN 3 WHEN 'audit' THEN 4 ELSE 5 END, t.name;

-- 2. Integridad del modelo: claves primarias y foráneas de la capa Gold
SELECT fk.name AS restriccion, OBJECT_NAME(fk.parent_object_id) AS tabla_hechos, OBJECT_NAME(fk.referenced_object_id) AS dimension
FROM sys.foreign_keys fk ORDER BY tabla_hechos, dimension;

-- 3. Log de ejecución del pipeline (incluye el lote de prueba con error)
SELECT lote_id, etapa, objeto, filas_entrada, filas_salida, filas_rechazadas, estado, mensaje, segundos
FROM audit.etl_log ORDER BY inicio;

-- 4a. Correcciones aplicadas en Silver por regla y fuente (cómo se resolvieron los errores entre sistemas)
SELECT regla, dimension_calidad, fuente, SUM(filas) AS filas
FROM audit.correcciones WHERE lote_id IN ('L1-2025H1', 'L2-2025H2')
GROUP BY regla, dimension_calidad, fuente ORDER BY dimension_calidad, regla, fuente;

-- 4b. Homologación de códigos de producto entre sistemas
SELECT sistema, codigo_origen, sku FROM bronze.equivalencias_productos
WHERE sku IN ('NB-001', 'AU-002') AND _run_id = (SELECT MAX(_run_id) FROM bronze.equivalencias_productos) ORDER BY sku, sistema;

-- 4. Cuarentena: registros rechazados por motivo
SELECT entidad, motivo, COUNT(*) AS registros FROM audit.rechazos GROUP BY entidad, motivo ORDER BY entidad, registros DESC;

-- 5. Controles de calidad
SELECT dimension_calidad, control, resultado, ok FROM audit.controles_calidad ORDER BY ok, dimension_calidad;

-- 6. SCD 2: versiones de un producto recategorizado
SELECT producto_key, sku, producto, subcategoria, categoria, costo_unitario, valido_desde, valido_hasta, es_actual
FROM gold.dim_producto WHERE sku IN ('AU-002', 'MI-016', 'TV-003') ORDER BY sku, producto_key;

-- 7. SCD 2 espacial: Chillán antes y después de la Región de Ñuble
SELECT geo_key, codigo_comuna, codigo_cut_vigente, comuna, provincia, region, valido_desde, valido_hasta, es_actual
FROM gold.dim_geografia WHERE comuna = 'Chillán';

-- 8. SCD 1 y SCD 3: sucursales
SELECT sucursal_key, codigo_sucursal, sucursal, tipo_sucursal, comuna, region, zona_comercial_actual, zona_comercial_anterior, fecha_cambio_zona
FROM gold.dim_sucursal ORDER BY sucursal_key;

-- 9. Los 4 data marts de la capa Gold
SELECT TOP 10 * FROM gold.dm_comercial_ventas ORDER BY venta_neta DESC;
SELECT TOP 10 * FROM gold.dm_marketing_campanas WHERE codigo_campana <> 'SIN_CAMPANA' ORDER BY venta_neta DESC;
SELECT TOP 10 * FROM gold.dm_finanzas_margen ORDER BY margen_bruto DESC;
SELECT TOP 10 * FROM gold.dm_operaciones_inventario ORDER BY dias_en_quiebre DESC;

-- 10. Vista integrada (grano producto–sucursal–mes) y prueba de que no duplica cifras
SELECT TOP 15 * FROM gold.vw_tablero_integrado WHERE anio = 2025 AND mes = 12 ORDER BY venta_neta DESC;
SELECT (SELECT SUM(venta_neta) FROM gold.vw_tablero_integrado) AS venta_vista,
       (SELECT SUM(monto_neto) FROM gold.fact_ventas)          AS venta_hecho,
       (SELECT SUM(dias_en_quiebre) FROM gold.vw_tablero_integrado) AS quiebres_vista,
       (SELECT SUM(en_quiebre) FROM gold.fact_inventario)      AS quiebres_hecho;

-- 11. Capa semántica: KPIs, diccionario para IA, mapa de fuentes y diccionario de datos completo
SELECT * FROM sem.kpi;
SELECT * FROM sem.diccionario;
SELECT * FROM sem.mapa_fuentes;
SELECT * FROM sem.diccionario_datos ORDER BY capa, tabla;

-- 12. Linaje: de una línea de venta hasta su archivo y fila de origen
SELECT TOP 1 v.nro_boleta, v.linea_boleta, v.monto_neto, v.archivo_origen, v.fila_origen, b.fecha AS fecha_cruda, b.sku AS sku_crudo,
       b.precio_unitario AS precio_crudo, b._cargado_en
FROM gold.fact_ventas v
JOIN bronze.pos_ventas b ON b._archivo = v.archivo_origen AND b._fila = v.fila_origen
WHERE v.devolucion = 1;

-- Esquema estrella: dim_geografia se conecta directo a fact_inventario (sin pasar por dim_sucursal)
SELECT g.region, COUNT(DISTINCT i.sucursal_key) AS sucursales,
       CAST(AVG(CAST(i.stock_cierre AS FLOAT)) AS DECIMAL(10,2)) AS stock_promedio_diario, SUM(i.en_quiebre) AS dias_producto_en_quiebre
FROM gold.fact_inventario i JOIN gold.dim_geografia g ON g.geo_key = i.geo_key
WHERE i.sucursal_key > 0
GROUP BY g.region ORDER BY g.region;

-- 13. Coherencia de negocio: reposición vs ventas por sucursal (control agregado en la sección 10)
SELECT codigo_sucursal, SUM(unidades_recibidas) AS unidades_recibidas, SUM(unidades_vendidas) AS unidades_vendidas,
       CAST(SUM(unidades_recibidas) * 1.0 / NULLIF(SUM(unidades_vendidas), 0) AS DECIMAL(5,2)) AS recibidas_sobre_vendidas,
       SUM(dias_en_quiebre) AS dias_producto_en_quiebre
FROM gold.dm_operaciones_inventario GROUP BY codigo_sucursal ORDER BY codigo_sucursal;
