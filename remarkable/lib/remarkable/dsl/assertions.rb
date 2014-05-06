module Remarkable
  module DSL
    # This module is responsable to create a basic matcher structure using a DSL.
    #
    # A matcher that checks if an element is included in an array can be done
    # just with:
    #
    #   class IncludedMatcher < Remarkable::Base
    #     arguments :value
    #     assertion :is_included?
    #
    #     protected
    #       def is_included?
    #         @subject.include?(@value)
    #       end
    #   end
    #
    # As you have noticed, the DSL also allows you to remove the messages from
    # matcher. Since it will look for it on I18n yml file.
    #
    # If you want to create a matcher that accepts multile values to be tested,
    # you just need to do:
    #
    #   class IncludedMatcher < Remarkable::Base
    #     arguments :collection => :values, :as => :value
    #     collection_assertion :is_included?
    #
    #     protected
    #       def is_included?
    #         @subject.include?(@value)
    #       end
    #   end
    #
    # Notice that the :is_included? logic didn't have to change, because Remarkable
    # handle this automatically for you.
    #
    module Assertions

      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end

      module ClassMethods

        protected

          # It sets the arguments your matcher receives on initialization.
          #
          # == Options
          #
          # * <tt>:collection</tt> - if a collection is expected.
          # * <tt>:as</tt> - how each item of the collection will be available.
          # * <tt>:block</tt> - tell the matcher can receive blocks as argument and store
          #                     them under the variable given.
          #
          # Note: the expected block cannot have arity 1. This is already reserved
          # for macro configuration.
          #
          # == Examples
          #
          # Let's see for each example how the arguments declarion reflects on
          # the matcher API:
          #
          #   arguments :assign
          #   # Can be called as:
          #   #=> should_assign :task
          #   #=> should_assign :task, :with => Task.new
          #
          # This is roughly the same as:
          #
          #   def initialize(assign, options = {})
          #     @assign   = name
          #     @options = options
          #   end
          #
          # As you noticed, a matcher can always receive options on initialization.
          # If you have a matcher that accepts only options, for example,
          # have_default_scope you just need to call <tt>arguments</tt>:
          #
          #   arguments
          #   # Can be called as:
          #   #=> should_have_default_scope :limit => 10
          #
          #   arguments :collection => :assigns, :as => :assign
          #   # Can be called as:
          #   #=> should_assign :task1, :task2
          #   #=> should_assign :task1, :task2, :with => Task.new
          #
          #   arguments :collection => :assigns, :as => :assign, :block => :buildeer
          #   # Can be called as:
          #   #=> should_assign :task1, :task2
          #   #=> should_assign(:task1, :task2){ Task.new }
          #
          # The block will be available under the instance variable @builder.
          #
          # == I18n
          #
          # All the parameters given to arguments are available for interpolation
          # in I18n. So if you have the following declarion:
          #
          #   class InRange < Remarkable::Base
          #     arguments :range, :collection => :names, :as => :name
          #
          # You will have %{range}, %{names} and %{name} available for I18n
          # messages:
          #
          #   in_range:
          #     description: "have %{names} to be on range %{range}"
          #
          # Before a collection is sent to I18n, it's transformed to a sentence.
          # So if the following matcher:
          #
          #   in_range(2..20, :username, :password)
          #
          # Has the following description:
          #
          #   "should have username and password in range 2..20"
          #
          def arguments(*names)
            options = names.extract_options!
            args = names.dup

            @matcher_arguments[:names] = names

            if collection = options.delete(:collection)
              @matcher_arguments[:collection] = collection

              if options[:as]
                @matcher_arguments[:as] = options.delete(:as)
              else
                raise ArgumentError, 'You gave me :collection as option but have not give me :as as well'
              end

              args          << "*#{collection}"
              get_options    = "#{collection}.extract_options!"
              set_collection = "@#{collection} = #{collection}"
            else
              args          << 'options={}'
              get_options    = 'options'
              set_collection = ''
            end

            if block = options.delete(:block)
              block = :block unless block.is_a?(Symbol)
              @matcher_arguments[:block] = block
            end

            # Blocks are always appended. If they have arity 1, they are used for
            # macro configuration, otherwise, they are stored in the :block variable.
            #
            args << "&block"

            assignments = names.map do |name|
              "@#{name} = #{name}"
            end.join("\n  ")

            class_eval <<-END, __FILE__, __LINE__
              def initialize(#{args.join(',')})
                _builder, block = block, nil if block && block.arity == 1
                #{assignments}
                #{"@#{block} = block" if block}
                @options = default_options.merge(#{get_options})
                #{set_collection}
                run_after_initialize_callbacks
                _builder.call(self) if _builder
              end
            END
          end

          # Declare the assertions that are runned for each element in the collection.
          # It must be used with <tt>arguments</tt> methods in order to work properly.
          #
          # == Examples
          #
          # The example given in <tt>assertions</tt> can be transformed to 
          # accept a collection just doing:
          #
          #   class IncludedMatcher < Remarkable::Base
          #     arguments :collection => :values, :as => :value
          #     collection_assertion :is_included?
          #
          #     protected
          #       def is_included?
          #         @subject.include?(@value)
          #       end
          #   end
          #
          # All further consideration done in <tt>assertions</tt> are also valid here. 
          # 
          def collection_assertions(*methods, &block)
            define_method methods.last, &block if block_given?
            @matcher_collection_assertions += methods
          end
          alias :collection_assertion :collection_assertions

          # Declares the assertions that are run once per matcher.
          #
          # == Examples
          #
          # A matcher that checks if an element is included in an array can be done
          # just with:
          #
          #   class IncludedMatcher < Remarkable::Base
          #     arguments :value
          #     assertion :is_included?
          #
          #     protected
          #       def is_included?
          #         @subject.include?(@value)
          #       end
          #   end
          #
          # Whenever the matcher is called, the :is_included? action is automatically
          # triggered. Each assertion must return true or false. In case it's false
          # it will seach for an expectation message on the I18n file. In this
          # case, the error message would be on:
          #
          #   included:
          #     description: "check %{value} is included in the array"
          #     expectations:
          #       is_included: "%{value} is included in the array"
          #
          # In case of failure, it will output:
          #
          #   "Expected %{value} is included in the array"
          #
          # Notice that on the yml file the question mark is removed for readability.
          #
          # == Shortcut declaration
          #
          # You can shortcut declaration by giving a name and block to assertion
          # method:
          #
          #   class IncludedMatcher < Remarkable::Base
          #     arguments :value
          #
          #     assertion :is_included? do
          #       @subject.include?(@value)
          #     end
          #   end
          #
          def assertions(*methods, &block)
            if block_given?
              define_method methods.last, &block
              protected methods.last
            end

            @matcher_single_assertions += methods
          end
          alias :assertion :assertions

          # Class method that accepts a block or a hash to set matcher's default
          # options. It's called on matcher initialization and stores the default
          # value in the @options instance variable.
          #
          # == Examples
          #
          #   default_options do
          #     { :name => @subject.name }
          #   end
          #
          #   default_options :message => :invalid
          #
          def default_options(hash = {}, &block)
            if block_given?
              define_method :default_options, &block
            else
              class_eval "def default_options; #{hash.inspect}; end"
            end
          end
      end

      # This method is responsable for connecting <tt>arguments</tt>, <tt>assertions</tt>
      # and <tt>collection_assertions</tt>.
      #
      # It's the one that executes the assertions once, executes the collection
      # assertions for each element in the collection and also responsable to set
      # the I18n messages.
      #
      def matches?(subject)
        @subject = subject

        run_before_assert_callbacks

        assertions = self.class.matcher_single_assertions
        unless assertions.empty?
          value = send_methods_and_generate_message(assertions)
          return negative? if positive? == !value
        end

        matches_collection_assertions?
      end

      protected

        # You can overwrite this instance method to provide default options on
        # initialization.
        #
        def default_options
          {}
        end

        # Overwrites default_i18n_options to provide arguments and optionals
        # to interpolation options.
        #
        # If you still need to provide more other interpolation options, you can
        # do that in two ways:
        #
        # 1. Overwrite interpolation_options:
        #
        #   def interpolation_options
        #     { :real_value => real_value }
        #   end
        #
        # 2. Return a hash from your assertion method:
        #
        #   def my_assertion
        #     return true if real_value == expected_value
        #     return false, :real_value => real_value
        #   end
        #
        # In both cases, :real_value will be available as interpolation option.
        #
        def default_i18n_options #:nodoc:
          i18n_options = {}

          @options.each do |key, value|
            i18n_options[key] = value.inspect
          end if @options

          # Also add arguments as interpolation options.
          self.class.matcher_arguments[:names].each do |name|
            i18n_options[name] = instance_variable_get("@#{name}").inspect
          end

          # Add collection interpolation options.
          i18n_options.update(collection_interpolation)

          # Add default options (highest priority). They should not be overwritten.
          i18n_options.update(super)
        end

        # Method responsible to add collection as interpolation.
        #
        def collection_interpolation #:nodoc:
          options = {}

          if collection_name = self.class.matcher_arguments[:collection]
            collection_name = collection_name.to_sym
            collection = instance_variable_get("@#{collection_name}")
            options[collection_name] = array_to_sentence(collection) if collection

            object_name = self.class.matcher_arguments[:as].to_sym
            object = instance_variable_get("@#{object_name}")
            options[object_name] = object if object
          end

          options
        end

        # Send the assertion methods given and create a expectation message
        # if any of those methods returns false.
        #
        # Since most assertion methods ends with an question mark and it's not
        # readable in yml files, we remove question and exclation marks at the
        # end of the method name before translating it. So if you have a method
        # called is_valid? on I18n yml file we will check for a key :is_valid.
        #
        def send_methods_and_generate_message(methods) #:nodoc:
          methods.each do |method|
            bool, hash = send(method)

            if positive? == !bool
              parent_scope = matcher_i18n_scope.split('.')
              matcher_name = parent_scope.pop
              method_name  = method.to_s.gsub(/(\?|\!)$/, '')

              lookup = []
              lookup << :"#{matcher_name}.negative_expectations.#{method_name}" if negative?
              lookup << :"#{matcher_name}.expectations.#{method_name}"
              lookup << :"negative_expectations.#{method_name}" if negative?
              lookup << :"expectations.#{method_name}"

              hash = { :scope => parent_scope, :default => lookup }.merge(hash || {})
              @expectation ||= Remarkable.t lookup.shift, default_i18n_options.merge(hash)

              return negative?
            end
          end

          return positive?
        end

        def matches_single_assertions? #:nodoc:
          assertions = self.class.matcher_single_assertions
          send_methods_and_generate_message(assertions)
        end

        def matches_collection_assertions? #:nodoc:
          arguments  = self.class.matcher_arguments
          assertions = self.class.matcher_collection_assertions
          collection = instance_variable_get("@#{self.class.matcher_arguments[:collection]}") || []

          assert_collection(nil, collection) do |value|
            instance_variable_set("@#{arguments[:as]}", value)
            send_methods_and_generate_message(assertions)
          end
        end


    end
  end
end
