# -*- coding: utf-8 -*-
"""
10_preparar_judicializacao.py — Observatório PPSUS-MT, aba "Judicialização" (versão 0.4 do site, em preparação)

COPIA e VALIDA os arquivos agregados da frente J do projeto (judicialização da saúde em Mato Grosso,
DataJud/CNJ, coleta de 17/10/2026, versão judicializacao_2026-10-17_rev1). Os arquivos de origem já
saem do pipeline da equipe com supressão primária (contagens de 1 a 4) e supressão complementar
AUDITADA (exporta_site.py + auditoria_supressao.py). Este script não recalcula nada: copia byte a byte,
confere e PARA (código de saída 1) se alguma conferência falhar.

Origem (pasta da frente J, fora do repositório): informe por --origem, pela variável de ambiente
PPSUS_JUD_ORIGEM ou pela linha PPSUS_JUD_ORIGEM=<pasta> no .env.local (ver scripts/config_local.py).
Dela são lidos:
  <origem>/site/*.csv                 arquivos agregados auditados e o dicionário de colunas
  <origem>/tjmt_comarca_municipio.csv comarca do TJMT que abrange cada município (Corregedoria do TJMT)

Saídas
  dados_site/judicializacao/judicializacao_*.csv  cópias idênticas dos arquivos auditados usados pela página
  dados_site/judicializacao/auditoria_supressao.csv  resultado das auditorias de divulgação (nota metodológica)
  dados_site/judicializacao/dicionario_judicializacao.csv  dicionário, sem as linhas do e-NatJus
  dados_site/judicializacao/comarca_municipio.csv  município → comarca (142 linhas, sem caminhos locais)
  dados_site/judicializacao/comarcas_mt.geojson     contorno das 79 comarcas (malha municipal dissolvida)
  dados_site/judicializacao/manifesto.csv           arquivo, linhas, SHA-256 da cópia e da origem
  arquivos/dados/judicializacao_*.csv               downloads (mesmo conteúdo; dicionário e auditoria renomeados)

Fica de FORA, por decisão do coordenador (17/10/2026): os números do Painel de Estatísticas do e-NatJus
(judicializacao_enatjus_tjmt*.csv), lidos à mão no painel do CNJ e não auditáveis por consulta.

Conferências (qualquer falha interrompe o script, sem deixar cópia parcial):
  1. arquivos presentes e colunas exatamente as esperadas;
  2. contagens inteiras, não negativas e NENHUMA de 1 a 4 (supressão primária);
  3. marca `suprimido` coerente com as células vazias; taxas e faixas vazias onde a contagem está vazia;
  4. supressão complementar intacta nas relações aditivas exatas verificáveis com os próprios arquivos:
     anos 2022–2024 → período 2022–2024 (por comarca) e comarcas → total atribuível do estado (por ano):
     nunca uma única célula vazia numa relação; sem células vazias, a soma tem de bater;
  5. somas exatas sem supressão: meses → ano e grupos → total (série mensal × série anual);
  6. herança municipal: a faixa de cada município é a da sua comarca no ano, e a taxa 2022–2024 também;
  7. taxa suavizada 2022–2024 múltipla de 5 e coerente com a faixa; faixas só nos 6 rótulos aprovados;
  8. previsão com 6 grupos × 3 meses, intervalo contendo o valor previsto e modelo = menor MASE do grupo;
  9. auditoria da origem sem célula recuperável (itens "= 0");
 10. nenhum caminho local (unidade de disco, ppsus_repo) nos arquivos copiados;
 11. (revisão 2, 18/10/2026) ações MISTAS: pública + suplementar − total nunca de 1 a 4 (estado e comarcas),
     esfera vazia sem intervalo degenerado; Núcleo 4.0 sem origem ≤ ações sem origem; testes conjuntos do
     bloco (Wald) e indicadores complementares (números do texto da página) presentes e coerentes.

Uso (a partir da raiz do repositório):
    python scripts/10_preparar_judicializacao.py --origem <pasta da frente J>
Requisitos: Python 3.12, pandas, geopandas/shapely (para o contorno das comarcas).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from config_local import caminho  # noqa: E402

SAIDA = RAIZ / "dados_site" / "judicializacao"
DOWN = RAIZ / "arquivos" / "dados"
GEO_MUN = RAIZ / "dados_site" / "geo_mt.geojson"

FAIXAS = ["0 a 50", "50 a 100", "100 a 150", "150 a 200", "200 a 300", "300 ou mais"]
CORTES = [0, 50, 100, 150, 200, 300, np.inf]
GRUPOS_MES = ["medicamentos", "tratamento", "internacao_uti", "outros_publica", "suplementar"]
GRUPOS_PREV = GRUPOS_MES + ["total"]
MODELOS_MET = ["ets", "lightgbm", "sarima", "persistencia", "ingenuo_sazonal"]

# Arquivos auditados que a página usa, com as colunas esperadas (na ordem) e as colunas de contagem
ARQS = {
    "judicializacao_mt_ano.csv": dict(
        cols=["ano", "acoes_saude", "publica", "suplementar", "pub_medicamentos", "pub_tratamento", "pub_internacao_uti",
              "pub_insumos", "pub_home_care", "pub_saude_mental", "atribuivel", "pct_atribuivel", "liminar_concedida",
              "acoes_nucleo_sem_origem", "ano_parcial", "suprimido"],
        contagens=["acoes_saude", "publica", "suplementar", "pub_medicamentos", "pub_tratamento", "pub_internacao_uti",
                   "pub_insumos", "pub_home_care", "pub_saude_mental", "atribuivel", "liminar_concedida",
                   "acoes_nucleo_sem_origem"]),
    "judicializacao_mt_mes_grupo.csv": dict(
        cols=["ano", "mes", "grupo", "acoes", "mes_incompleto", "suprimido"], contagens=["acoes"]),
    "judicializacao_comarca_2022_2024.csv": dict(
        cols=["comarca", "periodo", "populacao_media", "acoes_saude", "acoes_publica", "acoes_suplementar", "taxa_100mil",
              "taxa_eb_local_100mil", "taxa_publica_eb_local_100mil", "limite_inferior", "faixa_taxa_suavizada", "suprimido"],
        contagens=["acoes_saude", "acoes_publica", "acoes_suplementar"]),
    "judicializacao_comarca_ano.csv": dict(
        cols=["comarca", "ano", "populacao", "n_municipios", "acoes_saude", "taxa_100mil", "faixa_taxa_suavizada",
              "ano_parcial", "limite_inferior", "quebra_centralizacao", "suprimido"],
        contagens=["acoes_saude"]),
    "judicializacao_municipio_ano.csv": dict(
        cols=["cod_mun6", "nome_municipio", "nome_regsaud", "comarca", "ano", "ano_parcial", "taxa_limite_inferior",
              "faixa_taxa_suavizada", "quebra_centralizacao", "taxa_eb_local_2022_2024_100mil"],
        contagens=[]),
    "judicializacao_previsao_trimestre.csv": dict(
        cols=["grupo", "modelo", "alvo", "h", "prev", "li80", "ls80"], contagens=[]),
    "judicializacao_previsao_metricas.csv": dict(
        cols=["grupo", "modelo", "n", "mae", "rmse", "vies", "mase", "rmae"], contagens=[]),
    "judicializacao_fatores_associados.csv": dict(
        cols=["dependente", "variavel", "irr", "irr_li", "irr_ls", "p", "p_holm", "p_bh", "dp_variavel"], contagens=[]),
    # revisão 2 da origem (18/10/2026): números do texto da página que antes vinham só do relatório técnico
    "judicializacao_testes_bloco.csv": dict(
        cols=["dependente", "especificacao", "modelo", "chi2", "gl", "p", "p_holm", "p_bh", "n"], contagens=[]),
    "judicializacao_indicadores_complementares.csv": dict(
        cols=["grupo", "indicador", "recorte", "valor", "unidade", "descricao"], contagens=[]),
}
AUDITORIA = "auditoria_supressao.csv"
DICIONARIO = "dicionario_judicializacao.csv"
EXCLUIDOS = ["judicializacao_enatjus_tjmt.csv", "judicializacao_enatjus_tjmt_cid.csv"]  # leitura manual: não vão ao site
MAPA_CM = "tjmt_comarca_municipio.csv"
# Downloads: nome publicado em arquivos/dados → arquivo de origem (site/) ou gerado
DOWNLOADS = {**{k: k for k in ARQS},
             "judicializacao_dicionario.csv": DICIONARIO,
             "judicializacao_auditoria_supressao.csv": AUDITORIA,
             "judicializacao_comarca_municipio.csv": "comarca_municipio.csv"}

PADRAO_LOCAL = re.compile(r"\b[A-Za-z]:\\|ppsus_repo|ppsus_db|\\Users\\", re.IGNORECASE)

erros: list[str] = []


def falha(msg: str) -> None:
    erros.append(msg)


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def ler(p: Path) -> pd.DataFrame:
    return pd.read_csv(p, encoding="utf-8", keep_default_na=True, na_values=[""])


def booleana(s: pd.Series, nome: str) -> pd.Series:
    v = s.astype(str).str.strip().str.lower()
    ok = v.isin(["true", "false"])
    if not ok.all():
        falha(f"{nome}: valores não booleanos {sorted(v[~ok].unique())[:5]}")
    return v == "true"


# ----------------------------------------------------------------------------
# Conferências
# ----------------------------------------------------------------------------
def conferir_estrutura(d: dict[str, pd.DataFrame]) -> None:
    for arq, spec in ARQS.items():
        df = d[arq]
        if list(df.columns) != spec["cols"]:
            falha(f"{arq}: colunas {list(df.columns)} ≠ esperadas {spec['cols']}")
            continue
        if len(df) == 0:
            falha(f"{arq}: vazio")
        for c in spec["contagens"]:
            v = df[c].dropna()
            if not np.all(np.isclose(v, np.round(v))):
                falha(f"{arq}.{c}: contagem não inteira")
            if (v < 0).any():
                falha(f"{arq}.{c}: contagem negativa")
            pequenas = v[(v >= 1) & (v <= 4)]
            if len(pequenas):
                falha(f"{arq}.{c}: {len(pequenas)} contagem(ns) de 1 a 4 publicada(s) — supressão primária violada")


def conferir_mt(d: dict[str, pd.DataFrame]) -> None:
    a = d["judicializacao_mt_ano.csv"].copy()
    cont = ARQS["judicializacao_mt_ano.csv"]["contagens"]
    if sorted(a.ano.tolist()) != list(range(2020, 2027)):
        falha(f"mt_ano: anos {sorted(a.ano.tolist())} ≠ 2020–2026")
    parc = booleana(a.ano_parcial, "mt_ano.ano_parcial")
    if a.ano[parc].tolist() != [2026]:
        falha("mt_ano: ano_parcial deveria marcar só 2026")
    sup = booleana(a.suprimido, "mt_ano.suprimido")
    vazio = a[cont].isna().any(axis=1)
    if (sup != vazio).any():
        falha("mt_ano: marca 'suprimido' incoerente com as células vazias")
    if a[["acoes_saude", "publica", "suplementar", "atribuivel"]].isna().any().any():
        falha("mt_ano: total, pública, suplementar ou atribuível vazio (não deveria haver supressão no total estadual)")
    calc = (100 * a.atribuivel / a.acoes_saude).round(1)
    if not np.allclose(calc, a.pct_atribuivel, atol=0.051):
        falha("mt_ano: pct_atribuivel não confere com atribuivel / acoes_saude")
    # ações mistas (pública + suplementar − total) nunca de 1 a 4; Núcleo 4.0 sem origem ≤ ações sem origem
    mista = a.publica + a.suplementar - a.acoes_saude
    if (mista < 0).any() or mista.between(1, 4).any():
        falha(f"mt_ano: pública + suplementar − total (ações mistas) negativa ou de 1 a 4 em {a.ano[(mista < 0) | mista.between(1, 4)].tolist()}")
    nuc = a.acoes_nucleo_sem_origem
    if ((nuc > a.acoes_saude - a.atribuivel) & nuc.notna()).any():
        falha("mt_ano: ações do Núcleo 4.0 sem origem maiores que as ações sem origem (total − atribuível)")

    m = d["judicializacao_mt_mes_grupo.csv"].copy()
    if sorted(m.grupo.unique()) != sorted(GRUPOS_MES):
        falha(f"mes_grupo: grupos {sorted(m.grupo.unique())}")
    inc = booleana(m.mes_incompleto, "mes_grupo.mes_incompleto")
    meses_inc = sorted(set(zip(m.ano[inc], m.mes[inc])))
    if meses_inc != [(2026, 9)]:
        falha(f"mes_grupo: meses incompletos {meses_inc} ≠ [(2026, 9)]")
    sup = booleana(m.suprimido, "mes_grupo.suprimido")
    if (sup != m.acoes.isna()).any():
        falha("mes_grupo: marca 'suprimido' incoerente com as células vazias")
    n_esp = 5 * (6 * 12 + 9)
    if len(m) != n_esp or m.duplicated(["ano", "mes", "grupo"]).any():
        falha(f"mes_grupo: {len(m)} linhas (esperadas {n_esp}, sem duplicatas)")
    if m.acoes.isna().any():
        falha("mes_grupo: há meses suprimidos; a soma meses → ano não pode ser conferida (rever a página)")
    else:
        soma = m.groupby("ano").acoes.sum()
        tot = a.set_index("ano").acoes_saude
        if not (soma.reindex(tot.index) == tot).all():
            falha("mes_grupo: soma dos meses e grupos ≠ total anual de mt_ano")
        for g, col in [("medicamentos", "pub_medicamentos"), ("tratamento", "pub_tratamento"),
                       ("internacao_uti", "pub_internacao_uti")]:
            sg = m[m.grupo == g].groupby("ano").acoes.sum()
            ref = a.set_index("ano")[col]
            ok = ref.notna()
            if not (sg.reindex(ref.index)[ok] == ref[ok]).all():
                falha(f"mes_grupo: soma anual de {g} ≠ {col} de mt_ano")


def conferir_comarcas(d: dict[str, pd.DataFrame]) -> None:
    a = d["judicializacao_mt_ano.csv"].set_index("ano")
    p = d["judicializacao_comarca_2022_2024.csv"].copy()
    c = d["judicializacao_comarca_ano.csv"].copy()
    if p.comarca.nunique() != 79 or len(p) != 79:
        falha(f"comarca_2022_2024: {p.comarca.nunique()} comarcas (esperadas 79)")
    if set(p.periodo) != {"2022-2024"}:
        falha("comarca_2022_2024: período diferente de 2022-2024")
    if sorted(c.ano.unique()) != list(range(2020, 2027)) or len(c) != 79 * 7:
        falha("comarca_ano: esperadas 79 comarcas × 2020–2026")
    if set(c.comarca) != set(p.comarca):
        falha("comarca_ano e comarca_2022_2024 com comarcas diferentes")
    # marcas e células dependentes
    sup = booleana(p.suprimido, "comarca_2022_2024.suprimido")
    vaz = p[["acoes_saude", "acoes_publica", "acoes_suplementar"]].isna().any(axis=1)
    if (sup != vaz).any():
        falha("comarca_2022_2024: marca 'suprimido' incoerente")
    if (p.taxa_100mil.isna() != p.acoes_saude.isna()).any() or (p.taxa_eb_local_100mil.isna() & p.acoes_saude.notna()).any():
        falha("comarca_2022_2024: taxa vazia/preenchida incoerente com a contagem")
    if (p.taxa_publica_eb_local_100mil.isna() != p.acoes_publica.isna()).any():
        falha("comarca_2022_2024: taxa pública suavizada deveria ficar vazia exatamente onde a contagem pública está suprimida")
    t = p.taxa_eb_local_100mil.dropna()
    if not np.allclose(t / 5, np.round(t / 5)):
        falha("comarca_2022_2024: taxa suavizada não arredondada a 5 por 100 mil")
    tp = p.taxa_publica_eb_local_100mil.dropna()
    if not np.allclose(tp / 5, np.round(tp / 5)):
        falha("comarca_2022_2024: taxa pública suavizada não arredondada a 5 por 100 mil")
    # A faixa vem da taxa ANTES do arredondamento a 5: a taxa sem arredondar está em [t − 2,5; t + 2,5],
    # e a faixa publicada tem de cruzar esse intervalo (ex.: Sapezal, 300 arredondado, faixa "200 a 300").
    lim = {f: (CORTES[i], CORTES[i + 1]) for i, f in enumerate(FAIXAS)}
    for _, r in p.iterrows():
        lo, hi = lim.get(r.faixa_taxa_suavizada, (np.nan, np.nan))
        t_ = r.taxa_eb_local_100mil
        if not (lo <= t_ + 2.5 and t_ - 2.5 < hi):
            falha(f"comarca_2022_2024 {r.comarca}: faixa '{r.faixa_taxa_suavizada}' incompatível com a taxa arredondada {t_}")
    li = booleana(p.limite_inferior, "comarca_2022_2024.limite_inferior")
    if sorted(p.comarca[li]) != ["Cuiabá", "Várzea Grande"]:
        falha(f"comarca_2022_2024: limite_inferior marca {sorted(p.comarca[li])}")

    supa = booleana(c.suprimido, "comarca_ano.suprimido")
    if (supa != c.acoes_saude.isna()).any():
        falha("comarca_ano: marca 'suprimido' incoerente")
    if (c.taxa_100mil.isna() != c.acoes_saude.isna()).any() or (c.faixa_taxa_suavizada.isna() != c.acoes_saude.isna()).any():
        falha("comarca_ano: taxa ou faixa preenchida onde a contagem está suprimida (ou o contrário)")
    if not set(c.faixa_taxa_suavizada.dropna()) <= set(FAIXAS):
        falha("comarca_ano: faixa fora dos 6 rótulos aprovados")
    q = booleana(c.quebra_centralizacao, "comarca_ano.quebra_centralizacao")
    if sorted(c.ano[q].unique()) != [2025, 2026]:
        falha("comarca_ano: quebra_centralizacao deveria marcar 2025 e 2026")
    pa = booleana(c.ano_parcial, "comarca_ano.ano_parcial")
    if sorted(c.ano[pa].unique()) != [2026]:
        falha("comarca_ano: ano_parcial deveria marcar só 2026")
    lia = booleana(c.limite_inferior, "comarca_ano.limite_inferior")
    if sorted(c.comarca[lia].unique()) != ["Cuiabá", "Várzea Grande"]:
        falha("comarca_ano: limite_inferior incoerente")

    # Relação 1: anos 2022–2024 → período (por comarca)
    anos = c[c.ano.between(2022, 2024)].pivot(index="comarca", columns="ano", values="acoes_saude")
    per = p.set_index("comarca").acoes_saude
    for com, lin in anos.iterrows():
        cel = list(lin.values) + [per.get(com)]
        n_vazias = int(pd.isna(cel).sum())
        if n_vazias == 1:
            falha(f"comarca {com}: uma única célula vazia na relação 2022+2023+2024 = período (recuperável por diferença)")
        elif n_vazias == 0 and int(sum(lin.values)) != int(per.get(com)):
            falha(f"comarca {com}: soma dos anos 2022–2024 ≠ período")
    # Relação 2: comarcas → total atribuível do estado (por ano)
    for ano, g in c.groupby("ano"):
        n_vazias = int(g.acoes_saude.isna().sum())
        if n_vazias == 1:
            falha(f"comarca_ano {ano}: uma única comarca suprimida diante do total atribuível do estado")
        elif n_vazias == 0 and int(g.acoes_saude.sum()) != int(a.loc[ano, "atribuivel"]):
            falha(f"comarca_ano {ano}: soma das comarcas ≠ atribuível do estado")
        elif n_vazias >= 2 and g.acoes_saude.sum() > a.loc[ano, "atribuivel"]:
            falha(f"comarca_ano {ano}: soma das comarcas publicadas excede o atribuível do estado")
    if per.isna().sum() == 1:
        falha("comarca_2022_2024: uma única comarca suprimida no período")
    if per.notna().all() and int(per.sum()) != int(a.loc[2022:2024, "atribuivel"].sum()):
        falha("comarca_2022_2024: soma das comarcas ≠ atribuível do estado em 2022–2024")
    # pública e suplementar: nunca uma só célula vazia na coluna (diante do total atribuível por esfera, não publicado)
    for col in ["acoes_publica", "acoes_suplementar"]:
        if p[col].isna().sum() == 1:
            falha(f"comarca_2022_2024.{col}: uma única célula suprimida na coluna")
    # Revisão 2 (18/10/2026): ações MISTAS. Sem esfera "não especificada" na base, total = só pública + só suplementar
    # + mista, logo pública + suplementar − total = mistas: com as três colunas publicadas na linha, nunca de 1 a 4.
    mista = p.acoes_publica + p.acoes_suplementar - p.acoes_saude
    if (mista < 0).any():
        falha("comarca_2022_2024: pública + suplementar < total (deveria valer total ≤ pública + suplementar)")
    rev = p.comarca[mista.between(1, 4)].tolist()
    if rev:
        falha(f"comarca_2022_2024: pública + suplementar − total revela de 1 a 4 ações mistas em {len(rev)} comarcas ({rev[:5]})")
    # Com uma esfera vazia, ela não pode ficar presa a ≤ 4 nem a um valor: vale de total − outra esfera a total.
    for col, outra in (("acoes_publica", "acoes_suplementar"), ("acoes_suplementar", "acoes_publica")):
        so_uma = p[p[col].isna() & p[outra].notna()]
        ruins = so_uma.comarca[(so_uma.acoes_saude <= 4) | (so_uma.acoes_saude - so_uma[outra] == so_uma.acoes_saude)].tolist()
        if ruins:
            falha(f"comarca_2022_2024.{col}: célula vazia com intervalo degenerado em {ruins[:5]}")


def conferir_municipios(d: dict[str, pd.DataFrame], cm: pd.DataFrame) -> None:
    mu = d["judicializacao_municipio_ano.csv"].copy()
    c = d["judicializacao_comarca_ano.csv"]
    p = d["judicializacao_comarca_2022_2024.csv"].set_index("comarca")
    if mu.cod_mun6.nunique() != 142:
        falha(f"municipio_ano: {mu.cod_mun6.nunique()} municípios (esperados 142)")
    if cm.cod_mun6.nunique() != 142 or cm.comarca.nunique() != 79:
        falha("comarca_municipio: esperados 142 municípios em 79 comarcas")
    x = mu.drop_duplicates("cod_mun6").merge(cm[["cod_mun6", "comarca"]], on="cod_mun6", how="outer", suffixes=("", "_cm"))
    if (x.comarca != x.comarca_cm).any():
        falha("municipio_ano: comarca do município ≠ tabela oficial comarca → município")
    j = mu.merge(c[["comarca", "ano", "faixa_taxa_suavizada"]], on=["comarca", "ano"], how="left", suffixes=("", "_com"))
    dif = ~((j.faixa_taxa_suavizada == j.faixa_taxa_suavizada_com) | (j.faixa_taxa_suavizada.isna() & j.faixa_taxa_suavizada_com.isna()))
    if dif.any():
        falha(f"municipio_ano: {int(dif.sum())} linha(s) com faixa diferente da faixa da comarca no ano (herança)")
    t = mu.comarca.map(p.taxa_eb_local_100mil)
    if not np.allclose(t, mu.taxa_eb_local_2022_2024_100mil, equal_nan=True):
        falha("municipio_ano: taxa 2022–2024 ≠ taxa suavizada da comarca")
    li = booleana(mu.taxa_limite_inferior, "municipio_ano.taxa_limite_inferior")
    if set(mu.comarca[li]) != {"Cuiabá", "Várzea Grande"} or set(mu.comarca[~li]) & {"Cuiabá", "Várzea Grande"}:
        falha("municipio_ano: marca de limite inferior ≠ municípios das comarcas de Cuiabá e Várzea Grande")


def conferir_previsao(d: dict[str, pd.DataFrame]) -> None:
    pv = d["judicializacao_previsao_trimestre.csv"]
    me = d["judicializacao_previsao_metricas.csv"]
    if sorted(pv.grupo.unique()) != sorted(GRUPOS_PREV) or len(pv) != 18:
        falha("previsao_trimestre: esperados 6 grupos × 3 meses")
    if sorted(pv.alvo.unique()) != ["2026-09-01", "2026-10-01", "2026-11-01"]:
        falha("previsao_trimestre: meses previstos ≠ set–nov/2026")
    if ((pv.li80 > pv.prev) | (pv.prev > pv.ls80)).any():
        falha("previsao_trimestre: intervalo de 80% não contém o valor previsto")
    if sorted(me.grupo.unique()) != sorted(GRUPOS_PREV) or set(me.modelo) != set(MODELOS_MET) or len(me) != 30:
        falha("previsao_metricas: esperados 6 grupos × 5 modelos")
    melhor = me.loc[me.groupby("grupo").mase.idxmin(), ["grupo", "modelo"]].set_index("grupo").modelo
    usado = pv.drop_duplicates("grupo").set_index("grupo").modelo
    if not (melhor.reindex(usado.index) == usado).all():
        falha("previsao: o modelo da previsão não é o de menor MASE em algum grupo")
    f = d["judicializacao_fatores_associados.csv"]
    if ((f.irr_li > f.irr) | (f.irr > f.irr_ls)).any():
        falha("fatores_associados: IC 95% não contém a razão de taxas")
    if f.dependente.nunique() != 6:
        falha("fatores_associados: esperados 6 dependentes")
    w = d["judicializacao_testes_bloco.csv"]
    wc = w[w.especificacao == "completo"]
    if sorted(wc.dependente) != sorted(f.dependente.unique()) or ((w.p < 0) | (w.p > 1)).any():
        falha("testes_bloco: especificação completa sem os 6 dependentes ou p fora de [0, 1]")
    if (wc.p_holm < wc.p - 1e-12).any():
        falha("testes_bloco: p de Holm menor que o p bruto")
    ind = d["judicializacao_indicadores_complementares.csv"]
    esp = {"razao_documentos_datajud_painel_cnj", "pct_documentos_trf1_sobre_tjmt", "codigos_origem_identificados",
           "codigos_origem_associados_comarcas", "correlacao_postos_taxa_suavizada", "pseudo_r2_fora_da_amostra",
           "dm_p_minimo", "dm_p_maximo"}
    if not esp <= set(ind.indicador):
        falha(f"indicadores_complementares: faltam {sorted(esp - set(ind.indicador))}")


def conferir_auditoria(aud: pd.DataFrame) -> None:
    v = dict(zip(aud["item"].astype(str), aud["valor"].astype(str)))
    zeros = ["relacoes exatas com uma unica celula suprimida",
             "celulas primarias determinadas por programacao linear (atacante realista)",
             "celulas determinadas pela inversao do Bayes empirico na forma publicada"]
    for k in zeros:
        if v.get(k) != "0":
            falha(f"auditoria da origem: '{k}' = {v.get(k)!r} (esperado 0)")
    pior = [k for k in v if k.startswith("idem, pior caso")]
    if not pior or v[pior[0]] != "0":
        falha("auditoria da origem: pior caso (atacante informado) não é 0")
    if v.get("passo de arredondamento das taxas suavizadas do periodo 2022-2024 (por 100 mil)") != "5":
        falha("auditoria da origem: passo de arredondamento ≠ 5")


def conferir_sem_caminho_local(pasta: Path) -> None:
    for f in pasta.iterdir():
        if f.suffix.lower() in (".csv", ".geojson") and PADRAO_LOCAL.search(f.read_text(encoding="utf-8")):
            falha(f"{f.name}: contém caminho local")


# ----------------------------------------------------------------------------
# Geração
# ----------------------------------------------------------------------------
def comarca_municipio(origem: Path) -> pd.DataFrame:
    cm = ler(origem / MAPA_CM)
    esp = ["cod_mun6", "nome_municipio", "comarca", "n_mapa", "sede_comarca", "regra", "pagina_cms", "pagina_atualizada"]
    if list(cm.columns) != esp:
        falha(f"{MAPA_CM}: colunas {list(cm.columns)} ≠ {esp}")
        return cm
    cm = cm[["cod_mun6", "nome_municipio", "comarca", "sede_comarca", "regra", "pagina_atualizada"]].copy()
    cm["sede_comarca"] = booleana(cm.sede_comarca, "comarca_municipio.sede_comarca")
    # regra: texto curto, sem endereços de terceiros (a fonte secundária fica no relatório técnico)
    oficial = cm.regra.str.startswith("jurisdicao oficial")
    cm["regra"] = np.where(oficial, "jurisdição oficial (Corregedoria-Geral da Justiça do TJMT)",
                  np.where(cm.regra.str.contains("pagina sem jurisdicao"), "página da comarca sem lista: só o próprio município",
                  np.where(cm.regra.str.contains("desmembrado de Sorriso"), "município instalado em 2025, desmembrado de Sorriso (comarca de Sorriso)",
                  np.where(cm.regra.str.contains("distritos"), "listado entre os distritos da comarca",
                  np.where(cm.regra.str.contains("Nova Brasilandia"), "integra a comarca de Nova Brasilândia (LC 774/2023, não instalada), atendida por Chapada dos Guimarães — a confirmar com a Corregedoria",
                  np.where(cm.regra.str.contains("mais proxima"), "ausente das páginas oficiais: sede de comarca mais próxima por tempo rodoviário",
                           "regra documentada no relatório técnico"))))))
    return cm.sort_values(["comarca", "nome_municipio"]).reset_index(drop=True)


def contorno_comarcas(cm: pd.DataFrame, destino: Path) -> int:
    import geopandas as gpd
    g = gpd.read_file(GEO_MUN)
    g["cod_mun6"] = g["cod_mun6"].astype(int)
    g = g.merge(cm[["cod_mun6", "comarca"]], on="cod_mun6", how="left")
    if g.comarca.isna().any():
        falha(f"malha: municípios sem comarca {g.cod_mun6[g.comarca.isna()].tolist()}")
    g = g.to_crs(4326)
    dis = g.dissolve(by="comarca", as_index=False)[["comarca", "geometry"]]
    dis["geometry"] = dis.geometry.buffer(0).simplify(0.004, preserve_topology=True)
    nomes = cm.groupby("comarca").nome_municipio.apply(lambda s: "; ".join(sorted(s, key=lambda x: x.lower())))
    dis["municipios"] = dis.comarca.map(nomes)
    gj = json.loads(dis.to_json(drop_id=True))

    def arred(o):
        if isinstance(o, list):
            return [arred(x) for x in o]
        return round(o, 4) if isinstance(o, float) else o
    for f in gj["features"]:
        f["geometry"]["coordinates"] = arred(f["geometry"]["coordinates"])
    destino.write_text(json.dumps(gj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return len(dis)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--origem", help="pasta da frente J (contém site/ e tjmt_comarca_municipio.csv)")
    args = ap.parse_args()
    origem = Path(args.origem) if args.origem else caminho("PPSUS_JUD_ORIGEM", obrigatorio=False)
    if origem is None:
        raise SystemExit("Informe a pasta da frente J: --origem <pasta>, variável PPSUS_JUD_ORIGEM ou linha "
                         "PPSUS_JUD_ORIGEM=<pasta> no .env.local.")
    site = origem / "site"
    faltam = [f for f in [*ARQS, AUDITORIA, DICIONARIO] if not (site / f).exists()] + \
             ([MAPA_CM] if not (origem / MAPA_CM).exists() else [])
    if faltam:
        raise SystemExit(f"Arquivos ausentes na origem: {faltam}")

    d = {f: ler(site / f) for f in ARQS}
    aud = ler(site / AUDITORIA)
    dic = ler(site / DICIONARIO)
    cm = comarca_municipio(origem)

    conferir_estrutura(d)
    if not erros:
        conferir_mt(d)
        conferir_comarcas(d)
        conferir_municipios(d, cm)
        conferir_previsao(d)
        conferir_auditoria(aud)
    if list(dic.columns) != ["arquivo", "coluna", "descricao"]:
        falha("dicionário: colunas inesperadas")
    faltam_dic = [f for f in ARQS if f not in set(dic.arquivo)]
    if faltam_dic:
        falha(f"dicionário sem os arquivos {faltam_dic}")
    if erros:
        print("FALHOU — nada foi gravado:")
        for e in erros:
            print("  -", e)
        raise SystemExit(1)

    # Grava numa pasta temporária, confere e só então substitui a saída
    with tempfile.TemporaryDirectory(dir=RAIZ / "dados_site") as tmp:
        tmp = Path(tmp)
        manifesto = []
        for f in ARQS:
            shutil.copyfile(site / f, tmp / f)
            if sha256(tmp / f) != sha256(site / f):
                falha(f"{f}: cópia difere da origem")
            manifesto.append(dict(arquivo=f, linhas=len(d[f]), sha256=sha256(tmp / f), sha256_origem=sha256(site / f)))
        shutil.copyfile(site / AUDITORIA, tmp / AUDITORIA)
        manifesto.append(dict(arquivo=AUDITORIA, linhas=len(aud), sha256=sha256(tmp / AUDITORIA), sha256_origem=sha256(site / AUDITORIA)))
        dic_site = dic[~dic.arquivo.isin(EXCLUIDOS)].copy()
        dic_site.to_csv(tmp / DICIONARIO, index=False, encoding="utf-8", lineterminator="\n")
        manifesto.append(dict(arquivo=DICIONARIO, linhas=len(dic_site), sha256=sha256(tmp / DICIONARIO), sha256_origem=sha256(site / DICIONARIO)))
        cm.to_csv(tmp / "comarca_municipio.csv", index=False, encoding="utf-8", lineterminator="\n")
        manifesto.append(dict(arquivo="comarca_municipio.csv", linhas=len(cm), sha256=sha256(tmp / "comarca_municipio.csv"),
                              sha256_origem=sha256(origem / MAPA_CM)))
        n_com = contorno_comarcas(cm, tmp / "comarcas_mt.geojson")
        if n_com != 79:
            falha(f"contorno: {n_com} comarcas na malha (esperadas 79)")
        manifesto.append(dict(arquivo="comarcas_mt.geojson", linhas=n_com, sha256=sha256(tmp / "comarcas_mt.geojson"), sha256_origem=""))
        conferir_sem_caminho_local(tmp)
        if erros:
            print("FALHOU — nada foi gravado:")
            for e in erros:
                print("  -", e)
            raise SystemExit(1)
        man = pd.DataFrame(manifesto)
        man["gerado_em"] = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
        man["versao_origem"] = "judicializacao_2026-10-17_rev1"
        man.to_csv(tmp / "manifesto.csv", index=False, encoding="utf-8", lineterminator="\n")

        SAIDA.mkdir(parents=True, exist_ok=True)
        for f in SAIDA.iterdir():
            if f.is_file():
                f.unlink()
        for f in tmp.iterdir():
            shutil.copyfile(f, SAIDA / f.name)

    # Downloads (mesmo conteúdo, nomes com prefixo judicializacao_); remove sobras de rodadas anteriores
    DOWN.mkdir(parents=True, exist_ok=True)
    for f in DOWN.glob("judicializacao_*.csv"):
        if f.name not in DOWNLOADS:
            f.unlink()
    for pub, src in DOWNLOADS.items():
        shutil.copyfile(SAIDA / src, DOWN / pub)
        if sha256(DOWN / pub) != sha256(SAIDA / src):
            raise SystemExit(f"download {pub}: cópia difere")
    for f in EXCLUIDOS:
        for pasta in (SAIDA, DOWN):
            if (pasta / f).exists():
                raise SystemExit(f"{f} não pode ir ao site (leitura manual do e-NatJus)")

    print(f"OK — {len(ARQS)} arquivos auditados copiados e conferidos; contorno de {n_com} comarcas;")
    print(f"     saída em {SAIDA.relative_to(RAIZ)} e {len(DOWNLOADS)} downloads em {DOWN.relative_to(RAIZ)}.")


if __name__ == "__main__":
    main()
