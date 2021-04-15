require 'rbvmomi'

names = File.read(ARGV[0]).lines.map { |line| line.match(/[\w]+/)[0] }

conn = RbVmomi::VIM.connect(host: ENV['VSPHERE_HOST'],
                            user: ENV['LDAP_USER'],
                            password: ENV['LDAP_PASSWORD'],
                            ssl: true,
                            insecure: true)
begin
  dc = conn.serviceInstance.find_datacenter(ENV['VSPHERE_DC'])
  #folder = dc.vmFolder.traverse('Discovered virtual machine', RbVmomi::VIM::Folder)
  resourcePool = dc.find_compute_resource(ENV['VSPHERE_COMPUTE_CLUSTER']).resourcePool

  names.each do |name|
    vm = dc.vmFolder.findByDnsName(name)
    if vm
      puts "deleting #{name}"
      next

      #vm = folder.traverse(name)
      #raise "VM #{name} doesn't exist in #{folder.name}" if vm.nil?

      if resourcePool.find(name).nil?
        puts "VM #{name} is not in the #{resourcePool.parent.name} cluster, skipping"
      else
        if vm.runtime.powerState == 'poweredOn'
          puts "stopping #{name}"
          vm.PowerOffVM_Task.wait_for_completion
        end

        vm.Destroy_Task.wait_for_completion
        puts "deleted #{name}"
      end
    else
      puts "vm #{name} not found, skipping"
    end
  end
ensure
  conn.close
end
