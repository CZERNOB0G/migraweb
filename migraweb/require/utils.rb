module Utils
  extend self

  def read_file(filename, sort: true)
    lines = File.readlines(filename).map(&:chomp)
    sort ? lines.sort : lines
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
    write_file('./migrastart.log', 'a', log)
  end
end