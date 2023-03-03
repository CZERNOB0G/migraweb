require_relative 'digirati/api'

module API
  extend self

  def execute_command(api, params, execute = true)
    if execute
      api_user = 'migraweb'
      api_pass = '7s!S0N@u'
      r = Digirati::API::transaction do |t|
        t.authenticate :user => api_user, :password => api_pass
        t.command api
        t.parameters params
      end
      return r[api]
    else
      return [api, params]
    end
  end

  def account_info(account)
    api    = 'WTD2_AccountInfo'
    params = {
      'StAccount' => account
    }
    execute_command(api, params)
  end

  def recreate(account, server)
    server =~ /(web\d+)\..+/
    api    = 'WTD2_Recreate'
    params = {
      'account' => account,
      'server'  => $1
    }
    execute_command(api, params, EXECUTE)
  end

  def migrate(account, server, new_server)
    api    = 'WTD2_Migrate'
    params = {
      'account' => account,
      'server'  => server,
      'new_server' => new_server
    }
    execute_command(api, params, EXECUTE)
  end

  def server_info(server)
    api    = 'WTD2_ServerInfo'
    params = {
      'server' => server
    }
    execute_command(api, params)
  end

  def replace_host(domain, host, new_host)
    api    = 'DNS_ReplaceHost'
    params = {
      'domain'      => domain,
      'host'        => host,
      'new_host'    => new_host,
      'search_zone' => true
    }
    execute_command(api, params, EXECUTE)
  end
end
