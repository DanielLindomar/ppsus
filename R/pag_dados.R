# =============================================================================
# Observatório PPSUS-MT — funções da página Dados (dados/index.qmd)
# Carregar DEPOIS de R/funcoes.R (usa MUN, IND, SER, REG, GRUPOS, ANOS, num, esc, ...).
#
#   dados_explorador()     tabela município × indicador com os anos em colunas
#   explorador_dados()     reactable com filtros (município, região, grupo, indicador),
#                          seletor de ano (mostra só a coluna escolhida) e download em CSV
#   catalogo_downloads()   lê arquivos/dados/catalogo_arquivos.csv (script 05) e confere
#                          cada arquivo em disco (tamanho, linhas e colunas atuais)
#   tabela_downloads()     reactable dos downloads, agrupada por tema, com links
#   tabela_dicionario()    dicionário dos indicadores (indicadores.csv) em tabela
#   fmt_bytes()            "1,3 MB" / "16 KB"
# =============================================================================

ARQ <- function(...) file.path(RAIZ, "arquivos", ...)

# Casas decimais por formato do catálogo (para arredondar o explorador e o CSV baixado)
DEC_FMT <- c(int = 0, dec1 = 1, dec2 = 2, dec3 = 3, pct1 = 1, pct2 = 2, brl = 2)
casas_fmt <- function(fmt) { d <- DEC_FMT[as.character(fmt)]; d[is.na(d)] <- 2; unname(d) }

fmt_bytes <- function(b) ifelse(is.na(b), "—", ifelse(b >= 1024^2, paste0(num(b / 1024^2, 1), " MB"),
                                                     paste0(num(pmax(b / 1024, 1), 0), " KB")))

# ---- Explorador --------------------------------------------------------------------------
# Uma linha por município × indicador; colunas 2020–2025 com o valor arredondado segundo fmt.
# Linhas sem nenhum valor no período são omitidas. Colunas auxiliares: indicador (id), dec.
dados_explorador <- function(anos = ANOS) {
  ind <- IND[!is.na(IND$grupo) & IND$grupo %in% names(GRUPOS), ]
  if (!"ordem" %in% names(ind)) ind$ordem <- seq_len(nrow(ind))
  s <- SER[SER$ano %in% anos & SER$indicador %in% ind$id & !is.na(SER$valor), ]
  if (nrow(s) == 0) return(NULL)
  w <- tidyr::pivot_wider(s, id_cols = c(cod_mun6, indicador), names_from = ano, values_from = valor)
  for (a in anos) if (!as.character(a) %in% names(w)) w[[as.character(a)]] <- NA_real_
  w <- w |>
    left_join(MUN[, c("cod_mun6", "municipio", "regiao_saude")], by = "cod_mun6") |>
    left_join(ind[, c("id", "rotulo", "grupo", "unidade", "fmt", "ordem")], by = c("indicador" = "id")) |>
    mutate(dec = casas_fmt(fmt), grupo = unname(GRUPOS[grupo]),
           municipio = ifelse(is.na(municipio), as.character(cod_mun6), municipio))
  for (a in as.character(anos)) w[[a]] <- round(w[[a]], w$dec)
  chave <- iconv(w$municipio, from = "UTF-8", to = "ASCII//TRANSLIT"); chave[is.na(chave)] <- w$municipio[is.na(chave)]
  w <- w[order(tolower(chave), match(w$grupo, GRUPOS), w$ordem), ]   # município (sem acentos), grupo, ordem do catálogo
  w[, c("cod_mun6", "municipio", "regiao_saude", "grupo", "indicador", "rotulo", "unidade", as.character(anos), "dec")]
}

# Lista suspensa no cabeçalho da coluna (filtro exato); opcoes = ordem de exibição
filtro_lista <- function(id_tab, opcoes = NULL, rotulo = "Todos") function(values, name) {
  v <- if (is.null(opcoes)) sort(unique(as.character(values))) else opcoes[opcoes %in% as.character(values)]
  tags$select(`aria-label` = paste("Filtrar", name), class = "form-select form-select-sm",
    onchange = sprintf("Reactable.setFilter('%s', '%s', event.target.value || undefined)", id_tab, name),
    tags$option(value = "", rotulo),
    lapply(v, function(x) tags$option(value = x, x)))
}
filtro_igual <- JS("function(rows, columnId, filterValue) { return rows.filter(function(row) { return String(row.values[columnId]) === filterValue }) }")

# Célula numérica formatada em pt-BR com as casas da coluna 'dec' da própria linha
celula_ptbr <- JS("function(cellInfo) {
  var v = cellInfo.value;
  if (v === null || v === undefined || v === '') return '—';
  var d = cellInfo.row['dec']; if (d === null || d === undefined) d = 2;
  return Number(v).toLocaleString('pt-BR', {minimumFractionDigits: d, maximumFractionDigits: d});
}")

explorador_dados <- function(id_tab = "explorador", arquivo = "observatorio-ppsus-mt_recorte.csv", anos = ANOS) {
  d <- dados_explorador(anos)
  if (is.null(d) || nrow(d) == 0) return(p(class = "nota-fonte", "Séries ainda não carregadas (dados_site/serie.csv)."))
  ind <- IND[!is.na(IND$grupo) & IND$grupo %in% names(GRUPOS), ]
  if (!"ordem" %in% names(ind)) ind$ordem <- seq_len(nrow(ind))
  anos_c <- as.character(anos)
  cols_ano <- setNames(lapply(anos_c, function(a) colDef(name = a, align = "right", minWidth = 78, filterable = FALSE, cell = celula_ptbr)), anos_c)
  colunas <- c(list(
    cod_mun6 = colDef(name = "Código", minWidth = 74, filterable = FALSE, align = "left"),
    municipio = colDef(name = "Município", minWidth = 150, sticky = "left", filterInput = filtro_lista(id_tab, MUN$municipio), filterMethod = filtro_igual),
    regiao_saude = colDef(name = "Região de saúde", minWidth = 150, filterInput = filtro_lista(id_tab, sort(unique(REG$regiao_saude))), filterMethod = filtro_igual),
    grupo = colDef(name = "Grupo", minWidth = 130, filterInput = filtro_lista(id_tab, unname(GRUPOS)), filterMethod = filtro_igual),
    indicador = colDef(show = FALSE),
    rotulo = colDef(name = "Indicador", minWidth = 250, filterInput = filtro_lista(id_tab, ind$rotulo[order(match(ind$grupo, names(GRUPOS)), ind$ordem)]), filterMethod = filtro_igual),
    unidade = colDef(name = "Unidade", minWidth = 130, filterable = FALSE, style = list(color = "#6b7280", fontSize = "0.85em")),
    dec = colDef(show = FALSE)), cols_ano)
  js <- sprintf("
(function () {
  var ANOS = %s, BASE = ['cod_mun6','municipio','regiao_saude','grupo','indicador','rotulo','unidade'], OCULTAS = ['indicador','dec'];
  window.explAno = function (a) {
    var esconder = a ? ANOS.filter(function (x) { return x !== a; }) : [];
    Reactable.setHiddenColumns('%s', OCULTAS.concat(esconder));
  };
  window.explBaixar = function () {
    var a = document.getElementById('%s-ano').value;
    Reactable.downloadDataCSV('%s', '%s', {columnIds: BASE.concat(a ? [a] : ANOS)});
  };
})();", jsonlite::toJSON(anos_c), id_tab, id_tab, id_tab, arquivo)
  tagList(
    div(class = "explorador-barra",
        div(tags$label(`for` = paste0(id_tab, "-ano"), "Ano"),
            tags$select(id = paste0(id_tab, "-ano"), class = "form-select form-select-sm", `aria-label` = "Escolher o ano mostrado",
                        onchange = "explAno(this.value)",
                        tags$option(value = "", sprintf("Todos (%d–%d)", min(anos), max(anos))),
                        lapply(anos_c, function(a) tags$option(value = a, a)))),
        tags$button(type = "button", class = "btn btn-sm btn-primary", onclick = "explBaixar()",
                    "Baixar o recorte filtrado (CSV)"),
        span(class = "nota-fonte", sprintf("%s linhas (município × indicador); as listas nos cabeçalhos filtram a tabela e o arquivo baixado.", num(nrow(d))))),
    reactable(d, elementId = id_tab, filterable = TRUE, searchable = TRUE, compact = TRUE, striped = TRUE,
              highlight = TRUE, defaultPageSize = 20, showPageSizeOptions = TRUE, pageSizeOptions = c(20, 50, 100, 500),
              columns = colunas, wrap = TRUE, resizable = TRUE),
    tags$script(HTML(js)))
}

# ---- Downloads ------------------------------------------------------------------------------
# Catálogo (arquivos/dados/catalogo_arquivos.csv, gerado por scripts/05_downloads.py), conferido
# com o disco: tamanho, linhas e colunas atuais; arquivo ausente → aviso e linha marcada.
catalogo_downloads <- function() {
  f <- ARQ("dados", "catalogo_arquivos.csv")
  if (!file.exists(f)) { aviso("arquivos/dados/catalogo_arquivos.csv ausente: rode scripts/05_downloads.py"); return(NULL) }
  cat_b <- tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                               colClasses = list(character = c("arquivo", "grupo", "descricao", "chave", "periodo", "fonte", "gerado_por"))))
  cat_b$caminho <- ARQ(cat_b$arquivo)
  cat_b$existe <- file.exists(cat_b$caminho)
  if (any(!cat_b$existe)) aviso("arquivos do catálogo ausentes: %s", paste(cat_b$arquivo[!cat_b$existe], collapse = ", "))
  cat_b$bytes <- ifelse(cat_b$existe, file.size(cat_b$caminho), NA_real_)
  med <- lapply(seq_len(nrow(cat_b)), function(i) {
    if (!cat_b$existe[i]) return(c(NA_integer_, NA_integer_))
    p <- cat_b$caminho[i]
    if (grepl("\\.geojson$", p)) { g <- jsonlite::fromJSON(p, simplifyVector = FALSE)$features
      c(length(g), if (length(g)) length(g[[1]]$properties) else 0L) }
    else { h <- data.table::fread(p, encoding = "UTF-8", select = 1L, showProgress = FALSE)
      c(nrow(h), length(names(data.table::fread(p, nrows = 0, encoding = "UTF-8")))) }
  })
  cat_b$linhas <- vapply(med, `[`, numeric(1), 1); cat_b$colunas <- vapply(med, `[`, numeric(1), 2)
  cat_b
}

tabela_downloads <- function(prefixo = "../arquivos/", cat_b = catalogo_downloads()) {
  if (is.null(cat_b)) return(p(class = "nota-fonte", "Catálogo de arquivos ainda não gerado (scripts/05_downloads.py)."))
  ordem_grupos <- c("Painéis e indicadores", "Deslocamento residência × atendimento", "Hospitais", "Dicionários e referências", "Malhas (GeoJSON)")
  d <- cat_b |>
    mutate(nome = basename(arquivo), Tipo = ifelse(grepl("\\.geojson$", arquivo), "GeoJSON", "CSV"),
           `Linhas` = ifelse(Tipo == "GeoJSON", paste0(num(linhas), " polígonos"), num(linhas)),
           `Colunas` = ifelse(Tipo == "GeoJSON", paste0(num(colunas), " propr."), num(colunas))) |>
    arrange(match(grupo, ordem_grupos), arquivo) |>
    transmute(Tema = grupo, Arquivo = nome, href = paste0(prefixo, arquivo), existe,
              Descrição = descricao, Chave = chave, Período = periodo, Fonte = fonte, Linhas, Colunas, Tamanho = fmt_bytes(bytes), bytes)
  reactable(d, compact = TRUE, striped = FALSE, pagination = FALSE, wrap = TRUE, groupBy = "Tema", defaultExpanded = TRUE,
            columns = list(
              Tema = colDef(minWidth = 190, grouped = JS("function(cellInfo) { return cellInfo.value + ' (' + cellInfo.subRows.length + ')' }")),
              # atributo download com valor (nome do arquivo): download = NA vira null no JSON e quebra a hidratação do reactable
              Arquivo = colDef(minWidth = 230, cell = function(v, i) if (isTRUE(d$existe[i])) tagList(a(href = d$href[i], download = v, v)) else tagList(v, span(class = "sub", " (indisponível)"))),
              href = colDef(show = FALSE), existe = colDef(show = FALSE), bytes = colDef(show = FALSE),
              Descrição = colDef(minWidth = 380, style = list(fontSize = "0.85em")),
              Chave = colDef(minWidth = 130, style = list(fontSize = "0.82em", fontFamily = "monospace")),
              Período = colDef(minWidth = 80, align = "center"),
              Fonte = colDef(minWidth = 150, style = list(fontSize = "0.82em", color = "#4b5563")),
              Linhas = colDef(minWidth = 80, align = "right"), Colunas = colDef(minWidth = 70, align = "right"),
              Tamanho = colDef(minWidth = 75, align = "right")))
}

# ---- Dicionário de indicadores -------------------------------------------------------------------
tabela_dicionario <- function(prefixo_ind = "../indicadores/") {
  ind <- IND[!is.na(IND$grupo), ]
  if (nrow(ind) == 0) return(p(class = "nota-fonte", "Catálogo de indicadores ainda não carregado."))
  if (!"descricao" %in% names(ind)) ind$descricao <- ind$rotulo
  if (!"ordem" %in% names(ind)) ind$ordem <- seq_len(nrow(ind))
  sent <- c(`1` = "▲ maior é melhor", `-1` = "▼ menor é melhor", `0` = "contexto (sem juízo)")
  d <- ind |> arrange(match(grupo, names(GRUPOS)), ordem) |>
    transmute(Grupo = unname(rotulo_grupo(grupo)), Indicador = rotulo, id, Descrição = ifelse(is.na(descricao), "", descricao),
              Unidade = unidade, Fonte = fonte, Sentido = ifelse(is.na(sentido), "—", sent[as.character(sentido)]),
              `Até` = ano_max, KPI = ifelse(!is.na(kpi) & kpi == 1, "sim", ""), Fórmula = formula,
              Nota = ifelse(is.na(nota), "", nota))
  reactable(d, compact = TRUE, pagination = FALSE, wrap = TRUE, groupBy = "Grupo", defaultExpanded = TRUE, searchable = TRUE,
            columns = list(
              Grupo = colDef(minWidth = 160, grouped = JS("function(cellInfo) { return cellInfo.value + ' (' + cellInfo.subRows.length + ')' }")),
              Indicador = colDef(minWidth = 220, cell = function(v, i) a(href = paste0(prefixo_ind, d$id[i], ".html"), v)),
              id = colDef(name = "Identificador", minWidth = 150, style = list(fontFamily = "monospace", fontSize = "0.8em")),
              Descrição = colDef(minWidth = 300, style = list(fontSize = "0.85em")),
              Unidade = colDef(minWidth = 120, style = list(fontSize = "0.85em", color = "#4b5563")),
              Fonte = colDef(minWidth = 100, style = list(fontSize = "0.85em")),
              Sentido = colDef(minWidth = 120, style = list(fontSize = "0.82em")),
              `Até` = colDef(minWidth = 55, align = "center"),
              KPI = colDef(minWidth = 50, align = "center"),
              Fórmula = colDef(show = FALSE), Nota = colDef(show = FALSE)),
            details = function(i) div(class = "detalhe-ind",
              p(class = "nota-fonte", strong("Fórmula: "), d$Fórmula[i]),
              if (nzchar(d$Nota[i])) p(class = "nota-fonte", strong("Nota: "), d$Nota[i]),
              p(class = "nota-fonte", a(href = paste0(prefixo_ind, d$id[i], ".html"), "Ver mapa, ranking e série deste indicador →"))))
}
