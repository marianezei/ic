"""Baixa para a camada bronze a malha municipal do IBGE de uma UF e a lista do semiárido.

Uso:
    python -m pipeline.bronze.ibge --uf PB
"""

import argparse

import requests

from pipeline.comum import agora, bronze, gravar_manifesto, sha256

ANO_MALHA = 2025
URL_MALHA = (
    "https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/malhas_municipais/"
    "municipio_{ano}/UFs/{uf}/{uf}_Municipios_{ano}.zip"
)

# Lista do IBGE com a delimitação do semiárido da SUDENE (Res. CONDEL 150/2021),
# aplicada à divisão territorial de 2022.
SITUACAO_SEMIARIDO = "2022"
URL_SEMIARIDO = (
    "https://geoftp.ibge.gov.br/organizacao_do_territorio/estrutura_territorial/semiarido_brasileiro/"
    "Situacao_{s}/lista_municipios_Semiarido_{s}.xlsx"
)


def baixar(url: str, pasta, fonte: str, versao: str, descricao: str):
    """Baixa um arquivo para a pasta da bronze e grava o manifesto. Não baixa de novo se já existir."""
    pasta.mkdir(parents=True, exist_ok=True)
    destino = pasta / url.rsplit("/", 1)[-1]
    if destino.exists():
        print(f"já existe: {destino}")
        return destino

    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    destino.write_bytes(resp.content)
    gravar_manifesto(pasta, {
        "fonte": fonte,
        "versao": versao,
        "descricao": descricao,
        "baixado_em": agora(),
        "arquivos": [{
            "arquivo": destino.name,
            "url_original": url,
            "sha256": sha256(destino),
            "bytes": destino.stat().st_size,
        }],
    })
    print(f"baixado: {destino} ({destino.stat().st_size} bytes)")
    return destino


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--uf", default="PB", help="sigla da UF (padrão: PB)")
    args = p.parse_args()
    uf = args.uf.upper()

    baixar(
        URL_MALHA.format(ano=ANO_MALHA, uf=uf),
        bronze("ibge", f"malha_municipal_{ANO_MALHA}", uf),
        fonte="ibge_malha_municipal",
        versao=str(ANO_MALHA),
        descricao=f"Malha municipal do IBGE ({ANO_MALHA}), UF {uf}, shapefile em SIRGAS 2000 (EPSG:4674)",
    )
    baixar(
        URL_SEMIARIDO.format(s=SITUACAO_SEMIARIDO),
        bronze("ibge", f"semiarido_situacao_{SITUACAO_SEMIARIDO}"),
        fonte="ibge_semiarido",
        versao=SITUACAO_SEMIARIDO,
        descricao="Lista de municípios do semiárido (delimitação SUDENE, Res. CONDEL 150/2021), "
                  f"divisão territorial de {SITUACAO_SEMIARIDO}, publicada pelo IBGE",
    )


if __name__ == "__main__":
    main()
