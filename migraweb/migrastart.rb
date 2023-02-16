require 'pp'
require 'optparse'
require 'mysql2'
require 'logger'
require 'open4'

require_relative 'require/api'
require_relative 'require/utils'
require_relative 'require/rsync'
require_relative 'require/getaccounts'

# Define as opções com o OptionParser
options = {}
OptionParser.new do |opts|
  opts.banner = <<-USAGE
Usage:
  migrastart.rb ((-q <quantity>) or (-a <account> | -f <file>)) -o <origin> -d <destiny> <options>
  migrastart.rb (-h | --help)
  USAGE

  opts.on('-h', '--help', 'Exibe esse help') do
    puts opts
    exit(2)
  end

  opts.on('-q QUANTITY', Integer, 'Define uma quantidade de clientes a serem migrados a partir do banco') do |quantity|
    options[:quantity] = quantity
  end

  opts.on('-a ACCOUNT', 'Migra apenas a conta informada') do |account|
    options[:account] = account
  end

  opts.on('-f FILE', 'Migra as contas listadas no arquivo') do |file|
    options[:file] = file
  end

  opts.on('-o ORIGIN', 'Define o servidor de origem') do |origin|
    options[:origin] = origin
  end

  opts.on('-d DESTINY', 'Define o servidor de destino') do |destiny|
    options[:destiny] = destiny
  end

  opts.on('-av FILE', 'Pula os clientes citados') do |avoid|
    options[:avoid] = true
  end

  opts.on('-r', '--rsync', 'Realize o rsync da apenas da conta ou lista de contas') do
    options[:resync] = true
  end

  opts.on('-b', '--back', 'Realiza a migração reversa') do
    options[:back] = true
  end

  opts.on('-n', '--noop', 'Apenas mostra o que será migrado sem migrar') do
    options[:noop] = true
  end

end.parse!

# Valida as opções recebidas
def validate_options(options)
  if options[:quantity].nil? && options[:account].nil? && options[:file].nil?
    puts "Either '-q' or '-a' or '-f' should be provided"
    exit(1)
  end

  if options[:quantity] && !options[:quantity].is_a?(Integer)
    puts "The -q flag must be an integer"
    exit(1)
  end

  if ((options[:quantity] && (options[:account] || options[:file])) || (options[:resync] && options[:back]) || (options[:account] && options[:file]))
    puts 'Some flag must be provided. Flags should be provided separately.'
    exit(1)
  end

  if options[:destiny] == options[:origin]
    puts 'The origin and destination cannot be the same'
    exit(1)
  end

  unless options[:destiny]
    puts 'Destination server should be provided'
    exit(1)
  end

  unless options[:origin]
    puts 'Origin server should be provided'
    exit(1)
  end
end

validate_options(options)

# Configurações de execução
EXECUTE = options[:noop].nil? ? true : options[:noop]

# Servidores
ORIGIN_SERVER = options[:origin]
NEW_SERVER = ORIGIN_SERVER.nil? ? nil : "#{ORIGIN_SERVER}.f1.k8.com.br"
NEW_SERVER_PRV = ORIGIN_SERVER.nil? ? nil : "#{ORIGIN_SERVER}.prv.f1.k8.com.br"

# Reverter migração?
REVERT = options[:back] || false

# Capturar servidores WSS para migração DNS da CDN
original_wss_server = API.server_info(ORIGIN_SERVER)['wss'] unless ORIGIN_SERVER.nil?
new_wss_server = API.server_info(NEW_SERVER)['wss'] unless NEW_SERVER.nil?

# Contas a serem migradas
accounts = if options[:quantity]
             Accounts.get_accounts(ORIGIN_SERVER, options[:quantity])
           elsif options[:file]
             Utils.read_file(options[:file])
           else
             [options[:account]].flatten.compact
           end

# Evitar contas específicas, se necessário
avoid = Utils.get_avoid(options[:avoid])

accounts.each do |account|
  next if account <= avoid

  begin
    # Lista os VHosts a serem migrados
    Utils.log "[#{account}][migration][INFO] Iniciando migração"
    account_info = API.account_info(account)

    if REVERT
      vhost_list = API.list_vhost(account_info, NEW_SERVER)
      # Revertendo migração
      Utils.log "[#{account}][migration][INFO] Reverting migration VHost from #{NEW_SERVER} to #{SERVER}"
      Utils.log API.migrate(account, NEW_SERVER, SERVER)
    else
      # Migra as homes
      Rsync.rsync_home(account, "#{NEW_SERVER_PRV}:/home/", EXECUTE) if options[:rsync] || options[:quantity]
      vhost_list = list_vhost(account_info, SERVER)
      Utils.log "[#{account}][migration][INFO] Migrating VHost from #{SERVER} to #{NEW_SERVER}"
      # Migrando IDs (incluindo servidor, templates) - PHPVersion
      Utils.log API.migrate(account, SERVER, NEW_SERVER)

      if vhost_list.values.include?true
        Utils.log "[#{account}][migration][INFO] Recriating VHost in #{NEW_SERVER}"
        # Enviando ações de criação de Home, CGroup, VHosts etc
        Utils.log API.recreate(account, NEW_SERVER)
      else
        Utils.log "[#{account}][migration][WARN] There are no active VHosts - Home/VHosts creation will be done during restoration"
      end
    end

    # Para cada VHost, alterar o DNS da zona que aponta para o servidor e wss
    vhost_list.each do |domain, active|
      Utils.log "[#{account}][DNS][WARN] VHost #{domain} inative" if !active
      Utils.log "[#{account}][DNS][INFO] Start DNS migration of domain #{domain}"
      if REVERT
        Utils.log "[#{account}][DNS][INFO] Revert migrating domain from #{NEW_SERVER} to #{SERVER}"
        Utils.log API.replace_host(domain, NEW_SERVER, SERVER)
        Utils.log "[#{account}][DNS][INFO] Revert migrating WSS from #{new_wss_server} to #{original_wss_server}"
        Utils.log API.replace_host(domain, new_wss_server, original_wss_server) if new_wss_server and original_wss_server
      else
        Rsync.rsync_cert(domain, "#{NEW_SERVER_PRV}:/var/lib/apache2/md/domains/", account) if options[:rsync] || options[:rsync]
        Utils.log "[#{account}][DNS][INFO] Migrating domain from #{SERVER} to #{NEW_SERVER}"
        Utils.log API.replace_host(domain, SERVER, NEW_SERVER)
        Utils.log "[#{account}][DNS][INFO] Migrating WSS from #{original_wss_server} to #{new_wss_server}"
        Utils.log API.replace_host(domain, original_wss_server, new_wss_server) if new_wss_server and original_wss_server
      end
      Utils.log "[#{account}][DNS][INFO] Done DNS migration of domain #{domain}"
    end

    Utils.log "[#{account}][migration][INFO] Done migrating\n\n"
  rescue Digirati::API::CommandError => e
    Utils.log "[#{account}][migration][ERROR] #{e.message}"
    raise
  end
end