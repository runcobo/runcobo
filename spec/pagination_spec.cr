require "./spec_helper"

describe Runcobo::Pagination do
  it "uses consistent defaults for queries and in-memory lists" do
    pagination = Runcobo::Pagination.new
    pagination.page.should eq(1)
    pagination.per_page.should eq(20)
    pagination.offset.should eq(0)
    pagination.slice((1..30).to_a).should eq((1..20).to_a)
  end

  it "uses the query offset when slicing a list and retains a partial last page" do
    pagination = Runcobo::Pagination.new(2_i64, 2_i64)
    pagination.offset.should eq(2)
    pagination.slice([10, 20, 30, 40, 50]).should eq([30, 40])
    Runcobo::Pagination.new(3, 2).slice([10, 20, 30, 40, 50]).should eq([50])
    Runcobo::Pagination.new(4, 2).slice([10, 20, 30, 40, 50]).should be_empty
    Runcobo::Pagination.new.slice([] of Int32).should be_empty
  end

  it "normalizes missing and nonpositive values and limits oversized inputs" do
    Runcobo::Pagination.new(nil, nil).page.should eq(1)
    Runcobo::Pagination.new(nil, nil).per_page.should eq(20)
    [0_i64, -1_i64, Int64::MIN].each do |value|
      pagination = Runcobo::Pagination.new(value, value)
      pagination.page.should eq(1)
      pagination.per_page.should eq(20)
      pagination.offset.should eq(0)
    end
    Runcobo::Pagination.new(1, 101).per_page.should eq(100)
  end

  it "keeps large offsets in 64 bits and returns an empty list without narrowing them" do
    pagination = Runcobo::Pagination.new(Int64::MAX, Int64::MAX)
    pagination.page.should eq(Int32::MAX)
    pagination.per_page.should eq(100)
    pagination.offset.should eq((Int32::MAX.to_i64 - 1)*100)
    pagination.slice([1, 2]).should be_empty
    largest = Runcobo::Pagination.new(Int64::MAX, Int64::MAX, max_per_page: Int32::MAX)
    largest.offset.should eq((Int32::MAX.to_i64 - 1)*Int32::MAX)
    largest.slice([1, 2]).should be_empty
  end

  it "allows applications to configure the default and maximum page sizes" do
    [nil, 0, -1].each do |size|
      Runcobo::Pagination.new(nil, size, default_per_page: 5, max_per_page: 10).per_page.should eq(5)
    end
    pagination = Runcobo::Pagination.new(2, 99, default_per_page: 5, max_per_page: 10)
    pagination.per_page.should eq(10)
    pagination.offset.should eq(10)
    pagination.slice((1..25).to_a).should eq((11..20).to_a)
  end

  it "rejects invalid page size configuration" do
    [{0, 100}, {-1, 100}, {20, 0}, {20, -1}, {101, 100}].each do |defaults|
      expect_raises(ArgumentError, "default_per_page must be positive and no greater than max_per_page") do
        Runcobo::Pagination.new(default_per_page: defaults[0], max_per_page: defaults[1])
      end
    end
  end
end
