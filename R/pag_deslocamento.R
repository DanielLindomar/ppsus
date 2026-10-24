# =============================================================================
# Observatório PPSUS-MT — funções da página deslocamento/index.qmd
#
# Carregar DEPOIS de R/funcoes.R (que não deve ser editado). Usa os objetos já
# lidos por funcoes.R: DESL, FLUXO, FLUXOREG, POLOS, RESDESL, CENT, GEO, MUN, REG
# (contratos de dados_site/, BRIEF seção 3) e, na seção 7, lê os arquivos fuga_*.csv
# (internações de residentes de MT em outros estados, versão 0.3), com os contratos
# acrescentados a CONTRATOS aqui mesmo.
#
# Índice
#   1. Constantes e formatação
#   2. Fluxos por nível (município → município), polos por nível
#   3. KPIs e blocos por nível (grade, barra empilhada, séries)
#   4. Matriz região × região (tabela-calor)
#   5. Mapa de fluxos com seletor de nível (um só mapa, grupos de camadas)
#   6. Tabelas: ranking dos polos, municípios dependentes, todos os municípios
#   7. Internações em outros estados: KPIs, barras por UF, série, saldo, regiões,
#      municípios e principais destinos (com supressão de células < 5)
# =============================================================================

ANO_DESL    <- 2025L
NIVEIS_DESL <- c(total = "Total", MC = "Média complexidade", AC = "Alta complexidade")
PARTES      <- c(proprio = "Próprio município", mesma = "Outro município da mesma região", outra = "Outra região de saúde")
COR_PARTES  <- c(COR[["mun"]], COR[["sec"]], COR[["mt"]])
COR_NIVEIS  <- c(total = COR[["mun"]], MC = COR[["sec"]], AC = "#b45309")

# ---- 1. Formatação ------------------------------------------------------------------
pct_txt <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), "%"))
km_txt  <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), " km"))
saldo_txt <- function(v) ifelse(is.na(v), "—", ifelse(v > 0, paste0("+", num(v)), ifelse(v < 0, paste0("−", num(abs(v))), "0")))
nome_ou_traco <- function(x) ifelse(is.na(x) | !nzchar(x), "—", x)
regiao_mun <- function(cod) nome_regiao(regiao_de(cod))
link_mun <- function(cod, prefixo = "../municipios/") a(href = url_mun(cod, prefixo), nome_mun(cod))

# ---- 2. Fluxos e polos por nível -------------------------------------------------------
# Fluxos município de residência → município de internação, somados no nível (total = MC + AC)
fluxo_nivel <- function(nivel = "total", ano = ANO_DESL) {
  f <- FLUXO[FLUXO$ano == ano, ]
  if (nivel != "total") f <- f[f$nivel == nivel, ]
  f |> group_by(cod_origem, cod_destino) |> summarise(internacoes = sum(internacoes, na.rm = TRUE), .groups = "drop")
}

# Polos (municípios de atendimento) em um nível: recebidas, de fora, % de fora, nº de origens,
# principal origem externa e saldo (recebidas − internações de residentes no mesmo nível).
# No nível total usa polos_ano.csv (contrato); nos demais, deriva de fluxo_mun_ano.csv.
polos_nivel <- function(nivel = "total", ano = ANO_DESL) {
  f <- fluxo_nivel(nivel, ano)
  if (nrow(f) == 0) return(tibble::tibble(cod_mun6 = integer(0)))
  ext <- f[f$cod_origem != f$cod_destino, ]
  orig <- ext |> group_by(cod_destino) |> arrange(desc(internacoes)) |>
    summarise(n_origens = n(), origem_principal = nome_mun(first(cod_origem)),
              pct_origem_principal = 100 * first(internacoes) / sum(internacoes), .groups = "drop")
  res <- f |> group_by(cod_origem) |> summarise(res = sum(internacoes), .groups = "drop")
  if (nivel == "total" && nrow(POLOS)) {
    p <- POLOS[POLOS$ano == ano, ] |>
      transmute(cod_mun6, internacoes_recebidas, recebidas_de_fora, pct_recebidas_de_fora, n_origens, saldo, internacoes_ac_recebidas) |>
      left_join(select(orig, cod_mun6 = cod_destino, origem_principal, pct_origem_principal), by = "cod_mun6")
  } else {
    p <- f |> group_by(cod_mun6 = cod_destino) |>
      summarise(internacoes_recebidas = sum(internacoes), recebidas_de_fora = sum(internacoes[cod_origem != cod_destino]), .groups = "drop") |>
      mutate(pct_recebidas_de_fora = 100 * recebidas_de_fora / internacoes_recebidas) |>
      left_join(select(orig, cod_mun6 = cod_destino, n_origens, origem_principal, pct_origem_principal), by = "cod_mun6") |>
      left_join(select(res, cod_mun6 = cod_origem, res), by = "cod_mun6") |>
      mutate(n_origens = ifelse(is.na(n_origens), 0L, n_origens), saldo = internacoes_recebidas - ifelse(is.na(res), 0, res),
             internacoes_ac_recebidas = NA_real_) |> select(-res)
  }
  p |> arrange(desc(internacoes_recebidas)) |> mutate(pos = row_number())
}

# ---- 3. KPIs e blocos por nível ------------------------------------------------------------
# Grade de cinco cartões com o resumo do nível (resumo_deslocamento_ano.csv)
kpis_nivel <- function(nivel = "total", ano = ANO_DESL) {
  r <- resumo_desl(ano, nivel); r0 <- resumo_desl(min(ANOS), nivel)
  if (is.null(r)) return(p(class = "nota-fonte", "Resumo indisponível para este nível."))
  comp <- function(v, f = pct_txt) if (!is.null(r0)) paste0(f(v), " em ", r0$ano) else NULL
  div(class = "kpi-grade",
      kpi_simples("Internações de residentes de MT", num(r$internacoes), paste0("AIH tipo 1 · ", ano), comp(r0$internacoes, num)),
      kpi_simples("No próprio município", pct_txt(r$pct_proprio_mun), paste0("das internações · ", ano), comp(r0$pct_proprio_mun)),
      kpi_simples("Em outro município da mesma região", pct_txt(r$pct_mesma_regiao), paste0("das internações · ", ano), comp(r0$pct_mesma_regiao)),
      kpi_simples("Em outra região de saúde", pct_txt(r$pct_outra_regiao), paste0("das internações · ", ano), comp(r0$pct_outra_regiao)),
      kpi_simples("Distância média residência–hospital", km_txt(r$km_medio), paste0("linha reta entre as sedes municipais (IBGE) · ", ano), comp(r0$km_medio, km_txt)))
}

# Barra empilhada 100% com as três parcelas do nível no ano
barra_partes <- function(nivel = "total", ano = ANO_DESL) {
  r <- resumo_desl(ano, nivel); if (is.null(r)) return("")
  v <- c(r$pct_proprio_mun, r$pct_mesma_regiao, r$pct_outra_regiao); names(v) <- PARTES
  HTML(svg_barra_empilhada(v, cores = COR_PARTES, titulo = sprintf("Onde se internaram os residentes de Mato Grosso — %s, %d", NIVEIS_DESL[[nivel]], ano)))
}

# Série 2020–2025 das três parcelas de um nível
serie_partes <- function(nivel = "total") {
  r <- RESDESL[tolower(RESDESL$nivel) == tolower(nivel) & RESDESL$ano %in% ANOS, ] |> arrange(ano)
  if (nrow(r) < 2) return("")
  HTML(svg_linhas(list(
    list(nome = PARTES[["proprio"]], cor = COR_PARTES[1], larg = 2.8, dash = "", x = r$ano, y = r$pct_proprio_mun),
    list(nome = PARTES[["mesma"]], cor = COR_PARTES[2], larg = 2.2, dash = "", x = r$ano, y = r$pct_mesma_regiao),
    list(nome = PARTES[["outra"]], cor = COR_PARTES[3], larg = 2.2, dash = "6,4", x = r$ano, y = r$pct_outra_regiao)),
    fmt = "pct1", titulo = sprintf("Parcela das internações por local de atendimento — %s, 2020–2025", NIVEIS_DESL[[nivel]]), h = 240))
}

# Série 2020–2025 de um campo do resumo, uma linha por nível (Total, MC, AC)
serie_por_nivel <- function(campo, titulo, fmt = "pct1", transf = identity) {
  series <- lapply(names(NIVEIS_DESL), function(nv) {
    r <- RESDESL[tolower(RESDESL$nivel) == tolower(nv) & RESDESL$ano %in% ANOS, ] |> arrange(ano)
    if (nrow(r) == 0) return(NULL)
    list(nome = NIVEIS_DESL[[nv]], cor = COR_NIVEIS[[nv]], larg = if (nv == "total") 2.8 else 2, dash = if (nv == "AC") "6,4" else "",
         x = r$ano, y = transf(r[[campo]]))
  })
  series <- Filter(Negate(is.null), series)
  if (length(series) == 0) return("")
  HTML(svg_linhas(series, fmt = fmt, titulo = titulo, w = 400, h = 250))
}

# ---- 4. Matriz região × região (tabela-calor) ------------------------------------------------
# Cor de fundo proporcional à raiz da parcela (para que valores pequenos ainda apareçam)
# Texto sempre escuro (#1f2937); o extremo da rampa (#6CA2A4) mantém contraste ≥ 4,5:1 com ele.
# A diagonal é marcada por negrito e borda (classe .diagonal), não por fundo escuro.
cor_calor <- function(p) {
  t <- sqrt(pmin(pmax(p, 0), 100) / 100); t[is.na(t)] <- 0
  m <- grDevices::colorRamp(c("#ffffff", "#cfe0df", "#8CBFBD", "#6CA2A4"))(t)
  list(bg = grDevices::rgb(m[, 1], m[, 2], m[, 3], maxColorValue = 255), txt = rep("#1f2937", length(t)))
}

# Matriz 16 × 16: linhas = região de residência, colunas = região de internação,
# célula = % das internações dos residentes da região de origem. Colunas extras:
# internações, % fora da região e principal destino externo.
matriz_regioes <- function(nivel = "total", ano = ANO_DESL) {
  f <- FLUXOREG[FLUXOREG$ano == ano, ]
  if (nivel != "total") f <- f[f$nivel == nivel, ]
  if (nrow(f) == 0 || nrow(REG) == 0) return(p(class = "nota-fonte", "Não há fluxos entre regiões de saúde para este nível."))
  regs <- REG[ordem_nome(REG$regiao_saude), ]
  cod <- regs$co_regsaud; nm <- regs$regiao_saude; k <- length(cod)
  a <- f |> filter(co_reg_origem %in% cod, co_reg_destino %in% cod) |>
    group_by(co_reg_origem, co_reg_destino) |> summarise(n = sum(internacoes, na.rm = TRUE), .groups = "drop")
  M <- matrix(0, k, k, dimnames = list(cod, cod))
  M[cbind(match(a$co_reg_origem, cod), match(a$co_reg_destino, cod))] <- a$n
  tot <- rowSums(M); P <- 100 * M / tot; P[!is.finite(P)] <- NA
  fora <- ifelse(tot > 0, 100 * (tot - diag(M)) / tot, NA)
  cabecalho <- tags$tr(
    tags$th(class = "linha", style = "writing-mode:horizontal-tb;transform:none;height:auto;vertical-align:bottom;",
            HTML("Região de residência&nbsp;↓ &nbsp;·&nbsp; região de internação&nbsp;→")),
    lapply(nm, tags$th), tags$th("Internações de residentes"), tags$th("% fora da região"),
    tags$th(style = "writing-mode:horizontal-tb;transform:none;height:auto;vertical-align:bottom;", "Principal destino externo"))
  linhas <- lapply(seq_len(k), function(i) {
    cel <- lapply(seq_len(k), function(j) {
      v <- P[i, j]; c_ <- cor_calor(v)
      txt <- if (is.na(v) || M[i, j] == 0) "" else if (v < 0.05) "<0,1" else num(v, 1)
      tags$td(class = if (i == j) "diagonal" else NULL, style = sprintf("background:%s;color:%s;", c_$bg, c_$txt),
              `data-tip` = sprintf("%s → %s: %s internações (%s dos residentes de %s)", nm[i], nm[j], num(M[i, j]), pct_txt(v), nm[i]), txt)
    })
    ext <- replace(M[i, ], i, -1); j <- which.max(ext)
    principal <- if (tot[i] > 0 && ext[j] > 0) sprintf("%s (%s)", nm[j], pct_txt(P[i, j])) else "—"
    tags$tr(tags$th(class = "linha", nm[i]), cel,
            tags$td(style = "text-align:right;", num(tot[i])), tags$td(style = "text-align:right;font-weight:600;", pct_txt(fora[i])),
            tags$td(style = "text-align:left;", principal))
  })
  tagList(div(class = "rolagem-x", tags$table(class = "matriz-calor", `aria-label` = sprintf("Matriz de fluxos entre regiões de saúde — %s, %d", NIVEIS_DESL[[nivel]], ano),
                                              tags$thead(cabecalho), tags$tbody(linhas))),
          p(class = "nota-fonte", sprintf("Fonte: SIH/SUS. Nota: Cada linha soma 100%% das internações dos residentes da região (%s, %d). A diagonal, em negrito e com borda, corresponde à parcela atendida na própria região de saúde, e a intensidade da cor segue a raiz quadrada da parcela, para que os fluxos pequenos permaneçam visíveis. O número de internações de cada célula pode ser consultado ao posicionar o cursor sobre ela.", NIVEIS_DESL[[nivel]], ano)))
}

# ---- 5. Mapa de fluxos com seletor de nível ---------------------------------------------------
# Um único mapa (GeoJSON embutido, sem camada externa) com três grupos de camadas — Total,
# Média e Alta complexidade — trocados pelo controle no canto: polylines origem → destino dos
# n_max maiores fluxos intermunicipais (espessura ∝ internações) e círculos nos polos
# (raio ∝ internações recebidas de outros municípios), com rótulos fixos nos n_rot maiores polos.
mapa_fluxos_niveis <- function(ano = ANO_DESL, n_max = 80, n_rot = 6, altura = 560, prefixo = "../municipios/") {
  if (nrow(GEO) == 0 || nrow(CENT) == 0) return(sem_mapa())
  bb <- bbox_num(GEO)
  m <- mapa_vazio(altura) |>
    addPolygons(data = GEO, layerId = ~slug, fillColor = COR[["claro"]], fillOpacity = 1, color = "#ffffff", weight = 0.8,
                label = ~paste0(municipio, " · ", regiao_saude, " — o clique abre o perfil")) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4])
  cobertura <- c()
  for (nv in names(NIVEIS_DESL)) {
    g <- NIVEIS_DESL[[nv]]
    f <- fluxo_nivel(nv, ano) |> filter(cod_origem != cod_destino, is.finite(internacoes), internacoes > 0)
    total_fora <- sum(f$internacoes)
    f <- f |> arrange(desc(internacoes)) |> slice_head(n = n_max) |>
      left_join(rename(CENT, lon_o = lon, lat_o = lat), by = c("cod_origem" = "cod_mun6")) |>
      left_join(rename(CENT, lon_d = lon, lat_d = lat), by = c("cod_destino" = "cod_mun6")) |>
      filter(is.finite(lon_o), is.finite(lon_d))
    cobertura[nv] <- if (total_fora > 0) 100 * sum(f$internacoes) / total_fora else NA
    if (nrow(f)) {
      vmax <- max(f$internacoes)
      geom <- sf::st_sfc(lapply(seq_len(nrow(f)), function(i)
        sf::st_linestring(matrix(c(f$lon_o[i], f$lat_o[i], f$lon_d[i], f$lat_d[i]), ncol = 2, byrow = TRUE))), crs = 4326)
      sfl <- sf::st_sf(w = 1 + 7 * sqrt(f$internacoes / vmax),
                       lab = sprintf("%s → %s: %s internações (%s)", nome_mun(f$cod_origem), nome_mun(f$cod_destino), num(f$internacoes), g),
                       geometry = geom)
      m <- addPolylines(m, data = sfl, weight = ~w, color = COR[["sec"]], opacity = 0.6, label = ~lab, group = g,
                        highlightOptions = highlightOptions(color = COR[["mun"]], opacity = 1, bringToFront = TRUE))
    }
    pz <- polos_nivel(nv, ano) |> filter(is.finite(recebidas_de_fora), recebidas_de_fora > 0) |>
      left_join(CENT, by = "cod_mun6") |> filter(is.finite(lon))
    if (nrow(pz)) {
      rmax <- max(pz$recebidas_de_fora)
      pz <- pz |> mutate(raio = 4 + 18 * sqrt(recebidas_de_fora / rmax),
                         lab = sprintf("%s: %s internações recebidas de outros municípios (%s das %s recebidas; %s)",
                                       nome_mun(cod_mun6), num(recebidas_de_fora), pct_txt(pct_recebidas_de_fora), num(internacoes_recebidas), g))
      m <- addCircleMarkers(m, data = pz, lng = ~lon, lat = ~lat, radius = ~raio, color = COR[["mun"]], weight = 1,
                            fillColor = COR[["mun"]], fillOpacity = 0.5, label = ~lab, group = g)
      rot <- head(pz, n_rot)
      # rótulo à esquerda quando há um polo maior a menos de 0,6° (ex.: Várzea Grande, cuja sede
      # fica a cerca de 0,06° a oeste e 0,1° ao sul da sede de Cuiabá)
      for (i in seq_len(nrow(rot))) {
        perto <- i > 1 && any(abs(rot$lon[seq_len(i - 1)] - rot$lon[i]) < 0.6 & abs(rot$lat[seq_len(i - 1)] - rot$lat[i]) < 0.6)
        m <- addLabelOnlyMarkers(m, lng = rot$lon[i], lat = rot$lat[i], label = nome_mun(rot$cod_mun6[i]), group = g,
                                 labelOptions = labelOptions(noHide = TRUE, direction = if (perto) "left" else "right",
                                                             offset = c(if (perto) -6 else 6, 0), textOnly = TRUE,
                                                             style = list("font-weight" = "600", "font-size" = "11px", "color" = "#0E5A5E",
                                                                          "text-shadow" = "0 0 3px #fff, 0 0 3px #fff")))
      }
    }
  }
  legenda <- sprintf(paste0(
    "<div style='font-size:.78rem;line-height:1.3;max-width:230px'><b>Legenda</b><br>",
    "<svg width='40' height='10' aria-hidden='true'><line x1='0' x2='40' y1='5' y2='5' stroke='%s' stroke-width='4' opacity='.7'/></svg> ",
    "%d maiores fluxos entre municípios em %d (espessura ∝ internações)<br>",
    "<svg width='14' height='14' aria-hidden='true'><circle cx='7' cy='7' r='6' fill='%s' fill-opacity='.5' stroke='%s'/></svg> ",
    "polo de atendimento (tamanho ∝ internações recebidas de outros municípios)<br>",
    "O posicionamento do cursor exibe os valores, e o clique em um município abre o perfil.</div>"),
    COR[["sec"]], n_max, ano, COR[["mun"]], COR[["mun"]])
  m <- m |>
    addLayersControl(baseGroups = unname(NIVEIS_DESL), position = "topleft", options = layersControlOptions(collapsed = FALSE)) |>
    addControl(html = legenda, position = "bottomright") |>
    htmlwidgets::onRender(js_clique(prefixo))
  attr(m, "cobertura") <- cobertura
  m
}

# Cobertura (% das internações fora do município) dos n_max maiores fluxos de cada nível
cobertura_fluxos <- function(ano = ANO_DESL, n_max = 80) {
  sapply(names(NIVEIS_DESL), function(nv) {
    f <- fluxo_nivel(nv, ano) |> filter(cod_origem != cod_destino, internacoes > 0) |> arrange(desc(internacoes))
    if (nrow(f) == 0) return(NA_real_)
    100 * sum(head(f$internacoes, n_max)) / sum(f$internacoes)
  })
}

# ---- 6. Tabelas ------------------------------------------------------------------------------
# Ranking dos polos de atendimento (reactable)
tabela_polos <- function(nivel = "total", ano = ANO_DESL, prefixo = "../municipios/", tamanho = 15) {
  pl <- polos_nivel(nivel, ano)
  if (nrow(pl) == 0) return(p(class = "nota-fonte", "Não há polos de atendimento para este nível."))
  d <- pl |> transmute(Posição = pos, cod = cod_mun6, Município = nome_mun(cod_mun6), `Região de saúde` = regiao_mun(cod_mun6),
                      Recebidas = internacoes_recebidas, `De fora` = recebidas_de_fora, `% de fora` = pct_recebidas_de_fora,
                      Origens = n_origens, `Principal origem` = ifelse(is.na(origem_principal), "—", sprintf("%s (%s)", origem_principal, pct_txt(pct_origem_principal))),
                      Saldo = saldo, AC = internacoes_ac_recebidas)
  cols <- list(cod = colDef(show = FALSE),
    Posição = colDef(align = "center", minWidth = 55, cell = function(v) ordinal(v)),
    Município = colDef(minWidth = 140, sticky = "left", cell = function(v, i) a(href = url_mun(d$cod[i], prefixo), v)),
    `Região de saúde` = colDef(minWidth = 120),
    Recebidas = colDef(name = "Internações recebidas", align = "right", minWidth = 90, cell = function(v) num(v)),
    `De fora` = colDef(name = "De outros municípios", align = "right", minWidth = 90, cell = function(v) num(v)),
    `% de fora` = colDef(align = "right", minWidth = 70, cell = function(v) pct_txt(v)),
    Origens = colDef(name = "Municípios de origem (sem o próprio)", align = "center", minWidth = 90, cell = function(v) num(v)),
    `Principal origem` = colDef(name = "Principal origem (entre as de fora)", minWidth = 150),
    Saldo = colDef(name = "Saldo (recebidas − residentes)", align = "right", minWidth = 100, cell = function(v) saldo_txt(v)),
    AC = colDef(name = "Alta compl. recebida", align = "right", minWidth = 85, cell = function(v) num(v), show = nivel == "total"))
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE, searchable = TRUE, defaultPageSize = tamanho,
            showPageSizeOptions = TRUE, pageSizeOptions = c(15, 30, nrow(d)), columns = cols))
}

# Base municipal do ano com nomes, região, população e hospital SUS
desl_ano <- function(ano = ANO_DESL) {
  DESL[DESL$ano == ano, ] |>
    left_join(select(MUN, cod_mun6, municipio, slug, regiao_saude, populacao_2025, tem_hospital_sus_2025), by = "cod_mun6")
}

# Municípios mais dependentes: maior % fora do município (entre os que têm atendimento local e
# ao menos min_int internações de residentes) ou maior distância média (ao menos min_int internações)
tabela_dependentes <- function(criterio = c("pct", "km"), ano = ANO_DESL, n = 10, min_int = 500, prefixo = "../municipios/") {
  criterio <- match.arg(criterio)
  d <- desl_ano(ano) |> filter(internacoes_res >= min_int)
  d <- if (criterio == "pct") d |> filter(no_proprio_mun > 0) |> arrange(desc(pct_internacoes_fora_mun)) else d |> arrange(desc(km_medio_internacao))
  d <- head(d, n)
  if (nrow(d) == 0) return(p(class = "nota-fonte", "Não há municípios que atendam a este critério no ano."))
  t <- d |> transmute(cod = cod_mun6, Município = municipio, `Região de saúde` = regiao_saude, População = populacao_2025,
                      Internações = internacoes_res, `% fora` = pct_internacoes_fora_mun, `km médio` = km_medio_internacao,
                      Destino = ifelse(is.na(destino_principal_nome), "—", sprintf("%s (%s)", destino_principal_nome, pct_txt(pct_destino_principal))))
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE,
            columns = list(cod = colDef(show = FALSE),
              Município = colDef(minWidth = 140, sticky = "left", cell = function(v, i) a(href = url_mun(t$cod[i], prefixo), v)),
              `Região de saúde` = colDef(minWidth = 120),
              População = colDef(name = "População 2025", align = "right", minWidth = 80, cell = function(v) num(v)),
              Internações = colDef(name = "Internações de residentes", align = "right", minWidth = 90, cell = function(v) num(v)),
              `% fora` = colDef(name = "% fora do município", align = "right", minWidth = 80, cell = function(v) pct_txt(v),
                                style = if (criterio == "pct") list(fontWeight = 600) else NULL),
              `km médio` = colDef(name = "Distância média", align = "right", minWidth = 80, cell = function(v) km_txt(v),
                                  style = if (criterio == "km") list(fontWeight = 600) else NULL),
              Destino = colDef(name = "Destino principal", minWidth = 160))))
}

# Todos os municípios no ano (residência e atendimento), com busca, ordenação e download
tabela_todos_municipios <- function(ano = ANO_DESL, prefixo = "../municipios/", id_html = "tab-desl-mun") {
  d <- desl_ano(ano) |> arrange(ordem_nome(municipio))
  if (nrow(d) == 0) return(p(class = "nota-fonte", "Não há dados de deslocamento para o ano."))
  t <- d |> transmute(cod = cod_mun6, Município = municipio, `Região de saúde` = regiao_saude, `População 2025` = populacao_2025,
                      `Hospital SUS` = ifelse(is.na(tem_hospital_sus_2025), "—", ifelse(tem_hospital_sus_2025 == 1, "sim", "não")),
                      `Internações de residentes` = internacoes_res, `% no próprio município` = pct_proprio_mun,
                      `% na mesma região` = pct_mesma_regiao, `% em outra região` = pct_outra_regiao, `km médio` = km_medio_internacao,
                      `Destino principal` = nome_ou_traco(destino_principal_nome), `% no destino principal` = pct_destino_principal,
                      `Internações recebidas` = internacoes_recebidas, `Recebidas de fora` = recebidas_de_fora, `% recebidas de fora` = pct_recebidas_de_fora,
                      `Principal origem` = nome_ou_traco(origem_principal_nome))
  num_col <- function(nome, f = num, ...) colDef(name = nome, align = "right", minWidth = 90, cell = function(v) f(v), ...)
  tagList(
    tags$button(class = "btn btn-sm btn-outline-primary mb-2", onclick = sprintf("Reactable.downloadDataCSV('%s', 'ppsus-mt_deslocamento_%d.csv')", id_html, ano),
                sprintf("Baixar a tabela (CSV, %d)", ano)),
    div(class = "rolagem-x", reactable(t, elementId = id_html, compact = TRUE, striped = TRUE, highlight = TRUE, searchable = TRUE, defaultPageSize = 20,
              showPageSizeOptions = TRUE, pageSizeOptions = c(20, 50, nrow(t)),
              columnGroups = list(colGroup(name = "Como residência (onde os moradores se internam)", columns = c("Internações de residentes", "% no próprio município", "% na mesma região", "% em outra região", "km médio", "Destino principal", "% no destino principal")),
                                  colGroup(name = "Como atendimento (quem o município recebe)", columns = c("Internações recebidas", "Recebidas de fora", "% recebidas de fora", "Principal origem"))),
              columns = list(cod = colDef(show = FALSE),
                Município = colDef(minWidth = 150, sticky = "left", cell = function(v, i) a(href = url_mun(t$cod[i], prefixo), v)),
                `Região de saúde` = colDef(minWidth = 130), `População 2025` = num_col("População 2025"),
                `Hospital SUS` = colDef(name = "Hospital SUS (2025)", align = "center", minWidth = 80),
                `Internações de residentes` = num_col("Internações de residentes"),
                `% no próprio município` = num_col("% no próprio município", pct_txt), `% na mesma região` = num_col("% na mesma região", pct_txt),
                `% em outra região` = num_col("% em outra região", pct_txt), `km médio` = num_col("Distância média", km_txt),
                `Destino principal` = colDef(minWidth = 130), `% no destino principal` = num_col("% no destino principal", pct_txt),
                `Internações recebidas` = num_col("Internações recebidas"), `Recebidas de fora` = num_col("Recebidas de outros municípios"),
                `% recebidas de fora` = num_col("% recebidas de fora", pct_txt), `Principal origem` = colDef(minWidth = 130)))))
}

# Lista (nomes com internações) dos municípios sem nenhuma internação em estabelecimento próprio no ano
lista_sem_local <- function(ano = ANO_DESL, prefixo = "../municipios/") {
  d <- desl_ano(ano) |> filter(internacoes_res > 0, no_proprio_mun == 0) |> arrange(desc(internacoes_res))
  if (nrow(d) == 0) return(NULL)
  tags$details(class = "nota-fonte",
    tags$summary(sprintf("Ver os %d municípios sem internação em estabelecimento próprio em %d (internações de residentes entre parênteses)", nrow(d), ano)),
    p(HTML(paste(sprintf('<a href="%s">%s</a> (%s)', url_mun(d$cod_mun6, prefixo), esc(d$municipio), num(d$internacoes_res)), collapse = " · "))))
}

# ---- 7. Internações de residentes de MT em outros estados (versão 0.3) ------------------------
# Arquivos fuga_*.csv (scripts/02_preparar_deslocamento.py, passo 7): SIH/SUS RD de MT e das 26
# outras UF, residentes de MT, AIH tipo 1, ano da alta, 2020–2025. Nos recortes por região e por
# município, contagens de 1 a 4 chegam vazias (supressão do Termo de Uso, com supressão
# complementar): as funções abaixo mostram "suprimido" e nunca recalculam o valor escondido.
CONTRATOS$fuga_resumo_ano <- c(ano = "integer", nivel = "character", internacoes_mt = "numeric",
  internacoes_outra_uf = "numeric", internacoes_total = "numeric", pct_outra_uf = "numeric", valor_mt = "numeric",
  valor_outra_uf = "numeric", pct_valor_outra_uf = "numeric", pct_eletivas_mt = "numeric", pct_eletivas_outra_uf = "numeric",
  uf_principal = "character", nome_uf_principal = "character", pct_uf_principal = "numeric", n_uf_destino = "integer",
  n_mun_destino = "integer", entrada_outra_uf = "numeric", saldo_outra_uf = "numeric")
CONTRATOS$fuga_uf_ano <- c(ano = "integer", cod_uf = "character", uf = "character", nome_uf = "character", nivel = "character",
  internacoes = "numeric", internacoes_urgencia = "numeric", diarias = "numeric", valor_total = "numeric")
CONTRATOS$fuga_saldo_uf_ano <- c(ano = "integer", cod_uf = "character", uf = "character", nome_uf = "character",
  entrada = "numeric", saida = "numeric", saldo = "numeric")
CONTRATOS$fuga_regiao_ano <- c(co_regsaud = "character", regiao_saude = "character", ano = "integer",
  internacoes_total_res = "numeric", internacoes_outra_uf = "numeric", pct_outra_uf = "numeric",
  internacoes_ac_total_res = "numeric", internacoes_ac_outra_uf = "numeric", pct_ac_outra_uf = "numeric",
  uf_principal = "character", nome_uf_principal = "character", pct_uf_principal = "numeric",
  total_suprimido = "integer", ac_suprimida = "integer", nota_supressao = "character")
CONTRATOS$fuga_mun_periodo <- c(cod_mun6 = "integer", municipio = "character", co_regsaud = "character",
  regiao_saude = "character", periodo = "character", internacoes_total_res = "numeric", internacoes_outra_uf = "numeric",
  pct_outra_uf = "numeric", uf_principal = "character", nome_uf_principal = "character", pct_uf_principal = "numeric",
  total_suprimido = "integer", nota_supressao = "character")
CONTRATOS$fuga_destinos_mun <- c(posicao = "integer", cod_mun6 = "integer", municipio = "character", uf = "character",
  nome_uf = "character", periodo = "character", internacoes = "numeric", pct_do_total_fora = "numeric",
  internacoes_ac = "numeric", pct_ac = "numeric", ac_suprimida = "integer", nota_supressao = "character")
FUGARES  <- ler_contrato("fuga_resumo_ano")
FUGAUF   <- ler_contrato("fuga_uf_ano")
FUGASAL  <- ler_contrato("fuga_saldo_uf_ano")
FUGAREG  <- ler_contrato("fuga_regiao_ano")
FUGAMUN  <- ler_contrato("fuga_mun_periodo")
FUGADEST <- ler_contrato("fuga_destinos_mun")
COR_FUGA <- c(MC = COR[["sec"]], AC = "#b45309")
PERIODO_FUGA <- sprintf("%d–%d", min(ANOS), max(ANOS))
TXT_SUPR <- "suprimido"
NOTA_SUPR <- paste0("“Suprimido” designa a célula com menos de 5 internações ou aquela ocultada para que outra célula pequena não ",
                    "possa ser deduzida por diferença, conforme a regra de divulgação do projeto, segundo a qual nenhum recorte por ",
                    "região de saúde ou por município apresenta contagens de 1 a 4.")

# preposição contraída antes do nome da UF ("no Paraná", "na Bahia", "em São Paulo")
PREP_UF <- c("Acre" = "no", "Alagoas" = "em", "Amapá" = "no", "Amazonas" = "no", "Bahia" = "na", "Ceará" = "no", "Distrito Federal" = "no", "Espírito Santo" = "no", "Goiás" = "em", "Maranhão" = "no", "Mato Grosso do Sul" = "em", "Minas Gerais" = "em", "Pará" = "no", "Paraíba" = "na", "Paraná" = "no", "Pernambuco" = "em", "Piauí" = "no", "Rio de Janeiro" = "no", "Rio Grande do Norte" = "no", "Rio Grande do Sul" = "no", "Rondônia" = "em", "Roraima" = "em", "Santa Catarina" = "em", "São Paulo" = "em", "Sergipe" = "em", "Tocantins" = "no", "Mato Grosso" = "em")
em_uf <- function(nome) paste(ifelse(is.na(PREP_UF[nome]), "em", PREP_UF[nome]), nome)
lista_e_pt <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
supr_num <- function(v, f = num) ifelse(is.na(v), TXT_SUPR, f(v))
brl_mi <- function(v) ifelse(is.na(v), "—", paste0("R$ ", num(v / 1e6, 1), " mi"))

# Linha do resumo estadual (ano, nível total | MC | AC)
fuga_res <- function(ano, nivel = "total") {
  d <- FUGARES[FUGARES$ano == ano & tolower(FUGARES$nivel) == tolower(nivel), ]
  if (nrow(d) == 0) NULL else d[1, ]
}

# Internações por UF de destino (ano único ou período somado), com MC, AC e total em colunas
fuga_por_uf <- function(anos = ANO_DESL) {
  FUGAUF[FUGAUF$ano %in% anos, ] |> group_by(cod_uf, uf, nome_uf, nivel) |>
    summarise(internacoes = sum(internacoes), .groups = "drop") |>
    tidyr::pivot_wider(id_cols = c(cod_uf, uf, nome_uf), names_from = nivel, values_from = internacoes,
                       names_prefix = "internacoes_", values_fill = 0) |>
    arrange(desc(internacoes_total), uf)
}

# Saldo por UF (entrada − saída) no ano ou no período
fuga_saldo <- function(anos = ANO_DESL) {
  FUGASAL[FUGASAL$ano %in% anos, ] |> group_by(cod_uf, uf, nome_uf) |>
    summarise(entrada = sum(entrada), saida = sum(saida), saldo = sum(saldo), .groups = "drop")
}

# Cartões da seção
kpis_fuga <- function(ano = ANO_DESL) {
  t <- fuga_res(ano, "total"); ac <- fuga_res(ano, "AC"); t0 <- fuga_res(min(ANOS), "total"); ac0 <- fuga_res(min(ANOS), "AC")
  if (is.null(t)) return(p(class = "nota-fonte", "Dados de internações em outros estados indisponíveis."))
  sp <- fuga_saldo(ANOS); u <- fuga_por_uf(ano); u23 <- u[2:3, ]
  div(class = "kpi-grade",
    kpi_simples("Internações de residentes de MT em outros estados", num(t$internacoes_outra_uf),
                paste0("hospitais das outras 26 UF · ", ano),
                sprintf("%s das internações dos residentes · %s em %d", pct_txt(t$pct_outra_uf), num(t0$internacoes_outra_uf), t0$ano)),
    kpi_simples("Parcela na alta complexidade", pct_txt(ac$pct_outra_uf),
                paste0("das internações de alta complexidade dos residentes · ", ano),
                sprintf("%s internações · %s em %d", num(ac$internacoes_outra_uf), pct_txt(ac0$pct_outra_uf), ac0$ano)),
    kpi_simples("Principal estado de destino", t$nome_uf_principal,
                paste0(pct_txt(t$pct_uf_principal), " das internações em outros estados · ", ano),
                sprintf("seguido de %s", lista_e_pt(sprintf("%s (%s)", u23$nome_uf, pct_txt(100 * u23$internacoes_total / t$internacoes_outra_uf))))),
    kpi_simples("Valor das internações em outros estados", brl_mi(t$valor_outra_uf),
                paste0("valor aprovado das AIH, R$ correntes · ", ano),
                sprintf("%s do valor das internações dos residentes · %s na alta complexidade", pct_txt(t$pct_valor_outra_uf), pct_txt(ac$pct_valor_outra_uf))),
    kpi_simples("Saldo com os outros estados", saldo_txt(t$saldo_outra_uf),
                paste0("internações recebidas − enviadas · ", ano),
                sprintf("%s em %s (%s recebidas; %s enviadas)", saldo_txt(sum(sp$entrada) - sum(sp$saida)), PERIODO_FUGA,
                        num(sum(sp$entrada)), num(sum(sp$saida)))))
}

# Barras horizontais empilhadas (MC + AC) por UF de destino, SVG
svg_barras_pilha_uf <- function(d, titulo, w = 680, lh = 22, pl = 150, pr = 60) {
  d <- d[d$internacoes_total > 0, ]
  n <- nrow(d); if (n == 0) return("")
  vmax <- max(d$internacoes_total); h <- n * lh + 8
  sx <- function(v) v / vmax * (w - pl - pr)
  y0 <- (seq_len(n) - 1) * lh
  dica <- sprintf("%s: %s internações (média complexidade %s; alta complexidade %s)", d$nome_uf, num(d$internacoes_total),
                  num(d$internacoes_MC), num(d$internacoes_AC))
  barras <- paste(sprintf(paste0('<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937">%s</text>',
                                 '<rect x="%d" y="%.1f" width="%.1f" height="%d" fill="%s" data-tip="%s"/>',
                                 '<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s" data-tip="%s"/>',
                                 '<text x="%.1f" y="%.1f" font-size="11" fill="#374151">%s</text>'),
                          pl - 8, y0 + 15, esc(d$nome_uf),
                          pl, y0 + 4, sx(d$internacoes_MC), lh - 7, COR_FUGA[["MC"]], esc(dica),
                          pl + sx(d$internacoes_MC), y0 + 4, sx(d$internacoes_AC), lh - 7, COR_FUGA[["AC"]], esc(dica),
                          pl + sx(d$internacoes_total) + 5, y0 + 15, num(d$internacoes_total)), collapse = "")
  leg <- paste(sprintf('<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="%s"/></svg>%s</span>',
                       COR_FUGA, c("Média complexidade", "Alta complexidade")), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(titulo), esc(titulo), barras, leg)
}

grafico_fuga_uf <- function(anos = ANO_DESL) {
  d <- fuga_por_uf(anos)
  rot <- if (length(anos) == 1) as.character(anos) else sprintf("%d–%d", min(anos), max(anos))
  HTML(svg_barras_pilha_uf(d, sprintf("Internações de residentes de Mato Grosso em hospitais de outros estados, por estado de destino e complexidade — %s", rot)))
}

# Série 2020–2025: parcela das internações dos residentes realizada em outros estados, por nível
serie_fuga_pct <- function() {
  series <- lapply(c("total", "MC", "AC"), function(nv) {
    r <- FUGARES[tolower(FUGARES$nivel) == tolower(nv) & FUGARES$ano %in% ANOS, ] |> arrange(ano)
    if (nrow(r) == 0) return(NULL)
    list(nome = NIVEIS_DESL[[nv]], cor = COR_NIVEIS[[nv]], larg = if (nv == "total") 2.8 else 2, dash = if (nv == "AC") "6,4" else "",
         x = r$ano, y = r$pct_outra_uf)
  })
  series <- Filter(Negate(is.null), series)
  if (length(series) == 0) return("")
  HTML(svg_linhas(series, fmt = "pct1", titulo = "Internações de residentes de MT realizadas em outros estados (% das internações dos residentes), por nível, 2020–2025", h = 250))
}

# Saldo por UF: ano e período, com totais no rodapé
tabela_fuga_saldo <- function(ano = ANO_DESL) {
  a <- fuga_saldo(ano); p_ <- fuga_saldo(ANOS)
  d <- p_ |> select(cod_uf, nome_uf, uf, ent_p = entrada, sai_p = saida, sal_p = saldo) |>
    left_join(select(a, cod_uf, ent_a = entrada, sai_a = saida, sal_a = saldo), by = "cod_uf") |>
    arrange(desc(sai_p), uf) |> transmute(UF = sprintf("%s (%s)", nome_uf, uf), ent_a, sai_a, sal_a, ent_p, sai_p, sal_p)
  rod <- function(col) if (grepl("^sal", col)) saldo_txt(sum(d[[col]])) else num(sum(d[[col]]))
  nc <- function(nome, col, f = num, ...) colDef(name = nome, align = "right", minWidth = 85, cell = function(v) f(v), footer = rod(col), ...)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE, pagination = FALSE,
    defaultColDef = colDef(footerStyle = list(fontWeight = 600)),
    columnGroups = list(colGroup(name = as.character(ano), columns = c("ent_a", "sai_a", "sal_a")),
                        colGroup(name = PERIODO_FUGA, columns = c("ent_p", "sai_p", "sal_p"))),
    columns = list(UF = colDef(name = "Estado", minWidth = 170, sticky = "left", footer = "Total"),
      ent_a = nc("Recebidas (residentes da UF internados em MT)", "ent_a"), sai_a = nc("Enviadas (residentes de MT internados na UF)", "sai_a"),
      sal_a = nc("Saldo (recebidas − enviadas)", "sal_a", saldo_txt, style = list(fontWeight = 600)),
      ent_p = nc("Recebidas", "ent_p"), sai_p = nc("Enviadas", "sai_p"),
      sal_p = nc("Saldo", "sal_p", saldo_txt, style = list(fontWeight = 600)))))
}

# Regiões de saúde de residência no ano (supressão já aplicada no arquivo; o período só é
# somado quando nenhum ano da região está suprimido)
tabela_fuga_regioes <- function(ano = ANO_DESL) {
  r <- FUGAREG[FUGAREG$ano == ano, ]
  if (nrow(r) == 0) return(p(class = "nota-fonte", "Não há dados por região de saúde para o ano."))
  per <- FUGAREG[FUGAREG$ano %in% ANOS, ] |> group_by(co_regsaud) |>
    summarise(fora_p = if (any(is.na(internacoes_outra_uf))) NA_real_ else sum(internacoes_outra_uf),
              tot_p = if (any(is.na(internacoes_total_res))) NA_real_ else sum(internacoes_total_res), .groups = "drop")
  d <- r |> left_join(per, by = "co_regsaud") |>
    transmute(Região = nome_regiao(co_regsaud), tot = internacoes_total_res, fora = internacoes_outra_uf, pct = pct_outra_uf,
              fora_ac = internacoes_ac_outra_uf, pct_ac = pct_ac_outra_uf,
              uf = ifelse(is.na(nome_uf_principal), "—", ifelse(is.na(pct_uf_principal), nome_uf_principal,
                          sprintf("%s (%s)", nome_uf_principal, pct_txt(pct_uf_principal)))),
              fora_p, pct_p = 100 * fora_p / tot_p) |> arrange(desc(pct))
  nc <- function(nome, f = num, ...) colDef(name = nome, align = "right", minWidth = 85, cell = function(v) supr_num(v, f), ...)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE, pagination = FALSE,
    columnGroups = list(colGroup(name = as.character(ano), columns = c("tot", "fora", "pct", "fora_ac", "pct_ac", "uf")),
                        colGroup(name = PERIODO_FUGA, columns = c("fora_p", "pct_p"))),
    columns = list(Região = colDef(name = "Região de saúde de residência", minWidth = 160, sticky = "left"),
      tot = nc("Internações de residentes (MT e outros estados)"), fora = nc("Em outros estados"),
      pct = nc("% em outros estados", pct_txt, style = list(fontWeight = 600)),
      fora_ac = nc("Alta complexidade em outros estados"), pct_ac = nc("% da alta complexidade em outros estados", pct_txt),
      uf = colDef(name = "Principal estado de destino", minWidth = 150),
      fora_p = nc("Em outros estados"), pct_p = nc("% em outros estados", pct_txt))))
}

# Municípios de residência, 2020–2025 somado (supressão já aplicada no arquivo)
tabela_fuga_municipios <- function(prefixo = "../municipios/", id_html = "tab-fuga-mun") {
  if (nrow(FUGAMUN) == 0) return(p(class = "nota-fonte", "Não há dados por município de residência."))
  d <- FUGAMUN |> left_join(select(MUN, cod_mun6, populacao_2025), by = "cod_mun6") |>
    transmute(cod = cod_mun6, Município = municipio, Região = nome_regiao(co_regsaud), pop = populacao_2025,
              tot = internacoes_total_res, fora = internacoes_outra_uf, pct = pct_outra_uf,
              uf = ifelse(total_suprimido == 1, TXT_SUPR, ifelse(is.na(nome_uf_principal), "—",
                          ifelse(is.na(pct_uf_principal), nome_uf_principal, sprintf("%s (%s)", nome_uf_principal, pct_txt(pct_uf_principal))))))
  d <- d[order(-ifelse(is.na(d$pct), -1, d$pct), ordem_nome(d$Município)), ]
  nc <- function(nome, f = num, ...) colDef(name = nome, align = "right", minWidth = 90, cell = function(v) supr_num(v, f), ...)
  tagList(
    tags$button(class = "btn btn-sm btn-outline-primary mb-2",
                onclick = sprintf("Reactable.downloadDataCSV('%s', 'ppsus-mt_internacoes_outros_estados_municipios_%d_%d.csv')", id_html, min(ANOS), max(ANOS)),
                sprintf("Baixar a tabela (CSV, %s)", PERIODO_FUGA)),
    div(class = "rolagem-x", reactable(d, elementId = id_html, compact = TRUE, striped = TRUE, highlight = TRUE, searchable = TRUE,
      defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, nrow(d)),
      columns = list(cod = colDef(show = FALSE),
        Município = colDef(minWidth = 150, sticky = "left", cell = function(v, i) a(href = url_mun(d$cod[i], prefixo), v)),
        Região = colDef(name = "Região de saúde", minWidth = 130),
        pop = colDef(name = "População 2025", align = "right", minWidth = 85, cell = function(v) num(v)),
        tot = nc(sprintf("Internações de residentes, %s (MT e outros estados)", PERIODO_FUGA)),
        fora = nc("Em outros estados"), pct = nc("% em outros estados", pct_txt, style = list(fontWeight = 600)),
        uf = colDef(name = "Principal estado de destino", minWidth = 150)))))
}

# Municípios de residência com maior parcela de internações em outros estados (para o texto)
fuga_mun_top <- function(n = 5, min_tot = 500) {
  FUGAMUN |> filter(!is.na(pct_outra_uf), internacoes_total_res >= min_tot) |> arrange(desc(pct_outra_uf)) |> head(n)
}

# Principais municípios de destino fora de MT (2020–2025)
tabela_fuga_destinos <- function() {
  if (nrow(FUGADEST) == 0) return(p(class = "nota-fonte", "Não há dados sobre os municípios de destino."))
  d <- FUGADEST |> arrange(posicao) |>
    transmute(Posição = posicao, Município = sprintf("%s (%s)", municipio, uf), int = internacoes, pct = pct_do_total_fora,
              ac = internacoes_ac, pct_ac = pct_ac)
  nc <- function(nome, f = num, ...) colDef(name = nome, align = "right", minWidth = 90, cell = function(v) supr_num(v, f), ...)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, highlight = TRUE, pagination = FALSE, sortable = FALSE,
    columns = list(Posição = colDef(align = "center", minWidth = 55, cell = function(v) ordinal(v)),
      Município = colDef(name = "Município de destino", minWidth = 190),
      int = nc(sprintf("Internações, %s", PERIODO_FUGA)), pct = nc("% das internações em outros estados", pct_txt),
      ac = nc("Alta complexidade"), pct_ac = nc("% de alta complexidade", pct_txt, style = list(fontWeight = 600)))))
}
