module EntriesHelper

  # Return all free IP addresses as a JSON object
  def free_ips_json

    # Gather all used IP address from database
    used = []
    used[206] = []
    used[207] = []
    used[186] = []

    Entry.find_all_by_scope('206').each { |e| used[206] << e.ip }
    used[206].uniq!

    Entry.find_all_by_scope('207').each { |e| used[207] << e.ip }
    used[207].uniq!

    Entry.find_all_by_scope('186').each { |e| used[186] << e.ip }
    used[186].uniq!

    # Calculate all possible IP addresses
    possible = []
    possible[206] = []
    possible[207] = []
    possible[186] = []

    [*6..200].each do |i|
      possible[206] << '128.111.206.'+i.to_s
    end

    [*6..200].each do |i|
      possible[207] << '128.111.207.'+i.to_s
    end

    [*1..100].each do |i|
      possible[186] << '128.111.186.'+i.to_s
    end

    # Calculate available IP addresses for each scope
    scope = {}
    scope['206'] = possible[206] - used[206]
    scope['207'] = possible[207] - used[207]
    scope['186'] = possible[186] - used[186]

    # Construct JSON object
    out = '{ "free_ips": { '
    out << ' "scopes": [ '
    scope.each_pair do |k,s|
      out << ' { "id": "'+k+'", '
      out << ' "ips": [ '
      s.each do |ip|
        out << '{ "ip": "'+ip+'" },'
      end
      out.chop! # Removes extraneous comma
      out << '] }, ' 
    end
    out.chop! # Removes extraneous comma 
    out << ' ] } }' 
  end


  def dhcpd_conf
    timestamp = Time.gm(*Entry.find(:first, :order => 'updated_at DESC', :limit => 1).updated_at)
    
    out = "# Last updated #{timestamp}\n\n"
    out << "ddns-update-style none;\n"
    out << "default-lease-time 86400;\n"
    out << "max-lease-time 432000;\n"
    out << "authoritative;\n\n"

    out << "option domain-name \"education.ucsb.edu\";\n"
    out << "option domain-name-servers 128.111.207.95,128.111.1.1;\n\n"

    # Build the ranges for each scope
    scopes = [[186,1,100],[206,6,200],[207,6,200]]
    ranges = []
    scopes.each do |scope|
      sub = scope[0]
      first = scope[1]
      last = scope[2]
      ranges[sub] = []
      used = []
      entries = Entry.find_all_by_scope(sub)
      entries.each { |entry| used << entry.ip unless entry.ip.blank? }
      range_open = false
      range_valid = false 
      start = nil
      stop = nil
      [*first..last].each do |i|
        ip = "128.111.#{sub}.#{i}"
        last_ip = "128.111.#{sub}.#{last}"
        if !used.include?(ip) and !range_open
          start = ip 
          range_open = true
        end
        if !used.include?(ip) and range_open
          stop = ip
        end
        if (used.include?(ip) or (ip == last_ip and !used.include?(last_ip))) and range_open
          ranges[sub] << [start,stop]
          range_open = false
          start = stop = nil
        end
      end
    end

    out << "subnet 128.111.206.0 netmask 255.255.255.0 {\n"
    out << "    option routers 128.111.206.254;\n"
    out << "    pool {\n"
    ranges[206].each { |range| out << "        range #{range[0]} #{range[1]};\n" }
    out << "        deny unknown clients;\n"
    out << "    }\n"
    out << "}\n"

    out << "subnet 128.111.207.0 netmask 255.255.255.0 {\n"
    out << "    option routers 128.111.207.254;\n"
    out << "    pool {\n"
    ranges[207].each { |range| out << "        range #{range[0]} #{range[1]};\n" }
    out << "        deny unknown clients;\n"
    out << "    }\n"
    out << "}\n"

    out << "subnet 128.111.186.0 netmask 255.255.255.0 {\n"
    out << "    option routers 128.111.186.254;\n\n"
    out << "    class \"wireless\" {\n"
    out << "        match if (binary-to-ascii(10,8, \".\", packet(24,4)) = \"128.111.186.252\");\n"
    out << "    }\n\n"
    out << "    pool {\n"
    out << "        allow members of \"wireless\";\n"
    out << "        range 128.111.186.101 128.111.186.199;\n"
    out << "        default-lease-time 14400;\n"
    out << "        max-lease-time 14400;\n"
    out << "    }\n\n" 
    out << "    pool {\n"
    ranges[186].each { |range| out << "        range #{range[0]} #{range[1]};\n" }
    out << "        deny unknown clients;\n"
    out << "    }\n\n"
    out << "}\n"


    out << "group {\n"
    out << "    filename \"wired\";\n"
    Entry.find_all_by_enabled(true).each do |entry|
      out << "        host  #{entry.hostname}  { hardware ethernet #{entry.mac}; "
      out << "fixed-address #{entry.ip}; " unless entry.ip.blank? # Only print the fixed address if an IP is specified.
      out << "}\n"
    end
    out << "}\n\n"


    out << '# File generated successfully' # So we can tell the entire file is generated when we download it.

  end
end
