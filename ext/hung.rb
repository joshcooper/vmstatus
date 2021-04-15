require 'redis'

never = Hash.new
late = Hash.new

redis = Redis.new(:host => ENV['VMPOOLER_HOST'])
begin
  redis.keys('vmpooler__ready__*').each do |key|
    redis.smembers(key).each do |hostname|
      type = key.sub(/vmpooler__ready__/, '')

      check = redis.hget("vmpooler__vm__#{hostname}", 'check')
      if check.nil?
        never[type] ||= []
        never[type] << hostname
      else
        diff = ((Time.now - Time.parse(check)) / 60.0)
        if diff > 16 # default vm_checktime is 15 minutes, round up

          late[type] ||= []
          late[type] << hostname
        else
          #puts("checked #{type} #{hostname} %0.2f minutes ago" % diff)
        end
      end
    end
  end
ensure
  redis.close
end

never.keys.sort.each do |type|
  puts "never checked: #{type} (#{never[type].count} VMs)"
  # names.sort.each do |name|
  #   puts "  #{name}"
  # end
end

late.keys.sort.each do |type|
  puts "not checked recently: #{type} (#{late[type].count} VMs)"
  # names.sort.each do |name|
  #   puts "  #{name}"
  # end
end
#puts("not checked  #{type} #{hostname} in %0.2f minutes" % diff)
