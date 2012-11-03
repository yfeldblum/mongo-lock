#!/usr/bin/env ruby
require File.expand_path("../../profile_helper", __FILE__)
require "mongo/lock/mutex"

mutex = Mongo::Lock::Mutex.new($mongodb["mutexes"], "/users/6/settings")

profile "mutex/synchronize" do
  mutex.synchronize { }
end
