require "../../../src/runcobo"

{% if Runcobo.has_constant?("Tasks") %}
  {% raise "Runtime imports must not load development tools" %}
{% end %}
