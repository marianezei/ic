# Hub de Dados Climáticos do Semiárido (INSA)

Banco de dados, pipeline e (futuramente) API que reúnem dados climáticos do semiárido brasileiro por município.

- **Banco:** PostgreSQL + PostGIS + TimescaleDB, schema versionado com dbmate.
- **Pipeline:** Python, arquitetura medalhão (bronze → prata → banco).
- **Estado:** protótipo funcional para a Paraíba com uma amostra do BR-DWGD (Xavier).

## Começar

```bash
cp .env.example .env
make venv
make pipeline
make verificar
```

## Documentação

- [`docs/continuidade.md`](docs/continuidade.md): o que está feito, como rodar e próximos passos. **Comece por aqui.**
- [`docs/proposta-banco.md`](docs/proposta-banco.md): modelo de dados, decisões e números do protótipo.
- [`CLAUDE.md`](CLAUDE.md): contexto e decisões do projeto.
