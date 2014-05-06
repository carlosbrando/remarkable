module Remarkable
  module ActionController

    # Macro stubs makes stubs and expectations easier, more readable and DRY.
    #
    # == Example
    #
    # Let's jump off to an example:
    #
    #   describe ProjectsController do
    #     describe :get => :show, :id => 37 do
    #       expects :find, :on => Project, :with => '37', :returns => proc { mock_project }
    #
    #       should_assign_to :project, :with => proc { mock_project }
    #       should_render_template 'show'
    #
    #       describe Mime::XML do
    #         should_assign_to :project
    #         should_respond_with_content_type Mime::XML
    #       end
    #     end
    #   end
    #
    # See how the spec is readable: a ProjectsController responding to get show
    # expects :find on Project which a mock project and then should assign to
    # project and render template 'show'.
    #
    # Each macro before asserting will check if an action was already performed and
    # if not, it runs the expectations and call the action.
    #
    # In other words, should assign to macro is basically doing:
    #
    #   it 'should assign to project' do
    #     Project.should_receive(:find).with('37').and_return(mock_project)
    #     get :show, :id => '37'
    #     assigns(:project).should == mock_project
    #   end
    #
    # By default, all macros perform expectations. You can change
    # this behavior sending :with_stubs or :with_expectations as options:
    #
    #   should_assign_to       :project, :with_stubs => true
    #   should_render_template 'show', :with_expectations => false
    #
    # This also works in the rspec way:
    #
    #   it { should assign_to(:project).with_stubs                   }
    #   it { should render_template('show').with_expectations(false) }
    #
    # == Attention!
    #
    # If you need to check that an array is being sent to a method, you need to
    # give an array inside another array, for example:
    #
    #   expects :comment_ids=, :on => Post, :with => [1,2,3]
    #
    # Is the same as:
    #
    #   Post.comment_ids = (1, 2, 3)
    #
    # And it won't work. The right way to handle this is:
    #
    #   expects :comment_ids=, :on => Post, :with => [[1,2,3]]
    #
    # == mock_models
    #
    # You don't have to play with proc all the time. You can call mock_models which
    # creates two class methods that simply returns a proc and a instance method that
    # do the actual mock.
    #
    #   describe ProjectsController do
    #     mock_models :project
    #
    # And it creates:
    #
    #   def self.project_proc
    #     proc { mock_project }
    #   end
    #
    #   # To be used on index actions
    #   def self.projects_proc
    #     proc { [mock_project] }
    #   end
    #
    #   def mock_project(stubs={})
    #     @project ||= mock_model(Project, stubs)
    #   end
    #
    # Then you can replace those lines:
    #
    #    expects :find, :on => Project, :with => '37', :returns => proc { mock_project }
    #    should_assign_to :project, :with => proc { mock_project }
    #
    # For:
    #
    #    expects :find, :on => Project, :with => '37', :returns => project_proc
    #    should_assign_to :project, :with => project_proc
    #
    # = Give me more!
    #
    # If you need to set the example group description, you can also call <tt>get</tt>,
    # <tt>post</tt>, <tt>put</tt> and <tt>delete</tt> methods:
    #
    #   describe 'my description' do
    #     get :show, :id => 37
    #
    # Things start to get even better when we start to talk about nested resources.
    # After our ProjectsController is created, we want to create a TasksController:
    #
    #   describe TasksController do
    #     params :project_id => '42' #=> define params for all requests
    #
    #     # Those two expectations get inherited in all describe groups below
    #     expects :find_by_title, :on => Project, :with => '42', :returns => project_proc
    #     expects :tasks, :and_return => Task
    #
    #     describe :get => :show, :id => '37' do
    #       expects :find, :with => '37', :and_return => task_proc
    #
    #       should_assign_to :project, :task
    #       should_render_template 'show'
    #     end
    #   end
    #
    # As you noticed, you can define parameters that will be available to all requests,
    # using the method <tt>params</tt>.
    #
    # Finally if you need to write a spec by hand, you can invoke the action and
    # expectations with run_action!, run_expectations! and run_stubs!. Examples:
    #
    #   describe :get => :new do
    #     expects :new, :on => Project, :returns => project_proc
    #
    #     it "should do something different" do
    #       run_action!
    #       # do you assertions here
    #     end
    #   end
    #
    # = Performance!
    #
    # Remarkable comes with a new way to speed up your tests. It performs the
    # action inside a before(:all), so you can do:
    #
    #   describe "responding to GET show" do
    #     get! :show, :id => 37
    #
    #     should_assign_to :task
    #     should_render_template :show
    #   end
    #
    # Or in the compact way:
    #
    #   describe :get! => :show, :id => 37
    #
    # The action will be performed just once before running the macros. If any
    # error happens while performing the action, rspec will output an error
    # but ALL the examples inside the example group (describe) won't be run.
    #
    # By now, the bang methods works only when integrate_views is true and this
    # is when you must see a bigger performance gain.
    #
    # This feature comes with some rspec and rspec rails tweakings. So if you want
    # to do something before the action is performed (stubs something or log
    # someone in session), you have to do it giving a block to the action method:
    #
    #   get! :show, :id => 37 do
    #     login_as(mock_user)
    #   end
    #
    # You can still use the compact way and give the block:
    #
    #   describe :get => :show, :id => 37 do
    #     get! do
    #       login_as(mock_user)
    #     end
    #   end
    #
    module MacroStubs
      HTTP_VERBS_METHODS = [:get, :get!, :post, :post!, :put, :put!, :delete, :delete!]

      def self.included(base) #:nodoc:
        base.extend ClassMethods
        base.class_inheritable_reader :expects_chain, :default_action, :default_mime,
                                      :default_verb, :default_params, :default_xhr,
                                      :before_all_block
        base.class_eval do
          class << self
            alias_method :context, :describe
          end
        end
      end

      module ClassMethods

        # Creates a chain that will be evaluated as stub or expectation. The
        # first parameter is the method expected. You can also specify multiple
        # methods to stub and give a block to calculate the returned value. See
        # examples below.
        #
        # == Options
        #
        # * <tt>:on</tt> - Tell which object will receive the expected method.
        #   This option is always required.
        #
        # * <tt>:with</tt> - Tell each parameters will be sent with the expected
        #   method. This option is used only in expectations and is optional.
        #
        # * <tt>:returns</tt> - Tell what the expectations should return. Not
        #   required.
        #
        # * <tt>:times</tt> - The number of times the object will receive the
        #   method. Used only in expectations and when not given, defaults to 1.
        #
        # * <tt>:ordered</tt> - When true specifies that expectations should
        #   be received in order.
        #
        # == Example
        #
        #   expects :new, :on => Project, :returns => :project_proc, :times => 2
        #
        #   expects :new, :find, :on => Project, :returns => :project_proc
        #
        #   expects :human_attribute_name, :on => Project, :with => :title do |attr|
        #     attr.to_s.humanize
        #   end
        #
        def expects(*args, &block)
          options = args.extract_options!
          options.assert_valid_keys(:on, :with, :returns, :times, :ordered)

          args.each do |arg|
            write_inheritable_array(:expects_chain, [ [ arg, options, block] ])
          end
        end

        # The mime type of the request. The value given will be called transformed
        # into a string and set in the @request.env['HTTP_ACCEPT'] variable.
        #
        # == Examples
        #
        #   mime Mime::XML
        #   mime 'application/xml+rss'
        #
        def mime(mime)
          write_inheritable_attribute(:default_mime, mime.to_s)
        end

        # The params used for the request. Calls are always nested:
        #
        # == Examples
        #
        #   describe TasksController do
        #     params :project_id => 42
        #
        #     describe :get => :show, :id => 37 do
        #       # will request with params {:id => 37, :project_id => 42}
        #     end
        #   end
        #
        def params(params)
          write_inheritable_hash(:default_params, params)
        end

        # Sets the request to perform a XmlHttpRequest.
        #
        # == Examples
        #
        #   describe TasksController do
        #     xhr!
        #   end
        #
        def xhr!(bool=true)
          write_inheritable_attribute(:default_xhr, bool)
        end

        [:get, :post, :put, :delete].each do |verb|
          module_eval <<-VERB, __FILE__, __LINE__
            # Declares that we want to do a #{verb} request in the given action
            # and with the given params.
            #
            # == Examples
            #
            #   #{verb} :action, :id => 42
            #
            def #{verb}(action, params={})
              params(params)
              write_inheritable_attribute(:default_verb, #{verb.inspect})
              write_inheritable_attribute(:default_action, action)
            end
          VERB
        end

        [:get!, :post!, :put!, :delete!].each do |verb|
          module_eval <<-VERB, __FILE__, __LINE__
            # Declares that we want to do a #{verb} request in the given action
            # and with the given params, but the action is performed just once
            # in the describe group. In other words, it's performed in a
            # before(:all) filter.
            #
            # == Examples
            #
            #   #{verb} :action, :id => 42
            #
            def #{verb}(action=nil, params={}, &block)
              #{verb.to_s.chop}(action, params) if action
              write_inheritable_array(:before_all_block, [block]) if block
              run_callbacks_once!
            end
          VERB
        end

        # Undefine the method run_callbacks so rspec won't run them in the
        # before and after :each cycle. Then we redefine it as run_callbacks_once,
        # which will be used as an before(:all) and after(:all) filter.
        #
        def run_callbacks_once!(&block) #:nodoc:
          unless instance_methods.any?{|m| m.to_s == 'run_callbacks_once' }
            alias_method :run_callbacks_once, :run_callbacks
            class_eval "def run_callbacks(*args); end"

            before(:all) do
              setup_mocks_for_rspec
              run_callbacks_once :setup

              before_all_block.each do |block|
                instance_eval(&block)
              end if before_all_block

              run_action!
              verify_mocks_for_rspec
              teardown_mocks_for_rspec
            end

            after(:all) do
              run_callbacks_once :teardown
            end
          end
        end

        # Overwrites describe to provide quick action description with I18n.
        #
        # You can now do:
        #
        #   describe :get => :show, :id => 37
        #
        # Which is the same as:
        #
        #   describe 'responding to #GET show' do
        #     get :show, :id => 37
        #
        # And do this:
        #
        #   describe Mime::XML
        #
        # Which is the same as:
        #
        #   describe 'with xml' do
        #     mime Mime::XML
        #
        # The string can be localized using I18n. An example yml file is:
        #
        #   locale:
        #     remarkable:
        #       action_controller:
        #         responding: "responding to #%{verb} %{action}"
        #         mime_type: "with %{format} (%{content_type})"
        #
        # And load the locale file with:
        #
        #   Remarkable.add_locale locale_path
        #
        def describe(*args, &block)
          options = args.first.is_a?(Hash) ? args.first : {}
          verb    = (options.keys & HTTP_VERBS_METHODS).first

          if verb
            action = options.delete(verb)
            verb   = verb.to_s

            description = Remarkable.t 'remarkable.action_controller.responding',
                                        :default => "responding to \#%{verb} %{action}",
                                        :verb => verb.sub('!', '').upcase, :action => action

            send_args = [ verb, action, options ]
          elsif args.first.is_a?(Mime::Type)
            mime = args.first

            description = Remarkable.t 'remarkable.action_controller.mime_type',
                                        :default => "with #{mime.to_sym}",
                                        :format => mime.to_sym, :content_type => mime.to_s

            send_args = [ :mime, mime ]
          else # return if no special type was found
            return super(*args, &block)
          end

          args.shift
          args.unshift(description)

          # Creates an example group, send the method and eval the given block.
          #
          example_group = super(*args) do
            send(*send_args)
            instance_eval(&block)
          end
        end
        
        # Creates mock methods automatically.
        #
        # == Options
        #
        # * <tt>:as</tt> -  Used to set the model . For example, if you have
        #   Admin::Task model, you have to tell the name of the class to be
        #   mocked:
        #
        #      mock_models :admin_task, :as => "Admin::Task"
        #
        # * <tt>:class_method</tt> - When set to false, does not create the
        #   class method which returns a proc.
        #
        # == Examples
        #
        # Doing this:
        #
        #   describe ProjectsController do
        #     mock_models :project
        #   end
        #
        # Will create one instance and two class mock methods for you:
        #
        #   def self.project_proc
        #     proc { mock_project }
        #   end
        #
        #   # To be used on index actions
        #   def self.projects_procs
        #     proc { [ mock_project ] }
        #   end
        #
        #   def mock_project(stubs={})
        #     @project ||= mock_model(Project, stubs)
        #   end
        #
        # If you want to create just the instance method, you can give
        # :class_method => false as option.
        #
        def mock_models(*models)
          options = models.extract_options!
          options = { :class_method => true }.merge(options)

          models.each do |model|
            model = model.to_s
            klass = options[:as] || model.classify

            if options[:class_method]
              (class << self; self; end).class_eval <<-METHOD
                def #{model}_proc; proc { mock_#{model} }; end
                def #{model.pluralize}_proc; proc { [ mock_#{model} ] }; end

                alias :mock_#{model} :#{model}_proc
                alias :mock_#{model.pluralize} :#{model.pluralize}_proc
              METHOD
            end

            self.class_eval <<-METHOD
              def mock_#{model}(stubs={})
                @#{model} ||= mock_model(#{klass}, stubs)
              end
            METHOD
          end
        end
        alias :mock_model :mock_models

      end

      protected

        # Evaluates the expectation chain as stub or expectations.
        #
        def evaluate_expectation_chain(use_expectations=true) #:nodoc:
          return if self.expects_chain.nil?

          self.expects_chain.each do |method, options, block|
            object = evaluate_value(options[:on])
            raise ScriptError, "You have to give me :on as an option when calling :expects." if object.nil?

            if use_expectations
              chain = object.should_receive(method)

              if options.key?(:with)
                with = evaluate_value(options[:with])

                chain = if with.is_a?(Array)
                  chain.with(*with)
                else
                  chain.with(with)
                end
              end

              times = options[:times] || 1
              chain = chain.exactly(times).times

              chain = chain.ordered if options[:ordered]
            else
              chain = object.stub!(method)
            end

            chain = if block
              chain.and_return(&block)
            else
              return_value = evaluate_value(options[:returns])
              chain.and_return(return_value)
            end
          end
        end

        # Instance method run_stubs! if someone wants to declare additional
        # tests and call the stubs inside of it.
        #
        def run_stubs!
          evaluate_expectation_chain(false)
        end

        # Instance method run_expectations! if someone wants to declare
        # additional tests and call the stubs inside of it.
        #
        def run_expectations!
          evaluate_expectation_chain(true)
        end

        # Run the action declared in the describe group, but before runs also
        # the expectations. If an action was already performed, it doesn't run
        # anything at all and returns false.
        #
        # The first parameter is if you want to run expectations or stubs. You
        # can also supply the verb (get, post, put or delete), which action to
        # call, parameters, the mime type and if a xhr should be performed. If
        # any of those parameters are supplied, they override the current
        # definition.
        #
        def run_action!(use_expectations=true, verb=nil, action=nil, params=nil, mime=nil, xhr=nil)
          return false if controller.send(:performed?)

          evaluate_expectation_chain(use_expectations)

          mime   ||= default_mime
          verb   ||= default_verb
          action ||= default_action
          params ||= default_params
          xhr    ||= default_xhr

          raise ScriptError, "No action was performed or declared." unless verb && action

          request.env["HTTP_ACCEPT"] ||= mime.to_s                if mime
          request.env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest' if xhr
          send(verb, action, params)
        end

        # Evaluate a given value.
        #
        # This allows procs to be given to the expectation chain and they will
        # be evaluated in the instance binding.
        #
        def evaluate_value(duck) #:nodoc:
          if duck.is_a?(Proc)
            self.instance_eval(&duck)
          elsif duck.is_a?(Array)
            duck.map{|child_duck| evaluate_value(child_duck) }
          else
            duck
          end
        end

    end
  end
end
