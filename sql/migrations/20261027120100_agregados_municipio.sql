-- migrate:up transaction:false

-- Agregados contínuos (continuous aggregates) do Timescale não podem ser criados dentro
-- de uma transação, por isso esta migração roda com transaction:false.
--
-- Guardamos soma, média, mínimo e máximo: quem consulta escolhe o que faz sentido para a
-- variável (chuva mensal = soma; temperatura mensal = média). n_dias mostra se o período
-- está completo (um mês com 20 dias de dado não tem "chuva mensal" comparável).
--
-- Os dados são históricos e chegam em lote, então não há política de atualização
-- automática: o pipeline chama refresh_continuous_aggregate depois de cada carga.

CREATE MATERIALIZED VIEW clima_municipio_mensal
WITH (timescaledb.continuous, timescaledb.materialized_only = true) AS
SELECT time_bucket(INTERVAL '1 month', data) AS mes,
       fonte_id,
       cod_ibge,
       variavel,
       sum(valor)  AS soma,
       avg(valor)  AS media,
       min(valor)  AS minimo,
       max(valor)  AS maximo,
       count(*)    AS n_dias
FROM clima_municipio
GROUP BY 1, 2, 3, 4
WITH NO DATA;

CREATE MATERIALIZED VIEW clima_municipio_anual
WITH (timescaledb.continuous, timescaledb.materialized_only = true) AS
SELECT time_bucket(INTERVAL '1 year', data) AS ano,
       fonte_id,
       cod_ibge,
       variavel,
       sum(valor)  AS soma,
       avg(valor)  AS media,
       min(valor)  AS minimo,
       max(valor)  AS maximo,
       count(*)    AS n_dias
FROM clima_municipio
GROUP BY 1, 2, 3, 4
WITH NO DATA;

-- migrate:down transaction:false

DROP MATERIALIZED VIEW clima_municipio_anual;
DROP MATERIALIZED VIEW clima_municipio_mensal;
