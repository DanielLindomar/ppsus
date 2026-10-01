# =============================================================================
# Observatório PPSUS-MT — funções das páginas de indicador
# (indicadores/index.qmd e indicadores/_indicador.qmd).
# Carregar DEPOIS de R/funcoes.R; não redefine nada de lá.
# =============================================================================

# Texto curto de cada grupo do catálogo (usado no índice)
DESC_GRUPOS <- c(
  contexto       = "População de referência: o denominador dos indicadores por habitante.",
  financiamento  = "Quanto o município liquida em saúde e como financia esse gasto (SIOPS; R$ correntes, sem deflação).",
  capacidade     = "Profissionais, leitos, equipamentos, unidades e equipes com atendimento SUS (CNES; média das competências do ano).",
  atencao_basica = "Produção das equipes de atenção primária (SISAB) e vacinação de rotina (SI-PNI, sem COVID-19).",
  media_alta     = "Procedimentos ambulatoriais (SIA) e internações (SIH) realizados nos estabelecimentos do município ou por seus moradores.",
  deslocamento   = "Para onde os moradores se deslocam para se internar: fora do município, fora da região de saúde e distância média (SIH).",
  resultados     = "Resultados em saúde por residência: mortalidade e condições do nascimento (SIM/SINASC; dados até 2024).")

# Grupos do catálogo, na ordem de GRUPOS
grupos_presentes <- function() intersect(names(GRUPOS), unique(IND$grupo[!is.na(IND$grupo)]))

# Indicadores de um grupo, na ordem de exibição (coluna `ordem`, se existir)
ind_grupo <- function(g) {
  x <- IND[!is.na(IND$grupo) & IND$grupo == g, ]
  if ("ordem" %in% names(x)) x <- x[order(suppressWarnings(as.numeric(x$ordem))), ]
  x
}

# Definição curta (coluna `descricao`, adicional ao contrato; se ausente, o rótulo)
descricao_ind <- function(r) {
  d <- if ("descricao" %in% names(r)) as.character(r$descricao[1]) else NA_character_
  if (is.na(d) || !nzchar(d)) as.character(r$rotulo[1]) else d
}

# Leitura do sentido do indicador
texto_sentido <- function(s) {
  if (is.na(s) || s == 0) return("indicador de contexto, sem juízo de valor: ▲/▼ apenas descrevem a posição frente à mediana")
  if (s > 0) "maior é melhor: ▲ acima da mediana indica situação favorável"
  else "menor é melhor: ▼ abaixo da mediana indica situação favorável"
}

# Como o agregado de MT/região é calculado, segundo o formato
texto_agregado <- function(fmt) if (identical(fmt, "int")) "Soma dos municípios." else "Razão dos totais estaduais (numerador ÷ denominador), não a média dos municípios."

# Estilo próprio das páginas de indicador (evita alterar estilo.scss)
css_indicadores <- function() tags$style(HTML("
.definicao-ind { font-size: 1.08rem; margin: .2rem 0 .8rem; }
.ficha-ind { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: .5rem 1.2rem; margin: 0 0 1rem; font-size: .9rem; }
.ficha-ind > div { border-left: 3px solid #cfe0df; padding-left: .6rem; }
.ficha-ind .rot { font-size: .74rem; color: #6b7280; text-transform: uppercase; letter-spacing: .03em; }
.ficha-ind code { font-size: .84em; white-space: normal; color: #0E5A5E; background: #f3f7f7; padding: 1px 4px; border-radius: 3px; }
.ressalva-ind { background: #fff4d6; border-left: 4px solid #d4a017; padding: .5rem .9rem; font-size: .9rem; margin: 0 0 1.2rem; border-radius: 4px; }
.serie-reg { display: flex; flex-wrap: wrap; gap: .4rem 1rem; align-items: center; margin: .2rem 0 .6rem; font-size: .88rem; }
.serie-reg select { max-width: 340px; }
.lista-ind .cartao-ind p.sub { margin-top: .3rem; }
.grupo-ind-desc { color: #4b5563; }
/* No celular, a coluna única não pode crescer além da tela por causa da largura mínima do ranking */
@media (max-width: 860px) { .perfil-topo { grid-template-columns: minmax(0, 1fr); } }
.perfil-topo > div { min-width: 0; }
"))

# Cartões de um grupo de indicadores (índice): rótulo, definição curta, unidade · fonte · período
cartoes_indicadores <- function(x, prefixo = "") {
  if (nrow(x) == 0) return(p(class = "nota-fonte", "Nenhum indicador neste grupo."))
  div(class = "lista-ind", lapply(seq_len(nrow(x)), function(j) {
    r <- x[j, ]
    a(class = "cartao cartao-ind", href = paste0(prefixo, r$id, ".html"),
      h4(r$rotulo), p(descricao_ind(r)),
      p(class = "sub", paste0(r$unidade, " · ", r$fonte, " · 2020–", ifelse(is.na(r$ano_max), ANO_REF, r$ano_max))))
  }))
}

# Ficha do indicador: definição, grupo, unidade, fonte, período, fórmula e leitura
ficha_indicador <- function(id, prefixo_indice = "") {
  r <- info_ind(id); a1 <- ano_ult(id)
  periodo <- if (is.na(a1)) "—" else paste0(ANOS[1], "–", a1)
  grupo <- if (is.na(r$grupo)) "—" else a(href = paste0(prefixo_indice, "index.html#grupo-", r$grupo), rotulo_grupo(r$grupo))
  tagList(
    p(class = "definicao-ind", descricao_ind(r)),
    div(class = "ficha-ind",
        div(div(class = "rot", "Grupo"), grupo),
        div(div(class = "rot", "Unidade"), ifelse(is.na(r$unidade) | !nzchar(r$unidade), "—", r$unidade)),
        div(div(class = "rot", "Fonte"), ifelse(is.na(r$fonte) | !nzchar(r$fonte), "—", r$fonte)),
        div(div(class = "rot", "Período publicado"), periodo),
        div(div(class = "rot", "Fórmula"), if (is.na(r$formula) || !nzchar(r$formula)) "—" else code(r$formula)),
        div(div(class = "rot", "Leitura"), texto_sentido(r$sentido))))
}

# Ressalva do catálogo (coluna nota), sempre visível
ressalva_indicador <- function(id) {
  r <- info_ind(id)
  if (is.na(r$nota) || !nzchar(r$nota)) return(NULL)
  div(class = "ressalva-ind", strong("Ressalva: "), r$nota)
}

# Variação do agregado de MT entre o primeiro ano da janela e o ano de referência
variacao_mt <- function(id, ano, fmt) {
  a0 <- ANOS[1]; v0 <- valor_mt(id, a0); v1 <- valor_mt(id, ano)
  if (!is.finite(v0) || !is.finite(v1) || is.na(ano) || a0 >= ano) return(NULL)
  if (fmt %in% c("pct1", "pct2")) {
    d <- v1 - v0; txt <- paste0(ifelse(d >= 0, "+", "−"), num(abs(d), 1), " p.p.")
  } else {
    if (v0 == 0) return(NULL)
    d <- 100 * (v1 / v0 - 1); txt <- paste0(ifelse(d >= 0, "+", "−"), num(abs(d), 1), "%")
    if (identical(fmt, "brl")) txt <- paste0(txt, " (R$ correntes)")
  }
  div(sprintf("Variação %d→%d: %s", a0, ano, txt))
}

# Cartões do estado: agregado MT, mediana municipal, maior e menor valor (com município)
kpis_indicador <- function(id, ano = NULL, prefixo_mun = "../municipios/") {
  r <- info_ind(id); if (is.null(ano)) ano <- ano_ult(id)
  if (is.na(ano)) return(p(class = "nota-fonte", "Sem dados para este indicador."))
  v <- valores_ano(id, ano); v <- v[is.finite(v$valor), ]
  mt <- valor_mt(id, ano); md <- mediana_mt(id, ano)
  meta <- paste0(r$unidade, " · ", ano)
  extremo <- function(rotulo, i_sel) {
    val <- v$valor[i_sel]; iguais <- v$cod_mun6[abs(v$valor - val) < 1e-9]
    comp <- if (length(iguais) == 1) a(href = url_mun(iguais, prefixo_mun), nome_mun(iguais))
            else sprintf("%d municípios com este valor", length(iguais))
    kpi_simples(rotulo, fmt_valor(val, r$fmt), meta, comp)
  }
  cards <- list(
    kpi_simples("Mato Grosso (agregado)", fmt_valor(mt, r$fmt), meta, tagList(texto_agregado(r$fmt), variacao_mt(id, ano, r$fmt))),
    kpi_simples("Mediana dos municípios", fmt_valor(md, r$fmt), meta,
                sprintf("Metade dos %d municípios com dado está acima e metade abaixo deste valor.", nrow(v))))
  if (nrow(v) > 0) cards <- c(cards, list(extremo("Maior valor municipal", which.max(v$valor)),
                                          extremo("Menor valor municipal", which.min(v$valor))))
  div(class = "kpi-grade", cards)
}

# Série 2020–2025 do indicador (mediana municipal + MT) com seletor de região de saúde:
# um gráfico por região é gerado em R e só o escolhido fica visível (sem biblioteca JS).
serie_indicador_regioes <- function(id) {
  base <- serie_indicador(id)
  if (!nzchar(base)) return(p(class = "nota-fonte", "Série insuficiente para o gráfico (menos de dois anos com dado)."))
  regs <- REG[ordem_nome(REG$regiao_saude), ]
  blocos <- c(list(div(`data-reg` = "", HTML(base))),
              lapply(seq_len(nrow(regs)), function(j)
                div(`data-reg` = regs$co_regsaud[j], style = "display:none",
                    HTML(serie_indicador(id, co_reg = regs$co_regsaud[j])))))
  tagList(
    if (nrow(regs) > 0) div(class = "serie-reg",
        tags$label(`for` = "sel-reg", "Acrescentar uma região de saúde ao gráfico:"),
        tags$select(id = "sel-reg", class = "form-select form-select-sm", `aria-label` = "Região de saúde a destacar no gráfico",
                    tags$option(value = "", "Nenhuma (mediana dos municípios e Mato Grosso)"),
                    lapply(seq_len(nrow(regs)), function(j) tags$option(value = regs$co_regsaud[j], regs$regiao_saude[j])))),
    div(id = "serie-reg", blocos),
    tags$script(HTML("(function(){var s=document.getElementById('sel-reg');if(!s)return;s.addEventListener('change',function(){document.querySelectorAll('#serie-reg > [data-reg]').forEach(function(d){d.style.display=(d.getAttribute('data-reg')===s.value)?'':'none';});});})();")))
}
