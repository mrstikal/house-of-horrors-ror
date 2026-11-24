require "test_helper"
require "tempfile"

class RoomImageUploadTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @uploaded_blobs = []
    @tempfiles = []
  end

  teardown do
    (@uploaded_blobs || []).each do |blob|
      ActiveStorage::Blob.where(id: blob.id).delete_all
      blob.service.delete(blob.key)
    rescue ActiveStorage::FileNotFoundError
      nil
    end
    (@tempfiles || []).each do |tempfile|
      tempfile.close
      tempfile.unlink
    rescue IOError, SystemCallError
      nil
    end
  end

  test "stores a PNG detected from bytes with a generated filename and the room images service" do
    bytes = png_fixture_bytes
    upload = uploaded_file(bytes: bytes, filename: "untrusted.svg", type: "image/svg+xml")

    result = RoomImageUpload.call(upload)

    assert result[:ok], result[:messages].join(" ")
    blob = track(result[:record])
    assert_match(/\Aroom-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png\z/, blob.filename.to_s)
    assert_equal "image/png", blob.content_type
    assert_equal "room_images", blob.service_name
    assert_equal bytes.bytesize, blob.byte_size
    assert RoomImages.uploads.where(id: blob.id).exists?
    assert blob.service.exist?(blob.key)
  end

  test "accepts JPEG bytes and uses the jpg extension" do
    bytes = File.binread(Rails.root.join("app/assets/images/house_of_horrors/room1.jpg"))
    upload = uploaded_file(bytes: bytes, filename: "photo.jpg", type: "image/jpeg")

    result = RoomImageUpload.call(upload)

    assert result[:ok], result[:messages].join(" ")
    blob = track(result[:record])
    assert_match(/\.jpg\z/, blob.filename.to_s)
    assert_equal "image/jpeg", blob.content_type
    assert RoomImages.uploads.where(id: blob.id).exists?
  end

  test "rejects non-upload values, empty files and files above two megabytes" do
    before = ActiveStorage::Blob.count

    results = [
      RoomImageUpload.call(nil),
      RoomImageUpload.call("not a file"),
      RoomImageUpload.call(uploaded_file(bytes: "")),
      RoomImageUpload.call(uploaded_file(bytes: "x")),
      RoomImageUpload.call(uploaded_file(bytes: "x" * (2.megabytes + 1), filename: "big.png", type: "image/png"))
    ]

    results.each do |result|
      refute result[:ok]
      assert_equal :invalid_input, result[:code]
      assert_equal [ "Upload a PNG or JPEG of at most 2 MiB." ], result[:messages]
    end
    assert_equal before, ActiveStorage::Blob.count
  end

  test "rejects spoofed MIME, SVG and other non-raster magic bytes" do
    before = ActiveStorage::Blob.count
    svg = %q(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>)

    results = [
      RoomImageUpload.call(uploaded_file(bytes: svg, filename: "room.png", type: "image/png")),
      RoomImageUpload.call(uploaded_file(bytes: svg, filename: "room.svg", type: "image/svg+xml")),
      RoomImageUpload.call(uploaded_file(bytes: "GIF89a", filename: "room.gif", type: "image/gif"))
    ]

    results.each do |result|
      refute result[:ok]
      assert_equal :invalid_input, result[:code]
      assert_equal [ "Upload a PNG or JPEG of at most 2 MiB." ], result[:messages]
    end
    assert_equal before, ActiveStorage::Blob.count
  end

  test "maps a storage failure to storage_unavailable without committing a catalog row" do
    service_class = ActiveStorage::Blob.service.class
    assert_equal "ActiveStorage::Service::DiskService", service_class.name
    service_class.alias_method :__test_upload, :upload
    service_class.define_method(:upload) { |*_args, **_kwargs| raise IOError, "disk unavailable" }
    before = RoomImages.uploads.count

    begin
      result = RoomImageUpload.call(uploaded_file(bytes: png_fixture_bytes))
    ensure
      service_class.alias_method :upload, :__test_upload
      service_class.remove_method :__test_upload
    end

    refute result[:ok]
    assert_equal :storage_unavailable, result[:code]
    assert_equal [ "Could not store the image. Try again." ], result[:messages]
    assert_equal before, RoomImages.uploads.count
    assert_equal before, ActiveStorage::Blob.where(service_name: "room_images").count
  end

  test "maps a database timeout to storage_unavailable without committing a catalog row" do
    blob_class = ActiveStorage::Blob.singleton_class
    blob_class.alias_method :__test_create_and_upload, :create_and_upload!
    blob_class.define_method(:create_and_upload!) do |**_kwargs|
      raise ActiveRecord::StatementTimeout, "database is busy"
    end
    before = RoomImages.uploads.count

    begin
      result = RoomImageUpload.call(uploaded_file(bytes: png_fixture_bytes))
    ensure
      blob_class.alias_method :create_and_upload!, :__test_create_and_upload
      blob_class.remove_method :__test_create_and_upload
    end

    refute result[:ok]
    assert_equal :storage_unavailable, result[:code]
    assert_equal [ "Could not store the image. Try again." ], result[:messages]
    assert_equal before, RoomImages.uploads.count
    assert_equal before, ActiveStorage::Blob.where(service_name: "room_images").count
  end

  private

  def png_fixture_bytes
    File.binread(Rails.root.join("test/fixtures/files/room.png"))
  end

  def uploaded_file(bytes:, filename: "upload.bin", type: "application/octet-stream")
    tempfile = Tempfile.new([ "room-image-upload", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    @tempfiles << tempfile

    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: filename, type: type)
  end

  def track(blob)
    @uploaded_blobs << blob
    blob
  end
end
