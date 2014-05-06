module Remarkable
  module DSL
    # This module is responsable for create optional handlers and providing macro
    # configration blocks. Consider the matcher below:
    #
    #   class AllowValuesForMatcher < Remarkable::ActiveRecord::Base
    #     arguments :collection => :attributes, :as => :attribute
    #
    #     optional :message
    #     optional :in, :splat => true
    #     optional :allow_nil, :allow_blank, :default => true
    #   end
    #
    # This allow the matcher to be called as:
    #
    #   it { should allow_values_for(:email).in("jose.valim@gmail.com", "jose@another.com").message(:invalid).allow_nil }
    #
    # It also allow macros to be configured with blocks:
    #
    #   should_allow_values_for :email do |m|
    #     m.message :invalid
    #     m.allow_nil
    #     m.in "jose.valim@gmail.com"
    #     m.in "jose@another.com"
    #   end
    #
    # Which could be also writen as:
    #
    #   should_allow_values_for :email do |m|
    #     m.message = :invalid
    #     m.allow_nil = true
    #     m.in = [ "jose.valim@gmail.com", "jose@another.com" ]
    #   end
    #
    # The difference between the them are: 1) optional= always require an argument
    # even if :default is given. 2) optional= always overwrite all previous values
    # even if :splat is given.
    #
    # Blocks can be also given when :block => true is set:
    #
    #   should_set_session :user_id do |m|
    #     m.to { @user.id }
    #   end
    #
    # == I18n
    #
    # Optionals will be included in description messages if you assign them
    # properly on your locale file. If you have a validate_uniqueness_of
    # matcher with the following on your locale file:
    #
    #   description: validate uniqueness of %{attributes}
    #   optionals:
    #     scope:
    #       positive: scoped to %{inspect}
    #     case_sensitive:
    #       positive: case sensitive
    #       negative: case insensitive
    #
    # When invoked like below will generate the following messages:
    #
    #   validate_uniqueness_of :project_id, :scope => :company_id
    #   #=> "validate uniqueness of project_id scoped to :company_id"
    #
    #   validate_uniqueness_of :project_id, :scope => :company_id, :case_sensitive => true
    #   #=> "validate uniqueness of project_id scoped to :company_id and case sensitive"
    #
    #   validate_uniqueness_of :project_id, :scope => :company_id, :case_sensitive => false
    #   #=> "validate uniqueness of project_id scoped to :company_id and case insensitive"
    #
    # == Interpolation options
    #
    # The default interpolation options available are "inspect" and "value". Whenever
    # you use :splat => true, it also adds a new interpolation option called %{sentence}.
    #
    # Given the following matcher call:
    #
    #   validate_uniqueness_of :id, :scope => [ :company_id, :project_id ]
    #
    # The following yml setting and outputs are:
    #
    #    scope:
    #      positive: scoped to %{inspect}
    #      # Outputs: "validate uniqueness of project_id scoped to [ :company_id, :project_id ]"
    #
    #      positive: scoped to %{value}
    #      # Outputs: "validate uniqueness of project_id scoped to company_idproject_id"
    #
    #      positive: scoped to %{value}
    #      # Outputs: "validate uniqueness of project_id scoped to company_id and project_id"
    #
    # == Interpolation keys
    #
    # Three keys are available to be used in I18n files and control how optionals
    # are appended to your description:
    #
    #   * <tt>positive</tt> - When the optional is given and it evaluates to true (everything but false and nil).
    #   * <tt>negative</tt> - When the optional is given and it evaluates to false (false or nil).
    #   * <tt>not_given</tt> - When the optional is not given.
    #
    module Optionals

      OPTIONAL_KEYS = [ :positive, :negative, :not_given ]

      def self.included(base) #:nodoc:
        base.extend ClassMethods
      end

      module ClassMethods

        protected

          # Creates optional handlers for matchers dynamically.
          #
          # == Options
          #
          # * <tt>:default</tt> - The default value for this optional
          # * <tt>:alias</tt>  - An alias for this optional
          # * <tt>:splat</tt>  - Should be true if you expects multiple arguments
          # * <tt>:block</tt>  - Tell this optional can also receive blocks
          #
          # == Examples
          #
          #   class AllowValuesForMatcher < Remarkable::ActiveRecord::Base
          #     arguments :collection => :attributes, :as => :attribute
          #
          #     optional :message
          #     optional :in, :splat => true
          #     optional :allow_nil, :allow_blank, :default => true
          #   end
          #
          def optionals(*names)
            options = names.extract_options!

            @matcher_optionals += names
            default = options[:default] ? "=#{options[:default].inspect}" : nil

            block = if options[:block]
              @matcher_optionals_block += names 
              default ||= "=nil"
              ', &block'
            else
              nil
            end

            splat = if options[:splat]
              @matcher_optionals_splat += names
              '*'
            else
              nil
            end

            names.each do |name|
              class_eval <<-END, __FILE__, __LINE__
                def #{name}(#{splat}value#{default}#{block})
                  @options ||= {}
                  #{"@options[:#{name}] ||= []" if splat}
                  @options[:#{name}] #{:+ if splat}= #{"block ||" if block} value
                  self
                end
                def #{name}=(value)
                  @options ||= {}
                  @options[:#{name}] = value
                  self
                end
              END
            end

            class_eval %{
              alias :#{options[:alias]} :#{names.last}
              alias :#{options[:alias]}= :#{names.last}=
            } if options[:alias]

            # Call unique to avoid duplicate optionals.
            @matcher_optionals.uniq!
          end
          alias :optional :optionals

          # Instead of appending, prepend optionals to the beginning of optionals
          # array. This is important because the optionals declaration order 
          # changes how the description message is generated.
          #
          def prepend_optionals(*names)
            current_optionals  = @matcher_optionals.dup
            @matcher_optionals = []
            optional(*names)
            @matcher_optionals += current_optionals
            @matcher_optionals.uniq!
          end
          alias :prepend_optional :prepend_optionals

      end

      # Overwrites description to support optionals. Check <tt>optional</tt> for
      # more information.
      #
      def description(options={}) #:nodoc:
        message = super(options)
        message.strip!

        optionals = self.class.matcher_optionals.map do |optional|
          if @options.key?(optional)
            value = @options[optional]

            defaults = [ (value ? :positive : :negative) ]
            # If optional is a symbol and it's not any to any of the reserved symbols, search for it also
            defaults.unshift(value) if value.is_a?(Symbol) && !OPTIONAL_KEYS.include?(value)
            defaults << ''

            options = { :default => defaults, :inspect => value.inspect, :value => value.to_s }

            if self.class.matcher_optionals_splat.include?(optional)
              value = [ value ] unless Array === value
              options[:sentence] = array_to_sentence(value, true)
            end

            translate_optionals_with_namespace(optional, defaults.shift, options)
          else
            translate_optionals_with_namespace(optional, :not_given, :default => '')
          end
        end.compact

        message << ' ' << array_to_sentence(optionals)
        message.strip!
        message
      end

      def translate_optionals_with_namespace(optional, key, options={}) #:nodoc:
        scope = "#{matcher_i18n_scope}.optionals.#{optional}"

        translation = Remarkable.t key, options.merge!(:scope => scope)
        return translation unless translation.empty?

        parent_scope = scope.split('.')
        parent_scope.delete_at(-3)
        translation = Remarkable.t key, options.merge!(:scope => parent_scope)
        return translation unless translation.empty?

        nil
      end

    end
  end
end
