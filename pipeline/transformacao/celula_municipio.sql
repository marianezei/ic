-- Ponte grade -> município para uma grade (%(grade)s).
--
-- fracao_area = área(célula ∩ município) / área(município), as duas medidas numa projeção
-- de área igual (ESRI:102033, Albers para a América do Sul). Em graus a área sai errada,
-- porque um grau de longitude encolhe à medida que se afasta do equador.
--
-- ST_Segmentize adensa as bordas antes de reprojetar: um lado reto em graus vira levemente
-- curvo em Albers, e sem vértices intermediários essa curvatura se perderia.
--
-- Recalcula a grade inteira (apaga e insere de novo), então pode rodar quantas vezes precisar.

DELETE FROM celula_municipio cm
USING celula c
WHERE c.id = cm.celula_id AND c.grade = %(grade)s;

WITH pares AS (
    SELECT c.id AS celula_id,
           m.cod_ibge,
           ST_Transform(ST_Segmentize(c.geom, 0.01), 102033)                AS g_celula,
           ST_Transform(ST_Transform(m.poligono, 4326), 102033)             AS g_mun
    FROM celula c
    JOIN municipio m
      ON ST_Intersects(c.geom, ST_Transform(m.poligono, 4326))           -- usa o índice espacial
    WHERE c.grade = %(grade)s
),
areas AS (
    SELECT celula_id, cod_ibge,
           ST_Area(ST_Intersection(g_celula, g_mun)) AS area_inter,
           ST_Area(g_mun)                            AS area_mun
    FROM pares
)
INSERT INTO celula_municipio (celula_id, cod_ibge, fracao_area)
SELECT celula_id, cod_ibge, LEAST(area_inter / area_mun, 1)
FROM areas
WHERE area_inter > 0;
