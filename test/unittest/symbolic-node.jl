module TestSymbolicNode
using MXNet
using Base.Test

using ..Main: mlp2, mlpchain, reldiff

################################################################################
# Test Implementations
################################################################################
function test_basic()
  info("SymbolicNode::basic")

  model = mlp2()
  @test mx.list_arguments(model) == [:data,:fc1_weight,:fc1_bias,:fc2_weight,:fc2_bias]
  @test mx.list_outputs(model) == [:fc2_output]
  @test mx.list_auxiliary_states(model) == Symbol[]
end

function test_chain()
  info("SymbolicNode::chain")

  model = mlpchain()
  @test mx.list_arguments(model) == [:data,:fc1_weight,:fc1_bias,:fc2_weight,:fc2_bias]
  @test mx.list_outputs(model) == [:fc2_output]
  @test mx.list_auxiliary_states(model) == Symbol[]

  let layerconfig = [20, 10, 6]
    model = @mx.chain mx.Variable(:data) =>
      mx.MLP(layerconfig, prefix=:magic_) =>
      mx.LinearRegressionOutput(mx.Variable(:label))

    @test mx.list_arguments(model) == [
      :data,
      :magic_fc1_weight, :magic_fc1_bias,
      :magic_fc2_weight, :magic_fc2_bias,
      :magic_fc3_weight, :magic_fc3_bias,
      :label]
  end
end

function test_internal()
  info("SymbolicNode::internal")

  data  = mx.Variable(:data)
  oldfc = mx.FullyConnected(data, name=:fc1, num_hidden=10)
  net1  = mx.FullyConnected(oldfc, name=:fc2, num_hidden=100)

  @test mx.list_arguments(net1) == [:data,:fc1_weight,:fc1_bias,:fc2_weight,:fc2_bias]

  internal = mx.get_internals(net1)
  fc1      = internal[:fc1_output]
  @test mx.list_arguments(fc1) == mx.list_arguments(oldfc)
end

function test_compose()
  info("SymbolicNode::compose")

  data = mx.Variable(:data)
  net1 = mx.FullyConnected(data, name=:fc1, num_hidden=10)
  net1 = mx.FullyConnected(net1, name=:fc2, num_hidden=100)

  net2 = mx.FullyConnected(mx.SymbolicNode, name=:fc3, num_hidden=10)
  net2 = mx.Activation(net2, act_type=:relu)
  net2 = mx.FullyConnected(net2, name=:fc4, num_hidden=20)

  composed  = net2(fc3_data=net1, name=:composed)
  multi_out = mx.Group(composed, net1)
  @test mx.list_outputs(multi_out) == [:composed_output, :fc2_output]
end

function test_infer_shape()
  info("SymbolicNode::infer_shape::mlp2")

  model = mlp2()
  data_shape = (100, 100)
  arg_shapes, out_shapes, aux_shapes = mx.infer_shape(model, data=data_shape)
  arg_shape_dict = Dict{Symbol,Tuple}(zip(mx.list_arguments(model), arg_shapes))
  @test arg_shape_dict == Dict{Symbol,Tuple}(:fc2_bias => (10,),:fc2_weight => (1000,10),
                                             :fc1_bias => (1000,), :fc1_weight => (100, 1000),
                                             :data => data_shape)
  @test length(out_shapes) == 1
  @test out_shapes[1] == (10, 100)
end

function test_infer_shape_error()
  info("SymbolicNode::infer_shape::throws")

  model = mlp2()
  weight_shape = (100, 1)
  data_shape   = (100, 100)
  @test_throws mx.MXError mx.infer_shape(model, data=data_shape, fc1_weight=weight_shape)
end

function test_saveload()
  info("SymbolicNode::saveload::mlp2")

  model = mlp2()
  fname = tempname()
  mx.save(fname, model)
  model2 = mx.load(fname, mx.SymbolicNode)
  @test mx.to_json(model) == mx.to_json(model2)

  rm(fname)
end

function test_attrs()
  info("SymbolicNode::Attributes")

  data = mx.Variable(:data)

  @test mx.get_name(data) == :data
  result = mx.get_attr(data, :test)
  @test isnull(result)
  mx.set_attr(data, :test, "1.0")
  result = mx.get_attr(data, :test)
  @test !isnull(result)
  @test get(result) == "1.0"

  data2 = mx.Variable(:data2, attrs = Dict(:test => "hallo!"))
  @test get(mx.get_attr(data2, :test)) == "hallo!"

  conv = mx.Convolution(data2, kernel = (1,1), num_filter = 1, attrs = Dict(:a => "a", :π => "π"))
  @test isnull(mx.get_attr(conv, :b))
  @test get(mx.get_attr(conv, :a)) == "a"
  @test get(mx.get_attr(conv, :π)) == "π"
  @test isa(mx.get_name(conv), Symbol)

  @test_throws MethodError mx.Variable(:data3, attrs = Dict(:test => "1.0", :test2 => 1.0))
  @test_throws MethodError mx.Convolution(data2, kernel = (1,1), num_filter = 1, attrs = Dict(:test => "1.0", :test2 => 1.0))
end

function test_functions()
  info("SymbolicNode::Functions")
  data = mx.Variable(:data)
  typeof(mx.sum(data)) == mx.SymbolicNode
end

function test_reshape()
  info("SymbolicNode::reshape(sym, dim...)")

  A = mx.NDArray(collect(1:24))
  x = mx.Variable(:x)
  y = mx.reshape(x, 2, 3, 4)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (2, 3, 4)
  @test copy(out) == reshape(1:24, 2, 3, 4)

  info("SymbolicNode::reshape(sym, dim)")

  A = mx.NDArray(collect(1:24))
  x = mx.Variable(:x)
  y = mx.reshape(x, (2, 3, 4))
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (2, 3, 4)
  @test copy(out) == reshape(1:24, 2, 3, 4)

  info("SymbolicNode::reshape::reverse")

  A = mx.zeros(10, 5, 4)
  x = mx.Variable(:x)
  y = mx.reshape(x, -1, 0, reverse=true)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (50, 4)

  info("SymbolicNode::reshape::0")

  A = mx.zeros(2, 3, 4)
  x = mx.Variable(:x)
  y = mx.reshape(x, 4, 0, 2)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (4, 3, 2)

  info("SymbolicNode::reshape::-1")

  A = mx.zeros(2, 3, 4)
  x = mx.Variable(:x)
  y = mx.reshape(x, 6, 1, -1)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (6, 1, 4)

  info("SymbolicNode::reshape::-2")

  A = mx.zeros(2, 3, 4, 2)
  x = mx.Variable(:x)
  y = mx.reshape(x, 3, 2, -2)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (3, 2, 4, 2)

  info("SymbolicNode::reshape::-3")

  A = mx.zeros(2, 3, 4, 5)
  x = mx.Variable(:x)
  y = mx.reshape(x, -3, -3)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (6, 20)

  info("SymbolicNode::reshape::-4")

  A = mx.zeros(2, 3, 4)
  x = mx.Variable(:x)
  y = mx.reshape(x, 0, 0, -4, 2, 2)
  e = mx.bind(y, mx.cpu(), Dict(:x => A))
  mx.forward(e)
  out = e.outputs[1]

  @test size(out) == (2, 3, 2, 2)
end

function test_dot()
  info("SymbolicNode::dot")
  x = mx.Variable(:x)
  y = mx.Variable(:y)
  z = mx.dot(x, y)
  z_exec = mx.bind(z, context=mx.cpu(),
                   args=Dict(:x=>mx.ones((100, 2)), :y=>mx.ones((2, 200))))
  mx.forward(z_exec)

  ret = copy(z_exec.outputs[1])
  @test size(ret) == (100, 200)
  @test reldiff(ret, 2*ones(100, 200)) < 1e-6
end

function test_print()
  info("SymbolicNode::print")
  io = IOBuffer()
  print(io, mx.Variable(:x))
  @test !isempty(String(take!(io)))
end

function test_misc()
  info("SymbolicNode::Miscellaneous")
  # Test for #189
  a = mx.Variable("a")
  b = mx.Variable("b")
  symb = mx.ElementWiseSum(a,b)
end

################################################################################
# Run tests
################################################################################
@testset "SymbolicNode Test" begin
  test_basic()
  test_chain()
  test_internal()
  test_compose()
  test_infer_shape()
  test_infer_shape_error()
  test_saveload()
  test_attrs()
  test_functions()
  test_reshape()
  test_dot()
  test_print()
  test_misc()
end

end
