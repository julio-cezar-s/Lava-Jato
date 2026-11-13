# Lava-Jato — Sistema de Gestão e Atendimento

Sistema web para apresentação de serviços, atendimento de clientes e gerenciamento das operações de um lava-jato. O projeto foi desenvolvido para oferecer uma experiência simples aos clientes e ferramentas de administração para o responsável pelo estabelecimento.

O sistema reúne em um único site a apresentação dos serviços, consulta de pedidos, avaliação do atendimento e um painel administrativo conectado a um banco de dados Supabase.

---

## 1. Objetivo do projeto

O objetivo é digitalizar e organizar o atendimento do lava-jato, permitindo que os clientes conheçam os serviços disponíveis, solicitem atendimento e acompanhem a situação de seus pedidos.

Ao mesmo tempo, o responsável pelo estabelecimento dispõe de um painel administrativo para acompanhar os pedidos, atualizar os serviços e gerenciar as informações utilizadas no atendimento.

O projeto busca oferecer:

- Facilidade de utilização para os clientes.
- Organização dos pedidos e atendimentos.
- Acompanhamento dos serviços em andamento.
- Comunicação mais prática entre estabelecimento e clientes.
- Registro de avaliações.
- Administração centralizada das informações.
- Segurança no acesso aos dados e nas operações do sistema.

## 2. Tecnologias utilizadas

| Tecnologia | Finalidade |
|---|---|
| HTML5 | Estrutura das páginas e funcionalidades do site. |
| CSS3 | Aparência, identidade visual e adaptação para dispositivos móveis. |
| JavaScript | Interatividade, validações e funcionamento das funcionalidades. |
| Supabase | Banco de dados, autenticação, políticas de segurança e funções do sistema. |
| PostgreSQL | Banco de dados utilizado pelo Supabase. |
| Cloudflare Pages | Hospedagem e publicação do site. |
| Git e GitHub | Controle de versões e organização do desenvolvimento. |

O projeto utiliza uma estrutura baseada em `index.html`, concentrando a aplicação principal em um único arquivo.

## 3. Área pública — clientes

A área pública é destinada aos clientes que acessam o site para conhecer os serviços e utilizar os recursos de atendimento.

### 3.1. Apresentação do estabelecimento

A página inicial apresenta o lava-jato, suas informações de atendimento e os recursos disponíveis para os visitantes.

Entre os elementos da página estão:

- Identificação do estabelecimento.
- Informações de localização.
- Apresentação dos serviços.
- Valores dos serviços, conforme os dados cadastrados.
- Formas de contato.
- Acesso ao WhatsApp.
- Acesso ao mapa de localização.
- Avaliações de clientes.

A apresentação foi organizada em seções para facilitar a navegação e deixar as informações mais acessíveis.

### 3.2. Serviços

O sistema permite apresentar os serviços oferecidos pelo estabelecimento, utilizando informações armazenadas no Supabase.

Os serviços e seus respectivos valores podem ser administrados pelo painel, conforme as permissões configuradas.

### 3.3. Acompanhamento de pedidos

O cliente pode consultar a situação de seu pedido utilizando as informações de identificação solicitadas pelo sistema, como telefone e código do pedido.

O acompanhamento permite verificar o andamento do atendimento sem precisar acessar o painel administrativo.

O sistema utiliza uma função do Supabase para realizar essa consulta, com mecanismos de controle de tentativas para dificultar consultas indevidas e tentativas de descoberta de códigos.

### 3.4. Avaliação do atendimento

O cliente pode avaliar o serviço realizado.

O sistema possui mecanismos para verificar se o pedido está apto a receber uma avaliação e evitar avaliações duplicadas.

As avaliações podem ser apresentadas na área pública, de acordo com as regras configuradas no banco de dados.

### 3.5. Contato

O site disponibiliza recursos para facilitar a comunicação com o estabelecimento, incluindo:

- WhatsApp.
- Instagram, quando configurado.
- Endereço e localização.
- Link para consulta no mapa.

## 4. Painel administrativo

O painel administrativo é destinado ao gerenciamento interno do lava-jato.

O acesso é protegido por autenticação e verificação das permissões administrativas.

Entre as funcionalidades desenvolvidas estão:

### 4.1. Gerenciamento de pedidos

Permite acompanhar os pedidos cadastrados no sistema e realizar operações administrativas, como:

- Consultar pedidos.
- Visualizar informações do atendimento.
- Atualizar a situação dos pedidos.
- Gerenciar informações relacionadas ao atendimento.
- Acompanhar as mudanças realizadas.

### 4.2. Atualização de status

O painel permite alterar a situação dos pedidos.

As mudanças realizadas no painel são refletidas na consulta pública do cliente, permitindo acompanhar o andamento do serviço.

### 4.3. Funcionários

O projeto possui recursos relacionados ao gerenciamento de funcionários e à identificação do responsável pelo atendimento, conforme as permissões implementadas no banco de dados.

### 4.4. Serviços e informações

O painel também utiliza dados armazenados no Supabase para administrar informações apresentadas na área pública.

### 4.5. Avaliações

O administrador pode consultar as avaliações enviadas pelos clientes e acompanhar as notas recebidas.

## 5. Banco de dados e integração com Supabase

O Supabase é responsável pelo armazenamento das informações e pela execução de operações importantes do sistema.

A aplicação utiliza recursos como:

- PostgreSQL para armazenamento dos dados.
- Supabase Auth para autenticação.
- Row Level Security (RLS) para controle de acesso às tabelas.
- Funções RPC para operações específicas.
- Políticas de acesso para usuários públicos e autenticados.

### Segurança do banco de dados

A segurança é uma parte importante do projeto.

Foram desenvolvidos mecanismos para:

- Restringir o acesso ao painel administrativo.
- Controlar as permissões dos usuários.
- Proteger informações dos clientes.
- Restringir consultas públicas.
- Controlar tentativas de acompanhamento de pedidos.
- Evitar avaliações duplicadas.
- Restringir operações administrativas por meio de funções e políticas do banco.

As funções e políticas do Supabase devem ser mantidas alinhadas com as operações realizadas pelo `index.html`.

**Importante:** a chave `sb_publishable_` utilizada no navegador é uma chave pública de aplicação. Ela não substitui as políticas RLS, as permissões do banco ou a validação das operações no servidor.

Nenhuma chave `service_role` ou credencial administrativa secreta deve ser colocada no HTML público.

## 6. Segurança do acompanhamento de pedidos

O acompanhamento público merece atenção especial porque permite consultar informações sem exigir que o cliente entre no painel administrativo.

Por isso, o projeto utiliza mecanismos de proteção contra tentativas excessivas e consultas indevidas.

Entre os recursos de segurança desenvolvidos estão:

- Validação das informações utilizadas na consulta.
- Limitação de tentativas.
- Bloqueio temporário em situações de abuso.
- Controle associado ao telefone e ao IP, conforme as regras implementadas.
- Mensagens de erro que evitam revelar informações desnecessárias.
- Proteção contra tentativas automatizadas de descobrir códigos de pedidos.

O controle no navegador complementa as proteções do servidor, mas não as substitui.

## 7. Hospedagem e publicação

O site utiliza Cloudflare Pages para hospedagem.

O repositório GitHub é utilizado para armazenar os arquivos e controlar as alterações.

A organização do desenvolvimento utiliza duas branches principais:

| Branch | Finalidade |
|---|---|
| `main` | Versão de referência do site. |
| `desenvolvimento` | Ambiente de trabalho para melhorias, correções e testes. |

As alterações devem ser desenvolvidas e testadas primeiro na branch `desenvolvimento`.

Somente depois da revisão e aprovação das mudanças, elas poderão ser integradas à `main` e preparadas para publicação.

Essa separação reduz o risco de alterações em desenvolvimento afetarem a versão de referência.

## 8. Estrutura do projeto

A aplicação principal está concentrada no arquivo:

```text
index.html
```

O repositório também pode conter arquivos complementares de configuração, banco de dados, testes e documentação.

Exemplo de organização:

```text
Lava-Jato/
│
├── index.html
├── README.md
├── supabase.sql
├── supabase-teste.sql
├── testes-seguranca.sql
│
└── outros arquivos de configuração e documentação
```

A lista acima é ilustrativa. Os arquivos efetivamente presentes no repositório devem ser conferidos antes de utilizar esses nomes como estrutura definitiva.

## 9. Ambiente de desenvolvimento

O desenvolvimento é realizado utilizando:

- Visual Studio Code.
- Git.
- GitHub.
- Cloudflare Pages.
- Supabase.
- Navegador para testes e validações.

### Fluxo recomendado de trabalho

1. Atualizar a branch `desenvolvimento`.
2. Realizar as alterações necessárias.
3. Revisar o código e o diff.
4. Executar testes funcionais.
5. Executar testes de segurança quando aplicável.
6. Verificar a integração com o Supabase de desenvolvimento.
7. Conferir o comportamento em dispositivos móveis e computadores.
8. Aprovar as alterações antes de integrá-las à `main`.

A branch `main` deve permanecer preservada enquanto as alterações não forem aprovadas.

## 10. Testes e validação

O projeto vem passando por verificações funcionais, técnicas e de segurança.

Os testes realizados incluem:

- Cadastro de pedidos.
- Consulta de pedidos.
- Atualização de status.
- Sincronização das informações entre painel e área pública.
- Edição e exclusão de registros.
- Envio de avaliações.
- Bloqueio de acesso não autorizado ao painel.
- Verificação de permissões.
- Proteção contra tentativas excessivas de consulta.
- Testes de responsividade.
- Verificação de erros JavaScript.
- Revisão de alterações no código.

Os resultados dos testes devem ser registrados conforme cada etapa for concluída. Uma aprovação em testes locais não significa, por si só, que todas as condições de produção foram validadas.

## 11. SEO e acessibilidade

O site também recebe melhorias para facilitar sua identificação nos mecanismos de busca e tornar a navegação mais acessível.

Entre os itens trabalhados estão:

- Título da página.
- Meta description.
- Organização dos títulos e seções.
- Descrições alternativas para imagens.
- Textos acessíveis para leitores de tela.
- Identificação acessível das avaliações.
- Melhorias nos links de contato e localização.
- Otimização das conexões com recursos externos.

Essas melhorias devem preservar as funcionalidades e a identidade visual do sistema.

## 12. Cuidados antes da publicação

Antes de publicar alterações na versão definitiva, é necessário:

1. Confirmar a URL e a chave do projeto Supabase correto.
2. Verificar se todas as tabelas e funções necessárias existem no banco de destino.
3. Conferir as políticas RLS e as permissões.
4. Validar as funções RPC utilizadas pelo site.
5. Confirmar que nenhuma configuração do ambiente de testes foi levada indevidamente para produção.
6. Testar as operações públicas e administrativas.
7. Revisar as informações de contato e localização.
8. Verificar o funcionamento em dispositivos móveis.
9. Conferir se não existem erros no console.
10. Aprovar as alterações antes da integração com a `main`.

**Atenção aos arquivos SQL:** scripts de testes podem criar dados temporários, alterar estruturas ou executar operações específicas. Não devem ser executados em produção sem análise prévia de seu conteúdo e finalidade.

## 13. Situação atual do projeto

O projeto encontra-se em fase de desenvolvimento, revisão e testes.

O ambiente de desenvolvimento é utilizado para implementar melhorias e validar as funcionalidades antes de qualquer alteração definitiva.

As configurações do Supabase de testes devem permanecer separadas das configurações de produção.

A publicação definitiva depende da conclusão das verificações funcionais, de segurança e de integração com o banco de dados correto.

## 14. Objetivos futuros

O projeto poderá receber novas funcionalidades e melhorias, conforme as necessidades do estabelecimento.

Algumas possibilidades de evolução:

- Relatórios de atendimentos.
- Indicadores de desempenho.
- Histórico detalhado de clientes.
- Melhorias no gerenciamento de funcionários.
- Estatísticas de serviços realizados.
- Relatórios financeiros.
- Melhorias na experiência do cliente.
- Notificações sobre mudanças na situação dos pedidos.
- Recursos adicionais de controle administrativo.

Novas funcionalidades devem ser implementadas de forma gradual, mantendo a compatibilidade com a estrutura existente e os controles de segurança.

---

## Considerações finais

O Lava-Jato foi concebido para ser uma ferramenta prática de atendimento e gestão, reunindo a experiência do cliente e a administração do estabelecimento em uma aplicação web.

A prioridade do desenvolvimento é manter o sistema simples de utilizar, confiável, responsivo e seguro, com uma estrutura que permita futuras melhorias sem comprometer as funcionalidades já existentes.

**Repositório:** https://github.com/julio-cezar-s/Lava-Jato

**Hospedagem:** Cloudflare Pages

**Banco de dados:** Supabase

**Status:** Em desenvolvimento e testes.
