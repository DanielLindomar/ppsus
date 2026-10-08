# -*- coding: utf-8 -*-
"""
config_local.py — caminhos locais dos scripts de dados (fora do repositório público).

Os scripts não fixam caminhos da máquina de quem os executa. Cada caminho é lido, nesta ordem:
  1. da variável de ambiente (ex.: PPSUS_PGPASS);
  2. do arquivo `.env.local` na raiz do repositório (não versionado; linhas CHAVE=valor);
Se nenhum dos dois existir, o script para com uma mensagem explicando o que configurar.

Chaves usadas
  PPSUS_PGPASS   arquivo de uma linha com a senha do PostgreSQL local (usuário airflow)
  PPSUS_DIC_V2   dicionário das tabelas-base da estimação DEA v2 (Markdown; opcional)
"""
from __future__ import annotations

import os
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
ARQ_LOCAL = RAIZ / ".env.local"


def _ler_env_local() -> dict[str, str]:
    out: dict[str, str] = {}
    if ARQ_LOCAL.exists():
        for lin in ARQ_LOCAL.read_text(encoding="utf-8").splitlines():
            lin = lin.strip()
            if lin and not lin.startswith("#") and "=" in lin:
                k, v = lin.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def caminho(chave: str, obrigatorio: bool = True) -> Path | None:
    v = os.environ.get(chave) or _ler_env_local().get(chave)
    if not v:
        if obrigatorio:
            raise SystemExit(f"Configure {chave}: variável de ambiente ou linha '{chave}=<caminho>' em {ARQ_LOCAL.name} "
                             "(arquivo local, fora do controle de versão).")
        return None
    return Path(v)
