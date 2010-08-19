require "rack/test"
require "webrat"
require "test/unit"
require "main"

Webrat.configure do |config|
  config.mode = :rack
end

class AppTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Webrat::Methods
  include Webrat::Matchers

  def app
    MediaprocessorApi.new
  end

  def test_it_works
    visit "/"
    assert_contain "it works"
  end

  def test_create_avatar
    data = File.read("api-request.xml")
    p data
    resp = visit "/media/create", :put, :xml => data
    assert resp.ok?, "bad response status"
    assert_contain "ok"
  end
end
