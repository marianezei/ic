# Atalhos do projeto. Rode `make ajuda` para ver a lista.
PY := .venv/bin/python
UF ?= PB
DIA ?= 2024-04-15

.PHONY: ajuda venv db migrar bronze prata carga transformar pipeline verificar psql resetar-db

ajuda:
	@echo "make venv         cria .venv e instala requirements.txt"
	@echo "make db           sobe o PostgreSQL (PostGIS + TimescaleDB)"
	@echo "make migrar       aplica as migrações (dbmate)"
	@echo "make bronze       baixa amostra do Xavier (DIA=$(DIA)) e arquivos do IBGE (UF=$(UF))"
	@echo "make prata        adaptadores: bronze -> prata (com validação)"
	@echo "make carga        prata -> banco (municípios, recortes, células, observações)"
	@echo "make transformar  celula_municipio, clima_municipio e agregados"
	@echo "make pipeline     tudo acima, em ordem"
	@echo "make verificar    consultas de conferência"
	@echo "make psql         abre o psql no banco"
	@echo "make resetar-db   APAGA o volume do banco e recria do zero"

venv:
	python3 -m venv .venv
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r requirements.txt

db:
	docker compose up -d db
	@until docker compose exec -T db pg_isready -q; do sleep 1; done

migrar: db
	docker compose run --rm dbmate up

bronze:
	$(PY) -m pipeline.bronze.xavier_amostra --data $(DIA)
	$(PY) -m pipeline.bronze.ibge --uf $(UF)

prata:
	$(PY) -m pipeline.adaptadores.ibge --uf $(UF)
	$(PY) -m pipeline.adaptadores.xavier

carga:
	$(PY) -m pipeline.carga.municipios --uf $(UF)
	$(PY) -m pipeline.carga.xavier

transformar:
	$(PY) -m pipeline.transformacao.municipio

pipeline: migrar bronze prata carga transformar

verificar:
	docker compose exec -T db sh -c 'psql -U $$POSTGRES_USER -d $$POSTGRES_DB' < sql/verificacao.sql

psql:
	docker compose exec db sh -c 'psql -U $$POSTGRES_USER -d $$POSTGRES_DB'

resetar-db:
	docker compose down -v
