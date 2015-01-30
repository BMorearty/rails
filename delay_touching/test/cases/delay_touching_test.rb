require_relative 'helper'
require 'active_support/testing/autorun'

module DelayTouchingHelper
  def expect_updates(tables)
    capture_sql { yield }
  ensure
    expected_sql = expected_sql_for(tables)
    ActiveRecord::SQLCounter.log.each do |stmt|
      if stmt =~ /UPDATE /i
        index = expected_sql.index { |expected_stmt| stmt =~ expected_stmt }
        assert index, "An unexpected touch occurred: #{stmt}"
        expected_sql.delete_at(index)
      end
    end
    assert_empty expected_sql, "Some of the expected updates were not executed."
  end

  def person
    @person ||= Person.create(name: "Rosey")
  end

  def pet1
    @pet1 ||= Pet.create(name: "Bones")
  end

  def pet2
    @pet2 ||= Pet.create(name: "Ema")
  end

  private

  def expected_sql_for(tables)
    tables.map do |entry|
      if entry.kind_of?(Hash)
        entry.map do |table, columns|
          Regexp.new(%{UPDATE "#{table}" SET #{columns.map { |column| %{"#{column}" =.+} }.join(", ") } })
        end
      else
        Regexp.new(%{UPDATE "#{entry}" SET "updated_at" = })
      end
    end.flatten
  end
end

class DelayTouchingTest < ActiveRecord::TestCase
  include DelayTouchingHelper

  test "touch returns true in a delay_touching block" do
    ActiveRecord::Base.delay_touching do
      assert_equal true, person.touch
    end
  end

  test "delay_touching consolidates touches on a single record" do
    expect_updates ["people"] do
      ActiveRecord::Base.delay_touching do
        person.touch
        person.touch
      end
    end
  end

  test "delay_touching sets updated_at on the in-memory instance when it eventually touches the record" do
    original_time = new_time = nil

    Timecop.freeze(2014, 7, 4, 12, 0, 0) do
      original_time = Time.current
      person.touch
    end

    Timecop.freeze(2014, 7, 10, 12, 0, 0) do
      new_time = Time.current
      ActiveRecord::Base.delay_touching do
        person.touch
        assert_equal original_time, person.updated_at
        assert_not person.changed?
      end
    end

    assert_equal new_time, person.updated_at
    assert_not person.changed?
  end

  test "delay_touching does not mark the instance as changed when touch is called" do
    ActiveRecord::Base.delay_touching do
      person.touch
      assert_not person.changed?
    end
  end

  test "delay_touching consolidates touches for all instances in a single table" do
    expect_updates ["pets"] do
      ActiveRecord::Base.delay_touching do
        pet1.touch
        pet2.touch
      end
    end
  end

  test "does nothing if no_touching is on" do
    expect_updates [] do
      ActiveRecord::Base.no_touching do
        ActiveRecord::Base.delay_touching do
          person.touch
        end
      end
    end
  end

  test "delay_touching only applies touches for which no_touching is off" do
    expect_updates ["pets"] do
      Person.no_touching do
        ActiveRecord::Base.delay_touching do
          person.touch
          pet1.touch
        end
      end
    end
  end

  test "delay_touching does not apply nested touches if no_touching was turned on inside delay_touching" do
    expect_updates [ "people" ] do
      ActiveRecord::Base.delay_touching do
        person.touch
        ActiveRecord::Base.no_touching do
          pet1.touch
        end
      end
    end
  end

  test "delay_touching can update nonstandard columns" do
    expect_updates [ "pets" => [ "updated_at", "neutered_at" ] ] do
      ActiveRecord::Base.delay_touching do
        pet1.touch :neutered_at
      end
    end
  end

  test "delay_touching splits up nonstandard column touches and standard column touches" do
    expect_updates [ { "pets" => [ "updated_at", "neutered_at" ]  }, { "pets" => [ "updated_at" ] } ] do
      ActiveRecord::Base.delay_touching do
        pet1.touch :neutered_at
        pet2.touch
      end
    end
  end

  test "delay_touching can update multiple nonstandard columns of a single record in different calls to touch" do
    expect_updates [ { "pets" => [ "updated_at", "neutered_at" ] }, { "pets" => [ "updated_at", "fed_at" ] } ] do
      ActiveRecord::Base.delay_touching do
        pet1.touch :neutered_at
        pet1.touch :fed_at
      end
    end
  end
end

class DelayTouchingTouchTrueTest < ActiveRecord::TestCase
  include DelayTouchingHelper

  setup do
    person.pets << pet1
    person.pets << pet2
  end

  test "delay_touching consolidates touch: true touches" do
    expect_updates [ "pets", "people" ] do
      ActiveRecord::Base.delay_touching do
        pet1.touch
        pet2.touch
      end
    end
  end

  test "delay_touching does not touch the owning record via touch: true if it was already touched explicitly" do
    expect_updates [ "pets", "people" ] do
      ActiveRecord::Base.delay_touching do
        person.touch
        pet1.touch
        pet2.touch
      end
    end
  end
end

