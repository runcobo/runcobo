# Runcobo

[![Crystal CI](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml/badge.svg)](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml)
[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Latest release](https://img.shields.io/github/release/runcobo/runcobo.svg?style=flat-square)](https://github.com/runcobo/runcobo/releases)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://runcobo.github.io/runcobo/)

# Introduction

Runcobo is a general purpose framework built on Crystal.

This development branch targets Runcobo 3.0 and uses request-validation contracts
for typed request inputs. It is a breaking change from 2.x; see the migration
notes below. The version is `3.0.0-dev`, not a published release.

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
You can install Runcobo from sources. Crystal >= 1.22.0 and < 2.0.0 is required.
The request-validation dependency is private: configure an authenticated Git
connection with read access to `shootingfly/request-validation` before installing.
The manifest uses the repository's secure-shell Git address.

```shell
git clone https://github.com/runcobo/runcobo.git
cd runcobo
make build
./bin/runcobo --version
# Optional installation into a writable directory:
make install INSTALL_DIR="$HOME/.local/bin"
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

class AddContract < RequestValidation::Contract
  schema do
    required :a, Int32
    required :b, Int32
  end
end

class Api::V1::Add < BaseAction
  get "/api/v1/add"
  query AddContract

  call do
    sum = input.a + input.b
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
class FruitCountContract < RequestValidation::Contract
  schema do
    required :apple_count, Int32
    required :banana_count, Int32
  end
end

class Example < BaseAction
  get "/add/:apple_count/:banana_count"
  url FruitCountContract

  call do
    sum = input.apple_count + input.banana_count
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
  after log_request
  def log_request
    Runcobo::Log.info { "#{request.path}" }
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

# Request contracts

Declare a `RequestValidation::Contract` and bind it to the action's input source.
Runcobo loads request-validation through the normal entry point. Installing the
framework requires read access to the private `shootingfly/request-validation`
repository; the pinned dependency is installed transitively.

```crystal
require "runcobo"

class CreateAuthorContract < RequestValidation::Contract
  schema do
    required :name, String
    optional :bio, String, nullable: true
  end

  rule :name do |name, errors|
    errors.add(:name, :blank) if name.empty?
  end
end

class Authors::Create < BaseAction
  post "/authors"
  json CreateAuthorContract

  call do
    render_json({name: input.name, bio: input.bio}, status_code: 201)
  end
end

Runcobo.start
```

`url`, `query`, `form`, and `json` accept contract types. A single contract
provides `input`; multiple contracts provide `url_input`, `query_input`,
`form_input`, and `json_input` for the declared sources. These are concrete
contract outputs, with required fields retaining non-nullable types. Sources
are validated separately and their errors are collected together; same-named
fields do not overwrite each other. Results are cached only on the current
action instance, so repeated access does not rerun rules or reread the body.

Contracts currently support top-level `String`, `Int32`, `Int64`, `Float64`,
and `Bool` fields. Optional fields may be missing; explicit null requires
`nullable: true`. Use the generated `field_present?` accessor to distinguish
missing fields from explicit null when updating records. Required strings can
still be empty; add a rule when blank strings are invalid. Nested objects and
arrays are not currently supported. Add that capability to request-validation
before migrating endpoints that require it.

Query, path and form values use the contract's string conversions. Contract
booleans accept only `true` and `false`, and repeated scalar query/form fields
are rejected. Structured bodies retain their native types: strings are not
converted into numbers or booleans. Unknown fields are rejected by default;
use `query SomeContract, unknown_keys: :strip` (or the corresponding source)
to ignore them explicitly.

Each source may have only one contract, including inherited declarations. An
action cannot declare both a form and a structured-body contract. Conflicts and
old `NamedTuple` parameter declarations fail at compile time. Shared filters can
live in a base action without parameter declarations.

### Validation failures and request limits

Failures return an `application/json` response with an `errors` array:

```json
{
  "errors": [
    {"source": "query", "path": ["id"], "code": "invalid_type", "params": {"expected": "Int64"}}
  ]
}
```

Errors preserve the contract's paths, stable codes and message parameters,
without including raw input values. Field failures, custom rule failures and
non-object bodies return 422. Malformed structured bodies return 400. Body
contracts require the corresponding media type: `application/json` (including
`application/*+json`) or `application/x-www-form-urlencoded`; unsupported or
missing media types return 415. Media type parameters such as a charset are
accepted. Multipart forms are not supported by this integration.

Contract bodies are read lazily and limited to 1,048,576 bytes by default,
including bodies without a content length. Exceeding the limit returns 413.
Override `max_request_body_size : Int64` on an action to change this limit.
Body reading occurs only for declared body contracts; it does not happen in
the action constructor.

The action body and existing `before`/`after` filters run only after validation
succeeds. For authentication or other checks that must run before body reading,
use `before_request method_name`. These filters support inheritance and `skip`;
render a response and return `byebye` to halt without parsing or validating.
An early halt or validation failure skips the remaining action filters and body.

Override `render_validation_errors(issues : Array(Runcobo::Validation::Issue), *,
status_code : Int32)` to customize error responses. Rules' programming errors
continue to propagate as exceptions. For contracts with constructor dependencies,
override `build_query_contract`, `build_url_contract`, `build_form_contract`, or
`build_json_contract` on the action to return the configured contract instance.

## Migrating from 2.x

Runcobo 3.0 removes the old parameter mode instead of maintaining two parsers:

- Replace `query NamedTuple(...)` (and `url`, `form`, `json`) with a contract class
  containing `schema` declarations. Unsupported declarations fail with a migration
  diagnostic at compile time.
- Replace the merged `params[:field]` access with `input.field` for one source,
  or a source accessor such as `url_input.field` when there are multiple sources.
  There is no implicit source priority or `params[:__action]`; use `self.class.name`
  for the action name.
- Use `optional` for missing fields and `nullable: true` for explicit null. Optional
  output types require nil handling; presence accessors distinguish missing/null.
- Unknown fields now produce errors unless `unknown_keys: :strip` is explicit.
  Repeated scalar fields are errors, and boolean strings must be `true` or `false`.
  The primitive `from_http_param` extensions and `parse_params` helpers are removed.
- Send the correct body media type, account for the default body limit and error
  response statuses, and move authentication to `before_request` when appropriate.
- Nested inputs, array fields and custom conversion types are not yet supported.
  These require request-validation enhancements before those endpoints can migrate.

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
```html
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

# Database access

Runcobo supports [crsql](https://github.com/shootingfly/crsql) through a complete
[PostgreSQL example](examples/crsql/README.md). Request contracts produce typed
inputs, named queries generate typed data-access methods, and actions explicitly
construct their responses. The example includes partial updates with presence
flags and a two-write transaction with rollback on a duplicate book identifier.

Database access is optional: add the `pg` driver to applications that need it.
The framework does not create a global pool or require a database for ordinary
routes. crsql and sqlc are build-time tools; a compiled application runs with its
generated queries and database driver alone.

Use an application-specific subclass of `Runcobo::RouteHandler` and override its
protected `build_action(action_class, context)` hook to attach a typed query
object or service to your own base action. The example opens one application
pool, passes a store through that handler, and closes the pool when the server
scope ends. Caller-managed transactions use `queries.with_transaction(tx)`;
transactional work always uses that store instead of checking out another pool
connection.

Custom handlers work with `Runcobo.start(handlers: ...)` and
`Runcobo::Server.new(handlers: ...)`. They can also be assigned before sockets
are bound. See the example for setup, schema initialization, generation,
running requests, and dedicated-database tests.

## Contributing

### Local development

The development branch requires Crystal >= 1.22.0 and < 2.0.0, with Shards
and Make installed. Automated checks run on Crystal 1.22.0 and 1.22.3.
Installation and development checks require read access to the private
`shootingfly/request-validation` runtime dependency. Generator development checks
also require the private `shootingfly/crsql` repository. Generation uses sqlc
1.31.1; database tests use a dedicated PostgreSQL database.

```shell
git clone https://github.com/runcobo/runcobo.git
cd runcobo
make check
```

If you already have a local clone of request-validation, create the ignored
`shard.override.yml` in the Runcobo root instead of downloading it:

```yaml
dependencies:
  request_validation:
    path: ../request-validation
  crsql:
    path: ../crsql
```

Automated checks use separate read-only deploy keys in the repository secrets
`REQUEST_VALIDATION_SSH_KEY` and `CRSQL_SSH_KEY` to check out pinned dependencies.
They use a temporary dependency override, without embedding credentials in the
shard manifest. Full checks on forks need equivalent private-repository access;
GitHub does not expose upstream secrets to fork pull requests.

`make check` installs dependencies, runs the specs, compiles the example application,
checks formatting in `src` and `spec`, builds `bin/runcobo`, and checks its `--version` and `--help`
commands. It does not install anything into system directories. The same
command runs for pushes and pull requests targeting `main`. Automated checks
also run `make generate-check` and `make integration`; see the database example
for preparing the dedicated test database.

For individual tasks:

```shell
make build         # Build bin/runcobo locally; also the default for make
make test          # Install dependencies and run specs
make examples-check # Compile the example applications without linking
make generate      # Regenerate the crsql example queries (requires sqlc)
make generate-check # Check generation against the committed file
make integration   # Run with DATABASE_URL pointing to runcobo_crsql_test
make format        # Apply formatting to src and spec
make format-check  # Check formatting without changing files
make help          # List development commands
```

Dependencies and the local dependency lock file (`shard.lock`) are ignored in
this library repository. Applications should commit their own lock files.

To install the executable explicitly, use `make install`. The default
installation directory is `/usr/local/bin`; use an existing writable prefix
to avoid requiring elevated permissions:

```shell
make install INSTALL_DIR="$HOME/.local/bin"
```

Add that directory to your shell's command search path before running `runcobo`.

### Submitting changes

1. Fork it (<https://github.com/runcobo/runcobo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write specs and run `make check` (use `make format` to apply formatting)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Shootingfly](https://github.com/shootingfly) - creator and maintainer
