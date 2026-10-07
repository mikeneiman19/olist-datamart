-- =====================================================================
-- Script 02: Carga de datos (ejecutar con psql, desde la carpeta que
-- contiene la subcarpeta datos_limpios/ generada por 00_etl_limpieza.py)
--
--   (en Docker lo ejecuta scripts/run_pipeline.sh dentro del contenedor 'loader')
--
-- Orden: primero las dimensiones y al final la tabla de hechos
-- (las claves foraneas lo exigen).
-- Nota: \copy lee el archivo desde TU computador (cliente), por eso no
-- requiere permisos de superusuario. Cada \copy va en una sola linea.
-- Alternativa grafica: DBeaver -> clic derecho en la tabla -> Import Data.
-- =====================================================================

\echo 'Cargando dimensiones...'

\copy dim_tiempo (sk_tiempo, fecha, anio, trimestre, mes, nombre_mes, anio_mes, semana_anio, dia, dia_semana, nombre_dia, es_fin_de_semana) FROM 'datos_limpios/dim_tiempo.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy dim_producto (sk_producto, product_id, categoria_pt, categoria_en, peso_g, largo_cm, alto_cm, ancho_cm, num_fotos, nombre_longitud, descripcion_longitud) FROM 'datos_limpios/dim_producto.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy dim_vendedor (sk_vendedor, seller_id, ciudad, estado, codigo_postal, latitud, longitud) FROM 'datos_limpios/dim_vendedor.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy dim_cliente (sk_cliente, customer_unique_id, ciudad, estado, codigo_postal, latitud, longitud) FROM 'datos_limpios/dim_cliente.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy dim_pago (sk_pago, tipo_pago_principal, rango_cuotas, es_pago_mixto) FROM 'datos_limpios/dim_pago.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy dim_estado_pedido (sk_estado, estado_pedido, puntualidad, es_entregado, es_cancelado) FROM 'datos_limpios/dim_estado_pedido.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Cargando tabla de hechos...'

\copy fact_ventas (sk_venta, order_id, order_item_id, sk_tiempo, sk_producto, sk_vendedor, sk_cliente, sk_pago, sk_estado, price, freight_value, valor_total_item, payment_value, payment_installments, review_score, dias_entrega, dias_retraso, cantidad_items, es_primer_item) FROM 'datos_limpios/fact_ventas.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- Actualiza estadisticas para que el optimizador use bien los indices
ANALYZE;

\echo 'Carga finalizada. Ejecuta 03_validacion.sql para verificar.'
