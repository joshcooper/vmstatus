require 'redis'
require 'ruby-progressbar'
require 'slop'
require 'colorize'
require 'statsd'
require 'concurrent'

require 'vmstatus/list'
require 'vmstatus/processor'
require 'vmstatus/summary'
require 'vmstatus/version'
require 'vmstatus/vsphere_task'

class Vmstatus::CLI
  def initialize(argv)
    @argv = argv
    @progress = ProgressBar.create(:format => '%a %B %p%% %t', :autostart => false, :autofinish => false)
  end

  def execute
    opts = Slop.parse(@argv) do |o|
      o.separator 'Commands:'
      o.separator '     list          List status of all VMs'
      o.separator '     summary       Summary of VM status'
      o.separator ''
      o.separator 'Options:'
      o.array '--host', 'comma-separated list of vsphere hostname', delimiter: ',', default: ['localhost']
      o.string '--user', 'vsphere user'
      o.string '--password', 'vsphere password', default: ENV['LDAP_PASSWORD']
      o.array '--datacenter', 'comma-separated list of vsphere datacenter', delimiter: ',', default: ['opdx2']
      o.array '--cluster', 'comma-separated list of vsphere cluster', delimiter: ',', default: ['acceptance1']
      o.array '--vmpoolers', 'comma-separated list of vmpooler hostnames', delimiter: ',', default: ['vmpooler','vmpooler-cinext','vmpooler-dev']
      o.bool '-v', '--verbose', 'verbose mode'
      o.bool '-l', '--long', 'show long form of the job url'
      o.string '-s', '--sort', "sort by 'host', 'checkout', 'ttl', 'user', 'job', 'status', 'type', 'pooler'", default: 'status'
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

    if opts[:user].nil?
      raise ArgumentError.new("Specify the vsphere (LDAP) username, e.g. 'user@puppet.com'")
    elsif opts[:password].nil?
      raise ArgumentError.new("Specify the vsphere (LDAP) password or set ENV['LDAP_PASSWORD']")
    end

    if opts[:host].length != opts[:datacenter].length or opts[:datacenter].length != opts[:cluster].length
      raise ArgumentError.new("When specifying #{opts[:host].length} hosts, you have to also specify the respective --datacenter and --cluster")
    end

    formatter = nil
    command = opts.arguments.first
    case command
    when 'list'
      formatter = Vmstatus::List.new(opts)
    when 'summary'
      formatter = Vmstatus::Summary.new(opts)
    else
      puts "Unknown command '#{command}'\n" if command
      puts opts.options
      exit 1
    end

    # REMIND: filter output based on vmpooler
    # REMIND: filter output based on status, e.g. include only zombies, exclude ready
    on_total(8000)
    on_start

    # REMIND: need to account for mac VMs in mac1 cluster
    processor = Vmstatus::Processor.new(opts, self)
    results = processor.process

    on_finish
    formatter.output(results)
  end

  def on_total(total)
    @progress.total = [total, @progress.progress].max
  end

  def on_start
    @progress.start
  end

  def on_increment(time, value, reason)
    @progress.increment
  end

  def on_finish
    @progress.finish
  end
end
