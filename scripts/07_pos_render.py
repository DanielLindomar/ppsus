# -*- coding: utf-8 -*-
"""
07_pos_render.py — pós-processamento do site renderizado (executado pelo Quarto: project.post-render).

No Windows, o Quarto grava alguns caminhos com barra invertida (ex.: src="..\\assets/logos/..." no rodapé e
o redirecionamento {"": "eficiencia\\index.html"} do alias eficiencia.html). Os navegadores normalizam, mas
validadores, robôs de busca e verificadores de links podem falhar. Este passo troca '\\' por '/' só:
  - nos valores dos atributos src e href das tags HTML;
  - no objeto `var redirects = {...}` das páginas de redirecionamento.
Nada mais é alterado. Reexecutável (idempotente).

Uso: automático no `quarto render`; manual: python scripts/07_pos_render.py
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
SITE = RAIZ / "_site"

RE_ATRIB = re.compile(r'(\s(?:src|href)=")([^"<>]*\\[^"<>]*)(")')
RE_REDIR = re.compile(r"(var redirects = )(\{[^}]*\})")


def corrigir(txt: str) -> tuple[str, int]:
    n = 0

    def _atr(m):
        nonlocal n
        n += 1
        return m.group(1) + m.group(2).replace("\\", "/") + m.group(3)

    def _red(m):
        nonlocal n
        novo = re.sub(r"\\\\|\\", "/", m.group(2))
        if novo != m.group(2):
            n += 1
        return m.group(1) + novo

    txt = RE_ATRIB.sub(_atr, txt)
    txt = RE_REDIR.sub(_red, txt)
    return txt, n


def arquivos() -> list[Path]:
    lista = os.environ.get("QUARTO_PROJECT_OUTPUT_FILES", "")
    if lista.strip() and os.environ.get("QUARTO_PROJECT_RENDER_ALL") != "1":
        fs = [Path(x) for x in lista.splitlines() if x.strip().lower().endswith(".html")]
        fs = [f if f.is_absolute() else RAIZ / f for f in fs]
        # páginas de alias (redirecionamento) não aparecem na lista: inclui as da raiz do site
        fs += [f for f in SITE.glob("*.html") if f not in fs]
        return [f for f in fs if f.exists()]
    return sorted(SITE.rglob("*.html"))


def main() -> int:
    if not SITE.exists():
        return 0
    total, n_arq = 0, 0
    for f in arquivos():
        with f.open(encoding="utf-8", newline="") as h:
            txt = h.read()
        novo, n = corrigir(txt)
        if n and novo != txt:
            f.write_text(novo, encoding="utf-8", newline="")
            total += n
            n_arq += 1
    print(f"07_pos_render: {total} caminhos com barra invertida corrigidos em {n_arq} arquivos HTML")
    return 0


if __name__ == "__main__":
    sys.exit(main())
