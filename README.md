# Observatório PPSUS-MT

Site público do projeto **Gestão integrada no SUS: avaliação da eficiência na oferta e previsão da demanda de serviços públicos de saúde nos municípios de Mato Grosso** (Edital PPSUS 004/2025 FAPEMAT, processo FAPEMAT-PRO.0001999/2025). Executado pela UNEMAT, Campus de Sinop.

Publicado em: https://daniellindomar.github.io/ppsus/

Versão 0.1: dados e indicadores 2020–2025 dos 142 municípios e análise de deslocamento residência × atendimento (internações). Escores de eficiência (DEA) e produtividade (Malmquist) virão em versões seguintes.

## Como atualizar

Todos os comandos rodam pelo PowerShell, na raiz do repositório. Os scripts leem o PostgreSQL local (somente leitura) e gravam `dados_site/` e `arquivos/dados/`.

1. **Preparar os dados e gerar as páginas** (nesta ordem):

   ```powershell
   python scripts/00_sedes_ibge.py              # sedes municipais (IBGE, Localidades 2022) → dados_site/sedes_municipais.csv (Python puro)
   python scripts/01_preparar_dados.py          # municipios, indicadores, series, hospitais, geo, centroides.csv (= sedes), downloads do contrato
   python scripts/02_preparar_deslocamento.py   # fluxos de internação, deslocamento por município, polos, resumo, outras UFs, achados
   python scripts/01_preparar_dados.py          # de novo: incorpora pct_internacoes_fora_regiao e km_medio_internacao à serie.csv
   python scripts/03_gerar_paginas.py           # municipios/<slug>.qmd, indicadores/<id>.qmd e arquivos/municipios/<slug>.csv
   python scripts/04_gerar_indicadores.py       # regrava indicadores/<id>.qmd só a partir do catálogo (remove ids que saíram dele)
   python scripts/05_downloads.py               # downloads complementares e catálogo (arquivos/dados/catalogo_arquivos.csv)
   ```

   O script 00 lê o `.dbf` do shapefile `arquivos/geo/ibge_localidades_2022_mt/` (baixa o zip do IBGE se a pasta não existir) e grava as coordenadas das 142 sedes municipais; o script 01 copia essas coordenadas para `dados_site/centroides.csv` (nome do contrato), que o script 02 e as páginas usam em todas as distâncias — em linha reta entre as sedes, não rodoviárias. Os indicadores `pct_internacoes_fora_regiao` e `km_medio_internacao` vêm de `dados_site/deslocamento_mun_ano.csv` (script 02); por isso o script 01 roda duas vezes na primeira execução (na segunda ele encontra o arquivo e completa `serie.csv`, `serie_regiao.csv` e `serie_mt.csv`). Os scripts 03 e 04 não acessam o banco: o 03 gera as páginas de município (e também as de indicador) e os CSV por município; o 04 gera apenas as páginas de indicador a partir de `dados_site/indicadores.csv` e pode ser rodado sozinho sempre que o catálogo mudar. O script 05 só copia e enriquece arquivos de `dados_site/` (séries por região e MT, deslocamento, polos, sedes municipais, dicionário das 114 colunas do painel, malha com regiões de saúde) e gera o catálogo que a página Dados lê; rode-o sempre por último. Os scripts 00 a 05 completos levam cerca de 1 minuto.

2. **Renderizar e conferir localmente:** `quarto preview` (ou `quarto render` para o site inteiro — cerca de 190 páginas; `quarto render sobre.qmd` para uma página).

3. **Publicar:** `quarto publish gh-pages` (renderiza e envia o HTML para o ramo `gh-pages`).

4. Registrar a mudança em "Novidades" (`index.qmd`) e atualizar a versão e a data no rodapé (`_quarto.yml`).

## Estrutura

| Pasta/arquivo | Conteúdo |
|---|---|
| `_quarto.yml`, `estilo.scss` | Configuração do site (menu, rodapé, tema) e estilo |
| `R/funcoes.R` | Biblioteca compartilhada: carregadores dos CSV, formatação pt-BR, consultas, cartões, gráficos SVG, mapas leaflet, tabelas reactable |
| `R/idioma.R` | Textos das tabelas interativas em português |
| `R/pag_*.R` | Funções específicas de uma página (não editar `funcoes.R` para isso) |
| `scripts/` | Preparação de dados (00 sedes IBGE; 01–02 PostgreSQL → `dados_site/`, `arquivos/dados/`) e geração das páginas (03–05) |
| `dados_site/` | CSV usados na renderização; nomes e colunas definidos em `_planejamento/BRIEF_SITE.md` (seção 3) |
| `arquivos/` | Downloads publicados: painéis CSV, dicionário, fluxos, hospitais, sedes municipais, malhas GeoJSON; `arquivos/geo/ibge_localidades_2022_mt/` guarda o shapefile de origem das sedes |
| `assets/` | Logomarcas, favicon e glossário de siglas (`glossario.html`) |
| `municipios/_perfil.qmd` | Modelo das 142 páginas de município (`<slug>.qmd`, geradas pelo script 03) |
| `indicadores/_indicador.qmd` | Modelo das páginas de indicador (`<id>.qmd`, geradas pelos scripts 03/04) |
| `deslocamento/`, `dados/`, `metodologia.qmd`, `eficiencia.qmd`, `sobre.qmd` | Demais seções |

## Regras de conteúdo

- Só agregados por município, região de saúde ou estabelecimento; nunca microdados.
- Cada número com fonte e ano; ressalvas visíveis.
- Textos em português do Brasil, registro gerencial, siglas explicadas pelo glossário.

## Requisitos

- R 4.6 com dplyr, tidyr, htmltools, reactable, leaflet, sf, jsonlite, data.table, knitr, rmarkdown (sem `readr`: a política de Controle de Aplicativos do Windows bloqueia a DLL do `tzdb`; a leitura de CSV usa `data.table::fread`).
- Quarto 1.9 ou superior.
- Python 3.12 com psycopg2 e pandas (scripts de dados; o script 00 é Python puro).

## Licença

Conteúdo, indicadores e arquivos de dados derivados: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.pt-br). Ao usar, cite: *Observatório PPSUS-MT — Projeto Gestão Integrada no SUS (PPSUS 004/2025 FAPEMAT). UNEMAT, 2026. https://daniellindomar.github.io/ppsus/*. Os dados de origem são públicos (DATASUS, SIOPS, IBGE).
