# dados_site/eficiencia/ — dicionário curto

Arquivos gerados por `scripts/06_preparar_eficiencia.py` a partir dos resultados da **versão 2.1** da estimação DEA/Malmquist (schema `dea` do PostgreSQL local, `versao = 'v2.1'`, somente leitura; Resultados DEA v2.1 (16/10/2026)). Versão 2.1 (16/10/2026): o insumo de agentes comunitários de saúde do modelo de atenção básica passou a contar apenas o ACS (CBO 515105); a versão 2 somava toda a família 5151, que inclui agentes de combate às endemias e agentes indígenas, e isso penalizava municípios com esses profissionais. Os demais modelos não mudaram. A versão anterior (v2, 08/10/2026) continua no banco e pode ser regerada com `--versao v2`. CSV em UTF-8, separador vírgula, decimal ponto, vazio = indisponível ou não publicável. Booleanos em 0/1. `cnes` é texto de 7 dígitos (ler com `colClasses = list(character = 'cnes')` no `data.table::fread`). Uma cópia de cada arquivo fica em `arquivos/dados/eficiencia/` para download, com `catalogo_eficiencia.csv`.

Reexecutar o script sempre que o DEA for reprocessado: a especificação principal de cada modelo é lida do banco no momento da execução (`dea.especificacoes`, `principal = TRUE`), inclusive a do modelo de hospitais; nenhum nome de produto é fixado no código.

| arquivo | conteúdo | chave | período | linhas × colunas |
|---|---|---|---|---|
| `fichas_municipio.csv` | Fichas municipais de eficiência: uma linha por município, modelo (M1 atenção básica, M0 consolidado, M2 média complexidade, M2A média complexidade pela ótica do acesso) e ano: escore corrigido com intervalo de confiança, faixa, posição na região/macrorregião/estado, escore esperado pelo contexto, pares, evolução (Malmquist), indicadores de resultado, equidade, sinais de registro e frase-síntese. | cod_mun6 + modelo + ano | 2020–2025 | 3408 × 125 |
| `metas_municipio.csv` | Metas por variável (2025): observado, meta plena, meta intermediária (metade da distância), potencial de melhoria em unidades, % e R$ de 2025, por mil habitantes e em valores absolutos. | cod_mun6 + modelo + ano + variavel | 2025 | 3271 × 27 |
| `pares_municipio.csv` | Até 3 municípios de referência plausíveis por município e modelo (2025), com peso na projeção e indicação do par mais semelhante. Unidades na fronteira não têm pares, salvo quando a fronteira decorre de falta de comparável em algum recurso (referência alternativa). | cod_mun6 + modelo + ano + ordem | 2025 | 935 × 14 |
| `fichas_hospital.csv` | Fichas dos hospitais SUS (CNES): escore com IC, faixa, posição no grupo/região/estado, escore esperado, evolução, mortalidade hospitalar padronizada, perfil de oferta e sinais. | cnes + ano | 2020–2025 | 546 × 132 |
| `metas_hospital.csv` | Metas dos hospitais por variável (2025): observado, meta plena, meta intermediária, potencial. | cnes + ano + variavel | 2025 | 426 × 21 |
| `pares_hospital.csv` | Até 3 hospitais de referência plausíveis por hospital (2025). | cnes + ano + ordem | 2025 | 111 × 13 |
| `insumos_produtos_hospital.csv` | Valores observados das variáveis (recursos e produção) da especificação principal do modelo de hospitais, por hospital e ano. | cnes + ano + variavel | 2020–2025 | 3276 × 9 |
| `painel_ac_regiao.csv` | Painel regional de acesso e produção de alta complexidade (16 regiões de saúde): internações e procedimentos de residentes e realizados na região, autossuficiência, capacidade (UTI validada, equipamentos, habilitações), despesa e tendência do acesso. | co_regsaud + ano | 2020–2025 | 96 × 62 |
| `quadrantes_ac.csv` | Quadrantes acesso × autossuficiência em alta complexidade por região de saúde. | co_regsaud + ano | 2020–2025 | 96 × 12 |
| `painel_ac_macro.csv` | Painel de alta complexidade por macrorregião de saúde. | co_macsaud + ano | 2020–2025 | 36 × 33 |
| `fichas_regiao.csv` | Fichas regionais de alta complexidade: painel de acesso e, para as 3 regiões publicáveis, o escore diagnóstico com IC. | co_regsaud + ano | 2020–2025 | 96 × 94 |
| `resumo_modelos.csv` | Resumo por modelo, grupo e ano: unidades avaliadas, escore médio e mediano, distribuição por faixa e Malmquist médio da transição. | modelo + grupo + ano | 2020–2025 | 60 × 26 |
| `malmquist_regiao.csv` | Malmquist agregado (média geométrica) por modelo, região de saúde e estado: transições anuais e janelas 2020–2022, 2022–2025 e 2020–2025. | modelo + grupo + nivel + co_regsaud + periodo | 2020–2025 | 1118 × 18 |
| `especificacoes_modelos.csv` | Recursos (insumos) e produção (produtos) de cada modelo na especificação principal vigente, com nomes gerenciais, unidades e fontes. | modelo + grupo + tipo + variavel | — | 39 × 16 |
| `sensibilidade.csv` | Robustez: correlação de Spearman e mudança de tercil entre cada variante e a especificação principal. | modelo + variante + ano/periodo | 2020–2025 | 761 × 25 |
| `parametros.csv` | Parâmetros e limiares de trabalho da estimação v2.1 (ex.: fração da meta intermediária, limiares de comparabilidade). | chave + modelo | — | 97 × 10 |
| `metadados.csv` | Metadados da geração: versão dos resultados, data, nota de versão, especificações principais e contagens. | item | — | 22 × 2 |
| `dicionario_eficiencia.csv` | Dicionário de todos os campos dos arquivos de eficiência: nome gerencial, unidade, definição e fonte. | arquivo + campo | — | 639 × 6 |

## Regras

- **Faixas, não ranking**: `faixa` = quartil do escore corrigido entre os publicáveis do ano no estado ('fronteira' quando o escore original = 1). `posicao_regiao` e `posicao_macro` usam a mesma régua dentro do recorte (fronteira à parte; quartis entre os avaliados fora da fronteira; sem posição com menos de 4). `ic_cruza_faixa = 1` indica que o intervalo de confiança alcança a faixa vizinha (posição incerta).
- **Escore corrigido** (`escore_bc`, IC em `ic_inf`–`ic_sup`): escore BCC orientado ao produto corrigido do viés pelo bootstrap; o escore original (`escore_bcc`) fica fora do IC por construção. Linhas com `situacao` ≠ 'avaliado' não têm escore (motivo em `motivo_situacao`).
- **Escore esperado pelo contexto** (`escore_esperado`) e **diferença** (`residuo_escore`): a diferença usa o escore corrigido do segundo estágio (`escore_bc_2estagio`), não o escore publicado; não é a subtração direta dos dois.
- **Lacunas esperadas** (não são erro): sem escore esperado pelo contexto na média complexidade pela ótica do acesso (M2A, sem segundo estágio), nos hospitais fora do painel balanceado (`especificacao_escore = n_nao_balanceado`) e em Boa Esperança do Norte; sem tendência 2022–2025 quando há menos de duas transições publicáveis (transições marcadas, hospitais fora do painel, primeiro exercício). Na ótica do acesso há duas fronteiras (`grupo`: com e sem leito SUS) e a faixa é calculada dentro de cada uma.
- **Metas**: `meta_radial` = meta plena (projeção na fronteira com folgas); `meta_intermediaria` = metade da distância entre o observado e a meta plena (limiar homologado em 08/10/2026). Colunas sem sufixo estão por mil habitantes (municípios); `*_abs` em valores absolutos do ano. `potencial_unidades` é absoluto (positivo nos produtos, negativo nos insumos). Exibir só `meta_publicavel = 1`.
- **Pares** (`pares_*.csv`): até 3 por unidade, por peso decrescente, da fronteira restrita às unidades elegíveis como referência (regra da ESPEC_V2: a infactibilidade não restringe a elegibilidade). O par mais semelhante (banda de porte) está nas fichas (`par_mais_semelhante_*`); em 1 casos de 2025 ele não está entre os 3 de maior peso.
- **Malmquist**: fichas trazem MI e EC (acumulados 2020–2025 e médias anuais 2020–2022 e 2022–2025). O deslocamento tecnológico (TC) só é publicado como agregado (`resumo_modelos.csv`, `malmquist_regiao.csv`), com a nota de possível efeito do crescimento de registro no CNES após 2022. Transições marcadas (quebra de registro, SISAB incompleto) ficam fora das médias. Especificações usadas: M1 = `c_absoluto_crs`; M0 = `c_absoluto_crs`; M2 = `c_absoluto_crs`; M2A = `d2_acesso_hospitalar_c_absoluto_crs`; H = `c_absoluto_crs`.
- **Alta complexidade**: o produto gerencial é o painel regional (16 regiões). O escore diagnóstico (M3) é publicado só para as regiões com `publicavel_m3 = 1` (2025: Baixada Cuiabana, Sul Matogrossense, Teles Pires), ratificadas pelo coordenador em 08/10/2026.
- **Hospitais**: especificação principal vigente no banco: `principal` — produtos: Internações (MC + AC), Diárias de internação (todas); insumos: Leitos SUS, Médicos SUS, Equipe de enfermagem SUS (enfermeiros + técnicos), Equipamentos SUS em uso. Decisão do coordenador (08/10/2026): principal = internações totais + diárias totais; a anterior (internações MC + AC + diárias de UTI) vira variante.
- **Boa Esperança do Norte (510183)**: primeiro exercício em 2025 (`marca_parcial = 1`); fora dos modelos em 2020–2024.
- Regiões com nome sem o sufixo ' - MT'; macrorregiões como em `dados_site/municipios.csv`. Monetários em R$ de 2025 (IPCA).

## Validação (última execução)

- `M1_2025_municipios`: 142
- `M1_2025_avaliados`: 142
- `M0_2025_municipios`: 142
- `M0_2025_avaliados`: 142
- `M2_2025_municipios`: 142
- `M2_2025_avaliados`: 80
- `M2A_2025_municipios`: 142
- `M2A_2025_avaliados`: 141
- `metas_municipio.csv_violacoes_direcao`: 0
- `metas_hospital.csv_violacoes_direcao`: 0
- `fichas_municipio.csv_avaliados_sem_escore_esperado`: 806
- `fichas_municipio.csv_avaliados_sem_tendencia_ec_2022_2025`: 88
- `fichas_hospital.csv_avaliados_sem_escore_esperado`: 101
- `fichas_hospital.csv_avaliados_sem_tendencia_ec_2022_2025`: 101
- `regioes_publicaveis_m3_2025`: Baixada Cuiabana, Sul Matogrossense, Teles Pires
- `H_produtos_principal`: diarias, internacoes
- `H_produtos_nas_metas`: diarias, internacoes
- `pares_ocultados_fronteira_2025`: 5
- `n_vezes_referencia_recontadas_2025`: 93
- `pares_fora_top3`: 1
- `limpezas_texto_nulo`: 0
- `linhas_fichas_municipio.csv`: 3408
- `linhas_metas_municipio.csv`: 3271
- `linhas_pares_municipio.csv`: 935
- `linhas_fichas_hospital.csv`: 546
- `linhas_metas_hospital.csv`: 426
- `linhas_pares_hospital.csv`: 111
- `linhas_insumos_produtos_hospital.csv`: 3276
- `linhas_painel_ac_regiao.csv`: 96
- `linhas_quadrantes_ac.csv`: 96
- `linhas_painel_ac_macro.csv`: 36
- `linhas_fichas_regiao.csv`: 96
- `linhas_resumo_modelos.csv`: 60
- `linhas_malmquist_regiao.csv`: 1118
- `linhas_especificacoes_modelos.csv`: 39
- `linhas_sensibilidade.csv`: 761
- `linhas_parametros.csv`: 97
- `linhas_metadados.csv`: 22
- `linhas_dicionario_eficiencia.csv`: 639
- avisos: 0
- erros: 0
- gerado em: 16/10/2026 10:29
