require "../../../src/runcobo"
Runcobo.views "spec/fixtures/views", layout_dir: "spec/fixtures/layouts"
name = "common/payload"
Runcobo.render_to_string name
