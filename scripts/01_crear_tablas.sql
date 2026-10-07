-- =====================================================================
-- ENTREGABLE 2 - Data Mart Olist (PostgreSQL)
-- Script 01: Creacion del esquema estrella
--
-- GRANULARIDAD de FACT_VENTAS:
--   Una fila representa un ITEM (producto) vendido dentro de un pedido,
--   por un vendedor, a un cliente, en la fecha de compra del pedido.
--   (Excepcion documentada: los pedidos sin items -cancelados o no
--   disponibles- tienen UNA fila con producto/vendedor 'SIN_ITEM',
--   cantidad_items = 0 y price = 0, para que cuenten como pedidos.)
-- =====================================================================

-- Re-ejecutable: borra primero la tabla de hechos y luego las dimensiones
DROP TABLE IF EXISTS fact_ventas        CASCADE;
DROP TABLE IF EXISTS dim_tiempo         CASCADE;
DROP TABLE IF EXISTS dim_producto       CASCADE;
DROP TABLE IF EXISTS dim_vendedor       CASCADE;
DROP TABLE IF EXISTS dim_cliente        CASCADE;
DROP TABLE IF EXISTS dim_pago           CASCADE;
DROP TABLE IF EXISTS dim_estado_pedido  CASCADE;

-- ---------------------------------------------------------------------
-- DIMENSIONES
-- ---------------------------------------------------------------------

-- Tiempo: una fila por dia. sk_tiempo = AAAAMMDD (clave inteligente)
CREATE TABLE dim_tiempo (
    sk_tiempo         INTEGER      PRIMARY KEY,
    fecha             DATE         NOT NULL UNIQUE,
    anio              SMALLINT     NOT NULL,
    trimestre         SMALLINT     NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    mes               SMALLINT     NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nombre_mes        VARCHAR(15)  NOT NULL,
    anio_mes          VARCHAR(7)   NOT NULL,          -- 'AAAA-MM'
    semana_anio       SMALLINT     NOT NULL,
    dia               SMALLINT     NOT NULL,
    dia_semana        SMALLINT     NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),  -- 1 = lunes
    nombre_dia        VARCHAR(12)  NOT NULL,
    es_fin_de_semana  SMALLINT     NOT NULL CHECK (es_fin_de_semana IN (0, 1))
);

-- Producto: sk_producto = 0 es el miembro 'SIN_ITEM' (pedidos sin items)
CREATE TABLE dim_producto (
    sk_producto           INTEGER        PRIMARY KEY,
    product_id            VARCHAR(32)    NOT NULL UNIQUE,
    categoria_pt          VARCHAR(80)    NOT NULL,
    categoria_en          VARCHAR(80)    NOT NULL,
    peso_g                NUMERIC(10,1),
    largo_cm              NUMERIC(8,1),
    alto_cm               NUMERIC(8,1),
    ancho_cm              NUMERIC(8,1),
    num_fotos             SMALLINT,
    nombre_longitud       SMALLINT,
    descripcion_longitud  INTEGER
);

-- Vendedor: sk_vendedor = 0 es el miembro 'SIN_ITEM'
CREATE TABLE dim_vendedor (
    sk_vendedor    INTEGER           PRIMARY KEY,
    seller_id      VARCHAR(32)       NOT NULL UNIQUE,
    ciudad         VARCHAR(80)       NOT NULL,
    estado         VARCHAR(2)        NOT NULL,
    codigo_postal  VARCHAR(5),
    latitud        DOUBLE PRECISION,
    longitud       DOUBLE PRECISION
);

-- Cliente: una fila por persona (customer_unique_id)
CREATE TABLE dim_cliente (
    sk_cliente          INTEGER           PRIMARY KEY,
    customer_unique_id  VARCHAR(32)       NOT NULL UNIQUE,
    ciudad              VARCHAR(80)       NOT NULL,
    estado              VARCHAR(2)        NOT NULL,
    codigo_postal       VARCHAR(5),
    latitud             DOUBLE PRECISION,
    longitud            DOUBLE PRECISION
);

-- Pago: perfil de pago del pedido (tipo principal x rango de cuotas x pago mixto)
CREATE TABLE dim_pago (
    sk_pago              INTEGER      PRIMARY KEY,
    tipo_pago_principal  VARCHAR(20)  NOT NULL,
    rango_cuotas         VARCHAR(15)  NOT NULL,
    es_pago_mixto        SMALLINT     NOT NULL CHECK (es_pago_mixto IN (0, 1)),
    UNIQUE (tipo_pago_principal, rango_cuotas, es_pago_mixto)
);

-- Estado del pedido: estado x puntualidad de entrega
CREATE TABLE dim_estado_pedido (
    sk_estado     INTEGER      PRIMARY KEY,
    estado_pedido VARCHAR(20)  NOT NULL,
    puntualidad   VARCHAR(15)  NOT NULL,      -- 'A tiempo' | 'Con retraso' | 'Sin entrega'
    es_entregado  SMALLINT     NOT NULL CHECK (es_entregado IN (0, 1)),
    es_cancelado  SMALLINT     NOT NULL CHECK (es_cancelado IN (0, 1)),   -- canceled o unavailable
    UNIQUE (estado_pedido, puntualidad)
);

-- ---------------------------------------------------------------------
-- TABLA DE HECHOS
-- ---------------------------------------------------------------------
CREATE TABLE fact_ventas (
    sk_venta              INTEGER        PRIMARY KEY,
    order_id              VARCHAR(32)    NOT NULL,          -- dimension degenerada
    order_item_id         SMALLINT       NOT NULL,          -- 0 = pedido sin items
    sk_tiempo             INTEGER        NOT NULL REFERENCES dim_tiempo(sk_tiempo),
    sk_producto           INTEGER        NOT NULL REFERENCES dim_producto(sk_producto),
    sk_vendedor           INTEGER        NOT NULL REFERENCES dim_vendedor(sk_vendedor),
    sk_cliente            INTEGER        NOT NULL REFERENCES dim_cliente(sk_cliente),
    sk_pago               INTEGER        NOT NULL REFERENCES dim_pago(sk_pago),
    sk_estado             INTEGER        NOT NULL REFERENCES dim_estado_pedido(sk_estado),
    -- Medidas a nivel de item
    price                 NUMERIC(10,2)  NOT NULL,
    freight_value         NUMERIC(10,2)  NOT NULL,
    valor_total_item      NUMERIC(10,2)  NOT NULL,          -- price + freight_value
    cantidad_items        SMALLINT       NOT NULL,          -- 1 (0 en pedidos sin items)
    -- Medidas a nivel de pedido (repetidas en cada item del pedido)
    payment_value         NUMERIC(12,2),                    -- pago del pedido repartido proporcionalmente entre items
    payment_installments  SMALLINT,                         -- max. de cuotas del pedido
    review_score          SMALLINT       CHECK (review_score BETWEEN 1 AND 5),
    dias_entrega          INTEGER,                          -- compra -> entrega al cliente
    dias_retraso          INTEGER,                          -- entrega real - estimada (>0 = tarde)
    es_primer_item        SMALLINT       NOT NULL CHECK (es_primer_item IN (0, 1)),  -- 1 fila por pedido = 1
    UNIQUE (order_id, order_item_id)
);

-- Indices sobre las claves foraneas (aceleran joins y filtros del dashboard)
CREATE INDEX ix_fact_tiempo   ON fact_ventas (sk_tiempo);
CREATE INDEX ix_fact_producto ON fact_ventas (sk_producto);
CREATE INDEX ix_fact_vendedor ON fact_ventas (sk_vendedor);
CREATE INDEX ix_fact_cliente  ON fact_ventas (sk_cliente);
CREATE INDEX ix_fact_pago     ON fact_ventas (sk_pago);
CREATE INDEX ix_fact_estado   ON fact_ventas (sk_estado);
CREATE INDEX ix_fact_order    ON fact_ventas (order_id);

COMMENT ON TABLE fact_ventas IS
  'Grano: un item (producto) vendido dentro de un pedido. Pedidos sin items = 1 fila con SIN_ITEM y cantidad_items = 0.';
