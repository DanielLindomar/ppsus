# -*- coding: utf-8 -*-
"""
00_sedes_ibge.py — Observatório PPSUS-MT
Coordenadas das SEDES MUNICIPAIS de Mato Grosso (IBGE, Localidades do Brasil 2022).

Lê o .dbf do shapefile arquivos/geo/ibge_localidades_2022_mt/MT_localidades_2022.*
(campos CD_MUN, NM_MUN, SCT_LOCALI == "Sede Municipal", LAT_LOCALI, LONG_LOCAL) com um
leitor DBF próprio — Python puro, sem geopandas/shapely/pandas — e grava:

  dados_site/sedes_municipais.csv   cod_mun6, cod_ibge7, municipio, lon, lat, fonte  (142 linhas)

Se o shapefile não existir, baixa o zip nacional do IBGE
(https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/localidades/
Localidades_do_Brasil/2022/Localidades_UFs_shp.zip) e extrai só os arquivos de MT.

Essas coordenadas alimentam dados_site/centroides.csv (script 01) e, por ele, todas as
distâncias em linha reta do deslocamento (script 02) e das páginas (R/). Diferente do
centro geométrico do polígono, a sede não depende da extensão do território.

Validações: 142 linhas, sem duplicatas, lon em (-62, -50), lat em (-18.5, -7);
Boa Esperança do Norte (510183) presente.

Uso (a partir da raiz do repositório):  python scripts/00_sedes_ibge.py
"""
from __future__ import annotations

import csv
import io
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
GEO_DIR = RAIZ / "arquivos" / "geo" / "ibge_localidades_2022_mt"
DBF = GEO_DIR / "MT_localidades_2022.dbf"
SAIDA = RAIZ / "dados_site" / "sedes_municipais.csv"
URL_IBGE = ("https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/"
            "localidades/Localidades_do_Brasil/2022/Localidades_UFs_shp.zip")
FONTE = "IBGE, Localidades do Brasil 2022 (sede municipal)"
UF_MT = "51"
N_ESPERADO = 142
COD_BOA_ESPERANCA = "510183"


def msg(texto: str) -> None:
    print(texto, flush=True)


# ----------------------------------------------------------------------------
# Leitor DBF (dBase III/IV), suficiente para o .dbf dos shapefiles do IBGE
# ----------------------------------------------------------------------------
def ler_dbf(caminho: Path, codificacao: str | None = None) -> list[dict]:
    """Retorna as linhas do .dbf como dicionários {campo: str} (registros apagados ignorados)."""
    if codificacao is None:
        cpg = caminho.with_suffix(".cpg")
        codificacao = cpg.read_text(encoding="ascii", errors="ignore").strip() if cpg.exists() else "latin-1"
        if not codificacao:
            codificacao = "latin-1"
    with open(caminho, "rb") as f:
        cab = f.read(32)
        n_reg, tam_cab, tam_reg = struct.unpack("<IHH", cab[4:12])
        campos = []
        while True:
            d = f.read(32)
            if not d or d[0] == 0x0D:
                break
            nome = d[:11].split(b"\0")[0].decode("ascii")
            campos.append((nome, chr(d[11]), d[16]))
        f.seek(tam_cab)
        linhas = []
        for _ in range(n_reg):
            reg = f.read(tam_reg)
            if len(reg) < tam_reg or reg[:1] == b"*":
                continue
            pos, linha = 1, {}
            for nome, _tipo, tam in campos:
                linha[nome] = reg[pos:pos + tam].decode(codificacao, errors="replace").strip()
                pos += tam
            linhas.append(linha)
    return linhas


# ----------------------------------------------------------------------------
# Download do IBGE (só quando o shapefile não existe)
# ----------------------------------------------------------------------------
def baixar_shapefile_mt() -> None:
    msg(f"shapefile ausente; baixando {URL_IBGE} ...")
    req = urllib.request.Request(URL_IBGE, headers={"User-Agent": "Mozilla/5.0 (observatorio-ppsus-mt)"})
    with urllib.request.urlopen(req, timeout=300) as r:
        dados = r.read()
    msg(f"  {len(dados) / 1e6:.1f} MB recebidos")
    GEO_DIR.mkdir(parents=True, exist_ok=True)
    n = 0
    with zipfile.ZipFile(io.BytesIO(dados)) as z:
        for info in z.infolist():
            nome = Path(info.filename).name
            if info.is_dir() or not nome.upper().startswith("MT_LOCALIDADES"):
                continue
            (GEO_DIR / nome).write_bytes(z.read(info))
            n += 1
    if n == 0:
        sys.exit("ERRO: o zip do IBGE não contém arquivos MT_localidades_*.")
    msg(f"  {n} arquivos de MT extraídos em {GEO_DIR.relative_to(RAIZ).as_posix()}/")


# ----------------------------------------------------------------------------
# principal
# ----------------------------------------------------------------------------
def fmt_coord(txt: str) -> str:
    """'-55.1500' -> '-55.15' (número como o Python o imprime, sem zeros à direita)."""
    return repr(float(txt))


def main() -> int:
    if not DBF.exists():
        baixar_shapefile_mt()
    if not DBF.exists():
        sys.exit(f"ERRO: {DBF} não encontrado.")

    linhas = ler_dbf(DBF)
    msg(f"{DBF.relative_to(RAIZ).as_posix()}: {len(linhas)} localidades")
    sedes = [l for l in linhas if l["SCT_LOCALI"] == "Sede Municipal" and l["CD_MUN"][:2] == UF_MT]

    saida = []
    for l in sedes:
        cod7 = l["CD_MUN"]
        saida.append(dict(cod_mun6=cod7[:6], cod_ibge7=cod7, municipio=l["NM_MUN"],
                          lon=fmt_coord(l["LONG_LOCAL"]), lat=fmt_coord(l["LAT_LOCALI"]), fonte=FONTE))
    saida.sort(key=lambda d: d["cod_mun6"])

    # ---- validações ---------------------------------------------------------
    cods = [d["cod_mun6"] for d in saida]
    assert len(saida) == N_ESPERADO, f"esperadas {N_ESPERADO} sedes, encontradas {len(saida)}"
    assert len(set(cods)) == len(cods), "código de município duplicado entre as sedes"
    assert all(len(c) == 7 and c.isdigit() for c in (d["cod_ibge7"] for d in saida)), "cod_ibge7 inválido"
    for d in saida:
        lon, lat = float(d["lon"]), float(d["lat"])
        assert -62 < lon < -50 and -18.5 < lat < -7, f"coordenada fora de MT: {d}"
    assert COD_BOA_ESPERANCA in cods, "Boa Esperança do Norte (510183) ausente"
    mun_csv = RAIZ / "dados_site" / "municipios.csv"
    if mun_csv.exists():
        with open(mun_csv, encoding="utf-8", newline="") as f:
            cods_site = {r["cod_mun6"] for r in csv.DictReader(f)}
        faltam = sorted(cods_site - set(cods))
        sobram = sorted(set(cods) - cods_site)
        if faltam or sobram:
            msg(f"AVISO: divergência com municipios.csv — sem sede: {faltam}; sede sem município: {sobram}")
        else:
            msg("  conferido com dados_site/municipios.csv: os mesmos 142 códigos")

    SAIDA.parent.mkdir(exist_ok=True)
    with open(SAIDA, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["cod_mun6", "cod_ibge7", "municipio", "lon", "lat", "fonte"],
                           lineterminator="\n")
        w.writeheader()
        w.writerows(saida)
    msg(f"gravado {SAIDA.relative_to(RAIZ).as_posix()} ({len(saida)} linhas)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
