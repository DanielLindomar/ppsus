# =============================================================================
# Observatório PPSUS-MT — funções da página previsao/index.qmd (previsão de demanda, atividade A5)
#
# Carregar DEPOIS de R/funcoes.R (que não deve ser editado). Lê só dados_site/previsao/, gravado
# por scripts/08_preparar_previsao.py (cópias conferidas dos CSV agregados da A5, já com a
# supressão de contagens de 1 a 4 e a supressão complementar). Nada aqui recalcula valor
# suprimido: célula vazia aparece como "suprimido" (contagem observada) ou fica fora do gráfico.
# Estimativas de modelo (previsões, nowcast e limites de intervalo) abaixo de 5 aparecem como
# "< 5", por coerência com a regra de supressão (fmt_est).
#
# Índice
#   1. Leitura, constantes, rótulos e formatação
#   2. Gráfico de série semanal em SVG (motor genérico svg_tempo)
#   3. Situação agora: gráfico por região, minicartões, seletor, quadro das 4 semanas
#   4. Quão bem os modelos acertam: tabelas de erro, testes de Diebold-Mariano, cobertura
#   5. Alerta: classificação, antecedência, contexto pediátrico
#   6. Fontes e arquivos
# =============================================================================

# ---- 1. Leitura, constantes, rótulos e formatação -------------------------------------------------
PREV_DIR <- file.path(RAIZ, "dados_site", "previsao")

# Lê um CSV de dados_site/previsao; códigos de região e textos ficam como texto; datas viram Date;
# colunas *_suprimido / melhor_* viram lógicas
ler_prev <- function(nome) {
  f <- file.path(PREV_DIR, nome)
  if (!file.exists(f)) { aviso("previsão: arquivo ausente dados_site/previsao/%s (rode scripts/08_preparar_previsao.py)", nome); return(NULL) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  txt <- intersect(c("versao", "cod_regiao", "regiao", "modelo", "modelo_a", "modelo_b", "metodo", "otica", "nivel", "alvo",
                     "fonte", "regra", "cenario", "status", "tipo", "horizonte", "faixa_atraso_semanas", "corte",
                     "rotulo_modelo", "rotulo_metodo", "rotulo_a", "rotulo_b", "rotulo_alvo", "inicio_se", "fim_se",
                     "inicio_se_alvo", "fim_se_alvo", "chave", "valor", "fonte"), hdr)
  d <- tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "",
                                           colClasses = list(character = txt)))
  for (cn in grep("_suprimido$|^melhor_mase", names(d), value = TRUE)) d[[cn]] <- d[[cn]] %in% c(TRUE, "True", "TRUE", "true")
  for (cn in intersect(c("inicio_se", "fim_se", "inicio_se_alvo", "fim_se_alvo"), names(d))) d[[cn]] <- as.Date(d[[cn]])
  d
}

META_PREV <- local({ m <- ler_prev("meta.csv"); if (is.null(m)) character(0) else setNames(m$valor, m$chave) })
meta_prev <- function(k, padrao = "—") { v <- META_PREV[k]; if (is.na(v)) padrao else unname(v) }

SERIE_OBS <- ler_prev("a5_site_serie_observada.csv")          # baseline: SE 1/2020 a 12/2026
MET_RES   <- ler_prev("a5_site_metricas_resumo.csv")
MET_REG   <- ler_prev("a5_site_metricas_regiao.csv")
ROLL_MT   <- ler_prev("a5_site_rolling_mt.csv")
DM_BASE   <- ler_prev("a5_site_testes_dm.csv")
COB_INT   <- ler_prev("a5_site_intervalos_cobertura.csv")
SERIE_HOJ <- ler_prev("a5nc_site_serie_completa_hoje.csv")    # carga de 17/10: SE 1/2024 a 16/2026
NOW_HOJ   <- ler_prev("a5nc_site_nowcast_hoje.csv")
PREV_HOJ  <- ler_prev("a5nc_site_previsao_hoje.csv")
MET_NOW   <- ler_prev("a5nc_site_metricas_nowcast.csv")
MET_ENC   <- ler_prev("a5nc_site_metricas_encadeado.csv")
DM_ENC    <- ler_prev("a5nc_site_testes_dm.csv")
MET_M5    <- ler_prev("a5nc_site_metricas_menor5.csv")
ALE_LIM   <- ler_prev("a5nc_site_alerta_limiares.csv")
ALE_MED   <- ler_prev("a5nc_site_alerta_medidas.csv")
ALE_ANT   <- ler_prev("a5nc_site_alerta_antecedencia.csv")
CTX_PED   <- ler_prev("a5nc_site_contexto_pediatrico.csv")

NIV_REG <- "16 regioes (media)"; NIV_MT <- "Mato Grosso"
ALVOS <- c(j00_j99 = "todas as idades", j00_j99_menor5 = "menores de 5 anos")

# Regiões: Mato Grosso primeiro, depois as 16 em ordem alfabética (sem acento)
REG_PREV <- local({
  r <- unique(PREV_HOJ[PREV_HOJ$cod_regiao != "MT", c("cod_regiao", "regiao")])
  r <- r[ordem_nome(r$regiao), ]
  rbind(tibble::tibble(cod_regiao = "MT", regiao = "Mato Grosso"), r)
})
nome_reg_prev <- function(cod) REG_PREV$regiao[match(cod, REG_PREV$cod_regiao)]

# Rótulos dos modelos do baseline e das variantes
ROT_MOD <- c(ingenuo_sazonal = "Ingênuo sazonal", ingenuo_sazonal_aj = "Ingênuo sazonal ajustado",
             ingenuo_ultima = "Persistência (última semana)", sarima = "SARIMA", sarima_soma_regioes = "SARIMA (soma das regiões)",
             hgb = "Gradient boosting (HGB)", lgbm = "LightGBM", rf = "Random Forest", mlp = "Rede neural (MLP)",
             hgb_sem_exog = "HGB sem SRAG e clima", hgb_pandemia = "HGB com 2020–2021")
FAM_MOD <- c(ingenuo_sazonal = "referência ingênua", ingenuo_sazonal_aj = "referência ingênua", ingenuo_ultima = "referência ingênua",
             sarima = "estatístico", sarima_soma_regioes = "estatístico (sensibilidade)", hgb = "aprendizado de máquina",
             lgbm = "aprendizado de máquina", rf = "aprendizado de máquina", mlp = "aprendizado de máquina",
             hgb_sem_exog = "aprendizado de máquina (sensibilidade)", hgb_pandemia = "aprendizado de máquina (sensibilidade)")
DESC_MOD <- c(ingenuo_sazonal = "repete o valor da mesma semana do ano anterior",
              ingenuo_sazonal_aj = "mesma semana do ano anterior, corrigida pelo crescimento recente",
              ingenuo_ultima = "repete o valor da última semana conhecida",
              sarima = "modelo estatístico sazonal ajustado a cada série",
              sarima_soma_regioes = "soma das previsões SARIMA das 16 regiões",
              hgb = "árvores de decisão em sequência (scikit-learn), com SRAG, clima e calendário",
              lgbm = "árvores de decisão em sequência (LightGBM), mesmas variáveis do HGB",
              rf = "média de 500 árvores de decisão, mesmas variáveis do HGB",
              mlp = "perceptron com duas camadas ocultas, média de 5 redes, mesmas variáveis do HGB",
              hgb_sem_exog = "HGB só com a própria série e o calendário",
              hgb_pandemia = "HGB treinado desde 2020, com indicadores da pandemia")
MODS_PRINC <- c("ingenuo_sazonal", "ingenuo_ultima", "sarima", "hgb", "lgbm", "rf", "mlp")
MOD_REF <- "lgbm"
rot_mod <- function(m) ifelse(m %in% names(ROT_MOD), ROT_MOD[m], m)

# Nowcast, previsão encadeada e alerta
ROT_NC <- c(parcial = "Contagem já processada, sem correção", prior = "Ingênuo sazonal ajustado no corte",
            cl = "Chain-ladder (curva de completude)", bf = "Bornhuetter-Ferguson", ml = "LightGBM (principal)",
            ml_bf = "LightGBM com base Bornhuetter-Ferguson (post hoc)")
ROT_ENC <- c(ref_sem_atraso_lgbm_sem_exog = "Referência sem atraso, mesmas variáveis (inalcançável em tempo real)",
             baseline_sem_atraso_lgbm = "Referência sem atraso: LightGBM do baseline (inalcançável em tempo real)",
             encadeado_ml = "Nowcast LightGBM + LightGBM (principal)", encadeado_cl = "Nowcast chain-ladder + LightGBM",
             encadeado_ml_bf = "Nowcast LightGBM-BF + LightGBM (post hoc)", sem_nowcast_lgbm = "LightGBM sem nowcast",
             ingenuo_sazonal = "Ingênuo sazonal", ingenuo_sazonal_aj = "Ingênuo sazonal ajustado",
             baseline_sem_atraso_ingenuo_sazonal = "Referência sem atraso: ingênuo sazonal")
rot_enc <- function(m) ifelse(m %in% names(ROT_ENC), ROT_ENC[m], rot_mod(m))

# Situação do alerta (coluna status de a5nc_site_previsao_hoje.csv)
STATUS_ROT <- c(alta = "▲ Alta pressão prevista", possivel = "△ Possível", abaixo = "▽ Abaixo do limiar",
                sem_limiar = "Limiar suprimido", copia = "Suprimido")
STATUS_SEV <- c(sem_limiar = 0, copia = 0, abaixo = 1, possivel = 2, alta = 3)
status_cod <- function(s) dplyr::case_when(grepl("^alta", s) ~ "alta", grepl("^possivel", s) ~ "possivel",
                                           grepl("^abaixo", s) ~ "abaixo", grepl("^limiar suprimido", s) ~ "sem_limiar",
                                           TRUE ~ "copia")
selo_status <- function(cod) sprintf('<span class="st st-%s">%s</span>', cod, STATUS_ROT[cod])

# Formatação (num, fmt_eixo e esc vêm de R/funcoes.R)
MES_ABR <- c("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez")
dmy  <- function(d) format(d, "%d/%m/%Y")
dm   <- function(d) format(d, "%d/%m")
pct  <- function(x, d = 0) ifelse(is.na(x), "—", paste0(num(100 * x, d), "%"))
dec2 <- function(x) ifelse(is.na(x), "—", num(x, 2))
dec1 <- function(x) ifelse(is.na(x), "—", num(x, 1))
p_txt <- function(p) ifelse(is.na(p), "—", ifelse(p < 0.001, "p < 0,001", paste0("p = ", num(p, 3))))
# Estimativa de modelo arredondada; QUALQUER valor abaixo de 5 (testado antes de arredondar, inclusive 4,5 a 5)
# aparece como "< 5", como diz a nota da página; intervalo com limite inferior abaixo de 5: "< 5 a X"
fmt_est <- function(x) ifelse(is.na(x), "—", ifelse(x < 5, "< 5", num(x, 0)))
fmt_int_est <- function(lo, hi) ifelse(is.na(lo) | is.na(hi), "—", ifelse(hi < 5, "< 5", ifelse(lo < 5, paste0("< 5 a ", fmt_est(hi)), paste0(fmt_est(lo), " a ", fmt_est(hi)))))
# Versões escapadas para montar HTML ("< 5" vira "&lt; 5")
est_h <- function(x) esc(fmt_est(x)); int_h <- function(lo, hi) esc(fmt_int_est(lo, hi))
# Contagem observada: vazio = suprimido (nunca recalculado)
fmt_obs <- function(x) ifelse(is.na(x), "suprimido", num(x, 0))
# Limiar de alerta (percentil): vazio = suprimido
fmt_lim <- function(x) ifelse(is.na(x), "suprimido", num(x, 1))
se_txt <- function(se, ano) paste0("SE ", se, "/", ano)
periodo_se <- function(ini, fim) paste0(dm(ini), " a ", dm(fim))
lista_e_prev <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
data_iso_br <- function(s) { d <- as.Date(s); if (is.na(d)) s else dmy(d) }

# Datas de referência (meta.csv, gravado pelo script 08)
CORTE      <- as.Date(meta_prev("corte", NA))
ANO_CORTE  <- as.integer(meta_prev("ano_corte", NA))
SE_CORTE   <- as.integer(meta_prev("se_corte", NA))
SE_NOW_INI <- as.integer(meta_prev("se_nowcast_ini", NA))
SE_PREV_INI <- as.integer(meta_prev("se_previsao_ini", NA)); SE_PREV_FIM <- as.integer(meta_prev("se_previsao_fim", NA))
ULT_COMPL  <- meta_prev("ultima_se_completa"); FIM_ULT_COMPL <- as.Date(meta_prev("fim_ultima_se_completa", NA))
ULT_BASE   <- meta_prev("ultima_se_completa_baseline")
COMPET_SIH <- meta_prev("competencia_sih"); CARGA_SIH <- meta_prev("carga_sih"); VERSAO_SIVEP <- meta_prev("versao_sivep")
VERSAO_BASE <- meta_prev("versao_baseline"); VERSAO_NC <- meta_prev("versao_nowcast")

# CSS da página (classes próprias; o restante vem de estilo.scss)
css_previsao <- function() tags$style(HTML("
body.fullcontent main.content { min-width: 0; }
.faixa-prelim { background: #fff4d6; border-left: 4px solid #d4a017; padding: .6rem 1rem; font-size: .92rem; margin: 0 0 1.2rem; border-radius: 4px; }
.faixa-prelim b { color: #7a4d00; }
.st { display: inline-block; padding: 1px 8px; border-radius: 10px; font-size: .76rem; font-weight: 600; white-space: nowrap; border: 1px solid rgba(0,0,0,.08); }
.st-alta { background: #fde4e1; color: #a51d14; }
.st-possivel { background: #fff1c7; color: #7a4d00; }
.st-abaixo { background: #eef0f4; color: #374151; }
.st-sem_limiar, .st-copia { background: #f3f4f6; color: #4b5563; font-weight: 500; }
.selo-ref { display: inline-block; padding: 0 6px; border-radius: 8px; background: #E2EFEE; color: #0E5A5E; font-size: .72rem; font-weight: 700; white-space: nowrap; }
.prev-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: .7rem; margin: .8rem 0 1.4rem; }
.prev-card { display: block; width: 100%; text-align: left; border: 1px solid #d9e4e4; border-radius: 8px; padding: .55rem .7rem .5rem; background: #fff; color: #1f2937; font: inherit; cursor: pointer; }
.prev-card:hover, .prev-card:focus-visible { border-color: #0E5A5E; box-shadow: 0 2px 8px rgba(14,90,94,.14); outline: none; }
.prev-card[aria-pressed='true'] { border: 2px solid #0E5A5E; background: #f6fbfb; }
.prev-card .pc-topo { display: flex; justify-content: space-between; align-items: flex-start; gap: .4rem; }
.prev-card .pc-nome { display: block; font-weight: 600; font-size: .9rem; line-height: 1.2; color: #0E5A5E; }
.prev-card .pc-num { display: block; font-size: .8rem; color: #374151; margin-top: .15rem; }
.prev-card .pc-sub { display: block; font-size: .74rem; color: #6b7280; }
.prev-card svg { display: block; width: 100%; height: auto; margin: .25rem 0 .1rem; }
.prev-sel { display: flex; flex-wrap: wrap; gap: .5rem .9rem; align-items: center; margin: .6rem 0 .4rem; }
.prev-sel label { font-weight: 600; font-size: .9rem; }
.prev-sel select { max-width: 340px; flex: 1 1 220px; }
.prev-det { border: 1px solid #e6eeee; border-radius: 8px; padding: .6rem .9rem .4rem; background: #fff; }
.prev-det h4 { margin: .1rem 0 .3rem; font-size: 1.05rem; }
.grafico-prev .rolar-svg { max-width: 100%; overflow-x: auto; }
.grafico-prev .dica-rolar { display: none; font-size: .76rem; color: #6b7280; margin: 0 0 .15rem; }
@media (max-width: 620px) { .grafico-prev .dica-rolar { display: block; } }
.grafico-prev .rolar-svg > svg { width: 100%; min-width: 540px; height: auto; max-width: 820px; display: block; }
.grafico-prev svg text { paint-order: stroke; stroke: #fff; stroke-width: 3px; stroke-linejoin: round; }
table.tab-prev caption { caption-side: top; font-size: .82rem; color: #4b5563; text-align: left; padding: 0 0 .2rem; }
.grafico-prev .legenda-svg { margin-top: .3rem; }
.rolagem-x { max-width: 100%; overflow-x: auto; }
table.tab-prev { font-size: .84rem; border-collapse: collapse; margin: .4rem 0 .6rem; min-width: 100%; }
table.tab-prev th, table.tab-prev td { padding: 3px 8px; border-bottom: 1px solid #e5e7eb; text-align: right; white-space: nowrap; }
table.tab-prev th:first-child, table.tab-prev td:first-child { text-align: left; }
table.tab-prev th { font-weight: 600; color: #374151; background: #f8fbfb; }
.chave-prev { border-left: 4px solid #0E5A5E; background: #f3f8f8; padding: .6rem 1rem; margin: .5rem 0 1rem; border-radius: 4px; }
.barra-cel { display: flex; align-items: center; gap: .35rem; justify-content: flex-end; }
.barra-cel i { display: inline-block; height: 9px; background: #2E86AB; border-radius: 2px; }
details.mais { margin: .4rem 0 1rem; }
details.mais > summary { cursor: pointer; color: #0E5A5E; font-weight: 600; font-size: .92rem; }
.dicas path { cursor: pointer; }
@media (max-width: 576px) { .prev-cards { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); } }
"))

# Faixa do topo: resultados preliminares
faixa_preliminar <- function() div(class = "faixa-prelim", HTML(sprintf(paste0(
  "<b>Resultados preliminares.</b> Previsão de demanda do Projeto PPSUS-MT (atividade A5), versões <code>%s</code> e ",
  "<code>%s</code>. A especificação dos modelos encontra-se em validação pelo coordenador do projeto, e a regra do alerta ",
  "não foi pactuada com a SES-MT; por essa razão, os números desta página <b>não constituem recomendação oficial nem alerta operacional</b>. ",
  "Corte de %s (SE %d/%d), com o SIH disponível até a competência %s."),
  VERSAO_BASE, VERSAO_NC, dmy(CORTE), SE_CORTE, ANO_CORTE, COMPET_SIH)))

# Atalhos para as seções da página
secoes_prev <- function(secoes) tags$nav(class = "nav-mun", `aria-label` = "Seções desta página",
  lapply(names(secoes), function(id) a(class = "btn btn-sm btn-outline-primary", href = paste0("#", id), secoes[[id]])))

# ---- 2. Gráfico de série semanal em SVG (motor genérico) -----------------------------------------------
# Segmentos contíguos de valores finitos (para linhas e faixas com lacunas)
seg_id <- function(ok) { r <- rle(ok); id <- rep(seq_along(r$lengths), r$lengths); id[!ok] <- NA; id }
caminho_linha <- function(px, py) {
  ok <- is.finite(px) & is.finite(py); if (!any(ok)) return(list(d = "", isol = integer(0)))
  id <- seg_id(ok); grupos <- split(which(ok), id[ok])
  d <- paste(vapply(grupos, function(ix) paste0("M", paste(sprintf("%.1f %.1f", px[ix], py[ix]), collapse = "L")), ""), collapse = "")
  list(d = d, isol = unlist(grupos[lengths(grupos) == 1]))
}
caminho_faixa <- function(px, plo, phi) {
  ok <- is.finite(px) & is.finite(plo) & is.finite(phi); if (!any(ok)) return("")
  id <- seg_id(ok)
  paste(vapply(split(which(ok), id[ok]), function(ix) paste0("M", paste(sprintf("%.1f %.1f", px[ix], phi[ix]), collapse = "L"),
    "L", paste(sprintf("%.1f %.1f", rev(px[ix]), rev(plo[ix])), collapse = "L"), "Z"), ""), collapse = "")
}

# Marcas do eixo x (datas): anos, trimestres ou bimestres conforme a extensão
marcas_x <- function(x0, x1) {
  d0 <- as.Date(x0, origin = "1970-01-01"); d1 <- as.Date(x1, origin = "1970-01-01")
  meses <- seq(as.Date(format(d0, "%Y-%m-01")), d1, by = "month"); meses <- meses[meses >= d0]
  mm <- as.integer(format(meses, "%m")); span <- as.numeric(d1 - d0)
  if (span > 3 * 365) { m <- meses[mm == 1]; lab <- format(m, "%Y") }
  else if (span > 330) { m <- meses[mm %in% c(1, 4, 7, 10)]; lab <- paste0(MES_ABR[as.integer(format(m, "%m"))], "/", format(m, "%y")) }
  else { m <- meses[mm %% 2 == 1]; lab <- paste0(MES_ABR[as.integer(format(m, "%m"))], "/", format(m, "%y")) }
  list(x = as.numeric(m), lab = lab)
}

# series: list(nome, x (Date), y, cor, larg, dash, pontos, leg); faixas: list(nome, x, lo, hi, cor, opac, leg);
# hlinhas: list(y, cor, dash, rot); vlinhas: list(x, rot, cor); zonas: list(x0, x1, cor, rot);
# dicas: data.frame(x (Date), txt) — uma dica por semana (traço vertical transparente)
svg_tempo <- function(series = list(), faixas = list(), hlinhas = list(), vlinhas = list(), zonas = list(), dicas = NULL,
                      titulo = "", w = 760, h = 300, xlim = NULL, ymax = NULL, mini = FALSE, fonte_px = 12) {
  xs <- c(unlist(lapply(series, function(s) as.numeric(s$x))), unlist(lapply(faixas, function(f) as.numeric(f$x))))
  ys <- c(unlist(lapply(series, `[[`, "y")), unlist(lapply(faixas, `[[`, "hi")), unlist(lapply(hlinhas, `[[`, "y")))
  ys <- ys[is.finite(ys)]
  if (!length(ys) || !length(xs)) return("")
  xr <- if (is.null(xlim)) range(xs, na.rm = TRUE) else as.numeric(xlim)
  if (is.null(ymax)) ymax <- max(ys)
  if (mini) { pl <- 2; pr <- 2; pt <- 4; pb <- 3; yr <- c(0, ymax * 1.06); yt <- numeric(0) }
  else { pl <- 44; pr <- 10; pt <- 26; pb <- 24; yt <- pretty(c(0, ymax), n = 4)
    if (length(yt) > 1 && diff(yt[1:2]) < 5) yt <- seq(0, 5 * ceiling(ymax / 5), by = 5)  # marcas do eixo y em múltiplos de 5
    yr <- range(c(0, yt)) }
  sx <- function(x) pl + (as.numeric(x) - xr[1]) / diff(xr) * (w - pl - pr)
  sy <- function(y) h - pb - (y - yr[1]) / diff(yr) * (h - pt - pb)
  out <- character(0)
  # zonas sombreadas (nowcast, previsão, pandemia)
  for (z in zonas) {
    x0 <- max(sx(z$x0), pl); x1 <- min(sx(z$x1), w - pr); if (x1 <= x0) next
    out <- c(out, sprintf('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="%s"/>', x0, pt, x1 - x0, h - pt - pb, z$cor))
    if (!mini && !is.null(z$rot)) out <- c(out, sprintf('<text x="%.1f" y="%d" font-size="%d" fill="#4b5563" text-anchor="%s">%s</text>',
                                                         if (isTRUE(z$fim)) x1 - 3 else (x0 + x1) / 2, h - pb - 6, fonte_px - 1,
                                                         if (isTRUE(z$fim)) "end" else "middle", esc(z$rot)))
  }
  # grade e eixos
  if (!mini) {
    out <- c(out, sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#e5e7eb"/><text x="%d" y="%.1f" text-anchor="end" font-size="%d" fill="#6b7280">%s</text>',
                          pl, w - pr, sy(yt), sy(yt), pl - 5, sy(yt) + 4, fonte_px - 1, fmt_eixo(yt)))
    mx <- marcas_x(xr[1], xr[2])
    if (length(mx$x)) out <- c(out, sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="#d1d5db"/><text x="%.1f" y="%d" text-anchor="middle" font-size="%d" fill="#6b7280">%s</text>',
                                            sx(mx$x), sx(mx$x), h - pb, h - pb + 4, sx(mx$x), h - 7, fonte_px - 1, mx$lab))
  }
  # faixas de incerteza
  for (f in faixas) {
    d <- caminho_faixa(sx(f$x), sy(f$lo), sy(f$hi))
    if (nzchar(d)) out <- c(out, sprintf('<path d="%s" fill="%s" fill-opacity="%.2f" stroke="none"/>', d, f$cor, f$opac))
  }
  # linhas horizontais (limiar)
  for (l in hlinhas) {
    if (!is.finite(l$y)) next
    out <- c(out, sprintf('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="%s" stroke-dasharray="%s"/>',
                          pl, w - pr, sy(l$y), sy(l$y), l$cor, if (mini) "1.2" else "1.6", l$dash))
    if (!mini && !is.null(l$rot)) out <- c(out, sprintf('<text x="%d" y="%.1f" text-anchor="start" font-size="%d" fill="%s" font-weight="600">%s</text>',
                                                         pl + 4, sy(l$y) - 4, fonte_px - 1, l$cor, esc(l$rot)))
  }
  # linhas verticais (última semana completa, corte)
  for (v in vlinhas) {
    out <- c(out, sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="%s" stroke-dasharray="3,3"/>', sx(v$x), sx(v$x), pt - (if (mini) 0 else 10), h - pb, v$cor))
    if (!mini && !is.null(v$rot)) out <- c(out, sprintf('<text x="%.1f" y="%d" text-anchor="%s" font-size="%d" fill="#374151">%s</text>',
                                                         sx(v$x) + if (isTRUE(v$esq)) -3 else 3, pt - 12, if (isTRUE(v$esq)) "end" else "start", fonte_px - 1, esc(v$rot)))
  }
  # séries
  for (s in series) {
    px <- sx(s$x); py <- sy(s$y); cl <- caminho_linha(px, py)
    if (!nzchar(cl$d)) next
    dash <- if (!is.null(s$dash) && nzchar(s$dash)) sprintf(' stroke-dasharray="%s"', s$dash) else ""
    out <- c(out, sprintf('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round"%s/>', cl$d, s$cor, s$larg, dash))
    pts <- if (isTRUE(s$pontos)) which(is.finite(px) & is.finite(py)) else cl$isol
    if (length(pts)) out <- c(out, sprintf('<circle cx="%.1f" cy="%.1f" r="%s" fill="%s"/>', px[pts], py[pts], if (mini) "1.6" else "2.6", s$cor))
  }
  # dicas por semana
  if (!mini && !is.null(dicas) && nrow(dicas)) {
    larg <- max(2, 7 / diff(xr) * (w - pl - pr))
    out <- c(out, sprintf('<g class="dicas" stroke="transparent" stroke-width="%.1f">%s</g>', larg,
                          paste(sprintf('<path d="M%.1f %dV%d" data-tip="%s"/>', sx(dicas$x), pt, h - pb, esc(dicas$txt)), collapse = "")))
  }
  svg <- sprintf('<svg viewBox="0 0 %d %d" role="img" aria-label="%s"><title>%s</title>%s</svg>', w, h, esc(titulo), esc(titulo), paste(out, collapse = ""))
  if (mini) return(svg)
  # legenda
  leg <- c(
    vapply(Filter(function(s) !isFALSE(s$leg), series), function(s) sprintf(
      '<span class="leg-item"><svg width="24" height="10" aria-hidden="true"><line x1="0" x2="24" y1="5" y2="5" stroke="%s" stroke-width="%s"%s/></svg>%s</span>',
      s$cor, s$larg, if (!is.null(s$dash) && nzchar(s$dash)) sprintf(' stroke-dasharray="%s"', s$dash) else "", esc(s$nome)), ""),
    vapply(Filter(function(f) !isFALSE(f$leg), faixas), function(f) sprintf(
      '<span class="leg-item"><svg width="16" height="12" aria-hidden="true"><rect width="16" height="12" fill="%s" fill-opacity="%.2f"/></svg>%s</span>',
      f$cor, f$opac, esc(f$nome)), ""),
    vapply(Filter(function(l) !is.null(l$leg), hlinhas), function(l) sprintf(
      '<span class="leg-item"><svg width="24" height="10" aria-hidden="true"><line x1="0" x2="24" y1="5" y2="5" stroke="%s" stroke-width="1.6" stroke-dasharray="%s"/></svg>%s</span>',
      l$cor, l$dash, esc(l$leg)), ""))
  sprintf('<figure class="grafico-prev"><div class="dica-rolar" aria-hidden="true">&#8596; Deslize o gráfico para o lado para ver todo o período.</div><div class="rolar-svg">%s</div><figcaption class="legenda-svg">%s</figcaption></figure>', svg, paste(leg, collapse = ""))
}

# ---- 3. Situação agora ----------------------------------------------------------------------------------
COR_OBS <- "#0E5A5E"; COR_PREV <- "#2E86AB"; COR_PARC <- "#6b7280"; COR_LIM <- "#b45309"
INI_DET <- as.Date("2024-12-29")   # início da SE 1/2025: janela do gráfico detalhado
INI_MINI <- as.Date("2025-12-28")  # início da SE 1/2026: janela dos minigráficos

# Dados de uma série (região ou MT; todas as idades ou menores de 5) para os gráficos e quadros
dados_serie <- function(cod, alvo = "j00_j99", ini = INI_DET) {
  ob <- SERIE_HOJ[SERIE_HOJ$cod_regiao == cod & SERIE_HOJ$alvo == alvo & SERIE_HOJ$inicio_se >= ini, ] |> arrange(inicio_se)
  nc <- NOW_HOJ[NOW_HOJ$cod_regiao == cod & NOW_HOJ$alvo == alvo & NOW_HOJ$metodo == "ml", ] |> arrange(inicio_se)
  pv <- PREV_HOJ[PREV_HOJ$cod_regiao == cod & PREV_HOJ$alvo == alvo & PREV_HOJ$metodo == "encadeado_ml", ] |> arrange(inicio_se)
  pv$st <- status_cod(pv$status)
  lim <- unique(pv$limiar_p90); lim <- if (length(lim)) lim[1] else NA_real_
  list(ob = ob, nc = nc, pv = pv, lim = lim)
}

# Situação nas 4 semanas: a mais alta entre elas (e quantas semanas em cada)
situacao_4sem <- function(pv) {
  if (!nrow(pv)) return(list(cod = "copia", n = 0L))
  sev <- STATUS_SEV[pv$st]; k <- which.max(sev)
  list(cod = pv$st[k], n = sum(pv$st == pv$st[k]))
}

grafico_serie <- function(cod, alvo = "j00_j99", mini = FALSE) {
  ds <- dados_serie(cod, alvo, if (mini) INI_MINI else INI_DET)
  ob <- ds$ob; nc <- ds$nc; pv <- ds$pv; lim <- ds$lim
  if (!nrow(pv)) return("")
  mid <- function(d) d + 3
  # continuidade: o nowcast parte da última semana completa e a previsão, da última semana com nowcast
  ult_ob <- tail(ob[!is.na(ob$internacoes), ], 1); ult_nc <- tail(nc, 1)
  x_nc <- c(if (nrow(ult_ob) && tail(ob$inicio_se, 1) == ult_ob$inicio_se) mid(ult_ob$inicio_se), mid(nc$inicio_se))
  y_nc <- c(if (nrow(ult_ob) && tail(ob$inicio_se, 1) == ult_ob$inicio_se) ult_ob$internacoes, nc$y_nowcast)
  x_pv <- c(mid(ult_nc$inicio_se), mid(pv$inicio_se)); y_pv <- c(ult_nc$y_nowcast, pv$y_previsto)
  fx_pv <- c(mid(ult_nc$inicio_se), mid(pv$inicio_se))
  nome <- nome_reg_prev(cod)
  b1 <- min(nc$inicio_se); b2 <- min(pv$inicio_se); xfim <- max(pv$fim_se) + 1
  xini <- if (mini) INI_MINI else INI_DET
  series <- list(
    list(nome = "Internações (semanas completas)", x = mid(ob$inicio_se), y = ob$internacoes, cor = COR_OBS, larg = if (mini) 1.4 else 2),
    list(nome = "Já processado no SIH (incompleto)", x = mid(nc$inicio_se), y = nc$parcial_processado, cor = COR_PARC, larg = if (mini) 1 else 1.4, dash = "2,3", leg = !mini),
    list(nome = "Nowcast (estimativa das semanas incompletas)", x = x_nc, y = y_nc, cor = COR_PREV, larg = if (mini) 1.4 else 2, dash = "5,3"),
    list(nome = "Previsão das próximas 4 semanas", x = x_pv, y = y_pv, cor = COR_PREV, larg = if (mini) 1.8 else 2.6, pontos = !mini))
  if (mini) series[[2]] <- NULL
  faixas <- list(
    list(nome = "Intervalo de 80% (nowcast e previsão)", x = c(mid(nc$inicio_se), fx_pv), lo = c(nc$lo80, ult_nc$lo80, pv$lo80),
         hi = c(nc$hi80, ult_nc$hi80, pv$hi80), cor = COR_PREV, opac = 0.22))
  if (!mini) faixas <- c(list(list(nome = "Intervalo de 95% (previsão)", x = mid(pv$inicio_se), lo = pv$lo95, hi = pv$hi95, cor = COR_PREV, opac = 0.10)), faixas)
  hl <- list(list(y = lim, cor = COR_LIM, dash = "6,4", rot = if (is.finite(lim)) paste0("limiar P90: ", num(lim, 1)) else NULL,
                  leg = "Limiar de alta pressão (P90 de 2022–2023)"))
  zonas <- list(list(x0 = b1, x1 = b2, cor = "#f3f4f6", rot = if (!mini) "nowcast"), list(x0 = b2, x1 = xfim, cor = "#e3eef6", rot = if (!mini) "previsão", fim = TRUE))
  vl <- if (mini) list() else list(list(x = b1, rot = paste0("última semana completa (", ULT_COMPL, ")"), cor = "#6b7280", esq = TRUE),
                                   list(x = b2, rot = paste0("hoje (", dm(CORTE), ")"), cor = "#374151", esq = TRUE))
  ymax <- max(c(ob$internacoes, nc$hi80, nc$parcial_processado, pv$hi80, if (!mini) pv$hi95, lim), na.rm = TRUE)
  titulo <- sprintf("Internações respiratórias (J00–J99) por semana, %s, %s: observado, nowcast e previsão (corte de %s)",
                    ALVOS[[alvo]], nome, dmy(CORTE))
  dicas <- NULL
  if (!mini) {
    d_ob <- tibble::tibble(x = mid(ob$inicio_se), txt = sprintf("%s (%s): %s internações", se_txt(ob$se, ob$ano_se), periodo_se(ob$inicio_se, ob$fim_se), fmt_obs(ob$internacoes)))
    d_nc <- tibble::tibble(x = mid(nc$inicio_se), txt = sprintf("%s (%s): nowcast %s (80%%: %s) · já processado: %s",
      se_txt(nc$se, nc$ano_se), periodo_se(nc$inicio_se, nc$fim_se), ifelse(is.na(nc$y_nowcast), "suprimido", fmt_est(nc$y_nowcast)),
      ifelse(is.na(nc$y_nowcast), "—", fmt_int_est(nc$lo80, nc$hi80)), fmt_obs(nc$parcial_processado)))
    d_pv <- tibble::tibble(x = mid(pv$inicio_se), txt = sprintf("%s (%s): previsão %s (80%%: %s; 95%%: %s) · %s",
      se_txt(pv$se, pv$ano_se), periodo_se(pv$inicio_se, pv$fim_se), fmt_est(pv$y_previsto), fmt_int_est(pv$lo80, pv$hi80),
      fmt_int_est(pv$lo95, pv$hi95), sub("^[^ ]+ ", "", STATUS_ROT[pv$st])))
    dicas <- rbind(d_ob, d_nc, d_pv)
  }
  svg_tempo(series, faixas, hl, vl, zonas, dicas, titulo = titulo, w = if (mini) 260 else 760, h = if (mini) 78 else 300,
            xlim = c(xini, xfim), ymax = ymax, mini = mini)
}

# Quadro das 4 semanas previstas de uma série
quadro_4sem <- function(cod, alvo = "j00_j99") {
  pv <- dados_serie(cod, alvo)$pv
  if (!nrow(pv)) return(NULL)
  linhas <- sprintf('<tr><td>%s</td><td>%s</td><td><b>%s</b></td><td>%s</td><td>%s</td><td>%s</td></tr>',
                    se_txt(pv$se, pv$ano_se), periodo_se(pv$inicio_se, pv$fim_se), est_h(pv$y_previsto),
                    int_h(pv$lo80, pv$hi80), int_h(pv$lo95, pv$hi95), selo_status(pv$st))
  div(class = "rolagem-x", HTML(sprintf(paste0('<table class="tab-prev"><caption class="visually-hidden">Previsão das próximas 4 semanas — %s, %s</caption>',
    '<thead><tr><th>Semana</th><th>Período</th><th>Previsão</th><th>Intervalo de 80%%</th><th>Intervalo de 95%%</th><th>Situação</th></tr></thead><tbody>%s</tbody></table>'),
    esc(nome_reg_prev(cod)), ALVOS[[alvo]], paste(linhas, collapse = ""))))
}

# Bloco de detalhe (gráfico + quadro + notas) de uma série
detalhe_serie <- function(cod, alvo = "j00_j99", visivel = FALSE) {
  ds <- dados_serie(cod, alvo); pv <- ds$pv; nc <- ds$nc; sit <- situacao_4sem(pv)
  nc_ult <- tail(nc, 1)
  div(class = "prev-det", `data-reg` = cod, hidden = if (!visivel) NA else NULL,
      h4(sprintf("%s — %s", nome_reg_prev(cod), ALVOS[[alvo]])),
      p(HTML(sprintf("Situação nas próximas 4 semanas: %s%s. Limiar de alta pressão: <b>%s</b> internações por semana (percentil 90 das 104 semanas de 2022–2023).",
                     selo_status(sit$cod), if (sit$cod %in% c("alta", "possivel", "abaixo")) sprintf(" (%d de 4 semanas)", sit$n) else "",
                     fmt_lim(ds$lim)))),
      HTML(grafico_serie(cod, alvo)),
      quadro_4sem(cod, alvo),
      p(class = "nota-fonte", HTML(sprintf(paste0(
        "<i>Nowcast</i> das %s a %s (%s semanas ainda incompletas no SIH): na semana do corte (%s), %s; ",
        "contagem já processada no SIH: %s. Os valores de cada semana podem ser consultados ao passar o cursor sobre o gráfico (ou ao tocá-lo)."),
        se_txt(min(nc$se), ANO_CORTE), se_txt(max(nc$se), ANO_CORTE), nrow(nc), se_txt(nc_ult$se, nc_ult$ano_se),
        if (is.na(nc_ult$y_nowcast)) "estimativa suprimida (contagem pequena na região)" else
          sprintf("estimativa de %s (intervalo de 80%%: %s)", est_h(nc_ult$y_nowcast), int_h(nc_ult$lo80, nc_ult$hi80)),
        fmt_obs(nc_ult$parcial_processado)))))
}

# Minicartão de uma série (todas as idades)
cartao_serie <- function(cod, alvo = "j00_j99") {
  pv <- dados_serie(cod, alvo)$pv; sit <- situacao_4sem(pv); lim <- unique(pv$limiar_p90)[1]
  p1 <- pv[1, ]; p4 <- pv[nrow(pv), ]
  tags$button(type = "button", class = "prev-card", `data-reg` = cod, `aria-pressed` = if (cod == "MT") "true" else "false",
              `aria-label` = sprintf("%s: %s. Ver o gráfico detalhado", nome_reg_prev(cod), sub("^[^ ]+ ", "", STATUS_ROT[sit$cod])),
              span(class = "pc-topo", span(class = "pc-nome", nome_reg_prev(cod)), HTML(selo_status(sit$cod))),
              HTML(grafico_serie(cod, alvo, mini = TRUE)),
              span(class = "pc-num", HTML(sprintf("%s: <b>%s</b> (%s) · %s: <b>%s</b>", se_txt(p1$se, p1$ano_se), est_h(p1$y_previsto),
                                                  int_h(p1$lo80, p1$hi80), paste0("SE ", p4$se), est_h(p4$y_previsto)))),
              span(class = "pc-sub", sprintf("limiar P90: %s internações/semana", fmt_lim(lim))))
}

# Seletor + detalhes (todas as idades) + grade de minicartões, com o script que os liga
painel_situacao <- function() {
  cods <- REG_PREV$cod_regiao
  js <- "(function(){var s=document.getElementById('prev-reg');if(!s)return;
function mostrar(c){document.querySelectorAll('#prev-detalhe .prev-det').forEach(function(d){d.hidden=d.getAttribute('data-reg')!==c;});
document.querySelectorAll('.prev-card').forEach(function(b){b.setAttribute('aria-pressed',b.getAttribute('data-reg')===c?'true':'false');});}
s.addEventListener('change',function(){mostrar(s.value);});
document.querySelectorAll('.prev-card').forEach(function(b){b.addEventListener('click',function(){s.value=b.getAttribute('data-reg');mostrar(s.value);
var a=document.getElementById('prev-detalhe');if(a&&a.scrollIntoView)a.scrollIntoView({behavior:'smooth',block:'start'});});});
mostrar(s.value);})();
(function(){function fim(raiz){(raiz||document).querySelectorAll('.rolar-svg').forEach(function(r){if(r.scrollWidth>r.clientWidth)r.scrollLeft=r.scrollWidth;});}
var s=document.getElementById('prev-reg');if(s)s.addEventListener('change',function(){fim(document.getElementById('prev-detalhe'));});
document.querySelectorAll('.prev-card').forEach(function(b){b.addEventListener('click',function(){fim(document.getElementById('prev-detalhe'));});});
document.addEventListener('shown.bs.tab',function(){fim(document);});
fim(document);window.addEventListener('load',function(){fim(document);});})();"
  tagList(
    div(class = "prev-sel", tags$label(`for` = "prev-reg", "Região de saúde:"),
        tags$select(id = "prev-reg", class = "form-select", `aria-controls` = "prev-detalhe",
                    lapply(cods, function(c) tags$option(value = c, selected = if (c == "MT") NA else NULL,
                                                         if (c == "MT") "Mato Grosso (soma das 16 regiões)" else nome_reg_prev(c))))),
    div(id = "prev-detalhe", lapply(cods, function(c) detalhe_serie(c, "j00_j99", visivel = c == "MT"))),
    h4("Todas as regiões de saúde — próximas 4 semanas"),
    p(class = "nota-fonte", HTML("Ao tocar ou clicar em um cartão, abre-se o gráfico detalhado da região. Nos minigráficos, desde a SE 1/2026, a linha contínua escura representa as semanas completas; a tracejada, o <i>nowcast</i>; a faixa, o intervalo de 80%; e a linha laranja tracejada, o limiar de alta pressão.")),
    div(class = "prev-cards", lapply(cods, cartao_serie)),
    tags$script(HTML(js)))
}

# Quadro-resumo por região (reactable): previsões das 4 semanas, limiar e situação
tabela_situacao <- function(alvo = "j00_j99") {
  d <- PREV_HOJ[PREV_HOJ$alvo == alvo & PREV_HOJ$metodo == "encadeado_ml", ] |> arrange(se)
  d$st <- status_cod(d$status)
  ses <- sort(unique(d$se))
  linhas <- lapply(REG_PREV$cod_regiao, function(c) {
    x <- d[d$cod_regiao == c, ]; sit <- situacao_4sem(x)
    r <- tibble::tibble(Região = nome_reg_prev(c), mt = c == "MT",
                        Situação = sprintf("%s%s", selo_status(sit$cod), if (sit$cod %in% c("alta", "possivel", "abaixo")) sprintf('<div class="sub">%d de 4 semanas</div>', sit$n) else ""),
                        Limiar = fmt_lim(x$limiar_p90[1]))
    for (s in ses) { y <- x[x$se == s, ]
      r[[paste0("SE", s)]] <- if (nrow(y)) sprintf('<b>%s</b><div class="sub">%s</div>', est_h(y$y_previsto), int_h(y$lo80, y$hi80)) else "—" }
    r
  })
  t <- bind_rows(linhas)
  cols <- list(mt = colDef(show = FALSE),
               Região = colDef(minWidth = 160, sticky = "left", style = function(v, i) if (t$mt[i]) list(fontWeight = 700) else NULL),
               Situação = colDef(name = "Situação nas 4 semanas", html = TRUE, minWidth = 150),
               Limiar = colDef(name = "Limiar P90 (intern./semana)", align = "right", minWidth = 95))
  for (s in ses) { y <- d[d$se == s, ][1, ]
    cols[[paste0("SE", s)]] <- colDef(name = sprintf("SE %d (%s)", s, periodo_se(y$inicio_se, y$fim_se)), html = TRUE, align = "right", minWidth = 105) }
  reactable(t, columns = cols, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE, wrap = TRUE)
}

# ---- 4. Quão bem os modelos acertam ---------------------------------------------------------------------
metr <- function(mod, nivel = NIV_REG, h = 0L, otica = "ocorrencia", col = "mase") {
  v <- MET_RES[[col]][MET_RES$modelo == mod & MET_RES$nivel == nivel & MET_RES$h == h & MET_RES$otica == otica]
  if (length(v)) v[1] else NA_real_
}
melhor_modelo <- function(nivel = NIV_REG, otica = "ocorrencia", h = 0L) {
  x <- MET_RES[MET_RES$nivel == nivel & MET_RES$otica == otica & MET_RES$h == h, ]; x$modelo[which.min(x$mase)]
}

# Célula do modelo (nome, selo da referência e família)
cel_modelo <- function(m) sprintf('<b>%s</b>%s<div class="sub">%s</div>', esc(rot_mod(m)),
                                  ifelse(m == MOD_REF, ' <span class="selo-ref">★ referência</span>', ""), esc(FAM_MOD[m]))

# Barras do MASE médio (h = 1 a 4) dos modelos principais em um nível
barras_mase <- function(nivel = NIV_REG) {
  x <- MET_RES[MET_RES$otica == "ocorrencia" & MET_RES$nivel == nivel & MET_RES$h == 0 & MET_RES$modelo %in% MODS_PRINC, ] |> arrange(mase)
  HTML(svg_barras_h(rot_mod(x$modelo), x$mase, "dec2",
                    titulo = sprintf("MASE médio das previsões de 1 a 4 semanas — %s", if (nivel == NIV_REG) "média das 16 regiões de saúde" else "Mato Grosso"),
                    cor = ifelse(x$modelo == MOD_REF, COR_OBS, COR_PREV), refs = list(list(v = 1, cor = "#6b7280", rot = "MASE = 1")),
                    w = 460, pl = 170, pr = 44, dicas = sprintf("%s: MASE %s (MAE %s internações/semana)", rot_mod(x$modelo), dec2(x$mase), dec1(x$mae))))
}

# Tabela de erro por modelo e horizonte (nível: regiões ou MT)
tabela_erro <- function(nivel = NIV_REG) {
  x <- MET_RES[MET_RES$otica == "ocorrencia" & MET_RES$nivel == nivel, ]
  mods <- unique(x$modelo)
  t <- bind_rows(lapply(mods, function(m) { y <- x[x$modelo == m, ]; g <- function(h, col = "mase") { v <- y[[col]][y$h == h]; if (length(v)) v[1] else NA_real_ }
    tibble::tibble(modelo = m, Modelo = cel_modelo(m), h1 = g(1), h2 = g(2), h3 = g(3), h4 = g(4), mase = g(0),
                   mae = g(0, "mae"), mae1 = g(1, "mae"), mae4 = g(4, "mae"), rmse = g(0, "rmse"), rmae = g(0, "rmae_geo"),
                   n_reg = g(0, "regioes_melhor_que_ingenuo"), vies = g(0, "vies")) })) |> arrange(mase)
  t$rmae <- dec2(t$rmae)  # razão (1 = ingênuo sazonal) como texto, para não haver inteiros soltos nos dados embutidos
  num_col <- function(nome, f = dec2, ...) colDef(name = nome, align = "right", cell = function(v) f(v), ...)
  cols <- list(modelo = colDef(show = FALSE), Modelo = colDef(html = TRUE, minWidth = 190, sticky = "left"),
               h1 = num_col("MASE 1 sem."), h2 = num_col("MASE 2 sem."), h3 = num_col("MASE 3 sem."), h4 = num_col("MASE 4 sem."),
               mase = colDef(name = "MASE 1 a 4 (média)", align = "right", cell = function(v) dec2(v), style = list(fontWeight = 700)),
               mae = num_col("MAE 1 a 4 (intern./sem.)", dec1), mae1 = num_col("MAE 1 sem.", dec1), mae4 = num_col("MAE 4 sem.", dec1),
               rmse = num_col("RMSE 1 a 4", dec1), rmae = colDef(name = "rMAE 1 a 4 (÷ ingênuo sazonal)", align = "right"),
               n_reg = colDef(name = "Regiões com rMAE < 1", align = "right", cell = function(v) ifelse(is.na(v), "—", num(v, 0))),
               vies = num_col("Viés 1 a 4 (intern./sem.)", dec1))
  if (nivel == NIV_MT) { t$n_reg <- NULL; cols$n_reg <- NULL } else { t$mae1 <- NULL; t$mae4 <- NULL; cols$mae1 <- NULL; cols$mae4 <- NULL }
  reactable(t, columns = cols, compact = TRUE, striped = TRUE, pagination = FALSE, wrap = TRUE, defaultSortOrder = "asc",
            rowStyle = function(i) if (t$modelo[i] == MOD_REF) list(background = "#f1f8f8") else NULL)
}

# Horizontes exploratórios (13 e 26 semanas)
tabela_exploratoria <- function() {
  x <- MET_RES[MET_RES$otica == "ocorrencia" & MET_RES$h %in% c(13, 26), ]
  mods <- unique(x$modelo)
  g <- function(m, nv, h, col = "mase") { v <- x[[col]][x$modelo == m & x$nivel == nv & x$h == h]; if (length(v)) v[1] else NA_real_ }
  t <- tibble::tibble(modelo = mods, Modelo = cel_modelo(mods),
                      mt13 = sapply(mods, g, nv = NIV_MT, h = 13), mt26 = sapply(mods, g, nv = NIV_MT, h = 26),
                      r13 = sapply(mods, g, nv = NIV_REG, h = 13), r26 = sapply(mods, g, nv = NIV_REG, h = 26),
                      q13 = sapply(mods, g, nv = NIV_REG, h = 13, col = "rmae_geo"), q26 = sapply(mods, g, nv = NIV_REG, h = 26, col = "rmae_geo")) |>
    arrange(r13)
  t$q13 <- dec2(t$q13); t$q26 <- dec2(t$q26)
  cc <- function(nome) colDef(name = nome, align = "right", cell = function(v) dec2(v))
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
            columns = list(modelo = colDef(show = FALSE), Modelo = colDef(html = TRUE, minWidth = 190, sticky = "left"),
                           mt13 = cc("MASE MT, 13 sem."), mt26 = cc("MASE MT, 26 sem."), r13 = cc("MASE regiões, 13 sem."),
                           r26 = cc("MASE regiões, 26 sem."), q13 = colDef(name = "rMAE regiões, 13 sem.", align = "right"),
                           q26 = colDef(name = "rMAE regiões, 26 sem.", align = "right")))
}

# MASE por região de saúde e modelo (média dos horizontes 1 a 4); ★ = menor MASE na região
tabela_regioes_mase <- function() {
  x <- MET_REG[MET_REG$otica == "ocorrencia", ]
  mods <- intersect(c("lgbm", "hgb", "rf", "mlp", "sarima", "ingenuo_ultima", "ingenuo_sazonal"), unique(x$modelo))
  regs <- REG_PREV$cod_regiao[REG_PREV$cod_regiao != "MT"]
  t <- bind_rows(lapply(regs, function(c) { y <- x[x$cod_regiao == c, ]
    r <- tibble::tibble(Região = nome_reg_prev(c), melhor = rot_mod(y$modelo[y$melhor_mase_na_regiao][1]))
    for (m in mods) { z <- y[y$modelo == m, ]
      r[[m]] <- if (nrow(z)) sprintf("%s%s", if (z$melhor_mase_na_regiao) "<b>★ " else "", paste0(dec2(z$mase), if (z$melhor_mase_na_regiao) "</b>" else "")) else "—" }
    r }))
  cols <- c(list(Região = colDef(minWidth = 170, sticky = "left"), melhor = colDef(name = "Menor MASE", minWidth = 130)),
            setNames(lapply(mods, function(m) colDef(name = rot_mod(m), html = TRUE, align = "right", minWidth = 92)), mods))
  reactable(t, columns = cols, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE)
}

# Validação em Mato Grosso: observado × previsto com 1 e 4 semanas (um gráfico por modelo, com seletor)
grafico_validacao <- function(m) {
  x <- ROLL_MT[ROLL_MT$otica == "ocorrencia" & ROLL_MT$modelo == m, ]
  h1 <- x[x$h == 1, ] |> arrange(inicio_se_alvo); h4 <- x[x$h == 4, ] |> arrange(inicio_se_alvo)
  ob <- h1[, c("inicio_se_alvo", "ano_se_alvo", "se_alvo", "y_obs")]
  dd <- left_join(ob, select(h1, inicio_se_alvo, p1 = y_prev), by = "inicio_se_alvo") |> left_join(select(h4, inicio_se_alvo, p4 = y_prev), by = "inicio_se_alvo")
  svg_tempo(series = list(
    list(nome = "Observado", x = ob$inicio_se_alvo + 3, y = ob$y_obs, cor = COR_OBS, larg = 2.2),
    list(nome = paste0(rot_mod(m), ": 1 semana à frente"), x = h1$inicio_se_alvo + 3, y = h1$y_prev, cor = COR_PREV, larg = 1.6),
    list(nome = paste0(rot_mod(m), ": 4 semanas à frente"), x = h4$inicio_se_alvo + 3, y = h4$y_prev, cor = COR_LIM, larg = 1.6, dash = "5,3")),
    dicas = tibble::tibble(x = dd$inicio_se_alvo + 3, txt = sprintf("%s: observado %s · 1 sem.: %s · 4 sem.: %s",
                                                                    se_txt(dd$se_alvo, dd$ano_se_alvo), fmt_obs(dd$y_obs), fmt_est(dd$p1), fmt_est(dd$p4))),
    titulo = sprintf("Validação em Mato Grosso: internações observadas e previstas pelo modelo %s com 1 e 4 semanas de antecedência", rot_mod(m)), h = 280)
}
painel_validacao <- function() {
  mods <- c(MOD_REF, setdiff(MODS_PRINC, MOD_REF))
  js <- "(function(){var s=document.getElementById('val-mod');if(!s)return;s.addEventListener('change',function(){document.querySelectorAll('#val-graf > [data-mod]').forEach(function(d){d.hidden=d.getAttribute('data-mod')!==s.value;});});})();"
  tagList(div(class = "prev-sel", tags$label(`for` = "val-mod", "Modelo:"),
              tags$select(id = "val-mod", class = "form-select", `aria-controls` = "val-graf",
                          lapply(mods, function(m) tags$option(value = m, rot_mod(m))))),
          div(id = "val-graf", lapply(mods, function(m) div(`data-mod` = m, hidden = if (m != MOD_REF) NA else NULL, HTML(grafico_validacao(m))))),
          tags$script(HTML(js)))
}

# Série longa de Mato Grosso (2020 a 2026), com a quebra da COVID-19
grafico_historico <- function() {
  s <- SERIE_OBS[SERIE_OBS$otica == "ocorrencia" & SERIE_OBS$cod_regiao == "MT", ] |> arrange(inicio_se)
  svg_tempo(series = list(list(nome = "Internações J00–J99 por semana, Mato Grosso", x = s$inicio_se + 3, y = s$internacoes_j00_j99, cor = COR_OBS, larg = 1.6)),
            zonas = list(list(x0 = min(s$inicio_se), x1 = as.Date("2022-01-02"), cor = "#f3f4f6", rot = "2020–2021: pandemia")),
            dicas = tibble::tibble(x = s$inicio_se + 3, txt = sprintf("%s (%s): %s internações", se_txt(s$se, s$ano_se), periodo_se(s$inicio_se, s$fim_se), fmt_obs(s$internacoes_j00_j99))),
            titulo = sprintf("Internações por doenças respiratórias (J00–J99) por semana epidemiológica, Mato Grosso, SE 1/2020 a SE %s", ULT_BASE), h = 250)
}

# Testes de Diebold-Mariano em linguagem simples
dm_frase <- function(estat, p, a, b, limiar_limitrofe = 0.10) {
  ifelse(is.na(p), "—",
  ifelse(p < 0.05, sprintf("%s erra menos (%s)", ifelse(estat < 0, a, b), p_txt(p)),
  ifelse(p < limiar_limitrofe, sprintf("limítrofe (%s), a favor de %s", p_txt(p), ifelse(estat < 0, a, b)),
         sprintf("sem diferença clara (%s)", p_txt(p)))))
}
dm_linha <- function(a, b, nivel, h) {
  x <- DM_BASE[DM_BASE$otica == "ocorrencia" & DM_BASE$modelo_a == a & DM_BASE$modelo_b == b & DM_BASE$nivel == nivel & DM_BASE$h == h, ]
  if (!nrow(x)) return(NA_character_)
  dm_frase(x$estat_hln[1], x$p_valor[1], rot_mod(a), rot_mod(b))
}
# Frase "A × B — nas 16 regiões: ... ; em MT: ..."
dm_resumo <- function(a, b) {
  f <- function(nv) esc(sprintf("com 1 semana, %s; com 4 semanas, %s", dm_linha(a, b, nv, 1), dm_linha(a, b, nv, 4)))
  sprintf("<b>%s × %s</b> — nas 16 regiões: %s. Em Mato Grosso: %s.", esc(rot_mod(a)), esc(rot_mod(b)), f("16 regioes"), f("MT"))
}
tabela_dm <- function() {
  x <- DM_BASE[DM_BASE$otica == "ocorrencia" & DM_BASE$h %in% c(1, 4), ]
  pares <- unique(x[, c("modelo_a", "modelo_b")])
  t <- bind_rows(lapply(seq_len(nrow(pares)), function(i) { a <- pares$modelo_a[i]; b <- pares$modelo_b[i]
    bind_rows(lapply(c("16 regioes", "MT"), function(nv) tibble::tibble(
      Comparação = sprintf("%s × %s", rot_mod(a), rot_mod(b)), Onde = if (nv == "MT") "Mato Grosso" else "16 regiões (média)",
      h1 = dm_linha(a, b, nv, 1), h4 = dm_linha(a, b, nv, 4)))) }))
  reactable(t, compact = TRUE, striped = TRUE, searchable = TRUE, defaultPageSize = 10, showPageSizeOptions = TRUE, pageSizeOptions = c(10, 20, 40),
            columns = list(Comparação = colDef(minWidth = 220), Onde = colDef(minWidth = 110),
                           h1 = colDef(name = "1 semana à frente", minWidth = 200), h4 = colDef(name = "4 semanas à frente", minWidth = 200)))
}
# Testes da previsão encadeada (cenário S2): p robusto (Newey-West) e ajustado por Holm
dm_enc_linha <- function(a, b, nivel, h, alvo = "j00_j99") {
  x <- DM_ENC[DM_ENC$cenario == "S2" & DM_ENC$alvo == alvo & DM_ENC$modelo_a == a & DM_ENC$modelo_b == b & DM_ENC$nivel == nivel & DM_ENC$h == h, ]
  if (!nrow(x)) return(NA_character_)
  paste0(dm_frase(x$estat_hln_nw[1], x$p_valor_nw[1], rot_enc(a), rot_enc(b)), "; após ajuste de Holm, ", p_txt(x$p_holm_nw[1]))
}
tabela_dm_enc <- function(alvo = "j00_j99") {
  x <- DM_ENC[DM_ENC$cenario == "S2" & DM_ENC$alvo == alvo & DM_ENC$h %in% c(1, 4), ]
  pares <- unique(x[, c("modelo_a", "modelo_b")])
  t <- bind_rows(lapply(seq_len(nrow(pares)), function(i) { a <- pares$modelo_a[i]; b <- pares$modelo_b[i]
    bind_rows(lapply(c("16 regioes", "MT"), function(nv) tibble::tibble(
      Comparação = sprintf("%s × %s", rot_enc(a), rot_enc(b)), Onde = if (nv == "MT") "Mato Grosso" else "16 regiões (média)",
      h1 = dm_enc_linha(a, b, nv, 1, alvo), h4 = dm_enc_linha(a, b, nv, 4, alvo)))) }))
  reactable(t, compact = TRUE, striped = TRUE, defaultPageSize = 10, showPageSizeOptions = TRUE, pageSizeOptions = c(10, 20),
            columns = list(Comparação = colDef(minWidth = 240), Onde = colDef(minWidth = 110),
                           h1 = colDef(name = "1 semana à frente", minWidth = 240), h4 = colDef(name = "4 semanas à frente", minWidth = 240)))
}

# Cobertura dos intervalos (média ponderada pelo número de previsões nos horizontes 1 a 4)
cobertura_resumo <- function() {
  x <- COB_INT[COB_INT$otica == "ocorrencia" & COB_INT$h %in% 1:4, ]
  x |> group_by(modelo, tipo, nivel) |>
    summarise(c80 = sum(cobertura80 * n) / sum(n), c95 = sum(cobertura95 * n) / sum(n), l80 = sum(largura80 * n) / sum(n), .groups = "drop")
}
tabela_cobertura <- function() {
  x <- cobertura_resumo()
  chaves <- unique(x[, c("modelo", "tipo")])
  t <- bind_rows(lapply(seq_len(nrow(chaves)), function(i) { m <- chaves$modelo[i]; tp <- chaves$tipo[i]
    g <- function(nv, col) { v <- x[[col]][x$modelo == m & x$tipo == tp & x$nivel == nv]; if (length(v)) v[1] else NA_real_ }
    tibble::tibble(modelo = m, Modelo = cel_modelo(m), Tipo = if (tp == "empirico") "empírico" else "paramétrico",
                   r80 = g("16 regioes", "c80"), r95 = g("16 regioes", "c95"), rl = g("16 regioes", "l80"),
                   m80 = g("MT", "c80"), m95 = g("MT", "c95"), ml = g("MT", "l80")) })) |> arrange(match(modelo, MODS_PRINC), Tipo)
  pc <- function(nome) colDef(name = nome, align = "right", cell = function(v) pct(v, 1))
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
            columns = list(modelo = colDef(show = FALSE), Modelo = colDef(html = TRUE, minWidth = 190, sticky = "left"), Tipo = colDef(minWidth = 95),
                           r80 = pc("Regiões: cobertura 80%"), r95 = pc("Regiões: cobertura 95%"),
                           rl = colDef(name = "Regiões: largura 80% (intern./sem.)", align = "right", cell = function(v) dec1(v)),
                           m80 = pc("MT: cobertura 80%"), m95 = pc("MT: cobertura 95%"),
                           ml = colDef(name = "MT: largura 80% (intern./sem.)", align = "right", cell = function(v) dec1(v))))
}

# Nowcast: MASE por faixa de atraso (cenário S2)
FAIXAS_ATR <- c("0-3", "4-7", "8-11", "12-15", "16-19", "20-23", "24+", "todas")
tabela_nowcast <- function(alvo = "j00_j99") {
  x <- MET_NOW[MET_NOW$cenario == "S2" & MET_NOW$alvo == alvo, ]
  g <- function(f, nv, m) { v <- x$mase[x$faixa_atraso_semanas == f & x$nivel == nv & x$metodo == m]; if (length(v)) v[1] else NA_real_ }
  t <- tibble::tibble(Atraso = ifelse(FAIXAS_ATR == "todas", "Todas", paste(sub("-", " a ", FAIXAS_ATR), "semanas")))
  for (m in c("parcial", "prior", "cl", "bf", "ml", "ml_bf")) t[[m]] <- sapply(FAIXAS_ATR, g, nv = NIV_REG, m = m)
  t$mt_cl <- sapply(FAIXAS_ATR, g, nv = "MT", m = "cl"); t$mt_ml <- sapply(FAIXAS_ATR, g, nv = "MT", m = "ml")
  cc <- function(nome, ...) colDef(name = nome, align = "right", cell = function(v) dec2(v), ...)
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE,
            columns = list(Atraso = colDef(minWidth = 110, sticky = "left"), parcial = cc("Já processado, sem correção"), prior = cc("Ingênuo sazonal ajustado"),
                           cl = cc("Chain-ladder"), bf = cc("Bornhuetter-Ferguson"), ml = cc("LightGBM (principal)", style = list(fontWeight = 700)),
                           ml_bf = cc("LightGBM-BF (post hoc)"), mt_cl = cc("MT: chain-ladder"), mt_ml = cc("MT: LightGBM")))
}

# Previsão encadeada: MASE por horizonte (cenário S2)
ORD_ENC <- c("ref_sem_atraso_lgbm_sem_exog", "baseline_sem_atraso_lgbm", "encadeado_ml", "encadeado_cl", "encadeado_ml_bf",
             "sem_nowcast_lgbm", "ingenuo_sazonal", "ingenuo_sazonal_aj")
tabela_encadeado <- function(alvo = "j00_j99") {
  x <- MET_ENC[MET_ENC$cenario == "S2" & MET_ENC$alvo == alvo, ]
  g <- function(m, nv, h, col = "mase") { v <- x[[col]][x$metodo == m & x$nivel == nv & x$h == h]; if (length(v)) v[1] else NA_real_ }
  ms <- intersect(ORD_ENC, unique(x$metodo))
  t <- tibble::tibble(metodo = ms, Método = rot_enc(ms), r1 = sapply(ms, g, nv = NIV_REG, h = 1), r2 = sapply(ms, g, nv = NIV_REG, h = 2),
                      r3 = sapply(ms, g, nv = NIV_REG, h = 3), r4 = sapply(ms, g, nv = NIV_REG, h = 4), r0 = sapply(ms, g, nv = NIV_REG, h = 0),
                      m0 = sapply(ms, g, nv = "MT", h = 0), mae = sapply(ms, g, nv = "MT", h = 0, col = "mae"), cob = sapply(ms, g, nv = NIV_REG, h = 0, col = "cob80"))
  cc <- function(nome, f = dec2, ...) colDef(name = nome, align = "right", cell = function(v) f(v), ...)
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE,
            rowStyle = function(i) if (t$metodo[i] == "encadeado_ml") list(background = "#f1f8f8", fontWeight = 600) else NULL,
            columns = list(metodo = colDef(show = FALSE), Método = colDef(minWidth = 250, sticky = "left"),
                           r1 = cc("Regiões 1 sem."), r2 = cc("Regiões 2 sem."), r3 = cc("Regiões 3 sem."), r4 = cc("Regiões 4 sem."),
                           r0 = cc("Regiões 1 a 4"), m0 = cc("MT 1 a 4"), mae = cc("MAE MT 1 a 4 (intern./sem.)", dec1),
                           cob = cc("Cobertura 80% (regiões)", function(v) pct(v, 0))))
}

# Menores de 5 anos: erro da previsão sem atraso (todos os modelos)
tabela_menor5 <- function() {
  x <- MET_M5
  g <- function(m, nv, h, col = "mase") { v <- x[[col]][x$modelo == m & x$nivel == nv & x$h == h]; if (length(v)) v[1] else NA_real_ }
  ms <- unique(x$modelo)
  t <- tibble::tibble(modelo = ms, Modelo = cel_modelo(ms), r1 = sapply(ms, g, nv = NIV_REG, h = 1), r4 = sapply(ms, g, nv = NIV_REG, h = 4),
                      r0 = sapply(ms, g, nv = NIV_REG, h = 0), m0 = sapply(ms, g, nv = "MT", h = 0), mae = sapply(ms, g, nv = "MT", h = 0, col = "mae")) |>
    arrange(is.na(r0), r0, m0)
  cc <- function(nome, f = dec2, ...) colDef(name = nome, align = "right", cell = function(v) f(v), ...)
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE,
            rowStyle = function(i) if (t$modelo[i] == MOD_REF) list(background = "#f1f8f8") else NULL,
            columns = list(modelo = colDef(show = FALSE), Modelo = colDef(html = TRUE, minWidth = 190, sticky = "left"),
                           r1 = cc("MASE regiões, 1 sem."), r4 = cc("MASE regiões, 4 sem."), r0 = cc("MASE regiões, 1 a 4", style = list(fontWeight = 700)),
                           m0 = cc("MASE MT, 1 a 4"), mae = cc("MAE MT, 1 a 4 (intern./sem.)", dec1)))
}

# ---- 5. Alerta ------------------------------------------------------------------------------------------
med_alerta <- function(fonte, modelo, alvo = "j00_j99", nivel = "16 regioes", regra = "p90", h = 0L) {
  x <- ALE_MED[ALE_MED$fonte == fonte & ALE_MED$modelo == modelo & ALE_MED$alvo == alvo & ALE_MED$nivel == nivel & ALE_MED$regra == regra & ALE_MED$h == h, ]
  if (nrow(x)) x[1, ] else NULL
}
cel_barra <- function(v, f = pct) sprintf('<span class="barra-cel">%s<i style="width:%dpx" aria-hidden="true"></i></span>', f(v), as.integer(round(60 * pmin(pmax(v, 0), 1))))

# Tabela de classificação do alerta para uma fonte (C = com atraso real; A/B = sem atraso)
tabela_alerta <- function(fonte = "C_encadeado_S2", alvo = "j00_j99", fonte_janela = NULL, ordem = NULL) {
  x <- ALE_MED[ALE_MED$fonte == fonte & ALE_MED$alvo == alvo & ALE_MED$regra == "p90" & ALE_MED$h == 0, ]
  ms <- unique(x$modelo[x$nivel == "16 regioes"])
  if (!is.null(ordem)) ms <- c(intersect(ordem, ms), setdiff(ms, ordem))
  g <- function(m, col, nv = "16 regioes", regra = "p90", fo = fonte) { v <- ALE_MED[[col]][ALE_MED$fonte == fo & ALE_MED$alvo == alvo & ALE_MED$modelo == m &
                                                                                        ALE_MED$nivel == nv & ALE_MED$regra == regra & ALE_MED$h == 0]; if (length(v)) v[1] else NA_real_ }
  t <- tibble::tibble(modelo = ms, Método = rot_enc(ms), sens = sapply(ms, g, col = "sensibilidade"), esp = sapply(ms, g, col = "especificidade"),
                      vpp = sapply(ms, g, col = "vpp"), f1 = sapply(ms, g, col = "f1"), f1mt = sapply(ms, g, col = "f1", nv = "MT"),
                      f1p80 = sapply(ms, g, col = "f1", regra = "p80"),
                      f1jan = if (!is.null(fonte_janela)) sapply(ms, g, col = "f1", fo = fonte_janela) else NA_real_)
  if (is.null(ordem)) t <- arrange(t, desc(f1))
  cols <- list(modelo = colDef(show = FALSE), Método = colDef(minWidth = 230, sticky = "left"),
               sens = colDef(name = "Sensibilidade", html = TRUE, align = "right", minWidth = 120, cell = function(v) cel_barra(v)),
               esp = colDef(name = "Especificidade", align = "right", cell = function(v) pct(v)),
               vpp = colDef(name = "VPP", html = TRUE, align = "right", minWidth = 110, cell = function(v) cel_barra(v)),
               f1 = colDef(name = "F1 (regiões)", html = TRUE, align = "right", minWidth = 110, cell = function(v) cel_barra(v, dec2), style = list(fontWeight = 700)),
               f1mt = colDef(name = "F1 (MT)", align = "right", cell = function(v) dec2(v)),
               f1p80 = colDef(name = "F1 (regiões, regra P80)", align = "right", cell = function(v) dec2(v)),
               f1jan = colDef(name = "F1 (regiões), mesmos cortes de 2024–2025", align = "right", cell = function(v) dec2(v)))
  if (is.null(fonte_janela)) { t$f1jan <- NULL; cols$f1jan <- NULL }
  reactable(t, columns = cols, compact = TRUE, striped = TRUE, pagination = FALSE,
            rowStyle = function(i) if (t$modelo[i] %in% c("encadeado_ml", MOD_REF)) list(background = "#f1f8f8") else NULL)
}

# Antecedência do primeiro aviso (16 regiões, regra P90)
tabela_antecedencia <- function(fontes = c("C_encadeado_S2"), modelos = NULL) {
  x <- ALE_ANT[ALE_ANT$fonte %in% fontes & ALE_ANT$nivel == "16 regioes" & ALE_ANT$regra == "p90", ]
  if (!is.null(modelos)) x <- x[x$modelo %in% modelos, ]
  a1 <- x[x$duracao_minima == 1, ]; a2 <- x[x$duracao_minima == 2, ]
  t <- a1 |> left_join(select(a2, fonte, alvo, modelo, ep2 = episodios, pct2 = pct_antes_inicio), by = c("fonte", "alvo", "modelo")) |>
    transmute(Série = ALVOS[alvo], Fonte = ifelse(grepl("^C_", fonte), "com atraso real", "sem atraso"), Método = rot_enc(modelo),
              ep = episodios, det = detectados / episodios, antes = pct_antes_inicio,
              ant = dec1(antecedencia_media_detectados), ant0 = dec1(antecedencia_media_todos_perdido_0), ep2, pct2)
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, groupBy = c("Série"), defaultExpanded = TRUE,
            columns = list(Série = colDef(minWidth = 130), Fonte = colDef(minWidth = 110), Método = colDef(minWidth = 220),
                           ep = colDef(name = "Episódios", align = "right", cell = function(v) num(v, 0)),
                           det = colDef(name = "Com aviso", align = "right", cell = function(v) pct(v)),
                           antes = colDef(name = "Com aviso antes do início", align = "right", cell = function(v) pct(v)),
                           ant = colDef(name = "Antecedência média dos avisados (semanas)", align = "right"),
                           ant0 = colDef(name = "Antecedência média, perdidos = 0 (semanas)", align = "right"),
                           ep2 = colDef(name = "Episódios de 2 semanas ou mais (post hoc)", align = "right", cell = function(v) num(v, 0)),
                           pct2 = colDef(name = "Com aviso antes do início, 2+ semanas (post hoc)", align = "right", cell = function(v) pct(v))))
}

# Contexto pediátrico: limiar de menores de 5 anos, leitos pediátricos SUS e ocupação equivalente
tabela_pediatrica <- function() {
  x <- CTX_PED
  x <- x[match(REG_PREV$cod_regiao, x$cod_regiao), ]
  # leitos: média mensal do CNES; vazio = nenhum leito registrado (0, como no relatório técnico); abaixo de 5 = "< 5"
  leitos <- function(v) { v[is.na(v)] <- 0; ifelse(v > 0 & v < 4.5, "< 5", num(v, 0)) }
  t <- tibble::tibble(mt = x$cod_regiao == "MT", Região = nome_reg_prev(x$cod_regiao), lim = fmt_lim(x$limiar_p90_menor5),
                      perm = dec1(x$permanencia_media_menor5), lc = leitos(x$leitos_ped_clinicos_sus), lu = leitos(x$leitos_uti_ped_sus),
                      om = ifelse(is.na(x$ocupacao_equiv_media_pct), "—", paste0(num(x$ocupacao_equiv_media_pct, 0), "%")),
                      ol = ifelse(is.na(x$ocupacao_equiv_limiar_pct), "suprimido", paste0(num(x$ocupacao_equiv_limiar_pct, 0), "%")))
  reactable(t, compact = TRUE, striped = TRUE, pagination = FALSE, sortable = FALSE,
            columns = list(mt = colDef(show = FALSE),
                           Região = colDef(minWidth = 170, sticky = "left", style = function(v, i) if (t$mt[i]) list(fontWeight = 700) else NULL),
                           lim = colDef(name = "Limiar P90, menores de 5 (intern./semana)", align = "right"),
                           perm = colDef(name = "Permanência média (dias)", align = "right"),
                           lc = colDef(name = "Leitos pediátricos clínicos SUS", align = "right"),
                           lu = colDef(name = "Leitos de UTI pediátrica SUS", align = "right"),
                           om = colDef(name = "Ocupação equivalente na média de 2022–2023", align = "right"),
                           ol = colDef(name = "Ocupação equivalente no limiar", align = "right")))
}

# ---- 6. Fontes e arquivos ------------------------------------------------------------------------------
# figura: título da figura ("Figura N – ..."), escrito abaixo do gráfico, antes da fonte (convenção do site)
fonte_prev <- function(extra = NULL, figura = NULL) p(class = "nota-fonte", HTML(paste0(
  if (!is.null(figura)) paste0(figura, ". ") else "",
  "Fonte: elaboração do Projeto PPSUS-MT (previsão de demanda, atividade A5; resultados preliminares, versões <code>", VERSAO_BASE,
  "</code> e <code>", VERSAO_NC, "</code>), com base no SIH/SUS (DATASUS): AIH tipo 1, diagnóstico principal no capítulo J da CID-10 (J00–J99), ",
  "por semana epidemiológica da internação e região de saúde do hospital (ótica de ocorrência). ", if (!is.null(extra)) extra else "")))

ARQS_PREV <- c(
  "previsao_proximas_semanas.csv" = "previsão das 4 semanas a partir da semana de corte, por região, faixa etária e método, com limiar e situação",
  "previsao_nowcast_hoje.csv" = "nowcast das semanas ainda incompletas no SIH, por região, faixa etária e método",
  "previsao_serie_semanal_carga_2026_10_17.csv" = "série semanal completa na carga do SIH de 17/10/2026 (2024 a 2026)",
  "previsao_serie_semanal_2020_2026.csv" = "série semanal observada desde 2020, nas óticas de ocorrência e de residência",
  "previsao_metricas_modelos.csv" = "erro dos modelos por horizonte (MT e média das regiões)",
  "previsao_metricas_regioes.csv" = "erro dos modelos por região de saúde",
  "previsao_validacao_mt.csv" = "observado e previsto na validação, Mato Grosso",
  "previsao_testes_dm.csv" = "testes de Diebold-Mariano entre os modelos",
  "previsao_cobertura_intervalos.csv" = "cobertura e largura dos intervalos de previsão",
  "previsao_baseline_4sem.csv" = "previsões do baseline para as SE 13 a 16/2026",
  "previsao_metricas_nowcast.csv" = "erro do nowcast por faixa de atraso",
  "previsao_metricas_encadeado.csv" = "erro da previsão encadeada a partir da semana de corte",
  "previsao_testes_dm_encadeado.csv" = "testes de Diebold-Mariano da previsão encadeada",
  "previsao_metricas_menor5.csv" = "erro dos modelos para menores de 5 anos",
  "previsao_alerta_limiares.csv" = "limiares de alta pressão (P80 e P90 de 2022–2023)",
  "previsao_alerta_medidas.csv" = "sensibilidade, especificidade, VPP, VPN e F1 do alerta",
  "previsao_alerta_antecedencia.csv" = "antecedência do primeiro aviso nos episódios de alta pressão",
  "previsao_contexto_pediatrico.csv" = "limiar de menores de 5 anos, leitos pediátricos e ocupação equivalente",
  "previsao_dicionario.csv" = "dicionário: conteúdo, colunas, supressão e status de cada arquivo")
lista_arquivos_prev <- function(prefixo = "../arquivos/dados/") {
  ok <- file.exists(file.path(RAIZ, "arquivos", "dados", names(ARQS_PREV)))
  tags$ul(lapply(names(ARQS_PREV)[ok], function(f) tags$li(a(href = paste0(prefixo, f), f), " — ", ARQS_PREV[[f]])))
}
