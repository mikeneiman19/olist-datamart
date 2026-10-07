"""
ENTREGABLE 2 - Construccion del Data Mart (Olist)
Script 00: Limpieza y transformacion (ETL)

Lee los 9 CSV originales de Kaggle y genera en ./datos_limpios:
    dim_tiempo.csv, dim_producto.csv, dim_vendedor.csv, dim_cliente.csv,
    dim_pago.csv, dim_estado_pedido.csv, fact_ventas.csv
y un reporte con el conteo de cada transformacion (reporte_limpieza.txt).

Uso:
    python 00_etl_limpieza.py --origen ./olist_raw --destino ./datos_limpios
"""
import argparse
import math
import os
import re
import unicodedata

import numpy as np
import pandas as pd

parser = argparse.ArgumentParser()
parser.add_argument("--origen", default="./olist_raw", help="carpeta con los 9 CSV originales")
parser.add_argument("--destino", default="./datos_limpios", help="carpeta de salida")
args = parser.parse_args()
os.makedirs(args.destino, exist_ok=True)

LOG = []


def log(msg):
    print(msg)
    LOG.append(msg)


def leer(nombre, **kw):
    return pd.read_csv(os.path.join(args.origen, nombre), **kw)


def sin_acentos(x):
    return unicodedata.normalize("NFKD", str(x)).encode("ascii", "ignore").decode()


# ---------------------------------------------------------------------------
# 1. LECTURA (codigos postales como texto para no perder el cero inicial)
# ---------------------------------------------------------------------------
orders = leer("olist_orders_dataset.csv")
items = leer("olist_order_items_dataset.csv")
pays = leer("olist_order_payments_dataset.csv")
reviews = leer("olist_order_reviews_dataset.csv")
customers = leer("olist_customers_dataset.csv", dtype=str)
products = leer("olist_products_dataset.csv")
sellers = leer("olist_sellers_dataset.csv", dtype=str)
geo = leer("olist_geolocation_dataset.csv", dtype={"geolocation_zip_code_prefix": str})
trad = leer("product_category_name_translation.csv")

log("== 1. LECTURA ==")
for n, d in [("orders", orders), ("order_items", items), ("payments", pays), ("reviews", reviews),
             ("customers", customers), ("products", products), ("sellers", sellers),
             ("geolocation", geo), ("translation", trad)]:
    log(f"{n}: {len(d):,} filas")

# Fechas: texto -> datetime
for c in ["order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date",
          "order_delivered_customer_date", "order_estimated_delivery_date"]:
    orders[c] = pd.to_datetime(orders[c])
reviews["review_answer_timestamp"] = pd.to_datetime(reviews["review_answer_timestamp"])
reviews["review_creation_date"] = pd.to_datetime(reviews["review_creation_date"])
log("Fechas convertidas de texto a datetime (orders, reviews).")

# ---------------------------------------------------------------------------
# 2. GEOLOCATION: un registro por prefijo postal
# ---------------------------------------------------------------------------
geo["zip"] = geo["geolocation_zip_code_prefix"].str.zfill(5)
geo["city"] = geo["geolocation_city"].map(sin_acentos).str.lower().str.strip()
geo_zip = (geo.groupby("zip")
           .agg(lat=("geolocation_lat", "mean"), lng=("geolocation_lng", "mean"),
                ciudad_geo=("city", lambda s: s.mode().iloc[0]))
           .reset_index())
log("\n== 2. GEOLOCATION ==")
log(f"{len(geo):,} filas -> {len(geo_zip):,} prefijos postales unicos (promedio lat/lng). "
    f"Filas duplicadas exactas eliminadas: {geo.duplicated(['geolocation_zip_code_prefix','geolocation_lat','geolocation_lng','geolocation_city','geolocation_state']).sum():,}")
geo_ciudad = dict(zip(geo_zip["zip"], geo_zip["ciudad_geo"]))


def limpiar_ciudad(raw, zip5):
    """Estandariza nombres de ciudad: minusculas, sin tildes, sin sufijos de estado."""
    c = sin_acentos(raw).lower().strip().replace("\\", "/")
    if "@" in c or re.fullmatch(r"\d+", c):          # correo o codigo postal en lugar de ciudad
        return geo_ciudad.get(zip5, c)
    c = re.split(r"\s*[/,(]\s*", c)[0]               # 'maua/sao paulo' -> 'maua'
    c = re.sub(r"\s*-\s*[a-z]{2}$", "", c).strip()   # 'sao paulo - sp' -> 'sao paulo'
    if c == "sbc":
        c = "sao bernardo do campo"
    if len(c) <= 2:                                  # 'sp' -> ciudad segun codigo postal
        return geo_ciudad.get(zip5, c)
    return c


# ---------------------------------------------------------------------------
# 3. DIM_TIEMPO (generada)
# ---------------------------------------------------------------------------
log("\n== 3. DIM_TIEMPO ==")
fechas = pd.date_range("2016-01-01", "2018-12-31", freq="D")
meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]
dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
dim_tiempo = pd.DataFrame({
    "sk_tiempo": fechas.strftime("%Y%m%d").astype(int),
    "fecha": fechas.date,
    "anio": fechas.year,
    "trimestre": fechas.quarter,
    "mes": fechas.month,
    "nombre_mes": [meses[m - 1] for m in fechas.month],
    "anio_mes": fechas.strftime("%Y-%m"),
    "semana_anio": fechas.isocalendar().week.astype(int).values,
    "dia": fechas.day,
    "dia_semana": fechas.dayofweek + 1,
    "nombre_dia": [dias[d] for d in fechas.dayofweek],
    "es_fin_de_semana": (fechas.dayofweek >= 5).astype(int),
})
log(f"{len(dim_tiempo):,} dias (2016-01-01 a 2018-12-31).")

# ---------------------------------------------------------------------------
# 4. DIM_PRODUCTO
# ---------------------------------------------------------------------------
log("\n== 4. DIM_PRODUCTO ==")
p = products.rename(columns={"product_name_lenght": "nombre_longitud",
                             "product_description_lenght": "descripcion_longitud"})
log("Columnas con error ortografico renombradas: product_name_lenght -> nombre_longitud, "
    "product_description_lenght -> descripcion_longitud.")
p = p.merge(trad, on="product_category_name", how="left")
manual = {"pc_gamer": "pc_gamer",
          "portateis_cozinha_e_preparadores_de_alimentos": "portable_kitchen_food_preparers"}
sin_trad = p["product_category_name_english"].isna() & p["product_category_name"].notna()
log(f"Categorias sin traduccion en el archivo oficial: {sorted(p.loc[sin_trad, 'product_category_name'].unique())} "
    f"-> traducidas a mano ({sin_trad.sum()} productos).")
p.loc[sin_trad, "product_category_name_english"] = p.loc[sin_trad, "product_category_name"].map(manual)
n_sin_cat = p["product_category_name"].isna().sum()
p["product_category_name"] = p["product_category_name"].fillna("sin_categoria")
p["product_category_name_english"] = p["product_category_name_english"].fillna("sin_categoria")
log(f"{n_sin_cat} productos sin categoria -> 'sin_categoria'.")
n_peso0 = (p["product_weight_g"] == 0).sum()
p.loc[p["product_weight_g"] == 0, "product_weight_g"] = np.nan
log(f"{n_peso0} productos con peso 0 g -> peso NULL (un producto no pesa 0 g).")
dim_producto = pd.DataFrame({
    "sk_producto": np.arange(1, len(p) + 1),
    "product_id": p["product_id"],
    "categoria_pt": p["product_category_name"],
    "categoria_en": p["product_category_name_english"],
    "peso_g": p["product_weight_g"],
    "largo_cm": p["product_length_cm"],
    "alto_cm": p["product_height_cm"],
    "ancho_cm": p["product_width_cm"],
    "num_fotos": p["product_photos_qty"],
    "nombre_longitud": p["nombre_longitud"],
    "descripcion_longitud": p["descripcion_longitud"],
})
# Miembro "desconocido" (sk=0) para pedidos sin items
fila0 = {c: np.nan for c in dim_producto.columns}
fila0.update(sk_producto=0, product_id="SIN_ITEM", categoria_pt="sin_item", categoria_en="sin_item")
dim_producto = pd.concat([pd.DataFrame([fila0]), dim_producto], ignore_index=True)
for c in ["num_fotos", "nombre_longitud", "descripcion_longitud"]:
    dim_producto[c] = dim_producto[c].astype("Int64")
log(f"{len(dim_producto):,} filas (33,951 productos + 1 miembro 'SIN_ITEM').".replace("33,951", f"{len(p):,}"))
map_prod = dict(zip(dim_producto["product_id"], dim_producto["sk_producto"]))

# ---------------------------------------------------------------------------
# 5. DIM_VENDEDOR
# ---------------------------------------------------------------------------
log("\n== 5. DIM_VENDEDOR ==")
s = sellers.copy()
s["zip"] = s["seller_zip_code_prefix"].str.zfill(5)
s["ciudad"] = [limpiar_ciudad(c, z) for c, z in zip(s["seller_city"], s["zip"])]
cambiadas = (s["ciudad"] != s["seller_city"].map(lambda x: sin_acentos(x).lower().strip())).sum()
log(f"Ciudades de vendedores estandarizadas: {cambiadas} filas corregidas "
    f"(ej. 'sao paulo - sp', 'sbc/sp', correo o codigo postal usado como ciudad).")
s = s.merge(geo_zip[["zip", "lat", "lng"]], on="zip", how="left")
log(f"Vendedores sin coordenadas (zip no existe en geolocation): {s['lat'].isna().sum()}")
dim_vendedor = pd.DataFrame({
    "sk_vendedor": np.arange(1, len(s) + 1),
    "seller_id": s["seller_id"], "ciudad": s["ciudad"],
    "estado": s["seller_state"].str.upper(), "codigo_postal": s["zip"],
    "latitud": s["lat"], "longitud": s["lng"],
})
fila0 = {c: np.nan for c in dim_vendedor.columns}
fila0.update(sk_vendedor=0, seller_id="SIN_ITEM", ciudad="sin_item", estado="NA")
dim_vendedor = pd.concat([pd.DataFrame([fila0]), dim_vendedor], ignore_index=True)
log(f"{len(dim_vendedor):,} filas (incluye miembro 'SIN_ITEM').")
map_sell = dict(zip(dim_vendedor["seller_id"], dim_vendedor["sk_vendedor"]))

# ---------------------------------------------------------------------------
# 6. DIM_CLIENTE (una fila por customer_unique_id = persona real)
# ---------------------------------------------------------------------------
log("\n== 6. DIM_CLIENTE ==")
c = customers.merge(orders[["customer_id", "order_purchase_timestamp"]], on="customer_id", how="left")
c["zip"] = c["customer_zip_code_prefix"].str.zfill(5)
n_zip0 = int(c["customer_zip_code_prefix"].str.startswith("0").sum())
log(f"Codigos postales leidos como texto y rellenados a 5 digitos: {n_zip0:,} clientes tienen codigo con cero inicial "
    f"(leidos como numero lo habrian perdido).")
c = c.sort_values("order_purchase_timestamp")
c_unico = c.drop_duplicates("customer_unique_id", keep="last").copy()   # ubicacion de su compra mas reciente
log(f"{len(c):,} customer_id -> {len(c_unico):,} clientes unicos (se conserva la ubicacion de su pedido mas reciente).")
c_unico["ciudad"] = c_unico["customer_city"].map(lambda x: sin_acentos(x).lower().strip())
c_unico = c_unico.merge(geo_zip[["zip", "lat", "lng"]], on="zip", how="left")
log(f"Clientes sin coordenadas (zip no existe en geolocation): {c_unico['lat'].isna().sum():,} -> lat/lng NULL.")
c_unico = c_unico.reset_index(drop=True)
dim_cliente = pd.DataFrame({
    "sk_cliente": np.arange(1, len(c_unico) + 1),
    "customer_unique_id": c_unico["customer_unique_id"], "ciudad": c_unico["ciudad"],
    "estado": c_unico["customer_state"].str.upper(), "codigo_postal": c_unico["zip"],
    "latitud": c_unico["lat"], "longitud": c_unico["lng"],
})
map_unique_sk = dict(zip(dim_cliente["customer_unique_id"], dim_cliente["sk_cliente"]))
map_cust_sk = {cid: map_unique_sk[uid] for cid, uid in zip(customers["customer_id"], customers["customer_unique_id"])}

# ---------------------------------------------------------------------------
# 7. Resumen a nivel PEDIDO: pagos, resena, entrega
# ---------------------------------------------------------------------------
log("\n== 7. RESUMEN A NIVEL PEDIDO ==")
# 7a. Pagos
por_tipo = pays.groupby(["order_id", "payment_type"])["payment_value"].sum().reset_index()
principal = (por_tipo.sort_values(["order_id", "payment_value"], ascending=[True, False])
             .drop_duplicates("order_id")[["order_id", "payment_type"]]
             .rename(columns={"payment_type": "tipo_pago_principal"}))
agg = pays.groupby("order_id").agg(payment_total=("payment_value", "sum"),
                                   cuotas=("payment_installments", "max"),
                                   n_tipos=("payment_type", "nunique")).reset_index()
pago = agg.merge(principal, on="order_id")
pago["cuotas"] = pago["cuotas"].clip(lower=1)
pago["es_pago_mixto"] = (pago["n_tipos"] > 1).astype(int)


def rango_cuotas(n):
    if n <= 1: return "1 (contado)"
    if n <= 3: return "2-3"
    if n <= 6: return "4-6"
    if n <= 12: return "7-12"
    return "13-24"


pago["rango_cuotas"] = pago["cuotas"].map(rango_cuotas)
log(f"Pagos: {len(pays):,} registros -> {len(pago):,} pedidos con pago. "
    f"{pago['es_pago_mixto'].sum():,} pedidos pagados con mas de un metodo (tipo principal = el de mayor valor). "
    f"Cuotas 0 tratadas como 1.")
log(f"Tipo 'not_defined': {(pays['payment_type'] == 'not_defined').sum()} registros; se conserva como categoria.")

# 7b. Resena: la mas reciente por pedido
rv = (reviews.sort_values(["order_id", "review_answer_timestamp", "review_creation_date"])
      .drop_duplicates("order_id", keep="last")[["order_id", "review_score"]])
n_multi = int(reviews.groupby("order_id").size().gt(1).sum())
log(f"Resenas: {len(reviews):,} -> {len(rv):,} (una por pedido, la mas reciente; "
    f"pedidos con mas de una resena: {n_multi}). "
    f"Pedidos sin resena: {(~orders['order_id'].isin(rv['order_id'])).sum()} -> review_score NULL.")

# 7c. Entrega y puntualidad
o = orders.copy()
entregado_ts = o["order_delivered_customer_date"]
o["dias_entrega"] = ((entregado_ts - o["order_purchase_timestamp"]).dt.total_seconds() // 86400)
o["dias_retraso"] = ((entregado_ts - o["order_estimated_delivery_date"]).dt.total_seconds() / 86400).map(
    lambda x: math.ceil(x) if pd.notna(x) else np.nan)
o["puntualidad"] = np.where(entregado_ts.isna(), "Sin entrega",
                            np.where(entregado_ts <= o["order_estimated_delivery_date"], "A tiempo", "Con retraso"))
o["es_entregado"] = (o["order_status"] == "delivered").astype(int)
o["es_cancelado"] = o["order_status"].isin(["canceled", "unavailable"]).astype(int)
log(f"Pedidos 'delivered' sin fecha de entrega: "
    f"{((o['order_status'] == 'delivered') & entregado_ts.isna()).sum()} -> dias_entrega/dias_retraso NULL, puntualidad 'Sin entrega'.")
log("dias_entrega = dias enteros (compra -> entrega al cliente); dias_retraso = dias (entrega real - estimada), redondeado hacia arriba; "
    "'A tiempo' se decide comparando timestamps (como en el Entregable 1).")

# ---------------------------------------------------------------------------
# 8. DIM_PAGO y DIM_ESTADO_PEDIDO (dimensiones pequenas por combinacion)
# ---------------------------------------------------------------------------
log("\n== 8. DIM_PAGO / DIM_ESTADO_PEDIDO ==")
sin_pago = pd.DataFrame({"tipo_pago_principal": ["sin_pago"], "rango_cuotas": ["sin_pago"], "es_pago_mixto": [0]})
combos_pago = pd.concat([pago[["tipo_pago_principal", "rango_cuotas", "es_pago_mixto"]], sin_pago]) \
    .drop_duplicates().sort_values(["tipo_pago_principal", "rango_cuotas", "es_pago_mixto"]).reset_index(drop=True)
combos_pago.insert(0, "sk_pago", np.arange(1, len(combos_pago) + 1))
dim_pago = combos_pago
log(f"DIM_PAGO: {len(dim_pago)} combinaciones (tipo principal x rango de cuotas x pago mixto) + 'sin_pago'.")

combos_est = o[["order_status", "puntualidad", "es_entregado", "es_cancelado"]].drop_duplicates() \
    .sort_values(["order_status", "puntualidad"]).reset_index(drop=True)
combos_est.insert(0, "sk_estado", np.arange(1, len(combos_est) + 1))
dim_estado = combos_est.rename(columns={"order_status": "estado_pedido"})
log(f"DIM_ESTADO_PEDIDO: {len(dim_estado)} combinaciones (estado x puntualidad).")

# ---------------------------------------------------------------------------
# 9. FACT_VENTAS (grano: un item de pedido)
# ---------------------------------------------------------------------------
log("\n== 9. FACT_VENTAS ==")
it = items.sort_values(["order_id", "order_item_id"]).copy()
it["valor_total_item"] = (it["price"] + it["freight_value"]).round(2)
it["cantidad_items"] = 1

# Pedidos SIN items: una fila "placeholder" para no perder cancelaciones
sin_items = o.loc[~o["order_id"].isin(it["order_id"]), "order_id"]
ph = pd.DataFrame({"order_id": sin_items, "order_item_id": 0, "product_id": "SIN_ITEM", "seller_id": "SIN_ITEM",
                   "price": 0.0, "freight_value": 0.0, "valor_total_item": 0.0, "cantidad_items": 0})
log(f"{len(sin_items)} pedidos sin items (603 unavailable, 164 canceled, etc.) -> 1 fila con producto/vendedor 'SIN_ITEM', "
    f"precio 0 y cantidad_items 0, para que cuenten en pedidos y % de cancelacion.")
f = pd.concat([it[["order_id", "order_item_id", "product_id", "seller_id", "price", "freight_value",
                   "valor_total_item", "cantidad_items"]], ph], ignore_index=True)
f = f.sort_values(["order_id", "order_item_id"]).reset_index(drop=True)
f["es_primer_item"] = (~f["order_id"].duplicated()).astype(int)

# Atributos del pedido
f = f.merge(o[["order_id", "customer_id", "order_status", "puntualidad", "order_purchase_timestamp",
               "dias_entrega", "dias_retraso"]], on="order_id", how="left")
f = f.merge(pago[["order_id", "payment_total", "cuotas", "tipo_pago_principal", "rango_cuotas", "es_pago_mixto"]],
            on="order_id", how="left")
f = f.merge(rv, on="order_id", how="left")

# Reparto de payment_value entre items, proporcional a (price + freight); suma exacta por pedido
tot_pedido = f.groupby("order_id")["valor_total_item"].transform("sum")
n_items_ped = f.groupby("order_id")["order_id"].transform("size")
prop = np.where(tot_pedido > 0, f["valor_total_item"] / tot_pedido.replace(0, np.nan), 1.0 / n_items_ped)
f["_prop"] = prop
f["_cum"] = f.groupby("order_id")["_prop"].cumsum()
pt = f["payment_total"].fillna(0)
acum = (pt * f["_cum"]).round(2)
prev = acum.groupby(f["order_id"]).shift(1).fillna(0)
f["payment_value"] = np.where(f["payment_total"].isna(), np.nan, (acum - prev).round(2))
# el ultimo item de cada pedido cierra exactamente al total
ultimo = ~f["order_id"].duplicated(keep="last")
f.loc[ultimo & f["payment_total"].notna(), "payment_value"] = (
    f.loc[ultimo & f["payment_total"].notna(), "payment_total"] - prev[ultimo & f["payment_total"].notna()]).round(2)
log("payment_value repartido entre los items del pedido de forma proporcional a (price+freight); "
    "la suma por pedido coincide con el total pagado.")

# Llaves foraneas
f["sk_tiempo"] = f["order_purchase_timestamp"].dt.strftime("%Y%m%d").astype(int)
f["sk_producto"] = f["product_id"].map(map_prod)
f["sk_vendedor"] = f["seller_id"].map(map_sell)
f["sk_cliente"] = f["customer_id"].map(map_cust_sk)
sin_pago_sk = int(dim_pago.loc[dim_pago["tipo_pago_principal"] == "sin_pago", "sk_pago"].iloc[0])
f["tipo_pago_principal"] = f["tipo_pago_principal"].fillna("sin_pago")
f["rango_cuotas"] = f["rango_cuotas"].fillna("sin_pago")
f["es_pago_mixto"] = f["es_pago_mixto"].fillna(0).astype(int)
f = f.merge(dim_pago, on=["tipo_pago_principal", "rango_cuotas", "es_pago_mixto"], how="left")
f = f.merge(dim_estado.rename(columns={"estado_pedido": "order_status"})[["sk_estado", "order_status", "puntualidad"]],
            on=["order_status", "puntualidad"], how="left")
f = f.rename(columns={"cuotas": "payment_installments"})

fact = f.sort_values(["order_id", "order_item_id"]).reset_index(drop=True)
fact.insert(0, "sk_venta", np.arange(1, len(fact) + 1))
fact = fact[["sk_venta", "order_id", "order_item_id", "sk_tiempo", "sk_producto", "sk_vendedor", "sk_cliente",
             "sk_pago", "sk_estado", "price", "freight_value", "valor_total_item", "payment_value",
             "payment_installments", "review_score", "dias_entrega", "dias_retraso",
             "cantidad_items", "es_primer_item"]]
for col in ["payment_installments", "review_score", "dias_entrega", "dias_retraso"]:
    fact[col] = fact[col].astype("Int64")
log(f"FACT_VENTAS: {len(fact):,} filas ({len(items):,} items + {len(sin_items)} pedidos sin items). "
    f"Pedidos distintos: {fact['order_id'].nunique():,}.")
claves_nulas = fact[["sk_tiempo", "sk_producto", "sk_vendedor", "sk_cliente", "sk_pago", "sk_estado"]].isna().sum()
assert claves_nulas.sum() == 0, f"Hay claves foraneas nulas: {claves_nulas.to_dict()}"
log("Verificacion: ninguna clave foranea nula en la tabla de hechos.")

# ---------------------------------------------------------------------------
# 10. Exportar
# ---------------------------------------------------------------------------
for nombre, df in [("dim_tiempo", dim_tiempo), ("dim_producto", dim_producto), ("dim_vendedor", dim_vendedor),
                   ("dim_cliente", dim_cliente), ("dim_pago", dim_pago), ("dim_estado_pedido", dim_estado),
                   ("fact_ventas", fact)]:
    df.to_csv(os.path.join(args.destino, f"{nombre}.csv"), index=False)
log("\n== 10. EXPORTADO ==")
for nombre in ["dim_tiempo", "dim_producto", "dim_vendedor", "dim_cliente", "dim_pago", "dim_estado_pedido", "fact_ventas"]:
    n = sum(1 for _ in open(os.path.join(args.destino, f"{nombre}.csv"), encoding="utf-8")) - 1
    log(f"{nombre}.csv: {n:,} filas")

with open(os.path.join(args.destino, "reporte_limpieza.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(LOG))
