#!/usr/bin/env bash
# Se ejecuta DENTRO del contenedor 'loader' (cwd = /work).
# Corre los scripts SQL en orden y guarda la salida en ./evidencia/
set -euo pipefail

PSQL="psql -v ON_ERROR_STOP=1"
mkdir -p evidencia

# Verifica que el ETL haya generado los CSV limpios
for f in dim_tiempo dim_producto dim_vendedor dim_cliente dim_pago dim_estado_pedido fact_ventas; do
  if [ ! -f "datos_limpios/${f}.csv" ]; then
    echo "ERROR: falta datos_limpios/${f}.csv -> ejecuta primero: docker compose run --rm etl"
    exit 1
  fi
done

echo "==> PostgreSQL: $($PSQL -tAc 'SELECT version();')"      | tee evidencia/00_version.txt

echo "==> 01 Crear tablas"        ; $PSQL -f scripts/01_crear_tablas.sql     2>&1 | tee evidencia/01_crear_tablas.txt
echo "==> 02 Cargar datos"        ; $PSQL -f scripts/02_carga.sql            2>&1 | tee evidencia/02_carga.txt
echo "==> 03 Validacion"          ; $PSQL -f scripts/03_validacion.sql       2>&1 | tee evidencia/03_validacion.txt
echo "==> 04 Vistas y funciones"  ; $PSQL -f scripts/04_vistas_funciones.sql 2>&1 | tee evidencia/04_vistas_funciones.txt
echo "==> 05 Prueba de funciones" ; $PSQL -f scripts/05_prueba_funciones.sql 2>&1 | tee evidencia/05_prueba_funciones.txt

echo
echo "LISTO. Evidencia guardada en ./evidencia/"
