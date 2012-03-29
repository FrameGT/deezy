require 'ipaddr'
require 'json'

module HostsHelper

  FIRST_206    =  6
  LAST_206     =  200
  FIRST_207    =  5
  LAST_207     =  200
  FIRST_186    =  1
  LAST_186     =  90
  FIRST_WIFI   =  91
  LAST_WIFI    =  199
  FIRST_GUEST  =  96
  LAST_GUEST   =  116
  LEASE_LENGTH = 3*60*60 # 3 hours


  def dhcpd_conf
    # XXX You cannot change the first and last lines. They're consumed by the
    # receiving DHCP server and it expects a specific format. XXX
    #
    [
      "# Last updated #{Host.last_updated}",
      comments,
      globals,
      subnets,
      hosts,
      '# File generated successfully'
    ].join "\n"
  end

  #
  # Return all free IP addresses as JSON
  #
  def free_ips_json

    out = []
    @conf['dhcpd']['subnets'].each do |subnet|
      net = IPAddr.new("#{subnet['pools'].first['first']}/#{subnet['netmask']}").to_s


      ips = []
      subnet['pools'].each do |pool|
        puts '#'*80
        pp [*IPAddr.new(pool['first'])..IPAddr.new(pool['last'])]

        ips << [*IPAddr.new(pool['first'])..IPAddr.new(pool['last'])]
        ips.flatten!
        pool['exceptions'].each do |exception|
          ips.reject! do |ip|
            [*IPAddr.new(exception['first'])..IPAddr.new(exception['last'])].include? ip
          end
        end if pool['exceptions']
        ips.reject! do |ip|
          used_ips.include? ip
        end
      end

      out << {
        :subnet => net,
        :ips => ips.map {|ip| ip.to_s}
      }
    end

    out.to_json
  end

  private

  #
  # Return an array of IP address pairs which represent DHCPD ranges. The
  # ranges are calculated by running through the list of ips and detecting
  # non-contiguous addresses.
  #
  def ranges(ips)
    ranges, start, prev = [], ips.first, ips.first
    ips.each_with_index do |ip, i|
      prev = ips[i-1] if i > 0
      if ip == ips.last
        ranges << [start, ip]
      elsif ip.to_i - prev.to_i > 1
        ranges << [start, prev]
        start = ip
      end
    end
    ranges
  end

  #
  # Comments so we can glean some useful stuff about the configuration by
  # glancing at the config file
  #
  def comments
    out = []
    out << '#'
    @conf['dhcpd']['subnets'].each do |s|
      out << '# %s/%s via %s' % [s['subnet'], s['netmask'], s['routers']]
      s['pools'].each do |p|
        exceptions = []
        p['exceptions'].each do |e|
          exceptions << ", [except: %s-%s (%s)]" % [e['first'], e['last'], e['notes']]
        end if p['exceptions']
        out << [
          "#   #{p['first']}-#{p['last']}",
          "#{" (#{p['notes']})" if p['notes']}",
            exceptions.join
        ].join
      end
      out << '#'
    end
    out << ''
  end


  def globals
    out = []
    out << raw_options(@conf['dhcpd']['raw_options'])
    out << dhcpd_options(@conf['dhcpd']['options'])
    out << ''
  end

  def dhcpd_options(options, indent=0)
    out = []
    options.each do |key, value|
      value = value.join(',') if value.class == Array
      out << "#{' '*indent}option #{key} #{value.chomp};"
    end if options
    out << ''
  end

  def raw_options(options, indent=0)
    out = []
    options.each do |option|
      out << "#{' '*indent}#{option};"
    end if options
    out << ''
  end


  def classes(subnet)
    out = []
    subnet['classes'].each do |clas|
      out << %[  class "#{clas['class']}" {]
      out << raw_options(clas['raw_options'], 4)
      out << "  }"
      out << ''
    end if subnet['classes']
    out << ''
  end

  def used_ips
    @used_ips ||= Host.used_ips
  end

  def pools(subnet)
    out = []
    subnet['pools'].each do |pool|

      pool_ips = [*IPAddr.new(pool['first'])..IPAddr.new(pool['last'])]
      possible_ips = pool_ips.reject do |ip|
        used_ips.include? ip
      end

      pool['exceptions'].each do |h|
        possible_ips.reject! do |ip|
          [*IPAddr.new(h['first'])..IPAddr.new(pool['last'])].include? ip
        end
      end if pool['exceptions']

      out << "  pool {"

      out << raw_options(pool['raw_options'], 4)

      ranges(possible_ips).each do |range|
        out << "    range #{range.first} #{range.last};"
      end
      out << "  }"
      out << ''
    end
    out << ''
  end


  def subnets
    out = []
    @conf['dhcpd']['subnets'].each do |subnet|
      out << "subnet #{subnet['subnet']} netmask #{subnet['netmask']} {"
      out << dhcpd_options(subnet['options'], 2)
      out << raw_options(subnet['raw_options'], 2)
      out << classes(subnet)
      out << pools(subnet)
      out << '}'
      out << ''
    end
    out << ''
  end

  def hosts
    out = []
    out << "group {"
    out << '  filename "deezy";'
    Host.find_all_by_enabled(true).each do |host|
      out << [
        "  host  #{host.hostname}  { hardware ethernet #{host.mac}; ",
        "#{"fixed-address #{host.ip};"  unless host.ip.blank?}",
        "}"
      ].join
    end
    out << "}"
    out << ''
  end
end
