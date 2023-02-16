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
    accounts = get_accounts_for_domains(client, domains)
    accounts.uniq.sort
  ensure
    client.close if client
  end

  private

  def get_domains(client, server, limit)
    sql = <<-SQL
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
    SQL

    client.query(sql, server, limit).map { |row| row['domain'] }
  end

  def get_accounts_for_domains(client, domains)
    sql = <<-SQL
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
    SQL

    domains.flat_map do |domain|
      client.query(sql, domain).map { |row| row['StAccount'] }
    end
  end
end