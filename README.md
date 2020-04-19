# Runcobo

[![Travis CI build](https://img.shields.io/travis/runcobo/runcobo/master.svg?style=flat-square)](https://travis-ci.org/runcobo/runcobo)
[![Built with Crystal](https://img.shields.io/badge/built%20with-crystal-000000.svg?style=flat-square)](https://crystal-lang.org/)
[![Latest release](https://img.shields.io/github/release/runcobo/runcobo.svg?style=flat-square)](https://github.com/runcobo/runcobo/releases)
[![API docs](https://img.shields.io/badge/api_docs-online-brightgreen.svg?style=flat-square)](https://runcobo.github.io/runcobo/)

Runcobo is an api framework in Crystal. It is in develop now, please don't try.

## Philosophy
* **Simple**      Design must be simple, both in implementation and interface.
* **Intuitive**   Design must be intuitive.
* **Consistent**  Design must be consistent.

## Installation

0. Note: It was in an early version.

1. Add the dependency to your `shard.yml`:

```yaml
dependencies:
  runcobo:
    github: runcobo/runcobo
```

This shard follows Semantic Versioning v2.0.0, so check releases and change the version accordingly.

2. Run `shards install`

## Usage

```crystal
# It don't work now. Please don't try.

require "runcobo"

class Api::V1::Add < BaseAction
  get "/api/v1/add"
  query NamedTuple(a: Int32, b: Int32)

  call do
    sum = query[:a] + query[:b]
    text = "Hello, World! #{query[:a]} + #{query[:b]} = #{sum}"
    render_plain text
  end
end

Runcobo.start
```

## Api

```crystal
class BaseAction
  # Route
  def self.get(url : String)
  def self.post(url : String)
  def self.put(url : String)
  def self.patch(url : String)
  def self.delete(url : String)
  def self.options(url : String)
  def self.head(url : String)

  # Params Definition
  def self.url(named_tuple : NamedTuple.class)
  def self.query(named_tuple : NamedTuple.class)
  def self.form(named_tuple : NamedTuple.class)
  def self.json(named_tuple : NamedTuple.class)

  # Params Call
  def url
  def query
  def form
  def json

  # Call
  def self.call(&block) : HTTP::Server::Context
  def self.layout(filename : String)
  def self.before(method_name : Crystal::Macros::MacroId)
  def self.after(method_name : Crystal::Macros::MacroId)
  def self.skip(method_name : Crystal::Macros::MacroId)

  # Render View
  def render_plain(text : String, *, statu_code :Int32 = 200) : HTTP::Server::Context
  def render_body(body : String, *, statu_code : Int32 = 200) : HTTP::Server::Context
  def render_jbuilder(filename : String, *, layout : String? = nil, status_code = Int32) : HTTP::Server::Context
end

module Runcobo
  # Start
  def self.start(*, host : String? = ENV["HOST"]? || "0.0.0.0", port : Int32 = (ENV["PORT"]? || 3000).to_i)
end

```

## Development

WIP

## Contributing

1. Fork it (<https://github.com/runcobo/runcobo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write and execute specs (`crystal spec`) and formatting checks (`crystal tool format`)
4. Commit your changes (`git commit -am 'Add some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create a new Pull Request

## Contributors

- [Shootingfly](https://github.com/shootingfly) - creator and maintainer
