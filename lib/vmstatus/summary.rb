class Vmstatus::Summary
  def initialize(opts)
    @opts = opts
  end

  def output(results)
    puts ""
    puts "Number of VMs associated with running Jenkins jobs"
    puts format_line(results.queued, 'queued', :blue)
    puts format_line(results.building, 'building', :blue)
    puts ""

    puts "Number of VMs associated with completed Jenkins jobs"
    puts format_line(results.passed, 'passed', :red)
    puts format_line(results.failed, 'failed', :red)
    puts format_line(results.aborted, 'aborted', :red)
    puts format_line(results.disabled, 'disabled', :red)
    puts format_line(results.deleted, 'deleted', :red)
    puts ""

    puts "Number of VMs not associated with vSphere"
    puts format_line(results.zombie, 'zombie', :red)
    puts ""

    puts "Number of VMs not associated with any vmpooler"
    puts format_line(results.orphaned, 'orphaned', :red)
    puts ""

    puts "Number of VMs not associated with any Jenkins job"
    puts format_line(results.adhoc, 'adhoc', :yellow)
    puts format_line(results.ready, 'ready', :yellow)
    puts ""

    useful_vms = results.useful_count
    total_vms  = results.total_count
    eff = total_vms > 0 ? useful_vms / total_vms.to_f * 100 : 0

    puts "Efficiency %.1f%%, #{useful_vms} out of #{total_vms} VMs are doing useful work" % eff

    puts ""
    countcluster = Hash.new
    results.vms.each do |vm|
      clusterhost = vm.clusterhost ? vm.clusterhost : "N/A"
      # count for each cluster host
      if !countcluster[clusterhost]
        countcluster[clusterhost] = 1
      else
        countcluster[clusterhost] = countcluster[clusterhost] + 1
      end
    end

    puts "Cluster host count of VM"
    countcluster.sort_by {|host, count| host}.each do |host, count|
      puts "#{host} #{count}"
    end

    if @opts[:publish]
      begin
        host, port = @opts[:publish].split(':')
        statsd = Statsd.new(host, port)
        statsd.namespace = "vmstatus"

        Vmstatus::Results::STATES.each do |state|
          vms = results.state[state]
          vmpooler2vms = vms.group_by {|vm| vm.vmpooler || "none" }
          (@opts[:vmpoolers] + ["none"]).each do |vmpooler|
            next if vmpooler == "none" && state != "orphaned"
            next if vmpooler != "none" && state == "orphaned"

            arr = vmpooler2vms[vmpooler]
            count = arr.nil? ? 0 : arr.count
            statsd.gauge("#{vmpooler}.#{state}", count)
          end
        end

        countcluster.each do |host, count|
          statsd.gauge("host.#{host}", count)
        end
      rescue ArgumentError => e
        raise ArgumentError.new("Invalid publish host:port #{@opts[:publish]}: #{e.message}")
      end
    end
  end

  private

  def format_line(vms, label, color = nil)
    line = "#{vms.count}".rjust(7, ' ') + " #{label}"
    color ? line.colorize(color) : line
  end
end
