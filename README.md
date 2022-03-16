# Runcobo

[![Crystal CI](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml/badge.svg)](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml)
[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Latest release](https://img.shields.io/github/release/runcobo/runcobo.svg?style=flat-square)](https://github.com/runcobo/runcobo/releases)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://runcobo.github.io/runcobo/)

# Introduction

Runcobo is a general purpose framework built on Crystal.  

### Commands

```shell
runcobo [<commands>...] [<arguments>...]

  Commands:
    routes                      - Print all routes of the app.
    version                     - Print the current version of the runcobo.
    help                        - Print usage synopsis.

  Options:
    -h, --help                       Print usage synopsis.
    -v, --version                    Print the current version of the runcobo.
```

### Project Architecture

    lib/                # Library
    src/
        main.cr         # Entry file
        actions/        # Actions Directory
            ...
        assets/         # Assets Directory
        views/          # Views Directory
            layouts/    # Layouts directory
            ...
        models/         # Models Directory
            ...
    shards.yml          # The packages congfiuration file
    shards.lock         # The lock file for packages congfiuration file

Keep in this architecture to use `layouts` macro, `render` macro.

### Design Architecture
MVC (Model-View-Controller)

### Design Principles

+ Simple Design must be simple, both in implementation and interface.
+ Intuitive Design must be intuitive.
+ Consistent Design must be consistent.

# Installation

### Install Crystal
Crystal is a language for humans and computers. 

Crystal is a type safe, compiled language inspired by the simplicity of Ruby. Type safety means more errors are caught by the compiler during development, so you can be more confident about your code working in production.

See [https://crystal-lang.org/install/](https://crystal-lang.org/install) to install Crystal.

### Install Runcobo
You can install Runcobo from sources. Other installations are working on.

```shell
curl -L https://github.com/runcobo/runcobo/archive/stable.zip --output runcobo.zip
unzip runcobo.zip
cd runcobo-stable/
sudo make install
runcobo -v
```

# Getting Started

1.Init a Crystal project.
```shell
crystal init app demo && cd demo
```

2.Add the dependency to your shard.yml and run `shards install`.
```yaml
dependencies:
  runcobo:
    github: runcobo/runcobo
```

3.Write down the following code in `src/demo.cr`.
```crystal
require "runcobo"

class Api::V1::Add < BaseAction
  get "/api/v1/add"
  query NamedTuple(a: Int32, b: Int32)

  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end

Runcobo.start
```

4.Run server.
```shell
crystal src/demo.cr
```

5.Send request.
```shell
curl "http://0.0.0.0:3000/api/v1/add?a=1&b=2"
```

6.Auto restart server.
```shell
# Use nodemon to watch file changed and auto restart server.
sudo npm install -g nodemon
nodemon -e "cr,water,jbuilder,yml" --exec "crystal run" src/demo.cr
```

# Route
Runcobo declares routes in every Actions. If you access the route, it will run into related Action.

In this way, you can know the routes of current Action quickly.

You can declare RESTful routes as you want or not.

> In my personal view, RESTful is too abstact when you were far way from a CRUD system like Backend Management System.

> When writing API, I believe urls should be named like functions, not objects or resources.

> When writing a Backend Management System, enjoy RESTful.

### Routes Declaration
Runcobo declares routes by following methods: `get`, `post`, `put`, `patch`, `delete`, `options`, `head`.
An Action can bind to one or more routes.

```crystal
class Example < BaseAction
  get "/books"
  get "/books/:id"
  post "/books"
  put "/books/:id"
  patch "/books/:id"
  delete "/books/:id"
  options "/books/:id"
  head "/books/:id"

  call do
    render_plain "Hello World"
  end
end
```

### URL Params
URL Params can be declared in the route like `/add/:apple_count/:banana_count`. And then you should use `url` method to declare the type of URL params.

```crystal
class Example < BaseAction
  get "/add/:apple_count/:banana_count"
  url NamedTuple(apple_count: Int32, banana_count: Int32)

  call do
    sum = params[:apple_count] + params[:banana_count]
    render_plain sum.to_s
  end
end
```

### Custom HTTP method
If you need a route with custom HTTP method, such as `LINK`, `UNLINK`, `FIND` or `PURGE`, then you can use `route` method to declare it.

```crystal
class Example < BaseAction
  route "LINK", "/books/:id"

  call do
    render_plain "Hello World"
  end
end
```

# Action

Runcobo use one action one file. 

### Before Filter
```crystal
class BeforeExample < BaseAction
  before required_login
  def required_login
    Runcobo::Log.info { "Required Login" }
  end

  get "/before_example"
  call do
    render_plain "Hello World!"
  end
end
```

### After Filter
```crystal
class AfterExample < BaseAction
  after log_params
  def log_params
    Runcobo::Log.info { "#{params}" }
  end

  get "/after_example"
  call do
    render_plain "Hello World!"
  end
end
```

### Skip Filter
```crystal
class BaseAction
  before required_login
  def required_login
    Runcobo::Log.info { "Required Login" }
  end
end

class SkipExample < BaseAction
  skip required_login

  get "/skip_example"
  call do
    render_plain "Hello World!"
  end
end
```

# Params

### Type-safe Params
An old Chinese proverb says, "If something is important, then repeat it three times". So,

**Params in Runcobo are type-safe.**

**Params in Runcobo are type-safe.**

**Params in Runcobo are type-safe.**

### Three Steps To Use Params

+ First, declare what params you expect and what type you expect by following methods: `url`, `query`, `form` and `json`.
+ Next, Runcobo parses request and wraps params to a local variable called `params`.
+ Third, use `params` variable to get or set request params.

### Url Params
```crystal
class UrlExample < BaseAction
  get "/url_example/:a/:b"
  url NamedTuple(a: Int32, b: Int32)

  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end
```

### Query Params
```crystal
class QueryExample < BaseAction
  get "/query_example"
  query NamedTuple(a: Int32, b: Int32)

  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end
```

### Form Params
```crystal
class FormExample < BaseAction
  post "/form_example"
  form NamedTuple(a: Int32, b: Int32)

  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end
```

### JSON Params
```crystal
class JsonExample < BaseAction
  post "/json_example"
  json NamedTuple(a: Int32, b: Int32)

  call do
    sum = params[:a] + params[:b]
    render_plain sum.to_s
  end
end
```

### Params Merge Order
You can declare various kinds of params in a action. If params are in same key, they will be merged in following order:

`Query Params < Form Params < JSON Params < Url Params`

# Render

### Render HTML
```crystal
class WaterExample < BaseAction
  get "/water_example"
  call do
    render_water "examples/index"
  end
end
```

### Render Plain
```crystal
class PlainExample < BaseAction
  get "/plain_example"
  call do
    render_plain "Hello World!"
  end
end
```

### Render Body
```crystal
class BodyExample < BaseAction
  get "/body_example"
  call do
    render_body "Hello World!"
  end
end
```

### Render JSON
```crystal
class JbuilderExample < BaseAction
  get "/jbuilder_example"
  call do
    render_jbuilder "examples/index"
  end
end
```

# View

Runcobo renders JSON by **Jbuilder**, renders HTML by **Water**.
**Jbuilder** is a template engine designed for json using plain Crystal.
**Water** is a template engine designed for html using plain Crystal.

### Data transfer
All methods or variables defined in the action are available in the views.
This is because the views are compiled in the same scope as the action.

### Layout

You can override the default layout conventions in your actions by using the layout declaration. For example:
```crystal
class BaseAction
  layout "application"
  #...
end
```

### Partial

Runcobo renders partial view by build-in `read_file` macro. There's no magic about partial view. 
For example,

*src/views/books/index.jbuilder*
```crystal
json.array! "books", books do |json, book|
  {{ read_file("src/views/books/_base_book.jbuilder").id }}
end
```

*src/views/books/_base_book.jbuilder*
```crystal
json.book_id      book.id
json.author       book.author
json.name         book.name
json.published_at book.published_at
```

### Render JSON

*src/controllers/books/index.cr*
```crystal
class Books::Index < BaseAction
  get "/books"
  call do
    books = Book.all
    render_jbuilder "books/index"
  end
end
```

*src/views/books/index.jbuilder*
```crystal
json.array! "books", books do |json, book|
  json.book_id      book.id
  json.author       book.author
  json.name         book.name
  json.published_at book.published_at
end
```

Then, output a JSON string.
```json
{
  "books": [{
    "book_id": 1,
    "author": "David",
    "name": "Crystal Programming",
    "published_at": "2020-08-08T20:00:00+00:00"
  }]
}
```

### Render Partial

*src/views/books/index.jbuilder*
```crystal
json.array! "books", books do |json, book|
  {{ read_file("src/views/books/_base_book.jbuilder").id }}
end
```

*src/views/books/_base_book.jbuilder*
```crystal
json.book_id      book.id
json.author       book.author
json.name         book.name
json.published_at book.published_at
```

### Render HTML

*src/controllers/books/index.cr*
```crystal
class Books::Index < BaseAction
  get "/books"
  call do
    books = Book.all
    render_water "books/index"
  end
end
```

*src/views/books/index.water*
```crystal
table %|class="table table-hover"| {
  thead {
    tr {
      th "ID"
      th "Author"
      th "Name"
      th "Published At"
    } 
  }
  tbody {
    books.each do |book|
      tr {
        td book.id
        td book.author
        td book.name
        td book.published_at
      }
    end
  }
}
```

Then, output a HTML string.
```json
<table class="table table-hover">
  <thead>
    <tr>
      <th>ID</th>
      <th>Author</th>
      <th>Name</th>
      <th>Published At</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>1</td>
      <td>David</td>
      <td>Crystal Programming</td>
      <td>2020-08-02 14:07:41 +08:00</td>
    </tr>
  </tbody>
</table>
```

### Render Partial

*src/views/books/index.jbuilder*
```crystal
{{ read_file("src/views/books/table.water").id }}
```

*src/views/books/table.water*
```crystal
table %|class="table table-hover"| {
  thead {
    tr {
      th "ID"
      th "Author"
      th "Name"
      th "Published At"
    } 
  }
  tbody {
    books.each do |book|
      tr {
        td book.id
        td book.author
        td book.name
        td book.published_at
      }
    end
  }
}
``` 

# Model

Here is a list of ORM from [awesome-crystal](https://github.com/veelenga/awesome-crystal#ormodm-extensions)

+ [avram](https://github.com/luckyframework/avram) - A database wrapper for reading, writing, and migrating Postgres databases. (Only Postgres)
+ [clear](https://github.com/anykeyh/clear) - ORM specialized to PostgreSQL only but with advanced features (Only Postgres)
+ [crecto](https://github.com/Crecto/crecto) - Database wrapper, based on Ecto
+ [granite](https://github.com/amberframework/granite) - ORM for Postgres, Mysql, Sqlite
+ [jennifer.cr](https://github.com/imdrasil/jennifer.cr) - Active Record pattern implementation with flexible query chainable builder and migration system
+ [ohm-crystal](https://github.com/soveran/ohm-crystal) - Object-hash mapping library for Redis (Only Redis)
+ [onyx-sql](https://github.com/onyxframework/sql) - DB-agnostic SQL ORM with beautiful DSL and type-safe Query builder
+ [rethinkdb-orm](https://github.com/spider-gazelle/rethinkdb-orm) - ORM for RethinkDB / RebirthDB (Only RethinkDB / RebirthDB)
+ [stal-crystal](https://github.com/soveran/stal-crystal) - Set algebra solver for Redis

Runcobo prefers to use [jennifer.cr](https://github.com/imdrasil/jennifer.cr), you can check its [docs](https://imdrasil.github.io/jennifer.cr/docs/) and [api](https://imdrasil.github.io/jennifer.cr/latest/).

## Contributing

1. Fork it (<https://github.com/runcobo/runcobo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write and execute specs (`crystal spec`) and formatting checks (`crystal tool format`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Shootingfly](https://github.com/shootingfly) - creator and maintainer
