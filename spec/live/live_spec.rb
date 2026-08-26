# frozen_string_literal: true

RSpec.describe "opt-in live Fly API" do
  live = ENV["FLY_IO_LIVE_TESTS"] == "1" && ENV.fetch("FLY_API_TOKEN", nil) && ENV.fetch("FLY_IO_TEST_APP", nil)

  it "reads a disposable app without enabling destructive operations",
     skip: ("set FLY_IO_LIVE_TESTS=1, FLY_API_TOKEN, and FLY_IO_TEST_APP" unless live) do
    response = FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN")).apps.get(app_name: ENV.fetch("FLY_IO_TEST_APP"))
    expect(response.status).to eq(200)
  end

  it "keeps destructive live operations behind a second explicit flag",
     skip: ("set FLY_IO_DESTRUCTIVE_LIVE_TESTS=1 in a disposable environment" unless ENV["FLY_IO_DESTRUCTIVE_LIVE_TESTS"] == "1") do
    expect(ENV.fetch("FLY_IO_LIVE_TESTS")).to eq("1")
  end
end
