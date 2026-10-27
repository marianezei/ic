"""Validação genérica de observações no formato canônico longo.

Só conhece o formato canônico (data, id_local, variavel, valor), nunca uma fonte específica.
O que reprova não avança para o banco; o relatório é gravado em data/relatorios/.

Faixas plausíveis: limites físicos largos para um valor diário no Brasil. Servem para pegar
erro de unidade ou de decodificação (ex.: temperatura em kelvin, chuva negativa), não para
julgar se um evento extremo é real.
"""

import json

import pandas as pd
import pandera.pandas as pa

from pipeline.comum import agora, relatorios

FAIXAS = {
    "pr":   (0.0, 500.0),    # mm/dia; recorde brasileiro fica bem abaixo de 500
    "tmax": (-10.0, 50.0),   # °C
    "tmin": (-15.0, 45.0),   # °C
    "rs":   (0.0, 45.0),     # MJ m-2 por dia
    "rh":   (0.0, 100.0),    # %
    "u2":   (0.0, 30.0),     # m s-1
    "eto":  (0.0, 20.0),     # mm/dia
}


def _esquema(variaveis_catalogo):
    def dentro_da_faixa(df):
        lim = df["variavel"].map(FAIXAS)
        mn = lim.map(lambda x: x[0])
        mx = lim.map(lambda x: x[1])
        return (df["valor"] >= mn) & (df["valor"] <= mx)

    return pa.DataFrameSchema(
        {
            "data": pa.Column("datetime64[ns]"),
            "id_local": pa.Column(int),
            "variavel": pa.Column(str, pa.Check.isin(sorted(variaveis_catalogo))),
            "valor": pa.Column(float, nullable=False),
        },
        checks=[pa.Check(dentro_da_faixa, error="valor fora da faixa plausível")],
        unique=["id_local", "variavel", "data"],
        strict=True,
        coerce=True,
    )


def validar(df: pd.DataFrame, nome: str, n_ausentes: int, unidade_esperada: dict, unidade_recebida: dict):
    """Valida o DataFrame longo. Retorna o df validado ou levanta SystemExit com o relatório."""
    erros = []
    for var, un in unidade_recebida.items():
        if unidade_esperada.get(var) != un:
            erros.append(f"unidade de {var}: esperada {unidade_esperada.get(var)!r}, recebida {un!r}")

    try:
        validado = _esquema(set(FAIXAS)).validate(df, lazy=True)
    except pa.errors.SchemaErrors as e:
        validado = None
        casos = e.failure_cases.head(20)
        erros.append(f"{len(e.failure_cases)} falhas de esquema; primeiras: {casos.to_dict('records')}")

    total = len(df) + n_ausentes
    relatorio = {
        "arquivo": nome,
        "validado_em": agora(),
        "linhas_validas": int(len(df)),
        "ausentes": int(n_ausentes),
        "fracao_ausente": round(n_ausentes / total, 4) if total else None,
        "resumo": df.groupby("variavel")["valor"].describe().round(3).to_dict("index") if len(df) else {},
        "aprovado": not erros,
        "erros": erros,
    }
    pasta = relatorios("validacao")
    pasta.mkdir(parents=True, exist_ok=True)
    (pasta / f"{nome}.json").write_text(json.dumps(relatorio, indent=2, ensure_ascii=False, default=str) + "\n")

    if erros:
        raise SystemExit(f"{nome}: reprovado na validação\n  " + "\n  ".join(erros))
    return validado
