# =============================================================================
# Observatório PPSUS-MT — funções da seção "Eficiência" (eficiencia/*.qmd)
#
# Carregar DEPOIS de R/funcoes.R (não redefine nada de lá). Lê somente
# dados_site/eficiencia/ (gerado por scripts/06_preparar_eficiencia.py a partir
# da versão da estimação DEA/Malmquist registrada em metadados.csv — v2.1 desde
# 16/10/2026). Nenhum número é digitado: contagens, médias, limiares, datas e a
# nota de versão vêm dos CSVs.
#
# Índice
#   1. Leitura dos arquivos e constantes (modelos, faixas, parâmetros)
#   2. Formatação (escore, IC, tendência, faixas) e estilo da seção
#   3. Consultas (fichas por modelo/grupo, Malmquist do estado)
#   4. Componentes: navegação, faixa de versão, KPIs, especificação do modelo
#   5. Mapa por faixa (leaflet, sem tiles externos; clique abre o perfil)
#   6. Distribuições por faixa (SVG): por região de saúde e por modelo
#   7. Tabela de unidades (reactable) com ficha no detalhe e download
#   8. Potencial agregado de melhoria e pares mais usados
#   9. Evolução (Malmquist: EC em destaque, MI) — estado e regiões
#  10. Visão geral: cartões por modelo, tabela-resumo, ressalvas, fontes
# =============================================================================

# ---- 1. Leitura e constantes ---------------------------------------------------------
DIR_EF <- ds("eficiencia")

# Lê dados_site/eficiencia/<nome>.csv; `txt` = colunas lidas como texto (códigos)
ler_ef <- function(nome, txt = character()) {
  f <- file.path(DIR_EF, paste0(nome, ".csv"))
  if (!file.exists(f)) { aviso("arquivo ausente: dados_site/eficiencia/%s.csv (tabela vazia)", nome); return(tibble::tibble()) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  txt <- intersect(txt, hdr)
  tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                      colClasses = if (length(txt)) list(character = txt) else NULL))
}

COD_TXT <- c("co_regsaud", "co_macsaud", "cnes", "par_regiao_saude")
FICM  <- ler_ef("fichas_municipio", COD_TXT)
METM  <- ler_ef("metas_municipio", COD_TXT)
PARM  <- ler_ef("pares_municipio", COD_TXT)
RESMOD <- ler_ef("resumo_modelos")
ESPEC <- ler_ef("especificacoes_modelos")
MQREG <- ler_ef("malmquist_regiao", COD_TXT)
METAD <- ler_ef("metadados")
PARAM <- ler_ef("parametros")

meta_ef <- function(item, padrao = NA_character_) {
  v <- METAD$valor[METAD$item == item]; if (length(v) && !is.na(v[1])) as.character(v[1]) else padrao }
param_ef <- function(chave, padrao = NA) {
  v <- PARAM$valor_parametro[PARAM$chave == chave]
  if (!length(v) || is.na(v[1])) return(padrao)
  n <- suppressWarnings(as.numeric(v[1])); if (is.na(n)) as.character(v[1]) else n
}

ANO_EF      <- if (nrow(FICM)) as.integer(max(FICM$ano)) else ANO_REF
VERSAO_EF   <- meta_ef("versao_resultados", "v2")
DATA_EF     <- meta_ef("data_resultados", DATA_VERSAO)
FRACAO_META <- param_ef("meta_intermediaria_fracao", 0.5)
IC_NIVEL    <- param_ef("ic_nivel", 0.95)
LIM_TEND    <- param_ef("tendencia_limiar", 0.02)
CITACAO_EF  <- paste0("Resultados DEA ", VERSAO_EF, ", ", DATA_EF)
# Nota de versão (vazia na v2): o que mudou frente à versão anterior da estimação
NOTA_VERSAO_EF   <- redigir_nota_versao_ef(meta_ef("nota_versao", ""))   # redação v0.5 (R/redacao_eficiencia.R)
VERSAO_ANT_EF    <- meta_ef("versao_anterior", "")
DATA_ANT_EF      <- meta_ef("data_versao_anterior", "")
REESTIMADOS_EF   <- strsplit(meta_ef("modelos_reestimados", ""), ",\\s*")[[1]]
RELATORIO_EF     <- meta_ef("relatorio_tecnico", "")

# Modelos da seção: página, nome curto e unidade de análise
MODELOS_EF <- tibble::tribble(
  ~modelo, ~curto,                          ~pagina,                          ~unidade,
  "M1",    "Atenção básica",                "atencao-basica.html",            "municípios",
  "M0",    "Consolidado municipal",         "consolidado.html",               "municípios",
  "M2",    "Média complexidade",            "media-complexidade.html",        "municípios",
  "M2A",   "Média complexidade — acesso",   "media-complexidade.html#acesso", "municípios",
  "H",     "Hospitais SUS",                 "hospitais.html",                 "hospitais",
  "M3",    "Alta complexidade (regiões)",   "alta-complexidade.html",         "regiões de saúde")
info_modelo <- function(m) {
  r <- MODELOS_EF[MODELOS_EF$modelo == m, ]
  nm <- RESMOD$nome_modelo[RESMOD$modelo == m]
  list(modelo = m, curto = r$curto, pagina = r$pagina, unidade = r$unidade,
       nome = if (length(nm)) nm[1] else r$curto)
}

# Faixas publicadas (quartis do escore corrigido no estado; 'fronteira' = escore original 1)
FAIXAS    <- c("fronteira", "quartil superior", "terceiro quartil", "segundo quartil", "quartil inferior")
ROT_FAIXA <- setNames(c("Fronteira (melhores práticas)", "Quartil superior", "3º quartil", "2º quartil", "Quartil inferior"), FAIXAS)
# Sequência de um só matiz (escuro = mais eficiente); o texto da faixa acompanha sempre a cor
COR_FAIXA <- setNames(c("#0B4A4D", "#3D7C7F", "#6FA3A4", "#A9CACA", "#DCEBEA"), FAIXAS)
ROT_FAIXA_CURTO <- setNames(c("Fronteira", "Quartil superior", "3º quartil", "2º quartil", "Quartil inferior"), FAIXAS)
TXT_FAIXA <- setNames(c("#ffffff", "#ffffff", "#0b2f31", "#0b2f31", "#0b2f31"), FAIXAS)
# "Fora do modelo" não se distingue do quartil inferior só pela cor: no mapa, fundo branco com contorno cinza
# tracejado; nas barras, hachura diagonal cinza (WCAG 1.4.11)
COR_FORA  <- "#FFFFFF"
BORDA_FORA <- "#6b7280"
DEF_HACH_FORA <- '<defs><pattern id="hach-fora" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="#ffffff"/><line x1="0" y1="0" x2="0" y2="6" stroke="#6b7280" stroke-width="1.6"/></pattern></defs>'
SWATCH_FORA_HTML <- '<i style="background:repeating-linear-gradient(45deg,#ffffff 0 3px,#9ca3af 3px 4.5px);border:1.5px dashed #6b7280"></i>'
COL_RES_FAIXA <- c("n_fronteira", "n_quartil_superior", "n_terceiro_quartil", "n_segundo_quartil", "n_quartil_inferior")

# ---- 2. Formatação e estilo ------------------------------------------------------------
f3 <- function(x) num(x, 3)
# Primeira letra minúscula (preserva siglas no restante do nome)
inicial_min <- function(x) ifelse(is.na(x), x, paste0(tolower(substr(x, 1, 1)), substr(x, 2, nchar(x))))
fmt_ic <- function(inf, sup) ifelse(is.na(inf) | is.na(sup), "—", paste0(num(inf, 3), "–", num(sup, 3)))
pct_ef <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), "%"))
# Índice de Malmquist/EC → variação % ao ano com sinal ("+5,7% ao ano")
var_ano <- function(i, d = 1, sufixo = " ao ano") ifelse(is.na(i), "—",
  paste0(ifelse(i >= 1 | round(abs(100 * (i - 1)), d) == 0, "+", "−"), num(abs(100 * (i - 1)), d), "%", sufixo))
reais_txt <- function(x) ifelse(is.na(x), "—", escala(x, "R$ "))
rot_faixa <- function(f) ifelse(is.na(f) | !f %in% FAIXAS, "fora do modelo", ROT_FAIXA[f])
mais_ou_menos <- function(x) ifelse(is.na(x), "—", paste0(ifelse(x >= 0, "+", "−"), num(abs(x), 3)))

# Selo de faixa (cor + texto; nunca só cor)
selo_faixa <- function(f, incerta = FALSE) {
  if (is.na(f) || !f %in% FAIXAS) return(span(class = "selo-faixa selo-fora", "fora do modelo"))
  span(class = "selo-faixa", style = sprintf("background:%s;color:%s", COR_FAIXA[[f]], TXT_FAIXA[[f]]),
       ROT_FAIXA_CURTO[[f]], if (isTRUE(incerta)) span(class = "selo-inc", title = "O intervalo de confiança alcança a faixa vizinha: posição incerta", " ±"))
}

# Tendência do componente de gestão (EC) 2022–2025, com seta e texto
txt_tendencia <- function(t) {
  if (is.na(t) || !nzchar(t)) return(list(txt = "—", cls = "sit-neutra"))
  if (grepl("melhora", t)) return(list(txt = "▲ melhora consistente", cls = "sit-boa"))
  if (grepl("piora", t)) return(list(txt = "▼ piora consistente", cls = "sit-ruim"))
  list(txt = "◆ sem tendência definida", cls = "sit-neutra")
}

# Miniatura do intervalo de confiança na escala 0–1 (traço = IC, ponto = escore corrigido)
svg_ic <- function(est, inf, sup, w = 96, h = 14) {
  if (!is.finite(est)) return("")
  sx <- function(v) 3 + pmin(pmax(v, 0), 1) * (w - 6)
  ic <- if (is.finite(inf) && is.finite(sup))
    sprintf('<line x1="%.1f" x2="%.1f" y1="7" y2="7" stroke="#6FA3A4" stroke-width="4" stroke-linecap="round"/>', sx(inf), sx(sup)) else ""
  sprintf('<svg class="mini-ic" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="Escore %s; IC %s"><title>Escore corrigido %s (IC %s) na escala de 0 a 1</title><line x1="3" x2="%d" y1="7" y2="7" stroke="#e5e7eb" stroke-width="2"/>%s<circle cx="%.1f" cy="7" r="3.6" fill="#0B4A4D"/></svg>',
          w, h, w, h, f3(est), fmt_ic(inf, sup), f3(est), fmt_ic(inf, sup), w - 3, ic, sx(est))
}

css_eficiencia <- function() tags$style(HTML("
.selo-faixa { display: inline-block; padding: 1px 8px; border-radius: 10px; font-size: .76rem; font-weight: 600; white-space: nowrap; border: 1px solid rgba(0,0,0,.08); }
.selo-faixa.selo-fora { background: #EEF0F2; color: #4b5563; }
.selo-inc { font-weight: 700; }
svg.mini-ic { display: block; margin: 2px 0 0 auto; }
.ef-espec { display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); gap: .6rem; align-items: stretch; margin: .6rem 0 1.2rem; }
.ef-espec .bloco ul { margin: 0; padding-left: 1.1rem; font-size: .9rem; }
.ef-espec .bloco li { margin-bottom: .25rem; }
.ef-espec .seta { align-self: center; font-size: 1.8rem; color: #0E5A5E; }
@media (max-width: 760px) { .ef-espec { grid-template-columns: minmax(0, 1fr); } .ef-espec .seta { transform: rotate(90deg); justify-self: center; } }
.leg-faixas { background: rgba(255,255,255,.94); padding: 6px 9px; border-radius: 6px; font-size: .76rem; line-height: 1.45; box-shadow: 0 1px 4px rgba(0,0,0,.15); }
.leg-faixas i { display: inline-block; width: 13px; height: 13px; margin: 1px 5px 1px 0; vertical-align: -2px; border: 1px solid rgba(0,0,0,.12); }
.leg-faixas .leg-tit { font-weight: 600; margin-bottom: 2px; }
.ef-ficha { padding: .7rem 1rem .9rem; background: #f8fbfb; font-size: .88rem; }
.ef-ficha .sintese { font-size: .92rem; margin-bottom: .5rem; }
.ef-ficha table { font-size: .82rem; margin: .3rem 0 .4rem; border-collapse: collapse; }
.ef-ficha th, .ef-ficha td { padding: 2px 8px; border-bottom: 1px solid #e5e7eb; text-align: right; }
.ef-ficha th:first-child, .ef-ficha td:first-child { text-align: left; }
.ef-ficha h5 { font-size: .86rem; margin: .6rem 0 .2rem; color: #0E5A5E; }
.ef-botoes { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; margin: .4rem 0 .6rem; }
.ef-ler { border-left: 4px solid #0E5A5E; background: #f3f8f8; padding: .6rem 1rem; margin: .4rem 0 1rem; border-radius: 4px; }
.ef-ressalva { background: #fff4d6; border-left: 4px solid #d4a017; padding: .5rem .9rem; font-size: .9rem; margin: .4rem 0 1rem; border-radius: 4px; }
.ef-versao { background: #eef4fb; border-left: 4px solid #2f6db5; padding: .55rem 1rem; font-size: .92rem; margin: .5rem 0 1.1rem; border-radius: 4px; }
.cartoes-ef .cartao h4 { font-size: 1rem; }
.cartoes-ef .cartao .kpi-valor { font-size: 1.35rem; font-weight: 700; color: #0E5A5E; line-height: 1.2; margin: .2rem 0; }
.cartoes-ef .cartao .sub { margin-top: .15rem; }
.rolagem-x { max-width: 100%; overflow-x: auto; }
"))

# ---- 3. Consultas -----------------------------------------------------------------------
# Fichas de um modelo e ano (grupo: com_leito | sem_leito no M2A; NULL = todos)
fichas_modelo <- function(modelo, ano = ANO_EF, grupo = NULL) {
  f <- FICM[FICM$modelo == modelo & FICM$ano == ano, ]
  if (!is.null(grupo)) f <- f[!is.na(f$grupo) & f$grupo == grupo, ]
  f
}
avaliados <- function(f) f[!is.na(f$situacao) & f$situacao == "avaliado", ]

# Malmquist agregado do estado (média geométrica): janela ou transições
mq_estado <- function(modelo, grupo = "todos") MQREG[MQREG$modelo == modelo & MQREG$nivel == "estado" & MQREG$grupo == grupo, ]
mq_janela <- function(modelo, periodo = "2022-2025", grupo = "todos") {
  x <- mq_estado(modelo, grupo); x[x$periodo == periodo, ][1, ] }
resumo_mod <- function(modelo, ano = ANO_EF, grupo = "todos") {
  x <- RESMOD[RESMOD$modelo == modelo & RESMOD$ano == ano & RESMOD$grupo == grupo, ]; x[1, ] }
rotulo_grupo_ef <- function(g) switch(g, com_leito = "municípios com leito SUS", sem_leito = "municípios sem leito SUS",
                                      publico = "hospitais públicos", privado_filantropico = "hospitais privados e filantrópicos", "todos")

# ---- 4. Componentes ----------------------------------------------------------------------
PAGINAS_EF <- c("index.html" = "Como ler e visão geral", "atencao-basica.html" = "Atenção básica",
                "consolidado.html" = "Consolidado", "media-complexidade.html" = "Média complexidade",
                "hospitais.html" = "Hospitais", "alta-complexidade.html" = "Alta complexidade",
                "produtividade.html" = "Produtividade (Malmquist)")
nav_eficiencia <- function(atual = "index.html") {
  tags$nav(class = "nav-mun", `aria-label` = "Páginas da seção Eficiência",
           lapply(names(PAGINAS_EF), function(h) a(class = paste("btn btn-sm", if (h == atual) "btn-primary" else "btn-outline-primary"),
                                                  href = h, `aria-current` = if (h == atual) "page" else NULL, PAGINAS_EF[[h]])))
}

# Frase curta sobre a versão (para a faixa do topo): só o(s) modelo(s) reestimado(s) mudou(aram)
frase_versao_curta_ef <- function(href = "index.html#versao") {
  if (!nzchar(NOTA_VERSAO_EF) || !length(REESTIMADOS_EF) || !all(REESTIMADOS_EF %in% MODELOS_EF$modelo)) return("")
  nomes <- lista_e_ef(inicial_min(MODELOS_EF$curto[match(REESTIMADOS_EF, MODELOS_EF$modelo)]))
  sprintf(paste0("Na versão %s, apenas o modelo de %s foi reestimado, e os demais resultados correspondem aos da versão %s (%s) — ",
                 "<a href=\"%s\">nota de versão</a>. "),
          sub("^v", "", VERSAO_EF), nomes, sub("^v", "", VERSAO_ANT_EF), DATA_ANT_EF, href)
}

faixa_versao_ef <- function(nota_curta = TRUE) faixa_versao(sprintf(paste0(
  "<b>Resultados da versão %s da estimação DEA/Malmquist (%s), em validação com a SES-MT e o COSEMS-MT.</b> %s",
  "Os resultados devem ser lidos por <b>faixas com intervalo de confiança</b>, e não por posição pontual, e os dados de registro a verificar estão sinalizados. ",
  "A janela de análise é 2020–%d, e os anos de 2020–2021 refletem a pandemia de COVID-19."), sub("^v", "", VERSAO_EF), DATA_EF,
  if (isTRUE(nota_curta)) frase_versao_curta_ef() else "", ANO_EF))

# Parágrafo de ressalva da atenção básica sobre a versão (Markdown; vazio quando não há versão anterior)
ressalva_versao_m1 <- function() {
  if (!nzchar(NOTA_VERSAO_EF) || !"M1" %in% REESTIMADOS_EF) return("")
  sprintf(paste0("**Os resultados correspondem à versão %s (%s).** O insumo de agentes comunitários de saúde contabiliza apenas o ACS (CBO 515105). ",
                 "As visitas domiciliares, um dos produtos do modelo, são registradas sobretudo pelos ACS; por essa razão, os agentes de combate ",
                 "às endemias e os agentes indígenas, que a versão %s somava ao insumo, deixaram de ser contados como recurso deste modelo."),
          sub("^v", "", VERSAO_EF), DATA_EF, sub("^v", "", VERSAO_ANT_EF))
}

# Nota de versão visível (caixa): o texto vem de metadados.csv (nota_versao); `extra` acrescenta uma frase da página
nota_versao_ef <- function(extra = NULL) {
  if (!nzchar(NOTA_VERSAO_EF)) return(NULL)
  partes <- regmatches(NOTA_VERSAO_EF, regexpr("^[^:]+:", NOTA_VERSAO_EF))
  corpo <- if (length(partes)) sub("^[^:]+:\\s*", "", NOTA_VERSAO_EF) else NOTA_VERSAO_EF
  div(id = "versao", class = "ef-versao", role = "note",
      if (length(partes)) strong(partes), " ", corpo, if (!is.null(extra)) tagList(" ", HTML(extra)))
}

# KPIs de um modelo (municipal) no ano de referência
kpis_modelo <- function(modelo, grupo = NULL, ano = ANO_EF) {
  f <- fichas_modelo(modelo, ano, grupo); av <- avaliados(f)
  g <- if (is.null(grupo)) "todos" else grupo
  n_av <- nrow(av); n_fr <- sum(av$faixa == "fronteira", na.rm = TRUE)
  ec <- mq_janela(modelo, "2022-2025", g)
  ref_txt <- if (is.null(grupo)) sprintf("de %d municípios · %d", nrow(f), ano) else sprintf("de %d %s · %d", nrow(f), rotulo_grupo_ef(grupo), ano)
  okf <- !is.na(av$meta_financeira_publicavel) & av$meta_financeira_publicavel == 1 & is.finite(av$recursos_redirecionaveis_reais_2025)
  red <- sum(av$recursos_redirecionaveis_reais_2025[okf]); n_fin <- sum(okf & av$recursos_redirecionaveis_reais_2025 > 0)
  div(class = "kpi-grade",
    kpi_simples("Municípios avaliados", num(n_av), ref_txt,
                if (n_av < nrow(f)) sprintf("%d fora do modelo (motivo na tabela de cada município)", nrow(f) - n_av)),
    kpi_simples("Na fronteira (melhores práticas)", num(n_fr), sprintf("%s dos avaliados · %d", pct_ef(100 * n_fr / max(n_av, 1)), ano),
                "escore original = 1: nenhum município com recursos semelhantes produziu mais"),
    kpi_simples("Escore corrigido — mediana", num(median(av$escore_bc, na.rm = TRUE), 3), sprintf("escala 0–1 · %d", ano),
                sprintf("potencial mediano de expansão fora da fronteira: %s", pct_ef(median(av$potencial_expansao_pct, na.rm = TRUE)))),
    kpi_simples("Faixa incerta", num(sum(av$ic_cruza_faixa == 1, na.rm = TRUE)), sprintf("municípios cujo IC alcança a faixa vizinha · %d", ano),
                "a faixa destes municípios deve ser lida como provisória"),
    kpi_simples("Aproximação às melhores práticas", var_ano(ec$ec), "média anual 2022–2025 (EC, Malmquist)",
                sprintf("%d com melhora consistente · %d com piora consistente", as.integer(ec$n_melhora_ec), as.integer(ec$n_piora_ec))),
    kpi_simples("Recursos que poderiam ser redirecionados", reais_txt(red), sprintf("R$ de 2025 · soma de %d municípios · %d", n_fin, ano),
                "folga do insumo financeiro frente aos pares: realocação, não corte"),
    kpi_simples("Registro a verificar", num(sum(av$registro_a_verificar == 1, na.rm = TRUE)), sprintf("municípios sinalizados · %d", ano),
                "valores de origem a verificar com a SES-MT e o COSEMS-MT"))
}

# Recursos (insumos) → produção (produtos) da especificação principal do modelo
bloco_especificacao <- function(modelo, grupo = NULL) {
  e <- ESPEC[ESPEC$modelo == modelo, ]
  if (!is.null(grupo)) e <- e[e$tipo == "produto" | (!is.na(e$grupo) & e$grupo == grupo), ]
  if (nrow(e) == 0) return(p(class = "nota-fonte", "Especificação não disponível."))
  e <- e[order(e$tipo, e$ordem), ]
  item <- function(x) tags$li(strong(x$nome_gerencial), span(class = "sub", paste0(" — ", x$unidade, " · ", x$fonte)))
  lista <- function(tp) { x <- e[e$tipo == tp, ]; x <- x[!duplicated(x$variavel), ]
    tags$ul(lapply(seq_len(nrow(x)), function(j) item(x[j, ]))) }
  div(class = "ef-espec",
      div(class = "bloco", h4("Recursos (insumos)"), lista("insumo")),
      div(class = "seta", `aria-hidden` = "true", "→"),
      div(class = "bloco", h4("Produção (produtos)"), lista("produto")))
}

# ---- 5. Mapa por faixa ----------------------------------------------------------------------
legenda_faixas_html <- function(cont, n_fora, com_inc = TRUE, com_reg = TRUE, titulo = "Faixa no estado") {
  linhas <- vapply(FAIXAS, function(f) sprintf('<div><i style="background:%s"></i>%s (%d)</div>', COR_FAIXA[[f]], ROT_FAIXA[[f]], cont[[f]]), character(1))
  paste0('<div class="leg-faixas"><div class="leg-tit">', titulo, '</div>', paste(linhas, collapse = ""),
         if (n_fora > 0) sprintf('<div>%sFora do modelo (%d)</div>', SWATCH_FORA_HTML, n_fora) else "",
         if (com_inc) '<div><i style="background:#fff;border:1.6px dashed #111827"></i>IC alcança a faixa vizinha</div>' else "",
         if (com_reg) '<div><i style="background:#fff;border:2px solid #111827;border-radius:50%;width:10px;height:10px"></i>Registro a verificar</div>' else "",
         '</div>')
}

mapa_faixas <- function(modelo, ano = ANO_EF, altura = 500, prefixo = "../municipios/", grupo = NULL, titulo = NULL) {
  if (nrow(GEO) == 0) return(sem_mapa())
  f <- fichas_modelo(modelo, ano, grupo)
  g <- left_join(GEO, select(f, cod_mun6, faixa, situacao, motivo_situacao, escore_bc, ic_inf, ic_sup, ic_cruza_faixa,
                             registro_a_verificar, rotulo_grupo, sinal_gerencial, escore_esperado), by = "cod_mun6")
  if (!is.null(grupo)) g <- g[!is.na(g$situacao), ]
  k <- match(g$faixa, FAIXAS)
  fill <- ifelse(is.na(k), COR_FORA, unname(COR_FAIXA[k]))
  grp <- ifelse(is.na(g$rotulo_grupo) | g$rotulo_grupo == "todos", "", paste0("<br>Fronteira: ", esc(g$rotulo_grupo)))
  corpo <- ifelse(is.na(k),
                  paste0("<i>Fora do modelo em ", ano, "</i>"),
                  sprintf("Faixa: <b>%s</b>%s<br>Escore corrigido %s (IC %s)%s",
                          esc(rot_faixa(g$faixa)), ifelse(!is.na(g$ic_cruza_faixa) & g$ic_cruza_faixa == 1, " — posição incerta", ""),
                          f3(g$escore_bc), fmt_ic(g$ic_inf, g$ic_sup),
                          ifelse(is.na(g$escore_esperado), "", paste0("<br>Escore esperado pelo contexto: ", f3(g$escore_esperado)))))
  sinal <- ifelse(is.na(g$sinal_gerencial) | !nzchar(g$sinal_gerencial), "", paste0("<br><span style='color:#6b7280'>Sinalização: ", esc(g$sinal_gerencial), "</span>"))
  rot <- sprintf("<b>%s</b> · <span style='color:#6b7280'>%s</span>%s<br>%s%s<br><i>o clique abre o perfil</i>",
                 esc(g$municipio), esc(ifelse(is.na(g$regiao_saude), "", g$regiao_saude)), grp, corpo, sinal)
  cont <- sapply(FAIXAS, function(x) sum(f$faixa == x, na.rm = TRUE))
  n_fora <- sum(is.na(match(f$faixa, FAIXAS)) & f$cod_mun6 %in% GEO$cod_mun6)
  bb <- bbox_num(g)
  m <- mapa_vazio(altura) |>
    addPolygons(data = g, layerId = ~slug, fillColor = fill, fillOpacity = 1, color = "#ffffff", weight = 1,
                label = lapply(rot, HTML))
  fora <- g[is.na(k), ]
  if (nrow(fora)) m <- addPolygons(m, data = fora, fill = FALSE, color = BORDA_FORA, weight = 1.2, dashArray = "4,3", opacity = 1,
                                   options = pathOptions(interactive = FALSE))
  inc <- g[!is.na(g$ic_cruza_faixa) & g$ic_cruza_faixa == 1, ]
  if (nrow(inc)) m <- addPolygons(m, data = inc, fill = FALSE, color = "#111827", weight = 1.3, dashArray = "3,3", opacity = .85,
                                  options = pathOptions(interactive = FALSE))
  reg <- f[!is.na(f$registro_a_verificar) & f$registro_a_verificar == 1, c("cod_mun6")] |> left_join(CENT, by = "cod_mun6") |> filter(is.finite(lon))
  if (nrow(reg)) m <- addCircleMarkers(m, data = reg, lng = ~lon, lat = ~lat, radius = 4, color = "#111827", weight = 2,
                                       fillColor = "#ffffff", fillOpacity = 1, options = pathOptions(interactive = FALSE))
  if (is.null(titulo)) titulo <- if (is.null(grupo)) paste0("Faixa no estado, ", ano) else paste0("Faixa entre os ", rotulo_grupo_ef(grupo), ", ", ano)
  m |> addControl(html = legenda_faixas_html(cont, n_fora, nrow(inc) > 0, nrow(reg) > 0, titulo),
                  position = "bottomright") |>
    fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
    htmlwidgets::onRender(js_clique(prefixo))
}

# ---- 6. Distribuições por faixa (SVG) ----------------------------------------------------------
# Troca <a href> dentro de SVG por <g role="link"> com clique e teclado: o quarto-nav.js percorre todos
# os <a> da página e falha nos de SVG (href não é texto), interrompendo o restante do script.
svg_sem_ancora <- function(svg) {
  svg <- gsub("<a href=\"([^\"]*)\">",
              "<g class=\"svg-link\" role=\"link\" tabindex=\"0\" style=\"cursor:pointer\" onclick=\"window.location='\\1'\" onkeydown=\"if(event.key==='Enter')window.location='\\1'\">", svg)
  gsub("</a>", "</g>", svg, fixed = TRUE)
}

# Barras 100% empilhadas: uma linha por categoria; mat = matriz de contagens (colunas = FAIXAS [+ fora])
svg_faixas_barras <- function(rotulos, mat, titulo = "", hrefs = NULL, w = 720, lh = 26, pl = 210, pr = 70, rot_n = "n") {
  if (length(rotulos) == 0) return("")
  cores <- c(COR_FAIXA, fora = "url(#hach-fora)"); txtc <- c(TXT_FAIXA, fora = "#111827")
  cats <- colnames(mat); n <- nrow(mat); tot <- rowSums(mat)
  h <- n * lh + 8; larg <- w - pl - pr
  linhas <- vapply(seq_len(n), function(i) {
    y <- (i - 1) * lh + 4; x0 <- pl; partes <- ""
    for (c in cats) { v <- mat[i, c]; if (v <= 0 || tot[i] == 0) next
      wd <- larg * v / tot[i]
      nome_c <- if (c == "fora") "Fora do modelo" else ROT_FAIXA[[c]]
      partes <- paste0(partes, sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s" stroke="%s" stroke-width=".8" data-tip="%s · %s: %d (%s)"/>%s',
        x0, y, wd, lh - 8, cores[[c]], if (c == "fora") BORDA_FORA else "#fff", esc(rotulos[i]), esc(nome_c), as.integer(v), pct_ef(100 * v / tot[i]),
        if (wd >= 16) sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11" fill="%s" pointer-events="none">%d</text>', x0 + wd / 2, y + lh / 2 + 0, txtc[[c]], as.integer(v)) else ""))
      x0 <- x0 + wd }
    rt <- sprintf('<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937">%s</text>', pl - 8, y + lh / 2, esc(rotulos[i]))
    if (!is.null(hrefs) && !is.na(hrefs[i])) rt <- svg_sem_ancora(sprintf('<a href="%s">%s</a>', hrefs[i], rt))
    paste0(rt, partes, sprintf('<text x="%d" y="%.1f" font-size="11" fill="#4b5563">%s = %d</text>', w - pr + 6, y + lh / 2, rot_n, as.integer(tot[i])))
  }, character(1))
  leg_cats <- intersect(c(FAIXAS, "fora"), cats[colSums(mat) > 0])
  leg <- paste(vapply(leg_cats, function(c) sprintf('<span class="leg-item"><svg width="14" height="14" aria-hidden="true">%s<rect width="14" height="14" fill="%s" stroke="%s"/></svg>%s</span>',
                                                   if (c == "fora") DEF_HACH_FORA else "", cores[[c]], if (c == "fora") BORDA_FORA else "#d1d5db",
                                                   if (c == "fora") "Fora do modelo" else ROT_FAIXA[[c]]), character(1)), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(titulo), esc(titulo), if ("fora" %in% cats) DEF_HACH_FORA else "", paste(linhas, collapse = ""), leg)
}

# Distribuição das faixas por região de saúde (municípios do modelo no ano)
faixas_por_regiao <- function(modelo, ano = ANO_EF, grupo = NULL, com_fora = TRUE) {
  f <- fichas_modelo(modelo, ano, grupo)
  if (nrow(f) == 0) return(HTML(""))
  f$cat <- ifelse(f$faixa %in% FAIXAS, f$faixa, "fora")
  cats <- if (com_fora) c(FAIXAS, "fora") else FAIXAS
  if (!com_fora) f <- f[f$cat != "fora", ]
  regs <- REG$co_regsaud[ordem_nome(REG$regiao_saude)]
  regs <- regs[regs %in% f$co_regsaud]
  mat <- t(vapply(regs, function(r) vapply(cats, function(c) sum(f$co_regsaud == r & f$cat == c), numeric(1)), numeric(length(cats))))
  if (length(regs) == 1) mat <- matrix(mat, nrow = 1)
  colnames(mat) <- cats
  HTML(svg_faixas_barras(nome_regiao(regs), mat, titulo = paste0("Municípios por faixa e região de saúde, ", ano), rot_n = "n"))
}

# ---- 7. Tabela de unidades com ficha -------------------------------------------------------------
# Ficha resumida (detalhe da linha): frase-síntese, pares plausíveis, metas publicáveis
ficha_detalhe <- function(cod, modelo, ano = ANO_EF, prefixo = "../municipios/") {
  r <- FICM[FICM$cod_mun6 == cod & FICM$modelo == modelo & FICM$ano == ano, ][1, ]
  pr <- PARM[PARM$cod_mun6 == cod & PARM$modelo == modelo & PARM$ano == ano, ]; pr <- pr[order(pr$ordem), ]
  mt <- METM[METM$cod_mun6 == cod & METM$modelo == modelo & METM$ano == ano & METM$meta_publicavel == 1, ]
  mt <- mt[order(mt$tipo != "produto"), ]
  fora_banda <- isTRUE(r$par_mais_semelhante_fora_banda == 1)
  pares <- if (nrow(pr)) tagList(
      if (isTRUE(r$faixa == "fronteira")) p(class = "sub", "Referência alternativa: a posição na fronteira decorre da falta de comparável em algum recurso; em relação aos municípios elegíveis como referência, estas são as práticas a observar."),
      tags$ul(lapply(seq_len(nrow(pr)), function(j) tags$li(
      a(href = paste0(prefixo, pr$par_slug[j], ".html"), pr$par_municipio[j]), sprintf(" (%s · peso %s)", pr$par_regiao_saude[j], num(pr$peso[j], 2)),
      if (isTRUE(pr$mais_semelhante[j] == 1)) strong(if (fora_banda) " — maior peso; nenhum par na faixa de porte de 1/3 a 3 vezes" else " — mais semelhante em porte"))))) else
      p(class = "sub", if (isTRUE(r$faixa == "fronteira")) {
          # n_vezes_referencia = municípios que mostram esta unidade entre os seus pares publicados (scripts/06); com 0,
          # a frase dispensa o número ("nenhum outro município")
          nref <- suppressWarnings(as.numeric(r$n_vezes_referencia))
          if (isTRUE(nref == 0)) "Por situar-se na fronteira, o município não tem pares e, embora pertença às melhores práticas, não serve de referência para nenhum outro município, pois não figura entre os pares publicados dos demais."
          else sprintf("Por situar-se na fronteira, o município não tem pares e serve de referência para %s %s.", num(r$n_vezes_referencia),
                       if (isTRUE(nref == 1)) "município" else "municípios")
        } else
        "Sem pares listados: entre os municípios elegíveis como referência (com registro plausível), nenhum supera este município com recursos semelhantes. O escore publicado provém da fronteira comum, que inclui unidades que não servem de par.")
  sem_lacuna <- nrow(mt) > 0 && all(!is.finite(mt$potencial_unidades) | abs(mt$potencial_unidades) < 1e-9)
  metas <- if (nrow(mt) && (!isTRUE(r$faixa == "fronteira") || nrow(pr) > 0) && !sem_lacuna) tags$table(
    tags$thead(tags$tr(tags$th("Variável"), tags$th("Unidade"), tags$th("Observado"), tags$th("Meta intermediária"), tags$th("Meta plena"), tags$th("Potencial"))),
    tags$tbody(lapply(seq_len(nrow(mt)), function(j) { x <- mt[j, ]
      tags$tr(tags$td(paste0(x$nome_gerencial, if (x$tipo == "insumo") " (recurso)" else "")), tags$td(x$unidade),
              tags$td(num(x$observado, 1)), tags$td(num(x$meta_intermediaria, 1)), tags$td(num(x$meta_radial, 1)),
              tags$td(pct_ef(x$potencial_pct))) }))) else NULL
  div(class = "ef-ficha",
      if (!is.na(r$texto_padrao)) p(class = "sintese", redigir_texto_padrao(r$texto_padrao)),
      h5("Pares de referência plausíveis"), pares,
      if (!is.null(metas)) tagList(h5(sprintf("Metas %d (por mil habitantes; meta intermediária = %s da distância até a meta plena)", ano, pct_ef(100 * FRACAO_META, 0))), metas),
      if (!is.na(r$nota_evolucao) && nzchar(r$nota_evolucao)) p(class = "sub", strong("Evolução: "), redigir_nota_evolucao(r$nota_evolucao)),
      p(a(href = paste0(prefixo, r$slug, ".html"), paste0("Abrir o perfil de ", r$municipio, " →"))))
}

tabela_eficiencia <- function(modelo, ano = ANO_EF, grupo = NULL, prefixo = "../municipios/",
                              id_html = paste0("tab-ef-", tolower(modelo), if (!is.null(grupo)) paste0("-", gsub("_", "-", grupo)) else "")) {
  f <- avaliados(fichas_modelo(modelo, ano, grupo))
  if (nrow(f) == 0) return(p(class = "nota-fonte", "Sem municípios avaliados."))
  f <- ordenar_mun(f)
  d <- tibble::tibble(cod_mun6 = f$cod_mun6, Município = f$municipio, slug = f$slug, `Região de saúde` = f$regiao_saude,
                      Porte = f$porte_faixa, faixa = f$faixa, Faixa = match(f$faixa, FAIXAS), ic_cruza_faixa = f$ic_cruza_faixa,
                      Escore = f$escore_bc, ic_inf = f$ic_inf, ic_sup = f$ic_sup, Esperado = f$escore_esperado,
                      diferenca = f$residuo_escore, dif_inf = f$residuo_escore_ic_inf, dif_sup = f$residuo_escore_ic_sup,
                      Potencial = f$potencial_expansao_pct, Referencia = f$n_vezes_referencia,
                      Tendencia = f$tendencia_ec_2022_2025, ec_2022_2025 = f$ec_2022_2025, Sinais = f$sinal_gerencial,
                      registro_a_verificar = f$registro_a_verificar)
  esconder <- c("cod_mun6", "slug", "faixa", "ic_cruza_faixa", "ic_inf", "ic_sup", "diferenca", "dif_inf", "dif_sup", "ec_2022_2025", "registro_a_verificar",
                if (all(is.na(d$Esperado))) "Esperado")  # M2A: sem segundo estágio
  esconder <- setdiff(esconder, "Esperado")
  cols <- setNames(lapply(esconder, function(x) colDef(show = FALSE)), esconder)
  cols <- c(cols, list(
    Município = colDef(minWidth = 150, sticky = "left", cell = function(v, i) a(href = paste0(prefixo, d$slug[i], ".html"), v)),
    `Região de saúde` = colDef(minWidth = 130),
    Porte = colDef(name = "Porte (hab.)", minWidth = 80),
    Faixa = colDef(name = "Faixa", minWidth = 125, cell = function(v, i) selo_faixa(d$faixa[i], isTRUE(d$ic_cruza_faixa[i] == 1))),
    Escore = colDef(name = sprintf("Escore corrigido (IC %s%%)", num(100 * IC_NIVEL, 0)), align = "right", minWidth = 130,
                    html = TRUE, cell = function(v, i) sprintf('<b>%s</b><div class="sub">%s</div>%s', f3(v), fmt_ic(d$ic_inf[i], d$ic_sup[i]), svg_ic(v, d$ic_inf[i], d$ic_sup[i]))),
    Esperado = colDef(name = "Escore esperado pelo contexto", show = !all(is.na(d$Esperado)), align = "right", minWidth = 120,
                      cell = function(v, i) if (is.na(v)) span(class = "sub", "—") else tagList(f3(v),
                        div(class = "sub", leitura_contexto(d$dif_inf[i], d$dif_sup[i])))),
    Potencial = colDef(name = "Potencial de expansão da produção", align = "right", minWidth = 110,
                       cell = function(v, i) if (is.na(v)) span(class = "sub", if (d$faixa[i] %in% "fronteira") "na fronteira" else "—") else paste0("+", num(v, 1), "%")),
    Referencia = colDef(name = "É referência para (municípios)", align = "center", minWidth = 90, cell = function(v) if (is.na(v) || v == 0) "—" else num(v)),
    Tendencia = colDef(name = "Tendência 2022–2025 (gestão)", minWidth = 150,
                       cell = function(v, i) { t <- txt_tendencia(v); tagList(span(class = paste("sit", t$cls), t$txt),
                         if (!is.na(d$ec_2022_2025[i])) div(class = "sub", paste0("EC ", var_ano(d$ec_2022_2025[i])))) }),
    Sinais = colDef(name = "Sinalizações", minWidth = 150, cell = function(v) if (is.na(v) || !nzchar(v)) span(class = "sub", "—") else span(class = "sub", v))))
  arq <- paste0("eficiencia_", tolower(modelo), if (!is.null(grupo)) paste0("_", grupo), "_", ano, ".csv")
  tagList(
    div(class = "ef-botoes",
        tags$button(class = "btn btn-sm btn-outline-primary", type = "button",
                    onclick = sprintf("Reactable.downloadDataCSV('%s', '%s')", id_html, arq), "⭳ Baixar esta tabela (CSV)"),
        span(class = "sub", "O símbolo ▸ abre a ficha do município (frase-síntese, pares e metas). A ordem é alfabética, pois as faixas não constituem ", tags$em("ranking", .noWS = "outside"), ".")),
    div(class = "rolagem-x", reactable(d, elementId = id_html, searchable = TRUE, compact = TRUE, striped = TRUE, highlight = TRUE,
              defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, nrow(d)), wrap = TRUE,
              columns = cols, details = function(i) ficha_detalhe(d$cod_mun6[i], modelo, ano, prefixo))))
}

# Leitura qualitativa do escore esperado (a diferença é calculada com o escore do segundo estágio, por isso
# não se publica como subtração das duas colunas): acima / compatível / abaixo, pelo intervalo de confiança
leitura_contexto <- function(inf, sup) {
  if (is.finite(inf) && inf > 0) return("▲ acima do esperado")
  if (is.finite(sup) && sup < 0) return("▼ abaixo do esperado")
  if (is.finite(inf) || is.finite(sup)) return("● compatível com o esperado")
  ""
}

# ---- 8. Potencial agregado e pares mais usados -----------------------------------------------------
# Soma, entre os municípios com potencial de melhoria frente aos pares plausíveis (alguma meta diferente
# do observado: os "ineficientes" da fronteira de pares), do observado, da meta intermediária, da meta
# plena e do potencial, só nas metas publicáveis (valores absolutos do ano). Mesmo recorte das metas
# agregadas do relatório técnico (especificação de pares plausíveis).
municipios_com_potencial <- function(modelo, ano = ANO_EF, grupo = NULL) {
  f <- avaliados(fichas_modelo(modelo, ano, grupo))
  m <- METM[METM$modelo == modelo & METM$ano == ano & METM$cod_mun6 %in% f$cod_mun6, ]
  unique(m$cod_mun6[is.finite(m$potencial_unidades) & abs(m$potencial_unidades) > 1e-9])
}
potencial_agregado <- function(modelo, ano = ANO_EF, grupo = NULL) {
  ids <- municipios_com_potencial(modelo, ano, grupo)
  m <- METM[METM$modelo == modelo & METM$ano == ano & METM$meta_publicavel == 1 & METM$cod_mun6 %in% ids, ]
  if (nrow(m) == 0) return(m)
  m |> group_by(tipo, variavel, nome_gerencial, unidade_abs) |>
    summarise(n = n_distinct(cod_mun6), observado = sum(observado_abs, na.rm = TRUE), inter = sum(meta_intermediaria_abs, na.rm = TRUE),
              plena = sum(meta_radial_abs, na.rm = TRUE), pot = sum(potencial_unidades, na.rm = TRUE),
              reais = sum(potencial_reais_2025, na.rm = TRUE), n_reais = n_distinct(cod_mun6[is.finite(potencial_reais_2025) & potencial_reais_2025 > 0]),
              .groups = "drop") |>
    filter(abs(pot) > 1e-9) |>
    mutate(pct = 100 * pot / observado) |> arrange(desc(tipo == "produto"), desc(n))
}

tabela_potencial <- function(modelo, ano = ANO_EF, grupo = NULL) {
  x <- potencial_agregado(modelo, ano, grupo)
  if (nrow(x) == 0) return(p(class = "nota-fonte", "Sem metas publicáveis."))
  fm <- function(v, u) if (grepl("^R\\$", u)) reais_txt(v) else escala(v)
  d <- tibble::tibble(Tipo = ifelse(x$tipo == "produto", "Produção", "Recurso"), Variável = x$nome_gerencial, Unidade = x$unidade_abs,
                      Municípios = x$n, Observado = x$observado, Intermediaria = x$inter, Plena = x$plena, Pct = x$pct, u = x$unidade_abs)
  reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE,
            columns = list(u = colDef(show = FALSE),
              Tipo = colDef(minWidth = 80), Variável = colDef(minWidth = 190), Unidade = colDef(minWidth = 110),
              Municípios = colDef(align = "center", minWidth = 80),
              Observado = colDef(name = paste0("Observado ", ano), align = "right", cell = function(v, i) fm(v, d$u[i])),
              Intermediaria = colDef(name = "Meta intermediária", align = "right", cell = function(v, i) fm(v, d$u[i])),
              Plena = colDef(name = "Meta plena", align = "right", cell = function(v, i) fm(v, d$u[i])),
              Pct = colDef(name = "Potencial (meta plena × observado)", align = "right", minWidth = 120,
                           cell = function(v, i) if (is.na(v)) "—" else paste0(if (v > 0) "+" else "−", num(abs(v), 1), "%"))))
}

# Frase de síntese do potencial (produção e recurso financeiro), com números do arquivo
texto_potencial <- function(modelo, ano = ANO_EF, grupo = NULL) {
  x <- potencial_agregado(modelo, ano, grupo); if (nrow(x) == 0) return("")
  pr <- x[x$tipo == "produto", ]; fin <- x[x$tipo == "insumo" & grepl("^R\\$", x$unidade_abs), ]
  fin <- fin[which.max(fin$n), ]
  n_pot <- length(municipios_com_potencial(modelo, ano, grupo))
  partes <- if (nrow(pr)) sprintf("Em %d, %d municípios apresentam potencial de melhoria em relação aos seus pares plausíveis, isto é, têm alguma meta diferente do valor observado. Mantidos os recursos atuais, a produção desses municípios poderia crescer %s (meta plena), e a meta intermediária, que corresponde a %s dessa distância, constitui a referência de curto prazo.",
    ano, n_pot, if (nrow(pr) > 1) paste0("de ", pct_ef(min(pr$pct)), " a ", pct_ef(max(pr$pct)), ", conforme o serviço") else pct_ef(pr$pct), pct_ef(100 * FRACAO_META, 0)) else ""
  if (nrow(fin) == 1 && fin$reais > 0) partes <- paste(partes, sprintf(
    "Na despesa (%s), a folga em relação aos pares soma %s de 2025 em %d municípios (%s do gasto dos municípios com potencial de melhoria). Essa folga corresponde à parcela que os pares dispensam para obter o mesmo resultado e indica espaço de realocação, e não um corte automático.",
    inicial_min(fin$nome_gerencial), reais_txt(fin$reais), fin$n_reais, pct_ef(100 * fin$reais / fin$observado)))
  partes
}

# Municípios mais usados como referência (n_vezes_referencia) — barras com link ao perfil
pares_mais_usados <- function(modelo, ano = ANO_EF, grupo = NULL, n = 10, prefixo = "../municipios/") {
  f <- avaliados(fichas_modelo(modelo, ano, grupo)); f <- f[!is.na(f$n_vezes_referencia) & f$n_vezes_referencia > 0, ]
  if (nrow(f) == 0) return(p(class = "nota-fonte", "Sem pares de referência no ano."))
  f <- f[order(-f$n_vezes_referencia, ordem_nome(f$municipio)), ][seq_len(min(n, nrow(f))), ]
  HTML(svg_sem_ancora(svg_barras_h(paste0(f$municipio, " (", f$regiao_saude, ")"), f$n_vezes_referencia, "int",
                    titulo = paste0("Municípios mais usados como referência, ", ano), hrefs = paste0(prefixo, f$slug, ".html"),
                    dicas = sprintf("%s é par de referência para %d municípios", f$municipio, as.integer(f$n_vezes_referencia)), pl = 300, pr = 60)))
}

# ---- 9. Evolução (Malmquist) --------------------------------------------------------------------------
# Transições anuais do estado: EC (componente de gestão, em destaque) e MI (produtividade)
svg_evolucao <- function(modelo, grupo = "todos") {
  x <- mq_estado(modelo, grupo); x <- x[x$tipo_periodo == "transicao", ]
  if (nrow(x) < 2) return("")
  x$ano <- as.integer(substr(x$periodo, 6, 9)); x <- x[order(x$ano), ]
  pct <- function(v) 100 * (v - 1)
  svg_linhas(list(
    list(nome = "Aproximação às melhores práticas (EC, gestão)", cor = COR[["mun"]], larg = 3, dash = "", x = x$ano, y = pct(x$ec)),
    list(nome = "Produtividade total (índice de Malmquist)", cor = COR[["sec"]], larg = 2, dash = "6,4", x = x$ano, y = pct(x$mi)),
    list(nome = "Sem mudança", cor = COR[["mt"]], larg = 1.2, dash = "2,3", x = x$ano, y = rep(0, nrow(x)))),
    fmt = "pct1", titulo = paste0("Variação anual média dos municípios (média geométrica), ", min(x$ano) - 1, "–", max(x$ano)))
}

# Janelas do estado: EC e MI médios anuais, municípios com tendência consistente
tabela_janelas <- function(modelo, grupo = "todos") {
  x <- mq_estado(modelo, grupo); x <- x[x$tipo_periodo == "janela", ]
  if (nrow(x) == 0) return(p(class = "nota-fonte", "Sem Malmquist para este modelo."))
  x <- x[order(match(x$periodo, c("2020-2022", "2022-2025", "2020-2025"))), ]
  d <- tibble::tibble(Período = sub("-", "–", x$periodo), n = x$n, EC = x$ec, MI = x$mi,
                      Melhora = x$n_melhora_ec, Piora = x$n_piora_ec)
  reactable(d, compact = TRUE, pagination = FALSE, sortable = FALSE,
            columns = list(Período = colDef(minWidth = 90), n = colDef(name = "Municípios", align = "center"),
              EC = colDef(name = "Aproximação às melhores práticas (EC)", align = "right", minWidth = 150, cell = function(v) var_ano(v)),
              MI = colDef(name = "Produtividade (Malmquist)", align = "right", minWidth = 130, cell = function(v) var_ano(v)),
              Melhora = colDef(name = "Melhora consistente", align = "center", cell = function(v) num(v)),
              Piora = colDef(name = "Piora consistente", align = "center", cell = function(v) num(v))))
}

# EC 2022–2025 por região de saúde (barras em % ao ano; linha = estado)
ec_por_regiao <- function(modelo, grupo = "todos", periodo = "2022-2025") {
  x <- MQREG[MQREG$modelo == modelo & MQREG$grupo == grupo & MQREG$nivel == "regiao" & MQREG$periodo == periodo & is.finite(MQREG$ec), ]
  if (nrow(x) == 0) return(HTML(""))
  x <- x[order(-x$ec), ]; est <- mq_janela(modelo, periodo, grupo)
  HTML(svg_barras_h(paste0(x$regiao_saude, " (", x$n, ")"), 100 * (x$ec - 1), "pct1",
                    titulo = paste0("Aproximação às melhores práticas por região de saúde, média anual ", sub("-", "–", periodo)),
                    refs = list(list(v = 100 * (est$ec - 1), cor = COR[["mun"]], rot = paste0("Mato Grosso: ", var_ano(est$ec)))),
                    dicas = sprintf("%s: EC %s (%d municípios)", x$regiao_saude, var_ano(x$ec), as.integer(x$n)), pl = 230, pr = 70))
}

# ---- 10. Visão geral ----------------------------------------------------------------------------------
# Cartão de um modelo com números de 2025 (resumo_modelos.csv) e link à página
cartao_modelo <- function(modelo, ano = ANO_EF) {
  im <- info_modelo(modelo); r <- resumo_mod(modelo, ano)
  if (is.na(r$modelo)) return(NULL)
  ec <- mq_janela(modelo, "2022-2025")
  valor <- if (modelo == "M3") sprintf("%d de %d", as.integer(r$n_avaliados), as.integer(r$n_unidades)) else sprintf("%d na fronteira", as.integer(r$n_fronteira))
  linha1 <- if (modelo == "M3") "regiões de saúde com escore diagnóstico publicável" else
    sprintf("de %d %s avaliados · mediana do escore corrigido %s", as.integer(r$n_avaliados), im$unidade, num(r$mediana_escore, 3))
  linha2 <- if (modelo == "M3") "o produto gerencial é o painel regional de acesso e produção" else
    if (!is.na(ec$ec)) sprintf("EC 2022–2025: %s · IC cruza a faixa vizinha: %d", var_ano(ec$ec), as.integer(r$n_ic_cruza_faixa)) else ""
  a(class = "cartao", href = im$pagina, h4(im$curto), div(class = "kpi-valor", valor), p(linha1), p(class = "sub", linha2))
}
cartoes_modelos <- function(ano = ANO_EF) div(class = "cartoes cartoes-ef", lapply(MODELOS_EF$modelo, cartao_modelo, ano = ano))

# Distribuição das faixas por modelo (2025), a partir de resumo_modelos.csv
faixas_por_modelo <- function(ano = ANO_EF, modelos = c("M1", "M0", "M2", "M2A", "H")) {
  r <- RESMOD[RESMOD$ano == ano & RESMOD$grupo == "todos" & RESMOD$modelo %in% modelos, ]
  r <- r[match(intersect(modelos, r$modelo), r$modelo), ]
  mat <- as.matrix(r[, COL_RES_FAIXA]); colnames(mat) <- FAIXAS
  rot <- vapply(r$modelo, function(m) info_modelo(m)$curto, character(1))
  HTML(svg_faixas_barras(rot, mat, titulo = paste0("Unidades avaliadas por faixa, por modelo, ", ano),
                         hrefs = vapply(r$modelo, function(m) info_modelo(m)$pagina, character(1)), pl = 220))
}

# Tabela-resumo: modelo × ano (e grupos do M2A e do H)
tabela_resumo_modelos <- function() {
  r <- RESMOD[RESMOD$modelo != "M3", ]
  r <- r[order(match(r$modelo, MODELOS_EF$modelo), r$grupo != "todos", r$grupo, -r$ano), ]
  d <- tibble::tibble(Modelo = vapply(r$modelo, function(m) info_modelo(m)$curto, character(1)),
                      Grupo = ifelse(r$grupo == "todos", "todos", r$rotulo_grupo), Ano = r$ano,
                      Unidades = r$n_unidades, Avaliados = r$n_avaliados, Fronteira = r$n_fronteira,
                      Mediana = r$mediana_escore, Media = r$media_escore, IC = r$n_ic_cruza_faixa, Registro = r$n_registro_a_verificar,
                      EC = r$mq_ec, MI = r$mq_mi)
  reactable(d, compact = TRUE, striped = TRUE, filterable = TRUE, defaultPageSize = 12, showPageSizeOptions = TRUE,
            pageSizeOptions = c(12, 30, nrow(d)), wrap = TRUE,
            columns = list(Modelo = colDef(minWidth = 150), Grupo = colDef(minWidth = 140), Ano = colDef(align = "center", minWidth = 60),
              Unidades = colDef(align = "center", minWidth = 75, filterable = FALSE), Avaliados = colDef(align = "center", minWidth = 75, filterable = FALSE),
              Fronteira = colDef(name = "Na fronteira", align = "center", minWidth = 75, filterable = FALSE),
              Mediana = colDef(name = "Mediana do escore corrigido", align = "right", minWidth = 95, filterable = FALSE, cell = function(v) f3(v)),
              Media = colDef(name = "Média do escore corrigido", align = "right", minWidth = 95, filterable = FALSE, cell = function(v) f3(v)),
              IC = colDef(name = "IC cruza a faixa vizinha", align = "center", minWidth = 85, filterable = FALSE),
              Registro = colDef(name = "Registro a verificar", align = "center", minWidth = 85, filterable = FALSE),
              EC = colDef(name = "EC na transição do ano anterior", align = "right", minWidth = 105, filterable = FALSE, cell = function(v) var_ano(v, sufixo = "")),
              MI = colDef(name = "Malmquist na transição do ano anterior", align = "right", minWidth = 110, filterable = FALSE, cell = function(v) var_ano(v, sufixo = ""))))
}

# Rodapé de fontes da seção
fonte_eficiencia <- function(prefixo = "../", extra = NULL) {
  p(class = "nota-fonte",
    sprintf("Fonte: %s — estimação DEA (modelo BCC orientado ao produto, escore corrigido por ", CITACAO_EF), tags$em("bootstrap", .noWS = "outside"),
    sprintf(", IC de %s%%) e índice de Malmquist, Projeto PPSUS-MT, com base em dados do SIOPS, CNES, SISAB, SI-PNI, SIA, SIH e IBGE, 2020–%d. Nota: os valores monetários estão expressos em R$ de 2025 (IPCA). ",
            num(100 * IC_NIVEL, 0), ANO_EF), extra,
    "O método é descrito em ", a(href = paste0(prefixo, "metodologia.html"), "Metodologia", .noWS = "after"),
    ", e os arquivos completos (fichas, metas, pares e dicionário) encontram-se em ", a(href = paste0(prefixo, "arquivos/dados/eficiencia/fichas_municipio.csv"), "fichas_municipio.csv", .noWS = "after"),
    " e nos demais arquivos da página ", a(href = paste0(prefixo, "dados/index.html"), "Dados", .noWS = "after"), ".")
}

# Atalhos para as seções da própria página
secoes_pagina <- function(secoes) tags$nav(class = "nav-mun", `aria-label` = "Seções desta página",
  span(class = "sub", "Nesta página:"),
  lapply(names(secoes), function(id) a(class = "btn btn-sm btn-outline-secondary", href = paste0("#", id), secoes[[id]])))

# Lista "a, b e c"
lista_e_ef <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")

# Municípios fora do modelo no ano (para o texto das páginas)
fora_do_modelo <- function(modelo, ano = ANO_EF, grupo = NULL) {
  f <- fichas_modelo(modelo, ano, grupo); f[is.na(f$situacao) | f$situacao != "avaliado", ]
}
