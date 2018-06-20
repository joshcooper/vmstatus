require 'date'
require 'time'

class Vmstatus::VM
  attr_reader :hostname, :uuid, :url, :type, :user, :checkout, :ttl, :status, :vmpooler, :clusterhost

  def initialize(hostname)
    @hostname = hostname
  end

  def status
    @status ||=
      if vmpooler
        if uuid
          if checkout
            if url
              if @job_status
                @job_status # associated with vmpooler and vsphere, checked out, has url and job status
              else
                "bad: #{@reason}"
              end
            else
              'adhoc' # associated with vmpooler and checked out, but no job url
            end
          else
            'ready' # associated with vmpooler, but not checked out
          end
        else
          'zombie' # associated with vmpooler, but not in vsphere
        end
      else
        'orphaned' # not associated with any vmpooler, but in vsphere
      end
  end

  def on?
    @on
  end

  def running?
    @running
  end

  def job_name
    @job_name ||=
      if url.nil?
        ''
      elsif data = url.match(/.*\/job\/([^\/]+)/)
        data[1]
      else
        url
      end
  end

  def to_s
    @hostname
  end

  def vsphere_status=(status)
    @on   = status[:on]
    @uuid = status[:uuid]
    @clusterhost = status[:clusterhost]
  end

  def vmpooler_status=(status)
    @vmpooler = status[:vmpooler]
    @type     = status[:type]
    @url      = status[:url]
    @user     = status[:user] || ''

    if status[:checkout]
      @checkout = DateTime.parse(status[:checkout])

      if status[:lifetime]
        expiration = @checkout + (Integer(status[:lifetime]) / 24.0)
        @ttl = (expiration.to_time - Time.now) / 60.0 / 60.0 # hours
      end
    end
  end

  def running=(time, value, reason)
    if value
      @running = value
    else
      @reason = reason
      #$stderr.puts "Failed to connect to #{@hostname}: #{@reason} (#{reason.class})\n"
    end
  end

  def job_status=(time, value, reason)
    if value
      @job_status = value
    else
      @reason = reason
      #$stderr.puts "Failed to get job status for #{@hostname}: #{@reason} (#{reason.class})\n"
    end
  end
end
