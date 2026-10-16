"""Baixa uma amostra pequena do BR-DWGD (Xavier) para a camada bronze.

Em vez de baixar o NetCDF inteiro (~2,6 GB, Brasil todo), lê pela rede (HTTP Range)
só os dias e a caixa pedidos. Os valores são gravados crus, como estão no arquivo
original (int16 compactado, mesmos atributos), sem nenhuma padronização.

Uso:
    python pipeline/bronze/xavier_amostra.py --data 2024-04-15
"""

import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import fsspec
import numpy as np
import xarray as xr

VERSAO = "v_3.2.4"

# Links do Dropbox do autor (pasta netcdf_new_dtype). Período 2001-01-01 a 2025-12-31.
ARQUIVOS = {
    "pr": (
        "pr_20010101_20251231_BR-DWGD_UFES_UTEXAS_v_3.2.4.nc",
        "https://www.dropbox.com/scl/fo/t225fii1ir4o5ozga0o3u/AH82qHClvBB1tPTvnccaKn8/"
        "pr_20010101_20251231_BR-DWGD_UFES_UTEXAS_v_3.2.4.nc?rlkey=93nkonzxn08c4wioztkjq0x52&dl=1",
    ),
    "Tmax": (
        "Tmax_20010101_20251231_BR-DWGD_UFES_UTEXAS_v_3.2.4.nc",
        "https://www.dropbox.com/scl/fo/t225fii1ir4o5ozga0o3u/AF6e-TZ7So5o2bFb3S-yVRw/"
        "Tmax_20010101_20251231_BR-DWGD_UFES_UTEXAS_v_3.2.4.nc?rlkey=93nkonzxn08c4wioztkjq0x52&dl=1",
    ),
}

# Caixa da Paraíba (limites aproximados da malha IBGE), em graus.
CAIXA_PB = {"lon_min": -38.77, "lon_max": -34.79, "lat_min": -8.31, "lat_max": -6.02}
MARGEM_CELULAS = 2
RESOLUCAO = 0.1


def sha256(caminho: Path) -> str:
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(2**20), b""):
            h.update(bloco)
    return h.hexdigest()


def recortar(url: str, variavel: str, dia: np.datetime64, caixa: dict, margem: float):
    fs = fsspec.filesystem("http", headers={"User-Agent": "Mozilla/5.0"})
    with fs.open(url, "rb", block_size=2**19, cache_type="readahead") as f:
        # Só para achar o índice do dia; os dados saem do dataset cru abaixo.
        tempo = xr.open_dataset(f, engine="h5netcdf")["time"].values
        idx = np.where(tempo == dia)[0]
        if idx.size != 1:
            raise SystemExit(f"{variavel}: dia {dia} não encontrado no arquivo")

        f.seek(0)
        cru = xr.open_dataset(f, engine="h5netcdf", mask_and_scale=False, decode_times=False)
        lat, lon = cru["latitude"].values, cru["longitude"].values
        ilat = np.where((lat >= caixa["lat_min"] - margem) & (lat <= caixa["lat_max"] + margem))[0]
        ilon = np.where((lon >= caixa["lon_min"] - margem) & (lon <= caixa["lon_max"] + margem))[0]
        recorte = cru[[variavel]].isel(
            time=slice(idx[0], idx[0] + 1),
            latitude=slice(ilat[0], ilat[-1] + 1),
            longitude=slice(ilon[0], ilon[-1] + 1),
        ).load()
    return recorte


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data", required=True, help="dia no formato AAAA-MM-DD (2001-01-01 a 2025-12-31)")
    p.add_argument("--variaveis", nargs="+", default=list(ARQUIVOS), choices=list(ARQUIVOS))
    args = p.parse_args()

    dia = np.datetime64(args.data, "ns")
    data_dir = Path(os.environ.get("DATA_DIR", "data"))
    destino = data_dir / "bronze" / "xavier" / VERSAO / "amostra"
    destino.mkdir(parents=True, exist_ok=True)

    margem = MARGEM_CELULAS * RESOLUCAO
    arquivos = []
    for variavel in args.variaveis:
        nome_original, url = ARQUIVOS[variavel]
        recorte = recortar(url, variavel, dia, CAIXA_PB, margem)
        saida = destino / f"{variavel}_{args.data.replace('-', '')}_PB_{VERSAO}.nc"
        recorte.to_netcdf(saida, engine="h5netcdf")
        arquivos.append({
            "arquivo": saida.name,
            "sha256": sha256(saida),
            "bytes": saida.stat().st_size,
            "variavel_na_fonte": variavel,
            "arquivo_original": nome_original,
            "url_original": url.replace("&dl=1", "&dl=0"),
            "dimensoes": {k: int(v) for k, v in recorte.sizes.items()},
        })
        print(f"{variavel}: {saida} ({saida.stat().st_size} bytes)")

    manifesto = {
        "fonte": "xavier",
        "versao": VERSAO,
        "tipo": "amostra (recorte lido por HTTP Range; não é o arquivo original completo)",
        "baixado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "recorte": {
            "data": args.data,
            "caixa": CAIXA_PB,
            "margem_celulas": MARGEM_CELULAS,
        },
        "arquivos": arquivos,
    }
    (destino / "manifesto.json").write_text(json.dumps(manifesto, indent=2, ensure_ascii=False) + "\n")
    print(f"manifesto: {destino / 'manifesto.json'}")


if __name__ == "__main__":
    main()
