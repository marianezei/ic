# Hub de Dados Climáticos do Semiárido (INSA)

Contexto do projeto para o Claude Code. Consolida as decisões tomadas na fase de planejamento.

## Projeto

- Projeto de Inteligência Climática Municipal do INSA. Objetivo: reunir todos os dados climáticos disponíveis do **semiárido** numa única plataforma (Hub de dados + API + SIGWEB).
- Recorte: **semiárido pela delimitação da SUDENE** (não o bioma Caatinga). Começamos por **PB, PE e CE**; o desenho deve escalar para o semiárido inteiro sem mudar o schema.
- **Primeira entrega: formular o banco de dados**, validado com um protótipo real (Paraíba primeiro).
- Desenvolvimento local primeiro; depois deploy em servidor do INSA. Tudo precisa ser portátil.
- A responsável (Mariane) vem de infra/SRE (Docker, Terraform, Ansible, Prometheus) e não tem experiência prévia com dados climáticos: explicar conceitos do domínio quando aparecerem.

## Fontes de dados

### BR-DWGD (Xavier) — primeira fonte
- Site: https://sites.google.com/site/alexandrecandidoxavierufes/brazilian-daily-weather-gridded-data
- Variáveis: `pr` (mm), `Tmax` e `Tmin` (°C), `Rs` (MJ/m²), `RH` (%), `u2` (m/s), `ETo` (mm).
- Diário, 1961-01-01 a 2025-12-31, grade de 0,1° x 0,1°, só território brasileiro. Formato NetCDF.
- Versão atual: `v_3.2.4` (abril/2026). O dataset é atualizado periodicamente: versionar sempre.
- Código de exemplo: https://github.com/AlexandreCandidoXavier/BR-DWGD
- Validação: comparar a agregação municipal com o DataClimaBR (dados municipais do Xavier via Earth Engine).
- Citação: Xavier, A. C., Scanlon, B. R., King, C. W., & Alves, A. I. (2022). New improved Brazilian daily weather gridded data (1961–2020). International Journal of Climatology, 42(16), 8390–8404. https://doi.org/10.1002/joc.7731

### Outras fontes previstas
- Estações: INMET, AESA (PB), APAC (PE), FUNCEME (CE).
- Grids: CHIRPS, ERA5.
- Socioeconômicos: IBGE (malhas, SIDRA, Censo, PIB municipal) e Atlas Brasil/PNUD (IDHM, só 1991/2000/2010 — IDH não é do IBGE).
- Cada fonte chega num formato diferente.

## Arquitetura (medalhão)

```
Fontes → Bronze → [Padronização] → Prata → [Transformação] → Ouro (banco) → API / SIGWEB
```

- **Bronze (camada bruta)**: arquivos originais, imutáveis, uma pasta por fonte e versão, com `manifesto.json` (URL, data do download, hash). Nunca vai para o banco relacional.
- **Padronização**: um **adaptador por fonte** converte para o formato canônico e resolve nomes de variáveis, unidades, fuso/convenção de dia, códigos de ausência (cuidado: zero de chuva é válido), CSV brasileiro (vírgula decimal, `;`, latin-1), CRS e identificação de municípios. Seguida de **validação automática** (faixas plausíveis, unidades, duplicatas, ausentes) com Pandera ou Great Expectations; o que falha não avança e gera relatório. Nova fonte = novo adaptador, sem tocar no resto.
- **Prata (camada padronizada)**: formato canônico, guardado e versionado. Tabular → Parquet em formato longo (`fonte`, `id_local`, `data`, `variavel`, `valor`). Grid → NetCDF seguindo convenções CF, CRS e nomes padronizados.
- **Transformação**: genérica, só conhece o formato canônico. Recorte, agregação grid → município, normais, anomalias, índices.
- **Ouro (banco)**: PostgreSQL + **PostGIS** (eixo espaço) + **TimescaleDB** (eixo tempo: hypertables, compressão, continuous aggregates). Licença Timescale OK para auto-hospedagem.
- **Consumo**: API de dados (FastAPI) e SIGWEB. O grid como imagem/raster é servido pelo GeoServer (WMS/WCS), não pela API REST.

## Modelo de dados

Dimensões:
- `fonte` (id, nome, tipo, versao, formato, frequencia, licenca, contato, citacao)
- `variavel` (codigo PK, nome, unidade)
- `mapeamento_variavel` (fonte, nome na fonte → variavel canônica, fator de conversão)
- `municipio` (cod_ibge PK, 7 dígitos; nome, uf, semiarido, poligono)
- `celula` (id, quadrado de 0,1°)
- `estacao` (id, fonte_id, cod_ibge, ponto)
- `celula_municipio` (celula_id, cod_ibge, fracao_area) — ponte grid → município
- `recorte` / `municipio_recorte` — recortes como dado (semiárido SUDENE com ano da delimitação, UF etc.), não fixos no código
- `ingestao` (id, fonte, arquivo original, hash, data, linhas, status)

Observações (formato longo, `fonte_id` e `ingestao_id` em todas):
- `obs_celula` (celula_id, data, variavel, valor)
- `obs_estacao` (estacao_id, data, variavel, valor, qualidade)
- `clima_municipio` (cod_ibge, data, variavel, valor) — calculada a partir de `obs_celula` + `celula_municipio`
- agregados mensais/anuais via continuous aggregates
- `indicador_socio` (cod_ibge, indicador, ano, valor, fonte_id)

Decisões:
- Formato longo para aceitar variáveis novas sem alterar schema.
- O banco nunca escolhe um "valor verdadeiro" entre fontes; quem consulta escolhe a fonte.
- Toda observação é rastreável até o arquivo de origem (`ingestao_id`).
- `cod_ibge` é o identificador de município em todo o sistema.

## Regras técnicas do domínio

- Xavier usa EPSG:4326 (WGS 84). Malhas do IBGE usam EPSG:4674 (SIRGAS 2000). Reprojetar antes de cruzar.
- **Frações de área devem ser calculadas numa projeção de área igual** (ex.: Albers para América do Sul), não em graus.
- Agregação grid → município por **média ponderada pela área** (municípios pequenos podem ser menores que uma célula). Ferramentas: `xagg`, `exactextract`, `regionmask`.
- Recortar o grid com margem de 1–2 células em volta da área de interesse.
- Validar `celula_municipio`: a soma das frações de cada município deve ser 1.
- Normal climatológica de referência: 1991–2020.

## API (planejada)

- FastAPI, `/v1/` desde o início, OpenAPI com exemplos em Python e R.
- Catálogos: `/v1/fontes`, `/v1/variaveis`, `/v1/municipios` (GeoJSON), `/v1/estacoes`.
- Séries: `/v1/municipios/{cod_ibge}/series?variavel=&inicio=&fim=&agregacao=&fonte=`.
- Derivados: climatologia e índices por município; `/v1/indicadores`.
- Toda resposta inclui procedência (fonte, versão, unidade, citação, método espacial).
- Formatos JSON, CSV e GeoJSON; limites por requisição e exportação assíncrona para pedidos grandes; cache longo (dado histórico é imutável até nova versão).
- Inspiração: padrão OGC API – EDR (pygeoapi).

## Estrutura do repositório

```
hub-clima/
├── docker-compose.yml      # PostgreSQL + PostGIS + TimescaleDB (imagem timescale/timescaledb-ha)
├── .env.example            # credenciais, portas, caminhos (.env real fora do git)
├── data/                   # fora do git
│   ├── bronze/xavier/v_3.2.4/
│   └── prata/xavier/
├── sql/migrations/         # migrações numeradas (dbmate ou Alembic)
├── pipeline/
│   ├── adaptadores/
│   ├── validacao/
│   └── transformacao/
├── notebooks/
└── docs/
```

Convenções de portabilidade: caminhos e credenciais em variáveis de ambiente; schema só por migrações; dados em volumes, fora da imagem e do git.

## Próximos passos

1. Criar o esqueleto do repositório, `docker-compose.yml`, `.env.example` e a migração inicial (extensões + dimensões).
2. Baixar `pr` e `Tmax` do Xavier para `data/bronze/xavier/v_3.2.4/` com manifesto; explorar em notebook (dimensões, unidades, valor de ausência, datas, grade, mapa de um dia na PB).
3. Carregar `municipio` (malha IBGE da PB + lista do semiárido da SUDENE) e `celula` (grade do NetCDF recortada com margem).
4. Calcular `celula_municipio`, carregar `pr` e `tmax` da PB, gerar `clima_municipio`, comparar com o DataClimaBR.
5. Medir tamanho, tempo de carga e de consulta (com e sem compressão) e extrapolar para PB+PE+CE e semiárido inteiro.
6. Escrever o documento de proposta do banco (modelo ER, decisões, números do protótipo).

## Questões em aberto com a equipe

- Quais perguntas os pesquisadores querem responder (define agregações e índices)?
- Qual versão da delimitação do semiárido usar?
- O SIGWEB precisa do grid ou só de municípios?
- Inventário das fontes: formato, arquivo de exemplo, frequência, fornecedor, restrições de uso.
- Servidor do INSA: SO, CPU, RAM, disco, backup, acesso externo, quem administra.
