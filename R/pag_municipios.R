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
#   2. Deslocamento — KPIs, "Local de internação dos moradores", "Origem dos pacientes atendidos"
#   3. Hospitais SUS do município (resumo para o texto)
#   4. Botões de download e notas condicionais
#   5. Numeração de tabelas e figuras do perfil (versão 0.5)
# =============================================================================

# ---- 5. Numeração de tabelas e figuras do perfil (versão 0.5) ----------------------------
# Como nas demais páginas do site: "Tabela N – título" acima da tabela e "Figura N – título. Fonte: ..." abaixo da
# figura. Cada perfil é renderizado numa sessão própria do R e os blocos são avaliados na ordem em que aparecem na
# página, de modo que os contadores numeram na ordem de leitura; os blocos ausentes (sem hospital, sem série,
# modelo não avaliado) não consomem número.
NUM_PERFIL <- new.env()
NUM_PERFIL$tab <- 0L
NUM_PERFIL$fig <- 0L
prox_tab <- function() { NUM_PERFIL$tab <- NUM_PERFIL$tab + 1L; NUM_PERFIL$tab }
prox_fig <- function() { NUM_PERFIL$fig <- NUM_PERFIL$fig + 1L; NUM_PERFIL$fig }
titulo_tab <- function(txt) p(strong(sprintf("Tabela %d – %s", prox_tab(), txt)))
legenda_fig <- function(txt, fonte) p(class = "nota-fonte", sprintf("Figura %d – %s. Fonte: %s", prox_fig(), txt, fonte))
FONTE_IND_PERFIL <- "Fonte: elaboração própria, com base nas fontes de cada indicador, indicadas na respectiva página e na Metodologia."
# Tabela de indicadores de um grupo, com título numerado e fonte
GRUPO_TITULO <- c(financiamento = "financiamento", capacidade = "capacidade instalada", atencao_basica = "atenção básica",
                  media_alta = "média e alta complexidade", resultados = "resultados em saúde", deslocamento = "deslocamento para internação")
tabela_grupo_perfil <- function(grupo, cod) {
  tagList(titulo_tab(sprintf("Indicadores de %s de %s", GRUPO_TITULO[[grupo]], nome_mun(cod))),
          tabela_grupo(grupo, cod), p(class = "nota-fonte", FONTE_IND_PERFIL))
}
# Mapa de localização no topo do perfil, com legenda numerada
legenda_mapa_perfil <- function(cod) legenda_fig(sprintf("Município de %s e região de saúde %s no mapa de Mato Grosso", nome_mun(cod), nome_regiao(regiao_de(cod))),
                                                 "IBGE (malha municipal simplificada).")
# Hospitais SUS do município (tabela de funcoes.R), com título numerado e fonte
tabela_hospitais_perfil <- function(cod) {
  tagList(titulo_tab("Estabelecimentos hospitalares com atendimento SUS no município"), tabela_hospitais(cod),
          p(class = "nota-fonte", "Fonte: CNES; SIH/SUS."))
}

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
  p1 <- if (is.na(pop$valor)) sprintf("Não há estimativa populacional disponível para %s.", nome) else
    sprintf("Em %d, a população estimada do município era de **%s habitantes**, o que corresponde a %s da população do estado e o situa em %s lugar entre os 142 municípios.",
            pop$ano, fmt_valor(pop$valor, "int"), pct_pop_txt(100 * pop$valor / POP_MT_2025), ordinal(pos_populacao(cod)))
  s_desp <- resumo_ind("desp_total_pc", cod)
  p2 <- if (is.na(s_desp$valor)) "" else
    sprintf(" No que se refere ao financiamento, em %d, a despesa liquidada em saúde foi de **%s por habitante** (%s lugar entre %d municípios de Mato Grosso), ante uma mediana estadual de %s.",
            s_desp$ano, fmt_valor(s_desp$valor, "brl"), ordinal(s_desp$pos_mt), s_desp$n_mt, fmt_valor(s_desp$med_mt, "brl"))
  s_med <- resumo_ind("fte_medicos_p1000", cod); s_lei <- resumo_ind("leitos_sus_p1000", cod); s_hos <- ultimo("n_hospitais_sus", cod)
  p3 <- if (is.na(s_med$valor)) "" else
    sprintf(" Quanto à capacidade instalada, o município contava com **%s médicos SUS por mil habitantes**, em equivalente de 40 h semanais (%s de %d), e com %s leitos SUS por mil habitantes, %s.",
            fmt_valor(s_med$valor, "dec2"), ordinal(s_med$pos_mt), s_med$n_mt, fmt_valor(s_lei$valor, "dec2"),
            if (is.na(s_hos$valor)) "sem informação sobre hospitais SUS"
            else if (round(s_hos$valor) == 0) "sem hospital SUS registrado no Cadastro Nacional de Estabelecimentos de Saúde (CNES)"
            else sprintf("além de %s %s SUS (média anual no Cadastro Nacional de Estabelecimentos de Saúde, CNES)", num(round(s_hos$valor)), if (round(s_hos$valor) == 1) "hospital" else "hospitais"))
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
    sprintf(paste0("O SIH não registra internações de residentes de %s em %d. Isso decorre do fato de o município ter sido instalado em 2025 ",
                   "e de as AIH ainda não utilizarem o seu código, de modo que os moradores continuam codificados nos municípios de origem."), nome, ano)
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

# Bloco "Local de internação dos moradores" (residência → hospital)
bloco_moradores <- function(cod, ano = ANO_REF) {
  nome <- nome_mun(cod); d <- desl_mun(cod, ano)
  if (!tem_desl(d)) return(div(class = "bloco", h4("Local de internação dos moradores"), p(texto_sem_desl(cod, ano))))
  partes <- c(`No próprio município` = d$no_proprio_mun, `Outro município da mesma região de saúde` = d$mesma_regiao,
              `Outra região de saúde` = d$outra_regiao)
  td <- top_destinos(cod, ano, n = 1000) |> filter(cod_destino != cod) |> slice_head(n = 5)
  ac <- if (is.finite(d$internacoes_ac_res) && d$internacoes_ac_res > 0 && is.finite(d$pct_ac_fora_mun))
    sprintf(" Na alta complexidade, que somou %s internações, %s ocorreram fora do município.", num(d$internacoes_ac_res), fmt_valor(d$pct_ac_fora_mun, "pct1")) else ""
  dist <- if (is.finite(d$km_medio_internacao)) sprintf("A distância média, em linha reta, até o hospital foi de <b>%s</b>.", paste0(num(d$km_medio_internacao, 1), " km"))
          else "A distância média, em linha reta, até o hospital <b>não foi calculada</b>."
  div(class = "bloco",
      h4("Local de internação dos moradores"),
      p(HTML(sprintf(paste0("Em %d, registraram-se <b>%s internações</b> SUS de moradores de %s em hospitais de Mato Grosso, das quais <b>%s</b> ocorreram no próprio município, ",
                            "%s em outro município da mesma região de saúde e %s em outra região. %s%s"),
                     ano, num(d$internacoes_res), esc(nome), fmt_valor(d$pct_proprio_mun, "pct1"), fmt_valor(d$pct_mesma_regiao, "pct1"),
                     fmt_valor(d$pct_outra_regiao, "pct1"), dist, ac))),
      { gb <- svg_barra_empilhada(partes, titulo = paste0("Local de internação dos moradores de ", nome, " em ", ano))
        if (nzchar(gb)) tagList(HTML(gb), legenda_fig(sprintf("Distribuição das internações SUS de moradores de %s segundo o local de internação", nome), "SIH/SUS.")) },
      if (nrow(td)) tagList(
        titulo_tab(sprintf("Principais destinos dos moradores internados fora do município (%d)", ano)),
        tabela_fluxo_html("Município de destino", td$destino, paste0(slug_mun(td$cod_destino), ".html"), td$internacoes, td$pct,
                          km = km_entre(cod, td$cod_destino), rotulo_pct = "% das internações de moradores"),
        p(class = "nota-fonte", sprintf("Fonte: SIH/SUS; IBGE. Nota: no total, as internações de moradores fora do município distribuíram-se por %d %s; a distância é medida em linha reta entre as sedes municipais (IBGE, Localidades 2022), e não pela malha rodoviária.",
                                        d$n_destinos, if (d$n_destinos == 1) "município de destino" else "municípios de destino")))
      else p(class = "nota-fonte", sprintf("Em %d, a totalidade das internações de moradores ocorreu no próprio município.", ano)),
      { g <- serie_fora_mun(cod); if (nzchar(g)) tagList(HTML(g), legenda_fig("Evolução da parcela das internações de moradores realizadas fora do município de residência", "SIH/SUS.")) })
}

# Bloco "Origem dos pacientes atendidos" (hospital ← residência)
bloco_atende <- function(cod, ano = ANO_REF) {
  nome <- nome_mun(cod); d <- desl_mun(cod, ano); m <- info_mun(cod)
  tem_hosp <- isTRUE(m$tem_hospital_sus_2025 == 1)
  rec <- if (is.null(d)) NA_real_ else d$internacoes_recebidas
  if (!is.finite(rec) || rec == 0) {
    txt <- if (mun_novo(cod)) sprintf("O SIH não registra internações realizadas em %s em %d, uma vez que o município foi instalado em 2025.", nome, ano)
      else if (!tem_hosp) sprintf(paste0("<b>%s não possui hospital SUS registrado no CNES em %d</b> e não realizou internações SUS no ano, ",
                                         "de modo que os moradores se internam integralmente em outros municípios."), esc(nome), ano)
      else sprintf(paste0("Embora o CNES registre hospital com atendimento SUS em %s, o SIH não contém internações realizadas no município em %d, ",
                          "isto é, nenhuma AIH foi paga no ano."), esc(nome), ano)
    return(div(class = "bloco", h4("Origem dos pacientes atendidos"), p(HTML(txt))))
  }
  po <- POLOS[POLOS$cod_mun6 == cod & POLOS$ano == ano, ]
  saldo <- if (nrow(po)) po$saldo[1] else NA_real_
  ac_rec <- if (nrow(po)) po$internacoes_ac_recebidas[1] else NA_real_
  to <- top_origens(cod, ano, n = 5)
  frase_saldo <- if (is.finite(saldo)) sprintf(" O saldo entre as internações realizadas e as internações dos próprios moradores foi de <b>%s%s</b>, o que indica que %s.",
                                               if (saldo > 0) "+" else "", num(saldo),
                                               if (saldo > 0) "o município atende mais do que os moradores demandam"
                                               else if (saldo < 0) "os moradores demandam mais do que o município realiza" else "há equilíbrio entre ambas") else ""
  frase_ac <- if (is.finite(ac_rec) && ac_rec > 0) sprintf(if (isTRUE(ac_rec == 1)) " Na alta complexidade, realizou-se %s internação no município."
                                                           else " Na alta complexidade, realizaram-se %s internações no município.", num(ac_rec)) else ""
  nota_hosp <- if (!tem_hosp) p(class = "nota-fonte", "O CNES não classifica como hospital nenhum estabelecimento SUS do município; as internações, portanto, foram realizadas em outros tipos de estabelecimento (por exemplo, unidades mistas).")
  ser <- DESL[DESL$cod_mun6 == cod & DESL$ano %in% ANOS & is.finite(DESL$internacoes_recebidas), ]
  g <- if (nrow(ser) >= 2) svg_linhas(list(
    list(nome = "Internações realizadas no município", cor = COR[["mun"]], larg = 2.8, dash = "", x = ser$ano, y = ser$internacoes_recebidas),
    list(nome = "Das quais de moradores de outros municípios", cor = COR[["sec"]], larg = 1.8, dash = "6,4", x = ser$ano, y = ser$recebidas_de_fora)),
    fmt = "int", titulo = paste0("Internações realizadas em ", nome, " — 2020–2025"), h = 230) else ""
  div(class = "bloco",
      h4("Origem dos pacientes atendidos"),
      # versão 0.5 (5ª rodada): concordância no singular quando há uma única internação de moradores de outros municípios
      p(HTML(if (isTRUE(d$recebidas_de_fora == 1) && isTRUE(d$n_origens == 1))
        sprintf(paste0("Em %d, os estabelecimentos de %s realizaram <b>%s internações</b> SUS de residentes de Mato Grosso, das quais <b>%s (%s)</b> correspondeu a morador ",
                       "de outro município (%d município de origem).%s%s"),
                ano, esc(nome), num(d$internacoes_recebidas), num(d$recebidas_de_fora), fmt_valor(d$pct_recebidas_de_fora, "pct1"),
                d$n_origens, frase_saldo, frase_ac)
        else sprintf(paste0("Em %d, os estabelecimentos de %s realizaram <b>%s internações</b> SUS de residentes de Mato Grosso, das quais <b>%s (%s)</b> corresponderam a moradores ",
                            "de outros municípios, provenientes de %d %s.%s%s"),
                     ano, esc(nome), num(d$internacoes_recebidas), num(d$recebidas_de_fora), fmt_valor(d$pct_recebidas_de_fora, "pct1"),
                     d$n_origens, if (d$n_origens == 1) "outro município" else "outros municípios", frase_saldo, frase_ac))),
      nota_hosp,
      if (nrow(to)) tagList(
        titulo_tab(sprintf("Principais municípios de origem dos pacientes de outros municípios (%d)", ano)),
        tabela_fluxo_html("Município de residência", to$origem, paste0(slug_mun(to$cod_origem), ".html"), to$internacoes, to$pct,
                          km = km_entre(cod, to$cod_origem), rotulo_pct = "% dos pacientes de fora"),
        p(class = "nota-fonte", "Fonte: SIH/SUS; IBGE."))
      else p(class = "nota-fonte", sprintf("Em %d, a totalidade das internações realizadas no município correspondeu a moradores do próprio município.", ano)),
      if (nzchar(g)) tagList(HTML(g), legenda_fig("Internações SUS realizadas no município, no total e de moradores de outros municípios", "SIH/SUS.")))
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
  # versão 0.5 (5ª rodada): concordância no singular quando há um único estabelecimento
  paste0(sprintf("Em %d, o CNES registrava **%d %s com atendimento SUS** em %s em ao menos uma competência%s, que %s %s leitos SUS (%s de UTI) na média das competências do ano. ",
                 ano, r$n, if (r$n == 1) "estabelecimento hospitalar" else "estabelecimentos hospitalares", nome, media_txt,
                 if (r$n == 1) "somava" else "somavam", num(round(r$leitos)), num(round(r$uti))),
         if (r$internacoes > 0) sprintf("%s %s %s SUS no ano (SIH, ano da alta), inclusive de residentes de outros estados. ",
                                        if (r$n == 1) "Esse estabelecimento realizou" else "Esses estabelecimentos realizaram", num(r$internacoes),
                                        if (isTRUE(r$internacoes == 1)) "internação" else "internações") else "",
         if (r$sem_sih > 0) sprintf("Dos estabelecimentos registrados, %d %s sem produção registrada no SIH no ano, constando apenas no CNES. ", r$sem_sih,
                                    if (r$sem_sih == 1) "permaneceu" else "permaneceram") else "",
         "Na tabela por estabelecimento, os leitos e os médicos correspondem às médias dos meses em que cada estabelecimento constou no CNES, a mortalidade não tem ajuste de risco e a ocupação dos leitos SUS é expressa em percentual (%).")
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
  p(class = "nota-fonte", sprintf("%s ainda não consta da malha municipal do IBGE usada no site, razão pela qual o mapa destaca apenas a região de saúde.", nome_mun(cod)))
}

# Internações de moradores em hospitais de OUTROS estados, 2020–2025 somado (versão 0.3):
# dados_site/fuga_mun_periodo.csv (script 02), com supressão de contagens de 1 a 4 já aplicada.
# O valor suprimido nunca é reconstruído aqui.
if (!exists("em_uf")) {
  PREP_UF <- c("Acre" = "no", "Alagoas" = "em", "Amapá" = "no", "Amazonas" = "no", "Bahia" = "na", "Ceará" = "no", "Distrito Federal" = "no", "Espírito Santo" = "no", "Goiás" = "em", "Maranhão" = "no", "Mato Grosso do Sul" = "em", "Minas Gerais" = "em", "Pará" = "no", "Paraíba" = "na", "Paraná" = "no", "Pernambuco" = "em", "Piauí" = "no", "Rio de Janeiro" = "no", "Rio Grande do Norte" = "no", "Rio Grande do Sul" = "no", "Rondônia" = "em", "Roraima" = "em", "Santa Catarina" = "em", "São Paulo" = "em", "Sergipe" = "em", "Tocantins" = "no", "Mato Grosso" = "em")
  em_uf <- function(nome) paste(ifelse(is.na(PREP_UF[nome]), "em", PREP_UF[nome]), nome)
}
texto_fuga_mun <- function(cod) {
  f <- ds("fuga_mun_periodo.csv")
  base <- "Os números apresentados a seguir não incluem as internações em hospitais de outros estados."
  if (!file.exists(f)) return(base)
  d <- data.table::fread(f, encoding = "UTF-8", na.strings = "", colClasses = list(character = c("uf_principal", "nome_uf_principal", "nota_supressao")))
  r <- d[d$cod_mun6 == cod, ]
  if (nrow(r) == 0) return(base)
  per <- r$periodo[1]; lnk <- "(SIH/SUS das outras 26 UF; ver [Internações em outros estados](../deslocamento/index.html#fuga))"
  if (isTRUE(r$total_suprimido[1] == 1))
    return(sprintf("Em %s, a contagem de internações de moradores em hospitais de outros estados não é apresentada, uma vez que a regra de divulgação do projeto suprime as contagens de 1 a 4 e aquelas que permitiriam deduzi-las %s. Os números apresentados a seguir não incluem essas internações.", per, lnk))
  tot <- r$internacoes_total_res[1]; fora <- r$internacoes_outra_uf[1]
  if (is.na(tot) || tot == 0) return(sprintf("Não há internações de moradores registradas em %s, nem em Mato Grosso nem em outros estados.", per))
  if (fora == 0) return(sprintf("Em %s, nenhuma internação de moradores ocorreu em hospitais de outros estados %s.", per, lnk))
  uf <- if (!is.na(r$nome_uf_principal[1]) && !is.na(r$pct_uf_principal[1])) sprintf(", %s delas %s", paste0(num(r$pct_uf_principal[1], 1), "%"), em_uf(r$nome_uf_principal[1]))
        else if (!is.na(r$nome_uf_principal[1])) sprintf(", principalmente %s", em_uf(r$nome_uf_principal[1])) else ""
  sprintf("Em %s, %s das %s internações de moradores (%s) ocorreram em hospitais de outros estados%s %s; essas internações não integram os números apresentados a seguir.",
          per, num(fora), num(tot), paste0(num(r$pct_outra_uf[1], 1), "%"), uf, lnk)
}
