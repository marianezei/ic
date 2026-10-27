-- migrate:up

-- Observações em formato longo. Valor ausente não vira linha (zero de chuva vira).
-- Todas as tabelas de observação guardam fonte_id e ingestao_id para rastreabilidade.

-- Grade: um valor por célula, dia e variável.
CREATE TABLE obs_celula (
    data         date    NOT NULL,
    celula_id    integer NOT NULL REFERENCES celula (id),
    variavel     text    NOT NULL REFERENCES variavel (codigo),
    valor        real    NOT NULL,
    fonte_id     integer NOT NULL REFERENCES fonte (id),
    ingestao_id  integer NOT NULL REFERENCES ingestao (id),
    UNIQUE (fonte_id, celula_id, variavel, data)
);
SELECT create_hypertable('obs_celula', by_range('data', INTERVAL '1 year'));

-- Compressão: os dados de uma mesma (fonte, variável, célula) ficam juntos e ordenados por data,
-- o que dá séries longas e repetitivas, que comprimem bem. Colunas de segmentação ficam
-- guardadas uma vez por segmento, então variavel como texto não custa espaço depois de comprimir.
ALTER TABLE obs_celula SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'fonte_id, variavel, celula_id',
    timescaledb.compress_orderby = 'data'
);

-- Estações: mesmo formato, com um código de qualidade vindo da fonte.
CREATE TABLE obs_estacao (
    data         date    NOT NULL,
    estacao_id   integer NOT NULL REFERENCES estacao (id),
    variavel     text    NOT NULL REFERENCES variavel (codigo),
    valor        real    NOT NULL,
    qualidade    text,
    fonte_id     integer NOT NULL REFERENCES fonte (id),
    ingestao_id  integer NOT NULL REFERENCES ingestao (id),
    UNIQUE (fonte_id, estacao_id, variavel, data)
);
SELECT create_hypertable('obs_estacao', by_range('data', INTERVAL '1 year'));
ALTER TABLE obs_estacao SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'fonte_id, variavel, estacao_id',
    timescaledb.compress_orderby = 'data'
);

-- Clima por município, derivado de obs_celula + celula_municipio (média ponderada pela área).
-- cobertura = soma das frações de área das células com dado (1 = município todo coberto).
CREATE TABLE clima_municipio (
    data         date    NOT NULL,
    cod_ibge     char(7) NOT NULL REFERENCES municipio (cod_ibge),
    variavel     text    NOT NULL REFERENCES variavel (codigo),
    valor        real    NOT NULL,
    cobertura    real    NOT NULL CHECK (cobertura > 0 AND cobertura <= 1.0001),
    fonte_id     integer NOT NULL REFERENCES fonte (id),
    ingestao_id  integer NOT NULL REFERENCES ingestao (id),
    UNIQUE (fonte_id, cod_ibge, variavel, data)
);
SELECT create_hypertable('clima_municipio', by_range('data', INTERVAL '5 years'));
ALTER TABLE clima_municipio SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'fonte_id, variavel, cod_ibge',
    timescaledb.compress_orderby = 'data'
);

-- Indicadores socioeconômicos (anuais ou por censo). Tabela comum: volume pequeno.
CREATE TABLE indicador_socio (
    cod_ibge   char(7)  NOT NULL REFERENCES municipio (cod_ibge),
    indicador  text     NOT NULL,                -- ex.: 'idhm', 'pib_per_capita'
    ano        smallint NOT NULL,
    valor      double precision NOT NULL,
    unidade    text,
    fonte_id   integer  NOT NULL REFERENCES fonte (id),
    PRIMARY KEY (fonte_id, cod_ibge, indicador, ano)
);

-- migrate:down

DROP TABLE indicador_socio;
DROP TABLE clima_municipio;
DROP TABLE obs_estacao;
DROP TABLE obs_celula;
