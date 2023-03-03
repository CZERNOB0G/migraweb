# Migraweb

Este projeto contém um script responsável por realizar a migração e
recriação de contas/VHosts de servidores compartilhados.

## Preparando a execução

O script se baseia na chamada de APIs, portanto, é necessário dar
permissão de execução nas seguintes APIs para o servidor de origem:

- DNS_ExcluirRR
- DNS_IsZona
- DNS_ReplaceHost
- WTD2_AccountInfo
- WTD2_Migrate
- WTD2_Recreate
- WTD2_ServerInfo

## Passo 1 - Preparando servidor de destino

Precisa parar o webtodo para que ele não realize mudanças fora de hora e parar o puppet para não sobrescrever o arquivo:

- SERVIDOR DE DESTINO
```
sed -i -e 's/^/#/' /etc/cron.d/webtodo;
puppet agent --disable "Parando webtodo";
```

## Passo 2 - Permitir ssh com root

Para conectar do ssh no host de destino, cole o comando abaixo trocando `SERVIDOR_DESTINO` pelo nome do servidor web verdadeiro de destino:

- SERVIDOR DE ORIGEM
```sh
[ ! -e "/root/.ssh/id_rsa.pub" -o ! -e "/root/.ssh/id_rsa" ] && ssh-keygen -t rsa -q -f "/root/.ssh/id_rsa" -N "" >/dev/null <<<y; 
scp /root/.ssh/id_rsa.pub $USER@SERVIDOR_DESTINO.prv.f1.k8.com.br:
```

Logue no servidor destino para rodar o comando abaixo:

- SERVIDOR DE DESTINO
```sh
cat id_rsa.pub >> /root/.ssh/authorized_keys;
sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config;
service ssh reload;
```

feito isso, tente usar o comando scp com usuário root pelo servidor de origem como teste.

# Passo 3 - Sincronizando homes antes da migração

Para que o webtodo não fique parado por muito tempo, é importante adiantar a migração das homes para quando for feita a migração oficial ter poucos arquivos para sincronizar:

- SERVIDOR DE ORIGEM
```sh
ruby migraweb.rb -q QUANTIDADE -o web_ORIGEM -d web_Destino --rsync-only
```

Assim ele realizará apenas a sincronização das homes existentes.

## Passo 4 - Migrando clientes

Para migrar os clientes do servidor de origem, basta definir uma quantidade de contas (lote) que deseja migrar, o servidor de origem e destino usando o migraweb.rb.

Como boa prática, teste o script com a opção `--noop` sem valores associados para verificar se está tudo correto:

- SERVIDOR DE ORIGEM
```sh
ruby migraweb.rb -q QUANTIDADE -o web_ORIGEM -d web_Destino --noop
```

Desse modo ele apenas printa na tela o que será feito, confirmado esse procedimento pode iniciar a migração:

- SERVIDOR DE ORIGEM
```sh
ruby migraweb.rb -q QUANTIDADE -o web_ORIGEM -d web_Destino
```

O script com esses parametrôs de exemplo migrará a home, vhost, dns e o certificado do apache dos primeiros clientes que forem encontrados no banco.

> **Nota:**

> - O script mostra a saída do que está sendo feito na tela, mas se necessário pode ser consultado o arquivo ./migraweb.log
> - Depois da migração as homes são movidas para a pasta /home/_trash/.
> - O script realiza a sincronização das homes ao final da migração antes de mover-las, por isso só precisa fazer antes. 


## Passo 5 - Finalizando migração

Para aplicar as mudanças, precisamos executar o webtodo, realizer um restart no `apache` e todas as instâncias do `php-fpm`.

- SERVIDOR DE DESTINO
```sh
webtodo;
service apache2 restart;
service php* restart;
```

## Passo 6 - Devolvendo servidor para produção

Agora com as contas migradas, basta apenas rodar o puppet e certificar que está tudo funcionando:

- SERVIDOR DE DESTINO
```sh
puppet agent --enable;
puppet agent --test;
```

## Realizando backup mensal

Isso pode variar de acordo com a ocasião, mas se foi migrado um servidor com muitos clientes para o novo, vale a penas realizar um backup mensal para não impactar o diário:

- SERVIDOR DE DESTINO
```sh
echo "$(date --date='now + 1 minutes' +"%M %I") * * * root nice -n19 /usr/sbin/houelleback backup host filesystem --monthly" > /etc/cron.d/houelleback
```

## Opções adicionais do script

```
migraweb.rb ((-q <quantity>) or (-a <account> | -f <file>)) -o <origin> -d <destiny> <options>
  migraweb.rb (-h | --help)
    -h, --help                       Exibe esse help
    -q QUANTITY                      Define uma quantidade de clientes a serem migrados a partir do banco
    -f FILE                          Migra as contas listadas no arquivo
    -o ORIGIN                        Define o servidor de origem
    -d DESTINY                       Define o servidor de destino
    -av FILE                         Pula os clientes presentes no arquivo
    -b, --back                       Inverte a migração do destino para a origem
    -n, --noop                       Apenas mostra o que será migrado sem migrar
    -r, --rsync-only                 Realiza apenas o rsync das homes
```
