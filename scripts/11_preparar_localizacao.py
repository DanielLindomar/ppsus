# -*- coding: utf-8 -*-
"""
11_preparar_localizacao.py — Observatório PPSUS-MT, aba "Localização" (versão 0.4 do site, em preparação)

COPIA e VALIDA os arquivos agregados da frente de localização de serviços de saúde (pilotos de
atenção ao parto e de UTI adulto, cadeia L1–L5; relatório "Resultados_Localizacao_Pilotos", versão
localizacao_pilotos_2026-10-17, revisão 1). Os arquivos de origem saem do pipeline da equipe
(08_site.py) com supressão primária das contagens observadas de 1 a 4. Este script não recalcula
nenhum resultado: copia, confere e PARA (código de saída 1) se alguma conferência falhar, sem deixar
cópia parcial.

Origem (pasta `site` dos resultados da frente, fora do repositório): informe por --origem, pela
variável de ambiente PPSUS_LOC_ORIGEM ou pela linha PPSUS_LOC_ORIGEM=<pasta> no .env.local
(ver scripts/config_local.py).

Saídas
  dados_site/localizacao/<nome>.csv          os 12 arquivos agregados usados pelas páginas localizacao/*.qmd
  dados_site/localizacao/dicionario_localizacao.csv  dicionário de colunas (o da origem, com as notas abaixo)
  dados_site/localizacao/manifesto.csv       arquivo, linhas, SHA-256 da origem e da cópia, transformação
  arquivos/dados/localizacao_*.csv           downloads (mesmo conteúdo de dados_site/localizacao)

Transformações (as únicas; todas reduzem o que é divulgado, nenhuma recalcula resultado):
  T1 acesso_atual_mun: SUPRESSÃO COMPLEMENTAR. Na origem, as células de 1 a 4 (numerador dos
     percentuais de atendidos no próprio município, fora da região e fora de MT, 2024–2025) estão
     vazias, mas parte delas pode ser deduzida por diferença: a demanda do município (publicada) é a
     soma de "próprio município + mesma região + fora da região + fora de MT", e os totais por região
     de saúde (acesso_regiao) dão a soma de cada coluna (fora de MT exata: n − n em MT). Na UTI adulto,
     nas regiões sem UTI SUS, "próprio" e "mesma região" são zero por construção, e o percentual fora
     da região publicado devolve o fora de MT suprimido. O script mede a dedutibilidade por propagação
     de intervalos (e confirma por programação inteira, scipy/HiGHS) e esvazia percentuais adicionais
     do MESMO tipo de arquivo até que nenhuma célula suprimida fique determinada. As células
     complementares ficam vazias como as primárias (sem rótulo que as distinga) e a linha recebe
     suprimido = true. Revisão de 18/10/2026: além de nenhuma célula determinada, nenhuma vazia pode ficar
     presa a dois valores consecutivos no modelo sem rótulo (quem lê sabe só que o zero é publicado); e os
     totais regionais podem estar suprimidos na origem (supressão regional da revisão 2 do 08_site.py da
     frente), entrando então só pela linha de Mato Grosso (co_regsaud 51) de acesso_regiao.
  T2 contagens MODELADAS arredondadas ao inteiro (nada em partos ou internações fracionários):
     cenarios_resumo.fluxo_para_novas e fluxo_para_novas_proprios_residentes;
     otimizacao_sensibilidade.demanda_mt_2030; uti_necessidade_regional.demanda_residentes_2030;
     otimizacao_solucoes.nao_atendida.
  T3 cenarios_ganho_mun: saem as colunas demanda_proj_2030_mt (demanda projetada ATENDIDA EM MT) e
     minutos_poupados_ano (= ganho × essa demanda). Divididas pela projeção municipal de 2030
     (projecao_demanda), devolvem a parcela observada atendida fora de MT de cada município e, com a
     demanda 2024–2025 publicada, uma estimativa (erro típico de meia unidade) das contagens fora de MT
     que estão suprimidas. A página usa só o ganho por paciente e os tempos médios.
  Os demais arquivos são cópia byte a byte.

Fica de FORA, por decisão do coordenador (17/10/2026): a tabela de hospitais que perderiam demanda com
escore DEA (localizacao.l5_hospitais_dea), que não está na pasta de origem; o script confere que nenhum
arquivo copiado tem CNES, nome de hospital ou escore DEA.

Conferências (qualquer falha interrompe o script):
  1. os 13 arquivos presentes, colunas exatamente as esperadas, dicionário cobrindo todas as colunas;
  2. contagens observadas inteiras, não negativas e NENHUMA de 1 a 4 (supressão primária);
  3. marca `suprimido` coerente com os percentuais vazios; tempos e percentuais vazios onde a demanda é 0;
  4. soma das demandas municipais = demanda da região (acesso_regiao);
  5. supressão complementar intacta na cópia: nenhuma célula suprimida com valor único possível
     (propagação de intervalos e mínimo = máximo por programação inteira), nenhuma presa a dois valores
     (modelo sem rótulo) e nenhum total regional suprimido fixado; supressão regional (revisão 2 da origem):
     linha de MT = soma das regiões, nenhum % regional implicando contagem de 1 a 4, regiões sem o serviço
     com fora da região e fora de MT vazios juntos e complementar de fora de MT com S − (k − 1) ≥ 5;
  6. projeções inteiras, intervalo contendo o valor projetado, 142 municípios × 16 regiões × MT × 2026–2030,
     marcadas como provisórias; contagens modeladas inteiras depois de T2;
  7. coerência da validação por experimento natural (vence + empata + perde = eventos avaliáveis;
     linha "todos" = soma dos tipos) e da escolha do L1 (modelo do arquivo de projeção);
  8. nenhum caminho local (unidade de disco, ppsus_repo) nem coluna de hospital/DEA nos arquivos copiados.

Uso (a partir da raiz do repositório):
    python scripts/11_preparar_localizacao.py --origem <pasta site dos resultados de localização>
Requisitos: Python 3.12, pandas, numpy, scipy (>= 1.9, para a conferência por programação inteira).
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import math
import os
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
SAIDA = RAIZ / "dados_site" / "localizacao"
DOWN = RAIZ / "arquivos" / "dados"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from config_local import caminho  # noqa: E402

# ----------------------------------------------------------------------------
# Contrato: arquivos, colunas esperadas e nome do download
# ----------------------------------------------------------------------------
ARQS = {
    "acesso_atual_mun": ("localizacao_acesso_municipios_2025.csv",
        "piloto,cod_mun6,nome_municipio,co_regsaud,nome_regsaud,pop_alvo,leitos_proprios,tempo_servico_min,km_servico,"
        "e2sfca_60,e2sfca_120,indice_60,indice_120,unidade_contagem,n_2024_2025,tempo_medio_obs_min,km_medio_obs,"
        "pct_proprio_mun,pct_fora_regiao,pct_fora_mt,suprimido"),
    "acesso_regiao": ("localizacao_acesso_regioes_2025.csv",
        "piloto,co_regsaud,pop_alvo,leitos_servico_2025,municipios_com_servico,n_2024_2025,n_em_mt,tempo_medio_obs_min,"
        "km_medio_obs,pct_proprio_mun,pct_fora_regiao,pct_fora_mt,indice_60,pct_pop_ate_60min,indice_120,"
        "pct_pop_ate_120min,nome_regsaud,unidade_contagem,suprimido"),
    "projecao_demanda": ("localizacao_demanda_projetada_2026_2030.csv",
        "piloto,nivel,codigo,nome,ano,demanda_proj,li80,ls80,demanda_proj_calib_ibge,modelo,provisorio"),
    "validacao_demanda": ("localizacao_validacao_demanda.csv",
        "piloto,modelo,mae,rmse,wmape,wmape_regiao,erro_total_pct"),
    "validacao_escolha_temporal": ("localizacao_validacao_escolha_temporal.csv",
        "piloto,modelo,cpc,wmape_destino,acerto_principal_destino,tempo_medio_obs,tempo_medio_prev"),
    "validacao_escolha_experimentos": ("localizacao_validacao_escolha_experimentos.csv",
        "piloto,tipo,n_eventos,n_avaliaveis,cpc_medio_gravitacional_mnl,cpc_medio_lightgbm_pares,cpc_medio_pivo_mnl,"
        "cpc_medio_pivo_lightgbm,cpc_medio_persistencia,n_pivo_mnl_vence_margem,n_pivo_mnl_empata_margem,"
        "n_pivo_mnl_perde_margem"),
    "validacao_escolha_experimentos_ano": ("localizacao_validacao_escolha_experimentos_ano.csv",
        "piloto,ano_evento,anos_ajuste,anos_teste,n_eventos,n_avaliaveis,tipos,cpc_medio_pivo_mnl,cpc_medio_persistencia,"
        "n_pivo_vence,n_pivo_vence_margem,n_empate_margem,n_pivo_perde_margem,dif_cpc_mediana"),
    "otimizacao_solucoes": ("localizacao_otimizacao_solucoes_2030.csv",
        "piloto,modelo,limiar_min,k,abertos,nomes_abertos,tempo_medio,km_medio,pct_ate_60,pct_ate_120,"
        "ganho_tempo_medio_min,ganho_pct_ate_60,ganho_pct_ate_120,nao_atendida,leitos_deficit,tempo_medio_atendida,provisorio"),
    "otimizacao_sensibilidade": ("localizacao_otimizacao_sensibilidade_2030.csv",
        "piloto,modelo,limiar_min,variante,k,demanda_mt_2030,objetivo_sem_unidade_nova,abertos,nomes_abertos,objetivo,"
        "segunda_abertos,segunda_nomes,segunda_objetivo,dif_pct_objetivo,dif_pct_ganho,objetivo_tipo,quase_empate,"
        "igual_principal,provisorio"),
    "uti_necessidade_regional": ("localizacao_uti_leitos_regioes_2030.csv",
        "co_regsaud,demanda_residentes_2030,leitos_uti_sus_2025,leitos_necessarios_2030,saldo_leitos,nome_regsaud,"
        "permanencia_media_dias,ocupacao_alvo,demanda_residentes_2025_obs,leitos_necessarios_2025_obs,"
        "saldo_leitos_2025_obs,provisorio"),
    "cenarios_resumo": ("localizacao_cenarios_resumo_2030.csv",
        "piloto,cenario,modelo_l4,k,abertos,nomes_abertos,modulo_leitos,tempo_medio_esperado,km_medio_esperado,"
        "pct_ate_60,pct_ate_120,fluxo_para_novas,fluxo_para_novas_proprios_residentes,ganho_tempo_esperado_min,"
        "ganho_tempo_mais_proximo_min,ganho_tempo_mais_proximo_l4_min,ganho_pct_ate_60,ganho_pct_ate_120,"
        "ocupacao_implicita_media,ocupacao_implicita_max,destinos_ocupacao_acima_100pct,tempo_medio_esperado_capacidade,"
        "ganho_tempo_esperado_capacidade_min,provisorio"),
    "cenarios_ganho_mun": ("localizacao_cenarios_ganho_municipios_2030.csv",
        "piloto,cenario,cod_mun6,nome_municipio,nome_regsaud,demanda_proj_2030_mt,tempo_medio_ref,tempo_medio_cenario,"
        "ganho_min_por_paciente,minutos_poupados_ano,provisorio"),
}
DIC_ORIGEM = "dicionario_site"
DIC_SAIDA = "dicionario_localizacao"
DOWN_DIC = "localizacao_dicionario.csv"

# T2: contagens modeladas arredondadas ao inteiro
RETIRA = {"cenarios_ganho_mun": ["demanda_proj_2030_mt", "minutos_poupados_ano"]}
ARREDONDA = {
    "cenarios_resumo": ["fluxo_para_novas", "fluxo_para_novas_proprios_residentes"],
    "otimizacao_sensibilidade": ["demanda_mt_2030"],
    "uti_necessidade_regional": ["demanda_residentes_2030"],
    "otimizacao_solucoes": ["nao_atendida"],
}
# Notas acrescentadas ao dicionário copiado (arquivo, coluna) -> texto acrescentado ao fim da descrição
NOTAS_DIC = {
    ("acesso_atual_mun.csv", "pct_proprio_mun"): " No site, também vazio por supressão complementar (para que nenhuma célula suprimida seja deduzida por diferença).",
    ("acesso_atual_mun.csv", "pct_fora_regiao"): " No site, também vazio por supressão complementar.",
    ("acesso_atual_mun.csv", "pct_fora_mt"): " No site, também vazio por supressão complementar.",
    ("acesso_atual_mun.csv", "suprimido"): " No site, também true quando a linha recebeu supressão complementar (as duas não são distinguidas).",
    ("cenarios_resumo.csv", "fluxo_para_novas"): " Arredondado ao inteiro no site.",
    ("cenarios_resumo.csv", "fluxo_para_novas_proprios_residentes"): " Arredondado ao inteiro no site.",
    ("otimizacao_sensibilidade.csv", "demanda_mt_2030"): " Arredondada ao inteiro no site.",
    ("uti_necessidade_regional.csv", "demanda_residentes_2030"): " Arredondada ao inteiro no site.",
    ("otimizacao_solucoes.csv", "nao_atendida"): " Arredondada ao inteiro no site.",
}
PILOTOS = ("parto", "uti")
CAT = {"P": "pct_proprio_mun", "R": "pct_fora_regiao", "F": "pct_fora_mt"}
MT_REG = 51  # linha de Mato Grosso (total do estado) em acesso_regiao (revisão 2 da origem, 18/10/2026)
EPS = 1e-9

FALHAS: list[str] = []


def confere(cond: bool, msg: str) -> bool:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FALHA {msg}")
        FALHAS.append(msg)
    return bool(cond)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def inteiro(s: pd.Series) -> bool:
    v = s.dropna().astype(float)
    return bool(((v % 1) == 0).all())


def sem_1_a_4(s: pd.Series) -> bool:
    v = s.dropna().astype(float)
    return not bool(((v > 0) & (v < 5)).any())


# ----------------------------------------------------------------------------
# Dedutibilidade das células suprimidas (acesso_atual_mun × acesso_regiao)
# ----------------------------------------------------------------------------
def iv_pct(n: int, p: float) -> tuple[int, int]:
    """Contagens inteiras compatíveis com o percentual p (1 casa decimal) sobre a base n."""
    if p == 0:
        return (0, 0)
    if p == 100:
        return (n, n)
    return (max(0, math.ceil(n * (p - 0.05) / 100 - EPS)), min(n, math.floor(n * (p + 0.05) / 100 + EPS)))


def modelo_celulas(a: pd.DataFrame, r: pd.DataFrame, piloto: str, compl=frozenset(), sem_rotulo: bool = False):
    """Variáveis (cod_mun6, categoria) com intervalos e as relações aditivas conhecidas por quem lê os arquivos.
    Categorias: P próprio município, M mesma região (outro município; não publicado), R fora da região (em MT),
    F fora de MT. Primárias (vazias com demanda >= 5) valem 1 a 4; complementares, 0 a n. Com sem_rotulo=True
    (quem lê não sabe quais vazias são primárias, mas sabe que o zero é publicado): toda vazia vale de 1 a n.
    UTI (pior caso para quem divulga): sem leito no município => P = 0; nenhum outro município da região com leito
    => M = 0 (o SIH não registra UTI adulto onde não há leito)."""
    x = a[a.piloto == piloto].reset_index(drop=True)
    rg = r[r.piloto == piloto].set_index("co_regsaud")
    B: dict = {}
    prim: set = set()
    cons: list = []
    com_leito = set(x.loc[x.leitos_proprios > 0, "cod_mun6"].astype(int))
    for _, m in x.iterrows():
        n = int(m.n_2024_2025)
        cod = int(m.cod_mun6)
        if n == 0:
            for c in "PMRF":
                B[(cod, c)] = (0, 0)
            continue
        for c, col in CAT.items():
            if (cod, c) in compl:
                B[(cod, c)] = (1, n) if sem_rotulo else (0, n)
            elif pd.isna(m[col]):
                B[(cod, c)] = (1, n) if sem_rotulo else (1, 4)
                prim.add((cod, c))
            else:
                B[(cod, c)] = iv_pct(n, float(m[col]))
        B[(cod, "M")] = (0, n)
        if piloto == "uti":
            if cod not in com_leito and (cod, "P") not in prim:
                B[(cod, "P")] = (0, 0)
            outros = x[(x.co_regsaud == m.co_regsaud) & (x.cod_mun6 != cod)].cod_mun6.astype(int)
            if not (set(outros) & com_leito):
                B[(cod, "M")] = (0, 0)
        cons.append(([(cod, c) for c in "PMRF"], (n, n)))
    # Totais por região (revisão 2, 18/10/2026): o percentual regional pode estar SUPRIMIDO (vazio). Nas regiões sem
    # o serviço, o próprio município vazio é estrutural (= 0); qualquer outro vazio regional é desconhecido e só entra
    # pela linha de Mato Grosso (co_regsaud 51: total do estado, exato em fora de MT e com 1 casa nos percentuais).
    sem_serv = {k for k, v in rg.municipios_com_servico.items() if v == 0}
    desconhecidas = {"P": [], "R": [], "F": []}
    pub_tot = {"P": [0, 0], "R": [0, 0], "F": [0, 0]}
    for reg, xr in x.groupby("co_regsaud"):
        rr = rg.loc[reg]
        nreg = int(rr.n_2024_2025)
        cods = [int(c) for c in xr.cod_mun6]
        if pd.isna(rr.pct_proprio_mun) and reg in sem_serv:
            tp = (0, 0)
        elif pd.isna(rr.pct_proprio_mun):
            tp = None
        else:
            tp = iv_pct(nreg, float(rr.pct_proprio_mun))
        tr = None if pd.isna(rr.pct_fora_regiao) else iv_pct(nreg, float(rr.pct_fora_regiao))
        tf = None if (pd.isna(rr.n_em_mt) or pd.isna(rr.pct_fora_mt)) else (nreg - int(rr.n_em_mt),) * 2
        for k_, t_ in (("P", tp), ("R", tr), ("F", tf)):
            if t_ is None:
                desconhecidas[k_] += [(c, k_) for c in cods]
            else:
                cons.append(([(c, k_) for c in cods], t_))
                pub_tot[k_][0] += t_[0]; pub_tot[k_][1] += t_[1]
        if tp is not None and tr is not None and tf is not None:
            cons.append(([(c, "M") for c in cods], (nreg - tp[1] - tr[1] - tf[0], nreg - tp[0] - tr[0] - tf[0])))
    # Mato Grosso: soma das regiões com o total suprimido = total do estado − regiões publicadas
    if MT_REG in rg.index:
        mt = rg.loc[MT_REG]
        nmt = int(mt.n_2024_2025)
        tot = {"P": iv_pct(nmt, float(mt.pct_proprio_mun)), "R": iv_pct(nmt, float(mt.pct_fora_regiao)),
               "F": (nmt - int(mt.n_em_mt),) * 2}
        for k_, vs in desconhecidas.items():
            if vs:
                lo_, hi_ = tot[k_]
                cons.append((vs, (max(0, lo_ - pub_tot[k_][1]), hi_ - pub_tot[k_][0])))
    return B, prim, cons


def propaga(B: dict, cons: list, maxit: int = 500):
    B = dict(B)
    for _ in range(maxit):
        mudou = False
        for vs, (tl, tu) in cons:
            slo = sum(B[v][0] for v in vs)
            shi = sum(B[v][1] for v in vs)
            for v in vs:
                lo, hi = B[v]
                nlo, nhi = max(lo, tl - (shi - hi)), min(hi, tu - (slo - lo))
                if (nlo, nhi) != (lo, hi):
                    if nlo > nhi:
                        return None
                    B[v] = (nlo, nhi)
                    slo += nlo - lo
                    shi += nhi - hi
                    mudou = True
        if not mudou:
            break
    return B


def dedutiveis(a, r, piloto, compl=frozenset()):
    B, prim, cons = modelo_celulas(a, r, piloto, compl)
    P = propaga(B, cons)
    if P is None:
        raise RuntimeError(f"{piloto}: relações aditivas inconsistentes (modelo de dedução)")
    return sorted(v for v in prim if P[v][0] == P[v][1]), P, prim, B


def limites_exatos(a, r, piloto, compl=frozenset()):
    """Mínimo e máximo de cada célula primária por programação inteira (scipy.optimize.milp/HiGHS)."""
    from scipy.optimize import Bounds, LinearConstraint, milp
    from scipy.sparse import lil_matrix
    B, prim, cons = modelo_celulas(a, r, piloto, compl)
    vs = sorted(B)
    idx = {v: i for i, v in enumerate(vs)}
    A = lil_matrix((len(cons), len(vs)))
    lo_c, hi_c = [], []
    for j, (vv, (tl, tu)) in enumerate(cons):
        for v in vv:
            A[j, idx[v]] = 1
        lo_c.append(tl)
        hi_c.append(tu)
    lc = LinearConstraint(A.tocsr(), lo_c, hi_c)
    bd = Bounds([B[v][0] for v in vs], [B[v][1] for v in vs])
    integ = np.ones(len(vs))
    out = {}
    for v in sorted(prim):
        c = np.zeros(len(vs))
        c[idx[v]] = 1
        r1 = milp(c, constraints=lc, bounds=bd, integrality=integ)
        r2 = milp(-c, constraints=lc, bounds=bd, integrality=integ)
        if not (r1.success and r2.success):
            raise RuntimeError(f"{piloto}: programação inteira sem solução para {v}")
        out[v] = (round(r1.fun), round(-r2.fun))
    return out


def limites_sem_rotulo(a, r, piloto, compl=frozenset()):
    """Mínimo e máximo de cada célula vazia (primária ou complementar) no modelo SEM rótulo (revisão de 18/10/2026):
    serve à exigência de largura mínima — nenhuma vazia presa a dois valores consecutivos."""
    from scipy.optimize import Bounds, LinearConstraint, milp
    from scipy.sparse import lil_matrix
    B, prim, cons = modelo_celulas(a, r, piloto, compl, sem_rotulo=True)
    alvo = sorted(set(prim) | set(compl))
    vs = sorted(B)
    idx = {v: i for i, v in enumerate(vs)}
    A = lil_matrix((len(cons), len(vs)))
    lo_c, hi_c = [], []
    for j, (vv, (tl, tu)) in enumerate(cons):
        for v in vv:
            A[j, idx[v]] = 1
        lo_c.append(tl)
        hi_c.append(tu)
    lc = LinearConstraint(A.tocsr(), lo_c, hi_c)
    bd = Bounds([B[v][0] for v in vs], [B[v][1] for v in vs])
    integ = np.ones(len(vs))
    out = {}
    for v in alvo:
        c = np.zeros(len(vs))
        c[idx[v]] = 1
        r1 = milp(c, constraints=lc, bounds=bd, integrality=integ)
        r2 = milp(-c, constraints=lc, bounds=bd, integrality=integ)
        if not (r1.success and r2.success):
            raise RuntimeError(f"{piloto}: programação inteira (sem rótulo) sem solução para {v}")
        out[v] = (round(r1.fun), round(-r2.fun))
    return out


def limites_regionais(a, r, piloto, compl=frozenset()):
    """Mínimo e máximo, por programação inteira, de cada total REGIONAL suprimido (soma das células municipais da
    região), com as mesmas relações de modelo_celulas (inclusive a linha de Mato Grosso)."""
    from scipy.optimize import Bounds, LinearConstraint, milp
    from scipy.sparse import lil_matrix
    B, prim, cons = modelo_celulas(a, r, piloto, compl)
    vs = sorted(B)
    idx = {v: i for i, v in enumerate(vs)}
    A = lil_matrix((len(cons), len(vs)))
    lo_c, hi_c = [], []
    for j, (vv, (tl, tu)) in enumerate(cons):
        for v in vv:
            A[j, idx[v]] = 1
        lo_c.append(tl)
        hi_c.append(tu)
    lc = LinearConstraint(A.tocsr(), lo_c, hi_c)
    bd = Bounds([B[v][0] for v in vs], [B[v][1] for v in vs])
    integ = np.ones(len(vs))
    x = a[a.piloto == piloto]
    rg = r[(r.piloto == piloto) & (r.co_regsaud != MT_REG)]
    out = {}
    for _, rr in rg.iterrows():
        cods = [int(c) for c in x[x.co_regsaud == rr.co_regsaud].cod_mun6]
        for k_, col in CAT.items():
            if not pd.isna(rr[col]) or (k_ == "P" and rr.municipios_com_servico == 0):
                continue
            c = np.zeros(len(vs))
            for cod in cods:
                c[idx[(cod, k_)]] = 1
            r1 = milp(c, constraints=lc, bounds=bd, integrality=integ)
            r2 = milp(-c, constraints=lc, bounds=bd, integrality=integ)
            if not (r1.success and r2.success):
                raise RuntimeError(f"{piloto}: programação inteira sem solução para o total regional {rr.co_regsaud} {col}")
            out[(int(rr.co_regsaud), col)] = (round(r1.fun), round(-r2.fun))
    return out


def supressao_complementar(a, r) -> tuple[pd.DataFrame, dict]:
    """Esvazia percentuais adicionais até nenhuma célula primária ficar determinada. Determinístico."""
    a = a.copy()
    resumo = {}
    for piloto in PILOTOS:
        x = a[a.piloto == piloto]
        reg = dict(zip(x.cod_mun6.astype(int), x.co_regsaud))
        nn = dict(zip(x.cod_mun6.astype(int), x.n_2024_2025.astype(int)))
        lp = dict(zip(x.cod_mun6.astype(int), x.leitos_proprios))
        compl: set = set()
        vz0 = dedutiveis(a, r, piloto)[0]

        def livre(w, prim):
            """Célula que pode receber supressão complementar (publicada, não estrutural, demanda >= 5)."""
            return (w not in prim and w not in compl and nn[w[0]] >= 5
                    and not (piloto == "uti" and w[1] == "P" and lp[w[0]] == 0))

        def parceiros(cod, c, P, prim, extra=frozenset()):
            """Se a linha do município fixaria a célula (cod, c), devolve a célula da mesma linha a esvaziar junto."""
            outras = [(cod, k) for k in "PMRF" if k != c]
            if any(P[v][0] != P[v][1] or v in prim or v in compl or v in extra for v in outras):
                return []
            cand = sorted((w for w in outras if w[1] != "M" and livre(w, prim)), key=lambda w: (P[w][0], w))
            return cand[:1]

        for _ in range(200):
            vz, P, prim, B0 = dedutiveis(a, r, piloto, frozenset(compl))
            if not vz:
                # revisão de 18/10/2026: além de não fixada, nenhuma vazia pode ficar presa a dois valores consecutivos
                # (largura máxima − mínima ≤ 1) no modelo sem rótulo; esvazia, na mesma coluna e região, a menor contagem
                # publicada não nula (e a parceira da linha, se a linha a fixaria)
                ls = limites_sem_rotulo(a, r, piloto, frozenset(compl))
                estreitas = sorted(v for v, (lo_, hi_) in ls.items() if hi_ - lo_ <= 1)
                if not estreitas:
                    break
                novos: set = set()
                for cod, c in estreitas:
                    col = sorted((w for w in ((m, c) for m in reg if reg[m] == reg[cod]) if livre(w, prim) and P[w][0] > 0),
                                 key=lambda w: (P[w][0], w))
                    if col:
                        w = col[0]
                        novos.add(w)
                        novos |= set(parceiros(w[0], w[1], P, prim, frozenset({w})))
                if not novos:
                    raise RuntimeError(f"{piloto}: sem candidato para alargar {estreitas[:3]}")
                compl |= novos
                continue
            novos: set = set()
            for cod, c in vz:
                linha = parceiros(cod, c, P, prim)
                if linha:                       # (a) a própria linha fixa a célula: esvazia outra célula da linha
                    novos |= set(linha)
                    continue
                # (b) a soma da região fixa a célula: esvazia, na mesma coluna e região, a menor contagem publicada
                #     não nula (e, se preciso, a célula parceira na linha dela)
                col = sorted((w for w in ((m, c) for m in reg if reg[m] == reg[cod]) if livre(w, prim)),
                             key=lambda w: (P[w][0] == 0, P[w][0], w))
                if col:
                    w = col[0]
                    novos.add(w)
                    novos |= set(parceiros(w[0], w[1], P, prim, frozenset({w})))
            if not novos:
                raise RuntimeError(f"{piloto}: supressão complementar sem candidato para {vz[:3]}")
            compl |= novos
        else:
            raise RuntimeError(f"{piloto}: supressão complementar não convergiu")
        for cod, c in compl:
            i = a.index[(a.piloto == piloto) & (a.cod_mun6 == cod)]
            a.loc[i, CAT[c]] = np.nan
            a.loc[i, "suprimido"] = True
        resumo[piloto] = dict(dedutiveis_origem=len(vz0), complementares=len(compl),
                              por_tipo={k: sum(1 for _, c in compl if c == k) for k in "PRF"})
    return a, resumo


# ----------------------------------------------------------------------------
# Conferências
# ----------------------------------------------------------------------------
def conferir_regional(r: pd.DataFrame, rotulo: str):
    """Supressão REGIONAL (revisão 2 da origem, 18/10/2026): nenhuma contagem implícita de 1 a 4 (fora de MT = n − n em MT;
    % × n), regiões sem o serviço com fora da região e fora de MT vazios juntos, e supressão complementar de fora de MT
    suficiente diante do total exato de Mato Grosso (≥ 2 vazias e S − (k − 1) ≥ 5)."""
    print(f"[supressão regional: {rotulo}]")
    for p in PILOTOS:
        rp = r[r.piloto == p]
        reg = rp[rp.co_regsaud != MT_REG]
        mt = rp[rp.co_regsaud == MT_REG]
        if not confere(len(mt) == 1, f"{p}: linha de Mato Grosso (co_regsaud {MT_REG}) presente"):
            continue
        mt = mt.iloc[0]
        confere(int(reg.n_2024_2025.sum()) == int(mt.n_2024_2025) and abs(reg.leitos_servico_2025.sum() - mt.leitos_servico_2025) < 0.6
                and int(reg.municipios_com_servico.sum()) == int(mt.municipios_com_servico),
                f"{p}: linha de MT = soma das regiões (demanda, leitos e municípios com o serviço)")
        confere(bool((reg.n_em_mt.isna() == reg.pct_fora_mt.isna()).all()), f"{p}: n_em_mt e % fora de MT vazios juntos")
        fora = reg.n_2024_2025 - reg.n_em_mt
        confere(not bool(fora.between(1, 4).any()), f"{p}: n − n_em_mt (fora de MT) sem contagem de 1 a 4")
        ruins = []
        for c in CAT.values():
            for _, x in reg[reg[c].notna()].iterrows():
                lo, hi = iv_pct(int(x.n_2024_2025), float(x[c]))
                if lo >= 1 and hi <= 4:
                    ruins.append(f"{x.co_regsaud} {c}")
        confere(not ruins, f"{p}: nenhum % regional implica contagem de 1 a 4" + (f" ({ruins})" if ruins else ""))
        sem = reg[reg.municipios_com_servico == 0]
        confere(bool((sem.pct_fora_regiao.isna() == sem.pct_fora_mt.isna()).all()),
                f"{p}: regiões sem o serviço com fora da região e fora de MT vazios juntos")
        k = int(reg.pct_fora_mt.isna().sum())
        S = (int(mt.n_2024_2025) - int(mt.n_em_mt)) - float(fora.dropna().sum())
        confere(k == 0 or (k >= 2 and S - (k - 1) >= 5),
                f"{p}: complementar de fora de MT suficiente ({k} regiões vazias; soma S = {S:.0f}; S − (k − 1) ≥ 5)")


def conferir_acesso(a: pd.DataFrame, r: pd.DataFrame, rotulo: str):
    print(f"[acesso: {rotulo}]")
    for p in PILOTOS:
        x = a[a.piloto == p]
        confere(len(x) == 142 and x.cod_mun6.is_unique, f"{p}: 142 municípios, sem repetição")
        confere(len(r[(r.piloto == p) & (r.co_regsaud != MT_REG)]) == 16, f"{p}: 16 regiões de saúde (e a linha de MT)")
    conferir_regional(r, rotulo)
    confere(inteiro(a.n_2024_2025) and (a.n_2024_2025 >= 0).all() and a.n_2024_2025.notna().all(),
            "demanda municipal 2024–2025 inteira, não negativa e sempre informada")
    confere(sem_1_a_4(a.n_2024_2025), "demanda municipal sem contagem de 1 a 4")
    for c in ("n_2024_2025", "n_em_mt"):
        confere(inteiro(r[c]) and sem_1_a_4(r[c]), f"acesso_regiao.{c} inteiro e sem contagem de 1 a 4")
    pct = list(CAT.values())
    ok = True
    for _, m in a.iterrows():
        vazio = m[pct].isna()
        if m.n_2024_2025 == 0:
            ok &= bool(vazio.all()) and pd.isna(m.tempo_medio_obs_min)
        else:
            ok &= bool(vazio.any()) == bool(m.suprimido)
    confere(ok, "suprimido = true exatamente nas linhas com percentual vazio (demanda > 0); demanda 0 sem percentuais")
    vp = a[pct].to_numpy(dtype=float).ravel()
    vp = vp[~np.isnan(vp)]
    confere(bool(((vp >= 0) & (vp <= 100)).all()), "percentuais entre 0 e 100")
    s = a.groupby(["piloto", "co_regsaud"]).n_2024_2025.sum().reset_index()
    m = s.merge(r[["piloto", "co_regsaud", "n_2024_2025"]], on=["piloto", "co_regsaud"], suffixes=("_m", "_r"))
    confere(len(m) == 32 and bool((m.n_2024_2025_m == m.n_2024_2025_r).all()), "soma dos municípios = demanda da região (32 pares)")


def complementares(a: pd.DataFrame, a_origem: pd.DataFrame, piloto: str) -> frozenset:
    """Células vazias na cópia e publicadas na origem (pior caso: quem lê sabe quais são complementares)."""
    x = a[a.piloto == piloto].set_index("cod_mun6")
    o = a_origem[a_origem.piloto == piloto].set_index("cod_mun6")
    return frozenset((int(cod), c) for cod in x.index for c, col in CAT.items()
                     if pd.isna(x.at[cod, col]) and not pd.isna(o.at[cod, col]))


def conferir_dedutibilidade(a, r, a_origem, rotulo: str, exato: bool):
    print(f"[supressão complementar: {rotulo}]")
    tot = 0
    for p in PILOTOS:
        compl = complementares(a, a_origem, p)
        # as células primárias da cópia têm de ser exatamente as da origem
        prim_o = {(int(m.cod_mun6), c) for _, m in a_origem[a_origem.piloto == p].iterrows() for c, col in CAT.items()
                  if pd.isna(m[col]) and m.n_2024_2025 > 0}
        prim_c = {(int(m.cod_mun6), c) for _, m in a[a.piloto == p].iterrows() for c, col in CAT.items()
                  if pd.isna(m[col]) and m.n_2024_2025 > 0} - set(compl)
        confere(prim_o == prim_c, f"{p}: células suprimidas da origem continuam vazias na cópia ({len(prim_o)}; complementares {len(compl)})")
        vz = dedutiveis(a, r, p, compl)[0]
        tot += len(vz)
        confere(len(vz) == 0, f"{p}: nenhuma célula suprimida determinada por diferença (propagação; {len(vz)} encontradas)")
        if exato:
            lim = limites_exatos(a, r, p, compl)
            fix = [v for v, (lo, hi) in lim.items() if lo == hi]
            confere(len(fix) == 0, f"{p}: nenhuma célula suprimida com mínimo = máximo (programação inteira; {len(lim)} células)")
            ls = limites_sem_rotulo(a, r, p, compl)
            est = [v for v, (lo_, hi_) in ls.items() if hi_ - lo_ <= 1]
            confere(not est, f"{p}: nenhuma célula vazia presa a dois valores no modelo sem rótulo ({len(ls)} células; {est[:4]})")
            lr = limites_regionais(a, r, p, compl)
            fixr = {k: v for k, v in lr.items() if v[0] == v[1]}
            confere(not fixr, f"{p}: nenhum total REGIONAL suprimido com mínimo = máximo (programação inteira, com a linha de MT; "
                              f"{len(lr)} totais: {lr})")
    return tot


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--origem", help="pasta `site` dos resultados de localização")
    args = ap.parse_args()
    origem = Path(args.origem) if args.origem else caminho("PPSUS_LOC_ORIGEM", obrigatorio=False)
    if origem is None:
        raise SystemExit("Informe --origem, a variável de ambiente PPSUS_LOC_ORIGEM ou PPSUS_LOC_ORIGEM=<pasta> no .env.local.")
    origem = origem.resolve()
    print(f"Origem: pasta informada ({len(list(origem.glob('*.csv')))} CSV)")

    # 1. presença, colunas e dicionário
    print("[1. arquivos e colunas]")
    dfs = {}
    for nome, (_, cols) in ARQS.items():
        f = origem / f"{nome}.csv"
        if not confere(f.exists(), f"{nome}.csv presente"):
            continue
        d = pd.read_csv(f, encoding="utf-8")
        confere(list(d.columns) == cols.split(","), f"{nome}.csv: colunas esperadas ({len(d.columns)})")
        dfs[nome] = d
    fdic = origem / f"{DIC_ORIGEM}.csv"
    confere(fdic.exists(), f"{DIC_ORIGEM}.csv presente")
    if FALHAS:
        return fim()
    dic = pd.read_csv(fdic, encoding="utf-8")
    for nome, d in dfs.items():
        falta = [c for c in d.columns if not ((dic.arquivo == f"{nome}.csv") & (dic.coluna == c)).any()]
        confere(not falta, f"dicionário descreve todas as colunas de {nome}.csv" + (f" (faltam {falta})" if falta else ""))
    extras = sorted(set(p.stem for p in origem.glob("*.csv")) - set(ARQS) - {DIC_ORIGEM})
    confere(not extras, "nenhum arquivo além dos esperados na origem" + (f" (extras: {extras})" if extras else ""))

    # 8 (antecipada). nada de hospital/DEA nem caminho local
    print("[8. conteúdo proibido]")
    proib = re.compile(r"(^|_)(cnes|dea|escore|hospital|estabelecimento)(_|$)", re.I)
    cols_proib = [f"{n}.{c}" for n, d in dfs.items() for c in d.columns if proib.search(c)]
    confere(not cols_proib, "nenhuma coluna de hospital, CNES ou escore DEA" + (f" ({cols_proib})" if cols_proib else ""))
    loc = re.compile(r"[A-Za-z]:\\|ppsus_repo|\\Users\\", re.I)
    achou = [n for n in ARQS if loc.search((origem / f"{n}.csv").read_text(encoding="utf-8"))]
    confere(not achou, "nenhum caminho local nos arquivos" + (f" ({achou})" if achou else ""))

    # 2–4. acesso (origem)
    a0, r0 = dfs["acesso_atual_mun"], dfs["acesso_regiao"]
    conferir_acesso(a0, r0, "origem")
    if FALHAS:
        return fim()
    print("[5. dedutibilidade na ORIGEM (diagnóstico; corrigida pela T1)]")
    for p in PILOTOS:
        vz = dedutiveis(a0, r0, p)[0]
        print(f"  info {p}: {len(vz)} célula(s) suprimida(s) determinada(s) por diferença na origem")

    # T1 supressão complementar
    a1, res_t1 = supressao_complementar(a0, r0)
    for p, rr in res_t1.items():
        print(f"  T1 {p}: {rr['complementares']} percentuais esvaziados por supressão complementar "
              f"(próprio {rr['por_tipo']['P']}, fora da região {rr['por_tipo']['R']}, fora de MT {rr['por_tipo']['F']})")
    conferir_acesso(a1, r0, "cópia")
    conferir_dedutibilidade(a1, r0, a0, "cópia", exato=True)

    # 6. projeções e contagens modeladas
    print("[6. projeções e contagens modeladas]")
    pj = dfs["projecao_demanda"]
    for c in ("demanda_proj", "li80", "ls80", "demanda_proj_calib_ibge"):
        confere(inteiro(pj[c]) and pj[c].notna().all(), f"projecao_demanda.{c} inteiro e informado")
    confere(bool(((pj.li80 <= pj.demanda_proj) & (pj.demanda_proj <= pj.ls80)).all()), "intervalo de 80% contém a projeção")
    confere(sorted(pj.ano.unique()) == [2026, 2027, 2028, 2029, 2030], "anos 2026–2030")
    tam = pj.groupby(["piloto", "nivel"]).size().to_dict()
    confere(all(tam.get((p, n)) == k for p in PILOTOS for n, k in (("MT", 5), ("regiao", 80), ("municipio", 710))),
            "142 municípios, 16 regiões e MT por piloto e ano")
    confere(bool(pj.provisorio.astype(str).str.lower().eq("true").all()), "projeção marcada como provisória")
    reg_soma = pj[pj.nivel == "regiao"].groupby(["piloto", "ano"]).demanda_proj.sum()
    mt = pj[pj.nivel == "MT"].set_index(["piloto", "ano"]).demanda_proj
    confere(bool(((reg_soma - mt).abs() / mt < 0.005).all()), "soma das regiões = MT (tolerância 0,5% pelo arredondamento)")
    v1 = dfs["validacao_demanda"]
    for p in PILOTOS:
        modelo_proj = pj[pj.piloto == p].modelo.unique()
        confere(len(modelo_proj) == 1 and modelo_proj[0] in set(v1[v1.piloto == p].modelo),
                f"{p}: modelo da projeção ({modelo_proj[0]}) está na validação")
    copia = {n: d.copy() for n, d in dfs.items()}
    copia["acesso_atual_mun"] = a1
    for nome, cols in ARREDONDA.items():
        for c in cols:
            copia[nome][c] = copia[nome][c].round(0).astype("Int64")
    for nome, cols in ARREDONDA.items():
        for c in cols:
            confere(inteiro(copia[nome][c]), f"{nome}.{c} inteiro na cópia (T2)")
    for nome, cols in RETIRA.items():
        copia[nome] = copia[nome].drop(columns=cols)
        confere(not set(cols) & set(copia[nome].columns), f"{nome}: colunas {', '.join(cols)} retiradas da cópia (T3)")
    obs = dfs["uti_necessidade_regional"].demanda_residentes_2025_obs
    confere(inteiro(obs) and sem_1_a_4(obs), "uti_necessidade_regional: demanda observada 2025 inteira e sem contagem de 1 a 4")
    for n_, d in dfs.items():
        if "provisorio" in d.columns and n_ != "otimizacao_sensibilidade":
            confere(bool(d.provisorio.astype(str).str.lower().eq("true").all()), f"{n_}: marcado como provisório")

    # 7. validação
    print("[7. validação]")
    ex = dfs["validacao_escolha_experimentos"]
    ok = bool((ex.n_pivo_mnl_vence_margem + ex.n_pivo_mnl_empata_margem + ex.n_pivo_mnl_perde_margem == ex.n_avaliaveis).all())
    confere(ok, "experimentos: vence + empata + perde = eventos avaliáveis")
    for p in PILOTOS:
        t = ex[(ex.piloto == p) & (ex.tipo != "todos")]
        tt = ex[(ex.piloto == p) & (ex.tipo == "todos")].iloc[0]
        confere(all(int(t[c].sum()) == int(tt[c]) for c in ("n_eventos", "n_avaliaveis", "n_pivo_mnl_vence_margem")),
                f"{p}: linha 'todos' = soma dos tipos")
    ea = dfs["validacao_escolha_experimentos_ano"]
    for p in PILOTOS:
        confere(int(ea[ea.piloto == p].n_avaliaveis.sum()) == int(ex[(ex.piloto == p) & (ex.tipo == "todos")].n_avaliaveis.iloc[0]),
                f"{p}: eventos por ano somam os avaliáveis")
    so = dfs["otimizacao_solucoes"]
    confere(set(so.k) == {0, 1, 2, 3, 4, 5}, "otimização: k = 0 a 5")

    if FALHAS:
        return fim()

    # gravação atômica: pasta temporária -> destino
    tmp = Path(tempfile.mkdtemp(prefix="loc_", dir=RAIZ / "dados_site"))
    try:
        man = []
        for nome, (down, _) in ARQS.items():
            src = origem / f"{nome}.csv"
            dst = tmp / f"{nome}.csv"
            transf = []
            if nome == "acesso_atual_mun":
                transf.append("T1 supressão complementar")
            if nome in ARREDONDA:
                transf.append("T2 arredondamento de " + ", ".join(ARREDONDA[nome]))
            if nome in RETIRA:
                transf.append("T3 colunas retiradas: " + ", ".join(RETIRA[nome]))
            if transf:
                copia[nome].to_csv(dst, index=False, encoding="utf-8", lineterminator="\n")
            else:
                shutil.copyfile(src, dst)
            man.append(dict(arquivo=f"{nome}.csv", download=down, linhas=len(copia[nome]), sha256_origem=sha(src),
                            sha256_copia=sha(dst), transformacao="; ".join(transf) or "cópia idêntica"))
        dic2 = dic.copy()
        for nome, cols in RETIRA.items():
            dic2 = dic2[~((dic2.arquivo == f"{nome}.csv") & dic2.coluna.isin(cols))]
        for (arq, col), txt in NOTAS_DIC.items():
            i = (dic2.arquivo == arq) & (dic2.coluna == col)
            dic2.loc[i, "descricao"] = dic2.loc[i, "descricao"].astype(str) + txt
        dic2.to_csv(tmp / f"{DIC_SAIDA}.csv", index=False, encoding="utf-8", lineterminator="\n")
        man.append(dict(arquivo=f"{DIC_SAIDA}.csv", download=DOWN_DIC, linhas=len(dic2), sha256_origem=sha(fdic),
                        sha256_copia=sha(tmp / f"{DIC_SAIDA}.csv"),
                        transformacao="notas da supressão complementar e do arredondamento; sem as colunas retiradas (T3)"))
        pd.DataFrame(man).to_csv(tmp / "manifesto.csv", index=False, encoding="utf-8", lineterminator="\n")
        # conferência final sobre os arquivos gravados (lidos de novo)
        print("[conferência final da cópia gravada]")
        a2 = pd.read_csv(tmp / "acesso_atual_mun.csv", encoding="utf-8")
        r2 = pd.read_csv(tmp / "acesso_regiao.csv", encoding="utf-8")
        conferir_acesso(a2, r2, "cópia gravada")
        conferir_dedutibilidade(a2, r2, a0, "cópia gravada", exato=True)
        texto = "".join((tmp / f"{n}.csv").read_text(encoding="utf-8") for n in ARQS)
        confere(not loc.search(texto), "cópia sem caminho local")
        if FALHAS:
            return fim()
        if SAIDA.exists():
            shutil.rmtree(SAIDA)
        shutil.move(str(tmp), str(SAIDA))
    finally:
        if tmp.exists():
            shutil.rmtree(tmp, ignore_errors=True)
    DOWN.mkdir(parents=True, exist_ok=True)
    for nome, (down, _) in ARQS.items():
        shutil.copyfile(SAIDA / f"{nome}.csv", DOWN / down)
    shutil.copyfile(SAIDA / f"{DIC_SAIDA}.csv", DOWN / DOWN_DIC)
    print(f"Gravado: dados_site/localizacao ({len(ARQS) + 2} arquivos) e arquivos/dados/localizacao_*.csv ({len(ARQS) + 1} arquivos)")
    return fim()


def fim() -> int:
    if FALHAS:
        print(f"\n{len(FALHAS)} conferência(s) falharam; nada foi gravado.")
        return 1
    print("\nTodas as conferências OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
