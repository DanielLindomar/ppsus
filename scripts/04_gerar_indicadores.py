"""Gera indicadores/<id>.qmd para cada indicador do catálogo dados_site/indicadores.csv.

Uso (na raiz do repositório): python scripts/04_gerar_indicadores.py

Cada página gerada tem o cabeçalho YAML (title = rótulo do catálogo), define IND_ID em
um chunk R e inclui o modelo indicadores/_indicador.qmd. Páginas geradas cujo id saiu
do catálogo são removidas (só as que contêm a marca de inclusão do modelo).
Não depende do banco nem de scripts/03_gerar_paginas.py.
"""
import csv
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
CATALOGO = RAIZ / "dados_site" / "indicadores.csv"
PASTA = RAIZ / "indicadores"
MODELO = PASTA / "_indicador.qmd"
MARCA = "{{< include _indicador.qmd >}}"
ID_OK = re.compile(r"^[a-z][a-z0-9_]*$")

GRUPOS = {
    "contexto": "Contexto", "financiamento": "Financiamento", "capacidade": "Capacidade instalada",
    "atencao_basica": "Atenção básica", "media_alta": "Média e alta complexidade",
    "deslocamento": "Deslocamento", "resultados": "Resultados em saúde",
}


def yaml_str(s: str) -> str:
    """Texto entre aspas duplas, seguro para o cabeçalho YAML."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def pagina(r: dict) -> str:
    id_ = r["id"].strip()
    titulo = (r.get("rotulo") or id_).strip()
    grupo = GRUPOS.get((r.get("grupo") or "").strip(), (r.get("grupo") or "").strip())
    unidade = (r.get("unidade") or "").strip()
    ano_max = (r.get("ano_max") or "2025").strip()
    partes = [p for p in (grupo, unidade) if p]
    desc = (" · ".join(partes) + ". " if partes else "") + \
        f"Mapa dos 142 municípios de Mato Grosso, ranking, evolução 2020–{ano_max} e valores por região de saúde."
    return "\n".join([
        "---",
        f"title: {yaml_str(titulo)}",
        f"description: {yaml_str(desc)}",
        "toc: false",
        "page-layout: full",
        "---",
        "",
        "```{r}",
        "#| include: false",
        f'IND_ID <- "{id_}"',
        "```",
        "",
        MARCA,
        "",
    ])


def main() -> int:
    if not CATALOGO.exists():
        print(f"ERRO: catálogo não encontrado: {CATALOGO}", file=sys.stderr)
        return 1
    if not MODELO.exists():
        print(f"ERRO: modelo não encontrado: {MODELO}", file=sys.stderr)
        return 1
    with CATALOGO.open(encoding="utf-8", newline="") as f:
        linhas = list(csv.DictReader(f))
    ids = []
    for r in linhas:
        id_ = (r.get("id") or "").strip()
        if not ID_OK.match(id_):
            print(f"AVISO: id inválido ignorado: {id_!r}", file=sys.stderr)
            continue
        ids.append(id_)
    if len(ids) != len(set(ids)):
        print("ERRO: ids repetidos no catálogo", file=sys.stderr)
        return 1

    PASTA.mkdir(exist_ok=True)
    removidas = 0
    for q in PASTA.glob("*.qmd"):
        if q.name.startswith("_") or q.name == "index.qmd" or q.stem in ids:
            continue
        if MARCA in q.read_text(encoding="utf-8"):
            q.unlink()
            removidas += 1

    geradas = 0
    for r in linhas:
        id_ = (r.get("id") or "").strip()
        if id_ not in ids:
            continue
        (PASTA / f"{id_}.qmd").write_text(pagina(r), encoding="utf-8", newline="\n")
        geradas += 1

    print(f"{geradas} páginas geradas em {PASTA.relative_to(RAIZ)}/ "
          f"({removidas} removidas por não constarem mais no catálogo).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
