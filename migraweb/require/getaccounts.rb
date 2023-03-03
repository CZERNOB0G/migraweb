#!/usr/bin/ruby
module Accounts
  extend self

  def get_accounts(server, limit)
    client = Mysql2::Client.new(
      host: 'mysql18.digirati.com.br',
      username: 'admin.dig',
      password: 'fC92n%6YaLnQ',
      database: 'web'
    )

    domains = get_domains(client, server, limit)
    if domains.empty?
      Utils.log "[migration][\e[31mERROR\e[0m] No domains found on origin server"
      exit(1)
    end
    accounts = get_accounts_for_domains(client, domains)
    if accounts.empty?
      Utils.log "[migration][\e[31mERROR\e[0m] No accounts found on origin server"
      exit(1)
    end
    accounts = accounts.sort.uniq
    return accounts
  ensure
    client.close if client
  end

  private

  def get_domains(client, server, limit)
    domain_query = client.prepare("
    SELECT
      StAlias AS domain
    FROM
      Alias AL
    LEFT JOIN
      VHost VH ON VH.IDServerName = AL.IDAlias
    LEFT JOIN
      Addr AD USING (IDAddr)
    LEFT JOIN
      Server SE USING (IDServer)
    WHERE
      StServer = ? AND 
      VH.EnActive = 'TRUE'
    LIMIT ?
    ")
    domains = []
    domains_list = domain_query.execute(server,limit)
    domains_list.each do |row|
      domains << row['domain']
    end
    return domains
  end

  def get_accounts_for_domains(client, domains)
    accounts_query = client.prepare("
      SELECT 
        A.StAccount
      FROM 
        Alias Al
      LEFT JOIN 
        VHost VH ON Al.IDAlias = VH.IDServerName
      LEFT JOIN 
        Account A ON VH.IDAccount = A.IDAccount
      WHERE 
        Al.StAlias = ?
    ")
    accounts = []
    domains.each do |domain|
      accounts_list = accounts_query.execute(domain)
      accounts_list.each do |row|
        accounts << row['StAccount']
      end
    end
    return accounts
  end
end