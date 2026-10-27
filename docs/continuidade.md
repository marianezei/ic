# Estado do projeto e como continuar

Documento de passagem para quem vai continuar o Hub de Dados Climáticos do Semiárido (INSA).
Atualizado em 27/10/2026.

- **Leia antes:** [`CLAUDE.md`](../CLAUDE.md) (contexto e decisões de planejamento) e [`proposta-banco.md`](proposta-banco.md) (modelo de dados, decisões e números).
- **Em uma frase:** o caminho completo **fonte → bronze → prata → banco → município** funciona para a Paraíba, com uma amostra de 1 dia. Falta escalar (mais dias, mais estados), medir e construir a API.

---

## 1. O que está feito

| Passo do plano | Situação |
|---|---|
| 1. Esqueleto, Docker, migração inicial | ✅ |
| 2. Xavier na bronze com manifesto | ✅ Só amostra (1 dia, PB, `pr` e `Tmax`), lida por HTTP Range. Sem notebook de exploração; os achados estão na proposta, seção 6. |
| 3. Municípios, recortes e células | ✅ PB: 223 municípios, recortes `uf_pb` e `semiarido_sudene_2021`, 1.134 células |
| 4. `celula_municipio`, observações, `clima_municipio` | ✅ Exceto a comparação com o DataClimaBR (precisa de conta no Earth Engine) |
| 5. Medir tamanho e tempos | ⬜ Não feito: 1 dia não é representativo |
| 6. Documento de proposta do banco | ✅ [`proposta-banco.md`](proposta-banco.md) |
| API (FastAPI) e SIGWEB | ⬜ Não começados |
| Outras fontes (INMET, CHIRPS, ERA5, AESA...) | ⬜ Não começadas |

## 2. Como rodar do zero

Pré-requisitos: Docker (com Compose) e Python 3.12 ou mais novo. Testado com Docker 23, Python 3.14 e macOS.

```bash
cp .env.example .env        # ajuste a senha
make venv                   # cria .venv e instala requirements.txt
make pipeline               # sobe o banco, migra, baixa, padroniza, carrega e transforma (~1 min)
make verificar              # consultas de conferência (sql/verificacao.sql)
```

Outros atalhos (`make ajuda` lista todos):

| Comando | O que faz |
|---|---|
| `make db` | Sobe só o banco |
| `make migrar` | Aplica migrações pendentes |
| `make psql` | Abre um terminal SQL no banco |
| `make resetar-db` | **Apaga** o volume do banco (os dados podem ser recriados com `make pipeline`) |
| `make bronze DIA=2024-03-10` | Baixa outro dia da amostra |

**Atenção ao trocar a senha no `.env` depois de o banco já existir.** O Postgres só lê `POSTGRES_PASSWORD` na primeira inicialização do volume. Ou você roda `make resetar-db`, ou altera a senha dentro do banco (`ALTER USER ... PASSWORD ...`).

## 3. Mapa do repositório

```
.
├── CLAUDE.md                   contexto do projeto (lido pelo Claude Code)
├── Makefile                    atalhos do pipeline
├── docker-compose.yml          db (PostgreSQL+PostGIS+Timescale) e dbmate (migrações)
├── .env.example                variáveis de ambiente (copiar para .env)
├── requirements.txt            dependências Python
├── sql/
│   ├── migrations/             schema versionado (dbmate); nunca editar uma migração já aplicada
│   ├── schema.sql              foto do schema, gerada pelo dbmate (não editar)
│   └── verificacao.sql         consultas de conferência e de exemplo
├── pipeline/
│   ├── comum.py                caminhos, conexão, hash, manifesto
│   ├── bronze/                 download para a camada bruta
│   │   ├── xavier_amostra.py   recorte do Xavier via HTTP Range
│   │   └── ibge.py             malha municipal e lista do semiárido
│   ├── adaptadores/            bronze -> prata (um por fonte)
│   │   ├── xavier.py           NetCDF original -> NetCDF CF; metadados da fonte e mapeamento
│   │   └── ibge.py             shapefile/xlsx -> GeoParquet/Parquet
│   ├── validacao/regras.py     validação genérica do formato longo (pandera)
│   ├── carga/                  prata -> banco
│   │   ├── municipios.py       municipio, recorte, municipio_recorte
│   │   └── xavier.py           fonte, mapeamento, celula, ingestao, obs_celula
│   └── transformacao/          derivados dentro do banco
│       ├── celula_municipio.sql
│       ├── clima_municipio.sql
│       └── municipio.py        roda os dois SQL e atualiza os agregados
├── data/                       (fora do git) bronze/, prata/, relatorios/
├── docs/                       este documento e a proposta do banco
└── notebooks/                  (vazio)
```

## 4. Como o fluxo funciona

```
Dropbox do Xavier ──HTTP Range──> bronze/xavier/v_3.2.4/amostra/*.nc + manifesto.json
IBGE geoftp ───────────────────> bronze/ibge/...                    + manifesto.json
        │
        ▼  adaptadores (renomeiam, decodificam, conferem unidade, VALIDAM)
prata/xavier/v_3.2.4/{pr,tmax}_*.nc   (NetCDF CF, float32, lat/lon arredondados)
prata/ibge/.../*.parquet              (cod_ibge, nome, uf, geometria 4674)
        │
        ▼  carga (idempotente; uma `ingestao` por arquivo da bronze)
municipio, recorte, celula, obs_celula
        │
        ▼  transformação (SQL no PostGIS/Timescale)
celula_municipio -> clima_municipio -> clima_municipio_mensal / _anual
```

Regras que o código segue e que convém manter:

- **Nova fonte = novo adaptador + nova carga.** A transformação e a validação não conhecem fontes específicas.
- **Os metadados da fonte** (nome, versão, citação, mapeamento de variáveis) ficam no adaptador (`FONTE`, `MAPEAMENTO`). A carga os registra no banco.
- **Schema só muda por migração nova** em `sql/migrations/` (`docker compose run --rm dbmate new <nome>`).
- **Caminhos e credenciais** vêm do `.env`/ambiente (`pipeline/comum.py`). Nada de caminho fixo.

## 5. Coisas que você precisa saber (e que custaram descobrir)

1. **Os arquivos do Xavier permitem ler só um pedaço.** Cada dia do Brasil inteiro é um bloco de ~300 KB por variável, sem compressão, e o Dropbox aceita HTTP Range. Ler 1 ano da PB custa ~110 MB por variável em vez de baixar 2,6 GB.
2. **Os links do Dropbox** estão em `pipeline/bronze/xavier_amostra.py`. A pasta do autor se chama `netcdf_new_dtype`. Se os links quebrarem, abra a pasta compartilhada (link no site do Xavier) e copie os novos.
3. **Unidade da temperatura no arquivo:** `"Celcius degrees"`. O adaptador confere esse texto. Se uma versão nova corrigir a grafia, a validação vai reprovar: basta atualizar `MAPEAMENTO` em `pipeline/adaptadores/xavier.py`.
4. **Municípios do litoral têm cobertura < 1**, porque o Xavier mascara as células cujo centro cai no mar e a grade termina em −34,8°. Ver `clima_municipio.cobertura`.
5. **A compressão do Timescale piora com pouco dado.** Ela só compensa com séries longas por (fonte, variável, célula). Não tire conclusões de tamanho com a amostra.
6. **Agregados contínuos não se atualizam sozinhos.** `pipeline/transformacao/municipio.py` chama o refresh. Se você inserir dados por outro caminho, rode o refresh.
7. **Migrações com agregados contínuos** precisam de `-- migrate:up transaction:false` (ver `20261027120100_agregados_municipio.sql`).
8. **O psycopg 3 não executa vários comandos SQL com parâmetros numa chamada só**, a não ser com `psycopg.ClientCursor` (usado em `transformacao/municipio.py`).
9. **A lista do semiárido** vem do IBGE (`Situacao_2022`), que aplica a delimitação SUDENE 2021 à divisão territorial de 2022: 1.477 municípios, 198 na PB. O recorte só inclui municípios já carregados em `municipio`. Depois de carregar outra UF, rode `make carga` de novo para completar o recorte.

## 6. Próximos passos, em ordem sugerida

### Curto prazo

1. **Publicar o repositório num remoto** (GitHub/GitLab do INSA). Hoje ele só existe localmente.
2. **Medir de verdade (passo 5).** Ler um período da PB, por exemplo 1991–2020, que é a normal climatológica:
   - Generalizar `pipeline/bronze/xavier_amostra.py` para aceitar `--inicio/--fim` (hoje é `--data`, um dia só) e escolher o arquivo certo por período (1961–1980, 1981–2000, 2001–2025).
   - Medir tamanho com e sem compressão (`hypertable_compression_stats`), tempo de carga e tempo de consultas típicas (série de um município, média mensal da PB).
   - Atualizar a seção 5 da [proposta](proposta-banco.md) com os números.
3. **Comparar com o DataClimaBR** (validação externa): algumas datas e municípios, valores de `clima_municipio` contra os do DataClimaBR (Earth Engine, exige conta Google).
4. **Fixar versões:** tag exata da imagem `timescaledb-ha` no `.env`, versão do dbmate, e um `requirements.lock` (`pip freeze`).
5. **Testes automatizados** (pytest) para o adaptador, a validação e as frações. Hoje a verificação é manual (`make verificar`).

### Médio prazo

6. **PE e CE.** `make bronze prata carga UF=PE` já baixa e carrega a malha, mas **a caixa de recorte do Xavier está fixa na PB** (`CAIXA_PB` em `xavier_amostra.py`). Ela deve passar a ser calculada a partir da malha da UF, mais 2 células de margem.
7. **Demais variáveis do Xavier** (`Tmin`, `Rs`, `RH`, `u2`, `ETo`): é só acrescentar os links em `ARQUIVOS`. O adaptador e o catálogo já as conhecem.
8. **API FastAPI** (`/v1/...`), conforme o `CLAUDE.md`. As consultas em `sql/verificacao.sql` servem de base.
9. **Fontes de estação** (INMET primeiro): adaptador para CSV brasileiro (`;`, vírgula decimal, latin-1), carga em `estacao` e `obs_estacao`.
10. **Normais (1991–2020), anomalias e índices**, conforme as perguntas dos pesquisadores.

### Dívidas conhecidas

- `municipio` sem `fonte_id` (a procedência da malha IBGE não está no banco). Avaliar uma fonte do tipo `territorial`.
- `clima_municipio.ingestao_id` guarda uma ingestão por linha (ver a proposta, seção 7).
- Nenhuma política de backup definida para o banco.

## 7. Questões em aberto com a equipe

Seguem valendo as do `CLAUDE.md`, mais:

- Qual a cobertura mínima para publicar um valor municipal (ex.: só municípios com `cobertura >= 0.9`)?
- Baixar os NetCDF completos (dezenas de GB) ou ler por HTTP Range sob demanda?
- A lista do semiárido do IBGE (situação 2022) é a referência oficial do projeto?

## 8. Usando o Claude Code neste repositório

O `CLAUDE.md` na raiz é carregado automaticamente pelo Claude Code e descreve o projeto, as decisões e as regras do domínio. Mantenha-o atualizado quando uma decisão mudar: ele é a memória do projeto entre sessões.
