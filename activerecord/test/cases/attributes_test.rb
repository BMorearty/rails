require 'cases/helper'

class OverloadedType < ActiveRecord::Base
  attribute :overloaded_float, Type::Integer.new
  attribute :overloaded_string_with_limit, Type::String.new(limit: 50)
  attribute :non_existent_decimal, Type::Decimal.new
  attribute :string_with_default, Type::String.new, default: 'the overloaded default'
end

class ChildOfOverloadedType < OverloadedType
end

class GrandchildOfOverloadedType < ChildOfOverloadedType
  attribute :overloaded_float, Type::Float.new
end

class UnoverloadedType < ActiveRecord::Base
  self.table_name = 'overloaded_types'
end

module ActiveRecord
  class CustomPropertiesTest < ActiveRecord::TestCase
    test "overloading types" do
      data = OverloadedType.new

      data.overloaded_float = "1.1"
      data.unoverloaded_float = "1.1"

      assert_equal 1, data.overloaded_float
      assert_equal 1.1, data.unoverloaded_float
    end

    test "overloaded properties save" do
      data = OverloadedType.new

      data.overloaded_float = "2.2"
      data.save!
      data.reload

      assert_equal 2, data.overloaded_float
      assert_kind_of Fixnum, OverloadedType.last.overloaded_float
      assert_equal 2.0, UnoverloadedType.last.overloaded_float
      assert_kind_of Float, UnoverloadedType.last.overloaded_float
    end

    test "properties assigned in constructor" do
      data = OverloadedType.new(overloaded_float: '3.3')

      assert_equal 3, data.overloaded_float
    end

    test "overloaded properties with limit" do
      assert_equal 50, OverloadedType.type_for_attribute('overloaded_string_with_limit').limit
      assert_equal 255, UnoverloadedType.type_for_attribute('overloaded_string_with_limit').limit
    end

    test "nonexistent attribute" do
      data = OverloadedType.new(non_existent_decimal: 1)

      assert_equal BigDecimal.new(1), data.non_existent_decimal
      assert_raise ActiveModel::AttributeAssignment::UnknownAttributeError do
        UnoverloadedType.new(non_existent_decimal: 1)
      end
    end

    test "changing defaults" do
      data = OverloadedType.new
      unoverloaded_data = UnoverloadedType.new

      assert_equal 'the overloaded default', data.string_with_default
      assert_equal 'the original default', unoverloaded_data.string_with_default
    end

    test "defaults are not touched on the columns" do
      assert_equal 'the original default', OverloadedType.columns_hash['string_with_default'].default
    end

    test "children inherit custom properties" do
      data = ChildOfOverloadedType.new(overloaded_float: '4.4')

      assert_equal 4, data.overloaded_float
    end

    test "children can override parents" do
      data = GrandchildOfOverloadedType.new(overloaded_float: '4.4')

      assert_equal 4.4, data.overloaded_float
    end

    test "overloading properties does not attribute method order" do
      attribute_names = OverloadedType.attribute_names
      assert_equal %w(id overloaded_float unoverloaded_float overloaded_string_with_limit string_with_default non_existent_decimal), attribute_names
    end

    test "caches are cleared" do
      klass = Class.new(OverloadedType)

      assert_equal 6, klass.attribute_types.length
      assert_equal 6, klass.column_defaults.length
      assert_not klass.attribute_types.include?('wibble')

      klass.attribute :wibble, Type::Value.new

      assert_equal 7, klass.attribute_types.length
      assert_equal 7, klass.column_defaults.length
      assert klass.attribute_types.include?('wibble')
    end

    test "the given default value is cast from user" do
      custom_type = Class.new(Type::Value) do
        def type_cast_from_user(*)
          "from user"
        end

        def type_cast_from_database(*)
          "from database"
        end
      end

      klass = Class.new(OverloadedType) do
        attribute :wibble, custom_type.new, default: "default"
      end
      model = klass.new

      assert_equal "from user", model.wibble
    end
  end
end
