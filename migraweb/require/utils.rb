module Utils
  module_function

  def read_file(filename, sort: true)
    File.readlines(filename, chomp: true).tap do |lines|
      lines.sort! if sort
      lines.uniq!
    end
  rescue Errno::ENOENT
    []
  end

  def write_file(name, mode, text)
    File.open(name, mode) { |file| file.puts text }
  end

  def log(text)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    log = "[#{timestamp}]#{text}"
    puts log
    write_file('./migraweb.log', 'a', log)
  end

  def get_avoid(filename, account)
    read_file(filename).any? { |line| line.include?(account) }
  end

  def list_vhost(account_info, server)
    vhost_list = {}
    account_info['info']['VHosts'].each.each { |k, v|
      active = (v['EnActive'] == 'TRUE' && v['EnAction'] != 'DROP') ||
              (v['EnActive'] == 'FALSE' && v['EnAction'] == 'CREATE')
      if v['StFullServer'] == server
        vhost_list[v['StServerName']] = active
      end
    }
    vhost_list
  end

  def move_home(account, trash_dir, account_dir, revert: false, dry_run: true)
    if dry_run
      
      trash_account_dir = File.join(trash_dir, account)
      if revert
        Utils.log "[#{account}][HOME][\e[32mINFO\e[0m] Restauring account dir from #{trash_dir}#{account} to #{account_dir}"
        if File.directory?(trash_account_dir) && !account.empty?
          Utils.log FileUtils.mv(trash_account_dir, '/home/')
          Utils.log FileUtils.chown_R(account, account, account_dir)
        end
      else
        Utils.log "[#{account}][HOME][\e[32mINFO\e[0m] Moving account dir #{account_dir} to trash in #{trash_dir}"
        unless File.directory?(trash_dir)
          Utils.log FileUtils.mkdir(trash_dir, mode: 0000)
          Utils.log FileUtils.chown_R('root', 'root', trash_dir)
        end
        if File.directory?(account_dir) && !account.empty?
          Utils.log FileUtils.mv(account_dir, trash_dir)
          Utils.log FileUtils.chown_R('root', 'root', trash_account_dir)
        end
      end
    else
      Utils.log("[#{account}][HOME][\e[32mINFO\e[0m] Noop active, do nothing")
    end
  end
end
