require 'rexml/document'
class Package < ApplicationModel
  @@root = Rails.root.to_s

  def self.build(data)

    if data[:file]
      xml     = self._read_file( data[:file], data[:root] || true )
      package = self._parse(xml)
    elsif data[:string]
      package = self._parse( data[:string] )
    end

    build_date = REXML::Element.new("build_date")
    build_date.text = Time.now.utc.iso8601
    build_host = REXML::Element.new("build_host")
    build_host.text = Socket.gethostname

    package.root.insert_after( '//zpm/description', build_date )
    package.root.insert_after( '//zpm/description', build_host )
    package.elements.each('zpm/filelist/file') do |element|
      location = element.attributes['location']
      content = self._read_file( location, data[:root] )
      base64  = Base64.encode64(content)
      element.text = base64
    end
    return package.to_s
  end

  def self.install(data)
    if data[:file]
      xml     = self._read_file( data[:file], true )
      package = self._parse(xml)
    elsif data[:string]
      package = self._parse( data[:string] )
    end

    # package meta data
    meta = {
      :name           => package.elements["zpm/name"].text,
      :version        => package.elements["zpm/version"].text,
      :vendor         => package.elements["zpm/vendor"].text,
      :state          => 'uninstalled',
      :created_by_id  => 1,
      :updated_by_id  => 1,
    }

    # verify if package can get installed
    package_db = Package.where( :name => meta[:name] ).first
    if package_db
      if Gem::Version.new( package_db.version ) == Gem::Version.new( meta[:version] )
        raise "Package '#{meta[:name]}-#{meta[:version]}' already installed!"
      end
      if Gem::Version.new( package_db.version ) > Gem::Version.new( meta[:version] )
        raise "Newer version (#{package_db.version}) of package '#{meta[:name]}-#{meta[:version]}' already installed!"
      end

      # uninstall old package
      self.uninstall({
        :name               => package_db.name,
        :version            => package_db.version,
        :migration_not_down => true,
      })
    end

    # store package
    record = Package.create( meta )
    Store.add(
      :object      => 'Package',
      :o_id        => record.id,
      :data        => package.to_s,
      :filename    => meta[:name] + '-' + meta[:version] + '.zpm',
      :preferences => {},
    )

    # write files
    package.elements.each('zpm/filelist/file') do |element|
      location   = element.attributes['location']
      permission = element.attributes['permission'] || '644'
      base64     = element.text
      content    = Base64.decode64(base64)
      content    = self._write_file(location, permission, content)
    end

    # update package state
    record.state = 'installed'
    record.save

    # up migrations
    Package::Migration.migrate( meta[:name] )

    # prebuild assets

    return true
  end

  def self.uninstall( data )

    if data[:string]
      package = self._parse( data[:string] )
    else
      file    = self._get_bin( data[:name], data[:version] )
      package = self._parse(file)
    end

    # package meta data
    meta = {
      :name           => package.elements["zpm/name"].text,
      :version        => package.elements["zpm/version"].text,
    }

    # down migrations
    if !data[:migration_not_down]
      Package::Migration.migrate( meta[:name], 'reverse' )
    end

    package.elements.each('zpm/filelist/file') do |element|
      location   = element.attributes['location']
      permission = element.attributes['permission'] || '644'
      base64     = element.text
      content    = Base64.decode64(base64)
      content    = self._delete_file(location, permission, content)
    end

    # prebuild assets

    # delete package
    record = Package.where(
      :name     => meta[:name],
      :version  => meta[:version],
    ).first
    record.destroy

    return true
  end

  def self._parse(xml)
#    puts xml.inspect
    begin
      package = REXML::Document.new( xml )
    rescue => e
      puts 'ERROR: ' + e.inspect
      return
    end
#    puts package.inspect
    return package
  end

  def self._get_bin( name, version )
    package = Package.where(
      :name     => name,
      :version  => version,
    ).first
    if !package
      raise "No such package '#{name}' version '#{version}'"
    end
    list = Store.list(
      :object => 'Package',
      :o_id   => package.id,
    )

    # find file
    return if !list
    list.first.store_file.data
  end

  def self._read_file(file, fullpath = false)
    if fullpath == false
      location = @@root + '/' + file
    elsif fullpath == true
      location = file
    else
      location = fullpath + '/' + file
    end

    begin
      data = File.open( location, 'rb' )
      contents = data.read
    rescue => e
      raise 'ERROR: ' + e.inspect
    end
    return contents
  end

  def self._write_file(file, permission, data)
    location = @@root + '/' + file

    # rename existing file
    if File.exist?( location )
      backup_location = location + '.save'
      puts "NOTICE: backup old file '#{location}' to #{backup_location}"
      File.rename( location, backup_location )
    end

    # check if directories need to be created
    directories = location.split '/'
    (0..(directories.length-2) ).each {|position|
      tmp_path = ''
      (1..position).each {|count|
        tmp_path = tmp_path + '/' + directories[count].to_s
      }
      if tmp_path != ''
        if !File.exist?(tmp_path)
          Dir.mkdir( tmp_path, 0755)
        end
      end
    }

    # install file
    begin
      puts "NOTICE: install '#{location}' (#{permission})"
      file = File.new( location, 'wb' )
      file.write( data ) 
      file.close
      File.chmod( permission.to_i(8), location )
    rescue => e
      raise 'ERROR: ' + e.inspect
    end
    return true
  end

  def self._delete_file(file, permission, data)
    location = @@root + '/' + file

    # install file
    puts "NOTICE: uninstall '#{location}'"
    File.delete( location )

    # rename existing file
    backup_location = location + '.save'
    if File.exist?( backup_location )
      puts "NOTICE: restore old file '#{backup_location}' to #{location}"
      File.rename( backup_location, location )
    end

    return true
  end

  class Migration < ApplicationModel
    @@root = Rails.root.to_s

    def self.migrate( package, direction = 'normal' )
      location = @@root + '/db/addon/' + package.underscore

      return true if !File.exists?( location )
      migrations_done = Package::Migration.where( :name => package )

      # get existing migrations
      migrations_existing = []
      Dir.foreach(location) {|entry|
        next if entry == '.'
        next if entry == '..'
        migrations_existing.push entry
      }

      # up
      migrations_existing = migrations_existing.sort

      # down
      if direction == 'reverse'
        migrations_existing = migrations_existing.reverse
      end

      migrations_existing.each {|migration|
        next if migration !~ /\.rb$/
        version = nil
        name    = nil
        if migration =~ /^(.+?)_(.*)\.rb$/
          version = $1
          name    = $2
        end
        if !version || !name
          raise "Invalid package migration '#{migration}'"
        end

        # down
        if direction == 'reverse'
          done = Package::Migration.where( :name => package, :version => version ).first
          next if !done
          puts "NOTICE: down package migration '#{migration}'"
          load "#{location}/#{migration}"
          classname = name.camelcase
          Kernel.const_get(classname).down
          record = Package::Migration.where( :name => package, :version => version ).first
          if record
            record.destroy
          end

        # up
        else
          done = Package::Migration.where( :name => package, :version => version ).first
          next if done
          puts "NOTICE: up package migration '#{migration}'"
          load "#{location}/#{migration}"
          classname = name.camelcase
          Kernel.const_get(classname).up
          Package::Migration.create( :name => package, :version => version )
        end
      }
    end
  end
end