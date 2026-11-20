require "spec"
require "../src/app"

ENV["SKIP_LOG"] = "true"

TEST_DATABASE_URL = ENV["DATABASE_URL"]? || raise "Set DATABASE_URL to a dedicated runcobo_crsql_test database"
unless URI.parse(TEST_DATABASE_URL).path == "/runcobo_crsql_test"
  raise "Integration specs only run against the dedicated runcobo_crsql_test database"
end

private def crsql_test_url(application_name : String? = nil)
  uri = URI.parse(TEST_DATABASE_URL)
  params = HTTP::Params.parse(uri.query || "")
  params["max_pool_size"] = "1"
  params["checkout_timeout"] = "1"
  params["application_name"] = application_name if application_name
  uri.query = params.to_s
  uri.to_s
end

private def with_crsql_store(&)
  DB.open(crsql_test_url) do |database|
    database.exec("TRUNCATE books, authors RESTART IDENTITY")
    begin
      yield CrSQLExample::Store::Queries.new(database), database
    ensure
      database.exec("TRUNCATE books, authors RESTART IDENTITY")
    end
  end
end

private def crsql_request(store : CrSQLExample::Store::Queries, method : String, path : String, body : String? = nil)
  headers = HTTP::Headers.new
  headers["Content-Type"] = "application/json" if body
  request = HTTP::Request.new(method, path, headers, body)
  output = IO::Memory.new
  response = HTTP::Server::Response.new(output)
  context = HTTP::Server::Context.new(request, response)
  CrSQLExample::StoreRouteHandler.new(store).call(context)
  response.close
  output.rewind
  HTTP::Client::Response.from_io(output)
end

private def crsql_connection_count(application_name : String)
  DB.open(TEST_DATABASE_URL) do |database|
    database.query_one("SELECT count(*) FROM pg_stat_activity WHERE application_name = $1",
      application_name, as: Int64)
  end
end

private def expect_crsql_disconnected(application_name : String)
  50.times do
    return if crsql_connection_count(application_name) == 0
    sleep 10.milliseconds
  end
  crsql_connection_count(application_name).should eq(0)
end

describe "Runcobo with crsql" do
  it "creates an author from typed input and reads it through the generated query" do
    with_crsql_store do |store, database|
      response = crsql_request(store, "POST", "/authors", %({"name":"Ada","bio":"Writer"}))
      response.status_code.should eq(201)
      author = JSON.parse(response.body)
      found = crsql_request(store, "GET", "/authors/#{author["id"].as_i64}")
      found.status_code.should eq(200)
      JSON.parse(found.body).should eq(author)
      list = crsql_request(store, "GET", "/authors")
      JSON.parse(list.body).as_a.should eq([author])
      database.query_one("SELECT count(*) FROM authors", as: Int64).should eq(1_i64)
    end
  end

  it "returns validation errors before attempting to use a closed store" do
    database = DB.open(crsql_test_url)
    store = CrSQLExample::Store::Queries.new(database)
    database.close
    response = crsql_request(store, "POST", "/authors", %({"name":" ","unknown":"secret"}))
    response.status_code.should eq(422)
    response.body.should_not contain("secret")
    crsql_request(store, "GET", "/authors/not-an-integer").status_code.should eq(422)
  ensure
    database.try(&.close)
  end

  it "returns 404 for missing rows and rejects invalid identifiers" do
    with_crsql_store do |store|
      crsql_request(store, "GET", "/authors/999").status_code.should eq(404)
      crsql_request(store, "GET", "/authors/0").status_code.should eq(422)
      crsql_request(store, "PATCH", "/authors/999", %({"name":"new"})).status_code.should eq(404)
    end
  end

  it "preserves omitted fields and clears explicitly nullable fields on update" do
    with_crsql_store do |store|
      author = store.create_author(name: "Ada", bio: "Writer")
      response = crsql_request(store, "PATCH", "/authors/#{author.id}", %({"name":"Grace"}))
      response.status_code.should eq(200)
      value = JSON.parse(response.body)
      value["name"].as_s.should eq("Grace")
      value["bio"].as_s.should eq("Writer")

      response = crsql_request(store, "PATCH", "/authors/#{author.id}", %({"bio":null}))
      response.status_code.should eq(200)
      value = JSON.parse(response.body)
      value["name"].as_s.should eq("Grace")
      value["bio"].raw.should be_nil
      store.get_author(id: author.id).bio.should be_nil
    end
  end

  it "does not write invalid updates" do
    with_crsql_store do |store|
      author = store.create_author(name: "Ada", bio: "Writer")
      ["{}", %({"name":null}), %({"name":" "})].each do |body|
        crsql_request(store, "PATCH", "/authors/#{author.id}", body).status_code.should eq(422)
      end
      store.get_author(id: author.id).name.should eq("Ada")
      store.get_author(id: author.id).bio.should eq("Writer")
    end
  end

  it "commits both writes using a single-connection pool" do
    with_crsql_store do |store, database|
      response = crsql_request(store, "POST", "/author-books",
        %({"name":"Ada","title":"Notes","isbn":"book-1"}))
      response.status_code.should eq(201)
      value = JSON.parse(response.body)
      author_id = value["author"]["id"].as_i64
      value["book"]["author_id"].as_i64.should eq(author_id)
      store.get_author(id: author_id).name.should eq("Ada")
      store.get_book_by_isbn(isbn: "book-1").author_id.should eq(author_id)
      database.query_one("SELECT count(*) FROM authors", as: Int64).should eq(1_i64)
    end
  end

  it "rolls back the author when the second write violates a unique index" do
    with_crsql_store do |store, database|
      first = %({"name":"Ada","title":"Notes","isbn":"book-1"})
      second = %({"name":"Rolled back","title":"Other","isbn":"book-1"})
      crsql_request(store, "POST", "/author-books", first).status_code.should eq(201)
      response = crsql_request(store, "POST", "/author-books", second)
      response.status_code.should eq(409)
      JSON.parse(response.body)["error"].as_s.should eq("isbn_taken")
      response.body.should_not contain("duplicate key")
      store.list_authors.map(&.name).should eq(["Ada"])
      database.query_one("SELECT count(*) FROM books", as: Int64).should eq(1_i64)
    end
  end

  it "uses a transaction supplied by the caller without checking out another connection" do
    with_crsql_store do |store, database|
      database.transaction do |transaction|
        transactional = store.with_transaction(transaction)
        response = crsql_request(transactional, "POST", "/authors", %({"name":"Uncommitted"}))
        response.status_code.should eq(201)
        transactional.list_authors.map(&.name).should eq(["Uncommitted"])
        transaction.rollback
      end
      store.list_authors.should be_empty
    end
  end

  it "uses savepoints inside caller transactions and keeps the outer transaction usable" do
    with_crsql_store do |store, database|
      database.transaction do |transaction|
        transactional = store.with_transaction(transaction)
        body = %({"name":"Ada","title":"Notes","isbn":"book-1"})
        crsql_request(transactional, "POST", "/author-books", body).status_code.should eq(201)
        crsql_request(transactional, "POST", "/author-books", body).status_code.should eq(409)
        crsql_request(transactional, "POST", "/authors", %({"name":"After savepoint"})).status_code.should eq(201)
        transactional.list_authors.map(&.name).should eq(["Ada", "After savepoint"])
        transaction.rollback
      end
      store.list_authors.should be_empty
    end
  end

  it "isolates injected stores instead of sharing a global transaction" do
    with_crsql_store do |store, database|
      CrSQLExample::Store.open(crsql_test_url) do |other_store|
        database.transaction do |transaction|
          transactional = store.with_transaction(transaction)
          response = crsql_request(transactional, "POST", "/authors", %({"name":"Private"}))
          id = JSON.parse(response.body)["id"].as_i64
          crsql_request(transactional, "GET", "/authors/#{id}").status_code.should eq(200)
          crsql_request(other_store, "GET", "/authors/#{id}").status_code.should eq(404)
          transaction.rollback
        end
      end
    end
  end

  it "runs the configured database handlers over a real server connection" do
    with_crsql_store do |store|
      server = Runcobo::Server.new(handlers: CrSQLExample.handlers(store))
      address = server.instance.bind_unused_port
      spawn { server.instance.listen }
      client = HTTP::Client.new("127.0.0.1", address.port)
      begin
        response = client.post("/authors", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: %({"name":"Network"}))
        response.status_code.should eq(201)
        id = JSON.parse(response.body)["id"].as_i64
        client.get("/authors/#{id}").status_code.should eq(200)
      ensure
        client.close
        server.close
      end
    end
  end

  it "releases query connections after repeated requests" do
    with_crsql_store do |store|
      10.times do |index|
        response = crsql_request(store, "POST", "/authors", %({"name":"Author #{index}"}))
        response.status_code.should eq(201)
        id = JSON.parse(response.body)["id"].as_i64
        crsql_request(store, "GET", "/authors/#{id}").status_code.should eq(200)
      end
      store.list_authors.size.should eq(10)
    end
  end

  it "closes the application pool when the scope returns normally" do
    application_name = "runcobo_crsql_success_#{Random.rand(1_000_000)}"
    result = CrSQLExample::Store.open(crsql_test_url(application_name)) do |store|
      store.list_authors
      crsql_connection_count(application_name).should eq(1_i64)
      :finished
    end
    result.should eq(:finished)
    expect_crsql_disconnected(application_name)
  end

  it "closes the application pool when the scope raises" do
    application_name = "runcobo_crsql_failure_#{Random.rand(1_000_000)}"
    expect_raises(ArgumentError, "application failed") do
      CrSQLExample::Store.open(crsql_test_url(application_name)) do |store|
        store.list_authors
        raise ArgumentError.new("application failed")
      end
    end
    expect_crsql_disconnected(application_name)
  end
end
