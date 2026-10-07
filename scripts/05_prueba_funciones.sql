-- =====================================================================
-- Script 05: Prueba de vistas y funciones (evidencia para el dashboard)
-- =====================================================================
\echo '--- fn_kpis() todo el periodo ---'
SELECT * FROM fn_kpis();

\echo '--- fn_kpis() con filtros: 2017-01-01 a 2018-08-31, estado SP ---'
SELECT * FROM fn_kpis(p_fecha_ini => '2017-01-01', p_fecha_fin => '2018-08-31', p_estado_cliente => 'SP');

\echo '--- fn_ventas_por_mes() (primeros 6 meses) ---'
SELECT * FROM fn_ventas_por_mes() ORDER BY anio_mes LIMIT 6;

\echo '--- fn_ventas_por_categoria() top 5 ---'
SELECT * FROM fn_ventas_por_categoria(p_top => 5);

\echo '--- fn_logistica_por_estado() ---'
SELECT * FROM fn_logistica_por_estado() LIMIT 10;

\echo '--- fn_top_vendedores() top 5 ---'
SELECT * FROM fn_top_vendedores(p_top => 5);

\echo '--- fn_pagos_por_tipo() ---'
SELECT * FROM fn_pagos_por_tipo() LIMIT 10;

\echo '--- fn_resena_vs_entrega() ---'
SELECT * FROM fn_resena_vs_entrega();

\echo '--- fn_detalle_pedidos() 5 filas ---'
SELECT * FROM fn_detalle_pedidos(p_limit => 5);
