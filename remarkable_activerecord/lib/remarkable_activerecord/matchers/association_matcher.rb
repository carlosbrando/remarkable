module Remarkable
  module ActiveRecord
    module Matchers
      class AssociationMatcher < Remarkable::ActiveRecord::Base #:nodoc:
        arguments :macro, :collection => :associations, :as => :association

        optionals :through, :source, :source_type, :class_name, :foreign_key, :dependent, :join_table, :as
        optionals :select, :conditions, :include, :group, :having, :order, :limit, :offset, :finder_sql, :counter_sql
        optionals :uniq, :readonly, :validate, :autosave, :polymorphic, :counter_cache, :default => true

        collection_assertions :association_exists?, :macro_matches?, :through_exists?, :source_exists?,
                              :klass_exists?, :join_table_exists?, :foreign_key_exists?, :polymorphic_exists?,
                              :counter_cache_exists?, :options_match?

        protected

          def association_exists?
            reflection
          end

          def macro_matches?
            reflection.macro == @macro
          end

          def through_exists?
            return true unless @options.key?(:through)
            reflection.through_reflection rescue false
          end

          def source_exists?
            return true unless @options.key?(:through)
            reflection.source_reflection rescue false
          end

          # Polymorphic associations does not have a klass.
          #
          def klass_exists?
            return true if @options[:polymorphic]
            reflection.klass rescue nil
          end

          # has_and_belongs_to_many only works if the tables are in the same
          # database, so we always look for the table in the subject connection.
          #
          def join_table_exists?
            return true unless reflection.macro == :has_and_belongs_to_many
            subject_class.connection.tables.include?(reflection.options[:join_table].to_s)
          end

          def foreign_key_exists?
            return true unless foreign_key_table
            table_has_column?(foreign_key_table_class, foreign_key_table, reflection_foreign_key)
          end

          def polymorphic_exists?
            return true unless @options[:polymorphic]
            klass_table_has_column?(subject_class, reflection_foreign_key.sub(/_id$/, '_type'))
          end

          def counter_cache_exists?
            return true unless @options[:counter_cache]
            klass_table_has_column?(reflection.klass, reflection.counter_cache_column.to_s)
          end

          def options_match?
            actual_options = {}

            @options.keys.each do |key|
              method = :"reflection_#{key}"

              @options[key]       = @options[key].to_s
              actual_options[key] = (respond_to?(method, true) ? send(method) : reflection.options[key]).to_s
            end

            return @options == actual_options, :actual => actual_options.inspect
          end

        private

          def reflection
            @reflection ||= subject_class.reflect_on_association(@association.to_sym)
          end

          def subject_table_name
            subject_class.table_name.to_s
          end

          def reflection_class_name
            reflection.class_name.to_s rescue nil
          end

          def reflection_table_name
            reflection.klass.table_name.to_s rescue nil
          end

          def reflection_foreign_key
            (reflection.respond_to?(:foreign_key) ? reflection.foreign_key : reflection.primary_key_name).to_s
          end

          def table_has_column?(klass, table_name, column)
            klass.connection.columns(table_name, 'Remarkable column retrieval').any?{|c| c.name == column }
          end

          def klass_table_has_column?(klass, column)
            table_has_column?(klass, klass.table_name, column)
          end

          # In through we don't check the foreign_key, because it's spread
          # accross the through and the source reflection which should be tested
          # with their own macros.
          #
          # In cases a join table exists (has_and_belongs_to_many and through
          # associations), we check the foreign key in the join table.
          #
          # On belongs to, the foreign_key is in the subject class table and in
          # other cases it's on the reflection class table.
          #
          def foreign_key_table
            if reflection.options.key?(:through)
              nil
            elsif reflection.macro == :has_and_belongs_to_many
              reflection.options[:join_table]
            elsif reflection.macro == :belongs_to
              subject_table_name
            else
              reflection_table_name
            end
          end

          # Returns the foreign key table class to use the proper connection
          # when searching for the table and foreign key.
          #
          def foreign_key_table_class
            if [:belongs_to, :has_and_belongs_to_many].include?(reflection.macro)
              subject_class
            else
              reflection.klass
            end
          end

          def interpolation_options
            options = {}
            options[:macro]   = Remarkable.t(@macro, :scope => matcher_i18n_scope, :default => @macro.to_s.gsub("_", ""))
            options[:options] = @options.inspect

            if @subject && reflection
              options.merge!(
                :actual_macro         => Remarkable.t(reflection.macro, :scope => matcher_i18n_scope, :default => reflection.macro.to_s),
                :subject_table        => subject_table_name.inspect,
                :reflection_table     => reflection_table_name.inspect,
                :foreign_key_table    => foreign_key_table.inspect,
                :polymorphic_column   => reflection_foreign_key.sub(/_id$/, '_type').inspect,
                :counter_cache_column => reflection.counter_cache_column.to_s.inspect,
                :join_table           => reflection.options[:join_table].inspect,
                :foreign_key          => reflection_foreign_key.inspect
              )
            end

            options
          end
      end

      # Ensure that the belongs_to relationship exists. Will also test that the
      # subject table has the association_id column.
      #
      # == Options
      #
      # * <tt>:class_name</tt> - the expected associted class name.
      # * <tt>:foreign_key</tt> - the expected foreign key in the subject table.
      # * <tt>:dependent</tt> - the expected dependent value for the association.
      # * <tt>:readonly</tt> - checks wether readonly is true or false.
      # * <tt>:validate</tt> - checks wether validate is true or false.
      # * <tt>:autosave</tt> - checks wether autosave is true or false.
      # * <tt>:counter_cache</tt> - the expected dependent value for the association.
      #   It also checks if the column actually exists in the table.
      # * <tt>:polymorphic</tt> - if the association should be polymorphic or not.
      #   When true it also checks for the association_type column in the subject table.
      #
      # Plus all supported sql conditions options: :select, :conditions, :order,
      # :limit, :offset, :include, :group, :having.
      #
      # == Examples
      #
      #   should_belong_to :parent, :polymorphic => true
      #   it { should belong_to(:parent) }
      #
      def belong_to(*associations, &block)
        AssociationMatcher.new(:belongs_to, *associations, &block).spec(self)
      end

      # Ensures that the has_and_belongs_to_many relationship exists, if the join
      # table is in place and if the foreign_key column exists.
      #
      # == Options
      #
      # * <tt>:class_name</tt>  - the expected associted class name.
      # * <tt>:join_table</tt>  - the expected join table name.
      # * <tt>:foreign_key</tt> - the expected foreign key in the association table.
      # * <tt>:uniq</tt>     - checks wether uniq is true or false.
      # * <tt>:readonly</tt> - checks wether readonly is true or false.
      # * <tt>:validate</tt> - checks wether validate is true or false.
      # * <tt>:autosave</tt> - checks wether autosave is true or false.
      #
      # Plus all supported sql conditions options: :select, :conditions, :order,
      # :limit, :offset, :include, :group, :having.
      #
      # == Examples
      #
      #  should_have_and_belong_to_many :posts, :cars
      #  it{ should have_and_belong_to_many :posts, :cars }
      #
      def have_and_belong_to_many(*associations, &block)
        AssociationMatcher.new(:has_and_belongs_to_many, *associations, &block).spec(self)
      end

      # Ensures that the has_many relationship exists. Will also test that the
      # associated table has the required columns. It works by default with 
      # polymorphic association (:as does not have to be supplied).
      #
      # == Options
      #
      # * <tt>:class_name</tt>  - the expected associted class name.
      # * <tt>:through</tt>     - the expected join model which to perform the query.
      #   It also checks if the through table exists.
      # * <tt>:source</tt>      - the source of the through association.
      # * <tt>:source_type</tt> - the source type of the through association.
      # * <tt>:foreign_key</tt> - the expected foreign key in the associated table.
      #   When used with :through, it will check for the foreign key in the join table.
      # * <tt>:dependent</tt>   - the expected dependent value for the association.
      # * <tt>:uniq</tt>     - checks wether uniq is true or false.
      # * <tt>:readonly</tt> - checks wether readonly is true or false.
      # * <tt>:validate</tt> - checks wether validate is true or false.
      # * <tt>:autosave</tt> - checks wether autosave is true or false.
      #
      # Plus all supported sql conditions options: :select, :conditions, :order,
      # :limit, :offset, :include, :group, :having.
      #
      # == Examples
      #
      #   should_have_many :friends
      #   should_have_many :enemies, :through => :friends
      #   should_have_many :enemies, :dependent => :destroy
      #
      #   it{ should have_many(:friends) }
      #   it{ should have_many(:enemies, :through => :friends) }
      #   it{ should have_many(:enemies, :dependent => :destroy) }
      #
      def have_many(*associations, &block)
        AssociationMatcher.new(:has_many, *associations, &block).spec(self)
      end

      # Ensures that the has_many relationship exists. Will also test that the
      # associated table has the required columns. It works by default with 
      # polymorphic association (:as does not have to be supplied).
      #
      # == Options
      #
      # * <tt>:class_name</tt>  - the expected associted class name.
      # * <tt>:through</tt>     - the expected join model which to perform the query.
      #   It also checks if the through table exists.
      # * <tt>:source</tt>      - the source of the through association.
      # * <tt>:source_type</tt> - the source type of the through association.
      # * <tt>:foreign_key</tt> - the expected foreign key in the associated table.
      #   When used with :through, it will check for the foreign key in the join table.
      # * <tt>:dependent</tt>   - the expected dependent value for the association.
      # * <tt>:validate</tt> - checks wether validate is true or false.
      # * <tt>:autosave</tt> - checks wether autosave is true or false.
      #
      # Plus all supported sql conditions options: :select, :conditions, :order,
      # :limit, :offset, :include, :group, :having.
      #
      # == Examples
      #
      #  should_have_one :universe
      #  it{ should have_one(:universe) }
      #
      def have_one(*associations, &block)
        AssociationMatcher.new(:has_one, *associations, &block).spec(self)
      end

    end
  end
end
