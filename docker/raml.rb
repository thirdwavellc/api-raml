require 'fileutils'
require 'open-uri'
require 'yaml'

module DescriptionParser

  def description
    if (not @description)
      @description = (@obj.has_key?('description') ? @obj['description'] : '')
      @extended_attributes = _extract_attributes(@description.dup)
    end
    @description
  end

  def clean_description
    if (not @clean_description)
      desc = @description.dup
      while (desc.sub!(/\s*\[.*?\]\s*$/, ''))
      end
      s = since
      desc += " [Since:#{s}]" unless s == '0.0'
      @clean_description = desc
    end
    @clean_description
  end

  def value_of(key)
    description if not @extended_attributes
    key = key.downcase
    return @extended_attributes.has_key?(key) ? @extended_attributes[key] : ''
  end

  def extended_attributes
    if (not @extended_attributes)
      # The "description" method populates the "extended_attributes" attr
      description
    end
    @extended_attributes
  end

  private

  def _extract_attributes(desc)
    attributes = {}
    while (desc.sub!(/\[([^:]+):([^\]]+)\]\s*$/, ''))
      attributes[$1.downcase] = $2
    end
    return attributes
  end

  attr_writer :description, :extended_attributes

end

class Resource
  include DescriptionParser

  def initialize(dict, uri='', inheritedSince='0.0', inheritedVisibility='public')
    @uri = uri
    @obj = dict
    localSince = value_of('since')
    @since = localSince.greaterThanVersion(inheritedSince) \
           ? localSince \
           : inheritedSince
    localVisibility = value_of('visibility')
    if (inheritedVisibility == 'private')
      @visibility = inheritedVisibility
    elsif (localVisibility.length > 0)
      @visibility = localVisibility
    else
      @visibility = 'public'
    end
  end

  def resources
    @obj.keys.grep(/^\//).map {|e| Resource.new(@obj[e], File.join(@uri, e), @since, @visibility)}
  end

  def all_resources
    list = []
    resources.each do |res|
      list.push(res)
      list += res.all_resources
    end
    list
  end

  def actions
    @obj.keys.find_all{|k| k =~ /^(get|put|post|delete)$/}.map{|e| Action.new(@obj[e], e, @since, @visibility)}
  end

  def drop_resource(res)
    @obj.delete_if {|key, value| key == res.uri}
  end

  def drop_action(action)
    @obj.delete_if {|key, value| key == action.type}
  end

  def method_missing(method, *args, &block)
    if (@obj.has_key?(method))
      return @obj[method]
    end
    return '' if method == 'description'
    raise "Unknown attribute: #{method}"
  end

  attr_reader :since, :uri, :visibility

end

class Action
  include DescriptionParser

  def initialize(dict, type, inheritedSince='0.0', inheritedVisibility='public')
    @type = type
    @obj = dict
    localSince = value_of('since')
    @since = localSince.greaterThanVersion(inheritedSince) \
           ? localSince \
           : inheritedSince
    localVisibility = value_of('visibility')
    if (inheritedVisibility == 'private')
      @visibility = inheritedVisibility
    elsif (localVisibility.length > 0)
      @visibility = localVisibility
    else
      @visibility = 'public'
    end
  end

  def headers
    return [] unless @obj.has_key?('headers') and @obj['headers'].is_a?(Hash)
    @obj['headers'].keys.map {|k| Header.new(@obj['headers'][k], k, @since, @visibility)}
  end

  def responses
    return [] unless @obj.has_key?('responses')
    @obj['responses'].keys.map {|k| Response.new(@obj['responses'][k], k, @since, @visibility)}
  end

  def drop_header(header)
    @obj['headers'].delete_if {|key, value| key == header.name}
  end

  def drop_response(response)
    @obj['responses'].delete_if {|key, value| key == response.code}
  end

  def method_missing(method, *args, &block)
    if (@obj.has_key?(method))
      return @obj[method]
    end
    return '' if method == 'description'
    raise "Unknown attribute: #{method}"
  end

  attr_reader :since, :type, :visibility

end

class Header
  include DescriptionParser

  def initialize(dict, name, inheritedSince='0.0', inheritedVisibility='public')
    @name = name
    @obj = dict
    localSince = value_of('since')
    @since = localSince.greaterThanVersion(inheritedSince) \
           ? localSince \
           : inheritedSince
    localVisibility = value_of('visibility')
    if (inheritedVisibility == 'private')
      @visibility = inheritedVisibility
    elsif (localVisibility.length > 0)
      @visibility = localVisibility
    else
      @visibility = 'public'
    end
  end

  def method_missing(method, *args, &block)
    if (@obj.has_key?(method))
      return @obj[method]
    end
    return '' if method == 'description'
    raise "Unknown attribute: #{method}"
  end

  attr_reader :name, :since, :visibility

end

class Response
  include DescriptionParser

  def initialize(dict, code, inheritedSince='0.0', inheritedVisibility='public')
    @code = code
    @obj = dict
    localSince = value_of('since')
    @since = localSince.greaterThanVersion(inheritedSince) \
           ? localSince \
           : inheritedSince
    localVisibility = value_of('visibility')
    if (inheritedVisibility == 'private')
      @visibility = inheritedVisibility
    elsif (localVisibility.length > 0)
      @visibility = localVisibility
    else
      @visibility = 'public'
    end
  end

  def method_missing(method, *args, &block)
    if (@obj.has_key?(method))
      return @obj[method]
    end
    return '' if method == 'description'
    raise "Unknown attribute: #{method}"
  end

  attr_reader :code, :since, :visibility

end

class RAML < Resource

  def initialize(infile)
    inputdir = File.dirname(infile)
    input = open(infile, 'r:UTF-8') do |f|
      inlined_raml = ''
      f.readlines.each do |line|
        if (line !~ /^\s*#/ and line =~ /\!include\s+(.*)/)
          incfile = $1
          incfile = File.join(inputdir, incfile) unless File.exists?(incfile)
          inc = open(incfile).read
          inlined_raml += inc
        else
          inlined_raml += line
        end
      end
      inlined_raml
    end

    super(YAML.load(input))
  end

  def walknodes(&block)
    return _walknodes(@obj, [], :filter => false, &block)
  end

  def filternodes(&block)
    return _walknodes(@obj, [], :filter => true, &block)
  end

  def dump
    raml = @obj.to_yaml
    raml.sub!(/^---/, "#%RAML 0.8");
    return raml
  end

  private

  def _walknodes(node, keys, options={}, &block)
    return unless node.is_a?(Hash)

    do_filter = options[:filter] || false

    node.keys.each do |key|
      next unless node[key].is_a?(Hash)

      nkeys = keys + [key]
      drop_node = block.call(node[key], nkeys)
      if (do_filter and drop_node)
        node.delete(key)
      end

      _walknodes(node[key], nkeys, options, &block) if node.has_key?(key)
    end
  end

end

class String
  # Extract the specified value from the description where the key/value
  # combintion looks like this: "[Key:Value]"
  # For example: "[Since:1.2]" => "1.2"
  def value_of(pattern)
    if (self =~ /\[#{pattern}:(.*?)\]/i)
      return $1;
    end
    return ''
  end

  # Compare a given version string to current version
  # Will *only* work on strings which are in dotted notation.
  # Examples: "1.10", "3.14.15.9"
  def greaterThanVersion(version)
    Gem::Version.new(self.dup) > Gem::Version.new(version.dup)
  end
end
