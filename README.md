# Data Mart Olist + Dashboard Streamlit

**Materia:** Inteligencia de Negocios · UPSE · Carrera de Software
**Estudiante:** Tomalá Tumbaco Mike Neiman
**Docente:** Ing. Anthony Abrahan Pachay Espinoza, MSc.
**Entregable 3:** Mi primer dashboard (solución analítica completa)

Solución de Business Intelligence de extremo a extremo con el dataset
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce):

```
CSV de Kaggle -> ETL (Python/pandas) -> PostgreSQL (modelo estrella)
              -> Vista y funciones SQL -> Streamlit (dashboard)
```

La aplicación Streamlit **no lee los CSV**: todos los KPI, gráficos y tablas
salen de PostgreSQL.

## Preguntas de negocio

| N.º | Pregunta |
|---|---|
| P1 | ¿Qué categorías y estados generan más ingresos y cómo evolucionan las ventas por mes? |
| P2 | ¿Qué tan bien se cumplen los plazos de entrega y en qué regiones hay más demora? |
| P3 | ¿Cómo se relaciona el retraso en la entrega con la satisfacción del cliente? |

## Modelo dimensional

Esquema en estrella. **Granularidad:** una fila de `fact_ventas` representa un
ítem vendido dentro de un pedido (`order_id` + `order_item_id`).

- Tabla de hechos: `fact_ventas` (113.425 filas)
- Dimensiones: `dim_tiempo`, `dim_cliente`, `dim_producto`, `dim_vendedor`,
  `dim_pago`, `dim_estado_pedido`

## Requisitos

- Windows, macOS o Linux
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) en ejecución
- Git (opcional, para clonar el repositorio)

No hace falta instalar PostgreSQL ni Python: todo corre en contenedores.

## Estructura del proyecto

```
olist-datamart/
├── docker-compose.yml            PostgreSQL + ETL + loader + pgAdmin (opcional)
├── docker-compose.override.yml   Servicio de la app Streamlit
├── app/
│   ├── app.py                    Dashboard Streamlit
│   └── requirements.txt          Dependencias de Python
├── scripts/
│   ├── 00_etl_limpieza.py        Limpieza y transformación
│   ├── 01_crear_tablas.sql       Creación del modelo estrella
│   ├── 02_carga.sql              Carga de datos
│   ├── 03_validacion.sql         Consultas de validación
│   ├── 04_vistas_funciones.sql   Vistas y funciones (Entregable 2)
│   ├── 05_prueba_funciones.sql   Pruebas
│   └── 06_vistas_app.sql         Vista y funciones para la app (Entregable 3)
├── evidencia/                    Salidas de cada script
├── olist_raw/                    CSV originales (NO se suben a GitHub)
└── datos_limpios/                CSV generados por el ETL (NO se suben)
```

## Ejecución paso a paso

Ejecutar todos los comandos desde la carpeta del proyecto.

### 1. Descargar los datos
Descargar los 9 CSV desde Kaggle y copiarlos en la carpeta `olist_raw/`.

### 2. Levantar PostgreSQL
```
docker compose up -d postgres
docker compose ps
```
Esperar a que `bi-postgres` aparezca como `healthy`.

### 3. Ejecutar el ETL
```
docker compose run --rm etl
```
Genera los CSV limpios en `datos_limpios/` y el reporte `reporte_limpieza.txt`.

### 4. Crear tablas, cargar y validar
```
docker compose run --rm loader
```
Ejecuta los scripts 01 a 05 y guarda la salida en `evidencia/`.

### 5. Crear la vista y funciones para la aplicación
```
docker compose exec -T postgres psql -U bi_user -d bi_database < scripts/06_vistas_app.sql
```
Debe mostrar `CREATE VIEW` y dos veces `CREATE FUNCTION`.

### 6. Levantar la aplicación Streamlit
```
docker compose up -d app
```
La primera vez instala las librerías (1 a 3 minutos). Abrir en el navegador:

**http://localhost:8501**

Para ver el estado o los errores:
```
docker compose logs app --tail 40
```

### 7. (Opcional) Explorar con pgAdmin
```
docker compose --profile tools up -d
```
Abrir http://localhost:5050, elegir el servidor "BI Olist (Docker)" e ingresar la
contraseña `bi_password`.

## Credenciales de la base de datos (uso académico)

| Dato | Valor |
|---|---|
| Base de datos | `bi_database` |
| Usuario | `bi_user` |
| Contraseña | `bi_password` |
| Puerto | `5432` |

## Verificación rápida desde consola

```
docker compose exec postgres psql -x -P pager=off -U bi_user -d bi_database -c "SELECT * FROM fn_kpis_filtrado();"
```
Resultado esperado sin filtros: ingresos 13.494.400,74 · 98.199 pedidos ·
ticket 137,42 · 91,89 % de entregas a tiempo · 12,09 días · puntaje 4,09 ·
1,24 % de cancelación.

Con filtros (fecha inicial, fecha final, estado del cliente, categoría):
```
docker compose exec postgres psql -x -P pager=off -U bi_user -d bi_database -c "SELECT * FROM fn_kpis_filtrado('2018-01-01','2018-06-30','SP',NULL);"
```
`NULL` significa "sin filtro".

## Objetos SQL que consume la aplicación

| Objeto | Descripción |
|---|---|
| `vw_ventas_app` | Vista que une `fact_ventas` con las 6 dimensiones |
| `fn_kpis_filtrado(fecha_ini, fecha_fin, estado, categoria)` | KPI con filtros opcionales |
| `fn_ingresos_mensuales(fecha_ini, fecha_fin, estado, categoria)` | Ingresos y pedidos por mes |

## Contenido de la aplicación

| Sección | KPI | Gráficos | Detalle |
|---|---|---|---|
| Ventas e ingresos | Ingresos totales, total de pedidos, ticket promedio | Evolución mensual · Top 10 categorías | Top 20 vendedores |
| Entregas y satisfacción | % entregas a tiempo, tiempo promedio de entrega, puntaje de reseña | Puntaje según retraso · Días de entrega por estado | 100 pedidos con mayor retraso |

**Filtros** (barra lateral, afectan a todas las consultas): rango de fechas de
compra, estado del cliente y categoría de producto.

## Detener el entorno

```
docker compose down
```
Los datos se conservan en el volumen `postgres_data`.

## Uso de Inteligencia Artificial

Se utilizó IA generativa como apoyo para diseñar la vista y funciones SQL,
construir la aplicación Streamlit, resolver errores y configurar Git. El detalle
de cada uso (problema, prompt, solución, ajustes y validación) se documenta en el
informe final.
