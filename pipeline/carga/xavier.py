"""Carrega a prata do Xavier no banco: fonte, mapeamento, células e observações (obs_celula).

Cada arquivo da bronze vira uma linha em `ingestao`; todas as observações apontam para ela.
Se o mesmo arquivo (mesmo hash) já foi carregado com sucesso, é pulado. Se uma carga anterior
falhou, as linhas dela são apagadas e a carga é refeita.

Uso:
    python -m pipeline.carga.xavier
"""

import argparse
from decimal import Decimal

import xarray as xr

from pipeline.adaptadores.xavier import FONTE, GRADE, MAPEAMENTO, RESOLUCAO, VERSAO
from pipeline.comum import conectar, prata


def registrar_fonte(cur) -> int:
    fonte_id = cur.execute(
        """
        INSERT INTO fonte (codigo, nome, tipo, versao, formato, frequencia, url, licenca, contato, citacao)
        VALUES (%(codigo)s, %(nome)s, %(tipo)s, %(versao)s, %(formato)s, %(frequencia)s, %(url)s,
                %(licenca)s, %(contato)s, %(citacao)s)
        ON CONFLICT (codigo, versao) DO UPDATE
           SET nome = EXCLUDED.nome, formato = EXCLUDED.formato, frequencia = EXCLUDED.frequencia,
               url = EXCLUDED.url, licenca = EXCLUDED.licenca, contato = EXCLUDED.contato,
               citacao = EXCLUDED.citacao
        RETURNING id
        """,
        FONTE,
    ).fetchone()[0]
    cur.executemany(
        """
        INSERT INTO mapeamento_variavel (fonte_id, nome_na_fonte, variavel_codigo, unidade_na_fonte, fator, deslocamento)
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (fonte_id, nome_na_fonte) DO UPDATE
           SET variavel_codigo = EXCLUDED.variavel_codigo, unidade_na_fonte = EXCLUDED.unidade_na_fonte,
               fator = EXCLUDED.fator, deslocamento = EXCLUDED.deslocamento
        """,
        [(fonte_id, nome, *m) for nome, m in MAPEAMENTO.items()],
    )
    return fonte_id


def carregar_celulas(cur, ds) -> dict:
    """Insere todas as células da grade do arquivo (inclusive as sem dado, como o mar) e devolve
    {(lon, lat): celula_id}. Guardar a grade inteira deixa a cobertura dos municípios do litoral
    explícita, em vez de esconder o buraco."""
    meia = RESOLUCAO / 2
    linhas = [
        (GRADE, Decimal(f"{lon:.2f}"), Decimal(f"{lat:.2f}"), lon - meia, lat - meia, lon + meia, lat + meia)
        for lat in ds["lat"].values.tolist()
        for lon in ds["lon"].values.tolist()
    ]
    cur.executemany(
        """
        INSERT INTO celula (grade, lon, lat, geom)
        VALUES (%s, %s, %s, ST_MakeEnvelope(%s, %s, %s, %s, 4326))
        ON CONFLICT (grade, lon, lat) DO NOTHING
        """,
        linhas,
    )
    rows = cur.execute("SELECT lon, lat, id FROM celula WHERE grade = %s", (GRADE,)).fetchall()
    return {(round(float(lon), 2), round(float(lat), 2)): i for lon, lat, i in rows}


def carregar_arquivo(conn, fonte_id: int, arquivo):
    with xr.open_dataset(arquivo) as ds:
        variavel = next(v for v in ds.data_vars if v != "crs")
        ds = ds.load()
    bronze_rel, hash_bronze = ds.attrs["arquivo_bronze"], ds.attrs["sha256_bronze"]

    with conn.cursor() as cur:
        anterior = cur.execute(
            "SELECT id, status FROM ingestao WHERE fonte_id = %s AND hash_sha256 = %s ORDER BY id DESC LIMIT 1",
            (fonte_id, hash_bronze),
        ).fetchone()
        if anterior and anterior[1] == "concluida":
            print(f"{arquivo.name}: já carregado (ingestao {anterior[0]}), pulando")
            return
        if anterior:
            cur.execute("DELETE FROM obs_celula WHERE ingestao_id = %s", (anterior[0],))

        celulas = carregar_celulas(cur, ds)
        ingestao_id = cur.execute(
            "INSERT INTO ingestao (fonte_id, arquivo, hash_sha256) VALUES (%s, %s, %s) RETURNING id",
            (fonte_id, bronze_rel, hash_bronze),
        ).fetchone()[0]
    conn.commit()  # a ingestao fica registrada como em_andamento mesmo se a cópia falhar

    df = ds[variavel].to_dataframe().reset_index().dropna(subset=[variavel])
    try:
        with conn.cursor() as cur:
            with cur.copy("COPY obs_celula (data, celula_id, variavel, valor, fonte_id, ingestao_id) FROM STDIN") as cp:
                for r in df.itertuples(index=False):
                    celula_id = celulas[(round(float(r.lon), 2), round(float(r.lat), 2))]
                    cp.write_row((r.time.date(), celula_id, variavel, float(getattr(r, variavel)), fonte_id, ingestao_id))
            cur.execute(
                "UPDATE ingestao SET status = 'concluida', concluida_em = now(), linhas = %s WHERE id = %s",
                (len(df), ingestao_id),
            )
        conn.commit()
    except Exception as e:
        conn.rollback()
        conn.execute("UPDATE ingestao SET status = 'falhou', mensagem = %s WHERE id = %s", (str(e)[:1000], ingestao_id))
        conn.commit()
        raise
    print(f"{arquivo.name}: {len(df)} observações de {variavel} (ingestao {ingestao_id})")


def main():
    argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    arquivos = sorted(prata("xavier", VERSAO).glob("*.nc"))
    if not arquivos:
        raise SystemExit("nenhum arquivo na prata; rode antes: python -m pipeline.adaptadores.xavier")

    with conectar() as conn:
        with conn.cursor() as cur:
            fonte_id = registrar_fonte(cur)
        conn.commit()
        for arquivo in arquivos:
            carregar_arquivo(conn, fonte_id, arquivo)


if __name__ == "__main__":
    main()
