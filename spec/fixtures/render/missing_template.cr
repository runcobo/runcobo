require "../../../src/runcobo"
Runcobo.views "spec/fixtures/views", layout_dir: "spec/fixtures/layouts"
Runcobo.render_to_string "not_present"
