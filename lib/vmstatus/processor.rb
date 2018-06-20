require 'concurrent'
require 'set'

require 'vmstatus/vm'
require 'vmstatus/ping_task'
require 'vmstatus/jenkins_task'
require 'vmstatus/vmpooler_task'
require 'vmstatus/vsphere_task'
require 'vmstatus/results'

class Vmstatus::Processor
  def initialize(opts, observer)
    @opts = opts
    @observer = observer
    @executor = Concurrent::FixedThreadPool.new(Concurrent.processor_count * 2)
    @vms = Concurrent::Map.new
  end


  def process
    with_futures do |futures|
      @opts[:host].each do |host|
        # async collect vsphere inventory
        vcenter_config = {
            :host => host,
            :user => @opts[:user],
            :password => @opts[:password],
            :datacenter => @opts[:datacenter].shift,
            :cluster => @opts[:cluster].shift,
            :vmpoolers => @opts[:vmpoolers]
        }
        future = Concurrent::Future.new(:executor => @executor) do
          task = Vmstatus::VsphereTask.new(vcenter_config)
          task.run do |hostname, vsphere_status|
            @vms.compute(hostname) do |stored_value|
              vm = stored_value || Vmstatus::VM.new(hostname)
              vm.vsphere_status = vsphere_status
              vm
            end
          end
        end
        future.add_observer(@observer, :on_increment)
        futures << future
        future.execute
      end

      # async collect vmpooler(s) inventory
      @opts[:vmpoolers].each do |vmpooler|
        future = Concurrent::Future.new(:executor => @executor) do
          task = Vmstatus::VmpoolerTask.new(vmpooler)
          task.run do |hostname, vmpooler_status|
            @vms.compute(hostname) do |stored_value|
              vm = stored_value || Vmstatus::VM.new(hostname)
              vm.vmpooler_status = vmpooler_status
              vm
            end
          end
        end
        future.add_observer(@observer, :on_increment)
        futures << future
        future.execute
      end
    end

    @observer.on_total(4 * @vms.size)

    with_futures do |futures|
      # async ping all hosts
      @vms.each_pair do |hostname, vm|
        future = Concurrent::Future.new(:executor => @executor) do
          task = Vmstatus::PingTask.new(hostname, 22)
          task.run
        end
        future.add_observer(vm, :running=)
        future.add_observer(@observer, :on_increment)
        futures << future
        future.execute
      end

      # async lookup jenkins info
      @vms.each_pair do |hostname, vm|
        if vm.url
          future = Concurrent::Future.new(:executor => @executor) do
            task = Vmstatus::JenkinsTask.new(vm)
            task.run
          end
          future.add_observer(vm, :job_status=)
          future.add_observer(@observer, :on_increment)
          futures << future
          future.execute
        end
      end
    end

    Vmstatus::Results.new(@vms.values)
  end

  private

  def with_futures(&block)
    futures = Concurrent::Array.new
    begin
      yield futures

      futures.to_a.each do |future|
        future.wait
      end
    ensure
      futures.each { |future| future.delete_observers }
    end
  end
end
