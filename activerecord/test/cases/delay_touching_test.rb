require 'cases/helper'
require 'models/owner'
require 'models/pet'

class DelayTouchingTest < ActiveRecord::TestCase
  fixtures :owners, :pets

  test "touch returns true in a delay_touching block" do
    ActiveRecord::Base.delay_touching do
      assert_equal true, owner.touch
    end
  end

  test "delay_touching consolidates touches on a single record" do
    expect_updates [ { "owners" => { ids: owner } } ] do
      ActiveRecord::Base.delay_touching do
        owner.touch
        owner.touch
      end
    end
  end

  test "delay_touching sets updated_at on the in-memory instance when it eventually touches the record" do
    original_time = new_time = nil

    Time.stubs(:now).returns(Time.new(2014, 7, 4, 12, 0, 0))
    original_time = Time.current
    owner.touch

    Time.stubs(:now).returns(Time.new(2014, 7, 10, 12, 0, 0))
    new_time = Time.current
    ActiveRecord::Base.delay_touching do
      owner.touch
      assert_equal original_time, owner.updated_at
      assert_not owner.changed?
    end

    assert_equal new_time, owner.updated_at
    assert_not owner.changed?
  end

  test "delay_touching does not mark the instance as changed when touch is called" do
    ActiveRecord::Base.delay_touching do
      owner.touch
      assert_not owner.changed?
    end
  end

  test "delay_touching consolidates touches for all instances in a single table" do
    expect_updates [ { "pets" => { ids: [ pet1, pet2 ] } }, "owners" => { ids: owner } ] do
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
          owner.touch
        end
      end
    end
  end

  test "delay_touching only applies touches for which no_touching is off" do
    expect_updates [ "pets" => { ids: pet1 } ] do
      Owner.no_touching do
        ActiveRecord::Base.delay_touching do
          owner.touch
          pet1.touch
        end
      end
    end
  end

  test "delay_touching does not apply nested touches if no_touching was turned on inside delay_touching" do
    expect_updates [ "owners" => { ids: owner } ] do
      ActiveRecord::Base.delay_touching do
        owner.touch
        ActiveRecord::Base.no_touching do
          pet1.touch
        end
      end
    end
  end

  test "delay_touching can update nonstandard columns" do
    expect_updates [ "owners" => { ids: owner, columns: ["updated_at", "happy_at"] } ] do
      ActiveRecord::Base.delay_touching do
        owner.touch :happy_at
      end
    end
  end

  test "delay_touching splits up nonstandard column touches and standard column touches" do
    expect_updates [ { "pets" => { ids: [ pet1 ], columns: [ "updated_at", "neutered_at" ] } },
                     { "pets" => { ids: [ pet2 ], columns: [ "updated_at" ] } },
                       "owners" ] do

      ActiveRecord::Base.delay_touching do
        pet1.touch :neutered_at
        pet2.touch
      end
    end
  end

  test "delay_touching can update multiple nonstandard columns of a single record in different calls to touch" do
    expect_updates [ { "owners" => { ids: owner, columns: [ "updated_at", "happy_at" ] } },
                     { "owners" => { ids: owner, columns: [ "updated_at", "sad_at" ] } } ] do

      ActiveRecord::Base.delay_touching do
        owner.touch :happy_at
        owner.touch :sad_at
      end
    end
  end

  test "delay_touching can update multiple nonstandard columns of a single record in a single call to touch" do
    expect_updates [ { "owners" => { ids: owner, columns: [ "updated_at", "happy_at" ] } },
                     { "owners" => { ids: owner, columns: [ "updated_at", "sad_at" ] } } ] do

      ActiveRecord::Base.delay_touching do
        owner.touch :happy_at, :sad_at
      end
    end
  end

  test "delay_touching consolidates touch: true touches" do
    expect_updates [ { "pets" => { ids: [ pet1, pet2 ] } }, { "owners" => { ids: owner } } ] do
      ActiveRecord::Base.delay_touching do
        pet1.touch
        pet2.touch
      end
    end
  end

  test "delay_touching does not touch the owning record via touch: true if it was already touched explicitly" do
    expect_updates [ { "pets" => { ids: [ pet1, pet2 ] } }, { "owners" => { ids: owner } } ] do
      ActiveRecord::Base.delay_touching do
        owner.touch
        pet1.touch
        pet2.touch
      end
    end
  end

  test "delay_touching consolidates touch: :column_name touches" do
    klass = Class.new(ActiveRecord::Base) do
      def self.name; 'Pet'; end
      belongs_to :owner, :touch => :happy_at
    end

    pet = klass.first

    expect_updates [ { "owners" => { ids: owner, columns: [ "updated_at", "happy_at" ] } }, { "pets" => { ids: pet } } ] do
      ActiveRecord::Base.delay_touching do
        pet.touch
        pet.touch
      end
    end
  end

  private

  def owner
    @owner ||= owners(:blackbeard)
  end

  def pet1
    @pet1 ||= owner.pets.first
  end

  def pet2
    @pet2 ||= owner.pets.last
  end

  def expect_updates(tables_ids_and_columns)
    capture_sql { yield }
    expected_sql = expected_sql_for(tables_ids_and_columns)
    ActiveRecord::SQLCounter.log.each do |stmt|
      if stmt =~ /UPDATE /i
        index = expected_sql.index { |expected_stmt| stmt =~ expected_stmt }
        assert index, "An unexpected touch occurred: #{stmt}"
        expected_sql.delete_at(index)
      end
    end
    assert_empty expected_sql, "Some of the expected updates were not executed"
  end

  def expected_sql_for(tables_ids_and_columns)
    tables_ids_and_columns.map do |entry|
      if entry.kind_of?(Hash)
        entry.map do |table, options|
          ids = Array.wrap(options[:ids])
          columns = Array.wrap(options[:columns]).presence || ["updated_at"]
          Regexp.new(%{UPDATE "#{table}" SET #{columns.map { |column| %{"#{column}" =.+} }.join(", ") } .+#{ids_sql(ids)}\\Z})
        end
      else
        Regexp.new(%{UPDATE "#{entry}" SET "updated_at" = })
      end
    end.flatten
  end

  def ids_sql(ids)
    ids = ids.map { |id| id.class.respond_to?(:primary_key) ? id.send(id.class.primary_key) : id }
    ids.length > 1 ? %{ IN \\(#{ids.sort.join(", ")}\\)} : %{ = #{ids.first}}
  end
end

