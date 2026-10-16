\restrict dbmate

-- Dumped from database version 17.11 (Ubuntu 17.11-1.pgdg22.04+2)
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';


--
-- Name: timescaledb_toolkit; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb_toolkit; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb_toolkit IS 'Library of analytical hyperfunctions, time-series pipelining, and other SQL utilities';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: celula; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.celula (
    id integer NOT NULL,
    grade text NOT NULL,
    lon numeric(8,4) NOT NULL,
    lat numeric(8,4) NOT NULL,
    geom public.geometry(Polygon,4326) NOT NULL
);


--
-- Name: celula_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.celula ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.celula_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: celula_municipio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.celula_municipio (
    celula_id integer NOT NULL,
    cod_ibge character(7) NOT NULL,
    fracao_area double precision NOT NULL,
    CONSTRAINT celula_municipio_fracao_area_check CHECK (((fracao_area > (0)::double precision) AND (fracao_area <= (1)::double precision)))
);


--
-- Name: estacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estacao (
    id integer NOT NULL,
    fonte_id integer NOT NULL,
    codigo_na_fonte text NOT NULL,
    nome text,
    cod_ibge character(7),
    altitude_m double precision,
    ponto public.geometry(Point,4674) NOT NULL
);


--
-- Name: estacao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.estacao ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.estacao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fonte; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fonte (
    id integer NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    versao text NOT NULL,
    formato text,
    frequencia text,
    url text,
    licenca text,
    contato text,
    citacao text,
    CONSTRAINT fonte_tipo_check CHECK ((tipo = ANY (ARRAY['grade'::text, 'estacao'::text, 'socioeconomico'::text])))
);


--
-- Name: fonte_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.fonte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.fonte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ingestao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestao (
    id integer NOT NULL,
    fonte_id integer NOT NULL,
    arquivo text NOT NULL,
    hash_sha256 character(64) NOT NULL,
    iniciada_em timestamp with time zone DEFAULT now() NOT NULL,
    concluida_em timestamp with time zone,
    linhas bigint,
    status text DEFAULT 'em_andamento'::text NOT NULL,
    mensagem text,
    CONSTRAINT ingestao_status_check CHECK ((status = ANY (ARRAY['em_andamento'::text, 'concluida'::text, 'falhou'::text])))
);


--
-- Name: ingestao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ingestao ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ingestao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: mapeamento_variavel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mapeamento_variavel (
    fonte_id integer NOT NULL,
    nome_na_fonte text NOT NULL,
    variavel_codigo text NOT NULL,
    unidade_na_fonte text,
    fator double precision DEFAULT 1 NOT NULL,
    deslocamento double precision DEFAULT 0 NOT NULL
);


--
-- Name: municipio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.municipio (
    cod_ibge character(7) NOT NULL,
    nome text NOT NULL,
    uf character(2) NOT NULL,
    poligono public.geometry(MultiPolygon,4674) NOT NULL,
    CONSTRAINT municipio_cod_ibge_check CHECK ((cod_ibge ~ '^[0-9]{7}$'::text))
);


--
-- Name: municipio_recorte; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.municipio_recorte (
    recorte_id integer NOT NULL,
    cod_ibge character(7) NOT NULL
);


--
-- Name: recorte; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recorte (
    id integer NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    tipo text NOT NULL,
    ano smallint,
    descricao text,
    referencia text
);


--
-- Name: recorte_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.recorte ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.recorte_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: v_celula_municipio_soma; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_celula_municipio_soma AS
 SELECT c.grade,
    cm.cod_ibge,
    sum(cm.fracao_area) AS soma_fracoes,
    count(*) AS n_celulas
   FROM (public.celula_municipio cm
     JOIN public.celula c ON ((c.id = cm.celula_id)))
  GROUP BY c.grade, cm.cod_ibge;


--
-- Name: variavel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.variavel (
    codigo text NOT NULL,
    nome text NOT NULL,
    unidade text NOT NULL,
    descricao text
);


--
-- Name: celula celula_grade_lon_lat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celula
    ADD CONSTRAINT celula_grade_lon_lat_key UNIQUE (grade, lon, lat);


--
-- Name: celula_municipio celula_municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celula_municipio
    ADD CONSTRAINT celula_municipio_pkey PRIMARY KEY (celula_id, cod_ibge);


--
-- Name: celula celula_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celula
    ADD CONSTRAINT celula_pkey PRIMARY KEY (id);


--
-- Name: estacao estacao_fonte_id_codigo_na_fonte_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estacao
    ADD CONSTRAINT estacao_fonte_id_codigo_na_fonte_key UNIQUE (fonte_id, codigo_na_fonte);


--
-- Name: estacao estacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estacao
    ADD CONSTRAINT estacao_pkey PRIMARY KEY (id);


--
-- Name: fonte fonte_codigo_versao_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fonte
    ADD CONSTRAINT fonte_codigo_versao_key UNIQUE (codigo, versao);


--
-- Name: fonte fonte_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fonte
    ADD CONSTRAINT fonte_pkey PRIMARY KEY (id);


--
-- Name: ingestao ingestao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestao
    ADD CONSTRAINT ingestao_pkey PRIMARY KEY (id);


--
-- Name: mapeamento_variavel mapeamento_variavel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mapeamento_variavel
    ADD CONSTRAINT mapeamento_variavel_pkey PRIMARY KEY (fonte_id, nome_na_fonte);


--
-- Name: municipio municipio_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio
    ADD CONSTRAINT municipio_pkey PRIMARY KEY (cod_ibge);


--
-- Name: municipio_recorte municipio_recorte_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio_recorte
    ADD CONSTRAINT municipio_recorte_pkey PRIMARY KEY (recorte_id, cod_ibge);


--
-- Name: recorte recorte_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recorte
    ADD CONSTRAINT recorte_codigo_key UNIQUE (codigo);


--
-- Name: recorte recorte_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recorte
    ADD CONSTRAINT recorte_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: variavel variavel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.variavel
    ADD CONSTRAINT variavel_pkey PRIMARY KEY (codigo);


--
-- Name: celula_geom_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX celula_geom_gix ON public.celula USING gist (geom);


--
-- Name: celula_municipio_cod_ibge_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX celula_municipio_cod_ibge_idx ON public.celula_municipio USING btree (cod_ibge);


--
-- Name: estacao_ponto_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX estacao_ponto_gix ON public.estacao USING gist (ponto);


--
-- Name: ingestao_fonte_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ingestao_fonte_idx ON public.ingestao USING btree (fonte_id);


--
-- Name: municipio_poligono_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX municipio_poligono_gix ON public.municipio USING gist (poligono);


--
-- Name: municipio_recorte_cod_ibge_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX municipio_recorte_cod_ibge_idx ON public.municipio_recorte USING btree (cod_ibge);


--
-- Name: municipio_uf_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX municipio_uf_idx ON public.municipio USING btree (uf);


--
-- Name: celula_municipio celula_municipio_celula_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celula_municipio
    ADD CONSTRAINT celula_municipio_celula_id_fkey FOREIGN KEY (celula_id) REFERENCES public.celula(id);


--
-- Name: celula_municipio celula_municipio_cod_ibge_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.celula_municipio
    ADD CONSTRAINT celula_municipio_cod_ibge_fkey FOREIGN KEY (cod_ibge) REFERENCES public.municipio(cod_ibge);


--
-- Name: estacao estacao_cod_ibge_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estacao
    ADD CONSTRAINT estacao_cod_ibge_fkey FOREIGN KEY (cod_ibge) REFERENCES public.municipio(cod_ibge);


--
-- Name: estacao estacao_fonte_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estacao
    ADD CONSTRAINT estacao_fonte_id_fkey FOREIGN KEY (fonte_id) REFERENCES public.fonte(id);


--
-- Name: ingestao ingestao_fonte_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestao
    ADD CONSTRAINT ingestao_fonte_id_fkey FOREIGN KEY (fonte_id) REFERENCES public.fonte(id);


--
-- Name: mapeamento_variavel mapeamento_variavel_fonte_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mapeamento_variavel
    ADD CONSTRAINT mapeamento_variavel_fonte_id_fkey FOREIGN KEY (fonte_id) REFERENCES public.fonte(id);


--
-- Name: mapeamento_variavel mapeamento_variavel_variavel_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mapeamento_variavel
    ADD CONSTRAINT mapeamento_variavel_variavel_codigo_fkey FOREIGN KEY (variavel_codigo) REFERENCES public.variavel(codigo);


--
-- Name: municipio_recorte municipio_recorte_cod_ibge_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio_recorte
    ADD CONSTRAINT municipio_recorte_cod_ibge_fkey FOREIGN KEY (cod_ibge) REFERENCES public.municipio(cod_ibge);


--
-- Name: municipio_recorte municipio_recorte_recorte_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.municipio_recorte
    ADD CONSTRAINT municipio_recorte_recorte_id_fkey FOREIGN KEY (recorte_id) REFERENCES public.recorte(id);


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('20261014120000'),
    ('20261014120100');
