-- =====================================================================
-- Script 04: Vistas y funciones para alimentar el dashboard
--
-- REGLAS DE NEGOCIO (las mismas del Entregable 1):
--  * Ingresos (GMV)      = SUM(price) de pedidos NO cancelados
--                          (se excluyen estados 'canceled' y 'unavailable').
--  * Pedidos             = pedidos DISTINTOS (order_id), nunca filas de la fact.
--  * % entregas a tiempo = pedidos 'delivered' con fecha de entrega y a tiempo
--                          / pedidos 'delivered' con fecha de entrega.
--  * Tiempo de entrega   = promedio de dias_entrega en pedidos 'delivered' con fecha.
--  * Puntaje de resena   = promedio por PEDIDO (no por item).
--  * Clientes recurrentes= clientes con >= 2 pedidos no cancelados / clientes con >= 1.
--  * % cancelacion       = pedidos canceled+unavailable / total de pedidos.
--
-- Todas las funciones aceptan filtros opcionales (NULL = sin filtro) y se
-- invocan con notacion nombrada, por ejemplo:
--   SELECT * FROM fn_kpis(p_fecha_ini => '2018-01-01', p_estado_cliente => 'SP');
-- =====================================================================

-- =====================================================================
-- A. VISTAS
-- =====================================================================

-- A1. Hechos "aplanados" con todas las dimensiones (base de las funciones)
CREATE OR REPLACE VIEW vw_ventas_detalle AS
SELECT
    f.sk_venta, f.order_id, f.order_item_id,
    t.fecha, t.anio, t.trimestre, t.mes, t.nombre_mes, t.anio_mes,
    f.sk_cliente, c.customer_unique_id, c.ciudad AS ciudad_cliente, c.estado AS estado_cliente,
    f.sk_vendedor, s.seller_id, s.ciudad AS ciudad_vendedor, s.estado AS estado_vendedor,
    f.sk_producto, p.product_id, p.categoria_en AS categoria,
    e.estado_pedido, e.puntualidad, e.es_entregado, e.es_cancelado,
    pg.tipo_pago_principal, pg.rango_cuotas, pg.es_pago_mixto,
    f.price, f.freight_value, f.valor_total_item, f.cantidad_items,
    f.payment_value, f.payment_installments, f.review_score,
    f.dias_entrega, f.dias_retraso, f.es_primer_item
FROM fact_ventas f
JOIN dim_tiempo        t  ON t.sk_tiempo    = f.sk_tiempo
JOIN dim_cliente       c  ON c.sk_cliente   = f.sk_cliente
JOIN dim_vendedor      s  ON s.sk_vendedor  = f.sk_vendedor
JOIN dim_producto      p  ON p.sk_producto  = f.sk_producto
JOIN dim_estado_pedido e  ON e.sk_estado    = f.sk_estado
JOIN dim_pago          pg ON pg.sk_pago     = f.sk_pago;

-- A2. Una fila por PEDIDO (para KPI de pedidos, entregas, pagos, resenas)
CREATE OR REPLACE VIEW vw_pedidos AS
SELECT
    f.order_id, t.fecha, t.anio, t.mes, t.anio_mes,
    f.sk_cliente, c.customer_unique_id, c.estado AS estado_cliente,
    e.estado_pedido, e.puntualidad, e.es_entregado, e.es_cancelado,
    pg.tipo_pago_principal, pg.rango_cuotas, pg.es_pago_mixto,
    x.n_items, x.ingresos, x.flete, x.pagado,
    f.payment_installments, f.review_score, f.dias_entrega, f.dias_retraso
FROM fact_ventas f
JOIN (SELECT order_id,
             SUM(cantidad_items) AS n_items, SUM(price) AS ingresos,
             SUM(freight_value)  AS flete,   SUM(payment_value) AS pagado
      FROM fact_ventas GROUP BY order_id) x ON x.order_id = f.order_id
JOIN dim_tiempo        t  ON t.sk_tiempo   = f.sk_tiempo
JOIN dim_cliente       c  ON c.sk_cliente  = f.sk_cliente
JOIN dim_estado_pedido e  ON e.sk_estado   = f.sk_estado
JOIN dim_pago          pg ON pg.sk_pago    = f.sk_pago
WHERE f.es_primer_item = 1;

-- A3. P1 - Evolucion mensual de ventas
CREATE OR REPLACE VIEW vw_ventas_mensuales AS
SELECT anio_mes, anio, mes,
       SUM(ingresos)                         AS ingresos,
       COUNT(*)                              AS pedidos,
       ROUND(SUM(ingresos) / COUNT(*), 2)    AS ticket_promedio
FROM vw_pedidos
WHERE es_cancelado = 0
GROUP BY anio_mes, anio, mes;

-- A4. P1 - Ventas por categoria
CREATE OR REPLACE VIEW vw_ventas_categoria AS
SELECT categoria,
       SUM(price)                  AS ingresos,
       COUNT(DISTINCT order_id)    AS pedidos,
       SUM(cantidad_items)         AS items
FROM vw_ventas_detalle
WHERE es_cancelado = 0 AND categoria <> 'sin_item'
GROUP BY categoria;

-- A5. P1/P2 - Ventas y logistica por estado del cliente
CREATE OR REPLACE VIEW vw_logistica_estado AS
SELECT estado_cliente,
       COUNT(*)                                                                  AS pedidos_entregados,
       ROUND(100.0 * SUM(CASE WHEN puntualidad = 'A tiempo' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_a_tiempo,
       ROUND(AVG(dias_entrega), 2)                                               AS dias_prom_entrega,
       ROUND(AVG(dias_retraso), 2)                                               AS dias_retraso_prom
FROM vw_pedidos
WHERE es_entregado = 1 AND puntualidad <> 'Sin entrega'
GROUP BY estado_cliente;

-- A6. P3 - Satisfaccion vs. entrega
CREATE OR REPLACE VIEW vw_resena_vs_entrega AS
SELECT review_score,
       COUNT(*)                                                                   AS pedidos,
       ROUND(AVG(dias_entrega), 2)                                                AS dias_prom_entrega,
       ROUND(100.0 * SUM(CASE WHEN puntualidad = 'Con retraso' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_con_retraso
FROM vw_pedidos
WHERE es_entregado = 1 AND puntualidad <> 'Sin entrega' AND review_score IS NOT NULL
GROUP BY review_score;

-- A7. P4 - Metodos de pago y cuotas
CREATE OR REPLACE VIEW vw_pagos_resumen AS
SELECT tipo_pago_principal AS tipo_pago, rango_cuotas,
       COUNT(*)                         AS pedidos,
       SUM(ingresos)                    AS ingresos,
       ROUND(SUM(ingresos) / COUNT(*), 2) AS ticket_promedio
FROM vw_pedidos
WHERE es_cancelado = 0
GROUP BY tipo_pago_principal, rango_cuotas;

-- A8. P5 - Recompra (una fila por cliente)
CREATE OR REPLACE VIEW vw_recompra_clientes AS
SELECT sk_cliente, customer_unique_id, COUNT(*) AS n_pedidos, SUM(ingresos) AS ingresos
FROM vw_pedidos
WHERE es_cancelado = 0
GROUP BY sk_cliente, customer_unique_id;

-- =====================================================================
-- B. FUNCIONES (cada una = un componente del dashboard)
-- =====================================================================

DROP FUNCTION IF EXISTS fn_kpis(DATE, DATE, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_ventas_por_mes(DATE, DATE, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_ventas_por_categoria(DATE, DATE, VARCHAR, INTEGER);
DROP FUNCTION IF EXISTS fn_logistica_por_estado(DATE, DATE, VARCHAR);
DROP FUNCTION IF EXISTS fn_top_vendedores(INTEGER, DATE, DATE, VARCHAR);
DROP FUNCTION IF EXISTS fn_pagos_por_tipo(DATE, DATE, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_resena_vs_entrega(DATE, DATE, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS fn_detalle_pedidos(DATE, DATE, VARCHAR, VARCHAR, INTEGER, INTEGER);

-- B1. Las 7 tarjetas KPI en una sola consulta (una fila)
CREATE OR REPLACE FUNCTION fn_kpis(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_categoria      VARCHAR DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL)
RETURNS TABLE (
    ingresos_totales         NUMERIC,
    total_pedidos            BIGINT,
    ticket_promedio          NUMERIC,
    pct_entregas_a_tiempo    NUMERIC,
    tiempo_prom_entrega_dias NUMERIC,
    puntaje_prom_resena      NUMERIC,
    pct_clientes_recurrentes NUMERIC,
    pct_cancelacion          NUMERIC)
AS $$
WITH base AS (
    SELECT * FROM vw_ventas_detalle
    WHERE (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_categoria IS NULL OR categoria = p_categoria)
      AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
), ped AS (
    SELECT order_id,
           MAX(sk_cliente)     AS sk_cliente,
           MAX(review_score)   AS review_score,
           MAX(dias_entrega)   AS dias_entrega,
           MAX(es_cancelado)   AS es_cancelado,
           MAX(es_entregado)   AS es_entregado,
           MAX(CASE WHEN puntualidad = 'A tiempo'    THEN 1 ELSE 0 END) AS a_tiempo,
           MAX(CASE WHEN puntualidad = 'Sin entrega' THEN 0 ELSE 1 END) AS con_fecha,
           SUM(price)          AS ingresos
    FROM base GROUP BY order_id
), cli AS (
    SELECT sk_cliente, COUNT(*) AS n_pedidos FROM ped WHERE es_cancelado = 0 GROUP BY sk_cliente
)
SELECT
    CAST(COALESCE((SELECT SUM(ingresos) FROM ped WHERE es_cancelado = 0), 0) AS NUMERIC),
    CAST((SELECT COUNT(*) FROM ped) AS BIGINT),
    CAST(ROUND((SELECT SUM(ingresos) FROM ped WHERE es_cancelado = 0)
               / NULLIF((SELECT COUNT(*) FROM ped WHERE es_cancelado = 0), 0), 2) AS NUMERIC),
    CAST(ROUND(100.0 * (SELECT COUNT(*) FROM ped WHERE es_entregado = 1 AND con_fecha = 1 AND a_tiempo = 1)
               / NULLIF((SELECT COUNT(*) FROM ped WHERE es_entregado = 1 AND con_fecha = 1), 0), 2) AS NUMERIC),
    CAST(ROUND((SELECT AVG(dias_entrega) FROM ped WHERE es_entregado = 1 AND con_fecha = 1), 2) AS NUMERIC),
    CAST(ROUND((SELECT AVG(review_score) FROM ped), 2) AS NUMERIC),
    CAST(ROUND(100.0 * (SELECT COUNT(*) FROM cli WHERE n_pedidos >= 2)
               / NULLIF((SELECT COUNT(*) FROM cli), 0), 2) AS NUMERIC),
    CAST(ROUND(100.0 * (SELECT COUNT(*) FROM ped WHERE es_cancelado = 1)
               / NULLIF((SELECT COUNT(*) FROM ped), 0), 2) AS NUMERIC);
$$ LANGUAGE sql STABLE;

-- B2. Grafico de lineas: ingresos por mes
CREATE OR REPLACE FUNCTION fn_ventas_por_mes(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_categoria      VARCHAR DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL)
RETURNS TABLE (anio_mes TEXT, ingresos NUMERIC, pedidos BIGINT, ticket_promedio NUMERIC)
AS $$
SELECT CAST(anio_mes AS TEXT),
       CAST(SUM(price) AS NUMERIC),
       CAST(COUNT(DISTINCT order_id) AS BIGINT),
       CAST(ROUND(SUM(price) / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS NUMERIC)
FROM vw_ventas_detalle
WHERE es_cancelado = 0
  AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
  AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
  AND (p_categoria IS NULL OR categoria = p_categoria)
  AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
GROUP BY anio_mes
ORDER BY anio_mes;
$$ LANGUAGE sql STABLE;

-- B3. Grafico de barras: ingresos por categoria (top N)
CREATE OR REPLACE FUNCTION fn_ventas_por_categoria(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL,
    p_top            INTEGER DEFAULT 10)
RETURNS TABLE (categoria TEXT, ingresos NUMERIC, pedidos BIGINT, items BIGINT)
AS $$
SELECT CAST(categoria AS TEXT),
       CAST(SUM(price) AS NUMERIC),
       CAST(COUNT(DISTINCT order_id) AS BIGINT),
       CAST(SUM(cantidad_items) AS BIGINT)
FROM vw_ventas_detalle
WHERE es_cancelado = 0 AND categoria <> 'sin_item'
  AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
  AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
  AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
GROUP BY categoria
ORDER BY SUM(price) DESC
LIMIT p_top;
$$ LANGUAGE sql STABLE;

-- B4. Grafico por estado: entregas a tiempo y tiempo de entrega (peores primero)
CREATE OR REPLACE FUNCTION fn_logistica_por_estado(
    p_fecha_ini DATE    DEFAULT NULL,
    p_fecha_fin DATE    DEFAULT NULL,
    p_categoria VARCHAR DEFAULT NULL)
RETURNS TABLE (estado_cliente TEXT, pedidos_entregados BIGINT, pct_a_tiempo NUMERIC,
               dias_prom_entrega NUMERIC, dias_retraso_prom NUMERIC)
AS $$
WITH ped AS (
    SELECT order_id,
           MAX(estado_cliente) AS estado_cliente,
           MAX(dias_entrega)   AS dias_entrega,
           MAX(dias_retraso)   AS dias_retraso,
           MAX(CASE WHEN puntualidad = 'A tiempo' THEN 1 ELSE 0 END) AS a_tiempo
    FROM vw_ventas_detalle
    WHERE es_entregado = 1 AND puntualidad <> 'Sin entrega'
      AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_categoria IS NULL OR categoria = p_categoria)
    GROUP BY order_id
)
SELECT CAST(estado_cliente AS TEXT),
       CAST(COUNT(*) AS BIGINT),
       CAST(ROUND(100.0 * SUM(a_tiempo) / COUNT(*), 2) AS NUMERIC),
       CAST(ROUND(AVG(dias_entrega), 2) AS NUMERIC),
       CAST(ROUND(AVG(dias_retraso), 2) AS NUMERIC)
FROM ped
GROUP BY estado_cliente
ORDER BY 3 ASC;
$$ LANGUAGE sql STABLE;

-- B5. Ranking de vendedores
CREATE OR REPLACE FUNCTION fn_top_vendedores(
    p_top       INTEGER DEFAULT 10,
    p_fecha_ini DATE    DEFAULT NULL,
    p_fecha_fin DATE    DEFAULT NULL,
    p_categoria VARCHAR DEFAULT NULL)
RETURNS TABLE (seller_id TEXT, ciudad TEXT, estado TEXT, ingresos NUMERIC,
               pedidos BIGINT, pct_a_tiempo NUMERIC, puntaje_prom NUMERIC)
AS $$
WITH vo AS (
    SELECT sk_vendedor, MAX(seller_id) AS seller_id, MAX(ciudad_vendedor) AS ciudad,
           MAX(estado_vendedor) AS estado, order_id,
           SUM(price) AS ingresos,
           MAX(review_score) AS review_score,
           MAX(CASE WHEN es_entregado = 1 AND puntualidad <> 'Sin entrega' THEN 1 ELSE 0 END) AS entregado,
           MAX(CASE WHEN es_entregado = 1 AND puntualidad = 'A tiempo'     THEN 1 ELSE 0 END) AS a_tiempo
    FROM vw_ventas_detalle
    WHERE es_cancelado = 0 AND sk_vendedor <> 0
      AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_categoria IS NULL OR categoria = p_categoria)
    GROUP BY sk_vendedor, order_id
)
SELECT CAST(seller_id AS TEXT), CAST(ciudad AS TEXT), CAST(estado AS TEXT),
       CAST(SUM(ingresos) AS NUMERIC),
       CAST(COUNT(*) AS BIGINT),
       CAST(ROUND(100.0 * SUM(a_tiempo) / NULLIF(SUM(entregado), 0), 2) AS NUMERIC),
       CAST(ROUND(AVG(review_score), 2) AS NUMERIC)
FROM vo
GROUP BY sk_vendedor, seller_id, ciudad, estado
ORDER BY SUM(ingresos) DESC
LIMIT p_top;
$$ LANGUAGE sql STABLE;

-- B6. Metodos de pago y cuotas
CREATE OR REPLACE FUNCTION fn_pagos_por_tipo(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_categoria      VARCHAR DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL)
RETURNS TABLE (tipo_pago TEXT, rango_cuotas TEXT, pedidos BIGINT, ingresos NUMERIC, ticket_promedio NUMERIC)
AS $$
WITH ped AS (
    SELECT order_id, MAX(tipo_pago_principal) AS tipo_pago, MAX(rango_cuotas) AS rango_cuotas,
           SUM(price) AS ingresos
    FROM vw_ventas_detalle
    WHERE es_cancelado = 0
      AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_categoria IS NULL OR categoria = p_categoria)
      AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
    GROUP BY order_id
)
SELECT CAST(tipo_pago AS TEXT), CAST(rango_cuotas AS TEXT),
       CAST(COUNT(*) AS BIGINT),
       CAST(SUM(ingresos) AS NUMERIC),
       CAST(ROUND(SUM(ingresos) / COUNT(*), 2) AS NUMERIC)
FROM ped
GROUP BY tipo_pago, rango_cuotas
ORDER BY COUNT(*) DESC;
$$ LANGUAGE sql STABLE;

-- B7. Satisfaccion vs. entrega (puntaje 1-5)
CREATE OR REPLACE FUNCTION fn_resena_vs_entrega(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_categoria      VARCHAR DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL)
RETURNS TABLE (review_score INTEGER, pedidos BIGINT, dias_prom_entrega NUMERIC, pct_con_retraso NUMERIC)
AS $$
WITH ped AS (
    SELECT order_id, MAX(review_score) AS review_score, MAX(dias_entrega) AS dias_entrega,
           MAX(CASE WHEN puntualidad = 'Con retraso' THEN 1 ELSE 0 END) AS con_retraso
    FROM vw_ventas_detalle
    WHERE es_entregado = 1 AND puntualidad <> 'Sin entrega' AND review_score IS NOT NULL
      AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_categoria IS NULL OR categoria = p_categoria)
      AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
    GROUP BY order_id
)
SELECT CAST(review_score AS INTEGER),
       CAST(COUNT(*) AS BIGINT),
       CAST(ROUND(AVG(dias_entrega), 2) AS NUMERIC),
       CAST(ROUND(100.0 * SUM(con_retraso) / COUNT(*), 2) AS NUMERIC)
FROM ped
GROUP BY review_score
ORDER BY review_score;
$$ LANGUAGE sql STABLE;

-- B8. Tabla de detalle (con paginacion)
CREATE OR REPLACE FUNCTION fn_detalle_pedidos(
    p_fecha_ini      DATE    DEFAULT NULL,
    p_fecha_fin      DATE    DEFAULT NULL,
    p_categoria      VARCHAR DEFAULT NULL,
    p_estado_cliente VARCHAR DEFAULT NULL,
    p_limit          INTEGER DEFAULT 100,
    p_offset         INTEGER DEFAULT 0)
RETURNS TABLE (order_id TEXT, fecha DATE, categoria TEXT, estado_cliente TEXT, estado_pedido TEXT,
               price NUMERIC, freight_value NUMERIC, review_score INTEGER,
               dias_entrega INTEGER, dias_retraso INTEGER, tipo_pago TEXT)
AS $$
SELECT CAST(order_id AS TEXT), CAST(fecha AS DATE), CAST(categoria AS TEXT),
       CAST(estado_cliente AS TEXT), CAST(estado_pedido AS TEXT),
       CAST(price AS NUMERIC), CAST(freight_value AS NUMERIC), CAST(review_score AS INTEGER),
       CAST(dias_entrega AS INTEGER), CAST(dias_retraso AS INTEGER), CAST(tipo_pago_principal AS TEXT)
FROM vw_ventas_detalle
WHERE (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
  AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
  AND (p_categoria IS NULL OR categoria = p_categoria)
  AND (p_estado_cliente IS NULL OR estado_cliente = p_estado_cliente)
ORDER BY fecha DESC, order_id, order_item_id
LIMIT p_limit OFFSET p_offset;
$$ LANGUAGE sql STABLE;

-- =====================================================================
-- C. EJEMPLOS DE USO (probar en pgAdmin / DBeaver)
-- =====================================================================
-- SELECT * FROM fn_kpis();                                                    -- todo el periodo
-- SELECT * FROM fn_kpis('2017-01-01', '2018-08-31');                          -- periodo util
-- SELECT * FROM fn_kpis(p_categoria => 'health_beauty', p_estado_cliente => 'SP');
-- SELECT * FROM fn_ventas_por_mes('2017-01-01', '2018-08-31');
-- SELECT * FROM fn_ventas_por_categoria(p_top => 10);
-- SELECT * FROM fn_logistica_por_estado();
-- SELECT * FROM fn_top_vendedores(10);
-- SELECT * FROM fn_pagos_por_tipo();
-- SELECT * FROM fn_resena_vs_entrega();
-- SELECT * FROM fn_detalle_pedidos(p_estado_cliente => 'RJ', p_limit => 50);
-- SELECT * FROM vw_ventas_mensuales ORDER BY anio_mes;
