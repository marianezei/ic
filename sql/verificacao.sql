-- Consultas de conferência do protótipo. Rodar com: make verificar
-- Também servem de exemplo de como consultar o banco.

\echo '== 1. Contagem por tabela'
SELECT 'fonte' AS tabela, count(*) FROM fonte
UNION ALL SELECT 'mapeamento_variavel', count(*) FROM mapeamento_variavel
UNION ALL SELECT 'municipio', count(*) FROM municipio
UNION ALL SELECT 'recorte', count(*) FROM recorte
UNION ALL SELECT 'municipio_recorte', count(*) FROM municipio_recorte
UNION ALL SELECT 'celula', count(*) FROM celula
UNION ALL SELECT 'celula_municipio', count(*) FROM celula_municipio
UNION ALL SELECT 'ingestao', count(*) FROM ingestao
UNION ALL SELECT 'obs_celula', count(*) FROM obs_celula
UNION ALL SELECT 'clima_municipio', count(*) FROM clima_municipio
UNION ALL SELECT 'clima_municipio_mensal', count(*) FROM clima_municipio_mensal;

\echo '== 2. Recortes'
SELECT r.codigo, r.ano, count(mr.cod_ibge) AS municipios
FROM recorte r LEFT JOIN municipio_recorte mr ON mr.recorte_id = r.id
GROUP BY r.codigo, r.ano ORDER BY r.codigo;

\echo '== 3. Soma das frações por município (deve ser 1)'
SELECT round(min(soma_fracoes)::numeric, 6) AS minimo,
       round(max(soma_fracoes)::numeric, 6) AS maximo,
       count(*) AS municipios,
       round(avg(n_celulas), 1) AS media_celulas_por_municipio,
       min(n_celulas) AS min_celulas
FROM v_celula_municipio_soma;

\echo '== 4. Municípios menores que uma célula (maior fração de área numa única célula)'
SELECT m.nome, round(max(cm.fracao_area)::numeric, 3) AS maior_fracao, count(*) AS n_celulas
FROM celula_municipio cm JOIN municipio m USING (cod_ibge)
GROUP BY m.nome ORDER BY n_celulas, maior_fracao DESC LIMIT 5;

\echo '== 5. Ingestões (rastreabilidade)'
SELECT i.id, f.codigo || ' ' || f.versao AS fonte, i.arquivo, left(i.hash_sha256, 12) AS hash, i.linhas, i.status
FROM ingestao i JOIN fonte f ON f.id = i.fonte_id ORDER BY i.id;

\echo '== 6. Clima de 3 municípios em 2024-04-15 (litoral, agreste, sertão)'
SELECT m.nome, c.variavel, round(c.valor::numeric, 2) AS valor, v.unidade,
       round(c.cobertura::numeric, 3) AS cobertura, c.ingestao_id
FROM clima_municipio c
JOIN municipio m USING (cod_ibge)
JOIN variavel v ON v.codigo = c.variavel
WHERE m.nome IN ('João Pessoa', 'Campina Grande', 'Sousa')
ORDER BY m.nome, c.variavel;

\echo '== 7. Municípios com menor cobertura (litoral, células sem dado)'
SELECT m.nome, c.variavel, round(c.cobertura::numeric, 3) AS cobertura
FROM clima_municipio c JOIN municipio m USING (cod_ibge)
WHERE c.variavel = 'pr' ORDER BY c.cobertura LIMIT 5;

\echo '== 8. Média do semiárido x fora do semiárido na PB (pr, 2024-04-15)'
SELECT CASE WHEN mr.cod_ibge IS NULL THEN 'fora do semiárido' ELSE 'semiárido' END AS grupo,
       count(*) AS municipios, round(avg(c.valor)::numeric, 2) AS pr_media_mm
FROM clima_municipio c
LEFT JOIN municipio_recorte mr
       ON mr.cod_ibge = c.cod_ibge
      AND mr.recorte_id = (SELECT id FROM recorte WHERE codigo = 'semiarido_sudene_2021')
WHERE c.variavel = 'pr'
GROUP BY 1;

\echo '== 9. Agregado mensal (abril/2024, só 1 dia carregado: n_dias = 1)'
SELECT m.nome, a.variavel, round(a.soma::numeric, 2) AS soma, round(a.media::numeric, 2) AS media, a.n_dias
FROM clima_municipio_mensal a JOIN municipio m USING (cod_ibge)
WHERE m.nome = 'Campina Grande' ORDER BY a.variavel;

\echo '== 10. Tamanho das hypertables'
SELECT hypertable_name, pg_size_pretty(hypertable_size(format('%I', hypertable_name)::regclass)) AS tamanho
FROM timescaledb_information.hypertables ORDER BY 1;
