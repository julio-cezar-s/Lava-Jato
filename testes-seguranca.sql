-- Roteiro de verificação de segurança do banco do lava-jato (supabase.sql)
-- Como usar: Supabase > SQL Editor > New query > cole tudo > Run.
-- Não deixa nada gravado: tudo roda dentro de um único bloco que termina com um erro proposital
-- ("RESULTADO DOS TESTES"), o que desfaz os dados de teste. A mensagem desse erro começa com o resumo
-- (quantos OK, FALHOU e AVISO), depois lista só os problemas e, por fim, todos os detalhes.
-- Cada linha começa com OK, FALHOU (algo errado), AVISO (não foi possível concluir, revisar) ou INFO. Pode rodar quantas vezes quiser.
--
-- O QUE ESTE ROTEIRO COBRE (inventário do supabase.sql: 33 funções e 19 tabelas)
--   • 9 funções públicas (anon): config_publica, contatos_publicos, aviso_publico, horarios_disponiveis, criar_pedido,
--     acompanhar_pedido, enviar_avaliacao, avaliacoes_publicas, resumo_avaliacoes
--   • 24 funções restritas: 17 só para logados (is_admin, meu_papel, 4 de funcionário "staff_*" e 11 só do administrador)
--     e 7 internas que ninguém chama pela API (ip_do_cliente, consulta_travar, consulta_verificar, consulta_registrar,
--     chave_cliente, historico_usuario, registrar_historico_pedido)
--   • 19 tabelas: leitura, inserção, alteração e exclusão como público (anon), usuário logado sem permissão,
--     funcionário e administrador
--   • armazenamento de fotos (bucket "fotos" e as políticas de storage.objects)
--   • consulta de pedidos: limites por telefone/IP, travas, IP confiável (testes 0 a 8f)
--
-- COMO OS PAPÉIS SÃO SIMULADOS (sem usuários reais, sem gravar nada)
--   Dentro da transação o roteiro cria 3 usuários falsos em auth.users (administrador, funcionário, logado sem
--   permissão), liga-os a admins/funcionarios e troca de papel como o PostgREST faz (role anon/authenticated + claims do JWT).
--   Cada comando de teste roda num sub-bloco que é desfeito logo depois de medir o resultado, e o bloco inteiro termina
--   em erro, então nem os dados de teste nem as operações destrutivas permanecem. Se o seu projeto não permitir
--   criar usuários em auth.users por SQL, os testes de funcionário e administrador são pulados com um AVISO.
--   Uma única coisa fica para trás mesmo com o desfazer: os números de identidade (contadores de id) avançam,
--   o que só deixa "buracos" na numeração dos próximos pedidos e é inofensivo.
--
-- LEGENDA das linhas de tabelas: 4 símbolos por tabela, na ordem leitura, inserção, alteração, exclusão:
--   N = negado ("permissão negada" / política de linha)   0 = executou mas não alcançou nenhuma linha (RLS)
--   + = permitido (alcançou linhas)                        ? = erro inesperado (a linha FALHOU mostra o código)
-- LEGENDA das linhas de funções: A = funcionou sem erro; B = recusou com o erro de regra de negócio esperado (criar_pedido,
--   enviar_avaliacao e remarcar_pedido, que o teste chama com dados propositalmente inválidos); N = "nao_autorizado" (recusou por
--   dentro); D = negado (sem permissão de execução); X = erro inesperado (a linha FALHOU mostra o código).
--
--
-- LIMITES CONHECIDOS DO ROTEIRO (o que ele NÃO prova)
--   • É uma simulação em SQL: confirma tabelas, RLS, grants, funções e as políticas de storage, mas não passa pelo PostgREST,
--     pelo login, pela validação do JWT nem pela API de Storage (ver R1 a R6 abaixo).
--   • "0 linhas" só prova bloqueio se a linha existe: por isso há um controle positivo antes das matrizes (seção 13).
--   • AVISO não é aprovação: é algo que o roteiro não conseguiu concluir ou que merece decisão sua.
--   • TRUNCATE, REFERENCES, TRIGGER e MAINTAIN: o Supabase os concede por padrão a anon e authenticated (o "grant all" do PostgreSQL 17
--     inclui MAINTAIN, que não existe antes do 17). O supabase.sql agora os revoga de anon, authenticated e PUBLIC nas tabelas
--     atuais e como padrão das tabelas futuras criadas pelo papel que roda o arquivo; a seção 12 comprova isso (permissão efetiva,
--     PUBLIC, herança, papel pg_maintain, padrão de tabelas futuras e uma tabela de teste). Os privilégios padrão do papel
--     supabase_admin (da plataforma) não podem ser alterados pelo projeto e aparecem como AVISO. LOCK TABLE continua possível ao
--     logado por causa de UPDATE e DELETE (necessários ao painel): isso é informado, não corrigido.
--   • Projeto novo (A1): desde 30/10/2026 o Supabase não concede mais privilégios automáticos às tabelas novas de public. O supabase.sql
--     agora concede ao authenticated, de forma explícita e mínima, só o que o painel usa (bloco "Permissões de tabela do painel").
--     A seção 13c simula um projeto novo dentro da transação (zera os privilégios do authenticated, aplica o mesmo bloco e repete as
--     matrizes) e a 13d confere o estado real. A prova definitiva continua sendo rodar o supabase.sql e este roteiro num projeto Supabase novo.
--   • Sequências (M2): as colunas de id das 19 tabelas são todas IDENTITY always; não há SERIAL, sequência avulsa nem chamada a nextval,
--     currval, setval ou lastval no supabase.sql. As seções 12j e 12k medem isso no banco e provam, com objetos de teste desfeitos, que IDENTITY
--     dispensa privilégio de sequência e que SERIAL o exige (controle). A seção 13c só conclui que o painel funciona sem sequências se os
--     privilégios de sequência estiverem mesmo zerados.
--   • Pré-checagem da 13c (M3): depois de zerar as concessões diretas, confere os privilégios EFETIVOS que sobram ao authenticated nas 19 tabelas e
--     em todas as sequências de public (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER e, no PostgreSQL 17+, MAINTAIN; USAGE, SELECT
--     e UPDATE nas sequências), inclusive por coluna, via PUBLIC, via papel herdado, via pg_read_all_data, pg_write_all_data ou pg_maintain e por
--     superusuário. Se sobrar algo, mostra a origem e NÃO executa as matrizes: a simulação aparece como não concluída (AVISO e linha de cobertura).
--   • Necessidades reais x GRANTs (M1): a 13c NÃO usa a lista de GRANTs como gabarito. As necessidades do painel (tabela:privilégio) vêm de uma lista de
--     operações reais extraída do index.html por um programa à parte; a 13c executa essas operações como administrador, compara os privilégios efetivos
--     com as necessidades (FALTA = operação sem privilégio; SOBRA = privilégio sem uso) e prova, com uma falta e uma sobra provocadas de propósito, que a
--     comparação e a execução detectam diferenças. Se o painel mudar, gere de novo a lista (o index.html é a fonte da verdade).
--   • Excedente revogado (M4): o supabase.sql revoga 21 privilégios que o authenticated herdou do padrão antigo e o painel não usa. A matriz real da
--     seção 13 espera agora, para anon e para os papéis logados, "permitido" só onde a operação é necessária (administrador) ou barrada pelo RLS
--     (demais papéis) e "negado" por privilégio de tabela onde não é; a 13d exige que não reste excedente; a 13e simula o padrão antigo e prova que o
--     script converge ao estado mínimo sem tirar nada necessário. Sequências não foram tocadas.
--   • Permissões por coluna (M5): em pedidos, avaliacoes e funcionarios o INSERT e o UPDATE valem só nas colunas que o painel usa (o texto "(colunas: ...)"
--     de cada operação da lista extraída do index.html). O comparador (z_cmp) confere por coluna nessas três tabelas (has_column_privilege; INSERT ou UPDATE
--     de tabela inteira é SOBRA) e as seções 13, 13c e 13e rodam SONDAS DE ZERO LINHA em cada coluna (update t set c = c where false; insert into t (c)
--     select c from t where false): sem linhas não há RLS, gatilho nem constraint, então "negado" é privilégio. Controles: coluna usada tem de dar 0 linhas
--     (sem erro) e UPDATE/INSERT em pedidos_historico (revogados no M4) têm de dar negado; sem controle válido o resultado é AVISO, nunca OK. A 13c ainda
--     provoca de propósito uma SOBRA e uma FALTA por coluna e exige que o comparador e as sondas as enxerguem. Se o painel passar a escrever outra coluna,
--     atualize "(colunas: ...)" nas 4 cópias da lista e o bloco "Permissões por coluna (M5)" do supabase.sql.
-- ======================================================================================================
-- TESTES QUE EXIGEM USUÁRIOS REAIS NO SUPABASE (não dá para fazer só com SQL)
--   R1. Login e papéis pela API de verdade (PostgREST): obter o token de 3 contas reais (sem papel, funcionário
--       vinculado, administrador) e repetir, em /rest/v1/<tabela> e /rest/v1/rpc/<função>, as mesmas leituras,
--       inserções, alterações e exclusões desta matriz. Esperado: o mesmo resultado (401/403/erro 42501 ou lista vazia).
--   R2. Token inválido, expirado, de outro projeto ou sem token: deve dar 401; só a chave anon: só o que o público pode.
--   R3. Storage pela API: com admin, enviar JPEG de até 3 MB (deve funcionar), listar, gerar link assinado e apagar;
--       com funcionário e sem papel, tudo isso deve ser negado; arquivo acima de 3 MB ou que não seja JPEG deve ser
--       recusado pelo bucket; o endereço público (/storage/v1/object/public/fotos/...) não pode abrir a foto.
--       (Aqui só se testa por SQL o que as políticas permitem; o envio de arquivo, os limites e os links são da API.)
--   R4. Vínculo de funcionário pelo painel com um usuário real criado em Authentication > Users, e perda do acesso
--       quando o funcionário é desativado ou desvinculado.
--   R5. Chave service_role: nunca pode aparecer em index.html nem em nenhum arquivo do site (procure por "service_role"
--       e por chaves que comecem com "eyJ" para conferir que só a chave anon está lá).
--   R6. IP real pela Cloudflare do Supabase (IPv4 e IPv6, cabeçalhos forjados) e concorrência (várias conexões ao mesmo tempo).
-- COMO EXECUTAR COM SEGURANÇA
--   1. O ideal é um projeto Supabase separado (o plano gratuito serve): crie-o, rode o supabase.sql inteiro e faça lá
--      todos os testes destrutivos. Assim não há risco para os dados do lava-jato.
--   2. Se tiver de ser no projeto real: antes, confira o backup (Database > Backups) e faça os testes fora do horário de
--      movimento. Crie 3 usuários só de teste em Authentication > Users (por exemplo teste-sem@, teste-func@ e
--      teste-admin@ no seu domínio), cada um com senha forte e exclusiva, e anote os ids.
--   3. Torne o usuário de teste administrador só durante o teste (insert em admins) e remova no fim. O funcionário
--      de teste deve ser criado e vinculado pelo painel, e desvinculado no fim. Não use a conta do dono.
--   4. Obtenha o token só com a chave anon (pública) e a senha do usuário de teste (endpoint de login do Supabase).
--      NUNCA use a chave service_role em testes, nunca a cole em chats ou arquivos, e não guarde tokens depois.
--   5. Faça inserções, alterações e exclusões só em registros criados por você, com nome começando por TESTE, usando
--      sempre filtro por id (nunca apagar ou alterar sem "where"). Guarde as fotos de teste em teste-seg/ no bucket.
--   6. No fim: apague as fotos de teste, os registros TESTE, tire o usuário de teste de admins e de funcionarios, apague
--      os usuários de teste e confira que "select * from admins" mostra só o dono.
--   7. Evite repetir em laço as consultas de pedido (acompanhar_pedido) a partir da sua rede: os limites por IP existem
--      para bloquear justamente isso, e você ficaria bloqueado por algumas horas.
--
do $$
declare
  v_res text := '';
  v_id2 bigint; v_cod1 text; v_cod2 text; n int; i int; v_primeiro int; v_ok boolean; v_msg text; v_det text; r record;
  tel1 text := '69970000001';
  tel2 text := '69970000002';
  telx text := '69960000099';
  telz text := '69960000050';
  -- ampliação (testes 11 a 16): identificadores, usuários simulados e auxiliares
  z_users boolean := true; z_storage boolean := true;
  z_adm uuid := '00000000-0000-0000-0000-0000000000a1';
  z_func uuid := '00000000-0000-0000-0000-0000000000f1';
  z_sem uuid := '00000000-0000-0000-0000-0000000000aa';
  z_uid uuid;
  z_srv1 bigint; z_srv3 bigint; z_srv2 bigint; z_cli bigint; z_ped1 bigint; z_ped2 bigint; z_ped3 bigint; z_av bigint; z_av3 bigint;
  z_f1 bigint; z_f2 bigint;
  z_papeis text[] := array['anon', 'sem', 'func', 'admin'];
  z_tabs text[] := array['servicos', 'clientes', 'precos_cliente', 'pedidos', 'config', 'contatos', 'dias_fechados',
    'despesas', 'avaliacoes', 'avaliacao_fotos', 'fotos_pedido', 'admins', 'tentativas_consulta', 'cliente_notas',
    'funcionarios', 'telefones_bloqueados', 'bloqueios_horario', 'vistoria_avarias', 'pedidos_historico'];
  z_papel text; z_tab text; z_op text; z_sql text; z_exp text; z_got text; z_sim text; z_linha text; z_falhas text;
  z_avisos text; z_d text; z_e text; z_f text; z_ver int; z_privs text[]; z_x1 text; z_x2 text; z_simok boolean; z_ck_sim int := 0; z_rsim int := 0; z_idtabs text[]; z_idn int := 0; z_idfail text := ''; z_seqok boolean := true; z_seqs text; z_q1 int; z_q2 int; z_q3 int; z_q4 int := 0; z_s0 text; z_s1 text; z_s2 text; z_s3 text; z_s4 text; z_s5 text; z_s6 text; z_need text[]; z_cmp text; z_m1t text; z_m1c text; z_m2t text; z_m2p text; z_pall text[]; z_auth oid; z_ra boolean; z_wa boolean; z_ma boolean; z_su boolean; z_prob text; z_a text; z_b text; z_c text; z_sig text; z_cls text; z_ok2 boolean;
  z_n1 int; z_n2 int; z_n3 int; z_nfn int;
  z_oid regprocedure; z_oids oid[] := '{}';
  z_pub boolean; z_lim bigint; z_mime text[];
  z_r record;
  z_ck_tab int := 0; z_ck_fn int := 0; z_ck_st int := 0; z_rt int := 0; z_rf int := 0; z_rs int := 0;
  q text;
  -- M5 (permissões por coluna): tabelas restritas, necessidades por coluna, sondas de zero linha e testes de sensibilidade
  z_colrestr text[] := array['pedidos', 'avaliacoes', 'funcionarios'];
  z_needc text[]; z_cobre text;
  z_sondas_sql text[]; z_sondas_exp text[]; z_sondas_rot text[];
  z_si int; z_sonda_got text; z_sonda_fal text; z_sonda_inc text; z_sonda_ctl text; z_sonda_n int;
  z_pe text; z_pd text;
  z_c1 text; z_c2 text; z_c3 text; z_c4 text; z_c5 text;
begin
  perform set_config('lock_timeout', '5s', true);   -- nunca esperar mais de 5 s por um bloqueio de outra sessão
  -- Dois pedidos de teste (desfeitos no fim)
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.10"}', true);
  insert into pedidos (nome, telefone, veiculo, status) values ('TESTE SEGURANCA 1', tel1, 'TESTE', 'novo')
    returning codigo into v_cod1;
  insert into pedidos (nome, telefone, veiculo, status) values ('TESTE SEGURANCA 2', tel2, 'TESTE', 'pronto')
    returning id, codigo into v_id2, v_cod2;

  -- 0) identificação do IP (função interna: roda antes de virar "anon"). Só vale cf-connecting-ip; x-real-ip e
  --    x-forwarded-for, que o visitante pode forjar, são ignorados; IPv6 é agrupado pelo bloco /64
  for r in select * from (values
    ('IPv4 comum',                          '{"cf-connecting-ip":"203.0.113.10"}',                                  '203.0.113.10'),
    ('cf-connecting-ip vale mais que x-real-ip', '{"cf-connecting-ip":"203.0.113.10","x-real-ip":"198.51.100.99"}', '203.0.113.10'),
    ('x-real-ip sozinho é ignorado',        '{"x-real-ip":"198.51.100.99"}',                                         null),
    ('x-forwarded-for sozinho é ignorado',  '{"x-forwarded-for":"198.51.100.99, 10.0.0.1"}',                         null),
    ('sem cabeçalhos',                      '{}',                                                                    null),
    ('IPv6 vira o bloco /64',               '{"cf-connecting-ip":"2001:db8:aaaa:bbbb:1:2:3:4"}',                     '2001:db8:aaaa:bbbb::/64'),
    ('IPv6 do mesmo /64, outro final',      '{"cf-connecting-ip":"2001:db8:aaaa:bbbb:ffff:ffff:ffff:ffff"}',         '2001:db8:aaaa:bbbb::/64'),
    ('IPv6 abreviado e em maiúsculas',      '{"cf-connecting-ip":"2001:DB8:AAAA:BBBB::1"}',                          '2001:db8:aaaa:bbbb::/64'),
    ('IPv6 de outro /64 é outro grupo',     '{"cf-connecting-ip":"2001:db8:aaaa:cccc::1"}',                          '2001:db8:aaaa:cccc::/64'),
    ('IPv4 escrito como IPv6 vira IPv4',    '{"cf-connecting-ip":"::ffff:203.0.113.5"}',                             '203.0.113.5'),
    ('IPv4 em IPv6 na forma hexadecimal',   '{"cf-connecting-ip":"::ffff:cb00:7105"}',                               '203.0.113.5'),
    ('lista de IPs é rejeitada',            '{"cf-connecting-ip":"203.0.113.5, 198.51.100.1"}',                      'invalido'),
    ('texto qualquer é rejeitado',          '{"cf-connecting-ip":"abc"}',                                            'invalido'),
    ('IP com máscara é rejeitado',          '{"cf-connecting-ip":"203.0.113.0/24"}',                                 'invalido')
  ) as t(descr, hdr, esperado) loop
    begin
      perform set_config('request.headers', r.hdr, true);
      v_det := ip_do_cliente();
      v_ok := v_det is not distinct from r.esperado;
    exception when others then
      v_ok := false; v_det := 'erro: ' || sqlerrm;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'IP: ' || r.descr || ' (recebido: ' || coalesce(v_det, 'nulo') || ')' || E'\n';
  end loop;
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.10"}', true);

  execute 'set local role anon';

  -- 1) avaliar sem ter consultado antes: erro genérico, mesmo com telefone e código certos
  begin
    perform enviar_avaliacao(tel2, v_cod2, 5, 'teste', '{}');
    v_ok := false;
  exception when others then
    v_ok := position('pedido_nao_encontrado' in sqlerrm) > 0;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'avaliar sem consulta prévia retorna erro genérico' || E'\n';

  -- 2) consulta correta funciona
  select count(*) into n from acompanhar_pedido(tel1, v_cod1);
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'consulta correta retorna o pedido' || E'\n';

  -- 2b) a consulta tomou as travas contra requisições simultâneas (uma do telefone e uma do IP) e as mantém até o fim
  --      da transação; este roteiro roda tudo numa transação só, então elas continuam visíveis em pg_locks
  begin
    select count(*) into n from pg_locks
     where locktype = 'advisory' and objsubid = 1 and pid = pg_backend_pid() and granted;
    v_ok := n >= 2; v_det := 'travas encontradas: ' || n;
  exception when others then
    v_ok := false; v_det := sqlerrm;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'consulta trava telefone e IP (' || v_det || ')' || E'\n';

  -- 3) cinco erros seguidos no mesmo telefone: ainda respondem "não achou"
  v_ok := true;
  for i in 1..5 loop
    select count(*) into n from acompanhar_pedido(tel1, 'ZZZZ0' || i);
    if n <> 0 then v_ok := false; end if;
  end loop;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'cinco erros seguidos respondem "não achou"' || E'\n';

  -- 4) depois do 5º erro, o telefone fica bloqueado, até com o código certo
  --    (os horários das tentativas usam clock_timestamp(), então o acerto do teste 2 fica ANTES dos 5 erros do
  --    teste 3; com now() todos teriam o mesmo horário e o bloqueio não apareceria)
  v_det := 'a consulta NÃO foi bloqueada';
  begin
    perform count(*) from acompanhar_pedido(tel1, v_cod1);
    v_ok := false;
  exception when others then
    v_ok := position('muitas_tentativas' in sqlerrm) > 0;
    v_det := 'erro recebido: ' || sqlerrm;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'telefone bloqueado depois de 5 erros seguidos (mesmo com código certo)' || case when v_ok then '' else ' [' || v_det || ']' end || E'\n';

  -- 5) o bloqueio de um telefone não atinge outro
  select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'outro telefone continua funcionando' || E'\n';

  -- 6) avaliar depois de consultar com sucesso é aceito (pedido 2 está "pronto")
  begin
    perform enviar_avaliacao(tel2, v_cod2, 5, 'teste', '{}');
    v_ok := true;
  exception when others then
    v_ok := false; v_msg := sqlerrm;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'avaliar depois de consultar com sucesso funciona' || coalesce(' (' || v_msg || ')', '') || E'\n';

  -- 7) mesmo IP, telefones diferentes: bloqueia a partir da 16ª tentativa com erro
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.11"}', true);
  v_primeiro := null;
  for i in 1..20 loop
    begin
      perform count(*) from acompanhar_pedido('6997' || lpad(i::text, 7, '0'), 'AAAAAA');
    exception when others then
      if position('muitas_tentativas' in sqlerrm) > 0 and v_primeiro is null then v_primeiro := i; end if;
    end;
  end loop;
  v_res := v_res || case when v_primeiro = 16 then 'OK     ' else 'FALHOU ' end || 'IP bloqueado na 16ª tentativa com erro (bloqueou na: ' || coalesce(v_primeiro::text, 'nunca') || ')' || E'\n';

  -- 7b) IPv6: 20 endereços diferentes do MESMO bloco /64 contam como um só IP => bloqueia na 16ª tentativa com erro
  v_primeiro := null;
  for i in 1..20 loop
    perform set_config('request.headers', json_build_object('cf-connecting-ip', '2001:db8:aaaa:bbbb::' || i)::text, true);
    begin
      perform count(*) from acompanhar_pedido('6996' || lpad(i::text, 7, '0'), 'AAAAAA');
    exception when others then
      if position('muitas_tentativas' in sqlerrm) > 0 and v_primeiro is null then v_primeiro := i; end if;
    end;
  end loop;
  v_res := v_res || case when v_primeiro = 16 then 'OK     ' else 'FALHOU ' end || 'IPv6: trocar o final do endereço dentro do /64 não escapa do limite (bloqueou na: ' || coalesce(v_primeiro::text, 'nunca') || ')' || E'\n';

  -- 7c) IP falso: o visitante manda x-real-ip e x-forwarded-for diferentes a cada tentativa; o IP real (cf-connecting-ip)
  --     é sempre o mesmo, então o limite tem de valer igual (bloqueio na 16ª)
  v_primeiro := null;
  for i in 1..20 loop
    perform set_config('request.headers', json_build_object('cf-connecting-ip', '203.0.113.13',
      'x-real-ip', '198.51.100.' || i, 'x-forwarded-for', '192.0.2.' || i)::text, true);
    begin
      perform count(*) from acompanhar_pedido('6995' || lpad(i::text, 7, '0'), 'AAAAAA');
    exception when others then
      if position('muitas_tentativas' in sqlerrm) > 0 and v_primeiro is null then v_primeiro := i; end if;
    end;
  end loop;
  v_res := v_res || case when v_primeiro = 16 then 'OK     ' else 'FALHOU ' end || 'IP falso em x-real-ip / x-forwarded-for não burla o limite (bloqueou na: ' || coalesce(v_primeiro::text, 'nunca') || ')' || E'\n';

  -- 7d) outro bloco /64 não é afetado pelo bloqueio do 7b
  perform set_config('request.headers', '{"cf-connecting-ip":"2001:db8:aaaa:cccc::1"}', true);
  select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'outro bloco IPv6 /64 continua funcionando' || E'\n';

  -- 8) outro IP não é afetado
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.12"}', true);
  select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'outro IP continua funcionando' || E'\n';

  -- 8b) terceiro que erra de propósito o telefone de outro cliente só bloqueia a si mesmo (bloqueio ligado ao IP):
  --     o atacante (IP .20) erra 5 vezes o telefone do cliente 2 e é bloqueado na 6ª; o cliente, de outro IP, entra normal
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.20"}', true);
  v_primeiro := null;
  for i in 1..6 loop
    begin
      perform count(*) from acompanhar_pedido(tel2, 'AAAAA' || i);
    exception when others then
      if position('muitas_tentativas' in sqlerrm) > 0 and v_primeiro is null then v_primeiro := i; end if;
    end;
  end loop;
  v_res := v_res || case when v_primeiro = 6 then 'OK     ' else 'FALHOU ' end || 'o atacante é bloqueado depois de 5 erros no telefone alheio (bloqueou na: ' || coalesce(v_primeiro::text, 'nunca') || ')' || E'\n';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.21"}', true);
  v_det := '';
  begin
    select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  exception when others then
    n := -1; v_det := ' [erro: ' || sqlerrm || ']';
  end;
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'o cliente, de outro IP, continua consultando o próprio pedido' || v_det || E'\n';

  -- 8c) o bloqueio continua valendo para o IP do atacante, mesmo com o código certo
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.20"}', true);
  begin
    perform count(*) from acompanhar_pedido(tel2, v_cod2);
    v_ok := false;
  exception when others then
    v_ok := position('muitas_tentativas' in sqlerrm) > 0;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'o IP do atacante segue bloqueado para esse telefone' || E'\n';

  -- 8d) sem IP confiável (cabeçalho inválido ou ausente) vale a regra antiga: o telefone inteiro, de qualquer IP
  perform set_config('request.headers', '{"cf-connecting-ip":"lixo"}', true);
  for i in 1..5 loop
    begin
      perform count(*) from acompanhar_pedido(telx, 'BBBBB' || i);
    exception when others then null;
    end;
  end loop;
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.22"}', true);
  v_det := '';
  begin
    select count(*) into n from acompanhar_pedido(telx, 'BBBBB9');
  exception when others then
    n := -1; v_det := ' [erro: ' || sqlerrm || ']';
  end;
  v_res := v_res || case when n = 0 then 'OK     ' else 'FALHOU ' end || 'erros sem IP confiável não bloqueiam quem chega com IP confiável' || v_det || E'\n';
  perform set_config('request.headers', '{}', true);
  begin
    perform count(*) from acompanhar_pedido(telx, 'BBBBB8');
    v_ok := false;
  exception when others then
    v_ok := position('muitas_tentativas' in sqlerrm) > 0;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'sem IP confiável o telefone fica bloqueado depois de 5 erros seguidos' || E'\n';

  -- 8e) teto distribuído: 45 IPs diferentes erram o MESMO telefone 5 vezes cada (nenhum IP chega a ser bloqueado
  --     sozinho); o telefone para em 200 erros no total, e aí vale para qualquer IP novo
  for i in 1..45 loop
    perform set_config('request.headers', json_build_object('cf-connecting-ip', '203.0.114.' || i)::text, true);
    for j in 1..5 loop
      begin
        perform count(*) from acompanhar_pedido(telz, 'CCCCC' || j);
      exception when others then null;
      end;
    end loop;
  end loop;
  execute 'reset role';
  select count(*) into n from tentativas_consulta where tel8 = right(telz, 8) and not ok;
  execute 'set local role anon';
  v_res := v_res || case when n = 200 then 'OK     ' else 'FALHOU ' end || 'teto por telefone: erros aceitos antes de parar (esperado 200, foram: ' || n || ')' || E'\n';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.115.1"}', true);
  begin
    perform count(*) from acompanhar_pedido(telz, 'CCCCC9');
    v_ok := false;
  exception when others then
    v_ok := position('muitas_tentativas' in sqlerrm) > 0;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'depois do teto, um IP novo também é barrado nesse telefone' || E'\n';
  v_det := '';
  begin
    select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  exception when others then
    n := -1; v_det := ' [erro: ' || sqlerrm || ']';
  end;
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'o teto de um telefone não afeta outros telefones' || v_det || E'\n';

  -- 8f) alerta geral (300 erros em 10 min): não derruba todo mundo. 30 IPs erram 2 vezes cada (sem atingir 3);
  --     quem não errou passa; quem já errou 3 vezes é barrado
  for i in 1..30 loop
    perform set_config('request.headers', json_build_object('cf-connecting-ip', '203.0.116.' || i)::text, true);
    for j in 1..2 loop
      begin
        perform count(*) from acompanhar_pedido('6994' || lpad(i::text, 7, '0'), 'DDDDD' || j);
      exception when others then null;
      end;
    end loop;
  end loop;
  execute 'reset role';
  select count(*) into n from tentativas_consulta where not ok and quando > clock_timestamp() - interval '10 minutes';
  execute 'set local role anon';
  v_res := v_res || case when n >= 300 then 'OK     ' else 'FALHOU ' end || 'alerta geral ligado para o teste (erros nos últimos 10 min: ' || n || ', precisa de 300 ou mais)' || E'\n';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.117.1"}', true);
  v_det := '';
  begin
    select count(*) into n from acompanhar_pedido(tel2, v_cod2);
  exception when others then
    n := -1; v_det := ' [erro: ' || sqlerrm || ']';
  end;
  v_res := v_res || case when n = 1 then 'OK     ' else 'FALHOU ' end || 'com o alerta ligado, cliente que não errou continua consultando' || v_det || E'\n';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.116.1"}', true);
  v_ok := true;
  begin
    perform count(*) from acompanhar_pedido('69940000099', 'DDDDD3');   -- 3ª tentativa com erro desse IP: ainda passa
  exception when others then
    v_ok := false;
  end;
  begin
    perform count(*) from acompanhar_pedido('69940000098', 'DDDDD4');   -- já são 3 erros: barrado no alerta
    v_ok := false;
  exception when others then
    v_ok := v_ok and position('muitas_tentativas' in sqlerrm) > 0;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'com o alerta ligado, quem já errou 3 vezes é barrado' || E'\n';

  -- 9) RLS e permissões do público (anon): tudo isto precisa dar "permissão negada"
  foreach q in array array[
    'select count(*) from pedidos', 'select count(*) from clientes', 'select count(*) from avaliacoes',
    'select count(*) from avaliacao_fotos', 'select count(*) from admins', 'select count(*) from config',
    'select count(*) from contatos', 'select count(*) from despesas', 'select count(*) from fotos_pedido',
    'select count(*) from pedidos_historico', 'select count(*) from tentativas_consulta',
    'select count(*) from funcionarios', 'select count(*) from cliente_notas',
    'insert into pedidos (nome, telefone, veiculo) values (''x'', ''y'', ''z'')',
    'update servicos set preco = 0', 'delete from servicos',
    'select consulta_registrar(''11111111'', true, 1)', 'select consulta_verificar(''11111111'')',
    'select consulta_travar(''11111111'')',
    'select * from fichas_clientes()', 'select * from staff_pedidos(current_date)',
    'select * from fidelidade_clientes()', 'select * from comissao_mensal(2026, 11)'
  ] loop
    begin
      execute q;
      v_ok := false;
    exception when insufficient_privilege then
      v_ok := true;
    when others then
      v_ok := false; v_msg := sqlstate;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'anon sem acesso: ' || q || E'\n';
  end loop;
  begin
    select count(*) into n from servicos;
    v_ok := true;
  exception when others then
    v_ok := false;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'anon continua lendo os serviços ativos' || E'\n';

  -- 10) usuário logado que NÃO é administrador nem funcionário
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000aa","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000aa', true);
  execute 'set local role authenticated';
  select count(*) into n from pedidos;
  v_res := v_res || case when n = 0 then 'OK     ' else 'FALHOU ' end || 'logado sem permissão não enxerga nenhum pedido (RLS)' || E'\n';
  foreach q in array array[
    'select * from fichas_clientes()', 'select * from staff_pedidos(current_date)',
    'select * from comissao_mensal(2026, 11)', 'select * from fidelidade_clientes()',
    'select bloquear_telefone(''69999999999'')'
  ] loop
    begin
      execute q;
      v_ok := false;
    exception when others then
      v_ok := position('nao_autorizado' in sqlerrm) > 0 or sqlstate = '42501';
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'logado sem permissão é recusado: ' || q || E'\n';
  end loop;
  foreach q in array array[
    'select count(*) from tentativas_consulta', 'select consulta_registrar(''11111111'', true, 1)',
    'select consulta_travar(''11111111'')'
  ] loop
    begin
      execute q;
      v_ok := false;
    exception when insufficient_privilege then
      v_ok := true;
    when others then
      v_ok := false;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'logado sem acesso: ' || q || E'\n';
  end loop;

  execute 'reset role';

  -- ==========================================================================================================
  -- 11) PREPARO: usuários simulados e dados de teste (tudo desfeito no fim). Roda como dono do banco.
  -- ==========================================================================================================
  execute 'reset role';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.118.1"}', true);
  begin
    insert into auth.users (id, email) values
      (z_adm, 'teste-seg-admin@exemplo.invalid'),
      (z_func, 'teste-seg-func@exemplo.invalid'),
      (z_sem, 'teste-seg-sem@exemplo.invalid')
    on conflict (id) do nothing;
  exception when others then
    z_users := false;
    v_res := v_res || 'AVISO  não foi possível criar usuários de teste em auth.users dentro da transação (' || sqlerrm
          || '): os testes como funcionário e administrador foram pulados; faça-os com usuários reais (ver o roteiro no início do arquivo)' || E'\n';
  end;
  insert into servicos (nome, preco) values ('TESTE SEG A', 1) returning id into z_srv1;
  insert into servicos (nome, preco) values ('TESTE SEG B', 1) returning id into z_srv2;
  insert into servicos (nome, preco, ativo) values ('TESTE SEG INATIVO', 1, false) returning id into z_srv3;
  insert into clientes (nome) values ('TESTE SEG') returning id into z_cli;
  insert into precos_cliente (cliente_id, servico_id, preco) values (z_cli, z_srv1, 1);
  insert into pedidos (nome, telefone, veiculo, status, data_hora) values ('TESTE SEG P1', '69970000091', 'TESTE', 'novo', now()) returning id into z_ped1;
  insert into pedidos (nome, telefone, veiculo, status, data_hora) values ('TESTE SEG P2', '69970000092', 'TESTE', 'pronto', now()) returning id into z_ped2;
  insert into pedidos (nome, telefone, veiculo, status, data_hora) values ('TESTE SEG P3', '69970000093', 'TESTE', 'entregue', now()) returning id into z_ped3;
  insert into contatos (rotulo, telefone, ativo) values ('TESTE SEG', '5569999990000', true), ('TESTE SEG OFF', '5569999990002', false);
  insert into dias_fechados (dia, motivo) values ('2099-01-01', 'TESTE');
  insert into despesas (descricao, valor) values ('TESTE SEG', 1);
  insert into avaliacoes (pedido_id, nota, status) values (z_ped1, 5, 'pendente') returning id into z_av;
  insert into avaliacoes (pedido_id, nota, status) values (z_ped3, 4, 'aprovada') returning id into z_av3;
  insert into avaliacao_fotos (avaliacao_id, imagem) values (z_av, 'data:image/jpeg;base64,AAAA');
  insert into fotos_pedido (pedido_id, tipo, caminho) values (z_ped1, 'antes', 'teste-seg/a.jpg');
  insert into cliente_notas (chave, obs) values ('teste-seg-1', 'x');
  insert into funcionarios (nome) values ('TESTE SEG F2') returning id into z_f2;
  insert into telefones_bloqueados (tel8) values ('99990001');
  insert into bloqueios_horario (dia, inicio, fim, motivo) values ('2099-01-01', '08:00', '09:00', 'TESTE SEG');
  insert into vistoria_avarias (pedido_id, area, descricao) values (z_ped1, 'Frente', 'TESTE SEG avaria');
  insert into tentativas_consulta (tel8, ip, ok) values ('99990000', '203.0.118.250', false);
  if z_users then
    insert into admins (user_id) values (z_adm);
    insert into funcionarios (nome, user_id, email) values ('TESTE SEG F1', z_func, 'teste-seg-func@exemplo.invalid') returning id into z_f1;
  end if;
  v_res := v_res || 'INFO   dados de teste criados (desfeitos no fim). Usuários simulados: ' || case when z_users then 'sim' else 'NÃO' end || E'\n';

  -- ==========================================================================================================
  -- 12) CATÁLOGO: RLS, permissões (inclusive por coluna e TRUNCATE), políticas, inventário (roda como dono do banco)
  -- ==========================================================================================================
  execute 'reset role';
  -- 12a) RLS ligado nas 19 tabelas
  z_falhas := '';
  foreach z_tab in array z_tabs loop
    if not coalesce((select relrowsecurity from pg_class where oid = ('public.' || z_tab)::regclass), false) then
      z_falhas := z_falhas || ' ' || z_tab;
    end if;
  end loop;
  v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'RLS ligado nas 19 tabelas' || case when z_falhas = '' then '' else ' (sem RLS:' || z_falhas || ')' end || E'\n';
  -- 12b) o público (anon) não tem nenhuma permissão, nem por coluna, exceto ler serviços (a política mostra só os ativos)
  z_falhas := '';
  foreach z_tab in array z_tabs loop
    if z_tab = 'servicos' then
      if not has_table_privilege('anon', 'public.servicos', 'SELECT')
         or has_any_column_privilege('anon', 'public.servicos', 'INSERT,UPDATE,REFERENCES')
         or has_table_privilege('anon', 'public.servicos', 'DELETE,TRUNCATE,TRIGGER') then
        z_falhas := z_falhas || ' servicos';
      end if;
    elsif has_any_column_privilege('anon', 'public.' || z_tab, 'SELECT,INSERT,UPDATE,REFERENCES')
       or has_table_privilege('anon', 'public.' || z_tab, 'DELETE,TRUNCATE,TRIGGER') then
      z_falhas := z_falhas || ' ' || z_tab;
    end if;
  end loop;
  v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'anon só tem leitura em servicos e nada (nem por coluna) nas outras 18 tabelas' || case when z_falhas = '' then '' else ' (indevido em:' || z_falhas || ')' end || E'\n';
  select count(*) into n from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and has_sequence_privilege('anon', c.oid, 'USAGE,SELECT,UPDATE');
  v_res := v_res || case when n = 0 then 'OK     ' else 'FALHOU ' end || 'anon sem permissão nas sequências (contadores de id) (indevidas: ' || n || ')' || E'\n';
  -- 12c) tabelas internas e histórico (inclui permissões por coluna)
  v_ok := not (has_any_column_privilege('authenticated', 'public.tentativas_consulta', 'SELECT,INSERT,UPDATE,REFERENCES')
               or has_table_privilege('authenticated', 'public.tentativas_consulta', 'DELETE,TRUNCATE,TRIGGER'));
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'logado sem nenhuma permissão em tentativas_consulta' || E'\n';
  v_ok := not (has_any_column_privilege('authenticated', 'public.pedidos_historico', 'INSERT,UPDATE')
               or has_table_privilege('authenticated', 'public.pedidos_historico', 'DELETE'));
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'logado não grava, altera nem apaga o histórico de pedidos (só gatilho)' || E'\n';
  v_ok := exists (select 1 from pg_trigger where tgrelid = 'public.pedidos'::regclass and tgname = 'pedidos_historico_trg' and not tgisinternal);
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'gatilho do histórico existe em pedidos' || E'\n';
  -- 12d) as 33 funções: quem pode executar, ninguém via PUBLIC, search_path nas "security definer"
  z_falhas := ''; z_nfn := 0;
  foreach z_c in array array[
      'config_publica()|pub',
      'contatos_publicos()|pub',
      'aviso_publico()|pub',
      'horarios_disponiveis(date)|pub',
      'criar_pedido(text, text, text, bigint, timestamptz, text, boolean, text)|pub',
      'acompanhar_pedido(text, text)|pub',
      'enviar_avaliacao(text, text, int, text, text[])|pub',
      'avaliacoes_publicas(int, int)|pub',
      'resumo_avaliacoes()|pub',
      'is_admin()|auth',
      'meu_papel()|auth',
      'staff_pedidos(date)|staff',
      'staff_funcionarios()|staff',
      'staff_definir_status(bigint, text)|staff',
      'staff_definir_funcionario(bigint, bigint)|staff',
      'remarcar_pedido(bigint, timestamptz)|adm',
      'fidelidade_clientes()|adm',
      'fichas_clientes()|adm',
      'ficha_pedidos(text)|adm',
      'vincular_funcionario(bigint, text)|adm',
      'comissao_mensal(int, int)|adm',
      'faturamento_diario(int, int)|adm',
      'devedores_fixos()|adm',
      'bloquear_telefone(text, text)|adm',
      'pico_pedidos(int)|adm',
      'tempo_lavagem(int)|adm',
      'ip_do_cliente()|int',
      'consulta_travar(text)|int',
      'consulta_verificar(text)|int',
      'consulta_registrar(text, boolean, bigint)|int',
      'chave_cliente(bigint, text)|int',
      'historico_usuario()|int',
      'registrar_historico_pedido()|int'
  ] loop
    z_sig := split_part(z_c, '|', 1); z_cls := split_part(z_c, '|', 2);
    z_oid := null;
    begin
      z_oid := ('public.' || z_sig)::regprocedure;
    exception when others then
      z_falhas := z_falhas || ' ' || z_sig || ' (não existe)';
    end;
    if z_oid is not null then
      z_nfn := z_nfn + 1;
      z_oids := z_oids || z_oid::oid;
      if has_function_privilege('anon', z_oid, 'execute') <> (z_cls = 'pub') then
        z_falhas := z_falhas || ' ' || z_sig || ' (anon: ' || case when z_cls = 'pub' then 'deveria executar' else 'não deveria executar' end || ')';
      end if;
      if has_function_privilege('authenticated', z_oid, 'execute') <> (z_cls <> 'int') then
        z_falhas := z_falhas || ' ' || z_sig || ' (logado: ' || case when z_cls <> 'int' then 'deveria executar' else 'não deveria executar' end || ')';
      end if;
      if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where p.oid = z_oid and a.grantee = 0) then
        z_falhas := z_falhas || ' ' || z_sig || ' (liberada para PUBLIC)';
      end if;
      if exists (select 1 from pg_proc p where p.oid = z_oid and p.prosecdef
                  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg where cfg like 'search_path=%')) then
        z_falhas := z_falhas || ' ' || z_sig || ' (security definer sem search_path)';
      end if;
    end if;
  end loop;
  v_res := v_res || case when z_falhas = '' and z_nfn = 33 then 'OK     ' else 'FALHOU ' end || 'permissões das 33 funções (9 públicas, 17 só para logados, 7 internas) conferidas: ' || z_nfn || ' encontradas'
        || case when z_falhas = '' then '' else ' =>' || z_falhas end || E'\n';
  -- 12e) inventário: nada novo no esquema public sem teste (funções, tabelas e visões)
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ') into z_prob
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.oid <> all (z_oids)
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma função nova sem teste em public' || coalesce(' (sem cobertura: ' || z_prob || ')', '') || E'\n';
  select string_agg(c.relname, ', ') into z_prob
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and c.relname <> all (z_tabs)
     and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma tabela nova sem teste em public' || coalesce(' (sem cobertura: ' || z_prob || ')', '') || E'\n';
  select string_agg(c.relname || '(' || c.relkind || ')', ', ') into z_prob
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm', 'f')
     and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma visão em public (visões rodam com as permissões do dono e ignoram o RLS, salvo security_invoker)'
        || coalesce(' (revisar: ' || z_prob || ')', '') || E'\n';
  -- 12f) TRUNCATE, REFERENCES e TRIGGER (e MAINTAIN, que só existe no PostgreSQL 17 ou mais novo): permissão EFETIVA (já inclui
  --      herança entre papéis, o papel pg_maintain e o que vem de PUBLIC) de anon e logado nas 19 tabelas
  z_ver := current_setting('server_version_num')::int;
  z_privs := case when z_ver >= 170000 then array['TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] else array['TRUNCATE', 'REFERENCES', 'TRIGGER'] end;
  v_res := v_res || 'INFO   PostgreSQL ' || current_setting('server_version') || ' (server_version_num ' || z_ver || '): ' ||
           case when z_ver >= 170000 then 'o privilégio MAINTAIN existe e é verificado' else 'MAINTAIN não existe nesta versão (só a partir do 17): não se aplica' end || E'\n';
  z_falhas := '';
  foreach z_c in array array['anon', 'authenticated'] loop
    foreach z_sig in array z_privs loop
      z_a := '';
      foreach z_tab in array z_tabs loop
        if has_table_privilege(z_c, 'public.' || z_tab, z_sig) then z_a := z_a || ' ' || z_tab; end if;
      end loop;
      if z_a <> '' then z_falhas := z_falhas || ' | ' || z_c || ' tem ' || z_sig || ' em:' || z_a; end if;
    end loop;
  end loop;
  v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'anon e logado sem ' || array_to_string(z_privs, ', ') || ' nas 19 tabelas (permissão efetiva, inclusive herdada e via PUBLIC)'
        || case when z_falhas = '' then '' else z_falhas || ' | rode de novo o supabase.sql (seção 12, revogação de TRUNCATE, REFERENCES, TRIGGER e MAINTAIN)' end || E'\n';
  -- PUBLIC (todos os papéis) não pode ter nenhum privilégio de tabela nas 19 tabelas
  select string_agg(c.relname || ' (' || a.privilege_type || ')', ', ') into z_prob
    from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where c.oid = any (select ('public.' || t)::regclass::oid from unnest(z_tabs) t) and a.grantee = 0;
  v_res := v_res || case when z_prob is null then 'OK     ' else 'FALHOU ' end || 'PUBLIC não tem nenhum privilégio nas 19 tabelas'
        || coalesce(' (indevido: ' || z_prob || ')', '') || E'\n';
  -- herança: anon e logado não herdam permissões de outros papéis (a conferência acima já conta o que é herdado; aqui se mostra de onde vem)
  select string_agg(u.rolname || ' herda de ' || r.rolname, '; ') into z_prob
    from pg_auth_members m join pg_roles r on r.oid = m.roleid join pg_roles u on u.oid = m.member
   where u.rolname in ('anon', 'authenticated');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'anon e logado não herdam permissões de outros papéis'
        || coalesce(' (revisar: ' || z_prob || ')', '') || E'\n';
  -- permissões padrão para TABELAS FUTURAS: o papel dono das tabelas do projeto tem de nascer sem os três privilégios
  z_a := (select pg_get_userbyid(relowner)::text from pg_class where oid = 'public.servicos'::regclass);
  select string_agg(distinct pg_get_userbyid(d.defaclrole) || ' concede ' || a.privilege_type || ' a '
                    || case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end, '; ')
    into z_falhas
    from pg_default_acl d, aclexplode(d.defaclacl) a
   where d.defaclobjtype = 'r' and d.defaclnamespace in (0::oid, 'public'::regnamespace::oid)
     and a.privilege_type = any (z_privs)
     and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon', 'authenticated'))
     and pg_get_userbyid(d.defaclrole)::text = z_a;
  v_res := v_res || case when z_falhas is null then 'OK     ' else 'FALHOU ' end || 'tabelas futuras criadas por ' || coalesce(z_a, '?') || ' (dono das tabelas do projeto) nascem sem ' || array_to_string(z_privs, ', ') || ' para anon, logado e PUBLIC'
        || coalesce(' (padrão atual: ' || z_falhas || '; rode de novo o supabase.sql)', '') || E'\n';
  select string_agg(distinct pg_get_userbyid(d.defaclrole) || ' concede ' || a.privilege_type || ' a '
                    || case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end, '; ')
    into z_prob
    from pg_default_acl d, aclexplode(d.defaclacl) a
   where d.defaclobjtype = 'r' and d.defaclnamespace in (0::oid, 'public'::regnamespace::oid)
     and a.privilege_type = any (z_privs)
     and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon', 'authenticated'))
     and pg_get_userbyid(d.defaclrole)::text <> z_a;
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'privilégios padrão de outros papéis (por exemplo supabase_admin, da plataforma, que o projeto não consegue alterar) sem ' || array_to_string(z_privs, ', ') || ''
        || coalesce(' (' || z_prob || '; só valem para tabelas criadas por esses papéis, não pelo SQL Editor ou pelo painel)', '') || E'\n';
  -- pg_maintain (PostgreSQL 17+): quem pertence a esse papel tem MAINTAIN em TODAS as tabelas, inclusive as do sistema
  z_avisos := '';
  if z_ver >= 170000 then
    foreach z_c in array array['anon', 'authenticated'] loop
      if pg_has_role(z_c, 'pg_maintain', 'USAGE') then z_avisos := z_avisos || ' ' || z_c; end if;
    end loop;
    v_res := v_res || case when z_avisos = '' then 'OK     ' else 'FALHOU ' end || 'anon e logado não pertencem ao papel pg_maintain (que daria MAINTAIN em todas as tabelas)'
          || case when z_avisos = '' then '' else ' (pertencem:' || z_avisos || ')' end || E'\n';
  end if;
  -- 12g) tabela NOVA criada em public por este papel: prova, numa tabela de teste, que os padrões valem de fato e o TRUNCATE do logado é negado
  z_a := 'não executado'; z_b := 'não executado'; z_d := 'não executado'; z_e := 'não executado'; z_f := 'não executado';
  begin
    execute 'create table public.zz_teste_seg_nova (id int)';
    execute 'insert into public.zz_teste_seg_nova values (1)';
    z_d := coalesce((select string_agg(x, ', ') from (
             select 'anon:' || p as x from unnest(z_privs) p
              where has_table_privilege('anon', 'public.zz_teste_seg_nova', p)
             union all
             select 'authenticated:' || p from unnest(z_privs) p
              where has_table_privilege('authenticated', 'public.zz_teste_seg_nova', p)
             union all
             select 'PUBLIC:' || a.privilege_type from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
              where c.oid = 'public.zz_teste_seg_nova'::regclass and a.grantee = 0
                and a.privilege_type = any (z_privs)) t), 'nenhum');
    begin
      execute 'set local role anon';
      execute 'select count(*) from public.zz_teste_seg_nova';
      z_a := 'leitura permitida';
    exception
      when insufficient_privilege then z_a := 'negado';
      when others then z_a := 'erro ' || sqlstate;
    end;
    execute 'reset role';
    execute 'alter table public.zz_teste_seg_nova enable row level security';
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_sem::text, true);
      execute 'set local role authenticated';
      execute 'truncate table public.zz_teste_seg_nova';
      z_b := 'TRUNCATE permitido';
    exception
      when insufficient_privilege then z_b := 'negado';
      when others then z_b := 'erro ' || sqlstate;
    end;
    execute 'reset role';
    begin   -- REINDEX só é permitido ao dono da tabela ou a quem tem MAINTAIN (PostgreSQL 17+)
      perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_sem::text, true);
      execute 'set local role authenticated';
      execute 'reindex table public.zz_teste_seg_nova';
      z_e := 'REINDEX permitido';
    exception
      when insufficient_privilege then z_e := 'negado';
      when others then z_e := 'erro ' || sqlstate;
    end;
    execute 'reset role';
    begin   -- LOCK TABLE: qualquer modo é permitido a quem tem UPDATE, DELETE, TRUNCATE ou MAINTAIN (informativo)
      perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_sem::text, true);
      execute 'set local role authenticated';
      execute 'lock table public.zz_teste_seg_nova in access exclusive mode';
      z_f := 'LOCK TABLE permitido';
    exception
      when insufficient_privilege then z_f := 'negado';
      when others then z_f := 'erro ' || sqlstate;
    end;
    execute 'reset role';
    raise exception 'desfaz' using errcode = 'TS001';
  exception
    when sqlstate 'TS001' then null;
    when others then z_a := 'erro ao criar tabela de teste: ' || sqlerrm; z_b := z_a; z_d := z_a; z_e := z_a; z_f := z_a;
  end;
  execute 'reset role';
  v_res := v_res || case when z_d = 'nenhum' then 'OK     ' when z_d like 'anon:%' or z_d like 'authenticated:%' or z_d like 'PUBLIC:%' then 'FALHOU ' else 'AVISO  ' end
        || 'tabela nova em public nasce sem ' || array_to_string(z_privs, ', ') || ' para anon, logado e PUBLIC (resultado: ' || z_d || ')' || E'\n';
  v_res := v_res || case when z_b = 'negado' then 'OK     ' when z_b = 'TRUNCATE permitido' then 'FALHOU ' else 'AVISO  ' end
        || 'logado não consegue TRUNCATE numa tabela nova com RLS (resultado: ' || z_b || ')' || E'\n';
  v_res := v_res || case when z_e = 'negado' then 'OK     ' when z_e = 'REINDEX permitido' then 'FALHOU ' else 'AVISO  ' end
        || 'logado não consegue REINDEX (nem VACUUM, ANALYZE, CLUSTER ou REFRESH, que usam a mesma regra de MAINTAIN) numa tabela que não é dele (resultado: ' || z_e || ')' || E'\n';
  v_res := v_res || 'INFO   LOCK TABLE em modo exclusivo pelo logado: ' || z_f
        || ' (esperado "permitido": UPDATE e DELETE, que o painel precisa, já bastam para qualquer modo de bloqueio; MAINTAIN não é a única porta e esta correção não muda isso)' || E'\n';
  v_res := v_res || case when z_a = 'negado' then 'OK     ' else 'AVISO  ' end || 'tabela nova em public não nasce legível por anon (resultado: ' || z_a
        || case when z_a = 'leitura permitida' then '; fora desta correção: ao criar tabelas novas, ligue o RLS e rode de novo o bloco de permissões do supabase.sql' else '' end || ')' || E'\n';
  -- 12h) políticas de tabela: nada aberto a anon/todos, nenhuma "true", todas ligadas a administrador (ou à regra de serviços ativos)
  select string_agg(tablename || ': ' || policyname, '; ') into z_prob from pg_policies
   where schemaname = 'public' and permissive = 'PERMISSIVE'
     and ((roles && array['anon', 'public']::name[] and not (tablename = 'servicos' and policyname = 'ver servicos ativos'))
          or coalesce(qual, '') in ('true', '(true)') or coalesce(with_check, '') in ('true', '(true)')
          or not ((coalesce(qual, '') || coalesce(with_check, '')) ~* 'is_admin|meu_papel|ativo'));
  v_res := v_res || case when z_prob is null then 'OK     ' else 'FALHOU ' end || 'nenhuma política de tabela aberta demais (anon/todos, "true" ou sem regra de papel)'
        || coalesce(' (revisar: ' || z_prob || ')', '') || E'\n';
  -- 12i) anon e logado não criam objetos no esquema public; Realtime
  v_ok := not (has_schema_privilege('anon', 'public', 'CREATE') or has_schema_privilege('authenticated', 'public', 'CREATE'));
  v_res := v_res || case when v_ok then 'OK     ' else 'AVISO  ' end || 'anon e logado não têm CREATE no esquema public' || E'\n';
  select string_agg(tablename, ', ') into z_prob from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public';
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma tabela do projeto publicada no Realtime'
        || coalesce(' (publicadas: ' || z_prob || '; as mudanças só chegam a quem o RLS permite, confirme se é intencional)', '') || E'\n';

  -- ==========================================================================================================
  -- 12j) SEQUÊNCIAS: o que as 19 tabelas realmente usam (IDENTITY, SERIAL, sequências avulsas) e quem precisa de privilégio.
  --      Regras do PostgreSQL: nextval() exige USAGE ou UPDATE na sequência, currval() exige USAGE ou SELECT e setval() exige
  --      UPDATE. Coluna SERIAL (padrão nextval) obriga quem insere a ter esse privilégio; coluna IDENTITY, segundo o código-fonte
  --      do PostgreSQL, não verifica a permissão da sequência (há artigos que dizem o contrário, por isso a seção 12k prova na prática).
  -- ==========================================================================================================
  execute 'reset role';
  select array_agg(distinct c.relname::text), count(*) filter (where a.attidentity = 'a'), count(*) filter (where a.attidentity = 'd')
    into z_idtabs, z_n1, z_n2
    from pg_attribute a join pg_class c on c.oid = a.attrelid
   where c.relnamespace = 'public'::regnamespace and c.relname = any (z_tabs) and a.attidentity <> '' and not a.attisdropped;
  z_idtabs := coalesce(z_idtabs, '{}'::text[]);
  select count(*) filter (where k = 'identity'), count(*) filter (where k = 'serial'), count(*) filter (where k = 'avulsa'),
         string_agg(nome, ', ') filter (where k = 'avulsa')
    into z_q1, z_q2, z_q3, z_prob
    from (select c.relname::text as nome,
                 case when exists (select 1 from pg_depend d where d.objid = c.oid and d.classid = 'pg_class'::regclass and d.deptype = 'i') then 'identity'
                      when exists (select 1 from pg_depend d where d.objid = c.oid and d.classid = 'pg_class'::regclass and d.deptype = 'a') then 'serial'
                      else 'avulsa' end as k
            from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'S') t;
  v_res := v_res || 'INFO   colunas IDENTITY nas 19 tabelas: ' || z_n1 || ' "always" e ' || z_n2 || ' "by default", em ' || coalesce(array_length(z_idtabs, 1), 0)
        || ' tabelas; sequências em public: identity ' || z_q1 || ', serial ' || z_q2 || ', avulsas ' || z_q3 || E'\n';
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma sequência avulsa em public (sem dono: coluna IDENTITY ou SERIAL)'
        || coalesce(' (avulsas: ' || z_prob || '; confira quem as usa e com que privilégio)', '') || E'\n';
  -- necessidades reais do painel: pares tabela:privilégio DERIVADOS das operações que o painel faz (lista extraída do index.html por um
  -- programa à parte, sem consultar a lista de GRANTs). Regras do PostgreSQL: select -> SELECT; insert -> INSERT; update -> UPDATE + SELECT
  -- (o filtro lê colunas); delete -> DELETE + SELECT; upsert (insert ... on conflict do update) -> INSERT + UPDATE + SELECT.
  with o(tab, op, evid, cmd) as (values
        ('servicos', 'select', 'index.html: select x5; backup/exportação lê a tabela inteira', 'select count(*) from servicos where id = %1$s'),
        ('servicos', 'insert', 'index.html: insert x1 (colunas: descricao, nome, preco)', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)'),
        ('servicos', 'update', 'index.html: update x1 (colunas: ativo, descricao, nome, preco)', 'update servicos set ativo = ativo, descricao = descricao, nome = nome, preco = preco where id = %1$s'),
        ('clientes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from clientes where id = %3$s'),
        ('clientes', 'insert', 'index.html: insert x1 (colunas: nome, telefone)', 'insert into clientes (nome) values (''TESTE SEG INS'')'),
        ('precos_cliente', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'delete', 'index.html: delete x1', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'upsert', 'index.html: upsert x1 (colunas: cliente_id, preco, servico_id)', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %1$s, 2) on conflict (cliente_id, servico_id) do update set preco = excluded.preco'),
        ('pedidos', 'select', 'index.html: select x14; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from pedidos where id = %4$s'),
        ('pedidos', 'insert', 'index.html: insert x2 (colunas: cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo)', 'insert into pedidos (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) values (%3$s, now(), ''Rua Teste'', true, ''TESTE SEG INS'', ''x'', false, 1, %1$s, ''TESTE'', ''novo'', 0, ''69970000094'', ''TESTE'')'),
        ('pedidos', 'update', 'index.html: update x7 (colunas: desconto, funcionario_id, pago, resgate, status, vistoria_em)', 'update pedidos set desconto = desconto, funcionario_id = funcionario_id, pago = pago, resgate = resgate, status = status, vistoria_em = vistoria_em where id = %4$s'),
        ('config', 'select', 'index.html: select x7; backup/exportação lê a tabela inteira', 'select count(*) from config where id = 1'),
        ('config', 'update', 'index.html: update x6 (colunas: abre, aviso_ativo, aviso_fim, aviso_inicio, aviso_texto, dias, duracao_min, endereco, fecha, fidelidade_a_cada, fidelidade_pct, instagram, leva_traz_ativo, max_pedidos_abertos, taxa_leva_traz, vagas)', 'update config set abre = abre, aviso_ativo = aviso_ativo, aviso_fim = aviso_fim, aviso_inicio = aviso_inicio, aviso_texto = aviso_texto, dias = dias, duracao_min = duracao_min, endereco = endereco, fecha = fecha, fidelidade_a_cada = fidelidade_a_cada, fidelidade_pct = fidelidade_pct, instagram = instagram, leva_traz_ativo = leva_traz_ativo, max_pedidos_abertos = max_pedidos_abertos, taxa_leva_traz = taxa_leva_traz, vagas = vagas where id = 1'),
        ('contatos', 'select', 'index.html: select x4; backup/exportação lê a tabela inteira', 'select count(*) from contatos where rotulo = ''TESTE SEG'''),
        ('contatos', 'insert', 'index.html: insert x1 (colunas: ordem, rotulo, telefone, whatsapp)', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')'),
        ('contatos', 'update', 'index.html: update x2 (colunas: ativo, ordem, rotulo, telefone, whatsapp)', 'update contatos set ativo = ativo, ordem = ordem, rotulo = rotulo, telefone = telefone, whatsapp = whatsapp where rotulo = ''TESTE SEG'''),
        ('contatos', 'delete', 'index.html: delete x1', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'delete', 'index.html: delete x1', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'upsert', 'index.html: upsert x1 (colunas: dia, motivo)', 'insert into dias_fechados (dia, motivo) values (''2099-01-01'', ''TESTE'') on conflict (dia) do update set motivo = excluded.motivo'),
        ('despesas', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from despesas where descricao = ''TESTE SEG'''),
        ('despesas', 'insert', 'index.html: insert x1 (colunas: categoria, data, descricao, valor)', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)'),
        ('despesas', 'delete', 'index.html: delete x1', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from avaliacoes where id = %6$s'),
        ('avaliacoes', 'update', 'index.html: update x2 (colunas: status)', 'update avaliacoes set status = status where id = %6$s'),
        ('avaliacoes', 'delete', 'index.html: delete x1', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('fotos_pedido', 'insert', 'index.html: insert x1 (colunas: caminho, pedido_id, tipo)', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')'),
        ('fotos_pedido', 'delete', 'index.html: delete x1', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('cliente_notas', 'select', 'index.html: select x1; backup/exportação lê a tabela inteira', 'select count(*) from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'delete', 'index.html: delete x1', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'upsert', 'index.html: upsert x1 (colunas: atualizado_em, chave, obs)', 'insert into cliente_notas (chave, obs) values (''teste-seg-1'', ''y'') on conflict (chave) do update set obs = excluded.obs, atualizado_em = now()'),
        ('funcionarios', 'select', 'index.html: select x3; backup/exportação lê a tabela inteira', 'select count(*) from funcionarios where id = %8$s'),
        ('funcionarios', 'insert', 'index.html: insert x1 (colunas: comissao_tipo, comissao_valor, nome)', 'insert into funcionarios (comissao_tipo, comissao_valor, nome) values (''fixo'', 1, ''TESTE SEG INS'')'),
        ('funcionarios', 'update', 'index.html: update x1 (colunas: ativo, comissao_tipo, comissao_valor, nome)', 'update funcionarios set ativo = ativo, comissao_tipo = comissao_tipo, comissao_valor = comissao_valor, nome = nome where id = %8$s'),
        ('telefones_bloqueados', 'select', 'index.html: select x1', 'select count(*) from telefones_bloqueados where tel8 = ''99990001'''),
        ('telefones_bloqueados', 'delete', 'index.html: delete x1', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('bloqueios_horario', 'insert', 'index.html: insert x1 (colunas: dia, fim, inicio, motivo)', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')'),
        ('bloqueios_horario', 'delete', 'index.html: delete x1', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('vistoria_avarias', 'insert', 'index.html: insert x1 (colunas: area, caminho, descricao, pedido_id)', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')'),
        ('vistoria_avarias', 'delete', 'index.html: delete x1', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from pedidos_historico where pedido_id = %4$s')
  )
  select (select array_agg(distinct o.tab || ':' || pv)
            from o, lateral unnest(case o.op when 'select' then array['SELECT'] when 'insert' then array['INSERT']
                                     when 'update' then array['UPDATE', 'SELECT'] when 'delete' then array['DELETE', 'SELECT']
                                     when 'upsert' then array['INSERT', 'UPDATE', 'SELECT'] end) as pv),
         -- M5: nas tabelas restritas, INSERT e UPDATE são necessários só nas colunas da evidência "(colunas: ...)" de cada operação
         (select array_agg(distinct o.tab || ':' || pv || ':' || col)
            from o, lateral unnest((case when o.op in ('insert', 'upsert') then array['INSERT'] else array[]::text[] end)
                                   || (case when o.op in ('update', 'upsert') then array['UPDATE'] else array[]::text[] end)) as pv,
                 lateral unnest(string_to_array(substring(o.evid from '\(colunas: ([^)]*)\)'), ', ')) as col
           where o.tab = any (z_colrestr)),
         -- o SQL de teste de cada operação restrita precisa citar todas as colunas da evidência (senão a execução não provaria o privilégio de todas)
         (select string_agg(o.tab || '/' || o.op || ':' || col, ' ' order by o.tab, o.op, col)
            from o, lateral unnest(string_to_array(substring(o.evid from '\(colunas: ([^)]*)\)'), ', ')) as col
           where o.tab = any (z_colrestr) and o.cmd !~ ('\m' || col || '\M'))
    into z_need, z_needc, z_cobre;
  z_need := coalesce(z_need, '{}'::text[]);
  z_needc := coalesce(z_needc, '{}'::text[]);
  -- Comparador (M5): $1 = necessidades tabela:PRIV, $2 = tabelas, $3 = privilégios, $4 = AMBOS|FALTA|SOBRA, $5 = necessidades tabela:PRIV:coluna,
  -- $6 = tabelas restritas por coluna. Nível de tabela em todas as tabelas, MENOS INSERT e UPDATE das restritas: nelas qualquer INSERT ou UPDATE de
  -- tabela inteira é SOBRA ("tab:PRIV") e a comparação vai por coluna ("tab.coluna:PRIV", has_column_privilege, só onde não há privilégio de tabela).
  -- has_table_privilege é falso quando só existe grant por coluna: usá-lo nas restritas daria FALTA falsa.
  z_cmp := $q$select coalesce(string_agg(case when nd then 'FALTA ' else 'SOBRA ' end || item || ':' || pv, ', ' order by item, pv), '')
                 from (select t as item, pv, has_table_privilege('authenticated', 'public.' || t, pv) as hs,
                              (case when t = any ($6) and pv in ('INSERT', 'UPDATE') then false else ((t || ':' || pv) = any ($1)) end) as nd
                         from unnest($2) as t, unnest($3) as pv
                       union all
                       select c.relname::text || '.' || a.attname::text, pv, has_column_privilege('authenticated', c.oid, a.attnum, pv),
                              ((c.relname::text || ':' || pv || ':' || a.attname::text) = any ($5))
                         from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped,
                              unnest($3) as pv
                        where c.relnamespace = 'public'::regnamespace and c.relname::text = any ($6) and pv in ('INSERT', 'UPDATE')
                          and not has_table_privilege('authenticated', c.oid, pv)) x
                where hs <> nd and ($4 = 'AMBOS' or ($4 = 'FALTA' and nd) or ($4 = 'SOBRA' and hs))$q$;
  -- Sondas de ZERO LINHA (M5), geradas do catálogo: "update t set c = c where false" e "insert into t (c) select c from t where false". Sem linhas, nenhuma
  -- política RLS, gatilho ou constraint é avaliada: o único erro possível é a checagem de privilégio (42501), então "negado" aqui nunca é RLS.
  -- Esperado: N = coluna que o painel NÃO usa (tem de dar negado); Z = coluna usada (controle positivo: tem de dar 0 linhas, sem erro, o que também
  -- prova que o negado das outras não vem de falta de SELECT); C = controle negativo conhecido (o M4 deixou pedidos_historico só com SELECT: tem de
  -- dar negado, o que prova que a checagem de privilégio acontece mesmo sem linhas). Colunas "identity always" (id) ficam de fora: dão erro 428C9
  -- antes da checagem de privilégio.
  with cols as (
    select c.relname::text as tab, a.attname::text as col, a.attidentity::text as ident
      from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
     where c.relnamespace = 'public'::regnamespace and c.relname::text = any (z_colrestr)
  ), s as (
    select tab, col, 'UPDATE' as pv,
           case when (tab || ':UPDATE:' || col) = any (z_needc) then 'Z' else 'N' end as esp,
           format('update public.%I set %I = %I where false', tab, col, col) as cmd
      from cols where ident <> 'a'
    union all
    select tab, col, 'INSERT',
           case when (tab || ':INSERT:' || col) = any (z_needc) then 'Z' else 'N' end,
           format('insert into public.%I (%I) select %I from public.%I where false', tab, col, col, tab)
      from cols where ident <> 'a'
    union all
    select 'pedidos_historico', 'campo', 'UPDATE', 'C', 'update public.pedidos_historico set campo = campo where false'
    union all
    select 'pedidos_historico', 'campo', 'INSERT', 'C', 'insert into public.pedidos_historico (campo) select campo from public.pedidos_historico where false'
  )
  select array_agg(cmd order by tab, pv, col), array_agg(esp order by tab, pv, col), array_agg(tab || '.' || col || ':' || pv order by tab, pv, col)
    into z_sondas_sql, z_sondas_exp, z_sondas_rot from s;
  v_res := v_res || case when array_length(z_need, 1) is null then 'FALHOU ' else 'INFO   ' end
        || 'necessidades reais do painel (independentes da lista de GRANTs): ' || coalesce(array_length(z_need, 1), 0) || ' pares tabela:privilégio em '
        || (select count(distinct split_part(x, ':', 1)) from unnest(z_need) x) || ' tabelas'
        || case when array_length(z_need, 1) is null then ' => lista vazia: as comparações da seção 13 não valem' else '' end || E'\n';
  v_res := v_res || case when array_length(z_needc, 1) is null or z_cobre is not null then 'AVISO  ' else 'INFO   ' end
        || 'necessidades por coluna (INSERT e UPDATE, extraídas do index.html) nas tabelas restritas ' || array_to_string(z_colrestr, ', ') || ': '
        || coalesce(array_length(z_needc, 1), 0) || ' trios tabela:privilégio:coluna; ' || coalesce(array_length(z_sondas_sql, 1), 0) || ' sondas de zero linha geradas do catálogo'
        || case when array_length(z_needc, 1) is null then ' => lista vazia: as comparações por coluna não valem' else '' end
        || case when z_cobre is not null then ' => o SQL de teste não cita toda coluna da evidência (' || z_cobre || ')' else '' end || E'\n';
  -- colunas das 19 tabelas com padrão nextval() (SERIAL ou sequência avulsa): o painel só precisa de privilégio onde insere
  z_falhas := ''; z_avisos := ''; z_q4 := 0;
  for z_r in
    select c.relname::text as tab, a.attname::text as col,
           substring(pg_get_expr(d.adbin, d.adrelid) from 'nextval\(''([^'']+)''::regclass\)') as seq
      from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
           join pg_class c on c.oid = d.adrelid
     where c.relnamespace = 'public'::regnamespace and c.relname = any (z_tabs) and pg_get_expr(d.adbin, d.adrelid) ~* 'nextval\('
  loop
    z_q4 := z_q4 + 1;
    if z_r.seq is null then
      z_avisos := z_avisos || ' ' || z_r.tab || '.' || z_r.col || ' (sequência não identificada)';
    elsif (z_r.tab || ':INSERT') = any (z_need) then
      if not (has_sequence_privilege('authenticated', z_r.seq, 'USAGE') or has_sequence_privilege('authenticated', z_r.seq, 'UPDATE')) then
        z_falhas := z_falhas || ' ' || z_r.tab || '.' || z_r.col || ' -> ' || z_r.seq;
      end if;
    end if;
  end loop;
  v_res := v_res || case when z_falhas <> '' then 'FALHOU ' when z_avisos <> '' then 'AVISO  ' else 'OK     ' end
        || case when z_q4 = 0 then 'nenhuma coluna das 19 tabelas usa SERIAL nem nextval() como padrão: nenhuma operação do painel exige USAGE, SELECT ou UPDATE em sequência'
                else z_q4 || ' coluna(s) com padrão nextval(): o authenticated precisa de USAGE ou UPDATE na sequência das tabelas em que o painel insere'
                     || case when z_falhas <> '' then ' (faltando:' || z_falhas || ')' else '' end
                     || case when z_avisos <> '' then ' [' || z_avisos || ']' else '' end end || E'\n';
  -- funções, políticas e constraints que chamam funções de sequência
  select string_agg(p.proname || ' (' || case when p.prosecdef then 'definer' else 'invoker' end || ')', ', ') into z_prob
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and p.prosrc ~* '\m(nextval|currval|setval|lastval)\M|pg_get_serial_sequence';
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma função de public usa nextval, currval, setval nem lastval'
        || coalesce(' (usam: ' || z_prob || '; as "invoker" exigem o privilégio de sequência de quem chama, as "definer" usam o do dono)', '') || E'\n';
  select string_agg(x, ', ') into z_prob from (
    select 'política ' || tablename || ':' || policyname as x from pg_policies
     where schemaname = 'public' and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~* 'nextval|currval|lastval|setval'
    union all
    select 'constraint ' || conrelid::regclass::text || ':' || conname from pg_constraint
     where connamespace = 'public'::regnamespace and contype = 'c' and pg_get_constraintdef(oid) ~* 'nextval|currval|lastval|setval') t;
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma política nem constraint de public usa funções de sequência'
        || coalesce(' (usam: ' || z_prob || ')', '') || E'\n';
  -- privilégios de sequência no banco real: PUBLIC nenhum; authenticated só como excesso do padrão antigo
  select string_agg(c.relname || ' (' || a.privilege_type || ')', ', ') into z_prob
    from pg_class c, aclexplode(coalesce(c.relacl, acldefault('s', c.relowner))) a
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and a.grantee = 0;
  v_res := v_res || case when z_prob is null then 'OK     ' else 'FALHOU ' end || 'PUBLIC não tem nenhum privilégio nas sequências de public'
        || coalesce(' (indevido: ' || z_prob || ')', '') || E'\n';
  select string_agg(c.relname, ', ') into z_prob from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and has_sequence_privilege('authenticated', c.oid, 'USAGE,SELECT,UPDATE');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'authenticated sem privilégio de sequência no banco real (desnecessário enquanto as colunas forem IDENTITY)'
        || coalesce(' (a mais, herdado do padrão antigo do Supabase: ' || z_prob || ')', '') || E'\n';

  -- ==========================================================================================================
  -- 12k) PROVA PRÁTICA (objetos de teste, desfeitos no fim): IDENTITY dispensa privilégio de sequência; SERIAL o exige.
  --      O controle SERIAL mostra que o teste DETECTA a exigência: sem ele, um "permitido" em IDENTITY não provaria nada.
  -- ==========================================================================================================
  execute 'reset role';
  z_s0 := 'não executado'; z_s1 := 'não executado'; z_s2 := 'não executado'; z_s3 := 'não executado';
  z_s4 := 'não executado'; z_s5 := 'não executado'; z_s6 := 'não executado';
  begin
    execute 'create table public.zz_seq_identity (id bigint generated always as identity primary key, k int unique, v int)';
    execute 'create table public.zz_seq_serial (id bigserial primary key, v int)';
    execute 'grant select, insert, update on table public.zz_seq_identity to authenticated';
    execute 'grant select, insert, update on table public.zz_seq_serial to authenticated';
    z_x1 := pg_get_serial_sequence('public.zz_seq_identity', 'id');
    z_x2 := pg_get_serial_sequence('public.zz_seq_serial', 'id');
    execute 'revoke all on sequence ' || z_x1 || ' from authenticated, anon, public';
    execute 'revoke all on sequence ' || z_x2 || ' from authenticated, anon, public';
    z_s0 := case when has_sequence_privilege('authenticated', z_x1, 'USAGE,SELECT,UPDATE') or has_sequence_privilege('authenticated', z_x2, 'USAGE,SELECT,UPDATE')
                      or has_sequence_privilege('anon', z_x1, 'USAGE,SELECT,UPDATE') then 'sobrou privilégio de sequência' else 'zerado' end;
    if z_s0 = 'zerado' then
      -- IDENTITY: várias linhas com RETURNING e o "upsert" do painel (caminho de inserção e de conflito), sem nenhum privilégio de sequência
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_sem::text, true);
        execute 'set local role authenticated';
        execute 'insert into public.zz_seq_identity (k, v) values (1, 1)';
        execute 'insert into public.zz_seq_identity (k, v) values (1, 2) on conflict (k) do update set v = excluded.v';
        execute 'insert into public.zz_seq_identity (k, v) values (2, 1), (3, 1) returning id';
        z_s1 := 'permitido';
      exception
        when insufficient_privilege then z_s1 := 'negado';
        when others then z_s1 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
      -- SERIAL, controle: sem privilégio de sequência
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_sem::text, true);
        execute 'set local role authenticated';
        execute 'insert into public.zz_seq_serial (v) values (1)';
        z_s2 := 'permitido';
      exception
        when insufficient_privilege then z_s2 := 'negado';
        when others then z_s2 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
      -- SERIAL: só SELECT na sequência
      execute 'grant select on sequence ' || z_x2 || ' to authenticated';
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_sem::text, true);
        execute 'set local role authenticated';
        execute 'insert into public.zz_seq_serial (v) values (2)';
        z_s3 := 'permitido';
      exception
        when insufficient_privilege then z_s3 := 'negado';
        when others then z_s3 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
      -- SERIAL: só UPDATE na sequência
      execute 'revoke all on sequence ' || z_x2 || ' from authenticated';
      execute 'grant update on sequence ' || z_x2 || ' to authenticated';
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_sem::text, true);
        execute 'set local role authenticated';
        execute 'insert into public.zz_seq_serial (v) values (3)';
        z_s4 := 'permitido';
      exception
        when insufficient_privilege then z_s4 := 'negado';
        when others then z_s4 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
      -- SERIAL: só USAGE na sequência
      execute 'revoke all on sequence ' || z_x2 || ' from authenticated';
      execute 'grant usage on sequence ' || z_x2 || ' to authenticated';
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', z_sem, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_sem::text, true);
        execute 'set local role authenticated';
        execute 'insert into public.zz_seq_serial (v) values (4)';
        z_s5 := 'permitido';
      exception
        when insufficient_privilege then z_s5 := 'negado';
        when others then z_s5 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
      -- função SECURITY DEFINER (como criar_pedido, acompanhar_pedido e o gatilho do histórico) chamada por anon, sem privilégio de tabela nem de sequência
      execute 'create function public.zz_seq_definer() returns void language plpgsql security definer set search_path = public as $f$ begin insert into public.zz_seq_identity (k, v) values (99, 99); end $f$';
      execute 'revoke all on function public.zz_seq_definer() from public';
      execute 'grant execute on function public.zz_seq_definer() to anon';
      begin
        perform set_config('request.jwt.claims', '', true);
        perform set_config('request.jwt.claim.sub', '', true);
        execute 'set local role anon';
        execute 'select public.zz_seq_definer()';
        z_s6 := 'permitido';
      exception
        when insufficient_privilege then z_s6 := 'negado';
        when others then z_s6 := 'erro ' || sqlstate;
      end;
      execute 'reset role';
    end if;
    raise exception 'desfaz' using errcode = 'TS001';
  exception
    when sqlstate 'TS001' then null;
    when others then z_s0 := 'erro ao preparar: ' || sqlerrm;
  end;
  execute 'reset role';
  v_res := v_res || case when z_s0 = 'zerado' then 'OK     ' else 'AVISO  ' end
        || 'prova prática de sequências: privilégios de sequência dos objetos de teste zerados para authenticated e anon (resultado: ' || z_s0 || ')'
        || case when z_s0 = 'zerado' then '' else '; as provas abaixo ficam inconclusivas' end || E'\n';
  if z_s0 = 'zerado' then
    v_res := v_res || case z_s1 when 'permitido' then 'OK     ' when 'negado' then 'FALHOU ' else 'AVISO  ' end
          || 'IDENTITY: o logado insere (várias linhas com RETURNING e "upsert" com ON CONFLICT DO UPDATE) sem nenhum privilégio de sequência (resultado: ' || z_s1 || ')'
          || case when z_s1 = 'negado' then ' => neste PostgreSQL a coluna IDENTITY EXIGE privilégio de sequência: o supabase.sql precisaria conceder USAGE nas sequências ao authenticated' else '' end || E'\n';
    v_res := v_res || case z_s2 when 'negado' then 'OK     ' else 'AVISO  ' end
          || 'controle SERIAL: sem privilégio de sequência o logado NÃO consegue inserir, ou seja, o teste detecta a exigência (resultado: ' || z_s2 || ')'
          || case when z_s2 <> 'negado' then ' => controle falhou: a prova de IDENTITY acima não é confiável' else '' end || E'\n';
    v_res := v_res || case z_s3 when 'negado' then 'OK     ' else 'AVISO  ' end || 'SERIAL: só SELECT na sequência não basta para inserir (resultado: ' || z_s3 || ')' || E'\n';
    v_res := v_res || 'INFO   SERIAL: só UPDATE na sequência (resultado: ' || z_s4 || '; a documentação diz que nextval() aceita USAGE ou UPDATE)' || E'\n';
    v_res := v_res || case z_s5 when 'permitido' then 'OK     ' else 'AVISO  ' end || 'SERIAL: USAGE na sequência basta para inserir (resultado: ' || z_s5 || ')' || E'\n';
    v_res := v_res || case z_s6 when 'permitido' then 'OK     ' when 'negado' then 'FALHOU ' else 'AVISO  ' end
          || 'função SECURITY DEFINER insere em tabela IDENTITY sem o chamador (anon) ter privilégio de tabela nem de sequência (resultado: ' || z_s6 || ')' || E'\n';
  end if;


  -- ==========================================================================================================
  -- 13) TABELAS: controle positivo e, para cada papel, leitura/inserção/alteração/exclusão (cada comando é desfeito)
  -- ==========================================================================================================
  -- 13-0) controle positivo: sem a linha de teste, "0 linhas" não provaria bloqueio algum
  execute 'reset role';
  z_falhas := '';
  for z_r in select * from (values
        ('servicos', 'servicos', 'select count(*) from servicos where id = %1$s', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)', 'update servicos set nome = nome where id = %1$s', 'delete from servicos where id = %1$s'),
        ('clientes', 'padrao', 'select count(*) from clientes where id = %3$s', 'insert into clientes (nome) values (''TESTE SEG INS'')', 'update clientes set nome = nome where id = %3$s', 'delete from clientes where id = %3$s'),
        ('precos_cliente', 'padrao', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %2$s, 1)', 'update precos_cliente set preco = preco where cliente_id = %3$s and servico_id = %1$s', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('pedidos', 'padrao', 'select count(*) from pedidos where id = %4$s', 'insert into pedidos (nome, telefone, veiculo) values (''TESTE SEG INS'', ''69970000094'', ''TESTE'')', 'update pedidos set status = status where id = %4$s', 'delete from pedidos where id = %4$s'),
        ('config', 'padrao', 'select count(*) from config where id = 1', 'insert into config (id) values (1)', 'update config set vagas = vagas where id = 1', 'delete from config where id = 1'),
        ('contatos', 'padrao', 'select count(*) from contatos where rotulo = ''TESTE SEG''', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')', 'update contatos set rotulo = rotulo where rotulo = ''TESTE SEG''', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'padrao', 'select count(*) from dias_fechados where dia = ''2099-01-01''', 'insert into dias_fechados (dia, motivo) values (''2099-01-02'', ''TESTE'')', 'update dias_fechados set motivo = motivo where dia = ''2099-01-01''', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('despesas', 'padrao', 'select count(*) from despesas where descricao = ''TESTE SEG''', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)', 'update despesas set descricao = descricao where descricao = ''TESTE SEG''', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'padrao', 'select count(*) from avaliacoes where id = %6$s', 'insert into avaliacoes (pedido_id, nota) values (%5$s, 5)', 'update avaliacoes set status = status where id = %6$s', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'padrao', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s', 'insert into avaliacao_fotos (avaliacao_id, imagem) values (%6$s, ''data:image/jpeg;base64,BBBB'')', 'update avaliacao_fotos set imagem = imagem where avaliacao_id = %6$s', 'delete from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'padrao', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg''', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')', 'update fotos_pedido set tipo = tipo where caminho = ''teste-seg/a.jpg''', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('admins', 'admins', 'select count(*) from admins where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'insert into admins (user_id) values (''00000000-0000-0000-0000-0000000000aa'')', 'update admins set user_id = user_id where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'delete from admins where user_id = ''00000000-0000-0000-0000-0000000000a1'''),
        ('tentativas_consulta', 'tentativas', 'select count(*) from tentativas_consulta where tel8 = ''99990000''', 'insert into tentativas_consulta (tel8, ok) values (''99990000'', false)', 'update tentativas_consulta set ok = ok where tel8 = ''99990000''', 'delete from tentativas_consulta where tel8 = ''99990000'''),
        ('cliente_notas', 'padrao', 'select count(*) from cliente_notas where chave = ''teste-seg-1''', 'insert into cliente_notas (chave, obs) values (''teste-seg-2'', ''x'')', 'update cliente_notas set obs = obs where chave = ''teste-seg-1''', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('funcionarios', 'padrao', 'select count(*) from funcionarios where id = %8$s', 'insert into funcionarios (nome) values (''TESTE SEG INS'')', 'update funcionarios set nome = nome where id = %8$s', 'delete from funcionarios where id = %8$s'),
        ('telefones_bloqueados', 'padrao', 'select count(*) from telefones_bloqueados where tel8 = ''99990001''', 'insert into telefones_bloqueados (tel8) values (''99990002'')', 'update telefones_bloqueados set nome = nome where tel8 = ''99990001''', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'padrao', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG''', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')', 'update bloqueios_horario set motivo = motivo where motivo = ''TESTE SEG''', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'padrao', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria''', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')', 'update vistoria_avarias set descricao = descricao where descricao = ''TESTE SEG avaria''', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'historico', 'select count(*) from pedidos_historico where pedido_id = %4$s', 'insert into pedidos_historico (pedido_id, campo) values (%4$s, ''teste'')', 'update pedidos_historico set campo = campo where pedido_id = %4$s', 'delete from pedidos_historico where pedido_id = %4$s')
  ) as e(tab, cls, sel, ins, upd, del) loop
    if z_users or z_r.tab <> 'admins' then
      execute format(z_r.sel, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2) into n;
      if n < 1 then z_falhas := z_falhas || ' ' || z_r.tab; end if;
    end if;
  end loop;
  v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'controle positivo: a linha de teste existe em cada tabela (como dono do banco)'
        || case when z_falhas = '' then '' else ' (sem a linha, os resultados "0" dessas tabelas não provam nada:' || z_falhas || ')' end || E'\n';
  v_res := v_res || 'INFO   legenda das tabelas (leitura, inserção, alteração, exclusão): N=negado 0=sem efeito (RLS) +=permitido ?=erro' || E'\n';
  foreach z_papel in array z_papeis loop
    if z_papel in ('func', 'admin') and not z_users then
      v_res := v_res || 'AVISO  tabelas como ' || z_papel || ' puladas (usuário simulado indisponível)' || E'\n';
      continue;
    end if;
    z_rt := z_rt + 1;
      execute 'reset role';
      if z_papel = 'anon' then
        perform set_config('request.jwt.claims', '', true);
        perform set_config('request.jwt.claim.sub', '', true);
        execute 'set local role anon';
      else
        z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
        perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_uid::text, true);
        execute 'set local role authenticated';
      end if;

    z_linha := ''; z_falhas := '';
    for z_r in select * from (values
        ('servicos', 'servicos', 'select count(*) from servicos where id = %1$s', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)', 'update servicos set nome = nome where id = %1$s', 'delete from servicos where id = %1$s'),
        ('clientes', 'padrao', 'select count(*) from clientes where id = %3$s', 'insert into clientes (nome) values (''TESTE SEG INS'')', 'update clientes set nome = nome where id = %3$s', 'delete from clientes where id = %3$s'),
        ('precos_cliente', 'padrao', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %2$s, 1)', 'update precos_cliente set preco = preco where cliente_id = %3$s and servico_id = %1$s', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('pedidos', 'padrao', 'select count(*) from pedidos where id = %4$s', 'insert into pedidos (nome, telefone, veiculo) values (''TESTE SEG INS'', ''69970000094'', ''TESTE'')', 'update pedidos set status = status where id = %4$s', 'delete from pedidos where id = %4$s'),
        ('config', 'padrao', 'select count(*) from config where id = 1', 'insert into config (id) values (1)', 'update config set vagas = vagas where id = 1', 'delete from config where id = 1'),
        ('contatos', 'padrao', 'select count(*) from contatos where rotulo = ''TESTE SEG''', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')', 'update contatos set rotulo = rotulo where rotulo = ''TESTE SEG''', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'padrao', 'select count(*) from dias_fechados where dia = ''2099-01-01''', 'insert into dias_fechados (dia, motivo) values (''2099-01-02'', ''TESTE'')', 'update dias_fechados set motivo = motivo where dia = ''2099-01-01''', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('despesas', 'padrao', 'select count(*) from despesas where descricao = ''TESTE SEG''', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)', 'update despesas set descricao = descricao where descricao = ''TESTE SEG''', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'padrao', 'select count(*) from avaliacoes where id = %6$s', 'insert into avaliacoes (pedido_id, nota) values (%5$s, 5)', 'update avaliacoes set status = status where id = %6$s', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'padrao', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s', 'insert into avaliacao_fotos (avaliacao_id, imagem) values (%6$s, ''data:image/jpeg;base64,BBBB'')', 'update avaliacao_fotos set imagem = imagem where avaliacao_id = %6$s', 'delete from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'padrao', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg''', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')', 'update fotos_pedido set tipo = tipo where caminho = ''teste-seg/a.jpg''', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('admins', 'admins', 'select count(*) from admins where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'insert into admins (user_id) values (''00000000-0000-0000-0000-0000000000aa'')', 'update admins set user_id = user_id where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'delete from admins where user_id = ''00000000-0000-0000-0000-0000000000a1'''),
        ('tentativas_consulta', 'tentativas', 'select count(*) from tentativas_consulta where tel8 = ''99990000''', 'insert into tentativas_consulta (tel8, ok) values (''99990000'', false)', 'update tentativas_consulta set ok = ok where tel8 = ''99990000''', 'delete from tentativas_consulta where tel8 = ''99990000'''),
        ('cliente_notas', 'padrao', 'select count(*) from cliente_notas where chave = ''teste-seg-1''', 'insert into cliente_notas (chave, obs) values (''teste-seg-2'', ''x'')', 'update cliente_notas set obs = obs where chave = ''teste-seg-1''', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('funcionarios', 'padrao', 'select count(*) from funcionarios where id = %8$s', 'insert into funcionarios (nome) values (''TESTE SEG INS'')', 'update funcionarios set nome = nome where id = %8$s', 'delete from funcionarios where id = %8$s'),
        ('telefones_bloqueados', 'padrao', 'select count(*) from telefones_bloqueados where tel8 = ''99990001''', 'insert into telefones_bloqueados (tel8) values (''99990002'')', 'update telefones_bloqueados set nome = nome where tel8 = ''99990001''', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'padrao', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG''', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')', 'update bloqueios_horario set motivo = motivo where motivo = ''TESTE SEG''', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'padrao', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria''', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')', 'update vistoria_avarias set descricao = descricao where descricao = ''TESTE SEG avaria''', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'historico', 'select count(*) from pedidos_historico where pedido_id = %4$s', 'insert into pedidos_historico (pedido_id, campo) values (%4$s, ''teste'')', 'update pedidos_historico set campo = campo where pedido_id = %4$s', 'delete from pedidos_historico where pedido_id = %4$s')
    ) as e(tab, cls, sel, ins, upd, del) loop
      z_sim := '';
      foreach z_op in array array['leitura', 'insercao', 'alteracao', 'exclusao'] loop
        z_sql := format(case z_op when 'leitura' then z_r.sel when 'insercao' then z_r.ins when 'alteracao' then z_r.upd else z_r.del end,
                        z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
        -- estado esperado depois dos GRANTs necessários e da revogação do excedente (M4). Se a operação é NECESSÁRIA ao painel (lista independente
        -- z_need), o administrador consegue e os demais papéis logados são barrados pelo RLS (negado ou 0 linhas). Se NÃO é necessária, o privilégio
        -- de tabela não existe para nenhum papel logado e a resposta tem de ser "negado" (permissão), nunca "0 linhas" nem "permitido".
        z_exp := case
          when z_papel = 'anon' then case when z_r.tab = 'servicos' and z_op = 'leitura' then 'ALLOW' else 'DENY' end
          when (z_r.tab || ':' || case z_op when 'leitura' then 'SELECT' when 'insercao' then 'INSERT' when 'alteracao' then 'UPDATE' else 'DELETE' end) = any (z_need)
            then case when z_papel = 'admin' then 'ALLOW' else 'BLOCK' end
          else 'DENY' end;
        z_got := '';
        z_ck_tab := z_ck_tab + 1;
        begin
          if z_op = 'leitura' then
            execute z_sql into n;
          else
            execute z_sql;
            get diagnostics n = row_count;
          end if;
          z_got := case when n = 0 then 'zero' else 'ok' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when insufficient_privilege then z_got := 'negado';
          when others then z_got := 'erro:' || sqlstate;
        end;
        z_sim := z_sim || case z_got when 'negado' then 'N' when 'zero' then '0' when 'ok' then '+' else '?' end;
        v_ok := case z_exp
          when 'DENY' then z_got = 'negado'
          when 'BLOCK' then z_got = 'negado' or (z_op <> 'insercao' and z_got = 'zero')
          else z_got = 'ok'
        end;
        if not v_ok then
          z_falhas := z_falhas || ' ' || z_r.tab || '/' || z_op || ' (esperado ' || z_exp || ', obteve ' || z_got || ')';
        end if;
      end loop;
      z_linha := z_linha || ' ' || z_r.tab || ':' || z_sim;
    end loop;
    v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || '19 tabelas × 4 operações como ' || z_papel || case when z_falhas = '' then '' else ' => ' || z_falhas end || E'\n'
          || 'INFO   ' || z_papel || ':' || z_linha || E'\n';
    -- M5: sondas de zero linha nas colunas das tabelas restritas, como o papel authenticated (com o JWT deste papel); anon não tem privilégio algum
    if z_papel <> 'anon' then
      z_sonda_fal := ''; z_sonda_inc := ''; z_sonda_ctl := ''; z_sonda_n := 0;
      if current_user <> 'authenticated' then z_sonda_ctl := ' papel efetivo ' || current_user || ' (esperado authenticated)'; end if;
      for z_si in 1 .. coalesce(array_length(z_sondas_sql, 1), 0) loop
        z_sonda_n := z_sonda_n + 1;
        z_sonda_got := '';
        begin
          execute z_sondas_sql[z_si];
          get diagnostics n = row_count;
          z_sonda_got := case when n = 0 then 'zero' else 'ok' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when insufficient_privilege then z_sonda_got := 'negado';
          when others then z_sonda_got := 'erro:' || sqlstate;
        end;
        if z_sondas_exp[z_si] = 'N' then        -- coluna que o painel não usa: tem de ser barrada por privilégio
          if z_sonda_got = 'negado' then null;
          elsif z_sonda_got in ('zero', 'ok') then z_sonda_fal := z_sonda_fal || ' ' || z_sondas_rot[z_si];
          else z_sonda_inc := z_sonda_inc || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')';
          end if;
        elsif z_sondas_exp[z_si] = 'Z' then     -- controle positivo: coluna usada pelo painel, sem linhas, não pode dar erro
          if z_sonda_got <> 'zero' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
        else                                    -- controle negativo conhecido (o M4 revogou): tem de dar negado
          if z_sonda_got <> 'negado' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
        end if;
      end loop;
      v_res := v_res || case when z_sonda_ctl <> '' or z_sonda_n = 0 then 'AVISO  ' when z_sonda_fal <> '' then 'FALHOU ' when z_sonda_inc <> '' then 'AVISO  ' else 'OK     ' end
            || '' || z_sonda_n || ' sondas de coluna (zero linha, sem RLS) como ' || z_papel || ' em pedidos, avaliacoes e funcionarios: toda coluna que o painel não usa é barrada por privilégio; as usadas e os controles passam'
            || case when z_sonda_ctl <> '' then ' => CONTROLES FALHARAM (as sondas não valem):' || z_sonda_ctl else '' end
            || case when z_sonda_fal <> '' then ' => PRIVILÉGIO INDEVIDO:' || z_sonda_fal else '' end
            || case when z_sonda_inc <> '' then ' [inconclusivas:' || z_sonda_inc || ']' else '' end || E'\n';
    end if;
  end loop;
  execute 'reset role';

  -- 13b) o público vê só serviços ativos; o administrador vê também o inativo
  z_papel := 'anon';
  execute 'reset role';
  if z_papel = 'anon' then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
    perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', z_uid::text, true);
    execute 'set local role authenticated';
  end if;

  begin
    v_ok := exists (select 1 from servicos where id = z_srv1) and not exists (select 1 from servicos where id = z_srv3);
  exception when others then
    v_ok := false;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'anon enxerga o serviço ativo e não enxerga o inativo' || E'\n';
  if z_users then
    z_papel := 'admin';
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

    begin
      v_ok := exists (select 1 from servicos where id = z_srv3);
    exception when others then
      v_ok := false;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'administrador enxerga também o serviço inativo' || E'\n';
  end if;
  execute 'reset role';

  -- ==========================================================================================================
  -- 13c) PROJETO NOVO SIMULADO: prova que o painel funciona SEM os grants automáticos antigos do Supabase. Dentro de um
  --      sub-bloco (desfeito no fim) zera os privilégios de tabela e de sequência do papel authenticated, aplica o bloco
  --      de concessões do supabase.sql (cópia gerada da mesma lista, sem diferença além dos espaços) e repete as matrizes.
  -- ==========================================================================================================
  execute 'reset role';
  z_simok := false;
  begin
    execute 'revoke all on all tables in schema public from authenticated';
    execute 'revoke all on all sequences in schema public from authenticated';
    z_idn := 0; z_idfail := '';
    -- pré-checagem: privilégios EFETIVOS que sobram para o authenticated depois de zerar os concedidos diretamente por este papel.
    -- Inclui PUBLIC, papéis herdados, papéis especiais do PostgreSQL (pg_read_all_data, pg_write_all_data, pg_maintain), permissão por
    -- coluna, superusuário e, no PostgreSQL 17+, MAINTAIN; em tabelas (as 19) e em todas as sequências de public. Cada resíduo traz a origem.
    z_pall := array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] || z_privs;
    z_auth := (select r.oid from pg_roles r where r.rolname = 'authenticated');
    z_ra := coalesce((select pg_has_role('authenticated', r.oid, 'USAGE') from pg_roles r where r.rolname = 'pg_read_all_data'), false);
    z_wa := coalesce((select pg_has_role('authenticated', r.oid, 'USAGE') from pg_roles r where r.rolname = 'pg_write_all_data'), false);
    z_ma := coalesce((select pg_has_role('authenticated', r.oid, 'USAGE') from pg_roles r where r.rolname = 'pg_maintain'), false) and z_ver >= 170000;
    z_su := coalesce((select r.rolsuper from pg_roles r where r.rolname = 'authenticated'), false);
    z_falhas := (
      with alvo as (
        select c.oid as oid, c.relname::text as obj, p as priv
          from pg_class c cross join unnest(z_pall) as p
         where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and c.relname = any (z_tabs)
           and case when p in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES') then has_any_column_privilege('authenticated', c.oid, p)
                    else has_table_privilege('authenticated', c.oid, p) end
      ), origem as (
        select c.oid as oid, a.privilege_type::text as priv,
               case when a.grantee = 0 then 'PUBLIC'
                    when a.grantee = c.relowner then 'dono da relação (' || pg_get_userbyid(a.grantee) || ')'
                    when a.grantee = z_auth then 'concessão direta (concedente ' || pg_get_userbyid(a.grantor) || ')'
                    else 'papel herdado ' || pg_get_userbyid(a.grantee) end as orig
          from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
         where c.relnamespace = 'public'::regnamespace
           and case when a.grantee = 0 or a.grantee = z_auth then true else pg_has_role('authenticated', a.grantee, 'USAGE') end
        union all
        select c.oid, a.privilege_type::text,
               case when a.grantee = 0 then 'PUBLIC (por coluna ' || t.attname || ')'
                    when a.grantee = z_auth then 'concessão direta (por coluna ' || t.attname || ', concedente ' || pg_get_userbyid(a.grantor) || ')'
                    else 'papel herdado ' || pg_get_userbyid(a.grantee) || ' (por coluna ' || t.attname || ')' end
          from pg_class c join pg_attribute t on t.attrelid = c.oid and t.attacl is not null and not t.attisdropped,
               aclexplode(t.attacl) a
         where c.relnamespace = 'public'::regnamespace
           and case when a.grantee = 0 or a.grantee = z_auth then true else pg_has_role('authenticated', a.grantee, 'USAGE') end
        union all
        select c.oid, p, 'papel especial pg_read_all_data' from pg_class c, unnest(array['SELECT']) p where c.relnamespace = 'public'::regnamespace and z_ra
        union all
        select c.oid, p, 'papel especial pg_write_all_data' from pg_class c, unnest(array['INSERT', 'UPDATE', 'DELETE']) p where c.relnamespace = 'public'::regnamespace and z_wa
        union all
        select c.oid, 'MAINTAIN', 'papel especial pg_maintain' from pg_class c where c.relnamespace = 'public'::regnamespace and z_ma
        union all
        select c.oid, p, 'authenticated é superusuário' from pg_class c, unnest(z_pall) p where c.relnamespace = 'public'::regnamespace and z_su
      ), linhas as (
        select distinct x.obj, x.priv, coalesce(og.orig, 'origem não identificada') as orig
          from alvo x left join origem og on og.oid = x.oid and og.priv = x.priv
      )
      select string_agg(orig || ' => ' || itens, ' | ' order by orig)
        from (select orig, string_agg(obj || ':' || priv, ', ' order by obj, priv) as itens from linhas group by orig) gr
    );

    z_seqs := (
      with alvo as (
        select c.oid as oid, c.relname::text as obj, p as priv
          from pg_class c cross join unnest(array['USAGE', 'SELECT', 'UPDATE']) as p
         where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and has_sequence_privilege('authenticated', c.oid, p)
      ), origem as (
        select c.oid as oid, a.privilege_type::text as priv,
               case when a.grantee = 0 then 'PUBLIC'
                    when a.grantee = c.relowner then 'dono da sequência (' || pg_get_userbyid(a.grantee) || ')'
                    when a.grantee = z_auth then 'concessão direta (concedente ' || pg_get_userbyid(a.grantor) || ')'
                    else 'papel herdado ' || pg_get_userbyid(a.grantee) end as orig
          from pg_class c, aclexplode(coalesce(c.relacl, acldefault('s', c.relowner))) a
         where c.relnamespace = 'public'::regnamespace and c.relkind = 'S'
           and case when a.grantee = 0 or a.grantee = z_auth then true else pg_has_role('authenticated', a.grantee, 'USAGE') end
        union all
        select c.oid, p, 'papel especial pg_read_all_data' from pg_class c, unnest(array['USAGE', 'SELECT']) p
         where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and z_ra
        union all
        select c.oid, p, 'papel especial pg_write_all_data' from pg_class c, unnest(array['USAGE', 'SELECT', 'UPDATE']) p
         where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and z_wa
        union all
        select c.oid, p, 'authenticated é superusuário' from pg_class c, unnest(array['USAGE', 'SELECT', 'UPDATE']) p
         where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and z_su
      ), linhas as (
        select distinct x.obj, x.priv, coalesce(og.orig, 'origem não identificada') as orig
          from alvo x left join origem og on og.oid = x.oid and og.priv = x.priv
      )
      select string_agg(orig || ' => ' || itens, ' | ' order by orig)
        from (select orig, string_agg(obj || ':' || priv, ', ' order by obj, priv) as itens from linhas group by orig) gr
    );

    z_avisos := (
      with alvo as (
        select c.oid as oid, c.relname::text as obj, p as priv
          from pg_class c cross join unnest(z_pall) as p
         where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'f') and c.relname <> all (z_tabs)
           and case when p in ('SELECT', 'INSERT', 'UPDATE', 'REFERENCES') then has_any_column_privilege('authenticated', c.oid, p)
                    else has_table_privilege('authenticated', c.oid, p) end
      ), origem as (
        select c.oid as oid, a.privilege_type::text as priv,
               case when a.grantee = 0 then 'PUBLIC'
                    when a.grantee = c.relowner then 'dono da relação (' || pg_get_userbyid(a.grantee) || ')'
                    when a.grantee = z_auth then 'concessão direta (concedente ' || pg_get_userbyid(a.grantor) || ')'
                    else 'papel herdado ' || pg_get_userbyid(a.grantee) end as orig
          from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
         where c.relnamespace = 'public'::regnamespace
           and case when a.grantee = 0 or a.grantee = z_auth then true else pg_has_role('authenticated', a.grantee, 'USAGE') end
        union all
        select c.oid, a.privilege_type::text,
               case when a.grantee = 0 then 'PUBLIC (por coluna ' || t.attname || ')'
                    when a.grantee = z_auth then 'concessão direta (por coluna ' || t.attname || ', concedente ' || pg_get_userbyid(a.grantor) || ')'
                    else 'papel herdado ' || pg_get_userbyid(a.grantee) || ' (por coluna ' || t.attname || ')' end
          from pg_class c join pg_attribute t on t.attrelid = c.oid and t.attacl is not null and not t.attisdropped,
               aclexplode(t.attacl) a
         where c.relnamespace = 'public'::regnamespace
           and case when a.grantee = 0 or a.grantee = z_auth then true else pg_has_role('authenticated', a.grantee, 'USAGE') end
        union all
        select c.oid, p, 'papel especial pg_read_all_data' from pg_class c, unnest(array['SELECT']) p where c.relnamespace = 'public'::regnamespace and z_ra
        union all
        select c.oid, p, 'papel especial pg_write_all_data' from pg_class c, unnest(array['INSERT', 'UPDATE', 'DELETE']) p where c.relnamespace = 'public'::regnamespace and z_wa
        union all
        select c.oid, 'MAINTAIN', 'papel especial pg_maintain' from pg_class c where c.relnamespace = 'public'::regnamespace and z_ma
        union all
        select c.oid, p, 'authenticated é superusuário' from pg_class c, unnest(z_pall) p where c.relnamespace = 'public'::regnamespace and z_su
      ), linhas as (
        select distinct x.obj, x.priv, coalesce(og.orig, 'origem não identificada') as orig
          from alvo x left join origem og on og.oid = x.oid and og.priv = x.priv
      )
      select string_agg(orig || ' => ' || itens, ' | ' order by orig)
        from (select orig, string_agg(obj || ':' || priv, ', ' order by obj, priv) as itens from linhas group by orig) gr
    );

    z_seqok := z_seqs is null;
    if z_avisos is not null then
      v_res := v_res || 'AVISO  outras relações de public (fora das 19 tabelas) também mantêm privilégio efetivo do authenticated (não impede a simulação): ' || z_avisos || E'\n';
    end if;
    if z_falhas is not null or z_seqs is not null then
      v_res := v_res || 'AVISO  simulação de projeto novo NÃO CONCLUÍDA: depois de zerar as concessões diretas o authenticated ainda tem privilégios efetivos (a origem vem antes de =>)'
            || case when z_falhas is not null then ' | tabelas: ' || z_falhas else '' end
            || case when z_seqs is not null then ' | sequências: ' || z_seqs else '' end
            || ' | as matrizes NÃO foram executadas; elimine a origem indicada ou rode o supabase.sql e este roteiro num projeto Supabase novo' || E'\n';
    else
      z_simok := true;
      v_res := v_res || 'OK     projeto novo simulado: pré-checagem sem nenhum privilégio efetivo residual do authenticated (' || array_to_string(z_pall, ', ')
            || ' nas 19 tabelas; USAGE, SELECT e UPDATE em todas as sequências de public), inclusive via PUBLIC, papéis herdados, papéis especiais, permissão por coluna e superusuário' || E'\n';
      select string_agg(c.relname || ':' || a.privilege_type || ':' || a.grantee, ',' order by c.relname, a.privilege_type, a.grantee) into z_x1
        from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and (a.grantee = 0 or a.grantee = 'anon'::regrole::oid);
      execute 'grant select, insert, update on table public.servicos to authenticated';
      execute 'grant select, insert on table public.clientes to authenticated';
      execute 'grant select, insert, update, delete on table public.precos_cliente to authenticated';
      execute 'grant select on table public.pedidos to authenticated';
      execute 'grant select, update on table public.config to authenticated';
      execute 'grant select, insert, update, delete on table public.contatos to authenticated';
      execute 'grant select, insert, update, delete on table public.dias_fechados to authenticated';
      execute 'grant select, insert, delete on table public.despesas to authenticated';
      execute 'grant select, delete on table public.avaliacoes to authenticated';
      execute 'grant select on table public.avaliacao_fotos to authenticated';
      execute 'grant select, insert, delete on table public.fotos_pedido to authenticated';
      execute 'grant select, insert, update, delete on table public.cliente_notas to authenticated';
      execute 'grant select on table public.funcionarios to authenticated';
      execute 'grant select, delete on table public.telefones_bloqueados to authenticated';
      execute 'grant select, insert, delete on table public.bloqueios_horario to authenticated';
      execute 'grant select, insert, delete on table public.vistoria_avarias to authenticated';
      execute 'grant select on table public.pedidos_historico to authenticated';
      -- M5: mesma sequência do bloco "Permissões por coluna (M5)" do supabase.sql (num projeto novo as revogações não têm o que remover)
      execute 'revoke insert, update on table public.pedidos from authenticated';
      execute 'revoke insert, update on table public.avaliacoes from authenticated';
      execute 'revoke insert, update on table public.funcionarios from authenticated';
      execute 'grant insert (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) on table public.pedidos to authenticated';
      execute 'grant update (desconto, funcionario_id, pago, resgate, status, vistoria_em) on table public.pedidos to authenticated';
      execute 'grant update (status) on table public.avaliacoes to authenticated';
      execute 'grant insert (comissao_tipo, comissao_valor, nome) on table public.funcionarios to authenticated';
      execute 'grant update (ativo, comissao_tipo, comissao_valor, nome) on table public.funcionarios to authenticated';
      select string_agg(c.relname || ':' || a.privilege_type || ':' || a.grantee, ',' order by c.relname, a.privilege_type, a.grantee) into z_x2
        from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
       where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and (a.grantee = 0 or a.grantee = 'anon'::regrole::oid);
      v_res := v_res || case when z_x1 is not distinct from z_x2 then 'OK     ' else 'FALHOU ' end || 'projeto novo simulado: o bloco de concessões não muda nenhuma permissão de anon nem de PUBLIC' || E'\n';
      -- necessidades reais x privilégios efetivos, SEM usar a lista de GRANTs: FALTA = operação real do painel sem o privilégio necessário;
      -- SOBRA = privilégio concedido sem nenhuma operação real que o use (inclui TRUNCATE, REFERENCES, TRIGGER e, no PostgreSQL 17+, MAINTAIN)
      execute z_cmp into z_a using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
      v_res := v_res || case when z_a = '' then 'OK     ' else 'FALHOU ' end
            || 'projeto novo simulado: privilégios concedidos = necessidades reais do painel (lista extraída do index.html), nenhum a menos e nenhum a mais'
            || case when z_a = '' then '' else ' => ' || z_a || ' (FALTA: operação real sem o privilégio; SOBRA: privilégio concedido sem uso)' end || E'\n';
      -- matrizes das 19 tabelas: administrador faz o que o painel usa (e só isso), funcionário e logado sem papel continuam barrados pelo RLS
      foreach z_papel in array z_papeis loop
        if z_papel in ('func', 'admin') and not z_users then
          v_res := v_res || 'AVISO  projeto novo simulado: tabelas como ' || z_papel || ' puladas (usuário simulado indisponível)' || E'\n';
          continue;
        end if;
        z_rsim := z_rsim + 1;
        execute 'reset role';
        if z_papel = 'anon' then
          perform set_config('request.jwt.claims', '', true);
          perform set_config('request.jwt.claim.sub', '', true);
          execute 'set local role anon';
        else
          z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
          perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_uid::text, true);
          execute 'set local role authenticated';
        end if;

        z_linha := ''; z_falhas := '';
        for z_r in select * from (values
        ('servicos', 'servicos', 'select count(*) from servicos where id = %1$s', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)', 'update servicos set nome = nome where id = %1$s', 'delete from servicos where id = %1$s'),
        ('clientes', 'padrao', 'select count(*) from clientes where id = %3$s', 'insert into clientes (nome) values (''TESTE SEG INS'')', 'update clientes set nome = nome where id = %3$s', 'delete from clientes where id = %3$s'),
        ('precos_cliente', 'padrao', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %2$s, 1)', 'update precos_cliente set preco = preco where cliente_id = %3$s and servico_id = %1$s', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('pedidos', 'padrao', 'select count(*) from pedidos where id = %4$s', 'insert into pedidos (nome, telefone, veiculo) values (''TESTE SEG INS'', ''69970000094'', ''TESTE'')', 'update pedidos set status = status where id = %4$s', 'delete from pedidos where id = %4$s'),
        ('config', 'padrao', 'select count(*) from config where id = 1', 'insert into config (id) values (1)', 'update config set vagas = vagas where id = 1', 'delete from config where id = 1'),
        ('contatos', 'padrao', 'select count(*) from contatos where rotulo = ''TESTE SEG''', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')', 'update contatos set rotulo = rotulo where rotulo = ''TESTE SEG''', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'padrao', 'select count(*) from dias_fechados where dia = ''2099-01-01''', 'insert into dias_fechados (dia, motivo) values (''2099-01-02'', ''TESTE'')', 'update dias_fechados set motivo = motivo where dia = ''2099-01-01''', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('despesas', 'padrao', 'select count(*) from despesas where descricao = ''TESTE SEG''', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)', 'update despesas set descricao = descricao where descricao = ''TESTE SEG''', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'padrao', 'select count(*) from avaliacoes where id = %6$s', 'insert into avaliacoes (pedido_id, nota) values (%5$s, 5)', 'update avaliacoes set status = status where id = %6$s', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'padrao', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s', 'insert into avaliacao_fotos (avaliacao_id, imagem) values (%6$s, ''data:image/jpeg;base64,BBBB'')', 'update avaliacao_fotos set imagem = imagem where avaliacao_id = %6$s', 'delete from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'padrao', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg''', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')', 'update fotos_pedido set tipo = tipo where caminho = ''teste-seg/a.jpg''', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('admins', 'admins', 'select count(*) from admins where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'insert into admins (user_id) values (''00000000-0000-0000-0000-0000000000aa'')', 'update admins set user_id = user_id where user_id = ''00000000-0000-0000-0000-0000000000a1''', 'delete from admins where user_id = ''00000000-0000-0000-0000-0000000000a1'''),
        ('tentativas_consulta', 'tentativas', 'select count(*) from tentativas_consulta where tel8 = ''99990000''', 'insert into tentativas_consulta (tel8, ok) values (''99990000'', false)', 'update tentativas_consulta set ok = ok where tel8 = ''99990000''', 'delete from tentativas_consulta where tel8 = ''99990000'''),
        ('cliente_notas', 'padrao', 'select count(*) from cliente_notas where chave = ''teste-seg-1''', 'insert into cliente_notas (chave, obs) values (''teste-seg-2'', ''x'')', 'update cliente_notas set obs = obs where chave = ''teste-seg-1''', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('funcionarios', 'padrao', 'select count(*) from funcionarios where id = %8$s', 'insert into funcionarios (nome) values (''TESTE SEG INS'')', 'update funcionarios set nome = nome where id = %8$s', 'delete from funcionarios where id = %8$s'),
        ('telefones_bloqueados', 'padrao', 'select count(*) from telefones_bloqueados where tel8 = ''99990001''', 'insert into telefones_bloqueados (tel8) values (''99990002'')', 'update telefones_bloqueados set nome = nome where tel8 = ''99990001''', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'padrao', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG''', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')', 'update bloqueios_horario set motivo = motivo where motivo = ''TESTE SEG''', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'padrao', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria''', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')', 'update vistoria_avarias set descricao = descricao where descricao = ''TESTE SEG avaria''', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'historico', 'select count(*) from pedidos_historico where pedido_id = %4$s', 'insert into pedidos_historico (pedido_id, campo) values (%4$s, ''teste'')', 'update pedidos_historico set campo = campo where pedido_id = %4$s', 'delete from pedidos_historico where pedido_id = %4$s')
        ) as e(tab, cls, sel, ins, upd, del) loop
          z_sim := '';
          foreach z_op in array array['leitura', 'insercao', 'alteracao', 'exclusao'] loop
            z_sql := format(case z_op when 'leitura' then z_r.sel when 'insercao' then z_r.ins when 'alteracao' then z_r.upd else z_r.del end,
                            z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
            z_exp := case
              when z_papel = 'anon' then case when z_r.tab = 'servicos' and z_op = 'leitura' then 'ALLOW' else 'DENY' end
              when z_papel = 'admin' then
                case when (z_r.tab || ':' || case z_op when 'leitura' then 'SELECT' when 'insercao' then 'INSERT' when 'alteracao' then 'UPDATE' else 'DELETE' end)
                          = any (z_need) then 'ALLOW' else 'DENY' end
              else case when (z_r.tab || ':' || case z_op when 'leitura' then 'SELECT' when 'insercao' then 'INSERT' when 'alteracao' then 'UPDATE' else 'DELETE' end) = any (z_need)
                        then 'BLOCK' else 'DENY' end end;
            z_got := '';
            z_ck_sim := z_ck_sim + 1;
            begin
              if z_op = 'leitura' then
                execute z_sql into n;
              else
                execute z_sql;
                get diagnostics n = row_count;
              end if;
              z_got := case when n = 0 then 'zero' else 'ok' end;
              raise exception 'desfaz' using errcode = 'TS001';
            exception
              when sqlstate 'TS001' then null;
              when insufficient_privilege then z_got := 'negado';
              when others then z_got := 'erro:' || sqlstate;
            end;
            z_sim := z_sim || case z_got when 'negado' then 'N' when 'zero' then '0' when 'ok' then '+' else '?' end;
            if z_papel = 'admin' and z_op = 'insercao' and z_r.tab = any (z_idtabs) and (z_r.tab || ':INSERT') = any (z_need) then
              z_idn := z_idn + 1;
              if z_got <> 'ok' then z_idfail := z_idfail || ' ' || z_r.tab || ' (' || z_got || ')'; end if;
            end if;
            v_ok := case z_exp
              when 'DENY' then z_got = 'negado'
              when 'BLOCK' then z_got = 'negado' or (z_op <> 'insercao' and z_got = 'zero')
              else z_got = 'ok'
            end;
            if not v_ok then
              z_falhas := z_falhas || ' ' || z_r.tab || '/' || z_op || ' (esperado ' || z_exp || ', obteve ' || z_got || ')';
            end if;
          end loop;
          z_linha := z_linha || ' ' || z_r.tab || ':' || z_sim;
        end loop;
        v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'projeto novo simulado: 19 tabelas × 4 operações como ' || z_papel
              || case when z_falhas = '' then '' else ' => ' || z_falhas end || E'\n'
              || 'INFO   projeto novo, ' || z_papel || ':' || z_linha || E'\n';
        -- M5: sondas de zero linha nas colunas das tabelas restritas, só com o que o bloco concedeu
        if z_papel <> 'anon' then
          z_sonda_fal := ''; z_sonda_inc := ''; z_sonda_ctl := ''; z_sonda_n := 0;
          if current_user <> 'authenticated' then z_sonda_ctl := ' papel efetivo ' || current_user || ' (esperado authenticated)'; end if;
          for z_si in 1 .. coalesce(array_length(z_sondas_sql, 1), 0) loop
            z_sonda_n := z_sonda_n + 1;
            z_sonda_got := '';
            begin
              execute z_sondas_sql[z_si];
              get diagnostics n = row_count;
              z_sonda_got := case when n = 0 then 'zero' else 'ok' end;
              raise exception 'desfaz' using errcode = 'TS001';
            exception
              when sqlstate 'TS001' then null;
              when insufficient_privilege then z_sonda_got := 'negado';
              when others then z_sonda_got := 'erro:' || sqlstate;
            end;
            if z_sondas_exp[z_si] = 'N' then        -- coluna que o painel não usa: tem de ser barrada por privilégio
              if z_sonda_got = 'negado' then null;
              elsif z_sonda_got in ('zero', 'ok') then z_sonda_fal := z_sonda_fal || ' ' || z_sondas_rot[z_si];
              else z_sonda_inc := z_sonda_inc || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')';
              end if;
            elsif z_sondas_exp[z_si] = 'Z' then     -- controle positivo: coluna usada pelo painel, sem linhas, não pode dar erro
              if z_sonda_got <> 'zero' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
            else                                    -- controle negativo conhecido (o M4 revogou): tem de dar negado
              if z_sonda_got <> 'negado' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
            end if;
          end loop;
          v_res := v_res || case when z_sonda_ctl <> '' or z_sonda_n = 0 then 'AVISO  ' when z_sonda_fal <> '' then 'FALHOU ' when z_sonda_inc <> '' then 'AVISO  ' else 'OK     ' end
                || 'projeto novo simulado: ' || z_sonda_n || ' sondas de coluna (zero linha, sem RLS) como ' || z_papel || ' em pedidos, avaliacoes e funcionarios: toda coluna que o painel não usa é barrada por privilégio; as usadas e os controles passam'
                || case when z_sonda_ctl <> '' then ' => CONTROLES FALHARAM (as sondas não valem):' || z_sonda_ctl else '' end
                || case when z_sonda_fal <> '' then ' => PRIVILÉGIO INDEVIDO:' || z_sonda_fal else '' end
                || case when z_sonda_inc <> '' then ' [inconclusivas:' || z_sonda_inc || ']' else '' end || E'\n';
        end if;
      end loop;
      execute 'reset role';
      v_res := v_res || case when z_idn = 0 or not z_seqok then 'AVISO  ' when z_idfail = '' then 'OK     ' else 'FALHOU ' end
            || 'projeto novo simulado: inserções do painel em tabelas com coluna IDENTITY, sem nenhum privilégio de sequência (' || z_idn || ' tabelas)'
            || case when z_idn = 0 then ' => nenhuma executada (usuário administrador simulado indisponível)'
                    when not z_seqok then ' => inconclusivo: sobraram privilégios de sequência'
                    when z_idfail <> '' then ' => falharam:' || z_idfail else '' end || E'\n';
      -- as OPERAÇÕES REAIS do painel (lista extraída do index.html, inclusive os "upsert"), executadas como administrador só com o que o bloco concedeu
      if z_users then
        z_papel := 'admin';
        execute 'reset role';
        if z_papel = 'anon' then
          perform set_config('request.jwt.claims', '', true);
          perform set_config('request.jwt.claim.sub', '', true);
          execute 'set local role anon';
        else
          z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
          perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_uid::text, true);
          execute 'set local role authenticated';
        end if;

        z_falhas := ''; z_avisos := ''; z_q4 := 0;
        for z_r in select * from (values
        ('servicos', 'select', 'index.html: select x5; backup/exportação lê a tabela inteira', 'select count(*) from servicos where id = %1$s'),
        ('servicos', 'insert', 'index.html: insert x1 (colunas: descricao, nome, preco)', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)'),
        ('servicos', 'update', 'index.html: update x1 (colunas: ativo, descricao, nome, preco)', 'update servicos set ativo = ativo, descricao = descricao, nome = nome, preco = preco where id = %1$s'),
        ('clientes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from clientes where id = %3$s'),
        ('clientes', 'insert', 'index.html: insert x1 (colunas: nome, telefone)', 'insert into clientes (nome) values (''TESTE SEG INS'')'),
        ('precos_cliente', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'delete', 'index.html: delete x1', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'upsert', 'index.html: upsert x1 (colunas: cliente_id, preco, servico_id)', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %1$s, 2) on conflict (cliente_id, servico_id) do update set preco = excluded.preco'),
        ('pedidos', 'select', 'index.html: select x14; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from pedidos where id = %4$s'),
        ('pedidos', 'insert', 'index.html: insert x2 (colunas: cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo)', 'insert into pedidos (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) values (%3$s, now(), ''Rua Teste'', true, ''TESTE SEG INS'', ''x'', false, 1, %1$s, ''TESTE'', ''novo'', 0, ''69970000094'', ''TESTE'')'),
        ('pedidos', 'update', 'index.html: update x7 (colunas: desconto, funcionario_id, pago, resgate, status, vistoria_em)', 'update pedidos set desconto = desconto, funcionario_id = funcionario_id, pago = pago, resgate = resgate, status = status, vistoria_em = vistoria_em where id = %4$s'),
        ('config', 'select', 'index.html: select x7; backup/exportação lê a tabela inteira', 'select count(*) from config where id = 1'),
        ('config', 'update', 'index.html: update x6 (colunas: abre, aviso_ativo, aviso_fim, aviso_inicio, aviso_texto, dias, duracao_min, endereco, fecha, fidelidade_a_cada, fidelidade_pct, instagram, leva_traz_ativo, max_pedidos_abertos, taxa_leva_traz, vagas)', 'update config set abre = abre, aviso_ativo = aviso_ativo, aviso_fim = aviso_fim, aviso_inicio = aviso_inicio, aviso_texto = aviso_texto, dias = dias, duracao_min = duracao_min, endereco = endereco, fecha = fecha, fidelidade_a_cada = fidelidade_a_cada, fidelidade_pct = fidelidade_pct, instagram = instagram, leva_traz_ativo = leva_traz_ativo, max_pedidos_abertos = max_pedidos_abertos, taxa_leva_traz = taxa_leva_traz, vagas = vagas where id = 1'),
        ('contatos', 'select', 'index.html: select x4; backup/exportação lê a tabela inteira', 'select count(*) from contatos where rotulo = ''TESTE SEG'''),
        ('contatos', 'insert', 'index.html: insert x1 (colunas: ordem, rotulo, telefone, whatsapp)', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')'),
        ('contatos', 'update', 'index.html: update x2 (colunas: ativo, ordem, rotulo, telefone, whatsapp)', 'update contatos set ativo = ativo, ordem = ordem, rotulo = rotulo, telefone = telefone, whatsapp = whatsapp where rotulo = ''TESTE SEG'''),
        ('contatos', 'delete', 'index.html: delete x1', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'delete', 'index.html: delete x1', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'upsert', 'index.html: upsert x1 (colunas: dia, motivo)', 'insert into dias_fechados (dia, motivo) values (''2099-01-01'', ''TESTE'') on conflict (dia) do update set motivo = excluded.motivo'),
        ('despesas', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from despesas where descricao = ''TESTE SEG'''),
        ('despesas', 'insert', 'index.html: insert x1 (colunas: categoria, data, descricao, valor)', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)'),
        ('despesas', 'delete', 'index.html: delete x1', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from avaliacoes where id = %6$s'),
        ('avaliacoes', 'update', 'index.html: update x2 (colunas: status)', 'update avaliacoes set status = status where id = %6$s'),
        ('avaliacoes', 'delete', 'index.html: delete x1', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('fotos_pedido', 'insert', 'index.html: insert x1 (colunas: caminho, pedido_id, tipo)', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')'),
        ('fotos_pedido', 'delete', 'index.html: delete x1', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('cliente_notas', 'select', 'index.html: select x1; backup/exportação lê a tabela inteira', 'select count(*) from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'delete', 'index.html: delete x1', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'upsert', 'index.html: upsert x1 (colunas: atualizado_em, chave, obs)', 'insert into cliente_notas (chave, obs) values (''teste-seg-1'', ''y'') on conflict (chave) do update set obs = excluded.obs, atualizado_em = now()'),
        ('funcionarios', 'select', 'index.html: select x3; backup/exportação lê a tabela inteira', 'select count(*) from funcionarios where id = %8$s'),
        ('funcionarios', 'insert', 'index.html: insert x1 (colunas: comissao_tipo, comissao_valor, nome)', 'insert into funcionarios (comissao_tipo, comissao_valor, nome) values (''fixo'', 1, ''TESTE SEG INS'')'),
        ('funcionarios', 'update', 'index.html: update x1 (colunas: ativo, comissao_tipo, comissao_valor, nome)', 'update funcionarios set ativo = ativo, comissao_tipo = comissao_tipo, comissao_valor = comissao_valor, nome = nome where id = %8$s'),
        ('telefones_bloqueados', 'select', 'index.html: select x1', 'select count(*) from telefones_bloqueados where tel8 = ''99990001'''),
        ('telefones_bloqueados', 'delete', 'index.html: delete x1', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('bloqueios_horario', 'insert', 'index.html: insert x1 (colunas: dia, fim, inicio, motivo)', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')'),
        ('bloqueios_horario', 'delete', 'index.html: delete x1', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('vistoria_avarias', 'insert', 'index.html: insert x1 (colunas: area, caminho, descricao, pedido_id)', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')'),
        ('vistoria_avarias', 'delete', 'index.html: delete x1', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from pedidos_historico where pedido_id = %4$s')
        ) as o(tab, op, evid, cmd) loop
          z_q4 := z_q4 + 1;
          z_sql := format(z_r.cmd, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
          z_got := '';
          begin
            execute z_sql;
            get diagnostics n = row_count;
            z_got := case when n >= 1 then 'ok' else 'sem linha' end;
            raise exception 'desfaz' using errcode = 'TS001';
          exception
            when sqlstate 'TS001' then null;
            when insufficient_privilege then z_got := 'negado';
            when others then z_got := 'erro:' || sqlstate;
          end;
          if z_got = 'negado' then
            z_falhas := z_falhas || ' ' || z_r.tab || '/' || z_r.op || ' (faltando: '
                        || coalesce((select string_agg(pv, ',') from unnest(case z_r.op when 'select' then array['SELECT'] when 'insert' then array['INSERT']
                                                                                          when 'update' then array['UPDATE', 'SELECT'] when 'delete' then array['DELETE', 'SELECT']
                                                                                          else array['INSERT', 'UPDATE', 'SELECT'] end) as pv
                                      where not has_table_privilege('authenticated', 'public.' || z_r.tab, pv)
                                        and not (z_r.tab = any (z_colrestr) and pv in ('INSERT', 'UPDATE'))), '')
                        || coalesce((select string_agg(split_part(x, ':', 2) || '(' || split_part(x, ':', 3) || ')', ',')
                                       from unnest(z_needc) x
                                      where split_part(x, ':', 1) = z_r.tab
                                        and split_part(x, ':', 2) = any (case z_r.op when 'insert' then array['INSERT'] when 'update' then array['UPDATE']
                                                                                     when 'upsert' then array['INSERT', 'UPDATE'] else array[]::text[] end)
                                        and not has_column_privilege('authenticated', 'public.' || z_r.tab, split_part(x, ':', 3), split_part(x, ':', 2))), '')
                        || ')';
          elsif z_got <> 'ok' then
            z_avisos := z_avisos || ' ' || z_r.tab || '/' || z_r.op || ' (' || z_got || ')';
          end if;
        end loop;
        v_res := v_res || case when z_falhas <> '' then 'FALHOU ' when z_avisos <> '' or z_q4 = 0 then 'AVISO  ' else 'OK     ' end
              || 'projeto novo simulado: ' || z_q4 || ' operações reais do painel (extraídas do index.html) executadas como administrador só com o que o bloco concedeu'
              || case when z_falhas <> '' then ' => SEM O PRIVILÉGIO NECESSÁRIO:' || z_falhas else '' end
              || case when z_avisos <> '' then ' [inconclusivas:' || z_avisos || ']' else '' end || E'\n';
        execute 'reset role';
        -- TESTES DE SENSIBILIDADE (anti-circular): provoca de propósito uma FALTA (tira um UPDATE necessário) e uma SOBRA (dá um privilégio sem uso)
        -- e exige que a comparação e a execução real as detectem; se não detectarem, os resultados acima não valem
        z_s1 := 'não executado'; z_s2 := 'não executado'; z_m1t := null; z_m2t := null; z_m2p := null;
        select o.tab, o.cmd into z_m1t, z_m1c from (values
        ('servicos', 'select', 'index.html: select x5; backup/exportação lê a tabela inteira', 'select count(*) from servicos where id = %1$s'),
        ('servicos', 'insert', 'index.html: insert x1 (colunas: descricao, nome, preco)', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)'),
        ('servicos', 'update', 'index.html: update x1 (colunas: ativo, descricao, nome, preco)', 'update servicos set ativo = ativo, descricao = descricao, nome = nome, preco = preco where id = %1$s'),
        ('clientes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from clientes where id = %3$s'),
        ('clientes', 'insert', 'index.html: insert x1 (colunas: nome, telefone)', 'insert into clientes (nome) values (''TESTE SEG INS'')'),
        ('precos_cliente', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'delete', 'index.html: delete x1', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'upsert', 'index.html: upsert x1 (colunas: cliente_id, preco, servico_id)', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %1$s, 2) on conflict (cliente_id, servico_id) do update set preco = excluded.preco'),
        ('pedidos', 'select', 'index.html: select x14; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from pedidos where id = %4$s'),
        ('pedidos', 'insert', 'index.html: insert x2 (colunas: cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo)', 'insert into pedidos (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) values (%3$s, now(), ''Rua Teste'', true, ''TESTE SEG INS'', ''x'', false, 1, %1$s, ''TESTE'', ''novo'', 0, ''69970000094'', ''TESTE'')'),
        ('pedidos', 'update', 'index.html: update x7 (colunas: desconto, funcionario_id, pago, resgate, status, vistoria_em)', 'update pedidos set desconto = desconto, funcionario_id = funcionario_id, pago = pago, resgate = resgate, status = status, vistoria_em = vistoria_em where id = %4$s'),
        ('config', 'select', 'index.html: select x7; backup/exportação lê a tabela inteira', 'select count(*) from config where id = 1'),
        ('config', 'update', 'index.html: update x6 (colunas: abre, aviso_ativo, aviso_fim, aviso_inicio, aviso_texto, dias, duracao_min, endereco, fecha, fidelidade_a_cada, fidelidade_pct, instagram, leva_traz_ativo, max_pedidos_abertos, taxa_leva_traz, vagas)', 'update config set abre = abre, aviso_ativo = aviso_ativo, aviso_fim = aviso_fim, aviso_inicio = aviso_inicio, aviso_texto = aviso_texto, dias = dias, duracao_min = duracao_min, endereco = endereco, fecha = fecha, fidelidade_a_cada = fidelidade_a_cada, fidelidade_pct = fidelidade_pct, instagram = instagram, leva_traz_ativo = leva_traz_ativo, max_pedidos_abertos = max_pedidos_abertos, taxa_leva_traz = taxa_leva_traz, vagas = vagas where id = 1'),
        ('contatos', 'select', 'index.html: select x4; backup/exportação lê a tabela inteira', 'select count(*) from contatos where rotulo = ''TESTE SEG'''),
        ('contatos', 'insert', 'index.html: insert x1 (colunas: ordem, rotulo, telefone, whatsapp)', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')'),
        ('contatos', 'update', 'index.html: update x2 (colunas: ativo, ordem, rotulo, telefone, whatsapp)', 'update contatos set ativo = ativo, ordem = ordem, rotulo = rotulo, telefone = telefone, whatsapp = whatsapp where rotulo = ''TESTE SEG'''),
        ('contatos', 'delete', 'index.html: delete x1', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'delete', 'index.html: delete x1', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'upsert', 'index.html: upsert x1 (colunas: dia, motivo)', 'insert into dias_fechados (dia, motivo) values (''2099-01-01'', ''TESTE'') on conflict (dia) do update set motivo = excluded.motivo'),
        ('despesas', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from despesas where descricao = ''TESTE SEG'''),
        ('despesas', 'insert', 'index.html: insert x1 (colunas: categoria, data, descricao, valor)', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)'),
        ('despesas', 'delete', 'index.html: delete x1', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from avaliacoes where id = %6$s'),
        ('avaliacoes', 'update', 'index.html: update x2 (colunas: status)', 'update avaliacoes set status = status where id = %6$s'),
        ('avaliacoes', 'delete', 'index.html: delete x1', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('fotos_pedido', 'insert', 'index.html: insert x1 (colunas: caminho, pedido_id, tipo)', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')'),
        ('fotos_pedido', 'delete', 'index.html: delete x1', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('cliente_notas', 'select', 'index.html: select x1; backup/exportação lê a tabela inteira', 'select count(*) from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'delete', 'index.html: delete x1', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'upsert', 'index.html: upsert x1 (colunas: atualizado_em, chave, obs)', 'insert into cliente_notas (chave, obs) values (''teste-seg-1'', ''y'') on conflict (chave) do update set obs = excluded.obs, atualizado_em = now()'),
        ('funcionarios', 'select', 'index.html: select x3; backup/exportação lê a tabela inteira', 'select count(*) from funcionarios where id = %8$s'),
        ('funcionarios', 'insert', 'index.html: insert x1 (colunas: comissao_tipo, comissao_valor, nome)', 'insert into funcionarios (comissao_tipo, comissao_valor, nome) values (''fixo'', 1, ''TESTE SEG INS'')'),
        ('funcionarios', 'update', 'index.html: update x1 (colunas: ativo, comissao_tipo, comissao_valor, nome)', 'update funcionarios set ativo = ativo, comissao_tipo = comissao_tipo, comissao_valor = comissao_valor, nome = nome where id = %8$s'),
        ('telefones_bloqueados', 'select', 'index.html: select x1', 'select count(*) from telefones_bloqueados where tel8 = ''99990001'''),
        ('telefones_bloqueados', 'delete', 'index.html: delete x1', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('bloqueios_horario', 'insert', 'index.html: insert x1 (colunas: dia, fim, inicio, motivo)', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')'),
        ('bloqueios_horario', 'delete', 'index.html: delete x1', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('vistoria_avarias', 'insert', 'index.html: insert x1 (colunas: area, caminho, descricao, pedido_id)', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')'),
        ('vistoria_avarias', 'delete', 'index.html: delete x1', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from pedidos_historico where pedido_id = %4$s')
        ) as o(tab, op, evid, cmd) where o.op = 'update' order by o.tab limit 1;
        select t, pv into z_m2t, z_m2p from unnest(z_tabs) as t, unnest(array['DELETE', 'INSERT', 'UPDATE', 'SELECT']) as pv
         where (t || ':' || pv) <> all (z_need) and t <> all (z_colrestr) and not has_table_privilege('authenticated', 'public.' || t, pv) order by t, pv limit 1;
        if z_m1t is not null and z_m2t is not null then
          begin
            execute format('revoke update on table public.%I from authenticated', z_m1t);
            execute format('grant %s on table public.%I to authenticated', z_m2p, z_m2t);
            execute z_cmp into z_b using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
            -- numa tabela restrita, revogar o UPDATE da tabela remove também os grants por coluna: uma FALTA por coluna necessária
            z_s1 := case when z_b like ('%FALTA ' || z_m1t || '%:UPDATE%') and z_b like ('%SOBRA ' || z_m2t || ':' || z_m2p || '%')
                              and array_length(string_to_array(z_b, ', '), 1)
                                  = 1 + case when z_m1t = any (z_colrestr) then (select count(*) from unnest(z_needc) x where split_part(x, ':', 1) = z_m1t and split_part(x, ':', 2) = 'UPDATE') else 1 end
                         then 'detectou' else 'NÃO detectou (a comparação devolveu: ' || z_b || ')' end;
        execute 'reset role';
        if z_papel = 'anon' then
          perform set_config('request.jwt.claims', '', true);
          perform set_config('request.jwt.claim.sub', '', true);
          execute 'set local role anon';
        else
          z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
          perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_uid::text, true);
          execute 'set local role authenticated';
        end if;

            begin
              execute format(z_m1c, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
              z_s2 := 'permitido';
            exception
              when insufficient_privilege then z_s2 := 'negado';
              when others then z_s2 := 'erro ' || sqlstate;
            end;
            execute 'reset role';
            raise exception 'desfaz' using errcode = 'TS001';
          exception
            when sqlstate 'TS001' then null;
            when others then z_s1 := 'erro ao preparar: ' || sqlerrm;
          end;
        else
          z_s1 := 'sem candidato para a provocação';
        end if;
        execute 'reset role';
        v_res := v_res || case when z_s1 = 'detectou' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade: com a FALTA provocada (UPDATE em ' || coalesce(z_m1t, '?') || ') e a SOBRA provocada (' || coalesce(z_m2p, '?') || ' em ' || coalesce(z_m2t, '?')
              || '), a comparação apontou exatamente as duas e nada mais (' || z_s1 || ')' || case when z_s1 <> 'detectou' then ' => o teste seria cego a diferenças entre oferta e necessidade' else '' end || E'\n';
        v_res := v_res || case when z_s2 = 'negado' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade: sem o UPDATE necessário, a operação real de UPDATE em ' || coalesce(z_m1t, '?') || ' passa a dar "negado" (resultado: ' || z_s2 || ')'
              || case when z_s2 <> 'negado' then ' => a execução das operações reais não detectaria um privilégio faltando' else '' end || E'\n';
        -- TESTES DE SENSIBILIDADE POR COLUNA (anti-circular): cada provocação é desfeita; sem elas, um comparador ou uma sonda cegos dariam OK
        z_c1 := 'não executado'; z_c2 := 'não executado'; z_c3 := 'não executado'; z_c4 := 'não executado'; z_c5 := 'não executado';
        begin   -- (a) SOBRA por coluna: UPDATE (preco) a mais em pedidos
          execute 'grant update (preco) on table public.pedidos to authenticated';
          execute z_cmp into z_b using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
          z_c1 := case when z_b = 'SOBRA pedidos.preco:UPDATE' then 'detectou' else 'NÃO detectou (a comparação devolveu: ' || coalesce(nullif(z_b, ''), 'nada') || ')' end;
          execute 'reset role';
          perform set_config('request.jwt.claims', json_build_object('sub', z_adm, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_adm::text, true);
          execute 'set local role authenticated';
          begin
            execute 'update public.pedidos set preco = preco where false';
            z_c2 := 'zero';
          exception
            when insufficient_privilege then z_c2 := 'negado';
            when others then z_c2 := 'erro ' || sqlstate;
          end;
          execute 'reset role';
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when others then z_c1 := 'erro ao preparar: ' || sqlerrm;
        end;
        execute 'reset role';
        begin   -- (b) FALTA por coluna: sem UPDATE (status) em avaliacoes
          execute 'revoke update (status) on table public.avaliacoes from authenticated';
          execute z_cmp into z_b using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
          z_c3 := case when z_b = 'FALTA avaliacoes.status:UPDATE' then 'detectou' else 'NÃO detectou (a comparação devolveu: ' || coalesce(nullif(z_b, ''), 'nada') || ')' end;
          execute 'reset role';
          perform set_config('request.jwt.claims', json_build_object('sub', z_adm, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_adm::text, true);
          execute 'set local role authenticated';
          begin
            execute 'update public.avaliacoes set status = status where false';
            z_c4 := 'zero';
          exception
            when insufficient_privilege then z_c4 := 'negado';
            when others then z_c4 := 'erro ' || sqlstate;
          end;
          execute 'reset role';
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when others then z_c3 := 'erro ao preparar: ' || sqlerrm;
        end;
        execute 'reset role';
        begin   -- (c) UPDATE de tabela inteira em pedidos (o que o M5 revoga) tem de aparecer como SOBRA de tabela, sem ruído por coluna
          execute 'grant update on table public.pedidos to authenticated';
          execute z_cmp into z_b using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
          z_c5 := case when z_b = 'SOBRA pedidos:UPDATE' then 'detectou' else 'NÃO detectou (a comparação devolveu: ' || coalesce(nullif(z_b, ''), 'nada') || ')' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when others then z_c5 := 'erro ao preparar: ' || sqlerrm;
        end;
        execute 'reset role';
        v_res := v_res || case when z_c1 = 'detectou' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade por coluna: com um UPDATE (preco) a mais em pedidos, a comparação apontou exatamente SOBRA pedidos.preco:UPDATE (' || z_c1 || ')' || E'\n';
        v_res := v_res || case when z_c2 = 'zero' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade por coluna: com esse UPDATE (preco) a mais, a sonda de zero linha deixa de ser barrada (resultado: ' || z_c2 || ')'
              || case when z_c2 <> 'zero' then ' => as sondas seriam cegas a um privilégio por coluna indevido' else '' end || E'\n';
        v_res := v_res || case when z_c3 = 'detectou' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade por coluna: sem o UPDATE (status) de avaliacoes, a comparação apontou exatamente FALTA avaliacoes.status:UPDATE (' || z_c3 || ')' || E'\n';
        v_res := v_res || case when z_c4 = 'negado' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade por coluna: sem esse UPDATE (status), o controle positivo da sonda passa a dar negado (resultado: ' || z_c4 || ')'
              || case when z_c4 <> 'negado' then ' => os controles não detectariam um privilégio por coluna faltando' else '' end || E'\n';
        v_res := v_res || case when z_c5 = 'detectou' then 'OK     ' else 'FALHOU ' end
              || 'teste de sensibilidade por coluna: com UPDATE de tabela inteira em pedidos, a comparação apontou exatamente SOBRA pedidos:UPDATE (' || z_c5 || ')' || E'\n';
      else
        v_res := v_res || 'AVISO  projeto novo simulado: operações reais do painel e testes de sensibilidade pulados (usuário administrador simulado indisponível)' || E'\n';
      end if;
      -- as 33 funções continuam iguais (rodam com as permissões do dono, não dependem de privilégio de tabela do authenticated)
      foreach z_papel in array z_papeis loop
        if z_papel in ('func', 'admin') and not z_users then continue; end if;
        execute 'reset role';
        if z_papel = 'anon' then
          perform set_config('request.jwt.claims', '', true);
          perform set_config('request.jwt.claim.sub', '', true);
          execute 'set local role anon';
        else
          z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
          perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_uid::text, true);
          execute 'set local role authenticated';
        end if;

        z_falhas := '';
        for z_r in select * from (values
        ('config_publica', 'select * from config_publica()', 'pub', ''),
        ('contatos_publicos', 'select * from contatos_publicos()', 'pub', ''),
        ('aviso_publico', 'select * from aviso_publico()', 'pub', ''),
        ('horarios_disponiveis', 'select * from horarios_disponiveis(''2099-01-01''::date)', 'pub', ''),
        ('criar_pedido', 'select * from criar_pedido(''x'', ''1'', ''y'', 0, now())', 'pub', 'dados_invalidos'),
        ('acompanhar_pedido', 'select * from acompanhar_pedido(''69999999999'', ''ZZZZZZ'')', 'pub', ''),
        ('enviar_avaliacao', 'select * from enviar_avaliacao(''69999999999'', ''ZZZZZZ'', 5, ''x'')', 'pub', 'pedido_nao_encontrado'),
        ('avaliacoes_publicas', 'select * from avaliacoes_publicas(6, 0)', 'pub', ''),
        ('resumo_avaliacoes', 'select * from resumo_avaliacoes()', 'pub', ''),
        ('is_admin', 'select * from is_admin()', 'auth', ''),
        ('meu_papel', 'select * from meu_papel()', 'auth', ''),
        ('staff_pedidos', 'select * from staff_pedidos(null::date)', 'staff', ''),
        ('staff_funcionarios', 'select * from staff_funcionarios()', 'staff', ''),
        ('staff_definir_status', 'select * from staff_definir_status(%4$s, ''lavando'')', 'staff', ''),
        ('staff_definir_funcionario', 'select * from staff_definir_funcionario(%4$s, %8$s)', 'staff', ''),
        ('remarcar_pedido', 'select * from remarcar_pedido(%4$s, ''2099-01-01 13:00:00+00''::timestamptz)', 'adm', 'horario_indisponivel'),
        ('fidelidade_clientes', 'select * from fidelidade_clientes()', 'adm', ''),
        ('fichas_clientes', 'select * from fichas_clientes()', 'adm', ''),
        ('ficha_pedidos', 'select * from ficha_pedidos(''c%3$s'')', 'adm', ''),
        ('vincular_funcionario', 'select * from vincular_funcionario(%8$s, '''')', 'adm', ''),
        ('comissao_mensal', 'select * from comissao_mensal(2026, 11)', 'adm', ''),
        ('faturamento_diario', 'select * from faturamento_diario(2026, 11)', 'adm', ''),
        ('devedores_fixos', 'select * from devedores_fixos()', 'adm', ''),
        ('bloquear_telefone', 'select * from bloquear_telefone(''69970000091'', ''teste'')', 'adm', ''),
        ('pico_pedidos', 'select * from pico_pedidos(30)', 'adm', ''),
        ('tempo_lavagem', 'select * from tempo_lavagem(30)', 'adm', ''),
        ('ip_do_cliente', 'select ip_do_cliente()', 'int', ''),
        ('consulta_travar', 'select consulta_travar(''11111111'')', 'int', ''),
        ('consulta_verificar', 'select consulta_verificar(''11111111'')', 'int', ''),
        ('consulta_registrar', 'select consulta_registrar(''11111111'', true, null)', 'int', ''),
        ('chave_cliente', 'select chave_cliente(1, ''x'')', 'int', ''),
        ('historico_usuario', 'select historico_usuario()', 'int', ''),
        ('registrar_historico_pedido', 'select registrar_historico_pedido()', 'int', '')
        ) as e(fn, chamada, cls, msg) loop
          z_sql := format(z_r.chamada, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
          z_exp := case
            when z_r.cls = 'int' then 'D'
            when z_papel = 'anon' then case when z_r.cls = 'pub' then 'A' else 'D' end
            when z_r.cls in ('pub', 'auth') then 'A'
            when z_r.cls = 'staff' then case when z_papel = 'sem' then 'N' else 'A' end
            else case when z_papel = 'admin' then 'A' else 'N' end
          end;
          z_got := '';
          begin
            execute z_sql;
            z_got := 'A';
            raise exception 'desfaz' using errcode = 'TS001';
          exception
            when sqlstate 'TS001' then null;
            when insufficient_privilege then z_got := 'D';
            when raise_exception then z_got := case when sqlerrm = 'nao_autorizado' then 'N' else 'B:' || sqlerrm end;
            when others then z_got := 'X:' || sqlstate;
          end;
          v_ok := case z_exp
            when 'D' then z_got = 'D'
            when 'N' then z_got = 'N'
            else (z_r.msg = '' and z_got = 'A') or (z_r.msg <> '' and z_got = 'B:' || z_r.msg)
          end;
          if not v_ok then
            z_falhas := z_falhas || ' ' || z_r.fn || ' (esperado ' || z_exp || ', obteve ' || z_got || ')';
          end if;
        end loop;
        v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'projeto novo simulado: 33 funções como ' || z_papel
              || case when z_falhas = '' then '' else ' => ' || z_falhas end || E'\n';
      end loop;
      execute 'reset role';
    end if;
    raise exception 'desfaz' using errcode = 'TS001';
  exception
    when sqlstate 'TS001' then null;
    when others then
      v_res := v_res || 'AVISO  a simulação de projeto novo foi interrompida por um erro inesperado (' || sqlerrm || ')' || E'\n';
  end;
  execute 'reset role';

  -- 13d) estado REAL do banco: necessidades reais do painel (lista independente da de GRANTs) x privilégios efetivos do authenticated
  execute z_cmp into z_falhas using z_need, z_tabs, array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'FALTA', z_needc, z_colrestr;
  execute z_cmp into z_avisos using z_need, z_tabs, array['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'SOBRA', z_needc, z_colrestr;
  v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || 'authenticated tem, no banco real, todos os privilégios de tabela e de coluna que as operações reais do painel exigem'
        || case when z_falhas = '' then '' else ' (' || z_falhas || '; rode os blocos "Permissões de tabela do painel" e "Permissões por coluna (M5)" do supabase.sql)' end || E'\n';
  v_res := v_res || case when z_avisos = '' then 'OK     ' else 'FALHOU ' end || 'authenticated não tem, no banco real, privilégio de tabela nem de coluna sem uso pelo painel (excedente do padrão antigo revogado; INSERT e UPDATE de pedidos, avaliacoes e funcionarios só nas colunas usadas)'
        || case when z_avisos = '' then '' else ' (ainda presente: ' || z_avisos || '; rode de novo o supabase.sql, blocos "Excedente do padrão antigo (M4)" e "Permissões por coluna (M5)"; se vier de PUBLIC ou de outro papel, veja a pré-checagem da 13c)' end || E'\n';

  -- ==========================================================================================================
  -- 13e) PROJETO ANTIGO SIMULADO: prova que o script CONVERGE para o estado mínimo a partir do padrão antigo do Supabase (todos os privilégios
  --      para o authenticated). Dentro de um sub-bloco (desfeito no fim) executa uma cópia dos comandos de permissão do supabase.sql que
  --      afetam o authenticated, na mesma ordem relativa (revogações iniciais, GRANTs necessários, revogação do excedente M4, revogação de
  --      TRUNCATE/REFERENCES/TRIGGER e de MAINTAIN).
  --      M5: a cópia inclui o bloco "Permissões por coluna (M5)" (revoga INSERT e UPDATE de tabela em pedidos, avaliacoes e funcionarios e concede só as
  --      colunas autorizadas); a comparação final e as sondas de zero linha (z_sondas_*) valem por coluna nessas três tabelas.
  --      ESCOPO: a 13e simula SOMENTE os privilégios de TABELA e de COLUNA do papel authenticated nas tabelas atuais. NÃO simula o anon (o padrão antigo do
  --      anon não é recriado, e o "revoke all ... from anon" e o "grant select on servicos to anon" do supabase.sql não são copiados aqui) e NÃO
  --      simula os privilégios padrão de objetos futuros (ALTER DEFAULT PRIVILEGES), que a seção 12 verifica. Sequências também ficam de fora.
  --      PRÉ-CONDIÇÃO: logo após o "grant all", confirma-se que o authenticated recebeu de fato TODOS os privilégios de z_privs (TRUNCATE,
  --      REFERENCES, TRIGGER e, no PostgreSQL 17+, MAINTAIN) em TODAS as tabelas de z_tabs, como concessão direta. Se faltar qualquer um (por
  --      exemplo, o papel que roda o teste não é dono das tabelas nem tem grant option e o PostgreSQL só emitiu aviso), a simulação é abortada
  --      (TS001) e o resultado é AVISO, nunca OK, porque o estado de partida não foi o padrão antigo e a prova seria vazia.
  -- ==========================================================================================================
  execute 'reset role';
  z_s0 := 'não executado'; z_s1 := 'não executado'; z_falhas := ''; z_q4 := 0; z_pe := 'não executado'; z_pd := '';
  -- z_pall é definida aqui, na própria 13e: não depende de a 13c ter chegado a atribuí-la (NULL faria o z_cmp não comparar nada e dar OK falso)
  z_pall := array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] || z_privs;
  begin
    execute 'grant all on all tables in schema public to authenticated';
    -- pré-condição: o padrão antigo precisa existir de fato (ver "PRÉ-CONDIÇÃO" acima); faltando algo, aborta com AVISO
    z_s0 := (select coalesce(string_agg(t || ':' || p, ', ' order by t, p), '')
               from unnest(z_tabs) as t cross join unnest(z_privs) as p
              where not exists (
                select 1 from pg_class c, aclexplode(c.relacl) a
                 where c.oid = ('public.' || t)::regclass::oid
                   and a.grantee = (select ra.oid from pg_roles ra where ra.rolname = 'authenticated')
                   and a.grantor in (c.relowner, (select rb.oid from pg_roles rb where rb.rolname = current_user))
                   and a.privilege_type = p));
    if z_s0 <> '' then
      z_s0 := 'erro: o GRANT ALL não reproduziu o padrão antigo; não foram concedidos ao authenticated: ' || z_s0
           || ' (o papel que roda o teste precisa ser dono das tabelas ou ter grant option)';
      raise exception 'desfaz' using errcode = 'TS001';
    end if;
    execute 'revoke all on table public.tentativas_consulta from anon, authenticated';
    execute 'revoke insert, update, delete on table public.pedidos_historico from authenticated';
      execute 'grant select, insert, update on table public.servicos to authenticated';
      execute 'grant select, insert on table public.clientes to authenticated';
      execute 'grant select, insert, update, delete on table public.precos_cliente to authenticated';
      execute 'grant select on table public.pedidos to authenticated';
      execute 'grant select, update on table public.config to authenticated';
      execute 'grant select, insert, update, delete on table public.contatos to authenticated';
      execute 'grant select, insert, update, delete on table public.dias_fechados to authenticated';
      execute 'grant select, insert, delete on table public.despesas to authenticated';
      execute 'grant select, delete on table public.avaliacoes to authenticated';
      execute 'grant select on table public.avaliacao_fotos to authenticated';
      execute 'grant select, insert, delete on table public.fotos_pedido to authenticated';
      execute 'grant select, insert, update, delete on table public.cliente_notas to authenticated';
      execute 'grant select on table public.funcionarios to authenticated';
      execute 'grant select, delete on table public.telefones_bloqueados to authenticated';
      execute 'grant select, insert, delete on table public.bloqueios_horario to authenticated';
      execute 'grant select, insert, delete on table public.vistoria_avarias to authenticated';
      execute 'grant select on table public.pedidos_historico to authenticated';
    execute 'revoke delete on table public.servicos from authenticated';
    execute 'revoke update, delete on table public.clientes from authenticated';
    execute 'revoke delete on table public.pedidos from authenticated';
    execute 'revoke insert, delete on table public.config from authenticated';
    execute 'revoke update on table public.despesas from authenticated';
    execute 'revoke insert on table public.avaliacoes from authenticated';
    execute 'revoke insert, update, delete on table public.avaliacao_fotos from authenticated';
    execute 'revoke update on table public.fotos_pedido from authenticated';
    execute 'revoke select, insert, update, delete on table public.admins from authenticated';
    execute 'revoke delete on table public.funcionarios from authenticated';
    execute 'revoke insert, update on table public.telefones_bloqueados from authenticated';
    execute 'revoke update on table public.bloqueios_horario from authenticated';
    execute 'revoke update on table public.vistoria_avarias from authenticated';
    -- M5: mesma sequência do bloco "Permissões por coluna (M5)" do supabase.sql; aqui as revogações removem o INSERT e o UPDATE de tabela do padrão antigo
    execute 'revoke insert, update on table public.pedidos from authenticated';
    execute 'revoke insert, update on table public.avaliacoes from authenticated';
    execute 'revoke insert, update on table public.funcionarios from authenticated';
    execute 'grant insert (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) on table public.pedidos to authenticated';
    execute 'grant update (desconto, funcionario_id, pago, resgate, status, vistoria_em) on table public.pedidos to authenticated';
    execute 'grant update (status) on table public.avaliacoes to authenticated';
    execute 'grant insert (comissao_tipo, comissao_valor, nome) on table public.funcionarios to authenticated';
    execute 'grant update (ativo, comissao_tipo, comissao_valor, nome) on table public.funcionarios to authenticated';
    execute 'revoke truncate, references, trigger on all tables in schema public from anon, authenticated, public';
    if z_ver >= 170000 then
      execute 'revoke maintain on all tables in schema public from anon, authenticated, public';
    end if;
    execute z_cmp into z_s0 using z_need, z_tabs, z_pall, 'AMBOS', z_needc, z_colrestr;
    if z_users and z_s0 = '' then
      z_papel := 'admin';
        execute 'reset role';
        if z_papel = 'anon' then
          perform set_config('request.jwt.claims', '', true);
          perform set_config('request.jwt.claim.sub', '', true);
          execute 'set local role anon';
        else
          z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
          perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', z_uid::text, true);
          execute 'set local role authenticated';
        end if;

      for z_r in select * from (values
        ('servicos', 'select', 'index.html: select x5; backup/exportação lê a tabela inteira', 'select count(*) from servicos where id = %1$s'),
        ('servicos', 'insert', 'index.html: insert x1 (colunas: descricao, nome, preco)', 'insert into servicos (nome, preco) values (''TESTE SEG INS'', 1)'),
        ('servicos', 'update', 'index.html: update x1 (colunas: ativo, descricao, nome, preco)', 'update servicos set ativo = ativo, descricao = descricao, nome = nome, preco = preco where id = %1$s'),
        ('clientes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from clientes where id = %3$s'),
        ('clientes', 'insert', 'index.html: insert x1 (colunas: nome, telefone)', 'insert into clientes (nome) values (''TESTE SEG INS'')'),
        ('precos_cliente', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'delete', 'index.html: delete x1', 'delete from precos_cliente where cliente_id = %3$s and servico_id = %1$s'),
        ('precos_cliente', 'upsert', 'index.html: upsert x1 (colunas: cliente_id, preco, servico_id)', 'insert into precos_cliente (cliente_id, servico_id, preco) values (%3$s, %1$s, 2) on conflict (cliente_id, servico_id) do update set preco = excluded.preco'),
        ('pedidos', 'select', 'index.html: select x14; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from pedidos where id = %4$s'),
        ('pedidos', 'insert', 'index.html: insert x2 (colunas: cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo)', 'insert into pedidos (cliente_id, data_hora, endereco, leva_traz, nome, obs, pago, preco, servico_id, servico_nome, status, taxa, telefone, veiculo) values (%3$s, now(), ''Rua Teste'', true, ''TESTE SEG INS'', ''x'', false, 1, %1$s, ''TESTE'', ''novo'', 0, ''69970000094'', ''TESTE'')'),
        ('pedidos', 'update', 'index.html: update x7 (colunas: desconto, funcionario_id, pago, resgate, status, vistoria_em)', 'update pedidos set desconto = desconto, funcionario_id = funcionario_id, pago = pago, resgate = resgate, status = status, vistoria_em = vistoria_em where id = %4$s'),
        ('config', 'select', 'index.html: select x7; backup/exportação lê a tabela inteira', 'select count(*) from config where id = 1'),
        ('config', 'update', 'index.html: update x6 (colunas: abre, aviso_ativo, aviso_fim, aviso_inicio, aviso_texto, dias, duracao_min, endereco, fecha, fidelidade_a_cada, fidelidade_pct, instagram, leva_traz_ativo, max_pedidos_abertos, taxa_leva_traz, vagas)', 'update config set abre = abre, aviso_ativo = aviso_ativo, aviso_fim = aviso_fim, aviso_inicio = aviso_inicio, aviso_texto = aviso_texto, dias = dias, duracao_min = duracao_min, endereco = endereco, fecha = fecha, fidelidade_a_cada = fidelidade_a_cada, fidelidade_pct = fidelidade_pct, instagram = instagram, leva_traz_ativo = leva_traz_ativo, max_pedidos_abertos = max_pedidos_abertos, taxa_leva_traz = taxa_leva_traz, vagas = vagas where id = 1'),
        ('contatos', 'select', 'index.html: select x4; backup/exportação lê a tabela inteira', 'select count(*) from contatos where rotulo = ''TESTE SEG'''),
        ('contatos', 'insert', 'index.html: insert x1 (colunas: ordem, rotulo, telefone, whatsapp)', 'insert into contatos (rotulo, telefone) values (''TESTE SEG INS'', ''5569999990001'')'),
        ('contatos', 'update', 'index.html: update x2 (colunas: ativo, ordem, rotulo, telefone, whatsapp)', 'update contatos set ativo = ativo, ordem = ordem, rotulo = rotulo, telefone = telefone, whatsapp = whatsapp where rotulo = ''TESTE SEG'''),
        ('contatos', 'delete', 'index.html: delete x1', 'delete from contatos where rotulo = ''TESTE SEG'''),
        ('dias_fechados', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'delete', 'index.html: delete x1', 'delete from dias_fechados where dia = ''2099-01-01'''),
        ('dias_fechados', 'upsert', 'index.html: upsert x1 (colunas: dia, motivo)', 'insert into dias_fechados (dia, motivo) values (''2099-01-01'', ''TESTE'') on conflict (dia) do update set motivo = excluded.motivo'),
        ('despesas', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from despesas where descricao = ''TESTE SEG'''),
        ('despesas', 'insert', 'index.html: insert x1 (colunas: categoria, data, descricao, valor)', 'insert into despesas (descricao, valor) values (''TESTE SEG INS'', 1)'),
        ('despesas', 'delete', 'index.html: delete x1', 'delete from despesas where descricao = ''TESTE SEG'''),
        ('avaliacoes', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from avaliacoes where id = %6$s'),
        ('avaliacoes', 'update', 'index.html: update x2 (colunas: status)', 'update avaliacoes set status = status where id = %6$s'),
        ('avaliacoes', 'delete', 'index.html: delete x1', 'delete from avaliacoes where id = %6$s'),
        ('avaliacao_fotos', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira; embutido em select de avaliacoes', 'select count(*) from avaliacao_fotos where avaliacao_id = %6$s'),
        ('fotos_pedido', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('fotos_pedido', 'insert', 'index.html: insert x1 (colunas: caminho, pedido_id, tipo)', 'insert into fotos_pedido (pedido_id, tipo, caminho) values (%4$s, ''depois'', ''teste-seg/b.jpg'')'),
        ('fotos_pedido', 'delete', 'index.html: delete x1', 'delete from fotos_pedido where caminho = ''teste-seg/a.jpg'''),
        ('cliente_notas', 'select', 'index.html: select x1; backup/exportação lê a tabela inteira', 'select count(*) from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'delete', 'index.html: delete x1', 'delete from cliente_notas where chave = ''teste-seg-1'''),
        ('cliente_notas', 'upsert', 'index.html: upsert x1 (colunas: atualizado_em, chave, obs)', 'insert into cliente_notas (chave, obs) values (''teste-seg-1'', ''y'') on conflict (chave) do update set obs = excluded.obs, atualizado_em = now()'),
        ('funcionarios', 'select', 'index.html: select x3; backup/exportação lê a tabela inteira', 'select count(*) from funcionarios where id = %8$s'),
        ('funcionarios', 'insert', 'index.html: insert x1 (colunas: comissao_tipo, comissao_valor, nome)', 'insert into funcionarios (comissao_tipo, comissao_valor, nome) values (''fixo'', 1, ''TESTE SEG INS'')'),
        ('funcionarios', 'update', 'index.html: update x1 (colunas: ativo, comissao_tipo, comissao_valor, nome)', 'update funcionarios set ativo = ativo, comissao_tipo = comissao_tipo, comissao_valor = comissao_valor, nome = nome where id = %8$s'),
        ('telefones_bloqueados', 'select', 'index.html: select x1', 'select count(*) from telefones_bloqueados where tel8 = ''99990001'''),
        ('telefones_bloqueados', 'delete', 'index.html: delete x1', 'delete from telefones_bloqueados where tel8 = ''99990001'''),
        ('bloqueios_horario', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('bloqueios_horario', 'insert', 'index.html: insert x1 (colunas: dia, fim, inicio, motivo)', 'insert into bloqueios_horario (dia, inicio, fim) values (''2099-01-02'', ''08:00'', ''09:00'')'),
        ('bloqueios_horario', 'delete', 'index.html: delete x1', 'delete from bloqueios_horario where motivo = ''TESTE SEG'''),
        ('vistoria_avarias', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('vistoria_avarias', 'insert', 'index.html: insert x1 (colunas: area, caminho, descricao, pedido_id)', 'insert into vistoria_avarias (pedido_id, area, descricao) values (%4$s, ''Teto'', ''TESTE SEG avaria 2'')'),
        ('vistoria_avarias', 'delete', 'index.html: delete x1', 'delete from vistoria_avarias where descricao = ''TESTE SEG avaria'''),
        ('pedidos_historico', 'select', 'index.html: select x2; backup/exportação lê a tabela inteira', 'select count(*) from pedidos_historico where pedido_id = %4$s')
      ) as o(tab, op, evid, cmd) loop
        z_q4 := z_q4 + 1;
        z_sql := format(z_r.cmd, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
        z_got := '';
        begin
          execute z_sql;
          get diagnostics n = row_count;
          z_got := case when n >= 1 then 'ok' else 'sem linha' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when insufficient_privilege then z_got := 'negado';
          when others then z_got := 'erro:' || sqlstate;
        end;
        if z_got <> 'ok' then z_falhas := z_falhas || ' ' || z_r.tab || '/' || z_r.op || ' (' || z_got || ')'; end if;
      end loop;
      -- M5: sondas de zero linha, como administrador, com o que o script deixou depois de convergir (só roda se a comparação passou)
      z_sonda_fal := ''; z_sonda_inc := ''; z_sonda_ctl := ''; z_sonda_n := 0;
      if current_user <> 'authenticated' then z_sonda_ctl := ' papel efetivo ' || current_user || ' (esperado authenticated)'; end if;
      for z_si in 1 .. coalesce(array_length(z_sondas_sql, 1), 0) loop
        z_sonda_n := z_sonda_n + 1;
        z_sonda_got := '';
        begin
          execute z_sondas_sql[z_si];
          get diagnostics n = row_count;
          z_sonda_got := case when n = 0 then 'zero' else 'ok' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when insufficient_privilege then z_sonda_got := 'negado';
          when others then z_sonda_got := 'erro:' || sqlstate;
        end;
        if z_sondas_exp[z_si] = 'N' then        -- coluna que o painel não usa: tem de ser barrada por privilégio
          if z_sonda_got = 'negado' then null;
          elsif z_sonda_got in ('zero', 'ok') then z_sonda_fal := z_sonda_fal || ' ' || z_sondas_rot[z_si];
          else z_sonda_inc := z_sonda_inc || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')';
          end if;
        elsif z_sondas_exp[z_si] = 'Z' then     -- controle positivo: coluna usada pelo painel, sem linhas, não pode dar erro
          if z_sonda_got <> 'zero' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
        else                                    -- controle negativo conhecido (o M4 revogou): tem de dar negado
          if z_sonda_got <> 'negado' then z_sonda_ctl := z_sonda_ctl || ' ' || z_sondas_rot[z_si] || ' (' || z_sonda_got || ')'; end if;
        end if;
      end loop;
      z_pe := case when z_sonda_ctl <> '' or z_sonda_n = 0 then 'aviso' when z_sonda_fal <> '' then 'falhou' when z_sonda_inc <> '' then 'aviso' else 'ok' end;
      z_pd := trim((case when z_sonda_ctl <> '' then 'CONTROLES FALHARAM (as sondas não valem):' || z_sonda_ctl else '' end)
                || (case when z_sonda_fal <> '' then ' PRIVILÉGIO INDEVIDO:' || z_sonda_fal else '' end)
                || (case when z_sonda_inc <> '' then ' [inconclusivas:' || z_sonda_inc || ']' else '' end));
      execute 'reset role';
      z_s1 := case when z_falhas = '' then 'ok' else z_falhas end;
    end if;
    raise exception 'desfaz' using errcode = 'TS001';
  exception
    when sqlstate 'TS001' then null;
    when others then z_s0 := 'erro: ' || sqlerrm;
  end;
  execute 'reset role';
  v_res := v_res || case when z_s0 = '' then 'OK     ' when z_s0 like 'erro:%' or z_s0 = 'não executado' then 'AVISO  ' else 'FALHOU ' end
        || 'projeto antigo simulado: a partir do padrão antigo (todos os privilégios) o script converge exatamente para as necessidades reais do painel, sem faltar nem sobrar privilégio de tabela ou de coluna (M5)'
        || case when z_s0 = '' then '' else ' => ' || z_s0 || ' (FALTA: necessário que o script removeu; SOBRA: excedente que o script não removeu; se vier de PUBLIC ou de outro papel, veja a pré-checagem da 13c)' end || E'\n';
  v_res := v_res || case when not z_users then 'AVISO  ' when z_s1 = 'ok' then 'OK     ' when z_s1 = 'não executado' then 'AVISO  ' else 'FALHOU ' end
        || 'projeto antigo simulado: depois da revogação do excedente, '
        || case when z_users and (z_s0 like 'erro:%' or z_s0 = 'não executado')
                  then 'as operações reais do painel não foram executadas porque a simulação foi interrompida (pré-condição não atendida ou erro inesperado; detalhes na linha anterior)'
                when z_users and z_s0 <> ''
                  then '45 operações não executadas porque a comparação de privilégios falhou'
                else 'as ' || z_q4 || ' operações reais do painel continuam funcionando como administrador' end
        || case when not z_users then ' (puladas: usuário administrador simulado indisponível)' when z_s1 in ('ok', 'não executado') then '' else ' => falharam:' || z_s1 end || E'\n';
  v_res := v_res || case z_pe when 'ok' then 'OK     ' when 'falhou' then 'FALHOU ' else 'AVISO  ' end
        || 'projeto antigo simulado: sondas de coluna (zero linha, sem RLS) como administrador em pedidos, avaliacoes e funcionarios'
        || case z_pe when 'ok' then ': toda coluna que o painel não usa é barrada por privilégio; as usadas e os controles passam'
                     when 'não executado' then ' não executadas (a comparação de privilégios falhou, a simulação foi interrompida ou o usuário administrador simulado está indisponível)'
                     else ' => ' || z_pd end || E'\n';


  -- ==========================================================================================================
  -- 14) FUNÇÕES: as 33 funções para cada papel (cada chamada é desfeita logo depois). Só conta como "A" quem
  --     funciona sem erro; erro de regra de negócio só vale onde é o esperado; qualquer outro erro é FALHOU.
  -- ==========================================================================================================
  v_res := v_res || 'INFO   legenda das funções: A=funcionou B=recusa de regra de negócio esperada N=nao_autorizado D=negado X=erro inesperado' || E'\n';
  perform set_config('request.headers', '{"cf-connecting-ip":"203.0.118.2"}', true);
  foreach z_papel in array z_papeis loop
    if z_papel in ('func', 'admin') and not z_users then
      v_res := v_res || 'AVISO  funções como ' || z_papel || ' puladas (usuário simulado indisponível)' || E'\n';
      continue;
    end if;
    z_rf := z_rf + 1;
      execute 'reset role';
      if z_papel = 'anon' then
        perform set_config('request.jwt.claims', '', true);
        perform set_config('request.jwt.claim.sub', '', true);
        execute 'set local role anon';
      else
        z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
        perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_uid::text, true);
        execute 'set local role authenticated';
      end if;

    z_linha := ''; z_falhas := '';
    for z_r in select * from (values
        ('config_publica', 'select * from config_publica()', 'pub', ''),
        ('contatos_publicos', 'select * from contatos_publicos()', 'pub', ''),
        ('aviso_publico', 'select * from aviso_publico()', 'pub', ''),
        ('horarios_disponiveis', 'select * from horarios_disponiveis(''2099-01-01''::date)', 'pub', ''),
        ('criar_pedido', 'select * from criar_pedido(''x'', ''1'', ''y'', 0, now())', 'pub', 'dados_invalidos'),
        ('acompanhar_pedido', 'select * from acompanhar_pedido(''69999999999'', ''ZZZZZZ'')', 'pub', ''),
        ('enviar_avaliacao', 'select * from enviar_avaliacao(''69999999999'', ''ZZZZZZ'', 5, ''x'')', 'pub', 'pedido_nao_encontrado'),
        ('avaliacoes_publicas', 'select * from avaliacoes_publicas(6, 0)', 'pub', ''),
        ('resumo_avaliacoes', 'select * from resumo_avaliacoes()', 'pub', ''),
        ('is_admin', 'select * from is_admin()', 'auth', ''),
        ('meu_papel', 'select * from meu_papel()', 'auth', ''),
        ('staff_pedidos', 'select * from staff_pedidos(null::date)', 'staff', ''),
        ('staff_funcionarios', 'select * from staff_funcionarios()', 'staff', ''),
        ('staff_definir_status', 'select * from staff_definir_status(%4$s, ''lavando'')', 'staff', ''),
        ('staff_definir_funcionario', 'select * from staff_definir_funcionario(%4$s, %8$s)', 'staff', ''),
        ('remarcar_pedido', 'select * from remarcar_pedido(%4$s, ''2099-01-01 13:00:00+00''::timestamptz)', 'adm', 'horario_indisponivel'),
        ('fidelidade_clientes', 'select * from fidelidade_clientes()', 'adm', ''),
        ('fichas_clientes', 'select * from fichas_clientes()', 'adm', ''),
        ('ficha_pedidos', 'select * from ficha_pedidos(''c%3$s'')', 'adm', ''),
        ('vincular_funcionario', 'select * from vincular_funcionario(%8$s, '''')', 'adm', ''),
        ('comissao_mensal', 'select * from comissao_mensal(2026, 11)', 'adm', ''),
        ('faturamento_diario', 'select * from faturamento_diario(2026, 11)', 'adm', ''),
        ('devedores_fixos', 'select * from devedores_fixos()', 'adm', ''),
        ('bloquear_telefone', 'select * from bloquear_telefone(''69970000091'', ''teste'')', 'adm', ''),
        ('pico_pedidos', 'select * from pico_pedidos(30)', 'adm', ''),
        ('tempo_lavagem', 'select * from tempo_lavagem(30)', 'adm', ''),
        ('ip_do_cliente', 'select ip_do_cliente()', 'int', ''),
        ('consulta_travar', 'select consulta_travar(''11111111'')', 'int', ''),
        ('consulta_verificar', 'select consulta_verificar(''11111111'')', 'int', ''),
        ('consulta_registrar', 'select consulta_registrar(''11111111'', true, null)', 'int', ''),
        ('chave_cliente', 'select chave_cliente(1, ''x'')', 'int', ''),
        ('historico_usuario', 'select historico_usuario()', 'int', ''),
        ('registrar_historico_pedido', 'select registrar_historico_pedido()', 'int', '')
    ) as e(fn, chamada, cls, msg) loop
      z_sql := format(z_r.chamada, z_srv1, z_srv2, z_cli, z_ped1, z_ped2, z_av, z_f1, z_f2);
      z_exp := case
        when z_r.cls = 'int' then 'D'
        when z_papel = 'anon' then case when z_r.cls = 'pub' then 'A' else 'D' end
        when z_r.cls in ('pub', 'auth') then 'A'
        when z_r.cls = 'staff' then case when z_papel = 'sem' then 'N' else 'A' end
        else case when z_papel = 'admin' then 'A' else 'N' end
      end;
      z_got := '';
      z_ck_fn := z_ck_fn + 1;
      begin
        execute z_sql;
        z_got := 'A';
        raise exception 'desfaz' using errcode = 'TS001';
      exception
        when sqlstate 'TS001' then null;
        when insufficient_privilege then z_got := 'D';
        when raise_exception then z_got := case when sqlerrm = 'nao_autorizado' then 'N' else 'B:' || sqlerrm end;
        when others then z_got := 'X:' || sqlstate;
      end;
      v_ok := case z_exp
        when 'D' then z_got = 'D'
        when 'N' then z_got = 'N'
        else (z_r.msg = '' and z_got = 'A') or (z_r.msg <> '' and z_got = 'B:' || z_r.msg)
      end;
      z_linha := z_linha || ' ' || z_r.fn || ':' || left(z_got, 1);
      if not v_ok then
        z_falhas := z_falhas || ' ' || z_r.fn || ' (esperado ' || case when z_exp = 'A' then 'funcionar' || case when z_r.msg <> '' then ' com o erro ' || z_r.msg else '' end else z_exp end
                    || ', obteve ' || z_got || ')';
      end if;
    end loop;
    v_res := v_res || case when z_falhas = '' then 'OK     ' else 'FALHOU ' end || '33 funções como ' || z_papel || case when z_falhas = '' then '' else ' => ' || z_falhas end || E'\n'
          || 'INFO   ' || z_papel || ':' || z_linha || E'\n';
  end loop;
  execute 'reset role';

  -- 14b) quem é quem: is_admin() e meu_papel()
  foreach z_papel in array array['sem', 'func', 'admin'] loop
    if z_papel <> 'sem' and not z_users then continue; end if;
    z_a := null; z_b := null;
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

    begin
      select is_admin()::text, coalesce(meu_papel(), 'nulo') into z_a, z_b;
    exception when others then
      z_a := 'erro ' || sqlerrm;
    end;
    v_ok := (z_a, z_b) is not distinct from (case z_papel when 'admin' then 'true' else 'false' end,
                                              case z_papel when 'admin' then 'admin' when 'func' then 'funcionario' else 'nulo' end);
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'papel reconhecido como ' || z_papel || ' (is_admin=' || coalesce(z_a, '?') || ', meu_papel=' || coalesce(z_b, '?') || ')' || E'\n';
  end loop;
  execute 'reset role';

  if z_users then
    -- 14c) funcionário vê os pedidos do dia, mas as funções dele não devolvem valores nem comissão
    z_papel := 'func';
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

    begin
      v_ok := exists (select 1 from staff_pedidos(null) where o_id = z_ped1);
    exception when others then
      v_ok := false;
    end;
    execute 'reset role';
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'funcionário enxerga o pedido do dia em staff_pedidos' || E'\n';
    v_ok := pg_get_function_result('staff_pedidos(date)'::regprocedure) !~* 'preco|valor|pago|desconto|taxa';
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'staff_pedidos não devolve preço, desconto, taxa nem pagamento' || E'\n';
    v_ok := pg_get_function_result('staff_funcionarios()'::regprocedure) !~* 'comiss|valor|email|user';
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'staff_funcionarios não devolve comissão, e-mail nem usuário' || E'\n';
    -- 14d) funcionário: status inválido é recusado e a alteração válida entra no histórico com o nome dele
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

    begin
      perform staff_definir_status(z_ped1, 'xyz');
      v_ok := false;
    exception when others then
      v_ok := sqlerrm = 'status_invalido';
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'funcionário não define status inválido' || E'\n';
    z_a := null;
    begin
      perform staff_definir_status(z_ped1, 'lavando');
      execute 'reset role';
      select usuario into z_a from pedidos_historico where pedido_id = z_ped1 and campo = 'status' order by id desc limit 1;
      v_ok := z_a = 'TESTE SEG F1 (funcionário)';
      raise exception 'desfaz' using errcode = 'TS001';
    exception
      when sqlstate 'TS001' then null;
      when others then v_ok := false; z_a := sqlerrm;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'alteração do funcionário fica no histórico com o nome dele (usuário gravado: ' || coalesce(z_a, '?') || ')' || E'\n';
    -- 14e) funcionário desativado perde o acesso
    execute 'reset role';
    z_a := null; v_ok := false;
    begin
      update funcionarios set ativo = false where user_id = z_func;
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

      z_a := coalesce(meu_papel(), 'nulo');
      begin
        perform * from staff_funcionarios();
        z_ok2 := false;
      exception when others then
        z_ok2 := sqlerrm = 'nao_autorizado';
      end;
      v_ok := z_a = 'nulo' and z_ok2;
      raise exception 'desfaz' using errcode = 'TS001';
    exception
      when sqlstate 'TS001' then null;
      when others then v_ok := false; z_a := sqlerrm;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'funcionário desativado perde o acesso (meu_papel e staff_funcionarios) ' || coalesce('[' || z_a || ']', '') || E'\n';
    execute 'reset role';

    -- 14f) administrador: vínculo de funcionário com usuário (regras de vincular_funcionario)
    z_papel := 'admin';
    for z_r in select * from (values
      ('teste-seg-admin@exemplo.invalid', 'usuario_e_admin'),
      ('teste-seg-func@exemplo.invalid', 'usuario_ja_vinculado'),
      ('naoexiste-teste-seg@exemplo.invalid', 'usuario_nao_encontrado'),
      ('teste-seg-sem@exemplo.invalid', 'OK')
    ) as e(email, esperado) loop
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

      z_got := '';
      begin
        perform vincular_funcionario(z_f2, z_r.email);
        z_got := 'OK';
        raise exception 'desfaz' using errcode = 'TS001';
      exception
        when sqlstate 'TS001' then null;
        when others then z_got := sqlerrm;
      end;
      v_ok := z_got = z_r.esperado;
      v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'vincular_funcionario: ' || z_r.email || ' => esperado ' || z_r.esperado || ', obteve ' || z_got || E'\n';
    end loop;
    -- 14g) administrador: bloquear_telefone cancela só os pedidos novos do telefone e rejeita telefone curto
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

    z_a := null;
    begin
      select bloquear_telefone('69970000091', 'TESTE SEG') into n;
      v_ok := n >= 1 and exists (select 1 from telefones_bloqueados where tel8 = '70000091')
              and (select status from pedidos where id = z_ped1) = 'cancelado';
      raise exception 'desfaz' using errcode = 'TS001';
    exception
      when sqlstate 'TS001' then null;
      when others then v_ok := false; z_a := sqlerrm;
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'administrador bloqueia telefone e cancela o pedido novo dele' || coalesce(' [' || z_a || ']', '') || E'\n';
    begin
      perform bloquear_telefone('123', 'x');
      v_ok := false;
    exception when others then
      v_ok := sqlerrm = 'telefone_invalido';
    end;
    v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'bloquear_telefone recusa telefone curto' || E'\n';
    execute 'reset role';
  else
    v_res := v_res || 'AVISO  testes 14c a 14g (funcionário e administrador em detalhe) pulados: usuários simulados indisponíveis' || E'\n';
  end if;

  -- 14h) o público não vê avaliação pendente, contato inativo, nem o sobrenome do cliente
  z_papel := 'anon';
  execute 'reset role';
  if z_papel = 'anon' then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
    perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', z_uid::text, true);
    execute 'set local role authenticated';
  end if;

  begin
    v_ok := not exists (select 1 from avaliacoes_publicas(12, 0) where o_id = z_av)
            and exists (select 1 from avaliacoes_publicas(12, 0) where o_id = z_av3);
  exception when others then
    v_ok := false;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'avaliacoes_publicas esconde a avaliação pendente e mostra a aprovada' || E'\n';
  begin
    select o_nome into z_a from avaliacoes_publicas(12, 0) where o_id = z_av3;
    v_ok := z_a = 'TESTE';
  exception when others then
    v_ok := false; z_a := sqlerrm;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'avaliacoes_publicas mostra só o primeiro nome (recebido: ' || coalesce(z_a, 'nulo') || ')' || E'\n';
  begin
    v_ok := exists (select 1 from contatos_publicos() where o_rotulo = 'TESTE SEG')
        and not exists (select 1 from contatos_publicos() where o_rotulo = 'TESTE SEG OFF');
  exception when others then
    v_ok := false;
  end;
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'contatos_publicos mostra só os ativos' || E'\n';
  execute 'reset role';

  -- ==========================================================================================================
  -- 15) ARMAZENAMENTO DE FOTOS (bucket "fotos" e políticas de storage.objects)
  -- ==========================================================================================================
  execute 'reset role';
  z_pub := null;
  select public, file_size_limit, allowed_mime_types into z_pub, z_lim, z_mime from storage.buckets where id = 'fotos';
  if z_pub is null then
    v_res := v_res || 'FALHOU bucket "fotos" não existe' || E'\n';
  else
    v_res := v_res || case when not z_pub then 'OK     ' else 'FALHOU ' end || 'bucket fotos é privado (public = ' || z_pub::text || ')' || E'\n';
    v_res := v_res || case when z_lim = 3145728 then 'OK     ' else 'FALHOU ' end || 'bucket fotos limita o arquivo a 3 MB (limite: ' || coalesce(z_lim::text, 'sem limite') || ')' || E'\n';
    v_res := v_res || case when z_mime = array['image/jpeg'] then 'OK     ' else 'FALHOU ' end || 'bucket fotos só aceita image/jpeg (aceita: ' || coalesce(array_to_string(z_mime, ','), 'qualquer tipo') || ')' || E'\n';
  end if;
  v_ok := coalesce((select relrowsecurity from pg_class where oid = 'storage.objects'::regclass), false);
  v_res := v_res || case when v_ok then 'OK     ' else 'FALHOU ' end || 'RLS ligado em storage.objects' || E'\n';
  select count(*) into n from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and policyname in ('admin fotos ver', 'admin fotos enviar', 'admin fotos apagar')
     and roles = '{authenticated}'::name[] and coalesce(qual, with_check) like '%is_admin%';
  v_res := v_res || case when n = 3 then 'OK     ' else 'FALHOU ' end || 'políticas de ver, enviar e apagar fotos existem e exigem administrador (encontradas: ' || n || ' de 3)' || E'\n';
  select string_agg(policyname, ', ') into z_prob from pg_policies
   where schemaname = 'storage' and tablename in ('objects', 'buckets') and permissive = 'PERMISSIVE'
     and roles && array['anon', 'public']::name[];
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma política de storage libera acesso a anon ou a todos'
        || coalesce(' (revisar: ' || z_prob || ')', '') || E'\n';
  select string_agg(policyname, ', ') into z_prob from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and cmd in ('UPDATE', 'ALL');
  v_res := v_res || case when z_prob is null then 'OK     ' else 'AVISO  ' end || 'nenhuma política permite alterar objetos de storage (só ver, enviar e apagar)'
        || coalesce(' (revisar: ' || z_prob || ')', '') || E'\n';
  begin
    insert into storage.objects (bucket_id, name) values ('fotos', 'teste-seg/a.jpg');
    select count(*) into n from storage.objects where bucket_id = 'fotos' and name = 'teste-seg/a.jpg';
    if n <> 1 then
      z_storage := false;
      v_res := v_res || 'FALHOU controle positivo do storage: o objeto de teste não foi encontrado depois de criado (' || n || ')' || E'\n';
    end if;
  exception when others then
    z_storage := false;
    v_res := v_res || 'AVISO  não foi possível criar um objeto de teste em storage.objects (' || sqlerrm || '): testes de storage por papel pulados; use o roteiro R3' || E'\n';
  end;
  if z_storage then
    v_res := v_res || 'INFO   legenda storage (leitura, inserção, alteração, exclusão): N=negado 0=sem efeito +=permitido ?=erro' || E'\n';
    foreach z_papel in array z_papeis loop
      if z_papel in ('func', 'admin') and not z_users then
        v_res := v_res || 'AVISO  storage como ' || z_papel || ' pulado (usuário simulado indisponível)' || E'\n';
        continue;
      end if;
      z_rs := z_rs + 1;
      execute 'reset role';
      if z_papel = 'anon' then
        perform set_config('request.jwt.claims', '', true);
        perform set_config('request.jwt.claim.sub', '', true);
        execute 'set local role anon';
      else
        z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
        perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', z_uid::text, true);
        execute 'set local role authenticated';
      end if;

      z_sim := ''; z_falhas := ''; z_avisos := '';
      for z_r in select * from (values
        ('leitura', 'select count(*) from storage.objects where bucket_id = ''fotos'' and name = ''teste-seg/a.jpg'''),
        ('insercao', 'insert into storage.objects (bucket_id, name) values (''fotos'', ''teste-seg/b.jpg'')'),
        ('alteracao', 'update storage.objects set name = name where bucket_id = ''fotos'' and name = ''teste-seg/a.jpg'''),
        ('exclusao', 'delete from storage.objects where bucket_id = ''fotos'' and name = ''teste-seg/a.jpg''')
      ) as e(op, comando) loop
        z_exp := case when z_papel = 'admin' and z_r.op in ('leitura', 'insercao', 'exclusao') then 'ALLOW' else 'BLOCK' end;
        z_got := '';
        z_ck_st := z_ck_st + 1;
        begin
          perform set_config('storage.allow_delete_query', 'true', true);
          if z_r.op = 'leitura' then
            execute z_r.comando into n;
          else
            execute z_r.comando;
            get diagnostics n = row_count;
          end if;
          z_got := case when n = 0 then 'zero' else 'ok' end;
          raise exception 'desfaz' using errcode = 'TS001';
        exception
          when sqlstate 'TS001' then null;
          when insufficient_privilege then z_got := 'negado';
          when others then z_got := 'erro:' || sqlstate;
        end;
        z_sim := z_sim || case z_got when 'negado' then 'N' when 'zero' then '0' when 'ok' then '+' else '?' end;
        if left(z_got, 4) = 'erro' then
          z_avisos := z_avisos || ' ' || z_r.op || ' (' || z_got || ')';
        elsif z_exp = 'ALLOW' and z_got <> 'ok' then
          z_falhas := z_falhas || ' ' || z_r.op || ' (esperado permitido, obteve ' || z_got || ')';
        elsif z_exp = 'BLOCK' and not (z_got = 'negado' or (z_r.op <> 'insercao' and z_got = 'zero')) then
          z_falhas := z_falhas || ' ' || z_r.op || ' (esperado bloqueado, obteve ' || z_got || ')';
        end if;
      end loop;
      v_res := v_res || case when z_falhas <> '' then 'FALHOU ' when z_avisos <> '' then 'AVISO  ' else 'OK     ' end
            || 'storage.objects (fotos) como ' || z_papel || ': ' || z_sim
            || case when z_falhas <> '' then ' =>' || z_falhas else '' end
            || case when z_avisos <> '' then ' [inconclusivo, confirmar pela API (R3):' || z_avisos || ']' else '' end || E'\n';
    end loop;
    -- administrador também não grava em outro bucket
    if z_users then
      z_papel := 'admin';
    execute 'reset role';
    if z_papel = 'anon' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
    else
      z_uid := case z_papel when 'sem' then z_sem when 'func' then z_func else z_adm end;
      perform set_config('request.jwt.claims', json_build_object('sub', z_uid, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', z_uid::text, true);
      execute 'set local role authenticated';
    end if;

      z_got := '';
      begin
        execute 'insert into storage.objects (bucket_id, name) values (''teste-seg-outro'', ''x.jpg'')';
        z_got := 'ok';
        raise exception 'desfaz' using errcode = 'TS001';
      exception
        when sqlstate 'TS001' then null;
        when insufficient_privilege then z_got := 'negado';
        when others then z_got := 'erro:' || sqlstate;
      end;
      v_res := v_res || case when z_got = 'negado' then 'OK     ' when z_got = 'ok' then 'FALHOU ' else 'AVISO  ' end
            || 'administrador não grava objetos fora do bucket fotos (resultado: ' || z_got || ')' || E'\n';
    end if;
  end if;
  execute 'reset role';

  -- ==========================================================================================================
  -- 16) COBERTURA E RESUMO
  -- ==========================================================================================================
  v_ok := z_ck_tab = z_rt * 76 and z_ck_fn = z_rf * 33 and z_ck_st = z_rs * 4 and z_ck_sim = z_rsim * 76;
  v_res := v_res || case when not v_ok then 'FALHOU ' when z_rt = 4 and z_rf = 4 and z_rs = 4 and z_rsim = 4 then 'OK     ' else 'AVISO  ' end
        || 'cobertura: ' || z_ck_tab || ' verificações de tabela (' || z_rt || ' de 4 papéis), ' || z_ck_fn || ' de função (' || z_rf || ' de 4), '
        || z_ck_st || ' de storage (' || z_rs || ' de 4), ' || z_ck_sim || ' de tabela no projeto novo simulado (' || z_rsim || ' de 4)'
        || case when not v_ok then ' => alguma verificação deixou de rodar (esperado 76 por papel nas tabelas, 33 nas funções e 4 no storage)'
                when z_rt < 4 or z_rf < 4 or z_rs < 4 or z_rsim < 4 then ' => há papéis ou partes puladas (veja os AVISOs acima)' else '' end
        || case when z_simok then '' else ' [simulação de projeto novo NÃO concluída]' end || E'\n';
  select count(*) filter (where l like 'OK%'), count(*) filter (where l like 'FALHOU%'), count(*) filter (where l like 'AVISO%'),
         string_agg(l, E'\n') filter (where l like 'FALHOU%' or l like 'AVISO%')
    into z_n1, z_n2, z_n3, z_prob
    from regexp_split_to_table(v_res, E'\n') as l;
  raise exception E'RESULTADO DOS TESTES (nada foi gravado): % OK, % FALHOU, % AVISO\n\nPROBLEMAS (FALHOU e AVISO):\n%\n\nDETALHES:\n%',
    z_n1, z_n2, z_n3, coalesce(z_prob, 'nenhum'), v_res;
end
$$;
