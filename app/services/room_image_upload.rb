class RoomImageUpload
  EXTENSIONS = {
    "image/png" => "png",
    "image/jpeg" => "jpg"
  }.freeze
  INVALID_INPUT_MESSAGE = "Upload a PNG or JPEG of at most 2 MiB."
  STORAGE_UNAVAILABLE_MESSAGE = "Could not store the image. Try again."

  def self.call(upload)
    new.call(upload)
  end

  def call(upload)
    io = upload_io(upload)
    return failure(:invalid_input, INVALID_INPUT_MESSAGE) unless io

    content_type = detect_content_type(io)
    return failure(:invalid_input, INVALID_INPUT_MESSAGE) unless content_type

    success(store(io, content_type))
  rescue IOError, SystemCallError, ActiveStorage::IntegrityError,
         ActiveRecord::StatementTimeout, ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked,
         SQLite3::LockedException
    failure(:storage_unavailable, STORAGE_UNAVAILABLE_MESSAGE)
  end

  private

  def upload_io(upload)
    return nil unless upload.is_a?(ActionDispatch::Http::UploadedFile)
    return nil unless RoomImages::UPLOAD_BYTE_RANGE.cover?(upload.size)

    io = upload.tempfile
    return nil unless io.respond_to?(:read) && io.respond_to?(:rewind)

    io
  end

  def detect_content_type(io)
    io.rewind
    content_type = Marcel::MimeType.for(io)
    io.rewind

    EXTENSIONS.key?(content_type) ? content_type : nil
  end

  def store(io, content_type)
    filename = "room-#{SecureRandom.uuid}.#{EXTENSIONS.fetch(content_type)}"

    blob = nil
    ActiveRecord::Base.transaction do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: "room_images",
        identify: false
      )
    end
    blob
  end

  def success(record)
    { ok: true, record: record, code: nil, messages: [] }
  end

  def failure(code, message)
    { ok: false, record: nil, code: code, messages: [ message ] }
  end
end
