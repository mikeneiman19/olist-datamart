# Entregable 2 · Data Mart Olist en PostgreSQL con Docker

Todo corre en contenedores: no necesitas instalar PostgreSQL ni Python.

```
olist-datamart/
├── docker-compose.yml      <- postgres + etl + loader + pgadmin (opcional)
├── olist_raw/              <- aquí van los 9 CSV de Kaggle
├── datos_limpios/          <- los genera el ETL
├── evidencia/              <- salidas de cada script (para tu informe)
├── pgadmin/servers.json
└── scripts/                <- 00 ETL · 01 tablas · 02 carga · 03 validación · 04 vistas/funciones · 05 pruebas
```

Credenciales: host `localhost` · puerto `5432` · base `bi_database` · usuario `bi_user` · contraseña `bi_password`.

## Paso 0 · Requisitos
1. Docker Desktop instalado y **abierto** (`docker --version` y `docker compose version` deben responder).
2. Descarga el dataset de https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce, descomprime `archive.zip` y copia los 9 CSV dentro de `olist_raw/`.

## Paso 1 · Levantar PostgreSQL
```bash
docker compose up -d
docker compose ps          # bi-postgres debe decir "healthy"
```
📸 Captura 1: `docker compose ps` + `docker exec bi-postgres psql -U bi_user -d bi_database -c "SELECT version();"`

## Paso 2 · Limpiar y transformar (ETL)
```bash
docker compose run --rm etl
```
Genera 7 CSV en `datos_limpios/` y `reporte_limpieza.txt` (conteo de cada transformación → sección 5 del informe).

## Paso 3 · Crear tablas, cargar, validar y crear vistas/funciones
```bash
docker compose run --rm loader
```
Ejecuta `01` → `05` en orden y guarda la salida en `evidencia/`. Se detiene ante el primer error.
📸 Captura 2: salida de `02_carga` (COPY ...) y 03_validacion (compara con "esperado").

Para repetir desde cero (es re-ejecutable): `docker compose run --rm loader`
Para borrar TODO y empezar limpio: `docker compose down -v`

## Paso 4 · Explorar con pgAdmin (opcional, para capturas)
```bash
docker compose --profile tools up -d
```
Abre http://localhost:5050 → servidor "BI Olist (Docker)" → contraseña `bi_password`.
📸 Captura 3: Schemas → public → Tables (las 7 tablas) y el diagrama ERD (clic derecho en la base → ERD).

También puedes usar DBeaver con los datos de conexión de arriba (host `localhost`).

## Paso 5 · Probar las funciones a mano
```bash
docker exec -it bi-postgres psql -U bi_user -d bi_database
```
```sql
SELECT * FROM fn_kpis();
SELECT * FROM fn_kpis(p_fecha_ini => '2017-01-01', p_estado_cliente => 'SP');
SELECT * FROM fn_ventas_por_categoria(p_top => 10);
\dt      -- tablas
\dv      -- vistas
\df fn_* -- funciones
```

## Resultados esperados (de tu PDF)
| Control | Esperado |
|---|---|
| Filas | fact 113,425 · cliente 96,096 · producto 32,952 · vendedor 3,096 · tiempo 1,096 · pago 19 · estado 12 |
| Huérfanos por FK / grano duplicado / es_primer_item mal | 0 |
| SUM(price) / SUM(freight_value) / SUM(payment_value) | 13,591,643.70 / 2,251,909.54 / 16,008,872.12 |
| Ítems / pedidos | 112,650 / 99,441 |
| Pedidos sin reseña / sin entrega | 768 / 2,965 |
| fn_kpis() | ingresos 13,494,400.74 · ticket 137.41 · a tiempo 91.89 % · entrega 12.09 d · reseña 4.09 · recurrentes 3.04 % · cancelación 1.24 % |

## Problemas frecuentes
| Síntoma | Solución |
|---|---|
| `port is already allocated` (5432) | Tienes otro PostgreSQL local: cambia a `"5433:5432"` en el compose y vuelve a `docker compose up -d`. |
| `falta datos_limpios/...csv` | Corre primero el Paso 2. |
| `FileNotFoundError ... olist_raw` | Los CSV no están en `olist_raw/` (sin subcarpeta). |
| `could not connect` en loader | Espera a que postgres esté `healthy` (`docker compose ps`). |
| Cambié un script SQL y quiero rehacerlo | `docker compose run --rm loader` (01 borra y recrea las tablas). |

## Texto sugerido para la sección 6 del informe ("Instalación y configuración")
> Se usó Docker Compose con la imagen oficial `postgres:17` (contenedor `bi-postgres`, puerto 5432, base `bi_database`, usuario `bi_user`, volumen persistente `postgres_data`). El ETL en Python (pandas) corre en un contenedor `python:3.12-slim` y la carga/validación con `psql` en un contenedor `postgres:17`, de modo que el entorno es aislado y reproducible con `docker compose up -d`. Sistema operativo anfitrión: Windows 10. Cliente gráfico: pgAdmin 4 (captura adjunta).
>
 ## Dashboard (mockup)

Mockup del dashboard con los 8 KPI del Data Mart. Los gráficos de ingresos por mes y categorías son ilustrativos.

[Ver el dashboard](https://mikeneiman19.github.io/olist-datamart/dashboard_mockup.html)
