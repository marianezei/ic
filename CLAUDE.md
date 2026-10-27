# Hub de Dados Climáticos do Semiárido

Contexto do projeto para o Claude Code. Consolida as decisões do planejamento e da implementação.
Estado atual e próximos passos detalhados: `docs/continuidade.md`. Modelo e decisões do banco: `docs/proposta-banco.md`.

## Projeto

- Projeto de Inteligência Climática Municipal do INSA. Objetivo: reunir todos os dados climáticos disponíveis do semiárido numa única plataforma (Hub de dados + API + SIGWEB).
- Recorte: semiárido pela delimitação da SUDENE (não o bioma Caatinga). Começamos por **PB, PE e CE**; o desenho deve escalar para o semiárido inteiro sem mudar o schema.
- Primeira entrega: formular o banco de dados, validado com um protótipo real (Paraíba primeiro).
- Desenvolvimento local primeiro; depois deploy em servidor do INSA. 

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

## Arquitetura 

```
Fontes → Bronze → [Padronização] → Prata → [Transformação] → Ouro (banco) → API / SIGWEB
```

- **Bronze (camada bruta)**: arquivos originais, imutáveis, uma pasta por fonte e versão, com `manifesto.json` (URL, data do download, hash). Nunca vai para o banco relacional.
- **Padronização**: um adaptador por fonte converte para o formato canônico e resolve nomes de variáveis, unidades, fuso/convenção de dia, códigos de ausência (cuidado: zero de chuva é válido), CSV brasileiro (vírgula decimal, `;`, latin-1), CRS e identificação de municípios. Seguida de validação automática (faixas plausíveis, unidades, duplicatas, ausentes) com Pandera ou Great Expectations; o que falha não avança e gera relatório. Nova fonte = novo adaptador, sem tocar no resto.
- **Prata (camada padronizada)**: formato canônico, guardado e versionado. Tabular → Parquet em formato longo (`fonte`, `id_local`, `data`, `variavel`, `valor`). Grid → NetCDF seguindo convenções CF, CRS e nomes padronizados.
- **Transformação**: genérica, só conhece o formato canônico. Recorte, agregação grid → município, normais, anomalias, índices.
- **Ouro (banco)**: PostgreSQL + PostGIS (eixo espaço) + TimescaleDB (eixo tempo: hypertables, compressão, continuous aggregates). Licença Timescale OK para auto-hospedagem.
- **Consumo**: API de dados (FastAPI) e SIGWEB. O grid como imagem/raster é servido pelo GeoServer (WMS/WCS), não pela API REST.

## Modelo de dados 
**talvez algumas alterações devam ser realizadas aqui - definir com a equipe**

Dimensões:
- `fonte` (id, nome, tipo, versao, formato, frequencia, licenca, contato, citacao)
- `variavel` (codigo PK, nome, unidade)
- `mapeamento_variavel` (fonte, nome na fonte → variavel canônica, unidade na fonte, fator, deslocamento)
- `municipio` (cod_ibge PK, 7 dígitos; nome, uf, poligono) — pertencer ao semiárido é um `recorte`, não uma coluna
- `celula` (id, grade, lon, lat, geom) — `grade` separa grades diferentes (ex.: `xavier_0.1`); entra a grade inteira, inclusive células sem dado
- `estacao` (id, fonte_id, cod_ibge, ponto)
- `celula_municipio` (celula_id, cod_ibge, fracao_area) — ponte grid → município
- `recorte` / `municipio_recorte` — recortes como dado (semiárido SUDENE com ano da delimitação, UF etc.), não fixos no código
- `ingestao` (id, fonte, arquivo original, hash, data, linhas, status)

Observações (formato longo, `fonte_id` e `ingestao_id` em todas):
- `obs_celula` (celula_id, data, variavel, valor)
- `obs_estacao` (estacao_id, data, variavel, valor, qualidade)
- `clima_municipio` (cod_ibge, data, variavel, valor, cobertura) — média ponderada de `obs_celula` + `celula_municipio`, só sobre células com dado; `cobertura` = fração da área do município com dado
- agregados `clima_municipio_mensal` / `_anual` (continuous aggregates com soma, média, mín., máx., n_dias), atualizados pelo pipeline após cada carga
- `indicador_socio` (cod_ibge, indicador, ano, valor, fonte_id)

Decisões:
- Formato longo para aceitar variáveis novas sem alterar schema.
- O banco nunca escolhe um "valor verdadeiro" entre fontes; quem consulta escolhe a fonte.
- Toda observação é rastreável até o arquivo de origem (`ingestao_id`).
- `cod_ibge` é o identificador de município em todo o sistema.
- Valor ausente não vira linha; zero de chuva vira. `valor` é `real` (float4).
- Validação acontece no adaptador, antes de gravar na prata. Carga idempotente por hash do arquivo da bronze.

## Regras técnicas do domínio

- Xavier usa EPSG:4326 (WGS 84). Malhas do IBGE usam EPSG:4674 (SIRGAS 2000). Reprojetar antes de cruzar.
- Frações de área devem ser calculadas numa projeção de área igual (usamos `ESRI:102033`, Albers América do Sul, no PostGIS), não em graus.
- Agregação grid → município por média ponderada pela área (municípios pequenos podem ser menores que uma célula). Ferramentas: `xagg`, `exactextract`, `regionmask`.
- Recortar o grid com margem de 1–2 células em volta da área de interesse.
- Validar `celula_municipio`: a soma das frações de cada município deve ser 1.
- Normal climatológica de referência: 1991–2020.

## Achados sobre o BR-DWGD (Xavier)

- Um NetCDF por variável e período (1961–1980, 1981–2000, 2001–2025), Brasil inteiro (393×391), 1–2,6 GB cada. Links do Dropbox em `pipeline/bronze/xavier_amostra.py`.
- `int16` com `scale_factor`/`add_offset`; ausente = `-32768`; blocos de 1 dia × Brasil, sem compressão → dá para ler recortes por HTTP Range (~300 KB/dia/variável).
- Tempo em horas desde 1961-01-01; coordenadas `float32` dos centros (arredondar para 2 casas).
- Unidade da temperatura escrita `"Celcius degrees"`; atributo `title` diz 1961-2020 (desatualizado).
- Células com centro no mar são ausentes, e a grade termina em −34,8° de longitude: municípios do litoral têm `cobertura` < 1.

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
.
├── docker-compose.yml      # PostgreSQL + PostGIS + TimescaleDB (imagem timescale/timescaledb-ha)
├── .env.example            # credenciais, portas, caminhos (.env real fora do git)
├── data/                   # fora do git
│   ├── bronze/xavier/v_3.2.4/
│   └── prata/xavier/
├── Makefile                # make pipeline / verificar / psql ...
├── sql/migrations/         # migrações numeradas (dbmate)
├── sql/verificacao.sql     # consultas de conferência
├── pipeline/
│   ├── comum.py
│   ├── bronze/             # download (xavier_amostra, ibge)
│   ├── adaptadores/        # bronze -> prata, um por fonte
│   ├── validacao/
│   ├── carga/              # prata -> banco
│   └── transformacao/      # celula_municipio, clima_municipio
├── notebooks/
└── docs/
```

Convenções de portabilidade: caminhos e credenciais em variáveis de ambiente; schema só por migrações; dados em volumes, fora da imagem e do git.

## Próximos passos

1. ✅ Esqueleto do repositório, `docker-compose.yml`, `.env.example` e migrações.
2. ✅ (amostra) `pr` e `Tmax` do Xavier na bronze com manifesto — 1 dia (2024-04-15), PB, via HTTP Range.
3. ✅ `municipio` (malha IBGE 2025 da PB), recortes (`uf_pb`, `semiarido_sudene_2021`) e `celula`.
4. ✅ `celula_municipio`, `obs_celula`, `clima_municipio` e agregados. ⬜ Falta comparar com o DataClimaBR.
5. ⬜ Medir tamanho, tempo de carga e de consulta (com e sem compressão) com um período real e extrapolar.
6. ✅ `docs/proposta-banco.md` (atualizar com os números do passo 5).

Depois: PE e CE (a caixa do recorte do Xavier ainda está fixa na PB), demais variáveis, API, estações. Ver `docs/continuidade.md`.

## Questões em aberto 

- Quais perguntas queremos responder (define agregações e índices)?
- Qual versão da delimitação do semiárido usar? (provisório: SUDENE 2021, lista IBGE situação 2022)
- Cobertura mínima para publicar um valor municipal?
- O SIGWEB precisa do grid ou só de municípios?
- Inventário das fontes: formato, arquivo de exemplo, frequência, fornecedor, restrições de uso.
- Servidor: SO, CPU, RAM, disco, backup, acesso externo, quem administra.
