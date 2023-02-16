module Rsync
  extend self

  def rsync(source, destination, dry_run: false)
    cmd = "rsync -az --rsh=ssh #{source} #{destination}"
    return if dry_run

    pid = spawn(cmd)
    _, status = Process.waitpid2(pid)
    $stderr.puts(status.inspect) unless status.success?
  end

  def rsync_home(account, destination, dry_run: false)
    source = File.join('/home', account)
    Utils.log("[#{account}][rsync][INFO] Start rsync home")
    rsync(source, destination, dry_run: dry_run)
    Utils.log("[#{account}][rsync][INFO] Done rsync home\n\n")
    "rsync home completed for account #{account}"
  end

  def rsync_certificate(domain, destination, dry_run: false)
    source = File.join('/var/lib/apache2/md/domains', domain)
    Utils.log("[#{account}][rsync][INFO] Start rsync certificate")
    rsync(source, destination, dry_run: dry_run)
    Utils.log("[#{account}][rsync][INFO] Done rsync certificate\n\n")
    "rsync certificate completed for domain #{domain}"
  end
end