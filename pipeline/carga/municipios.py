"""Carrega municípios (prata IBGE) e recortes (UF, semiárido) no banco.

Idempotente: pode rodar de novo; atualiza o que já existe.

Uso:
    python -m pipeline.carga.municipios --uf PB
"""

import argparse

import geopandas as gpd
import pandas as pd

from pipeline.bronze.ibge import ANO_MALHA, SITUACAO_SEMIARIDO
from pipeline.comum import conectar, prata

RECORTE_SEMIARIDO = {
    "codigo": "semiarido_sudene_2021",
    "nome": "Semiárido brasileiro (delimitação SUDENE 2021)",
    "tipo": "semiarido",
    "ano": 2021,
    "descricao": "Delimitação da Res. CONDEL/SUDENE nº 150/2021. Lista do IBGE na divisão territorial "
                 f"de {SITUACAO_SEMIARIDO}.",
    "referencia": "https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/"
                  f"semiarido_brasileiro/Situacao_{SITUACAO_SEMIARIDO}/",
}


def upsert_recorte(cur, r: dict) -> int:
    return cur.execute(
        """
        INSERT INTO recorte (codigo, nome, tipo, ano, descricao, referencia)
        VALUES (%(codigo)s, %(nome)s, %(tipo)s, %(ano)s, %(descricao)s, %(referencia)s)
        ON CONFLICT (codigo) DO UPDATE
           SET nome = EXCLUDED.nome, tipo = EXCLUDED.tipo, ano = EXCLUDED.ano,
               descricao = EXCLUDED.descricao, referencia = EXCLUDED.referencia
        RETURNING id
        """,
        r,
    ).fetchone()[0]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--uf", default="PB")
    args = p.parse_args()
    uf = args.uf.upper()

    gdf = gpd.read_parquet(prata("ibge", f"malha_municipal_{ANO_MALHA}", f"municipios_{uf}.parquet"))
    semiarido = pd.read_parquet(prata("ibge", f"semiarido_situacao_{SITUACAO_SEMIARIDO}", "municipios_semiarido.parquet"))

    with conectar() as conn, conn.cursor() as cur:
        cur.executemany(
            """
            INSERT INTO municipio (cod_ibge, nome, uf, poligono)
            VALUES (%s, %s, %s, ST_GeomFromWKB(%s, 4674))
            ON CONFLICT (cod_ibge) DO UPDATE
               SET nome = EXCLUDED.nome, uf = EXCLUDED.uf, poligono = EXCLUDED.poligono
            """,
            [(r.cod_ibge, r.nome, r.uf, r.geometry.wkb) for r in gdf.itertuples()],
        )
        print(f"municipio: {len(gdf)} de {uf}")

        id_uf = upsert_recorte(cur, {
            "codigo": f"uf_{uf.lower()}", "nome": f"Unidade da Federação {uf}", "tipo": "uf",
            "ano": ANO_MALHA, "descricao": f"Municípios de {uf} na malha IBGE {ANO_MALHA}",
            "referencia": "https://www.ibge.gov.br/geociencias/organizacao-do-territorio/malhas-territoriais.html",
        })
        cur.executemany(
            "INSERT INTO municipio_recorte (recorte_id, cod_ibge) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            [(id_uf, c) for c in gdf["cod_ibge"]],
        )

        # Só entram no recorte os municípios já carregados (a FK exige). Rodar de novo depois de
        # carregar outras UFs completa o recorte.
        id_semi = upsert_recorte(cur, RECORTE_SEMIARIDO)
        carregados = {c for (c,) in cur.execute("SELECT cod_ibge FROM municipio").fetchall()}
        membros = [c for c in semiarido["cod_ibge"] if c in carregados]
        cur.executemany(
            "INSERT INTO municipio_recorte (recorte_id, cod_ibge) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            [(id_semi, c) for c in membros],
        )
        print(f"recorte {RECORTE_SEMIARIDO['codigo']}: {len(membros)} municípios carregados "
              f"(de {len(semiarido)} na lista; os demais aguardam a malha de outras UFs)")


if __name__ == "__main__":
    main()
