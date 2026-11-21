require "./spec_helper"
require "file_utils"

class InterruptedUploadFile < File
  @reads = 0

  def read(slice : Bytes) : Int32
    @reads += 1
    raise IO::Error.new("interrupted input") if @reads > 1
    super(slice[0, Math.min(4, slice.size)])
  end
end

describe "atomic upload persistence" do
  it "publishes a complete copy and restores the source position" do
    directory = File.join(Dir.tempdir, "runcobo-atomic-#{UUID.random}")
    Dir.mkdir(directory)
    input = File.tempfile("upload-input")
    input.print("complete uploaded bytes")
    input.flush
    input.seek(3)
    upload = Runcobo::UploadFile.new("file.png", "image/png", input.size, input)
    path = File.join(directory, "published.png")
    begin
      upload.save(path)
      File.read(path).should eq("complete uploaded bytes")
      input.pos.should eq(3)
      Dir.children(directory).should eq(["published.png"])
    ensure
      upload.cleanup
      FileUtils.rm_rf(directory)
    end
  end

  it "preserves an existing destination and removes temporary output after copy failure" do
    [false, true].each do |existing|
      directory = File.join(Dir.tempdir, "runcobo-atomic-#{UUID.random}")
      Dir.mkdir(directory)
      source_path = File.join(directory, "source")
      File.write(source_path, "partial uploaded bytes")
      input = InterruptedUploadFile.new(source_path)
      input.seek(2)
      upload = Runcobo::UploadFile.new("file.png", "image/png", input.size, input)
      destination = File.join(directory, "published.png")
      File.write(destination, "previous complete file") if existing
      begin
        expect_raises(IO::Error, "interrupted input") { upload.save(destination) }
        if existing
          File.read(destination).should eq("previous complete file")
        else
          File.exists?(destination).should be_false
        end
        input.pos.should eq(2)
        Dir.children(directory).sort.should eq(existing ? ["published.png", "source"] : ["source"])
      ensure
        upload.cleanup
        FileUtils.rm_rf(directory)
      end
    end
  end
end
