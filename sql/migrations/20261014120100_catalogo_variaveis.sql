-- migrate:up

-- Variáveis canônicas iniciais (as do BR-DWGD). Valores diários.
INSERT INTO variavel (codigo, nome, unidade, descricao) VALUES
    ('pr',   'Precipitação',                     'mm',      'Precipitação acumulada no dia'),
    ('tmax', 'Temperatura máxima do ar',         'degC',    'Temperatura máxima diária a 2 m'),
    ('tmin', 'Temperatura mínima do ar',         'degC',    'Temperatura mínima diária a 2 m'),
    ('rs',   'Radiação solar global',            'MJ m-2',  'Radiação solar incidente acumulada no dia'),
    ('rh',   'Umidade relativa do ar',           '%',       'Umidade relativa média diária'),
    ('u2',   'Velocidade do vento a 2 m',        'm s-1',   'Velocidade média diária do vento a 2 m'),
    ('eto',  'Evapotranspiração de referência',  'mm',      'ETo diária (FAO-56 Penman-Monteith)');

-- migrate:down

DELETE FROM variavel WHERE codigo IN ('pr', 'tmax', 'tmin', 'rs', 'rh', 'u2', 'eto');
