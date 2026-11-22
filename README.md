# Runcobo

[![Crystal CI](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml/badge.svg)](https://github.com/runcobo/runcobo/actions/workflows/crystal.yml)
[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Latest release](https://img.shields.io/github/release/runcobo/runcobo.svg?style=flat-square)](https://github.com/runcobo/runcobo/releases)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://runcobo.github.io/runcobo/)

# Introduction

Runcobo is a general purpose framework built on Crystal.

Runcobo 3.0 uses request-validation contracts for typed request inputs. It is a
breaking change from 2.x; see the migration notes below. Version `3.0.0` depends
on the tagged jbuilder `1.1.0` and private request-validation `0.1.0` releases.

### Commands

```text
cobo [--root PATH] COMMAND [arguments...]

  routes                      Print application routes
  version                     Print the Runcobo framework version
  dev                         Prepare and start the development server
  db                          Manage local databases and migrations
  generate [--check]          Generate or verify typed queries
  crsql [arguments...]        Run the default generator
  --help                      Show all commands
```

### Route inspection

`cobo routes` compiles and loads `src/app.cr` to inspect registered actions. It
also supports the legacy `src/runcobo.cr` layout, including `src/actions/`.
For another layout, select the file that registers actions with `--require`.
The command does not select `src/main.cr`, which normally starts the server.

```sh
bin/cobo routes
bin/cobo --root ../another-app routes
bin/cobo routes --require src/route_loader.cr
bin/cobo routes --no-color > routes.txt
```

The table displays method, path and action columns with a route count. Colors
are enabled for terminal output, disabled for redirected output, `NO_COLOR`,
or a `dumb` terminal, and can be overridden with `--color` or `--no-color`.
Route registration order and complete paths/action names are preserved.
Temporary inspection files have unique names and are removed after success or
compilation failure; existing project files are not overwritten. Projects do
not need database tool configuration to list routes.

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
./bin/cobo --version
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
    version: 3.0.0
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

### Validate directly inside an action

For a request-level contract, call `validate` in the action body:

```crystal
class Authors::Create < BaseAction
  post "/authors"

  call do
    input = validate(CreateAuthorContract)
    render_json({name: input.name, bio: input.bio}, status_code: 201)
  end
end
```

This returns the contract's native `Output`. Unknown fields are stripped by
default; use `validate(CreateAuthorContract, strict: true)` to reject them.
Failures raise `Runcobo::Validation::Failure`, unwind the action body, and reach
`render_validation_errors`. Code after a failed validation and `after` filters
do not run. Programming errors in rules continue to propagate normally.

Request-level input combines query fields, ordinary body fields and route
fields. Structured body fields replace same-named query fields; route fields
replace either. Ordinary form values append to query values, so repeated scalar
fields remain errors. Query and form requests use native `from_params`
conversions. Requests with a structured body use `from_json` for the combined
object: query and route values remain strings in that mode. Use the separate
source contracts below when sources need independent conversion or validation.
An empty structured body is treated as an empty object for this entry.

To check body format even on actions without a contract, opt in after your
authentication filter:

```crystal
abstract class AppAction < BaseAction
  before_request authenticate
  before_request read_input
end
```

`read_input` checks format and caches input; `validate(Contract)` checks fields.
No empty contract is needed. `skip read_input` skips inherited preparation for
an unconditional endpoint. Read-only `GET` and `HEAD` requests ignore the body.
Multipart fields use native parameter conversions; uploaded files are accessed
separately with `upload` or `uploads`.

### Declare separate source contracts

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

Contracts support `String`, `Int32`, `Int64`, `Float64`, `Bool`, `JSON::Any`,
scalar arrays and nested contracts. Optional fields may be missing; explicit null requires
`nullable: true`. Use the generated `field_present?` accessor to distinguish
missing fields from explicit null when updating records. Required strings can
still be empty; add a constraint or rule when blank strings are invalid.

Query, path and form values use the contract's string conversions. Contract
booleans accept only `true` and `false`, and repeated scalar query/form fields
are rejected. Structured bodies retain their native types: strings are not
converted into numbers or booleans. Unknown fields are stripped by default, matching `validate`;
use `query SomeContract, unknown_keys: :reject` (or the corresponding source)
to reject them explicitly.

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
accepted. A `form` contract also accepts ordinary fields from `multipart/form-data`;
files are kept separately from contract fields. Malformed multipart bodies return 400.

Contract bodies are read lazily and limited to 1,048,576 bytes by default,
including bodies without a content length. Exceeding the limit returns 413.
Override `max_request_body_size : Int64` on an action to change this limit.
Reading starts when a body contract, direct validation, `read_input`, or explicit
middleware buffering needs it; it does not happen in the action constructor.

Both contract styles and `read_input` share `request.runcobo_input`: raw bytes,
parsed query/form fields and parsed structured input are cached per request.
Middleware can set `request.runcobo_input.max_body_size` and call `body` to enforce
a limit using the same buffer for non-multipart requests. For multipart requests,
middleware only configures the limit; the parser counts bytes while receiving
parts, without caching the entire body string. Declared contract results are
cached per action; explicit `validate`
calls run their contracts against the cached input on each call. There is no
second parser or additional coercion layer.

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
- Both contract entry styles strip unknown fields by default. Explicit rejection uses `strict: true` with `validate`, or `unknown_keys: :reject` with a source declaration.
  Repeated scalar fields are errors, and boolean strings must be `true` or `false`.
  The primitive `from_http_param` extensions and `parse_params` helpers are removed.
- Send the correct body media type, account for the default body limit and error
  response statuses, and move authentication to `before_request` when appropriate.
- Nested contracts and scalar arrays are supported. Custom conversion types are not.
- Declare field constraints in `schema`, for example
  `required :count, Int64, gteq: 2, lteq: 100`. Their error codes, paths and
  parameters pass through the same validation response as custom rules.

# Explicit empty and missing responses

Actions explicitly declare `head` routes and choose their response. Runcobo does
not fall back from `HEAD` to `GET`, or globally remove response bodies for `HEAD`
or status 304. Use `render_empty` before writing any output:

```crystal
class Status::Show < BaseAction
  get "/status"
  head "/status"

  call do
    if request.method == "HEAD"
      render_empty content_type: "application/json"
    else
      render_json({status: "ok"})
    end
  end
end
```

`render_empty status_code: 304` also returns an empty conditional response when
chosen by an action. It sets status and optional content type without rendering a
template or clearing previously written data. Set representation headers such as
`ETag` and `Content-Length` in the action when needed.

Customize missing routes without an additional middleware class:

```crystal
Runcobo::RouteNotFoundHandler.new do |context|
  context.response.status_code = 404
  context.response.content_type = "application/json"
  context.response.print(%({"error":"not_found"})) unless context.request.method == "HEAD"
end
```

The callback owns the complete missing response, including empty bodies. Without
a callback, the existing 404 text response is unchanged.

# Static files and uploads

Mount a directory by placing `StaticFiles` before the action router:

```crystal
Runcobo.start handlers: [
  Runcobo::StaticFiles.new("/assets", directory: "public", cache_control: "public, max-age=300"),
  Runcobo::RouteHandler.new,
  Runcobo::RouteNotFoundHandler.new,
] of HTTP::Handler
```

`/assets/css/app.css` reads `public/css/app.css`. The wrapper reuses Crystal's
static file handler for content types, conditional caching, precompressed files
and range reads. Directory listing is disabled; paths and symlinks must remain
inside the configured directory. A missing directory can be created later.
Unmatched prefixes and missing files fall through to the next handler; missing
`HEAD` responses return 404 without a body. Static mounts accept `GET` and `HEAD`,
with no body sent for `HEAD`. Other methods return 405 with `Allow: GET, HEAD`.
This does not add implicit `HEAD` routes to actions. The optional `cache_control`
value is applied only to existing files and their conditional responses, not
missing files or rejected methods.

Receive files in an ordinary action:

```crystal
Dir.mkdir_p("storage/uploads")

class Files::Create < BaseAction
  post "/files"

  call do
    file = upload("file")
    name = Random::Secure.hex(16)
    file.save("storage/uploads/#{name}")
    render_json({name: name, filename: file.filename, size: file.size})
  end
end
```

`upload("file")` returns one `Runcobo::UploadFile`; missing or repeated single-file
fields use the normal validation error hook. `uploads("files")` returns an array,
or an empty array when absent. Ordinary fields continue to use `validate(Contract)`
or a declared `form` contract. Multipart input is parsed once regardless of the
access order, and file parts do not appear as unknown ordinary fields.

The object exposes `filename`, `content_type`, actual byte `size`, and a seekable
temporary `file`. `save(path)` copies the entire file without changing the read
position; the application prepares the directory and chooses the destination.
Names and content types come from client metadata and do not determine storage paths.

Files go directly to temporary files. The entire request, including fields,
headers and multipart epilogues, uses `max_request_body_size`; the default is
1,048,576 bytes. Override it for larger uploads. Each multipart request also has
fixed limits of 100 files and 1,000 fields. Limits return 413 and malformed input
returns 400 through the existing validation hook.

The `call do ... end` lifecycle closes and deletes temporary files on normal
completion, early returns and exceptions. Failed parsing also cleans files
already received. Files persisted by `save` remain; retain a saved file rather
than a request-owned temporary file for work after the action returns. File
storage policy, image processing and business validation remain in the application.

# Request addresses and trusted proxies

Requests expose `base_url`, `scheme`, `protocol`, `host`, `port`, `ssl?` and
`remote_ip`. The base address contains the scheme, host and non-default port,
without the path or query. The transport determines the scheme for direct
connections, including encrypted listeners. The peer address is retained on
the server context; `remote_ip` is the resolved client address, or `nil` when
there is no network peer.

```crystal
proxy_config = Runcobo::ProxyConfig.new(
  trusted_proxies: ["127.0.0.1", "10.0.0.0/8", "2001:db8::/48"],
)
Runcobo.start(proxy_config: proxy_config)
```

No proxies are trusted by default. Only a trusted direct peer can supply
`X-Forwarded-Proto`, `X-Forwarded-Host`, `X-Forwarded-Port` or `X-Forwarded-For`.
The last scheme, host and port values describe the nearest trusted proxy's
external request. Only `http` and `https` schemes are accepted. Invalid metadata
falls back to the direct request/transport. Missing or invalid `Host` values
fall back to the local listener address, or `localhost` for standalone requests.
Default ports are omitted from `base_url`; literal hosts with colons are bracketed.

The client address chain is walked from right to left, starting at the direct
peer, until an untrusted address is reached. Values to its left are ignored.
An invalid address encountered while traversing the trusted suffix causes a
fallback to the direct peer. Address headers must contain literal addresses
without ports. `Forwarded` and `Client-Ip` are not used; normalize the proxy
configuration to the documented `X-Forwarded-*` header family.

Provider-specific single-address headers are opt-in:

```crystal
proxy_config = Runcobo::ProxyConfig.new(
  trusted_proxies: ["127.0.0.1"],
  client_ip_header: "CF-Connecting-IP",
)
```

This header takes precedence when present; an invalid value falls back to the
peer. When absent, the ordinary address chain is used. Neither `CF-Connecting-IP`
nor `X-Real-IP` is read automatically. Configure trusted proxies to strip or
overwrite client-supplied forwarding and provider headers with correct external
request information.

`Runcobo::Server` installs `RequestInfoHandler` before application handlers,
including custom handler lists. A supplied `RequestInfoHandler` takes precedence
over the server's implicit handler and configuration. When composing a chain
directly with `HTTP::Server.build_middleware`, install
`Runcobo::RequestInfoHandler.new(proxy_config)` before handlers that use request
metadata. Configuration is scoped to each server/handler. Fixed public addresses
belong to application link generation; they do not change `request.base_url`.
Crystal's existing `hostname` and deprecated `host_with_port` retain their native
raw-header behavior; use `host`, `port` and `base_url` for resolved metadata.

# Pagination

`Runcobo::Pagination` holds the page, page size and 64-bit offset used by queries
and templates. Validate request fields with a contract before constructing it:

```crystal
pagination = Runcobo::Pagination.new(
  input.page,
  input.per_page,
  default_per_page: 20,
  max_per_page: 100,
)
# Use pagination.offset and pagination.per_page in database queries.
page_items = pagination.slice(items)
```

The default page is 1, the default page size is 20 and the maximum page size is
100. These page size settings can be configured per instance; they must be
positive and the default must not exceed the maximum. Missing or nonpositive
pages become 1, pages above `Int32::MAX` are capped, missing or nonpositive page
sizes use the configured default, and larger sizes use the configured maximum.
`slice` returns an empty array for a page beyond the list, including very large
offsets. This normalization does not replace request contract validation.

# Render

### Configure templates and render the current action

Configure the view root once, before declaring actions:

```crystal
Runcobo.views "src/actions", engine: :jbuilder,
  layout_dir: "src/web/templates/layouts"

abstract class AppAction < BaseAction
  layout "application"
end

class Notes::Create < AppAction
  post "/notes"
  call do
    title = "Hello"
    render status_code: 201
  end
end
```

This renders `src/actions/notes/create.jbuilder` with
`src/web/templates/layouts/application.jbuilder`. Configure `engine: :water`
to use Water by default. Without configuration the defaults are `src/views`,
jbuilder, and `src/views/layouts`. The configuration also registers jbuilder
partials, so a separate `Jbuilder.templates` declaration is unnecessary.

- `render` infers the template from the action's qualified class name.
- `render :create` or `render "create"` selects a template in the current
  action namespace. Names containing `/`, such as `"notes/create"`, are relative
  to the configured root.
- `dir: "other/templates"` sets an explicit root and skips the action namespace.
- Layouts inherit from the action class. `layout: "alternative"` overrides one
  render; `layout: nil` disables it. Declare `layout nil` to disable it for an
  action class. The existing `layout ""` convention is also supported.
- `engine: :water` or `engine: :jbuilder` overrides the configured engine.

Use `render_to_string` with the same options to obtain a string without changing
the response body, status or headers. Inside an action it infers the same path and
inherits the same layout as `render`. In helpers, provide a root-relative name:

```crystal
body = Runcobo.render_to_string "notes/partials/event", layout: nil
```

The helper entry has no action context and defaults to no layout. Templates retain
access to local variables in the calling scope. Paths, engines and layouts are
checked at compile time. The explicit `render_jbuilder` and `render_water`
entries remain available; their template names are relative to the configured
root, including names without `/`.

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

Register reusable jbuilder templates once with `Runcobo.views "src/views"`
(or `Jbuilder.templates "src/views"` when using the explicit engine entries
without view configuration).
Declare their named locals on the first line and pass those locals explicitly.
Partials run in separate methods on the current builder, so they do not capture
or overwrite the action's local variables. Paths and locals are checked at build
time; running the compiled application does not read template files.

For example,

*src/views/books/index.jbuilder*
```crystal
json.array! "books", books do |json, book|
  json.partial! "books/_base_book", book: book
end
```

*src/views/books/_base_book.jbuilder*
```crystal
# locals: book
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

## Project development commands

The `cobo` executable includes local database management, migration verification,
structure snapshots and native crsql generation. These commands read `runcobo.yml`;
the running application does not read that file or load the development tools.
The framework, shard name and `runcobo.yml` configuration keep the Runcobo name.
Existing Make targets, including `make runcobo`, remain available. Build the
executable from an application's installed framework dependency:

```sh
shards install --frozen
mkdir -p bin
crystal build lib/runcobo/src/cli.cr -o bin/cobo
```

Create a development-only `runcobo.yml` (no production credentials):

```yaml
name: example
database_prefix: example
database_user: example
database_port: 55439
# Optional application commands and environment:
seed_command: [crystal, run, src/seed.cr]
server_command: [crystal, run, src/main.cr]
development_environment:
  HOST: "127.0.0.1"
  PORT: "3000"
# Optional: create a private, persistent local signing secret.
secret_environment: JWT_SECRET
public_base_environment: PUBLIC_BASE_URL
```

The PostgreSQL tools manage only `example_development` and `example_test` on a
loopback host. They never use `DATABASE_URL` to select a development or test database;
explicit overrides are `DEVELOPMENT_DATABASE_URL` and `TEST_DATABASE_URL`, validated
against the same host and database restrictions. The owned cluster, logs and secret
live under `.local/`; add `/.local/`, `/bin/` and `/db/schema.snapshot.sql` to the
application's ignore file. PostgreSQL server and client programs must be on the
command search path. An existing cluster requires the matching ownership marker.

```sh
bin/cobo db prepare development  # Create the local database and apply migrations
bin/cobo db seed development     # Run the optional seed command
bin/cobo dev                     # Prepare, seed and start the configured server
bin/cobo db migrate test
bin/cobo db rollback test        # Undo the most recent migration
bin/cobo db verify               # Verify rollback and replay in a temporary test schema
bin/cobo db snapshot             # Read-only db/schema.snapshot.sql, never an input
bin/cobo generate
bin/cobo generate --check        # Generate in a temporary directory and compare
bin/cobo crsql --help            # Forward arguments to the default generator
```

Keep structure changes in `db/migrations/YYYYMMDDHHMMSS_description.sql`, with one
matching version in `db/rollbacks/`. Applied files are immutable: the ledger records
their checksums. Migration and rollback writes share a local process lock and commit
with their ledger changes in one transaction. `db verify` replays each migration,
its rollback and the migration again, comparing catalog structure, indexes and
comments. Replay requires unqualified statements confined to the temporary schema.
It does not verify restoration of business data. Snapshot export requires `pg_dump`
compatible with the local database; export and cleanup must succeed before the
previous snapshot is replaced atomically.

Maintain named queries in `db/queries/` and the native `sqlc.yaml` configuration:

```yaml
version: "2"
plugins:
  - name: crystal
    process:
      cmd: crsql
      format: json
sql:
  - engine: postgresql
    schema: db/migrations
    queries: db/queries
    codegen:
      - plugin: crystal
        out: src/persistence/generated
        options:
          module: Example::Store
          emit_table_models: true
```

Migrations are the only structure source; snapshots are optional generated references.
The first generator command installs the framework-pinned private crsql dependency
under `.local/runcobo/codegen/` and compiles `bin/crsql`. Subsequent calls reuse it;
a framework toolchain change triggers a rebuild. This requires private repository
read access, Crystal, Shards and sqlc 1.31.1. Projects do not need a crsql dependency
in their application manifest. The framework distributes only a pinned dependency
manifest, not private generator source. Compiled applications need only their
generated queries and database driver, without the generator or development cache.

Configuration also accepts `migration_directory`, `rollback_directory`,
`generator_config`, `generator_inputs`, `generator_binary`, `generated_directory`
and `snapshot_path`. Paths are relative to the project root. If paths change,
keep the native `sqlc.yaml` inputs/output and `generator_inputs` consistent.
`--root PATH` selects another project directory. For custom development integrations,
`require "runcobo/tasks"` exposes `Runcobo::Tasks` without loading application actions
or server code. Business conventions and migration acceptance reports belong in
the consuming project, outside the framework commands.

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

`make check` installs dependencies, builds the framework and development generator, runs the specs, compiles the example application,
checks formatting in `src` and `spec`, builds `bin/cobo`, and checks its `--version` and `--help`
commands. It does not install anything into system directories. The same
command runs for pushes and pull requests targeting `main`. Automated checks
also run `make generate-check` and `make integration`; see the database example
for preparing the dedicated test database.

For individual tasks:

```shell
make build         # Build bin/cobo locally; also the default for make
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

Add that directory to your shell's command search path before running `cobo`.

### Submitting changes

1. Fork it (<https://github.com/runcobo/runcobo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write specs and run `make check` (use `make format` to apply formatting)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Shootingfly](https://github.com/shootingfly) - creator and maintainer

Request-level contracts retain field decoding modes when combining sources: query
and route fields use parameter conversions, while structured body fields retain
strict native types. Body fields replace query fields and route fields take
precedence. Validation, constraints and cross-field rules run once on the merged
input. Explicit source contracts continue to validate only their declared source.

`REUSE_PORT` accepts `true` or `false` and defaults to `false` when absent. Other
values fail at startup rather than enabling port reuse through string presence.

A certificate and private key must be configured together. Supplying only one
fails before binding a socket. Response observers can use `headers_sent?` to
distinguish a failure before headers from an interrupted response stream.


Server shutdown stops admission and keeps `listen` blocked until active handlers
finish, before callers release their dependencies. `shutdown_timeout` defaults to
30 seconds and can be supplied to `Runcobo.start` or the server instance. Requests
exceeding the grace period are reported; repeated `close` calls are harmless.

`UploadFile#save` writes to a temporary file beside the destination and renames it
only after copying succeeds. A failed copy removes its temporary output and
preserves an existing destination.

Framework logs use the global Crystal logging builder under the `runcobo` source.
`Log.setup`, `Log.setup_from_env`, and `Log.capture` control both framework and
application output. `Runcobo.logger` now configures that shared pipeline. The
native `LogHandler` owns request IDs, elapsed time and completion/failure logs;
query values are excluded. `request.request_id` is now `String?` to preserve opaque
incoming request IDs and matches the `X-Request-Id` response header.
