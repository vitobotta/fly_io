# frozen_string_literal: true

module FlyIO
  module Resources
    module_function

    def install!
      OperationRegistry.resources.each do |resource_name, operations|
        constant_name = resource_name.split("_").map(&:capitalize).join
        klass = if const_defined?(constant_name, false)
                  const_get(constant_name, false)
                else
                  const_set(constant_name, Class.new(Base))
                end
        operations.each do |operation|
          next if klass.public_method_defined?(operation.ruby_method.to_sym, false)

          klass.define_method(operation.ruby_method) do |**arguments|
            invoke(operation, arguments)
          end
        end
      end
    end

    def class_for(resource_name)
      install!
      const_get(resource_name.split("_").map(&:capitalize).join, false)
    end
  end
end
