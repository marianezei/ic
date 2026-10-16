-- migrate:up

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Fonte de dados. Cada versão de um dataset é uma linha (ex.: xavier v_3.2.4).
CREATE TABLE fonte (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo      text NOT NULL,                 -- ex.: 'xavier', 'inmet', 'chirps'
    nome        text NOT NULL,
    tipo        text NOT NULL CHECK (tipo IN ('grade', 'estacao', 'socioeconomico')),
    versao      text NOT NULL,
    formato     text,
    frequencia  text,
    url         text,
    licenca     text,
    contato     text,
    citacao     text,
    UNIQUE (codigo, versao)
);

-- Catálogo de variáveis canônicas. Unidades em notação UDUNITS/CF.
CREATE TABLE variavel (
    codigo     text PRIMARY KEY,               -- ex.: 'pr', 'tmax'
    nome       text NOT NULL,
    unidade    text NOT NULL,
    descricao  text
);

-- Nome na fonte -> variável canônica. valor_canonico = valor_fonte * fator + deslocamento.
CREATE TABLE mapeamento_variavel (
    fonte_id         integer NOT NULL REFERENCES fonte (id),
    nome_na_fonte    text    NOT NULL,
    variavel_codigo  text    NOT NULL REFERENCES variavel (codigo),
    unidade_na_fonte text,
    fator            double precision NOT NULL DEFAULT 1,
    deslocamento     double precision NOT NULL DEFAULT 0,
    PRIMARY KEY (fonte_id, nome_na_fonte)
);

-- Municípios. Polígono em SIRGAS 2000 (EPSG:4674), como vem do IBGE.
CREATE TABLE municipio (
    cod_ibge  char(7) PRIMARY KEY CHECK (cod_ibge ~ '^[0-9]{7}$'),
    nome      text    NOT NULL,
    uf        char(2) NOT NULL,
    poligono  geometry(MultiPolygon, 4674) NOT NULL
);
CREATE INDEX municipio_poligono_gix ON municipio USING gist (poligono);
CREATE INDEX municipio_uf_idx ON municipio (uf);

-- Recortes como dado: semiárido SUDENE de um ano, UF, bacia etc.
CREATE TABLE recorte (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo     text NOT NULL UNIQUE,           -- ex.: 'semiarido_sudene_2021'
    nome       text NOT NULL,
    tipo       text NOT NULL,                  -- ex.: 'semiarido', 'uf'
    ano        smallint,
    descricao  text,
    referencia text                            -- ato normativo / URL de origem
);

CREATE TABLE municipio_recorte (
    recorte_id integer NOT NULL REFERENCES recorte (id),
    cod_ibge   char(7) NOT NULL REFERENCES municipio (cod_ibge),
    PRIMARY KEY (recorte_id, cod_ibge)
);
CREATE INDEX municipio_recorte_cod_ibge_idx ON municipio_recorte (cod_ibge);

-- Células de grade. 'grade' distingue grades diferentes (Xavier 0,1°, CHIRPS 0,05°, ERA5 0,25°).
-- lon/lat são o centro da célula; geom é o quadrado em WGS 84 (EPSG:4326).
CREATE TABLE celula (
    id     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    grade  text    NOT NULL,                   -- ex.: 'xavier_0.1'
    lon    numeric(8, 4) NOT NULL,
    lat    numeric(8, 4) NOT NULL,
    geom   geometry(Polygon, 4326) NOT NULL,
    UNIQUE (grade, lon, lat)
);
CREATE INDEX celula_geom_gix ON celula USING gist (geom);

-- Ponte grade -> município. fracao_area = parte da área do MUNICÍPIO coberta pela célula,
-- calculada em projeção de área igual. Para cada (grade, município) a soma deve ser 1.
CREATE TABLE celula_municipio (
    celula_id   integer NOT NULL REFERENCES celula (id),
    cod_ibge    char(7) NOT NULL REFERENCES municipio (cod_ibge),
    fracao_area double precision NOT NULL CHECK (fracao_area > 0 AND fracao_area <= 1),
    PRIMARY KEY (celula_id, cod_ibge)
);
CREATE INDEX celula_municipio_cod_ibge_idx ON celula_municipio (cod_ibge);

-- Verificação: municípios cuja soma de frações se afasta de 1.
CREATE VIEW v_celula_municipio_soma AS
SELECT c.grade,
       cm.cod_ibge,
       sum(cm.fracao_area) AS soma_fracoes,
       count(*)            AS n_celulas
FROM celula_municipio cm
JOIN celula c ON c.id = cm.celula_id
GROUP BY c.grade, cm.cod_ibge;

-- Estações de medição. Ponto em SIRGAS 2000.
CREATE TABLE estacao (
    id              integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fonte_id        integer NOT NULL REFERENCES fonte (id),
    codigo_na_fonte text    NOT NULL,
    nome            text,
    cod_ibge        char(7) REFERENCES municipio (cod_ibge),
    altitude_m      double precision,
    ponto           geometry(Point, 4674) NOT NULL,
    UNIQUE (fonte_id, codigo_na_fonte)
);
CREATE INDEX estacao_ponto_gix ON estacao USING gist (ponto);

-- Cada carga de arquivo no banco. Toda observação aponta para uma ingestão.
CREATE TABLE ingestao (
    id            integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fonte_id      integer NOT NULL REFERENCES fonte (id),
    arquivo       text    NOT NULL,            -- caminho relativo na camada bronze
    hash_sha256   char(64) NOT NULL,
    iniciada_em   timestamptz NOT NULL DEFAULT now(),
    concluida_em  timestamptz,
    linhas        bigint,
    status        text NOT NULL DEFAULT 'em_andamento'
                  CHECK (status IN ('em_andamento', 'concluida', 'falhou')),
    mensagem      text
);
CREATE INDEX ingestao_fonte_idx ON ingestao (fonte_id);

-- migrate:down

DROP TABLE ingestao;
DROP TABLE estacao;
DROP VIEW v_celula_municipio_soma;
DROP TABLE celula_municipio;
DROP TABLE celula;
DROP TABLE municipio_recorte;
DROP TABLE recorte;
DROP TABLE municipio;
DROP TABLE mapeamento_variavel;
DROP TABLE variavel;
DROP TABLE fonte;
