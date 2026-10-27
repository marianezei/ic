"""Adaptador BR-DWGD (Xavier): bronze (NetCDF original) -> prata (NetCDF CF canônico).

O que este adaptador resolve:
- nomes: Tmax -> tmax etc. (MAPEAMENTO);
- compactação: os valores vêm em int16 com scale_factor/add_offset; viram float32;
- ausente: -32768 no arquivo vira NaN;
- coordenadas: latitude/longitude em float32 (-7.1499996) viram lat/lon arredondados (-7.15);
- unidade: confere se a unidade declarada no arquivo é a esperada para a fonte
  (a de temperatura vem escrita "Celcius degrees") e grava a unidade canônica do catálogo.

Também guarda os metadados da fonte (FONTE) e o mapeamento de variáveis, que a carga registra no banco.

Uso:
    python -m pipeline.adaptadores.xavier [--pasta-bronze data/bronze/xavier/v_3.2.4/amostra]
"""

import argparse

import numpy as np
import xarray as xr

from pipeline.comum import agora, bronze, conectar, ler_manifesto, prata, relativo
from pipeline.validacao.regras import validar

VERSAO = "v_3.2.4"
GRADE = "xavier_0.1"
RESOLUCAO = 0.1

FONTE = {
    "codigo": "xavier",
    "nome": "Brazilian Daily Weather Gridded Data (BR-DWGD)",
    "tipo": "grade",
    "versao": VERSAO,
    "formato": "NetCDF4",
    "frequencia": "diaria",
    "url": "https://sites.google.com/site/alexandrecandidoxavierufes/brazilian-daily-weather-gridded-data",
    "licenca": None,
    "contato": "alexandre.xavier@ufes.br",
    "citacao": (
        "Xavier, A. C., Scanlon, B. R., King, C. W., & Alves, A. I. (2022). New improved Brazilian "
        "daily weather gridded data (1961–2020). International Journal of Climatology, 42(16), "
        "8390–8404. https://doi.org/10.1002/joc.7731"
    ),
}

# nome na fonte -> (variável canônica, unidade declarada no arquivo, fator, deslocamento)
MAPEAMENTO = {
    "pr":   ("pr",   "mm",              1.0, 0.0),
    "Tmax": ("tmax", "Celcius degrees", 1.0, 0.0),
    "Tmin": ("tmin", "Celcius degrees", 1.0, 0.0),
    "Rs":   ("rs",   "MJ m-2",          1.0, 0.0),
    "RH":   ("rh",   "%",               1.0, 0.0),
    "u2":   ("u2",   "m s-1",           1.0, 0.0),
    "ETo":  ("eto",  "mm",              1.0, 0.0),
}

# Nomes padrão CF (http://cfconventions.org/standard-names.html)
STANDARD_NAME = {
    "pr": "lwe_thickness_of_precipitation_amount",
    "tmax": "air_temperature",
    "tmin": "air_temperature",
    "rs": "integral_wrt_time_of_surface_downwelling_shortwave_flux_in_air",
    "rh": "relative_humidity",
    "u2": "wind_speed",
    "eto": "lwe_thickness_of_water_evaporation_amount",
}
CELL_METHODS = {"pr": "time: sum", "tmax": "time: maximum", "tmin": "time: minimum", "eto": "time: sum"}


def catalogo_variaveis() -> dict:
    with conectar() as conn:
        return dict(conn.execute("SELECT codigo, unidade FROM variavel").fetchall())


def padronizar_arquivo(arquivo_bronze, info_manifesto: dict, catalogo: dict):
    nome_fonte = info_manifesto["variavel_na_fonte"]
    canonica, unidade_fonte, fator, deslocamento = MAPEAMENTO[nome_fonte]

    with xr.open_dataset(arquivo_bronze) as ds:  # aplica scale_factor/add_offset e _FillValue
        da = ds[nome_fonte].load()
        unidade_recebida = ds[nome_fonte].attrs.get("units")

    da = (da * fator + deslocamento).astype("float32")
    da = da.rename({"latitude": "lat", "longitude": "lon"})
    da = da.assign_coords(lat=np.round(da["lat"].values.astype("float64"), 2),
                          lon=np.round(da["lon"].values.astype("float64"), 2))

    # Validação no formato longo, antes de qualquer coisa ir para a prata.
    longo = da.to_dataframe(name="valor").reset_index()
    n_ausentes = int(longo["valor"].isna().sum())
    longo = longo.dropna(subset=["valor"])
    longo["id_local"] = (longo["lat"] * 100).round().astype(int) * 100_000 + (longo["lon"] * 100).round().astype(int)
    longo = longo.rename(columns={"time": "data"}).assign(variavel=canonica)[["data", "id_local", "variavel", "valor"]]
    longo["valor"] = longo["valor"].astype(float)

    nome_saida = arquivo_bronze.name.replace(nome_fonte, canonica, 1)
    validar(longo, nome_saida.removesuffix(".nc"), n_ausentes,
            unidade_esperada={nome_fonte: unidade_fonte}, unidade_recebida={nome_fonte: unidade_recebida})

    da.name = canonica
    da.attrs = {
        "units": catalogo[canonica],
        "standard_name": STANDARD_NAME[canonica],
        "grid_mapping": "crs",
    }
    if canonica in CELL_METHODS:
        da.attrs["cell_methods"] = CELL_METHODS[canonica]
    da.encoding = {}

    saida_ds = da.to_dataset()
    saida_ds["crs"] = xr.DataArray(np.int32(0), attrs={
        "grid_mapping_name": "latitude_longitude",
        "epsg_code": "EPSG:4326",
        "semi_major_axis": 6378137.0,
        "inverse_flattening": 298.257223563,
    })
    saida_ds["lat"].attrs = {"units": "degrees_north", "standard_name": "latitude", "axis": "Y"}
    saida_ds["lon"].attrs = {"units": "degrees_east", "standard_name": "longitude", "axis": "X"}
    saida_ds.attrs = {
        "Conventions": "CF-1.8",
        "title": f"{FONTE['nome']} - {canonica} (padronizado)",
        "fonte": FONTE["codigo"],
        "versao": VERSAO,
        "grade": GRADE,
        "resolucao_graus": RESOLUCAO,
        "arquivo_bronze": relativo(arquivo_bronze),
        "sha256_bronze": info_manifesto["sha256"],
        "padronizado_em": agora(),
        "references": FONTE["citacao"],
    }

    destino = prata("xavier", VERSAO)
    destino.mkdir(parents=True, exist_ok=True)
    saida = destino / nome_saida
    saida_ds.to_netcdf(saida, engine="h5netcdf", encoding={
        canonica: {"dtype": "float32", "_FillValue": np.float32(np.nan), "zlib": True, "complevel": 4},
        "time": {"units": "days since 1961-01-01", "calendar": "standard", "dtype": "int32"},
    })
    print(f"{nome_fonte} -> {saida} ({len(longo)} valores, {n_ausentes} ausentes)")
    return saida


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--pasta-bronze", default=None, help="pasta com manifesto.json (padrão: amostra)")
    args = p.parse_args()

    pasta = bronze("xavier", VERSAO, "amostra") if args.pasta_bronze is None else __import__("pathlib").Path(args.pasta_bronze)
    manifesto = ler_manifesto(pasta)
    catalogo = catalogo_variaveis()
    for info in manifesto["arquivos"]:
        padronizar_arquivo(pasta / info["arquivo"], info, catalogo)


if __name__ == "__main__":
    main()
