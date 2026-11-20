module CrSQLExample
  class CreateAuthor < BaseAction
    post "/authors"
    json CreateAuthorContract

    call do
      author = store.create_author(name: input.name, bio: input.bio)
      render_json({id: author.id, name: author.name, bio: author.bio}, status_code: 201)
    end
  end

  class GetAuthor < BaseAction
    get "/authors/:id"
    url AuthorPathContract

    call do
      if author = store.get_author?(id: input.id)
        render_json({id: author.id, name: author.name, bio: author.bio})
      else
        render_json({error: "author_not_found"}, status_code: 404)
      end
    end
  end

  class ListAuthors < BaseAction
    get "/authors"

    call do
      render_json(store.list_authors.map { |author| {id: author.id, name: author.name, bio: author.bio} })
    end
  end

  class UpdateAuthor < BaseAction
    patch "/authors/:id"
    url AuthorPathContract
    json UpdateAuthorContract

    call do
      author = store.update_author?(id: url_input.id,
        name: json_input.name, name_present: json_input.name_present?,
        bio: json_input.bio, bio_present: json_input.bio_present?)
      if author
        render_json({id: author.id, name: author.name, bio: author.bio})
      else
        render_json({error: "author_not_found"}, status_code: 404)
      end
    end
  end

  class CreateAuthorBook < BaseAction
    post "/author-books"
    json CreateAuthorBookContract

    call do
      result = store.transaction do |tx|
        author = tx.create_author(name: input.name, bio: input.bio)
        book = tx.create_book(author_id: author.id, title: input.title, isbn: input.isbn)
        {author: {id: author.id, name: author.name, bio: author.bio},
         book:   {id: book.id, author_id: book.author_id, title: book.title, isbn: book.isbn}}
      end
      render_json(result, status_code: 201)
    rescue error : PQ::PQError
      raise error unless error.field_message(:code) == "23505" && error.field_message(:constraint_name) == "books_isbn_key"
      render_json({error: "isbn_taken"}, status_code: 409)
    end
  end
end
