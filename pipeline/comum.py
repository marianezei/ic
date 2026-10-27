"""Utilidades compartilhadas pelo pipeline: caminhos, conexão com o banco, hash e manifesto."""

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parent.parent


def _carregar_env():
    """Lê o .env da raiz do projeto sem sobrescrever variáveis já definidas no ambiente."""
    env = RAIZ / ".env"
    if not env.exists():
        return
    for linha in env.read_text().splitlines():
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        chave, valor = linha.split("=", 1)
        os.environ.setdefault(chave.strip(), valor.strip())


_carregar_env()


def data_dir() -> Path:
    caminho = Path(os.environ.get("DATA_DIR", "data"))
    return caminho if caminho.is_absolute() else RAIZ / caminho


def bronze(*partes) -> Path:
    return data_dir().joinpath("bronze", *partes)


def prata(*partes) -> Path:
    return data_dir().joinpath("prata", *partes)


def relatorios(*partes) -> Path:
    return data_dir().joinpath("relatorios", *partes)


def conectar() -> psycopg.Connection:
    """Conexão a partir do host. Dentro da rede do Compose, use PGHOST=db."""
    return psycopg.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("POSTGRES_PORT", "5432"),
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        dbname=os.environ["POSTGRES_DB"],
    )


def sha256(caminho: Path) -> str:
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(2**20), b""):
            h.update(bloco)
    return h.hexdigest()


def agora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def ler_manifesto(pasta: Path) -> dict:
    return json.loads((pasta / "manifesto.json").read_text())


def gravar_manifesto(pasta: Path, manifesto: dict) -> Path:
    destino = pasta / "manifesto.json"
    destino.write_text(json.dumps(manifesto, indent=2, ensure_ascii=False) + "\n")
    return destino


def relativo(caminho: Path) -> str:
    """Caminho relativo à raiz de dados, para gravar no banco sem depender da máquina."""
    return str(Path(caminho).resolve().relative_to(data_dir().resolve()))
