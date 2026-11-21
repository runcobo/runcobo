module Runcobo
  # A pagination value shared by queries, in-memory lists and response templates.
  # Request parsing and validation remain the caller's responsibility.
  struct Pagination
    getter page : Int32
    getter per_page : Int32
    getter offset : Int64

    def initialize(page : Int? = nil, per_page : Int? = nil, *, default_per_page : Int32 = 20, max_per_page : Int32 = 100)
      unless 0 < default_per_page <= max_per_page
        raise ArgumentError.new("default_per_page must be positive and no greater than max_per_page")
      end

      @page = (page || 1).clamp(1, Int32::MAX).to_i32
      size = per_page || default_per_page
      @per_page = (size <= 0 ? default_per_page : size.clamp(1, max_per_page)).to_i32
      @offset = (@page.to_i64 - 1)*@per_page
    end

    def slice(items : Array(T)) : Array(T) forall T
      return [] of T if offset >= items.size
      items[offset.to_i32, per_page]
    end
  end
end
