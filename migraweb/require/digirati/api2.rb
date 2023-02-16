#!/usr/bin/env ruby

require 'digest/md5'
require 'net/http'
require 'rexml/document'

#--
# TODO:
#   - handle errors
#   - debug mode
#++

module Digirati

  # This module implements the Digirati API version 2. You are not supposed
  # to use it directly. Refer to the documentation for module Digirati
  # instead. 
  module API2
    class Interface < Digirati::API::Interface
      def self.production(x = true); trait :production, x end

      # Catch missing methods and assume they are API requests.
      private
      def self.method_missing(meth, parms)
        # Camelize method name.
        meth = meth.to_s.split(/_/).map do |s|
          s == "id" ? s.upcase : s.capitalize
        end.join
        cmd = application ? "#{application}_#{meth}" : meth
        API::transaction do |t|
          t.authenticate :user => user, :password => password,
                         :production => production
          t.parameter parms
          t.command cmd
          t.debug if debug
        end
      end
    end

    # An API 2 transaction.
    class Transaction
      attr_reader :values

      # Instantiates a new Transaction object. The +parms+ hash may contain
      # the keys +:method+, +:url+ and +:folder+, which override de defaults
      # of 'POST', 'api.digirati.com.br' and '/', respectively.
      def initialize(parms = {})
        info = {
          :method => 'POST',
          :url    => 'api.digirati.com.br',
          :folder => '/'
        }.merge(parms)

        @folder     = info[:folder]
        @url        = info[:url]
        @debug      = false
        @auth       = nil
        @parms      = []
        @values     = {}
      end

      # Adds authentication information to the transaction. The +opts+ hash
      # is expected to contain the +:user+ and +:password+ keys. The
      # +:production+ key is optional and defaults to +true+.
      def authenticate(opts)
        info = { :production => true }.merge(opts)
        raise ArgumentError unless info[:user] and info[:password]
        @auth = REXML::Element.new('auth')
        @auth.add_attribute('user', info[:user])
        @auth.add_attribute('pass', Digest::MD5.hexdigest(info[:password]))
        @production = info[:production]
      end

      # Sets +cmd+ as the commands for this transaction. Optionally,
      # authentication information for this command may be passed in the
      # +opts+ hash;
      def command(cmd, opts = {})
        raise ArgumentError, "Invalid command" unless cmd =~ /^\w+$/
        @cmd = REXML::Element.new('command')
        @cmd.add_attribute('name', cmd)
        authenticate(opts) if opts[:user] and opts[:password]
      end

      # Adds parameters do the transaction. The +parms+ argument must be
      # a hash with parameter name and value pairs.
      def parameter(parms)
        parms.each do |name, value|
          param = REXML::Element.new('param')
          param.add_element('name')
          param.elements['name'].text = name
          add_value(param, value)
          @parms << param
        end
      end

      alias_method :parameters, :parameter

      # Commit the transaction and parse its response.
      def commit
        build_request.write(request = '')
        path = @folder + 'index.php'
        begin
          conn = Net::HTTP.new(@url)
          resp = conn.post(path, request, 'Content-type' => 'text/xml')
        rescue Exception => e
          raise API::Error, e
        end
        unless resp.is_a? Net::HTTPSuccess
          raise API::Error, "Request error"
        end
        parse_response(resp.body)
      end

      def debug
        @debug = true
      end

      private
      def build_request
        xml = REXML::Document.new
        xml.add REXML::XMLDecl.new("1.0", "UTF-8")
        xml.add_element('apirequest')
        request = xml.elements['apirequest']
        request.add_element('debug')
        request.elements['debug'].add_attribute('mode', @debug ? '1' : '0')
        request.add_element('istest')
        request.elements['istest'].add_attribute('value',
                                                   @production ? '0' : '1')
        request.add_element @auth
        @parms.each { |p| request.add_element p }
        request.add_element @cmd
        return xml
      end

      private
      def add_value(xml, value)
        xml.add_element('value')
        case value
        when String, Numeric, TrueClass, FalseClass
          xml.elements['value'].text = value
        when Array
          xml.elements['value'].add_element('struct')
          struct = xml.elements['value'].elements['struct']
          value.each_with_index { |val, i| build_struct(struct, i, val) }
        when Hash
          xml.elements['value'].add_element('struct')
          struct = xml.elements['value'].elements['struct']
          value.each { |key, val| build_struct(struct, key, val) }
        end
      end

      private
      def build_struct(xml, key, val)
        member = REXML::Element.new('member')
        member.add_element('name')
        member.elements['name'].text = key
        add_value(member, val)
        xml.add_element(member)
      end

      private
      def parse_response(data)
        if @debug
          puts data
          exit
        end

        begin
          doc = REXML::Document.new(data)
        rescue REXML::ParseException => e
          raise API::Error, e
        end

        error = doc.elements["//ErroMsg"]
        if error
          # XXX ARGH!
          raise API::CommandError.new(@cmd, error.to_s)
        end

        doc.elements.each('//result/value') do |value|
          @values[@cmd.attributes['name']] = convert_xml(value)
        end
      end

      private
      def convert_xml(element)
        values = {}
        members = element.get_elements('struct/member')
        return element.text if members.empty? # not a struct
        members.each do |member|
          name = member.elements['name'].text
          value = member.elements['value']
          case value.attributes['type']
          when 'string'
            values[name] = value.text
          when 'integer'
            values[name] = value.text.to_i
          when 'double'
            values[name] = value.text.to_f
          when 'boolean'
            values[name] = (value.text)? true : false
          when 'NULL'
            values[name] = nil
          when 'array'
            values[name] = convert_xml(value)
          end
        end
        return values
      end
    end
  end
end
