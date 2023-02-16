require 'delegate'

#
# = Introduction
#
# This library implements the Digirati API in its two versions. Three
# different interfaces are provided, as detailed below.
#
# == "Assembly-like" interface
#
# This is the the API interface which resembles the original PHP API
# the most. It is known as "assembly-like" because the way it is used
# is similar to assembly programming: push arguments to the stack and
# call an action that will act upon those arguments.
#
# === Example for API version 1
#
#  require 'digirati/api'
#  require 'pp'
#
#  # Create a new transaction, specifying version 1.
#  t = Digirati::API::Transaction.new(:version => 1)
#
#  # Push authentication information, parameters and commands to the "stack".
#  # Notice that the command method expects arguments in the form of a hash
#  # where the keys are application names and the values are command names.
#  t.authenticate :user => 'USER', :password => 'PASSWORD'
#  t.parameter 'dominio' => 'sneakymustard.com'
#  t.command 'clientes' => 'ColetaDados'
#
#  begin
#    # Commit the transaction
#    t.commit
#    pp t.values
#  rescue Digirati::API::Error => e
#    warn "API error: #{e}"
#  rescue Digirati::API::CommandError => e
#    warn "API command error in command `#{e.command}': #{e.error}"
#  end
#
# === Example for API version 2
#
#  require 'digirati/api'
#  require 'pp'
#
#  # Create a new Transaction instance for version 2.
#  t = Digirati::API::Transaction.new(:version => 2)
#
#  # Same as on the previous example, except that there is no notion of
#  # an "application anymore. Related commands are prefixed by a common
#  # string followed by an underscore character.
#  t.authenticate :user => 'USER', :password => 'PASSWORD'
#  t.command 'CL_ColetaDados'
#  t.parameters 'IDCliente' => 66461, 'ArDadosColetar' => 'StFormaPagamento'
#
#  # Commit the transaction. Error handling is not shown, as it works
#  # the same way as in version 1.
#  t.commit
#  pp t.values
#
# == Block interface
#
# This interface uses the transaction method defined on the Digirati::API
# module, which expects a block. It yields a transaction to it, upon which
# the usual methods can be called, and returns the transaction results.
#
# === Example for API version 1
#
#  begin
#    # Digirati::API::transaction accepts a block and yields a transaction
#    # on which authentication, parameters and commands can be specified.
#    # The transaction is automatically commited upon block termination.
#    result = Digirati::API.transaction(:version => 1) do |t|
#      t.authenticate :user => 'USER', :password => 'PASSWORD'
#      t.parameter :dominio => 'sneakymustard.com'
#      t.command :clientes => 'ColetaDados'
#    end
#    pp result
#  rescue Digirati::API::Error => e
#    warn "API error: #{e}"
#  rescue Digirati::API::CommandError => e
#    warn "API command error in command `#{e.command}': #{e.error}"
#  end
#
# === Example for API version 2
#
#  # Usage is pretty straightforward and the differences compared to API
#  # version 1 mentioned on the previous interface also apply here.
#  result = Digirati::API.transaction(:version => 2) do |t|
#    t.authenticate :user => 'USER', :password => 'PASSWORD'
#    t.parameter 'IDCliente' => 66461, 'ArDadosColetar' => 'StFormaPagamento'
#    t.command 'CL_ColetaDados'
#  end
#  pp result
#
# == Class methods interface
#
# This interface uses class methods to configure commonly used parameters
# and avoid the repetition that is inherent in the traditional methods of
# access to the APIs. It allows the user to define a class which sets up
# the basic API information once, and then invoke API commands as class
# methods of this class.
#
# The user-defined classes must inherit from the Interface class defined on
# the appropriate API version implementation. This can be easily done by
# means of ther Digirati::API method, as shown in the examples below.
#
# After defining the interface class, the user must define the username and
# password to access the API. A grouping prefix, here referred to as an
# "application" should be specified if necessary (some global API commands,
# however, have no prefix). If commands from different applications are to
# be called by the same user, a class containing only authentication data
# may be created. Then, classes for each application, inheriting from that
# class, may be created, thus minimizing the repetition of code.
#
# Finally, API commands are called as class methods of the classes defined
# above, as previously mentioned. The convention is that for each command
# FooBar there is a class method foo_bar that can be used. In other words,
# the application names are downcased, and words are separated by an
# underscore character.
#
# Error handling for this interface is analogous to the other interfaces,
# and thus is ommited in the examples that follow.
#
# === Examples
#
#  # Define an interface class for API version 1.
#  class Cliente < Digirati::API 1
#    user        'USER'
#    password    'PASSWORD'
#    application 'clientes2'
#  end
#
#  # Run the API command ColetaDados.
#  result = Cliente.coleta_dados 'dominio' => 'sneakymustard.com'
#
#
#  # Define authentication information for API version 2. This information
#  # can be used for any number of classes that define API 2 applications.
#  class Global < Digirati::API 2
#    user     'USER'
#    password 'PASSWORD'
#  end
#
#  # Define a class for the 'CL' grouping of commands, and use the
#  # authentication information from the Global class define above. The
#  # production method is available only in API 2 and defaults to true.
#  class Cliente < Global
#    application 'CL'
#    production  true
#  end
#
#  # Run a query to the 'CL_ColetaDados' API command.
#  result = Cliente.coleta_dados 'IDCliente' => 66461,
#                                'ArDadosColetar' => 'StFormaPagamento'
#
module Digirati
  DEFAULT_API_VERSION = 2

  # The Digirati::API method works as a wrapper to the available API
  # interfaces. The Interface class of the appropriate API version is
  # returned. User-defined classes inherit from this class to setup the
  # necessary API parameters.
  def API(version = DEFAULT_API_VERSION)
    raise ArgumentError, "Invalid API version." unless version.is_a? Integer
    require (File.expand_path("api#{version}", File.dirname(__FILE__)))
    return const_get("API#{version}")::Interface
  end
  module_function :API

  # This is a wrapper module for the Digirati APIs.
  module API
    # API error.
    class Error < Exception; end

    # API command error.
    class CommandError < Exception
      attr_reader :command, :error

      def initialize(command, error)
        @command = command
        @error   = error
      end

      def to_s
        "#{command}: #{error}"
      end
    end

    # This is a wrapper class for API transactions. Every method is forwarded
    # to an instance of the Transaction class of the appropriate API version.
    class Transaction < SimpleDelegator
      def initialize(parms = {})
        version = parms.delete(:version) || DEFAULT_API_VERSION
        raise ArgumentError, "Invalid API version." unless version.is_a? Integer
        require (File.expand_path("api#{version}", File.dirname(__FILE__)))
        t = Digirati::const_get("API#{version}")::Transaction.new(parms)
        super(t)
      end
    end

    # This method yields a transaction to the given block and commits
    # it afterwards. The results of the transaction are returned.
    def self.transaction(parms = {}) # :yields: transaction
      raise ArgumentError unless block_given?
      t = Transaction.new(parms)
      yield t
      t.commit
      return t.values
    end

    # This class defines the common class methods available in every API
    # version.
    class Interface
      # Dynamically re-define the class methods for further access of
      # the configured value.
      def self.trait(name, val)
        (class << self; self; end).class_eval do
          define_method(name) { val }
        end
        val
      end

      # Class methods below are common to every API version.

      def self.application(x = nil); trait :application, x end
      def self.user(x);              trait :user,        x end
      def self.password(x);          trait :password,    x end
      def self.debug(x = false);     trait :debug,       x end
    end
  end
end
