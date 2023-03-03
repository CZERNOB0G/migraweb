require 'pp'
require 'optparse'
require 'mysql2'
require 'fileutils'
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

  opts.on('-qQUANTITY', Integer, 'Define uma quantidade de clientes a serem migrados a partir do banco') do |quantity|
    options[:quantity] = quantity
  end

  opts.on('-aACCOUNT', String, 'Migra apenas a conta informada') do |account|
    options[:account] = account
  end

  opts.on('-fFILE', 'Migra as contas listadas no arquivo') do |file|
    options[:file] = file
  end

  opts.on('-oORIGIN', 'Define o servidor de origem') do |origin|
    options[:origin] = origin
  end

  opts.on('-dDESTINY', 'Define o servidor de destino') do |destiny|
    options[:destiny] = destiny
  end

  opts.on('-vFILE', 'Pula os clientes citados') do |avoid|
    options[:avoid] = avoid
  end

  opts.on('-b', '--back', 'Realiza a migração reversa') do
    options[:back] = true
  end

  opts.on('-n', '--noop', 'Apenas mostra o que será migrado sem migrar') do
    options[:noop] = true
  end

  opts.on('-r', '--rsync-only', 'Realiza apenas o rsync das homes') do
    options[:rsync] = true
  end

end.parse!

if options.empty?
  puts "migrastart.rb (-h | --help)"
  exit
end

# Valida as opções recebidas
def validate_options(options)
  if options[:quantity] && options[:account]
    puts "Flags '-q' and '-a' should be provided separately."
    exit(1)
  elsif options[:account] && options[:file]
    puts "Flags '-a' and '-f' should be provided separately."
    exit(1)
  elsif options[:quantity] && options[:file]
    puts "Flags '-q' and '-f' should be provided separately."
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

  if (options[:origin] =~ /(web\d+)\..+/ || options[:destiny] =~ /(web\d+)\..+/) 
    puts 'Origin and destiny server should be a webXXX'
    exit(1)
  end

  if options[:rsync] && options[:back]
    puts "Flags '-r' and '-b' should be provided separately."
    exit(1)
  elsif options[:rsync] && options[:noop]
    puts "Flags '-r' and '-n' should be provided separately."
    exit(1)
  end

end

validate_options(options)

# Configurações de execução
EXECUTE = options[:noop] ? false : true
# Servidores
ORIGIN_SERVER = "#{options[:origin]}.f1.k8.com.br" if options[:origin]
NEW_SERVER = "#{options[:destiny]}.f1.k8.com.br" if options[:destiny]
NEW_SERVER_PRV = "#{options[:destiny]}.prv.f1.k8.com.br" if options[:destiny]

# Reverter migração?
REVERT = options[:back] ? true : false

trash_dir = '/home/_trash'

# Capturar servidores WSS para migração DNS da CDN
original_wss_server = API.server_info(ORIGIN_SERVER)['wss'] unless ORIGIN_SERVER.nil?
new_wss_server = API.server_info(NEW_SERVER)['wss'] unless NEW_SERVER.nil?

# Contas a serem migradas
accounts = []
if options[:quantity]
  accounts = Accounts.get_accounts(options[:origin].to_s, options[:quantity].to_i)
elsif options[:file]
  accounts = Utils.read_file(options[:file].to_s) unless Utils.read_file(options[:file]).nil?
else
  accounts << options[:account]
end

# Evitar contas específicas, se necessário

accounts.each do |account, index|
  account_dir = "/home/#{account}/"
  if options[:avoid]
    if Utils.get_avoid(options[:avoid].to_s, account)
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Skipping client"
      next
    end
  end
  if options[:rsync]
    unless Rsync.test_rsync("/home/#{account}","#{NEW_SERVER_PRV}:/home/",account)
      next
    end
    Utils.log "[#{account}][rsync][\e[32mINFO\e[0m] Start migration home only"
    if File.directory?(account_dir) && account_dir != '/home//'
      Rsync.rsync_home(account, "#{NEW_SERVER_PRV}:/home/")
    else 
      Utils.log "[#{account}][rsync][\e[33mWARN\e[0m] Home #{account_dir} not exist"
    end
    Utils.log "[#{account}][rsync][\e[32mINFO\e[0m] Done migration home only"
    if index == accounts.size - 1
      exit(0)
    end
    next
  end

  begin
    # Lista os VHosts a serem migrados
    if EXECUTE
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Start migration"
    else
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Start fake migration"
    end
    account_info = API.account_info(account)

    if REVERT
      vhost_list = Utils.list_vhost(account_info, NEW_SERVER)
      # Reverter migração
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Reverting VHosts from #{NEW_SERVER} to #{ORIGIN_SERVER}"
      Utils.log API.migrate(account, NEW_SERVER, ORIGIN_SERVER)
    else
      vhost_list = Utils.list_vhost(account_info, ORIGIN_SERVER)
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Migrating VHosts from #{ORIGIN_SERVER} to #{NEW_SERVER}"
      # Migra IDs (incluindo servidor, templates) - PHPVersion
      Utils.log API.migrate(account, ORIGIN_SERVER, NEW_SERVER)
      if vhost_list.values.include? true
        Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Recreating VHosts in #{NEW_SERVER}"
        # Enviar ações para criar Homes, CGroups, VHosts, etc.
        Utils.log API.recreate(account, NEW_SERVER)
      else
        Utils.log "[#{account}][migration][\e[33mWARN\e[0m] No active VHosts - Home/VHost creation will be done during restore"
      end
    end

    # Para cada VHost, alterar o DNS da zona que aponta para o servidor e wss
    vhost_list.each do |domain, active|
      if !active
        Utils.log "[#{account}][DNS][\e[33mWARN\e[0m] VHost #{domain} inactive"
        next
      end
      Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Start DNS migration of domain #{domain}"
      if REVERT
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Revert migrating domain from #{NEW_SERVER} to #{ORIGIN_SERVER}"
        Utils.log API.replace_host(domain, NEW_SERVER, ORIGIN_SERVER)
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Revert migrating WSS from #{new_wss_server} to #{original_wss_server}"
        Utils.log API.replace_host(domain, new_wss_server, original_wss_server) if new_wss_server and original_wss_server
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Done DNS migration of domain #{domain}"
        Utils.move_home(account,trash_dir,account_dir, revert: true, dry_run: EXECUTE)
      else
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Migrating domain from #{ORIGIN_SERVER} to #{NEW_SERVER}"
        Utils.log API.replace_host(domain, ORIGIN_SERVER, NEW_SERVER)
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Migrating WSS from #{original_wss_server} to #{new_wss_server}"
        Utils.log API.replace_host(domain, original_wss_server, new_wss_server) if new_wss_server and original_wss_server
        Utils.log "[#{account}][DNS][\e[32mINFO\e[0m] Done DNS migration of domain #{domain}"
        Utils.move_home(account,trash_dir,account_dir, revert: false, dry_run: EXECUTE)
        if Rsync.test_rsync("/var/lib/apache2/md/domains/#{domain}","#{NEW_SERVER_PRV}:/var/lib/apache2/md/domains/",account)
          Rsync.rsync_certificate(domain, "#{NEW_SERVER_PRV}:/var/lib/apache2/md/domains/", account, dry_run: EXECUTE)
        end
      end
    end
    if Rsync.test_rsync("/home/#{account}","#{NEW_SERVER_PRV}:/home/",account)
      Rsync.rsync_home(account,"#{NEW_SERVER_PRV}:/home/", dry_run: EXECUTE)
    end
    
    if EXECUTE
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Done migration\n\n"
    else
      Utils.log "[#{account}][migration][\e[32mINFO\e[0m] Done fake migration\n\n"
    end
  rescue Digirati::API::CommandError => e
    Utils.log "[#{account}][migration][\e[31mERROR\e[0m] #{e.message}"
    raise
  end
end
