require "spec_helper"

describe InChildProcess do
  include InChildProcess

  in_child_process_jruby_pending

  it "returns the value" do
    expect( in_child_process{345} ).to be 345
  end

  it "raises the exception" do
    expect { in_child_process { raise StandardError, "hi there" } }
      .to raise_error StandardError, "hi there"
  end

  it "happens in another process" do
    x = [345]
    in_child_process { x[0] = 123 }
    expect(x).to be == [345]
  end

  it "requires a block" do
    expect { in_child_process }
      .to raise_error ArgumentError, "block not given"
  end

end
