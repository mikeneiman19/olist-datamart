-- 06_vistas_app.sql
-- Vista y funciones para el consumo analítico desde Streamlit (Entregable 3)

-- 1) Vista plana: une la tabla de hechos con sus 6 dimensiones
CREATE OR REPLACE VIEW vw_ventas_app AS
SELECT
    f.sk_venta,
    f.order_id,
    f.order_item_id,
    t.fecha,
    t.anio,
    t.mes,
    t.anio_mes,
    c.estado            AS estado_cliente,
    c.ciudad            AS ciudad_cliente,
    p.categoria_en      AS categoria,
    v.seller_id,
    v.estado            AS estado_vendedor,
    pg.tipo_pago_principal,
    pg.rango_cuotas,
    e.estado_pedido,
    e.puntualidad,
    e.es_entregado,
    e.es_cancelado,
    f.cantidad_items,
    f.price,
    f.freight_value,
    f.valor_total_item,
    f.payment_value,
    f.review_score,
    f.dias_entrega,
    f.dias_retraso,
    f.es_primer_item
FROM fact_ventas f
JOIN dim_tiempo        t  ON t.sk_tiempo   = f.sk_tiempo
JOIN dim_cliente       c  ON c.sk_cliente  = f.sk_cliente
JOIN dim_producto      p  ON p.sk_producto = f.sk_producto
JOIN dim_vendedor      v  ON v.sk_vendedor = f.sk_vendedor
JOIN dim_pago          pg ON pg.sk_pago    = f.sk_pago
JOIN dim_estado_pedido e  ON e.sk_estado   = f.sk_estado;

-- 2) KPI con filtros opcionales (NULL = sin filtro)
CREATE OR REPLACE FUNCTION fn_kpis_filtrado(
    p_fecha_ini DATE DEFAULT NULL,
    p_fecha_fin DATE DEFAULT NULL,
    p_estado    TEXT DEFAULT NULL,
    p_categoria TEXT DEFAULT NULL
)
RETURNS TABLE (
    ingresos_totales         NUMERIC,
    total_pedidos            BIGINT,
    ticket_promedio          NUMERIC,
    pct_entregas_a_tiempo    NUMERIC,
    tiempo_prom_entrega_dias NUMERIC,
    puntaje_prom_resena      NUMERIC,
    pct_cancelacion          NUMERIC
)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT * FROM vw_ventas_app
        WHERE (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
          AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
          AND (p_estado    IS NULL OR estado_cliente = p_estado)
          AND (p_categoria IS NULL OR categoria = p_categoria)
    )
    SELECT
        ROUND(COALESCE(SUM(price) FILTER (WHERE es_cancelado = 0), 0), 2),
        COUNT(DISTINCT order_id) FILTER (WHERE es_cancelado = 0 AND cantidad_items > 0),
        ROUND(
            SUM(price) FILTER (WHERE es_cancelado = 0)
            / NULLIF(COUNT(DISTINCT order_id) FILTER (WHERE es_cancelado = 0 AND cantidad_items > 0), 0), 2),
        ROUND(100.0
            * COUNT(*) FILTER (WHERE es_primer_item = 1 AND es_entregado = 1
                               AND dias_entrega IS NOT NULL AND puntualidad = 'A tiempo')
            / NULLIF(COUNT(*) FILTER (WHERE es_primer_item = 1 AND es_entregado = 1
                               AND dias_entrega IS NOT NULL), 0), 2),
        ROUND(AVG(dias_entrega) FILTER (WHERE es_primer_item = 1 AND es_entregado = 1), 2),
        ROUND(AVG(review_score) FILTER (WHERE es_primer_item = 1), 2),
        ROUND(100.0
            * COUNT(DISTINCT order_id) FILTER (WHERE es_cancelado = 1)
            / NULLIF(COUNT(DISTINCT order_id), 0), 2)
    FROM base;
$$;

-- 3) Ingresos por mes con los mismos filtros (para el gráfico de evolución)
CREATE OR REPLACE FUNCTION fn_ingresos_mensuales(
    p_fecha_ini DATE DEFAULT NULL,
    p_fecha_fin DATE DEFAULT NULL,
    p_estado    TEXT DEFAULT NULL,
    p_categoria TEXT DEFAULT NULL
)
RETURNS TABLE (anio_mes TEXT, ingresos NUMERIC, pedidos BIGINT)
LANGUAGE sql STABLE AS $$
    SELECT anio_mes::TEXT,
           ROUND(SUM(price), 2),
           COUNT(DISTINCT order_id)
    FROM vw_ventas_app
    WHERE es_cancelado = 0 AND cantidad_items > 0
      AND (p_fecha_ini IS NULL OR fecha >= p_fecha_ini)
      AND (p_fecha_fin IS NULL OR fecha <= p_fecha_fin)
      AND (p_estado    IS NULL OR estado_cliente = p_estado)
      AND (p_categoria IS NULL OR categoria = p_categoria)
    GROUP BY anio_mes
    ORDER BY anio_mes;
$$;
