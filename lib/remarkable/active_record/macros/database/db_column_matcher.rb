module Remarkable # :nodoc:
  module ActiveRecord # :nodoc:
    module Matchers # :nodoc:

      class DBColumnMatcher < Remarkable::Matcher::Base
        def initialize(*columns)
          @options = columns.extract_options!
          @columns  = columns
        end

        def type(type)
          @options[:type] = type
          self
        end

        def primary(value = true)
          @options[:primary] = value
          self
        end

        def default(default)
          @options[:default] = default
          self
        end

        def precision(precision)
          @options[:precision] = precision
          self
        end

        def limit(limit)
          @options[:limit] = limit
          self
        end

        def null(value = true)
          @options[:null] = value
          self
        end

        def scale(scale)
          @options[:scale] = scale
          self
        end

        def sql_type(sql_type)
          @options[:sql_type] = sql_type
          self
        end

        def matches?(subject)
          @subject = subject
          
          @columns.each do |column|
            return false unless has_column?(column) && all_options_correct?(column)
          end
          
          true
        end

        def failure_message
          "Expected #{expectation} (#{@missing})"
        end

        def negative_failure_message
          "Did not expect #{expectation}"
        end

        def description
          description = if @columns.size == 1
            "have column named :#{@columns[0]}"
          else
            "have columns #{@columns.to_sentence}"
          end
          description << " with options " + @options.inspect unless @options.empty?
          description
        end

        protected

        def model_class
          @subject
        end

        def column_type(column)
          model_class.columns.detect {|c| c.name == column.to_s }
        end

        def has_column?(column)
          if column_type(column)
            true
          else
            @missing = "#{model_class.name} does not have column #{column}"
            false
          end
        end

        def all_options_correct?(column)
          @options.each do |option, value|
            return false unless option_correct?(column, option, value)
          end
        end

        def option_correct?(column, option, expected_value)
          found_value = column_type(column).instance_variable_get("@#{option.to_s}").to_s

          if found_value == expected_value.to_s
            true
          else
            @missing = ":#{column} column on table for #{model_class} does not match option :#{option}, found '#{found_value}' but expected '#{expected_value}'"
            false
          end
        end

        def expectation
          if @columns.size == 1
            "#{model_class.name} to have a column named #{@columns[0]}"
          else
            "#{model_class.name} to have columns #{@columns.to_sentence}"
          end
        end
      end

      def have_db_column(column, options = {})
        DBColumnMatcher.new(column, options)
      end
      
      def have_db_columns(*columns)
        DBColumnMatcher.new(*columns)
      end
      
    end
  end
end
