# Migraweb

Este projeto contém um script responsável por realizar a migração e
recriação de contas/VHosts de servidores compartilhados.

## Preparando a execução

O script se baseia na chamada de APIs, portanto, é necessário dar
permissão de execução nas seguintes APIs para o servidor de origem:

- WTD2_ServerInfo
- WTD2_AccountInfo
- DNS_ExcluirRR
- DNS_IsZona
- WTD2_Recreate
- WTD2_Migrate
- WTD2_ServerInfo
- DNS_ReplaceHost
- WTD2_MigrateVHost
- WTD2_AccountsToMigrate
- WTD2_UpdateAccountInfo
- WTD2_Recreate
- WTD2_GetHostIDs
- WTD2_UpdateVHostInfo
- WTD2_UpdateAccountInfoK8
- WTD2_ChangeWSS
- WTD2_ServerInfo
- CGL_DnsRREditar

## Permitir ssh com root

Para conectar do ssh no host de destino, cole o comando abaixo trocando "SERVIDOR_DESTINO" pelo nome do servidor web verdadeiro de destino.

- SERVIDOR DE ORIGEM
```sh
ssh-keygen -t rsa -q -f "/root/.ssh/id_rsa" -N "" >/dev/null <<<y; 
scp /root/.ssh/id_rsa.pub $USER@SERVIDOR_DESTINO.prv.f1.k8.com.br
```

Coloque sua senha e logue no servidor destino para rodar o comando abaixo:

- SERVIDOR DE DESTINO
```sh
cat id_rsa.pub >> /root/.ssh/authorized_keys;
sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config;
service ssh reload;
```

feito isso, tente usar o comando scp com usuário root pelo servidor de origem como teste.

## Preparando servidor de destino

Precisa parar o webtodo para que ele não realize mudanças fora de hora e parar o puppet para não sobrescrever o arquivo.

- SERVIDOR DE DESTINO
```
sed -i -e 's/^/#/' /etc/cron.d/webtodo
puppet agent --disable "Parando webtodo"
```

## Listando contas do servidor

Use o script getaccounts.rb para listar as contas do servidor. 
Se estiver executando de dentro do servidor, basta executar o script sem parâmetros, caso contrário, faça da forma abaixo:

- SERVIDOR DE ORIGEM
```ruby
ruby getaccounts.rb [<Servidor web de origem>] > [<arquivo de contas>]
Exemplo: ruby getaccounts.rb web120 > contas
```
### Atenção, se der erro pela falta do mysql2, basta usar o comando apt install ruby-mysql2

## Migrando clientes

É possível simular a execução alterando o valor da constante ***EXECUTE***
para **false**, assim, somente serão impressas as chamadas de API junto
com os argumentos passados.

- SERVIDOR DE ORIGEM
```ruby
EXECUTE = false #Somente imprime chamadas das APIs
  # OU
EXECUTE = true #Roda o script e executa as alterações
```

É necessário informar o servidor de origem e o servidor de destino.
Os valores são armazenadas nas variáveis SERVER e NEW_SERVER:

- SERVIDOR DE ORIGEM
```ruby
SERVER = 'webXXX.f1.k8.com.br' # ORIGEM
NEW_SERVER = 'webXXX.f1.k8.com.br' # DESTINO
```
## Sincronizando homes e certificados

Antes de migrar é preciso que os arquivos e o certificado do cliente já existam no destino.
Para isso basta rodar o script abaixo com a lista de contas:

- SERVIDOR DE ORIGEM
```sh
 sh rsync.sh [<arquivo de contas>] [<servidor web de destino>]
 Exemplo: sh rsync.sh contas web120
```

## Executando o script

Para executar o script é necessário informar um arquivo contendo
uma lista contas a serem migradas.

- SERVIDOR DE ORIGEM
```ruby
 ruby migraweb.rb [<arquivo de contas>]
 Exemplo: ruby migraweb.rb contas
```

O script mantém um log de eventos em arquivo chamado ***log***,
mas também imprime na tela. Um arquivo chamado ***last*** contém
a última conta a ser migrada, o que permite que a execução continue
de onde parou em caso de erros.

> **Nota:**

> - O DNS também é alterado: registros que apontem para o servidor
de origem  são alterados para o servidor de destino
> - O mesmo ocorre com os registros que apontem para o WSS de
origem: são alterados para o WSS de destino.

## Revertendo a migração

O script permite a reversão se necessário da migração. Para isso, basta realizar
a seguinte alteração:

- SERVIDOR DE ORIGEM
```ruby
REVERT = true
```

Caso ***REVERT*** seja ***true***, a migração de IDs relacionados
ao servidor será desfeita para as contas listadas, fazendo com que
o banco ***web*** permaneça no estado anterior ao início da migração.

## Finalizando migração

Para aplicar as mudanças, precisamos executar o webtodo e realizer um restart no apache e php.

- SERVIDOR DE DESTINO
```sh
webtodo;
service apache2 restart;
service php* restart;
```

## Desativando homes antigas

Após a migração o correto é que a home do cliente se torne inacessível para
evitar que ocorra escrita no servidor migrado. Para isso basta executar o script
abaixo com a lista de contas migradas.

- SERVIDOR DE ORIGEM
```sh
 sh home_delete.sh [<Arquivo de contas>]
 Exemplo: sh home_delete.sh contas
```

## Devolvendo servidor para produção

Agora com as contas migradas, basta apenas rodar o puppet e certificar que está funcionando.

- SERVIDOR DE DESTINO
```sh
 puppet agent --enable;
 puppet agent --test
```

## Realizando backup mensal

Isso pode servir apenas como aviso, se migrou um servidor com muitos clientes para o novo, vale a penas realizar um backup mensal.

- SERVIDOR DE DESTINO
```sh
echo "$(date --date='now + 1 minutes' +"%M %I") * * * root nice -n19 /usr/sbin/houelleback backup host filesystem --monthly" > /etc/cron.d/houelleback
```
