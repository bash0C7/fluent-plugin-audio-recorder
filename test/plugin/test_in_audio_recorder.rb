require "helper"
require "fluent/plugin/in_audio_recorder.rb"

class AudioRecorderInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test "failure" do
    flunk
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::AudioRecorderInput).configure(conf)
  end
end
