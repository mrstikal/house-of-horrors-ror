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
end
