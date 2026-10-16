# dados_site/ — dicionário curto

Arquivos gerados por `scripts/01_preparar_dados.py` a partir dos marts `mart.painel_dea_mun_ano`, `mart.painel_dea_hosp_ano`,
`mart.dim_municipio` (PostgreSQL local, somente leitura), da malha `arquivos/geo/mt_municipios_ibge_minima.geojson` e das sedes
municipais `sedes_municipais.csv` (gerado antes por `scripts/00_sedes_ibge.py` a partir do shapefile IBGE Localidades 2022 em `arquivos/geo/ibge_localidades_2022_mt/`).
CSV em UTF-8, separador vírgula, decimal ponto, vazio = indisponível. Janela: 2020–2025 (resultados SIM/SINASC até 2024).

| arquivo | conteúdo | chave |
|---|---|---|
| `municipios.csv` | 142 municípios: `cod_mun6`, `cod_ibge7`, `municipio`, `slug`, `co_regsaud`, `regiao_saude`, `co_macsaud`, `macrorregiao`, `populacao_2025`, `tem_hospital_sus_2025` | `cod_mun6` |
| `indicadores.csv` | catálogo de 46 indicadores: `id`, `rotulo`, `grupo`, `unidade`, `fmt`, `sentido`, `fonte`, `formula`, `nota`, `kpi`, `ano_max` (+ `descricao`, `ordem`, `nota_curta` = ressalva curta dos cartões) | `id` |
| `serie.csv` | formato longo municipal: `cod_mun6`, `indicador`, `ano`, `valor` (grade completa 142 × indicadores × 2020–`ano_max`) | `cod_mun6`+`indicador`+`ano` |
| `regioes.csv` | 16 regiões de saúde (CIR): códigos, nomes, macrorregião, `n_municipios`, `populacao_2025` | `co_regsaud` |
| `serie_regiao.csv` | agregados por região: `co_regsaud`, `indicador`, `ano`, `valor` | `co_regsaud`+`indicador`+`ano` |
| `serie_mt.csv` | agregado estadual: `indicador`, `ano`, `valor` (MT) e `mediana` (mediana dos municípios) | `indicador`+`ano` |
| `hospitais.csv` | hospitais SUS 2020–2025 (uma linha por CNES-ano): capacidade e produção; `n_meses` = competências do CNES em que o estabelecimento constou no ano (adicional ao contrato); `taxa_ocupacao_leitos_sus` em fração 0–1 | `cnes`+`ano` |
| `geo_mt.geojson` | malha mínima IBGE (141 polígonos) com `cod_mun6`, `municipio`, `co_regsaud`, `regiao_saude`, `codarea` | `cod_mun6` |
| `sedes_municipais.csv` | 142 sedes municipais: `cod_mun6`, `cod_ibge7`, `municipio` (nome IBGE), `lon`, `lat` (WGS84, 4 decimais), `fonte` — script 00 | `cod_mun6` |
| `centroides.csv` | `cod_mun6`, `lon`, `lat` — coordenada usada nas distâncias em linha reta: sede municipal (IBGE, Localidades do Brasil 2022), copiada de `sedes_municipais.csv` | `cod_mun6` |

## Deslocamento (script 02)

`fluxo_mun_ano.csv`, `fluxo_regiao_ano.csv`, `deslocamento_mun_ano.csv`, `polos_ano.csv`, `resumo_deslocamento_ano.csv`, `outras_uf_ano.csv`
(residentes de outras UF atendidos em MT) e `deslocamento_achados.md` seguem o contrato da seção 3 do briefing e contam só internações
em hospitais de MT (`trusted.aih_reduzida`, AIH tipo 1, ano da alta, 2020–2025).

### Internações de residentes de MT em outras UF (versão 0.3)

Lidas de `mart.fluxo_internacao_od_ano` (matriz origem-destino: SIH/SUS RD de MT + RD das 26 outras UF, filtrado a residentes de MT;
internação = AIH tipo 1 distinta; ano de `data_saida`). Com destino em MT, o mart reproduz exatamente as internações dos fluxos
(conferido pelo script, por ano e nível); com destino fora, reproduz as AIH tipo 1 distintas de `trusted.aih_reduzida_fora_mt`.
`valor_*` soma todas as linhas da AIH, inclusive as de continuação (regra do mart); os arquivos de fluxos da v0.1 somam só a AIH tipo 1.

| arquivo | conteúdo | chave |
|---|---|---|
| `fuga_resumo_ano.csv` | estado, por ano e nível (MC, AC, total): `internacoes_mt`, `internacoes_outra_uf`, `internacoes_total`, `pct_outra_uf`, `valor_mt`, `valor_outra_uf`, `pct_valor_outra_uf`, `pct_eletivas_mt`, `pct_eletivas_outra_uf`, `uf_principal`, `nome_uf_principal`, `pct_uf_principal`, `n_uf_destino`, `n_mun_destino`, `entrada_outra_uf` (residentes de outras UF internados em MT), `saldo_outra_uf` (entrada − saída) | `ano`+`nivel` |
| `fuga_uf_ano.csv` | estado, por ano, UF de destino e nível: `internacoes`, `internacoes_urgencia` (caráter ≠ eletivo), `diarias`, `valor_total`; grade completa 26 UF × 6 anos × 3 níveis | `ano`+`cod_uf`+`nivel` |
| `fuga_saldo_uf_ano.csv` | estado, por ano e UF: `entrada`, `saida`, `saldo` (entrada − saída) | `ano`+`cod_uf` |
| `fuga_regiao_ano.csv` | região de saúde de residência × ano: `internacoes_total_res` (MT + outras UF), `internacoes_outra_uf`, `pct_outra_uf`, o mesmo para a alta complexidade (`*_ac_*`), UF principal; `total_suprimido`, `ac_suprimida`, `nota_supressao` | `co_regsaud`+`ano` |
| `fuga_mun_periodo.csv` | município de residência, 2020–2025 somado: `internacoes_total_res`, `internacoes_outra_uf`, `pct_outra_uf`, UF principal; `total_suprimido`, `nota_supressao` | `cod_mun6` |
| `fuga_destinos_mun.csv` | 20 principais municípios de destino fora de MT, 2020–2025: `internacoes`, `pct_do_total_fora`, `internacoes_ac`, `pct_ac`, `ac_suprimida`, `nota_supressao` | `cod_mun6` |

**Supressão de células pequenas (escolha registrada em 16/10/2026).** Regra do Termo de Uso do pacote de dados da equipe (item 6:
"suprimindo células com menos de 5 casos"), aplicada aos recortes **subestaduais** novos (região de saúde, município de residência,
município de destino): contagens de 1 a 4 ficam vazias; zero é publicado. Supressão complementar, para que a célula escondida não
seja deduzida por diferença: (i) saem também o total da linha e o percentual (o total menos as internações em MT, publicadas nos
fluxos, devolveria o valor); (ii) a alta complexidade sai quando a média complexidade da mesma linha (total − AC) teria 1 a 4;
(iii) a UF principal só tem percentual quando a contagem dela e o restante têm 0 ou 5 ou mais; (iv) nunca fica uma só célula
suprimida por ano (regiões, diante do total estadual) nem por região de saúde (municípios, diante do total da região) — a menor
célula positiva do grupo é suprimida junto. As contagens de células suprimidas de cada execução ficam no log do script 02, que
interrompe a execução se sobrar contagem entre 1 e 4 nesses arquivos.
Os recortes estaduais (MT × UF de destino, saldo por UF) não têm supressão, como os demais arquivos estaduais do site.
Os arquivos de fluxos da versão 0.1 (`fluxo_mun_ano.csv` e derivados) não passam por essa regra.

## Regras de cálculo

- Valores municipais recalculados a partir das colunas brutas do mart (numerador/denominador do catálogo) e conferidos com os per capita
  pré-calculados do mart (diferença relativa < 0,5%). Razões com denominador zero ficam vazias (ex.: mortalidade hospitalar onde não há internação local).
- **Região e MT**: contagens são somadas; razões e percentuais são recalculados com os totais (soma dos numeradores / soma dos denominadores),
  não pela média dos municípios. Os percentuais do SINASC (`pct_prenatal_7mais`, `pct_baixo_peso`, `pct_cesarea`, `pct_mae_adolescente`)
  são ponderados por nascidos vivos, porque o mart não publica seus numeradores. `mediana` em `serie_mt.csv` é a mediana simples dos municípios com valor.
- `ano_max` = 2025 para todos os indicadores, exceto os de resultados (SIM/SINASC) e `doses_menor1_por_nv`, com 2024. `serie.csv` só traz anos até `ano_max`.
- **Boa Esperança do Norte (510183)** foi instalada em 2025: sem população e com valores vazios em 2020–2024; ausente na malha IBGE
  (sem polígono nos mapas), mas com a coordenada da sede (IBGE, Localidades 2022) em `centroides.csv`. `cod_ibge7` = 5101837, obtido pelo
  dígito verificador do IBGE (algoritmo validado nas 141 feições da malha) e confirmado nas Localidades 2022.
- `regiao_saude` = nome da CIR sem o sufixo " - MT"; `macrorregiao` em caixa normal (ex.: "Centro-Norte").
- Em `hospitais.csv`, `natureza_juridica` é o código CONCLA (ex.: 1244 = município; 3999 = associação privada); `esfera` traz a categoria legível.
  Hospitais sem produção no SIH no ano ficam com `internacoes` vazio (só CNES). Leitos e FTE são médias dos `n_meses` em que o CNES
  constou no ano: para reproduzir a média municipal do painel, pondere por `n_meses`/12. `taxa_ocupacao_leitos_sus` é fração 0–1 (o site exibe em %).
- Indicadores `pct_internacoes_fora_regiao` e `km_medio_internacao` (grupo deslocamento): incorporados de `deslocamento_mun_ano.csv`.
  Nos agregados regionais/estaduais, o percentual usa soma de `outra_regiao` / soma de `internacoes_res` e o km médio é ponderado por `internacoes_res`
  (colunas do arquivo de deslocamento). As distâncias são em linha reta entre as sedes municipais (IBGE), não rodoviárias; `km_medio_internacao`
  fica vazio quando o município não tem internação de residentes no ano (ex.: Boa Esperança do Norte).

## Downloads (`arquivos/dados/`)

`painel_municipal_2020_2025.csv` (largo: todas as variáveis do mart + indicadores derivados, uma linha por município-ano),
`serie_longa.csv` (serie.csv com nomes, grupo e rótulos), `indicadores_dicionario.csv` (= indicadores.csv),
`hospitais_sus_mt.csv` (todas as colunas de `painel_dea_hosp_ano`, 2020–2025), `regioes_saude_mt.csv` (regioes.csv + lista de municípios).
Internações em outras UF (script 05, cópias de `fuga_*.csv`): `residentes_mt_outras_uf_resumo_2020_2025.csv`, `residentes_mt_outras_uf_por_uf_2020_2025.csv`,
`saldo_internacoes_mt_outras_uf_2020_2025.csv`, `residentes_mt_outras_uf_regioes_2020_2025.csv`, `residentes_mt_outras_uf_municipios_2020_2025.csv`,
`residentes_mt_outras_uf_destinos_2020_2025.csv`.

Fontes: SIOPS (despesa liquidada, RREO), CNES (vínculos SUS em FTE 40 h, leitos, equipamentos, equipes; média anual), SISAB, SI-PNI (sem COVID),
SIA/SUS (procedimentos aprovados), SIH/SUS (AIH tipo 1, ano da alta), SIM e SINASC (por residência), IBGE (população). Os indicadores
municipais e os fluxos usam só SIH/SIA de MT; desde a versão 0.3, as internações de residentes de MT em hospitais de outras UF entram
apenas nos arquivos `fuga_*.csv` (SIH/SUS RD das 26 outras UF). Atendimentos ambulatoriais em outras UF não são observados.
