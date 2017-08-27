#--
# Copyright 2004, 2005, 2010, 2012 by Jim Weirich (jim.weirich@gmail.com)
# and Mike Subelsky (mike@subelsky.com)
#
# All rights reserved.
#
# This software is available under the MIT license.  See the LICENSE file for details.
#++
#
# = Dependency Injection - Minimal (DIM)
#
# The DIM module provides a minimal dependency injection framework for
# Ruby programs.
#
# Example:
#
#   require 'dim'
#
#   container = Dim::Container.new
#   container.register(:log_file) { "logfile.log" }
#   container.register(:logger) { |c| FileLogger.new(c.log_file) }
#   container.register(:application) { |c|
#     app = Application.new
#     app.logger = c.logger
#     app
#   }
#
#   c.application.run
#
module Dim
  # Thrown when a service cannot be located by name.
  MissingServiceError = Class.new(StandardError)

  # Thrown when a duplicate service is registered.
  DuplicateServiceError = Class.new(StandardError)

  # Thrown by register_env when a suitable ENV variable can't be found
  EnvironmentVariableNotFound = Class.new(StandardError)

  # Dim::Container is the central data store for registering services
  # used for dependency injuction.  Users register services by
  # providing a name and a block used to create the service.  Services
  # may be retrieved by asking for them by name (via the [] operator)
  # or by selector (via the method_missing technique).
  #
  class Container
    attr_reader :parent

    # Create a dependency injection container.  Specify a parent
    # container to use as a fallback for service lookup.
    def initialize(parent=nil)
      @services = {}
      @cache = {}
      @parent = parent || Container
    end

    # Register a service named +name+.  The +block+ will be used to
    # create the service on demand.  It is recommended that symbols be
    # used as the name of a service.
    def register(name,raise_error_on_duplicate = true,&block)
      if @services[name]
        if raise_error_on_duplicate
          fail DuplicateServiceError, "Duplicate Service Name '#{name}'"
        else # delete the service from the cache
          @cache.delete(name)
        end
      end

      @services[name] = block

      self.class.send(:define_method, name) do
        self[name]
      end
    end

    def override(name,&block)
      register(name,false,&block)
    end

    # Lookup a service from ENV variables, or use a default if given; fall back to searching the container and its parents for a default value
    def register_env(name,default = nil)
      if value = ENV[name.to_s.upcase]
        register(name) { value }
      elsif default
        register(name) { default }
      else
        begin
          @parent.service_block(name)
        rescue MissingServiceError
          raise EnvironmentVariableNotFound, "Could not find an ENV variable named '#{name.to_s.upcase}' nor could we find a service named #{name} in the parent container"
        end
      end
    end

    # Lookup a service by name.  Throw an exception if no service is
    # found.
    def [](name)
      @cache[name] ||= service_block(name).call(self)
    end

    # Lookup a service by message selector.  A service with the same
    # name as +sym+ will be returned, or an exception is thrown if no
    # matching service is found.
    def method_missing(sym, *args, &block)
      self[sym]
    end

    # Return the block that creates the named service.  Throw an
    # exception if no service creation block of the given name can be
    # found in the container or its parents.
    def service_block(name)
      @services[name] || @parent.service_block(name)
    end

    # Resets the cached services
    def clear_cache!
      @cache = {}
    end

    # Searching for a service block only reaches the Container class
    # when all the containers in the hierarchy search chain have no
    # entry for the service.  In this case, the only thing to do is
    # signal a failure.
    def self.service_block(name)
      fail(MissingServiceError, "Unknown Service '#{name}'")
    end

    # Check to see if a custom method or service has been registered, returning true or false.
    def service_exists?(name)
      respond_to?(name) || service_block(name)
    rescue Dim::MissingServiceError
      false
    end

    # Given a list of services, check to see if they are available, returning true or false.
    def verify_dependencies(*names)
      names.all? { |name| service_exists?(name) }
    end

    # Given a list of services, check to see if they are available or raise an exception.
    def verify_dependencies!(*names)
      missing_dependencies = names.reject { |name| service_exists?(name) }

      unless missing_dependencies.empty?
        fail Dim::MissingServiceError, "Missing dependencies #{missing_dependencies.join(", ")}"
      end
    end
  end
end
