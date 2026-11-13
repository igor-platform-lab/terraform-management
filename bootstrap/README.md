# Bootstrap inicial da management account

O fluxo escolhido usa [main.tf](main.tf) para preparar a management account antes da landing zone. Executar Terraform neste diretório carrega todos os seus arquivos `.tf`; `main.tf` não é executado isoladamente. Esta documentação descreve o código em 13/09/2026, sem afirmar que os recursos já existem na AWS.

## Por onde começar se nenhuma conta existe

O Terraform precisa de uma conta AWS e de credenciais antes de criar qualquer recurso. Primeiro crie uma conta AWS para ser a futura **management account** e configure acesso administrativo inicial seguro. Não é necessário ter IAM Identity Center para iniciar. Confirme a identidade e o ID com `aws sts get-caller-identity --profile terraform-management`; o comando não cria recursos.

A ordem pretendida depois da criação da management account é:

1. **`bootstrap/`**: usando credenciais da management, criar Organizations, OUs, contas Audit e Log Archive, bucket de state e acesso OIDC do GitHub. O backend deste root começa local.
2. **Preparação da landing zone**: obter os IDs das contas criadas, preencher o manifest e o backend S3 do próximo root e providenciar os pré-requisitos ainda ausentes descritos adiante.
3. **`management-security/`**: inicializar seu backend S3 separado e, quando os pré-requisitos estiverem resolvidos, criar a landing zone e publicar o blueprint do Account Factory.
4. **Account Factory**: registrar e preparar as OUs necessárias no Control Tower e criar as contas de workloads pelo console, selecionando o blueprint. Elas recebem bucket e acesso GitHub pelo CloudFormation.

`management-security/account-bootstrap/` **não é o passo 2**. É um root alternativo, com state próprio, que prepara somente bucket e acesso GitHub em uma conta existente; não cria a organização nem as contas Audit e Log Archive. No fluxo escolhido, não o execute junto com `bootstrap/` na management para criar os mesmos objetos. Veja [a comparação e o uso independente](../management-security/account-bootstrap/README.md).

### O que impede a execução imediata

- `landing-zone.json` ainda contém placeholders para IDs das contas Audit e Log Archive. As roles de serviço do Control Tower necessárias para criação via API não são declaradas aqui. A role `AWSControlTowerAdmin` precisa existir antes da trust policy do blueprint; a dependência correspondente também precisa ser resolvida. Os detalhes estão no [guia da management](../management-security/README.md).
- O backend da management ainda usa o placeholder `meu-bucket-tfstate`. O exemplo do operador do blueprint também precisa ser preenchido. A landing zone e o blueprint estão no mesmo root: não presuma que executar esse root por etapas resolverá as dependências ausentes.
- O `bootstrap/` assume que os objetos declarados não estão em conflito com recursos existentes. Se houver organização, OIDC, bucket ou outros recursos preexistentes, avalie importação e propriedade antes de aplicar. Uma conta nova não impede conflitos de nomes globais de bucket.

Estes itens descrevem trabalho pendente. A implantação na AWS ainda precisa ser verificada.

## Origem do módulo S3

O bootstrap usa [`modules/s3`](https://github.com/igor-platform-lab/terraform-modules/tree/55c042f2753c907bf01cda102eea8a33756d2a39/modules/s3) do repositório compartilhado, com revisão fixa em `source`. Configure credenciais Git de leitura antes do `terraform init` se o repositório for privado. Use as credenciais AWS da management para provisionar os recursos.

## Recursos e responsabilidade

| Declaração | Comportamento |
| --- | --- |
| `module.s3_terraform_state` | Bucket de estado, versionado, SSE-S3 e quatro bloqueios de acesso público. |
| `aws_iam_openid_connect_provider.github` | OIDC do GitHub, audience `sts.amazonaws.com`, thumbprint fixo no código. |
| `aws_iam_role.github_actions` | Role `TerraformManagement`, com `AdministratorAccess`. |
| `aws_organizations_organization.org` | Organizations com todas as funcionalidades; tipos SCP e Tag Policy habilitados e trusted access para Control Tower. |
| `aws_organizations_organizational_unit.workloads` | OU `Workloads` diretamente sob a raiz. |
| `aws_organizations_organizational_unit.security` | OU com nome real `LogArchive`, diretamente sob a raiz. O identificador Terraform `security` não é o nome exibido no console. |
| `audit_account` e `log_archive_account` | Contas `Audit` e `Log Archive`, ambas na OU `LogArchive`. |

Habilitar os tipos SCP/Tag Policy não cria políticas personalizadas nem attachments. Criar uma OU no Organizations não a registra automaticamente no Control Tower. Este root não cria a landing zone, as roles de serviço do Control Tower ou o blueprint AFC.

## Inputs

Todos estão em [variables.tf](variables.tf).

| Nome | Tipo | Obrigatório | Uso/padrão |
| --- | --- | --- | --- |
| `aws_region` | `string` | sim | Região da preparação; o desenho atual usa `us-east-2`. |
| `aws_profile` | `string` | sim | Profile com acesso à management. |
| `state_bucket_name` | `string` | sim | Nome globalmente único do bucket. |
| `github_repository` | `string` | sim | Repositório no formato `OWNER/REPO`. |
| `github_branch` | `string` | não | Branch autorizada quando `github_subjects` está vazio; padrão `main`. |
| `github_subjects` | `list(string)` | não | Subjects exatos; padrão `[]`, que usa repository/branch. Aceita IDs imutáveis do GitHub. |
| `audit_account_email` | `string` | sim | E-mail exclusivo para a conta Audit. |
| `log_archive_account_email` | `string` | sim | E-mail exclusivo para a conta Log Archive. |
| `localstack_enabled` | `bool` | não | Padrão `false`; deve permanecer falso no fluxo AWS escolhido. |
| `localstack_endpoint` | `string` | não | Referência legada; padrão `http://localhost:4566`. |

## Execução e estado

Pré-requisitos: credenciais da management, permissões de S3/IAM/Organizations, e-mails disponíveis e configuração correspondente aos recursos já existentes. Caso a organização ou o OIDC já exista, o estado precisa representá-los antes de uma tentativa de criação. Este root não adota objetos existentes automaticamente.

Exemplo de conteúdo para `bootstrap/bootstrap.tfvars` local, sem credenciais estáticas:

```hcl
aws_region                = "us-east-2"
aws_profile               = "terraform-management"
state_bucket_name         = "terraform-state-<MANAGEMENT_ACCOUNT_ID>-us-east-2"
github_repository         = "<OWNER>/<REPO>"
github_branch             = "main"
audit_account_email       = "<EMAIL_AUDIT>"
log_archive_account_email = "<EMAIL_LOG_ARCHIVE>"
localstack_enabled        = false
```

A partir da raiz deste repositório, depois de configurar o acesso Git e preencher os valores reais:

```bash
export AWS_PROFILE=terraform-management
terraform -chdir=bootstrap init
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan -var-file=bootstrap.tfvars -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
```

`bootstrap.tfvars` não é carregado automaticamente pelo nome; o comando o informa explicitamente. Confira a conta retornada pelo STS, gere um plan novo, revise todos os recursos e só então aplique esse arquivo. Não reutilize um `bootstrap.tfplan` antigo. Para profile SSO, o login deve estar válido antes da execução. O provider não fixa uma versão do AWS provider neste root; o lockfile registra a versão selecionada.

O backend atual é local implícito (`bootstrap/terraform.tfstate`). Criar um bucket não migra o próprio estado. Preserve estado e backup fora do Git, pois este estado também controla a organização e as contas compartilhadas. Não reutilize esse estado para `management-security/` ou `live/`.

O root não declara outputs. Após uma aplicação bem-sucedida, os IDs de Audit e Log Archive podem ser consultados no Organizations ou no estado:

```bash
terraform -chdir=bootstrap state show aws_organizations_account.audit_account
terraform -chdir=bootstrap state show aws_organizations_account.log_archive_account
```

Os IDs de 12 dígitos alimentam [landing-zone.json](../landing-zone.json): Log Archive em `centralizedLogging.accountId`; Audit em `config.accountId` e `securityRoles.accountId`. O nome do bucket alimenta [o backend da management](../environments/management-security/backend.hcl), cuja chave é `management-security/terraform.tfstate`. Esse backend autentica independentemente do provider.

Uma eventual migração do próprio estado exige declarar o backend S3 e usar uma chave exclusiva, como `bootstrap/terraform.tfstate`, com backup e `terraform init -migrate-state`. Isso não foi implementado nem executado. `-reconfigure` não substitui migração de estado. Referência: [inicialização e migração de backend](https://developer.hashicorp.com/terraform/cli/commands/init#backend-initialization).

## Acesso GitHub e limites atuais

A trust policy da role `TerraformManagement` exige audience STS e um subject exato, comparado por `StringEquals`. Sem `github_subjects`, usa `repo:OWNER/REPO:ref:refs/heads/BRANCH`. A configuração local vigente informa os subjects imutáveis de `igor-platform-lab/terraform-management` para `main` e pull requests; o workflow da management não usa GitHub Environment. Jobs com Environment exigiriam subjects diferentes. O bootstrap fixa um thumbprint, enquanto `account_baseline` e o blueprint não o fixam. As permissões administrativas são explícitas no código.

O atributo `aws_service_access_principals` declara apenas Control Tower. Integrações posteriores podem habilitar outros serviços no Organizations; a gestão dessa lista precisa ser coerente com esses serviços para evitar que uma reaplicação remova trusted access. Referência: [Organizations no provider AWS](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization).

LocalStack saiu do plano do projeto, mas suas opções permanecem no código. Os endpoints alternativos declarados aqui cobrem IAM/S3/STS, não Organizations.

[management-security/account-bootstrap](../management-security/account-bootstrap/README.md) é uma alternativa preservada, fora do fluxo escolhido. Não execute os dois roots para gerir o mesmo bucket/OIDC. Nas novas contas de workloads, o dono dos recursos equivalentes é CloudFormation por meio do [blueprint AFC](../management-security/README.md).

## Implantação confirmada — 12/11/2026

O bootstrap está registrado no estado local com 12 recursos na management `058283627890`, organização `o-1lrm5qsjpv`, bucket `platform-lab-eks-terraform`, Audit `293521004133` e Log Archive `593400911863`. As duas contas foram consultadas na AWS como `ACTIVE`. Após perda do estado, 11 recursos existentes foram importados; a Audit foi criada depois pelo usuário. O estado ativo continua em `terraform.tfstate`, separado do backend S3 da management.

A role `TerraformManagement` teve somente sua trust policy atualizada por Terraform para o novo repositório e os subjects imutáveis, sem recriação dos recursos. A configuração local usa:

```hcl
github_repository = "igor-platform-lab/terraform-management"
github_subjects = [
  "repo:igor-platform-lab@331069808/terraform-management@1382391570:ref:refs/heads/main",
  "repo:igor-platform-lab@331069808/terraform-management@1382391570:pull_request",
]
```

O prefixo e a opção de subjects imutáveis foram consultados na API do GitHub. A aplicação da trust policy foi confirmada; a autenticação em uma execução remota do workflow ainda não foi demonstrada.
