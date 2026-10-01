"""
03_gerar_paginas.py — gera as páginas do Observatório PPSUS-MT a partir dos modelos.

Uso (na raiz do repositório, depois de 01_preparar_dados.py e 02_preparar_deslocamento.py):
    python scripts/03_gerar_paginas.py

O que faz (só lê dados_site/; nunca acessa o banco):
  1. municipios/<slug>.qmd — uma página por município (142), com YAML `title` = nome do
     município, um chunk que define MUN_ID e carrega R/funcoes.R e a inclusão do modelo
     municipios/_perfil.qmd via shortcode {{< include _perfil.qmd >}} (o modelo fica na
     mesma pasta das páginas geradas; arquivos iniciados por "_" não são renderizados sozinhos).
  2. indicadores/<id>.qmd — uma página por indicador do catálogo, SE o modelo
     indicadores/_indicador.qmd existir (define IND_ID e inclui o modelo). Se o modelo ainda
     não existir, o script avisa e segue: basta reexecutá-lo depois.
  3. arquivos/municipios/<slug>.csv — indicadores do município em formato largo (uma linha
     por indicador, colunas 2020…2025), usados pelo botão "Baixar os indicadores do
     município (CSV)" do perfil.

Páginas geradas levam a marca GERADO no início; só arquivos com essa marca são
sobrescritos ou removidos (páginas escritas à mão, como index.qmd, ficam intactas).
Saída em UTF-8 sem BOM, quebras de linha "\n".
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pandas as pd

RAIZ = Path(__file__).resolve().parents[1]
DADOS = RAIZ / "dados_site"
GERADO = "<!-- GERADO por scripts/03_gerar_paginas.py — não editar; altere o modelo _perfil.qmd / _indicador.qmd -->"
ANOS = list(range(2020, 2026))
SOURCE_R = 'source(file.path(Sys.getenv("QUARTO_PROJECT_DIR", "."), "R", "funcoes.R"))'


def yaml_str(s: str) -> str:
    """Texto entre aspas duplas válido em YAML (JSON é subconjunto de YAML)."""
    return json.dumps("" if s is None else str(s), ensure_ascii=False)


def escrever(caminho: Path, texto: str) -> None:
    caminho.parent.mkdir(parents=True, exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)


def eh_gerado(caminho: Path) -> bool:
    """Página gerada: tem a marca GERADO ou é só 'define o id + inclui o modelo'
    (formato das páginas geradas antes de a marca existir)."""
    try:
        with open(caminho, encoding="utf-8") as f:
            txt = f.read(4000)
    except OSError:
        return False
    if GERADO in txt:
        return True
    return ("{{< include _perfil.qmd >}}" in txt and "MUN_ID <-" in txt) or \
           ("{{< include _indicador.qmd >}}" in txt and "IND_ID <-" in txt)


def limpar_obsoletos(pasta: Path, manter: set[str]) -> int:
    """Remove páginas geradas (com a marca) que não estão mais na lista atual."""
    n = 0
    if not pasta.exists():
        return 0
    for f in pasta.glob("*.qmd"):
        if f.name not in manter and not f.name.startswith("_") and f.name != "index.qmd" and eh_gerado(f):
            f.unlink()
            n += 1
    return n


# ---------------------------------------------------------------------------
# 1. Páginas de município
# ---------------------------------------------------------------------------
def pagina_municipio(m: pd.Series) -> str:
    desc = f"Perfil de {m.municipio} (MT), região de saúde {m.regiao_saude}: indicadores de saúde 2020–2025, deslocamento para internação e hospitais SUS — Observatório PPSUS-MT"
    return "\n".join([
        "---",
        f"title: {yaml_str(m.municipio)}",
        f"description: {yaml_str(desc)}",
        "toc: false",
        "page-layout: full",
        "---",
        "",
        GERADO,
        "",
        "```{r}",
        "#| include: false",
        f"MUN_ID <- {int(m.cod_mun6)}L",
        SOURCE_R,
        "```",
        "",
        "{{< include _perfil.qmd >}}",
        "",
    ])


def gerar_municipios(mun: pd.DataFrame) -> int:
    pasta = RAIZ / "municipios"
    if not (pasta / "_perfil.qmd").exists():
        print("AVISO: municipios/_perfil.qmd não existe; as páginas geradas só renderizam depois que ele existir.")
    nomes = set()
    for _, m in mun.iterrows():
        f = pasta / f"{m.slug}.qmd"
        if f.exists() and not eh_gerado(f):
            print(f"AVISO: {f.relative_to(RAIZ)} existe e não tem a marca de página gerada; mantido sem alteração.")
            nomes.add(f.name)
            continue
        escrever(f, pagina_municipio(m))
        nomes.add(f.name)
    removidos = limpar_obsoletos(pasta, nomes)
    if removidos:
        print(f"  {removidos} página(s) de município obsoleta(s) removida(s).")
    return len(nomes)


# ---------------------------------------------------------------------------
# 2. Páginas de indicador (se o modelo existir)
# ---------------------------------------------------------------------------
GRUPOS = {"contexto": "Contexto", "financiamento": "Financiamento", "capacidade": "Capacidade instalada",
          "atencao_basica": "Atenção básica", "media_alta": "Média e alta complexidade",
          "deslocamento": "Deslocamento", "resultados": "Resultados em saúde"}


def pagina_indicador(r: pd.Series) -> str:
    """Mesmo formato das páginas de indicador do modelo indicadores/_indicador.qmd:
    o chunk define só IND_ID (o modelo carrega R/funcoes.R e R/pag_indicadores.R)."""
    grupo = GRUPOS.get(str(r.get("grupo", "")), str(r.get("grupo", "")))
    unidade = r.get("unidade", "")
    unidade = unidade.strip() if isinstance(unidade, str) else ""
    desc = f"{grupo} · {unidade}. Mapa dos 142 municípios de Mato Grosso, ranking, evolução 2020–2025 e valores por região de saúde."
    return "\n".join([
        "---",
        f"title: {yaml_str(r.rotulo)}",
        f"description: {yaml_str(desc)}",
        "toc: false",
        "page-layout: full",
        "---",
        "",
        GERADO,
        "",
        "```{r}",
        "#| include: false",
        f"IND_ID <- {json.dumps(str(r.id), ensure_ascii=False)}",
        "```",
        "",
        "{{< include _indicador.qmd >}}",
        "",
    ])


def gerar_indicadores(ind: pd.DataFrame) -> int:
    pasta = RAIZ / "indicadores"
    modelo = pasta / "_indicador.qmd"
    if not modelo.exists():
        print("AVISO: indicadores/_indicador.qmd ainda não existe; páginas de indicador NÃO geradas. "
              "Reexecute este script quando o modelo existir.")
        return 0
    ind = ind[ind["grupo"].notna() & (ind["grupo"].astype(str).str.len() > 0)]
    nomes = set()
    for _, r in ind.iterrows():
        f = pasta / f"{r.id}.qmd"
        if f.exists() and not eh_gerado(f):
            print(f"AVISO: {f.relative_to(RAIZ)} existe e não tem a marca de página gerada; mantido sem alteração.")
            nomes.add(f.name)
            continue
        escrever(f, pagina_indicador(r))
        nomes.add(f.name)
    removidos = limpar_obsoletos(pasta, nomes)
    if removidos:
        print(f"  {removidos} página(s) de indicador obsoleta(s) removida(s).")
    return len(nomes)


# ---------------------------------------------------------------------------
# 3. CSV por município (download do perfil)
# ---------------------------------------------------------------------------
def gerar_csv_municipios(mun: pd.DataFrame, ind: pd.DataFrame, ser: pd.DataFrame) -> int:
    pasta = RAIZ / "arquivos" / "municipios"
    pasta.mkdir(parents=True, exist_ok=True)
    cols_ind = [c for c in ["id", "rotulo", "grupo", "unidade", "fonte", "formula"] if c in ind.columns]
    cat = ind[cols_ind].rename(columns={"id": "indicador"})
    ordem = pd.to_numeric(ind["ordem"], errors="coerce") if "ordem" in ind.columns else pd.Series(range(len(ind)))
    cat = cat.assign(_ordem=ordem.fillna(9999).values)
    ser = ser[ser["ano"].isin(ANOS)]
    anos_txt = [str(a) for a in ANOS]

    def txt(v):  # 618124.0 → "618124"; 1.4616 → "1.4616"; NaN → ""
        return "" if pd.isna(v) else format(float(v), ".10g")

    n = 0
    for _, m in mun.iterrows():
        s = ser[ser["cod_mun6"] == m.cod_mun6]
        largo = (s.pivot_table(index="indicador", columns="ano", values="valor", aggfunc="first")
                   .reindex(columns=ANOS))
        largo.columns = anos_txt
        largo = largo.reset_index()
        out = cat.merge(largo, on="indicador", how="left").sort_values("_ordem", kind="stable").drop(columns="_ordem")
        for a in anos_txt:
            out[a] = out[a].map(txt) if a in out.columns else ""
        out.insert(0, "municipio", m.municipio)
        out.insert(0, "cod_mun6", int(m.cod_mun6))
        out.to_csv(pasta / f"{m.slug}.csv", index=False, encoding="utf-8", na_rep="", lineterminator="\n")
        n += 1
    return n


# ---------------------------------------------------------------------------
def main() -> int:
    f_mun, f_ind, f_ser = DADOS / "municipios.csv", DADOS / "indicadores.csv", DADOS / "serie.csv"
    if not f_mun.exists():
        print(f"ERRO: {f_mun} não existe. Rode primeiro scripts/01_preparar_dados.py.")
        return 1
    mun = pd.read_csv(f_mun, dtype={"co_regsaud": str, "co_macsaud": str, "slug": str, "municipio": str, "regiao_saude": str})
    mun = mun[mun["slug"].notna() & mun["cod_mun6"].notna()].copy()
    mun["cod_mun6"] = mun["cod_mun6"].astype(int)
    dup = mun[mun["slug"].duplicated(keep=False)]
    if len(dup):
        print("ERRO: slugs duplicados em municipios.csv:", ", ".join(sorted(dup["slug"].unique())))
        return 1

    n_mun = gerar_municipios(mun)
    print(f"municipios/<slug>.qmd: {n_mun} páginas.")

    ind = pd.read_csv(f_ind, dtype=str) if f_ind.exists() else pd.DataFrame(columns=["id", "rotulo", "grupo"])
    if not f_ind.exists():
        print("AVISO: dados_site/indicadores.csv não existe; páginas de indicador e CSV por município ficam sem catálogo.")
    n_ind = gerar_indicadores(ind)
    print(f"indicadores/<id>.qmd: {n_ind} páginas.")

    if f_ser.exists() and len(ind):
        ser = pd.read_csv(f_ser, dtype={"indicador": str})
        n_csv = gerar_csv_municipios(mun, ind, ser)
        print(f"arquivos/municipios/<slug>.csv: {n_csv} arquivos.")
    else:
        print("AVISO: dados_site/serie.csv ausente; CSV por município não gerados.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
