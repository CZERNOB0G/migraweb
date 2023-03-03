#!/usr/bin/ruby
module Rsync
  extend self

  def test_rsync(source,destination,account)
    if system("rsync --dry-run -a #{source} #{destination}")
      return true
    else
      return false
      Utils.log("[#{account}][rsync][\e[31mERROR\e[0m] #{$?.exitstatus}")
    end
  end

  def rsync(source, destination, account, dry_run: true)
    if dry_run
      cmd = 'rsync -az --rsh=ssh'
      cmd += " #{source} #{destination}"

      pid, _stdin, _stdout, stderr = Open4.popen4 cmd
      _ignored, status = Process.waitpid2 pid
     Utils.log puts stderr.read.strip unless status.success?
    else
      Utils.log("[#{account}][rsync][\e[32mINFO\e[0m] Noop active, do nothing")
    end
  end

  def rsync_home(account, destination, dry_run: true)
    source = "/home/#{account}"
    Utils.log("[#{account}][rsync][\e[32mINFO\e[0m] Migrating HOME")
    rsync(source, destination, account, dry_run: dry_run)
    Utils.log("[#{account}][rsync][\e[32mINFO\e[0m] Done migrating HOME")
  end

  def rsync_certificate(domain, destination, account, dry_run: true)
    source = "/var/lib/apache2/md/domains/#{domain}"
    Utils.log("[#{account}][rsync][\e[32mINFO\e[0m] Migrating CERTIFICATE")
    rsync(source, destination, account, dry_run: dry_run)
    Utils.log("[#{account}][rsync][\e[32mINFO\e[0m] Done migrating CERTIFICATE")
  end
end