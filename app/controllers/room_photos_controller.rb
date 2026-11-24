class RoomPhotosController < ApplicationController
  def show
    blob = find_uploaded_blob
    return head :not_found unless blob
    return head :not_found unless Room.exists?(image_blob_id: blob.id)

    bytes = blob.download_chunk(0...blob.byte_size)
    return head :not_found unless bytes && bytes.bytesize == blob.byte_size

    send_data bytes,
      type: blob.content_type,
      disposition: "inline",
      headers: { "X-Content-Type-Options" => "nosniff" }
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end

  private

  def find_uploaded_blob
    id = BookingSlots.parse_id(params[:id])
    return nil unless id

    RoomImages.uploads.find_by(id: id)
  end
end
