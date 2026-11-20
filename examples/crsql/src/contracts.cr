module CrSQLExample
  class CreateAuthorContract < RequestValidation::Contract
    schema do
      required :name, String
      optional :bio, String, nullable: true
    end

    rule :name do |name, errors|
      errors.add(:name, :blank) if name.strip.empty?
    end
  end

  class AuthorPathContract < RequestValidation::Contract
    schema do
      required :id, Int64
    end

    rule :id do |id, errors|
      errors.add(:id, :must_be_positive) unless id > 0
    end
  end

  class UpdateAuthorContract < RequestValidation::Contract
    schema do
      optional :name, String
      optional :bio, String, nullable: true
    end

    rule :name, :bio do |name, bio, errors|
      errors.base(:empty_update) unless errors.present?(:name) || errors.present?(:bio)
      errors.add(:name, :blank) if name && name.strip.empty?
    end
  end

  class CreateAuthorBookContract < RequestValidation::Contract
    schema do
      required :name, String
      optional :bio, String, nullable: true
      required :title, String
      required :isbn, String
    end

    rule :name, :title, :isbn do |name, title, isbn, errors|
      errors.add(:name, :blank) if name.strip.empty?
      errors.add(:title, :blank) if title.strip.empty?
      errors.add(:isbn, :blank) if isbn.strip.empty?
    end
  end
end
