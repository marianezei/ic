"""Transformação grade -> município para uma fonte de grade.

1. Calcula celula_municipio (frações de área) e confere se as frações de cada município somam 1.
2. Calcula clima_municipio (média ponderada) para o período com dados.
3. Atualiza os agregados mensal e anual (continuous aggregates).

Uso:
    python -m pipeline.transformacao.municipio --fonte xavier --versao v_3.2.4 --grade xavier_0.1
"""

import argparse
from pathlib import Path

import psycopg

from pipeline.comum import conectar

AQUI = Path(__file__).parent
TOLERANCIA_SOMA = 0.001


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--fonte", default="xavier")
    p.add_argument("--versao", default="v_3.2.4")
    p.add_argument("--grade", default="xavier_0.1")
    args = p.parse_args()

    with conectar() as conn:
        fonte_id = conn.execute(
            "SELECT id FROM fonte WHERE codigo = %s AND versao = %s", (args.fonte, args.versao)
        ).fetchone()[0]

        # ClientCursor permite vários comandos com parâmetros num só arquivo SQL.
        psycopg.ClientCursor(conn).execute((AQUI / "celula_municipio.sql").read_text(), {"grade": args.grade})
        n_pares, n_mun = conn.execute(
            "SELECT count(*), count(DISTINCT cod_ibge) FROM celula_municipio cm "
            "JOIN celula c ON c.id = cm.celula_id WHERE c.grade = %s", (args.grade,)
        ).fetchone()
        print(f"celula_municipio: {n_pares} pares célula-município, {n_mun} municípios")

        sem_celula = conn.execute(
            "SELECT count(*) FROM municipio m WHERE NOT EXISTS ("
            " SELECT 1 FROM celula_municipio cm JOIN celula c ON c.id = cm.celula_id"
            " WHERE cm.cod_ibge = m.cod_ibge AND c.grade = %s)", (args.grade,)
        ).fetchone()[0]
        fora = conn.execute(
            "SELECT cod_ibge, round(soma_fracoes::numeric, 4) FROM v_celula_municipio_soma "
            "WHERE grade = %s AND abs(soma_fracoes - 1) > %s ORDER BY soma_fracoes",
            (args.grade, TOLERANCIA_SOMA),
        ).fetchall()
        if sem_celula:
            print(f"  ATENÇÃO: {sem_celula} municípios sem nenhuma célula (a grade não os cobre)")
        if fora:
            print(f"  ATENÇÃO: {len(fora)} municípios com soma de frações fora de 1±{TOLERANCIA_SOMA}: {fora[:10]}")
        else:
            print(f"  soma das frações = 1 (±{TOLERANCIA_SOMA}) em todos os municípios")

        inicio, fim = conn.execute(
            "SELECT min(data), max(data) FROM obs_celula WHERE fonte_id = %s", (fonte_id,)
        ).fetchone()
        if inicio is None:
            raise SystemExit("nenhuma observação desta fonte; rode a carga antes")
        cur = conn.execute((AQUI / "clima_municipio.sql").read_text(),
                           {"fonte_id": fonte_id, "grade": args.grade, "inicio": inicio, "fim": fim})
        print(f"clima_municipio: {cur.rowcount} linhas ({inicio} a {fim})")
        conn.commit()

    # refresh_continuous_aggregate não roda dentro de transação.
    with conectar() as conn:
        conn.autocommit = True
        for view in ("clima_municipio_mensal", "clima_municipio_anual"):
            conn.execute("CALL refresh_continuous_aggregate(%s, NULL, NULL)", (view,))
        print("agregados mensal e anual atualizados")


if __name__ == "__main__":
    main()
