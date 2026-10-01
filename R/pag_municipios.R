# =============================================================================
# Observatório PPSUS-MT — funções das páginas de município
# (municipios/_perfil.qmd, gerado em municipios/<slug>.qmd, e municipios/index.qmd)
#
# Carregar SEMPRE depois de R/funcoes.R, que define MUN, IND, SER, DESL, FLUXO,
# POLOS, RESDESL, HOSP, CENT, COR, ANOS, ANO_REF e as funções de formatação.
# Nada aqui lê arquivo: só reorganiza o que funcoes.R já carregou.
#
# Índice
#   1. Contexto do município (população, frases com valor + posição)
#   2. Deslocamento — KPIs, "Onde os moradores se internam", "Quem o município atende"
#   3. Hospitais SUS do município (resumo para o texto)
#   4. Botões de download e notas condicionais
# =============================================================================

# ---- 0. Ajustes de exibição em HOSP (usados por tabela_hospitais, de funcoes.R) -----------
# 58 CNES não têm nome fantasia no mart: mostrar um texto em vez de célula vazia; esfera
# administrativa em rótulo legível (códigos desconhecidos ficam como estão).
if (nrow(HOSP) > 0) {
  sem_nome <- is.na(HOSP$nome_fantasia) | !nzchar(trimws(HOSP$nome_fantasia))
  HOSP$nome_fantasia[sem_nome] <- "(sem nome fantasia no CNES)"
  ESFERA_ROTULO <- c(MUNICIPAL = "Municipal", ESTADUAL = "Estadual", FEDERAL = "Federal",
                     PUBLICA_OUTRA = "Pública (outra)", EMPRESA_ESTATAL = "Empresa estatal",
                     PRIVADA_EMPRESARIAL = "Privada (empresarial)",
                     PRIVADA_SEM_FINS_LUCRATIVOS = "Privada sem fins lucrativos")
  i <- match(HOSP$esfera, names(ESFERA_ROTULO))
  HOSP$esfera <- ifelse(is.na(i), ifelse(is.na(HOSP$esfera), "—", HOSP$esfera), ESFERA_ROTULO[i])
}

# ---- 1. Contexto ---------------------------------------------------------------------
POP_MT_2025 <- sum(MUN$populacao_2025, na.rm = TRUE)

# Posição do município pela população 2025 (1 = mais populoso)
pos_populacao <- function(cod) {
  v <- MUN$populacao_2025[MUN$cod_mun6 == cod]
  if (length(v) == 0 || is.na(v)) return(NA_integer_)
  posicao(v, MUN$populacao_2025)
}

# Número de municípios da região de saúde do município
n_mun_regiao <- function(cod) { reg <- regiao_de(cod); if (is.na(reg)) NA_integer_ else length(muns_regiao(reg)) }

# Valor formatado do último ano + (ano; posição em MT), para frases: "R$ 2,3 mil (2025; 12º de 142)"
frase_ind <- function(id, cod, com_pos = TRUE, com_ano = TRUE) {
  r <- info_ind(id); s <- resumo_ind(id, cod)
  if (is.na(s$valor)) return("sem dado disponível")
  extras <- c(if (com_ano && !is.na(s$ano)) as.character(s$ano),
              if (com_pos && !is.na(s$pos_mt)) sprintf("%s de %d em MT", ordinal(s$pos_mt), s$n_mt))
  if (length(extras)) sprintf("%s (%s)", fmt_valor(s$valor, r$fmt), paste(extras, collapse = "; ")) else fmt_valor(s$valor, r$fmt)
}

# Verdadeiro quando o município não tinha população antes de 2025 (instalado em 2025)
mun_novo <- function(cod) is.na(valor_ind("populacao", cod, 2024L)) && !is.na(valor_ind("populacao", cod, 2025L))

# Participação na população do estado: "0,3%" ou "menos de 0,1%" (evita "0,0%" nos municípios pequenos)
pct_pop_txt <- function(p) if (!is.finite(p)) "—" else if (p < 0.05) "menos de 0,1%" else paste0(num(p, 1), "%")

# Parágrafo de contexto: população, despesa por habitante e estrutura no último ano
texto_contexto_mun <- function(cod) {
  nome <- nome_mun(cod); pop <- ultimo("populacao", cod)
  p1 <- if (is.na(pop$valor)) sprintf("%s não tem estimativa populacional disponível.", nome) else
    sprintf("A população estimada em %d é de **%s habitantes** (%s da população do estado; %s entre os 142 municípios).",
            pop$ano, fmt_valor(pop$valor, "int"), pct_pop_txt(100 * pop$valor / POP_MT_2025), ordinal(pos_populacao(cod)))
  s_desp <- resumo_ind("desp_total_pc", cod)
  p2 <- if (is.na(s_desp$valor)) "" else
    sprintf(" Em %d, a despesa liquidada em saúde foi de **%s por habitante** (%s de %d em MT; mediana estadual %s).",
            s_desp$ano, fmt_valor(s_desp$valor, "brl"), ordinal(s_desp$pos_mt), s_desp$n_mt, fmt_valor(s_desp$med_mt, "brl"))
  s_med <- resumo_ind("fte_medicos_p1000", cod); s_lei <- resumo_ind("leitos_sus_p1000", cod); s_hos <- ultimo("n_hospitais_sus", cod)
  p3 <- if (is.na(s_med$valor)) "" else
    sprintf(" O município contava com **%s médicos SUS por mil habitantes** em equivalente de 40 h (%s de %d), %s leitos SUS por mil habitantes e %s.",
            fmt_valor(s_med$valor, "dec2"), ordinal(s_med$pos_mt), s_med$n_mt, fmt_valor(s_lei$valor, "dec2"),
            if (is.na(s_hos$valor)) "sem informação sobre hospitais SUS"
            else if (round(s_hos$valor) == 0) "nenhum hospital SUS registrado no CNES"
            else sprintf("%s %s SUS (média anual no CNES)", num(round(s_hos$valor)), if (round(s_hos$valor) == 1) "hospital" else "hospitais"))
  paste0(p1, p2, p3)
}

# ---- 2. Deslocamento ------------------------------------------------------------------
# Distância geodésica (haversine, km) em linha reta entre as sedes de dois municípios (CENT); NA sem coordenada
km_entre <- function(cod_a, cod_b) {
  i <- match(cod_a, CENT$cod_mun6); j <- match(cod_b, CENT$cod_mun6)
  r <- pi / 180
  la1 <- CENT$lat[i] * r; la2 <- CENT$lat[j] * r
  dla <- la2 - la1; dlo <- (CENT$lon[j] - CENT$lon[i]) * r
  a <- sin(dla / 2)^2 + cos(la1) * cos(la2) * sin(dlo / 2)^2
  2 * 6371 * asin(pmin(1, sqrt(a)))
}

# Há internações de residentes registradas para o município no ano?
tem_desl <- function(d) !is.null(d) && is.finite(d$internacoes_res) && d$internacoes_res > 0

# Parágrafo explicando a ausência de registros (município novo ou sem dado)
texto_sem_desl <- function(cod, ano) {
  nome <- nome_mun(cod)
  if (mun_novo(cod))
    sprintf(paste0("O SIH não registra internações de residentes de %s em %d. O município foi instalado em 2025 e as AIH ",
                   "ainda não usam o seu código: os moradores continuam codificados nos municípios de origem."), nome, ano)
  else sprintf("O SIH não registra internações de residentes de %s em %d.", nome, ano)
}

# Cartões do deslocamento (internações de residentes, % fora do município e da região, km, destino principal)
kpis_deslocamento <- function(cod, ano = ANO_REF, prefixo_ind = "../indicadores/") {
  d <- desl_mun(cod, ano)
  if (!tem_desl(d)) return(invisible(NULL))
  cartao_pct <- function(id, rotulo, valor) {
    r <- info_ind(id); md <- mediana_mt(id, ano); sit <- situacao(valor, md, r$sentido)
    kpi_simples(rotulo, fmt_valor(valor, r$fmt), paste0(r$unidade, " · ", ano),
                tagList(sprintf("Mediana MT: %s", fmt_valor(md, r$fmt)), if (sit$cls != "sit-neutra") span_sit(sit), nota_kpi(r)),
                href = url_ind(id, prefixo_ind))
  }
  div(class = "kpi-grade",
      kpi_simples("Internações de moradores", num(d$internacoes_res), paste0("AIH tipo 1 · SIH · ", ano),
                  if (is.finite(d$internacoes_ac_res)) sprintf("%s na alta complexidade", num(d$internacoes_ac_res))),
      cartao_pct("pct_internacoes_fora_mun", "Fora do município de residência", d$pct_internacoes_fora_mun),
      cartao_pct("pct_internacoes_fora_regiao", "Em outra região de saúde", d$pct_internacoes_fora_regiao),
      kpi_simples("Distância média até o hospital", if (is.finite(d$km_medio_internacao)) paste0(num(d$km_medio_internacao, 1), " km") else "—",
                  paste0("linha reta entre as sedes municipais (IBGE) · ", ano),
                  if (is.finite(d$km_medio_internacao)) sprintf("Mediana MT: %s km", num(mediana_mt("km_medio_internacao", ano), 1)),
                  href = url_ind("km_medio_internacao", prefixo_ind)),
      kpi_simples("Principal local de internação", if (is.na(d$destino_principal_nome)) "—" else d$destino_principal_nome,
                  if (is.finite(d$pct_destino_principal)) sprintf("%s das internações · %s", fmt_valor(d$pct_destino_principal, "pct1"),
                      if (is.finite(d$n_destinos)) sprintf("%d %s fora do município", d$n_destinos, if (d$n_destinos == 1) "destino" else "destinos") else "") else ""))
}

# Tabela HTML simples (Bootstrap) de destinos ou origens
tabela_fluxo_html <- function(rotulo_col, nomes, hrefs, internacoes, pct, km = NULL, rotulo_pct = "% das internações") {
  linhas <- lapply(seq_along(nomes), function(i) tags$tr(
    tags$td(a(href = hrefs[i], nomes[i])),
    tags$td(class = "text-end", num(internacoes[i])),
    tags$td(class = "text-end", fmt_valor(pct[i], "pct1")),
    if (!is.null(km)) tags$td(class = "text-end", if (is.finite(km[i])) num(km[i], 0) else "—")))
  tags$table(class = "table table-sm tabela-fluxo",
             tags$thead(tags$tr(tags$th(rotulo_col), tags$th(class = "text-end", "Internações"), tags$th(class = "text-end", rotulo_pct),
                                if (!is.null(km)) tags$th(class = "text-end", "km"))),
             tags$tbody(linhas))
}

# Série da parcela internada fora do município: município × região (agregado) × MT (agregado)
serie_fora_mun <- function(cod) {
  dm <- DESL[DESL$cod_mun6 == cod & DESL$ano %in% ANOS & is.finite(DESL$pct_internacoes_fora_mun), ]
  if (nrow(dm) < 2) return("")
  reg <- regiao_de(cod)
  dr <- DESL[DESL$cod_mun6 %in% muns_regiao(reg) & DESL$ano %in% ANOS, ] |>
    group_by(ano) |> summarise(tot = sum(internacoes_res, na.rm = TRUE), prop = sum(no_proprio_mun, na.rm = TRUE), .groups = "drop") |>
    filter(tot > 0) |> mutate(v = 100 * (1 - prop / tot))
  mt <- RESDESL[tolower(RESDESL$nivel) == "total" & RESDESL$ano %in% ANOS & is.finite(RESDESL$pct_proprio_mun), ]
  series <- list(list(nome = nome_mun(cod), cor = COR[["mun"]], larg = 2.8, dash = "", x = dm$ano, y = dm$pct_internacoes_fora_mun))
  if (nrow(dr) >= 2) series <- c(series, list(list(nome = paste0("Região ", nome_regiao(reg), " (agregado)"), cor = COR[["sec"]], larg = 1.8, dash = "6,4", x = dr$ano, y = dr$v)))
  if (nrow(mt) >= 2) series <- c(series, list(list(nome = "Mato Grosso (agregado)", cor = COR[["mt"]], larg = 1.8, dash = "2,3", x = mt$ano, y = 100 - mt$pct_proprio_mun)))
  svg_linhas(series, fmt = "pct1", titulo = paste0("Internações de moradores fora do município de residência — ", nome_mun(cod)), h = 230)
}

# Bloco "Onde os moradores se internam" (residência → hospital)
bloco_moradores <- function(cod, ano = ANO_REF) {
  nome <- nome_mun(cod); d <- desl_mun(cod, ano)
  if (!tem_desl(d)) return(div(class = "bloco", h4("Onde os moradores se internam"), p(texto_sem_desl(cod, ano))))
  partes <- c(`No próprio município` = d$no_proprio_mun, `Outro município da mesma região de saúde` = d$mesma_regiao,
              `Outra região de saúde` = d$outra_regiao)
  td <- top_destinos(cod, ano, n = 1000) |> filter(cod_destino != cod) |> slice_head(n = 5)
  ac <- if (is.finite(d$internacoes_ac_res) && d$internacoes_ac_res > 0 && is.finite(d$pct_ac_fora_mun))
    sprintf(" Na alta complexidade (%s internações), %s ocorreram fora do município.", num(d$internacoes_ac_res), fmt_valor(d$pct_ac_fora_mun, "pct1")) else ""
  div(class = "bloco",
      h4("Onde os moradores se internam"),
      p(HTML(sprintf(paste0("Em %d, os moradores de %s tiveram <b>%s internações</b> SUS em hospitais de Mato Grosso: <b>%s</b> no próprio município, ",
                            "%s em outro município da mesma região de saúde e %s em outra região. Distância média em linha reta até o hospital: <b>%s</b>.%s"),
                     ano, esc(nome), num(d$internacoes_res), fmt_valor(d$pct_proprio_mun, "pct1"), fmt_valor(d$pct_mesma_regiao, "pct1"),
                     fmt_valor(d$pct_outra_regiao, "pct1"),
                     if (is.finite(d$km_medio_internacao)) paste0(num(d$km_medio_internacao, 1), " km") else "não calculada", ac))),
      HTML(svg_barra_empilhada(partes, titulo = paste0("Local de internação dos moradores de ", nome, " em ", ano))),
      if (nrow(td)) tagList(
        h5(sprintf("Principais destinos fora do município (%d)", ano)),
        tabela_fluxo_html("Município de destino", td$destino, paste0(slug_mun(td$cod_destino), ".html"), td$internacoes, td$pct,
                          km = km_entre(cod, td$cod_destino), rotulo_pct = "% das internações de moradores"),
        p(class = "nota-fonte", sprintf("%d %s fora do município no total; distância em linha reta entre as sedes municipais (IBGE, Localidades 2022), não rodoviária.",
                                        d$n_destinos, if (d$n_destinos == 1) "município de destino" else "municípios de destino")))
      else p(class = "nota-fonte", sprintf("Todas as internações de moradores em %d ocorreram no próprio município.", ano)),
      { g <- serie_fora_mun(cod); if (nzchar(g)) tagList(h5("Evolução da parcela internada fora do município"), HTML(g)) })
}

# Bloco "Quem o município atende" (hospital ← residência)
bloco_atende <- function(cod, ano = ANO_REF) {
  nome <- nome_mun(cod); d <- desl_mun(cod, ano); m <- info_mun(cod)
  tem_hosp <- isTRUE(m$tem_hospital_sus_2025 == 1)
  rec <- if (is.null(d)) NA_real_ else d$internacoes_recebidas
  if (!is.finite(rec) || rec == 0) {
    txt <- if (mun_novo(cod)) sprintf("O SIH não registra internações realizadas em %s em %d (município instalado em 2025).", nome, ano)
      else if (!tem_hosp) sprintf(paste0("<b>%s não tem hospital SUS registrado no CNES em %d</b> e não realizou internações SUS no ano: ",
                                         "os moradores se internam integralmente em outros municípios."), esc(nome), ano)
      else sprintf(paste0("O CNES registra hospital com atendimento SUS em %s, mas o SIH não traz internações realizadas no município em %d ",
                          "(nenhuma AIH paga no ano)."), esc(nome), ano)
    return(div(class = "bloco", h4("Quem o município atende"), p(HTML(txt))))
  }
  po <- POLOS[POLOS$cod_mun6 == cod & POLOS$ano == ano, ]
  saldo <- if (nrow(po)) po$saldo[1] else NA_real_
  ac_rec <- if (nrow(po)) po$internacoes_ac_recebidas[1] else NA_real_
  to <- top_origens(cod, ano, n = 5)
  frase_saldo <- if (is.finite(saldo)) sprintf(" Saldo entre internações realizadas e internações dos próprios moradores: <b>%s%s</b> (%s).",
                                               if (saldo > 0) "+" else "", num(saldo),
                                               if (saldo > 0) "o município atende mais do que os moradores demandam"
                                               else if (saldo < 0) "os moradores demandam mais do que o município realiza" else "equilíbrio") else ""
  frase_ac <- if (is.finite(ac_rec) && ac_rec > 0) sprintf(" Na alta complexidade, foram %s internações realizadas no município.", num(ac_rec)) else ""
  nota_hosp <- if (!tem_hosp) p(class = "nota-fonte", "O CNES não classifica como hospital nenhum estabelecimento SUS do município; as internações foram realizadas em outros tipos de estabelecimento (por exemplo, unidades mistas).")
  ser <- DESL[DESL$cod_mun6 == cod & DESL$ano %in% ANOS & is.finite(DESL$internacoes_recebidas), ]
  g <- if (nrow(ser) >= 2) svg_linhas(list(
    list(nome = "Internações realizadas no município", cor = COR[["mun"]], larg = 2.8, dash = "", x = ser$ano, y = ser$internacoes_recebidas),
    list(nome = "Das quais de moradores de outros municípios", cor = COR[["sec"]], larg = 1.8, dash = "6,4", x = ser$ano, y = ser$recebidas_de_fora)),
    fmt = "int", titulo = paste0("Internações realizadas em ", nome, " — 2020–2025"), h = 230) else ""
  div(class = "bloco",
      h4("Quem o município atende"),
      p(HTML(sprintf(paste0("Em %d, os estabelecimentos de %s realizaram <b>%s internações</b> SUS de residentes de Mato Grosso; <b>%s (%s)</b> foram de moradores ",
                            "de outros municípios, vindos de %d %s.%s%s"),
                     ano, esc(nome), num(d$internacoes_recebidas), num(d$recebidas_de_fora), fmt_valor(d$pct_recebidas_de_fora, "pct1"),
                     d$n_origens, if (d$n_origens == 1) "outro município" else "outros municípios", frase_saldo, frase_ac))),
      nota_hosp,
      if (nrow(to)) tagList(
        h5(sprintf("Principais origens dos pacientes de fora (%d)", ano)),
        tabela_fluxo_html("Município de residência", to$origem, paste0(slug_mun(to$cod_origem), ".html"), to$internacoes, to$pct,
                          km = km_entre(cod, to$cod_origem), rotulo_pct = "% dos pacientes de fora"))
      else p(class = "nota-fonte", sprintf("Em %d, todas as internações realizadas no município foram de moradores do próprio município.", ano)),
      if (nzchar(g)) tagList(h5("Evolução das internações realizadas"), HTML(g)))
}

# ---- 3. Hospitais SUS ------------------------------------------------------------------
# Resumo dos hospitais do município no ano (hospitais.csv), para o texto da seção
# Leitos e nº de hospitais ponderados pelos meses em que cada CNES constou no ano (n_meses/12), para
# coincidir com a média das 12 competências do painel municipal (leitos_sus_p1000, n_hospitais_sus).
resumo_hospitais <- function(cod, ano = ANO_REF) {
  h <- HOSP[HOSP$cod_mun6 == cod & HOSP$ano == ano, ]
  w <- if ("n_meses" %in% names(h)) ifelse(is.na(h$n_meses), 1, pmin(h$n_meses, 12) / 12) else rep(1, nrow(h))
  list(n = nrow(h), n_medio = sum(w), leitos = sum(h$leitos_sus * w, na.rm = TRUE), uti = sum(h$leitos_uti_sus * w, na.rm = TRUE),
       internacoes = sum(h$internacoes, na.rm = TRUE), sem_sih = sum(is.na(h$internacoes)))
}

texto_hospitais <- function(cod, ano = ANO_REF) {
  nome <- nome_mun(cod); r <- resumo_hospitais(cod, ano)
  if (r$n == 0) return(sprintf("Nenhum estabelecimento classificado como hospital com atendimento SUS consta no CNES para %s em %d.", nome, ano))
  media_txt <- if (abs(r$n_medio - r$n) >= 0.05) sprintf(" (%s em média nas competências do CNES)", num(r$n_medio, 1)) else ""
  paste0(sprintf("Em %d, o CNES registrava **%d %s com atendimento SUS** em %s em ao menos uma competência%s, com %s leitos SUS (%s de UTI) na média das competências do ano. ",
                 ano, r$n, if (r$n == 1) "estabelecimento hospitalar" else "estabelecimentos hospitalares", nome, media_txt, num(round(r$leitos)), num(round(r$uti))),
         if (r$internacoes > 0) sprintf("Esses estabelecimentos realizaram %s internações SUS no ano (SIH, ano da alta), inclusive de residentes de outros estados. ", num(r$internacoes)) else "",
         if (r$sem_sih > 0) sprintf("%d %s sem produção registrada no SIH no ano (só CNES). ", r$sem_sih, if (r$sem_sih == 1) "estabelecimento" else "estabelecimentos") else "",
         "Valores por estabelecimento: leitos e médicos são médias dos meses em que cada um constou no CNES; mortalidade sem ajuste de risco; ocupação dos leitos SUS em %.")
}

# ---- 4. Botões e notas -------------------------------------------------------------------
botoes_download_mun <- function(m) {
  div(class = "botoes-download",
      a(class = "btn btn-sm btn-primary", href = paste0("../arquivos/municipios/", m$slug, ".csv"), download = NA,
        "Baixar os indicadores do município (CSV)"),
      " ",
      a(class = "btn btn-sm btn-outline-primary", href = "../dados/index.html", "Explorar e baixar todos os dados"))
}

# Desliga o zoom pela roda do mouse em um mapa leaflet (a roda volta a rolar a página)
sem_zoom_rolagem <- function(m) {
  if (inherits(m, "leaflet")) m$x$options$scrollWheelZoom <- FALSE
  m
}

# Nota quando o município não tem polígono na malha (ex.: Boa Esperança do Norte)
nota_malha <- function(cod) {
  if (nrow(GEO) == 0 || cod %in% GEO$cod_mun6) return(invisible(NULL))
  p(class = "nota-fonte", sprintf("%s ainda não consta na malha municipal do IBGE usada no site; o mapa destaca apenas a região de saúde.", nome_mun(cod)))
}
