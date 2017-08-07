require_relative '../../../puppet_x/puppetlabs/aws'

Puppet::Type.type(:ec2_volume).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws

  mk_resource_methods

  def self.instances
    regions.collect do |region|
      ec2 = ec2_client(region)
      begin
        volumes = []
        volume_response = ec2.describe_volumes()
        volume_response.data.volumes.collect do |volume|
          hash = volume_to_hash(region, volume)
          volumes << new(hash) if has_name?(hash)
        end
        volumes
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

    config = {
      name: name,
      volume_id: volume.volume_id,
      size: volume.size,
      iops: volume.iops,
      volume_type: volume.volume_type,
      availability_zone: volume.availability_zone,
      snapshot_id: volume.snapshot_id,
      ensure: :present,
      region: region,
      instance_id: instance,
    }
    config[:attach] = attachments unless attachments.empty?
    config
  end

  def exists?
    Puppet.info("Checking if EC2 volume #{name} exists in region #{target_region}")
    @property_hash[:ensure] == :present
  end

  def ec2
    ec2 = ec2_client(target_region)
    ec2
  end

  def attach_instance(volume_id)
    config = {}
    config[:instance_id] = resource[:attach]["instance_id"]
    config[:volume_id] = volume_id
    config[:device] = resource[:attach]["device"]
    Puppet.info("Attaching Volume #{volume_id} to ec2 instance #{config[:instance_id]}")
    ec2.wait_until(:volume_available, volume_ids: [volume_id])
    ec2.attach_volume(config)
    if (resource[:attach].has_key?("delete_on_termination") ? resource[:attach]["delete_on_termination"] : false) then
      Puppet.info("Modifying instance attribute delete_on_termination=#{resource[:attach]["delete_on_termination"]} for #{resource[:attach]["device"]} on ec2 instance #{config[:instance_id]}")
      config = {}
      config[:instance_id] = resource[:attach]["instance_id"]
      config[:block_device_mappings] = [{ :device_name=> resource[:attach]["device"], :ebs=> { :delete_on_termination=> true } }]
      ec2.modify_instance_attribute(config)
    end
  end
end
