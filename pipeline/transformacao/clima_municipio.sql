-- Clima por município: média das células ponderada pela fração de área.
--
-- valor     = Σ(valor_célula × fração) / Σ(fração), só sobre células COM dado no dia.
-- cobertura = Σ(fração) das células com dado. Se um município do litoral tem 5%% da área
--             numa célula sem dado (mar ou fora da grade), a média usa os outros 95%% e
--             cobertura = 0,95. Quem consulta decide se aceita cobertura baixa.
--
-- Parâmetros: fonte_id, grade, inicio, fim. Recalcula o período (upsert).

INSERT INTO clima_municipio (data, cod_ibge, variavel, valor, cobertura, fonte_id, ingestao_id)
SELECT o.data,
       cm.cod_ibge,
       o.variavel,
       sum(o.valor * cm.fracao_area) / sum(cm.fracao_area),
       LEAST(sum(cm.fracao_area), 1),
       o.fonte_id,
       max(o.ingestao_id)      -- num mesmo dia e variável, as células vêm do mesmo arquivo
FROM obs_celula o
JOIN celula c            ON c.id = o.celula_id AND c.grade = %(grade)s
JOIN celula_municipio cm ON cm.celula_id = o.celula_id
WHERE o.fonte_id = %(fonte_id)s
  AND o.data BETWEEN %(inicio)s AND %(fim)s
GROUP BY o.data, cm.cod_ibge, o.variavel, o.fonte_id
ON CONFLICT (fonte_id, cod_ibge, variavel, data) DO UPDATE
   SET valor = EXCLUDED.valor,
       cobertura = EXCLUDED.cobertura,
       ingestao_id = EXCLUDED.ingestao_id;
