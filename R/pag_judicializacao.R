# =============================================================================
# Observatório PPSUS-MT — funções da aba judicializacao/index.qmd
#
# Carregar DEPOIS de R/funcoes.R (que não deve ser editado). Lê dados_site/judicializacao/,
# gravado por scripts/10_preparar_judicializacao.py: cópias conferidas dos arquivos agregados da
# frente J do projeto (DataJud/CNJ, TJMT e TRF1; coleta de 17/10/2026, versão
# judicializacao_2026-10-17_rev1), com supressão primária (contagens de 1 a 4) e supressão
# complementar auditada na origem.
#
# Regras desta página: nunca recalcular nem mostrar valor suprimido (célula vazia → "suprimido");
# taxa suavizada por comarca só no período 2022–2024 (arredondada a 5) e, por ano, só em faixas;
# 2026 = ajuizamentos até 11/09/2026; 2025–2026 afetados pela centralização no Núcleo 4.0;
# Cuiabá e Várzea Grande = limite inferior; fatores associados = associação, não causa.
#
# Índice
#   1. Leitura e constantes
#   2. Formatação e textos auxiliares
#   3. SVG: linhas (com ano parcial e banda), barras de atribuição, razões de taxas
#   4. Panorama: cartões, séries anual e mensal, tabela anual
#   5. Comarcas: mapa, ranking, municípios (herança), faixas por ano
#   6. Previsão (J3): gráfico por grupo, quadro e métricas
#   7. Fatores associados (J2)
# =============================================================================

# ---- 1. Leitura e constantes ------------------------------------------------------------
JUD_DIR <- ds("judicializacao")
ler_jud <- function(f) {
  p <- file.path(JUD_DIR, f)
  if (!file.exists(p)) {
    aviso("arquivo ausente: dados_site/judicializacao/%s (rode scripts/10_preparar_judicializacao.py)", f)
    return(tibble::tibble())
  }
  tibble::as_tibble(data.table::fread(p, encoding = "UTF-8", na.strings = ""))
}
lg <- function(x) toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1")

JUD_ANO  <- ler_jud("judicializacao_mt_ano.csv")
JUD_MES  <- ler_jud("judicializacao_mt_mes_grupo.csv")
JUD_PER  <- ler_jud("judicializacao_comarca_2022_2024.csv")
JUD_CA   <- ler_jud("judicializacao_comarca_ano.csv")
JUD_MUN  <- ler_jud("judicializacao_municipio_ano.csv")
JUD_PREV <- ler_jud("judicializacao_previsao_trimestre.csv")
JUD_MET  <- ler_jud("judicializacao_previsao_metricas.csv")
JUD_J2   <- ler_jud("judicializacao_fatores_associados.csv")
JUD_AUD  <- ler_jud("auditoria_supressao.csv")
JUD_CM   <- ler_jud("comarca_municipio.csv")
# Revisão 2 (18/10/2026): números do texto que antes vinham só do relatório técnico, agora em arquivos auditados
JUD_WALD <- ler_jud("judicializacao_testes_bloco.csv")
JUD_IND  <- ler_jud("judicializacao_indicadores_complementares.csv")
# Teste conjunto (Wald) do bloco de oferta: linha de um dependente e especificação
wald <- function(dep, esp = "completo") { x <- JUD_WALD[JUD_WALD$dependente == dep & JUD_WALD$especificacao == esp, ]; if (nrow(x)) x[1, ] else NULL }
# Indicador complementar (valor numérico)
ind_j <- function(indicador, recorte = NULL) {
  x <- JUD_IND[JUD_IND$indicador == indicador & (if (is.null(recorte)) TRUE else JUD_IND$recorte == recorte), ]
  as.numeric(x$valor)
}
for (cn in c("ano_parcial", "suprimido")) if (cn %in% names(JUD_ANO)) JUD_ANO[[cn]] <- lg(JUD_ANO[[cn]])
for (cn in c("mes_incompleto", "suprimido")) if (cn %in% names(JUD_MES)) JUD_MES[[cn]] <- lg(JUD_MES[[cn]])
for (cn in c("limite_inferior", "suprimido")) if (cn %in% names(JUD_PER)) JUD_PER[[cn]] <- lg(JUD_PER[[cn]])
for (cn in c("ano_parcial", "limite_inferior", "quebra_centralizacao", "suprimido")) if (cn %in% names(JUD_CA)) JUD_CA[[cn]] <- lg(JUD_CA[[cn]])
for (cn in c("ano_parcial", "taxa_limite_inferior", "quebra_centralizacao")) if (cn %in% names(JUD_MUN)) JUD_MUN[[cn]] <- lg(JUD_MUN[[cn]])
if ("sede_comarca" %in% names(JUD_CM)) JUD_CM$sede_comarca <- lg(JUD_CM$sede_comarca)

JUD_FONTE   <- "DataJud/CNJ (API pública), TJMT e TRF1"
JUD_COLETA  <- "17/10/2026"
JUD_ATE     <- "até 11/09/2026"
JUD_ANOS    <- 2020:2026
ANO_COMPL   <- 2025L          # último ano completo
URL_DATAJUD <- "https://datajud-wiki.cnj.jus.br/api-publica/acesso"
TXT_SUPR_J  <- "suprimido"
LIMITE_INF  <- c("Cuiabá", "Várzea Grande")

FAIXAS_JUD <- c("0 a 50", "50 a 100", "100 a 150", "150 a 200", "200 a 300", "300 ou mais")
COR_FAIXA  <- setNames(PAL_SEQ(6), FAIXAS_JUD)
TXT_FAIXA  <- setNames(c("#1f2937", "#1f2937", "#1f2937", "#ffffff", "#ffffff", "#ffffff"), FAIXAS_JUD)
COR_LIM    <- "#b45309"      # contorno de Cuiabá e Várzea Grande (limite inferior), sempre com traço e texto

# Grupos de assunto (série anual: saúde pública por assunto principal)
GRUPOS_ANO <- c(pub_tratamento = "Tratamento médico-hospitalar", pub_internacao_uti = "Internação, leito e UTI",
                pub_medicamentos = "Medicamentos", pub_insumos = "Insumos",
                pub_home_care = "Tratamento domiciliar (home care)", pub_saude_mental = "Saúde mental")
COR_GRUPO_ANO <- c(pub_tratamento = "#0E5A5E", pub_internacao_uti = "#2E86AB", pub_medicamentos = "#b45309",
                   pub_insumos = "#be185d", pub_home_care = "#6d28d9", pub_saude_mental = "#4b5563")
DASH_GRUPO_ANO <- c(pub_tratamento = "", pub_internacao_uti = "", pub_medicamentos = "",
                    pub_insumos = "", pub_home_care = "6,4", pub_saude_mental = "2,3")
# Grupos da série mensal e da previsão
GRUPOS_MES <- c(tratamento = "Tratamento médico-hospitalar", internacao_uti = "Internação, leito e UTI",
                medicamentos = "Medicamentos", outros_publica = "Outros da saúde pública",
                suplementar = "Saúde suplementar (planos de saúde)")
COR_GRUPO_MES <- c(tratamento = "#0E5A5E", internacao_uti = "#2E86AB", medicamentos = "#b45309",
                   outros_publica = "#6d28d9", suplementar = "#6b7280", total = "#0E5A5E")
DASH_GRUPO_MES <- c(tratamento = "", internacao_uti = "", medicamentos = "", outros_publica = "6,4", suplementar = "2,3")
GRUPOS_PREV <- c(total = "Total", GRUPOS_MES)
MODELOS <- c(ets = "ETS (Holt-Winters amortecido)", lightgbm = "LightGBM", sarima = "SARIMA",
             persistencia = "Persistência (repete o último mês)", ingenuo_sazonal = "Ingênuo sazonal (repete o mesmo mês do ano anterior)")
MODELOS_CURTO <- c(ets = "ETS", lightgbm = "LightGBM", sarima = "SARIMA", persistencia = "Persistência", ingenuo_sazonal = "Ingênuo sazonal")
MESES_PT <- c("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez")

# Variáveis do J2 (fatores associados)
J2_VAR <- c(inef_m1 = "Ineficiência DEA — atenção básica (M1)", inef_m0 = "Ineficiência DEA — global (M0)",
            cobertura_esf = "Cobertura potencial da ESF", leitos_sus_p1000 = "Leitos SUS por mil hab.",
            medicos_sus_p1000 = "Médicos SUS (FTE) por mil hab.", fuga_pct = "Internações de residentes fora do município",
            dist_polo_km = "Distância ao polo regional de saúde",
            log_litig_geral = "Litigiosidade geral (log)", unidades_p100mil = "Unidades judiciárias por 100 mil hab.",
            pct_pop_fora_sede = "População fora do município-sede da comarca", tempo_sede_min = "Tempo rodoviário até a sede da comarca",
            entr_final = "Comarca de entrância final", entr_intermediaria = "Comarca de entrância intermediária",
            log_pib_pc = "PIB per capita (log)", renda_pc_2022 = "Renda per capita (Censo 2022)", log_pop = "População (log)",
            tempo_cuiaba_min = "Tempo rodoviário até Cuiabá")
J2_UNID <- c(inef_m1 = "%s pontos de ineficiência (0–1)", inef_m0 = "%s pontos de ineficiência (0–1)",
             cobertura_esf = "%s p.p.", leitos_sus_p1000 = "%s leito SUS por mil hab.", medicos_sus_p1000 = "%s médico SUS por mil hab.",
             fuga_pct = "%s p.p.", dist_polo_km = "%s km", log_litig_geral = "%s no log", unidades_p100mil = "%s unidades por 100 mil",
             pct_pop_fora_sede = "%s p.p.", tempo_sede_min = "%s min", log_pib_pc = "%s no log", renda_pc_2022 = "R$ %s",
             log_pop = "%s no log", tempo_cuiaba_min = "%s min")
J2_BLOCO <- c(inef_m1 = "oferta", inef_m0 = "oferta", cobertura_esf = "oferta", leitos_sus_p1000 = "oferta",
              medicos_sus_p1000 = "oferta", fuga_pct = "oferta", dist_polo_km = "oferta",
              log_litig_geral = "acesso", unidades_p100mil = "acesso", pct_pop_fora_sede = "acesso", tempo_sede_min = "acesso",
              entr_final = "acesso", entr_intermediaria = "acesso",
              log_pib_pc = "contexto", renda_pc_2022 = "contexto", log_pop = "contexto", tempo_cuiaba_min = "contexto")
J2_BLOCOS <- c(oferta = "Oferta e eficiência do SUS (hipótese testada)", acesso = "Acesso à justiça (controle)",
               contexto = "Contexto socioeconômico e geográfico (controle)")
COR_BLOCO <- c(oferta = "#0E5A5E", acesso = "#2E86AB", contexto = "#6b7280")
J2_BLOCO_CURTO <- c(oferta = "Oferta e eficiência (testado)", acesso = "Acesso à justiça", contexto = "Contexto")
J2_DEP <- c(acoes_publica = "Saúde pública", acoes_suplementar = "Saúde suplementar (placebo)", acoes_saude = "Total de ações de saúde",
            acoes_medicamentos = "Medicamentos (saúde pública)", acoes_tratamento = "Tratamento (saúde pública)",
            acoes_internacao_uti = "Internação e UTI (saúde pública)")

# ---- 2. Formatação e textos ------------------------------------------------------------------
pct_j   <- function(x, d = 1) ifelse(is.na(x), "—", paste0(num(x, d), "%"))
supr_j  <- function(v, f = num) ifelse(is.na(v), TXT_SUPR_J, f(v))
rot_ano <- function(a) ifelse(a == 2026, "2026 (até 11/09)", as.character(a))
dec2    <- function(x) num(x, 2)
p_txt   <- function(p) ifelse(is.na(p), "—", ifelse(p < 0.001, "< 0,001", num(p, 3)))
# Termo técnico com explicação ao passar o cursor (texto corrido; HTML)
sigla_j <- function(s, titulo) as.character(tags$abbr(title = titulo, tabindex = "0", s))
lista_e_j <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
mes_rot <- function(ano, mes) paste0(MESES_PT[mes], "/", ano)
sem_mt  <- function(x) sub(" - MT$", "", x)
vezes   <- function(a, b) paste0(num(a / b, 1), " vezes")
por_extenso <- function(n) { e <- c("um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez"); ifelse(n >= 1 & n <= 10, e[pmax(1, pmin(n, 10))], as.character(n)) }
eixo_j  <- function(v) num(v, if (all(abs(v - round(v)) < 1e-9)) 0 else 1)   # 12.000 (não "12 mil"; nunca "0 mil")

# Linha de um ano do panorama estadual
jud_ano <- function(a) { r <- JUD_ANO[JUD_ANO$ano == a, ]; if (nrow(r)) r[1, ] else NULL }

# Taxa estadual de ações atribuíveis por 100 mil hab./ano (soma das comarcas = estado) — anos completos
taxa_estado <- function(anos) {
  pop <- sum(JUD_CA$populacao[JUD_CA$ano %in% anos])
  at  <- sum(JUD_ANO$atribuivel[JUD_ANO$ano %in% anos])
  if (pop > 0) 1e5 * at / pop else NA_real_
}

# Chip colorido de uma faixa de taxa (cor + texto; nunca só a cor)
chip_faixa <- function(f, extra = "") {
  ifelse(is.na(f) | !nzchar(f), sprintf('<span class="chip-supr">%s</span>', TXT_SUPR_J),
         sprintf('<span class="chip-faixa" style="background:%s;color:%s">%s</span>%s',
                 COR_FAIXA[f], TXT_FAIXA[f], f, extra))
}

# ---- 3. SVG ------------------------------------------------------------------------------------
# Linhas multi-série com eixo x numérico e rótulos livres; x_parcial: pontos desenhados vazados e
# não ligados à linha (ano parcial); bandas: list(x, lo, hi, cor, tip) (intervalo de previsão).
svg_linhas_jud <- function(series, titulo, xt, xl, tip_x, w = 680, h = 270, x_parcial = numeric(0), bandas = list(),
                           fmt = "int", leg_extra = NULL, r_pt = 2.6) {
  ys <- c(unlist(lapply(series, `[[`, "y")), unlist(lapply(bandas, `[[`, "hi")))
  ys <- ys[is.finite(ys)]
  if (length(ys) < 2) return("")
  xs <- c(unlist(lapply(series, `[[`, "x")), unlist(lapply(bandas, `[[`, "x")), xt)
  pl <- 50; pr <- 16; pt <- 12; pb <- 28
  xr <- range(xs); if (diff(xr) == 0) xr <- xr + c(-1, 1)
  yt <- pretty(c(0, max(ys)), n = 5); yr <- range(yt)
  sx <- function(x) pl + (x - xr[1]) / diff(xr) * (w - pl - pr)
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, eixo_j(yt)), collapse = "")
  eixo_x <- paste(sprintf('<text x="%.1f" y="%d" text-anchor="middle" font-size="12" fill="#6b7280">%s</text>', sx(xt), h - 9, esc(xl)), collapse = "")
  band <- paste(vapply(bandas, function(b) {
    pts <- c(sprintf("%.1f,%.1f", sx(b$x), sy(b$hi)), rev(sprintf("%.1f,%.1f", sx(b$x), sy(b$lo))))
    sprintf('<polygon points="%s" fill="%s" fill-opacity="0.16" stroke="%s" stroke-opacity="0.35" stroke-dasharray="2,2" data-tip="%s"/>',
            paste(pts, collapse = " "), b$cor, b$cor, esc(b$tip))
  }, character(1)), collapse = "")
  linhas <- vapply(series, function(s) {
    o <- order(s$x); x <- s$x[o]; y <- s$y[o]
    parc <- x %in% x_parcial
    ok <- is.finite(y) & !parc
    dash <- if (!is.null(s$dash) && nzchar(s$dash)) sprintf(' stroke-dasharray="%s"', s$dash) else ""
    seg <- if (sum(ok)) paste0(ifelse(c(TRUE, !ok[-length(ok)]) & ok, "M", "L")[ok], sprintf("%.1f %.1f", sx(x[ok]), sy(y[ok])), collapse = " ") else ""
    tips <- if (!is.null(s$tips)) s$tips[o] else sprintf("%s · %s: %s", s$nome, tip_x(x), fmt_valor(y, fmt))
    pts <- if (sum(ok)) paste(sprintf('<circle cx="%.1f" cy="%.1f" r="%s" fill="%s" stroke="transparent" stroke-width="8" data-tip="%s"/>',
                                      sx(x[ok]), sy(y[ok]), r_pt, s$cor, esc(tips[ok])), collapse = "") else ""
    pp <- is.finite(y) & parc
    ptp <- if (any(pp)) paste(sprintf('<circle cx="%.1f" cy="%.1f" r="4.2" fill="#ffffff" stroke="%s" stroke-width="2" data-tip="%s"/>',
                                      sx(x[pp]), sy(y[pp]), s$cor, esc(tips[pp])), collapse = "") else ""
    sprintf('<g><path d="%s" fill="none" stroke="%s" stroke-width="%s"%s/>%s%s</g>', seg, s$cor, s$larg, dash, pts, ptp)
  }, character(1))
  leg <- paste(vapply(series, function(s) {
    dash <- if (!is.null(s$dash) && nzchar(s$dash)) sprintf(' stroke-dasharray="%s"', s$dash) else ""
    sprintf('<span class="leg-item"><svg width="24" height="8" aria-hidden="true"><line x1="0" x2="24" y1="4" y2="4" stroke="%s" stroke-width="%s"%s/></svg>%s</span>',
            s$cor, s$larg, dash, esc(s$nome)) }, character(1)), collapse = "")
  if (!is.null(leg_extra)) leg <- paste0(leg, leg_extra)
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(titulo), esc(titulo), grade, eixo_x, band, paste(linhas, collapse = ""), leg)
}
LEG_PARCIAL <- '<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><circle cx="7" cy="7" r="4.2" fill="#fff" stroke="#374151" stroke-width="2"/></svg>2026: ajuizamentos até 11/09 (ano incompleto, não comparável)</span>'

# Barras empilhadas por ano: ações atribuíveis a uma comarca × sem origem identificável
svg_atribuicao <- function(w = 680, h = 290) {
  d <- JUD_ANO |> arrange(ano)
  if (nrow(d) == 0) return("")
  pl <- 50; pr <- 12; pt <- 26; pb <- 30
  yt <- pretty(c(0, max(d$acoes_saude)), n = 5); yr <- range(yt)
  n <- nrow(d); bw <- (w - pl - pr) / n
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  grade <- paste(sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#eef0f4"/><text x="%d" y="%.1f" text-anchor="end" font-size="12" fill="#6b7280">%s</text>',
                         pl, w - pr, sy(yt), sy(yt), pl - 6, sy(yt) + 4, eixo_j(yt)), collapse = "")
  x0 <- pl + (seq_len(n) - 1) * bw + bw * 0.18; bl <- bw * 0.64
  sem <- d$acoes_saude - d$atribuivel
  barras <- paste(sprintf(paste0(
    '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" data-tip="%s: %s ações atribuíveis a uma comarca (%s)"/>',
    '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#cbd5e1" data-tip="%s: %s ações sem comarca de origem identificável"/>',
    '<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11.5" font-weight="600" fill="#0E5A5E">%s</text>',
    '<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="#6b7280">%s</text>'),
    x0, sy(d$atribuivel), bl, sy(0) - sy(d$atribuivel), ifelse(d$ano == 2026, "#5f9a9b", COR[["mun"]]),
    rot_ano(d$ano), num(d$atribuivel), pct_j(d$pct_atribuivel),
    x0, sy(d$acoes_saude), bl, sy(d$atribuivel) - sy(d$acoes_saude), rot_ano(d$ano), num(sem),
    x0 + bl / 2, sy(d$acoes_saude) - 6, pct_j(d$pct_atribuivel, 0),
    x0 + bl / 2, h - 10, ifelse(d$ano == 2026, "2026*", as.character(d$ano))), collapse = "")
  leg <- paste0('<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="', COR[["mun"]], '"/></svg>Atribuíveis a uma comarca (código de origem do processo)</span>',
                '<span class="leg-item"><svg width="14" height="14" aria-hidden="true"><rect width="14" height="14" fill="#cbd5e1"/></svg>Sem comarca de origem identificável (unidades centralizadas)</span>',
                '<span class="leg-item">Número sobre a barra: % atribuível · * 2026: ajuizamentos até 11/09</span>')
  tit <- "Ações de saúde no 1º grau do TJMT por ano: atribuíveis a uma comarca e sem origem identificável, 2020–2026"
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="%s"><title>%s</title>%s%s</svg><figcaption class="legenda-svg">%s</figcaption></figure>',
          w, h, esc(tit), esc(tit), grade, barras, leg)
}

# Razões de taxas (IRR) com IC 95%, escala logarítmica, uma linha por variável, agrupadas por bloco
svg_irr <- function(dep, w = 420, lh = 40) {
  d <- JUD_J2[JUD_J2$dependente == dep & !JUD_J2$variavel %in% c("entr_final", "entr_intermediaria"), ]
  if (nrow(d) == 0) return("")
  d$bloco <- J2_BLOCO[d$variavel]
  d <- d[order(match(d$bloco, names(J2_BLOCOS)), match(d$variavel, names(J2_VAR))), ]
  pl <- 12; pr <- 16; pt <- 6
  lim <- log(range(c(d$irr_li, d$irr_ls, 0.7, 1.4))) + c(-0.04, 0.04)
  sx <- function(v) pl + (log(v) - lim[1]) / diff(lim) * (w - pl - pr)
  # rótulo acima de cada intervalo (cabe na largura do celular); halo branco sobre a grade
  halo <- 'stroke="#ffffff" stroke-width="3" paint-order="stroke"'
  linhas <- character(0); y <- pt
  for (b in names(J2_BLOCOS)) {
    db <- d[d$bloco == b, ]; if (nrow(db) == 0) next
    linhas <- c(linhas, sprintf('<text x="%d" y="%.1f" font-size="13" font-weight="700" fill="%s" %s>%s</text>', pl, y + 16, COR_BLOCO[[b]], halo, esc(J2_BLOCOS[[b]])))
    y <- y + 26
    for (i in seq_len(nrow(db))) {
      r <- db[i, ]
      tip <- sprintf("%s: razão de taxas %s (IC 95%% %s–%s) por 1 desvio-padrão; p bruto %s%s",
                     J2_VAR[[r$variavel]], dec2(r$irr), dec2(r$irr_li), dec2(r$irr_ls), p_txt(r$p),
                     if (!is.na(r$p_holm)) sprintf("; p ajustado: Holm %s, Benjamini-Hochberg %s", p_txt(r$p_holm), p_txt(r$p_bh)) else "")
      cheio <- !is.na(r$p) && r$p < 0.05
      linhas <- c(linhas, sprintf(paste0(
        '<text x="%d" y="%.1f" font-size="12.5" fill="#1f2937" %s>%s <tspan fill="#4b5563">· %s (%s–%s)</tspan></text>',
        '<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2.2"/>',
        '<rect x="%.1f" y="%.1f" width="10" height="10" fill="%s" stroke="%s" stroke-width="2" data-tip="%s"/>'),
        pl + 4, y + 13, halo, esc(J2_VAR[[r$variavel]]), dec2(r$irr), dec2(r$irr_li), dec2(r$irr_ls),
        sx(r$irr_li), sx(r$irr_ls), y + 27, y + 27, COR_BLOCO[[b]],
        sx(r$irr) - 5, y + 22, if (cheio) COR_BLOCO[[b]] else "#ffffff", COR_BLOCO[[b]], esc(tip)))
      y <- y + lh
    }
  }
  h <- y + 34
  ticks <- c(0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.25, 1.5, 1.75, 2)
  ticks <- ticks[log(ticks) >= lim[1] & log(ticks) <= lim[2]]
  grade <- paste(sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%.1f" stroke="%s" %s/><text x="%.1f" y="%.1f" text-anchor="middle" font-size="12" fill="#6b7280">%s</text>',
                         sx(ticks), sx(ticks), pt, y, ifelse(ticks == 1, "#374151", "#e9edf1"), ifelse(ticks == 1, 'stroke-width="1.5"', ""),
                         sx(ticks), y + 15, num(ticks, 2)), collapse = "")
  rot <- sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="11.5" fill="#4b5563">← menos ações</text><text x="%.1f" y="%.1f" font-size="11.5" fill="#4b5563">mais ações →</text>',
                 sx(1) - 6, y + 30, sx(1) + 6, y + 30)
  tit <- sprintf("Razões de taxas por 1 desvio-padrão, com intervalo de confiança de 95%% — %s, 2022–2025, 77 comarcas", J2_DEP[[dep]])
  sprintf('<figure class="grafico-svg"><svg viewBox="0 0 %d %.0f" width="100%%" style="max-width:560px" role="img" aria-label="%s"><title>%s</title>%s%s%s</svg><figcaption class="legenda-svg"><span class="leg-item"><svg width="12" height="12" aria-hidden="true"><rect x="1" y="1" width="9" height="9" fill="#374151"/></svg>p bruto &lt; 0,05</span><span class="leg-item"><svg width="12" height="12" aria-hidden="true"><rect x="1" y="1" width="9" height="9" fill="#fff" stroke="#374151" stroke-width="2"/></svg>p bruto ≥ 0,05</span><span class="leg-item">Linha vertical em 1 = nenhuma associação; ao lado do nome, a razão e o IC 95%%</span><span class="leg-item">p bruto, sem correção para comparações múltiplas; após a correção, nenhum coeficiente do bloco testado fica abaixo de 0,05</span></figcaption></figure>',
          w, h, esc(tit), esc(tit), grade, paste(linhas, collapse = ""), rot)
}

# ---- 4. Panorama ---------------------------------------------------------------------------------
kpis_jud <- function() {
  a <- jud_ano(ANO_COMPL); a0 <- jud_ano(2020L); a22 <- jud_ano(2022L); a26 <- jud_ano(2026L)
  if (is.null(a)) return(p(class = "nota-fonte", "Dados de judicialização indisponíveis."))
  tx <- taxa_estado(2022:2024)
  div(class = "kpi-grade",
    kpi_simples("Ações de saúde ajuizadas no 1º grau do TJMT", num(a$acoes_saude), paste0("processos distintos · ", ANO_COMPL),
                sprintf("%s em 2020 (%s) · %s em 2026 até 11/09", num(a0$acoes_saude), vezes(a$acoes_saude, a0$acoes_saude), num(a26$acoes_saude))),
    kpi_simples("Com assunto de saúde pública", num(a$publica), paste0("ações · ", ANO_COMPL),
                sprintf("%s das ações · %s em 2020", pct_j(100 * a$publica / a$acoes_saude), num(a0$publica))),
    kpi_simples("Com assunto de saúde suplementar (planos)", num(a$suplementar), paste0("ações · ", ANO_COMPL),
                sprintf("%s em 2020 (%s)", num(a0$suplementar), vezes(a$suplementar, a0$suplementar))),
    kpi_simples("Com liminar ou tutela concedida no 1º grau", pct_j(100 * a$liminar_concedida / a$acoes_saude),
                paste0("das ações (concessão total ou parcial) · ", ANO_COMPL),
                sprintf("%s ações · %s em 2020", num(a$liminar_concedida), pct_j(100 * a0$liminar_concedida / a0$acoes_saude))),
    kpi_simples("Atribuíveis a uma comarca", pct_j(a$pct_atribuivel), paste0("das ações · ", ANO_COMPL),
                sprintf("%s em 2022 · %s em 2020 (centralização)", pct_j(a22$pct_atribuivel), pct_j(a0$pct_atribuivel)), href = "#centralizacao"),
    kpi_simples("Ações atribuíveis por 100 mil hab./ano", num(tx, 1), "média do estado · 2022–2024 (período principal)",
                sprintf("%s em %d · limite inferior do total (só ações com comarca identificada)", num(taxa_estado(ANO_COMPL), 1), ANO_COMPL), href = "#comarcas"))
}

# Série anual por esfera: pública e suplementar (2026 vazado)
serie_esferas <- function() {
  d <- JUD_ANO |> arrange(ano)
  s <- list(list(nome = "Total de ações de saúde", cor = "#374151", larg = 2, dash = "2,3", x = d$ano, y = d$acoes_saude),
            list(nome = "Saúde pública", cor = COR[["mun"]], larg = 2.8, dash = "", x = d$ano, y = d$publica),
            list(nome = "Saúde suplementar (planos de saúde)", cor = COR[["sec"]], larg = 2.4, dash = "6,4", x = d$ano, y = d$suplementar))
  HTML(svg_linhas_jud(s, "Ações de saúde no 1º grau do TJMT por esfera, 2020–2026 (2026 até 11/09)", xt = d$ano, xl = ifelse(d$ano == 2026, "2026*", d$ano),
                      tip_x = rot_ano, x_parcial = 2026, leg_extra = LEG_PARCIAL, w = 430, h = 290))
}

# Série anual por grupo de assunto da saúde pública (grupos maiores ou menores)
serie_grupos_ano <- function(grupos, titulo) {
  d <- JUD_ANO |> arrange(ano)
  s <- lapply(grupos, function(g) {
    y <- d[[g]]
    tips <- sprintf("%s · %s: %s", GRUPOS_ANO[[g]], rot_ano(d$ano), supr_j(y))
    list(nome = GRUPOS_ANO[[g]], cor = COR_GRUPO_ANO[[g]], larg = 2.4, dash = DASH_GRUPO_ANO[[g]], x = d$ano, y = y, tips = tips)
  })
  HTML(svg_linhas_jud(s, titulo, xt = d$ano, xl = ifelse(d$ano == 2026, "2026*", d$ano), tip_x = rot_ano, x_parcial = 2026, leg_extra = LEG_PARCIAL, w = 430, h = 290))
}

# Tabela anual (todas as contagens do arquivo estadual, "suprimido" onde vazio)
tabela_anual <- function() {
  d <- JUD_ANO |> arrange(ano) |>
    transmute(Ano = rot_ano(ano), acoes_saude, publica, suplementar, pub_tratamento, pub_internacao_uti, pub_medicamentos,
              pub_insumos, pub_home_care, pub_saude_mental, liminar_concedida, pct_atribuivel)
  nc <- function(nome, f = num, w = 92, ...) colDef(name = nome, align = "right", minWidth = w, cell = function(v) supr_j(v, f), ...)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE,
    columnGroups = list(colGroup(name = "Saúde pública: assunto principal", columns = names(GRUPOS_ANO))),
    columns = list(Ano = colDef(minWidth = 92, sticky = "left", style = list(fontWeight = 600)),
      acoes_saude = nc("Total de ações de saúde", style = list(fontWeight = 600)), publica = nc("Saúde pública"), suplementar = nc("Saúde suplementar"),
      pub_tratamento = nc("Tratamento"), pub_internacao_uti = nc("Internação, leito e UTI"), pub_medicamentos = nc("Medicamentos", w = 112),
      pub_insumos = nc("Insumos"), pub_home_care = nc("Home care"), pub_saude_mental = nc("Saúde mental"),
      liminar_concedida = nc("Com liminar ou tutela concedida"), pct_atribuivel = nc("% atribuível a uma comarca", function(v) pct_j(v)))))
}

# Série mensal por grupo, sem o mês incompleto
serie_mensal <- function() {
  m <- JUD_MES[!JUD_MES$mes_incompleto, ] |> mutate(x = ano + (mes - 1) / 12)
  if (nrow(m) == 0) return("")
  s <- lapply(names(GRUPOS_MES), function(g) {
    d <- m[m$grupo == g, ] |> arrange(x)
    list(nome = GRUPOS_MES[[g]], cor = COR_GRUPO_MES[[g]], larg = 1.8, dash = DASH_GRUPO_MES[[g]], x = d$x, y = d$acoes,
         tips = sprintf("%s · %s: %s", GRUPOS_MES[[g]], mes_rot(d$ano, d$mes), supr_j(d$acoes)))
  })
  ult <- m |> filter(x == max(x)) |> slice(1)
  HTML(svg_linhas_jud(s, sprintf("Ações de saúde ajuizadas no 1º grau do TJMT por mês e grupo de assunto, jan/2020 a %s", mes_rot(ult$ano, ult$mes)),
                      xt = 2020:2026, xl = as.character(2020:2026), tip_x = function(x) x, r_pt = 1.7, h = 290))
}

# ---- 5. Comarcas -------------------------------------------------------------------------------------
# Comarca de cada município (nome) e municípios abrangidos por comarca
muns_da_comarca <- function(com) {
  x <- JUD_CM[JUD_CM$comarca == com, ]
  x$nome_municipio[ordem_nome(x$nome_municipio)]
}

# Mapa das 79 comarcas (malha municipal dissolvida pela comarca), cor = faixa da taxa suavizada 2022–2024
mapa_comarcas <- function(altura = 600) {
  f <- file.path(JUD_DIR, "comarcas_mt.geojson")
  if (!file.exists(f) || nrow(JUD_PER) == 0) return(sem_mapa())
  g <- sf::st_read(f, quiet = TRUE)
  g <- dplyr::left_join(g, JUD_PER[, c("comarca", "taxa_eb_local_100mil", "faixa_taxa_suavizada", "limite_inferior", "acoes_saude", "populacao_media")], by = "comarca")
  cor <- unname(COR_FAIXA[g$faixa_taxa_suavizada]); cor[is.na(cor)] <- "#f3f4f6"
  nmun <- vapply(strsplit(g$municipios, "; ", fixed = TRUE), length, integer(1))
  rot <- sprintf(paste0("<b>Comarca de %s</b><br>Taxa suavizada 2022–2024: <b>%s</b> ações de saúde por 100 mil hab./ano (faixa %s)",
                        "<br>%s<br><span style='color:#6b7280'>%s</span>%s"),
                 esc(g$comarca), num(g$taxa_eb_local_100mil), g$faixa_taxa_suavizada,
                 sprintf("%s ações atribuíveis em 2022–2024 · população média %s", supr_j(g$acoes_saude), num(g$populacao_media)),
                 ifelse(nmun == 1, sprintf("Abrange apenas o município de %s.", esc(g$municipios)),
                        sprintf("Abrange %s municípios, aos quais se atribui a mesma taxa: %s.", por_extenso(nmun), esc(gsub("; ", ", ", g$municipios)))),
                 ifelse(g$limite_inferior %in% TRUE,
                        "<br><b>Limite inferior:</b> parte das ações dos moradores tramita em unidades centralizadas sem origem identificável.", ""))
  li <- g[g$limite_inferior %in% TRUE, ]
  bb <- bbox_num(g)
  leg_li <- sprintf(paste0("<div class='leg-li'><span class='leg-traco' style='border-top:3px dashed %s'></span> Cuiabá e Várzea Grande: limite inferior<br>",
                           "<span class='leg-traco' style='border-top:1.5px solid #1f2937'></span> limite de comarca</div>"), COR_LIM)
  m <- mapa_vazio(altura) |>
    addPolygons(data = g, fillColor = cor, fillOpacity = 1, color = "#1f2937", weight = 0.9, opacity = 0.8,
                label = lapply(rot, HTML), highlightOptions = highlightOptions(weight = 2.5, color = "#111827", bringToFront = FALSE)) |>
    addPolygons(data = li, fill = FALSE, color = COR_LIM, weight = 3.5, opacity = 1, dashArray = "6,4",
                options = pathOptions(interactive = FALSE)) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4])
  # legendas FORA do mapa (no celular, dentro do mapa cobriam parte do estado)
  leg <- div(class = "leg-jud", role = "group", `aria-label` = "Legenda do mapa",
             span(class = "leg-jud-tit", "Ações de saúde por 100 mil hab./ano (taxa suavizada, 2022–2024):"),
             lapply(FAIXAS_JUD, function(f) span(class = "leg-jud-item", span(class = "leg-jud-cx", style = paste0("background:", COR_FAIXA[[f]])), f)),
             span(class = "leg-jud-item", HTML(sprintf("<span class='leg-traco' style='border-top:3px dashed %s'></span>", COR_LIM)), "Cuiabá e Várzea Grande: limite inferior"),
             span(class = "leg-jud-item", HTML("<span class='leg-traco' style='border-top:1.5px solid #1f2937'></span>"), "limite de comarca"))
  tagList(m, leg)
}

# Ranking das comarcas pela taxa suavizada 2022–2024 (posição por competição sobre o valor publicado)
tabela_ranking <- function(id_html = "tab-jud-comarcas") {
  d <- JUD_PER |>
    mutate(pos = dplyr::min_rank(dplyr::desc(taxa_eb_local_100mil)),
           muns = vapply(comarca, function(cc) paste(muns_da_comarca(cc), collapse = ", "), character(1))) |>
    arrange(desc(taxa_eb_local_100mil), desc(taxa_100mil), comarca) |>
    transmute(Posição = paste0(pos, "º"), Comarca = comarca, muns, pop = populacao_media, acoes = acoes_saude,
              pub = acoes_publica, sup = acoes_suplementar, bruta = taxa_100mil, eb = taxa_eb_local_100mil,
              faixa = faixa_taxa_suavizada,
              obs = ifelse(limite_inferior, "Limite inferior: parte das ações sem origem identificável", ""))
  nc <- function(nome, f = num, w = 88, ...) colDef(name = nome, align = "right", minWidth = w, cell = function(v) supr_j(v, f), ...)
  tagList(
    a(class = "btn btn-sm btn-outline-primary mb-2", href = "../arquivos/dados/judicializacao_comarca_2022_2024.csv", download = NA,
      "Baixar o arquivo das comarcas, 2022–2024 (CSV; colunas no dicionário)"),
    div(class = "rolagem-x", reactable(d, elementId = id_html, compact = TRUE, striped = TRUE, highlight = TRUE, searchable = TRUE,
      wrap = TRUE, defaultPageSize = 20, showPageSizeOptions = TRUE, pageSizeOptions = c(20, 79),
      columnGroups = list(colGroup(name = "Ações atribuíveis, 2022–2024 (soma)", columns = c("acoes", "pub", "sup")),
                          colGroup(name = "Por 100 mil hab. por ano, 2022–2024", columns = c("bruta", "eb", "faixa"))),
      columns = list(
        Posição = colDef(align = "center", minWidth = 62, sortable = FALSE),
        Comarca = colDef(minWidth = 140, sticky = "left", style = list(fontWeight = 600)),
        muns = colDef(name = "Municípios abrangidos (herdam a taxa)", minWidth = 210, style = list(fontSize = ".78rem", color = "#4b5563")),
        pop = colDef(name = "População média", align = "right", minWidth = 92, cell = function(v) num(v)),
        acoes = nc("Total"), pub = nc("Saúde pública"), sup = nc("Saúde suplementar"),
        bruta = nc("Taxa bruta", function(v) num(v, 1)),
        eb = nc("Taxa suavizada (arredondada a 5)", num, 100, style = list(fontWeight = 600)),
        faixa = colDef(name = "Faixa", minWidth = 104, html = TRUE, cell = function(v) chip_faixa(v)),
        obs = colDef(name = "Observação", minWidth = 160, style = list(fontSize = ".78rem"))))))
}

# Municípios: taxa e faixa HERDADAS da comarca (o DataJud não informa o município do autor)
tabela_municipios_jud <- function(prefixo = "../municipios/", id_html = "tab-jud-mun") {
  m <- JUD_MUN[JUD_MUN$ano == ANO_COMPL, ]
  if (nrow(m) == 0) return(p(class = "nota-fonte", "Não há dados por município."))
  per <- JUD_PER[, c("comarca", "faixa_taxa_suavizada")]; names(per)[2] <- "faixa_per"
  d <- m |> left_join(per, by = "comarca") |>
    left_join(JUD_CM[, c("cod_mun6", "sede_comarca")], by = "cod_mun6") |>
    transmute(cod = cod_mun6, Município = nome_municipio, Região = sem_mt(nome_regsaud), Comarca = comarca,
              sede = ifelse(sede_comarca, "sede", "abrangido"),
              eb = taxa_eb_local_2022_2024_100mil, faixa_per, faixa25 = faixa_taxa_suavizada,
              obs = ifelse(taxa_limite_inferior, "Limite inferior (comarca de Cuiabá ou de Várzea Grande)", ""))
  d <- d[ordem_nome(d$Município), ]
  tem_perfil <- d$cod %in% MUN$cod_mun6
  tagList(
    a(class = "btn btn-sm btn-outline-primary mb-2", href = "../arquivos/dados/judicializacao_municipio_ano.csv", download = NA,
      "Baixar o arquivo por município e ano (CSV; colunas no dicionário)"),
    div(class = "rolagem-x", reactable(d, elementId = id_html, compact = TRUE, striped = TRUE, highlight = TRUE, searchable = TRUE,
      wrap = TRUE, defaultPageSize = 15, showPageSizeOptions = TRUE, pageSizeOptions = c(15, 50, nrow(d)),
      columnGroups = list(colGroup(name = "Valor da COMARCA, atribuído ao município", columns = c("eb", "faixa_per", "faixa25"))),
      columns = list(cod = colDef(show = FALSE),
        Município = colDef(minWidth = 150, sticky = "left",
                           cell = function(v, i) if (tem_perfil[i]) a(href = url_mun(d$cod[i], prefixo), v) else v),
        Região = colDef(name = "Região de saúde", minWidth = 130),
        Comarca = colDef(minWidth = 130),
        sede = colDef(name = "Na comarca", minWidth = 82),
        eb = colDef(name = "Taxa suavizada 2022–2024 (por 100 mil hab./ano)", align = "right", minWidth = 120,
                    cell = function(v) supr_j(v), style = list(fontWeight = 600)),
        faixa_per = colDef(name = "Faixa 2022–2024", minWidth = 104, html = TRUE, cell = function(v) chip_faixa(v)),
        faixa25 = colDef(name = "Faixa 2025 (afetada pela centralização)", minWidth = 124, html = TRUE, cell = function(v) chip_faixa(v)),
        obs = colDef(name = "Observação", minWidth = 150, style = list(fontSize = ".78rem"))))))
}

# Faixas por ano (2022–2026) de cada comarca, com as ações atribuíveis do ano
tabela_faixas_ano <- function(anos = 2022:2026) {
  ca <- JUD_CA[JUD_CA$ano %in% anos, ]
  if (nrow(ca) == 0) return(p(class = "nota-fonte", "Não há série por comarca."))
  cel <- ca |> mutate(txt = ifelse(is.na(acoes_saude), chip_faixa(NA),
                                   chip_faixa(faixa_taxa_suavizada, sprintf('<div class="sub">%s ações</div>', num(acoes_saude))))) |>
    select(comarca, ano, txt) |> tidyr::pivot_wider(names_from = ano, values_from = txt)
  per <- JUD_PER[, c("comarca", "taxa_eb_local_100mil")]
  d <- per |> left_join(cel, by = "comarca") |> arrange(desc(taxa_eb_local_100mil), comarca) |> select(-taxa_eb_local_100mil)
  cols <- list(comarca = colDef(name = "Comarca", minWidth = 140, sticky = "left", style = list(fontWeight = 600)))
  for (a in anos) cols[[as.character(a)]] <- colDef(name = if (a == 2026) "2026 (até 11/09; não anualizada) ⚠" else if (a == 2025) "2025 ⚠" else as.character(a),
                                                    html = TRUE, minWidth = 104, align = "center", sortable = FALSE)
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = FALSE, pagination = TRUE, defaultPageSize = 20,
    showPageSizeOptions = TRUE, pageSizeOptions = c(20, 79), searchable = TRUE, wrap = TRUE, columns = cols,
    columnGroups = list(colGroup(name = "Período principal", columns = c("2022", "2023", "2024")),
                        colGroup(name = "⚠ Afetados pela centralização no Núcleo 4.0", columns = c("2025", "2026")))))
}

# ---- 6. Previsão (J3) --------------------------------------------------------------------------------
prev_grupo <- function(g) JUD_PREV[JUD_PREV$grupo == g, ] |> mutate(alvo = as.Date(alvo)) |> arrange(alvo)
obs_grupo <- function(g) {
  m <- JUD_MES[!JUD_MES$mes_incompleto, ]
  if (g == "total") m <- m |> group_by(ano, mes) |> summarise(acoes = sum(acoes), .groups = "drop")
  else m <- m[m$grupo == g, c("ano", "mes", "acoes")]
  m |> arrange(ano, mes) |> mutate(x = ano + (mes - 1) / 12)
}

grafico_previsao <- function(g, desde = 2023) {
  o <- obs_grupo(g); o <- o[o$ano >= desde, ]
  pv <- prev_grupo(g)
  if (nrow(o) == 0 || nrow(pv) == 0) return("")
  px <- as.integer(format(pv$alvo, "%Y")) + (as.integer(format(pv$alvo, "%m")) - 1) / 12
  ult <- tail(o, 1)
  cor <- COR_GRUPO_MES[[g]]; mod <- MODELOS_CURTO[[pv$modelo[1]]]
  tip_o <- sprintf("%s · %s: %s ações (observado)", GRUPOS_PREV[[g]], mes_rot(o$ano, o$mes), num(o$acoes))
  tip_p <- c(sprintf("%s · %s: %s ações (observado)", GRUPOS_PREV[[g]], mes_rot(ult$ano, ult$mes), num(ult$acoes)),
             sprintf("%s · %s: previsão %s (intervalo de 80%%: %s a %s; %s)", GRUPOS_PREV[[g]],
                     mes_rot(as.integer(format(pv$alvo, "%Y")), as.integer(format(pv$alvo, "%m"))),
                     num(pv$prev), num(pv$li80), num(pv$ls80), mod))
  s <- list(list(nome = "Observado", cor = cor, larg = 2.2, dash = "", x = o$x, y = o$acoes, tips = tip_o),
            list(nome = sprintf("Previsão (%s)", mod), cor = "#b45309", larg = 2.4, dash = "5,4",
                 x = c(ult$x, px), y = c(ult$acoes, pv$prev), tips = tip_p))
  b <- list(list(x = px, lo = pv$li80, hi = pv$ls80, cor = "#b45309", tip = "Intervalo de 80% da previsão (empírico, a partir dos erros da validação)"))
  leg <- '<span class="leg-item"><svg width="16" height="12" aria-hidden="true"><rect width="16" height="12" fill="#b45309" fill-opacity="0.16" stroke="#b45309" stroke-opacity="0.35" stroke-dasharray="2,2"/></svg>Intervalo de 80%</span>'
  xt <- desde:2026; xl <- paste0("jan/", xt)
  HTML(svg_linhas_jud(s, sprintf("%s: ações de saúde por mês no 1º grau do TJMT (observado até ago/2026) e previsão para set–nov/2026", GRUPOS_PREV[[g]]),
                      xt = xt, xl = xl, tip_x = function(x) x, bandas = b, leg_extra = leg, r_pt = 2.2, h = 260))
}

# Quadro da previsão: mês a mês, trimestre e intervalo de 80% (soma dos limites mensais publicados)
tabela_previsao <- function() {
  if (nrow(JUD_PREV) == 0) return(p(class = "nota-fonte", "Previsão indisponível."))
  d <- JUD_PREV |> mutate(mes = format(as.Date(alvo), "%m")) |> group_by(grupo, modelo) |>
    summarise(set = prev[mes == "09"], out = prev[mes == "10"], nov = prev[mes == "11"], tri = sum(prev),
              li = sum(li80), ls = sum(ls80), .groups = "drop") |>
    mutate(ordem = match(grupo, names(GRUPOS_PREV))) |> arrange(ordem) |>
    transmute(Grupo = unname(GRUPOS_PREV[grupo]), Modelo = unname(MODELOS_CURTO[modelo]), set, out, nov, tri,
              int = sprintf("%s a %s", num(li), num(ls)))
  nc <- function(nome) colDef(name = nome, align = "right", minWidth = 80, cell = function(v) num(v))
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE,
    rowStyle = function(i) if (i == 1) list(fontWeight = 600) else NULL,
    columns = list(Grupo = colDef(minWidth = 190, sticky = "left"), Modelo = colDef(name = "Modelo (menor MASE)", minWidth = 100),
                   set = nc("Set/2026"), out = nc("Out/2026"), nov = nc("Nov/2026"), tri = nc("Trimestre"),
                   int = colDef(name = "Intervalo de 80% do trimestre", align = "right", minWidth = 130))))
}

# Métricas da validação rolling-origin (26 origens, horizontes de 1 a 3 meses)
tabela_metricas <- function() {
  if (nrow(JUD_MET) == 0) return(p(class = "nota-fonte", "Métricas indisponíveis."))
  esc_mod <- JUD_PREV |> distinct(grupo, modelo) |> rename(escolhido = modelo)
  m <- JUD_MET |> left_join(esc_mod, by = "grupo")
  w <- m |> select(grupo, modelo, mase) |> tidyr::pivot_wider(names_from = modelo, values_from = mase)
  e <- m |> filter(modelo == escolhido) |> transmute(grupo, escolhido, mae, red = 100 * (1 - rmae), n)
  d <- w |> left_join(e, by = "grupo") |> mutate(ordem = match(grupo, names(GRUPOS_PREV))) |> arrange(ordem) |>
    mutate(Grupo = unname(GRUPOS_PREV[grupo]))
  celm <- function(mod) colDef(name = MODELOS_CURTO[[mod]], align = "right", minWidth = 86, html = TRUE,
    cell = function(v, i) if (d$escolhido[i] == mod) sprintf('<b>%s ✓</b>', num(v, 2)) else num(v, 2))
  div(class = "rolagem-x", reactable(d |> select(Grupo, all_of(names(MODELOS)), mae, red), compact = TRUE, striped = TRUE,
    pagination = FALSE, sortable = FALSE, wrap = TRUE,
    columnGroups = list(colGroup(name = "MASE na validação (menor = melhor; abaixo de 1 = erro menor que o do ingênuo sazonal no treino)", columns = names(MODELOS)),
                        colGroup(name = "Modelo escolhido (✓)", columns = c("mae", "red"))),
    columns = c(list(Grupo = colDef(minWidth = 180, sticky = "left")),
                setNames(lapply(names(MODELOS), celm), names(MODELOS)),
                list(mae = colDef(name = "Erro absoluto médio (ações/mês)", align = "right", minWidth = 110, cell = function(v) num(v, 1)),
                     red = colDef(name = "Redução do erro frente ao ingênuo sazonal", align = "right", minWidth = 120, cell = function(v) pct_j(v, 0))))))
}

# ---- 7. Fatores associados (J2) ---------------------------------------------------------------------------
tabela_j2 <- function(dep) {
  d <- JUD_J2[JUD_J2$dependente == dep, ]
  if (nrow(d) == 0) return(p(class = "nota-fonte", "Não há resultados para este tipo de ação."))
  d$bloco <- J2_BLOCO[d$variavel]
  d <- d[order(match(d$bloco, names(J2_BLOCOS)), match(d$variavel, names(J2_VAR))), ]
  dp <- vapply(seq_len(nrow(d)), function(i) {
    v <- d$variavel[i]; s <- d$dp_variavel[i]
    if (is.na(s) || !v %in% names(J2_UNID)) return("indicadora (0/1)")
    sprintf(J2_UNID[[v]], num(s, if (s >= 100) 0 else if (s >= 10) 1 else 2))
  }, character(1))
  t <- tibble::tibble(Bloco = unname(J2_BLOCOS[d$bloco]), Variável = unname(J2_VAR[d$variavel]), dp = unname(dp),
                      irr = sprintf("%s (%s–%s)", dec2(d$irr), dec2(d$irr_li), dec2(d$irr_ls)),
                      p = p_txt(d$p), holm = ifelse(is.na(d$p_holm), "—", p_txt(d$p_holm)), bh = ifelse(is.na(d$p_bh), "—", p_txt(d$p_bh)))
  t$Bloco <- c(J2_BLOCO_CURTO[d$bloco])
  div(class = "rolagem-x", reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE,
    columns = list(Bloco = colDef(name = "Bloco", minWidth = 110, style = function(v, i) list(color = COR_BLOCO[[d$bloco[i]]], fontWeight = 600)),
                   Variável = colDef(minWidth = 200),
      dp = colDef(name = "1 desvio-padrão =", minWidth = 120),
      irr = colDef(name = "Razão de taxas (IC 95%)", align = "right", minWidth = 130),
      p = colDef(name = "p bruto", align = "right", minWidth = 70),
      holm = colDef(name = "p ajustado (Holm)", align = "right", minWidth = 80),
      bh = colDef(name = "p ajustado (Benjamini-Hochberg)", align = "right", minWidth = 110))))
}

# Grupos de assunto (exploratório): só o bloco de oferta e eficiência, três dependentes
tabela_j2_grupos <- function() {
  deps <- c("acoes_medicamentos", "acoes_tratamento", "acoes_internacao_uti")
  d <- JUD_J2[JUD_J2$dependente %in% deps & JUD_J2$variavel %in% names(J2_BLOCO)[J2_BLOCO == "oferta"], ]
  if (nrow(d) == 0) return(p(class = "nota-fonte", "Não há resultados para os grupos de assunto."))
  d <- d |> mutate(txt = sprintf("%s (%s–%s)<div class='sub'>p %s · BH %s</div>", dec2(irr), dec2(irr_li), dec2(irr_ls), p_txt(p), p_txt(p_bh))) |>
    select(variavel, dependente, txt) |> tidyr::pivot_wider(names_from = dependente, values_from = txt) |>
    mutate(ordem = match(variavel, names(J2_VAR))) |> arrange(ordem) |> transmute(Variável = unname(J2_VAR[variavel]), !!!rlang::syms(deps))
  div(class = "rolagem-x", reactable(d, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE,
    columns = c(list(Variável = colDef(minWidth = 200)),
                setNames(lapply(deps, function(x) colDef(name = J2_DEP[[x]], html = TRUE, align = "right", minWidth = 130)), deps))))
}

# Valor de uma linha do J2 (para o texto)
j2 <- function(dep, var) { r <- JUD_J2[JUD_J2$dependente == dep & JUD_J2$variavel == var, ]; if (nrow(r)) r[1, ] else NULL }
irr_txt <- function(r, extra = "") sprintf("%s (IC 95%% %s–%s%s)", dec2(r$irr), dec2(r$irr_li), dec2(r$irr_ls), extra)
# Mesma razão para uso DENTRO de parênteses (v0.5: sem parênteses aninhados): "1,18; IC 95%: 1,03–1,35"
irr_par <- function(r) sprintf("%s; IC 95%%: %s–%s", dec2(r$irr), dec2(r$irr_li), dec2(r$irr_ls))

# Nota de supressão (auditoria da origem)
aud_val <- function(prefixo) {
  i <- which(startsWith(as.character(JUD_AUD$item), prefixo)); if (!length(i)) return("—")
  v <- as.character(JUD_AUD$valor[i[1]]); n <- suppressWarnings(as.numeric(v))
  if (is.na(n)) v else num(n)
}
