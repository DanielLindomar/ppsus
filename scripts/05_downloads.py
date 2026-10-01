# -*- coding: utf-8 -*-
"""
05_downloads.py — Observatório PPSUS-MT
Complementa os downloads de arquivos/ a partir de dados_site/ (sem acesso ao banco):

  arquivos/dados/municipios_mt.csv                       142 municípios: códigos, região, macrorregião, população 2025
  arquivos/dados/serie_regioes_saude_2020_2025.csv       agregados por região de saúde (formato longo, com rótulos)
  arquivos/dados/serie_mt_2020_2025.csv                  agregado estadual + mediana municipal (formato longo, com rótulos)
  arquivos/dados/deslocamento_municipios_2020_2025.csv   deslocamento por município de residência/atendimento e ano
  arquivos/dados/polos_internacao_2020_2025.csv          municípios de atendimento (polos) por ano
  arquivos/dados/resumo_deslocamento_mt_2020_2025.csv    resumo estadual do deslocamento por ano e nível
  arquivos/dados/sedes_municipais.csv                    sede municipal (lon, lat; IBGE Localidades 2022) de cada município
  arquivos/dados/painel_municipal_dicionario.csv         dicionário das colunas de painel_municipal_2020_2025.csv
  arquivos/dados/catalogo_arquivos.csv                   catálogo de todos os downloads (descrição, chave, período, tamanho)
  arquivos/geo/mt_municipios_regioes_saude.geojson       malha mínima com cod_mun6, município e região de saúde

Os arquivos do contrato gerados pelos scripts 01 e 02 (painel_municipal_2020_2025.csv,
serie_longa.csv, indicadores_dicionario.csv, fluxos_internacoes_*.csv, hospitais_sus_mt.csv,
regioes_saude_mt.csv e as malhas IBGE) não são alterados: o script apenas confere que existem
e os inclui no catálogo. A página dados/index.qmd lê catalogo_arquivos.csv.

Uso (a partir da raiz do repositório, depois dos scripts 01 e 02):  python scripts/05_downloads.py
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parents[1]
DS = RAIZ / "dados_site"
DOWN = RAIZ / "arquivos" / "dados"
GEO = RAIZ / "arquivos" / "geo"
CSV_KW = dict(index=False, encoding="utf-8", lineterminator="\n", na_rep="")
PERIODO = "2020–2025"


def msg(fmt: str, *a) -> None:
    print(fmt % a if a else fmt, flush=True)


def ler(nome: str) -> pd.DataFrame:
    """Lê dados_site/<nome> preservando os tipos do arquivo: colunas só com inteiros viram
    Int64 (com vazio = <NA>), evitando que um código como 510340 vire 510340.0 na cópia."""
    f = DS / nome
    if not f.exists():
        sys.exit(f"ERRO: dados_site/{nome} não existe; rode antes os scripts 01 e 02.")
    d = pd.read_csv(f, encoding="utf-8", dtype=str, keep_default_na=False)
    for c in d.columns:
        v = d[c][d[c] != ""]
        if len(v) and v.str.fullmatch(r"-?\d+").all():
            d[c] = pd.to_numeric(d[c].replace("", pd.NA), errors="coerce").astype("Int64")
        elif len(v) and v.str.fullmatch(r"-?\d+(\.\d+)?([eE][-+]?\d+)?").all():
            d[c] = pd.to_numeric(d[c].replace("", pd.NA), errors="coerce").astype(float)
        else:
            d[c] = d[c].replace("", pd.NA)
    return d


def gravar(df: pd.DataFrame, caminho: Path) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(caminho, **CSV_KW)
    msg("  gravado %s (%d linhas, %d colunas)", caminho.relative_to(RAIZ).as_posix(), len(df), df.shape[1])


# ----------------------------------------------------------------------------
# Dicionário das colunas brutas do painel municipal (colunas do mart). As colunas que
# coincidem com um indicador do site recebem a descrição de indicadores.csv.
# (descrição, unidade, fonte, bloco)
BRUTAS = {
    "cod_mun6": ("Código IBGE do município com 6 dígitos (chave)", "código", "IBGE", "identificação"),
    "municipio": ("Nome do município", "texto", "IBGE", "identificação"),
    "co_regsaud": ("Código da região de saúde (CIR)", "código", "SES-MT (PDR)", "identificação"),
    "regiao_saude": ("Nome da região de saúde", "texto", "SES-MT (PDR)", "identificação"),
    "co_macsaud": ("Código da macrorregião de saúde", "código", "SES-MT (PDR)", "identificação"),
    "macrorregiao": ("Nome da macrorregião de saúde", "texto", "SES-MT (PDR)", "identificação"),
    "ano": ("Ano de referência", "ano", "—", "identificação"),
    "fonte_populacao": ("Origem da estimativa populacional (Censo 2022, estimativa ou interpolação)", "texto", "IBGE", "cobertura"),
    "n_bimestres_disponiveis": ("Bimestres com declaração no SIOPS no ano (6 = ano completo)", "bimestres", "SIOPS", "cobertura"),
    "n_meses_cnes": ("Competências mensais do CNES disponíveis no ano (12 = completo)", "meses", "CNES", "cobertura"),
    "n_meses_sisab": ("Competências mensais do SISAB disponíveis no ano (12 = completo)", "meses", "SISAB", "cobertura"),
    "ano_parcial": ("Ano com cobertura incompleta de alguma fonte (True/False)", "lógico", "—", "cobertura"),
    "dmu_completa": ("Município-ano com todas as variáveis necessárias ao modelo DEA (True/False)", "lógico", "—", "cobertura"),
    "desp_total_saude": ("Despesa liquidada na função Saúde, todas as fontes de recursos, acumulada no ano", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_301_atencao_basica": ("Despesa liquidada na subfunção 301 (Atenção Básica)", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_302_mac": ("Despesa liquidada na subfunção 302 (Assistência Hospitalar e Ambulatorial)", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_outras": ("Despesa liquidada nas demais subfunções da Saúde (vigilância, suporte profilático, alimentação, outras)", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_corrente": ("Despesa corrente liquidada em saúde", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_capital": ("Despesa de capital (investimentos) liquidada em saúde", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "desp_recursos_proprios": ("Despesa em saúde financiada com receitas próprias do município (impostos e transferências constitucionais)", "R$ correntes", "SIOPS (RREO)", "financiamento"),
    "fte_medicos_sus": ("Médicos com atendimento SUS, em equivalentes de 40 h semanais (média das competências do ano)", "FTE", "CNES", "capacidade"),
    "fte_enfermeiros_sus": ("Enfermeiros com atendimento SUS, em equivalentes de 40 h semanais (média anual)", "FTE", "CNES", "capacidade"),
    "fte_tec_enfermagem_sus": ("Técnicos e auxiliares de enfermagem com atendimento SUS (FTE 40 h, média anual)", "FTE", "CNES", "capacidade"),
    "fte_dentistas_sus": ("Cirurgiões-dentistas com atendimento SUS (FTE 40 h, média anual)", "FTE", "CNES", "capacidade"),
    "fte_acs": ("Agentes comunitários de saúde (FTE 40 h, média anual)", "FTE", "CNES", "capacidade"),
    "fte_total_sus": ("Total de profissionais com atendimento SUS (FTE 40 h, média anual)", "FTE", "CNES", "capacidade"),
    "leitos_sus": ("Leitos de internação disponíveis ao SUS (média das competências do ano)", "leitos", "CNES", "capacidade"),
    "leitos_uti_sus": ("Leitos de UTI disponíveis ao SUS (média anual; sub-registro conhecido)", "leitos", "CNES", "capacidade"),
    "equip_sus_uso": ("Equipamentos declarados em uso e disponíveis ao SUS (média anual)", "equipamentos", "CNES", "capacidade"),
    "n_estab_sus": ("Estabelecimentos de saúde com atendimento SUS (média anual)", "estabelecimentos", "CNES", "capacidade"),
    "n_ubs": ("Centros de saúde / unidades básicas com atendimento SUS (média anual)", "unidades", "CNES", "capacidade"),
    "n_hospitais_sus": ("Hospitais (gerais, especializados e de dia) com atendimento SUS (média anual)", "hospitais", "CNES", "capacidade"),
    "n_upa": ("Unidades de pronto atendimento com atendimento SUS (média anual)", "unidades", "CNES", "capacidade"),
    "n_equipes_esf": ("Equipes de Saúde da Família (média anual)", "equipes", "CNES", "capacidade"),
    "n_equipes_eap": ("Equipes de Atenção Primária, modalidade eAP (média anual)", "equipes", "CNES", "capacidade"),
    "n_equipes_esb": ("Equipes de Saúde Bucal (média anual)", "equipes", "CNES", "capacidade"),
    "sisab_atend_individual": ("Atendimentos individuais registrados pelas equipes de atenção básica no ano", "atendimentos", "SISAB", "atenção básica"),
    "sisab_atend_odonto": ("Atendimentos odontológicos individuais registrados no ano", "atendimentos", "SISAB", "atenção básica"),
    "sisab_procedimentos": ("Procedimentos registrados pelas equipes de atenção básica no ano", "procedimentos", "SISAB", "atenção básica"),
    "sisab_visitas_domiciliares": ("Visitas domiciliares registradas no ano", "visitas", "SISAB", "atenção básica"),
    "sisab_atend_medico": ("Atendimentos individuais realizados por médicos", "atendimentos", "SISAB", "atenção básica"),
    "sisab_atend_enfermeiro": ("Atendimentos individuais realizados por enfermeiros", "atendimentos", "SISAB", "atenção básica"),
    "sipni_doses_local": ("Doses de vacina de rotina aplicadas em estabelecimentos do município, sem COVID-19", "doses", "SI-PNI", "vacinação"),
    "sipni_doses_menor1_local": ("Doses aplicadas em menores de 1 ano em estabelecimentos do município, sem COVID-19", "doses", "SI-PNI", "vacinação"),
    "sipni_doses_res": ("Doses aplicadas em residentes do município, em qualquer local, sem COVID-19", "doses", "SI-PNI", "vacinação"),
    "sia_qtd_ab_local": ("Procedimentos ambulatoriais de atenção básica aprovados em estabelecimentos do município", "procedimentos", "SIA/SUS", "ambulatorial"),
    "qtd_mc_local": ("Procedimentos ambulatoriais de média complexidade aprovados em estabelecimentos do município", "procedimentos", "SIA/SUS", "ambulatorial"),
    "valor_mc_local": ("Valor aprovado dos procedimentos de média complexidade realizados no município", "R$ correntes", "SIA/SUS", "ambulatorial"),
    "qtd_mc_res": ("Procedimentos ambulatoriais de média complexidade realizados em residentes do município (qualquer local de MT)", "procedimentos", "SIA/SUS", "ambulatorial"),
    "valor_mc_res": ("Valor aprovado dos procedimentos de média complexidade de residentes do município", "R$ correntes", "SIA/SUS", "ambulatorial"),
    "qtd_ac_local": ("Procedimentos ambulatoriais de alta complexidade aprovados em estabelecimentos do município", "procedimentos", "SIA/SUS", "ambulatorial"),
    "valor_ac_local": ("Valor aprovado dos procedimentos de alta complexidade realizados no município", "R$ correntes", "SIA/SUS", "ambulatorial"),
    "qtd_ac_res": ("Procedimentos ambulatoriais de alta complexidade realizados em residentes do município (qualquer local de MT)", "procedimentos", "SIA/SUS", "ambulatorial"),
    "valor_ac_res": ("Valor aprovado dos procedimentos de alta complexidade de residentes do município", "R$ correntes", "SIA/SUS", "ambulatorial"),
    "sia_qtd_total_local": ("Total de procedimentos ambulatoriais aprovados em estabelecimentos do município (todas as complexidades)", "procedimentos", "SIA/SUS", "ambulatorial"),
    "sia_valor_total_local": ("Valor total aprovado dos procedimentos ambulatoriais realizados no município", "R$ correntes", "SIA/SUS", "ambulatorial"),
    "internacoes_mc_local": ("Internações de média complexidade em hospitais do município (AIH tipo 1, ano da alta)", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_mc_res": ("Internações de média complexidade de residentes do município, em qualquer hospital de MT", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_ac_local": ("Internações de alta complexidade em hospitais do município", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_ac_res": ("Internações de alta complexidade de residentes do município, em qualquer hospital de MT", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_local": ("Internações (todas as complexidades) em hospitais do município", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_res": ("Internações de residentes do município em qualquer hospital de MT", "internações", "SIH/SUS", "hospitalar"),
    "internacoes_res_fora": ("Internações de residentes realizadas em hospitais de outro município de MT", "internações", "SIH/SUS", "hospitalar"),
    "diarias_local": ("Diárias pagas nas internações realizadas no município", "diárias", "SIH/SUS", "hospitalar"),
    "diarias_uti_local": ("Diárias de UTI pagas nas internações realizadas no município", "diárias", "SIH/SUS", "hospitalar"),
    "valor_sih_local": ("Valor aprovado das AIH realizadas em hospitais do município", "R$ correntes", "SIH/SUS", "hospitalar"),
    "valor_sih_res": ("Valor aprovado das AIH de residentes do município, em qualquer hospital de MT", "R$ correntes", "SIH/SUS", "hospitalar"),
    "obitos_hosp_local": ("Óbitos ocorridos nas internações realizadas no município", "óbitos", "SIH/SUS", "hospitalar"),
    "internacoes_urgencia_local": ("Internações de caráter não eletivo (urgência) realizadas no município", "internações", "SIH/SUS", "hospitalar"),
    "nascidos_vivos": ("Nascidos vivos de mães residentes no município (dados até 2024)", "nascidos vivos", "SINASC", "resultados"),
    "obitos_residentes": ("Óbitos de residentes no município (dados até 2024)", "óbitos", "SIM", "resultados"),
    "obitos_menor1": ("Óbitos de residentes com menos de 1 ano (dados até 2024)", "óbitos", "SIM", "resultados"),
    "desp_301_pc": ("Despesa liquidada na subfunção 301 (Atenção Básica) por habitante — igual a desp_ab_pc", "R$ por habitante", "SIOPS (RREO)", "indicador derivado"),
    "desp_302_pc": ("Despesa liquidada na subfunção 302 (Assistência Hospitalar e Ambulatorial) por habitante — igual a desp_mac_pc", "R$ por habitante", "SIOPS (RREO)", "indicador derivado"),
    "equipes_esf_p1000": ("Equipes de Saúde da Família por mil habitantes (o site publica a versão por 10 mil: equipes_esf_p10000)", "equipes por mil hab.", "CNES", "indicador derivado"),
}

# Catálogo dos downloads: (arquivo relativo a arquivos/, grupo, descrição, chave, período, fonte, script)
CATALOGO = [
    ("dados/painel_municipal_2020_2025.csv", "Painéis e indicadores",
     "Painel largo: uma linha por município e ano com todas as variáveis públicas do painel municipal (despesas, profissionais, leitos, produção, resultados) e os indicadores derivados publicados no site. Dicionário em painel_municipal_dicionario.csv.",
     "cod_mun6 + ano", PERIODO, "SIOPS, CNES, SISAB, SI-PNI, SIA, SIH, SIM, SINASC, IBGE", "01_preparar_dados.py"),
    ("dados/serie_longa.csv", "Painéis e indicadores",
     "Série municipal dos indicadores do site em formato longo (uma linha por município, indicador e ano), com nome do município, região de saúde, grupo, rótulo e unidade. Vazio = indisponível.",
     "cod_mun6 + indicador + ano", PERIODO, "Painel municipal (várias fontes)", "01_preparar_dados.py"),
    ("dados/serie_regioes_saude_2020_2025.csv", "Painéis e indicadores",
     "Agregados dos indicadores por região de saúde (contagens somadas; razões e percentuais recalculados com os totais da região), com rótulos.",
     "co_regsaud + indicador + ano", PERIODO, "Painel municipal (várias fontes)", "05_downloads.py"),
    ("dados/serie_mt_2020_2025.csv", "Painéis e indicadores",
     "Agregado estadual de cada indicador (coluna valor) e mediana dos municípios (coluna mediana), por ano.",
     "indicador + ano", PERIODO, "Painel municipal (várias fontes)", "05_downloads.py"),
    ("dados/indicadores_dicionario.csv", "Dicionários e referências",
     "Catálogo dos indicadores publicados: identificador, rótulo, grupo, unidade, formato, sentido (+1 maior é melhor; −1 menor é melhor; 0 contexto), fonte, fórmula, nota, último ano disponível e descrição curta.",
     "id", "—", "Projeto PPSUS-MT", "01_preparar_dados.py"),
    ("dados/painel_municipal_dicionario.csv", "Dicionários e referências",
     "Dicionário das 114 colunas de painel_municipal_2020_2025.csv: descrição, unidade, fonte e bloco temático; indica o identificador do indicador do site quando a coluna é um deles.",
     "coluna", "—", "Projeto PPSUS-MT", "05_downloads.py"),
    ("dados/municipios_mt.csv", "Dicionários e referências",
     "Os 142 municípios de Mato Grosso: códigos IBGE de 6 e 7 dígitos, nome, slug usado nas páginas, região de saúde, macrorregião, população 2025 e existência de hospital SUS em 2025.",
     "cod_mun6", "2025", "IBGE, SES-MT (PDR), CNES", "05_downloads.py"),
    ("dados/regioes_saude_mt.csv", "Dicionários e referências",
     "As 16 regiões de saúde (CIR): código, nome, macrorregião, número de municípios, população 2025 e lista de municípios.",
     "co_regsaud", "2025", "SES-MT (PDR), IBGE", "01_preparar_dados.py"),
    ("dados/sedes_municipais.csv", "Dicionários e referências",
     "Coordenadas da sede municipal (longitude, latitude, WGS84) dos 142 municípios, inclusive Boa Esperança do Norte, com região de saúde e fonte; são os pontos usados nas distâncias em linha reta do deslocamento (não rodoviárias).",
     "cod_mun6", "2022", "IBGE, Localidades do Brasil 2022 (sede municipal)", "00_sedes_ibge.py + 05_downloads.py"),
    ("dados/hospitais_sus_mt.csv", "Hospitais",
     "Hospitais com atendimento SUS, uma linha por estabelecimento (CNES) e ano: leitos, UTI, equipamentos, profissionais (FTE), internações por complexidade, diárias, valor, óbitos, mortalidade (%), permanência média (dias), taxa de ocupação dos leitos SUS (fração 0–1) e n_meses (competências do CNES em que o estabelecimento constou no ano; leitos e FTE são médias desses meses). Estabelecimentos identificados por nome fantasia e código CNES (dado público).",
     "cnes + ano", PERIODO, "CNES, SIH/SUS", "01_preparar_dados.py"),
    ("dados/fluxos_internacoes_municipios.csv", "Deslocamento residência × atendimento",
     "Fluxos de internação entre município de residência e município do hospital, por ano e nível de complexidade (MC, AC): internações, diárias, valor, óbitos e distância em linha reta entre as sedes municipais (km). Só residentes de MT identificados; AIH tipo 1, ano da alta.",
     "ano + cod_origem + cod_destino + nivel", PERIODO, "SIH/SUS (AIH reduzida)", "02_preparar_deslocamento.py"),
    ("dados/fluxos_internacoes_regioes.csv", "Deslocamento residência × atendimento",
     "Fluxos de internação entre regiões de saúde (residência → atendimento), por ano e nível de complexidade.",
     "ano + co_reg_origem + co_reg_destino + nivel", PERIODO, "SIH/SUS (AIH reduzida)", "02_preparar_deslocamento.py"),
    ("dados/deslocamento_municipios_2020_2025.csv", "Deslocamento residência × atendimento",
     "Por município e ano: internações de residentes por local (próprio município, mesma região, outra região), percentuais, distância média, destino principal e número de municípios de destino fora do município; e, como município de atendimento, internações recebidas, parcela vinda de fora, número de municípios de origem (excluído o próprio) e origem principal.",
     "cod_mun6 + ano", PERIODO, "SIH/SUS (AIH reduzida) + malha IBGE", "05_downloads.py"),
    ("dados/polos_internacao_2020_2025.csv", "Deslocamento residência × atendimento",
     "Municípios que realizaram internações (polos), por ano: internações recebidas, recebidas de outros municípios, número de municípios de origem (excluído o próprio), saldo (recebidas − internações de residentes) e internações de alta complexidade recebidas.",
     "cod_mun6 + ano", PERIODO, "SIH/SUS (AIH reduzida)", "05_downloads.py"),
    ("dados/resumo_deslocamento_mt_2020_2025.csv", "Deslocamento residência × atendimento",
     "Resumo estadual por ano e nível (MC, AC, total): internações de residentes de MT, parcelas no próprio município, na mesma região e em outra região, distância média, residência ignorada, residentes de outras UFs atendidos em MT e parcela de internações eletivas no próprio município e fora dele.",
     "ano + nivel", PERIODO, "SIH/SUS (AIH reduzida)", "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/internacoes_outras_uf_2020_2025.csv", "Deslocamento residência × atendimento",
     "Internações realizadas em hospitais de MT de residentes de outras unidades da federação, por ano e UF de residência (sigla e nome). Esses registros não entram nos fluxos.",
     "ano + uf", PERIODO, "SIH/SUS (AIH reduzida)", "02_preparar_deslocamento.py + 05_downloads.py"),
    ("geo/mt_municipios_regioes_saude.geojson", "Malhas (GeoJSON)",
     "Malha municipal mínima do IBGE (141 polígonos, simplificada para a web) com as propriedades cod_mun6, municipio, co_regsaud, regiao_saude e codarea (código IBGE de 7 dígitos). É a malha usada nos mapas do site.",
     "cod_mun6", "malha 2022", "IBGE + SES-MT (PDR)", "01_preparar_dados.py + 05_downloads.py"),
    ("geo/mt_municipios_ibge_minima.geojson", "Malhas (GeoJSON)",
     "Malha municipal do IBGE em resolução mínima, sem tratamento (propriedade codarea = código IBGE de 7 dígitos).",
     "codarea", "malha 2022", "IBGE", "—"),
    ("geo/mt_municipios_ibge_intermediaria.geojson", "Malhas (GeoJSON)",
     "Malha municipal do IBGE em resolução intermediária (mais detalhada e mais pesada), sem tratamento (propriedade codarea).",
     "codarea", "malha 2022", "IBGE", "—"),
    ("dados/catalogo_arquivos.csv", "Dicionários e referências",
     "Este catálogo: descrição, chave, período, fonte, linhas, colunas e tamanho de cada arquivo publicado.",
     "arquivo", "—", "Projeto PPSUS-MT", "05_downloads.py"),
]


def rotulos_ind(ind: pd.DataFrame) -> pd.DataFrame:
    return ind[["id", "grupo", "rotulo", "unidade"]].rename(columns={"id": "indicador"})


def main() -> None:
    msg("05_downloads.py — complementos de arquivos/ a partir de dados_site/")
    mun = ler("municipios.csv")
    ind = ler("indicadores.csv")
    reg = ler("regioes.csv")
    nomes = mun[["cod_mun6", "municipio", "regiao_saude"]]

    # 1. municípios
    gravar(mun, DOWN / "municipios_mt.csv")

    # 2. séries por região e estadual, com rótulos
    sr = ler("serie_regiao.csv").merge(reg[["co_regsaud", "regiao_saude", "macrorregiao"]], on="co_regsaud", how="left")
    sr = sr.merge(rotulos_ind(ind), on="indicador", how="left")
    sr = sr[["co_regsaud", "regiao_saude", "macrorregiao", "grupo", "indicador", "rotulo", "unidade", "ano", "valor"]]
    sr = sr.sort_values(["co_regsaud", "grupo", "indicador", "ano"], kind="stable")
    gravar(sr, DOWN / "serie_regioes_saude_2020_2025.csv")

    smt = ler("serie_mt.csv").merge(rotulos_ind(ind), on="indicador", how="left")
    smt = smt[["grupo", "indicador", "rotulo", "unidade", "ano", "valor", "mediana"]]
    ordem = dict(zip(ind["id"], ind["ordem"])) if "ordem" in ind.columns else {}
    smt["_o"] = smt["indicador"].map(ordem).fillna(999)
    smt = smt.sort_values(["_o", "ano"], kind="stable").drop(columns="_o")
    gravar(smt, DOWN / "serie_mt_2020_2025.csv")

    # 3. deslocamento
    d = ler("deslocamento_mun_ano.csv").merge(nomes, on="cod_mun6", how="left")
    cols = ["cod_mun6", "municipio", "regiao_saude"] + [c for c in d.columns if c not in ("cod_mun6", "municipio", "regiao_saude")]
    gravar(d[cols].sort_values(["cod_mun6", "ano"]), DOWN / "deslocamento_municipios_2020_2025.csv")

    p = ler("polos_ano.csv").merge(nomes[["cod_mun6", "regiao_saude"]], on="cod_mun6", how="left")
    cols = ["cod_mun6", "municipio", "regiao_saude"] + [c for c in p.columns if c not in ("cod_mun6", "municipio", "regiao_saude")]
    gravar(p[cols].sort_values(["ano", "internacoes_recebidas"], ascending=[True, False]), DOWN / "polos_internacao_2020_2025.csv")

    r = ler("resumo_deslocamento_ano.csv")
    gravar(r.sort_values(["ano", "nivel"]), DOWN / "resumo_deslocamento_mt_2020_2025.csv")

    if (DS / "outras_uf_ano.csv").exists():
        u = ler("outras_uf_ano.csv")
        gravar(u.sort_values(["ano", "internacoes"], ascending=[True, False]), DOWN / "internacoes_outras_uf_2020_2025.csv")
    else:
        msg("  AVISO: dados_site/outras_uf_ano.csv não existe (rode o script 02); download de outras UFs não gerado")

    # 4. sedes municipais (coordenadas usadas nas distâncias), com região de saúde
    if (DS / "sedes_municipais.csv").exists():
        c = ler("sedes_municipais.csv")[["cod_mun6", "cod_ibge7", "lon", "lat", "fonte"]]
    else:
        msg("  AVISO: dados_site/sedes_municipais.csv não existe (rode o script 00); usando centroides.csv (centro geométrico)")
        c = ler("centroides.csv").merge(mun[["cod_mun6", "cod_ibge7"]], on="cod_mun6", how="left")
        c["fonte"] = "IBGE, malha municipal 2022 (centro geométrico do polígono)"
    c = c.merge(nomes, on="cod_mun6", how="left")
    gravar(c[["cod_mun6", "cod_ibge7", "municipio", "regiao_saude", "lon", "lat", "fonte"]].sort_values("cod_mun6"),
           DOWN / "sedes_municipais.csv")
    antigo = DOWN / "centroides_municipios.csv"  # substituído por sedes_municipais.csv
    if antigo.exists():
        antigo.unlink()
        msg("  removido %s (substituído por sedes_municipais.csv)", antigo.relative_to(RAIZ).as_posix())

    # 5. dicionário do painel largo
    painel = DOWN / "painel_municipal_2020_2025.csv"
    if not painel.exists():
        sys.exit("ERRO: arquivos/dados/painel_municipal_2020_2025.csv não existe; rode o script 01.")
    colunas = list(pd.read_csv(painel, nrows=0, encoding="utf-8").columns)
    ind_i = ind.set_index("id")
    linhas, faltam = [], []
    for col in colunas:
        if col in ind_i.index:
            i = ind_i.loc[col]
            linhas.append(dict(coluna=col, descricao=i["descricao"] if "descricao" in ind_i.columns else i["rotulo"],
                               unidade=i["unidade"], fonte=i["fonte"],
                               bloco="indicador do site (" + str(i["grupo"]) + ")", indicador_site=col))
        elif col in BRUTAS:
            desc, uni, fonte, bloco = BRUTAS[col]
            linhas.append(dict(coluna=col, descricao=desc, unidade=uni, fonte=fonte, bloco=bloco, indicador_site=""))
        else:
            faltam.append(col)
            linhas.append(dict(coluna=col, descricao="(sem descrição)", unidade="", fonte="", bloco="", indicador_site=""))
    if faltam:
        msg("  AVISO: colunas sem descrição no dicionário: %s", ", ".join(faltam))
    dic = pd.DataFrame(linhas)
    dic.insert(0, "posicao", range(1, len(dic) + 1))
    gravar(dic, DOWN / "painel_municipal_dicionario.csv")

    # 6. malha com propriedades do site
    src = DS / "geo_mt.geojson"
    if src.exists():
        dst = GEO / "mt_municipios_regioes_saude.geojson"
        shutil.copyfile(src, dst)
        n = len(json.load(open(dst, encoding="utf-8"))["features"])
        msg("  copiado %s (%d feições)", dst.relative_to(RAIZ).as_posix(), n)
    else:
        msg("  AVISO: dados_site/geo_mt.geojson não existe; malha com regiões não publicada")

    # 7. catálogo (conferência de existência + linhas, colunas e tamanho)
    cat = []
    for arq, grupo, desc, chave, periodo, fonte, script in CATALOGO:
        f = RAIZ / "arquivos" / arq
        if arq.endswith("catalogo_arquivos.csv"):
            nlin, ncol, nbytes = len(CATALOGO), 10, None
        elif not f.exists():
            msg("  AVISO: arquivo do catálogo ausente: arquivos/%s", arq)
            nlin = ncol = nbytes = None
        elif f.suffix == ".geojson":
            g = json.load(open(f, encoding="utf-8"))
            nlin, ncol, nbytes = len(g["features"]), len(g["features"][0]["properties"]), f.stat().st_size
        else:
            hdr = pd.read_csv(f, nrows=0, encoding="utf-8").columns
            with open(f, encoding="utf-8") as fh:
                nlin = sum(1 for _ in fh) - 1
            ncol, nbytes = len(hdr), f.stat().st_size
        cat.append(dict(arquivo=arq, grupo=grupo, descricao=desc, chave=chave, periodo=periodo, fonte=fonte,
                        linhas=nlin, colunas=ncol, bytes=nbytes, gerado_por=script))
    cat = pd.DataFrame(cat)
    dst = DOWN / "catalogo_arquivos.csv"
    gravar(cat, dst)
    # tamanho do próprio catálogo
    cat.loc[cat["arquivo"].str.endswith("catalogo_arquivos.csv"), "bytes"] = dst.stat().st_size
    gravar(cat, dst)
    msg("concluído: %d arquivos no catálogo", len(cat))


if __name__ == "__main__":
    main()
