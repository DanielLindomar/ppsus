# Observatório PPSUS-MT

Site público do projeto **Gestão integrada no SUS: avaliação da eficiência na oferta e previsão da demanda de serviços públicos de saúde nos municípios de Mato Grosso** (Edital PPSUS 004/2025 FAPEMAT, processo FAPEMAT-PRO.0001999/2025). Executado pela UNEMAT, Campus de Sinop.

Publicado em: https://daniellindomar.github.io/ppsus/

Versão 0.5 (24/10/2026; revisão dos textos em linguagem científica, sem alteração dos valores ou dos resultados): dados e indicadores 2020–2025 dos 142 municípios, análise de deslocamento residência × atendimento (internações), com as internações de residentes de MT em hospitais de outros estados (SIH/SUS das outras 26 UF), e seção Eficiência — escores DEA e produtividade Malmquist (versão 2.1 da estimação: atenção básica reestimada com o insumo de agentes comunitários restrito ao ACS, CBO 515105; demais modelos da versão 2, de 08/10/2026) de municípios, hospitais SUS e regiões de saúde, com fichas no perfil de cada município. Desde a versão 0.4, três seções com resultados **preliminares**: Previsão (nowcast, previsão semanal e alerta das internações por doenças respiratórias, J00–J99, por região de saúde), Localização (onde abrir ou ampliar serviços; pilotos de atenção ao parto e UTI adulto, com demanda 2026–2030 provisória) e Judicialização (ações judiciais de saúde a partir do DataJud/CNJ). Na versão 0.5, corrige-se também a descrição do sinal de participação elevada da alta complexidade, que não caracteriza, por si só, polo de alta complexidade, nos perfis, na página Média complexidade e nos arquivos de eficiência (dicionário, fichas e metas).

## Como atualizar

Todos os comandos rodam pelo PowerShell, na raiz do repositório. Os scripts leem o PostgreSQL local (somente leitura) e gravam `dados_site/` e `arquivos/dados/`.

**Configuração local (uma vez por máquina).** Os scripts 01, 02 e 06 não fixam caminhos da máquina: o arquivo com a senha do PostgreSQL e os dicionários técnicos da estimação (v2 e v2.1) são lidos das variáveis de ambiente `PPSUS_PGPASS`, `PPSUS_DIC_V2` e `PPSUS_DIC_V21` ou, na falta delas, do arquivo `.env.local` na raiz (linhas `CHAVE=caminho`; fora do controle de versão — ver `scripts/config_local.py`). Os scripts 08, 10 e 11 (versão 0.4) leem as pastas de origem das frentes de pesquisa pelos argumentos indicados abaixo ou pelas chaves `PPSUS_A5_SITE`, `PPSUS_A5NC_SITE`, `PPSUS_JUD_ORIGEM` e `PPSUS_LOC_ORIGEM` (variável de ambiente ou `.env.local`).

1. **Preparar os dados e gerar as páginas** (nesta ordem):

   ```powershell
   python scripts/00_sedes_ibge.py              # sedes municipais (IBGE, Localidades 2022) → dados_site/sedes_municipais.csv (Python puro)
   python scripts/01_preparar_dados.py          # municipios, indicadores, series, hospitais, geo, centroides.csv (= sedes), downloads do contrato
   python scripts/02_preparar_deslocamento.py   # fluxos de internação, deslocamento por município, polos, resumo, outras UFs, achados e internações de residentes de MT em outras UF (fuga_*.csv, de mart.fluxo_internacao_od_ano)
   python scripts/01_preparar_dados.py          # de novo: incorpora pct_internacoes_fora_regiao e km_medio_internacao à serie.csv
   python scripts/06_preparar_eficiencia.py     # resultados DEA/Malmquist v2.1 (schema dea, versao='v2.1'; --versao v2 regera a anterior) → dados_site/eficiencia/ e arquivos/dados/eficiencia/
   python scripts/03_gerar_paginas.py           # municipios/<slug>.qmd, indicadores/<id>.qmd e arquivos/municipios/<slug>.csv
   python scripts/04_gerar_indicadores.py       # regrava indicadores/<id>.qmd só a partir do catálogo (remove ids que saíram dele)
   python scripts/08_preparar_previsao.py --origem-a5 <pasta a5/site> --origem-nowcast <pasta a5/nowcast/site>   # previsão (v0.4) → dados_site/previsao/ e arquivos/dados/previsao_*.csv
   python scripts/10_preparar_judicializacao.py --origem <pasta da frente J>      # judicialização (v0.4) → dados_site/judicializacao/ e arquivos/dados/judicializacao_*.csv
   python scripts/11_preparar_localizacao.py --origem <pasta localizacao/resultados/site>   # localização (v0.4) → dados_site/localizacao/ e arquivos/dados/localizacao_*.csv
   python scripts/05_downloads.py               # downloads complementares e catálogo (arquivos/dados/catalogo_arquivos.csv)
   ```

   Os scripts 08, 10 e 11 não acessam o banco: copiam os arquivos agregados que as frentes de pesquisa (previsão de demanda, judicialização e localização de serviços) já gravaram com supressão, conferem de novo colunas, versões, somas e a supressão de contagens de 1 a 4 (com supressão complementar) e só gravam se todas as conferências passarem; se alguma falhar, saem com código 1 sem gravar nada. O 10 também dissolve as comarcas em um GeoJSON leve; o 11 completa a supressão complementar quando a origem deixa célula dedutível, retira colunas que permitiriam recalcular células suprimidas e arredonda contagens modeladas ao inteiro. Cada pasta `dados_site/<seção>/` traz um manifesto com o SHA-256 dos arquivos de origem. Rode o 05 depois deles, para que o catálogo da página Dados inclua os arquivos novos.

   O script 00 lê o `.dbf` do shapefile `arquivos/geo/ibge_localidades_2022_mt/` (baixa o zip do IBGE se a pasta não existir) e grava as coordenadas das 142 sedes municipais; o script 01 copia essas coordenadas para `dados_site/centroides.csv` (nome do contrato), que o script 02 e as páginas usam em todas as distâncias — em linha reta entre as sedes, não rodoviárias. Os indicadores `pct_internacoes_fora_regiao` e `km_medio_internacao` vêm de `dados_site/deslocamento_mun_ano.csv` (script 02); por isso o script 01 roda duas vezes na primeira execução (na segunda ele encontra o arquivo e completa `serie.csv`, `serie_regiao.csv` e `serie_mt.csv`). Os scripts 03 e 04 não acessam o banco: o 03 gera as páginas de município (e também as de indicador) e os CSV por município; o 04 gera apenas as páginas de indicador a partir de `dados_site/indicadores.csv` e pode ser rodado sozinho sempre que o catálogo mudar. O script 05 só copia e enriquece arquivos de `dados_site/` (séries por região e MT, deslocamento, polos, sedes municipais, dicionário das 114 colunas do painel, malha com regiões de saúde) e gera o catálogo que a página Dados lê; rode-o sempre por último. Os scripts 00 a 05 completos levam cerca de 1 minuto.

2. **Renderizar e conferir localmente:** `quarto preview` (ou `quarto render` para o site inteiro — cerca de 200 páginas; `quarto render sobre.qmd` para uma página). Ao fim de cada render, `scripts/07_pos_render.py` (post-render do `_quarto.yml`) troca por `/` as barras invertidas que o Quarto grava no Windows em `src`/`href` e nos redirecionamentos.

3. **Publicar:** `quarto publish gh-pages` (renderiza e envia o HTML para o ramo `gh-pages`).

4. Registrar a mudança em "Novidades" (`index.qmd`) e atualizar a versão e a data no rodapé (`_quarto.yml`).

## Estrutura

| Pasta/arquivo | Conteúdo |
|---|---|
| `_quarto.yml`, `estilo.scss` | Configuração do site (menu, rodapé, tema) e estilo |
| `R/funcoes.R` | Biblioteca compartilhada: carregadores dos CSV, formatação pt-BR, consultas, cartões, gráficos SVG, mapas leaflet, tabelas reactable |
| `R/idioma.R` | Textos das tabelas interativas em português |
| `R/pag_*.R` | Funções específicas de uma página (não editar `funcoes.R` para isso) |
| `scripts/` | Preparação de dados (00 sedes IBGE; 01–02 PostgreSQL → `dados_site/`, `arquivos/dados/`; 06 eficiência; 08, 10 e 11 cópias conferidas das frentes de previsão, judicialização e localização), geração das páginas (03–05) e pós-render (07) |
| `dados_site/` | CSV usados na renderização; nomes e colunas definidos em `_planejamento/BRIEF_SITE.md` (seção 3) |
| `arquivos/` | Downloads publicados: painéis CSV, dicionário, fluxos, hospitais, sedes municipais, malhas GeoJSON; `arquivos/geo/ibge_localidades_2022_mt/` guarda o shapefile de origem das sedes |
| `assets/` | Logomarcas, favicon e glossário de siglas (`glossario.html`) |
| `municipios/_perfil.qmd` | Modelo das 142 páginas de município (`<slug>.qmd`, geradas pelo script 03) |
| `indicadores/_indicador.qmd` | Modelo das páginas de indicador (`<id>.qmd`, geradas pelos scripts 03/04) |
| `eficiencia/` | Seção Eficiência (visão geral, atenção básica, consolidado, média complexidade, hospitais, alta complexidade, produtividade); dados em `dados_site/eficiencia/` (script 06) |
| `previsao/` | Seção Previsão (v0.4, preliminar): nowcast, previsão semanal e alerta das internações respiratórias; funções em `R/pag_previsao.R`; dados em `dados_site/previsao/` (script 08) |
| `localizacao/` | Seção Localização (v0.4, preliminar): visão geral e pilotos de atenção ao parto e UTI adulto; funções em `R/pag_localizacao.R`; dados em `dados_site/localizacao/` (script 11) |
| `judicializacao/` | Seção Judicialização (v0.4, preliminar): DataJud/CNJ, comarcas, previsão e fatores associados; funções em `R/pag_judicializacao.R`; dados em `dados_site/judicializacao/` (script 10) |
| `deslocamento/`, `dados/`, `metodologia.qmd`, `sobre.qmd` | Demais seções |

## Regras de conteúdo

- Só agregados por município, região de saúde ou estabelecimento; nunca microdados.
- Internações em outros estados: nos recortes por região de saúde e por município, contagens de 1 a 4 não são publicadas (supressão complementar no script 02; regra em `dados_site/README_dados.md`).
- Previsão, localização e judicialização (v0.4): a mesma regra, aplicada pelas frentes de pesquisa e conferida pelos scripts 08, 10 e 11; nenhuma contagem de 1 a 4 em texto, tabela, gráfico ou dado embutido no HTML, e valor suprimido nunca é recalculado nem mostrado ("suprimido"). Os resultados são rotulados como preliminares e não são recomendação oficial.
- Cada número com fonte e ano; ressalvas visíveis.
- Textos em português do Brasil, registro gerencial, siglas explicadas pelo glossário.

## Requisitos

- R 4.6 com dplyr, tidyr, htmltools, reactable, leaflet, sf, jsonlite, data.table, knitr, rmarkdown (sem `readr`: a política de Controle de Aplicativos do Windows bloqueia a DLL do `tzdb`; a leitura de CSV usa `data.table::fread`).
- Quarto 1.9 ou superior.
- Python 3.12 com psycopg2 e pandas (scripts de dados; o script 00 é Python puro); o script 11 usa também scipy (programação inteira HiGHS) para conferir a supressão complementar.

## Licença

Conteúdo, indicadores e arquivos de dados derivados: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.pt-br). Ao usar, cite: *Observatório PPSUS-MT — Projeto Gestão Integrada no SUS (PPSUS 004/2025 FAPEMAT). UNEMAT, 2026. https://daniellindomar.github.io/ppsus/*. Os dados de origem são públicos (DATASUS, SIOPS, IBGE; na versão 0.4, também SIVEP-Gripe, INMET, InfoDengue, OpenStreetMap/ODbL e DataJud/CNJ, este pela API Pública, conforme o seu Termo de Uso).
