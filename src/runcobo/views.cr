require "jbuilder"
require "water"

module Runcobo
  # Configure once before declaring actions. Paths are relative to the project root.
  macro views(root, *, engine = :jbuilder, layout_dir = nil)
    {% unless root.is_a?(StringLiteral) && (layout_dir == nil || layout_dir.is_a?(StringLiteral)) %}
      {% root.raise "View directories must be string literals" %}
    {% end %}
    {% unless [:jbuilder, :water].includes?(engine) %}
      {% engine.raise "View engine must be :jbuilder or :water" %}
    {% end %}
    {% if ::Runcobo.resolve.has_constant?("VIEW_OPTIONS") %}
      {% root.raise "Runcobo.views may only be configured once" %}
    {% end %}
    {% layouts = layout_dir || (root.empty? || root.ends_with?("/") ? root + "layouts/" : root + "/layouts/") %}
    module ::Runcobo
      VIEW_OPTIONS = {root: {{root}}, engine: {{engine}}, layout_dir: {{layouts}}}
    end
    {% if engine == :jbuilder %}
      {% if ::Jbuilder.resolve.has_constant?("TEMPLATE_ROOT") %}
        {% unless ::Jbuilder.resolve.constant("TEMPLATE_ROOT") == root %}
          {% root.raise "Jbuilder templates are already registered with a different root" %}
        {% end %}
      {% else %}
        ::Jbuilder.templates {{root}}
      {% end %}
    {% end %}
  end

  # Render outside an action, with a path relative to the configured root.
  macro render_to_string(template, *, layout = nil, dir = nil, layout_dir = nil, engine = nil)
    ::Runcobo::Views.render {{template}}, layout: {{layout}}, dir: {{dir}}, layout_dir: {{layout_dir}}, engine: {{engine}}
  end

  # Shared compile-time path, layout and engine handling for all render entries.
  module Views
    macro render(template = nil, *, action_type = nil, relative_to_action = true,
                 layout = :inherit, dir = nil, layout_dir = nil, engine = nil,
                 context = nil, status_code = 200)
      {% options = ::Runcobo.resolve.has_constant?("VIEW_OPTIONS") ? ::Runcobo.resolve.constant("VIEW_OPTIONS") : {root: "src/views/", engine: :jbuilder, layout_dir: "src/views/layouts/"} %}
      {% selected_engine = engine || options[:engine] %}
      {% unless [:jbuilder, :water].includes?(selected_engine) %}
        {% selected_engine.raise "View engine must be :jbuilder or :water" %}
      {% end %}
      {% unless template == nil || template.is_a?(StringLiteral) || template.is_a?(SymbolLiteral) %}
        {% template.raise "Template names must be string or symbol literals" %}
      {% end %}
      {% unless (dir == nil || dir.is_a?(StringLiteral)) && (layout_dir == nil || layout_dir.is_a?(StringLiteral)) %}
        {% raise "View directories must be string literals" %}
      {% end %}
      {% type = action_type ? action_type.resolve : nil %}
      {% parts = type ? type.name.split("::").map(&.underscore) : [] of String %}
      {% if template == nil && parts.empty? %}
        {% raise "A template name is required outside an action" %}
      {% end %}
      {% name = template ? template.id.stringify : parts.last %}
      {% if name.empty? %}
        {% raise "Template names must not be empty" %}
      {% end %}
      {% if dir == nil && relative_to_action && !name.includes?("/") && parts.size > 1 %}
        {% name = parts[0, parts.size - 1].join("/") + "/" + name %}
      {% end %}
      {% root = dir || options[:root] %}
      {% prefix = root.empty? || root.ends_with?("/") ? root : root + "/" %}
      {% filename = prefix + name + "." + selected_engine.id.stringify %}
      {% unless file_exists?(filename) %}
        {% raise "Template not found: #{filename.id}" %}
      {% end %}
      {% selected_layout = layout %}
      {% if layout == :inherit || layout == "" %}
        {% owner = type ? ([type] + type.ancestors).find { |candidate| candidate.has_constant?("LAYOUT") } : nil %}
        {% selected_layout = owner ? owner.constant("LAYOUT") : nil %}
      {% end %}
      {% layout_file = nil %}
      {% unless selected_layout == nil || selected_layout == false || selected_layout == "" %}
        {% unless selected_layout.is_a?(StringLiteral) || selected_layout.is_a?(SymbolLiteral) %}
          {% selected_layout.raise "Layouts must be string or symbol literals, or nil" %}
        {% end %}
        {% layouts = layout_dir || options[:layout_dir] %}
        {% layout_prefix = layouts.empty? || layouts.ends_with?("/") ? layouts : layouts + "/" %}
        {% layout_file = layout_prefix + selected_layout.id.stringify + "." + selected_engine.id.stringify %}
        {% unless file_exists?(layout_file) %}
          {% raise "Layout not found: #{layout_file.id}" %}
        {% end %}
      {% end %}
      begin
        %body = String.build do |%output|
          {% if selected_engine == :jbuilder %}
            ::Jbuilder.embed {{filename}}, %output, {{layout_file}}
          {% else %}
            {% if layout_file %}
              ::Water.embed {{filename}}, %output, {{layout_file}}
            {% else %}
              ::Water.embed {{filename}}, %output
            {% end %}
          {% end %}
        end
        {% if context %}
          {{context}}.response.content_type = {{selected_engine == :jbuilder ? "application/json" : "text/html"}}
          {{context}}.response.status_code = {{status_code}}
          {{context}}.response.print(%body)
          {{context}}
        {% else %}
          %body
        {% end %}
      end
    end
  end
end
