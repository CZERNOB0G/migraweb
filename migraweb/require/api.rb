require_relative 'digirati/api'

module API
  extend self
  
  API_LOG = "api.log"
  EXECUTE = true
  API_USER = "migraweb"
  API_PASS = "7s!S0N@u"

  module_function

  def server_info(server)
    execute_command('WTD2_ServerInfo', 'server' => server)
  end

  def account_info(account)
    execute_command('WTD2_AccountInfo', 'StAccount' => account)
  end

  def recreate(account, server)
    server =~ /(web\d+)\..+/
    execute_command('WTD2_Recreate', 'account' => account, 'server' => $1, execute: EXECUTE)
  end

  def migrate(account, server, new_server)
    execute_command('WTD2_Migrate', 'account' => account, 'server' => server, 'new_server' => new_server, execute: EXECUTE)
  end

  def replace_host(domain, host, new_host)
    execute_command('DNS_ReplaceHost', 'domain' => domain, 'host' => host, 'new_host' => new_host, 'search_zone' => true, execute: EXECUTE)
  end

  def list_vhost(account_info, server)
    vhost_list = {}
    account_info['info']['VHosts'].each do |_, v|
      active = (v['EnActive'] == 'TRUE' && v['EnAction'] != 'DROP') ||
                (v['EnActive'] == 'FALSE' && v['EnAction'] == 'CREATE')
      vhost_list[v['StServerName']] = active if v['StFullServer'] == server
    end
    vhost_list
  end

  private

  def execute_command(api, params, execute: false)
    return [api, params] unless execute

    response = Digirati::API.transaction do |t|
      t.authenticate(user: API_USER, password: API_PASS)
      t.command(api)
      t.parameters(params)
    end

    response[api]
  end
end
