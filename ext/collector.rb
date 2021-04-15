require 'rbvmomi'
require 'pp'

conn = RbVmomi::VIM.connect(host: ENV['VSPHERE_HOST'],
                            user: ENV['LDAP_USER'],
                            password: ENV['LDAP_PASSWORD'],
                            ssl: true,
                            insecure: true)
begin
  dc = conn.serviceInstance.find_datacenter(ENV['VSPHERE_DC'])

  pod = [dc.find_compute_resource(ENV['VSPHERE_COMPUTE_CLUSTER'])]

  filterSpec = RbVmomi::VIM.PropertyFilterSpec(
    objectSet: pod.map do |computer, stats|
      {
        obj: computer.resourcePool,
        selectSet: [
          RbVmomi::VIM.TraversalSpec(
          name: 'tsFolder',
          type: 'ResourcePool',
          path: 'resourcePool',
          skip: false,
          selectSet: [
            RbVmomi::VIM.SelectionSpec(name: 'tsFolder'),
            RbVmomi::VIM.SelectionSpec(name: 'tsVM'),
          ]
        ),
          RbVmomi::VIM.TraversalSpec(
            name: 'tsVM',
            type: 'ResourcePool',
            path: 'vm',
            skip: false,
            selectSet: [],
          )
        ]
      }
    end,
    propSet: [
      { type: 'ResourcePool', pathSet: ['name'] },
      { type: 'VirtualMachine', pathSet: %w(name runtime.powerState summary.overallStatus summary.config.numCpu) }
    ]
  )
  result = conn.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
  result.each do |obj|
     puts "#{obj['name']}"
     obj.propSet.each do |prop|
       next if prop.name == 'name'
       puts "  #{prop.name}=#{prop.val}"
     end
  end
ensure
  conn.close
end

