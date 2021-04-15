require 'redis'

def with_redis(host)
  redis = Redis.new(:host => host)
  begin
    yield redis
  ensure
    redis.close
  end
end

names = File.read('delete.txt').lines.map { |line| line.match(/[\w]+/)[0] }

pooler = ENV['VMPOOLER_HOST']

with_redis(pooler) do |redis|
  names.each do |hostname|
    template, clone, checkout = redis.hmget("vmpooler__vm__#{hostname}", 'template', 'clone', 'checkout')

    if checkout
      if redis.srem("vmpooler__running__#{template}", hostname)
        redis.sadd("vmpooler__completed__#{template}", hostname)
      end
      puts "deleted running #{hostname} #{template} #{checkout}"
    elsif clone
      if redis.srem("vmpooler__ready__#{template}", hostname)
        redis.sadd("vmpooler__completed__#{template}", hostname)
      end
      puts "deleted ready #{hostname} #{template} #{clone}"
    else
      puts "skipping #{hostname}"
    end
  end
end
