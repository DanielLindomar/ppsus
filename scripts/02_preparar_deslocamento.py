# -*- coding: utf-8 -*-
"""
02_preparar_deslocamento.py — Observatório PPSUS-MT
Análise de deslocamento residência × atendimento (internações SIH, 2020–2025).

Lê (somente leitura) trusted.aih_reduzida e mart.dim_municipio no PostgreSQL local
e grava, conforme o contrato do briefing (_planejamento/BRIEF_SITE.md, seção 3):

  dados_site/centroides.csv               (cod_mun6, lon, lat) — sedes municipais; criado se não existir
  dados_site/fluxo_mun_ano.csv            fluxos município de residência → município do estabelecimento
  dados_site/fluxo_regiao_ano.csv         fluxos região de saúde → região de saúde
  dados_site/deslocamento_mun_ano.csv     indicadores por município (como residência e como atendente)
  dados_site/polos_ano.csv                municípios de atendimento (polos)
  dados_site/resumo_deslocamento_ano.csv  resumo estadual por ano e nível
  dados_site/deslocamento_achados.md      achados quantificados (pt-BR)
  arquivos/dados/fluxos_internacoes_municipios.csv  cópia com nomes (download)
  arquivos/dados/fluxos_internacoes_regioes.csv     cópia com nomes (download)

Internações de residentes de MT em OUTRAS UF (versão 0.3 do site), lidas de
mart.fluxo_internacao_od_ano (matriz origem-destino: SIH/SUS RD de MT + RD das 26 outras UF,
filtrado a residentes de MT):

  dados_site/fuga_resumo_ano.csv          estado: por ano e nível, em MT × em outras UF, valor, eletivas, saldo
  dados_site/fuga_uf_ano.csv              estado: por ano, UF de destino e nível (MC, AC, total)
  dados_site/fuga_saldo_uf_ano.csv        estado: por ano e UF, entrada (residentes da UF em MT) × saída × saldo
  dados_site/fuga_regiao_ano.csv          região de saúde de residência × ano (com supressão de células < 5)
  dados_site/fuga_mun_periodo.csv         município de residência, 2020–2025 somado (com supressão de células < 5)
  dados_site/fuga_destinos_mun.csv        20 principais municípios de destino fora de MT, 2020–2025 (supressão < 5)

Regras:
  - tipo_aih = '1' (uma linha por internação); ano = ano de data_saida; 2020–2025.
  - nivel: complexidade '02' = MC, '03' = AC, demais = 'outro'.
  - Residência '510000' (ignorada) e prefixo ≠ '51' (outra UF) NÃO entram nos fluxos;
    são contadas em resumo_deslocamento_ano.csv (n_res_ignorada, n_outra_uf).
  - Distância = haversine (linha reta) entre as SEDES municipais (IBGE, Localidades
    do Brasil 2022), lidas de dados_site/centroides.csv (contrato; gerado pelo script 01
    a partir de sedes_municipais.csv, script 00); não é distância rodoviária.
    0 no próprio município. Todos os 142 municípios têm coordenada, inclusive Boa
    Esperança do Norte (510183): o km_medio fica vazio apenas quando o município não
    tem internação de residentes no ano, não por falta de coordenada.
  - Fluxos, polos, matriz e distâncias usam só o SIH de MT (internações em hospitais de MT).
    As internações de residentes de MT em hospitais de outras UF entram apenas nos arquivos
    fuga_*.csv, com as regras do mart (internação = AIH tipo 1 distinta; valores e diárias em
    todas as linhas da AIH, inclusive continuações; ano de data_saida). O script confere que,
    com destino em MT, o mart reproduz exatamente as internações dos fluxos (por ano e nível).
  - Supressão (Termo de Uso do pacote de dados da equipe, item 6: "suprimindo células com menos
    de 5 casos"): nos recortes SUBESTADUAIS (região de saúde, município de residência, município de
    destino) contagens de 1 a 4 não são publicadas. Zero é publicado (não singulariza ninguém).
    Supressão complementar: a célula suprimida não pode ser deduzida por diferença — total e
    percentual da linha também saem; por ano (região) e por região (município) nunca fica uma só
    célula suprimida diante de um total publicado. Os recortes estaduais (MT × UF de destino,
    saldo por UF) não têm supressão, como os demais arquivos estaduais do site.
  - Janela 2020–2025; 2026 é parcial e não entra.

Uso (a partir da raiz do repositório):  python scripts/02_preparar_deslocamento.py
"""
from __future__ import annotations

import json
import math
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg2

warnings.filterwarnings("ignore", category=UserWarning)

ROOT = Path(__file__).resolve().parents[1]
DADOS = ROOT / "dados_site"
ARQ_DADOS = ROOT / "arquivos" / "dados"
GEOJSON = ROOT / "arquivos" / "geo" / "mt_municipios_ibge_minima.geojson"
SEDES = DADOS / "sedes_municipais.csv"   # script 00 (IBGE, Localidades 2022)
from config_local import caminho  # noqa: E402  (caminhos locais fora do repositório)
PGPASS = caminho("PPSUS_PGPASS")

ANO_INI, ANO_FIM = 2020, 2025
NIVEIS = ["MC", "AC", "outro"]
UF_MT = "51"
COD_IGNORADO = "510000"
PRIMEIRO_ANO_FIXO = {"510183": 2025}   # Boa Esperança do Norte: município instalado em 2025
CSV_KW = dict(index=False, encoding="utf-8", lineterminator="\n", na_rep="")
# Código IBGE da UF (2 dígitos) → (sigla, nome)
UF_SIGLA = {
    "11": ("RO", "Rondônia"), "12": ("AC", "Acre"), "13": ("AM", "Amazonas"), "14": ("RR", "Roraima"),
    "15": ("PA", "Pará"), "16": ("AP", "Amapá"), "17": ("TO", "Tocantins"), "21": ("MA", "Maranhão"),
    "22": ("PI", "Piauí"), "23": ("CE", "Ceará"), "24": ("RN", "Rio Grande do Norte"), "25": ("PB", "Paraíba"),
    "26": ("PE", "Pernambuco"), "27": ("AL", "Alagoas"), "28": ("SE", "Sergipe"), "29": ("BA", "Bahia"),
    "31": ("MG", "Minas Gerais"), "32": ("ES", "Espírito Santo"), "33": ("RJ", "Rio de Janeiro"),
    "35": ("SP", "São Paulo"), "41": ("PR", "Paraná"), "42": ("SC", "Santa Catarina"),
    "43": ("RS", "Rio Grande do Sul"), "50": ("MS", "Mato Grosso do Sul"), "51": ("MT", "Mato Grosso"),
    "52": ("GO", "Goiás"), "53": ("DF", "Distrito Federal"),
}
SIGLA_NOME = {s: n for s, n in UF_SIGLA.values()}
# Internações em outras UF (versão 0.3)
LIMIAR_SUPRESSAO = 5     # Termo de Uso do pacote, item 6: células com menos de 5 casos (1 a 4) não são publicadas
N_DESTINOS = 20          # principais municípios de destino fora de MT, 2020–2025
NIVEIS_FUGA = ["MC", "AC", "total"]


# ----------------------------------------------------------------------------
# utilidades
# ----------------------------------------------------------------------------
def log(msg: str) -> None:
    try:
        print(msg, flush=True)
    except UnicodeEncodeError:  # console em cp1252 (Windows): troca o que não couber
        enc = sys.stdout.encoding or "ascii"
        print(msg.encode(enc, errors="replace").decode(enc), flush=True)


def fmt_int(x) -> str:
    """1234567 -> '1.234.567' (pt-BR)."""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    return f"{int(round(x)):,}".replace(",", ".")


def fmt_dec(x, nd: int = 1) -> str:
    """12.345 -> '12,3' (pt-BR)."""
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    s = f"{x:,.{nd}f}"
    return s.replace(",", "X").replace(".", ",").replace("X", ".")


def fmt_pct(x, nd: int = 1) -> str:
    return fmt_dec(x, nd) + "%"


def fmt_saldo(v: int) -> str:
    """Saldo com sinal: +1.234 / −1.234 / 0 (pt-BR)."""
    return ("+" if v > 0 else "−" if v < 0 else "") + fmt_int(abs(v))


def haversine_km(lon1, lat1, lon2, lat2):
    """Distância em km (vetorizado) entre pares (lon, lat) em graus."""
    r = 6371.0088
    lon1, lat1, lon2, lat2 = map(np.radians, (lon1, lat1, lon2, lat2))
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = np.sin(dlat / 2) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))


def _anel_shoelace(ring: list[list[float]], cos_lat: float):
    """Centro geométrico (shoelace) e área de um anel, em espaço localmente escalado (só fallback)."""
    xs = np.array([p[0] * cos_lat for p in ring])
    ys = np.array([p[1] for p in ring])
    x2, y2 = np.roll(xs, -1), np.roll(ys, -1)
    cross = xs * y2 - x2 * ys
    area = cross.sum() / 2.0
    if abs(area) < 1e-12:
        return xs.mean(), ys.mean(), 0.0
    cx = ((xs + x2) * cross).sum() / (6 * area)
    cy = ((ys + y2) * cross).sum() / (6 * area)
    return cx, cy, abs(area)


def centro_geometrico_feicao(geom: dict) -> tuple[float, float]:
    """Centro geométrico ponderado pela área dos anéis externos (Polygon/MultiPolygon) — só fallback."""
    polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
    all_lat = [p[1] for poly in polys for p in poly[0]]
    cos_lat = math.cos(math.radians(sum(all_lat) / len(all_lat)))
    sx = sy = sa = 0.0
    for poly in polys:
        cx, cy, a = _anel_shoelace(poly[0], cos_lat)
        sx += cx * a
        sy += cy * a
        sa += a
    if sa == 0:
        return float("nan"), float("nan")
    return (sx / sa) / cos_lat, sy / sa


def carregar_centroides() -> pd.DataFrame:
    """Coordenadas (cod_mun6, lon, lat) usadas nas distâncias: dados_site/centroides.csv
    (contrato; = sedes municipais do IBGE quando gerado pelo script 01). Se não existir,
    usa sedes_municipais.csv (script 00) e grava; só sem os dois cai no centro geométrico
    da malha (com aviso)."""
    arq = DADOS / "centroides.csv"
    if arq.exists():
        c = pd.read_csv(arq, dtype={"cod_mun6": str})
        c["cod_mun6"] = c["cod_mun6"].str.zfill(6)
        log(f"centroides.csv existente reutilizado ({len(c)} linhas; sedes municipais IBGE quando gerado pelo script 01)")
        return c[["cod_mun6", "lon", "lat"]]
    if SEDES.exists():
        c = pd.read_csv(SEDES, dtype={"cod_mun6": str})
        c["cod_mun6"] = c["cod_mun6"].str.zfill(6)
        c = c[["cod_mun6", "lon", "lat"]].sort_values("cod_mun6").reset_index(drop=True)
        c.to_csv(arq, **CSV_KW)
        log(f"centroides.csv gravado a partir de sedes_municipais.csv ({len(c)} sedes municipais)")
        return c
    log("AVISO: nem centroides.csv nem sedes_municipais.csv existem (rode scripts/00_sedes_ibge.py); "
        "usando o centro geométrico dos polígonos da malha, que superestima distâncias em municípios extensos")
    g = json.loads(GEOJSON.read_text(encoding="utf-8"))
    rows = []
    for ft in g["features"]:
        cod7 = str(ft["properties"]["codarea"])
        lon, lat = centro_geometrico_feicao(ft["geometry"])
        rows.append({"cod_mun6": cod7[:6], "lon": round(lon, 5), "lat": round(lat, 5)})
    c = pd.DataFrame(rows).sort_values("cod_mun6").reset_index(drop=True)
    c.to_csv(arq, **CSV_KW)
    log(f"centroides.csv calculado da malha e gravado ({len(c)} linhas)")
    return c


# ----------------------------------------------------------------------------
# extração
# ----------------------------------------------------------------------------
SQL_FLUXO = f"""
select extract(year from data_saida)::int                     as ano,
       codigo_municipio_residencia_paciente                   as cod_res,
       codigo_municipio_estabelecimento                       as cod_estab,
       case complexidade when '02' then 'MC'
                         when '03' then 'AC' else 'outro' end as nivel,
       count(*)::bigint                                       as internacoes,
       sum(coalesce(dias_permanencia, 0))::bigint             as diarias,
       sum(coalesce(valor_total_aih, 0))::numeric             as valor_total,
       sum(case when indicador_obito = 1 then 1 else 0 end)::bigint as obitos,
       sum(case when carater_internacao = '01' then 1 else 0 end)::bigint as eletivas
from   trusted.aih_reduzida
where  tipo_aih = '1'
  and  data_saida >= date '{ANO_INI}-01-01'
  and  data_saida <  date '{ANO_FIM + 1}-01-01'
group by 1, 2, 3, 4
"""

SQL_DIM = """
select cod_mun6::text as cod_mun6, nome_municipio, co_regsaud::text as co_regsaud,
       nome_regsaud, co_macsaud::text as co_macsaud, nome_macsaud
from   mart.dim_municipio
order  by cod_mun6
"""


# Matriz origem-destino do mart (residentes de MT; destino em MT ou em outra UF)
SQL_OD = f"""
select ano, cod_mun6_res, co_regsaud_res, cod_mun6_destino, municipio_destino,
       cod_uf_destino, uf_destino, tipo_destino, nivel,
       internacoes, internacoes_urgencia, diarias, valor_total
from   mart.fluxo_internacao_od_ano
where  ano between {ANO_INI} and {ANO_FIM}
"""

# Conferência independente: AIH tipo 1 distintas de residentes de MT nos RD das outras UF
SQL_FORA_CONF = f"""
select extract(year from t.data_saida)::int as ano, count(distinct t.numero_aih)::bigint as internacoes
from   trusted.aih_reduzida_fora_mt t
join   mart.dim_municipio d on d.cod_mun6 = left(t.codigo_municipio_residencia_paciente, 6)
where  t.tipo_aih = '1'
  and  t.data_saida >= date '{ANO_INI}-01-01'
  and  t.data_saida <  date '{ANO_FIM + 1}-01-01'
group by 1
"""


def ler_sql(con, sql: str) -> pd.DataFrame:
    with con.cursor() as cur:
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)


def extrair() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    pw = PGPASS.read_text(encoding="utf-8").strip()
    con = psycopg2.connect(host="localhost", port=5432, dbname="airflow",
                           user="airflow", password=pw)
    try:
        con.set_session(readonly=True, autocommit=True)
        dim = ler_sql(con, SQL_DIM)
        log("consultando trusted.aih_reduzida (agregação) ...")
        fl = ler_sql(con, SQL_FLUXO)
        log("consultando mart.fluxo_internacao_od_ano (residentes de MT em MT e em outras UF) ...")
        od = ler_sql(con, SQL_OD)
        conf = ler_sql(con, SQL_FORA_CONF)
    finally:
        con.close()
    dim["cod_mun6"] = dim["cod_mun6"].str.zfill(6)
    for c in ("cod_res", "cod_estab"):
        fl[c] = fl[c].fillna("").astype(str).str.strip()
    fl["valor_total"] = fl["valor_total"].astype(float)
    for c in ("internacoes", "diarias", "obitos", "eletivas"):
        fl[c] = fl[c].astype("int64")
    for c in ("cod_mun6_res", "co_regsaud_res", "cod_mun6_destino", "cod_uf_destino"):
        od[c] = od[c].fillna("").astype(str).str.strip()
    od["nivel"] = od["nivel"].replace({"outra": "outro"})
    od["valor_total"] = od["valor_total"].astype(float)
    for c in ("ano", "internacoes", "internacoes_urgencia", "diarias"):
        od[c] = od[c].astype("int64")
    conf = conf.astype("int64")
    log(f"dim_municipio: {len(dim)} municípios; agregados AIH: {len(fl)} linhas, "
        f"{fl['internacoes'].sum():,} internações; matriz origem-destino: {len(od)} linhas, "
        f"{int(od.loc[od['tipo_destino'] == 'outra_uf', 'internacoes'].sum()):,} internações em outras UF")
    return fl, dim, od, conf


# ----------------------------------------------------------------------------
# processamento
# ----------------------------------------------------------------------------
def classificar_residencia(fl: pd.DataFrame, cods_mt: set[str]) -> pd.DataFrame:
    res = fl["cod_res"]
    cond_ign = (res == "") | (res == COD_IGNORADO) | (res.str.len() < 6)
    cond_uf = (~cond_ign) & (res.str[:2] != UF_MT)
    cond_mt_desc = (~cond_ign) & (~cond_uf) & (~res.isin(cods_mt))
    fl = fl.copy()
    fl["classe_res"] = np.select(
        [cond_ign, cond_uf, cond_mt_desc], ["ignorada", "outra_uf", "mt_desconhecido"], "mt")
    return fl


def main() -> int:
    DADOS.mkdir(parents=True, exist_ok=True)
    ARQ_DADOS.mkdir(parents=True, exist_ok=True)

    fl, dim, od, conf = extrair()
    cent = carregar_centroides()
    cods_mt = set(dim["cod_mun6"])
    nome = dim.set_index("cod_mun6")["nome_municipio"]
    reg = dim.set_index("cod_mun6")["co_regsaud"]
    nome_reg = dim.drop_duplicates("co_regsaud").set_index("co_regsaud")["nome_regsaud"]
    sem_coord = sorted(cods_mt - set(cent["cod_mun6"]))
    log(f"municípios sem coordenada da sede (km vazio): {sem_coord or 'nenhum'}")

    fl = classificar_residencia(fl, cods_mt)
    # destino deve ser município de MT conhecido
    dest_desc = fl.loc[~fl["cod_estab"].isin(cods_mt), "cod_estab"].unique()
    if len(dest_desc):
        log(f"AVISO: estabelecimentos com município desconhecido (excluídos): {list(dest_desc)}")
        fl = fl[fl["cod_estab"].isin(cods_mt)]
    n_mt_desc = int(fl.loc[fl["classe_res"] == "mt_desconhecido", "internacoes"].sum())
    if n_mt_desc:
        log(f"AVISO: {n_mt_desc} internações com residência MT fora de dim_municipio "
            f"(tratadas como residência ignorada)")
        fl.loc[fl["classe_res"] == "mt_desconhecido", "classe_res"] = "ignorada"

    # --- fluxos de residentes de MT --------------------------------------------
    mt = fl[fl["classe_res"] == "mt"].copy()
    mt = mt.rename(columns={"cod_res": "cod_origem", "cod_estab": "cod_destino"})
    mt["reg_origem"] = mt["cod_origem"].map(reg)
    mt["reg_destino"] = mt["cod_destino"].map(reg)
    mt = mt.merge(cent.rename(columns={"cod_mun6": "cod_origem", "lon": "lon_o", "lat": "lat_o"}),
                  on="cod_origem", how="left")
    mt = mt.merge(cent.rename(columns={"cod_mun6": "cod_destino", "lon": "lon_d", "lat": "lat_d"}),
                  on="cod_destino", how="left")
    mt["km"] = haversine_km(mt["lon_o"], mt["lat_o"], mt["lon_d"], mt["lat_d"])
    mt.loc[mt["cod_origem"] == mt["cod_destino"], "km"] = 0.0
    mt["km"] = mt["km"].round(1)
    mt["tipo"] = np.select(
        [mt["cod_origem"] == mt["cod_destino"], mt["reg_origem"] == mt["reg_destino"]],
        ["proprio", "mesma_regiao"], "outra_regiao")

    # 1) fluxo_mun_ano.csv
    fluxo_mun = (mt.groupby(["ano", "cod_origem", "cod_destino", "nivel"], as_index=False)
                   [["internacoes", "diarias", "valor_total", "obitos"]].sum()
                   .sort_values(["ano", "cod_origem", "cod_destino", "nivel"]))
    fluxo_mun["valor_total"] = fluxo_mun["valor_total"].round(2)
    fluxo_mun.to_csv(DADOS / "fluxo_mun_ano.csv", **CSV_KW)

    # 2) fluxo_regiao_ano.csv
    fluxo_reg = (mt.groupby(["ano", "reg_origem", "reg_destino", "nivel"], as_index=False)
                   ["internacoes"].sum()
                   .rename(columns={"reg_origem": "co_reg_origem", "reg_destino": "co_reg_destino"})
                   .sort_values(["ano", "co_reg_origem", "co_reg_destino", "nivel"]))
    fluxo_reg.to_csv(DADOS / "fluxo_regiao_ano.csv", **CSV_KW)

    # --- métricas por município de residência -------------------------------------
    def agg_residencia(df: pd.DataFrame) -> pd.DataFrame:
        g = df.groupby(["cod_origem", "ano"])
        out = g["internacoes"].sum().rename("internacoes_res").to_frame()
        piv = (df.pivot_table(index=["cod_origem", "ano"], columns="tipo",
                              values="internacoes", aggfunc="sum", fill_value=0)
                 .reindex(columns=["proprio", "mesma_regiao", "outra_regiao"], fill_value=0))
        out["no_proprio_mun"] = piv["proprio"]
        out["mesma_regiao"] = piv["mesma_regiao"]
        out["outra_regiao"] = piv["outra_regiao"]
        # km médio ponderado (apenas fluxos com distância conhecida)
        ok = df[df["km"].notna()]
        wk = ok.assign(w=ok["internacoes"] * ok["km"]).groupby(["cod_origem", "ano"])
        out["km_medio_internacao"] = (wk["w"].sum() / wk["internacoes"].sum()).round(1)
        # destino principal
        dest = (df.groupby(["cod_origem", "ano", "cod_destino"], as_index=False)["internacoes"].sum()
                  .sort_values(["cod_origem", "ano", "internacoes", "cod_destino"],
                               ascending=[True, True, False, True]))
        # nº de municípios de destino FORA do município de residência (o próprio não conta)
        out["n_destinos"] = (dest[dest["cod_destino"] != dest["cod_origem"]]
                             .groupby(["cod_origem", "ano"])["cod_destino"].nunique()
                             .reindex(out.index, fill_value=0))
        top = dest.drop_duplicates(["cod_origem", "ano"]).set_index(["cod_origem", "ano"])
        out["destino_principal_cod"] = top["cod_destino"]
        out["destino_principal_nome"] = top["cod_destino"].map(nome)
        out["pct_destino_principal"] = (100 * top["internacoes"] / out["internacoes_res"]).round(1)
        return out

    res = agg_residencia(mt)
    res["pct_proprio_mun"] = (100 * res["no_proprio_mun"] / res["internacoes_res"]).round(1)
    res["pct_mesma_regiao"] = (100 * res["mesma_regiao"] / res["internacoes_res"]).round(1)
    res["pct_outra_regiao"] = (100 * res["outra_regiao"] / res["internacoes_res"]).round(1)
    res["pct_internacoes_fora_mun"] = (100 * (res["internacoes_res"] - res["no_proprio_mun"])
                                       / res["internacoes_res"]).round(1)
    res["pct_internacoes_fora_regiao"] = res["pct_outra_regiao"]

    ac = mt[mt["nivel"] == "AC"]
    ac_g = ac.groupby(["cod_origem", "ano"])
    ac_res = ac_g["internacoes"].sum().rename("internacoes_ac_res").to_frame()
    ac_res["pct_ac_fora_mun"] = (100 * ac[ac["tipo"] != "proprio"].groupby(["cod_origem", "ano"])
                                 ["internacoes"].sum().reindex(ac_res.index, fill_value=0)
                                 / ac_res["internacoes_ac_res"]).round(1)
    res = res.join(ac_res, how="left")
    res["internacoes_ac_res"] = res["internacoes_ac_res"].fillna(0).astype("int64")

    # --- métricas por município de atendimento (polos) ------------------------------
    at = mt.groupby(["cod_destino", "ano"])
    pol = at["internacoes"].sum().rename("internacoes_recebidas").to_frame()
    pol["recebidas_de_fora"] = (mt[mt["tipo"] != "proprio"].groupby(["cod_destino", "ano"])
                                ["internacoes"].sum().reindex(pol.index, fill_value=0))
    pol["pct_recebidas_de_fora"] = (100 * pol["recebidas_de_fora"] / pol["internacoes_recebidas"]).round(1)
    # nº de municípios de origem FORA do município do hospital (o próprio não conta)
    pol["n_origens"] = (mt[mt["tipo"] != "proprio"].groupby(["cod_destino", "ano"])["cod_origem"].nunique()
                        .reindex(pol.index, fill_value=0))
    orig = (mt[mt["tipo"] != "proprio"]
              .groupby(["cod_destino", "ano", "cod_origem"], as_index=False)["internacoes"].sum()
              .sort_values(["cod_destino", "ano", "internacoes", "cod_origem"],
                           ascending=[True, True, False, True])
              .drop_duplicates(["cod_destino", "ano"]).set_index(["cod_destino", "ano"]))
    pol["origem_principal_nome"] = orig["cod_origem"].map(nome)
    pol["pct_origem_principal"] = (100 * orig["internacoes"] / pol["recebidas_de_fora"]).round(1)
    pol["internacoes_ac_recebidas"] = (ac.groupby(["cod_destino", "ano"])["internacoes"].sum()
                                       .reindex(pol.index, fill_value=0))
    pol.index = pol.index.set_names(["cod_mun6", "ano"])
    res.index = res.index.set_names(["cod_mun6", "ano"])

    # grade município × ano: cada município entra a partir do primeiro ano em que
    # aparece no SIH (residência ou atendimento); Boa Esperança do Norte (510183,
    # instalado em 2025) entra só em 2025 mesmo sem AIH com o novo código.
    anos = list(range(ANO_INI, ANO_FIM + 1))
    primeiro_ano = pd.concat([mt.groupby("cod_origem")["ano"].min(),
                              mt.groupby("cod_destino")["ano"].min()]).groupby(level=0).min()
    primeiro_ano = {c: int(primeiro_ano.get(c, ANO_INI)) for c in cods_mt}
    primeiro_ano.update(PRIMEIRO_ANO_FIXO)
    grade = [(c, a) for c in sorted(cods_mt) for a in anos if a >= primeiro_ano[c]]
    idx = pd.MultiIndex.from_tuples(grade, names=["cod_mun6", "ano"])

    des = pd.DataFrame(index=idx).join(res, how="left").join(pol, how="left")
    for c in ("internacoes_res", "no_proprio_mun", "mesma_regiao", "outra_regiao",
              "internacoes_recebidas", "recebidas_de_fora", "n_origens", "n_destinos",
              "internacoes_ac_res"):
        des[c] = des[c].fillna(0).astype("int64")
    des = des.reset_index()
    cols_des = ["cod_mun6", "ano", "internacoes_res", "no_proprio_mun", "mesma_regiao", "outra_regiao",
                "pct_proprio_mun", "pct_mesma_regiao", "pct_outra_regiao",
                "pct_internacoes_fora_mun", "pct_internacoes_fora_regiao", "km_medio_internacao",
                "destino_principal_cod", "destino_principal_nome", "pct_destino_principal", "n_destinos",
                "internacoes_recebidas", "recebidas_de_fora", "pct_recebidas_de_fora", "n_origens",
                "origem_principal_nome", "pct_origem_principal",
                "internacoes_ac_res", "pct_ac_fora_mun"]
    des = des[cols_des].sort_values(["cod_mun6", "ano"])
    des.to_csv(DADOS / "deslocamento_mun_ano.csv", **CSV_KW)

    # 4) polos_ano.csv
    polos = pol.reset_index()
    polos["municipio"] = polos["cod_mun6"].map(nome)
    polos = polos.merge(res.reset_index()[["cod_mun6", "ano", "internacoes_res"]],
                        on=["cod_mun6", "ano"], how="left")
    polos["saldo"] = polos["internacoes_recebidas"] - polos["internacoes_res"].fillna(0).astype("int64")
    polos = polos[["cod_mun6", "municipio", "ano", "internacoes_recebidas", "recebidas_de_fora",
                   "pct_recebidas_de_fora", "n_origens", "saldo", "internacoes_ac_recebidas"]]
    polos = polos.sort_values(["ano", "internacoes_recebidas"], ascending=[True, False])
    polos.to_csv(DADOS / "polos_ano.csv", **CSV_KW)

    # 5) resumo_deslocamento_ano.csv
    def resumo_nivel(df_mt: pd.DataFrame, df_all: pd.DataFrame, rotulo: str) -> pd.DataFrame:
        g = df_mt.groupby("ano")
        r = g["internacoes"].sum().rename("internacoes").to_frame()
        for t, col in (("proprio", "pct_proprio_mun"), ("mesma_regiao", "pct_mesma_regiao"),
                       ("outra_regiao", "pct_outra_regiao")):
            r[col] = (100 * df_mt[df_mt["tipo"] == t].groupby("ano")["internacoes"].sum()
                      .reindex(r.index, fill_value=0) / r["internacoes"]).round(1)
        ok = df_mt[df_mt["km"].notna()]
        r["km_medio"] = ((ok["internacoes"] * ok["km"]).groupby(ok["ano"]).sum()
                         / ok.groupby("ano")["internacoes"].sum()).round(1)
        r["n_res_ignorada"] = (df_all[df_all["classe_res"] == "ignorada"].groupby("ano")["internacoes"]
                               .sum().reindex(r.index, fill_value=0).astype("int64"))
        r["n_outra_uf"] = (df_all[df_all["classe_res"] == "outra_uf"].groupby("ano")["internacoes"]
                           .sum().reindex(r.index, fill_value=0).astype("int64"))
        # parcela de internações eletivas (caráter '01') no próprio município e fora dele
        for t, col in (("proprio", "pct_eletivas_proprio"), ("fora", "pct_eletivas_fora")):
            sub = df_mt[df_mt["tipo"] == "proprio"] if t == "proprio" else df_mt[df_mt["tipo"] != "proprio"]
            gs = sub.groupby("ano")[["eletivas", "internacoes"]].sum().reindex(r.index)
            r[col] = (100 * gs["eletivas"] / gs["internacoes"].where(gs["internacoes"] > 0)).round(1)
        r.insert(0, "nivel", rotulo)
        return r.reset_index()

    partes = [resumo_nivel(mt[mt["nivel"] == n], fl[fl["nivel"] == n], n) for n in ("MC", "AC")]
    if (mt["nivel"] == "outro").any():
        partes.append(resumo_nivel(mt[mt["nivel"] == "outro"], fl[fl["nivel"] == "outro"], "outro"))
    partes.append(resumo_nivel(mt, fl, "total"))
    resumo = pd.concat(partes, ignore_index=True)
    resumo = resumo[["ano", "nivel", "internacoes", "pct_proprio_mun", "pct_mesma_regiao",
                     "pct_outra_regiao", "km_medio", "n_res_ignorada", "n_outra_uf",
                     "pct_eletivas_proprio", "pct_eletivas_fora"]]
    resumo = resumo.sort_values(["ano", "nivel"]).reset_index(drop=True)
    resumo.to_csv(DADOS / "resumo_deslocamento_ano.csv", **CSV_KW)

    # 6) outras_uf_ano.csv — residentes de outras UFs atendidos em MT, por ano e UF de residência
    uf = fl[fl["classe_res"] == "outra_uf"].copy()
    uf["cod_uf"] = uf["cod_res"].str[:2]
    outras_uf = (uf.groupby(["ano", "cod_uf"], as_index=False)["internacoes"].sum())
    outras_uf["uf"] = outras_uf["cod_uf"].map(lambda k: UF_SIGLA.get(k, ("UF " + k, "UF " + k))[0])
    outras_uf["nome_uf"] = outras_uf["cod_uf"].map(lambda k: UF_SIGLA.get(k, ("UF " + k, "UF " + k))[1])
    outras_uf = (outras_uf[["ano", "uf", "nome_uf", "internacoes"]]
                 .sort_values(["ano", "internacoes", "uf"], ascending=[True, False, True]).reset_index(drop=True))
    outras_uf.to_csv(DADOS / "outras_uf_ano.csv", **CSV_KW)

    # 7) internações de residentes de MT em outras UF (fuga_*.csv) — versão 0.3
    fuga = preparar_fuga(od, conf, fl, mt, dim)

    # --- cópias para download, com nomes ---------------------------------------------
    fm = fluxo_mun.copy()
    fm.insert(2, "municipio_origem", fm["cod_origem"].map(nome))
    fm.insert(3, "regiao_origem", fm["cod_origem"].map(reg).map(nome_reg))
    fm.insert(5, "municipio_destino", fm["cod_destino"].map(nome))
    fm.insert(6, "regiao_destino", fm["cod_destino"].map(reg).map(nome_reg))
    km_par = mt.drop_duplicates(["cod_origem", "cod_destino"])[["cod_origem", "cod_destino", "km"]]
    fm = fm.merge(km_par, on=["cod_origem", "cod_destino"], how="left")
    fm.to_csv(ARQ_DADOS / "fluxos_internacoes_municipios.csv", **CSV_KW)

    fr = fluxo_reg.copy()
    fr.insert(2, "regiao_origem", fr["co_reg_origem"].map(nome_reg))
    fr.insert(4, "regiao_destino", fr["co_reg_destino"].map(nome_reg))
    fr.to_csv(ARQ_DADOS / "fluxos_internacoes_regioes.csv", **CSV_KW)

    # ----------------------------------------------------------------------------
    # validações
    # ----------------------------------------------------------------------------
    log("\n=== validações ===")
    n_mt = int(fl.loc[fl["classe_res"] == "mt", "internacoes"].sum())
    assert int(fluxo_mun["internacoes"].sum()) == n_mt, "soma dos fluxos ≠ residentes de MT"
    assert int(fluxo_reg["internacoes"].sum()) == n_mt, "soma dos fluxos regionais ≠ residentes de MT"
    assert int(des["internacoes_res"].sum()) == n_mt, "soma de internacoes_res ≠ residentes de MT"
    assert int(des["internacoes_recebidas"].sum()) == n_mt, "soma de recebidas ≠ residentes de MT"
    tot = resumo[resumo["nivel"] == "total"].set_index("ano")
    assert (tot["internacoes"].sum()) == n_mt
    soma_pct = (tot["pct_proprio_mun"] + tot["pct_mesma_regiao"] + tot["pct_outra_regiao"])
    assert ((soma_pct - 100).abs() <= 0.2).all(), f"percentuais não somam 100: {soma_pct.to_dict()}"
    d_ok = des[des["internacoes_res"] > 0]
    s2 = d_ok["pct_proprio_mun"] + d_ok["pct_mesma_regiao"] + d_ok["pct_outra_regiao"]
    assert ((s2 - 100).abs() <= 0.2).all(), "percentuais municipais não somam 100"
    assert ((d_ok["no_proprio_mun"] + d_ok["mesma_regiao"] + d_ok["outra_regiao"])
            == d_ok["internacoes_res"]).all()
    log(f"soma dos fluxos = internações de residentes de MT = {fmt_int(n_mt)}  OK")
    log("percentuais somam 100 (estado e municípios)  OK")
    cba = polos[(polos["municipio"].str.startswith("Cuiab")) & (polos["ano"] == 2024)].iloc[0]
    top24 = polos[polos["ano"] == 2024].iloc[0]
    log(f"Cuiabá 2024: {fmt_int(cba['internacoes_recebidas'])} recebidas, "
        f"{fmt_pct(cba['pct_recebidas_de_fora'])} de fora; maior polo 2024 = {top24['municipio']}")
    assert top24["municipio"].startswith("Cuiab"), "Cuiabá não é o maior polo em 2024"
    ben = des[(des["cod_mun6"] == "510183")]
    log(f"Boa Esperança do Norte: anos {sorted(ben['ano'].unique().tolist())}, "
        f"internações de residentes = {int(ben['internacoes_res'].sum())}, "
        f"km_medio vazio = {ben['km_medio_internacao'].isna().all()} "
        f"(coordenada da sede {'disponível' if '510183' in set(cent['cod_mun6']) else 'AUSENTE'})")
    # km vazio só pode ocorrer por ausência de internações (todas as sedes têm coordenada)
    assert des.loc[des["internacoes_res"] > 0, "km_medio_internacao"].notna().all(), \
        "km_medio_internacao vazio em município com internações de residentes"
    # municípios com coordenada mas sem nenhuma internação de residentes no período
    sem_internacao = sorted(set(des["cod_mun6"]) - set(des.loc[des["internacoes_res"] > 0, "cod_mun6"]))

    # ----------------------------------------------------------------------------
    # achados (pt-BR, quantificados)
    # ----------------------------------------------------------------------------
    escrever_achados(mt, fl, des, polos, resumo, fluxo_reg, nome, nome_reg, reg, sem_coord, sem_internacao, fuga)

    r25 = tot.loc[ANO_FIM]
    log("\n=== números-chave 2025 ===")
    log(f"internações de residentes de MT: {fmt_int(r25['internacoes'])}; "
        f"% próprio município: {fmt_pct(r25['pct_proprio_mun'])}; "
        f"% outra região: {fmt_pct(r25['pct_outra_regiao'])}; "
        f"km médio: {fmt_dec(r25['km_medio'])}; outra UF: {fmt_int(r25['n_outra_uf'])}; "
        f"residência ignorada: {fmt_int(r25['n_res_ignorada'])}")
    f25 = fuga["resumo"].set_index(["ano", "nivel"])
    log(f"residentes de MT internados em outras UF em {ANO_FIM}: {fmt_int(f25.loc[(ANO_FIM, 'total'), 'internacoes_outra_uf'])} "
        f"({fmt_pct(f25.loc[(ANO_FIM, 'total'), 'pct_outra_uf'])} do total; "
        f"{fmt_pct(f25.loc[(ANO_FIM, 'AC'), 'pct_outra_uf'])} na alta complexidade); "
        f"saldo {ANO_INI}–{ANO_FIM} (entrada − saída) = {fmt_saldo(fuga['saldo_periodo'])}")
    log("\nconcluído.")
    return 0


# ----------------------------------------------------------------------------
# internações de residentes de MT em outras UF (versão 0.3)
# ----------------------------------------------------------------------------
def _pequena(s: pd.Series) -> pd.Series:
    """Contagem publicável só se 0 ou >= LIMIAR_SUPRESSAO (Termo de Uso, item 6)."""
    return (s >= 1) & (s < LIMIAR_SUPRESSAO)


def _complementar(df: pd.DataFrame, grupo: str, flag: str, valor: str, flag_comp: str) -> int:
    """Supressão complementar: em cada grupo (ex.: ano, região) com exatamente uma célula
    suprimida diante de um total publicado, suprime também a menor célula positiva ainda
    publicada do grupo (desempate pela ordem do DataFrame). Repete até estabilizar."""
    n = 0
    for _ in range(len(df) + 1):
        alvo = []
        for _, sub in df.groupby(grupo, sort=True):
            if int(sub[flag].sum()) == 1:
                cand = sub[(~sub[flag]) & (sub[valor] > 0)]
                if len(cand):
                    alvo.append(cand.sort_values(valor, kind="stable").index[0])
        if not alvo:
            break
        df.loc[alvo, flag] = True
        df.loc[alvo, flag_comp] = True
        n += len(alvo)
    return n


def _uf_principal(base_fora: pd.DataFrame, chaves: list[str]) -> pd.DataFrame:
    """UF de destino com mais internações em cada grupo (desempate pela sigla)."""
    g = (base_fora.groupby(chaves + ["uf_destino"], as_index=False)["internacoes"].sum()
                  .sort_values(chaves + ["internacoes", "uf_destino"],
                               ascending=[True] * len(chaves) + [False, True]))
    return (g.drop_duplicates(chaves).set_index(chaves)
             .rename(columns={"uf_destino": "uf_principal", "internacoes": "n_uf_principal"}))


def _recorte_subestadual(base: pd.DataFrame, chaves: list[str], grade: pd.DataFrame,
                         grupo_comp: str, com_ac: bool) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    """Totais de residentes (MT + outras UF), internações em outras UF e, opcionalmente, alta
    complexidade, com supressão primária (1 a 4) e complementar. Devolve o DataFrame publicável
    (sem os valores suprimidos), o DataFrame interno (com todos os valores, só para conferência)
    e as contagens de supressão."""
    fora = base[base["tipo_destino"] == "outra_uf"]
    d = grade.set_index(chaves)
    d["internacoes_total_res"] = base.groupby(chaves)["internacoes"].sum()
    d["internacoes_outra_uf"] = fora.groupby(chaves)["internacoes"].sum()
    if com_ac:
        d["internacoes_ac_total_res"] = base[base["nivel"] == "AC"].groupby(chaves)["internacoes"].sum()
        d["internacoes_ac_outra_uf"] = fora[fora["nivel"] == "AC"].groupby(chaves)["internacoes"].sum()
    up = _uf_principal(fora, chaves)
    d = d.join(up, how="left")
    for c in [c for c in d.columns if c.startswith("internacoes")] + ["n_uf_principal"]:
        d[c] = d[c].fillna(0).astype("int64")
    d = d.reset_index()

    F = d["internacoes_outra_uf"]
    d["supr_total"] = _pequena(F)
    d["supr_total_comp"] = False
    n_prim = int(d["supr_total"].sum())
    n_comp = _complementar(d, grupo_comp, "supr_total", "internacoes_outra_uf", "supr_total_comp")
    stats = {"total_primaria": n_prim, "total_complementar": n_comp}
    if com_ac:
        A = d["internacoes_ac_outra_uf"]
        # AC sai quando ela própria é pequena, quando a média complexidade (F − A) seria pequena
        # e dedutível, ou quando o total da linha saiu por ser pequeno
        d["supr_ac"] = _pequena(A) | _pequena(F - A) | (d["supr_total"] & ~d["supr_total_comp"])
        d["supr_ac_comp"] = False
        stats["ac_primaria"] = int(d["supr_ac"].sum())
        stats["ac_complementar"] = _complementar(d, grupo_comp, "supr_ac", "internacoes_ac_outra_uf", "supr_ac_comp")

    # percentuais e UF principal (calculados antes de apagar os valores suprimidos)
    d["pct_outra_uf"] = (100 * F / d["internacoes_total_res"].where(d["internacoes_total_res"] > 0)).round(1)
    if com_ac:
        d["pct_ac_outra_uf"] = (100 * d["internacoes_ac_outra_uf"]
                                / d["internacoes_ac_total_res"].where(d["internacoes_ac_total_res"] > 0)).round(1)
    n1 = d["n_uf_principal"]
    resto = F - n1
    d["nome_uf_principal"] = d["uf_principal"].map(SIGLA_NOME)
    d["pct_uf_principal"] = (100 * n1 / F.where(F > 0)).round(1)
    pct_ok = (n1 >= LIMIAR_SUPRESSAO) & ~_pequena(resto) & ~d["supr_total"]
    d.loc[~pct_ok, "pct_uf_principal"] = np.nan
    sem_uf = d["supr_total"] | (F == 0)
    d.loc[sem_uf, ["uf_principal", "nome_uf_principal"]] = None

    # apaga os valores suprimidos (o total e o percentual da linha permitiriam deduzi-los)
    pub = d.copy()
    for c in ("internacoes_total_res", "internacoes_outra_uf"):
        pub[c] = pub[c].astype("Int64")
    pub.loc[pub["supr_total"], ["internacoes_total_res", "internacoes_outra_uf", "pct_outra_uf"]] = pd.NA
    if com_ac:
        for c in ("internacoes_ac_total_res", "internacoes_ac_outra_uf"):
            pub[c] = pub[c].astype("Int64")
        pub.loc[pub["supr_ac"], ["internacoes_ac_total_res", "internacoes_ac_outra_uf", "pct_ac_outra_uf"]] = pd.NA

    def nota(r) -> str:
        p = []
        if r["supr_total"]:
            p.append("internações em outras UF e total suprimidos: " +
                     ("complementar (evita deduzir outra célula suprimida pela soma)" if r["supr_total_comp"]
                      else f"menos de {LIMIAR_SUPRESSAO} internações"))
        if com_ac and r["supr_ac"] and not (r["supr_total"] and not r["supr_total_comp"]):
            p.append("alta complexidade suprimida: " +
                     ("complementar (evita deduzir outra célula suprimida pela soma)" if r["supr_ac_comp"]
                      else f"menos de {LIMIAR_SUPRESSAO} internações na alta ou na média complexidade"))
        return "; ".join(p)

    pub["nota_supressao"] = d.apply(nota, axis=1)
    pub["total_suprimido"] = d["supr_total"].astype(int)
    if com_ac:
        pub["ac_suprimida"] = d["supr_ac"].astype(int)
    return pub, d, stats


def preparar_fuga(od: pd.DataFrame, conf: pd.DataFrame, fl: pd.DataFrame, mt: pd.DataFrame,
                  dim: pd.DataFrame) -> dict:
    """Arquivos fuga_*.csv: residentes de MT internados em hospitais de outras UF (2020–2025)."""
    anos = list(range(ANO_INI, ANO_FIM + 1))
    ufs = sorted(k for k in UF_SIGLA if k != UF_MT)
    od = od[od["ano"].between(ANO_INI, ANO_FIM)].copy()
    fora = od[od["tipo_destino"] == "outra_uf"].copy()
    em_mt = od[od["tipo_destino"] != "outra_uf"]

    # --- conferências de consistência -------------------------------------------------
    a = em_mt.groupby(["ano", "nivel"])["internacoes"].sum()
    b = mt.groupby(["ano", "nivel"])["internacoes"].sum()
    assert a.sort_index().equals(b.reindex(a.index).sort_index()) and a.sum() == b.sum(), \
        "matriz origem-destino (destino em MT) ≠ fluxos do site por ano e nível"
    c1 = fora.groupby("ano")["internacoes"].sum()
    c2 = conf.set_index("ano")["internacoes"].reindex(c1.index)
    assert c1.equals(c2), f"internações em outras UF: mart {c1.to_dict()} ≠ AIH distintas {c2.to_dict()}"
    assert (fora["cod_uf_destino"] != UF_MT).all() and fora["uf_destino"].notna().all()
    assert set(fora["cod_uf_destino"]) <= set(ufs), "UF de destino desconhecida"
    assert set(od["cod_mun6_res"]) <= set(dim["cod_mun6"]), "residência fora de mart.dim_municipio"
    log(f"fuga: destino em MT = fluxos do site ({fmt_int(a.sum())} internações, por ano e nível)  OK")
    log(f"fuga: internações em outras UF = AIH tipo 1 distintas dos RD das outras UF ({fmt_int(c1.sum())})  OK")

    # --- 1) por ano, UF de destino e nível (estadual) ------------------------------------
    fora["eletivas"] = fora["internacoes"] - fora["internacoes_urgencia"]
    vals = ["internacoes", "internacoes_urgencia", "diarias", "valor_total"]
    porn = fora.groupby(["ano", "cod_uf_destino", "nivel"])[vals].sum()
    tot = fora.groupby(["ano", "cod_uf_destino"])[vals].sum()
    tot["nivel"] = "total"
    tot = tot.set_index("nivel", append=True)
    grade = pd.MultiIndex.from_product([anos, ufs, NIVEIS_FUGA], names=["ano", "cod_uf_destino", "nivel"])
    uf = pd.concat([porn, tot]).reindex(grade, fill_value=0).reset_index()
    uf = uf.rename(columns={"cod_uf_destino": "cod_uf"})
    uf.insert(2, "uf", uf["cod_uf"].map(lambda k: UF_SIGLA[k][0]))
    uf.insert(3, "nome_uf", uf["cod_uf"].map(lambda k: UF_SIGLA[k][1]))
    uf["valor_total"] = uf["valor_total"].round(2)
    for c in ("internacoes", "internacoes_urgencia", "diarias"):
        uf[c] = uf[c].astype("int64")
    uf["_o"] = uf["nivel"].map({n: i for i, n in enumerate(NIVEIS_FUGA)})
    uf = uf.sort_values(["ano", "_o", "internacoes", "uf"], ascending=[True, True, False, True]).drop(columns="_o")
    uf.to_csv(DADOS / "fuga_uf_ano.csv", **CSV_KW)

    # --- 2) saldo por UF: entrada (residentes da UF internados em MT) × saída -------------
    ent = (fl[fl["classe_res"] == "outra_uf"].assign(cod_uf=lambda x: x["cod_res"].str[:2])
             .groupby(["ano", "cod_uf"])["internacoes"].sum())
    sai = fora.groupby(["ano", "cod_uf_destino"])["internacoes"].sum().rename_axis(["ano", "cod_uf"])
    g2 = pd.MultiIndex.from_product([anos, ufs], names=["ano", "cod_uf"])
    sal = pd.DataFrame({"entrada": ent.reindex(g2, fill_value=0), "saida": sai.reindex(g2, fill_value=0)}).reset_index()
    fora_desc = sorted(set(ent.index.get_level_values(1)) - set(ufs))
    if fora_desc:
        log(f"AVISO: residentes de código de UF desconhecido atendidos em MT (fora do saldo): {fora_desc}")
    sal["saldo"] = sal["entrada"] - sal["saida"]
    sal.insert(2, "uf", sal["cod_uf"].map(lambda k: UF_SIGLA[k][0]))
    sal.insert(3, "nome_uf", sal["cod_uf"].map(lambda k: UF_SIGLA[k][1]))
    for c in ("entrada", "saida", "saldo"):
        sal[c] = sal[c].astype("int64")
    sal = sal.sort_values(["ano", "saida", "uf"], ascending=[True, False, True])
    sal.to_csv(DADOS / "fuga_saldo_uf_ano.csv", **CSV_KW)
    outras = fl[fl["classe_res"] == "outra_uf"].groupby("ano")["internacoes"].sum()
    assert sal.groupby("ano")["entrada"].sum().equals(outras.reindex(anos, fill_value=0).astype("int64")), \
        "entrada do saldo ≠ residentes de outras UF atendidos em MT (outras_uf_ano.csv)"

    # --- 3) resumo estadual por ano e nível ---------------------------------------------
    linhas = []
    for nv in NIVEIS_FUGA:
        sub_mt = em_mt if nv == "total" else em_mt[em_mt["nivel"] == nv]
        sub_f = fora if nv == "total" else fora[fora["nivel"] == nv]
        sub_e = fl[fl["classe_res"] == "outra_uf"]
        if nv != "total":
            sub_e = sub_e[sub_e["nivel"] == nv]
        upr = _uf_principal(sub_f, ["ano"])
        for ano in anos:
            m_ = sub_mt[sub_mt["ano"] == ano]
            f_ = sub_f[sub_f["ano"] == ano]
            i_mt, i_f = int(m_["internacoes"].sum()), int(f_["internacoes"].sum())
            v_mt, v_f = float(m_["valor_total"].sum()), float(f_["valor_total"].sum())
            e_f = i_f - int(f_["internacoes_urgencia"].sum())
            e_mt = i_mt - int(m_["internacoes_urgencia"].sum())
            ent_ = int(sub_e.loc[sub_e["ano"] == ano, "internacoes"].sum())
            sg = upr.loc[ano, "uf_principal"] if ano in upr.index else None
            linhas.append(dict(
                ano=ano, nivel=nv, internacoes_mt=i_mt, internacoes_outra_uf=i_f,
                internacoes_total=i_mt + i_f,
                pct_outra_uf=round(100 * i_f / (i_mt + i_f), 2) if i_mt + i_f else np.nan,
                valor_mt=round(v_mt, 2), valor_outra_uf=round(v_f, 2),
                pct_valor_outra_uf=round(100 * v_f / (v_mt + v_f), 2) if v_mt + v_f else np.nan,
                pct_eletivas_mt=round(100 * e_mt / i_mt, 1) if i_mt else np.nan,
                pct_eletivas_outra_uf=round(100 * e_f / i_f, 1) if i_f else np.nan,
                uf_principal=sg, nome_uf_principal=SIGLA_NOME.get(sg) if sg else None,
                pct_uf_principal=round(100 * upr.loc[ano, "n_uf_principal"] / i_f, 1) if sg and i_f else np.nan,
                n_uf_destino=int(f_.loc[f_["internacoes"] > 0, "cod_uf_destino"].nunique()),
                n_mun_destino=int(f_.loc[f_["internacoes"] > 0, "cod_mun6_destino"].nunique()),
                entrada_outra_uf=ent_, saldo_outra_uf=ent_ - i_f))
    res = pd.DataFrame(linhas)
    res["_o"] = res["nivel"].map({n: i for i, n in enumerate(NIVEIS_FUGA)})
    res = res.sort_values(["ano", "_o"]).drop(columns="_o").reset_index(drop=True)
    res.to_csv(DADOS / "fuga_resumo_ano.csv", **CSV_KW)
    rt = res[res["nivel"] == "total"].set_index("ano")
    assert (rt["internacoes_outra_uf"] == uf[uf["nivel"] == "total"].groupby("ano")["internacoes"].sum()).all()
    assert (rt["internacoes_mt"] == mt.groupby("ano")["internacoes"].sum()).all()
    assert (res[res["nivel"] != "total"].groupby("ano")["internacoes_outra_uf"].sum() == rt["internacoes_outra_uf"]).all(), \
        "MC + AC ≠ total nas internações em outras UF (há nível 'outro'?)"

    # --- 4) região de saúde de residência × ano (com supressão) --------------------------
    dimr = dim.drop_duplicates("co_regsaud")[["co_regsaud", "nome_regsaud"]].sort_values("co_regsaud")
    base = od.rename(columns={"co_regsaud_res": "co_regsaud"})
    grade_r = pd.DataFrame([(r, a_) for r in dimr["co_regsaud"] for a_ in anos], columns=["co_regsaud", "ano"])
    reg_pub, reg_int, st_reg = _recorte_subestadual(base, ["co_regsaud", "ano"], grade_r, "ano", com_ac=True)
    reg_pub.insert(1, "regiao_saude", reg_pub["co_regsaud"].map(dimr.set_index("co_regsaud")["nome_regsaud"])
                   .str.replace(r"\s*-\s*MT$", "", regex=True))
    cols_r = ["co_regsaud", "regiao_saude", "ano", "internacoes_total_res", "internacoes_outra_uf", "pct_outra_uf",
              "internacoes_ac_total_res", "internacoes_ac_outra_uf", "pct_ac_outra_uf",
              "uf_principal", "nome_uf_principal", "pct_uf_principal", "total_suprimido", "ac_suprimida", "nota_supressao"]
    reg_pub = reg_pub[cols_r].sort_values(["co_regsaud", "ano"])
    # soma das regiões = estado (antes da supressão)
    assert (reg_int.groupby("ano")["internacoes_outra_uf"].sum() == rt["internacoes_outra_uf"]).all()

    # --- 5) município de residência, 2020–2025 somado (com supressão) ---------------------
    dimm = dim[["cod_mun6", "nome_municipio", "co_regsaud"]].copy()
    grade_m = dimm[["cod_mun6", "co_regsaud"]].rename(columns={"cod_mun6": "cod_mun6_res"})
    bm = od.copy()
    bm["co_regsaud"] = bm["cod_mun6_res"].map(dimm.set_index("cod_mun6")["co_regsaud"])
    mun_pub, mun_int, st_mun = _recorte_subestadual(bm, ["cod_mun6_res"], grade_m, "co_regsaud", com_ac=False)
    mun_pub = mun_pub.rename(columns={"cod_mun6_res": "cod_mun6"})
    mun_pub.insert(1, "municipio", mun_pub["cod_mun6"].map(dimm.set_index("cod_mun6")["nome_municipio"]))
    mun_pub.insert(3, "regiao_saude", mun_pub["co_regsaud"].map(dimr.set_index("co_regsaud")["nome_regsaud"])
                   .str.replace(r"\s*-\s*MT$", "", regex=True))
    mun_pub.insert(4, "periodo", f"{ANO_INI}–{ANO_FIM}")
    cols_m = ["cod_mun6", "municipio", "co_regsaud", "regiao_saude", "periodo", "internacoes_total_res",
              "internacoes_outra_uf", "pct_outra_uf", "uf_principal", "nome_uf_principal", "pct_uf_principal",
              "total_suprimido", "nota_supressao"]
    mun_pub = mun_pub[cols_m].sort_values("cod_mun6")
    assert len(mun_pub) == len(dim) and int(mun_int["internacoes_outra_uf"].sum()) == int(c1.sum())

    # --- 6) principais municípios de destino fora de MT, 2020–2025 (com supressão) -------
    dg = (fora.groupby(["cod_mun6_destino", "municipio_destino", "cod_uf_destino", "uf_destino"], as_index=False)
              .agg(internacoes=("internacoes", "sum")))
    dac = fora[fora["nivel"] == "AC"].groupby("cod_mun6_destino")["internacoes"].sum()
    dg["internacoes_ac"] = dg["cod_mun6_destino"].map(dac).fillna(0).astype("int64")
    dg = dg.sort_values(["internacoes", "cod_mun6_destino"], ascending=[False, True]).reset_index(drop=True)
    top = dg.head(N_DESTINOS).copy()
    assert (top["internacoes"] >= LIMIAR_SUPRESSAO).all()
    top["supr_ac"] = _pequena(top["internacoes_ac"]) | _pequena(top["internacoes"] - top["internacoes_ac"])
    top["supr_ac_comp"] = False
    # complementar por UF só quando a UF não tem outros destinos (fora da lista) com alta complexidade:
    # aí o total estadual da UF permitiria deduzir a célula suprimida
    resto_ac = dg.iloc[N_DESTINOS:].groupby("cod_uf_destino")["internacoes_ac"].sum()
    n_comp_d = 0
    for ufc, sub in top.groupby("cod_uf_destino"):
        if int(sub["supr_ac"].sum()) == 1 and int(resto_ac.get(ufc, 0)) == 0:
            cand = sub[(~sub["supr_ac"]) & (sub["internacoes_ac"] > 0)].sort_values("internacoes_ac")
            if len(cand):
                top.loc[cand.index[0], ["supr_ac", "supr_ac_comp"]] = True
                n_comp_d += 1
    top["pct_ac"] = (100 * top["internacoes_ac"] / top["internacoes"]).round(1)
    top["posicao"] = range(1, len(top) + 1)
    top["nome_uf"] = top["uf_destino"].map(SIGLA_NOME)
    top["pct_do_total_fora"] = (100 * top["internacoes"] / int(c1.sum())).round(1)
    dpub = top.rename(columns={"cod_mun6_destino": "cod_mun6", "municipio_destino": "municipio", "uf_destino": "uf"})
    dpub["internacoes_ac"] = dpub["internacoes_ac"].astype("Int64")
    dpub.loc[top["supr_ac"].values, ["internacoes_ac", "pct_ac"]] = pd.NA
    dpub["ac_suprimida"] = top["supr_ac"].astype(int).values
    dpub["nota_supressao"] = np.where(top["supr_ac_comp"], "alta complexidade suprimida: complementar",
                                      np.where(top["supr_ac"], f"alta complexidade suprimida: menos de {LIMIAR_SUPRESSAO} "
                                               "internações na alta ou na média complexidade", ""))
    dpub["periodo"] = f"{ANO_INI}–{ANO_FIM}"
    dpub = dpub[["posicao", "cod_mun6", "municipio", "uf", "nome_uf", "periodo", "internacoes", "pct_do_total_fora",
                 "internacoes_ac", "pct_ac", "ac_suprimida", "nota_supressao"]]

    # --- verificação da supressão nos recortes subestaduais publicados -------------------
    def _sem_pequenas(df: pd.DataFrame, cols: list[str], nome_arq: str) -> None:
        for c in cols:
            v = pd.to_numeric(df[c], errors="coerce")
            ruins = df[(v >= 1) & (v < LIMIAR_SUPRESSAO)]
            assert ruins.empty, f"{nome_arq}: {len(ruins)} células entre 1 e {LIMIAR_SUPRESSAO - 1} em {c}"

    _sem_pequenas(reg_pub, ["internacoes_total_res", "internacoes_outra_uf", "internacoes_ac_total_res",
                            "internacoes_ac_outra_uf"], "fuga_regiao_ano.csv")
    _sem_pequenas(mun_pub, ["internacoes_total_res", "internacoes_outra_uf"], "fuga_mun_periodo.csv")
    _sem_pequenas(dpub, ["internacoes", "internacoes_ac"], "fuga_destinos_mun.csv")
    # média complexidade dedutível (F − A) e contagem da UF principal dedutível (pct × F) também ≥ 5 ou 0
    ok = reg_pub.dropna(subset=["internacoes_outra_uf", "internacoes_ac_outra_uf"])
    assert not _pequena(ok["internacoes_outra_uf"] - ok["internacoes_ac_outra_uf"]).any()
    for df_, nome_arq in ((reg_pub, "fuga_regiao_ano.csv"), (mun_pub, "fuga_mun_periodo.csv")):
        ok = df_.dropna(subset=["pct_uf_principal"])
        n1 = (ok["pct_uf_principal"] * ok["internacoes_outra_uf"] / 100).round()
        assert not _pequena(n1).any() and not _pequena(ok["internacoes_outra_uf"] - n1).any(), nome_arq
    # nenhuma célula suprimida sozinha diante de um total publicado
    for flag, grp, df_ in (("total_suprimido", "ano", reg_pub), ("ac_suprimida", "ano", reg_pub),
                           ("total_suprimido", "co_regsaud", mun_pub)):
        cont = df_.groupby(grp)[flag].sum()
        assert not (cont == 1).any(), f"supressão isolada em {flag} por {grp}: {cont[cont == 1].to_dict()}"
    log(f"fuga: supressão (< {LIMIAR_SUPRESSAO}) — regiões × ano: AC {st_reg['ac_primaria']} primária(s) + "
        f"{st_reg['ac_complementar']} complementar(es), total {st_reg['total_primaria']} + {st_reg['total_complementar']}; "
        f"municípios (2020–2025): {st_mun['total_primaria']} primária(s) + {st_mun['total_complementar']} complementar(es); "
        f"destinos: {int(top['supr_ac'].sum())} AC suprimida(s) ({n_comp_d} complementar)  OK")

    # só agora, conferida a supressão, os recortes subestaduais são gravados
    reg_pub.to_csv(DADOS / "fuga_regiao_ano.csv", **CSV_KW)
    mun_pub.to_csv(DADOS / "fuga_mun_periodo.csv", **CSV_KW)
    dpub.to_csv(DADOS / "fuga_destinos_mun.csv", **CSV_KW)

    ent_p, sai_p = int(sal["entrada"].sum()), int(sal["saida"].sum())
    return {"resumo": res, "uf": uf, "saldo": sal, "regiao": reg_pub, "mun": mun_pub, "destinos": dpub,
            "saldo_periodo": ent_p - sai_p, "entrada_periodo": ent_p, "saida_periodo": sai_p}


def escrever_achados(mt, fl, des, polos, resumo, fluxo_reg, nome, nome_reg, reg, sem_coord, sem_internacao, fuga):
    A = []
    tot = resumo[resumo["nivel"] == "total"].set_index("ano")
    mc = resumo[resumo["nivel"] == "MC"].set_index("ano")
    ac = resumo[resumo["nivel"] == "AC"].set_index("ano")
    a0, a1 = ANO_INI, ANO_FIM
    r0, r1 = tot.loc[a0], tot.loc[a1]
    n_mt_total = int(tot["internacoes"].sum())
    n_uf_total = int(tot["n_outra_uf"].sum())
    n_ign_total = int(tot["n_res_ignorada"].sum())

    # 1. volume e crescimento
    var = 100 * (r1["internacoes"] / r0["internacoes"] - 1)
    A.append(
        f"Entre {a0} e {a1} foram registradas {fmt_int(n_mt_total)} internações (AIH tipo 1) de "
        f"residentes de Mato Grosso em hospitais do estado, passando de {fmt_int(r0['internacoes'])} "
        f"em {a0} para {fmt_int(r1['internacoes'])} em {a1} (+{fmt_dec(var)}%). Em {a0} e 2021 o volume "
        f"foi deprimido pela pandemia de COVID-19.")
    # 2. onde se interna (2025) e tendência
    fora0, fora1 = 100 - r0["pct_proprio_mun"], 100 - r1["pct_proprio_mun"]
    A.append(
        f"Em {a1}, {fmt_pct(r1['pct_proprio_mun'])} das internações de residentes de MT ocorreram no "
        f"próprio município de residência, {fmt_pct(r1['pct_mesma_regiao'])} em outro município da mesma "
        f"região de saúde e {fmt_pct(r1['pct_outra_regiao'])} em outra região de saúde. A parcela fora do "
        f"município subiu de {fmt_pct(fora0)} em {a0} para {fmt_pct(fora1)} em {a1}, e a parcela em outra "
        f"região, de {fmt_pct(r0['pct_outra_regiao'])} para {fmt_pct(r1['pct_outra_regiao'])}.")
    # 4. km médio
    A.append(
        f"A distância média em linha reta entre as sedes do município de residência e do de internação "
        f"(IBGE, Localidades 2022; 0 km quando no próprio município) foi de {fmt_dec(r1['km_medio'])} km em {a1} "
        f"(vs. {fmt_dec(r0['km_medio'])} km em {a0}). Considerando apenas quem se internou fora do "
        f"município, a distância média em {a1} foi de "
        f"{fmt_dec(_km_medio_fora(mt, a1))} km.")
    # 5. MC vs AC
    A.append(
        f"O deslocamento cresce com a complexidade: em {a1}, na média complexidade "
        f"{fmt_pct(100 - mc.loc[a1, 'pct_proprio_mun'])} das internações ocorreram fora do município "
        f"({fmt_pct(mc.loc[a1, 'pct_outra_regiao'])} em outra região; {fmt_dec(mc.loc[a1, 'km_medio'])} km "
        f"em média), enquanto na alta complexidade {fmt_pct(100 - ac.loc[a1, 'pct_proprio_mun'])} "
        f"ocorreram fora do município ({fmt_pct(ac.loc[a1, 'pct_outra_regiao'])} em outra região; "
        f"{fmt_dec(ac.loc[a1, 'km_medio'])} km). A alta complexidade somou "
        f"{fmt_int(ac.loc[a1, 'internacoes'])} internações em {a1} "
        f"({fmt_pct(100 * ac.loc[a1, 'internacoes'] / r1['internacoes'])} do total).")
    # 6. polos 2025
    p25 = polos[polos["ano"] == a1].reset_index(drop=True)
    top5 = p25.head(5)
    itens = "; ".join(
        f"{r.municipio} ({fmt_int(r.internacoes_recebidas)} internações, "
        f"{fmt_pct(r.pct_recebidas_de_fora)} de residentes de outros municípios)"
        for r in top5.itertuples())
    share5 = 100 * top5["internacoes_recebidas"].sum() / p25["internacoes_recebidas"].sum()
    A.append(
        f"Os cinco maiores polos de atendimento em {a1} concentraram {fmt_pct(share5)} de todas as "
        f"internações de residentes de MT: {itens}.")
    # 7. Cuiabá detalhes (2024 e 2025)
    cba24 = polos[(polos["ano"] == 2024) & polos["municipio"].str.startswith("Cuiab")].iloc[0]
    cba25 = p25[p25["municipio"].str.startswith("Cuiab")].iloc[0]
    A.append(
        f"Cuiabá é o principal polo estadual: recebeu {fmt_int(cba24['internacoes_recebidas'])} "
        f"internações em 2024 ({fmt_pct(cba24['pct_recebidas_de_fora'])} de fora) e "
        f"{fmt_int(cba25['internacoes_recebidas'])} em {a1} ({fmt_pct(cba25['pct_recebidas_de_fora'])} "
        f"de fora, oriundas de {fmt_int(cba25['n_origens'])} outros municípios). Na alta complexidade, "
        f"Cuiabá respondeu por {fmt_pct(100 * cba25['internacoes_ac_recebidas'] / ac.loc[a1, 'internacoes'])} "
        f"das internações de residentes de MT em {a1}.")
    # 8. polos com maior % de fora (entre os grandes)
    grandes = p25[p25["internacoes_recebidas"] >= 3000].sort_values("pct_recebidas_de_fora", ascending=False)
    itens = "; ".join(f"{r.municipio} ({fmt_pct(r.pct_recebidas_de_fora)} de fora, "
                      f"saldo de +{fmt_int(r.saldo)})" for r in grandes.head(5).itertuples())
    A.append(
        f"Entre os polos com pelo menos 3 mil internações em {a1}, os mais dependentes de pacientes "
        f"de outros municípios foram: {itens}. O saldo é a diferença entre internações recebidas e "
        f"internações de residentes do próprio município.")
    # 9. municípios sem hospital / 100% fora
    d25 = des[(des["ano"] == a1) & (des["internacoes_res"] > 0)].copy()
    d25["municipio"] = d25["cod_mun6"].map(nome)
    sem_at = d25[d25["internacoes_recebidas"] == 0]
    pop_sem = sem_at["internacoes_res"].sum()
    A.append(
        f"Em {a1}, {fmt_int(len(sem_at))} dos {fmt_int(len(d25))} municípios com internações de residentes "
        f"não registraram nenhuma "
        f"internação em estabelecimentos do próprio território, isto é, dependeram integralmente de "
        f"outros municípios para {fmt_int(pop_sem)} internações de seus residentes "
        f"({fmt_pct(100 * pop_sem / d25['internacoes_res'].sum())} do total estadual).")
    # 10. mais dependentes com hospital
    com = d25[(d25["internacoes_recebidas"] > 0) & (d25["internacoes_res"] >= 500)]
    dep = com.sort_values("pct_internacoes_fora_mun", ascending=False).head(5)
    itens = "; ".join(f"{r.municipio} ({fmt_pct(r.pct_internacoes_fora_mun)}, destino principal "
                      f"{r.destino_principal_nome})" for r in dep.itertuples())
    A.append(
        f"Mesmo entre municípios que possuem atendimento hospitalar SUS e ao menos 500 internações "
        f"de residentes em {a1}, há forte dependência externa: {itens}.")
    # 11. maior km médio
    km_top = d25[d25["km_medio_internacao"].notna()].sort_values("km_medio_internacao", ascending=False).head(5)
    itens = "; ".join(f"{r.municipio} ({fmt_dec(r.km_medio_internacao)} km; "
                      f"{fmt_pct(r.pct_internacoes_fora_mun)} fora do município)" for r in km_top.itertuples())
    A.append(
        f"Os maiores deslocamentos médios em {a1} foram registrados em {itens}.")
    # 12. mais autossuficientes
    auto = d25[d25["internacoes_res"] >= 1000].sort_values("pct_proprio_mun", ascending=False).head(5)
    itens = "; ".join(f"{r.municipio} ({fmt_pct(r.pct_proprio_mun)})" for r in auto.itertuples())
    A.append(
        f"Os municípios com maior atendimento local em {a1} (entre os com ao menos mil internações de "
        f"residentes) foram: {itens}.")
    # 13. regiões: maior % outra região
    fr25 = fluxo_reg[fluxo_reg["ano"] == a1]
    rt = fr25.groupby("co_reg_origem")["internacoes"].sum()
    rf = fr25[fr25["co_reg_origem"] != fr25["co_reg_destino"]].groupby("co_reg_origem")["internacoes"].sum()
    pr = (100 * rf.reindex(rt.index, fill_value=0) / rt).sort_values(ascending=False)
    dest_reg = (fr25[fr25["co_reg_origem"] != fr25["co_reg_destino"]]
                .groupby(["co_reg_origem", "co_reg_destino"])["internacoes"].sum().reset_index()
                .sort_values("internacoes", ascending=False).drop_duplicates("co_reg_origem")
                .set_index("co_reg_origem"))
    itens = "; ".join(
        f"{_tit(nome_reg[c])} ({fmt_pct(v)}, principalmente para {_tit(nome_reg[dest_reg.loc[c, 'co_reg_destino']])})"
        for c, v in pr.head(4).items())
    mais_auto = pr.tail(3)
    itens2 = "; ".join(f"{_tit(nome_reg[c])} ({fmt_pct(v)})" for c, v in mais_auto.items())
    A.append(
        f"Por região de saúde, as maiores parcelas de residentes internados em outra região em {a1} "
        f"foram: {itens}. As menores parcelas foram: {itens2}.")
    # 14. maior fluxo intermunicipal
    fl25 = (mt[(mt["ano"] == a1) & (mt["tipo"] != "proprio")]
              .groupby(["cod_origem", "cod_destino"])["internacoes"].sum()
              .sort_values(ascending=False).head(5))
    itens = "; ".join(f"{nome[o]} → {nome[d]} ({fmt_int(v)})" for (o, d), v in fl25.items())
    A.append(f"Os maiores fluxos intermunicipais de internação em {a1} foram: {itens}.")
    # 15. eletivas e outra UF
    el = mt[mt["ano"] == a1].groupby("tipo")[["eletivas", "internacoes"]].sum()
    pe_prop = 100 * el.loc["proprio", "eletivas"] / el.loc["proprio", "internacoes"]
    pe_fora = 100 * (el.drop("proprio")["eletivas"].sum() / el.drop("proprio")["internacoes"].sum())
    A.append(
        f"Em {a1}, {fmt_pct(pe_fora)} das internações realizadas fora do município de residência foram "
        f"eletivas, contra {fmt_pct(pe_prop)} das realizadas no próprio município — o deslocamento está "
        f"associado, em parte, a procedimentos programados (regulação).")
    # 16. outra UF e ignorada
    uf25 = fl[(fl["ano"] == a1) & (fl["classe_res"] == "outra_uf")]
    uf_top = (uf25.groupby(uf25["cod_res"].str[:2])["internacoes"].sum()
                .sort_values(ascending=False).head(3))
    itens = ", ".join(f"{UF_SIGLA.get(k, ('UF ' + k, 'UF ' + k))[1]} ({fmt_int(v)})" for k, v in uf_top.items())
    if n_ign_total == 0:
        frase_ign = "Não houve AIH com município de residência ignorado (código 510000) no período."
    else:
        frase_ign = (f"Outras {fmt_int(r1['n_res_ignorada'])} AIH tiveram município de residência ignorado "
                     f"em {a1} ({fmt_int(n_ign_total)} no período).")
    fr = fuga["resumo"].set_index(["ano", "nivel"])
    f1, fac1 = fr.loc[(a1, "total")], fr.loc[(a1, "AC")]
    sal = fuga["saldo"]
    s1 = sal[sal["ano"] == a1]
    A.append(
        f"Hospitais de MT também atenderam {fmt_int(r1['n_outra_uf'])} internações de residentes de "
        f"outras unidades da federação em {a1} ({fmt_int(n_uf_total)} no período {a0}–{a1}), "
        f"principalmente de {itens}. {frase_ign} Esses registros ficam fora dos fluxos. "
        f"No sentido inverso (SIH/SUS das 26 outras UF), {fmt_int(f1['internacoes_outra_uf'])} internações de "
        f"residentes de MT ocorreram em hospitais de outros estados em {a1} "
        f"({fmt_pct(f1['pct_outra_uf'])} das internações dos residentes; {fmt_pct(fac1['pct_outra_uf'])} na alta "
        f"complexidade), {fmt_pct(f1['pct_uf_principal'])} delas em {f1['nome_uf_principal']}. O saldo com os outros "
        f"estados (recebidas − enviadas) foi de {fmt_saldo(int(s1['saldo'].sum()))} em {a1} e de "
        f"{fmt_saldo(fuga['saldo_periodo'])} em {a0}–{a1}.")

    cab = [
        "# Achados — deslocamento residência × atendimento (internações SIH, 2020–2025)",
        "",
        "Gerado por `scripts/02_preparar_deslocamento.py`. Base: AIH tipo 1 (uma linha por internação), "
        "ano de alta (`data_saida`), residentes de Mato Grosso; MC = média complexidade, AC = alta "
        "complexidade. Distâncias em linha reta entre as sedes municipais (IBGE, Localidades do Brasil 2022), "
        "não rodoviárias; 0 km no próprio município. "
        f"Município sem coordenada da sede: {', '.join(nome[c] for c in sem_coord) or 'nenhum'}. "
        f"Município com coordenada mas sem internação de residentes no período (distância vazia): "
        f"{', '.join(nome[c] for c in sem_internacao) or 'nenhum'}.",
        "",
    ]
    assert 10 <= len(A) <= 15, f"contrato: 10–15 achados (gerados {len(A)})"
    corpo = [f"{i}. {t}" for i, t in enumerate(A, 1)]
    (DADOS / "deslocamento_achados.md").write_text("\n".join(cab + corpo) + "\n", encoding="utf-8")
    log(f"deslocamento_achados.md: {len(A)} achados")


def _km_medio_fora(mt: pd.DataFrame, ano: int) -> float:
    d = mt[(mt["ano"] == ano) & (mt["tipo"] != "proprio") & mt["km"].notna()]
    return float((d["internacoes"] * d["km"]).sum() / d["internacoes"].sum())


def _tit(s: str) -> str:
    """'REGIAO DE SAUDE X' em maiúsculas → título simples; preserva se já misto."""
    if s == s.upper():
        pequenas = {"de", "da", "do", "das", "dos", "e"}
        return " ".join(w.lower() if w.lower() in pequenas else w.capitalize() for w in s.split())
    return s


if __name__ == "__main__":
    sys.exit(main())
