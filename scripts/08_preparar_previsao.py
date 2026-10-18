# -*- coding: utf-8 -*-
"""
08_preparar_previsao.py — Observatório PPSUS-MT, aba "Previsão" (previsão de demanda, atividade A5)

COPIA e VALIDA os CSV agregados da A5 (resultados PRELIMINARES) que alimentam previsao/index.qmd:

  origem A5 (baseline)   a5_site_*.csv   versão baseline_preliminar_2026-10-13 (Random Forest e rede
                                         neural acrescentados em 17/10/2026, mesma versão)
  origem A5 (nowcast)    a5nc_site_*.csv versão nowcast_preliminar_2026-10-17 (revisão 1): nowcast do
                                         atraso do SIH, previsão encadeada a partir de hoje e alerta

Os arquivos de origem já vêm com a supressão de células pequenas aplicada e auditada pela equipe
(contagens observadas de 1 a 4 suprimidas, com supressão complementar). Este script NÃO recalcula
nem altera nenhum valor: confere e copia byte a byte. Se qualquer conferência falhar, nada é
gravado e o script termina com código 1.

Conferências
  1. presença dos arquivos, UTF-8, colunas exatamente as esperadas, número de linhas igual ao do
     dicionário de origem, versão única e esperada, nenhum texto "nan"/"None";
  2. contagens observadas (série semanal, parcial já processado, observado da validação) e cópias de
     contagem (previsões dos modelos ingênuos) sem valores entre 0 e 5 (exclusive), inteiras, vazias
     exatamente quando marcadas como suprimidas; nowcast regional e limiares de alerta nunca abaixo
     de 5 quando publicados; ocupação no limiar vazia quando o limiar é suprimido;
  3. supressão complementar suficiente (revisão 2 da A5, 18/10/2026): em cada semana (e ótica/faixa
     etária/método) com região vazia há ≥ 2 vazias e S − (k − 1) ≥ 5 (S = MT − publicadas), e semana com o
     total de MT suprimido tem todas as regiões vazias; ataque por programação inteira (scipy/HiGHS) sem
     nenhuma célula fixada nem limitada a ≤ 4; nenhum arquivo traz o tipo de supressão; CL e BF de MT
     vazios quando o parcial de MT é suprimido; as séries semanais dos dois arquivos de
     origem suprimem exatamente as mesmas células nas semanas em comum, e o parcial das previsões do
     baseline suprime as mesmas regiões que a série de hoje; as cópias dos ingênuos só são publicadas
     quando a contagem copiada também é, e com o mesmo valor;
  4. Mato Grosso = soma das 16 regiões no nowcast e nas previsões de hoje (quando todas publicadas).

Saídas (só depois de todas as conferências passarem)
  dados_site/previsao/   cópias exatas dos 18 CSV de dados e dos 2 dicionários de origem, mais
                         meta.csv (versões, datas de referência, hashes SHA-256 das cópias)
  arquivos/dados/previsao_*.csv  cópias exatas para download, com nomes do site, e
                         previsao_dicionario.csv (dicionário dos downloads)

Caminhos de origem (não fixados no código; ver scripts/config_local.py):
  --origem-a5 / PPSUS_A5_SITE         pasta com os a5_site_*.csv
  --origem-nowcast / PPSUS_A5NC_SITE  pasta com os a5nc_site_*.csv
  (argumento de linha de comando, variável de ambiente ou linha CHAVE=caminho em .env.local)

Uso (a partir da raiz do repositório):
    python scripts/08_preparar_previsao.py --origem-a5 <pasta> --origem-nowcast <pasta>
    python scripts/08_preparar_previsao.py --so-conferir ...   # só confere, não grava
Requisitos: Python 3.12, pandas.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import shutil
import sys
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

SAIDA = RAIZ / "dados_site" / "previsao"
DOWN = RAIZ / "arquivos" / "dados"

VERSAO_A5 = "baseline_preliminar_2026-10-13"
VERSAO_NC = "nowcast_preliminar_2026-10-17"

# Referências que não estão nos CSV (relatório técnico A5_Nowcasting_Alerta.md, revisão 1, seção 6)
META_FIXA = {
    "competencia_sih": ("08/2026", "A5_Nowcasting_Alerta (17/10/2026), seção 6: SIH até a competência 08/2026"),
    "carga_sih": ("17/10/2026", "A5_Nowcasting_Alerta (17/10/2026), seção 6: carga do SIH de 17/10/2026"),
    "versao_sivep": ("12/10/2026", "A5_Nowcasting_Alerta (17/10/2026), seção 6: SIVEP-Gripe na versão de 12/10/2026"),
    "decisao_publicacao": ("17/10/2026", "Decisão do coordenador de 17/10/2026: publicar no site como resultados preliminares"),
    "relatorio_baseline": ("Modelo de referência preliminar da previsão de demanda (A5), versão baseline_preliminar_2026-10-13, documento regerado em 17/10/2026", "relatório técnico do projeto"),
    "relatorio_nowcast": ("Nowcasting do atraso do SIH, previsão encadeada e alerta de alta pressão (A5), versão nowcast_preliminar_2026-10-17, revisão 1", "relatório técnico do projeto"),
}

# arquivo de origem -> (origem, colunas esperadas, nome do download, descrição curta)
ARQ = {
    # --- baseline (origem A5) ---
    "a5_site_serie_observada.csv": ("a5",
        "versao,otica,cod_regiao,regiao,ano_se,se,inicio_se,fim_se,internacoes_j00_j99,internacoes_suprimido",
        "previsao_serie_semanal_2020_2026.csv",
        "Série semanal observada de internações J00–J99 (SIH, AIH tipo 1) por região de saúde e MT, duas óticas, SE 1/2020 à última SE completa do baseline (SE 12/2026)"),
    "a5_site_metricas_resumo.csv": ("a5",
        "versao,modelo,rotulo_modelo,otica,nivel,h,horizonte,n_series,mae,rmse,mase,rmae_geo,regioes_melhor_que_ingenuo,vies",
        "previsao_metricas_modelos.csv",
        "Erro de previsão por modelo, ótica, nível (MT ou média das 16 regiões) e horizonte; validação rolling-origin"),
    "a5_site_metricas_regiao.csv": ("a5",
        "versao,otica,cod_regiao,regiao,modelo,rotulo_modelo,n_alvos,mae,rmse,mase,rmae,vies,melhor_mase_na_regiao",
        "previsao_metricas_regioes.csv",
        "Erro médio dos horizontes de 1 a 4 semanas por região de saúde e modelo"),
    "a5_site_previsoes_4sem.csv": ("a5",
        "versao,otica,cod_regiao,regiao,modelo,rotulo_modelo,ano_se_origem,se_origem,h,ano_se_alvo,se_alvo,inicio_se_alvo,fim_se_alvo,y_prev,y_prev_suprimido,lo80,hi80,lo95,hi95,y_parcial_carga_atual,y_parcial_carga_atual_suprimido,completude_esperada,y_parcial_corrigido",
        "previsao_baseline_4sem.csv",
        "Previsões do baseline para as 4 SE seguintes à última SE completa (SE 13 a 16/2026), por região e MT"),
    "a5_site_rolling_mt.csv": ("a5",
        "versao,otica,modelo,rotulo_modelo,h,ano_se_alvo,se_alvo,inicio_se_alvo,y_prev,y_obs,y_obs_suprimido",
        "previsao_validacao_mt.csv",
        "Observado e previsto na validação rolling-origin, Mato Grosso, horizontes de 1 e 4 semanas"),
    "a5_site_testes_dm.csv": ("a5",
        "versao,otica,nivel,h,modelo_a,modelo_b,n,perda_a,perda_b,estat_hln,p_valor,rotulo_a,rotulo_b",
        "previsao_testes_dm.csv",
        "Testes de Diebold-Mariano (correção HLN) entre pares de modelos do baseline"),
    "a5_site_intervalos_cobertura.csv": ("a5",
        "versao,tipo,modelo,otica,nivel,h,n,cobertura80,largura80,score80,cobertura95,largura95,score95,rotulo_modelo",
        "previsao_cobertura_intervalos.csv",
        "Cobertura, largura e interval score dos intervalos de previsão de 80% e 95%"),
    # --- nowcast, previsão encadeada e alerta (origem A5NC) ---
    "a5nc_site_serie_completa_hoje.csv": ("nc",
        "versao,alvo,rotulo_alvo,cod_regiao,regiao,ano_se,se,inicio_se,fim_se,internacoes,internacoes_suprimido",
        "previsao_serie_semanal_carga_2026_10_17.csv",
        "Série semanal completa na carga do SIH de 17/10/2026 (todas as idades e menores de 5 anos), SE 1/2024 a SE 16/2026"),
    "a5nc_site_nowcast_hoje.csv": ("nc",
        "versao,corte,alvo,rotulo_alvo,cod_regiao,regiao,ano_se,se,inicio_se,fim_se,atraso_semanas,metodo,rotulo_metodo,y_nowcast,lo80,hi80,lo95,hi95,parcial_processado,parcial_processado_suprimido,nowcast_suprimido",
        "previsao_nowcast_hoje.csv",
        "Nowcast das SE ainda incompletas no SIH (SE 17 a 41/2026), por método, região e MT, corte de 17/10/2026"),
    "a5nc_site_previsao_hoje.csv": ("nc",
        "versao,corte,alvo,rotulo_alvo,cod_regiao,regiao,metodo,rotulo_metodo,h,ano_se,se,inicio_se,fim_se,y_previsto,y_previsto_suprimido,lo80,hi80,lo95,hi95,limiar_p90,limiar_p90_suprimido,status",
        "previsao_proximas_semanas.csv",
        "Previsão das SE 42 a 45/2026 a partir de hoje (nowcast + previsão encadeada), limiar e situação do alerta"),
    "a5nc_site_metricas_nowcast.csv": ("nc",
        "versao,cenario,alvo,nivel,metodo,rotulo_metodo,faixa_atraso_semanas,n,mae,mase,vies,cob80,cob95,n_int",
        "previsao_metricas_nowcast.csv",
        "Erro do nowcast por método e faixa de atraso (validação retrospectiva, cortes de 2024 e 2025)"),
    "a5nc_site_metricas_encadeado.csv": ("nc",
        "versao,cenario,alvo,nivel,metodo,rotulo_metodo,h,horizonte,n,mae,mase,vies,cob80,cob95,n_int",
        "previsao_metricas_encadeado.csv",
        "Erro da previsão a partir da SE de corte (nowcast + previsão encadeada) e dos comparadores"),
    "a5nc_site_testes_dm.csv": ("nc",
        "versao,cenario,alvo,nivel,h,modelo_a,modelo_b,n,perda_a,perda_b,estat_hln,p_valor,estat_hln_nw,p_valor_nw,p_holm_nw",
        "previsao_testes_dm_encadeado.csv",
        "Testes de Diebold-Mariano da previsão encadeada (HLN, Newey-West e ajuste de Holm)"),
    "a5nc_site_metricas_menor5.csv": ("nc",
        "versao,modelo,nivel,h,mae,mase,rotulo_modelo",
        "previsao_metricas_menor5.csv",
        "Erro da previsão rolling-origin das internações de menores de 5 anos (sem atraso)"),
    "a5nc_site_alerta_limiares.csv": ("nc",
        "versao,alvo,cod_regiao,regiao,regra,limiar,limiar_suprimido,n_semanas",
        "previsao_alerta_limiares.csv",
        "Limiares de alta pressão (percentis 80 e 90 das 104 SE de 2022–2023) por série"),
    "a5nc_site_alerta_medidas.csv": ("nc",
        "versao,regra,fonte,alvo,nivel,modelo,h,n,vp,fp,fn,vn,prevalencia,sensibilidade,especificidade,vpp,vpn,f1,rotulo_metodo",
        "previsao_alerta_medidas.csv",
        "Alerta como classificação: sensibilidade, especificidade, VPP, VPN e F1 por fonte, modelo e horizonte (vp/fp/fn/vn = número de região-semanas)"),
    "a5nc_site_alerta_antecedencia.csv": ("nc",
        "versao,regra,fonte,alvo,nivel,modelo,duracao_minima,episodios,detectados,detectados_antes_inicio,pct_antes_inicio,antecedencia_media_detectados,antecedencia_media_todos_perdido_0",
        "previsao_alerta_antecedencia.csv",
        "Antecedência do primeiro aviso nos episódios de alta pressão (episódios e detectados = número de episódios)"),
    "a5nc_site_contexto_pediatrico.csv": ("nc",
        "versao,cod_regiao,limiar_p90_menor5,media_2022_2023,permanencia_media_menor5,leitos_ped_clinicos_sus,leitos_uti_ped_sus,leitos_ped_clinicos_exist,ocupacao_equiv_limiar_pct,ocupacao_equiv_media_pct,regiao,limiar_p90_menor5_suprimido",
        "previsao_contexto_pediatrico.csv",
        "Contexto pediátrico: limiar de menores de 5 anos, permanência, leitos pediátricos SUS e ocupação equivalente"),
}
DIC = {"a5": "a5_site_dicionario.csv", "nc": "a5nc_site_dicionario.csv"}
VERDADEIRO = {"True": True, "False": False}

FALHAS: list[str] = []


def falha(msg: str) -> None:
    FALHAS.append(msg)
    print("  FALHA:", msg)


def ok(msg: str) -> None:
    print("  ok:", msg)


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def ler(p: Path) -> pd.DataFrame:
    """Lê como texto (sem converter vazio em NaN) para conferir o conteúdo exato."""
    return pd.read_csv(p, dtype=str, keep_default_na=False, encoding="utf-8")


def num(s: pd.Series) -> pd.Series:
    return pd.to_numeric(s.replace("", np.nan), errors="raise")


def booleano(d: pd.DataFrame, col: str, arq: str) -> pd.Series:
    v = d[col]
    if not v.isin(list(VERDADEIRO)).all():
        falha(f"{arq}: coluna {col} com valores fora de True/False: {sorted(set(v) - set(VERDADEIRO))[:5]}")
        return v.map(lambda x: VERDADEIRO.get(x, False))
    return v.map(VERDADEIRO)


def conferir_contagem(d: pd.DataFrame, arq: str, col: str, flag: str | None = None, mascara: pd.Series | None = None,
                      inteira: bool = True, rotulo: str = "") -> None:
    """Contagem observada (ou cópia de contagem): nenhum valor em (0, 5); inteira; vazia sse suprimida."""
    m = mascara if mascara is not None else pd.Series(True, index=d.index)
    v = num(d.loc[m, col])
    peq = v[(v > 0) & (v < 5)]
    if len(peq):
        falha(f"{arq}: {col}{rotulo} com {len(peq)} valor(es) entre 0 e 5 (ex.: {peq.iloc[0]})")
    if inteira:
        frac = v.dropna()
        frac = frac[(frac - frac.round()).abs() > 1e-9]
        if len(frac):
            falha(f"{arq}: {col}{rotulo} com {len(frac)} valor(es) não inteiro(s)")
    if (v < 0).any():
        falha(f"{arq}: {col}{rotulo} com valores negativos")
    if flag is not None:
        f = booleano(d.loc[m], flag, arq)
        vazio = v.isna()
        if (f & ~vazio).any():
            falha(f"{arq}: {col}{rotulo}: {int((f & ~vazio).sum())} célula(s) marcada(s) como suprimida(s) com valor publicado")
        if (~f & vazio).any() and col not in ("y_prev",):
            # contagens observadas: vazio só quando suprimido (as previsões podem faltar por outros motivos)
            falha(f"{arq}: {col}{rotulo}: {int((~f & vazio).sum())} célula(s) vazia(s) sem marca de supressão")
    if not len(peq):
        ok(f"{arq}: {col}{rotulo} sem contagens de 1 a 4 ({int(v.notna().sum())} publicadas, {int(v.isna().sum())} vazias)")


def conferir_complementar(d: pd.DataFrame, arq: str, col: str, flag: str, grupo: list[str], rotulo: str = "") -> None:
    """Supressão complementar (revisão 2 da A5, 18/10/2026), em cada grupo (semana × ótica/faixa etária/método):
    - MT suprimido ⇒ todas as regiões vazias (inclusive zeros);
    - MT publicado e k regiões vazias ⇒ k = 0 ou (k ≥ 2 e S − (k − 1) ≥ 5), com S = MT − soma das publicadas:
      como o zero é publicado, cada vazia vale de 1 a S − (k − 1), e nenhuma fica fixada nem limitada a 1–4."""
    ruins, n_grupos = [], 0
    for chave, g in d.groupby(grupo):
        reg = g[g["cod_regiao"] != "MT"]
        mt = g[g["cod_regiao"] == "MT"]
        vaz = reg[col] == ""
        if mt.empty:
            continue
        if mt[col].iloc[0] == "":
            n_grupos += 1
            if not vaz.all():
                ruins.append((chave, "MT suprimido com região publicada"))
            continue
        k = int(vaz.sum())
        if k == 0:
            continue
        n_grupos += 1
        S = float(mt[col].iloc[0]) - float(num(reg.loc[~vaz, col]).sum())
        if k < 2 or S - (k - 1) < 5:
            ruins.append((chave, f"k={k}, S={S:g}"))
    if ruins:
        falha(f"{arq}: {col}{rotulo}: {len(ruins)} grupo(s) sem supressão complementar suficiente (ex.: {ruins[:3]})")
    else:
        ok(f"{arq}: supressão complementar de {col}{rotulo} suficiente em {n_grupos} grupo(s) com supressão "
           f"(≥ 2 vazias e S − (k − 1) ≥ 5; MT suprimido ⇒ grupo vazio)")


def auditar_milp(d: pd.DataFrame, arq: str, col: str, grupo: list[str], rotulo: str = "") -> None:
    """Ataque por programação inteira (scipy/HiGHS), como o verificador: Σ 16 regiões = MT por alvo e menores de 5 ≤
    todas as idades por região; vazia ≥ 1 (zero publicado), salvo nos grupos com MT suprimido (vazia ≥ 0, MT de 1 a 4).
    Falha se alguma célula vazia regional fica fixada (mín = máx) ou, com MT publicado, limitada a ≤ 4."""
    try:
        from scipy.optimize import Bounds, LinearConstraint, milp
    except ImportError:
        falha("scipy ausente: auditoria por programação inteira não rodou")
        return
    if "alvo" not in d.columns:
        d = d.assign(alvo="j00_j99")
    v = d.assign(_v=num(d[col]))
    ruins, n_cel = [], 0
    for chave, g in v.groupby(grupo):
        if g["_v"].notna().all():
            continue
        ids, lb, ub, tot_sup = [], [], [], {}
        for a, ga in g.groupby("alvo"):
            mt = ga[ga["cod_regiao"] == "MT"]
            tot_sup[a] = len(mt) > 0 and mt["_v"].isna().all()
        for r in g[g["_v"].isna()].itertuples():
            ids.append((r.alvo, r.cod_regiao))
            if r.cod_regiao == "MT":
                lb.append(1); ub.append(4)
            else:
                lb.append(0 if tot_sup[r.alvo] else 1); ub.append(10 ** 6)
        pos = {c: i for i, c in enumerate(ids)}
        n = len(ids)
        A, lo, hi = [], [], []
        for a, ga in g.groupby("alvo"):
            mt = ga[ga["cod_regiao"] == "MT"]
            if mt.empty:
                continue
            reg = ga[ga["cod_regiao"] != "MT"]
            row = np.zeros(n)
            rhs = -float(reg["_v"].sum())
            for r in reg[reg["_v"].isna()].itertuples():
                row[pos[(a, r.cod_regiao)]] = 1
            if pd.isna(mt["_v"].iloc[0]):
                row[pos[(a, "MT")]] = -1
            else:
                rhs += float(mt["_v"].iloc[0])
            if row.any():
                A.append(row); lo.append(rhs); hi.append(rhs)
        if {"j00_j99", "j00_j99_menor5"} <= set(g["alvo"]):
            for cr, gr in g.groupby("cod_regiao"):
                t = gr[gr["alvo"] == "j00_j99"]["_v"]; c5 = gr[gr["alvo"] == "j00_j99_menor5"]["_v"]
                if t.empty or c5.empty:
                    continue
                row = np.zeros(n)
                if pd.isna(t.iloc[0]) and pd.isna(c5.iloc[0]):
                    row[pos[("j00_j99_menor5", cr)]] = 1; row[pos[("j00_j99", cr)]] = -1; A.append(row); lo.append(-np.inf); hi.append(0)
                elif pd.isna(c5.iloc[0]):
                    row[pos[("j00_j99_menor5", cr)]] = 1; A.append(row); lo.append(-np.inf); hi.append(float(t.iloc[0]))
                elif pd.isna(t.iloc[0]):
                    row[pos[("j00_j99", cr)]] = 1; A.append(row); lo.append(float(c5.iloc[0])); hi.append(np.inf)
        cons = [LinearConstraint(np.array(A), np.array(lo), np.array(hi))] if A else []
        for i, c in enumerate(ids):
            if c[1] == "MT":
                continue
            n_cel += 1
            ext = []
            for s in (1, -1):
                obj = np.zeros(n); obj[i] = s
                r = milp(obj, constraints=cons, integrality=np.ones(n), bounds=Bounds(np.array(lb, float), np.array(ub, float)))
                ext.append(int(round(r.x[i])) if r.success else None)
            mn, mx = ext
            if mn is not None and mx is not None and (mn == mx or (mx < 5 and not tot_sup[c[0]])):
                ruins.append((chave, c, mn, mx))
    if ruins:
        falha(f"{arq}: {col}{rotulo}: {len(ruins)} célula(s) vazia(s) fixada(s) ou limitada(s) a ≤ 4 por programação inteira (ex.: {ruins[:3]})")
    else:
        ok(f"{arq}: {col}{rotulo}: {n_cel} célula(s) vazia(s) regional(is) — nenhuma fixada nem limitada a ≤ 4 (programação inteira)")


def conferir_soma_mt(d: pd.DataFrame, arq: str, col: str, grupo: list[str], tol: float = 0.05) -> None:
    v = d.copy()
    v["_v"] = num(v[col])
    reg = v[v["cod_regiao"] != "MT"]
    mt = v[v["cod_regiao"] == "MT"].set_index(grupo)["_v"]
    soma = reg.groupby(grupo)["_v"].agg(lambda s: s.sum() if s.notna().all() and len(s) == 16 else np.nan)
    dif = (soma - mt.reindex(soma.index)).dropna().abs()
    if (dif > tol).any():
        falha(f"{arq}: MT difere da soma das 16 regiões em {int((dif > tol).sum())} grupo(s) ({col})")
    else:
        ok(f"{arq}: MT = soma das 16 regiões em {len(dif)} grupo(s) completos ({col})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--origem-a5", help="pasta com os a5_site_*.csv (ou PPSUS_A5_SITE)")
    ap.add_argument("--origem-nowcast", help="pasta com os a5nc_site_*.csv (ou PPSUS_A5NC_SITE)")
    ap.add_argument("--so-conferir", action="store_true", help="só confere, sem gravar")
    args = ap.parse_args()
    org = {"a5": Path(args.origem_a5) if args.origem_a5 else caminho("PPSUS_A5_SITE"),
           "nc": Path(args.origem_nowcast) if args.origem_nowcast else caminho("PPSUS_A5NC_SITE")}
    print(f"Origem A5 (baseline): {org['a5']}\nOrigem A5 (nowcast):  {org['nc']}")

    # ---- 1. presença, colunas, linhas, versão -----------------------------------------------------
    print("\n1. Arquivos, colunas, linhas e versão")
    dic = {}
    for k, nome in DIC.items():
        p = org[k] / nome
        if not p.exists():
            falha(f"dicionário ausente: {p}")
            continue
        dic[k] = ler(p).set_index("arquivo")
    D: dict[str, pd.DataFrame] = {}
    for nome, (k, cols, _, _) in ARQ.items():
        p = org[k] / nome
        if not p.exists():
            falha(f"arquivo ausente: {p}")
            continue
        try:
            txt = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            falha(f"{nome}: não está em UTF-8")
            continue
        d = ler(p)
        if list(d.columns) != cols.split(","):
            falha(f"{nome}: colunas diferentes das esperadas: {list(d.columns)}")
            continue
        for ruim in (",nan,", ",NaN,", ",None,", ",nan\r", ",nan\n", ",inf,", ",-inf,"):
            if ruim in txt:
                falha(f"{nome}: texto '{ruim.strip(',')}' no arquivo")
        esperado = dic.get(k)
        if esperado is not None and nome in esperado.index:
            n_dic = int(float(esperado.loc[nome, "linhas"]))
            if n_dic != len(d):
                falha(f"{nome}: {len(d)} linhas; o dicionário de origem informa {n_dic}")
        else:
            falha(f"{nome}: não consta do dicionário de origem")
        ver = set(d["versao"])
        alvo_ver = VERSAO_A5 if k == "a5" else VERSAO_NC
        if ver != {alvo_ver}:
            falha(f"{nome}: versão {sorted(ver)} (esperada {alvo_ver})")
        D[nome] = d
        ok(f"{nome}: {len(d)} linhas, {len(d.columns)} colunas, versão {alvo_ver}")
    if FALHAS:
        return fim(org, D, gravar=False)

    # ---- 2. contagens e cópias de contagem --------------------------------------------------------
    print("\n2. Contagens de 1 a 4 e marcas de supressão")
    so = D["a5_site_serie_observada.csv"]
    conferir_contagem(so, "serie_observada", "internacoes_j00_j99", "internacoes_suprimido")
    ro = D["a5_site_rolling_mt.csv"]
    conferir_contagem(ro, "rolling_mt", "y_obs", "y_obs_suprimido")
    p4 = D["a5_site_previsoes_4sem.csv"]
    conferir_contagem(p4, "previsoes_4sem", "y_parcial_carga_atual", "y_parcial_carga_atual_suprimido")
    conferir_contagem(p4, "previsoes_4sem", "y_parcial_corrigido", "y_parcial_carga_atual_suprimido", inteira=False)
    ing4 = p4["modelo"].isin(["ingenuo_sazonal", "ingenuo_ultima"])
    conferir_contagem(p4, "previsoes_4sem", "y_prev", "y_prev_suprimido", mascara=ing4, rotulo=" (ingênuos)")
    for c in ("lo80", "hi80", "lo95", "hi95"):
        if (p4.loc[booleano(p4, "y_prev_suprimido", "previsoes_4sem"), c] != "").any():
            falha(f"previsoes_4sem: {c} publicado em previsão suprimida")
    sc = D["a5nc_site_serie_completa_hoje.csv"]
    conferir_contagem(sc, "serie_completa_hoje", "internacoes", "internacoes_suprimido")
    nh = D["a5nc_site_nowcast_hoje.csv"]
    conferir_contagem(nh, "nowcast_hoje", "parcial_processado", "parcial_processado_suprimido")
    reg_nc = (nh["cod_regiao"] != "MT") & (nh["metodo"] != "parcial")
    v = num(nh.loc[reg_nc, "y_nowcast"])
    if ((v > 0) & (v < 5)).any():
        falha(f"nowcast_hoje: nowcast regional publicado abaixo de 5 em {int(((v > 0) & (v < 5)).sum())} célula(s)")
    else:
        ok("nowcast_hoje: nowcast regional publicado sempre ≥ 5")
    sup_nc = booleano(nh, "nowcast_suprimido", "nowcast_hoje")
    if (sup_nc & nh["y_nowcast"].ne("")).any():
        falha("nowcast_hoje: nowcast marcado como suprimido com valor publicado")
    for c in ("lo80", "hi80", "lo95", "hi95"):
        if (nh.loc[sup_nc, c] != "").any():
            falha(f"nowcast_hoje: {c} publicado em nowcast suprimido")
    if (nh.loc[nh["metodo"] == "parcial", "y_nowcast"] != "").any():
        falha("nowcast_hoje: método 'parcial' com y_nowcast preenchido")
    ph = D["a5nc_site_previsao_hoje.csv"]
    ing_h = ph["metodo"] == "ingenuo_sazonal"
    conferir_contagem(ph, "previsao_hoje", "y_previsto", None, mascara=ing_h, rotulo=" (ingênuo sazonal)")
    sup_ph = booleano(ph, "y_previsto_suprimido", "previsao_hoje")
    if (sup_ph & ph["y_previsto"].ne("")).any():
        falha("previsao_hoje: previsão marcada como suprimida com valor publicado")
    lim_ph = num(ph["limiar_p90"])
    if ((lim_ph > 0) & (lim_ph < 5)).any():
        falha("previsao_hoje: limiar publicado abaixo de 5")
    if (booleano(ph, "limiar_p90_suprimido", "previsao_hoje") & lim_ph.notna()).any():
        falha("previsao_hoje: limiar suprimido com valor publicado")
    li = D["a5nc_site_alerta_limiares.csv"]
    lv = num(li["limiar"])
    if ((lv > 0) & (lv < 5)).any() or (booleano(li, "limiar_suprimido", "alerta_limiares") != lv.isna()).any():
        falha("alerta_limiares: limiar abaixo de 5 publicado ou marca de supressão inconsistente")
    else:
        ok(f"alerta_limiares: {int(lv.isna().sum())} limiar(es) suprimido(s), demais ≥ 5")
    cp = D["a5nc_site_contexto_pediatrico.csv"]
    cv = num(cp["limiar_p90_menor5"])
    sup_cp = booleano(cp, "limiar_p90_menor5_suprimido", "contexto_pediatrico")
    if ((cv > 0) & (cv < 5)).any() or (sup_cp != cv.isna()).any():
        falha("contexto_pediatrico: limiar abaixo de 5 publicado ou marca inconsistente")
    if (cp.loc[sup_cp, "ocupacao_equiv_limiar_pct"] != "").any():
        falha("contexto_pediatrico: ocupação no limiar publicada com o limiar suprimido")
    else:
        ok("contexto_pediatrico: ocupação no limiar vazia onde o limiar é suprimido")
    # coerência entre os limiares das duas tabelas
    lp = li[li["regra"] == "p90"].set_index(["alvo", "cod_regiao"])["limiar"].map(lambda s: float(s) if s else np.nan)
    lh = ph.groupby(["alvo", "cod_regiao"])["limiar_p90"].agg(lambda s: set(s))
    n_dif = 0
    for chave, conj in lh.items():
        if len(conj) != 1:
            n_dif += 1
            continue
        a_ = next(iter(conj)); a_ = float(a_) if a_ else np.nan; b_ = lp.get(chave, np.nan)
        if not ((np.isnan(a_) and np.isnan(b_)) or (not np.isnan(a_) and not np.isnan(b_) and abs(a_ - b_) < 1e-6)):
            n_dif += 1
    if n_dif:
        falha(f"limiar P90 diferente entre previsao_hoje e alerta_limiares em {n_dif} série(s)")
    else:
        ok("limiar P90 igual em previsao_hoje e alerta_limiares nas 34 séries")

    # ---- 3. supressão complementar e coerência entre arquivos -------------------------------------
    print("\n3. Supressão complementar e coerência entre arquivos")
    conferir_complementar(so, "serie_observada", "internacoes_j00_j99", "internacoes_suprimido", ["otica", "ano_se", "se"])
    conferir_complementar(sc, "serie_completa_hoje", "internacoes", "internacoes_suprimido", ["alvo", "ano_se", "se"])
    pm = p4[p4["modelo"] == "lgbm"]
    conferir_complementar(pm, "previsoes_4sem", "y_parcial_carga_atual", "y_parcial_carga_atual_suprimido", ["otica", "se_alvo"])
    nm = nh[nh["metodo"] == "ml"]
    conferir_complementar(nm, "nowcast_hoje", "parcial_processado", "parcial_processado_suprimido", ["alvo", "se"])
    for met in ("ml", "cl", "bf"):
        conferir_complementar(nh[nh["metodo"] == met], "nowcast_hoje", "y_nowcast", "nowcast_suprimido", ["alvo", "se"], rotulo=f" ({met})")
    # programação inteira (o mesmo ataque do verificador do site)
    auditar_milp(so, "serie_observada", "internacoes_j00_j99", ["otica", "ano_se", "se"])
    auditar_milp(sc, "serie_completa_hoje", "internacoes", ["ano_se", "se"])
    auditar_milp(nm, "nowcast_hoje", "parcial_processado", ["se"], rotulo=" (já processado)")
    auditar_milp(pm, "previsoes_4sem", "y_parcial_carga_atual", ["otica", "se_alvo"])
    # parcial de MT suprimido ⇒ chain-ladder e Bornhuetter-Ferguson de MT vazios (parcial = F·CL − (CL − BF))
    mt_sup = nh[(nh["cod_regiao"] == "MT") & (nh["parcial_processado"] == "")][["alvo", "se"]].drop_duplicates()
    x = nh[(nh["cod_regiao"] == "MT") & nh["metodo"].isin(["cl", "bf"])].merge(mt_sup, on=["alvo", "se"])
    if (x["y_nowcast"] != "").any():
        falha(f"nowcast_hoje: CL/BF de MT publicados com o parcial de MT suprimido ({x[x['y_nowcast'] != ''][['alvo', 'se', 'metodo']].values.tolist()[:4]})")
    else:
        ok(f"nowcast_hoje: CL e BF de MT vazios nas {len(mt_sup)} SE com o parcial de MT suprimido")
    # nenhum arquivo traz o TIPO de supressão (primária/complementar)
    tipo = [f"{n}:{c}" for n, d_ in D.items() for c in d_.columns if c.endswith("_supressao")]
    if tipo:
        falha(f"colunas com o tipo de supressão: {tipo}")
    else:
        ok("nenhum arquivo publica o tipo de supressão (só a marca booleana)")
    # parcial idêntico entre os métodos da mesma região-semana
    par = nh.groupby(["alvo", "cod_regiao", "se"])["parcial_processado"].nunique()
    if (par > 1).any():
        falha("nowcast_hoje: parcial_processado difere entre métodos da mesma região-semana")
    # séries semanais dos dois arquivos: mesmas células suprimidas e mesmos valores nas semanas em comum
    a = so[so["otica"] == "ocorrencia"][["cod_regiao", "ano_se", "se", "internacoes_j00_j99", "internacoes_suprimido"]]
    b = sc[sc["alvo"] == "j00_j99"][["cod_regiao", "ano_se", "se", "internacoes", "internacoes_suprimido"]]
    m = a.merge(b, on=["cod_regiao", "ano_se", "se"])
    dif_sup = (m["internacoes_suprimido_x"] != m["internacoes_suprimido_y"]).sum()
    if dif_sup:
        falha(f"séries semanais: {dif_sup} célula(s) suprimida(s) em um arquivo e publicada(s) no outro")
    else:
        ok(f"séries semanais (baseline × carga de 17/10): mesmas células suprimidas em {len(m)} região-semanas comuns")
    m_pub = m[(m["internacoes_j00_j99"] != "") & (m["internacoes"] != "")]
    m26 = m_pub[m_pub["ano_se"] != "2026"]
    if (num(m26["internacoes_j00_j99"]) != num(m26["internacoes"])).any():
        falha("séries semanais: valores de 2024–2025 diferentes entre os dois arquivos")
    q = pm[["cod_regiao", "se_alvo", "y_parcial_carga_atual_suprimido"]].rename(columns={"se_alvo": "se"})
    q = q[pm["otica"] == "ocorrencia"].merge(b[b["ano_se"] == "2026"], on=["cod_regiao", "se"])
    if (q["y_parcial_carga_atual_suprimido"] != q["internacoes_suprimido"]).any():
        falha("parcial do baseline (SE 13–16/2026) e série de hoje suprimem regiões diferentes")
    else:
        ok("parcial do baseline (SE 13–16/2026) e série de hoje suprimem as mesmas regiões")
    # cópias do ingênuo sazonal (previsão de hoje) × contagem copiada (mesma SE de 2025)
    for alvo in ("j00_j99", "j00_j99_menor5"):
        ci = ph[(ph["metodo"] == "ingenuo_sazonal") & (ph["alvo"] == alvo)][["cod_regiao", "se", "y_previsto"]]
        orig = sc[(sc["alvo"] == alvo) & (sc["ano_se"] == "2025")][["cod_regiao", "se", "internacoes"]]
        x = ci.merge(orig, on=["cod_regiao", "se"], how="left").fillna("")
        vaz = x["internacoes"] == ""
        pub = x["y_previsto"] != ""
        pub_sem_orig = pub & vaz
        ambos = pub & ~vaz
        dif = (num(x.loc[ambos, "y_previsto"]) - num(x.loc[ambos, "internacoes"])).abs() > 1e-6
        if pub_sem_orig.any() or dif.any():
            falha(f"previsao_hoje ({alvo}): cópia do ingênuo sazonal publicada sem a contagem copiada ou com valor diferente")
        else:
            ok(f"previsao_hoje ({alvo}): cópias do ingênuo sazonal coerentes com a série de 2025")
    # cópias dos ingênuos do baseline (SE 13–16/2026) × série observada
    for mod, ano_ref, se_ref in (("ingenuo_sazonal", "2025", None), ("ingenuo_ultima", "2026", "12")):
        ci = p4[(p4["modelo"] == mod)][["otica", "cod_regiao", "se_alvo", "y_prev"]].copy()
        ci["se"] = ci["se_alvo"] if se_ref is None else se_ref
        orig = so[so["ano_se"] == ano_ref][["otica", "cod_regiao", "se", "internacoes_j00_j99"]]
        x = ci.merge(orig, on=["otica", "cod_regiao", "se"], how="left")
        vaz = x["internacoes_j00_j99"].isna() | (x["internacoes_j00_j99"] == "")
        if ((x["y_prev"] != "") & vaz).any():
            falha(f"previsoes_4sem: cópia de {mod} publicada com a contagem copiada suprimida")
        else:
            ok(f"previsoes_4sem: cópias de {mod} só publicadas quando a contagem copiada é publicada")

    # ---- 4. MT = soma das regiões --------------------------------------------------------------------
    print("\n4. Mato Grosso = soma das regiões")
    for met in ("ml", "cl", "bf"):
        conferir_soma_mt(nh[nh["metodo"] == met], "nowcast_hoje (" + met + ")", "y_nowcast", ["alvo", "se"])
    for met in ("encadeado_ml", "encadeado_cl", "sem_nowcast_lgbm"):
        conferir_soma_mt(ph[ph["metodo"] == met], "previsao_hoje (" + met + ")", "y_previsto", ["alvo", "se"])

    return fim(org, D, gravar=not args.so_conferir)


def fim(org: dict, D: dict, gravar: bool) -> int:
    if FALHAS:
        print(f"\n{len(FALHAS)} FALHA(S). Nada foi gravado.")
        return 1
    print("\nTodas as conferências passaram.")
    if not gravar:
        print("(--so-conferir: nada gravado)")
        return 0
    SAIDA.mkdir(parents=True, exist_ok=True)
    esperados = set(ARQ) | set(DIC.values()) | {"meta.csv"}
    for p in SAIDA.glob("*"):
        if p.is_file() and p.name not in esperados:
            p.unlink()
    for nome, (k, _, _, _) in ARQ.items():
        shutil.copyfile(org[k] / nome, SAIDA / nome)
    for k, nome in DIC.items():
        shutil.copyfile(org[k] / nome, SAIDA / nome)
    # downloads: cópias exatas com nomes do site
    downs = {v[2] for v in ARQ.values()} | {"previsao_dicionario.csv"}
    for p in DOWN.glob("previsao_*.csv"):
        if p.name not in downs:
            p.unlink()
    for nome, (k, _, dn, _) in ARQ.items():
        shutil.copyfile(org[k] / nome, DOWN / dn)
    # dicionário dos downloads
    dic_or = {k: pd.read_csv(org[k] / n, dtype=str, keep_default_na=False).set_index("arquivo") for k, n in DIC.items()}
    linhas = []
    for nome, (k, cols, dn, desc) in ARQ.items():
        o = dic_or[k].loc[nome]
        sup = o.get("supressao", "") if k == "a5" else ("células suprimidas na origem: " + str(o.get("celulas_suprimidas", "")))
        linhas.append({
            "arquivo": dn, "arquivo_origem": nome,
            "versao": VERSAO_A5 if k == "a5" else VERSAO_NC,
            "conteudo": desc,
            "colunas": cols.replace(",", "; "),
            "descricao_colunas_origem": o.get("colunas", ""),
            "linhas": len(D[nome]),
            "supressao": sup,
            "status": ("Resultados PRELIMINARES da previsão de demanda (atividade A5): especificação em validação pelo "
                       "coordenador; publicação decidida em 17/10/2026; não é recomendação oficial nem alerta operacional. "
                       "Contagens observadas de 1 a 4 suprimidas, com supressão complementar auditada (o tipo de supressão "
                       "não é publicado); vazio = suprimido ou indisponível. Estimativas de modelo (previsões, nowcast e "
                       "limites de intervalo) são publicadas mesmo abaixo de 5; vp/fp/fn/vn e episódios do alerta contam "
                       "região-semanas e episódios, não pessoas."),
        })
    pd.DataFrame(linhas).to_csv(DOWN / "previsao_dicionario.csv", index=False, encoding="utf-8")
    # meta.csv: referências da página
    nh = D["a5nc_site_nowcast_hoje.csv"]; ph = D["a5nc_site_previsao_hoje.csv"]
    sc = D["a5nc_site_serie_completa_hoje.csv"]; so = D["a5_site_serie_observada.csv"]
    def ult(d: pd.DataFrame) -> pd.Series:
        x = d.assign(_a=d["ano_se"].astype(int), _s=d["se"].astype(int)).sort_values(["_a", "_s"])
        return x.iloc[-1]
    u_sc, u_so = ult(sc), ult(so)
    nh_se = nh["se"].astype(int); ph_se = ph["se"].astype(int)
    corte = sorted(set(nh["corte"]))
    meta = [
        ("versao_baseline", VERSAO_A5, "CSV de origem (coluna versao)"),
        ("versao_nowcast", VERSAO_NC, "CSV de origem (coluna versao)"),
        ("corte", corte[0], "a5nc_site_nowcast_hoje.csv (coluna corte)"),
        ("ano_corte", str(int(nh["ano_se"].astype(int).max())), "a5nc_site_nowcast_hoje.csv"),
        ("se_corte", str(int(nh_se[nh["atraso_semanas"].astype(int) == 0].max())), "a5nc_site_nowcast_hoje.csv (atraso 0)"),
        ("se_nowcast_ini", str(int(nh_se.min())), "a5nc_site_nowcast_hoje.csv"),
        ("se_nowcast_fim", str(int(nh_se.max())), "a5nc_site_nowcast_hoje.csv"),
        ("ultima_se_completa", f"{int(u_sc['se'])}/{u_sc['ano_se']}", "a5nc_site_serie_completa_hoje.csv"),
        ("fim_ultima_se_completa", u_sc["fim_se"], "a5nc_site_serie_completa_hoje.csv"),
        ("ultima_se_completa_baseline", f"{int(u_so['se'])}/{u_so['ano_se']}", "a5_site_serie_observada.csv"),
        ("se_previsao_ini", str(int(ph_se.min())), "a5nc_site_previsao_hoje.csv"),
        ("se_previsao_fim", str(int(ph_se.max())), "a5nc_site_previsao_hoje.csv"),
        ("inicio_previsao", ph["inicio_se"].min(), "a5nc_site_previsao_hoje.csv"),
        ("fim_previsao", ph["fim_se"].max(), "a5nc_site_previsao_hoje.csv"),
    ] + [(k, v, f) for k, (v, f) in META_FIXA.items()] + [
        ("preparado_em", dt.datetime.now().strftime("%d/%m/%Y %H:%M"), "scripts/08_preparar_previsao.py"),
    ] + [(f"sha256:{n}", sha256(SAIDA / n), "cópia em dados_site/previsao") for n in ARQ]
    pd.DataFrame(meta, columns=["chave", "valor", "fonte"]).to_csv(SAIDA / "meta.csv", index=False, encoding="utf-8")
    print(f"Gravados: {len(ARQ) + len(DIC) + 1} arquivos em {SAIDA.relative_to(RAIZ)} e {len(downs)} em {DOWN.relative_to(RAIZ)} (previsao_*.csv)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
