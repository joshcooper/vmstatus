require 'redis'
require 'ruby-progressbar'
require 'slop'
require 'colorize'
require 'statsd'

require 'vmstatus/processor'
require 'vmstatus/version'

class Vmstatus::CLI
  def initialize(argv)
    @argv = argv
    @progress = ProgressBar.create(:format => '%a %B %p%% %t', :autostart => false, :autofinish => false)
  end

  def execute
    opts = Slop.parse(@argv) do |o|
      o.string '--host', 'vmpooler redis hostname', default: 'localhost'
      o.bool '-v', '--verbose', 'verbose mode'
      o.bool '-l', '--long', 'show long form of the job url'
      o.string '-s', '--sort', "sort by 'host', 'checkout', 'ttl', 'user', 'job'", default: 'host'
      o.string '-p', '--publish', 'publish stats <host:port>'
      o.on '--version', 'print the version' do
        puts Vmstatus::VERSION
        exit
      end
      o.on '-h', '--help' do
        puts o
        exit
      end
    end

    puts "Querying #{opts[:host]}"

    results = process(opts)

    puts ""
    puts ""

    results.state.each_pair do |name, vms|
      puts "#{name.upcase}".ljust(16, ' ') + " (#{vms.count})".rjust(69, '-')
      if opts.verbose?
        vms.sort_by do |vm|
          case opts[:sort]
          when 'checkout'
            vm.checkout
          when 'job'
            vm.job_name
          when 'ttl'
            vm.ttl
          when 'user'
            vm.user
          else
            vm.hostname
          end
        end.each do |vm|
          color = if vm.ttl <= 0
                    :red
                  elsif vm.url.nil?
                    :yellow
                  else
                    :cyan
                  end

          checkout = vm.checkout || (' ' * 25)
          left = ("#{vm.hostname} #{checkout} " + ("%10.2fh" % vm.ttl) + " #{vm.user}").ljust(20, ' ')

          right = opts.long? ? vm.url : vm.job_name

          puts "#{left} #{right}".colorize(color)
        end
      end
      puts ""
    end

    if opts[:publish]
      begin
        host, port = opts[:publish].split(':')
        statsd = Statsd.new(host, port)
        # use host as a substat in graphite. eg localhost will publish under vmstatus.localhost and
        # "vmpooler.d.p.n" push to "vmpooler" and "vmpooler-cinext.d.p.n" push to "vmpooler-cinext"
        substat = opts[:host].split('.').first
        results.state.each_pair do |name, vms|
          statsd.gauge("vmstatus.#{substat}.#{name}", vms.count)
        end
      rescue ArgumentError => e
        puts "Invalid publish host:port #{opts[:publish]}: #{e.message}"
        exit 1
      end
    end
  end

  def process(opts)
    with_redis(opts) do |redis|
      processor = Vmstatus::Processor.new(self)
      processor.process(redis)
    end
  end

  def on_total(total)
    @progress.total = total
  end

  def on_start
    @progress.start
  end

  def on_progress(current_progress)
    @progress.increment
  end

  def on_finish
    @progress.finish
  end

  private

  def with_redis(opts, &block)
    redis = Redis.new(:host => opts[:host])
    begin
      yield redis
    ensure
      redis.close
    end
  end
end
