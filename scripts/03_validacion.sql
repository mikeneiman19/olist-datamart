-- =====================================================================
-- Script 03: Consultas de validacion del Data Mart
-- Cada consulta indica el resultado ESPERADO (calculado de forma
-- independiente con pandas sobre los CSV originales).
-- =====================================================================

-- ---------------------------------------------------------------------
-- V1. CANTIDAD DE REGISTROS CARGADOS
-- ---------------------------------------------------------------------
SELECT 'dim_tiempo'        AS tabla, COUNT(*) AS filas FROM dim_tiempo        UNION ALL   -- esperado 1096
SELECT 'dim_producto'      AS tabla, COUNT(*) AS filas FROM dim_producto      UNION ALL   -- 32952 (32951 + SIN_ITEM)
SELECT 'dim_vendedor'      AS tabla, COUNT(*) AS filas FROM dim_vendedor      UNION ALL   -- 3096  (3095 + SIN_ITEM)
SELECT 'dim_cliente'       AS tabla, COUNT(*) AS filas FROM dim_cliente       UNION ALL   -- 96096
SELECT 'dim_pago'          AS tabla, COUNT(*) AS filas FROM dim_pago          UNION ALL   -- 19
SELECT 'dim_estado_pedido' AS tabla, COUNT(*) AS filas FROM dim_estado_pedido UNION ALL   -- 12
SELECT 'fact_ventas'       AS tabla, COUNT(*) AS filas FROM fact_ventas;                   -- 113425 (112650 items + 775 pedidos sin items)

-- ---------------------------------------------------------------------
-- V2. INTEGRIDAD DE LAS RELACIONES
-- 2a. Hechos huerfanos por cada clave foranea (todos deben dar 0)
-- ---------------------------------------------------------------------
SELECT 'huerfanos tiempo'   AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_tiempo        d ON d.sk_tiempo   = f.sk_tiempo   WHERE d.sk_tiempo   IS NULL UNION ALL
SELECT 'huerfanos producto' AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_producto      d ON d.sk_producto = f.sk_producto WHERE d.sk_producto IS NULL UNION ALL
SELECT 'huerfanos vendedor' AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_vendedor      d ON d.sk_vendedor = f.sk_vendedor WHERE d.sk_vendedor IS NULL UNION ALL
SELECT 'huerfanos cliente'  AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_cliente       d ON d.sk_cliente  = f.sk_cliente  WHERE d.sk_cliente  IS NULL UNION ALL
SELECT 'huerfanos pago'     AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_pago          d ON d.sk_pago     = f.sk_pago     WHERE d.sk_pago     IS NULL UNION ALL
SELECT 'huerfanos estado'   AS control, COUNT(*) AS resultado FROM fact_ventas f LEFT JOIN dim_estado_pedido d ON d.sk_estado   = f.sk_estado   WHERE d.sk_estado   IS NULL;

-- 2b. Grano: no debe haber (order_id, order_item_id) repetidos -> 0
SELECT COUNT(*) AS grano_duplicado
FROM (SELECT order_id, order_item_id FROM fact_ventas GROUP BY order_id, order_item_id HAVING COUNT(*) > 1) x;

-- 2c. Cada pedido debe tener exactamente UNA fila marcada es_primer_item = 1 -> 0
SELECT COUNT(*) AS pedidos_mal_marcados
FROM (SELECT order_id FROM fact_ventas GROUP BY order_id HAVING SUM(es_primer_item) <> 1) x;

-- 2d. Consistencia de medidas: valor_total_item = price + freight_value -> 0
SELECT COUNT(*) AS total_item_inconsistente
FROM fact_ventas
WHERE ABS(valor_total_item - (price + freight_value)) > 0.005;

-- 2e. Dimensiones sin uso (informativo): productos que nunca se vendieron
SELECT COUNT(*) AS productos_sin_ventas
FROM dim_producto d LEFT JOIN fact_ventas f ON f.sk_producto = d.sk_producto
WHERE f.sk_venta IS NULL;                                                                  -- esperado 0 (los 32951 productos se vendieron y SIN_ITEM lo usan los pedidos sin items)

-- ---------------------------------------------------------------------
-- V3. VALORES NULOS RELEVANTES
-- ---------------------------------------------------------------------
SELECT
    SUM(CASE WHEN review_score  IS NULL THEN 1 ELSE 0 END) AS filas_sin_resena,        -- esperado 961 (los 768 pedidos sin resena, repetidos por item)
    SUM(CASE WHEN dias_entrega  IS NULL THEN 1 ELSE 0 END) AS filas_sin_dias_entrega,   -- esperado 3229 (pedidos sin fecha de entrega, repetidos por item)
    SUM(CASE WHEN dias_retraso  IS NULL THEN 1 ELSE 0 END) AS filas_sin_dias_retraso,   -- esperado 3229
    SUM(CASE WHEN payment_value IS NULL THEN 1 ELSE 0 END) AS filas_sin_pago           -- esperado 3 (1 pedido sin pago, con 3 items)
FROM fact_ventas;

-- Nulos por PEDIDO (una fila por pedido)
SELECT
    COUNT(*)                                                    AS pedidos,                -- 99441
    SUM(CASE WHEN review_score IS NULL THEN 1 ELSE 0 END)       AS pedidos_sin_resena,     -- 768
    SUM(CASE WHEN dias_entrega IS NULL THEN 1 ELSE 0 END)       AS pedidos_sin_entrega     -- 2965 (sin fecha de entrega al cliente)
FROM fact_ventas
WHERE es_primer_item = 1;

-- Nulos en dimensiones
SELECT 'clientes sin coordenadas'  AS control, COUNT(*) AS resultado FROM dim_cliente  WHERE latitud IS NULL UNION ALL    -- 268
SELECT 'vendedores sin coordenadas',           COUNT(*)              FROM dim_vendedor WHERE latitud IS NULL AND sk_vendedor <> 0 UNION ALL  -- 7
SELECT 'productos sin_categoria',              COUNT(*)              FROM dim_producto WHERE categoria_en = 'sin_categoria' UNION ALL        -- 610
SELECT 'productos sin peso',                   COUNT(*)              FROM dim_producto WHERE peso_g IS NULL AND sk_producto <> 0;            -- 6 (2 originales + 4 con peso 0)

-- ---------------------------------------------------------------------
-- V4. TOTALES Y MEDIDAS PRINCIPALES
-- ---------------------------------------------------------------------
SELECT
    SUM(price)                     AS ingresos_price,       -- 13591643.70
    SUM(freight_value)             AS fletes,               -- 2251909.54
    SUM(payment_value)             AS pagos,                -- 16008872.12
    SUM(cantidad_items)            AS items_vendidos,       -- 112650
    COUNT(DISTINCT order_id)       AS pedidos_distintos     -- 99441
FROM fact_ventas;

-- Pedidos por estado (debe coincidir con orders.csv: delivered 96478, shipped 1107, canceled 625, ...)
SELECT e.estado_pedido, COUNT(DISTINCT f.order_id) AS pedidos
FROM fact_ventas f JOIN dim_estado_pedido e ON e.sk_estado = f.sk_estado
GROUP BY e.estado_pedido
ORDER BY pedidos DESC;

-- Rango de fechas de compra (4-sep-2016 a 17-oct-2018)
SELECT MIN(t.fecha) AS primera_compra, MAX(t.fecha) AS ultima_compra
FROM fact_ventas f JOIN dim_tiempo t ON t.sk_tiempo = f.sk_tiempo;

-- KPI de control a nivel de pedido
SELECT
    ROUND(AVG(review_score), 4) AS puntaje_prom,            -- 4.0864
    ROUND(AVG(dias_entrega), 2) AS dias_entrega_prom        -- 12.09 (pedidos con fecha de entrega)
FROM fact_ventas
WHERE es_primer_item = 1;
