require "../../../src/runcobo"
Runcobo.views "spec/fixtures/views", layout_dir: "spec/fixtures/layouts"
message = "test"
Runcobo.render_to_string "common/payload", layout: "not_present"
