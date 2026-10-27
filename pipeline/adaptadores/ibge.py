"""Adaptador IBGE: malha municipal e lista do semiárido, da bronze para a prata (GeoParquet/Parquet).

Formato canônico de município: cod_ibge (texto, 7 dígitos), nome, uf, geometry (MultiPolygon, EPSG:4674).

Uso:
    python -m pipeline.adaptadores.ibge --uf PB
"""

import argparse

import geopandas as gpd
import pandas as pd
from shapely.geometry import MultiPolygon

from pipeline.bronze.ibge import ANO_MALHA, SITUACAO_SEMIARIDO
from pipeline.comum import bronze, ler_manifesto, prata

CRS_IBGE = "EPSG:4674"  # SIRGAS 2000


def padronizar_malha(uf: str):
    pasta = bronze("ibge", f"malha_municipal_{ANO_MALHA}", uf)
    manifesto = ler_manifesto(pasta)
    arquivo = pasta / manifesto["arquivos"][0]["arquivo"]

    gdf = gpd.read_file(arquivo)
    if gdf.crs is None or gdf.crs.to_string() != CRS_IBGE:
        gdf = gdf.to_crs(CRS_IBGE)

    gdf = gpd.GeoDataFrame(
        {
            "cod_ibge": gdf["CD_MUN"].astype(str).str.zfill(7),
            "nome": gdf["NM_MUN"],
            "uf": gdf["SIGLA_UF"],
        },
        # Tudo vira MultiPolygon, que é o tipo da coluna no banco.
        geometry=[g if isinstance(g, MultiPolygon) else MultiPolygon([g]) for g in gdf.geometry],
        crs=CRS_IBGE,
    )

    problemas = []
    if gdf["cod_ibge"].duplicated().any():
        problemas.append("cod_ibge duplicado")
    if not gdf["cod_ibge"].str.fullmatch(r"\d{7}").all():
        problemas.append("cod_ibge fora do padrão de 7 dígitos")
    if not gdf.geometry.is_valid.all():
        problemas.append(f"{(~gdf.geometry.is_valid).sum()} geometrias inválidas")
    if problemas:
        raise SystemExit("malha IBGE reprovada: " + "; ".join(problemas))

    destino = prata("ibge", f"malha_municipal_{ANO_MALHA}")
    destino.mkdir(parents=True, exist_ok=True)
    saida = destino / f"municipios_{uf}.parquet"
    gdf.to_parquet(saida)
    print(f"malha: {len(gdf)} municípios -> {saida}")
    return saida


def padronizar_semiarido():
    pasta = bronze("ibge", f"semiarido_situacao_{SITUACAO_SEMIARIDO}")
    manifesto = ler_manifesto(pasta)
    arquivo = pasta / manifesto["arquivos"][0]["arquivo"]

    df = pd.read_excel(arquivo, dtype=str)
    df = pd.DataFrame({
        "cod_ibge": df["CD_MUN"].str.strip().str.zfill(7),
        "nome": df["NM_MUN"].str.strip(),
    })
    if df["cod_ibge"].duplicated().any() or not df["cod_ibge"].str.fullmatch(r"\d{7}").all():
        raise SystemExit("lista do semiárido reprovada: códigos duplicados ou fora do padrão")

    destino = prata("ibge", f"semiarido_situacao_{SITUACAO_SEMIARIDO}")
    destino.mkdir(parents=True, exist_ok=True)
    saida = destino / "municipios_semiarido.parquet"
    df.to_parquet(saida, index=False)
    print(f"semiárido: {len(df)} municípios -> {saida}")
    return saida


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--uf", default="PB")
    args = p.parse_args()
    padronizar_malha(args.uf.upper())
    padronizar_semiarido()


if __name__ == "__main__":
    main()
