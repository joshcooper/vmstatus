class Vmstatus::List
  def initialize(opts)
    @opts = opts
  end

  def output(results)
    puts ""

    puts "Hostname".ljust(16) + "Cluster Host".ljust(45) + "Type".ljust(23) + "Pooler".ljust(8) + "Status".ljust(10) + "Running".ljust(9) + "Checkout Time".ljust(25) + "TTL".rjust(12) + " User".ljust(22) + "Jenkins Job"

    countcluster = Hash.new
    results.vms.sort_by do |vm|
      case @opts[:sort]
      when 'checkout'
        [vm.checkout, vm.hostname]
      when 'job'
        [vm.job_name, vm.hostname]
      when 'ttl'
        [vm.ttl, vm.hostname]
      when 'user'
        [vm.user, vm.hostname]
      when 'host'
        vm.hostname
      when 'pooler'
        [vm.vmpooler || 'none', vm.status, vm.hostname]
      when 'type'
        [vm.type || 'unknown', vm.status, vm.hostname]
      else
        [vm.status, vm.hostname]
      end
    end.each do |vm|
      color = case vm.status
              when 'building', 'queued'
                :blue
              when 'adhoc', 'ready'
                :yellow
              else
                :red
              end

      hostname = vm.hostname.length > 15 ? (vm.hostname[0..12] + "...") : vm.hostname
      on = vm.on? ? 'on' : 'off'
      running = vm.running? ? '*' : '!'

      checkout = vm.checkout ? vm.checkout.to_s : ' '
      ttl = vm.ttl ? ("%8.2fh" % vm.ttl) : 'never'
      user = vm.user ? vm.user : ' '
      type = vm.type ? (vm.type.length > 22 ? (vm.type[0..18] + "...") : vm.type) : 'unknown'
      pooler = case vm.vmpooler
               when 'vmpooler'
                 'ci-old'
               when 'vmpooler-cinext'
                 'ci-next'
               when 'vmpooler-dev'
                 'ci-dev'
               else
                 vm.vmpooler || 'none'
               end
      clusterhost = vm.clusterhost ? vm.clusterhost : "N/A"
      left = hostname.ljust(16) + clusterhost.ljust(45) + type.ljust(23) + pooler.ljust(8) + vm.status.ljust(10) + on.rjust(3) + "/" + running.ljust(5) + checkout.ljust(25) + ttl.rjust(12) + " " + user.ljust(20)
      right = @opts.long? ? vm.url : vm.job_name

      puts "#{left} #{right}".colorize(color)

      # count for each cluster host
      if vm.on? == "poweredOn" # only count when VM is on
        if !countcluster[clusterhost]
          countcluster[clusterhost] = 1
        else
          countcluster[clusterhost] = countcluster[clusterhost] + 1
        end
      end
    end

    puts ""
    puts "Cluster host count of VM that are powered on"
    countcluster.sort_by {|host, count| host}.each do |host, count|
      puts "#{host} #{count}"
    end
  end
end
