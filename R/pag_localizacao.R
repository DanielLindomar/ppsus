# =============================================================================
# Observatório PPSUS-MT — aba "Localização" (localizacao/index.qmd, parto.qmd, uti-adulto.qmd)
#
# Lê somente dados_site/localizacao/ (gerado e conferido por scripts/11_preparar_localizacao.py a
# partir dos arquivos agregados da frente de localização, versão localizacao_pilotos_2026-10-17,
# revisão 1). Carregar DEPOIS de R/funcoes.R (usa num, esc, kpi_simples, GEO, mapa_vazio etc.).
#
# Regras de divulgação aplicadas aqui (além das do script 11):
#  - células vazias (supressão de 1 a 4 e supressão complementar) aparecem como "suprimido";
#    nenhum valor suprimido é recalculado;
#  - contagens MODELADAS de 1 a 4 (só o limite inferior do intervalo de 80% de alguns municípios)
#    aparecem como "< 5" e não entram como número nos dados embutidos das tabelas;
#  - projeções de 2026–2030 e cenários são PROVISÓRIOS (população municipal provisória) e
#    os parâmetros dos cenários não são normas.
#
# Índice
#   0. Constantes, leitura e formatação
#   1. Componentes gerais (faixa, navegação, CSS, KPIs, rodapé, arquivos)
#   2. Acesso atual (mapa com vistas, tabelas por região e por município)
#   3. Demanda projetada (gráfico com faixa, tabelas)
#   4. Validação dos modelos (L1, L2 temporal, experimentos naturais)
#   5. Otimização (soluções k = 0..5, curvas, municípios escolhidos, sensibilidade, leitos de UTI)
#   6. Cenários com a escolha do paciente (resumo e ganho por município)
# =============================================================================

# ---- 0. Constantes, leitura e formatação ---------------------------------------------
LOC_DIR   <- file.path(RAIZ, "dados_site", "localizacao")
DATA_LOC  <- "17/10/2026"
ANO_OFERTA <- 2025L

ler_loc <- function(nome) {
  f <- file.path(LOC_DIR, paste0(nome, ".csv"))
  if (!file.exists(f)) { aviso("arquivo ausente: dados_site/localizacao/%s.csv (tabela vazia)", nome); return(tibble::tibble()) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  txt <- intersect(c("co_regsaud", "codigo", "abertos", "segunda_abertos", "nomes_abertos", "segunda_nomes", "tipos",
                     "anos_ajuste", "anos_teste"), hdr)
  tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                      colClasses = if (length(txt)) list(character = txt) else NULL))
}
LACE <- ler_loc("acesso_atual_mun")
LREG <- ler_loc("acesso_regiao")
LPROJ <- ler_loc("projecao_demanda")
LV1 <- ler_loc("validacao_demanda")
LV2 <- ler_loc("validacao_escolha_temporal")
LV3 <- ler_loc("validacao_escolha_experimentos")
LV4 <- ler_loc("validacao_escolha_experimentos_ano")
LSOL <- ler_loc("otimizacao_solucoes")
LSEN <- ler_loc("otimizacao_sensibilidade")
LNEC <- ler_loc("uti_necessidade_regional")
LCEN <- ler_loc("cenarios_resumo")
LGAN <- ler_loc("cenarios_ganho_mun")
para_logico <- function(x) if (is.logical(x)) x else tolower(as.character(x)) %in% c("true", "1")
# Linha de Mato Grosso (co_regsaud "51"): total do estado calculado na origem a partir das contagens antes da supressão
# (revisão 2, 18/10/2026). Os totais do estado vêm dela, não da soma das regiões, que podem ter células suprimidas.
LREG_MT <- if (nrow(LREG)) LREG[LREG$co_regsaud == "51", ] else LREG
if (nrow(LREG)) { LREG <- LREG[LREG$co_regsaud != "51", ]; LREG$suprimido <- para_logico(LREG$suprimido) }
if (nrow(LACE)) LACE$suprimido <- para_logico(LACE$suprimido)
if (nrow(LSEN)) { LSEN$quase_empate <- para_logico(LSEN$quase_empate); LSEN$igual_principal <- para_logico(LSEN$igual_principal) }

# Pilotos: rótulos e unidades
PIL <- list(
  parto = list(
    nome = "Atenção ao parto", curto = "parto", servico = "leito obstétrico", servico_pl = "leitos obstétricos",
    tem_servico = "com leito obstétrico", pop = "mulheres de 15 a 49 anos", unid = "partos", unid1 = "parto",
    unid_obs = "nascidos vivos hospitalares", paciente = "parto", limiar = 60L,
    e2_unid = "leitos obstétricos por 10 mil mulheres de 15 a 49 anos",
    fonte_dem = "SINASC (nascidos vivos em hospital, por município de residência da mãe, inclusive os nascidos em outros estados)",
    fonte_oferta = "CNES (leitos obstétricos existentes, SUS e não SUS, média mensal de 2025)",
    href = "parto.html", modulo = "7,25 leitos obstétricos (mediana das maternidades com 100 a 500 partos por ano em 2025)"),
  uti = list(
    nome = "UTI adulto", curto = "UTI adulto", servico = "leito SUS de UTI adulto", servico_pl = "leitos SUS de UTI adulto",
    tem_servico = "com UTI adulto SUS", pop = "adultos de 20 anos ou mais", unid = "internações com UTI adulto",
    unid1 = "internação", unid_obs = "internações com UTI adulto", paciente = "paciente", limiar = 120L,
    e2_unid = "leitos SUS de UTI adulto por 100 mil adultos",
    fonte_dem = "SIH/SUS (internações SUS com UTI adulto tipos I a III ou SRAG/COVID-19, por município de residência, inclusive as realizadas em outros estados)",
    fonte_oferta = "CNES (leitos SUS de UTI adulto, média mensal de 2025)",
    href = "uti-adulto.html", modulo = "10 leitos SUS de UTI adulto")
)

# Rótulos gerenciais dos modelos e cenários
ROT_L1 <- c(taxa_historica = "Taxa histórica do município", glm_poisson = "Regressão de Poisson",
            glm_nb = "Regressão binomial negativa", glm_poisson_tendencia = "Poisson com tendência linear",
            lightgbm_poisson = "LightGBM (árvores de decisão)")
ROT_L2 <- c(gravitacional_mnl = "Gravitacional (logit multinomial)", lightgbm_pares = "LightGBM nos pares origem–destino",
            pivo_mnl = "Pivô do gravitacional", pivo_lightgbm = "Pivô do LightGBM",
            persistencia_2023 = "Persistência (repete o ano anterior)", persistencia = "Persistência (repete o ano anterior)")
ROT_TIPO <- c(abertura = "Abertura", ampliacao = "Ampliação", reducao = "Redução", fechamento = "Fechamento", todos = "Todos os eventos")
ROT_VAR <- c("principal (media dos cenarios, ancorada)" = "principal (média dos dois cenários populacionais)",
             "cenario constante" = "cenário populacional constante", "cenario tendencia" = "cenário populacional de tendência",
             "limite inferior IC80 (municipal)" = "limite inferior do intervalo de 80%",
             "limite superior IC80 (municipal)" = "limite superior do intervalo de 80%",
             "calibrada ao IBGE" = "total calibrado à projeção do IBGE",
             "versao anterior sem ancoragem (v0)" = "versão anterior, sem ancoragem regional",
             "observada 2025" = "demanda observada em 2025")

rot_modelo_l4 <- function(modelo, limiar = NA) {
  ifelse(modelo == "p_mediana", "p-mediana",
  ifelse(modelo == "mclp", paste0("Cobertura máxima (", ifelse(is.na(limiar), "", paste0(num(limiar), " min")), ")"),
  ifelse(modelo == "uti_capacitado", "Com capacidade",
  ifelse(modelo == "uti_regional", "Regional (uma por região)",
  ifelse(modelo == "situacao_2025", "Situação de 2025", modelo)))))
}
rot_cenario <- function(cen) {
  k <- sub(".*_k(\\d)$", "\\1", cen)
  base <- sub("_k\\d$", "", cen)
  nm <- c(p_mediana = "p-mediana", mclp60 = "Cobertura máxima 60 min", mclp120 = "Cobertura máxima 120 min",
          uti_capacitado = "Com capacidade", uti_regional = "Regional")
  ifelse(cen == "referencia_2030", "Referência 2030 (sem unidade nova)",
         paste0(ifelse(base %in% names(nm), nm[base], base), ", k = ", k))
}

sem_mt <- function(x) sub(" - MT$", "", x)
pct_l  <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), "%"))
min_l  <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), " min"))
dec_l  <- function(x, d = 2) ifelse(is.na(x), "—", num(x, d))
# minutos com equivalente em horas a partir de 2 h (texto corrido)
tempo_l <- function(x) ifelse(is.na(x), "—", ifelse(x >= 120, sprintf("%s min (cerca de %s h)", num(x, 1), num(x / 60, 0)), paste0(num(x, 1), " min")))
# idem, para uso dentro de parênteses
tempo_l2 <- function(x) ifelse(is.na(x), "—", ifelse(x >= 120, sprintf("%s min, cerca de %s h", num(x, 1), num(x / 60, 0)), paste0(num(x, 1), " min")))
# Contagens modeladas: inteiro; de 1 a 4 aparecem como "< 5" (regra do site para contagens pequenas)
cont_l <- function(x) ifelse(is.na(x), "—", ifelse(x > 0 & x < 5, "< 5", num(round(x), 0)))
# zero negativo (-0,0) vira zero
sem_menos_zero <- function(x) { x[!is.na(x) & abs(x) < 1e-9] <- 0; x }
lista_e_l <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
sim_nao <- function(x) ifelse(is.na(x), "—", ifelse(x, "sim", "não"))
maiusc1 <- function(x) paste0(toupper(substr(x, 1, 1)), substr(x, 2, nchar(x)))
# primeira letra minúscula, exceto siglas (ex.: "Com capacidade" -> "com capacidade"; "MCLP" fica)
minusc1 <- function(x) ifelse(grepl("^[A-ZÀ-Ú][a-zà-ú]", x), paste0(tolower(substr(x, 1, 1)), substr(x, 2, nchar(x))), x)
nomes_lista <- function(x) ifelse(is.na(x) | !nzchar(x), "—", gsub(";\\s*", "; ", x))
# Municípios de uma solução que não estão na outra ("A; B; C" × "A; B; D" → "C")
dif_sol <- function(a, b) setdiff(trimws(strsplit(a, ";")[[1]]), trimws(strsplit(b, ";")[[1]]))
# Sigla com explicação ao passar o cursor (siglas fora do glossário geral do site)
sigla <- function(s, titulo) tags$abbr(title = titulo, tabindex = "0", s)

# ---- 1. Componentes gerais -------------------------------------------------------------------
css_loc <- function() tags$style(HTML("
body.fullcontent main.content { min-width: 0; }
.rolagem-x { max-width: 100%; overflow-x: auto; contain: inline-size; }
.rolagem-x .reactable { max-width: 100%; }
.loc-cadeia { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: .6rem; margin: .8rem 0 1.2rem; counter-reset: passo; }
.loc-passo { border: 1px solid #d9e4e4; border-radius: 8px; padding: .7rem .8rem; background: #fff; position: relative; }
.loc-passo .loc-cod { display: inline-block; font-weight: 700; color: #fff; background: #0E5A5E; border-radius: 4px; padding: 0 .4rem; font-size: .8rem; }
.loc-passo h4 { font-size: .98rem; margin: .35rem 0 .25rem; }
.loc-passo p { font-size: .84rem; color: #374151; margin: 0; }
.loc-passo .loc-ml { font-size: .76rem; color: #2E86AB; font-weight: 600; margin-top: .3rem; }
.vistas-mapa { display: flex; flex-wrap: wrap; gap: .35rem; margin: .4rem 0 .5rem; }
.vistas-mapa .btn { white-space: normal; text-align: left; }
.leg-mapa { display: flex; flex-wrap: wrap; gap: .3rem .9rem; font-size: .8rem; color: #374151; margin: .4rem 0 .2rem; }
.leg-mapa .leg-tit { flex-basis: 100%; font-weight: 600; }
.leg-mapa .leg-cx { display: inline-block; width: 14px; height: 14px; border: 1px solid #cbd5e1; margin-right: .3rem; vertical-align: -2px; }
.leg-mapa .leg-dest { display: inline-block; width: 14px; height: 14px; border: 2.5px solid #111827; margin-right: .3rem; vertical-align: -2px; }
.cenarios-lado { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; margin: .8rem 0 1.2rem; }
.cenarios-lado .bloco h4 { color: #0E5A5E; }
.cenarios-lado dl { display: grid; grid-template-columns: 1fr auto; gap: .15rem .8rem; margin: 0; font-size: .88rem; }
.cenarios-lado dt { font-weight: 400; color: #374151; }
.cenarios-lado dd { margin: 0; font-weight: 700; text-align: right; }
.tab-loc { width: 100%; border-collapse: collapse; font-size: .86rem; }
.tab-loc th, .tab-loc td { padding: .3rem .45rem; border-bottom: 1px solid #e5e7eb; vertical-align: top; }
.tab-loc th { font-weight: 600; color: #374151; background: #f6f9f9; text-align: left; }
.tab-loc td.num, .tab-loc th.num { text-align: right; white-space: nowrap; }
.tab-loc tr.destaque td { background: #e8f2f2; font-weight: 600; }
.selo-prov { display: inline-block; font-size: .72rem; font-weight: 700; letter-spacing: .04em; color: #7c4a03; background: #fdf1dc; border: 1px solid #f2d39b; border-radius: 4px; padding: 0 .35rem; vertical-align: 2px; }
.supr { color: #6b7280; font-style: italic; }
"))

selo_prov <- function(txt = "PROVISÓRIO") span(class = "selo-prov", txt)

faixa_loc <- function() faixa_construcao(paste0(
  "<b>Resultados preliminares</b> (versão de ", DATA_LOC, "), divulgados para discussão com a gestão do SUS. ",
  "A demanda de 2026–2030 usa uma projeção populacional municipal <b>provisória</b>; os cenários de localização de ",
  "serviços, para apoiar a discussão, dependem de parâmetros de pesquisa que <b>não são normas</b> e <b>não constituem recomendação oficial</b> ",
  "do projeto, da SES-MT ou dos municípios."))

nav_loc <- function(atual = "index.html") {
  pags <- c("index.html" = "Visão geral", "parto.html" = "Atenção ao parto", "uti-adulto.html" = "UTI adulto")
  tags$nav(class = "nav-mun", `aria-label` = "Páginas da seção Localização",
           lapply(names(pags), function(h) a(class = paste("btn btn-sm", if (h == atual) "btn-primary" else "btn-outline-primary"),
                                              href = h, `aria-current` = if (h == atual) "page" else NULL, pags[[h]])))
}

secoes_loc <- function(secoes) tags$nav(class = "nav-mun", `aria-label` = "Seções desta página",
  lapply(names(secoes), function(id) a(class = "btn btn-sm btn-outline-secondary", href = paste0("#", id), secoes[[id]])))

# Fonte curta para logo abaixo de gráficos e tabelas
fonte_curta <- function(piloto, extra = NULL) p(class = "nota-fonte", paste0(
  "Fonte: ", if (piloto == "parto") "SINASC" else "SIH/SUS", " 2020–2025, CNES 2025 e tempos rodoviários OSRM/OpenStreetMap (consulta de 08/10/2026)",
  if (!is.null(extra)) paste0("; ", extra) else "", ". Elaboração: Projeto PPSUS-MT."))

fonte_loc <- function(piloto = NULL, prefixo = "../", arquivos = TRUE) {
  pil <- if (is.null(piloto)) PIL else PIL[piloto]
  p(class = "nota-fonte",
    "Fontes: ", paste(vapply(pil, function(x) x$fonte_dem, ""), collapse = "; "), "; ",
    paste(vapply(pil, function(x) x$fonte_oferta, ""), collapse = "; "),
    "; população RIPSA/SVS 2025 e projeção do IBGE para Mato Grosso (Revisão 2024), base da projeção municipal provisória; ",
    "tempos rodoviários entre sedes municipais calculados com o OSRM sobre o OpenStreetMap (consulta de 08/10/2026; condições ideais de automóvel). ",
    "Elaboração: Projeto PPSUS-MT, frente de localização de serviços (cadeia L1–L5, ", DATA_LOC, "). ",
    if (arquivos) tagList("Arquivos em ", a(href = paste0(prefixo, "localizacao/index.html#arquivos"), "Localização: arquivos", .noWS = "after"),
                          "; definições gerais em ")
    else "Definições gerais em ", a(href = paste0(prefixo, "metodologia.html"), "Metodologia", .noWS = "after"), ".")
}

ARQ_LOC <- list(
  c("localizacao_acesso_municipios_2025.csv", "Acesso atual por município e piloto: tempo até o serviço, índice E2SFCA (60 e 120 min), demanda e deslocamento observados em 2024–2025, com supressão"),
  c("localizacao_acesso_regioes_2025.csv", "Acesso atual por região de saúde de residência e piloto"),
  c("localizacao_demanda_projetada_2026_2030.csv", "Demanda projetada 2026–2030 (PROVISÓRIA) para MT, regiões de saúde e municípios, com intervalo de 80%"),
  c("localizacao_otimizacao_solucoes_2030.csv", "Soluções da otimização para k = 0 a 5 unidades novas (p-mediana, cobertura máxima; UTI: com capacidade e regional), 2030"),
  c("localizacao_otimizacao_sensibilidade_2030.csv", "Sensibilidade das soluções (k = 1 a 3) a oito variantes de demanda: segunda melhor solução e quase-empates"),
  c("localizacao_cenarios_resumo_2030.csv", "Cenários de 2030 com a escolha do paciente: tempo médio esperado e ganhos"),
  c("localizacao_cenarios_ganho_municipios_2030.csv", "Ganho de tempo por município de residência em cada cenário de 2030"),
  c("localizacao_uti_leitos_regioes_2030.csv", "UTI adulto: necessidade empírica de leitos SUS por região de saúde (2030, PROVISÓRIA, e demanda observada de 2025)"),
  c("localizacao_validacao_demanda.csv", "Validação dos modelos de demanda (treino 2020–2023, teste 2024–2025)"),
  c("localizacao_validacao_escolha_temporal.csv", "Validação temporal dos modelos de escolha do paciente (teste 2024–2025)"),
  c("localizacao_validacao_escolha_experimentos.csv", "Validação por experimento natural (aberturas, fechamentos e mudanças de leitos, 2021–2025), por tipo de evento"),
  c("localizacao_validacao_escolha_experimentos_ano.csv", "Validação por experimento natural, por ano do evento"),
  c("localizacao_dicionario.csv", "Dicionário das colunas de todos os arquivos acima"))

lista_arquivos_loc <- function(prefixo = "../") {
  tags$ul(lapply(ARQ_LOC, function(x) {
    f <- file.path(RAIZ, "arquivos", "dados", x[1])
    tam <- if (file.exists(f)) paste0(" (", num(file.size(f) / 1024, 0), " KB)") else ""
    tags$li(a(href = paste0(prefixo, "arquivos/dados/", x[1]), x[1]), tam, " — ", x[2])
  }))
}

# KPIs de acesso de um piloto (agregados de acesso_regiao.csv; tempo ponderado pelos atendidos em MT)
resumo_acesso <- function(piloto) {
  r <- LREG[LREG$piloto == piloto, ]; a <- LACE[LACE$piloto == piloto, ]; m <- LREG_MT[LREG_MT$piloto == piloto, ]
  if (!nrow(r) || nrow(m) != 1) return(NULL)
  # totais do estado: linha de Mato Grosso de acesso_regiao.csv (calculada das contagens, antes da supressão regional)
  list(
    n_mun_serv = sum(r$municipios_com_servico), leitos = sum(r$leitos_servico_2025), pop = sum(r$pop_alvo),
    pop60 = 100 * sum(a$pop_alvo[a$tempo_servico_min <= 60]) / sum(a$pop_alvo),
    pop120 = 100 * sum(a$pop_alvo[a$tempo_servico_min <= 120]) / sum(a$pop_alvo),
    sem60 = sum(a$indice_60 == 0), sem120 = sum(a$indice_120 == 0),
    baixo = sum(a[[paste0("indice_", PIL[[piloto]]$limiar)]] < 0.5),
    n = m$n_2024_2025, n_mt = m$n_em_mt,
    tempo = m$tempo_medio_obs_min, km = m$km_medio_obs,
    proprio = m$pct_proprio_mun, fora_reg = m$pct_fora_regiao, fora_mt = m$pct_fora_mt,
    tempo_serv_mediana = stats::median(a$tempo_servico_min))
}

proj_mt <- function(piloto, ano) LPROJ[LPROJ$piloto == piloto & LPROJ$nivel == "MT" & LPROJ$ano == ano, ][1, ]

kpis_acesso <- function(piloto) {
  s <- resumo_acesso(piloto); info <- PIL[[piloto]]
  if (is.null(s)) return(p(class = "nota-fonte", "Dados de acesso não carregados."))
  pr <- proj_mt(piloto, 2030L)
  div(class = "kpi-grade",
    kpi_simples(paste0("Municípios ", info$tem_servico), num(s$n_mun_serv), paste0("de 142 · CNES, média de ", ANO_OFERTA),
                sprintf("%s %s no estado", num(s$leitos, 0), info$servico_pl)),
    kpi_simples(paste0("População-alvo a até 60 min do serviço"), pct_l(s$pop60), paste0(info$pop, " · ", ANO_OFERTA),
                sprintf("%s a até 120 min (tempo rodoviário entre sedes)", pct_l(s$pop120))),
    kpi_simples("Tempo médio percorrido", min_l(s$tempo), paste0("sede a sede, atendidos em MT · 2024–2025"),
                sprintf("%s no próprio município · %s fora da região de saúde", pct_l(s$proprio), pct_l(s$fora_reg))),
    kpi_simples("Atendidos em outros estados", pct_l(s$fora_mt), paste0("da demanda dos residentes · 2024–2025"),
                sprintf("%s %s em 2024–2025", num(s$n), info$unid_obs)),
    kpi_simples(tagList("Demanda projetada para 2030 ", selo_prov()), num(pr$demanda_proj),
                paste0(info$unid, " de residentes de MT"),
                sprintf("intervalo de 80%%: %s a %s", num(pr$li80), num(pr$ls80))))
}

# ---- 2. Acesso atual ----------------------------------------------------------------------------
CORES_TEMPO <- c("#D6E7E6", "#C6DCEA", "#8BB6D2", "#4D8CB4", "#245F86", "#0B3954")
ROT_TEMPO <- c("0 min (no próprio município)", "até 30 min", "mais de 30 a 60 min", "mais de 60 a 120 min",
               "mais de 120 a 240 min", "mais de 240 min")
CORES_IND <- c("#F3EADD", "#DCEBEA", "#A9CFCC", "#6AA6A6", "#2F7A7D", "#0E4F52")
CORES_GANHO <- c("#E6D3BD", "#F3F4F6", "#D7E8E7", "#9CC7C5", "#4E8F92", "#0E5A5E")
COR_SEM <- "#E5E7EB"

classe_tempo <- function(x) ifelse(is.na(x), NA_integer_, as.integer(cut(x, c(-Inf, 0, 30, 60, 120, 240, Inf), right = TRUE)))
classe_ind <- function(x) ifelse(is.na(x), NA_integer_, ifelse(x == 0, 1L, 1L + findInterval(x, c(0, 0.5, 0.8, 1.2, 2))))
classe_ganho <- function(x) ifelse(is.na(x), NA_integer_, as.integer(cut(x, c(-Inf, -1, 1, 10, 60, 240, Inf), right = FALSE)))

cor_de <- function(cl, paleta) ifelse(is.na(cl), COR_SEM, paleta[cl])

leg_html <- function(titulo, cores, rotulos, extra = NULL, destaque = NULL) {
  tagList(span(class = "leg-tit", titulo),
          lapply(seq_along(cores), function(k) span(span(class = "leg-cx", style = paste0("background:", cores[k])), rotulos[k])),
          if (!is.null(extra)) span(span(class = "leg-cx", style = paste0("background:", COR_SEM)), extra),
          if (!is.null(destaque)) span(span(class = "leg-dest"), destaque))
}

JS_MAPA_LOC <- "function(el, x, data) {
  var map = this, camadas = {}, atual = 0;
  map.eachLayer(function(l) { if (l.options && l.options.layerId) camadas[l.options.layerId] = l; });
  function eDest(k) { var d = data.vistas[atual].destaque || []; return d.indexOf(k) >= 0; }
  function estilo(k, hover) { var d = eDest(k);
    return {fillColor: data.vistas[atual].cores[k] || '#E5E7EB', color: d ? '#111827' : '#ffffff', weight: d ? 3 : (hover ? 2.5 : 1)}; }
  Object.keys(camadas).forEach(function(k) { var l = camadas[k];
    l.on('mouseover', function() { l.setStyle(estilo(k, true)); });
    l.on('mouseout', function() { l.setStyle(estilo(k, false)); }); });
  var botoes = document.querySelectorAll('[data-mapa=\"' + data.id + '\"]');
  function mostra(i) { atual = i;
    Object.keys(camadas).forEach(function(k) { camadas[k].setStyle(estilo(k, false)); if (eDest(k)) camadas[k].bringToFront(); });
    botoes.forEach(function(b) { var on = +b.getAttribute('data-vista') === i; b.classList.toggle('active', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); });
    document.querySelectorAll('[data-legenda=\"' + data.id + '\"]').forEach(function(d) { d.style.display = (+d.getAttribute('data-vista') === i) ? '' : 'none'; });
  }
  botoes.forEach(function(b) { b.addEventListener('click', function() { mostra(+b.getAttribute('data-vista')); }); });
}"

# Ganho por paciente (min) de um cenário, por município (vetor nomeado por cod_mun6)
ganho_cenario <- function(piloto, cenario) {
  g <- LGAN[LGAN$piloto == piloto & LGAN$cenario == cenario, ]
  setNames(sem_menos_zero(g$ganho_min_por_paciente), g$cod_mun6)
}
abertos_cenario <- function(piloto, cenario) {
  x <- LCEN$abertos[LCEN$piloto == piloto & LCEN$cenario == cenario]
  if (!length(x) || is.na(x[1])) character(0) else strsplit(x[1], ";")[[1]]
}
nomes_cenario <- function(piloto, cenario) {
  x <- LCEN$nomes_abertos[LCEN$piloto == piloto & LCEN$cenario == cenario]
  if (!length(x) || is.na(x[1])) "—" else nomes_lista(x[1])
}

# Texto da célula percentual: valor, "suprimido" (linha com supressão) ou "—"
pct_celula <- function(v, supr, n) ifelse(!is.na(v), pct_l(v), ifelse(!is.na(n) & n == 0, "—", ifelse(supr, "suprimido", "—")))

mapa_loc <- function(piloto, cenarios = "p_mediana_k3", altura = 520) {
  if (nrow(GEO) == 0 || nrow(LACE) == 0) return(sem_mapa())
  info <- PIL[[piloto]]; lim <- info$limiar
  a <- LACE[LACE$piloto == piloto, ]
  g <- GEO
  i <- match(g$cod_mun6, a$cod_mun6)
  x <- a[i, ]
  id <- paste0("mapa-loc-", piloto)
  vistas <- list(
    list(rot = "Tempo até o serviço mais próximo (2025)", cores = cor_de(classe_tempo(x$tempo_servico_min), CORES_TEMPO),
         leg = leg_html(sprintf("Tempo rodoviário da sede ao município mais próximo %s (%d)", info$tem_servico, ANO_OFERTA), CORES_TEMPO, ROT_TEMPO)),
    list(rot = sprintf("Índice de acesso E2SFCA, %d min (2025)", lim),
         cores = cor_de(classe_ind(x[[paste0("indice_", lim)]]), CORES_IND),
         leg = leg_html(sprintf("Índice de acesso E2SFCA com limiar de %d min (média de MT = 1)", lim), CORES_IND,
                        c(sprintf("0 (nenhum leito a até %d min)", lim), "abaixo de 0,5", "0,5 a menos de 0,8", "0,8 a menos de 1,2", "1,2 a menos de 2", "2 ou mais"))),
    list(rot = "Tempo médio percorrido (2024–2025)", cores = cor_de(classe_tempo(x$tempo_medio_obs_min), CORES_TEMPO),
         leg = leg_html("Tempo médio sede a sede percorrido pelos residentes atendidos em MT (2024–2025)", CORES_TEMPO, ROT_TEMPO,
                        extra = "sem dado (ninguém atendido em MT ou demanda menor que 5)")))
  for (cen in cenarios) {
    gv <- ganho_cenario(piloto, cen)[as.character(g$cod_mun6)]
    ab <- abertos_cenario(piloto, cen)
    vistas[[length(vistas) + 1]] <- list(
      rot = paste0("Cenário 2030: ", minusc1(rot_cenario(cen))), cores = cor_de(classe_ganho(gv), CORES_GANHO), destaque = ab,
      leg = leg_html(sprintf("Minutos poupados por %s em 2030, cenário %s (PROVISÓRIO; escolha do paciente pelo modelo pivô)", info$paciente, minusc1(rot_cenario(cen))),
                     CORES_GANHO, c("tempo aumenta mais de 1 min", "variação de até 1 min", "1 a menos de 10 min", "10 a menos de 60 min",
                                    "60 a menos de 240 min", "240 min ou mais"),
                     destaque = paste0("município com unidade nova no cenário (", nomes_cenario(piloto, cen), ")")))
  }
  # Dica única com todas as medidas do município
  gan <- lapply(cenarios, function(cen) ganho_cenario(piloto, cen)[as.character(g$cod_mun6)])
  rot <- vapply(seq_len(nrow(g)), function(j) {
    r <- x[j, ]
    if (is.na(r$cod_mun6)) return(esc(g$municipio[j]))
    linhas <- c(
      sprintf("<b>%s</b> · %s", esc(r$nome_municipio), esc(sem_mt(r$nome_regsaud))),
      if (r$leitos_proprios > 0) sprintf("%s no município: %s (média de %d)", esc(info$servico_pl), num(r$leitos_proprios, 1), ANO_OFERTA)
      else sprintf("Sem %s no município em %d", esc(info$servico), ANO_OFERTA),
      sprintf("Tempo até o serviço mais próximo: %s (%s km)", min_l(r$tempo_servico_min), num(r$km_servico, 0)),
      sprintf("Índice de acesso E2SFCA: %s (60 min) · %s (120 min)", dec_l(r$indice_60), dec_l(r$indice_120)),
      if (r$n_2024_2025 > 0) sprintf("Demanda 2024–2025: %s %s · tempo médio percorrido: %s", num(r$n_2024_2025), esc(info$unid_obs), min_l(r$tempo_medio_obs_min))
      else sprintf("Sem %s registrados em 2024–2025", esc(info$unid_obs)),
      if (r$n_2024_2025 > 0) sprintf("Atendidos no próprio município: %s · fora da região: %s · fora de MT: %s",
                                     pct_celula(r$pct_proprio_mun, r$suprimido, r$n_2024_2025), pct_celula(r$pct_fora_regiao, r$suprimido, r$n_2024_2025),
                                     pct_celula(r$pct_fora_mt, r$suprimido, r$n_2024_2025)),
      unlist(lapply(seq_along(cenarios), function(k) { v <- gan[[k]][j]
        if (is.na(v)) NULL else sprintf("Cenário %s (2030): %s", esc(minusc1(rot_cenario(cenarios[k]))),
          if (abs(v) < 1) "diferença menor que 1 min" else if (v > 0) sprintf("poupa %s por %s", min_l(v), info$paciente)
          else sprintf("tempo aumenta %s por %s", min_l(-v), info$paciente)) })))
    paste(linhas, collapse = "<br>")
  }, character(1))
  bb <- bbox_num(g)
  dados_js <- list(id = id, vistas = lapply(vistas, function(v)
    list(cores = as.list(setNames(v$cores, as.character(g$cod_mun6))), destaque = I(as.character(if (is.null(v$destaque)) character(0) else v$destaque)))))
  m <- mapa_vazio(altura) |>
    addPolygons(data = g, layerId = ~as.character(cod_mun6), fillColor = vistas[[1]]$cores, fillOpacity = 0.95,
                color = "#ffffff", weight = 1, opacity = 1, label = lapply(rot, HTML),
                labelOptions = labelOptions(direction = "auto", style = list("max-width" = "300px", "white-space" = "normal"))) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
    htmlwidgets::onRender(JS_MAPA_LOC, data = dados_js)
  tagList(
    div(class = "vistas-mapa", role = "group", `aria-label` = "O que o mapa mostra",
        lapply(seq_along(vistas), function(k) tags$button(type = "button", class = paste("btn btn-sm btn-outline-primary", if (k == 1) "active"),
                                                          `data-mapa` = id, `data-vista` = k - 1, `aria-pressed` = if (k == 1) "true" else "false", vistas[[k]]$rot))),
    m,
    lapply(seq_along(vistas), function(k) div(class = "leg-mapa", `data-legenda` = id, `data-vista` = k - 1,
                                              style = if (k > 1) "display:none" else NULL, vistas[[k]]$leg)),
    p(class = "nota-fonte", "Passe o cursor (ou toque) sobre um município para ver todas as medidas. ",
      "Boa Esperança do Norte (instalado em 2025) não tem polígono na malha do IBGE usada no mapa; aparece nas tabelas."))
}

# Tabela por região de saúde (acesso atual)
tabela_acesso_regioes <- function(piloto) {
  info <- PIL[[piloto]]; lim <- info$limiar
  r <- LREG[LREG$piloto == piloto, ]
  sem_serv <- is.na(r$pct_proprio_mun) & r$municipios_com_servico == 0
  d <- tibble::tibble(
    `Região de saúde` = sem_mt(r$nome_regsaud), pop = r$pop_alvo, leitos = r$leitos_servico_2025, nmun = r$municipios_com_servico,
    i60 = r$indice_60, p60 = r$pct_pop_ate_60min, i120 = r$indice_120, p120 = r$pct_pop_ate_120min,
    n = r$n_2024_2025, tempo = r$tempo_medio_obs_min,
    proprio = ifelse(sem_serv, "— (região sem o serviço)", pct_l(r$pct_proprio_mun)), fora_reg = r$pct_fora_regiao, fora_mt = r$pct_fora_mt) |>
    arrange(desc(tempo))
  f1 <- function(v) num(v, 1); f2 <- function(v) dec_l(v, 2); fp <- function(v) pct_l(v)
  # fora da região e fora de MT vazios = supressão regional (contagem de 1 a 4 ou complementar); nunca recalculados
  fs <- function(v) if (is.na(v)) span(class = "supr", "suprimido") else pct_l(v)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, defaultSorted = list(tempo = "desc"),
    columns = list(
      `Região de saúde` = colDef(minWidth = 150, sticky = "left"),
      pop = colDef(name = paste0("População-alvo (", ANO_OFERTA, ")"), align = "right", minWidth = 105, cell = function(v) num(v)),
      leitos = colDef(name = paste0("Leitos (", ANO_OFERTA, ")"), align = "right", minWidth = 80, cell = f1),
      nmun = colDef(name = "Municípios com o serviço", align = "right", minWidth = 95),
      i60 = colDef(name = "Índice E2SFCA 60 min", align = "right", minWidth = 90, cell = f2),
      p60 = colDef(name = "% a até 60 min", align = "right", minWidth = 80, cell = fp),
      i120 = colDef(name = "Índice E2SFCA 120 min", align = "right", minWidth = 90, cell = f2),
      p120 = colDef(name = "% a até 120 min", align = "right", minWidth = 80, cell = fp),
      n = colDef(name = paste0("Demanda 2024–2025 (", info$unid_obs, ")"), align = "right", minWidth = 120, cell = function(v) num(v)),
      tempo = colDef(name = "Tempo médio percorrido (min)", align = "right", minWidth = 100, cell = f1),
      proprio = colDef(name = "% no próprio município", align = "right", minWidth = 95),
      fora_reg = colDef(name = "% fora da região", align = "right", minWidth = 80, cell = fs),
      fora_mt = colDef(name = "% fora de MT", align = "right", minWidth = 75, cell = fs))))
}

# Tabela por município (acesso atual), com busca
tabela_acesso_municipios <- function(piloto) {
  info <- PIL[[piloto]]; lim <- info$limiar
  a <- LACE[LACE$piloto == piloto, ] |> arrange(desc(tempo_servico_min))
  d <- tibble::tibble(
    `Município` = a$nome_municipio, `Região` = sem_mt(a$nome_regsaud), leitos = a$leitos_proprios,
    tserv = a$tempo_servico_min, i60 = a$indice_60, i120 = a$indice_120, n = a$n_2024_2025, tobs = a$tempo_medio_obs_min,
    proprio = pct_celula(a$pct_proprio_mun, a$suprimido, a$n_2024_2025),
    fora_reg = pct_celula(a$pct_fora_regiao, a$suprimido, a$n_2024_2025),
    fora_mt = pct_celula(a$pct_fora_mt, a$suprimido, a$n_2024_2025))
  cel_txt <- function(v) if (identical(v, "suprimido")) span(class = "supr", v) else v
  div(class = "rolagem-x", reactable(d, searchable = TRUE, compact = TRUE, striped = TRUE, highlight = TRUE, defaultPageSize = 15,
    showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, 142),
    columns = list(
      `Município` = colDef(minWidth = 150, sticky = "left"),
      `Região` = colDef(minWidth = 130),
      leitos = colDef(name = paste0(maiusc1(info$servico_pl), " (", ANO_OFERTA, ")"), align = "right", minWidth = 90, cell = function(v) num(v, 1)),
      tserv = colDef(name = "Tempo até o serviço (min)", align = "right", minWidth = 90, cell = function(v) num(v, 1)),
      i60 = colDef(name = "Índice 60 min", align = "right", minWidth = 75, cell = function(v) dec_l(v)),
      i120 = colDef(name = "Índice 120 min", align = "right", minWidth = 75, cell = function(v) dec_l(v)),
      n = colDef(name = paste0("Demanda 2024–2025"), align = "right", minWidth = 90, cell = function(v) num(v)),
      tobs = colDef(name = "Tempo médio percorrido (min)", align = "right", minWidth = 100, cell = function(v) if (is.na(v)) "—" else num(v, 1)),
      proprio = colDef(name = "% no próprio município", align = "right", minWidth = 95, sortable = FALSE, cell = cel_txt),
      fora_reg = colDef(name = "% fora da região", align = "right", minWidth = 85, sortable = FALSE, cell = cel_txt),
      fora_mt = colDef(name = "% fora de MT", align = "right", minWidth = 80, sortable = FALSE, cell = cel_txt))))
}

n_suprimidos <- function(piloto) {
  a <- LACE[LACE$piloto == piloto & LACE$n_2024_2025 > 0, ]
  sum(is.na(a$pct_proprio_mun)) + sum(is.na(a$pct_fora_regiao)) + sum(is.na(a$pct_fora_mt))
}

# ---- 3. Demanda projetada --------------------------------------------------------------------
svg_projecao <- function(piloto, w = 680, h = 280) {
  info <- PIL[[piloto]]
  d <- LPROJ[LPROJ$piloto == piloto & LPROJ$nivel == "MT", ] |> arrange(ano)
  if (nrow(d) < 2) return("")
  calib <- piloto == "parto"
  ys <- c(d$li80, d$ls80, if (calib) d$demanda_proj_calib_ibge)
  pl <- 70; pr <- 16; pt <- 14; pb <- 28
  yt <- pretty(c(min(ys) * 0.97, max(ys)), n = 5); yr <- range(yt)
  sx <- function(x) pl + (x - 2026) / 4 * (w - pl - pr)
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="11" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, fmt_eixo(yt)), collapse = "")
  eixo <- paste(sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%d</text>', sx(d$ano), h - 8, d$ano), collapse = "")
  faixa <- sprintf('<polygon points="%s" fill="%s" fill-opacity="0.28" stroke="none"><title>Intervalo de 80%%</title></polygon>',
                   paste(c(sprintf("%.1f,%.1f", sx(d$ano), sy(d$ls80)), rev(sprintf("%.1f,%.1f", sx(d$ano), sy(d$li80)))), collapse = " "), COR[["sec"]])
  linha <- sprintf('<polyline fill="none" stroke="%s" stroke-width="3" points="%s"/>', COR[["mun"]], paste(sprintf("%.1f,%.1f", sx(d$ano), sy(d$demanda_proj)), collapse = " "))
  pts <- paste(sprintf('<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="transparent" stroke-width="10" data-tip="%d: %s %s (intervalo de 80%%: %s a %s)"/>',
                       sx(d$ano), sy(d$demanda_proj), COR[["mun"]], d$ano, num(d$demanda_proj), esc(info$unid), num(d$li80), num(d$ls80)), collapse = "")
  cal <- if (calib) paste0(sprintf('<polyline fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6,4" points="%s"/>', COR[["neutro"]],
                                   paste(sprintf("%.1f,%.1f", sx(d$ano), sy(d$demanda_proj_calib_ibge)), collapse = " ")),
                           paste(sprintf('<circle cx="%.1f" cy="%.1f" r="3" fill="%s" stroke="transparent" stroke-width="10" data-tip="%d, calibrada ao IBGE: %s %s"/>',
                                         sx(d$ano), sy(d$demanda_proj_calib_ibge), COR[["neutro"]], d$ano, num(d$demanda_proj_calib_ibge), esc(info$unid)), collapse = "")) else ""
  tit <- sprintf("%s: demanda projetada de residentes de Mato Grosso, 2026–2030 (provisória), com intervalo de 80%%", info$nome)
  leg <- paste0('<span class="leg-item"><svg width="22" height="8" aria-hidden="true"><line x1="0" x2="22" y1="4" y2="4" stroke="', COR[["mun"]], '" stroke-width="3"/></svg>Projeção (média dos dois cenários populacionais)</span>',
                '<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="', COR[["sec"]], '" fill-opacity="0.28"/></svg>Intervalo de 80%</span>',
                if (calib) paste0('<span class="leg-item"><svg width="22" height="8" aria-hidden="true"><line x1="0" x2="22" y1="4" y2="4" stroke="', COR[["neutro"]], '" stroke-width="2" stroke-dasharray="6,4"/></svg>Total calibrado à projeção do IBGE (queda da fecundidade)</span>') else "")
  HTML(sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s%s%s%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
               w, h, esc(tit), esc(tit), grade, eixo, faixa, cal, linha, pts, leg))
}

tabela_projecao_regioes <- function(piloto) {
  info <- PIL[[piloto]]
  p <- LPROJ[LPROJ$piloto == piloto & LPROJ$nivel == "regiao", ]
  a26 <- p[p$ano == 2026, ]; a30 <- p[p$ano == 2030, ]
  d <- a30 |> transmute(codigo, `Região de saúde` = sem_mt(nome), d30 = demanda_proj, ic = paste0(num(li80), " a ", num(ls80)), calib = demanda_proj_calib_ibge) |>
    left_join(a26 |> transmute(codigo, d26 = demanda_proj), by = "codigo") |>
    mutate(var = 100 * (d30 / d26 - 1)) |> arrange(desc(d30)) |> select(`Região de saúde`, d26, d30, ic, var, calib)
  cols <- list(
    `Região de saúde` = colDef(minWidth = 160, sticky = "left"),
    d26 = colDef(name = "2026", align = "right", minWidth = 70, cell = function(v) num(v)),
    d30 = colDef(name = "2030", align = "right", minWidth = 70, cell = function(v) num(v)),
    ic = colDef(name = "Intervalo de 80% (2030)", align = "right", minWidth = 120, sortable = FALSE),
    var = colDef(name = "Variação 2026–2030", align = "right", minWidth = 90, cell = function(v) paste0(if (v >= 0) "+" else "−", num(abs(v), 1), "%")),
    calib = colDef(name = "2030 calibrada ao IBGE", align = "right", minWidth = 100, cell = function(v) num(v)))
  if (piloto != "parto") { d$calib <- NULL; cols$calib <- NULL }
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, columns = cols))
}

tabela_projecao_municipios <- function(piloto) {
  p <- LPROJ[LPROJ$piloto == piloto & LPROJ$nivel == "municipio", ]
  p$codigo <- as.integer(p$codigo)
  a26 <- p[p$ano == 2026, ]; a30 <- p[p$ano == 2030, ]
  reg <- LACE[LACE$piloto == piloto, c("cod_mun6", "nome_regsaud")]
  d <- a30 |> transmute(codigo, `Município` = nome, d30 = demanda_proj, ic = paste0(cont_l(li80), " a ", cont_l(ls80))) |>
    left_join(a26 |> transmute(codigo, d26 = demanda_proj), by = "codigo") |>
    left_join(reg, by = c("codigo" = "cod_mun6")) |>
    transmute(`Município`, `Região` = sem_mt(nome_regsaud), d26, d30, ic) |> arrange(desc(d30))
  # nenhuma projeção municipal fica entre 1 e 4 (conferido no script 11); o limite inferior pode ficar e aparece como "< 5"
  div(class = "rolagem-x", reactable(d, searchable = TRUE, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, 142),
    columns = list(`Município` = colDef(minWidth = 150, sticky = "left"), `Região` = colDef(minWidth = 130),
                   d26 = colDef(name = "2026", align = "right", minWidth = 70, cell = function(v) cont_l(v)),
                   d30 = colDef(name = "2030", align = "right", minWidth = 70, cell = function(v) cont_l(v)),
                   ic = colDef(name = "Intervalo de 80% (2030)", align = "right", minWidth = 120, sortable = FALSE))))
}

# ---- 4. Validação dos modelos -----------------------------------------------------------------
modelo_l1 <- function(piloto) { m <- unique(LPROJ$modelo[LPROJ$piloto == piloto]); if (length(m)) m[1] else NA_character_ }

tabela_valid_demanda <- function(piloto) {
  v <- LV1[LV1$piloto == piloto, ]
  base <- sub("_ancorado$", "", v$modelo)
  esc_m <- modelo_l1(piloto)
  d <- tibble::tibble(base = unique(base)) |>
    mutate(Modelo = unname(ROT_L1[base]),
           w0 = v$wmape[match(base, v$modelo)] * 100, w1 = v$wmape[match(paste0(base, "_ancorado"), v$modelo)] * 100,
           wr1 = v$wmape_regiao[match(paste0(base, "_ancorado"), v$modelo)] * 100,
           et1 = v$erro_total_pct[match(paste0(base, "_ancorado"), v$modelo)],
           escolhido = paste0(base, "_ancorado") == esc_m)
  linhas <- lapply(seq_len(nrow(d)), function(i) tags$tr(class = if (d$escolhido[i]) "destaque",
    tags$td(d$Modelo[i], if (d$escolhido[i]) tagList(" ", span(class = "sit sit-neutra", "escolhido"))),
    tags$td(class = "num", pct_l(d$w0[i])), tags$td(class = "num", pct_l(d$w1[i])), tags$td(class = "num", pct_l(d$wr1[i])),
    tags$td(class = "num", paste0(if (d$et1[i] >= 0) "+" else "−", num(abs(d$et1[i]), 1), "%"))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "Erro médio por município (WMAPE): soma dos erros absolutos dividida pela soma observada; treino 2020–2023, teste 2024–2025."),
    tags$thead(tags$tr(tags$th("Modelo"), tags$th(class = "num", "Erro por município"), tags$th(class = "num", "Erro por município, ancorado"),
                       tags$th(class = "num", "Erro por região, ancorado"), tags$th(class = "num", "Erro do total de MT, ancorado"))),
    tags$tbody(linhas)))
}

tabela_valid_escolha <- function(piloto) {
  v <- LV2[LV2$piloto == piloto, ]
  ordem <- c("persistencia_2023", "pivo_mnl", "pivo_lightgbm", "lightgbm_pares", "gravitacional_mnl")
  v <- v[order(match(v$modelo, ordem)), ]
  linhas <- lapply(seq_len(nrow(v)), function(i) tags$tr(class = if (v$modelo[i] == "pivo_mnl") "destaque",
    tags$td(unname(ROT_L2[v$modelo[i]]), if (v$modelo[i] == "pivo_mnl") tagList(" ", span(class = "sit sit-neutra", "usado nos cenários"))),
    tags$td(class = "num", num(v$cpc[i], 3)), tags$td(class = "num", pct_l(100 * v$acerto_principal_destino[i])),
    tags$td(class = "num", paste0(num(v$tempo_medio_prev[i], 1), " (obs. ", num(v$tempo_medio_obs[i], 1), ")"))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "CPC: parte comum entre fluxos previstos e observados (1 = previsão perfeita). Treino 2020–2023, teste 2024–2025, sem mudança de oferta além da observada."),
    tags$thead(tags$tr(tags$th("Modelo"), tags$th(class = "num", "CPC"), tags$th(class = "num", "Acerto do destino principal"),
                       tags$th(class = "num", "Tempo médio previsto (min)"))),
    tags$tbody(linhas)))
}

exp_todos <- function(piloto) LV3[LV3$piloto == piloto & LV3$tipo == "todos", ][1, ]

# Halteres: CPC do pivô × persistência por tipo de evento
svg_experimentos <- function(piloto, w = 680) {
  e <- LV3[LV3$piloto == piloto, ]
  e <- e[order(match(e$tipo, c("abertura", "ampliacao", "reducao", "fechamento", "todos"))), ]
  n <- nrow(e); if (!n) return("")
  lh <- 34; pl <- 190; pr <- 30; h <- n * lh + 40
  vals <- c(e$cpc_medio_pivo_mnl, e$cpc_medio_persistencia)
  lim <- c(floor(min(vals) * 20) / 20, 1)
  sx <- function(v) pl + (v - lim[1]) / diff(lim) * (w - pl - pr)
  xt <- seq(lim[1], 1, by = 0.05)
  grade <- paste(sprintf('<line x1="%.1f" x2="%.1f" y1="0" y2="%d" stroke="#eef0f4"/><text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%s</text>',
                         sx(xt), sx(xt), n * lh, sx(xt), n * lh + 16, num(xt, 2)), collapse = "")
  y <- (seq_len(n) - 0.5) * lh
  rot <- sprintf("%s (%s eventos)", ROT_TIPO[e$tipo], num(e$n_avaliaveis))
  itens <- paste(sprintf(paste0('<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937"%s>%s</text>',
                                '<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="#9ca3af" stroke-width="2"/>',
                                '<circle cx="%.1f" cy="%.1f" r="6" fill="%s" data-tip="%s · pivô do gravitacional: CPC %s"/>',
                                '<rect x="%.1f" y="%.1f" width="11" height="11" fill="%s" data-tip="%s · persistência: CPC %s"/>'),
                         pl - 8, y + 4, ifelse(e$tipo == "todos", ' font-weight="700"', ""), esc(rot),
                         sx(e$cpc_medio_pivo_mnl), sx(e$cpc_medio_persistencia), y, y,
                         sx(e$cpc_medio_pivo_mnl), y, COR[["mun"]], esc(ROT_TIPO[e$tipo]), num(e$cpc_medio_pivo_mnl, 3),
                         sx(e$cpc_medio_persistencia) - 5.5, y - 5.5, COR[["sec"]], esc(ROT_TIPO[e$tipo]), num(e$cpc_medio_persistencia, 3)), collapse = "")
  tit <- sprintf("%s: CPC médio nas origens afetadas por abertura, ampliação, redução ou fechamento de leitos (2021–2025), modelo pivô × persistência", PIL[[piloto]]$nome)
  leg <- paste0('<span class="leg-item"><svg width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="5" fill="', COR[["mun"]], '"/></svg>Pivô do gravitacional (usado nos cenários)</span>',
                '<span class="leg-item"><svg width="12" height="12" aria-hidden="true"><rect width="11" height="11" fill="', COR[["sec"]], '"/></svg>Persistência (repete o ano anterior)</span>',
                '<span class="leg-item">mais à direita = previsão mais próxima do observado</span>')
  HTML(sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
               w, h, esc(tit), esc(tit), grade, itens, leg))
}

tabela_experimentos <- function(piloto) {
  e <- LV3[LV3$piloto == piloto, ]
  e <- e[order(match(e$tipo, c("abertura", "ampliacao", "reducao", "fechamento", "todos"))), ]
  linhas <- lapply(seq_len(nrow(e)), function(i) tags$tr(class = if (e$tipo[i] == "todos") "destaque",
    tags$td(ROT_TIPO[[e$tipo[i]]]), tags$td(class = "num", num(e$n_avaliaveis[i])),
    tags$td(class = "num", num(e$cpc_medio_gravitacional_mnl[i], 3)), tags$td(class = "num", num(e$cpc_medio_lightgbm_pares[i], 3)),
    tags$td(class = "num", num(e$cpc_medio_pivo_lightgbm[i], 3)), tags$td(class = "num", tags$b(num(e$cpc_medio_pivo_mnl[i], 3))),
    tags$td(class = "num", tags$b(num(e$cpc_medio_persistencia[i], 3))),
    tags$td(class = "num", sprintf("%s / %s / %s", num(e$n_pivo_mnl_vence_margem[i]), num(e$n_pivo_mnl_empata_margem[i]), num(e$n_pivo_mnl_perde_margem[i])))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "CPC médio nas origens afetadas. Vence / empata / perde: eventos (mudanças de oferta de leitos no CNES, não pacientes) em que o pivô do gravitacional supera a persistência por 0,005 de CPC ou mais, fica a menos de 0,005 ou perde por 0,005 ou mais."),
    tags$thead(tags$tr(tags$th("Tipo de evento"), tags$th(class = "num", "Eventos avaliáveis"), tags$th(class = "num", "Gravitacional"),
                       tags$th(class = "num", "LightGBM nos pares"), tags$th(class = "num", "Pivô do LightGBM"), tags$th(class = "num", "Pivô do gravitacional"),
                       tags$th(class = "num", "Persistência"), tags$th(class = "num", "Pivô: vence / empata / perde"))),
    tags$tbody(linhas)))
}

tabela_experimentos_ano <- function(piloto) {
  e <- LV4[LV4$piloto == piloto, ] |> arrange(ano_evento)
  tipos <- function(x) { x <- gsub("ampliacao", "ampliação", gsub("reducao", "redução", x)); x }
  anos <- function(x) { p <- strsplit(x, "-")[[1]]; if (length(p) == 2 && p[1] == p[2]) p[1] else gsub("-", "–", x) }
  linhas <- lapply(seq_len(nrow(e)), function(i) tags$tr(
    tags$td(e$ano_evento[i]), tags$td(anos(e$anos_ajuste[i])), tags$td(anos(e$anos_teste[i])), tags$td(tipos(e$tipos[i])),
    tags$td(class = "num", num(e$cpc_medio_pivo_mnl[i], 3)), tags$td(class = "num", num(e$cpc_medio_persistencia[i], 3)),
    tags$td(class = "num", sprintf("%s / %s / %s", num(e$n_pivo_vence_margem[i]), num(e$n_empate_margem[i]), num(e$n_pivo_perde_margem[i])))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "Eventos do mesmo ano usam o mesmo ajuste e a mesma janela de teste: não são independentes."),
    tags$thead(tags$tr(tags$th("Ano do evento"), tags$th("Ajuste"), tags$th("Teste"), tags$th("Eventos avaliáveis por tipo"),
                       tags$th(class = "num", "CPC do pivô"), tags$th(class = "num", "CPC da persistência"), tags$th(class = "num", "Vence / empata / perde"))),
    tags$tbody(linhas)))
}

# ---- 5. Otimização ------------------------------------------------------------------------------------
sol <- function(piloto, modelo, k, limiar = NA) {
  s <- LSOL[LSOL$piloto == piloto & LSOL$modelo == modelo & LSOL$k == k, ]
  if (!is.na(limiar)) s <- s[!is.na(s$limiar_min) & s$limiar_min == limiar, ]
  s[1, ]
}
sit0 <- function(piloto) sol(piloto, "situacao_2025", 0)

# Tabela das soluções de um modelo, k = 0..5
tabela_solucoes <- function(piloto, modelo, limiar = NA) {
  s0 <- sit0(piloto)
  s <- LSOL[LSOL$piloto == piloto & LSOL$modelo == modelo, ]
  if (!is.na(limiar)) s <- s[!is.na(s$limiar_min) & s$limiar_min == limiar, ]
  cap <- modelo == "uti_capacitado"
  if (!cap) s <- bind_rows(s0, s)
  s <- s |> arrange(k)
  linhas <- lapply(seq_len(nrow(s)), function(i) tags$tr(
    tags$td(class = "num", s$k[i]), tags$td(if (s$k[i] == 0) "— (serviços de 2025)" else nomes_lista(s$nomes_abertos[i])),
    tags$td(class = "num", num(s$tempo_medio[i], 1)), tags$td(class = "num", pct_l(s$pct_ate_60[i])), tags$td(class = "num", pct_l(s$pct_ate_120[i])),
    tags$td(class = "num", if (s$k[i] == 0) "—" else num(s$ganho_tempo_medio_min[i], 2)),
    if (cap) tagList(tags$td(class = "num", num(s$nao_atendida[i])), tags$td(class = "num", num(s$leitos_deficit[i], 1)),
                     tags$td(class = "num", num(s$tempo_medio_atendida[i], 1)))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$thead(tags$tr(tags$th(class = "num", "k"), tags$th("Municípios com unidade nova"), tags$th(class = "num", "Tempo médio à unidade mais próxima (min)"),
                       tags$th(class = "num", "% da demanda a até 60 min"), tags$th(class = "num", "% a até 120 min"),
                       tags$th(class = "num", "Redução do tempo médio (min)"),
                       if (cap) tagList(tags$th(class = "num", "Internações/ano acima da capacidade"), tags$th(class = "num", "Leitos equivalentes"),
                                        tags$th(class = "num", "Tempo médio da demanda atendida (min)")))),
    tags$tbody(linhas)))
}

# Curvas: tempo médio à unidade mais próxima por k e modelo
svg_curvas_k <- function(piloto, modelos, w = 680, h = 260) {
  s0 <- sit0(piloto)
  series <- lapply(modelos, function(m) {
    s <- LSOL[LSOL$piloto == piloto & LSOL$modelo == m$modelo, ]
    if (!is.na(m$limiar)) s <- s[!is.na(s$limiar_min) & s$limiar_min == m$limiar, ]
    if (m$modelo != "uti_capacitado") s <- bind_rows(s0, s)
    s <- s |> arrange(k)
    list(nome = m$nome, cor = m$cor, dash = m$dash, x = s$k, y = s$tempo_medio)
  })
  ys <- unlist(lapply(series, `[[`, "y"))
  pl <- 56; pr <- 14; pt <- 12; pb <- 30
  yt <- pretty(range(ys), n = 5); yr <- range(yt)
  sx <- function(x) pl + x / 5 * (w - pl - pr)
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="11" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, num(yt, if (all(yt == round(yt))) 0 else 1)), collapse = "")
  eixo <- paste0(paste(sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%d</text>', sx(0:5), h - 12, 0:5), collapse = ""),
                 sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="10" fill="#6b7280">unidades novas (k)</text>', pl + (w - pl - pr) / 2, h - 1))
  lin <- paste(vapply(series, function(s) paste0(
    sprintf('<polyline fill="none" stroke="%s" stroke-width="2.4" %s points="%s"/>', s$cor, if (nzchar(s$dash)) sprintf('stroke-dasharray="%s"', s$dash) else "",
            paste(sprintf("%.1f,%.1f", sx(s$x), sy(s$y)), collapse = " ")),
    paste(sprintf('<circle cx="%.1f" cy="%.1f" r="3.2" fill="%s" stroke="transparent" stroke-width="10" data-tip="%s, k = %d: %s"/>',
                  sx(s$x), sy(s$y), s$cor, esc(s$nome), as.integer(s$x), min_l(s$y, 1)), collapse = "")), character(1)), collapse = "")
  leg <- paste(vapply(series, function(s) sprintf('<span class="leg-item"><svg width="22" height="8" aria-hidden="true"><line x1="0" x2="22" y1="4" y2="4" stroke="%s" stroke-width="2.4" %s/></svg>%s</span>',
                                                  s$cor, if (nzchar(s$dash)) sprintf('stroke-dasharray="%s"', s$dash) else "", esc(s$nome)), character(1)), collapse = "")
  tit <- sprintf("%s: tempo médio até a unidade mais próxima por número de unidades novas, demanda de 2030 (provisória)", PIL[[piloto]]$nome)
  HTML(sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
               w, h, esc(tit), esc(tit), grade, eixo, lin, leg))
}

# Em quais soluções (modelo × k) cada município aparece
tabela_escolhidos <- function(piloto, modelos) {
  s <- LSOL[LSOL$piloto == piloto & LSOL$k > 0, ]
  lin <- list()
  for (m in modelos) {
    x <- s[s$modelo == m$modelo, ]
    if (!is.na(m$limiar)) x <- x[!is.na(x$limiar_min) & x$limiar_min == m$limiar, ]
    for (i in seq_len(nrow(x))) for (nm in strsplit(nomes_lista(x$nomes_abertos[i]), "; ")[[1]])
      lin[[length(lin) + 1]] <- tibble::tibble(mun = nm, modelo = m$nome, k = x$k[i])
  }
  d <- bind_rows(lin)
  if (!nrow(d)) return(NULL)
  w <- d |> group_by(mun, modelo) |> summarise(ks = paste(sort(k), collapse = ", "), n = n(), .groups = "drop")
  tot <- d |> group_by(mun) |> summarise(n = n(), kmin = min(k), .groups = "drop") |> arrange(desc(n), kmin, mun)
  nomes_mod <- vapply(modelos, `[[`, "", "nome")
  linhas <- lapply(seq_len(nrow(tot)), function(i) tags$tr(tags$td(tot$mun[i]),
    lapply(nomes_mod, function(mm) { v <- w$ks[w$mun == tot$mun[i] & w$modelo == mm]; tags$td(class = "num", if (length(v)) v else "—") }),
    tags$td(class = "num", tot$n[i])))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "Cada célula lista os valores de k (número de unidades novas) em que o município está na solução daquele modelo."),
    tags$thead(tags$tr(tags$th("Município"), lapply(nomes_mod, function(mm) tags$th(class = "num", mm)), tags$th(class = "num", "Soluções em que aparece"))),
    tags$tbody(linhas)))
}

# Sensibilidade (variante principal; k = 1 a 3)
tabela_sensibilidade <- function(piloto) {
  s <- LSEN[LSEN$piloto == piloto, ]
  pr <- s[grepl("^principal", s$variante), ] |> arrange(match(modelo, c("p_mediana", "uti_regional", "mclp")), k)
  lin <- lapply(seq_len(nrow(pr)), function(i) {
    r <- pr[i, ]
    out <- s[s$modelo == r$modelo & s$k == r$k & !s$igual_principal &
             ((is.na(s$limiar_min) & is.na(r$limiar_min)) | (!is.na(s$limiar_min) & !is.na(r$limiar_min) & s$limiar_min == r$limiar_min)), ]
    outras <- if (nrow(out)) paste(sprintf("%s: %s", unname(ifelse(out$variante %in% names(ROT_VAR), ROT_VAR[out$variante], out$variante)), nomes_lista(out$nomes_abertos)), collapse = "; ") else "nenhuma"
    tags$tr(class = if (isTRUE(r$quase_empate)) "destaque",
      tags$td(rot_modelo_l4(r$modelo, r$limiar_min)), tags$td(class = "num", r$k), tags$td(nomes_lista(r$nomes_abertos)), tags$td(nomes_lista(r$segunda_nomes)),
      tags$td(class = "num", pct_l(r$dif_pct_objetivo, 2)), tags$td(class = "num", pct_l(r$dif_pct_ganho, 1)),
      tags$td(if (isTRUE(r$quase_empate)) tags$b("sim") else "não"), tags$td(outras))
  })
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "Quase-empate: na p-mediana e na regional, diferença entre a melhor e a segunda melhor solução menor que 1% do tempo médio; na cobertura máxima, menor que 10% do ganho de cobertura. Oito variantes de demanda; candidatos fixos; força bruta."),
    tags$thead(tags$tr(tags$th("Modelo"), tags$th(class = "num", "k"), tags$th("Melhor solução"), tags$th("Segunda melhor"),
                       tags$th(class = "num", "Diferença (% do objetivo)"), tags$th(class = "num", "Diferença (% do ganho)"),
                       tags$th("Quase-empate"), tags$th("Variantes de demanda com outra solução"))),
    tags$tbody(lin)))
}

sens_resumo <- function(piloto) {
  s <- LSEN[LSEN$piloto == piloto & grepl("^principal", LSEN$variante), ]
  list(n = nrow(s), empates = sum(s$quase_empate), mudam = sum(!LSEN$igual_principal[LSEN$piloto == piloto]))
}

# UTI: necessidade empírica de leitos por região
tabela_necessidade_uti <- function() {
  d <- LNEC |> arrange(saldo_leitos)
  sald <- function(v) ifelse(is.na(v), "—", ifelse(v < 0, paste0("▼ déficit de ", num(-v, 1)), ifelse(v > 0, paste0("▲ sobra de ", num(v, 1)), "0")))
  lin <- lapply(seq_len(nrow(d)), function(i) tags$tr(
    tags$td(sem_mt(d$nome_regsaud[i])), tags$td(class = "num", num(d$leitos_uti_sus_2025[i], 0)),
    tags$td(class = "num", num(d$demanda_residentes_2025_obs[i])), tags$td(class = "num", num(d$leitos_necessarios_2025_obs[i], 1)),
    tags$td(class = "num", sald(d$saldo_leitos_2025_obs[i])),
    tags$td(class = "num", cont_l(d$demanda_residentes_2030[i])), tags$td(class = "num", num(d$leitos_necessarios_2030[i], 1)),
    tags$td(class = "num", sald(d$saldo_leitos[i]))))
  tot <- tags$tr(class = "destaque", tags$td("Mato Grosso"), tags$td(class = "num", num(sum(d$leitos_uti_sus_2025), 0)),
                 tags$td(class = "num", num(sum(d$demanda_residentes_2025_obs))), tags$td(class = "num", num(sum(d$leitos_necessarios_2025_obs), 1)),
                 tags$td(class = "num", sald(sum(d$leitos_uti_sus_2025) - sum(d$leitos_necessarios_2025_obs))),
                 tags$td(class = "num", num(sum(d$demanda_residentes_2030))), tags$td(class = "num", num(sum(d$leitos_necessarios_2030), 1)),
                 tags$td(class = "num", sald(sum(d$leitos_uti_sus_2025) - sum(d$leitos_necessarios_2030))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$caption(class = "nota-fonte", "Leitos necessários = internações dos residentes atendidas em MT × permanência média em UTI adulto (6,95 dias, 2024–2025) ÷ (365 × 0,85). Critério empírico do estudo, não parâmetro normativo. ▲ sobra / ▼ déficit em relação aos leitos SUS existentes na região."),
    tags$thead(tags$tr(tags$th("Região de saúde"), tags$th(class = "num", "Leitos SUS de UTI adulto (2025)"),
                       tags$th(class = "num", "Internações observadas 2025 (em MT)"), tags$th(class = "num", "Leitos necessários, 2025"),
                       tags$th(class = "num", "Saldo, 2025"), tags$th(class = "num", tagList("Internações projetadas 2030 ", selo_prov())),
                       tags$th(class = "num", "Leitos necessários, 2030"), tags$th(class = "num", "Saldo, 2030"))),
    tags$tbody(lin, tot)))
}

# ---- 6. Cenários com a escolha do paciente ---------------------------------------------------------------
cen <- function(piloto, cenario) LCEN[LCEN$piloto == piloto & LCEN$cenario == cenario, ][1, ]

tabela_cenarios <- function(piloto) {
  d <- LCEN[LCEN$piloto == piloto, ]
  d <- d[!(d$cenario %in% c("uti_regional_k1", "uti_regional_k3")), ]   # coincidem com a p-mediana (nota no texto)
  uti <- piloto == "uti"
  lin <- lapply(seq_len(nrow(d)), function(i) {
    r <- d[i, ]; ref <- r$cenario == "referencia_2030"
    tags$tr(class = if (ref) "destaque",
      tags$td(rot_cenario(r$cenario)), tags$td(if (ref) "—" else nomes_lista(r$nomes_abertos)),
      tags$td(class = "num", num(r$tempo_medio_esperado, 1)),
      tags$td(class = "num", if (ref) "—" else num(r$ganho_tempo_esperado_min, 2)),
      tags$td(class = "num", if (ref) "—" else num(r$ganho_tempo_mais_proximo_min, 2)),
      if (!uti) tags$td(class = "num", if (ref) "—" else num(r$ganho_tempo_mais_proximo_l4_min, 2)),
      if (uti) tagList(tags$td(class = "num", if (ref) paste0("tempo de referência: ", num(r$tempo_medio_esperado_capacidade, 1)) else num(r$ganho_tempo_esperado_capacidade_min, 2)),
                       tags$td(class = "num", num(r$destinos_ocupacao_acima_100pct, 0))),
      tags$td(class = "num", if (ref) "—" else sprintf("%s (%s de residentes do próprio município)", cont_l(r$fluxo_para_novas), cont_l(r$fluxo_para_novas_proprios_residentes))))
  })
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$thead(tags$tr(tags$th("Cenário"), tags$th("Municípios com unidade nova"), tags$th(class = "num", "Tempo médio esperado (min)"),
                       tags$th(class = "num", "Ganho com a escolha do paciente (min)"),
                       tags$th(class = "num", if (uti) "Ganho supondo ida à unidade mais próxima (min)" else "Ganho supondo ida à mais próxima, mesma oferta (min)"),
                       if (!uti) tags$th(class = "num", "Ganho supondo ida à mais próxima entre as maternidades em funcionamento (min)"),
                       if (uti) tagList(tags$th(class = "num", "Ganho com a escolha e restrição de capacidade (min)"),
                                        tags$th(class = "num", "Destinos acima de 100% de ocupação")),
                       tags$th(class = "num", paste0("Atendimentos por ano nas unidades novas (", PIL[[piloto]]$unid, ")")))),
    tags$tbody(lin)))
}

# Ganho por município de residência: uma coluna por cenário (minutos poupados por paciente)
tabela_ganho_municipios <- function(piloto, cenarios) {
  g <- LGAN[LGAN$piloto == piloto & LGAN$cenario %in% cenarios, ]
  ref <- g |> group_by(cod_mun6) |> summarise(mun = first(nome_municipio), reg = sem_mt(first(nome_regsaud)), tref = first(tempo_medio_ref), .groups = "drop")
  w <- lapply(cenarios, function(cn) { x <- g[g$cenario == cn, c("cod_mun6", "ganho_min_por_paciente")]; names(x)[2] <- cn; x })
  d <- Reduce(function(a, b) left_join(a, b, by = "cod_mun6"), w, ref)
  for (cn in cenarios) d[[cn]] <- sem_menos_zero(d[[cn]])
  d <- d |> arrange(desc(.data[[cenarios[length(cenarios)]]])) |> select(-cod_mun6)
  fg <- function(v) if (is.na(v)) "—" else if (abs(v) < 0.05) "0,0" else paste0(if (v > 0) "" else "−", num(abs(v), 1))
  cols <- c(list(mun = colDef(name = "Município", minWidth = 150, sticky = "left"), reg = colDef(name = "Região", minWidth = 130),
                 tref = colDef(name = "Tempo esperado sem unidade nova (min)", align = "right", minWidth = 110, cell = function(v) num(v, 1))),
            setNames(lapply(cenarios, function(cn) colDef(name = rot_cenario(cn), align = "right", minWidth = 105, cell = fg)), cenarios))
  div(class = "rolagem-x", reactable(d, searchable = TRUE, compact = TRUE, striped = TRUE, defaultPageSize = 15,
                                     showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, 142), columns = cols))
}

# Visão geral: os dois pilotos lado a lado (números das páginas de cada piloto)
tabela_resumo_pilotos <- function() {
  ps <- c("parto", "uti")
  S <- lapply(ps, resumo_acesso); names(S) <- ps
  pr <- lapply(ps, function(p) proj_mt(p, 2030L)); names(pr) <- ps
  s0 <- lapply(ps, sit0); s3 <- lapply(ps, function(p) sol(p, "p_mediana", 3)); names(s0) <- names(s3) <- ps
  et <- lapply(ps, exp_todos); names(et) <- ps
  sr <- lapply(ps, sens_resumo); names(sr) <- ps
  linha <- function(rot, f, nota = NULL) tags$tr(tags$td(rot, if (!is.null(nota)) div(class = "sub", nota)),
                                                 lapply(ps, function(p) tags$td(class = "num", f(p))))
  div(class = "rolagem-x", tags$table(class = "tab-loc",
    tags$thead(tags$tr(tags$th("Indicador"), tags$th(class = "num", a(href = "parto.html", "Atenção ao parto")),
                       tags$th(class = "num", a(href = "uti-adulto.html", "UTI adulto")))),
    tags$tbody(
      linha("Municípios com o serviço (2025)", function(p) num(S[[p]]$n_mun_serv), "parto: leito obstétrico; UTI: leito SUS de UTI adulto (CNES)"),
      linha("População-alvo a até 60 min do serviço (2025)", function(p) pct_l(S[[p]]$pop60), "mulheres de 15 a 49 anos; adultos de 20 anos ou mais"),
      linha("População-alvo a até 120 min (2025)", function(p) pct_l(S[[p]]$pop120)),
      linha("Tempo médio percorrido (2024–2025)", function(p) min_l(S[[p]]$tempo), "sede a sede, atendidos em MT"),
      linha("Atendidos fora da região de saúde (2024–2025)", function(p) pct_l(S[[p]]$fora_reg)),
      linha("Atendidos em outros estados (2024–2025)", function(p) pct_l(S[[p]]$fora_mt)),
      linha(tagList("Demanda projetada para 2030 ", selo_prov()), function(p) sprintf("%s (%s a %s)", num(pr[[p]]$demanda_proj), num(pr[[p]]$li80), num(pr[[p]]$ls80)),
            "partos; internações com UTI adulto (intervalo de 80%)"),
      linha("Tempo médio até a unidade mais próxima: serviços de 2025 → mais 3 unidades novas (p-mediana)",
            function(p) sprintf("%s → %s", min_l(s0[[p]]$tempo_medio), min_l(s3[[p]]$tempo_medio)), "demanda de 2030 (provisória)"),
      linha("Modelo de escolha × regra ingênua quando a oferta muda (CPC médio)", function(p) sprintf("%s × %s", num(et[[p]]$cpc_medio_pivo_mnl, 3), num(et[[p]]$cpc_medio_persistencia, 3)),
            "experimentos naturais 2021–2025; maior é melhor"),
      linha("Soluções com quase-empate (k = 1 a 3)", function(p) sprintf("%s de %s", num(sr[[p]]$empates), num(sr[[p]]$n)))))
  )
}

# UTI: duas soluções de k = 3 lado a lado, como cenários (sem recomendar uma)
cenarios_lado_a_lado <- function(piloto = "uti", k = 3L) {
  bloco <- function(rot, modelo, cenario) {
    s <- sol(piloto, modelo, k); c5 <- cen(piloto, cenario); s0 <- sit0(piloto)
    sc <- sol(piloto, "uti_capacitado", k)
    div(class = "bloco", h4(rot), p(tags$b(nomes_lista(s$nomes_abertos))),
      tags$dl(
        tags$dt("Tempo médio até a UTI mais próxima, 2030"), tags$dd(min_l(s$tempo_medio)),
        tags$dt("Demanda a até 120 min de uma UTI"), tags$dd(pct_l(s$pct_ate_120)),
        tags$dt("Tempo médio esperado com a escolha do paciente"), tags$dd(min_l(c5$tempo_medio_esperado)),
        tags$dt("Ganho com a escolha (sem restrição de capacidade)"), tags$dd(min_l(c5$ganho_tempo_esperado_min, 1)),
        tags$dt("Ganho com restrição de capacidade (ocupação até 100%)"), tags$dd(min_l(c5$ganho_tempo_esperado_capacidade_min, 1)),
        tags$dt("Internações por ano nas unidades novas"), tags$dd(cont_l(c5$fluxo_para_novas)),
        tags$dt("Destinos com ocupação implícita acima de 100%"), tags$dd(num(c5$destinos_ocupacao_acima_100pct)),
        tags$dt("Ocupação média implícita dos leitos SUS"), tags$dd(pct_l(100 * c5$ocupacao_implicita_media, 0))))
  }
  div(class = "cenarios-lado",
      bloco(sprintf("Cenário A — p-mediana, k = %d", k), "p_mediana", paste0("p_mediana_k", k)),
      bloco(sprintf("Cenário B — com capacidade, k = %d", k), "uti_capacitado", paste0("uti_capacitado_k", k)))
}

maiores_ganhos <- function(piloto, cenario, n = 3) {
  g <- LGAN[LGAN$piloto == piloto & LGAN$cenario == cenario, ] |> arrange(desc(ganho_min_por_paciente)) |> head(n)
  sprintf("%s (%s)", g$nome_municipio, min_l(g$ganho_min_por_paciente, 0))
}
n_com_ganho <- function(piloto, cenario, limite = 1) sum(LGAN$ganho_min_por_paciente[LGAN$piloto == piloto & LGAN$cenario == cenario] >= limite)
n_perde <- function(piloto, cenario, limite = 1) sum(LGAN$ganho_min_por_paciente[LGAN$piloto == piloto & LGAN$cenario == cenario] <= -limite)
