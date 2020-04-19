module Runcobo
  module Pipe
    class Continue
    end

    def continue
      Runcobo::Pipe::Continue.new
    end

    class Byebye
    end

    def byebye
      Runcobo::Pipe::Byebye.new
    end

    macro skip(method)
      {% SKIPPED_PIPES << method.id %}
    end

    macro before(method)
      {% BEFORE_PIPES << method.id %}
    end

    macro after(method)
      {% AFTER_PIPES << method.id %}
    end

    macro included
      SKIPPED_PIPES = [] of Crystal::Macros::MacroId
      BEFORE_PIPES = [] of Crystal::Macros::MacroId
      AFTER_PIPES = [] of Crystal::Macros::MacroId
      macro inherited
        # :nodoc:
        SKIPPED_PIPES = [] of Crystal::Macros::MacroId
        # :nodoc:
        BEFORE_PIPES = [] of Crystal::Macros::MacroId
        # :nodoc:
        AFTER_PIPES = [] of Crystal::Macros::MacroId
        inherit_pipes
      end
    end

    macro call_before_actions
      {% pipes = BEFORE_PIPES.reject { |x| SKIPPED_PIPES.includes?(x) } %}
      {% for method in pipes %}
        pipe_result = {{ method }}
        if pipe_result.is_a?(Runcobo::Pipe::Byebye)
          return pipe_result
        end
      {% end %}
    end

    macro call_after_actions
      {% pipes = AFTER_PIPES.reject { |x| SKIPPED_PIPES.includes?(x) } %}
      {% for method in pipes %}
        pipe_result = {{ method }}
        if pipe_result.is_a?(Runcobo::Pipe::Byebye)
          return pipe_result
        end
      {% end %}
    end

    # :nodoc:
    macro inherit_pipes
      \{% for v in @type.ancestors.first.constant :BEFORE_PIPES %}
        \{% BEFORE_PIPES << v %}
      \{% end %}

      \{% for v in @type.ancestors.first.constant :AFTER_PIPES %}
        \{% AFTER_PIPES << v %}
      \{% end %}

      \{% for v in @type.ancestors.first.constant :SKIPPED_PIPES %}
        \{% SKIPPED_PIPES << v %}
      \{% end %}
    end
  end
end
