# =============================================================================
# Observatório PPSUS-MT — funções das páginas da seção Eficiência:
#   eficiencia/hospitais.qmd, eficiencia/alta-complexidade.qmd e eficiencia/produtividade.qmd
#
# Carregar DEPOIS de R/funcoes.R. Este arquivo é independente de R/pag_eficiencia.R
# (páginas dos modelos municipais): todos os objetos e funções daqui têm o prefixo
# EFX_/efx_ para não colidir com aquele arquivo, se os dois forem carregados juntos.
#
# Lê somente dados_site/eficiencia/ (gerado por scripts/06_preparar_eficiencia.py a partir
# do schema dea, na versão registrada em metadados.csv — v2.1 desde 16/10/2026). Nenhum
# número é digitado nas páginas: tudo vem dos CSVs.
# A especificação principal de cada modelo (inclusive a dos hospitais, em reprocessamento
# para "internações totais + diárias totais") é lida de especificacoes_modelos.csv.
#
# Índice
#   0. Leitura dos arquivos e constantes (faixas, quadrantes, modelos)
#   1. Formatação e componentes comuns (faixa de aviso, navegação, chips, especificação)
#   2. SVG (barras empilhadas por faixa, escore com IC por ano, painel de quadrantes)
#   3. Hospitais (KPIs, mapa por faixa, distribuição, tabela, metas, pares, evolução)
#   4. Alta complexidade (painel regional, quadrantes, mapa regional, escores diagnósticos)
#   5. Produtividade (Malmquist por modelo, janela e região de saúde)
# =============================================================================

# ---- 0. Leitura e constantes ---------------------------------------------------------
EFX_DIR <- file.path(RAIZ, "dados_site", "eficiencia")
EFX_TXT <- c("cnes", "par_cnes", "co_regsaud", "co_macsaud", "par_mais_semelhante_id")

efx_ler <- function(nome) {
  f <- file.path(EFX_DIR, paste0(nome, ".csv"))
  if (!file.exists(f)) { aviso("arquivo ausente: dados_site/eficiencia/%s.csv (tabela vazia)", nome); return(tibble::tibble()) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  txt <- intersect(EFX_TXT, hdr)
  tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                      colClasses = if (length(txt)) list(character = txt) else NULL))
}

EFX_FH   <- efx_ler("fichas_hospital")
EFX_MH   <- efx_ler("metas_hospital")
EFX_PH   <- efx_ler("pares_hospital")
EFX_IPH  <- efx_ler("insumos_produtos_hospital")
EFX_ESP  <- efx_ler("especificacoes_modelos")
EFX_RES  <- efx_ler("resumo_modelos")
EFX_MQ   <- efx_ler("malmquist_regiao")
EFX_PAC  <- efx_ler("painel_ac_regiao")
EFX_QAC  <- efx_ler("quadrantes_ac")
EFX_MAC  <- efx_ler("painel_ac_macro")
EFX_FR   <- efx_ler("fichas_regiao")
EFX_PARM <- efx_ler("parametros")
EFX_META <- efx_ler("metadados")

efx_meta <- function(item, padrao = NA_character_) {
  v <- EFX_META$valor[EFX_META$item == item]; if (length(v) && !is.na(v[1])) v[1] else padrao }
efx_param <- function(chave, padrao = NA_real_) {
  v <- suppressWarnings(as.numeric(EFX_PARM$valor_parametro[EFX_PARM$chave == chave]))
  if (length(v) && is.finite(v[1])) v[1] else padrao }

EFX_DATA <- efx_meta("data_resultados", "08/10/2026")
EFX_VERSAO   <- efx_meta("versao_resultados", "v2")          # ex.: "v2.1"
EFX_VERSAO_N <- sub("^v", "", EFX_VERSAO)                    # ex.: "2.1"
EFX_ROTULO   <- paste0("Resultados DEA ", EFX_VERSAO)        # rótulo de fonte das páginas
EFX_VERSAO_ANT   <- sub("^v", "", efx_meta("versao_anterior", ""))
EFX_DATA_ANT     <- efx_meta("data_versao_anterior", "")
EFX_REESTIMADOS  <- strsplit(efx_meta("modelos_reestimados", ""), ",\\s*")[[1]]
# Data da estimação de um modelo: na v2.1, os modelos não reestimados são cópia exata da versão anterior
efx_data_modelo <- function(m) if (nzchar(EFX_VERSAO_ANT) && length(EFX_REESTIMADOS) && !m %in% EFX_REESTIMADOS) EFX_DATA_ANT else EFX_DATA
EFX_ANO  <- 2025L
EFX_ANOS <- 2020:2025

# Faixas (quartis do escore corrigido; 'fronteira' = escore original igual a 1)
FAIXAS <- c("fronteira", "quartil superior", "terceiro quartil", "segundo quartil", "quartil inferior")
FAIXA_ROT <- c(fronteira = "Fronteira (melhores práticas)", `quartil superior` = "Quartil superior",
               `terceiro quartil` = "Terceiro quartil", `segundo quartil` = "Segundo quartil",
               `quartil inferior` = "Quartil inferior", `sem faixa` = "Sem faixa (escore não publicável)")
# Sequencial verde-azulado: mais escuro = mais perto das melhores práticas (sem vermelho/verde)
COR_FAIXA <- c(fronteira = "#0E5A5E", `quartil superior` = "#3D8588", `terceiro quartil` = "#7DB0AE",
               `segundo quartil` = "#B8D6D3", `quartil inferior` = "#EEF5F4", `sem faixa` = "#ffffff")
TXT_FAIXA <- c(fronteira = "#ffffff", `quartil superior` = "#ffffff", `terceiro quartil` = "#10393b",
               `segundo quartil` = "#10393b", `quartil inferior` = "#10393b", `sem faixa` = "#4b5563")

# Quadrantes da alta complexidade: cor + forma (não depender só da cor)
QUADRANTES <- c("polo", "em transição", "dependente com acesso adequado", "dependente com baixo acesso")
QUAD_ROT <- c(polo = "Polo", `em transição` = "Em transição",
              `dependente com acesso adequado` = "Dependente com acesso adequado",
              `dependente com baixo acesso` = "Dependente com baixo acesso")
COR_QUAD <- c(polo = "#0E5A5E", `em transição` = "#2E86AB", `dependente com acesso adequado` = "#8CBFBD",
              `dependente com baixo acesso` = "#d4a017")
FORMA_QUAD <- c(polo = "■", `em transição` = "◆", `dependente com acesso adequado` = "●", `dependente com baixo acesso` = "▲")

# Modelos (ordem de apresentação) e páginas da seção
MODELOS_MQ <- c(M1 = "Atenção básica", M0 = "Consolidado municipal", M2 = "Média complexidade (produção local)",
                M2A = "Média complexidade (ótica do acesso)", H = "Hospitais")
PAG_MODELO <- c(M1 = "atencao-basica.html", M0 = "consolidado.html", M2 = "media-complexidade.html",
                M2A = "media-complexidade.html", H = "hospitais.html", M3 = "alta-complexidade.html")
COR_MODELO <- c(M1 = "#0E5A5E", M0 = "#2E86AB", M2 = "#b45309", M2A = "#7c3aed", H = "#6b7280")
GRUPO_ROT <- c(todos = "Todos", publico = "Hospitais públicos", privado_filantropico = "Hospitais privados e filantrópicos",
               com_leito = "Municípios com leito SUS", sem_leito = "Municípios sem leito SUS")

# ---- 1. Formatação e componentes comuns --------------------------------------------------
efx_pct <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), "%"))
efx_esc <- function(x) num(x, 3)
efx_ic  <- function(lo, hi) ifelse(is.na(lo) | is.na(hi), "—", paste0(num(lo, 3), " a ", num(hi, 3)))
# Índice (Malmquist) como variação anual: 1,071 → "+7,1% ao ano"
efx_var <- function(x, sufixo = " ao ano") ifelse(is.na(x), "—",
  paste0(ifelse(x >= 1, "+", "−"), num(abs(100 * (x - 1)), 1), "%", sufixo))
efx_traco <- function(x) ifelse(is.na(x) | !nzchar(x), "—", x)
efx_lista_e <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
efx_limpa <- function(x) trimws(gsub(" ?\\((seção|se[cç][aã]o|item|anexo) [^)]*\\)", "", x))
efx_faixa2 <- function(f) ifelse(is.na(f) | !nzchar(f), "sem faixa", f)

# Folha de estilo comum às páginas desta seção
efx_css <- function() tags$style(HTML("
.chip-faixa { display:inline-block; padding:1px 8px; border-radius:10px; font-size:.76rem; font-weight:600;
  border:1px solid #9cbcba; white-space:nowrap; line-height:1.5; }
.chip-quad { display:inline-block; padding:1px 8px; border-radius:10px; font-size:.76rem; font-weight:600; white-space:nowrap; }
.efx-cruza { font-size:.72rem; color:#6b7280; display:block; }
.efx-spec { display:grid; grid-template-columns:repeat(auto-fit, minmax(260px, 1fr)); gap:1rem; margin:.6rem 0 1.2rem; }
.efx-spec ul { margin:.2rem 0 0 1.1rem; padding:0; } .efx-spec li { margin:.15rem 0; }
.efx-seta { font-size:1.6rem; color:#0E5A5E; align-self:center; text-align:center; }
.efx-quad-grade { display:grid; grid-template-columns: minmax(0,1fr) minmax(0,1fr); gap:.6rem; margin:.6rem 0 1rem; }
@media (max-width: 640px) { .efx-quad-grade { grid-template-columns: minmax(0,1fr); } }
.efx-quad { border:1px solid #d9e4e4; border-radius:8px; padding:.6rem .8rem; background:#fff; }
.efx-quad h5 { font-size:.9rem; margin:0 0 .3rem; color:#0E5A5E; }
.efx-quad p { font-size:.8rem; color:#4b5563; margin:.1rem 0 .4rem; }
.efx-quad ul { margin:0 0 0 1rem; padding:0; font-size:.86rem; }
.efx-ficha { border-left:4px solid #0E5A5E; background:#f8fbfb; padding:.6rem .9rem; margin:.6rem 0; border-radius:4px; font-size:.9rem; }
.efx-ficha h5 { font-size:.95rem; margin:0 0 .3rem; }
body.fullcontent main.content { min-width:0; }
.rolagem-x { max-width:100%; overflow-x:auto; contain:inline-size; }
.rolagem-x .reactable { max-width:100%; }
.efx-nav { display:flex; flex-wrap:wrap; gap:.4rem; margin:0 0 1rem; }
.efx-nav a.ativo { background:#0E5A5E; color:#fff; }
"))

# Aviso da seção: versão dos resultados e leitura por faixas
# Frase curta sobre a versão: só o(s) modelo(s) reestimado(s) mudou(aram) frente à versão anterior
efx_frase_versao <- function() {
  if (!nzchar(efx_meta("nota_versao", "")) || !length(EFX_REESTIMADOS) || !all(EFX_REESTIMADOS %in% names(MODELOS_MQ))) return("")
  nomes <- efx_lista_e(tolower(MODELOS_MQ[EFX_REESTIMADOS]))
  sprintf(paste0("Na versão %s, apenas o modelo de %s foi reestimado, e os demais resultados correspondem aos da versão %s (%s) — ",
                 "<a href=\"index.html#versao\">nota de versão</a>. "), EFX_VERSAO_N, nomes, EFX_VERSAO_ANT, EFX_DATA_ANT)
}

efx_faixa <- function() faixa_construcao(sprintf(paste0(
  "<b>Resultados da versão %s da estimação</b> (%s, %s), em validação com a SES-MT e o COSEMS-MT. %s",
  "Os escores devem ser lidos por <b>faixa e intervalo de confiança</b>, e não como <i>ranking</i>; a eficiência mede o volume de produção ",
  "obtido com os recursos disponíveis, e <b>não</b> a qualidade do cuidado."), EFX_VERSAO_N, EFX_ROTULO, EFX_DATA, efx_frase_versao()))

# Navegação entre as páginas da seção Eficiência (prefixo relativo à página que chama)
efx_nav <- function(atual = "") {
  pags <- c(`index.html` = "Como ler", `atencao-basica.html` = "Atenção básica", `consolidado.html` = "Consolidado",
            `media-complexidade.html` = "Média complexidade", `hospitais.html` = "Hospitais",
            `alta-complexidade.html` = "Alta complexidade", `produtividade.html` = "Produtividade")
  tags$nav(class = "efx-nav", `aria-label` = "Páginas da seção Eficiência",
           lapply(names(pags), function(h) a(class = paste("btn btn-sm btn-outline-primary", if (h == atual) "ativo"),
                                             href = h, `aria-current` = if (h == atual) "page" else NULL, pags[[h]])))
}

# Atalhos para as seções da página
efx_atalhos <- function(secoes) tags$nav(class = "nav-mun", `aria-label` = "Seções desta página",
  lapply(names(secoes), function(id) a(class = "btn btn-sm btn-outline-secondary", href = paste0("#", id), secoes[[id]])))

# Chip de faixa (HTML) com marca de intervalo de confiança que alcança a faixa vizinha
efx_chip <- function(faixa, cruza = 0) {
  f <- efx_faixa2(faixa)
  rot <- ifelse(f %in% names(FAIXA_ROT), FAIXA_ROT[f], f)
  rot <- ifelse(f == "fronteira", "Fronteira", rot)
  sprintf('<span class="chip-faixa" style="background:%s;color:%s">%s</span>%s', COR_FAIXA[f], TXT_FAIXA[f], esc(rot),
          ifelse(!is.na(cruza) & cruza == 1, '<span class="efx-cruza">IC alcança a faixa vizinha</span>', ""))
}
efx_chip_quad <- function(q) {
  cor <- COR_QUAD[q]; txt <- ifelse(q %in% c("polo", "em transição"), "#ffffff", "#1f2937")
  sprintf('<span class="chip-quad" style="background:%s;color:%s">%s %s</span>', cor, txt, FORMA_QUAD[q], esc(QUAD_ROT[q]))
}

# Especificação principal de um modelo: recursos (insumos) → produção (produtos), com unidade e fonte
efx_spec <- function(modelo) {
  e <- EFX_ESP[EFX_ESP$modelo == modelo, ]
  if (nrow(e) == 0) return(e)
  e[order(e$tipo != "insumo", e$ordem), ]
}
efx_bloco_spec <- function(modelo) {
  e <- efx_spec(modelo)
  if (nrow(e) == 0) return(p(class = "nota-fonte", "Especificação do modelo indisponível."))
  item <- function(x) lapply(seq_len(nrow(x)), function(i) tags$li(strong(x$nome_gerencial[i]),
    span(class = "sub", sprintf(" — %s; fonte: %s", x$unidade[i], gsub(";? ?com flags", "", x$fonte[i])))))
  ins <- unique(e[e$tipo == "insumo", c("variavel", "nome_gerencial", "unidade", "fonte")])
  pro <- unique(e[e$tipo == "produto", c("variavel", "nome_gerencial", "unidade", "fonte")])
  div(class = "efx-spec",
      div(class = "bloco", h4("Recursos (insumos)"), tags$ul(item(ins))),
      div(class = "bloco", h4("Produção (produtos)"), tags$ul(item(pro))))
}
efx_nomes_produtos <- function(modelo) { e <- efx_spec(modelo); unique(e$nome_gerencial[e$tipo == "produto"]) }
efx_nomes_insumos  <- function(modelo) { e <- efx_spec(modelo); unique(e$nome_gerencial[e$tipo == "insumo"]) }

# Botão de download de uma reactable (CSV com os dados da tabela, inclusive colunas ocultas)
efx_botao_csv <- function(id_html, arquivo, rotulo = "Baixar a tabela (CSV)")
  tags$button(class = "btn btn-sm btn-outline-primary mb-2", type = "button",
              onclick = sprintf("Reactable.downloadDataCSV('%s', '%s')", id_html, arquivo), rotulo)

# ---- 2. SVG ---------------------------------------------------------------------------------
# Barras horizontais empilhadas (contagens por categoria). m: matriz n × k com colnames = categorias.
efx_svg_empilhado <- function(rotulos, m, cores, cores_txt, rotulos_cat = colnames(m), titulo = "",
                              w = 680, lh = 26, pl = 200, pr = 44) {
  n <- nrow(m); if (n == 0) return("")
  tot <- rowSums(m); mx <- max(tot); if (mx == 0) return("")
  sx <- function(v) v / mx * (w - pl - pr)
  h <- n * lh + 6
  linhas <- vapply(seq_len(n), function(i) {
    y <- (i - 1) * lh; x0 <- pl; seg <- ""
    for (j in seq_len(ncol(m))) { v <- m[i, j]; if (v <= 0) next
      wd <- sx(v)
      seg <- paste0(seg, sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s" stroke="#6b9c9a" stroke-width=".6" data-tip="%s — %s: %s"/>',
                                 x0, y + 4, wd, lh - 8, cores[j], esc(rotulos[i]), esc(rotulos_cat[j]), num(v)),
                    if (wd >= 16) sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11" fill="%s" pointer-events="none">%s</text>',
                                          x0 + wd / 2, y + lh / 2 + 4, cores_txt[j], num(v)) else "")
      x0 <- x0 + wd }
    sprintf('<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937">%s</text>%s<text x="%.1f" y="%.1f" font-size="11" fill="#374151">%s</text>',
            pl - 8, y + lh / 2 + 4, esc(rotulos[i]), seg, x0 + 5, y + lh / 2 + 4, num(tot[i]))
  }, character(1))
  leg <- paste(sprintf('<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="%s" stroke="#6b9c9a"/></svg>%s</span>',
                       cores, esc(rotulos_cat)), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(titulo), esc(titulo), paste(linhas, collapse = ""), leg)
}

# Escore com intervalo de confiança por ano, várias séries (ex.: 3 regiões). d: serie, ano, est, lo, hi, faixa
efx_svg_ic_anos <- function(d, cores, titulo = "", w = 680, h = 280, ylim = c(0, 1)) {
  if (nrow(d) == 0) return("")
  pl <- 44; pr <- 14; pt <- 12; pb <- 28
  anos <- sort(unique(d$ano)); series <- unique(d$serie); k <- length(series)
  sx <- function(a, s) { i <- match(a, anos); j <- match(s, series)
    pl + (i - 0.5) / length(anos) * (w - pl - pr) + (j - (k + 1) / 2) * 14 }
  sy <- function(v) h - pb - (v - ylim[1]) / diff(ylim) * (h - pt - pb)
  yt <- seq(ylim[1], ylim[2], by = 0.2)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="11" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, num(yt, 1)), collapse = "")
  sxc <- function(a) pl + (match(a, anos) - 0.5) / length(anos) * (w - pl - pr)
  eixo <- paste(sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%d</text>',
                        sxc(anos), h - 8, anos), collapse = "")
  pts <- paste(vapply(seq_len(nrow(d)), function(i) { r <- d[i, ]; cor <- cores[[r$serie]]
    x <- sx(r$ano, r$serie)
    tip <- sprintf("%s · %d: %s (IC 95%%: %s) · %s", r$serie, r$ano, efx_esc(r$est), efx_ic(r$lo, r$hi), FAIXA_ROT[efx_faixa2(r$faixa)])
    sprintf('<g data-tip="%s"><line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2"/><line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2"/><line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2"/><circle cx="%.1f" cy="%.1f" r="4.5" fill="%s" stroke="#fff" stroke-width="1.2"/></g>',
            esc(tip), x, x, sy(r$lo), sy(r$hi), cor, x - 4, x + 4, sy(r$lo), sy(r$lo), cor, x - 4, x + 4, sy(r$hi), sy(r$hi), cor, x, sy(r$est), cor)
  }, character(1)), collapse = "")
  leg <- paste(sprintf('<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><circle cx="7" cy="7" r="5" fill="%s"/></svg>%s</span>',
                       unlist(cores[series]), esc(series)), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s%s</svg><figcaption class="legenda-svg">%s<span class="leg-item">ponto = escore corrigido; traço = intervalo de confiança de 95%%</span></figcaption></figure>',
          w, h, esc(titulo), esc(titulo), grade, eixo, pts, leg)
}

# ---- 3. Hospitais ----------------------------------------------------------------------------
# Produtos efetivamente usados nos escores publicados (metas) × produtos da especificação principal
efx_h_produtos_escore <- function() {
  m <- EFX_MH[EFX_MH$tipo == "produto", c("variavel", "nome_gerencial")]
  unique(m)
}
efx_h_atualizado <- function() {
  pe <- efx_spec("H"); pe <- pe$variavel[pe$tipo == "produto"]
  pm <- efx_h_produtos_escore()$variavel
  length(pe) == 0 || length(pm) == 0 || setequal(pe, pm)
}
efx_h_aviso_reprocessamento <- function() {
  if (efx_h_atualizado()) return(invisible(NULL))
  div(class = "callout callout-style-default callout-warning callout-titled", role = "note",
      div(class = "callout-header d-flex align-content-center", div(class = "callout-title-container flex-fill", "Atualização em andamento")),
      div(class = "callout-body-container callout-body",
          p(HTML(sprintf(paste0("A especificação principal do modelo de hospitais passou a ser <b>%s</b> (decisão da coordenação do projeto, %s). ",
            "Os escores, as faixas, os pares, as metas e a evolução desta página ainda provêm da estimação com os produtos da especificação anterior ",
            "(<b>%s</b>) e serão substituídos automaticamente quando o reprocessamento for concluído."),
            esc(efx_lista_e(efx_nomes_produtos("H"))), EFX_DATA, esc(efx_lista_e(efx_h_produtos_escore()$nome_gerencial)))))))
}

efx_perfil_txt <- function(p) ifelse(is.na(p), "—", paste0(ifelse(grepl("com_uti", p), "com UTI", "sem UTI"), ", ",
                                                           ifelse(grepl("com_ac", p), "com alta complexidade", "sem alta complexidade")))
efx_grupo_txt <- function(g) ifelse(is.na(g), "—", ifelse(g == "publico", "Público", "Privado/filantrópico"))

efx_h_ano <- function(a = EFX_ANO) {
  d <- EFX_FH[EFX_FH$ano == a, ]
  d$faixa2 <- efx_faixa2(d$faixa)
  d
}

# Produção observada (produtos da especificação principal) por hospital e ano, em formato largo
efx_h_producao <- function(a = EFX_ANO) {
  e <- efx_spec("H"); pro <- e[e$tipo == "produto", ]
  x <- EFX_IPH[EFX_IPH$ano == a & EFX_IPH$variavel %in% pro$variavel, c("cnes", "variavel", "valor")]
  if (nrow(x) == 0) return(tibble::tibble(cnes = character(0)))
  w <- tidyr::pivot_wider(x, names_from = variavel, values_from = valor)
  w <- w[, c("cnes", intersect(pro$variavel, names(w)))]
  names(w)[-1] <- paste0("prod_", names(w)[-1])  # prefixo: evita colisão com colunas homônimas das fichas
  w
}

efx_h_kpis <- function(a = EFX_ANO) {
  r <- EFX_RES[EFX_RES$modelo == "H" & EFX_RES$grupo == "todos" & EFX_RES$ano == a, ]
  d <- efx_h_ano(a)
  mq <- EFX_MQ[EFX_MQ$modelo == "H" & EFX_MQ$nivel == "estado" & EFX_MQ$grupo == "todos" & EFX_MQ$periodo == "2022-2025", ]
  bal <- sum(d$situacao == "avaliado" & d$especificacao_escore == "principal", na.rm = TRUE)
  fora <- sum(d$situacao == "avaliado" & d$especificacao_escore != "principal", na.rm = TRUE)
  aval <- d[d$situacao == "avaliado", ]
  div(class = "kpi-grade",
    kpi_simples("Hospitais avaliados", num(r$n_avaliados), paste0("hospitais SUS · ", a),
                sprintf("%s do painel completo 2020–2025 e %s com série incompleta; %s sem escore publicável", num(bal), num(fora), num(r$n_nao_publicavel))),
    kpi_simples("Na fronteira (melhores práticas)", num(r$n_fronteira), paste0("hospitais · ", a),
                sprintf("%s dos avaliados", efx_pct(100 * r$n_fronteira / r$n_avaliados))),
    kpi_simples("Escore corrigido mediano", efx_esc(r$mediana_escore), paste0("0 a 1; 1 = melhores práticas · ", a),
                sprintf("produção mediana a %s das melhores práticas com os mesmos recursos", efx_pct(100 * r$mediana_escore, 0))),
    kpi_simples("Posição incerta", num(r$n_ic_cruza_faixa), paste0("hospitais cujo intervalo alcança a faixa vizinha · ", a),
                "a faixa desses hospitais é provisória"),
    kpi_simples("Aproximação às melhores práticas", efx_var(mq$ec[1]), "média anual 2022–2025 (gestão, Malmquist)",
                sprintf("%s de %s hospitais com melhora no período", num(mq$n_ec_maior_1[1]), num(mq$n[1]))),
    kpi_simples("Registro a verificar", num(r$n_registro_a_verificar), paste0("hospitais com dado de origem a confirmar · ", a),
                "a verificar com a SES-MT e o COSEMS-MT"))
}

# JavaScript de clique: layerId "slug" ou "slug|identificador" → perfil do município
efx_js_clique <- function(prefixo) sprintf("function(el, x) { var map = this; map.eachLayer(function(l) {
  if (l.options && l.options.layerId) { var id = String(l.options.layerId).split('|')[0];
    l.on('click', function() { window.location = '%s' + id + '.html'; });
    var w0 = (l.options.weight === undefined) ? 1 : l.options.weight;
    l.on('mouseover', function() { if (l.setStyle) l.setStyle({weight: w0 + 1.5}); });
    l.on('mouseout', function() { if (l.setStyle) l.setStyle({weight: w0}); }); } }); }", prefixo)

efx_legenda_faixas <- function(m, faixas_presentes, titulo = "Faixa") {
  f <- c(FAIXAS, "sem faixa"); f <- f[f %in% faixas_presentes]
  addLegend(m, "bottomright", colors = unname(COR_FAIXA[f]), labels = unname(FAIXA_ROT[f]), title = titulo, opacity = 1)
}

# Mapa dos hospitais por faixa: pontos na sede do município (afastados quando há vários na mesma cidade)
efx_mapa_hospitais <- function(a = EFX_ANO, altura = 560, prefixo = "../municipios/") {
  if (nrow(GEO) == 0 || nrow(CENT) == 0) return(sem_mapa())
  d <- efx_h_ano(a) |> left_join(CENT, by = "cod_mun6") |> filter(is.finite(lon))
  if (nrow(d) == 0) return(sem_mapa())
  d <- d |> group_by(cod_mun6) |> arrange(desc(leitos_sus), .by_group = TRUE) |>
    mutate(i = row_number() - 1, k = n()) |> ungroup() |>
    mutate(r = ifelse(k == 1, 0, 0.05 * sqrt(i + 0.5)), ang = i * 2.39996,
           lon2 = lon + r * cos(ang) / cos(lat * pi / 180), lat2 = lat + r * sin(ang))
  rot <- sprintf("<b>%s</b> (CNES %s)<br>%s · região %s<br>%s · %s<br>Faixa %d: <b>%s</b>%s<br>Escore corrigido: %s (IC 95%%: %s)<br><i>o clique abre o perfil do município</i>",
                 esc(d$nome_hospital), d$cnes, esc(d$municipio), esc(d$regiao_saude), efx_grupo_txt(d$grupo2_ano), efx_perfil_txt(d$perfil_oferta),
                 a, FAIXA_ROT[d$faixa2], ifelse(!is.na(d$ic_cruza_faixa) & d$ic_cruza_faixa == 1, " (intervalo alcança a faixa vizinha)", ""),
                 efx_esc(d$escore_bc), efx_ic(d$ic_inf, d$ic_sup))
  lt <- ifelse(is.finite(d$leitos_sus), pmax(d$leitos_sus, 0), 0); d$raio <- 4 + 6 * sqrt(lt / max(lt, 1))
  bb <- bbox_num(GEO)
  m <- mapa_vazio(altura) |>
    addPolygons(data = GEO, layerId = ~slug, fillColor = "#e4ecec", fillOpacity = 1, color = "#ffffff", weight = 0.8,
                label = ~paste0(municipio, " — o clique abre o perfil")) |>
    addCircleMarkers(data = d, lng = ~lon2, lat = ~lat2, layerId = paste0(d$slug, "|", d$cnes),
                     radius = ~raio,
                     color = "#10393b", weight = 1, fillColor = unname(COR_FAIXA[d$faixa2]), fillOpacity = 0.95,
                     label = lapply(rot, HTML)) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4])
  m <- efx_legenda_faixas(m, unique(d$faixa2), paste0("Faixa ", a))
  htmlwidgets::onRender(m, efx_js_clique(prefixo))
}

# Distribuição dos hospitais por faixa em cada região de saúde
efx_h_distribuicao_regioes <- function(a = EFX_ANO) {
  d <- efx_h_ano(a)
  cats <- c(FAIXAS, "sem faixa")
  t <- table(factor(d$regiao_saude), factor(d$faixa2, levels = cats))
  t <- t[, colSums(t) > 0, drop = FALSE]
  o <- order(-rowSums(t[, intersect(colnames(t), c("fronteira", "quartil superior")), drop = FALSE]) / rowSums(t), -rowSums(t))
  t <- t[o, , drop = FALSE]
  HTML(efx_svg_empilhado(rownames(t), unclass(t), unname(COR_FAIXA[colnames(t)]), unname(TXT_FAIXA[colnames(t)]),
                         unname(FAIXA_ROT[colnames(t)]), titulo = sprintf("Hospitais por faixa em cada região de saúde, %d", a)))
}
efx_h_distribuicao_grupos <- function(a = EFX_ANO) {
  d <- efx_h_ano(a)
  d$grp <- paste0(efx_grupo_txt(d$grupo2_ano), " · ", efx_perfil_txt(d$perfil_oferta))
  cats <- c(FAIXAS, "sem faixa")
  t <- table(factor(d$grp), factor(d$faixa2, levels = cats))
  t <- t[, colSums(t) > 0, drop = FALSE]; t <- t[order(-rowSums(t)), , drop = FALSE]
  HTML(efx_svg_empilhado(rownames(t), unclass(t), unname(COR_FAIXA[colnames(t)]), unname(TXT_FAIXA[colnames(t)]),
                         unname(FAIXA_ROT[colnames(t)]), titulo = sprintf("Hospitais por faixa, grupo e perfil de oferta, %d", a), pl = 330))
}

# Tabela de todos os hospitais do ano: faixa, escore com IC, esperado, tendência, produção, sinais
efx_h_tabela <- function(a = EFX_ANO, prefixo = "../municipios/", id_html = "tab-hospitais") {
  d <- efx_h_ano(a)
  if (nrow(d) == 0) return(p(class = "nota-fonte", "Sem dados de hospitais."))
  pro <- efx_spec("H"); pro <- pro[pro$tipo == "produto", ]
  prod <- efx_h_producao(a)
  d <- left_join(d, prod, by = "cnes")
  d <- d[order(match(d$faixa2, c(FAIXAS, "sem faixa")), -ifelse(is.na(d$escore_bc), -1, d$escore_bc)), ]
  t <- tibble::tibble(
    slug = d$slug, Hospital = d$nome_hospital, CNES = d$cnes, Município = d$municipio, `Região de saúde` = d$regiao_saude,
    Grupo = efx_grupo_txt(d$grupo2_ano), Perfil = efx_perfil_txt(d$perfil_oferta),
    Faixa = d$faixa2, cruza = d$ic_cruza_faixa,
    Escore = d$escore_bc, ic_inf = d$ic_inf, ic_sup = d$ic_sup,
    Esperado = d$escore_esperado, Tendencia = efx_traco(d$tendencia_ec_2022_2025), EC = d$ec_2022_2025,
    RMP = d$rmp, rmp_peq = d$flag_rmp_base_pequena,
    Sinais = efx_traco(d$sinal_gerencial), Situacao = d$situacao)
  for (v in pro$variavel) t[[v]] <- if (paste0("prod_", v) %in% names(d)) d[[paste0("prod_", v)]] else NA_real_
  cols_prod <- setNames(lapply(seq_len(nrow(pro)), function(i) colDef(name = paste0(pro$nome_gerencial[i], " (", a, ")"),
                                                                         align = "right", minWidth = 110, cell = function(v) num(v))), pro$variavel)
  cols <- c(list(
    slug = colDef(show = FALSE), cruza = colDef(show = FALSE), ic_inf = colDef(show = FALSE), ic_sup = colDef(show = FALSE),
    rmp_peq = colDef(show = FALSE), Situacao = colDef(show = FALSE),
    Hospital = colDef(minWidth = 230, sticky = "left", style = list(fontSize = ".82rem")),
    CNES = colDef(minWidth = 80),
    Município = colDef(minWidth = 130, cell = function(v, i) a(href = paste0(prefixo, t$slug[i], ".html"), v)),
    `Região de saúde` = colDef(minWidth = 130), Grupo = colDef(minWidth = 110), Perfil = colDef(minWidth = 150),
    Faixa = colDef(name = paste0("Faixa ", a), minWidth = 140, html = TRUE,
                   cell = function(v, i) efx_chip(v, t$cruza[i])),
    Escore = colDef(name = "Escore corrigido (IC 95%)", minWidth = 140, align = "right", html = TRUE,
                    cell = function(v, i) if (is.na(v)) '<span class="sub">não publicável</span>' else
                      sprintf('<b>%s</b><div class="sub">%s</div>', efx_esc(v), efx_ic(t$ic_inf[i], t$ic_sup[i]))),
    Esperado = colDef(name = "Escore esperado pelo contexto", minWidth = 110, align = "right", cell = function(v) efx_esc(v)),
    Tendencia = colDef(name = "Tendência 2022–2025 (gestão)", minWidth = 150, html = TRUE,
                       cell = function(v, i) sprintf('%s<div class="sub">%s</div>', esc(v), efx_var(t$EC[i]))),
    EC = colDef(show = FALSE),
    RMP = colDef(name = "Mortalidade padronizada (1 = esperado)", minWidth = 120, align = "right", html = TRUE,
                 cell = function(v, i) if (is.na(v)) "—" else sprintf('%s%s', num(v, 2), if (isTRUE(t$rmp_peq[i] == 1)) '<div class="sub">base pequena</div>' else "")),
    Sinais = colDef(name = "Sinalizações", minWidth = 200, style = list(fontSize = ".8rem"))), cols_prod)
  tagList(
    efx_botao_csv(id_html, sprintf("ppsus-mt_eficiencia_hospitais_%d.csv", a), sprintf("Baixar a tabela (CSV, %d)", a)),
    div(class = "rolagem-x", reactable(t, elementId = id_html, columns = cols, searchable = TRUE, compact = TRUE, striped = TRUE,
        highlight = TRUE, wrap = TRUE, defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 30, nrow(t)))))
}

# Potencial agregado de melhoria (metas publicáveis do ano), por variável
efx_h_metas_agregadas <- function(a = EFX_ANO) {
  m <- EFX_MH[EFX_MH$ano == a & EFX_MH$meta_publicavel == 1 & is.finite(EFX_MH$observado) & is.finite(EFX_MH$meta_radial), ]
  if (nrow(m) == 0) return(NULL)
  m |> group_by(tipo, variavel, nome_gerencial, unidade) |>
    summarise(n = n_distinct(cnes), n_lacuna = sum(abs(meta_radial - observado) > 1e-6 * pmax(1, abs(observado))),
              obs = sum(observado), inter = sum(meta_intermediaria, na.rm = TRUE), meta = sum(meta_radial), .groups = "drop") |>
    mutate(var_pct = 100 * (meta / obs - 1), var_inter = 100 * (inter / obs - 1)) |>
    arrange(desc(tipo), variavel)
}
efx_h_tabela_metas <- function(a = EFX_ANO) {
  g <- efx_h_metas_agregadas(a)
  if (is.null(g)) return(p(class = "nota-fonte", "Metas indisponíveis."))
  t <- g |> transmute(Variável = nome_gerencial, Tipo = ifelse(tipo == "produto", "Produção", "Recurso"), Unidade = unidade,
                      `Hospitais com meta` = n, `Com lacuna` = n_lacuna, Observado = obs, `Meta intermediária` = inter,
                      `Meta plena` = meta, `Variação até a meta intermediária` = var_inter, `Variação até a meta plena` = var_pct)
  nc <- function(nome, f = num) colDef(name = nome, align = "right", minWidth = 100, cell = function(v) f(v))
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, columns = list(
    Variável = colDef(minWidth = 220), Tipo = colDef(minWidth = 90), Unidade = colDef(minWidth = 100),
    `Hospitais com meta` = nc("Hospitais com meta publicada"), `Com lacuna` = nc("Com distância até a meta"),
    Observado = nc(paste0("Observado (soma, ", a, ")")), `Meta intermediária` = nc("Meta intermediária (soma)"), `Meta plena` = nc("Meta plena (soma)"),
    `Variação até a meta intermediária` = nc("Variação até a meta intermediária", function(v) efx_pct(v)),
    `Variação até a meta plena` = nc("Variação até a meta plena", function(v) efx_pct(v)))))
}

# Hospitais de referência (pares) mais usados no ano
efx_h_pares_top <- function(a = EFX_ANO, n = 10, prefixo = "../municipios/") {
  p0 <- EFX_PH[EFX_PH$ano == a, ]
  if (nrow(p0) == 0) return(p(class = "nota-fonte", "Sem pares no ano."))
  f <- efx_h_ano(a)
  t <- p0 |> group_by(par_cnes, par_nome, par_municipio) |>
    summarise(n_ref = n_distinct(cnes), n_sem = sum(mais_semelhante == 1, na.rm = TRUE), peso = mean(peso, na.rm = TRUE), .groups = "drop") |>
    arrange(desc(n_ref), desc(n_sem)) |> slice_head(n = n) |>
    left_join(f |> select(cnes, regiao_saude, faixa, perfil_oferta, grupo2_ano, slug_par = slug), by = c("par_cnes" = "cnes"))
  d <- tibble::tibble(slug = t$slug_par, Referência = t$par_nome, Município = t$par_municipio, `Região de saúde` = t$regiao_saude,
                      Perfil = paste0(efx_grupo_txt(t$grupo2_ano), " · ", efx_perfil_txt(t$perfil_oferta)),
                      Faixa = t$faixa, `Hospitais que a usam` = t$n_ref, `Par mais semelhante de` = t$n_sem, `Peso médio` = t$peso)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, columns = list(
    slug = colDef(show = FALSE), Referência = colDef(minWidth = 230, style = list(fontSize = ".82rem")),
    Município = colDef(minWidth = 120, cell = function(v, i) if (is.na(d$slug[i])) v else a(href = paste0(prefixo, d$slug[i], ".html"), v)),
    `Região de saúde` = colDef(minWidth = 130), Perfil = colDef(minWidth = 200),
    Faixa = colDef(name = paste0("Faixa ", a), html = TRUE, minWidth = 110, cell = function(v) efx_chip(v)),
    `Hospitais que a usam` = colDef(align = "right", minWidth = 90), `Par mais semelhante de` = colDef(align = "right", minWidth = 90),
    `Peso médio` = colDef(name = "Peso médio na meta", align = "right", minWidth = 90, cell = function(v) efx_pct(100 * v, 0)))))
}

# ---- Malmquist (usado em hospitais e produtividade) ----
efx_mq <- function(modelo, nivel = "estado", grupo = "todos", tipo = NULL) {
  x <- EFX_MQ[EFX_MQ$modelo == modelo & EFX_MQ$nivel == nivel & EFX_MQ$grupo == grupo, ]
  if (!is.null(tipo)) x <- x[x$tipo_periodo == tipo, ]
  x
}
JANELAS <- c("2020-2022", "2022-2025", "2020-2025")
efx_janela_rot <- function(p) sub("-", "–", p)

# Tabela por janela: n, EC (variação anual), % com EC > 1, MI, TC, melhora/piora consistente
efx_mq_tabela_janelas <- function(modelos = names(MODELOS_MQ), grupos = list(), com_modelo = TRUE) {
  linhas <- lapply(modelos, function(md) {
    gs <- if (!is.null(grupos[[md]])) grupos[[md]] else "todos"
    lapply(gs, function(g) { x <- efx_mq(md, "estado", g, "janela"); x <- x[x$periodo %in% JANELAS, ]
      if (nrow(x) == 0) return(NULL)
      x <- x[order(match(x$periodo, JANELAS)), ]
      tibble::tibble(Modelo = MODELOS_MQ[[md]], cod = md, Grupo = GRUPO_ROT[[g]], Janela = efx_janela_rot(x$periodo), n = x$n,
                     EC = x$ec, pct_ec = 100 * x$n_ec_maior_1 / x$n, MI = x$mi, TC = x$tc, melhora = x$n_melhora_ec, piora = x$n_piora_ec) }) })
  t <- bind_rows(unlist(linhas, recursive = FALSE))
  if (nrow(t) == 0) return(p(class = "nota-fonte", "Malmquist indisponível."))
  # contagens de tendência consistente ausentes no agregado de um modelo (todas zero) → "—", não zero
  sem_cont <- tapply(t$melhora + t$piora, t$cod, function(v) all(is.na(v) | v == 0))
  t$melhora[t$cod %in% names(sem_cont)[sem_cont]] <- NA; t$piora[t$cod %in% names(sem_cont)[sem_cont]] <- NA
  if (!com_modelo) t$Modelo <- NULL
  ic <- function(nome, f, mw = 100) colDef(name = nome, align = "right", minWidth = mw, cell = function(v) f(v))
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
    columns = list(cod = colDef(show = FALSE), Modelo = if (com_modelo) colDef(minWidth = 170) else NULL,
      Grupo = colDef(minWidth = 150), Janela = colDef(minWidth = 90), n = colDef(name = "Unidades", align = "right", minWidth = 70),
      EC = colDef(name = "Aproximação às melhores práticas (EC)", align = "right", minWidth = 150, html = TRUE,
                  cell = function(v) sprintf('<b>%s</b><div class="sub">índice %s</div>', efx_var(v), num(v, 3))),
      pct_ec = ic("Unidades com EC > 1", efx_pct, 90),
      MI = colDef(name = "Índice de Malmquist (MI)", align = "right", minWidth = 120, html = TRUE,
                  cell = function(v) sprintf('%s<div class="sub">índice %s</div>', efx_var(v), num(v, 3))),
      TC = colDef(name = "Deslocamento das melhores práticas (TC)*", align = "right", minWidth = 130, html = TRUE,
                  cell = function(v) sprintf('<span style="color:#6b7280">%s</span>', num(v, 3))),
      melhora = ic("Melhora consistente (EC)", num, 90), piora = ic("Piora consistente (EC)", num, 90))[c("cod", if (com_modelo) "Modelo", "Grupo", "Janela", "n", "EC", "pct_ec", "MI", "TC", "melhora", "piora")]))
}

# Série das transições anuais (EC) por modelo/grupo no estado
efx_mq_serie <- function(chaves, titulo = "Aproximação às melhores práticas (EC) por transição anual", campo = "ec") {
  series <- lapply(chaves, function(k) { x <- efx_mq(k$modelo, "estado", k$grupo, "transicao")
    if (nrow(x) == 0) return(NULL)
    list(nome = k$nome, cor = k$cor, larg = if (is.null(k$larg)) 2.4 else k$larg, dash = if (is.null(k$dash)) "" else k$dash,
         x = as.integer(substr(x$periodo, 6, 9)), y = x[[campo]]) })
  series <- Filter(Negate(is.null), series)
  if (!length(series)) return("")
  svg_linhas(series, fmt = "dec3", titulo = titulo)
}

# Lista dos hospitais com tendência consistente (melhora/piora) em 2022–2025
efx_h_tendencias <- function(a = EFX_ANO, prefixo = "../municipios/") {
  d <- efx_h_ano(a); d <- d[!is.na(d$tendencia_ec_2022_2025) & grepl("consistente", d$tendencia_ec_2022_2025), ]
  if (nrow(d) == 0) return(p("Nenhum hospital com tendência consistente em 2022–2025."))
  d <- d[order(d$tendencia_ec_2022_2025, -d$ec_2022_2025), ]
  tags$ul(HTML(paste(sprintf('<li><b>%s</b>: %s (<a href="%s%s.html">%s</a>) — aproximação às melhores práticas de %s</li>',
    esc(d$tendencia_ec_2022_2025), esc(d$nome_hospital), prefixo, d$slug, esc(d$municipio), efx_var(d$ec_2022_2025)), collapse = "")))
}

# ---- 4. Alta complexidade -----------------------------------------------------------------------
efx_ac_ano <- function(a = EFX_ANO) { d <- EFX_PAC[EFX_PAC$ano == a, ]; d[ordem_nome(d$regiao_saude), ] }
efx_fr_ano <- function(a = EFX_ANO) EFX_FR[EFX_FR$ano == a, ]

efx_ac_kpis <- function(a = EFX_ANO) {
  d <- efx_ac_ano(a); if (nrow(d) == 0) return(NULL)
  tot_res <- sum(d$internacoes_ac_res, na.rm = TRUE); pop <- sum(d$populacao, na.rm = TRUE)
  q <- table(factor(d$quadrante, levels = QUADRANTES))
  lider <- d[which.max(d$internacoes_ac_local), ]
  share <- 100 * lider$internacoes_ac_local / sum(d$internacoes_ac_local, na.rm = TRUE)
  pub <- d$regiao_saude[d$publicavel_m3 == 1]
  div(class = "kpi-grade",
    kpi_simples("Internações de AC de residentes", num(1000 * tot_res / pop, 2), paste0("por mil hab. · Mato Grosso · ", a),
                sprintf("mediana das 16 regiões: %s por mil", num(d$mediana_acesso_estadual[1], 2))),
    kpi_simples("Regiões-polo", num(q[["polo"]]), paste0("autossuficiência ≥ 100% · ", a),
                efx_lista_e(d$regiao_saude[d$quadrante == "polo"])),
    kpi_simples("Dependentes com baixo acesso", num(q[["dependente com baixo acesso"]]), paste0("regiões · ", a),
                "prioridade para regulação e pactuação de fluxos"),
    kpi_simples("Concentração da produção", efx_pct(share), paste0("das internações de AC realizadas em MT · ", a),
                sprintf("realizadas na região %s", lider$regiao_saude)),
    kpi_simples("Regiões com escore diagnóstico", num(length(pub)), "oferta hospitalar contínua de AC 2020–2025",
                efx_lista_e(pub)))
}

# Painel regional (16 regiões) do ano, com busca e download
efx_ac_tabela_painel <- function(a = EFX_ANO, id_html = "tab-painel-ac") {
  d <- efx_ac_ano(a); if (nrow(d) == 0) return(p(class = "nota-fonte", "Painel indisponível."))
  t <- tibble::tibble(Região = d$regiao_saude, Quadrante = d$quadrante, Macrorregião = d$macrorregiao, População = d$populacao,
    Acesso = d$internacoes_ac_res_p1000, APAC = d$apac_ac_res_p1000, Realizadas = d$internacoes_ac_local_p1000,
    Autossuficiencia = d$autossuficiencia_ac_pct, Valor = d$valor_ac_res_pc,
    UTI = d$uti_sus_validada_p100mil, Habilitacoes = d$n_habilitacoes_ac, Distancia = d$dist_polo_ac_km,
    Tendencia = d$tendencia_acesso_2020_2025, Tendencia2225 = d$tendencia_acesso_2022_2025)
  nc <- function(nome, f, mw = 95) colDef(name = nome, align = "right", minWidth = mw, cell = function(v) f(v))
  tagList(
    efx_botao_csv(id_html, sprintf("ppsus-mt_alta_complexidade_regioes_%d.csv", a), sprintf("Baixar o painel (CSV, %d)", a)),
    div(class = "rolagem-x", reactable(t, elementId = id_html, compact = TRUE, striped = TRUE, highlight = TRUE, pagination = FALSE,
      searchable = TRUE, wrap = TRUE,
      columnGroups = list(colGroup(name = "Acesso dos residentes", columns = c("Acesso", "APAC", "Valor", "Tendencia", "Tendencia2225")),
                          colGroup(name = "Produção e capacidade na região", columns = c("Realizadas", "Autossuficiencia", "UTI", "Habilitacoes"))),
      columns = list(
        Região = colDef(minWidth = 170, sticky = "left"), Macrorregião = colDef(minWidth = 110),
        População = nc("População", num, 100),
        Acesso = nc("Internações de AC por mil hab.", function(v) num(v, 2), 105),
        APAC = nc("Procedimentos de AC (APAC) por mil hab.", function(v) num(v, 0), 115),
        Valor = nc("Valor de AC por residente (R$ 2025)", function(v) num(v, 2), 110),
        Tendencia = nc("Tendência do acesso 2020–2025 (% ao ano)", function(v) efx_pct(v), 115),
        Tendencia2225 = nc("Tendência do acesso 2022–2025 (% ao ano)", function(v) efx_pct(v), 115),
        Realizadas = nc("Internações de AC realizadas por mil hab.", function(v) num(v, 2), 115),
        Autossuficiencia = nc("Autossuficiência (%)", function(v) efx_pct(v), 105),
        UTI = nc("Leitos de UTI SUS validados por 100 mil hab.", function(v) num(v, 1), 115),
        Habilitacoes = nc("Serviços de AC habilitados", function(v) num(v, 0), 95),
        Distancia = nc("Distância ao polo de AC (km)", function(v) num(v, 0), 100),
        Quadrante = colDef(name = "Quadrante", minWidth = 190, html = TRUE, cell = function(v) efx_chip_quad(v))))))
}

# Grade 2 × 2 dos quadrantes (acesso × autossuficiência) com as regiões de cada célula
efx_ac_grade_quadrantes <- function(a = EFX_ANO) {
  d <- efx_ac_ano(a); if (nrow(d) == 0) return(NULL)
  med <- d$mediana_acesso_estadual[1]
  celula <- function(alto, autos, titulo, texto) {
    x <- d[d$acesso_alto == alto & d$autossuf_alta == autos, ]
    x <- x[order(-x$internacoes_ac_res_p1000), ]
    div(class = "efx-quad", h5(titulo), p(texto),
        if (nrow(x) == 0) p(em(sprintf("Nenhuma região em %d.", a))) else
          tags$ul(lapply(seq_len(nrow(x)), function(i) tags$li(HTML(sprintf("%s — acesso %s por mil; autossuficiência %s %s",
            esc(x$regiao_saude[i]), num(x$internacoes_ac_res_p1000[i], 2), efx_pct(x$autossuficiencia_ac_pct[i]), efx_chip_quad(x$quadrante[i])))))))
  }
  tagList(
    p(class = "nota-fonte", sprintf("Nas linhas, a autossuficiência (internações de AC realizadas na região ÷ internações de AC de residentes) é de pelo menos 50%% ou inferior a 50%%; nas colunas, o acesso dos residentes situa-se abaixo ou a partir da mediana estadual de %d (%s internações de AC por mil hab.).", a, num(med, 2))),
    div(class = "efx-quad-grade",
      celula(0, 1, "Autossuficiência ≥ 50% · acesso abaixo da mediana", "A região produz alta complexidade, mas seus residentes têm acesso inferior à mediana."),
      celula(1, 1, "Autossuficiência ≥ 50% · acesso na mediana ou acima", "Polos (≥ 100%: atendem também outras regiões) e regiões em transição (50% a 100%)."),
      celula(0, 0, "Autossuficiência < 50% · acesso abaixo da mediana", "Dependentes com baixo acesso: prioridade para regulação e pactuação de fluxos."),
      celula(1, 0, "Autossuficiência < 50% · acesso na mediana ou acima", "Dependentes com acesso adequado: a rede de referência funciona para seus residentes.")))
}

# Painel gráfico dos quadrantes: por região (agrupada por quadrante), acesso (ponto) e autossuficiência (barra)
efx_svg_quadrantes <- function(a = EFX_ANO, w = 680) {
  d <- efx_ac_ano(a); if (nrow(d) == 0) return("")
  d <- d[order(match(d$quadrante, QUADRANTES), -d$internacoes_ac_res_p1000), ]
  med <- d$mediana_acesso_estadual[1]
  pl <- 196; g1 <- 230; gap <- 26; g2 <- w - pl - g1 - gap - 40; lh <- 22; topo <- 48
  xa_max <- max(pretty(c(0, d$internacoes_ac_res_p1000))); sxa <- function(v) pl + v / xa_max * g1
  xb_max <- max(200, max(pretty(c(0, d$autossuficiencia_ac_pct)))); sxb <- function(v) pl + g1 + gap + pmin(v, xb_max) / xb_max * g2
  linhas <- character(0); y <- topo; qant <- ""
  for (i in seq_len(nrow(d))) {
    r <- d[i, ]
    if (r$quadrante != qant) {
      linhas <- c(linhas, sprintf('<text x="4" y="%.1f" font-size="11.5" font-weight="700" fill="%s">%s %s</text>', y + 14, "#0E5A5E", FORMA_QUAD[r$quadrante], esc(QUAD_ROT[r$quadrante])))
      y <- y + 20; qant <- r$quadrante }
    cor <- COR_QUAD[r$quadrante]
    tip <- sprintf("%s: acesso %s internações de AC por mil hab.; autossuficiência %s; %s", r$regiao_saude, num(r$internacoes_ac_res_p1000, 2), efx_pct(r$autossuficiencia_ac_pct), QUAD_ROT[r$quadrante])
    forma <- switch(r$quadrante,
      polo = sprintf('<rect x="%.1f" y="%.1f" width="10" height="10" fill="%s" stroke="#10393b"/>', sxa(r$internacoes_ac_res_p1000) - 5, y + lh / 2 - 5, cor),
      `em transição` = sprintf('<path d="M%.1f %.1f l6 6 l-6 6 l-6 -6 z" fill="%s" stroke="#10393b"/>', sxa(r$internacoes_ac_res_p1000), y + lh / 2 - 6, cor),
      `dependente com acesso adequado` = sprintf('<circle cx="%.1f" cy="%.1f" r="5.5" fill="%s" stroke="#10393b"/>', sxa(r$internacoes_ac_res_p1000), y + lh / 2, cor),
      sprintf('<path d="M%.1f %.1f l6 11 l-12 0 z" fill="%s" stroke="#10393b"/>', sxa(r$internacoes_ac_res_p1000), y + lh / 2 - 6, cor))
    linhas <- c(linhas, sprintf(paste0('<g data-tip="%s"><rect x="0" y="%.1f" width="%d" height="%d" fill="transparent"/>',
      '<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937">%s</text>',
      '<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/>%s',
      '<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s" opacity=".85"/><text x="%.1f" y="%.1f" font-size="11" fill="#374151">%s</text></g>'),
      esc(tip), y, w, lh, pl - 10, y + lh / 2 + 4, esc(r$regiao_saude), pl, pl + g1, y + lh / 2, y + lh / 2, forma,
      sxb(0), y + 5, sxb(r$autossuficiencia_ac_pct) - sxb(0), lh - 10, cor, sxb(r$autossuficiencia_ac_pct) + 4, y + lh / 2 + 4, efx_pct(r$autossuficiencia_ac_pct, 0)))
    y <- y + lh
  }
  h <- y + 22
  ta <- pretty(c(0, xa_max)); tb <- c(0, 50, 100, 200); tb <- tb[tb <= xb_max]
  eixos <- paste0(
    sprintf('<text x="%d" y="12" font-size="11.5" font-weight="600" fill="#374151">Acesso dos residentes</text><text x="%d" y="25" font-size="10.5" fill="#6b7280">internações de AC por mil hab.</text>', pl, pl),
    sprintf('<text x="%d" y="12" font-size="11.5" font-weight="600" fill="#374151">Autossuficiência</text><text x="%d" y="25" font-size="10.5" fill="#6b7280">realizadas na região ÷ de residentes (%%)</text>', pl + g1 + gap, pl + g1 + gap),
    paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10.5" fill="#6b7280">%s</text>', sxa(ta), h - 6, num(ta, 0)), collapse = ""),
    paste(sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10.5" fill="#6b7280">%s</text>', sxb(tb), h - 6, num(tb, 0)), collapse = ""),
    sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%.1f" stroke="#6b7280" stroke-dasharray="4,3"/><text x="%.1f" y="%d" font-size="10.5" fill="#6b7280" text-anchor="middle">mediana %s</text>',
            sxa(med), sxa(med), topo - 6, h - 18, sxa(med), topo - 10, num(med, 2)),
    paste(sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%.1f" stroke="#6b7280" stroke-dasharray="%s"/>', sxb(c(50, 100)), sxb(c(50, 100)), topo - 6, h - 18, c("2,3", "4,3")), collapse = ""),
    sprintf('<text x="%.1f" y="%d" font-size="10.5" fill="#6b7280" text-anchor="middle">50%%</text><text x="%.1f" y="%d" font-size="10.5" fill="#6b7280" text-anchor="middle">100%%</text>',
            sxb(50), topo - 10, sxb(100), topo - 10))
  leg <- paste(sprintf('<span class="leg-item">%s</span>', vapply(QUADRANTES, efx_chip_quad, character(1))), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %.0f" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, sprintf("Quadrantes acesso × autossuficiência em alta complexidade por região de saúde, %d", a),
          sprintf("Quadrantes acesso × autossuficiência em alta complexidade por região de saúde, %d", a), eixos, paste(linhas, collapse = ""), leg)
}

# Quadrante de cada região em cada ano (mudanças ao longo do período)
efx_ac_quadrantes_anos <- function() {
  q <- EFX_QAC; if (nrow(q) == 0) return(NULL)
  anos <- sort(unique(q$ano))
  regs <- unique(q$regiao_saude); regs <- regs[ordem_nome(regs)]
  w <- lapply(anos, function(a) { x <- q[q$ano == a, ]; x$quadrante[match(regs, x$regiao_saude)] })
  t <- tibble::tibble(Região = regs); for (i in seq_along(anos)) t[[as.character(anos[i])]] <- w[[i]]
  t$Mudancas <- apply(as.matrix(t[, as.character(anos)]), 1, function(v) sum(v[-1] != v[-length(v)], na.rm = TRUE))
  cq <- function(v) if (is.na(v)) "—" else sprintf('<span title="%s" style="color:%s;font-size:1.05rem">%s</span>', esc(QUAD_ROT[v]),
                                                  ifelse(v == "dependente com acesso adequado", "#4E8F92", COR_QUAD[v]), FORMA_QUAD[v])
  cols <- setNames(lapply(anos, function(a) colDef(name = as.character(a), align = "center", minWidth = 54, html = TRUE, cell = function(v) cq(v))), as.character(anos))
  tagList(
    div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
      columns = c(list(Região = colDef(minWidth = 180), Mudancas = colDef(name = "Mudanças de quadrante", align = "center", minWidth = 90)), cols))),
    p(class = "nota-fonte", HTML(paste(sprintf("%s = %s", FORMA_QUAD, QUAD_ROT[QUADRANTES]), collapse = " · "))))
}

# Mapa das 16 regiões de saúde coloridas pelo quadrante do ano (malha municipal dissolvida por região)
efx_geo_regioes <- function() {
  if (nrow(GEO) == 0) return(NULL)
  old <- sf::sf_use_s2(); suppressMessages(sf::sf_use_s2(FALSE)); on.exit(suppressMessages(sf::sf_use_s2(old)))
  g <- GEO[!is.na(GEO$co_regsaud), ]
  r <- suppressWarnings(suppressMessages(g |> group_by(co_regsaud) |> summarise(geometry = sf::st_union(geometry), .groups = "drop")))
  r <- suppressWarnings(sf::st_simplify(r, dTolerance = 0.005, preserveTopology = TRUE))
  sf::st_as_sf(r)
}
efx_mapa_regioes <- function(a = EFX_ANO, altura = 520) {
  r <- efx_geo_regioes(); if (is.null(r) || nrow(r) == 0) return(sem_mapa())
  d <- efx_ac_ano(a)
  r <- left_join(r, d, by = "co_regsaud")
  rot <- sprintf("<b>%s</b> (%s municípios, %s hab.)<br>%s %s<br>Acesso: %s internações de AC por mil hab. (mediana %s)<br>Autossuficiência: %s<br>Leitos de UTI SUS validados: %s por 100 mil hab.<br>Distância ao polo de AC: %s km%s",
                 esc(r$regiao_saude), num(r$n_municipios), num(r$populacao), FORMA_QUAD[r$quadrante], QUAD_ROT[r$quadrante],
                 num(r$internacoes_ac_res_p1000, 2), num(r$mediana_acesso_estadual, 2), efx_pct(r$autossuficiencia_ac_pct),
                 num(r$uti_sus_validada_p100mil, 1), num(r$dist_polo_ac_km, 0),
                 ifelse(!is.na(r$publicavel_m3) & r$publicavel_m3 == 1, sprintf("<br>Escore diagnóstico %d: %s", a, efx_esc(r$escore_m3_bc_sub)), ""))
  cent <- suppressWarnings(sf::st_coordinates(sf::st_point_on_surface(r)))
  bb <- bbox_num(r)
  q <- QUADRANTES[QUADRANTES %in% r$quadrante]
  mapa_vazio(altura) |>
    addPolygons(data = r, fillColor = unname(COR_QUAD[r$quadrante]), fillOpacity = 0.9, color = "#ffffff", weight = 2,
                label = lapply(rot, HTML), highlightOptions = highlightOptions(weight = 3.5, color = "#10393b", bringToFront = TRUE)) |>
    addLabelOnlyMarkers(lng = cent[, 1], lat = cent[, 2], label = paste(FORMA_QUAD[r$quadrante], r$regiao_saude),
                        labelOptions = labelOptions(noHide = TRUE, direction = "center", textOnly = TRUE,
                                                    style = list(`font-size` = "10.5px", `font-weight` = "600", color = "#10393b",
                                                                 `text-shadow` = "0 0 3px #fff, 0 0 3px #fff, 0 0 2px #fff"))) |>
    addLegend("bottomright", colors = unname(COR_QUAD[q]), labels = paste(FORMA_QUAD[q], QUAD_ROT[q]), title = paste0("Quadrante ", a), opacity = 1) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4])
}

# Evolução do acesso (internações de AC de residentes por mil hab.) por região, com MT e a mediana
efx_ac_serie_acesso <- function(destaque = NULL) {
  d <- EFX_PAC; if (nrow(d) == 0) return("")
  mt <- d |> group_by(ano) |> summarise(v = 1000 * sum(internacoes_ac_res) / sum(populacao), med = median(internacoes_ac_res_p1000), .groups = "drop")
  regs <- unique(d$regiao_saude)
  if (is.null(destaque)) destaque <- unique(d$regiao_saude[d$quadrante == "polo" | d$publicavel_m3 == 1])
  cores_d <- c("#0E5A5E", "#2E86AB", "#b45309", "#7c3aed")
  series <- lapply(setdiff(regs, destaque), function(r) { x <- d[d$regiao_saude == r, ]
    list(nome = r, cor = COR[["fraco"]], larg = 1.2, dash = "", leg = FALSE, x = x$ano, y = x$internacoes_ac_res_p1000) })
  series <- c(series, lapply(seq_along(destaque), function(i) { x <- d[d$regiao_saude == destaque[i], ]
    list(nome = destaque[i], cor = cores_d[(i - 1) %% 4 + 1], larg = 2.4, dash = "", x = x$ano, y = x$internacoes_ac_res_p1000) }),
    list(list(nome = "Mato Grosso", cor = "#111827", larg = 2.6, dash = "6,3", x = mt$ano, y = mt$v),
         list(nome = "Mediana das regiões", cor = COR[["mt"]], larg = 2, dash = "2,3", x = mt$ano, y = mt$med)))
  svg_linhas(series, fmt = "dec2", titulo = "Internações de alta complexidade de residentes por mil hab., 2020–2025", leg_oculta = "Demais regiões (uma por linha)")
}

# Painel por macrorregião (agregação das regiões)
efx_ac_tabela_macro <- function(a = EFX_ANO) {
  d <- EFX_MAC[EFX_MAC$ano == a, ]; if (nrow(d) == 0) return(NULL)
  d <- d[order(-d$internacoes_ac_res_p1000), ]
  t <- tibble::tibble(Macrorregião = d$macrorregiao, Regiões = d$n_regioes, População = d$populacao,
                      Acesso = d$internacoes_ac_res_p1000, Autossuficiencia = d$autossuficiencia_ac_pct,
                      UTI = d$uti_sus_validada_p100mil, Valor = d$valor_ac_res_pc, Pub = d$n_regioes_publicaveis_m3)
  nc <- function(nome, f, mw = 100) colDef(name = nome, align = "right", minWidth = mw, cell = function(v) f(v))
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, columns = list(
    Macrorregião = colDef(minWidth = 130), Regiões = nc("Regiões de saúde", num, 80), População = nc("População", num),
    Acesso = nc("Internações de AC de residentes por mil hab.", function(v) num(v, 2), 120),
    Autossuficiencia = nc("Autossuficiência (%)", efx_pct), UTI = nc("UTI SUS validada por 100 mil hab.", function(v) num(v, 1), 110),
    Valor = nc("Valor de AC por residente (R$ 2025)", function(v) num(v, 2), 110),
    Pub = nc("Regiões com escore diagnóstico", num, 100))))
}

# Participação de cada região nas internações de AC realizadas em MT (regiões com alguma produção)
efx_ac_participacao <- function() {
  d <- EFX_PAC; if (nrow(d) == 0) return(NULL)
  d <- d |> group_by(ano) |> mutate(share = 100 * internacoes_ac_local / sum(internacoes_ac_local, na.rm = TRUE)) |> ungroup()
  regs <- d |> group_by(regiao_saude) |> summarise(mx = max(share), pub = max(publicavel_m3), .groups = "drop") |> filter(mx > 0) |> arrange(desc(mx))
  anos <- sort(unique(d$ano))
  t <- tibble::tibble(Região = regs$regiao_saude)
  for (a in anos) { x <- d[d$ano == a, ]; t[[as.character(a)]] <- x$share[match(regs$regiao_saude, x$regiao_saude)] }
  t$Escore <- ifelse(regs$pub == 1, "sim", "não")
  lim <- 100 * efx_param("limiar_m3_sem_oferta", 0.01)
  cols <- setNames(lapply(anos, function(a) colDef(name = as.character(a), align = "right", minWidth = 64, html = TRUE,
    cell = function(v) if (is.na(v)) "—" else if (v < lim) sprintf('<span style="color:#6b7280">%s</span>', num(v, 2)) else sprintf("<b>%s</b>", num(v, 2)))), as.character(anos))
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
    columns = c(list(Região = colDef(minWidth = 180), Escore = colDef(name = "Escore diagnóstico publicável", align = "center", minWidth = 110)), cols)))
}

# Escores diagnósticos (regiões publicáveis): gráfico com IC e tabela
efx_m3_dados <- function() {
  f <- EFX_FR[!is.na(EFX_FR$publicavel_m3) & EFX_FR$publicavel_m3 == 1 & is.finite(EFX_FR$escore_bc), ]
  f[order(f$regiao_saude, f$ano), ]
}
efx_m3_grafico <- function() {
  f <- efx_m3_dados(); if (nrow(f) == 0) return("")
  regs <- unique(f$regiao_saude); cores <- setNames(as.list(c("#0E5A5E", "#2E86AB", "#b45309", "#7c3aed")[seq_along(regs)]), regs)
  efx_svg_ic_anos(tibble::tibble(serie = f$regiao_saude, ano = f$ano, est = f$escore_bc, lo = f$ic_inf, hi = f$ic_sup, faixa = f$faixa),
                  cores, titulo = "Escore diagnóstico de alta complexidade (fronteira única 2020–2025) com intervalo de confiança de 95%")
}
efx_m3_tabela <- function() {
  f <- efx_m3_dados(); if (nrow(f) == 0) return(NULL)
  t <- tibble::tibble(Região = f$regiao_saude, Ano = f$ano, Original = f$escore_bcc, Escore = f$escore_bc, ic_inf = f$ic_inf, ic_sup = f$ic_sup,
                      Faixa = f$faixa, cruza = f$ic_cruza_faixa, Quadrante = f$quadrante)
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, groupBy = NULL, columns = list(
    Região = colDef(minWidth = 150), Ano = colDef(align = "center", minWidth = 60),
    Original = colDef(name = "Escore original", align = "right", minWidth = 90, cell = function(v) efx_esc(v)),
    Escore = colDef(name = "Escore corrigido (IC 95%)", align = "right", minWidth = 140, html = TRUE,
                    cell = function(v, i) sprintf('<b>%s</b><div class="sub">%s</div>', efx_esc(v), efx_ic(t$ic_inf[i], t$ic_sup[i]))),
    ic_inf = colDef(show = FALSE), ic_sup = colDef(show = FALSE), cruza = colDef(show = FALSE),
    Faixa = colDef(name = "Faixa (entre as região-anos com escore)", minWidth = 150, html = TRUE, cell = function(v, i) efx_chip(v, t$cruza[i])),
    Quadrante = colDef(name = "Quadrante no ano", minWidth = 190, html = TRUE, cell = function(v) efx_chip_quad(v)))))
}

# Fichas-síntese das regiões (texto padrão do ano), em blocos recolhíveis
efx_fichas_regioes <- function(a = EFX_ANO) {
  f <- efx_fr_ano(a); if (nrow(f) == 0) return(NULL)
  f <- f[order(-f$publicavel_m3, ordem_nome(f$regiao_saude)), ]
  f <- f[c(which(f$publicavel_m3 == 1), which(f$publicavel_m3 != 1)), ]
  tagList(lapply(seq_len(nrow(f)), function(i) tags$details(class = "efx-ficha",
    tags$summary(HTML(sprintf("<b>%s</b> %s%s", esc(f$regiao_saude[i]), efx_chip_quad(f$quadrante[i]),
                              if (isTRUE(f$publicavel_m3[i] == 1)) " · com escore diagnóstico" else ""))),
    p(efx_limpa(f$texto_padrao[i])))))
}

# ---- 5. Produtividade ----------------------------------------------------------------------------
efx_mq_kpis <- function() {
  lst <- lapply(names(MODELOS_MQ), function(md) { x <- efx_mq(md, "estado", "todos", "janela"); x <- x[x$periodo == "2022-2025", ]
    if (nrow(x) == 0) return(NULL)
    kpi_simples(MODELOS_MQ[[md]], efx_var(x$ec[1]), sprintf("aproximação às melhores práticas · média anual 2022–2025 · %s unidades", num(x$n[1])),
                sprintf("%s com melhora (EC > 1) · índice de Malmquist %s", efx_pct(100 * x$n_ec_maior_1[1] / x$n[1], 0), efx_var(x$mi[1])),
                href = PAG_MODELO[[md]]) })
  div(class = "kpi-grade", Filter(Negate(is.null), lst))
}

# Por região de saúde: EC nas três janelas (+ MI 2022–2025), com barras da variação anual 2022–2025
efx_mq_regioes_tabela <- function(modelo, grupo = "todos", id_html = NULL) {
  x <- efx_mq(modelo, "regiao", grupo, "janela"); if (nrow(x) == 0) return(p(class = "nota-fonte", "Sem dados por região."))
  regs <- unique(x$regiao_saude); regs <- regs[ordem_nome(regs)]
  pega <- function(per, campo) { y <- x[x$periodo == per, ]; y[[campo]][match(regs, y$regiao_saude)] }
  t <- tibble::tibble(Região = regs, n = pega("2022-2025", "n"),
                      EC2022 = pega("2020-2022", "ec"), EC2225 = pega("2022-2025", "ec"), EC2025 = pega("2020-2025", "ec"),
                      MI2225 = pega("2022-2025", "mi"), TC2225 = pega("2022-2025", "tc"),
                      melhora = pega("2022-2025", "n_melhora_ec"), piora = pega("2022-2025", "n_piora_ec"))
  ec <- function(nome) colDef(name = nome, align = "right", minWidth = 105, html = TRUE,
                              cell = function(v) if (is.na(v)) "—" else sprintf('%s<div class="sub">%s</div>', efx_var(v, ""), num(v, 3)))
  if (is.null(id_html)) id_html <- paste0("tab-mq-", tolower(modelo), "-", grupo)
  tagList(
    efx_botao_csv(id_html, sprintf("ppsus-mt_malmquist_%s_regioes.csv", tolower(modelo)), "Baixar a tabela (CSV)"),
    div(class = "rolagem-x", reactable(t, elementId = id_html, compact = TRUE, striped = TRUE, pagination = FALSE,
      columnGroups = list(colGroup(name = "Aproximação às melhores práticas (EC), média anual", columns = c("EC2022", "EC2225", "EC2025"))),
      columns = list(Região = colDef(minWidth = 170, sticky = "left"), n = colDef(name = "Unidades (2022–2025)", align = "right", minWidth = 85),
        EC2022 = ec("2020–2022"), EC2225 = ec("2022–2025"), EC2025 = ec("2020–2025"),
        MI2225 = colDef(name = "Índice de Malmquist 2022–2025", align = "right", minWidth = 110, html = TRUE,
                        cell = function(v) if (is.na(v)) "—" else sprintf('%s<div class="sub">%s</div>', efx_var(v, ""), num(v, 3))),
        TC2225 = colDef(name = "TC 2022–2025*", align = "right", minWidth = 80, cell = function(v) num(v, 3), style = list(color = "#6b7280")),
        melhora = colDef(name = "Melhora consistente", align = "right", minWidth = 85),
        piora = colDef(name = "Piora consistente", align = "right", minWidth = 85)))))
}
efx_mq_regioes_barras <- function(modelo, grupo = "todos", periodo = "2022-2025") {
  x <- efx_mq(modelo, "regiao", grupo, "janela"); x <- x[x$periodo == periodo & is.finite(x$ec), ]
  if (nrow(x) == 0) return("")
  x <- x[order(-x$ec), ]
  e <- efx_mq(modelo, "estado", grupo, "janela"); e <- e[e$periodo == periodo, ]
  refs <- if (nrow(e)) list(list(v = 100 * (e$ec[1] - 1), cor = "#111827", rot = sprintf("Mato Grosso: %s", efx_var(e$ec[1], "")))) else list()
  sprintf('<figure class="grafico-svg">%s</figure>', svg_barras_h(x$regiao_saude, 100 * (x$ec - 1), fmt = "pct1", cor = COR_MODELO[[modelo]], refs = refs,
               titulo = sprintf("%s — variação anual média da aproximação às melhores práticas (EC), %s, por região de saúde", MODELOS_MQ[[modelo]], efx_janela_rot(periodo)),
               dicas = sprintf("%s: %s ao ano (índice %s; %s unidades)", x$regiao_saude, efx_var(x$ec, ""), num(x$ec, 3), x$n)))
}

# ---- 6. Arquivos para download (catálogo de arquivos/dados/eficiencia) ------------------------
efx_arquivos <- function(nomes, prefixo = "../arquivos/") {
  f <- file.path(RAIZ, "arquivos", "dados", "eficiencia", "catalogo_eficiencia.csv")
  cat_e <- if (file.exists(f)) tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "")) else tibble::tibble(arquivo = character(0), descricao = character(0))
  itens <- lapply(nomes, function(n) {
    arq <- paste0("dados/eficiencia/", n, ".csv")
    if (!file.exists(file.path(RAIZ, "arquivos", arq))) return(NULL)
    i <- match(arq, cat_e$arquivo); desc <- if (is.na(i)) "" else redigir_descricao_ef(cat_e$descricao[i])
    tags$li(a(href = paste0(prefixo, arq), download = paste0(n, ".csv"), paste0(n, ".csv")), if (nzchar(desc)) paste0(" — ", desc))
  })
  dic <- file.exists(file.path(RAIZ, "arquivos", "dados", "eficiencia", "dicionario_eficiencia.csv"))
  tagList(tags$ul(Filter(Negate(is.null), itens),
    if (dic) tags$li(a(href = paste0(prefixo, "dados/eficiencia/dicionario_eficiencia.csv"), download = "dicionario_eficiencia.csv", "dicionario_eficiencia.csv"),
                     " — dicionário de todos os campos, com o nome gerencial, a unidade, a definição e a fonte.")))
}
