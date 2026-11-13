# Landing zone e blueprints na management account

A preparação inicial usa [`bootstrap/main.tf`](../bootstrap/README.md). Este root publica o blueprint `account-baseline` na management account, que também será o hub dos blueprints neste projeto pessoal. A landing zone é declarada em `10_controltower.tf`. A criação das contas de workloads é feita pelo console do Account Factory. Este root não declara permission sets nem atribuições no IAM Identity Center.

## Arquivos

| Arquivo | Responsabilidade |
| --- | --- |
| `00_backend.tf` | Backend S3 do estado da management. |
| `00_providers.tf` | Região, profile e tags do provider. |
| `00_variables.tf` | Inputs de execução e ARN do operador do console. |
| `00_data.tf` | Dados da conta, região e partição. |
| `20_account_factory.tf` | Bucket de templates, upload, produto do Service Catalog e role de acesso. |
| `00_outputs.tf` | ID do hub, produto, versão e ARN da role. |
| `templates/account-baseline.yaml` | Recursos CloudFormation a criar nas novas contas. |
| `10_controltower.tf` | Landing zone 4.0 com o manifest `../landing-zone.json`. |
| `account-bootstrap/` | Alternativa preservada, fora do fluxo escolhido; possui estado e execução separados. |

## O que fica na management account

- Bucket privado `controltower-blueprints-<ACCOUNT_ID>-<REGION>`, versionado e com SSE-S3, usando o [módulo `s3`](https://github.com/igor-platform-lab/terraform-modules/tree/55c042f2753c907bf01cda102eea8a33756d2a39/modules/s3) via Git, com revisão fixa.
- Template YAML armazenado no bucket e produto `account-baseline` do tipo `CLOUD_FORMATION_TEMPLATE`.
- Role `AWSControlTowerBlueprintAccess`, com `AWSServiceCatalogAdminFullAccess` e `AmazonS3ReadOnlyAccess`.

A trust policy dessa role autoriza `AWSControlTowerAdmin` da própria management account e o ARN informado em `control_tower_operator_arn`. Informe o ARN IAM completo do usuário ou role que você usa para abrir o Account Factory; para Identity Center, inclua o caminho completo da role `AWSReservedSSO_...`. Não informe o ARN STS de uma sessão.

O Control Tower cria e compartilha o portfólio necessário durante o fluxo AFC; este root publica o produto e concede o acesso. O provider deve usar a management account e a Home Region da landing zone.

## Publicação

Para instalar o módulo S3, `terraform init` precisa de acesso Git de leitura ao repositório compartilhado. Configure as credenciais do Git se o repositório for privado.

O código da landing zone está presente, mas ainda faltam as roles de serviço exigidas pela criação via API. Os IDs reais das contas foram preenchidos no manifest em 12/11/2026. A role `AWSControlTowerAdmin` precisa existir antes de criar a trust policy de `AWSControlTowerBlueprintAccess`; ao implementar as roles, declare as dependências Terraform correspondentes. O bucket do backend também precisa existir antes do init: ele é diferente do bucket de templates criado aqui. O backend `environments/management-security/backend.hcl` aponta para `platform-lab-eks-terraform`, com chave `management-security/terraform.tfstate` e lockfile S3 habilitado.

Na raiz `terraform-management/`, copie e preencha o exemplo do operador:

```bash
cp environments/management-security/blueprints.tfvars.example environments/management-security/blueprints.tfvars
```

Confira o profile e a região em `management-security.tfvars`. Para um profile SSO, faça o login previamente. Depois:

```bash
export AWS_PROFILE=terraform-management
terraform -chdir=management-security init -reconfigure -backend-config=../environments/management-security/backend.hcl
terraform -chdir=management-security plan -var-file=../environments/management-security/management-security.tfvars -var-file=../environments/management-security/blueprints.tfvars
terraform -chdir=management-security apply -var-file=../environments/management-security/management-security.tfvars -var-file=../environments/management-security/blueprints.tfvars
terraform -chdir=management-security output
```

O profile do provider não configura a autenticação do backend; `AWS_PROFILE` no exemplo atende ao backend também. O apply inclui a landing zone e a publicação do blueprint; não cria contas de workloads nem aplica o template na management account. Conclua os pré-requisitos da landing zone antes de executar esses comandos. Se o permission set anteriormente declarado estiver no state, sua remoção da configuração fará o Terraform propor a exclusão dos recursos associados; confira o plan antes do apply.

## Uso no console

1. Abra Control Tower → Account Factory → Create account.
2. Informe os dados da conta e selecione uma OU registrada com a baseline do Control Tower habilitada.
3. Em Account factory customization, informe `blueprint_hub_account_id` como conta hub.
4. Escolha o produto `account-baseline` e a versão retornada em `blueprint_version`.
5. Preencha os parâmetros abaixo e escolha **Home Region**: o template contém recursos IAM globais e deve ser aplicado uma única vez por conta.
6. Crie a conta e acompanhe o provisionamento no Control Tower.

| Parâmetro do blueprint | Valor |
| --- | --- |
| `GitHubSubjects` | Subjects exatos, separados por vírgula; por exemplo `repo:OWNER/REPO:environment:dev`. Use o formato real do token, inclusive IDs imutáveis quando aplicável. |
| `GitHubRoleName` | Padrão `TerraformDeploy`. |
| `GitHubPolicyArns` | Policies existentes, separadas por vírgula. Padrão `arn:aws:iam::aws:policy/AdministratorAccess`, que concede administração ampla. |

Na nova conta, CloudFormation cria um bucket `terraform-state-<ACCOUNT_ID>-<REGION>`, com versionamento, SSE-S3 e os quatro bloqueios de acesso público; o provider OIDC do GitHub; e a role de deploy com as policies escolhidas. A trust policy exige audience STS e um dos subjects exatos. O template não contém validações customizadas.

Os outputs da stack na nova conta expõem `StateBucketName`, `GitHubRoleArn` e `GitHubOIDCProviderArn`. Use o bucket no backend do `live/` e o ARN da role em `AWS_ROLE_ARN` do GitHub Environment.

## SCPs e manutenção

Associe previamente suas SCPs à OU no Organizations. As contas ficam sujeitas às políticas da OU selecionada. O blueprint não cria SCPs e não concede exceções às políticas.

A versão do produto usa um hash do YAML: mudar o template altera a versão publicada no próximo apply. Isso não atualiza automaticamente as contas existentes; atualize o blueprint dessas contas pelo Control Tower. Este root não mantém um catálogo explícito de todas as versões históricas.

`bootstrap/main.tf` prepara a management no fluxo escolhido. `management-security/account-bootstrap/` permanece como alternativa, em estado separado. O [módulo `account_baseline`](https://github.com/igor-platform-lab/terraform-modules/tree/55c042f2753c907bf01cda102eea8a33756d2a39/modules/account_baseline) permanece reutilizável via Git; as contas criadas pelo Account Factory recebem os recursos pelo template. Não aplique ambos na mesma conta para criar os mesmos recursos. OIDC, role ou bucket preexistentes podem conflitar com o template.

O `10_controltower.tf` está ativo e lê `../landing-zone.json` com `file()`. Nenhuma migração de state foi feita. O `bootstrap/` original também declara bucket e OIDC na management; não duplique a gestão desses objetos no subdiretório `account-bootstrap/`.

Os recursos do blueprint são gerenciados pelo CloudFormation/AFC. Não foi definida retenção na exclusão da stack; remover o blueprint não é uma operação de simples publicação. O bucket versionado com objetos pode impedir a exclusão. Não há chave KMS personalizada, lifecycle de versões, integração Entra/Identity Center ou recursos EKS neste template.

Referências: [configuração do AFC](https://docs.aws.amazon.com/controltower/latest/userguide/afc-setup-steps.html), [role de acesso](https://docs.aws.amazon.com/controltower/latest/userguide/step-1-create-blueprint-access-role.html) e [seleção do blueprint no console](https://docs.aws.amazon.com/controltower/latest/userguide/create-afc-customized-account.html).

## Contrato do root

| Input | Tipo | Padrão/obrigatoriedade |
| --- | --- | --- |
| `aws_region` | `string` | `us-east-2`; deve corresponder à Home Region. |
| `aws_profile` | `string` | `null`; credenciais do ambiente quando não informado. |
| `environment` | `string` | `management-security`. |
| `environment_tags` | `map(string)` | `{}`; provider também define `Environment` e `ManagedBy`. |
| `control_tower_operator_arn` | `string` | Obrigatório; ARN IAM completo do operador do console. |

Outputs: `blueprint_hub_account_id`, `blueprint_product_id`, `blueprint_version` e `blueprint_access_role_arn`. Não há output da landing zone neste root. O `blueprint_version` usa `v-` seguido dos primeiros 12 caracteres do SHA-256 do template; o objeto S3 usa `account-baseline/<versão>.yaml`.

## Manifest e abrangência de segurança

`10_controltower.tf` está ativo com `version = "4.0"` e `manifest_json = file("${path.module}/../landing-zone.json")`. O caminho aponta para o JSON na raiz deste repositório, não para um arquivo dentro de `account-bootstrap/`.

O manifest governa `us-east-2`, habilita Identity Center, logging, Config e security roles; desabilita Backup. Audit é o destino de Config/security roles e Log Archive é o destino de logging. Os buckets de logs e access logs têm retenção configurada em 365 dias, sem chave KMS personalizada. Os IDs atuais são Log Archive `593400911863` e Audit `293521004133`, confirmados na AWS em 12/11/2026. As contas de integração precisam estar na mesma OU diretamente sob a raiz. Veja [manifest 4.0](https://docs.aws.amazon.com/controltower/latest/userguide/lz-api-launch.html).

As roles de serviço `AWSControlTowerAdmin`, `AWSControlTowerCloudTrailRole` e `AWSControlTowerStackSetRole`, no path `/service-role/`, não são declaradas aqui nem no bootstrap. O guia genérico também cita a role de agregação antiga, mas ela não é necessária para landing zone 4.0. Referências: [pré-requisitos via API](https://docs.aws.amazon.com/controltower/latest/userguide/lz-api-prereques.html) e [diferença da role de Config em 4.0](https://docs.aws.amazon.com/controltower/latest/userguide/roles-how.html).

Na versão 4.0, Config e CloudTrail usam recursos dedicados separados. No desenho deste manifest, Config fica na Audit e CloudTrail na Log Archive. A agregação não equivale a gravação habilitada em todas as contas: cobertura depende de baselines e OUs registradas. Referência: [AWS Config em 4.0](https://docs.aws.amazon.com/controltower/latest/userguide/config-updates-v4.html).

Não há um recurso separado de criação de contas do Account Factory neste fluxo: Terraform declara a landing zone e publica o produto; o provisionamento das contas usa o console. OUs do Organizations, registro no Control Tower, baseline do Control Tower e blueprint pessoal são conceitos distintos. Não existem SCPs customizadas, GuardDuty, Security Hub ou alertas centrais declarados neste root.

`accessManagement.enabled = true` não configura o Entra ID. A integração Entra por SAML/SCIM não é declarada no código e não foi confirmada nesta revisão. O root não declara permission sets nem assignments. OIDC do GitHub é autenticação de automação e não substitui o Identity Center de acesso humano.


## Histórico de SSO e permission sets

Atualização de 20/09/2026: o usuário informa que já possui SSO pelo IAM Identity Center. A instância existente é `arn:aws:sso:::instance/ssoins-66846c4ac9b86c19`; o módulo não a cria. Não foi feita consulta à AWS para verificar a implantação do permission set, os assignments ou o provedor externo de identidades.

A chamada `module.permission_set_adm`, anteriormente em `30_permission_set.tf`, foi removida da configuração. Ela declarava:

| Campo | Configuração atual |
| --- | --- |
| Nome | `administratorPermissionSet` — nome corrigido pelo usuário. |
| Policy | `arn:aws:iam::aws:policy/AdministratorAccess`. |
| Conta de destino | `965480031349`. |
| Identidade | Chave `admin_user`, tipo `USER`, ID `c15b6580-e0c1-7037-a2cd-b2593692644e`. |
| Sessão | Duas horas (`PT2H`), fixas no módulo. |
| Inline policy | Não informada; nenhum recurso de inline é criado. |

A configuração anterior declarava um permission set, uma associação de managed policy e uma atribuição de acesso. `AdministratorAccess` concede administração ampla, sujeita aos limites aplicáveis da organização. O nome precisa ter 1 a 32 caracteres e não aceita espaços; o valor anterior atende a esse formato. Referência: [CreatePermissionSet](https://docs.aws.amazon.com/singlesignon/latest/APIReference/API_CreatePermissionSet.html).

O módulo permite vários ARNs de policies gerenciadas pela AWS e uma inline JSON opcional; aceita ambos. Cada usuário ou grupo informado recebe acesso a todas as contas da chamada. IDs são do Identity Center, não IDs do Entra. O ARN da instância permanece fixo no módulo e o provider deve usar a região correspondente.

A validação entre variáveis exige Terraform >= 1.9. O módulo não exporta outputs, não cria identidades/contas e não configura federação SAML/SCIM ou acesso ao EKS. A presença do SSO não confirma esses componentes adicionais.

### Validação local em 20/09/2026

`terraform -chdir=management-security init -backend=false -input=false` concluiu usando o provider AWS `6.64.0` já instalado, conforme o lock file existente. `terraform -chdir=management-security validate -no-color` passou com Terraform `1.16.1`, incluindo o módulo `permission_set`. A inicialização não configurou o backend e não houve plan/apply ou consulta aos recursos AWS. A validação local não confirma que contas, identidades ou permissões estão corretas no serviço.

## Workflow deste repositório — 12/11/2026

`.github/workflows/terraform.yaml` executa exclusivamente `management-security/`, com Terraform `1.17.1`, na conta `058283627890` e região `us-east-2`. Não executa `bootstrap/` nem `account-bootstrap/`. Usa a role `TerraformManagement` via OIDC, com valores não sensíveis em repository Variables. O GitHub App fornece o token de leitura dos módulos privados. Não usa GitHub Environments.

Pull requests do próprio repositório para `main` executam init, fmt, validate e plan com sessão limitada à policy `ReadOnlyAccess`, sem lock de escrita no estado. PRs de forks não recebem acesso AWS. Push em `main` gera um plano novo e aplica exatamente esse plano no mesmo job. Não há artifact compartilhado entre PR e push; o plano do PR serve para revisão e não é o aplicado após o merge. Uma concurrency group única serializa as execuções deste root.

O workflow não carrega `.tfvars` locais ignorados pelo Git nem o profile `terraform-management`; usa as credenciais temporárias do runner e os defaults de região, ambiente e tags do provider. O operador do Account Factory é informado por `TF_VAR_control_tower_operator_arn`, alimentado pela variable `CONTROL_TOWER_OPERATOR_ARN = arn:aws:iam::058283627890:user/igor`, correspondente à identidade local consultada.

O estado da management usa S3 e uma chave diferente do estado local do bootstrap. O manifest já contém os IDs das contas de integração. Não houve apply da landing zone nesta adaptação.

### Bloqueios verificados nesta preparação

O repositório compartilhado `terraform-modules` é privado: o token automático de um repositório não fornece acesso de leitura ao outro. O usuário escolheu manter as origens remotas e reutilizar seu GitHub App. O workflow gera um token de instalação limitado a Contents: read em terraform-modules; depende da disponibilidade de RELEASE_APP_PRIVATE_KEY no repositório da management. A instalação local de `config-v0.1.0` falhou em `depends_on = var.organization`; o caller também usa argumentos diferentes dos declarados pelo módulo. A execução completa de validate/plan da management permanece bloqueada por essa implementação.

A consulta IAM na management não encontrou roles `AWSControlTower*`. As roles de serviço documentadas acima precisam ser providenciadas antes do apply da landing zone e do blueprint. A adaptação do workflow não as cria.

### Alternativa anterior: token pessoal para os módulos privados

Este procedimento registra a alternativa PAT preparada antes da escolha do GitHub App. O workflow atual usa o App, descrito na seção seguinte; não exige cadastrar MODULES_READ_TOKEN.

No GitHub pessoal, abra Settings → Developer settings → Personal access tokens → Fine-grained tokens e crie um token com resource owner `igor-platform-lab`, acesso somente ao repositório `terraform-modules` e permissão de repositório **Contents: Read-only**. Se a organização exigir aprovação, aguarde sua liberação. Escolha uma expiração e substitua o secret quando renovar o token. Referência: [gerenciar personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

No repositório `igor-platform-lab/terraform-management`, abra Settings → Secrets and variables → Actions → New repository secret. Use o nome `MODULES_READ_TOKEN` e cole o token no campo Secret. Na alternativa PAT, esse era o secret exigido para leitura dos módulos; o contrato atual do GitHub App está abaixo. O token é para leitura dos módulos no GitHub; AWS continua usando OIDC.

Na alternativa PAT, o passo de init falhava com uma mensagem explícita se o secret estivesse ausente. A autorização Git fica em variáveis de ambiente limitadas ao processo de init, com header restrito à URL de `terraform-modules.git`; não é gravada na configuração Git. O checkout não persiste credenciais. O token real e a execução remota não foram testados nesta preparação. Os bloqueios do módulo Config e das roles Control Tower permanecem independentes desse acesso.

### GitHub App e valores cadastrados no repositório

O workflow atual usa actions/create-github-app-token v3 com a mesma revisão fixa do workflow de releases. Solicita token somente para terraform-modules, na organização igor-platform-lab, com Contents: read. O token gerado alimenta o init; não é um secret manual nem uma credencial AWS. O App precisa estar instalado com acesso ao repositório de módulos.

As repository Variables abaixo foram cadastradas e relidas pela API em 12/11/2026:

| Variable | Valor |
| --- | --- |
| RELEASE_APP_CLIENT_ID | 5519180, reutilizado da configuração de releases |
| AWS_REGION | us-east-2 |
| AWS_ACCOUNT_ID | 058283627890 |
| AWS_ROLE_ARN | arn:aws:iam::058283627890:role/TerraformManagement |
| TERRAFORM_VERSION | 1.17.1 |
| CONTROL_TOWER_OPERATOR_ARN | arn:aws:iam::058283627890:user/igor |
| BACKEND_CONFIG | ../environments/management-security/backend.hcl |

O único secret exigido é RELEASE_APP_PRIVATE_KEY. Cadastre a chave privada do App em Settings → Secrets and variables → Actions → New repository secret de terraform-management. A captura fornecida pelo usuário confirma que o plano atual da organização permite organization secrets somente em repositórios públicos; terraform-management é privado, portanto o organization secret criado não está disponível para este workflow. O uso compartilhado por organization secret exigiria um plano que ofereça acesso a repositórios privados. O valor de um secret já existente em terraform-modules não pode ser lido e copiado pela API. Nenhum placeholder foi cadastrado como credencial.

Foram validados YAML, scripts Bash e a limitação do token ao repositório de módulos com leitura. A chave privada não foi lida, transferida nem testada; a execução remota permanece pendente. Esta etapa não mudou roles, policies ou confiança OIDC na AWS. A discussão sobre separar as roles de PR e apply permanece pendente e não foi resolvida pelo cadastro das Variables.

### Preparação do PR — 12/11/2026

A entrega reúne o workflow da management, a autenticação de leitura dos módulos por GitHub App, os IDs reais das contas e o backend existente. Os planos binários e os estados locais ficam fora do commit. O secret de organização informado pelo usuário não atende ao repositório privado no plano atual; é necessário cadastrar RELEASE_APP_PRIVATE_KEY como repository secret antes de executar o workflow.

A entrega ainda exige revisão antes de merge: a role administrativa aceita o subject de PR, com limitação ReadOnlyAccess solicitada apenas pelo workflow. O módulo Config bloqueia o init/validate da management, e faltam as roles do Control Tower para aplicar a landing zone. O PR documenta essas pendências e não representa confirmação de CI ou implantação. Nenhuma correção desses pontos foi incluída durante a preparação do commit.
