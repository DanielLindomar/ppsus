# =============================================================================
# Observatório PPSUS-MT — redação científica dos textos gerados das fichas de eficiência
# (versão 0.5 do site; carregado por R/funcoes.R)
#
# Alguns textos exibidos no site chegam prontos dos arquivos gerados por
# scripts/06_preparar_eficiencia.py a partir do schema `dea` (somente leitura), em redação
# telegráfica:
#   1. texto_padrao   (fichas_municipio.csv)  — leitura técnica completa da ficha, nos perfis
#                                               e no detalhe das tabelas da seção Eficiência;
#   2. nota_evolucao  (fichas_municipio.csv)  — linha "Evolução" do detalhe das tabelas;
#   3. nota_versao    (metadados.csv)         — nota de versão da estimação 2.1 (caixa da seção
#                                               Eficiência e página Dados);
#   4. descricao      (catalogo_eficiencia.csv) — descrições dos arquivos de eficiência (DESCR do 06),
#                                               na página Dados e nas listas de arquivos da seção.
# A versão 0.5 reescreve esses textos SOMENTE NA EXIBIÇÃO. O banco, o pipeline da DEA, o script 06
# e os CSV (inclusive os de download) não mudam.
#
# Regra do mapeamento: cada frase-modelo é uma expressão regular ancorada (^...$). Os grupos capturam
# os trechos variáveis (números, nomes de municípios e regiões, rótulos de faixa) exatamente como
# vêm do arquivo, e a redação nova os reaproveita sem recalcular nem reformatar nada. Frase sem
# mapeamento é exibida como está e gera aviso. A conferência
# _planejamento/v05_controle/confere_redacao_ef.R aplica o mapeamento às 3.408 fichas (6 anos) e
# exige: nenhuma frase sem mapeamento; o mesmo multiconjunto de números em cada texto; os mesmos
# nomes de municípios e regiões.
#
# Quadro das frases-modelo do texto_padrao (o texto é dividido em frases antes do mapeamento)
#   F01  "Em <ano>, <mun> está entre as melhores práticas do estado neste modelo (fronteira; escore
#         corrigido <e>, IC 95% de <a> a <b>) e serve de referência para <n> município(s)."
#        -> "Em <ano>, <mun> situa-se entre as melhores práticas do estado neste modelo, isto é, na
#            fronteira, com escore corrigido de <e> (intervalo de confiança de 95%: <a> a <b>), e serve
#            de referência para <n> município(s)."
#   F02  idem, sem a referência -> idem, sem a oração final.
#   F03  "Em <ano>, <mun> produziu cerca de <p>% a menos do que as melhores práticas comparáveis
#         permitiriam com os mesmos recursos (escore corrigido <e>, IC 95% de <a> a <b>; original <o>)."
#        -> "Em <ano>, a produção de <mun> situou-se cerca de <p>% abaixo do que as melhores práticas
#            comparáveis permitiriam alcançar com os mesmos recursos, com escore corrigido de <e>
#            (intervalo de confiança de 95%: <a> a <b>) e escore original de <o>."
#   F04  "Sem novos recursos, a produção poderia crescer cerca de <p>% (entre <a>% e <b>%)."
#        -> "Sem novos recursos, a produção poderia crescer cerca de <p>%, com intervalo entre <a>% e <b>%."
#   F05  "A posição na fronteira decorre da ausência de comparável em algum insumo (supereficiência
#         infactível): leitura com reserva."
#        -> "... (supereficiência infactível), razão pela qual deve ser interpretada com reserva."
#   F06  "Faixa no estado[ (entre os municípios do grupo '<g>')]: <faixa>[ (o intervalo cruza a faixa
#         vizinha)]; na região <reg>: <faixa2> | sem posição (poucos municípios avaliados fora da
#         fronteira na região: n = <n>)."
#        -> "No estado[, entre os municípios do grupo '<g>'], o município situa-se na faixa <da fronteira|
#            do quartil ...>[, e o intervalo de confiança cruza a faixa vizinha]; na região <reg>,
#            situa-se na faixa <...> | não se atribui posição, por haver poucos municípios avaliados
#            fora da fronteira na região (n = <n>)."
#   F07  "Municípios de referência plausíveis: <lista>; par mais semelhante: <par>."
#        -> "Identifica-se o seguinte município de referência plausível: <lista>; o par mais semelhante
#            é <par>." (no plural quando há mais de um município na lista)
#   F08  "Escore esperado pelo contexto (<fatores>): <x>; no segundo estágio (escore corrigido <e>),
#         o município fica <d> acima|abaixo do esperado."
#        -> "O escore esperado pelo contexto (<fatores>) é de <x>; no segundo estágio, com escore
#            corrigido de <e>, o município situa-se <d> acima|abaixo do esperado."
#   F09  "Evolução <a1>–<a2>: aproximação às melhores práticas (componente de gestão) <v>% ao ano
#         (<tendência>)."
#        -> "No período <a1>–<a2>, a aproximação às melhores práticas (componente de gestão) foi de
#            <v>% ao ano, <sem tendência definida | com melhora consistente | com piora consistente>."
#   F10  "Sinalizações: <s1>[; <s2>]." -> "A ficha apresenta a(s) seguinte(s) sinalização(ões): ..."
#        (registro a verificar; sem comparável em algum insumo -> ausência de comparável em algum
#        insumo; diagnóstico ordem-m -> diagnóstico de robustez de ordem-m; referência com alavancagem)
#   F11  "Sem hospital SUS no município: internações locais iguais a zero por configuração da rede
#         (meta de internações informativa)."
#        -> "Na ausência de hospital SUS no município, as internações locais são iguais a zero por
#            configuração da rede, e a meta de internações tem caráter apenas informativo."
#   F12  "Polo de alta complexidade: parte dos insumos atende à alta complexidade (escore de média
#         complexidade conservador)."
#        -> "Por se tratar de polo de alta complexidade, parte dos insumos atende à alta complexidade,
#            razão pela qual o escore de média complexidade é conservador."
#   F13  "Os dados de origem devem ser verificados (CNES/SIOPS/SISAB) antes de qualquer leitura; as
#         sinalizações da ficha permanecem válidas." -> mantida (já em redação formal).
#   F14  "<mun>, <ano>: escore não publicado — escore não publicado: <motivo> — registro a verificar
#         na origem." -> "Em <ano>, o escore de <mun> não é publicado, em razão de <motivo>, e o
#         registro deve ser verificado na origem."
#   F15  "<mun>, <ano>: sem avaliação neste modelo (não elegível ao M2: sem hospital SUS no município
#         (...; o modelo avalia só ... nos seis anos — ver modelo da ótica do acesso, ótica de acesso))."
#        -> "Em <ano>, <mun> não é avaliado neste modelo, uma vez que não é elegível ao M2 por não
#            dispor de hospital SUS: ...; a esse respeito, consulte-se o modelo da ótica do acesso."
#   F16  "<mun>, <ano>: sem avaliação neste modelo (excluído da estimação: despesa de média
#         complexidade (subfunção <s>) igual a zero no ano[; o município-ano entra só num teste de
#         sensibilidade, sem escore publicado])." -> "Em <ano>, <mun> não é avaliado neste modelo, uma
#         vez que foi excluído da estimação por apresentar despesa ... igual a zero no ano[; o
#         município-ano integra apenas um teste de sensibilidade, sem escore publicado]."
#   F17  "<mun>, <ano>: sem avaliação neste modelo (município instalado em <data> (<mun>): sem dados
#         próprios antes de <ano2>)." -> "Em <ano>, <mun> não é avaliado neste modelo, uma vez que o
#         município foi instalado em <data> e não dispõe de dados próprios antes de <ano2>."
#   F18  "<mun>, <ano>: sem avaliação neste modelo (não elegível ao M2: internações de média
#         complexidade locais iguais a zero em pelo menos um dos anos <a1>–<a2> (ver modelo da ótica
#         do acesso, ótica de acesso))." -> "Em <ano>, <mun> não é avaliado neste modelo, uma vez que
#         não é elegível ao M2: as internações ... iguais a zero em pelo menos um dos anos <a1>–<a2>;
#         a esse respeito, consulte-se o modelo da ótica do acesso."
#   F19  "<mun>, <ano>: sem avaliação neste modelo (não elegível ao M2: município instalado em <data>,
#         sem série própria de internações de média complexidade locais)." -> "Em <ano>, <mun> não é
#         avaliado neste modelo, uma vez que não é elegível ao M2: o município foi instalado em <data>
#         e não dispõe de série própria de internações de média complexidade locais."
#   F20  "<mun>, <ano>: sem avaliação neste modelo (fora do M2-acesso: o modelo-espelho avalia os <n>
#         municípios do painel; <mun>, instalado em <data>, não tem série própria de internações de
#         residentes (reagregado ao município de origem no Malmquist))." -> "Em <ano>, <mun> não é
#         avaliado neste modelo, uma vez que não integra o M2-acesso: o modelo-espelho avalia os <n>
#         municípios do painel, e <mun>, instalado em <data>, não dispõe de série própria de
#         internações de residentes (reagregado ao município de origem no Malmquist)."
#   F21  "Hospital de outra esfera: despesa <s> baixa com internações locais relevantes (nota
#         informativa; não restringe pares)." -> "Registra-se hospital de outra esfera, com despesa
#         <s> baixa e internações locais relevantes (nota informativa, que não restringe os pares)."
#   F22  "Primeiro exercício do município: registro possivelmente parcial (produtos SISAB
#         anualizados); escore publicável com marca 'parcial'." -> "Por se tratar do primeiro
#         exercício do município, o registro é possivelmente parcial (produtos do SISAB anualizados),
#         e o escore é publicável com a marca 'parcial'."
#   F23  "Flag de rede 'sem hospital SUS' ativa apesar de internações de média complexidade locais
#         registradas no SIH: configuração da rede a verificar na origem (CNES/SIH)." -> "A marcação de
#         rede 'sem hospital SUS' está ativa, apesar de haver internações de média complexidade locais
#         registradas no SIH, de modo que a configuração da rede deve ser verificada na origem (CNES/SIH)."
# As frases-modelo de nota_evolucao (E1–E4), a nota de versão (V1) e as descrições do catálogo
# (D01–D18) estão nos quadros REDACAO_NOTA_EVOLUCAO, REDACAO_NOTA_VERSAO e REDACAO_DESCRICAO_EF.
# =============================================================================

# Faixa no estado ou na região, como complemento de "situa-se na faixa ..."
.ef_faixa_loc <- c(`fronteira` = "da fronteira", `quartil superior` = "do quartil superior",
                   `terceiro quartil` = "do terceiro quartil", `segundo quartil` = "do segundo quartil",
                   `quartil inferior` = "do quartil inferior")
.ef_tendencia <- c(`sem tendência definida` = "sem tendência definida", `melhora consistente` = "com melhora consistente",
                   `piora consistente` = "com piora consistente")
.ef_sinal <- c(`registro a verificar` = "registro a verificar",
               `sem comparável em algum insumo` = "ausência de comparável em algum insumo",
               `diagnóstico ordem-m` = "diagnóstico de robustez de ordem-m",
               `referência com alavancagem` = "referência com alavancagem")
.ef_motivo <- c(`quebra de registro na série` = "quebra de registro na série",
                `SISAB com meses insuficientes` = "meses insuficientes no SISAB",
                `SISAB com valores implausíveis` = "valores implausíveis no SISAB")
.ef_faixas_re <- "fronteira|quartil superior|terceiro quartil|segundo quartil|quartil inferior"

# Cada família: id, expressão regular ancorada e função que recebe os grupos capturados (g[1], g[2], ...)
# e devolve a redação nova (ou NULL, quando um trecho capturado não pertence ao vocabulário mapeado).
REDACAO_TEXTO_PADRAO <- list(
  list(id = "F01", re = "^Em (\\d{4}), (.+) está entre as melhores práticas do estado neste modelo \\(fronteira; escore corrigido (.+?), IC 95% de (.+?) a (.+?)\\) e serve de referência para (\\d+) (municípios?)\\.$",
       f = function(g) sprintf("Em %s, %s situa-se entre as melhores práticas do estado neste modelo, isto é, na fronteira, com escore corrigido de %s (intervalo de confiança de 95%%: %s a %s), e serve de referência para %s %s.",
                               g[1], g[2], g[3], g[4], g[5], g[6], g[7])),
  list(id = "F02", re = "^Em (\\d{4}), (.+) está entre as melhores práticas do estado neste modelo \\(fronteira; escore corrigido (.+?), IC 95% de (.+?) a (.+?)\\)\\.$",
       f = function(g) sprintf("Em %s, %s situa-se entre as melhores práticas do estado neste modelo, isto é, na fronteira, com escore corrigido de %s (intervalo de confiança de 95%%: %s a %s).",
                               g[1], g[2], g[3], g[4], g[5])),
  list(id = "F03", re = "^Em (\\d{4}), (.+) produziu cerca de (.+?)% a menos do que as melhores práticas comparáveis permitiriam com os mesmos recursos \\(escore corrigido (.+?), IC 95% de (.+?) a (.+?); original (.+?)\\)\\.$",
       f = function(g) sprintf("Em %s, a produção de %s situou-se cerca de %s%% abaixo do que as melhores práticas comparáveis permitiriam alcançar com os mesmos recursos, com escore corrigido de %s (intervalo de confiança de 95%%: %s a %s) e escore original de %s.",
                               g[1], g[2], g[3], g[4], g[5], g[6], g[7])),
  list(id = "F04", re = "^Sem novos recursos, a produção poderia crescer cerca de (.+?)% \\(entre (.+?)% e (.+?)%\\)\\.$",
       f = function(g) sprintf("Sem novos recursos, a produção poderia crescer cerca de %s%%, com intervalo entre %s%% e %s%%.", g[1], g[2], g[3])),
  list(id = "F05", re = "^A posição na fronteira decorre da ausência de comparável em algum insumo \\(supereficiência infactível\\): leitura com reserva\\.$",
       f = function(g) "A posição na fronteira decorre da ausência de comparável em algum insumo (supereficiência infactível), razão pela qual deve ser interpretada com reserva."),
  list(id = "F06", re = paste0("^Faixa no estado( \\(entre os municípios do grupo '(com leito|sem leito)'\\))?: (", .ef_faixas_re,
                               ")( \\(o intervalo cruza a faixa vizinha\\))?; na região (.+?): (", .ef_faixas_re,
                               "|sem posição \\(poucos municípios avaliados fora da fronteira na região: n = (\\d+)\\))\\.$"),
       f = function(g) {
         estado <- paste0("No estado", if (nzchar(g[1])) sprintf(", entre os municípios do grupo '%s'", g[2]) else "",
                          ", o município situa-se na faixa ", .ef_faixa_loc[[g[3]]],
                          if (nzchar(g[4])) ", e o intervalo de confiança cruza a faixa vizinha" else "")
         regiao <- if (startsWith(g[6], "sem posição"))
           sprintf("na região %s, não se atribui posição, por haver poucos municípios avaliados fora da fronteira na região (n = %s)", g[5], g[7])
           else sprintf("na região %s, situa-se na faixa %s", g[5], .ef_faixa_loc[[g[6]]])
         paste0(estado, "; ", regiao, ".")
       }),
  list(id = "F07", re = "^Municípios de referência plausíveis: (.+); par mais semelhante: (.+)\\.$",
       f = function(g) {
         n <- length(strsplit(g[1], ", ", fixed = TRUE)[[1]])
         if (n == 1) sprintf("Identifica-se o seguinte município de referência plausível: %s; o par mais semelhante é %s.", g[1], g[2])
         else sprintf("Identificam-se os seguintes municípios de referência plausíveis: %s; o par mais semelhante é %s.", g[1], g[2])
       }),
  list(id = "F08", re = "^Escore esperado pelo contexto \\((.+?)\\): (.+?); no segundo estágio \\(escore corrigido (.+?)\\), o município fica (.+?) (acima|abaixo) do esperado\\.$",
       f = function(g) sprintf("O escore esperado pelo contexto (%s) é de %s; no segundo estágio, com escore corrigido de %s, o município situa-se %s %s do esperado.",
                               g[1], g[2], g[3], g[4], g[5])),
  list(id = "F09", re = "^Evolução (\\d{4})–(\\d{4}): aproximação às melhores práticas \\(componente de gestão\\) (.+?)% ao ano \\((sem tendência definida|melhora consistente|piora consistente)\\)\\.$",
       f = function(g) sprintf("No período %s–%s, a aproximação às melhores práticas (componente de gestão) foi de %s%% ao ano, %s.",
                               g[1], g[2], g[3], .ef_tendencia[[g[4]]])),
  list(id = "F10", re = "^Sinalizações: (.+)\\.$",
       f = function(g) {
         s <- strsplit(g[1], "; ", fixed = TRUE)[[1]]
         if (!all(s %in% names(.ef_sinal))) return(NULL)
         s <- unname(.ef_sinal[s])
         if (length(s) == 1) sprintf("A ficha apresenta a seguinte sinalização: %s.", s)
         else sprintf("A ficha apresenta as seguintes sinalizações: %s.", paste(s, collapse = "; "))
       }),
  list(id = "F11", re = "^Sem hospital SUS no município: internações locais iguais a zero por configuração da rede \\(meta de internações informativa\\)\\.$",
       f = function(g) "Na ausência de hospital SUS no município, as internações locais são iguais a zero por configuração da rede, e a meta de internações tem caráter apenas informativo."),
  list(id = "F12", re = "^Polo de alta complexidade: parte dos insumos atende à alta complexidade \\(escore de média complexidade conservador\\)\\.$",
       f = function(g) "Por se tratar de polo de alta complexidade, parte dos insumos atende à alta complexidade, razão pela qual o escore de média complexidade é conservador."),
  list(id = "F13", re = "^Os dados de origem devem ser verificados \\(CNES/SIOPS/SISAB\\) antes de qualquer leitura; as sinalizações da ficha permanecem válidas\\.$",
       f = function(g) "Os dados de origem devem ser verificados (CNES/SIOPS/SISAB) antes de qualquer leitura; as sinalizações da ficha permanecem válidas."),
  list(id = "F14", re = "^(.+), (\\d{4}): escore não publicado — escore não publicado: (quebra de registro na série|SISAB com meses insuficientes|SISAB com valores implausíveis) — registro a verificar na origem\\.$",
       f = function(g) sprintf("Em %s, o escore de %s não é publicado, em razão de %s, e o registro deve ser verificado na origem.", g[2], g[1], .ef_motivo[[g[3]]])),
  list(id = "F15", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(não elegível ao (M\\d+): sem hospital SUS no município \\(internações de média complexidade locais iguais a zero; o modelo avalia só os municípios com produção hospitalar de média complexidade nos seis anos — ver modelo da ótica do acesso, ótica de acesso\\)\\)\\.$",
       f = function(g) sprintf("Em %s, %s não é avaliado neste modelo, uma vez que não é elegível ao %s por não dispor de hospital SUS: as internações de média complexidade locais são iguais a zero, e o modelo avalia apenas os municípios com produção hospitalar de média complexidade nos seis anos; a esse respeito, consulte-se o modelo da ótica do acesso.",
                               g[2], g[1], g[3])),
  list(id = "F16", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(excluído da estimação: despesa de média complexidade \\(subfunção (\\d+)\\) igual a zero no ano(; o município-ano entra só num teste de sensibilidade, sem escore publicado)?\\)\\.$",
       f = function(g) sprintf("Em %s, %s não é avaliado neste modelo, uma vez que foi excluído da estimação por apresentar despesa de média complexidade (subfunção %s) igual a zero no ano%s.",
                               g[2], g[1], g[3], if (nzchar(g[4])) "; o município-ano integra apenas um teste de sensibilidade, sem escore publicado" else "")),
  list(id = "F17", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(município instalado em (\\S+) \\((.+)\\): sem dados próprios antes de (\\d{4})\\)\\.$",
       f = function(g) if (!identical(g[1], g[4])) NULL else
         sprintf("Em %s, %s não é avaliado neste modelo, uma vez que o município foi instalado em %s e não dispõe de dados próprios antes de %s.", g[2], g[1], g[3], g[5])),
  list(id = "F18", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(não elegível ao (M\\d+): internações de média complexidade locais iguais a zero em pelo menos um dos anos (\\d{4})–(\\d{4}) \\(ver modelo da ótica do acesso, ótica de acesso\\)\\)\\.$",
       f = function(g) sprintf("Em %s, %s não é avaliado neste modelo, uma vez que não é elegível ao %s: as internações de média complexidade locais são iguais a zero em pelo menos um dos anos %s–%s; a esse respeito, consulte-se o modelo da ótica do acesso.",
                               g[2], g[1], g[3], g[4], g[5])),
  list(id = "F19", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(não elegível ao (M\\d+): município instalado em (\\S+), sem série própria de internações de média complexidade locais\\)\\.$",
       f = function(g) sprintf("Em %s, %s não é avaliado neste modelo, uma vez que não é elegível ao %s: o município foi instalado em %s e não dispõe de série própria de internações de média complexidade locais.",
                               g[2], g[1], g[3], g[4])),
  list(id = "F20", re = "^(.+), (\\d{4}): sem avaliação neste modelo \\(fora do (M\\d+)-acesso: o modelo-espelho avalia os (\\d+) municípios do painel; (.+), instalado em (\\S+), não tem série própria de internações de residentes \\(reagregado ao município de origem no Malmquist\\)\\)\\.$",
       f = function(g) sprintf("Em %s, %s não é avaliado neste modelo, uma vez que não integra o %s-acesso: o modelo-espelho avalia os %s municípios do painel, e %s, instalado em %s, não dispõe de série própria de internações de residentes (reagregado ao município de origem no Malmquist).",
                               g[2], g[1], g[3], g[4], g[5], g[6])),
  list(id = "F21", re = "^Hospital de outra esfera: despesa (\\d+) baixa com internações locais relevantes \\(nota informativa; não restringe pares\\)\\.$",
       f = function(g) sprintf("Registra-se hospital de outra esfera, com despesa %s baixa e internações locais relevantes (nota informativa, que não restringe os pares).", g[1])),
  list(id = "F22", re = "^Primeiro exercício do município: registro possivelmente parcial \\(produtos SISAB anualizados\\); escore publicável com marca 'parcial'\\.$",
       f = function(g) "Por se tratar do primeiro exercício do município, o registro é possivelmente parcial (produtos do SISAB anualizados), e o escore é publicável com a marca 'parcial'."),
  list(id = "F23", re = "^Flag de rede 'sem hospital SUS' ativa apesar de internações de média complexidade locais registradas no SIH: configuração da rede a verificar na origem \\(CNES/SIH\\)\\.$",
       f = function(g) "A marcação de rede 'sem hospital SUS' está ativa, apesar de haver internações de média complexidade locais registradas no SIH, de modo que a configuração da rede deve ser verificada na origem (CNES/SIH).")
)

# Aplica a primeira família cuja expressão casa com a frase inteira; devolve list(txt, id) (id = NA sem mapeamento)
.redigir_frase <- function(s, familias) {
  for (fam in familias) {
    m <- regmatches(s, regexec(fam$re, s, perl = TRUE))[[1]]
    if (length(m)) {
      out <- fam$f(m[-1])
      if (!is.null(out)) return(list(txt = out, id = fam$id))
    }
  }
  list(txt = s, id = NA_character_)
}

# Divide o texto em frases: ponto ou parêntese de fechamento seguido de espaço e maiúscula
.dividir_frases <- function(t) strsplit(t, "(?<=[.)])\\s+(?=[A-ZÁÉÍÓÚÂÊÔÃÕÇ])", perl = TRUE)[[1]]

# Texto-padrão da ficha municipal em redação científica. Com detalhe = TRUE, devolve também as famílias
# aplicadas (uso da conferência).
redigir_texto_padrao <- function(x, detalhe = FALSE) {
  res <- lapply(x, function(t) {
    if (is.na(t) || !nzchar(t)) return(list(txt = t, ids = character(0)))
    r <- lapply(.dividir_frases(t), .redigir_frase, familias = REDACAO_TEXTO_PADRAO)
    ids <- vapply(r, function(z) z$id, character(1))
    if (anyNA(ids) && !detalhe) aviso("redação v0.5: frase do texto-padrão sem mapeamento, exibida como está: %s",
                                      .dividir_frases(t)[is.na(ids)][1])
    list(txt = paste(vapply(r, function(z) z$txt, character(1)), collapse = " "), ids = ids)
  })
  if (detalhe) return(res)
  vapply(res, function(z) z$txt, character(1), USE.NAMES = FALSE)
}

# Nota de evolução (linha "Evolução" do detalhe das tabelas da seção Eficiência): texto completo
# composto por até três partes, mapeadas como um todo.
#   E1 "o deslocamento das melhores práticas (TC) fica no relatório técnico, com nota sobre o crescimento
#       de registro do CNES após <ano>" -> "o deslocamento das melhores práticas (TC) é apresentado no
#       relatório técnico, com nota sobre o crescimento do registro no CNES após <ano>"
#   E2 "transição(ões) com registro marcado (<transições>): excluída(s) das médias regionais; leitura com
#       reserva; " -> "a(s) transição(ões) com registro marcado (<transições>) foi(ram) excluída(s) das
#       médias regionais e deve(m) ser interpretada(s) com reserva; "
#   E3 "série <ano> inclui a parcela de <mun> (instalado em <ano>; reagregação ao município de origem); "
#       -> "a série de <ano> inclui a parcela de <mun> (instalado em <ano>, com reagregação ao município
#       de origem); "
#   E4 "sem série própria: município instalado em <ano> (reagregado a <municípios> no painel do Malmquist)"
#       -> "não há série própria, uma vez que o município foi instalado em <ano> (reagregado a <municípios>
#       no painel do Malmquist)"
.re_e1 <- "o deslocamento das melhores práticas \\(TC\\) fica no relatório técnico, com nota sobre o crescimento de registro do CNES após (\\d{4})"
REDACAO_NOTA_EVOLUCAO <- list(
  list(id = "E1", re = paste0("^", .re_e1, "$"),
       f = function(g) sprintf("o deslocamento das melhores práticas (TC) é apresentado no relatório técnico, com nota sobre o crescimento do registro no CNES após %s", g[1])),
  list(id = "E2", re = paste0("^(transição|transições) com registro marcado \\(([^)]+)\\): (excluída|excluídas) das médias regionais; leitura com reserva; ", .re_e1, "$"),
       f = function(g) {
         if ((g[1] == "transição") != (g[3] == "excluída")) return(NULL)
         sprintf("%s com registro marcado (%s) %s das médias regionais e %s com reserva; o deslocamento das melhores práticas (TC) é apresentado no relatório técnico, com nota sobre o crescimento do registro no CNES após %s",
                 if (g[1] == "transição") "a transição" else "as transições", g[2],
                 if (g[1] == "transição") "foi excluída" else "foram excluídas",
                 if (g[1] == "transição") "deve ser interpretada" else "devem ser interpretadas", g[4])
       }),
  list(id = "E3", re = paste0("^série (\\d{4}) inclui a parcela de (.+?) \\(instalado em (\\d{4}); reagregação ao município de origem\\); ", .re_e1, "$"),
       f = function(g) sprintf("a série de %s inclui a parcela de %s (instalado em %s, com reagregação ao município de origem); o deslocamento das melhores práticas (TC) é apresentado no relatório técnico, com nota sobre o crescimento do registro no CNES após %s",
                               g[1], g[2], g[3], g[4])),
  list(id = "E4", re = "^sem série própria: município instalado em (\\d{4}) \\(reagregado a (.+) no painel do Malmquist\\)$",
       f = function(g) sprintf("não há série própria, uma vez que o município foi instalado em %s (reagregado a %s no painel do Malmquist)", g[1], g[2]))
)
redigir_nota_evolucao <- function(x) vapply(x, function(t) {
  if (is.na(t) || !nzchar(t)) return(t)
  r <- .redigir_frase(t, REDACAO_NOTA_EVOLUCAO)
  if (is.na(r$id)) aviso("redação v0.5: nota de evolução sem mapeamento, exibida como está: %s", t)
  r$txt
}, character(1), USE.NAMES = FALSE)

# Nota de versão da estimação (metadados.csv, item nota_versao): mapeamento do texto exato (V1).
# O prefixo "Versão 2.1 (16/10/2026):" é mantido, porque a caixa da seção Eficiência o exibe em negrito.
REDACAO_NOTA_VERSAO <- c(
  `Versão 2.1 (16/10/2026): o insumo de agentes comunitários de saúde do modelo de atenção básica passou a contar apenas o ACS (CBO 515105); a versão 2 somava toda a família 5151, que inclui agentes de combate às endemias e agentes indígenas, e isso penalizava municípios com esses profissionais. Os demais modelos não mudaram.` =
    "Versão 2.1 (16/10/2026): o insumo de agentes comunitários de saúde do modelo de atenção básica passou a contabilizar apenas o ACS (CBO 515105). A versão 2 somava toda a família 5151, que inclui agentes de combate às endemias e agentes indígenas, o que penalizava os municípios com esses profissionais. Os demais modelos permaneceram inalterados.")
redigir_nota_versao_ef <- function(x) {
  if (length(x) != 1 || is.na(x) || !nzchar(x)) return(x)
  if (x %in% names(REDACAO_NOTA_VERSAO)) return(unname(REDACAO_NOTA_VERSAO[[x]]))
  aviso("redação v0.5: nota de versão sem mapeamento, exibida como está")
  x
}

# Descrições do catálogo de arquivos de eficiência (DESCR de scripts/06_preparar_eficiencia.py,
# gravadas em catalogo_eficiencia.csv): mapeamento do texto exato, arquivo a arquivo (D01–D18).
# As descrições já em redação adequada (pares_hospital, insumos_produtos_hospital, painel_ac_macro,
# especificacoes_modelos) mapeiam para si mesmas.
REDACAO_DESCRICAO_EF <- c(
  `Fichas municipais de eficiência: uma linha por município, modelo (M1 atenção básica, M0 consolidado, M2 média complexidade, M2A média complexidade pela ótica do acesso) e ano: escore corrigido com intervalo de confiança, faixa, posição na região/macrorregião/estado, escore esperado pelo contexto, pares, evolução (Malmquist), indicadores de resultado, equidade, sinais de registro e frase-síntese.` =
    "Fichas municipais de eficiência, com uma linha por município, modelo (M1, atenção básica; M0, consolidado; M2, média complexidade; M2A, média complexidade pela ótica do acesso) e ano, que reúnem o escore corrigido com intervalo de confiança, a faixa, a posição na região, na macrorregião e no estado, o escore esperado pelo contexto, os pares, a evolução (Malmquist), os indicadores de resultado, a equidade, os sinais de registro e a frase-síntese.",
  `Metas por variável (2025): observado, meta plena, meta intermediária (metade da distância), potencial de melhoria em unidades, % e R$ de 2025, por mil habitantes e em valores absolutos.` =
    "Metas por variável (2025), com o valor observado, a meta plena, a meta intermediária (metade da distância) e o potencial de melhoria em unidades, em % e em R$ de 2025, por mil habitantes e em valores absolutos.",
  `Até 3 municípios de referência plausíveis por município e modelo (2025), com peso na projeção e indicação do par mais semelhante. Unidades na fronteira não têm pares, salvo quando a fronteira decorre de falta de comparável em algum recurso (referência alternativa).` =
    "Até 3 municípios de referência plausíveis por município e modelo (2025), com o peso na projeção e a indicação do par mais semelhante. As unidades na fronteira não têm pares, salvo quando a posição na fronteira decorre da falta de comparável em algum recurso (referência alternativa).",
  `Fichas dos hospitais SUS (CNES): escore com IC, faixa, posição no grupo/região/estado, escore esperado, evolução, mortalidade hospitalar padronizada, perfil de oferta e sinais.` =
    "Fichas dos hospitais SUS (CNES), que reúnem o escore com intervalo de confiança (IC), a faixa, a posição no grupo, na região e no estado, o escore esperado, a evolução, a mortalidade hospitalar padronizada, o perfil de oferta e os sinais.",
  `Metas dos hospitais por variável (2025): observado, meta plena, meta intermediária, potencial.` =
    "Metas dos hospitais por variável (2025), com o valor observado, a meta plena, a meta intermediária e o potencial.",
  `Até 3 hospitais de referência plausíveis por hospital (2025).` =
    "Até 3 hospitais de referência plausíveis por hospital (2025).",
  `Valores observados das variáveis (recursos e produção) da especificação principal do modelo de hospitais, por hospital e ano.` =
    "Valores observados das variáveis (recursos e produção) da especificação principal do modelo de hospitais, por hospital e ano.",
  `Painel regional de acesso e produção de alta complexidade (16 regiões de saúde): internações e procedimentos de residentes e realizados na região, autossuficiência, capacidade (UTI validada, equipamentos, habilitações), despesa e tendência do acesso.` =
    "Painel regional de acesso e produção de alta complexidade (16 regiões de saúde), que reúne as internações e os procedimentos de residentes e os realizados na região, a autossuficiência, a capacidade (UTI validada, equipamentos e habilitações), a despesa e a tendência do acesso.",
  `Quadrantes acesso × autossuficiência em alta complexidade por região de saúde.` =
    "Quadrantes de acesso × autossuficiência em alta complexidade, por região de saúde.",
  `Painel de alta complexidade por macrorregião de saúde.` =
    "Painel de alta complexidade por macrorregião de saúde.",
  `Fichas regionais de alta complexidade: painel de acesso e, para as 3 regiões publicáveis, o escore diagnóstico com IC.` =
    "Fichas regionais de alta complexidade, com o painel de acesso e, para as 3 regiões publicáveis, o escore diagnóstico com intervalo de confiança (IC).",
  `Resumo por modelo, grupo e ano: unidades avaliadas, escore médio e mediano, distribuição por faixa e Malmquist médio da transição.` =
    "Resumo por modelo, grupo e ano, com as unidades avaliadas, o escore médio e o mediano, a distribuição por faixa e o Malmquist médio da transição.",
  `Malmquist agregado (média geométrica) por modelo, região de saúde e estado: transições anuais e janelas 2020–2022, 2022–2025 e 2020–2025.` =
    "Índice de Malmquist agregado (média geométrica) por modelo, região de saúde e estado, para as transições anuais e para as janelas 2020–2022, 2022–2025 e 2020–2025.",
  `Recursos (insumos) e produção (produtos) de cada modelo na especificação principal vigente, com nomes gerenciais, unidades e fontes.` =
    "Recursos (insumos) e produção (produtos) de cada modelo na especificação principal vigente, com nomes gerenciais, unidades e fontes.",
  `Robustez: correlação de Spearman e mudança de tercil entre cada variante e a especificação principal.` =
    "Análise de robustez, com a correlação de Spearman e a mudança de tercil entre cada variante e a especificação principal.",
  `Parâmetros e limiares de trabalho da estimação v2.1 (ex.: fração da meta intermediária, limiares de comparabilidade).` =
    "Parâmetros e limiares de trabalho da estimação v2.1, como a fração da meta intermediária e os limiares de comparabilidade.",
  `Metadados da geração: versão dos resultados, data, nota de versão, especificações principais e contagens.` =
    "Metadados da geração, com a versão dos resultados, a data, a nota de versão, as especificações principais e as contagens.",
  `Dicionário de todos os campos dos arquivos de eficiência: nome gerencial, unidade, definição e fonte.` =
    "Dicionário de todos os campos dos arquivos de eficiência, com o nome gerencial, a unidade, a definição e a fonte.")
redigir_descricao_ef <- function(x) vapply(x, function(t) {
  if (is.na(t) || !nzchar(t)) return(t)
  if (t %in% names(REDACAO_DESCRICAO_EF)) return(unname(REDACAO_DESCRICAO_EF[[t]]))
  aviso("redação v0.5: descrição de arquivo de eficiência sem mapeamento, exibida como está: %s", substr(t, 1, 60))
  t
}, character(1), USE.NAMES = FALSE)
