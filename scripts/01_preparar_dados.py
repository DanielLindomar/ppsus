# -*- coding: utf-8 -*-
"""
01_preparar_dados.py — Observatório PPSUS-MT

Lê os marts do DEA no PostgreSQL local (somente leitura), a malha IBGE em
arquivos/geo/ e as sedes municipais de dados_site/sedes_municipais.csv (script 00),
e grava os arquivos do contrato (BRIEF_SITE.md, seção 3):

  dados_site/municipios.csv, indicadores.csv, serie.csv, regioes.csv,
  serie_regiao.csv, serie_mt.csv, hospitais.csv, geo_mt.geojson,
  centroides.csv, README_dados.md
  arquivos/dados/painel_municipal_2020_2025.csv, serie_longa.csv,
  indicadores_dicionario.csv, hospitais_sus_mt.csv, regioes_saude_mt.csv

Se dados_site/deslocamento_mun_ano.csv existir (agente de deslocamento),
os indicadores pct_internacoes_fora_regiao e km_medio_internacao são
incorporados a serie.csv, serie_regiao.csv e serie_mt.csv; caso contrário,
basta reexecutar este script depois que o arquivo for gerado.

centroides.csv (contrato: cod_mun6, lon, lat) recebe as coordenadas das SEDES
municipais (IBGE, Localidades 2022) quando dados_site/sedes_municipais.csv existe;
só na ausência desse arquivo cai no centro geométrico do polígono da malha (com aviso).

Uso (a partir da raiz do repositório, depois de scripts/00_sedes_ibge.py):  python scripts/01_preparar_dados.py
Requisitos: Python 3.12, psycopg2, pandas (shapely só no fallback geométrico).
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg2

warnings.filterwarnings("ignore", category=UserWarning)  # pandas + DBAPI2

# ----------------------------------------------------------------------------
# Configuração
# ----------------------------------------------------------------------------
RAIZ = Path(__file__).resolve().parents[1]
DADOS = RAIZ / "dados_site"
DOWN = RAIZ / "arquivos" / "dados"
GEO_IN = RAIZ / "arquivos" / "geo" / "mt_municipios_ibge_minima.geojson"
ARQ_DESLOC = DADOS / "deslocamento_mun_ano.csv"
ARQ_SEDES = DADOS / "sedes_municipais.csv"  # script 00 (IBGE, Localidades 2022)
SENHA = Path(r"D:\ppsus_repo\.pgpass_superuser.txt")

ANOS = list(range(2020, 2026))
ANO_MAX = 2025
ANO_MAX_RESULTADOS = 2024  # SIM/SINASC disponíveis até 2024
COD_BOA_ESPERANCA = 510183  # município instalado em 2025; ausente na malha IBGE

DADOS.mkdir(exist_ok=True)
DOWN.mkdir(parents=True, exist_ok=True)


def msg(texto: str, *args) -> None:
    print(texto % args if args else texto, flush=True)


def conectar():
    senha = SENHA.read_text(encoding="utf-8").strip().splitlines()[0].strip()
    con = psycopg2.connect(
        host="localhost", port=5432, dbname="airflow", user="airflow", password=senha,
        options="-c default_transaction_read_only=on",  # garantia extra: nunca escrever
    )
    con.set_client_encoding("UTF8")
    return con


def ler_sql(con, sql: str) -> pd.DataFrame:
    return pd.read_sql(sql, con)


def gravar(df: pd.DataFrame, caminho: Path) -> None:
    """CSV UTF-8, vírgula, decimal ponto, NA vazio."""
    df.to_csv(caminho, index=False, encoding="utf-8", lineterminator="\n", na_rep="")
    msg("  gravado %s (%d linhas)", caminho.relative_to(RAIZ), len(df))


def slugify(nome: str) -> str:
    s = unicodedata.normalize("NFKD", nome).encode("ascii", "ignore").decode()
    s = re.sub(r"[^A-Za-z0-9]+", "-", s.lower())
    return s.strip("-")


def dv_ibge(cod6: int) -> int:
    """Dígito verificador do código IBGE de município (7 dígitos)."""
    soma = 0
    for i, d in enumerate(f"{cod6:06d}"):
        p = int(d) * (1 if i % 2 == 0 else 2)
        soma += p - 9 if p >= 10 else p
    return (10 - soma % 10) % 10


def limpar_regiao(nome: str) -> str:
    return re.sub(r"\s*-\s*MT\s*$", "", nome).strip()


def limpar_macro(nome: str) -> str:
    return re.sub(r"^MACRORREGIAO\s+", "", nome.strip(), flags=re.I).title()


def fmt_valor(v, fmt: str) -> str:
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return ""
    if fmt == "int":
        return str(int(round(v)))
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


# ----------------------------------------------------------------------------
# Catálogo de indicadores
#   num/den: colunas do mart usadas para (re)calcular o valor municipal e os
#   agregados (região, MT) com totais; mult: fator; agg='soma' para contagens,
#   'razao' para num/den, 'pond' para percentuais já calculados ponderados por
#   `den`; 'externo' para os que vêm de deslocamento_mun_ano.csv.
# ----------------------------------------------------------------------------
NOTA_SUBFUNCAO = (
    "A classificação por subfunção do SIOPS é pouco confiável em alguns municípios "
    "(Várzea Grande, Cuiabá, Rondolândia, Alto Boa Vista e Planalto da Serra lançam grande "
    "parte da despesa em 'outras subfunções'); prefira a despesa total para comparações."
)
NOTA_FTE = (
    "FTE = vínculos com atendimento SUS em equivalente a 40 h semanais; média das competências "
    "do ano (CNES). O crescimento ao longo do tempo pode refletir melhoria do registro, não apenas expansão real."
)
NOTA_PEQUENOS = "Instável em municípios pequenos (menos de 100 nascidos vivos por ano); compare com a região e a série."

CATALOGO = [
    # id, rotulo, grupo, unidade, fmt, sentido, fonte, num, den, mult, agg, formula, nota, kpi, ano_max, descricao
    dict(id="populacao", rotulo="População", grupo="contexto", unidade="habitantes", fmt="int", sentido=0,
         fonte="IBGE", num="populacao", den=None, mult=1, agg="soma",
         formula="Estimativa populacional do IBGE (2022 = Censo; 2023 = interpolação entre o Censo 2022 e a estimativa 2024)",
         nota="Boa Esperança do Norte só tem população a partir de 2025 (município instalado em 2025).",
         kpi=0, ano_max=2025, descricao="Número de habitantes residentes no município."),

    # ---- financiamento (SIOPS, R$ correntes, despesa liquidada) ----
    dict(id="desp_total_pc", rotulo="Despesa em saúde por habitante", grupo="financiamento", unidade="R$ por habitante", fmt="brl", sentido=0,
         fonte="SIOPS (RREO)", num="desp_total_saude", den="populacao", mult=1, agg="razao",
         formula="desp_total_saude / populacao",
         nota="Despesa liquidada do município na função Saúde, acumulada no ano, em R$ correntes (sem deflação); inclui todas as fontes (recursos próprios e transferências).",
         kpi=1, ano_max=2025, descricao="Quanto o município liquidou em saúde no ano, por habitante."),
    dict(id="desp_ab_pc", rotulo="Despesa em atenção básica por habitante", grupo="financiamento", unidade="R$ por habitante", fmt="brl", sentido=0,
         fonte="SIOPS (RREO)", num="desp_301_atencao_basica", den="populacao", mult=1, agg="razao",
         formula="desp_301_atencao_basica / populacao  (subfunção 301)",
         nota=NOTA_SUBFUNCAO, kpi=0, ano_max=2025, descricao="Despesa liquidada na subfunção Atenção Básica (301), por habitante."),
    dict(id="desp_mac_pc", rotulo="Despesa em média e alta complexidade por habitante", grupo="financiamento", unidade="R$ por habitante", fmt="brl", sentido=0,
         fonte="SIOPS (RREO)", num="desp_302_mac", den="populacao", mult=1, agg="razao",
         formula="desp_302_mac / populacao  (subfunção 302 — assistência hospitalar e ambulatorial)",
         nota=NOTA_SUBFUNCAO, kpi=0, ano_max=2025, descricao="Despesa liquidada na subfunção Assistência Hospitalar e Ambulatorial (302), por habitante."),
    dict(id="pct_recursos_proprios", rotulo="Despesa com recursos próprios", grupo="financiamento", unidade="% da despesa total", fmt="pct1", sentido=0,
         fonte="SIOPS (RREO)", num="desp_recursos_proprios", den="desp_total_saude", mult=100, agg="razao",
         formula="100 × desp_recursos_proprios / desp_total_saude",
         nota="Parcela da despesa em saúde financiada com receitas próprias do município (impostos e transferências constitucionais), e não com transferências do SUS. Valores fora de 0–100% (lançamentos negativos no SIOPS: Novo Santo Antônio 2020, Peixoto de Azevedo 2021) foram anulados.",
         kpi=0, ano_max=2025, descricao="Parcela da despesa em saúde paga com receitas próprias do município."),
    dict(id="pct_capital", rotulo="Despesa de capital", grupo="financiamento", unidade="% da despesa total", fmt="pct1", sentido=0,
         fonte="SIOPS (RREO)", num="desp_capital", den="desp_total_saude", mult=100, agg="razao",
         formula="100 × desp_capital / desp_total_saude",
         nota="Investimentos (obras, equipamentos) em relação à despesa total; oscila muito de um ano para outro.",
         kpi=0, ano_max=2025, descricao="Parcela da despesa em saúde destinada a investimentos."),

    # ---- capacidade (CNES, média anual, vínculos SUS) ----
    dict(id="fte_medicos_p1000", rotulo="Médicos SUS por mil habitantes", grupo="capacidade", unidade="FTE por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="fte_medicos_sus", den="populacao", mult=1000, agg="razao",
         formula="1000 × fte_medicos_sus / populacao", nota=NOTA_FTE, kpi=1, ano_max=2025,
         descricao="Médicos com atendimento SUS, em equivalentes de 40 h semanais, por mil habitantes."),
    dict(id="fte_enfermeiros_p1000", rotulo="Enfermeiros SUS por mil habitantes", grupo="capacidade", unidade="FTE por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="fte_enfermeiros_sus", den="populacao", mult=1000, agg="razao",
         formula="1000 × fte_enfermeiros_sus / populacao", nota=NOTA_FTE, kpi=0, ano_max=2025,
         descricao="Enfermeiros com atendimento SUS (FTE 40 h) por mil habitantes."),
    dict(id="fte_tec_enfermagem_p1000", rotulo="Técnicos de enfermagem SUS por mil habitantes", grupo="capacidade", unidade="FTE por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="fte_tec_enfermagem_sus", den="populacao", mult=1000, agg="razao",
         formula="1000 × fte_tec_enfermagem_sus / populacao", nota=NOTA_FTE, kpi=0, ano_max=2025,
         descricao="Técnicos de enfermagem com atendimento SUS (FTE 40 h) por mil habitantes."),
    dict(id="fte_acs_p1000", rotulo="Agentes comunitários de saúde por mil habitantes", grupo="capacidade", unidade="FTE por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="fte_acs", den="populacao", mult=1000, agg="razao",
         formula="1000 × fte_acs / populacao", nota=NOTA_FTE, kpi=0, ano_max=2025,
         descricao="Agentes comunitários de saúde (FTE 40 h) por mil habitantes."),
    dict(id="fte_dentistas_p1000", rotulo="Dentistas SUS por mil habitantes", grupo="capacidade", unidade="FTE por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="fte_dentistas_sus", den="populacao", mult=1000, agg="razao",
         formula="1000 × fte_dentistas_sus / populacao", nota=NOTA_FTE, kpi=0, ano_max=2025,
         descricao="Cirurgiões-dentistas com atendimento SUS (FTE 40 h) por mil habitantes."),
    dict(id="leitos_sus_p1000", rotulo="Leitos SUS por mil habitantes", grupo="capacidade", unidade="leitos por mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="leitos_sus", den="populacao", mult=1000, agg="razao",
         formula="1000 × leitos_sus / populacao",
         nota="Leitos de internação disponíveis ao SUS; média das competências do ano. Municípios sem hospital SUS têm valor zero.",
         kpi=1, ano_max=2025, descricao="Leitos de internação disponíveis ao SUS por mil habitantes."),
    dict(id="leitos_uti_sus", rotulo="Leitos de UTI SUS", grupo="capacidade", unidade="leitos", fmt="int", sentido=0,
         fonte="CNES", num="leitos_uti_sus", den=None, mult=1, agg="soma",
         formula="leitos_uti_sus (média das competências do ano)",
         nota="Sub-registro no CNES: há hospitais com UTI em funcionamento e zero leitos de UTI SUS declarados; em 2020–2021 inclui leitos COVID.",
         kpi=0, ano_max=2025, descricao="Leitos de UTI disponíveis ao SUS (média anual)."),
    dict(id="equip_sus_p10000", rotulo="Equipamentos SUS em uso por 10 mil habitantes", grupo="capacidade", unidade="equipamentos por 10 mil hab.", fmt="dec1", sentido=1,
         fonte="CNES", num="equip_sus_uso", den="populacao", mult=10000, agg="razao",
         formula="10000 × equip_sus_uso / populacao",
         nota="Equipamentos declarados em uso e disponíveis ao SUS (todas as categorias, sem ponderação); a série cresce com a melhoria do registro.",
         kpi=0, ano_max=2025, descricao="Equipamentos em uso disponíveis ao SUS por 10 mil habitantes."),
    dict(id="n_ubs", rotulo="Unidades básicas de saúde", grupo="capacidade", unidade="unidades", fmt="int", sentido=0,
         fonte="CNES", num="n_ubs", den=None, mult=1, agg="soma",
         formula="n_ubs (média das competências do ano)", nota="Estabelecimentos do tipo centro de saúde/unidade básica com atendimento SUS.",
         kpi=0, ano_max=2025, descricao="Número de unidades básicas de saúde (média anual)."),
    dict(id="n_hospitais_sus", rotulo="Hospitais SUS", grupo="capacidade", unidade="hospitais", fmt="int", sentido=0,
         fonte="CNES", num="n_hospitais_sus", den=None, mult=1, agg="soma",
         formula="n_hospitais_sus (média das competências do ano)",
         nota="Hospitais (gerais, especializados e de dia) com atendimento SUS; 53 municípios não tinham hospital SUS em 2025.",
         kpi=0, ano_max=2025, descricao="Número de hospitais com atendimento SUS (média anual)."),
    dict(id="n_upa", rotulo="Unidades de pronto atendimento", grupo="capacidade", unidade="unidades", fmt="int", sentido=0,
         fonte="CNES", num="n_upa", den=None, mult=1, agg="soma",
         formula="n_upa (média das competências do ano)", nota="", kpi=0, ano_max=2025,
         descricao="Número de UPA/pronto atendimento com atendimento SUS (média anual)."),
    dict(id="n_estab_sus", rotulo="Estabelecimentos com atendimento SUS", grupo="capacidade", unidade="estabelecimentos", fmt="int", sentido=0,
         fonte="CNES", num="n_estab_sus", den=None, mult=1, agg="soma",
         formula="n_estab_sus (média das competências do ano)", nota="Todos os tipos de estabelecimento com atendimento SUS.",
         kpi=0, ano_max=2025, descricao="Número de estabelecimentos de saúde com atendimento SUS (média anual)."),
    dict(id="equipes_esf_p10000", rotulo="Equipes de Saúde da Família por 10 mil habitantes", grupo="capacidade", unidade="equipes por 10 mil hab.", fmt="dec2", sentido=1,
         fonte="CNES", num="n_equipes_esf", den="populacao", mult=10000, agg="razao",
         formula="10000 × n_equipes_esf / populacao",
         nota="Equipes eSF (tipo 70 e códigos antigos); média das competências do ano. Referência usual: 1 equipe para 2 mil a 3,5 mil habitantes (2,9 a 5 por 10 mil).",
         kpi=0, ano_max=2025, descricao="Equipes de Saúde da Família por 10 mil habitantes."),
    dict(id="n_equipes_eap", rotulo="Equipes de atenção primária (eAP)", grupo="capacidade", unidade="equipes", fmt="int", sentido=0,
         fonte="CNES", num="n_equipes_eap", den=None, mult=1, agg="soma",
         formula="n_equipes_eap (média das competências do ano)", nota="", kpi=0, ano_max=2025,
         descricao="Equipes de atenção primária (modalidade eAP), média anual."),
    dict(id="n_equipes_esb", rotulo="Equipes de saúde bucal", grupo="capacidade", unidade="equipes", fmt="int", sentido=0,
         fonte="CNES", num="n_equipes_esb", den=None, mult=1, agg="soma",
         formula="n_equipes_esb (média das competências do ano)", nota="", kpi=0, ano_max=2025,
         descricao="Equipes de saúde bucal (eSB), média anual."),

    # ---- atenção básica (SISAB, SI-PNI) ----
    dict(id="atend_individual_pc", rotulo="Atendimentos individuais na atenção básica por habitante", grupo="atencao_basica", unidade="atendimentos por hab.", fmt="dec2", sentido=1,
         fonte="SISAB", num="sisab_atend_individual", den="populacao", mult=1, agg="razao",
         formula="sisab_atend_individual / populacao",
         nota="Atendimentos individuais registrados no SISAB (e-SUS APS) por profissionais da atenção básica; o registro caiu em 2020 (pandemia) e cresce com a informatização.",
         kpi=1, ano_max=2025, descricao="Atendimentos individuais da atenção básica por habitante no ano."),
    dict(id="procedimentos_ab_pc", rotulo="Procedimentos na atenção básica por habitante", grupo="atencao_basica", unidade="procedimentos por hab.", fmt="dec2", sentido=1,
         fonte="SISAB", num="sisab_procedimentos", den="populacao", mult=1, agg="razao",
         formula="sisab_procedimentos / populacao", nota="Procedimentos registrados no SISAB (curativos, vacinas, coletas etc.).",
         kpi=0, ano_max=2025, descricao="Procedimentos da atenção básica por habitante no ano."),
    dict(id="visitas_pc", rotulo="Visitas domiciliares por habitante", grupo="atencao_basica", unidade="visitas por hab.", fmt="dec2", sentido=1,
         fonte="SISAB", num="sisab_visitas_domiciliares", den="populacao", mult=1, agg="razao",
         formula="sisab_visitas_domiciliares / populacao", nota="Visitas registradas no SISAB, sobretudo por agentes comunitários de saúde.",
         kpi=0, ano_max=2025, descricao="Visitas domiciliares da atenção básica por habitante no ano."),
    dict(id="atend_odonto_pc", rotulo="Atendimentos odontológicos por habitante", grupo="atencao_basica", unidade="atendimentos por hab.", fmt="dec2", sentido=1,
         fonte="SISAB", num="sisab_atend_odonto", den="populacao", mult=1, agg="razao",
         formula="sisab_atend_odonto / populacao", nota="", kpi=0, ano_max=2025,
         descricao="Atendimentos odontológicos individuais na atenção básica por habitante."),
    dict(id="doses_menor1_por_nv", rotulo="Doses de vacina em menores de 1 ano por nascido vivo", grupo="atencao_basica", unidade="doses por nascido vivo", fmt="dec2", sentido=1,
         fonte="SI-PNI / SINASC", num="sipni_doses_menor1_local", den="nascidos_vivos", mult=1, agg="razao",
         formula="sipni_doses_menor1_local / nascidos_vivos",
         nota="Doses aplicadas no município (local de aplicação) em menores de 1 ano, sem COVID, por nascido vivo de mãe residente; até 2024 (limite do SINASC). Municípios-polo aplicam doses em crianças de outros municípios.",
         kpi=0, ano_max=2024, descricao="Doses aplicadas em menores de 1 ano por nascido vivo residente."),
    dict(id="doses_pc", rotulo="Doses de vacina aplicadas por habitante", grupo="atencao_basica", unidade="doses por hab.", fmt="dec2", sentido=1,
         fonte="SI-PNI", num="sipni_doses_local", den="populacao", mult=1, agg="razao",
         formula="sipni_doses_local / populacao",
         nota="Doses de todas as vacinas de rotina aplicadas no município, sem COVID.", kpi=0, ano_max=2025,
         descricao="Doses de vacina de rotina aplicadas no município por habitante."),

    # ---- média e alta complexidade (SIA/SIH) ----
    dict(id="qtd_mc_local_pc", rotulo="Procedimentos de média complexidade por habitante", grupo="media_alta", unidade="procedimentos por hab.", fmt="dec2", sentido=1,
         fonte="SIA/SUS", num="qtd_mc_local", den="populacao", mult=1, agg="razao",
         formula="qtd_mc_local / populacao",
         nota="Procedimentos ambulatoriais aprovados de média complexidade realizados em estabelecimentos do município (inclui pacientes de outros municípios). Valores extremos por registro consolidado (BPA-C) em alguns municípios.",
         kpi=0, ano_max=2025, descricao="Procedimentos ambulatoriais de média complexidade realizados no município por habitante."),
    dict(id="qtd_ac_local_pc", rotulo="Procedimentos de alta complexidade por habitante", grupo="media_alta", unidade="procedimentos por hab.", fmt="dec2", sentido=1,
         fonte="SIA/SUS", num="qtd_ac_local", den="populacao", mult=1, agg="razao",
         formula="qtd_ac_local / populacao",
         nota="Procedimentos ambulatoriais de alta complexidade realizados no município; concentrados nos polos regionais (a maioria dos municípios tem zero).",
         kpi=0, ano_max=2025, descricao="Procedimentos ambulatoriais de alta complexidade realizados no município por habitante."),
    dict(id="internacoes_local_p1000", rotulo="Internações realizadas no município por mil habitantes", grupo="media_alta", unidade="internações por mil hab.", fmt="dec1", sentido=0,
         fonte="SIH/SUS", num="internacoes_local", den="populacao", mult=1000, agg="razao",
         formula="1000 × internacoes_local / populacao",
         nota="AIH pagas (tipo 1) por hospitais do município, ano da alta; inclui pacientes de outros municípios. Zero onde não há hospital SUS.",
         kpi=0, ano_max=2025, descricao="Internações SUS realizadas em hospitais do município por mil habitantes."),
    dict(id="internacoes_res_p1000", rotulo="Internações de residentes por mil habitantes", grupo="media_alta", unidade="internações por mil hab.", fmt="dec1", sentido=0,
         fonte="SIH/SUS", num="internacoes_res", den="populacao", mult=1000, agg="razao",
         formula="1000 × internacoes_res / populacao",
         nota="Internações SUS de moradores do município em qualquer hospital de MT; não inclui internações fora do estado (não observadas).",
         kpi=0, ano_max=2025, descricao="Internações SUS de moradores do município por mil habitantes."),
    dict(id="pct_urgencia", rotulo="Internações de urgência", grupo="media_alta", unidade="% das internações locais", fmt="pct1", sentido=0,
         fonte="SIH/SUS", num="internacoes_urgencia_local", den="internacoes_local", mult=100, agg="razao",
         formula="100 × internacoes_urgencia_local / internacoes_local",
         nota="Caráter de internação diferente de eletivo, nas internações realizadas no município. Vazio onde não há internação local.",
         kpi=0, ano_max=2025, descricao="Parcela das internações realizadas no município com caráter de urgência."),
    dict(id="mortalidade_hosp_pct", rotulo="Mortalidade hospitalar", grupo="media_alta", unidade="% das internações locais", fmt="pct1", sentido=-1,
         fonte="SIH/SUS", num="obitos_hosp_local", den="internacoes_local", mult=100, agg="razao",
         formula="100 × obitos_hosp_local / internacoes_local",
         nota="Óbitos nas internações realizadas no município, sem ajuste de risco (hospitais de referência recebem casos mais graves). Em 2020–2021 refletiu a COVID-19. Vazio onde não há internação local.",
         kpi=0, ano_max=2025, descricao="Parcela das internações realizadas no município que terminaram em óbito."),
    dict(id="permanencia_media", rotulo="Permanência média das internações", grupo="media_alta", unidade="dias", fmt="dec1", sentido=0,
         fonte="SIH/SUS", num="diarias_local", den="internacoes_local", mult=1, agg="razao",
         formula="diarias_local / internacoes_local",
         nota="Diárias pagas por internação nos hospitais do município. Vazio onde não há internação local.",
         kpi=0, ano_max=2025, descricao="Média de dias por internação nos hospitais do município."),
    dict(id="diarias_uti_p1000", rotulo="Diárias de UTI por mil habitantes", grupo="media_alta", unidade="diárias por mil hab.", fmt="dec1", sentido=0,
         fonte="SIH/SUS", num="diarias_uti_local", den="populacao", mult=1000, agg="razao",
         formula="1000 × diarias_uti_local / populacao",
         nota="Diárias de UTI pagas em hospitais do município; concentradas nos polos.", kpi=0, ano_max=2025,
         descricao="Diárias de UTI pagas em hospitais do município por mil habitantes."),
    dict(id="valor_sih_local_pc", rotulo="Valor das internações realizadas no município por habitante", grupo="media_alta", unidade="R$ por habitante", fmt="brl", sentido=0,
         fonte="SIH/SUS", num="valor_sih_local", den="populacao", mult=1, agg="razao",
         formula="valor_sih_local / populacao",
         nota="Valor aprovado das AIH pagas a hospitais do município, R$ correntes (produção, não despesa).", kpi=0, ano_max=2025,
         descricao="Valor pago pelo SUS às internações realizadas no município, por habitante."),
    dict(id="valor_sih_res_pc", rotulo="Valor das internações de residentes por habitante", grupo="media_alta", unidade="R$ por habitante", fmt="brl", sentido=0,
         fonte="SIH/SUS", num="valor_sih_res", den="populacao", mult=1, agg="razao",
         formula="valor_sih_res / populacao",
         nota="Valor aprovado das AIH de moradores do município, onde quer que tenham sido internados em MT; R$ correntes.", kpi=0, ano_max=2025,
         descricao="Valor pago pelo SUS às internações de moradores do município, por habitante."),

    # ---- deslocamento (SIH, residentes) ----
    dict(id="pct_internacoes_fora_mun", rotulo="Internações fora do município de residência", grupo="deslocamento", unidade="% das internações de residentes", fmt="pct1", sentido=-1,
         fonte="SIH/SUS", num="internacoes_res_fora", den="internacoes_res", mult=100, agg="razao",
         formula="100 × internacoes_res_fora / internacoes_res",
         nota="Parcela dos moradores internados em hospitais de outro município de MT. Menor valor indica mais atendimento local, mas não é 'ruim' em si: a alta complexidade é regionalizada por desenho. Vazio quando não há internação de residentes.",
         kpi=1, ano_max=2025, descricao="Parcela das internações de moradores realizadas em outro município."),
    dict(id="pct_internacoes_fora_regiao", rotulo="Internações fora da região de saúde", grupo="deslocamento", unidade="% das internações de residentes", fmt="pct1", sentido=0,
         fonte="SIH/SUS (AIH reduzida)", num="outra_regiao", den="internacoes_res", mult=100, agg="externo",
         formula="100 × internações em hospitais de outra região de saúde / internações de residentes",
         nota="Calculado a partir das AIH (tipo 1, ano da alta) na análise de deslocamento; só residentes de MT identificados. Fuga para outros estados não observada.",
         kpi=0, ano_max=2025, descricao="Parcela das internações de moradores realizadas fora da própria região de saúde."),
    dict(id="km_medio_internacao", rotulo="Distância média até a internação", grupo="deslocamento", unidade="km", fmt="dec1", sentido=0,
         fonte="SIH/SUS (AIH reduzida) + IBGE (Localidades 2022)", num="km_medio_internacao", den="internacoes_res", mult=1, agg="externo",
         formula="média ponderada da distância em linha reta entre as sedes municipais (IBGE, Localidades 2022) do município de residência e do município do hospital (0 km no próprio município)",
         nota="Distância geodésica (haversine) entre as sedes municipais, em linha reta: não é distância rodoviária, e o trajeto real é maior. Vazio quando não há internação de residentes no ano (ex.: Boa Esperança do Norte, ainda sem registros no SIH).",
         kpi=0, ano_max=2025, descricao="Distância média, em linha reta, percorrida pelos moradores para se internar."),

    # ---- resultados (SIM/SINASC, até 2024) ----
    dict(id="taxa_mortalidade_infantil", rotulo="Taxa de mortalidade infantil", grupo="resultados", unidade="óbitos por mil nascidos vivos", fmt="dec1", sentido=-1,
         fonte="SIM / SINASC", num="obitos_menor1", den="nascidos_vivos", mult=1000, agg="razao",
         formula="1000 × obitos_menor1 / nascidos_vivos",
         nota=NOTA_PEQUENOS + " Óbitos e nascimentos por residência da mãe; dados até 2024.",
         kpi=1, ano_max=2024, descricao="Óbitos de menores de 1 ano por mil nascidos vivos."),
    dict(id="taxa_mortalidade_geral", rotulo="Taxa de mortalidade geral", grupo="resultados", unidade="óbitos por mil habitantes", fmt="dec1", sentido=-1,
         fonte="SIM", num="obitos_residentes", den="populacao", mult=1000, agg="razao",
         formula="1000 × obitos_residentes / populacao",
         nota="Taxa bruta, sem padronização por idade: municípios com população mais velha tendem a valores maiores. Em 2020–2021 inclui a COVID-19. Dados até 2024.",
         kpi=0, ano_max=2024, descricao="Óbitos de residentes por mil habitantes (taxa bruta)."),
    dict(id="pct_prenatal_7mais", rotulo="Nascidos vivos com 7 ou mais consultas de pré-natal", grupo="resultados", unidade="% dos nascidos vivos", fmt="pct1", sentido=1,
         fonte="SINASC", num="pct_prenatal_7mais", den="nascidos_vivos", mult=1, agg="pond",
         formula="100 × nascidos vivos com 7+ consultas / nascidos vivos com informação",
         nota="Por residência da mãe; dados até 2024. " + NOTA_PEQUENOS, kpi=0, ano_max=2024,
         descricao="Parcela dos nascidos vivos cujas mães fizeram 7 ou mais consultas de pré-natal."),
    dict(id="pct_baixo_peso", rotulo="Nascidos vivos com baixo peso", grupo="resultados", unidade="% dos nascidos vivos", fmt="pct1", sentido=-1,
         fonte="SINASC", num="pct_baixo_peso", den="nascidos_vivos", mult=1, agg="pond",
         formula="100 × nascidos vivos com menos de 2.500 g / nascidos vivos com informação",
         nota="Por residência da mãe; dados até 2024. " + NOTA_PEQUENOS, kpi=0, ano_max=2024,
         descricao="Parcela dos nascidos vivos com peso inferior a 2.500 g."),
    dict(id="pct_cesarea", rotulo="Partos cesáreos", grupo="resultados", unidade="% dos nascidos vivos", fmt="pct1", sentido=0,
         fonte="SINASC", num="pct_cesarea", den="nascidos_vivos", mult=1, agg="pond",
         formula="100 × nascidos vivos por cesariana / nascidos vivos com informação",
         nota="Por residência da mãe; dados até 2024. Referência da OMS: 10% a 15%.", kpi=0, ano_max=2024,
         descricao="Parcela dos nascimentos por cesariana."),
    dict(id="pct_mae_adolescente", rotulo="Nascidos vivos de mães adolescentes", grupo="resultados", unidade="% dos nascidos vivos", fmt="pct1", sentido=-1,
         fonte="SINASC", num="pct_mae_adolescente", den="nascidos_vivos", mult=1, agg="pond",
         formula="100 × nascidos vivos de mães com menos de 20 anos / nascidos vivos com informação",
         nota="Por residência da mãe; dados até 2024. " + NOTA_PEQUENOS, kpi=0, ano_max=2024,
         descricao="Parcela dos nascidos vivos de mães com menos de 20 anos."),
]
KPIS = {"desp_total_pc", "fte_medicos_p1000", "leitos_sus_p1000", "atend_individual_pc",
        "pct_internacoes_fora_mun", "taxa_mortalidade_infantil"}
assert {c["id"] for c in CATALOGO if c["kpi"] == 1} == KPIS, "kpi=1 deve estar exatamente nos 6 indicadores do briefing"
# Ressalva curta, visível nos cartões-chave do perfil (coluna adicional ao contrato: nota_curta)
NOTA_CURTA = {
    "desp_total_pc": "R$ correntes, sem deflação; todas as fontes de recursos.",
    "fte_medicos_p1000": "FTE de 40 h; o crescimento pode refletir melhoria do registro no CNES.",
    "leitos_sus_p1000": "Zero onde não há hospital SUS; média das competências do ano.",
    "atend_individual_pc": "Registro no SISAB cresce com a informatização; caiu em 2020.",
    "pct_internacoes_fora_mun": "Não é 'ruim' em si: a alta complexidade é regionalizada; fuga para outros estados não observada.",
    "taxa_mortalidade_infantil": "Instável em municípios com menos de 100 nascidos vivos por ano; dados até 2024.",
    "leitos_uti_sus": "Sub-registro conhecido no CNES.",
    "mortalidade_hosp_pct": "Sem ajuste de risco.",
}
for c in CATALOGO:
    c["nota_curta"] = NOTA_CURTA.get(c["id"], "")
assert len({c["id"] for c in CATALOGO}) == len(CATALOGO), "ids duplicados no catálogo"

# Colunas do mart cujo valor pré-calculado deve coincidir com a fórmula do catálogo
CHECAR_MART = {
    "desp_total_pc": "desp_total_pc", "desp_ab_pc": "desp_301_pc", "desp_mac_pc": "desp_302_pc",
    "fte_medicos_p1000": "fte_medicos_p1000", "fte_enfermeiros_p1000": "fte_enfermeiros_p1000",
    "fte_acs_p1000": "fte_acs_p1000", "leitos_sus_p1000": "leitos_sus_p1000",
    "atend_individual_pc": "atend_individual_pc", "procedimentos_ab_pc": "procedimentos_ab_pc",
    "visitas_pc": "visitas_pc", "qtd_mc_local_pc": "qtd_mc_local_pc", "qtd_ac_local_pc": "qtd_ac_local_pc",
    "internacoes_local_p1000": "internacoes_local_p1000", "internacoes_res_p1000": "internacoes_res_p1000",
    "taxa_mortalidade_infantil": "taxa_mortalidade_infantil", "taxa_mortalidade_geral": "taxa_mortalidade_geral",
}


# ----------------------------------------------------------------------------
def main() -> int:
    con = conectar()
    msg("Conectado ao banco airflow (somente leitura).")

    # ---- 1. Municípios ------------------------------------------------------
    dim = ler_sql(con, "select cod_mun6, nome_municipio, co_regsaud, nome_regsaud, co_macsaud, nome_macsaud from mart.dim_municipio order by cod_mun6")
    dim["cod_mun6"] = dim["cod_mun6"].astype(int)
    assert len(dim) == 142 and dim["cod_mun6"].is_unique, "dim_municipio deve ter 142 municípios únicos"
    assert "Cuiabá" in set(dim["nome_municipio"]), "acentuação incorreta na leitura do banco"

    geo = json.loads(GEO_IN.read_text(encoding="utf-8"))
    codarea = {int(str(f["properties"]["codarea"])[:6]): int(f["properties"]["codarea"]) for f in geo["features"]}
    assert len(codarea) == 141, "malha mínima deve ter 141 feições"
    # Validação do algoritmo do dígito verificador contra a malha IBGE
    erros_dv = [c7 for c6, c7 in codarea.items() if int(f"{c6}{dv_ibge(c6)}") != c7]
    assert not erros_dv, f"algoritmo do DV falhou em {erros_dv[:5]}"

    def cod7(c6: int) -> int:
        if c6 in codarea:
            return codarea[c6]
        c = int(f"{c6}{dv_ibge(c6)}")  # Boa Esperança do Norte: 5101837 (confirmado pelo DV)
        msg("  cod_ibge7 de %d ausente na malha; calculado pelo dígito verificador: %d", c6, c)
        return c

    mun = pd.DataFrame({
        "cod_mun6": dim["cod_mun6"],
        "cod_ibge7": [cod7(c) for c in dim["cod_mun6"]],
        "municipio": dim["nome_municipio"].str.strip(),
        "slug": [slugify(n) for n in dim["nome_municipio"]],
        "co_regsaud": dim["co_regsaud"].astype(int),
        "regiao_saude": dim["nome_regsaud"].map(limpar_regiao),
        "co_macsaud": dim["co_macsaud"].astype(int),
        "macrorregiao": dim["nome_macsaud"].map(limpar_macro),
    })
    assert mun["slug"].is_unique and mun["cod_ibge7"].is_unique
    assert int(mun.loc[mun.cod_mun6 == COD_BOA_ESPERANCA, "cod_ibge7"].iloc[0]) == 5101837

    # ---- 2. Painel municipal 2020–2025 --------------------------------------
    painel = ler_sql(con, f"select * from mart.painel_dea_mun_ano where ano between {ANOS[0]} and {ANOS[-1]} order by cod_mun6, ano")
    painel["cod_mun6"] = painel["cod_mun6"].astype(int)
    for c in ("co_regsaud", "co_macsaud"):
        painel[c] = painel[c].astype(int)
    assert len(painel) == 142 * len(ANOS), f"painel deve ter {142 * len(ANOS)} linhas"
    assert not painel.duplicated(["cod_mun6", "ano"]).any()
    num_cols = [c for c in painel.columns if c not in ("cod_mun6", "nome_municipio", "co_regsaud", "nome_regsaud", "co_macsaud", "nome_macsaud", "ano", "fonte_populacao", "ano_parcial", "dmu_completa")]
    painel[num_cols] = painel[num_cols].apply(pd.to_numeric, errors="coerce").astype(float)

    # Município sem população (Boa Esperança do Norte antes de 2025): não existia → tudo indisponível
    sem_pop = painel["populacao"].isna()
    msg("  município-anos sem população (valores anulados): %d", int(sem_pop.sum()))
    painel.loc[sem_pop, [c for c in num_cols if c != "populacao"]] = np.nan
    # Lançamentos negativos de recursos próprios no SIOPS (artefato): anulados também para os agregados
    rp_neg = painel["desp_recursos_proprios"] < 0
    if rp_neg.any():
        msg("  desp_recursos_proprios negativo em %d município-ano(s): anulado", int(rp_neg.sum()))
        painel.loc[rp_neg, "desp_recursos_proprios"] = np.nan

    p25 = painel[painel.ano == ANO_MAX].set_index("cod_mun6")
    mun["populacao_2025"] = mun["cod_mun6"].map(p25["populacao"]).round().astype("Int64")
    mun["tem_hospital_sus_2025"] = (mun["cod_mun6"].map(p25["n_hospitais_sus"]).fillna(0) > 0).astype(int)
    assert mun["populacao_2025"].notna().all()
    gravar(mun, DADOS / "municipios.csv")
    msg("  municípios com hospital SUS em 2025: %d", int(mun.tem_hospital_sus_2025.sum()))

    # ---- 3. Deslocamento (opcional) ----------------------------------------
    desloc = None
    if ARQ_DESLOC.exists():
        desloc = pd.read_csv(ARQ_DESLOC, encoding="utf-8")
        desloc["cod_mun6"] = desloc["cod_mun6"].astype(int)
        faltam = {"cod_mun6", "ano", "internacoes_res", "outra_regiao", "pct_internacoes_fora_regiao", "km_medio_internacao"} - set(desloc.columns)
        if faltam:
            msg("AVISO: deslocamento_mun_ano.csv sem colunas %s; indicadores de deslocamento regional não incorporados", sorted(faltam))
            desloc = None
        else:
            desloc = desloc[desloc.ano.between(ANOS[0], ANOS[-1])].copy()
            msg("  deslocamento_mun_ano.csv encontrado: %d linhas; incorporando pct_internacoes_fora_regiao e km_medio_internacao", len(desloc))
    else:
        msg("  deslocamento_mun_ano.csv ausente: pct_internacoes_fora_regiao e km_medio_internacao ficam vazios (reexecutar após o agente de deslocamento)")

    # ---- 4. Valores municipais ---------------------------------------------
    base = painel[["cod_mun6", "co_regsaud", "ano"]].copy()
    if desloc is not None:
        base = base.merge(desloc[["cod_mun6", "ano", "internacoes_res", "outra_regiao", "pct_internacoes_fora_regiao", "km_medio_internacao"]]
                          .rename(columns={"internacoes_res": "desloc_internacoes_res"}), on=["cod_mun6", "ano"], how="left")

    def razao(num: pd.Series, den: pd.Series, mult: float) -> pd.Series:
        den = den.where(den > 0)
        return mult * num / den

    valores = {}
    for c in CATALOGO:
        i, agg = c["id"], c["agg"]
        if agg == "soma":
            v = painel[c["num"]]
        elif agg == "razao":
            v = razao(painel[c["num"]], painel[c["den"]], c["mult"])
        elif agg == "pond":
            v = painel[c["num"]]  # percentual já calculado no mart (numeradores não publicados)
        elif agg == "externo":
            v = base[i] if desloc is not None else pd.Series(np.nan, index=painel.index)
        else:
            raise ValueError(agg)
        v = v.where(painel["ano"] <= c["ano_max"])
        if c["fmt"] == "pct1":  # percentuais fora de 0–100 são artefatos de lançamento (ex.: recursos próprios negativos no SIOPS)
            fora = v.notna() & ~v.between(0, 100)
            if fora.any():
                msg("  %s: %d valor(es) fora de 0–100%% anulado(s)", i, int(fora.sum()))
                v = v.where(~fora)
        valores[i] = v.astype(float).round(4)
    val = pd.concat([painel[["cod_mun6", "ano"]], pd.DataFrame(valores)], axis=1)

    # Coerência com os per capita pré-calculados do mart
    for i, col in CHECAR_MART.items():
        a, b = val[i], painel[col].where(painel["ano"] <= dict((c["id"], c["ano_max"]) for c in CATALOGO)[i])
        ok = a.notna() & b.notna()
        assert (a.isna() == b.isna()).all(), f"{i}: padrão de vazios difere do mart ({col})"
        dif_abs = (a[ok] - b[ok]).abs()
        dif_rel = dif_abs / b[ok].abs().clip(lower=1e-9)
        # o mart arredonda a 2–4 casas: aceita diferença absoluta de arredondamento ou relativa < 0,5%
        ruim = (dif_abs > 0.0101) & (dif_rel > 5e-3)
        assert not ruim.any(), f"{i} diverge do mart ({col}): máx rel {dif_rel[ruim].max():.4f}"
    msg("  per capita coerentes com o mart em %d indicadores", len(CHECAR_MART))

    # ---- 5. serie.csv (longo, 2020–ano_max de cada indicador) --------------
    ano_max = {c["id"]: c["ano_max"] for c in CATALOGO}
    fmt = {c["id"]: c["fmt"] for c in CATALOGO}
    serie = val.melt(id_vars=["cod_mun6", "ano"], var_name="indicador", value_name="valor")
    serie = serie[serie["ano"] <= serie["indicador"].map(ano_max)]
    serie = serie[["cod_mun6", "indicador", "ano", "valor"]].sort_values(["indicador", "cod_mun6", "ano"]).reset_index(drop=True)
    assert not serie.duplicated(["cod_mun6", "indicador", "ano"]).any()
    assert serie["cod_mun6"].nunique() == 142 and sorted(serie["ano"].unique()) == ANOS
    serie_out = serie.copy()
    serie_out["valor"] = [fmt_valor(v, fmt[i]) for v, i in zip(serie["valor"], serie["indicador"])]
    gravar(serie_out, DADOS / "serie.csv")
    msg("  indicadores na série: %d; valores preenchidos: %d de %d", serie.indicador.nunique(), int(serie.valor.notna().sum()), len(serie))

    # ---- 6. indicadores.csv ---------------------------------------------------
    ind = pd.DataFrame(CATALOGO)
    ind["ordem"] = range(1, len(ind) + 1)
    ind["nota_curta"] = ind["nota_curta"].fillna("")
    ind = ind[["id", "rotulo", "grupo", "unidade", "fmt", "sentido", "fonte", "formula", "nota", "kpi", "ano_max", "descricao", "ordem", "nota_curta"]]
    gravar(ind, DADOS / "indicadores.csv")

    # ---- 7. regioes.csv ------------------------------------------------------
    reg = (mun.groupby(["co_regsaud", "regiao_saude", "co_macsaud", "macrorregiao"], as_index=False)
              .agg(n_municipios=("cod_mun6", "size"), populacao_2025=("populacao_2025", "sum"))
              .sort_values("co_regsaud").reset_index(drop=True))
    reg["populacao_2025"] = reg["populacao_2025"].astype(int)
    assert len(reg) == 16 and reg.n_municipios.sum() == 142
    assert reg.populacao_2025.sum() == int(mun.populacao_2025.sum())
    gravar(reg, DADOS / "regioes.csv")

    # ---- 8. serie_regiao.csv e serie_mt.csv (recalculados com totais) -------
    def agregar(df: pd.DataFrame, chaves: list[str]) -> pd.DataFrame:
        partes = []
        for c in CATALOGO:
            i, agg = c["id"], c["agg"]
            d = df[df["ano"] <= c["ano_max"]]
            if agg == "soma":
                g = d.groupby(chaves)[c["num"]].sum(min_count=1).rename("valor").reset_index()
            elif agg == "razao":
                m = d[[*chaves, c["num"], c["den"]]].dropna()
                g = m.groupby(chaves).sum(min_count=1).reset_index()
                g["valor"] = razao(g[c["num"]], g[c["den"]], c["mult"])
                g = g[[*chaves, "valor"]]
            elif agg == "pond":  # média ponderada por nascidos vivos
                m = d[[*chaves, c["num"], c["den"]]].dropna()
                m["_p"] = m[c["num"]] * m[c["den"]]
                g = m.groupby(chaves)[["_p", c["den"]]].sum(min_count=1).reset_index()
                g["valor"] = g["_p"] / g[c["den"]].where(g[c["den"]] > 0)
                g = g[[*chaves, "valor"]]
            elif agg == "externo":
                if desloc is None:
                    continue
                m = d[[*chaves, c["num"], "desloc_internacoes_res"]].dropna()
                if i == "pct_internacoes_fora_regiao":
                    g = m.groupby(chaves)[[c["num"], "desloc_internacoes_res"]].sum(min_count=1).reset_index()
                    g["valor"] = razao(g[c["num"]], g["desloc_internacoes_res"], c["mult"])
                else:  # km médio ponderado pelas internações de residentes
                    m["_p"] = m[c["num"]] * m["desloc_internacoes_res"]
                    g = m.groupby(chaves)[["_p", "desloc_internacoes_res"]].sum(min_count=1).reset_index()
                    g["valor"] = g["_p"] / g["desloc_internacoes_res"].where(g["desloc_internacoes_res"] > 0)
                g = g[[*chaves, "valor"]]
            g["indicador"] = i
            partes.append(g)
        out = pd.concat(partes, ignore_index=True)
        out["valor"] = out["valor"].astype(float).round(4)
        return out

    full = painel.merge(base.drop(columns=["co_regsaud"]), on=["cod_mun6", "ano"], how="left") if desloc is not None else painel.copy()
    full["mt"] = 1
    sreg = agregar(full, ["co_regsaud", "ano"])[["co_regsaud", "indicador", "ano", "valor"]].sort_values(["indicador", "co_regsaud", "ano"])
    assert not sreg.duplicated(["co_regsaud", "indicador", "ano"]).any() and sreg.co_regsaud.nunique() == 16
    smt = agregar(full, ["mt", "ano"]).drop(columns="mt")
    med = serie.groupby(["indicador", "ano"])["valor"].median().rename("mediana").reset_index()
    smt = smt.merge(med, on=["indicador", "ano"], how="left")[["indicador", "ano", "valor", "mediana"]].sort_values(["indicador", "ano"])
    smt["mediana"] = smt["mediana"].round(4)
    assert not smt.duplicated(["indicador", "ano"]).any()

    # Sanidade: população MT e despesa/hab
    pop_mt = smt[(smt.indicador == "populacao") & (smt.ano == ANO_MAX)]["valor"].iloc[0]
    assert abs(pop_mt - mun.populacao_2025.sum()) < 1, "população MT não bate"
    sreg_out, smt_out = sreg.copy(), smt.copy()
    sreg_out["valor"] = [fmt_valor(v, fmt[i]) for v, i in zip(sreg.valor, sreg.indicador)]
    smt_out["valor"] = [fmt_valor(v, fmt[i]) for v, i in zip(smt.valor, smt.indicador)]
    smt_out["mediana"] = [fmt_valor(v, fmt[i]) for v, i in zip(smt.mediana, smt.indicador)]
    gravar(sreg_out, DADOS / "serie_regiao.csv")
    gravar(smt_out, DADOS / "serie_mt.csv")
    r = smt[(smt.indicador == "desp_total_pc") & (smt.ano == ANO_MAX)].iloc[0]
    msg("  MT %d: população %.0f; despesa/hab R$ %.2f (mediana municipal R$ %.2f)", ANO_MAX, pop_mt, r.valor, r.mediana)

    # ---- 9. Hospitais --------------------------------------------------------
    hosp_all = ler_sql(con, f"select * from mart.painel_dea_hosp_ano where ano between {ANOS[0]} and {ANOS[-1]} order by ano, cod_mun6, cnes")
    hosp_all["cod_mun6"] = hosp_all["cod_mun6"].astype(int)
    hosp_all["co_regsaud"] = hosp_all["co_regsaud"].astype(int)
    hosp_all["municipio"] = hosp_all["cod_mun6"].map(mun.set_index("cod_mun6")["municipio"])
    hosp_all["regiao_saude"] = hosp_all["nome_regsaud"].map(limpar_regiao)
    assert hosp_all["municipio"].notna().all(), "hospital com município fora dos 142"
    assert not hosp_all.duplicated(["cnes", "ano"]).any()
    # n_meses (competências do CNES em que o estabelecimento constou no ano) é adicional ao contrato:
    # permite ponderar leitos e contagem de hospitais pelo tempo de registro, como no painel municipal.
    cols_hosp = ["cnes", "cod_mun6", "municipio", "regiao_saude", "ano", "nome_fantasia", "natureza_juridica", "esfera",
                 "leitos_sus", "leitos_uti_sus", "fte_medicos_sus", "internacoes", "internacoes_ac", "diarias_uti",
                 "valor_total", "taxa_mortalidade_hosp", "permanencia_media", "taxa_ocupacao_leitos_sus", "n_meses"]
    hosp = hosp_all[cols_hosp].copy()
    for c in ("leitos_sus", "leitos_uti_sus", "fte_medicos_sus", "valor_total", "taxa_mortalidade_hosp", "permanencia_media", "taxa_ocupacao_leitos_sus"):
        hosp[c] = pd.to_numeric(hosp[c], errors="coerce").round(2)
    for c in ("internacoes", "internacoes_ac", "diarias_uti", "natureza_juridica", "n_meses"):
        hosp[c] = pd.to_numeric(hosp[c], errors="coerce").astype("Int64")
    gravar(hosp, DADOS / "hospitais.csv")
    msg("  hospitais 2025: %d (com internação no SIH: %d)", int((hosp.ano == ANO_MAX).sum()), int(((hosp.ano == ANO_MAX) & hosp.internacoes.notna()).sum()))

    # ---- 10. Malha e coordenadas (centroides.csv = sedes municipais) ---------
    info = mun.set_index("cod_mun6")
    feats = []
    for f in geo["features"]:
        c6 = int(str(f["properties"]["codarea"])[:6])
        m = info.loc[c6]
        feats.append({"type": "Feature",
                      "properties": {"cod_mun6": c6, "municipio": m["municipio"], "co_regsaud": int(m["co_regsaud"]),
                                     "regiao_saude": m["regiao_saude"], "codarea": f["properties"]["codarea"]},
                      "geometry": f["geometry"]})
    geo_out = {"type": "FeatureCollection", "features": feats}
    (DADOS / "geo_mt.geojson").write_text(json.dumps(geo_out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    msg("  gravado dados_site/geo_mt.geojson (%d feições)", len(feats))

    # centroides.csv (contrato cod_mun6, lon, lat): coordenadas das SEDES municipais (IBGE, Localidades 2022),
    # geradas por scripts/00_sedes_ibge.py; inclui Boa Esperança do Norte, que não tem polígono na malha.
    if ARQ_SEDES.exists():
        sedes = pd.read_csv(ARQ_SEDES, encoding="utf-8", dtype={"cod_mun6": int, "lon": float, "lat": float})
        cent = sedes[["cod_mun6", "lon", "lat"]].copy()
        assert len(cent) == len(mun) and set(cent.cod_mun6) == set(mun.cod_mun6), "sedes_municipais.csv não cobre os 142 municípios"
        assert COD_BOA_ESPERANCA in set(cent.cod_mun6), "Boa Esperança do Norte sem sede"
        msg("  centroides.csv com as sedes municipais de %s (%d linhas)", ARQ_SEDES.relative_to(RAIZ).as_posix(), len(cent))
    else:  # fallback: centro geométrico do polígono (aproximação pior da sede em municípios extensos)
        msg("  AVISO: %s ausente (rode scripts/00_sedes_ibge.py); centroides.csv com o centro geométrico dos polígonos da malha",
            ARQ_SEDES.relative_to(RAIZ).as_posix())
        try:
            from shapely.geometry import shape
            cent = [(f["properties"]["cod_mun6"], shape(f["geometry"]).centroid) for f in feats]
            cent = pd.DataFrame({"cod_mun6": [c for c, _ in cent], "lon": [round(p.x, 5) for _, p in cent], "lat": [round(p.y, 5) for _, p in cent]})
        except ImportError:  # média dos vértices do anel externo
            def _cent(geom):
                anel = geom["coordinates"][0] if geom["type"] == "Polygon" else max(geom["coordinates"], key=lambda p: len(p[0]))[0]
                xs, ys = zip(*anel)
                return round(sum(xs) / len(xs), 5), round(sum(ys) / len(ys), 5)
            cent = pd.DataFrame([(f["properties"]["cod_mun6"], *_cent(f["geometry"])) for f in feats], columns=["cod_mun6", "lon", "lat"])
    cent = cent.sort_values("cod_mun6").reset_index(drop=True)
    assert not cent.cod_mun6.duplicated().any(), "cod_mun6 duplicado em centroides.csv"
    assert cent.lon.between(-62, -50).all() and cent.lat.between(-18.5, -7).all(), "coordenadas fora de MT"
    gravar(cent, DADOS / "centroides.csv")

    # ---- 11. Downloads em arquivos/dados ------------------------------------
    largo = painel.drop(columns=["nome_regsaud", "nome_macsaud"]).rename(columns={"nome_municipio": "municipio"})
    largo.insert(3, "regiao_saude", largo["cod_mun6"].map(info["regiao_saude"]))
    largo.insert(5, "macrorregiao", largo["cod_mun6"].map(info["macrorregiao"]))
    largo = largo.merge(val[["cod_mun6", "ano"] + [i for i in val.columns if i not in largo.columns and i not in ("cod_mun6", "ano")]], on=["cod_mun6", "ano"], how="left")
    largo = largo.sort_values(["cod_mun6", "ano"]).round(4)
    gravar(largo, DOWN / "painel_municipal_2020_2025.csv")

    longa = serie_out.merge(mun[["cod_mun6", "municipio", "regiao_saude"]], on="cod_mun6").merge(ind[["id", "grupo", "rotulo", "unidade"]], left_on="indicador", right_on="id")
    longa = longa[["cod_mun6", "municipio", "regiao_saude", "grupo", "indicador", "rotulo", "unidade", "ano", "valor"]].sort_values(["cod_mun6", "grupo", "indicador", "ano"])
    gravar(longa, DOWN / "serie_longa.csv")
    gravar(ind, DOWN / "indicadores_dicionario.csv")
    gravar(hosp_all.drop(columns=["nome_municipio", "nome_regsaud"]).round(4), DOWN / "hospitais_sus_mt.csv")
    reg_down = reg.merge(mun.groupby("co_regsaud")["municipio"].agg(lambda s: "; ".join(sorted(s))).rename("municipios").reset_index(), on="co_regsaud")
    gravar(reg_down, DOWN / "regioes_saude_mt.csv")

    # ---- 12. README ----------------------------------------------------------
    escrever_readme(len(CATALOGO), desloc is not None, ARQ_SEDES.exists())
    con.close()
    msg("Concluído.")
    return 0


def escrever_readme(n_ind: int, com_desloc: bool, com_sedes: bool) -> None:
    status = ("incorporados de `deslocamento_mun_ano.csv`" if com_desloc else
              "**vazios** nesta execução (`deslocamento_mun_ano.csv` ainda não existia); reexecute `python scripts/01_preparar_dados.py` após o agente de deslocamento gerar o arquivo")
    origem_coord = ("sede municipal (IBGE, Localidades do Brasil 2022), copiada de `sedes_municipais.csv`" if com_sedes else
                    "**centro geométrico do polígono da malha** (fallback: `sedes_municipais.csv` não existia; rode `python scripts/00_sedes_ibge.py` e repita o 01)")
    txt = f"""# dados_site/ — dicionário curto

Arquivos gerados por `scripts/01_preparar_dados.py` a partir dos marts `mart.painel_dea_mun_ano`, `mart.painel_dea_hosp_ano`,
`mart.dim_municipio` (PostgreSQL local, somente leitura), da malha `arquivos/geo/mt_municipios_ibge_minima.geojson` e das sedes
municipais `sedes_municipais.csv` (gerado antes por `scripts/00_sedes_ibge.py` a partir do shapefile IBGE Localidades 2022 em `arquivos/geo/ibge_localidades_2022_mt/`).
CSV em UTF-8, separador vírgula, decimal ponto, vazio = indisponível. Janela: 2020–2025 (resultados SIM/SINASC até 2024).

| arquivo | conteúdo | chave |
|---|---|---|
| `municipios.csv` | 142 municípios: `cod_mun6`, `cod_ibge7`, `municipio`, `slug`, `co_regsaud`, `regiao_saude`, `co_macsaud`, `macrorregiao`, `populacao_2025`, `tem_hospital_sus_2025` | `cod_mun6` |
| `indicadores.csv` | catálogo de {n_ind} indicadores: `id`, `rotulo`, `grupo`, `unidade`, `fmt`, `sentido`, `fonte`, `formula`, `nota`, `kpi`, `ano_max` (+ `descricao`, `ordem`, `nota_curta` = ressalva curta dos cartões) | `id` |
| `serie.csv` | formato longo municipal: `cod_mun6`, `indicador`, `ano`, `valor` (grade completa 142 × indicadores × 2020–`ano_max`) | `cod_mun6`+`indicador`+`ano` |
| `regioes.csv` | 16 regiões de saúde (CIR): códigos, nomes, macrorregião, `n_municipios`, `populacao_2025` | `co_regsaud` |
| `serie_regiao.csv` | agregados por região: `co_regsaud`, `indicador`, `ano`, `valor` | `co_regsaud`+`indicador`+`ano` |
| `serie_mt.csv` | agregado estadual: `indicador`, `ano`, `valor` (MT) e `mediana` (mediana dos municípios) | `indicador`+`ano` |
| `hospitais.csv` | hospitais SUS 2020–2025 (uma linha por CNES-ano): capacidade e produção; `n_meses` = competências do CNES em que o estabelecimento constou no ano (adicional ao contrato); `taxa_ocupacao_leitos_sus` em fração 0–1 | `cnes`+`ano` |
| `geo_mt.geojson` | malha mínima IBGE (141 polígonos) com `cod_mun6`, `municipio`, `co_regsaud`, `regiao_saude`, `codarea` | `cod_mun6` |
| `sedes_municipais.csv` | 142 sedes municipais: `cod_mun6`, `cod_ibge7`, `municipio` (nome IBGE), `lon`, `lat` (WGS84, 4 decimais), `fonte` — script 00 | `cod_mun6` |
| `centroides.csv` | `cod_mun6`, `lon`, `lat` — coordenada usada nas distâncias em linha reta: {origem_coord} | `cod_mun6` |

## Regras de cálculo

- Valores municipais recalculados a partir das colunas brutas do mart (numerador/denominador do catálogo) e conferidos com os per capita
  pré-calculados do mart (diferença relativa < 0,5%). Razões com denominador zero ficam vazias (ex.: mortalidade hospitalar onde não há internação local).
- **Região e MT**: contagens são somadas; razões e percentuais são recalculados com os totais (soma dos numeradores / soma dos denominadores),
  não pela média dos municípios. Os percentuais do SINASC (`pct_prenatal_7mais`, `pct_baixo_peso`, `pct_cesarea`, `pct_mae_adolescente`)
  são ponderados por nascidos vivos, porque o mart não publica seus numeradores. `mediana` em `serie_mt.csv` é a mediana simples dos municípios com valor.
- `ano_max` = 2025 para todos os indicadores, exceto os de resultados (SIM/SINASC) e `doses_menor1_por_nv`, com 2024. `serie.csv` só traz anos até `ano_max`.
- **Boa Esperança do Norte (510183)** foi instalada em 2025: sem população e com valores vazios em 2020–2024; ausente na malha IBGE
  (sem polígono nos mapas), mas com a coordenada da sede (IBGE, Localidades 2022) em `centroides.csv`. `cod_ibge7` = 5101837, obtido pelo
  dígito verificador do IBGE (algoritmo validado nas 141 feições da malha) e confirmado nas Localidades 2022.
- `regiao_saude` = nome da CIR sem o sufixo " - MT"; `macrorregiao` em caixa normal (ex.: "Centro-Norte").
- Em `hospitais.csv`, `natureza_juridica` é o código CONCLA (ex.: 1244 = município; 3999 = associação privada); `esfera` traz a categoria legível.
  Hospitais sem produção no SIH no ano ficam com `internacoes` vazio (só CNES). Leitos e FTE são médias dos `n_meses` em que o CNES
  constou no ano: para reproduzir a média municipal do painel, pondere por `n_meses`/12. `taxa_ocupacao_leitos_sus` é fração 0–1 (o site exibe em %).
- Indicadores `pct_internacoes_fora_regiao` e `km_medio_internacao` (grupo deslocamento): {status}.
  Nos agregados regionais/estaduais, o percentual usa soma de `outra_regiao` / soma de `internacoes_res` e o km médio é ponderado por `internacoes_res`
  (colunas do arquivo de deslocamento). As distâncias são em linha reta entre as sedes municipais (IBGE), não rodoviárias; `km_medio_internacao`
  fica vazio quando o município não tem internação de residentes no ano (ex.: Boa Esperança do Norte).

## Downloads (`arquivos/dados/`)

`painel_municipal_2020_2025.csv` (largo: todas as variáveis do mart + indicadores derivados, uma linha por município-ano),
`serie_longa.csv` (serie.csv com nomes, grupo e rótulos), `indicadores_dicionario.csv` (= indicadores.csv),
`hospitais_sus_mt.csv` (todas as colunas de `painel_dea_hosp_ano`, 2020–2025), `regioes_saude_mt.csv` (regioes.csv + lista de municípios).

Fontes: SIOPS (despesa liquidada, RREO), CNES (vínculos SUS em FTE 40 h, leitos, equipamentos, equipes; média anual), SISAB, SI-PNI (sem COVID),
SIA/SUS (procedimentos aprovados), SIH/SUS (AIH tipo 1, ano da alta), SIM e SINASC (por residência), IBGE (população). Só há SIH/SIA de MT:
atendimentos de residentes em outros estados não são observados.
"""
    (DADOS / "README_dados.md").write_text(txt, encoding="utf-8")
    msg("  gravado dados_site/README_dados.md")


if __name__ == "__main__":
    sys.exit(main())
