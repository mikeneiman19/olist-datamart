import os
from datetime import date

import altair as alt
import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text

st.set_page_config(page_title="Dashboard Olist", page_icon="📦", layout="wide")

# ---------- Conexión a PostgreSQL (nunca se lee el CSV) ----------
DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "user": os.getenv("DB_USER", "bi_user"),
    "password": os.getenv("DB_PASSWORD", "bi_password"),
    "name": os.getenv("DB_NAME", "bi_database"),
}


@st.cache_resource
def get_engine():
    url = (f"postgresql+psycopg2://{DB['user']}:{DB['password']}"
           f"@{DB['host']}:{DB['port']}/{DB['name']}")
    return create_engine(url)


@st.cache_data(ttl=300)
def query(sql: str, params: dict | None = None) -> pd.DataFrame:
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn, params=params or {})



def grafico_barras(df, x, y, titulo_y, ordenar=True, angulo=-45):
    """Barras ordenadas de mayor a menor (o en el orden original) con etiquetas legibles."""
    ch = (alt.Chart(df)
          .mark_bar(color="#1f77b4", cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
          .encode(x=alt.X(x, sort="-y" if ordenar else None, title=None,
                          axis=alt.Axis(labelAngle=angulo, labelLimit=160)),
                  y=alt.Y(y, title=titulo_y),
                  tooltip=[x, y])
          .properties(height=320))
    st.altair_chart(ch, use_container_width=True)


# ---------- Filtros (barra lateral) ----------
st.sidebar.title("📦 Olist BI")
pagina = st.sidebar.radio("Sección", ["Ventas", "Entregas y satisfacción"])
st.sidebar.header("Filtros")

rango = query("SELECT MIN(fecha) AS ini, MAX(fecha) AS fin FROM vw_ventas_app")
f_min, f_max = rango.loc[0, "ini"], rango.loc[0, "fin"]
fechas = st.sidebar.date_input("Rango de fechas de compra", value=(f_min, f_max),
                               min_value=f_min, max_value=f_max)
if len(fechas) != 2:
    st.warning("Selecciona fecha inicial y final.")
    st.stop()
ini, fin = fechas

estados = query("SELECT DISTINCT estado_cliente FROM vw_ventas_app "
                "WHERE estado_cliente IS NOT NULL ORDER BY 1")["estado_cliente"].tolist()
sel_estado = st.sidebar.selectbox("Estado del cliente", ["Todos"] + estados)

cats = query("SELECT DISTINCT categoria FROM vw_ventas_app "
             "WHERE categoria IS NOT NULL ORDER BY 1")["categoria"].tolist()
sel_cat = st.sidebar.selectbox("Categoría de producto", ["Todas"] + cats)

P = {
    "ini": ini,
    "fin": fin,
    "est": None if sel_estado == "Todos" else sel_estado,
    "cat": None if sel_cat == "Todas" else sel_cat,
}
# Mismo filtro para consultas directas sobre la vista
WHERE = """fecha BETWEEN :ini AND :fin
           AND (CAST(:est AS text) IS NULL OR estado_cliente = CAST(:est AS text))
           AND (CAST(:cat AS text) IS NULL OR categoria = CAST(:cat AS text))"""

kpi = query("SELECT * FROM fn_kpis_filtrado(CAST(:ini AS date), CAST(:fin AS date), "
            "CAST(:est AS text), CAST(:cat AS text))", P).iloc[0]


def num(v, fmt="{:,.2f}", suf=""):
    return "N/D" if pd.isna(v) else fmt.format(v) + suf


# =====================================================================
if pagina == "Ventas":
    st.title("Ventas e ingresos")
    st.caption("P1: ¿Qué categorías y estados generan más ingresos y cómo evolucionan las ventas por mes?")

    c1, c2, c3 = st.columns(3)
    c1.metric("Ingresos totales (R$)", num(kpi["ingresos_totales"]))
    c2.metric("Total de pedidos", num(kpi["total_pedidos"], "{:,.0f}"))
    c3.metric("Ticket promedio (R$)", num(kpi["ticket_promedio"]))

    left, right = st.columns(2)
    with left:
        st.subheader("Evolución mensual de ingresos")
        m = query("SELECT * FROM fn_ingresos_mensuales(CAST(:ini AS date), CAST(:fin AS date), "
                  "CAST(:est AS text), CAST(:cat AS text))", P)
        if m.empty:
            st.info("Sin datos para los filtros seleccionados.")
        else:
            st.line_chart(m.set_index("anio_mes")["ingresos"])
    with right:
        st.subheader("Top 10 categorías por ingresos")
        c = query(f"""SELECT categoria, ROUND(SUM(price),2) AS ingresos
                      FROM vw_ventas_app
                      WHERE es_cancelado = 0 AND cantidad_items > 0 AND {WHERE}
                      GROUP BY categoria ORDER BY ingresos DESC LIMIT 10""", P)
        if c.empty:
            st.info("Sin datos para los filtros seleccionados.")
        else:
            grafico_barras(c, "categoria", "ingresos", "Ingresos (R$)")

    st.subheader("Detalle: Top 20 vendedores por ingresos")
    d = query(f"""SELECT seller_id AS vendedor, estado_vendedor AS estado,
                         COUNT(DISTINCT order_id) AS pedidos,
                         ROUND(SUM(price),2) AS ingresos,
                         ROUND(AVG(review_score),2) AS puntaje_prom
                  FROM vw_ventas_app
                  WHERE es_cancelado = 0 AND cantidad_items > 0 AND {WHERE}
                  GROUP BY seller_id, estado_vendedor
                  ORDER BY ingresos DESC LIMIT 20""", P)
    st.dataframe(
        d, use_container_width=True, hide_index=True,
        height=35 * (len(d) + 1) + 3,
        column_config={
            "vendedor": st.column_config.TextColumn("Vendedor (ID)"),
            "estado": st.column_config.TextColumn("Estado"),
            "pedidos": st.column_config.NumberColumn("Pedidos", format="%d"),
            "ingresos": st.column_config.NumberColumn("Ingresos (R$)", format="%.2f"),
            "puntaje_prom": st.column_config.NumberColumn("Puntaje prom.", format="%.2f"),
        })

# =====================================================================
else:
    st.title("Entregas y satisfacción")
    st.caption("P2: ¿Qué tan bien se cumplen los plazos? P3: ¿Cómo se relaciona el retraso con la satisfacción?")

    c1, c2, c3 = st.columns(3)
    c1.metric("% entregas a tiempo", num(kpi["pct_entregas_a_tiempo"], suf=" %"))
    c2.metric("Tiempo prom. de entrega", num(kpi["tiempo_prom_entrega_dias"], suf=" días"))
    c3.metric("Puntaje promedio de reseña", num(kpi["puntaje_prom_resena"], suf=" / 5"))

    left, right = st.columns(2)
    with left:
        st.subheader("Puntaje de reseña según retraso")
        r = query(f"""SELECT CASE WHEN dias_retraso <= 0 THEN '1. A tiempo'
                                  WHEN dias_retraso <= 7 THEN '2. 1-7 días tarde'
                                  ELSE '3. Más de 7 días tarde' END AS grupo,
                             ROUND(AVG(review_score),2) AS puntaje_prom
                      FROM vw_ventas_app
                      WHERE es_primer_item = 1 AND es_entregado = 1
                        AND dias_retraso IS NOT NULL AND review_score IS NOT NULL AND {WHERE}
                      GROUP BY 1 ORDER BY 1""", P)
        if r.empty:
            st.info("Sin datos para los filtros seleccionados.")
        else:
            grafico_barras(r, "grupo", "puntaje_prom", "Puntaje promedio (1-5)", ordenar=False, angulo=0)
    with right:
        st.subheader("Días promedio de entrega por estado (Top 10 con más pedidos)")
        e = query(f"""SELECT estado_cliente AS estado,
                             ROUND(AVG(dias_entrega),1) AS dias_prom
                      FROM vw_ventas_app
                      WHERE es_primer_item = 1 AND es_entregado = 1
                        AND dias_entrega IS NOT NULL AND {WHERE}
                      GROUP BY estado_cliente
                      ORDER BY COUNT(*) DESC LIMIT 10""", P)
        if e.empty:
            st.info("Sin datos para los filtros seleccionados.")
        else:
            grafico_barras(e, "estado", "dias_prom", "Días promedio", angulo=0)

    st.subheader("Detalle: 100 pedidos con mayor retraso")
    t = query(f"""SELECT order_id AS pedido, fecha AS fecha_compra, estado_cliente AS estado,
                         categoria, dias_entrega, dias_retraso, review_score AS puntaje
                  FROM vw_ventas_app
                  WHERE es_primer_item = 1 AND es_entregado = 1
                    AND dias_retraso IS NOT NULL AND {WHERE}
                  ORDER BY dias_retraso DESC LIMIT 100""", P)
    st.dataframe(
        t, use_container_width=True, hide_index=True, height=420,
        column_config={
            "pedido": st.column_config.TextColumn("Pedido (ID)"),
            "fecha_compra": st.column_config.DateColumn("Fecha de compra"),
            "estado": st.column_config.TextColumn("Estado"),
            "categoria": st.column_config.TextColumn("Categoría"),
            "dias_entrega": st.column_config.NumberColumn("Días de entrega", format="%d"),
            "dias_retraso": st.column_config.NumberColumn("Días de retraso", format="%d"),
            "puntaje": st.column_config.NumberColumn("Puntaje", format="%d"),
        })

st.sidebar.caption("Datos: PostgreSQL (bi_database) · Olist 2016-2018")
