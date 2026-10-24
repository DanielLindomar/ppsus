# =============================================================================
# Observatório PPSUS-MT — seção "Eficiência" dos perfis municipais
# (municipios/_perfil.qmd, gerado em municipios/<slug>.qmd por scripts/03_gerar_paginas.py)
#
# Carregar SEMPRE depois de R/funcoes.R. Lê somente dados_site/eficiencia/ (gerado por
# scripts/06_preparar_eficiencia.py a partir dos resultados DEA/Malmquist; versão em metadados.csv, v2.1 desde 16/10/2026): nenhum
# número é digitado aqui. Saída em HTML simples (sem widgets) para manter o perfil leve.
#
# Índice
#   1. Leitura (fichas, metas, pares, hospitais, especificações) — só colunas usadas
#   2. Rótulos e formatação (faixa, glifo de nível, mudança de eficiência em %)
#   3. Peças da ficha (régua do escore, posição, contexto, pares, metas, evolução, sinais)
#   4. Frase-síntese em linguagem de gestor
#   5. Seção completa (resumo + abas por modelo) e bloco de hospitais
# =============================================================================

EF_DIR <- file.path(RAIZ, "dados_site", "eficiencia")
EF_ANO <- 2025L
EF_PREFIXO <- "../eficiencia/"   # páginas da seção Eficiência, vistas de municipios/

# ---- 1. Leitura ---------------------------------------------------------------------------
# Lê um CSV de dados_site/eficiencia/ com as colunas pedidas (as ausentes viram NA, com aviso)
ef_ler <- function(nome, cols, texto = character(0)) {
  f <- file.path(EF_DIR, nome)
  if (!file.exists(f)) { aviso("dados_site/eficiencia/%s ausente (seção de eficiência vazia)", nome)
    return(tibble::as_tibble(setNames(replicate(length(cols), character(0), simplify = FALSE), cols))) }
  hdr <- names(data.table::fread(f, nrows = 0, encoding = "UTF-8"))
  sel <- intersect(cols, hdr)
  falta <- setdiff(cols, hdr)
  if (length(falta)) aviso("dados_site/eficiencia/%s: colunas ausentes: %s", nome, paste(falta, collapse = ", "))
  txt <- intersect(texto, sel)
  d <- tibble::as_tibble(data.table::fread(f, encoding = "UTF-8", na.strings = "", select = sel,
                                           colClasses = if (length(txt)) list(character = txt) else NULL))
  for (cn in falta) d[[cn]] <- NA
  d
}

EF_COLS_FICHA <- c("cod_mun6", "municipio", "slug", "modelo", "nome_modelo", "ano", "grupo", "rotulo_grupo",
  "situacao", "motivo_situacao", "marca_parcial", "flag_primeiro_exercicio", "escore_bc", "ic_inf", "ic_sup",
  "escore_bcc", "fronteira", "potencial_expansao_pct", "potencial_expansao_min_pct", "potencial_expansao_max_pct",
  "faixa", "ic_cruza_faixa", "posicao_regiao", "posicao_macro", "posicao_estado", "n_dmus_ano",
  "n_vezes_referencia", "escore_esperado", "residuo_escore", "residuo_escore_ic_inf", "residuo_escore_ic_sup",
  "sem_contexto", "n_pares_plausiveis", "par_mais_semelhante_fora_banda", "nota_fronteira_pares", "ec_2020_2025_acum", "ec_2022_2025",
  "ec_ic_inf_2022_2025", "ec_ic_sup_2022_2025", "tendencia_ec_2022_2025", "transicao_marcada",
  "registro_a_verificar", "sinal", "super_infactivel", "flag_rede_sem_hospital", "flag_polo_ac",
  "flag_visitas_baixas", "flag_sisab_incompleto", "flag_quebra_registro", "texto_padrao")
EF_FICHAS <- ef_ler("fichas_municipio.csv", EF_COLS_FICHA,
                    texto = c("modelo", "grupo", "rotulo_grupo", "situacao", "motivo_situacao", "faixa",
                              "posicao_regiao", "posicao_macro", "posicao_estado", "tendencia_ec_2022_2025",
                              "sinal", "nota_fronteira_pares", "texto_padrao", "nome_modelo"))
EF_METAS <- ef_ler("metas_municipio.csv",
                   c("cod_mun6", "modelo", "ano", "variavel", "tipo", "nome_gerencial", "unidade_abs", "fonte",
                     "observado_abs", "meta_radial_abs", "meta_intermediaria_abs", "potencial_unidades",
                     "potencial_pct", "potencial_reais_2025", "meta_publicavel", "nota_meta"),
                   texto = c("modelo", "variavel", "tipo", "nome_gerencial", "unidade_abs", "fonte", "nota_meta"))
EF_PARES <- ef_ler("pares_municipio.csv",
                   c("cod_mun6", "modelo", "ano", "ordem", "par_cod_mun6", "par_municipio", "par_slug",
                     "par_regiao_saude", "par_populacao", "peso", "mais_semelhante"),
                   texto = c("modelo", "par_municipio", "par_slug", "par_regiao_saude"))
EF_ESPEC <- ef_ler("especificacoes_modelos.csv", c("modelo", "grupo", "tipo", "ordem", "nome_gerencial"),
                   texto = c("modelo", "grupo", "tipo", "nome_gerencial"))
EF_HOSP <- ef_ler("fichas_hospital.csv",
                  c("cnes", "nome_hospital", "ano", "cod_mun6", "rotulo_grupo", "situacao", "motivo_situacao",
                    "especificacao_escore", "escore_bc", "ic_inf", "ic_sup", "fronteira", "faixa", "ic_cruza_faixa",
                    "n_dmus_ano", "ec_2022_2025", "tendencia_ec_2022_2025", "registro_a_verificar", "sinal"),
                  texto = c("cnes", "nome_hospital", "rotulo_grupo", "situacao", "motivo_situacao",
                            "especificacao_escore", "faixa", "tendencia_ec_2022_2025", "sinal"))
EF_META <- ef_ler("metadados.csv", c("item", "valor"), texto = c("item", "valor"))
ef_meta <- function(item) { v <- EF_META$valor[EF_META$item == item]; if (length(v)) v[1] else NA_character_ }
EF_DATA <- ef_meta("data_resultados")   # data dos resultados (08/10/2026 na v2; 16/10/2026 na v2.1)
EF_VERSAO <- ef_meta("versao_resultados")
# Frase curta da nota de versão (vazia quando não há versão anterior): o que mudou frente à versão anterior
EF_NOTA_CURTA <- if (!is.na(ef_meta("nota_versao")) && nzchar(ef_meta("nota_versao")) && identical(ef_meta("modelos_reestimados"), "M1"))
  sprintf(" Na versão %s, apenas a atenção básica foi reestimada, com o insumo de agentes comunitários restrito ao ACS (CBO 515105) — [nota de versão](%sindex.html#versao).",
          sub("^v", "", EF_VERSAO), EF_PREFIXO) else ""

# Modelos municipais na ordem da ficha: rótulo curto (aba) e página da seção Eficiência
EF_MODELOS <- c(M1 = "Atenção básica", M0 = "Consolidado", M2 = "Média complexidade",
                M2A = "Média complexidade — ótica do acesso")
EF_PAGINA <- c(M1 = "atencao-basica", M0 = "consolidado", M2 = "media-complexidade",
               M2A = "media-complexidade", H = "hospitais")
EF_DESCR <- c(M1 = "na atenção básica",                       # "está entre as melhores práticas do estado ..."
              M0 = "no conjunto do sistema municipal de saúde",
              M2 = "na média complexidade realizada no município",
              M2A = "no acesso dos moradores às internações de média complexidade")
EF_PROD <- c(M1 = "a produção da atenção básica",                # "poderia ampliar ... em cerca de X%"
             M0 = "a produção do sistema municipal de saúde",
             M2 = "a produção de média complexidade realizada no município",
             M2A = "as internações de média complexidade dos moradores")

v1 <- function(x) if (length(x) == 0) NA else x[[1]]
eh1 <- function(x) isTRUE(as.integer(v1(x)) == 1L)

# ---- 2. Rótulos e formatação ---------------------------------------------------------------
EF_NIVEL <- c("fronteira" = 5L, "quartil superior" = 4L, "terceiro quartil" = 3L, "segundo quartil" = 2L,
              "quartil inferior" = 1L)
EF_ROTULO_FAIXA <- c("fronteira" = "Fronteira (melhores práticas)", "quartil superior" = "Quartil superior",
                     "terceiro quartil" = "Terceiro quartil", "segundo quartil" = "Segundo quartil",
                     "quartil inferior" = "Quartil inferior")
rotulo_faixa <- function(f) ifelse(is.na(f) | !nzchar(f), "—", ifelse(f %in% names(EF_ROTULO_FAIXA), EF_ROTULO_FAIXA[f], f))

# Glifo de nível: 5 quadrados, preenchidos até o nível da faixa (a cor não é o único código)
glifo_faixa <- function(f, w = 58) {
  n <- if (!is.na(f) && f %in% names(EF_NIVEL)) EF_NIVEL[[f]] else 0L
  if (n == 0L) return("")
  q <- paste(sprintf('<rect x="%d" y="1" width="9" height="9" rx="1.5" fill="%s" stroke="%s"/>', (0:4) * 11 + 1,
                     ifelse(1:5 <= n, COR[["mun"]], "#ffffff"), COR[["mun"]]), collapse = "")
  sprintf('<svg class="ef-glifo" viewBox="0 0 %d 11" width="%d" height="11" role="img" aria-label="Faixa: %s (%d de 5)"><title>%s (nível %d de 5)</title>%s</svg>',
          w, w, esc(rotulo_faixa(f)), n, esc(rotulo_faixa(f)), n, q)
}

# Mudança de eficiência (índice) → variação % ao ano: 0,969 → "−3,1% ao ano"
pct_ec <- function(x, sufixo = " ao ano") ifelse(!is.finite(x), "—",
  paste0(ifelse(x >= 1 | round(abs(x - 1) * 100, 1) == 0, "+", "−"), num(abs(x - 1) * 100, 1), "%", sufixo))
num2 <- function(x) num(x, 2)

# Casas decimais da unidade absoluta da meta: médias das competências do ano (FTE, estabelecimentos, equipes,
# leitos, equipamentos) com 1 casa; contagens anuais (internações, procedimentos, registros) sem casas
casas_unid <- function(unidade) ifelse(grepl("FTE|estabelec|equipe|leito|unidade", ifelse(is.na(unidade), "", unidade)), 1L, 0L)
# Formata quantidade conforme a unidade absoluta da meta
fmt_unid <- function(x, unidade) {
  u <- ifelse(is.na(unidade), "", unidade)
  cs <- casas_unid(u)
  ifelse(!is.finite(x), "—",
  ifelse(grepl("R\\$", u), escala(x, "R$ "),
  ifelse(cs == 1L, num(x, 1), num(x, 0))))
}
# Potencial visível na unidade exibida (arredondado com as casas da unidade) — evita "−0" na tabela
potencial_visivel <- function(x, unidade) {
  cs <- casas_unid(unidade)
  is.finite(x) & (grepl("R\\$", ifelse(is.na(unidade), "", unidade)) | abs(round(x, cs)) > 0)
}

# ---- 3. Peças da ficha -----------------------------------------------------------------------
# Régua 0–1: intervalo de confiança (barra), escore corrigido (ponto), mediana do estado
# (traço pontilhado) e escore esperado pelo contexto (losango vazado), quando houver.
regua_escore <- function(r, mediana = NA_real_, w = 420, h = 46) {
  e <- r$escore_bc; li <- r$ic_inf; ls <- r$ic_sup; esp <- r$escore_esperado
  if (!is.finite(e)) return("")
  pl <- 10; pr <- 10; sx <- function(v) pl + pmin(pmax(v, 0), 1) * (w - pl - pr)
  y <- 16
  eixo <- paste(sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="#d1d5db"/><text x="%.1f" y="%d" font-size="10" fill="#6b7280" text-anchor="middle">%s</text>',
                        sx(c(0, .25, .5, .75, 1)), sx(c(0, .25, .5, .75, 1)), y - 7, y + 7, sx(c(0, .25, .5, .75, 1)), h - 4,
                        num(c(0, .25, .5, .75, 1), 2)), collapse = "")
  base <- sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="#e5e7eb" stroke-width="3"/>', sx(0), sx(1), y, y)
  ic <- if (is.finite(li) && is.finite(ls)) sprintf('<rect x="%.1f" y="%d" width="%.1f" height="10" rx="3" fill="#8CBFBD" data-tip="Intervalo de confiança de 95%%: %s a %s"/>',
                                                     sx(li), y - 5, max(sx(ls) - sx(li), 1.5), num2(li), num2(ls)) else ""
  med <- if (is.finite(mediana)) sprintf('<line x1="%.1f" x2="%.1f" y1="%d" y2="%d" stroke="#4b5563" stroke-width="1.5" stroke-dasharray="2,2" data-tip="Mediana dos avaliados no estado: %s"/>',
                                         sx(mediana), sx(mediana), y - 11, y + 11, num2(mediana)) else ""
  ex <- if (is.finite(esp)) sprintf('<path d="M%.1f %d l6 6 l-6 6 l-6 -6 z" fill="#ffffff" stroke="%s" stroke-width="1.6" data-tip="Escore esperado pelo contexto: %s"/>',
                                    sx(esp), y - 6, COR[["sec"]], num2(esp)) else ""
  pt <- sprintf('<circle cx="%.1f" cy="%d" r="6" fill="%s" stroke="#fff" stroke-width="1.5" data-tip="Escore corrigido: %s"/>', sx(e), y, COR[["mun"]], num2(e))
  sprintf('<figure class="ef-regua"><svg viewBox="0 0 %d %d" width="100%%" style="max-width:%dpx" role="img" aria-label="Escore corrigido %s, intervalo de confiança %s a %s, numa escala de 0 a 1"><title>Escore corrigido e intervalo de confiança (escala 0 a 1)</title>%s%s%s%s%s%s</svg><figcaption class="legenda-svg"><span class="leg-item">● escore corrigido</span><span class="leg-item">▬ intervalo de confiança de 95%%</span>%s%s</figcaption></figure>',
          w, h, w, num2(e), num2(li), num2(ls), base, eixo, ic, med, ex, pt,
          if (nzchar(med)) '<span class="leg-item">┆ mediana do estado</span>' else "",
          if (nzchar(ex)) '<span class="leg-item">◇ escore esperado pelo contexto</span>' else "")
}

# Mediana do escore corrigido dos avaliados no ano (e no grupo, na ótica do acesso)
mediana_modelo <- function(modelo, ano, grupo = NA) {
  d <- EF_FICHAS[EF_FICHAS$modelo == modelo & EF_FICHAS$ano == ano & EF_FICHAS$situacao %in% "avaliado", ]
  if (!is.na(grupo) && nzchar(grupo)) d <- d[!is.na(d$grupo) & d$grupo == grupo, ]
  if (nrow(d) == 0) NA_real_ else median(d$escore_bc, na.rm = TRUE)
}

# Lista em oração, com "e" antes do último item
ef_lista_e <- function(x) if (length(x) <= 1) paste(x, collapse = "") else paste(paste(x[-length(x)], collapse = ", "), x[length(x)], sep = " e ")
# Nome gerencial no meio da oração: inicial minúscula ("Médicos SUS" → "médicos SUS"); siglas iniciais ficam
ef_inicial_min <- function(x) ifelse(grepl("^[[:upper:]][[:lower:]]", x), paste0(tolower(substr(x, 1, 1)), substr(x, 2, nchar(x))), x)

# Recursos e produção do modelo (especificação principal vigente), em oração completa (versão 0.5)
texto_espec <- function(modelo, grupo = NA) {
  e <- EF_ESPEC[EF_ESPEC$modelo == modelo, ]
  if (!is.na(grupo) && nzchar(grupo)) e <- e[is.na(e$grupo) | !nzchar(e$grupo) | e$grupo == grupo, ]
  if (nrow(e) == 0) return("")
  e <- e[order(e$tipo, as.numeric(e$ordem)), ]
  ins <- unique(e$nome_gerencial[e$tipo == "insumo"]); pro <- unique(e$nome_gerencial[e$tipo == "produto"])
  sprintf("Os recursos considerados são %s, e a produção compreende %s.", ef_lista_e(ef_inicial_min(ins)), ef_lista_e(ef_inicial_min(pro)))
}

# Leitura do escore esperado pelo contexto (diferença com IC)
texto_contexto <- function(r) {
  if (eh1(r$sem_contexto) || !is.finite(r$escore_esperado))
    return("O escore esperado pelo contexto não foi estimado para este modelo ou ano.")
  lei <- if (is.finite(r$residuo_escore_ic_inf) && r$residuo_escore_ic_inf > 0) "situa-se <b>acima</b> do que o contexto prevê"
         else if (is.finite(r$residuo_escore_ic_sup) && r$residuo_escore_ic_sup < 0) "situa-se <b>abaixo</b> do que o contexto prevê"
         else "é <b>compatível</b> com o que o contexto prevê, uma vez que o intervalo de confiança da diferença inclui zero"
  sprintf("O escore esperado pelo contexto (porte, riqueza, densidade, distância e finanças) é de <b>%s</b>, e o desempenho %s.",
          num2(r$escore_esperado), lei)
}

# Posição na região e na macrorregião: mesma régua da faixa estadual (fronteira à parte; quartis entre os
# avaliados fora da fronteira; sem posição quando há poucos) — calculada em scripts/06_preparar_eficiencia.py.
# Versão 0.5: oração completa; as faixas coincidentes são ditas uma só vez ("bem como na região ... e na macrorregião").
.ef_pos <- function(v) {
  if (is.na(v) || !nzchar(v)) return(list(tipo = "nd"))
  if (v %in% names(.ef_faixa_loc)) return(list(tipo = "faixa", f = v))
  m <- regmatches(v, regexec("^sem posição \\(poucos municípios avaliados fora da fronteira na (região|macrorregião): n = (\\d+)\\)$", v))[[1]]
  if (length(m)) return(list(tipo = "sem", n = m[3]))
  list(tipo = "outro", v = v)
}
.ef_pos_txt <- function(p) switch(p$tipo,
  faixa = sprintf("situa-se na faixa %s", .ef_faixa_loc[[p$f]]),
  sem = sprintf("não se atribui posição, por haver poucos municípios avaliados fora da fronteira (n = %s)", p$n),
  nd = "a posição não é informada",
  esc(p$v))
texto_posicao <- function(r, nome_reg) {
  fe <- r$faixa
  grp_nome <- if (!is.na(r$rotulo_grupo) && nzchar(r$rotulo_grupo)) r$rotulo_grupo else "municípios"
  est <- sprintf("no estado, entre os %s %s avaliados", num(r$n_dmus_ano), esc(grp_nome))
  fx <- sprintf("na faixa <b>%s</b>", if (!is.na(fe) && fe %in% names(.ef_faixa_loc)) .ef_faixa_loc[[fe]] else esc(tolower(rotulo_faixa(fe))))
  pr <- .ef_pos(r$posicao_regiao); pm <- .ef_pos(r$posicao_macro)
  igual <- function(p) identical(p$tipo, "faixa") && identical(p$f, fe)
  loc_r <- sprintf("na região de saúde %s", esc(nome_reg)); loc_m <- "na macrorregião"
  if (igual(pr) && igual(pm)) return(sprintf("O município situa-se %s %s, bem como %s e %s.", fx, est, loc_r, loc_m))
  if (igual(pr)) return(sprintf("O município situa-se %s %s, bem como %s; %s, %s.", fx, est, loc_r, loc_m, .ef_pos_txt(pm)))
  if (igual(pm)) return(sprintf("O município situa-se %s %s, bem como %s; %s, %s.", fx, est, loc_m, loc_r, .ef_pos_txt(pr)))
  if (identical(pr$tipo, "faixa") && identical(pm$tipo, "faixa") && identical(pr$f, pm$f))
    return(sprintf("O município situa-se %s %s; %s e %s, situa-se na faixa %s.", fx, est, loc_r, loc_m, .ef_faixa_loc[[pr$f]]))
  sprintf("O município situa-se %s %s; %s, %s; %s, %s.", fx, est, loc_r, .ef_pos_txt(pr), loc_m, .ef_pos_txt(pm))
}

# Pares de referência plausíveis (até 3) com link para o perfil
pares_de <- function(cod, modelo) {
  p <- EF_PARES[EF_PARES$cod_mun6 == cod & EF_PARES$modelo == modelo & EF_PARES$ano == EF_ANO, ]
  p[order(p$ordem), ]
}
# Na fronteira, a unidade só tem pares quando a fronteira decorre de falta de comparável em algum recurso:
# eles ficam como referência alternativa (os demais casos saem do arquivo em scripts/06_preparar_eficiencia.py)
referencia_alternativa <- function(cod, modelo, r) eh1(r$fronteira) && nrow(pares_de(cod, modelo)) > 0

bloco_pares <- function(cod, modelo, r) {
  p <- pares_de(cod, modelo)
  if (nrow(p) == 0) {
    txt <- if (eh1(r$fronteira)) {
      nref <- as.integer(r$n_vezes_referencia)
      if (is.finite(nref) && nref > 0) sprintf("Por situar-se na fronteira, o município não tem pares e serve de referência para %d %s neste modelo.", nref, if (nref == 1) "município" else "municípios")
      else "Por situar-se na fronteira, o município não tem pares."
    } else "Nenhum município é listado, uma vez que, entre os municípios elegíveis como referência (com registro plausível), nenhum produz mais com os mesmos recursos. O potencial indicado pelo escore provém da comparação com todos os municípios, que inclui unidades fora desse grupo."
    return(sprintf('<p class="ef-linha"><b>Municípios de referência.</b> %s</p>', txt))
  }
  itens <- sprintf('<li><a href="%s.html">%s</a> <span class="sub">(%s; %s hab.; peso %s%%)</span>%s</li>',
                   p$par_slug, esc(p$par_municipio), esc(p$par_regiao_saude), num(p$par_populacao),
                   num(100 * p$peso, 0), ifelse(!is.na(p$mais_semelhante) & p$mais_semelhante == 1,
                          if (eh1(r$par_mais_semelhante_fora_banda)) ' <span class="ef-selo" title="Nenhum par plausível tem população entre 1/3 e 3 vezes a do município">maior peso; nenhum par na faixa de porte de 1/3 a 3 vezes</span>'
                          else ' <span class="ef-selo">mais semelhante em porte</span>', ""))
  alt <- eh1(r$fronteira)
  sprintf('<div class="ef-pares"><b>%s</b> <span class="sub">(%s)</span><ul>%s</ul></div>',
          if (alt) "Referência alternativa" else "Municípios de referência plausíveis",
          if (alt) "a posição na fronteira decorre da falta de comparável em algum recurso; em relação aos municípios elegíveis como referência, estas são as práticas a observar, e o peso indica a participação de cada um na composição da meta"
          else "práticas a observar; o peso indica a participação de cada um na composição da meta",
          paste(itens, collapse = ""))
}

# Metas 2025: só variáveis publicáveis com lacuna; as demais já estão na meta
# Notas das metas em linguagem de gestor (a nota de polo de AC já aparece nos sinais)
nota_meta_gestor <- function(n) {
  n <- n[!grepl("^polo de alta complexidade", n)]
  out <- ifelse(grepl("pares restritos infact", n), "as metas foram calculadas na comparação com todos os municípios, uma vez que a comparação restrita aos elegíveis como referência não tem solução para este município",
         ifelse(grepl("^sem comparável entre os pares", n), "em alguma variável não há comparável entre os municípios elegíveis, razão pela qual a meta é igual ao valor observado",
         ifelse(grepl("meta financeira não publicada", n) & grepl("302", n), "meta financeira não publicada (despesa de média complexidade com registro a verificar)",
         ifelse(grepl("meta financeira não publicada", n), "meta financeira não publicada (classificação orçamentária a verificar)",
         ifelse(grepl("^sem hospital SUS", n), "sem hospital SUS no município, as internações locais são nulas por configuração da rede, e a meta de internações é apenas informativa", n)))))
  unique(out)
}

metas_publicaveis <- function(cod, modelo) EF_METAS[EF_METAS$cod_mun6 == cod & EF_METAS$modelo == modelo & EF_METAS$ano == EF_ANO &
                                                     !is.na(EF_METAS$meta_publicavel) & EF_METAS$meta_publicavel == 1, ]
# Classifica as metas publicáveis: lacuna (potencial ≥ 0,5% e visível na unidade exibida), informativa (observado zero
# com meta positiva: % indefinido) e recursos de polo de AC na ótica do acesso (folga não comparável)
classificar_metas <- function(cod, modelo, r) {
  m <- metas_publicaveis(cod, modelo)
  info <- m[!is.finite(m$potencial_pct) & is.finite(m$potencial_unidades) & abs(m$potencial_unidades) > 0, ]
  lac <- m[is.finite(m$potencial_pct) & abs(m$potencial_pct) >= 0.5 & potencial_visivel(m$potencial_unidades, m$unidade_abs), ]
  polo <- modelo == "M2A" && eh1(r$flag_polo_ac)
  rec_polo <- if (polo) lac[lac$tipo == "insumo", ] else lac[0, ]
  if (polo) lac <- lac[lac$tipo != "insumo", ]
  if (eh1(r$fronteira) && !referencia_alternativa(cod, modelo, r)) { lac <- lac[0, ]; info <- info[0, ] }
  list(m = m, lac = lac[order(lac$tipo != "produto", -abs(lac$potencial_pct)), ], info = info, rec_polo = rec_polo,
       n_ok = nrow(m) - nrow(lac) - nrow(info) - nrow(rec_polo))
}

bloco_metas <- function(cod, modelo, r) {
  fronteira <- eh1(r$fronteira)
  cm <- classificar_metas(cod, modelo, r)
  m <- cm$m; lac <- cm$lac; info <- cm$info; n_ok <- cm$n_ok
  if (nrow(m) == 0) return('<p class="ef-linha"><b>Metas.</b> As metas não são publicadas para este modelo.</p>')
  notas <- nota_meta_gestor(unique(m$nota_meta[!is.na(m$nota_meta) & nzchar(m$nota_meta)]))
  # Versão 0.5: quando a meta informativa decorre só da ausência de hospital SUS (nota_meta "sem hospital SUS"), a
  # explicação entra uma vez, na nota da tabela, e sai da linha "Nota:" (e, em lista_sinais, da lista de sinais)
  sem_hosp_var <- unique(m$variavel[!is.na(m$nota_meta) & grepl("^sem hospital SUS", m$nota_meta)])
  info_sem_hosp <- nrow(info) > 0 && length(sem_hosp_var) > 0 && all(info$variavel %in% sem_hosp_var)
  if (info_sem_hosp) notas <- notas[!grepl("^sem hospital SUS", notas)]
  if (nrow(cm$rec_polo)) notas <- c(notas, sprintf("%s, por se tratar de polo de alta complexidade: parte dos recursos atende moradores de outros municípios e a alta complexidade, razão pela qual a folga de recursos não é comparável e não é publicada",
                                                   if (nrow(cm$rec_polo) == 1) "omite-se a meta de recurso" else sprintf("omitem-se %d metas de recursos", nrow(cm$rec_polo))))
  txt_ok <- if (n_ok > 0) sprintf(" Além das variáveis da tabela, %d %s do modelo já %s na meta.", n_ok, if (n_ok == 1) "outra variável" else "outras variáveis", if (n_ok == 1) "está" else "estão") else ""
  nomes_info <- unique(info$nome_gerencial); n_info <- length(nomes_info)
  txt_info <- if (info_sem_hosp)
      sprintf(" %s %s, %s porque, sem hospital SUS no município, as internações locais são nulas por configuração da rede; por essa razão, não se calcula o percentual de lacuna, e a meta de internações tem caráter apenas informativo.",
              if (n_info == 1) "Na variável" else "Nas variáveis", ef_lista_e(esc(nomes_info)),
              if (n_info == 1) "o valor observado é igual a zero" else "os valores observados são iguais a zero")
    else if (nrow(info)) sprintf(" %s %s, %s no município, razão pela qual não se calcula o percentual de lacuna, e %s caráter apenas informativo.",
              if (n_info == 1) "Na variável" else "Nas variáveis", ef_lista_e(esc(nomes_info)),
              if (n_info == 1) "o valor observado é igual a zero" else "os valores observados são iguais a zero",
              if (n_info == 1) "a meta tem" else "as metas têm") else ""
  if (nrow(lac) == 0 && nrow(info) == 0) {
    corpo <- if (fronteira) '<p class="ef-linha"><b>Metas 2025.</b> Todas as variáveis do modelo já estão na meta, uma vez que o município se situa na fronteira.</p>'
             else if (nrow(cm$rec_polo)) '<p class="ef-linha"><b>Metas 2025:</b> sem lacuna de produção em relação aos municípios elegíveis como referência.</p>'
             else '<p class="ef-linha"><b>Metas 2025.</b> Não há lacuna na comparação com os municípios elegíveis como referência (com registro plausível), dos quais derivam as metas; por essa razão, não há meta a publicar, embora o escore, calculado entre todos os municípios, indique potencial.</p>'
  } else {
    if (nrow(info)) { info$potencial_pct <- NA_real_; lac <- rbind(lac, info) }
    pot <- ifelse(!is.finite(lac$potencial_pct),
                  sprintf("+%s <div class='sub'>meta informativa</div>", fmt_unid(lac$potencial_unidades, lac$unidade_abs)),
           ifelse(lac$tipo == "produto",
                  sprintf("+%s (+%s%%)", fmt_unid(lac$potencial_unidades, lac$unidade_abs), num(lac$potencial_pct, 1)),
                  sprintf("−%s (−%s%%)%s", fmt_unid(abs(lac$potencial_unidades), lac$unidade_abs), num(abs(lac$potencial_pct), 1),
                          ifelse(is.finite(lac$potencial_reais_2025) & abs(lac$potencial_reais_2025) > 0 & !grepl("R\\$", lac$unidade_abs),
                                 paste0("<div class='sub'>", escala(abs(lac$potencial_reais_2025), "R$ "), " de 2025</div>"), ""))))
    linhas <- sprintf('<tr><td>%s<div class="sub">%s · %s</div></td><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td></tr>',
                      esc(lac$nome_gerencial), ifelse(lac$tipo == "produto", "produção ▲", "recurso ▼"), esc(lac$unidade_abs),
                      fmt_unid(lac$observado_abs, lac$unidade_abs), fmt_unid(lac$meta_intermediaria_abs, lac$unidade_abs),
                      fmt_unid(lac$meta_radial_abs, lac$unidade_abs), pot)
    corpo <- sprintf('<div class="ef-tab-wrap"><table class="ef-tab"><caption>Metas 2025 (valores anuais do município)</caption><thead><tr><th>Variável</th><th class="num">Observado 2025</th><th class="num">Meta intermediária</th><th class="num">Meta plena</th><th class="num">Potencial de melhoria</th></tr></thead><tbody>%s</tbody></table></div><p class="nota-fonte">A meta plena corresponde ao que as melhores práticas comparáveis alcançam com os mesmos recursos, e a meta intermediária cobre metade da distância entre o valor observado e a meta plena. Na produção, o potencial expressa o aumento possível; nos recursos, a folga que poderia ser redirecionada sem reduzir a produção.%s</p>',
                     paste(linhas, collapse = ""), paste0(txt_ok, txt_info))
  }
  paste0(corpo, if (length(notas)) sprintf('<p class="nota-fonte">Nota: %s.</p>', esc(paste(notas, collapse = "; "))) else "")
}

# Faixa em cada ano 2020–2025 (posição relativa no ano: as fronteiras são anuais)
faixas_anos <- function(cod, modelo) {
  d <- EF_FICHAS[EF_FICHAS$cod_mun6 == cod & EF_FICHAS$modelo == modelo & EF_FICHAS$ano %in% ANOS, ]
  d <- d[order(d$ano), ]
  if (sum(d$situacao %in% "avaliado") < 2) return("")
  cel <- sprintf('<span class="ef-ano"><span class="sub">%d</span>%s</span>', d$ano,
                 vapply(seq_len(nrow(d)), function(i) if (d$situacao[i] %in% "avaliado" && !is.na(d$faixa[i]) && nzchar(d$faixa[i]))
                   glifo_faixa(d$faixa[i], w = 56) else '<span class="sub">—</span>', character(1)))
  sprintf('<div class="ef-anos" aria-label="Faixa em cada ano"><b>Faixa em cada ano</b> <span class="sub">(5 quadrados = fronteira; 1 = quartil inferior)</span><div>%s</div></div>',
          paste(cel, collapse = ""))
}

# Acumulado 2020–2025 só quando a série é completa: sem transição marcada e com escore em 2020
acumulado_publicavel <- function(r) {
  r20 <- ef_linha(r$cod_mun6, r$modelo, 2020L)
  is.finite(r$ec_2020_2025_acum) && !eh1(r$transicao_marcada) && !is.null(r20) && r20$situacao %in% "avaliado"
}
REGRA_TENDENCIA <- "a regra exige ao menos duas transições anuais com IC inteiramente acima ou abaixo de 1"
texto_evolucao <- function(r) {
  if (!is.finite(r$ec_2022_2025) && !is.finite(r$ec_2020_2025_acum))
    return("Não há transições anuais publicáveis suficientes para calcular a mudança de eficiência.")
  ten <- r$tendencia_ec_2022_2025
  ten_txt <- if (is.na(ten) || !nzchar(ten)) "" else if (ten == "sem tendência definida")
    sprintf(", <b>sem tendência definida</b> <span class=\"sub\">(%s)</span>", REGRA_TENDENCIA) else sprintf(", com <b>%s</b>", esc(ten))
  # IC omitido quando instável (limite inferior abaixo de −50% ao ano: janela curta ou transição isolada)
  ic_ok <- is.finite(r$ec_ic_inf_2022_2025) && is.finite(r$ec_ic_sup_2022_2025) && r$ec_ic_inf_2022_2025 >= 0.5
  ic <- if (ic_ok) sprintf(" (IC 95%%: %s a %s)", pct_ec(r$ec_ic_inf_2022_2025, ""), pct_ec(r$ec_ic_sup_2022_2025, "")) else ""
  paste0(if (is.finite(r$ec_2022_2025)) sprintf("No período 2022–2025, a mudança de eficiência (aproximação às melhores práticas) foi, em média, de <b>%s</b>%s%s.",
                 pct_ec(r$ec_2022_2025), ic, ten_txt) else "No período 2022–2025, não há transições publicáveis suficientes para calcular a mudança de eficiência.",
         if (acumulado_publicavel(r)) sprintf(" A variação acumulada no período 2020–2025 foi de %s.", pct_ec(r$ec_2020_2025_acum, ""))
         else if (is.finite(r$ec_2020_2025_acum)) " A variação acumulada no período 2020–2025 não é publicada, uma vez que a série contém ano sem escore ou transição com registro marcado." else "")
}

# Sinais em linguagem de gestor (códigos da coluna sinal + flags informativas)
EF_SINAIS <- c(
  registro_a_verificar = "Registro a verificar: algum dado de origem (SIOPS, CNES, SISAB, SIA/SIH) tem valor atípico; o município não serve de referência a outros até a verificação.",
  sem_comparavel_insumo = "Sem comparável em algum recurso: nenhum outro município usa tão pouco de algum recurso; a posição na fronteira deve ser lida com reserva.",
  diagnostico_ordem_m = "Desempenho muito acima de amostras de municípios comparáveis (diagnóstico de robustez, informativo): o município continua elegível como referência, mas recomenda-se confirmar os dados de origem.",
  referencia_com_alavancagem = "Referência com grande peso na fronteira (supereficiência acima de 2): não é usada como par de outros municípios.")
lista_sinais <- function(r) {
  cod <- if (is.na(r$sinal) || !nzchar(r$sinal)) character(0) else trimws(strsplit(r$sinal, ";", fixed = TRUE)[[1]])
  s <- unname(ifelse(cod %in% names(EF_SINAIS), EF_SINAIS[cod], gsub("_", " ", cod)))
  if (eh1(r$registro_a_verificar) && !"registro_a_verificar" %in% cod) s <- c(EF_SINAIS[["registro_a_verificar"]], s)
  if (eh1(r$flag_polo_ac) && r$modelo %in% c("M2", "M2A"))
    s <- c(s, "Polo de alta complexidade: parte dos recursos atende à alta complexidade; por isso, o escore de média complexidade é conservador.")
  # Versão 0.5: o sinal de rede sem hospital sai da lista quando a nota das metas da ficha já o explica (bloco_metas)
  if (eh1(r$flag_rede_sem_hospital) && r$modelo == "M0" &&
      !any(grepl("^sem hospital SUS", metas_publicaveis(r$cod_mun6, r$modelo)$nota_meta)))
    s <- c(s, "Sem hospital SUS no município: internações locais nulas por configuração da rede (meta de internações apenas informativa).")
  if (eh1(r$flag_visitas_baixas)) s <- c(s, "Visitas domiciliares abaixo do piso informativo (10% da mediana do ano): apenas sinalização, sem efeito no escore.")
  if (eh1(r$flag_sisab_incompleto)) s <- c(s, "Registro do SISAB incompleto no ano: produção da atenção básica anualizada.")
  if (eh1(r$flag_quebra_registro)) s <- c(s, "Quebra de registro na série do município (produção muito abaixo da dos demais anos).")
  if (eh1(r$transicao_marcada)) s <- c(s, "Há transição anual com registro marcado, que fica fora das médias de evolução.")
  s <- unique(s)
  if (length(s) == 0) return('<p class="ef-linha">Não há sinais de registro ou de leitura neste modelo.</p>')
  sprintf('<div class="ef-sinais"><b>Sinais de registro e leitura</b><ul>%s</ul></div>', paste0("<li>", esc(s), "</li>", collapse = ""))
}

# ---- 4. Frase-síntese -----------------------------------------------------------------------------
frase_sintese <- function(r, nome) {
  alvo <- EF_DESCR[[r$modelo]]
  if (!r$situacao %in% "avaliado") return(sprintf("Em %d, %s não tem escore publicado neste modelo.", EF_ANO, nome))
  f1 <- if (eh1(r$fronteira)) {
    nref <- suppressWarnings(as.integer(r$n_vezes_referencia))
    paste0(sprintf("Em %d, %s situa-se entre as melhores práticas do estado %s (faixa da fronteira)", EF_ANO, nome, alvo),
           if (is.finite(nref) && nref > 0) sprintf(" e serve de referência para %d %s", nref, if (nref == 1) "município" else "municípios") else "",
           if (eh1(r$super_infactivel) || grepl("sem_comparavel", ifelse(is.na(r$sinal), "", r$sinal))) "; essa posição, contudo, deve ser interpretada com reserva, em razão da ausência de comparável em algum recurso." else ".")
  } else {
    # Duas comparações: a meta plena vem dos municípios elegíveis como referência (registro plausível); o escore,
    # da comparação com todos os municípios. Quando há meta de produção, ela vem primeiro.
    cm <- classificar_metas(r$cod_mun6, r$modelo, r)
    pr <- cm$lac[cm$lac$tipo == "produto", ]
    esc_txt <- sprintf("%s%% (entre %s%% e %s%%)", num(r$potencial_expansao_pct, 0), num(r$potencial_expansao_min_pct, 0), num(r$potencial_expansao_max_pct, 0))
    paste0(if (nrow(pr))
             sprintf("Em %d, em relação aos municípios de referência com registro plausível, %s poderia ampliar %s em %s %s%% com os mesmos recursos (meta plena); na comparação com todos os municípios, o escore indica cerca de %s. No estado, o município situa-se na faixa do %s",
                     EF_ANO, nome, EF_PROD[[r$modelo]], if (nrow(pr) > 1) "até" else "cerca de", num(max(pr$potencial_pct), 0), esc_txt, tolower(rotulo_faixa(r$faixa)))
           else sprintf("Em %d, com os mesmos recursos, %s poderia ampliar %s em cerca de %s, segundo o escore calculado entre todos os municípios; no estado, o município situa-se na faixa do %s",
                        EF_ANO, nome, EF_PROD[[r$modelo]], esc_txt, tolower(rotulo_faixa(r$faixa))),
           if (eh1(r$ic_cruza_faixa)) ", com posição incerta entre esta faixa e a vizinha." else ".")
  }
  ten <- ifelse(is.na(r$tendencia_ec_2022_2025), "", r$tendencia_ec_2022_2025)
  f2 <- switch(ten,
    "melhora consistente" = " De 2022 a 2025, aproximou-se das melhores práticas de forma consistente.",
    "piora consistente" = " De 2022 a 2025, afastou-se das melhores práticas de forma consistente.",
    "sem tendência definida" = " De 2022 a 2025, não há tendência definida de aproximação ou afastamento das melhores práticas.",
    "")
  f3 <- if (!eh1(r$sem_contexto) && is.finite(r$residuo_escore_ic_inf) && r$residuo_escore_ic_inf > 0) " O resultado está acima do que o contexto do município prevê."
        else if (!eh1(r$sem_contexto) && is.finite(r$residuo_escore_ic_sup) && r$residuo_escore_ic_sup < 0) " O resultado está abaixo do que o contexto do município prevê."
        else ""
  paste0(f1, f2, f3)
}

# ---- 5. Seção completa -------------------------------------------------------------------------------
ef_linha <- function(cod, modelo, ano = EF_ANO) {
  d <- EF_FICHAS[EF_FICHAS$cod_mun6 == cod & EF_FICHAS$modelo == modelo & EF_FICHAS$ano == ano, ]
  if (nrow(d) == 0) NULL else d[1, ]
}

# Motivo de não avaliação em linguagem de gestor
motivo_gestor <- function(r) {
  m <- ifelse(is.na(r$motivo_situacao), "", r$motivo_situacao)
  if (r$modelo == "M2" && grepl("sem hospital SUS|iguais a zero", m))
    return("sem produção hospitalar de média complexidade no município em todos os anos 2020–2025, a média complexidade é analisada pela ótica do acesso.")
  if (grepl("instalado em 1", m)) return("município instalado em 1º/01/2025, sem série própria para este modelo.")
  if (grepl("^escore não publicado", m)) return(paste0(sub(" — registro a verificar na origem$", "", m), "; registro de origem a verificar."))
  if (grepl("subfunção 302\\) igual a zero", m)) return("despesa de média complexidade (subfunção 302) igual a zero no ano: o município fica fora da estimação deste modelo.")
  if (nzchar(m)) m else "sem avaliação neste modelo."
}

# Ficha de um modelo (HTML)
ficha_modelo <- function(cod, modelo, nome, nome_reg) {
  r <- ef_linha(cod, modelo)
  pag <- paste0(EF_PREFIXO, EF_PAGINA[[modelo]], ".html")
  if (is.null(r)) return(sprintf('<p class="nota-fonte">Sem ficha de %s para %s.</p>', EF_MODELOS[[modelo]], esc(nome)))
  if (!r$situacao %in% "avaliado")
    return(sprintf('<div class="ef-ficha"><p><b>Não avaliado em %d:</b> %s</p><p class="nota-fonte"><a href="%s">Como o modelo funciona →</a></p></div>',
                   EF_ANO, esc(motivo_gestor(r)), pag))
  grp <- if (!is.na(r$grupo) && nzchar(r$grupo)) r$grupo else NA
  intro_acesso <- if (modelo == "M2A") sprintf('<p class="ef-linha">O modelo compara os recursos municipais de média complexidade com as internações de média complexidade dos moradores, onde quer que tenham ocorrido em Mato Grosso, em uma fronteira composta apenas pelos <b>%s</b>.%s</p>',
    esc(r$rotulo_grupo), if (eh1(r$flag_rede_sem_hospital) || identical(grp, "sem_leito")) " Sem leito SUS no município, esta é a leitura da média complexidade." else "") else ""
  topo <- sprintf('<div class="ef-topo"><div class="ef-faixa">%s <span class="ef-faixa-txt">%s</span>%s</div><div class="ef-escore">Escore corrigido <b>%s</b> <span class="sub">(IC 95%%: %s a %s · original %s)</span></div></div>',
                  glifo_faixa(r$faixa), esc(rotulo_faixa(r$faixa)),
                  if (eh1(r$ic_cruza_faixa)) ' <span class="ef-selo" title="O intervalo de confiança alcança a faixa vizinha">IC cruza a faixa vizinha</span>' else "",
                  num2(r$escore_bc), num2(r$ic_inf), num2(r$ic_sup), num2(r$escore_bcc))
  paste0('<div class="ef-ficha">',
         sprintf('<p class="ef-sintese">%s</p>', esc(frase_sintese(r, nome))),
         topo,
         regua_escore(r, mediana_modelo(modelo, EF_ANO, grp)),
         sprintf('<p class="ef-linha"><b>O que o modelo compara.</b> %s</p>', esc(texto_espec(modelo, grp))),
         intro_acesso,
         sprintf('<p class="ef-linha"><b>Posição.</b> %s</p>', texto_posicao(r, nome_reg)),
         sprintf('<p class="ef-linha"><b>Contexto.</b> %s</p>', texto_contexto(r)),
         bloco_pares(cod, modelo, r),
         bloco_metas(cod, modelo, r),
         sprintf('<p class="ef-linha"><b>Evolução.</b> %s</p>', texto_evolucao(r)),
         faixas_anos(cod, modelo),
         lista_sinais(r),
         if (!is.na(r$texto_padrao) && nzchar(r$texto_padrao))
           sprintf('<details class="nota-det"><summary>Leitura técnica completa da ficha</summary><p class="nota-fonte">%s</p></details>', esc(redigir_texto_padrao(r$texto_padrao))) else "",
         sprintf('<p class="nota-fonte"><a href="%s">Ver %s para todos os municípios →</a></p>', pag, esc(tolower(EF_MODELOS[[modelo]]))),
         '</div>')
}

# Quadro-resumo 2025 dos quatro modelos municipais
resumo_ef <- function(cod) {
  linhas <- vapply(names(EF_MODELOS), function(mo) {
    r <- ef_linha(cod, mo)
    nm <- sprintf('<a href="%s%s.html">%s</a>', EF_PREFIXO, EF_PAGINA[[mo]], EF_MODELOS[[mo]])
    if (is.null(r)) return(sprintf("<tr><td>%s</td><td colspan='3' class='sub'>sem ficha</td></tr>", nm))
    if (!r$situacao %in% "avaliado") return(sprintf("<tr><td>%s</td><td colspan='3' class='sub'>não avaliado: %s</td></tr>", nm, esc(motivo_gestor(r))))
    ten <- ifelse(is.na(r$tendencia_ec_2022_2025) | !nzchar(r$tendencia_ec_2022_2025), "—", r$tendencia_ec_2022_2025)
    sprintf("<tr><td>%s</td><td>%s %s%s</td><td class='num'>%s <span class='sub'>(%s a %s)</span></td><td>%s</td></tr>",
            nm, glifo_faixa(r$faixa), esc(rotulo_faixa(r$faixa)), if (eh1(r$ic_cruza_faixa)) " <span class='sub'>· IC cruza a faixa vizinha</span>" else "",
            num2(r$escore_bc), num2(r$ic_inf), num2(r$ic_sup), esc(ten))
  }, character(1))
  sprintf('<div class="ef-tab-wrap"><table class="ef-tab ef-resumo"><caption>Eficiência em %d por modelo</caption><thead><tr><th>Modelo</th><th>Faixa no estado</th><th class="num">Escore corrigido (IC 95%%)</th><th>Tendência 2022–2025</th></tr></thead><tbody>%s</tbody></table></div>',
          EF_ANO, paste(linhas, collapse = ""))
}

ef_estilo <- function() tags$style(HTML("
.ef-tab-wrap { overflow-x: auto; }
.ef-tab { width: 100%; border-collapse: collapse; font-size: .88rem; margin: .3rem 0 .4rem; }
.ef-tab caption { caption-side: top; font-weight: 600; color: #374151; font-size: .85rem; padding: 0 0 .2rem; }
.ef-tab th { text-align: left; border-bottom: 2px solid #0E5A5E; padding: .3rem .45rem; font-size: .8rem; color: #374151; }
.ef-tab td { border-bottom: 1px solid #e5e7eb; padding: .3rem .45rem; vertical-align: top; }
.ef-tab td.num, .ef-tab th.num { text-align: right; white-space: nowrap; }
.ef-tab .sub, .ef-ficha .sub { color: #6b7280; font-size: .8rem; }
.ef-ficha { border: 1px solid #e3ecec; border-radius: 8px; padding: .7rem .9rem; background: #fbfdfd; }
.ef-sintese { font-size: 1rem; border-left: 4px solid #0E5A5E; padding-left: .6rem; margin-bottom: .6rem; }
.ef-topo { display: flex; flex-wrap: wrap; gap: .4rem 1.4rem; align-items: center; }
.ef-faixa { font-weight: 600; font-size: 1.02rem; display: flex; align-items: center; gap: .4rem; flex-wrap: wrap; }
.ef-glifo { vertical-align: middle; }
.ef-selo { display: inline-block; font-size: .72rem; font-weight: 600; background: #eef4f4; color: #0E5A5E; border: 1px solid #cfe0df; border-radius: 10px; padding: 0 .45rem; }
.ef-regua { margin: .3rem 0 .4rem; }
.ef-linha { margin: .35rem 0; font-size: .92rem; }
.ef-pares ul, .ef-sinais ul { margin: .2rem 0 .4rem; padding-left: 1.2rem; font-size: .9rem; }
.ef-pares, .ef-sinais { margin: .4rem 0; font-size: .92rem; }
.ef-anos { margin: .4rem 0; font-size: .9rem; }
.ef-anos > div { display: flex; flex-wrap: wrap; gap: .3rem .8rem; margin-top: .2rem; }
.ef-ano { display: inline-flex; flex-direction: column; align-items: center; gap: .1rem; }
"))

# Seção "Eficiência" do perfil: introdução, resumo, abas por modelo (texto Markdown + HTML bruto)
secao_eficiencia <- function(cod) {
  m <- info_mun(cod); nome <- m$municipio
  if (nrow(EF_FICHAS) == 0 || !any(EF_FICHAS$cod_mun6 == cod)) {
    cat("Os resultados de eficiência ainda não estão disponíveis para este município.\n\n"); return(invisible())
  }
  r1 <- ef_linha(cod, "M1"); r2 <- ef_linha(cod, "M2"); r2a <- ef_linha(cod, "M2A")
  primeiro <- !is.null(r1) && (eh1(r1$flag_primeiro_exercicio) || eh1(r1$marca_parcial))
  sem_m2 <- !is.null(r2) && !r2$situacao %in% "avaliado"
  html <- function(x) cat("\n```{=html}\n", x, "\n```\n\n", sep = "")
  html(as.character(ef_estilo()))
  cat(sprintf("Os escores comparam o que %s produz com os recursos que utiliza, tendo como referência as **melhores práticas observadas em municípios de Mato Grosso** no mesmo ano, estimadas por Análise Envoltória de Dados (DEA, do inglês *Data Envelopment Analysis*) com orientação ao produto. A leitura deve ser feita por **faixa com intervalo de confiança**, e não por posição exata. Cumpre ressaltar que o escore mede a eficiência técnica, **e não a qualidade do cuidado**, e que os resultados em saúde constam das abas acima. Os resultados correspondem à versão %s da estimação (%s) e encontram-se em validação com a Secretaria de Estado de Saúde de Mato Grosso (SES-MT) e o Conselho de Secretarias Municipais de Saúde de Mato Grosso (COSEMS-MT).%s A forma de leitura é detalhada em [Eficiência — visão geral](%sindex.html).\n\n",
              nome, ifelse(is.na(EF_VERSAO), "2", sub("^v", "", EF_VERSAO)), ifelse(is.na(EF_DATA), "", EF_DATA), EF_NOTA_CURTA, EF_PREFIXO))
  if (primeiro) cat(sprintf("::: {.callout-note}\n**Primeiro exercício.** %s foi instalado em 1º/01/2025, razão pela qual há resultado apenas para 2025, marcado como parcial (produção da atenção básica anualizada e registro possivelmente incompleto). O município ainda não serve de referência a outros e não dispõe de evolução (Malmquist) nem de escore esperado pelo contexto.\n:::\n\n", nome))
  if (sem_m2 && !primeiro) cat(sprintf("Por não dispor de hospital SUS com produção de média complexidade em todos os anos, %s não integra o modelo de média complexidade pela produção local; nesse caso, a média complexidade é analisada **pela ótica do acesso**, isto é, pelas internações de média complexidade dos moradores, onde quer que tenham ocorrido em Mato Grosso.\n\n", nome))
  html(resumo_ef(cod))
  cat(":::: {.panel-tabset}\n\n")
  for (mo in names(EF_MODELOS)) {
    r <- ef_linha(cod, mo)
    if (is.null(r)) next
    if (mo == "M2" && !r$situacao %in% "avaliado" && !is.null(r2a) && r2a$situacao %in% "avaliado") next  # a aba do acesso explica
    if (mo == "M2A" && !r$situacao %in% "avaliado" && !is.null(r2) && !r2$situacao %in% "avaliado" && primeiro) next
    cat(sprintf("### %s\n\n", EF_MODELOS[[mo]]))
    html(ficha_modelo(cod, mo, nome, m$regiao_saude))
  }
  cat("::::\n\n")
  cat(sprintf('<p class="nota-fonte">Fonte: Projeto PPSUS-MT, Resultados DEA %s (%s), com base em dados do SIOPS, CNES, SISAB, SI-PNI, SIA, SIH e IBGE, 2020–2025. Nota: os valores monetários estão expressos em R$ de 2025 (IPCA); o escore é corrigido do viés por <i>bootstrap</i>, e as faixas correspondem aos quartis entre os municípios avaliados fora da fronteira. Os arquivos completos encontram-se em <a href="../dados/index.html#eficiencia">Dados</a>.</p>\n\n',
              ifelse(is.na(EF_VERSAO), "v2", EF_VERSAO), ifelse(is.na(EF_DATA), "", EF_DATA)))
  invisible()
}

# ---- Hospitais do município: faixa e escore do modelo de hospitais ---------------------------------------
bloco_hospitais_ef <- function(cod, ano = EF_ANO) {
  h <- EF_HOSP[EF_HOSP$cod_mun6 == cod & EF_HOSP$ano == ano, ]
  if (nrow(h) == 0) return(invisible(NULL))
  h <- h[order(-(h$situacao %in% "avaliado"), -ifelse(is.na(h$escore_bc), -1, h$escore_bc)), ]
  n_aval <- sum(EF_HOSP$ano == ano & EF_HOSP$situacao %in% "avaliado")
  linhas <- vapply(seq_len(nrow(h)), function(i) {
    x <- h[i, ]
    nm <- sprintf("%s<div class='sub'>CNES %s · %s</div>", esc(x$nome_hospital), x$cnes, esc(ifelse(is.na(x$rotulo_grupo), "", x$rotulo_grupo)))
    if (!x$situacao %in% "avaliado")
      return(sprintf("<tr><td>%s</td><td colspan='3' class='sub'>escore não publicado: %s</td></tr>", nm,
                     esc(gsub("_", " ", sub(":.*$", "", ifelse(is.na(x$motivo_situacao), "", x$motivo_situacao))))))
    obs <- c(if (identical(x$especificacao_escore, "n_nao_balanceado")) "fora do painel balanceado 2020–2025 (sem evolução)",
             if (eh1(x$registro_a_verificar)) "registro a verificar")
    sprintf("<tr><td>%s</td><td>%s %s%s</td><td class='num'>%s <span class='sub'>(%s a %s)</span></td><td>%s%s</td></tr>",
            nm, glifo_faixa(x$faixa), esc(rotulo_faixa(x$faixa)), if (eh1(x$ic_cruza_faixa)) " <span class='sub'>· IC cruza a faixa vizinha</span>" else "",
            num2(x$escore_bc), num2(x$ic_inf), num2(x$ic_sup),
            if (is.finite(x$ec_2022_2025)) sprintf("%s <span class='sub'>(%s)</span>", pct_ec(x$ec_2022_2025), esc(ifelse(is.na(x$tendencia_ec_2022_2025), "", x$tendencia_ec_2022_2025))) else "—",
            if (length(obs)) sprintf("<div class='sub'>%s</div>", esc(paste(obs, collapse = "; "))) else "")
  }, character(1))
  tagList(
    h4(paste0("Eficiência dos hospitais (modelo de hospitais, ", ano, ")")),
    p(sprintf("O modelo compara cada hospital SUS com as melhores práticas entre os %s hospitais avaliados em Mato Grosso. %s A leitura é feita por faixa com intervalo de confiança, e não por ",
              num(n_aval), texto_espec("H")), tags$em("ranking", .noWS = "outside"), ", e cumpre lembrar que eficiência não é qualidade."),
    HTML(sprintf('<div class="ef-tab-wrap"><table class="ef-tab"><thead><tr><th>Hospital</th><th>Faixa no estado</th><th class="num">Escore corrigido (IC 95%%)</th><th>Mudança de eficiência 2022–2025</th></tr></thead><tbody>%s</tbody></table></div>',
                 paste(linhas, collapse = ""))),
    p(class = "nota-fonte", sprintf("Fonte: Projeto PPSUS-MT, Resultados DEA %s (%s), com base em dados do CNES e do SIH/SUS. Nota: os hospitais do município ausentes desta tabela não integram o modelo de hospitais. ",
                                    ifelse(is.na(EF_VERSAO), "v2", EF_VERSAO), ifelse(is.na(EF_DATA), "", EF_DATA)),
      a(href = paste0(EF_PREFIXO, "hospitais.html"), "Ver todos os hospitais avaliados →")))
}
