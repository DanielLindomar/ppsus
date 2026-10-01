# =============================================================================
# Observatório PPSUS-MT — biblioteca compartilhada das páginas (Quarto + R/knitr)
#
# As páginas leem somente dados_site/ (gerado por scripts/01_preparar_dados.py e
# scripts/02_preparar_deslocamento.py). Os nomes de arquivos e colunas seguem os
# CONTRATOS da seção 3 de _planejamento/BRIEF_SITE.md; a lista CONTRATOS abaixo
# os reproduz. Arquivo ausente → tabela vazia com as colunas do contrato (e um
# aviso), para que as páginas possam ser escritas e testadas antes dos dados.
#
# readr não é usado (política de Controle de Aplicativos do Windows bloqueia a
# DLL do tzdb): a leitura de CSV usa data.table::fread.
# Gráficos: SVG gerado em R (sem biblioteca JavaScript); mapas: leaflet com o
# GeoJSON embutido e sem camada de fundo externa.
#
# Regra para os agentes das páginas: NÃO editar este arquivo; funções extras
# vão em R/pag_<pagina>.R e são carregadas depois deste.
#
# Índice
#   0. Constantes (cores, grupos, versão)
#   1. Carregadores (CONTRATOS, ler_contrato, GEO, CENT)
#   2. Formatação pt-BR (num, escala, fmt_valor, fmt_eixo, esc)
#   3. Consultas (info_ind, ano_ult, ultimo, resumo_ind, medianas, situacao)
#   4. Componentes htmltools (faixa_versao, kpi, grade_kpis, cartao, navegação)
#   5. SVG (sparkline, posição, linhas multi-série, barras, barra empilhada)
#   6. Mapas leaflet (mapa_municipio, mapa_indicador, mapa_fluxos)
#   7. Tabelas reactable (ranking, tabela_grupo, regiões, municípios, hospitais)
#   8. Deslocamento (desl_mun, top_destinos, top_origens, resumo_desl)
#   9. Rodapé de fontes
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(htmltools); library(reactable); library(leaflet); library(sf)
})

RAIZ <- Sys.getenv("QUARTO_PROJECT_DIR", unset = ".")
source(file.path(RAIZ, "R", "idioma.R"))
ds    <- function(...) file.path(RAIZ, "dados_site", ...)
aviso <- function(...) message("[funcoes.R] ", sprintf(...))

# ---- 0. Constantes ------------------------------------------------------------
VERSAO_SITE <- "0.1"
DATA_VERSAO <- "01/10/2026"
ANOS        <- 2020:2025           # janela analítica publicada
ANO_REF     <- 2025L               # ano de referência dos KPIs (resultados: 2024)

# Cores (BRIEF, seção 5): mun = primária; sec = secundária; mt = cinza do estado
COR <- c(mun = "#0E5A5E", sec = "#2E86AB", mt = "#9CA3AF", bom = "#1b7f4b",
         ruim = "#b42318", neutro = "#6b7280", claro = "#E2EFEE", fraco = "#cfe0df")
# Paleta sequencial para mapas coropléticos (claro → escuro)
PAL_SEQ <- grDevices::colorRampPalette(c("#E2EFEE", "#8CBFBD", "#4E8F92", "#0E5A5E"))

# Grupos do catálogo de indicadores (indicadores.csv, coluna grupo) e rótulos
GRUPOS <- c(contexto = "Contexto", financiamento = "Financiamento",
            capacidade = "Capacidade instalada", atencao_basica = "Atenção básica",
            media_alta = "Média e alta complexidade", deslocamento = "Deslocamento",
            resultados = "Resultados em saúde")
# Grupos que viram abas no perfil municipal
GRUPOS_PERFIL <- c("financiamento", "capacidade", "atencao_basica", "media_alta", "resultados")

# Níveis de complexidade nos arquivos de deslocamento
NIVEIS <- c(total = "Total", MC = "Média complexidade", AC = "Alta complexidade", outro = "Outros")

# ---- 1. Carregadores ------------------------------------------------------------
# Tipos por coluna de cada CSV de dados_site/ (BRIEF, seção 3). Códigos de região,
# macrorregião e CNES são lidos como texto; códigos de município e anos, como inteiro.
CONTRATOS <- list(
  municipios = c(cod_mun6 = "integer", cod_ibge7 = "integer", municipio = "character", slug = "character",
                 co_regsaud = "character", regiao_saude = "character", co_macsaud = "character",
                 macrorregiao = "character", populacao_2025 = "integer", tem_hospital_sus_2025 = "integer"),
  indicadores = c(id = "character", rotulo = "character", grupo = "character", unidade = "character",
                  fmt = "character", sentido = "numeric", fonte = "character", formula = "character",
                  nota = "character", kpi = "integer", ano_max = "integer"),
  serie = c(cod_mun6 = "integer", indicador = "character", ano = "integer", valor = "numeric"),
  regioes = c(co_regsaud = "character", regiao_saude = "character", co_macsaud = "character",
              macrorregiao = "character", n_municipios = "integer", populacao_2025 = "integer"),
  serie_regiao = c(co_regsaud = "character", indicador = "character", ano = "integer", valor = "numeric"),
  serie_mt = c(indicador = "character", ano = "integer", valor = "numeric", mediana = "numeric"),
  hospitais = c(cnes = "character", cod_mun6 = "integer", municipio = "character", regiao_saude = "character",
                ano = "integer", nome_fantasia = "character", natureza_juridica = "character", esfera = "character",
                leitos_sus = "numeric", leitos_uti_sus = "numeric", fte_medicos_sus = "numeric",
                internacoes = "numeric", internacoes_ac = "numeric", diarias_uti = "numeric", valor_total = "numeric",
                taxa_mortalidade_hosp = "numeric", permanencia_media = "numeric", taxa_ocupacao_leitos_sus = "numeric",
                n_meses = "integer"),  # n_meses: adicional ao contrato (competências do CNES no ano)
  deslocamento_mun_ano = c(cod_mun6 = "integer", ano = "integer", internacoes_res = "numeric",
                           no_proprio_mun = "numeric", mesma_regiao = "numeric", outra_regiao = "numeric",
                           pct_proprio_mun = "numeric", pct_mesma_regiao = "numeric", pct_outra_regiao = "numeric",
                           pct_internacoes_fora_mun = "numeric", pct_internacoes_fora_regiao = "numeric",
                           km_medio_internacao = "numeric", destino_principal_cod = "integer",
                           destino_principal_nome = "character", pct_destino_principal = "numeric",
                           n_destinos = "integer", internacoes_recebidas = "numeric", recebidas_de_fora = "numeric",
                           pct_recebidas_de_fora = "numeric", n_origens = "integer", origem_principal_nome = "character",
                           pct_origem_principal = "numeric", internacoes_ac_res = "numeric", pct_ac_fora_mun = "numeric"),
  fluxo_mun_ano = c(ano = "integer", cod_origem = "integer", cod_destino = "integer", nivel = "character",
                    internacoes = "numeric", diarias = "numeric", valor_total = "numeric", obitos = "numeric"),
  fluxo_regiao_ano = c(ano = "integer", co_reg_origem = "character", co_reg_destino = "character",
                       nivel = "character", internacoes = "numeric"),
  polos_ano = c(cod_mun6 = "integer", municipio = "character", ano = "integer", internacoes_recebidas = "numeric",
                recebidas_de_fora = "numeric", pct_recebidas_de_fora = "numeric", n_origens = "integer",
                saldo = "numeric", internacoes_ac_recebidas = "numeric"),
  resumo_deslocamento_ano = c(ano = "integer", nivel = "character", internacoes = "numeric",
                              pct_proprio_mun = "numeric", pct_mesma_regiao = "numeric", pct_outra_regiao = "numeric",
                              km_medio = "numeric", n_res_ignorada = "numeric", n_outra_uf = "numeric",
                              pct_eletivas_proprio = "numeric", pct_eletivas_fora = "numeric"),  # adicionais ao contrato
  outras_uf_ano = c(ano = "integer", uf = "character", nome_uf = "character", internacoes = "numeric"),  # adicional ao contrato
  centroides = c(cod_mun6 = "integer", lon = "numeric", lat = "numeric")
)

# Tabela vazia com as colunas e os tipos de um contrato
tabela_vazia <- function(spec) tibble::as_tibble(lapply(spec, function(t) vector(t, 0)))

as_tipo <- function(x, tipo) switch(tipo, integer = as.integer(x), numeric = as.numeric(x), as.character(x))

# Lê dados_site/<nome>.csv conforme o contrato; tolera arquivo ou coluna ausente
ler_contrato <- function(nome) {
  spec <- CONTRATOS[[nome]]; f <- ds(paste0(nome, ".csv"))
  if (!file.exists(f)) { aviso("arquivo ausente: dados_site/%s.csv (tabela vazia)", nome); return(tabela_vazia(spec)) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  txt <- intersect(names(spec)[spec == "character"], hdr)
  d <- tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                           colClasses = if (length(txt)) list(character = txt) else NULL))
  falta <- setdiff(names(spec), names(d))
  if (length(falta)) {
    aviso("dados_site/%s.csv: colunas do contrato ausentes: %s (criadas vazias)", nome, paste(falta, collapse = ", "))
    for (cn in falta) d[[cn]] <- vector(spec[[cn]], nrow(d))
  }
  for (cn in names(spec)) d[[cn]] <- as_tipo(d[[cn]], spec[[cn]])
  d
}

# Ordenação alfabética que ignora acentos (Água Boa antes de Alta Floresta)
ordem_nome <- function(x) {
  y <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT"); y[is.na(y)] <- x[is.na(y)]
  order(tolower(y))
}

# Ordena e devolve o data frame por nome de município
ordenar_mun <- function(d, col = "municipio") d[ordem_nome(d[[col]]), ]

MUN      <- ordenar_mun(ler_contrato("municipios"))
IND      <- ler_contrato("indicadores")
SER      <- ler_contrato("serie")
REG      <- ler_contrato("regioes")
SERR     <- ler_contrato("serie_regiao")
SERMT    <- ler_contrato("serie_mt")
HOSP     <- ler_contrato("hospitais")
DESL     <- ler_contrato("deslocamento_mun_ano")
FLUXO    <- ler_contrato("fluxo_mun_ano")
FLUXOREG <- ler_contrato("fluxo_regiao_ano")
POLOS    <- ler_contrato("polos_ano")
RESDESL  <- ler_contrato("resumo_deslocamento_ano")
OUTRASUF <- ler_contrato("outras_uf_ano")
CENT     <- ler_contrato("centroides")

# Malha municipal (sf, WGS84) com cod_mun6, municipio, co_regsaud, regiao_saude, slug.
# Preferência: dados_site/geo_mt.geojson (contrato). Alternativa: a malha IBGE
# mínima de arquivos/geo (codarea de 7 dígitos → cod_mun6), com nomes de MUN.
ler_geo <- function() {
  vazio <- sf::st_sf(cod_mun6 = integer(0), municipio = character(0), co_regsaud = character(0),
                     regiao_saude = character(0), geometry = sf::st_sfc(crs = 4326))
  f1 <- ds("geo_mt.geojson"); f2 <- file.path(RAIZ, "arquivos", "geo", "mt_municipios_ibge_minima.geojson")
  g <- NULL
  if (file.exists(f1)) {
    g <- sf::st_read(f1, quiet = TRUE)
    g$cod_mun6 <- as.integer(g$cod_mun6)
    if (!"co_regsaud" %in% names(g)) g$co_regsaud <- NA_character_
    if (!"regiao_saude" %in% names(g)) g$regiao_saude <- NA_character_
    if (!"municipio" %in% names(g)) g$municipio <- NA_character_
  } else if (file.exists(f2)) {
    aviso("dados_site/geo_mt.geojson ausente; usando a malha IBGE de arquivos/geo")
    g <- sf::st_read(f2, quiet = TRUE)
    g$cod_mun6 <- as.integer(substr(as.character(g$codarea), 1, 6))
    i <- match(g$cod_mun6, MUN$cod_mun6)
    g$municipio <- ifelse(is.na(i), as.character(g$cod_mun6), MUN$municipio[i])
    g$co_regsaud <- MUN$co_regsaud[i]; g$regiao_saude <- MUN$regiao_saude[i]
  } else { aviso("nenhuma malha encontrada (mapas desativados)"); return(vazio) }
  g$co_regsaud <- as.character(g$co_regsaud)
  i <- match(g$cod_mun6, MUN$cod_mun6)
  g$slug <- ifelse(is.na(i), as.character(g$cod_mun6), MUN$slug[i])
  if (is.na(sf::st_crs(g))) sf::st_crs(g) <- 4326
  sf::st_transform(g, 4326)[, c("cod_mun6", "municipio", "co_regsaud", "regiao_saude", "slug")]
}
GEO <- ler_geo()

# Coordenadas municipais: contrato centroides.csv (nome histórico; o conteúdo são as SEDES
# municipais do IBGE, Localidades 2022, gravadas pelo script 01). Se ausente, ponto interno
# de cada feição da malha, que é uma aproximação pior da sede em municípios extensos.
if (nrow(CENT) == 0 && nrow(GEO) > 0) {
  pt <- suppressWarnings(sf::st_coordinates(sf::st_point_on_surface(GEO)))
  CENT <- tibble::tibble(cod_mun6 = GEO$cod_mun6, lon = pt[, 1], lat = pt[, 2])
  aviso("dados_site/centroides.csv ausente (sedes municipais); coordenadas calculadas da malha (ponto interno)")
}

# ---- 2. Formatação pt-BR --------------------------------------------------------
# num(1234.5, 1) → "1.234,5"; NA → "—"
num <- function(x, d = 0) ifelse(is.na(x), "—",
  formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))

# escala(5.3e9, "R$ ") → "R$ 5,3 bi"; 12500 → "12,5 mil"; 2522 → "2.522"
escala <- function(x, prefixo = "") {
  a <- abs(x)
  ifelse(is.na(x), "—",
  ifelse(a >= 1e9, paste0(prefixo, num(x / 1e9, 1), " bi"),
  ifelse(a >= 1e6, paste0(prefixo, num(x / 1e6, 1), " mi"),
  ifelse(a >= 1e4, paste0(prefixo, num(x / 1e3, 1), " mil"),
         paste0(prefixo, num(x, 0))))))
}

# Formata segundo a coluna fmt do catálogo: int | dec1 | dec2 | pct1 | brl
fmt_valor <- function(x, fmt) {
  fmt <- if (is.null(fmt) || is.na(fmt)) "dec1" else fmt
  switch(fmt,
    int  = num(x, 0), dec1 = num(x, 1), dec2 = num(x, 2), dec3 = num(x, 3),
    pct1 = ifelse(is.na(x), "—", paste0(num(x, 1), "%")),
    pct2 = ifelse(is.na(x), "—", paste0(num(x, 2), "%")),
    brl  = escala(x, "R$ "),
    num(x, 2))
}

# Rótulos de eixo para um vetor de quebras (mesma escala para todas)
fmt_eixo <- function(v) {
  a <- max(abs(v), na.rm = TRUE)
  if (a >= 1e9) return(paste0(num(v / 1e9, 1), " bi"))
  if (a >= 1e6) return(paste0(num(v / 1e6, 1), " mi"))
  if (a >= 1e4) return(paste0(num(v / 1e3, 0), " mil"))
  d <- if (all(abs(v - round(v)) < 1e-9)) 0 else if (a >= 10) 1 else 2
  num(v, d)
}

# Escapa texto para atributos/HTML
esc <- function(x) { x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE); gsub("\"", "&quot;", x, fixed = TRUE) }

# Ordinal pt-BR: 3 → "3º"
ordinal <- function(n) ifelse(is.na(n), "—", paste0(n, "º"))

# ---- 3. Consultas -----------------------------------------------------------------
# Linha do catálogo para um indicador (linha "genérica" se o id não existir)
info_ind <- function(id) {
  r <- IND[IND$id == id, ]
  if (nrow(r) == 0) {
    aviso("indicador '%s' não está em indicadores.csv", id)
    r <- tibble::tibble(id = id, rotulo = id, grupo = NA_character_, unidade = "", fmt = "dec1", sentido = 0,
                        fonte = "", formula = "", nota = "", kpi = 0L, ano_max = ANO_REF)
  }
  r[1, ]
}
rotulo_grupo <- function(g) ifelse(g %in% names(GRUPOS), GRUPOS[g], g)

# Município: linha de MUN, nome, slug, região e URL do perfil
info_mun <- function(cod) {
  m <- MUN[MUN$cod_mun6 == cod, ]
  if (nrow(m) == 0) { aviso("município %s não está em municipios.csv", cod)
    m <- tibble::tibble(cod_mun6 = as.integer(cod), cod_ibge7 = NA_integer_, municipio = as.character(cod),
                        slug = as.character(cod), co_regsaud = NA_character_, regiao_saude = NA_character_,
                        co_macsaud = NA_character_, macrorregiao = NA_character_, populacao_2025 = NA_integer_,
                        tem_hospital_sus_2025 = NA_integer_) }
  m[1, ]
}
nome_mun  <- function(cod) { i <- match(cod, MUN$cod_mun6); ifelse(is.na(i), as.character(cod), MUN$municipio[i]) }
slug_mun  <- function(cod) { i <- match(cod, MUN$cod_mun6); ifelse(is.na(i), as.character(cod), MUN$slug[i]) }
regiao_de <- function(cod) MUN$co_regsaud[match(cod, MUN$cod_mun6)]
nome_regiao <- function(co_reg) { i <- match(co_reg, REG$co_regsaud); ifelse(is.na(i), as.character(co_reg), REG$regiao_saude[i]) }
muns_regiao <- function(co_reg) MUN$cod_mun6[!is.na(MUN$co_regsaud) & MUN$co_regsaud == co_reg]
# URLs relativas: prefixo depende da profundidade da página que chama
url_mun <- function(cod, prefixo = "../municipios/") paste0(prefixo, slug_mun(cod), ".html")
url_ind <- function(id, prefixo = "../indicadores/") paste0(prefixo, id, ".html")

# Série de um indicador para um município (ano, valor), sem NA, ordenada
serie_mun <- function(id, cod) {
  s <- SER[SER$indicador == id & SER$cod_mun6 == cod & !is.na(SER$valor), c("ano", "valor")]
  s[order(s$ano), ]
}
# Valores de todos os municípios em um ano (cod_mun6, valor)
valores_ano <- function(id, ano) SER[SER$indicador == id & SER$ano == ano, c("cod_mun6", "valor")]

# Último ano com dado do indicador (limitado por ano_max do catálogo)
ano_ult <- function(id) {
  r <- info_ind(id); s <- SER[SER$indicador == id & !is.na(SER$valor), ]
  a <- if (nrow(s)) max(s$ano) else NA_integer_
  if (is.na(a) && is.na(r$ano_max)) return(NA_integer_)
  as.integer(min(a, r$ano_max, na.rm = TRUE))
}

# Último valor disponível para um município (opcionalmente até um ano)
ultimo <- function(id, cod, ate = NULL) {
  s <- serie_mun(id, cod); if (!is.null(ate) && !is.na(ate)) s <- s[s$ano <= ate, ]
  if (nrow(s) == 0) list(valor = NA_real_, ano = NA_integer_) else list(valor = tail(s$valor, 1), ano = tail(s$ano, 1))
}
# Valor de um indicador para um município e ano (NA se não houver)
valor_ind <- function(id, cod, ano) { v <- SER$valor[SER$indicador == id & SER$cod_mun6 == cod & SER$ano == ano]; if (length(v)) v[1] else NA_real_ }

# Agregados do estado e da região (serie_mt.csv / serie_regiao.csv)
valor_mt <- function(id, ano) { v <- SERMT$valor[SERMT$indicador == id & SERMT$ano == ano]; if (length(v)) v[1] else NA_real_ }
mediana_mt <- function(id, ano) {
  v <- SERMT$mediana[SERMT$indicador == id & SERMT$ano == ano]
  if (length(v) && !is.na(v[1])) return(v[1])
  median(valores_ano(id, ano)$valor, na.rm = TRUE)
}
valor_regiao <- function(id, co_reg, ano) {
  v <- SERR$valor[SERR$indicador == id & SERR$co_regsaud == co_reg & SERR$ano == ano]; if (length(v)) v[1] else NA_real_ }
mediana_regiao <- function(id, co_reg, ano) {
  v <- valores_ano(id, ano); median(v$valor[v$cod_mun6 %in% muns_regiao(co_reg)], na.rm = TRUE) }

# Posição (1 = maior valor) de um valor entre um vetor
posicao <- function(valor, vals) if (is.na(valor)) NA_integer_ else sum(vals > valor, na.rm = TRUE) + 1L

# Resumo completo de um indicador para um município: valor e ano, posição entre os
# 142 e na região, medianas de MT e da região, valor agregado de MT e da região.
resumo_ind <- function(id, cod) {
  r <- info_ind(id); a <- ano_ult(id); reg <- regiao_de(cod)
  me <- ultimo(id, cod, ate = a)
  v <- if (is.na(a)) valores_ano(id, -1L) else valores_ano(id, a)
  vr <- v[v$cod_mun6 %in% muns_regiao(reg), ]
  no_ano <- !is.na(me$ano) && !is.na(a) && me$ano == a
  list(valor = me$valor, ano = me$ano, ano_ref = a, co_regsaud = reg,
       pos_mt = if (no_ano) posicao(me$valor, v$valor) else NA_integer_, n_mt = sum(!is.na(v$valor)),
       pos_reg = if (no_ano) posicao(me$valor, vr$valor) else NA_integer_, n_reg = sum(!is.na(vr$valor)),
       med_mt = if (is.na(a)) NA_real_ else mediana_mt(id, a), med_reg = median(vr$valor, na.rm = TRUE),
       mt = if (is.na(a)) NA_real_ else valor_mt(id, a),
       reg = if (is.na(a) || is.na(reg)) NA_real_ else valor_regiao(id, reg, a),
       vals = setNames(v$valor, v$cod_mun6))
}

# Situação frente a uma referência (mediana), considerando o sentido do indicador:
# +1 maior é melhor; -1 menor é melhor; 0 contexto (neutro). Devolve texto ▲/▼ e classe.
situacao <- function(valor, ref, sentido) {
  if (is.na(valor) || is.na(ref)) return(list(txt = "—", cls = "sit-neutra"))
  if (isTRUE(all.equal(valor, ref))) return(list(txt = "= mediana", cls = "sit-neutra"))
  acima <- valor > ref
  txt <- if (acima) "▲ acima" else "▼ abaixo"
  cls <- if (is.na(sentido) || sentido == 0) "sit-neutra"
         else if ((acima && sentido > 0) || (!acima && sentido < 0)) "sit-boa" else "sit-ruim"
  list(txt = txt, cls = cls)
}
span_sit <- function(sit) span(class = paste("sit", sit$cls), sit$txt)

# ---- 4. Componentes htmltools --------------------------------------------------------
TEXTO_VERSAO <- paste0("<b>Versão ", VERSAO_SITE, "</b> — dados e indicadores 2020–2025; escores de eficiência (DEA) ",
                       "e produtividade (Malmquist) em preparação. Cada valor mostra a fonte e o ano a que se refere.")
faixa_versao <- function(texto = TEXTO_VERSAO) div(class = "faixa-versao", HTML(texto))
faixa_construcao <- function(texto) div(class = "faixa-construcao", HTML(texto))

# Cartão KPI genérico: rótulo, valor formatado, linha de contexto (unidade · ano), comparação opcional
kpi_simples <- function(rotulo, valor, meta = "", comp = NULL, href = NULL) {
  div(class = "kpi",
      div(class = "kpi-rotulo", if (is.null(href)) rotulo else a(href = href, rotulo)),
      div(class = "kpi-valor", valor),
      if (nzchar(meta)) div(class = "kpi-meta", meta),
      if (!is.null(comp)) div(class = "kpi-comp", comp))
}

# Ressalva curta do catálogo (coluna nota_curta, adicional ao contrato), para os cartões; "" se não houver
nota_curta_ind <- function(r) {
  n <- if ("nota_curta" %in% names(r)) as.character(r$nota_curta[1]) else NA_character_
  if (is.na(n) || !nzchar(n)) "" else n
}
# Linha de ressalva visível no cartão KPI (NULL quando o indicador não tem nota curta)
nota_kpi <- function(r) { n <- nota_curta_ind(r); if (nzchar(n)) div(class = "kpi-nota", paste0("Ressalva: ", n)) }

# Cartão KPI de um indicador para um município, com mediana MT/região, situação ▲/▼ e ressalva
kpi_ind <- function(id, cod, prefixo_ind = "../indicadores/") {
  r <- info_ind(id); s <- resumo_ind(id, cod)
  sit <- situacao(s$valor, s$med_mt, r$sentido)
  comp <- tagList(sprintf("Mediana MT: %s · região: %s", fmt_valor(s$med_mt, r$fmt), fmt_valor(s$med_reg, r$fmt)),
                  if (sit$cls != "sit-neutra") span_sit(sit), nota_kpi(r))
  kpi_simples(r$rotulo, fmt_valor(s$valor, r$fmt),
              paste0(r$unidade, if (!is.na(s$ano)) paste0(" · ", s$ano) else ""), comp, href = url_ind(id, prefixo_ind))
}

# Grade com os KPIs do catálogo (kpi = 1) ou com os ids informados
grade_kpis <- function(cod, ids = NULL, prefixo_ind = "../indicadores/") {
  if (is.null(ids)) ids <- IND$id[!is.na(IND$kpi) & IND$kpi == 1]
  if (length(ids) == 0) return(p(class = "nota-fonte", "Catálogo de indicadores ainda não carregado."))
  div(class = "kpi-grade", lapply(ids, kpi_ind, cod = cod, prefixo_ind = prefixo_ind))
}

# Cartões de navegação (página inicial e seções)
cartao <- function(href, titulo, texto, desativado = FALSE)
  a(class = paste("cartao", if (desativado) "desativado"), href = href, h4(titulo), p(texto))
cartoes <- function(...) div(class = "cartoes", ...)

# Seletores "Ir para um município" / "Ir para um indicador" (usados na página inicial)
seletor_municipios <- function(id_html = "ir-mun", prefixo = "municipios/", rotulo = "Ir para um município") {
  div(tags$label(`for` = id_html, rotulo),
      tags$select(id = id_html, class = "form-select", `aria-label` = rotulo,
                  onchange = "if (this.value) window.location = this.value",
                  tags$option(value = "", sprintf("Escolha um dos %d municípios…", nrow(MUN))),
                  lapply(seq_len(nrow(MUN)), function(j) tags$option(value = paste0(prefixo, MUN$slug[j], ".html"), MUN$municipio[j]))))
}
seletor_indicadores <- function(id_html = "ir-ind", prefixo = "indicadores/", rotulo = "Ir para um indicador", atual = NULL) {
  ind <- IND[!is.na(IND$grupo), ]
  grupos <- intersect(names(GRUPOS), unique(ind$grupo))
  div(tags$label(`for` = id_html, rotulo),
      tags$select(id = id_html, class = "form-select", `aria-label` = rotulo,
                  onchange = "if (this.value) window.location = this.value",
                  tags$option(value = "", sprintf("Escolha um dos %d indicadores…", nrow(ind))),
                  lapply(grupos, function(g) { x <- ind[ind$grupo == g, ]
                    tags$optgroup(label = GRUPOS[[g]], lapply(seq_len(nrow(x)), function(j)
                      tags$option(value = paste0(prefixo, x$id[j], ".html"),
                                  selected = if (!is.null(atual) && x$id[j] == atual) NA else NULL, x$rotulo[j]))) })))
}

# Navegação anterior / seletor / próximo entre os perfis municipais (ordem alfabética)
navegacao_municipio <- function(cod, prefixo = "") {
  if (nrow(MUN) == 0) return(NULL)
  i <- match(cod, MUN$cod_mun6); if (is.na(i)) i <- 1L
  ant <- MUN[ifelse(i == 1, nrow(MUN), i - 1), ]; prox <- MUN[ifelse(i == nrow(MUN), 1, i + 1), ]
  div(class = "nav-mun",
      a(class = "btn btn-sm btn-outline-primary", href = paste0(prefixo, ant$slug, ".html"), paste("←", ant$municipio)),
      tags$select(class = "form-select form-select-sm", `aria-label` = "Ir para outro município",
                  onchange = "if (this.value) window.location = this.value",
                  lapply(seq_len(nrow(MUN)), function(j) tags$option(value = paste0(prefixo, MUN$slug[j], ".html"),
                         selected = if (MUN$cod_mun6[j] == cod) NA else NULL, MUN$municipio[j]))),
      a(class = "btn btn-sm btn-outline-primary", href = paste0(prefixo, prox$slug, ".html"), paste(prox$municipio, "→")))
}

# Navegação entre páginas de indicador (voltar ao catálogo / seletor por grupo)
navegacao_indicador <- function(id, prefixo = "") {
  div(class = "nav-mun",
      a(class = "btn btn-sm btn-outline-primary", href = paste0(prefixo, "index.html"), "← Todos os indicadores"),
      seletor_indicadores("sel-ind", prefixo = prefixo, rotulo = "", atual = id)$children[[2]])
}

# ---- 5. SVG -----------------------------------------------------------------------------
# Minissérie (sparkline) para tabelas
svg_sparkline <- function(x, y, w = 110, h = 28, cor = COR[["mun"]]) {
  ok <- is.finite(y); x <- x[ok]; y <- y[ok]
  if (length(y) < 2) return("")
  o <- order(x); x <- x[o]; y <- y[o]
  xr <- range(x); yr <- range(y); if (diff(yr) == 0) yr <- yr + c(-1, 1)
  px <- 3 + (x - xr[1]) / diff(xr) * (w - 6); py <- h - 3 - (y - yr[1]) / diff(yr) * (h - 6)
  sprintf('<svg class="spark" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="Série %d–%d"><title>Série %d–%d</title><polyline fill="none" stroke="%s" stroke-width="1.6" points="%s"/><circle cx="%.1f" cy="%.1f" r="2.4" fill="%s"/></svg>',
          w, h, w, h, xr[1], xr[2], xr[1], xr[2], cor,
          paste(sprintf("%.1f,%.1f", px, py), collapse = " "), tail(px, 1), tail(py, 1), cor)
}

# Faixa de posição: pontos = municípios (vals nomeado por cod_mun6), ponto escuro = destaque,
# traço pontilhado = mediana MT
svg_posicao <- function(vals, destaque, med_mt, fmt, w = 130, h = 26) {
  vals <- vals[is.finite(vals)]
  if (length(vals) < 2 || !as.character(destaque) %in% names(vals)) return("")
  destaque <- as.character(destaque)
  r <- range(c(vals, med_mt), na.rm = TRUE); if (diff(r) == 0) r <- r + c(-1, 1)
  sx <- function(v) 6 + (v - r[1]) / diff(r) * (w - 12)
  nomes <- nome_mun(as.integer(names(vals)))
  outros <- names(vals) != destaque
  # Demais municípios em um único <path> (um traço de comprimento zero com extremidade arredondada por
  # município), em vez de 142 <circle> com dica individual: ~0,8 MB a menos por perfil.
  pts <- sprintf('<path d="%s" fill="none" stroke="#b8cdcc" stroke-width="5" stroke-linecap="round"><title>Demais municípios de Mato Grosso (%d)</title></path>',
                 paste(sprintf("M%.1f 13h0", sx(vals[outros])), collapse = " "), sum(outros))
  mt <- if (is.finite(med_mt)) sprintf('<line x1="%.1f" x2="%.1f" y1="4" y2="22" stroke="#6b7280" stroke-dasharray="2,2" data-tip="Mediana MT: %s"/>',
                                       sx(med_mt), sx(med_mt), fmt_valor(med_mt, fmt)) else ""
  eu <- sprintf('<circle cx="%.1f" cy="13" r="5.5" fill="%s" stroke="#fff" stroke-width="1.5" data-tip="%s: %s"/>',
                sx(vals[[destaque]]), COR[["mun"]], esc(nomes[!outros]), fmt_valor(vals[[destaque]], fmt))
  sprintf('<svg class="strip" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="Posição entre os municípios de Mato Grosso"><title>Posição entre os municípios</title><line x1="6" x2="%d" y1="13" y2="13" stroke="#e5e7eb" stroke-width="2"/>%s%s%s</svg>',
          w, h, w, h, w - 6, mt, pts, eu)
}

# Gráfico de linhas multi-série com eixos, grade e legenda.
# series: lista de list(nome, cor, larg, dash, x, y, leg = TRUE); leg_oculta: rótulo único
# para as séries com leg = FALSE (ex.: "Municípios da região (um por linha)").
svg_linhas <- function(series, fmt, titulo = "", w = 680, h = 260, leg_oculta = "Outros municípios (um por linha)") {
  ys <- unlist(lapply(series, `[[`, "y")); xs <- unlist(lapply(series, `[[`, "x"))
  ys <- ys[is.finite(ys)]
  if (length(ys) < 2) return("")
  pl <- 62; pr <- 14; pt <- 12; pb <- 26
  xr <- range(xs); if (diff(xr) == 0) xr <- xr + c(-1, 1)
  yt <- pretty(range(ys), n = 5); yr <- range(yt)
  sx <- function(x) pl + (x - xr[1]) / diff(xr) * (w - pl - pr)
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="11" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, fmt_eixo(yt)), collapse = "")
  xt <- pretty(xr, n = 6); xt <- xt[xt >= xr[1] & xt <= xr[2] & xt == round(xt)]
  eixo_x <- paste(sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%d</text>',
                          sx(xt), h - 8, as.integer(xt)), collapse = "")
  zero <- if (yr[1] < 0 && yr[2] > 0) sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#9ca3af"/>', pl, w - pr, sy(0), sy(0)) else ""
  linhas <- vapply(series, function(s) {
    ok <- is.finite(s$y); o <- order(s$x); x <- s$x[o]; y <- s$y[o]; ok <- ok[o]
    if (sum(ok) == 0) return("")
    dash <- if (!is.null(s$dash) && nzchar(s$dash)) s$dash else ""
    seg <- paste0(ifelse(c(TRUE, !ok[-length(ok)]) & ok, "M", "L")[ok], sprintf("%.1f %.1f", sx(x[ok]), sy(y[ok])), collapse = " ")
    pts <- paste(sprintf('<circle class="pt" cx="%.1f" cy="%.1f" r="%s" fill="%s" stroke="transparent" stroke-width="9" data-tip="%s · %d: %s"/>',
                         sx(x[ok]), sy(y[ok]), if (s$larg >= 2.5) "3" else "2.2", s$cor, esc(s$nome), as.integer(x[ok]),
                         fmt_valor(y[ok], fmt)), collapse = "")
    sprintf('<g class="serie"><path class="linha" d="%s" fill="none" stroke="%s" stroke-width="%s" %s data-tip="%s"/>%s</g>', seg, s$cor, s$larg,
            if (nzchar(dash)) sprintf('stroke-dasharray="%s"', dash) else "", esc(s$nome), pts)
  }, character(1))
  series_leg <- Filter(function(s) !isFALSE(s$leg), series)
  if (length(series_leg) < length(series)) series_leg <- c(list(list(nome = leg_oculta, cor = COR[["fraco"]], larg = 1.5, dash = "")), series_leg)
  leg <- paste(vapply(series_leg, function(s) { dash <- if (!is.null(s$dash) && nzchar(s$dash)) s$dash else ""
    sprintf('<span class="leg-item"><svg width="22" height="8" aria-hidden="true"><line x1="0" x2="22" y1="4" y2="4" stroke="%s" stroke-width="%s" %s/></svg>%s</span>',
            s$cor, s$larg, if (nzchar(dash)) sprintf('stroke-dasharray="%s"', dash) else "", esc(s$nome)) }, character(1)), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(titulo), esc(titulo), grade, zero, eixo_x, paste(linhas, collapse = ""), leg)
}

# Barras horizontais: rotulos, valores; hrefs opcionais (rótulo vira link); refs = lista de
# list(v, cor, rot) para linhas de referência (medianas)
svg_barras_h <- function(rotulos, valores, fmt, titulo = "", cor = COR[["sec"]], hrefs = NULL, refs = list(),
                         w = 680, lh = 24, pl = 190, pr = 110, dicas = NULL) {
  ok <- is.finite(valores); rotulos <- rotulos[ok]; valores <- valores[ok]; if (!is.null(hrefs)) hrefs <- hrefs[ok]
  n <- length(valores); if (n == 0) return("")
  refv <- unlist(lapply(refs, `[[`, "v"))
  h <- n * lh + if (length(refs)) 44 else 12
  lim <- range(c(0, valores, refv), na.rm = TRUE); if (diff(lim) == 0) lim <- lim + c(0, 1)
  sx <- function(x) pl + (x - lim[1]) / diff(lim) * (w - pl - pr)
  y0 <- (seq_len(n) - 1) * lh
  if (is.null(dicas)) dicas <- paste0(rotulos, ": ", fmt_valor(valores, fmt))
  txt <- sprintf('<text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#1f2937">%s</text>', pl - 8, y0 + 17, esc(rotulos))
  if (!is.null(hrefs)) txt <- sprintf('<a href="%s">%s</a>', hrefs, txt)
  barras <- paste(sprintf('%s<rect x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s" data-tip="%s"/><text x="%.1f" y="%.1f" font-size="11" fill="#374151">%s</text>',
                          txt, pmin(sx(0), sx(valores)), y0 + 5, abs(sx(valores) - sx(0)), lh - 8, cor, esc(dicas),
                          pmax(sx(0), sx(valores)) + 5, y0 + 17, fmt_valor(valores, fmt)), collapse = "")
  ref <- paste(vapply(seq_along(refs), function(i) { r <- refs[[i]]; if (!is.finite(r$v)) return("")
    sprintf('<line x1="%.1f" x2="%.1f" y1="0" y2="%d" stroke="%s" stroke-dasharray="4,3" stroke-width="1.5"/><text x="%.1f" y="%d" font-size="11" fill="%s" text-anchor="middle">%s</text>',
            sx(r$v), sx(r$v), n * lh + 4 + 13 * (i - 1), r$cor, sx(r$v), n * lh + 16 + 13 * (i - 1), r$cor, esc(r$rot)) }, character(1)), collapse = "")
  sprintf('<svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s</svg>', w, h, esc(titulo), esc(titulo), barras, ref)
}

# Barra empilhada 100% (ex.: próprio município / mesma região / outra região)
svg_barra_empilhada <- function(partes, cores = c(COR[["mun"]], COR[["sec"]], COR[["mt"]]), titulo = "", w = 680, h = 34) {
  partes <- partes[is.finite(partes) & partes > 0]
  if (length(partes) == 0) return("")
  p <- 100 * partes / sum(partes); x0 <- c(0, cumsum(p))[seq_along(p)]
  cores <- rep_len(cores, length(p))
  sx <- function(v) v / 100 * w
  ret <- paste(sprintf('<rect x="%.1f" y="0" width="%.1f" height="%d" fill="%s" data-tip="%s: %s"/>%s',
                       sx(x0), sx(p), h, cores, esc(names(p)), paste0(num(p, 1), "%"),
                       ifelse(p >= 8, sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="12" fill="#fff" font-weight="600">%s</text>', sx(x0 + p / 2), h / 2 + 4, paste0(num(p, 0), "%")), "")), collapse = "")
  leg <- paste(sprintf('<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="%s"/></svg>%s (%s)</span>', cores, esc(names(p)), paste0(num(p, 1), "%")), collapse = "")
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" height="%d" role="img" aria-label="%s"><title>%s</title>%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, h, esc(titulo), esc(titulo), ret, leg)
}

# Série do município comparada às medianas de MT e da região (SVG); "" se sem série
serie_comparada <- function(id, cod) {
  r <- info_ind(id); me <- serie_mun(id, cod); reg <- regiao_de(cod)
  if (nrow(me) < 2) return("")
  s <- SER[SER$indicador == id & SER$ano %in% ANOS, ]
  meds <- s |> group_by(ano) |> summarise(reg = median(valor[cod_mun6 %in% muns_regiao(reg)], na.rm = TRUE),
                                          mt = median(valor, na.rm = TRUE), .groups = "drop")
  svg_linhas(list(
    list(nome = nome_mun(cod), cor = COR[["mun"]], larg = 2.8, dash = "", x = me$ano, y = me$valor),
    list(nome = paste0("Mediana da região (", nome_regiao(reg), ")"), cor = COR[["sec"]], larg = 1.8, dash = "6,4", x = meds$ano, y = meds$reg),
    list(nome = "Mediana MT", cor = COR[["mt"]], larg = 1.8, dash = "2,3", x = meds$ano, y = meds$mt)),
    fmt = r$fmt, titulo = paste0(r$rotulo, " — ", nome_mun(cod)))
}

# Série do indicador para o estado: mediana municipal + agregado MT (+ região opcional)
serie_indicador <- function(id, co_reg = NULL, com_municipios = FALSE) {
  r <- info_ind(id)
  s <- SER[SER$indicador == id & SER$ano %in% ANOS, ]
  if (n_distinct(s$ano[!is.na(s$valor)]) < 2) return("")
  meds <- s |> group_by(ano) |> summarise(med = median(valor, na.rm = TRUE), .groups = "drop")
  mt <- SERMT[SERMT$indicador == id & SERMT$ano %in% ANOS, ]
  series <- list()
  if (com_municipios) series <- lapply(unique(s$cod_mun6), function(m) { x <- s[s$cod_mun6 == m, ]
    list(nome = nome_mun(m), cor = COR[["fraco"]], larg = 1, dash = "", leg = FALSE, x = x$ano, y = x$valor) })
  series <- c(series, list(list(nome = "Mediana dos municípios", cor = COR[["mun"]], larg = 3, dash = "", x = meds$ano, y = meds$med)))
  if (nrow(mt)) series <- c(series, list(list(nome = "Mato Grosso (agregado)", cor = COR[["mt"]], larg = 2, dash = "2,3", x = mt$ano, y = mt$valor)))
  if (!is.null(co_reg)) { rr <- SERR[SERR$indicador == id & SERR$co_regsaud == co_reg & SERR$ano %in% ANOS, ]
    if (nrow(rr)) series <- c(series, list(list(nome = paste0("Região ", nome_regiao(co_reg)), cor = COR[["sec"]], larg = 2, dash = "6,4", x = rr$ano, y = rr$valor))) }
  svg_linhas(series, fmt = r$fmt, titulo = paste0(r$rotulo, " — evolução ", ANOS[1], "–", ano_ult(id)), leg_oculta = "Municípios (um por linha)")
}

# ---- 6. Mapas leaflet (GeoJSON embutido, sem tiles externos) ------------------------------
mapa_vazio <- function(altura) leaflet(height = altura, options = leafletOptions(zoomSnap = 0.25, attributionControl = FALSE))
sem_mapa <- function() p(class = "nota-fonte", "Mapa indisponível: malha municipal não carregada.")

# Clique em um polígono com layerId (slug) abre prefixo + slug + ".html"
js_clique <- function(prefixo) sprintf("function(el, x) { var map = this; map.eachLayer(function(l) {
  if (l.options && l.options.layerId) { l.on('click', function() { window.location = '%s' + l.options.layerId + '.html'; });
    l.on('mouseover', function() { l.setStyle({weight: 2.5}); }); l.on('mouseout', function() { l.setStyle({weight: 1}); }); } }); }", prefixo)

bbox_num <- function(g) as.numeric(sf::st_bbox(g))

# Mapa dos 141 municípios; destaque (cod) em cor primária, sua região em tom médio,
# demais em claro. Clique → perfil (prefixo + slug + .html). zoom_regiao aproxima na região.
mapa_municipio <- function(cod = NULL, altura = 360, prefixo = "", zoom_regiao = FALSE) {
  if (nrow(GEO) == 0) return(sem_mapa())
  g <- GEO; reg <- if (!is.null(cod)) regiao_de(cod) else NA
  na_reg <- !is.na(reg) & !is.na(g$co_regsaud) & g$co_regsaud == reg
  cor <- ifelse(!is.null(cod) & g$cod_mun6 %in% cod, COR[["mun"]], ifelse(na_reg, "#8CBFBD", COR[["claro"]]))
  rot <- ifelse(is.na(g$regiao_saude), g$municipio, paste0(g$municipio, " · ", g$regiao_saude))
  bb <- if (zoom_regiao && any(na_reg)) bbox_num(g[na_reg, ]) else bbox_num(g)
  mapa_vazio(altura) |>
    addPolygons(data = g, layerId = ~slug, fillColor = cor, fillOpacity = 1, color = "#ffffff", weight = 1,
                label = paste0(rot, " — clique para abrir o perfil")) |>
    fitBounds(bb[1] - 0.2, bb[2] - 0.2, bb[3] + 0.2, bb[4] + 0.2) |>
    htmlwidgets::onRender(js_clique(prefixo))
}

# Mapa coroplético de um indicador (quantis, paleta sequencial, legenda formatada);
# clique → perfil. Municípios sem dado em cinza claro.
mapa_indicador <- function(id, ano = NULL, altura = 460, prefixo = "../municipios/", n_classes = 5) {
  if (nrow(GEO) == 0) return(sem_mapa())
  r <- info_ind(id); if (is.null(ano)) ano <- ano_ult(id)
  u <- if (is.na(ano)) tibble::tibble(cod_mun6 = integer(0), valor = numeric(0)) else valores_ano(id, ano)
  g <- left_join(GEO, u, by = "cod_mun6")
  v <- g$valor
  if (sum(is.finite(v)) < 2) {
    return(mapa_vazio(altura) |> addPolygons(data = g, fillColor = "#f3f4f6", fillOpacity = 1, color = "#fff", weight = 1, label = ~municipio) |>
             addControl(html = "<div class='nota-fonte'>Sem dados para este indicador.</div>", position = "topright"))
  }
  br <- unique(quantile(v, probs = seq(0, 1, length.out = n_classes + 1), na.rm = TRUE))
  pal <- if (length(br) >= 3) colorBin(PAL_SEQ(length(br) - 1), domain = v, bins = br, na.color = "#f3f4f6")
         else colorNumeric(PAL_SEQ(5), domain = v, na.color = "#f3f4f6")
  rot <- sprintf("<b>%s</b><br>%s (%s)%s", esc(g$municipio), fmt_valor(g$valor, r$fmt), ano,
                 ifelse(is.na(g$regiao_saude), "", paste0("<br><span style='color:#6b7280'>", esc(g$regiao_saude), "</span>")))
  bb <- bbox_num(g)
  mapa_vazio(altura) |>
    addPolygons(data = g, layerId = ~slug, fillColor = pal(v), fillOpacity = 0.95, color = "#ffffff", weight = 1,
                label = lapply(paste0(rot, "<br><i>clique para abrir o perfil</i>"), HTML)) |>
    addLegend("bottomright", pal = pal, values = v, title = esc(r$unidade), opacity = 0.9, na.label = "sem dado",
              labFormat = function(type, cuts, p) {
                if (type == "bin") { n <- length(cuts); paste0(fmt_valor(cuts[-n], r$fmt), " – ", fmt_valor(cuts[-1], r$fmt)) }
                else fmt_valor(cuts, r$fmt) }) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
    htmlwidgets::onRender(js_clique(prefixo))
}

# Mapa de fluxos: polylines origem → destino (espessura ∝ internações) para os n_max maiores
# fluxos intermunicipais e círculos nos polos (raio ∝ recebidas de fora).
# fluxos: tibble com cod_origem, cod_destino, internacoes; polos: tibble cod_mun6, recebidas_de_fora.
mapa_fluxos <- function(fluxos, polos = NULL, n_max = 60, altura = 520, prefixo = "../municipios/") {
  if (nrow(GEO) == 0 || nrow(CENT) == 0) return(sem_mapa())
  f <- fluxos |> filter(cod_origem != cod_destino, is.finite(internacoes), internacoes > 0) |>
    group_by(cod_origem, cod_destino) |> summarise(internacoes = sum(internacoes), .groups = "drop") |>
    arrange(desc(internacoes)) |> slice_head(n = n_max) |>
    left_join(rename(CENT, lon_o = lon, lat_o = lat), by = c("cod_origem" = "cod_mun6")) |>
    left_join(rename(CENT, lon_d = lon, lat_d = lat), by = c("cod_destino" = "cod_mun6")) |>
    filter(is.finite(lon_o), is.finite(lon_d))
  bb <- bbox_num(GEO)
  m <- mapa_vazio(altura) |>
    addPolygons(data = GEO, layerId = ~slug, fillColor = COR[["claro"]], fillOpacity = 1, color = "#ffffff", weight = 0.8,
                label = ~paste0(municipio, " — clique para abrir o perfil")) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4])
  if (nrow(f)) {
    vmax <- max(f$internacoes)
    for (i in seq_len(nrow(f))) {
      m <- addPolylines(m, lng = c(f$lon_o[i], f$lon_d[i]), lat = c(f$lat_o[i], f$lat_d[i]),
                        weight = 1 + 7 * sqrt(f$internacoes[i] / vmax), color = COR[["sec"]], opacity = 0.55,
                        label = sprintf("%s → %s: %s internações", nome_mun(f$cod_origem[i]), nome_mun(f$cod_destino[i]), num(f$internacoes[i])))
    }
  }
  if (!is.null(polos) && nrow(polos)) {
    pz <- polos |> filter(is.finite(recebidas_de_fora), recebidas_de_fora > 0) |> left_join(CENT, by = "cod_mun6") |> filter(is.finite(lon))
    if (nrow(pz)) { rmax <- max(pz$recebidas_de_fora)
      m <- addCircleMarkers(m, data = pz, lng = ~lon, lat = ~lat, radius = ~4 + 18 * sqrt(recebidas_de_fora / rmax),
                            color = COR[["mun"]], weight = 1, fillColor = COR[["mun"]], fillOpacity = 0.55,
                            label = ~sprintf("%s: %s internações recebidas de outros municípios", nome_mun(cod_mun6), num(recebidas_de_fora))) }
  }
  htmlwidgets::onRender(m, js_clique(prefixo))
}

# ---- 7. Tabelas reactable ---------------------------------------------------------------
# Ranking dos 142 municípios em um indicador (posição, município com link, região, valor)
ranking_indicador <- function(id, ano = NULL, prefixo = "../municipios/", tamanho = 20) {
  r <- info_ind(id); if (is.null(ano)) ano <- ano_ult(id)
  if (is.na(ano)) return(p(class = "nota-fonte", "Sem dados para este indicador."))
  u <- valores_ano(id, ano) |> left_join(select(MUN, cod_mun6, municipio, regiao_saude, slug), by = "cod_mun6") |>
    arrange(desc(valor), municipio) |>
    # posição por competição (empatados recebem a mesma posição), igual a posicao() usada nos perfis
    mutate(pos = ifelse(is.na(valor), NA_integer_, dplyr::min_rank(dplyr::desc(valor))))
  d <- transmute(u, Posição = pos, Município = municipio, slug, `Região de saúde` = regiao_saude, Valor = valor)
  reactable(d, searchable = TRUE, compact = TRUE, striped = TRUE, defaultPageSize = tamanho,
            showPageSizeOptions = TRUE, pageSizeOptions = c(20, 50, 142),
            columns = list(slug = colDef(show = FALSE),
              Posição = colDef(align = "center", minWidth = 70, cell = function(v) ordinal(v)),
              Município = colDef(minWidth = 170, cell = function(v, i) a(href = paste0(prefixo, d$slug[i], ".html"), v)),
              `Região de saúde` = colDef(minWidth = 150),
              Valor = colDef(name = paste0(r$rotulo, " (", ano, ")"), align = "right", cell = function(v) fmt_valor(v, r$fmt))))
}

# Tabela do perfil municipal para um grupo: rótulo, valor no último ano, posição entre 142 e
# na região, medianas, minissérie e situação ▲/▼ pelo sentido; detalhe = série comparada.
tabela_grupo <- function(grupo, cod, prefixo_ind = "../indicadores/") {
  ids <- IND$id[!is.na(IND$grupo) & IND$grupo == grupo]
  if (length(ids) == 0) return(p(class = "nota-fonte", "Nenhum indicador deste grupo no catálogo."))
  linhas <- lapply(ids, function(id) {
    r <- info_ind(id); s <- resumo_ind(id, cod); sit <- situacao(s$valor, s$med_mt, r$sentido)
    ser <- serie_mun(id, cod)
    # ressalva visível ao clicar/tocar (<details>), acessível por teclado — não depende de hover
    nota <- if (!is.na(r$nota) && nzchar(r$nota)) sprintf(' <details class="nota-det"><summary aria-label="Ressalva do indicador">ⓘ ressalva</summary>%s</details>', esc(r$nota)) else ""
    tibble::tibble(
      id = id,
      Indicador = sprintf('<a href="%s">%s</a>%s<div class="sub">%s</div>', url_ind(id, prefixo_ind), esc(r$rotulo), nota, esc(r$unidade)),
      Valor = sprintf('<b>%s</b><div class="sub">%s</div>', fmt_valor(s$valor, r$fmt), ifelse(is.na(s$ano), "", s$ano)),
      Posicao = sprintf('%s<div class="sub">%s</div>', svg_posicao(s$vals, cod, s$med_mt, r$fmt),
                        ifelse(is.na(s$pos_mt), "", sprintf("%s de %d em MT · %s de %d na região", ordinal(s$pos_mt), s$n_mt, ordinal(s$pos_reg), s$n_reg))),
      Serie = svg_sparkline(ser$ano, ser$valor),
      MT = sprintf('<span class="sit %s">%s</span><div class="sub">mediana %s</div>', sit$cls, sit$txt, fmt_valor(s$med_mt, r$fmt)),
      Regiao = fmt_valor(s$med_reg, r$fmt),
      nota_txt = ifelse(is.na(r$nota), "", r$nota))
  })
  d <- bind_rows(linhas)
  reactable(d, compact = TRUE, highlight = TRUE, sortable = FALSE, pagination = FALSE, wrap = TRUE, class = "tabela-grupo",
            columns = list(
              id = colDef(show = FALSE), nota_txt = colDef(show = FALSE),
              Indicador = colDef(html = TRUE, minWidth = 200),
              Valor = colDef(html = TRUE, align = "right", minWidth = 90),
              Posicao = colDef(name = "Posição (maior → menor)", html = TRUE, align = "center", minWidth = 160),
              Serie = colDef(name = "2020–2025", html = TRUE, align = "center", minWidth = 120),
              MT = colDef(name = "Frente à mediana MT", html = TRUE, align = "center", minWidth = 120),
              Regiao = colDef(name = "Mediana da região", align = "right", minWidth = 90)),
            details = function(i) {
              g <- serie_comparada(d$id[i], cod)
              div(class = "detalhe-ind",
                  if (nzchar(g)) HTML(g) else p(class = "sub", "Indicador sem série suficiente para o gráfico."),
                  if (nzchar(d$nota_txt[i])) p(class = "nota-fonte", strong("Nota: "), d$nota_txt[i]),
                  p(class = "nota-fonte", a(href = url_ind(d$id[i], prefixo_ind), "Ver este indicador para todos os municípios →")))
            })
}

# Tabela por região de saúde para um indicador (agregado da região e mediana dos municípios)
tabela_regioes_indicador <- function(id, ano = NULL) {
  r <- info_ind(id); if (is.null(ano)) ano <- ano_ult(id)
  if (is.na(ano) || nrow(REG) == 0) return(p(class = "nota-fonte", "Sem dados por região."))
  v <- valores_ano(id, ano) |> left_join(select(MUN, cod_mun6, co_regsaud), by = "cod_mun6")
  d <- REG |> select(co_regsaud, `Região de saúde` = regiao_saude, Macrorregião = macrorregiao, Municípios = n_municipios) |>
    left_join(SERR[SERR$indicador == id & SERR$ano == ano, c("co_regsaud", "valor")], by = "co_regsaud") |>
    left_join(v |> group_by(co_regsaud) |> summarise(med = median(valor, na.rm = TRUE), .groups = "drop"), by = "co_regsaud") |>
    arrange(desc(valor)) |> select(-co_regsaud) |> rename(`Valor da região` = valor, `Mediana dos municípios` = med)
  reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE,
            columns = list(`Região de saúde` = colDef(minWidth = 170), Municípios = colDef(align = "center", minWidth = 80),
                           `Valor da região` = colDef(align = "right", cell = function(x) fmt_valor(x, r$fmt)),
                           `Mediana dos municípios` = colDef(align = "right", cell = function(x) fmt_valor(x, r$fmt))))
}

# Lista dos 142 municípios com região, população, despesa/hab, médicos/mil, % internações fora e link
tabela_municipios <- function(prefixo = "", ano = ANO_REF) {
  if (nrow(MUN) == 0) return(p(class = "nota-fonte", "Lista de municípios ainda não carregada."))
  col <- function(id) sapply(MUN$cod_mun6, function(m) valor_ind(id, m, ano))
  d <- tibble::tibble(Município = MUN$municipio, slug = MUN$slug, `Região de saúde` = MUN$regiao_saude,
                      População = MUN$populacao_2025, `Despesa/hab.` = col("desp_total_pc"),
                      `Médicos/mil` = col("fte_medicos_p1000"), `% intern. fora` = col("pct_internacoes_fora_mun"))
  reactable(d, searchable = TRUE, compact = TRUE, striped = TRUE, highlight = TRUE, defaultPageSize = 20,
            showPageSizeOptions = TRUE, pageSizeOptions = c(20, 50, 142),
            columns = list(slug = colDef(show = FALSE),
              Município = colDef(minWidth = 170, sticky = "left", cell = function(v, i) a(href = paste0(prefixo, d$slug[i], ".html"), v)),
              `Região de saúde` = colDef(minWidth = 150),
              População = colDef(name = "População 2025", align = "right", cell = function(v) fmt_valor(v, "int")),
              `Despesa/hab.` = colDef(name = paste0("Despesa em saúde/hab. (", ano, ")"), align = "right", cell = function(v) fmt_valor(v, "brl")),
              `Médicos/mil` = colDef(name = paste0("Médicos SUS/mil hab. (", ano, ")"), align = "right", cell = function(v) fmt_valor(v, "dec2")),
              `% intern. fora` = colDef(name = paste0("% internações fora do município (", ano, ")"), align = "right", cell = function(v) fmt_valor(v, "pct1"))))
}

# Hospitais SUS (hospitais.csv) de um município (ou todos) em um ano
tabela_hospitais <- function(cod = NULL, ano = ANO_REF) {
  h <- HOSP[HOSP$ano == ano, ]; if (!is.null(cod)) h <- h[h$cod_mun6 == cod, ]
  if (nrow(h) == 0) return(p(class = "nota-fonte", if (is.null(cod)) "Sem hospitais carregados." else
    sprintf("Nenhum hospital SUS registrado no CNES para este município em %d.", ano)))
  d <- h |> arrange(desc(internacoes)) |>
    transmute(Estabelecimento = nome_fantasia, CNES = cnes, Município = municipio, Esfera = esfera,
              `Leitos SUS` = leitos_sus, `Leitos UTI SUS` = leitos_uti_sus, `Médicos (FTE)` = fte_medicos_sus,
              Internações = internacoes, `Alta compl.` = internacoes_ac, `Mortalidade (%)` = taxa_mortalidade_hosp,
              `Permanência (dias)` = permanencia_media, `Ocupação (%)` = taxa_ocupacao_leitos_sus)
  if (!is.null(cod)) d$Município <- NULL
  reactable(d, compact = TRUE, striped = TRUE, searchable = is.null(cod), defaultPageSize = if (is.null(cod)) 20 else 50,
            pagination = is.null(cod),
            columns = list(Estabelecimento = colDef(minWidth = 220), CNES = colDef(minWidth = 80),
              `Leitos SUS` = colDef(align = "right", cell = function(v) fmt_valor(v, "int")),
              `Leitos UTI SUS` = colDef(align = "right", cell = function(v) fmt_valor(v, "int")),
              `Médicos (FTE)` = colDef(align = "right", cell = function(v) fmt_valor(v, "dec1")),
              Internações = colDef(align = "right", cell = function(v) fmt_valor(v, "int")),
              `Alta compl.` = colDef(align = "right", cell = function(v) fmt_valor(v, "int")),
              `Mortalidade (%)` = colDef(align = "right", cell = function(v) fmt_valor(v, "dec1")),
              `Permanência (dias)` = colDef(align = "right", cell = function(v) fmt_valor(v, "dec1")),
              `Ocupação (%)` = colDef(align = "right", cell = function(v) fmt_valor(100 * v, "dec1"))))  # hospitais.csv traz fração 0–1
}

# ---- 8. Deslocamento ----------------------------------------------------------------------
# Linha de deslocamento_mun_ano para um município (último ano disponível se ano = NULL)
desl_mun <- function(cod, ano = NULL) {
  d <- DESL[DESL$cod_mun6 == cod, ]
  if (nrow(d) == 0) return(NULL)
  if (is.null(ano)) ano <- max(d$ano)
  d <- d[d$ano == ano, ]; if (nrow(d) == 0) NULL else d[1, ]
}

# Principais destinos dos moradores (fluxo_mun_ano) com nome, internações e % do total
top_destinos <- function(cod, ano, n = 5, nivel = NULL) {
  f <- FLUXO[FLUXO$cod_origem == cod & FLUXO$ano == ano, ]
  if (!is.null(nivel)) f <- f[f$nivel %in% nivel, ]
  if (nrow(f) == 0) return(f[, c("cod_destino", "internacoes")] |> mutate(destino = character(0), pct = numeric(0)))
  f |> group_by(cod_destino) |> summarise(internacoes = sum(internacoes, na.rm = TRUE), .groups = "drop") |>
    mutate(destino = nome_mun(cod_destino), pct = 100 * internacoes / sum(internacoes)) |>
    arrange(desc(internacoes)) |> slice_head(n = n)
}

# Principais origens dos pacientes atendidos (de fora do município)
top_origens <- function(cod, ano, n = 5, nivel = NULL) {
  f <- FLUXO[FLUXO$cod_destino == cod & FLUXO$ano == ano & FLUXO$cod_origem != cod, ]
  if (!is.null(nivel)) f <- f[f$nivel %in% nivel, ]
  if (nrow(f) == 0) return(f[, c("cod_origem", "internacoes")] |> mutate(origem = character(0), pct = numeric(0)))
  f |> group_by(cod_origem) |> summarise(internacoes = sum(internacoes, na.rm = TRUE), .groups = "drop") |>
    mutate(origem = nome_mun(cod_origem), pct = 100 * internacoes / sum(internacoes)) |>
    arrange(desc(internacoes)) |> slice_head(n = n)
}

# Resumo estadual do deslocamento (resumo_deslocamento_ano) para um ano e nível (total | MC | AC)
resumo_desl <- function(ano, nivel = "total") {
  d <- RESDESL[RESDESL$ano == ano & tolower(RESDESL$nivel) == tolower(nivel), ]
  if (nrow(d) == 0) NULL else d[1, ]
}

# ---- 9. Rodapé de fontes -----------------------------------------------------------------------
# prefixo: caminho relativo até a raiz do site ("" na raiz, "../" nas subpastas)
fonte_rodape <- function(prefixo = "../", extra = NULL) {
  p(class = "nota-fonte",
    "Fontes: DATASUS/Ministério da Saúde (CNES, SIA, SIH, SISAB, SI-PNI, SIM, SINASC), SIOPS e IBGE, tratados pelo ",
    "Projeto PPSUS-MT (Data Lake do SUS-MT). Despesas em R$ correntes (liquidadas); produção hospitalar pelo ano da alta; ",
    "medianas calculadas entre os municípios de Mato Grosso no ano indicado. ", extra,
    "Definições, ressalvas e anomalias conhecidas em ", a(href = paste0(prefixo, "metodologia.html"), "Metodologia", .noWS = "after"),
    "; arquivos completos em ", a(href = paste0(prefixo, "dados/index.html"), "Dados", .noWS = "after"), ".")
}
