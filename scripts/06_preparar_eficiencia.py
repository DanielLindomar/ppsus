# -*- coding: utf-8 -*-
"""
06_preparar_eficiencia.py — Observatório PPSUS-MT, seção "Eficiência" (versão 0.2.1 do site)

Lê os resultados de UMA versão da estimação DEA/Malmquist no PostgreSQL local (schema `dea`,
somente leitura; padrão versao = 'v2.1', escolhida por --versao) e grava o contrato de dados da
seção 2 de _planejamento/BRIEF_EFICIENCIA.md em dados_site/eficiencia/ (CSV UTF-8, vírgula,
decimal ponto, vazio = indisponível) e uma cópia para download em arquivos/dados/eficiencia/.

Versões conhecidas (VERSOES, abaixo): 'v2' (08/10/2026, publicada na versão 0.2 do site) e
'v2.1' (16/10/2026, decisão 13 do coordenador = opção (c): o modelo M1 reestimado com o insumo
de agentes comunitários restrito ao CBO 515105; M0, M2, M2A, M3, H e o painel de alta
complexidade são cópia exata da v2). A v2 continua no banco e pode ser regerada com --versao v2.

Arquivos do contrato
  fichas_municipio.csv   município × modelo (M1, M0, M2, M2A) × ano 2020–2025
  metas_municipio.csv    município × modelo × 2025 × variável
  pares_municipio.csv    município × modelo × 2025: até 3 pares plausíveis
  fichas_hospital.csv    hospital (CNES, texto de 7 dígitos) × ano 2020–2025
  metas_hospital.csv     hospital × 2025 × variável
  painel_ac_regiao.csv   painel de acesso e produção de alta complexidade, 16 regiões × 2020–2025
  quadrantes_ac.csv      quadrantes acesso × autossuficiência (alta complexidade)
  painel_ac_macro.csv    painel de alta complexidade por macrorregião
  fichas_regiao.csv      fichas regionais (alta complexidade; 3 regiões com escore diagnóstico)
  resumo_modelos.csv     por modelo (e grupo) e ano: n, média/mediana, fronteira, faixas, Malmquist médio
  dicionario_eficiencia.csv  arquivo, campo, nome gerencial, unidade, definição, fonte
Arquivos adicionais (não removem nada do contrato)
  pares_hospital.csv, especificacoes_modelos.csv (variáveis de cada modelo, lidas da
  especificação PRINCIPAL vigente no banco), insumos_produtos_hospital.csv (valores observados
  das variáveis da especificação principal do H), malmquist_regiao.csv, sensibilidade.csv,
  parametros.csv, metadados.csv, catalogo_eficiencia.csv (só na pasta de downloads).

A especificação principal de cada modelo é lida do banco no momento da execução
(dea.especificacoes, principal = TRUE); nenhum nome de produto do modelo de hospitais é fixado
aqui. O script é reexecutável: basta rodar de novo depois de qualquer reprocessamento do DEA.

Uso (a partir da raiz do repositório):
    python scripts/06_preparar_eficiencia.py                 # versão padrão (v2.1)
    python scripts/06_preparar_eficiencia.py --versao v2     # regera a partir da v2 (08/10/2026)
    (alternativa: variável de ambiente PPSUS_VERSAO_DEA)
Requisitos: Python 3.12, psycopg2, pandas.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import hashlib
import re
import shutil
import sys
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg2

warnings.filterwarnings("ignore", category=UserWarning)  # pandas + DBAPI2
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

# ----------------------------------------------------------------------------
# Configuração
# ----------------------------------------------------------------------------
RAIZ = Path(__file__).resolve().parents[1]
DS = RAIZ / "dados_site"
SAIDA = DS / "eficiencia"
DOWN = RAIZ / "arquivos" / "dados" / "eficiencia"
from config_local import caminho  # noqa: E402  (caminhos locais fora do repositório: .env.local ou variáveis de ambiente)
SENHA = caminho("PPSUS_PGPASS")

# Versões da estimação que o site sabe publicar. `dic` = chave do .env.local com o DICIONARIO_V2.md da pasta de código
# da versão (a v2.1 tem cópia própria, com a descrição corrigida do insumo de ACS); `nota_versao` aparece no site.
VERSOES = {
    "v2": dict(
        data="08/10/2026", dic="PPSUS_DIC_V2", versao_anterior="", data_versao_anterior="",
        relatorio_tecnico="Resultados DEA v2 (08/10/2026)", modelos_reestimados="todos", nota_versao=""),
    "v2.1": dict(
        data="16/10/2026", dic="PPSUS_DIC_V21", versao_anterior="v2", data_versao_anterior="08/10/2026",
        relatorio_tecnico="Resultados DEA v2 (08/10/2026)", modelos_reestimados="M1",
        nota_versao=("Versão 2.1 (16/10/2026): o insumo de agentes comunitários de saúde do modelo de atenção básica passou a "
                     "contar apenas o ACS (CBO 515105); a versão 2 somava toda a família 5151, que inclui agentes de combate às "
                     "endemias e agentes indígenas, e isso penalizava municípios com esses profissionais. Os demais modelos não mudaram.")),
}
_ap = argparse.ArgumentParser(description="Prepara dados_site/eficiencia/ a partir de uma versão da estimação DEA (schema dea).")
_ap.add_argument("--versao", default=os.environ.get("PPSUS_VERSAO_DEA", "v2.1"), choices=sorted(VERSOES),
                 help="versão dos resultados no schema dea (padrão: v2.1)")
_ARGS, _ = _ap.parse_known_args()
VERSAO = _ARGS.versao
INFO_VERSAO = VERSOES[VERSAO]
DATA_RESULTADOS = INFO_VERSAO["data"]
DIC_MD = (caminho(INFO_VERSAO["dic"], obrigatorio=False) or caminho("PPSUS_DIC_V2", obrigatorio=False)
          or RAIZ / "_sem_dicionario_v2.md")
ROTULO_RESULTADOS = f"Resultados DEA {VERSAO} ({DATA_RESULTADOS})"
ANOS = list(range(2020, 2026))
ANO_META = 2025
MODELOS_MUN = ["M1", "M0", "M2", "M2A"]
N_MUN = 142

NOME_MODELO = {
    "M1": "Atenção básica",
    "M0": "Consolidado (sistema municipal de saúde)",
    "M2": "Média complexidade (produção local)",
    "M2A": "Média complexidade (ótica do acesso)",
    "H": "Hospitais",
    "M3": "Alta complexidade (diagnóstico regional)",
}
ROTULO_GRUPO = {
    "com_leito": "municípios com leito SUS",
    "sem_leito": "municípios sem leito SUS",
    "publico": "hospitais públicos",
    "privado_filantropico": "hospitais privados e filantrópicos",
}
FAIXAS = ["fronteira", "quartil superior", "terceiro quartil", "segundo quartil", "quartil inferior"]

SAIDA.mkdir(parents=True, exist_ok=True)
DOWN.mkdir(parents=True, exist_ok=True)

AVISOS: list[str] = []
ERROS: list[str] = []
LIMPEZAS = {"texto_nan": 0}


def msg(texto: str, *args) -> None:
    print(texto % args if args else texto, flush=True)


def aviso(texto: str) -> None:
    AVISOS.append(texto)
    msg("  AVISO: %s", texto)


def erro(texto: str) -> None:
    ERROS.append(texto)
    msg("  ERRO: %s", texto)


# ----------------------------------------------------------------------------
# Banco (somente leitura)
# ----------------------------------------------------------------------------
def conectar():
    senha = SENHA.read_text(encoding="utf-8").strip().splitlines()[0].strip()
    con = psycopg2.connect(
        host="localhost", port=5432, dbname="airflow", user="airflow", password=senha,
        options="-c default_transaction_read_only=on",  # garantia extra: nunca escrever
    )
    con.set_client_encoding("UTF8")
    con.set_session(readonly=True)
    return con


def ler(con, sql: str, params=None) -> pd.DataFrame:
    return pd.read_sql(sql, con, params=params)


def colunas_tabela(con, tabela: str) -> list[str]:
    d = ler(con, "SELECT column_name FROM information_schema.columns WHERE table_schema='dea' AND table_name=%s "
                 "ORDER BY ordinal_position", (tabela,))
    return list(d.column_name)


def ler_tabela(con, tabela: str, where: str = "", params=None) -> pd.DataFrame:
    cols = colunas_tabela(con, tabela)
    if not cols:
        erro(f"tabela dea.{tabela} não existe")
        return pd.DataFrame()
    w = f"versao = '{VERSAO}'" + (f" AND {where}" if where else "")
    return ler(con, f"SELECT * FROM dea.{tabela} WHERE {w}", params)


# ----------------------------------------------------------------------------
# Limpeza e gravação
# ----------------------------------------------------------------------------
TEXTO_NULO = {"nan", "NaN", "None", "none", "null", "NULL", "NA", "<NA>"}


def eh_bool(s: pd.Series) -> bool:
    v = s.dropna()
    return len(v) > 0 and all(isinstance(x, (bool, np.bool_)) for x in v)


def normalizar(df: pd.DataFrame, reais: tuple[str, ...] = ()) -> pd.DataFrame:
    """Booleanos → 0/1 (Int64); textos 'nan'/'None' → vazio; floats arredondados (6 casas; R$ 2 casas);
    colunas de inteiros sem fração → Int64."""
    df = df.copy()
    for c in df.columns:
        s = df[c]
        if s.dtype == bool or (s.dtype == object and eh_bool(s)):
            df[c] = s.map(lambda x: pd.NA if x is None or (isinstance(x, float) and np.isnan(x)) else int(bool(x))).astype("Int64")
        elif s.dtype == object:
            def _t(x):
                if x is None or (isinstance(x, float) and np.isnan(x)):
                    return pd.NA
                if isinstance(x, str):
                    y = x.strip()
                    if y in TEXTO_NULO:
                        LIMPEZAS["texto_nan"] += 1
                        return pd.NA
                    return y if y != "" else pd.NA
                return x
            df[c] = s.map(_t)
        elif pd.api.types.is_float_dtype(s):
            casas = 2 if (c in reais or "reais" in c or c.endswith("_r2025") or c == "pib_pc") else 6
            v = s.round(casas)
            v = v.where(~np.isinf(v), np.nan)
            v = v.mask(v == 0, 0.0)  # sem "-0.0"
            nn = v.dropna()
            if len(nn) and np.all(np.mod(nn, 1) == 0) and not c.startswith(("escore", "ic_", "mi", "ec", "tc", "rmp", "peso")):
                v = v.round().astype("Int64")  # contagens e códigos sem ".0"
            df[c] = v
    return df


def gravar(df: pd.DataFrame, nome: str) -> None:
    caminho = SAIDA / nome
    df.to_csv(caminho, index=False, encoding="utf-8", lineterminator="\n", na_rep="")
    msg("  gravado dados_site/eficiencia/%s (%d linhas × %d colunas)", nome, len(df), df.shape[1])


def limpar_regiao(nome) -> str | None:
    if nome is None or (isinstance(nome, float) and np.isnan(nome)):
        return None
    return re.sub(r"\s*-\s*MT\s*$", "", str(nome)).strip()


# ----------------------------------------------------------------------------
# Textos públicos: sem nomes de tabelas, colunas ou scripts internos
# ----------------------------------------------------------------------------
PADRAO_INTERNO = re.compile(r"\b(?:dea|mart|trusted|raw|externo)\.[a-z_*]+|\b\w+\.py\b|\b\w+\.sql\b")
PADRAO_CAMINHO_LOCAL = re.compile(r"\b[A-Za-z]:\\|ppsus_repo|ppsus_db")
FLAG_GESTOR = {
    "flag_quebra_registro": "quebra de registro na série",
    "flag_sisab_nao_publicavel": "SISAB com meses insuficientes",
    "flag_sisab_implausivel": "SISAB com valores implausíveis",
}
SUBST_PUBLICO = [
    # nota da ótica do acesso e da residência
    (r"ótica de acesso no modelo-espelho M2A \(", "ótica do acesso ("),
    (r"modelo-espelho M2A", "modelo da ótica do acesso"),
    (r"internações MC \+ procedimentos individualizados MC de residentes",
     "internações e procedimentos individualizados de média complexidade de residentes"),
    (r"(\d) %", r"\1%"),
    (r"variante d2_acesso_hospitalar: ", ""),
    (r"\(variante d_residencia, ", "(leitura complementar pela residência, "),
    (r"\(variante d_residencia\)", "(leitura complementar pela residência)"),
    (r"especificação de referência do M2A", "especificação de referência da ótica do acesso"),
    (r"escores, pares e metas na ficha do modelo M2A", "escores, pares e metas na ficha da ótica do acesso"),
    (r"grupo_leito = com_leito se leitos_gerais_sus > 0 no ano, senão sem_leito",
     "grupo 'com leito SUS' quando há leito geral SUS no ano; senão, 'sem leito SUS'"),
    (r" \| n por grupo-ano: com_leito: ([\d–]+); sem_leito: ([\d–]+)", r"; municípios por grupo e ano: com leito \1, sem leito \2"),
    (r"cobertura parcial do SIA por residência declarada em dea\.especificacoes", "a cobertura do SIA por residência é parcial"),
    # situação e motivos
    (r"escore suprimido da ficha \(publicavel = FALSE\): (flag_\w+)",
     lambda m: "escore não publicado: " + FLAG_GESTOR.get(m.group(1), "registro de origem atípico")),
    (r"insumo essencial nulo \(desp_302_mc = 0\)", "despesa de média complexidade (subfunção 302) igual a zero no ano"),
    (r"; o município-ano é reestimado na variante f_302_imputada \(sensibilidade; escore não publicado\)",
     "; o município-ano entra só num teste de sensibilidade, sem escore publicado"),
    (r"desp_302_mc = 0", "despesa de média complexidade nula"),
    (r"\(elegivel_m2 = FALSE; ", "("),
]
SUBST_INTERNOS = [
    # nomes internos remanescentes (aplicado a todas as colunas de texto de todos os arquivos publicados)
    (r" ?\((?:gravado|calculado) (?:por|em) [\w.]+\.py\)", ""),
    (r" ?\(dea\.[a-z_]+\)", ""),
    (r"documentada em dea\.parametros", "documentada em parametros.csv"),
    (r"\b\w+\.py\b", "scripts do projeto"),
    (r"\b[\w./-]+\.sql\b", "scripts do projeto"),
    (r"\b(?:dea|mart|trusted|raw|externo)\.[a-z_*]+", "base do projeto"),
]


def sem_nomes_internos(x):
    if not isinstance(x, str):
        return x
    for a, b in SUBST_INTERNOS:
        x = re.sub(a, b, x)
    return x


def texto_publico(x):
    """Reescreve um texto para o público: sem nomes de tabelas, variantes, colunas ou scripts internos."""
    if not isinstance(x, str):
        return x
    for a, b in SUBST_PUBLICO:
        x = re.sub(a, b, x)
    return sem_nomes_internos(x)


FONTE_DEA = f"Projeto PPSUS-MT — estimação DEA {VERSAO} ({DATA_RESULTADOS})"


def sem_versao_na_fonte(f):
    """'CNES (CBO 515105; v2.1)' → 'CNES (CBO 515105)': a versão da estimação fica nos metadados e na nota de versão,
    não no rótulo da fonte do sistema de origem."""
    if not isinstance(f, str):
        return f
    return re.sub(r";\s*v\d+(?:\.\d+)?\)", ")", f)


def fonte_publica(f):
    """Fonte do dicionário em rótulo público (sistema de origem ou o projeto), nunca o nome da tabela ou do script."""
    if not isinstance(f, str) or not f.strip():
        return f
    s = sem_versao_na_fonte(f.strip())
    m = re.match(r"^mart\.[a-z_]+ \((.*)\)$", s)
    if m:
        return m.group(1)
    if s.startswith("trusted.equipamentos"):
        return "CNES (equipamentos)"
    if s.startswith("dea.mortalidade_padronizada"):
        return "SIH — Projeto PPSUS-MT (calculado)"
    if re.match(r"^dea\.(base_|contexto_)", s):
        return "Projeto PPSUS-MT (calculado)"
    if re.search(r"\.py\b", s) or s in ("calculado", "derivado", "fichas"):
        return "Projeto PPSUS-MT (calculado)"
    if s.startswith("ESPEC"):
        return f"Projeto PPSUS-MT — especificação {VERSAO}"
    if s.startswith("dea."):
        return FONTE_DEA + ("; SIH" if "SIH" in s else "")
    return sem_nomes_internos(s)


def num_br(v: float, casas: int = 1) -> str:
    return f"{v:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def pct_ao_ano(indice: float) -> str:
    """Índice anual (1 = sem mudança) → variação % com sinal: 1,237 → '+23,7% ao ano'."""
    return ("+" if indice >= 1 else "−") + num_br(abs(indice - 1) * 100, 1) + "% ao ano"


RE_POSICAO = r"(?:fronteira|quartil superior|terceiro quartil|segundo quartil|quartil inferior|grupo com \d+ município\(s\) publicável\(is\))"


def texto_leitura_tecnica(t, modelo: str | None = None):
    """Padroniza a leitura técnica (texto_padrao) com o restante do site: 'escore corrigido', '%' sem espaço,
    mudança de eficiência em % ao ano, sem referência a decomposições que o site não publica."""
    if not isinstance(t, str):
        return t
    t = t.replace("índice corrigido", "escore corrigido")
    t = re.sub(r"(\d) %", r"\1%", t)
    t = t.replace("IC 95 %", "IC 95%")
    t = re.sub(r"(aproximação às melhores práticas(?: \(componente de gestão\))?) (\d+,\d+) ao ano",
               lambda m: f"{m.group(1)} {pct_ao_ano(float(m.group(2).replace(',', '.')))}", t)
    t = t.replace("; ver decomposição MAC → MC/AC", "")
    if modelo is not None and modelo != "M0":
        # a nota de rede sem hospital só se aplica ao consolidado (internações locais entre os produtos)
        t = re.sub(r"\s*Sem hospital SUS no município: internações locais iguais a zero por configuração da rede "
                   r"\(meta de internações informativa\)\.", "", t)
    if modelo is not None and modelo not in ("M2", "M2A"):
        # a nota de polo de alta complexidade trata do escore de média complexidade
        t = re.sub(r"\s*Polo de alta complexidade: parte dos insumos atende à alta complexidade \(escore de média complexidade conservador\)\.", "", t)
    return texto_publico(t).strip()


def quartis_rotulo(esc: pd.Series) -> pd.Series:
    """Quartil do escore corrigido (mesma régua da faixa estadual): limites nos quantis 25/50/75% (interpolação linear),
    intervalos fechados à esquerda — abaixo de Q1 = quartil inferior; de Q3 para cima = quartil superior."""
    q1, q2, q3 = esc.quantile([0.25, 0.5, 0.75]).to_numpy()
    k = np.where(esc < q1, 1, np.where(esc < q2, 2, np.where(esc < q3, 3, 4)))
    return pd.Series(k, index=esc.index).map({1: "quartil inferior", 2: "segundo quartil", 3: "terceiro quartil", 4: "quartil superior"})


def posicao_relativa(df: pd.DataFrame, base: list[str], recorte: str, onde: str, unidades: str, n_min: int = 4) -> pd.Series:
    """Posição no recorte (região, macrorregião ou grupo) com a MESMA régua da faixa estadual: 'fronteira' para as unidades
    na fronteira (escore original = 1) e quartis do escore corrigido só entre as demais avaliadas do recorte. Com menos de
    n_min avaliadas fora da fronteira no recorte, não há posição (rótulo explicativo)."""
    out = pd.Series(pd.NA, index=df.index, dtype=object)
    av = df[(df.situacao == "avaliado") & df.escore_bc.notna()]
    for _, g in av.groupby(base + [recorte], dropna=False):
        fr = g.faixa == "fronteira"
        out.loc[g.index[fr]] = "fronteira"
        nf = g[~fr]
        if len(nf) == 0:
            continue
        if len(nf) < n_min:
            out.loc[nf.index] = f"sem posição (poucos {unidades} avaliados fora da fronteira {onde}: n = {len(nf)})"
        else:
            out.loc[nf.index] = quartis_rotulo(nf.escore_bc).values
    return out


# ----------------------------------------------------------------------------
# Referências do site (nomes, slugs, regiões)
# ----------------------------------------------------------------------------
def ler_site() -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    mun = pd.read_csv(DS / "municipios.csv", dtype={"cod_mun6": int, "co_regsaud": str, "co_macsaud": str})
    reg = pd.read_csv(DS / "regioes.csv", dtype={"co_regsaud": str, "co_macsaud": str})
    macro = dict(zip(mun.co_macsaud.astype(str), mun.macrorregiao))
    if len(mun) != N_MUN:
        erro(f"dados_site/municipios.csv tem {len(mun)} linhas (esperado {N_MUN})")
    return mun, reg, macro


# ----------------------------------------------------------------------------
# Especificação principal de cada modelo (lida do banco)
# ----------------------------------------------------------------------------
def especificacoes_principais(con) -> pd.DataFrame:
    esp = ler_tabela(con, "especificacoes")
    esp = esp[esp.principal.fillna(False).astype(bool) & ~esp.variante.str.startswith("2e")].copy()
    linhas = []
    for mod, g in esp.groupby("modelo"):
        if len(g) > 1:
            # transição de principal em curso: prefere a variante nomeada 'principal'
            aviso(f"modelo {mod}: {len(g)} especificações marcadas como principais ({', '.join(g.variante)}); "
                  f"usada a de nome 'principal' quando existir")
            g = g[g.variante == "principal"] if (g.variante == "principal").any() else g.head(1)
        linhas.append(g.iloc[0])
    return pd.DataFrame(linhas).reset_index(drop=True)


def separar_lista(txt: str) -> list[tuple[str | None, str]]:
    """'a, b' → [(None,'a'),(None,'b')]; 'com_leito: a, b; sem_leito: c' → [('com_leito','a'),...]."""
    if txt is None or (isinstance(txt, float) and np.isnan(txt)):
        return []
    out = []
    partes = [p.strip() for p in str(txt).split(";") if p.strip()]
    for p in partes:
        grupo = None
        m = re.match(r"^([a-z_]+)\s*:\s*(.*)$", p)
        if m and "," in m.group(2) or (m and m.group(2)):
            grupo, p = m.group(1), m.group(2)
        for v in [x.strip() for x in p.split(",") if x.strip()]:
            out.append((grupo, v))
    return out


def tabela_especificacoes(con, princ: pd.DataFrame) -> pd.DataFrame:
    dic = ler_tabela(con, "dicionario")
    dic = dic[dic.tabela.str.contains("metas", na=False) | dic.tabela.str.contains("especificacoes", na=False)]
    ref = {(r.modelo, r.coluna): r for r in dic.itertuples()}
    ref_col = {}
    for r in dic.itertuples():
        ref_col.setdefault(r.coluna, r)
    linhas = []
    for p in princ.itertuples():
        for tipo, txt in (("insumo", p.insumos), ("produto", p.produtos)):
            for ordem, (grupo, var) in enumerate(separar_lista(txt), start=1):
                r = ref.get((p.modelo, var)) or ref_col.get(var)
                if r is None:
                    aviso(f"especificação {p.modelo}/{p.variante}: variável {var} sem nome gerencial no dicionário")
                linhas.append(dict(
                    modelo=p.modelo, nome_modelo=NOME_MODELO.get(p.modelo, p.modelo), especificacao=p.variante,
                    grupo=grupo, rotulo_grupo=ROTULO_GRUPO.get(grupo) if grupo else None, tipo=tipo, ordem=ordem,
                    variavel=var, nome_gerencial=(r.nome_gerencial if r is not None else var),
                    unidade=(r.unidade if r is not None else None), fonte=(sem_versao_na_fonte(r.fonte) if r is not None else None),
                    orientacao=p.orientacao, retornos=p.rts, b_bootstrap=p.b_bootstrap, anos=p.anos,
                    descricao_especificacao=p.descricao,
                ))
    return pd.DataFrame(linhas)


# ----------------------------------------------------------------------------
# Fichas municipais
# ----------------------------------------------------------------------------
COLS_FICHA_MUN = [
    # identificação e situação
    "populacao", "porte_faixa", "grupo", "situacao", "motivo_situacao", "marca_parcial", "flag_primeiro_exercicio",
    # escore e posição
    "escore_bc", "ic_inf", "ic_sup", "escore_bcc", "fronteira", "publicar_bc", "ic_valido", "bc_no_limite",
    "potencial_expansao_pct", "potencial_expansao_min_pct", "potencial_expansao_max_pct",
    "faixa", "quartil_bc", "ic_cruza_faixa", "posicao_regiao", "posicao_macro", "posicao_estado", "n_dmus_ano", "n_vezes_referencia",
    # contexto
    "escore_esperado", "escore_bc_2estagio", "residuo_escore", "residuo_escore_ic_inf", "residuo_escore_ic_sup", "faixa_ajustada",
    "escore_condicional", "faixa_entre_semelhantes", "fatores_contexto", "contexto_imputado", "sem_contexto",
    # pares e metas (resumo)
    "n_pares_plausiveis", "par_mais_semelhante_id", "par_mais_semelhante_nome", "par_mais_semelhante_fora_banda", "pares_fonte",
    "nota_fronteira_pares", "n_metas", "recursos_redirecionaveis_reais_2025", "meta_financeira_publicavel",
    # evolução (Malmquist)
    "mi_2020_2025_acum", "ec_2020_2025_acum", "mi_2022_2025", "ec_2022_2025", "mi_2020_2022", "ec_2020_2022",
    "tendencia_2022_2025", "tendencia_ec_2022_2025", "mi_ic_inf_2022_2025", "mi_ic_sup_2022_2025", "ec_ic_inf_2022_2025",
    "ec_ic_sup_2022_2025", "transicao_marcada", "flag_reagregacao_ben", "nota_evolucao",
    # escala
    "retorno_escala", "eficiencia_escala", "ganho_escala_pct", "leitura_escala",
    # resultados (ao lado do escore; não são produto)
    "tmi_mm3_completo", "tmi_periodo", "obitos_menor1_mm3", "nv_mm3", "flag_tmi_base_pequena", "pct_prenatal_7mais",
    "rmp_hosp_local", "rmp_hosp_local_ic_inf", "rmp_hosp_local_ic_sup", "flag_rmp_base_pequena",
    # acesso e equidade
    "internacoes_res_p1000", "fuga_mc_pct", "dist_polo_km", "polo_nome", "dist_cuiaba_km", "pib_pc", "log_pib_pc_quartil",
    "eficiencia_faixa_equidade", "acesso_faixa_equidade", "quadrante_equidade", "otica_acesso_disponivel", "nota_acesso",
    # sinais e registro
    "registro_a_verificar", "sinal", "sinal_gerencial", "elegivel_par", "motivo_nao_par", "posicao_extrema", "super_infactivel",
    "flag_rede_sem_hospital", "flag_polo_ac", "share_ac", "flag_sisab_incompleto", "n_meses_sisab", "flag_sisab_nao_publicavel",
    "flag_sisab_implausivel", "flag_visitas_baixas", "flag_301_303_implausivel", "pct_301_303_total", "flag_301_dominante",
    "flag_302_nula", "flag_302_baixa", "flag_302_inconsistente", "flag_302_outra_esfera", "flag_quebra_registro",
    "flag_siops_incompleto", "flag_recursos_proprios_negativo", "escore_bc_desp_total",
    # síntese
    "texto_padrao",
]


def preparar_fichas_mun(con, mun: pd.DataFrame, macro: dict) -> pd.DataFrame:
    f = ler_tabela(con, "ficha_municipio_ano", "modelo = ANY(%s) AND ano BETWEEN %s AND %s", (MODELOS_MUN, ANOS[0], ANOS[-1]))
    msg("  lidas %d linhas de dea.ficha_municipio_ano (%s)", len(f), ", ".join(sorted(f.modelo.unique())))
    faltam = [c for c in COLS_FICHA_MUN if c not in f.columns]
    if faltam:
        aviso(f"colunas ausentes em dea.ficha_municipio_ano (ficam vazias): {', '.join(faltam)}")
        for c in faltam:
            f[c] = None
    f["cod_mun6"] = f.cod_mun6.astype(int)
    m = mun.set_index("cod_mun6")
    base = pd.DataFrame({
        "cod_mun6": f.cod_mun6, "municipio": f.cod_mun6.map(m.municipio), "slug": f.cod_mun6.map(m.slug),
        "modelo": f.modelo, "nome_modelo": f.modelo.map(NOME_MODELO), "ano": f.ano.astype(int),
        "co_regsaud": f.co_regsaud.astype(str), "regiao_saude": f.cod_mun6.map(m.regiao_saude),
        "co_macsaud": f.co_macsaud.astype(str), "macrorregiao": f.co_macsaud.astype(str).map(macro),
    })
    sem_nome = base.municipio.isna().sum()
    if sem_nome:
        erro(f"{sem_nome} linhas de fichas municipais com cod_mun6 fora de dados_site/municipios.csv")
    out = pd.concat([base, f[COLS_FICHA_MUN].reset_index(drop=True)], axis=1)
    out.insert(out.columns.get_loc("grupo") + 1, "rotulo_grupo", out.grupo.map(ROTULO_GRUPO))
    out["par_mais_semelhante_id"] = pd.to_numeric(out.par_mais_semelhante_id, errors="coerce").astype("Int64")
    # posição na região e na macrorregião com a régua da faixa estadual (fronteira à parte; quartis entre as demais)
    base_pos = ["modelo", "ano", "grupo"]
    estado = posicao_relativa(out.assign(_uf="MT"), base_pos, "_uf", "no estado", "municípios", n_min=1)
    av = (out.situacao == "avaliado") & out.escore_bc.notna()
    difere = int((av & (estado != out.faixa)).sum())
    if difere:
        aviso(f"fichas municipais: a régua de posição não reproduz a faixa estadual em {difere} linhas (conferir o cálculo)")
    out["posicao_regiao"] = posicao_relativa(out, base_pos, "co_regsaud", "na região", "municípios")
    out["posicao_macro"] = posicao_relativa(out, base_pos, "co_macsaud", "na macrorregião", "municípios")
    out["nota_acesso"] = out.nota_acesso.map(texto_publico)
    out["motivo_situacao"] = out.motivo_situacao.map(texto_publico)
    ordem_mod = {k: i for i, k in enumerate(MODELOS_MUN)}
    out = out.sort_values(["modelo", "ano", "cod_mun6"], key=lambda s: s.map(ordem_mod) if s.name == "modelo" else s)
    return normalizar(out.reset_index(drop=True), reais=("recursos_redirecionaveis_reais_2025", "pib_pc"))


def ajustar_referencias_e_textos(fm: pd.DataFrame, pm: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, dict]:
    """Coerência entre fichas, pares e leitura técnica (2025):
    - unidade na fronteira não tem pares; a exceção é a fronteira por falta de comparável em algum recurso (supereficiência
      infactível), cujos pares ficam como referência alternativa — os pares das demais unidades na fronteira saem do arquivo;
    - 'serve de referência para N' passa a contar os municípios que mostram a unidade entre os seus pares publicados;
    - a leitura técnica traz a posição regional recalculada e a nova contagem de referências."""
    fm, pm = fm.copy(), pm.copy()
    f25 = fm[fm.ano == ANO_META]
    sem_comp = f25.super_infactivel.fillna(0).astype(int).eq(1) | f25.sinal.fillna("").str.contains("sem_comparavel")
    fr_sem_alt = f25[(f25.faixa == "fronteira") & ~sem_comp]
    chave_fr = set(zip(fr_sem_alt.cod_mun6, fr_sem_alt.modelo))
    ocultar = pd.Series([(c, m) in chave_fr for c, m in zip(pm.cod_mun6, pm.modelo)], index=pm.index, dtype=bool)
    ocultos = set(zip(pm[ocultar].cod_mun6, pm[ocultar].modelo))
    pm = pm[~ocultar].reset_index(drop=True)
    nref = pm.groupby(["modelo", "par_cod_mun6"]).cod_mun6.nunique().to_dict() if len(pm) else {}
    m25 = fm.ano == ANO_META
    antes = pd.to_numeric(fm.loc[m25, "n_vezes_referencia"], errors="coerce")
    novo = pd.Series([nref.get((mo, int(c)), 0) for mo, c in zip(fm.loc[m25, "modelo"], fm.loc[m25, "cod_mun6"])], index=antes.index)
    fm["n_vezes_referencia"] = pd.to_numeric(fm.n_vezes_referencia, errors="coerce").astype("Float64")
    fm.loc[m25, "n_vezes_referencia"] = novo.where(fm.loc[m25, "situacao"].eq("avaliado"), antes)
    fm["n_vezes_referencia"] = fm.n_vezes_referencia.round().astype("Int64")
    n_mudou = int((antes.fillna(-1) != fm.loc[m25, "n_vezes_referencia"].astype("float").fillna(-1)).sum())

    def _texto(r):
        t = r.texto_padrao
        if not isinstance(t, str):
            return t
        pr = r.posicao_regiao if isinstance(r.posicao_regiao, str) else None
        t = re.sub(r"; na região (?P<nome>[^:;.]+?): " + RE_POSICAO,
                   (lambda m: f"; na região {m.group('nome')}: {pr}") if pr else "", t)
        if r.ano == ANO_META:
            n = r.n_vezes_referencia
            n = int(n) if pd.notna(n) else 0
            t = re.sub(r" e serve de referência para \d+ municípios?",
                       "" if n == 0 else f" e serve de referência para {n} {'município' if n == 1 else 'municípios'}", t)
            if (r.cod_mun6, r.modelo) in ocultos:
                t = re.sub(r"\s*Municípios de referência plausíveis: [^.]*\.", "", t)
        return texto_leitura_tecnica(t, r.modelo)
    fm["texto_padrao"] = fm.apply(_texto, axis=1)
    info = {"pares_ocultados_fronteira_2025": len(ocultos), "n_vezes_referencia_recontadas_2025": n_mudou}
    return fm, pm, info


def preparar_pares_mun(con, mun: pd.DataFrame) -> pd.DataFrame:
    f = ler_tabela(con, "ficha_municipio_ano", "modelo = ANY(%s) AND ano = %s", (MODELOS_MUN, ANO_META))
    m = mun.set_index("cod_mun6")
    linhas, fora_top3 = [], 0
    for r in f.itertuples():
        mais = str(r.par_mais_semelhante_id) if r.par_mais_semelhante_id is not None else None
        top = []
        for k in (1, 2, 3):
            pid = getattr(r, f"par{k}_id")
            if pid is None or (isinstance(pid, float) and np.isnan(pid)):
                continue
            pid = int(pid)
            top.append(str(pid))
            linhas.append(dict(
                cod_mun6=int(r.cod_mun6), municipio=m.municipio.get(int(r.cod_mun6)), modelo=r.modelo, ano=int(r.ano), ordem=k,
                par_cod_mun6=pid, par_municipio=m.municipio.get(pid, getattr(r, f"par{k}_nome")), par_slug=m.slug.get(pid),
                par_regiao_saude=m.regiao_saude.get(pid, limpar_regiao(getattr(r, f"par{k}_regiao"))),
                par_populacao=getattr(r, f"par{k}_populacao"), peso=getattr(r, f"par{k}_lambda_norm"),
                mais_semelhante=bool(mais is not None and str(pid) == mais),
                n_pares_plausiveis=r.n_pares_plausiveis, pares_fonte=r.pares_fonte,
            ))
        if mais and mais not in top and r.n_pares_plausiveis and r.n_pares_plausiveis > 0:
            fora_top3 += 1
    msg("  pares: %d municípios-modelo com o par mais semelhante fora dos 3 de maior peso (consta em fichas_municipio.csv)", fora_top3)
    d = pd.DataFrame(linhas)
    ordem_mod = {k: i for i, k in enumerate(MODELOS_MUN)}
    d = d.sort_values(["modelo", "cod_mun6", "ordem"], key=lambda s: s.map(ordem_mod) if s.name == "modelo" else s)
    return normalizar(d.reset_index(drop=True)), fora_top3


def preparar_metas_mun(con, mun: pd.DataFrame) -> pd.DataFrame:
    t = ler_tabela(con, "ficha_metas_municipio_ano", "modelo = ANY(%s) AND ano = %s", (MODELOS_MUN, ANO_META))
    m = mun.set_index("cod_mun6")
    t["cod_mun6"] = t.cod_mun6.astype(int)
    d = pd.DataFrame({
        "cod_mun6": t.cod_mun6, "municipio": t.cod_mun6.map(m.municipio), "slug": t.cod_mun6.map(m.slug),
        "modelo": t.modelo, "ano": t.ano.astype(int), "variavel": t.variavel, "tipo": t.tipo,
        "nome_gerencial": t.nome_gerencial, "unidade": t.unidade,
        "unidade_abs": t.unidade.map(lambda u: re.sub(r"\s*por mil hab\.?$", "", u).strip() if isinstance(u, str) else u),
        "fonte": t.fonte.map(sem_versao_na_fonte), "populacao": t.populacao,
        "observado": t.observado, "meta_radial": t.meta_radial, "meta_intermediaria": t.meta_intermediaria,
        "observado_abs": t.observado_abs, "meta_radial_abs": t.meta_radial_abs, "meta_intermediaria_abs": t.meta_intermediaria_abs,
        "potencial_unidades": t.potencial_unidades, "potencial_pct": t.potencial_pct, "potencial_reais_2025": t.potencial_reais_2025,
        "meta_publicavel": t.meta_publicavel, "sem_comparavel": t.sem_comparavel, "especificacao": t.especificacao,
        "meta_intermediaria_tipo": t.meta_intermediaria_tipo, "nota_meta": t.nota_meta, "trajetoria_lacuna_json": t.trajetoria_lacuna_json,
    })
    ordem_mod = {k: i for i, k in enumerate(MODELOS_MUN)}
    d["_t"] = d.tipo.map({"produto": 0, "insumo": 1})
    d = d.sort_values(["modelo", "cod_mun6", "_t", "variavel"], key=lambda s: s.map(ordem_mod) if s.name == "modelo" else s).drop(columns="_t")
    return normalizar(d.reset_index(drop=True), reais=("potencial_reais_2025",))


# ----------------------------------------------------------------------------
# Hospitais
# ----------------------------------------------------------------------------
COLS_FICHA_HOSP = [
    "grupo2_ano", "esfera", "esfera_mudou", "ano_mudanca_esfera", "perfil_oferta", "hospital_especializado",
    "leitos_sus", "leitos_total", "skill_mix", "taxa_ocupacao_leitos_sus", "internacoes_por_leito", "permanencia_media", "pct_urgencia",
    "internacoes", "diarias", "internacoes_mc", "internacoes_ac", "diarias_uti", "valor_total_r2025",
    "flag_painel_nao_balanceado", "especificacao_escore", "situacao", "motivo_situacao",
    "escore_bc", "ic_inf", "ic_sup", "escore_bcc", "fronteira", "publicar_bc", "ic_valido", "bc_no_limite",
    "potencial_expansao_pct", "potencial_expansao_min_pct", "potencial_expansao_max_pct",
    "faixa", "quartil_bc", "ic_cruza_faixa", "posicao_grupo", "posicao_regiao", "posicao_macro", "posicao_estado",
    "n_dmus_ano", "n_vezes_referencia",
    "escore_esperado", "escore_bc_2estagio", "residuo_escore", "residuo_escore_ic_inf", "residuo_escore_ic_sup", "faixa_ajustada",
    "escore_condicional", "faixa_entre_semelhantes", "fatores_contexto", "sem_contexto",
    "n_pares_plausiveis", "par_mais_semelhante_id", "par_mais_semelhante_nome", "par_mais_semelhante_fora_banda", "pares_fonte",
    "nota_fronteira_pares", "tipo_meta", "n_metas", "n_metas_publicaveis", "potencial_reais_2025",
    "mi_2020_2025_acum", "ec_2020_2025_acum", "mi_2022_2025", "ec_2022_2025", "mi_2020_2022", "ec_2020_2022",
    "tendencia_2022_2025", "tendencia_ec_2022_2025", "mi_ic_inf_2022_2025", "mi_ic_sup_2022_2025", "ec_ic_inf_2022_2025",
    "ec_ic_sup_2022_2025", "transicao_marcada", "nota_evolucao",
    "retorno_escala", "eficiencia_escala", "ganho_escala_pct", "leitura_escala",
    "rmp", "rmp_ic_inf", "rmp_ic_sup", "obitos_obs", "obitos_esp", "flag_rmp_base_pequena",
    "rmp_2020_2025", "rmp_2020_2025_ic_inf", "rmp_2020_2025_ic_sup", "flag_rmp_2020_2025_base_pequena",
    "tmi_mm3_municipio", "tmi_periodo", "flag_tmi_base_pequena", "pct_prenatal_7mais_municipio",
    "populacao_municipio", "porte_faixa", "pib_pc", "dist_cuiaba_km", "dist_polo_km", "polo_nome", "leitura_equidade",
    "sem_uti", "sem_ac", "flag_ocupacao_implausivel", "flag_uti_subregistrada", "flag_salto_insumo", "ano_parcial",
    "flag_comparabilidade", "motivo_comparabilidade", "flag_plausibilidade", "motivo_plausibilidade", "posicao_extrema",
    "sinal", "sinal_gerencial", "super_infactivel", "elegivel_par", "referencia_poucos_comparaveis", "registro_a_verificar",
    "texto_padrao",
]


def preparar_fichas_hosp(con, mun: pd.DataFrame, macro: dict) -> pd.DataFrame:
    f = ler_tabela(con, "ficha_hospital_ano", "ano BETWEEN %s AND %s", (ANOS[0], ANOS[-1]))
    msg("  lidas %d linhas de dea.ficha_hospital_ano (%d hospitais)", len(f), f.cnes.nunique())
    faltam = [c for c in COLS_FICHA_HOSP if c not in f.columns]
    if faltam:
        aviso(f"colunas ausentes em dea.ficha_hospital_ano (ficam vazias): {', '.join(faltam)}")
        for c in faltam:
            f[c] = None
    extras = [c for c in f.columns if c not in COLS_FICHA_HOSP and c not in (
        "versao", "modelo", "cnes", "nome_hospital", "ano", "cod_mun6", "nome_municipio", "co_regsaud", "nome_regsaud",
        "co_macsaud", "nome_macsaud", "metas") and not re.match(r"^par\d_", c) and not c.startswith("escore_grupo")
        and c not in ("escore_bc_registro", "escore_bcc_registro", "rmt", "rmt_bc", "publicar_bc_grupo", "pec_2022_2025", "sec_2022_2025")]
    if extras:
        msg("  colunas novas em dea.ficha_hospital_ano não exportadas (conferir após o reprocessamento do H): %s", ", ".join(extras))
    m = mun.set_index("cod_mun6")
    cod = f.cod_mun6.astype(int)
    base = pd.DataFrame({
        "cnes": f.cnes.astype(str).str.zfill(7), "nome_hospital": f.nome_hospital, "ano": f.ano.astype(int),
        "modelo": f.modelo, "cod_mun6": cod, "municipio": cod.map(m.municipio), "slug": cod.map(m.slug),
        "co_regsaud": f.co_regsaud.astype(str), "regiao_saude": cod.map(m.regiao_saude),
        "co_macsaud": f.co_macsaud.astype(str), "macrorregiao": f.co_macsaud.astype(str).map(macro),
    })
    out = pd.concat([base, f[COLS_FICHA_HOSP].reset_index(drop=True)], axis=1)
    out.insert(out.columns.get_loc("grupo2_ano") + 1, "rotulo_grupo", out.grupo2_ano.map(ROTULO_GRUPO))
    out["par_mais_semelhante_id"] = out.par_mais_semelhante_id.map(lambda x: str(x).zfill(7) if isinstance(x, str) and x.strip() else None)
    # posições no grupo, na região e na macrorregião com a régua da faixa estadual (fronteira à parte)
    out["posicao_grupo"] = posicao_relativa(out, ["ano"], "grupo2_ano", "no grupo", "hospitais")
    out["posicao_regiao"] = posicao_relativa(out, ["ano"], "co_regsaud", "na região", "hospitais")
    out["posicao_macro"] = posicao_relativa(out, ["ano"], "co_macsaud", "na macrorregião", "hospitais")

    def _texto(r):
        t = r.texto_padrao
        if not isinstance(t, str):
            return t
        pg = r.posicao_grupo if isinstance(r.posicao_grupo, str) else None
        t = re.sub(r"; no grupo (?P<g>[^:;.]+?): " + RE_POSICAO, (lambda m: f"; no grupo {m.group('g')}: {pg}") if pg else "", t)
        return texto_leitura_tecnica(t)
    out["texto_padrao"] = out.apply(_texto, axis=1)
    out["motivo_situacao"] = out.motivo_situacao.map(texto_publico)
    out = out.sort_values(["ano", "cnes"]).reset_index(drop=True)
    return normalizar(out, reais=("valor_total_r2025", "potencial_reais_2025", "pib_pc"))


def preparar_pares_hosp(con) -> pd.DataFrame:
    f = ler_tabela(con, "ficha_hospital_ano", "ano = %s", (ANO_META,))
    linhas = []
    for r in f.itertuples():
        mais = str(r.par_mais_semelhante_id).zfill(7) if isinstance(r.par_mais_semelhante_id, str) else None
        for k in (1, 2, 3):
            pid = getattr(r, f"par{k}_id")
            if not isinstance(pid, str) or not pid.strip():
                continue
            pid = pid.strip().zfill(7)
            linhas.append(dict(
                cnes=str(r.cnes).zfill(7), nome_hospital=r.nome_hospital, ano=int(r.ano), ordem=k,
                par_cnes=pid, par_nome=getattr(r, f"par{k}_nome"), par_municipio=getattr(r, f"par{k}_municipio"),
                par_perfil_oferta=getattr(r, f"par{k}_perfil_oferta"), par_leitos_sus=getattr(r, f"par{k}_leitos_sus"),
                peso=getattr(r, f"par{k}_lambda_norm"), mais_semelhante=bool(mais == pid),
                n_pares_plausiveis=r.n_pares_plausiveis, pares_fonte=r.pares_fonte,
            ))
    d = pd.DataFrame(linhas)
    if len(d):
        d = d.sort_values(["cnes", "ordem"]).reset_index(drop=True)
    return normalizar(d)


def preparar_metas_hosp(con) -> pd.DataFrame:
    t = ler_tabela(con, "ficha_metas_hospital_ano", "ano = %s", (ANO_META,))
    cols = ["variavel", "tipo", "nome_gerencial", "unidade", "especificacao", "tipo_meta", "observado", "meta_radial",
            "meta_intermediaria", "meta_intermediaria_tipo", "potencial_unidades", "potencial_pct", "potencial_reais_2025",
            "meta_publicavel", "produto_nao_ofertado", "sem_comparavel", "nota_meta", "trajetoria_lacuna_json"]
    for c in cols:
        if c not in t.columns:
            t[c] = None
    d = pd.concat([pd.DataFrame({"cnes": t.cnes.astype(str).str.zfill(7), "nome_hospital": t.nome_hospital, "ano": t.ano.astype(int)}),
                   t[cols].reset_index(drop=True)], axis=1)
    d["_t"] = d.tipo.map({"produto": 0, "insumo": 1})
    d = d.sort_values(["cnes", "_t", "variavel"]).drop(columns="_t").reset_index(drop=True)
    return normalizar(d, reais=("potencial_reais_2025",))


def preparar_vars_hosp(con, espec: pd.DataFrame) -> pd.DataFrame:
    """Valores observados (2020–2025) das variáveis da especificação PRINCIPAL vigente do H, em formato longo."""
    e = espec[espec.modelo == "H"]
    if e.empty:
        aviso("sem especificação principal do H em dea.especificacoes")
        return pd.DataFrame()
    cols_base = set(colunas_tabela(con, "base_hosp_ano"))
    vars_ = [v for v in e.variavel if v in cols_base]
    falt = [v for v in e.variavel if v not in cols_base]
    if falt:
        aviso(f"variáveis da especificação principal do H ausentes em dea.base_hosp_ano: {', '.join(falt)}")
    fh = ler_tabela(con, "ficha_hospital_ano", "ano BETWEEN %s AND %s", (ANOS[0], ANOS[-1]))[["cnes", "ano"]]
    sel = ", ".join(["cnes", "ano"] + vars_)
    b = ler(con, f"SELECT {sel} FROM dea.base_hosp_ano WHERE versao = %s AND ano BETWEEN %s AND %s", (VERSAO, ANOS[0], ANOS[-1]))
    b = b.merge(fh, on=["cnes", "ano"])  # só os hospitais com ficha
    longo = b.melt(id_vars=["cnes", "ano"], value_vars=vars_, var_name="variavel", value_name="valor")
    meta = e.set_index("variavel")[["tipo", "ordem", "nome_gerencial", "unidade", "fonte", "especificacao"]]
    longo = longo.join(meta, on="variavel")
    longo["cnes"] = longo.cnes.astype(str).str.zfill(7)
    longo = longo.sort_values(["cnes", "ano", "tipo", "ordem"], key=lambda s: s.map({"produto": 0, "insumo": 1}) if s.name == "tipo" else s)
    return normalizar(longo[["cnes", "ano", "variavel", "tipo", "nome_gerencial", "unidade", "fonte", "especificacao", "valor"]].reset_index(drop=True))


# ----------------------------------------------------------------------------
# Alta complexidade (regiões e macrorregiões)
# ----------------------------------------------------------------------------
def preparar_regiao(df: pd.DataFrame, reg: pd.DataFrame, macro: dict) -> pd.DataFrame:
    df = df.drop(columns=[c for c in ("versao",) if c in df.columns]).copy()
    nomes = dict(zip(reg.co_regsaud.astype(str), reg.regiao_saude))
    df["co_regsaud"] = df.co_regsaud.astype(str)
    if "nome_regsaud" in df.columns:
        df["nome_regsaud"] = df.co_regsaud.map(nomes).fillna(df.nome_regsaud.map(limpar_regiao))
        df = df.rename(columns={"nome_regsaud": "regiao_saude"})
    if "co_macsaud" in df.columns:
        df["co_macsaud"] = df.co_macsaud.astype(str)
        if "nome_macsaud" in df.columns:
            df["nome_macsaud"] = df.co_macsaud.map(macro).fillna(df.nome_macsaud)
            df = df.rename(columns={"nome_macsaud": "macrorregiao"})
    df["ano"] = df.ano.astype(int)
    df = df[df.ano.isin(ANOS)]
    return df.sort_values(["ano", "co_regsaud"]).reset_index(drop=True)


def preparar_ac(con, reg: pd.DataFrame, macro: dict) -> dict[str, pd.DataFrame]:
    out = {}
    out["painel_ac_regiao.csv"] = normalizar(preparar_regiao(ler_tabela(con, "painel_ac_regiao_ano"), reg, macro),
                                             reais=("valor_sih_ac_res_reg_r2025", "valor_sia_ac_res_r2025", "valor_ac_local_r2025",
                                                    "desp_302_ac", "desp_302_ac_p1000", "valor_ac_res_pc"))
    out["quadrantes_ac.csv"] = normalizar(preparar_regiao(ler_tabela(con, "quadrantes_ac"), reg, macro))
    fr = ler_tabela(con, "ficha_regiao_ano")
    fr = preparar_regiao(fr, reg, macro)
    if "modelo" in fr.columns:
        fr.insert(fr.columns.get_loc("modelo") + 1, "nome_modelo", fr.modelo.map(NOME_MODELO))
    if "texto_padrao" in fr.columns:
        fr["texto_padrao"] = fr.texto_padrao.map(texto_leitura_tecnica)
    out["fichas_regiao.csv"] = normalizar(fr, reais=("valor_ac_res_pc", "desp_302_ac_p1000", "pib_pc"))
    ma = ler_tabela(con, "painel_ac_macro_ano").drop(columns=["versao"])
    ma["co_macsaud"] = ma.co_macsaud.astype(str)
    ma["nome_macsaud"] = ma.co_macsaud.map(macro).fillna(ma.nome_macsaud)
    ma = ma.rename(columns={"nome_macsaud": "macrorregiao"})
    ma["ano"] = ma.ano.astype(int)
    ma = ma[ma.ano.isin(ANOS)].sort_values(["ano", "co_macsaud"]).reset_index(drop=True)
    out["painel_ac_macro.csv"] = normalizar(ma, reais=("valor_sih_ac_res_reg_r2025", "valor_sia_ac_res_r2025", "valor_ac_local_r2025",
                                                       "desp_302_ac", "desp_302_ac_p1000", "valor_ac_res_pc"))
    return out


# ----------------------------------------------------------------------------
# Malmquist: escolha da especificação usada nas fichas e agregados
# ----------------------------------------------------------------------------
def gmean(x: pd.Series) -> float:
    v = pd.to_numeric(x, errors="coerce")
    v = v[np.isfinite(v) & (v > 0)]
    return float(np.exp(np.log(v).mean())) if len(v) else np.nan


def escolher_spec_malmquist(mq: pd.DataFrame, fichas: pd.DataFrame, modelo: str, chave_ficha: str) -> str | None:
    """Entre as especificações CRS em níveis absolutos do modelo, escolhe a que reproduz o EC 2022–2025 das fichas."""
    cand = [e for e in mq[mq.modelo == modelo].especificacao.unique()
            if e.endswith("c_absoluto_crs") and not any(k in e for k in ("insumos_2022", "so_despesa", "valorada"))]
    if not cand:
        aviso(f"Malmquist {modelo}: nenhuma especificação CRS em níveis absolutos")
        return None
    fic = fichas[(fichas.modelo == modelo) & fichas.ec_2022_2025.notna()][[chave_ficha, "ec_2022_2025"]].drop_duplicates(chave_ficha)
    fic = fic.assign(dmu=fic[chave_ficha].astype(str))
    melhor, melhor_taxa = None, -1.0
    for e in cand:
        j = mq[(mq.modelo == modelo) & (mq.especificacao == e) & (mq.periodo == "2022-2025") & (mq.tipo_periodo == "janela")]
        j = j.assign(dmu=j.dmu_id.astype(str).str.zfill(7) if chave_ficha == "cnes" else j.dmu_id.astype(str))
        x = fic.merge(j[["dmu", "ec"]], on="dmu")
        taxa = float((np.abs(x.ec_2022_2025 - x.ec) < 1e-4).mean()) if len(x) else 0.0
        if taxa > melhor_taxa:
            melhor, melhor_taxa = e, taxa
    msg("  Malmquist %s: especificação %s (EC 2022–2025 coincide com as fichas em %.1f%% dos casos)", modelo, melhor, 100 * melhor_taxa)
    if melhor_taxa < 0.9:
        aviso(f"Malmquist {modelo}: a especificação escolhida ({melhor}) reproduz só {100 * melhor_taxa:.1f}% do EC das fichas")
    return melhor


def preparar_malmquist(con, fm: pd.DataFrame, fh: pd.DataFrame, nomes_reg: dict) -> tuple[pd.DataFrame, dict, pd.DataFrame]:
    mq = ler_tabela(con, "malmquist")
    specs = {}
    fm2 = fm.assign(cod=fm.cod_mun6.astype(str))
    for mod in MODELOS_MUN:
        specs[mod] = escolher_spec_malmquist(mq, fm2.rename(columns={"cod": "dmu_key"}), mod, "dmu_key")
    specs["H"] = escolher_spec_malmquist(mq, fh.assign(modelo="H"), "H", "cnes")
    partes = []
    for mod, e in specs.items():
        if e is None:
            continue
        x = mq[(mq.modelo == mod) & (mq.especificacao == e)].copy()
        x["modelo"] = mod
        x["especificacao_malmquist"] = e
        partes.append(x)
    mqs = pd.concat(partes, ignore_index=True)
    ok = mqs.publicavel.fillna(True).astype(bool) & ~mqs.transicao_marcada.fillna(False).astype(bool)
    mqs = mqs[ok].copy()
    mqs["grupo_mq"] = mqs.grupo.where(mqs.modelo.isin(["M2A", "H"]))
    if "grupo2" in mqs.columns:
        mqs.loc[mqs.modelo == "H", "grupo_mq"] = mqs.loc[mqs.modelo == "H", "grupo2"].fillna(mqs.loc[mqs.modelo == "H", "grupo"])
    # agregado por região e estado
    linhas = []
    for (mod, per, tp), g in mqs.groupby(["modelo", "periodo", "tipo_periodo"]):
        blocos = [("todos", g)] + ([(k, gg) for k, gg in g.groupby("grupo_mq")] if mod in ("M2A", "H") else [])
        for grupo, gg in blocos:
            def _lin(nivel, co, nome, s):
                return dict(modelo=mod, nome_modelo=NOME_MODELO[mod], grupo=grupo, rotulo_grupo=ROTULO_GRUPO.get(grupo, "todos"),
                            nivel=nivel, co_regsaud=co, regiao_saude=nome, periodo=per, tipo_periodo=tp, n=len(s),
                            mi=gmean(s.mi), ec=gmean(s.ec), tc=gmean(s.tc),
                            n_ec_maior_1=int((s.ec > 1).sum()), n_ec_menor_1=int((s.ec < 1).sum()),
                            n_melhora_ec=int((s.tendencia_ec == "melhora consistente").sum()) if "tendencia_ec" in s else None,
                            n_piora_ec=int((s.tendencia_ec == "piora consistente").sum()) if "tendencia_ec" in s else None,
                            especificacao_malmquist=s.especificacao_malmquist.iloc[0])
            linhas.append(_lin("estado", None, "Mato Grosso", gg))
            for co, s in gg.groupby(gg.co_regsaud.astype(str)):
                linhas.append(_lin("regiao", co, nomes_reg.get(co), s))
    reg = pd.DataFrame(linhas)
    return mqs, specs, reg


# ----------------------------------------------------------------------------
# Resumo por modelo e ano
# ----------------------------------------------------------------------------
def resumo_bloco(mod: str, grupo: str, ano: int, g: pd.DataFrame, mq_ano: pd.DataFrame | None) -> dict:
    av = g[(g.situacao == "avaliado") & g.escore_bc.notna()]
    d = dict(modelo=mod, nome_modelo=NOME_MODELO[mod], grupo=grupo, rotulo_grupo=ROTULO_GRUPO.get(grupo, "todos"), ano=ano,
             n_unidades=len(g), n_avaliados=len(av),
             n_nao_publicavel=int((g.situacao == "escore não publicável").sum()),
             n_fora_modelo=int(g.situacao.fillna("").str.startswith("fora").sum()),
             media_escore=av.escore_bc.mean() if len(av) else np.nan,
             mediana_escore=av.escore_bc.median() if len(av) else np.nan,
             media_escore_original=av.escore_bcc.mean() if len(av) else np.nan,
             n_fronteira=int((av.faixa == "fronteira").sum()))
    for fx in FAIXAS[1:]:
        d["n_" + fx.replace(" ", "_")] = int((av.faixa == fx).sum())
    d["n_ic_cruza_faixa"] = int(av.ic_cruza_faixa.fillna(0).astype(int).sum())
    d["n_registro_a_verificar"] = int(g.registro_a_verificar.fillna(0).astype(int).sum())
    if mq_ano is not None and len(mq_ano):
        d.update(mq_n=len(mq_ano), mq_mi=gmean(mq_ano.mi), mq_ec=gmean(mq_ano.ec), mq_tc=gmean(mq_ano.tc),
                 mq_n_ec_maior_1=int((mq_ano.ec > 1).sum()), mq_especificacao=mq_ano.especificacao_malmquist.iloc[0])
    else:
        d.update(mq_n=0, mq_mi=np.nan, mq_ec=np.nan, mq_tc=np.nan, mq_n_ec_maior_1=np.nan, mq_especificacao=None)
    return d


def preparar_resumo(fm: pd.DataFrame, fh: pd.DataFrame, fr: pd.DataFrame, mqs: pd.DataFrame) -> pd.DataFrame:
    linhas = []
    trans = mqs[mqs.tipo_periodo == "transicao"].copy()
    trans["ano_fim"] = trans.periodo.str[-4:].astype(int)
    for mod in MODELOS_MUN + ["H"]:
        f = fm[fm.modelo == mod] if mod != "H" else fh.assign(grupo=fh.grupo2_ano)
        for ano in ANOS:
            g = f[f.ano == ano]
            t = trans[(trans.modelo == mod) & (trans.ano_fim == ano)]
            linhas.append(resumo_bloco(mod, "todos", ano, g, t))
            if mod in ("M2A", "H"):
                for grp in sorted(g.grupo.dropna().unique()):
                    linhas.append(resumo_bloco(mod, grp, ano, g[g.grupo == grp], t[t.grupo_mq == grp]))
    # M3: diagnóstico regional (sem Malmquist publicável)
    for ano in ANOS:
        g = fr[fr.ano == ano].copy()
        g["situacao"] = np.where(g.publicavel_m3.fillna(0).astype(int) == 1, "avaliado", "painel de acesso (sem escore)")
        linhas.append(resumo_bloco("M3", "todos", ano, g, None))
    d = pd.DataFrame(linhas)
    d["mq_n_ec_maior_1"] = pd.to_numeric(d.mq_n_ec_maior_1).round().astype("Int64")
    d["mq_tc_publicavel"] = 0  # o deslocamento tecnológico é publicado só como agregado, com nota (registro do CNES após 2022)
    return normalizar(d)


# ----------------------------------------------------------------------------
# Dicionário
# ----------------------------------------------------------------------------
def ler_dic_md() -> dict[str, tuple[str, str, str]]:
    """Definições das tabelas-base em DICIONARIO_V2.md: coluna → (definição, fonte, unidade)."""
    out = {}
    if not DIC_MD.exists():
        return out
    for lin in DIC_MD.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*`([^`]+)`\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|", lin)
        if m and m.group(1) not in out:
            out[m.group(1)] = (m.group(2), m.group(3), m.group(4))
    return out


DIC_PROPRIO = {
    # campos acrescentados por este script
    "municipio": ("Município", "—", "nome do município (como nas demais páginas do site)", "IBGE"),
    "slug": ("Endereço da página do município", "—", "identificador usado no endereço do perfil municipal (municipios/<slug>.html)", "Observatório PPSUS-MT"),
    "nome_modelo": ("Modelo (nome)", "—", "nome gerencial do modelo DEA", "Observatório PPSUS-MT"),
    "regiao_saude": ("Região de saúde", "—", "região de saúde (CIR) — nome sem o sufixo ' - MT'", "SES-MT (PDR)"),
    "macrorregiao": ("Macrorregião de saúde", "—", "macrorregião de saúde", "SES-MT (PDR)"),
    "rotulo_grupo": ("Grupo de comparação", "—", "rótulo do grupo de fronteira: municípios com/sem leito SUS (ótica do acesso) ou hospitais públicos/privados e filantrópicos", "dea.*"),
    "grupo": ("Grupo de fronteira", "—", "grupo de comparação do modelo (com_leito/sem_leito na ótica do acesso; publico/privado_filantropico nos hospitais); 'todos' = conjunto do modelo", "dea.*"),
    "ordem": ("Ordem", "n", "ordem do par por peso decrescente (1 = maior peso)", "dea.benchmarks"),
    "par_cod_mun6": ("Par — código IBGE", "—", "município de referência plausível (fronteira restrita aos municípios elegíveis como referência)", "dea.benchmarks"),
    "par_municipio": ("Par — município", "—", "nome do município de referência", "IBGE"),
    "par_slug": ("Par — endereço do perfil", "—", "identificador da página do par", "Observatório PPSUS-MT"),
    "par_regiao_saude": ("Par — região de saúde", "—", "região de saúde do par", "SES-MT (PDR)"),
    "par_populacao": ("Par — população", "habitantes", "população do par no ano", "IBGE"),
    "peso": ("Peso do par", "proporção (0–1)", "λ normalizado: participação do par na projeção que define a meta (soma 1 entre todos os pares)", "dea.benchmarks"),
    "mais_semelhante": ("Par mais semelhante", "0/1", "1 = par de maior peso dentro da banda de porte (1/3 a 3 vezes o porte da unidade avaliada)", "dea.benchmarks"),
    "par_cnes": ("Par — CNES", "texto (7 dígitos)", "hospital de referência plausível", "dea.benchmarks"),
    "par_nome": ("Par — hospital", "—", "nome fantasia do hospital de referência", "CNES"),
    "par_perfil_oferta": ("Par — perfil de oferta", "—", "com/sem UTI e com/sem alta complexidade", "CNES/SIH"),
    "par_leitos_sus": ("Par — leitos SUS", "leitos", "leitos SUS do par no ano", "CNES"),
    "unidade_abs": ("Unidade (valores absolutos)", "—", "unidade das colunas *_abs (valores do ano, sem divisão pela população)", "dea.metas"),
    "observado_abs": ("Observado (absoluto)", "unidade_abs", "valor observado no ano em valores absolutos", "dea.metas"),
    "meta_radial_abs": ("Meta plena (absoluta)", "unidade_abs", "meta plena em valores absolutos (projeção na fronteira, com folgas)", "dea.metas"),
    "meta_intermediaria_abs": ("Meta intermediária (absoluta)", "unidade_abs", "meta intermediária em valores absolutos: metade da distância entre o observado e a meta plena", "dea.metas"),
    "potencial_unidades": ("Potencial de melhoria (unidades)", "unidade_abs", "meta plena − observado, em valores absolutos (positivo nos produtos = produção adicional; negativo nos insumos = recurso que poderia ser redirecionado)", "dea.metas"),
    "potencial_pct": ("Potencial de melhoria (%)", "%", "(meta plena − observado) / observado × 100", "dea.metas"),
    "potencial_reais_2025": ("Potencial de melhoria em R$", "R$ de 2025", "valor em reais da folga do insumo financeiro (só despesa); apresentado como realocação, não como corte", "dea.metas"),
    "especificacao": ("Especificação", "—", "especificação de origem (nas metas: fronteira usada para pares e metas)", "dea.especificacoes"),
    "trajetoria_lacuna_json": ("Trajetória da lacuna", "json", "potencial de melhoria (%) da variável em cada ano 2020–2025", "dea.metas"),
    "n_unidades": ("Unidades no recorte", "n", "linhas de ficha no modelo, grupo e ano (municípios, hospitais ou regiões)", "fichas"),
    "n_avaliados": ("Avaliados com escore publicável", "n", "unidades com situação 'avaliado' e escore corrigido", "fichas"),
    "n_nao_publicavel": ("Escore não publicável", "n", "unidades estimadas cujo escore não é publicado (motivo na ficha)", "fichas"),
    "n_fora_modelo": ("Fora do modelo", "n", "unidades não avaliadas pelo modelo no ano (ex.: sem hospital SUS no modelo de média complexidade)", "fichas"),
    "media_escore": ("Escore corrigido médio", "0–1", "média simples do índice de eficiência corrigido entre os avaliados", "fichas"),
    "mediana_escore": ("Escore corrigido mediano", "0–1", "mediana do índice de eficiência corrigido entre os avaliados", "fichas"),
    "media_escore_original": ("Escore original médio", "0–1", "média simples do escore DEA original (sem correção de viés)", "fichas"),
    "n_fronteira": ("Na fronteira", "n", "avaliados na faixa 'fronteira' (escore original = 1)", "fichas"),
    "n_quartil_superior": ("Quartil superior", "n", "avaliados na faixa 'quartil superior'", "fichas"),
    "n_terceiro_quartil": ("Terceiro quartil", "n", "avaliados na faixa 'terceiro quartil'", "fichas"),
    "n_segundo_quartil": ("Segundo quartil", "n", "avaliados na faixa 'segundo quartil'", "fichas"),
    "n_quartil_inferior": ("Quartil inferior", "n", "avaliados na faixa 'quartil inferior'", "fichas"),
    "n_ic_cruza_faixa": ("IC cruza a faixa vizinha", "n", "avaliados cujo intervalo de confiança alcança a faixa vizinha (posição incerta)", "fichas"),
    "n_registro_a_verificar": ("Registro a verificar", "n", "unidades com valores de origem a validar com SES-MT/COSEMS-MT", "fichas"),
    "mq_n": ("Malmquist — unidades", "n", "unidades com transição (ano anterior → ano) publicável", "dea.malmquist"),
    "mq_mi": ("Produtividade (Malmquist) média", "índice (1 = sem mudança)", "média geométrica do índice de Malmquist na transição do ano anterior para o ano", "dea.malmquist"),
    "mq_ec": ("Mudança de eficiência média", "índice (1 = sem mudança)", "média geométrica do componente de aproximação às melhores práticas (EC) na transição", "dea.malmquist"),
    "mq_tc": ("Deslocamento tecnológico médio", "índice (1 = sem mudança)", "média geométrica do deslocamento da fronteira (TC); leitura com cautela: possível efeito do crescimento de registro no CNES após 2022", "dea.malmquist"),
    "mq_n_ec_maior_1": ("Malmquist — EC > 1", "n", "unidades que se aproximaram das melhores práticas na transição", "dea.malmquist"),
    "mq_especificacao": ("Especificação do Malmquist", "—", "especificação de níveis absolutos com retornos constantes usada no Malmquist", "dea.malmquist"),
    "mq_tc_publicavel": ("TC publicável por unidade", "0/1", "0 = o deslocamento tecnológico não é publicado por unidade (só agregado, com nota)", "Observatório PPSUS-MT"),
    "especificacao_malmquist": ("Especificação do Malmquist", "—", "especificação de níveis absolutos com retornos constantes usada no Malmquist", "dea.malmquist"),
    "nivel": ("Nível de agregação", "—", "'estado' (Mato Grosso) ou 'regiao' (região de saúde)", "Observatório PPSUS-MT"),
    "periodo": ("Período", "texto", "transição anual (ex.: 2024-2025) ou janela (2020-2022, 2022-2025, 2020-2025)", "dea.malmquist"),
    "tipo_periodo": ("Tipo de período", "texto", "'transicao' (ano a ano) ou 'janela' (média anual na janela)", "dea.malmquist"),
    "n": ("Unidades", "n", "unidades com valor publicável no período (transições marcadas excluídas)", "dea.malmquist"),
    "mi": ("Produtividade (Malmquist)", "índice (1 = sem mudança)", "média geométrica do índice de Malmquist", "dea.malmquist"),
    "ec": ("Mudança de eficiência (EC)", "índice (1 = sem mudança)", "média geométrica da aproximação às melhores práticas (componente de gestão)", "dea.malmquist"),
    "tc": ("Deslocamento tecnológico (TC)", "índice (1 = sem mudança)", "média geométrica do deslocamento da fronteira; possível efeito de registro do CNES após 2022", "dea.malmquist"),
    "n_ec_maior_1": ("EC > 1", "n", "unidades que se aproximaram das melhores práticas", "dea.malmquist"),
    "n_ec_menor_1": ("EC < 1", "n", "unidades que se afastaram das melhores práticas", "dea.malmquist"),
    "n_melhora_ec": ("Melhora consistente (EC)", "n", "unidades com tendência 'melhora consistente' do componente de gestão", "dea.malmquist"),
    "n_piora_ec": ("Piora consistente (EC)", "n", "unidades com tendência 'piora consistente' do componente de gestão", "dea.malmquist"),
    "tipo": ("Tipo", "—", "'insumo' (recurso) ou 'produto' (produção)", "dea.especificacoes"),
    "variavel": ("Variável", "—", "nome técnico da variável", "dea.especificacoes"),
    "nome_gerencial": ("Nome gerencial", "—", "nome da variável para o gestor", "dea.dicionario"),
    "unidade": ("Unidade", "—", "unidade de medida", "dea.dicionario"),
    "fonte": ("Fonte", "—", "sistema de informação de origem", "dea.dicionario"),
    "valor": ("Valor observado", "unidade", "valor observado da variável no ano (unidade na coluna unidade)", "dea.base_hosp_ano"),
    "orientacao": ("Orientação", "—", "orientação do modelo (produto: quanto mais se poderia produzir com os mesmos recursos)", "dea.especificacoes"),
    "retornos": ("Retornos de escala", "—", "hipótese de retornos de escala da fronteira (VRS = variáveis, modelo BCC)", "dea.especificacoes"),
    "b_bootstrap": ("Réplicas bootstrap", "n", "número de réplicas do bootstrap de Simar e Wilson", "dea.especificacoes"),
    "anos": ("Anos", "texto", "anos estimados (fronteira anual)", "dea.especificacoes"),
    "descricao_especificacao": ("Descrição da especificação", "texto", "descrição técnica da especificação principal", "dea.especificacoes"),
    "chave": ("Parâmetro", "—", "chave do parâmetro", "dea.parametros"),
    "valor_parametro": ("Valor", "—", "valor do parâmetro", "dea.parametros"),
    "item": ("Item", "—", "nome do metadado", "06_preparar_eficiencia.py"),
}


# Definições específicas de um arquivo (prevalecem sobre as demais).
DIC_ARQ = {
    ("parametros.csv", "situacao"): ("Situação do parâmetro", "texto", "estado de aprovação/homologação do parâmetro ou limiar", "dea.parametros"),
    ("parametros.csv", "modelo"): ("Modelo", "—", "modelo a que o parâmetro se aplica (vazio = todos)", "dea.parametros"),
    ("parametros.csv", "tipo"): ("Tipo do valor", "—", "tipo do valor do parâmetro (int, float, texto)", "dea.parametros"),
    ("parametros.csv", "unidade"): ("Unidade", "—", "unidade do parâmetro", "dea.parametros"),
    ("metadados.csv", "valor"): ("Valor", "—", "valor do metadado", "06_preparar_eficiencia.py"),
    ("insumos_produtos_hospital.csv", "especificacao"): ("Especificação", "—", "especificação principal do modelo de hospitais vigente na geração", "dea.especificacoes"),
    ("fichas_municipio.csv", "n_vezes_referencia"): ("É referência para (municípios)", "n",
        "em 2025: número de municípios que mostram a unidade entre os seus pares de referência publicados (pares_municipio.csv); "
        "nos anos anteriores, contagem da estimação na fronteira de pares plausíveis", "dea.benchmarks"),
    ("fichas_municipio.csv", "posicao_regiao"): ("Posição na região de saúde", "texto",
        "mesma régua da faixa estadual: 'fronteira' quando o escore original = 1; para os demais avaliados, quartil do escore corrigido "
        "entre os avaliados fora da fronteira na região (na ótica do acesso, dentro do grupo com/sem leito SUS); sem posição quando há "
        "menos de 4 avaliados fora da fronteira na região", "Observatório PPSUS-MT (calculado)"),
    ("fichas_municipio.csv", "posicao_macro"): ("Posição na macrorregião de saúde", "texto",
        "mesma régua da faixa estadual: 'fronteira' quando o escore original = 1; para os demais avaliados, quartil do escore corrigido "
        "entre os avaliados fora da fronteira na macrorregião (na ótica do acesso, dentro do grupo com/sem leito SUS); sem posição quando há "
        "menos de 4 avaliados fora da fronteira", "Observatório PPSUS-MT (calculado)"),
    ("fichas_hospital.csv", "posicao_grupo"): ("Posição no grupo", "texto",
        "mesma régua da faixa estadual: 'fronteira' quando o escore original = 1; para os demais, quartil do escore corrigido entre os "
        "hospitais avaliados fora da fronteira do mesmo grupo (públicos ou privados/filantrópicos) no ano", "Observatório PPSUS-MT (calculado)"),
    ("fichas_hospital.csv", "posicao_regiao"): ("Posição na região de saúde", "texto",
        "mesma régua da faixa estadual: 'fronteira' quando o escore original = 1; para os demais, quartil do escore corrigido entre os "
        "hospitais avaliados fora da fronteira da região; sem posição quando há menos de 4", "Observatório PPSUS-MT (calculado)"),
    ("fichas_hospital.csv", "posicao_macro"): ("Posição na macrorregião de saúde", "texto",
        "mesma régua da faixa estadual: 'fronteira' quando o escore original = 1; para os demais, quartil do escore corrigido entre os "
        "hospitais avaliados fora da fronteira da macrorregião; sem posição quando há menos de 4", "Observatório PPSUS-MT (calculado)"),
    ("pares_municipio.csv", "ano"): ("Ano", "ano", "ano de referência dos pares (2025)", "Observatório PPSUS-MT"),
}

# Definições de reserva: usadas só quando dea.dicionario não traz o campo (ex.: durante um reprocessamento).
DIC_RESERVA = {
    "cnes": ("CNES", "texto (7 dígitos)", "código do estabelecimento no Cadastro Nacional de Estabelecimentos de Saúde", "CNES"),
    "grupo2_ano": ("Grupo do hospital", "—", "'publico' ou 'privado_filantropico' (natureza jurídica no ano); define o grupo de comparação", "CNES"),
    "esfera": ("Esfera administrativa", "—", "esfera administrativa do hospital no ano (municipal, estadual, federal, privada)", "CNES"),
    "esfera_mudou": ("Esfera mudou", "0/1", "1 = a esfera administrativa variou entre 2020 e 2025", "CNES"),
    "ano_mudanca_esfera": ("Ano da mudança de esfera", "ano", "primeiro ano em que a esfera difere do ano anterior", "CNES"),
    "perfil_oferta": ("Perfil de oferta", "—", "com/sem UTI e com/sem alta complexidade (produto > 0 em pelo menos 4 dos 6 anos)", "CNES/SIH"),
    "hospital_especializado": ("Hospital especializado", "0/1", "1 = tipo de unidade 07 no CNES (hospital especializado)", "CNES"),
    "leitos_sus": ("Leitos SUS", "leitos", "leitos SUS (média mensal do ano)", "CNES"),
    "leitos_total": ("Leitos totais", "leitos", "leitos totais, SUS e não SUS (média mensal)", "CNES"),
    "skill_mix": ("Participação de enfermeiros na enfermagem", "proporção", "enfermeiros ÷ (enfermeiros + técnicos de enfermagem), em FTE SUS", "CNES"),
    "taxa_ocupacao_leitos_sus": ("Taxa de ocupação dos leitos SUS", "proporção (0–1)", "diárias ÷ (leitos SUS × 365)", "CNES/SIH"),
    "internacoes_por_leito": ("Internações por leito", "razão", "internações ÷ leitos SUS", "CNES/SIH"),
    "permanencia_media": ("Permanência média", "dias", "dias de permanência ÷ internações", "SIH"),
    "pct_urgencia": ("Internações de urgência", "%", "internações não eletivas ÷ internações × 100", "SIH"),
    "internacoes": ("Internações (MC + AC)", "AIH/ano", "internações SUS do hospital no ano", "SIH"),
    "diarias": ("Diárias de internação (todas)", "diárias/ano", "diárias das internações SUS", "SIH"),
    "internacoes_mc": ("Internações de média complexidade", "AIH/ano", "internações de média complexidade", "SIH"),
    "internacoes_ac": ("Internações de alta complexidade", "AIH/ano", "internações de alta complexidade", "SIH"),
    "diarias_uti": ("Diárias de UTI", "diárias/ano", "diárias de UTI das internações SUS", "SIH"),
    "valor_total_r2025": ("Produção hospitalar valorada", "R$ de 2025", "valor aprovado das AIH, deflacionado pelo IPCA", "SIH"),
    "rmp": ("Mortalidade hospitalar padronizada (RMP)", "razão (1 = esperado)", "óbitos observados ÷ esperados no ano (padronização indireta por procedimento, sexo, idade e caráter)", "SIH"),
    "rmp_ic_inf": ("RMP — IC inferior", "razão", "limite inferior do IC 95 %", "SIH"),
    "rmp_ic_sup": ("RMP — IC superior", "razão", "limite superior do IC 95 %", "SIH"),
    "obitos_obs": ("Óbitos observados", "óbitos", "óbitos hospitalares observados no ano", "SIH"),
    "obitos_esp": ("Óbitos esperados", "óbitos", "óbitos esperados pelas taxas estaduais do estrato", "SIH"),
    "rmp_2020_2025": ("RMP 2020–2025", "razão (1 = esperado)", "mortalidade hospitalar padronizada agregada 2020–2025", "SIH"),
    "rmp_2020_2025_ic_inf": ("RMP 2020–2025 — IC inferior", "razão", "limite inferior do IC 95 %", "SIH"),
    "rmp_2020_2025_ic_sup": ("RMP 2020–2025 — IC superior", "razão", "limite superior do IC 95 %", "SIH"),
    "flag_rmp_2020_2025_base_pequena": ("RMP 2020–2025 com base pequena", "0/1", "1 = menos de 30 óbitos esperados em 2020–2025 (sem leitura comparativa)", "SIH"),
    "sem_uti": ("Sem UTI", "0/1", "1 = diárias de UTI em menos de 4 dos 6 anos", "SIH"),
    "sem_ac": ("Sem alta complexidade", "0/1", "1 = internações de alta complexidade em menos de 4 dos 6 anos", "SIH"),
    "flag_ocupacao_implausivel": ("Ocupação implausível", "0/1", "1 = taxa de ocupação dos leitos SUS < 0,20 ou > 1,00 (registro a verificar)", "CNES/SIH"),
    "flag_salto_insumo": ("Salto de insumo", "0/1", "1 = variação anual acima de 100 % em leitos, médicos, enfermagem ou equipamentos", "CNES"),
    "ano_parcial": ("Ano parcial", "0/1", "1 = ano com fontes incompletas", "SIH/CNES"),
    "flag_comparabilidade": ("Perfil pouco comparável", "0/1", "1 = hospital especializado, com 50 % ou mais de internações de alta complexidade ou hospital-dia (limiar homologado 0,50)", "CNES/SIH"),
    "motivo_comparabilidade": ("Motivo (comparabilidade)", "texto", "motivos do perfil pouco comparável", "CNES/SIH"),
    "flag_plausibilidade": ("Registro a verificar (motivo técnico)", "0/1", "1 = alguma regra de plausibilidade de registro acionada", "dea.*"),
    "motivo_plausibilidade": ("Motivo (registro)", "texto", "regras de plausibilidade acionadas, separadas por ';'", "dea.*"),
    "trs": ("Terapia renal substitutiva", "procedimentos/ano", "procedimentos de terapia renal substitutiva (diálise) aprovados de residentes", "SIA (APAC)"),
    "quimioterapia": ("Quimioterapia", "procedimentos/ano", "procedimentos de quimioterapia aprovados de residentes", "SIA (APAC)"),
    "radioterapia": ("Radioterapia", "procedimentos/ano", "procedimentos de radioterapia aprovados de residentes", "SIA (APAC)"),
    "nome_hospital": ("Hospital", "—", "nome fantasia do estabelecimento no CNES", "CNES"),
    "especificacao_escore": ("Especificação do escore", "—", "'principal' (hospitais do painel balanceado) ou 'n_nao_balanceado' (demais hospitais, fronteira anual sem painel)", "dea.escores"),
    "flag_painel_nao_balanceado": ("Fora do painel balanceado", "0/1", "1 = hospital sem série completa 2020–2025; escore da fronteira anual, sem contexto nem evolução", "dea.escores"),
    "posicao_grupo": ("Posição no grupo", "texto", "quartil do escore corrigido entre os hospitais publicáveis do mesmo grupo (públicos ou privados/filantrópicos) no ano", "dea.escores"),
    "n_metas_publicaveis": ("Metas publicáveis", "n", "variáveis com meta publicável na ficha", "dea.metas"),
    "tipo_meta": ("Tipo de meta", "texto", "'meta de perfil' (pares do mesmo grupo e perfil de oferta) ou 'meta na fronteira comum'", "dea.metas"),
    "produto_nao_ofertado": ("Produto não ofertado", "0/1", "1 = o hospital não oferta o serviço (ex.: sem UTI ou sem alta complexidade); sem meta", "dea.metas"),
    "referencia_poucos_comparaveis": ("Referência com poucos comparáveis", "0/1", "1 = na fronteira por haver poucos hospitais comparáveis no perfil", "dea.escores"),
    "tmi_mm3_municipio": ("Mortalidade infantil do município (triênio)", "por mil NV", "óbitos < 1 ano por mil nascidos vivos no município-sede, último triênio completo (indicador de resultado, não produto)", "SIM/SINASC"),
    "pct_prenatal_7mais_municipio": ("Pré-natal ≥ 7 consultas (município)", "%", "nascidos vivos de mães com 7 ou mais consultas de pré-natal no município-sede", "SINASC"),
    "populacao_municipio": ("População do município-sede", "habitantes", "população residente do município do hospital no ano", "IBGE"),
    "acesso_p1000": ("Acesso à alta complexidade", "internações/ano por mil hab.", "internações de alta complexidade de residentes da região por mil habitantes", "SIH"),
    "autossuficiencia_pct": ("Autossuficiência em alta complexidade", "%", "internações de alta complexidade realizadas na região ÷ internações de alta complexidade de residentes × 100 (acima de 100 = região polo que atende outras)", "SIH"),
    "mi_2020_2025_acum_diag": ("Produtividade acumulada 2020–2025 (diagnóstico)", "índice (1 = sem mudança)", "Malmquist acumulado do modelo diagnóstico de alta complexidade (não publicado como resultado)", "dea.malmquist"),
    "ec_2020_2025_acum_diag": ("Aproximação às melhores práticas acumulada 2020–2025 (diagnóstico)", "índice", "componente de gestão acumulado do modelo diagnóstico de alta complexidade", "dea.malmquist"),
    "ec_2022_2025_diag": ("Aproximação às melhores práticas 2022–2025 (diagnóstico)", "índice ao ano", "média geométrica anual do componente de gestão do modelo diagnóstico de alta complexidade", "dea.malmquist"),
    "escore_m3_bc_sub": ("Escore diagnóstico corrigido (subamostragem)", "0–1", "escore do modelo diagnóstico de alta complexidade corrigido por subamostragem (publicado só nas regiões publicáveis)", "dea.escores"),
    "escore_m3_sinais": ("Sinais do escore diagnóstico", "texto", "sinais de leitura do escore diagnóstico de alta complexidade", "dea.escores"),
    "n_regioes": ("Regiões de saúde", "n", "regiões de saúde da macrorregião", "SES-MT (PDR)"),
    "n_regioes_publicaveis_m3": ("Regiões com escore diagnóstico publicável", "n", "regiões da macrorregião com escore diagnóstico de alta complexidade publicável", "dea.escores"),
    "variante": ("Variante", "—", "especificação alternativa comparada com a principal", "dea.sensibilidade"),
    "base_comparacao": ("Base de comparação", "—", "conjunto de unidades usado na comparação com a principal", "dea.sensibilidade"),
    "escore_base": ("Escore comparado", "—", "escore usado na comparação (corrigido ou original)", "dea.sensibilidade"),
    "spearman_vs_principal": ("Correlação com a principal", "−1 a 1", "correlação de postos de Spearman entre a variante e a especificação principal", "dea.sensibilidade"),
    "spearman_bc": ("Correlação com a principal (corrigido)", "−1 a 1", "Spearman entre os escores corrigidos da variante e da principal", "dea.sensibilidade"),
    "spearman_original": ("Correlação com a principal (original)", "−1 a 1", "Spearman entre os escores originais da variante e da principal", "dea.sensibilidade"),
    "pct_muda_tercil": ("Mudança de tercil", "proporção", "parcela das unidades que mudam de tercil entre a variante e a principal", "dea.sensibilidade"),
    "pct_tercil_bc": ("Mudança de tercil (corrigido)", "proporção", "parcela que muda de tercil, escores corrigidos", "dea.sensibilidade"),
    "pct_tercil_original": ("Mudança de tercil (original)", "proporção", "parcela que muda de tercil, escores originais", "dea.sensibilidade"),
    "pct_tercil_bc_fronteira_empatada": ("Mudança de tercil (empates na fronteira)", "proporção", "parcela que muda de tercil tratando os empates na fronteira", "dea.sensibilidade"),
    "n_comum": ("Unidades em comum", "n", "unidades presentes na variante e na principal", "dea.sensibilidade"),
    "n_dmus_comuns": ("Unidades em comum", "n", "unidades presentes na variante e na principal", "dea.sensibilidade"),
    "media_bc_variante": ("Escore corrigido médio (variante)", "0–1", "média do escore corrigido na variante", "dea.sensibilidade"),
    "media_bc_principal": ("Escore corrigido médio (principal)", "0–1", "média do escore corrigido na principal", "dea.sensibilidade"),
    "media_original_variante": ("Escore original médio (variante)", "0–1", "média do escore original na variante", "dea.sensibilidade"),
    "media_original_principal": ("Escore original médio (principal)", "0–1", "média do escore original na principal", "dea.sensibilidade"),
    "n_eficientes_variante": ("Na fronteira (variante)", "n", "unidades na fronteira na variante", "dea.sensibilidade"),
    "n_eficientes_principal": ("Na fronteira (principal)", "n", "unidades na fronteira na principal", "dea.sensibilidade"),
    "estavel": ("Resultado estável", "0/1", "1 = a variante preserva a ordenação da principal segundo os critérios de robustez", "dea.sensibilidade"),
    "observacao": ("Observação", "texto", "observação técnica", "dea.*"),
    "descricao": ("Descrição", "texto", "descrição do parâmetro", "dea.parametros"),
    "origem": ("Origem", "texto", "origem do parâmetro (especificação, decisão ou cálculo)", "dea.parametros"),
    "gravado_em": ("Gravado em", "data", "data de gravação do parâmetro", "dea.parametros"),
    "observacao_coordenador": ("Observação da coordenação", "texto", "registro da decisão ou homologação do coordenador", "dea.parametros"),
}


def preparar_dicionario(dic: pd.DataFrame, arquivos: dict[str, pd.DataFrame]) -> pd.DataFrame:
    md = ler_dic_md()
    tab_de = {
        "fichas_municipio.csv": "dea.ficha_municipio_ano", "metas_municipio.csv": "dea.ficha_metas_municipio_ano",
        "pares_municipio.csv": "dea.ficha_municipio_ano", "fichas_hospital.csv": "dea.ficha_hospital_ano",
        "metas_hospital.csv": "dea.ficha_metas_hospital_ano", "pares_hospital.csv": "dea.ficha_hospital_ano",
        "fichas_regiao.csv": "dea.ficha_regiao_ano", "painel_ac_regiao.csv": "dea.painel_ac_regiao_ano",
        "quadrantes_ac.csv": "dea.painel_ac_regiao_ano", "painel_ac_macro.csv": "dea.painel_ac_regiao_ano",
    }
    por_tab: dict[tuple[str, str], object] = {}
    por_col: dict[str, object] = {}
    for r in dic.itertuples():
        por_tab.setdefault((r.tabela, r.coluna), r)
        por_col.setdefault(r.coluna, r)
    linhas, n_fallback = [], 0
    for arq, df in arquivos.items():
        for c in df.columns:
            if (arq, c) in DIC_ARQ:
                n, u, d, f = DIC_ARQ[(arq, c)]
                origem = "06_preparar_eficiencia.py"
            elif c in DIC_PROPRIO:
                n, u, d, f = DIC_PROPRIO[c]
                origem = "06_preparar_eficiencia.py"
            elif (tab_de.get(arq), c) in por_tab or c in por_col:
                r = por_tab.get((tab_de.get(arq), c)) or por_col.get(c)
                n, u, d, f = r.nome_gerencial, r.unidade, r.definicao, r.fonte
                origem = "dea.dicionario"
            elif c in DIC_RESERVA:
                n, u, d, f = DIC_RESERVA[c]
                origem = "06_preparar_eficiencia.py (reserva)"
            elif c in md:
                d, f, u = md[c]
                n = re.split(r"\s\(|;|\s—", d)[0].strip()
                n = (n[:1].upper() + n[1:]) if n else c.replace("_", " ")
                origem = "DICIONARIO_V2.md"
            else:
                n, u, d, f = c.replace("_", " "), "—", f"ver relatório técnico {INFO_VERSAO['relatorio_tecnico']}", "dea.*"
                origem = "sem definição"
                n_fallback += 1
            linhas.append(dict(arquivo=arq, campo=c, nome_gerencial=n, unidade=u, definicao=d, fonte=f, origem_definicao=origem))
    d = pd.DataFrame(linhas)
    if n_fallback:
        faltam = d[d.origem_definicao == "sem definição"]
        aviso(f"dicionário: {n_fallback} campos sem definição própria: " + ", ".join(sorted(set(faltam.campo))))
    msg("  dicionário: origem das definições — %s",
        "; ".join(f"{k}: {v}" for k, v in d.origem_definicao.value_counts().items()))
    d["fonte"] = d.fonte.map(fonte_publica)
    d["definicao"] = d.definicao.map(texto_publico)
    return normalizar(d.drop(columns=["origem_definicao"]))


# ----------------------------------------------------------------------------
# Validações
# ----------------------------------------------------------------------------
def validar(arqs: dict[str, pd.DataFrame], mun: pd.DataFrame, espec: pd.DataFrame) -> dict:
    cont = {}
    fm, mm, pm = arqs["fichas_municipio.csv"], arqs["metas_municipio.csv"], arqs["pares_municipio.csv"]
    fh, mh = arqs["fichas_hospital.csv"], arqs["metas_hospital.csv"]
    # 142 municípios em 2025 em cada modelo municipal
    for mod in MODELOS_MUN:
        g = fm[(fm.modelo == mod) & (fm.ano == ANO_META)]
        n = g.cod_mun6.nunique()
        cont[f"{mod}_2025_municipios"] = n
        cont[f"{mod}_2025_avaliados"] = int(((g.situacao == "avaliado") & g.escore_bc.notna()).sum())
        if n != N_MUN or set(g.cod_mun6) != set(mun.cod_mun6):
            erro(f"{mod}: {n} municípios em 2025 (esperado {N_MUN}, mesmos de municipios.csv)")
    # unicidade das chaves
    chaves = {
        "fichas_municipio.csv": ["cod_mun6", "modelo", "ano"], "metas_municipio.csv": ["cod_mun6", "modelo", "ano", "variavel"],
        "pares_municipio.csv": ["cod_mun6", "modelo", "ano", "ordem"], "fichas_hospital.csv": ["cnes", "ano"],
        "metas_hospital.csv": ["cnes", "ano", "variavel"], "pares_hospital.csv": ["cnes", "ano", "ordem"],
        "fichas_regiao.csv": ["co_regsaud", "ano"], "painel_ac_regiao.csv": ["co_regsaud", "ano"],
        "quadrantes_ac.csv": ["co_regsaud", "ano"], "painel_ac_macro.csv": ["co_macsaud", "ano"],
        "resumo_modelos.csv": ["modelo", "grupo", "ano"], "malmquist_regiao.csv": ["modelo", "grupo", "nivel", "co_regsaud", "periodo"],
        "especificacoes_modelos.csv": ["modelo", "grupo", "tipo", "variavel"], "insumos_produtos_hospital.csv": ["cnes", "ano", "variavel"],
    }
    for arq, k in chaves.items():
        df = arqs.get(arq)
        if df is None or df.empty:
            continue
        dup = int(df.duplicated(k).sum())
        if dup:
            erro(f"{arq}: {dup} linhas duplicadas na chave {'+'.join(k)}")
    # pares: no máximo 3 por município-modelo
    if len(pm) and pm.groupby(["cod_mun6", "modelo"]).size().max() > 3:
        erro("pares_municipio.csv: mais de 3 pares por município-modelo")
    # cnes texto de 7 dígitos
    for arq in ("fichas_hospital.csv", "metas_hospital.csv", "pares_hospital.csv", "insumos_produtos_hospital.csv"):
        df = arqs.get(arq)
        if df is not None and len(df) and not df.cnes.astype(str).str.fullmatch(r"\d{7}").all():
            erro(f"{arq}: CNES fora do padrão de 7 dígitos")
    # metas: produtos ≥ observado; insumos ≤ observado; intermediária entre observado e meta plena
    for arq, df in (("metas_municipio.csv", mm), ("metas_hospital.csv", mh)):
        x = df[df.meta_radial.notna() & df.observado.notna()]
        tol = 1e-6 * np.maximum(1.0, np.abs(x.observado))
        prod, ins = x.tipo == "produto", x.tipo == "insumo"
        viol = int(((prod & (x.meta_radial < x.observado - tol)) | (ins & (x.meta_radial > x.observado + tol))).sum())
        xi = x[x.meta_intermediaria.notna()]
        toli = 1e-6 * np.maximum(1.0, np.abs(xi.observado))
        lo = np.minimum(xi.observado, xi.meta_radial) - toli
        hi = np.maximum(xi.observado, xi.meta_radial) + toli
        viol_i = int(((xi.meta_intermediaria < lo) | (xi.meta_intermediaria > hi)).sum())
        cont[f"{arq}_violacoes_direcao"] = viol + viol_i
        if viol or viol_i:
            erro(f"{arq}: {viol} metas plenas e {viol_i} intermediárias fora do sentido esperado")
        pub = df[df.meta_publicavel == 1]
        nul = int(pub[["observado", "meta_radial", "meta_intermediaria"]].isna().any(axis=1).sum())
        if nul:
            erro(f"{arq}: {nul} metas publicáveis com valor vazio")
    # campos publicáveis sem vazio nas unidades avaliadas
    for arq, df in (("fichas_municipio.csv", fm), ("fichas_hospital.csv", fh)):
        av = df[df.situacao == "avaliado"]
        for c in ("escore_bc", "ic_inf", "ic_sup", "escore_bcc", "faixa", "posicao_estado"):
            n = int(av[c].isna().sum())
            if n:
                erro(f"{arq}: {n} avaliados sem {c}")
        for c in ("posicao_regiao", "escore_esperado", "tendencia_ec_2022_2025"):
            n = int(av[c].isna().sum())
            if n:
                cont[f"{arq}_avaliados_sem_{c}"] = n
        fora_ic = int(((av.escore_bc < av.ic_inf - 1e-9) | (av.escore_bc > av.ic_sup + 1e-9)).sum())
        if fora_ic:
            aviso(f"{arq}: {fora_ic} avaliados com escore corrigido fora do próprio IC")
    fr = arqs["fichas_regiao.csv"]
    pub = fr[fr.publicavel_m3 == 1]
    n_nul = int(pub[["escore_bc", "ic_inf", "ic_sup", "faixa"]].isna().any(axis=1).sum())
    if n_nul:
        erro(f"fichas_regiao.csv: {n_nul} regiões publicáveis sem escore/IC/faixa")
    cont["regioes_publicaveis_m3_2025"] = ", ".join(sorted(pub[pub.ano == ANO_META].regiao_saude.astype(str)))
    # nenhum 'nan' visível
    for arq, df in arqs.items():
        for c in df.columns:
            if df[c].dtype == object:
                n = int(df[c].astype(str).isin(TEXTO_NULO).sum())
                if n:
                    erro(f"{arq}: {n} células com texto nulo literal em {c}")
            elif pd.api.types.is_float_dtype(df[c]):
                if np.isinf(df[c].to_numpy(dtype=float, na_value=np.nan)).any():
                    erro(f"{arq}: valores infinitos em {c}")
    # coerência: produtos das metas do H = produtos da especificação principal vigente
    eh = espec[espec.modelo == "H"]
    p_esp = set(eh[eh.tipo == "produto"].variavel)
    p_met = set(mh[mh.tipo == "produto"].variavel)
    cont["H_produtos_principal"] = ", ".join(sorted(p_esp))
    cont["H_produtos_nas_metas"] = ", ".join(sorted(p_met))
    if p_met and p_met != p_esp:
        aviso("os produtos das metas dos hospitais (" + ", ".join(sorted(p_met)) + ") diferem da especificação principal vigente ("
              + ", ".join(sorted(p_esp)) + "): fichas do H ainda não refletem o reprocessamento — reexecutar este script depois")
    return cont


# ----------------------------------------------------------------------------
# README e catálogo
# ----------------------------------------------------------------------------
DESCR = {
    "fichas_municipio.csv": ("Fichas municipais de eficiência: uma linha por município, modelo (M1 atenção básica, M0 consolidado, M2 média complexidade, M2A média complexidade pela ótica do acesso) e ano: escore corrigido com intervalo de confiança, faixa, posição na região/macrorregião/estado, escore esperado pelo contexto, pares, evolução (Malmquist), indicadores de resultado, equidade, sinais de registro e frase-síntese.", "cod_mun6 + modelo + ano", "2020–2025"),
    "metas_municipio.csv": ("Metas por variável (2025): observado, meta plena, meta intermediária (metade da distância), potencial de melhoria em unidades, % e R$ de 2025, por mil habitantes e em valores absolutos.", "cod_mun6 + modelo + ano + variavel", "2025"),
    "pares_municipio.csv": ("Até 3 municípios de referência plausíveis por município e modelo (2025), com peso na projeção e indicação do par mais semelhante. Unidades na fronteira não têm pares, salvo quando a fronteira decorre de falta de comparável em algum recurso (referência alternativa).", "cod_mun6 + modelo + ano + ordem", "2025"),
    "fichas_hospital.csv": ("Fichas dos hospitais SUS (CNES): escore com IC, faixa, posição no grupo/região/estado, escore esperado, evolução, mortalidade hospitalar padronizada, perfil de oferta e sinais.", "cnes + ano", "2020–2025"),
    "metas_hospital.csv": ("Metas dos hospitais por variável (2025): observado, meta plena, meta intermediária, potencial.", "cnes + ano + variavel", "2025"),
    "pares_hospital.csv": ("Até 3 hospitais de referência plausíveis por hospital (2025).", "cnes + ano + ordem", "2025"),
    "insumos_produtos_hospital.csv": ("Valores observados das variáveis (recursos e produção) da especificação principal do modelo de hospitais, por hospital e ano.", "cnes + ano + variavel", "2020–2025"),
    "painel_ac_regiao.csv": ("Painel regional de acesso e produção de alta complexidade (16 regiões de saúde): internações e procedimentos de residentes e realizados na região, autossuficiência, capacidade (UTI validada, equipamentos, habilitações), despesa e tendência do acesso.", "co_regsaud + ano", "2020–2025"),
    "quadrantes_ac.csv": ("Quadrantes acesso × autossuficiência em alta complexidade por região de saúde.", "co_regsaud + ano", "2020–2025"),
    "painel_ac_macro.csv": ("Painel de alta complexidade por macrorregião de saúde.", "co_macsaud + ano", "2020–2025"),
    "fichas_regiao.csv": ("Fichas regionais de alta complexidade: painel de acesso e, para as 3 regiões publicáveis, o escore diagnóstico com IC.", "co_regsaud + ano", "2020–2025"),
    "resumo_modelos.csv": ("Resumo por modelo, grupo e ano: unidades avaliadas, escore médio e mediano, distribuição por faixa e Malmquist médio da transição.", "modelo + grupo + ano", "2020–2025"),
    "malmquist_regiao.csv": ("Malmquist agregado (média geométrica) por modelo, região de saúde e estado: transições anuais e janelas 2020–2022, 2022–2025 e 2020–2025.", "modelo + grupo + nivel + co_regsaud + periodo", "2020–2025"),
    "especificacoes_modelos.csv": ("Recursos (insumos) e produção (produtos) de cada modelo na especificação principal vigente, com nomes gerenciais, unidades e fontes.", "modelo + grupo + tipo + variavel", "—"),
    "sensibilidade.csv": ("Robustez: correlação de Spearman e mudança de tercil entre cada variante e a especificação principal.", "modelo + variante + ano/periodo", "2020–2025"),
    "parametros.csv": (f"Parâmetros e limiares de trabalho da estimação {VERSAO} (ex.: fração da meta intermediária, limiares de comparabilidade).", "chave + modelo", "—"),
    "metadados.csv": ("Metadados da geração: versão dos resultados, data, nota de versão, especificações principais e contagens.", "item", "—"),
    "dicionario_eficiencia.csv": ("Dicionário de todos os campos dos arquivos de eficiência: nome gerencial, unidade, definição e fonte.", "arquivo + campo", "—"),
}


def escrever_readme(arqs: dict[str, pd.DataFrame], cont: dict, espec: pd.DataFrame, specs_mq: dict, gerado_em: str) -> None:
    h = espec[espec.modelo == "H"]
    L = [
        "# dados_site/eficiencia/ — dicionário curto",
        "",
        f"Arquivos gerados por `scripts/06_preparar_eficiencia.py` a partir dos resultados da **versão {VERSAO.lstrip('v')}** da estimação DEA/Malmquist "
        f"(schema `dea` do PostgreSQL local, `versao = '{VERSAO}'`, somente leitura; {ROTULO_RESULTADOS}). "
        + (f"{INFO_VERSAO['nota_versao']} A versão anterior ({INFO_VERSAO['versao_anterior']}, {INFO_VERSAO['data_versao_anterior']}) "
           f"continua no banco e pode ser regerada com `--versao {INFO_VERSAO['versao_anterior']}`. " if INFO_VERSAO["nota_versao"] else "")
        +
        "CSV em UTF-8, separador vírgula, decimal ponto, vazio = indisponível ou não publicável. Booleanos em 0/1. "
        "`cnes` é texto de 7 dígitos (ler com `colClasses = list(character = 'cnes')` no `data.table::fread`). "
        "Uma cópia de cada arquivo fica em `arquivos/dados/eficiencia/` para download, com `catalogo_eficiencia.csv`.",
        "",
        "Reexecutar o script sempre que o DEA for reprocessado: a especificação principal de cada modelo é lida do banco no momento da "
        "execução (`dea.especificacoes`, `principal = TRUE`), inclusive a do modelo de hospitais; nenhum nome de produto é fixado no código.",
        "",
        "| arquivo | conteúdo | chave | período | linhas × colunas |",
        "|---|---|---|---|---|",
    ]
    for nome, df in arqs.items():
        d, k, p = DESCR.get(nome, ("", "", ""))
        L.append(f"| `{nome}` | {d} | {k} | {p} | {len(df)} × {df.shape[1]} |")
    L += [
        "",
        "## Regras",
        "",
        "- **Faixas, não ranking**: `faixa` = quartil do escore corrigido entre os publicáveis do ano no estado ('fronteira' quando o escore original = 1). "
        "`posicao_regiao` e `posicao_macro` usam a mesma régua dentro do recorte (fronteira à parte; quartis entre os avaliados fora da fronteira; "
        "sem posição com menos de 4). "
        "`ic_cruza_faixa = 1` indica que o intervalo de confiança alcança a faixa vizinha (posição incerta).",
        "- **Escore corrigido** (`escore_bc`, IC em `ic_inf`–`ic_sup`): escore BCC orientado ao produto corrigido do viés pelo bootstrap; o escore original "
        "(`escore_bcc`) fica fora do IC por construção. Linhas com `situacao` ≠ 'avaliado' não têm escore (motivo em `motivo_situacao`).",
        "- **Escore esperado pelo contexto** (`escore_esperado`) e **diferença** (`residuo_escore`): a diferença usa o escore corrigido do segundo estágio "
        "(`escore_bc_2estagio`), não o escore publicado; não é a subtração direta dos dois.",
        "- **Lacunas esperadas** (não são erro): sem escore esperado pelo contexto na média complexidade pela ótica do acesso (M2A, sem segundo estágio), "
        "nos hospitais fora do painel balanceado (`especificacao_escore = n_nao_balanceado`) e em Boa Esperança do Norte; sem tendência 2022–2025 "
        "quando há menos de duas transições publicáveis (transições marcadas, hospitais fora do painel, primeiro exercício). "
        "Na ótica do acesso há duas fronteiras (`grupo`: com e sem leito SUS) e a faixa é calculada dentro de cada uma.",
        "- **Metas**: `meta_radial` = meta plena (projeção na fronteira com folgas); `meta_intermediaria` = metade da distância entre o observado e a meta plena "
        "(limiar homologado em 08/10/2026). Colunas sem sufixo estão por mil habitantes (municípios); `*_abs` em valores absolutos do ano. "
        "`potencial_unidades` é absoluto (positivo nos produtos, negativo nos insumos). Exibir só `meta_publicavel = 1`.",
        "- **Pares** (`pares_*.csv`): até 3 por unidade, por peso decrescente, da fronteira restrita às unidades elegíveis como referência (regra da ESPEC_V2: "
        "a infactibilidade não restringe a elegibilidade). O par mais semelhante (banda de porte) está nas fichas (`par_mais_semelhante_*`); "
        f"em {cont.get('pares_fora_top3', 0)} casos de 2025 ele não está entre os 3 de maior peso.",
        "- **Malmquist**: fichas trazem MI e EC (acumulados 2020–2025 e médias anuais 2020–2022 e 2022–2025). O deslocamento tecnológico (TC) só é publicado "
        "como agregado (`resumo_modelos.csv`, `malmquist_regiao.csv`), com a nota de possível efeito do crescimento de registro no CNES após 2022. "
        "Transições marcadas (quebra de registro, SISAB incompleto) ficam fora das médias. Especificações usadas: "
        + "; ".join(f"{k} = `{v}`" for k, v in specs_mq.items() if v) + ".",
        "- **Alta complexidade**: o produto gerencial é o painel regional (16 regiões). O escore diagnóstico (M3) é publicado só para as regiões com "
        f"`publicavel_m3 = 1` (2025: {cont.get('regioes_publicaveis_m3_2025', '')}), ratificadas pelo coordenador em 08/10/2026.",
        "- **Hospitais**: especificação principal vigente no banco: `" + (h.especificacao.iloc[0] if len(h) else "—") + "` — produtos: "
        + ", ".join(h[h.tipo == "produto"].nome_gerencial) + "; insumos: " + ", ".join(h[h.tipo == "insumo"].nome_gerencial)
        + ". Decisão do coordenador (08/10/2026): principal = internações totais + diárias totais; a anterior (internações MC + AC + diárias de UTI) vira variante.",
        "- **Boa Esperança do Norte (510183)**: primeiro exercício em 2025 (`marca_parcial = 1`); fora dos modelos em 2020–2024.",
        "- Regiões com nome sem o sufixo ' - MT'; macrorregiões como em `dados_site/municipios.csv`. Monetários em R$ de 2025 (IPCA).",
        "",
        "## Validação (última execução)",
        "",
    ]
    for k, v in cont.items():
        L.append(f"- `{k}`: {v}")
    L.append(f"- avisos: {len(AVISOS)}" + ("" if not AVISOS else " — " + " | ".join(AVISOS)))
    L.append(f"- erros: {len(ERROS)}" + ("" if not ERROS else " — " + " | ".join(ERROS)))
    L.append(f"- gerado em: {gerado_em}")
    (SAIDA / "README.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    msg("  gravado dados_site/eficiencia/README.md")


def copiar_downloads(arqs: dict[str, pd.DataFrame]) -> None:
    linhas = []
    for nome, df in arqs.items():
        shutil.copyfile(SAIDA / nome, DOWN / nome)
        d, k, p = DESCR.get(nome, ("", "", ""))
        linhas.append(dict(arquivo=f"dados/eficiencia/{nome}", descricao=d, chave=k, periodo=p,
                           fonte=f"{ROTULO_RESULTADOS} — PPSUS-MT; SIOPS, CNES, SISAB, SI-PNI, SIA, SIH, SIM, SINASC, IBGE",
                           linhas=len(df), colunas=df.shape[1], bytes=(DOWN / nome).stat().st_size, gerado_por="Observatório PPSUS-MT"))
    cat = pd.DataFrame(linhas)
    cat.to_csv(DOWN / "catalogo_eficiencia.csv", index=False, encoding="utf-8", lineterminator="\n", na_rep="")
    msg("  copiados %d arquivos para arquivos/dados/eficiencia/ (+ catalogo_eficiencia.csv)", len(arqs))


# ----------------------------------------------------------------------------
# Versão 0.5 do site (24/10/2026; rodada 4, Editor D) — A CONFIRMAR: textos do sinal flag_polo_ac
# ----------------------------------------------------------------------------
# O sinal flag_polo_ac (share_ac >= 0,25; dea/v2_1/01_base_v2.py) mede só a participação da alta complexidade no valor
# aprovado da produção de média e alta complexidade (SIA + SIH) dos estabelecimentos do município e marca também
# municípios sem hospital SUS (13 dos 23 de 2025), nos quais decorre apenas de procedimentos ambulatoriais. Os textos
# que a DEA grava (nome gerencial e definição em dea.dicionario, nota_meta das metas de despesa e frase do texto_padrao)
# o chamam de "polo de alta complexidade". Esta camada sobrescreve SÓ a saída do site (dados_site/eficiencia e
# arquivos/dados/eficiencia), com a redação do diagnóstico de 24/10/2026 e a mesma descrição que o site exibe; o schema
# dea não muda, e nenhum valor numérico muda (só a troca de textos idênticos aos antigos, célula a célula).
SINAL_AC_TEXTO_ANTIGO = ("Polo de alta complexidade: parte dos insumos atende à alta complexidade (escore de média complexidade "
                         "conservador).")
SINAL_AC_TEXTO_NOVO = ("Participação elevada da alta complexidade na produção local: ao menos um quarto do valor aprovado dos "
                       "procedimentos ambulatoriais e das internações de média e alta complexidade realizados no município "
                       "corresponde à alta complexidade, o que não caracteriza, por si só, um polo regional; como parte dos insumos "
                       "pode atender à alta complexidade, o escore de média complexidade tende a ser conservador.")
SINAL_AC_NOTA_ANTIGA = "polo de alta complexidade (share_ac ≥ 0,25): parte dos insumos atende à AC; escore de MC conservador"
SINAL_AC_NOTA_NOVA = ("participação elevada da alta complexidade (share_ac ≥ 0,25): parte dos insumos pode atender à AC; "
                      "escore de MC tende a ser conservador")
SINAL_AC_DIC_ANTIGO = ("Polo de alta complexidade",
                       "share_ac ≥ 0,25 (parte dos insumos atende à alta complexidade; escore de MC conservador — informativa)")
SINAL_AC_DIC_NOVO = ("Participação elevada da alta complexidade (sinal informativo)",
                     "share_ac ≥ 0,25: participação da alta complexidade no valor aprovado da produção de média e alta complexidade "
                     "(SIA + SIH) realizada por estabelecimentos do município; informativa. Não identifica, por si só, polo de alta "
                     "complexidade: em municípios sem hospital SUS, decorre apenas de procedimentos ambulatoriais.")
ARQS_SINAL_AC = ("fichas_municipio.csv", "metas_municipio.csv", "dicionario_eficiencia.csv")


def aplica_textos_sinal_ac(nome: str, df: pd.DataFrame) -> tuple[pd.DataFrame, int]:
    """Troca, no arquivo `nome`, os textos antigos do sinal flag_polo_ac pelos novos (constantes acima). Só troca texto
    idêntico ao antigo; devolve (cópia do quadro, nº de células alteradas)."""
    df = df.copy()
    n = 0
    if nome == "fichas_municipio.csv" and "texto_padrao" in df.columns:
        m = df["texto_padrao"].map(lambda x: isinstance(x, str) and SINAL_AC_TEXTO_ANTIGO in x).astype(bool)
        df.loc[m, "texto_padrao"] = df.loc[m, "texto_padrao"].map(lambda x: x.replace(SINAL_AC_TEXTO_ANTIGO, SINAL_AC_TEXTO_NOVO))
        n = int(m.sum())
    elif nome == "metas_municipio.csv" and "nota_meta" in df.columns:
        m = df["nota_meta"].eq(SINAL_AC_NOTA_ANTIGA).fillna(False).astype(bool)
        df.loc[m, "nota_meta"] = SINAL_AC_NOTA_NOVA
        n = int(m.sum())
    elif nome == "dicionario_eficiencia.csv":
        m = (df["arquivo"].eq("fichas_municipio.csv") & df["campo"].eq("flag_polo_ac")
             & df["nome_gerencial"].eq(SINAL_AC_DIC_ANTIGO[0]) & df["definicao"].eq(SINAL_AC_DIC_ANTIGO[1])).fillna(False).astype(bool)
        df.loc[m, "nome_gerencial"] = SINAL_AC_DIC_NOVO[0]
        df.loc[m, "definicao"] = SINAL_AC_DIC_NOVO[1]
        n = 2 * int(m.sum())
    return df, n


def so_textos_sinal_ac(nome: str, antigo: bytes | None) -> bool:
    """True quando o arquivo gravado agora (SAIDA/nome) difere do conteúdo anterior SÓ pelos textos do sinal
    flag_polo_ac (aplica_textos_sinal_ac sobre o conteúdo anterior reproduz o novo, célula a célula)."""
    if antigo is None or nome not in ARQS_SINAL_AC:
        return False
    import io
    a = pd.read_csv(io.BytesIO(antigo), dtype=str, keep_default_na=False)
    b = pd.read_csv(SAIDA / nome, dtype=str, keep_default_na=False)
    a2, n = aplica_textos_sinal_ac(nome, a)
    return n > 0 and list(a2.columns) == list(b.columns) and a2.reset_index(drop=True).equals(b.reset_index(drop=True))


# ----------------------------------------------------------------------------
# Versão 0.5 do site (24/10/2026; rodada 5) — A CONFIRMAR: par de maior peso quando não há par na banda de porte
# ----------------------------------------------------------------------------
# Sem par plausível na banda de porte (par_mais_semelhante_fora_banda = 1), o par indicado pela DEA é o de maior λ entre
# os plausíveis (dea/v2_1/dea_lib_v2.py, pares_referencia), e não um par "mais semelhante" em porte. Esta camada corrige
# SÓ a saída do site (dados_site/eficiencia e arquivos/dados/eficiencia): a frase F07 do texto_padrao dessas fichas e a
# definição de mais_semelhante de pares_municipio.csv no dicionário. O schema dea não muda, e nenhum valor numérico muda
# (as frases novas não acrescentam números; só a troca de textos idênticos aos antigos, célula a célula).
PAR_F07_ANTIGO = "; par mais semelhante: "
PAR_F07_NOVO = "; par de maior peso (nenhum par na banda de porte): "
RE_PAR_F07 = re.compile(r"(Municípios de referência plausíveis: [^.]*?)" + re.escape(PAR_F07_ANTIGO))
PAR_DIC_ANTIGO = "1 = par de maior peso dentro da banda de porte (1/3 a 3 vezes o porte da unidade avaliada)"
PAR_DIC_NOVO = ("1 = par de maior peso dentro da banda de porte (1/3 a 3 vezes o porte da unidade avaliada); quando nenhum "
                "par plausível se situa na banda, o par de maior peso (par_mais_semelhante_fora_banda, em fichas_municipio.csv)")
ARQS_PAR = ("fichas_municipio.csv", "dicionario_eficiencia.csv")


def _sim(x) -> bool:
    return str(x).strip().lower() in ("1", "1.0", "true")


def aplica_textos_par(nome: str, df: pd.DataFrame) -> tuple[pd.DataFrame, int]:
    """Troca, no arquivo `nome`, os textos do par sem par na banda de porte (constantes acima). Só troca texto idêntico ao
    antigo; devolve (cópia do quadro, nº de células alteradas)."""
    df = df.copy()
    n = 0
    if nome == "fichas_municipio.csv" and {"texto_padrao", "par_mais_semelhante_fora_banda"} <= set(df.columns):
        m = (df["par_mais_semelhante_fora_banda"].map(_sim)
             & df["texto_padrao"].map(lambda x: isinstance(x, str) and RE_PAR_F07.search(x) is not None)).astype(bool)
        df.loc[m, "texto_padrao"] = df.loc[m, "texto_padrao"].map(
            lambda x: RE_PAR_F07.sub(lambda g: g.group(1) + PAR_F07_NOVO, x, count=1))
        n = int(m.sum())
    elif nome == "dicionario_eficiencia.csv":
        m = (df["arquivo"].eq("pares_municipio.csv") & df["campo"].eq("mais_semelhante")
             & df["definicao"].eq(PAR_DIC_ANTIGO)).fillna(False).astype(bool)
        df.loc[m, "definicao"] = PAR_DIC_NOVO
        n = int(m.sum())
    return df, n


def so_textos_site(nome: str, antigo: bytes | None) -> bool:
    """True quando o arquivo gravado agora (SAIDA/nome) difere do conteúdo anterior SÓ pelos textos que esta camada
    sobrescreve (sinal flag_polo_ac e par sem par na banda): aplicar as duas trocas ao conteúdo anterior reproduz o novo,
    célula a célula."""
    if antigo is None or nome not in set(ARQS_SINAL_AC) | set(ARQS_PAR):
        return False
    import io
    a = pd.read_csv(io.BytesIO(antigo), dtype=str, keep_default_na=False)
    b = pd.read_csv(SAIDA / nome, dtype=str, keep_default_na=False)
    a2, n1 = aplica_textos_sinal_ac(nome, a) if nome in ARQS_SINAL_AC else (a, 0)
    a3, n2 = aplica_textos_par(nome, a2) if nome in ARQS_PAR else (a2, 0)
    return (n1 + n2) > 0 and list(a3.columns) == list(b.columns) and a3.reset_index(drop=True).equals(b.reset_index(drop=True))


# ----------------------------------------------------------------------------
def main() -> int:
    msg("06_preparar_eficiencia.py — resultados DEA %s", VERSAO)
    mun, reg, macro = ler_site()
    con = conectar()
    try:
        msg("[1] especificações principais (lidas do banco)")
        princ = especificacoes_principais(con)
        for r in princ.itertuples():
            msg("  %s: %s — insumos: %s | produtos: %s", r.modelo, r.variante, r.insumos, r.produtos)
        espec = tabela_especificacoes(con, princ)

        msg("[2] fichas e metas municipais")
        fm = preparar_fichas_mun(con, mun, macro)
        mm = preparar_metas_mun(con, mun)
        pm, fora_top3 = preparar_pares_mun(con, mun)
        fm, pm, info_ref = ajustar_referencias_e_textos(fm, pm)
        msg("  pares ocultados (unidades na fronteira sem falta de comparável): %d; referências recontadas em 2025: %d",
            info_ref["pares_ocultados_fronteira_2025"], info_ref["n_vezes_referencia_recontadas_2025"])

        msg("[3] hospitais")
        fh = preparar_fichas_hosp(con, mun, macro)
        mh = preparar_metas_hosp(con)
        ph = preparar_pares_hosp(con)
        vh = preparar_vars_hosp(con, espec)

        msg("[4] alta complexidade")
        ac = preparar_ac(con, reg, macro)

        msg("[5] Malmquist e resumo por modelo")
        mqs, specs_mq, mqr = preparar_malmquist(con, fm, fh, dict(zip(reg.co_regsaud.astype(str), reg.regiao_saude)))
        res = preparar_resumo(fm, fh, ac["fichas_regiao.csv"], mqs)
        mqr = normalizar(mqr)

        msg("[6] sensibilidade, parâmetros, metadados")
        sen = ler_tabela(con, "sensibilidade").drop(columns=["versao"])
        # desempate pelo conteúdo da linha: a ordem de retorno do banco não é fixa e não deve sujar o diff entre execuções
        sen["_desempate"] = sen.apply(lambda s: s.map(lambda v: "" if pd.isna(v) else str(v))).agg("|".join, axis=1)
        sen = sen.sort_values(["modelo", "variante", "ano", "_desempate"]).drop(columns="_desempate")
        sen = normalizar(sen.reset_index(drop=True))
        par = ler_tabela(con, "parametros").drop(columns=["versao"]).rename(columns={"valor": "valor_parametro"})
        # a nota de versão diz quais modelos foram reestimados: confere com o registro do banco (dea.parametros, v21_*)
        if VERSAO == "v2.1":
            reest = par.loc[par.chave == "v21_modelos_reestimados", "valor_parametro"]
            esperado = '["' + '", "'.join(INFO_VERSAO["modelos_reestimados"].split(",")) + '"]'
            if not len(reest) or reest.iloc[0].strip() != esperado:
                erro(f"v21_modelos_reestimados no banco ({reest.iloc[0] if len(reest) else 'ausente'}) difere da nota de versão ({esperado})")
        # parâmetros de documentação interna com caminho da máquina (ex.: pasta do código da v2.1) não são publicados
        local = par.valor_parametro.astype(str).str.contains(PADRAO_CAMINHO_LOCAL)
        if local.any():
            msg("  parâmetros com caminho local fora do arquivo público: %s", ", ".join(sorted(par.chave[local])))
        par = par[~local]
        par = normalizar(par.sort_values(["modelo", "chave"], na_position="first").reset_index(drop=True))
        dic_db = ler_tabela(con, "dicionario")
    finally:
        con.close()

    meta = [("versao_resultados", VERSAO), ("data_resultados", DATA_RESULTADOS), ("gerado_em", ""),
            ("versao_anterior", INFO_VERSAO["versao_anterior"]), ("data_versao_anterior", INFO_VERSAO["data_versao_anterior"]),
            ("modelos_reestimados", INFO_VERSAO["modelos_reestimados"]), ("relatorio_tecnico", INFO_VERSAO["relatorio_tecnico"]),
            ("nota_versao", INFO_VERSAO["nota_versao"])]
    for r in princ.itertuples():
        meta.append((f"especificacao_principal_{r.modelo}", r.variante))
    for k, v in specs_mq.items():
        meta.append((f"especificacao_malmquist_{k}", v))
    meta.append(("municipios_2025", N_MUN))
    meta.append(("hospitais_2025", int(fh[fh.ano == ANO_META].cnes.nunique())))
    meta.append(("hospitais_avaliados_2025", int(((fh.ano == ANO_META) & (fh.situacao == "avaliado")).sum())))
    md = pd.DataFrame(meta, columns=["item", "valor"])

    arqs = {
        "fichas_municipio.csv": fm, "metas_municipio.csv": mm, "pares_municipio.csv": pm,
        "fichas_hospital.csv": fh, "metas_hospital.csv": mh, "pares_hospital.csv": ph, "insumos_produtos_hospital.csv": vh,
        "painel_ac_regiao.csv": ac["painel_ac_regiao.csv"], "quadrantes_ac.csv": ac["quadrantes_ac.csv"],
        "painel_ac_macro.csv": ac["painel_ac_macro.csv"], "fichas_regiao.csv": ac["fichas_regiao.csv"],
        "resumo_modelos.csv": res, "malmquist_regiao.csv": mqr, "especificacoes_modelos.csv": normalizar(espec),
        "sensibilidade.csv": sen, "parametros.csv": par, "metadados.csv": md,
    }
    # nenhum nome de tabela, coluna técnica ou script nos textos publicados
    for nome, df in arqs.items():
        for c in df.columns:
            if df[c].dtype == object or pd.api.types.is_string_dtype(df[c]):
                df[c] = df[c].map(sem_nomes_internos)
    msg("[7] dicionário e validação")
    dic = preparar_dicionario(dic_db, arqs)
    arqs["dicionario_eficiencia.csv"] = dic
    # versão 0.5 do site (A CONFIRMAR): textos do sinal flag_polo_ac só na saída do site (o schema dea não muda)
    for nome in ARQS_SINAL_AC:
        arqs[nome], n_sub = aplica_textos_sinal_ac(nome, arqs[nome])
        msg("  sinal de participação da alta complexidade (flag_polo_ac): %d célula(s) de texto reescrita(s) em %s", n_sub, nome)
    # versão 0.5 do site (rodada 5, A CONFIRMAR): par de maior peso quando não há par na banda de porte (só na saída do site)
    for nome in ARQS_PAR:
        arqs[nome], n_sub = aplica_textos_par(nome, arqs[nome])
        msg("  par de maior peso sem par na banda de porte: %d célula(s) de texto reescrita(s) em %s", n_sub, nome)
    cont = validar(arqs, mun, espec)
    cont.update(info_ref)
    cont["pares_fora_top3"] = fora_top3
    cont["limpezas_texto_nulo"] = LIMPEZAS["texto_nan"]
    for nome, df in arqs.items():
        cont[f"linhas_{nome}"] = len(df)

    msg("[8] gravação")
    # 'gerado_em' só muda quando algum arquivo de dados muda (execuções repetidas não sujam o diff)
    antes = {n: hashlib.md5((SAIDA / n).read_bytes()).hexdigest() for n in arqs if (SAIDA / n).exists()}
    antigos_sinal = {n: (SAIDA / n).read_bytes() for n in set(ARQS_SINAL_AC) | set(ARQS_PAR) if (SAIDA / n).exists()}
    gerado_antigo = None
    if (SAIDA / "metadados.csv").exists():
        mdv = pd.read_csv(SAIDA / "metadados.csv", dtype=str)
        g = mdv.loc[mdv["item"] == "gerado_em", "valor"]
        gerado_antigo = g.iloc[0] if len(g) and isinstance(g.iloc[0], str) and g.iloc[0].strip() else None
    for nome, df in arqs.items():
        if nome != "metadados.csv":
            gravar(df, nome)
    mudou = [n for n in arqs if n != "metadados.csv" and antes.get(n) != hashlib.md5((SAIDA / n).read_bytes()).hexdigest()]
    # versão 0.5 do site (A CONFIRMAR): a troca dos textos do sinal flag_polo_ac e (rodada 5) do par sem par na banda de
    # porte não é mudança de dados (gerado_em preservado)
    so_sinal = [n for n in mudou if so_textos_site(n, antigos_sinal.get(n))]
    if so_sinal:
        msg("  arquivos que mudaram só nos textos do sinal flag_polo_ac ou do par (não contam para gerado_em): %s", ", ".join(so_sinal))
    mudou = [n for n in mudou if n not in so_sinal]
    gerado_em = gerado_antigo if (gerado_antigo and not mudou) else f"{dt.datetime.now():%d/%m/%Y %H:%M}"
    msg("  arquivos alterados nesta execução: %s", ", ".join(mudou) if mudou else "nenhum (gerado_em preservado)")
    md.loc[md["item"] == "gerado_em", "valor"] = gerado_em
    gravar(md, "metadados.csv")
    escrever_readme(arqs, cont, espec, specs_mq, gerado_em)
    copiar_downloads(arqs)
    # varredura final: nenhum CSV publicado com nome de tabela interna ou de script
    for pasta in (SAIDA, DOWN):
        for arq in sorted(pasta.glob("*.csv")):
            txt = arq.read_text(encoding="utf-8")
            achados = sorted(set(m.group(0) for m in PADRAO_INTERNO.finditer(txt)))
            if achados:
                erro(f"{arq.relative_to(RAIZ).as_posix()}: nomes internos no texto publicado: {', '.join(achados[:8])}")
            if PADRAO_CAMINHO_LOCAL.search(txt):
                erro(f"{arq.relative_to(RAIZ).as_posix()}: caminho local da máquina no texto publicado")

    msg("Resumo da validação:")
    for k, v in cont.items():
        msg("  %s: %s", k, v)
    msg("Avisos: %d | Erros: %d", len(AVISOS), len(ERROS))
    return 1 if ERROS else 0


if __name__ == "__main__":
    sys.exit(main())
