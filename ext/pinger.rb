require 'concurrent'
require 'socket'
require 'redis'
require 'ruby-progressbar'

def run(host, port)
  connect_nonblocking(host, port)
end

private

def connect_nonblocking(host, port)
  sockaddr = Socket.sockaddr_in(port, host)

  socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  begin
    socket.connect_nonblock(sockaddr)
  rescue IO::WaitWritable
    if IO.select(nil, [socket], nil, 10)
      begin
        socket.connect_nonblock(sockaddr)
      rescue Errno::EISCONN
        # connected
      end
    else
      raise Errno::ETIMEDOUT.new
    end
  ensure
    socket.close
  end
end

def with_redis(host)
  redis = Redis.new(:host => host)
  begin
    yield redis
  ensure
    redis.close
  end
end

def last_checked(check)
  if check.nil?
    "never"
  else
    diff = (Time.now - Time.parse(check)) / 60
    "%.2f minutes ago" % diff
  end
end

#progress = ProgressBar.create(:format => '%a %B %p%% %t', :autostart => false, :autofinish => false)
connected = Concurrent::Array.new
lost = Concurrent::Array.new
delete = Concurrent::Array.new

futures = []

with_redis(ENV['VMPOOLER_HOST']) do |redis|
  redis.keys('vmpooler__ready__*').each do |key|
    redis.smembers(key).each do |hostname|
      print '.'
      future = Concurrent::Future.execute do
        values = redis.hgetall("vmpooler__vm__#{hostname}")
        check = values['check']

        begin
          connect_nonblocking(hostname, 22)
          connected << "Host #{hostname} (#{key}) connected"
        rescue => e
          delete << hostname
          lost << "Host #{hostname} (#{key}) not connected, last checked #{last_checked(check)}: #{e.message} "
        end
      end
      futures << future
    end
  end

  futures.each do |future|
    future.wait
  end
end

puts ""
puts "Connected #{connected.count}"
puts "Lost #{lost.count}"
puts ""
lost.each do |result|
  puts result
end

with_redis(pooler) do |redis|
  delete.map do |hostname|
    template, clone = redis.hmget("vmpooler__vm__#{hostname}", 'template', 'clone')

    #if redis.srem("vmpooler__ready__#{template}", hostname)
    #  redis.sadd("vmpooler__completed__#{template}", hostname)
    #end
    "#{clone} #{hostname} #{template}"
  end.sort.each do |line|
    puts line
  end
end
