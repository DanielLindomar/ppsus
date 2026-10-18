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
  arquivos/dados/residentes_mt_outras_uf_*.csv           internações de residentes de MT em hospitais de outras UF (v0.3)
  arquivos/dados/saldo_internacoes_mt_outras_uf_2020_2025.csv  entrada × saída × saldo por UF (v0.3)
  arquivos/dados/previsao_*.csv, localizacao_*.csv e judicializacao_*.csv  (v0.4) NÃO são gerados aqui: vêm dos
                                                         scripts 08, 11 e 10 (cópia conferida dos arquivos auditados);
                                                         este script só os confere e os inclui no catálogo
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
GRUPO_FUGA = "Internações de residentes de MT em outros estados"
FONTE_FUGA = "SIH/SUS (AIH reduzida, RD) de MT e das 26 outras UF"
# Internações de residentes de MT em outras UF (versão 0.3): dados_site/ → arquivos/dados/
FUGA = [("fuga_resumo_ano.csv", "residentes_mt_outras_uf_resumo_2020_2025.csv"),
        ("fuga_uf_ano.csv", "residentes_mt_outras_uf_por_uf_2020_2025.csv"),
        ("fuga_saldo_uf_ano.csv", "saldo_internacoes_mt_outras_uf_2020_2025.csv"),
        ("fuga_regiao_ano.csv", "residentes_mt_outras_uf_regioes_2020_2025.csv"),
        ("fuga_mun_periodo.csv", "residentes_mt_outras_uf_municipios_2020_2025.csv"),
        ("fuga_destinos_mun.csv", "residentes_mt_outras_uf_destinos_2020_2025.csv")]
CSV_KW = dict(index=False, encoding="utf-8", lineterminator="\n", na_rep="")
PERIODO = "2020–2025"
# Versão 0.4: seções de previsão (script 08), judicialização (script 10) e localização (script 11). Os arquivos
# já chegam a arquivos/dados/ conferidos (supressão < 5 e complementar); aqui só entram no catálogo.
GRUPO_PREV = "Previsão de demanda (preliminar)"
GRUPO_LOC = "Localização de serviços (preliminar)"
GRUPO_JUD = "Judicialização da saúde (preliminar)"
FONTE_PREV = "SIH/SUS (MT), SIVEP-Gripe, INMET, InfoDengue, RIPSA"
FONTE_PREV_SIH = "SIH/SUS (AIH reduzida, MT)"
FONTE_LOC = "SINASC, SIH/SUS, CNES, RIPSA/IBGE, OSRM/OpenStreetMap"
FONTE_JUD = "DataJud/CNJ (API Pública): TJMT"
FONTE_JUD_POP = "DataJud/CNJ (API Pública): TJMT; IBGE"


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
    """Grava o CSV (UTF-8, LF). Se o arquivo já existe com o MESMO conteúdo (ignorando só o fim de linha),
    não o regrava: assim o git não marca como modificado um arquivo versionado que só mudaria de fim de linha
    (core.autocrlf=true no Windows; NOTAS_V04, seção 11)."""
    caminho.parent.mkdir(parents=True, exist_ok=True)
    novo = df.to_csv(**{k: v for k, v in CSV_KW.items() if k != "encoding"}).encode("utf-8")
    if caminho.exists() and caminho.read_bytes().replace(b"\r\n", b"\n") == novo:
        msg("  sem mudança %s (%d linhas, %d colunas; não regravado)", caminho.relative_to(RAIZ).as_posix(), len(df), df.shape[1])
        return
    caminho.write_bytes(novo)
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
    "fte_acs": ("Agentes comunitários de saúde — só o CBO 515105 (FTE 40 h, média anual); até a versão 0.2 do site somava a família CBO 5151 (ver fte_5151_familia)", "FTE", "CNES", "capacidade"),
    "fte_ace": ("Agentes de combate às endemias — CBO 515140 (FTE 40 h, média anual)", "FTE", "CNES", "capacidade"),
    "fte_5151_outros": ("Demais ocupações da família CBO 5151, exceto ACS e agentes de combate às endemias (atendente de enfermagem, visitador sanitário, agentes indígenas de saúde e de saneamento, socorrista e outras), FTE 40 h, média anual", "FTE", "CNES", "capacidade"),
    "fte_5151_familia": ("Família CBO 5151 inteira (fte_acs + fte_ace + fte_5151_outros), FTE 40 h, média anual — valor publicado como agentes comunitários de saúde até a versão 0.2 do site", "FTE", "CNES", "capacidade"),
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
     "Dicionário das {n_colunas_painel} colunas de painel_municipal_2020_2025.csv: descrição, unidade, fonte e bloco temático; indica o identificador do indicador do site quando a coluna é um deles.",
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
    ("dados/residentes_mt_outras_uf_resumo_2020_2025.csv", GRUPO_FUGA,
     "Resumo estadual por ano e nível (MC, AC, total): internações de residentes de MT em hospitais de MT e de outras UF, parcela em outras UF, valor aprovado (todas as linhas da AIH, inclusive continuações) e parcela em outras UF, parcela de internações eletivas, UF principal de destino, número de UF e de municípios de destino, residentes de outras UF atendidos em MT (entrada) e saldo (entrada − saída).",
     "ano + nivel", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/residentes_mt_outras_uf_por_uf_2020_2025.csv", GRUPO_FUGA,
     "Internações de residentes de MT em hospitais de outras UF por ano, UF de destino (código, sigla e nome) e nível (MC, AC, total): internações, internações de urgência (caráter não eletivo), diárias e valor aprovado. Grade completa (26 UF × anos × níveis), com zero onde não houve internação.",
     "ano + cod_uf + nivel", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/saldo_internacoes_mt_outras_uf_2020_2025.csv", GRUPO_FUGA,
     "Saldo das internações entre MT e cada UF, por ano: entrada (residentes da UF internados em hospitais de MT), saída (residentes de MT internados em hospitais da UF) e saldo (entrada − saída; negativo = MT envia mais do que recebe).",
     "ano + cod_uf", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/residentes_mt_outras_uf_regioes_2020_2025.csv", GRUPO_FUGA,
     "Por região de saúde de residência e ano: internações dos residentes (em MT e em outras UF), internações em outras UF e parcela; o mesmo para a alta complexidade; UF principal de destino. Células com 1 a 4 internações suprimidas (vazias), com supressão complementar; as colunas total_suprimido, ac_suprimida e nota_supressao indicam o motivo.",
     "co_regsaud + ano", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/residentes_mt_outras_uf_municipios_2020_2025.csv", GRUPO_FUGA,
     "Por município de residência, período 2020–2025 somado: internações dos residentes (em MT e em outras UF), internações em outras UF, parcela e UF principal de destino. Células com 1 a 4 internações suprimidas (vazias), com supressão complementar dentro da região de saúde; as colunas total_suprimido e nota_supressao indicam o motivo.",
     "cod_mun6", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    ("dados/residentes_mt_outras_uf_destinos_2020_2025.csv", GRUPO_FUGA,
     "Os 20 municípios fora de MT que mais internaram residentes de MT em 2020–2025: internações, parcela do total em outras UF e internações de alta complexidade (suprimidas quando a alta ou a média complexidade tem de 1 a 4 internações).",
     "cod_mun6", PERIODO, FONTE_FUGA, "02_preparar_deslocamento.py + 05_downloads.py"),
    # ---- Versão 0.4: previsão de demanda (A5), resultados PRELIMINARES (script 08) ----
    ("dados/previsao_proximas_semanas.csv", GRUPO_PREV,
     "Previsão das quatro semanas seguintes ao corte de 17/10/2026 (SE 42 a 45/2026) das internações J00–J99, por região de saúde e MT, todas as idades e menores de 5 anos: método (nowcast + previsão encadeada e comparadores), previsão, intervalos de 80% e 95%, limiar P90 e situação do alerta. Valores que revelariam contagem de 1 a 4 suprimidos.",
     "alvo + cod_regiao + metodo + ano_se + se", "SE 42–45/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_nowcast_hoje.csv", GRUPO_PREV,
     "Nowcast das semanas ainda incompletas no SIH (SE 17 a 41/2026) no corte de 17/10/2026, por método, região de saúde e MT: estimativa, intervalos de 80% e 95%, atraso em semanas e internações já processadas (contagens de 1 a 4 suprimidas, com supressão complementar).",
     "alvo + cod_regiao + metodo + ano_se + se", "SE 17–41/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_serie_semanal_carga_2026_10_17.csv", GRUPO_PREV,
     "Série semanal das internações J00–J99 (todas as idades e menores de 5 anos) por região de saúde e MT na carga do SIH de 17/10/2026, SE 1/2024 a SE 16/2026. Contagens de 1 a 4 suprimidas, com supressão complementar.",
     "alvo + cod_regiao + ano_se + se", "2024–2026", FONTE_PREV_SIH, "08_preparar_previsao.py"),
    ("dados/previsao_serie_semanal_2020_2026.csv", GRUPO_PREV,
     "Série semanal observada das internações J00–J99 (AIH tipo 1, diagnóstico principal) por região de saúde e MT, óticas de ocorrência e de residência, SE 1/2020 a SE 12/2026 (última semana completa do modelo de referência). Contagens de 1 a 4 suprimidas, com supressão complementar.",
     "otica + cod_regiao + ano_se + se", "2020–2026", FONTE_PREV_SIH, "08_preparar_previsao.py"),
    ("dados/previsao_metricas_modelos.csv", GRUPO_PREV,
     "Erro de previsão de cada modelo (ingênuos, SARIMA, HGB, LightGBM, Random Forest, rede neural e variantes) por ótica, nível (MT ou média das 16 regiões) e horizonte: MAE, RMSE, MASE, rMAE e viés, na validação com origem móvel.",
     "modelo + otica + nivel + h", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_metricas_regioes.csv", GRUPO_PREV,
     "Erro médio dos horizontes de 1 a 4 semanas por região de saúde e modelo, com a marca do modelo de menor MASE em cada região.",
     "otica + cod_regiao + modelo", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_validacao_mt.csv", GRUPO_PREV,
     "Observado e previsto na validação com origem móvel, série de Mato Grosso, horizontes de 1 e 4 semanas, por modelo.",
     "otica + modelo + h + ano_se_alvo + se_alvo", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_testes_dm.csv", GRUPO_PREV,
     "Testes de Diebold-Mariano (correção HLN) entre pares de modelos do modelo de referência sem atraso: perdas médias, estatística e p-valor.",
     "otica + nivel + h + modelo_a + modelo_b", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_cobertura_intervalos.csv", GRUPO_PREV,
     "Cobertura, largura e interval score dos intervalos de previsão de 80% e 95%, por modelo, ótica, nível e horizonte.",
     "tipo + modelo + otica + nivel + h", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_baseline_4sem.csv", GRUPO_PREV,
     "Previsões do modelo de referência sem atraso para as quatro semanas seguintes à última semana completa (SE 13 a 16/2026), por região, MT e modelo, com a contagem já processada na carga atual. Contagens de 1 a 4 e previsões ingênuas que as copiariam suprimidas.",
     "otica + cod_regiao + modelo + h", "SE 13–16/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_metricas_nowcast.csv", GRUPO_PREV,
     "Erro do nowcast por método e faixa de atraso, na validação retrospectiva com cortes de 2024 e 2025, por cenário de reconstrução, alvo e nível.",
     "cenario + alvo + nivel + metodo + faixa_atraso_semanas", "2024–2025", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_metricas_encadeado.csv", GRUPO_PREV,
     "Erro da previsão a partir da semana de corte (nowcast + previsão encadeada) e dos comparadores, por cenário, alvo, nível e horizonte, com a cobertura dos intervalos.",
     "cenario + alvo + nivel + metodo + h", "2024–2025", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_testes_dm_encadeado.csv", GRUPO_PREV,
     "Testes de Diebold-Mariano da previsão encadeada: estatística HLN, versão robusta de Newey-West e p-valor ajustado por Holm.",
     "cenario + alvo + nivel + h + modelo_a + modelo_b", "2024–2025", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_metricas_menor5.csv", GRUPO_PREV,
     "Erro da previsão das internações de menores de 5 anos (validação com origem móvel, sem atraso), por modelo, nível e horizonte.",
     "modelo + nivel + h", "SE 1/2024–SE 12/2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_alerta_limiares.csv", GRUPO_PREV,
     "Limiares de alta pressão (percentis 80 e 90 das 104 semanas de 2022–2023) por alvo e região de saúde; limiares que revelariam contagem pequena ficam suprimidos.",
     "alvo + cod_regiao + regra", "2022–2023", FONTE_PREV_SIH, "08_preparar_previsao.py"),
    ("dados/previsao_alerta_medidas.csv", GRUPO_PREV,
     "Alerta avaliado como classificação: sensibilidade, especificidade, VPP, VPN e F1 por regra, fonte, modelo e horizonte (vp, fp, fn e vn = número de região-semanas).",
     "regra + fonte + alvo + nivel + modelo + h", "2024–2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_alerta_antecedencia.csv", GRUPO_PREV,
     "Antecedência do primeiro aviso nos episódios de alta pressão, por regra, fonte, modelo e duração mínima do episódio (episódios e detectados = número de episódios).",
     "regra + fonte + alvo + nivel + modelo + duracao_minima", "2024–2026", FONTE_PREV, "08_preparar_previsao.py"),
    ("dados/previsao_contexto_pediatrico.csv", GRUPO_PREV,
     "Contexto pediátrico por região de saúde e MT: limiar P90 de menores de 5 anos, média de 2022–2023, permanência média, leitos pediátricos clínicos e de UTI pediátrica SUS e ocupação equivalente no limiar.",
     "cod_regiao", "2022–2025", "SIH/SUS (MT), CNES", "08_preparar_previsao.py"),
    ("dados/previsao_dicionario.csv", GRUPO_PREV,
     "Dicionário dos arquivos de previsão: arquivo de origem, versão, conteúdo, colunas, regra de supressão e situação de publicação (resultados preliminares).",
     "arquivo", "—", "Projeto PPSUS-MT", "08_preparar_previsao.py"),
    # ---- Versão 0.4: localização de serviços, pilotos de parto e UTI adulto, PRELIMINAR (script 11) ----
    ("dados/localizacao_acesso_municipios_2025.csv", GRUPO_LOC,
     "Acesso atual por município de residência e piloto (atenção ao parto, UTI adulto): população-alvo, leitos próprios, tempo e distância rodoviários até o serviço mais próximo, índice de acesso E2SFCA (60 e 120 min), atendimentos de 2024–2025, tempo e distância médios percorridos e percentuais no próprio município, fora da região e fora de MT (vazios quando a contagem é de 1 a 4 ou permitiria deduzi-la).",
     "piloto + cod_mun6", "2024–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_acesso_regioes_2025.csv", GRUPO_LOC,
     "Acesso atual por região de saúde e piloto: população-alvo, leitos e municípios com o serviço em 2025, atendimentos de 2024–2025, tempo e distância médios percorridos, percentuais por local de atendimento e população a até 60 e 120 minutos.",
     "piloto + co_regsaud", "2024–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_demanda_projetada_2026_2030.csv", GRUPO_LOC,
     "Demanda projetada por piloto, nível (MT, região de saúde, município de residência) e ano: projeção, intervalo de 80% e, no parto, projeção calibrada ao IBGE. PROVISÓRIA: usa a projeção populacional municipal provisória (método de razão sobre a projeção do IBGE para MT). Estimativas de modelo, não contagens observadas.",
     "piloto + nivel + codigo + ano", "2026–2030", "SINASC, SIH/SUS, RIPSA/IBGE", "11_preparar_localizacao.py"),
    ("dados/localizacao_otimizacao_solucoes_2030.csv", GRUPO_LOC,
     "Soluções da otimização para 2030 por piloto, modelo (p-mediana, cobertura máxima de 60 e 120 min e, na UTI adulto, versão com capacidade e regional) e número de unidades novas: municípios escolhidos, tempo e distância médios, cobertura a até 60 e 120 min, ganhos e, na UTI, demanda acima da capacidade e déficit de leitos. Cenários de pesquisa, não recomendação.",
     "piloto + modelo + limiar_min + k", "2030", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_otimizacao_sensibilidade_2030.csv", GRUPO_LOC,
     "Sensibilidade das soluções da otimização às variantes de demanda: municípios escolhidos, segunda melhor solução, diferença no objetivo e marca de quase empate.",
     "piloto + modelo + limiar_min + variante + k", "2030", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_cenarios_resumo_2030.csv", GRUPO_LOC,
     "Cenários de 2030 com a escolha do paciente: municípios com unidade nova, tempo e distância esperados, cobertura, fluxo para as unidades novas e ganho de tempo frente à referência e frente à ida à unidade mais próxima.",
     "piloto + cenario", "2030", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_cenarios_ganho_municipios_2030.csv", GRUPO_LOC,
     "Ganho de tempo por município de residência em cada cenário de 2030: tempo médio de referência, tempo no cenário e ganho por paciente, em minutos.",
     "piloto + cenario + cod_mun6", "2030", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_uti_leitos_regioes_2030.csv", GRUPO_LOC,
     "UTI adulto por região de saúde: demanda dos residentes, leitos SUS de 2025, leitos necessários com a ocupação-alvo de 85% (parâmetro de cenário) com a demanda de 2025 e a projetada para 2030, e saldo.",
     "co_regsaud", "2025 e 2030", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_validacao_demanda.csv", GRUPO_LOC,
     "Validação dos modelos de demanda no teste temporal, por piloto e modelo: MAE, RMSE, WMAPE (municípios e regiões) e erro do total.",
     "piloto + modelo", "2024–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_validacao_escolha_temporal.csv", GRUPO_LOC,
     "Validação dos modelos de escolha do paciente no teste temporal: índice CPC, WMAPE dos destinos, acerto do destino principal e tempo médio observado e previsto.",
     "piloto + modelo", "2024–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_validacao_escolha_experimentos.csv", GRUPO_LOC,
     "Validação da escolha do paciente em experimentos naturais (aberturas, fechamentos e reduções de leitos no CNES): CPC médio por modelo e número de eventos em que o modelo vence, empata ou perde da persistência.",
     "piloto + tipo", "2021–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_validacao_escolha_experimentos_ano.csv", GRUPO_LOC,
     "Experimentos naturais da validação da escolha do paciente, por ano do evento: anos de ajuste e de teste, CPC médio do modelo e da persistência e resultado da comparação.",
     "piloto + ano_evento", "2021–2025", FONTE_LOC, "11_preparar_localizacao.py"),
    ("dados/localizacao_dicionario.csv", GRUPO_LOC,
     "Dicionário das colunas dos arquivos de localização de serviços.",
     "arquivo + coluna", "—", "Projeto PPSUS-MT", "11_preparar_localizacao.py"),
    # ---- Versão 0.4: judicialização da saúde, DataJud/CNJ, PRELIMINAR (script 10) ----
    ("dados/judicializacao_mt_ano.csv", GRUPO_JUD,
     "Ações de saúde no 1º grau do TJMT por ano de ajuizamento (2026 até 11/09): total, saúde pública e suplementar, grupos de assunto da saúde pública, ações atribuíveis a uma comarca, ações com liminar concedida e ações ajuizadas diretamente no Núcleo de Justiça 4.0 da Saúde sem comarca de origem. Células de 1 a 4 suprimidas.",
     "ano", "2020–2026", FONTE_JUD, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_mt_mes_grupo.csv", GRUPO_JUD,
     "Série mensal das ações de saúde por grupo de assunto, de 01/2020 a 09/2026 (mês incompleto marcado). Células de 1 a 4 suprimidas, com supressão complementar.",
     "ano + mes + grupo", "2020–2026", FONTE_JUD, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_comarca_2022_2024.csv", GRUPO_JUD,
     "Comarcas no período principal 2022–2024: ações de saúde (total, pública e suplementar, com supressão), população média, taxa bruta, taxa suavizada arredondada a 5 por 100 mil, faixa e marca de limite inferior (Cuiabá e Várzea Grande).",
     "comarca", "2022–2024", FONTE_JUD_POP, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_comarca_ano.csv", GRUPO_JUD,
     "Comarca e ano: ações de saúde (com supressão), população, taxa bruta, faixa da taxa suavizada e marcas de ano parcial, limite inferior e quebra pela centralização no Núcleo de Justiça 4.0 (2025–2026).",
     "comarca + ano", "2020–2026", FONTE_JUD_POP, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_municipio_ano.csv", GRUPO_JUD,
     "Município e ano: comarca, faixa da taxa suavizada da comarca, taxa suavizada 2022–2024 da comarca e marcas. O município herda a taxa da comarca; não há contagens por município.",
     "cod_mun6 + ano", "2020–2026", FONTE_JUD_POP, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_comarca_municipio.csv", GRUPO_JUD,
     "Correspondência entre os 142 municípios e as comarcas do TJMT: comarca, se o município é sede e a regra de atribuição usada.",
     "cod_mun6", "—", "TJMT, Corregedoria-Geral da Justiça", "10_preparar_judicializacao.py"),
    ("dados/judicializacao_previsao_trimestre.csv", GRUPO_JUD,
     "Previsão mensal das ações de saúde de setembro a novembro de 2026, por grupo de assunto, com intervalo empírico de 80% (modelo de menor MASE em cada grupo).",
     "grupo + alvo", "09–11/2026", FONTE_JUD, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_previsao_metricas.csv", GRUPO_JUD,
     "Erro da previsão mensal na validação com origem móvel, por grupo e modelo (ETS, SARIMA, LightGBM e referências ingênuas): MAE, RMSE, viés, MASE e rMAE.",
     "grupo + modelo", "01/2020–08/2026", FONTE_JUD, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_fatores_associados.csv", GRUPO_JUD,
     "Fatores associados à taxa de ações por comarca (binomial negativa, 2022–2025, 77 comarcas sem Cuiabá e Várzea Grande): razão de taxas por desvio-padrão, intervalo de 95% e p-valores bruto e ajustados (Holm e Benjamini-Hochberg). Associação, não causalidade.",
     "dependente + variavel", "2022–2025", "DataJud/CNJ; painéis do projeto (CNES, SIH, DEA v2.1); IBGE", "10_preparar_judicializacao.py"),
    ("dados/judicializacao_testes_bloco.csv", GRUPO_JUD,
     "Testes conjuntos (Wald) do bloco de oferta e eficiência por tipo de ação e especificação (binomial negativa e Poisson com efeitos fixos de comarca): estatística, graus de liberdade e p-valores bruto e ajustados (Holm e Benjamini-Hochberg). Associação, não causalidade.",
     "dependente + especificacao", "2021–2025", "DataJud/CNJ; painéis do projeto (CNES, SIH, DEA v2.1); IBGE", "10_preparar_judicializacao.py"),
    ("dados/judicializacao_indicadores_complementares.csv", GRUPO_JUD,
     "Indicadores citados no texto da aba Judicialização que não estão nas tabelas acima: cobertura da coleta frente ao painel de saúde do CNJ, peso da Justiça Federal, códigos de origem associados às comarcas, correlação de postos entre anos, validação fora da amostra dos fatores associados e testes de Diebold-Mariano da previsão.",
     "grupo + indicador + recorte", "2020–2026", FONTE_JUD, "10_preparar_judicializacao.py"),
    ("dados/judicializacao_auditoria_supressao.csv", GRUPO_JUD,
     "Resumo da auditoria da supressão dos arquivos de judicialização: células, relações de soma, supressões primárias e complementares e células recuperáveis (nenhuma).",
     "item", "—", "Projeto PPSUS-MT", "10_preparar_judicializacao.py"),
    ("dados/judicializacao_dicionario.csv", GRUPO_JUD,
     "Dicionário das colunas dos arquivos de judicialização.",
     "arquivo + coluna", "—", "Projeto PPSUS-MT", "10_preparar_judicializacao.py"),
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

    # 3b. internações de residentes de MT em outras UF (arquivos já com nomes e supressão, script 02)
    for src, dst in FUGA:
        if (DS / src).exists():
            gravar(ler(src), DOWN / dst)
        else:
            msg("  AVISO: dados_site/%s não existe (rode o script 02); %s não gerado", src, dst)

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
        desc = desc.replace("{n_colunas_painel}", str(len(colunas)))  # número de colunas lido do painel gravado pelo script 01
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
