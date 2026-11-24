require "test_helper"

class FoundationTest < ActionDispatch::IntegrationTest
  class Probe < Trailblazer::Operation
    step :first_step
    step :second_step

    def first_step(ctx, allow:, **)
      ctx[:first] = true
      return true if allow

      ctx[:code] = :refused
      ctx[:messages] = [ "Refused." ]
      false
    end

    def second_step(ctx, **)
      ctx[:second] = true
      true
    end
  end

  test "uses the exact Rails version" do
    assert_equal "8.1.4.1", Rails.version
  end

  test "runs the Ruby version from .ruby-version" do
    assert_equal RUBY_VERSION, File.read(Rails.root.join(".ruby-version")).strip
  end

  test "connects through the selected adapter" do
    connection = ActiveRecord::Base.connection
    db_config = connection.pool.db_config

    case ENV.fetch("HOH_DB", "sqlite")
    when "sqlite"
      assert_equal "SQLite", connection.adapter_name
      assert_equal "sqlite3", db_config.adapter
      assert_equal "schema.rb", db_config.schema_dump
      assert_match(%r{storage/test.*\.sqlite3\z}, db_config.database)
    when "mysql"
      assert_equal "Mysql2", connection.adapter_name
      assert_equal "mysql2", db_config.adapter
      assert_equal "mysql_schema.rb", db_config.schema_dump
      assert_match(/\Ahouse_of_horrors_test/, db_config.database)

      collation, engine = connection.select_rows("SELECT @@collation_database, @@default_storage_engine").first
      assert_equal "utf8mb4_0900_bin", collation
      assert_equal "InnoDB", engine
    else
      flunk "Unexpected HOH_DB=#{ENV.fetch("HOH_DB")}"
    end
  end

  test "renders the home page from HAML" do
    get "/"

    assert_response :success
    assert_includes ActionView::Template::Handlers.extensions, :haml
    assert_includes response.body, "<h1>House of Horrors</h1>"
    assert_includes response.body, "Homepage"
    assert File.exist?(Rails.root.join("app/views/home/show.html.haml"))
    assert File.exist?(Rails.root.join("app/views/layouts/application.html.haml"))
    refute File.exist?(Rails.root.join("app/views/home/show.html.erb"))
    refute File.exist?(Rails.root.join("app/views/layouts/application.html.erb"))
  end

  test "bootstraps the room picker with escaped config and a module bundle" do
    description = "He said \"boo\" & <script>alert(\"x\")</script>"
    room = Room.create!(
      name: "Quoted Room",
      description: description,
      capacity: 3,
      image_key: "kitchen"
    )

    travel_to Time.utc(2026, 11, 24, 12, 0, 0) do
      get "/"

      assert_response :success
      assert_select "header.home-header"
      assert_select "#booking-root[data-config]" do |elements|
        config = JSON.parse(elements.first["data-config"])

        assert_equal Room.order(:id).pluck(:id), config["rooms"].map { |entry| entry["id"] }
        assert_equal "2026-11-24", config["today"]
        assert_equal "/api/availability", config["availability_path"]
        assert_equal "/api/reservations", config["reservations_path"]

        entry = config["rooms"].find { |candidate| candidate["id"] == room.id }
        assert_equal [ "capacity", "description", "id", "image_url", "name" ], entry.keys.sort
        assert_equal room.id, entry["id"]
        assert_equal room.name, entry["name"]
        assert_equal description, entry["description"]
        assert_equal room.capacity, entry["capacity"]
        assert_equal ApplicationController.helpers.room_image_url(room), entry["image_url"]
        assert_match(%r{\A/assets/house_of_horrors/room3-[0-9a-f]+\.jpg\z}, entry["image_url"])

        raw_config = elements.first["data-config"]
        refute_includes raw_config, "<"
        refute_includes raw_config, ">"
        assert_includes raw_config, "\\u003cscript\\u003e"
      end

      assert_operator response.body.index("home-header"), :<, response.body.index("booking-root")
      assert_select "script[type='module'][src]", count: 1
      script = css_select("script[type='module'][src]").first["src"]
      assert_match(%r{\A/assets/booking(-[0-9a-f]+)?\.js\z}, script)
      assert_select "script", count: 1
      refute_includes response.body, "<script>alert"
    end
  end

  test "serves the bundled house and room images" do
    get "/"

    assert_response :success

    house_src = nil
    assert_select "header.home-header" do
      assert_select "h1", "House of Horrors"
      assert_select "img[alt='Entrance to the House of Horrors'][width='1536'][height='656']" do |images|
        house_src = images.first["src"]
      end
    end

    assert_match(%r{\A/assets/house_of_horrors/house-[0-9a-f]+\.jpg\z}, house_src)
    assert_asset_bytes(house_src, Rails.root.join("sources/house.jpg"))

    RoomImages.keys.each do |key|
      url = ApplicationController.helpers.room_image_url(Room.new(image_key: key))
      assert_asset_bytes(url, Rails.root.join("sources", File.basename(RoomImages.path_for(key))))
    end
  end

  test "a successful operation reaches the second step" do
    result = Probe.call(allow: true)

    assert result.success?
    assert_equal true, result[:first]
    assert_equal true, result[:second]
  end

  test "a refused operation skips the second step and keeps its failure data" do
    result = Probe.call(allow: false)

    refute result.success?
    assert_equal true, result[:first]
    assert_nil result[:second]
    assert_equal :refused, result[:code]
    assert_equal [ "Refused." ], result[:messages]
  end

  private

  def assert_asset_bytes(url, source_path)
    get url

    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal File.binread(source_path), response.body.b
  end
end
