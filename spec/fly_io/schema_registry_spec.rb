# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "SDK loading under the C locale" do
  it "loads the UTF-8 schema registry and coerces nested models without RUBYOPT" do
    script = <<~RUBY
      require "fly_io"
      app = FlyIO::Models::App.new("organization" => {"slug" => "personal"})
      puts app.organization.slug
    RUBY

    stdout, stderr, status = Open3.capture3(
      {"LC_ALL" => "C", "LANG" => "C", "RUBYOPT" => nil, "RUBYLIB" => nil},
      RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script
    )

    expect(status.success?).to be(true), stderr
    expect(stdout).to eq("personal\n")
  end
end
