require "mongo"
require "support/clock"

RSpec.configure do |config|

  config.before :suite do
    $mongodb = Mongo::Connection.new.db("mongo-lock-test")
  end

  config.before :each do
    $mongodb.collections.reject{|c| c.name.start_with?("system.")}.each(&:drop)
  end

  basic_includes = Module.new do
    def db ; $mongodb ; end
  end

  config.include basic_includes

end
