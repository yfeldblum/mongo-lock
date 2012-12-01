require "bundler/setup"
require "optparse"
require "pathname"
require "ruby-prof"
require "mongo"

$printers = []
OptionParser.new do |opts|
  opts.on("--flat"){$printers << [:Flat, "flat.prof"]}
  opts.on("--call-stack-html"){$printers << [:CallStack, "callstack.html"]}
  opts.on("--call-tree"){$printers << [:CallTree, "calltree.prof"]}
  opts.on("--graph"){$printers << [:Graph, "graph.prof"]}
  opts.on("--graph-html"){$printers << [:GraphHtml, "graph.html"]}
  opts.on("--graph-dot"){$printers << [:Dot, "graph.dot"]}
end.parse!(ARGV)

$mongodb = Mongo::Connection.new.db("mongo-lock-test")
$mongodb.collections.reject{|c| c.name.start_with?("system.")}.each(&:drop)

def pausing_gc
  GC.start
  GC.disable
  yield
ensure
  GC.enable
end

def profile(name)
  result = pausing_gc{RubyProf.profile{yield}}
  dir = Pathname(__FILE__).dirname + "result" + name
  dir.rmtree if dir.exist?
  dir.mkpath
  $printers.each do |klass, fn|
    dir.join(fn).open("w+b") do |f|
      RubyProf.const_get("#{klass}Printer").new(result).print(f)
    end
  end
end
